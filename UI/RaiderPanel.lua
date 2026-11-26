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

local ROLE_LETTER = { TANK = "T", HEALER = "H", DPS = "D" }
local function gearLabel(g)
    if g == "ready"   then return L["Ready"]   end
    if g == "gearing" then return L["Gearing"] end
    if g == "missing" then return L["Missing"] end
    return "—"
end

-- Column x-offsets inside the scroll child.
local NAME_X, ROLE_X, GEAR_X, ILVL_X, SPEC_X, NOTE_X = 6, 150, 268, 380, 410, 540
local ROW_H = 34
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge.
local GAP = UI.GAP
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
-- The mockup's raides-raiders: the coverage as dark KPI tiles on the wood, then the pool on a parchment
-- card: a raider in their class's colour, the roles as round letters (the ones they play filled in the
-- title's red), the gear as a pill, the item level, the spec and the officer's note as a link.
----------------------------------------------------------------------
local PAD = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
local function hex(h) return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 } end
-- The paper's shades of a gear state, and a class's colour as the paper prints it (the mockup's .card .c-*).
local PAPER_GEAR = { ready = hex("2f6e33"), gearing = hex("a0560f"), missing = hex("8f1b0b") }
local function paperClass(class)
    return GuildOS.UI:InkFor("paper", "class", class)   -- the paper's class inks (UI/Helpers.lua, #449)
end

-- A role as a round letter (the mockup's T C D): cream with a tan ring at rest, the title's red filled when
-- the raider plays it. toggle:SetOn(on).
local function roleToggle(parent, letter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local disc = GuildOS.Style:Texture(b, "circle", "ARTWORK", 0)
    disc:SetAllPoints()
    local ring = GuildOS.Style:Texture(b, "ring", "ARTWORK", 1)
    ring:SetAllPoints()
    b.disc, b.ring = disc, ring
    b.label = UI:CreateText(b, letter, 11, C.paperInk.r, C.paperInk.g, C.paperInk.b)
    GuildOS:ApplyFont(b.label, 11, "button")
    b.label:SetPoint("CENTER", 0, 0)
    function b:SetOn(on)
        self.on = on and true or false
        local fill = on and C.paperTitle or C.quiet
        disc:SetVertexColor(fill.r, fill.g, fill.b, 1)
        local edge = on and C.paperTitle or C.paperEdge
        ring:SetVertexColor(edge.r, edge.g, edge.b, 1)
        local ink = on and C.quiet or C.quietInk
        self.label:SetTextColor(ink.r, ink.g, ink.b)
    end
    b:SetOn(false)
    return b
end

function GuildOS:CreateRaiderPanel(panel, _mainFrame)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- KPI band: raid coverage at a glance, as the mockup's dark tiles. Positioned in Refresh.
    local KPI_H = 66
    local band = CreateFrame("Frame", nil, f)
    band:SetPoint("TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", 0, 0); band:SetHeight(KPI_H)

    local KPI_DEFS = { L["Raiders"], L["Online"], L["Tanks"], L["Healers"], L["DPS"], L["Ready"] }
    f.kpi = {}
    for i, label in ipairs(KPI_DEFS) do
        local card = UI:CreateMetricChip(band, "—", label)
        card:SetFrameLevel((band:GetFrameLevel() or 1) + 1)
        f.kpi[i] = { card = card, val = card.value }
    end
    f.KPI_H = KPI_H

    -- The pool on a parchment card under the band.
    local card = UI:CreateCard(f, L["The guild's raiders"])
    card:SetPoint("TOPLEFT", 0, -KPI_H - 4)
    card:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    f.card = card

    -- The table's header row: the shared one, the paper's red Cinzel and a 1px rule under it (#371).
    local header = UI:CreateTableHeader(card, HEAD_H)
    header:SetPoint("TOPLEFT", PAD, -CARD_TOP + 2)
    header:SetPoint("TOPRIGHT", -PAD, -CARD_TOP + 2)
    local function head(text, x)
        local h = UI:CreateHeaderText(header, text, UI.SP.META)
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
    local holder = CreateFrame("Frame", nil, card)
    holder:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    holder:SetPoint("BOTTOMRIGHT", -PAD + UI.SCROLL_GUTTER - 4, 10)
    f.holder = holder
    local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRaiderScroll")
    scroll:SetPoint("TOPLEFT", 0, 0)   -- else the viewport is 0x0 and clips everything
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:BindScrollChildWidth(scroll, child)
    f.child = child

    -- Row pool (reused across refreshes so editing doesn't leak frames).
    f.rows = {}
    local function buildRow()
        local row = CreateFrame("Frame", nil, child)
        row:SetHeight(ROW_H)
        local rule = row:CreateTexture(nil, "BACKGROUND")
        rule:SetTexture(WHITE)
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
        rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)

        row.nameFS = UI:CreateText(row, "", 12, C.paperInk.r, C.paperInk.g, C.paperInk.b)
        GuildOS:ApplyFont(row.nameFS, 12, "button")
        row.nameFS:SetPoint("LEFT", NAME_X, 0); row.nameFS:SetWidth(ROLE_X - NAME_X - 6); row.nameFS:SetJustifyH("LEFT")

        row.roleBtns = {}
        for ri, role in ipairs(RR().ROLES) do
            local b = roleToggle(row, ROLE_LETTER[role])
            b:SetPoint("LEFT", ROLE_X + (ri - 1) * 26, 0)
            b.role = role
            row.roleBtns[ri] = b
        end

        row.gearBtn = UI:SetButtonVariant(UI:CreateButton(row, "", 74, 20), "chip")
        row.gearBtn:SetPoint("LEFT", GEAR_X, 0)

        row.ilvlFS = UI:CreateText(row, "", 12, C.paperInk.r, C.paperInk.g, C.paperInk.b)
        row.ilvlFS:SetPoint("RIGHT", row, "LEFT", SPEC_X - 14, 0); row.ilvlFS:SetJustifyH("RIGHT")
        row.specFS = UI:CreateText(row, "", 12, C.paperInk.r, C.paperInk.g, C.paperInk.b)
        row.specFS:SetPoint("LEFT", SPEC_X, 0); row.specFS:SetWidth(NOTE_X - SPEC_X - 6); row.specFS:SetJustifyH("LEFT")

        -- The note as the paper's link: underlined, the officer clicks it to write one.
        row.noteBtn = CreateFrame("Button", nil, row)
        row.noteBtn:SetPoint("LEFT", NOTE_X, 0); row.noteBtn:SetPoint("RIGHT", -6, 0); row.noteBtn:SetHeight(ROW_H)
        row.noteFS = UI:CreateText(row.noteBtn, "", 12, C.paperLink.r, C.paperLink.g, C.paperLink.b)
        row.noteFS:SetPoint("LEFT", 0, 0); row.noteFS:SetJustifyH("LEFT")
        if row.noteFS.SetWordWrap then row.noteFS:SetWordWrap(false) end
        row.noteLine = row.noteBtn:CreateTexture(nil, "ARTWORK")
        row.noteLine:SetTexture(WHITE)
        row.noteLine:SetHeight(1)
        row.noteLine:SetPoint("TOPLEFT", row.noteFS, "BOTTOMLEFT", 0, -1)
        row.noteLine:SetPoint("TOPRIGHT", row.noteFS, "BOTTOMRIGHT", 0, -1)
        row.noteLine:SetVertexColor(C.paperLink.r, C.paperLink.g, C.paperLink.b, 1)
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

            -- Name (the class's colour on the paper; faded when offline)
            local cr, cg, cb = paperClass(m.class)
            row.nameFS:SetText(m.name); row.nameFS:SetTextColor(cr, cg, cb, m.online and 1 or 0.6)
            row.nameFS:SetAlpha(m.online and 1 or 0.6)

            -- Roles (multi-toggle; shows the effective set).
            for _, b in ipairs(row.roleBtns) do
                b:SetOn(eff[b.role])
                if isOfficer then
                    local key, role = m.key, b.role
                    b:EnableMouse(true)
                    b:SetScript("OnClick", function() RR():ToggleRole(key, role) end)
                else
                    b:EnableMouse(false)
                end
            end

            -- Gear status: a pill, its label in the state's colour.
            local g = rec.gear or ""
            row.gearBtn.label:SetText(gearLabel(g))
            statusLabel(row.gearBtn, PAPER_GEAR[g] or C.paperSoft)
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
            local nc = (hasNote or isOfficer) and C.paperLink or C.paperSoft
            row.noteFS:SetTextColor(nc.r, nc.g, nc.b)
            row.noteLine:SetShown(isOfficer)
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

        -- KPI band: tiles across the width, GAP apart, ending GAP short of the right (#371).
        local W = f:GetWidth(); if not W or W < 200 then W = 1000 end
        local G, N = GAP, #f.kpi
        local cw = math.floor((W - GAP - G * (N - 1)) / N)
        for i, c in ipairs(f.kpi) do
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", (i - 1) * (cw + G), -GAP)
            c.card:SetSize(cw, f.KPI_H - GAP - 6)
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
                f.emptyFS = UI:CreateText(child2, string.format(L["No level-%d members found."], GuildOS.Client.maxLevel), 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
                f.emptyFS:SetPoint("TOPLEFT", 6, -8)
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
