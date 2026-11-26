----------------------------------------------------------------------
-- Guild OS - Somebody with alts removed or gone (issue #426, epic #423 group B)
--
-- Removed: on the client of the officer who removed them (the game's "kicked out by <me>" line, or a
-- removal of Bulk actions the roster confirmed), when their alt group still has characters in the guild,
-- the officer is asked once per group: remove those too (a queue of Bulk actions, one per click of the
-- secure button, ADR-0038), ban the whole group (a term or permanent, a note for the officers), or
-- nothing. Removals made while a queue runs are asked about once it is through.
--
-- Gone: when the main of a group with alts still in the guild leaves of their own accord, each officer
-- online is asked once: "Set A as main" (SetMain, synced to everybody by AltSync), "Unlink" or "Keep".
-- An alt leaving is only its line in the Roster Log.
--
-- Only ever asks. Nothing here removes, bans or relinks without the officer's click, never promotes a
-- main on its own and never whispers anybody. Fed only by RosterLog's detection, which reads nothing
-- while the login settles or while the chat is in lockdown (Compat.IsSecret). Session state only.
-- The logic is here; UI/AltDepartureDialog.lua only lays it out.
----------------------------------------------------------------------
local AltDeparture = {}
GuildOS.AltDeparture = AltDeparture
local L = GuildOS.L

AltDeparture.FLUSH_DELAY = 2   -- seconds after a removal before asking: the game's line and the roster settle

local function state()
    GuildOS.State.altDeparture = GuildOS.State.altDeparture or { pending = {}, order = {}, removed = {}, asked = {}, left = {} }
    return GuildOS.State.altDeparture
end

local function short(key) return key and (key:match("^([^-]+)") or key) or "?" end

local function ready()
    return GuildOS.RosterLog ~= nil and GuildOS.RosterLog._ready == true
end

--- The member key of a name the Roster Log filed (short off retail, the whole key on retail).
function AltDeparture:KeyOf(target)
    if type(target) ~= "string" or target == "" then return nil end
    return GuildOS:KeyOfRosterName(target)
end

-- This character's key, never asked about.
local function meKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
end

-- The roster as Bulk actions reads it (name, key, class, rank).
local function roster()
    local BA = GuildOS.BulkActions
    return BA and BA:Collect(false) or {}
end

----------------------------------------------------------------------
-- Pure (tools/alt-departure.lua)
----------------------------------------------------------------------
--- The members of `members` in `group` (keys) that are not in `skip` (a set of keys), by name.
function AltDeparture.Others(group, members, skip)
    local want = {}
    for _, k in ipairs(group or {}) do
        if not (skip and skip[k]) then want[k] = true end
    end
    local out = {}
    for _, m in ipairs(members or {}) do
        if want[m.key] then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

--- A list of names, each in its class colour: "|cffc79c6eAna|r, |cff...Bia|r".
function AltDeparture.ColoredNames(members)
    local parts = {}
    for i, m in ipairs(members or {}) do
        local name = m.name or short(m.key)
        parts[i] = (m.class and m.class ~= "") and ("|cff" .. GuildOS:GetClassColorHex(m.class) .. name .. "|r") or name
    end
    return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- Removed by this officer
----------------------------------------------------------------------
--- Whether removals wait to be asked about.
function AltDeparture:HasPending()
    return #state().order > 0
end

--- The Roster Log took a removal from the game's line (local only, never a synced one).
function AltDeparture:OnKick(evt)
    if type(evt) ~= "table" or evt.action ~= "kick" or not evt.author then return end
    local RL = GuildOS.RosterLog
    local me = RL and RL:_NormShort(GuildOS.Compat.PlayerName())
    if evt.author ~= me then return end   -- only on the client of whoever removed them
    self:OnRemoved(self:KeyOf(evt.target))
end

--- `key` was removed from the guild by this officer: asked about after FLUSH_DELAY, or once a queue is through.
function AltDeparture:OnRemoved(key)
    if not key or not ready() then return end
    local s = state()
    s.removed[key] = true
    if s.pending[key] then return end
    s.pending[key] = true
    s.order[#s.order + 1] = key
    if not s.timer then
        s.timer = true
        GuildOS.Compat.After(self.FLUSH_DELAY, function()
            state().timer = nil
            GuildOS:SafeCall(AltDeparture.Flush, AltDeparture)
        end)
    end
end

--- The groups to ask about now: { { key, name, keys = the whole group, main first, others = roster lines } }. Each
--- group is asked about once a session. Empties the pending list.
function AltDeparture:TakeGroups(members)
    local s = state()
    local skip = {}
    for k in pairs(s.removed) do skip[k] = true end
    local me = meKey()
    if me then skip[me] = true end
    local groups = {}
    for _, key in ipairs(s.order) do
        local group = GuildOS:GetLinkedChars(key)
        local main = group[1]
        if #group > 1 and not s.asked[main] then
            local others = self.Others(group, members, skip)
            if #others > 0 then
                s.asked[main] = true
                groups[#groups + 1] = { key = key, name = short(key), keys = group, others = others }
            end
        end
    end
    s.pending, s.order = {}, {}
    return groups
end

--- Ask about what was removed, unless a removal queue is still running (its end asks).
function AltDeparture:Flush()
    if not self:HasPending() then return end
    local BA = GuildOS.BulkActions
    local q = BA and BA:Queue()
    if q and q.action == "remove" and BA:Busy() then return end
    local groups = self:TakeGroups(roster())
    if #groups == 0 then return end
    self.lastRemoved = groups   -- the tests read it
    -- Never in combat, one popup at a time (audit B21).
    if GuildOS.ShowAltRemovedDialog then
        GuildOS:ShowWhenClear("altremoved", function() return GuildOS:ShowAltRemovedDialog(groups) end)
    end
end

--- "Remove them too": the others of every group, into a removal queue of Bulk actions (one per click). True or false.
function AltDeparture:RemoveOthers(groups)
    local BA = GuildOS.BulkActions
    if not BA then return false end
    local keys = {}
    for _, g in ipairs(groups or {}) do
        for _, m in ipairs(g.others or {}) do keys[#keys + 1] = m.key end
    end
    return BA:StartListAndSay("remove", BA:ListFor(keys))
end

--- "Ban the group": every character of each group, with the same reason, term (days, nil for permanent) and note.
--- Returns how many bans were made.
function AltDeparture:BanGroups(groups, reason, days, note)
    local BL = GuildOS.BanList
    if not BL or not GuildOS:IsOfficer() then return 0 end
    local n = 0
    for _, g in ipairs(groups or {}) do n = n + BL:AddGroup(g.keys, reason, days, note) end
    return n
end

----------------------------------------------------------------------
-- A main who left
----------------------------------------------------------------------
--- The Roster Log took a member leaving from the game's line. A main with alts still in the guild: the officer is
--- asked, once per event and once per main this session.
function AltDeparture:OnLeave(evt)
    if type(evt) ~= "table" or evt.action ~= "leave" or not ready() or not GuildOS:IsOfficer() then return end
    local key = self:KeyOf(evt.target)
    if not key or key == meKey() then return end
    local s = state()
    local seen = evt.id or key
    if s.left[seen] or s.left[key] then return end
    local links = GuildOS.db and GuildOS.db.altLinks or {}
    if links[key] ~= nil then return end   -- an alt: its line in the log is all
    local group = GuildOS:GetLinkedChars(key)
    if #group < 2 then return end
    local others = self.Others(group, roster(), { [key] = true })
    if #others == 0 then return end
    s.left[seen], s.left[key] = true, true
    local info = { key = key, name = short(key), others = others }
    self.lastLeft = info   -- the tests read it
    if GuildOS.ShowMainLeftDialog then
        GuildOS:ShowWhenClear("mainleft:" .. key, function() return GuildOS:ShowMainLeftDialog(info) end)
    end
end

-- Whether `departed` still heads a group: some alt still points at them (another officer may have answered).
local function stillHeads(departed)
    for _, m in pairs(GuildOS.db and GuildOS.db.altLinks or {}) do
        if m == departed then return true end
    end
    return false
end

--- "Set A as main": A heads the group, the one who left becomes its alt, for everybody (AltSync). True, or false and
--- why: "officer", "settled" (another officer already answered, or the links changed).
function AltDeparture:SetNewMain(departed, newKey)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local links = GuildOS.db and GuildOS.db.altLinks or {}
    if not newKey or links[newKey] ~= departed then return false, "settled" end
    return GuildOS:SetMain(newKey) and true or false, "settled"
end

--- "Unlink": every alt of the one who left stands alone. True, or false and why ("officer", "settled").
function AltDeparture:Unlink(departed)
    if not GuildOS:IsOfficer() then return false, "officer" end
    if not stillHeads(departed) then return false, "settled" end
    return GuildOS:UnlinkGroup(departed) > 0, "settled"
end

--- What a refusal says.
function AltDeparture.WhyText(why)
    if why == "officer" then return L["|cffFF4444Officers only.|r"] end
    return L["The alt links already changed (another officer may have answered): nothing was done."]
end
