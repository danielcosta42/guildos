# Bulk actions by rules, one member per click (issue #420)

## Why

Officers asked (Discord, suggestions) for bulk promote, demote and remove on the guild roster, from
simple rules, as other addons do from a button or a macro. The game protects `GuildPromote`,
`GuildDemote` and `GuildUninvite`: an addon cannot run the list by itself (ADR-0010). The safe way is
to prepare the list and act on **one member per click** of the officer.

## What

**Leadership > Bulk actions** (a sub-tab of the Leadership tab, next to Presets).

1. **Action:** Promote, Demote or Remove.
2. **Rules** (all optional, every rule set must hold; with none, nobody is picked):
   - Offline at least N days (an online member never matches).
   - Current rank (any by default).
   - Level from / to.
   - Raid attendance from / to, in % (25-man attendance from the raid tracker). Shown only where the
     raid tracker runs; a member whose group has no tracked raid has no attendance and matches no
     attendance rule (never "0%").
   - Without GuildOS only (members whose GuildOS this client never heard).
3. **Who is never picked**, whatever the rules: yourself, members at or above your rank, a promotion
   that would reach your own rank, a demotion below the lowest rank.
4. **Preview** lists who the rules pick now (name, rank, level, days offline, attendance, no GuildOS),
   longest offline first.
5. **Start** makes the queue from the live roster. **Remove asks first**, listing who (ten names and
   "and N more"); the queue starts only on Start in that dialog.
6. **Next** acts on one member per click. The button says the action and the member ("Promote Bob");
   the line beside it says who is next and "3 of 12". Before each click the member is read again from
   the roster: who left the guild or whose rank changed since the list was made is skipped, with the
   reason in the list. **Skip** passes over the current member; **Stop** drops the queue.
7. **Macro:** `/click GuildOSBulkNext` presses the same button, one member per press (the panel shows
   it). `/gos bulk` opens the tab; `/gos bulk next` says who is next and the macro; `/gos bulk skip`
   and `/gos bulk stop` do what the buttons do. A typed command is addon code and never runs the
   protected command.
8. **Permission:** Preview, Start and every click need the rank's right in the game
   (`CanGuildPromote` / `CanGuildDemote` / `CanGuildRemove`). Nothing runs in combat.
9. **Roster Log:** each change the roster then shows is logged (promote and demote with the new rank,
   a removal as the game's "kick"), once, even when the game's own guild message logs it too.

## How it acts (ADR-0038)

- Next is a secure action button. Its PreClick writes, for that click only, the game's own
  `/gpromote`, `/gdemote` or `/gremove` for one member; the game runs it; PostClick clears it.
- **WoW: Forever** refused an addon-written guild command on a secure button (#256): there each click
  prints the line ("Type /gpromote Bob in chat") and goes on to the next member. Any client where the
  game blocks the click right after it switches to the same typed mode for the session.
- Retail acts on the press or the release by the game's "cast on key down" option; both are handled.

## Out of scope

- Saving rule sets (the Presets sub-tab keeps its saved presets).
- Setting an exact rank (one step per click, as the game's commands do).
- Syncing the queue to other officers.
