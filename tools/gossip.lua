-- ChehulGossip (specs/071-o-recrutamento in guildos-web, Task B2): the whisper gossip that carries an
-- ad past the zone and the layer of whoever yells. One sandbox per client, each with the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Libs/LibChehulMesh.lua, Modules/RecruitBeacon.lua and
-- Modules/ChehulGossip.lua, booted by the real GuildOS:InitModules, on a fake bus under AceComm and a
-- fake clock. Whisper, GUILD, group and YELL each reach who they reach in the game; a whisper to nobody
-- answers with the client's "no such player" line, through the chat filters.
--
-- The rules: 50 clients in separate zones, each knowing two neighbours, all get a new ad within 12
-- rounds, on an empty cache and on a nearly full one; no client ever says more than its ceiling, however
-- many ask, and one sender cannot spend it for the others; a list of names is read only when I asked
-- for it, and can never take my rounds from who I heard myself; a peer goes stale; inside an instance
-- or a chat lockdown nothing goes out; with no echo from the whisper test nothing goes by whisper, and
-- the spelling that came back is the one used; no line reaches the chat; trash off the network breaks
-- nothing; CR2 still reaches RecruitBeacon; and Anniversary stays out of it.
--
-- `pairs` order differs from one run to the next, and so do who ties with whom and the number of checks
-- that make: a rule here holds on every order, and a test must not lean on one.
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

-- `mute`: online, so a whisper reaches them and no error comes back, and never answering. It is how
-- somebody stays somebody I only heard of for as long as a test needs.
local function deliver(to, prefix, text, dist, from)
  local fn = to.recv[prefix]
  if fn and to.online and not to.mute then fn(prefix, text, dist, senderSeenBy(from, to)) end
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
      if dist == "CHANNEL" then hears = to.channels[c.idName[target] or ""] ~= nil end
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
              lockdown = false, online = true, chat = {}, filters = {}, recv = {}, cycle = 0, roundsAt = {},
              channels = {}, idName = {} }
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
      if world.refuse and target:find(world.refuse, 1, true) then error("the client refused that target") end
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
  -- Created channels: a name, the number this client gives it, and whoever joined the same name hears it.
  env.JoinChannelByName = function(channel)
    if not c.channels[channel] then
      local id = 4
      for _ in pairs(c.channels) do id = id + 1 end
      c.channels[channel], c.idName[id] = id, channel
    end
  end
  env.GetChannelName = function(channel) return c.channels[channel] or 0, channel end
  env.LeaveChannelByName = function(channel) c.channels[channel] = nil end
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
  if o.channel then c.Gossip.CHANNEL = true end   -- a version that turns the route on

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
  c.ads, c.pushed, c.digests = {}, 0, 0
  for k, v in pairs(list or {}) do c.ads[k] = v end
  c.Gossip:Topic("CR3", {
    digest = function()
      c.digests = c.digests + 1
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

--- `c` opens a round to these names, the way anybody earns the right to hand it names back.
local function dial(c, ...)
  for _, name in ipairs({ ... }) do c.Gossip:Note(name) end
  c.Gossip:Round()
  run(1)
end

--- How many names `c` holds only because somebody told it.
local function heardOf(c)
  local n = 0
  for _, p in ipairs(c.Gossip:Peers()) do
    if p.heardOf then n = n + 1 end
  end
  return n
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

-- A try that raises costs that try: the next one was already on its way.
fresh("hyphen")
world.refuse = " "
a = client("Chehul Costa")
run(30)
check(a.Gossip:CanWhisper() and a.Gossip:WhisperName("Chehul Costa") == "Chehul-Costa", "the client refusing the space leaves the hyphen to try")
check(#a.GuildOS.State.errors == 1, "and the refusal is recorded")

-- The door closing between two tries holds the second one, and costs nothing else.
fresh("hyphen")
a = client("Chehul Costa")
run(11)
check(#ops({ op = "CRW" }) == 1, "the space has gone")
a.inInstance = true
run(120)
check(#ops({ op = "CRW" }) == 1 and not a.Gossip:CanWhisper(), "inside an instance the hyphen waits")
a.inInstance = false
run(10)
check(#ops({ op = "CRW" }) == 2 and a.Gossip:Stats().whisper == "hyphen", "and goes on the way out, and the session keeps its whisper")

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
-- Four ads newer than the rest, in no order the keys would give.
a.ads["Guild 20"], a.ads["Guild 30"], a.ads["Guild 38"], a.ads["Guild 07"] = 9, 8, 7, 6
local NEWEST = { "Guild 20", "Guild 30", "Guild 38", "Guild 07" }
run(11)
for _, n in ipairs({ "Bruno Melo", "Carla Dias", "Dora Rosa", "Edu Lobo" }) do client(n) end
for _, n in ipairs({ "Bruno Melo", "Carla Dias", "Dora Rosa", "Edu Lobo" }) do a.Gossip:Note(n) end
run(600)
local digests = ops({ from = a.name, op = "CRD" })
check(#digests >= 2, "rounds go out")
check(G.DIGEST_NEWEST > 0 and G.DIGEST_NEWEST < G.DIGEST_MAX, "a digest keeps some seats for the newest and some for the rest")
check(G.DIGEST_NEWEST == #NEWEST, "this test seats exactly DIGEST_NEWEST ads")
local walked = {}
for _, e in ipairs(digests) do
  local n, once = 0, {}
  for name in e.text:sub(5):gmatch("([^,]+):%d+") do
    n = n + 1
    check(not once[name], "a digest lists an ad once: " .. name)
    once[name] = true
    if n <= #NEWEST then
      check(name == NEWEST[n], "the newest by version lead every digest, in that order: " .. name)
    else
      walked[#walked + 1] = name
    end
  end
  check(n == G.DIGEST_MAX, "a digest of forty ads holds DIGEST_MAX pairs")
  check(e.dist == "WHISPER" and e.prio == "NORMAL", "by whisper, through ChatThrottleLib at NORMAL")
end
local others = {}
for i = 1, 40 do
  local name = ("Guild %02d"):format(i)
  if name ~= "Guild 20" and name ~= "Guild 30" and name ~= "Guild 38" and name ~= "Guild 07" then others[#others + 1] = name end
end
check(#walked > #others, "enough digests to go all the way round, with beacons taking their turns in between")
for i, name in ipairs(walked) do
  check(name == others[(i - 1) % #others + 1], "the other seats walk the rest in turn, skipping none: " .. name)
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

-- What fits goes whole, each ad once: the seats change nothing below DIGEST_MAX.
for _, held in ipairs({ 1, 3, 5, 12, 13 }) do
  fresh()
  a = client("Ana Lima")
  stock(a, ads(held))
  run(11)
  dial(a, client("Bruno Melo").name)
  local text = ops({ from = a.name, op = "CRD" })[1].text
  local n, once = 0, {}
  for name in text:sub(5):gmatch("([^,]+):%d+") do
    n = n + 1
    check(not once[name], held .. " ads: nothing listed twice")
    once[name] = true
  end
  check(n == math.min(held, G.DIGEST_MAX), held .. " ads: all of them, up to DIGEST_MAX, saw " .. n)
end

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

-- A full digest still proves one thing: its first seats are the sender's newest, so an ad newer than the
-- last of them that it does not list is one it lacks, or it would have a seat. Anything else is a guess.
fresh()
a = client("Ana Lima")
stock(a, { Nova = 12, Meio = 6, Igual = 5, Velha = 3, Sentada = 9 })
run(11)
local seated = { "Sentada:9", "Guild 02:8", "Guild 03:8", "Guild 04:5" }
for i = 5, 12 do seated[i] = ("Guild %02d:1"):format(i) end
a.hear("CRD|" .. table.concat(seated, ","), "Bruno Melo")
run(1)
local proved = {}
for _, e in ipairs(ops({ from = a.name, op = "CR3" })) do proved[e.text] = true end
check(proved["CR3|Nova|12"] and proved["CR3|Meio|6"], "newer than its last seat and not listed: proved lacking, and sent")
check(not proved["CR3|Igual|5"] and not proved["CR3|Velha|3"], "level with that seat or older proves nothing, and stays")
check(not proved["CR3|Sentada|9"], "and what it lists at my version it holds")

-- Two clients holding the same forty ads have nothing to say: a full digest proves nothing about the
-- ads it left out, so they are not sent on suspicion. At any mix of versions.
for _, spread in ipairs({ false, true }) do
  fresh()
  a = client("Ana Lima")
  b = client("Bruno Melo")
  local same = ads(40)
  if spread then
    for i = 1, 40 do same[("Guild %02d"):format(i)] = 1 + i % 7 end
  end
  stock(a, same)
  stock(b, same)
  run(11)
  a.Gossip:Note(b.name)
  b.Gossip:Note(a.name)
  run(3000)
  check(#ops({ op = "CR3" }) == 0 and #ops({ op = "CRG" }) == 0, "two full caches trade nothing but digests, spread " .. tostring(spread))
end
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
local z = client("Zeca Baleiro")
stock(a)
run(11)
dial(a, z.name)
a.hear("CRP|Bruno Melo,Carla Dias,Dora Rosa,Edu Lobo,Fabi Reis,Gabi Lins,Hugo Ramos", z.name)
check(#a.Gossip:Peers() == 1 + a.Gossip.PEX_MAX, "a list of names counts only PEX_MAX")
fresh()
a = client("Ana Lima")
z = client("Zeca Baleiro")
run(11)
dial(a, z.name)
a.hear("CRP|Ana Lima,Bruno|Melo,Carla:Dias," .. ("x"):rep(200) .. ",Dora\nRosa", z.name)
peers = a.Gossip:Peers()
check(#peers == 1 and peers[1].name == z.name, "not me, not a bar, not a colon, not a line, not a novel")

-- A name I only heard of expires, and is not passed on: an offline ghost must not circle for ever.
fresh()
a = client("Ana Lima")
z = client("Zeca Baleiro")
client("Fantasma Velho").mute = true
run(11)
dial(a, z.name)
a.hear("CRP|Fantasma Velho", z.name)
check(has(a.Gossip:Peers(), "Fantasma Velho"), "a name off a list is a peer to try")
run(280)
dial(a, z.name)
a.hear("CRP|Fantasma Velho", z.name)
run(30)
check(not has(a.Gossip:Peers(), "Fantasma Velho"), "hearing of somebody again does not make them fresh")
fresh()
a = client("Ana Lima")
z = client("Zeca Baleiro")
client("Fantasma Novo").mute = true
stock(a)
run(11)
dial(a, z.name)
a.hear("CRP|Fantasma Novo", z.name)
a.Gossip:Note("Carla Dias")
a.hear("CRD|", "Bruno Melo")
run(1)
names = ops({ from = a.name, op = "CRP" })
check(#names == 1 and not names[1].text:find("Fantasma", 1, true), "only somebody I heard myself is passed on")
check(names[1].text:find("Carla Dias", 1, true), "and they are")
fresh()
a = client("Ana Lima")
z = client("Zeca Baleiro")
client("Bruno Melo").mute = true
run(11)
dial(a, z.name)
a.hear("CRP|Bruno Melo", z.name)
run(280)
a.hear("CRB||||", "Bruno Melo", "YELL")
run(30)
check(has(a.Gossip:Peers(), "Bruno Melo"), "somebody heard of and then heard is fresh")

-- ── A sender who wants my rounds for himself ────────────────────────────
-- Nobody hands me names unasked.
fresh()
a = client("Vitima Um")
z = client("Zeca Baleiro")
run(11)
a.Gossip:Note(z.name)
local droppedBefore = a.Gossip:Stats().dropped
a.hear("CRP|Falso Um,Falso Dois", z.name)
check(not has(a.Gossip:Peers(), "Falso Um"), "a list nobody asked for is not read")
check(a.Gossip:Stats().dropped == droppedBefore + 1, "and is counted")

-- And somebody I did ask, once, and for this round only.
dial(a, z.name)
a.hear("CRP|Falso Um", z.name)
check(has(a.Gossip:Peers(), "Falso Um"), "the answer to my digest is read")
a.hear("CRP|Falso Dois", z.name)
check(not has(a.Gossip:Peers(), "Falso Dois"), "and one answer is all a digest buys")
fresh()
a = client("Vitima Um")
z = client("Zeca Baleiro")
z.mute = true
run(11)
dial(a, z.name)
run(a.Gossip.PEER_FRESH + 200)
check(not has(a.Gossip:Peers(), z.name), "the peer has gone stale, so no round reached them again")
a.hear("CRP|Falso Um", z.name)
check(not has(a.Gossip:Peers(), "Falso Um"), "a digest of an old round buys nothing now")

-- The rows that came off lists have a ceiling, whoever fills them.
fresh()
a = client("Vitima Um")
z = client("Zeca Baleiro")
z.mute = true
run(11)
local serial = 0
for _ = 1, 12 do
  dial(a, z.name)
  local list = {}
  for i = 1, 5 do
    serial = serial + 1
    list[i] = "Falso X" .. serial
  end
  a.hear("CRP|" .. table.concat(list, ","), z.name)
  check(heardOf(a) <= a.Gossip.HEARD_OF_MAX, "names off lists stop at HEARD_OF_MAX, saw " .. heardOf(a))
end
check(heardOf(a) > 0, "and there are some, so the ceiling was what stopped them")

-- A round takes one of them at most: with nobody I heard, one digest and not two.
fresh()
a = client("Vitima Um")
z = client("Zeca Baleiro")
z.mute = true
for i = 1, 4 do client("Falso X" .. i).mute = true end
run(11)
dial(a, z.name)
a.hear("CRP|Falso X1,Falso X2,Falso X3,Falso X4", z.name)
local mark = #ops({ from = a.name, op = "CRD" })
a.GuildOS.State.gossip.peers[z.name] = nil
a.Gossip:Round()
run(1)
check(#ops({ from = a.name, op = "CRD" }) == mark + 1, "a round with only names off lists sends one digest")

-- The whole attack: thirty lists a round from a sender who is really there, against four honest peers.
math.randomseed(7)
fresh()
a = client("Vitima Um")
stock(a, ads(3))
local honest = {}
for i = 1, 4 do
  honest[i] = client("Honesto N" .. i)
  stock(honest[i])
end
local mau = client("Mau Ator")
mau.mute = true
run(11)
for _, c in ipairs(honest) do
  a.Gossip:Note(c.name)
  c.Gossip:Note(a.name)
end
local peak = 0
serial = 0
for _ = 1, 30 do
  for _ = 1, 30 do
    local list = {}
    for j = 1, 5 do
      serial = serial + 1
      list[j] = "Falso X" .. serial
    end
    a.hear("CRP|" .. table.concat(list, ","), mau.name)
  end
  peak = math.max(peak, heardOf(a))
  run(121)
end
local toHonest, told, heardMe = 0, {}, {}
for _, e in ipairs(ops({ from = a.name, op = "CRD" })) do
  if e.target:find("^Falso") then
    told[e.cycle] = (told[e.cycle] or 0) + 1
  else
    heardMe[e.cycle] = true
    if e.target:find("^Honesto") then toHonest = toHonest + 1 end
  end
end
local cycles = 0
for cycle, n in pairs(told) do
  check(n <= 1, "cycle " .. cycle .. ": never more than one digest to a name off a list, saw " .. n)
  check(heardMe[cycle], "cycle " .. cycle .. ": and a name off a list never takes the seat of somebody I heard")
  cycles = cycles + 1
end
check(cycles > 0, "the attack did get names in, so it is the seats that held")
check(peak <= a.Gossip.HEARD_OF_MAX, "the flood never passes the ceiling, peak " .. peak)
check(toHonest >= 15, "the honest peers keep their rounds, " .. toHonest .. " digests of 30 rounds")

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
check(#ops({ from = a.name, op = "CRG" }) == a.Gossip.REPLY_MAX, "a round asks no more than an answer can carry")
check(a.GuildOS.State.gossip.allowance >= a.Gossip.REPLY_MAX + 1, "and leaves a whole answer for whoever asks me")
a.Gossip:Round()
a.hear("CRB|Guild 39|1||", "Yeller N39", "YELL")
run(1)
check(#ops({ from = a.name, op = "CRG" }) == a.Gossip.REPLY_MAX + 1, "and the next round may ask again")

-- One sender is one answer, however it asks.
fresh()
a = client("Vitima Um")
stock(a, ads(20))
client("Mau Ator").mute = true
client("Honesto Um").mute = true
client("Carla Dias").mute = true
run(11)
a.Gossip:Note("Carla Dias")
for _ = 1, 3 do a.hear("CRD|", "Mau Ator") end
for i = 1, 12 do a.hear(("CRG|Guild %02d"):format(i), "Mau Ator") end
run(1)
local function adsTo(c, target) return #ops({ from = c.name, op = "CR3", target = target }) end
check(adsTo(a, "Mau Ator") == a.Gossip.REPLY_MAX, "one sender takes REPLY_MAX ads in a round, saw " .. adsTo(a, "Mau Ator"))
check(#ops({ from = a.name, op = "CRP", target = "Mau Ator" }) == 1, "and one list of names, however many digests it sends")
a.hear("CRD|", "Honesto Um")
run(1)
check(adsTo(a, "Honesto Um") == a.Gossip.REPLY_MAX, "and the next asker gets a whole answer, saw " .. adsTo(a, "Honesto Um"))
a.Gossip:Round()
a.hear("CRD|", "Mau Ator")
run(1)
check(adsTo(a, "Mau Ator") == 2 * a.Gossip.REPLY_MAX, "and the next round it is served again")

-- The list of names goes first: it is what crosses zones, and an answer's asks must not starve it.
fresh()
a = client("Novato Um")
stock(a)
run(11)
a.Gossip:Note("Carla Dias")
a.Gossip:Note("Dora Rosa")
local full = {}
for i = 1, 12 do full[i] = ("Guild %02d:1"):format(i) end
a.hear("CRD|" .. table.concat(full, ","), "Bruno Melo")
run(1)
check(#ops({ from = a.name, op = "CRP" }) == 1, "twelve pairs I want leave room for the names")
check(#ops({ from = a.name, op = "CRG" }) == a.Gossip.REPLY_MAX, "and I ask for what a peer can give me, no more")
check(ops({ from = a.name, op = "CRG" })[1].text == "CRG|Guild 01", "in the order of the digest, the newest first")

-- Down to the last whisper of the round, that whisper is the names.
fresh()
a = client("Vitima Um")
stock(a, ads(20))
run(11)
a.Gossip:Note("Carla Dias")
for _, who in ipairs({ "Bruno Melo", "Dora Rosa" }) do
  for i = 1, 4 do a.hear(("CRG|Guild %02d"):format(i), who) end
end
a.hear("CRG|Guild 09", "Edu Lobo")
check(a.GuildOS.State.gossip.allowance == 1, "a round spent down to its last whisper")
a.hear("CRD|Novo:1", "Fabi Reis")
run(1)
check(#ops({ from = a.name, op = "CRP", target = "Fabi Reis" }) == 1, "and it carries the names")
check(adsTo(a, "Fabi Reis") == 0 and #ops({ from = a.name, op = "CRG" }) == 0, "and nothing else got there first")

-- With nothing left a digest is not even read.
local reads = a.digests
local droppedThen = a.Gossip:Stats().dropped
a.hear("CRD|", "Gabi Lins")
run(1)
check(a.digests == reads, "an allowance at zero answers nothing and works out nothing")
check(a.Gossip:Stats().dropped == droppedThen + 1, "and counts one discard")

-- ── Keys off the network, and on their way out ──────────────────────────
fresh()
a = client("Ana Lima")
stock(a)
local answers = 0
a.Gossip:Topic("ANY", {
  digest = function() return { { ("k"):rep(300), 1 }, { "with|bar", 1 }, { "Boa", 1 } } end,
  want = function() return true end,
  pull = function() answers = answers + 1; return "ANY|ad" end,
  push = function() end,
})
run(11)
local long = ("k"):rep(2000)
a.hear("CRB|" .. long .. "|1||", "Bruno Melo", "YELL")
a.hear("CRB|tab\1bed|1||", "Bruno Melo", "YELL")
a.hear("CRD|" .. ("k"):rep(200) .. ":1", "Carla Dias")
a.hear("CRD|ctrl\1char:1", "Dora Rosa")
run(1)
check(#ops({ from = a.name, op = "CRG" }) == 0, "a key that is no name is never asked for")
answers = 0
a.hear("CRG|" .. ("g"):rep(200), "Edu Lobo")
a.hear("CRG|tab\1bed", "Edu Lobo")
a.hear("CRG|bar|bar", "Edu Lobo")
run(1)
check(answers == 0, "nor looked up")
a.hear("CRG|Boa", "Edu Lobo")
run(1)
check(answers == 1, "while a key that is one is")
dial(a, client("Fabi Reis").name)
for _, e in ipairs(ops({ from = a.name, op = "CRD" })) do
  check(#e.text < 200 and e.text:find("Boa", 1, true), "a digest carries the good key and no other: " .. e.text:sub(1, 60))
  check(not e.text:find("with", 1, true), "and never a bar inside a field")
end
a.Gossip:Beacon()
for _, e in ipairs(ops({ from = a.name, op = "CRB" })) do
  check(#e.text < 200, "and the beacon the same")
end

-- ── Fifty clients, each in its own zone, each knowing two neighbours ────
-- `held` is what every client already holds: a healthy network sits near the cache's forty, and a new
-- ad has to cross that as fast as it crosses an empty one. Its version is what says it is new.
for _, held in ipairs({ 0, 11, 12, 30, 39 }) do
  for _, edit in ipairs(held > 0 and { false, true } or { false }) do
    for seed = 1, 6 do
      math.randomseed(seed)
      fresh()
      local ring = {}
      for i = 1, 50 do
        ring[i] = client("Node N" .. i)
        stock(ring[i], ads(held))
      end
      local key = edit and "Guild 01" or "Ordem"
      ring[1].ads[key] = 2
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
          if (c.ads[key] or 0) < 2 then covered = false end
        end
      end
      local what = ("seed %d, %d held%s"):format(seed, held, edit and ", an edit" or "")
      check(covered and slowest <= 12, what .. ": the ad reaches all fifty in at most 12 rounds, took " .. slowest)
      ceilingHolds(ring[1].Gossip, what)
      check(#ops({ op = "CR3", dist = "YELL" }) == 0, "a whole ad never goes out on YELL")
      for _, e in ipairs(ops({ dist = "WHISPER" })) do
        check(e.op == "CRW" or e.prio == "NORMAL", "everything but the test goes through ChatThrottleLib at NORMAL")
      end
      if held >= 12 then
        check(#ops({ op = "CR3" }) <= 3 * 50, what .. ": one ad costs a few answers each, not ads on suspicion, saw " .. #ops({ op = "CR3" }))
      end
      local crossed = 0
      for _, c in ipairs(ring) do crossed = math.max(crossed, #c.Gossip:Peers()) end
      check(crossed > 2, "names crossed the ring: somebody knows more than their two neighbours")
    end
  end
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
run(10)
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
a.hear("CRD|Guild 01:1", "Edu Lobo")
run(1)
local list = ops({ from = a.name, op = "CRP", target = "Edu Lobo" })
check(#list == 1 and list[1].text:find("Carla Dias", 1, true), "and the answer's names still go")

-- A topic that raises over one key costs that key: the digest's next one is still asked for.
fresh()
a = client("Ana Lima")
a.Gossip:Topic("CR3", {
  digest = function() return {} end,
  want = function(k)
    if k == "Mala" then error("this key broke") end
    return true
  end,
  pull = function() end,
  push = function() end,
})
run(11)
a.hear("CRD|Mala:1,Boa:1", "Edu Lobo")
run(1)
check(#ops({ from = a.name, op = "CRG", text = "CRG|Boa" }) == 1, "one bad key does not stop the next")

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

-- ── The channel route: off, and only a new version turns it on ─────────
fresh()
a = client("Ana Lima", { zone = "Orgrimmar", guild = "Ordem" })
local b2 = client("Bruno Melo", { zone = "Durotar", guild = "Outra" })
check(a.Gossip.CHANNEL == false, "the channel route ships off")
run(400)
check(#ops({ op = "CRB", dist = "CHANNEL" }) == 0 and next(a.channels) == nil, "off: no channel is joined and nothing goes through one")
check(#ops({ from = a.name, op = "CRB", dist = "YELL" }) >= 1, "off: the beacon yells, as it always did")

fresh()
a = client("Ana Lima", { zone = "Orgrimmar", guild = "Ordem", channel = true })
b2 = client("Bruno Melo", { zone = "Durotar", guild = "Outra", channel = true })
a.env.ChehulMesh.YELL_PERCENT, b2.env.ChehulMesh.YELL_PERCENT = 100, 100
run(400)
check(a.channels[a.Gossip.CHANNEL_NAME] and b2.channels[b2.Gossip.CHANNEL_NAME], "on: both join the beacon's channel")
check(#ops({ from = a.name, op = "CRB", dist = "CHANNEL" }) >= 1, "on: the beacon goes through the channel")
check(#ops({ from = a.name, op = "CRB", dist = "YELL" }) == 0, "and not by YELL")
check(has(b2.Gossip:Peers(), "Ana Lima"), "a client in another zone hears it")
check(#a.chat == 0 and #b2.chat == 0, "and nothing reaches a chat line")

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
