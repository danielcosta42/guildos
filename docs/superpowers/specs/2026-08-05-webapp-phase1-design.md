# Web companion — Phase 1 design (Discord-login web app + minimal companion + single-server raid bot)

Bring the GuildOS guild data out of the game and onto the web, logged in with Discord, so a signup
posted by a bot shows **each signee's item level, spec and attendance** — data no other signup tool
(Raid-Helper, Raidify) has, because it comes straight from the GuildOS addon. First tester: a BR
community of 5 guilds / 150+ players. Timed to land before the Classic+ wave.

Scope for this document is **Phase 1 only**: web app + a deliberately tiny companion + a
single-server raid bot. Cross-server signup, live combat-log attendance and write-back into the game
are named in §14 and explicitly deferred.

Standing project rule (from `alliance-design.md`): **ASCII mockups approved before any UI work.** The
mockups in §7/§8 are for sign-off, not yet built.

---

## 1. What a GM sees in the Phase 1 demo (the "hope" moment)

1. An officer installs a small tray app on their PC once, pastes a guild token. Nothing else.
2. They `/reload` in-game (or just log out). Within seconds the web app shows the full guild roster —
   names, class, spec (`41/5/15 Protection`), item level, attendance %, loot history.
3. In Discord, an officer types `/raid Kara sexta 21h`. The bot posts a signup embed with
   Tank/Healer/DPS buttons.
4. A raider clicks **Tank**. The signup row instantly shows `Chehul — Prot Warr — iLvl 132 — 92%
   attendance`, because their Discord account is linked to their WoW character.
5. The officer opens the web raid page and sees the composition auto-filled with real gear/spec/att,
   not just names.

That step 4/5 is the entire pitch. Everything below exists to make it real and boring to operate.

---

## 2. Goals and non-goals

**Goals**

- Web app, login with Discord (OAuth), scoped to a community of up to ~8 guilds.
- Roster + loot + attendance flow **game → web automatically** via a minimal companion.
- A single-server Discord bot that creates raids and collects signups, with signups **enriched** by
  the linked character's GuildOS data.
- The web app is the source of truth for **signups**; the game is the source of truth for
  **roster/gear/loot/attendance**. No field is bidirectional in Phase 1 (this is what keeps it
  simple — see §11).
- Reuse the existing addon serialization surface (`Backup.lua`, §5) instead of inventing a new one.

**Non-goals (Phase 1)**

- Cross-server / multi-community signup sharing (the eventual differentiator — Phase 3).
- Writing anything back into the game (raid comps, soft-res). Signups stay on web/Discord for now.
- Live combat-log attendance. The addon already computes attendance into SavedVariables (§4 of the
  code map); the live combat-log leg is a Phase 2 upgrade.
- A signed/auto-updating polished installer. 10–15 officer installs, hand-delivered `.exe`, is fine.
- DKP/loot-council automation on the web. Read-only loot display only.

---

## 3. Constraints that shape the whole design

These are hard facts (game-side research + code map) that every component below obeys.

**C1 — The game is air-gapped; the only bridge is files on disk.** No HTTP from inside WoW. A PC-side
process reads/writes three file types the client touches.

**C2 — An addon cannot write its own file; SavedVariables is the only channel, and the *client*
flushes it only on logout / disconnect / quit / `/reload` (never mid-play, never on crash/Alt-F4).**
The WoW Lua sandbox strips `io.*`, `os.execute`, `loadfile`, etc. — there is no file-write API, so
"stream our own file live" is impossible (mmo-champion — "writing/reading files without relog").
`PLAYER_LOGOUT` is the last event before the flush, which is where we stamp the payload.
**On-demand flush trick:** `ReloadUI()` *is* callable from insecure Lua (the addon already does it in
`Backup:Import`, `Modules/Backup.lua`), and a `/reload` forces the SavedVariables flush in seconds. So
we don't wait passively for logout — a "Sync now" button writes the projection then calls
`ReloadUI()`, and the companion picks up the fresh file (§6). The one place this is off-limits is
mid-pull (reload drops combat-log tracking + a black screen); live in-combat presence is the
combat-log leg (C3 / Phase 2), which carries only combat events, never our custom data. Net: *custom
data = on-demand via SavedVariables; live = combat-log, combat-only.* This is the TSM Desktop App
model (reads `TradeSkillMaster.lua`, writes `AppData.lua` atomically).

**C3 — Loot is NOT in the combat log.** `WoWCombatLog.txt` carries `ENCOUNTER_START/END`,
`UNIT_DIED`, `COMBATANT_INFO`, damage/heal — no loot events. Loot must come from the addon. GuildOS
already records master-loot awards into `db.lootHistory` (code map §4). So for Phase 1 we take loot
from SavedVariables, not the combat log — the combat-log leg is unnecessary here.

**C4 — GuildOS payloads are LibSerialize, not JSON.** `Backup:Export` produces
`"GOSBKP1:" + LibDeflate:EncodeForPrint(CompressDeflate(LibSerialize:Serialize(db)))`
(`Modules/Backup.lua:14-26`). LibSerialize is a Lua-specific binary format; decoding it off-game is
real work. Phase 1 sidesteps this by adding a **JSON projection** export (§5) so the server never
needs a LibSerialize decoder.

**C5 — Identity is `"Name-Realm"` everywhere.** `GetPlayerKey` = `name.."-"..realm`
(`Core/Utils.lua:141-144`). Timestamps are Unix epoch (`GetServerTime()`/`time()`). The DB is
per-guild-keyed at `GuildOSDB["<Guild>-<Realm>"]` (`Core/Core.lua:147-204`). The web data model
mirrors these keys verbatim so merges are trivial.

---

## 4. Architecture overview

```
   IN-GAME (GuildOS addon)                COMPANION (officer PC)            CLOUD
  ┌───────────────────────────┐         ┌──────────────────────┐     ┌──────────────────────┐
  │ existing modules write     │         │  tiny tray app       │     │  Web App (Next.js)   │
  │ db.members / db.lootHistory│  disk   │  1. watch .lua file  │HTTP │  + Postgres          │
  │ db.raidTracker (attendance)│ ──────► │  2. extract GOSCOMP1 │────►│  ingest → upsert     │
  │                            │ .lua    │  3. POST w/ token    │     │  roster/loot/att     │
  │ NEW: CompanionExport.lua   │         └──────────────────────┘     │                      │
  │  writes GuildOSDB.__companion         (game→web, one direction)   │  Discord OAuth login │
  └───────────────────────────┘                                       │  raster + raid views │
                                                                       └──────┬───────────────┘
   DISCORD (single server)                                                    │ REST (source of
  ┌───────────────────────────┐                                              │ truth = signups)
  │  Bot (discord.js)          │  raid create / signup buttons                ▼
  │  /raid, Tank/Heal/DPS btns │◄─────────────────────────────────► ┌──────────────────────┐
  │  enriched embed            │        webhook + REST               │  Raid + Signup tables│
  └───────────────────────────┘                                     └──────────────────────┘
```

Four components, four data flows, one authority rule per domain:

| Domain | Source of truth | Flow in Phase 1 |
| --- | --- | --- |
| Roster / gear / spec / attunement | **Game** (addon) | game → companion → web (upsert, newest-wins) |
| Loot history | **Game** (addon) | game → companion → web (append, dedup) |
| Attendance | **Game** (addon, already computed) | game → companion → web (replace snapshot) |
| Raids / signups | **Web** | bot ↔ web REST; Discord is a view |
| Discord ↔ character link | **Web** | member self-claims, officer approves |

Nothing is written from web back into the game in Phase 1, so there is no reconciliation problem.

---

## 5. Component A — the addon change (`Modules/CompanionExport.lua`)

A small new module, same shape as `Backup.lua`. It does **not** replace `Backup` (that stays the
full-DB backup/restore). It produces a **reduced JSON projection** of only what the web needs, encoded
so it sits cleanly inside a SavedVariables Lua string.

**Why a projection and not the full `GOSBKP1` backup:** the full backup is the entire `BRutus.db`
(every table in DB_DEFAULTS, `Core/Core.lua:33-81`) in LibSerialize — decoding it server-side means
porting LibSerialize (C4). The projection is ~5 fields per member as JSON, so the server just
`JSON.parse`s.

**Encoding (mirrors Backup's outer layers, JSON inner):**
```
projection(table)  →  json = JSONEncode(projection)          -- small hand-rolled encoder, we own the fields
                   →  LibDeflate:CompressDeflate(json)
                   →  LibDeflate:EncodeForPrint(...)           -- printable: safe inside a .lua string literal
                   →  "GOSCOMP1:" .. encoded
```
Written on `PLAYER_LOGOUT` (last event before flush, C2) to `GuildOSDB.__companion`, and shown in a
copy box in the UI so the **same string** works for manual paste if someone has no companion.

Server decode is standard: strip `GOSCOMP1:` → `DecodeForPrint` (~30-line documented mapping from
LibDeflate) → zlib inflate → `JSON.parse`. **No LibSerialize decoder needed anywhere.**

**Projection shape** (`GOSCOMP1`), fields sourced directly from the code map:
```jsonc
{
  "fmt": "GOSCOMP1", "v": 1,
  "guildKey": "Chehul-Firemaw",              // db key, Core/Core.lua:147-204
  "guildName": "Nucleo BR", "realm": "Firemaw",
  "exportedAt": 1754400000,                  // GetServerTime()
  "exportedBy": "Chehul-Firemaw",            // uploader char
  "addonVersion": "0.45.0",                  // Config.lua:23
  "members": [
    { "key": "Chehul-Firemaw", "name": "Chehul", "class": "WARRIOR",
      "level": 70, "rank": 2, "avgIlvl": 132,          // DataCollector.lua:64-115
      "lastUpdate": 1754390000,                        // data.lastUpdate (merge guard)
      "spec": { "tree": "Protection", "points": [8,42,3] },   // SpecChecker.lua:112-129
      "prefRoles": ["TANK"],
      "professions": [ { "name": "Blacksmithing", "rank": 375 } ],
      "attunements": [ { "short": "KARA", "complete": true, "progress": 1.0 } ], // AttunementTracker.lua:202-249
      "gear": [ { "slot": 1, "id": 29011, "ilvl": 141, "quality": 4 } ]  // OPTIONAL in P1, avgIlvl usually enough
    }
  ],
  "loot": [
    { "playerKey": "Chehul-Firemaw", "itemId": 29011, "itemName": "Cursed Vision",
      "quality": 4, "timestamp": 1754300000, "raid": "Karazhan" }        // db.lootHistory, LootTracker §4
  ],
  "attendance": {                            // db.raidTracker.attendance, RaidTracker.lua:774
    "Core 1": { "Chehul-Firemaw": { "raids": 12, "attendance25": 0.92, "lastRaid": 1754300000 } }
  }
}
```
`gear` is marked optional because 150 members × 17 slots is a heavy payload and Phase 1's signup
enrichment only needs `avgIlvl` + `spec` + `attendance`. Ship gear detail in Phase 1.5 when the
member-detail page needs it.

TOC + registration: add `Modules/CompanionExport.lua` to `GuildOS.toc` and register like the other
modules (`Core/Core.lua` module list). Officer-gated to match the existing export UX
(`Backup:ShowExport`, `Backup.lua:61`).

**Alternative if you want the companion shipped before touching the addon:** the companion can parse
the raw `GuildOSDB.lua` table directly with a Lua-value parser (e.g. Go `gopher-lua`, Python `slpp`)
and build the projection itself. Costs a fragile dependency on the DB's internal shape; the addon-side
projection is the stabler contract. Recommendation: do the addon module — same team owns both.

---

## 6. Component B — the companion (minimal)

Deliberately tiny. One job: get `GOSCOMP1` from disk to the API.

**Behaviour**
1. On start, read a config: WoW `SavedVariables` path + guild upload token + API URL.
2. Watch `WTF/Account/<ACCOUNT>/SavedVariables/GuildOSDB.lua` (fs watcher).
3. On change, read the file, regex-extract `["__companion"] = "GOSCOMP1:..."` (clean because
   EncodeForPrint has no quotes/backslashes — C4/§5).
4. `POST /api/ingest` with `Authorization: Bearer <guild-token>`, body = the raw `GOSCOMP1` string.
5. Show last-sync status in a tray menu. That's the whole UI.

**What it is NOT (Phase 1):** no combat-log tailer, no write-back leg, no auto-`/reload`, no
installer signing, no auto-update. All Phase 2+.

**Sync cadence (C2):** the companion can't flush SavedVariables itself, but the addon can — a
**"Sync now" button writes the projection then calls `ReloadUI()`**, forcing the flush; the companion
uploads the instant the file changes. Passive path: the same write on `PLAYER_LOGOUT`. So officers get
one-click on-demand sync plus automatic sync on logout — no waiting. The only off-limits moment is
mid-pull (a reload drops you from combat and flashes a loading screen).

**Tech pick:** single static **Go binary** (or Tauri if a window is wanted later). Reasons: file-watch
+ HTTP is ~150 lines, no runtime to install, small enough that Windows SmartScreen/AV noise is
minimal, trivial cross-compile for the ~10–15 officer machines. Hand-deliver the `.exe` in Discord.

**Auth:** a per-guild token minted in the web admin by an officer (§12). Scopes every upload to one
`guildKey`; rotatable; revocable. The token is the only secret on the PC.

---

## 7. Component C — the web app

**Stack (decided):** Next.js (App Router) + Postgres + Auth.js Discord provider + Prisma. Boring on
purpose.

**Hosting (decided): one AWS Lightsail instance, everything in a monorepo, one `docker-compose`.**
Covered by existing AWS credits (flat, predictable; ~$10–20/mo instance runs Phase 1's scale for a
long time). Rationale: the bot holds a persistent Discord **gateway WebSocket** — an always-on process
that serverless (Lambda/Vercel Functions) can't host — so it needs a real box; with a monorepo the web
rides the same box rather than splitting the deploy. The bot needs **no public endpoint** (discord.js
receives slash commands / button clicks over the outbound gateway), so only `web` is exposed.

```
  Lightsail instance — docker-compose:
    web       Next.js        (only public port; HTTPS via caddy)
    bot       discord.js     (outbound gateway only, no inbound)
    postgres  container      (pg_dump → Lightsail snapshot; swap to Lightsail Managed DB if ops bite)
    caddy     reverse proxy + automatic HTTPS

  Monorepo (pnpm workspaces + Turborepo):
    /apps/web            Next.js
    /apps/bot            discord.js
    /packages/db         Prisma schema + client (shared web ↔ bot)
    /packages/goscomp    GOSCOMP1 decoder (DecodeForPrint + inflate + JSON) + shared types
    /companion           Go single binary (same repo, built separately)
```
Escape hatch: if web traffic ever spikes, move only `web` to Vercel without touching the bot.

**Domain: `guildos.gg`** (registered outside Route 53 — AWS credits don't cover domain registration).
An A record points at the Lightsail static IP; Caddy provisions HTTPS. App at `https://guildos.gg`,
ingest at `/api/ingest`, Discord OAuth callback at `/api/auth/callback/discord`.

**Login:** Discord OAuth. Scopes: `identify`, `guilds` (to confirm membership in the community's
Discord). On first login create a `DiscordAccount`.

**Data model (Postgres):**
```
Org            (id, name, discordServerId)                      -- the community
Guild          (id, orgId, guildKey "Name-Realm", name, realm) -- one per GuildOS guild
UploadToken    (id, guildId, tokenHash, createdBy, revokedAt)
Member         (guildId, key "Name-Realm", name, class, level, rank,
                avgIlvl, spec jsonb, prefRoles jsonb, professions jsonb,
                attunements jsonb, gear jsonb NULL, lastUpdate)  -- PK (guildId, key)
LootEntry      (guildId, playerKey, itemId, itemName, quality, ts, raid)  -- unique (guildId,playerKey,itemId,ts)
Attendance     (guildId, coreTag, playerKey, raids, attendance25, lastRaid) -- PK (guildId,coreTag,playerKey)
DiscordAccount (discordUserId, username, avatar)
CharacterLink  (discordUserId, guildId, memberKey, status enum(pending,approved), approvedBy) -- unique (discordUserId, memberKey)
Raid           (id, guildId, title, startsAt, size, instanceName,
                discordServerId, discordChannelId, discordMessageId, createdBy, status)
Signup         (raidId, discordUserId, memberKey NULL, status enum(yes,tentative,no),
                role enum(TANK,HEALER,DPS), signedAt)           -- PK (raidId, discordUserId)
```

**Ingest endpoint** `POST /api/ingest` (token-auth): decode `GOSCOMP1` → validate `guildKey` matches
token's guild → upsert:
- `members`: upsert by `(guildId, key)`, **guard `incoming.lastUpdate >= stored.lastUpdate`** — this
  mirrors the addon's own merge rule (`StoreReceivedData`, `DataCollector.lua:513-580`), so two
  officers uploading never clobber fresher data.
- `loot`: insert-ignore on the unique key (append-only, dedup).
- `attendance`: replace rows for the guild's core tags.

**Identity linking flow (§10):** member logs in with Discord → picks their character from the guild
roster dropdown → row goes `pending` → an officer approves. Mirrors the addon's trial/approve pattern
(`TrialTracker`). Low-risk; no in-game proof-of-ownership needed for Phase 1.

**Roster view (ASCII mockup for sign-off):**
```
  Nucleo BR › Guild: Chehul-Firemaw                         [ 148 members · synced 2m ago ]
  ┌────────────┬────────┬───────────────┬──────┬───────┬──────────────┐
  │ Name       │ Class  │ Spec          │ iLvl │ Att%  │ Last loot     │
  ├────────────┼────────┼───────────────┼──────┼───────┼──────────────┤
  │ Chehul     │ Warr   │ Prot 8/42/3   │ 132  │ 92%   │ Cursed Vision │
  │ Fulano     │ Priest │ Holy 23/28/0  │ 128  │ 78%   │ —             │
  └────────────┴────────┴───────────────┴──────┴───────┴──────────────┘
```

**Authz:** officer role in the web derived from the uploaded roster (`member.rank <=
settings.officerMaxRank`, `Core/Core.lua:33-81`) OR granted manually per Org. Officers manage tokens,
approve links, create raids.

---

## 8. Component D — the raid bot (single server)

discord.js bot in the community's one Discord server. The web app is the source of truth; the bot is a
thin front-end that calls the web REST API.

**Commands (officer-gated by Discord role):**
- `/raid create <title> <when> [size] [instance]` → `POST /api/raids` → bot posts the embed.
- `/raid lock <id>` / `/raid delete <id>`.

**Signup embed with buttons** (`[Tank] [Healer] [DPS] [Tentative] [Absent]`). On click →
`POST /api/raids/:id/signups {discordUserId, role, status}` → web resolves `discordUserId` →
`CharacterLink` → `Member`, and returns the enriched row. Bot edits the embed:

```
  ⚔  Karazhan — Sexta 21:00                              15 / 25 signed
  ────────────────────────────────────────────────────────────────────
  TANKS (2)    Chehul   Prot   iLvl132  92%     Beltrano Prot iLvl128 85%
  HEALERS (4)  Fulano   Holy   iLvl128  78%     ...
  DPS (9)      ...
  ────────────────────────────────────────────────────────────────────
  [ 🛡 Tank ]  [ ➕ Heal ]  [ ⚔ DPS ]  [ ❓ Tentative ]  [ ❌ Absent ]
```

`iLvl132 92%` is the differentiator — pulled from the ingested GuildOS data via the Discord↔character
link. If a clicker has no approved link yet, they show as `Chehul (unlinked)` and the bot DMs a link
to claim their character. Graceful degradation, no hard dependency on the companion having run.

---

## 9. Wire contracts summary

- **Companion → web:** `POST /api/ingest`, `Bearer <guild-token>`, body = `GOSCOMP1:` string (§5).
  Server decodes to the projection JSON and upserts (§7). Idempotent; safe to re-send.
- **Bot ↔ web:** REST over a shared bot API key. `POST /api/raids`, `POST /api/raids/:id/signups`,
  `GET /api/raids/:id` (enriched). Web is authoritative; the Discord message is a rendered view kept
  in sync by the bot editing its own message.
- **Manual fallback (no companion):** paste the `GOSCOMP1` string from the addon copy box into a web
  form that hits the same ingest path. Same format, zero install.

---

## 10. Identity & guild model

- `Org` = the BR community. Contains up to ~8 `Guild`s (one per GuildOS `guildKey`).
- Each guild needs **≥1 officer running the companion** (or pasting manually). 10–15 installs total,
  not 150.
- Discord user ↔ character is many-to-one-per-guild via `CharacterLink` (alts allowed). Self-claim +
  officer approve. This is the trust boundary; keep it human in Phase 1.
- Officer status flows from the uploaded roster rank, so the web never needs a separate officer list.

---

## 11. Data authority & conflict

The single rule that keeps Phase 1 tractable: **every domain has exactly one writer** (§4 table).

- Roster/loot/attendance: game writes, web reads. Upload merges are newest-`lastUpdate`-wins per
  member (mirrors `DataCollector.lua:513-580`), so multiple officer uploaders converge.
- Signups: web writes, game never sees them in Phase 1. No import-back = no conflict.
- No field is read-write on both sides. The moment we add write-back (Phase 2), we introduce
  reconciliation — deliberately out of scope now.

---

## 12. Security, privacy, ops

- **Tokens:** per-guild upload token (hashed at rest, `UploadToken.tokenHash`), officer-mintable and
  revocable. Separate bot API key. No player secret ever leaves the PC except the guild token.
- **ToS:** the companion only reads files the game writes and (Phase 2) writes an addon data file —
  the same accepted territory as TSM and Warcraft Logs. It never touches the game process, memory or
  input. Nothing here automates the client.
- **Privacy/LGPD:** the moment player data lives on a server it is personal data. Phase 1 must ship:
  a consent notice on first Discord login, an Org-level data-retention note, and a "delete my
  character data" action. Cheap now, expensive to retrofit.
- **Ops:** web + bot must be up ~24/7 (Fly/Railway). Postgres backups. The real cost is **support**
  ("companion doesn't see my WoW") — bounded because only officers install it.

---

## 13. Build order within Phase 1 (so we can start "brincar" fast)

1. **Addon `CompanionExport.lua`** — projection + `GOSCOMP1` string + copy box. Testable in-game
   alone (paste the string, eyeball it). ~1 module.
2. **Web ingest + roster view** — `/api/ingest` decoder, schema, read-only roster page. Feed it a
   pasted string first; the roster page is already a demo that impresses GMs.
3. **Companion** — Go tray app doing the file-watch upload. Now the roster updates on `/reload`
   hands-free.
4. **Discord login + character linking** — OAuth, self-claim/approve.
5. **Bot single-server raids** — `/raid` + signup buttons + enriched embed. This is the money shot.

Each step is demoable on its own; step 2 alone already gives the community something to react to.

---

## 14. Explicitly deferred (Phase 2+)

- **Live combat-log attendance** — companion tails `WoWCombatLog.txt`, a mini-addon auto-runs
  `/combatlog` on raid entry (required on TBC even with advanced logging on). Real-time presence
  without a reload.
- **Write-back into the game** — web → companion → an `AppData`-style `.lua` the addon loads on
  reload (TSM model), e.g. push the approved raid comp / soft-res into the in-game Calendar. Adds
  reconciliation (§11).
- **Cross-server / multi-community signup** — the eventual Raidify-style differentiator. Needs the
  moderation/trust tooling before host communities will run the bot.
- **Signed, auto-updating installer** — only once adoption justifies the code-signing cost.
- **Gear-detail projection** — full 17-slot gear for a member-detail page (§5).

---

## 15. Decisions

**Locked (2026-08-05):**
1. **Web stack** — Next.js (App Router) + Postgres + Auth.js Discord provider + Prisma. ✅
2. **Companion language** — Go single binary. ✅
3. **Link trust** — self-claim, no in-game proof-of-ownership in Phase 1. (Officer approve is now
   optional polish, not required — self-claim stands on its own for a trusted 5-guild community.) ✅
4. **Hosting** — one AWS Lightsail instance, monorepo, single `docker-compose`, on existing AWS
   credits. Bot needs the always-on box (gateway WS); web rides the same box. ✅

**Still open:**
5. **Addon change now or later** — add `CompanionExport.lua` (stabler contract, my rec), or parse the
   raw `GuildOSDB.lua` in the companion first to avoid touching the addon. Recommendation stands: add
   the module, since the same team owns both and the projection is the stable contract.

---

## References

- Code map: `Modules/Backup.lua:14-56`, `Core/Core.lua:33-81` (DB_DEFAULTS) & `:147-204` (guild key),
  `Core/Utils.lua:141-144` (player key), `Modules/DataCollector.lua:64-115` & `:513-580`,
  `Modules/RaidTracker.lua:158-167` & `:774`, `Modules/LootTracker.lua`, `Modules/SpecChecker.lua:112-129`,
  `Modules/AttunementTracker.lua:202-249`, `Modules/Calendar.lua:248-266`, `Core/Config.lua:23-32`.
- SavedVariables write timing: Warcraft Wiki / Wowpedia — "Saving variables between game sessions".
- Combat log (no loot events; `/combatlog` required on TBC): Warcraft Wiki — COMBAT_LOG_EVENT;
  Warcraft Logs forums — "TBC logging now requires /combatlog".
- TSM Desktop App file-bridge model: support.tradeskillmaster.com — "TSM Desktop Application".
- Warcraft Logs live-logging / companion uploader: warcraftlogs.com/help/start.
