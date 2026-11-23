# The officer's sheet and card on the roster (issue #427)

## Why

Officers asked (Discord, epic #423 group D) for a long note on each member kept in the addon, not in the
game's 31-letter officer note, and for a hover card on the roster with the notes, the alts in class colour
and when the member joined, as GRM shows. ADR-0042.

## What

1. **The sheet** (`db.officerNotes[key].sheet = { text, author, ts, rev }`): one text per member, up to 1000
   letters, several lines, any officer edits it (right-click on the roster > Edit officer sheet, or Edit
   sheet on the member card). Kept without "|" and control characters but the line break. Emptying it keeps
   an empty text, so an older one never comes back. The dated notes stay as they are, beside it.
2. **Sync:** officer domain `osheet` on the SyncService, carried only by the game's OFFICER addon channel
   (`CommSystem:SendToOfficers`): a member's client never gets the bytes; a sheet over GUILD or a whisper is
   refused. The game hands OFFICER messages to the ranks that may hear officer chat: an officer for Guild OS
   whose rank cannot hear it gets no sheet, and a rank that hears it but is not a Guild OS officer gets the
   bytes and drops them. WoW: Forever is not checked in game yet: there the channel is off
   (`Compat.OfficerAddonChannel` nil) and a sheet stays on the client that wrote it. The same for an officer
   whose rank may not speak in officer chat (the rank's flags, `Compat.CanSpeakOfficerChat`): the send would
   go nowhere, so the sheet stays here and the officer is told once a session. On the member card the Edit
   sheet button is made once, and the redraws a backfill brings are coalesced (one per 4 s, only when the shown
   member's sheet changed). A write takes revision max(server time, last + 1): the newer edit wins on every
   client, a tie settles the same everywhere. An officer re-sends every sheet at its stored revision on the
   answer to a sync request (at most once per 10 minutes) and on `/gos sync`, 2 sheets per envelope, 3 s
   apart (#324). "OA" no longer carries the sheet.
6. **The dated notes and tags (issue #430, ADR-0045):** "ON" (one note) and "OA" (all notes and tags) go the same
   way as the sheet: only over OFFICER (`CommSystem:SendToOfficers`; `CommSystem.OFFICER_TYPES`, the rule
   `OFFICER_CHANNEL_DOMAINS` is for envelopes), never over GUILD or a whisper, whoever calls. Without the channel,
   or for a rank that may not speak in officer chat, the note stays on this client, with the same warning once a
   session (one warning for sheets, marks and notes). Received over OFFICER from an officer only; over a whisper
   never. **Transition:** "ON" over GUILD from an officer (a client before #430) is still read, so an old
   officer's note is not lost; reading it exposes nothing more, the old client already sent it there. "OA" over
   GUILD is not read. The GUILD "ON" goes in the next version. Until then an officer on an old client does not
   get the notes new clients write.
3. **The card** (hover on a roster row), added lines:
   - everyone: the alts of a main, or the main and the other alts of an alt, each in its class colour,
     "(online)" in green on those online, a character not in the roster greyed; the Mythic+ rating and
     keystone on retail; the birthday when `GuildOS.Birthdays:TooltipLine(key)` exists (#428) and gives one;
   - officers only: joined (date, "~" when only seen by Guild OS) and days in the guild (#425), the game's
     officer note (when the rank may read it), the first 4 lines / 240 letters of the sheet, the 2 newest
     Guild OS notes.
   Everything comes from an index the roster builds once per refresh (alt links both ways, every roster
   line's name, class and online): a hover reads no roster line.
4. **Shift+click** on a row keeps the card open where it was; Escape, Shift+click on the same member, or
   Shift+click on another (which moves it) lets it go. A plain click still opens the member card.
5. **Joined column** (officers): the current passage's start from the member history, sortable.

## Privacy

Free text about people: on officers' clients only, never in the companion export, never on the site; the
sheet, the marks (#429) and the dated notes (#430) never reach a member's client.

## Out of scope

Writing to the game's officer note; any hook on Blizzard's roster or communities frame; the birthday itself
(#428); a sheet history (only the newest text is kept).

## Test

See `test-plan.md`.
