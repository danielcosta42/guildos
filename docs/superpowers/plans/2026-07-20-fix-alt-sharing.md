# Fix — Alt visibility for members + member self-managed alts (incl. cross-account)

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development.
> Branch `fix/alt-sharing`, cut from `main` so it can ship without waiting for Tier 3.

**Goal:** Two user-reported problems on the published addon:
1. **Members can't see anybody's alts** — only officers store the synced `altLinks` table.
2. **Alts on different WoW accounts can't be linked** — auto-detect is same-account-only, and manual `LinkAlt` is officer-only, so a member can't link their own alts at all.

**Architecture:**
- **Fix A:** `CommSystem`'s `ALT_LINK` handler currently gates on the *receiver* being an officer, so members never store the table. Gate on the **sender** instead (`IsOfficerByName(sender)`) — still officer-authoritative, but every member receives and can see alts (unlocks True Roster, chat alt-tags, and the inspector's "alt of X" for everyone).
- **Fix B:** Reuse the **existing** "LINKED CHARACTERS" UI in `UI/MemberDetail.lua` (input + `Link alt` + `Unlink`). Show it to a **member when they're viewing their own current character**, and route their add/remove through the existing **self-claim** path (`AltAutoDetect:LinkOwnAlts` / a new `UnlinkOwnAlt` → `SELF_ALT` → officers apply + sync). Cross-account works because the alt is typed by name, not detected. Officers keep today's behavior unchanged.

**Tech Stack:** Lua 5.1 (BCC 20506), luacheck, `/gos selftest`.

## Global Constraints
- luacheck **0/0** (`C:\Users\danie\bin\luacheck.exe . --config .luacheckrc`).
- Officer-authoritative model preserved: only officer-sent `ALT_LINK` tables are trusted; a member may only claim about their OWN alts (self-claim), never overwrite the table.
- **No new UI** — reuse the existing inspector section (the user explicitly asked for "a mesma interface visual"). Only a gate change + hint text.
- Strings in 5 locales. Commits Conventional; **no AI attribution**.

## File Structure
| File | Action | Responsibility |
|---|---|---|
| `Modules/CommSystem.lua` | Modify | ALT_LINK: trust by sender, store on every client. |
| `Modules/AltAutoDetect.lua` | Modify | `UnlinkOwnAlt`; `HandleSelfClaim` handles unlinks. |
| `UI/MemberDetail.lua` | Modify | Show LINKED CHARACTERS to a member on their own char; route through self-claim. |
| `Locales/*.lua` (×5) | Modify | Member hint string. |

---

## Task 1: Fix A — every member receives and stores alt links

**Files:** Modify `Modules/CommSystem.lua`.

- [ ] **Step 1: Trust by sender, store everywhere**

Find the ALT_LINK branch (~line 253):
```lua
    elseif msgType == CommSystem.MSG_TYPES.ALT_LINK then
        if BRutus:IsOfficer() then
            local ok, links = LibSerialize:Deserialize(data)
            if ok and type(links) == "table" then
                BRutus.db.altLinks = links
            end
        end
```
Replace the gate so EVERY client stores an officer-authored table:
```lua
    elseif msgType == CommSystem.MSG_TYPES.ALT_LINK then
        -- Officer-authored, everyone stores: members need altLinks to see
        -- alt/main grouping (True Roster, chat tags, inspector).
        if BRutus:IsOfficerByName(sender) then
            local ok, links = LibSerialize:Deserialize(data)
            if ok and type(links) == "table" then
                BRutus.db.altLinks = links
            end
        end
```
Also update the `MSG_TYPES` comment (~line 20) from `-- Alt/main link table sync (officer only)` to `-- Alt/main link table sync (officer-authored; all members store)`.

- [ ] **Step 2: Make sure members actually converge**

`BroadcastAltLinks` is called from `LinkAlt`/`UnlinkAlt` (mutation) and at `CommSystem.lua:~459`. **Read the ~459 call site** and confirm it sits in a path officers run periodically or on full sync (so a member who logs in later gets the table within a sync cycle). If it is NOT in such a path, add `if BRutus:IsOfficer() then self:BroadcastAltLinks() end` to the officer's existing periodic/full-sync routine (do not invent a new ticker). Report which you found/did.

- [ ] **Step 3: Lint + commit**

luacheck 0/0. (Agent: static-trace — a member receiving an officer-sent ALT_LINK now stores it; a NON-officer sender's table is ignored on every client.)

```bash
git add Modules/CommSystem.lua
git commit -m "fix: all guild members receive alt links (trust by sender, not receiver)"
```

---

## Task 2: Fix B — members manage their own alts in the existing inspector UI

**Files:** Modify `UI/MemberDetail.lua`, `Modules/AltAutoDetect.lua`, `Locales/*.lua`.

**Interfaces:**
- Consumes: `AltAutoDetect:LinkOwnAlts(mainKey, altKeys)` (officer → LinkAlt; member → local + `SELF_ALT`); `BRutus:LinkAlt/UnlinkAlt`; `BRutus:GetPlayerKey`.
- Produces: `AltAutoDetect:UnlinkOwnAlt(altKey)`; `HandleSelfClaim` handling `claim.unlink`.

- [ ] **Step 1: Self-claim unlink support (`Modules/AltAutoDetect.lua`)**

Add:
```lua
-- Member-safe unlink of one's OWN alt: officers apply directly, members
-- broadcast a self-claim that officers replay.
function AltAutoDetect:UnlinkOwnAlt(altKey)
    if not altKey then return end
    if BRutus:IsOfficer() then
        BRutus:UnlinkAlt(altKey)
    else
        BRutus.db.altLinks = BRutus.db.altLinks or {}
        BRutus.db.altLinks[altKey] = nil
        if BRutus.CommSystem then
            local payload = LibSerialize:Serialize({ unlink = { altKey } })
            BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.SELF_ALT, payload)
        end
    end
end
```
And extend `HandleSelfClaim` (after the existing link loop) to honour unlinks:
```lua
    if type(claim.unlink) == "table" then
        for _, k in ipairs(claim.unlink) do BRutus:UnlinkAlt(k) end
    end
```
Make sure `HandleSelfClaim` still validates shape and stays officer-gated, and that a claim carrying ONLY `unlink` (no `main`/`alts`) isn't rejected by the existing `claim.main` guard — restructure the validation so link and unlink are handled independently (e.g. validate `type(claim) == "table"`, then handle `claim.main`+`claim.alts` if present, then `claim.unlink` if present).

- [ ] **Step 2: Open the existing section to members on their own character (`UI/MemberDetail.lua`)**

The section starts (~line 787) with:
```lua
    if BRutus:IsOfficer() then
```
Change it so a member sees the SAME section when viewing their own current character:
```lua
    local myKey = BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
    local isSelfManage = (playerKey == myKey)
    if BRutus:IsOfficer() or isSelfManage then
```
(Compute `myKey`/`isSelfManage` just above the `if`.)

- [ ] **Step 3: Route member actions through the self-claim**

- In `doLink` (~line 863), replace the `BRutus:LinkAlt(altKey, playerKey)` call so members use the self-claim:
```lua
            local applied
            if BRutus:IsOfficer() then
                applied = BRutus:LinkAlt(altKey, playerKey)
            else
                BRutus.AltAutoDetect:LinkOwnAlts(playerKey, { altKey })
                applied = true
            end
            if applied then
```
(keep the existing success body — the refresh/clear — under `if applied then`).
- In the **Unlink** button handler (~line 823), replace the two `BRutus:UnlinkAlt(...)` calls with a helper that routes by permission:
```lua
                    local function doUnlink(k)
                        if BRutus:IsOfficer() then BRutus:UnlinkAlt(k)
                        else BRutus.AltAutoDetect:UnlinkOwnAlt(k) end
                    end
                    if lkIsMain then doUnlink(playerKey) else doUnlink(capturedKey) end
```
- Update the section hint (~line 803) so a member understands the flow: when `not BRutus:IsOfficer()`, set the label to `L["Add your own alts (any account). An officer's client applies them guild-wide."]`; officers keep `L["Linked chars share attunements account-wide."]`.

- [ ] **Step 4: Locale + lint + commit**

Add `L["Add your own alts (any account). An officer's client applies them guild-wide."]` to all 5 files (grep first; only add where missing).

luacheck 0/0. In-game (human): as a **member**, open your own character in the roster → LINKED CHARACTERS section is visible → type an alt's name (even on another account) → Link alt → an online officer applies it → everyone sees the grouping. As an **officer**, behavior is unchanged.

```bash
git add UI/MemberDetail.lua Modules/AltAutoDetect.lua Locales/
git commit -m "feat: members can manage their own alts from the inspector (self-claim)"
```

---

## Self-Review
- Problem 1 (cross-account) → Task 2: manual, name-typed linking available to members; works across accounts since nothing is auto-detected. ✓
- Problem 2 (members can't see alts) → Task 1: trust-by-sender so every client stores the officer-authored table. ✓
- Security preserved: only officer-authored tables are trusted; members can only self-claim their own links/unlinks (officers replay). ✓
- **No new UI** — same inspector section, gate + hint only (per the user's "mesma interface visual"). ✓
- Human-verify: member sees alts after an officer syncs; member links a cross-account alt from their own char; officer flow unchanged.
