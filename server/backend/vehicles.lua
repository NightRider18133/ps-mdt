local function getCoreObject()
    local ok, core = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)
    if ok and core then
        return core
    end

    local okQbx, qbx = pcall(function()
        return exports['qbx_core']:GetCoreObject()
    end)
    if okQbx and qbx then
        return qbx
    end

    return nil
end

local Core = getCoreObject()
local resourceName = tostring(GetCurrentResourceName())

local function formatLabel(value)
    if not value or value == '' then
        return 'Unknown'
    end
    local formatted = tostring(value)
    formatted = formatted:gsub("^%l", string.upper)
    formatted = formatted:gsub("_%l", function(s)
        return " " .. string.upper(s:sub(2))
    end)
    return formatted
end

local function getVehicleShared(model)
    if not Core or not Core.Shared or not Core.Shared.Vehicles then
        return nil
    end
    return Core.Shared.Vehicles[model]
end

local function buildVehicleFlags(stolen, hasActiveBolo, status)
    local flags = {}
    if hasActiveBolo then
        table.insert(flags, 'Bolo')
    end
    if stolen then
        table.insert(flags, 'Stolen')
    end
    if status and status ~= 'valid' then
        table.insert(flags, ('Status: %s'):format(formatLabel(status)))
    end
    return flags
end

local function countSetItems(set)
    if not set then
        return 0
    end
    local count = 0
    for _ in pairs(set) do
        count = count + 1
    end
    return count
end

-- Batch-resolve BOLO flags / report counts for a list of plates.
-- Returns: { activeByPlate = { [PLATE] = true }, reportCountByPlate = { [PLATE] = N } }
local function getBoloMetaForPlates(plates)
    local activeByPlate = {}
    local reportCountByPlate = {}
    if not plates or #plates == 0 then
        return activeByPlate, reportCountByPlate
    end

    local placeholders = (string.rep('?,', #plates)):sub(1, -2)
    local params = { 'vehicle' }
    for i = 1, #plates do
        params[#params + 1] = plates[i]
    end

    local rows = MySQL.query.await(([[
        SELECT
            UPPER(subject_id) AS plate,
            SUM(status = 'active') AS active_count,
            COUNT(DISTINCT reportId) AS report_count
        FROM mdt_bolos
        WHERE type = ? AND subject_id IN (%s)
        GROUP BY UPPER(subject_id)
    ]]):format(placeholders), params) or {}

    for _, row in ipairs(rows) do
        if row.plate then
            if tonumber(row.active_count) and tonumber(row.active_count) > 0 then
                activeByPlate[row.plate] = true
            end
            reportCountByPlate[row.plate] = tonumber(row.report_count) or 0
        end
    end

    return activeByPlate, reportCountByPlate
end

local function rowToVehicle(v, activeByPlate, reportCountByPlate)
    local vehicleData = getVehicleShared(v.vehicle)
    local plate = v.plate and string.upper(v.plate) or 'UNKNOWN'
    local hasActiveBolo = activeByPlate[plate] == true or v.boloactive == 1
    local flags = buildVehicleFlags(v.stolen == 1, hasActiveBolo, v.status)

    return {
        id = v.id,
        model = v.vehicle,
        label = vehicleData and vehicleData.name or 'Unknown Vehicle',
        plate = plate,
        owner = ps.getPlayerNameByIdentifier(v.citizenid) or 'Unknown',
        class = formatLabel(vehicleData and vehicleData.category or 'Unknown'),
        type = formatLabel(vehicleData and vehicleData.type or 'Unknown'),
        flags = flags,
        image = (v.image and v.image ~= '' and v.image) or ('https://docs.fivem.net/vehicles/' .. v.vehicle .. '.webp'),
        seenIn = reportCountByPlate[plate] or 0,
        points = tonumber(v.points) or 0,
        status = v.status or 'valid',
        core_state = tonumber(v.core_state) or 0,
    }
end

local VEHICLE_LIST_COLUMNS = [[
    pv.id,
    pv.plate,
    pv.vehicle,
    pv.citizenid,
    pv.mdt_vehicle_points AS points,
    pv.mdt_vehicle_status AS status,
    pv.mdt_vehicle_stolen AS stolen,
    pv.mdt_vehicle_boloactive AS boloactive,
    pv.mdt_vehicle_image AS image,
    pv.state AS core_state
]]

ps.registerCallback(resourceName .. ':server:GetVehicles', function(source, payload)
    local startTime = os.clock()
    local src = source
    if not CheckAuth(src) then return end

    payload = type(payload) == 'table' and payload or {}
    local page = math.max(1, tonumber(payload.page) or 1)
    local limit = Config.Pagination and Config.Pagination.Vehicles or 50
    if payload.perPage then
        local pp = tonumber(payload.perPage) or limit
        limit = math.max(10, math.min(pp, 200))
    end
    local offset = (page - 1) * limit

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM player_vehicles') or 0

    local vehList = MySQL.query.await(([[
        SELECT %s
        FROM player_vehicles pv
        ORDER BY pv.id ASC
        LIMIT ? OFFSET ?
    ]]):format(VEHICLE_LIST_COLUMNS), { limit, offset }) or {}

    -- Collect plates from this page only and resolve BOLO state in one query.
    local plates = {}
    for i = 1, #vehList do
        if vehList[i].plate then
            plates[#plates + 1] = vehList[i].plate
        end
    end
    local activeByPlate, reportCountByPlate = getBoloMetaForPlates(plates)

    local vehicles = {}
    for _, v in ipairs(vehList) do
        vehicles[#vehicles + 1] = rowToVehicle(v, activeByPlate, reportCountByPlate)
    end

    -- Active vehicle BOLOs as a separate, bounded list (not joined per-row).
    local boloRows = MySQL.query.await(
        'SELECT id, reportId, subject_id, subject_name, type, notes, status, image FROM mdt_bolos WHERE type = ? AND status = ? ORDER BY id DESC LIMIT 200',
        { 'vehicle', 'active' }
    ) or {}
    local bolos = {}
    for _, bolo in ipairs(boloRows) do
        bolos[#bolos + 1] = {
            id = bolo.id,
            reportId = bolo.reportId and tostring(bolo.reportId) or 'N/A',
            name = bolo.subject_name or 'Unknown Vehicle',
            type = bolo.type,
            notes = bolo.notes or '',
            status = bolo.status,
            plate = bolo.subject_id or 'Unknown',
            image = bolo.image or 'https://docs.fivem.net/vehicles/elegy.webp',
        }
    end

    local elapsedTime = (os.clock() - startTime) * 1000
    ps.debug(string.format("getVehicles callback executed in %.2f ms (page %d, %d rows)", elapsedTime, page, #vehicles))

    return {
        vehicles = vehicles,
        bolos = bolos,
        page = page,
        perPage = limit,
        total = tonumber(total) or 0,
    }
end)

ps.registerCallback(resourceName .. ':server:SearchVehicles', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { vehicles = {}, total = 0 } end

    payload = type(payload) == 'table' and payload or {}
    local query = payload.query
    if type(query) ~= 'string' or #query < 2 then
        return { vehicles = {}, total = 0 }
    end

    local limit = Config.Pagination and Config.Pagination.VehicleSearch or 50
    local needle = '%' .. string.lower(query) .. '%'

    if ps.auditLog then
        ps.auditLog(src, 'search_vehicles', 'search', nil, { query = query })
    end

    -- Plate is the most useful index — push it through a sargable lookup first,
    -- then OR a few fuzzier filters so owners and models still match.
    local rows = MySQL.query.await(([[
        SELECT %s
        FROM player_vehicles pv
        WHERE LOWER(pv.plate) LIKE ?
           OR LOWER(pv.vehicle) LIKE ?
           OR LOWER(pv.citizenid) LIKE ?
        ORDER BY pv.id ASC
        LIMIT ?
    ]]):format(VEHICLE_LIST_COLUMNS), { needle, needle, needle, limit }) or {}

    local plates = {}
    for i = 1, #rows do
        if rows[i].plate then
            plates[#plates + 1] = rows[i].plate
        end
    end
    local activeByPlate, reportCountByPlate = getBoloMetaForPlates(plates)

    local vehicles = {}
    for _, v in ipairs(rows) do
        vehicles[#vehicles + 1] = rowToVehicle(v, activeByPlate, reportCountByPlate)
    end

    return { vehicles = vehicles, total = #vehicles, page = 1, perPage = limit }
end)

ps.registerCallback(resourceName .. ':server:UpdateVehicle', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local plate = payload.plate
    if not plate or plate == '' then
        return { success = false, message = 'Missing plate' }
    end

    local ownerRow = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not ownerRow or not ownerRow.citizenid then
        return { success = false, message = 'Vehicle not found' }
    end

    local existing = MySQL.single.await('SELECT mdt_vehicle_points, mdt_vehicle_status, mdt_vehicle_information FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    local previousPoints = existing and tonumber(existing.mdt_vehicle_points) or 0

    local points = tonumber(payload.points)
    if points and points < 0 then
        points = 0
    end

    local allowedStatus = {
        valid = true,
        suspended = true,
        expired = true,
        impounded = true
    }
    local status = payload.status
    if status and not allowedStatus[status] then
        status = nil
    end

    local updates = {}
    local values = {}

    if payload.information ~= nil then
        updates[#updates + 1] = 'mdt_vehicle_information = ?'
        values[#values + 1] = payload.information
    end

    if points ~= nil then
        updates[#updates + 1] = 'mdt_vehicle_points = ?'
        values[#values + 1] = points
    end

    if status ~= nil then
        updates[#updates + 1] = 'mdt_vehicle_status = ?'
        values[#values + 1] = status
    end

    if #updates == 0 then
        return { success = true }
    end

    values[#values + 1] = plate

    MySQL.update.await(('UPDATE player_vehicles SET %s WHERE plate = ?'):format(table.concat(updates, ', ')), values)

    if ps.auditLog then
        ps.auditLog(src, 'vehicle_updated', 'vehicle', plate, {
            plate = plate,
            points = points,
            status = status,
            information = payload.information
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:GetVehicle', function(source, plate)
    local src = source
    if not CheckAuth(src) then return end

    if not plate or plate == '' then
        return { success = false, message = 'Missing plate' }
    end

    local vehicleRow = MySQL.query.await([[
        SELECT
            pv.id,
            pv.plate,
            pv.vehicle,
            pv.citizenid,
            pv.mdt_vehicle_information AS information,
            pv.mdt_vehicle_points AS points,
            pv.mdt_vehicle_status AS status,
            pv.mdt_vehicle_stolen AS stolen,
            pv.mdt_vehicle_boloactive AS boloactive,
            pv.mdt_vehicle_image AS image,
            pv.state AS core_state
        FROM player_vehicles pv
        WHERE pv.plate = ?
        LIMIT 1
    ]], { plate })

    if not vehicleRow or not vehicleRow[1] then
        return { success = false, message = 'Vehicle not found' }
    end

    local row = vehicleRow[1]
    local vehicleData = getVehicleShared(row.vehicle)
    local plateUpper = row.plate and string.upper(row.plate) or 'UNKNOWN'

    local boloRows = MySQL.query.await('SELECT * FROM mdt_bolos WHERE type = ? AND subject_id = ?', { 'vehicle', plate })
    local reportIdSet = {}
    local bolos = {}
    local hasActiveBolo = false
    for _, bolo in pairs(boloRows) do
        if bolo.reportId then
            reportIdSet[tostring(bolo.reportId)] = true
        end
        if bolo.status == 'active' then
            hasActiveBolo = true
        end
        table.insert(bolos, {
            id = bolo.id,
            reportId = bolo.reportId and tostring(bolo.reportId) or 'N/A',
            notes = bolo.notes or '',
            status = bolo.status,
            type = bolo.type,
        })
    end

    local reportCount = countSetItems(reportIdSet)
    local flags = buildVehicleFlags(row.stolen == 1, hasActiveBolo or row.boloactive == 1, row.status)

    return {
        success = true,
        vehicle = {
            id = row.id,
            model = row.vehicle,
            label = vehicleData and vehicleData.name or 'Unknown Vehicle',
            brand = vehicleData and vehicleData.brand or nil,
            plate = plateUpper,
            owner = ps.getPlayerNameByIdentifier(row.citizenid) or 'Unknown',
            class = formatLabel(vehicleData and vehicleData.category or 'Unknown'),
            type = formatLabel(vehicleData and vehicleData.type or 'Unknown'),
            image = (row.image and row.image ~= '' and row.image) or ('https://docs.fivem.net/vehicles/' .. row.vehicle .. '.webp'),
            information = row.information or '',
            points = tonumber(row.points) or 0,
            status = row.status or 'valid',
            core_state = tonumber(row.core_state) or 0,
            stolen = row.stolen == 1,
            boloactive = row.boloactive == 1,
            flags = flags,
            seenIn = reportCount,
            bolos = bolos,
        }
    }
end)
