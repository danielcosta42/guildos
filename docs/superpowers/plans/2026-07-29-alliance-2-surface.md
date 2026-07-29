# Alliance Surface Implementation Plan (parts 2 to 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the alliance in front of the user: the chat channel, the Alliance tab, and the four
remaining sync domains (`board`, `craft`, `events`, `lfg`) plus the integrations that come almost
free.

**Architecture:** Everything rides the foundation shipped in
`docs/superpowers/plans/2026-07-29-alliance-1-foundation.md`. New domains are registered through
`AllianceSync:Register(domain, spec)` and therefore inherit HEAD/PULL/PUSH, the monotonic store, the
rate limit and the guild-channel fanout for free. No new transport is introduced.

**Tech Stack:** Same as part 1. UI follows `UI/Helpers.lua` factories and the `BRutus.Colors`
palette; no hardcoded colours.

**Consolidation note:** parts 2 to 5 share one document rather than four, because they are the same
pattern applied four times and the design detail already lives in the spec. Task boundaries below
still respect the spec's rule that no single task mixes a new sync domain with a new screen.

## Global Constraints

Identical to part 1, plus:

- No hardcoded colours: everything from the `C` table in `UI/Helpers.lua`.
- `UI:CreateScrollFrame` does **not** anchor the scroll frame. The caller MUST `SetAllPoints()` or
  the content is clipped to 0x0: invisible, with no error.
- Frames are created SHOWN. Any window that toggles needs an explicit `f:Hide()` at build time.
- Never `frame:Hide()` a UIPanel: it leaks the panel slot and silently kills the ESC game menu.
- FauxScrollFrame rows are reused: reset ALL visual state in the update function.
- Business logic never lives in UI files. The UI renders module data APIs.
- All strings through `L[]`, with enUS as the master list and ptBR filled in.

## Verification

Same as part 1: `luacheck` must stay at `0 warnings / 0 errors`, and pure logic gets `/gos selftest`
cases the user runs in-client. UI is verified by the user in the running game.

---

## Part 2: chat channel and the Alliance tab

### Task 1: Alliance chat channel

**Files:** Create `Modules/AllianceChat.lua`; modify `GuildOS.toc`, `Core/Core.lua`, `.luacheckrc`,
`Locales/*`.

**Interfaces produced:**
- `AllianceChat:Join()` joins `Alliance.ChannelName(tag)` when a pact exists and the pref allows it.
- `AllianceChat:Leave()`
- `AllianceChat:IsConnected() -> boolean` via `GetChannelName(name) > 0`.
- `AllianceChat.Decorate(text, sender, guild) -> string` pure: prefixes a message with the sender's
  guild tag in the alliance accent colour.

Scope decision: the channel carries HUMAN chat only. It is deliberately NOT used as a presence
source, because `GetChannelRosterInfo` is unreliable on this client (the roster only populates when
the UI lists the channel) and `Alliance:PeerTarget` already answers "who of guild X is online" from
the presence mesh. Nothing is lost.

- [ ] **Step 1: Write the failing self-test**

```lua
    BRutus.SelfTest:Register("alliancechat.decorate", function()
        local out = AllianceChat.Decorate("hello", "Ann", "Guild B")
        if not out:find("Guild B", 1, true) then return false, "guild tag missing" end
        if not out:find("hello", 1, true) then return false, "message lost" end
        if AllianceChat.Decorate("hi", "Ann", nil):find("|cff", 1, true) == nil then
            return false, "unknown guild must still render"
        end
        if AllianceChat.Decorate(nil, nil, nil) == nil then return false, "nil must not error" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails** with `/gos selftest`.

- [ ] **Step 3: Implement.** Join on `PLAYER_ENTERING_WORLD` plus a 10 second delay (channels are
  not available immediately at login), and on pact creation or acceptance. Add `GetChannelRosterInfo`
  is NOT needed; only `JoinChannelByName`, `GetChannelName` and `LeaveChannelByName` (add the last
  one to `.luacheckrc`). A `db.alliancePrefs.chat = true` default with an off switch.

- [ ] **Step 4:** `luacheck Modules/AllianceChat.lua .luacheckrc` clean.

- [ ] **Step 5: Commit** `feat: auto-join and colour the alliance chat channel`

### Task 2: The Alliance tab (overview)

**Files:** Create `UI/AlliancePanel.lua`; modify `UI/RosterFrame.lua`, `GuildOS.toc`, `Locales/*`.

Renders the mockup approved in the design round: a header line (name, tag, guild count, member
count, bridge, channel state), the guild table (online marker, name, ambassadors, last sync, member
count) and the officer action buttons. Registered with
`CreateTab("alliance", L["Alliance"], false, function() return BRutus.Alliance and (BRutus.Alliance:Get() ~= nil or BRutus:IsOfficer()) end)`
so it only appears when there is a pact, or for an officer who could create one.

Data comes exclusively from `Alliance:Get()`, `Alliance:CurrentBridge()` and
`AllianceSync:Remote(guild, domain)`. No business logic in the panel.

- [ ] **Step 1:** Build the panel skeleton with `UI:CreateScrollFrame(holder, name)` followed
  immediately by `scroll:SetAllPoints()`.
- [ ] **Step 2:** Fill the header and guild rows from the module APIs, resetting every visual field
  per row.
- [ ] **Step 3:** Wire the officer buttons to `Alliance:Create/Invite/Leave/RemoveGuild` through
  `StaticPopup` confirmations.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: add the alliance tab with the allied guild overview`

### Task 3: The `board` domain (alliance bulletin)

**Files:** Modify `Modules/AllianceSync.lua`, `UI/AlliancePanel.lua`, `Locales/*`.

Smallest possible domain, and the one that proves the registry works for officer-authored content.

- Spec: `cap = 20`, `priority = "NORMAL"`.
- `build` returns the local guild's posts, newest first, each `{ id, text, by, ts }`, sorted by `id`
  so the fingerprint is stable.
- Posting requires `Alliance.IsAmbassador(pact, myGuild, player)`.
- `text` through `BRutus:SanitizeUserText(text, 200)`.

- [ ] **Step 1:** Self-test for the cap and the sort stability.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement the domain and the Bulletin sub-tab.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: share an alliance bulletin between allied guilds`

---

## Part 3: the `craft` domain

### Task 4: Crafter directory sync

**Files:** Modify `Modules/AllianceSync.lua`, `Locales/*`.

The heavy domain: `priority = "BULK"`, `cap = 5000` recipe entries per guild.

`build` reads `BRutus.RecipeTracker` and emits `{ [itemId] = { crafterIndex, ... } }` flattened into
a deterministic array: `{ i = itemId, c = { crafterIndex... } }` plus a parallel `names` array, so a
crafter name is stored once instead of per recipe. That name-indexing is what keeps a 3200 pair
directory inside the 8 to 15 KB the spec budgeted.

- [ ] **Step 1:** Self-test `_BuildCraft(recipes, cap)` for the cap, deterministic order and the
  name-index round trip via a matching `_ReadCraft`.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement both directions.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: sync a compressed crafter directory across the alliance`

### Task 5: Alliance scope in the recipes panel

**Files:** Modify `UI/RecipesPanel.lua`, `UI/CraftFinder.lua`, `Modules/Alliance.lua`, `Locales/*`.

Adds the Guild / Alliance scope selector from the approved mockup, plus
`Alliance:FindCrafters(itemId) -> { { name, guild, online } }` reading the cached directory, and an
"Ask in alliance channel" button.

- [ ] **Step 1:** Self-test `Alliance:FindCrafters` against a fabricated store.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement the lookup and the scope toggle.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: search allied guild crafters from the recipes panel`

---

## Part 4: the `events` domain and cross-guild signups

### Task 6: Event sharing

**Files:** Modify `Modules/AllianceSync.lua`, `Modules/Calendar.lua`, `Locales/*`.

`cap = 50`, `priority = "NORMAL"`. `build` emits upcoming events only (`when > now`), so the payload
shrinks by itself as events pass.

- [ ] **Step 1:** Self-test that past events are excluded and the cap holds.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: share upcoming events with allied guilds`

### Task 7: Free signup with approval

**Files:** Modify `Modules/Calendar.lua`, `UI/CalendarPanel.lua`, `Modules/Alliance.lua`,
`Locales/*`.

The signup policy chosen in the design round: an allied member signs up freely and lands in a
pending queue that the owning officer approves or declines one by one.

New wire op `EVT` on the `ChehulAlly` protocol, since a signup must not wait for the 120 second
heartbeat. Payload `{ kind = "signup", eventId, role, note }`. The signer's identity and guild come
from the envelope, never the payload. `note` through `SanitizeUserText(note, 60)`.

Failure path from the spec: a signup for an event that already filled comes back as an automatic
decline with a local notice.

- [ ] **Step 1:** Self-test the pure `Calendar._ResolveAllianceSignup(event, pending, decision)`.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement the queue, the `EVT` op and the approval UI inside the existing event
  detail view.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: let allied members request a raid slot for officer approval`

---

## Part 5: LFG scope and the free wins

### Task 8: The `lfg` domain and scope selector

**Files:** Modify `Modules/AllianceSync.lua`, `Modules/LFGBoard.lua`, `UI/FeaturePanels.lua`,
`Locales/*`.

`cap = 100`, `priority = "NORMAL"`, TTL pruned on build so expired entries never cross the wire.

- [ ] **Step 1:** Self-test that expired entries are pruned by `build`.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement the domain and the Guild / Alliance selector.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: pool looking-for-group entries across the alliance`

### Task 9: PugInspector, Digest and chat tags

**Files:** Modify `Modules/PugInspector.lua`, `Modules/Digest.lua`, `Modules/ChatTweaks.lua`,
`Locales/*`.

Three small integrations that need no new sync, because the allied roster is already cached:

- `PugInspector` gains an `allied` classification, ranked between `guildmate` and `unknown`, showing
  the allied guild name.
- `Digest` gains one login line: allied raids in the next 7 days.
- `ChatTweaks` colours an allied guild tag on messages from known allied members.

- [ ] **Step 1:** Self-test the PugInspector classification with explicit facts, matching the
  existing pure-decision test style in that module.
- [ ] **Step 2:** Verify it fails.
- [ ] **Step 3:** Implement all three.
- [ ] **Step 4:** `luacheck` clean.
- [ ] **Step 5: Commit** `feat: flag allied players in the pug inspector, digest and chat`

---

## Self-review against the spec

- 5.1 chat channel: Task 1, with the presence-source scope decision recorded above.
- 5.2 `EVT` op: Task 7, which is the first thing that actually needs it.
- 5.3 domains `board`, `craft`, `events`, `lfg`: Tasks 3, 4, 6, 8.
- 6 UI: Task 2 (overview), Task 3 (bulletin), Task 5 (recipes scope), Task 7 (approval queue),
  Task 8 (LFG scope). All three approved mockups are covered.
- 7 free wins: Task 9.
- 8 failure behaviour: the hollow marker and data age render in Task 2; the automatic decline of a
  signup into a full event is Task 7.
- 9 caps: every domain spec above carries its cap from the spec table.
