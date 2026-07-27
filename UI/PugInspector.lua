----------------------------------------------------------------------
-- Guild OS - Pug Inspector UI ("Do I know this pug?")
-- Draggable pooled-row window listing every group member with their
-- classification (Modules/PugInspector.lua). Class-coloured names, tag
-- text coloured by severity (banned = red), an auto-open checkbox bound to
-- a persisted pref via the module getters/setters, and a friendly solo
-- state. The UI holds no classification logic (Rule 10).
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Mod() return BRutus.PugInspector end

local ROW_H    = 22
local HEADER_H = 34
local FOOTER_H = 40

-- Severity -> colour for the tag text.
local SEV_COLOR = {
    high    = C.red,
    warn    = C.gold,
    guild   = C.green,
    unknown = C.textDim,
}

local frame
local rows = {}

----------------------------------------------------------------------
-- Row pool
----------------------------------------------------------------------
local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 10, -HEADER_H - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -10, -HEADER_H - (i - 1) * ROW_H)
    row:SetBackdrop({ bgFile = WHITE })
    row:SetBackdropColor(0, 0, 0, (i % 2 == 0) and 0.10 or 0)

    local nameFS = UI:CreateText(row, "", 11)
    nameFS:SetPoint("LEFT", 6, 0)
    nameFS:SetWidth(96); nameFS:SetJustifyH("LEFT"); nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    local classFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
    classFS:SetPoint("LEFT", 104, 0)
    classFS:SetWidth(66); classFS:SetJustifyH("LEFT"); classFS:SetWordWrap(false)
    row.classFS = classFS

    local tagFS = UI:CreateText(row, "", 11)
    tagFS:SetPoint("LEFT", 174, 0)
    tagFS:SetPoint("RIGHT", -6, 0)
    tagFS:SetJustifyH("LEFT"); tagFS:SetWordWrap(false)
    row.tagFS = tagFS

    rows[i] = row
    return row
end

----------------------------------------------------------------------
-- Refresh: pull a fresh Scan() and repaint. Resets every row's visual
-- state each pass (pooled rows are reused, never assume prior state).
----------------------------------------------------------------------
local function Refresh()
    if not frame then return end
    frame.autoChk.checkbox:SetChecked(Mod():IsAutoOpen())

    local inGroup = (IsInGroup and IsInGroup()) and true or false
    local scan = inGroup and Mod():Scan() or {}
    local count = #scan

    frame.countFS:SetText(inGroup and string.format(L["%d in group"], count) or "")

    if count == 0 then
        for i = 1, #rows do rows[i]:Hide() end
        frame.emptyFS:SetText(inGroup and L["No one else in your group."] or L["You are not in a group."])
        frame.emptyFS:Show()
        frame:SetHeight(HEADER_H + FOOTER_H + 24)
        return
    end
    frame.emptyFS:Hide()

    for i, e in ipairs(scan) do
        local row = GetRow(i)
        local cr, cg, cb = BRutus:GetClassColor(e.class)
        row.nameFS:SetText(e.name or "?")
        row.nameFS:SetTextColor(cr, cg, cb)

        local cn = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class]) or e.class or ""
        row.classFS:SetText(cn)

        local sev = SEV_COLOR[e.severity] or C.text
        local text = (e.severity == "high") and ("! " .. e.tag) or e.tag
        if e.detail and e.detail ~= "" then
            -- Banned reason reads best in parentheses; a note already carries
            -- its own "Note:" prefix. Both are dim so the tag stays primary.
            local d = (e.severity == "high") and ("(" .. e.detail .. ")") or e.detail
            text = text .. "  " .. BRutus:ColorText(d, C.textDim.r, C.textDim.g, C.textDim.b)
        end
        row.tagFS:SetText(text)
        row.tagFS:SetTextColor(sev.r, sev.g, sev.b)
        row:Show()
    end
    for i = count + 1, #rows do rows[i]:Hide() end

    frame:SetHeight(HEADER_H + count * ROW_H + FOOTER_H)
end

----------------------------------------------------------------------
-- Frame construction
----------------------------------------------------------------------
local function BuildFrame()
    local f = CreateFrame("Frame", "GuildOSPugInspector", UIParent, "BackdropTemplate")
    f:SetSize(470, 150)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSPugInspector")

    local title = UI:CreateTitle(f, L["Do I know this pug?"], 13)
    title:SetPoint("TOPLEFT", 12, -10)

    local count = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    count:SetPoint("LEFT", title, "RIGHT", 8, 0)
    f.countFS = count

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    local empty = UI:CreateText(f, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
    empty:SetPoint("TOPLEFT", 16, -HEADER_H - 6)
    empty:Hide()
    f.emptyFS = empty

    local chk = UI:CreateCheckbox(f, L["Auto-open when a flagged player is in the group"], 16)
    chk:SetPoint("BOTTOMLEFT", 10, 12)
    chk.checkbox.onChanged = function(_, checked)
        Mod():SetAutoOpen(checked and true or false)
    end
    f.autoChk = chk

    -- Start hidden: a frame is shown on creation, so TogglePugInspector's first
    -- call would otherwise see IsShown()==true and hide it right away.
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- Public entry points (/gos pug + minimap menu)
----------------------------------------------------------------------
function BRutus:ShowPugInspector()
    frame = frame or BuildFrame()
    Refresh()
    frame:Show(); frame:Raise()
end

function BRutus:TogglePugInspector()
    frame = frame or BuildFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        BRutus:ShowPugInspector()
    end
end

----------------------------------------------------------------------
-- Wire the module's live hooks. The module (loaded before this UI file)
-- drives refresh + auto-open through these callbacks; refresh is a no-op
-- unless the window is currently shown.
----------------------------------------------------------------------
if BRutus.PugInspector then
    BRutus.PugInspector.uiRefresh = function()
        if frame and frame:IsShown() then BRutus:SafeCall(Refresh) end
    end
    BRutus.PugInspector.uiOpen = function()
        BRutus:SafeCall(function() BRutus:ShowPugInspector() end)
    end
end
