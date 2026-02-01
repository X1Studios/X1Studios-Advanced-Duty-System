local onDuty = false
local DutyBlips = {}

-- ======================
-- DUTY MENU
-- ======================
RegisterCommand('dutymenu', function()
    if onDuty or IsNuiFocused() then return end

    SetNuiFocus(true, true)

    local departments = {}
    for k, v in pairs(Config.Departments) do
        departments[#departments + 1] = {
            value = k,
            label = v.label
        }
    end

    SendNUIMessage({
        action = 'openDuty',
        departments = departments
    })
end)

RegisterNUICallback('goOnDuty', function(data, cb)
    onDuty = true
    TriggerServerEvent('x1s-duty:onDuty', data)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('offDuty', function(_, cb)
    onDuty = false
    TriggerServerEvent('x1s-duty:offDuty')
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterCommand('offduty', function()
    if not onDuty then return end
    onDuty = false
    TriggerServerEvent('x1s-duty:offDuty')
end)

-- ======================
-- SUPERVISOR MENU
-- ======================
RegisterCommand('supervisormenu', function()
    TriggerServerEvent('x1s-duty:requestSupervisorMenu')
end)

RegisterNetEvent('x1s-duty:openSupervisor', function(data)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openSupervisor',
        players = data
    })
end)

-- FORCED OFF EVENT
RegisterNetEvent('x1s-duty:forcedOff', function()
    onDuty = false

    -- remove all blips when forced off
    for id, blip in pairs(DutyBlips) do
        RemoveBlip(blip)
        DutyBlips[id] = nil
    end
end)

RegisterNUICallback('forceOff', function(data, cb)
    TriggerServerEvent('x1s-duty:forceOffDuty', data)
    cb('ok')
end)

-- ======================
-- BLIPS
-- ======================
RegisterNetEvent('x1s-duty:addBlip', function(id, data)
    CreateThread(function()
        local tries = 0
        local player = GetPlayerFromServerId(id)

        while player == -1 and tries < 20 do
            Wait(250)
            player = GetPlayerFromServerId(id)
            tries = tries + 1
        end

        if player == -1 then return end

        local ped = GetPlayerPed(player)
        if not DoesEntityExist(ped) then return end

        if DutyBlips[id] then
            RemoveBlip(DutyBlips[id])
        end

        local blip = AddBlipForEntity(ped)
        SetBlipSprite(blip, data.sprite)
        SetBlipColour(blip, data.color)
        SetBlipScale(blip, 0.9)
        SetBlipAsShortRange(blip, false)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('[%s] %s'):format(data.callsign, data.name))
        EndTextCommandSetBlipName(blip)

        DutyBlips[id] = blip
    end)
end)

RegisterNetEvent('x1s-duty:removeBlip', function(id)
    if DutyBlips[id] then
        RemoveBlip(DutyBlips[id])
        DutyBlips[id] = nil
    end
end)

-- ======================
-- CLEANUP
-- ======================
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, blip in pairs(DutyBlips) do
        RemoveBlip(blip)
    end
end)

local DutyPlayers = {}

-- ======================
-- TOAST RECEIVER
-- ======================
RegisterNetEvent('x1s-duty:toast', function(data)
    if type(data) ~= 'table' then return end

    SendNUIMessage({
        action = 'toast',
        message = data.message or '',
        type = data.type or 'success'
    })
end)
