local DutyPlayers = {}

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    print([[
 __   __  __   ____  
 \ \ / / /_ | / ___| 
  \ V /   | | \___ \ 
  / _ \   | |  ___) |
 /_/ \_\  |_| |____/ 

      X1Studios Advanced Duty System
    ]])
end)

-- ======================
-- WEBHOOK HELPER
-- ======================
local function SendDeptWebhook(department, payload)
    local webhook = Config.Webhooks[department]
    if not webhook or webhook == "" then return end

    PerformHttpRequest(
        webhook,
        function() end,
        'POST',
        json.encode(payload),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ======================
-- CHAT HELPER
-- ======================
local function SendChat(target, prefix, message, color)
    TriggerClientEvent('chat:addMessage', target, {
        color = color or {255, 255, 255},
        args = { prefix, message }
    })
end

-- ======================
-- DISCORD UTIL
-- ======================
local function GetDiscordID(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == "discord:" then
            return identifier:sub(9)
        end
    end
    return nil
end

local function DiscordRequest(endpoint)
    local p = promise.new()

    PerformHttpRequest(
        'https://discord.com/api/' .. endpoint,
        function(code, data)
            if code == 200 and data then
                p:resolve(json.decode(data))
            else
                p:resolve(nil)
            end
        end,
        'GET',
        '',
        {
            ['Authorization'] = 'Bot ' .. Config.BotToken,
            ['Content-Type'] = 'application/json'
        }
    )

    return Citizen.Await(p)
end

-- ======================
-- ROLE CHECK
-- ======================
local function HasRole(roleId, member)
    if not roleId or not member or not member.roles then return false end

    for _, userRole in ipairs(member.roles) do
        if tostring(userRole) == tostring(roleId) then
            return true
        end
    end

    return false
end

-- ======================
-- ON DUTY
-- ======================
RegisterNetEvent('x1s-duty:onDuty', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local dept = Config.Departments[data.department]
    if not dept then
        TriggerClientEvent('x1s-duty:dutyDenied', src)
        return
    end

    if DutyPlayers[src] then
        SendChat(src, 'Duty', 'You are already on duty.', {255, 165, 0})
        TriggerClientEvent('x1s-duty:dutyDenied', src)
        return
    end

    local discord = GetDiscordID(src)
    if not discord then
        SendChat(src, 'Duty', 'Discord not detected.', {255, 0, 0})
        TriggerClientEvent('x1s-duty:dutyDenied', src)
        return
    end

    local member = DiscordRequest(
        ('guilds/%s/members/%s'):format(Config.GuildID, discord)
    )

    if not member then
        SendChat(src, 'Duty', 'Failed to verify Discord roles.', {255, 0, 0})
        TriggerClientEvent('x1s-duty:dutyDenied', src)
        return
    end

    if not HasRole(dept.dutyRole, member) then
        SendChat(
            src,
            'Duty',
            ('You do not have permission to go on duty for %s.'):format(dept.label),
            {255, 0, 0}
        )
        TriggerClientEvent('x1s-duty:dutyDenied', src)
        return
    end

    DutyPlayers[src] = {
        name = data.name,
        callsign = data.callsign,
        rank = data.rank,
        department = data.department,
        start = os.time()
    }

    TriggerClientEvent('x1s-duty:addBlip', -1, src, {
        sprite = dept.blip.sprite,
        color = dept.blip.color,
        name = data.name,
        callsign = data.callsign
    })

    SendChat(
        -1,
        'Duty',
        ("%s [%s] is now ON DUTY (%s)")
            :format(data.name, data.callsign, dept.label),
        {0, 255, 0}
    )

    SendDeptWebhook(data.department, {
        username = 'Duty Logs',
        embeds = {
            {
                title = '🟢 On Duty',
                color = 3066993,
                thumbnail = { url = dept.webhookThumbnail },
                fields = {
                    { name = 'Name', value = data.name, inline = true },
                    { name = 'Callsign', value = data.callsign, inline = true },
                    { name = 'Rank', value = data.rank, inline = true },
                    { name = 'Department', value = dept.label, inline = true },
                    { name = 'Server ID', value = tostring(src), inline = true }
                },
                footer = {
                    text = 'X1Studios Advanced Duty System',
                    icon_url = Config.FooterIcon
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    })

    TriggerClientEvent('x1s-duty:dutyConfirmed', src)
end)

-- ======================
-- OFF DUTY
-- ======================
RegisterNetEvent('x1s-duty:offDuty', function()
    local src = source
    local p = DutyPlayers[src]
    if not p then return end

    local deptCfg = Config.Departments[p.department]
    local dutyTime = math.floor((os.time() - p.start) / 60)

    DutyPlayers[src] = nil
    TriggerClientEvent('x1s-duty:removeBlip', -1, src)

    SendChat(
        -1,
        'Duty',
        p.name .. ' [' .. p.callsign .. '] is now OFF DUTY',
        {255, 0, 0}
    )

    SendDeptWebhook(p.department, {
        username = 'Duty Logs',
        embeds = {
            {
                title = '🔴 Off Duty',
                color = 15158332,
                thumbnail = { url = dept.webhookThumbnail },
                fields = {
                    { name = 'Name', value = p.name, inline = true },
                    { name = 'Callsign', value = p.callsign, inline = true },
                    { name = 'Department', value = deptCfg.label, inline = true },
                    { name = 'Time on Duty', value = dutyTime .. ' minutes', inline = true }
                },
                footer = {
                    text = 'X1Studios Advanced Duty System',
                    icon_url = Config.FooterIcon
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    })
end)

-- ======================
-- SUPERVISOR MENU
-- ======================
RegisterNetEvent('x1s-duty:requestSupervisorMenu', function()
    local src = source
    local discord = GetDiscordID(src)
    if not discord then return end

    local member = DiscordRequest(
        ('guilds/%s/members/%s'):format(Config.GuildID, discord)
    )
    if not member then return end

    local allowedDepartments = {}

    for deptId, dept in pairs(Config.Departments) do
        if HasRole(dept.supervisorRole, member) then
            allowedDepartments[deptId] = true
        end
    end

    if not next(allowedDepartments) then
        SendChat(src, 'Duty', 'You do not have access to the supervisor menu.', {255, 0, 0})
        return
    end

    local list = {}

    for id, v in pairs(DutyPlayers) do
        if allowedDepartments[v.department] then
            list[#list + 1] = {
                id = id,
                name = v.name,
                callsign = v.callsign,
                rank = v.rank,
                department = v.department,
                time = os.time() - v.start
            }
        end
    end

    TriggerClientEvent('x1s-duty:openSupervisor', src, list)
end)

RegisterNetEvent('x1s-duty:refreshSupervisor', function()
    TriggerEvent('x1s-duty:requestSupervisorMenu', source)
end)

-- ======================
-- FORCE OFF DUTY
-- ======================
RegisterNetEvent('x1s-duty:forceOffDuty', function(data)
    local src = source
    if type(data) ~= 'table' or type(data.id) ~= 'number' then return end

    local target = data.id
    local p = DutyPlayers[target]
    if not p then return end

    local discord = GetDiscordID(src)
    if not discord then return end

    local member = DiscordRequest(
        ('guilds/%s/members/%s'):format(Config.GuildID, discord)
    )
    if not member then return end

    local deptCfg = Config.Departments[p.department]
    if not deptCfg then return end

    if not HasRole(deptCfg.supervisorRole, member) then
        SendChat(src, 'Duty', 'You do not have permission to do that.', {255, 0, 0})
        return end

    DutyPlayers[target] = nil
    TriggerClientEvent('x1s-duty:removeBlip', -1, target)
    TriggerClientEvent('x1s-duty:forcedOff', target)

    SendChat(
        src,
        'Duty',
        ("Successfully forced %s [%s] off duty."):format(p.name, p.callsign),
        {255, 165, 0}
    )

    SendDeptWebhook(p.department, {
        username = 'Department Supervisor',
        embeds = {
            {
                title = '🚨 Forced Off Duty',
                color = 16753920,
                thumbnail = { url = dept.webhookThumbnail },
                fields = {
                    { name = 'Officer', value = p.name .. ' [' .. p.callsign .. ']', inline = true },
                    { name = 'Department', value = deptCfg.label, inline = true },
                    { name = 'Supervisor', value = GetPlayerName(src), inline = true }
                },
                footer = {
                    text = 'X1Studios Advanced Duty System',
                    icon_url = Config.FooterIcon
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    })
end)

-- ======================
-- CLEANUP
-- ======================
AddEventHandler('playerDropped', function()
    local src = source
    if DutyPlayers[src] then
        DutyPlayers[src] = nil
        TriggerClientEvent('x1s-duty:removeBlip', -1, src)
    end
end)
