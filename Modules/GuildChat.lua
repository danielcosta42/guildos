----------------------------------------------------------------------
-- Guild OS - Guild chat, kept for the Guild tab (issue #124)
--
-- Every line of /g, the player's own included, goes into the guild's own
-- log, so the Chat sub-tab can show what was said before the window opened
-- and before the last reload. Sending is the player pressing Enter in that
-- tab, which is a hardware event, so it is allowed on WoW: Forever too.
--
-- Where the server keeps the guild's chat (WoW: Forever, issue #126), the tab
-- shows that instead: it also holds what was said while the player was away.
--
-- Unlike the alliance channel, the line is kept as the game sent it: item
-- and player links stay clickable. It is what the default chat frame shows
-- for the same line, and only the guild can say it. Line breaks go: one
-- line of chat is one line of the feed.
----------------------------------------------------------------------
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

function GuildChat:_Notify()
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

-- What the tab shows, and whether it came from the server. The server's history
-- where it has one; the addon's log elsewhere, or while the server has nothing
-- loaded yet. Never both: one source, so no line shows twice.
function GuildChat:Entries()
    local server = GuildOS.Compat.GuildChatHistory(self.MAX_LOG)
    if server and #server > 0 then
        return server, true
    end
    return self:Log(), false
end

-- The tab opened (true) or closed. Opened, the server is asked for older lines
-- while it holds fewer than the cap; they redraw the tab when they arrive.
function GuildChat:Watch(on)
    GuildOS.Compat.WatchGuildChat(on)
    if not on then return end
    local server = GuildOS.Compat.GuildChatHistory(self.MAX_LOG)
    if server and #server < self.MAX_LOG then
        GuildOS.Compat.RequestOlderGuildChat(self.MAX_LOG - #server)
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

-- Only ever called from the tab's Enter or Send click. The line is not logged
-- here: it shows when the game echoes it back as CHAT_MSG_GUILD.
function GuildChat:Send(text)
    local clean = GuildOS:SanitizeUserText(text, 240)
    if clean == "" then
        return false
    end
    -- Forever drops a line sent in an encounter's chat lockdown without an error, so it is
    -- asked first and the text stays with the player (as Modules/CallToArms.lua does).
    if GuildOS.Compat.InChatLockdown() then
        return false, "locked"
    end
    SendChatMessage(clean, "GUILD")
    return true
end

function GuildChat:Initialize()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    -- The server's stream: a new line, or older ones arriving. Absent where there is none.
    GuildOS.Compat.RegisterEvent(f, "CLUB_MESSAGE_ADDED", true)
    GuildOS.Compat.RegisterEvent(f, "CLUB_MESSAGE_HISTORY_RECEIVED", true)
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_GUILD" then
            local msg, author = ...
            local guid = select(12, ...)
            GuildOS:SafeCall(function() GuildChat:_OnMessage(msg, author, guid) end)
            return
        end
        local clubId, streamId = ...
        GuildOS:SafeCall(function()
            if GuildOS.Compat.IsGuildChatStream(clubId, streamId) then GuildChat:_Notify() end
        end)
    end)
end
