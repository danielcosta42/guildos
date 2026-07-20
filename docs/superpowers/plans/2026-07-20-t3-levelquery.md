# Tier 3 #3 — Level-query Roster Filter Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Let the roster search box accept expressive level filters — `19`, `60-70`, `>=60`, `<10`, and comma-lists like `19, 60-70` — while normal name/class/zone search still works.

**Architecture:** New pure `Modules/LevelQuery.lua` — `Parse(query) -> predicate(level)->bool` or `nil` when the text isn't a level query. Wire it into `RosterFrame:BuildMemberList`: compute the matcher once per refresh; if non-nil, filter members by level; else fall through to the existing name-substring search. No new on-screen UI (behavior + a search placeholder hint only).

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. `local`-scope. Strings in 5 locales. Commits Conventional; **no AI attribution**.
- **Must not break normal name search:** `Parse` returns nil for any non-level token, so name/class/zone search is unaffected.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/LevelQuery.lua` | Create | Pure `Parse` + self-tests. |
| `Core/Core.lua` | Modify | Register `LevelQuery:Initialize()` (just registers tests). |
| `GuildOS.toc` | Modify | Add `Modules\LevelQuery.lua`. |
| `UI/RosterFrame.lua` | Modify | Use the matcher in `BuildMemberList`; update the search placeholder hint. |
| `Locales/*.lua` (×5) | Modify | Placeholder string. |

---

## Task 1: `LevelQuery:Parse` + self-tests

**Files:** Create `Modules/LevelQuery.lua`; modify `GuildOS.toc`, `Core/Core.lua`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`.
- Produces: `LevelQuery:Parse(query) -> function(level)->boolean | nil`.

- [ ] **Step 1: Create the module**

```lua
----------------------------------------------------------------------
-- Guild OS - Level Query
-- Parses an expressive level filter into a predicate. Returns nil when
-- the text isn't a level query (so normal name search still applies).
-- Supports: exact "19", range "60-70", comparisons ">=60" "<=10" ">5" "<70",
-- and comma-lists "19, 60-70, >=68" (OR).
----------------------------------------------------------------------
local LevelQuery = {}
BRutus.LevelQuery = LevelQuery

function LevelQuery:Initialize()
    self:_RegisterTests()
end

function LevelQuery:Parse(query)
    if not query then return nil end
    query = query:gsub("%s+", "")
    if query == "" then return nil end
    local preds = {}
    for token in query:gmatch("[^,]+") do
        local op, num = token:match("^([<>]=?)(%d+)$")
        local lo, hi = token:match("^(%d+)%-(%d+)$")
        local exact = token:match("^(%d+)$")
        if op and num then
            num = tonumber(num)
            if op == ">"  then preds[#preds+1] = function(l) return l >  num end
            elseif op == ">=" then preds[#preds+1] = function(l) return l >= num end
            elseif op == "<"  then preds[#preds+1] = function(l) return l <  num end
            elseif op == "<=" then preds[#preds+1] = function(l) return l <= num end end
        elseif lo and hi then
            lo, hi = tonumber(lo), tonumber(hi)
            preds[#preds+1] = function(l) return l >= lo and l <= hi end
        elseif exact then
            local n = tonumber(exact)
            preds[#preds+1] = function(l) return l == n end
        else
            return nil     -- any non-level token => not a level query
        end
    end
    if #preds == 0 then return nil end
    return function(level)
        level = level or 0
        for _, p in ipairs(preds) do if p(level) then return true end end
        return false
    end
end
```

- [ ] **Step 2: Self-tests**

```lua
function LevelQuery:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("levelq.range", function()
        local m = LevelQuery:Parse("60-70")
        if not m or not m(65) or m(59) or not m(70) or not m(60) then return false, "range" end
        return true
    end)
    S:Register("levelq.exact_and_list", function()
        local m = LevelQuery:Parse("19, 70")
        if not m or not m(19) or not m(70) or m(50) then return false, "list" end
        return true
    end)
    S:Register("levelq.comparisons", function()
        if not LevelQuery:Parse(">=60")(60) then return false, ">=" end
        if LevelQuery:Parse(">60")(60) then return false, ">" end
        if not LevelQuery:Parse("<10")(9) then return false, "<" end
        return true
    end)
    S:Register("levelq.not_a_query", function()
        if LevelQuery:Parse("Bob") ~= nil then return false, "name => nil" end
        if LevelQuery:Parse("60-x") ~= nil then return false, "mixed => nil" end
        if LevelQuery:Parse("") ~= nil then return false, "empty => nil" end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules)**

`.toc`: add `Modules\LevelQuery.lua`. `Core/Core.lua InitModules()`: `if BRutus.LevelQuery then BRutus.LevelQuery:Initialize() end`.

- [ ] **Step 4: Lint + commit**

luacheck 0/0. (Agent: hand-trace the 4 self-tests. `/gos selftest` → +4.)

```bash
git add Modules/LevelQuery.lua GuildOS.toc Core/Core.lua
git commit -m "feat: LevelQuery parser for roster level filters (tested)"
```

---

## Task 2: Wire into the roster filter + placeholder hint

**Files:** Modify `UI/RosterFrame.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `BRutus.LevelQuery:Parse`.

- [ ] **Step 1: Use the matcher in `BuildMemberList`**

In `UI/RosterFrame.lua` `frame:BuildMemberList()` (~line 1229): after `local filter = self.searchFilter and strlower(strtrim(self.searchFilter)) or ""` (~line 1234), add:
```lua
        local levelMatch = (filter ~= "" and BRutus.LevelQuery) and BRutus.LevelQuery:Parse(filter) or nil
```
Then replace the existing name-filter block (~lines 1253-1258):
```lua
                if filter ~= "" then
                    local searchTarget = strlower(displayName .. " " .. (classLoc or "") .. " " .. (zone or "") .. " " .. (rankName or ""))
                    if not searchTarget:find(filter, 1, true) then
                        passFilter = false
                    end
                end
```
with:
```lua
                if filter ~= "" then
                    if levelMatch then
                        if not levelMatch(level or 0) then passFilter = false end
                    else
                        local searchTarget = strlower(displayName .. " " .. (classLoc or "") .. " " .. (zone or "") .. " " .. (rankName or ""))
                        if not searchTarget:find(filter, 1, true) then
                            passFilter = false
                        end
                    end
                end
```
(The matcher is computed once per refresh; a name query → `Parse` returns nil → unchanged name search.)

- [ ] **Step 2: Placeholder hint**

Change the search placeholder (~line 658) from `L["Search..."]` to a hint that mentions level queries, e.g. `L["Search / 60-70 / >=60"]`. (Text in the existing box — no new UI element.)

- [ ] **Step 3: Locale + lint + commit**

Add `L["Search / 60-70 / >=60"]` in all 5 files (keep `L["Search..."]` if used elsewhere).

luacheck 0/0. In-game (human): type `60-70` in the roster search → only 60-70 members show; `>=68` → high levels; a name → normal search still works.

```bash
git add UI/RosterFrame.lua Locales/
git commit -m "feat: roster search accepts level queries (60-70, >=60, lists)"
```

---

## Self-Review
- Spec §Feature-3 (exact/range/comparison/list level query in roster search, name search preserved) → Tasks 1-2. ✓
- Pure `Parse` tested (incl. name → nil, mixed → nil). Matcher computed once per refresh. No new UI (behavior + placeholder text).
- Human-verify: `/gos selftest` (+4); `60-70`/`>=68` filter the roster; name search unaffected.
