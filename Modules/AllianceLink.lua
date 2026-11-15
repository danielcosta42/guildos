----------------------------------------------------------------------
-- Guild OS - The alliance, the GreenWall way (issue #348)
--
-- Modelled on GreenWall (AIE-Guild/GreenWall, the base of Greenwall Forever),
-- because it works without anybody in particular being online:
--
--   * ONE CODE, THE SAME IN EVERY GUILD of the alliance:
--
--         GOS=TAG:key:Guilda A;Guilda B;Guilda C
--
--     An officer of each guild pastes it once in Alliance > Setup. It is NOT
--     sent between guilds: nobody has to be an ambassador. GreenWall keeps it
--     in the guild info; here it is the addon's own data (db.allianceLink),
--     handed to the guild over the GUILD channel (SyncService "allylink"):
--     an officer's "set" reaches whoever is online, and anybody who logs in
--     asks ("ask") and is answered by any guildmate that holds it ("have").
--     The newest revision wins, and a removal is kept as one, so an old copy
--     never brings the alliance back. Only an officer authors it: "set" is an
--     officer write, and a relayed copy counts only when the officer it names
--     is an officer on the roster.
--
--   * ONE HIDDEN CHANNEL WITH A PASSWORD ("GOSA" .. TAG, the key). Every
--     member joins it and it is taken out of every chat frame.
--
--   * EVERY MEMBER CARRIES THEIR OWN WORDS. When the player presses Enter on
--     a line of /g, their own client says it on the channel too, inside the
--     same key press (Compat.HookChatSend), which is the only moment the game
--     lets an addon say anything on a channel. No bridge, no whisper, no
--     route: whoever is online hears whoever is online.
--
--   * WHO RECEIVES IT DRAWS IT AS /g. The line goes through the chat frame's
--     own handler as CHAT_MSG_GUILD (Compat.ReplayChatEvent): same colour,
--     same timestamp, same name link and class colour, the speaker's guild as
--     a tag in front.
--
-- On the channel a line is "<kind><code> <text>": kind G for /g, A for the
-- alliance room (Modules/AllianceChat.lua), code the speaker's guild
-- (Code). The speaker is the channel's sender, which nobody can forge.
--
-- The data the alliance shares (rosters, calendars, crafters) still goes by
-- whisper, timers cannot speak on a channel. With this configuration it is
-- trusted by a proof only who read the key can make (Proof), never by a list
-- of names (Modules/Alliance.lua).
--
-- HONEST LIMITS, the same as GreenWall's: who does not run Guild OS does not
-- see the other guilds; the key is readable by every member of every guild in
-- it; a line sent by a macro does not cross, since no key was pressed.
----------------------------------------------------------------------
local Link = {}
GuildOS.AllianceLink = Link
local L = GuildOS.L

Link.DIRECTIVE  = "GOS="
Link.MAX_GUILDS = 16
Link.KEY_LEN    = 10
Link.MAX_LINE   = 255     -- what the game sends in one line of chat
Link.ASK_DELAY  = 12      -- seconds after login before asking the guild for the code
Link.ANSWER_MAX = 4       -- seconds a holder waits before answering, so one answers, not all

Link.stats = { sent = 0, heard = 0, shown = 0, dropped = 0 }

local function shortName(name)
    local s = tostring(name or "")
    return (Ambiguate and Ambiguate(s, "short")) or s
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Pure. Pinned by tools/alliance-link.lua
----------------------------------------------------------------------

-- A guild's three-character code on the channel. Every client computes the
-- same one from the name (Alliance.Hash is part of the protocol).
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function Link.Code(guildName)
    local n = GuildOS.Alliance.Hash(tostring(guildName or "")) % 46656
    local out = ""
    for _ = 1, 3 do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    end
    return out
end

-- The configuration in a text, or nil. Only the first GOS= line
-- counts. A configuration with a repeated code (two names hashing alike) is
-- refused whole: the lines of one would show under the other.
function Link.Parse(text)
    if type(text) ~= "string" then
        return nil
    end
    for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
        local tag, key, list = line:match("^%s*GOS=([%w]+):([%w]+):(.+)$")
        if tag then
            tag = GuildOS.Alliance.NormalizeTag(tag)
            if tag == "" or #key < 4 then
                return nil
            end
            local guilds, codes, order = {}, {}, {}
            for name in (list .. ";"):gmatch("([^;]*);") do
                name = trim(name)
                if name ~= "" and not guilds[name] and #order < Link.MAX_GUILDS then
                    local code = Link.Code(name)
                    if codes[code] then
                        return nil
                    end
                    guilds[name], codes[code] = code, name
                    order[#order + 1] = name
                end
            end
            if #order < 2 then
                return nil
            end
            return { tag = tag, key = key, guilds = guilds, codes = codes, order = order, line = trim(line) }
        end
    end
    return nil
end

-- The line for a configuration.
function Link.Build(tag, key, guilds)
    return Link.DIRECTIVE .. GuildOS.Alliance.NormalizeTag(tag) .. ":" .. tostring(key) .. ":"
        .. table.concat(guilds, ";")
end

function Link.NewKey()
    local out = {}
    for i = 1, Link.KEY_LEN do
        local d = math.random(1, 62)
        out[i] = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"):sub(d, d)
    end
    return table.concat(out)
end

-- What only who read the key can say about `name`. Carried by the data ops.
function Link.Proof(key, name)
    return string.format("%08x", GuildOS.Alliance.Hash(tostring(key) .. "\0" .. shortName(name):lower()))
end

-- A line on the channel: kind, guild code, text.
function Link.Encode(kind, code, text)
    return GuildOS:CutBytes(kind .. code .. " " .. tostring(text or ""), Link.MAX_LINE)
end

function Link.Decode(msg)
    if type(msg) ~= "string" then
        return nil
    end
    local kind, code, text = msg:match("^([GA])(%w%w%w) (.+)$")
    return kind, code, text
end

----------------------------------------------------------------------
-- The configuration in force
----------------------------------------------------------------------
-- What this guild holds: { line, rev, by }. `line` nil is a removal, kept
-- with its revision.
function Link:Store()
    GuildOS.db.allianceLink = GuildOS.db.allianceLink or { rev = 0 }
    return GuildOS.db.allianceLink
end

function Link:Config()
    local line = GuildOS.db and GuildOS.db.allianceLink and GuildOS.db.allianceLink.line
    if line ~= self._text then
        self._text = line
        self._config = line and Link.Parse(line) or nil
    end
    return self._config
end

-- The pact the rest of the alliance reads (Alliance:Get), or nil: only while
-- the guild holds a code that names this guild.
function Link:Pact()
    local cfg = self:Config()
    local mine = GuildOS.Alliance:MyGuildName()
    if not cfg or not mine or not cfg.guilds[mine] then
        return nil
    end
    local p = self._pact
    if not p or p.line ~= cfg.line then
        GuildOS.db.allianceLinkBlocked = GuildOS.db.allianceLinkBlocked or {}
        local guilds = {}
        for _, name in ipairs(cfg.order) do
            guilds[name] = { ambassadors = {}, joinedAt = 0 }
        end
        p = {
            source = "link", line = cfg.line,
            tag = cfg.tag, name = cfg.tag, owner = cfg.order[1], revision = 0,
            guilds = guilds, key = cfg.key,
        }
        self._pact = p
    end
    p.blocked = GuildOS.db.allianceLinkBlocked
    return p
end

function Link:Active()
    return self:Pact() ~= nil
end

function Link:ChannelName()
    local cfg = self:Pact() and self:Config()
    return cfg and ("GOSA" .. cfg.tag) or nil
end

function Link:ChannelIndex()
    local name = self:ChannelName()
    local id = name and GetChannelName and GetChannelName(name)
    return (id and id > 0) and id or nil
end

----------------------------------------------------------------------
-- Joining. Idempotent; AllianceChat's watchdog calls it.
----------------------------------------------------------------------
function Link:EnsureJoined()
    local name = self:ChannelName()
    if not name then
        return false
    end
    if not self:ChannelIndex() then
        GuildOS.Compat.JoinPrivateChannel(name, self:Config().key)
    end
    local ok = self:ChannelIndex() ~= nil
    if ok then
        GuildOS.Compat.RemoveChannelFromFrames(name)
    end
    -- The old pact's public channel (GOS<TAG>) is the client's saved channel:
    -- with the line in force nothing reads it, so it is left once.
    local legacy = GuildOS.db and GuildOS.db.alliance
    local old = legacy and GuildOS.Alliance.ChannelName(legacy.tag)
    if old and old:lower() ~= name:lower() and GetChannelName and (GetChannelName(old) or 0) > 0
        and LeaveChannelByName then
        LeaveChannelByName(old)
    end
    return ok
end

----------------------------------------------------------------------
-- Out: only ever inside the player's key press
----------------------------------------------------------------------
function Link:Say(kind, text)
    local pact = self:Pact()
    local index = self:ChannelIndex()
    local mine = GuildOS.Alliance:MyGuildName()
    if not pact or not index or not mine then
        return false
    end
    local ok = GuildOS.Compat.SendChannelMessage(Link.Encode(kind, Link.Code(mine), text), index)
    if ok then
        self.stats.sent = self.stats.sent + 1
    end
    return ok
end

-- A line of /g the player just sent. Officer chat and the guild's other
-- channels never come here.
function Link:OnPlayerChat(chatType, text)
    if chatType == "GUILD" then
        self:Say("G", text)
    end
end

----------------------------------------------------------------------
-- In
----------------------------------------------------------------------
-- The allied guild a channel line came from, or nil. `author` is the
-- channel's sender.
function Link:GuildOfLine(code, author)
    local pact = self:Pact()
    local cfg = pact and self:Config()
    local guild = cfg and cfg.codes[code]
    if not guild or guild == GuildOS.Alliance:MyGuildName() or pact.blocked[guild] then
        return nil
    end
    -- Somebody the synced rosters place in another guild is not believed.
    local sync = GuildOS.AllianceSync
    local hit = sync and sync.MemberIndex and sync:MemberIndex()[shortName(author):lower()]
    if hit and hit.guild ~= guild then
        return nil
    end
    return guild
end

function Link:_OnChannel(msg, author, lang, _, target, flags, _, _, chanBaseName,
                         _, lineID, guid)
    local name = self:ChannelName()
    if not name or type(chanBaseName) ~= "string" or chanBaseName:lower() ~= name:lower() then
        return
    end
    if GuildOS.Compat.IsSecret(msg, author) or not msg or not author then
        return
    end
    if shortName(author):lower() == (GuildOS.Compat.PlayerName() or ""):lower() then
        return
    end
    self.stats.heard = self.stats.heard + 1
    local kind, code, text = Link.Decode(msg)
    local guild = kind and self:GuildOfLine(code, author)
    if not guild then
        self.stats.dropped = self.stats.dropped + 1
        return
    end
    if GuildOS.Compat.IsIgnored(author) then
        return
    end
    local chat = GuildOS.AllianceChat
    if chat and chat:HiddenSet()[chat.HiddenKey(shortName(author), text)] then
        return
    end
    if kind == "A" then
        if chat then chat:PushLine(shortName(author), guild, text) end
        return
    end
    if chat and not chat:Prefs().guildBridge then
        return
    end
    self.stats.shown = self.stats.shown + 1
    local tagged = "|cff" .. GuildOS.Alliance.GuildColorHex(guild) .. "[" .. guild .. "]|r " .. text
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and GuildOS.Compat.ChatFrameShows(f, "GUILD") then
            if not GuildOS.Compat.ReplayChatEvent(f, "CHAT_MSG_GUILD", tagged, author, lang, "", target, flags,
                                                  0, 0, "", 0, lineID, guid) and f.AddMessage then
                f:AddMessage(Link.FormatPlain(guild, author, text))
            end
        end
    end
    if GuildOS.GuildChat and GuildOS.GuildChat.AddAllied then
        local class
        if guid and GetPlayerInfoByGUID and not GuildOS.Compat.IsSecret(guid) then
            local _, c = GetPlayerInfoByGUID(guid)
            if not GuildOS.Compat.IsSecret(c) then class = c end
        end
        GuildOS.GuildChat:AddAllied(guild, { n = author, m = text, c = class })
    end
end

-- Where a frame has no handler to replay through: the line as /g reads.
function Link.FormatPlain(guild, author, text)
    local tag = "|cff" .. GuildOS.Alliance.GuildColorHex(guild) .. "[" .. guild .. "]|r"
    local who = tag .. " |Hplayer:" .. author .. "|h[" .. shortName(author) .. "]|h"
    local head = (type(CHAT_GUILD_GET) == "string" and CHAT_GUILD_GET:find("%s", 1, true))
        and CHAT_GUILD_GET:format(who) or ("[" .. L["Guild"] .. "] " .. who .. ": ")
    return head .. text
end

-- The channel's raw lines and its join/leave notices never print: the
-- channel is the addon's wire, not a room.
function Link:_Filter(chanBaseName)
    local name = self:ChannelName()
    return name ~= nil and type(chanBaseName) == "string" and chanBaseName:lower() == name:lower()
end

----------------------------------------------------------------------
-- The code, kept by the guild
----------------------------------------------------------------------
-- Pure. Does an incoming copy replace what is held? Only a newer revision.
function Link.Newer(held, rev)
    return (tonumber(rev) or 0) > (tonumber(held and held.rev) or 0)
end

function Link:_Changed()
    self._pact = nil
    if self:Pact() then
        self:EnsureJoined()
    end
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
end

-- An officer saves `line` for the guild (nil turns the alliance off). A
-- button click; the guild gets it at once over GUILD.
function Link:SetCode(line)
    if not GuildOS:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    if line then
        line = trim(line)
        local cfg = Link.Parse(line)
        local mine = GuildOS.Alliance:MyGuildName()
        if not cfg then
            return false, L["That is not an alliance code."]
        end
        if not mine or not cfg.guilds[mine] then
            return false, L["The code does not name this guild."]
        end
        line = cfg.line
    end
    local held = self:Store()
    local rev = math.max(GetServerTime(), (tonumber(held.rev) or 0) + 1)
    local by = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    held.line, held.rev, held.by = line, rev, by
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("allylink", "set", { line = line, rev = rev, by = by }, { priority = "ALERT" })
    end
    self:_Changed()
    return true
end

-- A copy from the guild. `trusted` is an officer's own "set"; a relayed
-- "have" counts only when the officer it names is one on the roster.
function Link:_Take(d, sender, trusted)
    if type(d) ~= "table" or not Link.Newer(self:Store(), d.rev) then
        return false
    end
    local by = type(d.by) == "string" and d.by or nil
    if trusted then
        by = by or sender
    elseif not by or not GuildOS:IsOfficerByName(by) then
        return false
    end
    local line = type(d.line) == "string" and d.line or nil
    local mine = GuildOS.Alliance:MyGuildName()
    local cfg = line and Link.Parse(line)
    if line and (not cfg or not mine or not cfg.guilds[mine]) then
        return false
    end
    local held = self:Store()
    held.line, held.rev, held.by = cfg and cfg.line or nil, tonumber(d.rev), by
    self:_Changed()
    return true
end

function Link:OnSync(env, sender)
    local d = env and env.data
    if type(d) ~= "table" then return end
    if env.act == "set" then
        self:_Take(d, sender, true)
    elseif env.act == "have" then
        self._answered = (tonumber(d.rev) or 0)
        self:_Take(d, sender, false)
    elseif env.act == "ask" then
        local held = self:Store()
        if not Link.Newer({ rev = d.rev }, held.rev) then
            return   -- nothing newer than what they hold
        end
        -- Wait a moment: whoever answers first saves everybody else the send.
        local want = tonumber(held.rev) or 0
        self._answered = nil
        GuildOS.Compat.After(math.random() * self.ANSWER_MAX, function()
            if (self._answered or -1) >= want then return end
            local now = self:Store()
            GuildOS.SyncService:Publish("allylink", "have", { line = now.line, rev = now.rev, by = now.by })
        end)
    end
end

function Link:Ask()
    if GuildOS.SyncService and IsInGuild and IsInGuild() then
        GuildOS.SyncService:Publish("allylink", "ask", { rev = tonumber(self:Store().rev) or 0 })
    end
end

-- What the panel offers: the line in force, or one made from the old pact
-- (tag and guilds kept, a new key), or nil.
function Link:Suggest()
    local cfg = self:Config()
    if cfg then
        return cfg.line
    end
    local legacy = GuildOS.db and GuildOS.db.alliance
    if legacy and legacy.tag and type(legacy.guilds) == "table" then
        local names = {}
        for name in pairs(legacy.guilds) do names[#names + 1] = name end
        table.sort(names)
        return Link.Build(legacy.tag, Link.NewKey(), names)
    end
    return nil
end

function Link:StatusLine()
    local s = self.stats
    return string.format("%s · sent %d · heard %d · shown %d · dropped %d",
        tostring(self:ChannelName() or "-"), s.sent, s.heard, s.shown, s.dropped)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function Link:Initialize()
    GuildOS.Compat.HookChatSend(function(chatType, text)
        GuildOS:SafeCall(function() Link:OnPlayerChat(chatType, text) end)
    end)
    local function hide(_, _, _, _, _, _, _, _, _, _, chanBaseName)
        return Link:_Filter(chanBaseName)
    end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
                              "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
        GuildOS.Compat.AddChatFilter(event, hide)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_CHANNEL" then
            local args = { ... }
            GuildOS:SafeCall(function() Link:_OnChannel(unpack(args, 1, 12)) end)
        elseif not Link._asked then
            -- Once a session: whatever the guild has newer than ours (a code saved
            -- while we were away, or ours lost with a reinstall) comes now.
            Link._asked = true
            GuildOS.Compat.After(Link.ASK_DELAY, function() GuildOS:SafeCall(function() Link:Ask() end) end)
        end
    end)
    if GuildOS.SyncService then
        GuildOS.SyncService:On("allylink", function(env, sender) Link:OnSync(env, sender) end)
    end
end
