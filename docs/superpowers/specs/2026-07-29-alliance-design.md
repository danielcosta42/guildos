# Alliance design (cross-guild federation over the Chehul mesh)

Let several guilds federate without merging: officers link their guilds, and the linked guilds share
a chat channel, a calendar, an LFG pool and a crafter directory. Driven by a real need from a group
of BR guild leaders who want to cooperate while staying independent.

Design round held 2026-07-29 (scope, size, chat, crafters, signup policy, architecture, mockups all
signed off by the user). Standing project rule satisfied: ASCII mockups approved before any UI work.

## 1. Goals and non-goals

**Goals**

- 5 to 12 guilds, invite-only, one alliance per guild.
- Shared chat, shared calendar with cross-guild signups, shared LFG board, searchable crafter
  directory that works while the crafter is offline.
- Works with no server, no crypto, and no dependency on any single guild being online.
- Every guild keeps full ownership of its own data and can walk away unilaterally.

**Non-goals (explicitly out of scope)**

- Shared ban list / cross-guild reputation. Considered and dropped in the design round: it is the
  highest-risk surface (defamation, brigading) and the least asked for. `BanList` stays per-guild.
- Shared loot systems, DKP pools or attendance. Guilds will not merge economies.
- Multi-alliance federation (a guild in several alliances at once). One pact per guild.
- Cross-faction or cross-realm. Both are impossible on the available transports.

## 2. Decisions from the design round

| Question | Decision |
| --- | --- |
| What is shared | Communication + calendar, group forming, services/economy. No shared blacklist. |
| Size and openness | 5 to 12 guilds, invite only. |
| Chat | Real custom game channel, auto-joined, plus addon data sync. |
| Crafters | Full synced directory (searchable while the crafter is offline). |
| Cross-guild signup | Free signup into a pending queue, approved one by one by the owning officer. |
| Architecture | Embassy model: one bridge client per guild, whisper between bridges, guild-channel fanout inside. |
| Removing a guild | Only the pact `owner` removes others. Any guild removes itself. Everything else is diplomacy. |

## 3. Constraint that shapes the whole design

There is no reliable cross-guild addon bus on the Anniversary client:

- `CHANNEL` addon sends are gated for timer-driven traffic and measured as delivering zero in
  practice (`Libs/LibChehulMesh.lua:14-16`).
- `YELL` (the mesh `:Realm` bus) is zone-local, layer-local, paced and probabilistic.
- `GUILD` only reaches your own guild.

The only reliable directed cross-guild bus is **WHISPER**. Everything below follows from that.

## 4. Trust model and the pact

Root of trust is **character names**. A whisper sender cannot be forged in WoW, so a signed list of
names is enough. No crypto, no server.

State lives in `BRutus.db.alliance` (`BRutus.db` is already guild-scoped, resolved before
`Initialize()` runs). The module registers as `GuildOS.Alliance` (`_G.BRutus` is a legacy alias of
`_G.GuildOS`; new mesh-facing modules use `GuildOS.*`, see `Modules/CraftNet.lua`).

```lua
alliance = {
  tag       = "BRCORE",              -- short, uppercase, [A-Z0-9] only; derives the channel name
  name      = "Nucleo BR",           -- display name, sanitized
  owner     = "Guild A",             -- founding guild; only it may remove other guilds
  revision  = 1785000000,            -- GetServerTime() of the last pact edit
  guilds    = {
    ["Guild A"] = { ambassadors = { "Chehul", "Fulano" }, joinedAt = ..., addedBy = "Chehul" },
    ["Guild B"] = { ambassadors = { "Beltrano" },         joinedAt = ..., addedBy = "Chehul" },
  },
  blocked   = { ["Guild C"] = true },-- purely local ignore; stripped before serialization
}
```

- Each guild publishes its **own** ambassadors. A change claimed on behalf of guild X is only
  accepted when whispered directly by a name currently listed under X.
- `blocked` is local-only and needs no agreement: a guild that turns hostile is dropped instantly by
  whoever wants to drop it (`/gos ally block <guild>`). It lives in the same table for convenience
  but `Alliance:SerializePact()` **must** strip it, and an incoming `blocked` key is always
  discarded on receive. It never travels on the wire in either direction.

**Invite flow (four steps, all over whisper)**

1. An officer of guild A creates the pact in the Alliance tab (tag + name). A becomes `owner` and
   the first member.
2. A invites B by typing the name of an officer of B. An `INV` whisper carries the serialized pact.
3. B's officer gets an in-addon prompt (never automatic), accepts, and answers `ACK` with B's
   ambassador list.
4. A adds B, bumps `revision`, and pushes the new pact to every member guild's bridge. Each bridge
   fans it out inside its own guild over `SyncService`, new domain `"alliance"`.

**Leaving.** A signed `LEAVE` from one of that guild's own ambassadors. The `owner` may also remove
another guild. A removed guild keeps its cached data until it prunes; it just stops receiving.

## 5. Transport and sync

### 5.1 Chat channel

On login GuildOS auto-joins `GOS<TAG>` (for example `GOSBRCORE`) via `JoinChannelByName`, with a
preference to turn it off. `GetChannelName` is already used in `Modules/RecruitmentSystem.lua:689-695`
and both are already whitelisted in `.luacheckrc`, so this is known ground. Colouring and the
per-message guild prefix ride `Modules/ChatTweaks.lua`.

Honest limitation, to be stated in the UI: a custom channel is public, anyone who knows the name can
join. A password may be carried in the pact as a speed bump, but channel ownership in WoW is fragile,
so the password is a deterrent and not a security boundary. Nothing sensitive goes in the channel.

The channel roster is a useful side effect: it is a cheap, reliable list of who from the alliance is
online, which answers the hardest routing question (whom do I whisper). Presence resolution order:
channel roster, then `ChehulNet` peers, then a direct whisper probe.

### 5.2 Wire protocol

Open protocol in the family style of `Modules/CraftNet.lua` and `Modules/RecruitBeacon.lua`, so any
Chehul addon could speak it.

```
prefix : "ChehulAlly"     proto : "AL1"

INV   <pact>                       invite, carries the serialized pact
ACK   <guild>|<ambassadors>        accept, answers with the accepting guild's ambassadors
PACT  <revision>|<pact>            updated pact
LEAVE <guild>|<revision>           signed departure
HEAD  <guild>|<domain:rev,...>     heartbeat: my guild and my revision per domain
PULL  <domain>|<sinceRevision>     ask for a domain
PUSH  <domain>|<revision>|<blob>   serialized domain snapshot
EVT   <domain>|<payload>           small live event (RSVP, LFG entry), no full sync needed
```

`PUSH` payloads go through LibSerialize then LibDeflate; AceComm chunks them automatically.
Priority `BULK` for `craft`, `NORMAL` for everything else.

### 5.3 Domains

Each carries its own revision so a small change never drags the whole payload.

| Domain | Content | Weight | Authored by |
| --- | --- | --- | --- |
| `pact` | the alliance pact itself | tiny | ambassador only, never via relay |
| `roster` | name, class, level, main/alt, professions of each member | light | guild bridge |
| `craft` | recipe index (item id to crafter) | heavy | guild bridge |
| `events` | calendar events + pending cross-guild signups | light | officers, RSVPs self-signed |
| `lfg` | LFG board entries, short TTL | light | self-signed by the entry's author |
| `board` | alliance bulletin | tiny | ambassadors |

### 5.4 Bridge election

The bridge is the online GuildOS client of the guild with the lowest hash of `Name-Realm`. Every
client already knows who is online through `CommSystem` presence, so this is a **pure function
computed identically on every client**, with a 30 second debounce against flapping. No election
traffic at all. If the bridge logs off, the next one takes over within 30 seconds.

The hash is a djb2 over the normalized `Name-Realm` key, implemented in `Alliance.lua` and pinned by
a selftest. It is part of the protocol: every client must compute the same number or two clients will
disagree about who the bridge is. Do not swap it for anything that varies by client or by locale.

**Reaching another guild's bridge.** A bridge cannot see another guild's roster, so it does not try
to compute the remote bridge. It whispers any member of the target guild it currently believes is
online, resolved in order: alliance channel roster, then `ChehulNet` peers, then the cached `roster`
domain. Serving `HEAD` and `PUSH` for your own guild is allowed for **any** online member, so any of
those is a valid entry point; the responder answers from its own local copy, which the local bridge
keeps fresh over the guild channel. This is what removes the single point of failure. Only
ambassadors may *author* changes, and `pact` changes are never accepted via relay.

### 5.5 Cadence and volume

- `HEAD` between bridges every 120 seconds. With 12 guilds that is 11 whispers per cycle, negligible.
- `PULL` only fires when the local revision is behind.
- Inside a guild, the bridge republishes over `SyncService` on the GUILD channel using the same
  revision scheme `Bulletin` and `Calendar` already use. A regular member never sends anything
  outside its own guild.
- `craft` volume: a 100 member guild with roughly 40 crafters and 80 recipes each is about 3200
  pairs, which lands between 8 and 15 KB serialized and deflated. It drains in tens of seconds at
  `BULK` priority and only when the revision changes. Cached in SavedVariables, so a relog re-pulls
  nothing.

## 6. UI surface

Alliance content does not get a parallel panel for everything. Calendar, LFG and recipes gain a
**scope selector** inside the panels that already exist. Only what is genuinely new (the guild list,
the bulletin, pact management) becomes its own tab.

The Alliance tab is registered in `UI/RosterFrame.lua` alongside the existing tabs, conditional: it
shows when a pact exists, or for officers so they can create one.

### Alliance tab, Overview sub-tab

```
+------------------------------------------------------------------------------+
| Guild OS                                                         [ - ] [ X ]  |
| Home  Roster  Guild  Recipes  Raids  Recruitment  ALLIANCE  Leadership  Config|
+------------------------------------------------------------------------------+
|  Overview | Bulletin | Manage                                                 |
+------------------------------------------------------------------------------+
|  NUCLEO BR  .  tag BRCORE  .  7 guilds  .  412 members  .  63 online          |
|  Bridge: Chehul (you)  .  synced 40s ago  .  channel GOSBRCORE connected      |
+------------------------------------------------------------------------------+
|  GUILD                  ONLINE   AMBASSADORS         LAST SYNC   RAIDS 7D     |
|  * Guild A (owner)      18/104   Chehul, Fulano      now         3            |
|  * Guild B              12/88    Beltrano            1 min       2            |
|  * Guild C               9/61    Sicrano, Zeca       2 min       1            |
|  o Guild D               0/47    Joana               2 h         0            |
|  * Guild E              14/72    Marcos              now         4            |
+------------------------------------------------------------------------------+
|  UPCOMING ALLIANCE EVENTS                                                     |
|  Thu 21:00  MC 40  .  Guild B  .  open slots        [Request slot]            |
|  Fri 20:30  Kara   .  Guild E  .  full                                        |
+------------------------------------------------------------------------------+
|  [Invite guild]   [Leave alliance]                                            |
+------------------------------------------------------------------------------+
```

### Approval queue, inside the existing calendar event detail

```
+- MC 40  .  Thu 21:00  .  Guild B ----------------------------------+
|  Signed up 37/40        Tank 3/4   Healer 8/8   DPS 26/28          |
+--------------------------------------------------------------------+
|  ALLIANCE PENDING (3)                                              |
|  Zeca     Warrior 70  Tank    Guild C   "have fire resist"         |
|                                             [Approve] [Decline]    |
|  Joana    Priest 70   Healer  Guild D                              |
|                                             [Approve] [Decline]    |
|  Marcos   Mage 70     DPS     Guild E                              |
|                                             [Approve] [Decline]    |
+--------------------------------------------------------------------+
```

### Crafters, as a scope selector in the existing recipes panel

```
+------------------------------------------------------------------------------+
|  Recipes        Scope: ( ) Guild  (o) Alliance        Search: [ arcanite    ] |
+------------------------------------------------------------------------------+
|  ITEM                       WHO KNOWS IT                GUILD        STATUS   |
|  Arcanite Bar               Fulano                      Guild A      online   |
|                             Zeca                        Guild C      online   |
|                             Joana                       Guild D      off 2h   |
|  Arcanite Reaper            Marcos                      Guild E      online   |
+------------------------------------------------------------------------------+
|  [Whisper]  [Ask in alliance channel]                                         |
+------------------------------------------------------------------------------+
```

The LFG board gets the same Guild / Alliance scope selector, with no new screen.

All user-visible strings go through `L[]`, with `Locales/enUS.lua` as the master list and ptBR
filled in (the alliance's first users are Brazilian).

## 7. Wins that come almost for free

- `Modules/PugInspector.lua` gains an "allied guild" classification, since the allied roster is
  already cached locally. No new sync.
- Allied guild tag coloured in chat via `Modules/ChatTweaks.lua`.
- `Modules/Digest.lua` gains one alliance line on login (allied raids this week).
- `UI/CraftFinder.lua` searches the whole alliance with no UX change.

## 8. Failure behaviour

- A guild with no bridge online renders with a hollow marker and the age of its data ("2 h"). Nothing
  disappears from the screen, it just visibly ages.
- Pact conflict: highest `revision` wins; on a tie, the `owner` copy wins.
- Unknown protocol version is ignored silently, exactly as the rest of the mesh already does.
- A signup sent to an event that filled up comes back as an automatic decline with a local notice.
- Whisper to an offline ambassador fails silently; the bridge falls back to the next known online
  member of that guild.

## 9. Limits and hardening

- Caps: 16 guilds (headroom over the expected 5 to 12, not a target), 300 imported members per
  guild, 5000 recipes per guild, 50 events, 100 LFG entries, 20 bulletin posts. Anything past a cap
  is dropped and the drop is surfaced in the panel, never truncated in a way that reads as complete.
- All member-authored text passes through `BRutus:SanitizeUserText` (established project rule).
- Rate limit: at most one `PUSH` per domain per sender per 60 seconds; invites are prompt-gated and
  rate limited per sender.
- Nothing is accepted from a guild outside the pact or listed in `blocked`.
- Identity is always the comm envelope sender, never a name inside the payload, matching the rule
  already enforced in `Modules/GuildMap.lua` and `Modules/LFGBoard.lua`.
- Every number arriving from the wire is clamped before use.

## 10. Testing

Decidable logic is written as pure functions and registered with the existing `/gos selftest`
harness:

- pact merge by revision, including the owner tie-break
- bridge election (deterministic, given a set of online names)
- domain conflict resolution
- cap clamping and payload rejection
- tag and channel-name derivation
- ambassador authorisation check (accept / reject a claimed change)

Manual verification covers the parts that need a live client: channel auto-join, whisper sync between
two guilds, and the approval queue round trip.

## 11. File layout

```
Modules/Alliance.lua        pact, trust, bridge election, wire protocol   (GuildOS.Alliance)
Modules/AllianceSync.lua    domain snapshots, PULL/PUSH, guild-channel fanout
UI/AlliancePanel.lua        Alliance tab: overview, bulletin, manage
```

Existing files touched: `UI/RosterFrame.lua` (register the tab), `UI/CalendarPanel.lua` and
`Modules/Calendar.lua` (alliance scope + pending queue), `UI/RecipesPanel.lua` and
`UI/CraftFinder.lua` (scope selector), `Modules/LFGBoard.lua` (scope), `Modules/ChatTweaks.lua`
(channel colouring), `Modules/PugInspector.lua` (allied classification), `Modules/Digest.lua`
(alliance line), `GuildOS.toc` (load order), `Locales/*`.

Alliance.lua must load after `CommSystem`/`SyncService` and before the UI files, matching the
existing ordering rule in `.cursorrules`.

## 12. Suggested build order

1. `Alliance.lua`: pact, invite/accept, bridge election, selftest coverage. No UI.
2. `AllianceSync.lua`: HEAD/PULL/PUSH plus guild-channel fanout, starting with the `roster` domain.
3. `UI/AlliancePanel.lua`: overview tab (mockups already approved).
4. Chat channel auto-join and colouring.
5. `craft` domain plus the recipes scope selector.
6. `events` domain plus the cross-guild signup approval queue.
7. `lfg` and `board` domains.
8. The free wins: PugInspector, Digest, chat tags.

This is deliberately more than one implementation plan. Steps 1 and 2 form the first plan (the
foundation: pact, trust, election, and the `roster` domain end to end, with no UI). Each later step
gets its own plan under `docs/superpowers/plans/2026-07-29-alliance-*`, so no single plan spans both
a new sync domain and a new screen.
