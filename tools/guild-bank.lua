-- The guild bank (issue #380), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/GuildBankPlan.lua and Modules/GuildBank.lua, with the game's bank played by a stub that
-- moves, merges, splits and locks items as the server does.
--
-- The planner always ends, and ends in the order it promised, losing nothing; a picture travels
-- and only newer tabs replace older ones; a received picture, ledger line, need or request is
-- cleaned and clamped; the ledger never counts a line twice and keeps two equal deposits apart;
-- requests are keyed by their sender and closed only by an officer or their author; organizing
-- runs only where the rank withdraws without limit, and puts a real tab in order.
--
--   luajit -e 'ADDON="."' tools/guild-bank.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = {}
RAID_CLASS_COLORS = {}
local function widget()
  local w = { scripts = {} }
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    return function() end
  end })
end
function CreateFrame() return widget() end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
PLAYER = "Ana"
function UnitName() return PLAYER end
function UnitClass() return "Warrior", "WARRIOR" end
local NOW, CLOCK = 1790000000, 1000
function GetServerTime() return NOW end
function GetTime() return CLOCK end
time = function() return NOW end
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() end }
-- The guild's levels, for the cleanup's "few are its level".
ROSTER_LEVELS = {}
function GetNumGuildMembers() return #ROSTER_LEVELS end
function GetGuildRosterInfo(i) return "M" .. i, "Rank", 1, ROSTER_LEVELS[i] end
function IsInGuild() return true end
function GetLocale() return "enUS" end

-- ── The items the stub knows ────────────────────────────────────────────
-- id = { name, quality, classID, subClassID, stack }
local ITEMS = {
  [22854] = { "Flask of Relentless Assault", 1, 0, 3, 20 },
  [22861] = { "Flask of Blinding Light", 1, 0, 3, 20 },
  [22832] = { "Super Mana Potion", 1, 0, 1, 20 },
  [23445] = { "Fel Iron Bar", 1, 7, 7, 20 },
  [21877] = { "Netherweave Cloth", 1, 7, 5, 20 },
  [23440] = { "Dawnstone", 3, 3, 1, 20 },
  [28555] = { "Seamaiden's Pendant", 4, 4, 0, 1 },
  [30000] = { "Pattern: Example", 3, 9, 2, 1 },
  -- The cleanup's: name, quality, class, subclass, stack, required level, vendor price (copper).
  [4500] = { "Broken Fang", 0, 15, 0, 20, 0, 25 },
  [4501] = { "Low Sword", 2, 2, 7, 1, 12, 1500 },
  [4502] = { "Old Elixir", 1, 0, 2, 20, 20, 40 },
  [4503] = { "Linen Cloth", 1, 7, 5, 20, 0, 13, 5 },          -- (8th: item level)
  [4504] = { "Minor Scroll", 1, 0, 4, 20, 5, 25 },
  [4505] = { "Blood Shard", 1, 12, 0, 20, 0, 0 },
  [4506] = { "Small Pouch", 1, 1, 0, 1, 0, 25, 5 },
}
local function idOf(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then return tonumber(item:match("item:(%d+)")) or tonumber(item) end
end
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::70:::::|h[" .. ITEMS[id][1] .. "]|h|r" end
function GetItemInfoInstant(item)
  local id = idOf(item)
  local it = id and ITEMS[id]
  if not it then return nil end
  return id, "", "", "", "icon" .. id, it[3], it[4]
end
function GetItemInfo(item)
  local id = idOf(item)
  local it = id and ITEMS[id]
  if not it then return nil end
  return it[1], linkOf(id), it[2], it[8] or 100, it[6] or 1, "", "", it[5], "", "icon" .. id, it[7] or 10
end

-- ── The server's bank ──────────────────────────────────────────────────
local BANK
local cursor
local function resetBank()
  BANK = { tabs = {}, money = 1234567, log = {}, moneyLog = {}, current = 1, leader = false }
  cursor = nil
end
local function addTab(name, remaining, canDeposit)
  BANK.tabs[#BANK.tabs + 1] = { name = name, slots = {}, remaining = remaining or -1, canDeposit = canDeposit ~= false }
  return #BANK.tabs
end
function GetNumGuildBankTabs() return #BANK.tabs end
function GetGuildBankTabInfo(tab)
  local t = BANK.tabs[tab]
  if not t then return nil end
  return t.name, "tabicon" .. tab, true, t.canDeposit, t.remaining, t.remaining
end
function GetGuildBankItemInfo(tab, slot)
  local s = BANK.tabs[tab] and BANK.tabs[tab].slots[slot]
  if not s then return nil, 0 end
  return "icon" .. s.id, s.c, s.locked
end
function GetGuildBankItemLink(tab, slot)
  local s = BANK.tabs[tab] and BANK.tabs[tab].slots[slot]
  return s and linkOf(s.id) or nil
end
function QueryGuildBankTab() end
-- The player's bags (bag 0, 16 slots) and gold, a vendor and the bank's gold.
BAG, MONEY = {}, 0
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerItemInfo(bag, slot)
  local it = bag == 0 and BAG[slot]
  if not it then return nil end
  return "icon" .. it.id, it.c, false, ITEMS[it.id][2], false, false, linkOf(it.id), false, (ITEMS[it.id][7] or 10) == 0, it.id
end
function UseContainerItem(bag, slot)
  local it = bag == 0 and BAG[slot]
  if not it or not MERCHANT then return end
  MONEY = MONEY + (ITEMS[it.id][7] or 10) * it.c
  BAG[slot] = nil
end
function GetMoney() return MONEY end
function AutoStoreGuildBankItem(tab, slot)
  local sl = BANK.tabs[tab].slots
  local it = sl[slot]
  if not it then return end
  for k = 1, 16 do
    if not BAG[k] then BAG[k] = { id = it.id, c = it.c }; sl[slot] = nil; return end
  end
end
function DepositGuildBankMoney(c) if c <= MONEY then MONEY = MONEY - c; BANK.money = BANK.money + c end end
function QueryGuildBankLog() end
function GetGuildBankMoney() return BANK.money end
function GetCurrentGuildBankTab() return BANK.current end
function SetCurrentGuildBankTab(tab) BANK.current = tab end
function IsGuildLeader() return BANK.leader end
function CursorHasItem() return cursor ~= nil end
function ClearCursor()
  if cursor and cursor.ghost then return end   -- the server has it; nothing to let go
  -- A swapped-out item on the cursor goes back where the game finds room: the first empty slot.
  if cursor and cursor.held then
    local slots = BANK.tabs[cursor.tab].slots
    for i = 1, 98 do if not slots[i] then slots[i] = BANK.held; break end end
    BANK.held = nil
  end
  cursor = nil
end
function InCombatLockdown() return false end
local moves = 0
-- As in the game, the client shows a drop's result only when the server answers, a moment later,
-- with GUILDBANKBAGSLOTS_CHANGED: until then the tab reads as it was (#380, seen on WoW: Forever).
local LAG = 0.3
local dropNow
function PickupGuildBankItem(tab, slot)
  -- While the server works on a drop, the item still shows on the cursor; another drop then is
  -- one too many (counted, ignored).
  if cursor and cursor.ghost then
    BANK.extraDrops = (BANK.extraDrops or 0) + 1
    return
  end
  -- A server that wants a breath after each move: an operation sent sooner is ignored.
  if BANK.breath and CLOCK - (BANK.lastDone or -99) < BANK.breath then
    BANK.ignored = (BANK.ignored or 0) + 1
    return
  end
  if cursor and GuildOS and GuildOS.GuildBank and not BANK.instant then
    local c = cursor
    if CLOCK - c.at < 0.05 then return end
    local ghost = { ghost = c, tab = c.tab, slot = c.slot, c = c.c, at = c.at }
    cursor = ghost
    GuildOS.Compat.After(LAG, function()
      -- Each drop is the server's own business: it never touches what the player holds meanwhile.
      local ours = cursor
      if ours == ghost then ours = nil end
      cursor = c
      dropNow(tab, slot)
      local after = cursor
      if after == nil then
        cursor = ours
      elseif after == c then
        -- Refused: back on the cursor if it is free, else back where it came from.
        cursor = ours or c
      elseif ours then
        -- A swapped item handed back while the cursor is busy: the game puts it in the first free slot.
        local sl = BANK.tabs[after.tab].slots
        for k = 1, 98 do if not sl[k] then sl[k] = BANK.held; break end end
        BANK.held, cursor = nil, ours
      end
      BANK.lastDone = CLOCK
      if GuildOS.GuildBank:IsOpen() then GuildOS.GuildBank:OnEvent("GUILDBANKBAGSLOTS_CHANGED") end
    end)
    return
  end
  return dropNow(tab, slot)
end
dropNow = function(tab, slot)
  local slots = BANK.tabs[tab].slots
  if not cursor then
    local s = slots[slot]
    if s and BANK.slowPickup then
      -- The server confirms the pickup late: the cursor shows the item only then (or never).
      BANK.pickups = (BANK.pickups or 0) + 1
      local lost = BANK.loseEvery and BANK.pickups % BANK.loseEvery == 0
      GuildOS.Compat.After(BANK.slowPickup, function()
        if not lost and not cursor then cursor = { tab = tab, slot = slot, c = s.c, at = CLOCK } end
      end)
      return
    end
    if s then
      cursor = { tab = tab, slot = slot, c = s.c, at = CLOCK }
      -- The game also says the slots changed on a pickup, and that word can come after the drop.
      GuildOS.Compat.After(0.2, function()
        if GuildOS.GuildBank:IsOpen() then GuildOS.GuildBank:OnEvent("GUILDBANKBAGSLOTS_CHANGED") end
      end)
    end
    return
  end
  -- As in the game: the server confirms a pickup a moment later, and a drop in the same frame is
  -- lost, the item left on the cursor (#380, seen on WoW: Forever).
  if CLOCK - cursor.at < 0.05 then return end
  if BANK.refuse then return end   -- a rank the server will not let move items
  -- A server that throttles: after a burst, it drops moves for a while.
  if BANK.throttle then
    BANK.burst = (BANK.burst or 0) + 1
    if BANK.burst > 4 then
      BANK.quietUntil = CLOCK + 2.5
      BANK.burst = 0
    end
    if CLOCK < (BANK.quietUntil or 0) then return end
  end
  if cursor.held then
    if slots[slot] then return end
    slots[slot], BANK.held, cursor = BANK.held, nil, nil
    return
  end
  local from = BANK.tabs[cursor.tab].slots[cursor.slot]
  local to = slots[slot]
  local n = cursor.c
  local per = ITEMS[from.id][5]
  if not to then
    if n == from.c then slots[slot], BANK.tabs[cursor.tab].slots[cursor.slot] = from, nil
    else slots[slot] = { id = from.id, c = n }; from.c = from.c - n end
  elseif to.id == from.id then
    local take = math.min(n, per - to.c)
    to.c = to.c + take
    from.c = from.c - take
    if from.c <= 0 then BANK.tabs[cursor.tab].slots[cursor.slot] = nil end
  else
    -- A drop on another item: refused (left on the cursor), swapped, or swapped with the other item
    -- handed back on the cursor, depending on BANK.swap.
    BANK.swapsTried = (BANK.swapsTried or 0) + 1
    if BANK.swap == "direct" then
      slots[slot], BANK.tabs[cursor.tab].slots[cursor.slot] = from, to
    elseif BANK.swap == "cursor" then
      slots[slot], BANK.tabs[cursor.tab].slots[cursor.slot] = from, nil
      BANK.held = to
      cursor = { tab = tab, slot = -1, c = to.c, at = CLOCK, held = true }
      moves = moves + 1
      return
    else
      return
    end
  end
  moves = moves + 1
  cursor = nil
end
function SplitGuildBankItem(tab, slot, count)
  if BANK.breath and CLOCK - (BANK.lastDone or -99) < BANK.breath then
    BANK.ignored = (BANK.ignored or 0) + 1
    return
  end
  local s = BANK.tabs[tab].slots[slot]
  check(s and count >= 1 and count <= s.c, "a split takes no more than the slot holds")
  cursor = { tab = tab, slot = slot, c = count, at = CLOCK }
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

-- Timers are held and run by hand; the clock moves with them.
local timers = {}
GuildOS.Compat.After = function(d, fn) timers[#timers + 1] = { at = CLOCK + (d or 0), fn = fn } end
local function runTimers(limit)
  local n = 0
  while #timers > 0 and n < (limit or 100000) do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = table.remove(timers, 1)
    if t.at > CLOCK then CLOCK = t.at end
    t.fn()
    n = n + 1
  end
end

local wire = {}
local officers = { Ana = true }
local revs = {}
GuildOS.SyncService = {
  handlers = {},
  On = function(self, d, fn) self.handlers[d] = fn end,
  Publish = function(_, d, act, data, opts) wire[#wire + 1] = { d = d, act = act, data = data, rev = opts and opts.rev } end,
  GetRevision = function(_, d, k) return revs[d .. k] or 0 end,
  NextRevision = function(_, d, k) revs[d .. k] = (revs[d .. k] or 0) + 1; return revs[d .. k] end,
  ShouldApply = function(_, d, k, rev) return (rev or 0) > (revs[d .. k] or 0) end,
  SetRevision = function(_, d, k, rev) revs[d .. k] = rev end,
}
local officer = true
GuildOS.IsOfficer = function() return officer end
GuildOS.IsOfficerByName = function(_, n) return officers[n] == true end
local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
GuildOS.Compat.HookTooltip = function() return true end

dofile(ADDON .. "/Modules/GuildBankPlan.lua")
dofile(ADDON .. "/Modules/GuildBank.lua")
dofile(ADDON .. "/Modules/GuildBankCleanup.lua")
local Plan, Bank = GuildOS.GuildBankPlan, GuildOS.GuildBank

local function deliver(msg, sender)
  GuildOS.SyncService.handlers[msg.d]({ act = msg.act, data = msg.data, rev = msg.rev }, sender)
end
local function last(d, act)
  for i = #wire, 1, -1 do if wire[i].d == d and (not act or wire[i].act == act) then return wire[i] end end
end
local function fresh()
  GuildOS.db = { settings = {}, members = {} }
  GuildOS.State.gbank = nil
  revs, wire, printed, timers = {}, {}, {}, {}
  resetBank()
  Bank:Initialize()
  timers = {}
end

-- ── The planner ─────────────────────────────────────────────────────────
math.randomseed(380)
for trial = 1, 400 do
  local swaps = trial % 2 == 0   -- every other run plays a bank that swaps
  local slots, rank, stack = {}, {}, {}
  local nkeys = math.random(1, 10)
  for k = 1, nkeys do
    rank["k" .. k] = Plan.SortKey({ id = k, classID = math.random(0, 15), subClassID = math.random(0, 4),
      quality = math.random(0, 5), name = math.random() < 0.7 and ("n" .. math.random(1, 3)) or nil })
    stack["k" .. k] = ({ 1, 5, 20, 200 })[math.random(1, 4)]
  end
  local before = {}
  for i = 1, 98 do
    if math.random() < 0.6 then
      local k = "k" .. math.random(1, nkeys)
      slots[i] = { k = k, c = math.random(1, stack[k]) }
      before[k] = (before[k] or 0) + slots[i].c
    end
  end
  local n = 0
  while true do
    local m = Plan.PlanMove(slots, 98, rank, stack, swaps)
    if not m then break end
    local dest = slots[m.to]
    check(swaps or dest == nil or dest.k == slots[m.from].k, "without swaps, a move only drops into an empty slot or onto the same item")
    Plan.Apply(slots, m, stack)
    n = n + 1
    if n > 1000 then break end
  end
  check(n <= 1000, "a run ends (trial " .. trial .. ")")
  local target = Plan.Target(slots, 98, rank, stack)
  local after = {}
  for i = 1, 98 do
    local s, w = slots[i], target[i]
    check((s == nil) == (w == nil) and (not s or (s.k == w.k and s.c == w.c)), "a run ends in the target order")
    if s then after[s.k] = (after[s.k] or 0) + s.c end
  end
  for k, v in pairs(before) do check(after[k] == v, "a run loses nothing") end
end
check(Plan.GroupOf(0) == "consumable" and Plan.GroupOf(7) == "trade" and Plan.GroupOf(4) == "gear"
  and Plan.GroupOf(nil) == "other", "items fall in their groups")
check(Plan.SortKey({ id = 1, classID = 0, name = "b" }) < Plan.SortKey({ id = 2, classID = 7, name = "a" }),
  "consumables sort before trade goods")
check(Plan.SortKey({ id = 1, classID = 0, quality = 4, name = "z" }) < Plan.SortKey({ id = 2, classID = 0, quality = 1, name = "a" }),
  "the better quality first within a kind")
check(Plan.SortKey({ id = 9, classID = 0, name = "a" }) < Plan.SortKey({ id = 1, classID = 0 }),
  "an item with no name yet sorts after the named ones, by id")

-- ── The picture on the wire ─────────────────────────────────────────────
local enc = Bank._encodeSlots({ [1] = { id = 22854, c = 20 }, [98] = { id = 28555, c = 1, l = "item:28555:0:0" } })
local dec = Bank._decodeSlots(enc)
check(dec[1].id == 22854 and dec[1].c == 20 and dec[98].l == "item:28555:0:0", "a tab's slots travel as they are")
dec = Bank._decodeSlots("0,1,1;99,1,1;5,0,1;6,1,0;7,1,5000;8,123,4,item:1;bad;9,22854,3,|cffEVIL")
local nslots = 0
for _ in pairs(dec) do nslots = nslots + 1 end
check(nslots == 2 and dec[8] and dec[8].l == "item:1" and dec[9] and dec[9].l == nil,
  "a slot out of range, an empty count, a huge count and a link with escapes are dropped")

fresh()
local changed = Bank:ApplySnapshot({ tabs = { [1] = { n = "Flasks|r", ts = NOW - 100, by = "Bea", s = "1,22854,20" },
  [9] = { ts = NOW, s = "1,1,1" }, [2] = { ts = NOW + 99999, s = "1,1,1" } }, m = 500, mt = NOW - 100 }, "Bea")
local db = Bank:Store()
check(changed and db.tabs[1] and db.tabs[1].slots[1].c == 20 and db.tabs[1].name == "Flasksr",
  "a received tab is kept, its name cleaned")
check(db.tabs[9] == nil and db.tabs[2] == nil, "a tab past the last one, or from the future, is refused")
check(not Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 200, s = "1,22832,5" } } }, "Cid") and db.tabs[1].slots[1].id == 22854,
  "an older tab never replaces a newer one")
Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 50, s = "1,22832,5;2,22832,7" } } }, "Cid")
check(db.tabs[1].slots[1].id == 22832 and Bank:CountOf(22832) == 12 and Bank:CountOf(22854) == 0,
  "a newer tab replaces the older, and the counts follow")

-- ── Asking and answering ────────────────────────────────────────────────
wire = {}
GuildOS.SyncService.handlers.gbank({ act = "ask", data = { ts = 0, lt = 0 } }, "Dan")
check(last("gbank", "snap") == nil, "an answer waits")
GuildOS.SyncService.handlers.gbank({ act = "snap", data = { tabs = { [1] = { ts = NOW - 50, s = "" } } } }, "Eva")
runTimers()
check(last("gbank", "snap") == nil, "somebody else's answer as new as ours cancels ours")
GuildOS.SyncService.handlers.gbank({ act = "ask", data = { ts = 0, lt = 0 } }, "Dan")
runTimers()
check(last("gbank", "snap") ~= nil, "with no other answer, ours goes out")
wire = {}
GuildOS.SyncService.handlers.gbank({ act = "ask", data = { ts = NOW, lt = NOW } }, "Dan")
runTimers()
check(last("gbank", "snap") == nil, "nobody answers an ask for nothing newer")

-- ── The ledger ──────────────────────────────────────────────────────────
fresh()
local function line(h, ty, n, id, c) return { t = NOW - h * 3600, ty = ty, n = n, id = id, c = c } end
local read1 = { line(5, "d", "Bea", 23445, 20), line(3, "d", "Bea", 23445, 20), line(3, "d", "Bea", 23445, 20), line(1, "w", "Cid", 22854, 2) }
check(Bank:MergeStream(1, read1) == 4, "a first read adds all its lines, two equal deposits included")
NOW = NOW + 2 * 3600
local function shifted(list, hours)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = { t = e.t + hours * 3600, ty = e.ty, n = e.n, id = e.id, c = e.c } end
  return out
end
-- The same lines read two hours later, each "hours ago" rounded a little differently, and one new.
local read2 = shifted({ read1[2], read1[3], read1[4] }, 1)
read2[#read2 + 1] = line(0, "d", "Dan", 21877, 20)
check(Bank:MergeStream(1, read2) == 1, "a later read adds only what is new")
check(Bank:MergeStream(1, read2) == 0, "the same read again adds nothing")
check(Bank:MergeStream(1, { read1[1], read1[2] }) == 0, "an old read arriving late adds nothing")
local c = Bank:Contributions(30)
check(c.Bea and c.Bea.di == 60 and c.Cid.wi == 2 and c.Dan.di == 20, "contributions sum each member's lines")
check(Bank:MergeStream(0, { { t = NOW, ty = "d", n = "Eva", g = 50000 } }) == 1 and Bank:Contributions(7).Eva.dg == 50000,
  "the money log is its own stream")
-- A shared read is cleaned before it is merged.
wire = {}
GuildOS.SyncService.handlers.gbank({ act = "log", data = { reads = { { k = 99, list = { line(0, "d", "X", 1, 1) } },
  { k = 2, list = { { t = NOW + 999999, ty = "d", n = "X", id = 1, c = 1 }, { t = NOW, ty = "zz" },
    { t = NOW, ty = "d", n = "Fae|r", id = 21877, c = 1e9 } } } } } }, "Fae")
local s2 = Bank:Stream(2)
check(#Bank:Stream(99) == 0 and #s2 == 1 and s2[1].n == "Faer" and s2[1].c == 1000,
  "a shared ledger read loses lines for no tab, from the future or of no kind, and clamps the rest")

-- ── Needs ───────────────────────────────────────────────────────────────
fresh()
officer = true
check(Bank:SetNeed(22854, 60, "raid") and Bank:NeedOf(22854) == 60, "an officer sets a need")
local msg = last("gbankneed", "snap")
check(msg and msg.rev == 1, "and it goes out with a revision")
officer = false
check(not Bank:SetNeed(22854, 10) and Bank:NeedOf(22854) == 60, "a member does not change a need")
revs = {}
GuildOS.SyncService.handlers.gbankneed({ act = "snap", rev = 5, data = { needs = { [22832] = { n = 1e12 }, [0] = { n = 5 }, [21877] = { n = -1 } } } }, "Ana")
check(Bank:NeedOf(22832) == 100000 and Bank:NeedOf(0) == nil and Bank:NeedOf(21877) == nil and Bank:NeedOf(22854) == nil,
  "received needs replace ours, clamped and cleaned")
GuildOS.SyncService.handlers.gbankneed({ act = "snap", rev = 4, data = { needs = {} } }, "Ana")
check(Bank:NeedOf(22832) == 100000, "an older revision is ignored")

-- ── Requests ────────────────────────────────────────────────────────────
fresh()
officer = false
GuildOS.SyncService.handlers.gbankreq({ act = "new", data = { id = "R1", who = "Ana", item = 22854, n = 3, st = "done" } }, "Bea")
local r = Bank:Requests().R1
check(r and r.who == "Bea" and r.st == "open", "a request belongs to its sender and arrives open, whatever it says")
GuildOS.SyncService.handlers.gbankreq({ act = "set", data = { id = "R1", st = "done" } }, "Cid")
check(r.st == "open", "a member who is no officer cannot fill it")
GuildOS.SyncService.handlers.gbankreq({ act = "set", data = { id = "R1", st = "cancelled" } }, "Cid")
check(r.st == "open", "nor cancel somebody else's")
GuildOS.SyncService.handlers.gbankreq({ act = "set", data = { id = "R1", st = "done" } }, "Ana")
check(r.st == "done" and r.by == "Ana", "an officer fills it")
GuildOS.SyncService.handlers.gbankreq({ act = "new", data = { id = "R2", item = 22854, n = 1 } }, "Bea")
GuildOS.SyncService.handlers.gbankreq({ act = "set", data = { id = "R2", st = "cancelled" } }, "Bea-Realm")
check(Bank:Requests().R2.st == "cancelled", "its author cancels it, whichever way the name comes")
check(Bank:Request(22832, 5, "heals") and Bank:IsMe(last("gbankreq", "new").data.who), "I ask, under my own name")

-- ── Organizing a real tab ───────────────────────────────────────────────
fresh()
local free = addTab("Raid", -1)
local limited = addTab("Mats", 5)
local t1 = BANK.tabs[free].slots
t1[3] = { id = 23445, c = 7 }
t1[10] = { id = 22854, c = 5 }
t1[20] = { id = 23445, c = 13 }
t1[21] = { id = 28555, c = 1 }
t1[40] = { id = 22854, c = 20 }
t1[41] = { id = 22854, c = 9 }
t1[55] = { id = 23440, c = 4 }
t1[70] = { id = 22832, c = 20 }
t1[97] = { id = 30000, c = 1 }
BANK.tabs[limited].slots[1] = { id = 21877, c = 20 }
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
check(Bank:IsOpen(), "the bank opens")
CLOCK = CLOCK + 1
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
check(Bank:Store().tabs[free] and Bank:Store().tabs[free].slots[3].c == 7, "opening the bank reads the tabs")
check(last("gbank", "snap") ~= nil, "and shares them")

check(select(1, Bank:CanOrganize(free)) == true, "a tab with no withdrawal limit may be organized")
local ok, why = Bank:CanOrganize(limited)
check(not ok and why and why ~= "", "a tab with limited withdrawals may not, with a reason")
BANK.leader = true
check(select(1, Bank:CanOrganize(limited)) == true, "except by the guild master")
BANK.leader = false
check(#Bank:OrganizableTabs() == 1, "only the tabs I may organize are offered")

local preview, planned = Bank:Preview(free)
check(planned > 0 and #preview == 7, "the preview merges into seven stacks")

moves = 0
check(Bank:StartSort({ free, limited }), "a run starts on what may be organized")
runTimers()
check(Bank:SortState() == nil, "the run ends by itself")
local got = BANK.tabs[free].slots
local want = { { 22832, 20 }, { 22854, 20 }, { 22854, 14 }, { 23445, 20 }, { 23440, 4 }, { 30000, 1 }, { 28555, 1 } }
-- Consumables (the potion, subclass 1, before the flasks, 3), trade goods, the gem, the recipe, then the gear.
local okOrder = true
for i, w in ipairs(want) do
  if not (got[i] and got[i].id == w[1] and got[i].c == w[2]) then okOrder = false end
end
for i = #want + 1, 98 do if got[i] then okOrder = false end end
check(okOrder, "the real tab ends merged and in order")
check(BANK.tabs[limited].slots[1].c == 20, "a tab the rank may not organize is left alone")
check(moves > 0 and cursor == nil, "the moves were made and nothing is left on the cursor")
local said = table.concat(printed, "\n")
check(said:find("Tab 1 organized", 1, true) ~= nil, "the run says what it did")

-- Closing the bank mid-run stops it.
t1 = BANK.tabs[free].slots
t1[1], t1[98] = t1[98], t1[1]
t1[60] = { id = 22854, c = 1 }
check(Bank:StartSort(free), "a second run starts")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")
runTimers()
check(Bank:SortState() == nil and not Bank:IsOpen(), "closing the bank stops the run")

-- A slot that stays locked stops it instead of looping.
Bank:OnEvent("GUILDBANKFRAME_OPENED")
CLOCK = CLOCK + 1
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
BANK.tabs[free].slots[5] = { id = 23445, c = 1, locked = true }
check(Bank:StartSort(free), "a third run starts")
runTimers()
check(Bank:SortState() == nil and table.concat(printed, "\n"):find("did not answer", 1, true) ~= nil,
  "a slot that never unlocks stops the run, with a reason")

-- ── Regressions from the review ────────────────────────────────────────
-- A full log whose lines share hours is lined up again on the next read, however often.
fresh()
local window = {}
for i = 1, 25 do window[i] = { t = NOW - (i <= 12 and 2 or 1) * 3600, ty = "d", n = "Bea", id = 23445, c = i } end
check(Bank:MergeStream(3, window) == 25, "a full log is taken whole the first time")
for round = 1, 3 do
  local nextRead = {}
  for i = 2, 25 do nextRead[#nextRead + 1] = window[i] end
  nextRead[#nextRead + 1] = { t = NOW, ty = "d", n = "Cid", id = 21877, c = 100 + round }
  check(Bank:MergeStream(3, nextRead) == 1, "the next read adds only its new line (round " .. round .. ")")
  window = nextRead
end
check(#Bank:Stream(3) == 28, "and the stream holds every line once")

-- Requests a member sends in a backfill are ignored; an officer's are taken, with times clamped.
fresh()
officers = { Ana = true }
GuildOS.SyncService.handlers.gbankreq({ act = "new", data = { id = "Q1", item = 22854, n = 2 } }, "Bea")
GuildOS.SyncService.handlers.gbank({ act = "reqs", data = { req = { Q1 = { id = "Q1", who = "Cid", item = 22854, n = 2,
  st = "done", by = "Ana", at = NOW + 1e9 } } } }, "Cid")
check(Bank:Requests().Q1.st == "open" and Bank:Requests().Q1.who == "Bea", "a member's backfill changes no request")
GuildOS.SyncService.handlers.gbank({ act = "hist", data = { reads = {}, req = { Q1 = { id = "Q1", who = "Cid", item = 22854,
  n = 2, st = "done", by = "Ana", at = NOW + 10 } } } }, "Cid")
check(Bank:Requests().Q1.st == "open", "nor does a ledger answer that carries requests")
GuildOS.SyncService.handlers.gbank({ act = "reqs", data = { req = { Q2 = { id = "Q2", who = "Dan", item = 22832, n = 1,
  st = "open", at = NOW + 1e9, ts = NOW + 1e9 } } } }, "Ana")
check(Bank:Requests().Q2 and Bank:Requests().Q2.at <= NOW and Bank:Requests().Q2.ts <= NOW,
  "an officer's backfill is taken, its times no later than now")

-- A picture's tab count is the last reader's, not the highest ever claimed.
Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 10, s = "" } }, nt = 8 }, "Eva")
Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 5, s = "" } }, nt = 3 }, "Eva")
check(Bank:Store().numTabs == 3, "a forged tab count passes with the next read")

-- A tab the server never answered keeps what the guild knew of it.
fresh()
local one = addTab("Raid", -1)
local two = addTab("Mats", -1)
BANK.tabs[one].slots[1] = { id = 23445, c = 5 }
Bank:ApplySnapshot({ tabs = { [two] = { n = "Mats", ts = NOW - 999, s = "1,21877,20" } } }, "Bea")
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")   -- tab 1 answers; tab 2 never does
runTimers()
check(Bank:Store().tabs[one].slots[1].c == 5, "the tab that answered is read")
check(Bank:Store().tabs[two].slots[1] and Bank:Store().tabs[two].slots[1].id == 21877, "the one that did not keeps its old picture")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

-- Pausing and resuming at once runs one loop, not two: the run takes the moves a plain run takes.
local function layout(slots)
  slots[2] = { id = 23445, c = 3 }; slots[9] = { id = 22854, c = 4 }; slots[15] = { id = 23445, c = 11 }
  slots[33] = { id = 22832, c = 20 }; slots[60] = { id = 22854, c = 16 }; slots[61] = { id = 28555, c = 1 }
end
local function organizeOnce(fidget)
  fresh()
  local tab = addTab("Raid", -1)
  layout(BANK.tabs[tab].slots)
  Bank:OnEvent("GUILDBANKFRAME_OPENED")
  Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
  runTimers()
  moves = 0
  check(Bank:StartSort(tab), "a run starts")
  if fidget then
    for _ = 1, 3 do Bank:PauseSort(true); Bank:PauseSort(false) end
  end
  runTimers()
  return moves
end
local plain = organizeOnce(false)
check(plain > 0 and organizeOnce(true) == plain, "pausing and resuming never doubles the moves")
fresh()
local tabS = addTab("Raid", -1)
layout(BANK.tabs[tabS].slots)
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
moves = 0
Bank:StartSort(tabS)
Bank:StopSort("cancel")
Bank:StartSort(tabS)
runTimers()
check(moves == plain, "stopping and starting again at once runs one loop")

-- Reads received from the guild line up just as my own do.
fresh()
local shared = {}
for i = 1, 25 do shared[i] = { t = NOW - (i <= 12 and 2 or 1) * 3600, ty = "d", n = "Bea", id = 23445, c = i } end
GuildOS.SyncService.handlers.gbank({ act = "log", data = { reads = { { k = 4, list = shared } } } }, "Bea")
local later = {}
for i = 2, 25 do later[#later + 1] = shared[i] end
later[#later + 1] = { t = NOW, ty = "d", n = "Cid", id = 21877, c = 7 }
GuildOS.SyncService.handlers.gbank({ act = "log", data = { reads = { { k = 4, list = later } } } }, "Cid")
check(#Bank:Stream(4) == 26, "a shared read adds only its new line")

-- A member's "reqs" never cancels an officer's answer.
fresh()
officer = true
Bank:Request(22854, 1)
wire = {}
GuildOS.SyncService.handlers.gbank({ act = "ask", data = { ts = 0, lt = 0, rq = 0 } }, "Dan")
GuildOS.SyncService.handlers.gbank({ act = "reqs", data = { req = {}, mark = 1e15 } }, "Cid")
runTimers()
check(last("gbank", "reqs") ~= nil, "a member's answer cannot silence the officer's")

-- One member cannot fill the request list.
fresh()
for i = 1, 30 do
  GuildOS.SyncService.handlers.gbankreq({ act = "new", data = { id = "F" .. i, item = 22854, n = 1 } }, "Bea")
end
local mine = 0
for _, x in pairs(Bank:Requests()) do if x.who == "Bea" then mine = mine + 1 end end
check(mine == 10, "a member keeps at most ten open requests")
for _ = 1, 12 do Bank:Request(22832, 1) end
local own = 0
for _, x in pairs(Bank:Requests()) do if Bank:IsMe(x.who) then own = own + 1 end end
check(own == 10, "and so do I")

-- A tab that does not answer ends the queries, so no late answer is taken for the next tab.
fresh()
addTab("A", -1); addTab("B", -1); addTab("C", -1)
BANK.tabs[1].slots[1] = { id = 23445, c = 1 }
Bank:ApplySnapshot({ tabs = { [2] = { ts = NOW - 99, s = "1,21877,3" }, [3] = { ts = NOW - 99, s = "1,21877,4" } } }, "Bea")
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")       -- tab 1 answers
runTimers()                                     -- tab 2 never does: the rest is not asked
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")       -- tab 2's late answer
runTimers()
check(Bank:Store().tabs[3].slots[1].c == 4, "a late answer never marks the next tab answered")
-- An empty read does not wipe a tab seen full unless the bank shows it.
check(Bank:Store().tabs[2].slots[1].c == 3, "nor does an empty read wipe a tab seen holding items")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

-- A bank that refuses every drop: the item goes back, nothing is lost, the run stops and says why.
fresh()
local tabR = addTab("Raid", -1)
BANK.tabs[tabR].slots[5] = { id = 23445, c = 3 }
BANK.tabs[tabR].slots[9] = { id = 22854, c = 4 }
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
BANK.refuse = true
check(Bank:StartSort(tabR), "a run starts on a bank that will refuse it")
runTimers()
BANK.refuse = nil
check(Bank:SortState() == nil and cursor == nil, "a refused drop leaves nothing on the cursor, and the run stops")
check(BANK.tabs[tabR].slots[5].c == 3 and BANK.tabs[tabR].slots[9].c == 4, "and nothing moved")
check(table.concat(printed, "\n"):find("refused the moves", 1, true) ~= nil, "saying the bank refused")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

-- A server that throttles bursts of moves: the run waits longer and longer, and still finishes.
local throttledPlain = organizeOnce(false)
fresh()
local tabT = addTab("Raid", -1)
layout(BANK.tabs[tabT].slots)
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
BANK.throttle = true
check(Bank:StartSort(tabT), "a run starts on a throttling server")
runTimers()
BANK.throttle = nil
local tg = BANK.tabs[tabT].slots
check(Bank:SortState() == nil and tg[1] and tg[1].id == 22832 and tg[2].id == 22854 and tg[2].c == 20,
  "the run waits out the throttle and finishes the tab")
check(throttledPlain > 0 and not table.concat(printed, "\n"):find("Stopped", 1, true), "without giving up")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

-- The real bank never sees a swap.
check((BANK.swapsTried or 0) <= 1, "a bank that refuses swaps is asked once, then moved around")

-- A full tab out of order says so instead of trying; one free slot is enough.
do
  local full, rk, st = {}, {}, {}
  for i = 1, 98 do
    local k = "k" .. ((i % 3) + 1)
    full[i] = { k = k, c = 1 }
    rk[k] = Plan.SortKey({ id = (i % 3) + 1, classID = 0, name = k })
    st[k] = 1
  end
  local m, why = Plan.PlanMove(full, 98, rk, st)
  check(m == nil and why == "full", "a full tab with nothing to merge cannot be ordered, and says so")
  full[98] = nil
  local n = 0
  while true do
    local mv = Plan.PlanMove(full, 98, rk, st)
    if not mv then break end
    check(full[mv.to] == nil or full[mv.to].k == full[mv.from].k, "with one slot free, every move lands on an empty slot")
    Plan.Apply(full, mv, st)
    n = n + 1
    if n > 600 then break end
  end
  local tgt = Plan.Target(full, 98, rk, st)
  local ordered = true
  for i = 1, 98 do
    local a2, b2 = full[i], tgt[i]
    if (a2 == nil) ~= (b2 == nil) or (a2 and a2.k ~= b2.k) then ordered = false end
  end
  check(n <= 600 and ordered, "and the tab ends in order through that one free slot")
end

-- A bank that swaps: one move per misplaced stack, fewer than through free slots.
local function organizeWith(mode, fill)
  fresh()
  local tab = addTab("Raid", -1)
  fill(BANK.tabs[tab].slots)
  local before = {}
  for _, x in pairs(BANK.tabs[tab].slots) do before[x.id] = (before[x.id] or 0) + x.c end
  BANK.swap = mode
  Bank:OnEvent("GUILDBANKFRAME_OPENED")
  Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
  runTimers()
  moves, BANK.swapsTried, printed = 0, 0, {}
  check(Bank:StartSort(tab), "a run starts (" .. tostring(mode) .. ")")
  runTimers()
  BANK.swap = nil
  local got, plain, rank, stack = BANK.tabs[tab].slots, nil, nil, nil
  local slots = {}
  for i = 1, 98 do if got[i] then slots[i] = { id = got[i].id, c = got[i].c } end end
  plain, rank, stack = Bank:PlanInput(slots)
  local inOrder = Plan.PlanMove(plain, 98, rank, stack) == nil
  local after = {}
  for _, x in pairs(got) do after[x.id] = (after[x.id] or 0) + x.c end
  for id, n in pairs(before) do check(after[id] == n, "nothing is lost (" .. tostring(mode) .. ", item " .. id .. ")") end
  return moves, inOrder, table.concat(printed, "\n"), cursor
end
local function crowded(slots)
  -- Reversed order, few gaps: what a swap does best.
  local ids = { 30000, 28555, 23440, 23445, 21877, 22861, 22854, 22832 }
  for i, id in ipairs(ids) do slots[i] = { id = id, c = ITEMS[id][5] } end
  slots[20] = { id = 22832, c = 20 }
end
local mSwap, okSwap, saidSwap, curSwap = organizeWith("direct", crowded)
check(okSwap and curSwap == nil and not saidSwap:find("Stopped", 1, true), "a swapping bank ends in order")
check(GuildOS.State.gbank.noSwap ~= true, "and none of its swaps is taken for refused, however late the game answers")
local mCur, okCur, _, curCur = organizeWith("cursor", crowded)
check(okCur and curCur == nil, "and so does one that hands the other item back on the cursor")
local mFree, okFree, saidFree = organizeWith(nil, crowded)
check(okFree and not saidFree:find("Stopped", 1, true), "a bank that refuses swaps still ends in order")
check(mSwap < mFree, "swapping takes fewer moves (" .. mSwap .. " against " .. mFree .. ")")
check(GuildOS.State.gbank.noSwap == true, "and a refused swap is remembered for the session")

-- The item shows in hand while the server answers: the run never drops it again meanwhile.
BANK.extraDrops = 0
organizeWith("direct", crowded)
check((BANK.extraDrops or 0) == 0, "no drop is sent again while the server is still answering one")

-- Pickups the server confirms late (1.2 s), one in five never: the drop waits for the item, none is
-- lost, nothing is left in hand, and a pickup never taken is in the log, with its item.
do
  fresh()
  local tab = addTab("Raid", -1)
  crowded(BANK.tabs[tab].slots)
  BANK.swap, BANK.slowPickup, BANK.loseEvery = "direct", 1.2, 5
  Bank:OnEvent("GUILDBANKFRAME_OPENED")
  Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
  runTimers()
  BANK.extraDrops = 0
  check(Bank:StartSort(tab), "a run starts on a slow bank")
  runTimers()
  BANK.swap, BANK.slowPickup, BANK.loseEvery = nil, nil, nil
  local got = BANK.tabs[tab].slots
  check(Bank:SortState() == nil and cursor == nil and (BANK.extraDrops or 0) == 0, "slow pickups: the run ends, nothing in hand, no drop sent twice")
  check(got[1] and got[1].id == 22832, "and the tab is in order")
  local log = table.concat(Bank:Store().trace or {}, "\n")
  check(log:find("PROBLEM pickup not taken", 1, true) and log:find("(id ", 1, true), "a pickup never taken is logged with its item")
  Bank:OnEvent("GUILDBANKFRAME_CLOSED")
end

-- A server that ignores what comes within 0.35 s of the last move: the run pauses between moves and
-- ends in order, with few operations ignored.
do
  fresh()
  local tab = addTab("Raid", -1)
  crowded(BANK.tabs[tab].slots)
  BANK.swap, BANK.breath, BANK.ignored = "direct", 0.35, 0
  Bank:OnEvent("GUILDBANKFRAME_OPENED")
  Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
  runTimers()
  check(Bank:StartSort(tab), "a run starts on a server that wants a breath")
  runTimers()
  local ignored = BANK.ignored
  BANK.swap, BANK.breath = nil, nil
  check(Bank:SortState() == nil and cursor == nil and BANK.tabs[tab].slots[1].id == 22832, "it ends in order, nothing in hand")
  check(ignored <= 1, "and hardly an operation is ignored (" .. ignored .. ")")
  Bank:OnEvent("GUILDBANKFRAME_CLOSED")
end

-- A client that never takes a drop in the pickup's frame: learned once, kept in the settings.
check(GuildOS.db.settings.gbankSameFrame == nil or GuildOS.db.settings.gbankSameFrame == false, "the same-frame finding is a setting")

-- A client that never says the slots changed for a tab it already has (WoW: Forever): the tabs
-- are read all the same, kept and shared.
do
  fresh()
  local t1, t2, t3 = addTab("A", -1), addTab("B", -1), addTab("C", -1)
  BANK.tabs[t1].slots[1] = { id = 23445, c = 5 }
  BANK.tabs[t2].slots[4] = { id = 22854, c = 3 }
  BANK.current = t1
  wire = {}
  Bank:OnEvent("GUILDBANKFRAME_OPENED")   -- and no GUILDBANKBAGSLOTS_CHANGED, ever
  runTimers()
  local db = Bank:Store()
  check(db.tabs[t1] and db.tabs[t1].slots[1].c == 5 and db.tabs[t2] and db.tabs[t2].slots[4].c == 3,
    "with no word from the game, the tabs holding items are read")
  check(db.tabs[t3] == nil, "an empty tab that is not shown is left as known")
  check(last("gbank", "snap") ~= nil, "and the picture goes to the guild")
  Bank:OnEvent("GUILDBANKFRAME_CLOSED")
end

-- ── The cleanup ─────────────────────────────────────────────────────────
local CL = GuildOS.GuildBankCleanup
do
  local J = CL.Judge
  local function v(it) it.have = it.have or 10; it.lowBelow = 30; return (J(it)) end
  check(v({ quality = 0 }) == "sell", "grey goes")
  check(v({ need = 4, have = 10 }) == "sell" and select(2, J({ need = 4, have = 10, lowBelow = 30 })) == 6,
    "past its need, the rest goes")
  check(v({ need = 10, have = 12 }) == "keep", "an item with a need stays")
  check(v({ requested = true, level = 5, classID = 0 }) == "keep" and v({ demandLines = 3, level = 5, classID = 0 }) == "keep",
    "an item asked for, or taken lately, stays whatever its level")
  check(v({ level = 12, classID = 0 }) == "sell" and v({ level = 12, classID = 4 }) == "sell" and v({ level = 5, classID = 1 }) == "sell",
    "consumables, gear and bags below the guild's level go, from the first look")
  check(v({ level = 5, classID = 7 }) == "review" and v({ level = 5, classID = 9 }) == "review",
    "low-level materials and recipes are only reviewed")
  check(v({ classID = 12, level = 1 }) == "review", "quest items are reviewed")
  check(v({ level = 58, classID = 4 }) == "keep", "gear at the guild's level stays")
  check(v({ level = 58, classID = 4, days = 40 }) == "sell", "unless it sat untouched for a month")
end

fresh()
officer, officers = true, { Ana = true }
local tabC = addTab("Raid", -1)
local slC = BANK.tabs[tabC].slots
slC[1] = { id = 4500, c = 7 }       -- grey
slC[2] = { id = 4501, c = 1 }       -- level 12 sword, 2% of the guild near it
slC[3] = { id = 22854, c = 30 }     -- flask, need 10: 15 past 1.5x
slC[4] = { id = 4502, c = 5 }       -- elixir, will be taken often
slC[5] = { id = 4503, c = 20 }      -- linen: a low-level material
slC[6] = { id = 4504, c = 3 }       -- a low-level scroll
slC[7] = { id = 4505, c = 2 }       -- a quest item
Bank:OnEvent("GUILDBANKFRAME_OPENED")
Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
runTimers()
Bank:SetNeed(22854, 10)
Bank:MergeStream(tabC, { { t = NOW - 3600, ty = "w", n = "Bea", id = 4502, c = 1 }, { t = NOW - 1800, ty = "w", n = "Cid", id = 4502, c = 1 } })
local byId = {}
for _, r in ipairs(CL:Rows()) do byId[r.id] = r end
check(byId[4500].verdict == "sell" and byId[4500].vendor == 25 * 7, "the grey stack is to sell, at its vendor value")
check(byId[4501].verdict == "sell", "the low-level sword is to sell, on the first look")
check(byId[4504].verdict == "sell", "and so is the low-level scroll")
check(byId[4503].verdict == "review" and byId[4505].verdict == "review", "linen and the quest item are for review")
check(byId[22854].verdict == "sell" and byId[22854].out == 20, "the flasks past their need are to sell (20 of 30)")
check(byId[4502].verdict == "keep", "the elixir members take is kept")
local items, value = CL:Summary(CL:Rows())
GuildOS:SetSetting("gbankCleanLow", 10)
local byId2 = {}
for _, r in ipairs(CL:Rows()) do byId2[r.id] = r end
check(byId2[4501].verdict == "keep" and byId2[4504].verdict == "sell", "the officers' level cutoff moves what counts as low")
GuildOS:SetSetting("gbankCleanLow", nil)
check(items == 4 and value > 0, "the summary counts what goes and what it makes")

-- Marks: an officer's, shared; a member's, refused.
wire = {}
check(CL:MarkSuggested() == 4 and CL:MarkedCount() == 4, "marking what is suggested marks the four")
check(last("gbankclean", "snap") ~= nil, "and the marks go to the other officers")
officer = false
check(not CL:SetMark("4502", true), "a member does not mark")
officer = true

-- Taking them out at the bank: the grey stack, the sword and 20 flasks (the flask stack of 30 is
-- bigger than the 20 marked, so it stays: only whole stacks come out).
check(CL:WithdrawMarked(), "taking out starts")
runTimers()
check(not CL:IsWithdrawing(), "and ends")
check(slC[1] == nil and slC[2] == nil and slC[3] and slC[3].c == 30, "the marked whole stacks left the bank")
local outs = CL:Mine().out
check(outs[4500] == 7 and outs[4501] == 1, "what came out is noted for selling")
check(CL:Store().clean.marks[tostring(4500)] == nil, "and their marks are done")

-- Selling at a vendor: only what came out; my own grey stack of the same item stays.
BAG[10] = { id = 4500, c = 3 }    -- mine, from before
local before = 0
MERCHANT = true
CL:OnEvent("MERCHANT_SHOW")
MONEY = 1000
local list = CL:ToSell()
check(list[4500] == 7 and list[4501] == 1, "the vendor bar offers what came out")
check(CL:SellOut(), "selling starts")
runTimers()
local mine = 0
for k = 1, 16 do if BAG[k] and BAG[k].id == 4500 then mine = mine + BAG[k].c end end
check(mine == 3, "my own stack of the same item is not sold")
check(CL:Owed() == 25 * 7 + 1500 + 25 * 3, "what it made is owed to the bank")
CL:OnEvent("MERCHANT_CLOSED")
MERCHANT = nil

-- Back at the bank: the gold goes in.
local bankBefore = BANK.money
check(CL:DepositOwed(), "the owed gold is deposited")
check(BANK.money == bankBefore + 25 * 7 + 1500 + 25 * 3 and CL:Owed() == 0, "all of it, and nothing is owed")
Bank:OnEvent("GUILDBANKFRAME_CLOSED")
ROSTER_LEVELS = {}

-- ── The cleanup: regressions from the pre-merge review ──────────────────
do
  -- A stack swapped for another item of the same count while the run waits is not taken; an
  -- organize run cannot start while stacks are coming out.
  fresh()
  officer, officers = true, { Ana = true }
  local tab = addTab("Raid", -1)
  local sl = BANK.tabs[tab].slots
  sl[1] = { id = 4500, c = 7 }
  sl[2] = { id = 4500, c = 7 }
  sl[3] = { id = 4504, c = 7 }       -- a scroll, same count, not marked
  Bank:OnEvent("GUILDBANKFRAME_OPENED")
  Bank:OnEvent("GUILDBANKBAGSLOTS_CHANGED")
  runTimers()
  BAG = {}
  check(CL:SetMark("4500", true), "the grey stacks are marked")
  wire = {}
  check(CL:WithdrawMarked(), "taking out starts")
  check(not Bank:StartSort(tab), "and no organize run starts meanwhile")
  -- Before the second stack goes, someone puts the scroll where it was.
  sl[2], sl[3] = sl[3], nil
  runTimers()
  local scrolls = 0
  for k = 1, 16 do if BAG[k] and BAG[k].id == 4504 then scrolls = scrolls + BAG[k].c end end
  check(scrolls == 0 and sl[2] and sl[2].id == 4504, "the unmarked scroll in its place stays in the bank")
  check(CL:Mine().out[4500] == 7, "only the stack that really came out may be sold")
  check(last("gbankclean", "snap") ~= nil, "the marks left go to the other officers when the run stops")

  -- Another character of the account sells nothing of it.
  MERCHANT = true
  CL:OnEvent("MERCHANT_SHOW")
  PLAYER = "Alt"
  BAG[12] = { id = 4500, c = 7 }     -- the alt's own grey stack
  local altList = CL:ToSell()
  check(next(altList) == nil, "an alt's own items are never sold as the bank's")
  PLAYER = "Ana"

  -- The vendor closing mid-run still owes what was sold.
  MONEY = 0
  check(CL:SellOut(), "selling starts")
  CL:OnEvent("MERCHANT_CLOSED")
  MERCHANT = nil
  runTimers()
  check(CL:Owed() == 25 * 7, "what was sold before the vendor closed is owed, at the vendor's price")
  Bank:OnEvent("GUILDBANKFRAME_CLOSED")
end

-- "Slots freed" counts stacks, not tabs.
do
  fresh()
  Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 10, s = "1,4500,5;2,4500,5;3,4500,5" } } }, "Bea")
  local _, _, slots = CL:Summary(CL:Rows())
  check(slots == 3, "three grey stacks free three slots")
end

-- ── Typing an item ──────────────────────────────────────────────────────
fresh()
Bank:ApplySnapshot({ tabs = { [1] = { ts = NOW - 10, s = "1,23445,20;2,22854,20" } } }, "Bea")
check(Bank:ParseItemInput(linkOf(22854)) == 22854 and Bank:ParseItemInput("22832") == 22832, "a link or an id names its item")
check(Bank:ParseItemInput("fel iron") == 23445 and Bank:ParseItemInput("Nothing at all") == nil,
  "a name the bank holds names its item; any other names none")

print(string.format("guild-bank: %d checks passed", checks))
