----------------------------------------------------------------------
-- Guild OS - Calendar sub-panel (month grid)
-- Embedded as the first sub-tab of the Guild hub. Month view with event
-- markers; click a day to RSVP to its events. Officers get a "New Event"
-- button plus per-event Edit / Delete, all driven through a shared editor
-- popup (title, date, time, size, description).
-- Backed by GuildOS.Calendar (synced "event" domain).
-- Time basis: the client's date()/time() used consistently (assumes the guild
-- shares one timezone, which is the normal case).
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local function CAL() return BRutus.Calendar end

local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local ROLES    = { "TANK", "HEALER", "DPS" }
local SIZES    = { 10, 25, 40 }

local COLS, ROWS = 7, 6
local CELL_H  = 44
local NAV_Y   = -6
local WD_Y    = -34
local GRID_Y  = -50
local GRID_X  = 8

-- Date helpers (noon avoids DST edge issues).
local function noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function daysInMonth(y, m) return date("*t", noon(y, m + 1, 0)).day end
local function firstWeekday(y, m) return date("*t", noon(y, m, 1)).wday end   -- 1=Sun..7=Sat
local function dayKey(y, m, d) return y * 10000 + m * 100 + d end
local function keyOfTs(ts) local t = date("*t", ts); return dayKey(t.year, t.month, t.day) end
local function roleLabel(r)
    if r == "TANK" then return L["Tank"] end
    if r == "HEALER" then return L["Healer"] end
    return L["DPS"]
end

-- Per-category accent colour for grid markers, header tags, and picker pills.
-- Tokens mirror Calendar.KINDS; unknown/legacy kinds fall back to RAID.
local KIND_COLOR = {
    RAID    = { r = 0.86, g = 0.34, b = 0.34 },
    DUNGEON = { r = 0.92, g = 0.66, b = 0.30 },
    PVP     = { r = 0.74, g = 0.48, b = 0.92 },
    FARM    = { r = 0.46, g = 0.78, b = 0.48 },
    SOCIAL  = { r = 0.40, g = 0.68, b = 0.92 },
    OTHER   = { r = 0.70, g = 0.72, b = 0.78 },
}
local function kindColor(k) return KIND_COLOR[k] or KIND_COLOR.RAID end
local function kindLabel(k) return (CAL() and CAL().KindLabel and CAL():KindLabel(k)) or k end

----------------------------------------------------------------------
-- Event editor popup (shared by create + edit).
-- A single lazily-built dialog. :Open(dayKey, event) fills it: pass an
-- event to edit it, or just a dayKey to create a new one on that day.
----------------------------------------------------------------------
local function parseDate(s)
    local y, m, d = tostring(s or ""):match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return y, m, d
end

local function parseTime(s)
    local hh, mm = tostring(s or ""):match("^(%d%d?):(%d%d)$")
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm or hh > 23 or mm > 59 then return nil end
    return hh, mm
end

local editor   -- lazily-built singleton

local function buildEditor()
    local f = CreateFrame("Frame", "GuildOSEventEditor", UIParent, "BackdropTemplate")
    f:SetSize(360, 336)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "GuildOSEventEditor")

    local titleFS = UI:CreateTitle(f, "", 14)
    titleFS:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Labelled EditBox factory (single- or multi-line).
    local function fieldBox(x, y, w, labelText, multiline, maxLetters)
        local lbl = UI:CreateText(f, labelText, 10, C.silver.r, C.silver.g, C.silver.b)
        lbl:SetPoint("TOPLEFT", x, y)
        local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        box:SetSize(w, multiline and 84 or 22)
        box:SetPoint("TOPLEFT", x, y - 14)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0.05, 0.05, 0.066, 1)
        box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
        box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        box:SetTextColor(C.white.r, C.white.g, C.white.b)
        box:SetTextInsets(6, 6, multiline and 4 or 0, 0)
        box:SetAutoFocus(false)
        if multiline then box:SetMultiLine(true) end
        if maxLetters then box:SetMaxLetters(maxLetters) end
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return box
    end

    local dateBox  = fieldBox(14,  -42, 118, L["Date (YYYY-MM-DD)"], false, 10)
    local timeBox  = fieldBox(140, -42, 66,  L["Time (HH:MM)"],      false, 5)
    local sizeLbl  = UI:CreateText(f, L["Size"], 10, C.silver.r, C.silver.g, C.silver.b)
    sizeLbl:SetPoint("TOPLEFT", 216, -42)
    local sizeBtn  = UI:CreateButton(f, "25", 44, 22)
    sizeBtn:SetPoint("TOPLEFT", 216, -56)
    sizeBtn.sizeVal = 25
    sizeBtn:SetScript("OnClick", function()
        local idx = 1
        for i, v in ipairs(SIZES) do if v == sizeBtn.sizeVal then idx = i break end end
        sizeBtn.sizeVal = SIZES[(idx % #SIZES) + 1]
        sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
    end)

    -- Category picker (pill toggles). f.kind holds the current selection.
    local kindLbl = UI:CreateText(f, L["Type"], 10, C.silver.r, C.silver.g, C.silver.b)
    kindLbl:SetPoint("TOPLEFT", 14, -84)
    local kindPills = {}
    local function refreshKinds()
        for _, p in ipairs(kindPills) do
            local col = kindColor(p.kind)
            if p.kind == f.kind then
                p:SetBackdropColor(col.r * 0.34, col.g * 0.34, col.b * 0.34, 0.95)
                p:SetBackdropBorderColor(col.r, col.g, col.b, 0.9)
                p.fs:SetTextColor(col.r, col.g, col.b)
            else
                p:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.9)
                p:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
                p.fs:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            end
        end
    end
    do
        local kinds = (CAL() and CAL().KINDS) or { "RAID", "DUNGEON", "PVP", "FARM", "SOCIAL", "OTHER" }
        for i, k in ipairs(kinds) do
            local p = CreateFrame("Button", nil, f, "BackdropTemplate")
            p:SetSize(52, 20)
            p:SetPoint("TOPLEFT", 14 + (i - 1) * 55, -98)
            p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            local fs = p:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            fs:SetPoint("CENTER"); fs:SetText(kindLabel(k))
            p.fs = fs; p.kind = k
            p:SetScript("OnClick", function() f.kind = k; refreshKinds() end)
            kindPills[#kindPills + 1] = p
        end
    end
    refreshKinds()

    local titleBox = fieldBox(14, -128, 332, L["Title"], false, 60)
    local descBox  = fieldBox(14, -178, 332, L["Description (optional)"], true, 500)

    local saveBtn = UI:CreateButton(f, L["Create"], 110, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 14, 14)
    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 24)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    local function commit()
        local y, m, d = parseDate(dateBox:GetText())
        if not y then BRutus:Print(L["Enter a date as YYYY-MM-DD."]); return end
        local hh, mm = parseTime(timeBox:GetText())
        if not hh then BRutus:Print(L["Enter a time as HH:MM."]); return end
        local title = strtrim(titleBox:GetText() or "")
        if title == "" then BRutus:Print(L["An event needs a title and a date/time."]); return end
        local when = time({ year = y, month = m, day = d, hour = hh, min = mm })
        if f.editId then
            CAL():Update(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind)
        else
            CAL():Create(title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind)
        end
        f:Hide()
    end
    saveBtn:SetScript("OnClick", commit)
    dateBox:SetScript("OnEnterPressed", commit)
    timeBox:SetScript("OnEnterPressed", commit)
    titleBox:SetScript("OnEnterPressed", commit)

    function f:Open(dk, event)
        f.editId = event and event.id or nil
        titleFS:SetText(event and L["Edit Event"] or L["New Event"])
        saveBtn.label:SetText(event and L["Save"] or L["Create"])
        f.kind = (event and event.kind and KIND_COLOR[event.kind]) and event.kind or "RAID"
        refreshKinds()
        local y, m, d, hh, mm, size, title, note
        if event then
            local t = date("*t", event.when)
            y, m, d, hh, mm = t.year, t.month, t.day, t.hour, t.min
            size, title, note = event.size or 25, event.title or "", event.note or ""
        else
            y = math.floor(dk / 10000); m = math.floor((dk % 10000) / 100); d = dk % 100
            hh, mm, size, title, note = 20, 0, 25, "", ""
        end
        dateBox:SetText(string.format("%04d-%02d-%02d", y, m, d))
        timeBox:SetText(string.format("%02d:%02d", hh, mm))
        sizeBtn.sizeVal = size; sizeBtn.label:SetText(tostring(size))
        titleBox:SetText(title)
        descBox:SetText(note)
        f:Show(); f:Raise()
        titleBox:SetFocus()
    end

    return f
end

local function openEditor(dk, event)
    if not editor then editor = buildEditor() end
    editor:Open(dk, event)
end

-- Delete confirmation (standard Blizzard popup; avoids accidental loss).
StaticPopupDialogs["GUILDOS_CALENDAR_DELETE"] = {
    text = L["Remove \"%s\" from the calendar? This cannot be undone."],
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        local id = data
        if id == nil and self then id = self.data end   -- older clients pass via dialog.data
        if id then CAL():Delete(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
}
local function confirmDelete(e)
    local dlg = StaticPopup_Show("GUILDOS_CALENDAR_DELETE", e.title or "?", nil, e.id)
    if dlg then dlg.data = e.id end   -- some clients pass data via dialog.data
end

----------------------------------------------------------------------
-- Build the calendar into a Guild-hub sub-panel; return its refresh fn.
----------------------------------------------------------------------
function BRutus:CreateCalendarSub(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- Month navigation
    local prevBtn = UI:CreateButton(f, "<", 26, 22)
    prevBtn:SetPoint("TOPLEFT", GRID_X, NAV_Y)
    local monthLabel = UI:CreateText(f, "", 14, C.gold.r, C.gold.g, C.gold.b)
    monthLabel:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
    monthLabel:SetWidth(170); monthLabel:SetJustifyH("LEFT")
    local nextBtn = UI:CreateButton(f, ">", 26, 22)
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", 4, 0)
    local todayBtn = UI:CreateButton(f, L["Today"], 60, 22)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)

    -- Weekday headers (repositioned in Render to match the dynamic grid width)
    f.wdFS = {}
    for i = 1, COLS do
        f.wdFS[i] = UI:CreateText(f, L[WEEKDAYS[i]], 10, C.silver.r, C.silver.g, C.silver.b)
    end

    -- Day cells
    f.cells = {}
    for idx = 1, COLS * ROWS do
        local cell = CreateFrame("Button", nil, f, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        cell.dayFS = cell:CreateFontString(nil, "OVERLAY")
        cell.dayFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        cell.dayFS:SetPoint("TOPLEFT", 4, -3)
        cell.evtFS = cell:CreateFontString(nil, "OVERLAY")
        cell.evtFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        cell.evtFS:SetPoint("BOTTOMLEFT", 3, 3)
        cell.evtFS:SetPoint("BOTTOMRIGHT", -3, 3)
        cell.evtFS:SetJustifyH("LEFT"); cell.evtFS:SetWordWrap(false)
        cell:SetScript("OnClick", function(self2)
            if self2.dkey then f.selectedKey = self2.dkey; f.Render() end
        end)
        f.cells[idx] = cell
    end

    -- Detail area (below the grid)
    local DET_Y = GRID_Y - ROWS * CELL_H - 12
    local detailLabel = UI:CreateText(f, "", 12, C.gold.r, C.gold.g, C.gold.b)
    detailLabel:SetPoint("TOPLEFT", GRID_X, DET_Y)

    -- Officer "New Event" button — opens the editor popup for the selected day.
    local newBtn = UI:CreateButton(f, L["New Event"], 100, 20)
    newBtn:SetPoint("TOPLEFT", GRID_X, DET_Y - 20)
    newBtn:SetScript("OnClick", function()
        if f.selectedKey then openEditor(f.selectedKey, nil) end
    end)
    f.newBtn = newBtn

    -- Event list holder (scrollable), fills the rest of the panel
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", GRID_X + 4, DET_Y - 46)
    holder:SetPoint("BOTTOMRIGHT", -12, 12)
    f.holder = holder
    local scrollFrame, scrollChild = UI:CreateScrollFrame(holder, "GuildOSCalendarScroll")
    scrollFrame:SetAllPoints()   -- fill the holder; without this the scroll viewport is 0x0 and clips all content
    f.child = scrollChild

    ------------------------------------------------------------------
    -- Render (grid sizes to the current panel width)
    ------------------------------------------------------------------
    function f.Render()
        local W = f:GetWidth()
        if not W or W < 120 then W = 1000 end
        local cellW = math.floor((W - GRID_X - 12) / COLS)

        monthLabel:SetText(date("%b %Y", noon(f.viewYear, f.viewMonth, 1)))

        for i = 1, COLS do
            f.wdFS[i]:ClearAllPoints()
            f.wdFS[i]:SetPoint("TOPLEFT", GRID_X + (i - 1) * cellW + 4, WD_Y)
        end

        -- Bucket events by day.
        local byDay = {}
        for _, e in pairs(CAL():GetEvents()) do
            if not e.canceled then
                local k = keyOfTs(e.when)
                byDay[k] = byDay[k] or {}
                byDay[k][#byDay[k] + 1] = e
            end
        end

        local dim = daysInMonth(f.viewYear, f.viewMonth)
        local lead = firstWeekday(f.viewYear, f.viewMonth) - 1
        local todayKey = keyOfTs(GetServerTime())

        for idx = 1, COLS * ROWS do
            local col = (idx - 1) % COLS
            local row = math.floor((idx - 1) / COLS)
            local cell = f.cells[idx]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", GRID_X + col * cellW, GRID_Y - row * CELL_H)
            cell:SetSize(cellW - 2, CELL_H - 2)

            local dayNum = idx - lead
            if dayNum < 1 or dayNum > dim then
                cell.dayFS:SetText(""); cell.evtFS:SetText(""); cell.dkey = nil
                cell:SetBackdropColor(0.04, 0.04, 0.05, 0.6)
                cell:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.15)
            else
                local k = dayKey(f.viewYear, f.viewMonth, dayNum)
                cell.dkey = k
                cell.dayFS:SetText(dayNum); cell.dayFS:SetTextColor(1, 1, 1)
                local evs = byDay[k]
                if evs then
                    table.sort(evs, function(a, b) return a.when < b.when end)
                    local line = date("%H:%M ", evs[1].when) .. (evs[1].title or "")
                    if #evs > 1 then line = "+" .. #evs .. " " .. line end
                    cell.evtFS:SetText(line)
                    local kc = kindColor(evs[1].kind)
                    cell.evtFS:SetTextColor(kc.r, kc.g, kc.b)
                else
                    cell.evtFS:SetText("")
                end
                if k == f.selectedKey then
                    cell:SetBackdropColor(C.accent.r * 0.30, C.accent.g * 0.30, C.accent.b * 0.30, 0.95)
                    cell:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.9)
                elseif k == todayKey then
                    cell:SetBackdropColor(0.14, 0.13, 0.08, 0.95)
                    cell:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.8)
                else
                    cell:SetBackdropColor(0.09, 0.09, 0.12, 0.9)
                    cell:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
                end
            end
        end

        f.RenderDetail(byDay)
    end

    ------------------------------------------------------------------
    -- Detail for the selected day
    ------------------------------------------------------------------
    function f.RenderDetail(byDay)
        local isOfficer = BRutus:IsOfficer()
        local sel = f.selectedKey
        if sel then
            local y = math.floor(sel / 10000); local m = math.floor((sel % 10000) / 100); local d = sel % 100
            detailLabel:SetText(date("%A, %d %b %Y", noon(y, m, d)))
        else
            detailLabel:SetText(L["Select a day"])
        end
        f.newBtn:SetShown(isOfficer and sel ~= nil)

        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local evs = (sel and byDay and byDay[sel]) or {}
        local yy = 0
        -- Per-day render is wrapped so a single malformed event can't blank the
        -- whole list; any failure is surfaced inline instead.
        local okAll, errAll = pcall(function()
        for _, e in ipairs(evs) do
            local comp = CAL():GetComposition(e)
            local mine = CAL():MyRsvp(e)

            local kc = kindColor(e.kind)
            local tag = string.format("|cff%02x%02x%02x[%s]|r ", kc.r * 255, kc.g * 255, kc.b * 255, kindLabel(e.kind))
            local head = UI:CreateText(child, date("%H:%M ", e.when) .. tag .. "|cffFFFFFF" .. (e.title or "") .. "|r  |cff888888(" .. (e.size or 25) .. ")|r",
                12, C.gold.r, C.gold.g, C.gold.b)
            head:SetPoint("TOPLEFT", 4, -yy)
            if isOfficer then
                local ev = e
                local delBtn = UI:CreateButton(child, L["Delete"], 58, 18)
                delBtn:SetPoint("TOPRIGHT", -4, -yy)
                delBtn:SetScript("OnClick", function() confirmDelete(ev) end)
                local editBtn = UI:CreateButton(child, L["Edit"], 48, 18)
                editBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                editBtn:SetScript("OnClick", function() openEditor(nil, ev) end)
            end
            yy = yy + 20

            local compFS = UI:CreateText(child, string.format(L["Tanks %d, Heals %d, DPS %d  (%d going, %d tentative)"],
                comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS, comp.yes, comp.tentative),
                10, C.silver.r, C.silver.g, C.silver.b)
            compFS:SetPoint("TOPLEFT", 6, -yy)
            yy = yy + 18

            if e.note and e.note ~= "" then
                local noteFS = UI:CreateText(child, e.note, 10, C.textDim.r, C.textDim.g, C.textDim.b)
                noteFS:SetPoint("TOPLEFT", 6, -yy)
                noteFS:SetWidth(child:GetWidth() - 12); noteFS:SetJustifyH("LEFT")
                yy = yy + math.max(14, (noteFS:GetStringHeight() or 12) + 6)
            end

            local id = e.id
            local roleBtn = UI:CreateButton(child, roleLabel((mine and mine.role) or "DPS"), 66, 18)
            roleBtn:SetPoint("TOPLEFT", 6, -yy)
            roleBtn.role = (mine and mine.role) or "DPS"
            roleBtn:SetScript("OnClick", function()
                local i = 1
                for j, v in ipairs(ROLES) do if v == roleBtn.role then i = j break end end
                roleBtn.role = ROLES[(i % #ROLES) + 1]
                roleBtn.label:SetText(roleLabel(roleBtn.role))
            end)
            local function rsvpBtn(text, status, xoff, col)
                local b = UI:CreateButton(child, text, 64, 18)
                b:SetPoint("LEFT", roleBtn, "RIGHT", xoff, 0)
                if mine and mine.status == status then b:SetBaseColor(col.r * 0.34, col.g * 0.34, col.b * 0.34, 0.95) end
                b:SetScript("OnClick", function() CAL():Rsvp(id, status, roleBtn.role) end)
                return b
            end
            rsvpBtn(L["Going"],     "yes",       8,   C.online)
            rsvpBtn(L["Tentative"], "tentative", 76,  C.gold)
            rsvpBtn(L["Absent"],    "no",        144, C.red)
            yy = yy + 24

            local going = {}
            for _, r in pairs(e.rsvps or {}) do
                if r.status == "yes" then
                    local cr, cg, cb = BRutus:GetClassColor(r.class)
                    going[#going + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, r.name or "?")
                end
            end
            if #going > 0 then
                local goFS = UI:CreateText(child, L["Going: "] .. table.concat(going, ", "), 9, C.textDim.r, C.textDim.g, C.textDim.b)
                goFS:SetPoint("TOPLEFT", 6, -yy); goFS:SetWidth(child:GetWidth() - 12); goFS:SetJustifyH("LEFT")
                yy = yy + math.max(14, (goFS:GetStringHeight() or 12) + 4)
            end
            yy = yy + 10
        end
        end)
        if not okAll then
            local errFS = UI:CreateText(child, "|cffFF6666" .. tostring(errAll) .. "|r", 10, 1, 0.4, 0.4)
            errFS:SetPoint("TOPLEFT", 6, -yy)
            errFS:SetWidth(math.max(50, child:GetWidth() - 12)); errFS:SetJustifyH("LEFT")
            yy = yy + math.max(40, (errFS:GetStringHeight() or 20) + 10)
        end

        if sel and #evs == 0 then
            local none = UI:CreateText(child, isOfficer and L["No events. Use New Event to add one."] or L["No events this day."],
                10, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, yy))
    end

    prevBtn:SetScript("OnClick", function()
        f.viewMonth = f.viewMonth - 1
        if f.viewMonth < 1 then f.viewMonth = 12; f.viewYear = f.viewYear - 1 end
        f.Render()
    end)
    nextBtn:SetScript("OnClick", function()
        f.viewMonth = f.viewMonth + 1
        if f.viewMonth > 12 then f.viewMonth = 1; f.viewYear = f.viewYear + 1 end
        f.Render()
    end)
    todayBtn:SetScript("OnClick", function()
        local t = date("*t", GetServerTime())
        f.viewYear, f.viewMonth, f.selectedKey = t.year, t.month, dayKey(t.year, t.month, t.day)
        f.Render()
    end)

    -- Initial view = current month, today selected.
    local t = date("*t", GetServerTime())
    f.viewYear, f.viewMonth, f.selectedKey = t.year, t.month, dayKey(t.year, t.month, t.day)

    -- Live-refresh while visible as synced events/RSVPs arrive.
    if BRutus.Calendar then
        BRutus.Calendar.uiRefresh = function() if panel:IsShown() then f.Render() end end
    end

    return f.Render
end

----------------------------------------------------------------------
-- Entry point (command): open the roster on the Guild hub's Calendar sub-tab.
----------------------------------------------------------------------
function BRutus:ShowCalendar()
    if not self.RosterFrame then self.RosterFrame = BRutus.CreateRosterFrame() end
    if not self.RosterFrame:IsShown() then self.RosterFrame:Show() end
    if self.RosterFrame.SetActiveTab then self.RosterFrame:SetActiveTab("guild") end
    local gp = self.RosterFrame.tabPanels and self.RosterFrame.tabPanels["guild"]
    if gp and gp.SelectSub then gp.SelectSub("calendar") end
end
