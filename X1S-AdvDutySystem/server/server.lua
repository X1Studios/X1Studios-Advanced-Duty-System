local DutyPlayers = {}
local PendingDuty = {}
local Cooldowns = {}

local function translate(key, ...)
    return X1S.Translate(key, ...)
end

local function isPlaceholder(value)
    return type(value) ~= 'string' or value == '' or value:find('_HERE', 1, true) ~= nil
end

local function cleanString(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end

    local length = utf8.len(value)
    if not length then return nil end
    if length <= maxLength then return value end

    local endByte = utf8.offset(value, maxLength + 1)
    return endByte and value:sub(1, endByte - 1) or value
end

local function cleanCoords(coords)
    local coordsType = type(coords)
    if coordsType ~= 'table' and coordsType ~= 'vector3' and coordsType ~= 'vector4' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return nil end
    return { x = x, y = y, z = z }
end

local function formatCoordinates(coords)
    return ('X: `%.2f`\nY: `%.2f`\nZ: `%.2f`'):format(coords.x, coords.y, coords.z)
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remaining = seconds % 60
    return ('%02dh %02dm %02ds'):format(hours, minutes, remaining)
end

local function countDutyPlayers()
    local count = 0
    for _ in pairs(DutyPlayers) do count = count + 1 end
    return count
end

local function getIdentifier(src, identifierType)
    local prefix = identifierType .. ':'
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, #prefix) == prefix then return identifier:sub(#prefix + 1) end
    end
    return nil
end

local function discordDisplay(src)
    local discordId = getIdentifier(src, 'discord')
    return discordId and ('<@%s>\n`%s`'):format(discordId, discordId) or 'Not linked'
end

local function makeAlertId(prefix, src)
    return ('%s-%s-%s'):format(prefix, os.time(), src)
end

local function utcTimestamp(epoch)
    return os.date('!%Y-%m-%d %H:%M:%S UTC', epoch or os.time())
end

local function getServerPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return nil end
    return cleanCoords(GetEntityCoords(ped))
end

local function checkCooldown(src, action, duration)
    Cooldowns[src] = Cooldowns[src] or {}
    local now = os.time()
    local expires = Cooldowns[src][action] or 0
    if expires > now then return true, expires - now end
    Cooldowns[src][action] = now + duration
    return false, 0
end

local function getRemoteSource()
    if GetInvokingResource() then return nil end
    local src = tonumber(source)
    if not src or src <= 0 then return nil end
    return src
end

local function validateConfiguration()
    assert(type(Config) == 'table', '[X1S] Config must be a table.')
    assert(type(ServerConfig) == 'table', '[X1S] ServerConfig must be a table.')
    assert(type(Config.Departments) == 'table', '[X1S] Config.Departments must be a table.')
    assert(type(Config.Notifications) == 'table', '[X1S] Config.Notifications must be a table.')
    assert(type(Config.Emergency) == 'table', '[X1S] Config.Emergency must be a table.')
    assert(type(Config.Panic) == 'table', '[X1S] Config.Panic must be a table.')
    assert(type(Config.Sync) == 'table', '[X1S] Config.Sync must be a table.')
    assert(type(ServerConfig.Departments) == 'table', '[X1S] ServerConfig.Departments must be a table.')
    assert(type(ServerConfig.Cooldowns) == 'table', '[X1S] ServerConfig.Cooldowns must be a table.')
    assert(
        type(Config.Sync.coordinateUpdateInterval) == 'number' and Config.Sync.coordinateUpdateInterval >= 500,
        '[X1S] Config.Sync.coordinateUpdateInterval must be at least 500ms.'
    )
    assert(
        type(Config.Sync.blipBroadcastInterval) == 'number' and Config.Sync.blipBroadcastInterval >= 500,
        '[X1S] Config.Sync.blipBroadcastInterval must be at least 500ms.'
    )

    local validPositions = {
        ['top-right'] = true,
        ['top-left'] = true,
        ['bottom-right'] = true,
        ['bottom-left'] = true
    }
    assert(
        validPositions[Config.Notifications.position],
        ('[X1S] Invalid notification position: %s'):format(tostring(Config.Notifications.position))
    )

    for department in pairs(Config.Departments) do
        assert(ServerConfig.Departments[department], ('[X1S] Missing server configuration for %s.'):format(department))
    end

    if isPlaceholder(ServerConfig.BotToken) or isPlaceholder(ServerConfig.GuildID) then
        print('^3[X1S] Discord bot credentials are not configured; duty role checks will be denied.^0')
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    validateConfiguration()
    TriggerClientEvent('x1s-duty:client:resetDutyState', -1)
    print([[
 __   __  __   ____  
 \ \ / / /_ | / ___| 
  \ V /   | | \___ \ 
  / _ \   | |  ___) |
 /_/ \_\  |_| |____/ 

  X1Studios Advanced
      Duty System
    ]])
end)

-- ======================
-- WEBHOOK HELPER
-- ======================
local function sendWebhook(webhook, payload, label)
    if isPlaceholder(webhook) then return end

    PerformHttpRequest(
        webhook,
        function(statusCode)
            local code = tonumber(statusCode) or 0
            if code < 200 or code >= 300 then
                print(('^1[X1S] %s webhook failed with HTTP %s.^0'):format(label, tostring(statusCode)))
            end
        end,
        'POST',
        json.encode(payload),
        { ['Content-Type'] = 'application/json' }
    )
end

local function sendDepartmentWebhook(department, payload)
    sendWebhook(ServerConfig.Webhooks[department], payload, ('%s duty'):format(department))
end

local function sendDispatchWebhook(payload)
    sendWebhook(ServerConfig.DispatchWebhook, payload, 'dispatch')
end

local function sendPanicWebhook(payload)
    sendWebhook(ServerConfig.PanicWebhook, payload, 'panic')
end

-- ======================
-- NOTIFICATION HELPER
-- ======================
local function sendNotification(target, notificationType, title, message, duration)
    TriggerClientEvent('x1s-duty:client:notify', target, {
        type = notificationType,
        title = title,
        message = message,
        duration = duration
    })
end

-- ======================
-- DISCORD UTIL
-- ======================
local function getDiscordId(src)
    return getIdentifier(src, 'discord')
end

local function discordRequest(endpoint)
    if isPlaceholder(ServerConfig.BotToken) or isPlaceholder(ServerConfig.GuildID) then
        return nil
    end

    local p = promise.new()
    PerformHttpRequest(
        'https://discord.com/api/' .. endpoint,
        function(code, data)
            if code == 200 and data then
                local ok, decoded = pcall(json.decode, data)
                p:resolve(ok and decoded or nil)
            else
                p:resolve(nil)
            end
        end,
        'GET',
        '',
        { ['Authorization'] = 'Bot ' .. ServerConfig.BotToken, ['Content-Type'] = 'application/json' }
    )
    return Citizen.Await(p)
end

local function getDiscordMember(src)
    local discord = getDiscordId(src)
    if not discord then return nil end
    return discordRequest(('guilds/%s/members/%s'):format(ServerConfig.GuildID, discord))
end

local function hasRole(roleId, member)
    if not roleId or not member or not member.roles then return false end
    for _, userRole in ipairs(member.roles) do
        if tostring(userRole) == tostring(roleId) then
            return true
        end
    end
    return false
end

local function getSupervisedDepartments(member)
    local allowed = {}
    if not member then return allowed end
    for department, secureConfig in pairs(ServerConfig.Departments) do
        if hasRole(secureConfig.supervisorRole, member) then
            allowed[department] = true
        end
    end
    return allowed
end

-- ======================================
-- SYNC DUTY BLIPS TO ALL ON-DUTY PLAYERS
-- ======================================
local function getDutyBlipSnapshot()
    local snapshot = {}
    for src, player in pairs(DutyPlayers) do
        snapshot[src] = {
            name = player.name,
            callsign = player.callsign,
            coords = player.coords,
            sprite = player.sprite,
            color = player.color
        }
    end
    return snapshot
end

local function syncDutyBlips()
    local snapshot = getDutyBlipSnapshot()
    for src in pairs(DutyPlayers) do
        TriggerClientEvent('x1s-duty:client:syncBlips', src, snapshot)
    end
end

RegisterNetEvent('x1s-duty:server:requestSync', function()
    local src = getRemoteSource()
    if not src then return end
    if DutyPlayers[src] then
        TriggerClientEvent('x1s-duty:client:syncBlips', src, getDutyBlipSnapshot())
    end
end)

RegisterNetEvent('x1s-duty:server:requestDutyState', function()
    local src = getRemoteSource()
    if not src then return end
    local eventName = DutyPlayers[src] and 'x1s-duty:client:dutyConfirmed' or 'x1s-duty:client:dutyDenied'
    TriggerClientEvent(eventName, src)
end)

RegisterNetEvent('x1s-duty:server:updateCoords', function(coords)
    local src = getRemoteSource()
    if not src then return end
    local sanitizedCoords = cleanCoords(coords)
    if DutyPlayers[src] and sanitizedCoords then
        DutyPlayers[src].coords = sanitizedCoords
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Sync.blipBroadcastInterval)
        if next(DutyPlayers) then syncDutyBlips() end
    end
end)

-- ======================
-- ON DUTY
-- ======================
local function denyDuty(src, message)
    PendingDuty[src] = nil
    if message then sendNotification(src, 'error', translate('notification_duty'), message) end
    TriggerClientEvent('x1s-duty:client:dutyDenied', src)
end

RegisterNetEvent('x1s-duty:server:onDuty', function(data)
    local src = getRemoteSource()
    if not src then return end
    if type(data) ~= 'table' then
        denyDuty(src, translate('invalid_duty_request'))
        return
    end

    if DutyPlayers[src] then
        PendingDuty[src] = nil
        sendNotification(src, 'warning', translate('notification_duty'), translate('already_on_duty'))
        TriggerClientEvent('x1s-duty:client:dutyConfirmed', src)
        return
    end

    if PendingDuty[src] then return end

    local coolingDown, remaining = checkCooldown(src, 'dutyRequest', ServerConfig.Cooldowns.dutyRequest)
    if coolingDown then
        denyDuty(src, translate('wait_seconds', remaining))
        return
    end

    PendingDuty[src] = true

    local dept = Config.Departments[data.department]
    local secureDept = ServerConfig.Departments[data.department]
    if not dept or not secureDept then
        denyDuty(src, translate('invalid_department'))
        return
    end

    local name = cleanString(data.name, 40)
    local callsign = cleanString(data.callsign, 16)
    local rank = cleanString(data.rank, 32)
    if not name or not callsign or not rank then
        denyDuty(src, translate('invalid_identity'))
        return
    end

    local member = getDiscordMember(src)
    if not PendingDuty[src] or not GetPlayerName(src) then return end
    if not member or not hasRole(secureDept.dutyRole, member) then
        denyDuty(src, translate('no_department_permission', dept.label))
        return
    end

    local startedAt = os.time()
    local sessionId = makeAlertId('DUTY', src)
    DutyPlayers[src] = {
        name = name,
        callsign = callsign,
        rank = rank,
        department = data.department,
        sprite = dept.blip.sprite,
        color = dept.blip.color,
        start = startedAt,
        sessionId = sessionId,
        discordId = getDiscordId(src),
        license = getIdentifier(src, 'license'),
        playerName = GetPlayerName(src) or translate('unknown')
    }
    PendingDuty[src] = nil

    syncDutyBlips()

    if Config.Notifications.announceDutyChanges then
        sendNotification(-1, 'success', translate('notification_duty'), translate('officer_on_duty', name, callsign, dept.label))
    end

    sendDepartmentWebhook(data.department, {
        username = 'Duty Logs',
        embeds = {{
            title = 'On Duty',
            description = ('**%s [%s]** began a verified duty session.'):format(name, callsign),
            color = 3066993,
            thumbnail = { url = secureDept.webhookThumbnail },
            fields = {
                { name = 'Officer', value = name, inline = true },
                { name = 'Callsign', value = ('`%s`'):format(callsign), inline = true },
                { name = 'Rank', value = rank, inline = true },
                { name = 'Department', value = ('%s\n`%s`'):format(dept.label, data.department), inline = true },
                { name = 'FiveM Player', value = DutyPlayers[src].playerName, inline = true },
                { name = 'Server ID', value = ('`%s`'):format(src), inline = true },
                { name = 'Discord', value = discordDisplay(src), inline = true },
                { name = 'License Identifier', value = DutyPlayers[src].license and ('`%s`'):format(DutyPlayers[src].license) or 'Unavailable', inline = false },
                { name = 'Session ID', value = ('`%s`'):format(sessionId), inline = true },
                { name = 'Started', value = utcTimestamp(startedAt), inline = true },
                { name = 'Officers Currently On Duty', value = tostring(countDutyPlayers()), inline = true }
            },
            footer = {
                text = 'X1Studios Advanced Duty System',
                icon_url = ServerConfig.FooterIcon
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }}
    })

    TriggerClientEvent('x1s-duty:client:dutyConfirmed', src)
end)

-- ======================
-- OFF DUTY
-- ======================
RegisterNetEvent('x1s-duty:server:offDuty', function()
    local src = getRemoteSource()
    if not src then return end
    local p = DutyPlayers[src]
    if not p then return end

    local deptCfg = Config.Departments[p.department]
    local secureDept = ServerConfig.Departments[p.department]
    local endedAt = os.time()
    local dutyTime = endedAt - p.start

    DutyPlayers[src] = nil
    syncDutyBlips()

    if Config.Notifications.announceDutyChanges then
        sendNotification(-1, 'info', translate('notification_duty'), translate('officer_off_duty', p.name, p.callsign))
    end

    sendDepartmentWebhook(p.department, {
        username = 'Duty Logs',
        embeds = {{
            title = 'Off Duty',
            description = ('**%s [%s]** ended their duty session normally.'):format(p.name, p.callsign),
            color = 15158332,
            thumbnail = { url = secureDept.webhookThumbnail },
            fields = {
                { name = 'Officer', value = p.name, inline = true },
                { name = 'Callsign', value = ('`%s`'):format(p.callsign), inline = true },
                { name = 'Rank', value = p.rank, inline = true },
                { name = 'Department', value = ('%s\n`%s`'):format(deptCfg.label, p.department), inline = true },
                { name = 'FiveM Player', value = p.playerName or translate('unknown'), inline = true },
                { name = 'Server ID', value = ('`%s`'):format(src), inline = true },
                { name = 'Discord', value = p.discordId and ('<@%s>\n`%s`'):format(p.discordId, p.discordId) or 'Not linked', inline = true },
                { name = 'Session ID', value = ('`%s`'):format(p.sessionId or 'Unavailable'), inline = true },
                { name = 'End Reason', value = 'Voluntary off-duty', inline = true },
                { name = 'Started', value = utcTimestamp(p.start), inline = true },
                { name = 'Ended', value = utcTimestamp(endedAt), inline = true },
                { name = 'Total Duty Time', value = formatDuration(dutyTime), inline = true }
            },
            footer = {
                text = 'X1Studios Advanced Duty System',
                icon_url = ServerConfig.FooterIcon
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }}
    })
end)

-- ======================
-- FORCE OFF DUTY
-- ======================
local function sendForceOffResult(src, ok, target, message)
    TriggerClientEvent('x1s-duty:client:forceOffResult', src, {
        ok = ok,
        target = target,
        message = message
    })
end

RegisterNetEvent('x1s-duty:server:forceOffDuty', function(data)
    local src = getRemoteSource()
    if not src then return end
    if type(data) ~= 'table' then
        sendForceOffResult(src, false, nil, translate('invalid_force_request'))
        return
    end

    local target = tonumber(data.id)
    if not target or target % 1 ~= 0 then
        sendForceOffResult(src, false, nil, translate('invalid_officer_id'))
        return
    end

    local p = DutyPlayers[target]
    if not p then
        sendForceOffResult(src, false, target, translate('officer_not_on_duty'))
        return
    end

    local coolingDown = checkCooldown(src, 'forceOff', ServerConfig.Cooldowns.forceOff)
    if coolingDown then
        sendForceOffResult(src, false, target, translate('force_off_wait'))
        return
    end

    local member = getDiscordMember(src)
    local allowedDepartments = getSupervisedDepartments(member)
    if not allowedDepartments[p.department] then
        sendNotification(src, 'error', translate('notification_duty'), translate('force_off_denied'))
        sendForceOffResult(src, false, target, translate('force_off_denied'))
        return
    end

    DutyPlayers[target] = nil
    TriggerClientEvent('x1s-duty:client:forcedOff', target)

    syncDutyBlips()

    sendForceOffResult(src, true, target, translate('force_off_success', p.name, p.callsign))

    local department = Config.Departments[p.department]
    local secureDepartment = ServerConfig.Departments[p.department]
    local endedAt = os.time()
    sendDepartmentWebhook(p.department, {
        username = 'Duty Logs',
        embeds = {{
            title = 'Officer Forced Off Duty',
            description = ('**%s [%s]** was removed from duty by a supervisor.'):format(p.name, p.callsign),
            color = 15105570,
            thumbnail = { url = secureDepartment.webhookThumbnail },
            fields = {
                { name = 'Officer', value = p.name, inline = true },
                { name = 'Callsign / Rank', value = ('`%s` • %s'):format(p.callsign, p.rank), inline = true },
                { name = 'Department', value = department.label, inline = true },
                { name = 'Target Server ID', value = ('`%s`'):format(target), inline = true },
                { name = 'Target Discord', value = p.discordId and ('<@%s>\n`%s`'):format(p.discordId, p.discordId) or 'Not linked', inline = true },
                { name = 'Duty Duration', value = formatDuration(endedAt - p.start), inline = true },
                { name = 'Supervisor', value = GetPlayerName(src) or translate('unknown'), inline = true },
                { name = 'Supervisor Server ID', value = ('`%s`'):format(src), inline = true },
                { name = 'Supervisor Discord', value = discordDisplay(src), inline = true },
                { name = 'Session ID', value = ('`%s`'):format(p.sessionId or 'Unavailable'), inline = true },
                { name = 'Action Time', value = utcTimestamp(endedAt), inline = true }
            },
            footer = {
                text = 'X1Studios Supervisor Audit Log',
                icon_url = ServerConfig.FooterIcon
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', endedAt)
        }}
    })
end)

-- ======================
-- SUPERVISOR MENU
-- ======================
RegisterNetEvent('x1s-duty:server:requestSupervisorMenu', function()
    local src = getRemoteSource()
    if not src then return end
    local coolingDown, remaining = checkCooldown(src, 'supervisorRequest', ServerConfig.Cooldowns.supervisorRequest)
    if coolingDown then
        sendNotification(src, 'warning', translate('notification_duty'), translate('wait_seconds', remaining))
        return
    end

    if isPlaceholder(ServerConfig.BotToken) or isPlaceholder(ServerConfig.GuildID) then
        sendNotification(src, 'error', translate('notification_duty'), translate('supervisor_unavailable'))
        return
    end

    local member = getDiscordMember(src)
    local allowedDepartments = getSupervisedDepartments(member)

    if not next(allowedDepartments) then
        sendNotification(src, 'error', translate('notification_duty'), translate('no_supervisor_access'))
        return
    end

    local list = {}
    for id,v in pairs(DutyPlayers) do
        if allowedDepartments[v.department] then
            list[#list+1]={
                id=id,
                name=v.name,
                callsign=v.callsign,
                rank=v.rank,
                department=v.department,
                time=os.time()-v.start
            }
        end
    end

    TriggerClientEvent('x1s-duty:client:openSupervisor', src, list)
end)

-- ======================
-- 911 DISPATCH SYSTEM
-- ======================

RegisterNetEvent('x1s-duty:server:911Call', function(reason, coords, street)
    local src = getRemoteSource()
    if not src then return end
    reason = cleanString(reason, Config.Emergency.reportMaxLength)
    street = cleanString(street, 96) or translate('unknown_location')
    coords = cleanCoords(coords)
    if not reason or not coords then
        sendNotification(src, 'error', translate('notification_dispatch'), translate('invalid_emergency'))
        return
    end

    local coolingDown, remaining = checkCooldown(src, 'emergencyCall', ServerConfig.Cooldowns.emergencyCall)
    if coolingDown then
        sendNotification(src, 'warning', translate('notification_dispatch'), translate('wait_seconds', remaining))
        return
    end

    local serverCoords = getServerPlayerCoords(src)
    if serverCoords then
        local distance = math.sqrt(
            ((coords.x - serverCoords.x) ^ 2) +
            ((coords.y - serverCoords.y) ^ 2) +
            ((coords.z - serverCoords.z) ^ 2)
        )
        if distance > 200.0 then coords = serverCoords end
    end

    local createdAt = os.time()
    local callerName = GetPlayerName(src) or translate('unknown')
    local alertId = makeAlertId('911', src)
    local notifiedOfficers = countDutyPlayers()

    local payload = {
        alertId = alertId,
        caller = callerName,
        id = src,
        reason = reason,
        street = street,
        coords = coords,
        createdAt = createdAt
    }

    TriggerClientEvent('x1s-duty:client:911Confirmed', src)

    for officer in pairs(DutyPlayers) do
        TriggerClientEvent('x1s-duty:client:received911', officer, payload)
    end

    local roleId = not isPlaceholder(ServerConfig.LEORoleID) and tostring(ServerConfig.LEORoleID) or nil
    local mention = roleId and ("<@&%s>"):format(roleId) or ''

    sendDispatchWebhook({
        content = mention,
        allowed_mentions = { roles = roleId and { roleId } or {} },
        username = '911 Dispatch',
        embeds = {{
            title = '911 Emergency Call',
            description = ('**A new emergency call requires review.**\n%s'):format(reason),
            color = 16711680,
            fields = {
                { name = 'Call Reference', value = ('`%s`'):format(alertId), inline = true },
                { name = 'Caller', value = callerName, inline = true },
                { name = 'Server ID', value = ('`%s`'):format(src), inline = true },
                { name = 'Discord', value = discordDisplay(src), inline = true },
                { name = 'License Identifier', value = getIdentifier(src, 'license') and ('`%s`'):format(getIdentifier(src, 'license')) or 'Unavailable', inline = false },
                { name = 'Reported Location', value = street, inline = false },
                { name = 'Coordinates', value = formatCoordinates(coords), inline = true },
                { name = 'Officers Notified', value = tostring(notifiedOfficers), inline = true },
                { name = 'Received', value = utcTimestamp(createdAt), inline = true },
                { name = 'Emergency Report', value = reason, inline = false }
            },
            footer = {
                text = 'X1Studios Dispatch System • Verify all caller-supplied information',
                icon_url = ServerConfig.FooterIcon
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', createdAt)
        }}
    })

    print(('[911:%s] %s [%s] @ %s -> %s'):format(alertId, callerName, src, street, reason))
end)

-- ======================
-- PANIC BUTTON SYSTEM
-- ======================

RegisterNetEvent('x1s-duty:server:panic', function(coords, street)
    local src = getRemoteSource()
    if not src then return end
    local officer = DutyPlayers[src]

    if not officer then
        sendNotification(src, 'error', translate('notification_panic'), translate('must_be_on_duty'))
        return
    end

    coords = cleanCoords(coords)
    street = cleanString(street, 96) or translate('unknown_location')
    if not coords then
        sendNotification(src, 'error', translate('notification_panic'), translate('invalid_panic'))
        return
    end

    local coolingDown, remaining = checkCooldown(src, 'panic', ServerConfig.Cooldowns.panic)
    if coolingDown then
        sendNotification(src, 'warning', translate('notification_panic'), translate('wait_seconds', remaining))
        return
    end

    local serverCoords = getServerPlayerCoords(src)
    if serverCoords then coords = serverCoords end

    local createdAt = os.time()
    local alertId = makeAlertId('PANIC', src)
    local name = officer.name or translate('unknown')
    local callsign = officer.callsign or '000'
    local department = Config.Departments[officer.department]
    local notifiedOfficers = countDutyPlayers()

    local payload = {
        alertId = alertId,
        name = name,
        callsign = callsign,
        rank = officer.rank,
        department = officer.department,
        departmentLabel = department and department.label or officer.department,
        id = src,
        coords = coords,
        street = street,
        createdAt = createdAt
    }

    -- The server roster is authoritative. Alert every on-duty officer, including
    -- the activating officer, so a single-officer shift still receives feedback.
    for id in pairs(DutyPlayers) do
        TriggerClientEvent('x1s-duty:client:receivedPanic', id, payload)
    end
    TriggerClientEvent('x1s-duty:client:panicConfirmed', src)

    local roleId = not isPlaceholder(ServerConfig.LEORoleID) and tostring(ServerConfig.LEORoleID) or nil
    local mention = roleId and ("<@&%s>"):format(roleId) or ''

    sendPanicWebhook({
        content = mention,
        allowed_mentions = { roles = roleId and { roleId } or {} },
        username = 'Officer Panic Alerts',
        embeds = {{
            title = 'OFFICER PANIC ACTIVATED',
            description = ('**Immediate assistance requested by %s [%s].**'):format(name, callsign),
            color = 16711680,
            fields = {
                { name = 'Alert Reference', value = ('`%s`'):format(alertId), inline = true },
                { name = 'Officer', value = name, inline = true },
                { name = 'Callsign', value = ('`%s`'):format(callsign), inline = true },
                { name = 'Rank', value = officer.rank or translate('unknown'), inline = true },
                { name = 'Department', value = department and ('%s\n`%s`'):format(department.label, officer.department) or officer.department, inline = true },
                { name = 'Server ID', value = ('`%s`'):format(src), inline = true },
                { name = 'FiveM Player', value = GetPlayerName(src) or translate('unknown'), inline = true },
                { name = 'Discord', value = discordDisplay(src), inline = true },
                { name = 'Duty Session', value = ('`%s`'):format(officer.sessionId or 'Unavailable'), inline = true },
                { name = 'Location', value = street, inline = false },
                { name = 'Coordinates', value = formatCoordinates(coords), inline = true },
                { name = 'Officers Alerted', value = tostring(notifiedOfficers), inline = true },
                { name = 'Activated', value = utcTimestamp(createdAt), inline = true }
            },
            footer = {
                text = 'X1Studios Panic System • Priority officer-assistance alert',
                icon_url = ServerConfig.FooterIcon
            },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', createdAt)
        }}
    })

    print(('[PANIC:%s] %s [%s] @ %s -> %s officer client(s)'):format(
        alertId,
        name,
        callsign,
        street,
        notifiedOfficers
    ))
end)

-- ======================
-- DISCONNECT HANDLER
-- ======================
AddEventHandler('playerDropped', function(reason)
    local src = source
    local p = DutyPlayers[src]
    local disconnectReason = cleanString(reason, 160) or 'Unknown'
    PendingDuty[src] = nil
    Cooldowns[src] = nil

    if p then
        local deptCfg = Config.Departments[p.department]
        local secureDept = ServerConfig.Departments[p.department]
        local endedAt = os.time()
        local dutyTime = endedAt - p.start

        -- remove from duty
        DutyPlayers[src] = nil
        syncDutyBlips()

        -- send chat (optional, you can remove this if you don’t want global spam)
        if Config.Notifications.announceDutyChanges then
            sendNotification(
                -1,
                'warning',
                translate('notification_duty'),
                translate('officer_disconnected', p.name, p.callsign)
            )
        end

        -- send webhook
        sendDepartmentWebhook(p.department, {
            username = 'Duty Logs',
            embeds = {{
                title = 'Disconnected While On Duty',
                description = ('**%s [%s]** disconnected during an active duty session.'):format(p.name, p.callsign),
                color = 16753920, -- orange
                thumbnail = { url = secureDept.webhookThumbnail },
                fields = {
                    { name = 'Officer', value = p.name, inline = true },
                    { name = 'Callsign / Rank', value = ('`%s` - %s'):format(p.callsign, p.rank), inline = true },
                    { name = 'Department', value = ('%s\n`%s`'):format(deptCfg.label, p.department), inline = true },
                    { name = 'FiveM Player', value = p.playerName or translate('unknown'), inline = true },
                    { name = 'Server ID', value = ('`%s`'):format(src), inline = true },
                    { name = 'Discord', value = p.discordId and ('<@%s>\n`%s`'):format(p.discordId, p.discordId) or 'Not linked', inline = true },
                    { name = 'Session ID', value = ('`%s`'):format(p.sessionId or 'Unavailable'), inline = true },
                    { name = 'Started', value = utcTimestamp(p.start), inline = true },
                    { name = 'Disconnected', value = utcTimestamp(endedAt), inline = true },
                    { name = 'Total Duty Time', value = formatDuration(dutyTime), inline = true },
                    { name = 'Disconnect Reason', value = disconnectReason, inline = false }
                },
                footer = {
                    text = "X1Studios Advanced Duty System",
                    icon_url = ServerConfig.FooterIcon
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', endedAt)
            }}
        })

        print(("[DUTY-DISCONNECT] %s [%s] (%s) disconnected while on duty")
            :format(p.name, p.callsign, deptCfg.label))
    end
end)

-- ======================
-- Update Checker
-- ======================
local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, 'version', 0)

local versionUrl = "https://raw.githubusercontent.com/X1Studios/X1Studios-Advanced-Duty-System/main/version.txt"

local function checkForUpdates()
    PerformHttpRequest(versionUrl, function(statusCode, responseText)
        if statusCode ~= 200 or type(responseText) ~= 'string' then
            print('^1[Update Checker] Unable to check for updates (HTTP Error ' .. tostring(statusCode) .. ')^0')
            return
        end

        local latestVersion = responseText:gsub('%s+', '')
        if latestVersion == '' then
            print('^1[Update Checker] The update server returned an empty version.^0')
            return
        end

        if latestVersion == currentVersion then
            print('^2[Update Checker] ' .. resourceName .. ' is up to date! (v' .. currentVersion .. ')^0')
        else
            print('^3-------------------------------------------------------^0')
            print('^1[Update Checker] Update available for ' .. resourceName .. '!^0')
            print('^3Current Version:^0 ' .. currentVersion)
            print('^2Latest Version:^0 ' .. latestVersion)
            print('^5Download:^0 https://github.com/X1Studios/X1Studios-Advanced-Duty-System')
            print('^3-------------------------------------------------------^0')
        end
    end, 'GET')
end

CreateThread(function()
    Wait(3000)
    checkForUpdates()
end)
