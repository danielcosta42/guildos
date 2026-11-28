-- No lag spikes from the companion's inbox while publishing (issue #449). Officers who publish to the companion
-- (the guild setting `companion`) reported periodic lag spikes in a big guild that went away once they stopped. The
-- export itself is built at logout only: what publishing turns on during play is everything that reads the
-- companion's Inbox.lua (_G.GuildOSInbox): the guild's GOSGILD1, the raids' GOSROST1, the cores' GOSCORE1, the
-- alliance's GOSALLY1 (about a megabyte inflated), and what each module reads of them on every roster update, chat
-- line, tick and panel draw.
--
-- This runs the whole addon under tools/alloc-budget.lua's stubbed WoW: Forever client (a guild of 500, 120 online)
-- with an inbox the size a big guild's is, made by the addon's own encoders: a GOSGILD1 (500 linked keys, the feed,
-- the site's events, join requests, the alliance's bans, its code), ten GOSROST1 raids with full sign-ups and loot,
-- a GOSCORE1 of six cores and a GOSALLY1 at Import.ALLY's caps. Then ten simulated minutes of play: a roster update
-- every three seconds, guild and trade chat, the addon traffic, the window opened on the Hall, the Raids (Raid Tools),
-- the calendar, the Alliance and the Members tab, then a raid of 20 in combat with the window on the Hall. It holds:
--   * every inbox string is decoded (LibDeflate's DecodeForPrint) at most once, whatever asks for it and how often;
--   * no single dispatch during play (a frame's handler, a timer, an event) takes over SPIKE_MS of CPU, and the
--     login's longest stays under LOGIN_SPIKE_MS;
--   * the garbage a minute with publishing on stays under alloc-budget.lua's budgets (idle and active).
--
--   luajit -e 'ADDON="."' tools/inbox-perf.lua
--   INBOX_COMPANION=0 ...   the same play with publishing off (for comparing)
--   INBOX_REPORT=1 ...      the top triggers by CPU, the decodes and the module calls, over the whole run
--   INBOX_SOFT=1 ...        a failed check is said and the run goes on (to measure an older build)
--   INBOX_PROFILE=1 ...     alloc-budget.lua's allocation profile, per function, of each tab and the idle and active runs
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local ON = os.getenv("INBOX_COMPANION") ~= "0"
local REPORT = os.getenv("INBOX_REPORT") == "1"
local SPIKE_MS = 50              -- a frame at 60 fps is 16.7 ms: 50 ms is three frames lost, a hitch anyone sees
local LOGIN_SPIKE_MS = 200       -- the login's own burst (the client is on its loading screen for part of it)
local IDLE_BUDGET_KB = 600       -- alloc-budget.lua's
local MEMBERS_BUDGET_KB = 1500   -- alloc-budget.lua's for the window open on the Members tab: here every tab in turn
local ACTIVE_BUDGET_KB = 4000

ALLOC_GUILD_N, ALLOC_ONLINE = 500, 120
ALLOC_MEASURE_LOGIN = true
ALLOC_LABEL = true
ALLOC_TIME = {}

local DECODES = {}               -- [body] = { n, ms, len, during }
local CALLS = {}                 -- ["Module.fn"] = { n, ms }
local LOGIN_DONE = false
local clockNow = os.clock

-- ── The inbox ────────────────────────────────────────────────────────────
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
local SLOTS = { "TANK", "HEALER", "MELEE", "RANGED" }
local function buildInbox()
  local LD = LibStub("LibDeflate")
  local enc = GuildOS.Companion.EncodeJson
  local function pack(prefix, t) return prefix .. ":" .. LD:EncodeForPrint(LD:CompressDeflate(enc(t))) end
  local now = GetServerTime()
  local inbox = {}

  -- The guild's block.
  local linked, feed, events, joins, bans = {}, {}, {}, {}, {}
  for i = 2, 500 do linked[#linked + 1] = "Member" .. i end
  for i = 1, 40 do
    feed[i] = { id = "ev" .. i, type = "member.level60", at = now - i * 3600, key = "Member" .. (i + 1),
      text = "Member" .. (i + 1) .. " reached 60" }
  end
  for i = 1, 10 do
    events[i] = { id = "site-ev-" .. i, kind = ({ "social", "pvp", "meetup", "other" })[i % 4 + 1],
      title = "Guild night " .. i, startsAt = now + i * 86400, where = "Goldshire", going = 30 + i, maybe = 5 }
  end
  for i = 1, 30 do
    joins[i] = { id = "jr-" .. i, character = "Applicant" .. i, class = CLASSES[i % 9 + 1], level = 60, role = "DPS",
      note = "hello, I raid three nights a week", source = "site", status = "pending", at = now - i * 600 }
  end
  for i = 1, 200 do
    bans[i] = { id = "ban-" .. i, key = "Ninja" .. i, name = "Ninja" .. i, guild = "Other Guild " .. (i % 15 + 1),
      reason = "ninja", note = "rolled need on everything", at = now - i * 86400 }
  end
  inbox[#inbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = "Big Guild", at = now - 1800, feed = feed,
    events = events, discordLinked = linked, joinRequests = joins, allianceBans = bans,
    alliance = { code = "GOS=BIG:AbCdE12345", name = "The Big Pact", version = 3 },
    activation = { steps = { publish = true, bot = true, account = true, members = true, run = true }, at = now - 1800 },
    founding = { foundedAt = now - 90 * 86400, source = "site", declaredBy = "Me", recordedAt = now - 80 * 86400,
      founders = { "Me", "Member2" }, revision = 2 } })

  -- Ten raids with full sign-ups and their loot: one under way now, the rest over the next days.
  for r = 1, 10 do
    local members, signups, soft, prios, wishes = {}, {}, {}, {}, {}
    for i = 1, 40 do
      local k = "Member" .. ((r * 37 + i) % 499 + 2)
      members[i] = { key = k, name = k, class = CLASSES[i % 9 + 1], spec = "Arms", slot = SLOTS[i % 4 + 1], group = (i - 1) % 8 + 1 }
    end
    for i = 1, 80 do
      local k = "Member" .. ((r * 53 + i) % 499 + 2)
      signups[i] = { key = k, name = k, class = CLASSES[i % 9 + 1], spec = "Arms", slot = SLOTS[i % 4 + 1],
        status = i <= 60 and "yes" or "maybe", group = (i - 1) % 8 + 1, invite = i <= 40 }
    end
    for i = 1, 40 do
      soft[i] = { key = members[i].key, name = members[i].name, class = members[i].class, items = { 19000 + i, 19100 + i } }
      wishes[i] = { key = members[i].key, name = members[i].name, class = members[i].class,
        items = { { id = 19000 + i, o = 1 }, { id = 19200 + i, o = 2 } } }
    end
    for i = 1, 30 do
      prios[i] = { id = 19300 + i, order = { { key = members[i].key, name = members[i].name, class = members[i].class, rank = 1 },
        { key = members[i + 1].key, name = members[i + 1].name, class = members[i + 1].class, rank = 2 } } }
    end
    inbox[#inbox + 1] = pack("GOSROST1", { fmt = "GOSROST1", v = 6, raidId = "raid-" .. r, title = "Molten Core " .. r,
      startsAt = r == 1 and now - 1800 or now + r * 86400, instance = "Molten Core", instanceKey = "mc", size = 40,
      guild = "Big Guild", members = members, signups = signups, owners = { "Me" },
      softres = { soft = soft, hard = { { id = 19999, ["for"] = "Tank" } } }, prios = prios, wishlists = wishes })
  end

  -- The cores.
  local cores = {}
  for c = 1, 6 do
    local ms = {}
    for i = 1, 25 do
      local k = "Member" .. ((c * 71 + i) % 499 + 2)
      ms[i] = { key = k, name = k, class = CLASSES[i % 9 + 1], slot = "dps", status = "main" }
    end
    cores[c] = { tag = "core-" .. c, name = "Core " .. c, size = 25, members = ms, waiting = { "Applicant1" } }
  end
  inbox[#inbox + 1] = pack("GOSCORE1", { fmt = "GOSCORE1", v = 1, guild = "Big Guild", cores = cores, unlinked = 3 })

  -- The alliance's directory at its caps: 16 guilds, 1000 members each, 30 raids; 60,000 recipes (the total's cap
  -- does not fit the site's 256 KiB).
  local A = GuildOS.CompanionImport.ALLY
  local guilds, raids, budget = { { name = "Big Guild", self = true } }, {}, A.recipeTotal
  for g = 2, A.guilds do
    local ms, crafters = {}, {}
    for i = 1, A.members do
      ms[i] = { key = "G" .. g .. "M" .. i, name = "G" .. g .. "M" .. i, class = CLASSES[i % 9 + 1], level = 60,
        role = ({ "TANK", "HEALER", "DPS" })[i % 3 + 1], main = i % 4 == 0 and ("G" .. g .. "M" .. (i - 1)) or nil }
    end
    for i = 1, 40 do
      local n = math.min(100, budget)
      if n <= 0 then break end
      local rec = {}
      for k = 1, n do rec[k] = 2000 + (g * 131 + i * 17) % 20000 + k * 3 end
      budget = budget - n
      crafters[i] = { key = ms[i * 10].key, recipes = rec }
    end
    guilds[g] = { name = "Other Guild " .. g, via = "invite", members = ms, crafters = crafters }
  end
  for i = 1, A.raids do
    raids[i] = { id = "ally-raid-" .. i, guild = "Other Guild " .. (i % 15 + 2), title = "Naxxramas " .. i, where = "Naxx",
      startsAt = now + i * 7200, size = 40, lead = "G2M1", going = 20 }
  end
  local ally = pack("GOSALLY1", { fmt = "GOSALLY1", v = 1, guild = "Big Guild", at = now - 1800,
    alliance = { name = "The Big Pact", tag = "BIG", version = 3 }, guilds = guilds, raids = raids })
  inbox[#inbox + 1] = ally
  return inbox, #ally - 9
end

-- ── Counting ─────────────────────────────────────────────────────────────
local function wrapDecodes()
  local LD = LibStub("LibDeflate")
  local decode = LD.DecodeForPrint
  LD.DecodeForPrint = function(self, body, ...)
    local t0 = clockNow()
    local a, b = decode(self, body, ...)
    local row = DECODES[body]
    if not row then row = { n = 0, ms = 0, len = #tostring(body) }; DECODES[body] = row end
    row.n, row.ms = row.n + 1, row.ms + (clockNow() - t0) * 1000
    row.during = row.during or (LOGIN_DONE and "play" or "login")
    return a, b
  end
  for _, name in ipairs({ "DecompressDeflate", "DecompressDeflateLimited" }) do
    local f = LD[name]
    local row = { n = 0, ms = 0, by = {} }
    CALLS["LibDeflate." .. name] = row
    LD[name] = function(...)
      local t0 = clockNow()
      local a, b = f(...)
      row.n, row.ms = row.n + 1, row.ms + (clockNow() - t0) * 1000
      if (clockNow() - t0) * 1000 > (row.max or 0) then row.max = (clockNow() - t0) * 1000 end
      return a, b
    end
  end
  -- Inclusive time of every function of the modules that read the inbox, by name.
  local function wrapAll(name, mod)
    if type(mod) ~= "table" then return end
    for k, f in pairs(mod) do
      if type(f) == "function" and type(k) == "string" then
        local key = name .. "." .. k
        local function finish(t0, ...)
          local row = CALLS[key]
          if not row then row = { n = 0, ms = 0, by = {} }; CALLS[key] = row end
          row.n, row.ms = row.n + 1, row.ms + (clockNow() - t0) * 1000
          local by = CURRENT or "-"
          row.by[by] = (row.by[by] or 0) + 1
          return ...
        end
        mod[k] = function(...) return finish(clockNow(), f(...)) end
      end
    end
  end
  wrapAll("Import", GuildOS.CompanionImport)
  wrapAll("RaidStart", GuildOS.RaidStart)
  wrapAll("Link", GuildOS.AllianceLink)
  wrapAll("Alliance", GuildOS.Alliance)
  wrapAll("RaidTools", GuildOS.RaidTools)
  wrapAll("SiteLoot", GuildOS.SiteLoot)
  wrapAll("Calendar", GuildOS.Calendar)
  wrapAll("GameCalendar", GuildOS.GameCalendar)
  wrapAll("CoreManager", GuildOS.CoreManager)
  wrapAll("BanList", GuildOS.BanList)
  wrapAll("Activation", GuildOS.Activation)
  wrapAll("WinterVeil", GuildOS.WinterVeil)
  wrapAll("AddonReminder", GuildOS.AddonReminder)
  wrapAll("JoinRequests", GuildOS.JoinRequests)
  wrapAll("Digest", GuildOS.Digest)
  local json = GuildOS.JsonDecode
  local jrow = { n = 0, ms = 0, by = {} }
  CALLS["GuildOS.JsonDecode"] = jrow
  GuildOS.JsonDecode = function(s)
    local t0 = clockNow()
    local v = json(s)
    jrow.n, jrow.ms = jrow.n + 1, jrow.ms + (clockNow() - t0) * 1000
    if (clockNow() - t0) * 1000 > (jrow.max or 0) then jrow.max = (clockNow() - t0) * 1000 end
    return v
  end
end

local ALLY_BODY
function ALLOC_BEFORE_LOGIN()
  local inbox
  inbox, ALLY_BODY = buildInbox()
  _G.GuildOSInbox = inbox
  _G.GuildOSInboxAck = { at = GetServerTime() - 1800, members = 500 }
  wrapDecodes()
  -- The guild's setting, once its db is known (InitModules reads the inbox).
  local init = GuildOS.InitModules
  GuildOS.InitModules = function(self, ...)
    if self.db and self.db.settings then self.db.settings.companion = ON end
    return init(self, ...)
  end
end

-- ── The play ─────────────────────────────────────────────────────────────
function ALLOC_HARNESS(H)
  local check = H.check
  if os.getenv("INBOX_SOFT") == "1" then
    -- measuring an older build: every check said, none stops the run
    check = function(cond, what) if not cond then print("FAIL (soft): " .. what) end end
  end
  local Import = GuildOS.CompanionImport
  check(GuildOS:GetSetting("companion") == ON, "publishing is " .. (ON and "on" or "off"))
  check(ALLY_BODY <= Import.ALLY_MAX, string.format("the GOSALLY1 fixture fits the site's cap (%d characters)", ALLY_BODY))
  local loginMax, loginWhat, warmN, warmMax = 0, "-", 0, 0
  for k, row in pairs(ALLOC_TIME) do
    if k:find("CompanionImport", 1, true) and k:find("^OnUpdate") then
      warmN, warmMax = row.n, row.max   -- the alliance's read ahead (Import:WarmAlliance), a piece a frame
    elseif row.max > loginMax then
      loginMax, loginWhat = row.max, k
    end
  end
  local ALLY = GuildOSInbox[#GuildOSInbox]
  if ON then
    check(Import._allyRaw == ALLY and Import._allyData, "the GOSALLY1 was read ahead after the login, before anything asked")
    check(warmN >= 5, string.format("the read ahead took %d frames: spread, not one", warmN))
  end
  LOGIN_DONE = true
  for k in pairs(ALLOC_TIME) do ALLOC_TIME[k] = nil end
  local UI = GuildOS.UI
  if os.getenv("INBOX_PROFILE") == "1" then
    -- alloc-budget.lua's profile of the same stretches, per function (lua5.1 for the client's numbers)
    local sc = {}
    for k, v in pairs(H.SC.idle) do sc[k] = v end
    sc.roster = 20
    for _, t in ipairs({ { "home" }, { "raids", "raidtools" }, { "guild", "calendar" }, { "alliance", "hall" }, { "roster" } }) do
      UI:OpenWindow(t[1], t[2])
      H.profiled(t[1] .. (t[2] and "/" .. t[2] or ""), sc, 1)
    end
    UI:GetMainWindow():Hide()
    H.profiled("idle", H.SC.idle, 2)
    H.goActive()
    H.profiled("active", H.SC.active, 2)
    os.exit(0)
  end

  -- Ten minutes: five with the window opened on another tab each minute and a roster update every three seconds,
  -- two quiet ones with the window closed, three in a raid of 20 in combat with the window on the Hall.
  local sc = {}
  for k, v in pairs(H.SC.idle) do sc[k] = v end
  sc.roster = 20
  local tabs = { { "home" }, { "raids", "raidtools" }, { "guild", "calendar" }, { "alliance", "hall" }, { "roster" } }
  local tabsKB, openMax, openWhat = 0, 0, "-"
  for m = 1, #tabs do
    local t = tabs[m]
    local t0 = clockNow()
    local ok, e = pcall(UI.OpenWindow, UI, t[1], t[2])
    check(ok, "the window opens on " .. t[1] .. ": " .. tostring(e))
    local ms = (clockNow() - t0) * 1000
    if ms > openMax then openMax, openWhat = ms, t[1] .. (t[2] and ("/" .. t[2]) or "") end
    tabsKB = tabsKB + H.scenario(sc, 1)
  end
  tabsKB = tabsKB / #tabs
  local main = UI.GetMainWindow and UI:GetMainWindow()
  if main then main:Hide() end
  local idle = H.scenario(H.SC.idle, 2)
  H.goActive()
  local active = H.scenario(H.SC.active, 3)

  -- ── What it measured ──
  local playMax, playWhat, playCpu = 0, "-", 0
  for k, row in pairs(ALLOC_TIME) do
    playCpu = playCpu + row.total
    if row.max > playMax then playMax, playWhat = row.max, k end
  end
  local decodes, strings, worst, worstLen, decodeMs = 0, 0, 0, 0, 0
  for _, row in pairs(DECODES) do
    decodes, strings, decodeMs = decodes + row.n, strings + 1, decodeMs + row.ms
    if row.n > worst then worst, worstLen = row.n, row.len end
  end
  if ON then
    local a = Import:AllianceBlock()
    check(a and #a.guilds == Import.ALLY.guilds and #a.raids == Import.ALLY.raids, "the GOSALLY1 at its caps reads")
    -- The read ahead reads what a read in one go reads, and waits out combat.
    local function same(x, y, path)
      if type(x) ~= type(y) then return false, path end
      if type(x) ~= "table" then return x == y, path end
      for k, v in pairs(x) do local ok, p = same(v, y[k], path .. "." .. tostring(k)); if not ok then return false, p end end
      for k in pairs(y) do if x[k] == nil then return false, path .. "." .. tostring(k) end end
      return true
    end
    Import._allyRaw, Import._allyData = nil, nil
    local whole = Import:AllianceBlock()
    local ok, where = same(a, whole, "block")
    check(ok, "the block read ahead is the block read in one go (" .. tostring(where) .. ")")
    if Import.WarmAlliance then   -- (an older build has no read ahead)
      -- Frames alone (no event, the window closed): nothing else asks for the block meanwhile.
      if main then main:Hide() end
      Import._allyRaw, Import._allyData = nil, nil
      local combat = InCombatLockdown
      InCombatLockdown = function() return true end
      Import:WarmAlliance()
      for _ = 1, 120 do H.stepFrame() end
      check(Import._allyRaw == nil, "the read ahead waits out combat")
      InCombatLockdown = combat
      for _ = 1, 600 do H.stepFrame() end
      ok, where = same(Import._allyData, whole, "block")
      check(Import._allyRaw == ALLY and ok, "and reads the same block after it (" .. tostring(where) .. ")")
      Import._allyRaw, Import._allyData = nil, nil
      Import:WarmAlliance()
      for _ = 1, 3 do H.stepFrame() end
      check(Import._allyRaw == nil, "three frames in, the read ahead is under way")
      ok, where = same(Import:AllianceBlock(), whole, "block")
      check(ok and Import._allyRaw == ALLY, "asked for halfway, the read ahead is finished there and then (" .. tostring(where) .. ")")
    end
    check(Import:GuildBlock() ~= nil and #(Import:SiteEvents() or {}) == 10, "the GOSGILD1 reads, with its events")
    check(#(GuildOS.RaidTools:SiteRaids()) == 10, "the ten raids read")
  end

  print(string.format("inbox-perf: publishing %s; %d inbox strings, GOSALLY1 body %d characters",
    ON and "ON" or "OFF", #GuildOSInbox, ALLY_BODY))
  print(string.format("inbox-perf: login: longest dispatch %.1f ms (%s); GOSALLY1 read ahead over %d frames, longest %.1f ms",
    loginMax * 1000, loginWhat, warmN, warmMax * 1000))
  print(string.format("inbox-perf: play: CPU %.0f ms over 10 simulated minutes; longest dispatch %.1f ms (%s)",
    playCpu * 1000, playMax * 1000, playWhat))
  print(string.format("inbox-perf: the window's slowest opening %.1f ms (%s)", openMax, openWhat))
  print(string.format("inbox-perf: DecodeForPrint %d calls on %d strings (%.0f ms), at most %d of one string (%d chars)",
    decodes, strings, decodeMs, worst, worstLen))
  print(string.format("inbox-perf: KB a minute: window tabs + roster every 3 s %.0f (budget %d), idle %.0f (budget %d), active %.0f (budget %d)",
    tabsKB, MEMBERS_BUDGET_KB, idle, IDLE_BUDGET_KB, active, ACTIVE_BUDGET_KB))
  if REPORT then
    local rows = {}
    for k, row in pairs(ALLOC_TIME) do rows[#rows + 1] = { k, row } end
    table.sort(rows, function(a, b) return a[2].total > b[2].total end)
    print("== triggers by CPU (play): total ms, dispatches, max ms")
    for i = 1, math.min(25, #rows) do
      local r = rows[i][2]
      print(string.format("%9.1f %7d %8.2f  %s", r.total * 1000, r.n, r.max * 1000, rows[i][1]))
    end
    rows = {}
    for k, row in pairs(CALLS) do rows[#rows + 1] = { k, row } end
    table.sort(rows, function(a, b) return a[2].ms > b[2].ms end)
    print("== module functions by inclusive ms (login and play): ms, calls")
    for i = 1, math.min(40, #rows) do
      local top, topN = "-", 0
      for k, n in pairs(rows[i][2].by or {}) do if n > topN then top, topN = k, n end end
      print(string.format("%9.1f %8d  %-28s mostly under %s (%d)%s", rows[i][2].ms, rows[i][2].n, rows[i][1], top, topN,
        rows[i][2].max and string.format(", longest %.1f ms", rows[i][2].max) or ""))
    end
    print("== decodes: calls, ms, chars, first during")
    for _, row in pairs(DECODES) do print(string.format("%5d %9.1f %8d  %s", row.n, row.ms, row.len, row.during)) end
    local errs = H.errors()
    print("errors", #errs)
    for i = 1, math.min(10, #errs) do print("  " .. errs[i]) end
  end

  check(worst <= 1, string.format("an inbox string was decoded %d times; once per string is the most", worst))
  check(playMax * 1000 < SPIKE_MS, string.format("a dispatch during play took %.1f ms (%s); the most is %d",
    playMax * 1000, playWhat, SPIKE_MS))
  check(openMax < SPIKE_MS * 2, string.format("opening the window on %s took %.1f ms", openWhat, openMax))
  check(warmMax * 1000 < SPIKE_MS, string.format("a frame of the read ahead took %.1f ms", warmMax * 1000))
  check(loginMax * 1000 < LOGIN_SPIKE_MS, string.format("the login's longest dispatch took %.1f ms (%s); the most is %d",
    loginMax * 1000, loginWhat, LOGIN_SPIKE_MS))
  check(tabsKB < MEMBERS_BUDGET_KB, string.format("garbage with the window open %.0f KB a minute with the inbox, budget %d",
    tabsKB, MEMBERS_BUDGET_KB))
  check(idle < IDLE_BUDGET_KB, string.format("idle garbage %.0f KB a minute with the inbox, budget %d", idle, IDLE_BUDGET_KB))
  check(active < ACTIVE_BUDGET_KB, string.format("active garbage %.0f KB a minute with the inbox, budget %d", active, ACTIVE_BUDGET_KB))
  print(string.format("inbox-perf: %d checks passed", H.checks()))
  os.exit(0)
end

dofile(ADDON .. "/tools/alloc-budget.lua")
