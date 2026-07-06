----------------------------------------------------------------------
-- Guild OS - Recruitment Beacon UI
-- Officer composer (create the guild's ad) + recruit inbox (browse/filter
-- ads heard over the Chehul mesh). Engine: GuildOS.RecruitBeacon.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local function RB() return BRutus.RecruitBeacon end

-- Friendly labels for guild-focus tokens.
local FOCUS_LABEL = {
    RAID = "Raid", PVP = "PvP", CASUAL = "Casual",
    LEVELING = "Leveling", SOCIAL = "Social", RP = "RP",
}

-- Display label for any token (role words, localized class names, focus, langs).
local function TokenLabel(t)
    if t == "TANK"   then return L["Tank"]   end
    if t == "HEALER" then return L["Healer"] end
    if t == "DPS"    then return L["DPS"]    end
    if FOCUS_LABEL[t] then return L[FOCUS_LABEL[t]] end
    local cn = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[t]
    if cn then return cn end
    return t   -- language codes (enUS/ptBR/…) show as-is
end

local function TokenColor(t)
    if BRutus.ClassColors and BRutus.ClassColors[t] then
        return BRutus:GetClassColor(t)   -- class token
    end
    return C.silver.r, C.silver.g, C.silver.b
end

-- Generic list-membership helpers (work on ad.needs / ad.langs / ad.focus).
local function HasTok(list, token)
    for _, t in ipairs(list or {}) do if t == token then return true end end
    return false
end

local function ToggleTok(list, token)
    for i, t in ipairs(list) do
        if t == token then table.remove(list, i); return end
    end
    table.insert(list, token)
end

-- Shared styled backdrop for both popups.
local function StylePopupFrame(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, name)
    return f
end

-- A labelled EditBox row; returns the editbox.
local function MakeInput(parent, y, labelText, width)
    local lbl = UI:CreateText(parent, labelText, 10, C.silver.r, C.silver.g, C.silver.b)
    lbl:SetPoint("TOPLEFT", 12, y)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", 12, y - 14)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(C.white.r, C.white.g, C.white.b)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

----------------------------------------------------------------------
-- OFFICER COMPOSER
----------------------------------------------------------------------
local ROLES   = { "TANK", "HEALER", "DPS" }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local FOCUS   = { "RAID", "PVP", "CASUAL", "LEVELING", "SOCIAL", "RP" }
local LANGS   = { "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU" }
local NEEDS   = {}
for _, t in ipairs(ROLES)   do NEEDS[#NEEDS + 1] = t end
for _, t in ipairs(CLASSES) do NEEDS[#NEEDS + 1] = t end
local TTL_CYCLE = { 1, 3, 7, 14, 30 }

local function BuildComposer()
    local f = StylePopupFrame("GuildOSRecruitComposer", 410, 440)

    local title = UI:CreateTitle(f, L["Recruitment Beacon"], 13)
    title:SetPoint("TOPLEFT", 12, -10)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    local enable = UI:CreateCheckbox(f, L["Broadcast this ad while I'm online"], 16)
    enable:SetPoint("TOPLEFT", 10, -34)
    enable.checkbox.onChanged = function(_, checked)
        RB():SetAdField("enabled", checked and true or false)
        if checked then RB():Broadcast() end
    end

    f.refreshers = {}

    -- A wrapped grid of toggle buttons bound to a list field of the ad
    -- (needs / focus / langs). Returns the bottom y so sections flow.
    local function Grid(labelText, tokens, field, startY)
        if labelText ~= "" then
            local lbl = UI:CreateText(f, labelText, 10, C.silver.r, C.silver.g, C.silver.b)
            lbl:SetPoint("TOPLEFT", 12, startY)
        end
        local btns, refresh = {}, nil
        local x, y = 12, startY - 14
        for _, tok in ipairs(tokens) do
            local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
            btn:SetSize(56, 20)
            btn:SetPoint("TOPLEFT", x, y)
            btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            local fs = btn:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            fs:SetPoint("CENTER")
            fs:SetText(TokenLabel(tok))
            btn.token = tok; btn.fs = fs
            btn:SetScript("OnClick", function()
                ToggleTok(RB():GetAd()[field], tok)
                RB():MarkEdited()
                if refresh then refresh() end
            end)
            btns[#btns + 1] = btn
            x = x + 62
            if x > 360 then x = 12; y = y - 24 end
        end
        refresh = function()
            local list = RB():GetAd()[field]
            for _, btn in ipairs(btns) do
                if HasTok(list, btn.token) then
                    local r, g, b = TokenColor(btn.token)
                    btn:SetBackdropColor(r * 0.35, g * 0.35, b * 0.35, 0.95)
                    btn:SetBackdropBorderColor(r, g, b, 0.9)
                    btn.fs:SetTextColor(1, 1, 1)
                else
                    btn:SetBackdropColor(0.10, 0.10, 0.13, 1.0)
                    btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
                    btn.fs:SetTextColor(0.55, 0.55, 0.55)
                end
            end
        end
        f.refreshers[#f.refreshers + 1] = refresh
        return (x ~= 12) and (y - 24) or y
    end

    local y = -56
    y = Grid(L["Recruiting (click to toggle):"], NEEDS, "needs", y)
    y = Grid(L["Guild focus:"], FOCUS, "focus", y - 10)
    y = Grid(L["Languages:"], LANGS, "langs", y - 10)

    -- Live-for (TTL) cycle button — how long the ad keeps relaying after we log off.
    local ttlLbl = UI:CreateText(f, L["Live for (days):"], 10, C.silver.r, C.silver.g, C.silver.b)
    ttlLbl:SetPoint("TOPLEFT", 12, y - 10)
    local ttlBtn = UI:CreateButton(f, "7", 50, 20)
    ttlBtn:SetPoint("LEFT", ttlLbl, "RIGHT", 8, -1)
    ttlBtn:SetScript("OnClick", function()
        local ad = RB():GetAd()
        local cur, idx = ad.ttlDays or 7, 1
        for i, v in ipairs(TTL_CYCLE) do if v == cur then idx = i break end end
        local nv = TTL_CYCLE[(idx % #TTL_CYCLE) + 1]
        RB():SetAdField("ttlDays", nv)
        ttlBtn.label:SetText(tostring(nv))
    end)
    y = y - 34

    -- Days + note
    local daysBox = MakeInput(f, y, L["Raid days / times:"], 386)
    daysBox:SetScript("OnTextChanged", function(self) RB():SetAdField("days", self:GetText() or "") end)
    y = y - 42
    local noteBox = MakeInput(f, y, L["Short note:"], 386)
    noteBox:SetMaxLetters(120)
    noteBox:SetScript("OnTextChanged", function(self) RB():SetAdField("note", self:GetText() or "") end)

    -- Reach hint + broadcast
    local hint = UI:CreateText(f, L["Yelled zone-wide (cities) + your guild while enabled."], 9, C.accentDim.r, C.accentDim.g, C.accentDim.b)
    hint:SetPoint("BOTTOMLEFT", 12, 40)

    local castBtn = UI:CreateButton(f, L["Broadcast now"], 120, 24)
    castBtn:SetPoint("BOTTOMLEFT", 12, 10)
    castBtn:SetScript("OnClick", function()
        RB():SetAdField("enabled", true)
        enable.checkbox:SetChecked(true)
        RB():Broadcast()
        BRutus:Print(L["Recruitment beacon sent."])
    end)

    function f.Refresh()
        local ad = RB():GetAd()
        enable.checkbox:SetChecked(ad.enabled and true or false)
        daysBox:SetText(ad.days or "")
        noteBox:SetText(ad.note or "")
        ttlBtn.label:SetText(tostring(ad.ttlDays or 7))
        for _, r in ipairs(f.refreshers) do r() end
    end

    return f
end

function BRutus:ShowRecruitBeacon()
    if not (self.IsOfficer and self:IsOfficer()) then
        self:Print(L["Only officers can set the recruitment beacon."])
        return
    end
    local f = self.recruitComposer or BuildComposer()
    self.recruitComposer = f
    f.Refresh()
    f:Show(); f:Raise()
end

----------------------------------------------------------------------
-- RECRUIT INBOX
----------------------------------------------------------------------
local INBOX_ROW_H = 46
local INBOX_MAX   = 8

local function BuildInbox()
    local f = StylePopupFrame("GuildOSRecruitInbox", 430, 130 + INBOX_MAX * INBOX_ROW_H)

    local title = UI:CreateTitle(f, L["Guilds Recruiting"], 13)
    title:SetPoint("TOPLEFT", 12, -10)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    f.matchesOnly = true
    local moChk = UI:CreateCheckbox(f, L["Only guilds that want my class"], 16)
    moChk:SetPoint("TOPLEFT", 10, -32)
    moChk.checkbox:SetChecked(true)
    moChk.checkbox.onChanged = function(_, checked)
        f.matchesOnly = checked and true or false
        f.Refresh()
    end

    local status = UI:CreateText(f, "", 9, C.silver.r, C.silver.g, C.silver.b)
    status:SetPoint("TOPLEFT", 12, -56)

    local LIST_TOP = -72
    f.rows = {}
    local function GetRow(i)
        local row = f.rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, f, "BackdropTemplate")
        row:SetSize(410, INBOX_ROW_H - 4)
        row:SetPoint("TOPLEFT", 10, LIST_TOP - (i - 1) * INBOX_ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })

        row.guildFS = row:CreateFontString(nil, "OVERLAY")
        row.guildFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        row.guildFS:SetPoint("TOPLEFT", 8, -5)

        row.matchFS = row:CreateFontString(nil, "OVERLAY")
        row.matchFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        row.matchFS:SetPoint("LEFT", row.guildFS, "RIGHT", 8, 0)

        row.needsFS = row:CreateFontString(nil, "OVERLAY")
        row.needsFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        row.needsFS:SetPoint("TOPLEFT", 8, -22)
        row.needsFS:SetWidth(300); row.needsFS:SetJustifyH("LEFT"); row.needsFS:SetWordWrap(false)

        row.noteFS = row:CreateFontString(nil, "OVERLAY")
        row.noteFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        row.noteFS:SetPoint("TOPLEFT", 8, -34)
        row.noteFS:SetWidth(300); row.noteFS:SetJustifyH("LEFT"); row.noteFS:SetWordWrap(false)
        row.noteFS:SetTextColor(0.6, 0.6, 0.65)

        row.applyBtn = UI:CreateButton(row, L["Whisper"], 70, 20)
        row.applyBtn:SetPoint("RIGHT", -6, 0)

        f.rows[i] = row
        return row
    end

    local function NeedsString(ad)
        local parts = {}
        for _, tok in ipairs(ROLES) do
            if ad.needs[tok] then parts[#parts + 1] = TokenLabel(tok) end
        end
        for _, tok in ipairs(CLASSES) do
            if ad.needs[tok] then
                local r, g, b = TokenColor(tok)
                parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, TokenLabel(tok))
            end
        end
        return (#parts > 0) and table.concat(parts, ", ") or L["anyone"]
    end

    -- Compact "focus  langs" tag string for the secondary line.
    local function MetaString(ad)
        local foc = {}
        for _, tok in ipairs(FOCUS) do if ad.focus and ad.focus[tok] then foc[#foc + 1] = TokenLabel(tok) end end
        local lang = {}
        for _, tok in ipairs(LANGS) do if ad.langs and ad.langs[tok] then lang[#lang + 1] = tok end end
        local s = (#foc > 0) and table.concat(foc, "/") or ""
        if #lang > 0 then s = (s ~= "" and s .. "  " or "") .. table.concat(lang, ",") end
        return s
    end

    function f.Refresh()
        local all = RB():GetInbox()
        local shown = 0
        for _, ad in ipairs(all) do
            local matches = RB():AdMatchesMe(ad)
            if (not f.matchesOnly or matches) and shown < INBOX_MAX then
                shown = shown + 1
                local row = GetRow(shown)
                local fr, fg, fb = (ad.faction == "A") and 0.4 or 0.9, 0.6, (ad.faction == "A") and 0.95 or 0.4
                row.guildFS:SetTextColor(fr, fg, fb)
                row.guildFS:SetText(ad.guild)
                if matches then
                    row.matchFS:SetTextColor(0.3, 1.0, 0.3)
                    row.matchFS:SetText(L["wants you!"])
                else
                    row.matchFS:SetText("")
                end
                row.needsFS:SetText(L["Wants: "] .. NeedsString(ad))
                local noteLine = ad.note ~= "" and ad.note or ""
                if ad.days ~= "" then noteLine = ad.days .. (noteLine ~= "" and "  -  " .. noteLine or "") end
                local meta = MetaString(ad)
                if meta ~= "" then noteLine = meta .. (noteLine ~= "" and "  -  " .. noteLine or "") end
                row.noteFS:SetText(noteLine)
                local from = ad.from
                row.applyBtn:SetScript("OnClick", function()
                    if from and from ~= "" then
                        ChatFrame_OpenChat("/w " .. Ambiguate(from, "none") .. " ")
                    end
                end)
                row.applyBtn:SetShown(ad.from ~= nil and ad.from ~= "")
                row:Show()
            end
        end
        for i = shown + 1, #f.rows do f.rows[i]:Hide() end

        if #all == 0 then
            status:SetText(L["No ads heard yet. You hear them while in a capital city."])
        elseif shown == 0 then
            status:SetText(L["No guild here wants your class right now."])
        else
            status:SetText(string.format(L["%d guild(s) recruiting"], shown))
        end
    end

    return f
end

function BRutus:ShowRecruitInbox()
    local f = self.recruitInbox or BuildInbox()
    self.recruitInbox = f
    -- Live-refresh while open as new ads arrive.
    if self.RecruitBeacon then
        self.RecruitBeacon.onUpdate = function()
            if f:IsShown() then f.Refresh() end
        end
    end
    f.Refresh()
    f:Show(); f:Raise()
end
