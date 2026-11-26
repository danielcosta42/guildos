# The alliance, redrawn (epic #444, from the audit #448)

Decided with the maintainer on 2026-11-26. The goal is the simplest alliance that works.

## 1. What is wrong today

There are three alliances, and the panel mixes them.

1. **The ambassador pact** (`Modules/Alliance.lua`, ~2,500 lines).
   - Invites, a join code and ambassadors.
   - The pact lives only in the SavedVariables of whoever founded or accepted it, so the rest of the guild
     never has it.
   - Joining by code never completes for the joining guild (audit C4).
2. **The alliance code, the GreenWall way** (`AllianceLink.lua`, `AllianceChat.lua`).
   - One code, `GOS=TAG:key`, in the guild master's public note.
   - A hidden channel with a password.
   - Each guild's /g is mirrored into the others.
   - This part works without anybody in particular being online.
3. **The site's federation** (guildos-web specs 035 and 106).
   - The guilds of one Discord server: the Council and cores.
   - The paid alliance panel, raids open to the alliance and shared bans.

On top of these, the in-game data sync between guilds (`AllianceSync.lua`, by whisper through an elected
"bridge") is fragile:
- Snapshots stop at the first client that receives them (C2).
- A former user can win the bridge election (C3).
- Guilds learn about each other only by meeting on the presence mesh (C8).
- Calendar slot requests always fail, because they go to ambassadors and the code model has none (C1).

The panel offers actions that only error (C6), shows the wrong channel name (C7) and labels the site's
shared bans as the in-game alliance's (C13).

## 2. What alliances use (the maintainer's answer)

- A shared /g.
- Raids and events together.
- Shared bans.
- Seeing the other guilds' members and crafters.

## 3. The design: one alliance, each side doing what it does well

### 3.1 Where it lives: on the site, with two ways in

An **Alliance** is a row of its own on the site, with a name, a tag and its member guilds. A guild joins it
in one of two ways:

- **By invite.** Independent guilds, each in its own Discord. A guild creates the alliance and sends an
  invite link; an officer of the invited guild accepts.
- **As a federation.** The guilds of a federation (specs/035) are the alliance's members automatically, and
  the federation can still invite guilds from outside it.

**Who decides, in each guild:** whoever may configure that guild (`mayConfigure`). This person creates the
alliance, invites, accepts, leaves and removes. Every change writes `AuditLog`.

The Lendário alliance panel (specs/106) reads this alliance instead of "the guilds of the federation". For
a federation the result is the same as today.

### 3.2 What reaches the game, through the companion

Nobody pastes anything.

1. **The chat code.** The site generates the alliance's key and sends `GOS=TAG:key` in `GOSGILD1`. The addon
   uses it exactly as the alliance code is used today (`AllianceLink`):
   - **The shared /g:** each line also crosses into the other guilds' guild chat, tagged with the speaker's
     guild. Each player can turn it off.
   - **The alliance room:** a channel of its own.

   A new key, when a guild leaves or the alliance is reset, closes the old channel.
2. **The directory**, in a new block `GOSALLY1`: the allied guilds, their members (name, class, level, role,
   main) and their crafters (recipe ids per member). It comes from the rosters and professions the site
   already holds.
   - In game: a "From the alliance" filter in Members, and the Workshop's "who crafts this?" includes allied
     crafters.
   - "Online now" comes from the live in-game presence (the mesh and the channel), as a best effort, and
     says so.
   - Members who opted out (`optedOut`) are left out. Nobody's Discord appears.
3. **Raids open to the alliance.** These already exist on the site (`Raid.allianceOpen`). `GOSALLY1` carries
   the open raids of the allied guilds: when, where, who leads and how many are going.
   - They show in the Salão's notice board and in Raids › Calendar.
   - Signing up is on the site or in Discord. The final roster reaches the raid leader in `GOSROST1`, as
     today.
4. **Shared bans.** These already go through the site (`GOSGILD1`). They are labelled "the alliance's" in the
   Officers' Room, and every way of inviting to the guild warns about an allied ban (audit M2).

### 3.3 Without the site

An officer may still paste the alliance code by hand, in the Officers' Room. That guild gets **the chat
only**. The screen says that members, crafters, raids and bans come from the site.

### 3.4 What leaves the addon

- The ambassador pact, the join code, the INV/ACK/JOIN/REQ/PACT/LEAVE/EJECT ops and the legacy
  `/gos ally create|invite|leave` verbs. One migration line remains: "Alliances now live on guildos.me."
- `AllianceSync` (whisper sync, the bridge, HEAD/PULL/PUSH), mesh discovery (`Learn`, `Candidates`), the
  alliance board and the alliance LFG pool.
- Channel moderation by ambassadors (`PromoteAmbassadors`, its 300 s ticker).
- The Manage tab and its founding, ambassador and code sections.

### 3.5 What stays on screen

- **Salão › Alliance:**
  - the alliance's name and its guilds, marking who is online now;
  - the alliance room;
  - the switch for the shared /g;
  - the open raids.
- **Officers' Room › Alliance:**
  - "From guildos.me" with the alliance's name and a link to manage it there, or the field to paste a code;
  - the shared bans.

### 3.6 Plan

The basic alliance is free: the code and chat, the guilds, members and crafters, the open raids and the
shared bans. The full panel on the site (rosters together, compared attendance, ranking) stays Lendário.

## 4. Work

- **guildos-web**, an issue of its own:
  - the `Alliance` and `AllianceGuild` models, invites, accept, leave and remove, each with `AuditLog`;
  - the federation as a way in;
  - key generation and rotation;
  - the code in `GOSGILD1` and the new block `GOSALLY1` (directory and open raids, `optedOut` honoured);
  - specs/106 reading the alliance;
  - the copy in nine languages.
- **guildos**, an issue of its own:
  - read the code from `GOSGILD1` (validated as untrusted);
  - read `GOSALLY1` into memory, never into the fields the addon owns;
  - the Members filter, the Workshop crafters and the board and calendar raids;
  - the new Alliance screens;
  - remove §3.4.
- **Order:** the site first, then the addon. Until the site sends anything, an addon with only a pasted code
  keeps the chat, so nobody loses the shared /g in between.

## 5. Questions answered

- **Uses:** all four (the shared /g, raids together, shared bans, members and crafters).
- **Source:** the site, with the pasted code as a chat-only fallback.
- **Chat:** the shared /g plus the room, and each player can turn off the shared /g.
- **Plan:** the basic alliance is free.
- **Alliance or federation:** both, as two ways into the same alliance.
- **Who decides:** whoever configures the guild.
