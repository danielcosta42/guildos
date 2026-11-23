# Officers' tools on the notes: join dates, the safe list, returns and nicknames (issue #429)

## Why

Epic #423, group F: what Guild Roster Manager does for officers and GuildOS did not. Write each member's join
date into their note; read the dates officers (or GRM) already wrote there into GuildOS's history; keep some
members out of every bulk removal (#420) whatever the rules say; tell the officers who came back after a long time
away; a nickname per member. ADR-0044.

## What

1. **Join date into a note** (`Modules/NoteDates.lua`), officers only, Leadership > Notes and marks or
   `/gos joindate [<name> | all | import]`:
   - the officer note (default) or the public one; format `dd/mm/yy` (default where the language writes the day
     first), `mm/dd/yy` (enUS, koKR, zhCN, zhTW), `dd.mm.yyyy` or `yyyy-mm-dd`; optional `Joined: ` before it;
   - the date is the member history's current passage (#425). A date GuildOS only saw (its first look at the guild)
     is left out unless the officer turns those on; one read from a note is written;
   - never past 31 bytes; an empty note gets the date, a note with room gets it after a space, a note that already
     says it is left alone; **another date** in the note or **no room** only from a confirmation showing the old and
     the new note (one member: a dialog; the whole guild: "Rewrite those too" lists them first). A note that
     changed after the question is asked again;
   - the whole guild: a plan (who, old note, new note, how), then one write every 2 s; "You are doing that too
     fast" doubles the gap and the last write is re-read (never sent twice); 5 calm writes halve it back;
   - where the game blocks a write from a timer, one write per click of Next; where it forbids an addon to write
     (WoW: Forever, retail, or `ADDON_ACTION_FORBIDDEN`), each click of Next shows the whole new note selected in
     a box, to paste into the game's roster ("copy the text"). A rank that may not edit that note gets nothing.
2. **Dates read from the notes:** the first date in the public note, else the officer note: `dd/mm/yy`,
   `dd/mm/yyyy`, `dd.mm.yyyy` (day first everywhere), `yyyy-mm-dd` (and `/`, `.`), with any `word:` before it
   ("Joined: ...", "Entrou: ..."). Slashed day and month by the client's language or the officer's choice (day
   first, month first); a number above 12 decides alone; impossible days, years before 2004 or after this one are
   no date. A review lists each: *new* (no date in the history), *earlier than GuildOS saw*, *same day*, *later
   than GuildOS saw: not taken*, *history has the exact day*. Only new and earlier are ticked; a click unticks one.
   A day taken is filed as "seen" at its last minute, marked "from a note", so the game's exact line replaces it.
3. **Safe list** (`Modules/MemberMarks.lua`): marked by hand (`/gos safe <name>`, the panel) or with the tag in
   either note (`[safe]` by default, capitals aside; the officers' choice, empty = no tag). Never in a bulk
   **removal or demotion**: not in `BulkActions:Preview`, and skipped at their click if tagged after the preview. A
   promotion still may. `/gos safe` lists them.
4. **Back after N days offline:** the history's roster look (#425) prints one line to the officer, "Back after a
   long time offline (days): Ana (45), ...", once a return; the log's "Back" line as before. N is 30 by default,
   0 turns the line off (panel field).
5. **Nicknames** (`/gos nick <name> [nickname]`, the panel): 24 bytes, on the roster tooltip ("Nickname: ...", and
   the safe list) and, with Chat Tweaks on, in the chat prefix.
6. **Sync of the marks:** officer domain `marks` (officers only, over GUILD): one entry per member and kind, the
   later time winning, a cleared one a tombstone (90 days). Sent at once, and every entry at login and on
   `/gos sync`, 40 per envelope, 2 s apart. Kept on officers' clients only.
7. **Chat Tweaks:** "Nickname (officers)", and "Also in whispers from guild members", "Also in party and raid
   chat" (off by default): the same prefix on a guild member's lines there.

## Out of scope

Hardcore; GRM's other date formats (month names); a note custom to GuildOS; syncing an imported day to the other
officers (each imports on their own); rewriting notes without a confirmation.

## Test

Automated: `luajit -e 'ADDON="."' tools/note-dates.lua`. In game, see `test-plan.md`.
