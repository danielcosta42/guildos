----------------------------------------------------------------------
-- Guild OS - Calendar Panel (month grid)
-- Month view with event markers; click a day to RSVP to its events or (officer)
-- create one. Backed by GuildOS.Calendar (synced "event" domain).
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
local CELL_W, CELL_H = 76, 46
local GRID_X, GRID_Y = 12, -84

-- Date helpers (noon avoids DST edge issues).
local function noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function daysInMonth(y, m) return date("*t", noon(y, m + 1, 0)).day end   -- day 0 of next month
local function firstWeekday(y, m) return date("*t", noon(y, m, 1)).wday end       -- 1=Sun..7=Sat
local function dayKey(y, m, d) return y * 10000 + m * 100 + d end
local function keyOfTs(ts) local t = date("*t", ts); return dayKey(t.year, t.month, t.day) end
local function roleLabel(r)
    if r == "TANK" then return L["Tank"] end
    if r == "HEALER" then return L["Healer"] end
    return L["DPS"]
end

----------------------------------------------------------------------
-- Build the singleton window.
----------------------------------------------------------------------
local function BuildCalendar()
    local f = CreateFrame("Frame", "GuildOSCalendar", UIParent, "BackdropTemplate")
    f:SetSize(568, 620)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSCalendar")

    local title = UI:CreateTitle(f, L["Guild Calendar"], 15)
    title:SetPoint("TOPLEFT", 16, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Month navigation
    local prevBtn = UI:CreateButton(f, "<", 26, 22)
    prevBtn:SetPoint("TOPLEFT", 16, -40)
    local monthLabel = UI:CreateText(f, "", 13, C.gold.r, C.gold.g, C.gold.b)
    monthLabel:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
    monthLabel:SetWidth(150); monthLabel:SetJustifyH("CENTER")
    local nextBtn = UI:CreateButton(f, ">", 26, 22)
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", 10, 0)
    local todayBtn = UI:CreateButton(f, L["Today"], 60, 22)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)

    -- Weekday header
    for i, wd in ipairs(WEEKDAYS) do
        local h = UI:CreateText(f, L[wd], 9, C.silver.r, C.silver.g, C.silver.b)
        h:SetPoint("TOPLEFT", GRID_X + (i - 1) * CELL_W + 4, -68)
    end

    -- Day cells
    f.cells = {}
    for idx = 1, COLS * ROWS do
        local col = (idx - 1) % COLS
        local row = math.floor((idx - 1) / COLS)
        local cell = CreateFrame("Button", nil, f, "BackdropTemplate")
        cell:SetSize(CELL_W - 2, CELL_H - 2)
        cell:SetPoint("TOPLEFT", GRID_X + col * CELL_W, GRID_Y - row * CELL_H)
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        cell.dayFS = cell:CreateFontString(nil, "OVERLAY")
        cell.dayFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        cell.dayFS:SetPoint("TOPLEFT", 4, -3)
        cell.evtFS = cell:CreateFontString(nil, "OVERLAY")
        cell.evtFS:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
        cell.evtFS:SetPoint("BOTTOMLEFT", 3, 3)
        cell.evtFS:SetPoint("BOTTOMRIGHT", -3, 3)
        cell.evtFS:SetJustifyH("LEFT"); cell.evtFS:SetWordWrap(false)
        cell:SetScript("OnClick", function(self2)
            if self2.dkey then f.selectedKey = self2.dkey; f.Render() end
        end)
        f.cells[idx] = cell
    end

    -- Detail area (selected day)
    local DET_Y = GRID_Y - ROWS * CELL_H - 12
    local detailLabel = UI:CreateText(f, "", 12, C.gold.r, C.gold.g, C.gold.b)
    detailLabel:SetPoint("TOPLEFT", 16, DET_Y)

    -- Officer create row (time / title / size / create)
    local createRow = CreateFrame("Frame", nil, f)
    createRow:SetPoint("TOPLEFT", 16, DET_Y - 20)
    createRow:SetSize(536, 26)
    local function mkBox(w, ph)
        local b = CreateFrame("EditBox", nil, createRow, "BackdropTemplate")
        b:SetSize(w, 22)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b:SetBackdropColor(0.05, 0.05, 0.066, 1); b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
        b:SetFont("Fonts\\FRIZQT__.TTF", 11, ""); b:SetTextColor(C.white.r, C.white.g, C.white.b)
        b:SetTextInsets(6, 6, 0, 0); b:SetAutoFocus(false)
        b:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        local p = b:CreateFontString(nil, "OVERLAY"); p:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        p:SetPoint("LEFT", 6, 0); p:SetTextColor(0.4, 0.4, 0.4); p:SetText(ph)
        b:SetScript("OnTextChanged", function(s) p:SetShown((s:GetText() or "") == "") end)
        return b
    end
    local timeBox  = mkBox(52, L["HH:MM"]); timeBox:SetPoint("LEFT", 0, 0); timeBox:SetMaxLetters(5)
    local titleBox = mkBox(220, L["Event title"]); titleBox:SetPoint("LEFT", timeBox, "RIGHT", 6, 0); titleBox:SetMaxLetters(60)
    local sizeBtn  = UI:CreateButton(createRow, "25", 40, 22); sizeBtn:SetPoint("LEFT", titleBox, "RIGHT", 6, 0)
    sizeBtn.sizeVal = 25
    sizeBtn:SetScript("OnClick", function()
        local idx = 1
        for i, v in ipairs(SIZES) do if v == sizeBtn.sizeVal then idx = i break end end
        sizeBtn.sizeVal = SIZES[(idx % #SIZES) + 1]
        sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
    end)
    local createBtn = UI:CreateButton(createRow, L["Create"], 80, 22); createBtn:SetPoint("LEFT", sizeBtn, "RIGHT", 6, 0)
    createBtn:SetScript("OnClick", function()
        if not f.selectedKey then return end
        local y = math.floor(f.selectedKey / 10000)
        local m = math.floor((f.selectedKey % 10000) / 100)
        local d = f.selectedKey % 100
        local hh, mm = (timeBox:GetText() or ""):match("^(%d%d?):(%d%d)$")
        hh, mm = tonumber(hh), tonumber(mm)
        if not hh or not mm or hh > 23 or mm > 59 then
            BRutus:Print(L["Enter a time as HH:MM."]); return
        end
        local when = time({ year = y, month = m, day = d, hour = hh, min = mm })
        CAL():Create(titleBox:GetText(), when, sizeBtn.sizeVal, "")
        titleBox:SetText(""); timeBox:SetText(""); titleBox:ClearFocus(); timeBox:ClearFocus()
    end)
    f.createRow = createRow

    -- Event list holder (scrollable)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", 12, DET_Y - 52)
    holder:SetPoint("BOTTOMRIGHT", -12, 14)
    local _, scrollChild = UI:CreateScrollFrame(holder, "GuildOSCalendarScroll")
    f.child = scrollChild

    ------------------------------------------------------------------
    -- Render
    ------------------------------------------------------------------
    function f.Render()
        -- Month label
        monthLabel:SetText(date("%b %Y", noon(f.viewYear, f.viewMonth, 1)))

        -- Bucket events by day for the visible month range.
        local byDay = {}
        for _, e in pairs(CAL():GetEvents()) do
            if not e.canceled then
                local k = keyOfTs(e.when)
                byDay[k] = byDay[k] or {}
                byDay[k][#byDay[k] + 1] = e
            end
        end

        local dim = daysInMonth(f.viewYear, f.viewMonth)
        local lead = firstWeekday(f.viewYear, f.viewMonth) - 1     -- blank cells before day 1
        local todayKey = keyOfTs(GetServerTime())

        for idx = 1, COLS * ROWS do
            local cell = f.cells[idx]
            local dayNum = idx - lead
            if dayNum < 1 or dayNum > dim then
                cell.dayFS:SetText(""); cell.evtFS:SetText(""); cell.dkey = nil
                cell:SetBackdropColor(0.04, 0.04, 0.05, 0.6)
                cell:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.15)
            else
                local k = dayKey(f.viewYear, f.viewMonth, dayNum)
                cell.dkey = k
                cell.dayFS:SetText(dayNum)
                cell.dayFS:SetTextColor(1, 1, 1)
                local evs = byDay[k]
                if evs then
                    table.sort(evs, function(a, b) return a.when < b.when end)
                    local line = date("%H:%M ", evs[1].when) .. (evs[1].title or "")
                    if #evs > 1 then line = "+" .. #evs .. " " .. line end
                    cell.evtFS:SetText(line)
                    cell.evtFS:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
                else
                    cell.evtFS:SetText("")
                end
                -- Cell background: selected > today > has-events > plain
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
        f.createRow:SetShown(isOfficer and sel ~= nil)

        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(536)

        local evs = (sel and byDay and byDay[sel]) or {}
        local yy = 0
        for _, e in ipairs(evs) do
            local comp = CAL():GetComposition(e)
            local mine = CAL():MyRsvp(e)

            local head = UI:CreateText(child, date("%H:%M ", e.when) .. "|cffFFFFFF" .. (e.title or "") .. "|r  |cff888888(" .. (e.size or 25) .. ")|r",
                12, C.gold.r, C.gold.g, C.gold.b)
            head:SetPoint("TOPLEFT", 4, -yy)
            if isOfficer then
                local cancelBtn = UI:CreateButton(child, L["Cancel"], 60, 18)
                cancelBtn:SetPoint("TOPRIGHT", -2, -yy)
                local id = e.id
                cancelBtn:SetScript("OnClick", function() CAL():Cancel(id) end)
            end
            yy = yy + 20

            local compFS = UI:CreateText(child, string.format(L["Tanks %d, Heals %d, DPS %d  (%d going, %d tentative)"],
                comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS, comp.yes, comp.tentative),
                10, C.silver.r, C.silver.g, C.silver.b)
            compFS:SetPoint("TOPLEFT", 6, -yy)
            yy = yy + 18

            -- RSVP row: role cycle + Yes / Tentative / No
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
            rsvpBtn(L["Going"],     "yes",       8,  C.online)
            rsvpBtn(L["Tentative"], "tentative", 76, C.gold)
            rsvpBtn(L["Absent"],    "no",        144, C.red)
            yy = yy + 24

            -- Who's going
            local going = {}
            for _, r in pairs(e.rsvps or {}) do
                if r.status == "yes" then
                    local cr, cg, cb = BRutus:GetClassColor(r.class)
                    going[#going + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, r.name or "?")
                end
            end
            if #going > 0 then
                local goFS = UI:CreateText(child, L["Going: "] .. table.concat(going, ", "), 9, C.textDim.r, C.textDim.g, C.textDim.b)
                goFS:SetPoint("TOPLEFT", 6, -yy); goFS:SetWidth(520); goFS:SetJustifyH("LEFT")
                yy = yy + math.max(14, (goFS:GetStringHeight() or 12) + 4)
            end
            yy = yy + 10
        end

        if sel and #evs == 0 then
            local none = UI:CreateText(child, isOfficer and L["No events. Set a time above to create one."] or L["No events this day."],
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

    return f
end

----------------------------------------------------------------------
-- Public entry
----------------------------------------------------------------------
function BRutus:ShowCalendar()
    local f = self.calendarFrame or BuildCalendar()
    self.calendarFrame = f
    if not f.viewYear then
        local t = date("*t", GetServerTime())
        f.viewYear, f.viewMonth, f.selectedKey = t.year, t.month, dayKey(t.year, t.month, t.day)
    end
    if self.Calendar then
        self.Calendar.uiRefresh = function() if f:IsShown() then f.Render() end end
    end
    f:Show(); f:Raise()
    f.Render()
end
