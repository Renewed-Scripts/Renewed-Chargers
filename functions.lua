local utils = {}

function utils.loadRope(coords)
    RopeLoadTextures()

    while not RopeAreTexturesLoaded() do
        Wait(0)
    end

    local rope = AddRope(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 3.0, 1, 1000.0, 0.0, 1.0, false, false, false, 1.0, true)
    while not rope do
        Wait(0)
    end

    ActivatePhysics(rope)

    return rope
end

function utils.createBlip(data)
    local blip = AddBlipForCoord(data.x, data.y, data.z)

	SetBlipSprite(blip, 361)
	SetBlipDisplay(blip, 4)
	SetBlipScale(blip, 0.8)
	SetBlipColour(blip, 6)
	SetBlipAsShortRange(blip, true)
    SetBlipCategory(blip, 7)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Charging Station')
	EndTextCommandSetBlipName(blip)
end

function utils.addModel(id, coords)
    local targetId = ('renewed_charger_%s'):format(id)

    local data = {
        object = 'electric_charger',
        coords = vec3(coords.x, coords.y, coords.z),
        heading = coords.w - 180,
        freeze = true,
        dist = 400,
        id = targetId,
        target = {{
            icon = 'fa-solid fa-magnifying-glass',
            label = 'Take Charger',
            name = targetId,
            id = id,
            event = 'Renewed-Chargers:client:takeChargerNozzle',
            canInteract = function()
                return exports['Renewed-Chargers']:CanTakeCharger()
            end,
            distance = 1.2
        },
        {
            icon = 'fa-solid fa-magnifying-glass',
            label = 'Return Charger',
            name = targetId,
            serverEvent = 'Renewed-Chargers:server:cancelHandle',
            canInteract = function()
                return exports['Renewed-Chargers']:CanReturnCharger()
            end,
            distance = 1.2
        }}
    }

    exports['Renewed-Lib']:addObject(data)
end

function utils.requestControl(currentCharger)
    while NetworkGetEntityOwner(currentCharger) ~= cache.playerId do
        NetworkRequestControlOfEntity(currentCharger)
        Wait(25)
    end
end


local vehicleBones = require 'Config'.vehicleBones
function utils.checkVehicleBones(vehicle)
    local bone, boneOffset = '', vec3(0.0, 0.0, 0.0)

    for i = 1, #vehicleBones do
        local boneName = vehicleBones[i]

        local doesBoneExsist = GetEntityBoneIndexByName(vehicle, boneName)
        if doesBoneExsist ~= -1 then
            bone = boneName
            boneOffset = GetWorldPositionOfEntityBone(vehicle, bone)
            break
        end
    end

    return bone, boneOffset
end



return utils
