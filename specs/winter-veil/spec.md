# Winter Veil's snow globe, in the game (#437; guildos-web #659, specs/119)

Layouts approved on the canvas "Winter Veil — Amigo Secreto (addon + site)": Addon-Embrulhar, Addon-Abrir, Addon-Perfil,
Addon-Revelacao, Addon-Oficial. This file replaces the first design (a list of crafts or gold, a cap, mail or trade
deliveries, the bank's needs). The site's `specs/119-o-amigo-secreto/{spec.md,redesenho-globo.md}` is the source of truth.

## Why

Winter Veil (15 December to 2 January) is WoW: Forever's holiday. The event is an engagement game the whole guild plays,
raiders or not, and it is 100% digital: each player wraps a collectible **snow globe** (a scene and a note of up to 80
characters) for whoever they drew, the receiver opens it at Christmas, and the globe's **rarity is drawn on the server**
at that moment. The Chimney is the share of players who already wrapped. The site holds the event, the draw, every pair
and every rarity; the addon shows them and tells the site what the player asked.

**The addon only shows and records; it never decides.** No rarity, no pair, no Chimney is computed in the game.

## What

1. **Blocks in** (all untrusted: numbers whole and bounded, keys one line with no `|`, lists capped, notes held to 80
   characters and made inert; a block of another guild, or older than a week, is refused).
   - `GOSGILD1.veil`: `{ year, joinUntil, wrapUntil, openAt, reassignDays, drawn, salt?, chimney?, counts = { entrants, wrapped,
     pairs, opened }, entrants? (officers: { key, wrapped }), carriers?, reveal? (after `openAt`, only opened globes:
     { giver, to, scene, rarity, host? }) }`. Read by `CompanionImport:WinterVeil`.
   - `GOSVEIL1` **v2** (one person's; v1 of the first design is refused): `{ guild, year, at, event?, mine = { { key, volunteer,
     gives = { { to, toClass?, scene?, note?, wrapped, extra?, hosted?, rarity? } }, got? = { ready, ornament? } } },
     relay, collection }`. Scenes are `tree|cabin|snowman|fire|mountain`, rarities `common|rare|epic|legendary`; anything
     else drops the line. Read by `CompanionImport:VeilBlock`. Before the site opens the event to everybody, a tester's own
     block carries it (`event`).
2. **The tab** appears only while the site sends this year's event. Sub-views:
   - **My secret friend** (Addon-Embrulhar / Addon-Abrir): not in → join (with "I can give one more globe"); in, before the
     draw → wait (and leave until joining closes); after the draw → whom I drew, a scene picker, the note (counter, and a
     hint when it is long enough to lift the rarity, which the server decides), "Wrap" / "Wrap again"; with two pairs (one
     taken over) a row picker. From `openAt`: the globe I received, wrapped until I press **Open the globe**, which only asks;
     the site draws the rarity and the next block shows it. Once the receiver opened mine, I see its rarity.
   - **Collection** (Addon-Perfil): every globe the account opened, newest first, with scene, rarity, year, giver and note.
   - **The guild's chain** (Addon-Revelacao): after the opening, who gave whom, scene and rarity, of the opened globes only.
   - **Organize** (officers, Addon-Oficial): who is in and who wrapped, never a pair. The rules and the draw are on the site.
   - The Chimney bar and the counts are in the header.
3. **Images.** The game cannot load 3D from outside: a globe is a 128×128 TGA per scene × rarity (20) plus `closed.tga`
   (wrapped), in `Media/Globes/`, rendered from the site's approved prototype (`prototipo-globo.html`, three.js r128) by
   `tools/render-globes.js` (see below). One frame each.
4. **The note** is checked here first with the site's rules (`WinterVeil.CleanNote` mirrors `cleanNote`): whitespace collapsed,
   up to 80 characters (not bytes), no control, zero-width or direction characters, no `@`, link or markdown. The site
   refuses a line whole when it breaks them; a scene outside the five also drops the line.
5. **Joining and leaving** are said on the guild channel (domain `veil`), each player only about themselves, so an
   officer's export carries a member who has no companion. **Wrapping and opening never travel on the channel**: they would
   tell the guild who wrapped, which only the officers' table shows. They go in the player's own export, or are done on the
   site (so wrapping and opening in the game need the companion's `GOSVEIL1`; without it the screen links to the site).
6. **The relay.** A carrier whispers each pair it carries (`{"to": key}` and nothing more) to its owner while they are online,
   at most once an hour, until the owner answers it has it. The owner believes a whispered pair only from the carrier the
   site names (`GOSGILD1.veil.carriers`) and opens it with `salt:<their key as the site spells it>`. The seal is the site's,
   byte for byte (FNV-1a 32 seeding xorshift32, XOR, hex; `lib/veil-rules.ts` `seal`/`unseal`; the harness holds the
   site's own vector). It is obfuscation, not secrecy, as the site's spec says.
7. **The export** (`GOSCOMP1.veil`, payload 17, additive): `{ year, joins, leaves, wrap, open }`: `joins` and `leaves` as
   announced (an officer's code believed by the site), `wrap = { giver, to?, scene, note, at }` (`to` only when I hold two
   pairs) and `open = { receiver, at }`, always my own. Capped at the site's limits (100 / 200 / 200), newest first.
   **Never a rarity.** Gone: `prices`, `needs`, `deliveries`, `wishes`.

## Removed from the first design

Auction prices (`ScanPrices`, `Compat.AuctionPrice` use), wish lists and the cap, the gift kind, `RecordDelivery` and
the mail/trade hooks, `deliveries`, the bank's needs (`GuildBank:Needs`), and their locale strings. The probe's
`MAIL_SEND_SUCCESS` / `TRADE_MONEY_CHANGED` and the extra luacheck globals went with them.

## Regenerating the images

```
node tools/render-globes.js <guildos-web>/specs/119-o-amigo-secreto/prototipo-globo.html [Media/Globes]
```

Needs Playwright with Chromium and network access to cdnjs (the prototype loads three.js r128 from there). Reduced motion
is forced so every globe stands still at the same angle; each of the 5 scenes × 4 rarities waits 2.5 s for the snow to
settle. Files: `<scene>-<rarity>.tga` and `closed.tga`; 32-bit uncompressed, top-left origin (descriptor `0x28`), the
size the WoW client wants (power of two).

## Tests

`tools/winter-veil.lua`: the seal against the site's vector; the guild's block and a person's v2 block read and refused;
the note's rules; wrapping (a pair I did not draw, a scene outside the five, a refused note, after the deadline, without
the companion, two pairs); opening (only from `openAt`, only a ready globe, never a rarity in the export); the relay (whispered
once an hour, opened only for its owner and only from the named carrier); the channel (a line about somebody else
dropped, nothing about wrapping or opening); the export's caps; and the panel drawing every state.

## Open

- The rendered globes are the "preview" of what the site draws in 3D; the wrapped globe is the common tree under a gold
  ribbon drawn by the render script, not a modelled one.
- A member who wraps or opens in the game needs the companion; a "wrap it on the site" link stands in when there is none.
- Frimm (the host) is shown as text only: no image or voice yet (launch kit).
- Not yet tried in the game client (Interface 20504).
