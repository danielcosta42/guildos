-- The Groups tab (issue #341): the real UI/GroupsPanel.lua built on the real helpers, under a
-- stubbed client, and driven by its own buttons.
--
-- Every view paints with nothing and with something in it; a tile opens the composer on its
-- activity; publishing lists me or my group; a card's role button asks for a spot; the queue's
-- buttons invite and decline; and a repaint reuses its rows instead of creating them again.
--
--   luajit -e 'ADDON="."' tools/groups-panel.lua
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

-- ── A frame that keeps what the panel reads back, and takes anything else ──
local created = 0
local Frame = {}
local VERBS = { "Set", "Get", "Is", "Clear", "Enable", "Register", "Unregister", "Raise", "Lower", "Start", "Stop", "Add" }
local function newFrame(kind, parent)
  created = created + 1
  local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true, w = 0, h = 0,
                           enabled = true, alpha = 1 }, { __index = function(_, k)
    -- A method the stub does not keep does nothing; a field nobody set is nil, as on a real frame.
    if Frame[k] then return Frame[k] end
    if type(k) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
      if k:find("^" .. verb) then return function() end end
    end
    return nil
  end })
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  return f
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:GetParent() return self.parent end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
  local f = self
  while f do
    if not f.shown then return false end
    f = f.parent
  end
  return true
end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text or "" end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont() return true end
function Frame:GetFrameLevel() return 1 end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:IsEnabled() return self.enabled end
function Frame:IsMouseOver() return false end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetScrollChild(c) self.scrollChild = c end
function Frame:SetBackdropBorderColor(r, g, b) self.border = { r, g, b } end
-- What the activity cards (#373) are read back by: where a frame is, which art a texture holds.
function Frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAtlas(name) self.atlas, self.texture = name, nil end
function Frame:SetTexCoord(...) self.coords = { ... } end
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:SetDesaturated(v) self.desaturated = v and true or false end

UIParent = newFrame("Frame")
function CreateFrame(kind, _, parent) return newFrame(kind, parent) end
GameTooltip = newFrame("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function UnitName(unit) if unit == "player" then return "Ana" end end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 70 end
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return 5000 end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
C_Timer = { After = function() end, NewTicker = function() end }
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function SendChatMessage() end
local invited, tells = {}, {}
function InviteUnit(name) invited[#invited + 1] = name end
function ChatFrame_SendTell(name) tells[#tells + 1] = name end
-- The guild: everybody online, so every listing shows. The third field is the level (#373).
local ROSTER = { { "Bea-Realm", "PRIEST" }, { "Cid-Realm", "PRIEST" }, { "Dan-Realm", "PRIEST", 68 },
                 { "Ana-Realm", "PRIEST" }, { "Eve-Realm", "MAGE", 69 }, { "Fay-Realm", "PRIEST", 62 } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local m = ROSTER[i]
  if m then return m[1], "Rank", 1, m[3] or 70, "Priest", "Zone", "", "", true, 0, m[2] end
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
dofile(ADDON .. "/Core/Utils.lua")
GuildOS.Style:Resolve()
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/Data/GroupActivities.lua")

local passThrough = { Serialize = function(_, t) return t end, Deserialize = function(_, d) return true, d end }
LibStub = function() return passThrough end
dofile(ADDON .. "/Modules/LFGBoard.lua")
dofile(ADDON .. "/Modules/Groups.lua")
dofile(ADDON .. "/UI/GroupsPanel.lua")

local wire = {}
GuildOS.CommSystem = {
  MSG_TYPES = { LFG = "LG", LFG_GROUP = "GF", LFG_JOIN = "GJ" },
  SendMessage = function(_, kind, payload, target) wire[#wire + 1] = { kind = kind, p = payload, to = target } end,
}
GuildOS.Print = function() end
GuildOS.Compat.After = function() end
GuildOS.RosterKey = function(_, name) return GuildOS:GetPlayerKey(name:match("^([^-]+)"), "Realm") end
GuildOS.SafeCall = function(_, fn, ...) return fn(...) end   -- an error in a paint fails the test, loudly

GuildOS.db = {}
local Board, Groups, UI = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.UI
Board:Initialize()
Groups:Initialize()
local function key(name) return GuildOS:GetPlayerKey(name, "Realm") end

-- ── Reading the panel ───────────────────────────────────────────────────
local function walk(f, visit)
  visit(f)
  for _, c in ipairs(f.children) do walk(c, visit) end
end
-- Every visible button with this label, under `root`.
local function buttons(root, label)
  local out = {}
  walk(root, function(f)
    if f.kind == "Button" and f:IsVisible() and f.label and f.label.text == label then out[#out + 1] = f end
  end)
  return out
end
local function click(root, label, nth)
  local b = buttons(root, label)[nth or 1]
  check(b ~= nil and b.scripts.OnClick ~= nil, "there is a button \"" .. label .. "\" to click")
  b.scripts.OnClick(b)
  return b
end
-- Every visible text under `root`, as one string.
local function texts(root)
  local out = {}
  walk(root, function(f)
    if f.kind == "FontString" and f:IsVisible() and f.text and f.text ~= "" then out[#out + 1] = f.text end
  end)
  return table.concat(out, "\n")
end
local function shows(root, text) return texts(root):find(text, 1, true) ~= nil end

-- ── The tab ─────────────────────────────────────────────────────────────
local panel = newFrame("Frame", UIParent)
panel:SetSize(900, 600)
GuildOS:CreateGroupsPanel(panel)
check(type(panel.SelectSub) == "function", "the tab takes a deep link")
-- The scroll area is as wide as the panel leaves it; the stub has no layout engine.
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(860, 500) end end)
panel.scripts.OnShow(panel)

check(shows(panel, "Groups being formed") and shows(panel, "Looking for a group"), "Active shows its two lists")
check(shows(panel, "No group is being formed right now. Pick an activity to start one."), "with nothing forming, it says so")
check(shows(panel, "Nobody is available right now. Be the first!"), "and with nobody looking")

for _, sub in ipairs({ "dungeon", "raid", "other" }) do
  panel.SelectSub(sub)
  check(panel.activeSub == sub, sub .. " opens")
end
panel.SelectSub("dungeon")
check(shows(panel, "The Steamvault") and shows(panel, "Heroic dungeon"), "Dungeons shows this client's dungeons")
panel.SelectSub("raid")
check(shows(panel, "Karazhan") and not shows(panel, "The Steamvault"), "Raids shows the raids, and only them")
panel.SelectSub("nonsense")
check(panel.activeSub == "active", "a sub-tab that is none opens Active")

-- A tile opens the composer on its activity
local function tileOf(name)
  local found
  walk(panel, function(f)
    if f.kind == "Button" and f:IsVisible() and f.title == name then found = f end
  end)
  return found
end
panel.SelectSub("raid")
local kara = tileOf("Karazhan")
check(kara ~= nil and kara.alpha == 1, "a raid of my level is lit")
panel.SelectSub("dungeon")
local ramparts = tileOf("Hellfire Ramparts")
check(ramparts ~= nil and ramparts.alpha < 1, "a dungeon I outgrew is dimmed")
panel.SelectSub("raid")
kara = tileOf("Karazhan")
kara.scripts.OnEnter(kara)
kara.scripts.OnLeave(kara)
kara.scripts.OnClick(kara)
local composer
walk(UIParent, function(f) if f.Open and f.SetMode then composer = f end end)
check(composer ~= nil and composer:IsShown(), "clicking a tile opens the composer")
check(shows(composer, "Karazhan"), "on that tile's activity")

-- I am looking
composer:SetMode("seek")
local chips = {}
walk(composer, function(f) if f.kind == "Button" and f.letter and f:IsVisible() and f.scripts.OnClick then chips[f.letter] = f end end)
check(chips.T and chips.H and chips.D, "the composer offers the three roles")
chips.H.scripts.OnClick(chips.H)
click(composer, "60m")
click(composer, "Publish")
local mine = Board:Mine()
check(mine ~= nil and mine.roles == "H" and mine.acts[1] == "karazhan" and mine.ttl == 3600, "publishing lists me, with my role, the activity and the duration")
check(not composer:IsShown(), "and closes the composer")
check(wire[#wire].kind == "LG" and wire[#wire].p.roles == "H", "the guild hears it")
panel.SelectSub("active")
check(shows(panel, "(you)") and shows(panel, "Karazhan") and shows(panel, "Healer"), "my listing is on the board, marked as mine")
check(#buttons(panel, "Stop looking") == 1, "and the button now takes it down")

-- A second tile adds to what I am looking for
panel.SelectSub("dungeon")
local vault = tileOf("The Steamvault")
vault.scripts.OnClick(vault)
check(composer.mode == "seek" and #composer.acts == 2, "another tile adds its activity to my listing")
check(#buttons(composer, "Update") == 1 and #buttons(composer, "Take down") == 1, "a listing I have is updated or taken down")
click(composer, "Only this one")
check(#composer.acts == 1 and composer.acts[1] == "steamvault", "or replaces the others")
click(composer, "Take down")
check(Board:Mine() == nil, "taking it down from the composer delists me")

-- Forming a group
vault.scripts.OnClick(vault)
composer:SetMode("group")
check(shows(composer, "OPEN SPOTS"), "the group mode asks for the open spots")
local before = Groups:OpenSpots(composer.need)
composer:Step("D", 1)
check(Groups:OpenSpots(composer.need) == before, "the spots never pass the room a party has")
composer:Step("T", -1)
composer:Step("T", -1)
check(composer.need.T == 0, "nor go below none")
click(composer, "Publish")
local group = Groups:Mine()
check(group ~= nil and group.act == "steamvault" and group.need.T == 0 and group.need.D == 3, "publishing lists my group with the spots chosen")
check(group.need.H == 0, "and no spot is offered for the one role I play myself")
panel.SelectSub("active")
check(shows(panel, "Your group: The Steamvault"), "my group heads the Active view")
check(shows(panel, "Nobody asked for a spot yet. Guildmates see your group here and in the tiles."), "with an empty queue said as such")
check(#buttons(panel, "My group") == 1, "and the button now opens it")

-- A group with no spot is refused in the composer, with the reason
click(panel, "Change")
check(composer:IsShown() and composer.mode == "group" and composer.act == "steamvault", "Change opens the composer on my group")
for _ = 1, 6 do composer:Step("H", -1); composer:Step("D", -1) end
click(composer, "Update")
check(composer:IsShown() and shows(composer, "A group needs at least one open spot."), "a group with no open spot stays in the composer, with the reason")
composer:Hide()

-- The queue
Groups:HandleJoin("Bea-Realm", { role = "D" }, "WHISPER")
check(shows(panel, "Asking for a spot") and shows(panel, "Bea"), "a request shows in the queue")
click(panel, "Invite")
check(invited[1] == "Bea-Realm" and shows(panel, "invited"), "Invite calls the game's invite and marks the row")
click(panel, "Decline")
check(#Groups:Requests() == 0 and wire[#wire].to == "Bea-Realm" and wire[#wire].p.decline == true, "Decline tells the asker and clears the row")
click(panel, "Take down")
check(Groups:Mine() == nil, "Take down removes my group")

-- Somebody else's group, and who is looking
Groups:HandleGroup("Cid-Realm", { act = "karazhan", need = { T = 1, D = 2 }, note = "first night", ttl = 3600 }, "GUILD")
Board:HandleEntry("Dan-Realm", { roles = "TD", acts = { "karazhan" }, note = "until 23h", ttl = 3600 })
check(shows(panel, "first night") and shows(panel, "missing 1 Tank, 2 DPS"), "a group shows its note and what it is missing")
check(#buttons(panel, "Tank") == 1 and #buttons(panel, "DPS") == 1 and #buttons(panel, "Healer") == 0,
  "and offers the roles it has a spot for, and no other")
check(shows(panel, "Karazhan: until 23h") and shows(panel, "Tank, DPS"), "a player looking shows the activities, the note and the roles")
click(panel, "Whisper")
check(tells[1] == "Cid", "Whisper opens a whisper to the leader")
click(panel, "Invite")
check(invited[#invited] == "Dan", "Invite on a player looking invites them")
click(panel, "Tank")
check(wire[#wire].kind == "GJ" and wire[#wire].to == "Cid-Realm" and wire[#wire].p.role == "T", "a role button asks the leader for that spot")
check(shows(panel, "asked as Tank") and #buttons(panel, "Tank") == 0, "and the card then says what I asked")
click(panel, "Take it back")
check(Groups:Asked(key("Cid")) == nil and #buttons(panel, "Tank") == 1, "taking it back offers the roles again")

-- The tiles count what is there
panel.SelectSub("raid")
check(shows(panel, "1 forming") and shows(panel, "1 looking"), "a tile counts its groups and its players")

-- The roles I play
local play = {}
walk(panel, function(f) if f.kind == "Button" and f.letter and f:IsVisible() and f.scripts.OnClick then play[f.letter] = f end end)
check(Board:Pref("roles") == "H" and play.H.on and not play.T.on, "the role I listed myself in is the one I play")
play.T.scripts.OnClick(play.T)
play.D.scripts.OnClick(play.D)
check(Board:Pref("roles") == "THD" and play.T.on and play.D.on and play.H.on, "the roles I play are remembered and lit")
play.T.scripts.OnClick(play.T)
check(Board:Pref("roles") == "HD" and not play.T.on, "and a second click takes one back")

-- ── Activity cards (#373) ───────────────────────────────────────────────
local function visible(root, pred)
  local out = {}
  walk(root, function(f) if f:IsVisible() and pred(f) then out[#out + 1] = f end end)
  return out
end
local function cards(root) return visible(root, function(f) return f.slots ~= nil and f.lead ~= nil end) end
local function cardOf(root, title)
  for _, c in ipairs(cards(root)) do if c.title.text == title then return c end end
end
-- A card's seats as drawn: how many are taken, and the roles of the open ones in order.
local function seatsOf(card)
  local filled, open = 0, {}
  for _, s in ipairs(card.slots) do
    if s:IsShown() then
      if s.filled then filled = filled + 1 else open[#open + 1] = s.role end
    end
  end
  return filled, table.concat(open)
end
local function seekerRows(root) return visible(root, function(f) return f.roleIcons ~= nil end) end
local function rowOf(rows, name)
  for _, r in ipairs(rows) do if r.name.text:find(name, 1, true) then return r end end
end
local function chipsOf(root)
  local out = {}
  walk(root, function(f) if f.kind == "Button" and f.letter and f:IsVisible() and f.scripts.OnClick then out[f.letter] = f end end)
  return out
end

-- This client has no role art: every role keeps its letter.
for _, letter in ipairs({ "T", "H", "D" }) do
  check(play[letter].label.text == letter and not play[letter].icon.shown, "with no role art the " .. letter .. " toggle keeps its letter")
end

-- One card per group being formed, its seats as its listing counts them
Groups:HandleGroup("Eve-Realm", { act = "steamvault", need = { H = 1 }, n = 3, ttl = 3600 }, "GUILD")
Board:HandleEntry("Fay-Realm", { roles = "H", acts = { "steamvault" }, ttl = 3600 })
panel.SelectSub("active")
check(#cards(panel) == 2, "one card per group being formed (" .. #cards(panel) .. ")")
local kc, sc = cardOf(panel, "Karazhan"), cardOf(panel, "The Steamvault")
check(kc ~= nil and sc ~= nil, "each card names its activity")
local taken, open = seatsOf(kc)
check(taken == 1 and open == "TDD", "a card's seats: its leader, then one per open spot by role (" .. taken .. " " .. open .. ")")
taken, open = seatsOf(sc)
check(taken == 3 and open == "H", "and another group's seats are its own (" .. taken .. " " .. open .. ")")
check(kc.range.text == "70" and sc.range.text == "68\226\128\14770", "a card shows its activity's level range")
check(kc.lead.text == "led by |cff" .. GuildOS:GetClassColorHex("PRIEST") .. "Cid|r", "and who leads it, in their class colour")
check(kc.when.text:find("1/10", 1, true) and kc.when.text:find("60m", 1, true), "how full it is and for how long")
check(shows(kc, "missing 1 Tank, 2 DPS") and shows(sc, "missing 1 Healer"), "and what it is missing")
check(#buttons(sc, "Healer") == 1 and #buttons(sc, "Tank") == 0 and #buttons(sc, "Whisper") == 1,
  "a card keeps its Join action for the roles it has open")
for _, s in ipairs(kc.slots) do
  if s:IsShown() and not s.filled then check(s.mark.text == s.role, "with no role art an open seat shows its letter") end
end

-- One row per player looking
local rows = seekerRows(panel)
check(#rows == 2, "one row per player looking (" .. #rows .. ")")
local dan, fay = rowOf(rows, "Dan"), rowOf(rows, "Fay")
check(dan.level.text == "Lv 68" and fay.level.text == "Lv 62", "a row says the player's level, from the roster")
check(dan.roles.text == "Tank, DPS" and fay.roles.text == "Healer", "with no role art the roles are spelled out")
check(dan.what.text == "Karazhan: until 23h" and fay.what.text == "The Steamvault", "and what they want")
check(#buttons(dan, "Invite") == 1 and not dan.class.shown, "the row keeps its Invite, and shows no class icon the client lacks")

-- Dungeons opens on the tiles of my level
local function yOf(f) return -f.points[1][3] end
local function sectionTiles(root, title)
  local heads, tiles = {}, {}
  walk(root, function(f)
    if f:IsVisible() and type(f.title) == "table" and f.title.rule ~= nil then heads[#heads + 1] = f end
    if f:IsVisible() and f.kind == "Button" and type(f.title) == "string" then tiles[#tiles + 1] = f end
  end)
  table.sort(heads, function(a, b) return yOf(a) < yOf(b) end)
  local top, bottom, first
  for i, h in ipairs(heads) do
    if h.title.text == title then
      top, bottom, first = yOf(h), heads[i + 1] and yOf(heads[i + 1]) or math.huge, i == 1
    end
  end
  if not top then return nil end
  local out = {}
  for _, t in ipairs(tiles) do
    if yOf(t) > top and yOf(t) < bottom then out[#out + 1] = t end
  end
  return out, first
end
local function inRange(level)
  local want, seen = {}, {}
  for _, s in ipairs(GuildOS.GroupActivities:Sections("dungeon")) do
    for _, it in ipairs(s.items) do
      if it.min and level >= it.min and level <= it.max and not seen[it.id] then
        seen[it.id] = true
        want[#want + 1] = Board:ActivityName(it.id)
      end
    end
  end
  table.sort(want)
  return want
end
local function names(tiles)
  local out = {}
  for _, t in ipairs(tiles) do out[#out + 1] = t.title end
  table.sort(out)
  return out
end
for _, level in ipairs({ 70, 60 }) do
  UnitLevel = function() return level end
  panel.SelectSub("dungeon")
  local got, first = sectionTiles(panel, "For your level")
  local want = inRange(level)
  check(#want > 0 and got ~= nil and first, "at level " .. level .. " Dungeons opens on For your level")
  check(table.concat(names(got), ",") == table.concat(want, ","),
    "holding exactly the tiles whose range has level " .. level .. ": " .. table.concat(names(got), ","))
  for _, t in ipairs(got) do check(t.alpha == 1, "every tile for my level is lit") end
end
UnitLevel = function() return 70 end
panel.SelectSub("dungeon")
local vaultHere
for _, t in ipairs((sectionTiles(panel, "For your level"))) do if t.title == "The Steamvault" then vaultHere = t end end
check(vaultHere.groups.text == "1 forming" and vaultHere.seekers.text == "1 looking", "a tile for my level says who wants to go")
vaultHere.scripts.OnClick(vaultHere)
check(composer:IsShown() and composer.picked == "steamvault", "and opens the composer on its activity, as every tile")
composer:Hide()
UnitLevel = function() return 5 end
panel.SelectSub("dungeon")
check(not shows(panel, "For your level"), "a level no dungeon has shows no For your level")
UnitLevel = function() return 70 end
panel.SelectSub("raid")
check(not shows(panel, "For your level"), "and Raids has none")

-- A repaint reuses what it drew
panel.SelectSub("active")
local settled = created
for _ = 1, 5 do
  panel.SelectSub("dungeon")
  panel.SelectSub("raid")
  panel.SelectSub("active")
end
check(created == settled, "repainting creates no frame it already has (" .. (created - settled) .. " new)")

-- The board's refresh lands here, and a hidden tab does no work
check(Board.uiRefresh ~= nil, "the modules' refresh is the panel's paint")
panel:Hide()
Board:HandleEntry("Bea-Realm", { roles = "H", ttl = 3600 })
panel:Show()
panel.scripts.OnShow(panel)
check(shows(panel, "Bea"), "what arrived while the tab was closed is there when it opens")

-- ── The game's role icons (#373) ────────────────────────────────────────
-- The client's art is asked once a load, so each client below loads the panel again.
local function build()
  local p = newFrame("Frame", UIParent)
  p:SetSize(900, 600)
  GuildOS:CreateGroupsPanel(p)
  walk(p, function(f) if f.kind == "ScrollFrame" then f:SetSize(860, 500) end end)
  p.scripts.OnShow(p)
  return p
end
local function near(a, b)
  if not a or #a ~= #b then return false end
  for i = 1, #b do if math.abs(a[i] - b[i]) > 1e-6 then return false end end
  return true
end
-- A fresh panel makes each tab's frames on its first visit: visit them all once, then count.
local function settles(p, what)
  p.SelectSub("dungeon")
  p.SelectSub("raid")
  p.SelectSub("active")
  local before = created
  for _ = 1, 3 do
    p.SelectSub("dungeon")
    p.SelectSub("raid")
    p.SelectSub("active")
  end
  check(created == before, what .. ": repainting creates no frame it already has (" .. (created - before) .. " new)")
end

-- A client with the group finder's atlases (and every file, so the activity art draws too)
local ATLAS = { T = "groupfinder-icon-role-large-tank", H = "groupfinder-icon-role-large-heal", D = "groupfinder-icon-role-large-dps" }
C_Texture = { GetAtlasInfo = function(name)
  for _, a in pairs(ATLAS) do if a == name then return { width = 32, height = 32 } end end
end }
CLASS_ICON_TCOORDS = { PRIEST = { 0.5, 0.75, 0.25, 0.5 }, MAGE = { 0.25, 0.5, 0, 0.25 } }
function GetFileIDFromPath() return 1 end
for _, it in pairs(GuildOS.GroupActivities.byId) do it.artOk = nil end
dofile(ADDON .. "/UI/GroupsPanel.lua")
panel:Hide()
local iconPanel = build()

local ic = chipsOf(iconPanel)
for letter, atlas in pairs(ATLAS) do
  check(ic[letter].icon.shown and ic[letter].icon.atlas == atlas and ic[letter].label.text == "",
    "with the atlases a role toggle is the game's icon, not its letter: " .. atlas)
end
check(ic.H.__selected and ic.D.__selected and not ic.T.__selected, "the roles I play are marked selected")
check(ic.T.icon.desaturated and not ic.H.icon.desaturated, "and a role I do not play is greyed")
ic.T.scripts.OnClick(ic.T)
check(Board:Pref("roles") == "THD" and ic.T.__selected and not ic.T.icon.desaturated, "a click on an icon toggles its role")
ic.T.scripts.OnClick(ic.T)

local ikc = cardOf(iconPanel, "Karazhan")
check(ikc.art.shown and ikc.art.texture == "Interface\\LFGFrame\\UI-LFG-BACKGROUND-Karazhan"
  and near(ikc.art.coords, { 0, 1, 0.08, 0.72 }), "a card's band is its activity's art, cut as the tiles cut it")
taken, open = seatsOf(ikc)
check(taken == 1 and open == "TDD", "the icons change no seat")
for _, s in ipairs(ikc.slots) do
  if s:IsShown() and s.filled then
    check(not s.icon.shown and s.mark.text == "", "a taken seat names no role: the listing does not say whose")
  elseif s:IsShown() then
    check(s.icon.shown and s.icon.atlas == ATLAS[s.role] and s.mark.text == "", "an open seat is its role's icon")
  end
end
rows = seekerRows(iconPanel)
check(#rows == 3, "one row per player looking (" .. #rows .. ")")
dan = rowOf(rows, "Dan")
local shownIcons = {}
for _, t in ipairs(dan.roleIcons) do if t.shown then shownIcons[#shownIcons + 1] = t.atlas end end
check(#shownIcons == 2 and shownIcons[1] == ATLAS.T and shownIcons[2] == ATLAS.D and dan.roles.text == "",
  "a row's roles are the game's icons")
check(dan.class.shown and dan.class.texture:find("UI-CharacterCreate-Classes", 1, true)
  and near(dan.class.coords, CLASS_ICON_TCOORDS.PRIEST), "and its class is the game's class icon")
local bea = rowOf(rows, "Bea")
check(bea.roleIcons[1].shown and not bea.roleIcons[2].shown, "a player with one role shows one icon")
settles(iconPanel, "with icons")

-- A client with only the LFG frame's file: Blizzard's own cut of it (GetTexCoordsForRole)
C_Texture = nil
function GetFileIDFromPath(path) if path == "Interface\\LFGFrame\\UI-LFG-ICON-ROLES" then return 1 end end
dofile(ADDON .. "/UI/GroupsPanel.lua")
iconPanel:Hide()
local filePanel = build()
local fc, cell = chipsOf(filePanel), 67 / 256
check(fc.T.icon.texture == "Interface\\LFGFrame\\UI-LFG-ICON-ROLES" and near(fc.T.icon.coords, { 0, cell, cell, 2 * cell })
  and near(fc.H.icon.coords, { cell, 2 * cell, 0, cell }) and near(fc.D.icon.coords, { cell, 2 * cell, cell, 2 * cell }),
  "without the atlases the role icons come from the LFG frame's file")
check(fc.T.label.text == "" and fc.T.icon.shown, "and still stand in for the letter")
settles(filePanel, "with the file")

-- The WoW: Forever style: the same screen on its palette
C_Texture = { GetAtlasInfo = function() return { width = 32, height = 32 } end }
GuildOSDB = { style = "forever" }
check(GuildOS.Style:Resolve() == "forever", "the Forever style resolves where the client has its art")
dofile(ADDON .. "/UI/GroupsPanel.lua")
filePanel:Hide()
local foreverPanel = build()
check(#cards(foreverPanel) == 2 and #seekerRows(foreverPanel) == 3, "in the Forever style the cards and rows are the same")
check(chipsOf(foreverPanel).T.icon.atlas == ATLAS.T, "with the Forever client's role atlases")
foreverPanel.SelectSub("dungeon")
check(sectionTiles(foreverPanel, "For your level") ~= nil, "and Dungeons opens on For your level")
settles(foreverPanel, "in the Forever style")

print(checks .. " checks ok")
