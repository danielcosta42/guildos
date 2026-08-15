----------------------------------------------------------------------
-- Guild OS - Companion Export (GOSCOMP1)
--
-- Builds the payload the web companion reads: everything the guild's
-- clients have verified about themselves, in one string a person can
-- copy out of the game and paste into the site.
--
-- Wire format, and it must not drift — the web decoder is written
-- against exactly this:
--
--   "GOSCOMP1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
--
-- EncodeForPrint is used rather than base64 because the string has to
-- survive being selected out of a WoW edit box and pasted into a browser.
--
-- Business logic only — UI calls Build() and shows the result.
----------------------------------------------------------------------
local Companion = {}
BRutus.Companion = Companion

-- The marker on the wire carries a colon; the `fmt` field inside the payload
-- does not. They are two different things and the web checks both.
local WIRE_PREFIX = "GOSCOMP1:"
local FMT = "GOSCOMP1"

-- Payload version. 1 was roster, spec, professions, attunements and
-- attendance. 2 adds the enchant summary, which is what lets the site say
-- "four slots unenchanted" instead of just showing an item level. 3 adds the
-- nights RaidTracker has been recording all along — who was actually there,
-- which is the half of "the signup that doesn't lie" the site never had. 4 adds
-- what the site needs to arrive at the same attendance number the game shows:
-- the consumable count behind the flag, the non-guild-raid mark, and each core's
-- penalty weights.
local PAYLOAD_VERSION = 4

----------------------------------------------------------------------
-- JSON encoding
--
-- The addon ships a JSON *decoder* (SoftRes imports Gargul strings) but
-- has never needed an encoder. This one only has to handle what we build
-- below: strings, finite numbers, booleans, arrays and maps.
----------------------------------------------------------------------
local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
    ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function jsonString(s)
    -- Control characters have to go out as \u00XX or the decoder rejects them.
    -- Player-authored text reaches this function, so it cannot be trusted.
    local out = tostring(s):gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. out .. '"'
end

local function jsonNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then return "0" end
    -- Integers must not go out as "5.0": the web side reads counts and ids.
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.4g", n)
end

local encode

-- An empty Lua table is ambiguous — it is both {} and []. Every empty
-- collection we emit is a list, so that is the default; a map is only
-- produced when there is at least one key.
local function isArray(t)
    return t[1] ~= nil or next(t) == nil
end

encode = function(v)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return jsonNumber(v) end
    if t == "string" then return jsonString(v) end
    if t ~= "table" then return jsonString(tostring(v)) end

    local parts = {}
    if isArray(v) then
        for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    -- Sorted keys so the same roster always produces the same string, which
    -- makes "did anything actually change?" answerable by comparison.
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = jsonString(k) .. ":" .. encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

Companion.EncodeJson = encode

----------------------------------------------------------------------
-- Per-member pieces
----------------------------------------------------------------------

-- Slots where a missing enchant is a real problem in TBC. Same list the
-- audit panel uses — one source, so the site and the in-game audit can
-- never disagree about who is missing what.
local function enchantSummary(gear)
    if not gear then return nil end
    local slots = BRutus.GearAudit and BRutus.GearAudit:GetEnchantableSlots()
    if not slots then return nil end

    local missing, checked = {}, 0
    for _, slotId in ipairs(slots) do
        local item = gear[slotId]
        -- Only an equipped slot can be missing an enchant. An empty slot is a
        -- different problem and saying "unenchanted" about it would be wrong.
        if item and item.name and item.name ~= "" then
            checked = checked + 1
            if not (item.enchantId and item.enchantId > 0) then
                missing[#missing + 1] = BRutus.SlotNames[slotId] or ("Slot " .. slotId)
            end
        end
    end
    if checked == 0 then return nil end
    return { checked = checked, missing = missing }
end

local function attunementsFor(key)
    local out = {}
    if not BRutus.AttunementTracker then return out end
    for _, a in ipairs(BRutus.AttunementTracker:GetEffectiveAttunements(key)) do
        out[#out + 1] = {
            short = a.short,
            complete = a.complete and true or false,
            -- 0..1. A partial chain is the useful number: "Kara 7/9" is a
            -- different conversation from "Kara 0/9".
            progress = tonumber(a.progress) or (a.complete and 1 or 0),
        }
    end
    return out
end

local function professionsFor(data)
    local out = {}
    for _, p in ipairs(data.professions or {}) do
        if p.name then out[#out + 1] = { name = p.name, rank = tonumber(p.rank) or 0 } end
    end
    return out
end

----------------------------------------------------------------------
-- Nights
--
-- RaidTracker has recorded these since long before the site could receive
-- them: encounters, five-minute snapshots, who was in the group, whether they
-- were online, whether they had consumables. This is the first time any of it
-- leaves the game.
--
-- The roll-up happens here rather than on the site because the addon holds
-- presence per *snapshot*: a four-hour night with 25 people is over a thousand
-- entries, and `{ snapshots, first, last, offline, consumes }` per person says
-- everything those screens ask while being an order of magnitude smaller. The
-- person's count against the session's is the fraction of the night they were
-- there, which is partial attendance without the whole timeline.
----------------------------------------------------------------------
local function rollUpPlayers(session, startTime)
    local seen = {}
    for _, snap in ipairs(session.snapshots or {}) do
        local at = tonumber(snap.time) or 0
        for key, m in pairs(snap.members or {}) do
            local p = seen[key]
            if not p then
                p = { key = key, snapshots = 0, first = at, last = at,
                      offline = false, consumes = false }
                seen[key] = p
            end
            p.snapshots = p.snapshots + 1
            if at < p.first then p.first = at end
            if at > p.last then p.last = at end
            -- Both flags are "at least once". Someone who dropped for one
            -- snapshot dropped; someone who had a flask for one had one.
            if m.online == false then p.offline = true end
            if m.hasConsumes then p.consumes = true end
            -- The count as well as the flag, because the attendance penalty is a
            -- ratio: `RaidTracker:UpdateAttendanceForLockout` docks the score when
            -- consumables show up in under half the snapshots that saw the person.
            -- "At least once" cannot answer that, so the site could never arrive at
            -- the same number the game shows.
            if m.hasConsumes then p.chits = (p.chits or 0) + 1 end
        end
    end

    -- Whoever the session knows was there but no snapshot ever caught.
    --
    -- Snapshots do not travel between officers, and the broadcast says so in as many
    -- words: it carries `players`, the encounters and the already-computed attendance,
    -- and leaves the frames behind. So an officer who received a night from a peer
    -- holds everyone who was there and evidence of none of them, and a night the two
    -- clients merged holds one officer's frames and both officers' people.
    --
    -- Emitting only what the frames saw is how the site ended up with three of five
    -- nights empty and a roster split between perfect and terrible, while the game
    -- showed a sane number for the same guild — the addon's own rule reads
    -- `session.players`, which survives the broadcast, and this did not.
    --
    -- `snapshots = 0` is the entire signal, and it needs no field of its own: it says
    -- "in the group, never in a frame". The addon's late and left-early guards check
    -- membership of the first and last frame, so with no frame to check they do not
    -- fire, and the site reads the zero the same way.
    for key in pairs(session.players or {}) do
        if not seen[key] then
            local at = tonumber(startTime) or tonumber(session.startTime) or 0
            seen[key] = { key = key, snapshots = 0, first = at, last = at,
                          offline = false, consumes = false }
        end
    end

    local out = {}
    for _, p in pairs(seen) do out[#out + 1] = p end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

----------------------------------------------------------------------
-- What each core docks from a perfect night.
--
-- Attendance is a score, not a count: a lockout is worth 100 and arriving late,
-- leaving early or raiding dry each take a bite out of it. The weights are per
-- core and an officer can change them, so the site cannot assume 10/10/10 and
-- still promise the same number the game shows.
--
-- Current config, not a stamp on each session: the addon recomputes its whole
-- history with today's weights every time it rebuilds, and freezing them per
-- night would make the two drift the moment somebody edited a core.
----------------------------------------------------------------------
local function attendanceRules(sessions)
    if not BRutus.CoreManager then return nil end
    local rules, any = {}, false
    local seen = {}
    for _, s in ipairs(sessions or {}) do
        local tag = s.groupTag or ""
        if not seen[tag] then
            seen[tag] = true
            local p = BRutus.CoreManager:GetPenalties(tag)
            rules[tag] = { late = p.LATE, early = p.LEFT_EARLY, dry = p.NO_CONSUMES }
            any = true
        end
    end
    return any and rules or nil
end

local function guildRaidFlag(session)
    if session.isGuildRaid == false then return false end
    return nil
end

local function raidSessions()
    local db = BRutus.db and BRutus.db.raidTracker
    if not db then return nil, nil end

    local sessions = {}
    for id, s in pairs(db.sessions or {}) do
        local startTime = tonumber(s.startTime) or tonumber(id) or 0
        if startTime > 0 then
            local encounters = {}
            for _, e in ipairs(s.encounters or {}) do
                encounters[#encounters + 1] = {
                    id = tonumber(e.id) or 0,
                    name = e.name or "",
                    start = math.floor(tonumber(e.startTime) or 0),
                    -- Absent, not zero: a night that ended mid-pull has no end
                    -- and no verdict, which is different from a wipe.
                    ["end"] = e.endTime and math.floor(e.endTime) or nil,
                    success = e.success,
                }
            end
            sessions[#sessions + 1] = {
                id = math.floor(tonumber(id) or startTime),
                groupTag = s.groupTag or "",
                -- The planned raid this night was stamped with when it started, so the
                -- site does not have to guess from an instance name and a clock. Absent
                -- for a night nobody planned, which is most of them.
                raidId = type(s.raidId) == "string" and s.raidId ~= "" and s.raidId or nil,
                instanceID = tonumber(s.instanceID) or 0,
                -- Only when false, mirroring the addon's own `isGuildRaid ~= false`:
                -- every session recorded before the flag existed is a guild raid, and
                -- absent has to keep meaning that on the far side too. Attendance
                -- ignores the ones marked false, so without this the site would count
                -- somebody's pug alt run against the guild's roster.
                --
                -- Spelled out rather than `x and false or nil`, which is the Lua trap
                -- that cannot ever yield false and would have shipped every alt run as
                -- a guild raid.
                guildRaid = guildRaidFlag(s),
                name = s.name or "",
                startTime = math.floor(startTime),
                endTime = s.endTime and math.floor(s.endTime) or nil,
                -- The denominator every player's count is read against.
                snapshots = #(s.snapshots or {}),
                encounters = encounters,
                players = rollUpPlayers(s, startTime),
            }
        end
    end
    table.sort(sessions, function(a, b) return a.startTime < b.startTime end)

    -- Tombstones travel as a list of ids. Without them a night an officer
    -- deleted here comes back from another officer's export, forever.
    local deleted = {}
    for id in pairs(db.deletedSessions or {}) do
        local n = tonumber(id)
        if n then deleted[#deleted + 1] = math.floor(n) end
    end
    table.sort(deleted)

    return sessions, deleted
end

----------------------------------------------------------------------
-- The switch
--
-- Everything that crosses between the game and the site goes through here —
-- this export today, roster import tomorrow. Guarding the module rather than
-- each caller means a new entry point cannot forget to ask.
--
-- Off by default. The payload carries the whole guild's gear, attunements and
-- attendance, and a guild that does not use the site should not have that one
-- mistyped command away.
----------------------------------------------------------------------
function Companion:IsEnabled()
    return BRutus:GetSetting("companion") == true
end

function Companion:SetEnabled(on)
    BRutus:SetSetting("companion", on and true or false)
end

----------------------------------------------------------------------
-- Payload
----------------------------------------------------------------------
function Companion:BuildPayload()
    local guildName = GetGuildInfo("player")
    if not guildName then return nil, "not in a guild" end
    local realm = GetRealmName()

    local members, count = {}, 0
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local fullName, rankName, rankIndex, level, _, _, _, _, _, _, classFile =
            GetGuildRosterInfo(i)
        if fullName then
            local short = fullName:match("^([^-]+)") or fullName
            local memberRealm = fullName:match("-(.+)$") or realm
            local key = BRutus:GetPlayerKey(short, memberRealm)
            local data = BRutus.db.members[key]

            -- Everybody on the guild roster, including whoever has never published.
            --
            -- This used to send only clients that had synced, and the reason was
            -- sound: a row built from the guild roster alone carries a level and a
            -- class and nothing the site cannot already guess, and it would look
            -- confirmed while being nothing of the sort.
            --
            -- What that cost only became visible against real data. One guild
            -- published 34 members and 48 different people were recorded raiding,
            -- overlapping by five — and the site had no way to tell "our member who
            -- has not installed it" from "somebody who is not in the guild". Those
            -- are different conversations, and both were invisible.
            --
            -- `lastUpdate = 0` carries it, the same trick as `snapshots = 0`: a value
            -- that already exists saying one more thing, with no field of its own.
            -- The site marks those rows, and that mark is the condition for sending
            -- them at all — without it this recreates exactly what the filter avoided.

            -- Nothing published means no record at all, so everything below reads
            -- through an empty table rather than guarding each field.
            data = data or {}
            count = count + 1
            local att = BRutus.RaidTracker
                and BRutus.RaidTracker:GetAttendance25ManPercent(key) or 0

            members[count] = {
                key = key,
                -- Name, class, level and rank come from the guild roster, so they are
                -- known for everybody. Everything after them comes from the person's
                -- own client and is absent until it has spoken.
                name = short,
                class = classFile or "",
                race = data.race or "",
                level = level or 0,
                rank = rankName or "",
                rankIndex = rankIndex or 0,
                avgIlvl = math.floor(tonumber(data.avgIlvl) or 0),
                lastUpdate = math.floor(tonumber(data.lastUpdate) or 0),
                spec = data.spec,
                prefRoles = data.prefRoles or {},
                professions = professionsFor(data),
                attunements = attunementsFor(key),
                att25 = tonumber(att) or 0,
                enchants = enchantSummary(data.gear),
            }
        end
    end

    local loot = {}
    if BRutus.LootTracker then
        for _, e in ipairs(BRutus.LootTracker:GetHistory(500) or {}) do
            -- The history stores an item link, not an id; the site wants the id
            -- so it can build its own tooltip link.
            local itemId = tonumber(e.itemId or (e.itemLink and e.itemLink:match("item:(%d+)"))) or 0
            loot[#loot + 1] = {
                playerKey = e.playerKey or "",
                player = e.player or "",
                itemId = itemId,
                itemName = e.itemName or "",
                quality = tonumber(e.quality) or 0,
                timestamp = math.floor(tonumber(e.timestamp) or 0),
                raid = e.raid or "",
            }
        end
    end

    local sessions, deletedSessions = raidSessions()

    return {
        fmt = FMT,
        v = PAYLOAD_VERSION,
        guildKey = guildName .. "-" .. realm,
        guildName = guildName,
        realm = realm,
        exportedAt = math.floor(time()),
        exportedBy = BRutus:GetPlayerKey(UnitName("player")),
        addonVersion = BRutus.VERSION or "0",
        count = count,
        members = members,
        loot = loot,
        sessions = sessions,
        deletedSessions = deletedSessions,
        attendanceRules = attendanceRules(sessions),
    }
end

----------------------------------------------------------------------
-- The string a person copies
----------------------------------------------------------------------
function Companion:Build()
    if not self:IsEnabled() then return nil, "the web companion is off" end

    local payload, err = self:BuildPayload()
    if not payload then return nil, err end
    if payload.count == 0 then
        return nil, "nobody in the guild has shared anything yet"
    end

    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    if not LibDeflate then return nil, "LibDeflate not available" end

    local json = encode(payload)
    local compressed = LibDeflate:CompressDeflate(json, { level = 9 })
    if not compressed then return nil, "compression failed" end

    return WIRE_PREFIX .. LibDeflate:EncodeForPrint(compressed), payload.count
end

----------------------------------------------------------------------
-- What the desktop companion reads
--
-- WoW flushes SavedVariables on logout and on /reload, and at no other
-- moment, so this is the only place a file on disk can come from. The
-- desktop companion watches that file and uploads what it finds, which is
-- the whole point: nobody has to remember to copy a string on raid night.
--
-- The build is wrapped. A payload that fails on the way out must never be
-- the reason someone's client hangs on logout.
----------------------------------------------------------------------
local writer = CreateFrame("Frame")
writer:RegisterEvent("PLAYER_LOGOUT")
writer:SetScript("OnEvent", function()
    if not GuildOSDB or not Companion:IsEnabled() then return end

    local ok, text = pcall(Companion.Build, Companion)
    -- Build answers nil for the ordinary cases as well — logged out on a
    -- guildless alt, nobody has published anything yet. Keeping the previous
    -- string beats replacing a good payload with nothing.
    if ok and type(text) == "string" then
        GuildOSDB.__companion = text
        -- When the addon WROTE it. Not when it was delivered: the companion
        -- does that and never reports back, so the Web panel can only ever
        -- say "last written".
        GuildOSDB.__companionAt = time()
    end
end)
