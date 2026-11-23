# A member with alts removed or gone: test plan (issue #426)

Automated:

- `luajit -e 'ADDON="."' tools/alt-departure.lua`: three clients on one guild channel (two officers, one
  member). Nothing during the settle or for a secret line; only the remover's client asks; a member
  without alts asks nothing; a main with two alts asks with both names in class colour; "Remove them too"
  queues the two (the protected API is never called); "Ban the group, 30 days, note" makes three bans with
  one term, synced to everybody, and no envelope (publish, backfill, another officer's
  edit) ever carries the note, which no member's or other officer's client holds, while the writer keeps it; an old client's ban without a note applies; a group is asked
  about once; the banned still in the guild and "Remove all"; a queue still running is never replaced; a
  removal inside a queue is asked about once the queue is through; a main leaving asks each officer once
  (never a member, never twice for the same line); "Set A as main" holds on every client; a late second
  answer changes nothing; "Unlink"; an alt leaving asks nothing.
- `tools/bulk-actions.lua`, `tools/alt-sync.lua`, `tools/locales.lua`: the queue, the links, the strings.

In game (officers A and B, a test guild with a main and two low-rank alts):

1. A removes the main (`/gremove`). Only A sees the window, with both alts in class colour.
2. "Remove them too": Leadership > Bulk actions opens with the two; each Next removes one.
3. Again with another group: "Ban the group", 30 days, a note. Ban list on A and B: three rows
   "(group of X)"; the note after the reason on A only. On a client before #426 the bans arrive without error.
4. A removal queue of two mains with alts in Bulk actions: the window comes after the last click.
5. The main of a group leaves on their own: A and B each see the question once; A picks "Set AltX as
   main"; B's roster shows AltX as the main; B's "Unlink" then says it already changed.
6. Ban list: a banned member still in the guild shows under "Banned still in the guild"; "Remove all"
   queues them.
7. `/reload` right after a guild line: nothing is asked for the lines of the first 8 seconds.
