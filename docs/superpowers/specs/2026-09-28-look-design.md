# The look on WoW: Forever — read in the barber's chair (payload v8)

Issue: danielcosta42/guildos#37 · Site: danielcosta42/guildos-web#81 (specs/038)

## Problem
guildos.me draws a Forever character with the game's default look: skin, face, hair, hair colour and
beard at their first choice. The game gives an addon no way to read a character's appearance — except
in a barber's chair. A throwaway probe on the beta (2026-09-28) found `C_BarberShop.GetAvailableCustomizations()`
returns nil at login and, in the chair, every option with `currentChoiceIndex`. The option and choice ids
are retail's, the ones the site's model viewer draws; the result was checked against the character in game.

## Design
- `Modules/Look.lua` (Forever only): on `BARBER_SHOP_OPEN` and `BARBER_SHOP_APPEARANCE_APPLIED`, one
  second later, reads the chair into `{ {optionID, choiceID}, ... }` (one per option, sorted, at most 32) and
  keeps it on the player's own member record. A new look prints one line ("guildos.me draws it after the
  next publish") and forces a broadcast; the same look again says nothing; an empty chair never erases it.
- The broadcast carries `look`; receivers keep it through `StoreReceivedData`'s generic merge, so a
  member who never sat in a chair erases nobody's.
- The companion export carries `look` per member when the record has a list (`PAYLOAD_VERSION` 8).
- Stacked on #36 (payload v7).

## Tests
`tools/look.lua`: no chair writes nothing; sitting down keeps the pairs (first of an option wins, options
with no current choice skipped) and tells the guild and the player once; the same look is quiet; a new
look replaces it; an empty chair afterwards keeps it; the cap; no module on Anniversary.
`tools/companion-payload.lua`: v8; `look` exported for a member who has one, absent otherwise and for a
value that is not a list.
