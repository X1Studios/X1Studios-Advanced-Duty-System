local onDuty = false
local DutyBlips = {}
local UpdateThread = nil

-- ======================
-- UTIL
-- ======================

local function clearAllBlips()
    for _, data in pairs(DutyBlips) do
        if data.blip then
            RemoveBlip(data.blip)
        end
    end
    DutyBlips = {}
end

local function stopUpdateThread()
    if UpdateThread then
        UpdateThread = nil
    end
end

-- ======================
-- DUTY MENU
-- ======================

RegisterCommand('dutymenu', function()
    if onDuty or IsNuiFocused() then return end

    SetNuiFocus(true, true)

    local departments = {}
    for k,v in pairs(Config.Departments) do
        departments[#departments+1] = {
            value = k,
            label = v.label
        }
    end

    SendNUIMessage({
        action='openDuty',
        departments=departments
    })
end)

RegisterNUICallback('goOnDuty', function(data, cb)
    onDuty = true
    TriggerServerEvent('x1s-duty:onDuty', data)
    cb('ok')
end)

RegisterNUICallback('offDuty', function(_, cb)
    goOffDuty()
    cb('ok')
end)

RegisterCommand('offduty', function()
    if onDuty then goOffDuty() end
end)

function goOffDuty()
    onDuty = false
    TriggerServerEvent('x1s-duty:offDuty')

    stopUpdateThread()
    clearAllBlips()
end

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false,false)
    cb('ok')
end)

-- ======================
-- SUPERVISOR MENU
-- ======================

RegisterCommand('supervisormenu', function()
    TriggerServerEvent('x1s-duty:requestSupervisorMenu')
end)

RegisterNetEvent('x1s-duty:openSupervisor', function(data)
    SetNuiFocus(true,true)
    SendNUIMessage({
        action='openSupervisor',
        players=data
    })
end)

RegisterNUICallback('forceOff', function(data, cb)
    TriggerServerEvent('x1s-duty:forceOffDuty', data)
    cb('ok')
end)

RegisterNetEvent('x1s-duty:forcedOff', function()
    goOffDuty()
end)

-- ======================
-- BLIP SYNC
-- ======================

RegisterNetEvent('x1s-duty:syncBlips', function(players)

    if not onDuty then return end

    local myId = GetPlayerServerId(PlayerId())

    clearAllBlips()

    for serverId, data in pairs(players) do
        if serverId ~= myId then

            local blip = AddBlipForCoord(0.0,0.0,0.0)

            SetBlipSprite(blip, data.sprite or 1)
            SetBlipColour(blip, data.color or 0)
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, false)
            ShowHeadingIndicatorOnBlip(blip, true)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(
                ('[%s] %s'):format(data.callsign or "000", data.name or "Unknown")
            )
            EndTextCommandSetBlipName(blip)

            DutyBlips[serverId] = {
                blip = blip,
                serverId = serverId
            }
        end
    end

    if not UpdateThread then
        UpdateThread = CreateThread(function()
            while onDuty do

                for _, info in pairs(DutyBlips) do
                    local player = GetPlayerFromServerId(info.serverId)

                    if player ~= -1 then
                        local ped = GetPlayerPed(player)

                        if DoesEntityExist(ped) then
                            local coords = GetEntityCoords(ped)
                            SetBlipCoords(info.blip, coords.x, coords.y, coords.z)
                        end
                    end
                end

                Wait(500)
            end

            UpdateThread = nil
        end)
    end
end)

-- ======================
-- CLEANUP
-- ======================

AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearAllBlips()
end)
