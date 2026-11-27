----------------------------------------------------------------------
-- Guild OS - A member's rename (specs/salao/log-e-renomes.md)
--
-- A paid name change keeps the character and gives it a new key: everything GuildOS keeps by key
-- (the member's history, alt links, ban, safe mark and nickname, officer notes and sheet, permanent
-- note, trial, birthday, raid attendance, first seen) would stay with a name nobody has any more,
-- and the new name would start from nothing. The officers' roster diff (MemberHistory:Scan) asks
-- Pairs() which of its "gone" and "join" are one character:
--   * the same GUID (GetGuildRosterInfo's 17th return, Compat.GuildRosterGUID) under a new name: a
--     rename, moved at once (a realm transfer changes the GUID: that is a departure and a join);
--   * without a GUID on either side: exactly one gone and one new in the same diff, with the same
--     class, the same rank, the level within one, and the same public or officer note (not empty):
--     likely the same character. One question to the officer, through the popup queue (never in
--     combat, one window at a time), once a session for the pair; until it is answered the two keys
--     stay out of the diff. Yes moves everything; no is remembered and the next diff records a
--     departure and a join as usual.
-- What is synced moves through its own API, so it reaches the other officers with its revision or
-- tombstone (AltSync, BanList, MemberMarks, OfficerNotes' sheet, Birthdays, TrialTracker); the rest is
-- this client's (every officer's client sees the same diff and moves its own). The audit log gets a
-- "rename" line ("Abc > Xyz"), this client's. The player's own rename (AltAutoDetect:CheckRename, by
-- the account's GUID) moves the alt links the same way, with the same PlanRename.
--
--   db.memberRenames = { declined = { ["old|new"] = at } }
----------------------------------------------------------------------
local MemberRename = {}
GuildOS.MemberRename = MemberRename
local L = GuildOS.L

MemberRename.DECLINED_TTL = 180 * 86400

local function session()
    GuildOS.State.memberRename = GuildOS.State.memberRename or { asked = {}, accepted = {} }
    return GuildOS.State.memberRename
end

local function pairKey(old, new) return tostring(old) .. "|" .. tostring(new) end
local function short(key) return type(key) == "string" and (key:match("^([^-]+)") or key) or key end

local function store()
    local db = GuildOS.db
    if type(db) ~= "table" then return { declined = {} } end
    if type(db.memberRenames) ~= "table" then db.memberRenames = {} end
    if type(db.memberRenames.declined) ~= "table" then db.memberRenames.declined = {} end
    return db.memberRenames
end

function MemberRename:Initialize()
    local s, now = store(), GetServerTime()
    for k, at in pairs(s.declined) do
        if type(at) ~= "number" or at < now - self.DECLINED_TTL then s.declined[k] = nil end
    end
    local st = session()
    st.asked, st.accepted = {}, {}
end

----------------------------------------------------------------------
-- Pure: which of a diff's departures and joins are one character
----------------------------------------------------------------------
local function sameNote(a, b)
    return type(a) == "string" and a ~= "" and a == b
end

-- `changes` (MemberHistory.Diff's), `base` (key -> { r, lv, n, o, c, g }) and `rows` (the roster read now:
-- { key, r, lv, n, o, cls, g }). Returns { { old, new, how = "guid"|"guess" } }. Linear in the roster.
function MemberRename.Pairs(changes, base, rows)
    local out = {}
    local goneByGuid, gone, joins = nil, {}, {}
    for _, c in ipairs(changes or {}) do
        if c.kind == "gone" then
            gone[#gone + 1] = c.key
            local g = base[c.key] and base[c.key].g
            if g then
                goneByGuid = goneByGuid or {}
                goneByGuid[g] = c.key
            end
        elseif c.kind == "join" then
            joins[c.key] = true
        end
    end
    if #gone == 0 or not next(joins) then return out end
    local newRows = {}
    for _, row in ipairs(rows or {}) do
        if joins[row.key] then newRows[#newRows + 1] = row end
    end
    local taken = {}
    if goneByGuid then
        for _, row in ipairs(newRows) do
            local old = row.g and goneByGuid[row.g]
            if old and not taken[old] then
                taken[old], taken[row.key] = true, true
                out[#out + 1] = { old = old, new = row.key, how = "guid" }
            end
        end
    end
    -- Without a GUID: one departure and one join in the same diff that look like the same character.
    if #out == 0 and #gone == 1 and #newRows == 1 then
        local b, row = base[gone[1]], newRows[1]
        if b and not b.g and not row.g and b.c and b.c == row.cls and b.r == row.r
            and b.lv and row.lv and math.abs(b.lv - row.lv) <= 1
            and (sameNote(b.n, row.n) or sameNote(b.o, row.o)) then
            out[#out + 1] = { old = gone[1], new = row.key, how = "guess" }
        end
    end
    return out
end

----------------------------------------------------------------------
-- The question
----------------------------------------------------------------------
function MemberRename:Declined(old, new)
    return store().declined[pairKey(old, new)] ~= nil
end

function MemberRename:Accepted(old, new)
    return session().accepted[pairKey(old, new)] == true
end

GuildOS.Dialogs["GUILDOS_MEMBER_RENAME"] = {
    text = "%s",
    button1 = L["Move"],
    button2 = L["Not the same"],
    OnAccept = function(_, data)
        if data then GuildOS:SafeCall(MemberRename.Answer, MemberRename, data.old, data.new, true) end
    end,
    OnCancel = function(_, data)
        if data then GuildOS:SafeCall(MemberRename.Answer, MemberRename, data.old, data.new, false) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function MemberRename.Question(old, new)
    return string.format(L["%s looks like %s renamed. Move %s's history, alt links, ban and marks to the new name?"],
        short(new), short(old), short(old))
end

-- Asks the officer about a likely rename: once a session for the pair, through the popup queue.
function MemberRename:Propose(old, new)
    local st, pk = session(), pairKey(old, new)
    if st.asked[pk] or not GuildOS:IsOfficer() then return false end
    st.asked[pk] = true
    GuildOS:ShowWhenClear("memberrename", function()
        if MemberRename:Declined(old, new) or MemberRename:Accepted(old, new) then return nil end
        return GuildOS:ShowDialog("GUILDOS_MEMBER_RENAME", MemberRename.Question(old, new), nil, { old = old, new = new })
    end)
    return true
end

-- The officer's answer. Yes: everything moves, and the roster last seen follows; no: remembered. Either way the
-- next diff runs soon.
function MemberRename:Answer(old, new, yes)
    local pk = pairKey(old, new)
    if yes then
        session().accepted[pk] = true
        self:Apply(old, new, "guess")
        local base = GuildOS.db and GuildOS.db.memberHistoryBase
        local m = type(base) == "table" and type(base.m) == "table" and base.m
        if m and m[old] then
            m[new] = m[new] or m[old]
            m[old] = nil
        end
    else
        store().declined[pk] = GetServerTime()
    end
    if GuildOS.MemberHistory then GuildOS.MemberHistory:Schedule() end
end

----------------------------------------------------------------------
-- The move
----------------------------------------------------------------------
local function moveKey(t, old, new)
    if type(t) ~= "table" or t[old] == nil then return false end
    if t[new] == nil then t[new] = t[old] end
    t[old] = nil
    return true
end

local function byTime(a, b)
    return (a.joinAt or a.leftAt or a.at or 0) < (b.joinAt or b.leftAt or b.at or 0)
end

-- The member's history: the old key's record becomes the new one's; what the new key already held joins it.
function MemberRename.MoveHistory(h, old, new)
    if type(h) ~= "table" or type(h[old]) ~= "table" then return false end
    local from, into = h[old], h[new]
    h[old] = nil
    if type(into) ~= "table" then h[new] = from; return true end
    for _, list in ipairs({ "stints", "ranks" }) do
        local merged = {}
        for _, x in ipairs(type(from[list]) == "table" and from[list] or {}) do merged[#merged + 1] = x end
        for _, x in ipairs(type(into[list]) == "table" and into[list] or {}) do merged[#merged + 1] = x end
        table.sort(merged, byTime)
        into[list] = merged
    end
    local fn, inn = type(from.note) == "table" and from.note, type(into.note) == "table" and into.note
    if fn and (not inn or (tonumber(fn.rev) or 0) > (tonumber(inn.rev) or 0)) then into.note = fn end
    into.cls = into.cls or from.cls
    local MH = GuildOS.MemberHistory
    if MH then
        while #into.stints > MH.MAX_STINTS do table.remove(into.stints, 1) end
        while #into.ranks > MH.MAX_RANKS do table.remove(into.ranks, 1) end
    end
    return true
end

-- Every store kept by the old key, onto the new one. `how`: "guid" or "guess" (the officer said yes). Returns the
-- list of what moved (store names, for the tests and the debug log).
function MemberRename:Apply(old, new, how)
    if type(old) ~= "string" or type(new) ~= "string" or old == new or not GuildOS.db then return {} end
    local db, moved, officer = GuildOS.db, {}, GuildOS:IsOfficer()
    local function did(name) moved[#moved + 1] = name end
    local SC = function(fn, ...) local ok, r = pcall(fn, ...); return ok and r end

    if MemberRename.MoveHistory(db.memberHistory, old, new) then did("history") end
    if moveKey(db.firstSeen, old, new) then did("firstSeen") end
    if moveKey(db.foundingJoins, old, new) then did("founding") end
    if moveKey(db.members, old, new) then did("members") end
    if moveKey(db.raiders, old, new) then did("raiders") end

    -- The alt links (synced per link, AltSync): the same plan the player's own rename uses.
    local links = db.altLinks or {}
    local heads = links[old] ~= nil
    if not heads then
        for _, m in pairs(links) do if m == old then heads = true; break end end
    end
    if heads and officer and GuildOS.AltAutoDetect then
        local planned = GuildOS.AltAutoDetect.PlanRename(links, old, new)
        if GuildOS.AltSync then SC(GuildOS.AltSync.Commit, GuildOS.AltSync, planned) else db.altLinks = planned end
        did("alts")
    end

    -- The ban (domain "ban", per-key revision): the new name banned the same way, the old key's lifted.
    local BL = GuildOS.BanList
    if BL and officer and type(db.banList) == "table" then
        local ok, nk = BL:_NormalizeKey(old), BL:_NormalizeKey(new)
        local e = db.banList[ok]
        if type(e) == "table" and not e.removed and ok ~= nk then
            local copy = {}
            for f, v in pairs(e) do copy[f] = v end
            copy.name = BL:_Who(new)
            copy.ts = math.max(GetServerTime(), (tonumber(e.ts) or 0) + 1)
            db.banList[nk] = copy
            SC(BL._Publish, BL, nk, copy)
            SC(BL.RemoveKey, BL, ok)
            did("ban")
        end
    end

    -- The safe mark and the nickname (domain "marks", newest wins, tombstones).
    local MM = GuildOS.MemberMarks
    if MM and officer then
        if MM:IsMarkedSafe(old) then
            SC(MM.SetSafe, MM, new, true, MM:SafeUntil(old)); SC(MM.SetSafe, MM, old, false); did("safe")
        end
        local nick = MM:Nick(old)
        if nick then
            if not MM:Nick(new) then SC(MM.SetNick, MM, new, nick) end
            SC(MM.SetNick, MM, old, ""); did("nick")
        end
    end

    -- The officers' dated notes (this client's list) and the sheet (domain "osheet").
    local ON = GuildOS.OfficerNotes
    local notes = db.officerNotes
    if type(notes) == "table" and type(notes[old]) == "table" then
        local from = notes[old]
        local sheet = ON and officer and ON:GetSheet(old)
        local into = notes[new]
        if type(into) ~= "table" then
            notes[new] = { notes = from.notes or {}, tags = from.tags or {} }
        else
            into.notes = type(into.notes) == "table" and into.notes or {}
            for _, n in ipairs(from.notes or {}) do into.notes[#into.notes + 1] = n end
            table.sort(into.notes, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
        end
        if sheet and not ON:GetSheet(new) then SC(ON.SetSheet, ON, new, sheet.text) end
        if sheet then
            SC(ON.SetSheet, ON, old, "")
            notes[old] = { notes = {}, tags = {}, sheet = notes[old].sheet }   -- the emptied sheet stays as a tombstone
        else
            notes[old] = nil
        end
        did("officerNotes")
    end

    -- The trial (domains "trial"/"trialg"): the new key's, the old one's a tombstone.
    if type(db.trials) == "table" and type(db.trials[old]) == "table" then
        if db.trials[new] == nil then db.trials[new] = db.trials[old] end
        db.trials[old] = nil
        if type(db.trialTombs) ~= "table" then db.trialTombs = {} end
        db.trialTombs[old] = GetServerTime()
        local TT = GuildOS.TrialTracker
        if TT and TT.BroadcastTrials then SC(TT.BroadcastTrials, TT, new); SC(TT.BroadcastTrials, TT, old) end
        did("trial")
    end

    -- The birthday (domain "birthday", newest `at` wins): written under the new key, a tombstone under the old.
    local BD = GuildOS.Birthdays
    local b = type(db.birthdays) == "table" and db.birthdays[old]
    if type(b) == "table" and not b.off and BD and BD._Write then
        local at = math.max(GetServerTime(), (tonumber(b.at) or 0) + 1)
        local by = b.by
        local writes = { { key = old, e = { off = true, at = at, by = by } } }
        local held = db.birthdays[new]
        if type(held) ~= "table" or held.off then
            table.insert(writes, 1, { key = new, e = { d = b.d, m = b.m, at = at, by = by } })
        end
        SC(BD._Write, BD, writes)
        did("birthday")
    end

    -- Raid attendance (this client's sessions and the attendance worked out from them).
    local rt = db.raidTracker
    if type(rt) == "table" then
        local any = false
        for _, sess in ipairs(type(rt.sessions) == "table" and rt.sessions or {}) do
            if type(sess) == "table" and moveKey(sess.players, old, new) then any = true end
        end
        for _, group in pairs(type(rt.attendance) == "table" and rt.attendance or {}) do
            if moveKey(group, old, new) then any = true end
        end
        if any then did("attendance") end
    end

    -- The audit log's line, this client's (every officer's client sees the same diff).
    if GuildOS.RosterLog then
        GuildOS.RosterLog:_Insert({ action = "rename", target = GuildOS.RosterLog:_NormShort(new),
            detail = string.format(L["renamed from %s"], short(old)), timestamp = GetServerTime(), loc = true,
            rename = how })
        GuildOS.RosterLog:Refresh()
    end
    if GuildOS.Logger and GuildOS.Logger.Debug then
        GuildOS.Logger.Debug("rename " .. old .. " > " .. new .. " (" .. tostring(how) .. "): " .. table.concat(moved, ", "))
    end
    return moved
end
