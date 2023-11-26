local Config = require 'Config'
local utils = require 'functions'

local ropes = {}
local entitiesCharging = {}
local activePoints = {}

local currentCharger

-- ROPES --

local function destroyRope(netId)
    if ropes[netId] then
        DeleteRope(ropes[netId])
        ropes[netId] = nil
    end
end


local function createRope(netId, coords)
    if netId and not ropes[netId] and coords and #(GetEntityCoords(cache.ped) - coords) < 100.0 then
        local objectPool = GetGamePool('CObject')

        local entity

        for i = 1, #objectPool do
            local v = objectPool[i]

            if GetEntityModel(v) == `electric_charger` and #(GetEntityCoords(v) - coords) < 1 then
                entity = v
                break
            end
        end

        if entity then

            local timeOut = GetGameTimer() + 5000

            while not NetworkDoesNetworkIdExist(netId) do
                if GetGameTimer() > timeOut then
                    return
                end

                Wait(25)
            end

            local nozzleHandle = NetToObj(netId)

            if nozzleHandle and DoesEntityExist(nozzleHandle) then
                local pumpCoords = GetEntityCoords(entity)
                local rope = utils.loadRope(pumpCoords)
                local nozzlePos = GetOffsetFromEntityInWorldCoords(nozzleHandle, -0.005, 0.2, -0.03)
                AttachEntitiesToRope(rope, entity, nozzleHandle, pumpCoords.x, pumpCoords.y, pumpCoords.z + 1.0, nozzlePos.x, nozzlePos.y, nozzlePos.z, 5.0, false, false, nil, nil)

                ropes[netId] = rope
            end
        end
    end
end

RegisterNetEvent('Renewed-Chargers:client:ropeMechanic', createRope)
RegisterNetEvent('Renewed-Charging:client:destroyRope', destroyRope)


AddEventHandler('Renewed-Charging:client:addCharger', function(data)
    if not currentCharger then return end
    local bone, boneOffset = utils.checkVehicleBones(data.entity)

    if NetworkGetEntityOwner(currentCharger) ~= cache.playerId then
        utils.requestControl(currentCharger)
    end

    local Charger = currentCharger

    local canCharge = lib.callback.await('Renewed-Charging:server:chargeVehicle', false, VehToNet(data.entity))

    if canCharge then
        AttachEntityToEntity(Charger, data.entity, GetEntityBoneIndexByName(data.entity, bone), -0.05 + boneOffset.x, boneOffset.y, 0.45 + boneOffset.z, 0.0, 0.0, 90.0, true, true, false, false, 1, true)
    else
        lib.notify({
            description = 'Vehicle is already fully charged!',
            type = 'error'
        })
    end
end)

local playerState = LocalPlayer.state


AddEventHandler('Renewed-Chargers:client:takeChargerNozzle', function(data)
    TriggerServerEvent('Renewed-Chargers:server:takeHandle', data.id, GetEntityCoords(data.entity))

    while not playerState.attachEntity do
        Wait(25)
    end

    CreateThread(function()
        local entity = data.entity

        if entity then
            while playerState.attachEntity do

                if #(GetEntityCoords(entity) - GetEntityCoords(cache.ped)) > 5.0 then
                    TriggerServerEvent('Renewed-Chargers:server:cancelHandle')
                    break
                end

                Wait(100)
            end
        end
    end)
end)

CreateThread(function()
    while not IsModelValid(`electric_charger`) do
        Wait(10)
    end

    for i = 1, #Config.Locations do
        local coords = Config.Locations[i]

        utils.createBlip(coords)
        utils.addModel(i, coords)
    end
end)

exports.ox_target:addModel(Config.electricCars, {
    {
        name = 'renewed_fuel_FuelCans',
        icon = 'fas fa-gas-pump',
        label = 'Remove Charger',
        distance = 2,
        bones = Config.vehicleBones,
        canInteract = function(entity)
            return entitiesCharging[entity]
        end,
        onSelect = function(data)
            TriggerServerEvent('Renewed-Chargers:server:removeChargingNozzle', VehToNet(data.entity))
        end
    },

    {
        name = 'renewed_fuel_FuelCans',
        icon = 'fas fa-gas-pump',
        label = 'Place Charger',
        distance = 2,
        bones = Config.vehicleBones,
        canInteract = function(entity)
            return currentCharger and not entitiesCharging[entity]
        end,
        event = 'Renewed-Charging:client:addCharger'
    },
})




local function canTakeCharger()
    return not currentCharger and not lib.progressActive()
end exports('CanTakeCharger', canTakeCharger)

local function canReturnCharger()
    return currentCharger and not lib.progressActive()
end exports('CanReturnCharger', canReturnCharger)

-- STATE BAGS

AddStateBagChangeHandler('vehicleCharging', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)

    if vehicle == 0 then
        return
    end

    entitiesCharging[vehicle] = value

    if value and NetworkGetEntityOwner(vehicle) == cache.playerId then
        SetVehicleUndriveable(vehicle, true)
    end

    if value and value.netId and not activePoints[vehicle] then
        activePoints[vehicle] = lib.zones.sphere({
            coords = GetEntityCoords(vehicle),
            radius = 20.0,
            debug = false,
            onEnter = function()
                createRope(value.netId, value.chargerCoords)
            end,
            onExit = function()
                destroyRope(value.netId)
            end
        })
    elseif not value and activePoints[vehicle] then
        activePoints[vehicle]:remove()
        activePoints[vehicle] = nil
    end
end)

RegisterNetEvent('Renewed-Chargers:client:setDriveable', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if vehicle > 0 and DoesEntityExist(vehicle) then
        SetVehicleUndriveable(vehicle, false)
    end
end)

CreateThread(function()
    while true do
        if activePoints and next(activePoints) then
            for k, v in pairs(activePoints) do
                if not DoesEntityExist(k) then
                    v:remove()
                    activePoints[k] = nil
                end
            end
        end
        Wait(10000)
    end
end)

lib.onCache('vehicle', function(vehicle)
    if vehicle then
        if Entity(vehicle).state.vehicleCharging then
            TriggerServerEvent('Renewed-Chargers:server:getFuelUpdate', VehToNet(vehicle))
        end
    end
end)

-- Make sure people can't drive while charging
lib.onCache('seat', function(seat)
    if seat == -1 then
        local state = Entity(cache.vehicle).state
        if state.vehicleCharging then
            SetTimeout(0, function()
                while state.vehicleCharging and cache.seat == -1 do
                    if GetIsVehicleEngineRunning(cache.vehicle) then
                        SetVehicleEngineOn(cache.vehicle, false, false, true)
                    end

                    Wait(100)
                end
            end)
        end
    end
end)

local function chargerLoop()
    while currentCharger do
        local vehicle = GetVehiclePedIsEntering(cache.ped)

        if vehicle > 0 then
            ClearPedTasks(cache.ped)
        end

        Wait(100)
    end
end

AddStateBagChangeHandler('attachEntity', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value and value.charging then
        while not NetworkDoesEntityExistWithNetworkId(value.entity) do
            Wait(25)
        end

        local entity = NetworkGetEntityFromNetworkId(value.entity)

        if entity > 0 and DoesEntityExist(entity) then
            currentCharger = entity
            return chargerLoop()
        end
    end

    currentCharger = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, v in pairs(ropes) do
            DeleteRope(v)
        end
    end
 end)
