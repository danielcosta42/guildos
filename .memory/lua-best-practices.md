# WoW Addon Engineering Standards — GuildOS

_Last updated: 2026-04-26_

## Core Philosophy
- Addons are **event-driven systems**, not web apps.
- Performance matters more than feature count.
- Architecture must be modular, predictable, and easy to extend.
- **UI must never own business logic.**
- Game API differences must be isolated in `GuildOS.Compat`.
- `GuildOS.db` (SavedVariables) is persistent storage — `GuildOS.State` is session state.

---

## Rule 1 — Single Namespace

```lua
-- Good: attach to GuildOS namespace
local MyModule = {}
GuildOS.MyModule = MyModule

-- Bad: random globals
MyFunction = function() end
SomeTable = {}
```

- The only global this addon creates is `GuildOS`.
- All sub-modules attach as `GuildOS.ModuleName`.
- Inside each file, alias to a local for readability:
  ```lua
  local MyModule = {}
  GuildOS.MyModule = MyModule
  -- ... use MyModule:Fn() throughout the file
  ```

---

## Rule 2 — One-Responsibility Modules

| Module | Owns |
|---|---|
| `Core.lua` | GuildOS namespace, DB bootstrap, Logger, Compat, State, Config, utilities |
| `CommSystem.lua` | Addon message encode/chunk/send/receive/route |
| `UI/Helpers.lua` | ALL visual widgets + theme (until Theme/Core split) |
| Data modules | One feature domain each — no UI, no comm internals |
| UI panel files | Visual layout only — no data writes, no business logic |

No module may mix UI logic, storage, and game-event handling.

---

## Rule 3 — One-Way Data Flow

```
Game Events/API → Event handlers → Data Modules → GuildOS.db / GuildOS.State → UI reads
```

- UI reads `GuildOS.db.*` and `GuildOS.State.*` — never writes directly.
- UI callbacks call module methods (e.g. `GuildOS.RaidTracker:SetGroupTag(name)`).
- Module methods own all writes to `GuildOS.db.*`.

---

## Rule 4 — Compatibility Layer (`GuildOS.Compat`)

All version-sensitive calls go through `GuildOS.Compat`:

```lua
GuildOS.Compat.RegisterAddonPrefix(prefix)  -- guards C_ChatInfo.*
GuildOS.Compat.GuildRoster()                -- guards C_GuildInfo vs GuildRoster()
GuildOS.Compat.IsQuestComplete(questId)     -- guards C_QuestLog.*
GuildOS.Compat.After(delay, fn)             -- guards C_Timer.After
GuildOS.Compat.NewTicker(interval, fn, n)   -- guards C_Timer.NewTicker
GuildOS.Compat.NewTimer(delay, fn)          -- guards C_Timer.NewTimer
```

Never scatter `if C_SomeAPI then` checks across feature modules.

---

## Rule 5 — No Orphan Event Frames

```lua
-- Bad: random frames scattered across modules
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ... end)

-- Good: module registers via the framework's event frame or its own Initialize()
-- (GuildOS does not yet have a centralized Events pub/sub — see decisions.md ADR-0006)
-- Until that exists: one event frame per module, created inside Initialize()
```

---

## Rule 6 — State vs Storage Separation

```lua
-- Session-only (reset on /reload) → GuildOS.State
GuildOS.State.lootMaster.activeLoot = item

-- Persistent → GuildOS.db (via the owning module's method)
GuildOS.LootTracker:RecordLoot(item)  -- internally writes GuildOS.db.lootHistory
```

Never persist `GuildOS.State.*` fields. Never use `GuildOS.db.*` for runtime-only flags.

---

## Rule 7 — SavedVariables Discipline

```lua
-- Always initialize with defaults
GuildOSDB = GuildOSDB or {}
local db  = GuildOSDB[guildKey] or {}
db.version = db.version or 1
```

- Always versioned, always migrated safely.
- Store summaries and configuration — never raw event arrays.
- Accessed only after `PLAYER_LOGIN`.

---

## Rule 8 — Configuration Accessors

```lua
GuildOS:GetSetting("showOffline")       -- reads GuildOS.db.settings[key]
GuildOS:SetSetting("showOffline", true) -- writes GuildOS.db.settings[key]
```

Never read/write `GuildOS.db.settings.*` directly from UI callbacks. Always go through `GetSetting`/`SetSetting`.

---

## Rule 9 — Structured Logger

```lua
GuildOS.Logger.Debug("msg")   -- only when GuildOS.Logger.debug == true
GuildOS.Logger.Info("msg")
GuildOS.Logger.Warn("msg")    -- always prints
```

- No `print()` directly.
- No chat spam.
- Debug output gated behind `GuildOS.Logger.debug`.

---

## Rule 10 — UI/Logic Separation

```lua
-- Bad: business logic inside SetScript
Button:SetScript("OnClick", function()
    -- 80 lines of roll logic
end)

-- Good: callback is a one-liner delegation to the owning module
Button:SetScript("OnClick", function()
    GuildOS.LootMaster:StartRoll()
end)
```

All event handlers and UI callbacks must be named functions or one-liner delegations.
No inline business logic in `SetScript`, `OnEvent`, or `OnClick`.

---

## Rule 11 — Performance

**Avoid:**
- Heavy `OnUpdate` handlers (use `C_Timer.After` / `C_Timer.NewTicker` instead)
- Scanning guild roster every frame
- Rebuilding large scroll lists without dirty flags
- Storing raw combat event data in SavedVariables
- `string.format` or `table.insert` before confirming an event is relevant

**Prefer:**
- Event-driven updates
- Throttled updates (`C_Timer.After`)
- Cached lookups
- Lazy UI rendering (build rows only when the panel is shown)

---

## Rule 12 — UI Component Separation

`UI/Helpers.lua` currently mixes theme data, component factory, and widget utilities.
The target split (see `architecture.md`) is:

| File | Owns |
|---|---|
| `UI/Theme.lua` | `C` color table, score color helpers, size constants — **no frames** |
| `UI/Core.lua` | Component factory: `CreateButton`, `CreateText`, `CreateHeaderText`, `CreateCloseButton`, `SkinScrollBar`, backdrop helpers |
| `UI/Panels.lua` | Compound panel builders, tab builders — delegates to Core |
| Panel files | Window-specific layout only — use Core widgets, never re-create them inline |

**Until the split is done:**
- Never hardcode colors — always use the `C` table from `UI/Helpers.lua`.
- Never create custom backdrop logic outside `UI:SkinScrollBar()` / `UI:CreateButton()`.
- Reuse `UI:CreateButton()`, `UI:CreateText()`, `UI:CreateHeaderText()` — never create bare FontStrings inline.

---

## Rule 13 — Magic Numbers

Every numeric constant that affects behavior must be a named `local`:

```lua
local THROTTLE_INTERVAL = 60     -- seconds between BroadcastMyData calls
local CHUNK_SIZE        = 230    -- addon message chunk size (255 - prefix overhead)
local IDLE_THRESHOLD    = 2      -- seconds; gaps > this count as idle (RaidHUD)
```

---

## Rule 14 — Commenting

- Every **public function** (`GuildOS.*`) must have a one-line description comment above it.
- Every **compatibility workaround** must explain WHY the fallback exists.
- Every **magic number** must have an inline comment.

---

## Anti-Patterns to Avoid

- One giant Lua file
- Globals everywhere
- UI callbacks containing business logic
- Direct SavedVariables mutation across modules
- Parsing game events in multiple places
- Retail-only APIs without fallback
- Rebuilding UI constantly without dirty checks
- Storing everything "just in case"
- Copy/paste feature logic

---

## Quick Quality Checklist (before calling task_complete)

- [ ] `local` at file scope — no accidental globals
- [ ] `GuildOS.Compat.*` used for all version-sensitive API calls
- [ ] No `GuildOS.db.settings.*` written directly from UI
- [ ] No business logic inline in `SetScript` / `OnClick` / `OnEvent`
- [ ] Session state in `GuildOS.State.*`, not as module member vars
- [ ] luacheck: `0 warnings / 0 errors`
- [ ] `functions-catalog.md` updated if new public functions added
