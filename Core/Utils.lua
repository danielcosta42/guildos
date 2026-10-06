----------------------------------------------------------------------
-- BRutus Guild Manager - Utilities
-- Pure helper functions. No business logic, no persistent state writes.
----------------------------------------------------------------------
local L = BRutus.L

----------------------------------------------------------------------
-- Alt / Main linking (account-wide attunement propagation)
----------------------------------------------------------------------
function BRutus:LinkAlt(altKey, mainKey)
    if not self:IsOfficer() then return false end
    if not altKey or not mainKey or altKey == mainKey then return false end
    self.db.altLinks = self.db.altLinks or {}
    -- Prevent circular links: mainKey must not itself be an alt
    if self.db.altLinks[mainKey] then
        self:Print(L["Error: "] .. mainKey .. L[" is already an alt. Unlink it first."])
        return false
    end
    self.db.altLinks[altKey] = mainKey
    if self.CommSystem then
        self.CommSystem:BroadcastAltLinks()
    end
    return true
end

function BRutus:UnlinkAlt(altKey)
    if not self:IsOfficer() then return false end
    self.db.altLinks = self.db.altLinks or {}
    self.db.altLinks[altKey] = nil
    if self.CommSystem then
        self.CommSystem:BroadcastAltLinks()
    end
    return true
end

-- Returns all keys in the same account group as playerKey (includes playerKey itself)
function BRutus:GetLinkedChars(playerKey)
    local altLinks = (self.db and self.db.altLinks) or {}
    -- Resolve canonical main
    local mainKey = altLinks[playerKey] or playerKey
    local result = { mainKey }
    local seen = { [mainKey] = true }
    for altK, mK in pairs(altLinks) do
        if mK == mainKey and not seen[altK] then
            seen[altK] = true
            table.insert(result, altK)
        end
    end
    return result
end

-- Pure re-point: given an altLinks table and a `group` (canonical main + all
-- its alts, as GetLinkedChars returns), return a NEW altLinks table in which
-- newMain is THE main (no entry) and every OTHER group member (including the
-- old main) points at newMain. The input table is never mutated, and links
-- for chars outside the group are copied through untouched. A group with
-- fewer than 2 members is returned as an unchanged copy. Idempotent: if
-- newMain is already the group's main the output equals the input.
function BRutus:_RepointGroup(altLinks, group, newMain)
    local out = {}
    for k, v in pairs(altLinks or {}) do out[k] = v end
    if not group or #group < 2 or not newMain then return out end
    for _, k in ipairs(group) do
        if k == newMain then
            out[k] = nil            -- the new main points at nobody
        else
            out[k] = newMain        -- old main + siblings point at newMain
        end
    end
    return out
end

-- Officer-side "set which character is the main" of an existing alt group.
-- Resolves the group via GetLinkedChars, no-ops (returns false) for a group
-- of fewer than 2 or when newMainKey is already the main, then re-points the
-- whole group onto newMainKey and broadcasts once. No circular link can
-- result because newMainKey's own entry is cleared.
function BRutus:SetMain(newMainKey)
    if not self:IsOfficer() then return false end
    if not newMainKey then return false end
    self.db.altLinks = self.db.altLinks or {}
    local group = self:GetLinkedChars(newMainKey)
    if #group < 2 then return false end                 -- nothing to re-main
    if self.db.altLinks[newMainKey] == nil then return false end  -- already main
    self.db.altLinks = self:_RepointGroup(self.db.altLinks, group, newMainKey)
    if self.CommSystem then
        self.CommSystem:BroadcastAltLinks()
    end
    return true
end

----------------------------------------------------------------------
-- General helpers
----------------------------------------------------------------------
function BRutus:DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = self:DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function BRutus:GetClassColor(class)
    local c = self.ClassColors[class]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

function BRutus:GetClassColorHex(class)
    local r, g, b = self:GetClassColor(class)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

function BRutus:ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function BRutus:FormatItemLevel(ilvl)
    if not ilvl or ilvl == 0 then return "|cff888888--|r" end
    local color
    if ilvl >= 141 then      -- T6+
        color = self.QualityColors[5]
    elseif ilvl >= 128 then   -- T5
        color = self.QualityColors[4]
    elseif ilvl >= 110 then   -- T4/Heroic
        color = self.QualityColors[3]
    elseif ilvl >= 85 then    -- Normal dungeons
        color = self.QualityColors[2]
    else
        color = self.QualityColors[1]
    end
    return self:ColorText(tostring(ilvl), color.r, color.g, color.b)
end

-- The client's realm for member keys: GetRealmName(), else GetNormalizedRealmName() (a
-- client with no realm name may still suffix roster names with a normalized one), else
-- nil; "" counts as nothing. Anniversary always answers the first, so its keys keep their bytes.
function BRutus:GetClientRealm()
    local realm = GetRealmName()
    if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
    if realm == "" then return nil end
    return realm
end

-- A member's key is "Name-Realm", byte for byte as it has always been. WoW: Forever has
-- no realms: when neither the caller nor the client gives one, the key is the name alone.
-- "First Last" and "Anne-Marie" then split on the first hyphen and rejoin to themselves,
-- so every split-and-rejoin site keeps a stable key.
--
-- On WoW: Forever the realm is always this client's (issue #95). Forever has no realms that set
-- players apart (a name is unique in its region) and its guild roster gives none, yet
-- GetRealmName() answers a name, and not the same one across a guild: on the beta,
-- "Classic Beta PvE" for one member and "Classic Beta PvE 2" for another. A realm taken from a
-- broadcast or a sender keyed a guildmate apart from their own roster line.
function BRutus:GetPlayerKey(name, realm)
    if not name or name == "" then return nil end
    if BRutus.Client and not BRutus.Client.isAnniversary then realm = nil end
    if not realm or realm == "" then realm = BRutus:GetClientRealm() end
    if not realm then return name end
    return name .. "-" .. realm
end

-- A member key another client built, as this client keys that member (issue #97). On WoW: Forever
-- a key carries its builder's realm and a guild's clients answer different ones, so a key that
-- arrives inside a payload is rebuilt from its name. Forever names never hold a hyphen (the roster,
-- the senders and UnitName all give "First Surname"), so the name is what comes before the first
-- one. Anniversary keys pass through: there a realm is part of who somebody is.
function BRutus:LocalMemberKey(key)
    if type(key) ~= "string" or key == "" then return key end
    if not (BRutus.Client and not BRutus.Client.isAnniversary) then return key end
    if key:find("^ally:") then return key end   -- an allied guild's member, realm-free already
    return self:GetPlayerKey(key:match("^([^-]+)") or key)
end

-- A table keyed by member keys, rekeyed with LocalMemberKey. `merge(held, incoming)` settles two
-- records that turn out to be the same member, and only ever sees two tables: a record always
-- beats a value that is not one, whichever came first. Without a merge the first record stays.
function BRutus:LocalizeMemberTable(t, merge)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        local lk = self:LocalMemberKey(k)
        local held = out[lk]
        if held == nil or (type(held) ~= "table" and type(v) == "table") then
            out[lk] = v
        elseif merge and type(held) == "table" and type(v) == "table" then
            out[lk] = merge(held, v)
        end
    end
    return out
end

-- The member-keyed tables a version before issue #97 stored with another client's keys, rekeyed
-- this client's way, each with its own merge for two keys that turn out to be one member. Forever
-- only, at start-up next to RekeyMembersToThisRealm, and once per database: every receive path
-- localizes since, so another pass would only rebuild the same tables (each session's snapshots
-- among them) on every login. Each table is its own step: bad data in one leaves the rest moved,
-- and the database is marked done only when every step was, so a failed one is retried.
function BRutus:LocalizeStoredMemberTables()
    if not (BRutus.Client and not BRutus.Client.isAnniversary) then return end
    local db = self.db
    if type(db) ~= "table" then return end
    local realm = self:GetClientRealm()
    if realm and db.storedKeysLocalized == realm then return end
    local rt = type(db.raidTracker) == "table" and db.raidTracker or {}
    local function points(pool)
        if type(pool) ~= "table" or type(pool.standings) ~= "table" then return end
        local start = tonumber(type(pool.config) == "table" and pool.config.startingPoints) or 0
        pool.standings = self:LocalizeMemberTable(pool.standings, function(a, b)
            a.current = (a.current or 0) + (b.current or 0) - start
            a.earned  = (a.earned or 0) + (b.earned or 0)
            a.spent   = (a.spent or 0) + (b.spent or 0)
            return a
        end)
    end
    local steps = {
        function()
            for group, recs in pairs(type(rt.attendance) == "table" and rt.attendance or {}) do
                -- The pre-group flat format is RaidTracker:MigrateAttendanceIfNeeded's to spot and rebuild.
                if type(recs) == "table" and recs.raids == nil and recs.lastRaid == nil and recs.raids25 == nil then
                    rt.attendance[group] = self:LocalizeMemberTable(recs, function(a, b)
                        local ra, rb = tonumber(a.raids) or 0, tonumber(b.raids) or 0
                        if rb ~= ra then return rb > ra and b or a end
                        return (tonumber(b.lastRaid) or 0) > (tonumber(a.lastRaid) or 0) and b or a
                    end)
                end
            end
        end,
        -- A session names each player twice, in its player list and in every snapshot: both move,
        -- or attendance rebuilt from them counts the same player late and gone early.
        function()
            for _, session in pairs(type(rt.sessions) == "table" and rt.sessions or {}) do
                if type(session) == "table" then
                    session.players = self:LocalizeMemberTable(session.players)
                    for _, snap in ipairs(type(session.snapshots) == "table" and session.snapshots or {}) do
                        if type(snap) == "table" then snap.members = self:LocalizeMemberTable(snap.members) end
                    end
                end
            end
        end,
        function()
            db.officerNotes = self:LocalizeMemberTable(db.officerNotes, function(a, b)
                return BRutus.OfficerNotes:MergeSheet(a, b)
            end)
        end,
        function()
            db.trials = self:LocalizeMemberTable(db.trials, function(a, b) return BRutus.TrialTracker:Merge(a, b) end)
        end,
        function()
            db.raiders = self:LocalizeMemberTable(db.raiders, function(a, b)
                return (tonumber(b.updatedAt) or 0) > (tonumber(a.updatedAt) or 0) and b or a
            end)
        end,
        function()
            if type(db.altLinks) ~= "table" then return end
            local links = {}
            for alt, main in pairs(db.altLinks) do
                local la, lm = self:LocalMemberKey(alt), self:LocalMemberKey(main)
                if la ~= lm then links[la] = lm end
            end
            db.altLinks = links
        end,
        function() points(db.points) end,
        function()
            for _, core in pairs(type(db.cores) == "table" and db.cores or {}) do
                if type(core) == "table" then
                    local ok = self:SafeCall(points, core.points)
                    core.members = self:LocalizeMemberTable(core.members)
                    core.signups = self:LocalizeMemberTable(core.signups)
                    if not ok then error("a core's points did not move") end   -- not done: retried
                end
            end
        end,
    }
    local done = true
    for _, step in ipairs(steps) do done = self:SafeCall(step) and done end
    if done then db.storedKeysLocalized = realm end
end

-- Members a version before issue #95 stored under the sender's realm move to this client's key,
-- the newer record winning, so nobody is shown without their data or counted twice. Forever
-- only: on Anniversary another realm is another player.
function BRutus:RekeyMembersToThisRealm()
    if not (BRutus.Client and not BRutus.Client.isAnniversary) then return end
    local members = self.db and self.db.members
    if type(members) ~= "table" then return end
    local moves = {}
    for key, rec in pairs(members) do
        local right = type(rec) == "table" and type(rec.name) == "string" and rec.name ~= ""
            and not (BRutus.Compat.IsSecret and BRutus.Compat.IsSecret(rec.name)) and self:GetPlayerKey(rec.name)
        if right and right ~= key then moves[#moves + 1] = { from = key, to = right, rec = rec } end
    end
    for _, mv in ipairs(moves) do
        if members[mv.from] == mv.rec then
            local held = members[mv.to]
            local winner, loser = mv.rec, held
            if held and (tonumber(held.lastUpdate) or 0) >= (tonumber(mv.rec.lastUpdate) or 0) then
                winner, loser = held, mv.rec
            end
            -- What only the older record knew (a look, a spec) is kept, never what it got wrong.
            if loser then
                for k, v in pairs(loser) do
                    if winner[k] == nil then winner[k] = v end
                end
            end
            members[mv.to] = winner
            members[mv.from] = nil
        end
    end
end

-- The roster's own key for somebody on it, built the way the roster frame builds it (the
-- roster name, on the realm its line gives or the player's), so a note typed for them lands
-- where their sheet reads it; then the shown name and the roster's whole name. Nil when
-- nobody on the roster has that name.
function BRutus:RosterKey(name)
    local idx = self.Compat.FindGuildRosterIndex(name)
    local full = idx and GetGuildRosterInfo(idx)
    if not full then return nil end
    local shown = full:match("^([^-]+)") or full
    return self:GetPlayerKey(shown, full:match("-(.+)$") or GetRealmName()), shown, full
end

-- Exactly somebody's roster name, with or without the realm. The roster lookup cuts at the
-- hyphen, so "Bob-Spineshatter great" would otherwise pass for Bob.
local function isRosterName(self, text)
    local _, shown, full = self:RosterKey(text)
    return shown ~= nil and (text == shown or text == full)
end

-- "<name> <text>" from a slash command. On WoW: Forever a name is two words ("Lethaniel
-- Blightwood"), so the first two are the name when they are somebody on the roster;
-- otherwise the first word, as it always was (issue #49).
function BRutus:SplitNameAndText(rest)
    rest = strtrim(rest)
    -- A whole name and nothing after it is a name with no note, not "Blightwood" as one.
    if isRosterName(self, rest) then return nil end
    local first, second, after = rest:match("^(%S+)%s+(%S+)%s+(.+)$")
    if first and isRosterName(self, first .. " " .. second) then
        return first .. " " .. second, after
    end
    return rest:match("^(%S+)%s+(.+)$")
end

----------------------------------------------------------------------
-- Member-authored free text
----------------------------------------------------------------------
-- Text a player types (a public note, an LFG note) ends up in FontStrings and
-- in the chat frame on every OTHER player's client, so it cannot be trusted
-- raw: a bare "|" injects a texture (|T...|t), an unterminated colour (|cff...)
-- that bleeds into the rest of the line, or a fake hyperlink (|H...|h). Strip
-- the escape character entirely (escaping to "||" renders literally in frames
-- that do not process escapes, so it is not equivalent) and flatten control
-- characters and runs of whitespace.
--
-- maxBytes, when given, caps the result WITHOUT splitting a UTF-8 codepoint.
-- string.sub counts bytes while SetMaxLetters counts characters, so an
-- accented note from a ptBR/deDE/frFR/esES player is longer in bytes than it
-- looks and a naive sub leaves a half codepoint that renders as a box.
local function utf8Backoff(s)
    local i = #s
    while i > 0 do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then break end   -- ASCII, or the lead byte
        i = i - 1                                 -- 10xxxxxx continuation
    end
    if i == 0 then return s end
    local lead, need = s:byte(i), 1
    if lead >= 0xF0 then need = 4
    elseif lead >= 0xE0 then need = 3
    elseif lead >= 0xC0 then need = 2 end
    if (#s - i + 1) < need then return s:sub(1, i - 1) end
    return s
end

----------------------------------------------------------------------
-- The record UI/MemberDetail.lua expects.
--
-- MemberDetail does NOT take a raw db.members entry: it needs the same merged
-- view the roster builds (UI/RosterFrame.lua), because `rank` and
-- `classDisplay` come from the LIVE guild roster and are never stored in the
-- synced member data. Passing the raw entry crashes on a nil format argument.
--
-- Returns nil when the character is not on this guild's roster.
----------------------------------------------------------------------
function BRutus:GetMemberRecord(name, realm)
    if not name or name == "" then return nil end
    local short = name:match("^([^-]+)") or name
    realm = realm or GetRealmName()

    local idx = self.Compat and self.Compat.FindGuildRosterIndex
        and self.Compat.FindGuildRosterIndex(short, realm)
    if not idx then return nil end

    local full, rankName, rankIndex, level, classLoc, zone, note, officerNote,
          isOnline, status, classFile = GetGuildRosterInfo(idx)
    local key = self:GetPlayerKey(short, realm)
    local data = (self.db and self.db.members and self.db.members[key]) or {}

    return {
        key          = key,
        name         = short,
        fullName     = full,
        realm        = realm,
        rank         = rankName or "",
        rankIndex    = rankIndex,
        level        = level or data.level or 0,
        class        = classFile or data.class or "",
        classDisplay = classLoc or "",
        zone         = zone or "",
        note         = note or "",
        officerNote  = officerNote or "",
        isOnline     = isOnline,
        status       = status or "",
        avgIlvl      = data.avgIlvl or 0,
        gear         = data.gear,
        -- WoW: Forever: the guild roster's professions for a member whose client sent none (issue #31).
        professions  = data.professions or (self.Professions and self.Professions:LegacyList(key)),
        attunements  = data.attunements,
        stats        = data.stats,
        spec         = data.spec,
        race         = data.race or "",
        lastUpdate   = data.lastUpdate or 0,
        lastSync     = data.lastSync or 0,
        addonVersion = data.addonVersion,
    }
end

-- A removable chip's label (issue #59): the text cut to `maxBytes` (14) on a character
-- boundary, ".." when something was cut, then the remove mark. UI:SetChipText shortens it
-- further until it fits the chip in whatever font is drawing it.
function BRutus:ChipLabel(text, maxBytes)
    local s = tostring(text or "")
    local short = self:SanitizeUserText(s, maxBytes or 14)
    if #short < #self:SanitizeUserText(s) then short = short .. ".." end
    return short .. "  x"
end

-- The first `n` characters of `s`, never half of one. A byte cut splits the Cyrillic, Hangul and
-- Han letters of four of the game's ten languages, and the names their players carry (#104).
function BRutus:Utf8Head(s, n)
    s = tostring(s or "")
    local i, count = 1, 0
    while i <= #s and count < n do
        local c = s:byte(i)
        i = i + ((c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1)
        count = count + 1
    end
    return s:sub(1, i - 1)
end

-- How many characters `s` has, for the same cuts.
function BRutus:Utf8Len(s)
    local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
    return n
end

function BRutus:SanitizeUserText(text, maxBytes)
    local s = (tostring(text or ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "))
    s = strtrim(s)
    if maxBytes and #s > maxBytes then
        s = utf8Backoff(s:sub(1, maxBytes))
    end
    return s
end

function BRutus:RegisterUtilTests()
    if not self.SelfTest then return end
    self.SelfTest:Register("utils.sanitize_escapes", function()
        if self:SanitizeUserText("|cffFF0000red|r") ~= "cffFF0000redr" then
            return false, "pipe not stripped"
        end
        if self:SanitizeUserText("|TInterface\\Icons\\X:64|t") ~= "TInterface\\Icons\\X:64t" then
            return false, "texture escape survived"
        end
        if self:SanitizeUserText("a\nb\tc") ~= "a b c" then return false, "control chars" end
        if self:SanitizeUserText("  spaced   out  ") ~= "spaced out" then return false, "trim/collapse" end
        if self:SanitizeUserText(nil) ~= "" then return false, "nil" end
        if self:SanitizeUserText({}) == nil then return false, "table must not error" end
        return true
    end)
    self.SelfTest:Register("utils.sanitize_utf8_cap", function()
        if self:SanitizeUserText("abcdef", 3) ~= "abc" then return false, "ascii cap" end
        if self:SanitizeUserText("abc", 10) ~= "abc" then return false, "under cap untouched" end
        -- "ação" is a,\xC3\xA7,a,o = 5 bytes. Capping at 2 must drop the split
        -- two-byte sequence, not leave half of it behind.
        local acao = "a\195\167ao"
        if self:SanitizeUserText(acao, 2) ~= "a" then return false, "split codepoint kept" end
        if self:SanitizeUserText(acao, 3) ~= "a\195\167" then return false, "whole codepoint dropped" end
        if self:SanitizeUserText(acao, 5) ~= acao then return false, "exact fit" end
        return true
    end)
    -- _RepointGroup is pure: no db, no comm. Pin the three re-main outcomes.
    self.SelfTest:Register("altlink.repoint_promote", function()
        local links = { ["Alt-R"] = "Main-R", ["Alt2-R"] = "Main-R" }
        local out = self:_RepointGroup(links, { "Main-R", "Alt-R", "Alt2-R" }, "Alt-R")
        if out["Alt-R"] ~= nil then return false, "new main must have no entry" end
        if out["Main-R"] ~= "Alt-R" then return false, "old main not re-pointed" end
        if out["Alt2-R"] ~= "Alt-R" then return false, "sibling not re-pointed" end
        if links["Alt-R"] ~= "Main-R" then return false, "input mutated" end
        return true
    end)
    self.SelfTest:Register("altlink.repoint_single", function()
        local out = self:_RepointGroup({}, { "Solo-R" }, "Solo-R")
        if next(out) ~= nil then return false, "1-member group must add nothing" end
        return true
    end)
    self.SelfTest:Register("altlink.repoint_noop_main", function()
        local out = self:_RepointGroup({ ["Alt-R"] = "Main-R" }, { "Main-R", "Alt-R" }, "Main-R")
        if out["Main-R"] ~= nil then return false, "main must stay the main" end
        if out["Alt-R"] ~= "Main-R" then return false, "alt must be unchanged" end
        return true
    end)
end

function BRutus:TimeAgo(timestamp)
    if not timestamp or timestamp == 0 then return L["Never"] end
    local diff = time() - timestamp
    if diff < 60 then return L["Just now"]
    elseif diff < 3600 then return math.floor(diff / 60) .. L["m ago"]
    elseif diff < 86400 then return math.floor(diff / 3600) .. L["h ago"]
    else return math.floor(diff / 86400) .. L["d ago"]
    end
end

----------------------------------------------------------------------
-- Chat Player Link: Guild Invite
-- Alt+Click a player name in chat to send a guild invite
----------------------------------------------------------------------
function BRutus:HookChatInvite()
    hooksecurefunc("SetItemRef", function(link, _, button)
        if not CanGuildInvite() then return end
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        if not link then return end

        local name = link:match("^player:([^:]+)")
        if name and name ~= "" then
            GuildInvite(name)
            BRutus:Print(L["Guild invite sent to "] .. name .. L[". (Alt+Click)"])
        end
    end)
end

----------------------------------------------------------------------
-- Profession Freshness Check & Reminder
----------------------------------------------------------------------
local STALE_THRESHOLD = 86400 -- 24 hours

function BRutus:GetStaleProfessions()
    local myData = self.db and self.db.myData
    if not myData or not myData.professions then return {} end

    local scanTimes = (self.db and self.db.recipeScanTimes) or {}
    local stale = {}
    local now = time()

    local DC = self.DataCollector
    for _, prof in ipairs(myData.professions) do
        local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(prof.name)
        if prof.isPrimary and prof.name and not isGathering then
            local lastScan = scanTimes[prof.name]
            if not lastScan or (now - lastScan) > STALE_THRESHOLD then
                table.insert(stale, prof.name)
            end
        end
    end

    return stale
end

function BRutus:CheckProfessionFreshness()
    if self.Professions then return end   -- WoW: Forever reads recipes without a window (issue #31)
    local stale = self:GetStaleProfessions()
    if #stale == 0 then return end

    self:ShowProfessionReminder(stale)
    self:Print(string.format(L["|cffFFAA00You have %d profession(s) with outdated recipe data.|r Open them to sync!"], #stale))
end

function BRutus:ShowProfessionReminder(staleProfessions)
    if self.profReminderFrame then
        self.profReminderFrame:Hide()
        self.profReminderFrame = nil
    end

    local C = self.Colors

    local frame = CreateFrame("Frame", "BRutusProfReminder", UIParent, "BackdropTemplate")
    frame:SetSize(420, 70)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.066, 0.066, 0.084, 0.95)
    frame:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Accent stripe on top
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture("Interface\\Buttons\\WHITE8x8")
    stripe:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.9)
    stripe:SetHeight(2)
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)

    -- Icon (trade skill icon)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")

    -- Title
    local titleFS = frame:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(titleFS, 11)
    titleFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    titleFS:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleFS:SetText(L["Guild OS — Profession Sync Required"])

    -- Description
    local profNames = table.concat(staleProfessions, ", ")
    local descFS = frame:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(descFS, 10)
    descFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
    descFS:SetWidth(320)
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)
    descFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    descFS:SetText(L["Open your profession windows to update recipe data:\n|cffFFFFFF"] .. profNames .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalFontObject(GameFontNormalSmall)

    local closeFS = closeBtn:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(closeFS, 12)
    closeFS:SetPoint("CENTER", 0, 0)
    closeFS:SetText("x")
    closeFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    closeBtn:SetScript("OnEnter", function()
        closeFS:SetTextColor(C.red.r, C.red.g, C.red.b)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    end)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        BRutus.profReminderFrame = nil
    end)

    -- Fade in
    frame:SetAlpha(0)
    frame:Show()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.3 then
            self:SetAlpha(elapsed / 0.3)
        else
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        end
    end)

    self.profReminderFrame = frame
    self.profReminderStale = {}
    for _, name in ipairs(staleProfessions) do
        self.profReminderStale[name] = true
    end
end

function BRutus:CheckAndDismissProfessionReminder()
    if not self.profReminderFrame or not self.profReminderStale then return end

    local scanTimes = (self.db and self.db.recipeScanTimes) or {}
    local now = time()

    for profName, _ in pairs(self.profReminderStale) do
        local lastScan = scanTimes[profName]
        if lastScan and (now - lastScan) <= STALE_THRESHOLD then
            self.profReminderStale[profName] = nil
        end
    end

    -- Check if any are still stale
    if not next(self.profReminderStale) then
        local frame = self.profReminderFrame
        -- Fade out
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 0.5 then
                self:SetAlpha(1 - (elapsed / 0.5))
            else
                self:Hide()
                self:SetScript("OnUpdate", nil)
                BRutus.profReminderFrame = nil
                BRutus.profReminderStale = nil
            end
        end)
        BRutus:Print(L["|cff00ff00All professions synced!|r Recipe data is up to date."])
    end
end

function BRutus:DismissProfessionReminder()
    if self.profReminderFrame then
        self.profReminderFrame:Hide()
        self.profReminderFrame = nil
        self.profReminderStale = nil
    end
end

----------------------------------------------------------------------
-- Data exports (tab-separated, paste straight into Sheets/Excel).
-- Headers stay in English on purpose so exports are a stable interchange
-- format regardless of the client locale.
----------------------------------------------------------------------
function BRutus:ExportRoster()
    local lines = { "Name\tClass\tLevel\tRank\tiLvl\tAttendance%\tAttunements\tLastSeen" }
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = self:GetPlayerKey(short, realm)
            local d = self.db.members[key] or {}
            local att = self.RaidTracker and self.RaidTracker:GetAttendance25ManPercent(key) or 0
            local attDone, attTotal = 0, 0
            if self.AttunementTracker then
                attTotal = #self.AttunementTracker:GetGuildColumns()
                for _, a in ipairs(self.AttunementTracker:GetEffectiveAttunements(key)) do
                    if a.complete and a.questsTotal and a.questsTotal > 0 then attDone = attDone + 1 end
                end
            end
            local lastSeen = (d.lastUpdate and d.lastUpdate > 0) and date("%Y-%m-%d", d.lastUpdate) or ""
            lines[#lines + 1] = table.concat({
                short, classFile or "", level or 0, rankName or "",
                d.avgIlvl or 0, att, attDone .. "/" .. attTotal, lastSeen,
            }, "\t")
        end
    end
    return table.concat(lines, "\n")
end

function BRutus:ExportLoot()
    local lines = { "Date\tItem\tPlayer\tRaid" }
    for _, e in ipairs(self.db.lootHistory or {}) do
        local itemName = (e.itemLink and BRutus.Compat.GetItemInfo(e.itemLink)) or e.itemName or "?"
        local dateStr = e.timestamp and date("%Y-%m-%d %H:%M", e.timestamp) or ""
        lines[#lines + 1] = table.concat({ dateStr, itemName, e.player or "?", e.raid or "" }, "\t")
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- First-seen tracking. WoW exposes no guild join date, so GuildOS
-- records when it first observed each member in the roster. This is a
-- "known to GuildOS since" date, not the true join date.
----------------------------------------------------------------------
function BRutus:RecordFirstSeen()
    if not self.db then return end
    if not self.db.firstSeen then self.db.firstSeen = {} end
    local now = GetServerTime()
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = self:GetPlayerKey(short, realm)
            if not self.db.firstSeen[key] then
                self.db.firstSeen[key] = now
            end
        end
    end
end

function BRutus:GetFirstSeen(playerKey)
    return self.db and self.db.firstSeen and self.db.firstSeen[playerKey]
end

----------------------------------------------------------------------
-- DB hygiene: drop cached data for members who left the guild.
-- Manual-only (never auto-run) to avoid data loss if the roster is mid-load.
-- Prunes the volatile caches (members gear/spec, firstSeen) but keeps officer
-- records (trials, officer notes) for historical reference.
----------------------------------------------------------------------
function BRutus:PruneStaleData()
    if not self.db then return 0 end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return 0 end  -- roster not loaded yet; refuse to prune

    local roster = {}
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            roster[self:GetPlayerKey(short, realm)] = true
        end
    end

    local removed = 0
    for key in pairs(self.db.members or {}) do
        if not roster[key] then
            self.db.members[key] = nil
            removed = removed + 1
        end
    end
    for key in pairs(self.db.firstSeen or {}) do
        if not roster[key] then
            self.db.firstSeen[key] = nil
        end
    end
    for key in pairs(self.db.professions or {}) do
        if not roster[key] then
            self.db.professions[key] = nil
            if self.Professions then self.Professions:Changed(key) end
        end
    end
    return removed
end
