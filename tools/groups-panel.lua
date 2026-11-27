-- The Groups tab (issue #341): the real UI/GroupsPanel.lua built on the real helpers, under a
-- stubbed client, and driven by its own buttons.
--
-- The board paints with nothing and with something in it; the forms open in place, with no window of
-- their own (#449, option E): Form a group turns the left column into a grid of activity cards that
-- count who is forming and looking, a card picked moves to the spots and times (Change goes back),
-- the players' list lights who would fit, and Publish hands the module the activity, spots, note,
-- duration, start, chat line and auto-invite; I am looking picks several cards in the right column;
-- Esc and Cancel go back. A card's role button asks for a spot; the queue's buttons invite and decline;
-- the filters are pills; a repaint reuses its rows instead of creating them again; the lists (and the
-- forms) sit side by side from 900px and one under the other below; and everything drawn on a card
-- lies inside it (#449).
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
-- UI/Forms.lua moves a field into its row's holder: the frame changes parent, as on the client.
function Frame:SetParent(p)
  if p == self.parent then return end
  local old = self.parent and self.parent.children
  if old then for i, c in ipairs(old) do if c == self then table.remove(old, i) break end end end
  self.parent = p
  if p and p.children then p.children[#p.children + 1] = self end
end
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
function Frame:HasFocus() return false end
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
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/Forms.lua")
dofile(ADDON .. "/Data/GroupActivities.lua")

local passThrough = { Serialize = function(_, t) return t end, Deserialize = function(_, d) return true, d end }
LibStub = function() return passThrough end
dofile(ADDON .. "/Modules/LFGBoard.lua")
-- My quest log (#450), in the modern shape: a solo quest first in the log, two group ones after it.
local QUEST_LOG = {
  { title = "Hellfire Peninsula", isHeader = true },
  { title = "Fel Orc Scavengers", questID = 10482, level = 61 },
  { title = "Wanted: Worg Master Kruush", questID = 10809, level = 62 },
  { title = "Zangarmarsh", isHeader = true },
  { title = "Lost in Action", questID = 9738, level = 64 },
  { title = "The Dying Balance", questID = 9895, level = 63 },
}
local QUEST_TAGS = { [10809] = { tagID = 1, tagName = "Group", isElite = true }, [9738] = { tagID = 81, tagName = "Dungeon" } }
C_QuestLog = {
  GetNumQuestLogEntries = function() return #QUEST_LOG end,
  GetInfo = function(i) return QUEST_LOG[i] end,
  GetQuestTagInfo = function(id) return QUEST_TAGS[id] end,
  GetSuggestedGroupSize = function(id) return id == 10809 and 3 or 0 end,
}
dofile(ADDON .. "/Modules/GroupQuests.lua")
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

-- ── Where things are: every frame's box, from its anchors, as the client lays it out ──
local function rectOf(f, memo)
  if memo[f] then return memo[f] end
  memo[f] = { l = 0, t = 0, r = 0, b = 0 }   -- a cycle reads as nothing
  local w = (f.w or 0) > 0 and f.w or (f.kind == "FontString" and f:GetStringWidth() or 0)
  local h = (f.h or 0) > 0 and f.h or (f.kind == "FontString" and f:GetStringHeight() or 0)
  local pts = f.points or {}
  local r
  if #pts == 0 then
    local base = f.scrollOwner and rectOf(f.scrollOwner, memo) or (f.parent and rectOf(f.parent, memo)) or { l = 0, t = 0 }
    r = { l = base.l, t = base.t, r = base.l + w, b = base.t + h }
  else
    local L, R, T, B, CX, CY
    for _, p in ipairs(pts) do
      local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
      if type(p[2]) == "table" then
        rel = p[2]
        if type(p[3]) == "string" then relPoint, x, y = p[3], p[4] or 0, p[5] or 0 else x, y = p[3] or 0, p[4] or 0 end
      else
        x, y = p[2] or 0, p[3] or 0
      end
      rel = rel or f.parent
      relPoint = relPoint or point
      local o = rel and rectOf(rel, memo) or { l = 0, t = 0, r = 0, b = 0 }
      local ax = (relPoint:find("LEFT") and o.l) or (relPoint:find("RIGHT") and o.r) or (o.l + o.r) / 2
      local ay = (relPoint:find("TOP") and o.t) or (relPoint:find("BOTTOM") and o.b) or (o.t + o.b) / 2
      ax, ay = ax + x, ay - y
      if point:find("LEFT") then L = ax elseif point:find("RIGHT") then R = ax else CX = ax end
      if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
    end
    if not L and not R then L = (CX or 0) - w / 2; R = L + w elseif not L then L = R - w elseif not R then R = L + w end
    if not T and not B then T = (CY or 0) - h / 2; B = T + h elseif not T then T = B - h elseif not B then B = T + h end
    r = { l = L, t = T, r = R, b = B }
  end
  memo[f] = r
  return r
end
-- Every visible text and frame drawn on a card lies inside the card (#449): nothing runs past its edge,
-- nothing touches it either (a card's content is CARD_PAD in, its decorations are textures and skipped).
local function insideCards(root, what)
  walk(root, function(f) if f.scrollChild then f.scrollChild.scrollOwner = f end end)
  local memo, n = {}, 0
  walk(root, function(card)
    if not (card.isCard and card:IsVisible()) then return end
    local box = rectOf(card, memo)
    walk(card, function(d)
      if d == card or d.kind == "Texture" or not d:IsVisible() then return end
      if d.kind == "FontString" and (d.text or "") == "" then return end
      local r = rectOf(d, memo)
      n = n + 1
      -- Inside a scroll frame of the card's own (a form's grid) a row may run past the bottom: the frame
      -- clips it. Across, it still stays inside.
      local clipped = false
      local x = d.parent
      while x and x ~= card do
        if x.kind == "ScrollFrame" then clipped = true end
        x = x.parent
      end
      local inside = r.l >= box.l - 0.5 and r.r <= box.r + 0.5
        and (clipped or (r.t >= box.t - 0.5 and r.b <= box.b + 0.5))
      check(inside, what .. ": " .. tostring(d.kind) .. " \"" .. tostring(d.text or (d.label and d.label.text) or "")
        .. "\" lies inside its card " .. string.format("(%d,%d,%d,%d in %d,%d,%d,%d)", r.l, r.t, r.r, r.b, box.l, box.t, box.r, box.b))
    end)
  end)
  return n
end

local function cardTitled(root, title)
  local found
  walk(root, function(f)
    if f.isCard and f:IsVisible() and f.title and (f.title.text or ""):find(title, 1, true) == 1 then found = f end
  end)
  return found
end
local function picker(root)
  local found
  walk(root, function(f) if f.isActivityPicker and f:IsVisible() then found = f end end)
  return found
end
local function optionTexts(dd)
  local out = {}
  for _, o in ipairs(dd.options) do out[#out + 1] = o.text end
  return table.concat(out, "\n")
end

check(shows(panel, "Groups being formed") and shows(panel, "Looking for a group"), "Active shows its two lists")
check(shows(panel, "No group is being formed right now. Pick an activity to start one."), "with nothing forming, it says so")
check(shows(panel, "Nobody is available right now. Be the first!"), "and with nobody looking")
local gc, sk = cardTitled(panel, "Groups being formed"), cardTitled(panel, "Looking for a group")
check(gc and sk and #buttons(gc, "+ Form a group") == 1 and #buttons(sk, "I am looking") == 1,
  "an empty list is a block with the action that fills it (#449)")
check(insideCards(panel, "empty") > 10, "the empty board stays inside its cards")

-- The categories are pills that filter the board; a deep link to one opens the board on it (#449)
for _, sub in ipairs({ "dungeon", "raid", "other" }) do
  panel.SelectSub(sub)
  check(panel.activeSub == "active" and Board:Pref("filterCat") == sub, sub .. " opens the board on that filter")
end
panel.SelectSub("all")
check(Board:Pref("filterCat") == "all", "and All on them all")
panel.SelectSub("nonsense")
check(Board:Pref("filterCat") == "all", "a category that is none changes nothing")

-- ── The forms, in place (#449, option E) ────────────────────────────────
-- No window of their own: Form a group turns the left column into the form, I am looking the right one.
local function vis(root, pred)
  local out = {}
  walk(root, function(f) if f:IsVisible() and pred(f) then out[#out + 1] = f end end)
  return out
end
local function formOf(flag) return vis(panel, function(f) return f[flag] == true end)[1] end
local function tilesOf(root) return vis(root, function(f) return f.isActivityTile == true end) end
local function tileOf(root, act) for _, t in ipairs(tilesOf(root)) do if t.act == act then return t end end end
local function rowNamed(name) for _, r in ipairs(vis(panel, function(f) return f.roleIcons ~= nil end)) do if r.name.text:find(name, 1, true) then return r end end end
-- A checkbox by its label (UI:CreateCheckbox), ticked or not, as a click would.
local function tick(root, label, on)
  local box
  walk(root, function(f) if f.checkbox and f.label and f.label.text == label and f:IsVisible() then box = f end end)
  check(box ~= nil, "there is a box \"" .. label .. "\"")
  box.checkbox:SetChecked(on)
  box.checkbox.onChanged(box.checkbox, on)
end
local function inputOf(root) return vis(root, function(f) return f.kind == "EditBox" end)[1] end
local function stepper(root, letter, label)
  return vis(root, function(f) return f.kind == "Button" and f.stepRole == letter and f.label.text == label end)[1]
end
local windows = #UIParent.children

check(picker(panel) == nil and inputOf(cardTitled(panel, "Guild groups")) == nil,
  "the top card has no activity picker nor note: they moved into the forms")

-- Something to count: a group and a player for Karazhan, a player for The Steamvault
local T0 = GetServerTime()
GuildOS.db.lfgGroups[key("Bea")] = Groups:_BuildGroup({ act = "karazhan", need = { T = 1, D = 1 }, ttl = 3600 }, T0)
GuildOS.db.lfgBoard[key("Eve")] = (Board:_BuildEntry({ roles = "D", acts = { "karazhan" }, ttl = 3600 }, T0))
GuildOS.db.lfgBoard[key("Fay")] = (Board:_BuildEntry({ roles = "H", acts = { "steamvault" }, ttl = 3600 }, T0))
Board:Refresh()

-- Step 1: what it is for, as cards (the two boxes start as saved: both off here)
Board:SetPref("autoInvite", false)
Board:SetPref("postToGuild", false)
-- In combat neither form opens: the lists stay.
do
  local realCombat = GuildOS.InCombat
  GuildOS.InCombat = function() return true end
  click(panel, "+ Form a group")
  check(formOf("isGroupForm") == nil and cardTitled(panel, "Groups being formed") ~= nil, "in combat, Form a group does not open")
  GuildOS.InCombat = realCombat
end
click(panel, "+ Form a group")
local fg = formOf("isGroupForm")
check(fg ~= nil and fg.isCard, "Form a group turns the left column into the form, a parchment card")
check(cardTitled(panel, "Groups being formed") == nil and cardTitled(panel, "Looking for a group") ~= nil,
  "in place of the groups being formed, the players' list beside it")
check(shows(fg, "1 · What is it for?") and #buttons(fg, "Cancel") == 1 and #buttons(fg, "Publish group") == 0,
  "on its first step, with Cancel and nothing to publish yet")
check(#UIParent.children == windows, "and no window of its own is made")
click(fg, "Raids")
local kt = tileOf(fg, "karazhan")
check(kt ~= nil and #tilesOf(fg) == 9, "the raids are cards (" .. #tilesOf(fg) .. ")")
check(kt.name.text == "Karazhan" and kt.meta.text:find("Level 70", 1, true) and kt.meta.text:find("group of 10", 1, true),
  "a card names its activity, its level and its size: " .. tostring(kt.meta.text))
check(kt.live.text:find("1 forming", 1, true) and kt.live.text:find("1 looking", 1, true),
  "and who is forming or looking for it: " .. tostring(kt.live.text))
check(tileOf(fg, "gruuls-lair").live.text == "quiet", "a card nobody wants says it is quiet")
check(tilesOf(fg)[1].act == "karazhan", "what is busy comes first")
check(kt.icon.glyph.shown and kt.icon.glyph.letter.text == "K" and not kt.icon.art.shown,
  "with no art on this client a card's emblem is a disc with its initial")
click(fg, "Dungeons")
check(tileOf(fg, "steamvault") ~= nil and tileOf(fg, "classic-dungeon") == nil, "my level only keeps the dungeons of my level")
tick(fg, "My level only", false)
check(tileOf(fg, "classic-dungeon") ~= nil and #tilesOf(fg) == 18, "without it every dungeon is a card (" .. #tilesOf(fg) .. ")")
local grid = vis(fg, function(f) return f.kind == "ScrollFrame" end)[1]
check(grid ~= nil and grid.h < grid.scrollChild.h, "a grid taller than its room scrolls inside the form")
tick(fg, "My level only", true)

-- Step 2: who and when
click(fg, "Raids")
kt = tileOf(fg, "karazhan")
kt.scripts.OnClick(kt)
check(shows(fg, "2 · Who and when") and #tilesOf(fg) == 0, "picking a card moves to the second step")
check(fg.picked:IsVisible() and shows(fg.picked, "Karazhan") and #buttons(fg.picked, "Change") == 1,
  "with the card picked at its top and a way back")
local sk = cardTitled(panel, "Looking for a group")
check(shows(sk, "1 would fit Karazhan"), "the players' list says how many would fit")
check(rowNamed("Eve").fits and not rowNamed("Fay").fits, "and lights them")
click(fg.picked, "Change")
check(shows(fg, "1 · What is it for?") and tileOf(fg, "karazhan").on and tileOf(fg, "karazhan").check.shown,
  "Change goes back to the cards, the one picked still chosen")
tileOf(fg, "karazhan").scripts.OnClick(tileOf(fg, "karazhan"))
check(shows(fg, "OPEN SPOTS") and shows(fg, "STARTS") and shows(fg, "LISTED FOR"), "the spots beside when it starts and how long")
stepper(fg, "H", "+").scripts.OnClick(stepper(fg, "H", "+"))
stepper(fg, "T", "-").scripts.OnClick(stepper(fg, "T", "-"))
stepper(fg, "T", "-").scripts.OnClick(stepper(fg, "T", "-"))
check(shows(fg, "You + 5 open of 10"), "the steppers count the spots: " .. texts(fg):match("You[^\n]*"))
click(fg, "in 15m")
click(fg, "60m")
inputOf(fg):SetText("first night")
tick(fg, "Also post in guild chat", true)
tick(fg, "Invite whoever asks", true)
check(shows(fg, "Guild chat:") and fg.preview.line.text:find("Group for Karazhan", 1, true)
  and fg.preview.line.text:find("first night", 1, true) and fg.preview.line.text:find("inv", 1, true),
  "posting to chat shows the line it will say: " .. tostring(fg.preview.line.text))
tick(fg, "Also post in guild chat", false)
check(not shows(fg, "Guild chat:") and shows(fg, "Only guildmates with Guild OS will see it (in this list and as a tile)."),
  "and not posting says who sees it")
tick(fg, "Also post in guild chat", true)
check(Board:Pref("autoInvite") == false and Board:Pref("postToGuild") == false, "the boxes are not saved before Publish")
check(insideCards(panel, "the form's second step") > 20, "the form stays inside its card")
local sent
local realCreate = Groups.Create
Groups.Create = function(self, ...) sent = { ... }; return realCreate(self, ...) end
click(fg, "Publish group")
Groups.Create = realCreate
check(sent and sent[1] == "karazhan" and sent[2].T == 0 and sent[2].H == 2 and sent[2].D == 3 and sent[3] == "first night"
  and sent[4] == 3600 and sent[5] == true and sent[6] == 900,
  "Publish lists the group with its activity, spots, note, duration, chat line and start")
check(Board:Pref("autoInvite") == true and Board:Pref("postToGuild") == true, "and saves the two boxes (invite whoever asks)")
check(not fg:IsVisible() and shows(panel, "Your group: Karazhan"), "then the left column is my group")
check(Groups:Mine().start == T0 + 900 and Groups:Mine().note == "first night", "listed as chosen")

-- Change on my group opens the second step on what it has
click(cardTitled(panel, "Your group"), "Change")
check(fg:IsVisible() and shows(fg, "2 · Who and when") and inputOf(fg):GetText() == "first night" and #buttons(fg, "Update") == 1,
  "Change on my group opens the form on its values")
check(buttons(fg, "in 15m")[1].__selected and buttons(fg, "60m")[1].__selected, "its start and its duration lit")
check(#buttons(fg, "Take down") == 0, "Take down is on my group's card, not in the form")
for _ = 1, 6 do
  stepper(fg, "H", "-").scripts.OnClick(stepper(fg, "H", "-"))
  stepper(fg, "D", "-").scripts.OnClick(stepper(fg, "D", "-"))
end
check(not buttons(fg, "Update")[1].enabled, "a group with no open spot cannot go up")
stepper(fg, "D", "+").scripts.OnClick(stepper(fg, "D", "+"))
local canInvite = GuildOS.Compat.CanInvite
GuildOS.Compat.CanInvite = function() return false end
click(fg, "Update")
GuildOS.Compat.CanInvite = canInvite
check(fg:IsVisible() and shows(fg, "Only the group's leader can list it."), "a group the module refuses stays in the form, with the reason")
panel.scripts.OnKeyDown(panel, "ESCAPE")
check(not fg:IsVisible() and shows(panel, "Your group: Karazhan") and Groups:Mine().need.H == 2, "Esc goes back to the lists, nothing changed")
click(panel, "Take down")
check(Groups:Mine() == nil, "Take down removes my group")
click(panel, "+ Form a group")
click(fg, "Cancel")
check(not fg:IsVisible() and cardTitled(panel, "Groups being formed") ~= nil, "Cancel goes back to the lists")

-- I am looking: the same cards, several at once
click(panel, "I am looking")
local sf = formOf("isSeekForm")
check(sf ~= nil and sf.isCard and cardTitled(panel, "Looking for a group") == nil and cardTitled(panel, "Groups being formed") ~= nil,
  "I am looking turns the right column into its form, the groups beside it")
check(shows(sf, "none picked: anything") and #buttons(sf, "Start looking") == 1, "with nothing picked: anything")
check(#UIParent.children == windows, "still no window of its own")
click(sf, "Raids")
tileOf(sf, "karazhan").scripts.OnClick(tileOf(sf, "karazhan"))
click(sf, "Dungeons")
tileOf(sf, "steamvault").scripts.OnClick(tileOf(sf, "steamvault"))
check(shows(sf, "2 picked") and tileOf(sf, "steamvault").on and tileOf(sf, "steamvault").check.shown, "a card picked is ticked, and counted")
click(sf, "Raids")
tileOf(sf, "karazhan").scripts.OnClick(tileOf(sf, "karazhan"))
check(shows(sf, "1 picked") and not tileOf(sf, "karazhan").on, "a second click takes it back")
local toggles = {}
walk(sf, function(f) if f.kind == "Button" and f.letter and f:IsVisible() and f.scripts.OnClick then toggles[f.letter] = f end end)
check(toggles.T and toggles.H and toggles.D and shows(sf, "MY ROLES (NONE IS ANY)"), "my roles are pills")
toggles.H.scripts.OnClick(toggles.H)
click(sf, "60m")
inputOf(sf):SetText("SP")
tick(sf, "Also post in guild chat", false)
check(insideCards(panel, "the looking form") > 20, "the looking form stays inside its card")
click(sf, "Start looking")
mine = Board:Mine()
check(mine ~= nil and #mine.acts == 1 and mine.acts[1] == "steamvault" and mine.roles == "H" and mine.ttl == 3600 and mine.note == "SP",
  "Start looking lists me with the activities, roles, duration and note")
check(Board:Pref("roles") == "H", "the roles I listed are the ones I play")
check(not sf:IsVisible() and shows(panel, "(you)") and #buttons(panel, "Stop looking") == 1 and shows(panel, "60m left"),
  "then the list shows me, and the top card my listing's time and Stop")
click(cardTitled(panel, "Guild groups"), "Change")
check(sf:IsVisible() and shows(sf, "1 picked") and tileOf(sf, "steamvault") and #buttons(sf, "Update") == 1
  and inputOf(sf):GetText() == "SP", "Change opens the form on my listing")
panel.scripts.OnKeyDown(panel, "ESCAPE")
check(not sf:IsVisible(), "Esc closes it")
click(panel, "Stop looking")
check(Board:Mine() == nil, "Stop looking takes me down")
check(#UIParent.children == windows, "and no form ever made a window")
GuildOS.db.lfgGroups[key("Bea")], GuildOS.db.lfgBoard[key("Eve")], GuildOS.db.lfgBoard[key("Fay")] = nil, nil, nil
Board:Refresh()

-- ── My quests (#450) ────────────────────────────────────────────────────
do
  local Q = GuildOS.GroupQuests
  Q:Refresh()
  local function questTile(root, id) for _, t in ipairs(tilesOf(root)) do if t.act == "q:" .. id then return t end end end
  -- Form a group: My quests is a pill beside the catalogue's, its cards my log's, group quests first.
  click(panel, "+ Form a group")
  check(#buttons(fg, "My quests") == 1 and #buttons(fg, "Quests and more") == 1, "My quests is a category beside Quests and more")
  click(fg, "My quests")
  local ts = tilesOf(fg)
  check(#ts == 4 and ts[1].act == "q:10809" and ts[2].act == "q:9738", "a card per quest of my log, the group ones first")
  local kt = questTile(fg, 10809)
  check(kt.name.text == "Wanted: Worg Master Kruush" and kt.meta.text:find("Level 62", 1, true)
    and kt.meta.text:find("Group", 1, true) and kt.meta.text:find("group of 3", 1, true),
    "a quest's card says its level, its tag and its suggested players: " .. tostring(kt.meta.text))
  check(kt.live.text == "Hellfire Peninsula", "and its zone while nobody is on it")
  check(questTile(fg, 9738).meta.text:find("Dungeon", 1, true), "a dungeon quest says so")
  check(not shows(fg, "My level only"), "the quests of my log need no level filter")
  check(insideCards(panel, "the quest cards") > 20, "the quest cards stay inside the form")
  -- Single pick: a card moves to the second step; another replaces it.
  questTile(fg, 9738).scripts.OnClick(questTile(fg, 9738))
  check(shows(fg.picked, "Lost in Action") and shows(fg, "2 · Who and when"), "picking a quest moves to the second step, its title on top")
  click(fg.picked, "Change")
  check(questTile(fg, 9738).on and not questTile(fg, 10809).on, "the quest picked is the one chosen")
  questTile(fg, 10809).scripts.OnClick(questTile(fg, 10809))
  check(not shows(fg.picked, "Lost in Action") and shows(fg.picked, "Wanted: Worg Master Kruush"), "another pick replaces it: one quest a group")
  -- A guildmate who shares this quest lights up while the group is formed.
  GuildOS.db.lfgBoard[key("Eve")] = (Board:_BuildEntry({ roles = "D", acts = { "deadmines" }, shared = { 10809 }, ttl = 3600 }, T0))
  GuildOS.db.lfgBoard[key("Fay")] = (Board:_BuildEntry({ roles = "H", acts = { "karazhan" }, ttl = 3600,
    quests = { { id = 9738, t = "Lost in Action" } } }, T0))
  Board:Refresh()
  check(rowNamed("Eve").fits and rowNamed("Eve").questMark.text == "also on this quest" and rowNamed("Eve").questMark.shown,
    "who has the quest fits, marked \"also on this quest\"")
  check(not rowNamed("Fay").fits and rowNamed("Fay").questMark.text == "you have this quest",
    "who is on another quest of my log is marked \"you have this quest\"")
  check(shows(cardTitled(panel, "Looking for a group"), "1 would fit Wanted: Worg Master Kruush"), "the chip names the quest")
  local sentQ
  local realCreate = Groups.Create
  Groups.Create = function(self, ...) sentQ = { ... }; return realCreate(self, ...) end
  GuildOS.State.groups.lastPublish = -100   -- past the publish window: the stub clock stands still
  click(fg, "Publish group")
  Groups.Create = realCreate
  check(sentQ and sentQ[7] and sentQ[7].id == 10809 and sentQ[7].t == "Wanted: Worg Master Kruush", "Publish hands the module the quest")
  local mine = Groups:Mine()
  check(mine.act == "elite-quests" and mine.quest.id == 10809 and wire[#wire].p.quest.id == 10809, "listed under Elite quests, with its quest")
  check(shows(panel, "Your group: Wanted: Worg Master Kruush"), "my group is named by its quest")
  check(shows(panel, "Fits your group") and shows(panel, "also on this quest"), "the leader's matches mark who has the quest")
  check(insideCards(panel, "my quest group") > 20, "and stay inside their cards")
  click(cardTitled(panel, "Your group"), "Change")
  check(shows(fg.picked, "Wanted: Worg Master Kruush"), "Change opens the form on the group's quest")
  panel.scripts.OnKeyDown(panel, "ESCAPE")
  click(panel, "Take down")

  -- Somebody else's group for a quest of my log: "you have this quest" on its card.
  Groups:HandleGroup("Bea-Realm", { act = "elite-quests", need = { D = 2 }, ttl = 3600, quest = { id = 9738, t = "Lost in Action" } }, "GUILD")
  Groups:HandleGroup("Cid-Realm", { act = "elite-quests", need = { D = 2 }, ttl = 3600, quest = { id = 777, t = "Not mine" } }, "GUILD")
  local bc, cc
  walk(panel, function(f) if f.lead and f:IsVisible() and f.title.text == "Lost in Action" then bc = f end end)
  walk(panel, function(f) if f.lead and f:IsVisible() and f.title.text == "Not mine" then cc = f end end)
  check(bc and bc.questBadge.shown and bc.questBadge.label.text == "you have this quest", "a group for a quest I have says so")
  check(bc.range.text == "Level 64", "with the quest's level from my log")
  check(cc and not cc.questBadge.shown, "a group for a quest I do not have says nothing")
  check(insideCards(panel, "quest groups") > 20, "the quest groups stay inside their cards")

  -- I am looking: several quests, capped; the opt-in off by default; only the picks go out.
  click(panel, "I am looking")
  local sf2 = formOf("isSeekForm")
  click(sf2, "My quests")
  for _, id in ipairs({ 10809, 9738, 10482, 9895 }) do questTile(sf2, id).scripts.OnClick(questTile(sf2, id)) end
  check(shows(sf2, "3 picked") and questTile(sf2, 10809).on and not questTile(sf2, 9895).on, "several quests, at most three")
  questTile(sf2, 10482).scripts.OnClick(questTile(sf2, 10482))
  check(shows(sf2, "2 picked"), "a second click takes one back")
  local share
  walk(sf2, function(f) if f.checkbox and f.label and f.label.text == "Share the group quests in my log with the guild LFG" then share = f end end)
  check(share and share:IsVisible() and not share.checkbox:GetChecked(), "the opt-in is there, off by default")
  check(insideCards(panel, "the looking form on my quests") > 20, "the looking form stays inside its card")
  click(sf2, "Start looking")
  local p = wire[#wire].p
  check(wire[#wire].kind == "LG" and #p.quests == 2 and p.quests[1].id == 10809 and p.quests[2].id == 9738 and p.shared == nil,
    "the listing carries the two quests picked and nothing else of my log")
  check(Board:Pref("shareQuests") == false, "the opt-in stays off")
  click(cardTitled(panel, "Guild groups"), "Change")
  check(shows(sf2, "2 picked"), "Change opens on the quests, Elite quests not counted as a pick")
  questTile(sf2, 9738).scripts.OnClick(questTile(sf2, 9738))
  tick(sf2, "Share the group quests in my log with the guild LFG", true)
  Board._cd = {}
  click(sf2, "Update")
  p = wire[#wire].p
  check(Board:Pref("shareQuests") == true and #p.quests == 1 and p.shared and #p.shared == 1 and p.shared[1] == 9738,
    "opted in, the group quests of my log not picked go too, as ids only")
  Board:SetPref("shareQuests", false)

  -- Classic's shape draws the same cards.
  local modern = C_QuestLog
  C_QuestLog = nil
  GetNumQuestLogEntries = function() return 2 end
  GetQuestLogTitle = function(i)
    if i == 1 then return "Hellfire Peninsula", 0, 0, true end
    return "Wanted: Worg Master Kruush", 62, 3, false, false, false, 0, 10809
  end
  GetQuestTagInfo = function() return 1, "Group" end
  Q:Refresh()
  click(panel, "+ Form a group")
  click(fg, "My quests")
  check(#tilesOf(fg) == 1 and questTile(fg, 10809).meta.text:find("group of 3", 1, true), "the Classic log draws the same card")
  -- An empty log says so.
  GetNumQuestLogEntries = function() return 0 end
  Q:Refresh()
  Board:Refresh()
  check(#tilesOf(fg) == 0 and shows(fg, "Your quest log has no quest."), "an empty log says so")
  click(fg, "Cancel")
  GetNumQuestLogEntries, GetQuestLogTitle, GetQuestTagInfo = nil, nil, nil
  C_QuestLog = modern
  Q:Refresh()

  -- Both widths: the quest cards stay inside their forms, a repaint makes no frame.
  for _, size in ipairs({ { 560, 580 }, { 1180, 1200 } }) do
    walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(size[1], 500) end end)
    panel:SetSize(size[2], 600)
    click(panel, "+ Form a group")
    click(fg, "My quests")
    check(#tilesOf(fg) == 4 and insideCards(panel, size[2] .. "px, quest cards") > 20, size[2] .. "px: the quest cards stay inside the form")
    local before = created
    for _ = 1, 3 do click(fg, "Raids"); click(fg, "My quests") end
    check(created == before, size[2] .. "px: repainting the quest cards makes no frame (" .. (created - before) .. " new)")
    click(fg, "Cancel")
    click(panel, "I am looking")
    click(formOf("isSeekForm"), "My quests")
    check(insideCards(panel, size[2] .. "px, looking on quests") > 20, size[2] .. "px: the looking form on quests stays inside")
    click(formOf("isSeekForm"), "Cancel")
  end
  walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(860, 500) end end)
  panel:SetSize(900, 600)

  click(panel, "Stop looking")
  GuildOS.db.lfgGroups[key("Bea")], GuildOS.db.lfgGroups[key("Cid")] = nil, nil
  GuildOS.db.lfgBoard[key("Eve")], GuildOS.db.lfgBoard[key("Fay")] = nil, nil
  Board._cd, GuildOS.State.groups.groupCd = {}, {}
  Board:Refresh()
end

-- Forming a group, as before the queue below needs it
click(panel, "+ Form a group")
click(fg, "Dungeons")
tileOf(fg, "steamvault").scripts.OnClick(tileOf(fg, "steamvault"))
stepper(fg, "D", "+").scripts.OnClick(stepper(fg, "D", "+"))
check(shows(fg, "You + 4 open of 5"), "the spots never pass the room a party has")
stepper(fg, "T", "-").scripts.OnClick(stepper(fg, "T", "-"))
stepper(fg, "T", "-").scripts.OnClick(stepper(fg, "T", "-"))
click(fg, "Publish group")
local group = Groups:Mine()
check(group ~= nil and group.act == "steamvault" and group.need.T == 0 and group.need.D == 3, "publishing lists my group with the spots chosen")
check(group.need.H == 0, "and no spot is offered for the one role I play myself")
check(shows(panel, "Your group: The Steamvault"), "my group heads the left column")
check(shows(panel, "Nobody asked for a spot yet. Guildmates see your group here and in the tiles."), "with an empty queue said as such")
check(#buttons(panel, "My group") == 1, "and the top card's button now opens it")

-- The queue
Groups:HandleJoin("Bea-Realm", { role = "D" }, "WHISPER")
check(shows(panel, "Asking for a spot") and shows(panel, "Bea"), "a request shows in the queue")
click(panel, "Invite")
check(invited[1] == "Bea-Realm" and shows(panel, "invited"), "Invite calls the game's invite and marks the row")
check(insideCards(panel, "my group") > 10, "my group's card holds its queue")
click(panel, "Decline")
check(#Groups:Requests() == 0 and wire[#wire].to == "Bea-Realm" and wire[#wire].p.decline == true, "Decline tells the asker and clears the row")
click(panel, "Take down")
check(Groups:Mine() == nil, "Take down removes my group")

-- Somebody else's group, and who is looking
Groups:HandleGroup("Cid-Realm", { act = "karazhan", need = { T = 1, D = 2 }, note = "first night", ttl = 3600 }, "GUILD")
Board:HandleEntry("Dan-Realm", { roles = "TD", acts = { "karazhan" }, note = "until 23h", ttl = 3600 })
gc = cardTitled(panel, "Groups being formed")
check(shows(gc, "first night") and shows(gc, "missing 1 Tank, 2 DPS"), "a group shows its note and what it is missing")
check(#buttons(gc, "Tank") == 1 and #buttons(gc, "DPS") == 1 and #buttons(gc, "Healer") == 0,
  "and offers the roles it has a spot for, and no other")
check(shows(panel, "Karazhan: until 23h") and shows(panel, "Tank, DPS"), "a player looking shows the activities, the note and the roles")
click(gc, "Whisper")
check(tells[1] == "Cid", "Whisper opens a whisper to the leader")
click(cardTitled(panel, "Looking for a group"), "Invite")
check(invited[#invited] == "Dan", "Invite on a player looking invites them")
click(gc, "Tank")
check(wire[#wire].kind == "GJ" and wire[#wire].to == "Cid-Realm" and wire[#wire].p.role == "T", "a role button asks the leader for that spot")
check(shows(gc, "asked as Tank") and #buttons(gc, "Tank") == 0, "and the card then says what I asked")
click(gc, "Take it back")
check(Groups:Asked(key("Cid")) == nil and #buttons(gc, "Tank") == 1, "taking it back offers the roles again")
check(insideCards(panel, "the board") > 20, "the board's groups and players stay inside their cards")

-- ── The figures, the filters and the leader's card (#378) ───────────────
check(shows(panel, "groups forming") and shows(panel, "looking") and shows(panel, "for you"), "the board opens on its figures")
click(panel, "Dungeons")
check(Board:Pref("filterCat") == "dungeon" and not shows(panel, "first night")
  and shows(panel, "No group is being formed right now. Pick an activity to start one."), "a filter leaves out the other activities")
check(shows(panel, "Karazhan: until 23h") == false, "and who is looking only for them")
click(panel, "Raids")
check(shows(panel, "first night") and shows(panel, "Karazhan: until 23h"), "the raids' filter keeps the raid")
click(panel, "All")
local before = Board:Pref("roles")
Board:SetPref("roles", "T")
Board:Refresh()
check(shows(cardTitled(panel, "Groups being formed"), "for you"), "a group of my level with a spot in my role says it is for me")
Board:SetPref("roles", before)
Board:Refresh()
check(not shows(cardTitled(panel, "Groups being formed"), "for you"), "and one with no spot in my role does not")
click(panel, "My level only")
check(Board:Pref("filterLevel") == true and shows(panel, "first night"), "my level only keeps a group of my level")
click(panel, "My level only")
check(Board:Pref("filterLevel") == false, "and a second click shows them all again")

Groups:Create("steamvault", { T = 0, H = 0, D = 2 }, "SP", 3600, false, 900)
Board:HandleEntry("Fay-Realm", { roles = "D", acts = {}, note = "anything", ttl = 3600 })
check(shows(panel, "Your group: The Steamvault") and shows(panel, "starts in 15m") and shows(panel, "1/5"),
  "the leader's card names the group, when it starts and how full it is")
check(#buttons(panel, "+30 min") >= 1 and #buttons(panel, "Change") == 1 and #buttons(panel, "Take down") == 1,
  "and gives the leader what to do with it")
GuildOS.db.lfgPrefs.lastGuildLine = 0
Board:Refresh()
check(#buttons(panel, "Post in chat") == 1, "posting in chat is one click while the cooldown allows it")
click(panel, "Post in chat")
check(#buttons(panel, "Post in chat") == 0, "and then waits out the cooldown")
local waiting
walk(panel, function(f)
  if f.kind == "Button" and f:IsVisible() and f.label and f.label.text == "Post in chat (in 5m)" then waiting = f end
end)
check(waiting ~= nil, "saying how long")
check(shows(panel, "Fits your group") and shows(panel, "anything"), "a player looking who fits is offered to the leader")
local inviteAs
walk(panel, function(f)
  if f.kind == "Button" and f:IsVisible() and f.label and f.label.text and f.label.text:find("Invite as", 1, true) then inviteAs = f end
end)
check(inviteAs ~= nil and inviteAs.variant == "primary", "with an invite in the role they fit")
inviteAs.scripts.OnClick(inviteAs)
check(invited[#invited] == "Fay" and Groups:Requests()[1].state == "invited", "which invites them and keeps their spot")
check(not shows(panel, "Fits your group"), "and they are no longer offered")
check(insideCards(panel, "leader") > 20, "the leader's card and the lists stay inside their cards")
click(panel, "+30 min")
check(Groups:Mine().ttl > 3600 - 1, "+30 min gives my group more time")
click(panel, "Take down")
GuildOS.db.lfgBoard[key("Fay")] = nil
Board._cd = {}   -- the stub never ends a cooldown; Fay speaks again below
Board:Refresh()

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

-- This client has no role art: every role is spelled out.
for _, letter in ipairs({ "T", "H", "D" }) do
  check(play[letter].label.text == Board:RoleName(({ T = "TANK", H = "HEALER", D = "DPS" })[letter]) and not play[letter].icon.shown,
    "with no role art the " .. letter .. " toggle says its role's name")
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
check(kc.range.text == "Level 70" and sc.range.text == "Level 68\226\128\14770", "a card shows its activity's level range")
local priest = string.format("%02x%02x%02x", (function(r, g, b) return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) end)(UI:InkFor("paper", "class", "PRIEST")))
check(kc.lead.text == "led by |cff" .. priest .. "Cid|r", "and who leads it, in their class's ink on the paper")
check(kc.avatar:IsShown() and kc.avatar.letter.text == "C", "with the leader's avatar")
check(kc.when.text:find("1/10", 1, true) and kc.when.text:find("60m", 1, true), "how full it is and for how long")
check(kc.ago.text ~= "", "and how long ago it was listed")
check(shows(kc, "missing 1 Tank, 2 DPS") and shows(sc, "missing 1 Healer"), "and what it is missing")
check(#buttons(sc, "Healer") == 1 and #buttons(sc, "Tank") == 0 and #buttons(sc, "Whisper") == 1,
  "a card keeps its Join action for the roles it has open")
check(buttons(sc, "Healer")[1].variant == "primary", "the role I would ask as is the primary one")
for _, s in ipairs(kc.slots) do
  if s:IsShown() and not s.filled then check(s.mark.text == s.role, "with no role art an open seat shows its letter") end
end

-- One row per player looking
local rows = seekerRows(panel)
check(#rows == 2, "one row per player looking (" .. #rows .. ")")
local dan, fay = rowOf(rows, "Dan"), rowOf(rows, "Fay")
check(dan.levelText.text == "Lv 68" and fay.levelText.text == "Lv 62", "a row says the player's level, from the roster")
check(dan.roles.text == "Tank, DPS" and fay.roles.text == "Healer", "with no role art the roles are spelled out")
check(dan.what.text == "Karazhan: until 23h" and fay.what.text == "The Steamvault", "and what they want")
check(#buttons(dan, "Invite") == 1 and #buttons(dan, "Whisper") == 1, "the row invites and whispers")
check(dan.avatar:IsShown() and dan.avatar.letter.text == "D", "with the player's avatar")

-- The form's cards follow my level: "My level only" keeps the dungeons of my level (give or take five)
local function formTiles(level)
  UnitLevel = function() return level end
  click(panel, "+ Form a group")
  local f = formOf("isGroupForm")
  click(f, "Dungeons")
  local got = {}
  for _, t in ipairs(tilesOf(f)) do got[t.act] = true end
  click(f, "Cancel")
  return got
end
local at70, at60 = formTiles(70), formTiles(60)
check(at70["steamvault"] and not at70["classic-dungeon"] and not at70["hellfire-ramparts"], "at level 70 the cards are the dungeons of 70")
check(at60["classic-dungeon"] and at60["hellfire-ramparts"] and not at60["steamvault"], "at level 60 those of 60")
UnitLevel = function() return 70 end

-- A repaint reuses what it drew
panel.SelectSub("active")
local settled = created
for _ = 1, 5 do
  panel.SelectSub("dungeon")
  panel.SelectSub("raid")
  panel.SelectSub("all")
end
check(created == settled, "repainting creates no frame it already has (" .. (created - settled) .. " new)")

-- The board's refresh lands here, and a hidden tab does no work
check(Board.uiRefresh ~= nil, "the modules' refresh is the panel's paint")
panel:Hide()
Board:HandleEntry("Bea-Realm", { roles = "H", ttl = 3600 })
panel:Show()
panel.scripts.OnShow(panel)
check(shows(panel, "Bea"), "what arrived while the tab was closed is there when it opens")

-- Narrow: the lists one under the other, still inside their cards
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(560, 500) end end)
panel:SetSize(580, 600)
panel.SelectSub("all")
gc, sk = cardTitled(panel, "Groups being formed"), cardTitled(panel, "Looking for a group")
local gr, sr = rectOf(gc, {}), rectOf(sk, {})
check(sr.t >= gr.b, "on a narrow window the players' list is under the groups'")
check(insideCards(panel, "narrow") > 20, "and everything stays inside its card")
-- The forms at both widths: nothing past a card's edge, each grid one card to a row when narrow
local function perRow(ts)
  local x1 = rectOf(ts[1], {}).l
  return math.abs(rectOf(ts[2], {}).l - x1) < 1 and 1 or 2
end
local function formsInside(what, stacked, gCols, sCols)
  local cols = stacked and 1 or 2
  click(panel, "+ Form a group")
  local f = formOf("isGroupForm")
  click(f, "Raids")
  local ts = tilesOf(f)
  check(#ts > 1 and perRow(ts) == gCols, what .. ": the form's grid is " .. gCols .. " card(s) to a row")
  check(insideCards(panel, what .. ", form step 1") > 20, what .. ": the form's cards stay inside it")
  ts[1].scripts.OnClick(ts[1])
  check(insideCards(panel, what .. ", form step 2") > 20, what .. ": its second step stays inside it")
  local fr, lr = rectOf(f, {}), rectOf(cardTitled(panel, "Looking for a group"), {})
  if cols == 1 then check(lr.t >= fr.b, what .. ": the players' list goes under the form")
  else check(math.abs(lr.t - fr.t) < 1 and lr.l > fr.r, what .. ": the players' list beside the form") end
  click(f, "Cancel")
  click(panel, "I am looking")
  local sf2 = formOf("isSeekForm")
  click(sf2, "Raids")
  check(perRow(tilesOf(sf2)) == sCols, what .. ": the looking form's grid is " .. sCols .. " card(s) to a row")
  check(insideCards(panel, what .. ", looking form") > 20, what .. ": the looking form stays inside its card")
  if cols == 1 then check(rectOf(sf2, {}).t < rectOf(cardTitled(panel, "Groups being formed"), {}).t, what .. ": an open form takes the top slot") end
  click(sf2, "Cancel")
end
formsInside("narrow", true, 2, 2)
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(1180, 500) end end)
panel:SetSize(1200, 600)
panel.SelectSub("all")
gr, sr = rectOf(gc, {}), rectOf(sk, {})
check(math.abs(sr.t - gr.t) < 1 and sr.l > gr.r, "from 900px they sit side by side")
check(math.abs((gr.b - gr.t) - (sr.b - sr.t)) < 1 and gr.b - gr.t >= 500 - 1, "as tall as each other, filling the height left")
check(insideCards(panel, "wide") > 20, "and everything stays inside its card")
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(1180, 500) end end)
formsInside("wide", false, 2, 2)
-- A column narrower than two cards takes one: the right one at 900px
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(920, 500) end end)
panel:SetSize(940, 600)
formsInside("900px", false, 2, 1)
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(860, 500) end end)
panel:SetSize(900, 600)

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
-- A fresh panel makes its frames on its first paints: paint each filter once, then count.
local function settles(p, what)
  p.SelectSub("dungeon")
  p.SelectSub("raid")
  p.SelectSub("all")
  local before = created
  for _ = 1, 3 do
    p.SelectSub("dungeon")
    p.SelectSub("raid")
    p.SelectSub("all")
  end
  check(created == before, what .. ": repainting creates no frame it already has (" .. (created - before) .. " new)")
end

-- A client with the group finder's atlases (and every file, so the activity art draws too)
local ATLAS = { T = "groupfinder-icon-role-large-tank", H = "groupfinder-icon-role-large-heal", D = "groupfinder-icon-role-large-dps" }
C_Texture = { GetAtlasInfo = function(name)
  for _, a in pairs(ATLAS) do if a == name then return { width = 32, height = 32 } end end
end }
function GetFileIDFromPath() return 1 end
for _, it in pairs(GuildOS.GroupActivities.byId) do it.artOk = nil end
dofile(ADDON .. "/UI/GroupsPanel.lua")
panel:Hide()
local iconPanel = build()

local ic = chipsOf(iconPanel)
for letter, atlas in pairs(ATLAS) do
  check(ic[letter].icon.shown and ic[letter].icon.atlas == atlas and ic[letter].label.text ~= "",
    "with the atlases a role toggle is the game's icon and its name: " .. atlas)
end
check(ic.H.__selected and ic.D.__selected and not ic.T.__selected, "the roles I play are marked selected")
check(ic.T.icon.desaturated and not ic.H.icon.desaturated, "and a role I do not play is greyed")
ic.T.scripts.OnClick(ic.T)
check(Board:Pref("roles") == "THD" and ic.T.__selected and not ic.T.icon.desaturated, "a click on an icon toggles its role")
ic.T.scripts.OnClick(ic.T)

local ikc = cardOf(iconPanel, "Karazhan")
check(ikc.icon.art.shown and ikc.icon.art.texture == "Interface\\LFGFrame\\UI-LFG-BACKGROUND-Karazhan"
  and near(ikc.icon.art.coords, { 0.32, 0.68, 0.12, 0.84 }) and not ikc.icon.glyph.shown,
  "a card's icon is its activity's art, cut square")
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
local bea = rowOf(rows, "Bea")
check(bea.roleIcons[1].shown and not bea.roleIcons[2].shown, "a player with one role shows one icon")
check(insideCards(iconPanel, "with icons") > 20, "with icons everything stays inside its card")
settles(iconPanel, "with icons")

-- An activity with no art of its own is its initial
GuildOS.GroupActivities.byId.karazhan.artOk = false
iconPanel.SelectSub("all")
ikc = cardOf(iconPanel, "Karazhan")
check(not ikc.icon.art.shown and ikc.icon.glyph.shown and ikc.icon.glyph.letter.text == "K", "an activity the client has no art for shows its initial")
GuildOS.GroupActivities.byId.karazhan.artOk = nil

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
check(fc.T.icon.shown, "and still stand beside the role's name")
settles(filePanel, "with the file")

-- The WoW: Forever client, with its atlases: the same screen, the same look (one look on every client, #449)
C_Texture = { GetAtlasInfo = function() return { width = 32, height = 32 } end }
GuildOSDB = { style = "forever" }
check(GuildOS.Style:Resolve() == "salao", "a saved style from before is ignored: the Salão's look on Forever too")
dofile(ADDON .. "/UI/GroupsPanel.lua")
filePanel:Hide()
local foreverPanel = build()
check(#cards(foreverPanel) == 2 and #seekerRows(foreverPanel) == 3, "in the Forever style the cards and rows are the same")
check(chipsOf(foreverPanel).T.icon.atlas == ATLAS.T, "with the Forever client's role atlases")
click(foreverPanel, "+ Form a group")
check(#tilesOf(foreverPanel) > 0 and insideCards(foreverPanel, "the Forever form") > 20, "and the form's cards are the same")
click(foreverPanel, "Cancel")
settles(foreverPanel, "in the Forever style")

-- A notice queued for after combat says the group as it is when it shows, not as it was queued (#449 review).
do
  local B, G = GuildOS.LFGBoard, GuildOS.Groups
  GuildOS.db.lfgPrefs = GuildOS.db.lfgPrefs or {}
  GuildOS.db.lfgPrefs.roles = "TH"
  local k = GuildOS:GetPlayerKey("Toastee", "Realm")
  local now = GetServerTime()
  GuildOS.db.lfgGroups = GuildOS.db.lfgGroups or {}
  GuildOS.db.lfgGroups[k] = G:_BuildGroup({ act = "karazhan", need = { T = 0, H = 1, D = 0 }, ttl = 3600 }, now)
  local shown
  local oldClear = GuildOS.ShowWhenClear
  GuildOS.ShowWhenClear = function(_, _, fn) shown = fn() end
  GuildOS:GroupsToast({ kind = "group", key = k, name = "Toastee", act = "karazhan", need = { T = 1, H = 1, D = 0 } })
  GuildOS.ShowWhenClear = oldClear
  check(shown ~= nil, "the notice shows")
  local body = shown.body.text or ""
  check(body:find(G:NeedText({ T = 0, H = 1, D = 0 }), 1, true) ~= nil and not body:find(G:NeedText({ T = 1, H = 1, D = 0 }), 1, true),
    "the open spots are the group's now: " .. body)
  check((shown.primary.label.text or ""):find(B:RoleName("HEALER"), 1, true) ~= nil,
    "and it offers the role still open: " .. tostring(shown.primary.label.text))
  GuildOS.db.lfgGroups[k] = nil
end

print(checks .. " checks ok")
