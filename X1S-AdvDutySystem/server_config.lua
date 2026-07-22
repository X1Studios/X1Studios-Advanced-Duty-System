ServerConfig = {
    BotToken = GetConvar('x1s_bot_token', 'BOT_TOKEN_HERE'),
    GuildID = GetConvar('x1s_guild_id', 'GUILD_ID_HERE'),
    FooterIcon = 'https://imgur.com/G4WAX8q.png',
    LEORoleID = GetConvar('x1s_leo_role_id', 'ROLE_ID_HERE'),

    Webhooks = {
        LSPD = GetConvar('x1s_lspd_webhook', 'WEBHOOK_LINK_HERE'),
        BCSO = GetConvar('x1s_bcso_webhook', 'WEBHOOK_LINK_HERE'),
        SAST = GetConvar('x1s_sast_webhook', 'WEBHOOK_LINK_HERE'),
        SAGW = GetConvar('x1s_sagw_webhook', 'WEBHOOK_LINK_HERE')
    },
    DispatchWebhook = GetConvar('x1s_dispatch_webhook', 'WEBHOOK_LINK_HERE'),
    PanicWebhook = GetConvar('x1s_panic_webhook', 'WEBHOOK_LINK_HERE'),

    Departments = {
        LSPD = {
            dutyRole = GetConvar('x1s_lspd_duty_role', 'ROLE_ID_HERE'),
            supervisorRole = GetConvar('x1s_lspd_supervisor_role', 'ROLE_ID_HERE'),
            webhookThumbnail = 'https://i.imgur.com/PCRR7pN.png'
        },
        BCSO = {
            dutyRole = GetConvar('x1s_bcso_duty_role', 'ROLE_ID_HERE'),
            supervisorRole = GetConvar('x1s_bcso_supervisor_role', 'ROLE_ID_HERE'),
            webhookThumbnail = 'https://i.imgur.com/MWL8fOL.png'
        },
        SAST = {
            dutyRole = GetConvar('x1s_sast_duty_role', 'ROLE_ID_HERE'),
            supervisorRole = GetConvar('x1s_sast_supervisor_role', 'ROLE_ID_HERE'),
            webhookThumbnail = 'https://i.imgur.com/qwjPGhj.png'
        },
        SAGW = {
            dutyRole = GetConvar('x1s_sagw_duty_role', 'ROLE_ID_HERE'),
            supervisorRole = GetConvar('x1s_sagw_supervisor_role', 'ROLE_ID_HERE'),
            webhookThumbnail = 'https://imgur.com/DbT5klb.png'
        }
    },

    Cooldowns = {
        emergencyCall = 30,
        panic = 15,
        dutyRequest = 5,
        supervisorRequest = 3,
        forceOff = 2
    }
}
