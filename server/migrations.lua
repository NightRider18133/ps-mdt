-- Schema + index migrations. On resource start we:
--   1. detect the framework (qb-core vs qbx_core),
--   2. install the matching schema if `mdt_settings` doesn't exist yet,
--   3. apply hot-path indexes idempotently.
-- Every step is gated so re-runs are safe.

local resourceName = GetCurrentResourceName()

-- ---------------------------------------------------------------------------
-- Framework detection
-- ---------------------------------------------------------------------------

local function detectFramework()
    if GetResourceState('qbx_core') == 'started' then
        return 'qbx', 'sql/qbx.sql'
    end
    if GetResourceState('qb-core') == 'started' then
        return 'qb', 'sql/qbcore.sql'
    end
    -- Fall back to qb-core's schema if neither resource is detected yet
    -- (e.g. start order). It's the more common deployment.
    return nil, 'sql/qbcore.sql'
end

-- ---------------------------------------------------------------------------
-- Schema presence check
-- ---------------------------------------------------------------------------

local function tableExists(name)
    local row = MySQL.scalar.await(
        'SELECT 1 FROM information_schema.TABLES WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1',
        { name }
    )
    return row ~= nil
end

local function columnExists(table_, column)
    local row = MySQL.scalar.await(
        'SELECT 1 FROM information_schema.COLUMNS WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? LIMIT 1',
        { table_, column }
    )
    return row ~= nil
end

local function indexExists(table_, name)
    local row = MySQL.scalar.await(
        'SELECT 1 FROM information_schema.STATISTICS WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ? LIMIT 1',
        { table_, name }
    )
    return row ~= nil
end

-- ---------------------------------------------------------------------------
-- SQL splitter
--
-- oxmysql executes one statement per query, so we have to split the schema
-- file ourselves. The splitter respects:
--   * '--' line comments and /* */ block comments
--   * single-quoted strings (with backslash escapes)
--   * double-quoted strings and backtick identifiers
--   * `DELIMITER //` directives so trigger bodies stay in one piece
-- ---------------------------------------------------------------------------

local function splitStatements(sql)
    local statements = {}
    local buf = {}
    local delimiter = ';'
    local i, n = 1, #sql

    local function flush()
        local stmt = table.concat(buf)
        stmt = stmt:gsub('^%s+', ''):gsub('%s+$', '')
        if #stmt > 0 then statements[#statements + 1] = stmt end
        buf = {}
    end

    -- True when `i` is at the start of a logical line (newline or BOF).
    local function atLineStart()
        if i == 1 then return true end
        local prev = sql:sub(i - 1, i - 1)
        return prev == '\n' or prev == '\r'
    end

    while i <= n do
        local c = sql:sub(i, i)
        local c2 = sql:sub(i, i + 1)

        -- DELIMITER directive: only valid at the start of a line.
        if atLineStart() and sql:sub(i, i + 9):upper() == 'DELIMITER ' then
            flush()
            local lineEnd = sql:find('[\r\n]', i) or (n + 1)
            local newDelim = sql:sub(i + 10, lineEnd - 1):gsub('^%s+', ''):gsub('%s+$', '')
            if #newDelim > 0 then delimiter = newDelim end
            i = lineEnd + 1

        -- Line comment
        elseif c2 == '--' then
            local lineEnd = sql:find('[\r\n]', i) or (n + 1)
            i = lineEnd

        -- Block comment
        elseif c2 == '/*' then
            local closeAt = sql:find('*/', i + 2, true)
            i = closeAt and (closeAt + 2) or (n + 1)

        -- Single-quoted string
        elseif c == "'" then
            buf[#buf + 1] = c
            i = i + 1
            while i <= n do
                local ch = sql:sub(i, i)
                buf[#buf + 1] = ch
                if ch == '\\' and i < n then
                    buf[#buf + 1] = sql:sub(i + 1, i + 1)
                    i = i + 2
                elseif ch == "'" then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end

        -- Double-quoted string
        elseif c == '"' then
            buf[#buf + 1] = c
            i = i + 1
            while i <= n do
                local ch = sql:sub(i, i)
                buf[#buf + 1] = ch
                i = i + 1
                if ch == '"' then break end
            end

        -- Backtick identifier
        elseif c == '`' then
            buf[#buf + 1] = c
            i = i + 1
            while i <= n do
                local ch = sql:sub(i, i)
                buf[#buf + 1] = ch
                i = i + 1
                if ch == '`' then break end
            end

        -- Statement terminator
        elseif sql:sub(i, i + #delimiter - 1) == delimiter then
            flush()
            i = i + #delimiter

        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end

    flush()
    return statements
end

-- ---------------------------------------------------------------------------
-- Schema installer
-- ---------------------------------------------------------------------------

-- Statements that fail noisily on re-run are safe to ignore.  CREATE TRIGGER
-- has no IF NOT EXISTS variant, INSERT may hit duplicate keys on unguarded
-- inserts, etc.  These error fragments are filtered out of the warning log.
local IGNORABLE_ERROR_FRAGMENTS = {
    'already exists',
    'Duplicate column',
    'Duplicate key',
    'Duplicate entry',
    'Trigger already exists',
}

local function isIgnorableError(err)
    err = tostring(err or '')
    for _, frag in ipairs(IGNORABLE_ERROR_FRAGMENTS) do
        if err:find(frag, 1, true) then return true end
    end
    return false
end

-- Strip CREATE TRIGGER blocks AND the SET @OLDTMP_SQL_MODE / SET SQL_MODE
-- pair that wraps them. The SET statements rely on a session variable that
-- doesn't survive the per-statement isolation oxmysql gives us, so they
-- always fail with "can't be set to NULL". Triggers themselves can't be
-- re-run because CREATE TRIGGER has no IF NOT EXISTS form.
local function stripTriggers(statements)
    local out = {}
    for _, stmt in ipairs(statements) do
        local trimmed = stmt:gsub('^%s+', ''):upper()
        if not trimmed:find('^CREATE%s+TRIGGER')
           and not trimmed:find('^CREATE%s+DEFINER')
           and not trimmed:find('^SET%s+@OLDTMP_SQL_MODE')
           and not trimmed:find('^SET%s+SQL_MODE%s*=%s*@OLDTMP_SQL_MODE')
        then
            out[#out + 1] = stmt
        end
    end
    return out
end

-- Strip FOREIGN KEY constraints from CREATE TABLE statements.
--
-- Older installs often have `mdt_profiles.citizenid` with a different
-- collation than the new tables expect, which trips errno 150 ("Foreign
-- key constraint is incorrectly formed"). SET FOREIGN_KEY_CHECKS=0 doesn't
-- help reliably because oxmysql pools connections and the SET may not
-- propagate to the CREATE TABLE call. The pragmatic fix is to drop the
-- FK constraints from the schema we apply — the application doesn't rely
-- on cascade behaviour for any of these references.
local function stripForeignKeys(stmt)
    if not stmt:upper():find('CREATE%s+TABLE') then return stmt end

    -- Remove `CONSTRAINT `name` FOREIGN KEY ... ON DELETE/UPDATE ...,`
    -- (multiline). We match up to the next comma OR the closing paren of
    -- the column list, whichever comes first.
    stmt = stmt:gsub('CONSTRAINT%s+`[^`]+`%s+FOREIGN%s+KEY[^,]-ON%s+UPDATE%s+%w+%s*,', '')
    stmt = stmt:gsub('CONSTRAINT%s+`[^`]+`%s+FOREIGN%s+KEY[^,]-ON%s+UPDATE%s+%w+%s*', '')
    stmt = stmt:gsub('CONSTRAINT%s+`[^`]+`%s+FOREIGN%s+KEY[^,)]+,', '')
    stmt = stmt:gsub('CONSTRAINT%s+`[^`]+`%s+FOREIGN%s+KEY[^,)]+', '')

    -- A trailing comma may now sit just before the closing paren — fix that.
    stmt = stmt:gsub(',(%s*%))', '%1')
    return stmt
end

local function installSchema(framework, sqlFile, opts)
    opts = opts or {}
    local sql = LoadResourceFile(resourceName, sqlFile)
    if not sql or #sql == 0 then
        ps.warn(('[migrations] could not read %s — skipping schema install'):format(sqlFile))
        return false
    end

    local statements = splitStatements(sql)
    if #statements == 0 then
        ps.warn('[migrations] schema file produced no statements — aborting install')
        return false
    end

    -- On re-run we skip CREATE TRIGGER blocks (they'd error since they don't
    -- support IF NOT EXISTS) and rely on the existing triggers staying valid.
    -- Triggers are only created on the very first install.
    if opts.skipTriggers then
        statements = stripTriggers(statements)
    end

    print(('^3[ps-mdt]^7 %s schema (%s, %d statements)…'):format(
        opts.label or 'installing', framework or 'unknown', #statements
    ))

    -- Drop foreign-key enforcement for the duration of the install.  Some
    -- legacy installs have `mdt_profiles.citizenid` with a different
    -- collation than the new tables expect, which causes errno 150
    -- ("Foreign key constraint is incorrectly formed") even though the
    -- referenced column exists.  The constraints are re-armed after.
    pcall(MySQL.query.await, 'SET FOREIGN_KEY_CHECKS = 0')

    local applied, failed, ignored = 0, 0, 0
    for _, stmt in ipairs(statements) do
        local cleaned = stripForeignKeys(stmt)
        local ok, err = pcall(MySQL.query.await, cleaned)
        if ok then
            applied = applied + 1
        elseif isIgnorableError(err) then
            ignored = ignored + 1
        else
            failed = failed + 1
            ps.warn(('[migrations] statement failed: %s\n  -> %s'):format(
                cleaned:sub(1, 120):gsub('%s+', ' '),
                tostring(err)
            ))
        end
    end

    pcall(MySQL.query.await, 'SET FOREIGN_KEY_CHECKS = 1')

    print(('^2[ps-mdt]^7 schema pass: %d applied, %d already-present, %d failed'):format(
        applied, ignored, failed
    ))
    return failed == 0
end

-- ---------------------------------------------------------------------------
-- Column-level migrations for known additions to existing tables.  The
-- schema file's CREATE TABLE IF NOT EXISTS only creates new tables; existing
-- tables left over from older ps-mdt versions need explicit ADD COLUMN.
-- ---------------------------------------------------------------------------

local COLUMN_MIGRATIONS = {
    { table = 'mdt_profiles',  column = 'fullname',       type = 'varchar(60) DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'profilepicture', type = 'text DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'callsign',       type = 'varchar(15) DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'badge_number',   type = 'varchar(20) DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'rank',           type = 'varchar(40) DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'department',     type = 'varchar(40) DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'notes',          type = 'text DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'certifications', type = 'text DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'last_login_at',  type = 'timestamp NULL DEFAULT NULL' },
    { table = 'mdt_profiles',  column = 'last_logout_at', type = 'timestamp NULL DEFAULT NULL' },

    { table = 'mdt_weapons',   column = 'serial',         type = "varchar(60) NOT NULL DEFAULT ''" },
    { table = 'mdt_weapons',   column = 'scratched',      type = 'tinyint(1) NOT NULL DEFAULT 0' },
    { table = 'mdt_weapons',   column = 'owner',          type = 'varchar(60) DEFAULT NULL' },
    { table = 'mdt_weapons',   column = 'information',    type = 'text DEFAULT NULL' },
    { table = 'mdt_weapons',   column = 'weaponClass',    type = 'int(11) DEFAULT 1' },
    { table = 'mdt_weapons',   column = 'weaponModel',    type = 'varchar(60) DEFAULT NULL' },

    { table = 'mdt_bolos',     column = 'image',          type = 'text DEFAULT NULL' },
    { table = 'mdt_bolos',     column = 'subject_name',   type = 'varchar(120) DEFAULT NULL' },
    { table = 'mdt_bolos',     column = 'reportId',       type = 'int(10) unsigned DEFAULT NULL' },

    { table = 'player_vehicles', column = 'mdt_vehicle_information', type = 'text DEFAULT NULL' },
    { table = 'player_vehicles', column = 'mdt_vehicle_points',      type = 'int(10) DEFAULT 0' },
    { table = 'player_vehicles', column = 'mdt_vehicle_status',      type = "varchar(20) DEFAULT 'valid'" },
    { table = 'player_vehicles', column = 'mdt_vehicle_stolen',      type = 'tinyint(1) DEFAULT 0' },
    { table = 'player_vehicles', column = 'mdt_vehicle_boloactive',  type = 'tinyint(1) DEFAULT 0' },
    { table = 'player_vehicles', column = 'mdt_vehicle_image',       type = 'text DEFAULT NULL' },

    -- mdt_cameras / mdt_tags were restructured in newer ps-mdt versions; older
    -- installs are missing the discriminator columns we now query against.
    { table = 'mdt_cameras',   column = 'cam_id',         type = "varchar(60) NOT NULL DEFAULT ''" },
    { table = 'mdt_cameras',   column = 'cam_label',      type = 'varchar(120) DEFAULT NULL' },
    { table = 'mdt_cameras',   column = 'cam_type',       type = "varchar(40) DEFAULT 'store'" },
    { table = 'mdt_cameras',   column = 'coords',         type = 'text DEFAULT NULL' },
    { table = 'mdt_cameras',   column = 'rotation',       type = 'text DEFAULT NULL' },
    { table = 'mdt_cameras',   column = 'image',          type = 'text DEFAULT NULL' },
    { table = 'mdt_cameras',   column = 'can_rotate',     type = 'tinyint(1) DEFAULT 1' },
    { table = 'mdt_cameras',   column = 'is_online',      type = 'tinyint(1) DEFAULT 1' },
    { table = 'mdt_cameras',   column = 'spawns_model',   type = 'tinyint(1) DEFAULT 0' },
    { table = 'mdt_cameras',   column = 'created_by',     type = "varchar(60) DEFAULT 'SYSTEM'" },

    { table = 'mdt_tags',      column = 'name',           type = 'varchar(60) DEFAULT NULL' },
    { table = 'mdt_tags',      column = 'type',           type = "varchar(20) DEFAULT 'officer'" },
    { table = 'mdt_tags',      column = 'color',          type = "varchar(20) DEFAULT '#3b82f6'" },
    { table = 'mdt_tags',      column = 'job_type',       type = "varchar(20) DEFAULT 'leo'" },
}

local function runColumnMigrations()
    local added, skipped = 0, 0
    for _, mig in ipairs(COLUMN_MIGRATIONS) do
        if not tableExists(mig.table) then
            skipped = skipped + 1
        elseif columnExists(mig.table, mig.column) then
            skipped = skipped + 1
        else
            local ddl = ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(
                mig.table, mig.column, mig.type
            )
            local ok, err = pcall(MySQL.query.await, ddl)
            if ok then
                added = added + 1
                ps.debug(('[migrations] added column %s.%s'):format(mig.table, mig.column))
            else
                ps.warn(('[migrations] could not add column %s.%s: %s'):format(
                    mig.table, mig.column, tostring(err)
                ))
            end
        end
    end
    if added > 0 then
        print(('^2[ps-mdt]^7 added %d missing columns to existing tables'):format(added))
    end
end

-- ---------------------------------------------------------------------------
-- Index migration (always runs)
-- ---------------------------------------------------------------------------

local INDEXES = {
    -- player_vehicles is owned by qb-core but is the hottest table the MDT
    -- touches: vehicle list, search, plate lookups, owner counts.
    { table = 'player_vehicles',     name = 'idx_pv_plate',           columns = '`plate`'              },
    { table = 'player_vehicles',     name = 'idx_pv_citizenid',       columns = '`citizenid`'          },
    { table = 'player_vehicles',     name = 'idx_pv_vehicle',         columns = '`vehicle`'            },

    { table = 'player_houses',       name = 'idx_ph_citizenid',       columns = '`citizenid`'          },

    -- BOLO joins on (type, status, subject_id) on every vehicle/weapon/citizen
    -- list open. Composite indexes give us index-only access for the batch
    -- lookups in the new vehicles/weapons code paths.
    { table = 'mdt_bolos',           name = 'idx_bolos_type_status',  columns = '`type`,`status`'      },
    { table = 'mdt_bolos',           name = 'idx_bolos_type_subject', columns = '`type`,`subject_id`'  },

    { table = 'mdt_report_vehicles', name = 'idx_rv_plate_report',    columns = '`plate`,`reportid`'   },

    { table = 'mdt_audit_logs',      name = 'idx_audit_actor_time',   columns = '`actor_citizenid`,`created_at`' },
    { table = 'mdt_audit_logs',      name = 'idx_audit_action_time',  columns = '`action`,`created_at`' },
}

local function runIndexMigration()
    local created, skipped, missing = 0, 0, 0
    for _, idx in ipairs(INDEXES) do
        if not tableExists(idx.table) then
            missing = missing + 1
        elseif indexExists(idx.table, idx.name) then
            skipped = skipped + 1
        else
            local ddl = ('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(idx.table, idx.name, idx.columns)
            local ok, err = pcall(MySQL.query.await, ddl)
            if ok then
                created = created + 1
                ps.debug(('[migrations] created index %s on %s'):format(idx.name, idx.table))
            else
                ps.warn(('[migrations] failed to create index %s on %s: %s'):format(idx.name, idx.table, tostring(err)))
            end
        end
    end

    if created > 0 then
        print(('^2[ps-mdt]^7 added %d new database indexes (%d already present, %d skipped — table missing)'):format(
            created, skipped, missing
        ))
    end
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- A handful of tables we expect to always exist after a successful install.
-- If any one of them is missing we know the schema is incomplete and re-run
-- the file (CREATE TABLE IF NOT EXISTS makes this safe).
local CRITICAL_TABLES = {
    'mdt_settings', 'mdt_profiles', 'mdt_reports', 'mdt_reports_warrants',
    'mdt_reports_charges', 'mdt_arrests', 'mdt_cases', 'mdt_case_officers',
    'mdt_evidence_items', 'mdt_bolos', 'mdt_weapons', 'mdt_audit_logs',
}

local function schemaIsComplete()
    for _, name in ipairs(CRITICAL_TABLES) do
        if not tableExists(name) then return false, name end
    end
    return true
end

-- Tables whose seed data lives inside the schema file. If any are empty
-- after the column backfill, re-run the schema in repair mode so the
-- INSERT IGNORE statements get a chance to populate them. Without this,
-- a partial migration where the seed INSERTs failed (e.g. column missing
-- at the time) would leave these tables empty forever.
local SEEDED_TABLES = { 'mdt_cameras', 'mdt_tags', 'mdt_penal_codes' }

local function rowCount(name)
    if not tableExists(name) then return 0 end
    return tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(name))) or 0
end

local function seedDataMissing()
    for _, name in ipairs(SEEDED_TABLES) do
        if rowCount(name) == 0 then return true, name end
    end
    return false
end

local function run()
    local framework, sqlFile = detectFramework()
    local freshInstall = not tableExists('mdt_settings')

    -- Backfill columns BEFORE running the schema, otherwise the seed-data
    -- INSERTs (mdt_cameras, mdt_tags) inside the schema file fail because
    -- they reference columns we haven't added yet to the legacy tables.
    -- On a fresh install this is a no-op (tables don't exist yet).
    if not freshInstall then
        runColumnMigrations()
    end

    if freshInstall then
        installSchema(framework, sqlFile, { label = 'installing' })
        -- Run column migrations again post-install in case the freshly-
        -- created tables are missing newer columns added since the schema
        -- file was written. Cheap idempotent pass.
        runColumnMigrations()
    else
        -- Existing install: re-run the schema in repair mode if either:
        --   (a) a critical table is missing, or
        --   (b) a seeded table (cameras / tags / penal codes) is empty —
        --       the INSERT IGNORE statements in the schema file are the
        --       canonical source of seed data, and on a previous failed
        --       migration they may have errored out before columns existed.
        local complete, missing = schemaIsComplete()
        local seedsMissing, emptyTable = seedDataMissing()

        if not complete then
            print(('^3[ps-mdt]^7 schema incomplete (missing `%s`) — running repair pass'):format(missing))
            installSchema(framework, sqlFile, { label = 'repairing', skipTriggers = true })
            runColumnMigrations()
        elseif seedsMissing then
            print(('^3[ps-mdt]^7 seed table `%s` is empty — re-running schema to backfill'):format(emptyTable))
            installSchema(framework, sqlFile, { label = 'reseeding', skipTriggers = true })
        end
    end

    runIndexMigration()

    -- cameras.lua loads its in-memory list 1s after resource start; we run
    -- ~2s after start so on first install the camera load races ahead of the
    -- INSERT IGNORE seed data and ends up with zero entries. Reload now that
    -- the seed rows exist.
    if Camera and Camera.loadAllFromDatabase then
        local ok, err = pcall(Camera.loadAllFromDatabase)
        if ok then
            ps.debug('[migrations] reloaded cameras after schema install')
        else
            ps.warn('[migrations] camera reload failed: ' .. tostring(err))
        end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= resourceName then return end
    -- Defer slightly so oxmysql is fully ready and shared scripts have loaded.
    SetTimeout(2000, function()
        local ok, err = pcall(run)
        if not ok then
            ps.warn('[migrations] migration failed: ' .. tostring(err))
        end
    end)
end)
