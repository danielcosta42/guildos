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
GuildOS.CompanionImport = Import

--- The name to invite, and to match a raid slot or a guild roster row by.
--- On TBC Anniversary a name that arrives with its realm ("Chehul-Mankrik") is cut back
--- to the plain name the invite API wants for a same-realm player. WoW: Forever has no
--- realms and writes the surname with a hyphen ("Chehul-Costa"): cutting at the first
--- hyphen would invite somebody else. What comes off there is exactly the client's own
--- realm, if it reports one ("Chehul-Costa-70") — as it writes it, or without spaces the
--- way a roster row does — compared as plain text, never as a pattern. The site does the
--- same with the keys it receives (the site's specs/036). Retail takes the same path: a
--- "Name-Realm" on this character's realm comes back plain, one on another connected realm
--- keeps its realm, which is what an invite there needs (issue #182).
function Import.PlainName(name)
    if GuildOS.Client.isAnniversary then return name:match("^([^-]+)") or name end
    local realm = GuildOS:GetClientRealm()
    if realm and realm ~= "" then
        local compact = (realm:gsub("%s", ""))
        for _, suffix in ipairs({ "-" .. realm, "-" .. compact }) do
            if #name > #suffix and name:sub(-#suffix) == suffix then
                return name:sub(1, #name - #suffix)
            end
        end
    end
    return name
end

local L = GuildOS.L
local WIRE_PREFIX = "GOSROST1:"
local CORES_PREFIX = "GOSCORE1:"

-- The name somebody from the site is invited, grouped and shown by. On retail the key is
-- "Name-Realm" with their own realm and the name has none: the name alone would invite a
-- namesake on this character's realm, so the key is what is cut (issue #182). Elsewhere the
-- name, as it always was.
local function nameOf(entry)
    local key = GuildOS.Client.isRetail and type(entry.key) == "string" and entry.key ~= "" and entry.key
    return Import.PlainName(key or entry.name)
end

----------------------------------------------------------------------
-- Reading the string
----------------------------------------------------------------------

-- The table inside a wire string's body (what follows its prefix), when it is the `fmt` asked
-- for; nil when it is damaged or another kind.
local function unwrap(body, fmt)
    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:DecodeForPrint(body)
    local json = compressed and LibDeflate:DecompressDeflate(compressed)
    if not json then return nil end
    local ok, data = pcall(GuildOS.JsonDecode, json)
    if ok and type(data) == "table" and data.fmt == fmt then return data end
    return nil
end

--- Returns (roster, err). roster = { title, instance, startsAt, members = {...} }
function Import:Parse(raw)
    if not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then
        return nil, L["The web companion is off. Turn it on with /gos web on."]
    end

    raw = strtrim(raw or "")
    if not raw:find(WIRE_PREFIX, 1, true) then
        return nil, L["That doesn't look like a roster from the website."]
    end
    -- People paste with a stray newline or a leading space; find the marker
    -- rather than insisting the string starts with it.
    raw = raw:sub(raw:find(WIRE_PREFIX, 1, true) + #WIRE_PREFIX)

    if not (LibStub and LibStub("LibDeflate", true)) then return nil, L["LibDeflate not available."] end
    local data = unwrap(raw, "GOSROST1")
    if not data then return nil, L["The roster string is damaged. Copy it again."] end

    local members = {}
    for _, m in ipairs(data.members or {}) do
        if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            members[#members + 1] = {
                key = m.key or m.name,
                -- The invite API wants the plain name for a same-realm player.
                name = nameOf(m),
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
                    name = nameOf(s),
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

    return {
        raidId = data.raidId,
        title = data.title or "",
        instance = data.instance,
        instanceKey = type(data.instanceKey) == "string" and data.instanceKey or nil,
        size = tonumber(data.size) or 0,
        -- v3, retail: 14 Normal, 15 Heroic, 16 Mythic; nil elsewhere and from an older site (issue #182).
        difficulty = tonumber(data.difficulty),
        startsAt = tonumber(data.startsAt) or 0,
        members = members,
        signups = signups,
    }
end

--- Parse and keep. Returns (count, err).
function Import:Load(raw)
    local roster, err = self:Parse(raw)
    if not roster then return nil, err end
    -- Pasted by hand, a roster with nobody in it is a copy of the wrong thing. Nobody to invite is
    -- not an empty envelope once v2 exists, though: a night where everyone declined is a real
    -- answer. From the inbox an empty one is a raid nobody has answered yet, and it still belongs
    -- on the calendar (#146), so the refusal lives here and not in Parse.
    if #roster.members == 0 and not (roster.signups and #roster.signups > 0) then
        return nil, L["That roster has nobody in it."]
    end

    GuildOS.db.companionRoster = roster
    return #roster.members
end

function Import:Current()
    return GuildOS.db and GuildOS.db.companionRoster
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

    -- Every raid goes on the calendar, once the rank is known (CalendarFromInbox). The soonest
    -- somebody answered is the one the Web panel's invite and group buttons act on: an unanswered
    -- leftover on an earlier night would otherwise take it over (#146); with none answered, the
    -- soonest of all.
    local soonest, soonestAny, imported, raids = nil, nil, 0, {}
    -- And all of them, stripped to the fields that answer "which planned raid is this
    -- night": where, when and, on retail, on which difficulty (issue #182). The full
    -- rosters are not kept: the soonest is the one anybody acts on, and holding ten of
    -- them in SavedVariables to answer one question later is ten rosters of churn at
    -- every logout.
    local planned = {}
    for _, raw in ipairs(raws) do
        local roster = self:Parse(raw)
        if roster then
            imported = imported + 1
            raids[#raids + 1] = roster
            if roster.raidId and roster.instanceKey then
                planned[#planned + 1] = {
                    raidId = roster.raidId,
                    instanceKey = roster.instanceKey,
                    startsAt = roster.startsAt or 0,
                    difficulty = roster.difficulty,
                }
            end
            local answered = #roster.members > 0 or (roster.signups and #roster.signups > 0)
            if answered and (not soonest or (roster.startsAt or 0) < (soonest.startsAt or 0)) then
                soonest = roster
            end
            if not soonestAny or (roster.startsAt or 0) < (soonestAny.startsAt or 0) then
                soonestAny = roster
            end
        end
    end
    if imported == 0 then return false end
    soonest = soonest or soonestAny

    self._lastInbox = key
    self._webRaids = raids
    GuildOS.db.companionRoster = soonest
    GuildOS.db.companionRaids = planned
    return true, #soonest.members
end

-- The guild's Discord cores in the inbox (a GOSCORE1, specs/041 in guildos-web), decoded, whether the
-- companion is on in game, and when the inbox was written (its ack line, #138): nil when there are
-- none or the string is damaged. CoreManager imports them once the guild's db is known (#135), and
-- says why when it does not; the roster reader above passes over them.
function Import:CoresFromInbox()
    local inbox = _G.GuildOSInbox
    if type(inbox) ~= "table" then return nil end
    for _, v in ipairs(inbox) do
        if type(v) == "string" and v:sub(1, #CORES_PREFIX) == CORES_PREFIX then
            local ack = _G.GuildOSInboxAck
            local at = type(ack) == "table" and tonumber(ack.at) or nil
            local on = GuildOS.Companion and GuildOS.Companion:IsEnabled() or false
            return unwrap(v:sub(#CORES_PREFIX + 1), "GOSCORE1"), on, at
        end
    end
    return nil
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

--- Returns the raidId of the planned raid covering `when` in `instanceKey`, or nil. On retail
--- `difficulty` is the night's (14, 15, 16): a raid planned on another one is another lockout,
--- so when both say one they must agree (issue #182).
function Import:RaidFor(instanceKey, when, difficulty)
    if type(instanceKey) ~= "string" or instanceKey == "" then return nil end
    when = tonumber(when) or 0
    difficulty = tonumber(difficulty)

    local best, bestGap
    for _, r in ipairs((GuildOS.db and GuildOS.db.companionRaids) or {}) do
        if r.instanceKey == instanceKey and not (difficulty and r.difficulty and r.difficulty ~= difficulty) then
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
    if not (GuildOS.Companion and GuildOS.Companion:IsEnabled()) then
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

--- Everyone on the live guild roster, by the name the site would send: the name to invite.
--- On retail the site sends a name it never confirmed without a realm, and that is a guildmate
--- only when one connected realm has it: two namesakes are nobody to guess between (issue #182).
local function guildNames()
    local names, retail = {}, GuildOS.Client.isRetail
    for i = 1, (GetNumGuildMembers() or 0) do
        local full = GetGuildRosterInfo(i)
        if full then
            local plain = Import.PlainName(full)
            if retail then
                local short = full:match("^([^-]+)") or full
                if names[short] == nil then names[short] = plain else names[short] = false end
            else
                names[plain] = plain
            end
        end
    end
    return names
end

--- The people the site could not vouch for but the game can, by short name.
---
--- The site only calls a character confirmed once an ingested roster has carried the
--- same "Name-Realm". A guild that has never published has confirmed nobody, and on its
--- first night that is everyone who signed up — the leader pastes a roster and invites
--- one person. The roster is standing right here in the client, so ask it.
---
--- Only "unknown" is rescued. Somebody on standby, refused, or waiting for approval is
--- not missing a confirmation; they are missing a decision, and that one is not ours.
---
--- The panel and the invite button both read this, for the reason every predicate in
--- this file is shared: a button that says "the game has never seen this character"
--- beside somebody it just invited is two versions of the truth.
---
--- Keyed by the signup's name; the value is the name to invite, with the realm on retail
--- when the guildmate is on another connected realm (issue #182).
function Import:Rescued(roster)
    local out, guild = {}, nil
    for _, p in ipairs((roster and roster.signups) or {}) do
        if p.why == "unknown" and not p.invite and type(p.name) == "string" then
            guild = guild or guildNames()
            if guild[p.name] then out[p.name] = guild[p.name] end
        end
    end
    return out
end

-- Who a name stands for in the group: on retail the name with its realm, so a guildmate already
-- here from another connected realm is not invited again, and a namesake from another realm is
-- not taken for them (issue #182). Elsewhere the name.
local function presence(name, realm)
    if not GuildOS.Client.isRetail then return name end
    return GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, realm or name:match("^[^-]+%-(.+)$"))
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
    local me = GuildOS.Compat.PlayerName()
    present[presence(me)] = true
    for i = 1, (GetNumGroupMembers() or 0) do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local n, realm = GuildOS.Compat.UnitIdentity(unit)
        if n then present[presence(n, realm)] = true end
    end

    -- Compat knows which invite the client has: WoW: Forever only has C_PartyInfo's (issue #43).
    local function ask(name)
        GuildOS.Compat.InviteUnit(name)
    end

    local invited, skipped = 0, 0
    local function send(name)
        local who = presence(name)
        if present[who] then
            skipped = skipped + 1
        else
            ask(name)
            -- Marked here as well as counted: two signups can name the same character,
            -- and a second invite to a name already asked is an error in their chat.
            present[who] = true
            invited = invited + 1
        end
    end

    for _, m in ipairs(roster.members) do send(m.name) end
    for _, name in pairs(self:Rescued(roster)) do send(name) end
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
            local target = want[Import.PlainName(name)]
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
-- Read in two halves (#146). The roster as soon as the guild's db is known
-- (Core's InitModules): at PLAYER_LOGIN, where it used to be read, a db not
-- resolved yet read the companion as off, and the raid tracker stamps
-- tonight's raid from it when the session starts. The calendar once the rank
-- is known (Core's officer start-up): only an officer's client publishes the
-- site's raids, and a rank not loaded yet read an officer as not one, so the
-- raids stayed off the calendar for the whole session.
--
-- Errors are swallowed by SafeCall. A roster that fails to arrive must
-- never be the reason someone cannot log in.
----------------------------------------------------------------------
function Import:ReadInbox()
    GuildOS:SafeCall(function()
        local ok, count = Import:ConsumeInbox()
        if ok then
            GuildOS:Print(string.format(L["Roster from the website: %d signed up."], count))
        end
    end)
end

function Import:CalendarFromInbox()
    local raids = self._webRaids
    if not (raids and GuildOS.Calendar and GuildOS.Calendar.UpsertWebRaid) then return end
    -- When the site gave these, so an old inbox takes back nobody's answer.
    local answeredAt = self:Ack()
    for _, roster in ipairs(raids) do
        GuildOS:SafeCall(function() GuildOS.Calendar:UpsertWebRaid(roster, answeredAt) end)
    end
end
