----------------------------------------------------------------------
-- Guild OS - Bulletin Board
-- Officers post short notices; everyone running the addon sees them.
-- Officer-authoritative: the board is broadcast as a revision-checked
-- snapshot via SyncService (domain "bulletin"). New posts also surface
-- in the login digest.
--
-- How long a notice lasts (issue #418): the officer picks it when posting,
-- some days or until it is removed. A notice that lasts some days carries
-- `exp`, the server time it ends; one without `exp` (every notice made
-- before #418, and "until I close it") lasts until removed, as before. The
-- field rides inside the same snapshot: an older client keeps and re-sends
-- it untouched and simply shows the notice until removed. Each client keeps
-- which notices it has told this player about (db.bulletin.seen), so the
-- login digest, or a chat line, tells each active one once.
----------------------------------------------------------------------
local Bulletin = {}
GuildOS.Bulletin = Bulletin
local L = GuildOS.L

local MAX = 20
local DAY = 86400
local TELL = 3        -- notices told at login, the newest; the Now tab shows as many
-- What the officer can pick: 0 is "until I close it".
Bulletin.DURATIONS = { 0, 1, 3, 7, 14, 30 }

local function serverNow() return GetServerTime() end

function Bulletin:Initialize()
    GuildOS.db.bulletin = GuildOS.db.bulletin or { messages = {} }
    GuildOS.db.bulletin.messages = GuildOS.db.bulletin.messages or {}
    if type(GuildOS.db.bulletin.seen) ~= "table" then
        -- First run with #418: every notice already on the board counts as told; only what arrives after is new.
        local seen = {}
        for _, m in ipairs(GuildOS.db.bulletin.messages) do
            local key = Bulletin.Key(m)
            if key then seen[key] = true end
        end
        GuildOS.db.bulletin.seen = seen
    end
    if GuildOS.SyncService then
        GuildOS.SyncService:On("bulletin", function(env) Bulletin:OnSync(env) end)
    end
end

function Bulletin:GetMessages()
    return (GuildOS.db.bulletin and GuildOS.db.bulletin.messages) or {}
end

-- What a notice is remembered as told by: its id, or, for one from the wire without one, who posted it, when and
-- its text, which do not change from one snapshot to the next. Nil for what is not a notice.
function Bulletin.Key(m)
    if type(m) ~= "table" then return nil end
    if m.id ~= nil then return tostring(m.id) end
    return "~" .. tostring(m.author or "?") .. "|" .. tostring(m.ts or 0) .. "|" .. tostring(m.text or "")
end

-- When a notice ends (a server time), or nil when it lasts until removed. It came over the wire: a number or nothing.
function Bulletin.Expires(m)
    local exp = type(m) == "table" and tonumber(m.exp)
    if exp and exp > 0 then return exp end
    return nil
end

function Bulletin.IsActive(m, now)
    local exp = Bulletin.Expires(m)
    return type(m) == "table" and (exp == nil or exp > (now or serverNow()))
end

-- The notices still running, the newest first, at most `limit`.
function Bulletin:Active(now, limit)
    now = now or serverNow()
    local out = {}
    for _, m in ipairs(self:GetMessages()) do
        if self.IsActive(m, now) and type(m.text) == "string" and m.text ~= "" then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
    if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
    return out
end

-- The active notices this player has not been told about yet, the newest first, at most `limit`.
function Bulletin:Unseen(now, limit)
    local seen, out = GuildOS.db.bulletin.seen or {}, {}
    for _, m in ipairs(self:Active(now)) do
        if not seen[Bulletin.Key(m)] then out[#out + 1] = m end
        if limit and #out >= limit then break end
    end
    return out
end

-- Every active notice has now been told (the ones over the limit too: they are not dripped login after login),
-- and what left the board is forgotten.
function Bulletin:MarkSeen(now)
    local seen, kept = GuildOS.db.bulletin.seen or {}, {}
    for _, m in ipairs(self:Active(now)) do kept[Bulletin.Key(m)] = true end
    for _, m in ipairs(self:GetMessages()) do
        local key = Bulletin.Key(m)
        if key and seen[key] then kept[key] = true end
    end
    GuildOS.db.bulletin.seen = kept
end

-- The picker's choices: { value = days, text }.
function Bulletin:DurationOptions()
    local opts = {}
    for _, days in ipairs(self.DURATIONS) do
        local text = days == 0 and L["Until I close it"]
            or days == 1 and L["For 1 day"] or string.format(L["For %d days"], days)
        opts[#opts + 1] = { value = days, text = text }
    end
    return opts
end

-- A notice's line under its text: who, when, and how long it lasts.
function Bulletin.MetaText(m, now)
    local s = (m.author or "?") .. " · " .. GuildOS:DateText(tonumber(m.ts) or 0, " %H:%M")
    local exp = Bulletin.Expires(m)
    if exp then
        if exp > (now or serverNow()) then
            s = s .. " · " .. string.format(L["until %s"], GuildOS:DateText(exp, " %H:%M"))
        else
            s = s .. " · " .. L["no longer shown"]
        end
    end
    return s
end

-- One notice as a line: in the digest and in the chat. Its text is an officer's: no links or textures.
function Bulletin.Line(m)
    return "|cffEDCC7B" .. L["Notice:"] .. "|r " .. GuildOS:SanitizeUserText(m.text or "")
        .. " |cff9D9D9D(" .. GuildOS:SanitizeUserText(m.author or "?") .. ")|r"
end

-- The notices not told yet go to the chat, a line each, and are told. Returns how many lines.
function Bulletin:TellInChat(now)
    now = now or serverNow()
    local list = self:Unseen(now, TELL)
    for _, m in ipairs(list) do GuildOS:Print(self.Line(m)) end
    self:MarkSeen(now)
    return #list
end

-- The login digest has had its turn (issue #418): from here a notice that arrives is told in the chat.
function Bulletin:LoginDone()
    self.loginDone = true
end

-- What the board lists: every notice for an officer, who can remove the ones that ended; a member sees the active.
function Bulletin:Listed(now)
    if GuildOS:IsOfficer() then
        local out = {}
        for _, m in ipairs(self:GetMessages()) do
            if type(m) == "table" then out[#out + 1] = m end
        end
        return out
    end
    now = now or serverNow()
    local out = {}
    for _, m in ipairs(self:GetMessages()) do
        if self.IsActive(m, now) then out[#out + 1] = m end
    end
    return out
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Officer mutations
----------------------------------------------------------------------
-- `days`: how long it lasts; nil or 0 until it is removed.
function Bulletin:Post(text, days)
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    text = strtrim(text or "")
    if text == "" then return end
    local msgs = self:GetMessages()
    local ts = GetServerTime()
    local m = { id = newId(), text = text, author = GuildOS.Compat.PlayerName(), ts = ts }
    days = math.floor(tonumber(days) or 0)
    if days > 0 then m.exp = ts + days * DAY end
    table.insert(msgs, 1, m)
    -- The officer wrote it: it is not told back to them.
    GuildOS.db.bulletin.seen = GuildOS.db.bulletin.seen or {}
    GuildOS.db.bulletin.seen[m.id] = true
    while #msgs > MAX do table.remove(msgs) end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Remove(id)
    if not GuildOS:IsOfficer() then return end
    local msgs = self:GetMessages()
    for i, m in ipairs(msgs) do
        if m.id == id then table.remove(msgs, i); break end
    end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Clear()
    if not GuildOS:IsOfficer() then return end
    GuildOS.db.bulletin.messages = {}
    self:Broadcast()
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync (domain "bulletin")
----------------------------------------------------------------------
function Bulletin:Broadcast()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
    local rev = GuildOS.SyncService:NextRevision("bulletin", "board")
    GuildOS.SyncService:Publish("bulletin", "snapshot", { messages = self:GetMessages() }, { rev = rev })
end

-- Cold-sync backfill: re-broadcast the current board snapshot at its STORED
-- revision (never a bumped one, unlike Broadcast) so an officer offline for
-- the last post/removal converges on login. Answering the sync REQUEST with
-- the existing revision keeps it idempotent: ShouldApply drops it for a peer
-- already at that revision and applies it only for one that missed the edit,
-- so a stale re-broadcast can never overwrite a newer board. A revision of 0
-- means nothing authoritative has been posted yet, so there is nothing to
-- backfill. Officers only. Called from CommSystem:HandleRequest.
function Bulletin:Backfill()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
    local rev = GuildOS.SyncService:GetRevision("bulletin", "board")
    if rev <= 0 then return end
    GuildOS.SyncService:Publish("bulletin", "snapshot", { messages = self:GetMessages() }, { rev = rev })
end

function Bulletin:OnSync(env)
    if env.act == "snapshot" and env.data
        and GuildOS.SyncService:ShouldApply("bulletin", "board", env.rev) then
        local msgs = {}
        for _, m in ipairs(type(env.data.messages) == "table" and env.data.messages or {}) do
            if type(m) == "table" then msgs[#msgs + 1] = m end
        end
        GuildOS.db.bulletin.messages = msgs
        GuildOS.SyncService:SetRevision("bulletin", "board", env.rev)
        -- After the login digest, a notice that arrives is told in the chat; before it, the digest tells it.
        if self.loginDone then self:TellInChat() end
        self:Refresh()
    end
end

function Bulletin:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Bulletin:Show()
    local UI = GuildOS.UI
    local C = GuildOS.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSBulletinFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 380)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Guild Bulletin"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local listTop = -44
        if GuildOS:IsOfficer() then
            -- The shared field, labelled, then its button: as the Guild tab's Bulletin draws it (#371).
            local label = UI:CreateText(f, L["Notice:"], 12)
            local postBtn = UI:CreateButton(f, L["Post"], 80, 24)
            -- How long it lasts (#418), between the field and its button.
            local lasts = UI:CreateDropdown(f, 110, 24)
            lasts:SetOptions(GuildOS.Bulletin:DurationOptions())
            lasts:SetValue(0)
            local box = UI:CreateInput(f, 0, 24, { max = 200 })
            box:SetPoint("TOPLEFT", 16 + math.ceil(label:GetStringWidth() or 0) + 8, -42)
            box:SetPoint("TOPRIGHT", -(16 + UI.ReserveFor(postBtn, 8) + UI.ReserveFor(lasts, 8)), -42)
            label:SetPoint("RIGHT", box, "LEFT", -8, 0)
            lasts:SetPoint("LEFT", box, "RIGHT", 8, 0)
            postBtn:SetPoint("LEFT", lasts, "RIGHT", 8, 0)
            f.lasts = lasts
            local function doPost()
                GuildOS.Bulletin:Post(box:GetText(), lasts:GetValue())
                box:SetText("")
                box:ClearFocus()
            end
            box:SetScript("OnEnterPressed", doPost)
            postBtn:SetScript("OnClick", doPost)
            listTop = -76
        end

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 16, listTop)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSBulletinScroll")
        scroll:SetAllPoints()
        -- The rows hang from both of the child's top corners; it keeps the list's width (#371).
        UI:BindScrollChildWidth(scroll, child)
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end

        local msgs = GuildOS.Bulletin:Listed()
        local y, isOfficer = 0, GuildOS:IsOfficer()
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 12, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 0, -y)
            textFS:SetPoint("TOPRIGHT", isOfficer and -30 or 0, -y)
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child, GuildOS.Bulletin.MetaText(m),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)  -- the multiplication sign
                del:SetPoint("TOPRIGHT", 0, -y)
                local id = m.id
                del:SetScript("OnClick", function() GuildOS.Bulletin:Remove(id) end)
            end
            y = y + th + 22
        end
        if #msgs == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end
