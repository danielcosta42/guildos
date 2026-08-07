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

--- Invite everyone on the loaded roster who is not already in the group.
--- Returns (invited, skipped, err).
function Import:InviteAll()
    local roster = self:Current()
    if not roster then return nil, nil, L["Import a roster first."] end
    if not (BRutus.Companion and BRutus.Companion:IsEnabled()) then
        return nil, nil, L["The web companion is off. Turn it on with /gos web on."]
    end

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
    local roster = self:Current()
    if not roster then return nil, L["Import a roster first."] end
    if not IsInRaid() then return nil, L["You need to be in a raid to organise groups."] end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return nil, L["Only the raid leader can organise groups."]
    end

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
