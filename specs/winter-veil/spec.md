# Winter Veil's Secret Santa, in the game (#437; guildos-web #659, specs/119)

Layout approved on the canvas "Winter Veil — Amigo Secreto (addon + site)" (2026-11-24/25).

## Why

Winter Veil (15 December to 2 January) is WoW: Forever's holiday. The owner wants an engagement event the whole
guild plays, raiders or not: a Secret Santa with crafts or gold within a cap the officers set, a guild "chimney" of
the bank's needs, and a public ranking of guilds. The site holds the event, the draw and every pair (guildos-web
specs/119); the addon shows them and tells the site what happened in the game.

## What

1. **Two blocks in.** `GOSGILD1.veil` (the guild's: rules, counts, the officers' table, the chain after the reveal,
   and after the draw the relay's `salt`) is read by `CompanionImport:WinterVeil`. `GOSVEIL1` (one person's, written
   by their own companion: whom each of their characters drew and that one's list, their list, and the pairs they
   carry for guildmates without the companion) is read by `CompanionImport:VeilBlock`. Both are untrusted: every
   number whole and bounded, every key one line with no `|`, lists capped (8 wishes, 4 pairs, 200 relays, 1000
   rows), a block of another guild or older than a week refused. Neither is ever written to the saved variables
   as received. Before the site opens the event to everybody (1 December), a tester's own `GOSVEIL1` carries the
   event (`event`) and the guild's block says nothing: `WinterVeil()` reads the guild's first, then the tester's, so
   only the tester's addon shows the tab. The officers' table and the carriers come only with the guild's block.
2. **The tab.** "Winter Veil" appears only while the site sends this year's event (`RegisterFeature` condition).
   - A member who is not in sees how to join (before joining closes) and may volunteer for an extra gift.
   - Left: whom I drew and their list; picking an option sets the action: mail the gold (the mail window filled
     with the name, "Winter Veil" and the amount) or place a craft order for the item.
   - Right: my list — each option with what it is worth, the cap bar (the dearest option against the cap), a gold
     option where the guild takes gold, and a search of the recipes somebody in the guild makes.
   - Officers: "Organize" shows who is in, who has a list and who delivered — never a pair, never who received.
     **The rules and the draw are on the site** (a change from the canvas, where the officer screen had inputs): the
     site owns the event, so the addon shows the rules and links there instead of offering a second place to edit
     them.
   - After the reveal: the guild's chain, who gave whom what, and the pairs reassigned.
3. **The list is checked here first** (`WinterVeil.ListRefusal`), with the site's rules: at most 8 options, one gold,
   each item 1 to 20 units, the guild's kind of gift, and each option alone within the cap at its auction price. The
   site refuses whole whatever slips through.
4. **Prices** (`ScanPrices`): the auction price of what a recipe makes (`ProfCatalog` out × count) through
   `Compat.AuctionPrice` (Auctionator, TSM), kept 14 days, and shared on the guild channel so a member without an
   auction addon uses a guildmate's scan.
5. **Deliveries** (`RecordDelivery`): a mail (`SendMail` hook + `MAIL_SEND_SUCCESS`) or a finished trade
   (`TRADE_SHOW` partner + "Trade complete") to whom I drew is recorded once, with the gold sent.
6. **The guild channel** (domain `veil`, not guild-only, since a pair is whispered): each player announces their
   own entry, list and delivery, and a client keeps a line only when its key is the sender's — the game says who
   sent a message, so nobody speaks for anybody else. Prices are anybody's, newest wins.
7. **The relay.** A carrier whispers each pair it carries to its owner while they are online, at most once an hour,
   until the owner answers it has it (the whisper name through ChehulGossip, for WoW: Forever's spaced names). The
   owner believes a whispered pair only from the carrier the site names for them (`GOSGILD1.veil.carriers`): every
   member holds the salt, so anybody could seal a false pair under somebody's key. The owner opens it with `salt:<their key as the site spells it>` (the realm
   off on WoW: Forever). The seal is the site's, byte for byte: FNV-1a 32 seeding xorshift32, XOR, hex; the
   harness holds the site's own vector. It is obfuscation, not secrecy, as the site's spec says.
8. **The export** (`GOSCOMP1.veil`, within payload 17, additive): the year, entries, lists, deliveries, fresh prices
   and, from an officer's client only, the bank's needs (`GuildBank:Needs`, with what the bank holds). No fresh price
   is no `prices` field (the encoder writes an empty table as a list), and each list is cut to the site's caps,
   newest first (100 entries, 200 lists, 200 deliveries).
9. **Prices are read on Enter**, when a recipe search is committed, never per keystroke: each scan is a guild
   message. The site
   believes all of it only from an officer's code; from any other, only the exporter's own lines.

## Tests

`tools/winter-veil.lua`: the seal against the site's vector; the guild's block and a person's block read and
refused; the list's rules; the relay (whispered once an hour, opened only by its owner); the guild channel (a line
about anybody else dropped); a delivery only to whom I drew, once; the export.
