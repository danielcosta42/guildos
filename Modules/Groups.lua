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
local ANNOUNCE_EVERY = 600   -- a listed group says it again in guild chat every 10 minutes (#378)
local WHISPER_COOLDOWN = 10  -- one "inv" a sender every 10 s (#378)
local LEVEL_SLACK    = 5     -- levels past an activity's range it still reads as mine (as the tiles)
local PARTY_MAX      = 5
local EXTEND_BY      = 1800  -- "+30 min" on a listing, never past the longest duration (#378)
local WARN_BEFORE    = 300   -- a listing of mine says it is about to end 5 minutes before (#378)
-- What a guildmate with no addon whispers a leader for an invite (#378): the whole message, any case.
local INVITE_WORDS = { inv = true, invite = true, ["+"] = true, ["+1"] = true }
local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }

Groups.REQUESTS_MAX = REQUESTS_MAX
-- When a group starts, from the moment it is listed (#378): now, or in 15, 30 or 60 minutes.
Groups.STARTS = { 0, 900, 1800, 3600 }
Groups.EXTEND_BY = EXTEND_BY

local function board() return GuildOS.LFGBoard end
local function myKey() return board():MyKey() end

-- Session only: who asked me, whom I asked, and the cooldowns.
local function state()
    local s = GuildOS.State.groups
    if not s then
        s = { requests = {}, asked = {}, askedAt = {}, askPending = {}, groupCd = {}, joinCd = {}, whisperCd = {},
              lastPublish = 0 }
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
        GuildOS.Compat.RegisterEvent(self.frame, "CHAT_MSG_WHISPER")
        GuildOS.Compat.RegisterEvent(self.frame, "GUILD_ROSTER_UPDATE")
        self.frame:SetScript("OnEvent", function(_, event, text, sender)
            if event == "CHAT_MSG_WHISPER" then
                GuildOS:SafeCall(Groups.OnWhisper, Groups, text, sender)
            elseif event == "GUILD_ROSTER_UPDATE" then
                GuildOS:SafeCall(Groups.OnGuildRoster, Groups)
            else
                GuildOS:SafeCall(Groups.OnGroupRoster, Groups)
            end
        end)
        -- Once a minute is enough for a line every ten (#378).
        self.ticker = GuildOS.Compat.NewTicker(60, function() GuildOS:SafeCall(Groups.Tick, Groups) end)
    end
    self:_RegisterTests()
end

local function pref(key)
    local prefs = GuildOS.db and GuildOS.db.lfgPrefs
    return prefs and prefs[key]
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

-- Whether an activity is one for a player of this level: inside its range, give or take LEVEL_SLACK,
-- and any level for one with no range. An id this client does not know is nobody's (#378).
function Groups:FitsLevel(act, level)
    local cat = GuildOS.GroupActivities
    local it = cat and cat.byId[act]
    if not it then return false end
    if not it.min or not level then return true end
    return level >= it.min - LEVEL_SLACK and level <= (it.max or it.min) + LEVEL_SLACK
end

-- The role I would ask for in a group that needs `need`: the first of mine it has a spot for, or,
-- with no roles of mine set, the first spot it has. nil when it has none for me.
function Groups:BestRole(need, myRoles)
    myRoles = myRoles or ""
    for _, k in ipairs(LETTERS) do
        if (myRoles == "" or myRoles:find(k, 1, true)) and ((need and need[k]) or 0) > 0 then return k end
    end
    return nil
end

-- Whether a whisper is a request for an invite: one of INVITE_WORDS, alone (#378).
function Groups:_IsInviteWord(text)
    if type(text) ~= "string" then return false end
    local word = text:match("^%s*(%S+)%s*$")
    return word ~= nil and INVITE_WORDS[word:lower()] == true
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
    -- A start, as seconds from when the listing was said (#378): never before it, never after it ends.
    local startIn = clampInt(p.startIn, 0, ttl - age, 0)
    return {
        start = startIn > 0 and (now + startIn) or nil,
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

-- Whoever is not online any more (logged off, or left the guild) leaves the board, on every client
-- (#449): a leader offline invites nobody, a player offline joins nothing, and what I asked of a
-- leader who left, or who asked me, goes with them. Nothing is said on the wire: when they come back
-- their own client answers the login's request with what is still up (CommSystem:HandleRequest), at
-- its real age. Only with a roster that has me online in it: an empty one at login says nothing. An entry
-- heard after the roster was last read (entry.rx, stamped on arrival, against rosterAt: the last
-- GUILD_ROSTER_UPDATE) stays: somebody who logged in and listed since is simply not in that roster yet.
-- onlineSet and rosterAt are injectable for the tests. Returns how many entries it dropped.
function Groups:SweepOffline(onlineSet, rosterAt)
    onlineSet = onlineSet or board():_BuildOnlineRoster()
    rosterAt = rosterAt or self.rosterAt
    local me = myKey()
    if not onlineSet or not onlineSet[me] then return 0 end
    local dropped, s = 0, state()
    local function fresh(entry) return type(entry) == "table" and entry.rx and (not rosterAt or entry.rx >= rosterAt) end
    local kept = {}
    for _, store in ipairs({ GuildOS.db.lfgGroups or {}, GuildOS.db.lfgBoard or {} }) do
        for key, entry in pairs(store) do
            if fresh(entry) then kept[key] = true end
            if key ~= me and not onlineSet[key] and not fresh(entry) then
                store[key] = nil
                dropped = dropped + 1
            end
        end
    end
    for key in pairs(s.asked) do
        if not onlineSet[key] and not kept[key] then s.asked[key] = nil; dropped = dropped + 1 end
    end
    for key in pairs(s.requests) do
        if not onlineSet[key] and not kept[key] then s.requests[key] = nil; dropped = dropped + 1 end
    end
    return dropped
end

-- The groups being formed, newest first. onlineSet (optional): { [key] = true } of members online;
-- a leader who logged off cannot invite anybody.
function Groups:ActiveList(store, now, onlineSet)
    local out = {}
    for key, g in pairs(store or {}) do
        -- A group with no spot left is formed, not being formed: it is not listed (#449).
        if board():_IsActive(g, now) and (not onlineSet or onlineSet[key]) and self:OpenSpots(g.need) > 0 then
            out[#out + 1] = {
                key = key, name = key:match("^([^-]+)") or key, from = g.from,
                act = g.act, note = g.note or "", need = g.need or {}, n = g.n or 1, max = g.max or SIZE_DEFAULT,
                ts = g.ts, ttl = g.ttl, start = g.start,
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
    local startIn = g.start and (g.start - now) or 0
    return { act = g.act, note = g.note, need = g.need, n = g.n, max = g.max, ttl = g.ttl, age = age,
             startIn = startIn > 0 and startIn or nil }
end

-- Seconds until a group starts, or nil for one that already has (or never named a start) (#378).
function Groups:StartsIn(g, now)
    if not g or not g.start then return nil end
    local left = g.start - (now or GetServerTime())
    return left > 0 and left or nil
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
function Groups:Create(act, need, note, ttl, toGuild, startIn)
    local B = board()
    act = B:_SanitizeAct(act)
    if not act then return nil, L["Pick what the group is for."] end
    if not GuildOS.Compat.CanInvite() then return nil, L["Only the group's leader can list it."] end
    local _, count = GuildOS.Compat.GroupRoster()
    local max = math.max(self:SizeOf(act), math.min(count, SIZE_MAX))
    need = self:_SanitizeNeed(need, max - count)
    if self:OpenSpots(need) == 0 then return nil, L["A group needs at least one open spot."] end
    ttl = B:_ClampTtl(ttl or GuildOS.db.lfgPrefs.lastTtl)
    local now = GetServerTime()
    startIn = clampInt(startIn, 0, ttl - 60, 0)
    local g = {
        act = act, note = GuildOS:SanitizeUserText(note, NOTE_MAX), need = need,
        n = count, max = max, ts = now, ttl = ttl, start = startIn > 0 and (now + startIn) or nil,
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
    -- The line is said again every ANNOUNCE_EVERY while the group is up (#378); the flag stays here,
    -- it never crosses the wire (payloadOf).
    g.announce = toGuild and true or nil
    -- A line the five-minute cooldown held back is tried again on the next tick.
    if toGuild then
        g.announcedAt = B:_SayInGuild(nil, nil, nil, self:_GuildLine(g)) and g.ts or (g.ts - ANNOUNCE_EVERY)
    end
    self:_Publish()
    B:Refresh()
    return g
end

-- The line in guild chat for a group: what for, how full, the spots, the note, and, when I invite
-- whoever asks, the word that gets a guildmate with no addon an invite (#378).
function Groups:_GuildLine(g)
    local name = string.format("%s (%d/%d)", board():ActivityName(g.act), g.n or 1, g.max or SIZE_DEFAULT)
    local line = string.format(L["[Guild OS] Group for %s, looking for %s"], name, self:NeedText(g.need))
    if g.note and g.note ~= "" then line = line .. ": " .. g.note end
    local startIn = self:StartsIn(g)
    if startIn then line = line .. string.format(L[" (starts in %dm)"], math.ceil(startIn / 60)) end
    if pref("autoInvite") then line = line .. L[" Whisper me \"inv\" for an invite."] end
    return line
end

-- Once a minute: a group listed with "also post in guild chat" says it again every ANNOUNCE_EVERY,
-- with the spots it has by then. A line the cooldown or the game held back is tried next minute.
function Groups:Tick(now)
    now = now or GetServerTime()
    -- Stale listings leave the board on their own, with the tab closed too (#449): what expired, and
    -- whoever is no longer online to form or join anything.
    local dropped = self:Prune(now) + board():Prune(now)
    if dropped > 0 then board():Refresh() end
    -- Who went offline is read from a fresh roster: asked for here, swept when it lands (OnGuildRoster).
    self.sweepPending = true
    GuildOS.Compat.GuildRoster()
    self:_WarnExpiring(now)
    local g = self:Mine()
    if not g or not g.announce or self:OpenSpots(g.need) == 0 then return false end
    if now - (g.announcedAt or g.ts or 0) < ANNOUNCE_EVERY then return false end
    if not board():_SayInGuild(nil, nil, nil, self:_GuildLine(g)) then return false end
    g.announcedAt = now
    return true
end

-- The guild's roster landed (GUILD_ROSTER_UPDATE): its time is when it was read, and the sweep a Tick asked
-- for runs against it.
function Groups:OnGuildRoster(now)
    self.rosterAt = now or GetServerTime()
    if not self.sweepPending then return 0 end
    self.sweepPending = false
    local dropped = self:SweepOffline()
    if dropped > 0 then board():Refresh() end
    return dropped
end

-- My group or my own listing ends in WARN_BEFORE: say so once, with "+30 min" one click away
-- (#378). Returns what was warned about, for the tests.
function Groups:_WarnExpiring(now)
    local warned
    local function check(entry, kind)
        if not entry or entry.warned then return end
        local left = entry.ts + (entry.ttl or 0) - now
        if left > 0 and left <= WARN_BEFORE then
            entry.warned = true
            warned = kind
            if GuildOS.GroupsToast then
                GuildOS:SafeCall(GuildOS.GroupsToast, GuildOS, { kind = "expiring", what = kind, left = left })
            else
                GuildOS:Print(L["Your listing ends in 5 minutes."])
            end
        end
    end
    check(self:Mine(), "group")
    check(board():Mine(), "seek")
    return warned
end

-- "+30 min": my group runs EXTEND_BY longer, up to the longest duration from now (#378). The listing
-- is said again with its new end; its start and its queue stay.
function Groups:Extend(by)
    local g = self:Mine()
    if not g then return false end
    local now = GetServerTime()
    local left = g.ts + g.ttl - now
    g.ttl = board():_ClampTtl(left + (by or EXTEND_BY))
    g.ts, g.warned = now, nil
    if g.announcedAt and g.announcedAt > now then g.announcedAt = now end
    self:_Publish()
    board():Refresh()
    return true
end

-- Say my group in guild chat now, outside the ten minutes. Returns true, or false and the seconds
-- the guild line's cooldown still holds it (#378).
function Groups:PostNow()
    local g = self:Mine()
    if not g then return false, 0 end
    local wait = board():GuildLineWait()
    if wait > 0 then return false, wait end
    if not board():_SayInGuild(nil, nil, nil, self:_GuildLine(g)) then return false, 0 end
    g.announcedAt = GetServerTime()
    return true
end

-- A ready check for my group, when there is one to check and I lead it (#378).
function Groups:CanReadyCheck()
    local _, count = GuildOS.Compat.GroupRoster()
    return count > 1 and GuildOS.Compat.CanInvite() and GuildOS.Compat.CanReadyCheck()
end
function Groups:ReadyCheck()
    if not self:CanReadyCheck() then return false end
    return GuildOS.Compat.DoReadyCheck()
end

-- Whether a group is one for me: my level, a spot in a role I play, and me not leading it (#378).
function Groups:FitsMe(g, level, myRoles)
    if not g or g.key == myKey() then return false end
    return self:FitsLevel(g.act, level) and self:BestRole(g.need, myRoles or "") ~= nil
end

-- The players looking who fit my group: they want its activity (or anything) and play a role it has
-- a spot for, with that role (#378). Newest first, as the board. Nobody already asked or invited.
function Groups:Matches(now, onlineSet)
    local g = self:Mine()
    if not g then return {} end
    local out, s = {}, state()
    for _, e in ipairs(board():ActiveList(GuildOS.db.lfgBoard, now, onlineSet)) do
        local wants = #(e.acts or {}) == 0
        for _, id in ipairs(e.acts or {}) do wants = wants or id == g.act end
        local role = wants and e.key ~= myKey() and not s.requests[e.key] and self:BestRole(g.need, e.roles or "")
        if role then out[#out + 1] = { key = e.key, name = e.name, role = role, entry = e } end
    end
    return out
end

-- Invite a player looking into my group, in the role they fit: they join the queue as invited, so
-- the spot of that role closes when they arrive (#378).
function Groups:InviteSeeker(key, name, role)
    local g = self:Mine()
    if not g or not key or not name or not ROLE_OF[role] or (g.need[role] or 0) < 1 then return false end
    local s = state()
    if not s.requests[key] then
        s.requests[key] = { key = key, name = name:match("^([^-]+)") or name, from = name, role = role,
                            at = GetServerTime(), state = "invited" }
    end
    self:_RaidUp(g)
    GuildOS.Compat.InviteUnit(name)
    board():Refresh()
    return true
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
        -- A listing with no spot left is a group that filled (#449): it closes, as a take-down does.
        if self:OpenSpots(g.need) == 0 then
            store[key] = nil
            state().asked[key] = nil
            board():Refresh()
            return
        end
        g.from = sender
        g.rx = now   -- heard now: a roster read before this has not seen them online yet (SweepOffline)
        store[key] = g
        -- What I asked, I asked of the group that was listed.
        if not wasActive or was.act ~= g.act then state().asked[key] = nil end
        if age == 0 and not wasActive and key ~= myKey() then self:_Announce(key, short, g) end
    end
    board():Refresh()
end

-- Whether a new group is worth a notice on screen (#378): one this client knows, for my level, and
-- me free to take it: in no group, leading none. The rest still reach the board. Combat does not drop
-- it any more (#449): the notice goes through GuildOS:ShowWhenClear, which holds it until combat ends,
-- and it checks the group still has my spot when it shows.
function Groups:_ShouldToast(g, level, inGroup)
    if pref("toast") == false or inGroup or self:Mine() then return false end
    return self:FitsLevel(g.act, level) and self:BestRole(g.need, board():Pref("roles") or "") ~= nil
end

-- A guildmate just listed a group: a small notice that goes away by itself where it fits me, the
-- chat line of #341 otherwise (when notices in chat are on).
function Groups:_Announce(key, short, g)
    local inGroup = (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 1) or false
    if GuildOS.GroupsToast and self:_ShouldToast(g, UnitLevel and UnitLevel("player"), inGroup) then
        GuildOS:SafeCall(GuildOS.GroupsToast, GuildOS, { kind = "group", key = key, name = short, act = g.act,
            need = g.need, note = g.note })
        return "toast"
    end
    if pref("notify") then
        GuildOS:Print(string.format(L["%s is forming a group for %s."], short, board():ActivityName(g.act)))
        return "chat"
    end
    return nil
end

-- Whether a notice queued behind combat or another window still says something true when it shows
-- (#449): the group is still up with a spot in a role of mine, the request is still waiting, my
-- listing is still mine. n is the notice GroupsToast was given.
function Groups:StillTrue(n, now)
    if type(n) ~= "table" then return false end
    now = now or GetServerTime()
    if n.kind == "group" then
        local g = GuildOS.db.lfgGroups and GuildOS.db.lfgGroups[n.key]
        if not board():_IsActive(g, now) or self:Mine() or self:Asked(n.key) then return false end
        return self:BestRole(g.need, board():Pref("roles") or "") ~= nil
    elseif n.kind == "request" then
        local r = state().requests[n.key]
        return r ~= nil and r.state == "pending" and self:Mine() ~= nil
    elseif n.kind == "expiring" then
        return (n.what == "group" and self:Mine() or board():Mine()) ~= nil
    end
    return false
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

-- A party for a group larger than one becomes a raid as soon as it can (two in it), so the sixth
-- invite never meets a full party (#378). Only the leader can, and the game says so itself.
function Groups:_RaidUp(g, count)
    g = g or self:Mine()
    if not g or g.max <= PARTY_MAX then return false end
    if count == nil then count = select(2, GuildOS.Compat.GroupRoster()) end
    if count < 2 or (IsInRaid and IsInRaid()) then return false end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return false end
    return GuildOS.Compat.ConvertToRaid()
end

function Groups:Invite(key)
    local r = state().requests[key]
    if not r then return false end
    r.state = "invited"
    self:_RaidUp()
    GuildOS.Compat.InviteUnit(r.from)
    board():Refresh()
    return true
end

-- A whisper from a guildmate with no addon: "inv" gets an invite into my listed group while it has
-- a spot and I invite whoever asks (#378). Only from somebody on the roster, never one already in
-- the group, at most once a sender every WHISPER_COOLDOWN. `schedule` is injectable for the tests.
function Groups:OnWhisper(text, sender, schedule)
    if GuildOS.Compat.IsSecret(text, sender) or type(sender) ~= "string" then return false end
    if not self:_IsInviteWord(text) or not pref("autoInvite") then return false end
    local g = self:Mine()
    if not g or self:OpenSpots(g.need) == 0 or not GuildOS.Compat.CanInvite() then return false end
    local key, shown = GuildOS:RosterKey(sender)
    if not key or key == myKey() then return false end
    local short = shown or sender:match("^([^-]+)") or sender
    local members = GuildOS.Compat.GroupRoster()
    if GuildOS.Compat.InGroup(members, key) then return false end
    if rateLimited(state().whisperCd, key, WHISPER_COOLDOWN, schedule) then return false end
    self:_RaidUp(g)
    GuildOS.Compat.InviteUnit(sender)
    GuildOS:Print(string.format(L["Inviting %s, who whispered for a spot."], short))
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
            -- Invite whoever asks (#378): the party forms as the requests arrive. Otherwise the leader
            -- answers from a notice, with the tab closed.
            if pref("autoInvite") then
                self:Invite(key)
            elseif GuildOS.GroupsToast then
                GuildOS:SafeCall(GuildOS.GroupsToast, GuildOS, { kind = "request", key = key, name = short,
                    role = role })
            end
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
        else
            self:_RaidUp(g, count)
            if changed then self:_Publish() end
        end
    end

    local joined = false
    for key in pairs(s.asked) do
        if here(key) then joined = true end
    end
    -- In the party of a guildmate's listed group, asked or invited, I am no longer looking (#449): an
    -- invite from the leader's "Invite" left my own listing up for as long as it had.
    if not joined and not g and board():AmAvailable() then
        for key in pairs(GuildOS.db.lfgGroups or {}) do
            if key ~= myKey() and here(key) then joined = true end
        end
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
