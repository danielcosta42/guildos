# Tier 2 #4 — Recruit Scanner Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Active recruiting — `/who`-scan for **unguilded** candidates (class/level filters), skip banned players, mass-whisper the selected ones with a token template, and capture their replies in an inbox. Officer-gated, off by default, fail-safe throughout.

**Architecture:** New `Modules/RecruitScanner.lua` (+ a self-contained `Show()` window). Reuses the fragile `/who` pattern already in `RecruitmentSystem` (auto-invite F4): `SetWhoToUI(1)`/`SendWho`/`WHO_LIST_UPDATE`/`C_FriendList.GetNumWhoResults`/`GetWhoInfo`, queued + timed-out + **fail-safe (empty result, never crash)**. Candidates are filtered to unguilded + not `BanList:IsBanned`. Mass-whisper is throttled + per-name cooldown + batch-capped. Replies from contacted names land in a capped inbox. This is the **highest in-game-verification risk** in Tier 2 (same `/who` API uncertainty as F4).

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. `/who` globals (`SetWhoToUI`, `C_FriendList`, `SendWho`) already allowed.
- **Default OFF, officer-gated.** Mass-whisper: max batch (default 10), per-name cooldown, throttle between sends. Inbox capped (200) + prune.
- `GetGuildRosterInfo` nil-checked. Colors from `BRutus.Colors`. All strings in 5 locales. Rule 10.
- Commits Conventional; **no AI attribution**.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/RecruitScanner.lua` | Create | Config, pure `_ExpandTemplate`/`_CandidateOK` + self-tests; `/who` scan; mass-whisper; reply inbox; `Show()` window. |
| `Core/Core.lua` | Modify | Register `RecruitScanner:Initialize()`. |
| `Core/Commands.lua` | Modify | `/gos scout` opens the window. |
| `GuildOS.toc` | Modify | Add `Modules\RecruitScanner.lua`. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: Module core (config + pure logic) + self-tests

**Files:** Create `Modules/RecruitScanner.lua`; modify `GuildOS.toc`, `Core/Core.lua`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`.
- Produces:
  - `RecruitScanner.DEFAULTS = { template="Hi [player], <Guild> is recruiting level 70s — whisper me if interested!", minLevel=0, maxLevel=70, classes={}, batchMax=10, cooldownSec=1800 }`.
  - `RecruitScanner:_ExpandTemplate(tmpl, cand) -> string` — replaces `[player]`/`[class]`/`[level]`.
  - `RecruitScanner:_CandidateOK(cand, filters, isBannedFn) -> boolean` — `cand = {name, level, class, guilded}`; unguilded + level in [minLevel,maxLevel] + class (if set) + not banned.

- [ ] **Step 1: Create the module + pure logic**

```lua
----------------------------------------------------------------------
-- Guild OS - Recruit Scanner
-- Active recruiting: /who-scan unguilded candidates, mass-whisper a
-- template, capture replies. Officer-gated, OFF by default, fail-safe.
----------------------------------------------------------------------
local RecruitScanner = {}
BRutus.RecruitScanner = RecruitScanner

RecruitScanner.DEFAULTS = {
    template    = "Hi [player], we're recruiting — whisper me if interested!",
    minLevel    = 0,
    maxLevel    = 70,
    classes     = {},     -- set { WARRIOR=true }; empty = any
    batchMax    = 10,
    cooldownSec = 1800,
}

function RecruitScanner:Initialize()
    BRutus.db.recruitScanner = BRutus.db.recruitScanner or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.recruitScanner[k] == nil then
            BRutus.db.recruitScanner[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    BRutus.db.recruitScanner.inbox = BRutus.db.recruitScanner.inbox or {}
    self._results = {}
    self._contactCd = {}
    self._RegisterEvents = self._RegisterEvents or function() end
    self:_RegisterEvents()      -- real body in Task 2 (until then, a stub below)
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure logic (unit-tested)
----------------------------------------------------------------------
function RecruitScanner:_ExpandTemplate(tmpl, cand)
    tmpl = tmpl or ""
    cand = cand or {}
    local out = tmpl
    out = out:gsub("%[player%]", cand.name or "")
    out = out:gsub("%[class%]", cand.class or "")
    out = out:gsub("%[level%]", tostring(cand.level or ""))
    return out
end

function RecruitScanner:_CandidateOK(cand, filters, isBannedFn)
    if not cand or not cand.name then return false end
    if cand.guilded then return false end                       -- unguilded only
    filters = filters or {}
    if (filters.minLevel or 0) > 0 and (cand.level or 0) < filters.minLevel then return false end
    if filters.maxLevel and (cand.level or 0) > filters.maxLevel then return false end
    if filters.classes and next(filters.classes) ~= nil and not filters.classes[cand.class] then return false end
    if isBannedFn and isBannedFn(cand.name) then return false end
    return true
end

function RecruitScanner:_RegisterEvents() end   -- Task 2 replaces this
```

- [ ] **Step 2: Self-tests**

```lua
function RecruitScanner:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("scanner.template", function()
        local s = RecruitScanner:_ExpandTemplate("Hi [player] ([level] [class])",
            { name = "Bob", level = 68, class = "MAGE" })
        if s ~= "Hi Bob (68 MAGE)" then return false, s end
        return true
    end)
    S:Register("scanner.candidate_ok", function()
        local f = { minLevel = 60, maxLevel = 70, classes = { MAGE = true } }
        local ok = RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = false }, f)
        if not ok then return false, "should pass" end
        return true
    end)
    S:Register("scanner.reject_guilded", function()
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = true }, {}) then
            return false, "guilded must be rejected"
        end
        return true
    end)
    S:Register("scanner.reject_banned", function()
        local banned = function(n) return n == "Bob" end
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, guilded = false }, {}, banned) then
            return false, "banned must be rejected"
        end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules)**

`.toc`: add `Modules\RecruitScanner.lua`. `Core/Core.lua InitModules()`: `if BRutus.RecruitScanner then BRutus.RecruitScanner:Initialize() end`.

- [ ] **Step 4: Lint + commit**

luacheck 0/0. (Agent: hand-trace the 4 self-tests. Runtime `/gos selftest` → 35 total.)

```bash
git add Modules/RecruitScanner.lua GuildOS.toc Core/Core.lua
git commit -m "feat: RecruitScanner core (template expansion + candidate filter, tested)"
```

---

## Task 2: `/who` scan engine + mass-whisper + reply inbox

**Files:** Modify `Modules/RecruitScanner.lua`.

**Interfaces:**
- Consumes: `BanList:IsBanned` (Tier 1); `_CandidateOK`, `_ExpandTemplate`; `SetWhoToUI`, `SendWho`, `WHO_LIST_UPDATE`, `C_FriendList.GetNumWhoResults`/`GetWhoInfo`; `BRutus.Compat.After`, `GetServerTime`, `SendChatMessage`, `BRutus:IsOfficer`.
- Produces: `RecruitScanner:Scan(cb)`, `RecruitScanner:GetResults()`, `RecruitScanner:WhisperSelected(names)`, `RecruitScanner:GetInbox()`, real `_RegisterEvents`.

- [ ] **Step 1: `/who` scan (fail-safe)**

```lua
function RecruitScanner:Scan(onDone)
    if not BRutus:IsOfficer() then return end
    if self._scanBusy then return end
    self._scanBusy = true
    self._results = {}
    local cfg = BRutus.db.recruitScanner
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() RecruitScanner:_OnWhoResult() end)
    end
    self._whoFrame:RegisterEvent("WHO_LIST_UPDATE")
    self._onScanDone = onDone
    if SetWhoToUI then SetWhoToUI(1) end
    -- level-range query; Blizzard caps results (~50). classes filtered post-hoc.
    local q = string.format("%d-%d", (cfg.minLevel or 1) > 0 and cfg.minLevel or 1, cfg.maxLevel or 70)
    SendWho(q)
    BRutus.Compat.After(6, function()
        if RecruitScanner._scanBusy then RecruitScanner:_FinishScan() end
    end)
end

function RecruitScanner:_OnWhoResult()
    local cfg = BRutus.db.recruitScanner
    local isBanned = function(n) return BRutus.BanList and BRutus.BanList:IsBanned(n) end
    local out = {}
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName then
                local short = w.fullName:match("^([^-]+)") or w.fullName
                local cand = {
                    name = short, level = w.level, class = w.filename,
                    zone = w.area, guilded = (w.fullGuildName ~= nil and w.fullGuildName ~= ""),
                }
                if self:_CandidateOK(cand, cfg, isBanned) then out[#out + 1] = cand end
            end
        end
    end
    self._results = out
    self:_FinishScan()
end

function RecruitScanner:_FinishScan()
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    if SetWhoToUI then SetWhoToUI(0) end
    self._scanBusy = nil
    if self._onScanDone then BRutus:SafeCall(self._onScanDone) end
end

function RecruitScanner:GetResults() return self._results or {} end
```

- [ ] **Step 2: Mass-whisper (throttled, cooldown, batch-capped)**

```lua
function RecruitScanner:WhisperSelected(names)
    if not BRutus:IsOfficer() then return end
    local cfg = BRutus.db.recruitScanner
    local now = GetServerTime()
    local sent, delay = 0, 0
    for _, name in ipairs(names or {}) do
        if sent >= (cfg.batchMax or 10) then break end
        local cd = self._contactCd[name]
        if not (cd and cd > now) then
            local cand
            for _, r in ipairs(self._results) do if r.name == name then cand = r; break end end
            local msg = self:_ExpandTemplate(cfg.template, cand or { name = name })
            self._contactCd[name] = now + (cfg.cooldownSec or 1800)
            sent = sent + 1
            delay = delay + 1.5    -- throttle: 1.5s between whispers
            BRutus.Compat.After(delay, function()
                SendChatMessage(msg, "WHISPER", nil, name)
            end)
        end
    end
    if sent > 0 then
        BRutus:Print(string.format(BRutus.L["Whispering %d candidate(s)…"], sent))
    end
end
```

- [ ] **Step 3: Reply inbox (`_RegisterEvents` real body)**

```lua
function RecruitScanner:_RegisterEvents()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local short = author and (author:match("^([^-]+)") or author)
        if short and RecruitScanner._contactCd[short] then
            local inbox = BRutus.db.recruitScanner.inbox
            table.insert(inbox, 1, { name = short, msg = msg, ts = GetServerTime() })
            while #inbox > 200 do table.remove(inbox) end
        end
    end)
end

function RecruitScanner:GetInbox() return (BRutus.db.recruitScanner and BRutus.db.recruitScanner.inbox) or {} end
```

- [ ] **Step 4: Lint + commit**

luacheck 0/0. (Agent: static-trace scan (fail-safe empty on timeout/no /who), whisper (batch-cap + cooldown + throttle delay), inbox (only captures replies from contacted names, capped). Flag: `/who` field names + `SendWho` behaviour on BCC 2.5 are the top in-game risk.)

```bash
git add Modules/RecruitScanner.lua
git commit -m "feat: RecruitScanner /who scan, throttled mass-whisper, reply inbox"
```

---

## Task 3: Scanner window + `/gos scout`

**Files:** Modify `Modules/RecruitScanner.lua` (add `Show`), `Core/Commands.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `Scan`/`GetResults`/`WhisperSelected`/`GetInbox`; `UI:*`, `BRutus.Colors`, `RAID_CLASS_COLORS`.

- [ ] **Step 1: `RecruitScanner:Show()`**

Mirror `Bulletin:Show()` (self-contained popup; scroll frame with `SetAllPoints`). Contents:
- **Filters row:** min/max level edit boxes, an optional class filter (keep simple — a text field or skip), a **Scan** button → `self:Scan(refresh)`.
- **Results list** (scroll): each candidate row = a checkbox/selectable name + level + class (class-colored) + zone. Track selection in a local set.
- **Template** edit box (multiline or single) bound to `cfg.template`, with a hint listing tokens `[player] [class] [level]`.
- **Whisper selected** button → `self:WhisperSelected(selectedNames)` (with a confirm popup: "Whisper N players?").
- **Inbox** toggle/section: list `GetInbox()` (name · reply · time).
- Officer-only: if `not BRutus:IsOfficer()`, show a notice instead of the controls.

- [ ] **Step 2: `/gos scout` command**

`Core/Commands.lua handleCommand`: `elseif msg == "scout" or msg == "recruitscan" then if BRutus.RecruitScanner then BRutus.RecruitScanner:Show() end`.

- [ ] **Step 3: Locale + lint + commit**

Add all used keys in all 5 files (`L["Recruit Scanner"]`, `L["Scan"]`, `L["Whisper selected"]`, `L["Whispering %d candidate(s)…"]`, `L["Inbox"]`, `L["No candidates."]`, `L["Min level"]`, `L["Max level"]`, `L["Whisper %d players?"]`, `L["Officers only."]`, etc.).

luacheck 0/0. In-game (human): `/gos scout` opens; Scan finds unguilded candidates (fail-safe empty if /who misbehaves); select + Whisper sends throttled whispers; replies from contacted names show in the inbox. **Verify `/who` behaviour carefully — this is the F4-class risk.**

```bash
git add Modules/RecruitScanner.lua Core/Commands.lua Locales/
git commit -m "feat: Recruit Scanner window (/gos scout) — scan, whisper, inbox"
```

---

## Self-Review
- Spec §Feature-4 (scan unguilded via /who, filters, skip banned, mass-whisper templates, reply inbox) → Tasks 1-3. ✓
- **Fail-safe:** scan empties on timeout/no result; whisper batch-capped + cooldown + throttle; inbox capped. Officer-gated; off by default. ✓
- **Highest in-game risk** (`/who` API on BCC 2.5) — documented, fail-safe degrades to "no candidates", never crash.
- Reuses `BanList:IsBanned`. Types: `cand = {name,level,class,zone,guilded}`; `_ExpandTemplate`/`_CandidateOK` pure + tested.
- Human-verify: `/gos selftest` (35); `/gos scout` scan/select/whisper/inbox; `/who` field-name correctness.
