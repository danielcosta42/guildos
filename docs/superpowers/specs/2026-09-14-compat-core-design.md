# Roster, own-character collection and addon messages go through Compat

Issue: danielcosta42/guildos#10 · Epic: #4 · Depends on #6, #7 · ADR-0019

Condensed spec + plan + tasks.

## 1. Problem
- **Direct calls outside `Core/Compat.lua`** (71 found by the guard below):
  - the roster request and the addon-prefix registration (Core, LootMaster);
  - `C_Container` (DataCollector, LootMaster), with the old globals inlined next to it in LootMaster;
  - `GetItemInfo` at 31 sites;
  - `GetSpellInfo` (RecipeTracker, ConsumableChecker), `GetSpellTexture` (RaidHUD), `UnitBuff` (ConsumableChecker);
  - talents (SpecChecker) and skill lines (DataCollector), **unguarded**.
- **A missing API stops collection.** A missing talent or skill-line function raises inside `CollectMyData`. That stops gear, spec and professions, then the throttled broadcast, and every later reply to a data request.
- **Sends ignore their result.** `CommSystem:SendRaw` calls ChatThrottleLib with no callback; `LootMaster:SafeSendAddon` calls `C_ChatInfo.SendAddonMessage` directly. ChatThrottleLib v31 re-queues only `AddonMessageThrottle` itself, so a chat lockdown dropped sync without a trace.
- **Shims nobody called:** `Compat.NewTimer` and `Compat.SendAddonMessage`. `RegisterAddonPrefix` had only Probe as a caller.

## 2. Design

### 2.1 Wrappers (namespaced first, then the old global, else nothing)
- `Compat.GetItemInfo`: `C_Item.GetItemInfo` or `GetItemInfo`, with every return passed through.
- `Compat.GetSpellInfo`: `C_Spell.GetSpellInfo`'s table mapped to the global's order (name, rank, icon, castTime, minRange, maxRange, spellID), or `GetSpellInfo`.
- `Compat.GetSpellTexture`: `C_Spell.GetSpellTexture` or `GetSpellTexture`.
- `Compat.UnitBuff`: `C_UnitAuras.GetBuffDataByIndex` mapped to `UnitBuff`'s order (spellId tenth), or `UnitBuff`. On 2.5.6 the client's own `UnitBuff` is built the same way.
- Bags:
  - `Compat.GetContainerNumSlots` returns 0 when the client has no API.
  - `Compat.GetContainerItemInfo` returns the namespaced table, built from the old global's returns where that is all there is.
  - `Compat.GetContainerItemLink` and `Compat.UseContainerItem` pass through.
- Talents and skill lines: `Compat.GetNumTalentTabs`, `GetNumTalents`, `GetTalentInfo`, `GetNumSkillLines` and `GetSkillLineInfo`.
  - The count functions return `nil, "no-api"` when the client lacks the function; the info functions return nil.
  - The inspect flag is passed through, and own talent tabs still call the global with no argument.
- `Compat.RegisterAddonPrefix` gains the `RegisterAddonMessagePrefix` fallback. `Compat.GuildRoster` already had both.

### 2.2 Collection degrades to absent fields
- **Professions:** `DataCollector:CollectProfessions()` returns nil without a skill-line API, so `professions` leaves the record and the broadcast.
- **Spec:** `SpecChecker:CollectOwnSpec()` returns `nil, "no-api"` without a talent API.
  - With no talent API, `CollectMyData` removes the saved spec and flags no re-collect.
  - When talents have not loaded yet (0 tabs), it keeps the old spec and flags a re-collect, as before.
- **Absent marker:** a field left out because its API is missing is named in `absent` (`{ spec = true, professions = true }`).
  - The broadcast carries the marker, and `DataCollector:StoreReceivedData` drops the `spec` or `professions` a receiver still held for that member.
  - A later broadcast with the fields clears the marker.
  - A client with every API sends no marker, as in 0.53.0.
- **Export:** a record that published (`lastUpdate > 0`) with no `professions` key exports no professions field.
  - A published empty list stays `[]`, and a roster member who never published keeps `[]`, as in 0.53.0.
  - On Anniversary every published record carries a list (all 7 `[]` rows in real saved data kept), so the payload does not change.

### 2.3 Two senders, one result path
- **Senders:**
  - `Compat.SendAddonMessage(prefix, text, channel, target, prio, queueName)` sends through ChatThrottleLib with a callback, `BULK` by default. `CommSystem:SendRaw` uses it: guild at `BULK` or the given priority, whisper at `NORMAL`.
  - `Compat.SendAddonMessageNow(prefix, text, channel, target)` sends at once through `C_ChatInfo.SendAddonMessage`, past ChatThrottleLib's queue. `LootMaster:SafeSendAddon` uses it, so a roll popup arrives when the roll timer starts, as before #10.
- **Refused before queueing:** a message ChatThrottleLib or the client would refuse (prefix empty or over 16 bytes, text missing or over 255 bytes, no channel, unknown priority) is recorded once and dropped, never queued.
- **By result.** Codes are read from `Enum.SendAddonMessageResult` by name, with 0, 3, 8 and 11 as fallbacks (the values the 2.5.6 API documents).
  - **Success:** done.
  - **`AddonMessageThrottle`:** ChatThrottleLib re-queues it itself on the sync path; a message sent now (loot) retries it after 1, 2, 4 and 8 seconds, like a channel throttle.
  - **Lockdown** (the result, or `C_ChatInfo.InChatMessagingLockdown()` before sending): the message is held.
    - Every later send waits behind it, so the order stays.
    - The queue is flushed on `PLAYER_REGEN_ENABLED`, on `ZONE_CHANGED_NEW_AREA`, and by a 2-second poll that runs while anything waits, so a lockdown that lifts with neither event (a boss dying after the officer died mid-fight) is noticed.
    - The flush sends one message at a time under `pcall`: one that raises is recorded, and the rest still go. Anything still locked down is held again.
    - The queue is capped at 200; past that, the oldest message goes.
  - **`ChannelThrottle`:** resent after 1, 2, 4 and 8 seconds, then recorded and dropped.
  - **Anything else:** recorded once per result code for `/guildos errors`, and dropped.
- Without ChatThrottleLib, the client's own return is read the same way (nil or true is sent).
- **Other paths:** incoming validation is untouched. LibChehulMesh (AceComm, used by the alliance and craft networks) and the probe's single test message keep their own paths.

### 2.4 Shims
- `RegisterAddonPrefix` registers the sync and legacy BRutus prefixes (Core) and the loot prefix (LootMaster).
- `SendAddonMessage` carries sync, and `SendAddonMessageNow` carries loot.
- `IsQuestComplete` already answers `/gos` attunement checks (#7).
- `NewTimer` is removed: `C_Timer.NewTimer` exists on every target client, and its four direct users stay.

### 2.5 CI guard
- `tools/compat-guard.lua` (lua5.1, no dependencies) scans every Lua file in the TOC outside Libs, after blanking comments, strings and long strings. It flags:
  - an old global (`GetItemInfo`, `GetSpellInfo`, `GetSpellTexture`, `UnitBuff`, the talent, skill-line and bag calls, `GuildRoster`, `RegisterAddonMessagePrefix` and `SendAddonMessage`), reached by name other than as a field or method of something else: called, tested for existence, after `..`, or as `_G.Name` or `_G["Name"]`;
  - `GuildRoster`, `RegisterAddonMessagePrefix`, `SendAddonMessage` and `SendAddonMessageLogged` as a field or method of anything but `Compat` (a receiver ending the line above included), or as a quoted string index directly on a plain name on the same line (`C_ChatInfo["SendAddonMessage"]`);
  - the namespaces `C_Item`, `C_Spell`, `C_UnitAuras` and `C_Container`, and `ChatThrottleLib`, wherever they appear, an alias included;
  - `_G` or `getfenv` used as a value (an alias, `rawget(_G, ...)`), and a single-name assignment `Compat = X` whose first token is not `BRutus.Compat`, `GuildOS.Compat` or `self.Compat`;
  - a file the TOC lists that is not on disk.
- Exempt:
  - `Core/Compat.lua`;
  - `Core/Probe.lua`, which records which of these APIs exist;
  - `Modules/ChehulNet.lua`, which is shared verbatim with other addons.
- Its file reader can be injected, so the harness plants violations in a fake tree.
- The lint job in `release.yml` runs `lua5.1 tools/compat-guard.lua`, and it names each file and line.

### 2.6 Not in #10 (disclosed)
- `C_Map` in ChehulNet.lua stays; that file must not depend on BRutus.
- The result names on WoW: Forever are unconfirmed. `/guildos probe` records `Enum.SendAddonMessageResult`, and the fallbacks are the retail codes.
- A lockdown that splits a chunked sync message can let the receiver's 30-second reassembly expire. The next broadcast (every 5 minutes, or on request) repairs it.
- **The guard reads names, not expressions.** It does not follow:
  - a name built at run time (`_G[name]`), or passed through a function argument or `rawget`;
  - a string index on a parenthesised, chained or previous-line receiver, or in a long-bracket string;
  - a `Compat` assigned in a compound or multi-name expression.
  Common idioms that rebind `_G` (`local _G = _G`, `pairs(_G)`) or name another table `Compat` fail CI loudly and would need an exemption; none is in the tree.

## 3. Tests
- **`tools/compat-core.lua`** (luajit; 170 checks). It loads the real Core, Compat, Utils, DataCollector, SpecChecker, CommSystem, LootMaster, ConsumableChecker, CompanionExport and `tools/compat-guard.lua` under a stubbed TBC Anniversary client. Its result codes differ from the fallbacks, so the names are proven to be read, and a second load of Compat without `Enum` proves the fallbacks.
  - **Wrappers:** each one with the namespaced API, the old global and neither.
    - Mapped returns: the `C_Spell` table, every `C_UnitAuras` position through spellId, the old bag tuple.
    - The inspect flag through `GetNumTalents` and `GetTalentInfo`; the prefix and the roster request. `NewTimer` is gone.
  - **Sends:**
    - success;
    - a lockdown by result and before sending;
    - order kept behind a held message;
    - no flush while locked down;
    - a flush on combat end, on a zone change, and by the poll after a lockdown that lifts with neither event, the poll rescheduling while still locked and stopping after;
    - five held messages arm one poll, and a poll that finds the lockdown still on arms exactly one more;
    - channel-throttle retries at 1, 2, 4 and 8 seconds, then recorded;
    - other failures recorded once and not retried;
    - an oversized message, an unknown priority, a long, empty or non-string prefix, no text or no channel refused and recorded once;
    - a held message that raises during the flush, with the one behind it still sent;
    - the 200 cap;
    - the no-ChatThrottleLib path;
    - an AddonMessageThrottle reaching ChatThrottleLib's callback recorded, not retried;
    - the fallback codes, 3 included on a message sent now.
  - **Senders:** guild sync at `BULK` or its priority, a whisper at `NORMAL`, a sync message caught by a lockdown held; loot sent at once past ChatThrottleLib, held by a lockdown on its direct path, and retried after a second when the client throttles it.
  - **Own character:**
    - with every API, spec, professions and gear are collected, every slot of the five bags is read through Compat, and no marker is sent;
    - with no skill-line API, professions are absent and named absent;
    - with no talent API, the spec is removed, no re-collect is flagged, and both fields are named absent;
    - with talents not loaded yet, the old spec stays, a re-collect is flagged, and nothing is named absent;
    - a receiver drops the stale fields on the marker and restores them on a later broadcast;
    - an inspected raider's spec is read with the inspect flag, and my own with mine.
  - **Export:** a published list travels; a record published without the API has no `professions` key in the encoded JSON; a published empty list and a never-published row keep `[]`.
  - **Loot master:** an item in a bag's last slot is found, a trade places it, and a roll from the bags reads its link, all through Compat.
  - **Roster and consumables:** opening the window requests the roster; the consumable check reads a raider's buffs by id and by the localized name, through Compat.
  - **Guard:**
    - no hits on the tree;
    - exactly three exempt files;
    - a fake tree proves every Core, Modules and UI file is read, Libs and Compat are skipped, and a missing file fails;
    - every listed call and every evasion is flagged: concatenation with or without spaces, `_G.Name`, `_G["Name"]` with spaces, `_G["C_Item"]`, string-indexed senders, namespace, ChatThrottleLib, `_G` and `Compat` aliases, `getfenv`, `rawget(_G, ...)`, senders on other objects and `SendAddonMessageLogged`;
    - comments, strings, long strings, fields and methods of Compat or other objects, a `Compat` receiver ending the line above, `_G.X` and run-time `_G[name]`, and longer names are ignored;
    - file and line are reported; its command line exits 1 on a planted tree on disk and 0 on the addon; the lint job runs it.
  - **Shims:** each is wired where §2.4 says.
- It fails on the tree before #10.
- **Anniversary unchanged:** the companion export from `tools/companion-payload.lua` is byte-identical before and after.
- **Mutation check:** 121 hand-written mutants of the wrappers, send results and validation, the poll, the senders, degraded collection and the absent marker, inspect, the loot master's bags, the roster, consumables, export, guard and CI step; the test kills all 121.
- Still passing: every Lua harness and `tools/beta-workflow.py`. `luacheck` is clean apart from the known `Inbox.lua:5` warning, with `C_Item`, `C_Spell`, `C_UnitAuras` and `Enum` added to its globals.
- **Manual, needs the maintainer:**
  1. On Anniversary, two officers sync and see the same data as with 0.53.0.
  2. `/gos sync` in combat inside an instance shows no error, and the data arrives after combat.
  3. A loot roll's popup appears for raiders as promptly as before.
  4. On the Forever beta, `/guildos probe` shows the `Enum.SendAddonMessageResult` names.

## 4. Tasks
- [x] Compat wrappers, prefix fallback, send path with results, validation and poll; `NewTimer` removed
- [x] Call sites; SpecChecker and DataCollector degrade with the absent marker; export professions absent
- [x] `tools/compat-guard.lua` and the CI step; `tools/compat-core.lua`
- [x] Spec, ADR-0019, catalog, architecture
- [ ] Manual checks (maintainer)
