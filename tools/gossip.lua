-- ChehulGossip (specs/071-o-recrutamento in guildos-web, Task B2): the whisper gossip that carries an
-- ad past the zone and the layer of whoever yells. One sandbox per client, each with the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Libs/LibChehulMesh.lua, Modules/RecruitBeacon.lua and
-- Modules/ChehulGossip.lua, booted by the real GuildOS:InitModules, on a fake bus under AceComm and a
-- fake clock. Whisper, GUILD, group and YELL each reach who they reach in the game; a whisper to nobody
-- answers with the client's "no such player" line, through the chat filters.
--
-- The rules: 50 clients in separate zones, each knowing two neighbours, all get an ad within 12 rounds;
-- no client ever says more than its ceiling, however many ask; a peer goes stale; inside an instance
-- or a chat lockdown nothing goes out; with no echo from the whisper test nothing goes by whisper, and
-- the spelling that came back is the one used; no line reaches the chat; trash off the network breaks
-- nothing; CR2 still reaches RecruitBeacon; and Anniversary stays out of it.
--
--   luajit -e 'ADDON="."' tools/gossip.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

local PREFIX = "ChehulRecruit"
local EPOCH = 1790000000
local NOT_FOUND = "No player named '%s' is currently playing."

-- strsplit keeps the empty fields, which is the whole point of a '|' protocol.
local function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local at = s:find(delim, from, true)
    if not at then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
  return unpack(out)
end

-- A value that raises on any use but passing it along, like the client's secrets.
local function raises() error("a secret was read") end
local SECRET = setmetatable({}, { __index = raises, __concat = raises, __len = raises, __lt = raises, __le = raises,
                                  __tostring = raises, __call = raises })

-- ── The clock ───────────────────────────────────────────────────────────
local clock, queue, world = 0, {}, nil

local function at(when, fn)
  local i = #queue
  while i > 0 and queue[i].when > when do i = i - 1 end
  table.insert(queue, i + 1, { when = when, fn = fn })
end

local function run(seconds)
  local stop = clock + seconds
  while queue[1] and queue[1].when <= stop do
    local item = table.remove(queue, 1)
    clock = item.when
    item.fn()
  end
  clock = stop
end

--- A new world. `spelling` is how a whisper to a surname reaches somebody: "space", "hyphen", or "none"
--- for no whisper at all.
local function fresh(spelling)
  queue, world = {}, { clients = {}, spelling = spelling or "space", log = {} }
end

-- ── The bus ─────────────────────────────────────────────────────────────
local function reach(from, target)
  if world.spelling == "none" then return nil end
  for _, c in ipairs(world.clients) do
    if c.online then
      if c.game == "forever" then
        local spelled = world.spelling == "hyphen" and c.name:gsub(" ", "-") or c.name
        if target == spelled then return c end
      elseif target == c.name .. "-" .. c.realm or (target == c.name and c.realm == from.realm) then
        return c
      end
    end
  end
end

-- What AceComm hands over: Ambiguate(sender, "none"), the realm only when it is not the reader's.
local function senderSeenBy(from, to)
  if from.game == "forever" or from.realm == to.realm then return from.name end
  return from.name .. "-" .. from.realm
end

local function deliver(to, prefix, text, dist, from)
  local fn = to.recv[prefix]
  if fn and to.online then fn(prefix, text, dist, senderSeenBy(from, to)) end
end

local function send(c, prefix, text, dist, target, prio)
  world.log[#world.log + 1] = { from = c.name, op = text:match("^[^|]*"), text = text, dist = dist, target = target,
                                prio = prio, at = clock, cycle = c.cycle }
  at(clock + 0.1, function()
    if dist == "WHISPER" then
      local to = reach(c, target)
      if to then deliver(to, prefix, text, dist, c) else c.system(NOT_FOUND:format(target)) end
      return
    end
    for _, to in ipairs(world.clients) do
      local hears = (dist == "GUILD" and to.guild == c.guild)
        or ((dist == "YELL" or dist == "SAY") and to.zone == c.zone)
        or ((dist == "PARTY" or dist == "RAID") and to.party == c.party)
      if hears then deliver(to, prefix, text, dist, c) end
    end
  end)
end

--- Every logged message that has these fields.
local function ops(filter)
  local out = {}
  for _, e in ipairs(world.log) do
    local same = true
    for k, v in pairs(filter) do
      if e[k] ~= v then same = false end
    end
    if same then out[#out + 1] = e end
  end
  return out
end

-- ── A client ────────────────────────────────────────────────────────────
local function frame()
  return setmetatable({}, { __index = function() return function() end end })
end

local chunks = {}
local function source(env, path)
  local chunk = chunks[path]
  if not chunk then
    chunk = assert(loadfile(ADDON .. "/" .. path))
    chunks[path] = chunk
  end
  setfenv(chunk, env)
  chunk()
end

local function client(name, o)
  o = o or {}
  local c = { name = name, game = o.game or "forever", realm = o.realm or "Azralon", zone = o.zone or name,
              guild = o.guild, rank = o.rank or 5, party = o.party, inInstance = o.inInstance or false,
              lockdown = false, online = true, chat = {}, filters = {}, recv = {}, cycle = 0, roundsAt = {} }
  local env = setmetatable({}, { __index = _G })
  env._G = env
  -- The client calls a secret a string: only asking issecretvalue tells it apart.
  env.type = function(v) return rawequal(v, SECRET) and "string" or type(v) end
  env.GuildOSDB = {}
  env.GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  env.UIParent, env.RAID_CLASS_COLORS = {}, {}
  env.CreateFrame = frame
  env.GetTime = function() return clock end
  env.time = function() return EPOCH + math.floor(clock) end
  env.GetServerTime = env.time
  env.date = os.date
  env.strsplit = strsplit
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.hooksecurefunc = function() end
  env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
  env.ERR_CHAT_PLAYER_NOT_FOUND_S = NOT_FOUND
  env.C_Timer = {
    After = function(delay, fn) at(clock + delay, fn) end,
    NewTicker = function(every, fn)
      local t = {}
      function t.Cancel() t.off = true end
      local function tick()
        if t.off then return end
        fn()
        at(clock + every, tick)
      end
      at(clock + every, tick)
      return t
    end,
  }
  env.C_ChatInfo = {
    InChatMessagingLockdown = function() return c.lockdown end,
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
      send(c, prefix, text, channel, target, "NOW")
      return true
    end,
  }
  env.ChatThrottleLib = {
    SendAddonMessage = function(_, prio, prefix, text, channel, target, _, callback)
      send(c, prefix, text, channel, target, prio)
      if callback then callback(nil, true) end
    end,
  }
  local comm = {
    RegisterComm = function(_, prefix, fn) c.recv[prefix] = fn end,
    SendCommMessage = function(_, prefix, text, dist, target, prio) send(c, prefix, text, dist, target, prio) end,
  }
  env.LibStub = function() return comm end
  env.IsInGuild = function() return c.guild ~= nil end
  env.GetGuildInfo = function()
    if c.guild then return c.guild, "Rank", c.rank end
  end
  env.GetNumGuildMembers = function() return 0 end
  env.IsInGroup = function() return c.party ~= nil end
  env.IsInRaid = function() return false end
  env.IsInInstance = function() return c.inInstance, c.inInstance and "party" or "none" end
  env.UnitIsGhost = function() return false end
  env.UnitClass = function() return "Paladin", "PALADIN" end
  env.UnitLevel = function() return 30 end
  env.UnitFactionGroup = function() return "Horde" end
  env.GetLocale = function() return "enUS" end
  env.GetCurrentRegion = function() return 1 end
  env.GetRealmName = function() return c.realm end
  env.GetNormalizedRealmName = function() return c.realm end
  if c.game == "forever" then
    local first, surname = name:match("^(%S+) (%S+)$")
    env.GetBuildInfo = function() return "1.60.1", "70707", "", 16001 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE = 1, 1
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    env.UnitName = function() return first end
    env.UnitFullName = function() return first, surname end
    env.issecretvalue = function(v) return rawequal(v, SECRET) end
    env.ChatFrame_AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end
  elseif c.game == "retail" then
    env.GetBuildInfo = function() return "12.1.5", "70448", "", 120105 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE = 1, 1
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    env.UnitName = function() return name end
    env.UnitFullName = function() return name, c.realm end
    env.issecretvalue = function(v) return rawequal(v, SECRET) end
    -- The filter's retail home, and no global.
    env.ChatFrameUtil = { AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end }
  else
    env.GetBuildInfo = function() return "2.5.6", "60000", "", 20506 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
    env.UnitName = function() return name end
    env.UnitFullName = function() return name, c.realm end
    env.ChatFrame_AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end
  end
  if o.noFilter then env.ChatFrame_AddMessageEventFilter, env.ChatFrameUtil = nil, nil end

  source(env, "Core/Core.lua")
  source(env, "Core/Compat.lua")
  source(env, "Core/Utils.lua")
  source(env, "Libs/LibChehulMesh.lua")
  source(env, "Modules/ChehulGossip.lua")
  source(env, "Modules/RecruitBeacon.lua")
  env.GuildOS.db = {}
  c.env, c.GuildOS = env, env.GuildOS
  c.Gossip, c.RB = env.GuildOS.ChehulGossip, env.GuildOS.RecruitBeacon

  --- One line of the system chat, through the filters, as a chat frame takes it.
  function c.system(line)
    for _, fn in ipairs(c.filters) do
      if fn({}, "CHAT_MSG_SYSTEM", line) then return end
    end
    c.chat[#c.chat + 1] = line
  end
  --- A message off the wire, along the same road the bus takes.
  function c.hear(payload, sender, dist)
    c.recv[PREFIX](PREFIX, payload, dist or "WHISPER", sender)
  end
  local round = c.Gossip.Round
  c.Gossip.Round = function(self)
    c.cycle = c.cycle + 1
    c.roundsAt[#c.roundsAt + 1] = clock
    return round(self)
  end

  world.clients[#world.clients + 1] = c
  env.GuildOS:InitModules()
  return c
end

--- The topic RecruitBeacon will register in B3: a guild name, a version, and an ad made of the two.
local function stock(c, list)
  c.ads, c.pushed = {}, 0
  for k, v in pairs(list or {}) do c.ads[k] = v end
  c.Gossip:Topic("CR3", {
    digest = function()
      local out = {}
      for k, v in pairs(c.ads) do out[#out + 1] = { k, v } end
      return out
    end,
    want = function(k, v) return (c.ads[k] or -1) < v end,
    pull = function(k)
      local v = c.ads[k]
      return v and ("CR3|" .. k .. "|" .. v) or nil
    end,
    push = function(payload)
      c.pushed = c.pushed + 1
      local _, k, v = strsplit("|", payload)
      if k and k ~= "" then c.ads[k] = math.max(c.ads[k] or 0, tonumber(v) or 0) end
    end,
  })
end

local function ads(n, version)
  local out = {}
  for i = 1, n do out[("Guild %02d"):format(i)] = version or 1 end
  return out
end

--- An old client's ad for the guild Ordem, valid for an hour.
local function cr2(author)
  return "CR2|Ordem|H||||||1|" .. (EPOCH + math.floor(clock) + 3600) .. "|" .. author
end

local function has(list, name)
  for _, p in ipairs(list) do
    if p.name == name then return p end
  end
end

--- No client said more than its ceiling in any one round of its own.
local function ceilingHolds(G, what)
  local replies = G.ROUND_PEERS * (G.REPLY_MAX + 1)
  local tally = {}
  local worstD, worstR = 0, 0
  for _, e in ipairs(world.log) do
    if e.dist == "WHISPER" and e.op ~= "CRW" then
      local key = e.from .. "#" .. e.cycle
      local t = tally[key] or { d = 0, r = 0 }
      tally[key] = t
      if e.op == "CRD" then t.d = t.d + 1 else t.r = t.r + 1 end
      worstD, worstR = math.max(worstD, t.d), math.max(worstR, t.r)
    end
  end
  check(worstD <= G.ROUND_PEERS, what .. ": no client opens more than ROUND_PEERS exchanges in a round, saw " .. worstD)
  check(worstR <= replies, what .. ": no client answers past its allowance in a round, saw " .. worstR)
end

math.randomseed(1)

-- ── The interface ───────────────────────────────────────────────────────
fresh()
local a = client("Chehul Costa")
local G = a.Gossip
check(G.ROUND_SECONDS == 120 and G.ROUND_PEERS == 2 and G.DIGEST_MAX == 12 and G.REPLY_MAX == 4 and G.PEX_MAX == 5
  and G.PEER_FRESH == 300 and G.BEACON_SECONDS == 180 and G.CHANNEL == false, "the constants are the spec's")
for _, m in ipairs({ "Topic", "Peers", "PeerFor", "Note", "Stats", "WhisperName", "CanWhisper" }) do
  check(type(G[m]) == "function", "the module has :" .. m)
end

-- ── The whisper test: the space is what the game writes, so it goes first ───
check(not a.Gossip:CanWhisper(), "nothing is proven at login")
run(9.9)
check(#ops({ dist = "WHISPER" }) == 0 and not a.Gossip:CanWhisper(), "nothing is tried before ten seconds")
run(1)
check(a.Gossip:CanWhisper(), "a whisper that came back is a yes")
local tries = ops({ dist = "WHISPER" })
check(#tries == 1 and tries[1].target == "Chehul Costa", "the space form is tried first, and alone when it works")
check(tries[1].prio == "NOW", "the test goes by C_ChatInfo.SendAddonMessage, through Compat, past the queue")
check(a.Gossip:WhisperName("Chehul Costa") == "Chehul Costa", "the space that came back is the one kept")
check(a.Gossip:Stats().whisper == "space", "and Stats says which")
check(#a.chat == 0, "not a line in the chat")
run(600)
check(#ops({ op = "CRW" }) == 1, "the test runs once a session")

fresh("hyphen")
a = client("Chehul Costa")
run(30)
tries = ops({ dist = "WHISPER" })
check(a.Gossip:CanWhisper(), "hyphen working and space not: still a yes")
check(#tries == 2 and tries[1].target == "Chehul Costa" and tries[2].target == "Chehul-Costa", "space first, then the hyphen")
check(a.Gossip:WhisperName("Chehul Costa") == "Chehul-Costa", "the hyphen is the spelling kept")
check(a.Gossip:WhisperName("Ana Lima-ClassicBetaPvE2") == "Ana-Lima", "a Forever realm means nothing to a whisper")
check(a.Gossip:Stats().whisper == "hyphen", "and Stats says which")
check(#a.chat == 0, "the space that failed printed nothing in the chat")

fresh("none")
a = client("Chehul Costa", { guild = "Ordem", party = "p" })
local b = client("Ana Lima", { guild = "Ordem" })
stock(a, { Ordem = 3 })
a.Gossip:Note(b.name)
run(11)
local token = ops({ op = "CRW" })[1].text:match("^CRW|([^|]+)")
a.hear("CRW|" .. token .. "9|1", b.name)
a.hear("CRW|bad|2", b.name)
check(not a.Gossip:CanWhisper(), "a test still running is not settled by somebody guessing")
run(30)
check(not a.Gossip:CanWhisper(), "with no echo there is no whisper")
run(900)
tries = ops({ from = a.name, dist = "WHISPER" })
check(#tries == 2, "the two tries are the only whispers")
check(tries[1].op == "CRW" and tries[2].op == "CRW", "nothing else goes by whisper")
check(#a.chat == 0, "and neither failure printed anything")
check(#ops({ from = a.name, op = "CRB", dist = "GUILD" }) >= 4, "the beacon still goes by GUILD")
check(#ops({ from = a.name, op = "CRB", dist = "PARTY" }) >= 4, "and by the group")
check(#ops({ from = a.name, op = "CRB", dist = "YELL" }) >= 1, "and by YELL")
check(a.Gossip:Stats().whisper == false, "Stats says it failed")
a.hear("CRD|", b.name)
a.hear("CRG|Ordem", b.name)
run(1)
check(#ops({ from = a.name, op = "CR3" }) == 0, "a client that cannot whisper does not try to answer")

fresh()
a = client("Ana", { game = "retail", realm = "Azralon" })
run(30)
tries = ops({ dist = "WHISPER" })
check(#tries == 1 and tries[1].target == "Ana" and a.Gossip:CanWhisper(), "a name with no surname needs one try")
check(a.Gossip:Stats().whisper == "plain", "and has no spelling to choose")
check(a.Gossip:WhisperName("Bob-Gallywix") == "Bob-Gallywix", "a connected realm's name is left whole")

fresh("none")
a = client("Ana", { game = "retail", realm = "Azralon" })
run(30)
check(#ops({ dist = "WHISPER" }) == 1 and not a.Gossip:CanWhisper(), "and with no echo there it stops at one try")

-- With no filter a failed try would print a line, so there is no try, and so no whisper at all.
fresh()
a = client("Chehul Costa", { noFilter = true })
a.Gossip:Note("Ana Lima")
run(600)
check(#ops({ dist = "WHISPER" }) == 0 and not a.Gossip:CanWhisper(), "a client with no chat filter never whispers")
check(#a.GuildOS.State.errors == 0, "and that is not an error")
check(#ops({ op = "CRB", dist = "YELL" }) >= 1, "it still beacons")

-- ── The filter: only the names tried, only while they are being tried ───
fresh()
a = client("Chehul Costa")
run(11)
a.Gossip:Note("Carla Dias")
check(has(a.Gossip:Peers(), "Carla Dias"), "a peer to start from")
a.Gossip:Whisper("Carla Dias", "CRD|")
run(1)
check(#a.chat == 0, "the error of a name I whispered is hidden")
check(not has(a.Gossip:Peers(), "Carla Dias"), "and somebody the game says is gone leaves the list at once")
a.system(NOT_FOUND:format("Bruno Melo"))
check(#a.chat == 1, "somebody else's error still shows")
a.system("Bruno Melo has come online.")
check(#a.chat == 2, "and so does every other line")
run(60)
a.system(NOT_FOUND:format("Carla Dias"))
check(#a.chat == 3, "once the try is over the same line shows again")
a.Gossip:Whisper("Dora Rosa", "CRD|")
a.system(SECRET)
check(a.chat[4] == SECRET, "a line in lockdown is secret: left alone")
check(#a.GuildOS.State.errors == 0, "and never read, which would raise")
a.GuildOS.MatchFormat = function() error("the filter broke") end
a.system("anything at all")
check(a.chat[5] == "anything at all", "a filter that breaks costs a chat frame nothing")
check(#a.GuildOS.State.errors == 1, "and is recorded")

fresh()
a = client("Ana", { game = "retail", realm = "Azralon" })
check(#a.filters == 1, "the filter finds ChatFrameUtil where the global is gone")
run(11)
a.Gossip:Whisper("Bob-Gallywix", "CRD|")
run(1)
check(#a.chat == 0, "and hides a connected realm's name too")
a.Gossip:Whisper("Bob", "CRD|")
run(1)
check(#a.chat == 0, "and a name on my own realm")

-- ── The list: its own, by the whole sender ──────────────────────────────
fresh("none")
a = client("Ana", { game = "retail", realm = "Azralon", zone = "Z" })
a.hear("CRB||||", "Bob-Gallywix", "YELL")
a.hear("CRB||||", "Bob", "YELL")
local peers = a.Gossip:Peers()
check(#peers == 2 and has(peers, "Bob-Gallywix") and has(peers, "Bob-Azralon"),
  "two namesakes on connected realms are two peers, and a name on mine is written whole")
a.hear("CRB||||", "Ana", "YELL")
a.hear("CRB||||", "Ana-Azralon", "GUILD")
check(#a.Gossip:Peers() == 2, "my own beacon is not a peer")
check(a.Gossip:Stats().peers == 2, "Stats counts them")
a.hear(cr2("Ana"), "Ana", "GUILD")
check(a.RB:Cache()["Ordem"] ~= nil, "my own CR2 still reaches RecruitBeacon, as it always did")
check(#a.GuildOS.State.errors == 0, "and hearing myself breaks nothing")

fresh("none")
a = client("Chehul Costa")
a.hear("CRB||||", "Ana Lima-ClassicBetaPvE2", "YELL")
a.hear("CRB||||", "Ana Lima-ClassicBetaPvE", "YELL")
a.hear("CRB||||", "Ana Lima", "YELL")
check(#a.Gossip:Peers() == 1 and has(a.Gossip:Peers(), "Ana Lima"), "on Forever a realm tells nobody apart")
a.hear("CRB||||", "Chehul Costa-ClassicBetaPvE2", "GUILD")
check(#a.Gossip:Peers() == 1, "nor makes me somebody else")

fresh("none")
a = client("Chehul Costa")
a.Gossip:Note("Ana Lima", "Ordem", false)
run(150)
a.Gossip:Note("Bruno Melo", "Ordem", true)
run(1)
a.Gossip:Note("Carla Dias", "Ordem", false)
a.Gossip:Note("Dora Rosa", "Outra", true)
check(a.Gossip:PeerFor("Ordem") == "Bruno Melo", "an officer of the guild comes first, even heard before a member")
check(select(2, a.Gossip:PeerFor("Ordem")) == true, "and says so")
a.hear("CRB||||", "Carla Dias", "YELL")
check(a.Gossip:PeerFor("Ninguem") == nil, "a guild nobody here belongs to has no peer")
check(a.Gossip:PeerFor(nil) == nil and a.Gossip:PeerFor("") == nil, "and no guild at all is not everybody with no guild")
run(160)
check(not has(a.Gossip:Peers(), "Ana Lima"), "a peer not heard for five minutes leaves the list")
check(has(a.Gossip:Peers(), "Bruno Melo"), "and one heard since stays")
run(151)
check(#a.Gossip:Peers() == 0 and a.Gossip:PeerFor("Ordem") == nil, "and then everybody has")
a.Gossip:Note("Ana Lima", "Ordem", false)
check(a.Gossip:PeerFor("Ordem") == "Ana Lima", "with no officer, a member will do")
a.hear("CRB||||", "Ana Lima", "YELL")
check(a.Gossip:PeerFor("Ordem") == nil, "a beacon with no guild says the guild stopped recruiting")
run(500)
check(next(a.GuildOS.State.gossip.peers) == nil, "the list empties by itself, on a client that can say nothing too")

fresh("none")
a = client("Chehul Costa")
a.hear(cr2("Ana Lima"), "Bruno Melo", "YELL")
check(has(a.Gossip:Peers(), "Bruno Melo"), "anything on the prefix makes a peer, a CR2 included")
check(a.RB:Cache()["Ordem"] ~= nil, "and a CR2 still lands in RecruitBeacon's cache")

-- ── The beacon ──────────────────────────────────────────────────────────
fresh()
a = client("Olga Reis", { guild = "Ordem", rank = 1, party = "p", zone = "Z" })
a.env.ChehulMesh.YELL_PERCENT = 0   -- nothing leaves the queue, so the queue can be counted
run(11)
local beacons = ops({ from = a.name, op = "CRB", dist = "GUILD" })
check(#beacons == 1 and beacons[1].text == "CRB||||", "a client with nothing to announce still beacons")
stock(a, { Outra = 5 })
run(180)
beacons = ops({ from = a.name, op = "CRB", dist = "GUILD" })
check(#beacons == 2 and beacons[2].text == "CRB|Outra|5||", "an ad, and no guild while mine is not recruiting")
a.ads.Ordem = 7
run(180)
beacons = ops({ from = a.name, op = "CRB", dist = "GUILD" })
check(beacons[3].text:match("|Ordem|1$"), "a recruiting guild's officer says so, " .. beacons[3].text)
run(180)
beacons = ops({ from = a.name, op = "CRB", dist = "GUILD" })
local announced = {}
for _, e in ipairs(beacons) do announced[e.text:match("^CRB|([^|]*)") or ""] = true end
check(announced.Ordem and announced.Outra, "the ads take turns")
check(#ops({ from = a.name, op = "CRB", dist = "PARTY" }) == #beacons, "the group hears every beacon")
check(a.env.ChehulMesh._realmQueueCount == 1, "and the YELL queue holds one beacon, however many went: a stable key")
a.rank = 5
run(180)
beacons = ops({ from = a.name, op = "CRB", dist = "GUILD" })
check(beacons[#beacons].text:match("|Ordem|0$"), "a member's says 0")

fresh()
a = client("Ana Lima", { zone = "Z" })
b = client("Bruno Melo", { zone = "Z" })
stock(a, { Ordem = 3 })
stock(b)
run(11)
a.env.ChehulMesh.YELL_PERCENT, b.env.ChehulMesh.YELL_PERCENT = 0, 0
b.hear("CRB|Ordem|3||", a.name, "YELL")
run(1)
local asks = ops({ from = b.name, op = "CRG" })
check(#asks == 1 and asks[1].target == a.name and asks[1].dist == "WHISPER", "an ad I lack is asked of whoever yelled it")
check(b.ads.Ordem == 3, "and arrives")
check(#ops({ from = a.name, op = "CR3", dist = "WHISPER" }) == 1, "by whisper")
b.hear("CRB|Ordem|3||", a.name, "YELL")
run(1)
check(#ops({ from = b.name, op = "CRG" }) == 1, "an ad I hold at that version is not asked again")
a.ads.Ordem = 4
b.hear("CRB|Ordem|4||", a.name, "YELL")
run(1)
check(b.ads.Ordem == 4, "a newer version is")
b.hear("CRB|Novo|1||", "Carla Dias", "YELL")
b.hear("CRB|Novo|1||", "Dora Rosa", "YELL")
run(1)
check(#ops({ from = b.name, op = "CRG", text = "CRG|Novo" }) == 1, "two people yelling one ad cost one question")

-- ── A round ─────────────────────────────────────────────────────────────
fresh()
a = client("Ana Lima")
stock(a, ads(40))
run(11)
for _, n in ipairs({ "Bruno Melo", "Carla Dias", "Dora Rosa", "Edu Lobo" }) do client(n) end
for _, n in ipairs({ "Bruno Melo", "Carla Dias", "Dora Rosa", "Edu Lobo" }) do a.Gossip:Note(n) end
run(600)
local digests = ops({ from = a.name, op = "CRD" })
check(#digests >= 2, "rounds go out")
local walked = {}
for _, e in ipairs(digests) do
  local n = 0
  for name in e.text:sub(5):gmatch("([^,]+):%d+") do
    n = n + 1
    walked[#walked + 1] = name
  end
  check(n == G.DIGEST_MAX, "a digest of forty ads holds DIGEST_MAX pairs")
  check(e.dist == "WHISPER" and e.prio == "NORMAL", "by whisper, through ChatThrottleLib at NORMAL")
end
check(#walked > 40, "enough digests to go all the way round, with beacons taking their turns in between")
for i, name in ipairs(walked) do
  check(name == ("Guild %02d"):format((i - 1) % 40 + 1), "the digest walks all forty in turn, skipping none: " .. name)
end
for i = 2, #a.roundsAt do
  local gap = a.roundsAt[i] - a.roundsAt[i - 1]
  check(gap >= G.ROUND_SECONDS, "two rounds are never closer than ROUND_SECONDS, saw " .. gap)
end
local same = true
for i = 3, #a.roundsAt do
  if a.roundsAt[i] - a.roundsAt[i - 1] ~= a.roundsAt[2] - a.roundsAt[1] then same = false end
end
check(not same, "and the gap varies, or a whole city would fire at once")
check(a.Gossip:Stats().rounds >= 2, "Stats counts the rounds")

-- A newcomer says it holds nothing, and gets the first four: a digest that fits says all there is.
fresh()
a = client("Ana Lima")
stock(a, ads(20))
a.Gossip:Note("Carla Dias")
a.Gossip:Note("Dora Rosa")
run(11)
a.hear("CRD|", "Bruno Melo")
run(1)
check(#ops({ from = a.name, op = "CR3" }) == a.Gossip.REPLY_MAX, "an answer carries REPLY_MAX ads")
local names = ops({ from = a.name, op = "CRP" })
check(#names == 1 and names[1].target == "Bruno Melo", "and one list of names")
check(not names[1].text:find("Bruno", 1, true), "that does not name the asker to himself")
check(names[1].text:find("Carla Dias", 1, true) and names[1].text:find("Dora Rosa", 1, true), "and names who I have heard")

-- What the other already has is not sent, at any version it says.
fresh()
a = client("Ana Lima")
stock(a, { Ordem = 5, Outra = 5, Nova = 5 })
run(11)
a.hear("CRD|Ordem:5,Outra:6", "Bruno Melo")
run(1)
local ad3 = ops({ from = a.name, op = "CR3" })
check(#ad3 == 1 and ad3[1].text == "CR3|Nova|5", "only what the digest does not list, or lists older")
local before = #ops({ from = a.name, op = "CRG" })
check(before == 1, "and what the digest has that I lack is asked for, " .. before)

-- Two clients holding the same forty ads have nothing to say: a full digest proves nothing about the
-- ads it left out, so they are not sent on suspicion.
fresh()
a = client("Ana Lima")
b = client("Bruno Melo")
stock(a, ads(40))
stock(b, ads(40))
run(11)
a.Gossip:Note(b.name)
b.Gossip:Note(a.name)
run(3000)
check(#ops({ op = "CRD" }) >= 20, "they do talk")
check(#ops({ op = "CR3" }) == 0, "two full caches trade digests and not one ad")

-- And one ad neither digest has to carry at once still crosses, as the rotation reaches it.
fresh()
a = client("Ana Lima")
b = client("Bruno Melo")
stock(a, ads(30))
stock(b, ads(30))
a.ads["Guild 99"] = 1
run(11)
a.Gossip:Note(b.name)
b.Gossip:Note(a.name)
run(2000)
check(b.ads["Guild 99"] == 1, "an ad past the digest's size still reaches a full cache")

-- ── Names: what crosses zones, and what must not outlive its owner ──────
fresh()
a = client("Ana Lima")
stock(a)
run(11)
a.hear("CRP|Bruno Melo,Carla Dias,Dora Rosa,Edu Lobo,Fabi Reis,Gabi Lins,Hugo Ramos", "Zeca Baleiro")
check(#a.Gossip:Peers() == 1 + a.Gossip.PEX_MAX, "a list of names counts only PEX_MAX")
fresh("none")
a = client("Ana Lima")
a.hear("CRP|Ana Lima,Bruno|Melo,Carla:Dias," .. ("x"):rep(200) .. ",Dora\nRosa", "Zeca Baleiro")
peers = a.Gossip:Peers()
check(#peers == 1 and peers[1].name == "Zeca Baleiro", "not me, not a bar, not a colon, not a line, not a novel")

-- A name I only heard of expires, and is not passed on: an offline ghost must not circle for ever.
fresh("none")
a = client("Ana Lima")
a.hear("CRP|Fantasma Velho", "Zeca Baleiro")
check(has(a.Gossip:Peers(), "Fantasma Velho"), "a name off a list is a peer to try")
run(280)
a.hear("CRP|Fantasma Velho", "Bruno Melo")
run(30)
check(not has(a.Gossip:Peers(), "Fantasma Velho"), "hearing of somebody again does not make them fresh")
a.hear("CRP|Fantasma Novo", "Zeca Baleiro")
a.hear("CRB||||", "Carla Dias", "YELL")
fresh()
a = client("Ana Lima")
stock(a)
run(11)
a.hear("CRP|Fantasma Novo", "Zeca Baleiro")
a.Gossip:Note("Carla Dias")
a.hear("CRD|", "Bruno Melo")
run(1)
names = ops({ from = a.name, op = "CRP" })
check(#names == 1 and not names[1].text:find("Fantasma", 1, true), "only somebody I heard myself is passed on")
check(names[1].text:find("Carla Dias", 1, true), "and they are")
fresh("none")
a = client("Ana Lima")
a.hear("CRP|Bruno Melo", "Zeca Baleiro")
run(280)
a.hear("CRB||||", "Bruno Melo", "YELL")
run(30)
check(has(a.Gossip:Peers(), "Bruno Melo"), "somebody heard of and then heard is fresh")

-- ── The ceiling: however many ask ───────────────────────────────────────
fresh()
local hub = client("Hub Node")
stock(hub, ads(40))
run(11)
for i = 1, 100 do
  local who = "Visita N" .. i
  hub.hear("CRD|", who)
  hub.hear("CRG|Guild 01", who)
end
run(1)
ceilingHolds(hub.Gossip, "a hundred people asking one client")
local out = ops({ from = hub.name, dist = "WHISPER" })
check(#out > 1 and #out <= 1 + hub.Gossip.ROUND_PEERS * (hub.Gossip.REPLY_MAX + 1), "the allowance is spent and stops, sent " .. #out)
check(hub.Gossip:Stats().dropped > 0, "and what it could not answer is counted")
local answered = #out
local allowance = hub.Gossip.ROUND_PEERS * (hub.Gossip.REPLY_MAX + 1)
run(160)
for i = 1, 100 do hub.hear("CRD|", "Visita N" .. i) end
run(1)
ceilingHolds(hub.Gossip, "and in the next round")
check(#ops({ from = hub.name, dist = "WHISPER" }) > answered, "the allowance comes back with the round")
check(#ops({ from = hub.name, dist = "WHISPER" }) <= 1 + 2 * allowance + 2 * hub.Gossip.ROUND_PEERS, "and no more than that")

-- Asking costs the same: forty yellers of forty ads I lack do not make forty questions.
fresh()
a = client("Ana Lima")
stock(a)
run(11)
for i = 1, 40 do a.hear(("CRB|Guild %02d|1||"):format(i), "Yeller N" .. i, "YELL") end
run(1)
check(#ops({ from = a.name, op = "CRG" }) <= a.Gossip.ROUND_PEERS * (a.Gossip.REPLY_MAX + 1), "questions come out of the same allowance")

-- ── Fifty clients, each in its own zone, each knowing two neighbours ────
for seed = 1, 6 do
  math.randomseed(seed)
  fresh()
  local ring = {}
  for i = 1, 50 do
    ring[i] = client("Node N" .. i)
    stock(ring[i])
  end
  ring[1].ads.Ordem = 1
  run(11)
  for i, c in ipairs(ring) do
    c.Gossip:Note(ring[i % 50 + 1].name)
    c.Gossip:Note(ring[(i + 48) % 50 + 1].name)
  end
  local slowest, covered = 0, false
  while not covered and slowest <= 12 do
    run(5)
    covered = true
    for _, c in ipairs(ring) do
      slowest = math.max(slowest, c.cycle)
      if not c.ads.Ordem then covered = false end
    end
  end
  check(covered and slowest <= 12, "seed " .. seed .. ": the ad reaches all fifty in at most 12 rounds, took " .. slowest)
  ceilingHolds(ring[1].Gossip, "seed " .. seed)
  check(#ops({ op = "CR3", dist = "YELL" }) == 0, "a whole ad never goes out on YELL")
  for _, e in ipairs(ops({ dist = "WHISPER" })) do
    check(e.op == "CRW" or e.prio == "NORMAL", "everything but the test goes through ChatThrottleLib at NORMAL")
  end
  local crossed = 0
  for _, c in ipairs(ring) do crossed = math.max(crossed, #c.Gossip:Peers()) end
  check(crossed > 2, "names crossed the ring: somebody knows more than their two neighbours")
end

-- ── Inside an instance, and in a lockdown ───────────────────────────────
for _, pause in ipairs({ "inInstance", "lockdown" }) do
  fresh()
  a = client("Ana Lima", { guild = "Ordem", party = "p" })
  b = client("Bruno Melo", { guild = "Ordem" })
  stock(a, ads(5))
  stock(b)
  run(11)
  a.Gossip:Note(b.name)
  b.Gossip:Note(a.name)
  a[pause] = true
  -- A beacon queued before the pause is the mesh's to flush: the shared file gates YELL on instances and
  -- not on a lockdown, where the client refuses it. Only what the gossip itself says is measured.
  a.env.ChehulMesh.YELL_PERCENT = 0
  local mark = #world.log
  local queued = a.env.ChehulMesh._realmQueueCount
  run(900)
  a.hear("CRD|", b.name)
  a.hear("CRG|Guild 01", b.name)
  a.hear("CRB|Novo|1||", b.name, "YELL")
  run(1)
  local spoke = 0
  for i = mark + 1, #world.log do
    if world.log[i].from == a.name then spoke = spoke + 1 end
  end
  check(spoke == 0, pause .. ": nothing at all goes out, saw " .. spoke)
  check(a.env.ChehulMesh._realmQueueCount == queued, pause .. ": and nothing new is queued to go out either")
  check(a.Gossip:Whisper(b.name, "CRD|") == false, pause .. ": a whisper asked for from outside the module is refused too")
  local afterRefused = 0
  for i = mark + 1, #world.log do
    if world.log[i].from == a.name then afterRefused = afterRefused + 1 end
  end
  check(afterRefused == 0, pause .. ": and said nothing")
  check(a.cycle > 0, pause .. ": the rounds go on ticking")
  a[pause] = false
  run(400)
  check(#ops({ from = a.name, op = "CRD" }) > 0, pause .. ": and it picks up again afterwards")
end

fresh()
a = client("Ana Lima", { inInstance = true })
run(600)
check(#ops({ from = a.name }) == 0 and not a.Gossip:CanWhisper(), "logged in inside an instance: the whisper test waits")
a.inInstance = false
run(200)
check(a.Gossip:CanWhisper() and #ops({ from = a.name, op = "CRW" }) == 1, "and runs as soon as it is out")

-- ── Trash off the network ───────────────────────────────────────────────
fresh()
a = client("Ana Lima")
stock(a, ads(3))
run(11)
local g = a.Gossip
local trash = { "", "|", "||||||||", "CRB", "CRB|", "CRB|||||||||||||", "CRB|x|notanumber|g|1", "CRB|x|-1|g|1",
  "CRD", "CRD|", "CRD|:", "CRD|,,,,", "CRD|a:b,c:,:9,:,", "CRD|" .. ("x:1,"):rep(800), "CRD|" .. ("x"):rep(9000),
  "CRG", "CRG|", "CRG|" .. ("g"):rep(500), "CRP", "CRP|", "CRP|,,,", "CRP|" .. ("y"):rep(300), "CR3", "CR3|",
  "CRW", "CRW|", "CRW|||", "\0\1\2", "|cffff0000CRB|r", "|Hplayer:x|h[y]|h", ("\255"):rep(40) }
for i = 1, 300 do
  local bytes = {}
  for j = 1, math.random(1, 80) do bytes[j] = string.char(math.random(0, 255)) end
  trash[#trash + 1] = table.concat(bytes)
  trash[#trash + 1] = ({ "CRB|", "CRD|", "CRG|", "CRP|", "CR3|" })[i % 5 + 1] .. table.concat(bytes)
end
for _, payload in ipairs(trash) do
  for _, sender in ipairs({ "Bruno Melo", "Bruno Melo-Realm", "x" }) do
    check(pcall(g.Receive, g, payload, sender, "WHISPER"), "trash does not raise")
  end
end
for _, weird in ipairs({ { nil, "Bruno Melo" }, { 42, "Bruno Melo" }, { {}, "Bruno Melo" }, { true, "Bruno Melo" },
                         { "CRB||||", nil }, { "CRB||||", 42 }, { "CRB||||", "" }, { "CRB||||", "a|b" },
                         { "CRB||||", ("z"):rep(500) }, { SECRET, "Bruno Melo" }, { "CRB||||", SECRET } }) do
  check(pcall(g.Receive, g, weird[1], weird[2], "WHISPER"), "not a string, not a name, or a secret: no raise")
end
check(#a.GuildOS.State.errors == 0, "and trash is refused, not an error caught: " .. tostring((a.GuildOS.State.errors[1] or {}).msg))
check(not has(a.Gossip:Peers(), ("z"):rep(500)) and not has(a.Gossip:Peers(), "a|b"), "and no such name is a peer")
run(1)
check(g:CanWhisper() and #a.chat == 0, "and nothing changed")
local routed = 0
g:On("CRX", function() routed = routed + 1 end)
g:Receive("CRX|" .. ("x"):rep(9000), "Bruno Melo", "WHISPER")
check(routed == 0, "a message past any the protocol makes reaches no route")
g:Receive("CRX|short", "Carla Dias", "WHISPER")
check(routed == 1, "and the route works")

-- A guild name is text that will reach a screen.
fresh("none")
a = client("Ana Lima")
a.hear("CRB|||Or\ndem\1 " .. ("xy"):rep(60) .. "|1", "Bruno Melo", "YELL")
local peer = has(a.Gossip:Peers(), "Bruno Melo")
check(peer and peer.guild and not peer.guild:find("%c") and #peer.guild <= 96, "a guild name comes in one line and cut")
a.hear("CRB|||" .. ("\227\130\171"):rep(40) .. "|1", "Carla Dias", "YELL")
peer = has(a.Gossip:Peers(), "Carla Dias")
check(peer.guild == ("\227\130\171"):rep(24), "cut on a character: twenty-four of them")

-- A topic that raises costs its own work and nothing else.
fresh()
a = client("Ana Lima", { guild = "Ordem" })
b = client("Bruno Melo")
local boom = function() error("topic broke") end
a.Gossip:Topic("CR3", { digest = boom, want = boom, pull = boom, push = boom })
a.Gossip:Note(b.name)
run(11)
a.Gossip:Note(b.name)
for _, payload in ipairs({ "CR3|x|1", "CRD|", "CRG|x", "CRB|x|1||" }) do
  check(pcall(a.Gossip.Receive, a.Gossip, payload, b.name, "WHISPER"), "a raising topic does not reach the caller: " .. payload)
end
run(800)
check(a.cycle >= 3, "the rounds go on")
check(#ops({ from = a.name, op = "CRB", dist = "GUILD" }) >= 4, "and the beacons")
check(#ops({ from = a.name, op = "CRD" }) >= 2, "a digest with nothing in it still goes")
check(#a.GuildOS.State.errors >= 1 and #a.GuildOS.State.errors < 10, "recorded, and once per kind, not per message")
a.Gossip:Note("Carla Dias")
a.hear("CRD|Guild 01:1", b.name)
run(1)
local list = ops({ from = a.name, op = "CRP" })
check(#list >= 1 and list[#list].text:find("Carla Dias", 1, true), "and the answer's names still go")

-- A round or a beacon that raises does not stop the next one.
fresh()
a = client("Ana Lima", { guild = "Ordem" })
run(11)
a.Gossip.Peers = boom
a.env.GetGuildInfo = boom
local cycles = a.cycle
run(800)
check(a.cycle >= cycles + 3, "a raising round leaves the timer alive")
a.env.GetGuildInfo = function() return nil end
local beats = #ops({ from = a.name, op = "CRB", dist = "GUILD" })
run(200)
check(#ops({ from = a.name, op = "CRB", dist = "GUILD" }) > beats, "and a raising beacon leaves the ticker alive")

-- ── One handler, by the first field ─────────────────────────────────────
fresh()
a = client("Ana Lima")
stock(a)
run(11)
a.hear(cr2("Bruno Melo"), "Bruno Melo", "YELL")
check(a.RB:Cache()["Ordem"] ~= nil, "CR2 goes to RB:OnMessage")
a.hear("CR3|Outra|2", "Bruno Melo", "GUILD")
check(a.ads.Outra == 2 and a.RB:Cache()["Outra"] == nil, "CR3 goes to the topic that owns it, and not to RecruitBeacon")
check(a.Gossip:Stats().adsIn == 1, "and is counted")
local got
a.Gossip:On("CRQ", function(payload, sender, dist) got = { payload, sender, dist } end)
a.hear("CRQ|abc|Bruno Melo|WARRIOR|60|TANK|Ordem|oi", "Bruno Melo", "WHISPER")
check(got and got[1]:match("^CRQ|abc") and got[2] == "Bruno Melo" and got[3] == "WHISPER", "a route B4 adds gets the whole message")
check(a.RB:Cache()["abc"] == nil, "and RecruitBeacon never sees it")
a.Gossip:On("CRA", boom)
check(pcall(a.Gossip.Receive, a.Gossip, "CRA|abc|invited|Ana", "Bruno Melo", "WHISPER"), "a route that raises is held too")

-- ── A sender over the limit ─────────────────────────────────────────────
fresh("none")
a = client("Ana Lima")
stock(a)
for i = 1, a.Gossip.SENDER_MAX + 20 do a.hear("CR3|Guild " .. i .. "|1", "Bruno Melo") end
check(a.pushed == a.Gossip.SENDER_MAX, "a sender past the limit is ignored, heard " .. a.pushed)
check(a.Gossip:Stats().dropped == 20, "and counted")
a.hear("CR3|Outra|1", "Carla Dias")
check(a.ads.Outra == 1, "and nobody else pays for it")
run(a.Gossip.ROUND_SECONDS + 1)
a.hear("CR3|Volta|1", "Bruno Melo")
check(a.ads.Volta == 1, "and the limit is per round")

-- ── Anniversary ─────────────────────────────────────────────────────────
fresh()
a = client("Bob", { game = "anniversary", realm = "Nightslayer", guild = "Ordem" })
run(900)
check(#ops({ from = a.name }) == 0, "Anniversary stays out of it: no beacon, no test, no round")
a.hear(cr2("Ana"), "Ana-Nightslayer", "YELL")
check(a.RB:Cache()["Ordem"] ~= nil, "and CR2 keeps working there")
check(not a.Gossip:CanWhisper(), "and says it cannot whisper")

-- ── The wiring ──────────────────────────────────────────────────────────
local function read(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local toc = read("GuildOS.toc")
local gossipAt = toc:find("Modules\\ChehulGossip.lua", 1, true)
check(gossipAt and gossipAt < toc:find("Modules\\RecruitBeacon.lua", 1, true), "the toc loads the module before RecruitBeacon")

print(string.format("gossip: %d checks passed", checks))
