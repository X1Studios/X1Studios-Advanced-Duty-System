Config = {}

Config.FooterIcon = "https://imgur.com/G4WAX8q.png"

Config.BotToken = "BOT_TOKEN_HERE"
Config.GuildID = "GUILD_ID_HERE"

Config.Webhooks = {
    LSPD = "WEBHOOK_LINK_HERE",
    BCSO = "WEBHOOK_LINK_HERE",
    SAST = "WEBHOOK_LINK_HERE",
    SAGW = "WEBHOOK_LINK_HERE"
}

Config.DispatchWebhook = "WEBHOOK_LINK_HERE"
Config.LEORoleID = "ROLEID_HERE" -- discord role ID to ping

Config.Departments = {
    LSPD = {
        label = "Los Santos Police Department",
        dutyRole = "LSPD_ROLE_ID",
        supervisorRole = "LSPD_SUPERVISOR_ROLE_ID",
        blip = { sprite = 672, color = 38 },
        webhookThumbnail = "https://i.imgur.com/PCRR7pN.png"
    },

    BCSO = {
        label = "Blaine County Sheriffs Office",
        dutyRole = "BCSO_ROLE_ID",
        supervisorRole = "BCSO_SUPERVISOR_ROLE_ID",
        blip = { sprite = 672, color = 47 },
        webhookThumbnail = "https://i.imgur.com/MWL8fOL.png"
    },

    SAST = {
        label = "San Andreas State Troopers",
        dutyRole = "SAST_ROLE_ID",
        supervisorRole = "SAST_SUPERVISOR_ROLE_ID",
        blip = { sprite = 672, color = 26 },
        webhookThumbnail = "https://i.imgur.com/qwjPGhj.png"
    },

    SAGW = {
        label = "San Andreas Game Warden",
        dutyRole = "SAGW_ROLE_ID",
        supervisorRole = "SAGW_SUPERVISOR_ROLE_ID",
        blip = { sprite = 672, color = 25 },
        webhookThumbnail = "https://imgur.com/DbT5klb.png"
    }
}

