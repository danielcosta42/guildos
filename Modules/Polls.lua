----------------------------------------------------------------------
-- Guild OS - Polls / Voting
-- Officers create a poll; members vote. Polls are broadcast via
-- SyncService (domain "poll"): "create"/"close" are officer actions,
-- "vote" is a member action recorded per voter on every client.
----------------------------------------------------------------------
local Polls = {}
BRutus.Polls = Polls
local L = BRutus.L

function Polls:Initialize()
    BRutus.db.polls = BRutus.db.polls or { list = {} }
    BRutus.db.polls.list = BRutus.db.polls.list or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("poll", function(env, sender) Polls:OnSync(env, sender) end)
    end
end

function Polls:GetList() return BRutus.db.polls.list end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function keyOf(name)
    local short = (name or ""):match("^([^-]+)") or name
    return BRutus:GetPlayerKey(short, GetRealmName())
end

-- Sorted polls: open first, then newest.
function Polls:GetSorted()
    local list = {}
    for _, p in pairs(self:GetList()) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if (a.closed and true or false) ~= (b.closed and true or false) then return not a.closed end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return list
end

----------------------------------------------------------------------
-- Mutations
----------------------------------------------------------------------
function Polls:Create(question, options)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    question = strtrim(question or "")
    if question == "" or type(options) ~= "table" or #options < 2 then
        BRutus:Print(L["A poll needs a question and at least 2 options."])
        return
    end
    local p = {
        id = newId(), question = question, options = options, votes = {},
        author = UnitName("player"), ts = GetServerTime(), closed = false,
    }
    self:GetList()[p.id] = p
    if BRutus.SyncService then
        local rev = BRutus.SyncService:NextRevision("poll", p.id)
        BRutus.SyncService:Publish("poll", "create", { poll = {
            id = p.id, question = p.question, options = p.options, author = p.author, ts = p.ts,
        } }, { rev = rev })
    end
    self:Refresh()
end

function Polls:Vote(id, opt)
    local p = self:GetList()[id]
    if not p or p.closed then return end
    p.votes = p.votes or {}
    p.votes[keyOf(UnitName("player"))] = opt
    if BRutus.SyncService then
        BRutus.SyncService:Publish("poll", "vote", { id = id, opt = opt })
    end
    self:Refresh()
end

function Polls:Close(id)
    if not BRutus:IsOfficer() then return end
    local p = self:GetList()[id]
    if not p then return end
    p.closed = true
    if BRutus.SyncService then
        BRutus.SyncService:Publish("poll", "close", { id = id })
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
function Polls:OnSync(env, sender)
    local d = env.data
    if env.act == "create" and d and d.poll then
        local p = d.poll
        if BRutus.SyncService:ShouldApply("poll", p.id, env.rev) then
            local existing = self:GetList()[p.id]
            p.votes = (existing and existing.votes) or {}
            self:GetList()[p.id] = p
            BRutus.SyncService:SetRevision("poll", p.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "close" and d and d.id then
        local p = self:GetList()[d.id]
        if p then p.closed = true; self:Refresh() end
    elseif env.act == "vote" and d and d.id and d.opt then
        local p = self:GetList()[d.id]
        if p and not p.closed then
            p.votes = p.votes or {}
            p.votes[keyOf(sender)] = d.opt
            self:Refresh()
        end
    end
end

function Polls:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Polls:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSPollsFrame", UIParent, "BackdropTemplate")
        f:SetSize(480, 440)
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

        local title = UI:CreateTitle(f, L["Guild Polls"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local listTop = -44
        if BRutus:IsOfficer() then
            local qBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
            qBox:SetSize(330, 24)
            qBox:SetPoint("TOPLEFT", 16, -42)
            qBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            qBox:SetBackdropColor(0.05, 0.05, 0.066, 1)
            qBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
            qBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            qBox:SetTextColor(C.white.r, C.white.g, C.white.b)
            qBox:SetTextInsets(6, 6, 0, 0)
            qBox:SetAutoFocus(false)
            qBox:SetMaxLetters(150)
            qBox:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
            local qPh = qBox:CreateFontString(nil, "OVERLAY")
            qPh:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            qPh:SetPoint("LEFT", 6, 0)
            qPh:SetTextColor(0.4, 0.4, 0.4)
            qPh:SetText(L["Question..."])
            qBox:SetScript("OnTextChanged", function(self2) if self2:GetText() ~= "" then qPh:Hide() else qPh:Show() end end)

            local oBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
            oBox:SetPoint("TOPLEFT", 16, -70)
            oBox:SetSize(420, 56)
            oBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            oBox:SetBackdropColor(0.05, 0.05, 0.066, 1)
            oBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
            oBox:SetMultiLine(true)
            oBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            oBox:SetTextColor(C.white.r, C.white.g, C.white.b)
            oBox:SetTextInsets(6, 6, 4, 4)
            oBox:SetAutoFocus(false)
            oBox:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
            local oHint = UI:CreateText(f, L["One option per line (2-6)"], 8, C.textDim.r, C.textDim.g, C.textDim.b)
            oHint:SetPoint("TOPLEFT", 18, -128)

            local createBtn = UI:CreateButton(f, L["Create Poll"], 110, 24)
            createBtn:SetPoint("LEFT", qBox, "RIGHT", 8, 0)
            createBtn:SetScript("OnClick", function()
                local opts = {}
                for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                    local t = strtrim(line)
                    if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
                end
                BRutus.Polls:Create(qBox:GetText(), opts)
                qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
            end)
            listTop = -146
        end

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, listTop)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSPollsScroll")
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

        local polls = BRutus.Polls:GetSorted()
        local isOfficer = BRutus:IsOfficer()
        local myKey = keyOf(UnitName("player"))
        local y = 0
        for _, p in ipairs(polls) do
            -- Question
            local q = UI:CreateText(child, (p.closed and "|cff888888[" .. L["closed"] .. "]|r " or "") .. p.question,
                12, C.gold.r, C.gold.g, C.gold.b)
            q:SetPoint("TOPLEFT", 4, -y)
            q:SetWidth(child:GetWidth() - (isOfficer and 70 or 10))
            q:SetJustifyH("LEFT")
            if isOfficer and not p.closed then
                local closeBtn = UI:CreateButton(child, L["Close"], 56, 18)
                closeBtn:SetPoint("TOPRIGHT", -2, -y)
                local id = p.id
                closeBtn:SetScript("OnClick", function() BRutus.Polls:Close(id) end)
            end
            y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

            -- Tally
            local total = 0
            local counts = {}
            for _, opt in pairs(p.votes or {}) do
                counts[opt] = (counts[opt] or 0) + 1
                total = total + 1
            end
            local myVote = p.votes and p.votes[myKey]

            for idx, optText in ipairs(p.options or {}) do
                local n = counts[idx] or 0
                local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
                local mine = (myVote == idx)
                local label = string.format("%s  (%d · %d%%)", optText, n, pct)
                local btn = UI:CreateButton(child, label, child:GetWidth() - 8, 20)
                btn:SetPoint("TOPLEFT", 4, -y)
                if mine then
                    btn:SetBaseColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.95)
                    btn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                end
                btn.label:SetJustifyH("LEFT")
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 8, 0)
                if not p.closed then
                    local id, oi = p.id, idx
                    btn:SetScript("OnClick", function() BRutus.Polls:Vote(id, oi) end)
                end
                y = y + 22
            end

            local meta = UI:CreateText(child,
                "|cff888888" .. string.format(L["%d vote(s) · by %s"], total, p.author or "?") .. "|r",
                8, C.textDim.r, C.textDim.g, C.textDim.b)
            meta:SetPoint("TOPLEFT", 4, -y)
            y = y + 22
        end
        if #polls == 0 then
            local empty = UI:CreateText(child, L["No polls yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end
