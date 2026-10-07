----------------------------------------------------------------------
-- Guild OS - Localization bootstrap
--
-- GuildOS.L is the translation table. KEYS are the canonical ENGLISH
-- strings used directly in the source (e.g. L["Roster"]). A missing key
-- falls back to the key itself, so:
--   * English is the implicit default,
--   * any untranslated string degrades gracefully to English (never nil).
--
-- Locale data files: enUS, ptBR, esES (also esMX), deDE, frFR, ruRU, koKR, zhCN, zhTW --
-- every language the game runs in (#104), checked by tools/locales.lua
-- populate GuildOS.L. enUS.lua loads unconditionally (the master list);
-- every other locale file early-returns unless GetLocale() matches and
-- then overrides only the keys it translates.
--
-- Loaded right after Config.lua so every later file can safely do
--   local L = GuildOS.L
----------------------------------------------------------------------

GuildOS.L = setmetatable({}, {
    __index = function(_, key)
        -- Untranslated → show the English key verbatim (never nil).
        return key
    end,
})

-- Active client locale (e.g. "enUS", "ptBR", "deDE"). Exposed for any
-- locale-specific behaviour beyond simple string lookups.
GuildOS.Locale = (GetLocale and GetLocale()) or "enUS"
