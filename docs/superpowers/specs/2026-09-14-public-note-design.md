# Public note writes through the API the client actually has

Issue: danielcosta42/guildos#5 · Epic: #4 · Type: bug

Condensed spec + plan + tasks.

## 1. Problem

`Compat.SetGuildPublicNote` (`Core/Compat.lua`) returned `false` without a word when the global
`GuildRosterSetPublicNote` was missing. That global is not in the 2.5.6 client's API list; the documented call
is `C_GuildInfo.SetNote(guid, note, isPublic)` (`classic_anniversary_GuildInfoDocumentation.lua`). The `!note`
command (`Modules/NoteCommand.lua`) most likely did nothing on Anniversary, and would do the same on Forever.

Before the fix, on Anniversary: `/dump GuildRosterSetPublicNote` and `/dump C_GuildInfo.SetNote`, output recorded
on the issue (needs the maintainer in game). `/guildos probe` (#9) records both as well.

## 2. Design

### 2.1 `Compat.FindGuildRosterIndex(name, realm)`
Unchanged rule: an exact `Name-Realm` wins; a short name only when it is unique. It now also says why it found
nothing: `idx`, or `nil, "ambiguous" | "absent"`. Callers that read one value are unaffected (`Core/Utils.lua`
takes it inside an `and`, `PugInspector` reads the note only).

### 2.2 `Compat.SetGuildPublicNote(name, text, realm)` → `true` or `false, reason`
In this order:
1. `CanEditPublicNote` missing or false → `false, "no-permission"`.
2. Resolve the roster row → `false, "absent" | "ambiguous"` when it does not resolve to exactly one (an empty
   name is absent).
3. Sanitize and cap at 31 bytes without splitting a codepoint (`BRutus:SanitizeUserText`, unchanged).
4. Write:
   - `C_GuildInfo.SetNote` exists and the row has a GUID (return 17 of `GetGuildRosterInfo`) →
     `C_GuildInfo.SetNote(guid, note, true)`;
   - otherwise the old global `GuildRosterSetPublicNote(idx, note)` when it exists;
   - otherwise `false, "no-guid"` (only `C_GuildInfo.SetNote` exists and the row has no GUID) or `false, "no-api"`.

`Compat.GetGuildPublicNote` passes the lookup's reason on as its second return.

### 2.3 Who is told (`NoteCommand`)
Every member's client sees every `!note` line, and `BRutus:Print` writes to each client's own chat frame, so a
message printed on every client would appear for every member running Guild OS. Each case is told once, to the
person it concerns:
- **The member who typed it, when their character cannot edit public notes:** their own client prints "You cannot
  edit public notes. Only an officer who is online now and running Guild OS can apply !note; if none is, type it
  again later." Nothing stores a `!note` for later, so the message describes the moment of typing. Other
  members' clients without the permission stay silent. (Short-name match on `UnitName("player")`.)
- **An officer whose client tried the write:** `NoteCommand:_Refused` prints why it did not happen — not on the
  roster, more than one member with that name, no GUID, no note API — or that the character lost the permission
  between the chat line and the write (a rank change in the jitter window), checked before any name lookup.
- **Nobody, when the roster is still empty:** "not found" would be wrong while the roster has not loaded, and
  another officer's client can apply it.
- A note that already reads that way is left alone, silently, as before.

Six new locale keys, five locales.

Risk to settle in game: the Anniversary API documentation marks `C_GuildInfo.SetNote` with
`HasRestrictions = true`. The same flag sits on plain getters (`GetMOTD`, `GetInfoText`), so it most likely
means the restricted-actions system (chat and instance lockdown), not a hardware-event requirement. `!note`
writes from a timer after a chat event, not from a click; if the manual check shows the write blocked there,
`!note` needs an officer action (a popup button) instead.

The issue's "the player is told" when they cannot edit public notes is covered twice: the member who typed the
line is told on their own client, and an officer whose client lost the permission before writing is told too.

## 3. Tests
`tools/public-note.lua` (luajit), real `Core/Core.lua`, `Core/Compat.lua`, `Core/Utils.lua` and
`Modules/NoteCommand.lua`, stubbed roster and the real guild chat hook (43 checks):
- the three API states: `C_GuildInfo.SetNote` (called with the GUID, the note and `true`), the old global only
  (called with the index), no `C_GuildInfo` at all (with and without the old global), neither (`false, "no-api"`); a row without a GUID falls back
  to the old global, refuses with `"no-guid"` when only `SetNote` exists, and says `"no-api"` when neither does;
- permission false or `CanEditPublicNote` missing → `false, "no-permission"`, nothing written, and checked before
  the name (an ambiguous name still says `"no-permission"`);
- unique, ambiguous (`Bob-RealmA` / `Bob-RealmB`), exact `Name-Realm`, absent, empty and nil names; the reasons
  from `FindGuildRosterIndex` and `GetGuildPublicNote`, and both still return the index and the note on a match;
- the note is sanitized (UI escapes stripped); 31 ASCII bytes are written whole, 32 are cut to 31, and the cap
  never splits a codepoint;
- `_Apply`: on success writes, says so and logs it for the officers with the member's full name; silent when the note already reads that way or the roster is still
  empty; says why for an ambiguous name (through the translation table), an absent member, no note API, a row
  without a GUID, and a permission lost before the write (ahead of the name lookup);
- the chat hook: another member's `!note` on a client without the permission is silent and schedules nothing;
  the member's own `!note` without the permission tells them once, in the translated wording that only an officer
  online now can apply it; with the permission the write is scheduled and happens; with `!note` turned off nothing
  is printed or scheduled, whether the client has the permission or not.

Mutation check: 39 hand-written mutants of `Compat` and `NoteCommand` (API order and each guard, the GUID's return
position, `isPublic`, the note passed, the old global's argument, each reason and the reason for no GUID with no
API, the permission check and its order, the sanitizer and both cap edges, each refusal path, its wording and its
translation, the lost-permission path, the empty-roster guard, the sender hint, who sees it, its wording and its
translation, the success log and the name it records, the `!note` switch and where it is checked, the hint's full wording, the identical-note path); the harness
kills all 39.

## 4. Tasks
- [ ] Record the `/dump` output on the issue (maintainer, in game)
- [x] `FindGuildRosterIndex` reason; `SetGuildPublicNote` with `C_GuildInfo.SetNote`, fallback and reasons
- [x] `NoteCommand:_Apply` failure messages (five locales)
- [x] `tools/public-note.lua`
- [x] Docs: functions catalog rows; spec
- [ ] Manual check on Anniversary: `!note` from a member, applied by an officer's client
