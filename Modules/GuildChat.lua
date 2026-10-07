----------------------------------------------------------------------
-- Guild OS - Guild chat, kept for the Guild tab (issue #124)
--
-- Every line of /g, the player's own included, goes into the guild's own
-- log, so the Chat sub-tab can show what was said before the window opened
-- and before the last reload. Sending is the player pressing Enter in that
-- tab, which is a hardware event, so it is allowed on WoW: Forever too.
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
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

-- Only ever called from the tab's Enter or Send click. The line is not logged
-- here: it shows when the game echoes it back as CHAT_MSG_GUILD.
function GuildChat:Send(text)
    local clean = GuildOS:SanitizeUserText(text, 240)
    if clean == "" then
        return false
    end
    SendChatMessage(clean, "GUILD")
    return true
end

function GuildChat:Initialize()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author, _, _, _, _, _, _, _, _, _, guid)
        GuildOS:SafeCall(function() GuildChat:_OnMessage(msg, author, guid) end)
    end)
end
