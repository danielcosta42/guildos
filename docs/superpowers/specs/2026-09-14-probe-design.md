# `/guildos probe`: the Forever beta unknowns in one command

Issue: danielcosta42/guildos#9 · Epic: #4 · Depends on #6 (start-up isolation), #7 (`BRutus.Client`)

Condensed spec + plan + tasks.

## 1. Problem

Most of what decides the Forever port is unknown until the beta opens: the interface number, the project
id, whether Secret Values are enforced, whether addon messages are locked down in instances, what roster
names look like, and which of the APIs and events GuildOS uses exist. Without a probe, a tester types
`/dump` for an hour and retypes the answers into a message.

## 2. Design

### 2.1 Command and storage
- `/guildos probe` (also `/gos probe`) runs `BRutus.Probe:Run()` in `Core/Probe.lua`, loaded right after
  `Core/Commands.lua`. `/gos help` lists it under Diagnostics.
- It writes `GuildOSDB.probe`, a top-level key next to `accountChars`, overwritten on each run. One caveat:
  the v1→v2 migration in `Core/Core.lua` moves every top-level key under the guild key. A player whose saved
  data is still in the pre-v2 flat format, and who runs the probe before their first login in a guild, has
  the probe moved there with everything else, as `accountChars` already would be.
- In combat it refuses with a message and writes nothing.

### 2.2 What it records
| Field | Source |
|---|---|
| `at`, `addonVersion` | `GetServerTime()`, `BRutus.VERSION` |
| `build` | every `GetBuildInfo()` return, in order |
| `projectId` | `WOW_PROJECT_ID` |
| `client` | `BRutus.Client` (#7) |
| `gameMode` | `C_GameRules.GetActiveGameMode()`, when that API exists |
| `secrets` | whether `issecretvalue`, `C_Secrets` and `C_RestrictedActions` exist, and `restricted` from `C_Secrets.HasSecretRestrictions()`: the build's own answer to whether Secret Values are enforced (the API existing proves nothing: 2.5.6 already ships it) |
| `chat` | `C_ChatInfo.InChatMessagingLockdown()` and the instance type from `IsInInstance()` |
| `roster` | the first roster row's name exactly as returned, `GetNormalizedRealmName()` and `GetRealmName()` (the second added by #8); `"not in guild"` otherwise |
| `guildMessage` | every return of one `C_ChatInfo.SendAddonMessage("GuildOSProbe", "probe", "GUILD")`; `"not in guild"` otherwise |
| `apis`, `missingApis` | `name -> true/false` for every entry of the inventory (2.3), and the missing names in order |
| `events`, `missingEvents` | `name -> true/false` for the 39 events the addon registers, and the missing names |

Each call is captured under `pcall`: a missing function reads `{ missing = true }`, a raising one keeps
its error text, and the probe carries on. The clock falls back to `time()` when `GetServerTime` is gone, and
the throwaway event frame and each register and unregister are guarded too. The GUILD message uses its own prefix, `GuildOSProbe`, so no
other GuildOS client parses it. From the roster row only the name is kept, never the notes that come back
with it.

### 2.3 The inventory
From the 0.53.0 API inventory: global functions, `hooksecurefunc` targets, `C_` namespace functions
(plus `C_GuildInfo.SetNote`, which #5 needs), the functions the bundled libraries read, frames, tables and
constants, and the Lua-side globals the review found (`GetBuildInfo`, `debugstack`, `geterrorhandler`,
`securecallfunction`, `tContains`, `STANDARD_TEXT_FONT`); the nine templates, asked through
`C_XMLUtil.GetTemplateInfo` when the client has it (which builds nothing) and otherwise tried with a named
`CreateFrame` under `pcall` and hidden at once; and the four tooltip scripts (`GameTooltip:HasScript`). Dotted names resolve through their namespace table; a
missing namespace makes every function in it missing, and a lookup that raises reads as missing.

Events are checked on one throwaway frame: `RegisterEvent` under `pcall`, then `UnregisterEvent` when it
worked, so nothing stays registered.

### 2.4 Chat summary (one screen)
Build and interface, project id, Anniversary or not, whether Secret Values are enforced, chat lockdown here
and the instance type, missing APIs and events as counts, the first ten missing names of each, and where
the full result was saved.

## 3. Tests
`tools/probe.lua` (luajit), real `Core/Core.lua`, `Core/Compat.lua` and `Core/Probe.lua`, under a stubbed
client missing about half the inventory, half the templates, two of the four tooltip scripts and half the
events (585 checks). It checks:
- the inventory lists each name once and holds 39 events;
- drift: the events the addon's own files register (every TOC file outside `Libs`, both quote styles,
  indexed frames, calls split over lines) are exactly `Probe.EVENTS`; an event name held in a variable is out
  of a static scan's reach;
- every inventory entry, template, tooltip script and event is recorded present or missing exactly as the
  client has it; a whole missing namespace and a raising lookup read as missing;
- templates: without `C_XMLUtil` one hidden frame per template the client has; with it, no template frame at
  all, and a raising lookup reads missing;
- after the probe, no frame it created has an event registered (the stub also raises on unregistering an
  event the client does not know);
- in combat it refuses, says why, and leaves the last result;
- not in a guild: roster and GUILD message say so, and nothing is registered or sent;
- in a guild: the first name and both realm answers are recorded, one message goes to GUILD on the probe prefix, the
  prefix is registered before it (one ordered log), and no member note is stored anywhere in `GuildOSDB`,
  whole or inside a longer string;
- the missing API and event lists are exactly the missing entries, in inventory order, computed from the
  stubbed client rather than read back from the record;
- every build field, the project id, the client, the game mode and a raising lockdown call with its error are
  recorded;
- Secret Values across four clients, so each API's presence is read on its own: `issecretvalue` and `C_Secrets`
  present, `C_RestrictedActions` absent, enforced (true); `C_Secrets` absent while the other two exist
  (missing); the way Anniversary answers, `C_Secrets` and `C_RestrictedActions` present with restrictions off
  (false); and all three present;
- a second run overwrites the first with a new timestamp;
- the summary: the build line exactly; the second line exactly in two states ("no / yes / error / raid", and on
  an Anniversary-like client "yes / no / no / raid"); a probe's own missing APIs shown as "missing", never "nil";
  the missing counts and the first ten missing API and event names from the expected lists; where it was saved;
- never raises on a client without the probe's own APIs (`GetServerTime` — the clock falls back to `time()`,
  then to 0 — `C_GameRules`, `C_ChatInfo`, `GameTooltip`, `IsInInstance`, `GetNormalizedRealmName`, `C_XMLUtil`),
  nor on one that cannot build frames, whose `CreateFrame` returns nothing, or whose namespace raises on lookup.

Mutation check: 66 hand-written mutants of `Core/Probe.lua` (lookups and their guards, combat guard, roster
privacy in every storage shape, prefix, channel and order, event registration and release, both template
paths, tooltip scripts, overwrite, every summary field and list, capture of errors and returns, each Secret
Values field and cross-wiring between them, game mode, instance, realm, clock, frame and namespace guards,
list order and contents, the build fields, the event list); the harness kills all 66.

## 4. Tasks
- [x] `Core/Probe.lua` with the inventory; TOC entry; `/gos probe` verb and help line
- [x] Locale keys for the refusal, the summary and the help line (five locales)
- [x] luacheck read_globals (`C_GameRules`, `C_Secrets`, `C_RestrictedActions`, `GetNormalizedRealmName`)
- [x] `tools/probe.lua`
- [x] Docs: ADR-0015, functions catalog
- [ ] Manual check on Anniversary: run it, `/reload`, read `GuildOSDB.probe` in the SavedVariables file
- [ ] Beta testing note for testers (with #11): what the file holds, including one character name
