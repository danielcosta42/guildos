# Tier 2 #1b — Auto-detect Own Alts Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Automatically detect the player's own same-(game-)account characters (via the account-wide SavedVariables) and offer, on login, a one-click "link them as alts of [Main]" — reusing the existing officer-authoritative `altLinks` sync safely.

**Architecture:** New `Modules/AltAutoDetect.lua`. An account-wide registry `GuildOSDB.accountChars` (the shared SV root, so it spans every character on the game account) is written on each login. A pure `DetectOwnAlts(accountChars, guildSet, altLinks)` returns the unlinked same-account guild characters + a suggested main (highest level). Linking reuses `BRutus:LinkAlt` (officer-authoritative): if the player is an officer it links directly; if a member, it applies locally + broadcasts a small **self-claim** that officers replay through `LinkAlt` (so a member can only claim their OWN alts, never overwrite the table). A login prompt confirms with one click.

**Why the sync split:** `CommSystem` applies the `ALT_LINK` table only on officer receivers (`CommSystem.lua:253-259`) and `LinkAlt` is officer-gated (`Core/Utils.lua:10-24`) — altLinks is officer-authoritative. The self-claim path lets a member contribute their own alts without breaking that model.

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. `GuildOSDB` is a global SavedVariables table (account-wide) — accessible after login; not the per-guild `BRutus.db`.
- `local`-scope; module `local X={}; BRutus.X=X`. `GetGuildRosterInfo` nil-checked. Keys normalized via `BRutus:GetPlayerKey(short, realm)` (the altLinks key form — see the Tier 2 key-form gotcha).
- Colors from `BRutus.Colors`. All strings in 5 locales. Rule 10. Commits Conventional; **no AI attribution**.
- `accountChars` must survive `/gos reset` (it lives at `GuildOSDB` root, not under the per-guild key that reset wipes) — verify.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/AltAutoDetect.lua` | Create | accountChars registry, record-on-login, pure `DetectOwnAlts`, `LinkOwnAlts`, self-claim send/receive, login prompt, self-tests. |
| `Modules/CommSystem.lua` | Modify | Add `SELF_ALT` message type + dispatch to `AltAutoDetect:HandleSelfClaim`. |
| `Core/Core.lua` | Modify | Register `AltAutoDetect:Initialize()` in InitModules. |
| `GuildOS.toc` | Modify | Add `Modules\AltAutoDetect.lua`. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: accountChars registry + pure DetectOwnAlts + self-tests

**Files:** Create `Modules/AltAutoDetect.lua`; modify `GuildOS.toc`, `Core/Core.lua`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `BRutus:GetPlayerKey`; `GetGuildRosterInfo`/`GetNumGuildMembers`; `UnitName`/`GetRealmName`/`UnitLevel`/`UnitClass`/`GetGuildInfo`.
- Produces:
  - `AltAutoDetect:RecordSelf()` — writes the current char into `GuildOSDB.accountChars`.
  - `AltAutoDetect:_GuildSet() -> { [key]=true }` — current guild members (normalized keys).
  - `AltAutoDetect:DetectOwnAlts(accountChars, guildSet, altLinks) -> { group={key…}, main=key } | nil` — pure.

- [ ] **Step 1: Module + registry + pure detection**

```lua
----------------------------------------------------------------------
-- Guild OS - Alt Auto-Detect
-- Detects the player's own same-account characters via the account-wide
-- SavedVariables (GuildOSDB is shared across all chars on the game account)
-- and offers a one-click link. Own alts only; others' alts are never
-- auto-detectable (no API reveals another player's account).
----------------------------------------------------------------------
local AltAutoDetect = {}
BRutus.AltAutoDetect = AltAutoDetect

function AltAutoDetect:Initialize()
    self:RecordSelf()
    self:_RegisterTests()
    -- login prompt is scheduled by Task 3 (after the roster is available)
    if self._SchedulePrompt then self:_SchedulePrompt() end
end

-- Account-wide registry lives at the GuildOSDB root (shared across every
-- character on the account), NOT under the per-guild db that /gos reset wipes.
function AltAutoDetect:RecordSelf()
    if not GuildOSDB then return end
    GuildOSDB.accountChars = GuildOSDB.accountChars or {}
    local name = UnitName("player")
    if not name then return end
    local key = BRutus:GetPlayerKey(name, GetRealmName())
    local _, classFile = UnitClass("player")
    GuildOSDB.accountChars[key] = {
        name = name, realm = GetRealmName(), class = classFile,
        level = UnitLevel("player"), guild = GetGuildInfo("player"),
        ts = GetServerTime(),
    }
end

function AltAutoDetect:_GuildSet()
    local set = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local short = full:match("^([^-]+)") or full
            local realm = full:match("-(.+)$") or GetRealmName()
            set[BRutus:GetPlayerKey(short, realm)] = true
        end
    end
    return set
end

-- Pure: from the account chars that are ALSO current guild members, if 2+
-- exist and they are not already all linked under one main, return the group
-- and the suggested main (highest level). Else nil.
function AltAutoDetect:DetectOwnAlts(accountChars, guildSet, altLinks)
    altLinks = altLinks or {}
    local group = {}
    for key, info in pairs(accountChars or {}) do
        if guildSet[key] then group[#group + 1] = { key = key, level = info.level or 0 } end
    end
    if #group < 2 then return nil end
    table.sort(group, function(a, b) return a.level > b.level end)
    local main = group[1].key
    -- already fully linked to this main?
    local allLinked = true
    for i = 2, #group do
        if altLinks[group[i].key] ~= main then allLinked = false; break end
    end
    if allLinked then return nil end
    local keys = {}
    for _, g in ipairs(group) do keys[#keys + 1] = g.key end
    return { group = keys, main = main }
end
```

- [ ] **Step 2: Self-tests**

```lua
function AltAutoDetect:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local acc = {
        ["Main-R"] = { level = 70 }, ["Alt-R"] = { level = 61 }, ["Other-R"] = { level = 70 },
    }
    local guild = { ["Main-R"] = true, ["Alt-R"] = true }   -- Other-R not in this guild
    S:Register("altauto.detect", function()
        local r = AltAutoDetect:DetectOwnAlts(acc, guild, {})
        if not r or r.main ~= "Main-R" then return false, "main=highest level in guild" end
        if #r.group ~= 2 then return false, "only guild members grouped" end
        return true
    end)
    S:Register("altauto.needs_two", function()
        if AltAutoDetect:DetectOwnAlts(acc, { ["Main-R"] = true }, {}) ~= nil then return false, "need 2+" end
        return true
    end)
    S:Register("altauto.already_linked", function()
        if AltAutoDetect:DetectOwnAlts(acc, guild, { ["Alt-R"] = "Main-R" }) ~= nil then
            return false, "already linked => nil"
        end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules)**

`.toc`: add `Modules\AltAutoDetect.lua`. `Core/Core.lua InitModules()`: `if BRutus.AltAutoDetect then BRutus.AltAutoDetect:Initialize() end`. (Runs after login; `GuildOSDB` exists by then.)

- [ ] **Step 4: Lint + commit**

luacheck 0/0 (add `GuildOSDB`, `UnitClass`, `UnitLevel` to `.luacheckrc` only if flagged — most are already there). Hand-trace the 3 self-tests. `/gos selftest` → +3.

```bash
git add Modules/AltAutoDetect.lua GuildOS.toc Core/Core.lua .luacheckrc
git commit -m "feat: AltAutoDetect account-wide registry + own-alt detection (tested)"
```

---

## Task 2: LinkOwnAlts + self-claim sync

**Files:** Modify `Modules/AltAutoDetect.lua`, `Modules/CommSystem.lua`.

**Interfaces:**
- Consumes: `BRutus:LinkAlt` (officer path), `BRutus:IsOfficer`, `BRutus.db.altLinks`, `CommSystem:SendMessage`, `LibSerialize`.
- Produces: `AltAutoDetect:LinkOwnAlts(mainKey, altKeys)`; `AltAutoDetect:HandleSelfClaim(sender, data)`.

- [ ] **Step 1: LinkOwnAlts (officer direct vs member self-claim)**

```lua
function AltAutoDetect:LinkOwnAlts(mainKey, altKeys)
    if not mainKey or not altKeys then return end
    if BRutus:IsOfficer() then
        -- authoritative path: LinkAlt writes db.altLinks + BroadcastAltLinks
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then BRutus:LinkAlt(k, mainKey) end
        end
    else
        -- member: apply locally (own view) + broadcast a self-claim officers replay
        BRutus.db.altLinks = BRutus.db.altLinks or {}
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then BRutus.db.altLinks[k] = mainKey end
        end
        if BRutus.CommSystem then
            local payload = LibSerialize:Serialize({ main = mainKey, alts = altKeys })
            BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.SELF_ALT, payload)
        end
    end
    if BRutus.AltRoster then BRutus:SafeCall(function() end) end   -- (UI refreshers pick up on next repaint)
end

-- Officer applies a member's self-claim through the authoritative LinkAlt path.
function AltAutoDetect:HandleSelfClaim(sender, data)
    if not BRutus:IsOfficer() then return end       -- only officers apply/propagate
    local ok, claim = LibSerialize:Deserialize(data)
    if not ok or type(claim) ~= "table" or not claim.main or type(claim.alts) ~= "table" then return end
    for _, k in ipairs(claim.alts) do
        if k ~= claim.main then BRutus:LinkAlt(k, claim.main) end
    end
end
```

_(Note: `LinkAlt`'s existing circular-link guard (main must not itself be an alt) still applies. The self-claim is trusted as "these are my own alts" — low harm; an officer can `UnlinkAlt` a bad claim. Document this.)_

- [ ] **Step 2: CommSystem message type + dispatch**

In `Modules/CommSystem.lua`: add to `MSG_TYPES`:
```lua
    SELF_ALT  = "SA",    -- member self-claim of own alts (officers replay via LinkAlt)
```
In `OnMessageReceived` dispatch (near the `ALT_LINK` branch), add:
```lua
    elseif msgType == CommSystem.MSG_TYPES.SELF_ALT then
        if BRutus.AltAutoDetect then BRutus.AltAutoDetect:HandleSelfClaim(sender, data) end
```

- [ ] **Step 3: Lint + commit**

luacheck 0/0. (Agent: static-trace — officer `LinkOwnAlts` → `LinkAlt` ×N (authoritative + sync); member → local write + SELF_ALT broadcast; officer receiving SELF_ALT → `LinkAlt` ×N → propagates. In-game / 2-client is the human checkpoint.)

```bash
git add Modules/AltAutoDetect.lua Modules/CommSystem.lua
git commit -m "feat: self-alt linking — officer direct, member self-claim officers replay"
```

---

## Task 3: Login suggestion prompt (one-click)

**Files:** Modify `Modules/AltAutoDetect.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `DetectOwnAlts`, `_GuildSet`, `LinkOwnAlts`; `StaticPopupDialogs`/`StaticPopup_Show` (or a small frame).

- [ ] **Step 1: Schedule + show the prompt**

Add `_SchedulePrompt` (called from Initialize) that, after the roster is ready (`BRutus.Compat.After(10, …)` — cold-login timing), computes `DetectOwnAlts(GuildOSDB.accountChars, self:_GuildSet(), BRutus.db.altLinks)` and, if non-nil AND not dismissed this session AND not previously declined for this exact set, shows a confirm:
- Register once: `StaticPopupDialogs["GUILDOS_ALT_AUTODETECT"]` with text `string.format(L["Found %d of your characters in this guild. Link them as alts of %s?"], #group-... , shortMain)` (count the alts = #group-1; main = short name of `main`). Buttons: `L["Link"]` → `AltAutoDetect:LinkOwnAlts(main, group)`; `L["Not now"]` → record a session-dismiss.
- Guard: show at most once per session (`self._prompted`), and remember a persistent "declined" marker keyed by the sorted group so it doesn't nag every login (`GuildOSDB.accountChars` or a small `db` flag). Re-offer if the group changes (a new alt appears).
- Officer-vs-member: the prompt is identical; `LinkOwnAlts` routes correctly.
- Add a manual trigger too: `/gos myalts` (or reuse `/gos`): `AltAutoDetect:PromptNow()` that ignores the session/declined guards so the user can invoke it on demand.

- [ ] **Step 2: `/gos myalts` command**

In `Core/Commands.lua`: `elseif msg == "myalts" then if BRutus.AltAutoDetect then BRutus.AltAutoDetect:PromptNow() end`.

- [ ] **Step 3: Locale + lint + commit**

Add all keys in 5 files: `L["Found %d of your characters in this guild. Link them as alts of %s?"]`, `L["Link"]` (may exist — reuse), `L["Not now"]`, `L["Linked %d alt(s) to %s."]`, `L["No other characters of yours found in this guild."]` (for the manual trigger's empty case).

luacheck 0/0. In-game (human): log an alt in the same guild → the prompt offers to link to your highest-level char; Link → alts grouped (True Roster/tag reflect it); `/gos myalts` re-offers on demand.

```bash
git add Modules/AltAutoDetect.lua Core/Commands.lua Locales/
git commit -m "feat: login prompt + /gos myalts to auto-link own detected alts"
```

---

## Self-Review
- Auto-detect own same-account alts → Tasks 1-3. Scope limit (own game-account chars that ran the addon; not others' alts) documented.
- Reuses officer-authoritative `LinkAlt`/sync; member self-claim replayed by officers (safe — can't overwrite the table). ✓
- `accountChars` at `GuildOSDB` root survives `/gos reset` (per-guild wipe). Keys normalized to `GetPlayerKey` (the Tier 2 gotcha). ✓
- Pure `DetectOwnAlts` tested; prompt guarded against nagging (session + declined-set).
- Human-verify: `/gos selftest` (+3); login prompt on an alt; Link → grouping; member self-claim propagates via an online officer; `/gos myalts`.
- **Deferred:** cross-account (Bnet) detection (not possible via SV trick); auto-relink when an alt is renamed.
