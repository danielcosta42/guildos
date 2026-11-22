# The talents and each item's suffix in the companion export (issue #399)

## Why
The `GOSCOMP1` payload already carries each member's equipment (item, item level, enchant per
slot), but not two things that make the character what it is:
- the **talents**, point by point;
- the **random suffix** of an item ("of the Eagle", "of the Monkey"), which is where such an
  item's stats are. Without it the same item id is a different item.

Without them the companion and the site cannot show the whole character.

## What
Payload **v17** (16 was the highest in use). Both fields are absent when unknown, never `null`,
`0` or `[]`; a reader from before never looks at them.

- **`members[].gear[].suffix`**: the item link's random suffix id, the field after the four gems
  (`item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:...`). An integer with its sign kept (the
  game writes some suffixes as negative ids). Absent when the link has `0` or nothing there. Read
  on every game (it is in the link on all three), collected by `DataCollector:CollectGear`, carried
  in the member broadcast and merged like any field.
- **`members[].talents`**: WoW: Forever only, `[[definitionID, rank], ...]`, only the talents with a
  rank, sorted by `definitionID`. Read from the game's trait tree (`C_ClassTalents.GetActiveConfigID`
  → `C_Traits.GetConfigInfo` → nodes → the active entry's `definitionID` and the node's
  `currentRank`), through `Compat.TraitTalents`. The `definitionID` is the talent's own id in the
  game's tables, which does not change when the tree is redrawn; on a choice node it is the chosen
  entry's.
  - The player's own: collected with the rest of the character (`CollectMyData`), carried in the
    member broadcast. A tree that cannot be read yet keeps what was read before.
  - An inspected member's: after `INSPECT_READY`, when the client exposes an inspect config for the
    trait API (`Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID`). Kept unless the member's own
    reading is at least as new, the same rule as the inspected item level.
  - TBC Anniversary and retail: absent. Anniversary's talent tabs have no talent id to send, and
    retail's trees are a different shape; neither is part of this issue.
  - The export only sends whole positive pairs, at most 200: a record with anything else in it sends
    no `talents` at all, never half a tree.

No interface change, no new setting, no new message on the addon channel (the fields ride the
broadcast the addon already sends).

## Acceptance
- [x] The player's own talents export as `[[id, rank]]` read from the client's API; inspected
      characters' too, when the inspect brings them.
- [x] Each gear slot exports its random suffix id from the item link, when there is one.
- [x] Absent when unknown (never `null`); the payload version goes up once, to 17.
- [x] An old addon and an old site keep working: whoever does not know a field ignores it.
- [x] Tests in `tools/` (luajit): `tools/companion-talents.lua` (the tree, absent cases, link
      parsing with and without a suffix and with a negative one, the broadcast, the inspect, the
      other games) and `tools/companion-payload.lua` (the shape on the wire).
- [x] No visible change in the addon's interface.

## To check in game
- WoW: Forever: that `GetNodeInfo` gives `activeEntry` and `currentRank` on 1.60, and that the ids
  match the talents' `definitionID` in the game's tables.
- WoW: Forever: whether `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID` exists and the trait API
  reads an inspected tree; if not, inspected members simply carry no talents.
- A link of an "of the X" item on each game, to see the suffix in that field.
