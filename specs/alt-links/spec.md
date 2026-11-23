# Alt links that stay linked, and the group that moves together (issue #424, epic #423 group A)

## Why

"Our linked alts keep getting unlinked automatically." The links travelled as one table ("AL") that
replaced the receiver's whole table. Every officer sent it on every sync request, so an officer with an
old or empty table wiped everybody's links, and an unlink came back when an old table was sent again. A
member's own claim (#353) was dropped when an old list lacked it. Keys written with and without the realm
on WoW: Forever could split one member.

Officers also asked (as in GRM) to promote or demote a member's alts together, and to audit groups with
too many alts.

## What

1. **Synced per alt.** Each alt is one entry (`main`, who wrote it, when) with its own revision; an unlink
   is a tombstone. The newer edit wins on every client; two officers linking different alts at the same
   time both stand. Domain `alt` on the SyncService: only an officer writes, over the guild channel.
2. **Cold sync.** An officer answers a sync request (and `/gos sync`) with every entry at its stored
   revision, in batches of 40, 2 s apart. A stale answer never rolls back a newer edit; a tombstone
   reaches an officer who was offline.
3. **Readers unchanged.** `db.altLinks` ([alt] = main) is rebuilt from the entries, flat, plus a member's
   own waiting claims on that member's client. The roster, chat tags, member sheet, cores, alliance and
   companion export read it as before.
4. **Migration.** The table saved before this version becomes entries at the lowest revision: any
   officer's entry replaces them.
5. **Old clients.** "AL" still goes out (the whole view, never an empty one). Received, it only adds an
   alt this client never heard of; it never removes or changes a link; an empty one does nothing.
6. **A member's claim** stays (and is re-sent once a session when an officer is online) until the
   officers' links carry it, or an officer's edit newer than the claim unlinks one of its characters or
   links it to another main. A link missing from an officer's list is no answer.
7. **WoW: Forever keys** with and without the realm are one member (`LocalMemberKey`), on receipt and in
   the stored entries.
8. **The group to the main's rank.** On a member's sheet an officer has **Promote alts** and **Demote
   alts**: a queue in Leadership > Bulk actions with the group's alts below (or above) the main's rank,
   never the main, each checked by `Eligible`. One rank step per click of Next; an alt still short of
   the target after a step is queued again. `/gos altgroup <promote | demote> <name> [rank]` does the
   same, to a rank given by name or by its number in the game's list.
9. **`/gos altlimit N`** prints the groups with more than N alts.

## Out of scope

- Importing GRM's data; promoting without a click; linking by name heuristics.
- Removing links of members who left (group B, #423).

## Known limits

- An officer still on an old client keeps replacing its own table, and an unlink made there is not heard
  by new clients (the merge never removes). The full gain comes when every officer has updated.
- Revisions use the server time: on the same realm every client reads the same clock.
