----------------------------------------------------------------------
-- Guild OS - Groups being formed (issue #341)
-- A leader lists a group: the activity, the open spots by role, a note and for how long. A member
-- asks for a spot, in a role, and only the leader hears it. A listing is always keyed by the comm
-- envelope sender, so nobody publishes, changes or takes down somebody else's group.
--
-- Who is looking stays Modules/LFGBoard.lua; the tab that draws both is UI/GroupsPanel.lua.
-- Listings are saved (a /reload keeps the board); requests live for the session only.
----------------------------------------------------------------------
local Groups = {}
GuildOS.Groups = Groups
local L = GuildOS.L
local LibSerialize = LibStub("GuildOS-LibSerialize")

local NOTE_MAX       = 60
local SIZE_MAX       = 40    -- the largest group the game forms
local SIZE_DEFAULT   = 5
local REQUESTS_MAX   = 20    -- requests a leader keeps; the rest are declined
local GROUP_COOLDOWN = 5     -- accept at most one listing per sender per 5s
local JOIN_COOLDOWN  = 2     -- and one request per sender per 2s
local ASK_EVERY      = 3     -- so an asker never sends two requests inside the cooldown above
local PUBLISH_EVERY  = 6     -- so a leader never sends two inside the cooldown above
local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }

Groups.REQUESTS_MAX = REQUESTS_MAX

local function board() return GuildOS.LFGBoard end
local function myKey() return board():MyKey() end

-- Session only: who asked me, whom I asked, and the cooldowns.
local function state()
    local s = GuildOS.State.groups
    if not s then
        s = { requests = {}, asked = {}, askedAt = {}, askPending = {}, groupCd = {}, joinCd = {}, lastPublish = 0 }
        GuildOS.State.groups = s
    end
    return s
end

function Groups:Initialize()
    GuildOS.db.lfgGroups = GuildOS.db.lfgGroups or {}
    state()
    self:Prune()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(self.frame, "GROUP_ROSTER_UPDATE")
        self.frame:SetScript("OnEvent", function() GuildOS:SafeCall(Groups.OnGroupRoster, Groups) end)
    end
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------------
local function clampInt(v, lo, hi, default)
    local n = GuildOS.Finite(v)
    if not n then return default end
    n = math.floor(n)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- The size a group for this activity fills to: the catalogue's, or a party's.
function Groups:SizeOf(act)
    local cat = GuildOS.GroupActivities
    local it = cat and cat.byId[act]
    return (it and it.size) or SIZE_DEFAULT
end

-- The open spots of a listing: a whole number per role, and never more in all than `room`, the
-- places a group of that size has besides its leader. Spots past the room are cut from the last role
-- back, so the same input gives the same answer on every client.
function Groups:_SanitizeNeed(need, room)
    local out, left = {}, math.max(0, room or (SIZE_MAX - 1))
    for _, k in ipairs(LETTERS) do
        local n = clampInt(type(need) == "table" and need[k] or nil, 0, SIZE_MAX - 1, 0)
        if n > left then n = left end
        out[k] = n
        left = left - n
    end
    return out
end

function Groups:OpenSpots(need)
    local n = 0
    for _, k in ipairs(LETTERS) do n = n + ((need and need[k]) or 0) end
    return n
end

-- A received payload as the listing we store, plus the age it claimed, or nil when it names no
-- activity. Age only ever moves the start backwards, as on the board (#243): a listing answered
-- again at a login keeps its deadline.
function Groups:_BuildGroup(p, now)
    local B = board()
    local act = B:_SanitizeAct(p and p.act)
    if not act then return nil end
    now = now or 0
    local ttl = B:_ClampTtl(p.ttl)
    local age = GuildOS.Finite(p.age) or 0
    if age < 0 then age = 0 end
    if age > ttl then age = ttl end
    local max = clampInt(p.max, 2, SIZE_MAX, self:SizeOf(act))
    return {
        act = act,
        note = GuildOS:SanitizeUserText(p.note, NOTE_MAX),
        need = self:_SanitizeNeed(p.need, max - 1),
        n = clampInt(p.n, 1, max, 1),
        max = max,
        ts = now - age,
        ttl = ttl,
    }, age
end

function Groups:Prune(now, store)
    store = store or (GuildOS.db and GuildOS.db.lfgGroups)
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for k, g in pairs(store) do
        if not board():_IsActive(g, now) then store[k] = nil; removed = removed + 1 end
    end
    -- A request never outlives the listing it was for: an expiry sends no word, so both ends drop
    -- theirs here (only for the saved store, which is the one they were made against).
    if store == (GuildOS.db and GuildOS.db.lfgGroups) then
        local s = state()
        for key in pairs(s.asked) do
            if not store[key] then s.asked[key] = nil end
        end
        if not store[myKey()] then
            for key in pairs(s.requests) do s.requests[key] = nil end
        end
    end
    return removed
end

-- The groups being formed, newest first. onlineSet (optional): { [key] = true } of members online;
-- a leader who logged off cannot invite anybody.
function Groups:ActiveList(store, now, onlineSet)
    local out = {}
    for key, g in pairs(store or {}) do
        if board():_IsActive(g, now) and (not onlineSet or onlineSet[key]) then
            out[#out + 1] = {
                key = key, name = key:match("^([^-]+)") or key, from = g.from,
                act = g.act, note = g.note or "", need = g.need or {}, n = g.n or 1, max = g.max or SIZE_DEFAULT,
                ts = g.ts, ttl = g.ttl,
            }
        end
    end
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return a.key < b.key
    end)
    return out
end

-- How many groups and how many players each activity has, for the tiles: { [act] = { groups, seekers } }.
function Groups:Counts(now, onlineSet, groupStore, seekerStore)
    local out = {}
    local function at(act)
        out[act] = out[act] or { groups = 0, seekers = 0 }
        return out[act]
    end
    for _, g in ipairs(self:ActiveList(groupStore or GuildOS.db.lfgGroups, now, onlineSet)) do
        at(g.act).groups = at(g.act).groups + 1
    end
    for _, e in ipairs(board():ActiveList(seekerStore or GuildOS.db.lfgBoard, now, onlineSet)) do
        for _, act in ipairs(e.acts) do at(act).seekers = at(act).seekers + 1 end
    end
    return out
end

-- "1 Tank, 2 DPS": the open spots in words, for a chat line.
function Groups:NeedText(need)
    local parts = {}
    for _, k in ipairs(LETTERS) do
        local n = (need and need[k]) or 0
        if n > 0 then parts[#parts + 1] = string.format("%d %s", n, board():RoleName(ROLE_OF[k])) end
    end
    return table.concat(parts, ", ")
end

-- Per-sender cooldown, self-clearing (as LFGBoard:_RateLimited, with a store and a window of its own:
-- a leader's listing and the same leader's own availability are two messages a moment apart).
local function rateLimited(store, sender, seconds, schedule)
    if not sender or store[sender] then return true end
    store[sender] = true
    local after = schedule or GuildOS.Compat.After
    after(seconds, function() store[sender] = nil end)
    return false
end
Groups._RateLimited = rateLimited

local function keyOf(sender)
    local short = sender:match("^([^-]+)") or sender
    return GuildOS:GetPlayerKey(short, sender:match("-(.+)$") or GetRealmName()), short
end

----------------------------------------------------------------------
-- My group
----------------------------------------------------------------------
function Groups:Mine()
    local store = GuildOS.db and GuildOS.db.lfgGroups
    local g = store and store[myKey()]
    return board():_IsActive(g, GetServerTime()) and g or nil
end

local function send(payload, target)
    if not GuildOS.CommSystem then return end
    local types = GuildOS.CommSystem.MSG_TYPES
    -- A listing goes out at NORMAL, not the guild channel's default BULK: behind a queue of bulk sync
    -- two of them would leave back to back, and a receiver's cooldown would drop the second.
    GuildOS.CommSystem:SendMessage(target and types.LFG_JOIN or types.LFG_GROUP, LibSerialize:Serialize(payload),
        target, "NORMAL")
end

local function payloadOf(g, now)
    local age = now - g.ts
    if age < 0 then age = 0 end
    return { act = g.act, note = g.note, need = g.need, n = g.n, max = g.max, ttl = g.ttl, age = age }
end

-- Say what my group is now, or that it is gone. At most one every PUBLISH_EVERY seconds: a second
-- change inside the window waits for it and goes out once, with whatever is true by then, so a
-- receiver's cooldown never drops the last word.
function Groups:_Publish()
    local s = state()
    local now = GetTime()
    local wait = PUBLISH_EVERY - (now - s.lastPublish)
    if wait > 0 then
        if not s.publishPending then
            s.publishPending = true
            GuildOS.Compat.After(wait, function()
                s.publishPending = false
                Groups:_Publish()
            end)
        end
        return false
    end
    s.lastPublish = now
    local g = self:Mine()
    send(g and payloadOf(g, GetServerTime()) or { clear = true })
    return true
end

-- List my group, or change the one I have. Returns the stored listing, or nil and why not.
-- `toGuild` is the composer's box, as on the board: one line in guild chat, five minutes apart.
function Groups:Create(act, need, note, ttl, toGuild)
    local B = board()
    act = B:_SanitizeAct(act)
    if not act then return nil, L["Pick what the group is for."] end
    if not GuildOS.Compat.CanInvite() then return nil, L["Only the group's leader can list it."] end
    local _, count = GuildOS.Compat.GroupRoster()
    local max = math.max(self:SizeOf(act), math.min(count, SIZE_MAX))
    need = self:_SanitizeNeed(need, max - count)
    if self:OpenSpots(need) == 0 then return nil, L["A group needs at least one open spot."] end
    ttl = B:_ClampTtl(ttl or GuildOS.db.lfgPrefs.lastTtl)
    local g = {
        act = act, note = GuildOS:SanitizeUserText(note, NOTE_MAX), need = need,
        n = count, max = max, ts = GetServerTime(), ttl = ttl,
    }
    -- Whoever asked for a spot asked for the group that was listed: another activity is another group.
    local was = self:Mine()
    if not was or was.act ~= act then self:_CloseQueue() end
    GuildOS.db.lfgGroups[myKey()] = g
    GuildOS.db.lfgPrefs.lastTtl = ttl
    -- Whoever forms a group is not looking for one, nor waiting on somebody else's.
    if B:AmAvailable() then B:ClearAvailable() end
    local waiting = {}
    for key in pairs(state().asked) do waiting[#waiting + 1] = key end
    for _, key in ipairs(waiting) do self:CancelRequest(key) end
    if toGuild then
        local name, spots = B:ActivityName(act), self:NeedText(need)
        local line = string.format(L["[Guild OS] Group for %s, looking for %s"], name, spots)
        if g.note ~= "" then line = line .. ": " .. g.note end
        B:_SayInGuild(nil, nil, nil, line)
    end
    self:_Publish()
    B:Refresh()
    return g
end

-- Empty my queue. Whoever was waiting is told the group closed, which is not a refusal.
function Groups:_CloseQueue()
    local s = state()
    for key, r in pairs(s.requests) do
        send({ decline = true, closed = true }, r.from)
        s.requests[key] = nil
    end
end

-- Take my listing down.
function Groups:Disband()
    local store = GuildOS.db.lfgGroups
    if not store[myKey()] then return false end
    store[myKey()] = nil
    self:_CloseQueue()
    self:_Publish()
    board():Refresh()
    return true
end

-- Answer a login's request with my live listing, at its real age (CommSystem:HandleRequest).
function Groups:Rebroadcast()
    if not self:Mine() then return false end
    return self:_Publish()
end

-- Incoming listing: the key ALWAYS comes from the envelope sender, and only over GUILD, where the
-- sender is a guildmate by the channel itself.
function Groups:HandleGroup(sender, data, channel)
    if not sender or channel ~= "GUILD" then return end
    local key, short = keyOf(sender)
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local store = GuildOS.db.lfgGroups
    local now = GetServerTime()
    if p.clear then
        -- Taking down a listing we hold is heard whatever the cooldown says: it happens once a
        -- listing, and the one dropped would leave a dead group up for as long as its leader plays.
        if not store[key] then return end
        store[key] = nil
        state().asked[key] = nil
    else
        if rateLimited(state().groupCd, short, GROUP_COOLDOWN) then return end
        local was = store[key]
        local wasActive = board():_IsActive(was, now)
        local g, age = self:_BuildGroup(p, now)
        if not g then return end
        g.from = sender
        store[key] = g
        -- What I asked, I asked of the group that was listed.
        if not wasActive or was.act ~= g.act then state().asked[key] = nil end
        local prefs = GuildOS.db.lfgPrefs
        if age == 0 and not wasActive and prefs and prefs.notify and key ~= myKey() then
            GuildOS:Print(string.format(L["%s is forming a group for %s."], short, board():ActivityName(g.act)))
        end
    end
    board():Refresh()
end

----------------------------------------------------------------------
-- Asking for a spot (the asker's side)
----------------------------------------------------------------------
-- What I asked of this leader: nil, or { role, state = "pending" | "declined" }.
function Groups:Asked(leaderKey) return state().asked[leaderKey] end

function Groups:RequestSpot(leaderKey, role)
    local g = GuildOS.db.lfgGroups[leaderKey]
    if not board():_IsActive(g, GetServerTime()) or leaderKey == myKey() then return false end
    if not ROLE_OF[role] or (g.need[role] or 0) < 1 or not g.from then return false end
    state().asked[leaderKey] = { role = role, state = "pending" }
    self:_SendAsk(leaderKey)
    board():Refresh()
    return true
end

-- Tell a leader what I ask of them now. A leader takes one request a sender every JOIN_COOLDOWN
-- seconds, so a second one inside ASK_EVERY waits and goes out once, if I am still asking by then.
function Groups:_SendAsk(leaderKey)
    local s = state()
    local wait = ASK_EVERY - (GetTime() - (s.askedAt[leaderKey] or -ASK_EVERY))
    if wait > 0 then
        if not s.askPending[leaderKey] then
            s.askPending[leaderKey] = true
            GuildOS.Compat.After(wait, function()
                s.askPending[leaderKey] = nil
                Groups:_SendAsk(leaderKey)
            end)
        end
        return false
    end
    local mine, g = s.asked[leaderKey], GuildOS.db.lfgGroups[leaderKey]
    if not mine or mine.state ~= "pending" or not g or not g.from then return false end
    s.askedAt[leaderKey] = GetTime()
    send({ role = mine.role }, g.from)
    return true
end

function Groups:CancelRequest(leaderKey)
    local s = state()
    local mine = s.asked[leaderKey]
    if not mine then return false end
    s.asked[leaderKey] = nil
    local g = GuildOS.db.lfgGroups[leaderKey]
    if mine.state == "pending" and g and g.from then send({ cancel = true }, g.from) end
    board():Refresh()
    return true
end

----------------------------------------------------------------------
-- The queue (the leader's side)
----------------------------------------------------------------------
-- Who asked for a spot in my group, oldest first.
function Groups:Requests()
    local out = {}
    for _, r in pairs(state().requests) do out[#out + 1] = r end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.key < b.key
    end)
    return out
end

function Groups:Invite(key)
    local r = state().requests[key]
    if not r then return false end
    r.state = "invited"
    GuildOS.Compat.InviteUnit(r.from)
    board():Refresh()
    return true
end

function Groups:Decline(key)
    local s = state()
    local r = s.requests[key]
    if not r then return false end
    s.requests[key] = nil
    send({ decline = true }, r.from)
    board():Refresh()
    return true
end

-- A whisper about a spot. Three things arrive here: a leader's answer to what I asked, an asker
-- taking a request back, and a request for a spot in my group. Never over GUILD (a request is the
-- leader's alone), and a request only from somebody on the guild roster: a whisper can come from
-- anybody. An answer and a take-back change something only when there is a matching entry, once, so
-- neither is held to the cooldown: the one dropped would leave a row that is no longer true.
function Groups:HandleJoin(sender, data, channel)
    if not sender or channel ~= "WHISPER" then return end
    local key, short = keyOf(sender)
    local s = state()
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end

    if p.decline then
        local mine = s.asked[key]
        if not mine then return end
        if p.closed then
            s.asked[key] = nil
        elseif mine.state == "pending" then
            mine.state = "declined"
            GuildOS:Print(string.format(L["%s has no spot for you in this group."], short))
        end
    elseif p.cancel then
        if not s.requests[key] then return end
        s.requests[key] = nil
    else
        -- The whole name, not the short one: a namesake on another realm is not the guildmate (as
        -- issue #78). Then the cooldown, by that key, so nobody else can use up a guildmate's.
        local g = self:Mine()
        if not g or GuildOS:RosterKey(sender) ~= key then return end
        if rateLimited(s.joinCd, key, JOIN_COOLDOWN) then return end
        local role = ROLE_OF[p.role] and p.role or nil
        local known = s.requests[key]
        local count = 0
        for _ in pairs(s.requests) do count = count + 1 end
        if not role or (g.need[role] or 0) < 1 or (not known and count >= REQUESTS_MAX) then
            send({ decline = true }, sender)
            return
        end
        s.requests[key] = { key = key, name = short, from = sender, role = role,
                            at = known and known.at or GetServerTime(), state = "pending" }
        if not known then
            GuildOS:Print(string.format(L["%s asks for a spot in your group as %s."], short,
                board():RoleName(ROLE_OF[role])))
        end
    end
    board():Refresh()
end

----------------------------------------------------------------------
-- The party changed
----------------------------------------------------------------------
-- A player from my queue who is now in my group closes the spot of the role they asked in, and with
-- no spot left the listing comes down. On the other side, joining the group of a leader I asked
-- means I am no longer looking. `members`, `count` are injectable for the self test.
function Groups:OnGroupRoster(members, count)
    if not members then members, count = GuildOS.Compat.GroupRoster() end
    local s = state()
    local changed = false
    local function here(key) return GuildOS.Compat.InGroup(members, key) end

    local g = self:Mine()
    -- A leader who passed the lead can invite nobody: the listing would promise what it cannot do.
    if g and not GuildOS.Compat.CanInvite() then
        self:Disband()
        GuildOS:Print(L["Only the group's leader can list it."])
        g = nil
    end
    if g then
        for key, r in pairs(s.requests) do
            if here(key) then
                if (g.need[r.role] or 0) > 0 then g.need[r.role] = g.need[r.role] - 1 end
                s.requests[key] = nil
                changed = true
            end
        end
        local n = math.min(count, g.max)
        if g.n ~= n then
            g.n, changed = n, true
            -- Somebody invited by hand took a seat: the spots never pass the seats left.
            g.need = self:_SanitizeNeed(g.need, g.max - n)
        end
        if self:OpenSpots(g.need) == 0 or count >= g.max then
            self:Disband()
            GuildOS:Print(L["Your group is complete: the listing came down."])
            changed = false
        elseif changed then
            self:_Publish()
        end
    end

    local joined = false
    for key in pairs(s.asked) do
        if here(key) then joined = true end
    end
    if joined then
        local others = {}
        for key in pairs(s.asked) do
            if here(key) then s.asked[key] = nil else others[#others + 1] = key end
        end
        for _, key in ipairs(others) do self:CancelRequest(key) end
        if board():AmAvailable() then board():ClearAvailable() end
        changed = true
    end
    if changed then board():Refresh() end
end

----------------------------------------------------------------------
-- Self tests (the rest are tools/groups.lua)
----------------------------------------------------------------------
function Groups:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    S:Register("groups.need_is_clamped", function()
        local need = Groups:_SanitizeNeed({ T = 1, H = "2", D = 99 }, 4)
        if need.T ~= 1 or need.H ~= 2 or need.D ~= 1 then return false, "spots past the room must be cut" end
        need = Groups:_SanitizeNeed({ T = -3, H = 0 / 0, D = {} }, 4)
        if Groups:OpenSpots(need) ~= 0 then return false, "junk is no spot" end
        if Groups:OpenSpots(Groups:_SanitizeNeed(nil, 4)) ~= 0 then return false, "nil must not error" end
        return true
    end)
    S:Register("groups.listing_is_sanitised", function()
        if Groups:_BuildGroup({ note = "x" }, 100) then return false, "a listing with no activity is refused" end
        if Groups:_BuildGroup({ act = "|cffEVIL" }, 100) then return false, "an id with an escape is refused" end
        local g, age = Groups:_BuildGroup({ act = "deadmines", note = "|TInterface\\Icons\\X:64|t", ttl = 1e12,
            need = { T = 1, D = 40 }, n = 99, max = 5, age = -5 }, 100)
        if not g or age ~= 0 or g.ts ~= 100 then return false, "a negative age cannot post date a listing" end
        if g.note:find("|", 1, true) then return false, "note escape survived" end
        if g.n ~= 5 or Groups:OpenSpots(g.need) ~= 4 then return false, "size and spots are clamped" end
        if board():_IsActive(g, 100 + 7200) then return false, "a forged ttl must still expire" end
        return true
    end)
    S:Register("groups.catalogue_ids", function()
        local cat = GuildOS.GroupActivities
        if not cat then return false, "catalogue missing" end
        local seen = {}
        for _, s in ipairs(cat.sections) do
            for _, it in ipairs(s.items) do
                if seen[it.id] then return false, "duplicate id " .. it.id end
                seen[it.id] = true
                if board():_SanitizeAct(it.id) ~= it.id then return false, "id would not cross the wire: " .. it.id end
            end
        end
        return true
    end)
end
