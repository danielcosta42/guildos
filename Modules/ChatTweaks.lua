----------------------------------------------------------------------
-- Guild OS - Chat Tweaks
-- Optional guild/officer chat annotations (class icon + level + alt tag, and
-- the officers' nickname for the member, #429), added as a safe MESSAGE PREFIX
-- (never modifies the author/name link). Off by default; whispers, party and
-- raid lines from guild members and their linked alts too when asked (#429; Settings > Chat and alerts:
-- "Also in whispers", "Also in party and raid", both off by default). Cache refreshed on
-- GUILD_ROSTER_UPDATE, never per line: a sender's key and prefix are worked out once a refresh, so a
-- line costs a lookup and a string join, no table.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
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

-- The cache's key for a roster name or a chat author: the whole name with its realm, the player's realm when it
-- gives none. By the short name a "Bob-OtherRealm" from outside the guild, whispering or in a group, got the
-- guild's Bob's nickname and alt tag (#429).
function ChatTweaks.KeyOf(name)
    if type(name) ~= "string" or name == "" then return nil end
    return GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, name:match("-(.+)$") or GetRealmName())
end

-- One pass over the roster (memory audit): nothing at all while Chat Tweaks is off (the filters do not read the
-- cache then; the first line after turning it on builds it), and no table a member: a sender's entry is the last
-- pass's, refilled, and the members gone since are dropped. Each pass builds a sender's prefix again at their
-- next line, as before.
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end   -- the game's; a stub may lack it
local passGen = 0
function ChatTweaks:_RefreshCache()
    local cfg = GuildOS.db and GuildOS.db.chatTweaks
    if not (cfg and cfg.enabled) then
        self._stale = true
        return
    end
    self._stale = nil
    passGen = passGen + 1
    local gen = passGen
    local cache = self._cache
    if not cache then cache = {}; self._cache = cache end
    local function put(key, classFile, level)
        local e = cache[key]
        if not e then e = {}; cache[key] = e end
        e.classFile, e.level, e.fullKey, e.gen = classFile, level, key, gen
        e.prefix, e.sig = nil, nil
    end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local key = ChatTweaks.KeyOf(name)
            if key then put(key, classFile, level) end
        end
    end
    -- A guild member's linked character outside the guild (an alt on the bank's account, a main who left): known
    -- to the officers' links, so its lines get the alt tag too, without a class or a level.
    for alt, main in pairs((GuildOS.db and GuildOS.db.altLinks) or {}) do
        if type(alt) == "string" and not (cache[alt] and cache[alt].gen == gen) then put(alt, nil, nil) end
        if type(main) == "string" and not (cache[main] and cache[main].gen == gen) then put(main, nil, nil) end
    end
    for key, e in pairs(cache) do
        if e.gen ~= gen then cache[key] = nil end
    end
    -- A chat author's key, worked out once a pass.
    if self._authors then wipe(self._authors) else self._authors = {} end
end

-- The settings that shape a prefix, as one number, and the marks and links it read (`epoch`, bumped when the
-- officers' nicknames or the alt links change): a sender's prefix is kept until one of them changes.
ChatTweaks.epoch = 0
local function cfgSig(cfg)
    return (cfg.classIcon and 1 or 0) + (cfg.level and 2 or 0) + (cfg.altTag and 4 or 0) + (cfg.altShort and 8 or 0)
        + (cfg.nick ~= false and 16 or 0) + 32 * ChatTweaks.epoch
end

-- A nickname or an alt link changed: every sender's prefix is built again at its next line.
function ChatTweaks:Invalidate()
    self.epoch = (self.epoch or 0) + 1
end
ChatTweaks._CfgSig = cfgSig

-- The prefix of a sender in the cache, built once a roster refresh and settings (`sig`), never per line.
function ChatTweaks:_PrefixFor(cached, cfg, sig)
    if cached.sig == sig and cached.prefix then return cached.prefix end
    local info = self._info or {}
    self._info = info
    info.classFile, info.level = cached.classFile, cached.level
    info.altTag = (GuildOS.GetAltTag and cached.fullKey) and GuildOS:GetAltTag(cached.fullKey) or nil
    info.shortTag = (cfg.altShort and GuildOS.AltRoster and cached.fullKey) and GuildOS.AltRoster:ShortTag(cached.fullKey) or nil
    info.nick = (cfg.nick ~= false and GuildOS.MemberMarks and cached.fullKey) and GuildOS.MemberMarks:Nick(cached.fullKey) or nil
    local prefix = self:_BuildPrefix(info, cfg)
    cached.prefix, cached.sig = prefix, sig
    return prefix
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
        if ChatTweaks._stale then ChatTweaks:_RefreshCache() end   -- turned on since the last roster pass
        local only = EVENT_SETTING[event]
        if only and not cfg[only] then return false end
        if GuildOS.Compat.IsSecret and GuildOS.Compat.IsSecret(msg, author) then return false end   -- chat in lockdown
        -- No table a line (the chat filter runs for every one): the author's key and the sender's prefix are cached.
        local authors = ChatTweaks._authors
        if not authors then authors = {}; ChatTweaks._authors = authors end
        local key = author and authors[author]
        if key == nil and type(author) == "string" then
            key = ChatTweaks.KeyOf(author) or false
            authors[author] = key
        end
        local cached = key and ChatTweaks._cache[key]
        if not cached then return false end
        local prefix = ChatTweaks:_PrefixFor(cached, cfg, cfgSig(cfg))
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
