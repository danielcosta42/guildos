# Tier 2 #3 — Guild Analytics Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Composition analytics — distribution of the guild by **class / level bracket / rank / zone**, shown as horizontal bars in a self-contained window (`/gos analytics`), with an online-only toggle.

**Architecture:** New `Modules/GuildAnalytics.lua` — pure `Distribution(dim, onlineOnly, roster?)` aggregation + `BuildRoster()` (live from `GetGuildRosterInfo`) + a self-contained `Show()` window (mirrors `Bulletin:Show`), so it does NOT touch the main frame's tab system. Race dimension dropped (no reliable BCC race from the roster).

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. New globals `RAID_CLASS_COLORS`, `LOCALIZED_CLASS_NAMES_MALE` → `.luacheckrc` if flagged.
- `local`-scope; module `local X={}; BRutus.X=X`. `GetGuildRosterInfo` nil-checked, 1-indexed.
- Colors from `BRutus.Colors` (class colors from `RAID_CLASS_COLORS`). All user-facing strings in all 5 locales. Rule 10.
- Commits Conventional; **no AI attribution**.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/GuildAnalytics.lua` | Create | Pure `Distribution`/`_LevelBracket` + `BuildRoster` + `Show()` window + self-tests. |
| `Core/Core.lua` | Modify | Register `GuildAnalytics:Initialize()` in InitModules. |
| `Core/Commands.lua` | Modify | `/gos analytics` opens the window. |
| `GuildOS.toc` | Modify | Add `Modules\GuildAnalytics.lua`. |
| `.luacheckrc` | Modify | `RAID_CLASS_COLORS`, `LOCALIZED_CLASS_NAMES_MALE` if flagged. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: GuildAnalytics module (pure Distribution) + self-tests

**Files:** Create `Modules/GuildAnalytics.lua`; modify `GuildOS.toc`, `Core/Core.lua`, `.luacheckrc`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `GetGuildRosterInfo`/`GetNumGuildMembers`.
- Produces:
  - `GuildAnalytics.DIMENSIONS = { "class", "level", "rank", "zone" }`.
  - `GuildAnalytics:_LevelBracket(level) -> string`.
  - `GuildAnalytics:Distribution(dim, onlineOnly, roster?) -> (array, total)` — pure; `roster` array of `{class, level, rank, zone, online}`; returns sorted-desc `{ {label, count, pct, colorKey} }`.
  - `GuildAnalytics:BuildRoster() -> array` (live).

- [ ] **Step 1: Create the module (logic)**

```lua
----------------------------------------------------------------------
-- Guild OS - Guild Analytics
-- Composition distributions (class / level / rank / zone) as pure
-- aggregation over the guild roster, shown as bars in a /gos analytics window.
----------------------------------------------------------------------
local GuildAnalytics = {}
BRutus.GuildAnalytics = GuildAnalytics
local L = BRutus.L

GuildAnalytics.DIMENSIONS = { "class", "level", "rank", "zone" }

function GuildAnalytics:Initialize()
    self:_RegisterTests()
end

function GuildAnalytics:_LevelBracket(level)
    level = level or 0
    if level >= 70 then return "70" end
    local lo = math.floor(level / 10) * 10
    if lo == 0 then return "1-9" end
    return lo .. "-" .. (lo + 9)
end

function GuildAnalytics:BuildRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { class = classFile, level = level, rank = rank, zone = zone, online = online }
        end
    end
    return roster
end

function GuildAnalytics:Distribution(dim, onlineOnly, roster)
    roster = roster or self:BuildRoster()
    local counts, order, total = {}, {}, 0
    for _, m in ipairs(roster) do
        if (not onlineOnly) or m.online then
            local key, colorKey
            if dim == "class" then key = m.class or "?"; colorKey = m.class
            elseif dim == "level" then key = self:_LevelBracket(m.level)
            elseif dim == "rank" then key = m.rank or "?"
            elseif dim == "zone" then key = (m.zone and m.zone ~= "" and m.zone) or "?"
            else key = "?" end
            if not counts[key] then counts[key] = { count = 0, colorKey = colorKey }; order[#order + 1] = key end
            counts[key].count = counts[key].count + 1
            total = total + 1
        end
    end
    local out = {}
    for _, k in ipairs(order) do
        out[#out + 1] = { label = k, count = counts[k].count, colorKey = counts[k].colorKey }
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.label) < tostring(b.label)
    end)
    for _, e in ipairs(out) do e.pct = total > 0 and (e.count / total * 100) or 0 end
    return out, total
end
```

_(Note: for `dim=="class"`, `label` is the class file token; the UI localizes via `LOCALIZED_CLASS_NAMES_MALE` and colors via `RAID_CLASS_COLORS`. Keeping the raw token here keeps `Distribution` pure and testable.)_

- [ ] **Step 2: Self-tests**

```lua
function GuildAnalytics:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("analytics.class", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false }, { class = "WARRIOR", online = true } }
        local out, total = GuildAnalytics:Distribution("class", false, roster)
        if total ~= 3 then return false, "total" end
        if out[1].label ~= "MAGE" or out[1].count ~= 2 then return false, "top bucket" end
        return true
    end)
    S:Register("analytics.online_filter", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false } }
        local _, total = GuildAnalytics:Distribution("class", true, roster)
        if total ~= 1 then return false, "online-only" end
        return true
    end)
    S:Register("analytics.level_bracket", function()
        if GuildAnalytics:_LevelBracket(70) ~= "70" then return false, "70" end
        if GuildAnalytics:_LevelBracket(65) ~= "60-69" then return false, "60-69" end
        if GuildAnalytics:_LevelBracket(5) ~= "1-9" then return false, "1-9" end
        return true
    end)
    S:Register("analytics.pct", function()
        local roster = { { class = "MAGE" }, { class = "MAGE" }, { class = "ROGUE" }, { class = "ROGUE" } }
        local out = GuildAnalytics:Distribution("class", false, roster)
        if math.abs(out[1].pct - 50) > 0.01 then return false, "pct" end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules + luacheckrc)**

`.toc`: add `Modules\GuildAnalytics.lua`. `Core/Core.lua InitModules()`: `if BRutus.GuildAnalytics then BRutus.GuildAnalytics:Initialize() end`. `.luacheckrc`: add `RAID_CLASS_COLORS`, `LOCALIZED_CLASS_NAMES_MALE` under a `-- Class data` comment if flagged (used by Task 2's UI). If `local L` is unused in this task, remove it.

- [ ] **Step 4: Lint + commit**

luacheck 0/0. (Agent: hand-trace the 4 self-tests. Runtime `/gos selftest` → 30 total.)

```bash
git add Modules/GuildAnalytics.lua GuildOS.toc Core/Core.lua .luacheckrc
git commit -m "feat: GuildAnalytics composition distributions (class/level/rank/zone, tested)"
```

---

## Task 2: Analytics window + `/gos analytics`

**Files:** Modify `Modules/GuildAnalytics.lua` (add `Show`), `Core/Commands.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `Distribution`; `RAID_CLASS_COLORS`, `LOCALIZED_CLASS_NAMES_MALE`; `UI:*` factories, `BRutus.Colors`.

- [ ] **Step 1: Build `GuildAnalytics:Show()`**

Mirror the self-contained window pattern of `Modules/Bulletin.lua:Show()` (a `CreateFrame("Frame", "GuildOSAnalyticsFrame", UIParent, "BackdropTemplate")`, `UI:StylePopup`, title, `UI:CreateCloseButton`, draggable). Read `Bulletin.lua:Show` first for the exact idiom (backdrop colors, title, close). Contents:
- **Dimension selector:** 4 `UI:CreateTab` (or `UI:CreateButton`) — Class / Levels / Ranks / Zones — set `self._dim`.
- **Online-only** checkbox (`UI:CreateCheckbox`) → `self._onlineOnly`.
- **Bar list** (a scroll frame via `UI:CreateScrollFrame` + `SetAllPoints`, per the ScrollFrame gotcha in memory): for each `Distribution(self._dim, self._onlineOnly)` entry, a row:
  - label (left): for `class`, `LOCALIZED_CLASS_NAMES_MALE[label] or label`; else `label`.
  - a bar: a texture whose width = `pct/100 * barMaxWidth`; color = for class, `RAID_CLASS_COLORS[colorKey]` (r,g,b); else `C.accent`.
  - value (right): `count .. " (" .. string.format("%.0f%%", pct) .. ")"`.
- A refresh function recomputed on dimension/toggle change and on show.

Store `self._dim = self._dim or "class"`, `self._onlineOnly` default false.

- [ ] **Step 2: `/gos analytics` command**

In `Core/Commands.lua handleCommand`, add:
```lua
    elseif msg == "analytics" or msg == "stats" then
        if BRutus.GuildAnalytics then BRutus.GuildAnalytics:Show() end
```

- [ ] **Step 3: Locale + lint + commit**

Add all used keys in all 5 files: `L["Guild Analytics"]`, `L["Class"]` (may exist — reuse), `L["Levels"]`, `L["Ranks"]`, `L["Zones"]`, `L["Online only"]`, `L["No data."]`, and any others used. (grep each in enUS first; only add missing.)

luacheck 0/0. In-game (human): `/gos analytics` opens a window; switching Class/Levels/Ranks/Zones and toggling Online only redraws the bars; class bars use class colors.

```bash
git add Modules/GuildAnalytics.lua Core/Commands.lua Locales/
git commit -m "feat: Guild Analytics window (/gos analytics) with distribution bars"
```

---

## Self-Review
- Spec §Feature-3 (class/level/rank/zone distribution, online toggle, bars) → Tasks 1-2. **Race dropped** (documented). ✓
- Self-contained window (no main-tab surgery) — lower risk. ✓
- Types: `Distribution(dim, onlineOnly, roster?)` → `{label,count,pct,colorKey}` consistent; `_LevelBracket` pure; `BuildRoster` fields `{class,level,rank,zone,online}`.
- Reuses ScrollFrame gotcha (SetAllPoints) from memory.
- Human-verify: `/gos selftest` (30); `/gos analytics` window, dimension switching, class colors, online toggle.
