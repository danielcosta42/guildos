----------------------------------------------------------------------
-- Guild OS - Alt Auto-Detect
-- Detects the player's own same-account characters via the account-wide
-- SavedVariables (GuildOSDB is shared across all chars on the game account)
-- and offers a one-click link. Own alts only; others' alts are never
-- auto-detectable (no API reveals another player's account).
-- One question for every undecided character of the account, its answers
-- kept per pair of characters for the whole account, a day between two
-- asks and three at most (#449, specs/salao/alts.md).
----------------------------------------------------------------------
local AltAutoDetect = {}
GuildOS.AltAutoDetect = AltAutoDetect

local L = GuildOS.L
local LibSerialize = LibStub("GuildOS-LibSerialize")

-- Stable signature for a detected group, used to dedupe the "declined"
-- marker: same set of keys => same signature regardless of order.
local function GroupSignature(group)
    local sorted = {}
    for i, key in ipairs(group) do sorted[i] = key end
    table.sort(sorted)
    return table.concat(sorted, "|")
end

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
    local name = GuildOS.Compat.PlayerName()
    if not name then return end
    -- The realm GuildOS:RealmName() reads back when the client answers none (issue #394).
    local realm = GuildOS:RealmName()
    local key = GuildOS:GetPlayerKey(name, realm)
    local _, classFile = UnitClass("player")
    -- The GUID outlives a rename (#449): the same one under another key is this character's old name, whose links
    -- and answers move to the new one once the roster is there (CheckRename).
    local guid = UnitGUID and UnitGUID("player") or nil
    if type(guid) == "string" and guid ~= "" then
        for k, info in pairs(GuildOSDB.accountChars) do
            if k ~= key and type(info) == "table" and info.guid == guid then
                GuildOSDB.accountChars[k] = nil
                GuildOSDB.altRenamed = { from = k, to = key, ts = GetServerTime() }
            end
        end
    else
        guid = nil
    end
    GuildOSDB.accountChars[key] = {
        name = name, realm = realm, class = classFile,
        level = UnitLevel("player"), guild = GetGuildInfo("player"),
        ts = GetServerTime(), guid = guid,
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
            set[GuildOS:GetPlayerKey(short, realm)] = true
        end
    end
    return set
end

-- Pure: the links that make `main` the one main of `group`: every other member points at it,
-- it points at nobody, and a character still pointing at a member that stops being a main
-- follows to the new one (no alt of an alt). Returns a new table and how many entries changed.
function AltAutoDetect:PlanGroup(altLinks, group, main)
    local out = {}
    for k, v in pairs(altLinks or {}) do out[k] = v end
    local inGroup = {}
    for _, k in ipairs(group or {}) do inGroup[k] = true end
    for k, v in pairs(out) do
        if inGroup[v] and v ~= main and not inGroup[k] then out[k] = main end
    end
    for k in pairs(inGroup) do
        if k == main then out[k] = nil else out[k] = main end
    end
    local changed = 0
    local seen = {}
    for k, v in pairs(out) do
        seen[k] = true
        if (altLinks or {})[k] ~= v then changed = changed + 1 end
    end
    for k in pairs(altLinks or {}) do
        if not seen[k] then changed = changed + 1 end
    end
    return out, changed
end

-- Pure: from the account chars that are ALSO current guild members, if 2+
-- exist and they do not already share one main (whichever of them it is),
-- return the group and the suggested main. Else nil. The suggestion keeps the
-- main the group already has; with none it is the highest level, and a tie
-- goes to the name, so the same group always gets the same answer (#353).
function AltAutoDetect:DetectOwnAlts(accountChars, guildSet, altLinks)
    altLinks = altLinks or {}
    local group = {}
    for key, info in pairs(accountChars or {}) do
        local lk = GuildOS:LocalMemberKey(key)   -- recorded on another realm's client (#97)
        if guildSet[lk] then group[#group + 1] = { key = lk, level = info.level or 0 } end
    end
    if #group < 2 then return nil end
    table.sort(group, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.key < b.key
    end)
    local roots, nRoots = {}, 0
    for _, g in ipairs(group) do
        local root = altLinks[g.key] or g.key
        if not roots[root] then roots[root] = 0; nRoots = nRoots + 1 end
        roots[root] = roots[root] + 1
    end
    if nRoots == 1 then return nil end            -- already one person, whoever is the main
    local main
    for _, g in ipairs(group) do                 -- the main the group already has, if any
        local c = roots[g.key]
        if c and c >= 2 and altLinks[g.key] == nil and (not main or c > roots[main]) then main = g.key end
    end
    main = main or group[1].key
    local keys = {}
    for _, g in ipairs(group) do keys[#keys + 1] = g.key end
    return { group = keys, main = main }
end

-- Returns how many links changed. An officer writes and publishes them (AltSync, #424); a member
-- applies them to their own view, asks the officers and keeps the claim until an officer's links
-- carry it or a newer officer edit overrules it (#353, #424).
function AltAutoDetect:LinkOwnAlts(mainKey, altKeys)
    if not mainKey or not altKeys then return 0 end
    local links, changed = self:PlanGroup(GuildOS.db.altLinks, altKeys, mainKey)
    if GuildOS:IsOfficer() then
        if GuildOS.AltSync then
            -- The officer named these alts: a link of theirs from before #424 becomes an officer's.
            local confirm = {}
            for _, k in ipairs(altKeys) do if k ~= mainKey then confirm[k] = true end end
            GuildOS.AltSync:Commit(links, confirm)
        elseif changed > 0 then
            GuildOS.db.altLinks = links
        end
        return changed
    end
    GuildOS.db.altLinks = links
    local alts = {}
    for _, k in ipairs(altKeys) do
        if k ~= mainKey then alts[#alts + 1] = k end
    end
    self:_KeepPending(mainKey, alts)
    self:_SendClaim(mainKey, alts)
    return changed
end

function AltAutoDetect:_SendClaim(mainKey, alts)
    if not GuildOS.CommSystem then return end
    local payload = LibSerialize:Serialize({ main = mainKey, alts = alts })
    GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
end

function AltAutoDetect:_SendUnlink(key)
    if not GuildOS.CommSystem then return end
    local payload = LibSerialize:Serialize({ unlink = { key } })
    GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
end

-- A claim, as it goes to the officers: a group's link, or a member's own unlink.
function AltAutoDetect:_Send(p)
    if p.unlink then self:_SendUnlink(p.unlink) else self:_SendClaim(p.main, p.alts) end
end

local PENDING_TTL = 30 * 86400
local function unlinkSig(key) return "unlink:" .. key end

-- Account-wide like accountChars, tagged with the guild: the keys only mean something there. A claim for
-- the group replaces a member's own unlink of any of its characters still waiting.
function AltAutoDetect:_KeepPending(mainKey, alts)
    if not GuildOSDB then return end
    GuildOSDB.altPending = GuildOSDB.altPending or {}
    local group = { mainKey }
    for _, k in ipairs(alts) do group[#group + 1] = k end
    for _, k in ipairs(group) do GuildOSDB.altPending[unlinkSig(k)] = nil end
    GuildOSDB.altPending[GroupSignature(group)] = {
        main = mainKey, alts = alts, guild = GetGuildInfo("player"), ts = GetServerTime(),
    }
end

-- A member's own unlink waits like a claim (#424): on the member's view (Overlay) until an officer's
-- tombstone for it, or a newer officer link of that character, answers it.
function AltAutoDetect:_KeepUnlink(key)
    if not GuildOSDB then return end
    GuildOSDB.altPending = GuildOSDB.altPending or {}
    GuildOSDB.altPending[unlinkSig(key)] = { unlink = key, guild = GetGuildInfo("player"), ts = GetServerTime() }
end

-- Each pending claim of this guild, after dropping the ones past their time.
function AltAutoDetect:_EachPending(fn)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local guild, now = GetGuildInfo("player"), GetServerTime()
    for sig, p in pairs(pending) do
        local valid = type(p) == "table"
            and ((p.main and type(p.alts) == "table") or (type(p.unlink) == "string" and p.unlink ~= ""))
        if not valid or now - (p.ts or 0) > PENDING_TTL then
            pending[sig] = nil
        elseif p.guild == guild then
            fn(sig, p)
        end
    end
end

local function carries(links, p)
    if links[p.main] ~= nil then return false end
    for _, k in ipairs(p.alts) do
        if links[k] ~= p.main then return false end
    end
    return true
end

-- Pure: whether an officer's edit newer than claim `p` overrules it: one of its alts unlinked or
-- linked to another main, or its main made somebody's alt, after the claim was made. Only an
-- officer's own entry counts (one with an author, not a link taken from an old client's table):
-- a link merely missing from an officer's list, or an older edit, is no answer (#424).
function AltAutoDetect.Overruled(p, entries)
    local since = p.ts or 0
    local function newer(e)
        return type(e) == "table" and e.author ~= nil and not e.legacy and (e.ts or 0) > since
    end
    for _, k in ipairs(p.alts) do
        local e = entries[k]
        if newer(e) and (e.removed or e.main ~= p.main) then return true end
    end
    local e = entries[p.main]
    return newer(e) and not e.removed and e.main ~= nil
end

-- Pure: whether a member's own unlink `p` is answered: the officers' entries hold no link for that
-- character (a tombstone, or none at all), or an officer linked it again after the unlink was asked.
-- A link this client only has from before #424, or an officer's older one, is no answer (#424).
function AltAutoDetect.UnlinkAnswered(p, entries)
    local e = entries[p.unlink]
    if type(e) ~= "table" or e.removed then return true end
    return e.author ~= nil and not e.legacy and (e.ts or 0) > (p.ts or 0)
end

-- An officer's word on the links just arrived (AltSync). A claim the officers' links carry is
-- done, one a newer officer edit overrules goes; any other stays on our view (Overlay) and goes
-- to the officers again, once a session each (an officer is online now).
function AltAutoDetect:OnOfficerLinks()
    if GuildOS:IsOfficer() or not GuildOS.AltSync then return end
    self._resentAt = self._resentAt or {}
    local base, entries = GuildOS.AltSync:HeardView(), GuildOS.AltSync:Entries()
    self:_EachPending(function(sig, p)
        local done
        if p.unlink then
            done = AltAutoDetect.UnlinkAnswered(p, entries)
        else
            done = carries(base, p) or AltAutoDetect.Overruled(p, entries)
        end
        if done then
            GuildOSDB.altPending[sig] = nil
        elseif not self._resentAt[sig] then
            self._resentAt[sig] = GetTime()
            self:_Send(p)
        end
    end)
end

-- The member's own claims still waiting, on top of the officers' links, oldest first: what a
-- member's view shows until an officer applies them. An officer's view is the officers' links.
function AltAutoDetect:Overlay(links)
    if GuildOS:IsOfficer() then return links end
    local list = {}
    self:_EachPending(function(_, p) list[#list + 1] = p end)
    table.sort(list, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) < (b.ts or 0) end
        return (a.main or ("\0" .. a.unlink)) < (b.main or ("\0" .. b.unlink))
    end)
    for _, p in ipairs(list) do
        if p.unlink then
            local out = {}
            for k, v in pairs(links) do out[k] = v end
            out[p.unlink] = nil
            links = out
        else
            local group = { p.main }
            for _, k in ipairs(p.alts) do group[#group + 1] = k end
            links = self:PlanGroup(links, group, p.main)
        end
    end
    return links
end

-- At login: an officer now on this account applies its own claims; a member sends them again.
function AltAutoDetect:ResendPending()
    self:_EachPending(function(sig, p)
        if GuildOS:IsOfficer() then
            if p.unlink then
                GuildOS:UnlinkAlt(p.unlink)
            else
                local group = { p.main }
                for _, k in ipairs(p.alts) do group[#group + 1] = k end
                self:LinkOwnAlts(p.main, group)
            end
            GuildOSDB.altPending[sig] = nil
        else
            -- Not marked as re-sent: nobody may be online to hear it, so the first officer
            -- word on the links this session sends it again.
            self:_Send(p)
        end
    end)
end

-- A member's own unlink takes that character out of any claim still waiting; a claim left with no
-- alt, or about the character as its main, goes.
function AltAutoDetect:_UnclaimPending(key)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local rewrite = {}   -- kept after the walk: a new key added during pairs() is undefined in Lua
    for sig, p in pairs(pending) do
        if type(p) ~= "table" or p.main == key or type(p.alts) ~= "table" then
            if type(p) ~= "table" or p.main == key then pending[sig] = nil end
        else
            local alts = {}
            for _, k in ipairs(p.alts) do if k ~= key then alts[#alts + 1] = k end end
            if #alts < #p.alts then
                pending[sig] = nil
                if #alts > 0 then rewrite[#rewrite + 1] = { main = p.main, alts = alts, guild = p.guild, ts = p.ts } end
            end
        end
    end
    -- Same guild and age as the claim it came from: an unlink here neither moves another guild's
    -- claim into this one nor restarts its thirty days.
    for _, r in ipairs(rewrite) do
        local group = { r.main }
        for _, k in ipairs(r.alts) do group[#group + 1] = k end
        pending[GroupSignature(group)] = r
    end
end

-- A member's re-main replaces any claim waiting about the group's characters with the new one.
function AltAutoDetect:_DropPendingWith(keys)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local hit = {}
    for _, k in ipairs(keys) do hit[k] = true end
    for sig, p in pairs(pending) do
        local touches = type(p) ~= "table" or hit[p.main] or hit[p.unlink]
        if not touches and type(p.alts) == "table" then
            for _, k in ipairs(p.alts) do if hit[k] then touches = true; break end end
        end
        if touches then pending[sig] = nil end
    end
end

-- Member-safe "set which of my chars is the main". Officers apply directly
-- via the authoritative SetMain; members re-point their OWN group LOCALLY (so
-- their view updates immediately) and broadcast a SELF_ALT self-claim
-- { main = newMainKey, alts = <every other current group member> } that
-- officers replay. Security: the broadcast rides the comm envelope, and
-- HandleSelfClaim only applies a claim whose sender is part of the named
-- group, so a member can only ever re-main a group they belong to.
function AltAutoDetect:SetOwnMain(newMainKey)
    if not newMainKey then return end
    if GuildOS:IsOfficer() then
        GuildOS:SetMain(newMainKey)
        return
    end
    local links = GuildOS.db.altLinks or {}
    local group = GuildOS:GetLinkedChars(newMainKey)
    if #group < 2 then return end               -- nothing to re-main
    if links[newMainKey] == nil then return end -- already the main, no-op
    self:_DropPendingWith(group)
    GuildOS.db.altLinks = GuildOS:_RepointGroup(links, group, newMainKey)
    if GuildOS.CommSystem then
        local alts = {}
        for _, k in ipairs(group) do
            if k ~= newMainKey then alts[#alts + 1] = k end
        end
        local payload = LibSerialize:Serialize({ main = newMainKey, alts = alts })
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
        self:_KeepPending(newMainKey, alts)   -- kept like an accepted prompt, until an officer's list has it
    end
end

-- Member-safe unlink of one's OWN alt: officers apply directly, members
-- broadcast a self-claim that officers replay. The member's unlink waits like a link claim (#424):
-- the view is rebuilt from the officers' entries, so a plain local edit would come back on the next
-- rebuild; the waiting unlink keeps it off the member's view until an officer answers it.
function AltAutoDetect:UnlinkOwnAlt(altKey)
    if not altKey then return end
    if GuildOS:IsOfficer() then
        GuildOS:UnlinkAlt(altKey)
    else
        GuildOS.db.altLinks = GuildOS.db.altLinks or {}
        self:_UnclaimPending(altKey)
        self:_KeepUnlink(altKey)
        if GuildOS.AltSync then GuildOS.AltSync:Rebuild() else GuildOS.db.altLinks[altKey] = nil end
        self:_SendUnlink(altKey)
    end
end

-- Officer applies a member's self-claim with LinkAlt's and UnlinkAlt's rules,
-- in one write of the officers' synced links (#424). Link and unlink are validated and handled independently so
-- an unlink-only claim (no main/alts) isn't rejected by the link guard.
-- Security: a claim is only ever trusted for the KEYS IT NAMES about the
-- SENDER themselves — the sender's own player key is derived from the comm
-- envelope (never taken from the claim body), so a member cannot forge a
-- claim that links/unlinks someone else's characters.
function AltAutoDetect:HandleSelfClaim(sender, data)
    if not GuildOS:IsOfficer() then return end       -- only officers apply/propagate
    local ok, claim = LibSerialize:Deserialize(data)
    if not ok or type(claim) ~= "table" then return end

    if type(sender) ~= "string" or sender == "" then return end
    -- The roster's key of the sender: on WoW: Forever "Chehul-Costa" is "Chehul Costa" (audit N2).
    local senderKey = GuildOS:SenderKey(sender)
    if not senderKey then return end
    -- The claim's keys were built on the sender's client: as this client keys them (#97).
    if claim.main then claim.main = GuildOS:LocalMemberKey(claim.main) end
    if type(claim.alts) == "table" then
        for i, k in ipairs(claim.alts) do claim.alts[i] = GuildOS:LocalMemberKey(k) end
    end
    if type(claim.unlink) == "table" then
        for i, k in ipairs(claim.unlink) do claim.unlink[i] = GuildOS:LocalMemberKey(k) end
    end

    local links, confirm = {}, {}
    for k, v in pairs(GuildOS.db.altLinks or {}) do links[k] = v end
    if claim.main and type(claim.alts) == "table" then
        -- Only apply if the sender is part of the group they're claiming
        -- (either the main or one of the alts) — never someone else's.
        local involvesSender = (claim.main == senderKey)
        if not involvesSender then
            for _, k in ipairs(claim.alts) do
                if k == senderKey then involvesSender = true; break end
            end
        end
        if involvesSender then
            -- The claim asserts claim.main is THE main. If it is currently an
            -- alt of someone else, clear its own entry BEFORE the LinkAlt loop
            -- so LinkAlt's circular guard (mainKey must not itself be an alt)
            -- does not reject promoting an existing alt to main.
            --
            -- BUT clear ONLY when claim.main is already in the SENDER's own
            -- group. Otherwise a claim {main=X, alts={self}} with an unrelated X
            -- would detach X from its real group. When not same-group we skip
            -- the clear, and LinkAlt's circular guard still blocks linking to an
            -- existing alt, so a member can only re-main a group they belong to.
            local senderGroup = GuildOS:GetLinkedChars(senderKey)
            for _, k in ipairs(senderGroup) do
                if k == claim.main then links[claim.main] = nil; break end
            end
            for _, k in ipairs(claim.alts) do
                if k ~= claim.main then
                    local planned = GuildOS:_PlanLink(links, k, claim.main)
                    if planned then links, confirm[k] = planned, true end
                end
            end
        end
    end
    if type(claim.unlink) == "table" then
        -- Only unlink a key the sender owns: themselves, an alt whose main is the sender, or (#449) another
        -- alt of the sender's own main: a member logged on an alt unlinking a sibling was refused here, and the
        -- unlink waited and went again every session for thirty days.
        local senderMain = GuildOS.db.altLinks and GuildOS.db.altLinks[senderKey]
        for _, k in ipairs(claim.unlink) do
            if k == senderKey or links[k] == senderKey or (senderMain and links[k] == senderMain) then links[k] = nil end
        end
    end
    -- One write for the whole claim, through the officers' synced links (#424).
    -- The member named these alts: a link of theirs from before #424 becomes an officer's.
    if GuildOS.AltSync then GuildOS.AltSync:Commit(links, confirm) else GuildOS.db.altLinks = links end
end

----------------------------------------------------------------------
-- The login prompt (#449): ONE question for every character of the account not decided yet,
--   "These characters are on your account: A, B, C. Link them as alts of [main]?"
--   Link all / Choose... / Not now / Don't ask again
-- instead of one per group that came back on every login, reload and character.
--
-- What it remembers is the account's (GuildOSDB.altAsk, the root every character reads; a /gos reset,
-- a guild left and joined again or a new guild db keeps it), per PAIR of characters:
--   * `d`: decided for good. "link" (linked from the prompt), "no" (Don't ask again, or left unticked
--     under Choose...), "linked" (seen in one group: an officer's later unlink is the officers' word and
--     does not bring the question back), "gone" (asked MAX_ASKS times without an answer);
--   * `n`, `at`: how many times it was SHOWN and when. Shown counts, not answered: a /reload, an Escape
--     or the close with the window up is a "Not now" too. A pair comes back at most once a SNOOZE
--     (a day) and never after MAX_ASKS (three) times.
-- A character is listed while it has a pair still open with another character of the account in the
-- guild; one that was answered for good about any of them (or is already in a group) is left out when
-- a character nobody was asked about is there: a new alt is asked about alone. The main's change, a
-- rename, an officer's sync or a second client never reopen a pair that was decided.
-- At most once a session, never in combat, after the login's popups (GuildOS:ShowWhenClear), and the
-- question is worked out again when it gets its turn: what changed while it waited is not asked.
----------------------------------------------------------------------
AltAutoDetect.SNOOZE = 86400
AltAutoDetect.MAX_ASKS = 3
AltAutoDetect.PROMPT_DELAY = 20   -- seconds after login: past the roster's settle and the login popups' burst

local function pairKey(a, b)
    if a < b then return a .. "|" .. b end
    return b .. "|" .. a
end
AltAutoDetect.PairKey = pairKey

local function mergeAsk(a, b)
    if type(a) ~= "table" then return b end
    if type(b) ~= "table" then return a end
    return { d = a.d or b.d, n = math.max(a.n or 0, b.n or 0), at = math.max(a.at or 0, b.at or 0) }
end

-- The account's answers, keyed this client's way (WoW: Forever rewrites a realm, #97), with the groups an
-- older version's "Don't ask again" kept (GuildOSDB.altDeclined) as declined pairs. Once per table.
function AltAutoDetect:_Asks()
    if type(GuildOSDB) ~= "table" then return {} end
    local a = GuildOSDB.altAsk
    if type(a) ~= "table" or type(a.pairs) ~= "table" then
        a = { v = 1, pairs = {} }
        GuildOSDB.altAsk = a
    end
    if self._asksTable == a then return a.pairs end
    local out = {}
    for pk, p in pairs(a.pairs) do
        local x, y
        if type(pk) == "string" then x, y = pk:match("^(.-)|(.+)$") end
        if x and type(p) == "table" then
            x, y = GuildOS:LocalMemberKey(x), GuildOS:LocalMemberKey(y)
            if x ~= "" and y ~= "" and x ~= y then out[pairKey(x, y)] = mergeAsk(out[pairKey(x, y)], p) end
        end
    end
    if type(GuildOSDB.altDeclined) == "table" then
        for sig in pairs(GuildOSDB.altDeclined) do
            local keys = {}
            for k in tostring(sig):gmatch("[^|]+") do keys[#keys + 1] = GuildOS:LocalMemberKey(k) end
            for i = 1, #keys do
                for j = i + 1, #keys do
                    if keys[i] ~= keys[j] then
                        local k = pairKey(keys[i], keys[j])
                        out[k] = out[k] or {}
                        out[k].d = out[k].d or "no"
                    end
                end
            end
        end
        GuildOSDB.altDeclined = nil
    end
    a.pairs, a.v = out, 1
    self._asksTable = a
    return out
end

-- Pure: the characters of `accountChars` in the guild (`guildSet`), highest level first, then by key.
local function inGuild(accountChars, guildSet)
    local level, chars = {}, {}
    for key, info in pairs(accountChars or {}) do
        local lk = GuildOS:LocalMemberKey(key)   -- recorded on another realm's client (#97)
        if type(lk) == "string" and guildSet[lk] then
            local lv = type(info) == "table" and tonumber(info.level) or 0
            if level[lk] == nil then
                chars[#chars + 1] = lk
                level[lk] = lv
            elseif lv > level[lk] then
                level[lk] = lv
            end
        end
    end
    table.sort(chars, function(a, b)
        if level[a] ~= level[b] then return level[a] > level[b] end
        return a < b
    end)
    return chars
end
AltAutoDetect.InGuild = inGuild

--- Pure: what the prompt would ask now, or nil. `asks` is the account's pairs, `now` the server time; `manual`
--- (/gos myalts, Detect my alts) asks about every character not in one group, whatever was answered. Returns
--- { list = the characters to link (keys), choices = the mains to offer (keys), main = the one suggested,
---   chars = every character of the account in the guild }.
--- The main suggested is the group the account already has (the one with the most of its characters), else
--- the highest level, a tie to the key: the same characters always get the same answer (#353).
function AltAutoDetect.Plan(accountChars, guildSet, altLinks, asks, now, manual)
    altLinks, asks, now = altLinks or {}, asks or {}, now or 0
    local chars = inGuild(accountChars, guildSet or {})
    if #chars < 2 then return nil end
    local function root(k) return altLinks[k] or k end
    local function final(p) return type(p) == "table" and (p.d ~= nil or (p.n or 0) >= AltAutoDetect.MAX_ASKS) end
    local function open(a, b)
        if root(a) == root(b) then return false end
        if manual then return true end
        local p = asks[pairKey(a, b)]
        if type(p) ~= "table" then return true end
        if final(p) then return false end
        return now - (p.at or 0) >= AltAutoDetect.SNOOZE
    end
    local has, any = {}, false
    for i = 1, #chars do
        for j = i + 1, #chars do
            if open(chars[i], chars[j]) then has[chars[i]], has[chars[j]], any = true, true, true end
        end
    end
    if not any then return nil end
    -- Answered for good about some other character, or already in a group with one.
    local function settled(k)
        for _, o in ipairs(chars) do
            if o ~= k and (root(o) == root(k) or (not manual and final(asks[pairKey(k, o)]))) then return true end
        end
        return false
    end
    local list = {}
    for _, k in ipairs(chars) do
        if has[k] and not settled(k) then list[#list + 1] = k end
    end
    if #list == 0 then
        for _, k in ipairs(chars) do if has[k] then list[#list + 1] = k end end
    end
    -- The mains to offer: the account's characters and the mains they are linked to in the guild; never the
    -- one character asked about alone (it cannot be its own alt).
    local choices, seen, count = {}, {}, {}
    local function offer(k)
        if seen[k] or (#list == 1 and k == list[1]) then return end
        seen[k] = true
        choices[#choices + 1] = k
    end
    for _, k in ipairs(chars) do
        local r = root(k)
        count[r] = (count[r] or 0) + 1
        if r ~= k and guildSet[r] then offer(r) end
        offer(k)
    end
    local main
    for _, k in ipairs(choices) do
        if altLinks[k] == nil and (count[k] or 0) >= 2 and (not main or count[k] > count[main]) then main = k end
    end
    if not main then
        for _, k in ipairs(chars) do if seen[k] then main = k; break end end
    end
    if not main then return nil end
    local out = {}
    for _, k in ipairs(list) do
        if root(k) ~= root(main) then out[#out + 1] = k end
    end
    if #out == 0 then return nil end
    return { list = out, choices = choices, main = main, chars = chars }
end

-- Each pair of a listed character with another character of the account: fn(pairKey, listed, other).
local function eachPair(plan, fn)
    for _, k in ipairs(plan.list or {}) do
        for _, o in ipairs(plan.chars or {}) do
            if o ~= k then fn(pairKey(k, o), k, o) end
        end
    end
end

--- The prompt was shown: one more time for each of its pairs still open; after MAX_ASKS they are not asked again.
function AltAutoDetect:MarkShown(plan, now)
    local asks = self:_Asks()
    now = now or GetServerTime()
    local links = GuildOS.db and GuildOS.db.altLinks or {}
    eachPair(plan, function(pk, k, o)
        if (links[k] or k) == (links[o] or o) then return end
        local p = asks[pk] or {}
        asks[pk] = p
        if p.d then return end
        p.n, p.at = (p.n or 0) + 1, now
        if p.n >= self.MAX_ASKS then p.d = "gone" end
    end)
end

--- The prompt was answered for good: `how` "link" (the characters in `picked`, a set; every listed one when nil)
--- or "no". A listed character left unticked under Choose... is a "no".
function AltAutoDetect:Answer(plan, how, picked)
    local asks = self:_Asks()
    eachPair(plan, function(pk, k)
        local d = (how == "link" and (picked == nil or picked[k])) and "link" or "no"
        local p = asks[pk] or {}
        asks[pk] = p
        if p.d ~= "link" then p.d = d end
    end)
end

-- Every pair of the account's characters found in one group is decided: the officers linked them, or the player
-- did. An officer's unlink later is theirs to make; the prompt does not ask to undo it.
function AltAutoDetect:_NoteLinked(chars, links)
    local asks = self:_Asks()
    for i = 1, #chars do
        for j = i + 1, #chars do
            local a, b = chars[i], chars[j]
            if (links[a] or a) == (links[b] or b) then
                local pk = pairKey(a, b)
                asks[pk] = asks[pk] or {}
                asks[pk].d = asks[pk].d or "linked"
            end
        end
    end
end

-- The question as of now, or nil.
function AltAutoDetect:_Plan(manual)
    if type(GuildOSDB) ~= "table" then return nil end
    local guildSet = self:_GuildSet()
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    self:_NoteLinked(inGuild(GuildOSDB.accountChars, guildSet), links)
    return AltAutoDetect.Plan(GuildOSDB.accountChars, guildSet, links, self:_Asks(), GetServerTime(), manual)
end

--- Pure: the characters the prompt links under `main`: the listed ones, and the main it suggested when another one
--- is picked (the account is one player), never `main` itself.
function AltAutoDetect.Candidates(plan, main)
    local out, seen = {}, { [main or ""] = true }
    for _, k in ipairs(plan.list or {}) do
        if not seen[k] then seen[k] = true; out[#out + 1] = k end
    end
    local sug = plan.main
    if sug and not seen[sug] then
        local inChars = false
        for _, k in ipairs(plan.chars or {}) do if k == sug then inChars = true; break end end
        if inChars then out[#out + 1] = sug end
    end
    return out
end

--- "Link all" / "Link selected": the ticked characters (`picked`, a set; nil: all of Candidates) become alts of
--- `main`, with the group `main` already has and the groups they head. Returns how many links changed.
function AltAutoDetect:Accept(plan, main, picked)
    if type(plan) ~= "table" or not main then return 0 end
    self:Answer(plan, "link", picked)
    local group, inGroup = {}, {}
    local function add(k)
        if not inGroup[k] then inGroup[k] = true; group[#group + 1] = k end
    end
    add(main)
    for _, k in ipairs(GuildOS:GetLinkedChars(main)) do add(k) end
    local n = 0
    for _, k in ipairs(AltAutoDetect.Candidates(plan, main)) do
        if picked == nil or picked[k] then
            n = n + 1
            for _, g in ipairs(GuildOS:GetLinkedChars(k)) do add(g) end
        end
    end
    if n == 0 then return 0 end
    local changed = self:LinkOwnAlts(main, group)
    if changed > 0 then
        GuildOS:Print(string.format(L["Linked %d alt(s) to %s."], n, main:match("^([^-]+)") or main))
    end
    return changed
end

--- "Don't ask again": none of the listed characters is asked about again (with any of the account's).
function AltAutoDetect:Decline(plan)
    if type(plan) == "table" then self:Answer(plan, "no") end
end

-- Opens the window (UI/AltDepartureDialog.lua) and returns it, so the popup queue holds its slot (B21).
function AltAutoDetect:_Show(plan, manual)
    if GuildOS.ShowAltPrompt then return GuildOS:ShowAltPrompt(plan, manual) end
    return nil
end

--- At login, once a session: the question, if there is one, when the popup queue lets it (never in combat, after
--- the login's own popups). Counted as asked only when it is on screen.
function AltAutoDetect:OfferAtLogin()
    if self._prompted then return end
    if not self:_Plan(false) then return end
    self._prompted = true
    GuildOS:ShowWhenClear("altdetect", function()
        local plan = AltAutoDetect:_Plan(false)   -- the links may have changed while it waited
        if not plan then return nil end
        local f = AltAutoDetect:_Show(plan, false)
        if f then AltAutoDetect:MarkShown(plan) end
        return f
    end)
end

-- Called from Initialize: the claims go again once the roster is there; the question after the login's popups.
function AltAutoDetect:_SchedulePrompt()
    GuildOS.Compat.After(10, function()
        AltAutoDetect:ResendPending()
        AltAutoDetect:CheckRename()
    end)
    GuildOS.Compat.After(self.PROMPT_DELAY, function() AltAutoDetect:OfferAtLogin() end)
    -- An officer: a group whose main is not in the guild any more, asked about once (AltDeparture, #449).
    local AD = GuildOS.AltDeparture
    if AD and AD.CheckOrphans then
        GuildOS.Compat.After(AD.ORPHAN_DELAY, function() GuildOS:SafeCall(AD.CheckOrphans, AD) end)
    end
end

--- /gos myalts, Detect my alts: every character of the account not in one group, whatever was answered.
function AltAutoDetect:PromptNow()
    local plan = self:_Plan(true)
    if not plan then
        GuildOS:Print(L["No other characters of yours found in this guild."])
        return
    end
    GuildOS:ShowWhenClear("altdetect", function()
        local p = AltAutoDetect:_Plan(true)
        return p and AltAutoDetect:_Show(p, true) or nil
    end)
end

--- /gos myalts reset: forget every answer, so the login prompt may ask again.
function AltAutoDetect:ResetAnswers()
    if type(GuildOSDB) ~= "table" then return end
    GuildOSDB.altAsk, GuildOSDB.altDeclined, self._asksTable = nil, nil, nil
    GuildOS:Print(L["Your answers about your alts are forgotten: the login prompt may ask again."])
end

----------------------------------------------------------------------
-- The member sheet's Add alt (#449)
----------------------------------------------------------------------
--- Pure: the key of the guild member `typed` names in `names` ({ { name, key } }, the roster), or nil. Any case; on
--- WoW: Forever the chat's "Chehul-Costa" is the roster's "Chehul Costa" (audit N2). Two namesakes of connected
--- realms (retail): the one whose key is `realmOf`'s realm, else the first.
function AltAutoDetect.FindMember(names, typed, realmOf)
    typed = strtrim(typed or ""):lower()
    if typed == "" then return nil end
    local spaced = typed:gsub("%-", " ")
    local want = realmOf and realmOf:match("%-(.+)$")
    local found
    for _, n in ipairs(names or {}) do
        local nm = type(n.name) == "string" and n.name:lower()
        if nm and (nm == typed or nm == spaced or (type(n.key) == "string" and n.key:lower() == typed)) then
            if not found or (want and n.key:match("%-(.+)$") == want) then found = n.key end
        end
    end
    return found
end

--- `altKey` linked to the group `cardKey` is in, under that group's main (an alt's sheet links to its main, never
--- to the alt: LinkAlt refused that, and a member's claim was dropped by the officers). Officers write it; a
--- member's goes as a claim of the whole group, which names the member. True, or false and why: "self" (the same
--- group already), "officer" (refused by LinkAlt).
function AltAutoDetect:AddAlt(cardKey, altKey)
    if not cardKey or not altKey or cardKey == altKey then return false, "self" end
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    local main = links[cardKey] or cardKey
    if (links[altKey] or altKey) == main then return false, "self" end
    if GuildOS:IsOfficer() then
        return GuildOS:LinkAlt(altKey, main) and true or false, "officer"
    end
    local group = GuildOS:GetLinkedChars(main)
    group[#group + 1] = altKey
    self:LinkOwnAlts(main, group)
    return true
end

----------------------------------------------------------------------
-- A renamed character (#449): the same GUID under a new name. Its links move to the new name (an officer writes
-- them; a member's view and claim carry the new name into the group) and so do the account's answers about it.
-- A realm transfer changes the GUID: that character is a new one, asked about once like any other.
----------------------------------------------------------------------
--- Pure: `links` with `old` renamed `new` (its own link and every alt pointing at it). A new table.
function AltAutoDetect.PlanRename(links, old, new)
    local out = {}
    for k, v in pairs(links or {}) do
        if k ~= old then out[k] = (v == old) and new or v end
    end
    local m = (links or {})[old]
    if m and m ~= new then out[new] = m end
    if out[new] == new then out[new] = nil end
    return out
end

function AltAutoDetect:CheckRename()
    local r = GuildOSDB and GuildOSDB.altRenamed
    if type(r) ~= "table" or type(r.from) ~= "string" or type(r.to) ~= "string" then return end
    local roster = GuildOS.WholeRoster and GuildOS:WholeRoster()
    if not roster then return end   -- not the whole guild yet: try at the next login
    GuildOSDB.altRenamed = nil
    local guildSet = self:_GuildSet()
    local old, new = GuildOS:LocalMemberKey(r.from), GuildOS:LocalMemberKey(r.to)
    if guildSet[old] or not guildSet[new] then return end
    -- The account's answers about the old name are the new one's.
    local asks = self:_Asks()
    for pk, p in pairs(asks) do
        local x, y = pk:match("^(.-)|(.+)$")
        if x == old or y == old then
            local o = (x == old) and y or x
            asks[pk] = nil
            if o ~= new then asks[pairKey(new, o)] = mergeAsk(asks[pairKey(new, o)], p) end
        end
    end
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    local main = links[old]
    local heads = false
    for _, m in pairs(links) do if m == old then heads = true; break end end
    if not main and not heads then return end
    local planned = AltAutoDetect.PlanRename(links, old, new)
    if GuildOS:IsOfficer() then
        if GuildOS.AltSync then GuildOS.AltSync:Commit(planned) else GuildOS.db.altLinks = planned end
    else
        local head = planned[new] or new
        local group = GuildOS:GetLinkedChars(old)
        local keys = { head }
        for _, k in ipairs(group) do
            local nk = (k == old) and new or k
            if nk ~= head then keys[#keys + 1] = nk end
        end
        if #keys > 1 then self:LinkOwnAlts(head, keys) end
    end
end

function AltAutoDetect:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    -- Keyed the way this client keys: on WoW: Forever any other realm is rewritten to its own (#97).
    local main, alt, other = GuildOS:GetPlayerKey("Main"), GuildOS:GetPlayerKey("Alt"), GuildOS:GetPlayerKey("Other")
    local acc = { [main] = { level = 70 }, [alt] = { level = 61 }, [other] = { level = 70 } }
    local guild = { [main] = true, [alt] = true }   -- Other not in this guild
    S:Register("altauto.detect", function()
        local r = AltAutoDetect:DetectOwnAlts(acc, guild, {})
        if not r or r.main ~= main then return false, "main=highest level in guild" end
        if #r.group ~= 2 then return false, "only guild members grouped" end
        return true
    end)
    S:Register("altauto.needs_two", function()
        if AltAutoDetect:DetectOwnAlts(acc, { [main] = true }, {}) ~= nil then return false, "need 2+" end
        return true
    end)
    S:Register("altauto.already_linked", function()
        if AltAutoDetect:DetectOwnAlts(acc, guild, { [alt] = main }) ~= nil then
            return false, "already linked => nil"
        end
        return true
    end)
end
