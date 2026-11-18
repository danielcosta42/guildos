----------------------------------------------------------------------
-- Guild OS - Raids › Cores (issue #346)
-- The guild's cores on the left: each with its size, how full it is and where it comes from (the
-- Discord, or only this game). On the right the core picked: its name, its origin and whether it is
-- the raid's; sub-tabs Roster · Requests · Rule · Config. Roster: the role meters, the members with
-- their role as a dropdown, the guests of the night (#340) and, for a Discord core, what is decided
-- there. Every change goes through CoreManager; the loot rule is the Loot window's (Rule says which
-- and opens it).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local LIST_MIN, LIST_MAX = 180, 240   -- the core list's column, by the window's width
local LIST_SHARE = 0.28
local CORE_ROW_H = 36
local GROUP_INDENT = 12   -- a group's row, under its elenco's (issue #352)
local ROW_H = 22
local METER_W = 120
-- The screen's margins (#371): flush with the left edge, GAP under the top, the content ending GAP short
-- of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll frame's right
-- edge sits SCROLL_R from its column's: its rows then end GAP short of it, the bar past them. Numbers
-- even where a test stands in for the UI.
local GAP = tonumber(UI.GAP) or 8
local SCROLL_R = (tonumber(UI.SCROLL_GUTTER) or 12) - GAP
local HEAD_ABOVE = 20   -- room over a later section title for its rule (UI:CreateSectionTitle)
local HEAD_H = 26       -- a section title's line and the space under it
local HEADER_H = 24     -- the core's name, its badges and its buttons
local SUBBAR_H = 26
local LABEL_GAP, LABEL_MIN = 12, 140   -- the Config form's label column

-- The roster's columns, by priority: the member and the role stay.
local MEMBER_COLS = {
    { key = "name",   min = 120, weight = 3, priority = 9, required = true },
    { key = "role",   min = 104, weight = 1, priority = 8, required = true },
    { key = "place",  min = 64,  weight = 1, priority = 5 },
    { key = "origin", min = 64,  weight = 1, priority = 4 },
    { key = "pres",   min = 44,  weight = 0, priority = 6 },
    { key = "acts",   min = 120, weight = 0, priority = 7 },
}

----------------------------------------------------------------------
-- Shared widget builders
----------------------------------------------------------------------
-- A box: the shared field (#371), with its hint shown while it is empty.
local function MakeInput(parent, w, numeric, placeholder)
    return UI:CreateInput(parent, w, 22, { numeric = numeric and true or nil, max = numeric and 5 or nil,
        placeholder = placeholder })
end

-- A line of text: textSoft unless a colour is given.
local function MakeLabel(parent, text, size, r, g, b)
    return UI:CreateText(parent, text, size or 11, r or C.textSoft.r, g or C.textSoft.g, b or C.textSoft.b)
end

-- A section title (#371): the shared one, at the content's left edge. The screen's first (y = 0) has no
-- rule; a later one leaves HEAD_ABOVE over itself for it. Returns the y under it (y runs negative here).
local function MakeSectionHeader(parent, text, y)
    local first = y >= 0
    if not first then y = y - HEAD_ABOVE end
    local lbl = UI:CreateSectionTitle(parent, text, first)
    lbl:SetPoint("TOPLEFT", 0, y)
    return y - HEAD_H
end

-- A core's origin, as the list and the header say it.
local function originOf(CM, name)
    if CM:IsFromDiscord(name) then return L["from Discord"] end
    return L["only in this game"]
end

----------------------------------------------------------------------
-- Main builder
----------------------------------------------------------------------
function GuildOS:CreateCoresPanel(panel)
    local listW = LIST_MAX

    ----------------------------------------------------------------
    -- Left column: the guild's cores
    ----------------------------------------------------------------
    local leftCol = CreateFrame("Frame", nil, panel)
    leftCol:SetPoint("TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(listW)

    -- The list's title: the screen's first section, GAP under its top (#371).
    local listTitle = UI:CreateSectionTitle(leftCol, L["GUILD CORES"], true)
    listTitle:SetPoint("TOPLEFT", 0, -GAP)

    local listDiv = leftCol:CreateTexture(nil, "ARTWORK")
    listDiv:SetTexture(WHITE)
    GuildOS.UI:Hairline(listDiv, "Width")
    listDiv:SetPoint("TOPRIGHT", 0, 0)
    listDiv:SetPoint("BOTTOMRIGHT", 0, 0)
    listDiv:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)

    local listScroll, listContent = UI:CreateScrollFrame(leftCol, "GuildOSCoreListScroll")
    listScroll:SetPoint("TOPLEFT", 0, -(GAP + HEAD_H))
    listScroll:SetPoint("BOTTOMRIGHT", 0, 92)   -- its bar inside the column, clear of the divider (#371)
    UI:BindScrollChildWidth(listScroll, listContent)

    -- At the foot: how cores are born. A guild linked to the site creates them on Discord (#339): a
    -- sentence says so, and when the site last sent; after 30 days with no package from it, a button
    -- creates in game again. An unlinked guild names one and creates it here.
    local linkNote = MakeLabel(leftCol, L["This guild is linked to the site. New cores are born on Discord, with /core criar."], 11)
    linkNote:SetPoint("BOTTOMLEFT", 0, 52)
    linkNote:SetPoint("RIGHT", leftCol, "RIGHT", -GAP, 0)
    linkNote:SetJustifyH("LEFT")
    if linkNote.SetWordWrap then linkNote:SetWordWrap(true) end
    local seenNote = MakeLabel(leftCol, "", 11, C.label.r, C.label.g, C.label.b)
    seenNote:SetPoint("BOTTOMLEFT", 0, 36)
    local newInput = MakeInput(leftCol, listW - 72 - GAP, false, L["Core name"])
    newInput:SetPoint("BOTTOMLEFT", 0, 6)
    local createBtn = UI:CreateButton(leftCol, L["Create"], 60, 22)
    createBtn:SetPoint("LEFT", newInput, "RIGHT", 4, 0)
    local againBtn = UI:CreateButton(leftCol, L["Create cores in game again"], listW - GAP, 22)
    againBtn:SetPoint("BOTTOMLEFT", 0, 6)
    local function showIf(w, on)
        if on then w:Show() else w:Hide() end
    end
    local function ShowCreate()
        local CM = GuildOS.CoreManager
        local linked = CM and CM:IsLinked()
        showIf(newInput, not linked)
        showIf(createBtn, not linked)
        showIf(linkNote, linked)
        showIf(seenNote, linked)
        local seen = linked and CM:LinkSeenAt()
        seenNote:SetText(seen and string.format(L["Received from the site %s"], GuildOS:TimeAgo(seen)) or "")
        showIf(againBtn, linked and CM:IsLinkQuiet() and GuildOS:IsOfficer())
    end

    ----------------------------------------------------------------
    -- Right column: the core picked
    ----------------------------------------------------------------
    -- The core picked: its header GAP under the top, the sub-tab bar under it, and the sub-tab's
    -- content flush with that bar's left edge, GAP under it, ending GAP short of the right (#371).
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", GAP, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    local statusLbl = MakeLabel(right, "", 11)
    statusLbl:SetPoint("TOPRIGHT", -GAP, -GAP)
    local function SetStatus(msg, color)
        statusLbl:SetText(msg or "")
        local col = color or C.textSoft
        statusLbl:SetTextColor(col.r, col.g, col.b)
    end

    local header = CreateFrame("Frame", nil, right)
    header:SetPoint("TOPLEFT", 0, -GAP)
    header:SetPoint("TOPRIGHT", -GAP, -GAP)
    header:SetHeight(HEADER_H)
    local barTop = GAP + HEADER_H + 4
    local subBar = CreateFrame("Frame", nil, right)
    subBar:SetPoint("TOPLEFT", 0, -barTop)
    subBar:SetPoint("TOPRIGHT", 0, -barTop)
    subBar:SetHeight(SUBBAR_H)
    UI:StyleSubTabBar(subBar)

    local rightScroll, rightContent = UI:CreateScrollFrame(right, "GuildOSCoreSettingsScroll")
    rightScroll:SetPoint("TOPLEFT", 0, -(barTop + SUBBAR_H + GAP))
    rightScroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(rightScroll, rightContent)

    -- Placeholder shown when no core is selected
    local noCoreLbl = MakeLabel(rightContent, L["Select or create a core on the left."],
        12, C.label.r, C.label.g, C.label.b)
    noCoreLbl:SetPoint("TOPLEFT", 0, 0)

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local selectedCore   = nil
    local activeRightTab = "roster"   -- "roster" | "signups" | "rule" | "config"
    local coreRows       = {}
    local cfgWidgets     = {}   -- every widget a drawing made; rebuilt per selection

    -- Add-member form state (persists across BuildSettings rebuilds)
    local addGMName     = nil   -- selected guild member name
    local addGMKey      = nil   -- and their key, with their own realm (connected realms on retail)
    local addGMClass    = nil   -- classFile e.g. "HUNTER"
    local addGMRole     = nil   -- nil = auto-inferred from class
    local lastCoreBuilt = nil   -- detect core switch so we reset the selection

    -- The class's role, or on retail the role of the member's scanned spec (issue #184).
    local function InferRole(class, key)
        return GuildOS.CoreManager and GuildOS.CoreManager:DefaultRole(class, key) or "rdps"
    end

    local function GetActiveName()
        return GuildOS.CoreManager and GuildOS.CoreManager:GetActiveName() or ""
    end

    -- The four roles, as the dropdowns offer them.
    local function roleOptions()
        local CM, opts = GuildOS.CoreManager, {}
        for _, role in ipairs({ "tank", "healer", "mdps", "rdps" }) do
            opts[#opts + 1] = { value = role, text = CM.ROLE_LABELS[role] or role, color = CM.ROLE_COLORS[role] }
        end
        return opts
    end

    local function ClearSettings()
        for _, w in ipairs(cfgWidgets) do
            if w.Hide then w:Hide() end
        end
        cfgWidgets = {}
        -- Section titles and labels are drawn straight on the content and the header: hide them too.
        for _, region in pairs({ rightContent:GetRegions() }) do region:Hide() end
        for _, region in pairs({ header:GetRegions() }) do region:Hide() end
        noCoreLbl:Hide()
    end

    local BuildSettings, RebuildList

    local function BuildHeader(coreName, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local title = UI:CreateTitle(header, coreName, 15)
        title:SetPoint("LEFT", 0, 0)
        local origin = track(UI:CreateBadge(header, originOf(CM, coreName)))
        origin:SetPoint("LEFT", title, "RIGHT", 10, 0)
        local x = origin
        -- A group says its elenco, and where its points go (issue #352).
        local parent = CM:ParentOf(coreName)
        if parent then
            local text = CM:UsesParentPool(coreName) and string.format(L["group of %s \194\183 points in its pool"], parent)
                or string.format(L["group of %s"], parent)
            local grp = track(UI:CreateBadge(header, text))
            grp:SetPoint("LEFT", x, "RIGHT", 6, 0)
            x = grp
        end
        if coreName == GetActiveName() then
            local active = track(UI:CreateBadge(header, L["active in the raid"]))
            active:SetPoint("LEFT", x, "RIGHT", 6, 0)
            x = active
        elseif GuildOS.RaidTracker then
            local setActiveBtn = track(UI:CreateButton(header, L["Set Active"], 90, 20))
            setActiveBtn:SetPoint("LEFT", x, "RIGHT", 8, 0)
            setActiveBtn:SetScript("OnClick", function()
                GuildOS.RaidTracker:PickCore(coreName)
                SetStatus(string.format(L["Active core set to: %s"], coreName), C.online)
                RebuildList()
                BuildSettings(coreName)
            end)
            x = setActiveBtn
        end
        -- A core of the Discord keeps the Discord's name and is closed there (#135, #293): no rename,
        -- no delete. One only this game has can be renamed and deleted.
        if not fromDiscord and GuildOS:IsOfficer() then
            local renameInput = track(MakeInput(header, 120, false, L["New name"]))
            renameInput:SetPoint("LEFT", x, "RIGHT", 12, 0)
            local renameBtn = track(UI:CreateButton(header, L["Rename"], 70, 20))
            renameBtn:SetPoint("LEFT", renameInput, "RIGHT", 4, 0)
            renameBtn:SetScript("OnClick", function()
                local newName = strtrim(renameInput:GetText() or "")
                if newName == "" then
                    SetStatus(L["Enter a new name first."], C.red)
                    return
                end
                local ok, err = CM:Rename(coreName, newName)
                if not ok then
                    SetStatus(err, C.red)
                else
                    SetStatus(string.format(L["Renamed to: %s"], newName), C.online)
                end
            end)
            local deleteBtn = track(UI:CreateButton(header, L["Delete"], 70, 20))
            deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 4, 0)
            UI:SetButtonVariant(deleteBtn, "danger")
            deleteBtn:SetScript("OnClick", function()
                local ok, err = CM:Delete(coreName)
                if not ok then SetStatus(err or L["Core not found."], C.red); return end
                selectedCore = nil
                SetStatus(string.format(L["Core \"%s\" deleted."], coreName), C.red)
            end)
        end
    end

    local function BuildTabs(coreName, track)
        local CM = GuildOS.CoreManager
        local isOfficer = GuildOS:IsOfficer()
        if activeRightTab == "config" and not isOfficer then activeRightTab = "roster" end
        local nSignups = 0
        for _ in pairs(CM:GetSignups(coreName) or {}) do nSignups = nSignups + 1 end
        local TABS = {
            { key = "roster",  label = L["Roster"] },
            { key = "signups", label = nSignups > 0 and string.format(L["Requests (%d)"], nSignups) or L["Requests"] },
            { key = "rule",    label = L["Rule"] },
        }
        if isOfficer then TABS[#TABS + 1] = { key = "config", label = L["Config"] } end
        local prev
        for _, t in ipairs(TABS) do
            local tb = track(UI:CreateTab(subBar, t.label, 90, true))
            if prev then tb:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tb:SetPoint("LEFT", 4, 0) end
            tb:SetActive(t.key == activeRightTab)
            tb.key = t.key
            tb:SetScript("OnClick", function()
                activeRightTab = t.key
                BuildSettings(coreName)
            end)
            prev = tb
        end
    end

    ----------------------------------------------------------------
    -- The core's roster: the meters, the members, the guests
    ----------------------------------------------------------------
    local function BuildRoster(coreName, y, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local isRL = CM:IsRaidLeader()
        local comp = CM:GetComposition(coreName)
        local members = CM:GetMembers(coreName)
        local W = math.max(200, rightContent:GetWidth() or 0)

        -- One meter a role: who it has against what the format asks.
        local roles = comp.roleCounts
        local T = CM:RaidTargets(CM:GetRaidSize(coreName))
        local METERS = {
            { key = "tank", label = L["Tanks"] }, { key = "healer", label = L["Healers"] },
            { key = "mdps", label = L["Melee"] }, { key = "rdps", label = L["Ranged"] },
        }
        local perRow = W >= 520 and 2 or 1
        local colW = math.floor(W / perRow)
        for i, m in ipairs(METERS) do
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local mx, my = col * colW, y - row * 22
            local have, want = roles[m.key] or 0, T[m.key] or 0
            local lbl = MakeLabel(rightContent, m.label, 12, C.text.r, C.text.g, C.text.b)
            lbl:SetPoint("TOPLEFT", mx, my - 4)
            local bar = track(UI:CreateProgressBar(rightContent, METER_W, 8))
            bar:SetPoint("TOPLEFT", mx + 90, my - 7)
            bar:SetProgress(want > 0 and have / want or 1)
            -- A role short of what the format asks is a warning: gold is not a status (#371).
            local full = have >= want and C.ok or C.warn
            local count = MakeLabel(rightContent, string.format(L["%d of %d"], have, want), 11, full.r, full.g, full.b)
            count:SetPoint("TOPLEFT", mx + 96 + METER_W, my - 4)
        end
        y = y - math.ceil(#METERS / perRow) * 22 - 6
        local summary = string.format(L["%d of %d members"], comp.total, CM:GetRaidSize(coreName))
        if (comp.bench or 0) > 0 then summary = summary .. "  \194\183  " .. string.format(L["%d in reserve"], comp.bench) end
        local open = CM:OpenSlots(coreName)
        if open.total + open.tank + open.healer + open.mdps + open.rdps > 0 then   -- a role short is a slot, full or not
            summary = summary .. "  \194\183  " .. string.format(L["Open: %d  (T %d · H %d · M %d · R %d)"],
                open.total, open.tank, open.healer, open.mdps, open.rdps)
        end
        local sumLbl = MakeLabel(rightContent, summary, 11)
        sumLbl:SetPoint("TOPLEFT", 0, y)
        y = y - 18

        -- Raid buff coverage, where the game has a list of them (none on Forever, issue #92)
        if #comp.buffStatus > 0 then
            y = MakeSectionHeader(rightContent, L["Raid Buffs"], y)
            local bfCol = 0
            for _, bs in ipairs(comp.buffStatus) do
                local col_c = bs.covered and C.online or C.red
                local bfLbl = MakeLabel(rightContent, (bs.covered and "+ " or "- ") .. bs.name, 11, col_c.r, col_c.g, col_c.b)
                bfLbl:SetPoint("TOPLEFT", bfCol * 180, y)
                bfCol = bfCol + 1
                if bfCol >= math.max(1, math.floor(W / 180)) then bfCol = 0; y = y - 15 end
            end
            if bfCol > 0 then y = y - 15 end
            y = y - 6
        end

        -- The members: titulars first, then the reserves (issue #212).
        local sortedMbrs = {}
        for k, m in pairs(members) do sortedMbrs[#sortedMbrs + 1] = { key = k, m = m } end
        table.sort(sortedMbrs, function(a, b)
            local ab, bb = a.m.status == "bench", b.m.status == "bench"
            if ab ~= bb then return bb end
            if (a.m.role or "") ~= (b.m.role or "") then return (a.m.role or "") < (b.m.role or "") end
            return (a.m.name or "") < (b.m.name or "")
        end)
        y = MakeSectionHeader(rightContent, string.format(L["Roster (%d)"], #sortedMbrs), y)

        local spec = {}
        for _, col in ipairs(MEMBER_COLS) do
            if not (col.key == "acts" and (fromDiscord or not isRL)) then spec[#spec + 1] = col end
        end
        -- The scroll child already stops short of the scroll bar (BindScrollChildWidth, #371).
        local layout = UI:ResolveColumns(spec, W, 6)
        panel.memberLayout = layout
        local function at(key) return layout.byKey[key] end
        local TITLES = { name = L["MEMBER"], role = L["ROLE"], place = L["PLACE"], origin = L["ORIGIN"], pres = L["PRES."], acts = "" }
        -- The table's header row: the shared one, no fill and a 1px rule under it (#371).
        local head = track(UI:CreateTableHeader(rightContent))
        head:SetPoint("TOPLEFT", 0, y)
        head:SetPoint("TOPRIGHT", 0, y)
        for _, col in ipairs(spec) do
            if at(col.key).shown and TITLES[col.key] ~= "" then
                local h = UI:CreateHeaderText(head, TITLES[col.key], 10)
                h:SetPoint("LEFT", at(col.key).x + 4, 0)
            end
        end
        y = y - 22

        local function cell(key, text, r, g, b)
            local c = at(key)
            if not (c and c.shown) then return nil end
            local fs = MakeLabel(rightContent, text, 11, r, g, b)
            fs:SetPoint("TOPLEFT", c.x + 4, y - 4)
            fs:SetWidth(math.max(1, c.w - 6))
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            return fs
        end

        if #sortedMbrs == 0 then
            local emL = MakeLabel(rightContent, L["No members yet."], 11, C.label.r, C.label.g, C.label.b)
            emL:SetPoint("TOPLEFT", 4, y - 4)
            y = y - 20
        end
        for i, entry in ipairs(sortedMbrs) do
            local m, mk = entry.m, entry.key
            -- The row's band hangs by both top corners: a width read at build time is 0 on a hidden tab.
            local bg = rightContent:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(WHITE)
            bg:SetPoint("TOPLEFT", 0, y)
            bg:SetPoint("TOPRIGHT", 0, y)
            bg:SetHeight(ROW_H)
            local band = (i % 2 == 1) and C.row1 or C.row2
            bg:SetVertexColor(band.r, band.g, band.b, band.a or 0.4)
            local cr, cg, cb = GuildOS:GetClassColor(m.class or "WARRIOR")
            local nameFS = cell("name", m.name or mk, cr, cg, cb)
            if nameFS and m.status == "bench" then nameFS:SetAlpha(0.6) end
            -- The role: a dropdown for whoever may change it (a Discord core's people too, #135).
            local rc = at("role")
            if isRL and rc.shown then
                local dd = track(UI:CreateDropdown(rightContent, math.max(90, rc.w - 6), 20))
                dd:SetPoint("TOPLEFT", rc.x, y - 1)
                dd:SetOptions(roleOptions())
                dd:SetValue(m.role or "rdps")
                dd.memberKey = mk
                dd.onSelect = function(_, role)
                    CM:SetMemberRole(mk, role, coreName)
                    BuildSettings(coreName)
                end
            else
                local col = CM.ROLE_COLORS[m.role or "rdps"] or C.text
                cell("role", CM.ROLE_LABELS[m.role or "rdps"] or "?", col.r, col.g, col.b)
            end
            cell("place", m.status == "bench" and L["Reserve"] or L["Starter"], C.textSoft.r, C.textSoft.g, C.textSoft.b)
            cell("origin", (fromDiscord and m.src == "discord") and L["Discord"] or L["in game"], C.labelDim.r, C.labelDim.g, C.labelDim.b)
            local pres = CM:MemberPresence(mk, coreName)
            local pc = (not pres and C.labelDim) or (pres >= 80 and C.ok) or (pres >= 60 and C.warn) or C.danger
            cell("pres", pres and (pres .. "%") or "-", pc.r, pc.g, pc.b)
            -- A Discord core's list is the Discord's (#339): who leaves it, and who is a reserve, too.
            local ac = at("acts")
            if ac and ac.shown then
                local stBtn = track(UI:CreateButton(rightContent, m.status == "bench" and L["starter"] or L["reserve"], 60, 18))
                stBtn:SetPoint("TOPLEFT", ac.x, y - 2)
                stBtn:SetScript("OnClick", function()
                    CM:SetMemberBench(mk, m.status ~= "bench", coreName)
                    BuildSettings(coreName)
                end)
                local remBtn = track(UI:CreateButton(rightContent, L["Remove"], 56, 18))
                remBtn:SetPoint("LEFT", stBtn, "RIGHT", 4, 0)
                UI:SetButtonVariant(remBtn, "danger")
                remBtn:SetScript("OnClick", function()
                    CM:RemoveMember(mk, coreName)
                    CM:BroadcastRoster(coreName)
                    BuildSettings(coreName)
                end)
            end
            y = y - ROW_H
        end
        -- Who is on the Discord core with no character the site can name: the people to chase (#138).
        local waiting = fromDiscord and GuildOS.db.cores[coreName].discordWaiting
        for _, name in ipairs(waiting or {}) do
            cell("name", name, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            cell("role", L["waiting for a character"], C.labelDim.r, C.labelDim.g, C.labelDim.b)
            cell("origin", L["no site account"], C.labelDim.r, C.labelDim.g, C.labelDim.b)
            y = y - ROW_H
        end
        y = y - 8

        -- The night's guests (issue #340): apart from the members, out of the composition. Each one
        -- leaves when the raid session ends, unless marked to stay.
        local guests = CM:GetGuests(coreName)
        local takesGuests = CM:TakesGuests(coreName)
        local guestList = {}
        for k, g in pairs(guests) do guestList[#guestList + 1] = { key = k, g = g } end
        table.sort(guestList, function(a, b) return (a.g.name or a.key) < (b.g.name or b.key) end)
        if takesGuests or #guestList > 0 then
            y = MakeSectionHeader(rightContent, string.format(L["Guests of the night (%d)"], #guestList), y)
            for _, entry in ipairs(guestList) do
                local g, gk = entry.g, entry.key
                local cr, cg, cb = GuildOS:GetClassColor(g.class or "WARRIOR")
                local gLbl = MakeLabel(rightContent, string.format("%s \194\183 %s \194\183 %s", g.name or gk,
                    CM.ROLE_LABELS[g.role] or "?", g.stay and L["stays"] or L["leaves when the raid ends"]), 11, cr, cg, cb)
                gLbl:SetPoint("TOPLEFT", 0, y - 4)
                if isRL then
                    local gStay = track(UI:CreateButton(rightContent, g.stay and L["tonight only"] or L["keep"], 90, 18))
                    gStay:SetPoint("TOPRIGHT", rightContent, "TOPRIGHT", -64, y - 2)
                    gStay:SetScript("OnClick", function() CM:SetGuestStay(gk, coreName, not g.stay); BuildSettings(coreName) end)
                    local gRem = track(UI:CreateButton(rightContent, L["Remove"], 60, 18))
                    gRem:SetPoint("LEFT", gStay, "RIGHT", 4, 0)
                    UI:SetButtonVariant(gRem, "danger")
                    gRem:SetScript("OnClick", function() CM:RemoveGuest(gk, coreName); BuildSettings(coreName) end)
                end
                y = y - ROW_H
            end
            if #guestList == 0 then
                local noG = MakeLabel(rightContent, L["No guests tonight."], 11, C.label.r, C.label.g, C.label.b)
                noG:SetPoint("TOPLEFT", 0, y - 2)
                y = y - 18
            end
            y = y - 6
        end

        -- Add: from the guild (a member, or on a Discord core of a linked guild a guest of the night,
        -- #340), and a pug from outside it by name.
        if isRL and (takesGuests or not fromDiscord) then
            local guildMembers, byFull = {}, {}
            for gi = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
                local gname, _, _, _, _, _, _, _, gonline, _, gclass = GetGuildRosterInfo(gi)
                if gname then
                    local gm = { name = gname:match("^([^%-]+)") or gname, full = gname, class = gclass or "WARRIOR", online = gonline }
                    guildMembers[#guildMembers + 1] = gm
                    byFull[gname] = gm
                end
            end
            table.sort(guildMembers, function(a, b)
                if a.online ~= b.online then return a.online and not b.online end
                return a.name < b.name
            end)
            local picks, pickedFull = {}, nil
            for _, gm in ipairs(guildMembers) do
                local key = GuildOS:KeyOfRosterName(gm.full)
                if key == addGMKey then pickedFull = gm.full end
                if not members[key] and not guests[key] then
                    local cr, cg, cb = GuildOS:GetClassColor(gm.class)
                    picks[#picks + 1] = { value = gm.full, text = gm.name .. (gm.online and "" or (" \194\183 " .. L["offline"])),
                        color = { r = cr, g = cg, b = cb } }
                end
            end
            y = MakeSectionHeader(rightContent, takesGuests and L["INVITE FROM THE GUILD OR THE GROUP"] or L["ADD FROM THE GUILD"], y)
            local gmPick = track(UI:CreateDropdown(rightContent, 190, 22))
            gmPick:SetPoint("TOPLEFT", 0, y)
            gmPick:SetPlaceholder(L["Select player..."])
            gmPick:SetOptions(picks)
            gmPick:SetValue(pickedFull)
            gmPick.isMemberPicker = true
            local roleDD = track(UI:CreateDropdown(rightContent, 110, 22))
            roleDD:SetPoint("LEFT", gmPick, "RIGHT", 6, 0)
            roleDD:SetOptions(roleOptions())
            roleDD:SetValue(addGMRole or "rdps")
            roleDD.onSelect = function(_, role) addGMRole = role end
            gmPick.onSelect = function(_, full)
                local captureGM = byFull[full]
                if not captureGM then return end
                addGMName  = captureGM.name
                addGMKey   = GuildOS:KeyOfRosterName(captureGM.full)
                addGMClass = captureGM.class
                addGMRole  = InferRole(captureGM.class, addGMKey)
                roleDD:SetValue(addGMRole)
            end
            local addBtn = track(UI:CreateButton(rightContent, takesGuests and L["Invite"] or L["Add"], 70, 22))
            addBtn:SetPoint("LEFT", roleDD, "RIGHT", 6, 0)
            addBtn:SetScript("OnClick", function()
                if not addGMName then SetStatus(L["Select a player first."], C.red); return end
                local k = addGMKey or GuildOS:GetPlayerKey(addGMName, GetRealmName())
                local added, why = CM:AddToRoster(k, {
                    name  = addGMName,
                    class = addGMClass,
                    role  = addGMRole or InferRole(addGMClass or "WARRIOR", k),
                }, coreName)
                if not added then SetStatus(why or L["Core not found."], C.red) end
                addGMName, addGMClass, addGMRole, addGMKey = nil, nil, nil, nil
                BuildSettings(coreName)
            end)
            y = y - 30
            -- A pug from outside the guild, by name (#340).
            if takesGuests then
                local nameIn = track(MakeInput(rightContent, 190, false, L["Guest's name"]))
                nameIn:SetPoint("TOPLEFT", 0, y)
                local byName = track(UI:CreateButton(rightContent, L["Add guest"], 90, 22))
                byName:SetPoint("LEFT", nameIn, "RIGHT", 6, 0)
                byName:SetScript("OnClick", function()
                    local ok, why = CM:AddGuestByName(nameIn:GetText(), addGMRole, coreName)
                    if not ok then SetStatus(why or L["Core not found."], C.red); return end
                    BuildSettings(coreName)
                end)
                y = y - 30
            end
        end

        -- What is the Discord's to decide, said once under the roster (#339).
        if fromDiscord then
            local note = MakeLabel(rightContent, L["Who joins and leaves the core is decided on Discord. Here you change the role and invite for the night."], 11)
            note:SetPoint("TOPLEFT", 0, y - 2)
            note:SetWidth(W)
            note:SetJustifyH("LEFT")
            if note.SetWordWrap then note:SetWordWrap(true) end
            y = y - 30
        end
        return y
    end

    ----------------------------------------------------------------
    -- The requests: who asked for a place
    ----------------------------------------------------------------
    local function BuildRequests(coreName, y, track)
        local CM = GuildOS.CoreManager
        local isRL   = CM:IsRaidLeader()
        local signups = CM:GetSignups(coreName)
        local suList = {}
        for k, su in pairs(signups) do suList[#suList + 1] = { key = k, su = su } end
        -- Newest first; alphabetical for entries without a timestamp
        table.sort(suList, function(a, b)
            local ta, tb = a.su.ts or 0, b.su.ts or 0
            if ta ~= tb then return ta > tb end
            return (a.su.name or "") < (b.su.name or "")
        end)
        y = MakeSectionHeader(rightContent, string.format(L["Pending Sign-ups (%d)"], #suList), y)
        local tipLbl = MakeLabel(rightContent,
            CM:IsFromDiscord(coreName) and L["The requests for a Discord core go to Discord: its leader answers there and the answer comes back here."]
            or L["Players apply in the Sign-up window or with: /gos signup <core> [role] [note]"], 11)
        tipLbl:SetPoint("TOPLEFT", 0, y)
        tipLbl:SetWidth(math.max(200, rightContent:GetWidth() or 0))
        tipLbl:SetJustifyH("LEFT")
        y = y - 20
        if #suList == 0 then
            local emL = MakeLabel(rightContent, L["No pending sign-ups."], 11)
            emL:SetPoint("TOPLEFT", 0, y)
            y = y - 20
        end
        local RL = CM.ROLE_LABELS
        for _, entry in ipairs(suList) do
            local su, sk = entry.su, entry.key
            local cr, cg, cb = GuildOS:GetClassColor(su.class or "WARRIOR")
            local nameLbl = MakeLabel(rightContent, string.format("%s \194\183 %s", su.name or sk, (RL and RL[su.role]) or su.role or "?"),
                12, cr, cg, cb)
            nameLbl:SetPoint("TOPLEFT", 0, y)
            if isRL then
                local accBtn = track(UI:CreateButton(rightContent, L["Accept"], 70, 20))
                accBtn:SetPoint("TOPRIGHT", rightContent, "TOPRIGHT", 0, y + 3)
                local decBtn = track(UI:CreateButton(rightContent, L["Decline"], 70, 20))
                decBtn:SetPoint("RIGHT", accBtn, "LEFT", -4, 0)
                UI:SetButtonVariant(decBtn, "danger")
                accBtn:SetScript("OnClick", function()
                    CM:AcceptSignup(sk, coreName)
                    CM:BroadcastRoster(coreName)
                    activeRightTab = "roster"
                    BuildSettings(coreName)
                end)
                decBtn:SetScript("OnClick", function()
                    CM:DeclineSignup(sk, coreName)
                    BuildSettings(coreName)
                end)
            end
            y = y - 22
            local noteStr = (su.note and su.note ~= "") and su.note or ""
            local tsStr = su.ts and GuildOS:TimeAgo(su.ts) or ""
            local subLine = tsStr ~= "" and (noteStr ~= "" and (noteStr .. "  \194\183  " .. tsStr) or tsStr) or noteStr
            if subLine ~= "" then
                local noteLbl = MakeLabel(rightContent, subLine, 11, C.label.r, C.label.g, C.label.b)
                noteLbl:SetPoint("TOPLEFT", 12, y)
                y = y - 16
            end
        end
        return y
    end

    ----------------------------------------------------------------
    -- The rule: what the core plays, read as players read it, and the way to edit it (Loot window)
    ----------------------------------------------------------------
    local function BuildRule(coreName, y, track)
        local CM, LR = GuildOS.CoreManager, GuildOS.LootRule
        -- The core's loot rule and its settings are edited in the Loot window (issue #346): here,
        -- only what it plays and the way there.
        y = MakeSectionHeader(rightContent, L["Loot Rules"], y)
        y = -GuildOS:DrawLootPointer(rightContent, -y - 2, coreName, 0) - 4
        track(rightContent.lootPointer)
        if not LR then return y end
        local site = CM.LootRuleFromSite and CM:LootRuleFromSite(coreName)
        local d = LR:Describe(site or LR:For(coreName), GuildOS.LootMaster and GuildOS.LootMaster:LootSettings(coreName).rollDuration)
        local function line(text)
            local fs = MakeLabel(rightContent, text, 12, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 0, y)
            fs:SetWidth(math.max(200, rightContent:GetWidth() or 0))
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(true) end
            y = y - math.max(14, math.ceil(fs:GetStringHeight() or 14)) - 4
        end
        line(L["Who may ask."] .. " " .. d.who)
        line(L["How to ask."] .. " " .. d.how)
        line(L["Who takes it."] .. " " .. table.concat(d.order, " > "))
        if d.exceptions then line(L["Exceptions."] .. " " .. d.exceptions) end
        if site then line(L["This core's loot rule is set on guildos.me, which sends it with the raid's roster."]) end
        return y
    end

    ----------------------------------------------------------------
    -- Config (officers): the format, the Discord core, the penalties, the raid leaders' ranks
    ----------------------------------------------------------------
    local function BuildConfig(coreName, y, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local catalog = CM:DiscordCatalog()
        local penFields = {
            { key = "LATE",        label = L["Late (pts):"]         },
            { key = "LEFT_EARLY",  label = L["Left early (pts):"]   },
        }
        -- Consumables are checked only where the checker exists (TBC, ADR-0014; issue #184).
        if GuildOS.ConsumableChecker then
            penFields[#penFields + 1] = { key = "NO_CONSUMES", label = L["No consumables (pts):"] }
        end
        -- One label column for the whole form (#371): past its widest label, never before LABEL_MIN.
        local texts = { L["Raid format:"] }
        if #catalog > 0 then texts[#texts + 1] = L["Discord core:"] end
        for _, pf in ipairs(penFields) do texts[#texts + 1] = pf.label end
        local widths = {}
        for i, text in ipairs(texts) do
            local probe = MakeLabel(rightContent, text, 12)
            widths[i] = probe:GetStringWidth() or 0
            probe:Hide()
        end
        local col = UI.LabelColumn(widths, 0, LABEL_GAP, LABEL_MIN)
        -- A form's label: the left column, in the text colour.
        local function formLabel(text)
            local lbl = MakeLabel(rightContent, text, 12, C.text.r, C.text.g, C.text.b)
            lbl:SetPoint("TOPLEFT", 0, y - 4)
            return lbl
        end

        y = MakeSectionHeader(rightContent, L["General"], y)
        local curSize = CM:GetRaidSize(coreName)
        formLabel(L["Raid format:"])
        -- The Discord's size comes back at every import, so a core from the Discord only shows it (#135).
        if fromDiscord then
            local szText = MakeLabel(rightContent, string.format(L["%d-man"], curSize) .. "  \194\183  " .. L["Managed on Discord."], 12)
            szText:SetPoint("TOPLEFT", col, y - 4)
        else
            -- This game's formats: 10 and 25 on TBC, 10, 20 and 40 on Forever (issue #89).
            local sizes = CM:RaidSizes()
            local function pick(size)
                CM:SetRaidSize(coreName, size)
                BuildSettings(coreName)
            end
            if #sizes > 2 then
                local dd = track(UI:CreateDropdown(rightContent, 110, 22))
                dd:SetPoint("TOPLEFT", col, y)
                local opts = {}
                for i, size in ipairs(sizes) do opts[i] = { value = size, text = string.format(L["%d-man"], size) } end
                dd:SetOptions(opts)
                dd:SetValue(curSize)
                dd.isSize = true
                dd.onSelect = function(_, size) pick(size) end
            else
                local x = col
                for _, size in ipairs(sizes) do
                    local b = track(UI:CreateButton(rightContent, string.format(L["%d-man"], size), 70, 22))
                    b:SetPoint("TOPLEFT", x, y)
                    -- The format in force: the shared selection mark (#371).
                    UI:SetSelected(b, size == curSize)
                    b:SetScript("OnClick", function() pick(size) end)
                    x = x + b:GetWidth() + 4
                end
            end
        end
        y = y - 30

        -- The Discord core this one is (#138). A game core named apart from it ("Core 10 Alpha" for
        -- "10 Alpha") is linked by hand, and the import fills it from then on.
        if #catalog > 0 then
            formLabel(L["Discord core:"])
            local linked = GuildOS.db.cores[coreName].discordTag
            if linked then
                local shown = linked
                for _, c in ipairs(catalog) do
                    if c.tag == linked then shown = c.name end
                end
                local cur = MakeLabel(rightContent, shown, 12, C.text.r, C.text.g, C.text.b)
                cur:SetPoint("TOPLEFT", col, y - 4)
            else
                local dd = track(UI:CreateDropdown(rightContent, 160, 22))
                dd:SetPoint("TOPLEFT", col, y)
                local opts = {}
                for i, c in ipairs(catalog) do opts[i] = { value = c.tag, text = c.name } end
                dd:SetOptions(opts)
                dd:SetValue(catalog[1].tag)
                dd.isDiscord = true
                local linkBtn = track(UI:CreateButton(rightContent, L["Link"], 60, 22))
                linkBtn:SetPoint("LEFT", dd, "RIGHT", 6, 0)
                linkBtn:SetScript("OnClick", function()
                    CM:LinkDiscord(coreName, dd:GetValue())
                    BuildSettings(coreName)
                end)
            end
            y = y - 30
        end

        -- The attendance penalties: each saves on its own, and says when it is saved.
        y = MakeSectionHeader(rightContent, L["Attendance Penalties"], y)
        local pen = CM:GetPenalties(coreName)
        local function penSave(key, val)
            CM:SetPenalty(key, val, coreName)
            -- Rebuild from sessions so the new weights apply immediately
            if GuildOS.RaidTracker then
                GuildOS.RaidTracker:RebuildAttendanceFromSessions()
            end
        end
        for _, pf in ipairs(penFields) do
            formLabel(pf.label)
            local inp = track(MakeInput(rightContent, 50, true))
            inp:SetPoint("TOPLEFT", col, y)
            inp:SetText(tostring(pen[pf.key] or 10))
            inp.penaltyKey = pf.key
            local captureKey = pf.key
            track(UI:AttachSaveButton(inp, function(self)
                local v = tonumber(self:GetText()) or 10
                if v < 0 then v = 0 elseif v > 100 then v = 100 end
                self:SetText(tostring(v))
                penSave(captureKey, v)
            end, { state = true }))
            y = y - 28
        end
        local penNote = MakeLabel(rightContent, L["Penalty values take effect on the next attendance rebuild."], 11)
        penNote:SetPoint("TOPLEFT", 0, y)
        y = y - 24

        -- Raid Leader Ranks (who can manage core rosters)
        y = MakeSectionHeader(rightContent, L["Raid Leader Ranks"], y)
        local rlNote = MakeLabel(rightContent,
            L["Guild ranks below can add/remove members and accept sign-ups (officers always can)."], 11)
        rlNote:SetPoint("TOPLEFT", 0, y)
        rlNote:SetWidth(math.max(200, rightContent:GetWidth() or 0))
        rlNote:SetJustifyH("LEFT")
        y = y - 24
        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for ri = 1, numRanks do
            local rn = GuildControlGetRankName and GuildControlGetRankName(ri) or ("Rank " .. ri)
            if rn and rn ~= "" then
                -- Its box flush with the content's edge, as the labels above (#371).
                local rlCk = track(UI:CreateCheckbox(rightContent, rn, 14))
                rlCk:SetPoint("TOPLEFT", 0, y - 4)
                rlCk.checkbox:SetChecked(CM:GetRaidLeaderRanks()[rn] == true)
                local captureRank = rn
                rlCk.checkbox.onChanged = function(_, checked)
                    CM:SetRaidLeaderRank(captureRank, checked and true or false)
                end
                y = y - 22
            end
        end
        return y
    end

    BuildSettings = function(coreName)
        ClearSettings()
        -- Reset add-member selection when switching to a different core
        if coreName ~= lastCoreBuilt then
            addGMName, addGMClass, addGMRole, addGMKey = nil, nil, nil, nil
        end
        lastCoreBuilt = coreName
        local CM = GuildOS.CoreManager
        if not coreName or coreName == "" or not CM or not GuildOS.db.cores[coreName] then
            noCoreLbl:Show()
            rightContent:SetHeight(60)
            return
        end
        local function track(w) cfgWidgets[#cfgWidgets + 1] = w; return w end
        BuildHeader(coreName, track)
        BuildTabs(coreName, track)
        -- The sub-tab's first line is at the top of its scroll (GAP under the bar): a section title
        -- there is the screen's first, with no rule over it (#371).
        local y = 0
        if activeRightTab == "signups" then
            y = BuildRequests(coreName, y, track)
        elseif activeRightTab == "rule" then
            y = BuildRule(coreName, y, track)
        elseif activeRightTab == "config" then
            y = BuildConfig(coreName, y, track)
        else
            y = BuildRoster(coreName, y, track)
        end
        -- Resize content frame so scroll bar knows the full height
        rightContent:SetHeight(math.abs(y) + 20)
    end

    ----------------------------------------------------------------
    -- Core list rebuild
    ----------------------------------------------------------------
    RebuildList = function()
        for _, row in pairs(coreRows) do row:Hide() end
        coreRows = {}
        local CM = GuildOS.CoreManager
        if not CM then return end
        -- Each elenco with its groups under it (issue #352); a core with neither lists as always.
        local names = CM:SortedTree()
        local active = GetActiveName()
        for idx, entry in ipairs(names) do
            local name, indent = entry.name, entry.depth * GROUP_INDENT
            -- Hung by both top corners, as wide as the list leaves it (#371).
            local row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
            row:SetHeight(CORE_ROW_H - 2)
            row:SetPoint("TOPLEFT", indent, -(idx - 1) * CORE_ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(idx - 1) * CORE_ROW_H)
            row:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(row) })
            local on = name == selectedCore
            row:SetBackdropColor(C.well.r, C.well.g, C.well.b, on and 1 or 0)
            local edge = on and C.gold or C.line
            row:SetBackdropBorderColor(edge.r, edge.g, edge.b, on and 1 or 0)

            local lbl = MakeLabel(row, name, 12, C.text.r, C.text.g, C.text.b)
            lbl:SetPoint("TOPLEFT", 8, -4)
            lbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            lbl:SetJustifyH("LEFT")
            -- The raid's core reads as live, in ok: gold is the selection's alone (#371).
            if name == active then lbl:SetTextColor(C.ok.r, C.ok.g, C.ok.b) end
            local size = CM:GetRaidSize(name)
            local comp = CM:GetComposition(name)
            local subText = string.format(L["%d \194\183 %d of %d \194\183 %s"], size, comp.total, size, originOf(CM, name))
            local nGroups = #CM:GroupsOf(name)
            if entry.depth > 0 then
                subText = string.format(L["%d \194\183 %d of %d \194\183 group"], size, comp.total, size)
            elseif nGroups > 0 then
                subText = subText .. " \194\183 " .. string.format(L["split into %d groups"], nGroups)
            end
            local sub = MakeLabel(row, subText, 11, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            sub:SetPoint("BOTTOMLEFT", 8, 4)
            sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            sub:SetJustifyH("LEFT")
            row.label, row.sub = lbl, sub
            row.coreName = name

            row:SetScript("OnClick", function()
                selectedCore = name
                BuildSettings(name)
                RebuildList()
            end)
            row:SetScript("OnEnter", function(self)
                if name ~= selectedCore then self:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1) end
            end)
            row:SetScript("OnLeave", function(self)
                if name ~= selectedCore then self:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0) end
            end)
            coreRows[#coreRows + 1] = row
        end
        listContent:SetHeight(math.max(1, #names * CORE_ROW_H))
        ShowCreate()
    end

    createBtn:SetScript("OnClick", function()
        local name = strtrim(newInput:GetText() or "")
        if name == "" then
            SetStatus(L["Enter a name for the new core."], C.red)
            return
        end
        local ok, err = GuildOS.CoreManager:Create(name)
        if not ok then
            SetStatus(err, C.red)
        else
            newInput:SetText("")
            selectedCore = name
            -- Only here until it is called on Discord: the site and the other officers never see it (#293).
            SetStatus(string.format(L["Core \"%s\" created, only on this client. Call it on Discord with /core so guildos.me and every officer have it."], name), C.online)
            RebuildList()
            BuildSettings(name)
        end
    end)

    againBtn:SetScript("OnClick", function()
        if GuildOS.CoreManager:CreateInGameAgain() then
            SetStatus(L["The guild's cores are created in game again."], C.online)
        end
    end)

    ----------------------------------------------------------------
    -- Refresh hook — called when the panel becomes visible or from sync
    ----------------------------------------------------------------
    GuildOS.coresPanelRefresh = function()
        RebuildList()
        if selectedCore then BuildSettings(selectedCore) end
    end

    panel:SetScript("OnShow", function()
        -- The raid's core, when there is one, is the one open first.
        if not selectedCore then
            local active = GetActiveName()
            if active ~= "" and GuildOS.db.cores and GuildOS.db.cores[active] then selectedCore = active end
        end
        RebuildList()
        if selectedCore then
            BuildSettings(selectedCore)
        else
            noCoreLbl:Show()
        end
    end)

    -- After OnShow is set, which would replace the hook MakeResponsive puts on it.
    -- The list takes a share of the window, between its least and its most.
    UI:MakeResponsive(panel, function(_, w)
        local want = math.max(LIST_MIN, math.min(LIST_MAX, math.floor(w * LIST_SHARE)))
        if want ~= listW then
            listW = want
            leftCol:SetWidth(listW)
            newInput:SetWidth(listW - 72 - GAP)
            againBtn:SetWidth(listW - GAP)
            RebuildList()
        end
        if selectedCore then BuildSettings(selectedCore) end
    end)

    -- Initial build
    noCoreLbl:Show()
end
