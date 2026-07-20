# Guild OS — Tier 3 (curated) — Design Spec

- **Data:** 2026-07-20
- **Status:** Autopilot (user delegated build). Branch `feat/tier3`, NOT pushed until user validates.
- **Scope:** curated 4 of the "toques espertos" tier: Mentions/watch-words, `!note`, level-query roster filter, internal LFG board.
- **Origin:** competitive gap analysis (GuildKit, GRM, GCM). Tier 1 + Tier 2 already merged/published.

## Global conventions
BCC 20506; `C_Timer`/`C_GuildInfo`/`/who` etc. via `BRutus.Compat.*`. luacheck 0/0 gate. Pure logic via `/gos selftest`. Strings in 5 locales. Colors from `BRutus.Colors`. Rule 10. Commits Conventional; **no AI attribution**. Each new synced/stored dataset needs cap/prune.

---

## Feature 1 — Mentions / watch-words

**New `Modules/Mentions.lua`.** Alerts you when your name — or a configured watch-word — appears in guild/officer chat.
- Hook `CHAT_MSG_GUILD` (+ `CHAT_MSG_OFFICER`, config). On a line, if it contains the player's own name (whole-word, case-insensitive) OR any `db.mentions.watchWords`, fire an alert: `BRutus:Print` a highlighted line + optional `PlaySound`, and append to a capped recent-mentions log (100).
- **Config** `db.mentions = { enabled=true, ownName=true, watchWords={}, sound=true, guild=true, officer=true }`. Own-name watching on by default; per-message cooldown so a single line alerts once. Don't alert on your OWN messages.
- **UI/commands:** `/gos mentions` opens/prints the recent-mentions log; `/gos mentions add|remove|clear <word>` manage watch-words; a toggle. (Keep UI light — a small popup list like Bulletin, or just a printed log + commands.)
- **Pure logic (tested):** `Mentions:_Match(msg, ownName, watchWords, watchOwn) -> matchedTerm|nil` — whole-word, case-insensitive.
- **Esforço:** S. **No sync** (personal).

---

## Feature 2 — `!note` (self public-note via chat)

**New `Modules/NoteCommand.lua`** (or extend GuildManager). Lets a member set their own guild **public note** by typing `!note <text>` in guild chat — applied by any client that has note-edit permission (officers), since on Classic/TBC members usually can't self-edit notes.
- Hook `CHAT_MSG_GUILD`; parse `!note <text>` (and `!note clear`). The **local client applies it IF it can edit public notes** (`CanEditPublicNote()` / permission) — set the sender's public note via `GuildRosterSetPublicNote(index, text)` (Compat-guarded), capped at 31 chars. Deterministic single-applier (lowest-name eligible client wins, mirroring the welcome-coordination pattern) to avoid redundant sets; per-name cooldown.
- **Config** `db.noteCommand = { enabled=true }`.
- **Pure logic (tested):** `NoteCommand:_Parse(msg) -> text|nil` (matches `^!note%s+(.+)$`, trims, 31-char cap; `!note clear` → empty).
- **Viabilidade 20506:** `GuildRosterSetPublicNote` exists on BCC; guard via Compat and check `CanEditPublicNote()`. If the client lacks the API/permission, it's a no-op (fail-safe).
- **Esforço:** S. **No new sync** (uses the game's own note propagation).

---

## Feature 3 — Level-query roster filter

**New pure `Modules/LevelQuery.lua`** + wire into the roster search. Lets the roster search box accept expressive level filters: `19`, `60-70`, `>=60`, `<10`, and comma-lists like `19, 60-70`.
- **Pure logic (tested):** `LevelQuery:Parse(query) -> matcherFn | nil` — returns a predicate `function(level) -> bool`, or nil if the query isn't a level query. Supports exact, ranges `lo-hi`, comparisons `>= <= > <`, and comma-separated OR-lists. Returns nil for non-level text (so normal name search still works).
- **Wire:** in the roster filter (`RosterFrame` `BuildMemberList`/filter path), if `LevelQuery:Parse(searchText)` returns a matcher, filter members by `matcher(memberLevel)` instead of (or in addition to) name-substring. A small hint near the search box: "tip: 60-70, >=60".
- **Esforço:** S-M (pure parser is easy; the wire into the existing roster filter is the care point — must not break normal name search).

---

## Feature 4 — Internal LFG board ("available now")

**New `Modules/LFGBoard.lua` + a board UI.** Members self-declare "available for a group" with a short note; the guild sees a live board. Distinct from the mesh RecruitBeacon (which is guild-vs-guild recruiting).
- **Data/sync:** `db.lfgBoard = { [nameKey] = { name, note, role?, ts, ttl } }`. A member broadcasts their OWN entry (member-write, low-harm — like an RSVP/self-claim); every client stores it. Auto-expire after `ttl` (default 90 min) — `_IsActive(entry, now)`. Use a dedicated CommSystem message type `LFG` (member self-declare; receivers just store their own copy, keyed by sender; a member can only set their OWN key — validate `sender == entry.name`).
- **Commands:** `/gos avail [note]` sets you available with an optional note; `/gos avail off` clears; `/gos lfgboard` (or the board opens) shows who's available. (Avoid `/gos lfg` — taken by the recruiting inbox.)
- **UI:** a self-contained board window (Bulletin/Analytics pattern): list of active entries (name · role/class · note · "for Nm"), a "Set me available" row (note box + duration), and an "I'm available / off" toggle.
- **Pure logic (tested):** `LFGBoard:_IsActive(entry, now)`; `LFGBoard:ActiveList(store, now)` (filters expired, sorted newest).
- **Esforço:** M (the sync + board UI). **Cap/prune** expired entries.

---

## Sequencing
`#1 Mentions → #2 !note → #3 level-query → #4 LFG board`. Each: own plan + SDD build (subagents, review/fix, luacheck 0/0). Branch `feat/tier3`, no push until validated.

## Risks / human-verify (no client here)
- Chat hooks (Mentions, !note) — verify in-game; keep them light (no per-line roster loops).
- `!note` — verify `GuildRosterSetPublicNote`/`CanEditPublicNote` on 2.5 (Compat-guard; fail-safe no-op if absent). Deterministic single-applier so one officer sets it.
- Level-query wiring must NOT break normal name search (parser returns nil for non-level text).
- LFG board member-write sync: validate `sender == entry.name` so a member can only set their own availability.
