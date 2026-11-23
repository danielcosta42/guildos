# Without GuildOS: the officers' list and the reminder (issue #422)

## Why

Officers asked (Discord, suggestions, "Discipline members not on Discord or using guildos") for a way to
see who in the guild does not use GuildOS or Discord, and to nudge them. Locking the guild bank by addon
is not possible (the game's API does not allow it). Related idea: #359.

## What

**Leadership > Without GuildOS** (a sub-tab of the Leadership tab, next to Bulk actions). Officers only.

1. **The list:** every guild member this client never heard GuildOS from: no `lastUpdate` in
   `db.members`, the same test as the roster's "no GuildOS" and the bulk actions' rule. Oneself is never
   listed. Each row: name, rank, level, **how long** ("no GuildOS for N days", counted from the day this
   client first saw them in the roster, `firstSeen`), online or days offline, and when they were last
   reminded. Longest without GuildOS first, then by name.
2. **Filter:** part of the name, rank, online only, hide the ones reminded within the officer's days.
3. **Remind** (one button per row) whispers the reminder to **that member only, on that click**. The text is
   the officer's (one line, at most 200 bytes, `{name}` and `{guild}` filled, cut at 255); a default in
   every language until one is written; **Default** puts it back.
4. **At most once every N days per member** (N the officer's, 1 to 90, default 7). The date of a reminder
   goes to the other officers (sync domain `reminder`, officer-authoritative, newest date kept), so a
   member is not whispered by each officer in turn. Dates are kept 90 days.
5. **The server's whisper limit (#393, "You are doing that too fast").** Whispers go out only on a click,
   never from a timer or a queue: WoW: Forever drops a timer's whisper anyway (`Compat.NeedsClick`).
   Between two reminders of a client at least 10 s (six a minute at most). After the game's
   `ERR_GENERIC_THROTTLE` no reminder for 60 s, and a reminder sent within the 3 s before it did not go:
   its date is rolled back, nothing is synced or filed, and the officer is told to try again in a minute.
   The panel says what holds the next reminder and turns the buttons back on when it passes.
6. **On the record (#402), when the officer asks:** with "Also file it on the disciplinary record" ticked
   (off by default, kept per officer) each reminder that went is filed as a warning of reason "other",
   note "Reminded to install GuildOS (whisper).". The record holds warnings only, so it **counts toward
   the ladder's step**; the box says so.
7. Who is offline, has GuildOS by now, left the guild, or the chat is locked: nothing is whispered, and
   the chat says why.

## Discord

Whether a member linked their Discord on guildos.me is **not** in the `GOSGILD1` the site sends down
(only a count, in `activation.members`), so the game cannot list "without Discord". The panel says so.
For it, the site would send, per member of the guild in the officer's block, the characters whose account
has a Discord link (e.g. `discordLinked = [key, ...]`, the keys in the game's form, officer code only),
and this list would gain a "without Discord" filter and the reminder a `{discord}` hint.

## Out of scope

- A record entry that does not count as a warning (the site's door, specs/116, takes warnings only).
- Reminding several members per click, or from a timer.
- Syncing the reminder text or the days among officers (each officer's own).
