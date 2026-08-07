# Modular UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "the addon is one 1236x808 window" with a ~230px hub card that opens one small, draggable, position-remembering window per feature — without rewriting a single panel builder.

**Architecture:** A feature registry (`UI/FeatureRegistry.lua`) becomes the single source of truth for every feature's identity: label, icon, window size, builder, rank gate, on/off toggle. A generic container (`UI/Window.lua`) turns any registry entry into a floating window, building its content lazily on first show. The container duck-types the main frame's navigation interface (`SetActiveTab`, `tabPanels[key].SelectSub`), so existing panel builders run unchanged in either container. The hub (`UI/Hub.lua`) and the current full window both render from the same registry.

**Tech Stack:** Lua 5.1, WoW TBC Classic API (Interface 20506), no new libraries. Existing helpers: `BRutus.UI` (`UI/Helpers.lua`), `BRutus.SelfTest` (`Modules/SelfTest.lua`), `BRutus.L` (key-is-English fallback).

**Spec:** `docs/superpowers/specs/2026-08-07-modular-ui-design.md`

## Global Constraints

- **No new dependencies.** Everything uses the existing `Libs/` set and the WoW API.
- **Two verification gates, both real:** `luacheck . --config .luacheckrc` (the CI gate, runs locally — `/usr/bin/luacheck` is installed) and `/gos selftest` in-client (`Modules/SelfTest.lua`). There is no headless frame test runner; frame behaviour is verified by the scripted in-game checks written into each task.
- **The luacheck bar is "0 errors, no new warnings".** The repo's baseline as of `066cd6e` is **71 warnings / 0 errors in 95 files**, all pre-existing in files this plan does not touch (`Modules/*`, `tools/*`, three `UI/*Panel.lua`, `UI/RosterFrame.lua`). A task passes when errors stay at 0 and the warning count does not rise. Files this plan creates must be individually clean.
- **In-game steps cannot be run by an implementer** — there is no WoW client in this environment. Write the self-tests, run luacheck, and report the `/gos selftest` and click-through steps as PENDING HUMAN. Never claim an in-game step passed.
- **Every new global must be declared in `.luacheckrc`,** or CI fails. New globals in this plan: none — everything hangs off `BRutus` / `BRutus.UI`.
- **New user-facing strings** go through `L["English text"]`. `BRutus.L` falls back to the key, so the string works immediately; add it to `Locales/enUS.lua` in the same commit (master list), other locales optional.
- **`GuildOS.VERSION` and `## Version:` in the TOC are managed by CI.** Never edit them by hand.
- **No AI attribution in commits.** No `Co-Authored-By:` trailer, no "Generated with" line.
- **Feature ids are one key space.** Registry ids and `db.settings.modules` keys are the same strings. Existing keys that must keep working: `raidTracker`, `lootTracker`, `lootMaster`, `consumableChecker`, `recruitment`, `trialTracker`, `officerNotes`, `commSystem`, `raidHUD`.
- **Load order** in `GuildOS.toc`: `UI\Helpers.lua` defines `BRutus.UI`, so every new UI file loads after it. `Core/Core.lua` loads *before* all UI files — code in Core that touches `BRutus.UI` must resolve it at call time, never at load time.
- **Default is ON.** An absent `db.settings.modules[id]` means "never touched", not "off" (`~= false`, matching `Core/Core.lua:238-239`).

## File Structure

| File | Responsibility |
| --- | --- |
| Create `UI/FeatureRegistry.lua` | Registry API + registry invariant self-tests. Knows nothing about frames. |
| Create `UI/Window.lua` | One generic floating container: chrome, drag, resize, geometry persistence, lazy build, navigation shim. |
| Create `UI/Features.lua` | The registry *entries* (data only): 13 features + the background-only module toggles. |
| Create `UI/Hub.lua` | The hub card: pulse band, feature rows, more page, footer. |
| Modify `Core/Core.lua` | Public `IsFeatureEnabled` / `SetFeatureEnabled`; `ToggleRoster` opens the hub. |
| Modify `Core/Commands.lua` | `/gos <feature-id>` opens a window; `/gos` opens the hub. |
| Modify `UI/RosterFrame.lua` | Tab bar generated from the registry; panels built lazily; expose `SelectSub` on the raid hub. |
| Modify `UI/FeaturePanels.lua` | Settings module list generated from the registry; UI scale slider. |
| Modify `UI/Minimap.lua` | Context menu generated from the registry. |
| Modify `UI/Onboarding.lua` | Opens the Settings window directly instead of the full frame. |
| Modify `Modules/TrialTracker.lua` | Refreshes the roster through the host resolver. |
| Modify `GuildOS.toc` | Load the four new UI files. |
| Modify `Locales/enUS.lua` | New master-list strings. |

---

### Task 1: Feature registry and public feature toggles

**Files:**
- Create: `UI/FeatureRegistry.lua`
- Modify: `Core/Core.lua` (add public API near `GetSetting` at line 704; delegate the local `modEnabled` at lines 236-240)
- Modify: `GuildOS.toc` (add `UI\FeatureRegistry.lua` immediately after `UI\Helpers.lua`)

**Interfaces:**
- Consumes: `BRutus.UI` (`UI/Helpers.lua:9`), `BRutus.SelfTest:Register(name, fn)` (`Modules/SelfTest.lua:13`), `BRutus:IsOfficer()`.
- Produces:
  - `UI:RegisterFeature(def) -> def|nil` — `def` fields: `id` (string, required), `label` (string, required), `icon` (string), `order` (number), `w`/`h`/`minW`/`minH` (numbers), `resizable` (bool, default true), `subs` (array of strings), `officerOnly` (bool), `condition` (function->bool), `core` (bool), `module` (string), `badge` (function->number), `hub` (bool, default true), `tab` (bool, default true), `build` (function(container, win)).
  - `UI:GetFeature(id) -> def|nil`
  - `UI:AllFeatures(scope) -> array<def>` — ordered, filtered by rank + `condition` + surface, but **not** by the on/off toggle.
  - `UI:VisibleFeatures(scope) -> array<def>` — `AllFeatures` plus the enabled filter; `scope` is `"hub"`, `"tab"` or `nil`.
  - `BRutus:IsFeatureEnabled(id) -> bool`
  - `BRutus:SetFeatureEnabled(id, enabled)`
  - `UI:OnFeatureToggled(id, enabled)` — defined as a no-op here, overridden in Task 2.

- [ ] **Step 1: Write the failing self-tests**

Create `UI/FeatureRegistry.lua` with only the test registration and an empty registry, so the tests exist before the API does:

```lua
----------------------------------------------------------------------
-- Guild OS - Feature registry
-- One entry per feature: what it is called, where it shows up, how big
-- its window is and how to build it. Single source of truth for the hub,
-- the expanded-mode tab bar, the minimap menu, the slash commands and the
-- Settings toggles. Frame-free on purpose: this file only holds data and
-- predicates, so it is testable without a live UI.
----------------------------------------------------------------------
local UI = BRutus.UI

UI.features     = {}   -- id -> def
UI.featureOrder = {}   -- ids, kept sorted by def.order

function UI:_RegisterFeatureTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("features.invariants", function()
        for _, id in ipairs(UI.featureOrder) do
            local d = UI.features[id]
            if type(d.label) ~= "string" or d.label == "" then
                return false, id .. ": missing label"
            end
            if d.hub then
                if type(d.build) ~= "function" then return false, id .. ": hub feature needs build()" end
                if type(d.w) ~= "number" or d.w <= 0 then return false, id .. ": bad width" end
                if type(d.h) ~= "number" or d.h <= 0 then return false, id .. ": bad height" end
            end
            if d.subs ~= nil then
                if type(d.subs) ~= "table" then return false, id .. ": subs must be a list" end
                for _, s in ipairs(d.subs) do
                    if type(s) ~= "string" or s == "" then return false, id .. ": bad sub key" end
                end
            end
        end
        return true
    end)

    S:Register("features.unique_ids", function()
        local seen, n = {}, 0
        for _, id in ipairs(UI.featureOrder) do
            if seen[id] then return false, "duplicate id in order list: " .. id end
            seen[id] = true
            n = n + 1
        end
        local m = 0
        for _ in pairs(UI.features) do m = m + 1 end
        if n ~= m then return false, string.format("order has %d ids, table has %d", n, m) end
        return true
    end)

    S:Register("features.core_cannot_be_disabled", function()
        local mods = BRutus.db and BRutus.db.settings and BRutus.db.settings.modules
        if not mods then return false, "db.settings.modules missing" end
        for _, id in ipairs(UI.featureOrder) do
            if UI.features[id].core then
                local prev = mods[id]
                mods[id] = false
                local ok = BRutus:IsFeatureEnabled(id)
                mods[id] = prev
                if not ok then return false, id .. " is core but reported disabled" end
            end
        end
        return true
    end)

    S:Register("features.toggle_roundtrip", function()
        local id = "__selftest_feature"
        UI:RegisterFeature({ id = id, label = "Self test", hub = false, tab = false })
        BRutus:SetFeatureEnabled(id, false)
        if BRutus:IsFeatureEnabled(id) then return false, "disable did not stick" end
        BRutus:SetFeatureEnabled(id, true)
        if not BRutus:IsFeatureEnabled(id) then return false, "re-enable did not stick" end
        -- clean up so repeated runs stay idempotent
        UI.features[id] = nil
        for i, v in ipairs(UI.featureOrder) do
            if v == id then table.remove(UI.featureOrder, i) break end
        end
        if BRutus.db.settings.modules then BRutus.db.settings.modules[id] = nil end
        return true
    end)
end
```

- [ ] **Step 2: Register the file and run the lint gate**

Add to `GuildOS.toc`, directly after `UI\Helpers.lua`:

```
UI\FeatureRegistry.lua
```

Run: `luacheck . --config .luacheckrc`
Expected: PASS (0 warnings). The self-tests are registered but reference `UI:RegisterFeature`, `BRutus:SetFeatureEnabled` and `BRutus:IsFeatureEnabled`, which do not exist yet — that is a runtime failure, not a lint failure.

Then in-game: `/reload` then `/gos selftest`
Expected: FAIL — `features.toggle_roundtrip` errors with "attempt to call method 'RegisterFeature' (a nil value)"; `features.core_cannot_be_disabled` errors on `IsFeatureEnabled`.

- [ ] **Step 3: Implement the registry API**

Insert into `UI/FeatureRegistry.lua`, above `UI:_RegisterFeatureTests`:

```lua
----------------------------------------------------------------------
-- Register a feature. Later duplicates are ignored with a printed
-- warning rather than an error: a bad entry must never take the whole
-- addon down at load time.
----------------------------------------------------------------------
function UI:RegisterFeature(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        BRutus:Print("|cffFF4444Feature registry: entry without an id ignored.|r")
        return nil
    end
    if self.features[def.id] then
        BRutus:Print("|cffFF4444Feature registry: duplicate id '" .. def.id .. "' ignored.|r")
        return nil
    end
    if def.hub == nil then def.hub = true end
    if def.tab == nil then def.tab = true end
    def.order = def.order or (#self.featureOrder + 1) * 10

    self.features[def.id] = def
    self.featureOrder[#self.featureOrder + 1] = def.id
    table.sort(self.featureOrder, function(a, b)
        return self.features[a].order < self.features[b].order
    end)
    return def
end

function UI:GetFeature(id)
    if type(id) ~= "string" then return nil end
    return self.features[id]
end

----------------------------------------------------------------------
-- Ordered defs for a surface, filtered by rank and condition but NOT by
-- the on/off toggle. `scope` narrows to a surface:
--   "hub" -> rows in the hub / floating windows
--   "tab" -> tabs in expanded mode
--   nil   -> every feature, background modules included
--
-- The Settings toggle list and the expanded-mode tab construction both
-- need this rather than VisibleFeatures: a disabled feature must keep
-- its checkbox (or there is no way to switch it back on) and must keep
-- its tab frame (or re-enabling could never show it again).
----------------------------------------------------------------------
function UI:AllFeatures(scope)
    local out = {}
    for _, id in ipairs(self.featureOrder) do
        local def = self.features[id]
        local ok = true
        if def.officerOnly and not BRutus:IsOfficer() then ok = false end
        if ok and def.condition and not def.condition() then ok = false end
        if ok and scope and not def[scope] then ok = false end
        if ok then out[#out + 1] = def end
    end
    return out
end

-- What the user may see AND has switched on: hub rows, minimap menu.
function UI:VisibleFeatures(scope)
    local out = {}
    for _, def in ipairs(self:AllFeatures(scope)) do
        if BRutus:IsFeatureEnabled(def.id) then out[#out + 1] = def end
    end
    return out
end

-- Overridden in UI/Window.lua once windows exist; a no-op until then so
-- SetFeatureEnabled can call it unconditionally.
function UI:OnFeatureToggled(_, _) end
```

At the very end of the file, call the test registration:

```lua
UI:_RegisterFeatureTests()
```

- [ ] **Step 4: Implement the public toggle API in Core**

Insert into `Core/Core.lua` immediately after `BRutus:SetSetting` (which ends at line 712):

```lua
----------------------------------------------------------------------
-- Feature toggles (Rule 8 — never read db.settings.modules directly).
-- Keys are the feature ids from UI/FeatureRegistry.lua. Default is ON:
-- an absent key means "never touched", not "off". `core` features can
-- never be turned off — that is how a user would lock themselves out of
-- the Settings window that would turn them back on.
----------------------------------------------------------------------
function BRutus:IsFeatureEnabled(id)
    if type(id) ~= "string" then return false end
    -- UI loads after Core, so the registry is resolved per call, not per load.
    local def = self.UI and self.UI.GetFeature and self.UI:GetFeature(id)
    if def and def.core then return true end
    local mods = self.db and self.db.settings and self.db.settings.modules
    if not mods then return true end
    return mods[id] ~= false
end

function BRutus:SetFeatureEnabled(id, enabled)
    if type(id) ~= "string" then return end
    local def = self.UI and self.UI.GetFeature and self.UI:GetFeature(id)
    if def and def.core then return end
    if not (self.db and self.db.settings) then return end
    self.db.settings.modules = self.db.settings.modules or {}
    -- GetChecked() returns true or nil (never false) in TBC, so store an
    -- explicit boolean — IsFeatureEnabled compares against false.
    enabled = enabled and true or false
    self.db.settings.modules[id] = enabled
    if self.UI and self.UI.OnFeatureToggled then self.UI:OnFeatureToggled(id, enabled) end
end
```

Then replace the local helper at `Core/Core.lua:236-240` so there is one implementation:

```lua
function BRutus:InitModules()
    -- Module enabled helper (delegates to the public API; call sites below
    -- keep the short local name).
    local function modEnabled(key)
        return self:IsFeatureEnabled(key)
    end
```

- [ ] **Step 5: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71).

In-game: `/reload` then `/gos selftest`
Expected: all four `features.*` cases pass; the total count grows by 4 and `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add UI/FeatureRegistry.lua Core/Core.lua GuildOS.toc
git commit -m "feat: feature registry and public feature-toggle API"
```

---

### Task 2: Generic floating window container

**Files:**
- Create: `UI/Window.lua`
- Modify: `GuildOS.toc` (add `UI\Window.lua` after `UI\FeatureRegistry.lua`)
- Modify: `Locales/enUS.lua` (one new string)

**Interfaces:**
- Consumes: `UI:GetFeature(id)`, `BRutus:IsFeatureEnabled(id)` (Task 1); `UI:CreatePanel(parent, name)` (`UI/Helpers.lua:42`), `UI:StylePopup(frame)` (`UI/Helpers.lua:144`), `UI:CreateHeaderText`, `UI:CreateCloseButton` (`UI/Helpers.lua:406`), `BRutus:GetSetting/SetSetting`.
- Produces:
  - `UI:CreateWindow(id) -> Frame|nil` — chrome only; content is built on first open.
  - `UI:OpenWindow(id, subKey)` — lazy-builds, shows, raises, optionally deep-links a sub-tab.
  - `UI:ToggleWindow(id)`
  - `UI:IsWindowOpen(id) -> bool`
  - `UI:GetWindow(id) -> Frame|nil` — the created window, or nil if it was never opened.
  - `UI:CloseAllWindows()`
  - `UI:ApplyScale()` — pushes `db.settings.uiScale` onto every live window.
  - `UI:OnFeatureToggled(id, enabled)` — real implementation, replaces Task 1's no-op.
  - Every window exposes `win.content` (the frame handed to `build`), `win:SetActiveTab(key)` and `win.tabPanels[key].SelectSub(sub)`.
  - Geometry shape: `db.settings.windows[id] = { point, relPoint, x, y, w, h }`.

- [ ] **Step 1: Write the failing geometry self-test**

Add to `UI/FeatureRegistry.lua` inside `UI:_RegisterFeatureTests()`, after the existing cases:

```lua
    S:Register("window.geometry_roundtrip", function()
        if not UI.SaveWindowGeometry then return false, "SaveWindowGeometry missing" end
        local probe = CreateFrame("Frame", nil, UIParent)
        probe.featureId = "__selftest_geom"
        probe:SetSize(321, 234)
        probe:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -60)
        UI:SaveWindowGeometry(probe)

        local restored = CreateFrame("Frame", nil, UIParent)
        restored.featureId = "__selftest_geom"
        UI:RestoreWindowGeometry(restored, { w = 10, h = 10 })
        local point, _, relPoint, x, y = restored:GetPoint()

        BRutus.db.settings.windows["__selftest_geom"] = nil
        if point ~= "TOPLEFT" or relPoint ~= "TOPLEFT" then
            return false, "point lost: " .. tostring(point) .. "/" .. tostring(relPoint)
        end
        if math.abs(x - 40) > 1 or math.abs(y + 60) > 1 then
            return false, string.format("offset lost: %.1f,%.1f", x, y)
        end
        if math.abs(restored:GetWidth() - 321) > 1 or math.abs(restored:GetHeight() - 234) > 1 then
            return false, "size lost"
        end
        return true
    end)
```

- [ ] **Step 2: Run the gates to see it fail**

Run: `luacheck . --config .luacheckrc`
Expected: PASS.

In-game: `/reload` then `/gos selftest`
Expected: FAIL — `window.geometry_roundtrip — SaveWindowGeometry missing`.

- [ ] **Step 3: Implement the container**

Create `UI/Window.lua`:

```lua
----------------------------------------------------------------------
-- Guild OS - Generic floating feature window
-- One draggable, resizable, position-remembering container. Content is
-- built lazily on first show by the feature's build(container, win), so
-- opening the addon constructs one window instead of thirteen panels.
--
-- A window duck-types the main frame's navigation interface
-- (SetActiveTab / tabPanels[key].SelectSub), which is why every existing
-- panel builder runs unchanged in either container.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local TITLE_H  = 26
local GRIP     = 14
local windows  = {}    -- id -> frame (created; shown or hidden)

----------------------------------------------------------------------
-- Geometry persistence (db.settings.windows[id])
----------------------------------------------------------------------
local function store()
    local w = BRutus:GetSetting("windows")
    if type(w) ~= "table" then
        w = {}
        BRutus:SetSetting("windows", w)
    end
    return w
end

function UI:SaveWindowGeometry(win)
    if not win.featureId then return end
    local point, _, relPoint, x, y = win:GetPoint()
    if not point then return end
    store()[win.featureId] = {
        point    = point,
        relPoint = relPoint or point,
        x        = math.floor((x or 0) + 0.5),
        y        = math.floor((y or 0) + 0.5),
        w        = math.floor(win:GetWidth() + 0.5),
        h        = math.floor(win:GetHeight() + 0.5),
    }
end

function UI:RestoreWindowGeometry(win, def)
    local g = win.featureId and store()[win.featureId]
    win:ClearAllPoints()
    if g and g.point then
        win:SetPoint(g.point, UIParent, g.relPoint or g.point, g.x or 0, g.y or 0)
        win:SetSize(g.w or def.w, g.h or def.h)
    else
        win:SetPoint("CENTER")
        win:SetSize(def.w, def.h)
    end
end

----------------------------------------------------------------------
-- UI scale: one global knob, applied to every live window and the hub.
----------------------------------------------------------------------
function UI:ApplyScale()
    local s = BRutus:GetSetting("uiScale") or 1
    for _, win in pairs(windows) do win:SetScale(s) end
    if self.Hub and self.Hub.frame then self.Hub.frame:SetScale(s) end
end

----------------------------------------------------------------------
-- Build the chrome. Content is NOT built here — see UI:OpenWindow.
----------------------------------------------------------------------
function UI:CreateWindow(id)
    local def = self:GetFeature(id)
    if not def or not def.hub then return nil end

    local name = "GuildOSWindow" .. id:gsub("^%l", string.upper)
    local win  = self:CreatePanel(UIParent, name)
    win.featureId = id
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:Hide()
    self:StylePopup(win)
    self:RestoreWindowGeometry(win, def)
    win:SetScale(BRutus:GetSetting("uiScale") or 1)

    -- Title bar doubles as the drag handle.
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        UI:SaveWindowGeometry(win)
    end)

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = self:CreateHeaderText(bar, def.label, 11)
    title:SetPoint("LEFT", 10, 0)

    local line = self:CreateAccentLine(win, 1)
    line:SetPoint("TOPLEFT", 0, -TITLE_H)
    line:SetPoint("TOPRIGHT", 0, -TITLE_H)

    local close = self:CreateCloseButton(win)
    close:SetPoint("TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() UI:ToggleWindow(id) end)

    -- Resize grip (bottom-right), unless the feature opted out.
    if def.resizable ~= false then
        win:SetResizable(true)
        local minW, minH = def.minW or 380, def.minH or 260
        if win.SetResizeBounds then
            win:SetResizeBounds(minW, minH)
        elseif win.SetMinResize then
            win:SetMinResize(minW, minH)
        end

        local grip = CreateFrame("Button", nil, win)
        grip:SetSize(GRIP, GRIP)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            win:StopMovingOrSizing()
            UI:SaveWindowGeometry(win)
        end)
    end

    -- Content area: everything under the title bar.
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + 1))
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    win.content = content

    -- Navigation shim. Panels cross-navigate through the main frame's
    -- interface; in window mode "go to tab X" means "open window X".
    function win:SetActiveTab(key)
        UI:OpenWindow(key)
    end
    win.tabPanels = setmetatable({}, {
        __index = function(_, key)
            return { SelectSub = function(sub) UI:OpenWindow(key, sub) end }
        end,
    })

    table.insert(UISpecialFrames, name)   -- ESC closes the top window
    windows[id] = win
    return win
end

----------------------------------------------------------------------
-- Open (creating and building on demand). subKey deep-links a sub-tab.
----------------------------------------------------------------------
function UI:OpenWindow(id, subKey)
    local def = self:GetFeature(id)
    if not def or not def.hub then return end
    if not BRutus:IsFeatureEnabled(id) then
        BRutus:Print(string.format(L["%s is disabled in Settings."], def.label))
        return
    end

    local win = windows[id] or self:CreateWindow(id)
    if not win then return end
    if not win.built then
        win.built = true
        def.build(win.content, win)
    end
    win:Show()
    win:Raise()
    if subKey and win.content.SelectSub then win.content.SelectSub(subKey) end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
end

function UI:ToggleWindow(id)
    local win = windows[id]
    if win and win:IsShown() then
        win:Hide()
        if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
        return
    end
    self:OpenWindow(id)
end

function UI:IsWindowOpen(id)
    local win = windows[id]
    return win ~= nil and win:IsShown()
end

-- The created window for a feature, or nil if it was never opened. Used by
-- refreshers that must find whichever container currently hosts a panel.
function UI:GetWindow(id)
    return windows[id]
end

function UI:CloseAllWindows()
    for _, win in pairs(windows) do win:Hide() end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
end

----------------------------------------------------------------------
-- A feature turned off in Settings disappears everywhere, live: its
-- window closes, the hub row goes, the expanded-mode tab goes.
----------------------------------------------------------------------
function UI:OnFeatureToggled(id, enabled)
    if not enabled and windows[id] then windows[id]:Hide() end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
    local rf = BRutus.RosterFrame
    if rf and rf.UpdateTabVisibility then rf:UpdateTabVisibility() end
end
```

- [ ] **Step 4: Add the new strings and register the file**

Append to `Locales/enUS.lua` under a new `-- UI/Window.lua` comment block:

```lua
-- UI/Window.lua
L["%s is disabled in Settings."] = "%s is disabled in Settings."
```

Add to `GuildOS.toc`, directly after `UI\FeatureRegistry.lua`:

```
UI\Window.lua
```

- [ ] **Step 5: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71).

In-game: `/reload` then `/gos selftest`
Expected: `window.geometry_roundtrip` passes, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add UI/Window.lua UI/FeatureRegistry.lua GuildOS.toc Locales/enUS.lua
git commit -m "feat: generic floating window container with saved geometry"
```

---

### Task 3: Extract the roster panel into a builder

**Files:**
- Modify: `UI/RosterFrame.lua` (the inline roster panel, lines 520-1012)
- Modify: `Core/Core.lua` (add `BRutus:RefreshRosterUI()`; update the refresher at line 445)
- Modify: `Modules/TrialTracker.lua` (lines 305-306)

**Interfaces:**
- Consumes: nothing new.
- Produces: `BRutus:CreateRosterPanel(parent, host)` — same shape as every other builder; `BRutus:RefreshRosterUI()`.

**Why this task exists:** every other tab already has a builder (`CreateRecipesPanel`, `CreateGuildHub`, `CreateDKPPanel`, ...). The roster is the one panel still written inline inside `CreateRosterFrame`, so there is nothing a window could call. This task changes no behaviour — it is the riskiest edit in the plan and it gets its own verification against today's UI, before the registry is involved at all.

**The range is two blocks, not one.** The roster's *widgets* are inline at lines 520-1012, but its five *methods* — `RefreshRoster`, `BuildMemberList`, `UpdateSortIndicators`, `UpdateRows`, `UpdateStats` — live further down in the `Data & Methods` block (~1253-1500) and must move too. The widget code calls `host:RefreshRoster()` and `host:UpdateRows()`; leaving the methods on the main frame works only while `host == frame` and throws the moment a window hosts the panel. Both blocks land in the same builder.

Those five methods touch exactly two things that belong to the main window rather than the roster: `self.UpdateGuildIcon` (already nil-guarded at the call site) and `self.subtitle:SetText(...)` in `UpdateStats`, which is **not** guarded. Wrap that one in `if self.subtitle then` — a floating window has no subtitle. Everything else they reference is roster state moving with them.

**The catch:** the inline block assigns 24 fields and methods to `frame` — `kpiOnline`, `kpiPlayers`, `kpiIlvl`, `kpiAtt`, `kpiAddon`, `kpiMembers`, `kpiPlayersSub`, `rail`, `rankBtns`, `classChips`, `classFilter`, `searchBox`, `searchFilter`, `segBtns`, `segment`, `offlineBtn`, `headerButtons`, `resultText`, `rows`, `scrollFrame`, and the methods `RefreshRoster`, `UpdateRows`, `UpdateRail`, `UpdateRailActive`, `SetSegment`, `SetClassFilter`, `GetSegmentLabel`. Those stay exactly where they are — they just land on the *host* rather than on the main frame specifically. External callers then have to ask which host is showing.

- [ ] **Step 1: Move the block into a builder**

Cut `UI/RosterFrame.lua` lines 520-1012 (from `local rosterPanel = CreateFrame(...)` through the end of the roster block, stopping before the `RECIPES PANEL` comment) into a new function at file scope, above `BRutus.CreateRosterFrame`:

```lua
----------------------------------------------------------------------
-- Roster panel: KPI band + left rail + member table.
-- `parent` is the container to fill; `host` is the frame that owns the
-- roster's state and methods (the main window in expanded mode, the
-- floating window otherwise). Both containers expose the same
-- navigation interface, so nothing in here needs to know which it got.
----------------------------------------------------------------------
function BRutus:CreateRosterPanel(parent, host)
    host = host or parent
```

Mechanical rules for the moved body:

- `local rosterPanel = CreateFrame("Frame", nil, frame)` and its two `SetPoint` calls go away — the container is already sized and anchored by its owner. Every later `rosterPanel` reference becomes `parent`.
- Every `frame.` becomes `host.`; every `frame:` becomes `host:`.
- Any `CreateFrame(..., frame)` inside the block becomes `CreateFrame(..., parent)` — children belong to the container, not the host.
- Leave `frame.tabPanels[...]` reads as `host.tabPanels[...]`: the window's shim (Task 2) answers them.
- End the function with `return parent`.

At the old location in `CreateRosterFrame`, leave the panel creation only:

```lua
    local rosterPanel = CreateFrame("Frame", nil, frame)
    rosterPanel:SetPoint("TOPLEFT", 0, contentTop)
    rosterPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    rosterPanel:Hide()
    frame.tabPanels["roster"] = rosterPanel
    BRutus:CreateRosterPanel(rosterPanel, frame)
```

- [ ] **Step 2: Add a host resolver for external refreshers**

Add to `Core/Core.lua`, right after `BRutus:ToggleRoster`:

```lua
----------------------------------------------------------------------
-- Refresh whichever container is currently showing the roster panel:
-- the expanded window, the floating window, or neither.
----------------------------------------------------------------------
function BRutus:RefreshRosterUI()
    local hosts = { self.RosterFrame }
    if self.UI and self.UI.GetWindow then hosts[#hosts + 1] = self.UI:GetWindow("roster") end
    for _, host in ipairs(hosts) do
        if host and host:IsShown() and host.RefreshRoster then host:RefreshRoster() end
    end
end
```

- [ ] **Step 3: Point the two refresh call sites at it**

`Core/Core.lua:445` and `Modules/TrialTracker.lua:305-306` both do the same `if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then ... RefreshRoster()` dance. Replace each with:

```lua
    BRutus:RefreshRosterUI()
```

Read each call site first — `Core/Core.lua:445` may refresh more than the roster, in which case keep the rest of its body and swap only the roster part.

- [ ] **Step 4: Run the lint gate**

Run: `luacheck . --config .luacheckrc`
Expected: PASS, 0 warnings. A leftover `frame` reference inside the moved block shows up here as an undefined-variable warning — that is the main thing this step catches.

- [ ] **Step 5: Verify nothing changed**

In-game: `/reload`, `/gos` (still the old full window at this point), Roster tab. Check every roster control still works:
1. KPI cards show real numbers.
2. Left rail: All / Online / Offline segments filter, rank buttons filter, class chips filter.
3. Search box filters as you type.
4. Column headers sort, both directions.
5. Scrolling works and rows show the right members.
6. Clicking a row opens member detail.
7. Log in a trial member change (or use `/gos selftest`, then any action that calls `RefreshRosterUI`) and confirm the table refreshes rather than erroring.

- [ ] **Step 6: Commit**

```bash
git add UI/RosterFrame.lua Core/Core.lua Modules/TrialTracker.lua
git commit -m "refactor: extract the roster panel into CreateRosterPanel"
```

---

### Task 4: Register every feature

**Files:**
- Create: `UI/Features.lua`
- Modify: `UI/RosterFrame.lua` (expose `container.SelectSub` on the raid hub, after line 215)
- Modify: `Core/Commands.lua` (add `/gos <feature-id>` dispatch)
- Modify: `GuildOS.toc` (add `UI\Features.lua` as the last UI entry, after `UI\RaidHUD.lua`)

**Interfaces:**
- Consumes: `UI:RegisterFeature(def)` (Task 1), `UI:OpenWindow(id, subKey)` (Task 2), every existing `BRutus:CreateXPanel(container, mainFrame)` builder.
- Produces: a populated registry. Ids: `home`, `roster`, `guild`, `recipes`, `wishlist`, `raids`, `loot`, `dkp`, `trials`, `recruitment`, `alliance`, `management`, `settings`, plus background-only toggles `raidTracker`, `lootTracker`, `lootMaster`, `consumableChecker`, `raidHUD`, `officerNotes`, `commSystem`.

**Why this file loads last:** `build` closures resolve their builder at call time, so load order does not affect correctness — but registering after every panel file keeps the dependency direction obvious.

- [ ] **Step 1: Make the roster's global frame names instance-unique**

This task is what first makes `CreateRosterPanel` callable twice — once for the expanded-mode tab, once for the floating window. Four frames inside it are created with hardcoded global names, and a second instance would steal them: `BRutusSearchBox` (`UI/RosterFrame.lua:345`), `BRutusRosterContainer` (:454), `BRutusRosterScroll` (:458), and `"BRutusRow" .. rowIndex` in `CreateRosterRow` (:1528). The live consumers are `UI:SkinScrollBar(scrollFrame, "BRutusRosterScroll")` (:461) and `FauxScrollFrameTemplate`'s `$parent`-derived scrollbar — both resolve by name, so the second instance silently re-skins or mis-targets the first.

Give each instance a suffix, keeping the first instance's names exactly as they are today so expanded mode is untouched:

```lua
-- Global frame names must stay unique: this builder now runs once per
-- container (expanded-mode tab and floating window). The first instance
-- keeps the historical names so nothing that hardcodes them breaks.
local rosterInstances = 0
```

at file scope near the other file-locals, then at the top of `BRutus:CreateRosterPanel`:

```lua
    rosterInstances = rosterInstances + 1
    local uid = rosterInstances > 1 and tostring(rosterInstances) or ""
```

Apply `uid` to all four names — `"BRutusSearchBox" .. uid`, `"BRutusRosterContainer" .. uid`, `"BRutusRosterScroll" .. uid`, and the `SkinScrollBar` argument — and pass it into `CreateRosterRow` so its rows become `"BRutusRow" .. uid .. rowIndex`. `CreateRosterRow` is a declared global (`.luacheckrc`); adding a third parameter is fine, but check for other callers first with `grep -rn "CreateRosterRow" --include=*.lua .` and update any you find.

- [ ] **Step 2: Expose sub-tab selection on the raid hub**

`UI/RosterFrame.lua` — `CreateRaidHubPanel` builds its sub-tabs but never exposes a selector, unlike `UI/CommunityPanel.lua:256` and `UI/AlliancePanel.lua:1466`. Add one line after `SetSubTab("sessions")` (line 215):

```lua
    -- Exposed so the hub and /gos can deep-link a sub-tab (same contract as
    -- CommunityPanel / AlliancePanel).
    container.SelectSub = SetSubTab
```

- [ ] **Step 3: Write the registry entries**

Create `UI/Features.lua`:

```lua
----------------------------------------------------------------------
-- Guild OS - Feature entries
-- The list every surface renders from: the hub rows, the expanded-mode
-- tab bar, the minimap menu, the slash commands and the Settings
-- toggles. Adding a feature means adding one entry here.
--
--   hub = false  -> no floating window and no hub row
--   tab = false  -> no tab in expanded mode
--   both false   -> a background module with a Settings toggle only
----------------------------------------------------------------------
local UI = BRutus.UI
local L  = BRutus.L

local ICON = "Interface\\Icons\\"

-- Windowed features, in hub order -----------------------------------
UI:RegisterFeature({
    id = "home", label = L["Home"], order = 5,
    hub = false, tab = true, core = true,
    build = function(c, win) BRutus:CreateDashboardPanel(c, win) end,
})

UI:RegisterFeature({
    id = "roster", label = L["Roster"], order = 10, core = true,
    icon = ICON .. "INV_Misc_GroupLooking",
    w = 1000, h = 620, minW = 700, minH = 420,
    build = function(c, win) BRutus:CreateRosterPanel(c, win) end,
})

UI:RegisterFeature({
    id = "raids", label = L["Raids"], order = 20,
    icon = ICON .. "INV_Sword_04",
    w = 780, h = 540, minW = 620, minH = 400,
    subs = { "sessions", "raiders", "cores", "audit", "raidtools" },
    build = function(c, win) BRutus:CreateRaidHubPanel(c, win) end,
})

UI:RegisterFeature({
    id = "loot", label = L["Loot"], order = 30, officerOnly = true,
    icon = ICON .. "INV_Misc_Coin_01",
    w = 680, h = 470,
    build = function(c, win) BRutus:CreateLootPanel(c, win) end,
})

UI:RegisterFeature({
    id = "dkp", label = L["DKP"], order = 35,
    icon = ICON .. "INV_Misc_Coin_02",
    w = 620, h = 440,
    condition = function() return BRutus:LootSystemShowsDKP() end,
    build = function(c, win) BRutus:CreateDKPPanel(c, win) end,
})

UI:RegisterFeature({
    id = "wishlist", label = L["Wishlist"], order = 38,
    icon = ICON .. "INV_Scroll_03",
    w = 680, h = 470,
    condition = function() return BRutus:IsOfficer() and BRutus:LootSystemShowsWishlist() end,
    build = function(c, win) BRutus:CreateWishlistGuildPanel(c, win) end,
})

UI:RegisterFeature({
    id = "recipes", label = L["Recipes"], order = 40,
    icon = ICON .. "INV_Misc_Book_09",
    w = 700, h = 500,
    build = function(c, win) BRutus:CreateRecipesPanel(c, win) end,
})

UI:RegisterFeature({
    id = "guild", label = L["Guild"], order = 50,
    icon = ICON .. "INV_Shirt_GuildTabard_01",
    w = 720, h = 520,
    subs = { "calendar", "activity" },
    build = function(c, win) BRutus:CreateGuildHub(c, win) end,
})

UI:RegisterFeature({
    id = "alliance", label = L["Alliance"], order = 60,
    icon = ICON .. "INV_BannerPVP_02",
    w = 900, h = 600, minW = 700, minH = 460,
    condition = function()
        return (BRutus.Alliance and BRutus.Alliance:Get() ~= nil) or BRutus:IsOfficer()
    end,
    build = function(c, win) BRutus:CreateAlliancePanel(c, win) end,
})

UI:RegisterFeature({
    id = "recruitment", label = L["Recruitment"], order = 70,
    icon = ICON .. "INV_Misc_GroupNeedMore",
    w = 720, h = 500,
    build = function(c, win) BRutus:CreateRecruitmentPanel(c, win) end,
})

UI:RegisterFeature({
    id = "trials", label = L["Trials"], order = 80, officerOnly = true,
    icon = ICON .. "INV_Misc_Note_01",
    w = 620, h = 420,
    build = function(c, win) BRutus:CreateTrialsPanel(c, win) end,
})

UI:RegisterFeature({
    id = "management", label = L["Leadership"], order = 90, officerOnly = true,
    icon = ICON .. "INV_Crown_01",
    w = 760, h = 540, minW = 620, minH = 420,
    build = function(c, win) BRutus:CreateManagementPanel(c, win) end,
})

UI:RegisterFeature({
    id = "settings", label = L["Settings"], order = 100, core = true,
    icon = ICON .. "INV_Misc_Gear_01",
    w = 560, h = 520, resizable = false,
    build = function(c, win) BRutus:CreateSettingsPanel(c, win) end,
})

-- Background modules: a Settings toggle and nothing else ------------
local function background(id, label, desc, officerOnly)
    UI:RegisterFeature({
        id = id, label = label, desc = desc,
        hub = false, tab = false, officerOnly = officerOnly,
        module = id,
    })
end

background("raidTracker",       L["Raid Tracker"],       L["Track raid attendance, penalties, and sessions"], true)
background("lootTracker",       L["Loot Tracker"],       L["Record loot drops from boss kills"])
background("lootMaster",        L["Loot Master"],        L["Master Loot with wishlist auto-council"])
background("consumableChecker", L["Consumable Checker"], L["Scan raid for missing flasks/food/elixirs"])
background("raidHUD",           L["Raid CD Tracker"],    L["Floating tracker for raid cooldowns and consumable check"])
background("trialTracker",      L["Trial Tracker"],      L["Track trial member progress (officer)"], true)
background("officerNotes",      L["Officer Notes"],      L["Private notes on guild members (officer)"], true)
background("commSystem",        L["Comm System"],        L["Sync member data between addon users"])
```

**These builder names were verified against the source, not guessed** — including the four that do not follow the `CreateXPanel` pattern: `CreateGuildHub` (`UI/CommunityPanel.lua:239`), `CreateDKPPanel` (`UI/CommunityPanel.lua:292`), `CreateWishlistGuildPanel` (`UI/RosterFrame.lua:2106`), `CreateRecruitmentPanel` (`UI/RosterFrame.lua:2627`). `CreateRosterPanel` exists only after Task 3. If a name still fails, re-derive the list with:

```bash
grep -rn "^function BRutus:Create" UI/*.lua
```

`recruitment` intentionally carries both a window and the existing background module key — one toggle, both effects.

**No feature registers a `badge` yet.** There is no ready counter for pending applications or unread alliance messages in the current modules, and inventing one is out of scope here. `Hub:Refresh` (Task 5) is nil-safe on `def.badge`, so badges light up the day a module exposes a count — one field, no other change.

- [ ] **Step 4: Wire the slash commands**

**A bare `/gos <id>` fallback does not work and must not be used.** Six feature ids collide with verbs the dispatcher already owns, and one collides destructively: `^trial` (`Core/Commands.lua:274`) prefix-matches `/gos trials` and would pass `"s"` as a player name. `^roster` (:325) belongs to the companion import, `dkp` (:110) and `alliance` (:128) to existing openers. A last-resort fallback can never reach any of them, so half the features would be reachable by bare id and half silently not — worse than a rule with no exceptions.

Use one explicit verb instead. In `Core/Commands.lua`, add this branch to the dispatch chain, positioned like the other verb branches:

```lua
    -- /gos open <feature> — one uniform way to open any feature window.
    -- Explicit rather than a bare-id fallback: several feature ids
    -- (roster, trials, dkp, alliance) are already verbs above, and
    -- "^trial" would even prefix-match "trials" and eat the "s".
    elseif msg == "open" or msg:match("^open%s") then
        local id  = msg:match("^open%s+(%S+)")
        local sub = msg:match("^open%s+%S+%s+(%S+)")
        local def = id and BRutus.UI and BRutus.UI.GetFeature and BRutus.UI:GetFeature(id)
        if def and def.hub then
            BRutus.UI:OpenWindow(id, sub)
        else
            BRutus:Print(L["Usage: /gos open <feature>. Try /gos open roster."])
        end
```

Match the surrounding branches' local-name style — read the function first; it pattern-matches on a single `msg` local rather than pre-splitting into `cmd` / `rest`.

Also fix the one command that opens a tab the long way (`Core/Commands.lua:515-521` — it creates the whole 1236px frame just to reach Leadership). Replace those lines with:

```lua
        BRutus.UI:OpenWindow("management")
```

Add to `printHelp` under the `General` header:

```lua
    helpLine("/gos open <feature>", L["Open a feature window (roster, raids, loot, guild...)"])
```

And to `Locales/enUS.lua` under the `-- Core/Commands.lua` block:

```lua
L["Open a feature window (roster, raids, loot, guild...)"] = "Open a feature window (roster, raids, loot, guild...)"
L["Usage: /gos open <feature>. Try /gos open roster."] = "Usage: /gos open <feature>. Try /gos open roster."
```

- [ ] **Step 5: Register the file**

Add to `GuildOS.toc` as the final UI line, after `UI\RaidHUD.lua`:

```
UI\Features.lua
```

- [ ] **Step 6: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71). New files must be individually clean.

In-game: `/reload` then `/gos selftest`
Expected: `features.invariants` and `features.unique_ids` pass with the real entries loaded — this is the step that catches a typo'd builder name or a missing size.

- [ ] **Step 7: Verify windows open**

In-game, one at a time: `/gos open roster`, `/gos open raids`, `/gos open loot`, `/gos open guild`, `/gos open settings`, `/gos open raids audit`.
Expected: each opens a small window with the correct title, the panel's real content, a working close button, drag by the title bar, resize by the corner grip (except Settings). `/gos open raids audit` opens Raids on its Audit sub-tab. `ESC` closes the top window.

Also confirm the existing verbs still do what they always did: `/gos roster` still runs the companion import, `/gos trial <name>` still adds a trial, `/gos dkp` and `/gos alliance` still open what they used to.

Then: drag Roster somewhere, `/reload`, `/gos open roster`.
Expected: it reopens exactly where it was left, at the size it was left.

- [ ] **Step 8: Commit**

```bash
git add UI/Features.lua UI/RosterFrame.lua Core/Commands.lua GuildOS.toc Locales/enUS.lua
git commit -m "feat: register every feature and open windows from slash commands"
```

---

### Task 5: The hub card

**Files:**
- Create: `UI/Hub.lua`
- Modify: `Core/Core.lua` (`ToggleRoster` at line 587 opens the hub)
- Modify: `UI/Minimap.lua` (context menu generated from the registry, replacing lines 50-95)
- Modify: `UI/Onboarding.lua` (lines 98-99 open the Settings window directly)
- Modify: `GuildOS.toc` (add `UI\Hub.lua` after `UI\Window.lua`)
- Modify: `Locales/enUS.lua`

**Interfaces:**
- Consumes: `UI:VisibleFeatures("hub")`, `UI:ToggleWindow(id)`, `UI:IsWindowOpen(id)`, `UI:CloseAllWindows()`, `UI:OpenWindow(id, subKey)`, `BRutus.Calendar:NextEvent()` (used the same way as `UI/Dashboard.lua:105`), `BRutus:ToggleExpanded()` (Task 6 — guard the call with `if BRutus.ToggleExpanded then`).
- Produces: `UI.Hub` with `UI.Hub.frame`, `UI.Hub:Toggle()`, `UI.Hub:Refresh()`; persisted state at `db.settings.hub = { point, relPoint, x, y, collapsed, pulse }`.

- [ ] **Step 1: Build the hub frame**

Create `UI/Hub.lua`:

```lua
----------------------------------------------------------------------
-- Guild OS - Hub
-- The minimal front door: a ~230px card with a live pulse band and one
-- clickable row per enabled feature. Rows toggle their feature's window,
-- so the hub is the only thing on screen until the user asks for more.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local Hub = {}
UI.Hub = Hub

local WIDTH   = 230
local TITLE_H = 24
local ROW_H   = 22
local PULSE_H = 34
local FOOT_H  = 22

local function cfg()
    local h = BRutus:GetSetting("hub")
    if type(h) ~= "table" then
        h = { collapsed = false, pulse = true }
        BRutus:SetSetting("hub", h)
    end
    return h
end

local function saveHubPos(f)
    local point, _, relPoint, x, y = f:GetPoint()
    local c = cfg()
    c.point, c.relPoint = point, relPoint or point
    c.x, c.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end
```

- [ ] **Step 2: Add the chrome, pulse band, row pool and footer**

Continue `UI/Hub.lua`:

```lua
function Hub:Create()
    if self.frame then return self.frame end
    local c = cfg()

    local f = UI:CreatePanel(UIParent, "GuildOSHub")
    f:SetWidth(WIDTH)
    f:SetHeight(TITLE_H + PULSE_H + FOOT_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    UI:StylePopup(f)
    f:ClearAllPoints()
    if c.point then
        f:SetPoint(c.point, UIParent, c.relPoint or c.point, c.x or 0, c.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -320, 120)
    end
    f:SetScale(BRutus:GetSetting("uiScale") or 1)
    self.frame = f

    -- Title bar: drag, and click to collapse to just this bar.
    local bar = CreateFrame("Button", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); saveHubPos(f) end)
    bar:SetScript("OnClick", function()
        cfg().collapsed = not cfg().collapsed
        Hub:Refresh()
    end)

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = UI:CreateHeaderText(bar, "GUILD OS", 11)
    title:SetPoint("LEFT", 8, 0)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local gear = UI:CreateButton(f, "|TInterface\\Icons\\INV_Misc_Gear_01:12|t", 20, 18)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetScript("OnClick", function() UI:OpenWindow("settings") end)
    UI:AddTooltip(gear, L["Settings"])

    local expand = UI:CreateButton(f, "[ ]", 20, 18)
    expand:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    expand:SetScript("OnClick", function()
        if BRutus.ToggleExpanded then BRutus:ToggleExpanded() end
    end)
    UI:AddTooltip(expand, L["Expanded mode"])

    -- Pulse band: two live lines, off when settings.hub.pulse is false.
    local pulse = CreateFrame("Frame", nil, f)
    pulse:SetPoint("TOPLEFT", 0, -TITLE_H)
    pulse:SetPoint("TOPRIGHT", 0, -TITLE_H)
    pulse:SetHeight(PULSE_H)
    f.pulse = pulse
    f.pulseOnline = UI:CreateText(pulse, "", 10, C.text.r, C.text.g, C.text.b)
    f.pulseOnline:SetPoint("TOPLEFT", 10, -4)
    f.pulseEvent = UI:CreateText(pulse, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.pulseEvent:SetPoint("TOPLEFT", 10, -18)

    -- Row pool: rows are reused across refreshes, never re-created.
    f.rows = {}
    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetHeight(FOOT_H)

    local more = UI:CreateButton(f.footer, L["... more"], 70, 18)
    more:SetPoint("LEFT", 8, 0)
    more:SetScript("OnClick", function() Hub:ToggleMorePage() end)

    local closeAll = UI:CreateButton(f.footer, L["Close all"], 70, 18)
    closeAll:SetPoint("RIGHT", -8, 0)
    closeAll:SetScript("OnClick", function() UI:CloseAllWindows() end)

    table.insert(UISpecialFrames, "GuildOSHub")
    return f
end

----------------------------------------------------------------------
-- One row: dot (window open) + icon + label + optional badge.
----------------------------------------------------------------------
local function acquireRow(f, index)
    local row = f.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, f, "BackdropTemplate")
    row:SetSize(WIDTH - 12, ROW_H)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0)

    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("LEFT", 2, 0)
    row.dot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
    row.label:SetPoint("LEFT", 30, 0)

    row.badge = UI:CreateText(row, "", 10, C.gold.r, C.gold.g, C.gold.b)
    row.badge:SetPoint("RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)

    f.rows[index] = row
    return row
end
```

- [ ] **Step 3: Implement Refresh — the whole layout in one function**

Continue `UI/Hub.lua`:

```lua
----------------------------------------------------------------------
-- Rebuild the card from the registry. Cheap enough to call on every
-- open/close: it repositions pooled rows, it does not create frames.
----------------------------------------------------------------------
function Hub:Refresh()
    local f = self.frame
    if not f then return end
    local c = cfg()

    if c.collapsed then
        for _, row in pairs(f.rows) do row:Hide() end
        f.pulse:Hide()
        f.footer:Hide()
        f:SetHeight(TITLE_H)
        return
    end

    local y = TITLE_H
    if c.pulse then
        f.pulse:Show()
        -- Counted live from the guild roster API, the same way
        -- frame:UpdateRail does it (UI/RosterFrame.lua:925-943). db.members
        -- has no online flag.
        local online, total = 0, 0
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if name then
                total = total + 1
                if isOnline then online = online + 1 end
            end
        end
        f.pulseOnline:SetText(string.format(L["%d online of %d"], online, total))

        -- The next event belongs to the Guild feature; if that is switched
        -- off, the line goes with it.
        if BRutus:IsFeatureEnabled("guild") then
            local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
            f.pulseEvent:SetText(e and (e.title or "?") or L["No upcoming events scheduled."])
        else
            f.pulseEvent:SetText("")
        end
        y = y + PULSE_H
    else
        f.pulse:Hide()
    end

    local defs = self.morePage and self:MoreEntries() or UI:VisibleFeatures("hub")
    local shown = 0
    for i, def in ipairs(defs) do
        local row = acquireRow(f, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)
        row.label:SetText(def.label)
        if def.icon then row.icon:SetTexture(def.icon) else row.icon:SetTexture(nil) end
        row.dot:SetShown(UI:IsWindowOpen(def.id))
        local n = def.badge and def.badge() or 0
        row.badge:SetText((n and n > 0) and tostring(n) or "")
        row:SetScript("OnClick", function()
            if def.sub then UI:OpenWindow(def.id, def.sub) else UI:ToggleWindow(def.id) end
        end)
        row:Show()
        y = y + ROW_H
        shown = i
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end

    if shown == 0 then
        local row = acquireRow(f, 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)
        row.icon:SetTexture(nil)
        row.dot:Hide()
        row.badge:SetText("")
        row.label:SetText(L["Everything is disabled — open Settings"])
        row:SetScript("OnClick", function() UI:OpenWindow("settings") end)
        row:Show()
        y = y + ROW_H
    end

    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", 0, -(y + 2))
    f.footer:SetPoint("TOPRIGHT", 0, -(y + 2))
    f.footer:Show()
    f:SetHeight(y + 2 + FOOT_H)
end

----------------------------------------------------------------------
-- Second page: loose tools and sub-tab deep links, shown in the same
-- card so "more" never costs another window.
----------------------------------------------------------------------
function Hub:MoreEntries()
    local out = {}
    local function add(id, label, sub, fn)
        out[#out + 1] = { id = id, label = label, sub = sub, badge = nil, run = fn }
    end
    add("roster", L["Search"], nil)
    out[#out].run = function() if BRutus.Search then BRutus.Search:Show() end end
    if BRutus:IsFeatureEnabled("raids") then
        add("raids", L["Raids"] .. " > " .. L["Audit"], "audit")
        add("raids", L["Raids"] .. " > " .. L["Raid Tools"], "raidtools")
    end
    if BRutus:IsFeatureEnabled("guild") then
        add("guild", L["Guild"] .. " > " .. L["Calendar"], "calendar")
    end
    return out
end

function Hub:ToggleMorePage()
    self.morePage = not self.morePage
    self:Refresh()
end

function Hub:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
    else
        self.morePage = false
        self:Refresh()
        f:Show()
    end
end
```

**Note on `MoreEntries`:** entries returned here carry an optional `run` function. Extend the row `OnClick` in `Refresh` to honour it:

```lua
        row:SetScript("OnClick", function()
            if def.run then def.run()
            elseif def.sub then UI:OpenWindow(def.id, def.sub)
            else UI:ToggleWindow(def.id) end
        end)
```

- [ ] **Step 4: Point every entry at the hub**

`Core/Core.lua` — `ToggleRoster` (line 587) keeps its guild/guildless guards and its `C_GuildInfo.GuildRoster()` refresh, but now toggles the hub. Replace the body after the guildless branch with:

```lua
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
    end
    if BRutus.UI and BRutus.UI.Hub then
        BRutus.UI.Hub:Toggle()
    end
```

`UI/Minimap.lua` — replace the hand-written menu items (lines 50-95) with a registry loop, keeping the title and the loose tools:

```lua
local function MinimapMenu_Init(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.isTitle = true; info.notCheckable = true
    info.text = "|cffFFD700Guild|r |cffD4AC0DOS|r"
    UIDropDownMenu_AddButton(info, level)

    for _, def in ipairs(BRutus.UI:VisibleFeatures("hub")) do
        info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
        info.text = def.label
        info.func = function() BRutus.UI:OpenWindow(def.id); CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = L["Guild Map"]
    info.func = function()
        if BRutus.ToggleGuildMap then BRutus:ToggleGuildMap() end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = L["Do I know this pug?"]
    info.func = function()
        if BRutus.TogglePugInspector then BRutus:TogglePugInspector() end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)
end
```

Delete the now-unused local `OpenSettings` helper above it (`UI/Minimap.lua:43-48`); the Settings entry comes from the registry loop.

`UI/Onboarding.lua:98-99` does the same "show the big frame, then switch tab" dance. Replace both lines with:

```lua
        BRutus.UI:OpenWindow("settings")
```

- [ ] **Step 5: Add strings and register the file**

Append to `Locales/enUS.lua` under a `-- UI/Hub.lua` block:

```lua
-- UI/Hub.lua
L["Expanded mode"] = "Expanded mode"
L["... more"] = "... more"
L["Close all"] = "Close all"
L["%d online of %d"] = "%d online of %d"
L["Everything is disabled — open Settings"] = "Everything is disabled — open Settings"
```

Add to `GuildOS.toc`, after `UI\Window.lua`:

```
UI\Hub.lua
```

- [ ] **Step 6: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71).

In-game: `/reload`, then `/gos`
Expected: the hub card appears (~230px wide), showing the pulse lines and one row per enabled feature. Officer-only rows are absent on a non-officer character.

- [ ] **Step 7: Verify hub behaviour**

In-game, in order:
1. Click `Roster` → the Roster window opens, the row grows a dot.
2. Click `Roster` again → it closes, the dot goes.
3. Open Roster and Loot → both stay open; `Close all` closes both.
4. Click the hub title bar → the card collapses to the title bar; click again → it expands.
5. Drag the hub, `/reload`, `/gos` → it reappears where it was left, in the same collapsed state.
6. `... more` → the same card shows the tools page; `... more` again returns.
7. Right-click the minimap button → the menu lists exactly the enabled features plus Guild Map and the pug check.

- [ ] **Step 8: Commit**

```bash
git add UI/Hub.lua Core/Core.lua UI/Minimap.lua UI/Onboarding.lua GuildOS.toc Locales/enUS.lua
git commit -m "feat: minimal hub card as the addon front door"
```

---

### Task 6: Expanded mode fed by the registry

**Files:**
- Modify: `UI/RosterFrame.lua` (tab creation at lines 375-505; panel creation at lines 510-1127)
- Modify: `Core/Core.lua` (add `BRutus:ToggleExpanded()`)

**Interfaces:**
- Consumes: `UI:AllFeatures("tab")`, `UI:GetFeature(id)`, `BRutus:IsFeatureEnabled(id)`.
- Produces: `BRutus:ToggleExpanded()`; `frame.tabPanels[key]` unchanged in shape, but panels are built on first activation.

**Why this is safe:** `SetActiveTab` and `UpdateTabVisibility` keep their current signatures and behaviour, so `UI/Dashboard.lua:53-60`, `UI/CalendarPanel.lua:588` and `Core/Commands.lua:519` need no changes.

- [ ] **Step 1: Replace the hardcoded tab list with a registry loop**

In `UI/RosterFrame.lua`, delete the 13 `CreateTab(...)` calls (lines 486-505) and replace with:

```lua
    -- Tabs come from the feature registry: one entry, every surface.
    -- AllFeatures, not VisibleFeatures — a tab hidden by a toggle must
    -- still exist so UpdateTabVisibility can bring it back.
    for _, def in ipairs(UI:AllFeatures("tab")) do
        CreateTab(def.id, def.label, def.officerOnly, def.condition)
    end
```

`CreateTab` keeps its current body, including the `condition` field it already supports (line 399).

- [ ] **Step 2: Make panels lazy**

Delete every per-tab block from `local homePanel = ...` (line 510) through the `settingsPanel` block (ending at line 1127) — including the roster stub Task 3 left behind — and replace all of it with:

```lua
    ----------------------------------------------------------------
    -- Tab panels: one empty container per registered tab, filled by the
    -- feature's build() the first time that tab is activated. This used
    -- to construct all thirteen panels (and every sub-panel) up front.
    ----------------------------------------------------------------
    for _, def in ipairs(UI:AllFeatures("tab")) do
        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 0, contentTop)
        panel:SetPoint("BOTTOMRIGHT", 0, BOTTOM_BAR_H)
        panel:Hide()
        panel.featureId = def.id
        frame.tabPanels[def.id] = panel
    end
```

`BOTTOM_BAR_H` is `30` — the inset every existing panel uses (`SetPoint("BOTTOMRIGHT", 0, 30)`), matching the bottom bar's height at line 1131. Declare it as a file-local constant next to `TAB_HEIGHT` (line 53) rather than repeating the literal.

Everything after the deleted range — the bottom bar at line 1128 onwards — stays exactly as it is.

Then extend `frame:SetActiveTab` (line 431) to build on first activation, before the show/hide loop:

```lua
    function frame:SetActiveTab(key)
        local panel = self.tabPanels[key]
        local def   = UI:GetFeature(key)
        if panel and def and not panel.built then
            panel.built = true
            def.build(panel, self)
        end
        self.activeTab = key
```

- [ ] **Step 3: Honour feature toggles in tab visibility**

In `frame:UpdateTabVisibility` (line 453), add the enabled check as the first gate:

```lua
        for _, tab in ipairs(self.tabs) do
            local visible = BRutus:IsFeatureEnabled(tab.key)
            if visible then
                if tab.condition then
                    visible = tab.condition()
                elseif tab.officerOnly then
                    visible = BRutus:IsOfficer()
                end
            end
```

- [ ] **Step 4: Add the expanded-mode toggle**

Add to `Core/Core.lua`, immediately after `BRutus:ToggleRoster`:

```lua
----------------------------------------------------------------------
-- Expanded mode: the full tabbed window. The hub is the default front
-- door; this is the opt-in for people who want everything at once.
----------------------------------------------------------------------
function BRutus:ToggleExpanded()
    if not (self.db and IsInGuild()) then return end
    if not self.RosterFrame then
        self.RosterFrame = BRutus.CreateRosterFrame()
    end
    if self.RosterFrame:IsShown() then
        self.RosterFrame:Hide()
        return
    end
    C_GuildInfo.GuildRoster()
    self.RosterFrame:UpdateTabVisibility()
    self.RosterFrame:Show()
end
```

- [ ] **Step 5: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71).

In-game: `/reload` then `/gos selftest`
Expected: `0 failed`.

- [ ] **Step 6: Verify expanded mode**

In-game:
1. `/gos` → hub → `[ ]` → the full window opens with the same tabs as before.
2. Click through every tab → each renders its real content (this is the check that lazy building did not break a panel).
3. From the Home dashboard, click a card → it navigates to the right tab, as before.
4. `[ ]` again (or the window's close button) → the full window closes, hub stays.

- [ ] **Step 7: Commit**

```bash
git add UI/RosterFrame.lua Core/Core.lua
git commit -m "refactor: build expanded-mode tabs from the feature registry, lazily"
```

---

### Task 7: Settings toggles from the registry, plus UI scale

**Files:**
- Modify: `UI/FeaturePanels.lua` (module toggle section, lines 1812-1878)
- Modify: `Locales/enUS.lua`

**Interfaces:**
- Consumes: `UI:AllFeatures(nil)` — every feature, disabled ones included, no surface filter — plus `def.core`, `def.desc`, `def.module`; `BRutus:SetFeatureEnabled(id, enabled)`; `UI:ApplyScale()`.
- Produces: nothing new; this task deletes a hand-maintained list.

- [ ] **Step 1: Generate the toggle list**

In `UI/FeaturePanels.lua`, delete the hardcoded `modules` table (lines 1830-1841) and the `db.settings.modules` seeding block (lines 1819-1827 — `SetFeatureEnabled` creates the table on demand, and absent means on). Replace the loop header so it walks the registry:

```lua
    -- Toggles come from the feature registry. AllFeatures, not
    -- VisibleFeatures: a disabled feature must keep its checkbox, or
    -- there is no way left to switch it back on. `core` features have no
    -- switch at all — turning Settings or Roster off would lock the user out.
    for _, def in ipairs(UI:AllFeatures(nil)) do
        if not def.core then
```

Inside the loop body, keep the existing row construction and replace the checkbox wiring:

```lua
        cb.checkbox:SetChecked(BRutus:IsFeatureEnabled(def.id))
        cb.checkbox.onChanged = function(_, checked)
            BRutus:SetFeatureEnabled(def.id, checked)
            -- Windows are lazy, so UI features toggle live. Background
            -- modules register their events at Initialize, so only those
            -- still need a reload.
            local needsReload = def.module and not def.hub
            BRutus:Print(def.label .. (checked
                and L[" |cff00ff00enabled|r."]
                or  L[" |cffFF4444disabled|r."])
                .. (needsReload and L[" Reload UI to apply."] or ""))
            if def.id == "lootMaster" and BRutus.LootMaster and BRutus.LootMaster.SetEnabled then
                BRutus.LootMaster:SetEnabled(checked and true or false)
            end
        end
```

Use `def.desc or ""` where the old code used `mod.desc`, and `def.label` where it used `mod.label`. The `officerOnly` skip is already handled by `VisibleFeatures`, so delete the surrounding `if not mod.officerOnly or isOfficer then` guard and its `end`.

- [ ] **Step 2: Add the UI scale slider**

In the same Settings panel, directly above the module section (before the `MODULES` header at line 1815), add:

```lua
    local scaleLabel = UI:CreateText(content, L["UI scale"], 11, C.text.r, C.text.g, C.text.b)
    scaleLabel:SetPoint("TOPLEFT", 0, -yOff)

    local scale = CreateFrame("Slider", "GuildOSScaleSlider", content, "OptionsSliderTemplate")
    scale:SetPoint("TOPLEFT", 120, -yOff)
    scale:SetWidth(180)
    scale:SetMinMaxValues(0.8, 1.2)
    scale:SetValueStep(0.05)
    scale:SetObeyStepOnDrag(true)
    scale:SetValue(BRutus:GetSetting("uiScale") or 1)
    _G[scale:GetName() .. "Low"]:SetText("80%")
    _G[scale:GetName() .. "High"]:SetText("120%")
    _G[scale:GetName() .. "Text"]:SetText(string.format("%d%%", (BRutus:GetSetting("uiScale") or 1) * 100))
    scale:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20   -- snap to the 0.05 step
        BRutus:SetSetting("uiScale", value)
        _G[self:GetName() .. "Text"]:SetText(string.format("%d%%", value * 100))
        UI:ApplyScale()
    end)
    yOff = yOff + 40
```

Add `"OptionsSliderTemplate"` usage needs no luacheck entry (it is a string), but `_G` does — confirm `_G` is accepted by the current `.luacheckrc`; if luacheck flags it, add `"_G"` to `read_globals`.

- [ ] **Step 3: Add strings**

Append to `Locales/enUS.lua` under a `-- UI/FeaturePanels.lua` block (create it if absent):

```lua
L["UI scale"] = "UI scale"
L[" Reload UI to apply."] = " Reload UI to apply."
```

- [ ] **Step 4: Run both gates**

Run: `luacheck . --config .luacheckrc`
Expected: 0 errors, warning count unchanged from baseline (71).

In-game: `/reload` then `/gos selftest`
Expected: `0 failed`.

- [ ] **Step 5: Verify the modularity rule end to end**

In-game:
1. `/gos` → open Settings → uncheck `Recipes`.
2. Expected, with no reload: the Recipes row disappears from the hub; if its window was open it closes; the minimap menu no longer lists it; `/gos recipes` prints "Recipes is disabled in Settings."; expanded mode has no Recipes tab.
3. Re-check `Recipes` → the row is back and `/gos recipes` opens it.
4. Uncheck `Comm System` (a background module) → the printed line ends with "Reload UI to apply."
5. Confirm Settings and Roster have **no** checkbox at all.
6. Drag the UI scale slider to 85% → the hub and every open window shrink immediately; `/reload` keeps the setting.

- [ ] **Step 6: Commit**

```bash
git add UI/FeaturePanels.lua Locales/enUS.lua
git commit -m "feat: generate settings toggles from the feature registry, add UI scale"
```

---

## Follow-up (not in this plan)

Spec section 10, phase 4 — migrating the 11 existing ad-hoc floating windows (Search, Digest, CraftFinder, PugInspector, GuildMap, Bulletin, GuildAnalytics, RecruitBeacon, AllyCard, EventEditor, Onboarding) onto `UI:CreateWindow`. It is pure deletion plus saved positions for free, it touches 11 unrelated files, and nothing in this plan depends on it. It gets its own plan once the hub has shipped and the container has survived contact with real use.
