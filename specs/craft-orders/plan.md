# Craft orders: plan (issue #389)

## Files

| File | Role |
|---|---|
| `Modules/RecipeTracker.lua` | `TooltipPick` (pure): at most 3 lines and the rest as a count. The roster's presence is cached for 10 s, not per GameTooltip clear. The Anniversary scan keeps each recipe's reagents locally (`db.craftReagents`). |
| `Modules/CraftOrders.lua` | Orders: the model, the rules, sync (`craftorder` domain, GUILD only), who can craft, reagents, the inbox count, trade and mail completion. |
| `UI/CraftOrdersPanel.lua` | The Orders tab, the order dialog, and the bars on the trade and mail windows. |
| `UI/CraftFinder.lua`, `UI/ProfessionsPanel.lua` | The entry points: Order (to anyone), Order on a crafter's row, and on the recipe card. |
| `Core/Compat.lua` | Bags, the trade window's slots and money, the mail's attachments and money. |
| `Core/Commands.lua`, `UI/Minimap.lua`, `UI/Features.lua`, `Core/Core.lua`, `GuildOS.toc` | `/gos order`, the inbox entry, the tab, the module start, the load order. |

## Data (`GuildOS.db.craftOrders[id]`)

`{ id, who, item, n, mode ("mats"/"own"), tip (copper), note, to, rg = { id, count, … }, st, cr, ts, at, acc }`
- `who`, `to`, `cr`: member keys.
- `acc`: when the order was accepted, which decides between two acceptances.

## Sync (`craftorder`, GUILD only)

| Action | Payload | Who may send it |
|---|---|---|
| `new` | the order | anyone; the author is the sender; 5 open per author |
| `acc` | `{ id, at, rg }` | a member, or the target when the order has one; earlier `at` wins, then the lower name |
| `dec` | `{ id }` | the target: `to` is cleared, the order stays open |
| `rel` | `{ id }` | the crafter: back to open |
| `mats` | `{ id }` | the author or the crafter, while it is accepted and mode is `mats` |
| `done` | `{ id }` | the crafter, or the author on receiving the item |
| `can` | `{ id }` | the author |
| `ask` / `have` | `{}` / `{ list }` | a login asks; one answer after 2–10 s; an answer with nothing new to us cancels ours; at most one answer a minute |

Orders merged from `have`: the newer `at` wins. A known order's author never changes.
