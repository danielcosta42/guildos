# Retail: GuildOS on a third client

Issue: danielcosta42/guildos#164 (epic), with #165, #166, #167 and #168; guildos-web#177. Decided with the
maintainer on 2026-10-17, section by section, then run in autopilot up to the in-game review.

## 1. Problem and goal

GuildOS ships for WoW: Forever (and still for TBC Anniversary, which is no longer supported but still
loads). Retail is where most players are. The goal is engagement: GuildOS installable from the CurseForge
Retail flavour and useful there from the first release.

Retail today is Midnight, build 12.1.5.70448, interface **120105** (wago.tools, 2026-10-17).

What retail would get today: the addon knows two clients, Anniversary and "everything else", and the second
is written for Forever. On retail it would load with a level cap of 60, read the realm as a surname, run the
Forever profession catalog, mark its payload `FOREVER`, and — the dangerous one — rekey every member to the
client's own realm at login, merging members of different connected realms into one record.

Decided:

- **Addon first.** The site does not take retail guilds in this epic. It refuses a retail upload, and the
  addon on retail never offers the site at all.
- **All loot goes on retail.** Personal loot only; nothing of the loot suite is kept, Points included.
- **Professions stay, with a Midnight catalog.** Only the current expansion's lines.
- **One build, one TOC** (ADR-0021). Retail's interface is added last, so no half-made release reaches the
  Retail flavour.

## 2. Client detection

`GuildOS.Client` (Core/Compat.lua) gains `isRetail` and `game`:

```lua
local isRetail = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    and interface >= 100000
game = isAnniversary and "ANNIVERSARY" or isRetail and "RETAIL" or "FOREVER"
```

- Two signals, as for Anniversary (ADR-0014). Forever runs the Mainline UI and may answer the Mainline
  project id, but its interface is 16001.
- An unknown client is still Forever, as today. `isAnniversary` keeps its meaning and its name: about 45
  harnesses stub it, and a stub with no `isRetail` reads as Forever, which is what they test.
- Nothing branches on `game` except the payload and diagnostics. Code asks `isRetail`, `isAnniversary` or a
  capability field.

## 3. Identity on retail

On retail a realm is part of who somebody is, as on Anniversary, and a guild spans connected realms.

- **Key:** `"Name-Realm"` with **each member's own realm**. `GetPlayerKey(name, realm)` keeps the caller's
  realm on retail; the Forever rule of issue #95 (ignore it, use the client's) stays Forever-only.
- **Spelling:** the **normalized** realm (`GetNormalizedRealmName()`, no spaces), the way the retail roster and
  every addon-message sender write it. `GetClientRealm()` prefers it on retail. On Anniversary it keeps
  `GetRealmName()` first, so Anniversary keys keep their bytes.
- **Never on retail:** `LocalMemberKey` rebuilding a carried key (passes through, as on Anniversary),
  `LocalizeStoredMemberTables` and `RekeyMembersToThisRealm` at start-up, the alliance bridge hashing the name
  alone, `CompanionImport.PlainName`. Each of those is gated "Forever only" instead of "not Anniversary".
- **My own name:** `has.surnames` is false on retail, whatever `C_PlayerInfo.ShouldDisplaySurname` exists to
  say: there `UnitFullName`'s second slot is the realm.
- ADR-0018 gets an amendment saying all this.

## 4. What is absent on retail

Absent, not disabled (ADR-0014): the module file returns before defining its global, every existing
`if GuildOS.X then` guard reads it as missing, and the player's toggles are never read or written for it.

- **Loot:** LootMaster, LootTracker, LootEquity, Points, SoftResSystem and WishlistSystem return early; the
  `loot`, `dkp` and `wishlist` features carry `retail = false`. Readers elsewhere (member detail, digest,
  dashboard, raid tracker's boss-kill EP, the companion export's loot list) must already guard on the
  module; any that does not gets a guard.
- **The site:** the `web` feature carries `retail = false`; CompanionExport, CompanionImport and Look return
  early; the onboarding step that points to guildos.me is skipped; the Discord core import (ADR-0025) is not
  offered. `Inbox.lua` still loads from the TOC (it is data), and nothing reads it.
- **Already absent outside Anniversary:** consumables, raid HUD, attunements, resistances. Bloodlust and
  Misdirection in Raid Tools stay hidden: they exist on retail but read the combat log, which Midnight closes
  to addons in instances.
- **The registry:** `def.retail == false` hides a feature on retail, in `AllFeatures` and `IsFeatureAllowed`,
  next to the `tbc` check (`UI:IsFeatureAbsent`). `/gos open` of one says "Not available on this client.", not
  officer-only; so do `/gos export loot|equity|standings`, whose usage line lists only what the client has (issue
  #177).
- **Words:** the onboarding's getting-started and privacy steps name no attunements or wishlists on retail; the
  probe lists retail's spec and item-level APIs and names the client it found (issue #177).
- **Recruitment channels:** retail's ChatChannels (12.1.5.70448, every language) are Forever's: Trade and
  LookingForGroup, no GuildRecruitment (issue #177).
- **The payload:** if anything still writes it, `game` is `client.game`, so retail says `RETAIL`.

## 5. Retail content

All of it as `GuildOS.Client` fields or `Compat` functions, never scattered.

- **Level cap 90.** `Client.maxLevel` already feeds recruitment, `/who`, roster filters, analytics and
  milestones.
- **Classes.** `Client.classes`: 13 class files on retail (Death Knight, Demon Hunter, Monk and Evoker added),
  the 9 classic ones elsewhere. It replaces the hard-coded lists in Core/Data.lua, Modules/RaidTools.lua,
  Modules/RecruitBeacon.lua, Modules/RecruitmentSystem.lua, UI/RecruitBeacon.lua, UI/RosterFrame.lua and
  UI/CorePanel.lua. CoreManager's default roles gain the four.
- **Specs.** `Compat.PlayerSpec()` and `Compat.InspectSpec(unit)` read `C_SpecializationInfo` /
  `GetSpecialization` / `GetInspectSpecialization` and `GetSpecializationInfoByID` on retail: the name and the
  role come from the client, localized. A synced spec is shown by its id in the reader's language, not the
  sender's (`SpecChecker:SpecName`, issue #177). SpecChecker's trait-tree column heuristic (Forever) does not run
  on retail. Hero talents are out.
- **Raids.**
  - `Client.raidSizes = {10, 20, 30}`, default 20 (mythic's size).
  - Only Normal, Heroic and Mythic (difficulty 14, 15, 16) are tracked; LFR (17), timewalking (33) and
    everything else is not.
  - Progression labels by difficulty (N/H/M), not by size: on flex the size says nothing. The locale's size word
    goes with the 25 ("N/H/M", never "N/H/M jogadores", issue #177).
  - A session keeps its difficulty, shows it on the raids panel ("Voidspire (H)"), sends it in the raid sync, and a
    raid's Normal and Heroic the same night stay two sessions: back in on another difficulty during the grace
    starts a new session, and the merge never joins two difficulties (issue #177). A session relayed by an
    officer on an older addon has no difficulty and shows apart until that officer updates.
  - An old raid run on N/H/M counts as attendance. Accepted for now.
  - `ENCOUNTER_START/END` check `encounterName` with `Compat.IsSecret` before concatenating, on every client; the
    session's difficulty name too (issue #177).
- **Gear.**
  - Item level is the effective one (`C_Item.GetDetailedItemLevelInfo`), not the base `GetItemInfo` gives.
  - The average is `GetAverageItemLevel()` for me and `C_PaperDollInfo.GetInspectItemLevel(unit)` for an
    inspect.
  - Gems are read from the link's four gem fields.
  - Enchant slots per client: Midnight's are head, shoulder, chest, legs (spellthread, armor kit), feet, both
    rings and both weapons (cloak and wrist enchants are gone). An off hand counts only when it is a weapon: a
    shield or a frill takes no enchant (issue #177). Whether a spellthread or an armor kit fills the link's
    enchant field is read in game.
  - Item-level colour bands are TBC's; on retail the colour is neutral, since bands go stale every season.
- **Professions.**
  - `tools/prof_catalog.py --retail <build>` writes `Data/ProfCatalogRetail.lua`, gated retail-only, with only
    the Midnight child skill lines.
  - `Data/ProfCatalogForever.lua` becomes Forever-only (today it loads anywhere but Anniversary).
  - The rest of ADR-0022 holds: `IsPlayerSpell` per recipe, hash-summarized sync, members without the addon
    from the Communities roster. If `IsPlayerSpell` or `GetProfessionInfo` answer differently on retail, the
    open window's `extra` still catches recipes; the in-game review checks it.
  - Out: profession specializations and craft quality.

## 6. Packaging and store

- `GuildOS.toc`: `## Interface: 20506, 16001, 120105`, and Notes name retail.
- `beta.yml` stops requiring the line to end at 16001; it still refuses a TOC that lost 16001.
  `tools/beta-workflow.py` accepts the third interface.
- `publish.yml` does not change: the packager reads the flavours from the interface line (ADR-0021). After the
  release, the publish log's `Game version:` line is the only proof retail was tagged.
- `CURSEFORGE.md` and `README.md` name retail, with what it has and what it does not (no loot suite, no
  guildos.me yet).
- ADR-0026 "Retail, the third client"; amendments to ADR-0014, ADR-0018, ADR-0021 and ADR-0022.

## 7. guildos-web

`payloadGame` stops reading every value that is not `FOREVER` as `ANNIVERSARY`. An absent `game` is still
Anniversary (an addon before v6); `RETAIL` or any other value is refused at the door like a payload from the
other game. Tested; recorded in specs/036.

## 8. Testing

- LuaJIT harnesses, one per rule: detection of the three clients; retail keys with the member's realm and the
  start-up rekey not running; the feature matrix (retail hides loot and the site, Forever unchanged); level,
  sizes and classes; specs; raid difficulty filter; item level and enchant slots; the retail catalog.
- Every existing harness keeps passing unchanged.
- In game, on the maintainer's retail characters (Azralon), at the end: the review script lists what to
  check, `/guildos probe` included.

## 9. Delivery

Four addon PRs, in order, stacked, none merged before the in-game review:

1. #165 — detection, identity, what is absent.
2. #166 — content.
3. #167 — the Midnight profession catalog.
4. #168 — TOC, store, page.

And guildos-web#177 on its own.

## 10. Out of scope

- guildos.me for retail guilds (its own epic).
- A loot suite for personal loot (trade-based council, loot history from `ENCOUNTER_LOOT_RECEIVED`).
- Mythic+, delves, hero talents, profession specializations, craft quality.
- Raid Tools cooldowns that need the combat log.
