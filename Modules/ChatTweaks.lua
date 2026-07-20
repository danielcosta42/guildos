----------------------------------------------------------------------
-- Guild OS - Chat Tweaks
-- Optional guild/officer chat annotations (class icon + level + alt tag),
-- added as a safe MESSAGE PREFIX (never modifies the author/name link).
-- Off by default. Cache refreshed on GUILD_ROSTER_UPDATE, never per line.
----------------------------------------------------------------------
local ChatTweaks = {}
BRutus.ChatTweaks = ChatTweaks

ChatTweaks.DEFAULTS = {
    enabled   = false,
    guild     = true,
    officer   = true,
    classIcon = true,
    level     = true,
    altTag    = true,
}

local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"

function ChatTweaks:Initialize()
    BRutus.db.chatTweaks = BRutus.db.chatTweaks or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.chatTweaks[k] == nil then BRutus.db.chatTweaks[k] = v end
    end
    self._cache = {}

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() ChatTweaks:_RefreshCache() end)

    self:_RegisterFilters()
    self:_RegisterTests()
end

function ChatTweaks:_RefreshCache()
    local cache = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            cache[short] = { classFile = classFile, level = level, fullKey = name }
        end
    end
    self._cache = cache
end

----------------------------------------------------------------------
-- Pure prefix building (unit-tested)
----------------------------------------------------------------------
function ChatTweaks:_ClassIcon(classFile)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if not c then return "" end
    return string.format("|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t",
        CLASS_TEX, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

function ChatTweaks:_BuildPrefix(info, cfg)
    if not info then return "" end
    local parts = {}
    if cfg.classIcon and info.classFile then
        local ic = self:_ClassIcon(info.classFile)
        if ic ~= "" then parts[#parts + 1] = ic end
    end
    if cfg.level and info.level and info.level > 0 then
        parts[#parts + 1] = "[" .. info.level .. "]"
    end
    if cfg.altTag and info.altTag then
        parts[#parts + 1] = "|cff888888(" .. info.altTag .. ")|r"
    end
    return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Chat filters (message-prefix only; returns false = keep line, modified)
----------------------------------------------------------------------
function ChatTweaks:_MakeFilter()
    return function(_, _, msg, author, ...)
        local cfg = BRutus.db.chatTweaks
        if not cfg or not cfg.enabled then return false end
        local short = author and (author:match("^([^-]+)") or author)
        local cached = short and ChatTweaks._cache[short]
        if not cached then return false end
        local info = {
            classFile = cached.classFile,
            level     = cached.level,
            altTag    = (BRutus.GetAltTag and cached.fullKey) and BRutus:GetAltTag(cached.fullKey) or nil,
        }
        local prefix = ChatTweaks:_BuildPrefix(info, cfg)
        if prefix == "" then return false end
        return false, prefix .. " " .. msg, author, ...
    end
end

function ChatTweaks:_RegisterFilters()
    if BRutus.db.chatTweaks.guild ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", self:_MakeFilter())
    end
    if BRutus.db.chatTweaks.officer ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", self:_MakeFilter())
    end
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function ChatTweaks:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local cfg = { classIcon = true, level = true, altTag = true }
    S:Register("chattweaks.level", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, cfg)
        if not p:find("[70]", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.alttag", function()
        local p = ChatTweaks:_BuildPrefix({ altTag = "alt of Main" }, cfg)
        if not p:find("alt of Main", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.off", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, { level = false })
        if p ~= "" then return false, "toggles off => empty" end
        return true
    end)
    S:Register("chattweaks.nil_info", function()
        if ChatTweaks:_BuildPrefix(nil, cfg) ~= "" then return false end
        return true
    end)
end
