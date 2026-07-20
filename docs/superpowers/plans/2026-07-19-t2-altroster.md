# Tier 2 #1 — Alt/Main + True Roster Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** An aggregation layer over the existing `db.altLinks` — `GetMain`/`IsAlt`/`GetAltTag`/`GetTrueRoster` — plus a "unique players / total chars" KPI and an "alt of X" indicator in the member inspector. Unblocks Tier 2 #2 (chat tags) and #3 (analytics unique count).

**Architecture:** New `Modules/AltRoster.lua` holds pure aggregation (injectable data for tests). Thin `BRutus:GetAltTag`/`GetTrueRoster` wrappers read live `db.altLinks` + the guild roster. Existing `BRutus:LinkAlt/UnlinkAlt/GetLinkedChars` (Core/Utils.lua) and altLinks sync (CommSystem) are reused unchanged. The full "collapse alts under main" grouped roster view is a DEFERRED follow-up (invasive RosterFrame surgery, lower incremental value).

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0** (`C:\Users\danie\bin\luacheck.exe . --config .luacheckrc`).
- `local`-scope; module `local X={}; BRutus.X=X`. `GetGuildRosterInfo` nil-checked, 1-indexed.
- Every user-facing string in all 5 locales. Colors from `BRutus.Colors`. Rule 10 (no logic in UI callbacks).
- Commits Conventional; **no `Co-Authored-By`/AI attribution**.
- Reuse existing: `db.altLinks = {[altKey]=mainKey}`; `BRutus:GetLinkedChars(key)`; officer-gated `LinkAlt/UnlinkAlt`.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/AltRoster.lua` | Create | Pure `GetMain/IsAlt/GetAltTag/BuildTrueRoster` + `BRutus:GetAltTag/GetTrueRoster` wrappers + self-tests. |
| `Core/Core.lua` | Modify | Register `AltRoster:Initialize()` in InitModules. |
| `GuildOS.toc` | Modify | Add `Modules\AltRoster.lua`. |
| `UI/RosterFrame.lua` | Modify | Add "unique players / chars" KPI. |
| `UI/MemberDetail.lua` | Modify | Show "alt of X" near the name. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: AltRoster aggregation API + self-tests

**Files:** Create `Modules/AltRoster.lua`; modify `GuildOS.toc`, `Core/Core.lua`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `BRutus.db.altLinks`; `GetGuildRosterInfo`/`GetNumGuildMembers`.
- Produces:
  - `AltRoster:GetMain(key, links?) -> key` — `links` default `BRutus.db.altLinks`; returns `links[key] or key`.
  - `AltRoster:IsAlt(key, links?) -> boolean`.
  - `AltRoster:GetAltTag(key, links?) -> string|nil` — nil if not an alt; else `"alt of " .. shortMain`.
  - `AltRoster:BuildTrueRoster(roster, links?) -> { groups={ {main, alts={} } }, uniqueCount, totalChars }` — pure; `roster` is an array of member keys.
  - `BRutus:GetAltTag(key) -> string|nil` (live wrapper).
  - `BRutus:GetTrueRoster() -> table` (live wrapper: builds keys from the guild roster, then `BuildTrueRoster`).

- [ ] **Step 1: Create the module + pure API**

```lua
----------------------------------------------------------------------
-- Guild OS - AltRoster
-- Aggregation over db.altLinks (main/alt grouping + "True Roster"
-- unique-player counts). Linking itself lives in Core/Utils (LinkAlt).
----------------------------------------------------------------------
local AltRoster = {}
BRutus.AltRoster = AltRoster

function AltRoster:Initialize()
    self:_RegisterTests()
end

local function shortName(key)
    if not key then return "" end
    return key:match("^([^-]+)") or key
end

function AltRoster:GetMain(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    return links[key] or key
end

function AltRoster:IsAlt(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    return links[key] ~= nil
end

function AltRoster:GetAltTag(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    local m = links[key]
    if not m then return nil end
    return string.format(BRutus.L["alt of %s"], shortName(m))
end

-- roster: array of member keys present in the guild. Returns groups keyed
-- by canonical main, the count of unique mains (unique players) and total
-- chars observed.
function AltRoster:BuildTrueRoster(roster, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    local byMain = {}
    local order = {}
    for _, key in ipairs(roster) do
        local main = links[key] or key
        if not byMain[main] then
            byMain[main] = { main = main, alts = {} }
            order[#order + 1] = main
        end
        if main ~= key then
            table.insert(byMain[main].alts, key)
        end
    end
    local groups = {}
    for _, m in ipairs(order) do groups[#groups + 1] = byMain[m] end
    return { groups = groups, uniqueCount = #order, totalChars = #roster }
end

----------------------------------------------------------------------
-- Live wrappers
----------------------------------------------------------------------
function BRutus:GetAltTag(key)
    return AltRoster:GetAltTag(key)
end

function BRutus:GetTrueRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then roster[#roster + 1] = full end
    end
    return AltRoster:BuildTrueRoster(roster)
end
```

_(Note: guild roster keys here are the `GetGuildRosterInfo` full name. `db.altLinks` keys must be the same form for a match — they are, per the existing `LinkAlt` usage in MemberDetail which links roster keys. If a mismatch surfaces in-game, normalization is a follow-up.)_

- [ ] **Step 2: Self-tests**

```lua
function AltRoster:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local links = { ["Alt1-R"] = "Main-R", ["Alt2-R"] = "Main-R" }
    S:Register("altroster.getmain", function()
        if AltRoster:GetMain("Alt1-R", links) ~= "Main-R" then return false, "alt->main" end
        if AltRoster:GetMain("Main-R", links) ~= "Main-R" then return false, "main->self" end
        return true
    end)
    S:Register("altroster.isalt", function()
        if not AltRoster:IsAlt("Alt1-R", links) or AltRoster:IsAlt("Main-R", links) then return false end
        return true
    end)
    S:Register("altroster.tag", function()
        local t = AltRoster:GetAltTag("Alt1-R", links)
        if not t or not t:find("Main", 1, true) then return false, tostring(t) end
        if AltRoster:GetAltTag("Main-R", links) ~= nil then return false, "main has no tag" end
        return true
    end)
    S:Register("altroster.truer", function()
        local r = AltRoster:BuildTrueRoster({ "Main-R", "Alt1-R", "Alt2-R", "Solo-R" }, links)
        -- 2 unique players (Main + Solo), 4 chars; Main group has 2 alts
        if r.uniqueCount ~= 2 or r.totalChars ~= 4 then return false, "counts" end
        for _, g in ipairs(r.groups) do
            if g.main == "Main-R" and #g.alts ~= 2 then return false, "alt count" end
        end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules)**

`GuildOS.toc`: add `Modules\AltRoster.lua` (any position after the libs; it only needs SelfTest at Initialize, which is order-safe). In `Core/Core.lua BRutus:InitModules()`, add:
```lua
    if BRutus.AltRoster then
        BRutus.AltRoster:Initialize()
    end
```

- [ ] **Step 4: Locale + lint + commit**

`L["alt of %s"]` in all 5 files (enUS: `"alt of %s"`; ptBR: `"alt de %s"`; esES: `"alt de %s"`; deDE: `"Twink von %s"`; frFR: `"reroll de %s"`).

luacheck 0/0. (Agent: hand-trace the 4 self-tests; runtime `/gos selftest` → 22 total, human checkpoint.)

```bash
git add Modules/AltRoster.lua GuildOS.toc Core/Core.lua Locales/
git commit -m "feat: AltRoster aggregation API (GetMain/GetAltTag/GetTrueRoster, tested)"
```

---

## Task 2: Surface it — unique-players KPI + "alt of X" in the inspector

**Files:** Modify `UI/RosterFrame.lua`, `UI/MemberDetail.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `BRutus:GetTrueRoster`, `BRutus:GetAltTag`.

- [ ] **Step 1: Unique-players KPI in the roster band**

In `UI/RosterFrame.lua`, find the KPI card band (grep for the existing KPI/stat cards — e.g. member counts). Add one card "Players" showing `GetTrueRoster().uniqueCount` with a sub-label `"of N chars"` (`totalChars`), styled exactly like the sibling cards. Update it in the same refresh path the other cards use.

- [ ] **Step 2: "alt of X" in the member inspector**

In `UI/MemberDetail.lua`, near where the member name/title is rendered, if `BRutus:GetAltTag(memberKey)` returns non-nil, show it as a dim line under the name (use `C.textDim`, `UI:CreateText`). MemberDetail already reads `db.altLinks` (~line 779), so the key form is consistent.

- [ ] **Step 3: Locale + lint + commit**

`L["Players"]`, `L["of %d chars"]` in all 5 files.

luacheck 0/0. In-game (human): the roster shows a Players (unique) KPI; an alt member's inspector shows "alt of <Main>".

```bash
git add UI/RosterFrame.lua UI/MemberDetail.lua Locales/
git commit -m "feat: unique-players KPI + alt-of indicator in the inspector"
```

---

## Self-Review
- Spec §Feature-1 API → Task 1 (GetMain/IsAlt/GetAltTag/BuildTrueRoster + wrappers). ✓
- True Roster count + tag surfacing → Task 2 (KPI + inspector). ✓
- **Deferred (documented):** the full collapse-alts-under-main grouped roster VIEW (invasive RosterFrame table surgery); alt-group rank sync (Blizzard lockdown).
- Reuses existing linking/sync — no new sync domain, no member-write. ✓
- Types: `GetMain/IsAlt/GetAltTag/BuildTrueRoster` consistent; `roster` = array of guild-roster full-name keys; `links` = `db.altLinks`.
- Human-verify: `/gos selftest` (22), Players KPI, alt-of inspector line.
