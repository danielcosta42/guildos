# Alliance Foundation Implementation Plan (part 1 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the alliance pact, its trust model, deterministic bridge election, the cross-guild
wire protocol and the `roster` domain end to end, with no on-screen UI.

**Architecture:** Embassy model from `docs/superpowers/specs/2026-07-29-alliance-design.md`. One
bridge client per guild, elected by a pure function every client computes identically. Bridges
whisper each other over the shared `_G.ChehulMesh` transport using the open `ChehulAlly` protocol.
Whatever a bridge learns is republished inside its own guild through `SyncService` domain
`"alliance"`, so a regular member never sends anything cross-guild.

**Tech Stack:** Lua 5.1, WoW BCC client API (Interface 20506), LibSerialize, LibDeflate, AceComm-3.0
via `_G.ChehulMesh`, existing `SyncService` / `CommSystem` / `SelfTest` harnesses.

## Global Constraints

- Lua 5.1 only. No goto, no bitwise operators, no `//`. Guard every API that may be absent.
- 4-space indent, no tabs, no trailing semicolons, `local` at file scope, early returns.
- Modules register on `GuildOS.*` (new mesh-facing code) or `BRutus.*` (legacy alias of the same
  table, `Core/Core.lua:9-10`). Alliance code uses `GuildOS.Alliance` / `GuildOS.AllianceSync`.
- Persistent state lives under `BRutus.db` (already guild-scoped) and must be initialised in
  `Initialize()`, never at file scope.
- Identity is always the comm envelope sender, never a name inside the payload.
- All member-authored text goes through `BRutus:SanitizeUserText(text, maxBytes)`.
- Every number arriving from the wire is clamped before use.
- `blocked` is local-only: stripped on send, discarded on receive.
- Caps: 16 guilds, 8 ambassadors per guild, 300 roster entries per guild.
- Protocol: prefix `ChehulAlly`, proto `AL1`. Unknown proto is ignored silently.
- No new on-screen panel in this plan. A native `StaticPopup` confirmation is allowed (system
  dialog, not a designed screen).
- Commit style is Conventional Commits; the commit subject **is** the changelog line, and CI owns
  `.toc` version bumps and `CHANGELOG.md`. Never edit those two by hand.

## Verification reality

There is no Lua interpreter on this machine, so plan steps cannot run unit tests headlessly. The
verification loop for every task is:

1. `luacheck` over the changed files, which **must** report `0 warnings / 0 errors`.
2. Self-test cases registered with the existing `BRutus.SelfTest` harness
   (`Modules/SelfTest.lua`), run in-client by the user with `/gos selftest`.

Every task below states both. A task is not complete until luacheck is clean; the `/gos selftest`
result is reported to the user at the end rather than gating each commit.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Modules/Alliance.lua` (create) | Pact state, pure helpers, trust checks, bridge election, `ChehulAlly` wire ops (INV/ACK/PACT/LEAVE), slash commands. |
| `Modules/AllianceSync.lua` (create) | Domain registry, HEAD/PULL/PUSH, remote snapshot store, guild-channel fanout, the `roster` domain. |
| `GuildOS.toc` (modify) | Load both after `SyncService`, before the UI block. |
| `Core/Core.lua` (modify) | `InitModules` wiring. |
| `Core/Commands.lua` (modify) | `/gos ally` dispatch + help lines. |
| `Locales/enUS.lua`, `Locales/ptBR.lua` (modify) | New strings. |

---

### Task 1: Alliance module skeleton and pure string helpers

**Files:**
- Create: `Modules/Alliance.lua`
- Modify: `GuildOS.toc` (add `Modules\Alliance.lua` after `Modules\SyncService.lua`)

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register(name, fn)`, `BRutus:SanitizeUserText(text, maxBytes)`.
- Produces:
  - `Alliance.NormalizeTag(tag) -> string` uppercase `[A-Z0-9]` only, capped at 12, `""` when invalid.
  - `Alliance.ChannelName(tag) -> string|nil` `"GOS"..normalizedTag`, `nil` when the tag is empty.
  - `Alliance.Hash(s) -> number` djb2, non-negative, deterministic across clients.

- [ ] **Step 1: Write the failing self-test cases**

In `Modules/Alliance.lua`, inside `Alliance:_RegisterTests()`:

```lua
    BRutus.SelfTest:Register("alliance.normalize_tag", function()
        if Alliance.NormalizeTag("brcore") ~= "BRCORE" then return false, "not uppercased" end
        if Alliance.NormalizeTag(" br-core! ") ~= "BRCORE" then return false, "punctuation kept" end
        if Alliance.NormalizeTag("abcdefghijklmno") ~= "ABCDEFGHIJKL" then return false, "not capped at 12" end
        if Alliance.NormalizeTag("...") ~= "" then return false, "empty result expected" end
        if Alliance.NormalizeTag(nil) ~= "" then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.channel_name", function()
        if Alliance.ChannelName("brcore") ~= "GOSBRCORE" then return false, "bad channel name" end
        if Alliance.ChannelName("...") ~= nil then return false, "empty tag must yield nil" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.hash_is_stable", function()
        local a = Alliance.Hash("Chehul-Nefarian")
        if a ~= Alliance.Hash("Chehul-Nefarian") then return false, "not deterministic" end
        if a < 0 then return false, "must be non-negative" end
        if Alliance.Hash("Chehul-Nefarian") == Alliance.Hash("Chehul-Ragnaros") then
            return false, "realm must affect the hash"
        end
        if Alliance.Hash("") ~= 5381 then return false, "djb2 seed changed" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: three FAIL/ERROR lines for `alliance.*` because the functions do not exist yet.

- [ ] **Step 3: Implement the helpers**

```lua
Alliance.TAG_MAX = 12

function Alliance.NormalizeTag(tag)
    local s = tostring(tag or ""):upper():gsub("[^A-Z0-9]", "")
    if #s > Alliance.TAG_MAX then s = s:sub(1, Alliance.TAG_MAX) end
    return s
end

function Alliance.ChannelName(tag)
    local t = Alliance.NormalizeTag(tag)
    if t == "" then return nil end
    return "GOS" .. t
end

-- djb2. PART OF THE PROTOCOL: every client must compute the same number or two
-- clients will disagree about who the bridge is. Do not swap this for anything
-- that varies by client, locale, or table iteration order.
function Alliance.Hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483648
    end
    return h
end
```

Note: `("x"):gsub()` returns two values, so `NormalizeTag` must wrap the chain in parentheses or
assign before returning. Write it as shown (assignment first), never `return s:gsub(...)`.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/Alliance.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/Alliance.lua GuildOS.toc
git commit -m "feat: add alliance module skeleton with tag, channel and hash helpers"
```

---

### Task 2: Deterministic bridge election

**Files:**
- Modify: `Modules/Alliance.lua`

**Interfaces:**
- Consumes: `Alliance.Hash`.
- Produces: `Alliance.ElectBridge(onlineKeys) -> string|nil`. `onlineKeys` is an array of
  `"Name-Realm"` strings. Returns the key with the lowest `Alliance.Hash`, breaking ties by
  lexicographic order of the key itself so the result never depends on array order. Returns `nil`
  for an empty or nil list.

- [ ] **Step 1: Write the failing self-test case**

```lua
    BRutus.SelfTest:Register("alliance.elect_bridge", function()
        local keys = { "Ann-R", "Bob-R", "Cid-R" }
        local first = Alliance.ElectBridge(keys)
        if not first then return false, "no bridge elected" end
        -- Order of the input must not change the outcome.
        if Alliance.ElectBridge({ "Cid-R", "Ann-R", "Bob-R" }) ~= first then
            return false, "election depends on input order"
        end
        -- The winner really is the lowest hash.
        for _, k in ipairs(keys) do
            if Alliance.Hash(k) < Alliance.Hash(first) then return false, "not the lowest hash" end
        end
        if Alliance.ElectBridge({}) ~= nil then return false, "empty list must yield nil" end
        if Alliance.ElectBridge(nil) ~= nil then return false, "nil must not error" end
        if Alliance.ElectBridge({ "Solo-R" }) ~= "Solo-R" then return false, "single candidate" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on `alliance.elect_bridge`.

- [ ] **Step 3: Implement**

```lua
-- Pure. Given every online GuildOS client of this guild as "Name-Realm" keys,
-- return the one that acts as the bridge. Lowest djb2 wins; a hash collision is
-- broken by the key string itself, so the answer never depends on table order.
function Alliance.ElectBridge(onlineKeys)
    if type(onlineKeys) ~= "table" then return nil end
    local best, bestHash
    for _, key in ipairs(onlineKeys) do
        if type(key) == "string" and key ~= "" then
            local h = Alliance.Hash(key)
            if not best or h < bestHash or (h == bestHash and key < best) then
                best, bestHash = key, h
            end
        end
    end
    return best
end
```

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/Alliance.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/Alliance.lua
git commit -m "feat: elect the alliance bridge deterministically from online guild clients"
```

---

### Task 3: Pact state, sanitisation and conflict resolution

**Files:**
- Modify: `Modules/Alliance.lua`

**Interfaces:**
- Consumes: `BRutus:SanitizeUserText`, `Alliance.NormalizeTag`.
- Produces:
  - `Alliance.MAX_GUILDS = 16`, `Alliance.MAX_AMBASSADORS = 8`, `Alliance.NAME_MAX = 32`
  - `Alliance.SerializePact(pact) -> table` deep copy with `blocked` removed.
  - `Alliance.SanitizePact(raw) -> table|nil` validates an incoming pact, sanitises text, clamps to
    the caps, drops `blocked`, returns `nil` when the shape is unusable.
  - `Alliance.ResolvePact(current, incoming) -> table` highest `revision` wins; on a tie the copy
    whose `owner` matches `current.owner` wins; `current` wins when both are equal.
  - `Alliance.IsAmbassador(pact, guildName, playerName) -> boolean` short-name comparison.

- [ ] **Step 1: Write the failing self-test cases**

```lua
    local function samplePact()
        return {
            tag = "BRCORE", name = "Nucleo BR", owner = "Guild A", revision = 100,
            guilds = {
                ["Guild A"] = { ambassadors = { "Chehul" } },
                ["Guild B"] = { ambassadors = { "Beltrano" } },
            },
            blocked = { ["Guild C"] = true },
        }
    end

    BRutus.SelfTest:Register("alliance.serialize_strips_blocked", function()
        local out = Alliance.SerializePact(samplePact())
        if out.blocked ~= nil then return false, "blocked leaked onto the wire" end
        if out.guilds["Guild A"] == nil then return false, "guilds lost" end
        local src = samplePact()
        out.guilds["Guild A"].ambassadors[1] = "Tampered"
        if src.guilds["Guild A"].ambassadors[1] ~= "Chehul" then return false, "not a deep copy" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_drops_blocked", function()
        local incoming = samplePact()
        local out = Alliance.SanitizePact(incoming)
        if not out then return false, "valid pact rejected" end
        if out.blocked ~= nil then return false, "incoming blocked was kept" end
        if Alliance.SanitizePact(nil) ~= nil then return false, "nil must be rejected" end
        if Alliance.SanitizePact({ tag = "" }) ~= nil then return false, "tagless pact must be rejected" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_clamps", function()
        local p = samplePact()
        for i = 1, 40 do p.guilds["Filler " .. i] = { ambassadors = { "Amb" .. i } } end
        for i = 1, 30 do p.guilds["Guild A"].ambassadors[i] = "Amb" .. i end
        local out = Alliance.SanitizePact(p)
        local n = 0
        for _ in pairs(out.guilds) do n = n + 1 end
        if n > Alliance.MAX_GUILDS then return false, "guild cap not enforced: " .. n end
        if #out.guilds["Guild A"].ambassadors > Alliance.MAX_AMBASSADORS then
            return false, "ambassador cap not enforced"
        end
        return true
    end)

    BRutus.SelfTest:Register("alliance.resolve_pact", function()
        local cur = samplePact()
        local newer = samplePact(); newer.revision = 200
        if Alliance.ResolvePact(cur, newer).revision ~= 200 then return false, "newer must win" end
        local older = samplePact(); older.revision = 50
        if Alliance.ResolvePact(cur, older).revision ~= 100 then return false, "older must lose" end
        local tie = samplePact(); tie.owner = "Guild B"
        if Alliance.ResolvePact(cur, tie).owner ~= "Guild A" then
            return false, "tie must keep the current owner copy"
        end
        if Alliance.ResolvePact(nil, newer).revision ~= 200 then return false, "no current pact" end
        if Alliance.ResolvePact(cur, nil).revision ~= 100 then return false, "no incoming pact" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.is_ambassador", function()
        local p = samplePact()
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul") then return false, "known ambassador rejected" end
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul-Nefarian") then return false, "realm suffix broke it" end
        if Alliance.IsAmbassador(p, "Guild B", "Chehul") then return false, "wrong guild accepted" end
        if Alliance.IsAmbassador(p, "Guild Z", "Chehul") then return false, "unknown guild accepted" end
        if Alliance.IsAmbassador(nil, "Guild A", "Chehul") then return false, "nil pact accepted" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on all five new `alliance.*` cases.

- [ ] **Step 3: Implement**

Add the caps, then the five functions. `SerializePact` deep-copies via `BRutus:DeepCopy`
(`Core/Utils.lua:95`) and then sets `blocked = nil`. `SanitizePact` rejects when `raw` is not a
table, when `NormalizeTag(raw.tag)` is `""`, or when `raw.guilds` is not a table; it sanitises
`name` with `BRutus:SanitizeUserText(raw.name, Alliance.NAME_MAX)`, sanitises every guild key and
ambassador name, clamps `revision` with `tonumber(...) or 0`, keeps at most `MAX_GUILDS` guilds
(iterating a sorted key list so the truncation is deterministic) and `MAX_AMBASSADORS` per guild,
and always sets `blocked = nil`. `ResolvePact` compares `revision` and applies the owner tie-break.
`IsAmbassador` compares `Ambiguate(name, "short")` against each stored ambassador, also ambiguated.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/Alliance.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/Alliance.lua
git commit -m "feat: sanitise, cap and resolve alliance pacts with an owner tie-break"
```

---

### Task 4: Pact lifecycle and persistence

**Files:**
- Modify: `Modules/Alliance.lua`
- Modify: `Core/Core.lua` (`InitModules`, after the `SyncService` block)

**Interfaces:**
- Produces:
  - `Alliance:Initialize()` creates `BRutus.db.alliance` lazily, registers the mesh handler and the
    self-tests, and starts the heartbeat ticker.
  - `Alliance:Get() -> table|nil` the live pact, or `nil` when this guild is in no alliance.
  - `Alliance:MyGuildName() -> string|nil` from `GetGuildInfo("player")`.
  - `Alliance:IsMemberGuild(name) -> boolean`
  - `Alliance:IsBlocked(name) -> boolean`
  - `Alliance:OnlineGuildKeys() -> table` array of `"Name-Realm"` for online guildmates known to run
    GuildOS (guild roster online set intersected with `db.members[key].addonVersion`).
  - `Alliance:CurrentBridge() -> string|nil` and `Alliance:AmBridge() -> boolean`, both debounced by
    30 seconds against flapping.
  - `Alliance:Create(tag, name) -> boolean, string` officer only.
  - `Alliance:Leave()`, `Alliance:RemoveGuild(name)` (owner only), `Alliance:Block(name)`,
    `Alliance:Unblock(name)`.

- [ ] **Step 1: Write the failing self-test case for the debounce**

```lua
    BRutus.SelfTest:Register("alliance.bridge_debounce", function()
        -- Pure form: _DebouncedBridge(prev, candidate, prevAt, now, hold)
        local r = Alliance._DebouncedBridge(nil, "Ann-R", 0, 100, 30)
        if r ~= "Ann-R" then return false, "first election must apply immediately" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 110, 30)
        if r ~= "Ann-R" then return false, "must hold the previous bridge inside the window" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 140, 30)
        if r ~= "Bob-R" then return false, "must switch after the hold window" end
        r = Alliance._DebouncedBridge("Ann-R", nil, 100, 140, 30)
        if r ~= nil then return false, "no candidates means no bridge" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on `alliance.bridge_debounce`.

- [ ] **Step 3: Implement the lifecycle**

`_DebouncedBridge(prev, candidate, prevAt, now, hold)` returns `candidate` when `prev` is nil or
`candidate` is nil or `now - prevAt >= hold`, otherwise `prev`. `CurrentBridge()` calls it with the
stored `_bridgeAt` timestamp from `GetServerTime()` and `ElectBridge(self:OnlineGuildKeys())`,
persisting the result in memory only (never in SavedVariables, it is derived state).

`Create` refuses when `not BRutus:IsOfficer()`, when a pact already exists, or when the normalized
tag is empty, returning `false, reason`. On success it writes `BRutus.db.alliance` with this guild
as `owner`, the caller as the sole ambassador, and `revision = GetServerTime()`.

Wire `Alliance:Initialize()` into `Core/Core.lua:InitModules`, immediately after the
`BRutus.SyncService:Initialize()` block, guarded with `if BRutus.Alliance then`.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/Alliance.lua Core/Core.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/Alliance.lua Core/Core.lua
git commit -m "feat: persist the alliance pact and expose a debounced bridge role"
```

---

### Task 5: ChehulAlly wire protocol (INV, ACK, PACT, LEAVE)

**Files:**
- Modify: `Modules/Alliance.lua`

**Interfaces:**
- Consumes: `_G.ChehulMesh:Register(prefix, handler)` and `:Whisper(prefix, payload, target)`.
- Produces:
  - `Alliance.PREFIX = "ChehulAlly"`, `Alliance.PROTO = "AL1"`
  - `Alliance.Encode(tbl) -> string|nil` LibSerialize then LibDeflate `CompressDeflate` then
    `EncodeForWoWAddonChannel`.
  - `Alliance.Decode(str) -> table|nil` the exact inverse, returning `nil` on any failure.
  - `Alliance:Invite(officerName) -> boolean, string`
  - `Alliance:OnMessage(payload, sender, dist)` routes `INV`/`ACK`/`PACT`/`LEAVE`.

- [ ] **Step 1: Write the failing self-test case**

```lua
    BRutus.SelfTest:Register("alliance.encode_roundtrip", function()
        local src = { tag = "BRCORE", revision = 42, guilds = { ["G A"] = { ambassadors = { "Ann" } } } }
        local wire = Alliance.Encode(src)
        if type(wire) ~= "string" or wire == "" then return false, "encode produced nothing" end
        if wire:find("|", 1, true) then return false, "wire payload must not contain a pipe" end
        local back = Alliance.Decode(wire)
        if not back then return false, "decode failed" end
        if back.tag ~= "BRCORE" or back.revision ~= 42 then return false, "fields lost" end
        if back.guilds["G A"].ambassadors[1] ~= "Ann" then return false, "nested table lost" end
        if Alliance.Decode("not a real payload") ~= nil then return false, "garbage must decode to nil" end
        if Alliance.Decode(nil) ~= nil then return false, "nil must not error" end
        return true
    end)
```

The pipe assertion matters: the wire format is `AL1|OP|<blob>` split with `strsplit("|", ...)`, so a
blob containing `|` would corrupt routing. `EncodeForWoWAddonChannel` guarantees it does not.

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on `alliance.encode_roundtrip`.

- [ ] **Step 3: Implement the protocol**

Wire format `AL1|<OP>|<blob>`, routed with `strsplit("|", payload, 3)` so the blob keeps any
remaining characters. `OnMessage` rejects, in this order: wrong proto (silent), `dist ~= "WHISPER"`
(silent, this kills party and yell injection), sender equal to the local player, a sender whose
guild is in `blocked`.

- `INV`: only when this guild has no pact. Sanitise, then raise a `StaticPopup` naming the sender and
  the alliance. Accepting replies `ACK` with this guild's name and ambassador list and stores the
  pact. Rate limited to one prompt per sender per 30 seconds.
- `ACK`: only accepted by an officer who has an outstanding invite to that sender. Adds the guild,
  bumps `revision` to `GetServerTime()`, then pushes `PACT` to every member guild.
- `PACT`: accepted only when `Alliance.IsAmbassador(currentPact, senderGuild, sender)` passes, where
  `senderGuild` is resolved from the incoming pact, never from a payload field. Applied through
  `ResolvePact`.
- `LEAVE`: same ambassador check; removes only the sender's own guild.

`senderGuild` resolution: find the guild in the **current** pact that lists the sender as an
ambassador. For the very first `INV` there is no current pact, which is exactly why an invite always
needs a human to accept.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/Alliance.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/Alliance.lua
git commit -m "feat: add the ChehulAlly invite, accept, pact and leave wire protocol"
```

---

### Task 6: Slash commands

**Files:**
- Modify: `Core/Commands.lua`
- Modify: `Locales/enUS.lua`, `Locales/ptBR.lua`

**Interfaces:**
- Consumes: everything from Tasks 4 and 5.
- Produces: `/gos ally` (status), `/gos ally create <tag> <name>`, `/gos ally invite <officer>`,
  `/gos ally leave`, `/gos ally kick <guild>`, `/gos ally block <guild>`, `/gos ally unblock <guild>`.

- [ ] **Step 1: Add the dispatch branch**

Follow the existing dispatch shape in `Core/Commands.lua`. Officer-only verbs (`create`, `invite`,
`kick`) print the refusal from inside `Modules/Alliance.lua`, matching how the other modules refuse,
so the command table stays a thin router.

Argument parsing warning, from `project_tier3` memory: `strtrim(gsub(...))` truncated every slash
argument at the digit `1` in a previous feature. Parse with `msg:match("^(%S+)%s*(.*)$")` and
`strtrim` the parts separately. Never chain `gsub` into `strtrim` here.

- [ ] **Step 2: Add the help lines**

In `printHelp()`, add `/gos ally` under the `General` header, and the officer verbs inside the
existing `if BRutus:IsOfficer() then` block.

- [ ] **Step 3: Add locale strings**

Add every new `L[]` key to `Locales/enUS.lua` (master list) and `Locales/ptBR.lua`.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Core/Commands.lua Locales/enUS.lua Locales/ptBR.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Core/Commands.lua Locales/enUS.lua Locales/ptBR.lua
git commit -m "feat: add /gos ally commands for pact creation and membership"
```

---

### Task 7: AllianceSync domain registry and remote store

**Files:**
- Create: `Modules/AllianceSync.lua`
- Modify: `GuildOS.toc` (after `Modules\Alliance.lua`), `Core/Core.lua` (`InitModules`)

**Interfaces:**
- Produces:
  - `AllianceSync:Register(domain, spec)` where `spec = { build = fn() -> table, apply = fn(guild, data), cap = number, priority = "BULK"|"NORMAL" }`.
  - `AllianceSync:LocalRevision(domain) -> number` and `:BumpLocal(domain) -> number`.
  - `AllianceSync:Remote(guild, domain) -> table|nil` returns `{ rev, data, ts }`.
  - `AllianceSync:StoreRemote(guild, domain, rev, data)` writes `BRutus.db.allianceData[guild][domain]`, refusing a `rev` that is not strictly greater.
  - `AllianceSync.ShouldPull(localRev, remoteRev) -> boolean` pure, `remoteRev > localRev`.

- [ ] **Step 1: Write the failing self-test cases**

```lua
    BRutus.SelfTest:Register("alliancesync.should_pull", function()
        if not AllianceSync.ShouldPull(1, 2) then return false, "behind must pull" end
        if AllianceSync.ShouldPull(2, 2) then return false, "equal must not pull" end
        if AllianceSync.ShouldPull(3, 2) then return false, "ahead must not pull" end
        if AllianceSync.ShouldPull(nil, 2) ~= true then return false, "nil local counts as zero" end
        if AllianceSync.ShouldPull(1, nil) ~= false then return false, "nil remote must not pull" end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.store_is_monotonic", function()
        BRutus.db.allianceData = {}
        AllianceSync:StoreRemote("Guild B", "roster", 10, { a = 1 })
        AllianceSync:StoreRemote("Guild B", "roster", 5, { a = 2 })
        local got = AllianceSync:Remote("Guild B", "roster")
        if not got then return false, "nothing stored" end
        if got.rev ~= 10 then return false, "an older revision overwrote a newer one" end
        if got.data.a ~= 1 then return false, "stale data applied" end
        AllianceSync:StoreRemote("Guild B", "roster", 11, { a = 3 })
        if AllianceSync:Remote("Guild B", "roster").data.a ~= 3 then return false, "newer rejected" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on both `alliancesync.*` cases.

- [ ] **Step 3: Implement**

`BRutus.db.allianceData[guildName][domain] = { rev = number, data = table, ts = GetServerTime() }`,
initialised in `Initialize()`. `StoreRemote` clamps `rev` with `tonumber(rev) or 0` and returns early
unless it is strictly greater than the stored one.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/AllianceSync.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/AllianceSync.lua GuildOS.toc Core/Core.lua
git commit -m "feat: add the alliance domain registry and monotonic remote snapshot store"
```

---

### Task 8: HEAD, PULL and PUSH between bridges

**Files:**
- Modify: `Modules/AllianceSync.lua`

**Interfaces:**
- Consumes: `Alliance.Encode/Decode`, `Alliance:AmBridge()`, `Alliance:Get()`, `_G.ChehulMesh:Whisper`.
- Produces:
  - `AllianceSync:PeerTarget(guildName) -> string|nil` resolved in order: alliance channel roster,
    then `ChehulNet` peers, then the cached `roster` domain for that guild.
  - `AllianceSync:Tick()` every 120 seconds, no-op unless `Alliance:AmBridge()`.
  - `AllianceSync.RateLimitOk(lastAt, now, window) -> boolean` pure.

- [ ] **Step 1: Write the failing self-test case**

```lua
    BRutus.SelfTest:Register("alliancesync.rate_limit", function()
        if not AllianceSync.RateLimitOk(nil, 1000, 60) then return false, "first send must pass" end
        if AllianceSync.RateLimitOk(1000, 1030, 60) then return false, "inside the window must fail" end
        if not AllianceSync.RateLimitOk(1000, 1060, 60) then return false, "at the window must pass" end
        if not AllianceSync.RateLimitOk(1000, 9999, 60) then return false, "well past must pass" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on `alliancesync.rate_limit`.

- [ ] **Step 3: Implement the three operations**

Extend `Alliance:OnMessage` routing with `HEAD`, `PULL` and `PUSH`, all whisper-only.

- `HEAD` carries `{ guild = myGuild, revs = { [domain] = rev } }`. A receiver compares each domain
  with `ShouldPull` and answers `PULL` for the domains it is behind on.
- `PULL` carries `{ domain }`. **Any** online member may answer for its own guild, since inside the
  alliance that data is public. The responder replies `PUSH` with the local snapshot, priority from
  the domain spec.
- `PUSH` carries `{ guild, domain, rev, data }`. The receiver takes `guild` from the *pact lookup of
  the sender*, not from the payload, then `StoreRemote`, then fans out to its own guild.
- One `PUSH` per domain per sender per 60 seconds, enforced with `RateLimitOk`.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/AllianceSync.lua Modules/Alliance.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/AllianceSync.lua Modules/Alliance.lua
git commit -m "feat: sync alliance domains between guild bridges over head, pull and push"
```

---

### Task 9: Guild-channel fanout and the roster domain

**Files:**
- Modify: `Modules/AllianceSync.lua`

**Interfaces:**
- Consumes: `BRutus.SyncService:Publish/On`, `BRutus.db.members`.
- Produces:
  - `AllianceSync:Fanout(guild, domain, rev, data)` publishes `SyncService` domain `"alliance"`,
    action `"snap"`.
  - The `roster` domain spec: `build` emits at most 300 entries of
    `{ n = shortName, c = class, l = level, p = professionsString, m = mainKey }`.
  - `AllianceSync.TrustedFanout(sender, bridge, isOfficer) -> boolean` pure.

- [ ] **Step 1: Write the failing self-test cases**

```lua
    BRutus.SelfTest:Register("alliancesync.trusted_fanout", function()
        if not AllianceSync.TrustedFanout("Ann-R", "Ann-R", false) then return false, "the bridge must be trusted" end
        if not AllianceSync.TrustedFanout("Ann-R", "Bob-R", true) then return false, "an officer must be trusted" end
        if AllianceSync.TrustedFanout("Ann-R", "Bob-R", false) then return false, "a random member must be refused" end
        if AllianceSync.TrustedFanout(nil, "Bob-R", false) then return false, "nil sender must be refused" end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.roster_build_caps", function()
        local src = {}
        for i = 1, 500 do src["P" .. i .. "-R"] = { name = "P" .. i, class = "MAGE", level = 70 } end
        local out = AllianceSync._BuildRoster(src, 300)
        if #out ~= 300 then return false, "cap not enforced: " .. #out end
        if not out[1].n then return false, "missing name field" end
        if AllianceSync._BuildRoster(nil, 300) == nil then return false, "nil source must not error" end
        return true
    end)
```

- [ ] **Step 2: Verify it fails**

Run in-client: `/gos selftest`
Expected: FAIL on both cases.

- [ ] **Step 3: Implement**

`"alliance"` is deliberately **not** added to `SyncService.OFFICER_DOMAINS`, because the bridge is
often not an officer. The handler enforces trust itself with `TrustedFanout(sender, Alliance:CurrentBridge(), BRutus:IsOfficerByName(sender))`.
`_BuildRoster(members, cap)` iterates a sorted key list so truncation is deterministic across
clients, and reports the dropped count through `BRutus.Logger.Debug` rather than silently.

- [ ] **Step 4: Verify luacheck is clean**

Run: `luacheck Modules/AllianceSync.lua`
Expected: `0 warnings / 0 errors`

- [ ] **Step 5: Commit**

```bash
git add Modules/AllianceSync.lua
git commit -m "feat: fan alliance snapshots into the guild and publish the roster domain"
```

---

### Task 10: Full-file lint and self-test sweep

**Files:** all of the above.

- [ ] **Step 1: Lint the whole addon**

Run: `luacheck .`
Expected: `0 warnings / 0 errors` (the repository baseline; anything new is a regression).

- [ ] **Step 2: Confirm load order**

Read `GuildOS.toc` and verify `Modules\Alliance.lua` and `Modules\AllianceSync.lua` sit after
`Modules\SyncService.lua` and before the `# UI` block. A file cannot reference a module defined in a
file loaded after it (`.cursorrules`).

- [ ] **Step 3: Report the self-test list to the user**

Print the list of new `/gos selftest` case names so the user knows what to expect in-client.

- [ ] **Step 4: Commit anything outstanding**

```bash
git add -A
git commit -m "chore: lint sweep for the alliance foundation"
```

---

## Self-review against the spec

- Spec section 4 (trust and pact): Tasks 3, 4, 5. `blocked` stripping is asserted by
  `alliance.serialize_strips_blocked` and `alliance.sanitize_drops_blocked`.
- Spec section 5.2 (wire protocol): Task 5 covers INV/ACK/PACT/LEAVE, Task 8 covers HEAD/PULL/PUSH.
  `EVT` is deliberately deferred to the plan that introduces the first live-event domain (`events`),
  since there is nothing to send until then.
- Spec section 5.3 (domains): the registry is Task 7 and `roster` is Task 9. `craft`, `events`,
  `lfg` and `board` belong to plans 3, 4 and 5.
- Spec section 5.4 (bridge election): Tasks 2 and 4, including the djb2 pinning test.
- Spec section 5.5 (cadence): Task 8, 120 second tick, 60 second per-domain rate limit.
- Spec section 9 (limits and hardening): caps in Task 3 and Task 9, whisper-only and sender-bound
  identity in Task 5, rate limits in Task 8.
- Spec section 10 (testing): every pure function listed there has a case, except the ones that
  belong to later plans (domain conflict resolution beyond `ShouldPull`, cap clamping for `craft`).
- Spec sections 5.1 (chat channel), 6 (UI), 7 (free wins) and 8 (failure UI) are explicitly out of
  scope here and belong to plans 2 through 5.

## Not in this plan

Chat channel auto-join, the Alliance panel, the `craft` / `events` / `lfg` / `board` domains, the
cross-guild signup approval queue, and the PugInspector, Digest and ChatTweaks integrations. Each
gets its own plan under `docs/superpowers/plans/2026-07-29-alliance-*`.
