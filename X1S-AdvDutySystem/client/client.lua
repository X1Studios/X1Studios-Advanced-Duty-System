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
-- 911 Call System
-- ======================

RegisterCommand("911", function()
    -- open on-screen keyboard
    DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP8", "", "", "", "", "", 128)
    while (UpdateOnscreenKeyboard() == 0) do
        DisableAllControlActions(0)
        Wait(0)
    end

    local reason = GetOnscreenKeyboardResult()
    if not reason or reason == "" then
        TriggerEvent('chat:addMessage', {
            color = {255,0,0},
            args = {"Dispatch", "911 call cancelled."}
        })
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)

    TriggerServerEvent('x1s-duty:911Call', reason, coords, street)
end)

-- Confirm to caller
RegisterNetEvent('x1s-duty:911Confirmed', function()
    TriggerEvent('chat:addMessage', {
        color = {0,255,0},
        args = {"X1S Dispatch", "✅ Your 911 call has been sent to emergency services."}
    })
end)

-- Receive alert (on-duty cops only)
RegisterNetEvent('x1s-duty:receive911', function(data)
    -- Top divider (red)
    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {"════════════ 🚨 911 DISPATCH 🚨 ════════════"}
    })

    -- Inner info (white) sent line by line
    TriggerEvent('chat:addMessage', {
        color = {255, 255, 0},
        args = {("📞[Caller]: %s [%s]"):format(data.caller, data.id)}
    })

    TriggerEvent('chat:addMessage', {
        color = {255, 255, 255},
        args = {"────────────────────────────"}
    })

    TriggerEvent('chat:addMessage', {
        color = {0, 128, 0},
        args = {("🗺️[Location]: %s"):format(data.street)}
    })

    TriggerEvent('chat:addMessage', {
        color = {255, 255, 255},
        args = {"────────────────────────────"}
    })

    TriggerEvent('chat:addMessage', {
        color = {255, 165, 0},
        args = {("⚠️[Report]: %s"):format(data.reason)}
    })

    -- Bottom divider (red)
    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {"══════════════════════════════════════"}
    })

    -- Blip for 2 minutes
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.3)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("911 Call")
    EndTextCommandSetBlipName(blip)

    CreateThread(function()
        Wait(120000)
        RemoveBlip(blip)
    end)
end)

-- ======================
-- PANIC BUTTON SYSTEM
-- ======================

RegisterCommand("panic", function()
    if not onDuty then
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            args = {"SYSTEM", "❌ You must be on duty to use panic."}
        })
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)

    TriggerServerEvent('x1s-duty:panic', coords, street)
end)

-- Receive panic (ONLY on-duty officers)
RegisterNetEvent('x1s-duty:receivePanic', function(data)
    if not onDuty then return end

    -- TOP BAR
    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {"════════════ 🚨 OFFICER PANIC 🚨 ════════════"}
    })

    -- Officer info
    TriggerEvent('chat:addMessage', {
        color = {255, 255, 0},
        args = {("👮‍♂️ [%s] %s"):format(data.callsign, data.name)}
    })

    TriggerEvent('chat:addMessage', {
        color = {255, 255, 255},
        args = {"────────────────────────────"}
    })

    -- Location
    TriggerEvent('chat:addMessage', {
        color = {0, 128, 255},
        args = {("🗺️ Location: %s"):format(data.street)}
    })

    -- Bottom bar
    TriggerEvent('chat:addMessage', {
        color = {255, 0, 0},
        multiline = true,
        args = {"══════════════════════════════════════"}
    })

    -- Panic blip
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.5)
    SetBlipFlashes(blip, true)
    SetBlipFlashInterval(blip, 500)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("🚨 Officer Panic")
    EndTextCommandSetBlipName(blip)

    -- Remove after 120 sec
    CreateThread(function()
        Wait(120000)
        RemoveBlip(blip)
    end)
end)

-- ======================
-- CLEANUP
-- ======================

AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearAllBlips()
end)
