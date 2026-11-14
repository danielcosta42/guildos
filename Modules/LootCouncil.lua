----------------------------------------------------------------------
-- Guild OS - Loot Council (issue #336)
--
-- A rule whose items a council decides (`decide.by = "council"`). When the answers close, the master
-- looter's client opens a session: the council's members who run GuildOS see the candidates, already
-- in the rule's order, with what the rule knows of each, and vote for one. The master looter's client
-- counts; when the votes the rule asks for are in (`quorum`), or the master looter ends the vote, the
-- candidate with the most votes is proposed (a tie goes to whoever the rule's order puts first) and
-- the master looter confirms with Award. With no quorum when the time runs out, the master looter
-- decides, and the award's record says so.
--
-- The messages, all under LootMaster.PREFIX; a client from before reads none of them:
--   COPEN|sid|seconds|flags|quorum|ranks|link   master looter -> raid: a vote opens. flags: "a" who
--                                               voted for whom is hidden, "s" a member who is a
--                                               candidate may vote; ranks: the guild rank indexes of
--                                               the council, as digits ("-" for none)
--   CMEM|sid|name,name,...                      master looter -> raid: the members named one by one
--   CCAND|sid|i|name|KEY|roll|bid|att|recv|points|wish|prio|reserve|accts|note
--                                               master looter -> raid: the candidate in place i
--   CVOTE|sid|i                                 member -> master looter: a vote for the candidate in
--                                               place i (0 takes the vote back). Over RAID, or
--                                               whispered when the council is anonymous, as a sealed
--                                               bid is
--   CTALLY|sid|i=n,i=n                          master looter -> raid: the votes so far
--   CWHO|sid|voter|i                            master looter -> raid: who voted for whom (never
--                                               sent by an anonymous council)
--   CNO|sid|voter|why                           master looter -> raid: a vote it refused
--   CCLOSE|sid|reason|i                         master looter -> raid: the vote is over; reason "q"
--                                               quorum, "m" the master looter ended it, "t" time ran
--                                               out, "x" cancelled; i the candidate proposed, 0 none
--
-- Untrusted input. Only the raid's master looter opens or closes a session, and a client reads those
-- messages from nobody else (LootMaster:IsFromMasterLooter: where the game names no master looter, the
-- raid's leader or an assistant). A vote is its sender's, as the game names them, who has to be in the
-- raid and a member of the council by this client's own guild roster (a rank) or by the rule's list
-- of names; what a message says of who sent it is never read. One vote a member and an item: a new
-- one replaces the old. The session's id is the roll's, so a vote for the item before is not one for
-- this.
-- Pure of frames: the window is UI/LootCouncil.lua, and reads `View`.
----------------------------------------------------------------------
-- Not on retail, which has no master looter (ADR-0026): there the item's holder or an officer awards.
if GuildOS.Client.isRetail then return end

local Council = {}
GuildOS.LootCouncil = Council
local L = GuildOS.L

Council.VOTE_MIN = 30            -- seconds a vote stays open at least, whatever the rule's time
local CANDIDATES_MAX = 10        -- candidates one vote lists: the record's own cap
local NAME_MAX = 64              -- bytes of a name on the wire
local NOTE_MAX = 60              -- bytes of a candidate's note
local ACCTS_MAX = 60             -- bytes of a candidate's accounts on the wire
local MEMBERS_CHUNK = 200        -- bytes of names one CMEM carries
local WIRE_MAX = 255             -- bytes of an addon message
local CLOSE_CODE = { quorum = "q", ml = "m", timeout = "t", cancel = "x" }
local CODE_CLOSE = { q = "quorum", m = "ml", t = "timeout", x = "cancel" }

local function LM() return GuildOS.LootMaster end

-- A raider's side: the vote this client is watching, { sid, ml, link, endsAt, anon, selfVote, quorum,
-- ranks, named, candidates = { [i] = candidate }, tally = { [i] = n }, who = { [voter] = i }, mine,
-- member, open, reason, proposed }. Lost on a reload, as a roll's popup is.
local function watching()
    return GuildOS.State and GuildOS.State.lootCouncil
end

local function refresh()
    if GuildOS.RefreshLootCouncil then GuildOS:RefreshLootCouncil() end
end

local function myName()
    return GuildOS.Compat.PlayerName() or ""
end

-- Whether two names are the same player's. On a client with surnames one side may hold the first
-- name alone (issue #48).
local function sameName(a, b)
    if a == b then return true end
    if not (a and b) then return false end
    if strlower(a) == strlower(b) then return true end
    return GuildOS.Client.has.surnames and a:match("^%S+") == b:match("^%S+") or false
end

----------------------------------------------------------------------
-- Who is on the council
----------------------------------------------------------------------
-- A player's guild rank index by this client's own roster, or nil for somebody who is not in the guild.
function Council:RankOf(name)
    if not (IsInGuild() and type(name) == "string" and name ~= "") then return nil end
    local short = name:match("^([^%-]+)") or name
    for i = 1, GetNumGuildMembers() or 0 do
        local full, _, rankIndex = GetGuildRosterInfo(i)
        if full and (full:match("^([^%-]+)") or full) == short then return rankIndex end
    end
    return nil
end

-- The council's ranks as the rule means them: its own, and with neither a rank nor a name, the
-- guild's officers (ranks 0 to the officer threshold).
function Council:Ranks(council)
    local ranks = {}
    if council.ranks or (council.names and #council.names > 0) then
        for _, rank in ipairs(council.ranks or {}) do ranks[rank] = true end
        return ranks
    end
    local top = GuildOS.db and GuildOS.db.settings and tonumber(GuildOS.db.settings.officerMaxRank) or 1
    for rank = 0, top do ranks[rank] = true end
    return ranks
end

-- Whether `name`, a raider as the game names them, is a member of `council`: one of its names, or
-- of one of its ranks by this client's guild roster.
function Council:IsMember(name, council)
    if type(name) ~= "string" or name == "" or type(council) ~= "table" then return false end
    for _, listed in ipairs(council.names or {}) do
        if sameName(listed, name) then return true end
    end
    local rank = self:RankOf(name)
    return rank ~= nil and self:Ranks(council)[rank] == true
end

----------------------------------------------------------------------
-- The master looter's side
----------------------------------------------------------------------
local function send(payload)
    LM():SendEcho(payload)
end

-- A candidate as the council reads them: what the roll's row holds, by the names the wire uses.
local function candidateOf(row, place, rule)
    local accts = {}
    for _, a in ipairs(GuildOS.LootRule:OwnAccounts(rule)) do
        local has = row.accts and row.accts[a.key]
        if has then accts[#accts + 1] = { key = a.key, value = math.floor(has) } end
    end
    local reserve = row.softRes
    return {
        place = place, name = row.name, answer = row.rollType, roll = math.floor(row.roll or 0), bid = math.floor(row.bid or 0),
        att = math.floor(row.att25 or 0), recv = math.floor(row.recvCount or 0), points = math.floor(row.dkp or 0),
        wish = row.wishlist and row.wishlist.order or 0, prio = row.prioOrder or 0,
        reserve = reserve and ((type(reserve) == "table" and reserve.hard) and 2 or 1) or 0,
        accts = accts, note = row.note,
    }
end

local function acctsText(accts)
    local parts, size = {}, 0
    for _, a in ipairs(accts) do
        local part = string.format("%s:%d", a.key, a.value)
        if size + #part + 1 > ACCTS_MAX then break end
        parts[#parts + 1], size = part, size + #part + 1
    end
    return table.concat(parts, ",")
end

local function candidateWire(sid, c)
    local head = string.format("CCAND|%s|%d|%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%s|", sid, c.place, c.name, c.answer,
        c.roll, c.bid, c.att, c.recv, c.points, c.wish, c.prio, c.reserve, acctsText(c.accts))
    local note = tostring(c.note or ""):gsub("[|%c]", "")
    return head .. note:sub(1, math.max(0, math.min(NOTE_MAX, WIRE_MAX - #head)))
end

-- The session of the item being given, on the master looter's client, or nil.
function Council:Session()
    local loot = LM() and LM().activeLoot
    return loot and loot.council or nil
end

-- A vote opens for the roll that just ended: `sorted` are its candidates in the rule's order.
-- Returns the session, kept on the item (`loot.council`):
--   { sid, cfg, open, endsAt, candidates = { [i] = candidate }, votes = { [voter] = i },
--     reason, proposed, noQuorum }
function Council:Open(loot, sorted, rule)
    local cfg = GuildOS.LootRule:Council(rule)
    if not (cfg and loot and loot.sid) then return nil end
    local seconds = math.max(self.VOTE_MIN, tonumber(rule.time) or LM().ROLL_DURATION or 30)
    local session = {
        sid = loot.sid, cfg = cfg, open = true, endsAt = GetServerTime() + seconds, seconds = seconds,
        candidates = {}, votes = {}, link = loot.link,
    }
    for i, row in ipairs(sorted) do
        if i > CANDIDATES_MAX then break end
        session.candidates[i] = candidateOf(row, i, rule)
    end
    loot.council = session

    local ranks = {}
    for rank = 0, 9 do
        if self:Ranks(cfg)[rank] then ranks[#ranks + 1] = tostring(rank) end
    end
    local flags = (cfg.anon and "a" or "") .. (cfg.self and "s" or "")
    send(string.format("COPEN|%s|%d|%s|%d|%s|%s", session.sid, seconds, flags ~= "" and flags or "-",
        cfg.quorum or 0, #ranks > 0 and table.concat(ranks) or "-", loot.link or ""))
    -- The members named one by one, in as many messages as their names take.
    local chunk = ""
    for _, name in ipairs(cfg.names or {}) do
        if #chunk + #name + 1 > MEMBERS_CHUNK then
            send("CMEM|" .. session.sid .. "|" .. chunk)
            chunk = ""
        end
        chunk = chunk ~= "" and (chunk .. "," .. name) or name
    end
    if chunk ~= "" then send("CMEM|" .. session.sid .. "|" .. chunk) end
    for _, c in ipairs(session.candidates) do send(candidateWire(session.sid, c)) end

    if session.timer then session.timer:Cancel() end
    session.timer = C_Timer.NewTimer(seconds, function() Council:Timeout(session.sid) end)
    if GuildOS.ShowLootCouncil then GuildOS:ShowLootCouncil() end
    return session
end

-- The votes so far: how many each candidate has (by place), how many there are, and the place of
-- whoever has the most, a tie going to the one the rule's order puts first. nil with no vote.
function Council:Tally(session)
    local tally, count, lead = {}, 0, nil
    for _, place in pairs(session.votes) do
        tally[place] = (tally[place] or 0) + 1
        count = count + 1
    end
    for place = 1, #session.candidates do
        if tally[place] and (not lead or tally[place] > tally[lead]) then lead = place end
    end
    return tally, count, lead
end

local function tallyWire(session)
    local tally = Council:Tally(session)
    local parts = {}
    for place = 1, #session.candidates do
        if tally[place] then parts[#parts + 1] = place .. "=" .. tally[place] end
    end
    return "CTALLY|" .. session.sid .. "|" .. (#parts > 0 and table.concat(parts, ",") or "-")
end

-- One vote of `voter`, a raid member as the game named them, for the candidate in `place` (0 takes
-- the vote back). Returns true, or false and why: "closed", "member" (not on the council), "self" (a
-- candidate on a council whose candidates do not vote) or "unknown" (no such candidate).
function Council:TakeVote(voter, place)
    local session = self:Session()
    if not (session and session.open) then return false, "closed" end
    if not self:IsMember(voter, session.cfg) then return false, "member" end
    place = tonumber(place)
    if not place or place ~= math.floor(place) or place < 0 or place > #session.candidates then return false, "unknown" end
    if not session.cfg.self then
        for _, c in ipairs(session.candidates) do
            if sameName(c.name, voter) then return false, "self" end
        end
    end
    -- One vote a member: under the name already kept for them, when this one is the same player's.
    local key = voter
    for held in pairs(session.votes) do
        if sameName(held, voter) then key = held end
    end
    session.votes[key] = place > 0 and place or nil
    send(tallyWire(session))
    if not session.cfg.anon then send(string.format("CWHO|%s|%s|%d", session.sid, key, place)) end
    local _, count = self:Tally(session)
    if session.cfg.quorum and count >= session.cfg.quorum then
        self:Close("quorum")
    else
        refresh()
        if LM().RefreshRollFrame then LM():RefreshRollFrame() end
    end
    return true
end

-- A CVOTE message. The vote is its sender's, who has to be in the raid; the session's id has to be
-- this item's.
function Council:OnVoteMessage(rest, sender)
    local session = self:Session()
    if not (session and LM():IsMasterLooter()) then return end
    if type(rest) ~= "string" or #rest > 24 then return end
    local sid, place = rest:match("^(%x+)|(%d+)$")
    if not sid or sid ~= session.sid or #place > 2 then return end
    local voter = LM():RaidRollerName(sender)
    if not voter then return end
    local ok, why = self:TakeVote(voter, tonumber(place))
    if not ok then send(string.format("CNO|%s|%s|%s", session.sid, voter, why)) end
end

-- The vote is over. `reason`: "quorum" (the votes the rule asks for are in), "ml" (the master looter
-- ended it, or awarded the item), "timeout" or "cancel". Whoever has the most votes is proposed; when
-- the time ran out short of the quorum nobody is, and the master looter decides.
function Council:Close(reason)
    local session = self:Session()
    if not (session and session.open) then return nil end
    session.open, session.reason = false, reason
    if session.timer then session.timer:Cancel(); session.timer = nil end
    local _, count, lead = self:Tally(session)
    if reason == "cancel" then
        lead = nil
    elseif reason == "timeout" and session.cfg.quorum and count < session.cfg.quorum then
        lead, session.noQuorum = nil, true
    end
    session.proposed = lead and session.candidates[lead].name or nil
    send(string.format("CCLOSE|%s|%s|%d", session.sid, CLOSE_CODE[reason] or "x", lead or 0))
    if reason ~= "cancel" then
        local loot = LM().activeLoot
        local line
        if session.proposed then
            local tally = self:Tally(session)
            line = string.format(L["[Council] %s: the council proposes %s (%d of %d votes)"], loot and loot.link or "",
                session.proposed, tally[lead] or 0, count)
        elseif session.noQuorum then
            line = string.format(L["[Council] %s: no quorum (%d of %d votes): the master looter decides"],
                loot and loot.link or "", count, session.cfg.quorum)
        else
            line = string.format(L["[Council] %s: nobody voted: the master looter decides"], loot and loot.link or "")
        end
        -- The time running out is no click: on WoW: Forever the line then reaches the loot master only (#63).
        if reason == "timeout" then LM():SafeSendChatAuto(line, "RAID") else LM():SafeSendChat(line, "RAID") end
    end
    refresh()
    if LM().RefreshRollFrame then LM():RefreshRollFrame() end
    return session.proposed
end

function Council:Timeout(sid)
    local session = self:Session()
    if session and session.open and session.sid == sid then self:Close("timeout") end
end

-- The votes for the award's record (LootRule:Why): { anon, quorum, cast = { { by, for } }, tally =
-- { [name] = n } }. With an anonymous council who voted for whom is not kept at all.
function Council:Record(session)
    local votes = { anon = session.cfg.anon == true, quorum = session.cfg.quorum or 0 }
    local tally, any = {}, false
    for _, place in pairs(session.votes) do
        local name = session.candidates[place].name
        tally[name], any = (tally[name] or 0) + 1, true
    end
    votes.tally = any and tally or nil
    if not votes.anon then
        votes.cast = {}
        for voter, place in pairs(session.votes) do
            votes.cast[#votes.cast + 1] = { by = voter, ["for"] = session.candidates[place].name }
        end
        table.sort(votes.cast, function(a, b) return a.by < b.by end)
    end
    return votes
end

-- What decided an award under a council: "council" when the winner is who the council proposed,
-- "ml" when the master looter gave the item to somebody else or had to decide for want of a quorum.
function Council:DecidedBy(session, winner)
    return (session.proposed ~= nil and session.proposed == winner) and "council" or "ml"
end

----------------------------------------------------------------------
-- A raider's side
----------------------------------------------------------------------
local function whole(text, max)
    local n = tonumber(text)
    if not n or n ~= math.floor(n) or n < 0 or n > max then return nil end
    return n
end

-- What this client makes of being on the council of the vote it watches: by its own guild rank, or
-- by its name among the members the master looter named. Only what the window is shown for; the
-- master looter's client checks every vote by itself.
local function amMember(w)
    for _, name in ipairs(w.named) do
        if sameName(name, myName()) then return true end
    end
    local _, _, rank = GetGuildInfo("player")
    return rank ~= nil and w.ranks[rank] == true
end

local HANDLERS = {}

function HANDLERS.COPEN(sender, rest)
    local sid, seconds, flags, quorum, ranks, link = rest:match("^(%x+)|(%d+)|([as%-]+)|(%d+)|([%d%-]+)|(.*)$")
    seconds, quorum = whole(seconds, 3600), whole(quorum, 40)
    if not (sid and #sid <= 8 and seconds and quorum) or link:find("%c") then return end
    local w = {
        sid = sid, ml = sender, link = link, endsAt = GetServerTime() + seconds, open = true,
        anon = flags:find("a", 1, true) ~= nil, selfVote = flags:find("s", 1, true) ~= nil,
        quorum = quorum, ranks = {}, named = {}, candidates = {}, tally = {}, who = {},
    }
    for digit in ranks:gmatch("%d") do w.ranks[tonumber(digit)] = true end
    w.member = amMember(w)
    GuildOS.State.lootCouncil = w
    if w.member and GuildOS.ShowLootCouncil then GuildOS:ShowLootCouncil() end
end

function HANDLERS.CMEM(_, rest, w)
    local names = rest:match("^%x+|(.+)$")
    if not names or #w.named >= 20 then return end
    for name in names:gmatch("[^,]+") do
        if #name <= NAME_MAX and not name:find("%c") and #w.named < 20 then w.named[#w.named + 1] = name end
    end
    local was = w.member
    w.member = amMember(w)
    if w.member and not was and w.open and GuildOS.ShowLootCouncil then GuildOS:ShowLootCouncil() end
end

function HANDLERS.CCAND(_, rest, w)
    local place, name, answer, roll, bid, att, recv, points, wish, prio, reserve, accts, note = rest:match(
        "^%x+|(%d+)|([^|]+)|([A-Z0-9]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%-?%d+)|(%d+)|(%d+)|([012])|([^|]*)|(.*)$")
    place = whole(place, CANDIDATES_MAX)
    if not place or place < 1 or #name > NAME_MAX or #answer > 8 or name:find("%c") or note:find("[|%c]") then return end
    local c = {
        place = place, name = name, answer = answer, roll = whole(roll, 1000000) or 0, bid = whole(bid, 1000000) or 0,
        att = whole(att, 100) or 0, recv = whole(recv, 1000) or 0, points = tonumber(points) or 0,
        wish = whole(wish, 999) or 0, prio = whole(prio, 999) or 0, reserve = tonumber(reserve), accts = {},
        note = note ~= "" and note:sub(1, NOTE_MAX) or nil,
    }
    if #accts <= ACCTS_MAX then
        for key, value in accts:gmatch("([a-z0-9]+):(%d+)") do
            c.accts[#c.accts + 1] = { key = key, value = tonumber(value) }
        end
    end
    w.candidates[place] = c
end

function HANDLERS.CTALLY(_, rest, w)
    local text = rest:match("^%x+|([%d=,%-]+)$")
    if not text then return end
    local tally = {}
    for place, n in text:gmatch("(%d+)=(%d+)") do
        place, n = whole(place, CANDIDATES_MAX), whole(n, 40)
        if place and n then tally[place] = n end
    end
    w.tally = tally
end

function HANDLERS.CWHO(_, rest, w)
    local voter, place = rest:match("^%x+|([^|]+)|(%d+)$")
    place = whole(place, CANDIDATES_MAX)
    if not place or #voter > NAME_MAX or voter:find("%c") or w.anon then return end
    w.who[voter] = place > 0 and place or nil
    if sameName(voter, myName()) then w.mine = place > 0 and place or nil end
end

function HANDLERS.CNO(_, rest, w)
    local voter, why = rest:match("^%x+|([^|]+)|(%a+)$")
    if not voter or not sameName(voter, myName()) then return end
    w.mine, w.refused = nil, why
    GuildOS:Print("|cffFF4444" .. Council:WhyNot(why) .. "|r")
end

function HANDLERS.CCLOSE(_, rest, w)
    local code, place = rest:match("^%x+|(%a)|(%d+)$")
    place = whole(place, CANDIDATES_MAX)
    if not (code and CODE_CLOSE[code] and place) then return end
    w.open, w.reason = false, CODE_CLOSE[code]
    w.proposed = w.candidates[place] and w.candidates[place].name or nil
end

-- A council message heard on the raid's channel. Read only from the raid's master looter, and after
-- the COPEN only from the one who sent it and for the session it opened.
function Council:OnMessage(cmd, rest, sender)
    local handler = HANDLERS[cmd]
    if not handler or type(rest) ~= "string" or #rest > WIRE_MAX then return end
    local lm = LM()
    if lm:IsMasterLooter() or not lm:IsFromMasterLooter(sender) then return end
    if cmd == "COPEN" then
        handler(sender, rest)
    else
        local w = watching()
        if not w or sender ~= w.ml or rest:match("^(%x+)|") ~= w.sid then return end
        handler(sender, rest, w)
    end
    refresh()
end

-- Why a vote was not taken, in words. Each one by its own literal key.
function Council:WhyNot(why)
    if why == "member" then return L["You are not on the council of this item."] end
    if why == "self" then return L["A candidate does not vote on this item."] end
    if why == "unknown" then return L["That is not one of this vote's candidates."] end
    return L["No vote is open."]
end

-- My vote: the candidate in `place`, or 0 to take it back. On the master looter's own client it is
-- counted here; from anybody else it goes to the master looter, over the raid or, when who voted for
-- whom is hidden, by whisper. Returns true, or false and why.
function Council:Vote(place)
    local lm = LM()
    local session = self:Session()
    if session and lm:IsMasterLooter() then
        local voter = lm:RaidRollerName(myName()) or myName()
        local ok, why = self:TakeVote(voter, place)
        if ok then session.mine = place > 0 and place or nil end
        refresh()
        return ok, why
    end
    local w = watching()
    if not (w and w.open) then return false, "closed" end
    if not w.member then return false, "member" end
    local msg = string.format("CVOTE|%s|%d", w.sid, place)
    if w.anon then
        if IsInRaid() and not lm.testMode then
            GuildOS:NoteWhisper(w.ml)
            GuildOS.Compat.SendAddonMessageNow(lm.PREFIX, msg, "WHISPER", w.ml)
        end
    else
        lm:SafeSendAddon(lm.PREFIX, msg, "RAID")
    end
    -- Shown at once; the master looter's tally, or its refusal, says what came of it.
    w.mine, w.refused = place > 0 and place or nil, nil
    refresh()
    return true
end

-- The master looter ends the vote now.
function Council:EndVote()
    if not (self:Session() and LM():IsMasterLooter()) then return nil end
    return self:Close("ml")
end

----------------------------------------------------------------------
-- What the council window shows, on either side: nil with no vote to show.
--   { link, open, endsAt, anon, quorum, cast, isML, canVote, whyNot, mine, proposed, reason,
--     candidates = { { place, name, answer, roll, bid, att, recv, points, wish, prio, reserve, accts,
--                      note, votes, voters = { name, ... } }, ... } }
-- `voters` is empty with an anonymous council: only the totals are shown.
----------------------------------------------------------------------
function Council:View()
    local lm = LM()
    local session = self:Session()
    local view
    if session and lm:IsMasterLooter() then
        local tally, count = self:Tally(session)
        local member = self:IsMember(lm:RaidRollerName(myName()) or myName(), session.cfg)
        view = {
            link = session.link, open = session.open, endsAt = session.endsAt, anon = session.cfg.anon == true,
            quorum = session.cfg.quorum or 0, cast = count, isML = true, member = member,
            selfVote = session.cfg.self == true, mine = session.mine, proposed = session.proposed, reason = session.reason,
            candidates = {},
        }
        for i, c in ipairs(session.candidates) do
            local row = { votes = tally[i] or 0, voters = {} }
            for k, v in pairs(c) do row[k] = v end
            if not view.anon then
                for voter, place in pairs(session.votes) do
                    if place == i then row.voters[#row.voters + 1] = voter end
                end
                table.sort(row.voters)
            end
            view.candidates[i] = row
        end
    else
        local w = watching()
        if not w then return nil end
        local count = 0
        for _, n in pairs(w.tally) do count = count + n end
        view = {
            link = w.link, open = w.open, endsAt = w.endsAt, anon = w.anon, quorum = w.quorum, cast = count,
            isML = false, member = w.member, selfVote = w.selfVote, mine = w.mine, proposed = w.proposed,
            reason = w.reason, candidates = {},
        }
        for i = 1, CANDIDATES_MAX do
            local c = w.candidates[i]
            if c then
                local row = { votes = w.tally[i] or 0, voters = {} }
                for k, v in pairs(c) do row[k] = v end
                for voter, place in pairs(w.who) do
                    if place == i then row.voters[#row.voters + 1] = voter end
                end
                table.sort(row.voters)
                view.candidates[#view.candidates + 1] = row
            end
        end
    end
    -- Whether this player may vote now, and why not when they may not.
    local candidate = false
    for _, c in ipairs(view.candidates) do candidate = candidate or sameName(c.name, myName()) end
    if not view.open then
        view.canVote, view.whyNot = false, "closed"
    elseif not view.member then
        view.canVote, view.whyNot = false, "member"
    elseif candidate and not view.selfVote then
        view.canVote, view.whyNot = false, "self"
    else
        view.canVote = true
    end
    return view
end

-- The line that says where the vote stands, for the windows. Each one by its own literal key.
function Council:StatusText(view)
    if view.open then
        local left = math.max(0, (view.endsAt or 0) - GetServerTime())
        if view.quorum > 0 then
            return string.format(L["Council vote: %d of %d votes needed, %ds left"], view.cast, view.quorum, left)
        end
        return string.format(L["Council vote: %d votes, %ds left"], view.cast, left)
    end
    if view.proposed then return string.format(L["The council proposes %s. The master looter confirms with Award."], view.proposed) end
    if view.reason == "cancel" then return L["The vote was cancelled."] end
    return L["No proposal from the council: the master looter decides."]
end
