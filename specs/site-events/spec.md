# The site's events that are not raids, on the calendar (guildos-web #652)

## Why

The site books events that are not raids (guildos-web specs/118, #648): a social night, PvP, a meetup, anything
else, answered on Discord or the site with going, maybe or not going. They stayed off the game: `GOSROST1` says no
kind, and `Calendar:UpsertWebRaid` puts every roster it receives on the calendar as a `RAID` with people to invite.
The owner decided to bring them in, without an old addon ever seeing one as a raid.

## What

1. **The wire.** The site sends them in the guild's `GOSGILD1` (the block the companion already carries), as
   `events`: `{ id, kind, title, startsAt, clock, where?, going, maybe }`, the raids' window and limit (three hours
   back, 28 days ahead, ten at most, never cancelled), counts only — never a name, never a key. Never in the inbox's
   rosters. An addon before this never reads the field; a site before #652 never sends it.
2. **Read as untrusted** (`CompanionImport:SiteEvents`): only from this guild's block, fresh, with the companion on
   (`GuildBlock`); at most `SITE_EVENTS_MAX` (10); an id of `[%w_-]`, 64 bytes at most; one of the four kinds; a
   title and a place made inert, one line, held to 192 and 240 bytes; a whole positive start; whole counts from 0
   to 100000. An entry that fails is passed over alone. Nil when the block says nothing of events.
3. **The kind in the game**: social → `SOCIAL`, pvp → `PVP`, other → `OTHER`, and **meetup → `SOCIAL`** (decision:
   a guild gathering is social; `OTHER` would say less).
4. **On the calendar** (`Calendar:UpsertSiteEvent`, an officer's client, like the raids): the event `web:<id>`,
   marked as the site's by `site = { where, going, maybe }`, on the guild's clock (`clock`), with the note "From the
   website." (and its place), no size, no list of names, no in-game answer buttons ("Sign up in Discord or on the
   website."), and "N going · N maybe" where a raid shows its roles. Never offered to the game's own calendar
   (the guild event the game lets the addon create is one to sign up and invite to). Forward only by the
   companion's ack: an older inbox changes nothing. Nothing moved: nothing goes out (the note is not compared,
   since it is the importing client's language).
5. **Gone from the site, gone from the calendar** (`Calendar:DropSiteEvents`, `GameCalendar.SiteEventGone`): an
   event the list leaves out is cancelled, on every client, only where the inbox can tell — the same reasoning as
   "no longer on the website" for the raids (specs/075) and the window of `NotSentYet` (#416): an ack no older
   than a day, the event inside the inbox's 28 days from when it was written and not three hours past its start,
   below the cap of ten (or, at the cap, no later than its last event), and never from an inbox older than the
   one that brought it. One that only left the window comes back when it returns: the update carries
   `canceled = false` and the other clients take it (`OnSync`). An event made in game, or a raid of the site,
   is never one this takes.
6. **Without the field** (an old site), with no block, an inbox a day old, no ack or the companion off: nothing
   changes.

## Tests

`tools/site-events.lua`: no field and no block change nothing; the four kinds land as SOCIAL/PVP/SOCIAL/OTHER,
from the site, with place and counts and nobody to invite, on the guild's clock; nothing moved publishes nothing,
a count that moved does, an older inbox changes nothing; a member's client writes nothing; every malformed entry is
passed over alone, at most ten, another guild's block is not read; cancelled on the site, the list empty, and back
again; the inference's edges (listed, past the window, past its start, newer stamp, never stamped, a full inbox, an
event made in game, a raid); over the guild channel the counts and place are cleaned, no names, never in the game's
calendar, cancelled and back.
