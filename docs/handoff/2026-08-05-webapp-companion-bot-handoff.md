# Handoff — GuildOS Web Companion (Phase 1): web app + Go companion + Discord bot

This document is written for a **fresh agent starting the new repo** that holds the web app,
the desktop companion and the Discord bot. The WoW addon side (data export) is **already built and
tested** in the `guildos` addon repo — see "What's already done" at the end. Your job is everything
*outside* the game.

Full design rationale lives in the addon repo at
`docs/superpowers/specs/2026-08-05-webapp-phase1-design.md`. This handoff is the actionable subset
plus the exact wire contract and a real test fixture so you can build the ingest path test-first,
before you ever touch WoW.

---

## 1. Mission & Phase 1 scope

Bring GuildOS guild data out of the game onto the web, logged in with Discord, so a raid signup
posted by a bot shows **each signee's item level, spec and attendance** — data no other signup tool
has, because it comes straight from the addon. First tester: a BR community of 5 guilds / 150+
players. Timed for the Classic+ wave.

**In scope (Phase 1):**
- Web app, Discord OAuth login, roster + loot + attendance views.
- Ingest of the addon's `GOSCOMP1` payload (§3) → Postgres.
- A tiny Go companion that watches the WoW SavedVariables file and POSTs the payload.
- A single-server Discord bot: create raids, collect signups, enrich each signup with the linked
  character's GuildOS data.

**Out of scope (Phase 2+):** cross-server signup, live combat-log attendance, writing anything back
into the game, signed/auto-updating installer. Don't build these yet.

---

## 2. Locked decisions

| Area | Decision |
| --- | --- |
| Web stack | Next.js (App Router) + Postgres + Auth.js (Discord provider) + Prisma |
| Hosting | **One AWS Lightsail instance**, monorepo, single `docker-compose` (AWS credits) |
| Bot | discord.js, same box, **no public endpoint** (gateway WS is outbound-only) |
| Companion | **Go** single static binary |
| Identity | Discord OAuth; character link by **self-claim** (no in-game proof in Phase 1) |
| Authority | game = source of truth for roster/loot/attendance; web = source of truth for signups; **no bidirectional field** |

Only `web` is publicly exposed (for the OAuth redirect). The bot receives slash commands / button
clicks over the outbound Discord gateway, so it needs no inbound port.

---

## 3. THE WIRE CONTRACT — `GOSCOMP1` (read this carefully)

The addon produces a single string per guild. The companion ships it verbatim to your API; **your
server decodes it.** The companion never parses it.

### 3.1 Encoding pipeline (addon side — already implemented)

```
projection(table) → JSON → LibDeflate:CompressDeflate (raw DEFLATE)
                         → LibDeflate:EncodeForPrint    (custom 6-bit printable)
                         → "GOSCOMP1:" .. encoded
```

### 3.2 Decode recipe (your side)

```
strip "GOSCOMP1:" prefix
  → DecodeForPrint  (custom base64: little-endian, alphabet a-zA-Z0-9 then "(" ")")
  → inflateRaw      (raw DEFLATE, no zlib header — Node: inflateRawSync / zlib wbits -15)
  → JSON.parse
```

`EncodeForPrint` is **not** standard base64 — it is LibDeflate's own little-endian 6-bit codec. The
alphabet is index 0-63 = `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()`. The
following TypeScript decoder is a **verified** port (checked byte-for-byte against LibDeflate's
`DecodeForPrint` on real payloads). Put it in `/packages/goscomp`:

```ts
import { inflateRawSync } from "node:zlib";

const ALPHABET =
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()";
const D = new Int8Array(128).fill(-1);
for (let i = 0; i < ALPHABET.length; i++) D[ALPHABET.charCodeAt(i)] = i;

/** Port of LibDeflate:DecodeForPrint — little-endian custom base64. */
function decodeForPrint(s: string): Buffer {
  s = s.trim();
  const out: number[] = [];
  let i = 0;
  const n = s.length;
  while (i + 4 <= n) {
    const x1 = D[s.charCodeAt(i)], x2 = D[s.charCodeAt(i + 1)],
          x3 = D[s.charCodeAt(i + 2)], x4 = D[s.charCodeAt(i + 3)];
    if ((x1 | x2 | x3 | x4) < 0) throw new Error("bad GOSCOMP1 char");
    i += 4;
    let cache = x1 + x2 * 64 + x3 * 4096 + x4 * 262144; // 24 bits, LSB first
    const b1 = cache % 256; cache = (cache - b1) / 256;
    const b2 = cache % 256; const b3 = (cache - b2) / 256;
    out.push(b1, b2, b3);
  }
  let cache = 0, bits = 0;
  while (i < n) {                       // 1 or 2 leftover bytes → 2 or 3 chars
    const x = D[s.charCodeAt(i)];
    if (x < 0) throw new Error("bad GOSCOMP1 char");
    cache += x * 2 ** bits; bits += 6; i++;
  }
  while (bits >= 8) { const b = cache % 256; cache = (cache - b) / 256; out.push(b); bits -= 8; }
  return Buffer.from(out);
}

export function decodeGoscomp(payload: string): GoscompPayload {
  const trimmed = payload.trim();
  if (!trimmed.startsWith("GOSCOMP1:")) throw new Error("missing GOSCOMP1 prefix");
  const raw = decodeForPrint(trimmed.slice("GOSCOMP1:".length));
  return JSON.parse(inflateRawSync(raw).toString("utf8"));
}
```

The Go companion does **not** need this codec — it only extracts and forwards the opaque string.

### 3.3 Payload schema

Top-level object:

| field | type | notes |
| --- | --- | --- |
| `fmt` | `"GOSCOMP1"` | format tag |
| `v` | int | schema version (`1`) |
| `guildKey` | string | `"<GuildName>-<Realm>"` — the tenant key; must match the upload token's guild |
| `guildName`, `realm` | string | |
| `exportedAt` | int | Unix epoch (server time) of this export |
| `exportedBy` | string | uploader character key |
| `addonVersion` | string | |
| `count` | int | `members.length` |
| `members` | array | see below |
| `loot` | array | see below |

`members[]`:

| field | type | notes |
| --- | --- | --- |
| `key` | string | `"Name-Realm"` — **the identity key everywhere**; PK with guild |
| `name`, `class`, `race` | string | class is the WoW token (`WARRIOR`, `PRIEST`, …) |
| `level` | int | |
| `rank` | string | guild rank name (from the live roster) — may be absent if roster wasn't loaded |
| `rankIndex` | int | 0 = GM. **Officer = `rankIndex <= officerMaxRank`** (default `officerMaxRank = 1`) |
| `avgIlvl` | int | |
| `lastUpdate` | int | Unix epoch; **use as the merge guard** (newest wins) |
| `spec` | object\|absent | `{ tree, treeIndex, points:[t1,t2,t3] }` |
| `prefRoles` | array\|absent | self-declared roles; **normalize defensively** (may be `["TANK"]`) |
| `professions` | array | `[{ name, rank }]` (empty array if none) |
| `attunements` | array | `[{ short, complete:bool, progress:0..1 }]` |
| `att25` | number | 25-man attendance %, `0..100` |

`loot[]`: `{ playerKey, player, itemId:int, itemName, quality:int(0-5), timestamp:int, raid }`.

**Notes for a robust ingest:**
- Absent optional keys (`rank`, `spec`, `prefRoles`) simply won't be present — code for `undefined`.
- Only **current** guild members are included; ex-members with stale cached data are excluded by the
  addon.
- `itemName` can contain quotes/tabs (properly JSON-escaped) — don't assume it's clean.

### 3.4 Test fixture (build the decoder + ingest against this, no game needed)

A real payload emitted by the addon (2 members, 1 loot row, an ex-member deliberately excluded, and
an item name with embedded quotes to exercise escaping):

```
GOSCOMP1:fp5tpQnmqu8VkiFofL)kGClG6UfHwaf2U9qPhCtgalSJtDCOlDfF37mjrWMwUV5uu8BEZm)EoVX4556IxatLqxWIzUddJg6YCy7RfY8fWz8BlRZKGEW00p9GWak(VXJvG6NyrS4VJwyT(rS4j(o0R1fGckSThvDqBSOflsstWQkn69gOcpZZHLPvLsWcSyRPgU4Ct9MnZ6j2Dy07LVJlRGl)WHj5v2VwMZPp6nkkmyIl(GsXdWYyFljnD(Qu0ldV448IC4v0mYzyxQwc0mYEoz5cgAwvjKXIFJznaAhBTrBHmlrfSaTODJg7e67eGQjvDggCH8pJkALjdvFSHAZoahQLVdz8t7NlpjXrnWVz72Hlh6FlPk4kYHPsE2XkLWEquSVBWXwmkQzFHtaw)iCf6K32KR6ypsP2GNqUaggH0USz04p8SzC)SzD68pV55(rt4)LcFrlp)E(7h44p2XTFa4FlaUs)hQL8c9DPpAW)q)7I2whUH2uUiNGkk(udJGxlrKa5tVBAl1ABdMlL8ZyD9YkroXDUHV1(NdC6gMWcQLDzATPcYhSL9IGgWT0s9RAUuyp3GiRqbvwUQSdSUTGTTplU)DpY(5yt9N465rRqZV3Dn86)3mkjRlW52)26LyB7tyxF2PORbpUAZSvpT2JwhGlveW662L)(
```

`decodeGoscomp(fixture)` must yield exactly (pretty-printed):

```json
{
  "fmt": "GOSCOMP1", "v": 1, "count": 2,
  "guildKey": "Nucleo BR-Firemaw", "guildName": "Nucleo BR", "realm": "Firemaw",
  "exportedAt": 1754400000, "exportedBy": "Chehul-Firemaw", "addonVersion": "0.45.0",
  "members": [
    { "key": "Chehul-Firemaw", "name": "Chehul", "class": "WARRIOR", "race": "Orc", "level": 70,
      "rank": "Guild Master", "rankIndex": 0, "avgIlvl": 132, "lastUpdate": 1754390000,
      "spec": { "tree": "Protection", "treeIndex": 3, "points": [8, 42, 3] },
      "prefRoles": ["TANK"], "professions": [{ "name": "Blacksmithing", "rank": 375 }],
      "attunements": [ { "short": "KARA", "complete": true, "progress": 1 },
                       { "short": "SSC", "complete": false, "progress": 0.5 } ],
      "att25": 92 },
    { "key": "Fulano-Firemaw", "name": "Fulano", "class": "PRIEST", "race": "", "level": 70,
      "rank": "Raider", "rankIndex": 4, "avgIlvl": 128, "lastUpdate": 1754380000,
      "spec": { "tree": "Holy", "treeIndex": 2, "points": [23, 28, 0] },
      "professions": [],
      "attunements": [ { "short": "KARA", "complete": true, "progress": 1 },
                       { "short": "SSC", "complete": false, "progress": 0.5 } ],
      "att25": 78 }
  ],
  "loot": [
    { "playerKey": "Chehul-Firemaw", "player": "Chehul", "itemId": 29011,
      "itemName": "Cursed \"Vision\"", "quality": 4, "timestamp": 1754300000, "raid": "Kara\tzhan" }
  ]
}
```

Make this a golden test in `/packages/goscomp`.

---

## 4. Monorepo layout to create

```
/apps/web            Next.js (App Router) — the only public service
/apps/bot            discord.js — outbound gateway only
/packages/db         Prisma schema + generated client (shared web ↔ bot)
/packages/goscomp    the decoder above + payload types + golden test
/companion           Go single binary (built separately; not part of the pnpm graph)
docker-compose.yml   web + bot + postgres + caddy
```
pnpm workspaces + Turborepo. Caddy terminates TLS for `web` and reverse-proxies it.

---

## 5. Postgres data model (Prisma)

```
Org            (id, name, discordServerId)
Guild          (id, orgId, guildKey "Name-Realm", name, realm)
UploadToken    (id, guildId, tokenHash, createdBy, revokedAt?)
Member         (guildId, key "Name-Realm", name, class, level, rank?, rankIndex?,
                avgIlvl, spec Json?, prefRoles Json?, professions Json,
                attunements Json, att25 Float, lastUpdate BigInt)   @@id([guildId, key])
LootEntry      (guildId, playerKey, itemId, itemName, quality, ts BigInt, raid)
                @@unique([guildId, playerKey, itemId, ts])
DiscordAccount (discordUserId, username, avatar)
CharacterLink  (discordUserId, guildId, memberKey, status: pending|approved, approvedBy?)
                @@unique([discordUserId, memberKey])
Raid           (id, guildId, title, startsAt, size, instanceName,
                discordServerId, discordChannelId, discordMessageId, createdBy, status)
Signup         (raidId, discordUserId, memberKey?, status: yes|tentative|no,
                role: TANK|HEALER|DPS, signedAt)                    @@id([raidId, discordUserId])
```

Attendance is folded into `Member.att25` (no separate table) — the addon already computes it.

---

## 6. Ingest endpoint

`POST /api/ingest`, `Authorization: Bearer <guild-upload-token>`, body = the raw `GOSCOMP1:` string
(text/plain is fine).

1. Resolve token → `Guild`. Reject if revoked.
2. `decodeGoscomp(body)`. Reject if `payload.guildKey !== guild.guildKey` (token/tenant mismatch).
3. Upsert `Member` by `(guildId, key)`, **guarded by `lastUpdate`**: skip a row whose incoming
   `lastUpdate < stored.lastUpdate`. (This mirrors the addon's own merge rule, so two officers both
   running the companion converge instead of clobbering each other.)
4. `LootEntry`: insert-ignore on the unique key (append-only, dedup).
5. Idempotent — re-POSTing the same payload is a no-op. Safe to retry.

Officer status is derived, never stored separately: `rankIndex <= officerMaxRank` (default 1).

---

## 7. Discord OAuth + self-claim linking

- Auth.js Discord provider, scopes `identify` + `guilds`. First login creates a `DiscordAccount`.
- **Self-claim:** logged-in user picks their character from the guild roster (populated by ingest) →
  `CharacterLink` row. For a trusted 5-guild community, self-claim is sufficient; an optional
  officer-approve step (`status: pending → approved`) is nice-to-have, not required for Phase 1.
- Alts: allow multiple `CharacterLink` per Discord user within a guild.

---

## 8. Discord bot (single server)

discord.js, gateway only. The web app is the source of truth; the bot is a thin front-end.

- Slash (officer-gated by Discord role): `/raid create <title> <when> [size] [instance]`,
  `/raid lock <id>`, `/raid delete <id>` → call the web REST API.
- Signup embed buttons: `[🛡 Tank] [➕ Heal] [⚔ DPS] [❓ Tentative] [❌ Absent]`. On click →
  `POST /api/raids/:id/signups {discordUserId, role, status}`. The web resolves
  `discordUserId → CharacterLink → Member` and returns the enriched row; the bot edits its own
  message to show e.g. `Chehul — Prot — iLvl132 — 92%`.
- Unlinked clicker → show `name (unlinked)` and DM them the claim link. Never hard-fail.

---

## 9. Go companion (minimal)

One job: get `GOSCOMP1` from disk to the API.

1. Config: WoW SavedVariables path + guild upload token + API URL.
2. Watch `.../WTF/Account/<ACCOUNT>/SavedVariables/GuildOSDB.lua` (fsnotify).
3. On change, read the file and extract the payload with a regex — it is stored on one clean line as
   a printable string (no quotes/backslashes to fight):
   ```
   \["__companion"\]\s*=\s*"(GOSCOMP1:[a-zA-Z0-9()]+)"
   ```
4. `POST /api/ingest` with the bearer token, body = the captured string.
5. Tray menu with last-sync status. That's the whole UI.

Do **not** build: combat-log tailer, write-back leg, auto-reload, installer signing, auto-update
(all Phase 2). Hand-deliver the `.exe` to the ~10-15 officers who need it.

### 9.1 Presence heartbeat (so the game can show/hide the Web Sync button)

The addon shows its one-click **Web Sync** button only when it detects the companion. Detection works
the TSM AppHelper way: the companion maintains a tiny **side addon** the client loads at login/reload.
On first run and every ~60s while running, the companion ensures this exists:

```
Interface/AddOns/GuildOS_Companion/
  GuildOS_Companion.toc        # static, write once:
      ## Interface: 20506
      ## Title: Guild OS Companion Link
      ## Notes: Auto-generated by the Guild OS companion app. Do not edit.
      ## DefaultState: enabled
      Heartbeat.lua
  Heartbeat.lua                # overwritten every ~60s:
      GuildOSCompanionLink = { v = 1, app = "0.1.0", heartbeat = 1754400000, os = "windows" }
```

- `heartbeat` = the PC's **local** Unix epoch at write time (`time.Now().Unix()`). The WoW client and
  the companion run on the same PC, so the addon compares it against its own `time()` with no clock
  skew. The addon treats the companion as "connected" when the heartbeat is within **900 s** at load —
  keep the write interval well under that (60 s recommended).
- **Load-time only:** the client reads this file just at login / `/reload`, so the button state
  reflects "companion running as of the last load", not live. This is expected; don't try to make it
  live.
- The companion generates the whole folder itself (toc + Heartbeat.lua) — nothing to ship in the
  addon repo. Keep the `.toc` bytes exactly as above (the `## Interface:` must match the client;
  20506 is the TBC Anniversary build the addon targets).

---

## 10. Build order (each step demoable on its own)

1. `/packages/goscomp` decoder + golden test against the §3.4 fixture. **Start here — no infra
   needed.**
2. `/apps/web` ingest endpoint + Prisma schema + a read-only roster page. Feed it the fixture string
   via `curl` first; the roster page already impresses GMs.
3. `/companion` Go tray app → roster now updates on `/reload` hands-free.
4. Discord OAuth + self-claim linking.
5. Bot single-server raids + enriched embed. This is the payoff.

---

## 11. What's already done on the addon side (you don't build this)

In the `guildos` addon repo, branch `claude/web-app-roster-raids-loot-nrvom8` (PR #3):

- **`Modules/CompanionExport.lua`** produces the `GOSCOMP1` string (validated end-to-end:
  encode → deflate → EncodeForPrint → DecodeForPrint → inflate → JSON.parse).
- The payload is written to `GuildOSDB.__companion` on `PLAYER_LOGOUT` (the last event before the
  SavedVariables flush).
- Officer slash commands: **`/gos websync`** (stamps the payload and forces a flush via `ReloadUI`,
  for on-demand sync) and **`/gos webstring`** (shows a copy box for manual paste when there's no
  companion).
- Registered in `GuildOS.toc` and `Core/Core.lua`.

**To get more/real test data:** in-game, an officer runs `/gos webstring` and copies the string, or
reads `GuildOSDB.__companion` from the SavedVariables file after a `/reload`. Every such string
decodes with the §3.3 schema.

**Contract stability:** if the addon projection changes, `v` will bump and this handoff's schema will
be updated in the addon repo's spec. Code defensively against unknown/missing fields regardless.

---

## 12. Constraints you must respect (from the game side)

- The game is air-gapped — no HTTP from WoW. The companion (files on disk) is the only bridge.
- SavedVariables is flushed only on logout / `/reload`, never mid-play, never on crash. So ingest is
  event-driven off the file change, not real-time. This is expected; don't design for live push.
- `"Name-Realm"` is the identity key end to end. Timestamps are Unix epoch. Keep both verbatim.
