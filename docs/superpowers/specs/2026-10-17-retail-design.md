# Retail: GuildOS on a third client

Issue: danielcosta42/guildos#164 (epic), with #165, #166, #167 and #168; guildos-web#177. Decided with the
maintainer on 2026-10-17, section by section, then run in autopilot up to the in-game review. The content an
audit found still missing on retail followed in #184 (2026-10-21), marked in place below.

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
  addon on retail never offers the site at all. *Since issue #182 (guildos-web specs/056) it does: the site
  leg is on, see §11.*
- **All loot goes on retail.** Personal loot only; nothing of the loot suite is kept, Points included. *Since
  issue #183 the history comes back, read from personal loot: see §12. Nothing that hands loot out does.*
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
  say: there `UnitFullName`'s second slot is the realm. ChehulNet, shipped identical in other addons and unable
  to ask GuildOS, reads the same two signals itself (v9, issue #184).
- **Namesakes (issue #184):** two members of one guild on two connected realms can share a name. The ban list
  files a ban under the whole key, lower case; a name without a realm is this realm's, never a guess at a
  namesake elsewhere, so every caller passes the whole name it has (the whisper's author, the invite popup's
  name, /who's fullName). A ban filed under the name alone before still holds on every realm. The ban list's
  x lifts its row by the row's key; `/gos unban Name-Realm` lifts that key, `/gos unban Name` the old ban by
  name first, then this realm's. An officer still on an older addon lifts the name alone from any row (see
  ADR-0026). The group inspector, the rank lookup (`GuildManager:GetRosterIndex`), the roster log and the
  raid's guild check compare whole keys. Forever and Anniversary keep the name alone.
- ADR-0018 gets an amendment saying all this.

## 4. What is absent on retail

Absent, not disabled (ADR-0014): the module file returns before defining its global, every existing
`if GuildOS.X then` guard reads it as missing, and the player's toggles are never read or written for it.

- **Loot:** LootMaster, LootTracker, LootEquity, Points, SoftResSystem and WishlistSystem return early; the
  `loot`, `dkp` and `wishlist` features carry `retail = false`. Readers elsewhere (member detail, digest,
  dashboard, raid tracker's boss-kill EP, the companion export's loot list) must already guard on the
  module; any that does not gets a guard. *Since issue #183 (§12) LootTracker and LootEquity load on retail, and
  the `loot` tab and the `lootTracker` feature with them; since issue #185 (§13) Points and Wishlist too, with a loot
  council by trade. LootMaster and SoftRes stay absent.*
- **The site:** the `web` feature carries `retail = false`; CompanionExport, CompanionImport and Look return
  early; the onboarding step that points to guildos.me is skipped; the Discord core import (ADR-0025) is not
  offered. `Inbox.lua` still loads from the TOC (it is data), and nothing reads it. *Superseded by issue #182
  (§11): only Look stays absent.*
- **Already absent outside Anniversary:** consumables, raid HUD, attunements. What was left of them follows the
  module, on Forever too (issue #184): a trial's attunement progress, the linked characters' attunement note,
  the attunement and consumables export columns, the "no consumables" penalty, the readiness target and its
  attunement and consumables columns, and `/gos attune dumpquests`.
- **Resistances:** the module is absent on retail, which has no resistance gear, and so are the resistance
  scan, its sync and `/gos resscan` (issue #184). Forever keeps them.
- **Raid Tools' cooldowns** on retail are listed by class presence, who in the group can cast one, never
  whether it is ready, which would read the combat log Midnight closes to addons in instances: Bloodlust
  (Shaman, Mage, Hunter, Evoker), Rebirth, Innervate, Power Infusion and Soulstone. Misdirection is not on
  retail's list; TBC's Bloodlust/Heroism and Misdirection entries stay TBC's.
- **The registry:** `def.retail == false` hides a feature on retail, in `AllFeatures` and `IsFeatureAllowed`,
  next to the `tbc` check (`UI:IsFeatureAbsent`). `/gos open` of one says "Not available on this client.", not
  officer-only; so do `/gos export loot|equity|standings`, whose usage line lists only what the client has (issue
  #177).
- **Words:** the onboarding's getting-started and privacy steps name no attunements or wishlists on retail; the
  probe lists retail's spec and item-level APIs and names the client it found (issue #177). *Since issue #185 the
  privacy step and About name the wishlist, and the officer step the Loot settings (free roll, Wishlist or DKP).*
- **Recruitment channels:** retail's ChatChannels (12.1.5.70448, every language) are Forever's: Trade and
  LookingForGroup, no GuildRecruitment (issue #177). Only retail has an Italian client: Commercio and
  CercaGruppo; Forever's (1.60.1.70450, 70532) and Anniversary's (2.5.6.70006) itIT rows are English
  (issue #184).
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
  - My spec change goes out at once (`PLAYER_SPECIALIZATION_CHANGED`, a burst sent once), not on the next
    five-minute tick (issue #184).
  - A scanned spec sets the role a member starts in on a core: tank, healer, and melee or ranged by the spec
    (ChrSpecialization's melee flag, 12.1.5.70448: Survival is melee; Augmentation and Devourer ranged),
    when the class can play it; no spec, or another client, the class's own (issue #184).
  - The alliance roster sends the spec's id beside its name, and an allied reader names it in their own
    language (issue #184).
- **Core composition.** A core's raid-buff coverage on retail is Raid Tools' Midnight list, one table for
  both screens, named by the client from the spell (issue #184). Forever lists none; Anniversary TBC's.
- **The member sheet** on retail shows the spec's primary stat, stamina and the four ratings in percent:
  crit (the best of melee, ranged and the weakest spell school, as the character sheet takes it), haste,
  mastery and versatility; no spirit, no mana (issue #184).
- **Raids.**
  - `Client.raidSizes = {10, 20, 30}`, default 20 (mythic's size).
  - Only Normal, Heroic and Mythic (difficulty 14, 15, 16) are tracked; LFR (17), timewalking (33) and
    everything else is not.
  - Progression labels by difficulty (N/H/M), not by size: on flex the size says nothing. The locale's size word
    goes with the 25 ("N/H/M", never "N/H/M jogadores", issue #177).
  - A session keeps its difficulty, shows it on the raids panel ("Voidspire (H)"), sends it in the raid sync, and a
    raid's Normal and Heroic the same night stay two sessions: back in on another difficulty during the grace
    starts a new session, keeping the core an officer picked, and the merge never joins two difficulties (issue
    #177). A session relayed by an
    officer on an older addon has no difficulty and shows apart until that officer updates. *Since issue #182 the
    attendance lockout carries the difficulty too, and a night with none does not count (§11).*
  - An old raid run on N/H/M counts as attendance. Accepted for now.
  - `ENCOUNTER_START/END` check `encounterName` with `Compat.IsSecret` before concatenating, on every client; the
    session's difficulty name too (issue #177).
- **Gear.**
  - Item level is the effective one (`C_Item.GetDetailedItemLevelInfo`), not the base `GetItemInfo` gives.
  - The average is `GetAverageItemLevel()` for me and `C_PaperDollInfo.GetInspectItemLevel(unit)` for an
    inspect: a group scan brings the item level of a guildmate without the addon, never over a broadcast of
    their own at least as new (issue #184).
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

- guildos.me for retail guilds (its own epic: guildos-web#191, addon #182, §11).
- Soft reserves for retail raids (softres.it runs Classic raids only). The loot history from
  `ENCOUNTER_LOOT_RECEIVED` is in since issue #183 (§12); points, the wishlist and a council by trade since issue #185
  (§13).
- Mythic+, delves, hero talents, profession specializations, craft quality.
- Raid Tools cooldowns that need the combat log.

## 11. The site leg (issue #182)

guildos.me takes retail guilds (guildos-web#191, specs/056; off there until its `RETAIL=1`). In the addon:

- **Present on retail:** CompanionExport, CompanionImport, the `web` feature, `/gos web`, `/gos roster`, the site
  link, the inbox (the planned roster, the site's raids on the calendar, the Discord's cores). Look stays absent:
  the site draws a retail character from the Armory. `RETAIL_ABSENT` keeps only the loot verbs.
- **Payload v10.** `game = "RETAIL"`; `region` from `GetCurrentRegion()` (1 `us`, 2 `kr`, 3 `eu`, 4 `tw`; any other
  answer publishes nothing and the Web panel and `/gos web` say why); `guildKey = "<Guild>-<HomeRealm>"` and
  `realm` from the guild's home realm, normalized (`GuildOS:GuildRealm`, the database key's rule), never the
  exporter's; every person `Name-Realm` with their own realm; `sessions[].difficulty` (14, 15, 16); `members[].spec`
  as stored, `{ tree, specID, role }`. Forever and Anniversary send exactly v9's bytes, with `v = 10`.
- **Enchants:** the summary asks `GearAudit:NeedsEnchant`, as the member sheet does.
- **Raids:** `RaidTracker.RAID_KEYS` gains `midnight-voidspire` (2912), `midnight-dreamrift` (2939),
  `midnight-queldanas` (2913) and `midnight-abyss` (3004).
- **GOSROST v3:** the raid carries `difficulty`; `RaidFor` needs it to match the night's when both have one. A
  member is invited and grouped by its `Name-Realm` key (the site sends no region), cut to the plain name only on
  this character's realm. Who is already in the group is known by name and realm. A name the site never confirmed
  is rescued from the guild roster only when one connected realm has it.
- **GOSCORE:** a package is this guild's when its `realm` is the guild's home realm, normalized.
- **Names:** what the addon keeps from the site is the `Name-Realm` key, the same on every officer's client, so the
  calendar's list of answers matches across connected realms; it is cut to the plain name only to invite. A raid
  member the client keeps secret is passed over by the groups. The JSON decoder is Core/Utils.lua's: it lived in
  SoftRes, absent on retail, and every roster from the site read as damaged there.
- **Attendance as the site counts it:** the lockout is core, instance, week and difficulty
  (`RaidTracker:LockoutKey`, the site's `lockoutKey`): Normal and Heroic in one week are two lockouts. A retail night
  counts by its difficulty; one with none (an addon before #177) does not. `tools/attendance-parity.lua` with
  `RETAIL` prints the site's retail fixture (the TBC nights at N/H/M, Karazhan at none) and checks that its answers
  are TBC's, then Normal and Heroic in one week, an old raid, Raid Finder and a night with no difficulty.
- **Tests:** `tools/retail-site.lua` (the modules loaded in TOC order, SoftRes absent); `tools/retail-absent.lua`,
  `tools/client-detection.lua`, `tools/retail-raids.lua` and `tools/attendance-parity.lua` follow.

## 12. Personal loot (issue #183)

Retail loot is personal: each player gets their own item and nobody hands anything out. What comes back is the
history (guildos-web specs/056, "Addon → Loot pessoal").

- **Recorded:** `LootTracker:OnEncounterLoot`, from `ENCOUNTER_LOOT_RECEIVED` (encounterID, itemID, itemLink,
  quantity, playerName, className), registered on retail only. Every guildmate's item, not only mine, into the same
  `lootHistory` an ML award goes to and in its shape: `itemLink`, `itemName`, `quality`, `player` and `playerKey`
  (both the whole `Name-Realm` through `GetPlayerKey`: a name with no realm is on this character's realm, a realm is
  normalized; a bare `player` would name another person to an alt on a connected realm, and `/gos equity` groups by
  it), `count`, `timestamp`, `raid` (the session's name), `instanceID`, plus `itemId` and `encounterID`; no `fromML`.
- **Only the guild:** the player has to be on the guild roster by that key (`Compat.FindGuildRosterIndex`, then
  `KeyOfRosterName`). A guildmate on a connected realm counts; a pickup raid's strangers and a namesake from another
  realm do not. On Forever a record needs this guild's officer's award; here any member's client would otherwise send
  strangers' items to the guild's loot page, `/gos equity` and the digest.
- **Only in a tracked raid session** whose instance and difficulty this client is standing in (Normal, Heroic,
  Mythic; §5), in its grace too when that is where the client stands. A dungeon run in the meantime, Raid Finder (of
  the same raid too, which has the same instance id): nothing. The Loot Tracker switched off in Settings: nothing.
- **The grace on retail:** in another instance, or in the session's raid on another difficulty, the session takes no
  snapshot, opens or closes no boss and records no loot (`RaidTracker:ElsewhereInGrace`): Raid Finder's group is not
  the guild's Heroic. A grace that runs out there, or another raid begun inside it, ends the session without its
  `session_end` snapshot (`EndSession(away)`), so that group never joins its players nor makes every guildmate leave
  late. The open world is the run-back and keeps its snapshots; Forever and Anniversary are as before.
- **Secret values:** any field the client keeps secret skips the whole item, never half a record.
- **What is kept:** Rare and up, the loot master's default threshold. An item not cached yet is read from its link
  (retail colours it `|cnIQn:` and names it in brackets), else taken as epic, as an ML award is.
- **Re-fires:** the same boss, item and player within five minutes is one record, checked against the history
  itself.
- **Back on retail:** the `lootTracker` feature, the Loot tab (History and Equity, Export; no Soft Res button and no
  loot-master line), the roster's LOOT column, the dashboard's loot card, the digest's loot line, the member sheet's
  loot section, LootEquity and `/gos equity`, the `loot` and `equity` exports, and the loot list in the payload, in
  today's row format (`playerKey`, `player`, `itemId`, `itemName`, `quality`, `timestamp`, `raid`).
- **Still absent:** LootMaster, Points, SoftRes, Wishlist and the Settings loot category; their verbs say "Not
  available on this client." (`RETAIL_ABSENT`).
- **Forever and Anniversary:** the event is never registered and `OnEncounterLoot` returns at once; the ML path is
  unchanged.
- **Read in game:** whether Midnight fires the event for every player's loot (the boss banner does show it) and
  whether any field arrives secret. A guildmate the roster has not loaded yet is not recorded.
- **Tests:** `tools/retail-loot.lua`; `tools/retail-site.lua` (the row in the payload), `tools/retail-absent.lua`,
  `tools/client-detection.lua`, `tools/window-shell.lua` and `tools/probe.lua` follow.

## 13. Loot distribution (issue #185)

Retail has no Master Loot: every item is personal, and one that is still tradeable can be handed, for a while, to
someone who was eligible for it. The guild's distribution tools come back built on that.

- **Points** (DKP, EPGP, council modes) load: boss-kill EP, manual awards, decay, standings, the `standings` export and
  the DKP tab, as on Forever; an entry is named by the whole `Name-Realm`. An item is charged only when an award by trade
  is recorded (below), by the officer who awarded it, with the guild's cost per item.
- **The loot system** is the guild's: an officer's choice goes to every member (`guildcfg`/`lootsys`, stamped, newest
  wins, re-sent with the officer threshold). Retail offers the free roll (the "rolls" key), Wishlist, DKP and
  External / Off; TMB is Classic only. External / Off switches the council off. The Settings Loot category is back with
  the loot system and the points; the loot master's sections stay out.
- **The wishlist** loads. Its items come from the Encounter Journal at run time for Midnight's raids, by journal
  instance: 1307 The Voidspire, 1314 The Dreamrift, 1308 March on Quel'Danas, 1320 The Venomous Abyss (every class's
  loot; never read while the journal is open; its filters and instance put back; read again on
  `EJ_LOOT_DATA_RECIEVED` until whole). An item not cached yet is found and wished for by the journal's name. A list is
  kept under its sender's whole key, never the name it carries. On retail an item is delivered when the history has it
  as mine: personal loot, or an award by trade.
- **The loot council by trade:**
  - *Offer.* Whoever received a tradeable item offers it: `/gos offer [item]`, the council window's Offer button by each
    tradeable item in their bags, or the Offer button on their own recent row of the loot history. Settings' quick
    access ("Loot Council") opens the window for every member. Needs a raid; refused when the item is not in the bags,
    is past its trade window or is already offered.
  - *Trade time.* Read on the holder's client only. The client has no function for it: `C_Container`'s `isBound`, then
    the `TradeTimeRemaining` line (type 36) of `C_TooltipInfo.GetBagItem`, its duration read with the client's own
    duration strings. When it cannot be read the offer still goes out, runs at most two hours, and shows the time as
    unknown.
  - *Wire.* Addon messages on `GuildOSTC` over RAID: `O|id|free|secs|link`, `A|id|choice|link`, `W|id|winner`, `X|id`,
    `D|id|winner`. Only a guildmate's message is read (a pickup raid's strangers have no say); a secret one is never
    touched; Midnight holds what is sent during an encounter until the lockdown lifts.
  - *Answers.* Need, Greed or Pass, with the item worn in that slot (the lower of a pair). The window ranks them Need,
    Greed, Pass, then by the guild's system (DKP points, wishlist place), then a roll every screen computes alike (a
    hash of the offer and the player, 1 to 100), and shows who has the item on a wishlist, points and attendance.
  - *Award.* An officer awards it; under the free roll its holder may too (the offer carries that, so every client
    agrees). A Pass is never awarded. The winner is announced in raid chat (printed instead in a lockdown).
  - *Trade.* When the holder trades the offered item to the winner (`TRADE_SHOW`, `TRADE_PLAYER_ITEM_CHANGED`,
    `TRADE_ACCEPT_UPDATE`, "Trade complete." within 15 seconds; the item must be the offered one), the award goes into
    the loot history: the holder's row of that drop becomes the winner's (`awarded`, `from`), or a new row on a client
    that missed the drop; the holder's `D` tells every client, and the awarding officer charges it under DKP. Traded to
    anyone else, nothing is recorded, the holder is told so and the offer is withdrawn.
- **Still absent:** the loot master (no Master Loot) and soft reserves: softres.it's page says "Soft-reserves for your
  Classic WoW raids!" and names no retail raid (read 2026-10-22).
- **Forever and Anniversary:** unchanged. TradeCouncil does not exist there; `/gos offer` says "Not available on this
  client."
- **Read in game:** the tooltip's trade line and its duration words; "Trade complete." as `UI_INFO_MESSAGE`;
  `GetTradePlayerItemLink`'s link against the bag's; the journal's functions with the journal never opened; addon
  messages over RAID across connected realms.
- **Tests:** `tools/retail-points.lua`, `tools/retail-wishlist.lua`, `tools/retail-loot-council.lua`,
  `tools/trade-council-ui.lua`; `tools/retail-absent.lua`, `tools/retail-loot.lua`, `tools/client-detection.lua`,
  `tools/window-shell.lua`, `tools/probe.lua` and `tools/commands-in-ui.lua` follow.
