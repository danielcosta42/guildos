----------------------------------------------------------------------
-- Guild OS - Somebody left or was removed: the officers' popup, and who comes back (issue #449; a supporter's
-- suggestion, specs/salao/saidas.md)
--
-- Departure: on every officer's client, whoever leaves or is removed (the Roster Log's reading of the game's line,
-- or MemberHistory's roster diff when nobody saw the line) is one "happening": the same member within SAME seconds
-- is the same one, whichever way it was seen first (the rule of the Salão's activity, UI/Agora.lua ROSTER_SAME); a
-- removal's line after a diff only names the officer who removed them. The happenings wait in a list, shown one at a
-- time in a small window (UI/DeparturePopup.lua) through GuildOS:ShowWhenClear, never in combat, "1 of 3" when
-- several left at once. For each one the officer may:
--   * remove the player's other characters (the alt links, GuildOS:GetLinkedChars) still in the guild: a queue of
--     Bulk actions, one member per click of its Next (ADR-0038); where the game takes no removal from an addon at
--     all (WoW: Forever, Compat.SecureGuildMacro), the /gremove lines to copy, never typed by the addon;
--   * write a permanent officer note (MemberHistory:SetNote: kept with the member's history, over the officers'
--     channel only, never to a member's client);
--   * ban the player for good or suspend them for N days (BanList:AddGroup, the whole group of characters), which
--     then warns on an invite and on a join as any ban does.
-- Saving tells the other officers ("dh" on the audit domain, no free text in it): their window says "Handled by
-- <officer>" and the happening leaves their list. A switch turns the popup off (Officers' Room › Safe list and
-- nicknames). Nothing here removes or bans anybody without the officer's click.
--
-- Welcome back: somebody the history knows as a former member joins: officers get a notice (date they left, days
-- away, days they had been a member, the permanent note) or, banned or suspended, a warning in its place
-- (Departure:OnReturn); the guild welcome takes the officers' "for members who return" list (RecruitmentSystem).
--
--   db.departure = { handled = { [memberKey] = { at, by, ts, f, d } } }   -- claims kept HANDLED_KEEP seconds
--   GuildOS.State.departure = { list = { happening... }, byKey = {} }       -- this session's happenings
----------------------------------------------------------------------
local Departure = {}
GuildOS.Departure = Departure
local L = GuildOS.L

Departure.SAME = 15 * 60               -- seconds: the same departure seen twice (UI/Agora.lua ROSTER_SAME)
Departure.HANDLED_KEEP = 30 * 86400    -- a claim is kept this long (the login backfill re-sends the newest)
Departure.HANDLED_MAX = 60
Departure.BACKFILL_N = 15
Departure.SUSPEND_MAX = 365            -- days
Departure.LIST_MAX = 30                -- happenings waiting at most; the oldest goes first
Departure.LINGER = 4                   -- seconds the "Handled by" line stays before the window moves on
local KEY_MAX = 64

local function now() return GetServerTime() end
local function short(key) return key and (key:match("^([^-]+)") or key) or "?" end

local function state()
    GuildOS.State.departure = GuildOS.State.departure or { list = {}, byKey = {} }
    return GuildOS.State.departure
end

local function store()
    local db = GuildOS.db
    if not db then return nil end
    db.departure = type(db.departure) == "table" and db.departure or {}
    db.departure.handled = type(db.departure.handled) == "table" and db.departure.handled or {}
    return db.departure
end

function Departure:Initialize()
    store()
    self:Prune()
end

----------------------------------------------------------------------
-- The switch
----------------------------------------------------------------------
--- Whether the popup is on (the default) on this client.
function Departure:Enabled()
    return GuildOS:GetSetting("departurePopup") ~= false
end

function Departure:SetEnabled(on)
    GuildOS:SetSetting("departurePopup", on and true or false)
    if not on then
        local s = state()
        s.list, s.byKey = {}, {}
        if GuildOS.CancelWhenClear then GuildOS:CancelWhenClear("departure") end
        self:Redraw()
    end
end

--- Whether this client asks: an officer, in the guild whose db is loaded, the switch on.
function Departure:MayAsk()
    return self:Enabled() and GuildOS:IsOfficer() and GuildOS:IsOnGuildDB()
end

----------------------------------------------------------------------
-- Happenings
----------------------------------------------------------------------
local function meKey() return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) end

-- A claim held for `key` that covers a departure at `t`.
local function handledFor(key, t)
    local s = store()
    local c = s and s.handled[key]
    if type(c) ~= "table" then return nil end
    if math.abs((tonumber(c.at) or 0) - t) <= Departure.SAME then return c end
    return nil
end

--- A departure of `key` at `t`: `how` "leave", "kick" (by `by`) or "gone" (the roster diff). Returns the happening
--- and whether it is a new one (a second sighting of the same one returns it with false). Nil when it is not asked
--- about: not an officer, the switch off, this character, or already handled by an officer.
function Departure:Take(key, how, by, t)
    if type(key) ~= "string" or key == "" or not self:MayAsk() then return nil end
    if key == meKey() then return nil end
    t = tonumber(t) or now()
    if handledFor(key, t) then return nil end
    local s = state()
    local h = s.byKey[key]
    if h and math.abs(h.at - t) <= self.SAME then
        -- The same departure: a removal's line names the officer a diff could not see.
        if how == "kick" and h.how ~= "kick" then
            h.how, h.by = "kick", by
            self:Redraw()
        end
        return h, false
    end
    h = { key = key, name = short(key), how = how or "gone", by = by, at = t }
    s.list[#s.list + 1] = h
    s.byKey[key] = h
    while #s.list > self.LIST_MAX do
        local old = table.remove(s.list, 1)
        if s.byKey[old.key] == old then s.byKey[old.key] = nil end
    end
    self.lastTaken = h   -- the tests read it
    self:Show()
    return h, true
end

--- The Roster Log read the game's line (RosterLog's detection): a leave or a removal.
function Departure:OnRosterEvent(evt)
    if type(evt) ~= "table" or (evt.action ~= "leave" and evt.action ~= "kick") or type(evt.target) ~= "string" then return end
    return self:Take(GuildOS:KeyOfRosterName(evt.target), evt.action, evt.action == "kick" and evt.author or nil, evt.timestamp)
end

--- The roster diff found `key` gone (MemberHistory:Scan): nobody saw the game's line on this client.
function Departure:OnGone(key, t)
    return self:Take(key, "gone", nil, t)
end

--- The happenings still waiting for an answer here, oldest first.
function Departure:Pending()
    local out = {}
    for _, h in ipairs(state().list) do
        if not h.done then out[#out + 1] = h end
    end
    return out
end

--- What the window shows: the waiting ones, and one another officer just handled while it was on screen.
function Departure:Shown()
    local out = {}
    for _, h in ipairs(state().list) do
        if not h.done or (h.handledBy and not h.gone) then out[#out + 1] = h end
    end
    return out
end

-- The happening leaves the list.
local function drop(h)
    local s = state()
    for i, x in ipairs(s.list) do
        if x == h then table.remove(s.list, i) break end
    end
    if s.byKey[h.key] == h then s.byKey[h.key] = nil end
end

--- "Dismiss": this officer's window lets it go; the other officers still have theirs.
function Departure:Dismiss(h)
    if not h then return end
    h.done, h.gone = true, true
    drop(h)
    self:Redraw()
end

--- Queue the window (never in combat, one popup at a time); a window already up is redrawn in place.
function Departure:Show()
    if not GuildOS.ShowDeparturePopup then return end
    GuildOS:ShowWhenClear("departure", function() return GuildOS:ShowDeparturePopup() end)
end

function Departure:Redraw()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- The player's characters
----------------------------------------------------------------------
-- A class for a key the roster no longer has: the member row while it lasts, then the history's.
local function classOf(key)
    local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    if type(m) == "table" and type(m.class) == "string" and m.class ~= "" then return m.class end
    local MH = GuildOS.MemberHistory
    return MH and MH.ClassOf and MH:ClassOf(key) or nil
end

--- The characters of the player who left (the alt links: main first, then the alts by name), each
--- { key, name, class, inGuild, checked, me }: in the guild now (the live roster, never the one who left) and ticked
--- for removal when they are, this character never.
function Departure:Linked(h)
    if not h then return {} end
    local group = GuildOS:GetLinkedChars(h.key)
    local BA = GuildOS.BulkActions
    local roster = {}
    for _, m in ipairs(BA and BA:Collect(false) or {}) do roster[m.key] = m end
    local me = meKey()
    local out = {}
    for i, k in ipairs(group) do
        local m = k ~= h.key and roster[k] or nil
        out[#out + 1] = {
            key = k, name = m and m.name or short(k), class = (m and m.class ~= "" and m.class) or classOf(k),
            inGuild = m ~= nil, me = k == me, main = i == 1 and #group > 1 or nil,
            checked = m ~= nil and k ~= me,
        }
    end
    local main = table.remove(out, 1)
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    table.insert(out, 1, main)
    return out
end

--- A name in its class colour (the window's dark body), plain without a class.
function Departure.Colored(c)
    local name = c.name or short(c.key)
    if c.class and c.class ~= "" then return "|cff" .. GuildOS:GetClassColorHex(c.class) .. name .. "|r" end
    return name
end

--- The window's header: "Ana left the guild" or "Ana was removed by Bob".
function Departure.Header(h)
    if h.how == "kick" then
        return h.by and string.format(L["%s was removed by %s"], h.name, h.by) or string.format(L["%s was removed from the guild"], h.name)
    elseif h.how == "leave" then
        return string.format(L["%s left the guild"], h.name)
    end
    return string.format(L["%s is no longer in the guild"], h.name)
end

----------------------------------------------------------------------
-- The answers
----------------------------------------------------------------------
--- "Remove selected": the characters of `keys` still in the guild, into the removal queue of Bulk actions (one per
--- click of its Next). Where the game takes no removal from an addon (WoW: Forever) the /gremove lines come back
--- for the officer to copy. Returns "queued", or "typed" and the lines, or false and why (BulkActions:WhyText's).
function Departure:Remove(h, keys)
    local BA = GuildOS.BulkActions
    if not (h and BA) then return false, "action" end
    if not BA:Allowed("remove") then return false, "permission" end
    local me = meKey()
    local want = {}
    for _, k in ipairs(keys or {}) do
        if k ~= me and k ~= h.key then want[#want + 1] = k end
    end
    local list = BA:ListFor(want)
    if #list == 0 then return false, "listEmpty" end
    if not GuildOS.Compat.SecureGuildMacro() then
        local lines = {}
        for _, m in ipairs(list) do
            local line = GuildOS.Compat.GuildRankCommand("remove", m.fullName)
            if line then lines[#lines + 1] = line end
        end
        if #lines == 0 then return false, "listEmpty" end
        return "typed", lines
    end
    local ok, why = BA:StartList("remove", list)
    if ok then return "queued" end
    return false, why
end

-- The ban's reason, as the ban list shows it.
local function reasonFor(flag, days)
    if flag == "suspend" then return string.format(L["Suspended for %d days when they left"], days) end
    return L["Banned when they left"]
end

--- "Save": `opts` = { note, flag = nil | "ban" | "suspend", days }. The note goes to the member's history (synced to
--- officers only), the flag bans the player's whole group of characters (for good, or `days`), and the other
--- officers are told it is handled. Returns true and what was done ({ note, banned }), or false and why ("officer",
--- "days", "nothing").
function Departure:Save(h, opts)
    if not h or not GuildOS:IsOfficer() then return false, "officer" end
    opts = opts or {}
    local flag = (opts.flag == "ban" or opts.flag == "suspend") and opts.flag or nil
    local days
    if flag == "suspend" then
        days = GuildOS.Finite(opts.days)
        days = days and math.floor(days)
        if not days or days < 1 or days > self.SUSPEND_MAX then return false, "days" end
    end
    local note = type(opts.note) == "string" and strtrim(opts.note) or ""
    local MH, BL = GuildOS.MemberHistory, GuildOS.BanList
    local did = {}
    if note ~= "" and MH and MH.SetNote then did.note = MH:SetNote(h.key, note) end
    if flag and BL then
        did.banned = BL:AddGroup(GuildOS:GetLinkedChars(h.key), reasonFor(flag, days), days, nil)
    end
    if not did.note and not did.banned and not opts.force then
        -- Nothing written and no flag: still handled, the officer looked at it.
        did.none = true
    end
    self:_Claim(h, flag, days)
    return true, did
end

-- This officer handled `h`: kept, sent to the other officers (the audit domain over GUILD: names and a flag, no
-- free text), and the happening leaves the list.
function Departure:_Claim(h, flag, days)
    local s = store()
    local me = GuildOS:ShortName(GuildOS.Compat.PlayerName())
    if s then
        s.handled[h.key] = { at = h.at, by = me, ts = now(), f = flag, d = days }
        self:Prune()
    end
    h.done, h.gone = true, true
    drop(h)
    if GuildOS.SyncService and GuildOS:IsOfficer() then
        GuildOS.SyncService:Publish("audit", "dh", { k = h.key, t = h.at, f = flag, d = days })
    end
    self:Redraw()
end

--- A claim checked field by field, or nil.
function Departure.ValidClaim(data, t0)
    if type(data) ~= "table" or type(data.k) ~= "string" or data.k == "" or #data.k > KEY_MAX or data.k:find("|", 1, true) then
        return nil
    end
    local at = GuildOS.Finite(data.t)
    if not at or at <= 0 or at > t0 + 300 then return nil end
    local f = (data.f == "ban" or data.f == "suspend") and data.f or nil
    local d = f == "suspend" and GuildOS.Finite(data.d) or nil
    return { k = GuildOS:LocalMemberKey(data.k), at = at, f = f, d = d and math.floor(d) or nil }
end

--- Another officer handled a departure (RosterLog routes the audit domain's "dh"; SyncService checked the officer
--- over GUILD). Kept on every officer's client; a window showing it says who, and moves on.
function Departure:OnHandled(data, sender)
    if not GuildOS:IsOfficer() then return end
    local c = self.ValidClaim(data, now())
    if not c or not c.k then return end
    local by = GuildOS:ShortName(sender or "?") or "?"
    local s = store()
    local held = s.handled[c.k]
    if not (type(held) == "table" and math.abs((tonumber(held.at) or 0) - c.at) <= self.SAME) then
        s.handled[c.k] = { at = c.at, by = by, ts = now(), f = c.f, d = c.d }
    end
    local h = state().byKey[c.k]
    if h and not h.done and math.abs(h.at - c.at) <= self.SAME then
        h.done, h.handledBy = true, by
        self:Redraw()
        -- The line stays a moment, then the happening goes and the window shows the next one (or closes).
        GuildOS.Compat.After(self.LINGER, function()
            h.gone = true
            drop(h)
            Departure:Redraw()
        end)
    end
end

--- The claims kept, the oldest gone past HANDLED_KEEP or HANDLED_MAX.
function Departure:Prune(t)
    local s = store()
    if not s then return 0 end
    t = t or now()
    local keep, n = {}, 0
    for k, c in pairs(s.handled) do
        if type(c) ~= "table" or (tonumber(c.ts) or 0) < t - self.HANDLED_KEEP then
            s.handled[k] = nil
            n = n + 1
        else
            keep[#keep + 1] = { k = k, ts = tonumber(c.ts) or 0 }
        end
    end
    table.sort(keep, function(a, b) return a.ts > b.ts end)
    for i = self.HANDLED_MAX + 1, #keep do
        s.handled[keep[i].k] = nil
        n = n + 1
    end
    return n
end

--- At login (the answer to a sync request, through RosterLog:Backfill): the newest claims again, so an officer who
--- was offline does not get a popup for what was handled.
function Departure:Backfill()
    local s = store()
    if not (s and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    local list = {}
    for k, c in pairs(s.handled) do
        if type(c) == "table" and c.at then list[#list + 1] = { k = k, c = c } end
    end
    table.sort(list, function(a, b) return (a.c.ts or 0) > (b.c.ts or 0) end)
    for i = 1, math.min(#list, self.BACKFILL_N) do
        local c = list[i].c
        GuildOS.SyncService:Publish("audit", "dh", { k = list[i].k, t = c.at, f = c.f, d = c.d })
    end
end

----------------------------------------------------------------------
-- Welcome back
----------------------------------------------------------------------
--- The notice's lines for a former member who joined again: `info` is MemberHistory:ReturnInfo's, `note` the
--- permanent note ({ text, author }), `ban` the ban in force (BanList's entry) or nil. Returns { title, lines,
--- warn }: a ban or a suspension is the title, in red, and the welcome back a line under it. Pure on its arguments.
function Departure.ReturnLines(name, info, note, ban, t)
    t = t or now()
    local lines = {}
    local back = string.format(L["%s left on %s and returned after %d days; was a member for %s days before."],
        name, GuildOS:DateText(info.leftAt, "/%Y"), info.away or 0, info.past and tostring(info.past) or "?")
    local title, warn = string.format(L["Welcome back: %s"], name), false
    if ban then
        warn = true
        if ban.expiry and ban.expiry > t then
            title = string.format(L["%s is suspended until %s"], name, GuildOS:DateText(ban.expiry, "/%Y"))
        else
            title = string.format(L["%s is banned"], name)
        end
        lines[#lines + 1] = string.format(L["Reason: %s"], GuildOS:SanitizeUserText(ban.reason or "?", 120))
    end
    lines[#lines + 1] = back
    if info.how == "kick" then
        lines[#lines + 1] = info.by and string.format(L["Last time they were removed by %s."], info.by)
            or L["Last time they were removed."]
    end
    if note and note.text and note.text ~= "" then
        lines[#lines + 1] = string.format(L["Permanent note (%s): %s"], note.author or "?", note.text)
    end
    return { title = title, lines = lines, warn = warn }
end

--- Somebody the history knows as a former member joined (`info`, MemberHistory:ReturnInfo's, taken before the join
--- opened a passage). On an officer's client: the notice, or the ban's warning in its place.
function Departure:OnReturn(key, name, info)
    if not (key and info) or not GuildOS:IsOfficer() then return nil end
    local MH, BL = GuildOS.MemberHistory, GuildOS.BanList
    local note = MH and MH.NoteFor and MH:NoteFor(key) or nil
    local ban
    if BL then
        local e = BL:Get(name or short(key))
        if e and BL:IsBanned(name or short(key)) then ban = e end
    end
    local r = self.ReturnLines(name or short(key), info, note, ban)
    r.key, r.name = key, name or short(key)
    self.lastReturn = r   -- the tests read it
    if GuildOS.ShowWelcomeBackNotice then
        GuildOS:ShowWhenClear("welcomeback:" .. key, function() return GuildOS:ShowWelcomeBackNotice(r) end)
    end
    return r
end
