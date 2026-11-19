# Craft orders: in-game test (issue #389)

Two characters with the addon: A (no professions) and B (knows a recipe, e.g. Copper Bracers).

1. **Tooltip.** Hover an item many members craft: at most 3 names, then `+N more (M online)`.
   With every crafter offline: 3 offline names.
2. **Open order.** A: `/gos order [item]` → 2×, "I bring the materials", 1g tip → Send.
   B gets one chat line and a sound, and the Crafts tab reads "Crafts (1)". B: Crafts › queue Open →
   Accept on the card. A gets "B accepted"; A's card under Mine shows step 2 with Trade.
3. **Trade.** A trades B: the bar shows "Put materials (+1g)"; click → reagents and gold in the
   window; accept → A's order shows "materials delivered". B crafts, trades A: "Put item" → accept
   → "done" on both.
4. **Mail.** Repeat with B offline: A at a mailbox, the bar's "Mail materials to B" fills the
   mail; Send → "materials delivered". B mails the item back with the bar → "done".
5. **Directed.** In Crafts, open a recipe B knows, "Ask them" on B, Send → only B sees it in For me
   (gold edge); B declines → it shows under Open for every crafter.
8. **The tab.** Alt-click an item in the bags: Crafts opens on its recipe, opened. Filters I craft and
   With orders. Narrow the window under 940 px: the queue becomes "Orders (N)", a drawer.
   As master looter, Alt-click on a bag item still starts the roll, not the tab.
9. **Two orders with one player.** The trade bar shows "1/2 >" and switches between them.
6. **Rules.** A cancels an order; B gives an accepted order back → open again.
7. **Late login.** C logs in after the orders were made: Orders shows them within ~10 s.
