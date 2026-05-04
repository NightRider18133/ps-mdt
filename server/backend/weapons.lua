
local resourceName = tostring(GetCurrentResourceName())

local class = {
    -- pistol
    weapon_pistol                ={type = 'pistol', class  = 1},
	weapon_pistol_mk2            ={type = 'pistol', class  = 1},
	weapon_combatpistol          ={type = 'pistol', class  = 1},
	weapon_appistol              ={type = 'pistol', class  = 1},
	weapon_stungun               ={type = 'pistol', class  = 1},
	weapon_pistol50              ={type = 'pistol', class  = 1},
	weapon_snspistol             ={type = 'pistol', class  = 1},
	weapon_snspistol_mk2         ={type = 'pistol', class  = 1},
	weapon_heavypistol           ={type = 'pistol', class  = 1},
	weapon_vintagepistol         ={type = 'pistol', class  = 1},
	weapon_flaregun              ={type = 'pistol', class  = 1},
	weapon_marksmanpistol        ={type = 'pistol', class  = 1},
	weapon_revolver              ={type = 'pistol', class  = 1},
	weapon_revolver_mk2          ={type = 'pistol', class  = 1},
	weapon_doubleaction          ={type = 'pistol', class  = 1},
	weapon_raypistol             ={type = 'pistol', class  = 1},
	weapon_ceramicpistol         ={type = 'pistol', class  = 1},
	weapon_navyrevolver          ={type = 'pistol', class  = 1},
	weapon_gadgetpistol          ={type = 'pistol', class  = 1},
	weapon_stungun_mp            ={type = 'pistol', class  = 1},
	weapon_pistolxm3             ={type = 'pistol', class  = 1},
    -- SMG
    weapon_microsmg              ={type = 'smg', class  = 2},
	weapon_smg                   ={type = 'smg', class  = 2},
	weapon_smg_mk2               ={type = 'smg', class  = 2},
	weapon_assaultsmg            ={type = 'smg', class  = 2},
	weapon_combatpdw             ={type = 'smg', class  = 2},
	weapon_machinepistol         ={type = 'smg', class  = 2},
	weapon_minismg               ={type = 'smg', class  = 2},
	weapon_raycarbine            ={type = 'smg', class  = 2},
    -- shotguns
    weapon_pumpshotgun           ={type = 'shotgun', class  = 3},
	weapon_pumpshotgun_mk2       ={type = 'shotgun', class  = 3},
	weapon_sawnoffshotgun        ={type = 'shotgun', class  = 3},
	weapon_assaultshotgun        ={type = 'shotgun', class  = 3},
	weapon_bullpupshotgun        ={type = 'shotgun', class  = 3},
	weapon_musket                ={type = 'shotgun', class  = 3},
	weapon_heavyshotgun          ={type = 'shotgun', class  = 3},
	weapon_dbshotgun             ={type = 'shotgun', class  = 3},
	weapon_autoshotgun           ={type = 'shotgun', class  = 3},
	weapon_combatshotgun         ={type = 'shotgun', class  = 3},
    -- assault rifles
    weapon_assaultrifle          ={type = 'assault', class  = 4},
	weapon_assaultrifle_mk2      ={type = 'assault', class  = 4},
	weapon_carbinerifle          ={type = 'assault', class  = 4},
	weapon_carbinerifle_mk2      ={type = 'assault', class  = 4},
	weapon_advancedrifle         ={type = 'assault', class  = 4},
	weapon_specialcarbine        ={type = 'assault', class  = 4},
	weapon_specialcarbine_mk2   = {type = 'assault', class  = 4},
	weapon_bullpuprifle         = {type = 'assault', class  = 4},
	weapon_bullpuprifle_mk2     = {type = 'assault', class  = 4},
	weapon_compactrifle         = {type = 'assault', class  = 4},
	weapon_militaryrifle        = {type = 'assault', class  = 4},
	weapon_heavyrifle           = {type = 'assault', class  = 4},
    -- light machine guns
    weapon_mg                    ={type = 'lmg', class  = 5},
    weapon_combatmg              ={type = 'lmg', class  = 5},
    weapon_combatmg_mk2          ={type = 'lmg', class  = 5},
    weapon_gusenberg             ={type = 'lmg', class  = 5},
    --- sniper rifles
    weapon_sniperrifle           ={type = 'sniper', class  = 6},
    weapon_heavysniper           ={type = 'sniper', class  = 6},
    weapon_heavysniper_mk2       ={type = 'sniper', class  = 6},
    weapon_marksmanrifle         ={type = 'sniper', class  = 6},
    weapon_marksmanrifle_mk2     ={type = 'sniper', class  = 6},
    weapon_precisionrifle        ={type = 'sniper', class  = 6},
    -- heavy
    weapon_rpg                   ={type = 'heavy', class  = 7},
    weapon_grenadelauncher       ={type = 'heavy', class  = 7},
    weapon_grenadelauncher_smoke ={type = 'heavy', class  = 7},
    weapon_minigun               ={type = 'heavy', class  = 7},
    weapon_firework              ={type = 'heavy', class  = 7},
    weapon_railgun               ={type = 'heavy', class  = 7},
    weapon_hominglauncher        ={type = 'heavy', class  = 7},
    weapon_compactlauncher       ={type = 'heavy', class  = 7},
    weapon_rayminigun            ={type = 'heavy', class  = 7},
}
local okQB, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
if not okQB then QBCore = nil end
local function registerWeapon(citizenid, weaponName, serial, info)
    -- Ensure profile exists so owner name can be resolved later
    if citizenid and citizenid ~= '' then
        EnsureProfileExists(citizenid)
    end

    -- Normalize weapon model to lowercase for class table lookup
    local modelLower = weaponName and string.lower(weaponName) or ''
    local weaponClass = class[modelLower] and class[modelLower].class or 1

    MySQL.query.await('INSERT INTO mdt_weapons (serial, scratched, owner, information, weaponClass, weaponModel) VALUES (?, ?, ?, ?, ?, ?)', {
        serial, false, citizenid, info or '', weaponClass, weaponName
    })
    MySQL.insert.await([[
        INSERT INTO mdt_weapon_ownership_history (serial, owner, weapon_model, weapon_class, information, changed_by, reason)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        serial,
        citizenid,
        weaponName,
        weaponClass,
        info or '',
        citizenid,
        'register'
    })
end

exports('registerWeapon', registerWeapon)

-- Look up a weapon's display label safely. GetHashKey crashes on nil, and
-- legacy rows may have NULL weaponModel (the column was added later), so
-- guard the lookup explicitly.
local function resolveWeaponLabel(weaponModel)
    if not weaponModel or weaponModel == '' then return 'Unknown' end
    if QBCore and QBCore.Shared and QBCore.Shared.Weapons then
        local entry = QBCore.Shared.Weapons[GetHashKey(weaponModel)]
        if entry and entry.label then return entry.label end
    end
    return weaponModel
end

-- Resolve owner display names for a list of citizen IDs in a single query.
-- Falls back to ps.getPlayerNameByIdentifier for IDs that have no profile row.
local function resolveOwnerNames(citizenids)
    local out = {}
    if not citizenids or #citizenids == 0 then return out end

    local seen = {}
    local unique = {}
    for i = 1, #citizenids do
        local cid = citizenids[i]
        if cid and cid ~= '' and not seen[cid] then
            seen[cid] = true
            unique[#unique + 1] = cid
        end
    end
    if #unique == 0 then return out end

    local placeholders = (string.rep('?,', #unique)):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT citizenid, fullname FROM mdt_profiles WHERE citizenid IN (%s)'):format(placeholders),
        unique
    ) or {}
    for _, row in ipairs(rows) do
        if row.fullname and row.fullname ~= '' then
            out[row.citizenid] = row.fullname
        end
    end

    -- Fall back for any unique cid that had no profile row.
    for _, cid in ipairs(unique) do
        if not out[cid] then
            out[cid] = ps.getPlayerNameByIdentifier(cid) or 'Unknown'
        end
    end
    return out
end

local function rowToWeapon(v, ownerNames)
    local modelLower = v.weaponModel and string.lower(v.weaponModel) or ''
    local ownerName = (v.owner and v.owner ~= '' and ownerNames[v.owner]) or 'Unknown'
    return {
        id = v.id,
        serial = v.serial,
        scratched = v.scratched == 1,
        owner = ownerName,
        information = v.information,
        weaponClass = v.weaponClass,
        weaponModel = v.weaponModel,
        name = resolveWeaponLabel(v.weaponModel),
        image = v.weaponModel
            and ('https://docs.fivem.net/weapons/' .. v.weaponModel:upper() .. '.png')
            or '',
        type = class[modelLower] and class[modelLower].type or 'unknown',
    }
end

local WEAPON_LIST_COLUMNS = 'id, serial, scratched, owner, information, weaponClass, weaponModel'

ps.registerCallback('ps-mdt:server:getWeapons', function(source, payload)
    local startTime = os.clock()
    if not CheckAuth(source) then return { weapons = {}, bolos = {}, total = 0 } end

    payload = type(payload) == 'table' and payload or {}
    local page = math.max(1, tonumber(payload.page) or 1)
    local limit = Config.Pagination and Config.Pagination.Weapons or 50
    if payload.perPage then
        local pp = tonumber(payload.perPage) or limit
        limit = math.max(10, math.min(pp, 200))
    end
    local offset = (page - 1) * limit

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM mdt_weapons') or 0

    local weapons = MySQL.query.await(
        ('SELECT %s FROM mdt_weapons ORDER BY id DESC LIMIT ? OFFSET ?'):format(WEAPON_LIST_COLUMNS),
        { limit, offset }
    ) or {}

    local cids = {}
    for i = 1, #weapons do
        cids[#cids + 1] = weapons[i].owner
    end
    local ownerNames = resolveOwnerNames(cids)

    local newData = {}
    for _, v in ipairs(weapons) do
        newData[#newData + 1] = rowToWeapon(v, ownerNames)
    end

    local weaponBolos = MySQL.query.await(
        'SELECT id, reportId, subject_id, subject_name, type, notes, status FROM mdt_bolos WHERE type = ? AND status = ? ORDER BY id DESC LIMIT 200',
        { 'weapon', 'active' }
    ) or {}
    local weaponBolo = {}
    for _, v in ipairs(weaponBolos) do
        weaponBolo[#weaponBolo + 1] = {
            id = v.id,
            reportId = v.reportId and tostring(v.reportId) or 'N/A',
            name = v.subject_name or 'Unknown Weapon',
            type = v.type,
            notes = v.notes or '',
            status = v.status,
            serial = v.subject_id or 'Unknown',
        }
    end

    local elapsed = (os.clock() - startTime) * 1000
    ps.debug(string.format("getWeapons callback executed in %.2f ms (page %d, %d rows)", elapsed, page, #newData))

    return {
        weapons = newData,
        bolos = weaponBolo,
        page = page,
        perPage = limit,
        total = tonumber(total) or 0,
    }
end)

ps.registerCallback('ps-mdt:server:searchWeapons', function(source, payload)
    if not CheckAuth(source) then return { weapons = {}, total = 0 } end

    payload = type(payload) == 'table' and payload or {}
    local query = payload.query
    if type(query) ~= 'string' or #query < 2 then
        return { weapons = {}, total = 0 }
    end

    local limit = Config.Pagination and Config.Pagination.WeaponSearch or 50
    local needle = '%' .. string.lower(query) .. '%'

    if ps.auditLog then
        ps.auditLog(source, 'search_weapons', 'search', nil, { query = query })
    end

    local rows = MySQL.query.await(([[
        SELECT %s
        FROM mdt_weapons
        WHERE LOWER(serial) LIKE ?
           OR LOWER(weaponModel) LIKE ?
           OR LOWER(owner) LIKE ?
        ORDER BY id DESC
        LIMIT ?
    ]]):format(WEAPON_LIST_COLUMNS), { needle, needle, needle, limit }) or {}

    local cids = {}
    for i = 1, #rows do
        cids[#cids + 1] = rows[i].owner
    end
    local ownerNames = resolveOwnerNames(cids)

    local out = {}
    for _, v in ipairs(rows) do
        out[#out + 1] = rowToWeapon(v, ownerNames)
    end

    return { weapons = out, total = #out, page = 1, perPage = limit }
end)

ps.registerCallback(resourceName .. ':server:getWeaponOwnershipHistory', function(source, serial)
    local src = source
    if not CheckAuth(src) then return end
    if not serial or serial == '' then return {} end

    local rows = MySQL.query.await([[
        SELECT id, serial, owner, weapon_model, weapon_class, information, changed_by, reason, created_at
        FROM mdt_weapon_ownership_history
        WHERE serial = ?
        ORDER BY created_at DESC
    ]], { serial })
    return rows or {}
end)

-- Save/Edit Weapon Info (from NUI)
ps.registerCallback(resourceName .. ':server:saveWeaponInfo', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local serial = payload.serial
    local notes = payload.notes or ''
    local imageurl = payload.imageurl or ''
    local owner = payload.owner or ''
    local weapClass = tonumber(payload.weapClass) or 1
    local weapModel = payload.weapModel or ''

    if not serial or serial == '' then
        return { success = false, message = 'Missing serial number' }
    end

    local existing = MySQL.single.await('SELECT id FROM mdt_weapons WHERE serial = ? LIMIT 1', { serial })

    if existing then
        MySQL.update.await([[
            UPDATE mdt_weapons
            SET information = ?, owner = ?, weaponClass = ?, weaponModel = ?
            WHERE serial = ?
        ]], { notes, owner, weapClass, weapModel, serial })
    else
        MySQL.insert.await([[
            INSERT INTO mdt_weapons (serial, scratched, owner, information, weaponClass, weaponModel)
            VALUES (?, 0, ?, ?, ?, ?)
        ]], { serial, owner, notes, weapClass, weapModel })

        MySQL.insert.await([[
            INSERT INTO mdt_weapon_ownership_history (serial, owner, weapon_model, weapon_class, information, changed_by, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { serial, owner, weapModel, weapClass, notes, ps.getIdentifier(src), 'manual_entry' })
    end

    if ps.auditLog then
        ps.auditLog(src, existing and 'weapon_updated' or 'weapon_created', 'weapon', serial, {
            owner = owner,
            model = weapModel,
        })
    end

    return { success = true, message = existing and 'Weapon info updated' or 'Weapon info created' }
end)

-- Delete Weapon Record
ps.registerCallback(resourceName .. ':server:deleteWeapon', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local id = tonumber(payload.id)
    local serial = payload.serial

    if not id and not serial then
        return { success = false, message = 'Missing weapon ID or serial' }
    end

    local deleted = 0
    if id then
        local wep = MySQL.single.await('SELECT serial FROM mdt_weapons WHERE id = ?', { id })
        serial = wep and wep.serial or serial
        deleted = MySQL.update.await('DELETE FROM mdt_weapons WHERE id = ?', { id })
    elseif serial then
        deleted = MySQL.update.await('DELETE FROM mdt_weapons WHERE serial = ?', { serial })
    end

    if deleted and deleted > 0 and ps.auditLog then
        ps.auditLog(src, 'weapon_deleted', 'weapon', serial or tostring(id), {})
    end

    return { success = deleted and deleted > 0, message = deleted > 0 and 'Weapon deleted' or 'Weapon not found' }
end)

-- Scan player inventory for weapons (for self-register)
ps.registerCallback(resourceName .. ':server:getWeaponInfo', function(source)
    local src = source
    if not QBCore then return {} end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return {} end

    local weaponInfos = {}

    if GetResourceState('ox_inventory') == 'started' then
        local success, inv = pcall(function()
            return exports.ox_inventory:GetInventoryItems(src)
        end)
        if success and inv then
            for _, item in pairs(inv) do
                if item.name and string.find(item.name, 'WEAPON_') then
                    local invImage = ('https://cfx-nui-ox_inventory/web/images/%s.png'):format(item.name)
                    weaponInfos[#weaponInfos + 1] = {
                        serialnumber = item.metadata and item.metadata.serial or 'Unknown',
                        owner = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                        weaponmodel = (QBCore.Shared.Items[string.lower(item.name)] and QBCore.Shared.Items[string.lower(item.name)].label) or item.name,
                        weaponurl = invImage,
                        notes = 'Self Registered',
                        weapClass = 1,
                    }
                end
            end
        end
    else
        if Player.PlayerData.items then
            for _, item in pairs(Player.PlayerData.items) do
                if item.type == 'weapon' then
                    weaponInfos[#weaponInfos + 1] = {
                        serialnumber = item.info and item.info.serie or 'Unknown',
                        owner = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                        weaponmodel = (QBCore.Shared.Items[item.name] and QBCore.Shared.Items[item.name].label) or item.name,
                        weaponurl = item.image or '',
                        notes = 'Self Registered',
                        weapClass = 1,
                    }
                end
            end
        end
    end

    return weaponInfos
end)

-- ox_inventory weapon auto-registration hooks
CreateThread(function()
    Wait(2000)

    if GetResourceState('ox_inventory') ~= 'started' then return end
    if not Config.RegisterWeaponsAutomatically then return end

    exports.ox_inventory:registerHook('buyItem', function(payload)
        if not payload.itemName or not string.find(payload.itemName, 'WEAPON_') then return true end
        CreateThread(function()
            if not QBCore then return end
            local Player = QBCore.Functions.GetPlayer(payload.source)
            if not Player then return end
            local owner = Player.PlayerData.citizenid
            if not owner or not payload.metadata or not payload.metadata.serial then return end

            local success, err = pcall(function()
                exports[resourceName]:registerWeapon(owner, payload.itemName, payload.metadata.serial, 'Purchased from shop')
            end)
            if not success then
                ps.warn('Error auto-registering weapon: ' .. tostring(err))
            end
        end)
        return true
    end, {
        typeFilter = { ['player'] = true }
    })

    if Config.RegisterCreatedWeapons then
        exports.ox_inventory:registerHook('createItem', function(payload)
            if not payload.item or not payload.item.name or not string.find(payload.item.name, 'WEAPON_') then return true end
            CreateThread(function()
                if not QBCore then return end
                local Player = QBCore.Functions.GetPlayer(payload.inventoryId)
                if not Player then return end
                local owner = Player.PlayerData.citizenid
                if not owner or not payload.metadata or not payload.metadata.serial then return end

                local success, err = pcall(function()
                    exports[resourceName]:registerWeapon(owner, payload.item.name, payload.metadata.serial, 'Purchased from shop')
                end)
                if not success then
                    ps.warn('Error auto-registering created weapon: ' .. tostring(err))
                end
            end)
            return true
        end, {
            typeFilter = { ['player'] = true }
        })
    end
end)

-- qb-inventory / qb-core auto-registration via player data change detection
-- qb-inventory doesn't fire weapon-specific events; instead it calls
-- Player.Functions.SetPlayerData('items', inventory) which triggers
-- QBCore:Player:SetPlayerData on the server. We track known weapon serials
-- per player and register any new ones that appear.
do
    if not Config.RegisterWeaponsAutomatically then return end

    local knownSerials = {} -- [citizenid] = { [serial] = true }

    --- Build a set of weapon serials from a player's items table
    local function getWeaponSerials(items)
        local serials = {}
        if not items then return serials end
        for _, item in pairs(items) do
            if item.name and string.find(string.upper(item.name), 'WEAPON_') then
                local serial = item.info and (item.info.serie or item.info.serial) or nil
                if serial then
                    serials[serial] = item.name
                end
            end
        end
        return serials
    end

    AddEventHandler('QBCore:Player:SetPlayerData', function(PlayerData)
        if not PlayerData or not PlayerData.items or not PlayerData.citizenid then return end
        local citizenid = PlayerData.citizenid

        local currentSerials = getWeaponSerials(PlayerData.items)

        -- First time seeing this player: seed the known set without registering
        if not knownSerials[citizenid] then
            knownSerials[citizenid] = {}
            for serial, _ in pairs(currentSerials) do
                knownSerials[citizenid][serial] = true
            end
            return
        end

        -- Detect new weapon serials
        for serial, itemName in pairs(currentSerials) do
            if not knownSerials[citizenid][serial] then
                knownSerials[citizenid][serial] = true
                -- New weapon appeared - register it asynchronously
                local _cid = citizenid
                local _serial = serial
                local _model = string.upper(itemName)
                CreateThread(function()
                    local existing = MySQL.single.await('SELECT id FROM mdt_weapons WHERE serial = ? LIMIT 1', { _serial })
                    if existing then return end
                    local ok, err = pcall(function()
                        exports[resourceName]:registerWeapon(_cid, _model, _serial, 'Purchased from shop')
                    end)
                    if not ok then
                        ps.warn('Auto-register weapon failed: ' .. tostring(err))
                    end
                end)
            end
        end
    end)

    -- Clean up tracking when player drops
    AddEventHandler('playerDropped', function()
        local src = source
        if not QBCore then return end
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData and Player.PlayerData.citizenid then
            knownSerials[Player.PlayerData.citizenid] = nil
        end
    end)
end

-- Weapon Self-Register (server event from 3rd eye)
RegisterNetEvent(resourceName .. ':server:selfRegisterWeapon')
AddEventHandler(resourceName .. ':server:selfRegisterWeapon', function(serial, imageurl, notes, owner, weapClass, weapModel)
    local src = source
    if not serial then return end

    local success, err = pcall(function()
        exports[resourceName]:registerWeapon(owner or ps.getIdentifier(src), weapModel or 'unknown', serial, notes or 'Self Registered')
    end)

    if success then
        ps.notify(src, 'Weapon registered in police database', 'success')
    end
end)
