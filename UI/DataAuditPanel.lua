----------------------------------------------------------------------
-- Guild OS - Data audit panel (Officers' Room > Members > Data audit; specs/salao/manutencao-roster.md)
-- The members whose roster data needs an officer: no real join date (only when Guild OS saw them), no alt
-- link at all, or a join date in a note that is not the history's; with the days in their current rank.
-- Filter chips by problem with their counts, a search, columns that sort, and on each row the existing flow
-- that fixes it (Notes and marks' Write date, the member window's Add alt, NoteDates' write). A click on a
-- row opens the member window. Visual layout only: the audit and the actions are GuildOS.RosterMaint's.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
-- Drawn on a parchment card in the Officers' Room (specs/salao/fase3.md): the text takes the paper's inks and a
-- class its colour on the paper (UI/Kit.lua).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local function classInk(class)
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end
local L = GuildOS.L

local SP = UI.SP
local ROW_H = 40           -- a two-line row (Forms.TODO_H): the member, and what is wrong under it
local COL_IN_RANK = 64     -- the days in the rank
local COL_JOINED = 72      -- the join date
local WIDE = 640           -- the list's width from which the join date has a column
local DOT = " \194\183 "
local wideList = true      -- the list is at least WIDE: every action of a row and the join date show

local CHIPS = {
    { kind = "all",      label = L["All"] },
    { kind = "nodate",   label = L["No join date"] },
    { kind = "noalt",    label = L["No alt link"] },
    { kind = "notediff", label = L["Note date differs"] },
}

local function hex(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

-- A note's date or a timestamp, as the client writes a day.
local function dayText(day)
    if type(day) == "table" then
        return GuildOS:DateText(time({ year = day.year, month = day.month, day = day.day, hour = 12 }), "/%y")
    end
    return day and GuildOS:DateText(day, "/%y") or "-"
end

local function whichText(which)
    return which == "officer" and L["officer note"] or L["public note"]
end

-- What a row says is wrong, in the soft ink: each problem, in the chips' order.
local function problemsText(r)
    local parts = {}
    if r.problems.nodate then
        parts[#parts + 1] = r.joinAt and string.format(L["only seen by Guild OS (%s)"], dayText(r.joinAt)) or L["no join date"]
    end
    if r.problems.noalt then parts[#parts + 1] = L["no alt linked"] end
    if r.problems.notediff and r.noteDiff then
        parts[#parts + 1] = string.format(L["%s says %s, history %s"], whichText(r.noteDiff.which), dayText(r.noteDiff.day),
            dayText(r.joinAt))
    end
    return table.concat(parts, DOT)
end

function GuildOS:BuildDataAuditSub(panel)
    local RM = GuildOS.RosterMaint
    if not RM then return nil end
    local Forms = GuildOS.Forms
    local state = { kind = "all", sortBy = "name", asc = true }
    local refresh

    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtDataAuditBoard" })
    local card = board:Card(L["Data audit"], { fill = true })
    card:Note(L["Members whose roster data needs a look: no real join date, no alt linked, or a note whose date is not the history's. Each row's button opens the flow that fixes it; a click on the row opens the member."])
    local hiddenNote = card:Note(L["Your rank cannot read officer notes: only public notes are compared."], {
        shown = function() return not GuildOS.Compat.CanViewOfficerNote() end })
    hiddenNote:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)

    -- The chips: one problem each and All, with how many (the mockup's .chips).
    local chips = {}
    for _, c in ipairs(CHIPS) do
        local b = Forms:Pill(card, c.label)
        b:SetScript("OnClick", function()
            state.kind = c.kind
            refresh()
        end)
        b.kind, b.base = c.kind, c.label
        chips[#chips + 1] = b
    end
    card:Flow(chips)

    local search = UI:CreateInput(card, 220, SP.FIELD, { placeholder = L["Search"], max = 40 })
    search:HookScript("OnTextChanged", function() if refresh then refresh() end end)
    local again = Forms:Button(card, L["Refresh"])
    again:SetScript("OnClick", function() RM:Invalidate(); refresh() end)
    card:Field("", search, { w = 260, button = again })
    local status = card:Note("")

    -- The actions' widths, once: the columns sit left of them on every row and on the header.
    local ACTIONS = { { key = "nodate", label = L["Write date"] }, { key = "noalt", label = L["Link alt..."] },
                      { key = "notediff", label = L["Fix note"] } }
    -- On a narrow list a row shows one action (its first problem's, or the chip's), in the widest one's room.
    local actW, oneW = 0, 0
    for i, a in ipairs(ACTIONS) do
        local probe = Forms:SmallButton(card, a.label)
        a.w = math.ceil(tonumber(probe:GetWidth()) or 70)
        probe:Hide()
        actW = actW + a.w + (i > 1 and 2 * SP.UNIT or 0)
        oneW = math.max(oneW, a.w)
    end
    local function actArea() return wideList and actW or oneW end

    -- The header: Member, In rank and Joined sort (a click again turns the order round).
    local header = UI:CreateTableHeader(card, SP.HIT)
    local heads = {}
    local function headButton(key, text, justify)
        local b = CreateFrame("Button", nil, header)
        b:SetHeight(SP.HIT)
        b.text = UI:CreateHeaderText(b, text, SP.META)
        b.text:SetPoint(justify, b, justify, 0, 0)
        b.arrow = b:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(b.arrow, SP.META)
        b.arrow:Hide()
        if justify == "RIGHT" then b.arrow:SetPoint("RIGHT", b.text, "LEFT", -2, 0)
        else b.arrow:SetPoint("LEFT", b.text, "RIGHT", 2, 0) end
        b:SetScript("OnClick", function()
            if state.sortBy == key then state.asc = not state.asc
            else state.sortBy, state.asc = key, key == "name" end
            refresh()
        end)
        heads[key] = b
        return b
    end
    local hName = headButton("name", L["Member"], "LEFT")
    local hRank = headButton("rankDays", L["In rank"], "RIGHT")
    local hJoined = headButton("joined", L["Joined"], "RIGHT")
    card:Add(header, { h = SP.HIT, wide = true, place = function(f, w)
        f:SetSize(math.max(1, w), SP.HIT)
        wideList = w >= WIDE
        local area = actArea()
        hName:ClearAllPoints()
        hName:SetPoint("LEFT", f, "LEFT", 32, 0)
        hName:SetWidth(120)
        hRank:ClearAllPoints()
        hRank:SetPoint("RIGHT", f, "RIGHT", -(area + 2 * SP.CELL), 0)
        hRank:SetWidth(COL_IN_RANK)
        hJoined:ClearAllPoints()
        hJoined:SetPoint("RIGHT", f, "RIGHT", -(area + 3 * SP.CELL + COL_IN_RANK), 0)
        hJoined:SetWidth(COL_JOINED)
        hJoined:SetShown(wideList)
        return SP.HIT
    end })

    local listHolder = card:Body(ROW_H * 4, { gap = 2 })
    local empty = UI:CreateEmptyState(listHolder, "A", 380)
    empty:Hide()

    local function createRow(parent)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_H)
        if Kit then Kit:Rule(row) end
        row.sel = UI:CreateRowSelection(row)
        row.av = UI:CreateAvatar(row, 24, false)
        row.av:SetPoint("LEFT", 0, 0)
        if row.av.EnableMouse then row.av:EnableMouse(false) end
        row.buttons = {}
        local xr = 0
        for i = #ACTIONS, 1, -1 do
            local a = ACTIONS[i]
            local b = Forms:SmallButton(row, a.label, i == 1 and "primary" or nil)
            b:SetWidth(a.w)
            b.slotX = xr
            xr = xr + a.w + 2 * SP.UNIT
            b:SetScript("OnClick", function()
                local r = row.item
                if not r then return end
                if a.key == "nodate" then RM:WriteDate(r)
                elseif a.key == "noalt" then RM:LinkAlt(r)
                else RM:FixNote(r) end
                refresh()
            end)
            row.buttons[a.key] = b
        end
        row.inRank = UI:CreateText(row, "", SP.BODY, C.text.r, C.text.g, C.text.b)
        GuildOS:ApplyFont(row.inRank, SP.BODY, "tableNum")
        row.inRank:SetWidth(COL_IN_RANK)
        row.inRank:SetJustifyH("RIGHT")
        row.inRank:SetWordWrap(false)
        row.joined = UI:CreateText(row, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.joined:SetWidth(COL_JOINED)
        row.joined:SetJustifyH("RIGHT")
        row.joined:SetWordWrap(false)
        local ink = GuildOS.Colors.paperInk
        row.title = UI:CreateText(row, "", SP.BODY, ink.r, ink.g, ink.b)
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -SP.UNIT)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.sub = Forms:Soft(row, "", SP.META)
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.item then RM:Open(self.item) end end)
        row:SetScript("OnEnter", function(self)
            self.sel:Show()
            local r = self.item
            if not (r and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -2)
            GameTooltip:AddLine(r.name, 1, 1, 1)
            if r.rankSince then
                GameTooltip:AddLine(string.format(L["%s since %s (%d days)"], r.rankName or "?", dayText(r.rankSince),
                    r.rankDays or 0), 0.85, 0.85, 0.85)
            end
            if r.joinAt then
                GameTooltip:AddLine(string.format(r.joinEst and L["Joined %s (seen by Guild OS)"] or L["Joined %s"],
                    dayText(r.joinAt)), 0.85, 0.85, 0.85)
            end
            GameTooltip:AddLine(problemsText(r), 1, 0.82, 0.3, true)
            GameTooltip:AddLine(L["Click: open the member."], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.sel:Hide()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return row
    end

    local function fillRow(row, r)
        row.item = r
        row.av:SetMember(r.name, r.class, not r.online)
        local cr, cg, cb = classInk(r.class)
        local nick = r.nick and (" \"" .. r.nick .. "\"") or ""
        row.title:SetText(r.name .. nick .. "  |cff" .. hex(C.textSoft) .. (r.rankName or "?") .. DOT .. L["Lv "] .. (r.level or 0) .. "|r")
        row.title:SetTextColor(cr, cg, cb)
        row.sub:SetText(problemsText(r))
        row.inRank:SetText(r.rankDays and ((r.rankEst and "~" or "") .. string.format(L["%dd"], r.rankDays)) or "-")
        row.joined:SetText(r.joinAt and ((r.joinEst and "~" or "") .. dayText(r.joinAt)) or "-")
        row.joined:SetShown(wideList)
        local area = actArea()
        row.inRank:ClearAllPoints()
        row.inRank:SetPoint("RIGHT", row, "RIGHT", -(area + 2 * SP.CELL), 0)
        row.joined:ClearAllPoints()
        row.joined:SetPoint("RIGHT", row, "RIGHT", -(area + 3 * SP.CELL + COL_IN_RANK), 0)
        -- The text stops at the columns (the join date's only where it has one).
        local stop = area + 3 * SP.CELL + COL_IN_RANK + (wideList and (COL_JOINED + SP.CELL) or 0)
        for _, fs in ipairs({ row.title, row.sub }) do
            fs:ClearAllPoints()
        end
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -SP.UNIT)
        row.title:SetPoint("RIGHT", row, "RIGHT", -stop, 0)
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -stop, 0)
        -- A row's actions: the active chip's only, or each of its problems on All (in its slot); on a narrow list
        -- only the first of them, at the right.
        local first = true
        for _, a in ipairs(ACTIONS) do
            local b = row.buttons[a.key]
            local on = r.problems[a.key] == true and (state.kind == "all" or state.kind == a.key)
            if on and not wideList and not first then on = false end
            b:ClearAllPoints()
            b:SetPoint("RIGHT", row, "RIGHT", wideList and -b.slotX or 0, 0)
            b:SetShown(on)
            if on then first = false end
        end
    end

    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtDataAuditScroll", ROW_H, createRow, fillRow)

    refresh = function()
        local officer = GuildOS:IsOfficer()
        local data = RM:Audit()
        local counts = data.counts
        for _, b in ipairs(chips) do
            b.label:SetText(string.format("%s (%d)", b.base, counts[b.kind] or 0))
            Forms:FitPill(b)
            Forms:SetOn(b, b.kind == state.kind)
        end
        local rows = RM.Sort(RM.Filter(data.rows, state.kind, search:GetText()), state.sortBy, state.asc)
        for key, b in pairs(heads) do
            if key == state.sortBy then
                b.arrow:SetText(state.asc and "|TInterface\\BUTTONS\\Arrow-Up-Up:12:12|t" or "|TInterface\\BUTTONS\\Arrow-Down-Up:12:12|t")
                b.arrow:Show()
            else
                b.arrow:Hide()
            end
        end
        if not officer then
            status:SetText(L["Officers only."])
        else
            status:SetText(string.format(L["%d of %d member(s) with something to fix"], #rows, counts.all)
                .. DOT .. string.format(L["checked %s"], date("%H:%M", data.at or GetServerTime())))
        end
        board:Layout()
        list:SetData(rows)
        local none = officer and #rows == 0
        empty:SetShown(none)
        if none then
            local w = UI:LaidWidth(listHolder)
            empty:SetWidth(math.max(200, math.min(420, (w > 0 and w or 420) - 4)))
            empty:Set(counts.all == 0 and L["Nothing to fix: every member has a join date, an alt link and notes that agree."]
                or L["Nobody here: the filter or the search hides them."])
            empty:ClearAllPoints()
            empty:SetPoint("TOP", listHolder, "TOP", 0, -SP.SECTION)
        end
    end

    return refresh
end
