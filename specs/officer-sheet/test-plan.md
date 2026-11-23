# The officer's sheet and card: test plan (issue #427)

Automated:

- `luajit -e 'ADDON="."' tools/officer-sheet.lua`: clients on one guild channel with the real LibSerialize,
  LibDeflate and CommSystem chunking. 800 letters over 16 lines from officer A reach B whole; B's later edit
  wins on A; an older copy re-sent rolls nothing back; a member keeps and reads nothing, and a member's
  forged sheet is dropped; an officer offline at the time gets every sheet from the spaced backfill, which
  does not repeat within 10 minutes unless forced; "ON" (also as an old client sends it) and "OA" read as
  before, "OA" carries no sheet and a sheet inside one is never taken; "ON" and "OA" go over OFFICER only (#430),
  the member's client gets no envelope of a note, a caller asking for GUILD or a whisper sends nothing, an old
  officer's "ON" over GUILD is still read, a member's "ON", a whispered one and an "OA" over GUILD are refused,
  without the channel a note stays local, and a muted rank is told once for sheets, marks and notes together; the card names a main's three alts in
  their class colours with the online ones marked, an alt names its main, officers see the sheet, the notes
  and the game's officer note, members only the alts, the birthday hook; no roster read on a hover.
- `tools/locales.lua`: every new string in the ten languages.

In game (two officers A and B, one member M; a main with three alts, two online):

1. A: right-click M on the roster > Edit officer sheet; paste ~800 letters in several lines; Save.
2. B (online): hover M: the card shows the sheet's first lines, by A; M's card opens the whole sheet.
3. B edits it; A hovers: B's text. B logs off, A edits again; B logs in: A's text.
4. M hovers itself and others: alts and rating, no sheet, no notes, no officer note.
4b. A adds a dated note to M; B sees it; with an addon-message logger on M, no "ON"/"OA" reaches M (#430).
5. Hover the main: the three alts in their class colours, the two online marked "(online)".
6. Shift+click a row: the card stays when the mouse leaves; Esc closes it; Shift+click again also does.
7. Columns > Joined (officer): dates appear for members the history knows; sort by it.
8. A big guild: hovering fast over many rows stays smooth.
