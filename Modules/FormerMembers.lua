----------------------------------------------------------------------
-- Guild OS - Former members (Officers' Room > Members > Former members; specs/salao/manutencao-roster.md §6)
-- Who left the guild, read from what the addon keeps past a departure (Core/Utils.lua DropDeparted drops the
-- rest): the member history's passages, rank changes and permanent note (Modules/MemberHistory.lua), the ban
-- list, the officer notes and sheet, and the alt links. Nothing new is stored or sent.
--
--   * The list: one row per key the history says left and has not come back, with the last departure, how
--     (left, removed by X, or banned / suspended when a ban stands), the passages, the days in the guild over
--     all of them, and whether there are notes and alts. Filters (All, Left, Removed, Banned, With notes; the
--     first three split the list, the last cuts across it), a search over the name and the notes, three sorts.
--   * The actions, each the existing flow: the member window for somebody no longer in the roster (a record
--     built here, UI/MemberDetail.lua hides what only a present member has), Ban... (BanList:AddGroup on the
--     whole alt group, the reason asked first), Unban (the group's bans lifted, after a question), Invite back
--     (BanList:HoldInvite first, then the officer action queue on this click, or on WoW: Forever the /ginvite
--     line to copy), Forget.
--   * Forget deletes the key's history and its permanent note from THIS client only. The history syncs between
--     officers as append-only records (the audit domain's "hist") and the note by revision ("hnote"): nothing
--     tells another client to delete, so the other officers keep theirs and a record or note they send later
--     can bring part of it back here. The question says so.
--
-- Big guilds: the history holds up to MemberHistory.MAX_KEYS keys; one pass over it with table lookups (the alt
-- groups indexed once, never GetLinkedChars per key), cached CACHE_SECONDS unless invalidated (an action, a ban
-- or a note that changes). The search and the chips only filter the cache. Business logic only, no frames.
----------------------------------------------------------------------
local FormerMembers = {}
GuildOS.FormerMembers = FormerMembers
local L = GuildOS.L

FormerMembers.KINDS = { "left", "removed", "banned", "notes" }
FormerMembers.SORTS = { "left", "name", "days" }
FormerMembers.CACHE_SECONDS = 20

local function short(key) return key and (key:match("^([^-]+)") or key) or "?" end
local function lower(s) return string.lower(s or "") end

----------------------------------------------------------------------
-- Pure (tools/former-members.lua)
----------------------------------------------------------------------
--- A ban entry as the list reads it at `now`: "banned" (for good), "suspended" (a term still running), or nil (none,
--- lifted or run out).
function FormerMembers.BanState(entry, now)
    if type(entry) ~= "table" or entry.removed then return nil end
    if entry.expiry then
        if entry.expiry <= now then return nil end
        return "suspended"
    end
    return "banned"
end

--- Which of the three exclusive filters a row is in: "banned" when a ban stands, else "removed" for a removal,
--- else "left" (a departure the game said was theirs, or one a roster diff saw without knowing which).
function FormerMembers.KindOf(how, ban)
    if ban then return "banned" end
    if how == "kick" then return "removed" end
    return "left"
end

--- The rows of filter `kind` ("all" or nil: every row) whose name or notes hold `text` (any case).
function FormerMembers.Filter(rows, kind, text)
    text = lower(strtrim(text or ""))
    local out = {}
    for _, r in ipairs(rows or {}) do
        local okKind = kind == nil or kind == "all" or (kind == "notes" and r.hasNotes) or r.kind == kind
        local okText = text == "" or lower(r.name):find(text, 1, true) ~= nil
            or (r.find ~= nil and r.find:find(text, 1, true) ~= nil)
        if okKind and okText then out[#out + 1] = r end
    end
    return out
end

--- How many rows each filter holds: { all, left, removed, banned, notes }.
function FormerMembers.Count(rows)
    local c = { all = #(rows or {}), left = 0, removed = 0, banned = 0, notes = 0 }
    for _, r in ipairs(rows or {}) do
        c[r.kind] = (c[r.kind] or 0) + 1
        if r.hasNotes then c.notes = c.notes + 1 end
    end
    return c
end

local SORT = {
    left = function(r) return r.leftAt end,
    name = function(r) return lower(r.name) end,
    days = function(r) return r.days end,
}

--- `rows` sorted in place by `by` ("left", "name", "days"), ascending when `asc`; a row with no value goes last
--- either way, ties by name. Returns it.
function FormerMembers.Sort(rows, by, asc)
    local key = SORT[by] or SORT.left
    table.sort(rows, function(a, b)
        local va, vb = key(a), key(b)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if asc then return va < vb end
            return va > vb
        end
        return lower(a.name) < lower(b.name)
    end)
    return rows
end

--- How the row left, as the list says it: "banned", "suspended until <date>", "removed by X", "left".
function FormerMembers.HowText(r)
    if r.ban == "suspended" then
        return string.format(L["suspended until %s"], GuildOS:DateText(r.banUntil or 0, "/%Y"))
    elseif r.ban == "banned" then
        return L["banned"]
    end
    if r.how == "kick" then
        return r.by and string.format(L["removed by %s"], r.by) or L["removed"]
    elseif r.how == "leave" then
        return L["left"]
    end
    return L["left or was removed"]
end

--- "Today", "1 day ago", "N days ago".
function FormerMembers.AgoText(days)
    if not days then return "" end
    if days <= 0 then return L["Today"] end
    if days == 1 then return L["1 day ago"] end
    return string.format(L["%d days ago"], days)
end

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------
local cache = { at = nil, data = nil }

--- Drop the list's cache: the next Rows reads the stores again.
function FormerMembers:Invalidate()
    cache.at, cache.data = nil, nil
end

-- The name a ban or an invite takes for `key`: the whole key on retail (a guild spans connected realms), else the
-- name alone, as BanList and the game's invite read it.
local function whoOf(key)
    if GuildOS.Client.isRetail then return key end
    return short(key)
end
FormerMembers.WhoOf = whoOf

--- The former members, officers only: { rows, counts, at }. Each row { key, name, class, leftAt, leftEst, how, by,
--- kind, ban, banUntil, banReason, stints, days, ago, hasNotes, hasAlts, note, find }. Cached CACHE_SECONDS unless
--- `force` or Invalidate.
function FormerMembers:Rows(force)
    if not GuildOS:IsOfficer() then return { rows = {}, counts = self.Count({}) } end
    local now = GetServerTime()
    if not force and cache.data and cache.at and now - cache.at < self.CACHE_SECONDS then return cache.data end
    local MH, BL, ON = GuildOS.MemberHistory, GuildOS.BanList, GuildOS.OfficerNotes
    local rows = {}
    if MH then
        local links = (GuildOS.db and GuildOS.db.altLinks) or {}
        local mains = {}
        for _, main in pairs(links) do mains[main] = true end
        local onotes = (GuildOS.db and type(GuildOS.db.officerNotes) == "table") and GuildOS.db.officerNotes or {}
        for _, f in ipairs(MH:Former()) do
            local key, last = f.key, f.last
            local entry = BL and BL:Get(whoOf(key)) or nil
            local ban = self.BanState(entry, now)
            local pnote = MH:GetNote(key)
            local sheet = ON and ON:GetSheet(key)
            local dated = type(onotes[key]) == "table" and type(onotes[key].notes) == "table" and #onotes[key].notes or 0
            local find = {}
            if pnote then find[#find + 1] = pnote.text end
            if sheet then find[#find + 1] = sheet.text end
            if dated > 0 then
                for i = 1, math.min(dated, 10) do
                    local n = onotes[key].notes[i]
                    if type(n) == "table" and type(n.text) == "string" then find[#find + 1] = n.text end
                end
            end
            rows[#rows + 1] = {
                key = key, name = short(key), class = MH:ClassOf(key),
                leftAt = last.leftAt, leftEst = last.leftEst == true, how = last.how, by = last.by,
                kind = self.KindOf(last.how, ban), ban = ban,
                banUntil = ban == "suspended" and entry.expiry or nil, banReason = ban and entry.reason or nil,
                stints = f.stints, days = f.days, ago = math.max(0, MH.DaysBetween(last.leftAt, now) or 0),
                hasNotes = (pnote or sheet or dated > 0) and true or false,
                hasAlts = links[key] ~= nil or mains[key] == true,
                note = pnote and pnote.text or nil,
                find = #find > 0 and lower(table.concat(find, "\n")) or nil,
            }
        end
    end
    local data = { rows = rows, counts = self.Count(rows), at = now }
    cache.at, cache.data = now, data
    return data
end

-- Something the list reads changed: the cache goes, and the screen redraws (now if shown, else when it shows).
function FormerMembers:Changed()
    self:Invalidate()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- The member window for somebody no longer in the roster
----------------------------------------------------------------------
--- The record UI/MemberDetail.lua draws for a former member: what the history knows (the class last seen), the
--- "Ex-member" rank, `former` set so the window hides what only a present member has.
function FormerMembers:Record(row)
    if not row or not row.key then return nil end
    local key = row.key
    local cls = row.class or (GuildOS.MemberHistory and GuildOS.MemberHistory:ClassOf(key)) or ""
    local display = cls ~= "" and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls) or nil
    return {
        key = key, name = short(key), fullName = key, realm = key:match("^[^-]+%-(.+)$"),
        rank = L["Ex-member"], level = 0, class = cls, classDisplay = display or "", race = "",
        note = "", officerNote = "", isOnline = false, status = "", zone = "",
        former = true, leftAt = row.leftAt, leftEst = row.leftEst,
    }
end

--- The member window's line for a ban or a suspension standing on `key` ("Banned: <reason>", "Suspended until
--- <date>: <reason>"), or nil.
function FormerMembers:BanLine(key, now)
    local BL = GuildOS.BanList
    if not (BL and key) then return nil end
    now = now or GetServerTime()
    local e = BL:Get(whoOf(key))
    local state = self.BanState(e, now)
    if not state then return nil end
    local reason = GuildOS:SanitizeUserText(e.reason or "?", 80)
    if state == "suspended" then
        return string.format(L["Suspended until %s: %s"], GuildOS:DateText(e.expiry, "/%Y"), reason)
    end
    return string.format(L["Banned: %s"], reason)
end

--- A click on a row: the member window, from the roster when they are back in it, else the former member's record.
function FormerMembers:Open(row)
    if not (row and GuildOS.ShowMemberDetail) then return false end
    local rec = GuildOS:GetMemberRecord(row.name) or self:Record(row)
    if not rec then return false end
    GuildOS:ShowMemberDetail(rec)
    return true
end

----------------------------------------------------------------------
-- The row's actions (officers only; each the module that owns it)
----------------------------------------------------------------------
--- Every character of the row's alt group, the main first (GetLinkedChars).
function FormerMembers:GroupOf(row)
    if not (row and row.key) then return {} end
    return GuildOS:GetLinkedChars(row.key)
end

--- "Ban...": the question, its box for the reason; yes bans the whole group (BanGroup).
function FormerMembers:Ban(row)
    if not (row and GuildOS:IsOfficer()) then return false end
    local n = #self:GroupOf(row)
    local who = n > 1 and string.format(L["%s and their %d other character(s)"], row.name, n - 1) or row.name
    GuildOS:ShowDialog("GUILDOS_FORMER_BAN", who, nil, row)
    return true
end

--- Bans the row's whole alt group for good with `reason` (BanList:AddGroup). How many characters were banned.
function FormerMembers:BanGroup(row, reason)
    local BL = GuildOS.BanList
    if not (row and BL and GuildOS:IsOfficer()) then return 0 end
    local n = BL:AddGroup(self:GroupOf(row), reason, nil, nil)
    self:Changed()
    return n
end

--- "Unban": the question; yes lifts the group's bans (UnbanGroup).
function FormerMembers:Unban(row)
    if not (row and GuildOS:IsOfficer()) then return false end
    GuildOS:ShowDialog("GUILDOS_FORMER_UNBAN", row.name, nil, row)
    return true
end

--- Lifts every ban in force on the row's alt group (BanList:RemoveKey on the key each is filed under). How many.
function FormerMembers:UnbanGroup(row)
    local BL = GuildOS.BanList
    if not (row and BL and GuildOS:IsOfficer()) then return 0 end
    local now, n = GetServerTime(), 0
    for _, k in ipairs(self:GroupOf(row)) do
        local who = whoOf(k)
        local banKey, entry = BL:_Find(who, nil, now)
        if self.BanState(entry, now) and BL:RemoveKey(banKey) then n = n + 1 end
    end
    self:Changed()
    return n
end

--- "Invite back", from the button's click (the key press C_GuildInfo.Invite wants). A ban (the guild's or the
--- alliance's) holds it first with "Invite anyway" (BanList:HoldInvite, which also says in chat when they were a
--- member). WoW: Forever lets no addon invite: the /ginvite line to copy (the officer action queue's). Elsewhere the
--- queue runs it now (this click is the hardware event). Returns "held", "typed", "ran" or false.
function FormerMembers:InviteBack(row, confirmed)
    if not (row and row.key and GuildOS:IsOfficer()) then return false end
    local name = whoOf(row.key)
    local BL = GuildOS.BanList
    if not confirmed and BL and BL.HoldInvite and BL:HoldInvite(name, function() FormerMembers:InviteBack(row, true) end) then
        return "held"
    end
    local AQ = GuildOS.ActionQueue
    if not GuildOS.Compat.AddonMayInvite() then
        if AQ and CanGuildInvite and CanGuildInvite() then
            AQ:OfferTyped(name)
            return "typed"
        end
        -- No right to invite, or no queue: the game's own line says how (Compat.GuildInvite).
        GuildOS.Compat.GuildInvite(name)
        return false
    end
    if not AQ then return GuildOS.Compat.GuildInvite(name) and "ran" or false end
    return AQ:Add({ kind = "guildInvite", key = "ginv:" .. name, name = name,
                    run = function() return GuildOS.Compat.GuildInvite(name) end }, true)
end

--- "Forget": the question first (local only, and why).
function FormerMembers:Forget(row)
    if not (row and row.key and GuildOS:IsOfficer()) then return false end
    GuildOS:ShowDialog("GUILDOS_FORMER_FORGET", row.name, nil, row.key)
    return true
end

--- Deletes `key`'s history (its passages, rank changes, class and permanent note) from this client, and its records
--- from this client's outbox so its login backfill does not send them again. Officers only; a present member is never
--- forgotten. True when something was deleted.
function FormerMembers:ForgetNow(key)
    if type(key) ~= "string" or key == "" or not GuildOS:IsOfficer() then return false end
    local db = GuildOS.db
    local h = db and db.memberHistory
    if type(h) ~= "table" or h[key] == nil then return false end
    local MH = GuildOS.MemberHistory
    if MH and not MH:IsFormer(key) then return false end
    h[key] = nil
    local out = db.memberHistoryOut
    if type(out) == "table" then
        for i = #out, 1, -1 do
            if type(out[i]) == "table" and out[i].k == key then table.remove(out, i) end
        end
    end
    self:Changed()
    if GuildOS.RosterLog then GuildOS.RosterLog:Refresh() end
    return true
end

----------------------------------------------------------------------
-- The questions (GuildOS's own dialog, UI/Helpers.lua)
----------------------------------------------------------------------
if GuildOS.Dialogs then
    GuildOS.Dialogs["GUILDOS_FORMER_BAN"] = {
        text = L["Ban %s for good? Every character of the group gets the ban. Reason:"],
        button1 = L["Ban"], button2 = L["Cancel"],
        hasEditBox = true, maxLetters = 80,
        OnAccept = function(dlg, row)
            local box = GuildOS.Compat.PopupEditBox and GuildOS.Compat.PopupEditBox(dlg) or (dlg and dlg.editBox)
            FormerMembers:BanGroup(row, box and box:GetText() or "")
        end,
        EditBoxOnEnterPressed = function(box, row)
            local dlg = box:GetParent()
            FormerMembers:BanGroup(row or (dlg and dlg.data), box:GetText() or "")
            if dlg then dlg:Hide() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    GuildOS.Dialogs["GUILDOS_FORMER_UNBAN"] = {
        text = L["Lift the ban on %s?"],
        button1 = L["Lift"], button2 = L["Cancel"],
        OnAccept = function(_, row) FormerMembers:UnbanGroup(row) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    GuildOS.Dialogs["GUILDOS_FORMER_FORGET"] = {
        text = L["Forget %s? Their membership history and permanent note are deleted from this client only. The history syncs between officers as records that are never deleted: the other officers keep theirs, and a sync may bring part of it back. Bans, officer notes and alt links stay."],
        button1 = L["Forget"], button2 = L["Cancel"],
        OnAccept = function(_, key) FormerMembers:ForgetNow(key) end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    }
end
