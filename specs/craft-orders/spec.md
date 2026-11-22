# Craft orders and the short crafter tooltip (issue #389)

## Why

With more than 900 members, the "Crafted by:" lines of an item tooltip listed everyone who knows
the recipe and ran off the screen. And the addon only said who makes an item: asking someone to
make it meant whispering around.

## What

1. **A short tooltip.** Up to 3 crafters who are online. When nobody is online, up to 3 offline
   crafters, the ones seen most recently first. Then one line with the rest: `+N more (M online)`
   and how to see them all (`/gos craft`). This applies to item and spell tooltips, on every client.
2. **Craft orders.** A member asks for an item, a count and optionally a note:
   - **Who it goes to.** By default the order is **open** to everyone who knows the recipe, and the
     first to accept takes it. It can also be sent **to one crafter**: only they see it as theirs.
     If that crafter declines, the order becomes open to everyone.
   - **Materials, chosen per order.** "I bring the materials" (the default) or "the crafter uses
     their own". A **tip** in gold is optional. Paying is on trust: the addon holds no gold.
   - **Delivery.**
     - With both online, by **trade**. A bar on the game's trade window puts the materials (and
       the tip) in with one click for the author, or the crafted item for the crafter. When the
       trade completes, the order moves on by itself.
     - With the other player offline, by **mail**. A bar on the mail window fills in the recipient,
       the subject, the attachments and the money. Once the mail is sent, the order moves on.
   - **States.**
     - `open` → `accepted` → `mats` (materials delivered, only when the author brings them) → `done`.
     - The author cancels an order any time before it is done.
     - The crafter who accepted can give the order back, and it becomes `open` again.
     - An open order not taken in 7 days expires.
3. **One Crafts tab** (it replaces the Professions/Recipes tab; no separate Orders tab). Three
   columns, seen at once:
   - **Professions** on the left, each with the guild's coverage (WoW: Forever and retail).
     Anniversary keeps its profession filters over the list.
   - **The catalog** in the middle: every recipe and who makes it.
     - Marks after each name: "you craft" and "N orders".
     - Filters, beside All / In the guild / Nobody crafts: **I craft** and **With orders**. In a
       narrow window these two give way first; the chosen one stays.
     - **A recipe clicked opens in place**, in the list, instead of the old floating card. Its block
       holds the materials (what I carry against what the order needs, counted in crafts), the
       crafters (three, online first, "Ask them" sends the order to that one alone, and the rest as
       a count) and the order itself: quantity, whose materials, tip, and Send. A second click closes it.
   - **The order queue** on the right, always in view: For me · Mine · Open, each with its count.
     - One card per order shows its four steps (Open, Accepted, Materials, Ready).
     - The card's main button is the next thing to do: Accept, Trade, Done, Received, Order again.
       A second button holds the other choice: Decline, Give back, Cancel.
     - The card waiting on me has a gold edge.
     - Under 940 px the queue folds into an "Orders (N)" button that opens it as a drawer.
   - The window's tab reads "Crafts (N)" while something waits for me.
   - **Alt-click an item** anywhere (bags, chat, the bank) to open its recipe in the tab, ready to
     order. It does nothing for a master looter, whose Alt-click on a bag item starts a roll, nor
     while the loot window is open.
   - `/gos order <item>` does the same. Without an item it opens the tab on Mine. An item the
     catalog does not list still gets the order dialog, as Find a Crafter's Order buttons do.
   - **Several orders with the same player**: the trade bar's "1/2 >" picks which one the trade is
     about.
4. **The inbox.**
   - A new order I can craft, sent to everyone or to me, says so in the chat, once, with a sound.
   - My order accepted, its materials received and its item delivered: each says so in the chat.
   - The minimap menu shows "Craft orders (N)" while something waits for me; it opens the
     Crafts tab on For me.

## Rules

- An order belongs to its sender: the author is who sent the message, never what it says.
- Only the author cancels. Only the target declines. Only one crafter accepts: when two accept at
  once (within a minute of each other, and heard within a minute of being sent), every client keeps the earlier acceptance, and on a tie the
  lower name, so they all agree. Once the materials went to a crafter, nobody takes the order from
  them. An acceptance dated before the order, or before its last release, is ignored, so a late
  message from an earlier round changes nothing. The crafter who lost a tie is told.
  If the order was sent to one crafter, only that crafter accepts. Only the crafter who accepted
  gives the order back or marks it done. The author or the crafter marks the materials delivered.
- At most 5 open orders per member, up to 20 items each, a note of up to 80 characters, and a tip
  of up to 100,000 gold. Closed orders are kept for 14 days. At most 200 orders are kept.
- A member who logs in asks once. Each member with running orders they placed or took answers
  for those, after a random wait, at most once every two minutes.
- An answer speaks only for the sender's own orders: as their author, or as the crafter this client
  already knows took them. A forged answer says nothing about anyone else's.
  - It adds only running orders from their own author, within the cap, and never one naming me.
  - It moves a known order only forward (open, accepted, materials, done), keeping its author, its
    target and, once accepted, its crafter. Only the author's answer may say it was cancelled.
  - It never revives an order, and never touches orders I placed or took: those come to me live.
- A crafter who took an order and gave it back before hearing an earlier acceptance loses to it on
  every client, whatever order the messages arrived in.
- An item two recipes make (Forever has seven: a bar smelted or transmuted, Tailoring's or
  Leatherworking's) is read through one recipe, never the first one found (issue #396):
  - the row clicked shows its own, and an order placed from that row carries it;
  - an order shows the recipe of the crafter who took it, or of the crafter it was sent to;
  - otherwise it shows the recipe most of the guild knows.

  The crafter's acceptance sends their recipe's reagents and yield.
- Known limit: on Anniversary (no catalog) a character keeps one material list per item, the last
  tradeskill window read; one who makes an item two ways keeps the list of the window opened last.
- Season of Discovery's recipes stay in Forever's game data: 285 of 2490, under categories named
  "SEASON OF DISCOVERY" (2592-2598), many beside the Forever recipe of the same name with other
  reagents and skill. Two "Enchant Bracer - Agility" exist: 1217203 (SoD, skill 320) and 1248497
  (Forever, 225, one Vision Dust). The catalog marks those categories (`seasonal`). Such a recipe is
  listed, counted in coverage, and taken as an item's recipe only while someone in the guild knows
  it (issue #396).
- The Forever catalog follows the game's build (`tools/prof_catalog.py <build>`), now 1.60.1.71037.
- The materials count crafts, not items: a recipe that makes five takes a fifth of the crafts. The
  yield comes from the catalog, or the crafter's tradeskill window on Anniversary.
- A tip by mail is always sent as money, never as C.O.D.
- Only the mail the bar wrote, with the same recipient and subject, moves the order on.

## Acceptance

- [x] An item with 50 crafters shows at most 3 names and the summary line.
- [x] An order reaches those who know the recipe. The first acceptance holds for everyone.
- [x] An order sent to one crafter is "for me" only for them. A decline opens it to everyone.
- [x] The materials show how many the author carries. The trade and mail bars put them in.
- [x] A state from someone who may not set it is ignored: cancelling someone else's order, or
      marking done an order another crafter accepted.
- [x] `tools/craft-orders.lua` and `tools/craft-tooltip.lua` cover the model and the tooltip limit.
- [x] `tools/crafts-tab.lua` and `tools/professions-panel.lua` drive the tab: the queue's views and
      actions, the drawer, a recipe opened in place, the filters and marks, an item opened from
      anywhere, and the tab's count.
