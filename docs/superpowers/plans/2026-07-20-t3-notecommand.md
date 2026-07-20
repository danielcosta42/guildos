# Tier 3 #2 — `!note` (self public-note) Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Let a guild member set their own **public note** by typing `!note <text>` (or `!note` / `!note clear` to clear) in guild chat — applied by any online client that has note-edit permission (officers), since on Classic/TBC members usually can't self-edit notes.

**Architecture:** New `Modules/NoteCommand.lua`. A `CHAT_MSG_GUILD` handler parses `!note` via a pure `_Parse`, and if the LOCAL client `CanEditPublicNote()`, sets the sender's public note through a Compat helper (`Compat.SetGuildPublicNote(name, text)` → find roster index + `GuildRosterSetPublicNote`, 31-char cap). Per-sender cooldown; redundant sets by multiple officers are idempotent (same value) — acceptable. Fail-safe no-op if the API/permission is absent.

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. Route `GuildRosterSetPublicNote`/`CanEditPublicNote` via `Core/Compat.lua` (Rule 4); add globals to `.luacheckrc` if flagged.
- `local`-scope. Colors from `BRutus.Colors`. Strings in 5 locales. Commits Conventional; **no AI attribution**.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/NoteCommand.lua` | Create | Config, pure `_Parse`, chat hook, self-tests, `/gos notecmd`. |
| `Core/Compat.lua` | Modify | `Compat.SetGuildPublicNote(name, text)` + `Compat.CanEditPublicNote()`. |
| `Core/Core.lua` | Modify | Register `NoteCommand:Initialize()`. |
| `Core/Commands.lua` | Modify | `/gos notecmd on|off`. |
| `GuildOS.toc` | Modify | Add `Modules\NoteCommand.lua`. |
| `.luacheckrc` | Modify | `GuildRosterSetPublicNote`, `CanEditPublicNote` if flagged. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: Module (pure `_Parse` + Compat + hook) + self-tests

**Files:** Create `Modules/NoteCommand.lua`; modify `Core/Compat.lua`, `GuildOS.toc`, `Core/Core.lua`, `.luacheckrc`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `GetNumGuildMembers`/`GetGuildRosterInfo`; `CanEditPublicNote`, `GuildRosterSetPublicNote`; `strtrim`; `BRutus.Compat.After`.
- Produces: `NoteCommand:_Parse(msg) -> text|nil` (pure); `Compat.SetGuildPublicNote(name, text) -> bool`; `Compat.CanEditPublicNote() -> bool`.

- [ ] **Step 1: Compat helpers (`Core/Compat.lua`)**

Append:
```lua

-- Whether this client may edit guild public notes
function Compat.CanEditPublicNote()
    if CanEditPublicNote then return CanEditPublicNote() and true or false end
    return false
end

-- Set a guild member's public note by name (finds the roster index).
-- Returns true if applied. No-op (false) if the API/permission is absent.
function Compat.SetGuildPublicNote(name, text)
    if not name or not GuildRosterSetPublicNote or not (CanEditPublicNote and CanEditPublicNote()) then
        return false
    end
    local short = name:match("^([^-]+)") or name
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local fs = full:match("^([^-]+)") or full
            if fs == short then
                GuildRosterSetPublicNote(i, (text or ""):sub(1, 31))
                return true
            end
        end
    end
    return false
end
```

- [ ] **Step 2: Module + pure parse + hook**

```lua
----------------------------------------------------------------------
-- Guild OS - !note command
-- A member types "!note <text>" in guild chat; any online client with
-- public-note-edit permission (officers) applies it to that member's
-- public note. Useful on Classic/TBC where members can't self-edit notes.
----------------------------------------------------------------------
local NoteCommand = {}
BRutus.NoteCommand = NoteCommand
local L = BRutus.L

function NoteCommand:Initialize()
    BRutus.db.noteCommand = BRutus.db.noteCommand or {}
    if BRutus.db.noteCommand.enabled == nil then BRutus.db.noteCommand.enabled = true end
    self._cd = {}
    self:_SetupHook()
    self:_RegisterTests()
end

-- Pure: returns the note text (<=31, "" to clear) or nil if not a !note command.
function NoteCommand:_Parse(msg)
    if not msg then return nil end
    if msg:match("^!note%s*$") then return "" end
    local rest = msg:match("^!note%s+(.+)$")
    if not rest then return nil end
    rest = strtrim(rest)
    if rest:lower() == "clear" then return "" end
    return rest:sub(1, 31)
end

function NoteCommand:_SetupHook()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local cfg = BRutus.db.noteCommand
        if not cfg or not cfg.enabled then return end
        local text = NoteCommand:_Parse(msg)
        if text == nil then return end
        if not BRutus.Compat.CanEditPublicNote() then return end
        local sender = author and (author:match("^([^-]+)") or author)
        if not sender then return end
        if NoteCommand._cd[sender] then return end
        NoteCommand._cd[sender] = true
        BRutus.Compat.After(15, function() NoteCommand._cd[sender] = nil end)
        if BRutus.Compat.SetGuildPublicNote(sender, text) then
            BRutus:Print(string.format(L["Set %s's note: |cffFFFFFF%s|r"], sender, text ~= "" and text or L["(cleared)"]))
        end
    end)
end
```

- [ ] **Step 3: Self-tests**

```lua
function NoteCommand:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("notecmd.parse_text", function()
        if NoteCommand:_Parse("!note LFG Kara") ~= "LFG Kara" then return false, "text" end
        return true
    end)
    S:Register("notecmd.parse_clear", function()
        if NoteCommand:_Parse("!note") ~= "" then return false, "bare" end
        if NoteCommand:_Parse("!note clear") ~= "" then return false, "clear" end
        return true
    end)
    S:Register("notecmd.not_a_command", function()
        if NoteCommand:_Parse("hello world") ~= nil then return false, "plain" end
        if NoteCommand:_Parse("!notepad rocks") ~= nil then return false, "!notepad must not match" end
        return true
    end)
    S:Register("notecmd.cap31", function()
        local long = "!note " .. string.rep("x", 50)
        if #NoteCommand:_Parse(long) ~= 31 then return false, "cap" end
        return true
    end)
end
```

- [ ] **Step 4: Register (.toc + InitModules + luacheckrc)**

`.toc`: add `Modules\NoteCommand.lua`. `Core/Core.lua InitModules()`: `if BRutus.NoteCommand then BRutus.NoteCommand:Initialize() end`. `.luacheckrc`: add `GuildRosterSetPublicNote`, `CanEditPublicNote` under a `-- Guild notes` comment if flagged.

- [ ] **Step 5: Lint + commit**

luacheck 0/0. (Agent: hand-trace the 4 self-tests, incl. the `!notepad` negative. `/gos selftest` → +4. In-game: an officer with note perms sees a member type `!note LFG` → that member's public note becomes "LFG".)

```bash
git add Modules/NoteCommand.lua Core/Compat.lua GuildOS.toc Core/Core.lua .luacheckrc
git commit -m "feat: !note self public-note command (officers apply; tested)"
```

---

## Task 2: `/gos notecmd` toggle + locales

**Files:** Modify `Modules/NoteCommand.lua`, `Core/Commands.lua`, `Locales/*.lua`.

- [ ] **Step 1: Command**

Add to `NoteCommand`:
```lua
function NoteCommand:HandleCommand(args)
    local cfg = BRutus.db.noteCommand
    if not cfg then return end
    local sub = args[1]
    if sub == "on" then cfg.enabled = true; BRutus:Print(L["!note command |cff4CFF4Con|r."])
    elseif sub == "off" then cfg.enabled = false; BRutus:Print(L["!note command |cffFF4444off|r."])
    else
        local st = cfg.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        BRutus:Print(L["!note command: "] .. st .. L[" — members type !note <text> in guild chat; officers apply it."])
    end
end
```
`Core/Commands.lua`: 
```lua
    elseif msg == "notecmd" or msg:match("^notecmd%s") then
        if BRutus.NoteCommand then
            local rest = strtrim(msg:gsub("^notecmd%s*", ""))
            local a = {}; for w in rest:gmatch("%S+") do a[#a+1] = w end
            BRutus.NoteCommand:HandleCommand(a)
        end
```

- [ ] **Step 2: Locale + lint + commit**

Add used keys in all 5 files (`Set %s's note: |cffFFFFFF%s|r`, `(cleared)`, `!note command |cff4CFF4Con|r.`, `!note command |cffFF4444off|r.`, `!note command: `, ` — members type !note <text> in guild chat; officers apply it.` — reuse `|cff4CFF4CON|r`/`|cffFF4444OFF|r` if present).

luacheck 0/0.

```bash
git add Modules/NoteCommand.lua Core/Commands.lua Locales/
git commit -m "feat: /gos notecmd toggle for the !note command"
```

---

## Self-Review
- Spec §Feature-2 (!note parse, officer-applies via GuildRosterSetPublicNote, 31-cap, cooldown, toggle) → Tasks 1-2. ✓
- Compat-guarded API (fail-safe no-op if absent/no permission). Pure `_Parse` tested incl. `!notepad` negative + cap31.
- Redundant sets by multiple officers = idempotent (documented). Human-verify: `/gos selftest` (+4); officer sees a `!note` → member's public note updates.
