----------------------------------------------------------------------
-- Guild OS - The alliance room
--
-- The social half of the alliance code (Modules/AllianceLink.lua): the room is
-- the hidden, passworded channel the code names (AllianceLink.ChannelNameFor), whose lines
-- AllianceLink decodes and hands here, each with the speaker's guild. This
-- module keeps the player in the channel (a watchdog), keeps the feed the
-- Salão shows, and the player's switches, the shared /g among them.
--
-- Sending is only ever inside a key press (a button click, an EditBox Enter):
-- the game lets an addon speak on a channel at no other moment.
--
-- HONEST LIMIT, surfaced in the UI: the key is readable by every member of
-- every guild in the alliance. Nothing sensitive belongs here.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local AllianceChat = {}
GuildOS.AllianceChat = AllianceChat
local L = GuildOS.L

AllianceChat.DEFAULTS = {
    chat        = true,   -- auto-join the channel
    tags        = true,   -- the allied guild's tag on a whisper from one of its members
    history     = true,   -- keep a rolling log in SavedVariables
    system      = true,   -- alliance events in the feed, not just conversation
    guildBridge = true,   -- the shared /g: the allied guilds' /g in our guild chat (issue #344)
}

-- Capped on purpose: this is plain text on the player's disk, and an
-- unbounded log would grow the SavedVariables file forever.
AllianceChat.MAX_LOG = 200

local function accentHex()
    local c = GuildOS.Colors and GuildOS.Colors.accent
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
    local link = GuildOS.AllianceLink
    return (link and link:Active()) and link:ChannelName() or nil
end

function AllianceChat:IsConnected()
    local name = self:ChannelName()
    if not name or not GetChannelName then
        return false
    end
    return (GetChannelName(name) or 0) > 0
end

-- Where the room stands, for the screens (#449): "none" (no alliance), "off" (the player turned the room off),
-- "joined", "failed" (the server refused the channel, or never answered: the second value is AllianceLink's
-- { name, reason }), or "joining".
function AllianceChat:State()
    local link = GuildOS.AllianceLink
    if not (link and link:Active()) then return "none" end
    if not self:Prefs().chat then return "off" end
    if self:IsConnected() then return "joined" end
    local err = link:JoinError()
    if err then return "failed", err end
    return "joining"
end

function AllianceChat:Prefs()
    GuildOS.db.alliancePrefs = GuildOS.db.alliancePrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.alliancePrefs[k] == nil then
            GuildOS.db.alliancePrefs[k] = v
        end
    end
    return GuildOS.db.alliancePrefs
end

-- Seconds between watchdog checks. GetChannelName is a trivial call, so this
-- is cheap enough to run forever.
AllianceChat.JOIN_RETRY = 20

-- Idempotent, and the ONLY thing that joins. Being out of the alliance channel
-- is never an acceptable resting state: the chat system is not ready for a
-- while after a reload, so this keeps running instead of giving up. It stops
-- for exactly one reason: the player turned the room off.
function AllianceChat:EnsureJoined()
    if not GuildOS.db or not GuildOS.db.alliancePrefs then
        return false
    end
    self:_LeaveLegacy()
    local link = GuildOS.AllianceLink
    if link then
        link:SyncSite()
        link:LeaveStale()   -- a channel of an alliance that ended, or of an old key, goes even with the room off
        link:LeaveUnhashed()   -- and the channel as 1.27 to 1.43 named it (GOSA .. TAG), once per character
    end
    if not self:Prefs().chat then
        return false
    end
    if link and link:Active() then
        return link:EnsureJoined()
    end
    return false
end

-- The old pact's public channel (GOS<TAG>) is the client's saved channel, and
-- nothing reads it any more (audit #448). Its name was kept when the pact's data
-- was cleared (Core/Core.lua ResolveGuildDB) and stays: the guild's db is shared by
-- the account's characters and each one is in the channel on its own, so each
-- leaves it once (allianceLeftBy, per character). Never the hidden channel in
-- force: an old pact's name can meet the code's (GOS .. "A..." against GOSA .. TAG .. hash).
function AllianceChat:_LeaveLegacy()
    local db = GuildOS.db
    local old = db and db.allianceLeaveChannel
    if type(old) ~= "string" or not GetChannelName then
        return
    end
    local link = GuildOS.AllianceLink
    if old:lower() == ((link and link:ChannelName()) or ""):lower() then
        return
    end
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName() or "?", GetRealmName())
    db.allianceLeftBy = type(db.allianceLeftBy) == "table" and db.allianceLeftBy or {}
    if db.allianceLeftBy[me] then
        return
    end
    if (GetChannelName(old) or 0) > 0 then
        GuildOS.Compat.LeaveChannel(old)
        db.allianceLeftBy[me] = true
    end
end

function AllianceChat:Join()
    return self:EnsureJoined()
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
    GuildOS.db.allianceChatLog = GuildOS.db.allianceChatLog or {}
    return GuildOS.db.allianceChatLog
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
    local clean = GuildOS:SanitizeUserText(text, 180)
    if clean == "" then
        return
    end
    self:Push({ t = GetServerTime(), m = clean, sys = kind or "info" })
end

----------------------------------------------------------------------
-- Hiding a message.
--
-- Honest about what this is: the message was already delivered by the server.
-- This removes it from the Guild OS feed of this guild's members, after the
-- fact: an officer's hide reaches the guild over SyncService ("allyhide").
--
-- Matched on speaker plus text rather than an id, because there is no id: each
-- client stamps its own arrival time, so any hash including the timestamp
-- would differ between clients. The failure mode of matching on text is that
-- an identical line from the same person also goes, which is harmless.
----------------------------------------------------------------------
AllianceChat.MAX_HIDDEN = 50

function AllianceChat:HiddenStore()
    GuildOS.db.allianceHidden = GuildOS.db.allianceHidden or {}
    return GuildOS.db.allianceHidden
end

-- Pure. The lookup the renderer uses, built from every guild's hide list.
function AllianceChat.BuildHiddenSet(lists)
    local set = {}
    if type(lists) ~= "table" then
        return set
    end
    for _, list in ipairs(lists) do
        if type(list) == "table" then
            for _, h in ipairs(list) do
                if type(h) == "table" and h.n and h.m then
                    set[tostring(h.n):lower() .. "\0" .. tostring(h.m)] = true
                end
            end
        end
    end
    return set
end

function AllianceChat.HiddenKey(name, text)
    return tostring(name or ""):lower() .. "\0" .. tostring(text or "")
end

-- Every line this guild's officers hid.
function AllianceChat:HiddenSet()
    return AllianceChat.BuildHiddenSet({ self:HiddenStore() })
end

function AllianceChat:HideMessage(name, text)
    local ally = GuildOS.Alliance
    if not ally or not ally:CanAdminister() then
        return false, L["Only officers can do that."]
    end
    local clean = GuildOS:SanitizeChatLine(text, 255)
    if clean == "" or not name then
        return false
    end
    local store = self:HiddenStore()
    for _, h in ipairs(store) do
        if h.n == name and h.m == clean then
            return true   -- already hidden
        end
    end
    store[#store + 1] = { n = name, m = clean, ts = GetServerTime() }
    while #store > self.MAX_HIDDEN do
        table.remove(store, 1)
    end
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("allyhide", "add", { n = name, m = clean })
    end
    self:_Notify()
    return true
end

function AllianceChat:OnHideSync(env)
    local d = env and env.data
    if type(d) ~= "table" or not d.n or not d.m then
        return
    end
    local store = self:HiddenStore()
    for _, h in ipairs(store) do
        if h.n == d.n and h.m == d.m then
            return
        end
    end
    store[#store + 1] = { n = d.n, m = GuildOS:SanitizeChatLine(d.m, 255), ts = GetServerTime() }
    while #store > self.MAX_HIDDEN do
        table.remove(store, 1)
    end
    self:_Notify()
end

function AllianceChat:Clear()
    GuildOS.db.allianceChatLog = {}
    self.unread = 0
    self:_Notify()
end

function AllianceChat:MarkRead()
    self.unread = 0
end

-- Seconds within which further lines from the same speaker fold into the
-- block above instead of repeating the header.
AllianceChat.GROUP_WINDOW = 300

-- Pure. Fold a flat log into render blocks. A block is one speaker talking
-- without interruption inside the window; a system line always stands alone
-- and always breaks the run, because "X entered the alliance" appearing under
-- somebody's name would read as if they said it.
function AllianceChat.GroupLog(log, window)
    local out = {}
    if type(log) ~= "table" then
        return out
    end
    window = tonumber(window) or AllianceChat.GROUP_WINDOW
    local last

    for _, e in ipairs(log) do
        if e.sys then
            out[#out + 1] = { sys = e.sys, t = e.t, lines = { e.m or "" } }
            last = nil
        else
            local sameRun = last
                and last.name == e.n
                and last.guild == e.g
                and ((tonumber(e.t) or 0) - (tonumber(last.lastT) or 0)) <= window
            if sameRun then
                last.lines[#last.lines + 1] = e.m or ""
                last.lastT = e.t
            else
                last = {
                    name = e.n, guild = e.g, t = e.t, lastT = e.t, lines = { e.m or "" },
                }
                out[#out + 1] = last
            end
        end
    end
    return out
end

-- Send to the alliance channel. Only ever called from a button click or an
-- EditBox Enter, which ARE hardware events, so the CHANNEL restriction noted
-- in Modules/RecruitmentSystem.lua does not apply here.
function AllianceChat:Send(text)
    -- An item link goes through whole, as /g takes it (#449).
    local clean = GuildOS:SanitizeChatLine(text, 240)
    if clean == "" then
        return false
    end
    -- On the hidden channel the room's lines are framed like /g's (issue #348),
    -- and nothing prints them but the feed, so ours goes in here.
    local link = GuildOS.AllianceLink
    if not (link and link:Active()) or not link:Say("A", clean) then
        return false
    end
    local ally = GuildOS.Alliance
    self:PushLine(GuildOS.Compat.PlayerName(), ally and ally:MyGuildName(), clean)
    return true
end

-- A line of the room, already decoded (Modules/AllianceLink.lua, issue #348).
function AllianceChat:PushLine(name, guild, text)
    self:Push({ t = GetServerTime(), n = name, g = guild, m = GuildOS:SanitizeChatLine(text, 255) })
end

----------------------------------------------------------------------
-- A whisper from a member of an allied guild carries its tag: knowing a
-- stranger is from an allied guild is exactly the moment you need it. A chat
-- filter, so the author link is never rewritten (only a prefix is added).
----------------------------------------------------------------------
function AllianceChat:_MakeWhisperFilter()
    return function(_, _, msg, author, ...)
        if not GuildOS.db or not GuildOS.db.alliancePrefs or not GuildOS.db.alliancePrefs.tags then
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

    if GuildOS.SyncService then
        GuildOS.SyncService:On("allyhide", function(env) AllianceChat:OnHideSync(env) end)
    end
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", self:_MakeWhisperFilter())
    end

    -- Channels are not available the instant the world loads, so join on a
    -- delay, staggered; the watchdog below is what actually guarantees it.
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_ENTERING_WORLD")
    -- Fires whenever the channel list changes, which after a reload is exactly
    -- the moment joining starts working.
    GuildOS.Compat.RegisterEvent(f, "CHANNEL_UI_UPDATE")
    f:SetScript("OnEvent", function(_, event)
        if event == "CHANNEL_UI_UPDATE" then
            AllianceChat:EnsureJoined()
            return
        end
        for _, delay in ipairs({ 3, 8, 15, 30 }) do
            GuildOS.Compat.After(delay, function() AllianceChat:EnsureJoined() end)
        end
    end)

    if GuildOS.Compat and GuildOS.Compat.NewTicker then
        GuildOS.Compat.NewTicker(self.JOIN_RETRY, function()
            AllianceChat:EnsureJoined()
        end)
    end
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
function AllianceChat:_RegisterTests()
    if not GuildOS.SelfTest then
        return
    end

    GuildOS.SelfTest:Register("alliancechat.group_log", function()
        local G = AllianceChat.GroupLog
        local log = {
            { t = 100, n = "Ann", g = "GA", m = "oi" },
            { t = 120, n = "Ann", g = "GA", m = "alguem de kara" },   -- folds in
            { t = 130, n = "Bob", g = "GB", m = "eu vou" },           -- new speaker
            { t = 140, n = "Ann", g = "GA", m = "fechou" },           -- Ann again, new block
            { t = 150, sys = "info", m = "GC entrou" },
            { t = 160, n = "Ann", g = "GA", m = "bora" },
        }
        local out = G(log, 300)
        if #out ~= 5 then return false, "expected 5 blocks, got " .. #out end
        if #out[1].lines ~= 2 then return false, "same speaker in window must fold" end
        if out[1].lines[2] ~= "alguem de kara" then return false, "folded text lost" end
        if out[2].name ~= "Bob" then return false, "speaker change must break the run" end
        if out[3].name ~= "Ann" or #out[3].lines ~= 1 then return false, "return after Bob" end
        if out[4].sys ~= "info" then return false, "system line must stand alone" end
        -- A system line breaks the run even for the same speaker either side.
        if out[5].name ~= "Ann" or #out[5].lines ~= 1 then
            return false, "system line must break the run"
        end

        -- Outside the window the same speaker starts a fresh block.
        local far = G({
            { t = 100, n = "Ann", g = "GA", m = "a" },
            { t = 500, n = "Ann", g = "GA", m = "b" },
        }, 300)
        if #far ~= 2 then return false, "window not enforced" end

        -- Same name in a DIFFERENT guild is a different person.
        local twins = G({
            { t = 100, n = "Ann", g = "GA", m = "a" },
            { t = 110, n = "Ann", g = "GB", m = "b" },
        }, 300)
        if #twins ~= 2 then return false, "guild change must break the run" end

        if #G(nil, 300) ~= 0 then return false, "nil must not error" end
        return true
    end)

    GuildOS.SelfTest:Register("alliancechat.decorate", function()
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
