# Responsive panels + command-centre hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Guild OS panel lay itself out from its container's real size, rebuild the hub into a two-column command centre, and fix the title-bar buttons that are dead in every window.

**Architecture:** One new `UI/Layout.lua` holds four layout primitives, three of them pure functions so they run under the existing `/gos selftest` harness. Panels consume those primitives from an `OnSizeChanged` callback instead of computing geometry from module-level constants. A one-line clipping net on the window content frame makes any remaining overflow a truncation rather than a paint over the screen.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary client API (Interface 20506). No build step. Lint via `luacheck`. In-client assertions via `BRutus.SelfTest` (`/gos selftest`).

## Global Constraints

- Lua 5.1 only: no `goto`, no bitwise operators, no `//` floor division, no integer division semantics.
- Indent 4 spaces, no tabs, no trailing semicolons.
- `local` everything at file scope; only write to `BRutus.*` for module registration.
- Never hardcode colours; use the `C` table from `UI/Helpers.lua`.
- All frames use `BackdropTemplate`.
- Guard client API calls that may be absent: `if frame.SetClipsChildren then ... end`.
- `.toc` load order matters: a file cannot reference anything defined in a file loaded after it. `UI/Layout.lua` goes immediately after `UI/Helpers.lua`.
- Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`). CI owns the `.toc` version bump and `CHANGELOG.md`; the commit subject IS the changelog line. Never edit either by hand.
- Never add AI/Claude attribution or `Co-Authored-By` trailers to commits.
- Roster column spec is fixed by the design doc section 5.3 and must not drift:
  `name` min 150 w 3 p 100 required, `level` min 34 w 0 p 95 required, `class` min 74 w 1 p 90 required, `avgIlvl` min 46 w 0 p 80, `race` min 70 w 1 p 60, `lastSeen` min 78 w 1 p 50, `professions` min 160 w 2 p 40, `zone` min 120 w 2 p 30. Gap 10.

## Verification tooling

Two runners exercise the same `BRutus.SelfTest` cases:

1. **Headless (used during implementation).** A `fengari` Lua VM under node stubs `BRutus:Print`, loads `Modules/SelfTest.lua` and `UI/Layout.lua`, and runs `BRutus.SelfTest:Run()`. This runs the real harness against the real file, so a green run is real evidence for the pure functions. Setup lives in the scratchpad, NOT in the repo:
   `C:\Users\danie\AppData\Local\Temp\claude\e--World-of-Warcraft--anniversary--Interface-AddOns-GuildOS\7f3628bf-3264-4726-b287-0ce3a11edc2c\scratchpad\luavm`
2. **In-client.** `/reload` then `/gos selftest`. This is the only runner that can exercise anything touching frames. Steps that need it are marked **[user-run]**: the implementing agent cannot run the game and must not claim these passed.

`luacheck` is available at `luacheck` and runs on every task.

---

### Task 1: Layout primitives

**Files:**
- Create: `UI/Layout.lua`
- Modify: `GuildOS.toc:106-107` (insert after `UI\Helpers.lua`)
- Create: scratchpad `luavm/run.js` (headless runner, not committed)

**Interfaces:**
- Produces:
  - `UI:ResolveColumns(spec, width, gap) -> layout` where `spec` is an array of `{ key, min, weight, priority, required }` and `layout` is an array of `{ key, x, w, shown }` in spec order, additionally keyed by `layout.byKey[key]`.
  - `UI:ResolveRows(height, rowH, reserved) -> n` (integer, >= 0)
  - `UI:FlowRows(widths, available, gap) -> rows` where `rows` is an array of arrays of indices into `widths`.
  - `UI:FlowBar(bar, buttons, opts) -> height` with `opts = { gap, rowGap, rowH }`.
  - `UI:MakeResponsive(container, layoutFn)` calling `layoutFn(container, width, height)`.

- [ ] **Step 1: Write the failing tests**

Create `UI/Layout.lua` containing ONLY the test registrations at first, so the run fails on missing functions:

```lua
----------------------------------------------------------------------
-- Guild OS - Layout primitives
-- Container-driven geometry: how many columns fit, how many rows fit,
-- how a button bar wraps. The three resolvers are pure functions of
-- their arguments so /gos selftest can exercise them with no frames.
----------------------------------------------------------------------
local UI = BRutus.UI

function UI:_RegisterLayoutTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    -- The roster spec from the design doc, section 5.3.
    local ROSTER = {
        { key = "name",        min = 150, weight = 3, priority = 100, required = true },
        { key = "level",       min = 34,  weight = 0, priority = 95,  required = true },
        { key = "class",       min = 74,  weight = 1, priority = 90,  required = true },
        { key = "avgIlvl",     min = 46,  weight = 0, priority = 80 },
        { key = "race",        min = 70,  weight = 1, priority = 60 },
        { key = "lastSeen",    min = 78,  weight = 1, priority = 50 },
        { key = "professions", min = 160, weight = 2, priority = 40 },
        { key = "zone",        min = 120, weight = 2, priority = 30 },
    }

    local function shownKeys(width)
        local out = {}
        for _, c in ipairs(UI:ResolveColumns(ROSTER, width, 10)) do
            if c.shown then out[#out + 1] = c.key end
        end
        return table.concat(out, ",")
    end

    S:Register("layout.columns_drop_by_priority", function()
        local cases = {
            -- table width -> expected shown set, from design doc 5.3
            { 1060, "name,level,class,avgIlvl,race,lastSeen,professions,zone" },
            {  720, "name,level,class,avgIlvl,race,lastSeen,professions" },
            {  520, "name,level,class,avgIlvl,race,lastSeen" },
            {  440, "name,level,class,avgIlvl,race" },
            {  340, "name,level,class,avgIlvl" },
            {  200, "name,level,class" },
        }
        for _, c in ipairs(cases) do
            local got = shownKeys(c[1])
            if got ~= c[2] then
                return false, string.format("at %d got [%s] want [%s]", c[1], got, c[2])
            end
        end
        return true
    end)

    S:Register("layout.columns_fit", function()
        for width = 120, 1400, 7 do
            local layout = UI:ResolveColumns(ROSTER, width, 10)
            local last
            for _, c in ipairs(layout) do
                if c.shown then
                    if c.w < 1 then return false, "zero-width column at " .. width end
                    last = c
                end
            end
            if not last then return false, "no columns shown at " .. width end
            local right = last.x + last.w
            if right > width + 0.5 then
                return false, string.format("overflow at %d: right edge %d", width, right)
            end
        end
        return true
    end)

    S:Register("layout.columns_respect_min_when_room", function()
        local layout = UI:ResolveColumns(ROSTER, 1400, 10)
        for _, c in ipairs(layout) do
            if c.shown and c.w < c.min then
                return false, c.key .. " below min at a width where everything fits"
            end
        end
        return true
    end)

    S:Register("layout.columns_required_never_dropped", function()
        for _, width in ipairs({ 400, 200, 90, 10, 0 }) do
            local byKey = UI:ResolveColumns(ROSTER, width, 10).byKey
            for _, key in ipairs({ "name", "level", "class" }) do
                if not byKey[key].shown then
                    return false, key .. " dropped at width " .. width
                end
            end
        end
        return true
    end)

    S:Register("layout.rows_fit", function()
        local cases = {
            { 400, 32, 36, 11 },
            { 400, 32, 0,  12 },
            { 0,   32, 36, 0  },
            { 10,  32, 36, 0  },
            { 480, 24, 96, 16 },
        }
        for _, c in ipairs(cases) do
            local n = UI:ResolveRows(c[1], c[2], c[3])
            if n ~= c[4] then
                return false, string.format("h=%d rowH=%d res=%d got %d want %d",
                    c[1], c[2], c[3], n, c[4])
            end
            if n * c[2] + c[3] > c[1] and n > 0 then
                return false, "rows overflow the available height"
            end
        end
        return true
    end)

    S:Register("layout.flow_wraps", function()
        local widths = { 116, 116, 116, 116, 116, 116, 116, 116 }
        local rows = UI:FlowRows(widths, 740, 4)
        if #rows ~= 2 then return false, "8 tabs in 740px want 2 rows, got " .. #rows end
        if #rows[1] ~= 6 then return false, "first row want 6 tabs, got " .. #rows[1] end
        if #rows[2] ~= 2 then return false, "second row want 2 tabs, got " .. #rows[2] end

        local wide = UI:FlowRows(widths, 2000, 4)
        if #wide ~= 1 then return false, "everything fits, want 1 row, got " .. #wide end

        local narrow = UI:FlowRows(widths, 40, 4)
        if #narrow ~= 8 then return false, "nothing fits, want 8 rows, got " .. #narrow end
        return true
    end)
end

UI:_RegisterLayoutTests()
```

Register it in the `.toc` right after Helpers so `BRutus.UI` exists:

```
# UI
UI\Helpers.lua
UI\Layout.lua
UI\FeatureRegistry.lua
```

- [ ] **Step 2: Build the headless runner and watch the tests fail**

Create the runner in the scratchpad `luavm` directory (`npm install fengari` has already been done there):

```js
// run.js
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = 'e:/World of Warcraft/_anniversary_/Interface/AddOns/GuildOS';
const FILES = ['Modules/SelfTest.lua', 'UI/Layout.lua'];

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// Minimal stand-in for the addon environment the pure files touch.
const bootstrap = `
BRutus = { UI = {} }
_G.__failed = 0
function BRutus:Print(msg)
    print(msg)
    if tostring(msg):find("FAIL") or tostring(msg):find("ERROR") then
        _G.__failed = _G.__failed + 1
    end
end
`;
function run(code, name) {
    if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
        console.error('LUA ERROR in ' + name + ': ' + lua.lua_tojsstring(L, -1));
        process.exit(1);
    }
}
run(bootstrap, 'bootstrap');
for (const f of FILES) run(fs.readFileSync(path.join(ROOT, f), 'utf8'), f);
run('local ok = BRutus.SelfTest:Run() if not ok then _G.__failed = math.max(_G.__failed, 1) end', 'run');
run('return _G.__failed', 'result');
const failed = lua.lua_tonumber(L, -1);
process.exit(failed > 0 ? 1 : 0);
```

Run: `node run.js`
Expected: FAIL, every case erroring with "attempt to call a nil value (method 'ResolveColumns')" and similar.

- [ ] **Step 3: Implement the four primitives**

Insert above `UI:_RegisterLayoutTests` in `UI/Layout.lua`:

```lua
----------------------------------------------------------------------
-- How many of these columns fit in `width`, and where does each go?
-- Columns are dropped lowest-priority-first until the minimums fit,
-- then the leftover is shared out by weight. `required` columns are
-- never dropped: if even they do not fit they shrink below their
-- minimum and their text truncates, because a squeezed table is more
-- useful than an empty one.
----------------------------------------------------------------------
function UI:ResolveColumns(spec, width, gap)
    gap = gap or 0
    width = math.max(width or 0, 0)

    local shown = {}
    for i, c in ipairs(spec) do shown[i] = true end

    local function needed()
        local total, n = 0, 0
        for i, c in ipairs(spec) do
            if shown[i] then
                total = total + c.min
                n = n + 1
            end
        end
        if n > 1 then total = total + gap * (n - 1) end
        return total, n
    end

    -- Drop the lowest-priority droppable column until the minimums fit.
    while true do
        local total = needed()
        if total <= width then break end
        local victim, worst
        for i, c in ipairs(spec) do
            if shown[i] and not c.required then
                if not worst or c.priority < worst then
                    victim, worst = i, c.priority
                end
            end
        end
        if not victim then break end   -- only required columns left: floor case
        shown[victim] = false
    end

    local total, count = needed()
    local slack = width - total
    local weightSum = 0
    for i, c in ipairs(spec) do
        if shown[i] then weightSum = weightSum + (c.weight or 0) end
    end

    local layout = { byKey = {} }
    local x = 0
    for i, c in ipairs(spec) do
        local entry = { key = c.key, x = 0, w = 0, min = c.min, shown = shown[i] }
        if shown[i] then
            local w = c.min
            if slack > 0 and weightSum > 0 then
                w = w + math.floor(slack * (c.weight or 0) / weightSum)
            elseif slack < 0 and count > 0 then
                -- Floor case: share the deficit across the survivors.
                w = math.max(1, w + math.floor(slack / count))
            end
            entry.x, entry.w = x, w
            x = x + w + gap
        end
        layout[#layout + 1] = entry
        layout.byKey[c.key] = entry
    end
    return layout
end

----------------------------------------------------------------------
-- How many rows of `rowH` fit in `height` once `reserved` (column
-- header, footer, paging strip) is carved out. Replaces every
-- VISIBLE_ROWS constant in the addon.
----------------------------------------------------------------------
function UI:ResolveRows(height, rowH, reserved)
    if not rowH or rowH <= 0 then return 0 end
    local usable = (height or 0) - (reserved or 0)
    if usable <= 0 then return 0 end
    return math.floor(usable / rowH)
end

----------------------------------------------------------------------
-- Break a list of button widths into rows that each fit `available`.
-- A button wider than the whole bar gets a row to itself rather than
-- looping forever.
----------------------------------------------------------------------
function UI:FlowRows(widths, available, gap)
    gap = gap or 0
    local rows, current, used = {}, {}, 0
    for i, w in ipairs(widths) do
        local advance = (#current > 0) and (gap + w) or w
        if #current > 0 and used + advance > available then
            rows[#rows + 1] = current
            current, used = {}, 0
            advance = w
        end
        current[#current + 1] = i
        used = used + advance
    end
    if #current > 0 then rows[#rows + 1] = current end
    return rows
end

----------------------------------------------------------------------
-- Lay `buttons` out inside `bar`, wrapping as needed. Returns the total
-- height so whatever sits below the bar can anchor to it.
----------------------------------------------------------------------
function UI:FlowBar(bar, buttons, opts)
    opts = opts or {}
    local gap    = opts.gap or 4
    local rowGap = opts.rowGap or 4
    local rowH   = opts.rowH or 26

    local widths = {}
    for i, b in ipairs(buttons) do widths[i] = b:GetWidth() end

    local rows = self:FlowRows(widths, bar:GetWidth(), gap)
    for r, row in ipairs(rows) do
        local x = 0
        for _, idx in ipairs(row) do
            local b = buttons[idx]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -((r - 1) * (rowH + rowGap)))
            x = x + widths[idx] + gap
        end
    end

    local height = #rows * rowH + math.max(0, #rows - 1) * rowGap
    bar:SetHeight(height)
    return height
end

----------------------------------------------------------------------
-- Re-run `layoutFn` whenever the container is resized. A grip drag
-- fires OnSizeChanged many times per second, so the work is coalesced
-- into one call per frame. Also fires once on the first OnShow, so the
-- initial layout is right before the user touches anything.
----------------------------------------------------------------------
function UI:MakeResponsive(container, layoutFn)
    container.__layout = layoutFn

    local function apply()
        container.__layoutPending = false
        local w, h = container:GetWidth(), container:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        BRutus:SafeCall(function() layoutFn(container, w, h) end)
    end

    container:SetScript("OnSizeChanged", function(self)
        if self.__layoutPending then return end
        self.__layoutPending = true
        C_Timer.After(0, apply)
    end)

    container:HookScript("OnShow", function(self)
        if self.__layoutDone then return end
        self.__layoutDone = true
        C_Timer.After(0, apply)
    end)

    -- A container that is already visible never fires OnShow again.
    if container:IsVisible() then
        container.__layoutDone = true
        C_Timer.After(0, apply)
    end
end
```

- [ ] **Step 4: Run the headless tests to verify they pass**

Run: `node run.js`
Expected: `SelfTest: 6 passed, 0 failed (6 total)`, exit code 0.

- [ ] **Step 5: Lint**

Run: `luacheck UI/Layout.lua`
Expected: `0 warnings / 0 errors`. `C_Timer` and `BRutus` must already be in `.luacheckrc` globals; add `C_Timer` if luacheck flags it.

- [ ] **Step 6: Commit**

```bash
git add UI/Layout.lua GuildOS.toc
git commit -m "feat: container-driven layout primitives with selftest coverage"
```

---

### Task 2: Clipping net and the dead title-bar buttons

**Files:**
- Modify: `UI/Helpers.lua` (add `Helpers:TitleBarButton` near `CreateCloseButton` at line 406)
- Modify: `UI/Window.lua:110-112`, `UI/Window.lua:137-140`
- Modify: `UI/Hub.lua:59-93`
- Modify: `UI/RosterFrame.lua:1106-1127`
- Modify: `UI/Layout.lua` (add the frame-level selftest)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `UI:TitleBarButton(bar, kind, ...) -> button`. `kind` is `"close"` (delegates to `CreateCloseButton`) or `"text"` (delegates to `CreateButton(bar, text, w, h)`, extra args forwarded). Always parents to `bar` and sets `SetFrameLevel(bar:GetFrameLevel() + 5)`.

**Why:** `UI/RosterFrame.lua:1108` already bumps its close button's frame level above the title bar. `UI/Window.lua:110` and `UI/Hub.lua:79-93` do not, and their bar is mouse-enabled across the full width, so it swallows the click. In the hub the bar is a `Button` whose `OnClick` collapses the card, so `x`, gear and expand are all inert.

- [ ] **Step 1: Write the failing test**

Append to `UI:_RegisterLayoutTests` in `UI/Layout.lua`:

```lua
    -- Regression guard for the dead-close-button bug: a title-bar button
    -- must outrank the mouse-enabled bar it sits on, or the bar eats the
    -- click. See UI/RosterFrame.lua:1108 for the original of this pattern.
    S:Register("ui.titlebar_button_outranks_bar", function()
        if not UI.TitleBarButton then return false, "UI:TitleBarButton missing" end
        if not CreateFrame then return true end   -- headless run: frames unavailable
        local host = CreateFrame("Frame", nil, UIParent)
        local bar  = CreateFrame("Frame", nil, host)
        bar:EnableMouse(true)
        local btn = UI:TitleBarButton(bar, "close")
        local ok = btn:GetParent() == bar
            and btn:GetFrameLevel() > bar:GetFrameLevel()
        host:Hide()
        if not ok then
            return false, string.format("level %d vs bar %d, parent %s",
                btn:GetFrameLevel(), bar:GetFrameLevel(),
                tostring(btn:GetParent() == bar))
        end
        return true
    end)
```

- [ ] **Step 2: Run the headless tests to verify the new case fails**

Run: `node run.js`
Expected: 6 passed, 1 failed, with `FAIL ui.titlebar_button_outranks_bar — UI:TitleBarButton missing`. The `if not CreateFrame then return true end` guard means that once the helper exists the headless runner passes it trivially; the real assertion runs in-client.

- [ ] **Step 3: Add the helper**

In `UI/Helpers.lua`, immediately after `Helpers:CreateCloseButton` (ends line 436):

```lua
----------------------------------------------------------------------
-- A button that lives on a title bar. The bar is mouse-enabled and
-- drag-registered across its full width, so a button at the same frame
-- level never receives the click: the bar swallows it. Parenting to the
-- bar and bumping the level is the fix, and putting it here means the
-- three title bars in the addon cannot drift apart again.
--   kind == "close" -> CreateCloseButton
--   kind == "text"  -> CreateButton(bar, text, width, height)
----------------------------------------------------------------------
function Helpers:TitleBarButton(bar, kind, ...)
    local btn
    if kind == "close" then
        btn = self:CreateCloseButton(bar)
    else
        btn = self:CreateButton(bar, ...)
    end
    btn:SetFrameLevel(bar:GetFrameLevel() + 5)
    return btn
end
```

- [ ] **Step 4: Use it in `UI/Window.lua`**

Replace lines 110-112:

```lua
    local close = self:TitleBarButton(bar, "close")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() UI:ToggleWindow(id) end)
```

And add the clipping net to the content frame (replace lines 137-140):

```lua
    -- Content area: everything under the title bar. Clipping is the net
    -- under the responsive layout: a panel that still miscalculates gets
    -- truncated inside its own window instead of painting over the screen.
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + 1))
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    win.content = content
```

- [ ] **Step 5: Use it in `UI/Hub.lua`**

The hub's bar is a `Button` whose `OnClick` collapses the card, which is the second half of the bug. Replace the bar block (lines 59-93) so the bar is drag-only and a chevron owns the collapse:

```lua
    -- Title bar: drag only. It is mouse-enabled across the full width, so
    -- anything clickable on it must go through UI:TitleBarButton.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); saveHubPos(f) end)
    f.bar = bar

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = UI:CreateHeaderText(bar, "GUILD OS", 11)
    title:SetPoint("LEFT", 8, 0)

    local close = UI:TitleBarButton(bar, "close")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local gear = UI:TitleBarButton(bar, "text", "|TInterface\\Icons\\INV_Misc_Gear_01:12|t", 20, 18)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetScript("OnClick", function() UI:OpenWindow("settings") end)
    UI:AddTooltip(gear, L["Settings"])

    local expand = UI:TitleBarButton(bar, "text", "[ ]", 20, 18)
    expand:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    expand:SetScript("OnClick", function()
        if BRutus.ToggleExpanded then BRutus:ToggleExpanded() end
    end)
    UI:AddTooltip(expand, L["Expanded mode"])
```

The chevron that replaces the bar's collapse click is added in Task 3 along with the summary line it belongs to. Until then the hub cannot be collapsed by clicking, which is correct: the old behaviour was the bug.

- [ ] **Step 6: Collapse the duplicate in `UI/RosterFrame.lua`**

Replace lines 1106-1127 so the three header buttons use the helper instead of three manual `SetFrameLevel(titleBar:GetFrameLevel() + 5)` calls:

```lua
    -- Close button
    local closeBtn = UI:TitleBarButton(titleBar, "close")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -10)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Sync button
    local syncBtn = UI:TitleBarButton(titleBar, "text", L["Sync"], 70, 24)
    syncBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    syncBtn:SetScript("OnClick", function()
        if BRutus.CommSystem then
            BRutus.CommSystem:FullSync()
        end
    end)

    -- Global search button (always available in the header)
    local searchBtn = UI:TitleBarButton(titleBar, "text", L["Search"], 80, 24)
    searchBtn:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
    searchBtn:SetScript("OnClick", function()
        if BRutus.Search then BRutus.Search:Show() end
    end)
```

- [ ] **Step 7: Verify**

Run: `node run.js`
Expected: 7 passed, 0 failed.

Run: `luacheck UI/Layout.lua UI/Helpers.lua UI/Window.lua UI/Hub.lua UI/RosterFrame.lua`
Expected: 0 warnings / 0 errors.

**[user-run]** `/reload`, then `/gos selftest` (expect `ui.titlebar_button_outranks_bar` to pass for real), then open two windows and click the `x` on each, plus the hub's `x`, gear and `[ ]`.

- [ ] **Step 8: Commit**

```bash
git add UI/Helpers.lua UI/Window.lua UI/Hub.lua UI/RosterFrame.lua UI/Layout.lua
git commit -m "fix: title-bar buttons lost their clicks to the drag bar"
```

---

### Task 3: The command-centre hub

**Files:**
- Modify: `UI/Hub.lua` (rewrite `Create` and `Refresh`, keep `MoreEntries`/`ToggleMorePage`/`Toggle`)
- Modify: `Locales/enUS.lua`, `Locales/ptBR.lua` (new strings)

**Interfaces:**
- Consumes: `UI:TitleBarButton` (Task 2), `UI:VisibleFeatures("hub")`, `UI:ToggleWindow`, `UI:OpenWindow`, `UI:IsWindowOpen`, `UI:CloseAllWindows`.
- Produces: `Hub:Refresh()` unchanged in signature, still safe to call on every window open/close.

Layout constants replacing the current single-column geometry:

```lua
local WIDTH      = 430
local RAIL_W     = 150      -- left feature list
local SIDE_W     = WIDTH - RAIL_W
local TITLE_H    = 24
local SUMMARY_H  = 20       -- guild name . members . online, plus the chevron
local ROW_H      = 22
local FOOT_H     = 22
local BLOCK_HEAD = 16       -- section caption height in the right column
local BLOCK_ROW  = 14       -- one line inside a section
```

- [ ] **Step 1: Add the new locale strings**

In `Locales/enUS.lua` (and the ptBR equivalents in `Locales/ptBR.lua`):

```lua
L["ONLINE NOW"]        = "ONLINE NOW"
L["NEXT EVENT"]        = "NEXT EVENT"
L["NEEDS YOU"]         = "NEEDS YOU"
L["YOU"]               = "YOU"
L["Only you online"]   = "Only you online"
L["All caught up"]     = "All caught up"
L["+%d more"]          = "+%d more"
L["%d inactive over %dd"] = "%d inactive over %dd"
L["%d trials expiring"]   = "%d trials expiring"
L["%d pending suggestions"] = "%d pending suggestions"
L["%d applicants waiting"]  = "%d applicants waiting"
L["create"]            = "create"
```

ptBR:

```lua
L["ONLINE NOW"]        = "ONLINE AGORA"
L["NEXT EVENT"]        = "PROXIMO EVENTO"
L["NEEDS YOU"]         = "PRECISA DE VOCE"
L["YOU"]               = "VOCE"
L["Only you online"]   = "So voce online"
L["All caught up"]     = "Tudo em dia"
L["+%d more"]          = "+%d mais"
L["%d inactive over %dd"] = "%d inativos ha mais de %dd"
L["%d trials expiring"]   = "%d trials vencendo"
L["%d pending suggestions"] = "%d sugestoes pendentes"
L["%d applicants waiting"]  = "%d candidatos aguardando"
L["create"]            = "criar"
```

- [ ] **Step 2: Build the summary line and the chevron**

Below the title bar block from Task 2, in `Hub:Create`:

```lua
    -- Summary line: guild identity plus the two numbers worth seeing
    -- without opening anything. The chevron owns collapse now, because
    -- the bar has to stay drag-only for the title buttons to work.
    local summary = CreateFrame("Frame", nil, f)
    summary:SetPoint("TOPLEFT", 0, -TITLE_H)
    summary:SetPoint("TOPRIGHT", 0, -TITLE_H)
    summary:SetHeight(SUMMARY_H)
    f.summary = summary

    f.summaryText = UI:CreateText(summary, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.summaryText:SetPoint("LEFT", 10, 0)
    f.summaryText:SetPoint("RIGHT", summary, "RIGHT", -26, 0)
    f.summaryText:SetJustifyH("LEFT")
    f.summaryText:SetWordWrap(false)

    local chevron = UI:CreateButton(f, "", 18, 16)
    chevron:SetPoint("RIGHT", summary, "RIGHT", -6, 0)
    chevron:SetFrameLevel(summary:GetFrameLevel() + 5)
    chevron:SetScript("OnClick", function()
        cfg().collapsed = not cfg().collapsed
        Hub:Refresh()
    end)
    f.chevron = chevron
```

- [ ] **Step 3: Build the two columns**

```lua
    -- Left rail: one row per enabled feature (the existing row pool).
    f.rail = CreateFrame("Frame", nil, f)
    f.rail:SetPoint("TOPLEFT", 0, -(TITLE_H + SUMMARY_H))
    f.rail:SetWidth(RAIL_W)
    f.rows = {}

    local railDiv = f.rail:CreateTexture(nil, "ARTWORK")
    railDiv:SetTexture("Interface\\Buttons\\WHITE8x8")
    railDiv:SetWidth(1)
    railDiv:SetPoint("TOPRIGHT", 0, 0)
    railDiv:SetPoint("BOTTOMRIGHT", 0, 0)
    railDiv:SetVertexColor(C.separator.r, C.separator.g, C.separator.b, C.separator.a)

    -- Right column: live blocks, rebuilt from a pooled line list.
    f.side = CreateFrame("Frame", nil, f)
    f.side:SetPoint("TOPLEFT", f.rail, "TOPRIGHT", 0, 0)
    f.side:SetWidth(SIDE_W)
    f.sideLines = {}
```

Pooled line acquisition, next to `acquireRow`:

```lua
----------------------------------------------------------------------
-- One line in the right column. `kind` picks the styling: "head" is a
-- section caption with an optional count, "line" is a clickable body
-- line, "dim" is a non-clickable empty state.
----------------------------------------------------------------------
local function acquireLine(f, index)
    local line = f.sideLines[index]
    if line then return line end

    line = CreateFrame("Button", nil, f.side, "BackdropTemplate")
    line:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    line:SetBackdropColor(0, 0, 0, 0)
    line:SetPoint("LEFT", f.side, "LEFT", 8, 0)
    line:SetPoint("RIGHT", f.side, "RIGHT", -8, 0)

    line.left = UI:CreateText(line, "", 10, C.text.r, C.text.g, C.text.b)
    line.left:SetPoint("LEFT", 0, 0)
    line.left:SetJustifyH("LEFT")
    line.left:SetWordWrap(false)

    line.right = UI:CreateText(line, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    line.right:SetPoint("RIGHT", 0, 0)
    line.right:SetJustifyH("RIGHT")

    line:SetScript("OnEnter", function(self)
        if self.__click then
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        end
    end)
    line:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
    line:SetScript("OnClick", function(self) if self.__click then self.__click() end end)

    f.sideLines[index] = line
    return line
end
```

- [ ] **Step 4: Build the block data functions**

Add above `Hub:Refresh`. These are the only new data reads, and each one guards the module it depends on:

```lua
----------------------------------------------------------------------
-- The right column's content, as flat description tables. Keeping the
-- data separate from the frames means Refresh only ever positions
-- pooled lines, and each block can be reasoned about on its own.
----------------------------------------------------------------------
local MAX_ONLINE = 5

function Hub:OnlineBlock()
    local list, total = {}, 0
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, class, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            total = total + 1
            if #list < MAX_ONLINE then
                list[#list + 1] = {
                    name  = Ambiguate(name, "guild"),
                    level = level,
                    class = class,
                    classFile = classFile,
                }
            end
        end
    end
    return list, total
end

function Hub:AlertBlock()
    local out = {}
    if not BRutus:IsOfficer() then return out end

    local gm = BRutus.GuildManager
    if gm and gm.CountInactive then
        local days = BRutus:GetSetting("inactiveDays") or 30
        local n = gm:CountInactive(days)
        if n and n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d inactive over %dd"], n, days),
                go   = function() UI:OpenWindow("management", "inactive") end,
            }
        end
    end

    local tt = BRutus.TrialTracker
    if tt and tt.CountExpiring then
        local n = tt:CountExpiring()
        if n and n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d trials expiring"], n),
                go   = function() UI:OpenWindow("trials") end,
            }
        end
    end

    if gm and gm.CountPendingSuggestions then
        local n = gm:CountPendingSuggestions()
        if n and n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d pending suggestions"], n),
                go   = function() UI:OpenWindow("management", "suggest") end,
            }
        end
    end

    local rs = BRutus.RecruitmentSystem
    if rs and rs.CountInbox then
        local n = rs:CountInbox()
        if n and n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d applicants waiting"], n),
                go   = function() UI:OpenWindow("recruitment") end,
            }
        end
    end
    return out
end

function Hub:YouBlock()
    local bits = {}
    local me = BRutus:GetPlayerKey()

    local pts = BRutus.Points
    if pts and pts.GetBalance and BRutus:IsFeatureEnabled("dkp") then
        local n = pts:GetBalance(me)
        if n then bits[#bits + 1] = string.format("%d DKP", n) end
    end

    local rt = BRutus.RaidTracker
    if rt and rt.GetAttendancePct then
        local pct = rt:GetAttendancePct(me)
        if pct then bits[#bits + 1] = string.format("%s %d%%", L["Attendance"], pct) end
    end

    local ws = BRutus.WishlistSystem
    if ws and ws.CountOpen then
        local n = ws:CountOpen(me)
        if n and n > 0 then bits[#bits + 1] = string.format(L["%d on wishlist"], n) end
    end

    return table.concat(bits, " . ")
end
```

Before writing these, confirm each helper exists with exactly that name and arity. Run:

```bash
grep -nE "function (GuildManager|TrialTracker|RecruitmentSystem|Points|RaidTracker|WishlistSystem):(CountInactive|CountExpiring|CountPendingSuggestions|CountInbox|GetBalance|GetAttendancePct|CountOpen)" Modules/*.lua
```

For each one that does NOT exist, either use the real accessor the module already exposes, or add a small counting function to that module in this task. Do not invent a call and leave it guarded: a permanently-nil guard means the block silently never renders. Record what you found in the commit body.

- [ ] **Step 5: Rewrite `Hub:Refresh`**

```lua
function Hub:Refresh()
    local f = self.frame
    if not f then return end
    local c = cfg()

    local online, onlineTotal = self:OnlineBlock()
    local guildName = GetGuildInfo("player") or "Guild OS"
    local memberCount = GetNumGuildMembers() or 0

    f.chevron.label:SetText(c.collapsed and ">" or "v")

    if c.collapsed then
        local alerts = self:AlertBlock()
        local bits = { string.format(L["%d online of %d"], onlineTotal, memberCount) }
        local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
        if e then bits[#bits + 1] = e.title or "?" end
        if #alerts > 0 then bits[#bits + 1] = "|cffFFD700" .. #alerts .. " !|r" end
        f.summaryText:SetText(table.concat(bits, " . "))

        for _, row in pairs(f.rows) do row:Hide() end
        for _, line in pairs(f.sideLines) do line:Hide() end
        f.rail:Hide(); f.side:Hide(); f.footer:Hide()
        f:SetHeight(TITLE_H + SUMMARY_H)
        return
    end

    f.summaryText:SetText(string.format("%s . %d %s . %d online",
        guildName, memberCount, L["members"], onlineTotal))
    f.rail:Show(); f.side:Show()

    -- Left rail
    local defs = self.morePage and self:MoreEntries() or UI:VisibleFeatures("hub")
    local railY, shown = 0, 0
    for i, def in ipairs(defs) do
        local row = acquireRow(f, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.rail, "TOPLEFT", 6, -railY)
        row:SetWidth(RAIL_W - 12)
        row.label:SetText(def.label)
        if def.icon then row.icon:SetTexture(def.icon) else row.icon:SetTexture(nil) end
        row.dot:SetShown(UI:IsWindowOpen(def.id))
        local n = def.badge and def.badge() or 0
        row.badge:SetText((n and n > 0) and tostring(n) or "")
        row:SetScript("OnClick", function()
            if def.run then def.run()
            elseif def.sub then UI:OpenWindow(def.id, def.sub)
            else UI:ToggleWindow(def.id) end
        end)
        row:Show()
        railY = railY + ROW_H
        shown = i
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end

    -- Right column
    local sideY, used = 0, 0
    local function emit(kind, text, rightText, click, colour)
        used = used + 1
        local line = acquireLine(f, used)
        local h = (kind == "head") and BLOCK_HEAD or BLOCK_ROW
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", f.side, "TOPLEFT", 8, -sideY)
        line:SetPoint("TOPRIGHT", f.side, "TOPRIGHT", -8, -sideY)
        line:SetHeight(h)
        if kind == "head" then
            line.left:SetFont(select(1, line.left:GetFont()), 9, "OUTLINE")
            line.left:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            line.left:SetFont(select(1, line.left:GetFont()), 10, "OUTLINE")
            local col = colour or C.text
            line.left:SetTextColor(col.r, col.g, col.b)
        end
        line.left:SetText(text or "")
        line.right:SetText(rightText or "")
        line.__click = click
        line:Show()
        sideY = sideY + h
    end

    emit("head", L["ONLINE NOW"], tostring(onlineTotal))
    if #online == 0 then
        emit("dim", L["Only you online"], nil, nil, C.textDim)
    else
        for _, m in ipairs(online) do
            local col = (m.classFile and RAID_CLASS_COLORS[m.classFile]) or C.text
            emit("line", m.name, string.format("%d  %s", m.level or 0, m.class or ""),
                function() BRutus:ShowMemberDetailByName(m.name) end, col)
        end
        if onlineTotal > #online then
            emit("line", string.format(L["+%d more"], onlineTotal - #online), nil,
                function() UI:OpenWindow("roster") end, C.textDim)
        end
    end
    sideY = sideY + 6

    if BRutus:IsFeatureEnabled("guild") then
        emit("head", L["NEXT EVENT"])
        local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
        if e then
            emit("line", e.title or "?", nil,
                function() UI:OpenWindow("guild", "calendar") end)
            emit("line", BRutus.Calendar:DescribeWhen(e), nil,
                function() UI:OpenWindow("guild", "calendar") end, C.textDim)
        else
            emit("dim", L["No upcoming events scheduled."], nil, nil, C.textDim)
        end
        sideY = sideY + 6
    end

    if BRutus:IsOfficer() then
        local alerts = self:AlertBlock()
        emit("head", L["NEEDS YOU"], #alerts > 0 and tostring(#alerts) or nil)
        if #alerts == 0 then
            emit("dim", L["All caught up"], nil, nil, C.online)
        else
            for _, a in ipairs(alerts) do
                emit("line", "> " .. a.text, nil, a.go)
            end
        end
        sideY = sideY + 6
    end

    local you = self:YouBlock()
    if you ~= "" then
        emit("head", L["YOU"])
        emit("line", you, nil, nil, C.textDim)
    end

    for i = used + 1, #f.sideLines do f.sideLines[i]:Hide() end

    local bodyH = math.max(railY, sideY) + 6
    f.rail:SetHeight(bodyH)
    f.side:SetHeight(bodyH)

    local y = TITLE_H + SUMMARY_H + bodyH
    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", 0, -(y + 2))
    f.footer:SetPoint("TOPRIGHT", 0, -(y + 2))
    f.footer:Show()
    f:SetWidth(WIDTH)
    f:SetHeight(y + 2 + FOOT_H)
end
```

`BRutus:ShowMemberDetailByName` and `BRutus.Calendar:DescribeWhen` must be confirmed the same way as Step 4. If `ShowMemberDetailByName` does not exist, look up the member in `BRutus.db.members` by player key and call the existing `BRutus:ShowMemberDetail(data)`.

- [ ] **Step 6: Keep the hub live while it is open**

Append to `Hub:Create`, before `table.insert(UISpecialFrames, "GuildOSHub")`:

```lua
    -- The online list goes stale fast. Tick only while the card is up:
    -- a hidden hub must cost nothing.
    f:SetScript("OnShow", function(self)
        if self.__ticker then return end
        self.__ticker = C_Timer.NewTicker(10, function() Hub:Refresh() end)
    end)
    f:SetScript("OnHide", function(self)
        if self.__ticker then self.__ticker:Cancel(); self.__ticker = nil end
    end)
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() if f:IsShown() then Hub:Refresh() end end)
```

- [ ] **Step 7: Verify**

Run: `luacheck UI/Hub.lua Locales/enUS.lua Locales/ptBR.lua`
Expected: 0 warnings / 0 errors.

**[user-run]** `/reload`, `/gos` to open the hub. Check: both columns render, the right column's blocks are populated, clicking a name opens that member's detail, clicking an alert opens the right window on the right sub-tab, the chevron collapses to a one-line summary and back, and `x` / gear / `[ ]` all work.

- [ ] **Step 8: Commit**

```bash
git add UI/Hub.lua Locales/enUS.lua Locales/ptBR.lua
git commit -m "feat: two-column command-centre hub with live guild blocks"
```

---

### Task 4: Responsive roster

**Files:**
- Modify: `UI/RosterFrame.lua:28-51` (column spec), `:242-500` (`CreateRosterPanel`), `:1436-1577` (`CreateRosterRow`), `:890-900` (`UpdateRosterUI`)
- Modify: `UI/Features.lua:23-28` (roster `minW`/`minH`)

**Interfaces:**
- Consumes: `UI:ResolveColumns`, `UI:ResolveRows`, `UI:MakeResponsive` (Task 1).
- Produces: `host.colLayout` (the current `ResolveColumns` result), `row:ApplyColumns(layout)`, `host.visibleRows` (integer).

- [ ] **Step 1: Replace the column table with a resolver spec**

Replace lines 28-38. The `status` column folds into `name` (the dot is drawn inside the name cell), so the table drops from 9 entries to 8:

```lua
-- Column definitions. `min` is the narrowest the column may be drawn,
-- `weight` its share of any leftover width, `priority` the order in
-- which columns are dropped as the window narrows (lowest goes first),
-- and `required` marks the three that never drop. The old 20px unlabelled
-- status column folded into `name`: the online dot is drawn inside the
-- name cell, so it is not something the user can lose.
-- Attunements and Attendance live in their own dedicated places (member
-- detail / Raids tab / KPI card), so they are intentionally omitted here.
local COLUMNS = {
    { key = "name",        label = L["MEMBER"],      min = 150, weight = 3, priority = 100, required = true, align = "LEFT" },
    { key = "level",       label = L["LVL"],         min = 34,  weight = 0, priority = 95,  required = true, align = "CENTER" },
    { key = "class",       label = L["CLASS"],       min = 74,  weight = 1, priority = 90,  required = true, align = "LEFT" },
    { key = "avgIlvl",     label = L["iLVL"],        min = 46,  weight = 0, priority = 80,  align = "CENTER" },
    { key = "race",        label = L["RACE"],        min = 70,  weight = 1, priority = 60,  align = "LEFT" },
    { key = "lastSeen",    label = L["LAST SEEN"],   min = 78,  weight = 1, priority = 50,  align = "RIGHT" },
    { key = "professions", label = L["PROFESSIONS"], min = 160, weight = 2, priority = 40,  align = "LEFT" },
    { key = "zone",        label = L["ZONE"],        min = 120, weight = 2, priority = 30,  align = "LEFT" },
}

local COL_GAP = 10
local TABLE_INSET = 24   -- left + right margin inside the table area
```

Delete `local FRAME_WIDTH = 1080 + RAIL_WIDTH` and `local FRAME_HEIGHT = ...` only after Step 6 confirms nothing else reads them. Run `grep -n "FRAME_WIDTH\|FRAME_HEIGHT" UI/RosterFrame.lua` and convert every remaining reader.

- [ ] **Step 2: Give the row an ApplyColumns method**

In `CreateRosterRow`, the elements stay as they are but stop being positioned at build time. Replace the `xOff` walk (lines 1452-1551) so each element is created unanchored, then add:

```lua
    row.cells = {
        name        = { nameText, classIcon, statusDot, addonDot },
        level       = { levelText },
        class       = { classText },
        race        = { raceText },
        avgIlvl     = { ilvlText },
        professions = { profText },
        zone        = { zoneText },
        lastSeen    = { lastSeenText },
    }

    -- Reposition every cell from a resolved layout. Called once per row
    -- per resize, never per data update.
    function row:ApplyColumns(layout)
        for _, col in ipairs(layout) do
            local cell = self.cells[col.key]
            if cell then
                for _, el in ipairs(cell) do el:SetShown(col.shown) end
            end
        end
        local n = layout.byKey
        if n.name.shown then
            self.statusDot:ClearAllPoints()
            self.statusDot:SetPoint("LEFT", n.name.x + 6, 0)
            self.classIcon:ClearAllPoints()
            self.classIcon:SetPoint("LEFT", n.name.x + 20, 0)
            self.nameText:SetWidth(math.max(20, n.name.w - 48))
        end
        local function place(key, fs)
            local c = n[key]
            if not c or not c.shown then return end
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", c.x, 0)
            fs:SetWidth(c.w)
        end
        place("level",       self.levelText)
        place("class",       self.classText)
        place("race",        self.raceText)
        place("avgIlvl",     self.ilvlText)
        place("professions", self.profText)
        place("zone",        self.zoneText)
        place("lastSeen",    self.lastSeenText)
    end
```

- [ ] **Step 3: Make the header follow the same layout**

Replace the header loop at lines 418-424 so the buttons are stored by key and repositioned rather than placed once:

```lua
    host.headerButtons = {}
    host.headerByKey = {}
    for _, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetHeight(HEADER_HEIGHT)
        local text = UI:CreateHeaderText(btn, col.label, 10)
        text:SetPoint("LEFT", 0, 0)
        btn.text = text
        host.headerByKey[col.key] = btn
        host.headerButtons[#host.headerButtons + 1] = btn
```

(keep the existing sort-click wiring that follows, unchanged)

- [ ] **Step 4: Grow the row pool on demand**

Replace lines 483-487:

```lua
    host.scrollFrame = scrollFrame
    host.rows = {}
    host.visibleRows = 0

    -- Rows are pooled and grown on demand: how many exist depends on how
    -- tall the window is right now, which changes as the grip is dragged.
    host.AcquireRows = function(n)
        for i = #host.rows + 1, n do
            host.rows[i] = CreateRosterRow(rosterContainer, i, uid)
            if host.colLayout then host.rows[i]:ApplyColumns(host.colLayout) end
        end
        for i = 1, #host.rows do
            host.rows[i]:SetShown(i <= n)
        end
        host.visibleRows = n
    end
```

- [ ] **Step 5: Wire the layout callback**

At the end of `CreateRosterPanel`, before it returns:

```lua
    UI:MakeResponsive(parent, function(_, w, h)
        -- KPI band: the same drop-by-priority rule as the table.
        local kpiLayout = UI:ResolveColumns(KPI_SPEC, w - 24, 10)
        for _, entry in ipairs(kpiLayout) do
            local card = host.kpiCards[entry.key]
            if card then
                card:SetShown(entry.shown)
                if entry.shown then
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", 12 + entry.x, -8)
                    card:SetWidth(entry.w)
                end
            end
        end

        -- Table columns.
        local tableW = w - RAIL_WIDTH - TABLE_INSET
        local layout = UI:ResolveColumns(COLUMNS, tableW, COL_GAP)
        host.colLayout = layout
        for _, col in ipairs(layout) do
            local btn = host.headerByKey[col.key]
            if btn then
                btn:SetShown(col.shown)
                if col.shown then
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", 10 + col.x, 0)
                    btn:SetWidth(col.w)
                end
            end
        end

        -- Rows.
        local listH = h - KPI_BAND_HEIGHT - HEADER_HEIGHT - BOTTOM_BAR_H
        local n = UI:ResolveRows(listH, ROW_HEIGHT, 0)
        host.AcquireRows(n)
        for i = 1, n do host.rows[i]:ApplyColumns(layout) end

        BRutus:RefreshRosterUI()
    end)
```

`KPI_SPEC` is a new module-level table next to `COLUMNS`:

```lua
-- KPI cards use the same resolver as the table so they disappear in a
-- deliberate order instead of running off the edge.
local KPI_SPEC = {
    { key = "members",  min = 96, weight = 1, priority = 100, required = true },
    { key = "online",   min = 96, weight = 1, priority = 95,  required = true },
    { key = "ilvl",     min = 96, weight = 1, priority = 90,  required = true },
    { key = "players",  min = 96, weight = 1, priority = 40 },
    { key = "addon",    min = 96, weight = 1, priority = 50 },
    { key = "att",      min = 96, weight = 1, priority = 60 },
}
```

Change `MakeKpiCard` to record the frame: `host.kpiCards = {}` before the six calls, and each call stores `host.kpiCards[key] = card`. `MakeKpiCard` currently returns only font strings, so give it a `key` first argument and have it do `host.kpiCards[key] = card` internally.

- [ ] **Step 6: Replace the remaining fixed row counts**

`grep -n "VISIBLE_ROWS" UI/RosterFrame.lua` and replace each with `self.visibleRows` (inside `UpdateRosterUI`, line 896-898) or `host.visibleRows`. Guard the zero case: `if (self.visibleRows or 0) < 1 then return end` at the top of the row loop, so a window dragged to nothing does not error.

Delete the now-unused `local VISIBLE_ROWS = 18`.

- [ ] **Step 7: Set the real minimums**

In `UI/Features.lua`, the roster entry:

```lua
    w = 1000, h = 620, minW = 520, minH = 380,
```

- [ ] **Step 8: Verify**

Run: `luacheck UI/RosterFrame.lua UI/Features.lua`
Expected: 0 warnings / 0 errors.

Run: `grep -n "FRAME_WIDTH\|FRAME_HEIGHT\|VISIBLE_ROWS" UI/RosterFrame.lua`
Expected: no output.

**[user-run]** `/reload`, open the Roster window, drag the grip from full width down to the minimum. Expect columns to disappear in the order ZONE, PROFESSIONS, LAST SEEN, RACE, and nothing to draw outside the frame at any point. Then open expanded mode (`[ ]` on the hub) and confirm the roster tab renders the same way.

- [ ] **Step 9: Commit**

```bash
git add UI/RosterFrame.lua UI/Features.lua
git commit -m "refactor: roster table and KPI band lay out from their container"
```

---

### Task 5: Responsive recipes

**Files:**
- Modify: `UI/RecipesPanel.lua:9-10`, `:106` (filter row), `:239-290` (header + list), `:372-390` (update loop)

**Interfaces:**
- Consumes: `UI:ResolveColumns`, `UI:ResolveRows`, `UI:FlowBar`, `UI:MakeResponsive`.

- [ ] **Step 1: Add the column spec**

Replace `local VISIBLE_ROWS = 20` with:

```lua
local RECIPE_COLUMNS = {
    { key = "recipe",     min = 200, weight = 3, priority = 100, required = true },
    { key = "profession", min = 120, weight = 0, priority = 40 },
    { key = "crafters",   min = 140, weight = 2, priority = 60, required = true },
}
local COL_GAP     = 10
local LIST_TOP    = 96   -- y of the first row, below the top bar + header
local LIST_BOTTOM = 12
```

- [ ] **Step 2: Wire the layout callback**

At the end of `BRutus:CreateRecipesPanel`, before it returns:

```lua
    UI:MakeResponsive(parent, function(_, w, h)
        UI:FlowBar(filterRow, filterButtons, { gap = 4, rowH = 22 })

        local layout = UI:ResolveColumns(RECIPE_COLUMNS, w - 20 - COL_GAP, COL_GAP)
        panel.colLayout = layout
        for _, col in ipairs(layout) do
            local hdr = headerByKey[col.key]
            if hdr then
                hdr:SetShown(col.shown)
                if col.shown then
                    hdr:ClearAllPoints()
                    hdr:SetPoint("LEFT", col.x, 0)
                    hdr:SetWidth(col.w)
                end
            end
        end

        panel.visibleRows = UI:ResolveRows(h - LIST_TOP - LIST_BOTTOM, ROW_HEIGHT, 0)
        acquireRows(panel.visibleRows)
        for i = 1, panel.visibleRows do rows[i]:ApplyColumns(layout) end
        UpdateList()
    end)
```

Mirror Task 4's shape: `headerByKey` collected while the header is built, `acquireRows(n)` growing the pool, and `row:ApplyColumns(layout)` positioning `row.recipeText`, `row.profText` (plus its icon) and `row.craftersText`.

- [ ] **Step 3: Replace the fixed counts**

`grep -n "VISIBLE_ROWS" UI/RecipesPanel.lua` and swap each for `panel.visibleRows`, including the `FauxScrollFrame_Update(scrollFrame, total, panel.visibleRows, ROW_HEIGHT)` call at line 383. Guard `if (panel.visibleRows or 0) < 1 then return end` before the row loop.

- [ ] **Step 4: Verify**

Run: `luacheck UI/RecipesPanel.lua` -> 0 warnings / 0 errors.
Run: `grep -n VISIBLE_ROWS UI/RecipesPanel.lua` -> no output.

**[user-run]** `/reload`, open Recipes, drag the grip. Rows must stop at the bottom edge, the profession icon bar must wrap rather than overflow, and PROFESSION must drop out below ~520px.

- [ ] **Step 5: Commit**

```bash
git add UI/RecipesPanel.lua
git commit -m "refactor: recipes list follows its container height and width"
```

---

### Task 6: Responsive Leadership

**Files:**
- Modify: `UI/ManagementPanel.lua:1034-1100` (`CreateManagementPanel`), plus the six list sub-builders

**Interfaces:**
- Consumes: `UI:FlowBar`, `UI:ResolveRows`, `UI:ResolveColumns`, `UI:MakeResponsive`.

- [ ] **Step 1: Flow the sub-tab bar**

Replace the fixed walk at lines 1064-1071:

```lua
    local subTabList = {}
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 0)
        btn:SetWidth(math.max(70, btn.text and btn.text:GetStringWidth() + 20 or 90))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        subTabList[#subTabList + 1] = btn
    end
```

`UI:CreateTab`'s third argument is a width; confirm the label FontString's field name with `grep -n "function Helpers:CreateTab" -A 20 UI/Helpers.lua` and use the real one instead of `btn.text` if it differs.

- [ ] **Step 2: Make the sub-panels follow the bar's height**

Replace `makeSubPanel` (lines 1074-1080) so the panels anchor to the bar rather than a hardcoded `-42`:

```lua
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -8)
        p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end
```

- [ ] **Step 3: Wire the layout callback**

At the end of `CreateManagementPanel`:

```lua
    UI:MakeResponsive(parent, function(_, w, _)
        bar:SetWidth(w - 20)
        UI:FlowBar(bar, subTabList, { gap = 4, rowGap = 4, rowH = 26 })
        local info = parent.subPanels[parent.activeSub]
        if info and info.relayout then BRutus:SafeCall(info.relayout) end
    end)
```

- [ ] **Step 4: Give each list sub-panel a relayout**

Each of the six list builders (`BuildRanksSub`, `BuildInactiveSub`, `BuildSuggestSub`, `BuildLogSub`, `BuildBanSub`, `BuildEngageSub`) currently creates a fixed row count. Convert each to the same three-part shape used in Task 4: a pooled `acquireRows(n)`, a `ResolveRows` call sized from the sub-panel's own height, and a `relayout` returned alongside `refresh` so `parent.subPanels[key] = { panel = p, refresh = r, relayout = rl }`.

Update the builder call site (line 1092-1095) to store the third value.

- [ ] **Step 5: Verify**

Run: `luacheck UI/ManagementPanel.lua` -> 0 warnings / 0 errors.

**[user-run]** `/reload`, open Leadership. At the default 760px the 8 sub-tabs must wrap to two rows with the content starting below them, not behind them. Drag wide: they collapse back to one row and the content moves up. Drag narrow: list rows stop at the bottom edge.

- [ ] **Step 6: Commit**

```bash
git add UI/ManagementPanel.lua
git commit -m "refactor: leadership sub-tabs wrap and its lists follow the window"
```

---

### Task 7: Recruitment scroll and anchors

**Files:**
- Modify: `UI/RosterFrame.lua:2560-2960` (`CreateRecruitmentPanel`)

**Interfaces:**
- Consumes: `UI:CreateScrollFrame`, `UI:MakeResponsive`.

**Gotcha:** `UI:CreateScrollFrame` does NOT anchor the scroll frame it returns. The caller must `SetAllPoints` (or explicit points) or the content clips to 0x0 and the panel renders blank with no Lua error.

- [ ] **Step 1: Wrap the section stack in a scroll frame**

The panel is a vertical stack of sections (Auto-Recruit, Welcome Message, Recruitment Beacon) that has a natural height well over the 500px window. Anchoring alone cannot fix that, so it gets a real scroll frame:

```lua
    local scroll, content = UI:CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    UI:SkinScrollBar(scroll)
    content:SetWidth(1)   -- real width set by the layout callback below
```

Reparent every existing section to `content` and keep their relative vertical stacking.

- [ ] **Step 2: Replace the fixed widths**

Every one of these becomes a container-relative anchor:

| Line | Was | Becomes |
|---|---|---|
| 2568 | `discordText:SetWidth(400)` | anchor LEFT+RIGHT with a 12px inset |
| 2573 | `msgText:SetWidth(700)` | anchor LEFT+RIGHT with a 12px inset |
| 2749 | `infoNote:SetWidth(700)` | anchor LEFT+RIGHT with a 12px inset |
| 2861 | `msgBox:SetSize(680, 40)` | `SetHeight(40)` plus LEFT+RIGHT anchors, leaving room for the Save button |
| 2928 | `discordBox:SetSize(400, 22)` | `SetHeight(22)` plus LEFT+RIGHT anchors |
| 2952 | `welcomeBox:SetSize(680, 40)` | `SetHeight(40)` plus LEFT+RIGHT anchors |

- [ ] **Step 3: Wire the layout callback**

```lua
    UI:MakeResponsive(parent, function(_, w, _)
        content:SetWidth(math.max(200, w - 32))
    end)
```

- [ ] **Step 4: Verify**

Run: `luacheck UI/RosterFrame.lua` -> 0 warnings / 0 errors.

**[user-run]** `/reload`, open Recruitment. Every section must be reachable by scrolling, nothing may render below the window's bottom edge, and the edit boxes must resize with the window. Confirm the panel is not blank (that is the `SetAllPoints` gotcha biting).

- [ ] **Step 5: Commit**

```bash
git add UI/RosterFrame.lua
git commit -m "fix: recruitment panel scrolls instead of spilling past the window"
```

---

### Task 8: Remaining panel sweep

**Files:**
- Modify: `UI/AlliancePanel.lua:993,1049,1066,1091,1469,1485`
- Modify: `UI/FeaturePanels.lua:361,377,929,965,1003,1283`
- Modify: `UI/CorePanel.lua`
- Modify: `UI/Dashboard.lua`

- [ ] **Step 1: Alliance**

Sub-tabs at `x = x + 124` (line 1485) go through `UI:FlowBar`, same shape as Task 6 Step 1. The four `SetWidth(460)` hint texts (993, 1049, 1066, 1091) become LEFT+RIGHT anchors on their parent.

- [ ] **Step 2: FeaturePanels scroll contents**

Each `xContent:SetSize(800, 1)` becomes width-follows-parent. Add one layout callback per panel:

```lua
    UI:MakeResponsive(parent, function(_, w, _)
        sessionContent:SetWidth(math.max(200, w - 32))
    end)
```

Repeat for `attContent` (377), `lootContent` (929), `eqContent` (965), `srContent` (1003), `trialContent` (1283), each inside its own panel builder.

- [ ] **Step 3: CorePanel and Dashboard**

`LIST_W = 220` stays fixed (it is a genuine fixed sidebar). Anchor the right-hand pane to the container instead of a computed width. In `UI/Dashboard.lua`, convert any fixed card row to `ResolveColumns` with all cards at equal weight.

- [ ] **Step 4: Verify**

Run: `luacheck UI/` -> 0 warnings / 0 errors across the whole directory.

**[user-run]** `/reload`, open Alliance, Raids, Loot, Trials, Cores and the Home tab in expanded mode. Drag each to its minimum and to full screen. Nothing may draw outside a window.

- [ ] **Step 5: Commit**

```bash
git add UI/AlliancePanel.lua UI/FeaturePanels.lua UI/CorePanel.lua UI/Dashboard.lua
git commit -m "refactor: remaining panels follow their container width"
```

---

### Task 9: Registry minimums and final verification

**Files:**
- Modify: `UI/Features.lua:23-112`

- [ ] **Step 1: Set real minimums per feature**

Every windowed feature gets a `minW`/`minH` matching what its converted layout can actually take, replacing the generic 380x260 fallback at `UI/Window.lua:117`:

```lua
    roster:      w = 1000, h = 620, minW = 520, minH = 380
    raids:       w = 780,  h = 540, minW = 560, minH = 360
    loot:        w = 680,  h = 470, minW = 480, minH = 320
    dkp:         w = 620,  h = 440, minW = 440, minH = 300
    wishlist:    w = 680,  h = 470, minW = 480, minH = 320
    recipes:     w = 700,  h = 500, minW = 400, minH = 300
    guild:       w = 720,  h = 520, minW = 500, minH = 360
    alliance:    w = 900,  h = 600, minW = 620, minH = 420
    recruitment: w = 720,  h = 560, minW = 460, minH = 340
    trials:      w = 620,  h = 420, minW = 440, minH = 300
    management:  w = 900,  h = 560, minW = 560, minH = 380
    settings:    w = 560,  h = 520, resizable = false
```

Note the two default-size corrections: `recruitment` grows from 500 to 560 tall and `management` from 760x540 to 900x560, so both open at a size their content actually fits.

- [ ] **Step 2: Full verification**

Run: `node run.js`
Expected: all cases pass, exit 0.

Run: `luacheck .`
Expected: 0 warnings / 0 errors.

Run: `git status --short`
Expected: clean apart from what is being committed.

**[user-run]** `/reload`, then `/gos selftest`. Expect 0 failures. Then open every window from the hub in turn and confirm: it opens at a sensible default size, the grip stops at a size where the content still reads, nothing paints outside, and the `x` closes it.

- [ ] **Step 3: Commit**

```bash
git add UI/Features.lua
git commit -m "fix: per-feature window minimums matched to the responsive layouts"
```

---

## Self-review notes

- Spec section 3.1-3.4 -> Task 1. Section 3.5 (clipping) -> Task 2 Step 4. Section 3.6 (minimums) -> Task 4 Step 7 and Task 9 Step 1.
- Spec section 4 (hub) -> Task 3, all four right-column blocks plus the collapsed summary and the refresh cadence.
- Spec section 5.1 (title-bar buttons) -> Task 2. Section 5.2 table -> Tasks 4 through 8, one row each. Section 5.3 -> Task 4 Step 1 and the Task 1 test.
- Spec section 6 (tests) -> Task 1 Step 1 and Task 2 Step 1.
- Task 3 Step 4 and Step 5 deliberately require verifying that six module accessors exist before calling them, because writing a guarded call to a function that never existed produces a block that silently never renders.
