----------------------------------------------------------------------
-- Guild OS - Companion Import (GOSROST1)
--
-- The other direction. CompanionExport sends what the game knows to the
-- website; this brings a finished roster back, so a raid leader stops
-- retyping twenty-five names into invite macros at 21:58.
--
--   "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
--
-- Same transport as GOSCOMP1, for the same reason: the string has to
-- survive being copied out of a browser and pasted into an edit box.
--
-- Everything here goes through Companion:IsEnabled(). The gate lives in
-- the export module so a new entry point cannot forget to ask.
----------------------------------------------------------------------
local Import = {}
BRutus.CompanionImport = Import

local L = BRutus.L
local WIRE_PREFIX = "GOSROST1:"

----------------------------------------------------------------------
-- Reading the string
----------------------------------------------------------------------

--- Returns (roster, err). roster = { title, instance, startsAt, members = {...} }
function Import:Parse(raw)
    if not (BRutus.Companion and BRutus.Companion:IsEnabled()) then
        return nil, L["The web companion is off. Turn it on with /gos web on."]
    end

    raw = strtrim(raw or "")
    if not raw:find(WIRE_PREFIX, 1, true) then
        return nil, L["That doesn't look like a roster from the website."]
    end
    -- People paste with a stray newline or a leading space; find the marker
    -- rather than insisting the string starts with it.
    raw = raw:sub(raw:find(WIRE_PREFIX, 1, true) + #WIRE_PREFIX)

    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    if not LibDeflate then return nil, L["LibDeflate not available."] end

    local compressed = LibDeflate:DecodeForPrint(raw)
    if not compressed then return nil, L["The roster string is damaged. Copy it again."] end

    local json = LibDeflate:DecompressDeflate(compressed)
    if not json then return nil, L["The roster string is damaged. Copy it again."] end

    local ok, data = pcall(BRutus.JsonDecode, json)
    if not ok or type(data) ~= "table" or data.fmt ~= "GOSROST1" then
        return nil, L["The roster string is damaged. Copy it again."]
    end

    local members = {}
    for _, m in ipairs(data.members or {}) do
        if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            members[#members + 1] = {
                key = m.key or m.name,
                -- The invite API wants the plain name for a same-realm player.
                name = m.name:match("^([^-]+)") or m.name,
                class = m.class or "",
                spec = m.spec or "",
                slot = m.slot or "RANGED",
                group = tonumber(m.group) or 0,
            }
        end
    end
    -- v2 and up. Absent on an older site, which is not the same as nobody signing up:
    -- the panel shows what it was given and stays quiet about the rest.
    --
    -- `members` above is frozen at "who can be invited". This is everyone who answered,
    -- including the ones who said no, the ones on standby, and the ones whose character
    -- no export has ever confirmed. None of them are invitable and all of them are
    -- things a raid leader is trying to find out at 21:58.
    local signups
    if type(data.signups) == "table" then
        signups = {}
        for _, s in ipairs(data.signups) do
            if type(s) == "table" and type(s.name) == "string" and s.name ~= "" then
                signups[#signups + 1] = {
                    key = type(s.key) == "string" and s.key or nil,
                    name = s.name:match("^([^-]+)") or s.name,
                    class = s.class or "",
                    spec = s.spec or "",
                    slot = s.slot or "RANGED",
                    status = s.status or "yes",
                    wait = tonumber(s.wait),
                    group = tonumber(s.group) or 0,
                    invite = s.invite == true,
                    why = type(s.why) == "string" and s.why or nil,
                }
            end
        end
    end

    -- Nobody to invite is not the same as an empty envelope once v2 exists: a night where
    -- everyone declined is a real answer, and one the panel should be allowed to show.
    if #members == 0 and not (signups and #signups > 0) then
        return nil, L["That roster has nobody in it."]
    end

    return {
        raidId = data.raidId,
        title = data.title or "",
        instance = data.instance,
        instanceKey = type(data.instanceKey) == "string" and data.instanceKey or nil,
        size = tonumber(data.size) or 0,
        startsAt = tonumber(data.startsAt) or 0,
        members = members,
        signups = signups,
    }
end

--- Parse and keep. Returns (count, err).
function Import:Load(raw)
    local roster, err = self:Parse(raw)
    if not roster then return nil, err end

    BRutus.db.companionRoster = roster
    return #roster.members
end

function Import:Current()
    return BRutus.db and BRutus.db.companionRoster
end

--- What the site last confirmed. Returns (unixTime, members) or nil.
---
--- Publishing used to be blind in this direction: the addon wrote the file, the
--- companion sent it, and nothing ever came back, so the panel could only ever say
--- "written". The companion knows the answer and already writes this file, so it
--- says so.
---
--- Numbers only, and that is a contract rather than a preference: the companion
--- formats these with %d, so the property that nothing off the network reaches a
--- file the client executes survives intact.
function Import:Ack()
    local a = _G.GuildOSInboxAck
    if type(a) ~= "table" then return nil end
    local at = tonumber(a.at)
    if not at or at <= 0 then return nil end
    return at, tonumber(a.members) or 0
end

----------------------------------------------------------------------
-- Inviting
----------------------------------------------------------------------

----------------------------------------------------------------------
-- The inbox: what the companion left for us.
--
-- The companion writes Interface/AddOns/GuildOS/Inbox.lua, which the client
-- executes at load, setting the GuildOSInbox global. That makes it untrusted
-- input even though our own tool produced it, so it goes through the same
-- Parse a hand-pasted string does and a bad one is dropped on the floor.
--
-- Silent on failure on purpose: a damaged inbox is the companion's problem to
-- report in its own panel, and a chat error at every login about a file the
-- player cannot see or fix is just noise.
--
-- The site is where raids are planned, so a valid inbox wins over whatever was
-- stored. Pasting by hand stays the fallback for when the companion is not
-- running. See specs/009-a-volta-para-o-jogo/spec.md in guildos-web.
----------------------------------------------------------------------
function Import:ConsumeInbox()
    -- A table of strings from a current companion, a bare string from one that
    -- has not been updated. The two halves ship separately, so both shapes have
    -- to work rather than the older one silently importing nothing.
    local inbox = _G.GuildOSInbox
    local raws = {}
    if type(inbox) == "table" then
        for _, v in ipairs(inbox) do
            if type(v) == "string" and v ~= "" then raws[#raws + 1] = v end
        end
    elseif type(inbox) == "string" and inbox ~= "" then
        raws[1] = inbox
    elseif type(_G.GuildOSInboxFirst) == "string" and _G.GuildOSInboxFirst ~= "" then
        raws[1] = _G.GuildOSInboxFirst
    end
    if #raws == 0 then return false end

    -- The whole set is the unit: a raid added or dropped changes it even when
    -- the first one did not move.
    local key = table.concat(raws, "|")
    if key == self._lastInbox then return false end

    -- Every raid goes on the calendar; the soonest is the one the Web panel's
    -- invite and group buttons act on.
    local soonest, imported = nil, 0
    -- And all of them, stripped to the three fields that answer "which planned raid is
    -- this night". The full rosters are not kept: the soonest is the one anybody acts on,
    -- and holding ten of them in SavedVariables to answer one question later is ten
    -- rosters of churn at every logout.
    local planned = {}
    for _, raw in ipairs(raws) do
        local roster = self:Parse(raw)
        if roster then
            imported = imported + 1
            if BRutus.Calendar and BRutus.Calendar.UpsertWebRaid then
                BRutus:SafeCall(function() BRutus.Calendar:UpsertWebRaid(roster) end)
            end
            if roster.raidId and roster.instanceKey then
                planned[#planned + 1] = {
                    raidId = roster.raidId,
                    instanceKey = roster.instanceKey,
                    startsAt = roster.startsAt or 0,
                }
            end
            if not soonest or (roster.startsAt or 0) < (soonest.startsAt or 0) then
                soonest = roster
            end
        end
    end
    if imported == 0 then return false end

    self._lastInbox = key
    BRutus.db.companionRoster = soonest
    BRutus.db.companionRaids = planned
    return true, #soonest.members
end

----------------------------------------------------------------------
-- Which planned raid is happening now
--
-- The same window the website uses, from the same two numbers: two hours before
-- covers a raid that pulled early, eight hours after covers a long night and a
-- start that slipped. They are written on both sides on purpose — two halves that
-- disagree about which night is which produce an accusation on the wrong evening,
-- and nothing anywhere would show that it happened.
--
-- Keys, never names. Matching "Magtheridon" against "Magtheridon's Lair" across two
-- codebases is what lost every Magtheridon night the site ever received.
----------------------------------------------------------------------
local MATCH_EARLY = 2 * 3600
local MATCH_LATE = 8 * 3600

--- Returns the raidId of the planned raid covering `when` in `instanceKey`, or nil.
function Import:RaidFor(instanceKey, when)
    if type(instanceKey) ~= "string" or instanceKey == "" then return nil end
    when = tonumber(when) or 0

    local best, bestGap
    for _, r in ipairs((BRutus.db and BRutus.db.companionRaids) or {}) do
        if r.instanceKey == instanceKey then
            local gap = when - (r.startsAt or 0)
            if gap >= -MATCH_EARLY and gap <= MATCH_LATE then
                gap = math.abs(gap)
                -- Nearest start wins. Two candidates only happen when a guild books the
                -- same instance twice inside one window, and then the closer is the one.
                if not bestGap or gap < bestGap then
                    best, bestGap = r.raidId, gap
                end
            end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Can this action run right now, and if not, why?
--
-- The Web panel greys a button and prints the reason beside it; the
-- slash command refuses with the same words. Both ask these, so a change
-- to the rule reaches the button and the command together instead of
-- drifting into two versions of the truth.
----------------------------------------------------------------------
function Import:CanInvite()
    if not self:Current() then return false, L["Import a roster first."] end
    if not (BRutus.Companion and BRutus.Companion:IsEnabled()) then
        return false, L["The web companion is off. Turn it on with /gos web on."]
    end
    return true
end

function Import:CanOrganize()
    if not self:Current() then return false, L["Import a roster first."] end
    if not IsInRaid() then return false, L["You need to be in a raid to organise groups."] end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false, L["Only the raid leader can organise groups."]
    end
    return true
end

--- Invite everyone on the loaded roster who is not already in the group.
--- Returns (invited, skipped, err).
function Import:InviteAll()
    local allowed, reason = self:CanInvite()
    if not allowed then return nil, nil, reason end
    local roster = self:Current()

    -- Who is already here. Inviting someone in the raid produces an error
    -- message in their chat for no reason.
    local present = {}
    local me = UnitName("player")
    present[me] = true
    for i = 1, (GetNumGroupMembers() or 0) do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local n = UnitName(unit)
        if n then present[n] = true end
    end

    local invited, skipped = 0, 0
    for _, m in ipairs(roster.members) do
        if present[m.name] then
            skipped = skipped + 1
        else
            -- C_PartyInfo is the modern call; InviteUnit is the Classic one.
            -- Both exist in TBC Anniversary depending on the build.
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(m.name)
            elseif InviteUnit then
                InviteUnit(m.name)
            end
            invited = invited + 1
        end
    end
    return invited, skipped, nil
end

----------------------------------------------------------------------
-- Groups
----------------------------------------------------------------------

--- Move raid members into the parties the website planned.
--- Returns (moved, err). Only works while in a raid and leading it.
function Import:OrganizeGroups()
    local allowed, reason = self:CanOrganize()
    if not allowed then return nil, reason end
    local roster = self:Current()

    -- Where the website wants each person.
    local want = {}
    for _, m in ipairs(roster.members) do
        if m.group >= 1 and m.group <= 8 then want[m.name] = m.group end
    end

    local moved = 0
    for i = 1, 40 do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local target = want[short]
            -- Only move people who are in the wrong place. Setting a group that
            -- is already correct still costs a server call and can shuffle
            -- someone else out of a full party.
            if target and subgroup and target ~= subgroup then
                SetRaidSubgroup(i, target)
                moved = moved + 1
            end
        end
    end
    return moved, nil
end

----------------------------------------------------------------------
-- Read the companion's drop box once the database exists.
--
-- PLAYER_LOGIN rather than ADDON_LOADED: Parse asks whether the web
-- companion is switched on, and that setting lives in the saved
-- variables, which are not there yet at ADDON_LOADED.
--
-- Errors are swallowed by SafeCall. A roster that fails to arrive must
-- never be the reason someone cannot log in.
----------------------------------------------------------------------
local reader = CreateFrame("Frame")
reader:RegisterEvent("PLAYER_LOGIN")
reader:SetScript("OnEvent", function()
    BRutus:SafeCall(function()
        local ok, count = Import:ConsumeInbox()
        if ok then
            BRutus:Print(string.format(L["Roster from the website: %d signed up."], count))
        end
    end)
end)
