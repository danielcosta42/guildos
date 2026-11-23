# A member with alts removed or gone: ask about the alts, the ban and the new main (issue #426, epic #423 group B)

## Why

From the Discord: "when I remove somebody, ask whether to remove or ban their alts too, with a term and a
note", and "when somebody leaves, tell me they still have alts and ask whether the main changed". GRM does
it on its own (removes, promotes the last one left); the request is to ask.

## What

1. **Removed, with alts in the guild.** On the client of the officer who removed them only (the game's
   "kicked out of the guild by <me>" line, or a removal of Leadership > Bulk actions the roster confirmed),
   a GuildOS window (never a StaticPopup, #315) lists the characters of the same player still in the
   guild, by name in class colour, and offers:
   - **Remove them too**: a removal queue in Bulk actions, one per click of Next (the secure button,
     ADR-0038). Each is checked by `Eligible` (never oneself, never a rank at or above one's own) and again
     before their click. A queue still running is never replaced.
   - **Ban the group** (officers): one ban per character of the group, removed one included, the same
     reason and term in days (empty: permanent), and a note; each row shows "(group of X)".
   - **Do nothing.**
   A removal made while a Bulk actions removal queue runs is asked about once the queue is through
   (done, skipped or stopped). Each group is asked about once a session.
2. **`BanList:Add(name, reason, durationSec, note, group)`** and **`BanList:AddGroup(keys, reason, days,
   note)`**. The note is never sent: it stays on the client of the officer who wrote it (a GUILD addon
   message reaches every member's client, and there is no channel only officers read). `group` travels; a
   client before #426 keeps it unread.
3. **A main left of their own accord**, with alts still in the guild: each officer online is asked once:
   "X left and still has N alt(s) in the guild: A, B. Did the main change?" with **Set A as main** (a pick
   among the alts; `SetMain`, synced to everybody), **Unlink** (every alt stands alone) and **Keep**. When
   another officer already answered, the answer changes nothing and says so. An alt leaving is only its
   line in the Roster Log.
4. **Leadership > Ban list: "Banned still in the guild"**, above the list (when no filter is typed), with
   **Remove all**: a removal queue in Bulk actions.
5. **Never** during the login's settle (8 s) or for a chat line in lockdown (`Compat.IsSecret`).

## Out of scope

- Removing, banning or relinking without a click; promoting a new main on its own; whispering the
  removed member.
- A removal or departure seen only by the roster diff (MemberHistory), e.g. a secret line on retail.

## Known limits

- Other officers see the ban, its term and its group, not the note.
