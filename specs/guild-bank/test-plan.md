# Guild bank: in-game test (issue #380)

Two characters with the addon help (A at the bank, B anywhere). `/gos errors` after each block.

1. **Scan and share.** A opens the bank and waits ~5 s. B opens Bank › Inventory: the items, the
   gold, "read by A". B hovers an item in their bags: "Guild bank: N" on the tooltip.
2. **Inventory.** Search a name; switch the sort (category / name / quantity / quality) and the
   category filter; Shift-click a row (link in chat); right-click (goes to Requests prefilled).
3. **Tabs.** Each tab shows as the game draws it; "Organized" shows the preview, with moves and
   slots freed.
4. **Organize (A, at the bank).** The bar under the game's bank shows. On a tab where A's rank
   withdraws **without limit**: Organize tab → stacks merge, the tab sorts, the chat says how many
   moves. Try Pause/Resume and Stop mid-run; close the bank mid-run (it stops); enter combat
   (it stops). On a tab with **limited** withdrawals the button is off, with the reason.
   **Check:** after a run on a limited rank as GM, did the rank's daily withdrawals change?
5. **Ledger.** Deposit and withdraw a few items and some gold; reopen the bank: the lines appear
   once each, also on B. Filters and the member search; the gold bars and the top contributors.
6. **Needs (officer).** Shift-click an item into the field, set a target: B sees it (tab and
   tooltip). Shopping list prints; Announce posts one line in guild chat.
7. **Requests.** B asks for an item; A sees it, clicks Filled; B sees "filled". B cancels another.
8. **Settings.** Turn off the tooltip line and the bar; both go.
9. **WoW: Forever.** Does the Bank tab appear (only if the server has a guild bank)?
