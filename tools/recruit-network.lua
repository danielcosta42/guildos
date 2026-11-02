-- The recruitment with its pieces running together (specs/071-o-recrutamento in guildos-web). One sandbox
-- per client, each with the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Libs/LibChehulMesh.lua,
-- Modules/ChehulGossip.lua, Modules/GuildFinder.lua, Modules/RecruitBeacon.lua and Modules/JoinRequests.lua,
-- resolved by the real ResolveGuildDB and booted by the real GuildOS:InitModules, on a fake bus under
-- AceComm and a fake clock. What the companion leaves (the site's list, the guild's block) stands in for
-- CompanionImport; tools/recruit-beacon.lua reads the same thing out of the site's own strings.
--
-- What only shows when they run together:
--   * A guild keeps its own ad: an officer's CR3 over GUILD lands on every member, nobody asks for it
--     again, the officer's allowance is left over, and a member holding it says the guild in its beacon,
--     is found by PeerFor and answers a request as "member". The same name by whisper, or from a member
--     over GUILD, is still refused.
--   * The companion's list crosses to who has no companion: a client with only the block seeds the others,
--     within the ceilings, with the seal nowhere, with a full list.
--   * The officer hears of a request from the site once the rank is known, once per new row.
--   * An officer's broadcast pauses inside an instance and in a lockdown, and comes back after.
--
--   luajit -e 'ADDON="."' tools/recruit-network.lua
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

local function fresh()
  clock, queue, world = 0, {}, { clients = {}, log = {} }
end

-- ── The bus ─────────────────────────────────────────────────────────────
local function reach(from, target)
  for _, c in ipairs(world.clients) do
    if c.online then
      if c.game == "forever" then
        if target == c.name then return c end
      elseif target == c.name .. "-" .. c.realm or (target == c.name and c.realm == from.realm) then
        return c
      end
    end
  end
end

-- What AceComm hands over: Ambiguate(sender, "none"), the realm only when it is not the reader's.
local function senderSeenBy(from, to)
  if from.game == "forever" then return world.hyphen and (from.name:gsub(" ", "-")) or from.name end
  if from.realm == to.realm then return from.name end
  return from.name .. "-" .. from.realm
end

local function deliver(to, prefix, text, dist, from)
  local fn = to.recv[prefix]
  if fn and to.online then fn(prefix, text, dist, senderSeenBy(from, to)) end
end

local function send(c, prefix, text, dist, target, prio)
  if not c.online then return end   -- a logged-off client's timers say nothing to anybody
  world.log[#world.log + 1] = { from = c.name, op = text:match("^[^|]*"), text = text, dist = dist, target = target,
                                prio = prio, at = clock, cycle = c.cycle }
  at(clock + 0.1, function()
    if dist == "WHISPER" then
      local to = reach(c, target)
      if to then deliver(to, prefix, text, dist, c) else c.system(NOT_FOUND:format(target)) end
      return
    end
    for _, to in ipairs(world.clients) do
      local hears = (dist == "GUILD" and to.guild ~= nil and to.guild == c.guild)
        or ((dist == "YELL" or dist == "SAY") and to.zone == c.zone)
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

--- `o.own`: the guild's ad, what the block's recruitAd gives. `o.list`: the site's list, what GOSRECR1 gives.
--- `o.site`: the block's joinRequests. `o.rankAt`, `o.rosterAt`: when the game answers about each.
--- `o.faction`, `o.region`: what the game says, false for nothing at all.
local function client(name, o)
  o = o or {}
  local c = { name = name, game = o.game or "forever", realm = o.realm or "Azralon", zone = o.zone or name,
              guild = o.guild, rank = o.rank or 5, rankAt = o.rankAt or 0, rosterAt = o.rosterAt or 0,
              inInstance = false, lockdown = false, online = true, chat = {}, filters = {}, recv = {}, cycle = 0,
              notices = {}, printed = {}, list = o.list }
  if o.faction == nil then c.faction = "Horde" else c.faction = o.faction end
  if o.region == nil then c.region = 1 else c.region = o.region end
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.GuildOSDB = {}
  env.GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) c.printed[#c.printed + 1] = line end }
  env.UIParent, env.RAID_CLASS_COLORS = {}, {}
  env.CreateFrame = frame
  env.GetTime = function() return clock end
  env.time = function() return EPOCH + math.floor(clock) end
  env.GetServerTime = env.time
  env.date = os.date
  env.strsplit = strsplit
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
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
    if c.guild then return c.guild, "Rank", clock >= c.rankAt and c.rank or nil end
  end
  local function roster()
    local out = {}
    if c.guild and clock >= c.rosterAt then
      for _, other in ipairs(world.clients) do
        if other.guild == c.guild then out[#out + 1] = other end
      end
    end
    return out
  end
  env.GetNumGuildMembers = function() return #roster() end
  env.GetGuildRosterInfo = function(i)
    local m = roster()[i]
    if m then return m.game == "retail" and (m.name .. "-" .. m.realm) or m.name, "Rank", m.rank end
  end
  env.IsInGroup = function() return false end
  env.IsInRaid = function() return false end
  env.IsInInstance = function() return c.inInstance, c.inInstance and "raid" or "none" end
  env.UnitIsGhost = function() return false end
  env.UnitClass = function() return "Paladin", "PALADIN" end
  env.UnitLevel = function() return 30 end
  env.UnitFactionGroup = function() return c.faction or nil end
  env.GetLocale = function() return "enUS" end
  env.GetCurrentRegion = function() return c.region or nil end
  env.GetRealmName = function() return c.realm end
  env.GetNormalizedRealmName = function() return c.realm end
  if c.game == "forever" then
    local first, surname = name:match("^(%S+) (%S+)$")
    env.GetBuildInfo = function() return "1.60.1", "70707", "", 16001 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE = 1, 1
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    env.UnitName = function() return first end
    env.UnitFullName = function() return first, surname end
    env.ChatFrame_AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end
  elseif c.game == "retail" then
    env.GetBuildInfo = function() return "12.1.5", "70448", "", 120105 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE = 1, 1
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    env.UnitName = function() return name end
    env.UnitFullName = function() return name, c.realm end
    env.ChatFrameUtil = { AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end }
  else
    env.GetBuildInfo = function() return "2.5.6", "60000", "", 20506 end
    env.WOW_PROJECT_ID, env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
    env.UnitName = function() return name end
    env.UnitFullName = function() return name, c.realm end
    env.ChatFrame_AddMessageEventFilter = function(_, fn) c.filters[#c.filters + 1] = fn end
  end

  source(env, "Core/Core.lua")
  source(env, "Core/Compat.lua")
  source(env, "Core/Utils.lua")
  source(env, "Libs/LibChehulMesh.lua")
  source(env, "Modules/ChehulGossip.lua")
  source(env, "Modules/GuildFinder.lua")
  source(env, "Modules/RecruitBeacon.lua")
  source(env, "Modules/JoinRequests.lua")
  env.GuildOS.CompanionImport = {
    OwnRecruitAd = function() return o.own and o.own() or nil end,
    RecruitDirectory = function() return c.list end,
    SiteJoinRequests = function() return o.site end,
  }
  env.GuildOS.JoinRequestsHeard = function(_, r) c.notices[#c.notices + 1] = r.id end
  c.env, c.GuildOS = env, env.GuildOS
  c.Gossip, c.RB, c.GF, c.JR = env.GuildOS.ChehulGossip, env.GuildOS.RecruitBeacon, env.GuildOS.GuildFinder, env.GuildOS.JoinRequests

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
    return round(self)
  end

  world.clients[#world.clients + 1] = c
  assert(env.GuildOS:ResolveGuildDB(), "the guild's db resolves")
  env.ChehulMesh.YELL_PERCENT = 100
  env.GuildOS:InitModules()
  return c
end

local function ownAd()
  return { n = "Ordem", u = "ordem", f = "H", w = "normal:us", p = "Raids", ct = { "Bruno Reis" },
           v = EPOCH - 3600, x = EPOCH + 60 * 3600, pc = "regular", l = { "pt" } }
end

--- What the site's list says, `n` guilds, the first the newest.
local function listOf(n, more)
  local ads = {}
  for i = 1, n do
    ads[i] = { n = ("Guilda %03d"):format(i), u = ("guilda-%03d"):format(i), f = "H", w = "normal:us", p = "Raids",
               ct = { "Dora Lima" }, v = EPOCH - i * 60, x = EPOCH + 60 * 3600, pc = "regular", l = { "en" } }
  end
  for _, ad in ipairs(more or {}) do ads[#ads + 1] = ad end
  return { fmt = "GOSRECR1", v = 1, at = EPOCH, game = "FOREVER", ads = ads }
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

--- A CR3 as a client puts it on the wire, with the fields a test wants to say.
local function cr3(c, o)
  local ad = ownAd()
  for k, v in pairs(o or {}) do ad[k] = v end
  return c.RB:AdToPayload(ad)
end

math.randomseed(1)

-- ── A guild keeps its own ad: one officer, N members, half an hour ──────
local function proof(members)
  fresh()
  local officer = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city", own = ownAd })
  local mates = {}
  for i = 1, members do mates[i] = client(("M%03d Silva"):format(i), { guild = "Ordem", zone = "m" .. i }) end
  local outsider = client("Zed Fora", { zone = "city" })
  run(1800)
  local asked, wasted, holding = 0, 0, 0
  for _, e in ipairs(ops({ op = "CRG", target = officer.name })) do
    if e.from ~= outsider.name then asked = asked + 1 end
  end
  for _, e in ipairs(ops({ from = officer.name, op = "CR3", dist = "WHISPER" })) do
    if e.target ~= outsider.name then wasted = wasted + 1 end
  end
  for _, m in ipairs(mates) do
    if m.RB:Cache3().Ordem then holding = holding + 1 end
  end
  local said = 0
  for _, e in ipairs(ops({ op = "CRB", dist = "GUILD" })) do
    if e.from ~= officer.name and e.text:match("^CRB|[^|]*|[^|]*|Ordem|0$") then said = said + 1 end
  end
  local guildCR3 = #ops({ from = officer.name, op = "CR3", dist = "GUILD" })
  local dropped = officer.Gossip:Stats().dropped
  print(("members=%d  30min: CRG from guildmates=%d  CR3 whispered to guildmates=%d  CR3 on GUILD=%d  officer dropped=%d  members holding=%d  member beacons naming the guild=%d  outsider has it=%s"):format(
    members, asked, wasted, guildCR3, dropped, holding, said, tostring(outsider.RB:Cache3().Ordem ~= nil)))
  check(holding == members, "every member holds the guild's ad: " .. holding .. " of " .. members)
  check(asked == 0, "no guildmate asks the officer for the guild's own ad: " .. asked)
  check(wasted == 0, "and the officer whispers it to none of them: " .. wasted)
  -- A peer whose round falls twice inside the officer's is a discard by design: a handful, never the hundreds
  -- a guild asking for its own ad cost.
  check(dropped <= 6, "the officer's limit is left over: dropped " .. dropped)
  check(said >= members, "a member holding the ad says the guild in its beacon: " .. said)
  check(outsider.RB:Cache3().Ordem ~= nil, "somebody outside the guild still gets it")
  check(guildCR3 >= 25, "and the officer goes on repeating it to the guild: " .. guildCR3)
end
proof(3)
proof(40)

-- The door: an officer, over GUILD, and nobody else by any road.
fresh()
local officer = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city" })
local ana = client("Ana Lima", { guild = "Ordem", zone = "m1" })
local eve = client("Eva Reis", { guild = "Ordem", zone = "m2" })
run(1)
local RB = ana.RB
check(RB:IngestCR3(cr3(ana, { p = "FORJADO" }), "Eva Reis", "GUILD") == false and not RB:Cache3().Ordem, "a member over GUILD is refused")
check(RB:IngestCR3(cr3(ana, { p = "FORJADO" }), "Bruno Reis", "WHISPER") == false and not RB:Cache3().Ordem, "the officer's name by whisper is refused")
check(RB:IngestCR3(cr3(ana, { p = "FORJADO" }), "Bruno Reis", nil) == false and not RB:Cache3().Ordem, "and with no channel said at all")
check(RB:IngestCR3(cr3(ana, { p = "FORJADO" }), "Zed Fora", "GUILD") == false and not RB:Cache3().Ordem, "somebody who is not on the roster is refused")
ana.hear(cr3(ana, { p = "FORJADO" }), "Mallory Fora", "WHISPER")
ana.hear(cr3(ana, { p = "FORJADO" }), "Bruno Reis", "WHISPER")
check(not RB:Cache3().Ordem, "the real road refuses a whisper in the officer's name too")
ana.hear(cr3(ana, { p = "O anuncio" }), "Bruno Reis", "GUILD")
check(RB:Cache3().Ordem and RB:Cache3().Ordem.p == "O anuncio", "and takes the officer's over GUILD")
ana.hear(cr3(ana, { p = "FORJADO", v = EPOCH }), "Eva Reis", "GUILD")
check(RB:Cache3().Ordem.p == "O anuncio", "a member cannot replace it")
local topic = ana.GuildOS.State.gossip.topics.CR3
check(topic.want("Ordem", EPOCH + 1) == false and topic.want("Ordem", 1) == false, "want refuses the guild's own key whatever the version")
check(eve.GuildOS.State.gossip.topics.CR3.want("Ordem", EPOCH) == false, "even for who does not hold it yet")
check(topic.want("Outra", EPOCH) == true, "and only that key")
check(topic.want("ordem", EPOCH) == false, "the site and the game do not agree on the case of a guild's name")

-- A roster not loaded yet: the officer cannot be vouched for, and the next minute's repeat lands.
fresh()
officer = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city", own = ownAd })
ana = client("Ana Lima", { guild = "Ordem", zone = "m1", rosterAt = 100 })
run(95)
check(not ana.RB:Cache3().Ordem and #ops({ from = officer.name, op = "CR3", dist = "GUILD" }) >= 2, "no roster: the ad does not land, and the officer goes on")
run(65)
check(ana.RB:Cache3().Ordem ~= nil, "the roster loads: the next repeat lands, with nothing else asked for")
check(#ops({ from = ana.name, op = "CRG" }) == 0, "no question went out meanwhile")

-- Retail: the same rule by the whole key.
fresh()
officer = client("Bruno", { game = "retail", guild = "Ordem", rank = 0, zone = "city", own = function()
  local ad = ownAd()
  ad.w = "Azralon:us"
  return ad
end })
ana = client("Ana", { game = "retail", guild = "Ordem", zone = "m1" })
run(70)
check(ana.RB:Cache3().Ordem ~= nil, "retail: the officer's ad lands on the member")
check(ana.RB:IngestCR3(cr3(ana, { p = "FORJADO", v = EPOCH }), "Bruno-Gallywix", "GUILD") == false, "retail: a namesake on another realm is not the officer")

-- A request reaches a member. Every contact is offline, nobody with a rank is around, twenty are online.
fresh()
officer = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city", own = ownAd })
local mates = {}
for i = 1, 20 do mates[i] = client(("M%03d Silva"):format(i), { guild = "Ordem", zone = "m" .. i }) end
local zed = client("Zed Fora", { zone = "m1" })
run(90)
officer.online = false
run(400)
local peer, isOfficer = zed.Gossip:PeerFor("Ordem")
check(peer == "M001 Silva" and not isOfficer, "PeerFor finds the member heard in the zone: " .. tostring(peer))
local ad = zed.GF:Ads({})[1]
check(ad and ad.n == "Ordem" and ad.heard == true and ad.verified == false, "and the ad reached who is outside, from a member")
local req = zed.JR:Send(ad, "oi")
run(1)
check(req and zed.JR:Status(req.id) == "member", "the request is answered as delivered to a member: " .. tostring(req and zed.JR:Status(req.id)))
local _, by = zed.JR:Status(req.id)
check(by == "M001 Silva", "and by whom")
check(#ops({ from = "M001 Silva", op = "CRA", target = "Zed Fora" }) == 1, "CRA|member went back to who asked")
check(ops({ from = "M001 Silva", op = "CRA", target = "Zed Fora" })[1].text == "CRA|" .. req.id .. "|member|M001 Silva", "and says so")
local kept = 0
for _, m in ipairs(mates) do
  if m.GuildOS.db.joinRequests and m.GuildOS.db.joinRequests[req.id] then kept = kept + 1 end
end
check(kept == 20, "and the whole guild keeps the request, from the GUILD relay: " .. kept)

-- ── The companion's list crosses to who has no companion ────────────────
local function ceilingHolds(G, what)
  local replies = G.ROUND_PEERS * (G.REPLY_MAX + 1)
  local tally, worstD, worstR = {}, 0, 0
  for _, e in ipairs(world.log) do
    if e.dist == "WHISPER" and e.op ~= "CRW" then
      local key = e.from .. "#" .. e.cycle
      local t = tally[key] or { d = 0, r = 0 }
      tally[key] = t
      if e.op == "CRD" then t.d = t.d + 1 else t.r = t.r + 1 end
      worstD, worstR = math.max(worstD, t.d), math.max(worstR, t.r)
    end
  end
  print(("%s: worst round, %d digests and %d answers"):format(what, worstD, worstR))
  check(worstD <= G.ROUND_PEERS, what .. ": no client opens more than ROUND_PEERS exchanges in a round, saw " .. worstD)
  check(worstR <= replies, what .. ": no client answers past its allowance in a round, saw " .. worstR)
end

fresh()
local seed = client("Ana Lima", { zone = "city", list = listOf(500) })
local newcomers = {}
for i = 1, 6 do newcomers[i] = client(("Novo%d Silva"):format(i), { zone = "city" }) end
run(3600)
local G = seed.Gossip
local digest = ops({ from = seed.name, op = "CRD" })[1]
check(digest, "the block's holder opens rounds")
local pairsSent = {}
for name, version in digest.text:gmatch("([^,:|]+):(%d+)") do pairsSent[#pairsSent + 1] = { name, tonumber(version) } end
check(#pairsSent == G.DIGEST_MAX, "a digest holds DIGEST_MAX of the list, no more: " .. #pairsSent)
for i = 1, G.DIGEST_NEWEST do
  check(pairsSent[i][1] == ("Guilda %03d"):format(i), "the four newest first: " .. pairsSent[i][1])
end
for _, e in ipairs(ops({ from = seed.name, op = "CR3" })) do
  check(e.dist == "WHISPER", "the list's ads go by whisper, and never to a public bus")
end
ceilingHolds(G, "a full list")
for _, c in ipairs(newcomers) do
  local n = count(c.RB:Cache3())
  check(n > 0 and n <= c.RB.CACHE_CAP, "who has no companion holds ads, within the cache: " .. n)
  for i = 1, G.DIGEST_NEWEST do
    check(c.RB:Cache3()[("Guilda %03d"):format(i)], c.name .. " has the newest of the list, Guilda " .. i)
  end
  local shown = c.GF:All()
  check(#shown > 0, "and the finder shows them")
  for _, a in ipairs(shown) do
    check(a.verified == false and a.heard == true, "heard in the game, with no seal")
  end
end
local mine = seed.GF:All()
check(#mine == 500, "the holder's own finder shows the whole list: " .. #mine)
for _, a in ipairs(mine) do check(a.verified == true, "with its seal") end
check(count(seed.RB:Cache3()) <= 40, "and the list is not copied into the holder's cache")

-- What the list holds is not asked for; what is newer than it is. On a client that has heard nothing: after
-- an hour its peers have pushed copies back into its cache, and that would prove the cache and not the list.
fresh()
seed = client("Ana Lima", { zone = "city", list = listOf(500) })
check(count(seed.RB:Cache3()) == 0, "the cache is empty")
local T = seed.GuildOS.State.gossip.topics.CR3
local v1 = EPOCH - 60
check(T.want("Guilda 001", v1) == false, "the list has it at this version: not wanted")
check(T.want("Guilda 001", v1 - 100) == false, "nor an older one")
check(T.want("Guilda 001", v1 + 1) == true, "a newer version is")
check(T.want("Guilda 999", v1) == true, "and one it does not have")
local found
for _, e in ipairs(T.digest()) do if e[1] == "Guilda 001" then found = e end end
check(found and found[2] == v1, "the digest offers it at the list's version")
seed.RB:IngestCR3(cr3(seed, { n = "Guilda 001", v = v1, p = "FORJADO" }), "Eva Reis", "WHISPER")
check(not T.pull("Guilda 001"):find("FORJADO", 1, true), "at the same version what is handed out is the list's")
seed.RB:IngestCR3(cr3(seed, { n = "Guilda 001", v = v1 + 1, p = "Nova" }), "Eva Reis", "WHISPER")
check(T.pull("Guilda 001"):find("Nova", 1, true), "and a newer one heard is the one to pass on")

-- The opening night: more guilds than the cache seats, every ad with the same validity. The newest stay, and
-- a member never loses its own guild's ad to them: that ad is what says the guild in the beacon.
fresh()
ana = client("Ana Lima", { guild = "Ordem", zone = "m1" })
for i = 1, 60 do
  ana.RB:IngestCR3(cr3(ana, { n = ("Guilda %03d"):format(i), u = ("guilda-%03d"):format(i), v = EPOCH - i, x = EPOCH + 3600 }), "Eva Reis", "WHISPER")
end
check(count(ana.RB:Cache3()) == ana.RB.CACHE_CAP, "the cache keeps its forty")
for i = 1, ana.RB.CACHE_CAP do
  check(ana.RB:Cache3()[("Guilda %03d"):format(i)], "at the same validity the older version goes first: Guilda " .. i)
end
ana.RB:IngestCR3(cr3(ana, { v = EPOCH - 9000, x = EPOCH + 60 }), "Bruno Reis", "GUILD")
check(not ana.RB:Cache3().Ordem, "with no officer on the roster nothing lands")
local bruno = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city" })
check(ana.RB:IngestCR3(cr3(ana, { v = EPOCH - 9000, x = EPOCH + 60 }), bruno.name, "GUILD") == true, "the officer's ad lands in a full cache")
ana.RB:Prune3()
check(ana.RB:Cache3().Ordem ~= nil, "and stays, the oldest and the soonest to expire of them all")
check(count(ana.RB:Cache3()) == ana.RB.CACHE_CAP + 1, "beside the forty, and taking none of their seats")

-- Validity: the relayed CR3 carries the ad's own, the way in still cuts it, and what is past is not offered.
fresh()
seed = client("Ana Lima", { zone = "city", list = listOf(2, {
  { n = "Longa", u = "longa", w = "normal:us", v = EPOCH - 5, x = EPOCH + 30 * 86400 },
  { n = "Vencida", u = "vencida", w = "normal:us", v = EPOCH - 4, x = EPOCH - 1 },
}) })
T = seed.GuildOS.State.gossip.topics.CR3
local longa = T.pull("Longa")
check(longa and longa:find("|" .. (EPOCH + 30 * 86400) .. "$"), "x in the relayed CR3 is the ad's own")
local listener = client("Novo Silva", { zone = "elsewhere" })
check(listener.RB:IngestCR3(longa, seed.name, "WHISPER") == true, "and it lands")
check(listener.RB:Cache3().Longa.x == EPOCH + 72 * 3600, "cut to 72 hours on the way in")
check(T.pull("Vencida") == nil, "an expired ad of the list is not handed out")
for _, e in ipairs(T.digest()) do check(e[1] ~= "Vencida", "nor offered") end

-- Two guilds of one name in the list: one seat, the newer.
fresh()
seed = client("Ana Lima", { zone = "city", list = listOf(0, {
  { n = "Xara", u = "xara-us", w = "normal:us", v = EPOCH - 100, x = EPOCH + 3600 },
  { n = "Xara", u = "xara-pvp", w = "pvp:us", v = EPOCH - 50, x = EPOCH + 3600 },
}) })
T = seed.GuildOS.State.gossip.topics.CR3
local seats = 0
for _, e in ipairs(T.digest()) do
  if e[1] == "Xara" then seats = seats + 1; check(e[2] == EPOCH - 50, "the newer of the two") end
end
check(seats == 1, "one name, one seat")

-- ── Only what somebody here can use: this client's faction and region ──
local function placed(n, f, w, v)
  return { n = n, u = (n:lower():gsub(" ", "-")), f = f, w = w, v = v or EPOCH - 100, x = EPOCH + 3600 }
end
local NAMES = { "Aqui", "Outro Ruleset", "Sem Faccao", "Outra Faccao", "Outra Regiao", "Longe", "Sem Faccao Longe", "Sem Mundo" }
local function mixedList()
  return listOf(0, { placed("Aqui", "H", "normal:us"), placed("Outro Ruleset", "H", "pvp:us"), placed("Sem Faccao", nil, "normal:us"),
    placed("Outra Faccao", "A", "normal:us"), placed("Outra Regiao", "H", "normal:eu"), placed("Longe", "A", "pvp:eu"),
    placed("Sem Faccao Longe", nil, "normal:eu"), placed("Sem Mundo", "H", nil) })
end
--- What `c`'s digest offers, sorted, with pull made to agree with it name by name.
local function offered(c)
  local topic3 = c.GuildOS.State.gossip.topics.CR3
  local names, set = {}, {}
  for _, e in ipairs(topic3.digest()) do
    names[#names + 1] = e[1]
    set[e[1]] = true
  end
  table.sort(names)
  for _, n in ipairs(NAMES) do
    check((topic3.pull(n) ~= nil) == (set[n] == true), c.name .. ": pull and the digest agree on " .. n)
  end
  return table.concat(names, ",")
end

fresh()
seed = client("Ana Lima", { zone = "city", list = mixedList() })
local says = offered(seed)
check(says == "Aqui,Outro Ruleset,Sem Faccao", "Horde in the Americas: its faction and region, any ruleset, and the guild with no faction yet: " .. says)
local bia = client("Bia Lima", { zone = "a", faction = "Alliance", list = mixedList() })
says = offered(bia)
check(says == "Outra Faccao,Sem Faccao", "the other faction offers the other side: " .. says)
local caio = client("Caio Lima", { zone = "b", region = 3, list = mixedList() })
says = offered(caio)
check(says == "Outra Regiao,Sem Faccao Longe", "another region offers its own: " .. says)

-- What it cannot judge it does not offer: never everything.
local unsure = {
  { client("Davi Lima", { zone = "c", faction = false, list = mixedList() }), "Sem Faccao", "no faction" },
  { client("Edu Lima", { zone = "d", faction = "Neutral", list = mixedList() }), "Sem Faccao", "a neutral character" },
  { client("Gil Lima", { zone = "e", region = false, list = mixedList() }), "", "no region" },
  { client("Ivo Lima", { zone = "f", region = 5, list = mixedList() }), "", "a region the site has no world for" },
  { client("Jon Lima", { zone = "g", faction = false, region = false, list = mixedList() }), "", "neither" },
}
for _, case in ipairs(unsure) do
  says = offered(case[1])
  check(says == case[2], case[3] .. ": only what needs no answer goes: " .. says)
  check(#case[1].GuildOS.State.errors == 0, case[3] .. ": and nothing raised")
end

-- And down the wire: a client with no list ends up holding what was offered, and nothing else went.
fresh()
seed = client("Ana Lima", { zone = "city", list = mixedList() })
local novo = client("Novo Silva", { zone = "city" })
run(1800)
local got = {}
for key in pairs(novo.RB:Cache3()) do got[#got + 1] = key end
table.sort(got)
check(table.concat(got, ",") == "Aqui,Outro Ruleset,Sem Faccao", "who has no list holds what fits and nothing else: " .. table.concat(got, ","))
for _, e in ipairs(ops({ from = seed.name, op = "CR3" })) do
  for _, far in ipairs({ "Outra Faccao", "Outra Regiao", "Longe", "Sem Faccao Longe", "Sem Mundo" }) do
    check(not e.text:find("CR3|" .. far .. "|", 1, true), "nothing else crossed the wire: " .. far)
  end
end
novo.hear("CRG|Outra Faccao", seed.name)
seed.hear("CRG|Outra Faccao", novo.name)
run(1)
for _, e in ipairs(ops({ from = seed.name, op = "CR3" })) do
  check(not e.text:find("Outra Faccao", 1, true), "asking by name does not get it either")
end

-- The filter comes before the choice of one ad per name: a namesake far away hides nobody here.
fresh()
seed = client("Ana Lima", { zone = "city", list = listOf(0, { placed("Xara", "H", "normal:us", EPOCH - 100), placed("Xara", "H", "normal:eu", EPOCH - 50) }) })
T = seed.GuildOS.State.gossip.topics.CR3
local seen
for _, e in ipairs(T.digest()) do if e[1] == "Xara" then seen = e[2] end end
check(seen == EPOCH - 100, "the namesake in another region does not take this one's seat: " .. tostring(seen))
check(T.pull("Xara"):find("|normal:us|", 1, true), "and pull hands out this region's")
check(seed.RB:IngestCR3(cr3(seed, { n = "Xara", u = "xara-a", f = "A", v = EPOCH - 10 }), "Eva Reis", "WHISPER") == true, "a heard one of the other faction is kept")
seen = nil
for _, e in ipairs(T.digest()) do if e[1] == "Xara" then seen = e[2] end end
check(seen == EPOCH - 100, "and shadows nothing either: " .. tostring(seen))

-- What was heard and is not offered is still known: asked for again every round, it would be the loop
-- a guild once ran on its own ad.
fresh()
seed = client("Ana Lima", { zone = "city" })
T = seed.GuildOS.State.gossip.topics.CR3
check(seed.RB:IngestCR3(cr3(seed, { n = "Ouvida", u = "ouvida", f = "A", v = EPOCH - 9 }), "Eva Reis", "WHISPER") == true, "a heard ad of the other faction lands")
check(offered(seed) == "", "and is not offered")
check(T.want("Ouvida", EPOCH - 9) == false, "and is not asked for again")
check(T.want("Ouvida", EPOCH - 8) == true, "a newer version still is")
seed = client("Bia Lima", { zone = "city", list = listOf(0, { placed("Longe", "A", "pvp:eu", EPOCH - 9) }) })
T = seed.GuildOS.State.gossip.topics.CR3
check(T.want("Longe", EPOCH - 9) == false, "and what the list has, offered or not, is not wanted at its version")

-- A guild's own ad is the one a client can always judge: it is its guild. Without it the beacon says no
-- guild, and nobody finds the member.
fresh()
ana = client("Ana Lima", { guild = "Ordem", zone = "m1", faction = false, own = ownAd })
run(200)
check(offered(ana) == "Ordem", "a member with no faction read yet still offers its guild's ad")
local named = 0
for _, e in ipairs(ops({ from = ana.name, op = "CRB", dist = "GUILD" })) do
  if e.text:match("^CRB|[^|]*|[^|]*|Ordem|0$") then named = named + 1 end
end
check(named >= 1, "and says the guild in its beacon")

-- ── The officer hears of a request from the site once the rank is known ─
local SITE = { { id = "550e8400-e29b-41d4-a716-446655440000", character = "Davi Rocha", class = "MAGE", level = 14,
                 role = "DPS", note = "Procuro", source = "site", status = "open", at = EPOCH - 60 } }
fresh()
local late = client("Bruno Reis", { guild = "Ordem", rank = 0, rankAt = 12, site = SITE })
run(4)
check(late.JR:OpenCount() == 1 and #late.notices == 0, "at login the rank is not known: the row is kept, and nobody was told")
run(30)
check(#late.notices == 1 and late.notices[1] == SITE[1].id, "the rank arrives, through the real officer start, and the officer hears of it: " .. #late.notices)
late.JR:Refresh()
late.JR:Refresh()
check(#late.notices == 1, "once")

-- A /reload: the rank is known at once, and the second reading says nothing again.
fresh()
late = client("Bruno Reis", { guild = "Ordem", rank = 0, site = SITE })
run(30)
check(#late.notices == 1, "with the rank known from the start, still once: " .. #late.notices)

-- A row that was told before does not tell again, and a member hears nothing at all.
fresh()
late = client("Ana Lima", { guild = "Ordem", rank = 5, site = SITE })
run(30)
check(late.JR:OpenCount() == 1 and #late.notices == 0, "a member keeps the row and is told nothing")

-- ── An officer's broadcast pauses where the gossip does ─────────────────
for _, pause in ipairs({ "inInstance", "lockdown" }) do
  fresh()
  officer = client("Bruno Reis", { guild = "Ordem", rank = 0, zone = "city", own = ownAd })
  ana = client("Ana Lima", { guild = "Ordem", zone = "m1" })
  run(100)
  check(#ops({ from = officer.name, op = "CR3", dist = "GUILD" }) >= 2 and ana.RB:Cache3().Ordem, pause .. ": out of it the GUILD road works")
  officer[pause] = true
  -- The old CR2 relay yells from the mesh's queue, every client's and not the officer's broadcast: the shared
  -- file gates YELL on instances and not on a lockdown, where the client refuses it. Only Broadcast is measured.
  officer.env.ChehulMesh.YELL_PERCENT = 0
  local mark = #world.log
  run(300)
  local spoke = 0
  for i = mark + 1, #world.log do
    local e = world.log[i]
    if e.from == officer.name and (e.op == "CR3" or e.op == "CR2") then spoke = spoke + 1 end
  end
  check(spoke == 0, pause .. ": nothing of the ad goes out: " .. spoke)
  officer[pause] = false
  mark = #world.log
  run(70)
  local back = 0
  for i = mark + 1, #world.log do
    local e = world.log[i]
    if e.from == officer.name and e.op == "CR3" and e.dist == "GUILD" then back = back + 1 end
  end
  check(back >= 1, pause .. ": and it picks up again on the way out")
end

-- Anniversary keeps the plain beacon as it always ran.
fresh()
officer = client("Bob", { game = "anniversary", realm = "Nightslayer", guild = "Ordem", rank = 0, zone = "city" })
officer.RB:GetAd().enabled = true
officer.inInstance = true
run(70)
check(#ops({ from = officer.name, op = "CR2", dist = "GUILD" }) >= 1, "Anniversary: the /gos beacon goes on, in an instance as before")

print(("recruit-network: %d checks passed"):format(checks))
