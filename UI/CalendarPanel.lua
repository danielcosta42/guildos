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
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local function CAL() return GuildOS.Calendar end

local WEEKDAYS = { L["Sun"], L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"] }
local ROLES    = { "TANK", "HEALER", "DPS" }
local SIZES    = GuildOS.Client.raidSizes   -- the game's: 10/25/40 on TBC, 10/20/40 on Forever (#92)
local DEFAULT_SIZE = GuildOS.Client.defaultRaidSize

local COLS, ROWS = 7, 6
local CELL_H  = 44
-- The Guild tab's grid (#371): flush with the sub-tab bar's left edge, the first line GAP under the
-- sub-panel's top, the grid ending GAP short of its right edge.
local GAP     = UI.GAP
local NAV_Y   = -GAP
local WD_Y    = NAV_Y - 22 - GAP   -- under the 22px month buttons
local GRID_Y  = WD_Y - 16
local GRID_X  = 0

-- Secondary bits of a line drawn in one string (a size, "(repeats)", a guild): the token's colour,
-- so a palette the style re-points carries them too (#371).
local function tint(text, c) return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text) end

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
    -- Not kinds of event: the calendar's drawn dates (#428).
    BIRTHDAY = { r = 0.93, g = 0.80, b = 0.48 },
    JOINDAY  = { r = 0.56, g = 0.80, b = 0.86 },
}
local function kindColor(k) return KIND_COLOR[k] or KIND_COLOR.RAID end
local VIRTUAL_LABEL = { BIRTHDAY = L["Birthday"], JOINDAY = L["Anniversary"] }
local function kindLabel(k) return VIRTUAL_LABEL[k] or (CAL() and CAL().KindLabel and CAL():KindLabel(k)) or k end

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
    f:SetSize(360, 392)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
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

    -- A labelled field (single- or multi-line): the shared field under a form label (#371).
    local function fieldBox(x, y, w, labelText, multiline, maxLetters)
        local lbl = UI:CreateText(f, labelText, 11)
        lbl:SetPoint("TOPLEFT", x, y)
        local box = UI:CreateInput(f, w, multiline and 84 or 22, { multiline = multiline, max = maxLetters })
        box:SetPoint("TOPLEFT", x, y - 14)
        return box
    end

    local dateBox  = fieldBox(14,  -42, 118, L["Date (YYYY-MM-DD)"], false, 10)
    local timeBox  = fieldBox(140, -42, 66,  L["Time (HH:MM)"],      false, 5)
    local sizeLbl  = UI:CreateText(f, L["Size"], 11)
    sizeLbl:SetPoint("TOPLEFT", 216, -42)
    local sizeBtn  = UI:CreateButton(f, tostring(DEFAULT_SIZE), 44, 22)
    sizeBtn:SetPoint("TOPLEFT", 216, -56)
    sizeBtn.sizeVal = DEFAULT_SIZE
    sizeBtn:SetScript("OnClick", function()
        local idx = 1
        local sizes = CAL().SizesFor(f.kind, SIZES)   -- a dungeon is five (issue #283)
        for i, v in ipairs(sizes) do if v == sizeBtn.sizeVal then idx = i break end end
        sizeBtn.sizeVal = sizes[(idx % #sizes) + 1]
        sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
    end)

    -- Category picker: one button per kind, the chosen one marked as every selection is (#371).
    -- f.kind holds the current selection.
    local kindLbl = UI:CreateText(f, L["Type"], 11)
    kindLbl:SetPoint("TOPLEFT", 14, -84)
    local kindPills = {}
    local refreshDungeon   -- the dungeon picker beside the title (#308), built with the title below
    local function refreshKinds()
        for _, p in ipairs(kindPills) do
            -- A kind this rank may not create (#308) stays in its place, dimmed and not clickable.
            if CAL():MayCreateKind(p.kind) then p:Enable() else p:Disable() end
            UI:SetSelected(p, p.kind == f.kind)
        end
        if refreshDungeon then refreshDungeon() end
    end
    do
        local kinds = (CAL() and CAL().KINDS) or { "RAID", "DUNGEON", "PVP", "FARM", "SOCIAL", "OTHER" }
        for i, k in ipairs(kinds) do
            -- Six fixed 52px places in the 360px editor, as before: a long translation ("Schlachtzug",
            -- "Подземелье") is shortened to fit rather than pushing the row past the popup's edge.
            local p = UI:CreateButton(f, "", 52, 20)
            GuildOS:ApplyFont(p.label, 11, "button")
            p:SetPoint("TOPLEFT", 14 + (i - 1) * 55, -98)
            -- Shortened by hand: UI:SetChipText would add a removable chip's "x" to a kind.
            local text = kindLabel(k)
            local chars = select(2, text:gsub("[^\128-\191]", ""))   -- UTF-8 characters, not bytes
            p.label:SetText(text)
            while p.label:GetStringWidth() > 44 and chars > 2 do
                chars = chars - 1
                p.label:SetText(GuildOS:Utf8Head(text, chars) .. "..")
            end
            p:SetWidth(52)   -- back from the growth the label asked for
            p.fs = p.label   -- the pill's label, under the name it always had
            p.kind = k
            p:SetScript("OnClick", function()
                f.kind = k; refreshKinds()
                -- A size the new kind does not offer moves to one it does: a dungeon's five, or back to the raid default.
                local sizes = CAL().SizesFor(k, SIZES)
                local fits = false
                for _, v in ipairs(sizes) do if v == sizeBtn.sizeVal then fits = true end end
                if not fits then
                    sizeBtn.sizeVal = (k == "DUNGEON") and sizes[1] or DEFAULT_SIZE
                    sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
                end
            end)
            kindPills[#kindPills + 1] = p
        end
    end
    refreshKinds()

    local titleBox = fieldBox(14, -128, 332, L["Title"], false, 60)

    -- A Dungeon event picks its dungeon from the game's list (#308), the one guildos.me offers, or
    -- "Other" and types it: the pick is the title. The list opens beside the editor.
    local dungeonBtn = UI:CreateButton(f, L["Pick a dungeon"], 104, 22)
    dungeonBtn:SetPoint("TOPLEFT", 242, -142)
    local dungeonList
    local function hideDungeonList() if dungeonList then dungeonList:Hide() end end
    local function pickDungeon(name)
        if name then
            titleBox:SetText(name)
        else
            -- Other: a name the list put there gives way to the one typed.
            for _, n in ipairs(CAL():DungeonChoices()) do
                if strtrim(titleBox:GetText() or "") == n then titleBox:SetText("") end
            end
            titleBox:SetFocus()
        end
        hideDungeonList()
    end
    local function buildDungeonList()
        local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
        list:SetFrameStrata("DIALOG")
        list:SetFrameLevel(f:GetFrameLevel() + 10)
        list:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
        list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(list) })
        list:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        list:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        local choices = CAL():DungeonChoices()
        for i, name in ipairs(choices) do
            local b = UI:CreateButton(list, name, 196, 20)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
            b:SetScript("OnClick", function() pickDungeon(name) end)
        end
        local other = UI:CreateButton(list, L["Other (type a name)"], 196, 20)
        other:SetPoint("TOPLEFT", 6, -6 - #choices * 22)
        other:SetScript("OnClick", function() pickDungeon(nil) end)
        list:SetSize(208, 12 + (#choices + 1) * 22)
        list:Hide()
        return list
    end
    dungeonBtn:SetScript("OnClick", function()
        dungeonList = dungeonList or buildDungeonList()
        dungeonList:SetShown(not dungeonList:IsShown())
    end)
    -- Only for a dungeon, and only where the game has a list (WoW: Forever); the title makes room.
    refreshDungeon = function()
        local show = f.kind == "DUNGEON" and #CAL():DungeonChoices() > 0
        dungeonBtn:SetShown(show)
        titleBox:SetWidth(show and 222 or 332)
        if not show then hideDungeonList() end
    end
    local descBox  = fieldBox(14, -178, 332, L["Description (optional)"], true, 500)

    -- Repeating (#267). A new event cycles through the repeats its date allows; an event of a series
    -- offers to change every later date instead.
    local repLbl = UI:CreateText(f, L["Repeat"], 11)
    repLbl:SetPoint("TOPLEFT", 14, -284)
    local repBtn = UI:CreateButton(f, "", 260, 22)
    repBtn:SetPoint("TOPLEFT", 70, -280)
    local laterCb = UI:CreateCheckbox(f, L["Change every later date in this series"], 18)
    laterCb:SetPoint("TOPLEFT", 14, -282)
    local REPEATS = (CAL() and CAL().REPEATS) or { "none" }
    f.rep = "none"
    local function repDate()
        local y, m, d = parseDate(dateBox:GetText())
        return y and noon(y, m, d) or nil
    end
    local function repLabel(rep)
        local ts = repDate()
        local r = (ts and CAL() and CAL().RepeatOf) and CAL().RepeatOf(rep, ts) or { wday = 1, nth = 1, day = 1 }
        if rep == "weekly" then return string.format(L["Every week on %s"], WEEKDAYS[r.wday]) end
        if rep == "biweekly" then return string.format(L["Every 2 weeks on %s"], WEEKDAYS[r.wday]) end
        if rep == "daily" then return L["Every day"] end
        if rep == "everyother" then return L["Every other day"] end
        if rep == "monthnth" then return string.format(L["Every month, %s"], WEEKDAYS[r.wday] .. " #" .. r.nth) end
        if rep == "monthday" then return string.format(L["Every month on day %d"], r.day) end
        if rep == "yearly" then return string.format(L["Every year on %s"], ts and (GuildOS:LocalDate("%d %b", ts):gsub("^0", "")) or "") end
        return L["Does not repeat"]
    end
    local function refreshRep() repBtn.label:SetText(repLabel(f.rep)) end
    repBtn:SetScript("OnClick", function()
        local idx = 1
        for i, v in ipairs(REPEATS) do if v == f.rep then idx = i break end end
        f.rep = REPEATS[(idx % #REPEATS) + 1]
        refreshRep()
    end)
    dateBox:HookScript("OnTextChanged", refreshRep)
    local REP_ROW = 32   -- the room the repeat row takes

    -- Alliance sharing. The whole block only exists while this guild is in a
    -- pact: with no alliance there is nothing to share with, and an unexplained
    -- checkbox is worse than no checkbox.
    local shareCb = UI:CreateCheckbox(f, L["Share with the alliance"], 18)
    shareCb:SetPoint("TOPLEFT", 14, -276 - REP_ROW)
    local shareHint = UI:CreateText(f,
        L["Allied guilds see this event and can request a slot. Unchecked, it stays in the guild."],
        9, C.textDim.r, C.textDim.g, C.textDim.b)
    shareHint:SetPoint("TOPLEFT", 34, -296 - REP_ROW)
    shareHint:SetWidth(310)
    shareHint:SetJustifyH("LEFT")
    shareHint:SetWordWrap(true)

    local saveBtn = UI:CreateButton(f, L["Create"], 110, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 14, 14)
    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 24)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

    -- An event made here never becomes a raid on the site or a Discord post (spec 075 in guildos-web):
    -- said where it is made, since "the bot didn't post my dungeon" is the question it answers.
    local HINT_ROW = 28
    local gameOnly = UI:CreateText(f, L["Events made here stay in the game. For signups on Discord, create the raid on guildos.me or with /raid create."], 9, C.textDim.r, C.textDim.g, C.textDim.b)
    gameOnly:SetPoint("BOTTOMLEFT", saveBtn, "TOPLEFT", 0, 6)
    gameOnly:SetWidth(332)
    gameOnly:SetJustifyH("LEFT")
    gameOnly:SetWordWrap(true)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    local function commit()
        local y, m, d = parseDate(dateBox:GetText())
        if not y then GuildOS:Print(L["Enter a date as YYYY-MM-DD."]); return end
        local hh, mm = parseTime(timeBox:GetText())
        if not hh then GuildOS:Print(L["Enter a time as HH:MM."]); return end
        local title = strtrim(titleBox:GetText() or "")
        if title == "" then GuildOS:Print(L["An event needs a title and a date/time."]); return end
        local when = time({ year = y, month = m, day = d, hour = hh, min = mm })
        local inAlliance = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        local share = inAlliance and shareCb.checkbox:GetChecked() or nil
        if f.editId and f.inSeries and laterCb.checkbox:GetChecked() then
            CAL():UpdateSeries(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, share)
        elseif f.editId then
            CAL():Update(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "",
                f.kind, share)
        elseif f.rep ~= "none" then
            CAL():CreateSeries(title, when, sizeBtn.sizeVal, descBox:GetText() or "",
                f.kind, share and true or false, f.rep)
        else
            CAL():Create(title, when, sizeBtn.sizeVal, descBox:GetText() or "",
                f.kind, share and true or false)
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
        -- A new event starts on a kind this rank creates (#308): a raid, else the first one open.
        local first = CAL():MayCreateKind("RAID") and "RAID" or CAL():CreatableKinds()[1] or "RAID"
        f.kind = (event and event.kind and KIND_COLOR[event.kind]) and event.kind or first
        hideDungeonList()
        refreshKinds()
        local y, m, d, hh, mm, size, title, note
        if event then
            local t = date("*t", event.when)
            y, m, d, hh, mm = t.year, t.month, t.day, t.hour, t.min
            size, title, note = event.size or DEFAULT_SIZE, event.title or "", event.note or ""
        else
            y = math.floor(dk / 10000); m = math.floor((dk % 10000) / 100); d = dk % 100
            hh, mm, size, title, note = 20, 0, CAL().SizesFor(f.kind, { DEFAULT_SIZE })[1], "", ""
        end
        local inAlliance = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        shareCb:SetShown(inAlliance)
        shareHint:SetShown(inAlliance)
        f:SetHeight((inAlliance and 392 or 336) + REP_ROW + HINT_ROW)
        -- New: pick a repeat. An event of a series: change only it, or every later date too.
        f.inSeries = event and type(event.series) == "table" or false
        f.rep = "none"
        repLbl:SetShown(not event)
        repBtn:SetShown(not event)
        laterCb:SetShown(f.inSeries)
        laterCb.checkbox:SetChecked(false)
        shareCb.checkbox:SetChecked((event and event.shareAlliance) and true or false)

        dateBox:SetText(string.format("%04d-%02d-%02d", y, m, d))
        refreshRep()
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
GuildOS.Dialogs["GUILDOS_CALENDAR_DELETE"] = {
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
    local dlg = GuildOS:ShowDialog("GUILDOS_CALENDAR_DELETE", e.title or "?", nil, e.id)
    if dlg then dlg.data = e.id end   -- some clients pass data via dialog.data
end

-- Ending a series from one date on (#267): the earlier dates stay.
GuildOS.Dialogs["GUILDOS_CALENDAR_END_SERIES"] = {
    text = L["End \"%s\" from this date on? Earlier dates stay."],
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        local id = data
        if id == nil and self then id = self.data end
        if id then CAL():EndSeries(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
}
local function confirmEndSeries(e)
    local dlg = GuildOS:ShowDialog("GUILDOS_CALENDAR_END_SERIES", e.title or "?", nil, e.id)
    if dlg then dlg.data = e.id end
end

----------------------------------------------------------------------
-- Build the calendar into a Guild-hub sub-panel; return its refresh fn.
----------------------------------------------------------------------
function GuildOS:CreateCalendarSub(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- Month navigation. The month is the screen's first section title; it is as wide as its name, so
    -- the ">" sits right after it rather than a fixed 170px away (#371).
    local prevBtn = UI:CreateButton(f, "<", 26, 22)
    prevBtn:SetPoint("TOPLEFT", GRID_X, NAV_Y)
    local monthLabel = UI:CreateSectionTitle(f, "", true)
    monthLabel:SetPoint("LEFT", prevBtn, "RIGHT", GAP, 0)
    local nextBtn = UI:CreateButton(f, ">", 26, 22)
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", GAP, 0)
    local todayBtn = UI:CreateButton(f, L["Today"], 60, 22)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)

    -- Birthdays and join anniversaries (#428): dates drawn from the members, never events; each kind
    -- has its filter. On WoW: Forever an officer puts this month's birthdays in the game's calendar.
    local BD = GuildOS.Birthdays
    local barEnd = todayBtn
    if BD then
        for _, kind in ipairs({ "birthday", "join" }) do
            local cb = UI:CreateCheckbox(f, kind == "birthday" and L["Birthdays"] or L["Join anniversaries"], 18)
            cb:SetWidth(kind == "birthday" and 100 or 140)
            cb:SetPoint("LEFT", barEnd, "RIGHT", 16, 0)
            cb.checkbox:SetChecked(BD:Shows(kind))
            cb.checkbox.onChanged = function(_, checked) BD:SetShows(kind, checked) end
            barEnd = cb
        end
    end
    local gameBdayBtn = UI:CreateButton(f, L["Birthdays to the game's calendar"], 200, 22)
    gameBdayBtn:SetPoint("LEFT", barEnd, "RIGHT", 12, 0)
    gameBdayBtn:SetScript("OnClick", function() GuildOS.GameCalendar:PutNextBirthday() end)

    -- Weekday headers: the grid's column labels (repositioned in Render to match the grid width)
    f.wdFS = {}
    for i = 1, COLS do
        f.wdFS[i] = UI:CreateHeaderText(f, WEEKDAYS[i])
    end

    -- Day cells
    f.cells = {}
    for idx = 1, COLS * ROWS do
        local cell = CreateFrame("Button", nil, f, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(cell) })
        cell.dayFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.dayFS, 11)
        cell.dayFS:SetPoint("TOPLEFT", 4, -3)
        cell.evtFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.evtFS, 9)
        cell.evtFS:SetPoint("BOTTOMLEFT", 3, 3)
        cell.evtFS:SetPoint("BOTTOMRIGHT", -3, 3)
        cell.evtFS:SetJustifyH("LEFT"); cell.evtFS:SetWordWrap(false)
        cell:SetScript("OnClick", function(self2)
            if self2.dkey then f.selectedKey = self2.dkey; f.Render() end
        end)
        f.cells[idx] = cell
    end

    -- Detail area (below the grid): the selected day is a section of its own, its rule 12px over it,
    -- with room for that rule under the grid (#371).
    local DET_Y = GRID_Y - ROWS * CELL_H - 20
    local detailLabel = UI:CreateSectionTitle(f, "")
    detailLabel:SetPoint("TOPLEFT", GRID_X, DET_Y)

    -- Officer "New Event" button, beside the day it adds to: opens the editor popup for the selected day.
    local newBtn = UI:CreateButton(f, L["New Event"], 100, 20)
    newBtn:SetPoint("LEFT", detailLabel, "RIGHT", 12, 0)
    newBtn:SetScript("OnClick", function()
        if f.selectedKey then openEditor(f.selectedKey, nil) end
    end)
    f.newBtn = newBtn

    -- Event list holder (scrollable), fills the rest of the panel
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", detailLabel, "BOTTOMLEFT", 0, -12)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    f.holder = holder
    local scrollFrame, scrollChild = UI:CreateScrollFrame(holder, "GuildOSCalendarScroll")
    scrollFrame:SetAllPoints()   -- fill the holder; without this the scroll viewport is 0x0 and clips all content
    -- The child keeps the list's width, less the bar's gutter; the rows hang from both its top corners.
    UI:BindScrollChildWidth(scrollFrame, scrollChild)
    f.child = scrollChild

    ------------------------------------------------------------------
    -- Render (grid sizes to the current panel width)
    ------------------------------------------------------------------
    function f.Render()
        local W = f:GetWidth()
        if not W or W < 120 then W = 1000 end
        local cellW = math.floor((W - GRID_X - GAP) / COLS)

        monthLabel:SetText(GuildOS:LocalDate(L["%b %Y"], noon(f.viewYear, f.viewMonth, 1)))

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
        -- The month's birthdays and join anniversaries, worked out now (#428).
        if BD then
            for _, e in ipairs(BD:VirtualEvents(noon(f.viewYear, f.viewMonth, 1) - 43200, noon(f.viewYear, f.viewMonth, dim) + 43199)) do
                local k = keyOfTs(e.when)
                byDay[k] = byDay[k] or {}
                byDay[k][#byDay[k] + 1] = e
            end
        end
        gameBdayBtn:SetShown(GuildOS.GameCalendar ~= nil and BD ~= nil and GuildOS.GameCalendar:CanAct())
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
            -- Flat cells with a 1px line; the selected day and today take a 1px gold border and no
            -- gold fill, the selected one on the selected-row surface (#371).
            if dayNum < 1 or dayNum > dim then
                cell.dayFS:SetText(""); cell.evtFS:SetText(""); cell.dkey = nil
                cell:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0)
                cell:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 0.4)
            else
                local k = dayKey(f.viewYear, f.viewMonth, dayNum)
                cell.dkey = k
                cell.dayFS:SetText(dayNum); cell.dayFS:SetTextColor(C.text.r, C.text.g, C.text.b)
                local evs = byDay[k]
                if evs then
                    table.sort(evs, function(a, b) return a.when < b.when end)
                    local line = (evs[1].virtual and "" or date("%H:%M ", evs[1].when)) .. (evs[1].title or "")
                    if #evs > 1 then line = "+" .. #evs .. " " .. line end
                    cell.evtFS:SetText(line)
                    local kc = kindColor(evs[1].kind)
                    cell.evtFS:SetTextColor(kc.r, kc.g, kc.b)
                else
                    cell.evtFS:SetText("")
                end
                local fill = (k == f.selectedKey) and C.popup or C.well
                local edge = (k == f.selectedKey or k == todayKey) and C.gold or C.line
                cell:SetBackdropColor(fill.r, fill.g, fill.b, 1)
                cell:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
            end
        end

        f.RenderDetail(byDay)
    end

    ------------------------------------------------------------------
    -- Detail for the selected day
    ------------------------------------------------------------------
    function f.RenderDetail(byDay)
        local isOfficer = GuildOS:IsOfficer()
        -- The guild's ranks (issue #283), and a kind left open to this one (#308).
        local canCreate = GuildOS:MayCreateEvents() and #CAL():CreatableKinds() > 0
        local sel = f.selectedKey
        if sel then
            local y = math.floor(sel / 10000); local m = math.floor((sel % 10000) / 100); local d = sel % 100
            detailLabel:SetText(GuildOS:LocalDate(L["%A, %d %b %Y"], noon(y, m, d)))
        else
            detailLabel:SetText(L["Select a day"])
        end
        f.newBtn:SetShown(canCreate and sel ~= nil)

        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end

        -- A line that wraps hangs from both of the list's top corners, never from a width read while
        -- the tab may be hidden (#371).
        local function across(fs, y)
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetPoint("TOPRIGHT", 0, -y)
            fs:SetJustifyH("LEFT")
        end
        local soft = C.textSoft

        local evs, virtual = {}, {}
        for _, e in ipairs((sel and byDay and byDay[sel]) or {}) do
            if e.virtual then virtual[#virtual + 1] = e else evs[#evs + 1] = e end
        end
        local yy = 0
        -- Birthdays and join anniversaries first, a line each: nothing to sign up to (#428).
        for _, e in ipairs(virtual) do
            local fs = UI:CreateText(child, tint("[" .. kindLabel(e.kind) .. "]", kindColor(e.kind)) .. " " .. (e.title or ""),
                12, C.text.r, C.text.g, C.text.b)
            across(fs, yy)
            yy = yy + 20
        end
        if #virtual > 0 then yy = yy + 8 end
        -- The game's own calendar (guildos-web specs/075, #263), read once for the day's raids from the
        -- site: its guild events over the inbox's window, and the inbox. WoW: Forever only.
        local GC = GuildOS.GameCalendar
        local gameOn = GC ~= nil and GuildOS.Compat.CalendarAvailable()
        local gameEvents, inbox   -- gameEvents stays nil until the game has read its calendar
        if gameOn then
            GuildOS.Compat.CalendarRequest()
            local now = GetServerTime()
            gameEvents = GuildOS.Compat.CalendarGuildEvents(now - GC.GRACE - 86400, now + (GC.WINDOW_DAYS + 1) * 86400)
            inbox = GuildOS.CompanionImport and GuildOS.CompanionImport:InboxInfo()
        end
        -- Per-day render is wrapped so a single malformed event can't blank the
        -- whole list; any failure is surfaced inline instead.
        local okAll, errAll = pcall(function()
        for _, e in ipairs(evs) do
            local comp = CAL():GetComposition(e)
            local mine = CAL():MyRsvp(e)

            -- The kind keeps its colour: it is the same one the grid marks the day with.
            local tag = tint("[" .. kindLabel(e.kind) .. "]", kindColor(e.kind)) .. " "
            -- Shared events carry a mark so an officer can see what is exposed
            -- without opening each one. Marking the SHARED ones (not the
            -- private ones) because exposure is the state that wants attention.
            -- An [A] rather than a globe glyph: the skin fonts have no symbol
            -- coverage and unicode marks render as a box in these fonts. In the
            -- text colour, not gold: gold is the selection's (#371).
            local shareMark = e.shareAlliance and "  [A]" or ""
            local inSeries = type(e.series) == "table"
            local repMark = inSeries and ("  " .. tint(L["(repeats)"], soft)) or ""
            local head = UI:CreateText(child, date("%H:%M ", e.when) .. tag .. (e.title or "") .. "  "
                .. tint("(" .. (e.size or DEFAULT_SIZE) .. ")", soft) .. shareMark .. repMark,
                12, C.text.r, C.text.g, C.text.b)
            head:SetPoint("TOPLEFT", 0, -yy)
            if CAL():MayManage(e) then
                local ev = e
                local delBtn = UI:CreateButton(child, L["Delete"], 58, 18)
                delBtn:SetPoint("TOPRIGHT", 0, -yy)
                delBtn:SetScript("OnClick", function() confirmDelete(ev) end)
                local editBtn = UI:CreateButton(child, L["Edit"], 48, 18)
                editBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                editBtn:SetScript("OnClick", function() openEditor(nil, ev) end)
                if inSeries then
                    -- This date and every later one of the series go (#267).
                    local endBtn = UI:CreateButton(child, L["End series"], 80, 18)
                    endBtn:SetPoint("RIGHT", editBtn, "LEFT", -6, 0)
                    endBtn:SetScript("OnClick", function() confirmEndSeries(ev) end)
                end
            end
            yy = yy + 20

            local compFS = UI:CreateText(child, string.format(L["Tanks %d, Heals %d, DPS %d  (%d going, %d tentative)"],
                comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS, comp.yes, comp.tentative),
                11, soft.r, soft.g, soft.b)
            compFS:SetPoint("TOPLEFT", 0, -yy)
            yy = yy + 18

            if e.note and e.note ~= "" then
                local noteFS = UI:CreateText(child, e.note, 11, soft.r, soft.g, soft.b)
                across(noteFS, yy)
                yy = yy + math.max(14, (noteFS:GetStringHeight() or 12) + 6)
            end

            if CAL():IsWebEvent(e) then
                -- Planned on the site, so signing up happens there: the game shows the site's
                -- answers and no buttons of its own. A second list here was a second answer to
                -- the same question, empty, and it never reached the site (#146).
                -- With when the list is from: a member who was offline when it was sent keeps the
                -- last one they got.
                local where = L["Sign up in Discord or on the website."]
                if (tonumber(e.signupsAt) or 0) > 0 then
                    where = where .. " " .. string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", e.signupsAt))
                end
                local whereFS = UI:CreateText(child, where, 11, soft.r, soft.g, soft.b)
                whereFS:SetPoint("TOPLEFT", 0, -yy)
                yy = yy + 16
                -- Whether it is in the game's own calendar, and for an officer the click that changes it.
                if gameOn then
                    local view = GC:ViewFor(e, gameEvents, inbox)
                    if view.text then
                        local stateFS = UI:CreateText(child, view.text, 11, soft.r, soft.g, soft.b)
                        stateFS:SetPoint("TOPLEFT", 0, -yy)
                        if view.action then
                            local evId, action = e.id, view.action
                            local gameBtn = UI:CreateButton(child, view.label, 200, 18)
                            gameBtn:SetPoint("TOPRIGHT", 0, -yy)
                            gameBtn:SetScript("OnClick", function() GC:Act(evId, action) end)
                        end
                        yy = yy + 20
                    end
                end
                -- An allied seat is approved in the game, and goes with the ones coming.
                local answers = CAL():WebSignups(e)
                for _, r in pairs(e.rsvps or {}) do
                    if r.ally and r.status == "yes" then
                        answers[#answers + 1] = { name = GuildOS:SanitizeUserText(r.name or "?", 48), class = r.class, status = "yes" }
                    end
                end
                for _, line in ipairs({
                    { "yes", L["Going: "] }, { "pending", L["Awaiting approval: "] },
                    { "tentative", L["Tentative: "] }, { "wait", L["Standby: "] }, { "no", L["Absent: "] },
                }) do
                    local names = {}
                    for _, s in ipairs(answers) do
                        if s.status == line[1] then
                            local cr, cg, cb = GuildOS:GetClassColor(s.class)
                            names[#names + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, s.name)
                        end
                    end
                    if #names > 0 then
                        local fs = UI:CreateText(child, line[2] .. table.concat(names, ", "), 11, soft.r, soft.g, soft.b)
                        across(fs, yy)
                        yy = yy + math.max(14, (fs:GetStringHeight() or 12) + 4)
                    end
                end
            else
                local id = e.id
                local roleBtn = UI:CreateButton(child, roleLabel((mine and mine.role) or "DPS"), 66, 18)
                roleBtn:SetPoint("TOPLEFT", 0, -yy)
                roleBtn.role = (mine and mine.role) or "DPS"
                roleBtn:SetScript("OnClick", function()
                    local i = 1
                    for j, v in ipairs(ROLES) do if v == roleBtn.role then i = j break end end
                    roleBtn.role = ROLES[(i % #ROLES) + 1]
                    roleBtn.label:SetText(roleLabel(roleBtn.role))
                end)
                -- Chained, so a label that grew its button pushes the next one (issue #28). My answer
                -- is the selected one of the three, marked as every selection is (#371).
                local function rsvpBtn(text, status, anchor, xoff)
                    local b = UI:CreateButton(child, text, 64, 18)
                    b:SetPoint("LEFT", anchor, "RIGHT", xoff, 0)
                    UI:SetSelected(b, mine and mine.status == status)
                    b:SetScript("OnClick", function() CAL():Rsvp(id, status, roleBtn.role) end)
                    return b
                end
                local goingBtn = rsvpBtn(L["Going"],     "yes",       roleBtn,  8)
                local tentBtn  = rsvpBtn(L["Tentative"], "tentative", goingBtn, 4)
                rsvpBtn(L["Absent"],    "no",        tentBtn,  4)
                yy = yy + 24

                local going = {}
                for _, r in pairs(e.rsvps or {}) do
                    if r.status == "yes" then
                        local cr, cg, cb = GuildOS:GetClassColor(r.class)
                        going[#going + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, r.name or "?")
                    end
                end
                if #going > 0 then
                    local goFS = UI:CreateText(child, L["Going: "] .. table.concat(going, ", "), 11, soft.r, soft.g, soft.b)
                    across(goFS, yy)
                    yy = yy + math.max(14, (goFS:GetStringHeight() or 12) + 4)
                end
            end

            -- Cross-guild signup queue. Officers only: the request already
            -- reached only ambassadors, and seating is an officer action.
            local pending = isOfficer and CAL().AlliancePending and CAL():AlliancePending(e) or {}
            if #pending > 0 then
                -- The queue's own column label, not gold (#371).
                local hdr = UI:CreateHeaderText(child, string.format(L["ALLIANCE PENDING (%d)"], #pending))
                hdr:SetPoint("TOPLEFT", 0, -yy)
                yy = yy + 16
                for _, p in ipairs(pending) do
                    local cr, cg, cb = GuildOS:GetClassColor(p.class)
                    local line = string.format("|cff%02x%02x%02x%s|r  %s  %s  %s",
                        cr * 255, cg * 255, cb * 255, p.name or "?",
                        p.level and tostring(p.level) or "", roleLabel(p.role), tint(p.guild or "?", soft))
                    if p.note and p.note ~= "" then
                        line = line .. "  " .. tint("\"" .. p.note .. "\"", C.label)
                    end
                    local evId, pKey = e.id, p.key
                    local noBtn = UI:CreateButton(child, L["Decline"], 62, 18)
                    noBtn:SetPoint("TOPRIGHT", 0, -yy + 2)
                    noBtn:SetScript("OnClick", function() CAL():DeclineAlliance(evId, pKey) end)
                    local yesBtn = UI:CreateButton(child, L["Approve"], 62, 18)
                    yesBtn:SetPoint("RIGHT", noBtn, "LEFT", -6, 0)
                    yesBtn:SetScript("OnClick", function() CAL():ApproveAlliance(evId, pKey) end)

                    -- One line, stopping short of its two buttons.
                    local fs = UI:CreateText(child, line, 11, C.text.r, C.text.g, C.text.b)
                    fs:SetPoint("TOPLEFT", 0, -yy)
                    fs:SetPoint("TOPRIGHT", yesBtn, "TOPLEFT", -GAP, -2)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)

                    yy = yy + 20
                end
            end

            yy = yy + 12
        end
        end)
        if not okAll then
            local errFS = UI:CreateText(child, tostring(errAll), 11, C.danger.r, C.danger.g, C.danger.b)
            across(errFS, yy)
            yy = yy + math.max(40, (errFS:GetStringHeight() or 20) + 10)
        end

        if sel and #evs == 0 and #virtual == 0 then
            local none = UI:CreateText(child, canCreate and L["No events. Use New Event to add one."] or L["No events this day."],
                12, soft.r, soft.g, soft.b)
            none:SetPoint("TOPLEFT", 0, 0)
            yy = 20
        end

        -- A raid the site has but the game was not sent yet (#416): the inbox carries ten raids, four weeks
        -- ahead, so a night planned two months out is on Discord and not here. Said only where the guild
        -- uses the site (the companion is on here, or a raid from it is on the calendar).
        if sel then
            local Imp = GuildOS.CompanionImport
            local usesSite = GuildOS.Companion ~= nil and GuildOS.Companion:IsEnabled()
            if not usesSite then
                for _, e in pairs(CAL():GetEvents()) do
                    if CAL():IsWebEvent(e) and not e.canceled then usesSite = true break end
                end
            end
            local why = usesSite and GuildOS.GameCalendar and GuildOS.GameCalendar.NotSentYet(
                noon(math.floor(sel / 10000), math.floor((sel % 10000) / 100), sel % 100) + 12 * 3600,
                GetServerTime(), inbox or (Imp and Imp:InboxInfo()))
            if why then
                local text = why == "window"
                    and string.format(L["Raids planned on the website more than %d days ahead have not reached the game yet; they arrive as the date gets closer."], GuildOS.GameCalendar.WINDOW_DAYS)
                    or string.format(L["The website sends the game its next %d raids; later ones arrive as those pass."], GuildOS.GameCalendar.INBOX_CAP)
                local fs = UI:CreateText(child, text, 11, soft.r, soft.g, soft.b)
                across(fs, yy)
                yy = yy + math.max(14, (fs:GetStringHeight() or 12) + 6)
            end
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

    -- A deep link (the Now tab's raid) opens on that day, its events listed.
    panel.ApplyFilter = function(when)
        local d = date("*t", when)
        f.viewYear, f.viewMonth, f.selectedKey = d.year, d.month, dayKey(d.year, d.month, d.day)
        f.Render()
    end

    -- Live-refresh while visible as synced events/RSVPs arrive.
    if GuildOS.Calendar then
        GuildOS.Calendar.uiRefresh = function() if panel:IsShown() then f.Render() end end
    end

    return f.Render
end

----------------------------------------------------------------------
-- Entry point (command): open the roster on the Guild hub's Calendar sub-tab.
----------------------------------------------------------------------
function GuildOS:ShowCalendar()
    GuildOS.UI:OpenWindow("guild", "calendar")
end
