----------------------------------------------------------------------
-- Guild OS - Raiders panel
-- Officer-curated pool of the guild's raiders (level 70), independent of any
-- one raid. Officers hand-manage Roles (multi), a Gear status, and a Note per
-- player (no addon required on the listed player); the row auto-enriches with
-- iLvl + spec read-only when that player DOES run the addon.
-- Backed by GuildOS.RaiderRoster (officer-synced).
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function RR() return BRutus.RaiderRoster end

local ROLE_COL = {
    TANK   = { r = 0.42, g = 0.62, b = 0.96 },
    HEALER = { r = 0.40, g = 0.85, b = 0.50 },
    DPS    = { r = 0.92, g = 0.46, b = 0.46 },
}
local ROLE_LETTER = { TANK = "T", HEALER = "H", DPS = "D" }
local GEAR_COL = {
    ready   = { r = 0.40, g = 0.85, b = 0.50 },
    gearing = { r = 0.92, g = 0.72, b = 0.35 },
    missing = { r = 0.90, g = 0.42, b = 0.42 },
}
local function gearLabel(g)
    if g == "ready"   then return L["Ready"]   end
    if g == "gearing" then return L["Gearing"] end
    if g == "missing" then return L["Missing"] end
    return "—"
end

-- Column x-offsets inside the scroll child.
local NAME_X, ROLE_X, GEAR_X, ILVL_X, SPEC_X, NOTE_X = 6, 160, 276, 360, 414, 524
local ROW_H = 26

-- Officer note editor (shared StaticPopup; data = playerKey).
StaticPopupDialogs["GUILDOS_RAIDER_NOTE"] = {
    text = L["Officer note for %s"],
    button1 = L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 120,
    OnShow = function(self, data)
        local rec = data and RR():Get(data)
        if self.editBox then self.editBox:SetText((rec and rec.note) or ""); self.editBox:HighlightText() end
    end,
    OnAccept = function(self, data)
        if data and self.editBox then RR():SetNote(data, self.editBox:GetText()) end
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
function BRutus:CreateRolePicker(parent)
    local pick = CreateFrame("Frame", nil, parent)
    pick:SetSize(200, 24)
    local btns = {}
    local function refresh()
        local roles = BRutus:GetMyRoles()
        for _, b in ipairs(btns) do
            local rc = ROLE_COL[b.role]
            if roles[b.role] then
                b:SetBaseColor(rc.r * 0.40, rc.g * 0.40, rc.b * 0.40, 0.95)
                b.label:SetTextColor(rc.r, rc.g, rc.b)
            else
                b:SetBaseColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.6)
                b.label:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
            end
        end
    end
    for i, role in ipairs(ROLE_ORDER) do
        local b = UI:CreateButton(pick, roleName(role), 62, 22)
        b:SetPoint("LEFT", (i - 1) * 66, 0)
        b.role = role
        b:SetScript("OnClick", function()
            local roles = BRutus:GetMyRoles()
            roles[role] = (not roles[role]) and true or nil
            BRutus:SetMyRoles(roles)
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
function BRutus:CreateRaiderPanel(panel, _mainFrame)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- KPI band (same card style as the Roster tab): raid coverage at a glance.
    -- Values filled + cards positioned responsively in Refresh.
    local KPI_H = 66
    local band = CreateFrame("Frame", nil, f)
    band:SetPoint("TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", 0, 0); band:SetHeight(KPI_H)

    local KPI_DEFS = {
        { label = L["RAIDERS"], col = C.gold },
        { label = L["ONLINE"],  col = C.online },
        { label = L["TANKS"],   col = ROLE_COL.TANK },
        { label = L["HEALERS"], col = ROLE_COL.HEALER },
        { label = L["DPS"],     col = ROLE_COL.DPS },
        { label = L["READY"],   col = GEAR_COL.ready },
    }
    f.kpi = {}
    for i, k in ipairs(KPI_DEFS) do
        local card = UI:CreatePanel(band)
        card:SetFrameLevel((band:GetFrameLevel() or 1) + 1)
        card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.95)
        local val = UI:CreateText(card, "—", 20, k.col.r, k.col.g, k.col.b)
        val:SetPoint("TOPLEFT", 12, -7)
        local lbl = UI:CreateText(card, k.label, 9, C.textDim.r, C.textDim.g, C.textDim.b)
        lbl:SetPoint("BOTTOMLEFT", 12, 8)
        f.kpi[i] = { card = card, val = val }
    end
    f.KPI_H = KPI_H

    local bandLine = UI:CreateSeparator(f)
    bandLine:SetPoint("TOPLEFT", 0, -KPI_H); bandLine:SetPoint("TOPRIGHT", 0, -KPI_H)

    -- Column headers (below the band)
    local function head(text, x)
        local h = UI:CreateHeaderText(f, text, 10)
        h:SetPoint("TOPLEFT", x + 8, -(KPI_H + 8))
        return h
    end
    head(L["Raider"],  NAME_X)
    head(L["Roles"],   ROLE_X)
    head(L["Gear"],    GEAR_X)
    head(L["iLvl"],    ILVL_X)
    head(L["Spec"],    SPEC_X)
    head(L["Note"],    NOTE_X)

    local sep = UI:CreateSeparator(f)
    sep:SetPoint("TOPLEFT", 8, -(KPI_H + 24)); sep:SetPoint("TOPRIGHT", -8, -(KPI_H + 24))

    -- Scrollable list
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", 8, -(KPI_H + 28))
    holder:SetPoint("BOTTOMRIGHT", -8, 8)
    f.holder = holder
    local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRaiderScroll")
    scroll:SetAllPoints()   -- else the viewport is 0x0 and clips everything
    f.child = child

    -- Row pool (reused across refreshes so editing doesn't leak frames).
    f.rows = {}
    local function buildRow()
        local row = CreateFrame("Frame", nil, child, "BackdropTemplate")
        row:SetSize(child:GetWidth(), ROW_H)
        row:SetBackdrop({ bgFile = WHITE })

        row.nameFS = UI:CreateText(row, "", 11, 1, 1, 1)
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

        row.ilvlFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.ilvlFS:SetPoint("LEFT", ILVL_X, 0)
        row.specFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.specFS:SetPoint("LEFT", SPEC_X, 0); row.specFS:SetWidth(NOTE_X - SPEC_X - 6); row.specFS:SetJustifyH("LEFT")

        row.noteBtn = CreateFrame("Button", nil, row)
        row.noteBtn:SetPoint("LEFT", NOTE_X, 0); row.noteBtn:SetPoint("RIGHT", -6, 0); row.noteBtn:SetHeight(ROW_H)
        row.noteFS = UI:CreateText(row.noteBtn, "", 10, C.text.r, C.text.g, C.text.b)
        row.noteFS:SetPoint("LEFT", 0, 0); row.noteFS:SetPoint("RIGHT", 0, 0); row.noteFS:SetJustifyH("LEFT")
        return row
    end

    ------------------------------------------------------------------
    function f.Refresh()
        local isOfficer = BRutus:IsOfficer()
        local child2 = f.child
        child2:SetWidth(f.holder:GetWidth())

        -- Gather level-70 guild members (offline included).
        local list = {}
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if name and (level or 0) >= 70 then
                local short = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                list[#list + 1] = { name = short, key = BRutus:GetPlayerKey(short, realm), class = classFile, online = online }
            end
        end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)

        -- Aggregate counts for the KPI band (accumulated in the row loop).
        local online, rT, rH, rD, gReady = 0, 0, 0, 0, 0

        for idx, m in ipairs(list) do
            local row = f.rows[idx]
            if not row then row = buildRow(); f.rows[idx] = row end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
            row:SetSize(child2:GetWidth(), ROW_H)
            row:SetBackdropColor(0.08, 0.08, 0.10, (idx % 2 == 0) and 0.5 or 0.0)
            row:Show()

            local rec = RR():Get(m.key) or {}
            local mem = BRutus.db.members and BRutus.db.members[m.key]

            -- Tally for the KPI band. Roles are effective (officer override or
            -- the player's own self-declared roles).
            local eff = RR():EffectiveRoles(m.key)
            if m.online then online = online + 1 end
            if eff.TANK   then rT = rT + 1 end
            if eff.HEALER then rH = rH + 1 end
            if eff.DPS    then rD = rD + 1 end
            if (rec.gear or "") == "ready" then gReady = gReady + 1 end

            -- Name (class-colored; dim when offline)
            local cr, cg, cb = BRutus:GetClassColor(m.class)
            if not m.online then cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.55 end
            row.nameFS:SetText(m.name); row.nameFS:SetTextColor(cr, cg, cb)

            -- Roles (multi-toggle; shows the effective set)
            for _, b in ipairs(row.roleBtns) do
                local on = eff[b.role]
                local rc = ROLE_COL[b.role]
                if on then
                    b:SetBaseColor(rc.r * 0.40, rc.g * 0.40, rc.b * 0.40, 0.95)
                    b.label:SetTextColor(rc.r, rc.g, rc.b)
                else
                    b:SetBaseColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.6)
                    b.label:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
                end
                if isOfficer then
                    local key, role = m.key, b.role
                    b:EnableMouse(true)
                    b:SetScript("OnClick", function() RR():ToggleRole(key, role) end)
                else
                    b:EnableMouse(false)
                end
            end

            -- Gear status
            local g = rec.gear or ""
            local gc = GEAR_COL[g] or C.textDim
            row.gearBtn.label:SetText(gearLabel(g))
            row.gearBtn.label:SetTextColor(gc.r, gc.g, gc.b)
            if g ~= "" then row.gearBtn:SetBaseColor(gc.r * 0.32, gc.g * 0.32, gc.b * 0.32, 0.95)
            else row.gearBtn:SetBaseColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.6) end
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
            local spec = mem and mem.spec and mem.spec.tree
            row.specFS:SetText((spec and spec ~= "") and spec or "—")

            -- Note
            local hasNote = rec.note and rec.note ~= ""
            row.noteFS:SetText(hasNote and rec.note or (isOfficer and L["+ add note"] or "—"))
            row.noteFS:SetTextColor(hasNote and C.text.r or C.textDim.r,
                                    hasNote and C.text.g or C.textDim.g,
                                    hasNote and C.text.b or C.textDim.b)
            if isOfficer then
                local key, nm = m.key, m.name
                row.noteBtn:EnableMouse(true)
                row.noteBtn:SetScript("OnClick", function()
                    -- 4th arg → dialog.data, delivered to OnShow/OnAccept.
                    local dlg = StaticPopup_Show("GUILDOS_RAIDER_NOTE", nm, nil, key)
                    if dlg then dlg.data = key end
                end)
            else
                row.noteBtn:EnableMouse(false)
            end
        end

        -- Hide any leftover pooled rows.
        for i = #list + 1, #f.rows do f.rows[i]:Hide() end

        -- KPI band: position cards responsively (like the roster band) + fill.
        local W = f:GetWidth(); if not W or W < 200 then W = 1000 end
        local M, G, N = 12, 8, #f.kpi
        local cw = math.floor((W - M * 2 - G * (N - 1)) / N)
        for i, c in ipairs(f.kpi) do
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", M + (i - 1) * (cw + G), -8)
            c.card:SetSize(cw, f.KPI_H - 16)
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
                f.emptyFS = UI:CreateText(child2, L["No level-70 members found."], 11, C.silver.r, C.silver.g, C.silver.b)
                f.emptyFS:SetPoint("TOPLEFT", 6, -6)
            end
            f.emptyFS:Show()
        elseif f.emptyFS then
            f.emptyFS:Hide()
        end
    end

    -- Live refresh on synced edits + when the tab is shown.
    if RR() then RR().uiRefresh = function() if panel:IsShown() then f.Refresh() end end end
    panel:HookScript("OnShow", function() BRutus:SafeCall(f.Refresh) end)

    return f.Refresh
end
