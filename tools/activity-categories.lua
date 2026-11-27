-- The Chronicle's Activity in categories (#449, the maintainer: "can we make this screen categorized?"), run against
-- the real Modules/Digest.lua, Milestones, Journal, RosterLog and UI/CommunityPanel.lua on tools/salao-layout.lua's
-- stub frames (a method the stub does not know raises) under a WoW: Forever client:
--   * dedup: a cap ding held both by the fifty milestone events and by the journal is one person once, in the
--     model, in the login digest and on the screen (before, the same names ran twice, one block under the other);
--   * categorization: Digest:Collect files each thing under its category; Build says them category by category,
--     and hands the popup the same groups;
--   * empty states: a category with nothing hides its card; nothing at all is the centred empty state;
--   * the period: Today, 7 days and 30 days, as pills;
--   * every shown part of a card lies inside it, at a wide window (two columns) and a narrow one (one);
--   * a long list of names shows a few and "and N more", which opens the rest.
--
--   luajit -e 'ADDON="."' tools/activity-categories.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
SALAO_KIT = true
local kit = dofile(ADDON .. "/tools/salao-layout.lua")
SALAO_KIT = nil
local check, flush = kit.check, kit.flush

kit.client({ style = "forever", officer = false })
local NOW, DAY = kit.NOW, 86400
local G = GuildOS
G.Client.maxLevel = 60
for _, f in ipairs({ "Modules/RosterLog.lua", "Modules/Milestones.lua", "Modules/Journal.lua", "Modules/Digest.lua" }) do
  dofile(ADDON .. "/" .. f)
end
for _, f in ipairs({ "Modules/CallToArms.lua", "Modules/AllianceChat.lua", "Modules/GuildChat.lua" }) do
  pcall(dofile, ADDON .. "/" .. f)
end
dofile(ADDON .. "/UI/CommunityPanel.lua")
G.IsOfficer = function() return false end
G.IsFeatureEnabled = function() return true end
check(G.Journal ~= nil, "WoW: Forever has its journal")

local K = function(n) return G:GetPlayerKey(n) end
local function reset()
  G.db = { settings = { modules = {} }, members = {}, calendar = { events = {} }, digest = { enabled = true, lastSeen = 0, feedSeen = {} },
    firstSeen = {}, firstSeenSince = NOW - 60 * DAY, rosterLog = { events = {} }, lootHistory = {},
    milestones = { events = {} }, journal = { entries = {}, seq = 0, firsts = {} }, raidTracker = { sessions = {} } }
end
local function count(list, s)
  local n = 0
  for _, l in ipairs(list) do if tostring(l):find(s, 1, true) then n = n + 1 end end
  return n
end

-- ── Dedup: the cap, from two places, each person once ──────────────────
reset()
local DINGERS = { "Xama Tiltada", "Fat Beef", "Arvere Albus", "Chad Zul", "Chica Pombas" }
for i, n in ipairs(DINGERS) do
  table.insert(G.db.milestones.events, 1, { type = "ding", key = K(n), name = n, detail = "60", ts = NOW - i * 3600 })
  -- The journal's copy, its key as another client built it (another realm name: #97).
  G.db.journal.entries[#G.db.journal.entries + 1] = { id = n .. ":1", subjectKey = n .. "-Other Realm", at = NOW - i * 3600 + 20,
    type = "member.level60", data = {} }
end
table.sort(G.db.journal.entries, function(a, b) return a.at < b.at end)
local m = G.Digest:Collect(NOW - 7 * DAY)
check(#m.levels.dings == 5, "five people dinged, five in the model (" .. #m.levels.dings .. ")")
local lines = G.Digest:Build(NOW - 7 * DAY)
for _, n in ipairs(DINGERS) do
  check(count(lines, n .. " reached level 60!") == 1, n .. " is told once in the digest")
end
check(count(G.Milestones:GetDigestLines(NOW - 7 * DAY), "reached level 60!") == 5, "and once in Milestones' own lines")

-- ── Categorization ──────────────────────────────────────────────────────
reset()
for i = 1, 20 do G.db.firstSeen[K("Recruit" .. i)] = NOW - i * 600 end
local function log(action, target, ago, detail) local ev = G.db.rosterLog.events; ev[#ev + 1] = { action = action, target = target, timestamp = NOW - ago, detail = detail } end
log("leave", "Gone", 3 * DAY)
log("kick", "Ninja", 2 * DAY)
log("promote", "Kaelis", DAY, "Raider")
log("demote", "Brakk", DAY, "Social")
log("leave", "Old", 20 * DAY)
G.db.rosterLog.events[#G.db.rosterLog.events + 1] = { action = "promote", target = "Mine", timestamp = NOW - 60, loc = true }
G.db.lootHistory[1] = { itemLink = "|cffa335ee|Hitem:1|h[Nathrezim Mindblade]|h|r", quality = 4, player = K("Kaelis"), timestamp = NOW - 3600 }
G.db.raidTracker.sessions.s1 = { startTime = NOW - 2 * DAY, name = "Karazhan" }
local je = G.db.journal.entries
for i = 1, 14 do je[#je + 1] = { id = "l" .. i, subjectKey = K("Novice" .. i), at = NOW - 4000 - i, type = "member.level", data = { level = 50 } } end
je[#je + 1] = { id = "c1", subjectKey = K("Kaelis"), at = NOW - 5000, type = "dungeon.clear",
  data = { dungeonId = "slabs", dungeonName = "Shadow Labyrinth", runId = "r", bosses = 4, fullClear = true } }
je[#je + 1] = { id = "d1", subjectKey = K("Oruk"), at = NOW - 25 * DAY, type = "member.level60", data = {} }
table.sort(je, function(a, b) return a.at < b.at end)
m = G.Digest:Collect(NOW - 7 * DAY)
check(#m.members.joined == 20 and m.members.joined[1].name == "Recruit1", "who joined, newest first")
check(#m.members.left == 1 and m.members.left[1].name == "Gone" and #m.members.kick == 1, "who left and who was removed, in the week")
check(#m.members.promote == 1 and m.members.promote[1].detail == "Raider" and #m.members.demote == 1,
  "promoted and demoted, from the guild's log only (not this client's own diff line)")
check(#m.loot.items == 1 and m.loot.items[1].quality == 4, "the loot, with its quality")
check(#m.dungeons.raids == 1 and #m.dungeons.clears == 1 and m.dungeons.clears[1].name == "Shadow Labyrinth", "raids and clears")
check(#m.levels.levels == 1 and m.levels.levels[1].level == 50 and #m.levels.levels[1].names == 14, "level 50, fourteen members")
check(#m.levels.dings == 0, "a ding older than the period is not in it")
local groups = G.Digest:Groups(m)
local order = {}
for _, g in ipairs(groups) do order[#order + 1] = g.id end
check(table.concat(order, ",") == "members,levels,dungeons,loot", "the categories, in order: " .. table.concat(order, ","))
lines = G.Digest:Build(NOW - 7 * DAY)
check(lines.groups and #lines.groups == 4, "Build hands the popup the groups")
local at = {}
for i, l in ipairs(lines) do
  if l:find("new member", 1, true) then at.members = i end
  if l:find("level 50", 1, true) then at.levels = i end
  if l:find("raid session", 1, true) then at.dungeons = i end
  if l:find("looted", 1, true) then at.loot = i end
end
check(at.members and at.levels and at.dungeons and at.loot and at.members < at.levels and at.levels < at.dungeons and at.dungeons < at.loot,
  "the digest's lines, category by category")
local popup = G.Digest:Show(lines)
check(kit.shows(popup, "Levels and milestones") and kit.shows(popup, "Members"), "the popup heads each category")

-- ── The screen ──────────────────────────────────────────────────────────
local UI = G.UI
local SP = UI.SP
local function resolver(root)
  local rects = {}
  local function size(fr)
    local w, h = fr.w or 0, fr.h or 0
    if fr.kind == "FontString" then
      if w == 0 then w = fr:GetStringWidth() end
      if h == 0 then h = fr:GetStringHeight() end
    end
    return w, h
  end
  local resolve
  resolve = function(fr)
    if rects[fr] then return rects[fr] end
    if fr == root or not fr.parent then rects[fr] = { l = 0, t = 0, r = fr.w or 0, b = fr.h or 0 }; return rects[fr] end
    local w, h = size(fr)
    if #fr.points == 0 then
      local o = resolve(fr.parent)
      rects[fr] = { l = o.l, t = o.t, r = o.l + w, b = o.t + h }
      return rects[fr]
    end
    local L, R, T, B, CX, CY
    for _, p in ipairs(fr.points) do
      if p[1] == "ALL" then
        local o = resolve(p[2] or fr.parent)
        L, R, T, B = o.l, o.r, o.t, o.b
      else
        local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
        if type(p[2]) == "number" or p[2] == nil then x, y = p[2] or 0, p[3] or 0
        else rel, relPoint, x, y = p[2], p[3], p[4] or 0, p[5] or 0 end
        rel = rel or fr.parent
        relPoint = relPoint or point
        local o = resolve(rel)
        local ax = (relPoint:find("LEFT") and o.l) or (relPoint:find("RIGHT") and o.r) or (o.l + o.r) / 2
        local ay = (relPoint:find("TOP") and o.t) or (relPoint:find("BOTTOM") and o.b) or (o.t + o.b) / 2
        ax, ay = ax + x, ay - y
        if point:find("LEFT") then L = ax elseif point:find("RIGHT") then R = ax else CX = ax end
        if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
      end
    end
    if not L and not R then L = (CX or 0) - w / 2; R = L + w elseif not L then L = R - w elseif not R then R = L + w end
    if not T and not B then T = (CY or 0) - h / 2; B = T + h elseif not T then T = B - h elseif not B then B = T + h end
    rects[fr] = { l = L, t = T, r = R, b = B }
    return rects[fr]
  end
  return resolve
end

local panel
local function open(W)
  UIParent = kit.newFrame("Frame")
  panel = kit.newFrame("Frame", UIParent)
  local refresh = UI.BuildActivityScreen(panel)
  panel:SetSize(W - 40, 640)
  refresh()
  flush()
  return panel
end
local function shownCards()
  local out = {}
  for _, c in ipairs(panel.activityCards) do if c.frame.shown then out[#out + 1] = c end end
  return out
end
local function card(id)
  for _, c in ipairs(panel.activityCards) do if c.cat.id == id then return c.frame end end
end
local function inside(W)
  local resolve = resolver(UIParent)
  for _, c in ipairs(shownCards()) do
    local r = resolve(c.frame)
    local function walk(fr)
      for _, k in ipairs(fr.children) do
        if k.shown then
          local art = k.kind == "Texture" and fr == c.frame
          local blank = k.kind == "FontString" and (k.text or "") == ""
          if not art and not blank then
            local q = resolve(k)
            if (q.r - q.l) >= 1 or (q.b - q.t) >= 1 then
              check(q.l >= r.l - 2 and q.r <= r.r + 2 and q.t >= r.t - 2 and q.b <= r.b + 2,
                string.format("at %d, %s \"%s\" lies inside the %s card (%d,%d %dx%d in %dx%d)", W, k.kind,
                  tostring(k.text or (rawget(k, "label") and k.label.text) or ""), c.cat.id, q.l - r.l, q.t - r.t, q.r - q.l, q.b - q.t,
                  r.r - r.l, r.b - r.t))
            end
          end
          walk(k)
        end
      end
    end
    walk(c.frame)
  end
end

open(1250)
check(panel.activityState.period.id == "week", "the screen opens on the last 7 days")
local ids = {}
for _, c in ipairs(shownCards()) do ids[#ids + 1] = c.cat.id end
check(table.concat(ids, ",") == "members,levels,dungeons,loot", "a card per category with something to say: " .. table.concat(ids, ","))
check(not panel.activityEmpty.shown, "and no empty state")
local resolve = resolver(UIParent)
local a, b = resolve(card("members")), resolve(card("levels"))
check(math.abs(a.t - b.t) < 1 and b.l > a.r, "two columns from SP.TWO_COLS")
inside(1250)
check(kit.shows(card("members"), "Joined") and kit.shows(card("members"), "Promoted") and kit.shows(card("members"), "Kaelis"),
  "members: counts and names")
check(kit.shows(card("levels"), "Level 50 — 14 member(s)"), "a milestone, grouped")
check(kit.shows(card("loot"), "Nathrezim Mindblade") and not kit.shows(card("loot"), "|Hitem"), "loot as the item's name, never its code")
-- A long list: twelve names and "and 8 more", which opens the rest.
local more = kit.button(card("members"), "and 8 more")
check(more ~= nil and not kit.shows(card("members"), "Recruit20"), "twenty joined: twelve named and \"and 8 more\"")
more.scripts.OnClick(more)
flush()
check(kit.shows(card("members"), "Recruit20") and kit.button(card("members"), "Show less") ~= nil, "which opens all of them")
inside(1250)

open(800)
resolve = resolver(UIParent)
a, b = resolve(card("members")), resolve(card("levels"))
check(b.t >= a.b and math.abs(a.l - b.l) < 1, "one column under SP.TWO_COLS")
inside(800)

-- ── The period ──────────────────────────────────────────────────────────
local function pick(label)
  local btn = kit.button(panel, label)
  check(btn ~= nil, "the " .. label .. " pill")
  btn.scripts.OnClick(btn)
  flush()
end
pick("30 days")
check(kit.shows(card("levels"), "Oruk") and kit.shows(card("members"), "Old"), "30 days: the ding and the leave of three weeks ago")
pick("Today")
check(not kit.shows(card("dungeons"), "Karazhan") and not kit.shows(card("members"), "Gone"), "today: not what happened days ago")
check(card("loot").shown and kit.shows(card("dungeons"), "Shadow Labyrinth"), "but what happened this morning")
pick("7 days")
check(kit.shows(card("dungeons"), "Karazhan") and not kit.shows(card("levels"), "Oruk"), "back to the week")

-- ── Empty states ────────────────────────────────────────────────────────
reset()
open(1250)
check(#shownCards() == 0, "nothing happened: no card")
check(panel.activityEmpty.shown and kit.shows(panel.activityEmpty, "Nothing new in the last 7 days."), "the centred empty state says so")
pick("Today")
check(kit.shows(panel.activityEmpty, "Nothing new today."), "for the period picked")
reset()
G.db.lootHistory[1] = { itemName = "Bread", quality = 1, player = K("Ana"), timestamp = NOW - 60 }
open(1250)
ids = {}
for _, c in ipairs(shownCards()) do ids[#ids + 1] = c.cat.id end
check(table.concat(ids, ",") == "loot" and not panel.activityEmpty.shown, "only the loot: only its card")
inside(1250)
check(#(G.State.errors or {}) == 0, "no error recorded: " .. tostring((G.State.errors or {})[1] and G.State.errors[1].msg))

print(("activity-categories: %d checks passed"):format(kit.count()))
