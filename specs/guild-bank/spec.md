# Guild bank (issue #380)

## Why

The game's guild bank has no search and no order, and it can only be seen inside the building.
Its log keeps 25 lines a tab and then forgets them. An officer cannot see what the raid will lack,
a member cannot see what to ask for, and keeping tabs tidy means dragging items one by one.

## What

A **Bank** tab in the window (TBC Anniversary and retail; on WoW: Forever only where the server
opens a guild bank: `C_GuildBank.IsGuildBankEnabled`), with five sub-tabs, a bar under the game's
own bank, and a line on item tooltips.

1. **Inventory**: the last picture of the bank, seen from anywhere by every member with the
   addon. Every tab summed, grouped by category (consumables, trade goods, gems, recipes,
   equipment, bags, other), searchable and sortable by category, name, quantity and quality, with
   where each item is and how far it is from its need. Gold, item count, free slots and who read
   the bank when.
2. **Tabs**: each tab as the game draws it (14 by 7). The **As it is / Organized** switch shows
   the tab already in order without moving anything: the same order organizing would reach, with
   the moves it would take and the slots it would free.
3. **Organize** (at the bank): merges partial stacks and sorts a tab for real, one move at a time,
   waiting for the server, with progress, pause and stop. Only on a tab where the rank withdraws
   without limit, or by the guild master: to the game a move is a withdrawal. Stops when the bank
   closes, in combat, or when a slot stays locked.
4. **Ledger**: every tab's log and the money log, kept past the game's 25 lines without counting a
   line twice. Filters by kind and member; the bank's gold over 30 days; the top contributors over
   30 days (items and gold deposited; withdrawals shown to officers only).
5. **Needs**: officers set how many of an item the bank should hold. Everyone sees have / target,
   what is short, a shopping list; officers can announce it in guild chat.
6. **Requests**: a member asks the officers for an item (quantity and why); an officer fills or
   declines it; its author cancels it.
7. **Tooltip**: "Guild bank: N", per tab and the picture's age, and the need when there is one.
   Follows the existing item tooltip setting (always / Shift / off) and has its own switch.
8. **Bar** over the game's bank (outside it, so the bank's own log tabs stay free; draggable, right-click its name to reset): Organize tab, Organize all, Open in Guild OS, progress.
   Has its own switch.

`/gos bank [sort [all] | stop | sync | need]`.

### Acceptance

- [x] The inventory shows to a member who never opened the bank, with the time and reader.
- [x] Search and sort (category, name, quantity, quality), summed and per tab.
- [x] Organizing merges stacks and sorts the tab; stops on close, combat, cancel or a stuck slot;
      never acts on a tab the rank withdraws from with a limit (unless guild master).
- [x] The ledger never repeats a line across reads; two equal deposits in one hour stay two.
- [x] Only officers change needs; everyone sees have / short.
- [x] A request belongs to its sender; only an officer fills or declines it, only its author
      cancels it.
- [x] Everything received is cleaned and clamped; a client without the feature ignores the domains.
- [x] Every language translated; luacheck 0/0; `tools/guild-bank.lua` and
      `tools/guild-bank-panel.lua`.

### Out of scope (next)

Moving items between tabs; a bank alt's own bags; per-tab layout templates; prices
(Auctionator/TSM) on contributions.

## To verify in game

- Whether a move inside one tab counts against a limited rank's withdrawals (assumed yes, so
  organizing is offered only without a limit).
- That the swap of two different items within a tab happens in one drop on every client.
- Whether WoW: Forever's servers open a guild bank.
- The money log's length.

## Cleanup (officers; asked during the in-game tests)

A guild of 900 fills its bank with what nobody takes. A **Cleanup** sub-tab, for officers only,
gives each item a verdict with its reasons and value:

- **Sell**: grey; what the bank holds past 1.5× its need (all but the need); consumables, gear, bags
  and ammo below the guild's level; gear untouched (no withdrawal in 60 days) for a month.
- **Review**: materials, reagents and recipes below the guild's level (crafters still level on them);
  quest items; anything else untouched for a month.
- **Keep**: has a need, taken twice or more in 60 days, a member's open request, or at the guild's
  level.

"Below the guild's level" is under a level the officers choose in the tab (half the game's cap until
they do: 30 on WoW: Forever): the required level for what has one, the item's own level for
materials. Nothing waits for time to pass: how long an item sat comes from the ledger (its last
deposit, or at least as far back as the ledger reaches), so a bank read for the first time already
has its verdicts (the first in-game try showed nothing to clean in a bank full of it: the rules
then waited 30 days from the first read and asked that under 5% of a 900-member guild be near the
item's level).

The value is the vendor's; with Auctionator or TSM installed, the auction price too, and an item
worth over 3× its vendor price there is flagged for the auction house. Chips: items to sell, the
gold they would make, slots freed, marked (and gold owed to the bank).

Officers mark what goes (one by one, or "Mark all suggested"); the marks are shared (officer domain
`gbankclean`, backfilled with the needs). At the bank all of it happens in a **drawer beside the
game's bank** (#384), opened and closed by the bar's **Cleanup (N)** button, with no trip to the
Guild OS window: what selling would make, the Sell / Review / Keep lists with their marks, "All
suggested", the steps (1 take out > 2 sell > 3 gold back) and one button for the step at hand.
**Take out marked** moves the marked whole stacks into the bags one at a time (each counts as a
withdrawal; stops when the bags are full or a stack does not come out), showing "Taking out X of N"
with Stop. At a vendor, a bar sells **only what came out of the bank**, never more of an item than
came out, so a member's own copies stay. The gold it made is owed to the bank; the next time the
bank opens, the drawer opens itself on its **Deposit** button. The drawer docks on the bank's right,
or its left when the screen has no room there. The Cleanup sub-tab stays, for a look away from the
bank and the "Low level below" setting.

Limits: only whole stacks come out (a part of a stack past its need stays until organized or taken
by hand); auction-house items are only flagged, not posted.
