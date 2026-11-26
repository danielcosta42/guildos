-- The Groups tab (issue #341): the real UI/GroupsPanel.lua built on the real helpers, under a
-- stubbed client, and driven by its own buttons.
--
-- The board paints with nothing and with something in it; the activity picker lists this client's
-- activities by level and instance and opens the composer on the one picked; publishing lists me or
-- my group, from the composer or from the card; a card's role button asks for a spot; the queue's
-- buttons invite and decline; the filters are pills; a repaint reuses its rows instead of creating
-- them again; the lists sit side by side from 900px and one under the other below; and everything
-- drawn on a card lies inside it (#449).
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
      local inside = r.l >= box.l - 0.5 and r.r <= box.r + 0.5 and r.t >= box.t - 0.5 and r.b <= box.b + 0.5
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

-- The activity picker: by level, then by instance
local dd = picker(panel)
check(dd ~= nil, "the top card has the activity picker")
check(dd.options[1].value == "" and dd.options[1].text == "Anything", "which starts on Anything")
check(optionTexts(dd):find("The Steamvault", 1, true) and optionTexts(dd):find("Heroic dungeon", 1, true)
  and optionTexts(dd):find("Karazhan", 1, true), "and lists this client's dungeons and raids under their sections")
local function headers(d)
  local out = {}
  for _, o in ipairs(d.options) do if o.disabled then out[#out + 1] = o.text end end
  return out
end
check(#headers(dd) >= 3, "a section's title is a row that cannot be picked")

-- Form a group on the activity picked
dd:Select("karazhan")
click(panel, "+ Form a group")
local composer
walk(UIParent, function(f) if f.Open and rawget(f, "Pick") then composer = f end end)
check(composer ~= nil and composer:IsShown(), "Form a group opens the composer")
check(composer.mode == "group" and composer.act == "karazhan" and shows(composer, "Karazhan"), "on the activity picked")

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
check(shows(panel, "(you)") and shows(panel, "Karazhan") and shows(panel, "Healer"), "my listing is on the board, marked as mine")
check(#buttons(panel, "Stop looking") == 1, "and the card now takes it down")
check(shows(panel, "60m left"), "saying how long it has left")

-- The composer's picker adds to what I am looking for
click(panel, "Change")
check(composer:IsShown() and composer.mode == "seek", "Change opens my listing")
picker(composer):Select("steamvault")
check(#composer.acts == 2, "another activity picked joins my listing")
check(#buttons(composer, "Update") == 1 and #buttons(composer, "Take down") == 1, "a listing I have is updated or taken down")
click(composer, "Only this one")
check(#composer.acts == 1 and composer.acts[1] == "steamvault", "or replaces the others")
click(composer, "Take down")
check(Board:Mine() == nil, "taking it down from the composer delists me")

-- I am looking, from the card itself
picker(panel):Select("steamvault")
local note = nil
walk(panel, function(f) if f.kind == "EditBox" and f:IsVisible() then note = f end end)
note:SetText("SP")
click(panel, "I am looking")
mine = Board:Mine()
check(mine ~= nil and mine.acts[1] == "steamvault" and mine.note == "SP", "the card lists me for the activity picked, with the note")
check(#buttons(panel, "Update") == 0, "with nothing to update")
picker(panel):Select("karazhan")
check(#buttons(panel, "Update") == 1, "picking another activity offers to update it")
click(panel, "Update")
check(Board:Mine().acts[1] == "karazhan" and #buttons(panel, "Update") == 0, "and Update says it")
click(panel, "Stop looking")
check(Board:Mine() == nil, "Stop looking takes me down")

-- Forming a group
picker(panel):Select("steamvault")
click(panel, "+ Form a group")
check(composer.mode == "group" and composer.act == "steamvault", "the composer opens on the group to form")
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
check(shows(panel, "Your group: The Steamvault"), "my group heads the board")
check(shows(panel, "Nobody asked for a spot yet. Guildmates see your group here and in the tiles."), "with an empty queue said as such")
check(#buttons(panel, "My group") == 2, "and the card's button (and the empty list's) now opens it")

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

-- The picker counts what is there
dd = picker(panel)
local kara
for _, o in ipairs(dd.options) do if o.value == "karazhan" then kara = o.text end end
check(kara and kara:find("1 forming", 1, true) and kara:find("1 looking", 1, true), "an activity in the picker counts its groups and its players: " .. tostring(kara))

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

-- The picker opens on the dungeons of my level
local function inRange(level)
  local want, seen = {}, {}
  for _, s in ipairs(GuildOS.GroupActivities:Sections("dungeon")) do
    for _, it in ipairs(s.items) do
      if it.min and level >= it.min and level <= it.max and not seen[it.id] then
        seen[it.id] = true
        want[#want + 1] = it.id
      end
    end
  end
  table.sort(want)
  return want
end
-- The ids listed under "For your level", or nil when there is no such section.
local function forYourLevel(d)
  local got, inside = nil, false
  for _, o in ipairs(d.options) do
    if o.disabled then
      if inside then break end
      if o.text == "For your level" then inside, got = true, {} end
    elseif inside then
      got[#got + 1] = o.value
    end
  end
  if got then table.sort(got) end
  return got, d.options[2] and d.options[2].text == "For your level"
end
for _, level in ipairs({ 70, 60 }) do
  UnitLevel = function() return level end
  panel.SelectSub("active")
  local got, first = forYourLevel(picker(panel))
  local want = inRange(level)
  check(#want > 0 and got ~= nil and first, "at level " .. level .. " the picker opens on For your level")
  check(table.concat(got, ",") == table.concat(want, ","),
    "holding exactly the dungeons whose range has level " .. level .. ": " .. table.concat(got, ","))
end
UnitLevel = function() return 5 end
panel.SelectSub("active")
check(forYourLevel(picker(panel)) == nil, "a level no dungeon has shows no For your level")
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
walk(panel, function(f) if f.kind == "ScrollFrame" then f:SetSize(1180, 500) end end)
panel:SetSize(1200, 600)
panel.SelectSub("all")
gr, sr = rectOf(gc, {}), rectOf(sk, {})
check(math.abs(sr.t - gr.t) < 1 and sr.l > gr.r, "from 900px they sit side by side")
check(math.abs((gr.b - gr.t) - (sr.b - sr.t)) < 1 and gr.b - gr.t >= 500 - 1, "as tall as each other, filling the height left")
check(insideCards(panel, "wide") > 20, "and everything stays inside its card")
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
check(forYourLevel(picker(foreverPanel)) ~= nil, "and the picker opens on For your level")
settles(foreverPanel, "in the Forever style")

print(checks .. " checks ok")
