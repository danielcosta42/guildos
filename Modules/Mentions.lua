----------------------------------------------------------------------
-- Guild OS - Mentions / Watch-words
-- Alerts you when your name (or a watch-word) appears in guild/officer
-- chat. Personal, no sync. Keeps a small capped recent-mentions log.
----------------------------------------------------------------------
local Mentions = {}
BRutus.Mentions = Mentions
local L = BRutus.L

local LOG_MAX = 100

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
    self:_SetupHook()
    self:_RegisterTests()
end

-- whole-word, case-insensitive: normalize non-alphanumerics to spaces,
-- then look for " needle " inside " haystack ".
local function hasWord(hay, needle)
    if not hay or not needle or needle == "" then return false end
    local h = " " .. hay:lower():gsub("[^%w]", " ") .. " "
    return h:find(" " .. needle:lower() .. " ", 1, true) ~= nil
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
end
