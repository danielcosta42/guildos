# RosterLog / Event Log (Roster Admin & Audit — Subsistema 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A synced, deduplicated guild audit trail — who joined/left, who was kicked/promoted/demoted **and by whom** — captured from system messages, stored with a cap, shown in the Leadership "Audit Log" tab, and surfaced in the login digest.

**Architecture:** New `Modules/RosterLog.lua` following the officer-domain-sync template. A `CHAT_MSG_SYSTEM` hook parses guild events via the localized `ERR_GUILD_*` format strings (giving the actor for kicks/promotes/demotes) into events `{ id, action, target, author, detail, timestamp }`, deduped by a stable `id`. Events publish live over a new `audit` SyncService domain (officer-write); online officers converge (cold-login backfill is deferred to the shared cold-sync follow-up). RosterLog **absorbs** `GuildManager.managementLog` (officer addon-actions delegate to it; existing entries migrate once). The existing Leadership "History" sub-tab is relabeled "Audit Log" and reads RosterLog. `Digest:Build` gains audit counts.

**Tech Stack:** Lua 5.1 (BCC Interface 20506), SyncService v2, luacheck.

## Global Constraints

- **Client:** BCC Interface **20506**. `C_Timer` via `BRutus.Compat.*`.
- **Lint gate (mandatory per task):** `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc` → **0 warnings / 0 errors**. New WoW globals → `.luacheckrc read_globals` under a section comment.
- **Event shape** is fixed and reuses the existing History UI's field names: `{ id (string), action (string), target (string|nil), author (string|nil), detail (string|nil), timestamp (number) }`. `action` ∈ `join | leave | kick | promote | demote | motd | info` (motd/info come from the absorbed managementLog).
- **`audit` is an officer-domain** in `SyncService.OFFICER_DOMAINS` (only officers publish; everyone may keep a local copy). No ACK (broadcast; convergence via id-dedup + live publish). **Cold-login backfill is out of scope** (deferred to the shared cold-sync follow-up with the `ban`/`bulletin` domains).
- **SavedVariables:** `db.rosterLog.events` is a ring buffer — cap **1000** entries / prune **> 90 days**, via `RosterLog:Prune()` called from `Initialize`.
- `GetGuildRosterInfo` nil-checked. Colors from `BRutus.Colors`. Every user-facing string in all 5 locales.
- **Commits:** Conventional Commits. **No `Co-Authored-By` / AI attribution.**

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Modules/RosterLog.lua` | Create | Event model, pure `_EventId`/`_ParseSystem`, `_Insert`/`Add`/`Record`/`GetLog`/`Clear`/`Prune`/`CountsSince`, detection hook, `audit` sync, self-tests. |
| `Modules/SyncService.lua` | Modify | Add `audit = true` to `OFFICER_DOMAINS`. |
| `Modules/GuildManager.lua` | Modify | `LogAction`/`GetLog`/`ClearLog` delegate to RosterLog; one-time managementLog migration. |
| `Core/Core.lua` | Modify | Register `RosterLog:Initialize()` in `InitModules` (after SyncService). |
| `Modules/Digest.lua` | Modify | Audit counts in `Build`. |
| `UI/ManagementPanel.lua` | Modify | Relabel "History" sub-tab → "Audit Log"; add `join`/`leave` to `ACTION_LABELS`. |
| `GuildOS.toc` | Modify | Register `RosterLog.lua` after `SyncService.lua`. |
| `.luacheckrc` | Modify | Add `ERR_GUILD_LEAVE_S`, `ERR_GUILD_REMOVE_SS`, `ERR_GUILD_PROMOTE_SSS`, `ERR_GUILD_DEMOTE_SSS`. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: Module + model + pure logic (`_EventId`, `_ParseSystem`, `_Insert`) + self-tests

**Files:** Create `Modules/RosterLog.lua`; modify `GuildOS.toc`, `Core/Core.lua`, `.luacheckrc`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `GetServerTime`; the `ERR_GUILD_*` globals.
- Produces:
  - `RosterLog:_NormShort(name) -> string` — short name (strip realm), preserving case.
  - `RosterLog:_EventId(action, target, author, ts) -> string` — stable key; `ts` bucketed to 5s.
  - `RosterLog:_ParseSystem(msg) -> table|nil` — returns `{ action, target, author, detail }` for a guild join/leave/kick/promote/demote system message, else nil.
  - `RosterLog:_Insert(evt, store?) -> boolean` — dedups by `evt.id` (assigns `id`/`timestamp` if missing) into `store` (default `db.rosterLog.events`); returns true if newly inserted; keeps store capped.
  - `RosterLog:Prune(now?, store?) -> removedCount`.
  - `RosterLog:GetLog(store?) -> array` — newest-first copy.

- [ ] **Step 1: Create the module skeleton + pure logic**

Create `Modules/RosterLog.lua`:

```lua
----------------------------------------------------------------------
-- Guild OS - Roster Log (guild audit trail)
-- Captures join/leave/kick/promote/demote (with actor) from system
-- messages; synced officer-authoritative (domain "audit"); absorbs the
-- old GuildManager action log. Cold-login backfill is a tracked follow-up.
----------------------------------------------------------------------
local RosterLog = {}
BRutus.RosterLog = RosterLog
local L = BRutus.L

local CAP = 1000
local MAX_AGE = 90 * 86400

function RosterLog:Initialize()
    BRutus.db.rosterLog = BRutus.db.rosterLog or { events = {} }
    BRutus.db.rosterLog.events = BRutus.db.rosterLog.events or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("audit", function(env) RosterLog:OnSync(env) end)
    end
    self:_MigrateManagementLog()
    self:_SetupDetection()
    self:Prune()
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic; unit-tested via /gos selftest)
----------------------------------------------------------------------
function RosterLog:_NormShort(name)
    if not name or name == "" then return name end
    return name:match("^([^-]+)") or name
end

function RosterLog:_EventId(action, target, author, ts)
    local bucket = math.floor((ts or 0) / 5)
    return string.format("%s|%s|%s|%d", tostring(action), tostring(target or ""),
        tostring(author or ""), bucket)
end

-- Build a Lua pattern from a localized "%s ... %s" format string. Returns
-- the pattern and the number of captures, in order of appearance.
local function fmtToPattern(fmt)
    if not fmt then return nil end
    -- escape magic chars, then turn each %s into a capture
    local esc = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    local pat = esc:gsub("%%s", "(.+)")
    return "^" .. pat .. "$"
end

function RosterLog:_ParseSystem(msg)
    if not msg then return nil end
    msg = strtrim(msg)
    -- join: ERR_GUILD_JOIN_S = "%s has joined the guild."
    local p = fmtToPattern(ERR_GUILD_JOIN_S)
    if p then local t = msg:match(p); if t then return { action = "join", target = self:_NormShort(t) } end end
    -- leave: ERR_GUILD_LEAVE_S = "%s has left the guild."
    p = fmtToPattern(ERR_GUILD_LEAVE_S)
    if p then local t = msg:match(p); if t then return { action = "leave", target = self:_NormShort(t) } end end
    -- kick: ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."  (target, actor)
    p = fmtToPattern(ERR_GUILD_REMOVE_SS)
    if p then local t, a = msg:match(p); if t and a then
        return { action = "kick", target = self:_NormShort(t), author = self:_NormShort(a) } end end
    -- promote: ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."  (actor, target, rank)
    p = fmtToPattern(ERR_GUILD_PROMOTE_SSS)
    if p then local a, t, rk = msg:match(p); if a and t then
        return { action = "promote", target = self:_NormShort(t), author = self:_NormShort(a), detail = rk } end end
    -- demote: ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."  (actor, target, rank)
    p = fmtToPattern(ERR_GUILD_DEMOTE_SSS)
    if p then local a, t, rk = msg:match(p); if a and t then
        return { action = "demote", target = self:_NormShort(t), author = self:_NormShort(a), detail = rk } end end
    return nil
end

function RosterLog:_Insert(evt, store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events)
    if not store or not evt then return false end
    evt.timestamp = evt.timestamp or GetServerTime()
    evt.id = evt.id or self:_EventId(evt.action, evt.target, evt.author, evt.timestamp)
    for i = 1, #store do
        if store[i].id == evt.id then return false end   -- dedup
    end
    store[#store + 1] = evt
    while #store > CAP do table.remove(store, 1) end
    return true
end

function RosterLog:Prune(now, store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events)
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for i = #store, 1, -1 do
        if (store[i].timestamp or 0) < now - MAX_AGE then
            table.remove(store, i); removed = removed + 1
        end
    end
    return removed
end

function RosterLog:GetLog(store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events) or {}
    local out = {}
    for i = #store, 1, -1 do out[#out + 1] = store[i] end
    return out
end
```

Add stubs so later tasks fill them (prevents nil-call from Initialize order):

```lua
function RosterLog:_MigrateManagementLog() end   -- Task 4
function RosterLog:_SetupDetection() end          -- Task 2
function RosterLog:OnSync() end                    -- Task 3
```

- [ ] **Step 2: Self-tests**

```lua
function RosterLog:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("rosterlog.parse_join", function()
        local e = RosterLog:_ParseSystem("Grefer has joined the guild.")
        if not e or e.action ~= "join" or e.target ~= "Grefer" then return false, "join" end
        return true
    end)
    S:Register("rosterlog.parse_kick", function()
        local e = RosterLog:_ParseSystem("Grefer has been kicked out of the guild by Daniel.")
        if not e or e.action ~= "kick" or e.target ~= "Grefer" or e.author ~= "Daniel" then return false, "kick" end
        return true
    end)
    S:Register("rosterlog.parse_promote", function()
        local e = RosterLog:_ParseSystem("Daniel has promoted Grefer to Officer.")
        if not e or e.action ~= "promote" or e.target ~= "Grefer" or e.author ~= "Daniel" then return false, "promote" end
        return true
    end)
    S:Register("rosterlog.dedup", function()
        local store = {}
        local a = RosterLog:_Insert({ action = "join", target = "X", timestamp = 100 }, store)
        local b = RosterLog:_Insert({ action = "join", target = "X", timestamp = 101 }, store)  -- same 5s bucket
        if not a or b or #store ~= 1 then return false, "dedup" end
        return true
    end)
    S:Register("rosterlog.prune", function()
        local store = { { action = "join", target = "Y", timestamp = 1, id = "y" } }
        local n = RosterLog:Prune(1 + MAX_AGE + 1, store)
        if n ~= 1 or #store ~= 0 then return false, "prune" end
        return true
    end)
end
```

- [ ] **Step 3: Register in .toc + InitModules + luacheckrc**

In `GuildOS.toc`, after `Modules\SyncService.lua`, add `Modules\RosterLog.lua`.
In `Core/Core.lua` `BRutus:InitModules()`, after `BRutus.SyncService:Initialize()`, add:

```lua
    if BRutus.RosterLog then
        BRutus.RosterLog:Initialize()
    end
```

In `.luacheckrc read_globals`, under a `-- Guild system messages` comment, add `"ERR_GUILD_LEAVE_S"`, `"ERR_GUILD_REMOVE_SS"`, `"ERR_GUILD_PROMOTE_SSS"`, `"ERR_GUILD_DEMOTE_SSS"` (JOIN_S is already present).

- [ ] **Step 4: Verify + lint + commit**

luacheck 0/0. (Agent: hand-trace the 5 self-tests. Runtime `/gos selftest` should show the prior 12 + these 5 = 17, human-verified.)

```bash
git add Modules/RosterLog.lua GuildOS.toc Core/Core.lua .luacheckrc
git commit -m "feat: RosterLog model + system-message parsers + dedup (tested)"
```

---

## Task 2: Detection hook + Record/Add

**Files:** Modify `Modules/RosterLog.lua`.

**Interfaces:**
- Consumes: `_ParseSystem`, `_Insert`; `BRutus.Compat.After`, `GetServerTime`, `BRutus:IsOfficer`.
- Produces:
  - `RosterLog:Record(action, target, author, detail) -> boolean` — builds an event and `Add`s it.
  - `RosterLog:Add(evt) -> boolean` — `_Insert` locally; if inserted AND officer AND SyncService, publish `audit`/`add`.
  - `RosterLog:_SetupDetection()` — real body (replaces the Task 1 stub).

- [ ] **Step 1: Implement Record/Add + detection (replace the `_SetupDetection` stub)**

```lua
function RosterLog:Add(evt)
    local inserted = self:_Insert(evt)
    if inserted then
        self:_Publish(evt)     -- no-op until Task 3; safe stub below
        self:Refresh()
    end
    return inserted
end

function RosterLog:Record(action, target, author, detail)
    return self:Add({
        action = action, target = target and self:_NormShort(target) or nil,
        author = author and self:_NormShort(author) or nil, detail = detail,
        timestamp = GetServerTime(),
    })
end

function RosterLog:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

function RosterLog:_SetupDetection()
    self._ready = false
    BRutus.Compat.After(8, function() RosterLog._ready = true end)
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, _, msg)
        if not RosterLog._ready then return end
        local evt = RosterLog:_ParseSystem(msg)
        if evt then RosterLog:Add(evt) end
    end)
end
```

Add a temporary `_Publish` stub (Task 3 replaces it):

```lua
function RosterLog:_Publish() end   -- Task 3
```

- [ ] **Step 2: Verify + lint + commit**

luacheck 0/0. (Agent: static-trace — a "kicked out ... by Daniel" system line → `_ParseSystem` → `Add` → `_Insert` stores one event. In-game is the human's checkpoint.)

```bash
git add Modules/RosterLog.lua
git commit -m "feat: RosterLog detects guild events from system messages"
```

---

## Task 3: `audit` sync domain (live publish + dedup apply)

**Files:** Modify `Modules/SyncService.lua`, `Modules/RosterLog.lua`.

**Interfaces:**
- Consumes: `SyncService:Publish`, `SyncService.OFFICER_DOMAINS`, `BRutus:IsOfficer`, `_Insert`.
- Produces: `RosterLog:_Publish(evt)` (real), `RosterLog:OnSync(env)` (real).

- [ ] **Step 1: Register the domain**

In `Modules/SyncService.lua` `OFFICER_DOMAINS` (block with `bulletin = true`), add:

```lua
    audit    = true,   -- guild audit trail (officer-authoritative, id-deduped)
```

- [ ] **Step 2: Replace the `_Publish`/`OnSync` stubs**

```lua
function RosterLog:_Publish(evt)
    if not BRutus.SyncService or not BRutus:IsOfficer() then return end
    -- broadcast; convergence is by id-dedup on receipt (no rev, no ACK).
    BRutus.SyncService:Publish("audit", "add", { evt = evt })
end

function RosterLog:OnSync(env)
    if env.act == "add" and env.data and env.data.evt then
        if self:_Insert(env.data.evt) then self:Refresh() end
    end
end
```

_(Note: `_Insert` already dedups by `id`, so a locally-detected event and the same event echoed back over sync collapse to one. Non-officers never `_Publish`, but they still apply inbound `audit` events into their local log.)_

- [ ] **Step 3: Verify + lint + commit**

luacheck 0/0. (Agent: static-trace — officer detects a kick → `Add` inserts + `_Publish` broadcasts `{evt}`; a peer officer's `OnSync` `_Insert`s it (new id) once; a third copy of the same id is dropped. In-game / 2-client convergence is the human's checkpoint.)

```bash
git add Modules/SyncService.lua Modules/RosterLog.lua
git commit -m "feat: sync RosterLog events live over officer-domain audit"
```

---

## Task 4: Absorb managementLog + relabel the sub-tab

**Files:** Modify `Modules/RosterLog.lua`, `Modules/GuildManager.lua`, `UI/ManagementPanel.lua`.

**Interfaces:**
- Consumes: `RosterLog:Record/GetLog/Prune`; existing `GuildManager.managementLog`, `GuildManager:GetLog/ClearLog/LogAction`.
- Produces: `RosterLog:_MigrateManagementLog()` (real); `RosterLog:Clear()`.

- [ ] **Step 1: Migration + Clear (replace the Task 1 `_MigrateManagementLog` stub)**

```lua
function RosterLog:_MigrateManagementLog()
    if BRutus.db.rosterLog.migrated then return end
    BRutus.db.rosterLog.migrated = true
    local old = BRutus.db.managementLog
    if type(old) == "table" then
        for _, e in ipairs(old) do
            self:_Insert({
                action = e.action, target = e.target, author = e.author,
                detail = e.detail, timestamp = e.timestamp,
            })
        end
    end
end

function RosterLog:Clear()
    if not BRutus:IsOfficer() then return end
    BRutus.db.rosterLog.events = {}
    self:Refresh()
end
```

- [ ] **Step 2: Delegate GuildManager's log to RosterLog**

In `Modules/GuildManager.lua`:
- In `LogAction(action, target, detail)`: if `BRutus.RosterLog` exists, `BRutus.RosterLog:Record(action, target, UnitName("player"), detail)` and return; otherwise keep the existing ring-buffer append (fallback for load-order safety).
- `GetLog()`: `if BRutus.RosterLog then return BRutus.RosterLog:GetLog() end` before the existing body.
- `ClearLog()`: `if BRutus.RosterLog then BRutus.RosterLog:Clear(); return end` before the existing body.

(Keep the existing `managementLog` code as the fallback branch — don't delete it.)

- [ ] **Step 3: Relabel the sub-tab + add action labels**

In `UI/ManagementPanel.lua`:
- Change the `SUBTABS` entry `{ key = "log", label = L["History"] }` to `label = L["Audit Log"]`.
- Add to `ACTION_LABELS`:

```lua
    join    = { txt = L["Joined"], color = "online" },
    leave   = { txt = L["Left"],   color = "offline" },
```

- [ ] **Step 4: Locales (all 5) + lint + commit**

enUS master (translate the rest): `L["Audit Log"]`, `L["Joined"]`, `L["Left"]`.

luacheck 0/0. In-game (human): Leadership → Audit Log shows joins/leaves/kicks (with "by"), and MOTD/info edits still appear (via the delegate).

```bash
git add Modules/RosterLog.lua Modules/GuildManager.lua UI/ManagementPanel.lua Locales/
git commit -m "feat: RosterLog absorbs the action log; History becomes Audit Log"
```

---

## Task 5: Feed the login digest

**Files:** Modify `Modules/RosterLog.lua`, `Modules/Digest.lua`, `Locales/*.lua`.

**Interfaces:**
- Consumes: `db.rosterLog.events`.
- Produces: `RosterLog:CountsSince(since) -> { join=n, leave=n, kick=n }` (pure).

- [ ] **Step 1: CountsSince + self-test**

```lua
function RosterLog:CountsSince(since, store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events) or {}
    local c = { join = 0, leave = 0, kick = 0 }
    for _, e in ipairs(store) do
        if (e.timestamp or 0) > (since or 0) and c[e.action] ~= nil then
            c[e.action] = c[e.action] + 1
        end
    end
    return c
end
```

Add a self-test:

```lua
    S:Register("rosterlog.counts", function()
        local store = { { action="join", timestamp=10 }, { action="kick", timestamp=20 }, { action="join", timestamp=5 } }
        local c = RosterLog:CountsSince(8, store)
        if c.join ~= 1 or c.kick ~= 1 then return false, "counts" end
        return true
    end)
```

- [ ] **Step 2: Add digest lines**

In `Modules/Digest.lua` `Build(since)`, after the "New members" block, add:

```lua
    -- Roster changes since last login (from the audit log)
    if BRutus.RosterLog then
        local c = BRutus.RosterLog:CountsSince(since)
        if c.kick > 0 then lines[#lines + 1] = string.format(L["%d member(s) removed"], c.kick) end
        if c.leave > 0 then lines[#lines + 1] = string.format(L["%d member(s) left"], c.leave) end
    end
```

(Joins are already reported by the existing `firstSeen` block — don't double-count; only add kick/leave.)

- [ ] **Step 3: Locales (all 5) + lint + commit**

enUS master (translate the rest): `L["%d member(s) removed"]`, `L["%d member(s) left"]`.

luacheck 0/0. (`/gos selftest` → 18 total.) In-game (human): after a session with a kick, the login digest shows "N member(s) removed".

```bash
git add Modules/RosterLog.lua Modules/Digest.lua Locales/
git commit -m "feat: RosterLog audit counts in the login digest"
```

---

## Self-Review

**Spec coverage (design spec §7):**
- §7.1 detection via ERR_GUILD_* (actor) → Tasks 1 (parsers) + 2 (hook). Roster-diff (level/note) intentionally dropped — documented (low value, rapid-fire-event risk). ✓
- §7.2 model + dedup id → Task 1 (`_EventId`/`_Insert`). ✓
- §7.3 sync → Task 3 (live publish + dedup). **Backfill-on-login deferred** to the shared cold-sync follow-up (F1) — documented. ✓
- §7.4 absorb managementLog → Task 4 (delegate + migration). ✓
- §7.5 UI Audit Log → Task 4 (relabel + labels; reuses existing BuildLogSub which already reads `GuildManager:GetLog`, now delegated). ✓
- §7.6 cap+prune → Task 1 (`Prune`, CAP/MAX_AGE). ✓
- §7.7 name-change reconciliation (GUID) → out of scope (stretch; documented). ✓
- Digest feed → Task 5. ✓

**Deviations (intentional, documented):** roster-diff detection dropped; cold-login backfill deferred to F1; GUID name-reconciliation out of scope.

**Type consistency:** event fields `{id, action, target, author, detail, timestamp}` consistent across model, UI (existing BuildLogSub reads `timestamp/action/target/detail/author`), migration, sync, digest. `_EventId/_ParseSystem/_Insert/Add/Record/GetLog/Clear/Prune/CountsSince/OnSync/_Publish` used consistently; stubs in Task 1 are replaced by Tasks 2-4 with matching signatures.

**Human-verification (no client here):** `/gos selftest` (18 cases), in-game kick/join/promote captured with actor, Audit Log tab, MOTD/info still logged via delegate, digest counts, 2-client live convergence.
