Config = {}

Config.Locale = 'en' -- Supported: en, es, fr

Config.Notifications = {
    position = 'top-right', -- top-right, top-left, bottom-right, bottom-left
    duration = 5500,
    dispatchDuration = 10000,
    panicDuration = 12000,
    maxVisible = 5,
    sound = true,
    announceDutyChanges = true
}

Config.Emergency = {
    reportMaxLength = 256,
    blipDuration = 120000
}

Config.Panic = {
    blipDuration = 120000
}

Config.Sync = {
    coordinateUpdateInterval = 2000,
    blipBroadcastInterval = 2000
}

Config.Departments = {
    LSPD = {
        label = "Los Santos Police Department",
        blip = { sprite = 672, color = 38 }
    },

    BCSO = {
        label = "Blaine County Sheriffs Office",
        blip = { sprite = 672, color = 47 }
    },

    SAST = {
        label = "San Andreas State Troopers",
        blip = { sprite = 672, color = 26 }
    },

    SAGW = {
        label = "San Andreas Game Warden",
        blip = { sprite = 672, color = 25 }
    }
}

-- !!!! ROLES AND WEBHOOKS WERE MOVED TO "server_config.lua" FOR SECURITY REASON !!!!

-- !!! DO NOT TOUCH ANYTHING BELOW THIS IT WILL BREAK EVERYTHING !!!

local localePath = 'locales.json'
local rawLocales = LoadResourceFile(GetCurrentResourceName(), localePath)
assert(rawLocales, ('[X1S] Unable to read %s. Ensure it is included in fxmanifest.lua.'):format(localePath))

local decodeSucceeded, decodedLocales = pcall(json.decode, rawLocales)
assert(
    decodeSucceeded and type(decodedLocales) == 'table',
    ('[X1S] %s contains invalid JSON.'):format(localePath)
)
assert(type(decodedLocales.en) == 'table', '[X1S] locales.json must contain an English fallback.')
assert(
    type(decodedLocales[Config.Locale]) == 'table',
    ('[X1S] Unsupported locale: %s'):format(tostring(Config.Locale))
)

local function countFormatPlaceholders(value)
    local _, count = value:gsub('%%s', '')
    return count
end

for localeName, locale in pairs(decodedLocales) do
    assert(type(locale) == 'table', ('[X1S] Locale %s must be an object.'):format(tostring(localeName)))

    for key, englishValue in pairs(decodedLocales.en) do
        local translatedValue = locale[key]
        assert(
            type(translatedValue) == 'string',
            ('[X1S] Locale %s is missing string key %s.'):format(tostring(localeName), key)
        )
        assert(
            countFormatPlaceholders(translatedValue) == countFormatPlaceholders(englishValue),
            ('[X1S] Locale %s has invalid format placeholders for key %s.'):format(tostring(localeName), key)
        )
    end

    for key in pairs(locale) do
        assert(
            type(decodedLocales.en[key]) == 'string',
            ('[X1S] Locale %s contains unknown key %s.'):format(tostring(localeName), key)
        )
    end
end

Locales = decodedLocales
X1S = X1S or {}

function X1S.Translate(key, ...)
    local selectedLocale = Locales[Config.Locale]
    local value = selectedLocale[key] or Locales.en[key] or key
    if select('#', ...) == 0 then return value end

    local formatSucceeded, translated = pcall(string.format, value, ...)
    if not formatSucceeded then
        print(('^3[X1S] Translation format failed for key %s in locale %s.^0'):format(key, Config.Locale))
        return value
    end

    return translated
end
