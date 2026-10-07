# GuildOS — Dev Workflow

_Last updated: 2026-04-26_

---

## Mandatory Agent Workflow: READ → CREATE → WRITE

**Every task that touches .lua files must follow this pattern:**

### 1. READ
Before writing any code:
- Read `.memory/architecture.md` (or `/memories/repo/architecture.md`) — module map, data flow, load order
- Read `.memory/functions-catalog.md` (or `/memories/repo/functions-catalog.md`) — find existing functions; never duplicate
- Read `.memory/lua-best-practices.md` — coding rules (14 rules)
- Read `.memory/quality-checklist.md` — know what to verify before finishing
- If modifying UI: read `UI/Helpers.lua` for available factory functions and the `C` color table
- If adding an architectural pattern: read `.memory/decisions.md` first, then add an ADR

### 2. CREATE (plan)
- Identify which module owns the new logic (see Module Map in architecture.md)
- Confirm one-way data flow: `Game Events → Modules → State/DB → UI`
- Confirm no business logic will land in UI callbacks (Rule 10)
- Confirm `GuildOS.State.*` is used for session data, not module member vars (Rule 6)
- Confirm `GuildOS:GetSetting()` / `GuildOS:SetSetting()` used for settings (Rule 8)
- Identify any new WoW API globals that need adding to `.luacheckrc`

### 3. WRITE
- Implement changes with `local` scoping at file scope
- Register module as `GuildOS.ModuleName = {}` if creating a new module
- Run luacheck BEFORE calling `task_complete`:
  ```
  C:\Users\danie\bin\luacheck.exe . --config .luacheckrc
  ```
- Fix ALL warnings before completing — **0 warnings / 0 errors required**
- Update `.memory/functions-catalog.md` if new public functions were added
- Update `.memory/decisions.md` if a new architectural pattern was introduced

---

## luacheck
- Binary: `C:\Users\danie\bin\luacheck.exe`
- Config: `.luacheckrc` at workspace root
- Must pass: `0 warnings / 0 errors`
- New WoW API globals → add to `read_globals` in `.luacheckrc` under appropriate section comment

---

## Architectural Decision Records (ADRs)

When introducing a **new architectural pattern or significant design choice**:

1. Open `.memory/decisions.md`
2. Add a new ADR section
3. Include: Context, Decision, Consequences (+/-)

ADRs document **why** the codebase is structured the way it is.
See existing ADRs in `decisions.md` as examples.

---

## Commit Convention (Conventional Commits)

| Prefix | Use for |
|---|---|
| `feat:` | new feature (minor bump) |
| `fix:` | bug fix (patch bump) |
| `feat!:` | breaking change (major bump) |
| `refactor:` | code restructure, no behavior change |
| `perf:` | performance improvement |
| `chore:` | maintenance, deps |
| `docs:` | documentation only |
| `test:` | tests |
| `ci:` | CI/CD changes |
| `style:` | formatting only |

---

## CI/CD
- **Lint**: luacheck on every push/PR to `main`
- **Versioning**: auto-semver from Conventional Commits
- **Changelog**: auto-generated, prepended to `CHANGELOG.md`
- **Publish**: BigWigsMods packager → CurseForge (project ID 1549177, BCC client)

---

## Module Template (new data module)

```lua
----------------------------------------------------------------------
-- GuildOS Guild Manager - ModuleName
-- One-line description of responsibility
----------------------------------------------------------------------
local ModuleName = {}
GuildOS.ModuleName = ModuleName

----------------------------------------------------------------------
-- Initialize (called by GuildOS:InitModules)
----------------------------------------------------------------------
function ModuleName:Initialize()
    if not GuildOS.db.moduleName then
        GuildOS.db.moduleName = {}
    end
    -- register events if needed
end
```

Rules:
- `local` everything at file scope
- Only write to `GuildOS.*` for module registration
- No globals, no random event frames outside Initialize
- Guard all WoW API calls that may not exist (via `GuildOS.Compat.*`)

---

## Module Template (new UI panel)

```lua
----------------------------------------------------------------------
-- GuildOS Guild Manager - UI/PanelName
-- One-line description of this panel
----------------------------------------------------------------------
local UI  = GuildOS.UI
local C   = UI.Colors           -- theme color table from UI/Helpers.lua

local PanelName = {}
GuildOS.UI.PanelName = PanelName

function PanelName:Create(parent)
    -- build frame hierarchy using UI:CreateButton(), UI:CreateText(), etc.
    -- NEVER inline backdrop logic or color constants
    -- NEVER write to GuildOS.db directly — call module methods
end

function PanelName:Refresh()
    -- read GuildOS.db.* or GuildOS.State.* and update visual state
end
```

---

## DB Access Pattern

```lua
-- Read
local data = GuildOS.db.members[key] or {}

-- Write (only inside the owning module method)
GuildOS.db.members[key] = data

-- Settings read/write — ALWAYS via accessors
local val = GuildOS:GetSetting("showOffline")
GuildOS:SetSetting("showOffline", true)

-- Never: mutate GuildOS.db.settings from UI callbacks directly
```

---

## Permission Gates

```lua
-- General officer check
if not GuildOS:IsOfficer() then return end

-- Validate incoming officer-only comm messages: the officer AND the channel. IsOfficerByName
-- drops the realm, so without GUILD a namesake on another realm could whisper as the officer
-- (issues #78, #81). A new SyncService domain goes in OFFICER_DOMAINS or GUILD_ONLY_DOMAINS.
if channel ~= "GUILD" or not GuildOS:IsOfficerByName(sender) then return end
```

---

## Comm Protocol (adding a new message type)

1. Add constant to `CommSystem.MSG_TYPES`:
   ```lua
   MY_TYPE = "MT",
   ```
2. Add handler in `CommSystem:OnMessageReceived`:
   ```lua
   elseif msgType == CommSystem.MSG_TYPES.MY_TYPE then
       if GuildOS.MyModule then
           GuildOS.MyModule:HandleIncoming(data)
       end
   ```
3. Send via:
   ```lua
   GuildOS.CommSystem:SendMessage(CommSystem.MSG_TYPES.MY_TYPE, serialized)
   ```
4. Use `"NORMAL"` priority only for time-sensitive messages (default is `"BULK"`).

---

## UI Conventions

| Pattern | Details |
|---|---|
| Colors | Always from `C` table in `UI/Helpers.lua` — **never hardcode** |
| Buttons | `UI:CreateButton()` |
| Headers | `UI:CreateHeaderText()` |
| Close buttons | `UI:CreateCloseButton()` |
| Plain text | `UI:CreateText()` |
| Virtual scroll (lists) | `FauxScrollFrameTemplate` + `FauxScrollFrame_Update/GetOffset` |
| Content scroll (panels) | `UIPanelScrollFrameTemplate` |
| Scroll bar skinning | `UI:SkinScrollBar()` |
| Tooltips | `GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")` → populate → Show/Hide |
| Row hover flicker | Check `IsMouseOver()` in OnLeave for child button rows |
| FauxScrollFrame rows | Always reset ALL visual state in UpdateRows — **never assume previous state** |
| Backdrop | Pass `"BackdropTemplate"` (TBC Anniversary always needs it) |

---

## Common Pitfalls

- `GetLootMethod()` returns nil on Anniversary — use `LootMaster:IsMasterLooter()` (4-tier fallback)
- `SendChatMessage` needs hardware event for some channels — use popup-based pattern
- `GetGuildRosterInfo` is 1-indexed, may return nil — always nil-check
- `.toc` load order matters — a file cannot reference modules defined in later files
- Addon messages have 255-byte limit — always chunk large payloads (CommSystem handles this)
- `PLAYER_ENTERING_WORLD` fires on every zone transition — guard with `isInitialLogin or isReloadingUi`
- FauxScrollFrame rows are reused — always reset ALL visual state, never assume previous state
- `C_Timer.*` on Anniversary client exists but guard with `GuildOS.Compat.*` for forward safety
