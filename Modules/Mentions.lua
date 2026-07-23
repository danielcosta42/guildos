----------------------------------------------------------------------
-- Guild OS - Mentions / Watch-words
-- Alerts you when your name (or a watch-word) appears in guild/officer
-- chat. Personal, no sync. Keeps a small capped recent-mentions log.
----------------------------------------------------------------------
local Mentions = {}
BRutus.Mentions = Mentions
local L = BRutus.L

local LOG_MAX = 100
local MIN_WORD = 3      -- shorter watch-words fire on nearly every message

Mentions.DEFAULTS = {
    enabled   = true,
    ownName   = true,
    watchWords= {},
    sound     = true,
    guild     = true,
    officer   = true,
}

function Mentions:Initialize()
    BRutus.db.mentions = BRutus.db.mentions or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.mentions[k] == nil then
            BRutus.db.mentions[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    BRutus.db.mentions.log = BRutus.db.mentions.log or {}
    self._cd = {}
    self._hinted = false
    self:_SetupHook()
    self:_RegisterTests()
end

-- Split on SEPARATORS (whitespace, punctuation, control chars) rather than on
-- "not alphanumeric": %w rejects every UTF-8 byte >= 0x80 in the C locale, so
-- the old "[^%w]" pass turned the accents in Jurgen/Bjorn/Jose into spaces on
-- the haystack while the needle kept them, and the match could never land.
-- Runs of separators collapse to one space so "mc-run" still matches "mc - run".
local function normWords(s)
    local t = s:lower():gsub("[%s%p%c]+", " ")
    t = t:gsub("^ ", ""):gsub(" $", "")
    return " " .. t .. " "
end

-- whole-word, case-insensitive: normalize BOTH sides the same way, then look
-- for " needle " inside " haystack ".
local function hasWord(hay, needle)
    if not hay or not needle then return false end
    local n = normWords(needle)
    -- A needle made only of separators would normalize to "  " and match any
    -- haystack; treat it as matching nothing instead.
    if not n:find("[^ ]") then return false end
    return normWords(hay):find(n, 1, true) ~= nil
end

-- Pure: append `phrase` to `list`. Returns status ("ok"|"short"|"dupe") and the
-- normalized phrase. Dedupe is case-insensitive against what is already stored.
function Mentions:_AddWatchWord(list, phrase)
    local p = strtrim(tostring(phrase or "")):lower()
    if #p < MIN_WORD then return "short", p end
    for _, w in ipairs(list) do
        if tostring(w):lower() == p then return "dupe", p end
    end
    list[#list + 1] = p
    return "ok", p
end

function Mentions:_Match(msg, ownName, watchWords, watchOwn)
    if not msg then return nil end
    if watchOwn and ownName and ownName ~= "" and hasWord(msg, ownName) then return ownName end
    for _, w in ipairs(watchWords or {}) do
        if w and w ~= "" and hasWord(msg, w) then return w end
    end
    return nil
end

function Mentions:_Record(term, sender, msg)
    local log = BRutus.db.mentions.log
    table.insert(log, 1, { term = term, sender = sender, msg = msg, ts = GetServerTime() })
    while #log > LOG_MAX do table.remove(log) end
end

function Mentions:_SetupHook()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_GUILD")
    f:RegisterEvent("CHAT_MSG_OFFICER")
    f:SetScript("OnEvent", function(_, event, msg, author)
        local cfg = BRutus.db.mentions
        if not cfg or not cfg.enabled then return end
        if event == "CHAT_MSG_GUILD" and not cfg.guild then return end
        if event == "CHAT_MSG_OFFICER" and not cfg.officer then return end
        local me = UnitName("player")
        local sender = author and (author:match("^([^-]+)") or author)
        if sender == me then return end     -- don't alert on your own messages
        local term = Mentions:_Match(msg, me, cfg.watchWords, cfg.ownName)
        if not term then return end
        -- per (sender+term) cooldown so one burst doesn't spam
        local key = (sender or "?") .. "|" .. term
        if Mentions._cd[key] then return end
        Mentions._cd[key] = true
        BRutus.Compat.After(5, function() Mentions._cd[key] = nil end)
        Mentions:_Record(term, sender, msg)
        BRutus:Print(string.format(L["|cffFFD700Mention|r (%s): %s: %s"], term, sender or "?", msg))
        if cfg.sound and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
        -- Own-name matching is on by default and there is no settings UI for it,
        -- so a player called Tank/Ally/Lol would get alerted on normal guild
        -- chatter with no idea where it came from. Point at the off switch once
        -- per session (flag set first, so later alerts stay quiet).
        if not Mentions._hinted then
            Mentions._hinted = true
            BRutus:Print(L["Tip: turn these off with /gos mentions ownname off, /gos mentions sound off, or /gos mentions off."])
        end
    end)
end

function Mentions:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("mentions.ownname", function()
        if Mentions:_Match("hey Bob can you inv?", "Bob", {}, true) ~= "Bob" then return false, "own name" end
        if Mentions:_Match("Bobby says hi", "Bob", {}, true) ~= nil then return false, "whole-word only" end
        return true
    end)
    S:Register("mentions.watchword", function()
        if Mentions:_Match("who wants to run SP?", "X", { "sp" }, false) ~= "sp" then return false, "watch-word" end
        return true
    end)
    S:Register("mentions.no_own_when_off", function()
        if Mentions:_Match("hey Bob", "Bob", {}, false) ~= nil then return false, "ownName off => nil" end
        return true
    end)
    S:Register("mentions.case_insensitive", function()
        if Mentions:_Match("HEY BOB", "bob", {}, true) ~= "bob" then return false, "case" end
        return true
    end)
    S:Register("mentions.punctuation_needle", function()
        -- Both sides normalize the same way, so an apostrophe/hyphen in the
        -- watch-word still lands (it used to be a guaranteed silent no-op).
        if Mentions:_Match("anyone for Kel'Thuzad?", "X", { "kel'thuzad" }, false) ~= "kel'thuzad" then
            return false, "apostrophe"
        end
        if Mentions:_Match("lf1m mc-run", "X", { "mc-run" }, false) ~= "mc-run" then
            return false, "hyphen"
        end
        -- Whole-word matching must not regress.
        if Mentions:_Match("Bobby says hi", "Bob", {}, true) ~= nil then return false, "Bobby is not Bob" end
        -- A needle of pure punctuation must match nothing, not everything.
        if Mentions:_Match("hello there", "X", { "!!!" }, false) ~= nil then return false, "punct-only needle" end
        return true
    end)
    S:Register("mentions.high_bytes", function()
        -- "Jose" with an accented e: \195\169 must survive on BOTH sides.
        local jose = "Jos\195\169"
        if Mentions:_Match("hey " .. jose .. " inv?", jose, {}, true) ~= jose then return false, "accented own name" end
        return true
    end)
    S:Register("mentions.add_watchword", function()
        local list = {}
        local st, norm = Mentions:_AddWatchWord(list, "need heals")
        if st ~= "ok" or norm ~= "need heals" then return false, "phrase not kept whole" end
        if #list ~= 1 then return false, "not stored" end
        st = Mentions:_AddWatchWord(list, "NEED HEALS")
        if st ~= "dupe" or #list ~= 1 then return false, "case-insensitive dedupe" end
        st = Mentions:_AddWatchWord(list, "a")
        if st ~= "short" or #list ~= 1 then return false, "min length" end
        return true
    end)
end

function Mentions:HandleCommand(args)
    local cfg = BRutus.db.mentions
    if not cfg then return end
    local sub = args[1]
    if sub == "on" then cfg.enabled = true; BRutus:Print(L["Mentions |cff4CFF4Con|r."])
    elseif sub == "off" then cfg.enabled = false; BRutus:Print(L["Mentions |cffFF4444off|r."])
    elseif sub == "ownname" and (args[2] == "on" or args[2] == "off") then
        cfg.ownName = (args[2] == "on")
        BRutus:Print(L["Own-name alerts: "] .. (cfg.ownName and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]))
    elseif sub == "sound" and (args[2] == "on" or args[2] == "off") then
        cfg.sound = (args[2] == "on")
        BRutus:Print(L["Mention sound: "] .. (cfg.sound and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]))
    elseif sub == "list" then
        BRutus:Print(L["--- Watch-words ---"])
        if #cfg.watchWords == 0 then BRutus:Print(L["(none)"]) end
        for i = 1, #cfg.watchWords do
            BRutus:Print("  |cffFFFFFF" .. tostring(cfg.watchWords[i]) .. "|r")
        end
    elseif sub == "add" and args[2] then
        -- Keep the whole phrase: "add need heals" is two words, not "need".
        local phrase = table.concat(args, " ", 2, #args)
        local status, norm = Mentions:_AddWatchWord(cfg.watchWords, phrase)
        if status == "ok" then
            BRutus:Print(L["Watch-word added: |cffFFFFFF"] .. norm .. "|r")
        elseif status == "short" then
            BRutus:Print(L["Watch-words must be at least 3 characters."])
        else
            BRutus:Print(L["Already watching: |cffFFFFFF"] .. norm .. "|r")
        end
    elseif sub == "remove" and args[2] then
        local t = strtrim(table.concat(args, " ", 2, #args)):lower()
        for i = #cfg.watchWords, 1, -1 do
            if tostring(cfg.watchWords[i]):lower() == t then table.remove(cfg.watchWords, i) end
        end
        BRutus:Print(L["Watch-word removed: |cffFFFFFF"] .. t .. "|r")
    elseif sub == "clearwords" then
        cfg.watchWords = {}; BRutus:Print(L["Watch-words cleared."])
    else
        -- default: print the recent log
        local log = cfg.log or {}
        BRutus:Print(L["--- Recent mentions ---"])
        if #log == 0 then BRutus:Print(L["(none)"]) end
        for i = 1, math.min(#log, 15) do
            local e = log[i]
            BRutus:Print(string.format("|cff888888%s|r %s: %s", date("%m/%d %H:%M", e.ts or 0), e.sender or "?", e.msg or ""))
        end
        BRutus:Print(L["Usage: /gos mentions <on|off|add|remove|list|clearwords|ownname|sound> [word|on|off]"])
    end
end
