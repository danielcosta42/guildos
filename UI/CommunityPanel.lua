----------------------------------------------------------------------
-- Guild OS - Guild Hub + DKP panels
-- Brings the community/loot features into the main window as real tabs
-- instead of slash-only popups:
--   * Guild hub: Activity feed, Bulletin board, Polls (sub-tabs)
--   * DKP: standings + officer controls
-- Renders from the module data APIs (Rule 3 / Rule 10).
--
-- The Salão's entries and the Chronicle's Activity are drawn as the approved mockup (#449 phase 3):
-- parchment cards to read on the wood, in two columns (the mockup's .g2) from a 700px tab and one under it
-- below; the notices as pinned notes, the polls as bars, the rules as a parchment list, the calls as lines
-- with a coloured square, the forms in a card of their own on the right.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab
local FIELD_H = 26         -- a one-line field, and the button beside it

----------------------------------------------------------------------
-- The cards (#449 phase 3)
----------------------------------------------------------------------
local TWO_COLUMNS = 700     -- from this content width the cards sit in two columns
local LEFT_SHARE  = 0.535   -- the mockup's 1.15fr : 1fr
local GUTTER      = 12
local PAD         = UI.CARD_PAD or 14
local TOP         = 38      -- a card's first line, under its title
local NOTE_GAP    = 10

local function hex(h)
    return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
end
-- The mockup's squares and glyphs: red for what is open now, the paper's brown for what is past.
local SQUARE_OPEN, SQUARE_PAST = hex("b0261b"), hex("6f5a3c")
local POLL_FILL = GuildOS:PaperShade("ecd9a8", "5e4a2e")   -- a poll's bar on the light field

-- A FontString in `color`, left-aligned; `wrap` lets it run over lines (give it a width).
local function text(parent, size, color, role, wrap)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(wrap and true or false)
    return fs
end

-- A thin rule of the card's line colour across `row`'s top.
local function rule(row, card)
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    UI:Hairline(t)
    local c = card.lineColor or C.paperLine
    t:SetVertexColor(c.r, c.g, c.b, 1)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", 0, 0)
    return t
end

-- A small rounded square in a colour with a letter on it (the mockup's .ic): an open call, a closed poll.
local function square(parent, size)
    local sq = CreateFrame("Frame", nil, parent)
    sq:SetSize(size, size)
    sq.fill = sq:CreateTexture(nil, "ARTWORK")
    sq.fill:SetTexture(GuildOS.Style.ART.card)
    sq.fill:SetAllPoints()
    sq.mark = text(sq, 12, { r = 1, g = 1, b = 1 }, "button")
    sq.mark:SetJustifyH("CENTER")
    sq.mark:SetPoint("CENTER", 0, 0)
    function sq:Set(letter, c)
        self.fill:SetVertexColor(c.r, c.g, c.b, 1)
        self.mark:SetText(letter or "")
    end
    return sq
end

-- A field's label over it (the mockup's .field), in the card's ink.
local function label(card)
    return text(card, 12, card.ink, nil)
end

-- A screen of cards over a sub-panel: a scroll area, cards added across both columns (0), to the left (1) or the right (2) column in
-- `order`, each with fill(width) returning its height (0 hides it). Laid out at once on a resize: a narrow
-- tab stacks the right column under the left.
local function cardScreen(panel, name)
    local scroll, content = UI:CreateScrollFrame(panel, name)
    scroll:SetAllPoints(panel)
    local s = { scroll = scroll, content = content, cards = {} }
    function s.add(card, col, order, fill)
        s.cards[#s.cards + 1] = { frame = card, col = col, order = order or #s.cards, fill = fill }
        table.sort(s.cards, function(a, b)
            if a.col ~= b.col then return a.col < b.col end
            return a.order < b.order
        end)
        return card
    end
    function s.layout()
        local w = (panel:GetWidth() or 0) - (UI.SCROLL_GUTTER or 12)
        if w < 60 then w = 600 end   -- not laid out yet (built hidden): OnSizeChanged lays it out again
        content:SetWidth(w)
        local two = w >= TWO_COLUMNS
        local lw = two and math.floor((w - GUTTER) * LEFT_SHARE) or w
        local rw = two and (w - GUTTER - lw) or w
        -- 2px in, so the paper's shadow is not cut at the scroll area's edge.
        local y = { 2, 2 }
        for _, c in ipairs(s.cards) do
            local right = two and c.col == 2
            local cw = right and rw or lw
            if c.col == 0 then cw = w end   -- a card across both columns, over them
            local h = c.fill(cw) or 0
            local slot = right and 2 or 1
            c.frame:ClearAllPoints()
            c.frame:SetPoint("TOPLEFT", right and (lw + GUTTER) or 0, -y[slot])
            c.frame:SetSize(cw, math.max(1, h))
            c.frame:SetShown(h > 0)
            if h > 0 then y[slot] = y[slot] + h + GUTTER end
            if c.col == 0 then y[2] = y[1] end
        end
        content:SetHeight(math.max(y[1], y[2]) + 8)
    end
    panel:SetScript("OnSizeChanged", function() GuildOS:SafeCall(s.layout) end)
    return s
end

-- A short dark card of one paragraph (the mockup's H.dark with a .sm line).
local function noteCard(parent, title, body)
    local card = UI:CreateCard(parent, title, { dark = true })
    card.body = text(card, 12, card.soft, nil, true)
    card.body:SetPoint("TOPLEFT", PAD, -TOP)
    card.body:SetText(body)
    return card, function(w)
        card.body:SetWidth(w - 2 * PAD)
        return TOP + (card.body:GetStringHeight() or 14) + PAD
    end
end

----------------------------------------------------------------------
-- ACTIVITY sub-panel: what happened in the guild, in categories (#449, the maintainer: "can we make this screen
-- categorized?"). A row of pills picks the period (today, 7 or 30 days); each category of the digest's model
-- (Digest:Collect: members, levels and milestones, dungeons and raids, loot, achievements and renown, guild life,
-- guildos.me) is a card, in two columns from SP.TWO_COLS, hidden when it has nothing to say. Members are counts
-- (KPI chips) and names; the level cap is one list of names in their class's ink, each person once; the milestones
-- every ten levels are a line each, their names under it. A long list of names shows a few and "and N more".
----------------------------------------------------------------------
local SP = UI.SP
local ACTIVITY_PERIODS = {
    { id = "today", label = L["Today"] },
    { id = "week",  label = L["7 days"], days = 7 },
    { id = "month", label = L["30 days"], days = 30 },
}
local NAMES_SHOWN = 12   -- names in a list before "and N more"
local ROW_GLYPH = 24

-- Where a period starts: today's midnight (the realm's clock as the game gives it), or N days back.
local function periodStart(period, now)
    if period.days then return now - period.days * 86400 end
    local ok, t = pcall(date, "*t", now)
    if ok and type(t) == "table" then
        return now - ((t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0))
    end
    return now - 86400
end

-- Short name -> class file, from the roster and the synced member data, for the names' ink.
local function classesByName()
    local out = {}
    for key, m in pairs(GuildOS.db.members or {}) do
        local cf = type(m) == "table" and (m.classFile or m.class)
        if type(cf) == "string" and GuildOS.ClassColors[cf] then out[(key:match("^(.-)%-[^-]*$") or key)] = cf end
    end
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local full, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if full and classFile then out[GuildOS:ShortName(full)] = classFile end
    end
    return out
end

-- What a card draws, from pools: texts, glyphs, links and metric chips, reused on every layout.
local function cardPool(card)
    local P = { fs = {}, gl = {}, bt = {}, ch = {}, used = {} }
    function P.begin() P.used = { fs = 0, gl = 0, bt = 0, ch = 0 } end
    local function take(kind, make)
        P.used[kind] = P.used[kind] + 1
        local o = P[kind][P.used[kind]]
        if not o then o = make(); P[kind][P.used[kind]] = o end
        o:ClearAllPoints()
        o:Show()
        return o
    end
    function P.text(size, color, wrap)
        local fs = take("fs", function() return text(card, size, color, nil, wrap) end)
        GuildOS:ApplyFont(fs, size)
        fs:SetTextColor(color.r, color.g, color.b)
        fs:SetWordWrap(wrap and true or false)
        fs:SetJustifyH("LEFT")
        return fs
    end
    function P.glyph() return take("gl", function() return UI:CreateGlyph(card, ROW_GLYPH) end) end
    function P.link(caption, onClick)
        local b = take("bt", function() return UI:SetButtonVariant(UI:CreateButton(card, "", 40, SP.HIT), "ghost") end)
        b.label:SetText(caption)
        b:SetWidth(math.ceil(b.label:GetStringWidth() or 40) + 4)
        b:SetScript("OnClick", onClick)
        return b
    end
    function P.chip(value, caption)
        local c = take("ch", function() return UI:CreateMetricChip(card, "", "") end)
        c:SetValue(tostring(value))
        c.label:SetText(caption)
        c:SetWidth(math.max(56, math.ceil(c.value:GetStringWidth() or 0), math.ceil(c.label:GetStringWidth() or 0)) + 24)
        return c
    end
    function P.finish()
        for kind, list in pairs({ fs = P.fs, gl = P.gl, bt = P.bt, ch = P.ch }) do
            for i = P.used[kind] + 1, #list do list[i]:Hide() end
        end
    end
    return P
end

local function BuildActivitySub(panel)
    local Digest = GuildOS.Digest
    local scroll, content = UI:CreateScrollFrame(panel, "GuildOSHubActivityScroll")
    scroll:SetAllPoints(panel)
    local state = { period = ACTIVITY_PERIODS[2], model = nil, expanded = {}, classes = {} }
    local layout

    -- The period, as pills on the wood.
    local pills = {}
    for i, p in ipairs(ACTIVITY_PERIODS) do
        local b = UI:SetButtonVariant(UI:CreateButton(content, p.label, 80, SP.FIELD), "chip")
        b:SetWidth(math.max(64, math.ceil(b.label:GetStringWidth() or 40) + 2 * SP.PAD))
        b:SetPoint("TOPLEFT", (i == 1) and 2 or 0, -2)
        if i > 1 then b:SetPoint("TOPLEFT", pills[i - 1], "TOPRIGHT", SP.UNIT * 2, 0) end
        b:SetScript("OnClick", function()
            state.period = p
            state.expanded = {}
            GuildOS:SafeCall(panel.activityRefresh)
        end)
        pills[i] = b
    end

    local empty = UI:CreateEmptyState(content, "!")

    -- One card per category, each drawn by a function of (card, pool, width, data) returning its height (0: none).
    local function ink(name)
        local cf = state.classes[name]
        if not cf then return name end
        return "|cff" .. GuildOS:GetClassColorHex(cf) .. name .. "|r"
    end

    -- A list of names in their class's ink, wrapped; past NAMES_SHOWN, "and N more" opens the rest.
    local function names(P, card, y, x, w, list, key)
        local shown, open = {}, state.expanded[key]
        local cut = open and #list or math.min(#list, NAMES_SHOWN)
        for i = 1, cut do
            local n = list[i]
            shown[i] = type(n) == "table" and (ink(n.name) .. " (" .. tostring(n.detail) .. ")") or ink(n)
        end
        local fs = P.text(SP.BODY, card.ink, true)
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetWidth(w - x - SP.PAD)
        UI:SetInkText(fs, table.concat(shown, ", "))
        y = y + math.ceil(fs:GetStringHeight() or 14) + SP.UNIT
        if #list > NAMES_SHOWN then
            local more = open and L["Show less"] or string.format(L["and %d more"], #list - NAMES_SHOWN)
            local b = P.link(more, function()
                state.expanded[key] = not state.expanded[key] or nil
                GuildOS:SafeCall(layout)
            end)
            b:SetPoint("TOPLEFT", x - 2, -y + SP.UNIT)
            y = y + SP.HIT
        end
        return y
    end

    -- A line on a round glyph (the category's mark in its colour, or the row's own).
    local function row(P, card, y, w, letter, color, line, meta)
        local g = P.glyph()
        g:SetPoint("TOPLEFT", SP.PAD, -y)
        g:Set(letter, color)
        local x = SP.PAD + ROW_GLYPH + SP.CELL
        local fs = P.text(SP.BODY, card.ink, true)
        fs:SetPoint("TOPLEFT", x, -(y + 5))
        local right = 0
        if meta then
            local m = P.text(SP.META, card.soft)
            m:SetText(meta)
            m:SetPoint("TOPRIGHT", -SP.PAD, -(y + 6))
            right = math.ceil(m:GetStringWidth() or 0) + SP.CELL
        end
        fs:SetWidth(w - x - SP.PAD - right)
        UI:SetInkText(fs, line)
        return y + math.max(ROW_GLYPH, math.ceil(fs:GetStringHeight() or 14) + 6) + SP.UNIT, x
    end

    local function section(P, card, y, caption)
        local fs = P.text(SP.META + 1, card.soft)
        fs:SetText(caption)
        fs:SetPoint("TOPLEFT", SP.PAD, -y)
        return y + SP.TITLE_H
    end

    local function lines(P, card, y, w, cat, list)
        local color = Digest.Color(cat.color)
        for _, line in ipairs(list) do y = row(P, card, y, w, cat.glyph, color, line) end
        return y
    end

    local function namesOf(list, withDetail)
        local out = {}
        for i, e in ipairs(list) do out[i] = (withDetail and e.detail) and { name = e.name, detail = e.detail } or e.name end
        return out
    end

    local DRAW = {}
    function DRAW.members(P, card, w, d, cat)
        local kinds = {
            { list = d.joined,  label = L["Joined"] },
            { list = d.left,    label = L["Left"] },
            { list = d.kick,    label = L["Removed"] },
            { list = d.promote, label = L["Promoted"], detail = true },
            { list = d.demote,  label = L["Demoted"], detail = true },
        }
        local y, x = SP.TOP, SP.PAD
        local rowH = 0
        for _, k in ipairs(kinds) do
            if k.list and #k.list > 0 then
                local c = P.chip(#k.list, k.label)
                local cw = c:GetWidth()
                if x > SP.PAD and x + cw > w - SP.PAD then x, y = SP.PAD, y + rowH + SP.UNIT * 2 end
                c:SetPoint("TOPLEFT", x, -y)
                x = x + cw + SP.UNIT * 2
                rowH = math.max(rowH, c:GetHeight())
            end
        end
        if rowH > 0 then y = y + rowH + SP.SECTION end
        for i, k in ipairs(kinds) do
            if k.list and #k.list > 0 then
                y = section(P, card, y, k.label)
                y = names(P, card, y, SP.PAD, w, namesOf(k.list, k.detail), "members" .. i) + SP.UNIT
            end
        end
        local extra = {}
        for _, a in ipairs(d.anniversaries or {}) do
            extra[#extra + 1] = string.format(L["%s is celebrating %d year(s) with the guild!"], a.name, a.years)
        end
        if d.inactive then extra[#extra + 1] = string.format(L["%d inactive member(s)"], d.inactive) end
        if #extra == 0 and y == SP.TOP then return 0 end
        return lines(P, card, y, w, cat, extra) - SP.UNIT + SP.PAD
    end

    function DRAW.levels(P, card, w, d, cat)
        local y = SP.TOP
        local color = Digest.Color(cat.color)
        if d.dings and #d.dings > 0 then
            y = section(P, card, y, string.format(L["Reached level %s"], tostring(GuildOS.Client.maxLevel)))
            y = names(P, card, y, SP.PAD, w, namesOf(d.dings), "cap") + SP.UNIT * 2
        end
        if d.attunes and #d.attunes > 0 then
            y = section(P, card, y, L["Attunements"])
            y = names(P, card, y, SP.PAD, w, namesOf(d.attunes), "attune") + SP.UNIT * 2
        end
        for _, g in ipairs(d.levels or {}) do
            local x
            y, x = row(P, card, y, w, tostring(g.level), color,
                string.format(L["Level %s — %d member(s)"], tostring(g.level), #g.names))
            y = names(P, card, y - SP.UNIT, x, w, g.names, "level" .. g.level) + SP.UNIT
        end
        if y == SP.TOP then return 0 end
        return y - SP.UNIT + SP.PAD
    end

    function DRAW.dungeons(P, card, w, d, cat)
        local y = SP.TOP
        local color = Digest.Color(cat.color)
        for _, g in ipairs(d.clears or {}) do
            local line = string.format(L["%s — %d member(s)"], g.name, #g.names)
            if g.first then
                local t = C.paperTitle
                line = line .. string.format("  |cff%02x%02x%02x", t.r * 255 + 0.5, t.g * 255 + 0.5, t.b * 255 + 0.5) .. L["First clear"] .. "|r"
            end
            local x
            y, x = row(P, card, y, w, "D", color, line)
            y = names(P, card, y - SP.UNIT, x, w, g.names, "clear" .. tostring(g.id)) + SP.UNIT
        end
        for _, r in ipairs(d.raids or {}) do
            y = row(P, card, y, w, "R", color, r.name, GuildOS:TimeAgo(r.at))
        end
        if y == SP.TOP then return 0 end
        return y - SP.UNIT + SP.PAD
    end

    local function qualityColor(q)
        local Compat = GuildOS.Compat
        if q and Compat and Compat.GetItemQualityColor then
            local r, g, b = Compat.GetItemQualityColor(q)
            if r then return { r = r, g = g, b = b } end
        end
        return Digest.Color("7a3d9a")
    end

    -- An item as its name in its quality's colour: the link's own colour, or the quality's (the card's text takes
    -- no hyperlink: a link drawn raw would show its code).
    local function itemText(it)
        local link = tostring(it.link or "?")
        local name = link:match("%[(.-)%]") or link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local code = link:match("^|c(%x%x%x%x%x%x%x%x)")
        if not code and it.quality then
            local c = qualityColor(it.quality)
            code = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
        return code and ("|c" .. code .. "[" .. name .. "]|r") or ("[" .. name .. "]"), name
    end

    function DRAW.loot(P, card, w, d)
        local y = SP.TOP
        for _, it in ipairs(d.items or {}) do
            local who = it.player and ink(GuildOS:ShortName(it.player)) or nil
            local item, name = itemText(it)
            local code = item:match("^|cff(%x%x%x%x%x%x)")
            local color = code and Digest.Color(code) or qualityColor(it.quality)
            local line = who and string.format(L["%s received %s"], who, item) or item
            y = row(P, card, y, w, UI.Initial(name), color, line, GuildOS:TimeAgo(it.at))
        end
        if y == SP.TOP then return 0 end
        return y - SP.UNIT + SP.PAD
    end

    local cards = {}
    for _, cat in ipairs(Digest and Digest.CATEGORIES or {}) do
        local card = UI:CreateCard(content, cat.title)
        local P = cardPool(card)
        cards[#cards + 1] = { frame = card, cat = cat, fill = function(w)
            P.begin()
            local d = state.model and state.model[cat.id]
            local h = 0
            if d then
                if DRAW[cat.id] then
                    h = DRAW[cat.id](P, card, w, d, cat)
                elseif #d.lines > 0 then
                    h = lines(P, card, SP.TOP, w, cat, d.lines) - SP.UNIT + SP.PAD
                end
            end
            P.finish()
            return h
        end }
    end

    -- The cards in two columns from SP.TWO_COLS (each into the shorter one), one under the other below it.
    layout = function()
        local w = (panel:GetWidth() or 0) - (UI.SCROLL_GUTTER or 12)
        if w < 60 then w = 600 end   -- not laid out yet (built hidden): OnSizeChanged lays it out again
        content:SetWidth(w)
        for i, b in ipairs(pills) do UI:SetSelected(b, ACTIVITY_PERIODS[i] == state.period) end
        local top = 2 + SP.FIELD + SP.GAP
        local two = w >= SP.TWO_COLS
        local cw = two and math.floor((w - 4 - SP.GAP) / 2) or (w - 4)
        local y = { top, top }
        local any = false
        for _, c in ipairs(cards) do
            local h = c.fill(cw) or 0
            c.frame:SetShown(h > 0)
            if h > 0 then
                any = true
                local col = (two and y[2] < y[1]) and 2 or 1
                c.frame:ClearAllPoints()
                c.frame:SetPoint("TOPLEFT", 2 + (col == 2 and (cw + SP.GAP) or 0), -y[col])
                c.frame:SetSize(cw, h)
                y[col] = y[col] + h + SP.GAP
            end
        end
        empty:SetShown(not any)
        if not any then
            local p = state.period
            empty:SetWidth(math.min(420, w - 4))
            empty:Set(p.id == "today" and L["Nothing new today."]
                or p.id == "month" and L["Nothing new in the last 30 days."]
                or L["Nothing new in the last 7 days."])
            empty:ClearAllPoints()
            empty:SetPoint("TOP", content, "TOP", 0, -(top + SP.SECTION * 2))
            y[1] = top + SP.SECTION * 2 + (empty:GetHeight() or 120)
        end
        content:SetHeight(math.max(y[1], y[2]) + 8)
    end
    panel:SetScript("OnSizeChanged", function() GuildOS:SafeCall(layout) end)
    panel.activityState, panel.activityCards, panel.activityPills, panel.activityEmpty = state, cards, pills, empty

    local function refresh()
        state.model = nil
        if Digest then
            local now = GetServerTime()
            state.model = Digest:Collect(periodStart(state.period, now))
        end
        state.classes = classesByName()
        layout()
    end
    panel.activityRefresh = refresh
    return refresh
end
UI.BuildActivityScreen = BuildActivitySub   -- the hub's Activity sub-tab; tools/activity-categories.lua builds it alone

----------------------------------------------------------------------
-- BULLETIN sub-panel: the notices as pinned notes, the polls as bars, the officers' forms on the right.
----------------------------------------------------------------------
-- The polls, drawn on the board under the notices (audit B24): what a poll is, a kind of notice.
local function pollKey(name)
    local short = (name or ""):match("^([^-]+)") or name
    return GuildOS:GetPlayerKey(short, GetRealmName())
end

-- What a poll's bars show: { text, n, pct, mine } per option, the total and this player's vote.
local function tally(p, myKey)
    local total, counts = 0, {}
    for _, opt in pairs(p.votes or {}) do counts[opt] = (counts[opt] or 0) + 1; total = total + 1 end
    local out = {}
    for idx, optText in ipairs(p.options or {}) do
        local n = counts[idx] or 0
        out[idx] = { text = optText, n = n, pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0 }
    end
    return out, total, p.votes and p.votes[myKey]
end

-- One option of a poll (the mockup's .poll button): a light bar filled to its share, "Option · n · p%" on it,
-- this player's vote outlined in the soft gold. A click votes while the poll is open.
local function pollBar(card)
    local b = CreateFrame("Button", nil, card)
    b:SetHeight(30)
    local bg = GuildOS.Style:Nine(b, "card", 5, "BACKGROUND", 1)
    bg:SetColor(C.paperLight)
    b.line = GuildOS.Style:Nine(b, "card-line", 5, "BORDER", 0)
    b.fill = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.fill:SetTexture(WHITE)
    b.fill:SetVertexColor(POLL_FILL.r, POLL_FILL.g, POLL_FILL.b, 1)
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMLEFT", 1, 1)
    b.label = text(b, 13, card.ink)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -10, 0)
    b:SetScript("OnClick", function(self) if self.vote then self.vote() end end)
    return b
end

local function drawPolls(card, y, w, p, myKey)
    card.bars = card.bars or {}
    local opts, total, myVote = tally(p, myKey)
    for idx, o in ipairs(opts) do
        local b = card.bars[idx] or pollBar(card)
        card.bars[idx] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PAD, -y)
        b:SetWidth(w - 2 * PAD)
        b.fill:SetWidth(math.max(1, (w - 2 * PAD - 2) * o.pct / 100))
        b.fill:SetShown(o.pct > 0)
        b.label:SetText(string.format("%s \194\183 %d \194\183 %d%%", o.text, o.n, o.pct))
        local mine = myVote == idx
        b.line:SetColor(mine and C.paperTitle or C.paperRule)
        b.mine = mine
        local id, oi = p.id, idx
        b.vote = (not p.closed) and function() if GuildOS.Polls then GuildOS.Polls:Vote(id, oi) end end or nil
        b:Show()
        y = y + 34
    end
    for idx = #opts + 1, #card.bars do card.bars[idx]:Hide() end
    card.meta = card.meta or text(card, 12, card.soft)
    card.meta:ClearAllPoints()
    card.meta:SetPoint("TOPLEFT", PAD, -(y + 2))
    card.meta:SetText(string.format(L["%d vote(s) · by %s"], total, p.author or "?"))
    return y + 22
end

-- A pinned note (as the Salão's board): cream, a red pin, the notice in the reading face, who and until under it,
-- and an officer's "Remove" link.
local function pinnedNote(board)
    local n = CreateFrame("Frame", nil, board)
    local shade = GuildOS.Style:Nine(n, "shadow", 12, "BACKGROUND", 0, { -6, -5, -8, -10 })
    shade:SetRGBA(0, 0, 0, 0.25)
    local fill = GuildOS.Style:Nine(n, "card", 3, "BACKGROUND", 1)
    fill:SetColor(C.paperLight)
    n.pin = GuildOS.Style:Texture(n, "orb", "OVERLAY", 1)
    n.pin:SetSize(11, 11)
    n.pin:SetPoint("CENTER", n, "TOP", 0, 0)
    n.pin:SetVertexColor(0.85, 0.2, 0.15, 1)
    n.text = text(n, 13, C.paperInk, "reading", true)
    n.text:SetPoint("TOPLEFT", 10, -12)
    n.meta = text(n, 11, C.paperSoft, nil, true)
    n.meta:SetPoint("TOPLEFT", n.text, "BOTTOMLEFT", 0, -6)
    if GuildOS:IsOfficer() then
        n.del = UI:SetButtonVariant(UI:CreateButton(n, L["Remove"], 50, 16), "ghost")
        n.del:SetWidth(math.ceil(n.del.label:GetStringWidth()) + 4)
        n.del:SetPoint("BOTTOMRIGHT", -8, 6)
        n.del:SetScript("OnClick", function() if n.id and GuildOS.Bulletin then GuildOS.Bulletin:Remove(n.id) end end)
    end
    return n
end

local function BuildBulletinSub(panel)
    local screen = cardScreen(panel, "GuildOSHubBulletinScroll")
    local content = screen.content
    local isOfficer = GuildOS:IsOfficer()
    local msgs, polls, myKey = {}, {}, nil

    -- The board: the notices as pinned notes, two or three to a row.
    local board = UI:CreateCard(content, L["Notice board"])
    board.notes = {}
    board.empty = text(board, 12, board.soft)
    board.empty:SetText(L["No notices yet."])
    screen.add(board, 1, 1, function(w)
        local inner = w - 2 * PAD
        local perRow = inner >= 560 and 3 or (inner >= 300 and 2 or 1)
        local noteW = math.floor((inner - (perRow - 1) * NOTE_GAP) / perRow)
        local y = TOP + 6
        local rowH = 0
        for i, m in ipairs(msgs) do
            local n = board.notes[i] or pinnedNote(board)
            board.notes[i] = n
            local col = (i - 1) % perRow
            if col == 0 and i > 1 then y = y + rowH + NOTE_GAP + 4; rowH = 0 end
            n.id = m.id
            n.text:SetWidth(noteW - 20)
            n.text:SetText(m.text or "")
            n.meta:SetWidth(noteW - 20 - (n.del and (n.del:GetWidth() + 4) or 0))
            n.meta:SetText(GuildOS.Bulletin.MetaText(m))
            local h = 12 + (n.text:GetStringHeight() or 14) + 6 + (n.meta:GetStringHeight() or 12) + 10
            if n.del then h = h + 4 end
            rowH = math.max(rowH, h)
            n:ClearAllPoints()
            n:SetPoint("TOPLEFT", PAD + col * (noteW + NOTE_GAP), -y)
            n:SetWidth(noteW)
            n:Show()
        end
        -- Every note of a row as tall as its tallest.
        local first = 1
        for i = 1, #msgs do
            if (i - 1) % perRow == perRow - 1 or i == #msgs then
                local tall = 0
                for j = first, i do
                    local n = board.notes[j]
                    tall = math.max(tall, 12 + (n.text:GetStringHeight() or 14) + 6 + (n.meta:GetStringHeight() or 12) + 10
                        + (n.del and 4 or 0))
                end
                for j = first, i do board.notes[j]:SetHeight(tall) end
                first = i + 1
            end
        end
        for i = #msgs + 1, #board.notes do board.notes[i]:Hide() end
        board.empty:ClearAllPoints()
        board.empty:SetPoint("TOPLEFT", PAD, -(TOP))
        board.empty:SetShown(#msgs == 0)
        if #msgs == 0 then return TOP + 20 + PAD end
        return y + rowH + PAD + 4
    end)

    -- A card per open poll: the question as its title, a bar per option; an officer closes it from the title's link.
    local pollCards = {}
    local function pollCard(i)
        if pollCards[i] then return pollCards[i] end
        local card = UI:CreateCard(content, "", isOfficer and { link = L["Close"] } or nil)
        if card.link then
            card.link:SetScript("OnClick", function() if card.pollId and GuildOS.Polls then GuildOS.Polls:Close(card.pollId) end end)
        end
        pollCards[i] = card
        screen.add(card, 1, 10 + i, function(w)
            local p = card.poll
            if not p then return 0 end
            GuildOS:SetTitleText(card.title, p.question or "")
            return drawPolls(card, TOP, w, p, myKey) + PAD - 6
        end)
        return card
    end

    -- The closed polls, a line each: a square, the question, the winner under it.
    local closed = UI:CreateCard(content, L["Closed"])
    closed.rows = {}
    screen.add(closed, 1, 100, function(w)
        local y = TOP
        local n = 0
        for _, p in ipairs(polls) do
            if p.closed then
                n = n + 1
                local r = closed.rows[n]
                if not r then
                    r = CreateFrame("Frame", nil, closed)
                    r:SetHeight(40)
                    r.sq = square(r, 28)
                    r.sq:SetPoint("LEFT", 0, 0)
                    r.main = text(r, 13, closed.ink, "memberName")
                    r.main:SetPoint("TOPLEFT", 38, -3)
                    r.main:SetPoint("RIGHT", 0, 0)
                    r.side = text(r, 11, closed.soft)
                    r.side:SetPoint("TOPLEFT", r.main, "BOTTOMLEFT", 0, -3)
                    r.side:SetPoint("RIGHT", 0, 0)
                    closed.rows[n] = r
                end
                local opts, total = tally(p, myKey)
                local best
                for _, o in ipairs(opts) do if o.n > 0 and (not best or o.n > best.n) then best = o end end
                r.sq:Set(best and UI.Initial(best.text) or "-", SQUARE_PAST)
                r.main:SetText(p.question or "")
                r.side:SetText(best and string.format(L["%s won with %d of %d votes"], best.text, best.n, total)
                    or L["closed"])
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", PAD, -y)
                r:SetWidth(w - 2 * PAD)
                r:Show()
                y = y + 44
            end
        end
        for i = n + 1, #closed.rows do closed.rows[i]:Hide() end
        if n == 0 then return 0 end
        return y + PAD - 6
    end)

    local box, lasts
    if isOfficer then
        -- The officers' forms, on the right: a notice, then a poll.
        local form = UI:CreateCard(content, L["New notice"])
        local l1 = label(form)
        l1:SetText(L["Notice (up to 200 letters)"])
        l1:SetPoint("TOPLEFT", PAD, -TOP)
        box = UI:CreateInput(form, 0, FIELD_H, { max = 200, placeholder = L["E.g.: a meeting on Sunday after the run"] })
        box:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -6)
        box:SetPoint("RIGHT", form, "RIGHT", -PAD, 0)
        local l2 = label(form)
        l2:SetText(L["Shown until"])
        l2:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
        -- How long the notice lasts (issue #418): some days, or until an officer removes it.
        lasts = UI:CreateDropdown(form, 160, FIELD_H)
        lasts:SetOptions(GuildOS.Bulletin and GuildOS.Bulletin:DurationOptions() or {})
        lasts:SetValue(0)
        lasts:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -6)
        lasts:SetPoint("RIGHT", form, "RIGHT", -PAD, 0)
        panel.lasts = lasts
        local postBtn = UI:SetButtonVariant(UI:CreateButton(form, L["Post"], 84, FIELD_H + 2), "primary")
        postBtn:SetPoint("TOPLEFT", lasts, "BOTTOMLEFT", 0, -12)
        local function doPost()
            if GuildOS.Bulletin then GuildOS.Bulletin:Post(box:GetText(), lasts:GetValue()) end
            box:SetText(""); box:ClearFocus()
        end
        box:SetScript("OnEnterPressed", doPost)
        postBtn:SetScript("OnClick", doPost)
        screen.add(form, 2, 1, function() return TOP + 16 + 6 + FIELD_H + 10 + 16 + 6 + FIELD_H + 12 + FIELD_H + 2 + PAD end)

        -- The poll: the question, then three lines of options with what they take under it.
        local pf = UI:CreateCard(content, L["New poll"])
        local q1 = label(pf)
        q1:SetText(L["Question"])
        q1:SetPoint("TOPLEFT", PAD, -TOP)
        local qBox = UI:CreateInput(pf, 0, FIELD_H, { max = 150, placeholder = L["Question..."] })
        qBox:SetPoint("TOPLEFT", q1, "BOTTOMLEFT", 0, -6)
        qBox:SetPoint("RIGHT", pf, "RIGHT", -PAD, 0)
        local q2 = label(pf)
        q2:SetText(L["One option per line (2-6)"])
        q2:SetPoint("TOPLEFT", qBox, "BOTTOMLEFT", 0, -10)
        local oArea = UI:CreateTextArea(pf, 0, 56)   -- a multi-line EditBox alone shrinks to one line
        oArea:SetPoint("TOPLEFT", q2, "BOTTOMLEFT", 0, -6)
        oArea:SetPoint("RIGHT", pf, "RIGHT", -PAD, 0)
        local oBox = oArea.edit
        local createBtn = UI:SetButtonVariant(UI:CreateButton(pf, L["Create Poll"], 110, FIELD_H + 2), "primary")
        createBtn:SetPoint("TOPLEFT", oArea, "BOTTOMLEFT", 0, -12)
        createBtn:SetScript("OnClick", function()
            local opts = {}
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                local t = strtrim(line)
                if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
            end
            if GuildOS.Polls then GuildOS.Polls:Create(qBox:GetText(), opts) end
            qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
        end)
        screen.add(pf, 2, 2, function() return TOP + 16 + 6 + FIELD_H + 10 + 16 + 6 + 56 + 12 + FIELD_H + 2 + PAD end)
    else
        local who, fill = noteCard(content, L["Who writes here"],
            L["The officers post notices for the whole guild. The newest also show in the Salão."])
        screen.add(who, 2, 1, fill)
    end

    local function refresh()
        msgs = (GuildOS.Bulletin and GuildOS.Bulletin:Listed()) or {}
        polls = (GuildOS.Polls and GuildOS.Polls:GetSorted()) or {}
        myKey = pollKey(GuildOS.Compat.PlayerName())
        local open = 0
        for _, p in ipairs(polls) do
            if not p.closed then
                open = open + 1
                local card = pollCard(open)
                card.poll, card.pollId = p, p.id
                if card.link then card.link:Show() end
            end
        end
        for i = open + 1, #pollCards do pollCards[i].poll = nil end
        screen.layout()
    end
    -- Only while it is on screen (memory audit): showing it refreshes it anyway.
    local function onChange() if panel:IsVisible() then refresh() end end
    if GuildOS.Bulletin then GuildOS.Bulletin.uiRefresh = onChange end
    if GuildOS.Polls then GuildOS.Polls.uiRefresh = onChange end
    return refresh
end

----------------------------------------------------------------------
-- RULES sub-panel (issue #407): the guild's rules for everybody to read; the officers write them here.
----------------------------------------------------------------------
local RULE_WHY = {
    officer = L["|cffFF4444Officers only.|r"],
    empty = L["A rule needs a title."],
    full = L["The list is full."],
    missing = L["That rule is gone."],
}

local function BuildGuildRulesSub(panel)
    local GR = GuildOS.GuildRules
    local screen = cardScreen(panel, "GuildOSHubRulesScroll")
    local content = screen.content
    local editing   -- the number of the rule the form rewrites, nil while it adds one
    local titleBox, textBox, saveBtn, cancelBtn, result
    local list = UI:CreateCard(content, L["The guild's rules"])

    if GuildOS:IsOfficer() and GR then
        -- Title then text, each with its label over it (the mockup's .field), then the buttons.
        local form = UI:CreateCard(content, L["New rule"])
        local tLabel = label(form)
        tLabel:SetText(L["Title"])
        tLabel:SetPoint("TOPLEFT", PAD, -TOP)
        titleBox = UI:CreateInput(form, 0, FIELD_H, { max = GR.TITLE_MAX })
        titleBox:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 0, -6)
        titleBox:SetPoint("RIGHT", form, "RIGHT", -PAD, 0)
        local xLabel = label(form)
        xLabel:SetText(L["Text"])
        xLabel:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", 0, -10)
        textBox = UI:CreateInput(form, 0, FIELD_H, { max = GR.TEXT_MAX })
        textBox:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -6)
        textBox:SetPoint("RIGHT", form, "RIGHT", -PAD, 0)
        saveBtn = UI:SetButtonVariant(UI:CreateButton(form, L["Add rule"], 120, FIELD_H + 2), "primary")
        saveBtn:SetPoint("TOPLEFT", textBox, "BOTTOMLEFT", 0, -12)
        cancelBtn = UI:CreateButton(form, L["Cancel"], 90, FIELD_H + 2)
        cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
        cancelBtn:Hide()
        result = text(form, 11, form.soft, nil, true)
        result:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -8)
        local function stopEditing()
            editing = nil
            titleBox:SetText(""); textBox:SetText("")
            titleBox:ClearFocus(); textBox:ClearFocus()
            saveBtn.label:SetText(L["Add rule"])
            GuildOS:SetTitleText(form.title, L["New rule"])
            cancelBtn:Hide()
        end
        panel.stopEditing = stopEditing
        local function doSave()
            local ok, why
            if editing then
                ok, why = GR:Update(editing, titleBox:GetText(), textBox:GetText())
            else
                ok, why = GR:Add(titleBox:GetText(), textBox:GetText())
            end
            if ok then
                stopEditing()
                result:SetText(L["Saved. The guild gets it now."])
            else
                result:SetText(RULE_WHY[why] or RULE_WHY.empty)
            end
        end
        saveBtn:SetScript("OnClick", doSave)
        textBox:SetScript("OnEnterPressed", doSave)
        cancelBtn:SetScript("OnClick", stopEditing)
        panel.editRule = function(n)
            local r = GR:Rule(n)
            if not r then return end
            editing = n
            titleBox:SetText(r.title); textBox:SetText(r.text or "")
            saveBtn.label:SetText(L["Save rule"])
            GuildOS:SetTitleText(form.title, L["Edit rule"])
            cancelBtn:Show()
        end
        screen.add(form, 2, 1, function(w)
            result:SetWidth(w - 2 * PAD)
            local rh = (result:GetText() or "") ~= "" and ((result:GetStringHeight() or 12) + 8) or 0
            return TOP + 16 + 6 + FIELD_H + 10 + 16 + 6 + FIELD_H + 12 + FIELD_H + 2 + rh + PAD
        end)
    end
    local where, whereFill = noteCard(content, L["Where else it shows"],
        L["The rules also go to the guild's page on the site, for whoever joins to read."])
    screen.add(where, 2, 2, whereFill)

    -- One frame per rule, made once and refilled (at most GR.RULES_MAX): its title in the title face and the
    -- paper's red, the rule in the reading face, an officer's links under it.
    local rows = {}
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, list)
        row.title = text(row, 12, C.paperTitle, "sectionTitle")
        row.title:SetPoint("TOPLEFT", 0, 0)
        row.title:SetPoint("TOPRIGHT", 0, 0)
        row.text = text(row, 13, list.ink, "reading", true)
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
        if panel.editRule then
            local function ghost(caption, w)
                return UI:SetButtonVariant(UI:CreateButton(row, caption, w, 16), "ghost")
            end
            row.edit = ghost(L["Edit"], 40)
            row.edit:SetWidth(math.ceil(row.edit.label:GetStringWidth()) + 4)
            row.edit:SetScript("OnClick", function() panel.editRule(row.n) end)
            row.up = ghost(L["Move up"], 60)
            row.up:SetWidth(math.ceil(row.up.label:GetStringWidth()) + 4)
            row.up:SetPoint("LEFT", row.edit, "RIGHT", 10, 0)
            row.up:SetScript("OnClick", function() GR:MoveUp(row.n); if panel.stopEditing then panel.stopEditing() end end)
            row.del = ghost(L["Remove"], 60)
            row.del:SetWidth(math.ceil(row.del.label:GetStringWidth()) + 4)
            row.del:SetScript("OnClick", function() GR:Remove(row.n); if panel.stopEditing then panel.stopEditing() end end)
        end
        rows[i] = row
        return row
    end
    local empty = text(list, 12, list.soft, nil, true)
    empty:SetText(L["The guild has not written its rules yet."])
    empty:SetPoint("TOPLEFT", PAD, -TOP)

    local rules = {}
    screen.add(list, 1, 1, function(w)
        local y = TOP
        local inner = w - 2 * PAD
        for i, r in ipairs(rules) do
            local row = rowAt(i)
            row.n = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -y)
            row:SetWidth(inner)
            GuildOS:SetTitleText(row.title, r.title or "")
            row.text:SetWidth(inner)
            row.text:SetText(r.text or "")
            local h = 16 + (((r.text or "") ~= "") and (5 + (row.text:GetStringHeight() or 14)) or 0)
            if row.edit then
                row.edit:ClearAllPoints()
                row.edit:SetPoint("TOPLEFT", 0, -(h + 4))
                row.up:SetShown(i > 1)
                row.del:ClearAllPoints()
                row.del:SetPoint("LEFT", i > 1 and row.up or row.edit, "RIGHT", 10, 0)
                h = h + 4 + 16
            end
            row:SetHeight(h)
            row:Show()
            y = y + h + 14
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        empty:SetWidth(inner)
        empty:SetShown(#rules == 0)
        if #rules == 0 then y = y + 22 end
        return y + PAD - 10
    end)

    local function refresh()
        rules = GR and GR:Get() or {}
        screen.layout()
    end
    -- Only while it is on screen (memory audit): showing it refreshes it anyway.
    if GR then GR.uiRefresh = function() if panel:IsVisible() then refresh() end end end
    return refresh
end

----------------------------------------------------------------------
-- CALL TO ARMS sub-panel (issue #108): officers send, everyone sees the
-- recent calls, answers them and sets how they want to be told.
----------------------------------------------------------------------
local function BuildCallToArmsSub(panel)
    local CTA = GuildOS.CallToArms
    local selected = "worldboss"
    local screen = cardScreen(panel, "GuildOSHubCTAScroll")
    local content = screen.content
    -- { row frame, its widgets, line height }: wrapped again on every layout. A row grows to the lines it took,
    -- and what hangs below it moves down with it.
    local rows = {}
    local function flow(width)
        for _, r in ipairs(rows) do
            r[1]:SetWidth(math.max(60, width))
            UI:FlowBar(r[1], r[2], { gap = 6, rowGap = 6, rowH = r[3] })
        end
    end

    if GuildOS:IsOfficer() then
        local send = UI:CreateCard(content, L["Call the guild"])
        local tplRow, cells = CreateFrame("Frame", nil, send), {}
        tplRow:SetPoint("TOPLEFT", PAD, -TOP)
        rows[#rows + 1] = { tplRow, cells, 22 }

        local l1 = label(send)
        l1:SetText(L["Message (optional, {zone} becomes your zone)"])
        l1:SetPoint("TOPLEFT", tplRow, "BOTTOMLEFT", 0, -10)
        -- Left empty, the call carries the template's own message: the hint says so (#371).
        local msgBox = UI:CreateInput(send, 0, FIELD_H, { placeholder = L["Message (optional)"] })
        msgBox:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -6)
        msgBox:SetPoint("RIGHT", send, "RIGHT", -PAD, 0)
        msgBox:SetMaxBytes(CTA.TEXT_MAX + 1)   -- the call is cut at bytes, not letters: Cyrillic is two each
        local function sendNow()
            if CTA:Send(selected, msgBox:GetText()) then msgBox:ClearFocus() end
        end
        msgBox:SetScript("OnEnterPressed", sendNow)   -- a key press is a hardware event, as a click is
        send.msgBox = msgBox

        local chatCb = UI:CreateCheckbox(send, L["Also post in guild chat"], 16)
        chatCb:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", 0, -8)
        chatCb:SetWidth(30 + (chatCb.label:GetStringWidth() or 100))
        -- UI:CreateCheckbox inks its label for the wood: on the paper it takes the card's.
        chatCb.label:SetTextColor(send.ink.r, send.ink.g, send.ink.b)
        chatCb.checkbox:SetChecked(CTA:ChatOn())
        chatCb.checkbox.onChanged = function(_, checked) GuildOS:SetSetting("ctaChat", checked and true or false) end

        local sendBtn = UI:SetButtonVariant(UI:CreateButton(send, L["Send"], 88, FIELD_H + 2), "primary")
        sendBtn:SetPoint("TOPLEFT", chatCb, "BOTTOMLEFT", 0, -10)
        sendBtn:SetScript("OnClick", sendNow)

        -- A template's name is the title its calls go out under: saved from the message in the box.
        local nameBox = UI:CreateInput(send, 140, FIELD_H, { placeholder = L["Title"] })
        nameBox:SetMaxBytes(CTA.NAME_MAX + 1)
        local saveBtn = UI:CreateButton(send, L["Save as template"], 130, FIELD_H)
        saveBtn:SetPoint("TOPRIGHT", send, "TOPRIGHT", -PAD, 0)
        nameBox:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)

        -- The chosen template is marked as every selection is, the soft gold, never a ">" (#371).
        local function paintSelected()
            for _, cell in ipairs(cells) do
                UI:SetSelected(cell.btn, cell.id == selected)
                cell:SetWidth(cell.btn:GetWidth() + (cell.del and 19 or 0))
            end
        end
        -- Built again only when the list changes; picking one only marks it.
        local buildTemplates
        buildTemplates = function()
            for i = #cells, 1, -1 do cells[i]:Hide(); cells[i] = nil end
            for _, t in ipairs(CTA:Templates()) do
                local cell = CreateFrame("Frame", nil, tplRow)
                cell:SetHeight(22)
                cell.id = t.id
                cell.btn = UI:SetButtonVariant(UI:CreateButton(cell, t.name, 60, 22), "chip")
                cell.btn:SetWidth(math.ceil(cell.btn.label:GetStringWidth()) + 22)
                cell.btn:SetPoint("TOPLEFT")
                local id, msg = t.id, t.text
                cell.btn:SetScript("OnClick", function()
                    selected = id
                    msgBox:SetText(msg)
                    paintSelected()
                end)
                if not t.builtin then
                    cell.del = UI:CreateButton(cell, "\195\151", 18, 22)
                    cell.del:SetPoint("LEFT", cell.btn, "RIGHT", 1, 0)
                    cell.del:SetScript("OnClick", function()
                        CTA:DeleteTemplate(id)
                        if selected == id then selected = "worldboss" end
                        buildTemplates()
                        screen.layout()
                    end)
                end
                cells[#cells + 1] = cell
            end
            paintSelected()
        end
        saveBtn:SetScript("OnClick", function()
            local tpl = CTA:Template(selected)
            local ok, why = CTA:SaveTemplate(nameBox:GetText(), msgBox:GetText(), tpl and tpl.kind)
            if not ok then GuildOS:Print(why) return end
            nameBox:SetText("")
            buildTemplates()
            screen.layout()
        end)
        screen.add(send, 1, 1, function(w)
            flow(w - 2 * PAD)
            local y = TOP + (tplRow:GetHeight() or 22) + 10 + 16 + 6 + FIELD_H + 8 + 18 + 10
            saveBtn:ClearAllPoints()
            saveBtn:SetPoint("TOPRIGHT", send, "TOPRIGHT", -PAD, -(y + 1))
            return y + FIELD_H + 2 + PAD
        end)
        buildTemplates()
        msgBox:SetText(CTA:Template(selected).text)
    end

    -- The recent calls (the mockup's .todo): a red square while a call is open, the paper's brown once past; the
    -- call and its zone, who sent it and how many are on the way; "On my way" while it is open.
    local recent = UI:CreateCard(content, L["Recent calls"], GuildOS.LFGBoard and { link = L["Groups"] } or nil)
    -- /gos avail: who in the guild is free for a group, and listing yourself (#142).
    if recent.link then recent.link:SetScript("OnClick", function() GuildOS.LFGBoard:Show() end) end
    local lines = {}
    local empty = text(recent, 12, recent.soft)
    empty:SetText(L["No calls yet."])
    empty:SetPoint("TOPLEFT", PAD, -TOP)
    local function lineAt(i)
        if lines[i] then return lines[i] end
        local ln = CreateFrame("Frame", nil, recent)
        ln.rule = rule(ln, recent)
        ln.sq = square(ln, 28)
        ln.sq:SetPoint("TOPLEFT", 0, -8)
        ln.text = text(ln, 14, recent.ink, "itemName", true)
        ln.text:SetPoint("TOPLEFT", 38, -6)
        ln.meta = text(ln, 12, recent.soft, nil, true)
        ln.meta:SetPoint("TOPLEFT", ln.text, "BOTTOMLEFT", 0, -3)
        ln.go = UI:SetButtonVariant(UI:CreateButton(ln, L["On my way"], 90, 26), "primary")
        ln.go:SetWidth(math.max(90, math.ceil(ln.go.label:GetStringWidth()) + 22))
        ln.go:SetPoint("TOPRIGHT", 0, -8)
        ln.go:SetScript("OnClick", function() CTA:Answer(ln.id) end)
        lines[i] = ln
        return ln
    end
    screen.add(recent, 1, 2, function(w)
        local now, y = GetServerTime(), TOP - 4
        local inner = w - 2 * PAD
        for i, e in ipairs(CTA.recent) do
            local ln = lineAt(i)
            ln.id = e.id
            -- Anybody who has not answered can, from here too: with popups off, in quiet mode
            -- or after dismissing one, this is the only place to.
            local live = now - (tonumber(e.ts) or 0) <= CTA.MAX_AGE
            local open = not e.mine and not e.answered and live
            ln.go:SetShown(open)
            ln.rule:SetShown(i > 1)
            ln.sq:Set("!", live and SQUARE_OPEN or SQUARE_PAST)
            local tw = inner - 38 - (open and (ln.go:GetWidth() + 10) or 0)
            ln.text:SetWidth(tw)
            ln.meta:SetWidth(tw)
            local title = e.title or ""
            ln.text:SetText((e.text and e.text ~= "") and (title .. ": " .. e.text) or title)
            local n = CTA:GoingCount(e)
            local who = (Ambiguate and Ambiguate(e.sender or "", "short")) or (e.sender or "")
            ln.meta:SetText(string.format("%s \194\183 %s \194\183 %s", e.zone or "", who,
                n > 0 and string.format(L["%d on the way"], n) or date("%H:%M", e.at or 0)))
            local h = math.max(44, 6 + (ln.text:GetStringHeight() or 16) + 3 + (ln.meta:GetStringHeight() or 14) + 8)
            ln:ClearAllPoints()
            ln:SetPoint("TOPLEFT", PAD, -y)
            ln:SetSize(inner, h)
            ln:Show()
            y = y + h
        end
        for i = #CTA.recent + 1, #lines do lines[i]:Hide() end
        empty:SetShown(#CTA.recent == 0)
        if #CTA.recent == 0 then y = y + 24 end
        return y + PAD - 4
    end)

    -- Everyone: how a call reaches me, then the types to hear (the mockup's dark "Meus avisos").
    local mine = UI:CreateCard(content, L["My alerts"], { dark = true })
    local function checkCol(anchor, items, dy)
        local boxes = {}
        local prev = anchor
        for i, it in ipairs(items) do
            local cb = UI:CreateCheckbox(mine, it[1], 16)
            cb:SetWidth(30 + (cb.label:GetStringWidth() or 100))
            if i == 1 and dy then
                cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -dy)
            elseif i == 1 then
                cb:SetPoint("TOPLEFT", PAD, -TOP)
            else
                cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -5)
            end
            cb.checkbox:SetChecked(it[2]())
            local set = it[3]
            cb.checkbox.onChanged = function(_, checked) set(checked and true or false) end
            boxes[#boxes + 1] = cb
            prev = cb
        end
        return prev, boxes
    end
    local function setting(key) return function(v) GuildOS:SetSetting(key, v) end end
    local lastHow, how = checkCol(nil, {
        { L["Show popups"], function() return CTA:PopupsOn() end, setting("ctaPopups") },
        { L["Play a sound"], function() return CTA:SoundOn() end, setting("ctaSound") },
        { L["Quiet in instances and combat"], function() return CTA:QuietOn() end, setting("ctaQuiet") },
    })
    local hearHead = text(mine, 12, C.gold2, "sectionTitle")
    hearHead:SetText(L["Calls I hear"])
    hearHead:SetPoint("TOPLEFT", lastHow, "BOTTOMLEFT", 0, -14)
    local kinds = {}
    for _, k in ipairs(CTA.KINDS) do
        local id = k.id
        kinds[#kinds + 1] = { k.title, function() return not CTA:Muted(id) end,
                              function(v) GuildOS:SetSetting("ctaMute_" .. id, not v) end }
    end
    local _, hear = checkCol(hearHead, kinds, 8)
    screen.add(mine, 2, 1, function()
        return TOP + #how * 21 + 14 + 16 + 8 + #hear * 21 + PAD - 4
    end)

    local function refresh()
        screen.layout()
    end
    -- Answers arrive by the dozen while the tab is closed; it catches up when it opens.
    CTA.uiRefresh = function() if panel:IsVisible() then refresh() end end
    return refresh
end

----------------------------------------------------------------------
-- CHAT sub-panel: the guild's chat in a dark card on the left (the mockup's .chat), the mentions on the right.
----------------------------------------------------------------------
local BuildChatSub   -- defined after the feed, below

----------------------------------------------------------------------
-- Guild chat feed (issues #124, #126), kept by Modules/GuildChat.lua. Laid out
-- like the alliance feed: one card per run of lines from one speaker, newest at
-- the bottom, a box underneath, and a tab per channel of the guild. Guild > Chat
-- and the Now cards both build it.
----------------------------------------------------------------------
local AVATAR = 22   -- the mockup's small avatar (.av.s)
local feeds = 0   -- each feed's scroll frame needs its own global name

-- A channel is { id, name, kind }; nil, and the Guild tab, mean /g.
local function idOf(stream)
    return (stream and stream.kind ~= "guild") and stream.id or nil
end

local function streamLabel(stream)
    if stream.kind == "guild" then return L["Guild"] end
    if stream.kind == "officer" then return L["Officers"] end
    return stream.name or "?"
end

-- `top`: room over the feed. The Guild tab leaves GAP under its sub-tab bar, as on every sub-tab
-- (#371); a Now card gives none.
function GuildOS:CreateGuildChatFeed(panel, top)
    local GC = GuildOS.GuildChat
    local current   -- the channel open; nil is /g
    top = top or 0
    feeds = feeds + 1

    -- The channel tabs, shown only when there is more than /g to choose from.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, -top)
    bar:SetPoint("TOPRIGHT", 0, -top)   -- as wide as the feed: its anchors size it, never a width read too early
    bar:SetHeight(24)
    bar:Hide()
    local tabs = {}

    local holder = CreateFrame("Frame", nil, panel)
    local function anchorHolder(belowTabs)
        holder:ClearAllPoints()
        if belowTabs then
            holder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
        else
            holder:SetPoint("TOPLEFT", 0, -top)
        end
        holder:SetPoint("BOTTOMRIGHT", 0, FIELD_H + 10)
    end
    anchorHolder(false)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSGuildChatScroll" .. feeds)
    scroll:SetAllPoints()
    UI:BindScrollChildWidth(scroll, content, 12)   -- the lines follow the feed's width as the window resizes

    local input = UI:CreateInput(panel, 100, FIELD_H, { placeholder = L["Write to the guild"] })
    input:SetPoint("BOTTOMLEFT", 0, 0)
    input:SetPoint("BOTTOMRIGHT", -78, 0)
    input:SetMaxBytes(241)   -- what Send keeps (240 bytes), plus the terminator
    local sendBtn = UI:SetButtonVariant(UI:CreateButton(panel, L["Send"], 70, FIELD_H), "primary")
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 0)

    local empty = UI:CreateText(content, L["No guild chat yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local refresh   -- declared for the tab clicks
    -- The newest line is shown on opening and on changing channel; after that the feed follows
    -- new lines only for a reader already at the bottom, never pulling one who scrolled up.
    local pinBottom = true
    local scrolling = false   -- a move to the bottom is queued for the next frame
    local waiting = false     -- a look after a chat lockdown is queued

    -- Another channel: the server stops being told about the old one, and is told about this one.
    local function open(stream)
        -- In a chat lockdown the feed cannot be redrawn: a channel changed then would send Enter
        -- somewhere other than what is on screen, an officer's line to the whole guild.
        if GC:Locked() or idOf(stream) == idOf(current) then return end
        GC:Watch(false, current)
        current = idOf(stream) and stream or nil
        GC:Watch(true, current)
        pinBottom = true
        refresh()
    end

    local function layoutTabs()
        local streams = GC:Streams()
        local list = (streams and #streams > 1) and streams or nil
        -- The channel open is gone (removed, or no longer listed to this player): back to /g.
        if current then
            local still
            for _, s in ipairs(list or {}) do
                if s.id == current.id then still = s end
            end
            if not still then
                -- Hidden, the feed already stopped watching it.
                local watched = panel:IsVisible()
                if watched then GC:Watch(false, current) end
                current = nil
                if watched then GC:Watch(true, nil) end
            end
        end
        bar:SetShown(list ~= nil)
        anchorHolder(list ~= nil)
        if not list then return end
        local shown = {}
        for i, s in ipairs(list) do
            local t = tabs[i]
            if not t then
                -- The channels as the mockup's chips (Guild, Officers, the guild's own).
                t = UI:CreateTab(bar, "", 50, true)
                t:SetHeight(24)
                t:SetScript("OnClick", function(self) open(self.stream) end)
                tabs[i] = t
            end
            t.stream = s
            t.label:SetText(streamLabel(s))
            t:SetWidth(math.max(50, math.ceil(t.label:GetStringWidth()) + 24))
            t:SetActive(idOf(s) == idOf(current))
            t:Show()
            shown[#shown + 1] = t
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = 24 })
    end

    -- Pooled: refresh runs on every line of chat, and WoW never frees a frame.
    local blocks = {}
    local function getBlock(i)
        if blocks[i] then return blocks[i] end
        -- The mockup's .chat .ln: a small round class avatar, the name in the class's colour and the time beside
        -- it, the lines under it. No box: the dark card is the feed's.
        local card = CreateFrame("Frame", nil, content)
        -- A link in the line opens as it does in the chat frame.
        card:EnableMouse(true)
        card:SetHyperlinksEnabled(true)
        card:SetScript("OnHyperlinkClick", function(_, link, linkText, button) SetItemRef(link, linkText, button) end)
        local avatar = UI:CreateAvatar(card, AVATAR, false)
        avatar:SetPoint("TOPLEFT", 0, -2)
        avatar:EnableMouse(false)
        local nameFS = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        GuildOS:ApplyFont(nameFS, 13, "itemName")
        nameFS:SetPoint("TOPLEFT", AVATAR + 10, -1)
        local timeFS = UI:CreateText(card, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        timeFS:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)
        local bodyFS = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", AVATAR + 10, -19)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)
        blocks[i] = { card = card, avatar = avatar, nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS }
        return blocks[i]
    end

    refresh = function()
        -- In a chat lockdown the server's lines and channels arrive secret: keep what is drawn,
        -- and look again every 2 seconds while on screen, since no event says the lockdown lifted.
        if GC:Locked() then
            if not waiting then
                waiting = true
                GuildOS.Compat.After(2, function()
                    waiting = false
                    if panel:IsVisible() then refresh() end
                end)
            end
            return
        end
        local follow = pinBottom or scrolling or scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
        pinBottom = false
        layoutTabs()
        -- Born 0 wide (CreateScrollFrame sizes it before layout), so re-set on every draw.
        content:SetWidth(math.max(UI:LaidWidth(holder) - 12, 1))
        local log = GC:Entries(current)
        local classOf = {}
        for _, e in ipairs(log) do classOf[e.n] = e.c or classOf[e.n] end
        local groups = GuildOS.AllianceChat.GroupLog(log, GuildOS.AllianceChat.GROUP_WINDOW)
        local today = date("%Y%m%d", GetServerTime())
        local width = math.max(content:GetWidth() - 12, 200)
        local y = 0
        for i, g in ipairs(groups) do
            local b = getBlock(i)
            local class = classOf[g.name]
            b.avatar:SetMember(g.name, class)
            -- A line from an allied guild (issue #344) says which one, in its colour.
            local who = g.name or "?"
            if g.guild and GuildOS.Alliance then
                who = "|cff" .. GuildOS.Alliance.GuildColorHex(g.guild) .. "[" .. g.guild .. "]|r " .. who
            end
            b.nameFS:SetText(who)
            b.nameFS:SetTextColor(GuildOS:GetClassColor(class))
            -- The log outlives the session: a line from another day says which day.
            local t = tonumber(g.t)
            b.timeFS:SetText(t and GuildOS:LocalDate(date("%Y%m%d", t) == today and "%H:%M" or "%a %H:%M", t) or "")
            b.bodyFS:SetWidth(width - AVATAR - 10)
            b.bodyFS:SetText(table.concat(g.lines, "\n"))
            local h = math.max(AVATAR + 4, (b.bodyFS:GetStringHeight() or 12) + 21)
            b.card:SetPoint("TOPLEFT", 0, -y)
            b.card:SetSize(width, h)
            b.card:Show()
            y = y + h + 8
        end
        for i = #groups + 1, #blocks do blocks[i].card:Hide() end
        empty:SetShown(#groups == 0)
        if #groups == 0 then y = 20 end
        content:SetHeight(math.max(y, 1))
        -- A frame later: the scroll range follows the new height only after it lands.
        if not follow then return end
        local target = math.max(0, y - holder:GetHeight())
        scrolling = true
        GuildOS.Compat.After(0, function()
            scrolling = false
            if panel:IsVisible() then scroll:SetVerticalScroll(target) end
        end)
    end

    -- Enter and the click are the player's own key press, which chat needs on Forever.
    local function doSend()
        local ok, why = GC:Send(input:GetText(), current)
        if ok then
            input:SetText("")
        elseif why == "locked" then
            GuildOS:Print(L["Chat is locked right now: your message is still in the box."])
        end
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)

    GC:OnRefresh(function()
        if panel:IsVisible() then refresh() end
    end)
    -- The server is told a channel is being read only while the feed is on screen.
    panel:HookScript("OnShow", function() pinBottom = true; GC:Watch(true, current) end)
    panel:HookScript("OnHide", function() GC:Watch(false, current) end)
    -- The cards are as wide as the view: a resized window lays them out again, once a frame.
    UI:MakeResponsive(holder, function()
        if panel:IsVisible() then refresh() end
    end)
    return refresh
end

-- The Chat entry: the feed in a dark card as tall as the view (the mockup's "Chat da guilda"), and the mentions
-- this player was told about on the right (Modules/Mentions.lua's log, never shared).
local MAX_MENTIONS = 3
BuildChatSub = function(panel)
    local screen = cardScreen(panel, "GuildOSHubChatScroll")
    local content = screen.content
    local chat = UI:CreateCard(content, L["Guild chat"], { dark = true })
    local inner = CreateFrame("Frame", nil, chat)
    inner:SetPoint("TOPLEFT", PAD, -(TOP - 4))
    inner:SetPoint("BOTTOMRIGHT", -PAD, PAD - 2)
    local refreshFeed = GuildOS:CreateGuildChatFeed(inner, 0)
    screen.add(chat, 1, 1, function(w)
        local h = math.max(300, (panel:GetHeight() or 0) - 6)
        if (content:GetWidth() or 0) < TWO_COLUMNS then h = 380 end
        inner:SetSize(w - 2 * PAD, h - (TOP - 4) - (PAD - 2))
        return h
    end)

    local mentions = UI:CreateCard(content, L["Mentions"], { link = L["Adjust"] })
    mentions.link:SetScript("OnClick", function() UI:OpenWindow("settings", "chat") end)
    local intro = text(mentions, 12, mentions.soft, nil, true)
    intro:SetText(L["We tell you when somebody says your name or a word you chose. None of it is shared."])
    intro:SetPoint("TOPLEFT", PAD, -TOP)
    local empty = text(mentions, 12, mentions.soft)
    empty:SetText(L["Nobody has mentioned you yet."])
    local rows = {}
    screen.add(mentions, 2, 1, function(w)
        local inner2 = w - 2 * PAD
        intro:SetWidth(inner2)
        local y = TOP + (intro:GetStringHeight() or 28) + 12
        local log = GuildOS.db and GuildOS.db.mentions and GuildOS.db.mentions.log or {}
        local n = math.min(#log, MAX_MENTIONS)
        for i = 1, n do
            local e = log[i]
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, mentions)
                r.sq = square(r, 28)
                r.sq:SetPoint("TOPLEFT", 0, -4)
                r.sq:Set("@", hex("1d4f99"))
                r.main = text(r, 13, mentions.ink, nil, true)
                r.main:SetPoint("TOPLEFT", 40, -2)
                r.side = text(r, 11, mentions.soft)
                r.side:SetPoint("TOPLEFT", r.main, "BOTTOMLEFT", 0, -3)
                rows[i] = r
            end
            local who = (Ambiguate and Ambiguate(e.sender or "?", "short")) or (e.sender or "?")
            r.main:SetWidth(inner2 - 40)
            r.main:SetText(string.format("%s: \"%s\"", GuildOS:SanitizeUserText(who), GuildOS:SanitizeUserText(e.msg or "")))
            r.side:SetText(GuildOS:TimeAgo(e.ts or 0))
            local h = math.max(36, (r.main:GetStringHeight() or 14) + 20)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -y)
            r:SetSize(inner2, h)
            r:Show()
            y = y + h + 6
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", PAD, -y)
        empty:SetShown(n == 0)
        if n == 0 then y = y + 20 end
        return y + PAD - 4
    end)

    return function()
        screen.layout()
        refreshFeed()
    end
end

----------------------------------------------------------------------
-- Guild Hub assembly (sub-tab bar mirrors the Audit panel)
----------------------------------------------------------------------
-- `feature`: offered only while that feature may open here (UI:IsFeatureAllowed: present on this
-- client, switched on, started), and built the first time it opens. The Journal and Achievements
-- tabs became the last two (issue #367); both are WoW: Forever's. Achievements leads the bar and is
-- where Guild opens wherever it is offered (#373); elsewhere Guild opens on Calendar.
local HUB_SUBTABS = {
    { key = "achievements", label = L["Achievements"], feature = "achievements" },
    { key = "calendar", label = L["Calendar"] },
    { key = "activity", label = L["Activity"] },
    { key = "bulletin", label = L["Bulletin"] },
    { key = "rules",    label = L["Rules"] },
    { key = "cta",      label = L["Call to Arms"] },
    { key = "chat",     label = L["Chat"] },
    { key = "journal",      label = L["Journal"],      feature = "journal" },
}

-- `failed`: this hub's lazy sub-tabs whose builder errored (issue #367), refused for the session.
local function hubOffers(key, failed)
    if failed and failed[key] then return false end
    for _, t in ipairs(HUB_SUBTABS) do
        if t.key == key then return not t.feature or UI:IsFeatureAllowed(UI:GetFeature(t.feature)) end
    end
    return false
end

-- Where Guild opens: Achievements where this client has it and it started, else Calendar (#373).
local function hubDefault(failed)
    return hubOffers("achievements", failed) and "achievements" or "calendar"
end

function GuildOS:CreateGuildHub(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = hubDefault()

    -- Anchored on the left only: UI:FlowBar reads GetWidth to wrap, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized (as ManagementPanel).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    local builders = {
        calendar = function(p) return GuildOS:CreateCalendarSub(p) end,
        activity = BuildActivitySub, bulletin = BuildBulletinSub, cta = BuildCallToArmsSub,
        rules = BuildGuildRulesSub,
        chat = function(p) return BuildChatSub(p) end,
        journal = function(p) return GuildOS:CreateJournalPanel(p) end,
        achievements = function(p) return GuildOS:CreateAchievementsPanel(p) end,
    }
    local failed = {}
    -- The six built with the tab raise as they did, into the tab's own start-up guard. Journal and
    -- Achievements are built the first time they open: one that errors is recorded, with its stack, and
    -- refused for the session rather than left half built (issue #367).
    local function build(key)
        local info = parent.subPanels[key]
        if not info or info.built then return end
        info.built = true
        local def
        for _, t in ipairs(HUB_SUBTABS) do if t.key == key then def = t end end
        if not (def and def.feature) then
            info.refresh = builders[key](info.panel)
            return
        end
        local ok, res = xpcall(function() return builders[key](info.panel) end, function(e)
            return tostring(e) .. (debugstack and ("\n" .. debugstack(2)) or "")
        end)
        if ok then
            info.refresh = res
        else
            failed[key] = true
            GuildOS:RecordError("Guild hub " .. key .. ": " .. tostring(res))
            GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
        end
    end

    local subTabBtns = {}
    -- A sub-tab not offered (switched off, or not on this client) falls back to the calendar, deep
    -- links included.
    local function selectSub(key, filter)
        if not hubOffers(key, failed) then key = hubDefault(failed) end
        build(key)
        if failed[key] then key = hubDefault(failed); build(key) end   -- its builder just errored
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
        -- A deep link's filter goes to the sub-panel that takes one (the calendar: a day).
        if filter ~= nil and info and info.panel.ApplyFilter then GuildOS:SafeCall(info.panel.ApplyFilter, filter) end
    end
    parent.SelectSub = selectSub   -- deep links: /guildos calendar, /gos open journal, the Now tab

    -- A tab is as wide as its label: five at a fixed 120px ran off a narrow window (issue #108).
    for _, t in ipairs(HUB_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
    end

    -- Flow the offered tabs only, so a sub-tab switched off leaves no gap in the bar (as the
    -- Alliance panel).
    local function layoutTabs()
        local shown = {}
        for _, t in ipairs(HUB_SUBTABS) do
            local btn = subTabBtns[t.key]
            local offered = hubOffers(t.key, failed)
            btn:SetShown(offered)
            if offered then shown[#shown + 1] = btn end
        end
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end
    layoutTabs()

    -- Hung from the bar, so a bar wrapped onto two rows pushes the content down. Flush with the bar on
    -- both sides and right under it: each sub-tab starts its content at x = 0, GAP down (#371), so
    -- every one of them starts at the same place.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", -10, 10)
        p:Hide()
        return p
    end

    for _, t in ipairs(HUB_SUBTABS) do
        parent.subPanels[t.key] = { panel = makeSubPanel() }
        if not t.feature then build(t.key) end
    end

    -- A room that opens one of these sub-tabs as its own entry (the Salão's Notices, Raids' Calendar,
    -- specs/salao #445) hides this bar, so the screen never shows two rows of the same tabs: the
    -- sub-panels then start where the bar was.
    for key, info in pairs(parent.subPanels) do
        info.panel:HookScript("OnShow", function() if parent.OnSubChanged then parent.OnSubChanged(key) end end)
    end
    local barShown = true
    function parent.SetSubBarShown(shown)
        shown = shown and true or false
        if shown == barShown then return end
        barShown = shown
        bar:SetShown(shown)
        for _, info in pairs(parent.subPanels) do
            info.panel:ClearAllPoints()
            if shown then
                info.panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
            else
                info.panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -8)
            end
            info.panel:SetPoint("BOTTOMRIGHT", -10, 10)
        end
    end

    parent:SetScript("OnShow", function()
        layoutTabs()
        selectSub(parent.activeSub or hubDefault(failed))
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs()
    end)
end

