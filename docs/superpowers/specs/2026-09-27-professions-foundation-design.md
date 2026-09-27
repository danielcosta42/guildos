# Professions on WoW: Forever — foundation

Issue: danielcosta42/guildos#31 · Epic: #30 (sub-project 1 of 5) · Forever only

## 1. Problem

- On WoW: Forever the addon collects no profession at all. The Classic API it reads is gone
  (`GetNumSkillLines`, `GetSkillLineInfo`, `GetTradeSkill*`, `GetCraft*`), so every record carries
  `absent.professions`, `db.recipes` stays empty, and every surface that reads them is blank:
  the roster column, member detail, the recipes panel, "crafted by" tooltips, CraftFinder,
  `/gos craft`, CraftNet answers, the alliance craft directory, and the professions on guildos.me.
- Professions will be central in Forever, and the guild wants four things on top of this data
  (epic #30): who crafts what, coverage planning, crafting requests, a showcase on the site. All
  four need the same foundation: every member's professions, levels and recipes, by ID, kept in
  sync cheaply.
- The old recipe sync ships a character's whole recipe map inside every `BC` broadcast (every
  300s and on every request reply), and only learns recipes when the player opens the window.

## 2. What the client offers (verified 2026-09-27, build 1.60.1.70009)

A throwaway probe addon in the beta recorded what the client returns (results in the professions
memory note and the epic):

- `GetProfessions()` returns spell-book indices (slots: two primaries, First Aid, Fishing,
  Cooking); `GetProfessionInfo(index)` returns name, icon, **exact rank and max rank**, and the
  skill line (e.g. Mining 21/75, line 186) with the window closed.
  `C_TradeSkillUI.GetProfessionInfoBySkillLineID` returns 0/0 and is not used.
- With the window closed, **`IsPlayerSpell(recipeID)` matched the window's learned list exactly**
  (6/6 across Mining, Cooking, First Aid). `C_SpellBook.IsSpellInSpellBook` returned false for all,
  and `GetRecipeInfo().learned` is only valid for the last profession opened.
- `C_TradeSkillUI.GetAllRecipeIDs()` (window open) lists learned and unlearned recipes;
  `GetRecipeInfo` gives `learned`, name, category, skill-up data; `GetRecipeSchematic` gives the
  output item and reagents; `IsTradeSkillLinked/Guild/GuildMember` tell another player's view apart.
- `C_TradeSkillUI.IsGuildTradeSkillsEnabled()` is false, yet `C_Club.GetMemberInfo` returns
  `profession1ID/Name` and `profession2ID/Name` for **every** guild member, with or without the
  addon; the rank is always 1 (meaningless). `QueryGuildMembersForRecipe` got no answer.
  `C_Club.GetMemberInfo` is `SecretInChatMessagingLockdown`.
- Game data (wago DB2 for 70009): 9 primaries plus Cooking, First Aid, Fishing; each has one
  retail-style child line (2937–2948); recipes sit on the parent line. Cap 300. ~2,520 recipes
  (~930 new against Classic Era), a camp and crafting-station system (many recipes require a
  station), vanilla specializations (gating recipe items through `ItemSparse.RequiredAbility`),
  no Jewelcrafting (a hidden test profession 2933/2934 exists). Retail crafting systems (quality,
  profession trait trees, crafting orders, concentration) have 0 records.

## 3. Design

### 3.1 Scope and loading
- Forever only. Each new file starts with `if BRutus.Client.isAnniversary then return end`; a
  module that does not exist is skipped by `StartModule`. Anniversary behaviour and data do not
  change.
- New files:
  - `Data/ProfCatalogForever.lua` — the generated catalog (data only).
  - `Modules/Professions.lua` — collection, the per-member model, the query API, native data,
    the legacy adapter.
  - `Modules/ProfSync.lua` — the `prof` SyncService domain.
  - `tools/prof-catalog/build.py` — the generator; `tools/professions.lua` — the harness.
- `Professions` starts after `SyncService` and `DataCollector` in `MODULE_START`; `ProfSync`
  right after it.

### 3.2 Catalog
- `python tools/prof-catalog/build.py <build> [--cache <dir>]` downloads the DB2 CSVs from
  `https://wago.tools/db2/<Table>/csv?build=<build>` and writes `Data/ProfCatalogForever.lua`,
  stamped with the build. Rerun on every beta build.
- Tables: SkillLine, SkillLineAbility, SpellEffect, SpellReagents, SpellCastingRequirements,
  SpellFocusObject, TradeSkillCategory, Item, ItemSparse, ItemEffect, ItemXItemEffect.
- `BRutus.ProfCatalog`:
  - `build` — the build string.
  - `professions[line] = { child = childLine, primary = bool, en = "Alchemy" }` for the 12
    profession lines (Poisons and Comprehension are left out: class skills, not professions).
    `en` is the canonical English name the legacy code keys on.
  - `specs[spellID] = line` — specialization spells (every non-zero `RequiredAbility` of a
    recipe item, mapped to its skill line).
  - `recipes[recipeID] = { line, yellow, grey, out, outCount, enchant, reqSkill, spec, focus,
    src, recipeItem, category, reagents }` as a positional array; `reagents` is a flat
    `{itemID, count, ...}` list; `src` is 1 trainer/other, 2 recipe item, 3 automatic.
  - A recipe two professions learn (Synthetic Gordok Ogre Suit, Tailoring and Leatherworking) is
    listed in both lines' `byLine` and recorded once, under the lowest line; a spell with several
    rows on one line is listed once.
  - `stations[focusID]` — the English name of each crafting station a recipe requires.
  - `byLine[line] = { recipeID, ... }` sorted — the passive scan's work list.
- Left out: the test profession (2933/2934), rank spells, rows with `AcquireMethod` 3 (retired),
  rows with no create/enchant effect. No names: the client localizes them at run time
  (`C_Spell.GetSpellName`, item info).

### 3.3 Collection (own character)
- **Levels:** `GetProfessions()` → `GetProfessionInfo(i)` → `{ line, rank, max }`, keyed by the
  skill line. Lines not in the catalog's `professions` are ignored.
- **Specialization:** the first spell of `specs` for that line the player knows (`IsPlayerSpell`).
- **Recipes:** for each owned line, `IsPlayerSpell(id)` over `byLine[line]` → sorted learned list.
- **Extra:** while the player's **own** profession window is open (not linked, not guild), learned
  recipe IDs from `GetAllRecipeIDs` + `GetRecipeInfo().learned` that the catalog does not have
  are kept in the line's `extra` list (a newer build than the catalog). Persisted with the record.
- **Hash:** `LibDeflate:Adler32` of the sorted recipe and extra IDs joined by commas.
- **Triggers:** login + 4s (full scan); `SKILL_LINES_CHANGED` (levels, debounced 2s);
  `NEW_RECIPE_LEARNED` (add that ID, rehash); `LEARNED_SPELL_IN_SKILL_LINE` (full scan, debounced
  2s); `TRADE_SKILL_LIST_UPDATE` with the own window settled (extra). A line no longer owned
  disappears on the next full scan.
- A change republishes the summary (3.5) after 10s of quiet.

### 3.4 Model and storage
- `db.professions[memberKey] = { src = "addon"|"native", ts, profs = { [line] = { rank, max,
  spec, h, n, recipes = {...}|nil, extra = {...}|nil } } }` in the per-guild DB. `recipes` is nil
  until the list for the current hash arrived.
- Native records come from `C_Club` (primary professions, no rank) for members without an addon
  record, refreshed on `GUILD_ROSTER_UPDATE` at most every 60s, skipping secret values. An addon
  record replaces a native one and is never downgraded by it.
- Query API: `Professions:Get(key)`, `:KnowsRecipe(key, id)`, `:CraftersOf(recipeID)` (cached
  inverted index, rebuilt when a record changes), `:Members(line)`, `:Catalog()`.
- Hygiene: `PruneStaleData` also drops `db.professions` rows no longer in the roster; a newer
  summary without a line removes it.
- Validation of anything received: numbers only; at most 7 lines per member, 1,500 recipe and 200
  extra IDs per line, IDs in 1..2^31; anything else is dropped without raising.

### 3.5 Sync — the `prof` domain (SyncService v2)
| Action | Channel | Data | When |
|---|---|---|---|
| `sum` | GUILD | `{ p = { [line] = { r = rank, m = max, s = spec, h = hash, n = count } } }` | login + 5–15s, 10s after a change, every 10 min |
| `ask` | GUILD | `{}` | login; each receiver answers with its own `sum` after 1–8s |
| `req` | WHISPER | `{ l = { line, ... } }` | on a `sum` whose hash differs from the stored one (2–6s jitter, once per sender and hash) |
| `list` | WHISPER or GUILD | `{ l = line, h = hash, r = { ids }, x = { ids } }` | answer to `req` |

- Requests for the same line within 3s are aggregated: one requester gets a whisper, two or more
  get one GUILD `list`.
- A receiver stores a `list` only if the hash it recomputes equals the `h` in the list and the
  `h` of the latest `sum` it holds from that sender, and it does not hold that list yet. A list with
  no summary before it is dropped: whoever asked always has the summary.
- A request that got no list is asked again after 120s, when the next summary still carries that hash.
- Trust: the member key comes from the sender, never from the payload; a sender that is not in the
  guild roster (`GetMemberRecord`) is ignored, whatever the channel.
- Size: ~300 recipes serialize and deflate to ~1.5 KB (about 7 chunks at BULK), sent once per
  change instead of every 300s.

### 3.6 Legacy adapter and integration points
- On every record change, the adapter writes the legacy shapes the existing surfaces read:
  - `members[key].professions = { { name = en, rank, maxRank, isPrimary }, ... }` (ranked lines
    only; native records produce `{ name = en, isPrimary = true }` with no rank);
  - `db.recipes[key][en] = { { name = localized spell name, itemId = out, spellId = recipeID } }`.
- `DataCollector:CollectProfessions` takes the own list from `Professions` on Forever, so `BC`
  stops carrying `absent.professions` there and cannot wipe peers' copies.
- `DataCollector:GetBroadcastData` stops including `recipes` on Forever (ProfSync carries them).
- The stale-profession reminder (`Core/Utils.lua`) does not run on Forever: nothing needs a window.
- A profession without a rank renders as its name alone in `RosterFrame` (cell and tooltip) and
  `MemberDetail` (fixes the nil-rank raise); `CompanionExport` sends only ranked professions.

### 3.7 Compat, probe, CI
- New `Compat` wrappers: `GetProfessions`, `GetProfessionInfo`, `IsPlayerSpell`, `TradeSkillLearned`
  (the open window's line and learned IDs, only for the player's own settled view) and
  `GuildMemberProfessions` (the Communities roster's profession lines, secret fields skipped). Names
  come through the existing `Compat.GetSpellInfo`. `compat-guard` lists `GetProfessions`,
  `GetProfessionInfo`, `C_TradeSkillUI` and `C_Club` so nothing else reaches them.
- `/guildos probe` records `GetProfessions`, `GetProfessionInfo`, `IsPlayerSpell`,
  `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo`, `C_Club.GetMemberInfo`, the catalog build and
  the number of extra IDs.
- `.luacheckrc` learns the new globals.

## 4. Out of scope
- Anniversary (unchanged) and its pre-existing profession bugs (separate issues).
- New screens (sub-project 2), officer coverage (3), recipes on the site / payload v7 (4),
  crafting requests (5).

## 5. Tests
- `tools/professions.lua` (luajit), stubbed Forever client with the real Compat, SyncService,
  CommSystem framing where needed, DataCollector integration points and a small fixture catalog:
  - collection: levels, spec, recipes by `IsPlayerSpell`, extra from the own window only, a line
    dropped, `NEW_RECIPE_LEARNED`, hash stability and order independence;
  - sync: `sum` → `req` → `list`, aggregation (whisper vs guild), hash mismatch rejected, sender not
    in guild ignored, payload key ignored in favour of the sender, caps and malformed data dropped
    without raising;
  - model: native records, addon replaces native, prune, `CraftersOf`;
  - adapter: legacy shapes, no `absent` on Forever, no recipes in `BC`, reminder off, rankless
    rendering, export only ranked;
  - Anniversary: the modules do not exist, `DataCollector` unchanged.
- `tools/prof-catalog/build.py --selftest` on a checked-in fixture subset of CSVs.
- Every existing harness, luacheck and compat-guard stay green.
- Manual (maintainer, beta): two characters with different professions see each other's ranks and
  recipes without opening a window; learning a recipe shows up on the other within ~15s.

## 6. Tasks
- [x] Catalog generator + fixture self-test + generated catalog for 1.60.1.70009 (2,490 recipes,
  10 specializations, 21 stations)
- [x] Compat wrappers, compat-guard, luacheck, probe
- [x] `Professions` (collection, model, native, API, adapter)
- [x] `ProfSync`
- [x] Integration points (DataCollector, reminder, rankless rendering, export)
- [x] `tools/professions.lua` (7,553 checks, most of them the real catalog's per-recipe checks);
  mutants of the native guard, the hash compare, the extra filter, the list guard, the roster
  check, aggregation, re-ask, hash verification, the broadcast gate, the reminder gate, pruning,
  the own-list scan and the crafter dedupe are all killed
- [x] Spec, functions catalog, decisions (ADR-0022)
- [ ] Manual check on the beta (maintainer)
