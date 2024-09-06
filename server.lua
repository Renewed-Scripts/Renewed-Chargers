lib.versionCheck('Renewed-Scripts/Renewed-Chargers')

local Config = require 'Config'

local vehiclesCharging = {}
local Nozzles = {}

local function createObject(coords)
    local object = CreateObject(`electric_nozzle`, coords.x, coords.y, coords.z - 2, true, true, false)

    while not DoesEntityExist(object) do
        Wait(0)
    end

    SetEntityIgnoreRequestControlFilter(object, true)

    return object, NetworkGetNetworkIdFromEntity(object)
end

local function setPlayerState(source, netId, state)
    if state and netId then
        Player(source).state:set('attachEntity', {
            entity = netId,
            bone = 0x49D9,
            offset = vec3(0.13, 0.13, 0.02),
            rotation = vec3(-180.0, 0.0, 0.0),
            charging = true
        }, true)
    else
        Player(source).state:set('attachEntity', nil, true)
    end
end


RegisterNetEvent('Renewed-Chargers:server:takeHandle', function(id, objectCoords)
    local src = source

    local Location = id and Config.Locations[id]

    if not Location then
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(src))

    local object, netId = createObject(coords)

    Nozzles[src] = {
        entity = object,
        netId = netId,
        chargerCoords = objectCoords,
    }

    setPlayerState(src, netId, true)
    TriggerClientEvent('Renewed-Chargers:client:ropeMechanic', -1, netId, objectCoords)
end)

lib.callback.register('Renewed-Charging:server:chargeVehicle', function(source, netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    local hasNozzle = Nozzles[source]

    if hasNozzle and vehicle and DoesEntityExist(vehicle) then
        local state = Entity(vehicle).state

        if state and state.fuel and state.fuel < 100 then
            setPlayerState(source, nil, false)
            state:set('vehicleCharging', {
                id = hasNozzle.id,
                netId = hasNozzle.netId,
                chargerCoords = hasNozzle.chargerCoords,
                nozzle = hasNozzle.entity,
            }, true)

            return true
        end
    end

    return false
end)

RegisterNetEvent('Renewed-Chargers:server:cancelHandle', function()
    local nozzles = Nozzles[source]

    if nozzles then
        setPlayerState(source, nil, false)
        Nozzles[source] = nil
        TriggerClientEvent('Renewed-Charging:client:destroyRope', -1, nozzles.netId)
        DeleteEntity(nozzles.entity)
    end
end)

local function findNozzle(netId)
    if netId then
        for k, v in pairs(Nozzles) do
            if v.netId == netId then
                return k, v.entity, v.netId
            end
        end
    end

    return false, false
end

local function doFuelChanges(state, vehicle)
    local chargingConfig = vehiclesCharging[vehicle]

    local timePassed = os.time() - chargingConfig.time

    if timePassed < Config.timePerTick then
        return
    end

    local fuel = state.fuel + (Config.fuelPerTick * (timePassed / Config.timePerTick))

    if fuel > 100 then
        fuel = 100
    end

    state:set('fuel', fuel, true)
    state:set('fuelType', '100', true)
    chargingConfig.time = os.time()
end

RegisterNetEvent('Renewed-Chargers:server:removeChargingNozzle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local vehicleData = vehicle and vehiclesCharging[vehicle]

    if not vehicleData or not vehicle or not DoesEntityExist(vehicle) then
        return
    end

    local nozzleId, entity, nozzleNetId = findNozzle(vehicleData.netId)

    if nozzleId and entity then
        local owner = NetworkGetEntityOwner(vehicle)

        if nozzleId ~= source then
            Nozzles[source] = lib.table.deepclone(Nozzles[nozzleId])

            Nozzles[nozzleId] = nil
        end
        local state = Entity(vehicle).state

        doFuelChanges(state, vehicle)
        state:set('vehicleCharging', false, true)

        if owner then
            TriggerClientEvent('Renewed-Chargers:client:setDriveable', owner, netId)
        end

        setPlayerState(source, nozzleNetId, true)
    end
end)

RegisterNetEvent('Renewed-Chargers:server:getFuelUpdate', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    local state = vehicle > 0 and Entity(vehicle).state

    if not vehicle or not vehiclesCharging[vehicle] or not state or not state.fuel then
        if state and state.vehicleCharging then
            local owner = NetworkGetEntityOwner(vehicle)
            state:set('vehicleCharging', false, true)

            if owner then
                TriggerClientEvent('Renewed-Chargers:client:setDriveable', owner, netId)
            end
        end

        return
    end

    doFuelChanges(state, vehicle)
end)

AddEventHandler('Renewed-Lib:server:playerRemoved', function(source)
    local Nozzle = Nozzles[source]
    if Nozzle then
        setPlayerState(source, nil, false)
        Nozzles[source] = nil
        TriggerClientEvent('Renewed-Charging:client:destroyRope', -1, Nozzle.netId)
        DeleteEntity(Nozzle.entity)
    end
end)

AddEventHandler('entityRemoved', function(entityId)
    local vehicle = vehiclesCharging[entityId]
    if vehicle then
        if DoesEntityExist(vehicle.nozzle) then
            DeleteEntity(vehicle.nozzle)
        end

        TriggerClientEvent('Renewed-Charging:client:destroyRope', -1, vehicle.netId)
        vehiclesCharging[entityId] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, v in pairs(Nozzles) do
            DeleteEntity(v.entity)
        end
    end
end)

AddStateBagChangeHandler('vehicleCharging', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)

    if vehicle == 0 then
        return
    end

    if value then
        value.time = os.time()
    end

    vehiclesCharging[vehicle] = value or nil
end)