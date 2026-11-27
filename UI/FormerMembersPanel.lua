----------------------------------------------------------------------
-- Guild OS - Former members panel (Officers' Room > Members > Former members; specs/salao/manutencao-roster.md §6)
-- Who left the guild, from what Guild OS keeps past a departure: the last departure and how long ago, how they
-- went (left, removed by X, banned or suspended), their passages and days in the guild, and whether the officers
-- have notes on them or alts linked. Filter chips with their counts, a search over the name and the notes, columns
-- that sort, and on each row Ban... or Unban, Invite back and Forget. A click on a row opens the member window as a
-- former member's. Visual layout only: the list and the actions are GuildOS.FormerMembers'.
-- Mirrors UI/DataAuditPanel.lua: one paper card, a virtual list of pooled rows (UI.MakeVirtualList), and a change
-- that arrives while the screen is hidden only marks it stale (specs/salao/memoria.md).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local function classInk(class)
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end
local L = GuildOS.L

local SP = UI.SP
local ROW_H = 40           -- a two-line row (Forms.TODO_H): the name, and how they went under it
local COL_LEFT = 92        -- the last departure: the date, and "N days ago" under it
local COL_STINTS = 44      -- the passages
local COL_DAYS = 56        -- the days in the guild over all of them
local WIDE = 700           -- the list's width from which the passages and the days have columns, and Ban... shows
local DOT = " \194\183 "
local wideList = true

local CHIPS = {
    { kind = "all",     label = L["All"] },
    { kind = "left",    label = L["Left"] },
    { kind = "removed", label = L["Removed"] },
    { kind = "banned",  label = L["Banned"] },
    { kind = "notes",   label = L["With notes"] },
}

local function hex(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

local function dayText(t)
    return t and GuildOS:DateText(t, "/%y") or "-"
end

-- What a row says under the name: how they went (a ban in the paper's red), then the notes and the alts, and on a
-- narrow list the passages and the days the columns would hold.
local function subText(FM, r)
    local how = FM.HowText(r)
    if r.ban then how = "|cff" .. hex(C.danger) .. how .. "|r" end
    local parts = { how }
    if r.hasNotes then parts[#parts + 1] = L["has notes"] end
    if r.hasAlts then parts[#parts + 1] = L["has alts"] end
    if not wideList then
        parts[#parts + 1] = string.format(L["%d stint(s), %s days"], r.stints or 0, r.days and tostring(r.days) or "?")
    end
    return table.concat(parts, DOT)
end

function GuildOS:BuildFormerMembersSub(panel)
    local FM = GuildOS.FormerMembers
    if not FM then return nil end
    local Forms = GuildOS.Forms
    local state = { kind = "all", sortBy = "left", asc = false }
    local refresh

    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtFormerBoard" })
    local card = board:Card(L["Former members"], { fill = true })
    card:Note(L["Who left the guild, from the membership history Guild OS keeps after a departure, with the bans, the officers' notes and the alt links. A click on a row opens the member."])

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

    local search = UI:CreateInput(card, 220, SP.FIELD, { placeholder = L["Search name or note"], max = 40 })
    search:HookScript("OnTextChanged", function() if refresh then refresh() end end)
    local again = Forms:Button(card, L["Refresh"])
    again:SetScript("OnClick", function() FM:Invalidate(); refresh() end)
    card:Field("", search, { w = 260, button = again })
    local status = card:Note("")

    -- The actions' widths, once. Wide: Ban... or Unban (one slot), Invite back, Forget. Narrow: the row's first
    -- (Unban when banned, else Invite back) and Forget.
    local ACTIONS = { { key = "ban", label = L["Ban..."] }, { key = "unban", label = L["Unban"] },
                      { key = "invite", label = L["Invite back"] }, { key = "forget", label = L["Forget"] } }
    local width = {}
    for _, a in ipairs(ACTIONS) do
        local probe = Forms:SmallButton(card, a.label)
        a.w = math.ceil(tonumber(probe:GetWidth()) or 70)
        width[a.key] = a.w
        probe:Hide()
    end
    local GAP = 2 * SP.UNIT
    local slotBan = math.max(width.ban, width.unban)
    local slotFirst = math.max(width.unban, width.invite)
    local function actArea()
        if wideList then return slotBan + width.invite + width.forget + 2 * GAP end
        return slotFirst + width.forget + GAP
    end

    -- The header: Member, Left and Days sort (a click again turns the order round); Stints only reads.
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
        if key then
            b:SetScript("OnClick", function()
                if state.sortBy == key then state.asc = not state.asc
                else state.sortBy, state.asc = key, key == "name" end
                refresh()
            end)
            heads[key] = b
        end
        return b
    end
    local hName = headButton("name", L["Member"], "LEFT")
    local hLeft = headButton("left", L["Left"], "RIGHT")
    local hStints = headButton(nil, L["Stints"], "RIGHT")
    local hDays = headButton("days", L["Days"], "RIGHT")
    -- Where each column's right edge sits, from the row's right, past the actions.
    local function cols()
        local x = actArea() + 2 * SP.CELL
        local out = { left = x }
        if wideList then
            out.days = x + COL_LEFT + SP.CELL
            out.stints = out.days + COL_DAYS + SP.CELL
            out.stop = out.stints + COL_STINTS + SP.CELL
        else
            out.stop = x + COL_LEFT + SP.CELL
        end
        return out
    end
    card:Add(header, { h = SP.HIT, wide = true, place = function(f, w)
        f:SetSize(math.max(1, w), SP.HIT)
        wideList = w >= WIDE
        local x = cols()
        hName:ClearAllPoints()
        hName:SetPoint("LEFT", f, "LEFT", 32, 0)
        hName:SetWidth(120)
        hLeft:ClearAllPoints()
        hLeft:SetPoint("RIGHT", f, "RIGHT", -x.left, 0)
        hLeft:SetWidth(COL_LEFT)
        hDays:ClearAllPoints()
        hStints:ClearAllPoints()
        if wideList then
            hDays:SetPoint("RIGHT", f, "RIGHT", -x.days, 0)
            hStints:SetPoint("RIGHT", f, "RIGHT", -x.stints, 0)
        end
        hDays:SetWidth(COL_DAYS)
        hStints:SetWidth(COL_STINTS)
        hDays:SetShown(wideList)
        hStints:SetShown(wideList)
        return SP.HIT
    end })

    local listHolder = card:Body(ROW_H * 4, { gap = 2 })
    local empty = UI:CreateEmptyState(listHolder, "?", 380)
    empty:Hide()

    local function rightText(row, size, soft, w)
        local ink = soft and C.textSoft or C.text
        local fs = UI:CreateText(row, "", size, ink.r, ink.g, ink.b)
        fs:SetWidth(w)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        return fs
    end

    local function createRow(parent)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        if Kit then Kit:Rule(row) end
        row.sel = UI:CreateRowSelection(row)
        row.av = UI:CreateAvatar(row, 24, false)
        row.av:SetPoint("LEFT", 0, 0)
        if row.av.EnableMouse then row.av:EnableMouse(false) end
        row.buttons = {}
        for _, a in ipairs(ACTIONS) do
            local b = Forms:SmallButton(row, a.label, nil)
            b:SetWidth(a.w)
            b:SetScript("OnClick", function()
                local r = row.item
                if not r then return end
                if a.key == "ban" then FM:Ban(r)
                elseif a.key == "unban" then FM:Unban(r)
                elseif a.key == "invite" then FM:InviteBack(r)
                else FM:Forget(r) end
            end)
            row.buttons[a.key] = b
        end
        row.leftDate = rightText(row, SP.BODY, false, COL_LEFT)
        GuildOS:ApplyFont(row.leftDate, SP.BODY, "tableNum")
        row.leftAgo = rightText(row, SP.META, true, COL_LEFT)
        row.stints = rightText(row, SP.BODY, false, COL_STINTS)
        GuildOS:ApplyFont(row.stints, SP.BODY, "tableNum")
        row.days = rightText(row, SP.BODY, false, COL_DAYS)
        GuildOS:ApplyFont(row.days, SP.BODY, "tableNum")
        local ink = GuildOS.Colors.paperInk
        row.title = UI:CreateText(row, "", SP.BODY, ink.r, ink.g, ink.b)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.sub = Forms:Soft(row, "", SP.META)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.item then FM:Open(self.item) end end)
        row:SetScript("OnEnter", function(self)
            self.sel:Show()
            local r = self.item
            if not (r and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -2)
            GameTooltip:AddLine(r.name, 1, 1, 1)
            local day = GuildOS:DateText(r.leftAt or 0, "/%Y")
            if r.leftEst then day = string.format(L["%s (seen by GuildOS)"], day) end
            GameTooltip:AddLine(string.format(L["Left the guild on %s"], day) .. DOT .. FM.AgoText(r.ago), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(FM.HowText(r), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(string.format(L["%d stint(s), %s days"], r.stints or 0, r.days and tostring(r.days) or "?"),
                0.85, 0.85, 0.85)
            if r.banReason then
                GameTooltip:AddLine(string.format(L["Reason: %s"], GuildOS:SanitizeUserText(r.banReason, 120)), 1, 0.45, 0.4, true)
            end
            if r.note then
                GameTooltip:AddLine(GuildOS:SanitizeUserText(r.note, 300), 1, 0.82, 0.3, true)
            end
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
        row.av:SetMember(r.name, r.class, true)
        local cr, cg, cb = classInk(r.class)
        if not r.class then local ink = GuildOS.Colors.paperInk; cr, cg, cb = ink.r, ink.g, ink.b end
        row.title:SetText(r.name)
        row.title:SetTextColor(cr, cg, cb)
        row.sub:SetText(subText(FM, r))
        row.leftDate:SetText((r.leftEst and "~" or "") .. dayText(r.leftAt))
        row.leftAgo:SetText(FM.AgoText(r.ago))
        row.stints:SetText(tostring(r.stints or 0))
        row.days:SetText(r.days and tostring(r.days) or "-")
        local x = cols()
        row.leftDate:ClearAllPoints()
        row.leftDate:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x.left, -SP.UNIT)
        row.leftAgo:ClearAllPoints()
        row.leftAgo:SetPoint("TOPRIGHT", row.leftDate, "BOTTOMRIGHT", 0, -2)
        row.stints:ClearAllPoints()
        row.days:ClearAllPoints()
        if wideList then
            row.days:SetPoint("RIGHT", row, "RIGHT", -x.days, 0)
            row.stints:SetPoint("RIGHT", row, "RIGHT", -x.stints, 0)
        end
        row.stints:SetShown(wideList)
        row.days:SetShown(wideList)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -SP.UNIT)
        row.title:SetPoint("RIGHT", row, "RIGHT", -x.stop, 0)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -x.stop, 0)
        -- The actions, right to left: Forget, Invite back, then Ban... or Unban (wide); Forget and the first (narrow).
        local b = row.buttons
        for _, a in ipairs(ACTIONS) do b[a.key]:ClearAllPoints() end
        b.forget:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        b.forget:Show()
        local banned = r.ban ~= nil
        if wideList then
            b.invite:SetPoint("RIGHT", row, "RIGHT", -(width.forget + GAP), 0)
            b.invite:Show()
            local slot = b[banned and "unban" or "ban"]
            slot:SetPoint("RIGHT", row, "RIGHT", -(width.forget + width.invite + 2 * GAP), 0)
            b.unban:SetShown(banned)
            b.ban:SetShown(not banned)
        else
            b.ban:Hide()
            local first = banned and b.unban or b.invite
            first:SetPoint("RIGHT", row, "RIGHT", -(width.forget + GAP), 0)
            b.unban:SetShown(banned)
            b.invite:SetShown(not banned)
        end
    end

    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtFormerScroll", ROW_H, createRow, fillRow)

    local stale = false
    refresh = function()
        stale = false
        local officer = GuildOS:IsOfficer()
        local data = FM:Rows()
        local counts = data.counts
        for _, b in ipairs(chips) do
            b.label:SetText(string.format("%s (%d)", b.base, counts[b.kind] or 0))
            Forms:FitPill(b)
            Forms:SetOn(b, b.kind == state.kind)
        end
        local rows = FM.Sort(FM.Filter(data.rows, state.kind, search:GetText()), state.sortBy, state.asc)
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
            status:SetText(string.format(L["%d of %d former member(s)"], #rows, counts.all)
                .. DOT .. string.format(L["checked %s"], date("%H:%M", data.at or GetServerTime())))
        end
        board:Layout()
        list:SetData(rows)
        local none = officer and #rows == 0
        empty:SetShown(none)
        if none then
            local w = UI:LaidWidth(listHolder)
            empty:SetWidth(math.max(200, math.min(420, (w > 0 and w or 420) - 4)))
            empty:Set(counts.all == 0 and L["No former members yet: Guild OS writes down who leaves from when an officer's client sees it."]
                or L["Nobody here: the filter or the search hides them."])
            empty:ClearAllPoints()
            empty:SetPoint("TOP", listHolder, "TOP", 0, -SP.SECTION)
        end
    end

    -- A ban, a note or a departure that changes: the list is read again, drawn now when on screen, else when it shows
    -- (memory audit). The ban list and the audit log each hold one hook, the Ban List and Audit Log screens' (built
    -- before this one): this screen's joins theirs.
    local function onChange()
        FM:Invalidate()
        if panel:IsVisible() then refresh() else stale = true end
    end
    FM.uiRefresh = onChange
    for _, mod in ipairs({ GuildOS.BanList, GuildOS.RosterLog }) do
        if mod then
            local prev = mod.uiRefresh
            mod.uiRefresh = function(...)
                if prev then prev(...) end
                onChange()
            end
        end
    end
    panel:HookScript("OnShow", function() if stale then refresh() end end)

    return refresh
end
