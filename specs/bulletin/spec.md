# The bulletin on the Now tab and at login, with how long a notice lasts (issue #418)

## Why
Asked on Discord (suggestions › "Bulletins"): a notice posted on Guild › Bulletin did not show on
the Now tab, nor when a member logged in, so not everyone saw it. The login digest only listed
notices posted after its last look, and the board arrives over sync a few seconds after login, so
a notice the officer posted while the member was offline often arrived too late for the digest
and was never told at all.

## What
- **How long it lasts.** Beside the field, a picker: *Until I close it* (the default), *For 1
  day*, *3*, *7*, *14* or *30 days*. A notice for some days carries `exp`, the server time it
  ends. A notice without `exp` (every notice made before #418, and *until I close it*) runs until
  an officer removes it, as before.
- **The wire.** `exp` is one more optional number inside the same `bulletin` snapshot (SyncService,
  LibSerialize, the whole board): no new domain, action or protocol version. An older client
  stores the board as it arrives, so it keeps `exp`, re-sends it untouched on its next post or
  backfill, and simply shows the notice until removed. An `exp` that is not a positive number
  counts as no end.
- **The board.** Each notice's line says until when it runs. A member sees only the notices that
  run; an officer sees the ended ones too, marked *no longer shown*, to remove them.
- **The Now tab.** A *Bulletin* section between *Needs me* and *Activity*: the newest three
  running notices, a line each with its time, opening Guild › Bulletin. Drawn only while a notice
  runs and the player may open the Guild tab. The tab keeps its name.
- **At login.** Each client keeps which notices it has told (`db.bulletin.seen`, per guild, as
  the digest's clock). The login digest lists the running notices not told yet, the newest three,
  and marks every running notice told (the older ones are not dripped login after login). With
  the digest off, or on the first login ever, each is a chat line instead. After the login, a
  notice that arrives over sync is a chat line. An officer's own post is never told back.
- **The update.** The first run with #418 counts as told the notices posted before the digest's
  last look, so nothing the digest already showed is shown again.
- Officer text on the Now tab and in the chat goes through `SanitizeUserText` (no links or
  textures).

## Acceptance
- [x] The Now tab shows the newest 2–3 running notices (three).
- [x] Posting, the officer picks how long: some days, or until it is removed.
- [x] At login/reload the member is told each running notice not told yet, once: in the login
      digest, or a chat line.
- [x] Notices from before keep working (no end, as today).
- [x] Strings in the 10 locales; `tools/bulletin-expiry.lua`, and the Now tab's section in
      `tools/dashboard-layout.lua`.

## Out of scope
Renaming "Now" to "Overview" (needs a decision).
