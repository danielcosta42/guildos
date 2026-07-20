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

-- UI/ManagementPanel.lua
L["Ban List"] = "Ban List"
L["Ban"] = "Ban"
L["No bans."] = "No bans."
L["BANNED PLAYERS"] = "BANNED PLAYERS"
L["Blocked from auto-invite. You're alerted when a banned player rejoins the guild or whispers you."] = "Blocked from auto-invite. You're alerted when a banned player rejoins the guild or whispers you."
L["Player"] = "Player"
L["Reason"] = "Reason"
L["Temporary"] = "Temporary"
L["days"] = "days"
L["Ban player"] = "Ban player"
L["Enter a positive number of days for a temporary ban."] = "Enter a positive number of days for a temporary ban."
L["Filter"] = "Filter"
L["PLAYER"] = "PLAYER"
L["REASON"] = "REASON"
L["BY"] = "BY"
L["EXPIRES"] = "EXPIRES"
L["permanent"] = "permanent"
L["(expired)"] = "(expired)"
L["No banned players yet. Add one above to block them."] = "No banned players yet. Add one above to block them."

-- Modules/RecruitmentSystem.lua
L["Auto-invited |cffFFFFFF%s|r to the guild."] = "Auto-invited |cffFFFFFF%s|r to the guild."
L["Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"] = "Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"
L["Auto-invite |cffFF4444disabled|r."] = "Auto-invite |cffFF4444disabled|r."
L["Auto-invite keyword set to |cffFFFFFF"] = "Auto-invite keyword set to |cffFFFFFF"
L["Current keyword: |cffFFFFFF"] = "Current keyword: |cffFFFFFF"
L["Auto-invite: "] = "Auto-invite: "
L[" · keyword: |cffFFFFFF"] = " · keyword: |cffFFFFFF"
L["|r · min level: |cffFFFFFF"] = "|r · min level: |cffFFFFFF"
L["Usage: /gos autoinvite <on|off|keyword|minlevel|class|status>"] = "Usage: /gos autoinvite <on|off|keyword|minlevel|class|status>"
L["Auto-invite min level set to |cffFFFFFF%d|r."] = "Auto-invite min level set to |cffFFFFFF%d|r."
L["Usage: /gos autoinvite minlevel <0-70>"] = "Usage: /gos autoinvite minlevel <0-70>"
L["Auto-invite class filter cleared."] = "Auto-invite class filter cleared."
L["Auto-invite class filter updated."] = "Auto-invite class filter updated."
L["Usage: /gos autoinvite class <add|remove|clear> <CLASS>"] = "Usage: /gos autoinvite class <add|remove|clear> <CLASS>"
L["Auto-invite is available to officers after login."] = "Auto-invite is available to officers after login."

-- UI/FeaturePanels.lua
L["AUTO-INVITE"] = "AUTO-INVITE"
L["Auto-invite players who whisper the keyword"] = "Auto-invite players who whisper the keyword"
L["Keyword & level/class filters: /gos autoinvite. Banned players are never invited."] = "Keyword & level/class filters: /gos autoinvite. Banned players are never invited."

-- UI/ManagementPanel.lua (RosterLog Audit Log)
L["Audit Log"] = "Audit Log"
L["Joined"] = "Joined"
L["Left"] = "Left"

-- Modules/Digest.lua (RosterLog audit counts)
L["%d member(s) removed"] = "%d member(s) removed"
L["%d member(s) left"] = "%d member(s) left"
