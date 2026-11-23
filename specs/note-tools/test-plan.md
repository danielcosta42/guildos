# Officers' tools on the notes: in-game test (issue #429)

Automated: `luajit -e 'ADDON="."' tools/note-dates.lua` (parser, 31 bytes, confirmations, the run and its
throttle, forbidden writes, the import, the safe list in the bulk preview and at the click, back after N days,
the marks' sync, the chat prefix). In game, an officer who may edit notes, on a test guild:

1. **One member (Anniversary).** Leadership > Notes and marks, Officer, a member whose history has a date:
   Write date: the officer note reads the date; again: "already says". `/gos joindate <name>` does the same.
2. **Nothing lost.** A member whose note has another date, or 28 letters: Write date opens the confirmation with
   the old and new note; Cancel writes nothing.
3. **Whole guild.** Whole guild: the plan lists each member with old and new note; Start writes one every 2 s.
   Several dozen members: no "You are doing that too fast"; if it shows, the run slows down and goes on.
4. **WoW: Forever / retail.** Whole guild, Start: Next shows "Copy <name>"; each click opens the box with the note
   selected; Ctrl+C and paste in the game's roster.
5. **Import.** Put "Joined: 03/02/24" and "2024-02-03" in two notes; Read dates from notes: both listed as new or
   earlier, ticked; a click unticks one; Take ticked: the member card shows the date "(from a note)".
   Switch Day first / Month first on `03/02/24`: the date read changes.
6. **Safe list.** Put `[safe]` in a member's note; Bulk actions, Remove, rules that would pick them: Preview does
   not list them; Demote neither; Promote does. `/gos safe <name>` marks another by hand: same; `/gos safe`
   lists them; a second officer sees the hand mark after a moment (or after login).
7. **Back after N days.** A member offline 30+ days logs in: within a minute one line "Back after a long time
   offline (days): ..." to each officer, once; set the field to 0: no line.
8. **Nicknames.** `/gos nick <name> Big Bob`: the roster tooltip shows "Nickname: Big Bob"; with Chat Tweaks on,
   their guild lines start with "Big Bob"; with "Also in party and raid chat", their raid lines too.
