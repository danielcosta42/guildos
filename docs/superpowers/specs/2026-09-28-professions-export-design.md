# Professions on WoW: Forever — the export to the site (payload v7)

Issue: danielcosta42/guildos#35 · Epic: #30 (sub-project 4, addon side) · Site: danielcosta42/guildos-web#77 (specs/037)

## Problem
guildos.me knows a member's professions only as `{ name, rank }`; it has no recipes and no way to tell a
member without the addon who has a profession. The foundation (#31) holds all of it in `db.professions`.

## Design
- `PAYLOAD_VERSION` 6 → 7. Each member row gains `crafting`, built by `craftingFor(key)` from
  `BRutus.Professions:Get(key)`:
  - an addon record: `{ line, rank, max, spec?, recipes = { ids } }` per profession line, `recipes` holding the
    catalog and extra IDs sorted (the current lists, or the previous ones while a changed list is pending,
    through `Professions.Lists`);
  - a native record (guild roster only): `{ line, native = true }`;
  - lines sorted by ID.
- **Absent, not empty:** no key where the client has no profession model (Anniversary, older versions) or no
  record of the member — the site keeps what it had (`COALESCE`, specs/037). Also no key for a member while
  a line's list is on its way with no previous one to stand in (a summary heard, the list not yet): sending
  `recipes: []` then would overwrite, on the site, the full list another officer published.
- Stacked on #34 (the directory), which exports `Professions.Lists`.
- `professions` is unchanged, so a site reading v6 reads the same.
- Size: about 150 members × 2 lines × 300 IDs ≈ 0.6 MB of JSON before deflate, inside the site's 4 MiB body
  and 16 MiB inflated caps.

## Tests
`tools/companion-payload.lua`: v7; no `crafting` without a model; with the real `Modules/Professions.lua`
over saved records, an addon member's lines (rank, max, spec, sorted recipes and extras, an empty list), a
native member's line, no key for a member with no record, a stale list standing in, and no key while a list
is on its way. The Anniversary payload is the same length as before (only the version changed).
