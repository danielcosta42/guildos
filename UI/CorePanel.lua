----------------------------------------------------------------------
-- Guild OS - Raids › Cores (issue #346)
-- The guild's cores on the left: each with its size, how full it is and where it comes from (the
-- Discord, or only this game). On the right the core picked: a header card with its name, where it
-- comes from, whether it is the raid's, its format and schedule, and the sub-tabs Roster · Requests ·
-- Rule · Config as pills. Roster: a card a role (who it has of what the format asks, as a bar), the
-- members in a table (avatar, name, role, place, origin, presence) and, beside it, the guests of the
-- night (#340), who to invite, the raid buffs and what is the Discord's to decide. Every change goes
-- through CoreManager; the loot rule is the Loot window's (Rule says which and opens it).
--
-- The spacing standard (#449, specs/salao/fase3.md, "Espaçamento"): cards 16 in and 14 apart, sections
-- 18 apart, fields 26 high and 12 apart, rows 32 with an avatar, body text 13, meta 11, titles 15.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SP = UI.SP                              -- the spacing standard (#449, UI/Helpers.lua)
local M = tonumber(UI.GAP) or 8               -- the room's margin around a screen (#371)
local SPLIT = 820                             -- the content's width from which the roster has a column beside it
local SIDE_MIN, SIDE_MAX = 280, 340           -- that column

local LIST_MIN, LIST_MAX = 200, 280   -- the core list's column, by the window's width
local LIST_SHARE = 0.28
local CORE_ROW_H = 52
local GROUP_INDENT = 12   -- a group's row, under its elenco's (issue #352)
local AVATAR = 24
local ROLE_CARD_H = 66
local HEAD_ABOVE = 20     -- room over a later section title for its rule (UI:CreateSectionTitle)
local HEAD_H = SP.TITLE_H + SP.TITLE_GAP   -- a section title's line and the space under it
local LABEL_GAP, LABEL_MIN = 12, 140       -- the Config form's label column

-- The roster's columns, by priority: the member and the role stay.
local MEMBER_COLS = {
    { key = "name",   min = 150, weight = 3, priority = 9, required = true },
    { key = "role",   min = 120, weight = 1, priority = 8, required = true },
    { key = "place",  min = 76,  weight = 1, priority = 5 },
    { key = "origin", min = 70,  weight = 1, priority = 4 },
    { key = "pres",   min = 52,  weight = 0, priority = 6 },
    { key = "acts",   min = 132, weight = 0, priority = 7 },
}

----------------------------------------------------------------------
-- Shared widget builders
----------------------------------------------------------------------
-- A box: the shared field (#371), with its hint shown while it is empty.
local function MakeInput(parent, w, numeric, placeholder)
    return UI:CreateInput(parent, w, SP.FIELD, { numeric = numeric and true or nil, max = numeric and 5 or nil,
        placeholder = placeholder })
end

local function paperClass(class)
    return GuildOS.UI:InkFor("paper", "class", class)   -- the paper's class inks (UI/Helpers.lua, #449)
end

-- The wood's colours, as the paper prints them: the ink, the soft ink, a state's deeper shade.
local function onPaper(r, g, b)
    return GuildOS.UI.PaperRGB(r, g, b)   -- the one mapping of the paper's inks (UI/Helpers.lua, #449)
end

-- A line of text: the soft ink unless a colour is given; on the parchment, the paper's own shade of it.
-- Body text is 13 (#449); a meta line passes 11.
local function MakeLabel(parent, text, size, r, g, b)
    r, g, b = r or C.textSoft.r, g or C.textSoft.g, b or C.textSoft.b
    if UI:OnPaper(parent) then r, g, b = onPaper(r, g, b) end
    return UI:CreateText(parent, text, size or SP.BODY, r, g, b)
end

-- A section title (#371): the shared one at 15px, at the content's left edge. The first (y = 0) has no
-- rule; a later one leaves HEAD_ABOVE over itself for it. Returns the y under it (y runs negative here).
local function MakeSectionHeader(parent, text, y)
    local first = y >= 0
    if not first then y = y - HEAD_ABOVE end
    local lbl = UI:CreateSectionTitle(parent, text, first)
    GuildOS:ApplyFont(lbl, SP.TITLE, "sectionTitle")
    lbl:SetPoint("TOPLEFT", 0, y)
    return y - HEAD_H
end

-- A card as the standard draws it (#449): the shared card, its title 15px at 16 in, `isCard` for the
-- test that nothing drawn on it leaves it.
local function newCard(parent, title, dark)
    local c = UI:CreateCard(parent, title or "", { dark = dark and true or nil })
    c.isCard = true
    c.title:ClearAllPoints()
    c.title:SetPoint("TOPLEFT", SP.PAD, -SP.PAD)
    c.title:SetPoint("RIGHT", c, "RIGHT", -SP.PAD, 0)
    GuildOS:ApplyFont(c.title, SP.TITLE, "sectionTitle")
    if not title or title == "" then c.title:Hide() end
    return c
end

-- A core's origin, as the list and the header say it.
local function originOf(CM, name)
    if CM:IsFromDiscord(name) then return L["from Discord"] end
    return L["only in this game"]
end

-- The game's role icon for a core's role (#449): the group finder's atlas where the client lists it, the
-- LFG frame's file otherwise, nothing where it has neither (a path it lacks draws a green square).
local ROLE_LETTER = { tank = "T", healer = "H", mdps = "D", rdps = "D" }
local ROLE_ATLAS = { T = "groupfinder-icon-role-large-tank", H = "groupfinder-icon-role-large-heal", D = "groupfinder-icon-role-large-dps" }
local ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local CELL = 67 / 256
local ROLE_CELL = { T = { 0, CELL, CELL, 2 * CELL }, H = { CELL, 2 * CELL, 0, CELL }, D = { CELL, 2 * CELL, CELL, 2 * CELL } }
local function setRoleIcon(tex, role)
    local letter = ROLE_LETTER[role]
    local get = C_Texture and C_Texture.GetAtlasInfo
    if letter and get then
        local ok, info = pcall(get, ROLE_ATLAS[letter])
        if ok and info then tex:SetAtlas(ROLE_ATLAS[letter]); tex:Show(); return true end
    end
    if letter and GuildOS.Compat.TextureExists(ROLE_FILE) then
        tex:SetTexture(ROLE_FILE)
        tex:SetTexCoord(unpack(ROLE_CELL[letter]))
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

----------------------------------------------------------------------
-- Main builder
----------------------------------------------------------------------
function GuildOS:CreateCoresPanel(panel)
    local listW = LIST_MAX

    ----------------------------------------------------------------
    -- Left column: the guild's cores
    ----------------------------------------------------------------
    -- A dark card on the wood (the mockup's "Cores da guilda"), M under the entries.
    local leftCol = newCard(panel, L["Guild cores"], true)
    leftCol:SetPoint("TOPLEFT", 0, -M)
    leftCol:SetPoint("BOTTOMLEFT", 0, M)
    leftCol:SetWidth(listW)

    local listScroll, listContent = UI:CreateScrollFrame(leftCol, "GuildOSCoreListScroll")
    listScroll:SetPoint("TOPLEFT", SP.PAD, -SP.TOP)
    listScroll:SetPoint("BOTTOMRIGHT", -SP.PAD + 6, 110)   -- its bar inside the card (#371)
    UI:BindScrollChildWidth(listScroll, listContent)

    -- At the foot: how cores are born. A guild linked to the site creates them on Discord (#339): a
    -- sentence says so, and when the site last sent; after 30 days with no package from it, a button
    -- creates in game again. An unlinked guild names one and creates it here.
    local linkNote = MakeLabel(leftCol, L["This guild is linked to the site. New cores are born on Discord, with /core criar."], SP.META)
    linkNote:SetJustifyH("LEFT")
    if linkNote.SetWordWrap then linkNote:SetWordWrap(true) end
    local seenNote = MakeLabel(leftCol, "", SP.META, C.label.r, C.label.g, C.label.b)
    local newInput = MakeInput(leftCol, listW - 72 - 2 * SP.PAD, false, L["Core name"])
    newInput:SetPoint("BOTTOMLEFT", SP.PAD, SP.PAD)
    local createBtn = UI:CreateButton(leftCol, L["Create"], 64, SP.FIELD)
    createBtn:SetPoint("LEFT", newInput, "RIGHT", 8, 0)
    local againBtn = UI:CreateButton(leftCol, L["Create cores in game again"], listW - 2 * SP.PAD, SP.FIELD)
    againBtn:SetPoint("BOTTOMLEFT", SP.PAD, SP.PAD)
    local function showIf(w, on)
        if on then w:Show() else w:Hide() end
    end
    local function ShowCreate()
        local CM = GuildOS.CoreManager
        local linked = CM and CM:IsLinked()
        local again = linked and CM:IsLinkQuiet() and GuildOS:IsOfficer()
        showIf(newInput, not linked)
        showIf(createBtn, not linked)
        showIf(linkNote, linked)
        showIf(seenNote, linked)
        showIf(againBtn, again)
        local seen = linked and CM:LinkSeenAt()
        seenNote:SetText(seen and string.format(L["Received from the site %s"], GuildOS:TimeAgo(seen)) or "")
        -- From the foot up: the button row, what the site sent, how cores are born.
        local base = (not linked or again) and (SP.PAD + SP.FIELD + SP.CELL) or SP.PAD
        seenNote:ClearAllPoints()
        seenNote:SetPoint("BOTTOMLEFT", SP.PAD, base)
        seenNote:SetPoint("RIGHT", leftCol, "RIGHT", -SP.PAD, 0)
        linkNote:ClearAllPoints()
        linkNote:SetPoint("BOTTOMLEFT", seenNote, "TOPLEFT", 0, 4)
        linkNote:SetPoint("RIGHT", leftCol, "RIGHT", -SP.PAD, 0)
        listScroll:SetPoint("BOTTOMRIGHT", -SP.PAD + 6, linked and (base + 14 + 4 + 30 + SP.CELL) or (base + SP.CELL))
    end

    ----------------------------------------------------------------
    -- Right: the core picked, a header card and its tab's cards under it
    ----------------------------------------------------------------
    local head = newCard(panel, "")
    head:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", SP.GAP, 0)
    head:SetPoint("TOPRIGHT", -M, -M)
    head:SetHeight(110)
    -- What a drawing puts on the header: it goes with each new drawing (ClearSettings).
    local header = CreateFrame("Frame", nil, head)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("BOTTOMRIGHT", 0, 0)

    local statusLbl = MakeLabel(head, "", SP.META)
    statusLbl:SetJustifyH("RIGHT")
    local function SetStatus(msg, color)
        statusLbl:SetText(msg or "")
        local col = color or C.textSoft
        local r, g, b = onPaper(col.r, col.g, col.b)
        statusLbl:SetTextColor(r, g, b)
    end

    local rightScroll, rightContent = UI:CreateScrollFrame(panel, "GuildOSCoreSettingsScroll")
    rightScroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -SP.GAP)
    -- The scroll child stops UI.SCROLL_GUTTER short of the frame: the frame reaches that far past the
    -- header's right edge, so the cards end where it does (#371).
    rightScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(M - (tonumber(UI.SCROLL_GUTTER) or 12)), M)
    UI:BindScrollChildWidth(rightScroll, rightContent)

    -- Shown when no core is selected
    local noCoreLbl = MakeLabel(head, L["Select or create a core on the left."], SP.BODY, C.label.r, C.label.g, C.label.b)
    -- No core chosen: the line centred in its card, a block rather than a line in the corner (#449).
    noCoreLbl:SetPoint("LEFT", SP.PAD, 0)
    noCoreLbl:SetPoint("RIGHT", -SP.PAD, 0)
    noCoreLbl:SetJustifyH("CENTER")

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
            -- The role's colour as the parchment prints it: every one of these sits on a parchment card.
            local rc = CM.ROLE_COLORS[role]
            local color
            if rc then
                local r, g, b = onPaper(rc.r, rc.g, rc.b)
                color = { r = r, g = g, b = b }
            end
            opts[#opts + 1] = { value = role, text = CM.ROLE_LABELS[role] or role, color = color }
        end
        return opts
    end

    -- The cards a drawing lays (cardAt), kept and handed out again by their order on every build (#449 review:
    -- each build made new ones, and the client never frees a frame).
    local cardPool, cardsUsed = {}, 0
    local function ClearSettings()
        cardsUsed = 0
        for _, w in ipairs(cfgWidgets) do
            if w.Hide then w:Hide() end
        end
        cfgWidgets = {}
        -- What a drawing put straight on the header: hide it too.
        for _, region in pairs({ header:GetRegions() }) do region:Hide() end
        noCoreLbl:Hide()
    end

    local BuildSettings, RebuildList

    -- The width the cards under the header have: the scroll child's, as its anchors make it.
    -- The scroll frame's width as its anchors make it, less the gutter, kept on the child too: the child
    -- is sized when the frame's size changes, which a window built and filled at once has not seen yet.
    local function contentWidth()
        local w = (tonumber(UI:LaidWidth(rightScroll)) or 0) - (tonumber(UI.SCROLL_GUTTER) or 12)
        if w > 2 then
            rightContent:SetWidth(w)
        else
            w = tonumber(UI:LaidWidth(rightContent)) or 0
        end
        return math.max(200, w)
    end

    -- A card on the scroll, at x, y (y down from the top), `w` wide; its body is where its content goes,
    -- CARD_PAD in, under its title. Returns the card and the body.
    local function cardAt(title, x, y, w, track)
        cardsUsed = cardsUsed + 1
        local card = cardPool[cardsUsed]
        if not card then
            card = newCard(rightContent, "")
            card.body = CreateFrame("Frame", nil, card)
            -- The card's height from its body's (h, positive), never under `min`.
            function card:Fit(h, min)
                local top = self.titled and SP.TOP or SP.PAD
                self:SetHeight(math.max(min or 0, top + h + SP.PAD))
                self.body:SetHeight(math.max(1, h))
                return self:GetHeight()
            end
            cardPool[cardsUsed] = card
        end
        track(card)
        card.titled = (title and title ~= "") and true or false
        GuildOS:SetTitleText(card.title, title or "")
        card.title:SetShown(card.titled)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", rightContent, "TOPLEFT", x, -y)
        card:SetWidth(w)
        card:Show()
        local body = card.body
        -- What the last build drew on the body is hidden (tracked); this build draws on it afresh.
        local top = card.titled and SP.TOP or SP.PAD
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", SP.PAD, -top)
        body:SetPoint("TOPRIGHT", -SP.PAD, -top)
        body:SetHeight(1)
        body:Show()
        return card, body
    end

    ----------------------------------------------------------------
    -- The header: name, origin, state, format and schedule, the sub-tabs
    ----------------------------------------------------------------
    local function BuildHeader(coreName, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local title = UI:CreateTitle(header, coreName, 18)
        title:SetPoint("TOPLEFT", SP.PAD, -(SP.PAD + 2))
        local x = title
        local origin = track(UI:CreateBadge(header, originOf(CM, coreName), fromDiscord and C.info or C.label))
        origin:SetPoint("LEFT", x, "RIGHT", 10, 0)
        x = origin
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
            local active = track(UI:CreateBadge(header, L["active in the raid"], C.ok))
            active:SetPoint("LEFT", x, "RIGHT", 6, 0)
        elseif GuildOS.RaidTracker then
            local setActiveBtn = track(UI:CreateButton(header, L["Set Active"], 96, SP.HIT))
            setActiveBtn:SetPoint("LEFT", x, "RIGHT", 10, 0)
            setActiveBtn:SetScript("OnClick", function()
                GuildOS.RaidTracker:PickCore(coreName)
                SetStatus(string.format(L["Active core set to: %s"], coreName), C.online)
                RebuildList()
                BuildSettings(coreName)
            end)
        end
        -- A core of the Discord keeps the Discord's name and is closed there (#135, #293): no rename,
        -- no delete. One only this game has can be renamed and deleted.
        if not fromDiscord and GuildOS:IsOfficer() then
            local deleteBtn = track(UI:CreateButton(header, L["Delete"], 72, SP.HIT))
            deleteBtn:SetPoint("TOPRIGHT", -SP.PAD, -SP.PAD)
            UI:SetButtonVariant(deleteBtn, "danger")
            deleteBtn:SetScript("OnClick", function()
                local ok, err = CM:Delete(coreName)
                if not ok then SetStatus(err or L["Core not found."], C.red); return end
                selectedCore = nil
                SetStatus(string.format(L["Core \"%s\" deleted."], coreName), C.red)
            end)
            local renameBtn = track(UI:CreateButton(header, L["Rename"], 72, SP.HIT))
            renameBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -6, 0)
            local renameInput = track(UI:CreateInput(header, 130, SP.HIT, { placeholder = L["New name"] }))
            renameInput:SetPoint("RIGHT", renameBtn, "LEFT", -6, 0)
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
        end
        -- The meta line: the format, when it raids (the site's schedule), how full it is.
        local comp = CM:GetComposition(coreName)
        local size = CM:GetRaidSize(coreName)
        local parts = { string.format(L["%d-man"], size) }
        local core = GuildOS.db.cores[coreName]
        if type(core.schedule) == "string" and core.schedule ~= "" then parts[#parts + 1] = core.schedule end
        parts[#parts + 1] = string.format(L["%d of %d members"], comp.total, size)
        if (comp.bench or 0) > 0 then parts[#parts + 1] = string.format(L["%d in reserve"], comp.bench) end
        local meta = MakeLabel(header, table.concat(parts, "  \194\183  "), SP.BODY)
        meta:SetPoint("TOPLEFT", SP.PAD, -(SP.PAD + 24 + 6))
        return SP.PAD + 24 + 6 + 18 + SP.FIELD_GAP
    end

    local function BuildTabs(coreName, y, track)
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
            local tb = track(UI:SetButtonVariant(UI:CreateButton(header, t.label, 40, SP.HIT), "chip"))
            tb:SetWidth(math.ceil(tb.label:GetStringWidth() or 30) + 24)
            if prev then tb:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tb:SetPoint("TOPLEFT", SP.PAD, -y) end
            UI:SetSelected(tb, t.key == activeRightTab)
            tb.key = t.key
            tb:SetScript("OnClick", function()
                activeRightTab = t.key
                BuildSettings(coreName)
            end)
            prev = tb
        end
        statusLbl:ClearAllPoints()
        statusLbl:SetPoint("TOPRIGHT", head, "TOPRIGHT", -SP.PAD, -(y + 6))
        return y + SP.HIT + SP.PAD
    end

    ----------------------------------------------------------------
    -- The core's roster: a card a role, the members, and beside them the guests and who to invite
    ----------------------------------------------------------------
    -- One card a role: its icon and name, who it has of what the format asks, and that as a thin bar in
    -- the paper's ok ink, or its warn ink while the role is short. Returns the y under the cards.
    local function RoleCards(coreName, W, track)
        local CM = GuildOS.CoreManager
        local roles = CM:GetComposition(coreName).roleCounts
        local T = CM:RaidTargets(CM:GetRaidSize(coreName))
        local METERS = {
            { key = "tank", label = L["Tanks"] }, { key = "healer", label = L["Healers"] },
            { key = "mdps", label = L["Melee"] }, { key = "rdps", label = L["Ranged"] },
        }
        local cols = W >= 4 * 150 + 3 * SP.GAP and 4 or 2
        local rw = math.floor((W - (cols - 1) * SP.GAP) / cols)
        for i, m in ipairs(METERS) do
            local have, want = roles[m.key] or 0, T[m.key] or 0
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local card = cardAt("", col * (rw + SP.GAP), row * (ROLE_CARD_H + SP.GAP), rw, track)
            card:SetHeight(ROLE_CARD_H)
            card.role = m.key
            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("TOPLEFT", SP.PAD, -(SP.PAD + 1))
            local drawn = setRoleIcon(icon, m.key)
            local lbl = MakeLabel(card, m.label, SP.BODY)
            lbl:SetPoint("TOPLEFT", SP.PAD + (drawn and 22 or 0), -SP.PAD)
            local count = UI:CreateText(card, string.format("%d / %d", have, want), SP.KPI)
            GuildOS:ApplyFont(count, SP.KPI, "metricValue")
            count:SetTextColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
            count:SetPoint("TOPRIGHT", -SP.PAD, -(SP.PAD - 4))
            local track0 = card:CreateTexture(nil, "ARTWORK")
            track0:SetTexture(WHITE)
            track0:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
            track0:SetHeight(4)
            track0:SetPoint("BOTTOMLEFT", SP.PAD, SP.PAD)
            track0:SetPoint("BOTTOMRIGHT", -SP.PAD, SP.PAD)
            local bar = card:CreateTexture(nil, "OVERLAY")
            bar:SetTexture(WHITE)
            local r, g, b = UI:InkFor("paper", "status", have >= want and "ok" or "warn")
            bar:SetVertexColor(r, g, b, 1)
            bar:SetHeight(4)
            bar:SetPoint("BOTTOMLEFT", SP.PAD, SP.PAD)
            bar:SetWidth(math.max(1, (rw - 2 * SP.PAD) * (want > 0 and math.min(1, have / want) or 1)))
        end
        local rows = math.ceil(#METERS / cols)
        return rows * ROLE_CARD_H + (rows - 1) * SP.GAP + SP.GAP
    end

    -- The members' table, in its card. Returns its height (the card is sized by the caller).
    local function RosterTable(coreName, body, W, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local isRL = CM:IsRaidLeader()
        local members = CM:GetMembers(coreName)
        local y = 0
        -- The members: titulars first, then the reserves (issue #212).
        local sortedMbrs = {}
        for k, m in pairs(members) do sortedMbrs[#sortedMbrs + 1] = { key = k, m = m } end
        table.sort(sortedMbrs, function(a, b)
            local ab, bb = a.m.status == "bench", b.m.status == "bench"
            if ab ~= bb then return bb end
            if (a.m.role or "") ~= (b.m.role or "") then return (a.m.role or "") < (b.m.role or "") end
            return (a.m.name or "") < (b.m.name or "")
        end)
        local spec = {}
        for _, col in ipairs(MEMBER_COLS) do
            if not (col.key == "acts" and (fromDiscord or not isRL)) then spec[#spec + 1] = col end
        end
        local layout = UI:ResolveColumns(spec, W, SP.CELL)
        panel.memberLayout = layout
        local function at(key) return layout.byKey[key] end
        local TITLES = { name = L["Member"], role = L["Role"], place = L["Place"], origin = L["Origin"], pres = L["Pres."], acts = "" }
        -- The table's header row: the shared one, no fill and a 1px rule under it (#371).
        local thead = track(UI:CreateTableHeader(body, 24))
        thead:SetPoint("TOPLEFT", 0, y)
        thead:SetPoint("TOPRIGHT", 0, y)
        for _, col in ipairs(spec) do
            local c = at(col.key)
            if c.shown and TITLES[col.key] ~= "" then
                local h = UI:CreateHeaderText(thead, TITLES[col.key], UI.SP.META)
                if col.key == "pres" then
                    h:SetPoint("RIGHT", thead, "LEFT", c.x + c.w, 0)
                else
                    h:SetPoint("LEFT", c.x + (col.key == "name" and (AVATAR + 8) or 0), 0)
                end
            end
        end
        y = y - 24

        local function cell(key, text, size, r, g, b, right)
            local c = at(key)
            if not (c and c.shown) then return nil end
            local fs = MakeLabel(body, text, size or SP.BODY, r, g, b)
            fs:SetPoint("TOPLEFT", c.x, y - (SP.ROW_AV - 16) / 2)
            fs:SetWidth(math.max(1, c.w))
            fs:SetJustifyH(right and "RIGHT" or "LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            return fs
        end
        local function rule()
            local bg = body:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(WHITE)
            bg:SetPoint("TOPLEFT", 0, y - SP.ROW_AV)
            bg:SetPoint("TOPRIGHT", 0, y - SP.ROW_AV)
            bg:SetHeight(1)
            bg:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
        end

        if #sortedMbrs == 0 then
            local emL = MakeLabel(body, L["No members yet."], SP.BODY, C.label.r, C.label.g, C.label.b)
            emL:SetPoint("TOPLEFT", 0, y - SP.FIELD_GAP)
            y = y - SP.FIELD_GAP - 18
        end
        for _, entry in ipairs(sortedMbrs) do
            local m, mk = entry.m, entry.key
            rule()
            local nc = at("name")
            local av = track(UI:CreateAvatar(body, AVATAR, false))
            av:SetPoint("TOPLEFT", nc.x, y - (SP.ROW_AV - AVATAR) / 2)
            av:SetMember(m.name or mk, m.class, m.status == "bench")
            local cr, cg, cb = paperClass(m.class or "WARRIOR")
            local nameFS = MakeLabel(body, m.name or mk, SP.BODY, cr, cg, cb)
            nameFS:SetTextColor(cr, cg, cb)
            GuildOS:ApplyFont(nameFS, SP.BODY, "memberName")
            nameFS:SetPoint("TOPLEFT", nc.x + AVATAR + 8, y - (SP.ROW_AV - 16) / 2)
            nameFS:SetWidth(math.max(1, nc.w - AVATAR - 8))
            nameFS:SetJustifyH("LEFT")
            if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end
            if m.status == "bench" then nameFS:SetAlpha(0.7) end
            -- The role: a dropdown for whoever may change it (a Discord core's people too, #135).
            local rc = at("role")
            if isRL and rc.shown then
                local dd = track(UI:CreateDropdown(body, math.min(150, rc.w), SP.HIT))
                dd:SetPoint("TOPLEFT", rc.x, y - (SP.ROW_AV - SP.HIT) / 2)
                dd:SetOptions(roleOptions())
                dd:SetValue(m.role or "rdps")
                dd.memberKey = mk
                dd.onSelect = function(_, role)
                    CM:SetMemberRole(mk, role, coreName)
                    BuildSettings(coreName)
                end
            else
                local col = CM.ROLE_COLORS[m.role or "rdps"] or C.text
                cell("role", CM.ROLE_LABELS[m.role or "rdps"] or "?", SP.BODY, col.r, col.g, col.b)
            end
            -- The place: a badge, the reserve's in the warn ink.
            local pc = at("place")
            if pc and pc.shown then
                local badge = track(UI:CreateBadge(body, m.status == "bench" and L["Reserve"] or L["Starter"],
                    m.status == "bench" and C.warn or C.label))
                badge:SetPoint("LEFT", body, "TOPLEFT", pc.x, y - SP.ROW_AV / 2)
            end
            cell("origin", (fromDiscord and m.src == "discord") and L["Discord"] or L["in game"], SP.BODY)
            local pres = CM:MemberPresence(mk, coreName)
            local pk = (not pres and "mute") or (pres >= 80 and "ok") or (pres >= 60 and "warn") or "bad"
            local pr, pg, pb = UI:InkFor("paper", "status", pk)
            local presFS = cell("pres", pres and (pres .. "%") or "-", SP.BODY, nil, nil, nil, true)
            if presFS then presFS:SetTextColor(pr, pg, pb) end
            -- A Discord core's list is the Discord's (#339): who leaves it, and who is a reserve, too.
            local ac = at("acts")
            if ac and ac.shown then
                local stBtn = track(UI:CreateButton(body, m.status == "bench" and L["starter"] or L["reserve"], 64, SP.HIT))
                stBtn:SetPoint("TOPLEFT", ac.x, y - (SP.ROW_AV - SP.HIT) / 2)
                stBtn:SetScript("OnClick", function()
                    CM:SetMemberBench(mk, m.status ~= "bench", coreName)
                    BuildSettings(coreName)
                end)
                local remBtn = track(UI:CreateButton(body, L["Remove"], 62, SP.HIT))
                remBtn:SetPoint("LEFT", stBtn, "RIGHT", 6, 0)
                UI:SetButtonVariant(remBtn, "danger")
                remBtn:SetScript("OnClick", function()
                    CM:RemoveMember(mk, coreName)
                    CM:BroadcastRoster(coreName)
                    BuildSettings(coreName)
                end)
            end
            y = y - SP.ROW_AV
        end
        -- Who is on the Discord core with no character the site can name: the people to chase (#138).
        local waiting = fromDiscord and GuildOS.db.cores[coreName].discordWaiting
        for _, name in ipairs(waiting or {}) do
            rule()
            local nc = at("name")
            local nameFS = MakeLabel(body, name, SP.BODY, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            nameFS:SetPoint("TOPLEFT", nc.x + AVATAR + 8, y - (SP.ROW_AV - 16) / 2)
            nameFS:SetWidth(math.max(1, nc.w - AVATAR - 8))
            nameFS:SetJustifyH("LEFT")
            cell("role", L["waiting for a character"], SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            cell("origin", L["no site account"], SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            y = y - SP.ROW_AV
        end
        return -y
    end

    -- The night's guests (issue #340): apart from the members, out of the composition, each leaving
    -- when the raid session ends unless marked to stay; then a pug from outside the guild by name.
    local function GuestsCard(coreName, x, y, w, track)
        local CM = GuildOS.CoreManager
        local isRL = CM:IsRaidLeader()
        local guests = CM:GetGuests(coreName)
        local guestList = {}
        for k, g in pairs(guests) do guestList[#guestList + 1] = { key = k, g = g } end
        table.sort(guestList, function(a, b) return (a.g.name or a.key) < (b.g.name or b.key) end)
        local card, body = cardAt(string.format(L["Guests of the night (%d)"], #guestList), x, y, w, track)
        local inner = w - 2 * SP.PAD
        local by = 0
        for _, entry in ipairs(guestList) do
            local g, gk = entry.g, entry.key
            local cr, cg, cb = paperClass(g.class or "WARRIOR")
            local nameFS = MakeLabel(body, g.name or gk, SP.BODY, cr, cg, cb)
            nameFS:SetTextColor(cr, cg, cb)
            GuildOS:ApplyFont(nameFS, SP.BODY, "memberName")
            nameFS:SetPoint("TOPLEFT", 0, by - 4)
            local metaFS = MakeLabel(body, string.format("%s \194\183 %s", CM.ROLE_LABELS[g.role] or "?",
                g.stay and L["stays"] or L["leaves when the raid ends"]), SP.META)
            metaFS:SetPoint("TOPLEFT", 0, by - 22)
            local taken = 0
            if isRL then
                local gRem = track(UI:CreateButton(body, L["Remove"], 64, SP.HIT))
                gRem:SetPoint("TOPRIGHT", 0, by - 9)
                UI:SetButtonVariant(gRem, "danger")
                gRem:SetScript("OnClick", function() CM:RemoveGuest(gk, coreName); BuildSettings(coreName) end)
                local gStay = track(UI:CreateButton(body, g.stay and L["tonight only"] or L["keep"], 84, SP.HIT))
                gStay:SetPoint("RIGHT", gRem, "LEFT", -6, 0)
                gStay:SetScript("OnClick", function() CM:SetGuestStay(gk, coreName, not g.stay); BuildSettings(coreName) end)
                taken = 64 + 6 + 84 + 8
            end
            nameFS:SetWidth(math.max(20, inner - taken))
            nameFS:SetJustifyH("LEFT")
            metaFS:SetWidth(math.max(20, inner - taken))
            metaFS:SetJustifyH("LEFT")
            if metaFS.SetWordWrap then metaFS:SetWordWrap(false); nameFS:SetWordWrap(false) end
            by = by - 42
        end
        if #guestList == 0 then
            local noG = MakeLabel(body, L["No guests tonight."], SP.BODY, C.label.r, C.label.g, C.label.b)
            noG:SetPoint("TOPLEFT", 0, by)
            by = by - 18
        end
        -- A pug from outside the guild, by name (#340): the name, its role, Add guest.
        if isRL and CM:TakesGuests(coreName) then
            by = by - SP.SECTION
            local nameIn = track(MakeInput(body, inner, false, L["Guest's name"]))
            nameIn:SetPoint("TOPLEFT", 0, by)
            by = by - SP.FIELD - SP.FIELD_GAP
            local guestRole = track(UI:CreateDropdown(body, math.max(100, inner - 110 - 8), SP.FIELD))
            guestRole:SetPoint("TOPLEFT", 0, by)
            guestRole:SetOptions(roleOptions())
            guestRole:SetValue(addGMRole or "rdps")
            guestRole.onSelect = function(_, role) addGMRole = role end
            local byName = track(UI:CreateButton(body, L["Add guest"], 110, SP.FIELD))
            byName:SetPoint("TOPRIGHT", 0, by)
            byName:SetScript("OnClick", function()
                local ok, why = CM:AddGuestByName(nameIn:GetText(), addGMRole, coreName)
                if not ok then SetStatus(why or L["Core not found."], C.red); return end
                BuildSettings(coreName)
            end)
            by = by - SP.FIELD
        end
        return card:Fit(-by)
    end

    -- Add from the guild: a member, or on a Discord core of a linked guild a guest of the night (#340).
    local function InviteCard(coreName, x, y, w, track)
        local CM = GuildOS.CoreManager
        local members, guests = CM:GetMembers(coreName), CM:GetGuests(coreName)
        local takesGuests = CM:TakesGuests(coreName)
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
        local card, body = cardAt(takesGuests and L["Invite from the guild or the group"] or L["Add from the guild"], x, y, w, track)
        local inner = w - 2 * SP.PAD
        local by = 0
        local gmPick = track(UI:CreateDropdown(body, inner, SP.FIELD))
        gmPick:SetPoint("TOPLEFT", 0, by)
        gmPick:SetPlaceholder(L["Select player..."])
        gmPick:SetOptions(picks)
        gmPick:SetValue(pickedFull)
        gmPick.isMemberPicker = true
        by = by - SP.FIELD - SP.FIELD_GAP
        local addW = 96
        local roleDD = track(UI:CreateDropdown(body, math.max(100, inner - addW - 8), SP.FIELD))
        roleDD:SetPoint("TOPLEFT", 0, by)
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
        local addBtn = track(UI:SetButtonVariant(UI:CreateButton(body, takesGuests and L["Invite"] or L["Add"], addW, SP.FIELD), "primary"))
        addBtn:SetPoint("TOPRIGHT", 0, by)
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
        by = by - SP.FIELD
        return card:Fit(-by)
    end

    -- Raid buff coverage, where the game has a list of them (none on Forever, issue #92).
    local function BuffsCard(comp, x, y, w, track)
        local card, body = cardAt(L["Raid Buffs"], x, y, w, track)
        local inner = w - 2 * SP.PAD
        local perRow = math.max(1, math.floor(inner / 140))
        local colW = math.floor(inner / perRow)
        local by, col = 0, 0
        for _, bs in ipairs(comp.buffStatus) do
            local r, g, b = UI:InkFor("paper", "status", bs.covered and "ok" or "bad")
            local lbl = MakeLabel(body, (bs.covered and "+ " or "- ") .. bs.name, SP.BODY, r, g, b)
            lbl:SetTextColor(r, g, b)
            lbl:SetPoint("TOPLEFT", col * colW, by)
            lbl:SetWidth(colW - 6)
            lbl:SetJustifyH("LEFT")
            col = col + 1
            if col >= perRow then col = 0; by = by - 20 end
        end
        if col > 0 then by = by - 20 end
        return card:Fit(-by - 2)
    end

    -- What is the Discord's to decide (#339), as a soft note: a glyph and the sentence.
    local function DiscordNote(x, y, w, track)
        local card, body = cardAt("", x, y, w, track)
        card.isNote = true
        local glyph = UI:CreateGlyph(body, 22)
        glyph:SetPoint("TOPLEFT", 0, 0)
        glyph:Set("i", C.info)
        local note = MakeLabel(body, L["Who joins and leaves the core is decided on Discord. Here you change the role and invite for the night."], SP.BODY)
        note:SetPoint("TOPLEFT", 22 + SP.CELL, 0)
        note:SetWidth(math.max(40, w - 2 * SP.PAD - 22 - SP.CELL))
        note:SetJustifyH("LEFT")
        if note.SetWordWrap then note:SetWordWrap(true) end
        local h = math.max(22, math.ceil(note:GetStringHeight() or 14))
        return card:Fit(h)
    end

    local function BuildRoster(coreName, track)
        local CM = GuildOS.CoreManager
        local fromDiscord = CM:IsFromDiscord(coreName)
        local isRL = CM:IsRaidLeader()
        local comp = CM:GetComposition(coreName)
        local W = contentWidth()
        local availH = rightScroll:GetHeight() or 0
        local y = RoleCards(coreName, W, track)

        local split = W >= SPLIT
        local sideW = split and math.max(SIDE_MIN, math.min(SIDE_MAX, math.floor(W * 0.34))) or W
        local mainW = split and (W - SP.GAP - sideW) or W

        -- The roster, the wide card: the table, and what is still open in its title's line.
        local nMembers = 0
        for _ in pairs(CM:GetMembers(coreName)) do nMembers = nMembers + 1 end
        local roster, body = cardAt(string.format(L["Roster (%d)"], nMembers), 0, y, mainW, track)
        local open = CM:OpenSlots(coreName)
        if open.total + open.tank + open.healer + open.mdps + open.rdps > 0 then   -- a role short is a slot, full or not
            local openFS = MakeLabel(roster, string.format(L["Open: %d  (T %d · H %d · M %d · R %d)"],
                open.total, open.tank, open.healer, open.mdps, open.rdps), SP.META)
            openFS:SetPoint("TOPRIGHT", -SP.PAD, -(SP.PAD + 3))
            roster.title:SetPoint("RIGHT", roster, "RIGHT", -(SP.PAD + math.ceil(openFS:GetStringWidth() or 120) + SP.CELL), 0)
        end
        local rosterH = RosterTable(coreName, body, mainW - 2 * SP.PAD, track)

        -- The column beside it (under it when narrow): guests, who to invite, buffs, the Discord's note.
        local sx, sy = split and (mainW + SP.GAP) or 0, split and y or nil
        local side = {}
        if CM:TakesGuests(coreName) or next(CM:GetGuests(coreName)) then
            side[#side + 1] = function(at) return GuestsCard(coreName, sx, at, sideW, track) end
        end
        if isRL and (CM:TakesGuests(coreName) or not fromDiscord) then
            side[#side + 1] = function(at) return InviteCard(coreName, sx, at, sideW, track) end
        end
        if #comp.buffStatus > 0 then
            side[#side + 1] = function(at) return BuffsCard(comp, sx, at, sideW, track) end
        end
        if fromDiscord then
            side[#side + 1] = function(at) return DiscordNote(sx, at, sideW, track) end
        end

        local minRoster = split and (availH - y) or 0
        local rh = roster:Fit(rosterH, minRoster)
        if not split then sy = y + rh + SP.GAP end
        local sideBottom = sy
        for _, draw in ipairs(side) do
            sideBottom = sideBottom + draw(sideBottom) + SP.GAP
        end
        if split then
            -- The roster grows to the column's height and to the room left, the lists fill it (#449).
            local colH = sideBottom - SP.GAP - y
            if colH > rh then rh = roster:Fit(rosterH, colH) end
            return math.max(y + rh, sideBottom - SP.GAP)
        end
        return math.max(y + rh, sideBottom - SP.GAP)
    end

    ----------------------------------------------------------------
    -- The requests: who asked for a place
    ----------------------------------------------------------------
    local function BuildRequests(coreName, body, W, track)
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
        local y = MakeSectionHeader(body, string.format(L["Pending Sign-ups (%d)"], #suList), 0)
        local tipLbl = MakeLabel(body,
            CM:IsFromDiscord(coreName) and L["The requests for a Discord core go to Discord: its leader answers there and the answer comes back here."]
            or L["Players apply in the Sign-up window or with: /gos signup <core> [role] [note]"], SP.BODY)
        tipLbl:SetPoint("TOPLEFT", 0, y)
        tipLbl:SetWidth(W)
        tipLbl:SetJustifyH("LEFT")
        if tipLbl.SetWordWrap then tipLbl:SetWordWrap(true) end
        y = y - math.max(18, math.ceil(tipLbl:GetStringHeight() or 16)) - SP.FIELD_GAP
        if #suList == 0 then
            local emL = MakeLabel(body, L["No pending sign-ups."], SP.BODY, C.label.r, C.label.g, C.label.b)
            emL:SetPoint("TOPLEFT", 0, y)
            y = y - 20
        end
        local RL = CM.ROLE_LABELS
        for _, entry in ipairs(suList) do
            local su, sk = entry.su, entry.key
            local cr, cg, cb = paperClass(su.class or "WARRIOR")
            local av = track(UI:CreateAvatar(body, AVATAR, false))
            av:SetPoint("TOPLEFT", 0, y - (SP.ROW_AV - AVATAR) / 2)
            av:SetMember(su.name or sk, su.class)
            local nameLbl = MakeLabel(body, string.format("%s \194\183 %s", su.name or sk, (RL and RL[su.role]) or su.role or "?"),
                SP.BODY, cr, cg, cb)
            nameLbl:SetTextColor(cr, cg, cb)
            nameLbl:SetPoint("TOPLEFT", AVATAR + 8, y - 4)
            local noteStr = (su.note and su.note ~= "") and su.note or ""
            local tsStr = su.ts and GuildOS:TimeAgo(su.ts) or ""
            local subLine = tsStr ~= "" and (noteStr ~= "" and (noteStr .. "  \194\183  " .. tsStr) or tsStr) or noteStr
            if subLine ~= "" then
                local noteLbl = MakeLabel(body, subLine, SP.META, C.label.r, C.label.g, C.label.b)
                noteLbl:SetPoint("TOPLEFT", AVATAR + 8, y - 22)
            end
            if isRL then
                local accBtn = track(UI:SetButtonVariant(UI:CreateButton(body, L["Accept"], 76, SP.HIT), "primary"))
                accBtn:SetPoint("TOPRIGHT", 0, y - 9)
                local decBtn = track(UI:CreateButton(body, L["Decline"], 76, SP.HIT))
                decBtn:SetPoint("RIGHT", accBtn, "LEFT", -6, 0)
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
            y = y - 42
        end
        return -y
    end

    ----------------------------------------------------------------
    -- The rule: what the core plays, read as players read it, and the way to edit it (Loot window)
    ----------------------------------------------------------------
    local function BuildRule(coreName, body, W, track)
        local CM, LR = GuildOS.CoreManager, GuildOS.LootRule
        -- The core's loot rule and its settings are edited in the Loot window (issue #346): here,
        -- only what it plays and the way there.
        local y = MakeSectionHeader(body, L["Loot Rules"], 0)
        y = -GuildOS:DrawLootPointer(body, -y - 2, coreName, 0) - 4
        track(body.lootPointer)
        if not LR then return -y end
        local site = CM.LootRuleFromSite and CM:LootRuleFromSite(coreName)
        local d = LR:Describe(site or LR:For(coreName), GuildOS.LootMaster and GuildOS.LootMaster:LootSettings(coreName).rollDuration)
        local function line(text)
            local fs = MakeLabel(body, text, SP.BODY, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 0, y)
            fs:SetWidth(W)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(true) end
            y = y - math.max(16, math.ceil(fs:GetStringHeight() or 16)) - 6
        end
        line(L["Who may ask."] .. " " .. d.who)
        line(L["How to ask."] .. " " .. d.how)
        line(L["Who takes it."] .. " " .. table.concat(d.order, " > "))
        if d.exceptions then line(L["Exceptions."] .. " " .. d.exceptions) end
        if site then line(L["This core's loot rule is set on guildos.me, which sends it with the raid's roster."]) end
        return -y
    end

    ----------------------------------------------------------------
    -- Config (officers): the format, the Discord core, the penalties, the raid leaders' ranks
    ----------------------------------------------------------------
    local function BuildConfig(coreName, body, W, track)
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
            local probe = MakeLabel(body, text, SP.BODY)
            widths[i] = probe:GetStringWidth() or 0
            probe:Hide()
        end
        local col = UI.LabelColumn(widths, 0, LABEL_GAP, LABEL_MIN)
        local y = 0
        -- A form's label: the left column, in the text colour, centred on its field's line.
        local function formLabel(text)
            local lbl = MakeLabel(body, text, SP.BODY, C.text.r, C.text.g, C.text.b)
            lbl:SetPoint("TOPLEFT", 0, y - 5)
            return lbl
        end

        y = MakeSectionHeader(body, L["General"], y)
        local curSize = CM:GetRaidSize(coreName)
        formLabel(L["Raid format:"])
        -- The Discord's size comes back at every import, so a core from the Discord only shows it (#135).
        if fromDiscord then
            local szText = MakeLabel(body, string.format(L["%d-man"], curSize) .. "  \194\183  " .. L["Managed on Discord."], SP.BODY)
            szText:SetPoint("TOPLEFT", col, y - 5)
        else
            -- This game's formats: 10 and 25 on TBC, 10, 20 and 40 on Forever (issue #89).
            local sizes = CM:RaidSizes()
            local function pick(size)
                CM:SetRaidSize(coreName, size)
                BuildSettings(coreName)
            end
            if #sizes > 2 then
                local dd = track(UI:CreateDropdown(body, 120, SP.FIELD))
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
                    local b = track(UI:CreateButton(body, string.format(L["%d-man"], size), 76, SP.FIELD))
                    b:SetPoint("TOPLEFT", x, y)
                    -- The format in force: the shared selection mark (#371).
                    UI:SetSelected(b, size == curSize)
                    b:SetScript("OnClick", function() pick(size) end)
                    x = x + b:GetWidth() + 6
                end
            end
        end
        y = y - SP.FORM_ROW

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
                local cur = MakeLabel(body, shown, SP.BODY, C.text.r, C.text.g, C.text.b)
                cur:SetPoint("TOPLEFT", col, y - 5)
            else
                local dd = track(UI:CreateDropdown(body, 180, SP.FIELD))
                dd:SetPoint("TOPLEFT", col, y)
                local opts = {}
                for i, c in ipairs(catalog) do opts[i] = { value = c.tag, text = c.name } end
                dd:SetOptions(opts)
                dd:SetValue(catalog[1].tag)
                dd.isDiscord = true
                local linkBtn = track(UI:CreateButton(body, L["Link"], 64, SP.FIELD))
                linkBtn:SetPoint("LEFT", dd, "RIGHT", 6, 0)
                linkBtn:SetScript("OnClick", function()
                    CM:LinkDiscord(coreName, dd:GetValue())
                    BuildSettings(coreName)
                end)
            end
            y = y - SP.FORM_ROW
        end

        -- The attendance penalties: each saves on its own, and says when it is saved.
        y = y + SP.FIELD_GAP
        y = MakeSectionHeader(body, L["Attendance Penalties"], y)
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
            local inp = track(MakeInput(body, 56, true))
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
            y = y - SP.FORM_ROW
        end
        local penNote = MakeLabel(body, L["Penalty values take effect on the next attendance rebuild."], SP.META)
        penNote:SetPoint("TOPLEFT", 0, y)
        y = y - 16 - SP.FIELD_GAP

        -- Raid Leader Ranks (who can manage core rosters)
        y = MakeSectionHeader(body, L["Raid Leader Ranks"], y)
        local rlNote = MakeLabel(body,
            L["Guild ranks below can add/remove members and accept sign-ups (officers always can)."], SP.BODY)
        rlNote:SetPoint("TOPLEFT", 0, y)
        rlNote:SetWidth(W)
        rlNote:SetJustifyH("LEFT")
        y = y - 18 - SP.FIELD_GAP
        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for ri = 1, numRanks do
            local rn = GuildControlGetRankName and GuildControlGetRankName(ri) or ("Rank " .. ri)
            if rn and rn ~= "" then
                -- Its box flush with the content's edge, as the labels above (#371).
                local rlCk = track(UI:CreateCheckbox(body, rn, 14))
                rlCk:SetPoint("TOPLEFT", 0, y - 2)
                rlCk.checkbox:SetChecked(CM:GetRaidLeaderRanks()[rn] == true)
                local captureRank = rn
                rlCk.checkbox.onChanged = function(_, checked)
                    CM:SetRaidLeaderRank(captureRank, checked and true or false)
                end
                y = y - SP.ROW
            end
        end
        return -y
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
            head:SetHeight(SP.PAD * 2 + 18 + 2 * SP.SECTION)
            rightContent:SetHeight(1)
            return
        end
        local function track(w) cfgWidgets[#cfgWidgets + 1] = w; return w end
        local hy = BuildHeader(coreName, track)
        head:SetHeight(BuildTabs(coreName, hy, track))
        local h
        if activeRightTab == "roster" then
            h = BuildRoster(coreName, track)
        else
            -- The other tabs: one card, the height left at least.
            local W = contentWidth()
            local card, body = cardAt("", 0, 0, W, track)
            local inner = W - 2 * SP.PAD
            local bh
            if activeRightTab == "signups" then
                bh = BuildRequests(coreName, body, inner, track)
            elseif activeRightTab == "rule" then
                bh = BuildRule(coreName, body, inner, track)
            else
                bh = BuildConfig(coreName, body, inner, track)
            end
            h = card:Fit(bh, rightScroll:GetHeight() or 0)
        end
        -- Resize content frame so scroll bar knows the full height
        rightContent:SetHeight(math.max(1, h))
    end

    ----------------------------------------------------------------
    -- Core list rebuild
    ----------------------------------------------------------------
    -- A core's row, made once by its place in the list and filled again on every rebuild (#449 review).
    local function coreRow(idx)
        local row = coreRows[idx]
        if row then return row end
        -- Hung by both top corners, as wide as the list leaves it (#371): the core's glyph, its name (the
        -- raid's with a badge saying so), and under it its size, fill and origin; a line between two.
        row = CreateFrame("Button", nil, listContent)
        row:SetHeight(CORE_ROW_H)
        local rule = row:CreateTexture(nil, "BACKGROUND")
        rule:SetTexture(WHITE)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT"); rule:SetPoint("TOPRIGHT")
        rule:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
        rule:SetShown(idx > 1)
        row.sel = UI:CreateRowSelection(row)
        local hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        hover:SetTexture(WHITE)
        hover:SetAllPoints()
        hover:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 0.07)
        hover:Hide()
        row.glyph = UI:CreateGlyph(row, 28)
        row.glyph:SetPoint("LEFT", 4, 0)
        local lbl = MakeLabel(row, "", SP.BODY, C.text.r, C.text.g, C.text.b)
        GuildOS:ApplyFont(lbl, SP.BODY, "memberName")
        lbl:SetPoint("TOPLEFT", 42, -9)
        lbl:SetJustifyH("LEFT")
        if lbl.SetWordWrap then lbl:SetWordWrap(false) end
        row.badge = UI:CreateBadge(row, L["active in the raid"], C.ok)
        row.badge:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        local sub = MakeLabel(row, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        sub:SetPoint("BOTTOMLEFT", 42, 9)
        sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        sub:SetJustifyH("LEFT")
        row.label, row.sub = lbl, sub
        row:SetScript("OnClick", function(self)
            selectedCore = self.coreName
            BuildSettings(self.coreName)
            RebuildList()
        end)
        row:SetScript("OnEnter", function() hover:Show() end)
        row:SetScript("OnLeave", function() hover:Hide() end)
        coreRows[idx] = row
        return row
    end

    RebuildList = function()
        local CM = GuildOS.CoreManager
        if not CM then
            for _, row in ipairs(coreRows) do row:Hide() end
            return
        end
        -- Each elenco with its groups under it (issue #352); a core with neither lists as always.
        local names = CM:SortedTree()
        local active = GetActiveName()
        for idx, entry in ipairs(names) do
            local name, indent = entry.name, entry.depth * GROUP_INDENT
            local row = coreRow(idx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", indent, -(idx - 1) * CORE_ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(idx - 1) * CORE_ROW_H)
            row.sel:SetShown(name == selectedCore)
            row.glyph:Set(UI.Initial and UI.Initial(name) or name:sub(1, 1), entry.depth > 0 and C.paperSoft or C.count)
            row.label:SetText(name)
            -- The raid's core reads as live: a green badge beside its name.
            row.badge:SetShown(name == active)
            local size = CM:GetRaidSize(name)
            local comp = CM:GetComposition(name)
            local subText = string.format(L["%d \194\183 %d of %d \194\183 %s"], size, comp.total, size, originOf(CM, name))
            local nGroups = #CM:GroupsOf(name)
            if entry.depth > 0 then
                subText = string.format(L["%d \194\183 %d of %d \194\183 group"], size, comp.total, size)
            elseif nGroups > 0 then
                subText = subText .. " \194\183 " .. string.format(L["split into %d groups"], nGroups)
            end
            row.sub:SetText(subText)
            row.coreName = name
            row:Show()
        end
        for idx = #names + 1, #coreRows do coreRows[idx]:Hide() end
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
            newInput:SetWidth(listW - 72 - 2 * SP.PAD)
            againBtn:SetWidth(listW - 2 * SP.PAD)
            RebuildList()
        end
        if selectedCore then BuildSettings(selectedCore) end
    end)

    -- Initial build
    noCoreLbl:Show()
end
