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
--   db.memberMarks = { safe = { [key] = { v = true|false, at, by } }, nick = { [key] = { v = "text"|"", at, by } },
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

--- Whether entry `e` replaces `held`: the later time wins; at the same time, the same answer on every client.
function MemberMarks.Wins(e, held)
    if not held then return true end
    if e.at ~= held.at then return e.at > held.at end
    return tostring(e.v) .. "\0" .. (e.by or "") > tostring(held.v) .. "\0" .. (held.by or "")
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

--- Whether an officer marked the member safe by hand.
function MemberMarks:IsMarkedSafe(key)
    local e = key and store().safe[key]
    return type(e) == "table" and e.v == true
end

--- Whether the member is on the safe list: marked by hand, or the tag in either note (as the roster gave them now).
function MemberMarks:IsSafe(key, note, onote)
    return self:IsMarkedSafe(key) or self.NoteHasTag(note, onote, self:SafeTag())
end

--- The keys marked safe by hand, sorted.
function MemberMarks:SafeKeys()
    local out = {}
    for k, e in pairs(store().safe) do
        if type(e) == "table" and e.v == true then out[#out + 1] = k end
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
    return { s = kind, k = key, v = e.v, t = e.at, b = e.by }
end

local function publish(items)
    local SS = GuildOS.SyncService
    if not SS or #items == 0 then return end
    SS:Publish(MemberMarks.DOMAIN, "set", { items = items }, { priority = "BULK" })
end

-- One entry of `kind` for `key`, as this officer's, now; published.
function MemberMarks:_Write(kind, key, v)
    if not GuildOS:IsOfficer() or not self.KINDS[kind] or type(key) ~= "string" or key == "" then return false end
    local s = store()
    local list = s[kind]
    local at = GetServerTime()
    local last = lastAt(s, kind, key)
    if last >= at then at = last + 1 end
    local e = { v = v, at = at, by = GuildOS.Compat.PlayerName() }
    list[key] = e
    publish({ wire(kind, key, e) })
    self:Refresh()
    return true
end

--- Mark or unmark the member safe. Officers only. Whether it changed.
function MemberMarks:SetSafe(key, on)
    if (self:IsMarkedSafe(key)) == (on and true or false) then return false end
    return self:_Write("safe", key, on and true or false)
end

--- Set the member's nickname ("" or nil clears it). Officers only. Whether it changed.
function MemberMarks:SetNick(key, text)
    local v = GuildOS:SanitizeUserText(text or "", self.NICK_MAX)
    if (self:Nick(key) or "") == v then return false end
    return self:_Write("nick", key, v)
end

--- Drop tombstones older than TOMBSTONE_TTL. Their time stays in `rev` (audit N6).
function MemberMarks:Prune(now)
    now = now or (GetServerTime and GetServerTime()) or 0
    local s = store()
    for kind in pairs(self.KINDS) do
        for k, e in pairs(s[kind]) do
            local dead = type(e) ~= "table" or e.v == false or e.v == ""
            if dead and (type(e) ~= "table" or now - (e.at or 0) > self.TOMBSTONE_TTL) then
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
--- An entry off the network ({ s, k, v, t, b }), checked field by field, as { kind, key, e }, or nil.
function MemberMarks.Valid(it, now, sender)
    if type(it) ~= "table" or not MemberMarks.KINDS[it.s] then return nil end
    local k = it.k
    if type(k) ~= "string" or k == "" or #k > KEY_MAX or k:find("|", 1, true) then return nil end
    local t = GuildOS.Finite(it.t)
    if not t or t <= 0 or t > now + FUTURE_SLACK then return nil end
    local v
    if it.s == "safe" then
        if type(it.v) ~= "boolean" then return nil end
        v = it.v
    else
        if type(it.v) ~= "string" then return nil end
        v = GuildOS:SanitizeUserText(it.v, MemberMarks.NICK_MAX)
    end
    local by = (type(it.b) == "string" and it.b ~= "") and GuildOS:SanitizeUserText(it.b, BY_MAX) or sender
    return it.s, GuildOS:LocalMemberKey(k), { v = v, at = t, by = by }
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
        tt:AddLine(L["On the safe list"], 0.3, 0.9, 0.3)
    elseif self.NoteHasTag(note, onote, self:SafeTag()) then
        tt:AddLine(L["On the safe list (tag in the note)"], 0.3, 0.9, 0.3)
    end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
local function short(key) return key and (key:match("^([^-]+)") or key) or "?" end

--- `/gos safe [<name>]`: no name lists the safe list; a name marks or unmarks them.
function MemberMarks:CommandSafe(rest)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Only officers can do that."]) return end
    rest = strtrim(rest or "")
    if rest == "" then
        local keys = self:SafeKeys()
        local names = {}
        for i, k in ipairs(keys) do names[i] = short(k) end
        GuildOS:Print(#keys > 0 and string.format(L["Safe list (%d): %s"], #keys, table.concat(names, ", "))
            or L["Nobody is on the safe list by hand."])
        local tag = self:SafeTag()
        if tag ~= "" then GuildOS:Print(string.format(L["Members with %s in a note are safe too."], tag)) end
        return
    end
    local key = GuildOS:RosterKey(rest)
    if not key then GuildOS:Print(string.format(L["%s is not in the guild roster."], rest)) return end
    local on = not self:IsMarkedSafe(key)
    self:SetSafe(key, on)
    GuildOS:Print(string.format(on and L["%s is on the safe list: never in a bulk removal or demotion."]
        or L["%s is off the safe list."], short(key)))
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
