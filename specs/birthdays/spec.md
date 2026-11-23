# Birthdays: the member's own, and the anniversary of joining (issue #428)

## Why

Officers asked (Discord, epic #423 group E, as GRM does) for each member's birthday and the anniversary of
their joining the guild, on the calendar and said on the day. Nothing in the game gives either. ADR-0043.

## What

1. **The member gives it**: day and month, never the year (no age is ever shown or kept). `/gos birthday 14/03`
   (alias `/gos aniversario`), or Settings > Profile > Birthday (a box in the language's order, DD/MM or
   MM/DD; a date only valid the other way round is read so). `/gos birthday off` or unticking **Show my
   birthday to the guild** removes it, here and, by a tombstone, on every other client.
2. **One per person**: set on any character, it shows on every character of the alt group (`db.altLinks`);
   the newest entry of the group wins. Removing it tombstones every character of the group that held one.
3. **Officers correct it**: `/gos birthday <name> <DD/MM | off>`.
4. **The join anniversary** (the rule): it counts from the **current passage** — `MemberHistory`'s last
   passage, when it is open and has a start (officers' clients). A member who left and came back counts
   from the return; earlier passages count for the days in the guild (#425), not for the date. Without a
   history (members' clients, or no passage known) it is `firstSeen`. A date only *seen* at GuildOS's first
   look at the guild (`firstSeenSince`, else the earliest `firstSeen`) is no join and makes no anniversary,
   or everybody would share the install day. One per character that is nobody's alt; the first one is a
   year after the join.
5. **The calendar** (Guild > Calendar) draws both as **virtual** yearly dates, worked out when it draws with
   `Calendar._Occurrences` "yearly" (#358): nothing is written to `db.events` or synced as an event. Two
   filters: Birthdays, Join anniversaries (on by default, per account's settings).
6. **29 February** falls on 28 February in a year with none, the same rule the calendar's yearly dates use.
7. **On the day** (the realm's calendar: `GetServerTime` + `Compat.RealmClock`): a line in the login
   digest at the first login of the day (or in chat when the digest is off); `/gos digest` always shows it.
8. **Guild chat** (optional, an officer's own setting, **off** by default): one line in /g per person, kind
   (birthday, join anniversary: two lines when both fall on the same day) and day, however many officers
   are online. The officer claims it (`claim`), waits 5 s plus up to 3 s, and says it unless another officer
   said it (`said`) or claimed it with a lower name meanwhile. Only a `claim` or `said` from an officer
   counts: a member's would let anybody silence the line. What was said today is remembered, answered to a
   late officer's claim by every officer who knows it, and sent with an officer's backfill (so a late
   officer's own login sync request tells it). **Limit**: an officer who logs in when no officer who heard
   the `said` is online says the line again.
9. **Roster column** Birthday (Columns panel), sorted by the date in the year.
10. **WoW: Forever**: an officer's button on the calendar, **Birthdays to the game's calendar**, puts the next
    birthday of the rest of this month in the game's calendar as a guild announcement, one per click (the
    game takes one new event per click), skipping those already there. Never on its own. The event is at
    noon on the realm's calendar: from 11:50 today's birthdays are left out (the game refuses an event in
    the past), and one the game refuses is left out for the session, so the next click goes on to the next.
11. **The roster card** (#427): `Birthdays:TooltipLine(key)` -> "Birthday: 14/03" or nil.

## Sync

Member domain `birthday` (GUILD channel only, `SyncService.GUILD_ONLY_DOMAINS`), act `set` with
`{ list = { { k, d, m, at, by } | { k, off = true, at, by } } }`, newest `at` (server time) wins, a tie to the
tombstone. A member writes for their own characters only (their key or their alt group); an officer for
anybody; nobody the whole roster lacks is kept. Each client re-sends its own entry 20 s after login; an
officer re-sends all of them (40 an envelope, 2 s apart) on a sync request and `/gos sync`, at most once per
10 minutes and once per hour when nothing changed since its last, and answers an older entry than the one it
holds with its own, once a session per key. The roster's keys an envelope is checked against are worked out
once per roster update. Acts `claim` / `said` carry `{ id, kind = "b" | "j", day = YYYYMMDD }` (no `kind`
is a birthday); a backfill's `said` carries `{ day, list = { { id, kind } } }`.

## Privacy

Day and month only; no year is stored or sent. The member removes it whenever they want (tombstone). Whoever
leaves the guild takes it along (`DropDeparted`).

## Out of scope

The year and an age; an officer button on the member's card (the command does it); join anniversaries in
the game's calendar; the game's calendar on Retail and TBC Anniversary; a guild-wide setting for the /g line.

## API

`GuildOS.Birthdays:For(key)` -> `{ day, month }` or nil; `:TooltipLine(key)`; `:Mine()`; `:Text(b)`;
`:JoinedAt(key)`; `:Today(now)`; `:VirtualEvents(fromT, toT)`.

## Test

Automated: `luajit -e 'ADDON="."' tools/birthdays.lua`. In game: `/gos birthday 29/02` on an alt, open
Guild > Calendar in a February: the main's birthday shows (on the 28th in a year with no 29th) and
`/dump GuildOSDB` shows no new event. Untick "Show my birthday" on one client: it disappears on another. Two
officers with the announcement on, on the day: one line in /g.
