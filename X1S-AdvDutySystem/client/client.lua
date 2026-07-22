local onDuty = false
local dutyRequestPending = false
local dutyBlips = {}
local alertBlips = {}
local nuiReady = false
local pendingUiMessages = {}
local maxPendingUiMessages = 32

local function sendUiMessage(message)
    if nuiReady then
        SendNUIMessage(message)
        return
    end

    if #pendingUiMessages >= maxPendingUiMessages then
        table.remove(pendingUiMessages, 1)
    end
    pendingUiMessages[#pendingUiMessages + 1] = message
end

local function translate(key, ...)
    return X1S.Translate(key, ...)
end

local function getUiLocale()
    return Locales[Config.Locale] or Locales.en
end

local function notify(notificationType, title, message, duration)
    sendUiMessage({
        action = 'notify',
        notification = {
            type = notificationType or 'info',
            title = title or translate('notification_system'),
            message = message or '',
            duration = duration or Config.Notifications.duration,
            position = Config.Notifications.position,
            maxVisible = Config.Notifications.maxVisible,
            sound = Config.Notifications.sound
        }
    })
end

local function toCoordinateTable(coords)
    return {
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0
    }
end

local function getCurrentLocation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and GetStreetNameFromHashKey(crossingHash) or ''

    if street == '' then street = translate('unknown_location') end
    if crossing ~= '' and crossing ~= street then
        street = ('%s / %s'):format(street, crossing)
    end

    return toCoordinateTable(coords), street
end

local function clearBlipCollection(collection)
    for id, entry in pairs(collection) do
        local blip = type(entry) == 'table' and entry.blip or entry
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
        collection[id] = nil
    end
end

local function createTimedAlertBlip(data, options)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    local x = tonumber(data.coords.x)
    local y = tonumber(data.coords.y)
    local z = tonumber(data.coords.z)
    if not x or not y or not z then return end

    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, options.sprite)
    SetBlipColour(blip, options.color)
    SetBlipScale(blip, options.scale)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, options.flashes)
    if options.flashInterval then SetBlipFlashInterval(blip, options.flashInterval) end

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(options.label)
    EndTextCommandSetBlipName(blip)

    local alertId = data.alertId or ('%s-%s'):format(options.label, GetGameTimer())
    alertBlips[alertId] = blip

    CreateThread(function()
        Wait(options.duration)
        if alertBlips[alertId] and DoesBlipExist(alertBlips[alertId]) then
            RemoveBlip(alertBlips[alertId])
        end
        alertBlips[alertId] = nil
    end)
end

RegisterNetEvent('x1s-duty:client:notify', function(data)
    if GetInvokingResource() then return end
    if type(data) ~= 'table' then return end
    notify(data.type, data.title, data.message, data.duration)
end)

RegisterNUICallback('ready', function(_, callback)
    nuiReady = true
    for index = 1, #pendingUiMessages do
        SendNUIMessage(pendingUiMessages[index])
    end
    pendingUiMessages = {}
    callback({ ok = true })
end)

RegisterNUICallback('uiError', function(data, callback)
    local message = type(data) == 'table' and tostring(data.message or 'Unknown NUI error') or 'Unknown NUI error'
    print(('[X1S NUI] %s'):format(message))
    callback({ ok = true })
end)

-- Duty menu
RegisterCommand('dutymenu', function()
    if onDuty or IsNuiFocused() then return end

    local departments = {}
    for key, department in pairs(Config.Departments) do
        departments[#departments + 1] = { value = key, label = department.label }
    end

    SetNuiFocus(true, true)
    sendUiMessage({
        action = 'openDuty',
        departments = departments,
        locale = getUiLocale(),
        notificationConfig = Config.Notifications
    })
end)

RegisterNUICallback('goOnDuty', function(data, callback)
    if dutyRequestPending or onDuty then
        callback({ ok = false, error = translate('duty_pending') })
        return
    end

    dutyRequestPending = true
    TriggerServerEvent('x1s-duty:server:onDuty', data)
    callback({ ok = true })
end)

local function goOffDuty()
    onDuty = false
    dutyRequestPending = false
    TriggerServerEvent('x1s-duty:server:offDuty')
    clearBlipCollection(dutyBlips)
end

RegisterCommand('offduty', function()
    if onDuty then goOffDuty() end
end)

RegisterNUICallback('offDuty', function(_, callback)
    goOffDuty()
    callback({ ok = true })
end)

RegisterNetEvent('x1s-duty:client:dutyConfirmed', function()
    if GetInvokingResource() then return end
    local wasOnDuty = onDuty
    dutyRequestPending = false
    onDuty = true
    if not wasOnDuty and not Config.Notifications.announceDutyChanges then
        notify('success', translate('notification_duty'), translate('duty_confirmed'))
    end
end)

RegisterNetEvent('x1s-duty:client:dutyDenied', function()
    if GetInvokingResource() then return end
    local wasPending = dutyRequestPending
    dutyRequestPending = false
    onDuty = false
    clearBlipCollection(dutyBlips)
    if wasPending then
        notify('error', translate('notification_duty'), translate('duty_denied'))
    end
end)

RegisterNetEvent('x1s-duty:client:resetDutyState', function()
    if GetInvokingResource() then return end
    onDuty = false
    dutyRequestPending = false
    SetNuiFocus(false, false)
    sendUiMessage({ action = 'close' })
    clearBlipCollection(dutyBlips)
    clearBlipCollection(alertBlips)
end)

RegisterNUICallback('close', function(_, callback)
    SetNuiFocus(false, false)
    callback({ ok = true })
end)

-- Supervisor menu
RegisterCommand('supervisormenu', function()
    TriggerServerEvent('x1s-duty:server:requestSupervisorMenu')
end)

RegisterNetEvent('x1s-duty:client:openSupervisor', function(data)
    if GetInvokingResource() then return end
    SetNuiFocus(true, true)
    sendUiMessage({
        action = 'openSupervisor',
        players = data,
        locale = getUiLocale(),
        notificationConfig = Config.Notifications
    })
end)

RegisterNUICallback('forceOff', function(data, callback)
    TriggerServerEvent('x1s-duty:server:forceOffDuty', data)
    callback({ ok = true })
end)

RegisterNetEvent('x1s-duty:client:forceOffResult', function(data)
    if GetInvokingResource() then return end
    sendUiMessage({ action = 'forceOffResult', result = data })
end)

RegisterNetEvent('x1s-duty:client:forcedOff', function()
    if GetInvokingResource() then return end
    onDuty = false
    dutyRequestPending = false
    clearBlipCollection(dutyBlips)
    notify('error', translate('notification_duty'), translate('forced_off'), 7000)
end)

-- Duty blips
RegisterNetEvent('x1s-duty:client:syncBlips', function(players)
    if GetInvokingResource() then return end
    if not onDuty or type(players) ~= 'table' then return end

    local myId = GetPlayerServerId(PlayerId())
    local seen = {}

    for serverId, data in pairs(players) do
        local id = tonumber(serverId)
        if id and id ~= myId and type(data) == 'table' and type(data.coords) == 'table' then
            local x, y, z = tonumber(data.coords.x), tonumber(data.coords.y), tonumber(data.coords.z)
            if x and y and z then
                seen[id] = true
                local entry = dutyBlips[id]
                local blip = entry and entry.blip

                if not blip or not DoesBlipExist(blip) then
                    blip = AddBlipForCoord(x, y, z)
                    SetBlipScale(blip, 0.9)
                    SetBlipAsShortRange(blip, false)
                    ShowHeadingIndicatorOnBlip(blip, true)
                    dutyBlips[id] = { blip = blip }
                else
                    SetBlipCoords(blip, x, y, z)
                end

                SetBlipSprite(blip, data.sprite or 1)
                SetBlipColour(blip, data.color or 0)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(('[%s] %s'):format(data.callsign or '000', data.name or translate('unknown')))
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    for id, entry in pairs(dutyBlips) do
        if not seen[id] then
            if entry.blip and DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
            dutyBlips[id] = nil
        end
    end
end)

CreateThread(function()
    Wait(500)
    TriggerServerEvent('x1s-duty:server:requestDutyState')

    while true do
        Wait(Config.Sync.coordinateUpdateInterval)
        if onDuty then
            local coords = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('x1s-duty:server:updateCoords', toCoordinateTable(coords))
        end
    end
end)

-- 911 emergency UI and alerts
RegisterCommand('911', function()
    if IsNuiFocused() then return end
    SetNuiFocus(true, true)
    sendUiMessage({
        action = 'openEmergency',
        locale = getUiLocale(),
        notificationConfig = Config.Notifications,
        maxLength = Config.Emergency.reportMaxLength
    })
end)

RegisterNUICallback('submitEmergency', function(data, callback)
    local reason = type(data) == 'table' and data.reason or nil
    if type(reason) ~= 'string' or reason:match('^%s*$') then
        callback({ ok = false, error = translate('missing_report') })
        return
    end

    local coords, street = getCurrentLocation()
    TriggerServerEvent('x1s-duty:server:911Call', reason, coords, street)
    callback({ ok = true })
end)

RegisterNetEvent('x1s-duty:client:911Confirmed', function()
    if GetInvokingResource() then return end
    notify('success', translate('notification_dispatch'), translate('emergency_sent'))
end)

RegisterNetEvent('x1s-duty:client:received911', function(data)
    if GetInvokingResource() then return end
    if type(data) ~= 'table' then return end

    notify(
        'dispatch',
        translate('emergency_received_title'),
        translate('emergency_received', data.caller or translate('unknown'), data.street or translate('unknown_location'), data.reason or ''),
        Config.Notifications.dispatchDuration
    )

    createTimedAlertBlip(data, {
        sprite = 9,
        color = 1,
        scale = 0.7,
        flashes = true,
        label = translate('emergency_received_title'),
        duration = Config.Emergency.blipDuration
    })
end)

-- Panic system
RegisterCommand('panic', function()
    if not onDuty then
        notify('error', translate('notification_panic'), translate('must_be_on_duty'))
        return
    end

    local coords, street = getCurrentLocation()
    TriggerServerEvent('x1s-duty:server:panic', coords, street)
end)

RegisterNetEvent('x1s-duty:client:panicConfirmed', function()
    if GetInvokingResource() then return end
    notify('success', translate('notification_panic'), translate('panic_sent'))
end)

RegisterNetEvent('x1s-duty:client:receivedPanic', function(data)
    if GetInvokingResource() then return end
    if type(data) ~= 'table' then return end

    notify(
        'panic',
        translate('panic_received_title'),
        translate('panic_received', data.name or translate('unknown'), data.callsign or '000', data.street or translate('unknown_location')),
        Config.Notifications.panicDuration
    )

    createTimedAlertBlip(data, {
        sprite = 161,
        color = 1,
        scale = 1.35,
        flashes = true,
        flashInterval = 500,
        label = translate('panic_received_title'),
        duration = Config.Panic.blipDuration
    })
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    nuiReady = false
    pendingUiMessages = {}
    clearBlipCollection(dutyBlips)
    clearBlipCollection(alertBlips)
end)
