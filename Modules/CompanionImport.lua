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
    if #members == 0 then return nil, L["That roster has nobody in it."] end

    return {
        raidId = data.raidId,
        title = data.title or "",
        instance = data.instance,
        startsAt = tonumber(data.startsAt) or 0,
        members = members,
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
    local raw = _G.GuildOSInbox
    if type(raw) ~= "string" or raw == "" then return false end
    -- Same string twice (a /reload with no new roster) is not a new import.
    if raw == self._lastInbox then return false end

    local roster = self:Parse(raw)
    if not roster then return false end

    self._lastInbox = raw
    BRutus.db.companionRoster = roster

    -- And put it on the guild calendar, so the raid is visible to people who
    -- never open the Web panel. Keyed off the site's raidId, so every officer
    -- running the companion converges on one event instead of each publishing
    -- their own copy of the same night.
    if BRutus.Calendar and BRutus.Calendar.UpsertWebRaid then
        BRutus:SafeCall(function() BRutus.Calendar:UpsertWebRaid(roster) end)
    end

    return true, #roster.members
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
