----------------------------------------------------------------------
-- Guild OS - Raiders panel
-- Officer-curated pool of the guild's raiders (at the level cap), independent of any
-- one raid. Officers hand-manage Roles (multi), a Gear status, and a Note per
-- player (no addon required on the listed player); the row auto-enriches with
-- iLvl + spec read-only when that player DOES run the addon.
-- Backed by GuildOS.RaiderRoster (officer-synced).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function RR() return GuildOS.RaiderRoster end

local ROLE_COL = {
    TANK   = { r = 0.42, g = 0.62, b = 0.96 },
    HEALER = { r = 0.40, g = 0.85, b = 0.50 },
    DPS    = { r = 0.92, g = 0.46, b = 0.46 },
}
local ROLE_LETTER = { TANK = "T", HEALER = "H", DPS = "D" }
-- A raider's gear in the palette's status colours (#371).
local GEAR_COL = { ready = C.ok, gearing = C.warn, missing = C.danger }
local function gearLabel(g)
    if g == "ready"   then return L["Ready"]   end
    if g == "gearing" then return L["Gearing"] end
    if g == "missing" then return L["Missing"] end
    return "—"
end

-- Column x-offsets inside the scroll child.
local NAME_X, ROLE_X, GEAR_X, ILVL_X, SPEC_X, NOTE_X = 6, 160, 276, 360, 414, 524
local ROW_H = 26
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll
-- frame's right edge sits SCROLL_R from the panel's.
local GAP = UI.GAP
local SCROLL_R = UI.SCROLL_GUTTER - UI.GAP
local HEAD_H = 22   -- the table's header row (UI:CreateTableHeader)

-- A button's label in a status colour that survives the hover: the resting colour, repainted.
local function statusLabel(btn, col)
    btn.baseLabelColor = { col.r, col.g, col.b }
    UI:SetSelected(btn, false)
end

-- Officer note editor (data = playerKey).
GuildOS.Dialogs["GUILDOS_RAIDER_NOTE"] = {
    text = L["Officer note for %s"],
    button1 = L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 120,
    -- The box through Compat: WoW: Forever's popup has no `editBox` (issue #49).
    OnShow = function(self, data)
        local rec = data and RR():Get(data)
        local box = GuildOS.Compat.PopupEditBox(self)
        if box then box:SetText((rec and rec.note) or ""); box:HighlightText() end
    end,
    OnAccept = function(self, data)
        local box = GuildOS.Compat.PopupEditBox(self)
        if data and box then RR():SetNote(data, box:GetText()) end
    end,
    EditBoxOnEnterPressed = function(editBox)
        local dlg = editBox:GetParent()
        if dlg.data then RR():SetNote(dlg.data, editBox:GetText()) end
        dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

----------------------------------------------------------------------
-- Reusable self-service role picker (Settings "My Profile" + onboarding).
-- Reads/writes the player's OWN preferred roles; the change syncs to the
-- guild via their member data, so officers don't have to set it.
----------------------------------------------------------------------
local ROLE_ORDER = { "TANK", "HEALER", "DPS" }
local function roleName(r)
    if r == "TANK"   then return L["Tank"]   end
    if r == "HEALER" then return L["Healer"] end
    return L["DPS"]
end
function GuildOS:CreateRolePicker(parent)
    local pick = CreateFrame("Frame", nil, parent)
    pick:SetSize(200, 24)
    local btns = {}
    -- A role the player plays: the shared selection mark, not a fill tinted in the role's colour (#371).
    local function refresh()
        local roles = GuildOS:GetMyRoles()
        for _, b in ipairs(btns) do UI:SetSelected(b, roles[b.role]) end
    end
    local x = 0
    for i, role in ipairs(ROLE_ORDER) do
        local b = UI:CreateButton(pick, roleName(role), 62, 22)
        b:SetPoint("LEFT", x, 0)
        x = x + b:GetWidth() + 4  -- a role its label grew pushes the next one (issue #28)
        b.role = role
        b:SetScript("OnClick", function()
            local roles = GuildOS:GetMyRoles()
            roles[role] = (not roles[role]) and true or nil
            GuildOS:SetMyRoles(roles)
            refresh()
        end)
        btns[i] = b
    end
    refresh()
    pick.refresh = refresh
    return pick
end

----------------------------------------------------------------------
-- Build the raiders panel; return its refresh fn.
----------------------------------------------------------------------
function GuildOS:CreateRaiderPanel(panel, _mainFrame)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- KPI band (same card style as the Roster tab): raid coverage at a glance.
    -- Values filled + cards positioned responsively in Refresh.
    local KPI_H = 66
    local band = CreateFrame("Frame", nil, f)
    band:SetPoint("TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", 0, 0); band:SetHeight(KPI_H)

    -- The count of raiders in the text colour; the others keep their role's or status's (#371: gold).
    local KPI_DEFS = {
        { label = L["RAIDERS"], col = C.text },
        { label = L["ONLINE"],  col = C.ok },
        { label = L["TANKS"],   col = ROLE_COL.TANK },
        { label = L["HEALERS"], col = ROLE_COL.HEALER },
        { label = L["DPS"],     col = ROLE_COL.DPS },
        { label = L["READY"],   col = GEAR_COL.ready },
    }
    f.kpi = {}
    for i, k in ipairs(KPI_DEFS) do
        local card = UI:CreatePanel(band)
        card:SetFrameLevel((band:GetFrameLevel() or 1) + 1)
        local val = UI:CreateText(card, "—", 20, k.col.r, k.col.g, k.col.b)
        val:SetPoint("TOPLEFT", 12, -7)
        local lbl = UI:CreateText(card, k.label, 10, C.label.r, C.label.g, C.label.b)
        lbl:SetPoint("BOTTOMLEFT", 12, 8)
        f.kpi[i] = { card = card, val = val }
    end
    f.KPI_H = KPI_H

    -- The table's header row, under the band: the shared one, no fill and a 1px rule under it (#371).
    local header = UI:CreateTableHeader(f, HEAD_H)
    header:SetPoint("TOPLEFT", 0, -KPI_H)
    header:SetPoint("TOPRIGHT", -GAP, -KPI_H)
    local function head(text, x)
        local h = UI:CreateHeaderText(header, text, 10)
        h:SetPoint("LEFT", x, 0)
        return h
    end
    head(L["Raider"],  NAME_X)
    head(L["Roles"],   ROLE_X)
    head(L["Gear"],    GEAR_X)
    head(L["iLvl"],    ILVL_X)
    head(L["Spec"],    SPEC_X)
    head(L["Note"],    NOTE_X)

    -- Scrollable list: its child keeps the frame's width less the gutter, so the rows end where the
    -- header does and nothing runs under the bar (#371).
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", 0, -(KPI_H + HEAD_H))
    holder:SetPoint("BOTTOMRIGHT", 0, GAP)
    f.holder = holder
    local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRaiderScroll")
    scroll:SetPoint("TOPLEFT", 0, 0)   -- else the viewport is 0x0 and clips everything
    scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(scroll, child)
    f.child = child

    -- Row pool (reused across refreshes so editing doesn't leak frames).
    f.rows = {}
    local function buildRow()
        local row = CreateFrame("Frame", nil, child, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = WHITE })

        row.nameFS = UI:CreateText(row, "", 12, C.text.r, C.text.g, C.text.b)
        row.nameFS:SetPoint("LEFT", NAME_X, 0); row.nameFS:SetWidth(ROLE_X - NAME_X - 6); row.nameFS:SetJustifyH("LEFT")

        row.roleBtns = {}
        for ri, role in ipairs(RR().ROLES) do
            local b = UI:CreateButton(row, ROLE_LETTER[role], 24, 18)
            b:SetPoint("LEFT", ROLE_X + (ri - 1) * 28, 0)
            b.role = role
            row.roleBtns[ri] = b
        end

        row.gearBtn = UI:CreateButton(row, "", 74, 18)
        row.gearBtn:SetPoint("LEFT", GEAR_X, 0)

        row.ilvlFS = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.ilvlFS:SetPoint("LEFT", ILVL_X, 0)
        row.specFS = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.specFS:SetPoint("LEFT", SPEC_X, 0); row.specFS:SetWidth(NOTE_X - SPEC_X - 6); row.specFS:SetJustifyH("LEFT")

        row.noteBtn = CreateFrame("Button", nil, row)
        row.noteBtn:SetPoint("LEFT", NOTE_X, 0); row.noteBtn:SetPoint("RIGHT", -6, 0); row.noteBtn:SetHeight(ROW_H)
        row.noteFS = UI:CreateText(row.noteBtn, "", 11, C.text.r, C.text.g, C.text.b)
        row.noteFS:SetPoint("LEFT", 0, 0); row.noteFS:SetPoint("RIGHT", 0, 0); row.noteFS:SetJustifyH("LEFT")
        return row
    end

    ------------------------------------------------------------------
    function f.Refresh()
        local isOfficer = GuildOS:IsOfficer()
        local child2 = f.child

        -- Gather the guild's members at the level cap (offline included; issue #53).
        local list = {}
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if name and (level or 0) >= GuildOS.Client.maxLevel then
                local short = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                list[#list + 1] = { name = short, key = GuildOS:GetPlayerKey(short, realm), class = classFile, online = online }
            end
        end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)

        -- Aggregate counts for the KPI band (accumulated in the row loop).
        local online, rT, rH, rD, gReady = 0, 0, 0, 0, 0

        for idx, m in ipairs(list) do
            local row = f.rows[idx]
            if not row then row = buildRow(); f.rows[idx] = row end
            -- Hung by both top corners: a width read at refresh time is 0 on a hidden tab (#371).
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(idx - 1) * ROW_H)
            row:SetBackdropColor(C.well.r, C.well.g, C.well.b, (idx % 2 == 0) and 0.5 or 0.0)
            row:Show()

            local rec = RR():Get(m.key) or {}
            local mem = GuildOS.db.members and GuildOS.db.members[m.key]

            -- Tally for the KPI band. Roles are effective (officer override or
            -- the player's own self-declared roles).
            local eff = RR():EffectiveRoles(m.key)
            if m.online then online = online + 1 end
            if eff.TANK   then rT = rT + 1 end
            if eff.HEALER then rH = rH + 1 end
            if eff.DPS    then rD = rD + 1 end
            if (rec.gear or "") == "ready" then gReady = gReady + 1 end

            -- Name (class-colored; dim when offline)
            local cr, cg, cb = GuildOS:GetClassColor(m.class)
            if not m.online then cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.55 end
            row.nameFS:SetText(m.name); row.nameFS:SetTextColor(cr, cg, cb)

            -- Roles (multi-toggle; shows the effective set): the shared selection mark (#371).
            for _, b in ipairs(row.roleBtns) do
                UI:SetSelected(b, eff[b.role])
                if isOfficer then
                    local key, role = m.key, b.role
                    b:EnableMouse(true)
                    b:SetScript("OnClick", function() RR():ToggleRole(key, role) end)
                else
                    b:EnableMouse(false)
                end
            end

            -- Gear status
            -- Gear status: its status colour on the label, no tinted fill (#371).
            local g = rec.gear or ""
            row.gearBtn.label:SetText(gearLabel(g))
            statusLabel(row.gearBtn, GEAR_COL[g] or C.label)
            if isOfficer then
                local key = m.key
                row.gearBtn:EnableMouse(true)
                row.gearBtn:SetScript("OnClick", function() RR():CycleGear(key) end)
            else
                row.gearBtn:EnableMouse(false)
            end

            -- Synced enrichment (read-only)
            local ilvl = mem and mem.avgIlvl or 0
            row.ilvlFS:SetText(ilvl > 0 and tostring(ilvl) or "—")
            local spec = mem and GuildOS.SpecChecker and GuildOS.SpecChecker:SpecName(mem.spec)
            row.specFS:SetText((spec and spec ~= "") and spec or "—")

            -- Note
            local note = isOfficer and rec.note or ""
            local hasNote = note ~= ""
            row.noteFS:SetText(hasNote and note or (isOfficer and L["+ add note"] or "—"))
            row.noteFS:SetTextColor(hasNote and C.text.r or C.label.r,
                                    hasNote and C.text.g or C.label.g,
                                    hasNote and C.text.b or C.label.b)
            if isOfficer then
                local key, nm = m.key, m.name
                row.noteBtn:EnableMouse(true)
                row.noteBtn:SetScript("OnClick", function()
                    -- 4th arg → dialog.data, delivered to OnShow/OnAccept.
                    local dlg = GuildOS:ShowDialog("GUILDOS_RAIDER_NOTE", nm, nil, key)
                    if dlg then dlg.data = key end
                end)
            else
                row.noteBtn:EnableMouse(false)
            end
        end

        -- Hide any leftover pooled rows.
        for i = #list + 1, #f.rows do f.rows[i]:Hide() end

        -- KPI band: position cards responsively (like the roster band) + fill. Flush with the left
        -- edge, GAP under the top, ending GAP short of the right (#371).
        local W = f:GetWidth(); if not W or W < 200 then W = 1000 end
        local G, N = GAP, #f.kpi
        local cw = math.floor((W - GAP - G * (N - 1)) / N)
        for i, c in ipairs(f.kpi) do
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", (i - 1) * (cw + G), -GAP)
            c.card:SetSize(cw, f.KPI_H - GAP - 8)
        end
        f.kpi[1].val:SetText(tostring(#list))
        f.kpi[2].val:SetText(tostring(online))
        f.kpi[3].val:SetText(tostring(rT))
        f.kpi[4].val:SetText(tostring(rH))
        f.kpi[5].val:SetText(tostring(rD))
        f.kpi[6].val:SetText(tostring(gReady))

        child2:SetHeight(math.max(1, #list * ROW_H))

        if #list == 0 then
            if not f.emptyFS then
                f.emptyFS = UI:CreateText(child2, string.format(L["No level-%d members found."], GuildOS.Client.maxLevel), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                f.emptyFS:SetPoint("TOPLEFT", 6, -6)
            end
            f.emptyFS:Show()
        elseif f.emptyFS then
            f.emptyFS:Hide()
        end
    end

    -- Live refresh on synced edits + when the tab is shown.
    if RR() then RR().uiRefresh = function() if panel:IsShown() then f.Refresh() end end end
    panel:HookScript("OnShow", function() GuildOS:SafeCall(f.Refresh) end)

    return f.Refresh
end
