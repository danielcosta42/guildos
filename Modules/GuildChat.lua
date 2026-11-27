----------------------------------------------------------------------
-- Guild OS - Guild chat, kept for the Guild tab (issue #124)
--
-- Every line of /g, the player's own included, goes into the guild's own
-- log, so the Chat sub-tab can show what was said before the window opened
-- and before the last reload. Sending is the player pressing Enter in that
-- tab, which is a hardware event, so it is allowed on WoW: Forever too.
--
-- Where the server keeps the guild's chat (WoW: Forever, issue #126), the tab
-- shows that instead: it also holds what was said while the player was away,
-- and every channel of the guild, Officer and the ones it made, gets a tab.
-- Only /g is ever written to disk.
--
-- A channel is { id, name, kind } from Compat.GuildChatStreams; nil means /g.
--
-- Unlike the alliance channel, the line is kept as the game sent it: item
-- and player links stay clickable. It is what the default chat frame shows
-- for the same line, and only the guild can say it. Line breaks go: one
-- line of chat is one line of the feed.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local GuildChat = {}
GuildOS.GuildChat = GuildChat

-- Capped on purpose: plain text on the player's disk, and an unbounded log
-- would grow the SavedVariables file forever.
GuildChat.MAX_LOG = 200

GuildChat.listeners = {}

function GuildChat:Log()
    GuildOS.db.guildChatLog = GuildOS.db.guildChatLog or {}
    return GuildOS.db.guildChatLog
end

function GuildChat:OnRefresh(fn)
    if type(fn) == "function" then
        self.listeners[#self.listeners + 1] = fn
    end
end

-- Counts every change (a line, a channel's history arriving): a screen that drew the chat at this version has
-- nothing new to draw (the Hall's chat card).
GuildChat.version = 0
function GuildChat:_Notify()
    self.version = (self.version or 0) + 1
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

-- The guild's channels this player can read; nil where the server keeps none, or
-- in a chat lockdown, when the list arrives secret.
function GuildChat:Streams()
    return (GuildOS.Compat.GuildChatStreams())
end

-- In a chat lockdown nothing of the server's can be read: a feed keeps what it shows.
function GuildChat:Locked()
    return GuildOS.Compat.InChatLockdown()
end

local function isGuild(stream)
    return not stream or stream.kind == "guild"
end

-- What a channel's tab shows, and whether it came from the server. For /g, the
-- server's history where it has one, and the addon's log elsewhere or while the
-- server has nothing loaded yet: never both, so no line shows twice. Any other
-- channel only ever has the server's.
-- `max` (default MAX_LOG): only the newest that many are asked of the server and kept.
function GuildChat:Entries(stream, max)
    max = math.min(tonumber(max) or self.MAX_LOG, self.MAX_LOG)
    local server, locked = GuildOS.Compat.GuildChatHistory(max, stream and stream.id)
    if locked then return nil end
    if not isGuild(stream) then
        return server or {}, true
    end
    if server and #server > 0 then
        return GuildChat.Merge(server, self:AlliedLog(), max), true
    end
    return GuildChat.Merge(self:Log(), self:AlliedLog(), max), false
end

----------------------------------------------------------------------
-- The allied guilds' /g (issue #344), kept apart from ours: the server's
-- history replaces our log where it has one, and it never holds these.
-- Each entry carries `g`, the guild it came from, which the feed shows as a
-- tag and which keeps two namesakes of two guilds in separate blocks.
----------------------------------------------------------------------
function GuildChat:AlliedLog()
    GuildOS.db.guildChatAllyLog = GuildOS.db.guildChatAllyLog or {}
    return GuildOS.db.guildChatAllyLog
end

function GuildChat:AddAllied(guild, line)
    if type(guild) ~= "string" or type(line) ~= "table" then return end
    local log = self:AlliedLog()
    log[#log + 1] = {
        t = GetServerTime(),
        n = (Ambiguate and Ambiguate(line.n or "", "short")) or line.n,
        c = line.c,
        g = guild,
        m = line.m,
    }
    while #log > self.MAX_LOG do
        table.remove(log, 1)
    end
    self:_Notify()
end

-- Pure. Two time-ordered logs as one, oldest first, the newest `cap` kept. An
-- empty allied log hands back ours untouched, which is every guild outside an
-- alliance.
function GuildChat.Merge(own, allied, cap)
    if type(allied) ~= "table" or #allied == 0 then
        if not cap or #own <= cap then return own end
        local newest = {}
        for k = #own - cap + 1, #own do newest[#newest + 1] = own[k] end
        return newest
    end
    local out, i, j = {}, 1, 1
    while i <= #own or j <= #allied do
        local a, b = own[i], allied[j]
        if b and (not a or (tonumber(b.t) or 0) < (tonumber(a.t) or 0)) then
            out[#out + 1] = b
            j = j + 1
        else
            out[#out + 1] = a
            i = i + 1
        end
    end
    cap = cap or #out
    if #out > cap then
        local trimmed = {}
        for k = #out - cap + 1, #out do trimmed[#trimmed + 1] = out[k] end
        out = trimmed
    end
    return out
end

-- A channel's tab opened (true) or closed. Two feeds can show one channel (the
-- Now card and Guild > Chat), so the server hears the first open and the last
-- close. Opened, it is asked for older lines while it holds fewer than the cap;
-- they redraw the tab when they arrive.
GuildChat.watching = {}

function GuildChat:Watch(on, stream)
    local id = (not isGuild(stream)) and stream.id or nil
    local key = id or "guild"
    local was = self.watching[key] or 0
    if not on and was == 0 then return end
    self.watching[key] = was + (on and 1 or -1)
    if not on then
        if was == 1 then GuildOS.Compat.WatchGuildChat(false, id) end
        return
    end
    if was > 0 then return end
    GuildOS.Compat.WatchGuildChat(true, id)
    local server = GuildOS.Compat.GuildChatHistory(self.MAX_LOG, id)
    if server and #server < self.MAX_LOG then
        GuildOS.Compat.RequestOlderGuildChat(self.MAX_LOG - #server, id)
    end
end

-- The class is read now, while the speaker is a GUID the game knows: the
-- history is drawn in class colours long after they logged off.
local function classOf(guid)
    if not guid or GuildOS.Compat.IsSecret(guid) or not GetPlayerInfoByGUID then return nil end
    local _, class = GetPlayerInfoByGUID(guid)
    if GuildOS.Compat.IsSecret(class) then return nil end
    return class
end

function GuildChat:_OnMessage(msg, author, guid)
    -- Chat in lockdown on Forever: neither the line nor its speaker is readable.
    if GuildOS.Compat.IsSecret(msg, author) or not msg or not author then return end
    -- The data resolved at login for a guildless character is shared by every guildless
    -- character on the realm: a guild joined since then is not written into it.
    if not GuildOS.isGuilded then return end
    local log = self:Log()
    log[#log + 1] = {
        t = GetServerTime(),
        n = (Ambiguate and Ambiguate(author, "guild")) or author,
        c = classOf(guid),
        m = (tostring(msg):gsub("%c", " ")),
    }
    while #log > self.MAX_LOG do
        table.remove(log, 1)
    end
    self:_Notify()
end

-- Only ever called from a tab's Enter or Send click. The line is not logged
-- here: it shows when the game echoes it back.
function GuildChat:Send(text, stream)
    -- An item link pasted into the box stays a link (#449 review); anything else that is not text goes.
    local clean = GuildOS:SanitizeChatLine(text, 240)
    if clean == "" then
        return false
    end
    -- Forever drops a line sent in an encounter's chat lockdown without an error, so it is
    -- asked first and the text stays with the player (as Modules/CallToArms.lua does).
    if GuildOS.Compat.InChatLockdown() then
        return false, "locked"
    end
    if isGuild(stream) then
        SendChatMessage(clean, "GUILD")
        -- The same click carries it to the allied guilds (issue #348): the tab's
        -- box is not one of the chat frame's, so the hook there never sees it.
        if GuildOS.AllianceLink then GuildOS.AllianceLink:OnPlayerChat("GUILD", clean) end
    elseif stream.kind == "officer" then
        SendChatMessage(clean, "OFFICER")
    else
        return GuildOS.Compat.SendGuildStream(stream.id, clean)
    end
    return true
end

function GuildChat:_OnClubEvent(clubId)
    if GuildOS.Compat.IsGuildClub(clubId) then self:_Notify() end
end

function GuildChat:Initialize()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    -- The server's channels: a new line, older ones arriving, a channel made or
    -- removed, the list arriving. Absent where there are none.
    GuildOS.Compat.RegisterEvent(f, "CLUB_MESSAGE_ADDED", true)
    GuildOS.Compat.RegisterEvent(f, "CLUB_MESSAGE_HISTORY_RECEIVED", true)
    GuildOS.Compat.RegisterEvent(f, "CLUB_STREAM_ADDED", true)
    GuildOS.Compat.RegisterEvent(f, "CLUB_STREAM_REMOVED", true)
    GuildOS.Compat.RegisterEvent(f, "CLUB_STREAMS_LOADED", true)
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_GUILD" then
            local msg, author = ...
            local guid = select(12, ...)
            GuildOS:SafeCall(GuildChat._OnMessage, GuildChat, msg, author, guid)
            return
        end
        local clubId = ...
        GuildOS:SafeCall(GuildChat._OnClubEvent, GuildChat, clubId)
    end)
end
