-- The Winter Veil tab's screens (guildos-web#673, the site's specs/122), the real UI/VeilFx.lua, UI/VeilChimney.lua,
-- UI/VeilShelf.lua, UI/WinterVeilPanel.lua and UI/Snow.lua over the real CompanionImport and WinterVeil, under a
-- stubbed client whose frames know when they are visible, fire OnShow/OnHide down the tree, run OnUpdate and play
-- AnimationGroups in simulated time.
-- Proves: the Chimney's level by state (out before the draw, live, frozen after the deadline, full) and its numbers
-- (the site's odds); at most 64 textures in motion, the peak of a legendary opening included; nothing in motion and no
-- OnUpdate with the window closed or the option off; the opening plays once, only when the opened globe is here and
-- the tab is in view, and starts over if cut short; the caprice tag only for a literal `caprice = true`; the gift box
-- in the wrapped state; the shelf (frames in the rarity's colour, rays only in the detail, scrolling by a row); the
-- sounds inside pcall; every frame a child of the window; every file one the art set has.
--
--   luajit -e 'ADDON="."' tools/veil-ui.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── A client whose frames know when they are visible ──────────────────
local NOW = 1765800000
local GUILD, ME = "Curva-Mor", "Chehul"
function GetServerTime() return NOW end
function GetTime() return 0 end
function time() return NOW end
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Member", 3 end
function GetRealmName() return "Nightslayer" end
function UnitName() return ME end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function date(...) return os.date(...) end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() return nil end

local frames, groups, orphans = {}, {}, 0
local Region = {}
Region.__index = function(_, k)
  local v = rawget(Region, k)
  if v ~= nil then return v end
  -- Unknown methods (capitalised) are no-ops; an unset field is nil, as on a real frame.
  if type(k) == "string" and k:match("^%u") then return function() end end
  return nil
end

local function fire(self, name, ...)
  local s = self.scripts[name]
  if s then s(self, ...) end
  for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
end

local function newRegion(kind, parent)
  local r = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, hooks = {}, children = {},
    alpha = 1, w = 0, h = 0, level = parent and (parent.level or 1) + 1 or 1, text = "" }, Region)
  if parent then table.insert(parent.children, r) end
  return r
end

function Region:IsShown() return self.shown end
function Region:IsVisible()
  local r = self
  while r do
    if not r.shown then return false end
    if r.isRoot then return true end
    r = r.parent
  end
  return false
end
local function visibleKids(self, out)
  for _, c in ipairs(self.children) do
    if c.shown and c.kind == "Frame" then out[#out + 1] = c; visibleKids(c, out) end
  end
  return out
end
function Region:Show()
  if self.shown then return end
  self.shown = true
  if self.kind == "Frame" and self:IsVisible() then
    fire(self, "OnShow")
    for _, c in ipairs(visibleKids(self, {})) do fire(c, "OnShow") end
  end
end
function Region:Hide()
  if not self.shown then return end
  local was = self.kind == "Frame" and self:IsVisible()
  local kids = was and visibleKids(self, {}) or {}
  self.shown = false
  if was then
    fire(self, "OnHide")
    for _, c in ipairs(kids) do fire(c, "OnHide") end
  end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:SetScript(n, fn) self.scripts[n] = fn end
function Region:GetScript(n) return self.scripts[n] end
function Region:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], fn) end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha end
function Region:SetFrameLevel(l) self.level = l end
function Region:GetFrameLevel() return self.level end
function Region:SetPoint(...) self.point = { ... } end
function Region:ClearAllPoints() self.point = nil end
function Region:SetTexture(p) self.texPath = p end
function Region:SetTexCoord(...) self.coords = { ... } end
function Region:SetColorTexture(r, g, b, a) self.color = { r = r, g = g, b = b, a = a } end
function Region:SetVertexColor(r, g, b) self.vcolor = { r = r, g = g, b = b } end
function Region:SetText(t) self.text = t; fire(self, "OnTextChanged", false) end
function Region:GetText() return self.text end
function Region:GetStringHeight() return 14 end
function Region:GetStringWidth() return 60 end
function Region:SetTextColor(r, g, b) self.tcolor = { r = r, g = g, b = b } end
function Region:SetEnabled(v) self.enabled = v end
function Region:IsEnabled() return self.enabled ~= false end
function Region:CreateTexture()
  local t = newRegion("Texture", self)
  return t
end
function Region:CreateFontString()
  return newRegion("FontString", self)
end
function Region:CreateAnimationGroup()
  local region = self
  local ag = { region = region, anims = {}, scripts = {}, playing = false, elapsed = 0 }
  function ag:CreateAnimation(kind)
    local a = { kind = kind, dur = 0, delay = 0, order = 1 }
    function a:SetDuration(d) self.dur = d end
    function a:SetStartDelay(d) self.delay = d end
    function a:SetOrder(o) self.order = o end
    setmetatable(a, { __index = function() return function() end end })
    table.insert(self.anims, a)
    return a
  end
  function ag:SetLooping(l) self.loop = l end
  function ag:SetToFinalAlpha() end
  function ag:SetScript(n, fn) self.scripts[n] = fn end
  function ag:Play() self.playing = true; self.elapsed = 0 end
  function ag:Stop() self.playing = false end
  function ag:IsPlaying() return self.playing end
  function ag:Total()
    local byOrder = {}
    for _, a in ipairs(self.anims) do byOrder[a.order] = math.max(byOrder[a.order] or 0, a.delay + a.dur) end
    local t = 0
    for _, v in pairs(byOrder) do t = t + v end
    return t
  end
  table.insert(groups, ag)
  return ag
end

function CreateFrame(_, _, parent)
  if parent == nil then orphans = orphans + 1 end
  local f = newRegion("Frame", parent)
  table.insert(frames, f)
  return f
end

local played = {}
function PlaySound(id) played[#played + 1] = id end
local function soundsOf(id) local n = 0; for _, x in ipairs(played) do if x == id then n = n + 1 end end; return n end

GameTooltip = setmetatable({}, { __index = function() return function() end end })

-- ── Guild OS, the parts the tab uses ──────────────────────────────────
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent) if registry[name] or silent then return registry[name] end error("no lib " .. name) end,
  minor = 1,
}, { __call = function(_, name, silent) if registry[name] or silent then return registry[name] end error("no lib " .. name) end })

GuildOS = {
  VERSION = "1.43.4",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
  Client = { isAnniversary = true, defaultRaidSize = 25 },
  Compat = { PlayerName = function() return ME end },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then io.stderr:write("SafeCall: " .. tostring(err) .. "\n"); check(false, "no error inside the tab: " .. tostring(err)) end
  return ok
end
function GuildOS:Print() end
function GuildOS:IsOfficer() return false end
dofile(ADDON .. "/Core/Utils.lua")
GuildOS.SyncService = { Publish = function() end, On = function() end }
dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/WinterVeil.lua")
local Import, WV = GuildOS.CompanionImport, GuildOS.WinterVeil

local function color(r, g, b) return { r = r, g = g, b = b } end
GuildOS.Colors = setmetatable({}, { __index = function() return color(0.5, 0.5, 0.5) end })
GuildOS.QualityColors = GuildOS.Colors

local texts = {}
local UI = {}
local function text(parent, t)
  local fs = parent:CreateFontString()
  fs.text = t or ""
  texts[#texts + 1] = fs
  return fs
end
UI.CreateText = function(_, p, t) return text(p, t) end
UI.CreateTitle = UI.CreateText
UI.CreateHeaderText = UI.CreateText
UI.CreateSectionTitle = UI.CreateText
UI.CreatePanel = function(_, p) return CreateFrame("Frame", nil, p) end
UI.CreateButton = function(_, p, t)
  local b = CreateFrame("Button", nil, p)
  b.label = text(b, t)
  function b:SetText(x) self.label.text = x end
  function b:GetText() return self.label.text end
  return b
end
UI.SetButtonVariant = function() end
UI.CreateTab = function(_, p, t) local b = UI.CreateButton(nil, p, t); b.tabName = t; function b:SetActive(v) self.active = v end; return b end
UI.CreateCheckbox = function(_, p) local f = CreateFrame("Frame", nil, p); f.checkbox = { GetChecked = function() return false end }; return f end
UI.CreateTextArea = function(_, p) local f = CreateFrame("Frame", nil, p); f.edit = CreateFrame("EditBox", nil, f); return f end
UI.CreateMetricChip = function(_, p, v) local f = CreateFrame("Frame", nil, p); f.value = text(f, v); function f:SetValue(x) self.value.text = x end; return f end
GuildOS.UI = UI

dofile(ADDON .. "/UI/Spacing.lua"); UI.SP = GuildOS.Spacing   -- the spacing standard (#449)
for _, f in ipairs({ "VeilFx", "VeilChimney", "VeilShelf", "WinterVeilPanel", "Snow" }) do dofile(ADDON .. "/UI/" .. f .. ".lua") end
local Fx, Chimney, Shelf, Snow = GuildOS.VeilFx, GuildOS.VeilChimney, GuildOS.VeilShelf, GuildOS.Snow

-- ── Blocks ────────────────────────────────────────────────────────────
local function pack(fmt, t)
  return fmt .. ":" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local ME_KEY = "Chehul-Nightslayer"
local function veil(extra)
  local v = { year = 2025, joinUntil = NOW - 86400, wrapUntil = NOW + 5 * 86400, openAt = NOW + 6 * 86400, reassignDays = 3,
              drawn = true, chimney = 62, counts = { entrants = 16, wrapped = 9, pairs = 16, opened = 0 } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
local function inbox(gild, personal)
  GuildOSInbox = {}
  if gild then GuildOSInbox[#GuildOSInbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, veil = gild }) end
  if personal then
    local p = { fmt = "GOSVEIL1", v = 2, guild = GUILD, realm = "Nightslayer", at = NOW - 60, year = 2025, mine = {}, collection = {} }
    for k, x in pairs(personal) do p[k] = x end
    GuildOSInbox[#GuildOSInbox + 1] = pack("GOSVEIL1", p)
  end
  Import._blockRaw, Import._veilRaw = nil, nil
end
local function personal(gives, got, extra)
  local p = { mine = { { key = ME_KEY, volunteer = false, gives = gives or {}, got = got } } }
  for k, x in pairs(extra or {}) do p[k] = x end
  return p
end

-- ── Time ──────────────────────────────────────────────────────────────
local maxMoving, maxUpdates = 0, 0
local function countUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate and f:IsVisible() then n = n + 1 end end
  return n
end
local function playingGroups()
  local n = 0
  for _, g in ipairs(groups) do if g.playing then n = n + 1 end end
  return n
end
local function advance(sec, step)
  step = step or 0.05
  local t = 0
  while t < sec - 1e-9 do
    t = t + step
    NOW = NOW -- the server clock stands still: nothing here depends on it
    for _, f in ipairs(frames) do
      local u = f.scripts.OnUpdate
      if u and f:IsVisible() then u(f, step) end
    end
    for _, g in ipairs(groups) do
      if g.playing and g.region:IsVisible() then
        g.elapsed = g.elapsed + step
        local total = g:Total()
        if g.elapsed >= total then
          if g.loop then g.elapsed = g.elapsed - math.max(total, step)
          else
            g.playing = false
            if g.scripts.OnFinished then g.scripts.OnFinished(g) end
          end
        end
      end
    end
    maxMoving = math.max(maxMoving, Fx.Moving())
    maxUpdates = math.max(maxUpdates, countUpdates())
  end
end
local function said(t)
  for _, fs in ipairs(texts) do
    if fs:IsVisible() and type(fs.text) == "string" and fs.text:find(t, 1, true) then return fs end
  end
  return nil
end

-- ── 1. The Chimney's state is the site's number, by phase ─────────────
local e = veil({ drawn = false, joinUntil = NOW + 86400 })
local cs = WV.ChimneyState(e, NOW)
check(cs.state == "off" and cs.pct == nil, "before the draw the Chimney is out")
cs = WV.ChimneyState(veil(), NOW)
check(cs.state == "live" and cs.pct == 62 and not cs.full, "while wrapping it is live at the site's share")
check(cs.wrappedPct == 56 and cs.questPct == 6, "the quests' slice is the share the wrapped globes do not explain: " .. cs.wrappedPct .. "/" .. cs.questPct)
cs = WV.ChimneyState(veil({ chimney = 100 }), NOW)
check(cs.state == "full" and cs.full, "100% while wrapping is full")
cs = WV.ChimneyState(veil({ wrapUntil = NOW - 10, chimney = 71 }), NOW)
check(cs.state == "frozen" and cs.pct == 71, "after the deadline it is frozen at the site's number")
cs = WV.ChimneyState(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10, chimney = 100 }), NOW)
check(cs.state == "frozen" and cs.full, "at the opening it stays frozen, full if it closed full")
cs = WV.ChimneyState(veil({ counts = { entrants = 0, wrapped = 0, pairs = 0, opened = 0 }, chimney = 0 }), NOW)
check(cs.state == "live" and cs.pct == 0 and cs.questPct == 0, "an empty event is live at zero, with no slice")

-- The odds are the site's (lib/veil-rules.ts rarityOf: cuts 60/85/97, full 20/70/94).
local function cuts(o) return { o[1], o[1] + o[2], o[1] + o[2] + o[3], o[1] + o[2] + o[3] + o[4] } end
local b, f = cuts(Chimney.ODDS), cuts(Chimney.ODDS_FULL)
check(b[1] == 60 and b[2] == 85 and b[3] == 97 and b[4] == 100, "the base odds are the site's cuts")
check(f[1] == 20 and f[2] == 70 and f[3] == 94 and f[4] == 100, "the full odds are the site's cuts")

-- The drawing by level.
local lay = Chimney.Layout(nil)
check(lay.hot == 0 and lay.fire == 0 and lay.embers == 0 and not lay.lit, "out: no heat, no fire, no embers")
lay = Chimney.Layout(62)
check(math.abs(lay.hot - (6 + 62 * 3.58)) < 1e-6 and lay.embers == 8 and lay.smoke == 3 and lay.stars == 0, "62%: the prototype's heat, 8 embers, 3 puffs")
lay = Chimney.Layout(100)
check(lay.fire == 140 and lay.embers == Chimney.EMBERS_MAX and lay.stars == Chimney.STARS and lay.full, "full: the big fire, every ember, the stars")

-- ── 2. The tab in the window ──────────────────────────────────────────
local win = CreateFrame("Frame", nil, nil)
win.isRoot = true
local orphansBefore = orphans
local container = CreateFrame("Frame", nil, win)
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", toClass = "MAGE", wrapped = false } }))
local panel = GuildOS:CreateWinterVeilPanel(container)
check(orphans == orphansBefore, "every frame the tab makes is a child of the window, none of UIParent's")
Snow.CUTOFF_AT, Snow.END_AT = NOW - 10, NOW + 30 * 86400
Snow:Attach(win)
panel:Hide(); panel:Show()
advance(1.2)
local ch = panel.chimney
check(ch.hot:IsShown() and math.abs(ch.hot.h - (6 + 62 * 3.58)) < 0.5, "the hot drawing shows up to the level after the 0.9 s transition")
check(math.abs(ch.hot.coords[3] - (1 - ch.hot.h / 512)) < 1e-6 and ch.hot.coords[4] == 1, "clipped by SetTexCoord from the bottom up")
check(math.abs(ch.cold.coords[3] - 84 / 512) < 1e-6 and ch.cold.coords[4] == 1, "the cold drawing is the bottom 428 px of its file")
check(ch.flip.running, "the fire's flipbook runs")
check(ch.plateText.text == "62%", "the plate says the share")
check(said("62% of the pairs wrapped or played the event") ~= nil, "the caption says the share wrapped or played")
check(said("+6% quests") ~= nil, "and the quests' slice, apart")
check(said("ODDS AT THE OPENING") and ch.labels[1].text == "60%" and ch.labels[4].text == "3%", "the odds at the opening are the base ones")
local embersOn = 0
for _, em in ipairs(ch.embers) do if em.g.playing then embersOn = embersOn + 1 end end
check(embersOn == 8, "8 embers rise at 62%: " .. embersOn)
check(Fx.Moving() <= Fx.BUDGET, "within the ceiling: " .. Fx.Moving())
check(countUpdates() <= 2, "two OnUpdate at most once the transition ended (snow, fire): " .. countUpdates())
local frame1 = ch.flip.frame
advance(0.5)
local stepped = (ch.flip.frame - frame1) % Fx.FIRE_FRAMES
check(stepped >= 4 and stepped <= 6, "the flipbook steps at 10 Hz: " .. stepped .. " frames in 0.5 s")
local l1, r1 = ch.f1.coords[1], ch.f1.coords[2]
local l2, r2 = ch.f2.coords[1], ch.f2.coords[2]
check(l2 > r2 and l1 < r1, "the back flame is the same atlas, mirrored")

-- ── 3. Full: three times, once ────────────────────────────────────────
local celebrated = 0
local orig = Chimney.Celebrate
Chimney.Celebrate = function(self) celebrated = celebrated + 1; return orig(self) end
inbox(veil({ chimney = 100 }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
panel.Draw()
advance(1.2)
check(celebrated == 1 and WV:Seen("chimneyFull"), "the Chimney filling is celebrated once")
check(ch.plateText.text == "FULL" and said("DOUBLE ODDS") and ch.labels[1].text == "20%" and ch.labels[2].text == "50%"
  and ch.labels[3].text == "24%" and ch.labels[4].text == "6%", "the plate says FULL and the odds move to 20/50/24/6")
check(said("The Chimney is full!") ~= nil, "Frimm says so")
check(soundsOf(Fx.SOUND.full) == 1, "with the sound, once")
panel.Draw(); panel:Hide(); panel:Show(); advance(0.5)
check(celebrated == 1, "and not again")
check(maxMoving <= Fx.BUDGET, "full, with the snow and the stars, still within the ceiling: " .. maxMoving)

-- ── 4. Out before the draw; frozen after the deadline ─────────────────
inbox(veil({ drawn = false, joinUntil = NOW + 86400, chimney = nil }), { mine = {} })
panel.Draw()
advance(1)
check(not ch.hot:IsShown() and not ch.flip.running and ch.plateText.text == "—", "before the draw: cold, no fire, a dash on the plate")
check(said("Lights at the draw") ~= nil, "and it says it lights at the draw")
local anyEmber = false
for _, em in ipairs(ch.embers) do anyEmber = anyEmber or em.g.playing end
check(not anyEmber, "no ember rises")
check(said("Join the Secret Santa") ~= nil and said("The workshop is open!") ~= nil, "the joining screen, with Frimm's line")
-- GOSVEIL1 alone (no GOSGILD1): its `event` draws the same joining screen, and joining works from it.
inbox(nil, { mine = {}, event = veil({ drawn = false, joinUntil = NOW + 86400, chimney = 0 }) })
panel.Draw()
check(said("Join the Secret Santa") ~= nil, "with GOSVEIL1 alone the joining screen shows")
check(WV:Join(false) == true and WV:Joined(), "and I join from it")
GuildOS.db.winterVeil.people = {}
inbox(veil({ wrapUntil = NOW - 10, openAt = NOW + 86400, chimney = 71 }), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "fire" } }))
panel.Draw()
advance(1)
check(said("Closed at 71%") ~= nil and ch.flip.running, "frozen: it says where it closed, and keeps burning")

-- ── 5. The wrapped state: the gift box and the countdown ──────────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "fire", note = "Que o seu totem nunca caia" } }))
panel.Draw()
local box
for _, fr in ipairs(frames) do
  if fr:IsVisible() then
    for _, c in ipairs(fr.children) do
      if c.kind == "Texture" and c.texPath == Fx.PATH.giftbox256 and c:IsVisible() then box = c end
    end
  end
end
check(box ~= nil, "wrapped: a gift box shows, not a wrapped globe")
check(said("WRAPPED") and said("Que o seu totem nunca caia") and said("UNTIL THE OPENING"), "with the note as a card and the countdown")
check(said("Wrap again") ~= nil, "and the button to wrap again while wrapping is open")

-- The wrapping itself: the box closes over the globe in about 1.1 s, then the wrapped state.
GuildOS.db.winterVeil.wraps = {}
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
panel.Draw()
local wrapBtn
for _, fs in ipairs(texts) do if fs.text == "Wrap" and fs:IsVisible() then wrapBtn = fs.parent end end
check(wrapBtn ~= nil, "the wrap button is there")
local before = soundsOf(Fx.SOUND.wrap)
wrapBtn.scripts.OnClick(wrapBtn)
check(soundsOf(Fx.SOUND.wrap) == before + 1, "wrapping plays its sound")
advance(2)
check(said("WRAPPED") ~= nil, "after the animation the wrapped box shows")

-- ── 6. Closing the window stops everything ────────────────────────────
win:Hide()
check(Fx.Moving() == 0 and playingGroups() == 0, "window closed: nothing in motion, no group playing")
check(countUpdates() == 0, "and no OnUpdate")
local anyUpdate = false
for _, fr in ipairs(frames) do if fr.scripts.OnUpdate and fr ~= Snow.full and fr ~= Snow.corner then anyUpdate = anyUpdate or (fr == ch.flip.driver) end end
check(not anyUpdate, "the flipbook's OnUpdate is removed, not just hidden")
win:Show()
advance(1)
check(ch.flip.running and Fx.Moving() > 0, "opened again, it moves again")

-- ── 7. The option off stops it all ────────────────────────────────────
Snow:SetEnabled(false)
check(Fx.Moving() == 0 and playingGroups() == 0 and Snow:Moving() == 0, "the option off: nothing in motion, the snow included")
panel.Draw()
advance(1)
check(Fx.Moving() == 0 and playingGroups() == 0 and not ch.flip.running, "and a redraw does not start anything")
check(ch.hot:IsShown(), "the Chimney still shows its level, standing still")
Snow:SetEnabled(true)
advance(1)
check(ch.flip.running, "the option on: it burns again")

-- ── 8. The opening: one click, the ceremony once when the globe is here ──
local OPEN = { wrapUntil = NOW - 86400, openAt = NOW - 10, chimney = 100 }
GuildOS.db.winterVeil.opens = {}
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer", rarity = "rare" } }, { ready = true }))
panel.Draw()
advance(0.2)
check(said("Somebody in the guild wrapped a globe for you.") and said("Open the globe") and said("Yours for"), "the gift box I got, the button, and the rarity of mine")
local openBtn
for _, fs in ipairs(texts) do if fs.text == "Open the globe" and fs:IsVisible() then openBtn = fs.parent end end
openBtn.scripts.OnClick(openBtn)
check(WV:OpenRequested(), "one click asks the site")
check(said("Went to fetch it from the site") and said("Asked: waiting for the site"), "Frimm goes to fetch it")
check(soundsOf(Fx.SOUND.shake) == 0, "no ceremony before the globe is here")

-- The opened globe arrives (the companion's next sync) while the tab is not in view: nothing plays yet.
local LEG = { id = "g1", year = 2025, scene = "cabin", rarity = "legendary", openedAt = NOW - 5, from = "Kaelthos-Nightslayer",
              note = "Que a sua lareira nunca apague e o seu loot nunca seja de pano.", caprice = true }
panel:Hide()
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer", rarity = "rare" } }, { ready = true, ornament = LEG }))
check(soundsOf(Fx.SOUND.shake) == 0 and not WV:Seen("open:g1"), "hidden: it waits")
maxMoving = 0
panel:Show()
check(soundsOf(Fx.SOUND.shake) == 1, "in view: the ceremony starts, the ribbon falls")
-- Cut short: it starts over next time, from the box.
advance(1)
panel:Hide()
check(Fx.Moving() == Snow:Moving() and playingGroups() == 0 and not WV:Seen("open:g1"), "hidden mid-way: everything of the tab stops (the window's snow is the window's), and it is not marked seen")
panel:Show()
advance(12)
check(soundsOf(Fx.SOUND.shake) == 2, "shown again, it played from the start")
check(WV:Seen("open:g1"), "and, played to the end, it is seen")
check(soundsOf(Fx.SOUND.step) == 4, "a legendary climbs four steps: wood, silver, gold, crystal: " .. soundsOf(Fx.SOUND.step))
check(soundsOf(Fx.SOUND.big) == 1, "with the big reveal's sound")
check(said("LEGENDARY") and said("From Kaelthos") and said("Que a sua lareira nunca apague"), "the result: the rarity, who gave it, the note")
check(said("caprice note: drawn twice") ~= nil, "the caprice tag, for caprice = true")
check(said("Chimney full: double odds") ~= nil, "and the full Chimney's")
check(maxMoving <= Fx.BUDGET, "the legendary peak stays within the ceiling: " .. maxMoving)
check(maxUpdates <= 3, "never more than the snow, the fire and a transition's OnUpdate: " .. maxUpdates)
local shakes = soundsOf(Fx.SOUND.shake)
panel.Draw(); panel:Hide(); panel:Show(); advance(3)
check(soundsOf(Fx.SOUND.shake) == shakes, "it plays once: not again on the next look")

-- A common one: one step, and no caprice tag when the block does not say true.
local COM = { id = "g2", year = 2025, scene = "tree", rarity = "common", openedAt = NOW - 5, from = "Kaelthos-Nightslayer", caprice = "true" }
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = COM }))
check(WV:Got().ornament.caprice == nil, "caprice that is not a literal true is false")
local steps = soundsOf(Fx.SOUND.step)
panel.Draw()
advance(6)
check(soundsOf(Fx.SOUND.step) == steps + 1 and WV:Seen("open:g2"), "a common stops at the first step")
check(said("caprice note: drawn twice") == nil, "and shows no caprice tag")
local plain = { id = "g3", year = 2025, scene = "tree", rarity = "rare", openedAt = NOW - 5 }
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = plain }))
check(WV:Got().ornament.caprice == nil, "absent caprice is false")

-- With the option off the result shows at once, and counts as seen.
Snow:SetEnabled(false)
local EPIC = { id = "g4", year = 2025, scene = "fire", rarity = "epic", openedAt = NOW - 5 }
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = EPIC }))
shakes = soundsOf(Fx.SOUND.shake)
panel.Draw()
check(said("Epic") and WV:Seen("open:g4") and soundsOf(Fx.SOUND.shake) == shakes and playingGroups() == 0, "option off: the result at once, no ceremony, nothing moving")
Snow:SetEnabled(true)

-- Frimm's globe always counts as a caprice note.
local HOST = { id = "g5", year = 2025, scene = "snowman", rarity = "rare", openedAt = NOW - 5, host = true }
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = HOST }))
Snow:SetEnabled(false); panel.Draw(); Snow:SetEnabled(true)
check(said("caprice note: drawn twice") ~= nil and said("Frimm, the host") ~= nil, "Frimm's globe shows the caprice tag")

-- The extras of the site's block, when it sends them: clues on the box, my guess, their thanks, badges.
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer", rarity = "epic", thanks = "Amei o globo!" } },
  { ready = true, clues = { "Toca flauta", "Mora em |cffff0000Lua Cheia|r", "uma terceira" }, guess = "Kaelthos-Nightslayer" }))
local got = WV:Got()
check(#got.clues == 2 and not got.clues[2]:find("|", 1, true), "two clues at most, made inert")
GuildOS.db.winterVeil.opens = {}
panel.Draw()
check(said("CLUES FROM WHOEVER WRAPPED IT") and said("Toca flauta"), "the clues show on the box")
check(said("Your guess: Kaelthos") and said('Thalindra thanked you: "Amei o globo!"'), "my guess and their thanks show")
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true }))
panel.Draw()
check(said("CLUES FROM") == nil and said("Your guess") == nil and said("thanked you") == nil, "absent, nothing of them shows")
local B = { id = "g6", year = 2025, scene = "tree", rarity = "common", openedAt = NOW - 5, badges = { "first-of-guild", "bad|badge" } }
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = B }))
check(#WV:Got().ornament.badges == 1, "a badge that is not a plain word is dropped")

-- ── The caprice hint: 40 characters and 6 different letters ───────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
GuildOS.db.winterVeil.wraps = {}
local tabMineFirst
for _, fs in ipairs(texts) do if fs.text == "My secret friend" then tabMineFirst = fs.parent end end
tabMineFirst.scripts.OnClick(tabMineFirst)
panel.Draw()
local box
for _, fr in ipairs(frames) do if fr.kind == "Frame" and fr.edit == nil and fr.parent and rawget(fr.parent, "edit") == fr then box = fr end end
check(box ~= nil, "the note box is there")
box:SetText(string.rep("ab ", 14))
check(said("needs 6 different letters") ~= nil, "40 characters of two letters is not a caprice note")
box:SetText("Que o seu totem nunca caia na hora errada!")
check(said("drawn twice and the better one stays") ~= nil, "40 characters and enough letters is one")

-- ── Two pairs: the form follows the pair ──────────────────────────────
GuildOS.db.winterVeil.wraps = {}
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "fire", note = "Para a maga" },
                         { to = "Gorbash-Nightslayer", extra = true, wrapped = true, scene = "mountain", note = "Para o urso" } }))
local wrapAgain
for _, fs in ipairs(texts) do if fs.text == "Wrap again" and fs:IsVisible() then wrapAgain = fs.parent end end
panel.Draw()
for _, fs in ipairs(texts) do if fs.text == "Wrap again" and fs:IsVisible() then wrapAgain = fs.parent end end
wrapAgain.scripts.OnClick(wrapAgain)
check(box:GetText() == "Para a maga", "the form opens on the first pair's note")
local rowGorbash
for _, fs in ipairs(texts) do if fs.text == "Gorbash" and fs:IsVisible() then rowGorbash = fs.parent end end
rowGorbash.scripts.OnClick(rowGorbash)
check(box:GetText() == "Para o urso", "picking the other pair brings its note")
check(panel.chimney ~= nil and said("Wrap again") ~= nil, "and its button")

-- ── A wrap the site has not confirmed yet ─────────────────────────────
local tabChain
for _, fs in ipairs(texts) do if fs.text == "The guild's chain" then tabChain = fs.parent end end
tabChain.scripts.OnClick(tabChain); tabMineFirst.scripts.OnClick(tabMineFirst)
GuildOS.db.winterVeil.wraps = { ["Thalindra-Nightslayer"] = { scene = "tree", note = "", at = NOW } }
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
panel.Draw()
check(said("Waiting to sync") ~= nil, "a wrap made here and not on the site yet says it waits to sync")
inbox(veil({ wrapUntil = NOW + 3600, openAt = NOW + 86400 }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
panel.Draw()
check(said("closes in less than a day") ~= nil, "near the deadline it says so louder")
inbox(veil({ wrapUntil = NOW + 3 * 86400 + 3600, openAt = NOW + 5 * 86400 }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
panel.Draw()
check(said("hands the unwrapped pairs to somebody else") ~= nil and said("closes in less than a day") == nil,
  "near the reassignment (WinterVeil.SyncWarningAt), it says that one")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "tree" } }))
panel.Draw()
check(said("Waiting to sync") == nil and said("Double ribbon") ~= nil, "once the site has it, Frimm is at ease")

-- ── The chain and the officers' table scroll ──────────────────────────
local many = {}
for i = 1, 60 do many[i] = { key = "P" .. i .. "-Nightslayer", wrapped = i % 2 == 0 } end
inbox(veil({ entrants = many }), personal({ { to = "Thalindra-Nightslayer" } }))
GuildOS.IsOfficer = function() return true end
local tabBoard
for _, fs in ipairs(texts) do if fs.text == "Organize" then tabBoard = fs.parent end end
panel.Draw()
tabBoard.scripts.OnClick(tabBoard)
check(said("P1") ~= nil and said("of 60") ~= nil, "sixty entrants: the first rows and where they are")
local list
for _, fs in ipairs(texts) do if fs.text == "P1" and fs:IsVisible() then list = fs.parent.parent end end
for _ = 1, 30 do list.scripts.OnMouseWheel(list, -1) end
check(said("P60") ~= nil and said("P1") == nil, "the wheel reaches the last one")
GuildOS.IsOfficer = function() return false end
tabMineFirst.scripts.OnClick(tabMineFirst)

-- ── 9. The Collection as a shelf ──────────────────────────────────────
check(select(1, Shelf.Window(0, 0)) == 1 and select(2, Shelf.Window(0, 0)) == 6, "an empty shelf shows two rows")
check(select(3, Shelf.Window(7, 5)) == 1, "seven globes scroll by one row at most")
check(select(3, Shelf.Window(4, 3)) == 0, "four do not scroll")
local coll = {}
local rars = { "legendary", "common", "rare", "epic", "common", "rare", "common" }
for i, r in ipairs(rars) do
  coll[i] = { id = "c" .. i, year = 2025, scene = "tree", rarity = r, openedAt = NOW - i * 60, from = "Kaelthos-Nightslayer", note = i == 1 and "Guardei a última brasa" or nil }
end
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = EPIC }, { collection = coll }))
local tabColl
for _, fs in ipairs(texts) do if fs.text == "Collection" then tabColl = fs.parent end end
tabColl.scripts.OnClick(tabColl)
advance(0.5)
local sh = panel.shelf
check(said("COLLECTION · 7") ~= nil, "the shelf says how many")
check(sh.slots[1].item.rarity == "legendary" and sh.slots[1].border.lines[1].color.r == Fx.Rarity("legendary").frame.r, "a globe is framed in its rarity's colour")
check(sh.slots[1].globe.texPath == Fx.GlobePath("tree", "legendary"), "the shelf uses the 128 globes")
check(sh.slots[1].shineG.playing and not sh.slots[2].shineG.playing, "a legendary on the shelf has its band of light, a common does not")
check(sh.rays1G.playing and sh.rays2G.playing, "the legendary selected: two rays in the detail")
check(sh.globe.texPath == Fx.GlobePath("tree", "legendary", true), "the detail is the 256 globe")
check(said("Guardei a última brasa") ~= nil, "and the note as a card")
sh.slots[2].scripts.OnClick(sh.slots[2])
check(not sh.rays1G.playing and not sh.rays2G.playing, "a common selected: no rays")
sh.slots[4].scripts.OnClick(sh.slots[4])
check(sh.rays1G.playing and not sh.rays2G.playing, "an epic: one ray")
local raysOnShelf = 0
for _, s in ipairs(sh.slots) do if s.item and s.item.rarity ~= "legendary" and s.shineG.playing then raysOnShelf = raysOnShelf + 1 end end
check(raysOnShelf == 0, "rays and shine never on a shelf slot that is not legendary")
check(sh.slots[6].item.id == "c6", "two rows: the sixth globe is the last shown")
sh.area.scripts.OnMouseWheel(sh.area, -1)
check(sh.slots[4].item and sh.slots[4].item.id == "c7" and said("next globe") ~= nil, "the wheel moves a row: the seventh shows, and the next empty slot")
check(Fx.Moving() <= Fx.BUDGET, "the shelf within the ceiling")
-- Leaving the Collection stops its effects.
local tabMine
for _, fs in ipairs(texts) do if fs.text == "My secret friend" then tabMine = fs.parent end end
tabMine.scripts.OnClick(tabMine)
local shelfOn = sh.rays1G.playing
for _, s in ipairs(sh.slots) do shelfOn = shelfOn or s.shineG.playing end
check(not shelfOn, "another sub-tab: the shelf's rays and shine stop")
inbox(veil(OPEN), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = EPIC }, { collection = {} }))
tabColl.scripts.OnClick(tabColl)
check(said("Empty shelf!") ~= nil, "an empty shelf: Frimm says it wasn't him")

-- ── 10. The ceiling holds, whatever asks ──────────────────────────────
local sc = panel.scope
local extra, refused = {}, 0
for i = 1, 80 do
  local t = panel:CreateTexture()
  extra[i] = sc:Group(t, { { "alpha", 0, 1, 1 } }, { loop = "REPEAT" })
  if not extra[i]:Play() then refused = refused + 1 end
end
check(refused > 0 and Fx.Moving() <= Fx.BUDGET, "past 64 textures a group is refused: " .. Fx.Moving())
for _, g in ipairs(extra) do g:Stop() end

-- ── 11. Sounds: inside pcall, behind their option ─────────────────────
PlaySound = function() error("no such sound") end
check(Fx.Sound("step") == false, "a sound the client does not have fails quietly")
local n = 0
PlaySound = function() n = n + 1 end
GuildOS.db.settings.veilSounds = false
Fx.Sound("step")
check(n == 0, "with the sounds off nothing plays")
GuildOS.db.settings.veilSounds = nil

-- ── 12. The files are the art set's ───────────────────────────────────
local paths = {}
for _, fr in ipairs(frames) do
  for _, c in ipairs(fr.children) do if c.texPath then paths[c.texPath] = true end end
end
local ok = true
for p in pairs(paths) do
  if type(p) ~= "string" then io.stderr:write("texture not a path: " .. tostring(p) .. "\n") end
  local rel = type(p) == "string" and p:match("^Interface\\AddOns\\GuildOS\\Media\\(.+)$")
  local good = rel and (rel:match("^Veil\\[%w%-]+$") or rel:match("^Globes\\[%w]+%-[%w]+$") or rel:match("^Globes\\256\\[%w]+%-[%w]+$")
    or rel == "Globes\\closed" or rel == "Globes\\closed-256")
  if not good then ok = false; io.stderr:write("unexpected texture: " .. p .. "\n") end
end
check(ok, "every texture is one of Media/Veil or Media/Globes")
for _, need in ipairs({ "Veil\\veil-fx", "Veil\\chimney-cold", "Veil\\chimney-hot", "Veil\\frimm", "Veil\\giftbox-256", "Veil\\giftbox-open-256", "Globes\\closed-256" }) do
  check(paths["Interface\\AddOns\\GuildOS\\Media\\" .. need], "the tab uses " .. need)
end
-- The atlas: every piece inside the 512 square, on the layout of addon.md.
for name, p in pairs(Fx.PIECES) do
  check(p[1] >= 0 and p[2] >= 384 and p[1] + p[3] <= 512 and p[2] + p[4] <= 512, "the piece " .. name .. " sits in the atlas's last row")
end
local l, r, t, bt = Fx.FireCoords(8)
check(l == 0.75 and r == 1 and t == 0.25 and bt == 0.5, "the fire's 8th frame is the last of the second row")
l, r, t, bt = Fx.SnowCoords(4)
check(l == 0.75 and t == 0.5 and bt == 0.75, "the snow's 4th frame is the end of the third row")

print(string.format("veil-ui: %d checks passed", checks))
