-- Winter Veil's snow (guildos-web#662), the real UI/Snow.lua under stubbed WoW APIs.
-- Proves: the cutoff (before: corner teaser; from 1 Dec to the end of December: whole window; after: nothing), the
-- `snow` option, the tooltip text, at most 20 flakes, a throttled OnUpdate, and nothing updating with the window closed.
--
--   luajit -e 'ADDON="."' tools/snow.lua
ADDON = ADDON or "."
local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then io.stderr:write("FAIL: " .. what .. "\n"); os.exit(1) end
end

local NOW = 1796094000 - 3600
function time() return NOW end

local function newFrame()
  local f = { shown = false, scripts = {}, hooks = {}, children = {}, w = 200, h = 150, level = 10, textures = {} }
  function f:SetClipsChildren() end
  function f:EnableMouse(v) self.mouse = v end
  function f:Hide() local was = self.shown; self.shown = false; if was then for _, h in ipairs(self.hooks.OnHide or {}) do h(self) end end end
  function f:Show() local was = self.shown; self.shown = true; if not was then for _, h in ipairs(self.hooks.OnShow or {}) do h(self) end end end
  function f:IsShown() return self.shown end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], fn) end
  function f:ClearAllPoints() end
  function f:SetPoint() end
  function f:SetAllPoints() end
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:GetWidth() return self.w end
  function f:GetHeight() return self.h end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:CreateTexture()
    local t = { n = 0 }
    function t:SetColorTexture() end
    function t:ClearAllPoints() end
    function t:SetPoint() self.n = self.n + 1 end
    function t:SetSize() end
    function t:SetShown(v) self.vis = v end
    table.insert(f.textures, t)
    return t
  end
  return f
end
function CreateFrame() local f = newFrame(); return f end

local tip = { lines = {} }
function tip:SetOwner() end
function tip:SetText(t) self.text = t end
function tip:Show() self.shownNow = true end
function tip:Hide() self.shownNow = false end
GameTooltip = tip

GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  UI = {}, db = { settings = {} },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
dofile(ADDON .. "/UI/Snow.lua")
local S = GuildOS.Snow

-- ── 1. The date: one constant, the client's clock ─────────────────────
check(S.CUTOFF_AT == 1796094000, "the cutoff is 2026-12-01 00:00 in São Paulo (03:00 UTC)")
check(S:Phase(S.CUTOFF_AT - 1) == "teaser", "a second before the cutoff: teaser")
check(S:Phase(S.CUTOFF_AT) == "season", "at the cutoff: the whole window")
check(S:Phase(S.END_AT - 1) == "season", "the last second of December: still snowing")
check(S:Phase(S.END_AT) == "off", "from January: nothing")

-- ── 2. The option ─────────────────────────────────────────────────────
check(S:Enabled(), "unset, the snow is on")
check(S:Mode(S.CUTOFF_AT + 5) == "season" and S:Mode(S.CUTOFF_AT - 5) == "teaser", "mode follows the phase")
GuildOS.db.settings.snow = false
check(S:Mode(S.CUTOFF_AT + 5) == nil and S:Mode(S.CUTOFF_AT - 5) == nil, "snow = false turns both off")
GuildOS.db.settings.snow = nil

-- ── 3. Before the cutoff: the corner and its tooltip ──────────────────
local win = newFrame()
S:Attach(win)
check(not S.corner.shown and not S.full.shown and not S.corner.scripts.OnUpdate, "window closed: nothing shown, no OnUpdate")
win:Show()
check(S.corner.shown and not S.full.shown, "before the cutoff the corner panel shows, not the whole window")
check(S.corner.scripts.OnUpdate and not S.full.scripts.OnUpdate, "only the corner animates")
check(S.corner.mouse == true and S.full.mouse == false, "the corner takes the mouse for the tooltip; the full layer lets it through")
check(#S.corner.flakes <= S.MAX_FLAKES and #S.corner.flakes > 0, "the corner has a few flakes")
S.corner.scripts.OnEnter(S.corner)
check(tip.text and tip.text:find("Winter Veil Secret Santa", 1, true) and tip.text:find("Frimm", 1, true), "hover shows the teaser text")
check(tip.shownNow, "the tooltip is shown")
S.corner.scripts.OnLeave(S.corner)
check(not tip.shownNow, "and hidden on leave")

-- ── 4. Throttle ───────────────────────────────────────────────────────
local moved = 0
local orig = S.Step
S.Step = function(...) moved = moved + 1; return orig(...) end
for _ = 1, 10 do S.corner.scripts.OnUpdate(S.corner, 0.01) end
check(moved == 2, "ten 10 ms frames step twice (about every 0.05 s), not ten times: " .. moved)
S.Step = orig

-- ── 5. Closing the window stops everything ────────────────────────────
win:Hide()
check(not S.corner.scripts.OnUpdate and not S.full.scripts.OnUpdate and not S.corner.shown, "closed: no OnUpdate, nothing shown")

-- ── 6. From the cutoff: the whole window, 20 flakes at most ───────────
NOW = S.CUTOFF_AT + 60
win:Show()
check(S.full.shown and not S.corner.shown, "from the cutoff the whole window snows and the corner stops")
check(S.full.scripts.OnUpdate and not S.corner.scripts.OnUpdate, "only the full layer animates")
check(#S.full.flakes == S.MAX_FLAKES and S.MAX_FLAKES <= 20, "at most 20 flakes")
local visible = 0
for _, fl in ipairs(S.full.flakes) do if fl.tex.vis then visible = visible + 1 end end
check(visible <= 20, "no more than 20 visible textures")
local before = S.full.flakes[1].y
S.full.scripts.OnUpdate(S.full, 0.2)
check(S.full.flakes[1].y ~= before or S.full.flakes[1].x ~= 0, "flakes move")
for _ = 1, 400 do S.full.scripts.OnUpdate(S.full, 0.05) end
local inside = true
for _, fl in ipairs(S.full.flakes) do if fl.y > S.full.h + 1 or fl.x > S.full.w + 1 then inside = false end end
check(inside, "flakes recycle at the bottom and stay in the window")

-- ── 7. The option, live ───────────────────────────────────────────────
S:SetEnabled(false)
check(not S.full.shown and not S.full.scripts.OnUpdate, "turning it off stops the snow at once")
check(GuildOS.db.settings.snow == false, "and is saved in the settings")
S:SetEnabled(true)
check(S.full.shown and S.full.scripts.OnUpdate, "turning it on brings it back")

-- ── 8. After December ─────────────────────────────────────────────────
win:Hide()
NOW = S.END_AT + 1
win:Show()
check(not S.full.shown and not S.corner.shown and not S.full.scripts.OnUpdate, "in January: nothing")

-- ── 9. The snow reads no guild data ───────────────────────────────────
local f = io.open(ADDON .. "/UI/Snow.lua"); local src = f:read("*a"); f:close()
check(not src:find("CompanionImport") and not src:find("GetGuildRosterInfo") and not src:find("WinterVeil%.") , "no guild data in Snow.lua")

print("ok " .. checks .. " checks")
