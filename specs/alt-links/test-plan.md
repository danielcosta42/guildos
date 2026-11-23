# Alt links: test plan (issue #424)

Automated:

- `luajit -e 'ADDON="."' tools/alt-sync.lua`: several clients on one guild channel. Migration; an officer
  with an empty table answering a request; an old client's empty, partial and conflicting "AL"; an unlink
  while another officer is offline, who comes back with the old list; two officers linking at once (and
  the same alt to two mains); a member's claim kept through an officer's list that lacks it, re-sent, then
  applied; a 300-alt backfill in spaced batches, never stacked; the group queue (promote, demote, never the
  main, `Eligible`, re-queued until the main's rank); WoW: Forever keys with and without the realm.
  Mixed versions: no "AL" with only new clients heard, one after an old version is heard, ignored by new
  clients, without a link an old officer unlinked, empty after the last unlink, none from a new install;
  migrated tables not united (a new install takes them, a tombstone beats them in either order); a pruned
  tombstone still refuses an old table; the backfill at most once per 10 minutes (and the safe list's); a
  member's own unlink waiting until an officer applies it.
- `luajit -e 'ADDON="."' tools/alt-autodetect.lua`: the member's claim is dropped only by a newer
  tombstone or a newer link elsewhere, never by a missing link.
- `tools/forever-payload-keys.lua`, `tools/officer-ranks.lua`: "AL" keys and channel rules.

In game (two officers A and B, one member M; a test guild with a main and two low-rank alts):

1. A links two alts. B and M see them (member sheet, roster "main" column).
2. B logs off. A unlinks one alt. B logs in: the alt stays unlinked for everybody, B included.
3. A fresh install for B (or `/gos reset` on B): B logs in, `/gos sync`. Nobody loses a link; B gets them.
4. With an officer on a version before this one online, link and unlink on the new one: no link is lost
   on new clients.
5. M on its own sheet links its alt; with no officer online M still sees it; once an officer logs in it is
   applied guild-wide.
6. A on the main's sheet clicks **Promote alts**: Leadership > Bulk actions opens with the alts below the
   main's rank; each Next promotes one step; an alt two ranks below comes back for its second step.
7. `/gos altlimit 1` lists the main with two alts; `/gos altlimit 5` says no group has more.
8. WoW: Forever: links made by an officer whose client answers another realm land on the same members.
