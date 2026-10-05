----------------------------------------------------------------------
-- BRutus Guild Manager - Officer Notes
-- Private notes per member, synced between officers via comm system
----------------------------------------------------------------------
local OfficerNotes = {}
BRutus.OfficerNotes = OfficerNotes

local LibSerialize = LibStub("GuildOS-LibSerialize")

function OfficerNotes:Initialize()
    if not BRutus.db.officerNotes then
        BRutus.db.officerNotes = {}  -- [playerKey] = { notes = { {text, author, timestamp} }, tags = {} }
    end
end

function OfficerNotes:AddNote(playerKey, text)
    if not BRutus:IsOfficer() then return false end
    if not text or text == "" then return false end

    if not BRutus.db.officerNotes[playerKey] then
        BRutus.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end

    local entry = {
        text = text,
        author = BRutus.Compat.PlayerName(),
        timestamp = GetServerTime(),
    }
    table.insert(BRutus.db.officerNotes[playerKey].notes, 1, entry)

    -- Cap at 50 notes per player
    while #BRutus.db.officerNotes[playerKey].notes > 50 do
        table.remove(BRutus.db.officerNotes[playerKey].notes)
    end

    -- Broadcast to other officers
    self:BroadcastNote(playerKey, entry)
    return true
end

function OfficerNotes:DeleteNote(playerKey, index)
    if not BRutus:IsOfficer() then return end
    local data = BRutus.db.officerNotes[playerKey]
    if data and data.notes[index] then
        table.remove(data.notes, index)
    end
end

function OfficerNotes:GetNotes(playerKey)
    local data = BRutus.db.officerNotes[playerKey]
    if data then
        return data.notes or {}
    end
    return {}
end

function OfficerNotes:SetTag(playerKey, tag, value)
    if not BRutus:IsOfficer() then return end
    if not BRutus.db.officerNotes[playerKey] then
        BRutus.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end
    BRutus.db.officerNotes[playerKey].tags[tag] = value
end

function OfficerNotes:GetTag(playerKey, tag)
    local data = BRutus.db.officerNotes[playerKey]
    if data and data.tags then
        return data.tags[tag]
    end
    return nil
end

function OfficerNotes:GetAllTags(playerKey)
    local data = BRutus.db.officerNotes[playerKey]
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
    if not BRutus.CommSystem then return end
    local data = {
        target = playerKey,
        note = noteEntry,
    }
    local serialized = LibSerialize:Serialize(data)
    BRutus.CommSystem:SendMessage("ON", serialized)
end

-- Reached only through CommSystem:OnMessageReceived, which has checked the sender is an officer
-- and the channel GUILD (issue #78). Any other caller must check the same.
function OfficerNotes:HandleIncoming(data)
    if not BRutus:IsOfficer() then return end

    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    local playerKey = BRutus:LocalMemberKey(payload.target)   -- the sender's key, as this client's (#97)
    local note = payload.note
    if not playerKey or not note then return end

    if not BRutus.db.officerNotes[playerKey] then
        BRutus.db.officerNotes[playerKey] = { notes = {}, tags = {} }
    end

    -- Avoid duplicates (same author + timestamp)
    for _, existing in ipairs(BRutus.db.officerNotes[playerKey].notes) do
        if existing.author == note.author and existing.timestamp == note.timestamp then
            return
        end
    end

    table.insert(BRutus.db.officerNotes[playerKey].notes, 1, note)
end

-- Bulk sync: broadcast entire officerNotes table to all officers
function OfficerNotes:BroadcastAllNotes()
    if not BRutus:IsOfficer() then return end
    if not BRutus.CommSystem then return end
    if not IsInGuild() then return end

    local notes = BRutus.db.officerNotes
    if not notes or not next(notes) then return end

    local serialized = LibSerialize:Serialize(notes)
    BRutus.CommSystem:SendMessage("OA", serialized)
end

-- Handle incoming bulk officer notes
-- Reached only through CommSystem:OnMessageReceived, which has checked the sender is an officer
-- and the channel GUILD (issue #78). Any other caller must check the same.
function OfficerNotes:HandleAllIncoming(data)
    if not BRutus:IsOfficer() then return end

    local ok, incoming = LibSerialize:Deserialize(data)
    if not ok or type(incoming) ~= "table" then return end

    if not BRutus.db.officerNotes then BRutus.db.officerNotes = {} end

    for incomingKey, playerData in pairs(incoming) do
        local playerKey = BRutus:LocalMemberKey(incomingKey)   -- the sender's key, as this client's (#97)
        if type(playerData) == "table" then
            if not BRutus.db.officerNotes[playerKey] then
                BRutus.db.officerNotes[playerKey] = { notes = {}, tags = {} }
            end
            self:MergeSheet(BRutus.db.officerNotes[playerKey], playerData)
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
    return existing
end
