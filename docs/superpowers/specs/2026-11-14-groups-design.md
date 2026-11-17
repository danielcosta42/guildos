# Groups: the guild's own group finder (issue #341)

## Why

Members asked on Discord for a better LFG. What the addon has is the availability board
(`/gos avail`, a popup behind Guild › Call to Arms): a role, a note and a duration. It cannot say
which dungeon, there is no group being formed with open spots, and nobody can ask a leader for one.

## What

A **Groups** tab in the window, with four sub-tabs: **Active**, **Dungeons**, **Raids** and
**Quests and more**.

1. As a member I see the game's activities as tiles, with their level range and how many groups and
   how many players each one has, so I know where the guild is going tonight.
2. As a member I list myself as looking: one or several activities, the roles I play (tank, healer,
   damage), a note and for how long.
3. As a leader I publish a group: the activity, the open spots by role, a note and for how long.
4. As a member I ask a group for a spot, in a role. Only its leader hears it.
5. As a leader I see who asked, invite or decline with one click, and the spot closes when the
   player joins. With no spot left the listing comes down by itself.

### Acceptance

- The tab opens from the window and from `/gos avail`; Guild › Call to Arms keeps its button.
- A tile opens the composer with its activity chosen.
- A published group reaches the other members with leader, activity, spots, note and time left.
- A request reaches the leader alone; inviting calls the game's invite; declining tells the asker.
- Nobody publishes, changes or takes down somebody else's listing: the key is the sender.
- Everything received is sanitised and clamped (role, activity, spots, duration, note).
- A client on the version before keeps seeing who is looking and ignores what is new.
- The line in guild chat stays a choice, and one every five minutes at most.

### Out of scope

Groups across allied guilds (the alliance keeps seeing who is looking, as today); booking another
day, which is the Calendar.

## How

**Catalogue** (`Data/GroupActivities.lua`): sections of activities for the client it is loaded on,
each with a stable id, the instance's map id (for the name in the player's language), level range,
group size and the game's own LFG background, drawn only when the client has the file.

**Looking** stays `Modules/LFGBoard.lua` and message `LG`, which gains two fields an older client
never reads: `roles` (a subset of `THD`) and `acts` (up to six ids). `role` still goes out, so an
older client shows the listing as it always did.

**Groups** are `Modules/Groups.lua` and two new messages, which an older client drops as unknown:

| Message | Channel | Payload | Rule |
|---|---|---|---|
| `GF` | GUILD | `{ act, note, need = { T, H, D }, n, max, ttl, age }` or `{ clear }` | keyed by the sender, one a leader |
| `GJ` | WHISPER | `{ role, lvl, class }`, `{ cancel }` to the leader; `{ decline }` from the leader | the sender is on the guild roster; a request is kept only by somebody leading a group |

`LP` was the natural code and is taken: it is the wishlist's loot prio.

A listing carries its age, never a timestamp, so answering a login's request cannot stretch it
(as `LG` since #243). Requests live for the session only (`GuildOS.State.groups`): a leader who
reloads asks nobody twice, and a request with no answer costs the asker nothing.

When a player from the queue shows up in the leader's party, their role's spot closes and the
listing goes out again; with no spot left it comes down. A seat taken by somebody invited by hand
caps the open spots at the seats left. A request never outlives its listing: another activity, or
an expiry, empties the queue and forgets what was asked. Only whoever can invite lists a group.

**Panel** (`UI/GroupsPanel.lua`): one scroll area repainted from pooled frames (a repaint that
creates frames leaks them, WoW never frees one), and one composer popup with two modes.

### Trade-offs

- A request is a whisper, not a guild message: forty clients have no use for it, and it is
  nobody else's business. The cost is that it needs the leader online, which a listing already does.
- Party roles are not read from the game: Classic has none to read. The leader states the open
  spots and the queue closes them.
- Activity names are the client's own where it knows the instance, English otherwise, as the
  Calendar's dungeon list (#308).

### Tests

`tools/groups.lua` runs the real modules under a stubbed client: sanitising, the sender as the key,
the request from both ends, the spot that closes, the listing that comes down, the counts on the
tiles and the catalogue of each client. `tools/lfg-board.lua` keeps pinning the board and gains the
new fields.

## Tasks

1. Catalogue, with its checks.
2. `LFGBoard`: roles and activities; the popup gives way to the tab.
3. `Groups`: listings, requests, the party watcher.
4. The panel and the composer; the feature entry; `/gos avail` and the Call to Arms button.
5. The ten languages.
6. Memory files: architecture, functions catalogue, ADR-0035.
