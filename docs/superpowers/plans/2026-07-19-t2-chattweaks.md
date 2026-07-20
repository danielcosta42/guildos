# Tier 2 #2 — Chat Enhancements Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Optionally annotate guild/officer chat lines with a class icon, the sender's level, and an alt/main tag — added as a safe **message prefix** (never touches the author/name link), off by default.

**Architecture:** New `Modules/ChatTweaks.lua`. A lightweight cache (short name → `{classFile, level, fullKey}`) refreshed on `GUILD_ROSTER_UPDATE` (never per-message). `ChatFrame_AddMessageEventFilter` on `CHAT_MSG_GUILD`/`CHAT_MSG_OFFICER` prepends a pure-built prefix to the message text. Alt tag comes from Tier 2 #1 `BRutus:GetAltTag`. A "CHAT" settings block toggles each part. **Message-prefix (not name-modification)** is deliberate: it can't break click-to-whisper links. **Race icon dropped** (GetGuildRosterInfo doesn't return race reliably on BCC).

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0**. New globals `CLASS_ICON_TCOORDS`, `ChatFrame_AddMessageEventFilter` → `.luacheckrc` if flagged.
- `local`-scope; module `local X={}; BRutus.X=X`. `GetGuildRosterInfo` nil-checked, 1-indexed.
- Colors from `BRutus.Colors`. All user-facing strings in all 5 locales. Rule 10.
- Commits Conventional; **no AI attribution**.
- **Default OFF** (opt-in) — a fresh install is unaffected; the chat filter only runs when `db.chatTweaks.enabled`.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/ChatTweaks.lua` | Create | Config defaults, roster cache, pure `_BuildPrefix`/`_ClassIcon`, chat filters, self-tests. |
| `Core/Core.lua` | Modify | Register `ChatTweaks:Initialize()` in InitModules. |
| `GuildOS.toc` | Modify | Add `Modules\ChatTweaks.lua`. |
| `UI/FeaturePanels.lua` | Modify | "CHAT" settings block (toggles). |
| `.luacheckrc` | Modify | Add `CLASS_ICON_TCOORDS`, `ChatFrame_AddMessageEventFilter` if flagged. |
| `Locales/*.lua` (×5) | Modify | New strings. |

---

## Task 1: ChatTweaks module (cache + prefix + filters) + self-tests

**Files:** Create `Modules/ChatTweaks.lua`; modify `GuildOS.toc`, `Core/Core.lua`, `.luacheckrc`.

**Interfaces:**
- Consumes: `BRutus.SelfTest:Register`; `BRutus:GetAltTag` (T2#1); `GetGuildRosterInfo`/`GetNumGuildMembers`; `CLASS_ICON_TCOORDS`; `ChatFrame_AddMessageEventFilter`.
- Produces: `ChatTweaks:_ClassIcon(classFile) -> string`; `ChatTweaks:_BuildPrefix(info, cfg) -> string` (`info = {classFile, level, altTag}`); `ChatTweaks:_RefreshCache()`.

- [ ] **Step 1: Create the module**

```lua
----------------------------------------------------------------------
-- Guild OS - Chat Tweaks
-- Optional guild/officer chat annotations (class icon + level + alt tag),
-- added as a safe MESSAGE PREFIX (never modifies the author/name link).
-- Off by default. Cache refreshed on GUILD_ROSTER_UPDATE, never per line.
----------------------------------------------------------------------
local ChatTweaks = {}
BRutus.ChatTweaks = ChatTweaks

ChatTweaks.DEFAULTS = {
    enabled   = false,
    guild     = true,
    officer   = true,
    classIcon = true,
    level     = true,
    altTag    = true,
}

local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"

function ChatTweaks:Initialize()
    BRutus.db.chatTweaks = BRutus.db.chatTweaks or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.chatTweaks[k] == nil then BRutus.db.chatTweaks[k] = v end
    end
    self._cache = {}

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() ChatTweaks:_RefreshCache() end)

    self:_RegisterFilters()
    self:_RegisterTests()
end

function ChatTweaks:_RefreshCache()
    local cache = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            cache[short] = { classFile = classFile, level = level, fullKey = name }
        end
    end
    self._cache = cache
end

----------------------------------------------------------------------
-- Pure prefix building (unit-tested)
----------------------------------------------------------------------
function ChatTweaks:_ClassIcon(classFile)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if not c then return "" end
    return string.format("|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t",
        CLASS_TEX, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

function ChatTweaks:_BuildPrefix(info, cfg)
    if not info then return "" end
    local parts = {}
    if cfg.classIcon and info.classFile then
        local ic = self:_ClassIcon(info.classFile)
        if ic ~= "" then parts[#parts + 1] = ic end
    end
    if cfg.level and info.level and info.level > 0 then
        parts[#parts + 1] = "[" .. info.level .. "]"
    end
    if cfg.altTag and info.altTag then
        parts[#parts + 1] = "|cff888888(" .. info.altTag .. ")|r"
    end
    return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Chat filters (message-prefix only; returns false = keep line, modified)
----------------------------------------------------------------------
function ChatTweaks:_MakeFilter()
    return function(_, _, msg, author, ...)
        local cfg = BRutus.db.chatTweaks
        if not cfg or not cfg.enabled then return false end
        local short = author and (author:match("^([^-]+)") or author)
        local cached = short and ChatTweaks._cache[short]
        if not cached then return false end
        local info = {
            classFile = cached.classFile,
            level     = cached.level,
            altTag    = (BRutus.GetAltTag and cached.fullKey) and BRutus:GetAltTag(cached.fullKey) or nil,
        }
        local prefix = ChatTweaks:_BuildPrefix(info, cfg)
        if prefix == "" then return false end
        return false, prefix .. " " .. msg, author, ...
    end
end

function ChatTweaks:_RegisterFilters()
    if BRutus.db.chatTweaks.guild ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", self:_MakeFilter())
    end
    if BRutus.db.chatTweaks.officer ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", self:_MakeFilter())
    end
end
```

_(Note: filters are registered once at Initialize and always installed; the per-line `cfg.enabled` check makes the toggle live without re-registering. `guild`/`officer` are install-time channel choices — a reload applies changes to those two, acceptable.)_

- [ ] **Step 2: Self-tests (pure prefix builder)**

```lua
function ChatTweaks:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local cfg = { classIcon = true, level = true, altTag = true }
    S:Register("chattweaks.level", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, cfg)
        if not p:find("[70]", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.alttag", function()
        local p = ChatTweaks:_BuildPrefix({ altTag = "alt of Main" }, cfg)
        if not p:find("alt of Main", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.off", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, { level = false })
        if p ~= "" then return false, "toggles off => empty" end
        return true
    end)
    S:Register("chattweaks.nil_info", function()
        if ChatTweaks:_BuildPrefix(nil, cfg) ~= "" then return false end
        return true
    end)
end
```

- [ ] **Step 3: Register (.toc + InitModules + luacheckrc)**

`GuildOS.toc`: add `Modules\ChatTweaks.lua`. `Core/Core.lua InitModules()`:
```lua
    if BRutus.ChatTweaks then
        BRutus.ChatTweaks:Initialize()
    end
```
`.luacheckrc`: under a `-- Chat` comment, add `"CLASS_ICON_TCOORDS"`, `"ChatFrame_AddMessageEventFilter"` if luacheck flags them.

- [ ] **Step 4: Lint + commit**

luacheck 0/0. (Agent: hand-trace the 4 self-tests. Runtime `/gos selftest` → 26 total, human checkpoint. Flag that the chat filter itself needs in-game verification: enable it, watch a guild line get the class icon + [level] + (alt tag) prefix, and confirm click-to-whisper on the name still works — it should, since author is untouched.)

```bash
git add Modules/ChatTweaks.lua GuildOS.toc Core/Core.lua .luacheckrc
git commit -m "feat: ChatTweaks — guild/officer chat class-icon/level/alt-tag prefix (off by default)"
```

---

## Task 2: Settings toggles ("CHAT" block)

**Files:** Modify `UI/FeaturePanels.lua`, `Locales/*.lua`.

**Interfaces:** Consumes `db.chatTweaks`; `UI:CreateCheckbox`, `UI:CreateHeaderText`, `UI:CreateText`, `BRutus.Colors`.

- [ ] **Step 1: Add the block**

In `UI/FeaturePanels.lua`, in the General settings category (the member-visible options area — this is a personal display toggle, not officer-only), following the section idiom you find (read a neighbouring checkbox group for anchoring/spacing), add a "CHAT" block:
- Header `L["CHAT"]`.
- Master checkbox `L["Annotate guild chat (class icon, level, alt tag)"]` ↔ `db.chatTweaks.enabled`.
- A dim hint `L["Adds a class icon, level and alt tag before guild/officer messages. Toggle parts with /gos … or here."]` — keep concise; if adding per-part checkboxes (classIcon/level/altTag) fits the section cleanly, add them (each ↔ its `db.chatTweaks` key); otherwise the master toggle + hint is enough for v1 (note it).

Guard `BRutus.db.chatTweaks` (created in Initialize) with `and` before read/write.

- [ ] **Step 2: Locale + lint + commit**

Add the used keys in all 5 files (enUS master; translate rest).

luacheck 0/0. In-game (human): the CHAT toggle enables/disables the annotations.

```bash
git add UI/FeaturePanels.lua Locales/
git commit -m "feat: CHAT settings block for chat annotations"
```

---

## Self-Review
- Spec §Feature-2 (class icon + level + alt tag on guild/officer chat, toggles, cache not per-message) → Tasks 1-2. ✓
- **Deviations (documented):** race icon dropped (no reliable BCC race from roster); annotations as message-prefix not on-name (safe; on-name is a follow-up needing in-game iteration); default OFF.
- Reuses T2#1 `GetAltTag`. No new sync. Cache refreshed on roster update only.
- Types: `_BuildPrefix(info={classFile,level,altTag}, cfg)`, `_ClassIcon(classFile)`, cache `short->{classFile,level,fullKey}` consistent.
- Human-verify: `/gos selftest` (26); enable CHAT → class icon/[level]/(alt tag) prefix on guild lines; click-to-whisper still works (author untouched).
