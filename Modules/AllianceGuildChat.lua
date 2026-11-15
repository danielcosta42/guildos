----------------------------------------------------------------------
-- Guild OS - The alliance's guild chat (issue #344)
--
-- Every line of /g in one guild of the alliance shows in the guild chat of
-- every other one, in the frames that show /g, in /g's colour, with the
-- speaker's guild as a coloured tag and the name a link that whispers them:
--
--   [Guild] [Guild B] [Fulano]: alguém pra kara?
--
-- WHY IT TRAVELS LIKE THIS: addon messages on a custom channel are refused on
-- Forever and retail, and a chat post on a channel needs a key press, so the
-- only bus between guilds is WHISPER and inside one it is GUILD (see the
-- header of Modules/Alliance.lua). So:
--
--   1. The guild's BRIDGE (Alliance:CurrentBridge, the same one AllianceSync
--      elects) reads every CHAT_MSG_GUILD and, after BATCH_DELAY, whispers the
--      lines to ONE compatible client online in each allied guild ("L").
--   2. That client checks the sender speaks for the guild it claims, shows the
--      lines and says them once on GUILD ("F"), so its whole guild has them.
--   3. Everybody else only receives. A line that came from outside never goes
--      out again: only CHAT_MSG_GUILD is relayed, and nothing here makes one.
--
-- Two paths, an election that overlaps for a moment, the game echoing our own
-- GUILD message back: the same line can arrive twice, so every line is shown
-- once per DEDUP_WINDOW by guild, speaker and text.
--
-- ROUTES: whom to whisper in guild X. First whoever sent us X's chat in the
-- last ROUTE_TTL (proof they are online and run this), then a presence peer of
-- X advertising "gosc=1" (Mesh:BuildCaps). Never blind: a line with no route
-- is lost for that guild, which is right, since nobody there could show it.
--
-- TRUST: the whisper's sender (the envelope, never the payload) must be an
-- ambassador of the guild it claims or be on that guild's synced roster, the
-- guild must be in the pact and not blocked. The GUILD hop is a guildmate, who
-- could already type anything in /g. Officer chat and the guild's other
-- channels never leave: only CHAT_MSG_GUILD is read.
--
-- HONEST LIMIT: who does not run Guild OS does not see the other guilds. The
-- game cannot post a line in somebody else's name.
----------------------------------------------------------------------
local AGC = {}
GuildOS.AllianceGuildChat = AGC

AGC.PREFIX = "ChehulAllyChat"   -- 14 of the 16 bytes a prefix may have
AGC.PROTO  = "AC1"
AGC.CAP    = "gosc=1"           -- in the HELLO caps: this client takes "L"

AGC.BATCH_DELAY  = 0.4   -- seconds lines wait to share one whisper
AGC.MAX_BATCH    = 10    -- lines per whisper; more goes in the next one
AGC.DEDUP_WINDOW = 120   -- seconds a line is remembered as shown
AGC.ROUTE_TTL    = 900   -- seconds a sender stays a route to its guild
AGC.MAX_TEXT     = 260   -- bytes of one line on the wire (the game caps /g at 255)
AGC.MAX_NAME     = 48

AGC.stats = { out = 0, linesOut = 0, inL = 0, inF = 0, shown = 0, dup = 0, rejected = 0, noRoute = 0 }

local function now()
    return (GetServerTime and GetServerTime()) or time()
end

-- The same short name Modules/Alliance.lua matches ambassadors and rosters by.
local function shortName(name)
    local s = tostring(name or "")
    return (Ambiguate and Ambiguate(s, "short")) or s
end

local function Ally()
    return GuildOS.Alliance
end

----------------------------------------------------------------------
-- Pure helpers, pinned by tools/alliance-guild-chat.lua
----------------------------------------------------------------------

-- The links a line of /g may carry across. Anything else with a pipe is shown
-- as the text it is (a pipe doubled), so a peer cannot draw textures, colours
-- or links of its own making on our screen.
AGC.LINKS = {
    item = true, spell = true, enchant = true, achievement = true, quest = true,
    talent = true, trade = true, battlepet = true, currency = true, mount = true,
    transmogappearance = true, keystone = true, journal = true, player = true,
}

-- Pure. A line as it may be drawn: whitespace for control characters, allowed
-- links kept whole, every other pipe made literal.
function AGC.CleanText(text, max)
    local s = tostring(text or "")
    max = max or AGC.MAX_TEXT
    if #s > max then
        s = s:sub(1, max)
    end
    s = s:gsub("%c", " ")
    local keep = {}
    local function hold(whole, kind)
        if not AGC.LINKS[kind] then
            return nil   -- untouched here, escaped below
        end
        keep[#keep + 1] = whole
        return "\1" .. #keep .. "\2"
    end
    -- |cffRRGGBB (classic) or |cnIQ4: (retail quality colour) around a link.
    s = s:gsub("(|c%x%x%x%x%x%x%x%x|H(%a+):[^|]*|h%b[]|h|r)", hold)
    s = s:gsub("(|cn[%w_]*:|H(%a+):[^|]*|h%b[]|h|r)", hold)
    s = s:gsub("(|H(%a+):[^|]*|h%b[]|h)", hold)
    s = s:gsub("|", "||")
    s = s:gsub("\1(%d+)\2", function(i) return keep[tonumber(i)] end)
    return (strtrim and strtrim(s)) or s
end

-- Pure. The key a line is known by, the same on every client.
function AGC.LineKey(guild, name, text)
    return tostring(guild or "") .. "\0" .. shortName(name):lower() .. "\0" .. tostring(text or "")
end

-- Pure. Has `key` been seen within `window`? Marks it seen either way and
-- forgets what aged out, so the table stays the size of the window.
function AGC.SeenBefore(seen, key, t, window)
    window = window or AGC.DEDUP_WINDOW
    local at = seen[key]
    seen[key] = t
    if at and (t - at) < window then
        return true
    end
    seen._n = (seen._n or 0) + 1
    if seen._n > 200 then
        seen._n = 0
        for k, v in pairs(seen) do
            if k ~= "_n" and (t - v) >= window then
                seen[k] = nil
            end
        end
    end
    return false
end

-- Pure. The lines of `lines` not seen within the window, without marking them.
function AGC.Fresh(seen, guild, lines, t, window)
    window = window or AGC.DEDUP_WINDOW
    local out = {}
    for _, line in ipairs(lines) do
        local at = seen[AGC.LineKey(guild, line.n, line.m)]
        if not at or (t - at) >= window then
            out[#out + 1] = line
        end
    end
    return out
end

-- Pure. Which guild `sender` may speak for in the chat: an ambassador of
-- `claimed`, or somebody on its synced roster. nil refuses.
function AGC.SpeaksFor(pact, claimed, sender, rosterIndex, myGuild)
    if type(pact) ~= "table" or type(pact.guilds) ~= "table" then
        return nil
    end
    if type(claimed) ~= "string" or claimed == "" or claimed == myGuild then
        return nil
    end
    if not pact.guilds[claimed] or (pact.blocked and pact.blocked[claimed]) then
        return nil
    end
    if GuildOS.Alliance.IsAmbassador(pact, claimed, sender) then
        return claimed
    end
    local hit = type(rosterIndex) == "table" and rosterIndex[shortName(sender):lower()]
    if hit and hit.guild == claimed then
        return claimed
    end
    return nil
end

-- Pure. The lines of a payload that may be shown, cleaned. Anything malformed
-- is dropped on its own, so one bad line never costs the rest.
function AGC.ReadLines(lines)
    local out = {}
    if type(lines) ~= "table" then
        return out
    end
    for i = 1, math.min(#lines, AGC.MAX_BATCH) do
        local l = lines[i]
        if type(l) == "table" and type(l.n) == "string" and type(l.m) == "string" then
            local n = GuildOS:SanitizeUserText(l.n, AGC.MAX_NAME)
            local m = AGC.CleanText(l.m)
            if n ~= "" and m ~= "" then
                local c = type(l.c) == "string" and l.c:match("^%u+$") or nil
                out[#out + 1] = { n = n, m = m, c = c, t = tonumber(l.t) }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
AGC.seen   = {}   -- [LineKey] = time shown
AGC.routes = {}   -- [guild] = { name = "Name-Realm", ts = t }
AGC.queue  = {}   -- lines waiting for the next whisper

function AGC:Enabled()
    local chat = GuildOS.AllianceChat
    return chat and chat:Prefs().guildBridge ~= false
end

----------------------------------------------------------------------
-- Routes
----------------------------------------------------------------------
function AGC:LearnRoute(guild, name)
    if type(guild) == "string" and type(name) == "string" and name ~= "" then
        self.routes[guild] = { name = name, ts = now() }
    end
end

function AGC:ForgetRoute(name)
    local short = shortName(name):lower()
    for guild, r in pairs(self.routes) do
        if shortName(r.name):lower() == short then
            self.routes[guild] = nil
        end
    end
end

-- A presence peer of `guild` that says it takes the chat, freshest first.
function AGC:_MeshTarget(guild)
    local net, mesh = _G.ChehulNet, GuildOS.Mesh
    if not net or not net.Peers or not mesh then
        return nil
    end
    local best, bestTs
    for short, peer in pairs(net:Peers()) do
        local caps = type(peer.caps) == "string" and peer.caps or ""
        if caps:find(AGC.CAP, 1, true) and mesh:GetPeerGuild(short) == guild
            and (not bestTs or (peer.ts or 0) > bestTs) then
            best, bestTs = short, peer.ts or 0
        end
    end
    return best
end

function AGC:Route(guild)
    local r = self.routes[guild]
    if r and (now() - (r.ts or 0)) < self.ROUTE_TTL then
        return r.name
    end
    return self:_MeshTarget(guild)
end

----------------------------------------------------------------------
-- Wire
----------------------------------------------------------------------
local function frame(op, tbl)
    local blob = GuildOS.Alliance.Encode(tbl)
    return blob and (AGC.PROTO .. "|" .. op .. "|" .. blob) or nil
end

----------------------------------------------------------------------
-- Out: the bridge relays its guild's /g
----------------------------------------------------------------------
-- Asked on every line of /g, and the answer walks the whole roster, so it is
-- kept for BRIDGE_CHECK seconds (the election itself holds for 30).
AGC.BRIDGE_CHECK = 10

function AGC:_AmBridge(ally)
    local t = now()
    if self._bridgeAt and (t - self._bridgeAt) < self.BRIDGE_CHECK then
        return self._amBridge
    end
    self._bridgeAt, self._amBridge = t, ally:AmBridge() and true or false
    return self._amBridge
end

function AGC:_OnGuildLine(msg, author, guid)
    if GuildOS.Compat.IsSecret(msg, author) or not msg or not author then
        return
    end
    local ally = Ally()
    local pact = ally and ally:Get()
    if not pact or not self:_AmBridge(ally) then
        return
    end
    local m = AGC.CleanText(msg)
    if m == "" then
        return
    end
    local class
    if guid and not GuildOS.Compat.IsSecret(guid) and GetPlayerInfoByGUID then
        local _, c = GetPlayerInfoByGUID(guid)
        if not GuildOS.Compat.IsSecret(c) then class = c end
    end
    self.queue[#self.queue + 1] = { n = author, m = m, c = class, t = now() }
    if not self._flushing then
        self._flushing = true
        GuildOS.Compat.After(self.BATCH_DELAY, function() AGC:Flush() end)
    end
end

function AGC:Flush()
    self._flushing = false
    local ally = Ally()
    local pact = ally and ally:Get()
    local mine = ally and ally:MyGuildName()
    local mesh = _G.ChehulMesh
    if #self.queue == 0 then
        return
    end
    if not pact or not mine or not mesh then
        self.queue = {}
        return
    end
    local lines = {}
    for i = 1, math.min(#self.queue, self.MAX_BATCH) do
        lines[i] = self.queue[i]
    end
    local rest = {}
    for i = self.MAX_BATCH + 1, #self.queue do
        rest[#rest + 1] = self.queue[i]
    end
    self.queue = rest
    local payload = frame("L", { g = mine, l = lines })
    if payload then
        for guild in pairs(pact.guilds) do
            if guild ~= mine and not ally:IsBlocked(guild) then
                local target = self:Route(guild)
                if target then
                    GuildOS:NoteWhisper(target)
                    if mesh:Whisper(self.PREFIX, payload, target) then
                        self.stats.out = self.stats.out + 1
                        self.stats.linesOut = self.stats.linesOut + #lines
                    end
                else
                    self.stats.noRoute = self.stats.noRoute + 1
                end
            end
        end
    end
    if #self.queue > 0 then
        self._flushing = true
        GuildOS.Compat.After(self.BATCH_DELAY, function() AGC:Flush() end)
    end
end

----------------------------------------------------------------------
-- In
----------------------------------------------------------------------
function AGC:OnMessage(payload, sender, dist)
    if type(payload) ~= "string" or type(sender) ~= "string" then
        return
    end
    local proto, op, blob = strsplit("|", payload, 3)
    if proto ~= self.PROTO or not blob then
        return
    end
    if shortName(sender):lower() == (GuildOS.Compat.PlayerName() or ""):lower() then
        return   -- our own GUILD echo: shown when it was received
    end
    local ally = Ally()
    local pact = ally and ally:Get()
    if not pact then
        return
    end
    local data = GuildOS.Alliance.Decode(blob)
    if type(data) ~= "table" then
        return
    end
    local mine = ally:MyGuildName()

    if op == "L" and dist == "WHISPER" then
        self.stats.inL = self.stats.inL + 1
        local sync = GuildOS.AllianceSync
        local guild = AGC.SpeaksFor(pact, data.g, sender, sync and sync:MemberIndex(), mine)
        if not guild then
            self.stats.rejected = self.stats.rejected + 1
            return
        end
        self:LearnRoute(guild, sender)
        -- Only what this client has not shown yet goes on: a line a second relayer
        -- of that guild already brought here, the guild has had once already.
        local lines = AGC.Fresh(self.seen, guild, AGC.ReadLines(data.l), now())
        if #lines == 0 then
            return
        end
        -- Said on GUILD before it is shown, so the guild does not wait on our frames.
        local mesh = _G.ChehulMesh
        local out = frame("F", { g = guild, r = sender, l = lines })
        if mesh and out then
            mesh:Guild(self.PREFIX, out)
        end
        self:_ShowAll(guild, lines)
    elseif op == "F" and dist == "GUILD" then
        self.stats.inF = self.stats.inF + 1
        local guild = data.g
        if type(guild) ~= "string" or guild == mine or not pact.guilds[guild] or ally:IsBlocked(guild) then
            self.stats.rejected = self.stats.rejected + 1
            return
        end
        -- Who reached us from there is a route for whoever is bridge here next.
        if type(data.r) == "string" then
            self:LearnRoute(guild, GuildOS:SanitizeUserText(data.r, AGC.MAX_NAME))
        end
        self:_ShowAll(guild, AGC.ReadLines(data.l))
    end
end

----------------------------------------------------------------------
-- Showing
----------------------------------------------------------------------
local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then
        return c.colorStr
    end
    if c and c.r then
        return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return nil
end

-- Pure but for the game's globals. The line as the default chat frame draws a
-- line of /g, the speaker's guild tag in front of the name.
function AGC.Format(guild, line)
    local tag = "|cff" .. GuildOS.Alliance.GuildColorHex(guild) .. "[" .. guild .. "]|r"
    local label = shortName(line.n)
    local hex = classHex(line.c)
    if hex then
        label = "|c" .. hex .. label .. "|r"
    end
    local who = tag .. " |Hplayer:" .. line.n .. "|h[" .. label .. "]|h"
    local head = (type(CHAT_GUILD_GET) == "string" and CHAT_GUILD_GET:find("%s", 1, true))
        and CHAT_GUILD_GET:format(who) or ("[" .. ((GuildOS.L and GuildOS.L["Guild"]) or "Guild") .. "] " .. who .. ": ")
    return head .. line.m
end

function AGC:_Print(text)
    local info = ChatTypeInfo and ChatTypeInfo.GUILD
    local r, g, b = 0.25, 1, 0.25
    if info then r, g, b = info.r or r, info.g or g, info.b or b end
    local stamp = CHAT_TIMESTAMP_FORMAT
    if stamp and BetterDate then
        text = BetterDate(stamp, time()) .. text
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.AddMessage and GuildOS.Compat.ChatFrameShows(f, "GUILD") then
            f:AddMessage(text, r, g, b, info and info.id)
        end
    end
end

function AGC:_ShowAll(guild, lines)
    local hidden = GuildOS.AllianceChat and GuildOS.AllianceChat:HiddenSet() or {}
    local t = now()
    for _, line in ipairs(lines) do
        if AGC.SeenBefore(self.seen, AGC.LineKey(guild, line.n, line.m), t) then
            self.stats.dup = self.stats.dup + 1
        elseif not GuildOS.Compat.IsIgnored(line.n)
            and not hidden[GuildOS.AllianceChat.HiddenKey(shortName(line.n), line.m)] then
            self.stats.shown = self.stats.shown + 1
            if self:Enabled() then
                self:_Print(AGC.Format(guild, line))
                if GuildOS.GuildChat and GuildOS.GuildChat.AddAllied then
                    GuildOS.GuildChat:AddAllied(guild, line)
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Diagnostics: /gos ally gchat
----------------------------------------------------------------------
function AGC:StatusLine()
    local s = self.stats
    local routes = 0
    for _ in pairs(self.routes) do routes = routes + 1 end
    return string.format("out %d (%d lines) · in %d+%d · shown %d · dup %d · rejected %d · no route %d · routes %d",
        s.out, s.linesOut, s.inL, s.inF, s.shown, s.dup, s.rejected, s.noRoute, routes)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function AGC:Initialize()
    local mesh = _G.ChehulMesh
    if mesh and not self._registered then
        self._registered = true
        mesh:Register(self.PREFIX, function(payload, sender, dist)
            GuildOS:SafeCall(function() AGC:OnMessage(payload, sender, dist) end)
        end)
    end
    -- A whisper that answered "No player named": that route is gone.
    if GuildOS.OnWhisperNotFound then
        GuildOS:OnWhisperNotFound(function(name) AGC:ForgetRoute(name) end)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author, ...)
        local guid = select(10, ...)
        GuildOS:SafeCall(function() AGC:_OnGuildLine(msg, author, guid) end)
    end)
end
