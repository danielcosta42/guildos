# SR+ by raid or by item (issue #433)

## Why

The SR+ loot rule (`srplus`, issue #337) kept one bonus per character: every raid attended added `srBonus`,
whether they had reserved or not, and winning any item emptied it. Somebody who reserved A one week and B the next
took the whole bonus to B. Most guilds that run SR+ count it **per item**: reserving the same item week after week
builds up on that item. GuildOS runs every loot system itself and talks to no other addon, so the game has to keep
both. The site's standalone sheet already counts per item (`guildos-web apps/web/lib/reserve-plus.ts`).

## What

The rule's bonus account takes `scope` (guildos-web#657 writes it from the SR+ question "The bonus counts by"):

- **absent or `"character"`** — the rule as it always was. Nothing changes for a rule saved before.
- **`"item"`** — the account is kept per character and item, at the key `Name-Realm#itemId`
  (`LootRule:CounterKey`). The figures, their sync (`cdelta`), snapshots and merges are the counters' own: only
  the key differs.
  - **At a raid's end** (`Points:EarnItemBonuses`, from `OnRaidEnd`, on the one client that pays the raid's end):
    for everybody who was there, each item they reserved on tonight's sheet (`SoftRes:ActiveItems`, matched by
    name) and were not given tonight (the loot history between the raid's start and end) grows by the account's
    `raid` earn, never past `cap`, which holds per item. Each item they hold a figure on and did **not** reserve
    tonight goes back to nothing: only reserves in a row add up.
  - **Whoever missed the raid** keeps what they hold.
  - **With no sheet in force** (none imported, none from the site, retail) nothing moves: a night nobody imported
    reserves for wipes nobody. The sheet read is the paying client's own (`RaidEndPayer`): a sheet from the site
    reaches every officer with the companion; an imported one only the officer who imported it.
  - "Given tonight" is read from the loot history, which officers share (`AWARD`). With the loot history switched
    off in Settings, an item won tonight is emptied by the award and grows again at the raid's end.
  - **An award** (`LootMaster:CounterEffects`, with the item awarded) empties the item won only; an undo gives it
    back (the award keeps the key it moved).
  - **The roll** adds the bonus of the item being rolled for (the candidate's `accts`, read and re-read on
    `activeLoot.itemId`); the raider's popup shows the same figure (`LootMaster:Standing`).
  - The points window lists one row per item: the player and the item's name.
  - Each entry is named after the raid night and the key (`I…`, `Z…`), so the same raid ended twice counts once.
- **Validation** (`LootRule:Validate`): `scope` is only `character` or `item`, only on a `bonus` account; kept per
  item, only `auto: "raid"` feeds it (a boss killed says nothing of what was reserved) — refused otherwise as
  `unsupported: earn`.
- **The rule editor** in the game offers "SR+ counts by: Raid attended / Item reserved" on every bonus account
  (`LootRule:SetBonusScope`); choosing item drops its boss earns.

## Decisions (owner, on the issue)

- A raid attended without reserving the item empties it.
- No transition for clients without this version: the Forever raids have not started.

## Tests

`tools/loot-contract.lua`, the variant `srplus:item` of `tools/data/loot-rule-models.json` (written from
`guildos-web apps/web/lib/loot-rule-models.ts` with `srScope: "item"`): the rule reads whole; the key per item;
a raid adds per item reserved and nothing at the player's key; the same raid ended twice counts once; one row per
item in the points window; the roll adds the bonus of the item rolled for; the award empties the item won only and
an undo gives it back; a reserve in a row adds, an item not reserved empties, the item won tonight does not grow;
whoever missed keeps theirs; the cap per item; no sheet moves nobody; a boss earn, an unknown scope and a scope on
a counter are refused. The by-raid scenes of `srplus` are unchanged.
