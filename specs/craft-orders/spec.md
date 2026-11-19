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
3. **The Orders tab.** It has three lists:
   - *My orders*: the ones I placed.
   - *For me*: the ones I accepted, and the ones sent to me.
   - *Open that I can craft*: open orders for recipes I know.

   Each row offers the actions its state allows. An order is started from the Find a Crafter
   window (to anyone, or to one crafter on a row), from the recipe card on the Professions tab, or
   with `/gos order <item>`.
4. **The inbox.**
   - A new order I can craft, sent to everyone or to me, says so in the chat, once, with a sound.
   - My order accepted, its materials received and its item delivered: each says so in the chat.
   - The minimap menu shows "Craft orders (N)" while something waits for me.

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
- An answer speaks only for the sender's own orders, as their author or their crafter, so a
  forged answer says nothing about anyone else's.
  - It adds only running orders, within their author's cap, and never one naming me.
  - It moves a known order only forward (open, accepted, materials, done), keeping its author, its
    target and, once accepted, its crafter. Only the author's answer may say it was cancelled.
  - It never revives an order, and never touches orders I placed or took: those come to me live.
- A crafter who took an order and gave it back before hearing an earlier acceptance loses to it on
  every client, whatever order the messages arrived in.
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
