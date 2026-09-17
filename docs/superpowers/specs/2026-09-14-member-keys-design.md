# Member identity without a realm

Issue: danielcosta42/guildos#8 · Epic: #4 · Depends on #7 · ADR-0018

Condensed spec + plan + tasks.

## 1. Problem

- **One key shape everywhere.** Every member key is `name .. "-" .. realm`. `BRutus:GetPlayerKey(name, realm)` (`Core/Utils.lua`) builds most of them, and a handful of places built their own.
- **Forever has no realms.** What `GetRealmName()`, `GetNormalizedRealmName()` and `GetGuildRosterInfo` return there is unknown: nil, `""` or a suffix are all plausible. Names may be in two parts ("First Last").
- **What broke on a realm-less client:**
  - `GetPlayerKey` raised when neither the caller nor `GetRealmName()` gave a realm;
  - hand-built joins raised the same way, one of them on every incoming addon message (`CommSystem:OnMessageReceived`), others in `/gos trial`, `/gos note`, raid snapshots, the consumable check and the companion export's guild key;
  - LootMaster and the wishlist fell back to `""` in some places and `"Unknown"` in others, so one member ended up under `Ana-`, `Ana-Unknown` and nowhere at all;
  - PugInspector joined `Name-` with an empty realm, missing every alt link and note.

## 2. Design

### 2.1 One rule
- **`BRutus:GetClientRealm()`:** `GetRealmName()`, else `GetNormalizedRealmName()`, else nil. An empty answer counts as nothing.
- **`BRutus:GetPlayerKey(name, realm)`:**
  - an empty realm from the caller counts as absent, and the client's realm fills it;
  - with a realm, the key is `name .. "-" .. realm`, byte for byte as in 0.53.0, so Anniversary keys, saved data and sync payloads do not change;
  - with no realm, the key is the name alone;
  - a nil or empty name returns nil instead of raising.
- **Why `Name` and not `Name-`:** every split-and-rejoin site uses `^([^-]+)` and `-(.+)$`.
  - "First Last" splits to itself with no suffix and rejoins to "First Last".
  - "Anne-Marie" splits to "Anne" + "Marie" and rejoins to "Anne-Marie".
  - Each site keeps a stable key.
- **`GetRealmName` first:** the normalized name drops spaces and apostrophes, which would change Anniversary keys for realms like "Living Flame" or "Nek'Rosh". `GetNormalizedRealmName()` is asked only when `GetRealmName()` answers nothing, for a client that still suffixes roster names.

### 2.2 Every hand-built join goes through it
- **Addon messages:**
  - `CommSystem:OnMessageReceived`, the own-message check.
  - `CommSystem:HandleBroadcast`: the payload's realm, else the client's, as in 0.53.0. Only a client with no realm at all takes the sender's own suffix, so a broadcast lands under the key the roster gives that member.
- **Commands:** `/gos trial` and `/gos note`.
- **Raid attendance:** `RaidTracker:TakeSnapshot`, the group members (keeping a cross-realm member's own realm) and me.
- **Consumables:** `ConsumableChecker:CheckRaid` (Anniversary only).
- **Export:** `Companion:BuildPayload` takes the client's realm for `guildKey` ("Guild-Realm", or the guild name alone), the member fallback and the `realm` field (absent without one).
- **Loot:** `LootMaster:GetPlayerContext`, a peer's `AWARD`, `RegisterRoll`, `AwardLoot` and its DKP charge. The `""` and `"Unknown"` fallbacks are gone.
- **Wishlist:** the one-time migration, `GetMyList` and `IsItemDelivered`. Their `"Unknown"` and `""` fallbacks are gone.
- **PugInspector:** `Classify` stays free of globals, so it applies the same rule inline; its live sources hand it the client's realm.

### 2.3 Not changed (disclosed)
- **The per-guild database key** (`BRutus:ResolveGuildDB`, `Guild-Realm` with an `"Unknown"` fallback) is not a member key; it is already stable on a realm-less client.
- **A roster that suffixes names on a client where both realm functions answer nothing** splits keys:
  - roster rows, the export's member rows and a suffixed sender's broadcast carry the suffix (`Bob-Suffix`);
  - every key built from a bare name stays bare (`Bob`): my own key and the export's author, loot history and rolls,
    `/gos` commands, raid attendance and `GetMemberRecord`. The export's loot and attendance then do not join its
    member rows, and member detail finds no synced data;
  - my own suffixed messages are not recognised as mine, so my broadcast comes back as a second record under `Ana-Suffix`.

  `/guildos probe` records `GetRealmName()`, `GetNormalizedRealmName()` and the first roster name, so the beta shows
  whether this state exists before anything depends on it. The harness pins the behaviour (section 13).
- **`GetMemberRecord("Anne-Marie")`** reads "Marie" as a realm on a realm-less client, exactly as it ignores a realm suffix on Anniversary today. Hyphenated names wait for the beta to show whether they exist.
- **Slash commands that take `%S+`** (`/gos trial`, `note`, `ban`, `tempban`, `recruit invite`) still take one word; a two-part name needs quoting rules. Follow-up issue.
- **Short-name matches** (`IsOfficerByName`, the roster index lookups, `BanList`) are only ambiguous if Forever names repeat across what used to be realms. Follow-up once the beta shows real names.

## 3. Tests
- **`tools/member-keys.lua`** (luajit; 437 checks). It loads the real `Core/Core.lua`, `Compat.lua`, `Utils.lua`, `Commands.lua`, `CommSystem`, `RaidTracker`, `LootMaster`, `WishlistSystem`, `ConsumableChecker`, `PugInspector`, `CompanionExport` and `CompanionImport` under a stubbed TBC Anniversary client.
  - **Realm states:** sections 3 to 11 each run their key sites twice with the client answering nothing (`GetRealmName()` and `GetNormalizedRealmName()` nil, then both `""`), then on Anniversary ("Firemaw").
  - **Rule, with a realm:** the same bytes as 0.53.0's rule for four realms (spaces and apostrophes included, with a normalized realm present that must not be used), for the client's realm and a caller's; an empty caller realm is filled; no name gives no key.
  - **Anniversary roster fixture:** `tools/roster-fixture.txt` is decoded through the real `CompanionImport`, and every member's key and invite name key exactly as 0.53.0's rule does.
  - **Rule, without a realm:**
    - the name alone, for both answers and the mixed pairs;
    - a two-part name, and a caller's realm still counts;
    - split and rejoin keeps "Ana", "First Last", "Anne-Marie" and "First Last-Suffix";
    - names sharing a first part stay apart;
    - a key survives a SavedVariables write and read;
    - `GetMemberRecord("First Last")` resolves under "First Last".
  - **Addon messages:**
    - my own are skipped, and everybody else's are decoded;
    - a received broadcast is stored under the rule's key: on a realm-less client, a two-part name, a payload with no name, and a suffixed sender with no or an empty payload realm; on Anniversary, a payload realm, the client's realm, a cross-realm sender, and a sender suffixed with the normalized realm, keyed as 0.53.0 did.
  - **Raid attendance:** the session players and the snapshot members, a cross-realm member included.
  - **Consumables:** the result keys.
  - **Loot:** attendance and this lockout's loot lookup, a peer's award, my award, its DKP charge and a `/roll`.
  - **Wishlist:** `GetMyList`, the migration and `IsItemDelivered` agree on one key.
  - **Commands:** `/gos trial` and `/gos note`.
  - **PugInspector:** alt links and notes found under the rule's key, and the live sources' realm (none, a normalized-only client, Anniversary).
  - **Export:** guild key, author, `realm` field and every member key, with a published record found under its key.
  - **A roster that suffixes names on a client with only a normalized realm:** with `GetRealmName()` nil or `""`, the export's author, guild key, realm and rows, my own message, `GetMemberRecord` and a received broadcast all use the roster's `Name-Suffix`.
  - **Disclosed, not solved:** the §2.3 state (a roster that suffixes names, both realm functions empty) is pinned as it behaves today: bare keys for me, loot, rolls, `/gos trial` and member records; suffixed roster rows and broadcasts; my own suffixed message not recognised.
  - **Source scan:** every Lua file in the TOC must be on disk. None builds a `.. "-" ..` join (either quote), a `"%s-%s"` format, or a literal fallback from `GetRealmName()`, `GetNormalizedRealmName()` or `GetClientRealm()`, apart from the six joins that are not member keys or only join with a realm, and the two sentinel fallbacks.
- It fails on 0.53.0's code, at the first rule check.
- **`tools/roster-import.lua`** now runs the real rule instead of a copy of it.
- **`tools/probe.lua`** checks that `/guildos probe` records `GetRealmName()` next to `GetNormalizedRealmName()`, each from its own function (the stubs answer differently), and "missing" without them.
- **`tools/companion-payload.lua` repaired** (it stopped at `gearFor` without `BRutus.SlotIDs`) and moved onto the real rule; its payload is byte-identical to the one the pre-change tree builds.
- **Mutation check:** 56 hand-written mutants of the rule, the client realm, every join site, the broadcast receiver, PugInspector and the source scan; the test kills all 56.
- Still passing: every Lua harness. `luacheck` is clean apart from the known `Inbox.lua:5` warning.
- **Manual, needs the maintainer:**
  1. On Anniversary, sync with another officer; the roster, attendance and loot history show no duplicates.
  2. The companion export is byte-identical to one taken before the change.
  3. On the Forever beta, `/guildos probe` records what `GetRealmName()`, `GetNormalizedRealmName()` and the first roster name look like.

## 4. Tasks
- [x] Rule in `GetPlayerKey`, with `GetClientRealm`
- [x] Joins, fallbacks and the broadcast receiver through it
- [x] `tools/member-keys.lua`; `roster-import.lua` on the real rule; repair `companion-payload.lua`
- [x] Spec, ADR-0018, catalog
- [ ] Manual checks (maintainer)
