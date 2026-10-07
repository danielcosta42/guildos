# Phase 1: the style layer, the frame, the components, the picker. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A player on WoW: Forever can switch GuildOS to a "WoW: Forever" style. It is painted with the
client's own `-c60` art, its palette and the game's font. Anyone else keeps today's look unchanged.

**Architecture:** A new `Core/Style.lua` holds the two styles. At load (`Initialize`), it resolves the
account's choice, re-points `GuildOS.Colors` in place, and switches `ApplyFont` to the game font. The
Helpers keep their public API and delegate painting to `Style:Paint(frame, role)` and to per-control
skins. In the `guildos` style these do exactly today's backdrops; in the `forever` style they build
nine-slices and three-slices of the client's atlases. A picker in Settings, `/gos style` and
`/gos style preview` sit on top.

**Tech Stack:** Lua 5.1 WoW addon (Anniversary 2.5.6 and Forever 1.60.1), LuaJIT harnesses in `tools/`, luacheck.

**Spec:** `docs/superpowers/specs/2026-10-07-ui-styles-design.md` §2, §4, §6, §7 (epic #119). This phase is issue #122.

## Global Constraints

- **Style ids:** `guildos` (the default, shown as "GuildOS") and `forever` (shown as "WoW: Forever"). The
  names are brands and are not translated.
- **The saved choice:** `GuildOSDB.style`, at the account root, read once at load. A switch needs `ReloadUI()`.
- **Availability:** `forever` is offered only when `C_Texture.GetAtlasInfo` answers for its key
  atlases. This is checked at run time, never by `Client.isAnniversary`.
- **The `guildos` style must paint exactly as before:** the same backdrop files, colours and border
  colours as the Helpers use today.
- **The Helpers API does not change:** `CreatePanel`, `CreateDarkPanel`, `CreateButton`,
  `SetButtonVariant`, `CreateTab`, `StyleSubTabBar`, `CreateCheckbox`, `CreateCloseButton`,
  `TitleBarButton`, `SkinScrollBar` and `StylePopup` keep their names, arguments and returned fields.
- **A missing atlas never breaks a window.** The piece paints flat, and the missing atlas is recorded
  once (`GuildOS:RecordError`).
- **Strings.** Every new player-facing string is an `L["…"]` key, translated in all ten languages
  (`tools/locales.lua` must pass).
- **Commits.** Commit type `feat:` (minor bump). Never `feat!:` nor "BREAKING CHANGE". Messages are in
  Portuguese, with no AI attribution.
- **Checks:** every `tools/*.lua` passes, and luacheck is `0 warnings / 0 errors`.

Commands (Git Bash, from `/e/World of Warcraft/_anniversary_/Interface/AddOns/GuildOS`):

```bash
LJ="$LOCALAPPDATA/Programs/LuaJIT/bin/luajit"
"$LJ" -e 'ADDON="."' tools/<name>.lua
for f in tools/*.lua; do "$LJ" -e 'ADDON="."' "$f" >/dev/null 2>&1 || echo "FAIL $f"; done
/c/Users/danie/bin/luacheck.exe . --config .luacheckrc | tail -1
```

## Review Focus

1. **A small frame with the window art.** `CreatePanel` frames are not only the main window. A small
   popup built with `CreatePanel` gets metal corners (about 48 px) that can overlap its content. Pinned in
   Task 3 (corner sizes come from the atlas times the scale) and checked in the beta with the preview.
2. **Toggle buttons in the Forever style.** Some screens call `btn:SetBaseColor` to show a toggle's
   state, which tints the backdrop under the art. In the Forever style that tint sits behind the red
   button and barely shows. Pinned in Task 4: `SetBaseColor` still works and does not raise. The visual
   is a phase 2 item.
3. **The minimise button** reuses the close button with its glyph swapped. In the Forever style the
   glyph is replaced by art, so minimise needs its own art (`128-redbutton-minus-c60`). Pinned in Task 4.
4. **A saved `forever` on Anniversary** (a shared account). It must fall back to `guildos` with one
   chat line, never draw holes. Pinned in Task 1.
5. **A module that copied a colour at load** (`local GOLD = C.gold`) must see the Forever palette.
   Re-pointing in place keeps the tables; pinned in Task 2.

---

## Before Task 1

```bash
git checkout main && git pull
git checkout -b feat/122-camada-de-estilo
F=C:/Users/danie/.claude/plugins/cache/ferion/ferion-engineering/0.2.1/hooks/flow-gate.sh
bash $F stamp task 122 && gh issue edit 122 --add-label status:in-progress --add-assignee @me && bash $F stamp dev
```

---

### Task 1: The registry: `Core/Style.lua`, availability, choice, resolve

**Files:**
- Create: `Core/Style.lua`
- Create: `tools/data/forever-c60-atlases.txt` (copied from the scratchpad, generated from wago.tools, build 1.60.1.70235)
- Create: `tools/style.lua`
- Modify: `GuildOS.toc` (add `Core\Style.lua` after `Core\Data.lua`)
- Modify: `Core/Core.lua` (`Initialize` calls `GuildOS.Style:Resolve()` right after `GuildOSDB` exists)

**Interfaces:**
- Produces:
  - `GuildOS.Style.DEFAULT = "guildos"`, `Style.ORDER = { "guildos", "forever" }`, `Style.current`
    (string), `Style.gameFont` (true or nil);
  - `Style.FOREVER` (the art by role);
  - `Style.FOREVER_PALETTE` (token name → `{r,g,b,a}`);
  - `Style.AtlasNames(art) -> { string }`;
  - `Style:Has(id) -> bool`, `Style:Available() -> { id }`, `Style:Name(id)`, `Style:Description(id)`,
    `Style:Current()`;
  - `Style:Choose(id) -> true | false, "unknown"|"unavailable"`;
  - `Style:Resolve() -> id`;
  - `Style:Apply(id) -> bool` (Choose plus the reload popup);
  - `Style:PrintList()`.

- [ ] **Step 1: Copy the atlas fixture**

```bash
mkdir -p tools/data && cp "C:/Users/danie/AppData/Local/Temp/claude/e--Bacon-01---Clientes-guildos-web/39114d2d-5ec6-4291-9510-708382ecda1d/scratchpad/forever-c60-atlases.txt" tools/data/
head -3 tools/data/forever-c60-atlases.txt && wc -l tools/data/forever-c60-atlases.txt
```

Expected: the 3-line header, and about 1891 lines.

- [ ] **Step 2: Write the failing test `tools/style.lua` (registry part)**

```lua
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
```

- [ ] **Step 3: Run it to see it fail**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: an error, `cannot open ./Core/Style.lua`.

- [ ] **Step 4: Write `Core/Style.lua`**

```lua
----------------------------------------------------------------------
-- Guild OS - Interface styles (issue #122; spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §4)
-- A style is how the addon is painted: its palette, its font, and the art behind each role
-- (window, title bar, panel, well, popup, input) and control (button, tab, checkbox, close
-- button, scroll bar). "guildos" is the flat look the addon was made with; it paints exactly as
-- the Helpers always did. "forever" paints with the WoW: Forever client's own -c60 atlases, and
-- is offered only where the client has them. The choice belongs to the account (GuildOSDB.style)
-- and takes effect at load: frames are built once, so a switch asks for a reload.
----------------------------------------------------------------------
local Style = {}
GuildOS.Style = Style
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

Style.DEFAULT = "guildos"
Style.ORDER = { "guildos", "forever" }
Style.current = Style.DEFAULT

local INFO = {
    guildos = { name = "GuildOS", desc = L["Flat and dark: the look Guild OS was made with."] },
    forever = { name = "WoW: Forever",
                desc = L["The game's own bronze frames, tabs and buttons. A beta: tell us what looks off."] },
}

-- A frame's border in nine pieces, named as the client names them: four corners, and edges whose
-- names start with "_" (tiled across) or "!" (tiled down).
local function nine(prefix, suffix, scale, center)
    return { kind = "nine", scale = scale, center = center,
        TopLeftCorner = prefix .. "cornertopleft" .. suffix, TopRightCorner = prefix .. "cornertopright" .. suffix,
        BottomLeftCorner = prefix .. "cornerbottomleft" .. suffix,
        BottomRightCorner = prefix .. "cornerbottomright" .. suffix,
        TopEdge = "_" .. prefix .. "edgetop" .. suffix, BottomEdge = "_" .. prefix .. "edgebottom" .. suffix,
        LeftEdge = "!" .. prefix .. "edgeleft" .. suffix, RightEdge = "!" .. prefix .. "edgeright" .. suffix }
end
local function three(left, center, right)
    return { kind = "three", Left = left, Center = center, Right = right }
end
local function redButton(state)
    local s = (state == "rest") and "" or ("-" .. state)
    return three("128-redbutton-left" .. s .. "-c60", "_128-redbutton-center" .. s .. "-c60",
                 "128-redbutton-right" .. s .. "-c60")
end
local function iconButton(name)
    return { rest = "128-redbutton-" .. name .. "-c60", pressed = "128-redbutton-" .. name .. "-pressed-c60",
             disabled = "128-redbutton-" .. name .. "-disabled-c60" }
end

-- The Forever client's art (build 1.60.1.70235), by role. A nine-slice's pieces are the atlas size
-- times `scale`; a three-slice is as tall as its frame. Candidates until beta screenshots of
-- /gos style preview confirm them (spec §4.6).
Style.FOREVER = {
    window   = nine("ui-frame-metal-", "-c60-2x", 0.25),
    panel    = nine("optionsframe-nineslice-", "-c60", 0.5),
    well     = nine("optionsframe-nineslice-", "-c60", 0.5),
    popup    = nine("tooltip-nineslice-", "-c60", 1, "tooltip-nineslice-center-c60"),
    titlebar = three("ui-frame-diamondmetal-header-cornerleft-c60-2x", "_ui-frame-diamondmetal-header-tile-c60-2x",
                     "ui-frame-diamondmetal-header-cornerright-c60-2x"),
    input    = three("common-search-border-left-c60", "common-search-border-middle-c60",
                     "common-search-border-right-c60"),
    button   = { rest = redButton("rest"), pressed = redButton("pressed"), disabled = redButton("disabled") },
    tab      = { rest = "common-internaltab-c60", hover = "common-internaltab-hover-c60",
                 active = "common-internaltab-selected-c60" },
    checkbox = { box = "checkbox-minimal-c60", mark = "talents-checkmark-c60" },
    close    = iconButton("exit"),
    minimise = iconButton("minus"),
    scroll   = { track = "!minimal-scrollbar-track-middle-c60", thumb = "minimal-scrollbar-thumb-middle-c60" },
}
-- The pieces that say the client has the art at all.
local KEY_ATLASES = { "ui-frame-metal-cornertopleft-c60-2x", "_128-redbutton-center-c60", "common-internaltab-c60" }

-- Stone, bronze and parchment, with the game's yellow as the accent. Status colours keep theirs.
local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
Style.FOREVER_PALETTE = {
    bg = rgb(0.078, 0.067, 0.055), panel = rgb(0.125, 0.106, 0.086), popup = rgb(0.157, 0.133, 0.106),
    well = rgb(0.051, 0.043, 0.035), line = rgb(0.361, 0.290, 0.180), lineHi = rgb(0.549, 0.443, 0.263),
    text = rgb(1.000, 0.957, 0.859), textSoft = rgb(0.824, 0.761, 0.624), label = rgb(0.722, 0.643, 0.482),
    labelDim = rgb(0.522, 0.459, 0.349), disabled = rgb(0.400, 0.361, 0.298),
    gold = rgb(1.000, 0.820, 0.000), onGold = rgb(0.149, 0.098, 0.020),
}

----------------------------------------------------------------------
-- Atlases
----------------------------------------------------------------------
local function atlasInfo(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return nil end
    local ok, info = pcall(get, name)
    return ok and info or nil
end

-- Every atlas a piece of art names, depth first.
function Style.AtlasNames(art, out)
    out = out or {}
    if type(art) == "string" then out[#out + 1] = art; return out end
    for k, v in pairs(art or {}) do
        if k ~= "kind" and (type(v) == "string" or type(v) == "table") then Style.AtlasNames(v, out) end
    end
    return out
end

-- True when the client has every atlas of `art`. Each missing one is recorded once per session.
local reported = {}
function Style:_HasArt(art)
    local all = true
    for _, n in ipairs(Style.AtlasNames(art)) do
        if not atlasInfo(n) then
            all = false
            if not reported[n] then
                reported[n] = true
                GuildOS:RecordError("style forever: the client has no atlas " .. n)
            end
        end
    end
    return all
end

----------------------------------------------------------------------
-- The registry
----------------------------------------------------------------------
function Style:Has(id)
    if id == "guildos" then return true end
    if id ~= "forever" then return false end
    for _, n in ipairs(KEY_ATLASES) do
        if not atlasInfo(n) then return false end
    end
    return true
end

function Style:Available()
    local out = {}
    for _, id in ipairs(self.ORDER) do
        if self:Has(id) then out[#out + 1] = id end
    end
    return out
end

function Style:Name(id) return INFO[id] and INFO[id].name or tostring(id) end
function Style:Description(id) return INFO[id] and INFO[id].desc or "" end
function Style:Current() return self.current end

-- Saves the account's choice; it is used from the next load on.
function Style:Choose(id)
    if not INFO[id] then return false, "unknown" end
    if not self:Has(id) then return false, "unavailable" end
    if type(GuildOSDB) ~= "table" then GuildOSDB = {} end
    GuildOSDB.style = id
    return true
end

-- At load, before any window is built: the saved style if this client draws it, else the default,
-- said once. The Forever style re-points the palette in place and takes the game's font.
function Style:Resolve()
    local want = type(GuildOSDB) == "table" and GuildOSDB.style or nil
    local id = (want and self:Has(want)) and want or self.DEFAULT
    self.current, self.gameFont = id, nil
    if want and want ~= id then
        GuildOS:Print(string.format(L["The %s style is not available on this client; using %s."],
            self:Name(want), self:Name(id)))
    end
    if id == "forever" then
        GuildOS:RepointColors(self.FOREVER_PALETTE)
        self.gameFont = true
    end
    return id
end

if StaticPopupDialogs then StaticPopupDialogs["GUILDOS_STYLE_RELOAD"] = {
    text = "%s", button1 = L["Reload"], button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
} end

-- The picker's and /gos style's verb: save, then offer the reload.
function Style:Apply(id)
    local ok, why = self:Choose(id)
    if not ok then
        if why == "unknown" then
            GuildOS:Print(string.format(L["Unknown style: %s. Styles: %s"], tostring(id), table.concat(self.ORDER, ", ")))
        else
            GuildOS:Print(string.format(L["The %s style is not available on this client."], self:Name(id)))
        end
        return false
    end
    StaticPopup_Show("GUILDOS_STYLE_RELOAD", string.format(L["Reload the interface now to use the %s style?"], self:Name(id)))
    return true
end

function Style:PrintList()
    for _, id in ipairs(self.ORDER) do
        local tag = (id == self.current and L["in use"]) or ((not self:Has(id)) and L["not available here"]) or nil
        GuildOS:Print("  " .. id .. " - " .. self:Name(id) .. (tag and (" (" .. tag .. ")") or ""))
    end
end
```

- [ ] **Step 5: Wire it in**

In `GuildOS.toc`, add the line `Core\Style.lua` right after `Core\Data.lua`.

In `Core/Core.lua` `Initialize`, right after `if not GuildOSDB then GuildOSDB = {} end`, add:

```lua
    -- The interface style is the account's, and is settled before anything is drawn (#122).
    if self.Style then self.Style:Resolve() end
```

Task 2 adds `GuildOS:RepointColors`; until then `Resolve("forever")` raises. Section 4 of the test does
exercise it, so Task 1's test fails at section 4 until Task 2. That is expected: run Steps 6 and 7 after
Task 2's Step 3.

- [ ] **Step 6: Run the registry test (sections 1-3)**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: sections 1-3 pass; section 4 fails with `attempt to call method 'RepointColors'`.

- [ ] **Step 7: Commit (after Task 2's Step 3 makes section 4 pass)**

```bash
git add Core/Style.lua tools/style.lua tools/data/forever-c60-atlases.txt GuildOS.toc Core/Core.lua
git commit -m "feat: a camada de estilos de interface, com o estilo WoW: Forever disponível onde o cliente tem a arte (#122)"
```

---

### Task 2: The palette and the font, re-pointed in place

**Files:**
- Modify: `Core/Data.lua` (`GuildOS:RepointColors(tokens)` and the alias map; `ApplyFont` honours `Style.gameFont`)
- Modify: `tools/style.lua` (append section 5)

**Interfaces:**
- Consumes: `Style.FOREVER_PALETTE`, `Style:Resolve()` (Task 1).
- Produces: `GuildOS:RepointColors(tokens)`. It sets `r,g,b,a` of each named token in place, then
  recomputes every legacy alias in place.

- [ ] **Step 1: Append the failing checks to `tools/style.lua`**

```lua
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
```

- [ ] **Step 2: Run it to see it fail**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: FAIL in section 4, `attempt to call method 'RepointColors'`.

- [ ] **Step 3: Implement in `Core/Data.lua`**

After the `GuildOS.Colors = { … }` table, add:

```lua
-- The legacy keys and the token each copies, so a style can re-point the palette in place
-- (issue #122): every module that captured `local C = GuildOS.Colors`, or one of its colours, sees it.
local ALIASES = {
    silver = { "textSoft" }, textDim = { "label" }, border = { "line" }, separator = { "line" },
    accent = { "gold" }, accentDim = { "gold", dim = ACCENT_DIM }, accentSoft = { "gold", a = ACCENT_WASH },
    headerBg = { "panel" }, bg0 = { "well" }, bg1 = { "well" }, bg2 = { "panel" }, panelDark = { "well" },
    row1 = { "well" }, row2 = { "bg" }, rowHover = { "panel" },
    red = { "danger" }, green = { "ok" }, blue = { "info" }, online = { "ok" }, offline = { "disabled" },
}

-- Re-point the named tokens in place, then every legacy key from its token.
function GuildOS:RepointColors(tokens)
    local C = GuildOS.Colors
    for key, v in pairs(tokens) do
        local t = C[key]
        if t then t.r, t.g, t.b, t.a = v.r, v.g, v.b, v.a or 1 end
    end
    for key, how in pairs(ALIASES) do
        local src, t, k = C[how[1]], C[key], how.dim or 1
        t.r, t.g, t.b, t.a = src.r * k, src.g * k, src.b * k, how.a or src.a
    end
end
```

In `GuildOS:ApplyFont`, change
`if GuildOS.GameFontOnly or (type(GuildOSDB) == "table" and GuildOSDB.font == "game") then` to:

```lua
    if GuildOS.GameFontOnly or (GuildOS.Style and GuildOS.Style.gameFont)
        or (type(GuildOSDB) == "table" and GuildOSDB.font == "game") then
```

- [ ] **Step 4: Run the test**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: sections 1-5 pass.

- [ ] **Step 5: Commit Tasks 1 and 2**

Task 1's commit (Step 7), and then:

```bash
git add Core/Data.lua tools/style.lua
git commit -m "feat: o estilo Forever re-aponta a paleta no lugar e usa a fonte do jogo (#122)"
```

---

### Task 3: Painting by role: `Style:Paint`, nine-slice and three-slice

**Files:**
- Modify: `Core/Style.lua` (append the painting section)
- Modify: `tools/style.lua` (append section 6)

**Interfaces:**
- Produces:
  - `Style:Paint(frame, role) -> "flat" | "art"` (roles: `window`, `titlebar`, `panel`, `well`, `popup`, `input`);
  - `Style:_PaintFlat(frame, role)`;
  - `Style:_PaintThree(frame, art, layer) -> pieces { Left, Center, Right }`.
- Frame fields:
  - `frame.__nine` (the 8 border textures, plus `Center` for a popup);
  - `frame.__three` (`Left`/`Center`/`Right`);
  - `frame.__styleBg` (a title bar's flat band).

- [ ] **Step 1: Append the failing checks**

```lua
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
check(f.__three.Left.atlas == "ui-frame-diamondmetal-header-cornerleft-c60-2x" and f.__styleBg, "a title bar gets the diamond-metal band over its colour")

S = load({ db = { style = "forever" }, without = { ["_ui-frame-metal-edgetop-c60-2x"] = true } }); S:Resolve()
f = newRegion("Frame")
local first = S:Paint(f, "window")
S:Paint(newRegion("Frame"), "window")
check(first == "flat" and f.backdrop.edgeSize == 1, "a missing atlas paints that piece flat, never a hole")
check(#errors == 1 and errors[1]:find("_ui-frame-metal-edgetop-c60-2x", 1, true), "and is recorded once, however often it is asked for")
```

- [ ] **Step 2: Run to see it fail**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: FAIL, `attempt to call method 'Paint'`.

- [ ] **Step 3: Append the painting section to `Core/Style.lua`**

```lua
----------------------------------------------------------------------
-- Painting by role
----------------------------------------------------------------------
local function roleColor(role)
    local C = GuildOS.Colors
    if role == "well" or role == "input" then return C.well end
    if role == "titlebar" then return C.panel end
    return C.bg
end

-- Today's paint, unchanged: a WHITE8x8 backdrop with a 1px `line` border, or the title bar's band.
-- A popup's colours are its caller's (Helpers:StylePopup never set them), so flat leaves it alone.
function Style:_PaintFlat(frame, role)
    local C = GuildOS.Colors
    if role == "popup" then return "flat" end
    if role == "titlebar" then
        local bg = frame.__styleBg or frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(WHITE)
        bg:SetAllPoints()
        bg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
        frame.__styleBg = bg
        return "flat"
    end
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    return "flat"
end

local function setAtlasSized(tex, name, scale)
    tex:SetAtlas(name)
    local info = atlasInfo(name)
    local w, h = (info and info.width or 0) * scale, (info and info.height or 0) * scale
    tex:SetSize(w, h)
    return w, h
end

-- The border in nine pieces around the role's colour.
function Style:_PaintNine(frame, art, role)
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    local p = frame.__nine or {}
    frame.__nine = p
    for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                           "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
        p[key] = p[key] or frame:CreateTexture(nil, "BORDER")
        setAtlasSized(p[key], art[key], art.scale)
        p[key]:ClearAllPoints()
    end
    p.TopLeftCorner:SetPoint("TOPLEFT")
    p.TopRightCorner:SetPoint("TOPRIGHT")
    p.BottomLeftCorner:SetPoint("BOTTOMLEFT")
    p.BottomRightCorner:SetPoint("BOTTOMRIGHT")
    p.TopEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "TOPRIGHT")
    p.TopEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "TOPLEFT")
    p.BottomEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "BOTTOMRIGHT")
    p.BottomEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "TOPLEFT")
    p.RightEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "BOTTOMRIGHT")
    p.RightEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPRIGHT")
    if art.center then
        p.Center = p.Center or frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        p.Center:SetAtlas(art.center)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPLEFT")
    end
    return "art"
end

-- Three pieces side by side, as tall as the frame. The caps keep their atlas proportions at that
-- height and are squeezed together when the frame is narrower than both.
function Style:_PaintThree(frame, art, layer)
    local p = frame.__three or {}
    frame.__three = p
    for _, k in ipairs({ "Left", "Center", "Right" }) do
        p[k] = p[k] or frame:CreateTexture(nil, layer or "BACKGROUND")
        p[k]:SetAtlas(art[k])
    end
    local function layout()
        local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
        local li, ri = atlasInfo(art.Left), atlasInfo(art.Right)
        local k = (li and li.height and li.height > 0) and (h / li.height) or 1
        local lw, rw = (li and li.width or 0) * k, (ri and ri.width or 0) * k
        if w > 0 and lw + rw > w then
            local f = w / (lw + rw)
            lw, rw = lw * f, rw * f
        end
        p.Left:ClearAllPoints(); p.Left:SetPoint("TOPLEFT"); p.Left:SetPoint("BOTTOMLEFT"); p.Left:SetWidth(lw)
        p.Right:ClearAllPoints(); p.Right:SetPoint("TOPRIGHT"); p.Right:SetPoint("BOTTOMRIGHT"); p.Right:SetWidth(rw)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.Left, "TOPRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.Right, "BOTTOMLEFT")
    end
    layout()
    if not frame.__threeHooked then
        frame.__threeHooked = true
        frame:HookScript("OnSizeChanged", layout)
    end
    return p
end

-- Paint `frame` as `role`. In the Forever style with the client's art, the role's art; otherwise,
-- and for any piece the client lacks, today's flat paint.
function Style:Paint(frame, role)
    local art = (self.current == "forever") and self.FOREVER[role] or nil
    if art and self:_HasArt(art) then
        if art.kind == "nine" then return self:_PaintNine(frame, art, role) end
        if role == "titlebar" then self:_PaintFlat(frame, role) end   -- the band behind the art
        if role == "input" then
            local c = roleColor(role)
            frame:SetBackdrop({ bgFile = WHITE })
            frame:SetBackdropColor(c.r, c.g, c.b, 1)
        end
        self:_PaintThree(frame, art, role == "titlebar" and "ARTWORK" or "BORDER")
        return "art"
    end
    return self:_PaintFlat(frame, role)
end
```

- [ ] **Step 4: Run the test**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: sections 1-6 pass.

- [ ] **Step 5: Commit**

```bash
git add Core/Style.lua tools/style.lua
git commit -m "feat: o estilo pinta cada papel, com a arte do Forever em nine-slice e three-slice e o flat de sempre como reserva (#122)"
```

---

### Task 4: The Helpers and the window delegate to the style

**Files:**
- Modify: `Core/Style.lua` (append the controls section)
- Modify: `UI/Helpers.lua`: `CreatePanel`, `CreateDarkPanel`, `StylePopup`, `_ButtonState`,
  `CreateButton`, `SetButtonVariant`, `CreateCheckbox`, `CreateCloseButton`, `SkinScrollBar`,
  `CreateTab`, and the header comment ("Forever skin" becomes "the GuildOS style")
- Modify: `UI/Window.lua:250-253` (the title bar band) and `:277-279` (minimise)
- Modify: `tools/style.lua` (append section 7)
- Create: `tools/window-shell-forever.lua`
- Modify: `tools/window-shell.lua` (load `Core/Style.lua`; honour a `STYLE` global; stub `SetAtlas` and `C_Texture`)

**Interfaces:**
- Consumes: `Style:Paint`, `Style:_PaintThree`, `Style.FOREVER` (Tasks 1 and 3).
- Produces:
  - `Style:SkinButton(btn)` (sets `btn.__forever`);
  - `Style:ButtonState(btn, state)`;
  - `Style:SkinTab(tab)` and `Style:TabState(tab, hovered)`;
  - `Style:SkinCheckbox(cb, border, fill, mark)`;
  - `Style:SkinClose(btn, kind)` (`kind` is `"close"` or `"minimise"`);
  - `Style:SkinScrollBar(track, thumb)`.
  In the `guildos` style each is a no-op that returns false.

- [ ] **Step 1: Append the failing checks**

```lua
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

local close = UI:CreateCloseButton(UIParent)
check(close.__art and close.__art.atlas == "128-redbutton-exit-c60" and not close.x.shown, "the close button is the game's exit button")
S:SkinClose(close, "minimise")
check(close.__art.atlas == "128-redbutton-minus-c60", "and the minimise button its minus")

local sp = newRegion("Frame"); sp.ScrollBar = newRegion("Slider", sp)
sp.ScrollBar.GetMinMaxValues = function() return 0, 0 end
sp.ScrollBar.GetValue = function() return 0 end
UI:SkinScrollBar(sp)
local track, thumb
for _, t in ipairs(sp.ScrollBar.children) do
  if t.atlas == "!minimal-scrollbar-track-middle-c60" then track = t end
  if t.atlas == "minimal-scrollbar-thumb-middle-c60" then thumb = t end
end
check(track and thumb, "a scroll bar is the game's minimal track and thumb")

local panel = UI:CreatePanel(UIParent)
check(panel.__nine and panel.__nine.TopLeftCorner.atlas == "ui-frame-metal-cornertopleft-c60-2x", "CreatePanel is the metal window")
local dark = UI:CreateDarkPanel(UIParent)
check(dark.__nine and dark.__nine.TopLeftCorner.atlas == "optionsframe-nineslice-cornertopleft-c60", "CreateDarkPanel is the inset frame")
local pop = UI:CreatePanel(UIParent)
UI:StylePopup(pop, { noShadow = true, noFade = true })
check(pop.__nine.TopLeftCorner.atlas == "tooltip-nineslice-cornertopleft-c60", "a popup takes the tooltip art")
```

- [ ] **Step 2: Run to see it fail**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: FAIL at `forever: a button is the game's red button`.

- [ ] **Step 3: Append the controls section to `Core/Style.lua`**

```lua
----------------------------------------------------------------------
-- Controls. Each is a no-op returning false in the guildos style (or without the art), so the
-- Helpers keep painting as they always did.
----------------------------------------------------------------------
local function forever(self, art) return self.current == "forever" and self:_HasArt(art) end

function Style:SkinButton(btn)
    if not forever(self, self.FOREVER.button) then return false end
    btn.__forever = true
    self:_PaintThree(btn, self.FOREVER.button.rest, "BACKGROUND")
    return true
end

function Style:ButtonState(btn, state)
    local C = GuildOS.Colors
    local key = (state == "pressed" or state == "disabled") and state or "rest"
    local art, p = self.FOREVER.button[key], btn.__three
    p.Left:SetAtlas(art.Left); p.Center:SetAtlas(art.Center); p.Right:SetAtlas(art.Right)
    local ghost = btn.variant == "ghost"
    for _, t in pairs(p) do t:SetShown(not ghost) end
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)
    local rest = (btn.variant == "danger" and C.danger) or (ghost and C.label) or C.gold
    local ink = (state == "disabled" and C.disabled) or (state == "hover" and C.text) or rest
    btn.label:SetTextColor(ink.r, ink.g, ink.b)
    btn.__hovered = (state == "hover")
    if btn.glow then btn.glow:Hide() end
    if btn.underline then btn.underline:SetShown(ghost) end
end

function Style:SkinTab(tab)
    if not forever(self, self.FOREVER.tab) then return false end
    local art = tab:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    art:SetAtlas(self.FOREVER.tab.rest)
    tab.__art = art
    return true
end

function Style:TabState(tab, hovered)
    local t = self.FOREVER.tab
    tab.__art:SetAtlas((tab.isActive and t.active) or (hovered and t.hover) or t.rest)
end

function Style:SkinCheckbox(cb, border, fill, mark)
    if not forever(self, self.FOREVER.checkbox) then return false end
    border:Hide()
    fill:SetAtlas(self.FOREVER.checkbox.box)
    fill:SetVertexColor(1, 1, 1, 1)
    mark:SetAtlas(self.FOREVER.checkbox.mark)
    mark:SetVertexColor(1, 1, 1, 1)
    return true
end

-- The close button, or (kind "minimise") the minimise button the window makes from it.
function Style:SkinClose(btn, kind)
    local art = self.FOREVER[kind == "minimise" and "minimise" or "close"]
    if not forever(self, art) then return false end
    btn.__art = btn.__art or btn:CreateTexture(nil, "ARTWORK")
    btn.__art:SetAllPoints()
    btn.__art:SetAtlas(art.rest)
    if btn.x then btn.x:Hide() end
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnMouseDown", function(self) self.__art:SetAtlas(art.pressed) end)
    btn:SetScript("OnMouseUp", function(self) self.__art:SetAtlas(art.rest) end)
    return true
end

function Style:SkinScrollBar(track, thumb)
    if not forever(self, self.FOREVER.scroll) then return false end
    track:SetAtlas(self.FOREVER.scroll.track)
    track:SetVertexColor(1, 1, 1, 1)
    thumb:SetAtlas(self.FOREVER.scroll.thumb)
    thumb:SetVertexColor(1, 1, 1, 1)
    return true
end
```

- [ ] **Step 4: Delegate from `UI/Helpers.lua`**

`local Style = GuildOS.Style` near the top, under `local C = GuildOS.Colors`. Then:

`CreatePanel` body becomes:

```lua
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    Style:Paint(f, "window")
    return f
```

`CreateDarkPanel` becomes:

```lua
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    Style:Paint(f, "well")
    return f
```

In `StylePopup`, before `return frame`, add: `Style:Paint(frame, "popup")`.

In `_ButtonState`, as its first line:
`if btn.__forever then return Style:ButtonState(btn, state) end`.

In `CreateButton`, right before `self:_ButtonState(btn, "rest")`: `Style:SkinButton(btn)`.

In `SetButtonVariant`, the primary branch creates the glow only `if not btn.__forever and not btn.glow then`.

In `CreateCheckbox`, after the `mark` texture is made (`mark:Hide()`): `Style:SkinCheckbox(cb, border, fill, mark)`.

In `CreateCloseButton`, before `return btn`: `Style:SkinClose(btn, "close")`.

In `SkinScrollBar`, after `scrollBar.customThumb = thumb`: `Style:SkinScrollBar(track, thumb)`.

In `CreateTab`, after `tab.underline = underline`: `Style:SkinTab(tab)`. And inside its local
`paint(self, hovered)`, as the last line: `if self.__art then Style:TabState(self, hovered) end`.

In the file header, replace `-- Reusable factories for the "Forever" skin (design handoff §3-5 and §8;`
with `-- Reusable factories for the GuildOS style (design handoff §3-5 and §8;`. Add a line:
`-- The interface style (Core/Style.lua, #122) paints each surface and control through them.`

- [ ] **Step 5: The window's title bar and minimise button (`UI/Window.lua`)**

Replace:

```lua
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(WHITE)
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
```

with `GuildOS.Style:Paint(bar, "titlebar")`.

After `minimise.x:SetText(DASH)`, add `GuildOS.Style:SkinClose(minimise, "minimise")`.

- [ ] **Step 6: Run the style test**

Run: `"$LJ" -e 'ADDON="."' tools/style.lua`
Expected: sections 1-7 pass.

- [ ] **Step 7: Run `window-shell` under the GuildOS style, then under the Forever style**

In `tools/window-shell.lua`, after `dofile(ADDON .. "/Core/Data.lua")` (line 248), add:

```lua
dofile(ADDON .. "/Core/Style.lua")
-- tools/window-shell-forever.lua runs this whole harness again under the Forever style (#122).
if STYLE == "forever" then
  local atlases = {}
  for line in io.lines(ADDON .. "/tools/data/forever-c60-atlases.txt") do
    if not line:find("^#") then atlases[line:lower()] = true end
  end
  C_Texture = { GetAtlasInfo = function(n) return atlases[tostring(n):lower()] and { width = 32, height = 32 } or nil end }
  GuildOSDB.style = "forever"
end
GuildOS.Style:Resolve()
```

Add the texture methods the stub lacks, next to `Frame:SetTexture`'s neighbours:

```lua
function Frame:SetAtlas(name) self.atlas = name end
function Frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
```

Create `tools/window-shell-forever.lua`:

```lua
-- The one-window harness (tools/window-shell.lua) again, under the WoW: Forever style (#122): the same
-- layout and every check, with the client's art and palette. The Helpers' API did not change.
--
--   luajit -e 'ADDON="."' tools/window-shell-forever.lua
ADDON = ADDON or "."
STYLE = "forever"
dofile(ADDON .. "/tools/window-shell.lua")
```

Run both:
`"$LJ" -e 'ADDON="."' tools/window-shell.lua` → `window-shell: 310 checks passed`.
`"$LJ" -e 'ADDON="."' tools/window-shell-forever.lua` → `window-shell: 310 checks passed`.

If a check fails only under Forever, decide whether the check pins today's paint (then guard it with
`STYLE ~= "forever"` and ledger the ruling), or whether the Forever skin broke a behaviour (then fix
the skin).

- [ ] **Step 8: The other harnesses that load the Helpers**

`tools/forever-components.lua` and `tools/professions-panel.lua` also `dofile` `UI/Helpers.lua`. Add
`dofile(ADDON .. "/Core/Style.lua")` right before it in each. Without `Resolve()`, the style is `guildos`,
and they paint as before.

- [ ] **Step 9: Run every harness and luacheck**

Expected: all pass, and luacheck is `0 warnings / 0 errors`.

- [ ] **Step 10: Commit**

```bash
git add Core/Style.lua UI/Helpers.lua UI/Window.lua tools/style.lua tools/window-shell.lua tools/window-shell-forever.lua tools/forever-components.lua tools/professions-panel.lua
git commit -m "feat: janela, botões, abas, checkboxes, fechar e barras de rolagem no estilo Forever, pela mesma API dos Helpers (#122)"
```

---

### Task 5: The picker, `/gos style`, and the game-font option

**Files:**
- Modify: `UI/FeaturePanels.lua` (the Settings section around the "Use the game's font" checkbox, about line 2146)
- Modify: `Core/Commands.lua` (the `style` verb and two help lines)
- Modify: `tools/style.lua` (append section 8)

**Interfaces:**
- Consumes: `Style:Available()`, `Style:Current()`, `Style:Name()`, `Style:Description()`,
  `Style:Apply()`, `Style:PrintList()`, `Style.gameFont`.

- [ ] **Step 1: Append the failing checks (commands)**

```lua
-- ── 8. /gos style ──────────────────────────────────────────────────────
S = load({ db = {} }); S:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("style")
check(said("guildos - GuildOS (in use)") and said("forever - WoW: Forever"), "/gos style lists the styles and marks the one in use")
SlashCmdList.GUILDOS("style forever")
check(GuildOSDB.style == "forever" and popups[1] and popups[1].which == "GUILDOS_STYLE_RELOAD", "/gos style forever saves it and offers the reload")
SlashCmdList.GUILDOS("style neon")
check(said("Unknown style: neon"), "an unknown style says which exist")
S = load({ db = {}, noArt = true }); S:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("style forever")
check(GuildOSDB.style == nil and said("not available on this client"), "forever is refused where the client has no art")
SlashCmdList.GUILDOS("style")
check(said("not available here"), "and the list says so")
```

- [ ] **Step 2: Run to see it fail**

Expected: FAIL at `/gos style lists the styles…`, because there is no `style` verb.

- [ ] **Step 3: The command**

In `Core/Commands.lua`'s dispatcher, next to the `probe` branches, add:

```lua
    elseif msg == "style" or msg:match("^style%s") then
        -- The interface style (#122): list, switch, or show the Forever pieces side by side.
        local arg = strtrim((msg:gsub("^style%s*", ""))):lower()
        if arg == "" then
            GuildOS.Style:PrintList()
        elseif arg == "preview" then
            GuildOS.Style:ShowPreview()
        else
            GuildOS.Style:Apply(arg)
        end
```

In the help:
- under `General`, add `helpLine("/gos style [name]", L["List the interface styles, or switch to one"])`;
- under `Diagnostics`, add `helpLine("/gos style preview", L["Show the Forever style's pieces side by side"])`.

- [ ] **Step 4: The picker in Settings**

In `UI/FeaturePanels.lua`, right before the comment `-- The game's own font instead of GuildOS's (issue #57)`, add:

```lua
    -- The interface style (issue #122): one row per style this client can draw. A switch saves the
    -- account's choice and asks to reload, since every frame is built once.
    local styleHead = UI:CreateText(content, L["Interface style"], 11, C.gold.r, C.gold.g, C.gold.b)
    styleHead:SetPoint("TOPLEFT", 8, -yOff)
    yOff = yOff + 20
    for _, id in ipairs(GuildOS.Style:Available()) do
        local inUse = GuildOS.Style:Current() == id
        local name = UI:CreateText(content, GuildOS.Style:Name(id), 12, C.text.r, C.text.g, C.text.b)
        name:SetPoint("TOPLEFT", 16, -yOff)
        local desc = UI:CreateText(content, GuildOS.Style:Description(id), 10, C.label.r, C.label.g, C.label.b)
        desc:SetPoint("TOPLEFT", 16, -(yOff + 16))
        local apply = UI:CreateButton(content, inUse and L["In use"] or L["Apply"], 90, 22)
        apply:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -(yOff + 4))
        if inUse then apply:Disable() else apply:SetScript("OnClick", function() GuildOS.Style:Apply(id) end) end
        yOff = yOff + 40
    end
    yOff = yOff + 8
```

Then, for the font checkbox:
- `fontCb.checkbox:SetChecked(GuildOSDB.font == "game" or GuildOS.GameFontOnly)` becomes
  `fontCb.checkbox:SetChecked(GuildOSDB.font == "game" or GuildOS.GameFontOnly or GuildOS.Style.gameFont)`;
- `if GuildOS.GameFontOnly then` (the block that disables it) becomes
  `if GuildOS.GameFontOnly or GuildOS.Style.gameFont then`.

If `content` has no right anchor there (check how the surrounding rows anchor), anchor `apply` at
`TOPLEFT, 380, -(yOff + 4)` instead, and ledger it.

- [ ] **Step 5: Run the tests**

Expected: `tools/style.lua` sections 1-8 pass, and `window-shell` and `window-shell-forever` still pass.

- [ ] **Step 6: Commit**

```bash
git add UI/FeaturePanels.lua Core/Commands.lua tools/style.lua
git commit -m "feat: o seletor de estilo em Settings e o /gos style (#122)"
```

---

### Task 6: `/gos style preview`

**Files:**
- Create: `UI/StylePreview.lua`
- Modify: `GuildOS.toc` (add `UI\StylePreview.lua` after `UI\Helpers.lua`)
- Modify: `tools/style.lua` (append section 9; load `UI/StylePreview.lua` in `load()` after Helpers)

**Interfaces:**
- Produces: `Style:PreviewRows() -> { { role, atlas, has } }` and `Style:ShowPreview()`, which builds
  once and shows `Style.previewFrame`.

- [ ] **Step 1: Append the failing checks**

In `load()`, after `dofile(ADDON .. "/UI/Helpers.lua")`, add `dofile(ADDON .. "/UI/StylePreview.lua")`.
Then append:

```lua
-- ── 9. /gos style preview ──────────────────────────────────────────────
S = load({ db = {}, without = { ["redbutton-exit-c60"] = true, ["128-redbutton-exit-c60"] = true } }); S:Resolve()
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
```

- [ ] **Step 2: Run to see it fail**

Expected: `cannot open ./UI/StylePreview.lua`.

- [ ] **Step 3: Write `UI/StylePreview.lua`**

```lua
----------------------------------------------------------------------
-- Guild OS - /gos style preview (issue #122; spec §4.6)
-- Every piece of the Forever style's art side by side, each labelled with its role and atlas name,
-- and the ones this client lacks marked: the pieces are chosen from a beta screenshot of it.
----------------------------------------------------------------------
local Style = GuildOS.Style
local L = GuildOS.L

local ROLES = { "window", "titlebar", "panel", "well", "popup", "input",
                "button", "tab", "checkbox", "close", "minimise", "scroll" }

function Style:PreviewRows()
    local rows = {}
    for _, role in ipairs(ROLES) do
        for _, atlas in ipairs(Style.AtlasNames(self.FOREVER[role])) do
            local get = C_Texture and C_Texture.GetAtlasInfo
            local has = get and select(2, pcall(get, atlas)) ~= nil or false
            rows[#rows + 1] = { role = role, atlas = atlas, has = has and true or false }
        end
    end
    return rows
end

function Style:ShowPreview()
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = self.previewFrame
    if not f then
        f = UI:CreatePanel(UIParent, "GuildOSStylePreview")
        f:SetSize(720, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local title = UI:CreateText(f, L["Style preview"], 13, C.gold.r, C.gold.g, C.gold.b)
        title:SetPoint("TOPLEFT", 12, -10)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -6, -6)
        close:SetScript("OnClick", function() f:Hide() end)
        local scroll, child = UI:CreateScrollFrame(f, "GuildOSStylePreviewScroll")
        scroll:SetPoint("TOPLEFT", 10, -34)
        scroll:SetPoint("BOTTOMRIGHT", -14, 10)
        child:SetWidth(680)
        local y = 0
        for i, r in ipairs(self:PreviewRows()) do
            local col = (i - 1) % 2
            if col == 0 and i > 1 then y = y + 70 end
            local x = col * 340
            local tex = child:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", x, -y)
            tex:SetSize(96, 60)
            if r.has then tex:SetAtlas(r.atlas) else tex:SetColorTexture(0.4, 0, 0, 0.6) end
            local label = UI:CreateText(child, r.role .. "\n" .. r.atlas
                .. (r.has and "" or ("\n|cffFF4444" .. L["missing"] .. "|r")), 9, C.text.r, C.text.g, C.text.b)
            label:SetPoint("TOPLEFT", x + 104, -y)
            label:SetWidth(230)
            label:SetJustifyH("LEFT")
        end
        child:SetHeight(y + 70)
        self.previewFrame = f
    end
    f:Show()
end
```

Add `UI\StylePreview.lua` to `GuildOS.toc` right after `UI\Helpers.lua`.

- [ ] **Step 4: Run the tests**

Expected: `tools/style.lua` sections 1-9 pass.

- [ ] **Step 5: Commit**

```bash
git add UI/StylePreview.lua GuildOS.toc tools/style.lua
git commit -m "feat: /gos style preview mostra as peças do estilo Forever lado a lado (#122)"
```

---

### Task 7: The new strings in the ten languages

**Files:**
- Modify: `Locales/ptBR.lua`, `esES.lua`, `deDE.lua`, `frFR.lua`, `ruRU.lua`, `koKR.lua`, `zhCN.lua`, `zhTW.lua` (append)

The keys, as written in the code:
- "Flat and dark: the look Guild OS was made with."
- "The game's own bronze frames, tabs and buttons. A beta: tell us what looks off."
- "The %s style is not available on this client; using %s."
- "The %s style is not available on this client."
- "Unknown style: %s. Styles: %s"
- "Reload the interface now to use the %s style?"
- "Reload"
- "Later"
- "in use"
- "not available here"
- "Interface style"
- "In use"
- "Style preview"
- "List the interface styles, or switch to one"
- "Show the Forever style's pieces side by side"

("Apply" and "missing" are already translated.)

- [ ] **Step 1: See which are missing**

Run: `"$LJ" -e 'ADDON="."' tools/locales.lua`
Expected: FAIL, `ptBR: every string the code shows is translated (15 still in English)`, and the same
for each language.

- [ ] **Step 2: Translate and append**

Translate the 15 keys for each of the 8 files, keeping every `%s` in order. Append them with a
`-- Interface styles (#122)` header, the way `scratchpad/l10n/apply.py` does. Run
`python scratchpad/l10n/validate.py <loc>` on each JSON first if you use the pipeline.

- [ ] **Step 3: Run the locales harness**

Expected: `locales: 40 checks passed`, with the string count up by 15 (the two existing keys don't count).

- [ ] **Step 4: Commit**

```bash
git add Locales/
git commit -m "feat: os textos dos estilos de interface nos dez idiomas (#122)"
```

---

### Task 8: Docs, review, PR, release

**Files:**
- Modify:
  - `docs/superpowers/specs/2026-10-07-ui-styles-design.md` §4.3, the button row: the rectangular
    button is the three-slice `128-redbutton-left/_center/right-c60`, found in the client's data;
  - the Data.lua header comment `"Forever" skin` → `GuildOS style`;
  - `.memory/functions-catalog.md`: a "Style.lua" section with the functions of the Interfaces blocks.

- [ ] **Step 1: Update the docs** as listed above.

- [ ] **Step 2: Every harness and luacheck**

Expected: all pass (including `style`, `window-shell`, `window-shell-forever` and `locales`), and
luacheck is `0 warnings / 0 errors`.

- [ ] **Step 3: Final whole-branch review** (executing-plans: one fresh reviewer, most capable model,
  with this plan's Review Focus).

- [ ] **Step 4: PR and ship**

```bash
bash C:/Users/danie/.claude/plugins/cache/ferion/ferion-engineering/0.2.1/hooks/flow-gate.sh stamp review
git push -u origin feat/122-camada-de-estilo
gh pr create --base main --title "feat: estilos de interface, com o estilo WoW: Forever (#122)" --body-file <scratchpad>/pr122.md
bash <scratchpad>/ship.sh 122 <pr> "<note>"
```

The PR body is in English, with `Closes #122` and `Part of #119`. It says:
- the Forever style is opt-in, in Settings and with `/gos style forever`;
- its pieces are candidates until the beta screenshots of `/gos style preview` confirm them;
- toggle buttons do not show their state in the Forever style yet (phase 2).
