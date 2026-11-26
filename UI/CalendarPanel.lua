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
-- The Raids room's calendar (specs/salao/fase3.md, the mockup's raides-calendario): the month on a
-- parchment card on the left, the chosen day on another on the right, both GAP under the entry pills.
local GAP      = UI.GAP
local NAV_Y    = -GAP
local GRID_X   = 0
local PAD      = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
local CELL_GAP = 3      -- between two days
local MAX_BARS = 3      -- event bars a day shows; the rest are in its tooltip and the day's card
local STACK_BELOW = 600 -- px: under this the day's card goes under the month's
local AVATAR   = 24     -- who is going
local ROLE_H   = 40     -- a role counter
local WHITE    = "Interface\\Buttons\\WHITE8x8"

-- The paper's own shades (the mockup's .cal and .roles): a day's line, the chosen day's warm paper and its
-- gold line, a counter's box and the pink of a counter nobody fills yet.
local function hex(h) return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 } end
local CELL_LINE   = hex("d9c49a")
local CHOSEN_FILL = hex("f5e2b3")
local CHOSEN_LINE = hex("b37b12")
local ROLE_FILL   = hex("efe0bd")
local ROLE_MISS   = hex("f6d6c9")

-- A class's colour as the paper prints it (the mockup's .card .c-*): the game's colours, darkened where
-- they would not read on the parchment.
local function paperClass(class)
    return GuildOS.UI:InkFor("paper", "class", class)   -- the paper's class inks (UI/Helpers.lua, #449)
end

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
    RAID    = hex("b0261b"),
    DUNGEON = hex("1d4f99"),
    PVP     = hex("6c2fb0"),
    FARM    = hex("9a6a12"),
    SOCIAL  = hex("3e8e41"),
    OTHER   = hex("6f5a3c"),
    -- Not kinds of event: the calendar's drawn dates (#428).
    BIRTHDAY = hex("e08bb0"),
    JOINDAY  = hex("16758d"),
}
local KIND_RANK = { RAID = 1, DUNGEON = 2, PVP = 3, FARM = 4, SOCIAL = 5, OTHER = 6, BIRTHDAY = 7, JOINDAY = 8 }
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
        -- Alliance raids come from guildos.me (specs/salao/alianca.md): nothing here is shared with one.
        if f.editId and f.inSeries and laterCb.checkbox:GetChecked() then
            CAL():UpdateSeries(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind)
        elseif f.editId then
            CAL():Update(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind)
        elseif f.rep ~= "none" then
            CAL():CreateSeries(title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, false, f.rep)
        else
            CAL():Create(title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, false)
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
        f:SetHeight(336 + REP_ROW + HINT_ROW)
        -- New: pick a repeat. An event of a series: change only it, or every later date too.
        f.inSeries = event and type(event.series) == "table" or false
        f.rep = "none"
        repLbl:SetShown(not event)
        repBtn:SetShown(not event)
        laterCb:SetShown(f.inSeries)
        laterCb.checkbox:SetChecked(false)

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
    local Style = GuildOS.Style
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- Two parchment cards on the wood (the mockup's raides-calendario): the month on the left, the chosen
    -- day on the right; stacked when the window is narrow.
    local monthCard = UI:CreateCard(f, "")
    monthCard:SetPoint("TOPLEFT", GRID_X, NAV_Y)
    f.monthCard = monthCard
    local dayCard = UI:CreateCard(f, "")
    f.dayCard = dayCard

    -- Month navigation: ‹ the month › as the card's title, Today beside it; New Event at the card's right.
    local function arrow(text)
        local b = UI:SetButtonVariant(UI:CreateButton(monthCard, text, 18, 20), "ghost")
        if b.underline then b.underline:Hide() end
        GuildOS:ApplyFont(b.label, 14, "button")
        return b
    end
    local prevBtn = arrow("<")
    prevBtn:SetPoint("TOPLEFT", PAD - 4, -9)
    local monthLabel = monthCard.title
    monthLabel:ClearAllPoints()
    monthLabel:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    local nextBtn = arrow(">")
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", 2, 0)
    local todayBtn = UI:CreateButton(monthCard, L["Today"], 52, 20)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)

    -- Officer "New Event": opens the editor popup for the selected day.
    local newBtn = UI:SetButtonVariant(UI:CreateButton(monthCard, L["New Event"], 92, 22), "primary")
    newBtn:SetPoint("TOPRIGHT", -PAD + 2, -9)
    newBtn:SetScript("OnClick", function()
        if f.selectedKey then openEditor(f.selectedKey, nil) end
    end)
    f.newBtn = newBtn

    -- Birthdays and join anniversaries (#428): dates drawn from the members, never events; each kind
    -- has its filter. On WoW: Forever an officer puts this month's birthdays in the game's calendar.
    -- Laid in Render (#449): on their own line under the month's title, the second under the first when the
    -- card is too narrow for both, and the weekday row under them, never over them.
    local BD = GuildOS.Birthdays
    f.filterBoxes = {}
    if BD then
        for _, kind in ipairs({ "birthday", "join" }) do
            local cb = UI:CreateCheckbox(monthCard, kind == "birthday" and L["Birthdays"] or L["Join anniversaries"], 18)
            cb.label:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
            cb:SetWidth(math.ceil(cb.label:GetStringWidth() or 80) + 28)
            cb.checkbox:SetChecked(BD:Shows(kind))
            cb.checkbox.onChanged = function(_, checked) BD:SetShows(kind, checked) end
            f.filterBoxes[#f.filterBoxes + 1] = cb
        end
    end
    local gameBdayBtn = UI:CreateButton(monthCard, L["Birthdays to the game's calendar"], 200, 20)
    gameBdayBtn:SetScript("OnClick", function() GuildOS.GameCalendar:PutNextBirthday() end)

    -- Weekday headers: the grid's column labels, centred over their column (placed in Render).
    f.wdFS = {}
    for i = 1, COLS do
        local fs = UI:CreateText(monthCard, WEEKDAYS[i], 10, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(fs, 10, "badge")
        fs:SetJustifyH("CENTER")
        f.wdFS[i] = fs
    end

    -- Day cells (the mockup's .cal button): the light paper with a tan line, today outlined in the title's
    -- red, the chosen day on a warmer paper inside a gold line; under the number a coloured bar an event.
    f.cells = {}
    for idx = 1, COLS * ROWS do
        local cell = CreateFrame("Button", nil, monthCard)
        cell.fill = Style:Nine(cell, "card", 4, "BACKGROUND", -6)
        cell.line = Style:Nine(cell, "card-line", 4, "BACKGROUND", -5)
        cell.ring = Style:Nine(cell, "card-line", 4, "BACKGROUND", -4, { 1, 1, 1, 1 })
        cell.dayFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.dayFS, 11)
        cell.dayFS:SetPoint("TOPLEFT", 5, -3)
        cell.bars = {}
        for b = 1, MAX_BARS do
            local bar = cell:CreateTexture(nil, "ARTWORK")
            bar:SetTexture(WHITE)
            bar:SetHeight(4)
            bar:SetPoint("TOPLEFT", 4, -18 - (b - 1) * 6)
            bar:SetPoint("TOPRIGHT", -4, -18 - (b - 1) * 6)
            bar:Hide()
            cell.bars[b] = bar
        end
        -- The first event's name, where the cell is wide enough to read it (the bars always say what kind).
        cell.evtFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.evtFS, 9)
        cell.evtFS:SetPoint("BOTTOMLEFT", 4, 3)
        cell.evtFS:SetPoint("BOTTOMRIGHT", -4, 3)
        cell.evtFS:SetJustifyH("LEFT"); cell.evtFS:SetWordWrap(false)
        cell.evtFS:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        cell:SetScript("OnClick", function(self2)
            if self2.dkey then f.selectedKey = self2.dkey; f.Render() end
        end)
        -- The day's events by name under the cursor: a narrow cell shows only their bars.
        cell:SetScript("OnEnter", function(self2)
            if not (self2.events and #self2.events > 0) then return end
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            for _, e in ipairs(self2.events) do
                local kc = kindColor(e.kind)
                GameTooltip:AddLine((e.virtual and "" or date("%H:%M ", e.when)) .. (e.title or ""),
                    math.min(1, kc.r + 0.35), math.min(1, kc.g + 0.35), math.min(1, kc.b + 0.35))
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.cells[idx] = cell
    end

    -- The legend under the grid: a short bar and the name of each kind on the month.
    f.legend = {}
    local function legendItem(i)
        local it = f.legend[i]
        if it then return it end
        it = CreateFrame("Frame", nil, monthCard)
        it:SetSize(60, 14)
        it.bar = it:CreateTexture(nil, "ARTWORK")
        it.bar:SetTexture(WHITE)
        it.bar:SetSize(12, 4)
        it.bar:SetPoint("LEFT", 0, 0)
        it.fs = UI:CreateText(it, "", 10, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        it.fs:SetPoint("LEFT", it.bar, "RIGHT", 4, 0)
        f.legend[i] = it
        return it
    end

    -- The chosen day: the right card's title, its events in a scroll list under it.
    local detailLabel = dayCard.title
    f.detailLabel = detailLabel
    local holder = CreateFrame("Frame", nil, dayCard)
    holder:SetPoint("TOPLEFT", PAD, -CARD_TOP)
    holder:SetPoint("BOTTOMRIGHT", -PAD + 4, 10)
    f.holder = holder
    local scrollFrame, scrollChild = UI:CreateScrollFrame(holder, "GuildOSCalendarScroll")
    scrollFrame:SetAllPoints()   -- fill the holder; without this the scroll viewport is 0x0 and clips all content
    -- The child keeps the list's width, less the bar's gutter; the rows hang from both its top corners.
    UI:BindScrollChildWidth(scrollFrame, scrollChild)
    f.child = scrollChild

    ------------------------------------------------------------------
    -- Render (the cards size to the current panel)
    ------------------------------------------------------------------
    function f.Render()
        local W, H = f:GetWidth(), f:GetHeight()
        if not W or W < 120 then W = 1000 end
        if not H or H < 200 then H = 520 end
        local stacked = W < STACK_BELOW
        local leftW = stacked and (W - GAP) or math.floor((W - GAP) * 0.54)
        local innerW = leftW - 2 * PAD
        local cellW = math.floor((innerW + CELL_GAP) / COLS)

        monthLabel:SetText(GuildOS:LocalDate(L["%b %Y"], noon(f.viewYear, f.viewMonth, 1)))

        -- Bucket events by day.
        local byDay = {}
        for _, e in pairs(CAL():GetEvents()) do
            if not e.canceled then
                local k = keyOfTs(e.when)
                byDay[k] = byDay[k] or {}
                byDay[k][#byDay[k] + 1] = e
            end
        end

        -- The raids the allied guilds opened to the alliance (guildos.me's GOSALLY1, Alliance:OpenRaids): shown,
        -- never stored in the calendar, nothing to answer here (alianca.md §3.2). Its text is inert already
        -- (CompanionImport.ReadAlliance).
        local ALLY = GuildOS.Alliance
        for _, r in ipairs(ALLY and ALLY:OpenRaids() or {}) do
            local k = keyOfTs(r.when)
            byDay[k] = byDay[k] or {}
            byDay[k][#byDay[k] + 1] = { allied = true, kind = "RAID", when = r.when, guild = r.guild,
                title = "[" .. tostring(r.guild or "?") .. "] " .. tostring(r.title or "?"),
                where = r.where, leader = r.leader, going = r.going, size = r.size }
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
        local gameBday = GuildOS.GameCalendar ~= nil and BD ~= nil and GuildOS.GameCalendar:CanAct()
        gameBdayBtn:SetShown(gameBday)
        local lead = firstWeekday(f.viewYear, f.viewMonth) - 1
        local todayKey = keyOfTs(GetServerTime())
        local rows = math.ceil((lead + dim) / COLS)

        -- The cells grow with the window, never under the mockup's 44px less what a short window lacks.
        -- Under the title (36px), the filters' line(s), then the weekday row (16px) and the grid.
        local filterTop, x, fline = 36, 0, 0
        for _, cb in ipairs(f.filterBoxes) do
            local cw = cb:GetWidth() or 100
            if x > 0 and x + cw > innerW then x, fline = 0, fline + 1 end
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", monthCard, "TOPLEFT", PAD - 2 + x, -(filterTop + fline * 22))
            x = x + cw + 10
        end
        local filtersH = #f.filterBoxes > 0 and ((fline + 1) * 22) or 0
        local gridTop = filterTop + filtersH + 18
        local room = H - gridTop - 34 - 2 * GAP
        local cellH = math.max(30, math.min(56, math.floor(room / rows) - CELL_GAP))
        if stacked then cellH = math.max(30, math.min(cellH, 40)) end

        for i = 1, COLS do
            f.wdFS[i]:ClearAllPoints()
            f.wdFS[i]:SetPoint("TOP", monthCard, "TOPLEFT", PAD + (i - 1) * cellW + (cellW - CELL_GAP) / 2, -gridTop + 15)
        end

        local kindsShown, kindOrder = {}, {}
        for idx = 1, COLS * ROWS do
            local col = (idx - 1) % COLS
            local row = math.floor((idx - 1) / COLS)
            local cell = f.cells[idx]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", PAD + col * cellW, -gridTop - row * (cellH + CELL_GAP))
            cell:SetSize(cellW - CELL_GAP, cellH)
            cell:SetShown(row < rows)

            local dayNum = idx - lead
            cell.events = nil
            for _, bar in ipairs(cell.bars) do bar:Hide() end
            if dayNum < 1 or dayNum > dim then
                -- The days of the months either side: the paper, faded, no number.
                cell.dayFS:SetText(""); cell.evtFS:SetText(""); cell.dkey = nil
                cell.fill:SetColor(C.paperLight, 0.4)
                cell.line:SetColor(C.paperLine, 0.4)
                cell.ring:SetShown(false)
            else
                local k = dayKey(f.viewYear, f.viewMonth, dayNum)
                cell.dkey = k
                cell.dayFS:SetText(dayNum)
                cell.dayFS:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
                local evs = byDay[k]
                if evs then
                    table.sort(evs, function(a, b) return a.when < b.when end)
                    cell.events = evs
                    local line = (evs[1].virtual and "" or date("%H:%M ", evs[1].when)) .. (evs[1].title or "")
                    if #evs > 1 then line = "+" .. #evs .. " " .. line end
                    cell.evtFS:SetText(line)
                    local maxBars = math.max(1, math.min(MAX_BARS, math.floor((cellH - 20) / 6)))
                    for b = 1, math.min(#evs, maxBars) do
                        local kc = kindColor(evs[b].kind)
                        cell.bars[b]:SetVertexColor(kc.r, kc.g, kc.b, 1)
                        cell.bars[b]:Show()
                    end
                    for _, e in ipairs(evs) do
                        local kk = KIND_COLOR[e.kind] and e.kind or "RAID"
                        if not kindsShown[kk] then kindsShown[kk] = true; kindOrder[#kindOrder + 1] = kk end
                    end
                    -- The name too where the cell has the room for it under its bars.
                    cell.evtFS:SetShown(cellW >= 84 and cellH >= 20 + math.min(#evs, maxBars) * 6 + 12)
                else
                    cell.evtFS:SetText("")
                end
                local chosen = k == f.selectedKey
                cell.fill:SetColor(chosen and CHOSEN_FILL or C.paperLight)
                cell.line:SetColor(k == todayKey and C.paperTitle or (chosen and CHOSEN_LINE or CELL_LINE))
                -- A 2px line: today's red, or the chosen day's gold inside it.
                cell.ring:SetShown(chosen or k == todayKey)
                cell.ring:SetColor(chosen and CHOSEN_LINE or C.paperTitle)
            end
        end

        -- The legend: the kinds on this month, in the order the calendar knows them.
        table.sort(kindOrder, function(a, b) return (KIND_RANK[a] or 99) < (KIND_RANK[b] or 99) end)
        local legendY = -gridTop - rows * (cellH + CELL_GAP) - 6
        local lx = PAD
        for i, k in ipairs(kindOrder) do
            local it = legendItem(i)
            local kc = kindColor(k)
            it.bar:SetVertexColor(kc.r, kc.g, kc.b, 1)
            it.fs:SetText(kindLabel(k):lower())
            it:SetWidth(16 + math.ceil(it.fs:GetStringWidth() or 40) + 10)
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", lx, legendY)
            it:Show()
            lx = lx + it:GetWidth()
        end
        for i = #kindOrder + 1, #f.legend do f.legend[i]:Hide() end
        gameBdayBtn:ClearAllPoints()
        gameBdayBtn:SetPoint("TOPRIGHT", -PAD + 2, legendY + 4)
        local cardH = gridTop + rows * (cellH + CELL_GAP) + 6 + ((#kindOrder > 0 or gameBday) and 22 or 4) + 8
        monthCard:SetSize(leftW, cardH)

        dayCard:ClearAllPoints()
        if stacked then
            dayCard:SetPoint("TOPLEFT", monthCard, "BOTTOMLEFT", 0, -GAP - 4)
            dayCard:SetWidth(leftW)
        else
            dayCard:SetPoint("TOPLEFT", monthCard, "TOPRIGHT", GAP + 4, 0)
            dayCard:SetWidth(W - GAP - leftW - GAP - 4)
        end
        f.dayRoom = stacked and math.max(120, H - cardH - 2 * GAP - 4) or (H - 2 * GAP)

        f.RenderDetail(byDay)
    end

    ------------------------------------------------------------------
    -- Detail for the selected day
    ------------------------------------------------------------------
    function f.RenderDetail(byDay)
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
        local ink, soft = C.paperInk, C.paperSoft
        local function text(s, size, col, role)
            col = col or ink
            local fs = UI:CreateText(child, s, size or 12, col.r, col.g, col.b)
            if role then GuildOS:ApplyFont(fs, size, role) end
            fs:SetJustifyH("LEFT")
            return fs
        end
        -- A small section heading inside the day (the mockup's .sec b): Cinzel, the title's red.
        local function heading(s, y)
            local fs = text(s, 11, C.paperTitle, "sectionTitle")
            fs:SetPoint("TOPLEFT", 0, -y)
            return fs
        end
        local listW = UI:LaidWidth(child)
        if not listW or listW < 60 then listW = 360 end

        local evs, virtual, allied = {}, {}, {}
        for _, e in ipairs((sel and byDay and byDay[sel]) or {}) do
            if e.virtual then virtual[#virtual + 1] = e
            elseif e.allied then allied[#allied + 1] = e
            else evs[#evs + 1] = e end
        end
        local yy = 0
        -- Birthdays and join anniversaries first, a line each: nothing to sign up to (#428).
        for _, e in ipairs(virtual) do
            local fs = text(tint("[" .. kindLabel(e.kind) .. "]", kindColor(e.kind)) .. " " .. (e.title or ""), 12)
            across(fs, yy)
            yy = yy + 20
        end
        if #virtual > 0 then yy = yy + 8 end
        -- The alliance's open raids: read-only, as the site sent them.
        if #allied > 0 then
            table.sort(allied, function(a, b) return a.when < b.when end)
            local asOf = GuildOS.Alliance and GuildOS.Alliance:AsOf()
            for _, e in ipairs(allied) do
                local fs = text(date("%H:%M ", e.when) .. tint("[" .. L["Alliance"] .. "]", kindColor("RAID")) .. " "
                    .. e.title .. "  " .. tint(string.format("%d/%d", e.going or 0, e.size or 0), soft), 12)
                across(fs, yy)
                yy = yy + 18
                local bits = {}
                if e.where then bits[#bits + 1] = e.where end
                if e.leader then bits[#bits + 1] = string.format(L["led by %s"], e.leader) end
                bits[#bits + 1] = L["Sign up in Discord or on the website."]
                if asOf then bits[#bits + 1] = string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", asOf)) end
                local sub = text(table.concat(bits, " · "), 11, soft)
                across(sub, yy)
                yy = yy + math.max(16, (sub:GetStringHeight() or 12) + 4)
            end
            yy = yy + 8
        end
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

        -- Who is going, as round class avatars in a row, and how many more there are past the row.
        local function faces(list, y)
            local n = #list
            if n == 0 then return y end
            local fit = math.max(1, math.floor((listW - 70) / (AVATAR + 4)))
            local shownN = (n > fit) and fit or n
            for i = 1, shownN do
                local a = UI:CreateAvatar(child, AVATAR, false)
                a:SetPoint("TOPLEFT", (i - 1) * (AVATAR + 4), -y)
                a:SetMember(list[i].name, list[i].class)
                local nm = list[i].name
                a:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    GameTooltip:AddLine(nm, 1, 1, 1)
                    GameTooltip:Show()
                end)
                a:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            if n > shownN then
                local more = text(string.format(L["and %d more"], n - shownN), 11, soft)
                more:SetPoint("LEFT", child, "TOPLEFT", shownN * (AVATAR + 4) + 4, -y - AVATAR / 2)
            end
            return y + AVATAR + 8
        end

        -- The role counters (the mockup's .roles): a box each, pink where nobody is there yet.
        local function roleBoxes(boxes, y)
            local n = #boxes
            local bw = math.floor((listW - (n - 1) * 6) / n)
            for i, b in ipairs(boxes) do
                local box = CreateFrame("Frame", nil, child)
                box:SetSize(bw, ROLE_H)
                box:SetPoint("TOPLEFT", (i - 1) * (bw + 6), -y)
                local fill = Style:Nine(box, "card", 5, "BACKGROUND", -6)
                fill:SetColor(b.miss and ROLE_MISS or ROLE_FILL)
                local v = UI:CreateText(box, b.value, 14, ink.r, ink.g, ink.b)
                GuildOS:ApplyFont(v, 14, "button")
                v:SetPoint("TOP", 0, -5)
                local cap = UI:CreateText(box, b.label, 10, soft.r, soft.g, soft.b)
                cap:SetPoint("TOP", v, "BOTTOM", 0, -1)
            end
            return y + ROLE_H + 8
        end

        -- Per-day render is wrapped so a single malformed event can't blank the
        -- whole list; any failure is surfaced inline instead.
        local okAll, errAll = pcall(function()
        for n, e in ipairs(evs) do
            local comp = CAL():GetComposition(e)
            local mine = CAL():MyRsvp(e)
            if n > 1 then
                local rule = child:CreateTexture(nil, "ARTWORK")
                rule:SetTexture(WHITE)
                rule:SetHeight(1)
                rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
                rule:SetPoint("TOPLEFT", 0, -yy + 6)
                rule:SetPoint("TOPRIGHT", 0, -yy + 6)
                yy = yy + 6
            end

            -- The event's name in the title's face; under it the hour in bold with its kind (in the colour the
            -- grid marks the day with), the size and "(repeats)".
            local inSeries = type(e.series) == "table"
            local siteEvent = CAL().IsSiteEvent and CAL():IsSiteEvent(e)
            local name = text(e.title or "", 13, C.paperTitle, "sectionTitle")
            name:SetPoint("TOPLEFT", 0, -yy)
            name:SetPoint("RIGHT", child, "RIGHT", -150, 0)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
            if CAL():MayManage(e) then
                local ev = e
                local delBtn = UI:CreateButton(child, L["Delete"], 58, 20)
                delBtn:SetPoint("TOPRIGHT", 0, -yy + 2)
                delBtn:SetScript("OnClick", function() confirmDelete(ev) end)
                local editBtn = UI:CreateButton(child, L["Edit"], 48, 20)
                editBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                editBtn:SetScript("OnClick", function() openEditor(nil, ev) end)
                if inSeries then
                    -- This date and every later one of the series go (#267).
                    local endBtn = UI:CreateButton(child, L["End series"], 80, 20)
                    endBtn:SetPoint("TOPRIGHT", delBtn, "BOTTOMRIGHT", 0, -4)
                    endBtn:SetScript("OnClick", function() confirmEndSeries(ev) end)
                end
            end
            yy = yy + 20
            local tag = tint(kindLabel(e.kind), kindColor(e.kind))
            local sizeMark = siteEvent and "" or ("  " .. tint("(" .. (e.size or DEFAULT_SIZE) .. ")", soft))
            local repMark = inSeries and ("  " .. tint(L["(repeats)"], soft)) or ""
            local when = text(date("%H:%M", e.when) .. "  ·  " .. tag .. sizeMark .. repMark, 12, ink, "button")
            when:SetPoint("TOPLEFT", 0, -yy)
            yy = yy + 18
            local countLine = string.format(L["%d going · %d maybe"], comp.yes, comp.tentative)
            local countFS = text(countLine, 11, soft)
            countFS:SetPoint("TOPLEFT", 0, -yy)
            yy = yy + 20

            -- The counters: the site's going and maybe for an event that is not a raid; else the roles of
            -- who is going and the seats taken.
            if siteEvent then
                yy = roleBoxes({ { value = tostring(comp.yes), label = L["Going"] },
                                 { value = tostring(comp.tentative), label = L["Tentative"] } }, yy)
            else
                local size = e.size or DEFAULT_SIZE
                yy = roleBoxes({
                    { value = tostring(comp.roles.TANK), label = L["Tanks"], miss = comp.roles.TANK == 0 },
                    { value = tostring(comp.roles.HEALER), label = L["Healers"], miss = comp.roles.HEALER == 0 },
                    { value = tostring(comp.roles.DPS), label = L["DPS"], miss = comp.roles.DPS == 0 },
                    { value = string.format("%d/%d", comp.yes, size), label = L["Going"], miss = comp.yes < size },
                }, yy)
            end

            -- The note, on a darker paper in the reading face (the mockup's .msg).
            if e.note and e.note ~= "" then
                local box = CreateFrame("Frame", nil, child)
                box:SetPoint("TOPLEFT", 0, -yy)
                box:SetPoint("TOPRIGHT", 0, -yy)
                local fill = Style:Nine(box, "card", 5, "BACKGROUND", -6)
                fill:SetColor(ROLE_FILL)
                local noteFS = UI:CreateText(box, e.note, 13, ink.r, ink.g, ink.b)
                GuildOS:ApplyFont(noteFS, 13, "reading")
                noteFS:SetPoint("TOPLEFT", 10, -7)
                noteFS:SetPoint("TOPRIGHT", -10, -7)
                noteFS:SetJustifyH("LEFT")
                local h = math.max(16, noteFS:GetStringHeight() or 14) + 14
                box:SetHeight(h)
                yy = yy + h + 10
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
                local whereFS = text(where, 11, soft)
                across(whereFS, yy)
                yy = yy + math.max(16, (whereFS:GetStringHeight() or 12) + 4)
                -- Whether it is in the game's own calendar, and for an officer the click that changes it. Not for
                -- the site's events that are not raids (#652): the game's guild event is one to sign up and invite to.
                if gameOn and not siteEvent then
                    local view = GC:ViewFor(e, gameEvents, inbox)
                    if view.text then
                        local stateFS = text(view.text, 11, soft)
                        stateFS:SetPoint("TOPLEFT", 0, -yy)
                        yy = yy + 18
                        if view.action then
                            local evId, action = e.id, view.action
                            local gameBtn = UI:CreateButton(child, view.label, 200, 22)
                            gameBtn:SetPoint("TOPLEFT", 0, -yy)
                            gameBtn:SetScript("OnClick", function() GC:Act(evId, action) end)
                            yy = yy + 28
                        end
                    end
                end
                -- An allied seat is approved in the game, and goes with the ones coming.
                local answers = CAL():WebSignups(e)
                for _, r in pairs(e.rsvps or {}) do
                    if r.ally and r.status == "yes" then
                        answers[#answers + 1] = { name = GuildOS:SanitizeUserText(r.name or "?", 48), class = r.class, status = "yes" }
                    end
                end
                local going = {}
                for _, s in ipairs(answers) do
                    if s.status == "yes" then going[#going + 1] = s end
                end
                if #going > 0 then
                    heading(L["Who's going"], yy)
                    yy = faces(going, yy + 18)
                end
                for _, line in ipairs({
                    { "yes", L["Going: "] }, { "pending", L["Awaiting approval: "] },
                    { "tentative", L["Tentative: "] }, { "wait", L["Standby: "] }, { "no", L["Absent: "] },
                }) do
                    local names = {}
                    for _, s in ipairs(answers) do
                        if s.status == line[1] then
                            local cr, cg, cb = paperClass(s.class)
                            names[#names + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, s.name)
                        end
                    end
                    if #names > 0 then
                        local fs = text(line[2] .. table.concat(names, ", "), 11, soft)
                        across(fs, yy)
                        yy = yy + math.max(14, (fs:GetStringHeight() or 12) + 4)
                    end
                end
            else
                -- My answer: the three choices, the chosen one the primary button, and the role I go as.
                heading(L["Your answer"], yy)
                yy = yy + 18
                local id = e.id
                local function rsvpBtn(label, status, anchor, xoff)
                    local b = UI:CreateButton(child, label, 54, 22)
                    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", xoff, 0) else b:SetPoint("TOPLEFT", 0, -yy) end
                    if mine and mine.status == status then UI:SetButtonVariant(b, "primary") end
                    return b
                end
                local goingBtn = rsvpBtn(L["Going"],     "yes",       nil,      0)
                local tentBtn  = rsvpBtn(L["Tentative"], "tentative", goingBtn, 6)
                local noBtn    = rsvpBtn(L["Absent"],    "no",        tentBtn,  6)
                local roleBtn = UI:SetButtonVariant(UI:CreateButton(child, roleLabel((mine and mine.role) or "DPS"), 60, 22), "chip")
                roleBtn:SetPoint("LEFT", noBtn, "RIGHT", 10, 0)
                roleBtn.role = (mine and mine.role) or "DPS"
                roleBtn:SetScript("OnClick", function()
                    local i = 1
                    for j, v in ipairs(ROLES) do if v == roleBtn.role then i = j break end end
                    roleBtn.role = ROLES[(i % #ROLES) + 1]
                    roleBtn.label:SetText(roleLabel(roleBtn.role))
                end)
                for b, status in pairs({ [goingBtn] = "yes", [tentBtn] = "tentative", [noBtn] = "no" }) do
                    b:SetScript("OnClick", function() CAL():Rsvp(id, status, roleBtn.role) end)
                end
                yy = yy + 30

                local going = {}
                for _, r in pairs(e.rsvps or {}) do
                    if r.status == "yes" then going[#going + 1] = { name = r.name or "?", class = r.class } end
                end
                table.sort(going, function(a, b) return a.name < b.name end)
                if #going > 0 then
                    heading(L["Who's going"], yy)
                    yy = faces(going, yy + 18)
                end
            end

            yy = yy + 10
        end
        end)
        if not okAll then
            local errFS = text(tostring(errAll), 11, C.paperTitle)
            across(errFS, yy)
            yy = yy + math.max(40, (errFS:GetStringHeight() or 20) + 10)
        end

        if sel and #evs == 0 and #virtual == 0 and #allied == 0 then
            local none = text(canCreate and L["No events. Use New Event to add one."] or L["No events this day."], 12, soft)
            across(none, 0)
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
                local msg = why == "window"
                    and string.format(L["Raids planned on the website more than %d days ahead have not reached the game yet; they arrive as the date gets closer."], GuildOS.GameCalendar.WINDOW_DAYS)
                    or string.format(L["The website sends the game its next %d raids; later ones arrive as those pass."], GuildOS.GameCalendar.INBOX_CAP)
                local fs = text(msg, 11, soft)
                across(fs, yy + 4)
                yy = yy + 4 + math.max(14, (fs:GetStringHeight() or 12) + 6)
            end
        end
        child:SetHeight(math.max(1, yy))
        -- The day's card is as tall as what it holds, up to the room there is; past that its list scrolls.
        dayCard:SetHeight(math.max(90, math.min(f.dayRoom or 480, CARD_TOP + yy + 14)))
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
