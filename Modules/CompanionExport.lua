----------------------------------------------------------------------
-- Guild OS - Companion Export
--
-- Emits a compact, versioned JSON projection of the guild data that the
-- web companion needs (roster + spec + attunements + attendance + loot),
-- encoded as a print-safe "GOSCOMP1:" string. A desktop companion app
-- reads it out of the SavedVariables file and POSTs it to the web API;
-- the same string can be pasted by hand when no companion is installed.
--
-- WHY A JSON PROJECTION AND NOT THE Backup.lua BLOB: Backup:Export()
-- serializes the WHOLE db with LibSerialize (a Lua-specific binary
-- format), so decoding it off-game means porting LibSerialize. This ships
-- ONLY the fields the web needs, as JSON, so the server just inflates and
-- JSON.parses — no LibSerialize decoder anywhere. The outer layers
-- (CompressDeflate + EncodeForPrint) mirror Backup so the payload sits
-- cleanly inside a .lua string literal (no quotes/backslashes to escape).
--
-- WHY THE PAYLOAD LIVES IN SavedVariables: a WoW addon has no file-write
-- API; SavedVariables is the only channel and the client flushes it only
-- on logout / reload. So we stamp GuildOSDB.__companion on PLAYER_LOGOUT
-- (the last event before the flush), and :SyncNow() forces an on-demand
-- flush with ReloadUI() (the same call Backup:Import already uses).
----------------------------------------------------------------------
local CompanionExport = {}
BRutus.CompanionExport = CompanionExport
local L = BRutus.L

local LibDeflate = LibStub("LibDeflate")

local PREFIX = "GOSCOMP1:"   -- format/version tag; server strips this before decoding
local FORMAT_VERSION = 1
-- Where the encoded payload is parked inside the SavedVariables global.
-- Double-underscore keeps it out of the way of the per-guild keys that
-- share GuildOSDB (same convention as the _migrated / _dbVersion meta keys).
local SAVED_SLOT = "__companion"

-- Presence detection: the companion app writes a heartbeat global from a
-- side addon (GuildOS_Companion/Heartbeat.lua) that the client loads at
-- login/reload. Because the WoW client and the companion run on the SAME
-- PC, the heartbeat epoch and time() share one wall clock, so freshness is
-- an exact comparison (no clock skew). The global only refreshes on load,
-- so this reports "active as of the last login/reload", not live state.
local HEARTBEAT_GLOBAL = "GuildOSCompanionLink"
local FRESH_WINDOW = 900   -- seconds; heartbeat within this at load => "connected"

----------------------------------------------------------------------
-- Minimal JSON encoder.
--
-- We own every field we feed it, so it only needs strings, numbers,
-- booleans and tables. Arrays vs objects are disambiguated by key shape
-- (contiguous 1..n integer keys => array). Every object in the projection
-- is always non-empty, so the empty-table => "[]" fallback never produces
-- a wrong shape.
----------------------------------------------------------------------
local ESCAPES = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
    ['\r'] = '\\r', ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
}

local function encStr(s)
    s = tostring(s):gsub('[%z\1-\31\\"]', function(c)
        return ESCAPES[c] or string.format('\\u%04x', c:byte())
    end)
    return '"' .. s .. '"'
end

local function encode(v)
    local t = type(v)
    if t == "string" then
        return encStr(v)
    elseif t == "number" then
        -- Guard NaN/inf (invalid JSON); %.14g round-trips doubles and keeps
        -- epoch timestamps and item levels in plain (non-scientific) form.
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return string.format("%.14g", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        local n = #v
        local count, isArray = 0, true
        for k in pairs(v) do
            count = count + 1
            if type(k) ~= "number" then isArray = false end
        end
        if isArray and count == n then
            local parts = {}
            for i = 1, n do parts[i] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, val in pairs(v) do
            parts[#parts + 1] = encStr(tostring(k)) .. ":" .. encode(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

----------------------------------------------------------------------
-- Build the name-realm -> {rank, rankIndex} map from the LIVE guild
-- roster. Rank is never stored in db.members (it comes from the roster,
-- see Core/Utils.lua:GetMemberRecord), so the web needs it from here to
-- decide officer status via rankIndex <= officerMaxRank.
----------------------------------------------------------------------
local function buildRankMap(realm)
    local map = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, rankIndex = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local rlm = name:match("%-(.+)$") or realm
            map[BRutus:GetPlayerKey(short, rlm)] = {
                rank = rankName or "",
                rankIndex = rankIndex or 99,
            }
        end
    end
    return map
end

local function projectSpec(spec)
    if not spec then return nil end
    return {
        tree = spec.tree or "Unknown",
        treeIndex = spec.treeIndex or 0,
        points = spec.points or {},   -- e.g. {8,42,3}
    }
end

local function projectAttunements(key)
    local out = {}
    local AT = BRutus.AttunementTracker
    if not AT or not AT.GetEffectiveAttunements then return out end
    local ok, list = pcall(function() return AT:GetEffectiveAttunements(key) end)
    if not ok or type(list) ~= "table" then return out end
    for _, a in ipairs(list) do
        if a.short and not a.alwaysComplete then
            out[#out + 1] = {
                short = a.short,
                complete = a.complete and true or false,
                progress = tonumber(a.progress) or 0,
            }
        end
    end
    return out
end

local function projectProfessions(profs)
    local out = {}
    for _, p in ipairs(profs or {}) do
        if p.name and p.name ~= "" then
            out[#out + 1] = { name = p.name, rank = tonumber(p.rank) or 0 }
        end
    end
    return out
end

local function attendancePct(key)
    local RT = BRutus.RaidTracker
    if not RT or not RT.GetAttendance25ManPercent then return 0 end
    local ok, pct = pcall(function() return RT:GetAttendance25ManPercent(key) end)
    return (ok and tonumber(pct)) or 0
end

local function projectMember(key, d, rankInfo)
    d = d or {}
    return {
        key = key,
        name = d.name or (key:match("^([^-]+)")) or key,
        class = d.class or "",
        level = d.level or 0,
        race = d.race or "",
        rank = rankInfo and rankInfo.rank or nil,
        rankIndex = rankInfo and rankInfo.rankIndex or nil,
        avgIlvl = d.avgIlvl or 0,
        lastUpdate = d.lastUpdate or 0,
        spec = projectSpec(d.spec),
        prefRoles = d.prefRoles,            -- passed through; web normalizes
        professions = projectProfessions(d.professions),
        attunements = projectAttunements(key),
        att25 = attendancePct(key),         -- 25-man attendance %, 0..100
    }
end

local function projectLoot(history)
    local out = {}
    for _, e in ipairs(history or {}) do
        local itemId = e.itemLink and tonumber(e.itemLink:match("item:(%d+)")) or e.itemId
        out[#out + 1] = {
            playerKey = e.playerKey or "",
            player = e.player or "",
            itemId = itemId or 0,
            itemName = e.itemName or (e.itemLink and GetItemInfo(e.itemLink)) or "",
            quality = tonumber(e.quality) or 0,
            timestamp = e.timestamp or 0,
            raid = e.raid or "",
        }
    end
    return out
end

----------------------------------------------------------------------
-- Build the full projection table (pre-JSON).
----------------------------------------------------------------------
function CompanionExport:BuildProjection()
    local db = BRutus.db
    if not db then return nil end

    local realm = GetRealmName()
    local guildName = (GetGuildInfo("player")) or ""
    local me = BRutus:GetPlayerKey(UnitName("player"), realm)

    local proj = {
        fmt = "GOSCOMP1",
        v = FORMAT_VERSION,
        guildKey = BRutus.guildKey or (guildName .. "-" .. realm),
        guildName = guildName,
        realm = realm,
        exportedAt = GetServerTime(),
        exportedBy = me,
        addonVersion = BRutus.VERSION or GuildOS.VERSION or "",
        members = {},
        loot = projectLoot(db.lootHistory),
    }

    local members = db.members or {}
    local rankMap = buildRankMap(realm)
    local n = GetNumGuildMembers() or 0

    if n > 0 then
        -- Primary path: one row per CURRENT guild member (mirrors
        -- BRutus:ExportRoster), so ex-members are never leaked and rank is
        -- always present.
        local seen = {}
        for i = 1, n do
            local name = GetGuildRosterInfo(i)
            if name then
                local short = name:match("^([^-]+)") or name
                local rlm = name:match("%-(.+)$") or realm
                local key = BRutus:GetPlayerKey(short, rlm)
                if not seen[key] then
                    seen[key] = true
                    proj.members[#proj.members + 1] =
                        projectMember(key, members[key], rankMap[key])
                end
            end
        end
    else
        -- Roster not loaded (e.g. exporting offline): fall back to every
        -- member we have cached data for; rank stays nil.
        for key, d in pairs(members) do
            proj.members[#proj.members + 1] = projectMember(key, d, rankMap[key])
        end
    end

    proj.count = #proj.members
    return proj
end

----------------------------------------------------------------------
-- Encode the projection to the print-safe "GOSCOMP1:" string.
----------------------------------------------------------------------
function CompanionExport:Export()
    local proj = self:BuildProjection()
    if not proj then return nil end
    local ok, json = pcall(encode, proj)
    if not ok or type(json) ~= "string" then return nil end
    local compressed = LibDeflate:CompressDeflate(json)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return PREFIX .. encoded
end

----------------------------------------------------------------------
-- Park the encoded payload in SavedVariables so the companion picks it up
-- on the next flush. pcall-wrapped: a projection bug must never block a
-- logout or a reload.
----------------------------------------------------------------------
function CompanionExport:WriteToSaved()
    if not GuildOSDB then return false end
    local ok, str = pcall(function() return self:Export() end)
    if not ok or not str then return false end
    GuildOSDB[SAVED_SLOT] = str
    return true
end

----------------------------------------------------------------------
-- On-demand sync: stamp the payload, then force the SavedVariables flush
-- with a reload so the companion sees the change within seconds instead
-- of waiting for logout. (Never call this mid-pull — a reload drops you
-- from combat and flashes a loading screen.)
----------------------------------------------------------------------
function CompanionExport:SyncNow()
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Web sync is available to officers only.|r"])
        return
    end
    self:WriteToSaved()
    BRutus:Print(L["Web sync: reloading to flush data to the companion..."])
    ReloadUI()
end

----------------------------------------------------------------------
-- Show the payload in a copy box for manual paste (no companion / no
-- reload). Same popup Backup uses.
----------------------------------------------------------------------
function CompanionExport:ShowExport()
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Web sync is available to officers only.|r"])
        return
    end
    local str = self:Export()
    if not str then
        BRutus:Print(L["|cffFF4444Web export failed.|r"])
        return
    end
    BRutus:ShowExportPopup(L["Guild OS Web Sync"], str)
end

----------------------------------------------------------------------
-- Report whether the companion app looks active, based on the heartbeat
-- global it writes. Returns a table:
--   { present = bool, fresh = bool, ageSecs = number, lastSeen = epoch,
--     appVersion = string }
-- `present` = the side addon is installed and wrote a heartbeat at all.
-- `fresh`   = that heartbeat is recent (companion was running at load).
----------------------------------------------------------------------
function CompanionExport:GetCompanionStatus()
    local link = _G[HEARTBEAT_GLOBAL]
    if type(link) ~= "table" or not tonumber(link.heartbeat) then
        return { present = false, fresh = false }
    end
    local age = time() - tonumber(link.heartbeat)
    return {
        present = true,
        -- Small negative tolerance guards a companion write a few seconds
        -- ahead of the client clock at load.
        fresh = (age >= -60) and (age <= FRESH_WINDOW),
        ageSecs = age,
        lastSeen = tonumber(link.heartbeat),
        appVersion = link.app,
    }
end

----------------------------------------------------------------------
-- Register the logout hook. Fires on true logout AND on every /reload
-- (reload raises PLAYER_LOGOUT too), so a fresh payload is always written
-- just before the SavedVariables flush.
----------------------------------------------------------------------
function CompanionExport:Initialize()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        CompanionExport:WriteToSaved()
    end)
    self._frame = f
end
