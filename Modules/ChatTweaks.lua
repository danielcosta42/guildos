----------------------------------------------------------------------
-- Guild OS - Chat Tweaks
-- Optional guild/officer chat annotations (class icon + level + alt tag, and
-- the officers' nickname for the member, #429), added as a safe MESSAGE PREFIX
-- (never modifies the author/name link). Off by default; whispers, party and
-- raid lines from guild members too when asked (#429). Cache refreshed on
-- GUILD_ROSTER_UPDATE, never per line.
----------------------------------------------------------------------
local ChatTweaks = {}
GuildOS.ChatTweaks = ChatTweaks

ChatTweaks.DEFAULTS = {
    enabled   = false,
    guild     = true,
    officer   = true,
    classIcon = true,
    level     = true,
    altTag    = true,
    altShort  = false,   -- "[Floyd]" / "[M]" instead of "(alt of Floyd)" (#269)
    nick      = true,    -- the officers' nickname for the member (#429; only an officer's client has them)
    whisper   = false,   -- a guild member's whispers too (#429)
    group     = false,   -- a guild member's party and raid lines too (#429)
}

-- Which setting turns each chat event on (#429): guild and officer are read once at login, as before.
local EVENT_SETTING = {
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_PARTY = "group", CHAT_MSG_PARTY_LEADER = "group",
    CHAT_MSG_RAID = "group", CHAT_MSG_RAID_LEADER = "group", CHAT_MSG_RAID_WARNING = "group",
}

local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"

function ChatTweaks:Initialize()
    GuildOS.db.chatTweaks = GuildOS.db.chatTweaks or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.chatTweaks[k] == nil then GuildOS.db.chatTweaks[k] = v end
    end
    self._cache = {}

    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    -- A pass over the whole roster: at most one every ROSTER_GAP seconds (issue #324).
    f:SetScript("OnEvent", function()
        GuildOS:Coalesce("chatTweaks", GuildOS.ROSTER_GAP, ChatTweaks.TimedRefresh)
    end)

    self:_RegisterFilters()
    self:_RegisterTests()
end

function ChatTweaks.TimedRefresh()
    local t = GuildOS.Perf:Start()
    ChatTweaks:_RefreshCache()
    GuildOS.Perf:Stop("roster chat cache", t)
end

function ChatTweaks:_RefreshCache()
    local cache = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            cache[short] = { classFile = classFile, level = level, fullKey = GuildOS:GetPlayerKey(short, realm) }
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
    if cfg.nick ~= false and info.nick then
        parts[#parts + 1] = "|cffd8b34a\"" .. info.nick .. "\"|r"
    end
    if cfg.level and info.level and info.level > 0 then
        parts[#parts + 1] = "[" .. info.level .. "]"
    end
    if cfg.altTag and cfg.altShort then
        if info.shortTag then parts[#parts + 1] = "|cff888888" .. info.shortTag .. "|r" end
    elseif cfg.altTag and info.altTag then
        parts[#parts + 1] = "|cff888888(" .. info.altTag .. ")|r"
    end
    return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Chat filters (message-prefix only; returns false = keep line, modified)
----------------------------------------------------------------------
function ChatTweaks:_MakeFilter()
    return function(_, event, msg, author, ...)
        local cfg = GuildOS.db.chatTweaks
        if not cfg or not cfg.enabled then return false end
        local only = EVENT_SETTING[event]
        if only and not cfg[only] then return false end
        if GuildOS.Compat.IsSecret and GuildOS.Compat.IsSecret(msg, author) then return false end   -- chat in lockdown
        local short = author and (author:match("^([^-]+)") or author)
        local cached = short and ChatTweaks._cache[short]
        if not cached then return false end
        local info = {
            classFile = cached.classFile,
            level     = cached.level,
            altTag    = (GuildOS.GetAltTag and cached.fullKey) and GuildOS:GetAltTag(cached.fullKey) or nil,
            shortTag  = (cfg.altShort and GuildOS.AltRoster and cached.fullKey) and GuildOS.AltRoster:ShortTag(cached.fullKey) or nil,
            nick      = (cfg.nick ~= false and GuildOS.MemberMarks and cached.fullKey) and GuildOS.MemberMarks:Nick(cached.fullKey) or nil,
        }
        local prefix = ChatTweaks:_BuildPrefix(info, cfg)
        if prefix == "" then return false end
        return false, prefix .. " " .. msg, author, ...
    end
end

function ChatTweaks:_RegisterFilters()
    if not ChatFrame_AddMessageEventFilter then return end
    if GuildOS.db.chatTweaks.guild ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", self:_MakeFilter())
    end
    if GuildOS.db.chatTweaks.officer ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", self:_MakeFilter())
    end
    -- Whispers, party and raid (#429): always hooked, each line checked against its setting, so the
    -- setting takes effect without a reload. Only a guild member (in the cache) gets a prefix.
    local others = {}
    for event in pairs(EVENT_SETTING) do others[#others + 1] = event end
    table.sort(others)
    for _, event in ipairs(others) do ChatFrame_AddMessageEventFilter(event, self:_MakeFilter()) end
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function ChatTweaks:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
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
    S:Register("chattweaks.nick", function()
        local p = ChatTweaks:_BuildPrefix({ nick = "Big Bob" }, cfg)
        if not p:find("Big Bob", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.nil_info", function()
        if ChatTweaks:_BuildPrefix(nil, cfg) ~= "" then return false end
        return true
    end)
end
