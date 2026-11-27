----------------------------------------------------------------------
-- Guild OS - Member Detail Panel
-- Shows full gear inspection, professions, and attunement details
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local DETAIL_WIDTH = 460
local DETAIL_HEIGHT = 620
local HEADER_H = 62    -- the card's header: the portrait, the name, the line under it and an alt's line
local PORTRAIT = 44
local TIMELINE_SHOWN = 8   -- entries of the officers' timeline (dated notes and trial comments) the sheet shows
local SP = UI.SP or GuildOS.Spacing   -- read at load only for PADX: a test loads this file alone for its stat cells
-- The parchment body (#449): the scroll frame sits SHEET_IN inside it and reaches SCROLL_IN from its right edge,
-- its bar inside that padding; the content's sections stand PADX in from the content's sides, so a section's text
-- is SHEET_IN + PADX (a card's padding, SP.PAD) from the sheet's left, and ends SP.PAD + the bar short of its right.
local SHEET_IN = 8
local SCROLL_IN = 4
local PADX = (SP and SP.PAD or 16) - SHEET_IN
local GEAR_ROW = 40       -- an equipment row: the slot, the 28px icon, the name over its enchant, the item level
local GEAR_SLOT_W = 72
local GEAR_ICON = 24      -- UI:CreateIcon's art; its quality frame is 4px more (28)
local GEAR_ILVL_W = 36
local SECTION_ROLE = "reading"   -- a section title's face: serif, in normal case (CreateSectionHeader)

-- The scroll child's width: the scroll frame's, as its anchors make it, less the bar and the padding it keeps
-- clear (the content's right edge SP.PAD + the bar's width from the sheet's).
local function ContentWidth(scroll)
    local w = UI:LaidWidth(scroll)
    if w < 1 then w = DETAIL_WIDTH - 2 * 8 - SHEET_IN - SCROLL_IN end
    -- The child ends SP.PAD - SCROLL_IN short of the scroll frame's right: its sections, PADX in from that,
    -- end SP.PAD + the bar's width (8) short of the sheet's edge; the bar, 2px inside the frame, is clear of them.
    return math.max(200, math.floor(w - (SP.PAD - SCROLL_IN)))
end

-- Static stat list — defined once at module level to avoid per-call allocation.
local STATS_LIST = {
    { label = L["HP"],  key = "health",    color = "green" },
    { label = L["MP"],  key = "mana",      color = "blue"  },
    { label = L["STR"], key = "strength"  },
    { label = L["AGI"], key = "agility"   },
    { label = L["STA"], key = "stamina"   },
    { label = L["INT"], key = "intellect" },
    { label = L["SPI"], key = "spirit"    },
}
-- Retail's sheet (issue #184): the spec's primary stat, named by which one it is, stamina and the
-- four ratings in percent. No spirit, and no mana bar for most specs.
local PRIMARY_LABEL = { strength = L["STR"], agility = L["AGI"], intellect = L["INT"] }
if GuildOS.Client.isRetail then
    STATS_LIST = {
        { label = L["HP"],      key = "health", color = "green" },
        { primary = true },
        { label = L["STA"],     key = "stamina" },
        { label = L["Crit"],    key = "crit",        pct = true },
        { label = L["Haste"],   key = "haste",       pct = true },
        { label = L["Mastery"], key = "mastery",     pct = true },
        { label = L["Vers"],    key = "versatility", pct = true },
    }
end

-- The stat cells a member's sheet draws, as { label, text, color }: the primary entry becomes the
-- stat the member sent (left out when they sent none), a rating reads in percent. A value the client
-- hid, or one from a guildmate's broadcast that is not a number, shows as "—": it is not a 0 (issue #170),
-- and it does not stop the sheet (issue #184).
function GuildOS:MemberStatCells(stats)
    local out = {}
    if type(stats) ~= "table" then return out end
    for _, s in ipairs(STATS_LIST) do
        local label, key = s.label, s.key
        if s.primary then label, key = PRIMARY_LABEL[stats.primary], stats.primary end
        if label then
            local v = tonumber(stats[key])
            out[#out + 1] = { label = label, text = v and (s.pct and string.format("%.1f%%", v) or tostring(v)) or "—", color = s.color }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Widget pool for PopulateDetail.
-- WoW FontStrings and Textures are never garbage-collected once created.
-- Without pooling, every member view permanently allocates ~200 new
-- FontStrings and ~25 Textures as children of the scroll child.
-- The pool caps growth at the high-water mark of the most complex
-- member ever shown, then reuses those objects for subsequent views.
----------------------------------------------------------------------
local function _pFS(parent)
    local p = parent._p
    p.fsCur = p.fsCur + 1
    local fs = p.fs[p.fsCur]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY")
        p.fs[p.fsCur] = fs
    end
    return fs
end

-- The card's body is parchment (#449): the sections draw with the wood's colours (a quality's, a class's, the
-- silver labels, the status reds and greens, the dark row bands), so after each fill every pooled text takes
-- the paper's shade of its colour (UI.PaperRGB) and of the codes in its string (UI:PaperText), and a dark band
-- becomes the paper's tan rule. A text drawn on a dark part (a talent bar's segment) keeps its own.
local function paperInks(child)
    local p = child._p
    if not p or not UI.PaperRGB then return end
    for _, fs in ipairs(p.fs) do
        if fs:IsShown() and not fs.__ownInk then
            local r, g, b, a = fs:GetTextColor()
            if r then
                local pr, pg, pb = UI.PaperRGB(r, g, b)
                fs:SetTextColor(pr, pg, pb, math.max(a or 1, 0.85))
            end
            local t = fs:GetText()
            if t and t:find("|c", 1, true) then fs:SetText(UI:PaperText(t, "paper")) end
        end
    end
    for _, tx in ipairs(p.bg) do
        if tx:IsShown() and not tx.__ownInk then
            local r, g, b, a = tx:GetVertexColor()
            if r and UI.Luminance(r, g, b) < 0.06 then
                tx:SetVertexColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, math.min(a or 1, 0.35))
            end
        end
    end
end

local function _pBG(parent)
    local p = parent._p
    p.bgCur = p.bgCur + 1
    local tx = p.bg[p.bgCur]
    if not tx then
        tx = parent:CreateTexture(nil, "BACKGROUND")
        p.bg[p.bgCur] = tx
    end
    return tx
end

-- The frames a fill lays (the talent bar, the stats grid, an item's icon and its gems, a tooltip's zone, a
-- progress bar), pooled by `kind` as the texts are (memory audit): a fill used to make them anew, for every
-- member opened and every redraw of the card. Each pooled frame comes back unanchored and shown; the fill hides
-- every child of the content first, so the ones it does not take stay hidden.
local function _pF(parent, kind, make)
    local p = parent._p
    local n = (p.frCur[kind] or 0) + 1
    p.frCur[kind] = n
    local list = p.fr[kind]
    if not list then list = {}; p.fr[kind] = list end
    local f = list[n]
    local reused = f ~= nil
    if f then f:ClearAllPoints() else f = make(); list[n] = f end
    f:Show()
    return f, reused
end

----------------------------------------------------------------------
-- The header's marks (#449): the founder's banner and the member's Guild OS crest (or its out-of-date warning)
-- after the name, the Members list's own marks (UI.RosterMarks) with its tooltips. The name gives way to them.
----------------------------------------------------------------------
local function LayHeaderMarks(frame, data, founder)
    local Marks = UI.RosterMarks
    local marks = frame.marks or {}
    for _, m in ipairs(marks) do m:Hide() end
    local kinds = {}
    if founder then kinds[#kinds + 1] = { "founder" } end
    if Marks and data.key and GetNumGuildMembers then
        local ok, scan = pcall(Marks.Scan)
        local mine = ok and scan and scan.byKey[data.key]
        if mine and (mine.status == "cur" or mine.status == "old") then
            kinds[#kinds + 1] = { mine.status, mine.version, scan.latest }
        end
    end
    local name = frame.nameText
    local maxW = (frame.nameMaxW and frame.nameMaxW > 0) and frame.nameMaxW or UI:LaidWidth(name)
    local room = math.max(40, maxW - #kinds * ((Marks and Marks.SIZE or 18) + SP.UNIT) - SP.UNIT)
    local textW = math.ceil((name.GetUnboundedStringWidth and name:GetUnboundedStringWidth()) or name:GetStringWidth() or 0)
    name:SetWidth(math.max(20, math.min(room, textW + 4)))
    local prev
    for i, k in ipairs(kinds) do
        local m = marks[i]
        if m then
            m:SetKind(k[1], k[2], k[3])
            m:ClearAllPoints()
            if prev then m:SetPoint("LEFT", prev, "RIGHT", SP.UNIT, 0)
            else m:SetPoint("LEFT", name, "RIGHT", SP.UNIT + 2, 0) end
            m:Show()
            prev = m
        end
    end
end

----------------------------------------------------------------------
-- The card's forms (#449, the Officers' Room's standard, UI/Forms.lua): a section is a block under its title,
-- its fields with their label above them on the paper's light fields, two side by side as a pair, and its
-- buttons at the block's bottom right, the primary one rightmost. The controls are made once for the panel's
-- life (kept) and laid again on each fill; the fill hides every child of the content first, and kept shows
-- the ones it lays.
----------------------------------------------------------------------
local function kept(child, name, make)
    child._kept = child._kept or {}
    local f = child._kept[name]
    if not f then f = make(); child._kept[name] = f end
    f:ClearAllPoints()
    f:Show()
    return f
end

-- A field: `label` above `control` (Forms:MakeField), laid at x, y and w wide. Returns its height.
local function placeField(child, name, label, control, x, y, w)
    local holder = kept(child, name .. ".field", function() return GuildOS.Forms:MakeField(child, label, control) end)
    holder:SetPoint("TOPLEFT", child, "TOPLEFT", x, y)
    control:Show()
    return holder:Place(w)
end

-- A pair of fields side by side (Forms' .row2), each half the row; one under the other when the row is narrow.
-- Returns the height.
local function placePair(child, a, b, y, width)
    local w = width - 2 * PADX
    if w >= GuildOS.Forms.PAIR_MIN then
        local aw = math.floor((w - SP.FIELD_GAP) / 2)
        return math.max(placeField(child, a[1], a[2], a[3], PADX, y, aw),
            placeField(child, b[1], b[2], b[3], PADX + aw + SP.FIELD_GAP, y, w - aw - SP.FIELD_GAP))
    end
    local ha = placeField(child, a[1], a[2], a[3], PADX, y, w)
    return ha + SP.FIELD_GAP + placeField(child, b[1], b[2], b[3], PADX, y - ha - SP.FIELD_GAP, w)
end

-- The block's buttons at its bottom right (Forms' card:Actions): the last one given rightmost (the primary),
-- wrapping to a new line when the row runs out. Laid `gap` (SP.FIELD_GAP) under `yOff`; returns the new yOff.
local function placeActions(child, buttons, yOff, width, gap)
    local gx = 2 * SP.UNIT
    local right = width - PADX
    local x, y, rowH = right, yOff - (gap or SP.FIELD_GAP), 0
    for i = #buttons, 1, -1 do
        local b = buttons[i]
        local bw = b:GetWidth() or 60
        if x < right and x - bw < PADX then y, x, rowH = y - rowH - gx, right, 0 end
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", child, "TOPLEFT", x, y)
        b:Show()
        x = x - bw - gx
        rowH = math.max(rowH, b:GetHeight() or SP.FIELD)
    end
    return y - rowH
end

-- The guild roster once per fill: byKey[key] = { name, class (its file), rank }, and the names in roster order.
local function RosterIndex()
    local idx = { byKey = {}, names = {} }
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return idx end
    for i = 1, GetNumGuildMembers() or 0 do
        local full, rank, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if type(full) == "string" and full ~= "" then
            local short = full:match("^([^-]+)") or full
            local key = GuildOS:GetPlayerKey(short, full:match("-(.+)$") or GetRealmName())
            if key then
                idx.byKey[key] = { name = short, class = classFile, rank = rank }
                idx.names[#idx.names + 1] = { name = short, key = key }
            end
        end
    end
    return idx
end

-- The first character of the roster whose name starts with `typed` (any case), not one of `taken` (keys):
-- the Add alt field's suggestion. Nil under two letters or with none.
local function SuggestCharacter(roster, typed, taken)
    typed = (typed or ""):lower()
    if #typed < 2 then return nil end
    local best
    for _, n in ipairs(roster.names) do
        if not taken[n.key] and n.name:lower():sub(1, #typed) == typed then
            if not best or n.name < best then best = n.name end
        end
    end
    return best
end

-- A link on a row (the mockup's underlined word): the paper's link ink, sized to its label.
local function rowLink(parent, text)
    local b = UI:SetButtonVariant(UI:CreateButton(parent, text, 40, SP.HIT), "ghost")
    b:SetWidth(math.ceil(b.label:GetStringWidth() or 30) + 6)
    return b
end

-- A text in the paper's ink `c` (paperInk unless given), kept from paperInks' remapping.
local function ink(fs, c, a)
    c = c or C.paperInk
    fs:SetTextColor(c.r, c.g, c.b, a or 1)
    fs.__ownInk = true
    return fs
end
-- A status colour of the wood (a green, a red) as the paper reads it.
local function paperInk(c) return UI:Ink("paper", c) end

----------------------------------------------------------------------
-- Create an invisible tooltip hover zone over a region
-- anchor: FontString or Frame to overlay
-- link: itemLink string OR itemId number
-- w, h: optional size override (defaults to anchor size)
----------------------------------------------------------------------
local function zoneEnter(self)
    local link = self.link
    if not link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(link) == "number" then
        GameTooltip:SetHyperlink("item:" .. link)
    else
        GameTooltip:SetHyperlink(link)
    end
    GameTooltip:Show()
end
local function CreateItemTooltipZone(parent, anchor, link, w, h)
    if not link then return end
    local function make()
        local z = CreateFrame("Frame", nil, parent)
        z:EnableMouse(true)
        z:SetScript("OnEnter", zoneEnter)
        z:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return z
    end
    -- Pooled with the card's other frames when the card has its pool (PopulateDetail), else made.
    local zone = parent._p and parent._p.fr and _pF(parent, "tipZone", make) or make()
    zone:SetAllPoints(anchor)
    if w and h then
        zone:SetSize(w, h)
    end
    zone.link = link
    zone:Show()
    return zone
end

----------------------------------------------------------------------
-- Show member detail panel
----------------------------------------------------------------------
-- `focus` "alt": the cursor in the Add alt box (the data audit's "Link alt…"), when the card draws it.
function GuildOS:ShowMemberDetail(memberData, focus)
    if not memberData then return end

    local frame = self.DetailFrame
    if not frame then
        frame = CreateDetailFrame()
        self.DetailFrame = frame
    end

    PopulateDetail(frame, memberData)
    frame:Show()
    if focus == "alt" then
        local held = frame.content and rawget(frame.content, "_kept")
        local box = held and held["alt.add"]
        if box and box:IsShown() and box.SetFocus then box:SetFocus() end
    end
end

----------------------------------------------------------------------
-- Create the detail frame
----------------------------------------------------------------------
function CreateDetailFrame()
    -- The mockup's floating member card (#449): Kit:Dress's metal frame and dark body, a taller brown header
    -- with the member's round portrait, the name in Cinzel in the class's colour, the level, race, class and rank under it and,
    -- for a linked alt, whose alt it is; the round red close.
    local frame = CreateFrame("Frame", "GuildOSDetailFrame", UIParent, "BackdropTemplate")
    frame:SetSize(DETAIL_WIDTH, DETAIL_HEIGHT)
    frame:SetPoint("CENTER", 250, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(20)
    frame:Hide()
    local Kit = GuildOS.Kit
    Kit:Dress(frame, "", { headerH = HEADER_H, lead = PORTRAIT, stack = true })

    local avatar = UI:CreateAvatar(frame.header.lead, PORTRAIT, false)
    avatar:SetPoint("CENTER", 0, 0)
    avatar:EnableMouse(false)
    frame.avatar = avatar

    frame.nameText = frame.titleText
    GuildOS:ApplyFont(frame.nameText, 17, "windowTitle")
    frame.nameMaxW = UI:LaidWidth(frame.nameText)
    frame.infoText = frame.subText
    frame.altTagText = frame.header.extra
    -- The marks after the name, as the Members list draws them (UI.RosterMarks: the founder's banner, the Guild OS
    -- crest or its out-of-date warning), each with the list's tooltip.
    local Marks = UI.RosterMarks
    frame.marks = Marks and { Marks.Create(frame.header), Marks.Create(frame.header) } or {}
    for _, m in ipairs(frame.marks) do m:Hide() end

    -- An item the client had not cached draws from what the member sent, with its icon from the item's id; when
    -- the client's answer arrives the card draws again (once per burst, never under the officer's typing).
    GuildOS.Compat.RegisterEvent(frame, "GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(self)
        if not self._itemsPending or not self:IsShown() then return end
        GuildOS:Coalesce("memberDetail.items", 1, function()
            if not self._itemsPending or not self:IsShown() or not self._data then return end
            local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
            if focus and focus.IsVisible and focus:IsVisible() then return end
            PopulateDetail(self, self._data)
        end)
    end)

    ----------------------------------------------------------------
    -- Content scroll
    ----------------------------------------------------------------
    -- The body is a parchment sheet in the dark frame (the mockup's member card): every text on it takes the
    -- paper's inks (paperInks, after each fill), the controls the paper's look; the slim scrollbar inside it.
    local sheet = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sheet:SetPoint("TOPLEFT", 8, -(HEADER_H + 4))
    sheet:SetPoint("BOTTOMRIGHT", -8, 8)
    GuildOS.Style:Paint(sheet, "paper")
    sheet.__paper = true
    frame.sheet = sheet
    -- The scroll frame reaches into the sheet's right padding, where its bar sits (UI:SkinScrollBar puts it 2px
    -- inside the frame's right edge): the content ends a card's padding plus the bar short of the sheet's edge
    -- (ContentWidth), so nothing (an item level, a row's rule) runs under the bar.
    local content = CreateFrame("ScrollFrame", "GuildOSDetailScroll", sheet, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", SHEET_IN, -SHEET_IN)
    content:SetPoint("BOTTOMRIGHT", -SCROLL_IN, SHEET_IN)
    UI:SkinScrollBar(content, "GuildOSDetailScroll")

    local child = CreateFrame("Frame", "GuildOSDetailScrollChild", content)
    child:SetWidth(ContentWidth(content))
    child:SetHeight(1) -- will grow
    content:SetScrollChild(child)
    frame.content = child

    table.insert(UISpecialFrames, "GuildOSDetailFrame")

    return frame
end

----------------------------------------------------------------------
-- Populate detail with member data
----------------------------------------------------------------------
function PopulateDetail(frame, data)
    local child = frame.content
    frame._sheetRedraw = nil   -- set again below when this member's card has the officers' sheet
    -- Initialise or reset the FontString/Texture pool. Pooled objects are
    -- hidden and their cursors reset so the current populate reuses them
    -- in order rather than accumulating fresh C-level objects each call.
    if not child._p then
        child._p = { fs = {}, bg = {}, fsCur = 0, bgCur = 0, fr = {}, frCur = {} }
    end
    local p = child._p
    p.fr, p.frCur = p.fr or {}, {}
    for _, fs in ipairs(p.fs) do
        fs:Hide(); fs:ClearAllPoints(); fs:SetText(""); fs:SetWidth(0); fs:SetWordWrap(false); fs:SetJustifyH("LEFT"); fs.__ownInk = nil
    end
    for _, tx in ipairs(p.bg) do tx:Hide(); tx:ClearAllPoints(); tx.__ownInk = nil end
    p.fsCur, p.bgCur = 0, 0
    frame._data, frame._itemsPending = data, nil
    -- Hide non-pooled child frames (Buttons, EditBoxes, plain Frames created
    -- by interactive sections such as alt-links and trial notes).
    local children = { child:GetChildren() }
    for _, c in ipairs(children) do c:Hide() end

    -- Reset scroll position so switching members always starts at the top.
    child:GetParent():SetVerticalScroll(0)

    -- The round portrait in the class's colour, the name in Cinzel in the class's colour (the mockup's card).
    local cr, cg, cb = GuildOS:GetClassColor(data.class)
    frame.avatar:SetMember(data.name, data.class and tostring(data.class):upper())
    local founder = GuildOS.Founding and data.key and GuildOS.Founding:Founders()[data.key]
    GuildOS:SetTitleText(frame.nameText, data.name)
    frame.nameText:SetTextColor(cr, cg, cb)   -- the name in the class's colour on the dark header (the mockup)
    LayHeaderMarks(frame, data, founder)

    -- Info line
    -- Defence in depth: string.format on a nil takes the WHOLE panel down, and
    -- these two fields come from the live roster rather than the synced member
    -- data, so any caller holding only a db.members entry would crash here.
    -- GuildOS:GetMemberRecord builds the correct merged record; this is the net
    -- under it, not a substitute for it.
    local raceStr = (data.race and data.race ~= "") and data.race or L["Unknown"]
    local infoLine = string.format(L["Level %d %s %s  |  %s"],
        data.level or 0, raceStr, data.classDisplay or data.class or "?", data.rank or "?")
    -- The parts with the card's " · " between them (#449), whatever bar the translation put there.
    infoLine = infoLine:gsub("%s*|%s+", " \194\183 ")
    -- Cross-addon presence: append which sibling Chehul addons this player is
    -- currently broadcasting on the mesh (e.g. "· PartyLens"). Empty if none.
    if GuildOS.Mesh then
        infoLine = infoLine .. GuildOS.Mesh:PresenceSuffix(data.name)
    end
    frame.infoText:SetText(infoLine)

    -- The line under it: since when a founder is one, and whose alt this is (nil unless linked to a main).
    local memberKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
    local extra = {}
    if founder then
        extra[#extra + 1] = string.format(L["Founding member · joined %s"], date("!%Y-%m-%d", founder.joinedAt))
    end
    local altTag = GuildOS.GetAltTag and GuildOS:GetAltTag(memberKey)
    if altTag and altTag ~= "" then extra[#extra + 1] = altTag end
    frame.altTagText:SetText(table.concat(extra, " \194\183 "))

    local yOff = -4
    local contentWidth = ContentWidth(child:GetParent())
    child:SetWidth(contentWidth)

    ----------------------------------------------------------------
    -- Section: Spec
    ----------------------------------------------------------------
    local playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
    local specLabel = GuildOS.SpecChecker and GuildOS.SpecChecker:GetSpecLabel(playerKey)

    yOff = CreateSectionHeader(child, L["Talent spec"], yOff, contentWidth)

    local spec = GuildOS.db.members and GuildOS.db.members[playerKey] and GuildOS.db.members[playerKey].spec
    -- A scan that counted no point (a tree's name and a lone 0: the talents never read) is no scan (#449).
    local scanned = specLabel ~= nil
    if scanned and spec and not spec.specID then
        local total = 0
        for _, pts in ipairs(spec.points or {}) do total = total + (tonumber(pts) or 0) end
        scanned = total > 0
    end
    local barW = contentWidth - 2 * PADX

    if scanned then
        -- Talent distribution bar (one segment per tree; clickable to view tree)
        if spec and spec.points and spec.names then
            local barFrame = _pF(child, "talentBar", function()
                local b = CreateFrame("Button", nil, child)
                b:RegisterForClicks("LeftButtonUp")
                -- The light track under the trees (#449): the paper's field.
                b.track = b:CreateTexture(nil, "ARTWORK")
                b.track:SetTexture("Interface\\Buttons\\WHITE8x8")
                b.track:SetPoint("TOPLEFT", 0, 0)
                b.track:SetVertexColor(C.paperLight.r, C.paperLight.g, C.paperLight.b, 1)
                b.segs, b.labels, b.divs = {}, {}, {}
                return b
            end)
            barFrame:SetPoint("TOPLEFT", PADX, yOff)
            barFrame:SetSize(barW, 20)
            for _, list in ipairs({ barFrame.segs, barFrame.labels, barFrame.divs }) do
                for _, part in ipairs(list) do part:Hide() end
            end
            barFrame:SetScript("OnClick", nil)
            barFrame:SetScript("OnEnter", nil)
            barFrame:SetScript("OnLeave", nil)
            if spec.talents then
                barFrame:SetScript("OnClick", function()
                    local freshSpec = GuildOS.db.members[playerKey]
                        and GuildOS.db.members[playerKey].spec
                    GuildOS:ShowTalentViewer(freshSpec or spec, data.name, data.class)
                end)
                barFrame:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(L["Click to view talent tree"], 1, 1, 0.6)
                    GameTooltip:Show()
                end)
                barFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            barFrame:Show()

            barFrame.track:SetSize(barW, 18)

            local total = 0
            for _, pts in ipairs(spec.points) do total = total + pts end
            if total == 0 then total = 1 end

            -- The trees in soft cuts of the class's paper ink (#449): washed toward the light field, so the
            -- paper's ink reads on every one of them.
            local ir, ig, ib = UI:InkFor("paper", "class", data.class)
            local function mix(t)
                return { r = ir + (C.paperLight.r - ir) * t, g = ig + (C.paperLight.g - ig) * t, b = ib + (C.paperLight.b - ib) * t }
            end
            local treeColors = { mix(0.55), mix(0.75), { r = C.paperLine.r, g = C.paperLine.g, b = C.paperLine.b } }

            local BAR_W = barW
            local xPos = 0
            local nonZero = 0
            for _, pts in ipairs(spec.points) do if pts > 0 then nonZero = nonZero + 1 end end

            local drawn, nDivs = 0, 0
            for i, pts in ipairs(spec.points) do
                if pts > 0 then
                    drawn = drawn + 1
                    -- Last drawn segment gets the remainder to absorb rounding drift.
                    local segW
                    if drawn == nonZero then
                        segW = BAR_W - xPos
                    else
                        segW = math.floor((pts / total) * BAR_W + 0.5)
                    end

                    -- Segment fill
                    local seg = barFrame.segs[drawn]
                    if not seg then
                        seg = barFrame:CreateTexture(nil, "OVERLAY")
                        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
                        barFrame.segs[drawn] = seg
                    end
                    seg:ClearAllPoints()
                    seg:SetPoint("TOPLEFT", xPos, 0)
                    seg:SetSize(segW, 18)
                    local tc = treeColors[i] or treeColors[1]
                    seg:SetVertexColor(tc.r, tc.g, tc.b, 1)
                    seg:Show()

                    -- Label clipped to segment width; text adapts to available space
                    local segLabel = barFrame.labels[drawn]
                    if not segLabel then
                        segLabel = barFrame:CreateFontString(nil, "OVERLAY")
                        GuildOS:ApplyFont(segLabel, UI.SP.META)
                        barFrame.labels[drawn] = segLabel
                    end
                    segLabel:ClearAllPoints()
                    segLabel:SetPoint("TOPLEFT", xPos + 4, -1)
                    segLabel:SetSize(math.max(1, segW - 8), 18)
                    segLabel:SetJustifyH("CENTER")
                    segLabel:SetJustifyV("MIDDLE")
                    segLabel:SetWordWrap(false)
                    segLabel:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b, 1)   -- the paper's ink on every tree
                    if segW >= 55 then
                        segLabel:SetText(pts .. "  " .. (spec.names[i] or ""))
                    elseif segW >= 22 then
                        segLabel:SetText(tostring(pts))
                    else
                        segLabel:SetText("")
                    end
                    segLabel:Show()

                    -- 1-px divider before each segment except the first
                    if xPos > 0 then
                        nDivs = nDivs + 1
                        local div = barFrame.divs[nDivs]
                        if not div then
                            div = barFrame:CreateTexture(nil, "OVERLAY")
                            div:SetTexture("Interface\\Buttons\\WHITE8x8")
                            div:SetHeight(18)
                            GuildOS.UI:Hairline(div, "Width")
                            div:SetVertexColor(C.paperLight.r, C.paperLight.g, C.paperLight.b, 1)
                            barFrame.divs[nDivs] = div
                        end
                        div:ClearAllPoints()
                        div:SetPoint("TOPLEFT", xPos, 0)
                        div:Show()
                    end

                    xPos = xPos + segW
                end
            end
            yOff = yOff - 26
        end

        -- Text label: e.g.  "41 / 5 / 15  (Protection)"
        local specText = _pFS(child)
        GuildOS:ApplyFont(specText, SP.BODY)
        specText:SetPoint("TOPLEFT", PADX, yOff)
        specText:SetJustifyH("LEFT")
        local sr, sg, sb = UI:InkFor("paper", "class", data.class)
        ink(specText, { r = sr, g = sg, b = sb })
        specText:SetText(specLabel)
        specText:Show()
        yOff = yOff - 20

        if spec and spec.scannedAt and spec.scannedAt > 0 then
            local age = GetServerTime() - spec.scannedAt
            local ageStr
            if age < 3600 then
                ageStr = math.floor(age / 60) .. L["m ago"]
            elseif age < 86400 then
                ageStr = math.floor(age / 3600) .. L["h ago"]
            else
                ageStr = math.floor(age / 86400) .. L["d ago"]
            end
            local scanText = _pFS(child)
            GuildOS:ApplyFont(scanText, UI.SP.META)
            scanText:SetPoint("TOPLEFT", PADX, yOff)
            scanText:SetJustifyH("LEFT")
            ink(scanText, C.paperSoft)
            scanText:SetText(L["Last scanned: "] .. ageStr)
            scanText:Show()
            yOff = yOff - 18
        end
    else
        local noSpec = _pFS(child)
        GuildOS:ApplyFont(noSpec, UI.SP.META)
        noSpec:SetPoint("TOPLEFT", PADX, yOff)
        noSpec:SetWidth(barW)
        noSpec:SetJustifyH("LEFT")
        noSpec:SetWordWrap(true)
        ink(noSpec, C.paperSoft)
        -- A scan that counted nothing says so; a member never read, how to read them.
        noSpec:SetText(specLabel and L["No talent scan yet"] or L["No spec data. Use /guildos specs to scan the group."])
        noSpec:Show()
        yOff = yOff - (math.ceil(noSpec:GetStringHeight() or 14) + 8)
    end

    yOff = yOff - 8

    ----------------------------------------------------------------
    -- Section: Stats
    ----------------------------------------------------------------
    if data.stats then
        yOff = CreateSectionHeader(child, L["Character stats"], yOff, contentWidth)

        local statsGrid = _pF(child, "statsGrid", function() return CreateFrame("Frame", nil, child) end)
        statsGrid:SetPoint("TOPLEFT", PADX, yOff)
        statsGrid:SetSize(contentWidth - 2 * PADX, 40)
        statsGrid:Show()

        local colWidth = (contentWidth - 2 * PADX) / 4
        for i, stat in ipairs(GuildOS:MemberStatCells(data.stats)) do
            local col = ((i - 1) % 4)
            local row = math.floor((i - 1) / 4)
            -- The label in the paper's soft ink, the value in its ink (a health or mana value in the paper's
            -- cut of its colour).
            local sc = stat.color and paperInk(C[stat.color]) or C.paperInk

            local label = _pFS(child)
            GuildOS:ApplyFont(label, UI.SP.META)
            label:SetPoint("TOPLEFT", statsGrid, "TOPLEFT", col * colWidth, -(row * 20))
            ink(label, C.paperSoft)
            label:SetText(stat.label)
            label:Show()

            local value = _pFS(child)
            GuildOS:ApplyFont(value, SP.META)
            value:SetPoint("LEFT", label, "RIGHT", 4, 0)
            ink(value, sc)
            value:SetText(stat.text)
            value:Show()
        end

        yOff = yOff - 48
        -- None of the attributes came through: the sender's game hid them (WoW: Forever's Secret Values) or they
        -- were never sent. Say so instead of a row of dashes (#449).
        local st = data.stats
        if not (tonumber(st.strength) or tonumber(st.agility) or tonumber(st.stamina) or tonumber(st.intellect)
                or tonumber(st.spirit) or tonumber(st[st.primary or ""])) then
            local why = _pFS(child)
            GuildOS:ApplyFont(why, UI.SP.META)
            why:SetPoint("TOPLEFT", PADX, yOff + 18)
            why:SetWidth(contentWidth - 2 * PADX)
            why:SetJustifyH("LEFT")
            ink(why, C.paperSoft)
            why:SetText(L["The attributes did not come through: the game hides them on this client while it restricts data (WoW: Forever). They fill in when the member syncs without that restriction."])
            why:Show()
            yOff = yOff - 6
        end
    end

    ----------------------------------------------------------------
    -- Section: Mythic+ and the Great Vault (retail, issue #187): what the member's own client sent.
    -- A guildmate without Guild OS sent nothing, and has no section.
    ----------------------------------------------------------------
    local MP = GuildOS.MythicPlus
    if MP and (type(data.mplus) == "table" or type(data.vault) == "table") then
        local function cell(label, text, x, y, color)
            local l = _pFS(child)
            GuildOS:ApplyFont(l, UI.SP.META)
            l:SetPoint("TOPLEFT", x, y)
            ink(l, C.paperSoft)
            l:SetText(label)
            l:Show()
            local v = _pFS(child)
            GuildOS:ApplyFont(v, SP.META)
            v:SetPoint("LEFT", l, "RIGHT", 4, 0)
            ink(v, color and paperInk(color) or C.paperInk)
            v:SetText(text)
            v:Show()
        end

        yOff = CreateSectionHeader(child, L["Mythic+"], yOff, contentWidth)
        local rating = MP:Rating(data.mplus)
        local r, g, b = GuildOS.Compat.RatingColor(rating)
        cell(L["Rating"], rating and tostring(rating) or "\226\128\148", PADX, yOff, r and { r = r, g = g, b = b } or C.gold)
        cell(L["Keystone"], MP:KeystoneText(data.mplus) or L["none"], PADX + (contentWidth - 2 * PADX) / 3, yOff)
        yOff = yOff - 26

        yOff = CreateSectionHeader(child, L["Great Vault"], yOff, contentWidth)
        local cells, why = MP:VaultCells(data.vault, GuildOS.Compat.WeekStart())
        if cells then
            for i, c in ipairs(cells) do
                cell(c.label, c.text, PADX + (i - 1) * (contentWidth - 2 * PADX) / 3, yOff)
            end
        else
            local none = _pFS(child)
            GuildOS:ApplyFont(none, 11)
            none:SetPoint("TOPLEFT", PADX, yOff)
            ink(none, C.paperSoft)
            none:SetText(why == "old" and L["Not updated since the weekly reset."] or L["No vault data yet."])
            none:Show()
        end
        yOff = yOff - 26
    end

    ----------------------------------------------------------------
    -- Section: Equipment
    ----------------------------------------------------------------
    -- The average item level as the title's soft meta at its right (#449).
    local avgMeta = (data.avgIlvl and data.avgIlvl > 0) and string.format(L["Average item level %d"], data.avgIlvl) or nil
    yOff = CreateSectionHeader(child, L["Equipment"], yOff, contentWidth, avgMeta)

    if data.gear then
        -- Fixed rows, a rule only between two of them.
        for i, slotInfo in ipairs(GuildOS.SlotIDs) do
            local item = data.gear[slotInfo.id]
            if CreateGearRow(child, slotInfo.id, item, yOff, contentWidth, i > 1) then frame._itemsPending = true end
            yOff = yOff - GEAR_ROW
        end
    else
        local noData = _pFS(child)
        GuildOS:ApplyFont(noData, 11)
        noData:SetPoint("TOPLEFT", PADX, yOff)
        ink(noData, C.paperSoft)
        noData:SetText(L["No gear data available. Player needs Guild OS addon."])
        noData:Show()
        yOff = yOff - 25
    end

    ----------------------------------------------------------------
    -- Section: Professions
    ----------------------------------------------------------------
    yOff = yOff - 10
    yOff = CreateSectionHeader(child, L["Professions"], yOff, contentWidth)
    yOff = yOff - 5

    if data.professions and #data.professions > 0 then
        for _, prof in ipairs(data.professions) do
            yOff = CreateProfessionRow(child, prof, yOff, contentWidth)
        end
    else
        local noData = _pFS(child)
        GuildOS:ApplyFont(noData, 11)
        noData:SetPoint("TOPLEFT", PADX, yOff)
        ink(noData, C.paperSoft)
        noData:SetText(L["No profession data available."])
        noData:Show()
        yOff = yOff - 25
    end

    ----------------------------------------------------------------
    -- Section: Attunements (account-wide propagation from linked chars).
    -- TBC content: only on TBC Anniversary (ADR-0014).
    ----------------------------------------------------------------
    if GuildOS.Client.isAnniversary then
        yOff = yOff - 10
        yOff = CreateSectionHeader(child, L["Raid attunements"], yOff, contentWidth)
        yOff = yOff - 5

        local attsToShow
        if GuildOS.AttunementTracker then
            attsToShow = GuildOS.AttunementTracker:GetEffectiveAttunements(playerKey)
        else
            attsToShow = data.attunements
        end

        if attsToShow and #attsToShow > 0 then
            for _, att in ipairs(attsToShow) do
                yOff = CreateAttunementRow(child, att, yOff, contentWidth)
            end
        else
            local noData = _pFS(child)
            GuildOS:ApplyFont(noData, 11)
            noData:SetPoint("TOPLEFT", PADX, yOff)
            ink(noData, C.paperSoft)
            noData:SetText(L["No attunement data available."])
            noData:Show()
            yOff = yOff - 25
        end
    end

    ----------------------------------------------------------------
    -- Section: Wishlist (nativa)
    ----------------------------------------------------------------
    -- By the whole key on retail, where a list is filed under it (issue #185).
    local wishData = GuildOS.Wishlist and GuildOS.Wishlist:ListFor(playerKey, data.name)
    if wishData and wishData.wishlist and #wishData.wishlist > 0 then
        yOff = yOff - 10
        local wishHeader = L["Wishlist"] .. " · " .. #wishData.wishlist .. L[" item(s)"]
        yOff = CreateSectionHeader(child, wishHeader, yOff, contentWidth)
        yOff = yOff - 5

        for _, item in ipairs(wishData.wishlist) do
            local qColor = C.white
            if GuildOS.Wishlist and GuildOS.QualityColors then
                local q = GuildOS.Wishlist:GetItemQuality(item.itemId)
                qColor = GuildOS.QualityColors[q] or C.white
            end
            local localName = GuildOS.Wishlist and GuildOS.Wishlist:GetItemName(item.itemId) or (L["Item #"] .. (item.itemId or "?"))
            local osStr = item.isOffspec and " |cffAAAAAA(OS)|r" or ""
            local itemStr = _pFS(child)
            GuildOS:ApplyFont(itemStr, UI.SP.META)
            itemStr:SetPoint("TOPLEFT", 20, yOff)
            itemStr:SetWidth(contentWidth - 2 * PADX)
            itemStr:SetJustifyH("LEFT")
            itemStr:SetWordWrap(false)
            itemStr:SetTextColor(qColor.r, qColor.g, qColor.b)
            itemStr:SetText(string.format("#%d %s%s", item.order or 0, localName, osStr))
            itemStr:Show()
            CreateItemTooltipZone(child, itemStr, item.itemId)
            yOff = yOff - 15
        end
    end

    ----------------------------------------------------------------
    -- Section: Raid Attendance
    ----------------------------------------------------------------
    if GuildOS.RaidTracker then
        yOff = yOff - 10
        playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        -- The core with the most nights that count, as the roster's figure (#134); with none anywhere
        -- (not even nights with no core), the one with the most raids.
        local playerGroup  = GuildOS.RaidTracker:GetPlayerGroup(playerKey, "raids25")
        if playerGroup == "" and (GuildOS.RaidTracker:GetAttendance(playerKey, "").raids25 or 0) == 0 then
            playerGroup = GuildOS.RaidTracker:GetPlayerGroup(playerKey)
        end
        local att          = GuildOS.RaidTracker:GetAttendance(playerKey, playerGroup)
        local pct          = GuildOS.RaidTracker:GetAttendance25ManPercent(playerKey, playerGroup)
        local total25      = GuildOS.RaidTracker:GetTotal25ManSessions(playerGroup)
        local raids25      = att.raids25 or 0
        local groupSuffix  = playerGroup ~= "" and ("  [" .. playerGroup .. "]") or ""
        local attStr = string.format(GuildOS.RaidTracker:ProgLabel(L["Raid attendance%s · %d%% (%d/%d raids, 25-man)"]),
            groupSuffix, pct, raids25, total25)
        yOff = CreateSectionHeader(child, attStr, yOff, contentWidth)

        if att.lastRaid > 0 then
            local lastStr = _pFS(child)
            GuildOS:ApplyFont(lastStr, UI.SP.META)
            lastStr:SetPoint("TOPLEFT", PADX, yOff - 5)
            ink(lastStr, C.paperSoft)
            lastStr:SetText(L["Last raid: "] .. GuildOS:DateText(att.lastRaid, "/%Y"))
            lastStr:Show()
            yOff = yOff - 20
        end
    end

    ----------------------------------------------------------------
    -- Section: Loot History
    ----------------------------------------------------------------
    if GuildOS.LootTracker then
        yOff = yOff - 10
        playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        local lootCount = GuildOS.LootTracker:GetLootCount(playerKey)
        local lootHeader = L["Loot history"] .. " · " .. lootCount .. L[" items"]
        yOff = CreateSectionHeader(child, lootHeader, yOff, contentWidth)

        local recentLoot = GuildOS.LootTracker:GetPlayerLoot(playerKey, 5)
        for _, entry in ipairs(recentLoot) do
            local qColor = GuildOS.QualityColors[entry.quality] or GuildOS.QualityColors[1]
            local itemStr = _pFS(child)
            GuildOS:ApplyFont(itemStr, UI.SP.META)
            itemStr:SetPoint("TOPLEFT", PADX, yOff - 5)
            itemStr:SetWidth(contentWidth - 2 * PADX)
            itemStr:SetJustifyH("LEFT")
            itemStr:SetWordWrap(false)
            -- Resolve item name via GetItemInfo for correct client locale.
            -- GetItemInfo accepts itemLink directly, so no need to parse the ID.
            local localItemName = GuildOS.Compat.GetItemInfo(entry.itemLink or entry.itemId or 0)
            local displayName = localItemName or entry.itemName or "?"
            local dateStr = entry.timestamp and (" |cffAAAAAA" .. GuildOS:DateText(entry.timestamp) .. "|r") or ""
            local raidStr = entry.raid and entry.raid ~= "" and (" |cff888888(" .. entry.raid .. ")|r") or ""
            itemStr:SetText(string.format("|cff%02x%02x%02x%s|r%s%s",
                qColor.r * 255, qColor.g * 255, qColor.b * 255,
                displayName, raidStr, dateStr))
            itemStr:Show()
            if entry.itemLink then
                CreateItemTooltipZone(child, itemStr, entry.itemLink)
            end
            yOff = yOff - 15
        end
        if lootCount == 0 then
            yOff = yOff - 5
        end
    end

    ----------------------------------------------------------------
    -- Section: Trial Status (officer only)
    ----------------------------------------------------------------
    if GuildOS.TrialTracker and GuildOS:IsOfficer() then
        playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        local trial = GuildOS.TrialTracker:GetTrial(playerKey)
        if trial then
            yOff = yOff - 10
            local daysRem = GuildOS.TrialTracker:GetDaysRemaining(playerKey)
            local daysSince = GuildOS.TrialTracker:GetDaysSinceStart(playerKey)
            -- The state worked out from the start and the guild's length, not the word stored (#249).
            local state = GuildOS.TrialTracker:GetState(playerKey)
            local stateText = ({ trial = L["Trial"], review = L["Ready to review"], left = L["Left the guild"],
                approved = L["Approved"], denied = L["Denied"] })[state] or tostring(trial.status or "?")
            local trialStr = L["Trial status"] .. " · " .. stateText
            if daysRem and state == "trial" then trialStr = trialStr .. "  (" .. daysRem .. L[" days left)"] end
            yOff = CreateSectionHeader(child, trialStr, yOff, contentWidth)

            local infoStr = _pFS(child)
            GuildOS:ApplyFont(infoStr, UI.SP.META)
            infoStr:SetPoint("TOPLEFT", PADX, yOff - 5)
            ink(infoStr, C.paperSoft)
            infoStr:SetText(L["Sponsor: "] .. (trial.sponsor or "?") .. L["  |  Day "] .. (daysSince or 0))
            infoStr:Show()
            yOff = yOff - 20

            -- Progress tracking
            local progress = GuildOS.TrialTracker:GetProgress(playerKey)
            if progress then
                -- iLvl progress
                local ilvlColor = progress.ilvlDelta > 0 and C.green or (progress.ilvlDelta < 0 and C.red or C.silver)
                local ilvlSign = progress.ilvlDelta > 0 and "+" or ""
                local ilvlStr = format(L["iLvl: %d >> %d  (%s%d)"], progress.startIlvl, progress.currentIlvl, ilvlSign, progress.ilvlDelta)
                local ilvlText = _pFS(child)
                GuildOS:ApplyFont(ilvlText, UI.SP.META)
                ilvlText:SetPoint("TOPLEFT", PADX, yOff - 3)
                ilvlText:SetTextColor(ilvlColor.r, ilvlColor.g, ilvlColor.b)
                ilvlText:SetText(ilvlStr)
                ilvlText:Show()

                -- Attunement progress, where the game has attunements (TBC, ADR-0014; issue #184)
                if GuildOS.AttunementTracker then
                    local attColor = progress.attDelta > 0 and C.green or C.silver
                    local attStr = format(L["Attunements: %d/%d >> %d/%d  (+%d)"], progress.startAttDone, progress.attTotal, progress.currentAttDone, progress.attTotal, progress.attDelta)
                    local attText = _pFS(child)
                    GuildOS:ApplyFont(attText, UI.SP.META)
                    attText:SetPoint("TOPLEFT", PADX + (contentWidth - 2 * PADX) / 2, yOff - 3)
                    attText:SetTextColor(attColor.r, attColor.g, attColor.b)
                    attText:SetText(attStr)
                    attText:Show()
                end
                yOff = yOff - 16
            end

            -- The trial's comments are read on the officer notes' timeline below, with the dated notes (audit B10).
            -- A comment: its field with the label above it, the block's Add at its bottom right (#449).
            local addNoteBox = kept(child, "trial.note", function()
                local box = UI:CreateInput(child, 200, SP.FIELD, { max = 200, placeholder = L["Add officer comment..."] })
                box:HookScript("OnEnterPressed", function(self) if self.onEnter then self.onEnter() end end)
                return box
            end)
            yOff = yOff - SP.SECTION / 2
            yOff = yOff - placeField(child, "trial.note", L["Officer comment"], addNoteBox, PADX, yOff, contentWidth - 2 * PADX)
            local addBtn = kept(child, "trial.add", function() return GuildOS.Forms:Button(child, L["Add"], "primary") end)
            local function addComment()
                local text = addNoteBox:GetText()
                if text and strtrim(text) ~= "" then
                    GuildOS.TrialTracker:AddTrialNote(playerKey, strtrim(text))
                    addNoteBox:SetText("")
                    addNoteBox:ClearFocus()
                    PopulateDetail(frame, data)
                end
            end
            addBtn:SetScript("OnClick", addComment)
            addNoteBox.onEnter = addComment
            yOff = placeActions(child, { addBtn }, yOff, contentWidth) - SP.UNIT
        end
    end

    ----------------------------------------------------------------
    -- Section: Membership history (officer only, issue #425): every passage, then the rank changes.
    ----------------------------------------------------------------
    local MH = GuildOS.MemberHistory
    if MH and GuildOS:IsOfficer() then
        local hkey = data.key or GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        local stints, ranks = MH:Stints(hkey), MH:Ranks(hkey)
        local pnote = MH.NoteFor and MH:NoteFor(hkey)   -- the permanent note (#449, specs/salao/saidas.md)
        if #stints > 0 or #ranks > 0 or pnote then
            yOff = yOff - 10
            local total = MH:TenureDays(hkey)
            yOff = CreateSectionHeader(child, string.format(L["Membership · %s days in the guild"],
                total and tostring(total) or "?"), yOff, contentWidth)
            local lines = {}
            if pnote then
                lines[#lines + 1] = "|cffFFD100" .. string.format(L["Permanent note (%s): %s"], GuildOS:SanitizeUserText(pnote.author or "?", 40),
                    GuildOS:SanitizeUserText(pnote.text, 300)) .. "|r"
            end
            for i = #stints, 1, -1 do
                local st = stints[i]
                -- Who invited them, when the game's guild event log said so (Modules/GuildEventLog.lua).
                local inv = type(st.inv) == "string" and st.inv ~= ""
                    and (" · " .. string.format(L["Invited by %s"], GuildOS:SanitizeUserText(st.inv, 48))) or ""
                lines[#lines + 1] = MH:StintLine(st) .. inv
            end
            for i = #ranks, math.max(1, #ranks - 4), -1 do
                local rk = ranks[i]
                local line = string.format(L["%s: rank %s"], GuildOS:DateText(rk.at, "/%Y"), rk.to)
                if rk.from then line = line .. " (" .. string.format(L["was %s"], rk.from) .. ")" end
                if rk.by then line = line .. " — " .. string.format(L["by %s"], rk.by) end
                lines[#lines + 1] = "|cffAAAAAA" .. line .. "|r"
            end
            for _, text in ipairs(lines) do
                local fs = _pFS(child)
                GuildOS:ApplyFont(fs, UI.SP.META)
                fs:SetPoint("TOPLEFT", PADX, yOff - 3)
                fs:SetWidth(contentWidth - 2 * PADX)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                fs:SetText(text)
                fs:Show()
                yOff = yOff - (fs:GetStringHeight() + 4)
            end
        end
    end

    ----------------------------------------------------------------
    -- Section: Officer Notes (officer only)
    ----------------------------------------------------------------
    if GuildOS.OfficerNotes and GuildOS:IsOfficer() then
        yOff = yOff - 10
        playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        -- One timeline: the dated notes and the trial's comments (audit B10).
        local notes = GuildOS.OfficerNotes:Timeline(playerKey)
        local notesHeader = L["Officer notes"] .. " · " .. #notes .. L[" notes"]
        yOff = CreateSectionHeader(child, notesHeader, yOff, contentWidth)
        -- WoW: Forever: what is written here stays on this client (audit B11).
        local localOnly = GuildOS:LocalOnlyText()
        if localOnly then
            local lo = _pFS(child)
            GuildOS:ApplyFont(lo, UI.SP.META)
            lo:SetPoint("TOPLEFT", PADX, yOff - 3)
            lo:SetWidth(contentWidth - 2 * PADX)
            lo:SetJustifyH("LEFT")
            lo:SetWordWrap(true)
            ink(lo, C.paperSoft)
            lo:SetText(localOnly)
            lo:Show()
            yOff = yOff - (lo:GetStringHeight() + 6)
        end


        -- The member's sheet, whole (issue #427), and the button that edits it.
        local sheet = GuildOS.OfficerNotes:GetSheet(playerKey)
        if sheet then
            local by = _pFS(child)
            GuildOS:ApplyFont(by, UI.SP.META)
            by:SetPoint("TOPLEFT", PADX, yOff - 3)
            by:SetText("|cffAAAAAA" .. string.format(L["Officer sheet (%s, %s):"], sheet.author or "?",
                GuildOS:DateText(sheet.ts or 0, "/%Y")) .. "|r")
            by:Show()
            yOff = yOff - 16
            local body = _pFS(child)
            GuildOS:ApplyFont(body, UI.SP.META)
            body:SetPoint("TOPLEFT", PADX, yOff - 3)
            body:SetWidth(contentWidth - 2 * PADX)
            body:SetJustifyH("LEFT")
            body:SetWordWrap(true)
            body:SetText(sheet.text)   -- kept without "|" (OfficerNotes.CleanSheetText)
            body:Show()
            yOff = yOff - (body:GetStringHeight() + 6)
        end
        local sheetKey, sheetName = playerKey, data.name
        -- A sheet saved here or by another officer redraws the card, unless the officer is typing in it. Only
        -- when this member's sheet changed, and at most once per SHEET_GAP + 1 seconds: a backfill sends an
        -- envelope every SHEET_GAP seconds, most of them other members' sheets (#427).
        local drawn = sheet and (tostring(sheet.rev) .. "\0" .. sheet.text) or ""
        local function redraw()
            if not frame:IsShown() then return end
            local now = GuildOS.OfficerNotes:GetSheet(sheetKey)
            if (now and (tostring(now.rev) .. "\0" .. now.text) or "") == drawn then return end
            local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
            if focus and focus.IsVisible and focus:IsVisible() then return end
            PopulateDetail(frame, data)
        end
        -- Through the frame: a redraw held back by the coalescing runs for whoever the panel shows then.
        frame._sheetRedraw = redraw
        GuildOS.OfficerNotes.uiRefresh = function()
            GuildOS:Coalesce("memberDetail.sheet", GuildOS.OfficerNotes.SHEET_GAP + 1, function()
                if frame._sheetRedraw then frame._sheetRedraw() end
            end)
        end

        -- The newest of the timeline; a trial's comment says so.
        for i = 1, math.min(TIMELINE_SHOWN, #notes) do
            local note = notes[i]
            local noteStr = _pFS(child)
            GuildOS:ApplyFont(noteStr, UI.SP.META)
            noteStr:SetPoint("TOPLEFT", PADX, yOff - 3)
            noteStr:SetWidth(contentWidth - 2 * PADX)
            noteStr:SetJustifyH("LEFT")
            noteStr:SetWordWrap(true)
            local dateStr = note.timestamp > 0 and GuildOS:DateText(note.timestamp) or ""
            local kind = note.kind == "trial" and (" |cffEDCC7B" .. L["trial"] .. "|r") or ""
            noteStr:SetText("|cffAAAAAA[" .. (note.author or "?") .. " " .. dateStr .. "]|r" .. kind .. " " .. (note.text or ""))
            noteStr:Show()
            yOff = yOff - (noteStr:GetStringHeight() + 4)
        end
        -- The block's one action at its bottom right (#449). One button for the panel's life (#427): a redraw per
        -- backfill envelope made a new one each time.
        local editSheet = child._editSheet
        if not editSheet then
            editSheet = GuildOS.Forms:Button(child, L["Edit sheet"], "primary")
            child._editSheet = editSheet
        end
        editSheet:SetScript("OnClick", function() GuildOS:ShowOfficerSheetEditor(sheetKey, sheetName) end)
        yOff = placeActions(child, { editSheet }, yOff, contentWidth, SP.UNIT * 2) - SP.UNIT
    end

    ----------------------------------------------------------------
    -- Section: Disciplinary record (officer only, issue #402)
    ----------------------------------------------------------------
    if GuildOS.Discipline and GuildOS:IsOfficer() then
        yOff = yOff - 10
        playerKey = GuildOS:GetPlayerKey(data.name, data.realm or GetRealmName())
        local D = GuildOS.Discipline
        local now = GetServerTime()
        local term = D:GetTerm()
        local record = D:Record(playerKey)
        local step = D.Step(record, term, now)
        yOff = CreateSectionHeader(child, format(L["Record · step %d (%d days term)"], step, term), yOff, contentWidth)
        if #record == 0 then
            local none = _pFS(child)
            GuildOS:ApplyFont(none, UI.SP.META)
            none:SetPoint("TOPLEFT", PADX, yOff)
            ink(none, C.paperSoft)
            none:SetText(L["No warnings."])
            none:Show()
            yOff = yOff - 16
        end
        -- The warnings as rows (#449): the reason (a Discord one says so) over the date, who gave it, its state and
        -- the note; a standing one given here a Revoke link at the right.
        for i = 1, math.min(10, #record) do
            local w = record[i]
            local active = D.Active(w, term, now)
            local state = w.revokedAt and L["revoked"] or (active and L["standing"] or L["lapsed"])
            local row = kept(child, "warn.row" .. i, function()
                local r = GuildOS.Forms:TodoRow(child, { none = true })
                r.revoke = rowLink(r, L["Revoke"])
                return r
            end)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", PADX, yOff)
            row:SetWidth(contentWidth - 2 * PADX)
            ink(row.title, active and C.paperInk or C.paperSoft)
            row.title:SetText(D.ReasonText(w.reason) .. (w.discord and ("  " .. L["(Discord)"]) or ""))
            local sub = { GuildOS:DateText(w.at or 0), string.format(L["by %s"], w.by or "?"), state }
            if w.note then sub[#sub + 1] = GuildOS:SanitizeUserText(w.note, 200) end
            row.sub:SetText(table.concat(sub, " \194\183 "))
            local canRevoke = active and not w.discord
            row.revoke:SetShown(canRevoke and true or false)
            if canRevoke then
                local id = w.id
                row.revoke:SetScript("OnClick", function()
                    D:Revoke(id)   -- the sheet redraws through D.uiRefresh
                end)
            end
            row:Right({ row.revoke })
            yOff = yOff - GuildOS.Forms.TODO_H
        end

        -- Warn (issue #403): the window files it, whispers on the click and suggests the step's rung. The block's
        -- one action, at its bottom right.
        local who = data.name
        local warnBtn = kept(child, "warn.go", function() return GuildOS.Forms:Button(child, L["Warn"], "primary") end)
        warnBtn:SetScript("OnClick", function() GuildOS:ShowWarnDialog(playerKey, who) end)
        yOff = placeActions(child, { warnBtn }, yOff, contentWidth) - SP.UNIT
        -- A warning or a setting that changes (here or from another officer) redraws the sheet, unless the
        -- officer is typing in it: the sheet would scroll back to the top and lose what they typed.
        D.uiRefresh = function()
            if not frame:IsShown() then return end
            local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
            if focus and focus.IsVisible and focus:IsVisible() then return end
            PopulateDetail(frame, data)
        end

        -- The guild's rules every sheet counts by (#449): the term and the punishment rank as a pair, the rank one
        -- of the guild's ranks (a free field where the client lists none), saved by the block's one button.
        yOff = yOff - 10
        yOff = CreateSectionHeader(child, L["Discipline rules"], yOff, contentWidth)
        local termBox = kept(child, "rules.term", function()
            local box = UI:CreateInput(child, 60, SP.FIELD, { numeric = true, max = 3 })
            box:HookScript("OnEnterPressed", function(self) if self.onEnter then self.onEnter() end end)
            return box
        end)
        termBox:SetText(tostring(term))
        local ranks = GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}
        local rankCtl
        local held = D:GetPunishRank()
        if #ranks > 0 then
            rankCtl = kept(child, "rules.rankList", function() return UI:CreateDropdown(child, 120, SP.FIELD) end)
            local opts, known = { { value = "", text = L["None"] } }, false
            for _, r in ipairs(ranks) do
                opts[#opts + 1] = { value = r.name, text = r.name }
                known = known or r.name == held
            end
            -- A rank saved that the guild no longer has stays offered, so saving keeps it.
            if held and not known then opts[#opts + 1] = { value = held, text = held } end
            rankCtl:SetOptions(opts)
            rankCtl:SetValue(held or "")
        else
            rankCtl = kept(child, "rules.rankText", function()
                return UI:CreateInput(child, 120, SP.FIELD, { max = 48, placeholder = L["Punishment rank"] })
            end)
            rankCtl:SetText(held or "")
        end
        yOff = yOff - placePair(child, { "rules.term", L["Term (days)"], termBox },
            { #ranks > 0 and "rules.rankList" or "rules.rankText", L["Punishment rank"], rankCtl }, yOff, contentWidth)
        local saveRules = kept(child, "rules.save", function() return GuildOS.Forms:Button(child, L["Save"], "primary") end)
        local function applyRules()
            termBox:ClearFocus()
            local days = termBox:GetText()
            local rank
            if rankCtl.GetValue then rank = rankCtl:GetValue() else rank = rankCtl:GetText() end
            rank = rank or ""
            -- Each setting that changed, the rank's read before the term's redraw (D.uiRefresh) refills the fields.
            if tostring(days) ~= tostring(D:GetTerm()) then
                if not D:SetTerm(days) then termBox:SetText(tostring(D:GetTerm())) end
            end
            if rank ~= (D:GetPunishRank() or "") then D:SetPunishRank(rank) end
        end
        saveRules:SetScript("OnClick", applyRules)
        termBox.onEnter = applyRules
        yOff = placeActions(child, { saveRules }, yOff, contentWidth) - SP.UNIT
    end

    ----------------------------------------------------------------
    -- Section: Linked Characters (officers manage anyone; members manage
    -- their own alts on the current character via self-claim)
    ----------------------------------------------------------------
    local myKey = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    local isSelfManage = (playerKey == myKey)
    if GuildOS:IsOfficer() or isSelfManage then
        yOff = yOff - 10
        local linkedKeys = GuildOS:GetLinkedChars(playerKey)
        local altLinks = (GuildOS.db and GuildOS.db.altLinks) or {}
        local roster = RosterIndex()

        -- Header shows how many chars are linked
        local linkCount = #linkedKeys - 1  -- exclude self
        local hdrSuffix = linkCount > 0 and (" · " .. linkCount .. L[" linked"]) or ""
        yOff = CreateSectionHeader(child, L["Linked characters"] .. hdrSuffix, yOff, contentWidth)

        -- The officer's note is about attunements: none where the game has none (issue #184).
        local noteText = not GuildOS:IsOfficer()
            and L["Add your own alts (any account). An officer's client applies them guild-wide."]
            or (GuildOS.AttunementTracker and L["Linked chars share attunements account-wide."])
        if noteText then
            local noteLabel = _pFS(child)
            GuildOS:ApplyFont(noteLabel, UI.SP.META)
            noteLabel:SetPoint("TOPLEFT", PADX, yOff)
            noteLabel:SetWidth(contentWidth - 2 * PADX)
            noteLabel:SetJustifyH("LEFT")
            noteLabel:SetWordWrap(true)
            ink(noteLabel, C.paperSoft)
            noteLabel:SetText(noteText)
            noteLabel:Show()
            yOff = yOff - noteLabel:GetStringHeight() - 6
        end

        -- The group as rows (#449): the round avatar in the class's colour, the name in the class's paper ink, a
        -- Main or Alt badge, and at the right its links: Set as main on an alt, Unlink on any character but the
        -- one this card is about (its own row, kept so the character shown can be made the main without logging an
        -- alt; "(you)" on your own). Officers apply directly; members route through the self-claim.
        local function doUnlink(k)
            if GuildOS:IsOfficer() then GuildOS:UnlinkAlt(k)
            else GuildOS.AltAutoDetect:UnlinkOwnAlt(k) end
        end
        local function doSetMain(k)
            if GuildOS:IsOfficer() then GuildOS:SetMain(k)
            else GuildOS.AltAutoDetect:SetOwnMain(k) end
        end
        if #linkedKeys > 1 then
            local order = { playerKey }
            for _, lk in ipairs(linkedKeys) do if lk ~= playerKey then order[#order + 1] = lk end end
            for i, lk in ipairs(order) do
                local row = kept(child, "alt.row" .. i, function()
                    local r = GuildOS.Forms:TodoRow(child)
                    r.badge = GuildOS.Kit:Badge(r, "", "mute")
                    r.setMain = rowLink(r, L["Set as main"])
                    r.unlink = rowLink(r, L["Unlink"])
                    return r
                end)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", PADX, yOff)
                row:SetWidth(contentWidth - 2 * PADX)
                local isMain = (altLinks[lk] == nil)
                local isSelf = (lk == playerKey)
                local info = roster.byKey[lk]
                local name = (info and info.name) or lk:match("^([^-]+)") or lk
                local class = info and info.class
                    or (GuildOS.db.members and GuildOS.db.members[lk] and GuildOS.db.members[lk].class)
                    or (isSelf and data.class) or nil
                row.av:SetMember(name, class and tostring(class):upper() or nil)
                local r, g, b = UI:InkFor("paper", "class", class)
                if not class then r, g, b = C.paperInk.r, C.paperInk.g, C.paperInk.b end
                row.title:SetTextColor(r, g, b)
                row.title:SetText(name)
                local sub = {}
                if info and info.rank then sub[#sub + 1] = info.rank end
                if isSelf and isSelfManage then sub[#sub + 1] = L["(you)"] end
                row.sub:SetText(table.concat(sub, " \194\183 "))
                row.badge:SetText(isMain and L["Main"] or L["Alt"], isMain and C.gold or C.paperSoft)
                -- The badge right after the name.
                row.badge:ClearAllPoints()
                row.badge:SetPoint("LEFT", row.title, "LEFT",
                    math.min(math.ceil(row.title:GetStringWidth() or 0) + SP.UNIT * 2, (contentWidth - 2 * PADX) - 220), 0)
                local capturedKey = lk
                row.setMain:SetShown(not isMain)
                row.setMain:SetScript("OnClick", function()
                    doSetMain(capturedKey)
                    PopulateDetail(frame, data)
                end)
                row.unlink:SetShown(not isSelf)
                row.unlink:SetScript("OnClick", function()
                    -- If lk is the main, unlink playerKey from it; else unlink lk.
                    if isMain then doUnlink(playerKey) else doUnlink(capturedKey) end
                    PopulateDetail(frame, data)
                end)
                row:Right({ row.unlink, row.setMain })
                yOff = yOff - GuildOS.Forms.TODO_H
            end
        end

        -- Add an alt: the field with its label above it, a character of the guild suggested as one types (Tab or a
        -- click on it takes it), and the block's Link at its bottom right with the group's other actions.
        local addLinkBox = kept(child, "alt.add", function()
            local box = UI:CreateInput(child, 200, SP.FIELD, { max = 60, placeholder = L["Character name"] })
            local hint = rowLink(box, "")
            hint:SetPoint("RIGHT", box, "RIGHT", -SP.UNIT, 0)
            hint:Hide()
            box.hint = hint
            hint:SetScript("OnClick", function()
                if hint.name then box:SetText(hint.name); box:SetCursorPosition(#hint.name); hint:Hide() end
            end)
            box:HookScript("OnTextChanged", function(self) if self.onChange then self.onChange(self) end end)
            box:HookScript("OnEnterPressed", function(self) if self.onEnter then self.onEnter() end end)
            box:HookScript("OnTabPressed", function(self) if self.hint.name and self.hint:IsShown() then self.hint:Click() end end)
            return box
        end)
        local taken = {}
        for _, lk in ipairs(linkedKeys) do taken[lk] = true end
        taken[playerKey] = true
        addLinkBox.onChange = function(self)
            local typed = strtrim(self:GetText() or "")
            local pick = SuggestCharacter(roster, typed, taken)
            local hint = self.hint
            hint.name = pick
            if pick and pick:lower() ~= typed:lower() then
                hint.label:SetText(pick)
                hint:SetWidth(math.ceil(hint.label:GetStringWidth() or 30) + 6)
                hint:Show()
            else
                hint:Hide()
            end
        end
        addLinkBox.hint:Hide()
        yOff = yOff - SP.FIELD_GAP
        yOff = yOff - placeField(child, "alt.add", L["Add alt"], addLinkBox, PADX, yOff, contentWidth - 2 * PADX)

        local doLink = function()
            local altName = strtrim(addLinkBox:GetText())
            if altName == "" then return end
            -- A member of the guild, as the roster keys them (WoW: Forever's "Chehul-Costa" is "Chehul Costa"): a
            -- typo, or somebody who left, is never linked (#449). Linked under the group's main, whose card this is
            -- or not; officers write it, a member's goes to them as a claim of the whole group.
            local altKey = GuildOS.AltAutoDetect.FindMember(roster.names, altName, playerKey)
            if not altKey then
                GuildOS:Print(string.format(L["%s is not in the guild roster."], altName))
                return
            end
            if GuildOS.AltAutoDetect:AddAlt(playerKey, altKey) then
                addLinkBox:SetText("")
                addLinkBox:ClearFocus()
                PopulateDetail(frame, data)
            end
        end
        local addLinkBtn = kept(child, "alt.link", function() return GuildOS.Forms:Button(child, L["Link"], "primary") end)
        addLinkBtn:SetScript("OnClick", doLink)
        addLinkBox.onEnter = doLink

        -- The group's other actions, cream, left of Link.
        local buttons = {}
        -- /gos myalts: on your own sheet, find your characters in the guild and offer to link them (#142).
        if isSelfManage and GuildOS.AltAutoDetect then
            local detectBtn = kept(child, "alt.detect", function() return GuildOS.Forms:Button(child, L["Detect my alts"]) end)
            detectBtn:SetScript("OnClick", function() GuildOS.AltAutoDetect:PromptNow() end)
            buttons[#buttons + 1] = detectBtn
        end
        -- The group's alts to the main's rank (issue #424): a queue in Leadership > Bulk actions, one alt per
        -- click of its Next button; the game's rank commands only ever run from that click.
        if GuildOS:IsOfficer() and GuildOS.BulkActions and #linkedKeys > 1 then
            local promoteBtn = kept(child, "alt.promote", function()
                local b = GuildOS.Forms:Button(child, L["Promote alts"])
                return b
            end)
            local demoteBtn = kept(child, "alt.demote", function()
                local b = GuildOS.Forms:Button(child, L["Demote alts"])
                return b
            end)
            promoteBtn:SetScript("OnClick", function() GuildOS.BulkActions:StartGroupAndSay(playerKey, "promote") end)
            demoteBtn:SetScript("OnClick", function() GuildOS.BulkActions:StartGroupAndSay(playerKey, "demote") end)
            for _, b in ipairs({ promoteBtn, demoteBtn }) do
                if not b.tipHooked then
                    b.tipHooked = true
                    b:HookScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_TOP")
                        GameTooltip:SetText(L["To the main's rank, one alt per click of Next in Leadership > Bulk actions."], 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end
            buttons[#buttons + 1] = promoteBtn
            buttons[#buttons + 1] = demoteBtn
        end
        buttons[#buttons + 1] = addLinkBtn
        yOff = placeActions(child, buttons, yOff, contentWidth) - SP.UNIT
    end

    -- Update scroll child height and refresh the scroll range so the
    -- scrollbar clamps correctly when content is shorter than the frame.
    child:SetHeight(math.abs(yOff) + 20)
    child:GetParent():UpdateScrollChildRect()
    paperInks(child)
end

----------------------------------------------------------------------
-- Create a section header
----------------------------------------------------------------------
-- A section of the card (#449, the Officers' Room's blocks): its title in the serif face (SECTION_ROLE: Alegreya,
-- in normal case, never the capitals the title face draws) in the paper's dark red, a soft tan rule above it
-- (none over the first), and `meta`, a soft line at the title's right (the equipment's average item level).
-- Returns the y its content starts at.
function CreateSectionHeader(parent, text, yOff, width, meta)
    if yOff < -6 then
        local line = _pBG(parent)
        line:SetTexture("Interface\\Buttons\\WHITE8x8")
        line:SetPoint("TOPLEFT", PADX, yOff - 2)
        -- A pooled texture (_pBG) comes back as a band or a row later: size it, never register it (#369).
        line:SetSize(width - 2 * PADX, GuildOS.UI:Px(line))
        line:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)   -- the card's soft tan rule
        line.__ownInk = true
        line:Show()
    end

    local label = _pFS(parent)
    GuildOS:ApplyFont(label, SP.TITLE - 1, SECTION_ROLE)   -- the reading face draws a px larger: SP.TITLE
    label:SetPoint("TOPLEFT", PADX, yOff - 8)
    ink(label, C.paperTitle)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local metaW = 0
    if meta and meta ~= "" then
        local m = _pFS(parent)
        GuildOS:ApplyFont(m, SP.META)
        ink(m, C.paperSoft)
        m:SetJustifyH("RIGHT")
        m:SetWordWrap(false)
        m:SetText(meta)
        metaW = math.ceil(m:GetStringWidth() or 0) + 2
        m:SetWidth(metaW)
        m:SetPoint("TOPRIGHT", parent, "TOPLEFT", width - PADX, yOff - 11)
        m:Show()
    end
    label:SetWidth(math.max(40, width - 2 * PADX - (metaW > 0 and metaW + SP.CELL or 0)))
    GuildOS:SetTitleText(label, text)
    label:Show()

    return yOff - 8 - SP.TITLE_H - SP.TITLE_GAP
end

----------------------------------------------------------------------
-- Create a gear slot row (with enchant & gem display)
----------------------------------------------------------------------

-- One equipment row (#449), GEAR_ROW tall whatever it holds: the slot's name in the paper's soft ink, centred in
-- its column on the left; the item's icon in its quality's frame (from the item's id when the client has not
-- cached it, else a question mark in that frame); the name in the paper's cut of its quality on the first line
-- and the enchant (or "Not enchanted") under it, at the name's left; the item level right-aligned and centred in
-- its column. `rule`: a thin rule above it, between two rows, clear of the icons. Returns true when the client
-- had not cached the item yet (the card draws again when it has).
function CreateGearRow(parent, slotId, item, yOff, width, rule)
    local slotName = GuildOS.SlotNames[slotId] or L["Slot "] .. slotId
    local pending = false
    local mid = yOff - GEAR_ROW / 2
    local iconX = PADX + GEAR_SLOT_W + SP.UNIT * 2
    local nameX = iconX + GEAR_ICON + 4 + SP.UNIT * 2
    local right = width - PADX
    local nameW = math.max(40, right - GEAR_ILVL_W - SP.UNIT * 2 - nameX)

    if rule then
        local sep = _pBG(parent)
        sep:SetTexture("Interface\\Buttons\\WHITE8x8")
        sep:SetPoint("TOPLEFT", PADX, yOff)
        sep:SetSize(width - 2 * PADX, GuildOS.UI:Px(sep))   -- pooled, like the line above: not registered
        sep:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
        sep.__ownInk = true
        sep:Show()
    end

    -- Slot label
    local slotLabel = _pFS(parent)
    GuildOS:ApplyFont(slotLabel, UI.SP.META)
    slotLabel:SetPoint("LEFT", parent, "TOPLEFT", PADX, mid)
    slotLabel:SetWidth(GEAR_SLOT_W)
    slotLabel:SetJustifyH("LEFT")
    ink(slotLabel, C.paperSoft)
    slotLabel:SetText(slotName)
    slotLabel:Show()

    if item and item.name and item.name ~= "" then
        -- Resolve localized item name and icon from client cache
        local localName, _, _, _, _, _, _, _, _, itemIcon = GuildOS.Compat.GetItemInfo(item.id or 0)
        if not localName and item.id then pending = true end
        local displayName = (localName and localName ~= "") and localName or item.name
        local icon = (itemIcon and itemIcon ~= "") and itemIcon or nil
        if not icon then
            local _, instant = GuildOS.Compat.ItemInstant(item.link or item.id)
            icon = instant
        end

        -- Item icon, always in its quality's frame
        local iconFrame = _pF(parent, "gearIcon", function() return UI:CreateIcon(parent, GEAR_ICON) end)
        iconFrame.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        iconFrame:SetPoint("LEFT", parent, "TOPLEFT", iconX, mid)
        iconFrame:SetBackdropColor(C.paperLight.r, C.paperLight.g, C.paperLight.b, 1)
        iconFrame:Show()
        UI:SetIconQuality(iconFrame, item.quality)

        -- Item name, in the paper's cut of its quality (contrast on the parchment)
        local qr, qg, qb = UI:InkFor("paper", "quality", item.quality or 1)
        local nameText = _pFS(parent)
        GuildOS:ApplyFont(nameText, SP.BODY)
        nameText:SetPoint("TOPLEFT", nameX, mid + 15)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        ink(nameText, { r = qr, g = qg, b = qb })
        nameText:SetText(displayName)
        nameText:Show()

        -- Tooltip hover zone over gear row
        CreateItemTooltipZone(parent, nameText, item.link or item.id)

        -- Gem icons — inline after item name on the same row; the name gives them room
        local gemAnchor = nameText
        local gems = 0
        if item.gems and #item.gems > 0 then
            for _, gem in ipairs(item.gems) do
                local _, _, _, _, _, _, _, _, _, gemIcon = GuildOS.Compat.GetItemInfo(gem.id or 0)
                if not gemIcon and gem.id then local _, gi = GuildOS.Compat.ItemInstant(gem.id); gemIcon = gi end
                if gemIcon and gemIcon ~= "" then
                    local gemFrame = _pF(parent, "gemIcon", function() return UI:CreateIcon(parent, 12) end)
                    gemFrame.icon:SetTexture(gemIcon)
                    gemFrame:SetScript("OnEnter", nil)
                    gemFrame:SetScript("OnLeave", nil)
                    gemFrame:EnableMouse(false)
                    gemFrame:SetPoint("LEFT", gemAnchor, "RIGHT", 4, 0)
                    gemFrame:Show()
                    gemAnchor = gemFrame
                    gems = gems + 1

                    -- Gem tooltip on hover
                    if gem.id then
                        gemFrame:EnableMouse(true)
                        gemFrame:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink("item:" .. gem.id)
                            GameTooltip:Show()
                        end)
                        gemFrame:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                    end
                end
            end
        end
        local gemRoom = gems * 20
        local textW = math.ceil(nameText:GetStringWidth() or 0) + 2
        nameText:SetWidth(math.max(20, math.min(textW, nameW - gemRoom)))

        -- Item level, in the paper's ink, right-aligned in its column
        local ilvlText = _pFS(parent)
        GuildOS:ApplyFont(ilvlText, SP.META, "tableNum")
        ilvlText:SetPoint("RIGHT", parent, "TOPLEFT", right, mid)
        ilvlText:SetWidth(GEAR_ILVL_W)
        ilvlText:SetJustifyH("RIGHT")
        ink(ilvlText, C.paperInk)
        ilvlText:SetText(UI:PaperText(GuildOS:FormatItemLevel(item.ilvl), "paper"))
        ilvlText:Show()

        -- Enchant line — resolve name from DataCollector cache, same as local player
        local enchantY = mid - 2
        local enchantName = item.enchantId and item.enchantId > 0
            and GuildOS.DataCollector and GuildOS.DataCollector:GetEnchantName(item.enchantId)
        local line, lineInk
        if enchantName then
            line, lineInk = enchantName, UI.QUALITY_INK[2]
        elseif item.enchantId and item.enchantId > 0 then
            line, lineInk = L["Enchanted"], UI.QUALITY_INK[2]
        elseif GuildOS.GearAudit and GuildOS.GearAudit:NeedsEnchant(slotId, item) then   -- ADR-0026, #177
            line, lineInk = L["Not enchanted"], paperInk(C.red)
        end
        if line then
            local enchText = _pFS(parent)
            GuildOS:ApplyFont(enchText, UI.SP.META)
            enchText:SetPoint("TOPLEFT", nameX, enchantY)
            enchText:SetWidth(nameW)
            enchText:SetJustifyH("LEFT")
            ink(enchText, lineInk)
            enchText:SetText(line)
            enchText:Show()
        end
    else
        -- Empty slot
        local emptyText = _pFS(parent)
        GuildOS:ApplyFont(emptyText, UI.SP.META)
        emptyText:SetPoint("LEFT", parent, "TOPLEFT", iconX, mid)
        ink(emptyText, C.paperSoft)
        emptyText:SetText(L["- Empty -"])
        emptyText:Show()
    end

    return pending
end

----------------------------------------------------------------------
-- Create a profession row
----------------------------------------------------------------------
function CreateProfessionRow(parent, prof, yOff, width)
    local ROW_H = 30

    -- Profession name
    local nameColor = prof.isPrimary and C.paperInk or C.paperSoft
    local nameText = _pFS(parent)
    GuildOS:ApplyFont(nameText, 11)
    nameText:SetPoint("TOPLEFT", PADX, yOff - 3)
    ink(nameText, nameColor)
    nameText:SetText(L[prof.name])
    nameText:Show()

    -- Skill level text
    local skillText = _pFS(parent)
    GuildOS:ApplyFont(skillText, UI.SP.META)
    skillText:SetPoint("TOPRIGHT", -PADX, yOff - 4)
    ink(skillText, C.paperInk)
    -- A profession known from the guild roster only has no rank (issue #31).
    skillText:SetText(prof.rank and string.format("%d / %d", prof.rank, prof.maxRank or 0) or "")
    skillText:Show()

    -- Progress bar
    local progressBar = _pF(parent, "profBar", function() return UI:CreateProgressBar(parent, width - 2 * PADX, 6) end)
    progressBar:SetSize(width - 2 * PADX, 6)
    progressBar:SetPoint("TOPLEFT", PADX, yOff - 18)
    progressBar:SetProgress((prof.rank and (prof.maxRank or 0) > 0) and (prof.rank / prof.maxRank) or 0)
    progressBar:Show()

    return yOff - ROW_H
end

----------------------------------------------------------------------
-- Create an attunement row
----------------------------------------------------------------------
function CreateAttunementRow(parent, att, yOff, width)
    local ROW_H = 34

    -- Background with subtle color coding
    local rowBg = _pBG(parent)
    rowBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    rowBg:SetPoint("TOPLEFT", PADX, yOff)
    rowBg:SetSize(width - 2 * PADX, ROW_H - 2)
    if att.complete then
        rowBg:SetVertexColor(C.green.r * 0.1, C.green.g * 0.1, C.green.b * 0.1, 0.3)
    else
        rowBg:SetVertexColor(0.050, 0.050, 0.066, 0.3)
    end
    rowBg:Show()

    -- Tier badge
    local tierBadge = _pFS(parent)
    GuildOS:ApplyFont(tierBadge, SP.META)
    tierBadge:SetPoint("TOPLEFT", PADX, yOff - 4)
    tierBadge:SetTextColor(C.accentDim.r, C.accentDim.g, C.accentDim.b)
    tierBadge:SetText("[" .. att.tier .. "]")
    tierBadge:Show()

    -- Raid name
    local nameText = _pFS(parent)
    GuildOS:ApplyFont(nameText, 11)
    nameText:SetPoint("LEFT", tierBadge, "RIGHT", 5, 0)
    nameText:Show()

    -- Status
    local statusText = _pFS(parent)
    GuildOS:ApplyFont(statusText, UI.SP.META)
    statusText:SetPoint("TOPRIGHT", -PADX, yOff - 4)
    statusText:Show()

    if att.complete then
        nameText:SetTextColor(C.green.r, C.green.g, C.green.b)
        nameText:SetText(att.name)
        statusText:SetTextColor(C.green.r, C.green.g, C.green.b)
        if att.accountWide and att.sourceChar then
            local srcName = att.sourceChar:match("^([^-]+)") or att.sourceChar
            statusText:SetText(L["ATTUNED"] .. " |cff888888(" .. L["account: "] .. srcName .. ")|r")
        else
            statusText:SetText(L["ATTUNED"])
        end
    elseif att.progress and att.progress > 0 then
        nameText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        nameText:SetText(att.name)
        statusText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        statusText:SetText(string.format("%d/%d", att.questsDone or 0, att.questsTotal or 0))
    else
        nameText:SetTextColor(C.red.r, C.red.g, C.red.b, 0.7)
        nameText:SetText(att.name)
        statusText:SetTextColor(C.red.r, C.red.g, C.red.b, 0.7)
        statusText:SetText(L["NOT STARTED"])
    end

    -- Progress bar (only for in-progress attunements, not completed ones)
    if not att.complete and att.questsTotal and att.questsTotal > 0 then
        local progressBar = _pF(parent, "attBar", function() return UI:CreateProgressBar(parent, width - 2 * PADX - 8, 5) end)
        progressBar:SetSize(width - 2 * PADX - 8, 5)
        progressBar:SetPoint("TOPLEFT", PADX, yOff - 20)
        progressBar:SetProgress(att.progress or 0)
        progressBar:Show()
    end

    return yOff - ROW_H
end

----------------------------------------------------------------------
-- Talent Tree Viewer
-- A compact floating panel showing a member's talents tab by tab.
----------------------------------------------------------------------
local TV_SLOT_SIZE = 38   -- icon cell size (includes border/gap)
local TV_ICON_SIZE = 34   -- inner texture size
local TV_COLS      = 4
local TV_ROWS      = 9    -- max tier rows in TBC talent trees
local TV_W         = TV_COLS * TV_SLOT_SIZE + 22          -- 174
local TV_H         = 36 + 30 + 4 + TV_ROWS * TV_SLOT_SIZE + 10  -- 422

local function CreateTalentViewerFrame()
    local f = UI:CreatePanel(UIParent, "GuildOSTalentViewer")
    f:SetSize(TV_W, TV_H)
    f:SetPoint("CENTER", 350, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:Hide()
    UI:StylePopup(f, { noSheen = true, shadowSize = 16 })

    ----------------------------------------------------------------
    -- Title bar (draggable)
    ----------------------------------------------------------------
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetAllPoints()
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, UI.SP.META)
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetPoint("RIGHT", -26, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetWordWrap(false)
    f.titleText = titleText

    local closeBtn = UI:CreateCloseButton(titleBar)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local titleLine = f:CreateTexture(nil, "OVERLAY")
    titleLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleLine:SetPoint("TOPLEFT",  0, -36)
    titleLine:SetPoint("TOPRIGHT", 0, -36)
    GuildOS.UI:Hairline(titleLine, "Height")
    titleLine:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.8)

    ----------------------------------------------------------------
    -- Tree tab buttons (3 trees per class)
    ----------------------------------------------------------------
    local tabW = math.floor((TV_W - 8) / 3)
    local tabs = {}
    for i = 1, 3 do
        local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
        tab:SetSize(tabW - 2, 28)  -- two lines of 10px text: name, then points
        tab:SetPoint("TOPLEFT", 4 + (i - 1) * tabW, -38)
        tab:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GuildOS.UI:Edge(tab),
        })
        tab:SetBackdropColor(C.row2.r, C.row2.g, C.row2.b, 1)
        tab:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.5)

        local lbl = tab:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(lbl, 7)
        lbl:SetAllPoints()
        lbl:SetJustifyH("CENTER")
        lbl:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        tab.label = lbl

        local capturedI = i
        tab:SetScript("OnClick", function()
            f.currentTab = capturedI
            f:RefreshGrid()
        end)
        tabs[i] = tab
    end
    f.tabs = tabs

    ----------------------------------------------------------------
    -- Icon slots — pre-created grid; repositioned on refresh
    ----------------------------------------------------------------
    local gridX = 11
    local gridY = -70  -- below title bar + tabs + gap
    local slots = {}
    for row = 1, TV_ROWS do
        slots[row] = {}
        for col = 1, TV_COLS do
            local slot = CreateFrame("Button", nil, f, "BackdropTemplate")
            slot:SetSize(TV_ICON_SIZE, TV_ICON_SIZE)
            slot:SetPoint(
                "TOPLEFT",
                gridX + (col - 1) * TV_SLOT_SIZE,
                gridY - (row - 1) * TV_SLOT_SIZE)
            slot:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = GuildOS.UI:Edge(slot),
            })
            slot:SetBackdropColor(0, 0, 0, 0.7)
            slot:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)

            local icon = slot:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT",     2, -2)
            icon:SetPoint("BOTTOMRIGHT", -2, 2)
            slot.icon = icon

            local rankText = slot:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(rankText, 7)
            rankText:SetPoint("BOTTOMRIGHT", -1, 2)
            slot.rankText = rankText

            -- The rank sits over icon art with no outline: a dark chip behind it
            -- keeps "5/5" readable. Shown only while there is a rank to read.
            local rankBg = slot:CreateTexture(nil, "ARTWORK", nil, 7)
            rankBg:SetTexture("Interface\\Buttons\\WHITE8x8")
            rankBg:SetPoint("TOPLEFT", rankText, "TOPLEFT", -1, 1)
            rankBg:SetPoint("BOTTOMRIGHT", rankText, "BOTTOMRIGHT", 1, -1)
            rankBg:SetVertexColor(C.well.r, C.well.g, C.well.b, 0.85)  -- dark enough over bright icon art
            rankBg:Hide()
            slot.rankBg = rankBg

            local dimOverlay = slot:CreateTexture(nil, "OVERLAY")
            dimOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
            dimOverlay:SetAllPoints()
            dimOverlay:SetVertexColor(0, 0, 0, 0.55)
            slot.dimOverlay = dimOverlay

            slot:SetScript("OnEnter", function(self)
                if not self.talentData then return end
                local td = self.talentData
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(td.name, 1, 1, 1)
                if td.currentRank > 0 then
                    GameTooltip:AddLine(
                        format(L["Rank %d / %d"], td.currentRank, td.maxRank),
                        0.9, 0.8, 0.1)
                else
                    GameTooltip:AddLine(
                        format(L["Not learned  (0/%d)"], td.maxRank),
                        0.5, 0.5, 0.5)
                end
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

            slot:Hide()
            slots[row][col] = slot
        end
    end
    f.slots = slots

    ----------------------------------------------------------------
    -- RefreshGrid: fill the grid from the current tab's talent data
    ----------------------------------------------------------------
    function f:RefreshGrid()
        local tab  = self.currentTab or 1
        local spec = self.spec
        if not spec then return end

        -- Tab button styles
        local cr, cg, cb = GuildOS:GetClassColor(self.classToken)
        for i, tabBtn in ipairs(self.tabs) do
            local pts  = (spec.points and spec.points[i]) or 0
            local name = (spec.names  and spec.names[i])  or (L["Tree "] .. i)
            name = GuildOS:Utf8Head(name, 8)
            tabBtn.label:SetText(name .. "\n" .. pts)
            if i == tab then
                tabBtn:SetBackdropColor(cr * 0.35, cg * 0.35, cb * 0.35, 1)
                tabBtn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            else
                tabBtn:SetBackdropColor(C.row2.r, C.row2.g, C.row2.b, 1)
                tabBtn.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            end
        end

        -- Clear all slots
        for row = 1, TV_ROWS do
            for col = 1, TV_COLS do
                local slot = self.slots[row][col]
                slot.talentData = nil
                slot.icon:SetTexture("")
                slot.rankText:SetText("")
                slot.rankBg:Hide()
                slot.dimOverlay:Show()
                slot:Hide()
            end
        end

        -- Populate talents for the active tab
        local tabTalents = spec.talents and spec.talents[tab]
        if not tabTalents then return end

        for _, td in ipairs(tabTalents) do
            local row = tonumber(td.tier)   or 0
            local col = tonumber(td.column) or 0
            if row >= 1 and row <= TV_ROWS and col >= 1 and col <= TV_COLS then
                local slot = self.slots[row][col]
                slot.talentData = td
                slot.icon:SetTexture(
                    (td.icon and td.icon ~= "") and td.icon
                    or "Interface\\Icons\\INV_Misc_QuestionMark")
                if td.currentRank > 0 then
                    slot.icon:SetDesaturated(false)
                    slot.icon:SetAlpha(1.0)
                    slot.dimOverlay:Hide()
                    slot:SetBackdropBorderColor(cr * 0.8, cg * 0.8, cb * 0.8, 0.9)
                    if td.currentRank >= td.maxRank then
                        slot.rankText:SetTextColor(0.2, 1.0, 0.2)
                    else
                        slot.rankText:SetTextColor(1.0, 0.85, 0.0)
                    end
                    slot.rankText:SetText(td.currentRank .. "/" .. td.maxRank)
                    slot.rankBg:Show()
                else
                    slot.icon:SetDesaturated(true)
                    slot.icon:SetAlpha(0.4)
                    slot.dimOverlay:Show()
                    slot:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)
                    slot.rankText:SetTextColor(0.35, 0.35, 0.35)
                    slot.rankText:SetText("0/" .. td.maxRank)
                    slot.rankBg:Show()
                end
                slot:Show()
            end
        end
    end

    table.insert(UISpecialFrames, "GuildOSTalentViewer")
    return f
end

----------------------------------------------------------------------
-- GuildOS:ShowTalentViewer(spec, playerName, classToken)
-- Opens the talent tree viewer for the given spec record.
----------------------------------------------------------------------
function GuildOS:ShowTalentViewer(spec, playerName, classToken)
    if not spec or not spec.talents then
        GuildOS:Print(L["|cffFF4444No talent data available for this player.|r"])
        return
    end

    if not self.TalentViewerFrame then
        self.TalentViewerFrame = CreateTalentViewerFrame()
    end
    local f = self.TalentViewerFrame
    f.spec       = spec
    f.classToken = classToken

    local shortName = (playerName or "?"):match("^([^-]+)") or playerName
    local specName  = spec.tree or L["Unknown"]
    f.titleText:SetText(shortName .. "  —  " .. specName)

    f.currentTab = spec.treeIndex or 1
    f:RefreshGrid()
    f:Show()
    f:Raise()
end
