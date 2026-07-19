# Auto-invite (Roster Admin & Audit — Subsistema 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a whispered keyword (`ginv`) auto-invite a player to the guild, gated by the ban list, an officer opt-in, a per-name cooldown, and optional level/class filters resolved via `/who`.

**Architecture:** Extends `Modules/RecruitmentSystem.lua` (owns invites already: `HookChatInvite`, `GuildInvite`, `CanGuildInvite`, `DEFAULT_SETTINGS`/`db.recruitment`). A `CHAT_MSG_WHISPER` hook matches the keyword; the flow checks opt-in + invite permission + `BanList:IsBanned` (from subsystem 1) + cooldown, then invites. If level/class filters are configured, an async `/who` lookup (`SetWhoToUI`/`SendWho`/`WHO_LIST_UPDATE`, queued, timed-out, **fail-safe = skip**) qualifies the player first. Config via `/gos autoinvite …` commands plus a compact toggle in Settings. Pure logic (keyword match, cooldown, filter check) is TDD'd via the `/gos selftest` harness.

**Tech Stack:** Lua 5.1 (TBC Anniversary / BCC, Interface 20506), SyncService not needed (no shared state — auto-invite is a per-officer local behavior), luacheck.

## Global Constraints

- **Client:** BCC Interface **20506**. `C_Timer` via `BRutus.Compat.*`.
- **Lint gate (mandatory per task):** `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc` → **0 warnings / 0 errors**. New WoW globals → `read_globals` in `.luacheckrc` under a section comment.
- **No new sync/domain.** Auto-invite is a local per-client behavior (each officer opts in on their own client). No SavedVariables growth beyond a small config table + an in-memory cooldown table.
- Officer/permission gate: only act when `CanGuildInvite()` is true and the officer enabled auto-invite.
- **Fail-safe:** when a `/who` filter lookup can't confirm the player, the default `whoFallback = "skip"` means **do not invite** — auto-invite must never invite someone who fails or can't be confirmed against a set filter.
- Every user-facing string in all 5 locales: `Locales/enUS.lua` (master) + `ptBR`, `esES`, `deDE`, `frFR`.
- `GetGuildRosterInfo`/`GetNumGuildMembers` 1-indexed, nil-checked. Colors from `BRutus.Colors`.
- **Commits:** Conventional Commits. **No `Co-Authored-By` / AI attribution.**

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Modules/RecruitmentSystem.lua` | Modify | `autoInvite` config defaults; pure helpers (`_MatchKeyword`, `_OnInviteCooldown`, `_MarkInvited`, `_PassesFilters`); whisper hook + flow; `/who` filter path; `autoinvite` sub-commands; self-tests. |
| `Core/Commands.lua` | Modify | `/gos autoinvite …` top-level alias → recruit handler. |
| `UI/FeaturePanels.lua` | Modify | Compact, labeled auto-invite toggle block in the Recruitment settings area. |
| `.luacheckrc` | Modify | Add `SetWhoToUI`, `C_FriendList` globals. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: Config defaults + pure logic + self-tests

**Files:** Modify `Modules/RecruitmentSystem.lua`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register` (subsystem 1).
- Produces:
  - `Recruitment.AUTOINVITE_DEFAULTS` = `{ enabled=false, keyword="ginv", minLevel=0, classes={}, cooldownSec=300, whoFallback="skip" }` (`classes` is a set: `{ WARRIOR=true }`).
  - `Recruitment:_MatchKeyword(msg, keyword) -> boolean` — trimmed, case-insensitive; true if msg == keyword or msg starts with `keyword` followed by a space.
  - `Recruitment:_OnInviteCooldown(name, now, store?) -> boolean` — `store` defaults `self._inviteCd`.
  - `Recruitment:_MarkInvited(name, now, cooldownSec, store?)` — sets `store[name] = now + cooldownSec`.
  - `Recruitment:_PassesFilters(info, cfg) -> boolean` — `info = { level, class }`; passes when `cfg.minLevel==0 or info.level>=cfg.minLevel`, and (`cfg.classes` empty or `cfg.classes[info.class]`).

- [ ] **Step 1: Add the defaults + helpers**

In `Modules/RecruitmentSystem.lua`, after the `DEFAULT_SETTINGS` table, add:

```lua
-- Auto-invite defaults (merged into db.recruitment.autoInvite on Initialize).
Recruitment.AUTOINVITE_DEFAULTS = {
    enabled     = false,
    keyword     = "ginv",
    minLevel    = 0,
    classes     = {},        -- set: { WARRIOR = true, ... }; empty = any class
    cooldownSec = 300,
    whoFallback = "skip",    -- "skip" (fail-safe) or "invite" when /who can't confirm
}
```

Add the pure helpers (place them in a clearly commented "Auto-invite" section):

```lua
----------------------------------------------------------------------
-- Auto-invite: pure helpers (deterministic; unit-tested via /gos selftest)
----------------------------------------------------------------------
function Recruitment:_MatchKeyword(msg, keyword)
    local m = strtrim(msg or ""):lower()
    local k = (keyword or ""):lower()
    if k == "" then return false end
    return m == k or m:sub(1, #k + 1) == (k .. " ")
end

function Recruitment:_OnInviteCooldown(name, now, store)
    store = store or self._inviteCd or {}
    local exp = store[name]
    return exp ~= nil and exp > (now or 0)
end

function Recruitment:_MarkInvited(name, now, cooldownSec, store)
    store = store or self._inviteCd
    if not store then self._inviteCd = {}; store = self._inviteCd end
    store[name] = (now or 0) + (cooldownSec or 300)
end

function Recruitment:_PassesFilters(info, cfg)
    if not info then return false end
    if (cfg.minLevel or 0) > 0 and (info.level or 0) < cfg.minLevel then return false end
    if cfg.classes and next(cfg.classes) ~= nil then
        if not cfg.classes[info.class] then return false end
    end
    return true
end
```

- [ ] **Step 2: Merge the defaults in Initialize**

In `Recruitment:Initialize()`, after the existing "Fill missing keys" loop for `DEFAULT_SETTINGS`, add:

```lua
    -- Auto-invite config (fill missing keys the same way)
    r.autoInvite = r.autoInvite or {}
    for k, v in pairs(self.AUTOINVITE_DEFAULTS) do
        if r.autoInvite[k] == nil then
            r.autoInvite[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    self._inviteCd = {}
    self:_RegisterAutoInviteTests()
```

- [ ] **Step 3: Write the failing self-tests**

Add:

```lua
function Recruitment:_RegisterAutoInviteTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("autoinvite.keyword_exact", function()
        if not Recruitment:_MatchKeyword("  GINV ", "ginv") then return false, "exact should match" end
        return true
    end)
    S:Register("autoinvite.keyword_prefix", function()
        if not Recruitment:_MatchKeyword("ginv please", "ginv") then return false, "prefix should match" end
        if Recruitment:_MatchKeyword("ginvite me", "ginv") then return false, "must not match 'ginvite'" end
        return true
    end)
    S:Register("autoinvite.cooldown", function()
        local store = { Bob = 500 }
        if not Recruitment:_OnInviteCooldown("Bob", 400, store) then return false, "should be on cd" end
        if Recruitment:_OnInviteCooldown("Bob", 600, store) then return false, "cd should be over" end
        return true
    end)
    S:Register("autoinvite.filters", function()
        local cfg = { minLevel = 60, classes = { WARRIOR = true } }
        if not Recruitment:_PassesFilters({ level = 70, class = "WARRIOR" }, cfg) then return false, "should pass" end
        if Recruitment:_PassesFilters({ level = 58, class = "WARRIOR" }, cfg) then return false, "level fail" end
        if Recruitment:_PassesFilters({ level = 70, class = "MAGE" }, cfg) then return false, "class fail" end
        return true
    end)
end
```

- [ ] **Step 4: Verify (`/gos selftest` is the human checkpoint) + lint**

Run: `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc` → 0/0. (Agent: hand-trace the 4 cases in the report; runtime `/gos selftest` should show the prior 8 plus these 4 = 12, verified in-client by the human.)

- [ ] **Step 5: Commit**

```bash
git add Modules/RecruitmentSystem.lua
git commit -m "feat: auto-invite config + pure keyword/cooldown/filter logic (tested)"
```

---

## Task 2: Whisper hook + core flow + commands + locales

**Files:** Modify `Modules/RecruitmentSystem.lua`, `Core/Commands.lua`, `Locales/*.lua`.

**Interfaces:**
- Consumes: Task 1 helpers; `BRutus.BanList:IsBanned` (subsystem 1); `CanGuildInvite`, `GuildInvite`, `GetServerTime`, `BRutus.Compat.After`.
- Produces:
  - `Recruitment:_DoInvite(name)` — invites, marks cooldown, prints (assumes checks already passed).
  - `Recruitment:_HandleKeywordWhisper(sender)` — ban-gate → cooldown → (filters via Task 3, else) `_DoInvite`.
  - `Recruitment:HandleAutoInviteCommand(args)` — `on|off|keyword <x>|status`.

- [ ] **Step 1: Register the whisper hook in Initialize**

In `Recruitment:Initialize()` (near `RegisterWelcomeEvent`), add `self:RegisterAutoInviteEvent()` and define:

```lua
function Recruitment:RegisterAutoInviteEvent()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local cfg = BRutus.db.recruitment and BRutus.db.recruitment.autoInvite
        if not cfg or not cfg.enabled then return end
        if not CanGuildInvite() then return end
        if not Recruitment:_MatchKeyword(msg, cfg.keyword) then return end
        local sender = author and (author:match("^([^-]+)") or author)
        if sender and sender ~= "" then
            Recruitment:_HandleKeywordWhisper(sender)
        end
    end)
end
```

- [ ] **Step 2: Implement the flow**

```lua
function Recruitment:_DoInvite(name)
    local cfg = BRutus.db.recruitment.autoInvite
    GuildInvite(name)
    self:_MarkInvited(name, GetServerTime(), cfg.cooldownSec)
    BRutus:Print(string.format(L["Auto-invited |cffFFFFFF%s|r to the guild."], name))
end

function Recruitment:_HandleKeywordWhisper(sender)
    local cfg = BRutus.db.recruitment.autoInvite
    -- Ban gate (BanList already alerts on a banned whisper)
    if BRutus.BanList and BRutus.BanList:IsBanned(sender) then return end
    -- Cooldown
    if self:_OnInviteCooldown(sender, GetServerTime()) then return end
    -- Filters: no filter set → invite now. (Task 3 inserts the /who path when filters are set.)
    if (cfg.minLevel or 0) == 0 and (not cfg.classes or next(cfg.classes) == nil) then
        self:_DoInvite(sender)
    else
        self:_DoInvite(sender)   -- Task 3 replaces this branch with a /who-qualified invite
    end
end
```

_(Note for the Task 3 implementer: replace the `else` branch above with the `/who` lookup. Kept as a direct invite here so Task 2 is shippable and functional for the common no-filter case.)_

- [ ] **Step 3: Command sub-handler + top-level alias**

In the recruit command handler (the `if cmd == ... elseif` chain, before the final `else` help block), add:

```lua
    elseif cmd == "autoinvite" or cmd == "ai" then
        table.remove(args, 1)
        Recruitment:HandleAutoInviteCommand(args)
```

Add the handler:

```lua
function Recruitment:HandleAutoInviteCommand(args)
    local cfg = BRutus.db.recruitment.autoInvite
    local sub = args[1]
    if sub == "on" then
        cfg.enabled = true
        BRutus:Print(L["Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"] .. cfg.keyword .. "|r).")
    elseif sub == "off" then
        cfg.enabled = false
        BRutus:Print(L["Auto-invite |cffFF4444disabled|r."])
    elseif sub == "keyword" then
        local kw = args[2] and strtrim(args[2]:lower())
        if kw and kw ~= "" then
            cfg.keyword = kw
            BRutus:Print(L["Auto-invite keyword set to |cffFFFFFF"] .. kw .. "|r.")
        else
            BRutus:Print(L["Current keyword: |cffFFFFFF"] .. cfg.keyword .. "|r.")
        end
    else
        local st = cfg.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        BRutus:Print(L["Auto-invite: "] .. st .. L[" · keyword: |cffFFFFFF"] .. cfg.keyword ..
            L["|r · min level: |cffFFFFFF"] .. tostring(cfg.minLevel) .. "|r")
        BRutus:Print(L["Usage: /gos autoinvite <on|off|keyword|minlevel|class|status>"])
    end
end
```

In `Core/Commands.lua`, add a top-level alias (before the help/else branch):

```lua
    elseif msg == "autoinvite" or msg:match("^autoinvite%s") or msg == "ai" or msg:match("^ai%s") then
        if BRutus.Recruitment then
            local rest = strtrim(msg:gsub("^ai%s*", ""):gsub("^autoinvite%s*", ""))
            local a = {}
            for w in rest:gmatch("%S+") do a[#a + 1] = w end
            BRutus.Recruitment:HandleAutoInviteCommand(a)
        end
```

- [ ] **Step 4: Locales (all 5 files)**

enUS master (translate the same keys in ptBR/esES/deDE/frFR in-style):

```lua
L["Auto-invited |cffFFFFFF%s|r to the guild."] = "Auto-invited |cffFFFFFF%s|r to the guild."
L["Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"] = "Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"
L["Auto-invite |cffFF4444disabled|r."] = "Auto-invite |cffFF4444disabled|r."
L["Auto-invite keyword set to |cffFFFFFF"] = "Auto-invite keyword set to |cffFFFFFF"
L["Current keyword: |cffFFFFFF"] = "Current keyword: |cffFFFFFF"
L["Auto-invite: "] = "Auto-invite: "
L[" · keyword: |cffFFFFFF"] = " · keyword: |cffFFFFFF"
L["|r · min level: |cffFFFFFF"] = "|r · min level: |cffFFFFFF"
L["Usage: /gos autoinvite <on|off|keyword|minlevel|class|status>"] = "Usage: /gos autoinvite <on|off|keyword|minlevel|class|status>"
```

- [ ] **Step 5: Lint + verify + commit**

luacheck 0/0. In-game (human): `/gos autoinvite on`, whisper `ginv` from a non-banned alt → invite fires; from a banned name → no invite; repeat within 5 min → cooldown blocks.

```bash
git add Modules/RecruitmentSystem.lua Core/Commands.lua Locales/
git commit -m "feat: keyword auto-invite flow (ban-gate, cooldown) + commands"
```

---

## Task 3: `/who` filter path + filter config commands + luacheckrc

**Files:** Modify `Modules/RecruitmentSystem.lua`, `.luacheckrc`, `Locales/*.lua`.

**Interfaces:**
- Consumes: Task 1 `_PassesFilters`; Task 2 `_DoInvite`. WoW `/who`: `SetWhoToUI`, `SendWho`, `WHO_LIST_UPDATE`, `C_FriendList.GetNumWhoResults`, `C_FriendList.GetWhoInfo`.
- Produces: `Recruitment:_QualifyAndInvite(sender)` (async, fail-safe); filter config in `HandleAutoInviteCommand` (`minlevel <n>`, `class <add|remove|clear> <CLASS>`).

- [ ] **Step 1: luacheckrc globals**

In `.luacheckrc` `read_globals`, under a `-- /who lookups` comment, add `"SetWhoToUI"` and `"C_FriendList"` (if not already present). (`SendWho` is already there.)

- [ ] **Step 2: The `/who` qualify path (fail-safe)**

Add:

```lua
-- Async /who lookup, one query at a time. Fail-safe: on timeout / no result,
-- apply whoFallback ("skip" = do NOT invite).
function Recruitment:_QualifyAndInvite(sender)
    self._whoPending = self._whoPending or {}
    if self._whoBusy then
        -- one lookup at a time; drop extra concurrent triggers (cooldown will let them retry)
        return
    end
    self._whoBusy = sender
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() Recruitment:_OnWhoResult() end)
    end
    self._whoFrame:RegisterEvent("WHO_LIST_UPDATE")
    if SetWhoToUI then SetWhoToUI(1) end   -- results to the API, not the Social frame
    SendWho('n-"' .. sender .. '"')
    -- Timeout: /who is throttled; give it 6s then fail-safe.
    BRutus.Compat.After(6, function()
        if Recruitment._whoBusy == sender then Recruitment:_FinishWho(sender, nil) end
    end)
end

function Recruitment:_OnWhoResult()
    local sender = self._whoBusy
    if not sender then return end
    local info
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName and (w.fullName:match("^([^-]+)") or w.fullName) == sender then
                info = { level = w.level, class = w.filename }
                break
            end
        end
    end
    self:_FinishWho(sender, info)
end

function Recruitment:_FinishWho(sender, info)
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    if SetWhoToUI then SetWhoToUI(0) end
    self._whoBusy = nil
    local cfg = BRutus.db.recruitment.autoInvite
    -- Re-check cooldown/ban in case time passed.
    if BRutus.BanList and BRutus.BanList:IsBanned(sender) then return end
    if self:_OnInviteCooldown(sender, GetServerTime()) then return end
    if info then
        if self:_PassesFilters(info, cfg) then self:_DoInvite(sender) end
    else
        -- couldn't confirm → fail-safe
        if cfg.whoFallback == "invite" then self:_DoInvite(sender) end
    end
end
```

- [ ] **Step 3: Wire the filter branch into `_HandleKeywordWhisper`**

Replace the Task 2 `else` branch in `_HandleKeywordWhisper` with:

```lua
    else
        self:_QualifyAndInvite(sender)
    end
```

- [ ] **Step 4: Filter config commands**

In `HandleAutoInviteCommand`, add before the `else`:

```lua
    elseif sub == "minlevel" then
        local n = tonumber(args[2])
        if n and n >= 0 then
            cfg.minLevel = n
            BRutus:Print(string.format(L["Auto-invite min level set to |cffFFFFFF%d|r."], n))
        else
            BRutus:Print(L["Usage: /gos autoinvite minlevel <0-70>"])
        end
    elseif sub == "class" then
        local op, cls = args[2], args[3] and args[3]:upper()
        if op == "clear" then
            cfg.classes = {}
            BRutus:Print(L["Auto-invite class filter cleared."])
        elseif (op == "add" or op == "remove") and cls then
            cfg.classes[cls] = (op == "add") and true or nil
            BRutus:Print(L["Auto-invite class filter updated."])
        else
            BRutus:Print(L["Usage: /gos autoinvite class <add|remove|clear> <CLASS>"])
        end
```

- [ ] **Step 5: Locales (all 5) + lint + commit**

Add (enUS master; translate the rest):

```lua
L["Auto-invite min level set to |cffFFFFFF%d|r."] = "Auto-invite min level set to |cffFFFFFF%d|r."
L["Usage: /gos autoinvite minlevel <0-70>"] = "Usage: /gos autoinvite minlevel <0-70>"
L["Auto-invite class filter cleared."] = "Auto-invite class filter cleared."
L["Auto-invite class filter updated."] = "Auto-invite class filter updated."
L["Usage: /gos autoinvite class <add|remove|clear> <CLASS>"] = "Usage: /gos autoinvite class <add|remove|clear> <CLASS>"
```

luacheck 0/0. In-game (human): set `minlevel 60`; whisper `ginv` from a level-70 alt (invited) vs a low-level one (skipped); with `/who` off/failing, confirm fail-safe skip.

```bash
git add Modules/RecruitmentSystem.lua .luacheckrc Locales/
git commit -m "feat: /who-qualified auto-invite filters (level/class), fail-safe"
```

---

## Task 4: Settings toggle (compact, labeled)

**Files:** Modify `UI/FeaturePanels.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `db.recruitment.autoInvite`; `UI:CreateCheckbox`, `UI:CreateText`, `BRutus.Colors`.

- [ ] **Step 1: Find the recruitment settings area**

Run `grep -n "recruitment\|Recruit\|welcome" UI/FeaturePanels.lua` to locate where recruitment options are rendered (the General or a Recruitment settings section). Add the auto-invite block there, matching the surrounding builder style.

- [ ] **Step 2: Add a compact, labeled block**

A header + one checkbox + a hint line (keyword/filters are configured via `/gos autoinvite …`; keep the panel minimal to avoid clutter):

```lua
-- Auto-invite (officer opt-in)
local aiHeader = UI:CreateHeaderText(parent, L["AUTO-INVITE"], 11)
-- ...anchor per the surrounding section...
local aiChk = UI:CreateCheckbox(parent, L["Auto-invite players who whisper the keyword"], 18)
aiChk.checkbox:SetChecked(BRutus.db.recruitment.autoInvite.enabled)
aiChk.checkbox.onChanged = function(_, checked)
    BRutus.db.recruitment.autoInvite.enabled = checked
end
local aiHint = UI:CreateText(parent,
    L["Keyword & level/class filters: /gos autoinvite. Banned players are never invited."],
    9, C.silver.r, C.silver.g, C.silver.b)
```

(Anchor the three elements consistently with the section's existing layout; use `C = BRutus.Colors`.)

- [ ] **Step 3: Locales (all 5) + lint + commit**

```lua
L["AUTO-INVITE"] = "AUTO-INVITE"
L["Auto-invite players who whisper the keyword"] = "Auto-invite players who whisper the keyword"
L["Keyword & level/class filters: /gos autoinvite. Banned players are never invited."] = "Keyword & level/class filters: /gos autoinvite. Banned players are never invited."
```

luacheck 0/0. In-game (human): the checkbox toggles auto-invite and reflects `/gos autoinvite on/off`.

```bash
git add UI/FeaturePanels.lua Locales/
git commit -m "feat: auto-invite toggle in recruitment settings"
```

---

## Self-Review

**Spec coverage (design spec §6):**
- §6.1 whisper trigger, no coordination → Task 2 whisper hook. ✓
- §6.2 config model → Task 1 defaults (races dropped — documented YAGNI: localized race strings are fragile and low-value). ✓
- §6.3 flow (enabled+officer, ban-gate, cooldown, filters via /who, invite) → Tasks 2 (core) + 3 (/who). ✓
- §6.4 commands + settings → Tasks 2–4. ✓
- §6.5 edge cases (cooldown, /who throttle/fail, one-at-a-time) → Task 3 `_whoBusy` + timeout + fail-safe. ✓

**Deviations (intentional, documented):** race filter dropped; auto-invite config surfaced mainly via commands with a minimal settings toggle (avoids UI clutter/risk).

**Type consistency:** `_MatchKeyword/_OnInviteCooldown/_MarkInvited/_PassesFilters/_DoInvite/_HandleKeywordWhisper/_QualifyAndInvite/HandleAutoInviteCommand` used consistently. `cfg` = `db.recruitment.autoInvite` throughout. `info = {level, class}` produced in `_OnWhoResult`, consumed by `_PassesFilters`.

**Human-verification (no client here):** `/gos selftest` (12 cases), whisper-triggered invite, ban-gate, cooldown, /who filter + fail-safe, settings toggle.
