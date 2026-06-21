----------------------------------------------------------------------
-- Guild OS - Bulletin Board
-- Officers post short notices; everyone running the addon sees them.
-- Officer-authoritative: the board is broadcast as a revision-checked
-- snapshot via SyncService (domain "bulletin"). New posts also surface
-- in the login digest.
----------------------------------------------------------------------
local Bulletin = {}
BRutus.Bulletin = Bulletin
local L = BRutus.L

local MAX = 20

function Bulletin:Initialize()
    BRutus.db.bulletin = BRutus.db.bulletin or { messages = {} }
    BRutus.db.bulletin.messages = BRutus.db.bulletin.messages or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("bulletin", function(env) Bulletin:OnSync(env) end)
    end
end

function Bulletin:GetMessages()
    return (BRutus.db.bulletin and BRutus.db.bulletin.messages) or {}
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Officer mutations
----------------------------------------------------------------------
function Bulletin:Post(text)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    text = strtrim(text or "")
    if text == "" then return end
    local msgs = self:GetMessages()
    table.insert(msgs, 1, { id = newId(), text = text, author = UnitName("player"), ts = GetServerTime() })
    while #msgs > MAX do table.remove(msgs) end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Remove(id)
    if not BRutus:IsOfficer() then return end
    local msgs = self:GetMessages()
    for i, m in ipairs(msgs) do
        if m.id == id then table.remove(msgs, i); break end
    end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Clear()
    if not BRutus:IsOfficer() then return end
    BRutus.db.bulletin.messages = {}
    self:Broadcast()
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync (domain "bulletin")
----------------------------------------------------------------------
function Bulletin:Broadcast()
    if not BRutus:IsOfficer() or not BRutus.SyncService then return end
    local rev = BRutus.SyncService:NextRevision("bulletin", "board")
    BRutus.SyncService:Publish("bulletin", "snapshot", { messages = self:GetMessages() }, { rev = rev })
end

function Bulletin:OnSync(env)
    if env.act == "snapshot" and env.data
        and BRutus.SyncService:ShouldApply("bulletin", "board", env.rev) then
        BRutus.db.bulletin.messages = env.data.messages or {}
        BRutus.SyncService:SetRevision("bulletin", "board", env.rev)
        self:Refresh()
    end
end

function Bulletin:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Bulletin:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSBulletinFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 380)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
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
        if BRutus:IsOfficer() then
            local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
            box:SetSize(330, 24)
            box:SetPoint("TOPLEFT", 16, -42)
            box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            box:SetBackdropColor(0.05, 0.05, 0.066, 1)
            box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
            box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            box:SetTextColor(C.white.r, C.white.g, C.white.b)
            box:SetTextInsets(6, 6, 0, 0)
            box:SetAutoFocus(false)
            box:SetMaxLetters(200)
            box:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
            local function doPost()
                BRutus.Bulletin:Post(box:GetText())
                box:SetText("")
                box:ClearFocus()
            end
            box:SetScript("OnEnterPressed", doPost)
            local postBtn = UI:CreateButton(f, L["Post"], 80, 24)
            postBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
            postBtn:SetScript("OnClick", doPost)
            listTop = -76
        end

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, listTop)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSBulletinScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local msgs = BRutus.Bulletin:GetMessages()
        local y, isOfficer = 0, BRutus:IsOfficer()
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 11, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 4, -y)
            textFS:SetWidth(child:GetWidth() - (isOfficer and 30 or 10))
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child,
                "|cff888888" .. (m.author or "?") .. " · " .. date("%m/%d %H:%M", m.ts or 0) .. "|r",
                9, C.textDim.r, C.textDim.g, C.textDim.b)
            meta:SetPoint("TOPLEFT", 4, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)  -- ×
                del:SetPoint("TOPRIGHT", -2, -y)
                local id = m.id
                del:SetScript("OnClick", function() BRutus.Bulletin:Remove(id) end)
            end
            y = y + th + 22
        end
        if #msgs == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end
