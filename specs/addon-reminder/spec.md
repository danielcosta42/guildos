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

Who linked their Discord on guildos.me comes from the site, in the `GOSGILD1` of an **officer's code**
only (`discordLinked`, the site's specs/009): the keys, in the game's form, of the guild's characters a
Discord account registered. `CompanionImport:DiscordLinked` reads it **whole or not at all**: a list
(no other keys), at most 1000 entries, each a string of at most 64 bytes with no `|` or control
character; anything else and the list is refused (nil), since a cut or patched list would call a linked
member "without Discord". Kept in memory only, once per block, as this client's keys in lower case
(`LocalMemberKey`). Never in SavedVariables.

With it:

1. The list holds who is **without GuildOS, without Discord, or both** (who has both is not listed), and a
   row says "no Discord" beside "no GuildOS for N days".
2. A **"which lack"** filter: without GuildOS or Discord (default), without GuildOS, without Discord,
   without either.
3. The reminder follows what the member lacks: without GuildOS only, the GuildOS text (`{discord}` left
   empty); without Discord only, the **Discord text** (its own setting, `reminderDiscordTemplate`, the same
   rules, its own default in every language and its own **Default**); without both, the GuildOS text
   with `{discord}` filled with "Also link your Discord on guildos.me." (put at its end when the text has
   no `{discord}`). One date per member whatever the text: the N days, the gap and the game's throttle
   are the same.
4. On the record (when asked) the note says which: install GuildOS, link Discord, or both.

Without it (an older site, a member's code, no block), everything is as before: only who has no GuildOS,
no filter by lack, no Discord text, and the panel says the game does not know who linked Discord.

## Out of scope

- A record entry that does not count as a warning (the site's door, specs/116, takes warnings only).
- Reminding several members per click, or from a timer.
- Syncing the reminder text or the days among officers (each officer's own).
