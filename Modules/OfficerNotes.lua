----------------------------------------------------------------------
-- Guild OS - Officer Notes
-- Private notes per member, synced between officers via comm system
--
-- Two things per member, both officers only:
--   * the dated notes (`notes`), a list each officer adds to, synced as "ON" (one) and "OA" (all), as
--     before: a client before #427 reads them the same;
--   * the member's sheet (`sheet`, issue #427): one long text (up to SHEET_MAX characters, several
--     lines) any officer edits, `{ text, author, ts, rev }`. Synced per member over the SyncService's
--     officer domain "osheet": a write takes revision max(server time, last + 1), so the newer edit wins
--     on every client; an officer re-sends every sheet at its stored revision on a sync request, a few
--     per envelope and spaced out (#324). An emptied sheet is kept as an empty text, so an older one
--     never comes back. "OA" never carries it (a client before #427 would drop it anyway, and a big
--     guild's sheets would make that one message huge). A member's client drops every packet of it.
--     Never exported to the site.
----------------------------------------------------------------------
local OfficerNotes = {}
GuildOS.OfficerNotes = OfficerNotes

local LibSerialize = LibStub("GuildOS-LibSerialize")

OfficerNotes.SHEET_MAX = 1000          -- characters (letters, not bytes) of a member's sheet
OfficerNotes.SHEET_WIRE_MAX = 4000     -- bytes of a sheet off the network: 1000 letters of Han or Hangul
OfficerNotes.SHEET_DOMAIN = "osheet"
OfficerNotes.SHEET_BATCH = 2           -- sheets per envelope: two full ones are ~10 chunks
OfficerNotes.SHEET_GAP = 3             -- seconds between the envelopes of one backfill (#324)
OfficerNotes.SHEET_BACKFILL_GAP = 600  -- an officer re-sends every sheet at most once per 10 minutes
OfficerNotes.KEY_MAX = 80

function OfficerNotes:Initialize()
    if not GuildOS.db.officerNotes then
        GuildOS.db.officerNotes = {}  -- [playerKey] = { notes = { {text, author, timestamp} }, tags = {}, sheet = {...} }
    end
    if GuildOS.SyncService then
        GuildOS.SyncService:On(self.SHEET_DOMAIN, function(env, sender) OfficerNotes:OnSheetSync(env, sender) end)
    end
end

function OfficerNotes:AddNote(playerKey, text)
    if not GuildOS:IsOfficer() then return false end
    if not text or text == "" then return false end

    if not GuildOS.db.officerNotes[playerKey] then
        GuildOS.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end

    local entry = {
        text = text,
        author = GuildOS.Compat.PlayerName(),
        timestamp = GetServerTime(),
    }
    table.insert(GuildOS.db.officerNotes[playerKey].notes, 1, entry)

    -- Cap at 50 notes per player
    while #GuildOS.db.officerNotes[playerKey].notes > 50 do
        table.remove(GuildOS.db.officerNotes[playerKey].notes)
    end

    -- Broadcast to other officers
    self:BroadcastNote(playerKey, entry)
    return true
end

function OfficerNotes:DeleteNote(playerKey, index)
    if not GuildOS:IsOfficer() then return end
    local data = GuildOS.db.officerNotes[playerKey]
    if data and data.notes[index] then
        table.remove(data.notes, index)
    end
end

function OfficerNotes:GetNotes(playerKey)
    local data = GuildOS.db.officerNotes[playerKey]
    if data then
        return data.notes or {}
    end
    return {}
end

function OfficerNotes:SetTag(playerKey, tag, value)
    if not GuildOS:IsOfficer() then return end
    if not GuildOS.db.officerNotes[playerKey] then
        GuildOS.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end
    GuildOS.db.officerNotes[playerKey].tags[tag] = value
end

function OfficerNotes:GetTag(playerKey, tag)
    local data = GuildOS.db.officerNotes[playerKey]
    if data and data.tags then
        return data.tags[tag]
    end
    return nil
end

function OfficerNotes:GetAllTags(playerKey)
    local data = GuildOS.db.officerNotes[playerKey]
    if data and data.tags then
        return data.tags
    end
    return {}
end

-- Predefined tags for quick marking
OfficerNotes.QUICK_TAGS = {
    { key = "role",     label = "Role",       options = { "Tank", "Healer", "DPS", "Flex" } },
    { key = "priority", label = "Prioridade", options = { "Alta", "Media", "Baixa" } },
    { key = "status",   label = "Status",     options = { "Core", "Reserva", "Trial", "Social" } },
}

----------------------------------------------------------------------
-- Comm sync (officer-only broadcast)
----------------------------------------------------------------------
function OfficerNotes:BroadcastNote(playerKey, noteEntry)
    if not GuildOS.CommSystem then return end
    local data = {
        target = playerKey,
        note = noteEntry,
    }
    local serialized = LibSerialize:Serialize(data)
    GuildOS.CommSystem:SendMessage("ON", serialized)
end

-- Reached only through CommSystem:OnMessageReceived, which has checked the sender is an officer
-- and the channel GUILD (issue #78). Any other caller must check the same.
function OfficerNotes:HandleIncoming(data)
    if not GuildOS:IsOfficer() then return end

    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    local playerKey = GuildOS:LocalMemberKey(payload.target)   -- the sender's key, as this client's (#97)
    local note = payload.note
    if not playerKey or not note then return end

    if not GuildOS.db.officerNotes[playerKey] then
        GuildOS.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end

    -- Avoid duplicates (same author + timestamp)
    for _, existing in ipairs(GuildOS.db.officerNotes[playerKey].notes) do
        if existing.author == note.author and existing.timestamp == note.timestamp then
            return
        end
    end

    table.insert(GuildOS.db.officerNotes[playerKey].notes, 1, note)
end

-- Bulk sync: broadcast entire officerNotes table to all officers
function OfficerNotes:BroadcastAllNotes()
    if not GuildOS:IsOfficer() then return end
    if not GuildOS.CommSystem then return end
    if not IsInGuild() then return end

    local notes = GuildOS.db.officerNotes
    if not notes or not next(notes) then return end

    -- The notes and tags only: the sheets go per member over "osheet" (#427).
    local out = {}
    for k, v in pairs(notes) do
        if type(v) == "table" then out[k] = { notes = v.notes, tags = v.tags } end
    end
    local serialized = LibSerialize:Serialize(out)
    GuildOS.CommSystem:SendMessage("OA", serialized)
end

-- Handle incoming bulk officer notes
-- Reached only through CommSystem:OnMessageReceived, which has checked the sender is an officer
-- and the channel GUILD (issue #78). Any other caller must check the same.
function OfficerNotes:HandleAllIncoming(data)
    if not GuildOS:IsOfficer() then return end

    local ok, incoming = LibSerialize:Deserialize(data)
    if not ok or type(incoming) ~= "table" then return end

    if not GuildOS.db.officerNotes then GuildOS.db.officerNotes = {} end

    for incomingKey, playerData in pairs(incoming) do
        local playerKey = GuildOS:LocalMemberKey(incomingKey)   -- the sender's key, as this client's (#97)
        if type(playerData) == "table" then
            if not GuildOS.db.officerNotes[playerKey] then
                GuildOS.db.officerNotes[playerKey] = { notes = {}, tags = {} }
            end
            -- The notes and tags only: a sheet comes over "osheet", checked there (#427).
            self:MergeSheet(GuildOS.db.officerNotes[playerKey], { notes = playerData.notes, tags = playerData.tags })
        end
    end
end

-- One member's sheet folded into another: an incoming note is added unless one by the same author
-- at the same time is already there, the sheet ends newest first, and the incoming tags win where
-- they say something. Notes already held are all kept: two in one second exist on their author's
-- client. On a bulk sync and in the stored-key migration (#97); a note that is not a note is
-- dropped rather than breaking either.
function OfficerNotes:MergeSheet(existing, incoming)
    local notes, seen = {}, {}
    local function key(n) return tostring(n.author or "") .. "_" .. tostring(n.timestamp or 0) end
    for _, n in ipairs(type(existing.notes) == "table" and existing.notes or {}) do
        if type(n) == "table" then notes[#notes + 1], seen[key(n)] = n, true end
    end
    for _, n in ipairs(type(incoming.notes) == "table" and incoming.notes or {}) do
        if type(n) == "table" and not seen[key(n)] then notes[#notes + 1], seen[key(n)] = n, true end
    end
    table.sort(notes, function(a, b) return (tonumber(a.timestamp) or 0) > (tonumber(b.timestamp) or 0) end)
    existing.notes = notes
    if type(existing.tags) ~= "table" then existing.tags = {} end
    for k, v in pairs(type(incoming.tags) == "table" and incoming.tags or {}) do
        if v and v ~= "" then existing.tags[k] = v end
    end
    -- Two keys of one member folded (#97): the sheet at the higher revision stays.
    local a, b = existing.sheet, incoming.sheet
    if type(b) == "table" and type(b.text) == "string" then
        if type(a) ~= "table" or OfficerNotes.SheetWins(tonumber(b.rev) or 0, b, tonumber(a.rev) or 0, a) then
            existing.sheet = b
        end
    end
    return existing
end

----------------------------------------------------------------------
-- The member's sheet (issue #427)
----------------------------------------------------------------------
--- The text as it is kept: no escape sequence ("|"), no control character but the line break, no more
--- than three lines blank in a row, no spaces at either end, at most SHEET_MAX letters. Pure.
function OfficerNotes.CleanSheetText(text)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("\r\n?", "\n"):gsub("|", ""):gsub("[%z\1-\9\11-\31\127]", " ")
    s = s:gsub("\n\n\n\n+", "\n\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return GuildOS:Utf8Head(s, OfficerNotes.SHEET_MAX)
end

local function sheetTie(e)
    return tostring(e.text or "") .. "\0" .. tostring(e.author or "")
end

--- Whether `entry` at `rev` replaces `held` at `cur`: the higher revision; at the same one, the same
--- answer on every client whatever the order they arrive in. Pure.
function OfficerNotes.SheetWins(rev, entry, cur, held)
    cur = cur or 0
    if rev > cur then return true end
    if rev < cur or not held then return false end
    return sheetTie(entry) > sheetTie(held)
end

local function notesStore()
    local d = GuildOS.db
    if type(d.officerNotes) ~= "table" then d.officerNotes = {} end
    return d.officerNotes
end

local function sheetHolder(key)
    local s = notesStore()
    if type(s[key]) ~= "table" then s[key] = { notes = {}, tags = {} } end
    return s[key]
end

--- The member's sheet `{ text, author, ts, rev }`, or nil when none (or emptied). Officers only.
function OfficerNotes:GetSheet(key)
    if not GuildOS:IsOfficer() or type(key) ~= "string" then return nil end
    local h = GuildOS.db and type(GuildOS.db.officerNotes) == "table" and GuildOS.db.officerNotes[key]
    local e = type(h) == "table" and h.sheet
    if type(e) ~= "table" or type(e.text) ~= "string" or e.text == "" then return nil end
    return e
end

local function sheetWire(k, e)
    return { k = k, x = e.text, a = e.author, t = e.ts, r = e.rev }
end

local function publishSheets(items)
    local SS = GuildOS.SyncService
    if not SS or #items == 0 then return end
    for i = 1, #items, OfficerNotes.SHEET_BATCH do
        local batch = {}
        for j = i, math.min(i + OfficerNotes.SHEET_BATCH - 1, #items) do batch[#batch + 1] = items[j] end
        SS:Publish(OfficerNotes.SHEET_DOMAIN, "set", { sheets = batch }, { priority = "BULK" })
    end
end

--- Write the member's sheet as this officer's and publish it. An empty text empties it. Returns true when
--- it was written (false when not an officer, or the text is what the sheet already says).
function OfficerNotes:SetSheet(key, text)
    if not GuildOS:IsOfficer() or type(key) ~= "string" or key == "" then return false end
    local clean = self.CleanSheetText(text or "")
    if not clean then return false end
    local h = sheetHolder(key)
    local held = type(h.sheet) == "table" and h.sheet or nil
    if (held and held.text or "") == clean then return false end
    local now = GetServerTime()
    local e = {
        text = clean, author = GuildOS.Compat.PlayerName(), ts = now,
        rev = math.max(now, (held and tonumber(held.rev) or 0) + 1),
    }
    h.sheet = e
    publishSheets({ sheetWire(key, e) })
    self:Refresh()
    return true
end

local function netKey(v)
    if type(v) ~= "string" or v == "" or #v > OfficerNotes.KEY_MAX or v:find("|", 1, true) then return nil end
    return GuildOS:LocalMemberKey(v)
end

--- Apply sheets off the network ({ k, x, a, t, r } each). `sender` is the officer SyncService checked; a
--- sheet names its own author, else the sender. Returns how many were applied.
function OfficerNotes:ApplySheets(list, sender)
    if type(list) ~= "table" then return 0 end
    local applied = 0
    for i = 1, math.min(#list, self.SHEET_BATCH * 2) do
        local it = list[i]
        local k = type(it) == "table" and netKey(it.k)
        local rev = k and GuildOS.Finite(it.r)
        local text = k and type(it.x) == "string" and #it.x <= self.SHEET_WIRE_MAX and self.CleanSheetText(it.x)
        if k and rev and rev >= 1 and text then
            local e = {
                text = text,
                author = (type(it.a) == "string" and it.a ~= "" and #it.a <= self.KEY_MAX and not it.a:find("|", 1, true))
                    and it.a or sender,
                ts = GuildOS.Finite(it.t) or 0, rev = rev,
            }
            local h = sheetHolder(k)
            local held = type(h.sheet) == "table" and h.sheet or nil
            if self.SheetWins(rev, e, held and tonumber(held.rev) or 0, held) then
                h.sheet = e
                applied = applied + 1
            end
        end
    end
    return applied
end

-- From an officer over GUILD (SyncService checked it). A member's client keeps nothing.
function OfficerNotes:OnSheetSync(env, sender)
    if not GuildOS:IsOfficer() then return end
    if type(env) ~= "table" or env.act ~= "set" or type(env.data) ~= "table" then return end
    if self:ApplySheets(env.data.sheets, sender) > 0 then self:Refresh() end
end

--- Every sheet, emptied ones included, at its stored revision, SHEET_BATCH per envelope and SHEET_GAP
--- seconds apart. On the answer to a sync request (at most once per SHEET_BACKFILL_GAP) and on /gos sync
--- (`force`). Officers only; one backfill at a time.
function OfficerNotes:BackfillSheets(force)
    if not GuildOS:IsOfficer() or not GuildOS.SyncService or self._sheetBackfilling then return end
    local now = GetTime()
    if not force and self._sheetBackfillAt and now - self._sheetBackfillAt < self.SHEET_BACKFILL_GAP then return end
    local keys = {}
    for k, h in pairs(notesStore()) do
        if type(h) == "table" and type(h.sheet) == "table" and type(h.sheet.text) == "string" then keys[#keys + 1] = k end
    end
    if #keys == 0 then return end
    table.sort(keys)
    self._sheetBackfillAt = now
    self._sheetBackfilling = true
    local store = notesStore()
    local function send(i)
        local batch = {}
        for j = i, math.min(i + self.SHEET_BATCH - 1, #keys) do
            local h = store[keys[j]]
            if type(h) == "table" and type(h.sheet) == "table" then batch[#batch + 1] = sheetWire(keys[j], h.sheet) end
        end
        if #batch > 0 then
            GuildOS.SyncService:Publish(self.SHEET_DOMAIN, "set", { sheets = batch }, { priority = "BULK" })
        end
        if keys[i + self.SHEET_BATCH] then
            GuildOS.Compat.After(self.SHEET_GAP, function() send(i + self.SHEET_BATCH) end)
        else
            self._sheetBackfilling = nil
        end
    end
    send(1)
end

--- The first `lines` lines and `letters` letters of a sheet's text, and whether there is more. Pure.
function OfficerNotes.SheetHead(text, lines, letters)
    if type(text) ~= "string" or text == "" then return nil, false end
    local out, n, pos = {}, 0, 1
    while n < lines do
        local nl = text:find("\n", pos, true)
        out[#out + 1] = text:sub(pos, (nl or 0) - 1)
        n = n + 1
        if not nl then pos = #text + 1 break end
        pos = nl + 1
    end
    local head = table.concat(out, "\n")
    local cut = GuildOS:Utf8Head(head, letters)
    local more = #cut < #head or pos <= #text
    return cut, more
end

function OfficerNotes:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
