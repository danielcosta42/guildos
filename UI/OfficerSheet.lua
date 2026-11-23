----------------------------------------------------------------------
-- Guild OS - The officer's card on the roster (issue #427)
--
-- Two things on top of the roster's hover:
--   * the card's extra lines (RosterCard:AddLines): alts and main in their class colour with the online
--     ones marked, the Mythic+ rating on retail and, to officers only, the join date and days in the
--     guild (MemberHistory), the start of the member's sheet, the last two Guild OS notes and the game's
--     officer note. A member sees only what is public (alts, rating). Everything comes from an index
--     the roster builds once per refresh (NewIndex / IndexRow): a hover never walks the roster.
--   * the card kept open (RosterCard:Toggle, Shift+click on a row): a tooltip of its own that stays
--     until Escape, another Shift+click on the same member, or a Shift+click on another one.
-- And the editor of the member's sheet (GuildOS:ShowOfficerSheetEditor). The data is OfficerNotes'.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local RosterCard = {}
GuildOS.RosterCard = RosterCard

RosterCard.ALTS_SHOWN = 10        -- alts named on the card; the rest are counted
RosterCard.SHEET_LINES = 4        -- lines of the sheet on the card
RosterCard.SHEET_LETTERS = 240    -- and letters
RosterCard.NOTES_SHOWN = 2        -- the newest Guild OS notes
RosterCard.NOTE_BYTES = 120

local GREY = { r = 0.5, g = 0.5, b = 0.5 }

----------------------------------------------------------------------
-- The index (one per roster refresh)
----------------------------------------------------------------------
--- A new index on `links` ([altKey] = mainKey, flat): who is whose alt, both ways, alts sorted by key.
function RosterCard.NewIndex(links)
    local idx = { links = type(links) == "table" and links or {}, altsOf = {}, byKey = {} }
    for alt, main in pairs(idx.links) do
        local list = idx.altsOf[main]
        if not list then list = {}; idx.altsOf[main] = list end
        list[#list + 1] = alt
    end
    for _, list in pairs(idx.altsOf) do table.sort(list) end
    return idx
end

--- One roster line into the index: its name, class file and whether it is online.
function RosterCard.IndexRow(idx, key, name, class, online)
    if idx and key then idx.byKey[key] = { name = name, class = class, online = online and true or false } end
end

local function short(key) return (key:match("^([^-]+)") or key) end

--- A character as the card names it: in its class colour, " (online)" in green when it is; a character
--- not in the guild roster greyed. Pure on the index.
function RosterCard.NameText(idx, key)
    local row = idx and idx.byKey[key]
    local name = row and row.name or short(key)
    if not row then return GuildOS:ColorText(name, GREY.r, GREY.g, GREY.b) end
    local r, g, b = GuildOS:GetClassColor(row.class)
    local text = GuildOS:ColorText(name, r, g, b)
    if row.online then text = text .. " " .. GuildOS:ColorText(L["(online)"], C.green.r, C.green.g, C.green.b) end
    return text
end

--- The alt lines of `key`: { header, names... }. A main names its alts; an alt names its main and the
--- main's other alts. Nil when the character has no link. Pure on the index.
function RosterCard.AltLines(idx, key)
    if not idx or not key then return nil end
    local main = idx.links[key]
    local alts
    local out = {}
    if main then
        out[#out + 1] = string.format(L["Alt of %s"], RosterCard.NameText(idx, main))
        alts = {}
        for _, a in ipairs(idx.altsOf[main] or {}) do
            if a ~= key then alts[#alts + 1] = a end
        end
        if #alts > 0 then out[#out + 1] = string.format(L["Other alts (%d):"], #alts) end
    else
        alts = idx.altsOf[key]
        if not alts or #alts == 0 then return nil end
        out[#out + 1] = string.format(L["Alts (%d):"], #alts)
    end
    for i = 1, math.min(#alts, RosterCard.ALTS_SHOWN) do
        out[#out + 1] = "  " .. RosterCard.NameText(idx, alts[i])
    end
    if #alts > RosterCard.ALTS_SHOWN then
        out[#out + 1] = "  " .. string.format(L["+%d more"], #alts - RosterCard.ALTS_SHOWN)
    end
    return out
end

----------------------------------------------------------------------
-- The card's lines
----------------------------------------------------------------------
local function add(tip, text, color, wrap)
    color = color or C.text
    tip:AddLine(text, color.r, color.g, color.b, wrap)
end

--- The lines this file adds to a roster row's card, in `tip` (a GameTooltip). `data` is the row's member,
--- `idx` the roster's index (nil: no alt lines).
function RosterCard:AddLines(tip, data, idx)
    local key = data.key
    local altLines = self.AltLines(idx, key)
    if altLines then
        tip:AddLine(" ")
        for _, line in ipairs(altLines) do add(tip, line, C.silver) end
    end

    -- Retail (issue #187): the rating in the game's colour, and the keystone.
    local MP = GuildOS.MythicPlus
    local rating = MP and MP:Rating(data.mplus)
    if rating then
        local r, g, b = GuildOS.Compat.RatingColor(rating)
        local text = string.format(L["Mythic+ rating: %d"], rating)
        local keyText = MP:KeystoneText(data.mplus)
        if keyText then text = text .. "  |cff999999" .. keyText .. "|r" end
        tip:AddLine(text, r or C.text.r, g or C.text.g, b or C.text.b)
    end

    -- The birthday, when its module is there (issue #428); it says what this reader may see.
    local B = GuildOS.Birthdays
    if B and type(B.TooltipLine) == "function" then
        local ok, line = pcall(B.TooltipLine, B, key)
        if ok and type(line) == "string" and line ~= "" then add(tip, line, C.silver) end
    end

    if not GuildOS:IsOfficer() then return end

    -- When they joined, and their days in the guild over every passage (issue #425).
    local MH = GuildOS.MemberHistory
    local joinedAt, est
    if MH then joinedAt, est = MH:JoinedAt(key) end
    if joinedAt then
        local days = MH:TenureDays(key)
        local when = (est and "~" or "") .. GuildOS:DateText(joinedAt, "/%Y")
        add(tip, string.format(L["Joined %s, %s days in the guild"], when, days and tostring(days) or "?"), C.silver)
    end

    -- The game's officer note.
    if data.officerNote and data.officerNote ~= "" and GuildOS.Compat.CanViewOfficerNote() then
        add(tip, string.format(L["Officer note: %s"], GuildOS:SanitizeUserText(data.officerNote, 200)), C.silver, true)
    end

    local ON = GuildOS.OfficerNotes
    if not ON or not GuildOS:IsFeatureEnabled("officerNotes") then return end

    -- The start of the member's sheet.
    local sheet = ON:GetSheet(key)
    if sheet then
        local head, more = ON.SheetHead(sheet.text, self.SHEET_LINES, self.SHEET_LETTERS)
        tip:AddLine(" ")
        add(tip, string.format(L["Officer sheet (%s, %s):"], sheet.author or "?", GuildOS:DateText(sheet.ts or 0, "/%Y")), C.gold)
        for line in (head .. "\n"):gmatch("(.-)\n") do
            add(tip, line ~= "" and line or " ", C.text, true)
        end
        if more then add(tip, L["(more on the member's card)"], GREY) end
    end

    -- The newest Guild OS notes.
    local notes = ON:GetNotes(key)
    if #notes > 0 then
        if not sheet then tip:AddLine(" ") end
        for i = 1, math.min(#notes, self.NOTES_SHOWN) do
            local n = notes[i]
            local stamp = n.timestamp and GuildOS:DateText(n.timestamp) or ""
            add(tip, "|cffAAAAAA[" .. GuildOS:SanitizeUserText(n.author or "?", 40) .. " " .. stamp .. "]|r "
                .. GuildOS:SanitizeUserText(n.text, self.NOTE_BYTES), C.text, true)
        end
    end
end

----------------------------------------------------------------------
-- The card kept open (Shift+click, Escape lets go)
----------------------------------------------------------------------
local function lockedTip()
    local tip = RosterCard.tip
    if tip then return tip end
    tip = CreateFrame("GameTooltip", "GuildOSRosterCard", UIParent, "GameTooltipTemplate")
    tip:SetFrameStrata("DIALOG")
    tip:SetScript("OnHide", function() RosterCard.lockedKey = nil end)
    tinsert(UISpecialFrames, "GuildOSRosterCard")
    RosterCard.tip = tip
    return tip
end

--- Keep the card of `row` open where the hover showed it, or let it go when it is that member's already.
--- `fill(row, tip)` draws the card.
function RosterCard:Toggle(row, fill)
    local data = row and row.memberData
    if not data then return end
    local tip = lockedTip()
    if tip:IsShown() and self.lockedKey == data.key then
        tip:Hide()
        return
    end
    local left, top = GameTooltip:IsShown() and GameTooltip:GetLeft(), GameTooltip:IsShown() and GameTooltip:GetTop()
    tip:Hide()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearAllPoints()
    if left and top then
        local s = GameTooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
        tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * s, top * s)
    else
        tip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -5)
    end
    fill(row, tip, true)
    self.lockedKey = data.key
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- The sheet's editor
----------------------------------------------------------------------
local EDITOR_W, EDITOR_H = 440, 330

local function buildEditor()
    local f = CreateFrame("Frame", "GuildOSOfficerSheet", UIParent, "BackdropTemplate")
    f:SetSize(EDITOR_W, EDITOR_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    tinsert(UISpecialFrames, "GuildOSOfficerSheet")
    f:Hide()

    f.title = UI:CreateTitle(f, "", 14)
    f.title:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)
    f.hint = UI:CreateText(f, L["Only officers receive and see it. Never sent to the website."], 9,
        C.textDim.r, C.textDim.g, C.textDim.b)
    f.hint:SetPoint("TOPLEFT", 14, -34)

    -- The text in a scrolling well, so a sheet of many lines stays reachable.
    local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    well:SetPoint("TOPLEFT", 14, -54)
    well:SetPoint("BOTTOMRIGHT", -14, 50)
    well:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(well) })
    well:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    well:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    local scroll = CreateFrame("ScrollFrame", "GuildOSOfficerSheetScroll", well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    UI:SkinScrollBar(scroll, "GuildOSOfficerSheetScroll")
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetWidth(EDITOR_W - 28 - 32)
    edit:SetMaxLetters(GuildOS.OfficerNotes.SHEET_MAX)
    GuildOS:ApplyFont(edit, 12)
    edit:SetTextColor(C.text.r, C.text.g, C.text.b)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.edit = edit

    f.count = UI:CreateText(f, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    f.count:SetPoint("BOTTOMLEFT", 14, 32)
    f.byline = UI:CreateText(f, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    f.byline:SetPoint("BOTTOMRIGHT", -14, 32)
    edit:SetScript("OnTextChanged", function(self)
        local n = GuildOS:Utf8Len(self:GetText() or "")
        f.count:SetText(string.format("%d / %d", n, GuildOS.OfficerNotes.SHEET_MAX))
    end)

    local save = UI:CreateButton(f, L["Save"], 100, 22)
    save:SetPoint("BOTTOMRIGHT", -14, 8)
    UI:SetButtonVariant(save, "primary")
    save:SetScript("OnClick", function()
        local text = edit:GetText()
        edit:ClearFocus()
        f:Hide()   -- first, so the member's card redraws with the new text
        if f.key and GuildOS.OfficerNotes:SetSheet(f.key, text) then
            GuildOS:Print(string.format(L["Officer sheet saved for %s."], f.name or "?"))
        end
    end)
    local cancel = UI:CreateButton(f, CANCEL or L["Cancel"], 100, 22)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() f:Hide() end)
    return f
end

--- Open the editor of the member's sheet. Officers only.
function GuildOS:ShowOfficerSheetEditor(key, name)
    if not self:IsOfficer() or not self.OfficerNotes or type(key) ~= "string" then return end
    local f = RosterCard.editor or buildEditor()
    RosterCard.editor = f
    f.key, f.name = key, name or short(key)
    f.title:SetText(string.format(L["Officer sheet: %s"], f.name))
    local sheet = self.OfficerNotes:GetSheet(key)
    f.edit:SetText(sheet and sheet.text or "")
    f.byline:SetText(sheet and string.format(L["Last edited by %s on %s"], sheet.author or "?",
        self:DateText(sheet.ts or 0, "/%Y")) or "")
    f:Show()
    f.edit:SetFocus()
    f.edit:SetCursorPosition(#(f.edit:GetText() or ""))
end
