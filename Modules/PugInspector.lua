----------------------------------------------------------------------
-- Guild OS - Pug Inspector ("Do I know this pug?")
-- Classifies the members of the player's current party/raid against data
-- GuildOS already holds (ban list, guild roster, alt links, notes, roster
-- log). PURE classifier + a live group Scan. NO new sync: everything is
-- read-only against existing state.
--
-- TAINT SAFETY: reads the group roster (GetRaidRosterInfo / party units) and
-- our own db only. Makes no protected call and overwrites no Blizzard global.
--
-- Rule 10 (no business logic in UI): the classification lives here; UI just
-- renders Scan() and flips the auto-open pref through our getters/setters.
----------------------------------------------------------------------
local PugInspector = {}
BRutus.PugInspector = PugInspector
local L = BRutus.L

function PugInspector:Initialize()
    self:_SetupEvents()
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure decision (deterministic; unit-tested via /gos selftest).
-- Takes explicit facts so tests pin each branch with no live state.
--   facts = {
--     banned, reason,            -- BanList
--     inGuild,                   -- this char is itself on the guild roster
--     isAlt, mainShort, mainInGuild,  -- altLinks resolution
--     exMember,                  -- best-effort, from the roster log
--     note,                      -- officer/public note (already resolved)
--   }
-- Returns { tag, detail, severity }. severity in high|warn|guild|unknown.
--
-- Order (most useful first): Banned -> Guildmate/Alt -> Alt of a guild main
-- -> Ex-member -> Unknown. A note is appended as `detail` for any non-banned
-- tag; on a banned player the ban reason is the more important detail and the
-- note is intentionally dropped.
----------------------------------------------------------------------
function PugInspector:_Decide(facts)
    local f = facts or {}
    local tag, detail, severity

    if f.banned then
        tag      = L["BANNED"]
        detail   = f.reason
        severity = "high"
    elseif f.inGuild then
        if f.isAlt and f.mainShort and f.mainShort ~= "" then
            tag = string.format(L["Alt of %s"], f.mainShort)
        else
            tag = L["Guildmate"]
        end
        severity = "guild"
    elseif f.isAlt and f.mainInGuild and f.mainShort and f.mainShort ~= "" then
        tag      = string.format(L["Alt of %s (guild)"], f.mainShort)
        severity = "guild"
    elseif f.exMember then
        tag      = L["Ex-member"]
        severity = "warn"
    else
        tag      = L["Unknown (not in guild)"]
        severity = "unknown"
    end

    if not f.banned and f.note and f.note ~= "" then
        detail = string.format(L["Note: %s"], f.note)
    end

    return { tag = tag, detail = detail, severity = severity }
end

----------------------------------------------------------------------
-- Pure: best-effort ex-member detection. Given a roster-log list (any order),
-- returns the action of the MOST RECENT event whose target short-name matches
-- `short` (case-insensitive), or nil. A later "join" therefore overrides an
-- earlier "leave"/"kick", so a rejoined player is not mislabelled. Callers
-- only treat "leave"/"kick" as ex-member, and only for players NOT currently
-- on the roster, so a stale record can never mislabel a present guildmate.
----------------------------------------------------------------------
function PugInspector:_LastRosterAction(short, log)
    if not short or short == "" or type(log) ~= "table" then return nil end
    local want = short:lower()
    local bestTs, bestAction = -1, nil
    for _, e in ipairs(log) do
        local t = e.target and (e.target:match("^([^-]+)") or e.target)
        if t and t:lower() == want then
            local ts = e.timestamp or 0
            if ts >= bestTs then
                bestTs, bestAction = ts, e.action
            end
        end
    end
    return bestAction
end

----------------------------------------------------------------------
-- Live data sources (built once per Scan). Injectable: pass a table with the
-- same shape to Classify to test it without live guild/ban/alt state.
----------------------------------------------------------------------
function PugInspector:_LiveSources()
    local db = BRutus.db or {}

    -- Guild roster short-name set (lowercased) for O(1) membership checks.
    local guildShort = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local s = full:match("^([^-]+)") or full
            guildShort[s:lower()] = true
        end
    end

    local log = (BRutus.RosterLog and BRutus.RosterLog.GetLog and BRutus.RosterLog:GetLog()) or nil
    local officerNotes = db.officerNotes or {}

    return {
        guildShort = guildShort,
        altLinks   = db.altLinks or {},
        log        = log,
        realm      = (GetRealmName and GetRealmName()) or "",
        banEntry   = function(short)
            if BRutus.BanList and BRutus.BanList:IsBanned(short) then
                return BRutus.BanList:Get(short)
            end
            return nil
        end,
        -- Officer note (most recent) first, else the guild public note. The
        -- public note only exists for a roster member, so it is only fetched
        -- when inGuild (also bounds the O(roster) FindGuildRosterIndex scan).
        -- Both are member-authored, so they go through the shared sanitizer
        -- before reaching a FontString (a bare "|" would inject an escape).
        noteFor    = function(short, realm, key, inGuild)
            local on = officerNotes[key]
            local text = on and on.notes and on.notes[1] and on.notes[1].text
            if text and text ~= "" then
                return BRutus:SanitizeUserText(text, 80)
            end
            if inGuild and BRutus.Compat and BRutus.Compat.GetGuildPublicNote then
                local pub = BRutus.Compat.GetGuildPublicNote(short, realm)
                if pub and pub ~= "" then
                    return BRutus:SanitizeUserText(pub, 80)
                end
            end
            return nil
        end,
    }
end

----------------------------------------------------------------------
-- Classify one player by name. `name` may be "Name" or "Name-Realm".
-- KEY-FORM: db.altLinks / db.officerNotes keys are "Name-Realm"
-- (GetPlayerKey), while the group/guild APIs hand back bare "Name". We
-- normalize BOTH sides here: short + realm -> "Name-Realm" for the table
-- lookups, short (lowercased) for the roster / ban short-name checks.
----------------------------------------------------------------------
function PugInspector:Classify(name, srcs)
    srcs = srcs or self:_LiveSources()
    local short = (name and (name:match("^([^-]+)") or name)) or ""
    local realm = (name and name:match("%-(.+)$")) or srcs.realm or ""
    local key   = short .. "-" .. realm
    local shortLower = short:lower()

    local f = {}

    local ban = srcs.banEntry and srcs.banEntry(short)
    if ban then
        f.banned = true
        f.reason = ban.reason or L["(no reason)"]
    end

    f.inGuild = (srcs.guildShort and srcs.guildShort[shortLower]) and true or false

    local mainKey = srcs.altLinks and srcs.altLinks[key]
    if mainKey then
        f.isAlt = true
        f.mainShort = mainKey:match("^([^-]+)") or mainKey
        f.mainInGuild = (srcs.guildShort and srcs.guildShort[(f.mainShort or ""):lower()]) and true or false
    end

    if srcs.log then
        local last = self:_LastRosterAction(shortLower, srcs.log)
        f.exMember = (last == "leave" or last == "kick")
    end

    if srcs.noteFor then
        f.note = srcs.noteFor(short, realm, key, f.inGuild)
    end

    return self:_Decide(f)
end

----------------------------------------------------------------------
-- Current group membership (self excluded). Returns { {name, full, class} }.
-- `name` is the short display name; `full` keeps any realm suffix so Classify
-- can resolve the "Name-Realm" table keys; `class` is the class file token.
----------------------------------------------------------------------
function PugInspector:_GroupMembers()
    local out = {}
    local myName = UnitName and UnitName("player")

    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if name then
                local short = name:match("^([^-]+)") or name
                if short ~= myName then
                    out[#out + 1] = { name = short, full = name, class = classFile or "" }
                end
            end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, (GetNumGroupMembers() or 1) - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local nm = UnitName(unit)
                local _, cf = UnitClass(unit)
                if nm then
                    out[#out + 1] = { name = nm:match("^([^-]+)") or nm, full = nm, class = cf or "" }
                end
            end
        end
    end

    return out
end

-- Classify every member of the current group. Returns a list of
-- { name, class, tag, detail, severity }. Empty when solo / not grouped.
function PugInspector:Scan()
    local srcs = self:_LiveSources()
    local out = {}
    for _, m in ipairs(self:_GroupMembers()) do
        local c = self:Classify(m.full, srcs)
        out[#out + 1] = {
            name = m.name, class = m.class,
            tag = c.tag, detail = c.detail, severity = c.severity,
        }
    end
    return out
end

----------------------------------------------------------------------
-- Auto-open preference (persisted; default OFF). UI reads/writes ONLY
-- through these; it never touches db directly (Rule 8).
----------------------------------------------------------------------
function PugInspector:IsAutoOpen()
    return BRutus:GetSetting("pugAutoOpen") == true
end

function PugInspector:SetAutoOpen(on)
    BRutus:SetSetting("pugAutoOpen", on and true or false)
end

----------------------------------------------------------------------
-- Events + auto-open. GROUP_ROSTER_UPDATE fires in bursts as a group forms,
-- so we debounce, then: refresh the window if it's open, and (if the pref is
-- on) show it ONCE per distinct group when it contains a high-severity
-- member. _autoShown is reset only when the group's member signature changes,
-- so it will not reopen every roster tick for the same group.
----------------------------------------------------------------------
local function groupSig(scan)
    local names = {}
    for _, e in ipairs(scan) do names[#names + 1] = (e.name or ""):lower() end
    table.sort(names)
    return table.concat(names, ",")
end

function PugInspector:_SetupEvents()
    if self._eventFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() PugInspector:_OnGroupUpdate() end)
    self._eventFrame = f
end

function PugInspector:_OnGroupUpdate()
    if self._debounce then return end
    self._debounce = true
    BRutus.Compat.After(0.5, function()
        PugInspector._debounce = false
        BRutus:SafeCall(function() PugInspector:_Evaluate() end)
    end)
end

function PugInspector:_Evaluate()
    if not (IsInGroup and IsInGroup()) then
        self._groupSig = nil
        self._autoShown = false
        if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
        return
    end

    local scan = self:Scan()
    local sig = groupSig(scan)
    if sig ~= self._groupSig then
        self._groupSig = sig
        self._autoShown = false
    end

    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end

    if self:IsAutoOpen() and not self._autoShown then
        for _, e in ipairs(scan) do
            if e.severity == "high" then
                self._autoShown = true
                if self.uiOpen then BRutus:SafeCall(self.uiOpen) end
                break
            end
        end
    end
end

----------------------------------------------------------------------
-- Self-tests (pure logic only; injected facts/sources, never live state).
----------------------------------------------------------------------
function PugInspector:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("pug.decide_banned", function()
        local r = PugInspector:_Decide({ banned = true, reason = "ninja" })
        if r.severity ~= "high" then return false, "severity " .. tostring(r.severity) end
        if r.detail ~= "ninja" then return false, "detail " .. tostring(r.detail) end
        if r.tag ~= L["BANNED"] then return false, "tag " .. tostring(r.tag) end
        return true
    end)

    S:Register("pug.decide_banned_keeps_reason_over_note", function()
        local r = PugInspector:_Decide({ banned = true, reason = "ninja", note = "nice" })
        if r.detail ~= "ninja" then return false, "note must not override reason" end
        return true
    end)

    S:Register("pug.decide_guildmate", function()
        local r = PugInspector:_Decide({ inGuild = true })
        if r.tag ~= L["Guildmate"] or r.severity ~= "guild" then return false, tostring(r.tag) end
        if r.detail ~= nil then return false, "no detail expected" end
        return true
    end)

    S:Register("pug.decide_alt_in_guild", function()
        local r = PugInspector:_Decide({ inGuild = true, isAlt = true, mainShort = "Thordak" })
        if r.tag ~= string.format(L["Alt of %s"], "Thordak") then return false, tostring(r.tag) end
        if r.severity ~= "guild" then return false, "severity" end
        return true
    end)

    S:Register("pug.decide_alt_of_guild_main", function()
        local r = PugInspector:_Decide({ isAlt = true, mainInGuild = true, mainShort = "Thordak" })
        if r.tag ~= string.format(L["Alt of %s (guild)"], "Thordak") then return false, tostring(r.tag) end
        if r.severity ~= "guild" then return false, "severity" end
        return true
    end)

    S:Register("pug.decide_alt_of_nonguild_is_unknown", function()
        -- An alt whose main is NOT in the guild, and who is not on the roster,
        -- must not claim a guild relationship: it falls through to Unknown.
        local r = PugInspector:_Decide({ isAlt = true, mainInGuild = false, mainShort = "Ghost" })
        if r.tag ~= L["Unknown (not in guild)"] or r.severity ~= "unknown" then return false, tostring(r.tag) end
        return true
    end)

    S:Register("pug.decide_exmember", function()
        local r = PugInspector:_Decide({ exMember = true })
        if r.tag ~= L["Ex-member"] or r.severity ~= "warn" then return false, tostring(r.tag) end
        return true
    end)

    S:Register("pug.decide_unknown", function()
        local r = PugInspector:_Decide({})
        if r.tag ~= L["Unknown (not in guild)"] or r.severity ~= "unknown" then return false, tostring(r.tag) end
        return true
    end)

    S:Register("pug.decide_note_appended", function()
        local r = PugInspector:_Decide({ inGuild = true, note = "solid healer" })
        if r.tag ~= L["Guildmate"] then return false, "tag" end
        if r.detail ~= string.format(L["Note: %s"], "solid healer") then return false, "detail " .. tostring(r.detail) end
        return true
    end)

    S:Register("pug.lastaction_leave", function()
        local log = {
            { action = "join",  target = "Zed", timestamp = 10 },
            { action = "leave", target = "Zed", timestamp = 20 },
        }
        if PugInspector:_LastRosterAction("zed", log) ~= "leave" then return false, "should be leave" end
        return true
    end)

    S:Register("pug.lastaction_rejoin_wins", function()
        local log = {
            { action = "leave", target = "Zed", timestamp = 20 },
            { action = "join",  target = "Zed", timestamp = 30 },
        }
        if PugInspector:_LastRosterAction("Zed", log) ~= "join" then return false, "rejoin must win" end
        if PugInspector:_LastRosterAction("Nobody", log) ~= nil then return false, "unknown name" end
        return true
    end)

    S:Register("pug.classify_keyform", function()
        -- KEY-FORM: altLinks key is "Bornax-TestRealm"; the group API hands us
        -- bare "Bornax". Classify must rebuild the key and resolve the alt.
        local srcs = {
            realm = "TestRealm",
            guildShort = { ["thordak"] = true, ["kaelra"] = true },
            altLinks = { ["Bornax-TestRealm"] = "Thordak-TestRealm" },
            banEntry = function(s) if s == "Zezinho" then return { reason = "ninja" } end end,
            noteFor = function() return nil end,
        }
        local a = PugInspector:Classify("Bornax", srcs)
        if a.tag ~= string.format(L["Alt of %s (guild)"], "Thordak") then return false, "alt " .. tostring(a.tag) end
        local g = PugInspector:Classify("Kaelra", srcs)
        if g.tag ~= L["Guildmate"] then return false, "guildmate " .. tostring(g.tag) end
        local b = PugInspector:Classify("Zezinho", srcs)
        if b.severity ~= "high" or b.detail ~= "ninja" then return false, "banned " .. tostring(b.tag) end
        local u = PugInspector:Classify("Strangr", srcs)
        if u.severity ~= "unknown" then return false, "unknown " .. tostring(u.tag) end
        return true
    end)
end
