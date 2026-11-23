# Member history: "was a member from X to Y, N days" and the full log (issue #425)

## Why

Officers asked (Discord, epic #423 group C) to know, when they re-invite somebody, that the person was a
member before, when, for how long and how they went. The Roster Log forgets after 90 days, `firstSeen` is
dropped when somebody leaves, and no client gives a guild join date. ADR-0039.

## What

1. **History** (`db.memberHistory[key] = { stints, ranks }`), on officers' clients only, outside the log's
   90-day pruning. A passage: join, departure, how (left, removed by whom, or "gone" when only the roster
   showed it) and whether a date is only "seen by GuildOS". A rank change: when, from, to, by whom.
2. **Sources:** the Roster Log's events (live and synced), a diff of the whole roster against the one last
   seen (at most once a minute, 45 s after login, whole roster only), the other officers' records
   (`audit` domain, act `hist`, append-only with an id), and once, a migration of the log's events,
   `firstSeen` and `foundingJoins`.
3. **Since your last login:** the first diff of a session prints, once, who joined, who left or was removed
   and who changed rank while the officer was away.
4. **The warning** "Ana was a member: 03/02/2025 to 10/06/2025 (127 days), removed by Bob." (several passages:
   the count and the days in all) shows to officers at a manual invite (`BanList:HoldInvite`, never holding
   it; in the alliance-ban dialog when that one holds it), at the join line, and at a whisper (once a session).
5. **The log** gains: Rejoined (a join with `rejoin`), Gone, Level (milestones by default: every 10 and the cap;
   all or off with the button), Note, Officer note, Back (after 30+ days offline). A search box filters by
   member, officer, detail or the action's word. The diff's lines stay on this client.
6. **Export** (`/gos export log|former [csv|tsv|discord]`, and the export chooser), officers only:
   `log` = Date, Action, Member, Detail, By; `former` = Name, FirstJoined, LastLeft, How, By, Stints,
   TotalDays, Estimated.
7. **Member card** (officers): MEMBERSHIP with every passage and the last five rank changes.
8. **Pug Inspector:** an ex-member shows when they left and their days in the guild.
9. **Days** are calendar days on the client's dates (time zone, summer time, year turn).

## Ceiling

10 passages and 15 rank changes a member (oldest dropped), 4000 keys (former members who left longest ago
dropped; present members never). Bound ~7.6 MB; a 1000-member guild over three years stays near 1 MB.

## API (for the hover card, join anniversaries, dates in notes)

`GuildOS.MemberHistory:Stints(key)`, `:Ranks(key)`, `:JoinedAt(key)` (time, estimated?), `:TenureDays(key)`
(days, passages), `:LastLeft(key)`, `:IsFormer(key)`, `:Describe(name)`, `.DaysBetween(a, b)`.

## Out of scope

Reading another addon's data; renames by GUID; a full-history sync between officers (only the last 25
records each); syncing anything of this to non-officers.

## Test

Automated: `luajit -e 'ADDON="."' tools/member-history.lua`. In game (officer): have an alt leave while you are
offline, log in after a minute: the chat says it once. Invite the alt: the chat shows dates and days. The
alt joins: the log says Rejoined and the chat repeats the past. Export `former` and `log` and paste in
Google Sheets: English headers.
