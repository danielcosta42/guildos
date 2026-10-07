# GuildOS — Quality Checklist

_Last updated: 2026-04-26_

Run through this checklist before calling `task_complete` on any implementation.

---

## Namespace & Globals

- [ ] Only the `GuildOS` global is used — no new top-level globals created
- [ ] All file-scope variables are `local` — no accidental globals
- [ ] Sub-module registered as `GuildOS.ModuleName = {}` (not a bare global)
- [ ] Local alias used inside the file: `local MyModule = GuildOS.MyModule`

## Compatibility

- [ ] All version-sensitive API calls go through `GuildOS.Compat.*`
- [ ] No `C_ChatInfo`, `C_QuestLog`, `C_GuildInfo`, `C_Timer` called directly outside `Compat`
- [ ] New WoW API globals added to `read_globals` in `.luacheckrc` if needed
- [ ] `.toc` updated if new files were added (in correct load order)

## Architecture

- [ ] Module stays within its defined responsibility boundary (see `architecture.md` Module Map)
- [ ] No circular dependencies between modules
- [ ] UI files contain zero data writes to `GuildOS.db.*` (they call module methods)
- [ ] Data/analysis modules contain zero UI frame creation or widget logic
- [ ] Event handlers and `SetScript` callbacks are named functions or one-liner delegations (Rule 10)

## State & Storage

- [ ] Session-only data is in `GuildOS.State.*` — never as module member vars
- [ ] Persistent data is in `GuildOS.db.*` (via the owning module's method)
- [ ] `GuildOS.db` accessed only after `PLAYER_LOGIN`
- [ ] `GuildOS.db.*` initialized with `or {}` / `or default` guards

## Configuration

- [ ] Settings reads use `GuildOS:GetSetting(key)` — never `GuildOS.db.settings.key` in UI files
- [ ] Settings writes use `GuildOS:SetSetting(key, value)` — never `GuildOS.db.settings.key = v` in UI files

## UI Components

- [ ] Colors always from the `C` table — no hardcoded `r, g, b` hex values
- [ ] Buttons created with `UI:CreateButton()` — not bare Frame + OnClick
- [ ] Text created with `UI:CreateText()` or `UI:CreateHeaderText()` — not bare `CreateFontString`
- [ ] Scroll bar skinned with `UI:SkinScrollBar()` — not manual styling
- [ ] `FauxScrollFrame` rows: ALL visual state reset in every `UpdateRows` call
- [ ] No backdrop logic outside `UI:CreateButton()` / factory functions

## Performance

- [ ] No `C_Timer.After` or `C_Timer.NewTicker` on hot paths (per-event handlers)
- [ ] No `GetGuildRosterInfo` loop inside an `OnUpdate` or rapid-fire event
- [ ] `OnUpdate` handlers removed/nil'd when no longer needed
- [ ] No large table allocation inside `COMBAT_LOG_EVENT_UNFILTERED` handler

## Output & UX

- [ ] No unsolicited chat output
- [ ] Debug output guarded by `GuildOS.Logger.debug`
- [ ] Officer-gated features check `GuildOS:IsOfficer()` before acting

## Correctness

- [ ] All nil-paths handled (missing player key, empty tables, zero-length results)
- [ ] Score values clamped: `math.max(0, math.min(100, score))`
- [ ] `GetGuildRosterInfo` loop starts at 1 and nil-checks every return value
- [ ] Incoming officer-only comm message handlers guard the channel and the officer: `if channel ~= "GUILD" or not GuildOS:IsOfficerByName(sender) then return end` (a new SyncService domain goes in `OFFICER_DOMAINS` or `GUILD_ONLY_DOMAINS`)

## Luacheck

- [ ] `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc` returns `0 warnings / 0 errors`

## Documentation (memory files)

- [ ] `.memory/functions-catalog.md` updated if new public functions were added
- [ ] `.memory/architecture.md` updated if module structure or data flow changed
- [ ] `.memory/decisions.md` updated if a new architectural pattern was introduced
- [ ] `.memory/dev-workflow.md` updated if workflow steps changed

## Addon Integrity

- [ ] Addon loads without Lua errors on `/reload`
- [ ] `/gos` slash command opens the roster frame without errors
- [ ] Affected feature (roster, raids, loot, etc.) displays correctly after `/reload`
- [ ] No taint warnings in combat (avoid modifying Blizzard frames during combat lockdown)
