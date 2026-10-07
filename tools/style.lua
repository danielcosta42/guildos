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
  function CreateFrame(kind, _, parent) return newRegion(kind, parent) end
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
    return { width = s[1], height = s[2] }
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
f = newRegion("Frame")
S:Paint(f, "popup")
check(f.__nine.Center and f.__nine.Center.atlas == "tooltip-nineslice-center-c60", "a popup gets the tooltip art and its centre")
f = newRegion("Frame"); f.w, f.h = 200, 30
S:Paint(f, "titlebar")
check(f.__three.Left.atlas == "ui-frame-diamondmetal-header-cornerleft-c60-2x" and f.__styleBg,
  "a title bar gets the diamond-metal band over its colour")

S = load({ db = { style = "forever" }, without = { ["_ui-frame-metal-edgetop-c60-2x"] = true } }); S:Resolve()
f = newRegion("Frame")
local first = S:Paint(f, "window")
S:Paint(newRegion("Frame"), "window")
check(first == "flat" and f.backdrop.edgeSize == 1, "a missing atlas paints that piece flat, never a hole")
check(#errors == 1 and errors[1]:find("_ui-frame-metal-edgetop-c60-2x", 1, true),
  "and is recorded once, however often it is asked for")

print(("style: %d checks passed"):format(checks))
