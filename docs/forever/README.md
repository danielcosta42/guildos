# WoW: Forever, read from the client before the beta opened

Build `wow_classic_beta` **1.60.1.69893**, installed 2026-09-17. Epic danielcosta42/guildos#4 asked the day-one
questions in game (`/guildos probe`). Most of them can be answered from the build itself, without logging in:

- **The API documentation.** `Blizzard_APIDocumentationGenerated`, as the client ships it, lists every documented
  function, event and enum, with its `Secret*` fields.
- **Blizzard's own UI code and TOCs.** They show which files load for which game type, and which old globals
  survive as compat shims.
- **The executables.** A legacy C global is registered by name; one that is in Anniversary's `WowClassic.exe` and
  in neither Forever's `WowB.exe` nor its Lua is gone.

The files come from wago.tools' CASC endpoint, pinned to the build. `tools/forever-scan/` does all of it again for
a new build (see the end of this page).

## What Forever is, to an addon

- **Its game type is `camelot`**, the "Project Camelot" name. Blizzard's TOCs filter on it
  (`[AllowLoadGameType camelot]`, `## AllowLoadGameType: standard, camelot`).
- **It runs the retail interface.** It loads the cooldown viewer, the damage meter, Edit Mode and retail character
  creation. `[Family]` resolves to the Mainline folders, with Forever-only overrides under `[Game]`. Those override
  files have no names in the community listfile yet, so they cannot be read.
- **It is neither `classic` nor `mainline`.** TOCs name it separately from both
  (`[AllowLoadGameType mainline, camelot]`, `classic, camelot`). So:
  - **Classic shims do not load.** Among the functions that exist only in `Blizzard_Deprecated/Classic/*`,
    `UnitBuff` and `GetTalentInfo` are the ones GuildOS calls; only `Core/Compat.lua` calls them, and it has the
    namespaced paths.
  - **The talent shims do not load either.** `Blizzard_DeprecatedSpecialization` declares
    `## AllowLoadGameType: classic, standard`.
  - **The rest of the compat addons carry no filter and should load:** chat, guild script, combat log,
    Battle.net, raid warning. That keeps `SendChatMessage`, `ChatFrame_AddMessageEventFilter`, `GuildSetMOTD`,
    `GetGuildRosterMOTD` and `CombatLogGetCurrentEventInfo`.
- **UI experience presets.** `C_GameRules` has `SelectClassicExperiencePreset` and `SelectModernExperiencePreset`:
  the player can choose a classic or a modern UI.
- **No detection API.** There is no `C_GameRules.IsCamelot`, and `WOW_PROJECT_ID` has no Forever constant in the
  UI code that could be read. `BRutus.Client` keeps reading the interface number.
- **Interface: 16001**, by the `GetBuildInfo` rule for 1.60.1 (`%d%02d%02d`). No Blizzard TOC carries an
  `## Interface` line to confirm it; `beta.yml` stamps `16000, 16001`.

## Secret Values: the retail system, in full

- **The scale.** 4,025 documented entries carry `Secret*` fields on Forever, against 3 on Anniversary.
- **Chat lines and senders.** `CHAT_MSG_GUILD`, `OFFICER`, `WHISPER`, `SYSTEM`, `CHANNEL` and `SKILL` are
  `SecretInChatMessagingLockdown`: the line and the sender arrive secret. The channel name is `NeverSecret`.
- **Addon messages.**
  - `CHAT_MSG_ADDON` carries no secret flag.
  - `C_ChatInfo.SendAddonMessage` is `SecretArguments = NotAllowed`: a secret argument raises.
  - `Enum.SendAddonMessageResult` is retail's list; 11 is `AddOnMessageLockdown`, which the compat core already
    falls back to.
- **Units.** `UnitName`, `UnitClass`, `UnitGUID`, `UnitRace`, `UnitSex`, `UnitIsGroupLeader` and
  `UnitIsGroupAssistant` return secrets when the unit's identity is restricted. Blizzard's own unit frames ask
  `C_Secrets.ShouldUnitIdentityBeSecret` for any unit, so party and raid members are not exempt.
- **Stats.** `UnitStat`, `UnitHealthMax` and `UnitPowerMax` are secret while stats are restricted.
- **Combat log.** `COMBAT_LOG_EVENT_UNFILTERED` has `HasRestrictions`. GuildOS registers it only on Anniversary
  (RaidHUD).
- **Chat filters** are safe: `ChatFrameFilters.lua` calls an addon's filter only when `canaccessvalue` says the
  values can be read.

Addon code may pass a secret along — `FontString:SetText` takes one — but matching, comparing, concatenating,
indexing or doing arithmetic with it raises.

### What this pass changed in GuildOS

- **`Compat.IsSecret(...)`:** true when any argument is secret; always false on a client without the system.
- **`Compat.UnitIdentity(unit)`:** name, realm and class file, or nothing when the unit's identity is secret.
- **Chat handlers:** each one that reads a payload returns first when it is secret.
  - `Mentions`, `NoteCommand`, `RosterLog`, `RecruitScanner`, `BanList`;
  - `Recruitment`'s welcome and auto-invite;
  - `LootMaster`'s roll capture (a roll made while chat is locked down is missed, not misread);
  - `AllianceChat` on its channel.
- **Group-unit loops skip a member they cannot read:** `RaidTracker`, `Points`, `LootMaster` (seven places plus
  the trade window), `PugInspector`, `SoftRes`, `RaidTools`, `CompanionImport`, `SpecChecker` and
  `ConsumableChecker` (Anniversary only today).
- **Own stats:** `DataCollector:CollectStats` leaves a restricted stat out instead of serialising it.
- **The addon-message path** records a secret argument as `"secret"` and never sends it.
- **`ChehulNet` (`DetectLayer`)** skips a secret GUID. The file is shared verbatim with the other Chehul addons:
  copy the change there.
- **Two small ones:** `RecipeTracker:ScanCraft` checks `GetCraftInfo` too, and `ChatTweaks` checks
  `ChatFrame_AddMessageEventFilter` before registering.
- **The test.** `tools/secret-values.lua` (luajit, 48 checks) loads the real Core, Compat, Utils and eleven modules
  under a stubbed client, with a secret that raises on every use. Each handler also gets a readable line, so one that
  returns unconditionally fails too.
  - **Mutation check:** 23 of 24 hand mutants are killed.
  - **The survivor is the trade window's guard.** Lua 5.1 never calls `__eq` between a table and a string, so the
    stub cannot make that comparison raise the way the client does.

## Gone on Forever

In Anniversary's executable, and in neither Forever's executable nor its Lua:

| Function | What it means for GuildOS |
|---|---|
| `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillLine`, `GetTradeSkillItemLink`, `GetTradeSkillRecipeLink` | Classic professions are gone; Forever has retail's `C_TradeSkillUI`. `RecipeTracker` already reads them guarded, so it finds no recipes rather than raising. Reading recipes through `C_TradeSkillUI` is the next piece of work, best designed with the beta open. |
| `GetCraftInfo`, `GetNumCrafts`, `GetCraftItemLink`, `GetCraftDisplaySkillLine`, `CRAFT_SHOW` | No Craft frame at all. |
| `GetNumTalentTabs`, `GetNumTalents` | No talent tabs. Forever uses `C_ClassTalents` and `C_Traits` (17 trait trees), and `ChrSpecialization` has one row per class, named after the class. `SpecChecker` degrades to "spec absent" today. A spec read from trait trees needs the beta's real data. |

Nothing the probe inventory lists as documented on Anniversary is missing from Forever's documentation.

## The game data (wago.tools DB2 exports for this build)

- **No new raids.** Six new instances, all five-player dungeons:
  - **City of Dalaran:** 9 bosses;
  - **Ruins of Lordaeron:** 7;
  - **Excavation Site: Wetlands:** 4;
  - **The Hall of Thanes:** 4;
  - **Half-Pint Tavern:** 2;
  - **Manor Mistmantle:** no bosses listed yet.
- **Sunken Temple** gains a 10-player and a 20-player version (difficulties 184, 201 and 215), with new encounter
  ids for its bosses.
- **Other new maps:** Dalaran City, Zephras Isle, Hyjal Crater (arena), Battle for Gilneas and Darkspear Islands
  (battlegrounds), and a winter Warsong Gulch.
- **6,715 item ids** that Classic Era does not have. The same ten classes.
- **The beta:** 2026-09-17 to 2026-10-21, level cap 30, no raids. Launch 2026-11-04; raids 2026-12-09.

## Still for the game to answer

- **Chat lockdown.** When it starts on Forever: combat, instances, encounters? This decides how often roll capture
  and mention alerts go quiet.
- **Group members' identity.** Whether it is restricted outside instances.
- **`GetRaidRosterInfo`.** Whether its names come back secret too. It is not in the documentation's secret list,
  and RaidTools, PugInspector, LootMaster's master looter, CompanionImport and RaidHUD read names from it.
- **The interface number.** `GetBuildInfo()` on the client itself: is it really 16001?
- **The TOC suffix.** Whether Forever reads a `_Camelot.toc`. `GuildOS.toc` loads either way.
- **Recipes and specs.** The shapes of `C_TradeSkillUI` and `C_ClassTalents` / `C_Traits` for a real character,
  before recipes and specs are read from them.

`/guildos probe` records most of these in one run.

## Running the scan on a new build

```
python tools/forever-scan/scan.py <forever-build> <anniversary-build> <work-dir> [<WowB.exe> <WowClassic.exe>]
python tools/forever-scan/scan.py 1.60.1.69893 2.5.6.69795 %TEMP%/forever-scan "E:/World of Warcraft/_classic_beta_/WowB.exe" "E:/World of Warcraft/_anniversary_/WowClassic.exe"
```

It needs Python 3, `luajit` on the PATH and network access to wago.tools, and writes `<work-dir>/report.txt`:

- documented functions removed, new, flagged or present;
- undocumented globals that are gone, defined in Forever's Lua, or unknown.

The first run downloads about 3,500 files; later runs reuse them.
