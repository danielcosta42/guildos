----------------------------------------------------------------------
-- Guild OS - Journal (issue #205, guildos.me specs/061)
--
-- What happened to this character, written down by this character's own client at the
-- moment it happened: a level milestone, the cap, a dungeon cleared. Each client keeps the
-- whole guild's journal as it arrives by sync, and the companion export carries it to
-- guildos.me (payload v12), which turns it into the guild's feed.
--
-- Nobody writes another person's journal. An entry is taken only from its subject — the
-- sender of the envelope — because on WoW: Forever the identity of other players can be
-- secret, and a client may only ever speak for itself.
--
-- WoW: Forever only: the feed is a Forever feature (guildos.me #238).
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local Journal = {}
GuildOS.Journal = Journal

local Compat = GuildOS.Compat

local MAX = 1000                  -- entries kept, the whole guild's
local KEEP = 30 * 86400           -- and for this long
local SNAP = 7 * 86400            -- my own, republished at login for whoever was offline
local SNAP_DELAY = 30             -- seconds after login: the guild channel is up by then
local SKEW = 600                  -- a sender's clock a little ahead is a clock, not a lie
local BOSSES_MAX = 20
local MILESTONES = { [10] = true, [20] = true, [30] = true, [40] = true, [50] = true }
local TYPES = { ["member.level"] = true, ["member.level60"] = true, ["dungeon.clear"] = true }

local function myKey()
    return GuildOS:GetPlayerKey(Compat.PlayerName())
end

-- The key a sync envelope's sender has, built the way CoreManager files a sign-up (#97).
local function senderKey(sender)
    local short = sender:match("^([^-]+)") or sender
    return GuildOS:GetPlayerKey(short, sender:match("-(.+)$"))
end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

-- An entry that makes sense, whoever wrote it.
local function valid(e, now)
    if type(e) ~= "table" or type(e.id) ~= "string" or e.id == "" or #e.id > 200 then return false end
    if type(e.subjectKey) ~= "string" or e.subjectKey == "" then return false end
    if type(e.at) ~= "number" or e.at <= 0 or e.at > now + SKEW or e.at < now - KEEP then return false end
    if not TYPES[e.type] or type(e.data) ~= "table" then return false end
    local d = e.data
    if e.type == "member.level" then return isInt(d.level, 1, GuildOS.Client.maxLevel) end
    if e.type == "dungeon.clear" then
        return type(d.dungeonId) == "string" and d.dungeonId ~= "" and type(d.runId) == "string" and d.runId ~= ""
            and isInt(d.bosses, 0, BOSSES_MAX) and type(d.fullClear) == "boolean"
    end
    return true
end

local function entries()
    return GuildOS.db.journal and GuildOS.db.journal.entries or {}
end

local function has(id)
    for _, e in ipairs(entries()) do
        if e.id == id then return true end
    end
    return false
end

function Journal:Initialize()
    GuildOS.db.journal = GuildOS.db.journal or {}
    GuildOS.db.journal.entries = GuildOS.db.journal.entries or {}
    GuildOS.db.journal.seq = GuildOS.db.journal.seq or 0
    self:Prune(GetServerTime())
    if GuildOS.SyncService then
        GuildOS.SyncService:On("journal", function(env, sender) Journal:OnSync(env, sender) end)
    end
    if not self.frame then
        self.frame = CreateFrame("Frame")
        Compat.RegisterEvent(self.frame, "PLAYER_LEVEL_UP")
        self.frame:SetScript("OnEvent", function(_, _, level) Journal:OnLevelUp(level) end)
    end
    Compat.After(SNAP_DELAY, function() Journal:Snap() end)
end

-- Oldest out first: past 30 days, then past 1,000.
function Journal:Prune(now)
    local list = entries()
    local kept = {}
    for _, e in ipairs(list) do
        if (e.at or 0) >= now - KEEP then kept[#kept + 1] = e end
    end
    table.sort(kept, function(a, b) return a.at < b.at end)
    while #kept > MAX do table.remove(kept, 1) end
    if GuildOS.db.journal then GuildOS.db.journal.entries = kept end
end

-- Write down something that happened to me, keep it and tell the guild. Returns the entry.
function Journal:Add(etype, data)
    if not GuildOS.db.journal then return nil end
    local key = myKey()
    if not key then return nil end
    local now = GetServerTime()
    GuildOS.db.journal.seq = GuildOS.db.journal.seq + 1
    local e = { id = key .. ":" .. GuildOS.db.journal.seq, subjectKey = key, at = now, type = etype, data = data }
    if not valid(e, now) then return nil end
    table.insert(GuildOS.db.journal.entries, e)
    self:Prune(now)
    if GuildOS.SyncService then GuildOS.SyncService:Publish("journal", "add", { entry = e }) end
    return e
end

-- What is kept of an entry that makes sense: the fields its type has, nothing else (a name rides
-- nowhere: the roster names people), and the subject's key in this client's shape. On WoW: Forever
-- each client answers its own realm name (#95), and a key built by another one carries it (#97).
local function keptOf(e)
    local d, data = e.data, {}
    if e.type == "member.level" then
        data.level = d.level
    elseif e.type == "dungeon.clear" then
        data.dungeonId, data.runId, data.bosses, data.fullClear = d.dungeonId, d.runId, d.bosses, d.fullClear
        if type(d.dungeonName) == "string" then data.dungeonName = d.dungeonName:sub(1, 100) end
    end
    return { id = e.id, subjectKey = GuildOS:LocalMemberKey(e.subjectKey), at = e.at, type = e.type, data = data }
end

-- Entries from the guild: only the sender's own, only ones that make sense, each once.
function Journal:OnSync(env, sender)
    if type(sender) ~= "string" or sender == "" or type(env.data) ~= "table" then return end
    local list = env.act == "add" and { env.data.entry } or env.act == "snap" and env.data.entries
    if type(list) ~= "table" then return end
    local who, now, added = senderKey(sender), GetServerTime(), false
    for _, e in ipairs(list) do
        if valid(e, now) and not has(e.id) then
            local kept = keptOf(e)
            if kept.subjectKey == who then
                table.insert(GuildOS.db.journal.entries, kept)
                added = true
            end
        end
    end
    if added then self:Prune(now) end
end

-- My own entries of the last week, again, for whoever was offline when they happened.
function Journal:Snap()
    local key, since, mine = myKey(), GetServerTime() - SNAP, {}
    for _, e in ipairs(entries()) do
        if GuildOS:LocalMemberKey(e.subjectKey) == key and e.at >= since then mine[#mine + 1] = e end
    end
    if #mine > 0 and GuildOS.SyncService then GuildOS.SyncService:Publish("journal", "snap", { entries = mine }) end
end

function Journal:OnLevelUp(level)
    level = tonumber(level)
    if not level then return end
    if level == GuildOS.Client.maxLevel then
        self:Add("member.level60", {})
    elseif MILESTONES[level] then
        self:Add("member.level", { level = level })
    end
end

-- Everything after `ts`, oldest first.
function Journal:GetSince(ts)
    local out = {}
    for _, e in ipairs(entries()) do
        if e.at > (ts or 0) then out[#out + 1] = e end
    end
    return out
end

-- What the companion export carries (payload v12): the whole journal this client holds.
function Journal:ForExport()
    local out = {}
    for _, e in ipairs(entries()) do
        out[#out + 1] = { id = e.id, subjectKey = e.subjectKey, at = e.at, type = e.type, data = e.data }
    end
    return out
end

----------------------------------------------------------------------
-- Not named on Discord (guildos.me #247): the member's own choice, carried by the member
-- broadcast like the roles they play, and in the export as `feedOptOut`.
----------------------------------------------------------------------
function Journal:IsOptedOut()
    return GuildOS.db.profile ~= nil and GuildOS.db.profile.feedOptOut == true
end

function Journal:SetOptedOut(on)
    GuildOS.db.profile = GuildOS.db.profile or {}
    GuildOS.db.profile.feedOptOut = on and true or nil
    local key = myKey()
    if key then
        GuildOS.db.members = GuildOS.db.members or {}
        GuildOS.db.members[key] = GuildOS.db.members[key] or {}
        GuildOS.db.members[key].feedOptOut = on and true or false
    end
    if GuildOS.CommSystem and GuildOS.CommSystem.BroadcastMyData then
        GuildOS.CommSystem:BroadcastMyData(true)
    end
end
