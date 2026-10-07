-- Interface styles (issue #122, spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §4), run
-- against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Style.lua,
-- UI/Helpers.lua and Core/Commands.lua under a stubbed client.
--
-- Two styles: "guildos", the flat look the addon was made with, painting exactly as it always did;
-- "forever", the WoW: Forever client's own -c60 art, offered only where the client has it. The
-- account's choice is read at load; a style the client cannot draw falls back to guildos, said once.
--
--   luajit -e 'ADDON="."' tools/style.lua
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

-- The Forever client's -c60 atlases, as wago.tools lists them for build 1.60.1.70235.
local ATLAS = {}
for line in io.lines(ADDON .. "/tools/data/forever-c60-atlases.txt") do
  if line ~= "" and not line:find("^#") then ATLAS[line:lower()] = true end
end
local SIZES = {}   -- the sizes the tests rely on, from the same table
SIZES["ui-frame-metal-cornertopleft-c60-2x"] = { 190, 190 }
SIZES["128-redbutton-left-c60"], SIZES["128-redbutton-right-c60"] = { 114, 128 }, { 292, 128 }

-- ── A client: frames and textures that remember what was done to them ────
local function newRegion(kind, parent)
  local r = { kind = kind, parent = parent, children = {}, points = {}, scripts = {}, w = 0, h = 0, shown = true }
  if parent then parent.children[#parent.children + 1] = r end
  return setmetatable(r, { __index = function(_, k)
    if k:match("^[a-z_]") then return nil end   -- a field nobody set is nil; only methods answer
    return function(self, ...)
      local a = { ... }
      if k == "SetAtlas" then self.atlas = a[1]
      elseif k == "SetHorizTile" then self.horizTile = a[1]
      elseif k == "SetVertTile" then self.vertTile = a[1]
      elseif k == "SetTexture" then self.texture = a[1]
      elseif k == "SetVertexColor" or k == "SetTextColor" or k == "SetColorTexture" then self.color = a
      elseif k == "SetBackdrop" then self.backdrop = a[1]
      elseif k == "SetBackdropColor" then self.bg = a
      elseif k == "SetBackdropBorderColor" then self.border = a
      elseif k == "SetSize" then self.w, self.h = a[1], a[2]
      elseif k == "SetWidth" then self.w = a[1]
      elseif k == "SetHeight" then self.h = a[1]
      elseif k == "GetWidth" then return self.w
      elseif k == "GetHeight" then return self.h
      elseif k == "SetPoint" then self.points[#self.points + 1] = a
      elseif k == "ClearAllPoints" then self.points = {}
      elseif k == "Show" then self.shown = true
      elseif k == "Hide" then self.shown = false
      elseif k == "SetShown" then self.shown = a[1] and true or false
      elseif k == "IsShown" then return self.shown
      elseif k == "SetText" then self.text = a[1]
      elseif k == "GetText" then return self.text
      elseif k == "SetFont" then self.font = a[1]; return true
      elseif k == "GetStringWidth" then return #(self.text or "") * 6
      elseif k == "SetScript" then self.scripts[a[1]] = a[2]
      elseif k == "HookScript" then
        local prev = self.scripts[a[1]]
        self.scripts[a[1]] = prev and function(...) prev(...); a[2](...) end or a[2]
      elseif k == "GetScript" then return self.scripts[a[1]]
      elseif k == "CreateTexture" or k == "CreateFontString" then return newRegion(k, self)
      elseif k == "IsEnabled" then return self.enabled ~= false
      elseif k == "Enable" then self.enabled = true
      elseif k == "Disable" then self.enabled = false
      elseif k == "IsMouseOver" then return false
      elseif k == "GetFrameLevel" then return 1
      elseif k == "GetChecked" then return self.checked
      elseif k == "SetChecked" then self.checked = a[1]
      end
    end
  end })
end

local printed, errors, popups = {}, {}, {}
local function load(opts)
  opts = opts or {}
  printed, errors, popups = {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  function CreateFrame(kind, _, parent)
    local f = newRegion(kind, parent)
    if kind == "ScrollFrame" then   -- UIPanelScrollFrameTemplate's scroll bar and its children
      local bar = newRegion("Slider", f)
      bar.ScrollUpButton, bar.ScrollDownButton = newRegion("Button", bar), newRegion("Button", bar)
      bar.ThumbTexture = newRegion("Texture", bar)
      bar.GetMinMaxValues = function() return 0, 0 end
      bar.GetValue = function() return 0 end
      f.ScrollBar = bar
    end
    return f
  end
  UIParent = newRegion("Frame")
  function hooksecurefunc() end
  function GetBuildInfo() return "1.60.1", "70235", "", 16001 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName() return "Ana" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1 end
  function IsInGuild() return true end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs, UISpecialFrames, SlashCmdList = {}, {}, {}
  function StaticPopup_Show(which, text) popups[#popups + 1] = { which = which, text = text } end
  function ReloadUI() popups.reloaded = true end
  local without = opts.without or {}
  C_Texture = opts.noArt and {} or { GetAtlasInfo = function(name)
    name = tostring(name):lower()
    if not ATLAS[name] or without[name] then return nil end
    local s = SIZES[name] or { 32, 32 }
    -- "_" pieces tile across and "!" pieces tile down, as the client's atlas flags say.
    return { width = s[1], height = s[2], tilesHorizontally = name:sub(1, 1) == "_",
             tilesVertically = name:sub(1, 1) == "!" }
  end }
  GuildOSDB = opts.db or {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  GuildOS.RecordError = function(_, msg) errors[#errors + 1] = msg end
  GuildOS.db = { settings = {} }
  dofile(ADDON .. "/UI/Helpers.lua")
  dofile(ADDON .. "/UI/StylePreview.lua")
  return GuildOS.Style
end
local function said(fragment)
  for _, m in ipairs(printed) do if m:find(fragment, 1, true) then return true end end
end

-- ── 1. The art the style names is the client's ─────────────────────────
local S = load()
local named = {}
for role, art in pairs(S.FOREVER) do
  for _, n in ipairs(S.AtlasNames(art)) do named[#named + 1] = role .. ": " .. n end
end
local unknown = {}
for _, rn in ipairs(named) do
  local n = rn:match(": (.+)$")
  if not ATLAS[n:lower()] then unknown[#unknown + 1] = rn end
end
check(#named > 40 and #unknown == 0, "every atlas the Forever style names is in the client's table (" ..
  #named .. " named; unknown: " .. table.concat(unknown, ", ") .. ")")

-- ── 2. Which styles a client can draw ──────────────────────────────────
S = load({ noArt = true })
check(S:Has("guildos") and not S:Has("forever"), "a client without the art (Anniversary) draws only guildos")
check(#S:Available() == 1 and S:Available()[1] == "guildos", "and offers only it")
S = load()
check(S:Has("forever") and #S:Available() == 2 and S:Available()[2] == "forever", "the Forever client offers both")
S = load({ without = { ["common-internaltab-c60"] = true } })
check(not S:Has("forever"), "a client missing one of the key atlases does not offer forever")
check(S:Name("guildos") == "GuildOS" and S:Name("forever") == "WoW: Forever" and S:Name("x") == "x",
  "the styles' names are their brands")

-- ── 3. Choosing ────────────────────────────────────────────────────────
S = load()
local ok, why = S:Choose("neon")
check(not ok and why == "unknown" and GuildOSDB.style == nil, "an unknown style is refused, and nothing is saved")
ok = S:Choose("forever")
check(ok and GuildOSDB.style == "forever", "a style the client draws is saved for the account")
S = load({ noArt = true })
ok, why = S:Choose("forever")
check(not ok and why == "unavailable", "forever is refused where the client has no art")

-- ── 4. Resolving at load ───────────────────────────────────────────────
S = load({ db = { style = "forever" }, noArt = true })
check(S:Resolve() == "guildos" and S:Current() == "guildos", "a saved forever on a client without the art falls back")
check(said("WoW: Forever") and said("GuildOS"), "and says so in chat")
S = load({ db = {} })
check(S:Resolve() == "guildos" and #printed == 0, "nothing saved: guildos, silently")
S = load({ db = { style = "forever" } })
check(S:Resolve() == "forever" and S:Current() == "forever", "a saved forever where the art exists is used")

-- ── 5. The palette and the font ────────────────────────────────────────
S = load({ db = {} })
local C = GuildOS.Colors
local GOLD, ACCENT = C.gold, C.accent          -- as a module captures them at load
local flatGold = C.gold.r
S:Resolve()
check(C.gold.r == flatGold and S.gameFont == nil, "guildos leaves the palette and the font as they are")
S = load({ db = { style = "forever" } })
C = GuildOS.Colors
GOLD, ACCENT = C.gold, C.accent
S:Resolve()
check(GOLD.r == 1 and GOLD.g == 0.82 and C.gold == GOLD, "forever re-points gold in place: a captured table sees it")
check(ACCENT.r == 1 and ACCENT.g == 0.82 and ACCENT ~= GOLD, "and the legacy keys follow their token, still their own copies")
check(math.abs(C.accentSoft.a - 0.14) < 1e-9 and math.abs(C.accentDim.r - 0.54) < 1e-9 and C.row2.r == C.bg.r,
  "dimmed and washed aliases are recomputed from the new gold")
check(C.ok.r == 0.490, "status colours keep theirs")
local fs = newRegion("FontString")
GuildOS:ApplyFont(fs, 12)
check(S.gameFont and fs.font == STANDARD_TEXT_FONT, "and every text takes the game's font")

-- ── 6. Painting by role ────────────────────────────────────────────────
S = load({ db = {} }); S:Resolve()
C = GuildOS.Colors
local f = newRegion("Frame")
check(S:Paint(f, "window") == "flat" and f.backdrop.bgFile == "Interface\\Buttons\\WHITE8x8"
  and f.backdrop.edgeFile == "Interface\\Buttons\\WHITE8x8"
  and f.backdrop.edgeSize == 1 and f.bg[1] == C.bg.r and f.border[1] == C.line.r,
  "guildos: a window is today's backdrop, bg with a 1px line")
f = newRegion("Frame")
S:Paint(f, "well")
check(f.bg[1] == C.well.r, "a well is today's inset colour")
f = newRegion("Frame")
check(S:Paint(f, "popup") == "flat" and f.backdrop == nil, "a popup's colours stay its caller's")
f = newRegion("Frame")
S:Paint(f, "titlebar")
check(f.__styleBg and f.__styleBg.color[1] == C.panel.r, "a title bar is today's panel band")

S = load({ db = { style = "forever" } }); S:Resolve()
f = newRegion("Frame")
check(S:Paint(f, "window") == "art" and f.__nine.TopLeftCorner.atlas == "ui-frame-metal-cornertopleft-c60-2x",
  "forever: a window gets the metal frame")
check(f.__nine.TopLeftCorner.w == 190 * 0.25 and f.__nine.RightEdge.atlas == "!ui-frame-metal-edgeright-c60-2x",
  "its corners are the atlas size times the scale, and its edges tile")
check(f.backdrop.bgFile and not f.backdrop.edgeFile and f.bg[1] == GuildOS.Colors.bg.r, "the middle stays the role's colour")
check(f.__nine.TopEdge.horizTile == true and f.__nine.LeftEdge.vertTile == true and not f.__nine.TopLeftCorner.horizTile,
  "edges repeat along their length, as the client's NineSlice does; corners do not")
f = newRegion("Frame")
S:Paint(f, "popup")
check(f.__nine.Center and f.__nine.Center.atlas == "tooltip-nineslice-center-c60", "a popup gets the tooltip art and its centre")
f = newRegion("Frame"); f.w, f.h = 200, 30
S:Paint(f, "titlebar")
check(f.__three.Center.horizTile == true, "a title bar's middle repeats across")
check(f.__three.Left.atlas == "ui-frame-diamondmetal-header-cornerleft-c60-2x" and f.__styleBg,
  "a title bar gets the diamond-metal band over its colour")

S = load({ db = { style = "forever" }, without = { ["_ui-frame-metal-edgetop-c60-2x"] = true } }); S:Resolve()
f = newRegion("Frame")
local first = S:Paint(f, "window")
S:Paint(newRegion("Frame"), "window")
check(first == "flat" and f.backdrop.edgeSize == 1, "a missing atlas paints that piece flat, never a hole")
check(#errors == 1 and errors[1]:find("_ui-frame-metal-edgetop-c60-2x", 1, true),
  "and is recorded once, however often it is asked for")

-- ── 7. The controls, through the real Helpers ──────────────────────────
S = load({ db = {} }); S:Resolve()
local UI = GuildOS.UI
local b = UI:CreateButton(UIParent, "Go", 120, 26)
check(not b.__forever and b.backdrop.edgeSize == 1, "guildos: a button is today's bordered backdrop")

S = load({ db = { style = "forever" } }); S:Resolve()
UI = GuildOS.UI
b = UI:CreateButton(UIParent, "Go", 120, 26)
check(b.__forever and b.__three.Left.atlas == "128-redbutton-left-c60", "forever: a button is the game's red button")
UI:_ButtonState(b, "pressed")
check(b.__three.Center.atlas == "_128-redbutton-center-pressed-c60", "pressed swaps to the pressed art")
UI:_ButtonState(b, "disabled")
check(b.__three.Right.atlas == "128-redbutton-right-disabled-c60" and b.label.color[1] == GuildOS.Colors.disabled.r,
  "disabled swaps to the disabled art and dims the label")
UI:_ButtonState(b, "hover")
check(b.__three.Left.atlas == "128-redbutton-left-c60" and b.label.color[1] == GuildOS.Colors.text.r, "hover lights the label")
UI:SetButtonVariant(b, "ghost")
check(not b.__three.Left.shown, "a ghost button has no art")
b:SetBaseColor(0.2, 0.6, 0.2, 1)
check(true, "a toggle's SetBaseColor does not raise in forever")
local narrow = UI:CreateButton(UIParent, "", 40, 26)
narrow.scripts.OnSizeChanged()
check(math.abs(narrow.__three.Left.w + narrow.__three.Right.w - 40) < 0.01, "a button narrower than both caps squeezes them to fit")

local tab = UI:CreateTab(UIParent, "Roster", 100)
check(tab.__art and tab.__art.atlas == "common-internaltab-c60", "a tab sits on the game's tab art")
tab:SetActive(true)
check(tab.__art.atlas == "common-internaltab-selected-c60" and tab.underline.shown, "the open one is the selected art, with its gold rule")
tab:SetActive(false); tab.scripts.OnEnter(tab)
check(tab.__art.atlas == "common-internaltab-hover-c60", "hovered, the hover art")

local cbf = UI:CreateCheckbox(UIParent, "Sound", 16)
local hasBox, hasMark = false, false
for _, t in ipairs(cbf.checkbox.children) do
  if t.atlas == "checkbox-minimal-c60" then hasBox = true end
  if t.atlas == "talents-checkmark-c60" then hasMark = true end
end
check(hasBox and hasMark, "a checkbox is the game's box and mark")
local box
for _, t in ipairs(cbf.checkbox.children) do if t.atlas == "checkbox-minimal-c60" then box = t end end
cbf.checkbox.scripts.OnMouseDown(cbf.checkbox); cbf.checkbox.scripts.OnMouseUp(cbf.checkbox)
check(box.color[1] == 1 and box.color[2] == 1 and box.color[3] == 1, "a click leaves the box's art its own colour")

local close = UI:CreateCloseButton(UIParent)
check(close.__art and close.__art.atlas == "128-redbutton-exit-c60" and not close.x.shown, "the close button is the game's exit button")
S:SkinClose(close, "minimise")
check(close.__art.atlas == "128-redbutton-minus-c60", "and the minimise button its minus")

local sp = newRegion("Frame"); sp.ScrollBar = newRegion("Slider", sp)
sp.ScrollBar.GetMinMaxValues = function() return 0, 0 end
sp.ScrollBar.GetValue = function() return 0 end
-- The template's own children, which the skin hides.
sp.ScrollBar.ScrollUpButton, sp.ScrollBar.ScrollDownButton = newRegion("Button"), newRegion("Button")
sp.ScrollBar.ThumbTexture = newRegion("Texture")
UI:SkinScrollBar(sp)
local track, thumb
for _, t in ipairs(sp.ScrollBar.children) do
  if t.atlas == "!minimal-scrollbar-track-middle-c60" then track = t end
  if t.atlas == "minimal-scrollbar-thumb-middle-c60" then thumb = t end
end
check(track and thumb, "a scroll bar is the game's minimal track and thumb")

local panel = UI:CreatePanel(UIParent)
check(panel.__nine and panel.__nine.TopLeftCorner.atlas == "ui-frame-metal-cornertopleft-c60-2x", "CreatePanel is the metal window")
local inner = UI:CreatePanel(UI:CreatePanel(UIParent))
check(inner.__nine.TopLeftCorner.atlas == "optionsframe-nineslice-cornertopleft-c60",
  "a panel inside another frame is a panel, not a window")
local small = UI:CreatePanel(UIParent)
small.w, small.h = 320, 28
small.scripts.OnSizeChanged(small)
check(not small.__nine.TopLeftCorner.shown and small.backdrop.edgeSize == 1, "a frame too small for the corners paints flat")
small.w, small.h = 600, 400
small.scripts.OnSizeChanged(small)
check(small.__nine.TopLeftCorner.shown and not small.backdrop.edgeFile, "and gets the art back when it grows")
local dark = UI:CreateDarkPanel(UIParent)
check(dark.__nine and dark.__nine.TopLeftCorner.atlas == "optionsframe-nineslice-cornertopleft-c60", "CreateDarkPanel is the inset frame")
local pop = UI:CreatePanel(UIParent)
UI:StylePopup(pop, { noShadow = true, noFade = true })
check(pop.__nine.TopLeftCorner.atlas == "tooltip-nineslice-cornertopleft-c60", "a popup takes the tooltip art")

-- ── 7b. Initialize settles the style; the Settings picker ─────────────
S = load({ db = { style = "forever" } })
GuildOS:Initialize()
check(S:Current() == "forever" and GuildOS.Colors.gold.r == 1, "Initialize settles the saved style before anything is drawn")
local host = newRegion("Frame")
local y = S:BuildPicker(host, 100)
local applies, longDesc = {}, nil
for _, c in ipairs(host.children) do
  if c.label and (c.label.text == "Apply" or c.label.text == "In use") then applies[#applies + 1] = c end
  if c.text == S:Description("forever") then longDesc = c end
end
check(#applies == 2 and y > 100, "the picker lists each style the client draws, with its button")
check(applies[1].label.text == "Apply" and applies[2].label.text == "In use" and applies[2].enabled == false,
  "the one in use says so and cannot be pressed")
check(longDesc and longDesc.w > 0 and longDesc.w < 380 - 16, "a description wraps short of the button")
applies[1].scripts.OnClick(applies[1])
check(GuildOSDB.style == "guildos" and popups[1], "Apply saves the choice and offers the reload")
S = load({ db = {}, noArt = true }); S:Resolve()
host = newRegion("Frame")
check(S:BuildPicker(host, 100) == 100 and #host.children == 0, "with one style there is nothing to choose: no section at all")

-- ── 8. /gos style ──────────────────────────────────────────────────────
S = load({ db = {} }); S:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("style")
check(said("guildos - GuildOS (in use)") and said("forever - WoW: Forever"), "/gos style lists the styles and marks the one in use")
SlashCmdList.GUILDOS("style forever")
check(GuildOSDB.style == "forever" and popups[1] and popups[1].which == "GUILDOS_STYLE_RELOAD",
  "/gos style forever saves it and offers the reload")
SlashCmdList.GUILDOS("style neon")
check(said("Unknown style: neon"), "an unknown style says which exist")
S = load({ db = {}, noArt = true }); S:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("style forever")
check(GuildOSDB.style == nil and said("not available on this client"), "forever is refused where the client has no art")
SlashCmdList.GUILDOS("style")
check(said("not available here"), "and the list says so")

-- ── 9. /gos style preview ──────────────────────────────────────────────
S = load({ db = {}, without = { ["128-redbutton-exit-c60"] = true } }); S:Resolve()
local rows = S:PreviewRows()
local seen, missingSeen = {}, false
for _, r in ipairs(rows) do
  seen[r.role] = true
  if r.atlas == "128-redbutton-exit-c60" and r.has == false then missingSeen = true end
end
check(seen.window and seen.button and seen.tab and seen.scroll and seen.minimise, "the preview lists every role's pieces")
check(missingSeen, "and marks the ones this client lacks")
S:ShowPreview()
check(S.previewFrame and S.previewFrame.shown, "/gos style preview opens it, even in the GuildOS style")

print(("style: %d checks passed"):format(checks))
