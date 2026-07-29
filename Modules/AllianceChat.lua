----------------------------------------------------------------------
-- Guild OS - Alliance chat channel
--
-- The social half of the alliance: every member auto-joins one custom game
-- channel derived from the pact tag ("GOSBRCORE"), and Guild OS prefixes each
-- line with the speaker's guild so a 7-guild channel stays readable.
--
-- WHY A REAL GAME CHANNEL: it is cross-guild, cross-zone and cross-layer, it
-- costs the addon nothing, and it works for people who do not run Guild OS at
-- all. Automated posting is NOT possible (SendChatMessage to a channel needs a
-- hardware event), but a human pressing Enter IS one, which is all this needs.
--
-- SCOPE DECISION: the channel carries human chat only. It is deliberately NOT
-- used as a presence source: GetChannelRosterInfo only populates when the UI
-- lists the channel, and Alliance:PeerTarget already answers "who of guild X is
-- online" from the presence mesh. Using it would add a flaky dependency for
-- nothing.
--
-- HONEST LIMIT, surfaced in the UI: a custom channel is public. Anyone who
-- guesses the name can join. Nothing sensitive belongs here.
----------------------------------------------------------------------
local AllianceChat = {}
GuildOS.AllianceChat = AllianceChat
local L = BRutus.L

AllianceChat.DEFAULTS = {
    chat        = true,   -- auto-join the channel
    tags        = true,   -- guild tag prefix on each line
    history     = true,   -- keep a rolling log in SavedVariables
    hideDefault = false,  -- suppress the channel from the default chat frame
    system      = true,   -- alliance events in the feed, not just conversation
}

-- Capped on purpose: this is plain text on the player's disk, and an
-- unbounded log would grow the SavedVariables file forever.
AllianceChat.MAX_LOG = 200

local function accentHex()
    local c = BRutus.Colors and BRutus.Colors.accent
    if not c or not c.r then
        return "ffd700"
    end
    return string.format("%02x%02x%02x",
        math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

----------------------------------------------------------------------
-- Pure: the guild tag prefix. Kept separate from the filter so it is testable
-- without a live chat frame.
----------------------------------------------------------------------
function AllianceChat.Decorate(text, _sender, guild)
    local msg = tostring(text or "")
    local tag = (guild and guild ~= "" and guild) or L["unknown guild"]
    return "|cff" .. accentHex() .. "[" .. tag .. "]|r " .. msg
end

----------------------------------------------------------------------
-- Channel membership
----------------------------------------------------------------------
function AllianceChat:ChannelName()
    local ally = GuildOS.Alliance
    local pact = ally and ally:Get()
    if not pact then
        return nil
    end
    return GuildOS.Alliance.ChannelName(pact.tag)
end

function AllianceChat:IsConnected()
    local name = self:ChannelName()
    if not name or not GetChannelName then
        return false
    end
    return (GetChannelName(name) or 0) > 0
end

function AllianceChat:Prefs()
    BRutus.db.alliancePrefs = BRutus.db.alliancePrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.alliancePrefs[k] == nil then
            BRutus.db.alliancePrefs[k] = v
        end
    end
    return BRutus.db.alliancePrefs
end

function AllianceChat:Join()
    local name = self:ChannelName()
    if not name or not self:Prefs().chat then
        return false
    end
    if self:IsConnected() then
        return true
    end
    if JoinChannelByName then
        JoinChannelByName(name)
    end
    return self:IsConnected()
end

function AllianceChat:Leave()
    local name = self:ChannelName()
    if name and LeaveChannelByName then
        LeaveChannelByName(name)
    end
end

function AllianceChat:SetEnabled(on)
    self:Prefs().chat = on and true or false
    if on then
        self:Join()
    else
        self:Leave()
    end
end

----------------------------------------------------------------------
-- The feed: conversation and alliance events on one timeline.
--
-- Capture rides a dedicated event frame, NOT the display filter, because a
-- filter runs once per chat frame showing the channel: a player with the
-- channel in two tabs would log every line twice.
----------------------------------------------------------------------
AllianceChat.unread = 0
AllianceChat.listeners = {}

function AllianceChat:Log()
    BRutus.db.allianceChatLog = BRutus.db.allianceChatLog or {}
    return BRutus.db.allianceChatLog
end

function AllianceChat:OnRefresh(fn)
    if type(fn) == "function" then
        self.listeners[#self.listeners + 1] = fn
    end
end

function AllianceChat:_Notify()
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

function AllianceChat:Push(entry)
    if not self:Prefs().history then
        return
    end
    local log = self:Log()
    log[#log + 1] = entry
    while #log > self.MAX_LOG do
        table.remove(log, 1)
    end
    self.unread = self.unread + 1
    self:_Notify()
end

-- An alliance event, rendered inline with the conversation. `kind` is "info"
-- (something happened) or "warn" (something wants a decision).
function AllianceChat:AddSystem(text, kind)
    if not self:Prefs().system then
        return
    end
    local clean = BRutus:SanitizeUserText(text, 180)
    if clean == "" then
        return
    end
    self:Push({ t = GetServerTime(), m = clean, sys = kind or "info" })
end

function AllianceChat:Clear()
    BRutus.db.allianceChatLog = {}
    self.unread = 0
    self:_Notify()
end

function AllianceChat:MarkRead()
    self.unread = 0
end

-- Send to the alliance channel. Only ever called from a button click or an
-- EditBox Enter, which ARE hardware events, so the CHANNEL restriction noted
-- in Modules/RecruitmentSystem.lua does not apply here.
function AllianceChat:Send(text)
    local clean = BRutus:SanitizeUserText(text, 240)
    if clean == "" then
        return false
    end
    local name = self:ChannelName()
    local index = name and GetChannelName and GetChannelName(name)
    if not index or index == 0 then
        return false
    end
    SendChatMessage(clean, "CHANNEL", nil, index)
    return true
end

function AllianceChat:_OnChannelMessage(msg, author, chanBaseName)
    local mine = self:ChannelName()
    if not mine or not chanBaseName or chanBaseName:lower() ~= mine:lower() then
        return
    end
    local ally = GuildOS.Alliance
    local short = (Ambiguate and Ambiguate(author or "", "short")) or author
    self:Push({
        t = GetServerTime(),
        n = short,
        g = (ally and ally:GuildOfMember(author)) or (ally and ally:MyGuildName()) or nil,
        m = BRutus:SanitizeUserText(msg, 240),
    })
end

----------------------------------------------------------------------
-- Message decoration. A chat filter, exactly like ChatTweaks, so the author
-- link is never rewritten (only a prefix is added).
----------------------------------------------------------------------
function AllianceChat:_MakeFilter()
    return function(_, _, msg, author, lang, channelString, target, flags,
                    zoneID, chanIndex, chanBaseName, ...)
        if not BRutus.db or not BRutus.db.alliancePrefs then
            return false
        end
        if not BRutus.db.alliancePrefs.tags then
            return false
        end
        local mine = AllianceChat:ChannelName()
        if not mine or not chanBaseName or chanBaseName:lower() ~= mine:lower() then
            return false
        end
        -- Reading it in our own feed AND in the default frame means reading it
        -- twice. Off by default: hiding a channel the player joined is the kind
        -- of thing that must be asked for, never assumed.
        if BRutus.db.alliancePrefs.hideDefault then
            return true
        end
        local ally = GuildOS.Alliance
        local guild = ally and ally:GuildOfMember(author)
        if not guild then
            return false   -- unknown speaker: leave the line untouched
        end
        return false, AllianceChat.Decorate(msg, author, guild), author, lang,
            channelString, target, flags, zoneID, chanIndex, chanBaseName, ...
    end
end

function AllianceChat:_MakeWhisperFilter()
    return function(_, _, msg, author, ...)
        if not BRutus.db or not BRutus.db.alliancePrefs or not BRutus.db.alliancePrefs.tags then
            return false
        end
        local ally = GuildOS.Alliance
        local guild = ally and ally:GuildOfMember(author)
        if not guild then
            return false
        end
        return false, AllianceChat.Decorate(msg, author, guild), author, ...
    end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function AllianceChat:Initialize()
    self:Prefs()
    self:_RegisterTests()

    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", self:_MakeFilter())
        -- Same tag on an incoming whisper: knowing a stranger is from an allied
        -- guild is exactly the moment you need it, and it costs no extra sync.
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", self:_MakeWhisperFilter())
    end

    -- Channels are not available the instant the world loads, so join on a
    -- delay and retry once. Joining is idempotent (IsConnected short-circuits).
    -- CHAT_MSG_CHANNEL is captured HERE rather than in the display filter, so
    -- the feed logs each line exactly once no matter how many chat tabs show
    -- the channel.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHAT_MSG_CHANNEL")
    f:SetScript("OnEvent", function(_, event, msg, author, _, _, _, _, _, _, chanBaseName)
        if event == "CHAT_MSG_CHANNEL" then
            BRutus:SafeCall(function()
                AllianceChat:_OnChannelMessage(msg, author, chanBaseName)
            end)
            return
        end
        BRutus.Compat.After(10, function() AllianceChat:Join() end)
        BRutus.Compat.After(45, function() AllianceChat:Join() end)
    end)
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
function AllianceChat:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("alliancechat.decorate", function()
        local out = AllianceChat.Decorate("hello", "Ann", "Guild B")
        if not out:find("Guild B", 1, true) then return false, "guild tag missing" end
        if not out:find("hello", 1, true) then return false, "message lost" end
        if not out:find("|r", 1, true) then return false, "colour never closed" end
        if not AllianceChat.Decorate("hi", "Ann", nil):find("|cff", 1, true) then
            return false, "unknown guild must still render"
        end
        if AllianceChat.Decorate(nil, nil, nil) == nil then return false, "nil must not error" end
        return true
    end)
end
