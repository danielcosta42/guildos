# Start-up isolation: one module that fails no longer takes the addon down

Issue: danielcosta42/guildos#6 · Epic: #4 (ready to test on the WoW: Forever beta from day one)

Condensed spec + plan + tasks: the change is small and every other Forever slice stands on it.

## 1. Problem

`BRutus:InitModules` called about 50 module `Initialize()` functions in a row with no error
isolation. On a client that lacks one API a module touches while it starts, that module raises,
and no module after it in the list ever starts. The addon is dead and the player sees one Lua
error that says nothing about why.

Two more ways to raise at start-up had the same effect:

- `frame:RegisterEvent("X")` raises when the client does not know event `X` (`CRAFT_SHOW`,
  `RAID_ROSTER_UPDATE` and other TBC-era events are candidates on a new client).
- `tooltip:HookScript("OnTooltipSetItem", fn)` raises when the tooltip has no such script.

`BRutus:SafeCall` and the `/guildos errors` ring already existed; start-up did not use them.

## 2. Goal and acceptance

From the issue, unchanged:

- One module raising in `Initialize()` → every other module still starts; the failure (module
  name + error) is recorded and listed by `/guildos errors`.
- A module that failed marks the window it backs, which then refuses to open with a message
  instead of erroring while it builds.
- Registering an event the client does not know, or hooking a tooltip script the frame lacks,
  does not raise; the miss is recorded and the owning feature keeps working.
- One chat line at login points to `/guildos errors` only when something failed.
- Offline harness proves it; Anniversary behaves exactly as before.

## 3. Design

### 3.1 The start list

`InitModules` becomes a loop over `MODULE_START`, a list that keeps today's order exactly, and
`OFFICER_START`, run after the same 5-second delay for officers. An entry names the module and,
optionally:

| Field | Meaning |
|---|---|
| `feature` | the Settings toggle that can switch the module off (the old `modEnabled(key)`) |
| `ui` | the window the module backs (`raids`, `loot`, `dkp`, `wishlist`, `recipes`, `alliance`, `management`, `trials`) |
| `method` | start function other than `Initialize` (`Recruitment:InitParticipation`) |
| `after` | a second function run only when the first succeeded (`TrialTracker:CheckExpired`) |

A list rather than ~150 lines of `if BRutus.X then BRutus.X:Initialize() end` because the next
slice (#7, client detection) needs one place to mark TBC-only modules.

Non-module steps that can also raise on a new client — theme, util tests, minimap button, chat
invite hook, guild frame hook — run through the same isolation, named. The roster request goes
through `Compat.GuildRoster` instead of `C_GuildInfo.GuildRoster` directly, since it sits on the
same path.

### 3.2 Recording

- `BRutus:RunStartup(name, entry, fn, ...)` — `xpcall` with a stack-keeping handler, and on failure writes
  `State.startup.failed[name]`, marks `State.startup.failedFeatures[entry.feature/ui] = name`,
  and pushes `"<name>: <error>"` into the error ring.
- `BRutus:RecordError(msg)` — the ring push, extracted from `SafeCall` so both share it.
- `BRutus:RecordMissing(what)` — once per session per item, into `State.missing` and the ring.
- `BRutus:FeatureStartFailed(id)` — read by `UI:IsFeatureAllowed` (tab hidden, hub gate) and
  `UI:OpenWindow` (prints "`<label>` could not start on this client…").
- `BRutus:ReportStartup()` — after the officer modules, one localized line with the number of
  failures plus misses, or nothing.
- `BRutus:ListStartupProblems()` — every failure and miss, sorted. `/guildos errors` prints these
  first: the error ring is capped at 50 and shared with runtime errors, so it can lose them.
- Failures are recorded as `Module` for `Initialize` and `Module:Method` otherwise, so two stages
  of one module (Recruitment's member and officer stages, TrialTracker's `CheckExpired`) never
  overwrite each other.
- `xpcall` keeps the stack (`State.startup.stacks[name]`); in debug mode the whole error also goes
  to `geterrorhandler()`, the way an unguarded start-up always reached BugSack.
- `UI:OpenWindow` builds a panel through `SafeCall`. A panel that raises while building stays
  refused until `/reload` instead of opening empty, which also covers sub-panels whose module has no
  `ui` mapping (Calendar, RaiderRoster, RecruitBeacon...).

### 3.3 Compat helpers

- `Compat.RegisterEvent(frame, event)` — `pcall(frame.RegisterEvent, frame, event)`; records
  `event X` when it fails. Every `RegisterEvent` in `Modules/` and `UI/` goes through it, with
  three deliberate exceptions:
  - `Core/Core.lua`'s bootstrap frame (loads before `Compat.lua`; universal events only);
  - `Modules/ChehulNet.lua` (a file shared verbatim between Chehul addons; must not depend on
    `BRutus`);
  - `Modules/CompanionExport.lua` and `Modules/CompanionImport.lua` (file-scope
    `PLAYER_LOGOUT`/`PLAYER_LOGIN`, universal, and loaded by `tools/` harnesses that do not stub
    `Compat`).
- `Compat.HookTooltip(tooltip, script, fn)` — hooks only when `tooltip:HasScript(script)`; a nil
  tooltip is skipped silently, a missing script is recorded. Used by BanList, RecipeTracker,
  WishlistSystem and SoftResSystem.

## 4. Out of scope

- A `TooltipDataProcessor` path for clients that dropped `OnTooltipSet*` — added when a client
  needs it (the probe in #9 tells us).
- Errors raised while a file loads (TOC time). WoW keeps loading the next file; a module that
  half-loaded is caught by the start list when its `Initialize` is missing or raises.
- Which modules are TBC-only on a new client (#7).

## 5. Test strategy

- `tools/startup-isolation.lua` (luajit, stubbed API, real `Core.lua` + `Compat.lua`):
  failures in the middle of the list, officer modules after failures, failure → window mapping,
  one login line, unknown event and tooltip script handling, clean start is silent, Settings
  toggles and officer rank still decide what starts.
- The existing harnesses (`companion-payload`, `roster-import`, `attendance-parity`) still run.
- `luacheck` clean.
- Manual, on Anniversary (pending — needs the game): `/reload` with no errors and no login
  line; `/gos selftest` green; roster, raids and recipes windows open.

## 6. Tasks

- [x] Start list + `RunStartup`/`StartModule`/`FeatureStartFailed`/`ReportStartup` in `Core.lua`
- [x] `RecordError` extracted from `SafeCall`; `RecordMissing`
- [x] `Compat.RegisterEvent` + call sites; `Compat.HookTooltip` + call sites
- [x] `UI:IsFeatureAllowed` and `UI:OpenWindow` refuse a failed feature
- [x] Locale keys (enUS master + ptBR, esES, deDE, frFR)
- [x] `tools/startup-isolation.lua`
- [x] ADR-0012, functions catalog
- [ ] Manual check on Anniversary
