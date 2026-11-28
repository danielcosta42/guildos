-- What Guild OS costs at the moment the player enters and leaves combat (PLAYER_REGEN_DISABLED / _ENABLED): a
-- report of a "micro stutter every time I enter/leave combat" on WoW: Forever (a member of a guild of 35, the
-- companion publishing only their own character, no alliance; /gos debug mem: 33.4 MB, 18.1 MB after a full
-- collection, 482 frames). A measuring harness, not a gate: it loads the whole addon under tools/alloc-budget.lua's
-- stubbed WoW: Forever client, lets the login settle, then runs COMBAT_CYCLES (default 20) pulls in each scenario
-- and reports, per edge (enter, leave):
--   * the edge frame's CPU (the event's dispatch and that frame's timers and OnUpdates), the longest frame of the
--     window that follows (COMBAT_WINDOW frames, 2.5 s: the coalesced repaints, the 0.5 s redraws, the popup pump),
--     the window's CPU over a control window of the same length with no edge, and the KB it allocated over the
--     control's (the collector stopped while measuring);
--   * the handlers (dispatches by their function's file:line) that ran in the edge windows, by CPU;
--   * once a variant, the module functions by inclusive ms over the edges (a wrapped pass, overhead included);
--   * in the busiest setting, each handler of the two events alone (every other one's frame no longer gets them)
--     against none of them: what each costs by itself;
--   * the garbage a minute idle, in combat and with a pull every 15 s, and the edges under the incremental
--     collector as the client runs it.
-- Scenarios: the window closed; the Hall (with the "Start raid" stepper when the inbox has a raid starting now);
-- the Web tab; the window closed after the Web tab was open; Raid Tools; a raid of 20 and of 40 with the Raid HUD
-- (WoW: Forever never shows it: Compat.CanReadCombatLog is TBC Anniversary's; forced on here, with 200 combat log
-- events a second in combat); the tour; the guild map (minimap dots, the world map open, guildmates nearby).
-- Variants (COMBAT_VARIANT): member35 (the reporter, the Web tab's publishing switch off); member35pub (the same
-- with the switch on: any player may turn it on, and the Web panel then builds the whole export); member35raid (an
-- inbox with a GOSROST1 raid starting now that this player owns); officer35raid; member500; officer500pub (an
-- officer of 500 with the switch on). With no COMBAT_VARIANT it runs each one in a child process of the same
-- interpreter and prints their reports. The window is also closed after the Web tab (3b-3d): the Web panel's
-- own shown flag stays set under a hidden window or tab, and its combat handler reads IsShown.
--
--   COMBAT_CYCLES=20 lua5.1 -e 'ADDON="."' tools/combat-perf.lua   (the client's Lua: the numbers that matter)
--   luajit -e 'ADDON="."' tools/combat-perf.lua                    (every variant, 4 pulls a scenario: the suite's run)
--   COMBAT_VARIANT=member35 COMBAT_CYCLES=5 ...          one variant, fewer pulls
--   COMBAT_STRICT=0 ...                                  report only (by default it exits 1 when an edge frame takes over 16 ms)
--
-- What a stub cannot model: the C side (frame layout, text measuring and rendering, texture loads, the secure
-- frame manager), every API the stub answers at once; LuaJIT's JIT is not the client's Lua 5.1; os.clock is this
-- machine's CPU. Read the numbers as Lua work only, and relative to each other.
ADDON = ADDON or "."

local VARIANT = os.getenv("COMBAT_VARIANT")
local VARIANTS = { "member35", "member35pub", "member35raid", "officer35raid", "member500", "officer500pub" }

-- ── The driver: each variant in its own process (the harness loads the addon once) ──
if not VARIANT then
  local exe, i = nil, -1
  while arg and arg[i] do exe = arg[i]; i = i - 1 end
  exe = exe or "lua5.1"
  local script = (arg and arg[0]) or (ADDON .. "/tools/combat-perf.lua")
  local failed = false
  -- Run from the suite (no COMBAT_CYCLES), a shorter pass: COMBAT_CYCLES=20 for the full report.
  local cyc = os.getenv("COMBAT_CYCLES") or "4"
  for _, v in ipairs(VARIANTS) do
    local cmd = string.format("COMBAT_CYCLES=%s COMBAT_VARIANT=%s %s -e 'ADDON=%q' %s 2>&1; echo \"__exit $?\"", cyc, v, exe, ADDON, script)
    local p = assert(io.popen(cmd))
    for line in p:lines() do
      local code = line:match("^__exit (%d+)$")
      if code then
        if code ~= "0" then failed = true; print("combat-perf: variant " .. v .. " exited " .. code) end
      else
        print(line)
      end
    end
    p:close()
  end
  os.exit(failed and 1 or 0)
end

local CYCLES = tonumber(os.getenv("COMBAT_CYCLES") or "") or 20
local STRICT = os.getenv("COMBAT_STRICT") ~= "0"   -- a guard by default (#449): COMBAT_STRICT=0 only reports
local FPS = 60
local WINDOW = tonumber(os.getenv("COMBAT_WINDOW") or "") or 150   -- frames after an edge: 2.5 s
local IN_COMBAT_EXTRA = 3 * FPS                                    -- frames of fighting after the enter window
local STUTTER_MS = 16.7
local CLEU_PER_SEC = 200

local V = {
  member35      = { n = 35,  online = 10,  officer = false, raid = false },
  member35pub   = { n = 35,  online = 10,  officer = false, raid = false, companion = true },
  member35raid  = { n = 35,  online = 10,  officer = false, raid = true },
  officer35raid = { n = 35,  online = 10,  officer = true,  raid = true },
  member500     = { n = 500, online = 120, officer = false, raid = false },
  officer500pub = { n = 500, online = 120, officer = true,  raid = true, companion = true },
}
local CFG = assert(V[VARIANT], "unknown COMBAT_VARIANT " .. VARIANT)

ALLOC_GUILD_N, ALLOC_ONLINE = CFG.n, CFG.online
ALLOC_MEASURE_LOGIN = true   -- alloc-budget's run() times every dispatch from the start
ALLOC_LABEL = true           -- keyed by kind and the handler's file:line
ALLOC_TIME = {}

local clockNow = os.clock
local function ms(s) return s * 1000 end

-- ── Before the login: the rank, the inbox, the server's roster answer, the world map ──
local ROSTER_REPLIES, rosterAskAt = 0, -math.huge
local pendingRoster = false
function ALLOC_BEFORE_LOGIN()
  if not CFG.officer then
    GetGuildInfo = function() return "Big Guild", "Member", 5, nil end
    ROSTER_ROWS[1].rankIndex, ROSTER_ROWS[1].rank = 5, "Rank5"
    C_GuildInfo.IsGuildOfficer = function() return false end
    C_GuildInfo.CanEditOfficerNote = function() return false end
    C_GuildInfo.CanViewOfficerNote = function() return false end
    CanEditOfficerNote = function() return false end
    CanGuildInvite = function() return false end
    CanGuildRemove = function() return false end
    CanGuildPromote = function() return false end
  end
  -- The server answers a roster request (GuildRoster) with GUILD_ROSTER_UPDATE about a quarter second later, at
  -- most one every 10 seconds: an ask at a combat edge (the stepper's AskGuildRoster) costs the roster's rebuild.
  local function ask()
    local now = GetTime()
    if pendingRoster or now - rosterAskAt < 10 then return end
    rosterAskAt, pendingRoster = now, true
    C_Timer.After(0.25, function()
      pendingRoster = false
      ROSTER_REPLIES = ROSTER_REPLIES + 1
      if COUNT and COUNT.GUILD_ROSTER_UPDATE then COUNT.GUILD_ROSTER_UPDATE = COUNT.GUILD_ROSTER_UPDATE + 1 end
      if ROSTER_FIRE then ROSTER_FIRE("GUILD_ROSTER_UPDATE", false) end
    end)
  end
  C_GuildInfo.GuildRoster = ask
  GuildRoster = ask
  -- The world map (hidden): its canvas takes the guild map's pin layer.
  local wmf = CreateFrame("Frame", "WorldMapFrame", UIParent)
  local canvas = CreateFrame("Frame", nil, wmf)
  wmf.GetCanvas = function() return canvas end
  wmf.GetMapID = function() return 1453 end
  wmf:Hide()
  -- The inbox: the site's guild block (the reporter publishes only their own character: the guild's block is
  -- what the site sends every member), and in the raid variants a raid this player owns that starts now.
  local LD = LibStub("LibDeflate")
  local enc = GuildOS.Companion.EncodeJson
  local function pack(prefix, t) return prefix .. ":" .. LD:EncodeForPrint(LD:CompressDeflate(enc(t))) end
  local now = GetServerTime()
  local linked, feed = {}, {}
  for i = 2, math.min(CFG.n, 60) do linked[#linked + 1] = "Member" .. i end
  for i = 1, 10 do
    feed[i] = { id = "ev" .. i, type = "member.level60", at = now - i * 3600, key = "Member" .. (i + 1),
      text = "Member" .. (i + 1) .. " reached 60" }
  end
  local inbox = { pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = "Big Guild", at = now - 1800, feed = feed,
    discordLinked = linked }) }
  if CFG.raid then
    local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
    local SLOTS = { "TANK", "HEALER", "MELEE", "RANGED" }
    local members, signups = {}, {}
    for i = 1, 20 do
      local k = "Member" .. (i + 1)
      members[i] = { key = k, name = k, class = CLASSES[i % 9 + 1], spec = "Arms", slot = SLOTS[i % 4 + 1], group = (i - 1) % 4 + 1 }
      signups[i] = { key = k, name = k, class = CLASSES[i % 9 + 1], spec = "Arms", slot = SLOTS[i % 4 + 1],
        status = "yes", group = (i - 1) % 4 + 1, invite = true }
    end
    inbox[#inbox + 1] = pack("GOSROST1", { fmt = "GOSROST1", v = 6, raidId = "raid-now", title = "Molten Core",
      startsAt = now - 300, instance = "Molten Core", instanceKey = "mc", size = 20, guild = "Big Guild",
      members = members, signups = signups, owners = { "Me" } })
  end
  _G.GuildOSInbox = inbox
  _G.GuildOSInboxAck = { at = now - 1800, members = CFG.n }
  local init = GuildOS.InitModules
  GuildOS.InitModules = function(self, ...)
    if self.db and self.db.settings then self.db.settings.companion = CFG.companion == true end
    return init(self, ...)
  end
end

-- ── Helpers ──────────────────────────────────────────────────────────────
local function upvalue(fn, name)
  for i = 1, 200 do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
  end
end
local function where(fn)
  local i = debug.getinfo(fn, "S")
  return (i.short_src:gsub("^.*guildos[^/]*/", ""):gsub("^%./", "")) .. ":" .. (i.linedefined or 0)
end
local function pad(s, n) s = tostring(s); return s .. string.rep(" ", math.max(0, n - #s)) end
local function f1(x) return string.format("%.1f", x) end
local function f2(x) return string.format("%.2f", x) end

-- ── The play ─────────────────────────────────────────────────────────────
function ALLOC_HARNESS(H)
  local FIRE, stepFrame = H.FIRE, H.stepFrame
  ROSTER_FIRE = FIRE
  local EVENTS = assert(upvalue(FIRE, "EVENTS"), "alloc-budget's event table")
  local FRAMES = assert(upvalue(stepFrame, "FRAMES"), "alloc-budget's frame list")
  local GROUP = assert(upvalue(H.goActive, "GROUP"), "alloc-budget's group")
  local UNITS = assert(upvalue(H.goActive, "UNITS"), "alloc-budget's units")
  local UI = GuildOS.UI
  local steppers = upvalue(GuildOS.RefreshRaidSteppers, "steppers") or {}
  local NOTES = {}
  local function note(s) NOTES[#NOTES + 1] = s end

  -- The client's combat state. PLAYER_REGEN_DISABLED fires while the lockdown has not begun yet (the last moment
  -- secure frames can change) and UnitAffectingCombat("player") is already true; _ENABLED after it ended.
  local inCombat, lockdown = false, false
  InCombatLockdown = function() return lockdown end
  UnitAffectingCombat = function(u)
    if u == "player" then return inCombat end
    return inCombat and UNITS[u] ~= nil and UNITS[u].raid ~= nil
  end

  -- The combat log (only reaches a frame that registered it: the Raid HUD where it may read it).
  local CLEU = { 0, "SPELL_DAMAGE", false, "", "", 0, 0, "", "", 0, 0, 0 }
  CombatLogGetCurrentEventInfo = function() return unpack(CLEU, 1, 12) end
  local cleuN = 0
  local CD_SPELLS = { 20484, 29166, 10060 }
  local function fireCleu(k)
    for _ = 1, k do
      cleuN = cleuN + 1
      local n = math.max(1, GROUP.n)
      local u = UNITS["raid" .. (cleuN % n + 1)]
      local ev = (cleuN % 100 == 0) and "SPELL_CAST_SUCCESS" or ((cleuN % 25 == 0) and "SPELL_AURA_APPLIED" or "SPELL_DAMAGE")
      CLEU[1], CLEU[2] = GetTime(), ev
      CLEU[5], CLEU[6] = u and u.name or "Me", 0x514
      CLEU[12] = ev == "SPELL_CAST_SUCCESS" and CD_SPELLS[cleuN % 3 + 1] or 133
      FIRE("COMBAT_LOG_EVENT_UNFILTERED")
    end
  end

  -- Frames, each timed; `perFrame` runs first (the frame's events).
  local cleuRate = 0          -- events a second while in combat
  local cleuAcc = 0
  local function frame(extra)
    local t0 = clockNow()
    if extra then extra() end
    if inCombat and cleuRate > 0 then
      cleuAcc = cleuAcc + cleuRate / FPS
      local k = math.floor(cleuAcc)
      cleuAcc = cleuAcc - k
      if k > 0 then fireCleu(k) end
    end
    stepFrame()
    return clockNow() - t0
  end
  local function run(n)
    local total, maxf = 0, 0
    for _ = 1, n do
      local d = frame()
      total = total + d
      if d > maxf then maxf = d end
    end
    return total, maxf
  end
  local function settle(sec) run(math.floor(sec * FPS)) end

  local function enterEdge()
    inCombat = true
    FIRE("PLAYER_REGEN_DISABLED")
    FIRE("UNIT_FLAGS", "player")
    for i = 1, GROUP.n do FIRE("UNIT_FLAGS", "raid" .. i) end
    lockdown = true
  end
  local function leaveEdge()
    lockdown, inCombat = false, false
    FIRE("PLAYER_REGEN_ENABLED")
    FIRE("UNIT_FLAGS", "player")
    for i = 1, GROUP.n do FIRE("UNIT_FLAGS", "raid" .. i) end
  end

  -- One measured stretch: the edge frame (its event, then the frame), then WINDOW-1 frames; dispatches per label.
  local gcount = collectgarbage
  local function window(edge)
    ALLOC_TIME = {}
    local kb0 = gcount("count")
    local t0 = clockNow()
    local edgeMs = frame(edge)
    local rest, maxf = run(WINDOW - 1)
    local total = clockNow() - t0
    local kb = gcount("count") - kb0
    local rows = ALLOC_TIME
    ALLOC_TIME = {}
    return { edge = edgeMs, max = math.max(edgeMs, maxf), total = total, kb = kb, rows = rows }
  end

  local function newAgg()
    return { n = 0, edge = 0, edgeMax = 0, max = 0, total = 0, ctrl = 0, kb = 0, ctrlKb = 0, kbMax = 0,
      disp = {}, dispMax = 0, dispWhat = "-", setoff = 0 }
  end
  local function add(agg, w, c)
    agg.n = agg.n + 1
    agg.edge = agg.edge + w.edge
    if w.edge > agg.edgeMax then agg.edgeMax = w.edge end
    if w.max > agg.max then agg.max = w.max end
    agg.total, agg.ctrl = agg.total + w.total, agg.ctrl + c.total
    agg.kb, agg.ctrlKb = agg.kb + w.kb, agg.ctrlKb + c.kb
    if w.kb - c.kb > agg.kbMax then agg.kbMax = w.kb - c.kb end
    -- What the edge set off: the edge's own dispatches and the timers, less what ran in the control window under
    -- the same label (a periodic ticker that happened to fall in either). The frames' OnUpdate and the combat log
    -- are steady work, the control's too.
    for sign, rows in pairs({ [1] = w.rows, [-1] = c.rows }) do
      for k, r in pairs(rows) do
        if not k:find("^OnUpdate") and not k:find("^COMBAT_LOG") and not k:find("^UNIT_FLAGS") then
          local d = agg.disp[k] or { ms = 0, n = 0, max = 0 }
          agg.disp[k] = d
          d.ms, d.n = d.ms + sign * r.total, d.n + sign * r.n
          agg.setoff = agg.setoff + sign * r.total
          if sign > 0 then
            if r.max > d.max then d.max = r.max end
            if r.max > agg.dispMax then agg.dispMax, agg.dispWhat = r.max, k end
          end
        end
      end
    end
  end

  -- N pulls: out of combat (control), enter (window), fight, in combat (control), leave (window), rest.
  local function cycles(n)
    local res = { enter = newAgg(), leave = newAgg(), fightMsPerSec = 0, idleMsPerSec = 0 }
    collectgarbage("collect")
    collectgarbage("stop")
    local fight, idle = 0, 0
    for _ = 1, n do
      local cOut = window(nil)
      local wIn = window(enterEdge)
      local f = run(IN_COMBAT_EXTRA)
      fight = fight + f
      local cIn = window(nil)
      local wOut = window(leaveEdge)
      idle = idle + run(IN_COMBAT_EXTRA)
      add(res.enter, wIn, cOut)
      add(res.leave, wOut, cIn)
      collectgarbage("restart"); collectgarbage("step", 0); collectgarbage("stop")
    end
    collectgarbage("restart")
    collectgarbage("collect")
    res.fightMsPerSec = ms(fight) / (n * IN_COMBAT_EXTRA / FPS)
    res.idleMsPerSec = ms(idle) / (n * IN_COMBAT_EXTRA / FPS)
    return res
  end

  local function stepperShown()
    for _, s in ipairs(steppers) do if s.btn:IsVisible() then return true end end
    return false
  end
  local function hidePopups()
    -- what the login opened by itself (the owner's raid prompt, the digest, what's new): closed, as a player would
    local main = UI:GetMainWindow()
    for _, s in ipairs(steppers) do
      if s.btn:IsVisible() then
        local f = s.btn
        while f.__parent and f.__parent ~= UIParent do f = f.__parent end
        if f ~= main then f:Hide() end
      end
    end
  end
  local function closeWindow() local w = UI:GetMainWindow(); if w then w:Hide() end end
  local function open(id, sub)
    local ok, e = pcall(UI.OpenWindow, UI, id, sub)
    if not ok then note("open " .. id .. ": " .. tostring(e)) end
    return ok and e ~= false
  end

  local function setRaid(n)
    GROUP.raid, GROUP.n = n > 0, n
    for i = 1, 40 do UNITS["raid" .. i] = nil end
    for i = 1, n do
      local r = ROSTER_ROWS[i + 1]
      if r then
        UNITS["raid" .. i] = { name = r.name, guid = r.guid, class = r.classFile, raid = i }
      else
        UNITS["raid" .. i] = { name = "Pug" .. i, guid = string.format("Player-1-9%07d", i), class = "MAGE", raid = i }
      end
    end
    FIRE("GROUP_ROSTER_UPDATE"); FIRE("ZONE_CHANGED_NEW_AREA")
    settle(3)
  end

  -- Guildmates nearby on the map: positions every 2 s (flags follow combat: they fight beside the player), one
  -- of them watching this client's (so its position goes out, the combat flag with it).
  local GM = GuildOS.GuildMap
  local mapPeers = false
  local mapTick = 0
  local function mapFeed()
    if not mapPeers then return end
    mapTick = mapTick + 1
    if mapTick % 20 ~= 0 then return end
    local k = (mapTick / 20) % 8
    local who = "Member" .. (3 + k)
    local flags = inCombat and GM.F_COMBAT or 0
    pcall(GM.HandlePosition, GM, who, string.format("1453,%d,%d,10,%d", 5000 + k * 30 + mapTick % 50, 4000 + k * 20, flags), "GUILD")
  end
  local baseFrame = frame
  frame = function(extra)
    return baseFrame(function() mapFeed(); if extra then extra() end end)
  end

  -- ── Login settles: three minutes of a quiet evening (the guild's traffic scaled to who is online) ──
  local idleSc = {}
  for k, v in pairs(H.SC.idle) do idleSc[k] = v end
  idleSc.copies = math.min(15, CFG.online - 1)
  for _ = 1, 180 do H.simSecond(idleSc) end
  hidePopups()
  closeWindow()
  settle(5)
  local loginErrs = #H.errors()
  local BUILD = "switch off"
  do
    local co = GuildOS.Companion
    if co and co:IsEnabled() then
      collectgarbage("collect"); collectgarbage("stop")
      local kb0, t0 = collectgarbage("count"), clockNow()
      local text, count = co:Build()
      local dt, kb = clockNow() - t0, collectgarbage("count") - kb0
      collectgarbage("restart")
      local t1 = clockNow()
      local payload = co:BuildPayload()
      local dp = clockNow() - t1
      BUILD = string.format("Companion:Build %.1f ms (BuildPayload %.1f ms), %.0f KB garbage, %d members, %d characters on the wire",
        ms(dt), ms(dp), kb, tonumber(count) or 0, type(text) == "string" and #text or 0)
      -- Where the time goes: the JSON, the deflate at the export's level 9, and at lower levels for comparison.
      local LD = LibStub("LibDeflate")
      local t2 = clockNow()
      local json = co.EncodeJson(payload)
      local dj = clockNow() - t2
      local parts = {}
      for _, lvl in ipairs({ 9, 5, 1 }) do
        local t3 = clockNow()
        local c = LD:CompressDeflate(json, { level = lvl })
        local dc = clockNow() - t3
        parts[#parts + 1] = string.format("level %d %.1f ms (%d bytes)", lvl, ms(dc), #c)
      end
      local t4 = clockNow()
      LD:EncodeForPrint(LD:CompressDeflate(json, { level = 1 }))
      BUILD = BUILD .. string.format("\n   ... JSON %.1f ms (%d bytes), deflate %s", ms(dj), #json, table.concat(parts, ", "))
      local _ = t4
    end
  end

  -- Counted in every scenario (calls a pull): what the edges are suspected of running.
  COUNT = {}
  local function count(name, mod, fn)
    local f = mod and mod[fn]
    if type(f) ~= "function" then return end
    COUNT[name] = 0
    mod[fn] = function(...) COUNT[name] = COUNT[name] + 1; return f(...) end
  end
  count("Companion:Build", GuildOS.Companion, "Build")
  count("RaidStart:Next", GuildOS.RaidStart, "Next")
  count("RefreshRaidSteppers", GuildOS, "RefreshRaidSteppers")
  count("RaidHUD:Update", GuildOS.RaidHUD, "Update")
  count("GUILD_ROSTER_UPDATE", { f = function() end }, "f")
  local function countWebRefresh()
    for _, f in ipairs(FRAMES) do
      if rawget(f, "Refresh") and rawget(f, "Relayout") and rawget(f, "content") and not rawget(f, "__counted")
        and rawget(f, "publishing") ~= nil then
        f.__counted = true
        count("WebPanel:Refresh", f, "Refresh")
      end
    end
  end

  -- ── Scenarios ──
  local results = {}
  local function scenario(name, setup, teardown, cyc)
    local ok, e = pcall(setup)
    if not ok then note(name .. ": setup failed: " .. tostring(e)) end
    settle(3)
    for k in pairs(COUNT) do COUNT[k] = 0 end
    local r = cycles(cyc or CYCLES)
    r.name, r.stepper = name, stepperShown()
    r.frames = #FRAMES
    r.counts = {}
    for k, c in pairs(COUNT) do r.counts[k] = c; COUNT[k] = 0 end
    results[#results + 1] = r
    if teardown then pcall(teardown) end
    settle(3)
    return r
  end

  scenario("1 window closed", function() end)
  scenario("2 Hall", function() open("home") end, closeWindow)
  scenario("3 Web tab", function() open("web"); countWebRefresh() end, closeWindow)
  scenario("3b closed after Web", function() open("web"); settle(1); closeWindow() end)
  scenario("3c Web, Hall, closed", function() open("web"); settle(1); open("home"); settle(1); closeWindow() end)
  scenario("3d closed on Web again", function() open("web"); settle(1); closeWindow() end)
  scenario("4 Raid Tools", function() open("raids", "raidtools") end, closeWindow)
  -- The Raid HUD: as WoW: Forever runs it (never shown), then forced on as TBC Anniversary's (with the log).
  local RH = GuildOS.RaidHUD
  local canRead = GuildOS.Compat.CanReadCombatLog
  scenario("5a raid 20, Forever (no HUD)", function() setRaid(20); cleuRate = CLEU_PER_SEC end)
  scenario("5b raid 20, HUD + log", function()
    GuildOS.Compat.CanReadCombatLog = function() return true end
    GuildOS.db.settings.raidHUDEveryone = true
    RH:Update()
  end)
  local hudShown = RH.frame and RH.frame:IsVisible() or false
  scenario("5c raid 40, HUD + log", function() setRaid(40) end)
  scenario("5d raid 40, HUD + log, Hall", function() open("home") end, function()
    closeWindow()
    GuildOS.Compat.CanReadCombatLog = canRead
    GuildOS.db.settings.raidHUDEveryone = nil
    cleuRate = 0
    setRaid(0)
    RH:Update()
  end)
  local Tour = UI.Tour
  local tourOn = false
  scenario("6 Tour", function()
    open("home")
    tourOn = Tour and Tour:Start("member") or false
  end, function() if Tour then Tour:Stop() end; closeWindow() end)
  scenario("7 guild map", function()
    GM:SetMinimapDots(true)
    mapPeers = true
    pcall(GM.HandleWatch, GM, "Member3", GM:EncodeWatch(1453, true), "GUILD")
    WorldMapFrame:Show()
  end, function() WorldMapFrame:Hide(); mapPeers = false; GM:SetMinimapDots(false) end)

  -- ── 8: each handler of the two events taken away, in the busiest setting (Hall open, raid of 20, HUD on) ──
  local function busy()
    setRaid(20)
    cleuRate = CLEU_PER_SEC
    GuildOS.Compat.CanReadCombatLog = function() return true end
    GuildOS.db.settings.raidHUDEveryone = true
    RH:Update()
    open("home")
    settle(3)
  end
  local function unbusy()
    closeWindow()
    GuildOS.Compat.CanReadCombatLog = canRead
    GuildOS.db.settings.raidHUDEveryone = nil
    cleuRate = 0
    setRaid(0)
  end
  local ABL = math.max(3, math.floor(CYCLES / 4))
  pcall(busy)
  local full = cycles(ABL)
  local handlers = {}
  for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    for f in pairs(EVENTS[ev] or {}) do
      local s = f.__scripts.OnEvent
      local key = s and where(s) or "?"
      handlers[key] = handlers[key] or {}
      handlers[key][#handlers[key] + 1] = { f = f, ev = ev, units = EVENTS[ev][f] }
    end
  end
  -- Each handler alone (every other handler of the two events taken away): what it costs by itself, free of the
  -- others' noise; then all of them against none.
  local function setAll(on)
    for _, list in pairs(handlers) do
      for _, h in ipairs(list) do EVENTS[h.ev][h.f] = on and h.units or nil end
    end
  end
  setAll(false)
  local none = cycles(ABL)
  local ablation = {}
  for key, list in pairs(handlers) do
    for _, h in ipairs(list) do EVENTS[h.ev][h.f] = h.units end
    local r = cycles(ABL)
    for _, h in ipairs(list) do EVENTS[h.ev][h.f] = nil end
    ablation[#ablation + 1] = { key = key, evs = list,
      dEnter = (r.enter.setoff - none.enter.setoff) / ABL, dLeave = (r.leave.setoff - none.leave.setoff) / ABL,
      dEnterEdge = (r.enter.edge - none.enter.edge) / ABL, dLeaveEdge = (r.leave.edge - none.leave.edge) / ABL,
      maxEdge = math.max(r.enter.edgeMax, r.leave.edgeMax),
      dKb = ((r.enter.kb - r.enter.ctrlKb) + (r.leave.kb - r.leave.ctrlKb)
        - (none.enter.kb - none.enter.ctrlKb) - (none.leave.kb - none.leave.ctrlKb)) / ABL / 2 }
  end
  setAll(true)
  local allVsNone = { enter = (full.enter.setoff - none.enter.setoff) / ABL, leave = (full.leave.setoff - none.leave.setoff) / ABL,
    noneEdge = math.max(none.enter.edgeMax, none.leave.edgeMax) }
  table.sort(ablation, function(a, b) return a.dEnter + a.dLeave > b.dEnter + b.dLeave end)

  -- ── Inclusive ms per module function over the edges (a wrapped pass in the busiest setting) ──
  local CALLS, wrapped, onEdge = {}, {}, false
  local SKIP = { db = true, State = true, L = true, Colors = true, C = true }
  local function wrapAll(name, mod)
    for k, f in pairs(mod) do
      if type(f) == "function" and type(k) == "string" then
        local key = name .. "." .. k
        local depth = 0
        local function finish(t0, ...)
          depth = depth - 1
          if onEdge and depth == 0 then
            local row = CALLS[key]
            if not row then row = { n = 0, ms = 0 }; CALLS[key] = row end
            row.n, row.ms = row.n + 1, row.ms + (clockNow() - t0) * 1000
          end
          return ...
        end
        wrapped[#wrapped + 1] = { mod, k, f }
        mod[k] = function(...) depth = depth + 1; return finish(clockNow(), f(...)) end
      end
    end
  end
  wrapAll("GuildOS", GuildOS)
  for k, v in pairs(GuildOS) do
    if type(v) == "table" and type(k) == "string" and not SKIP[k] and v ~= GuildOS then wrapAll(k, v) end
  end
  for k, v in pairs(UI) do
    if type(v) == "table" and type(k) == "string" and not SKIP[k] and v ~= UI then wrapAll("UI." .. k, v) end
  end
  local PROF = math.max(3, math.floor(CYCLES / 4))
  collectgarbage("stop")
  for _ = 1, PROF do
    run(WINDOW)
    onEdge = true; frame(enterEdge); run(WINDOW - 1); onEdge = false
    run(IN_COMBAT_EXTRA)
    onEdge = true; frame(leaveEdge); run(WINDOW - 1); onEdge = false
    run(IN_COMBAT_EXTRA)
  end
  collectgarbage("restart")
  for i = #wrapped, 1, -1 do local w = wrapped[i]; w[1][w[2]] = w[3] end
  local prof = {}
  for k, r in pairs(CALLS) do prof[#prof + 1] = { k, r } end
  table.sort(prof, function(a, b) return a[2].ms > b[2].ms end)

  -- ── The collector as the client runs it (incremental) across the busiest setting's edges ──
  collectgarbage("setpause", 200); collectgarbage("setstepmul", 200)
  collectgarbage("collect")
  local gcEdge = { enter = 0, leave = 0, enterMax = 0, leaveMax = 0, n = 0 }
  for _ = 1, ABL do
    run(WINDOW)
    local w = window(enterEdge)
    gcEdge.enter, gcEdge.enterMax = gcEdge.enter + w.edge, math.max(gcEdge.enterMax, w.max)
    run(IN_COMBAT_EXTRA)
    w = window(leaveEdge)
    gcEdge.leave, gcEdge.leaveMax = gcEdge.leave + w.edge, math.max(gcEdge.leaveMax, w.max)
    run(IN_COMBAT_EXTRA)
    gcEdge.n = gcEdge.n + 1
  end
  pcall(unbusy)
  settle(3)

  -- ── Garbage a minute: idle, in combat, a pull every 15 s (the guild's traffic on, window closed, solo) ──
  local function minuteKB(sc, pulls, fighting)
    collectgarbage("collect"); collectgarbage("stop")
    local kb0, t0 = gcount("count"), clockNow()
    if fighting then inCombat, lockdown = true, true end
    for s = 1, 60 do
      if pulls and s % 15 == 1 then enterEdge() end
      if pulls and s % 15 == 11 then leaveEdge() end
      H.simSecond(sc)
    end
    local kb, cpu = gcount("count") - kb0, clockNow() - t0
    collectgarbage("restart")
    if fighting or inCombat then leaveEdge() end
    return kb, ms(cpu)
  end
  local combatSc = {}
  for k, v in pairs(idleSc) do combatSc[k] = v end
  combatSc.aura, combatSc.target, combatSc.tooltip, combatSc.nameplate = 600, 30, 0, 60
  minuteKB(idleSc)   -- warm-up: what the scenarios left scheduled
  local gcIdle, cpuIdle = minuteKB(idleSc)
  local gcIdle2 = minuteKB(idleSc)
  local gcFight, cpuFight = minuteKB(combatSc, false, true)
  local gcPulls, cpuPulls = minuteKB(combatSc, true)
  local retained = H.fullKB()

  -- ── The report ──
  local errs = H.errors()
  print(string.format("== combat-perf [%s] %s, guild of %d (%d online), %s%s; %d pulls a scenario, window %d frames",
    VARIANT, _VERSION .. (rawget(_G, "jit") and (" / " .. rawget(_G, "jit").version) or ""), CFG.n, CFG.online, CFG.officer and "officer" or "member",
    CFG.raid and ", inbox with a raid starting now (owner)" or "", CYCLES, WINDOW))
  print("   companion export: " .. BUILD)
  print(string.format("   frames made %d, retained after a full collection %.0f KB, %d handler errors (login %d), roster answers %d",
    #FRAMES, retained, #errs, loginErrs, ROSTER_REPLIES))
  print("   per edge, ms (means over the pulls; max = the worst one):")
  print("   " .. pad("scenario", 30) .. pad("edge", 5) .. pad("edgeFr", 8) .. pad("edgeMax", 8) .. pad("frMax", 7)
    .. pad("+win", 7) .. pad("setoff", 7) .. pad("+KB", 7) .. pad("KBmax", 7) .. pad("dispMax", 8) .. "stepper / longest dispatch")
  local worstEdge = 0
  for _, r in ipairs(results) do
    for _, e in ipairs({ "enter", "leave" }) do
      local a = r[e]
      local n = math.max(1, a.n)
      if a.edgeMax > worstEdge then worstEdge = a.edgeMax end
      print("   " .. pad(e == "enter" and r.name or "", 30) .. pad(e, 5) .. pad(f2(ms(a.edge / n)), 8) .. pad(f2(ms(a.edgeMax)), 8)
        .. pad(f2(ms(a.max)), 7) .. pad(f2(ms((a.total - a.ctrl) / n)), 7) .. pad(f2(ms(a.setoff / n)), 7)
        .. pad(f1((a.kb - a.ctrlKb) / n), 7)
        .. pad(f1(a.kbMax), 7) .. pad(f2(ms(a.dispMax)), 8)
        .. (e == "enter" and (r.stepper and "stepper " or "") or "") .. a.dispWhat)
    end
  end
  print("   steady CPU, ms a second: fighting / out of combat; calls a pull (both edges and their windows, control windows included)")
  for _, r in ipairs(results) do
    local cs = {}
    for k, c in pairs(r.counts) do if c > 0 then cs[#cs + 1] = string.format("%s %.1f", k, c / CYCLES) end end
    table.sort(cs)
    print(string.format("     %-30s %6.2f / %6.2f   %s", r.name, r.fightMsPerSec, r.idleMsPerSec, table.concat(cs, ", ")))
  end
  print("   what each edge set off, per scenario (handlers and timers by file:line: ms a pull, dispatches a pull, max ms)")
  for _, r in ipairs(results) do
    for _, e in ipairs({ "enter", "leave" }) do
      local rows = {}
      for k, d in pairs(r[e].disp) do rows[#rows + 1] = { k, d } end
      table.sort(rows, function(a, b) return a[2].ms > b[2].ms end)
      local parts = {}
      for i = 1, math.min(4, #rows) do
        local d = rows[i][2]
        if d.ms > 0 then
          parts[#parts + 1] = string.format("%s %.2f/%.1f/%.2f", rows[i][1], ms(d.ms / r[e].n), d.n / r[e].n, ms(d.max))
        end
      end
      print(string.format("     %-28s %-5s %s", r.name, e, table.concat(parts, "; ")))
    end
  end
  print(string.format("   8. each handler alone vs none (Hall open, raid of 20, HUD + log; %d pulls): ms a pull of what the edge set off / of the edge frame, enter then leave; worst edge frame; KB an edge", ABL))
  print(string.format("     all handlers vs none: enter %.2f ms, leave %.2f ms; with none the worst edge frame is %.2f ms",
    ms(allVsNone.enter), ms(allVsNone.leave), ms(allVsNone.noneEdge)))
  for _, a in ipairs(ablation) do
    local evs = {}
    for _, h in ipairs(a.evs) do evs[#evs + 1] = h.ev == "PLAYER_REGEN_DISABLED" and "D" or "E" end
    print(string.format("     %-34s %-4s %7.2f / %7.2f   %7.2f / %7.2f   %7.2f   %8.1f", a.key, table.concat(evs), ms(a.dEnter),
      ms(a.dEnterEdge), ms(a.dLeave), ms(a.dLeaveEdge), ms(a.maxEdge), a.dKb))
  end
  print(string.format("   module functions by inclusive ms over the edge windows (%d pulls, wrapped: overhead included; ms a pull, calls a pull)", PROF))
  for i = 1, math.min(15, #prof) do
    print(string.format("     %8.2f %7.1f  %s", prof[i][2].ms / PROF, prof[i][2].n / PROF, prof[i][1]))
  end
  print(string.format("   incremental collector (pause 200, stepmul 200), busiest setting: edge frame enter %.2f ms (max frame %.2f), leave %.2f ms (max frame %.2f)",
    ms(gcEdge.enter / gcEdge.n), ms(gcEdge.enterMax), ms(gcEdge.leave / gcEdge.n), ms(gcEdge.leaveMax)))
  print(string.format("   garbage a minute (window closed, solo): idle %.0f / %.0f KB (%.0f ms CPU), fighting %.0f KB (%.0f ms), a pull every 15 s %.0f KB (%.0f ms)",
    gcIdle, gcIdle2, cpuIdle, gcFight, cpuFight, gcPulls, cpuPulls))
  print(string.format("   checks: Raid HUD shown when forced %s; tour started %s; stepper on the Hall %s",
    tostring(hudShown), tostring(tourOn), tostring(results[2].stepper)))
  for _, n in ipairs(NOTES) do print("   note: " .. n) end
  local seen = {}
  for i = 1, #errs do
    local e = errs[i]:sub(1, 160)
    if not seen[e] and #seen < 6 then seen[e] = true; seen[#seen + 1] = e; print("   handler error: " .. e) end
  end
  if STRICT and ms(worstEdge) > STUTTER_MS then
    io.stderr:write(string.format("FAIL: an edge frame took %.1f ms\n", ms(worstEdge)))
    os.exit(1)
  end
  os.exit(0)
end

dofile(ADDON .. "/tools/alloc-budget.lua")
