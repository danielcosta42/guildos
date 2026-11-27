----------------------------------------------------------------------
-- Guild OS - Officers' marks on members: the safe list and nicknames (issue #429, epic #423 group F)
--
-- The safe list: a member an officer marked by hand, or whose public or officer note holds the safe tag
-- ("[safe]" by default, the officers' choice), is never put in a bulk removal or demotion (BulkActions,
-- #420), neither in the preview nor when their click comes. A promotion still may.
--
-- A nickname: what the officers call a member ("Big Bob" for Bobthetank), shown on the roster's tooltip
-- and, with Chat Tweaks on, before their lines in chat.
--
-- Both are the officers' word and every officer's client keeps them: one entry per member and kind,
-- { v, at, by }, the later `at` winning (server time), a cleared one kept as a tombstone so an old copy
-- does not bring it back. Synced over the officer domain "marks" (SyncService: officers only, and only
-- over the game's OFFICER addon channel, as the officer sheet (#427): a member's client never gets the
-- bytes): sent at once on a change, and every entry again at login in spaced batches, like the alt links
-- (#424). Applied on officers' clients only. On a client without that channel (Compat.OfficerAddonChannel)
-- nothing is sent: the marks stay on the client of the officer who wrote them.
--
-- A tombstone goes after TOMBSTONE_TTL, but its time stays for good in `rev` (audit N6, as AltSync keeps its
-- revisions): an officer's copy older than it, sent months later, never brings a removed mark back.
--
-- A safe mark may have an end (`u`, a server time: "safe for 14 days", "until 15/01"; none: for good). From then
-- on it no longer counts anywhere (IsMarkedSafe: the bulk actions, the inactivity count, the digest), and the
-- next Prune drops it, its time kept in `rev` like a tombstone's, so a copy of it never comes back. On the wire
-- the end is one more field, `u`: a client older than it ignores the field (to it the mark is for good), and
-- this one refuses an entry whose `u` is no plausible time.
--
--   db.memberMarks = { safe = { [key] = { v = true|false, at, by, u = until|nil } },
--                      nick = { [key] = { v = "text"|"", at, by } },
--                      rev = { safe = { [key] = at }, nick = { [key] = at } } }
----------------------------------------------------------------------
local MemberMarks = {}
GuildOS.MemberMarks = MemberMarks
local L = GuildOS.L

MemberMarks.DOMAIN = "marks"
MemberMarks.KINDS = { safe = true, nick = true }
MemberMarks.DEFAULT_TAG = "[safe]"
MemberMarks.TAG_MAX = 16          -- bytes of the safe tag: room in a 31-byte note for something else
MemberMarks.NICK_MAX = 24         -- bytes of a nickname
MemberMarks.BATCH = 40            -- entries per envelope of the login backfill
MemberMarks.BATCH_GAP = 2         -- seconds between them (#324)
MemberMarks.TOMBSTONE_TTL = 90 * 86400
local KEY_MAX = 80                -- bytes of a key off the network
local BY_MAX = 48                 -- bytes of an author off the network
local FUTURE_SLACK = 300          -- a time off the network may run this far past this client's clock
MemberMarks.UNTIL_MAX = 5 * 365 * 86400   -- a safe mark's end is at most this far ahead of its time
MemberMarks.DURATIONS = { 7, 14, 30 }     -- the screen's "safe for N days"
local DAY = 86400

local function store()
    local d = GuildOS.db
    if type(d) ~= "table" then return { safe = {}, nick = {} } end
    if type(d.memberMarks) ~= "table" then d.memberMarks = {} end
    local s = d.memberMarks
    if type(s.safe) ~= "table" then s.safe = {} end
    if type(s.nick) ~= "table" then s.nick = {} end
    if type(s.rev) ~= "table" then s.rev = {} end
    if type(s.rev.safe) ~= "table" then s.rev.safe = {} end
    if type(s.rev.nick) ~= "table" then s.rev.nick = {} end
    return s
end

-- The last time known for `kind` and `key`: the entry's, or the pruned tombstone's kept in `rev`. 0 when none.
local function lastAt(s, kind, key)
    local e = s[kind][key]
    if type(e) == "table" and type(e.at) == "number" then return e.at end
    return tonumber(s.rev[kind][key]) or 0
end

function MemberMarks:Initialize()
    if GuildOS.SyncService then
        GuildOS.SyncService:On(self.DOMAIN, function(env, sender) MemberMarks:OnSync(env, sender) end)
    end
    self:Prune()
end

----------------------------------------------------------------------
-- Pure (tools/member-marks.lua)
----------------------------------------------------------------------
--- Whether `note` or `onote` holds `tag`, capitals aside. An empty tag is no tag.
function MemberMarks.NoteHasTag(note, onote, tag)
    if type(tag) ~= "string" or tag == "" then return false end
    tag = tag:lower()
    for _, n in ipairs({ note or "", onote or "" }) do
        if type(n) == "string" and n:lower():find(tag, 1, true) then return true end
    end
    return false
end

--- Whether entry `e` replaces `held`: the later time wins; at the same time, the same answer on every client (the
--- later end last: an older client's copy of a mark, without its end, never takes the end away).
function MemberMarks.Wins(e, held)
    if not held then return true end
    if e.at ~= held.at then return e.at > held.at end
    local a = tostring(e.v) .. "\0" .. (e.by or "")
    local b = tostring(held.v) .. "\0" .. (held.by or "")
    if a ~= b then return a > b end
    return (e.u or 0) > (held.u or 0)
end

--- Whether safe entry `e` counts at `now`: marked, and its end (if it has one) not reached.
function MemberMarks.Active(e, now)
    if type(e) ~= "table" or e.v ~= true then return false end
    return e.u == nil or (now ~= nil and e.u > now)
end

--- The end a choice of the screen means: "forever" (nil), "7", "14", "30" (days from `now`, to the end of that day
--- on this client's clock) or "date" with `text` a date the notes' parser reads ("15/01/2027", "2027-01-15",
--- "15 Jan 2027"), to its last minute. Returns the time, or nil and "forever"; or nil and "bad" (no date, or one not
--- after now).
function MemberMarks.UntilOf(choice, text, now, order)
    now = now or GetServerTime()
    if choice == nil or choice == "forever" or choice == "" then return nil, "forever" end
    local days = tonumber(choice)
    if days then
        if days < 1 or days > 3650 then return nil, "bad" end
        local d = date("*t", now + math.floor(days) * DAY)
        return time({ year = d.year, month = d.month, day = d.day, hour = 23, min = 59, sec = 0 })
    end
    local ND = GuildOS.NoteDates
    if choice ~= "date" or not ND then return nil, "bad" end
    local day = ND.Parse(text or "", order or ND:Order())
    if not day then return nil, "bad" end
    local t = time({ year = day.year, month = day.month, day = day.day, hour = 23, min = 59, sec = 0 })
    if t <= now or t > now + MemberMarks.UNTIL_MAX then return nil, "bad" end
    return t
end

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------
--- The safe tag the officers chose ("" turns it off).
function MemberMarks:SafeTag()
    local t = GuildOS:GetSetting("safeTag")
    if type(t) ~= "string" then return self.DEFAULT_TAG end
    return t
end

--- Officers only. The tag is cut to TAG_MAX bytes and loses UI escapes; "" turns it off. Whether it changed.
function MemberMarks:SetSafeTag(tag)
    if not GuildOS:IsOfficer() or type(tag) ~= "string" then return false end
    GuildOS:SetSetting("safeTag", GuildOS:SanitizeUserText(tag, self.TAG_MAX))
    return true
end

--- Whether an officer marked the member safe by hand, and the mark has not reached its end (`now`: the server's).
function MemberMarks:IsMarkedSafe(key, now)
    local e = key and store().safe[key]
    if type(e) ~= "table" or e.v ~= true then return false end
    return e.u == nil or e.u > (now or GetServerTime())
end

--- When the member's safe mark ends, or nil (for good, or not marked).
function MemberMarks:SafeUntil(key)
    local e = key and store().safe[key]
    if type(e) == "table" and e.v == true then return e.u end
    return nil
end

--- Whether the member is on the safe list: marked by hand, or the tag in either note (as the roster gave them now).
function MemberMarks:IsSafe(key, note, onote)
    return self:IsMarkedSafe(key) or self.NoteHasTag(note, onote, self:SafeTag())
end

--- The keys marked safe by hand, sorted; a mark past its end is not one (and is dropped here, lazily).
function MemberMarks:SafeKeys()
    local now = GetServerTime()
    self:Prune(now)
    local out = {}
    for k, e in pairs(store().safe) do
        if self.Active(e, now) then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

--- The member's nickname, or nil; nil too on a client that is no officer's now (one demoted keeps the old store).
function MemberMarks:Nick(key)
    if not GuildOS:IsOfficer() then return nil end
    local e = key and store().nick[key]
    if type(e) == "table" and type(e.v) == "string" and e.v ~= "" then return e.v end
    return nil
end

----------------------------------------------------------------------
-- Writing (officers)
----------------------------------------------------------------------
local function wire(kind, key, e)
    return { s = kind, k = key, v = e.v, t = e.at, b = e.by, u = e.u }
end

local function publish(items)
    local SS = GuildOS.SyncService
    if not SS or #items == 0 then return end
    SS:Publish(MemberMarks.DOMAIN, "set", { items = items }, { priority = "BULK" })
end

-- One entry of `kind` for `key`, as this officer's, now; published. `u`: a safe mark's end.
function MemberMarks:_Write(kind, key, v, u)
    if not GuildOS:IsOfficer() or not self.KINDS[kind] or type(key) ~= "string" or key == "" then return false end
    local s = store()
    local list = s[kind]
    local at = GetServerTime()
    local last = lastAt(s, kind, key)
    if last >= at then at = last + 1 end
    local e = { v = v, at = at, by = GuildOS.Compat.PlayerName(), u = (kind == "safe" and v == true) and u or nil }
    list[key] = e
    publish({ wire(kind, key, e) })
    self:Refresh()
    return true
end

--- Mark or unmark the member safe; `untilT` (optional, a server time in the future) is when the mark ends, none for
--- good. Marking again with another end changes it. Officers only. Whether it changed.
function MemberMarks:SetSafe(key, on, untilT)
    on = on and true or false
    local now = GetServerTime()
    untilT = GuildOS.Finite(untilT)
    if not on then untilT = nil end
    if untilT and (untilT <= now or untilT > now + self.UNTIL_MAX) then return false end
    local marked = self:IsMarkedSafe(key, now)
    if marked == on and (not on or self:SafeUntil(key) == untilT) then return false end
    return self:_Write("safe", key, on, untilT)
end

--- Set the member's nickname ("" or nil clears it). Officers only. Whether it changed.
function MemberMarks:SetNick(key, text)
    local v = GuildOS:SanitizeUserText(text or "", self.NICK_MAX)
    if (self:Nick(key) or "") == v then return false end
    return self:_Write("nick", key, v)
end

--- Drop tombstones older than TOMBSTONE_TTL, and safe marks past their end. Their time stays in `rev` (audit N6).
function MemberMarks:Prune(now)
    now = now or (GetServerTime and GetServerTime()) or 0
    local s = store()
    for kind in pairs(self.KINDS) do
        for k, e in pairs(s[kind]) do
            local dead = type(e) ~= "table" or e.v == false or e.v == ""
            local ended = type(e) == "table" and e.v == true and type(e.u) == "number" and e.u <= now
            if ended or (dead and (type(e) ~= "table" or now - (e.at or 0) > self.TOMBSTONE_TTL)) then
                if type(e) == "table" and type(e.at) == "number" then
                    s.rev[kind][k] = math.max(tonumber(s.rev[kind][k]) or 0, e.at)
                end
                s[kind][k] = nil
            end
        end
    end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
--- An entry off the network ({ s, k, v, t, b, u }), checked field by field, as { kind, key, e }, or nil. `u`, a safe
--- mark's end, is optional (older clients send none); when there, a number after `t` and at most UNTIL_MAX past it,
--- or the entry is refused. On a cleared mark it means nothing and is dropped.
function MemberMarks.Valid(it, now, sender)
    if type(it) ~= "table" or not MemberMarks.KINDS[it.s] then return nil end
    local k = it.k
    if type(k) ~= "string" or k == "" or #k > KEY_MAX or k:find("|", 1, true) then return nil end
    local t = GuildOS.Finite(it.t)
    if not t or t <= 0 or t > now + FUTURE_SLACK then return nil end
    local v, u
    if it.s == "safe" then
        if type(it.v) ~= "boolean" then return nil end
        v = it.v
        if it.u ~= nil then
            u = type(it.u) == "number" and GuildOS.Finite(it.u) or nil
            if not u or u <= t or u > t + MemberMarks.UNTIL_MAX then return nil end
            u = math.floor(u)
            if not v then u = nil end
        end
    else
        if type(it.v) ~= "string" then return nil end
        v = GuildOS:SanitizeUserText(it.v, MemberMarks.NICK_MAX)
    end
    local by = (type(it.b) == "string" and it.b ~= "") and GuildOS:SanitizeUserText(it.b, BY_MAX) or sender
    return it.s, GuildOS:LocalMemberKey(k), { v = v, at = t, by = by, u = u }
end

--- Entries from an officer (SyncService checked the officer and the OFFICER channel): applied on an officer's client only. How many.
function MemberMarks:Apply(items, sender)
    if type(items) ~= "table" or not GuildOS:IsOfficer() then return 0 end
    local s, now, n = store(), GetServerTime(), 0
    for _, it in ipairs(items) do
        local kind, key, e = self.Valid(it, now, sender)
        -- No entry held: a pruned tombstone's time still refuses anything no newer (audit N6).
        if kind and s[kind][key] == nil and e.at <= (tonumber(s.rev[kind][key]) or 0) then kind = nil end
        if kind and self.Wins(e, s[kind][key]) then
            s[kind][key] = e
            n = n + 1
        end
    end
    if n > 0 then self:Prune(now) end   -- a mark that arrived already past its end goes at once, its time in rev
    return n
end

function MemberMarks:OnSync(env, sender)
    if env.act ~= "set" or type(env.data) ~= "table" then return end
    if self:Apply(env.data.items, sender) > 0 then self:Refresh() end
end

--- Every entry, tombstones included, in batches BATCH_GAP seconds apart: at login (CommSystem) and on /gos sync.
--- Officers only; one at a time.
function MemberMarks:Backfill()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService or self._backfilling then return end
    if not GuildOS.Compat.OfficerAddonChannel() then return end   -- the marks stay on this client
    self:Prune()   -- a mark past its end is not sent: its time stays in rev
    local s, items = store(), {}
    for kind in pairs(self.KINDS) do
        for k, e in pairs(s[kind]) do
            if type(e) == "table" then items[#items + 1] = wire(kind, k, e) end
        end
    end
    if #items == 0 then return end
    table.sort(items, function(a, b) return a.s .. a.k < b.s .. b.k end)
    self._backfilling = true
    local function send(i)
        local batch = {}
        for j = i, math.min(i + self.BATCH - 1, #items) do batch[#batch + 1] = items[j] end
        publish(batch)
        if items[i + self.BATCH] then
            GuildOS.Compat.After(self.BATCH_GAP, function() send(i + self.BATCH) end)
        else
            self._backfilling = nil
        end
    end
    send(1)
end

----------------------------------------------------------------------
-- What the roster's tooltip and the chat show
----------------------------------------------------------------------
--- The tooltip's lines for the member (officers): the nickname, and the safe list with why.
function MemberMarks:TooltipLines(tt, key, note, onote)
    if not (tt and key and GuildOS:IsOfficer()) then return end
    local nick = self:Nick(key)
    if nick then tt:AddLine(string.format(L["Nickname: %s"], nick), 1, 0.82, 0) end
    if self:IsMarkedSafe(key) then
        local u = self:SafeUntil(key)
        tt:AddLine(u and string.format(L["On the safe list until %s"], self:UntilDate(u)) or L["On the safe list"], 0.3, 0.9, 0.3)
    elseif self.NoteHasTag(note, onote, self:SafeTag()) then
        tt:AddLine(L["On the safe list (tag in the note)"], 0.3, 0.9, 0.3)
    end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
local function short(key) return key and (key:match("^([^-]+)") or key) or "?" end

--- A mark's end as a day: "15/01" in the language's order, the year after it when it is not this one.
function MemberMarks:UntilDate(u)
    if type(u) ~= "number" then return "" end
    local same = date("%Y", u) == date("%Y", GetServerTime())
    return GuildOS:DateText(u, (not same) and "/%Y" or nil)
end

--- How a mark's end reads: "until 15/01", or "" for good.
function MemberMarks:UntilText(u)
    if type(u) ~= "number" then return "" end
    return string.format(L["until %s"], self:UntilDate(u))
end

-- A duration word of the command: "7d", "14d", "30d" (any number of days) or a date; the end, or nil.
local function untilWord(word, now)
    local n = word and word:lower():match("^(%d+)d$")
    if n then return (MemberMarks.UntilOf(n, nil, now)) end
    return (MemberMarks.UntilOf("date", word, now))
end

--- `/gos safe [<name> [7d|14d|30d|<date>]]`: no name lists the safe list; a name marks or unmarks them (`untilT`, or
--- the word after the name, the end of a new mark). A name with an end always marks (a new end on a marked member).
function MemberMarks:CommandSafe(rest, untilT)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Only officers can do that."]) return end
    rest = strtrim(rest or "")
    if rest == "" then
        local keys = self:SafeKeys()
        local names = {}
        for i, k in ipairs(keys) do
            local u = self:SafeUntil(k)
            names[i] = short(k) .. (u and (" (" .. self:UntilText(u) .. ")") or "")
        end
        GuildOS:Print(#keys > 0 and string.format(L["Safe list (%d): %s"], #keys, table.concat(names, ", "))
            or L["Nobody is on the safe list by hand."])
        local tag = self:SafeTag()
        if tag ~= "" then GuildOS:Print(string.format(L["Members with %s in a note are safe too."], tag)) end
        return
    end
    local key = GuildOS:RosterKey(rest)
    local forced = false
    if not key then
        -- "<name> 14d": the whole text is no roster name (a WoW: Forever name has a space), its last word an end.
        local who, word = rest:match("^(.-)%s+(%S+)$")
        local u = who and who ~= "" and untilWord(word, GetServerTime())
        if u then key, untilT, forced = GuildOS:RosterKey(who), u, true end
    end
    if not key then GuildOS:Print(string.format(L["%s is not in the guild roster."], rest)) return end
    local on = forced or not self:IsMarkedSafe(key)
    self:SetSafe(key, on, on and untilT or nil)
    local u = on and self:SafeUntil(key)
    if on and u then
        GuildOS:Print(string.format(L["%s is on the safe list %s: never in a bulk removal or demotion."], short(key), self:UntilText(u)))
    else
        GuildOS:Print(string.format(on and L["%s is on the safe list: never in a bulk removal or demotion."]
            or L["%s is off the safe list."], short(key)))
    end
end

--- `/gos nick <name> [nickname]`: no nickname clears it. A WoW: Forever name has a space: the whole text as a
--- roster name first.
function MemberMarks:CommandNick(rest)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Only officers can do that."]) return end
    rest = strtrim(rest or "")
    if rest == "" then GuildOS:Print(L["Usage: /gos nick <name> [nickname]"]) return end
    local key, nick = GuildOS:RosterKey(rest), ""
    if not key then
        local who, text = GuildOS:SplitNameAndText(rest)
        key, nick = who and GuildOS:RosterKey(who), text or ""
    end
    if not key then GuildOS:Print(string.format(L["%s is not in the guild roster."], rest)) return end
    self:SetNick(key, nick)
    local now = self:Nick(key)
    GuildOS:Print(now and string.format(L["%s's nickname: %s"], short(key), now)
        or string.format(L["%s has no nickname."], short(key)))
end

function MemberMarks:Refresh()
    if GuildOS.ChatTweaks and GuildOS.ChatTweaks.Invalidate then GuildOS.ChatTweaks:Invalidate() end   -- the chat prefixes
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
