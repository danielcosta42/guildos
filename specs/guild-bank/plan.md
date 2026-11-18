# Guild bank: plan (issue #380)

## Files

| File | Role |
|---|---|
| `Core/Compat.lua` | The guild bank section: every bank call (tabs, slots, logs, money, pickup, split, current tab, events). The 98 slots and 14 per column are constants, since Blizzard keeps them file-local. |
| `Modules/GuildBankPlan.lua` | Pure: item groups, the sort key, the organized target, the next move, a move's effect. |
| `Modules/GuildBank.lua` | Scanning, the shared picture, asks and answers, the ledger, needs, requests, the organize run, the tooltip, `/gos bank`. |
| `UI/GuildBankPanel.lua` | The Bank tab's five sub-tabs and the bar under the game's bank. |
| `UI/Features.lua`, `Core/Core.lua`, `GuildOS.toc` | The tab, the module start, the load order. |
| `Modules/SyncService.lua` | Domains `gbank`, `gbankreq` (GUILD only), `gbankneed` (officers). |
| `UI/SettingsPanel.lua` | The tooltip and bar switches. |
| `tools/guild-bank.lua`, `tools/guild-bank-panel.lua` | Harnesses; `tools/compat-guard.lua` now guards the bank calls. |

## Data (`GuildOS.db.guildBank`)

- `tabs[i] = { name, icon, ts, by, slots = { [slot] = { id, c, l } } }`: `l` is the link string,
  kept only for equipment and pets, which differ copy to copy.
- `numTabs`, `moneyNow`, `moneyTs`, `moneyBy`; `money` = up to 120 readings `{ t, m }`.
- `ledger` = up to 2,000 lines `{ k (tab, 0 for money), t, ty (d/w/m/r/b/s), n, id, c, g, t2 }`.
- `needs[itemId] = { n, note, by, ts }` (up to 60).
- `requests[id] = { id, who, item, n, note, ts, at, st (open/done/declined/cancelled), by }`.

## Sync

| Domain · action | Payload | Rule |
|---|---|---|
| `gbank` · `snap` | `{ tabs = { [i] = { n, ic, ts, by, s = "slot,id,c[,link];…" } }, nt, m, mt }` | GUILD only; per tab, the newer `ts` wins; future times refused |
| `gbank` · `ask` | `{ ts, lt, rq }` | a member logging in; answered after 2–8 s by one member with newer data; any answer as new cancels the others |
| `gbank` · `log` / `hist` | `{ reads = { { k, list } }, req }` | lined up with the end of the kept stream; cleaned and clamped |
| `gbankneed` · `snap` | `{ needs }` with a revision | officers only; officers backfill on an ask |
| `gbankreq` · `new` / `set` | a request / `{ id, st, at }` | the author is the sender; `done`/`declined` need an officer sender, `cancelled` the author |

## The ledger without ids

The game gives each line "years, months, days, hours ago". A read becomes absolute times (now minus
that), oldest first. Merging finds the longest run at the start of the read that matches the end
of the kept stream (same kind, name, item, count, gold and target tab, times within 3 h) and keeps
only what follows. With no overlap, only lines not older than the kept end are added, so a late,
older read adds nothing.

## Organizing

Each step reads the real tab, waits while any slot is locked (gives up after 8 s), and asks the
planner for one move: first merges (the bigger partial stack takes from the smallest, by split
when only part fits), then the first slot out of order is filled from a later slot holding exactly
what it should. The guild bank never swaps (a drop on another item is refused and stays on the
cursor), so a move only lands on an empty slot or on the same item: what sits in the wrong slot is
first moved out, to its own place if that is free, else to the last free slot. A full tab with
nothing to merge cannot be ordered and says so; one free slot is enough. A move is two halves: the pickup (or split), then the drop once the cursor holds the item (at least 0.1 s, at most 0.8 s later): a drop in the same frame as its pickup is lost and leaves the item on the cursor (seen on WoW: Forever). An item still on the cursor after a drop is put back and counted; six refused drops in a row stop the run; a move that did not take is tried again after a wait that doubles (0.45 s up to 4 s), six times at most. `/gos bank debug` prints every half. One move every 0.45 s; the same move on the same state three times stops the run;
at most 400 moves. Sort keys are cached once per item name, so the order cannot shift mid-run.

### Swaps first (after the in-game tests)

A run first tries swaps: the misplaced slot is filled straight from where its stack is, whatever
holds the slot, one move per misplaced stack and no free slot needed. Every move is checked by
reading the tab back once no slot is locked (no fixed delays: pick up, drop once the cursor holds the
item, read back after 0.1 s). A swap that hands the other item back on the cursor has it dropped
where ours came from. A swap the bank refuses switches the run, and the session, to moving through
free slots. Setting `gbankSwap = false` starts there.

A drop is judged only after the game says the slots changed (`GUILDBANKBAGSLOTS_CHANGED`, at most
2 s): read before it, the client still shows the old tab, and a move that landed looked refused
(the in-game log of 2026-11-18 showed every move landing and the run stopping at the sixth). A tab
that changed in any way since the pickup counts as progress.

Second in-game log (2026-11-18): the swap landed, and was still judged refused. The game also
says the slots changed when an item is picked up, and that word arrived after the drop. A move is
now judged by the tab alone: it landed once the tab differs from before it, unlocked, and reads the
same twice in a row; unchanged for 2 s, refused. An item left on the cursor is let go before any
wait on a lock, since its slot stays locked until the cursor lets go.

### Pipelined (faster)

Moves go out back to back instead of one per server round trip. The run keeps a model of the tab as
it will be and plans on it; the planner skips slots a move in flight still uses (`busy`) and offers
the next independent move. Up to 2 moves fly at first, up to 4 after 6 in a row land; any move whose
two slots do not show the expected result within 2 s sends the run back to the real tab, one move at
a time. Until a swap has landed with nothing handed back on the cursor, a swap flies alone. Measured
on the stub (90 items shuffled, 0.3 s server lag): 68 s before, 19 s now with swaps; 76 s → 26 s
through free slots.
