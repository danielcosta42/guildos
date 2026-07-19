----------------------------------------------------------------------
-- Guild OS - enUS (master list)
-- English is the canonical key language, so entries map each key to itself.
-- This file is the authoritative list of every translatable string; loads
-- unconditionally. Translators copy keys from here into their locale file.
----------------------------------------------------------------------
local L = BRutus.L

-- Populated during i18n conversion.
local _ = L

-- Core/Commands.lua
L["Banned "] = "Banned "
L["Unbanned "] = "Unbanned "
L["Temp-banned "] = "Temp-banned "
L[" days)"] = " days)"
L["Usage: /gos ban <name> [reason]"] = "Usage: /gos ban <name> [reason]"
L["Usage: /gos tempban <name> <days> [reason]"] = "Usage: /gos tempban <name> <days> [reason]"

-- Modules/BanList.lua
L["Banned %s (%s) — banned by %s on %s"] = "Banned %s (%s) — banned by %s on %s"
L["BANNED"] = "BANNED"
L["(no reason)"] = "(no reason)"
