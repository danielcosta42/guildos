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
-- "four slots unenchanted" instead of just showing an item level.
local PAYLOAD_VERSION = 2

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

            -- Only members whose own client has published something. A row
            -- built from the guild roster alone would carry a level and a
            -- class and nothing the site cannot already guess, and it would
            -- look confirmed on the site while being nothing of the sort.
            if data and (data.lastUpdate or 0) > 0 then
                count = count + 1
                local att = BRutus.RaidTracker
                    and BRutus.RaidTracker:GetAttendance25ManPercent(key) or 0

                members[count] = {
                    key = key,
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
