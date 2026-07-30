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

-- Seconds between watchdog checks. GetChannelName is a trivial call, so this
-- is cheap enough to run forever.
AllianceChat.JOIN_RETRY = 20

-- Idempotent, and the ONLY thing that joins. Being out of the alliance channel
-- is never an acceptable resting state: the chat system is not ready for a
-- while after a reload, and a fixed pair of attempts could land entirely
-- inside that window and leave the player silently outside until next login.
-- So this keeps running instead of giving up.
--
-- It stops for exactly one reason: the player turned the channel off. A kick
-- WILL be undone by this, deliberately, since a kick is a warning and a ban is
-- what actually removes somebody (the server refuses the rejoin).
function AllianceChat:EnsureJoined()
    if not BRutus.db or not BRutus.db.alliancePrefs then
        return false
    end
    if not self:Prefs().chat then
        return false
    end
    local name = self:ChannelName()
    if not name then
        return false   -- no pact, nothing to join
    end
    if self:IsConnected() then
        return true
    end
    if JoinChannelByName then
        JoinChannelByName(name)
    end
    return self:IsConnected()
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
-- Channel moderation.
--
-- This is the ONLY real moderation available. A custom channel message is
-- delivered by the server to everyone in the channel and cannot be retracted:
-- once it is printed it is printed, in the default chat frame and in our feed.
-- What CAN be done is stop the person continuing, which is kick and ban.
--
-- Ownership is the catch. WoW hands a custom channel to whoever joined it
-- first, which for an alliance channel is very often a regular member rather
-- than an ambassador, so the people who need to moderate usually cannot. That
-- is why PromoteAmbassadors exists: the owner hands moderator to the pact's
-- ambassadors in one action.
----------------------------------------------------------------------

-- Best effort. The channel roster is only populated while the client is
-- tracking it, so "unknown" is a real answer here and callers must treat it as
-- "try and let the server decide" rather than as a refusal.
function AllianceChat:ModeratorState()
    local name = self:ChannelName()
    local id = name and GetChannelName and GetChannelName(name)
    if not id or id == 0 or not GetChannelRosterInfo then
        return "unknown"
    end
    local me = UnitName("player")
    for i = 1, 400 do
        local ok, who, owner, moderator = pcall(GetChannelRosterInfo, id, i)
        if not ok or not who then
            break
        end
        if who == me then
            if owner then return "owner" end
            if moderator then return "moderator" end
            return "member"
        end
    end
    return "unknown"
end

function AllianceChat:CanModerate()
    local state = self:ModeratorState()
    return state == "owner" or state == "moderator" or state == "unknown"
end

local function channelName()
    return GuildOS.AllianceChat:ChannelName()
end

function AllianceChat:Kick(playerName)
    local ch = channelName()
    if not ch or not playerName or playerName == "" or not ChannelKick then
        return false
    end
    ChannelKick(ch, playerName)
    return true
end

function AllianceChat:Ban(playerName)
    local ch = channelName()
    if not ch or not playerName or playerName == "" or not ChannelBan then
        return false
    end
    ChannelBan(ch, playerName)
    return true
end

-- Names currently in the channel, lowercased. Empty when the roster is not
-- populated, which the callers treat as "cannot tell" rather than "nobody".
function AllianceChat:_ChannelNames()
    local out = {}
    local name = self:ChannelName()
    local id = name and GetChannelName and GetChannelName(name)
    if not id or id == 0 or not GetChannelRosterInfo then
        return out
    end
    for i = 1, 400 do
        local ok, who = pcall(GetChannelRosterInfo, id, i)
        if not ok or not who then
            break
        end
        out[who:lower()] = who
    end
    return out
end

-- If WE own the channel and are NOT an ambassador, hand ownership to one.
--
-- WoW gives a custom channel to whoever joined first, which is usually a
-- regular member, so moderation lands on the wrong person by default. This
-- runs on the OWNER's client, which is the only client allowed to transfer,
-- and does nothing anywhere else. If the owner does not run Guild OS there is
-- nothing any of us can do about it, and the Manage tab says so.
function AllianceChat:EnsureAmbassadorOwnership()
    local ally = GuildOS.Alliance
    local pact = ally and ally:Get()
    if not pact or not SetChannelOwner then
        return false
    end
    if self:ModeratorState() ~= "owner" then
        return false   -- only the owner can pass it on
    end
    local me = UnitName("player")
    if GuildOS.Alliance.IsAmbassadorAnywhere(pact, me) then
        return false   -- already in the right hands
    end

    -- Prefer somebody actually in the channel: transferring to an absent
    -- character is silently ignored by the server.
    local present = self:_ChannelNames()
    local ch = self:ChannelName()
    for _, entry in pairs(pact.guilds) do
        for _, amb in ipairs(entry.ambassadors or {}) do
            if present[tostring(amb):lower()] then
                SetChannelOwner(ch, amb)
                BRutus.Logger.Debug("Alliance: handed channel ownership to " .. amb)
                self:PromoteAmbassadors()
                return true
            end
        end
    end
    return false
end

-- Hand channel moderator to every ambassador in the pact. Only the owner can
-- do this, and it is an explicit action rather than something that happens on
-- login: silently changing other people's channel permissions is not the kind
-- of thing an addon should decide on its own.
function AllianceChat:PromoteAmbassadors()
    local ch = channelName()
    local ally = GuildOS.Alliance
    local pact = ally and ally:Get()
    if not ch or not pact or not ChannelModerator then
        return 0
    end
    if self:ModeratorState() ~= "owner" then
        return 0
    end
    local n = 0
    for _, entry in pairs(pact.guilds) do
        for _, amb in ipairs(entry.ambassadors or {}) do
            ChannelModerator(ch, amb)
            n = n + 1
        end
    end
    return n
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

----------------------------------------------------------------------
-- Hiding a message.
--
-- Honest about what this is: the message was already delivered by the server
-- and already printed in the default chat frame, and people without the addon
-- still see it. This removes it from the Guild OS feed, alliance-wide, after
-- the fact. Ban is the tool that actually stops somebody.
--
-- Matched on speaker plus text rather than an id, because there is no id: each
-- client stamps its own arrival time, so any hash including the timestamp
-- would differ between clients. The failure mode of matching on text is that
-- an identical line from the same person also goes, which is harmless.
----------------------------------------------------------------------
AllianceChat.MAX_HIDDEN = 50

function AllianceChat:HiddenStore()
    BRutus.db.allianceHidden = BRutus.db.allianceHidden or {}
    return BRutus.db.allianceHidden
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

-- Every hide anyone in the alliance published, ours included.
function AllianceChat:HiddenSet()
    local lists = { self:HiddenStore() }
    local sync = GuildOS.AllianceSync
    local store = (BRutus.db and BRutus.db.allianceData) or {}
    if sync then
        for _, domains in pairs(store) do
            local entry = domains.hidden
            if entry and type(entry.data) == "table" then
                lists[#lists + 1] = entry.data
            end
        end
    end
    return AllianceChat.BuildHiddenSet(lists)
end

function AllianceChat:HideMessage(name, text)
    local ally = GuildOS.Alliance
    if not ally or not ally:CanAdminister() then
        return false, BRutus.L["Only an alliance ambassador can do that."]
    end
    local clean = BRutus:SanitizeUserText(text, 240)
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
    if BRutus.SyncService then
        BRutus.SyncService:Publish("allyhide", "add", { n = name, m = clean })
    end
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:RefreshLocal("hidden")
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
    store[#store + 1] = { n = d.n, m = BRutus:SanitizeUserText(d.m, 240), ts = GetServerTime() }
    while #store > self.MAX_HIDDEN do
        table.remove(store, 1)
    end
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:RefreshLocal("hidden")
    end
    self:_Notify()
end

function AllianceChat:Clear()
    BRutus.db.allianceChatLog = {}
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

    if BRutus.SyncService then
        BRutus.SyncService:On("allyhide", function(env) AllianceChat:OnHideSync(env) end)
    end
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:Register("hidden", {
            priority = "NORMAL",
            cap = AllianceChat.MAX_HIDDEN,
            build = function()
                local out = {}
                for _, h in ipairs(AllianceChat:HiddenStore()) do
                    out[#out + 1] = { n = h.n, m = h.m }
                end
                table.sort(out, function(a, b)
                    return (tostring(a.n) .. tostring(a.m)) < (tostring(b.n) .. tostring(b.m))
                end)
                return out
            end,
        })
    end

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
    -- Fires whenever the channel list changes, which after a reload is exactly
    -- the moment joining starts working.
    f:RegisterEvent("CHANNEL_UI_UPDATE")
    f:SetScript("OnEvent", function(_, event, msg, author, _, _, _, _, _, _, chanBaseName)
        if event == "CHAT_MSG_CHANNEL" then
            BRutus:SafeCall(function()
                AllianceChat:_OnChannelMessage(msg, author, chanBaseName)
            end)
            return
        end
        if event == "CHANNEL_UI_UPDATE" then
            AllianceChat:EnsureJoined()
            return
        end
        -- Staggered because the chat system comes up at an unpredictable time
        -- after a reload. The watchdog below is what actually guarantees it;
        -- these just make the common case fast.
        for _, delay in ipairs({ 3, 8, 15, 30 }) do
            BRutus.Compat.After(delay, function() AllianceChat:EnsureJoined() end)
        end
        -- Late, so the channel roster has had time to populate: the transfer
        -- needs a target that is actually in the channel.
        BRutus.Compat.After(75, function() AllianceChat:EnsureAmbassadorOwnership() end)
    end)

    if BRutus.Compat and BRutus.Compat.NewTicker then
        -- The watchdog. Never stops, because being outside the channel is not
        -- a state the player should ever be left sitting in.
        BRutus.Compat.NewTicker(self.JOIN_RETRY, function()
            AllianceChat:EnsureJoined()
        end)
        -- Ownership can land on us at any time: WoW passes it on when the
        -- previous owner leaves.
        BRutus.Compat.NewTicker(300, function()
            AllianceChat:EnsureAmbassadorOwnership()
        end)
    end
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
function AllianceChat:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("alliancechat.group_log", function()
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
