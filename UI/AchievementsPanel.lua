----------------------------------------------------------------------
-- Guild OS - The Achievements tab (issue #216, guildos.me #245)
-- The guild's renown, what is nearest to done, and what it earned. Modules/Achievements.lua answers;
-- this draws. WoW: Forever only: the Guild tab's Achievements sub-tab since issue #367, offered only
-- where the feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
--
-- "Insignia and collection" (#373): the insignia and the renown head the screen, with the points beside
-- the renown; what is nearest to done is a row of boxes; and what was earned reads as a collection:
-- a numbered series with its row of tier pills (with the tier being worked on shown dim after them),
-- "Prefix: part" titles under their prefix, the rest a row each. Drawn in cards as the Chronicle's
-- mockup (#449 phase 3).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

-- GAP and the gutter are the shared grid's (#371); a test's stand-in UI carries neither.
local GAP = type(UI.GAP) == "number" and UI.GAP or 8
local GUTTER = type(UI.SCROLL_GUTTER) == "number" and UI.SCROLL_GUTTER or 12
local COL_W = 80           -- the right-hand column: a date

local INSIGNIA = 64        -- the renown insignia, the screen's one picture (#373)
local INSIGNIA_GAP = 12

local CARD_MIN = 200       -- a nearest card is never narrower; the row takes as many as fit
local BOX_PAD = 12            -- a nearest box's padding (a box inside the card, not a card)
local TITLE_H = 30         -- two lines of 12px: every card keeps room for two, so the bars line up
local NUM_H = 13           -- a line of the mono number font
local BAR_H = 8
local CARD_H = BOX_PAD + TITLE_H + GAP + NUM_H + BOX_PAD

local PILL_H = 16          -- UI:CreateBadge's height
local PILL_GAP = 4

----------------------------------------------------------------------
-- The collection (#373), a pure function of what Achievements:Earned() and :Next() return, so the
-- harness (tools/achievements-layout.lua) can hold it to the real titles.
----------------------------------------------------------------------

-- Tiers in roman numerals. Series run short (I to III in the real data), so I, V and X are enough, and
-- a numeral written any way but the canonical one ("IIII", "VX") is a word, not a tier.
local NUMERALS = { { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local VALUE = { I = 1, V = 5, X = 10 }

local function roman(n)
    local out = {}
    for _, p in ipairs(NUMERALS) do
        while n >= p[1] do
            out[#out + 1] = p[2]
            n = n - p[1]
        end
    end
    return table.concat(out)
end

-- "Biblioteca Viva II" -> "Biblioteca Viva", 2; anything else -> nil.
local function tierOf(title)
    local name, numeral = tostring(title or ""):match("^(.-)%s+([IVX]+)%s*$")
    if not name or name == "" then return nil end
    local n, prev = 0, 0
    for i = #numeral, 1, -1 do
        local v = VALUE[numeral:sub(i, i)]
        if v < prev then n = n - v else n, prev = n + v, v end
    end
    if n < 1 or roman(n) ~= numeral then return nil end
    return name, n
end

-- What was earned, as rows, the most recently added to first:
--   { kind = "series", name, tiers = { { n, label, entry } ... } ascending, following = { n, label, entry } or nil, at }
--   { kind = "group",  name = prefix, parts = { ... } in the order they were earned, partEntries (alike), at }
--   { kind = "single", name = title, entry, at }
-- Each `entry` is the achievement as Earned()/Next() gave it, for its tooltip (#373).
-- `at` is the newest of the row's. `following` is the series' next tier when Next() holds it.
function GuildOS:AchievementCollection(earned, nearest)
    -- The tiers being worked on, by series.
    local working = {}
    for _, e in ipairs(nearest or {}) do
        local name, n = tierOf(e.title)
        if name then
            working[name] = working[name] or {}
            table.insert(working[name], { n = n, entry = e })
        end
    end

    local rows, byKey = {}, {}
    earned = earned or {}
    -- Oldest first, so a group's parts read in the order they were earned; `order` keeps the list's
    -- own place (newest first) to break a tie between rows of the same day.
    for i = #earned, 1, -1 do
        local e = earned[i]
        local title = tostring(e.title or "")
        local at = tonumber(e.at) or 0
        local name, n = tierOf(title)
        local prefix, part
        if not name then prefix, part = title:match("^(.-):%s+(.+)$") end
        if prefix == "" then prefix = nil end
        local key = (name and "series:" .. name) or (prefix and "group:" .. prefix) or nil
        local row = key and byKey[key]
        if not row then
            row = { at = at, order = i }
            if name then
                row.kind, row.name, row.tiers, row.has = "series", name, {}, {}
            elseif prefix then
                row.kind, row.name, row.parts, row.partEntries, row.has = "group", prefix, {}, {}, {}
            else
                row.kind, row.name, row.entry = "single", title, e
            end
            rows[#rows + 1] = row
            if key then byKey[key] = row end
        end
        row.at = math.max(row.at, at)
        row.order = math.min(row.order, i)
        if row.kind == "series" and not row.has[n] then
            row.has[n] = true
            row.tiers[#row.tiers + 1] = { n = n, label = roman(n), entry = e }
        elseif row.kind == "group" and not row.has[part] then
            row.has[part] = true
            row.parts[#row.parts + 1] = part
            row.partEntries[#row.partEntries + 1] = e
        end
    end

    for _, row in ipairs(rows) do
        if row.kind == "series" then
            table.sort(row.tiers, function(a, b) return a.n < b.n end)
            local top = row.tiers[#row.tiers].n
            -- The tier that comes next: the lowest one past what was earned that Next() is counting.
            for _, w in ipairs(working[row.name] or {}) do
                if w.n > top and (not row.following or w.n < row.following.n) then
                    row.following = { n = w.n, label = roman(w.n), entry = w.entry }
                end
            end
        end
        row.has = nil
    end
    table.sort(rows, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.order < b.order
    end)
    return rows
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

-- A member's name in their class colour, from the roster this client keeps; the key's name otherwise.
local function memberName(key)
    local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    local name = (type(m) == "table" and m.name) or tostring(key):match("^([^-]+)") or tostring(key)
    local cls = type(m) == "table" and m.class
    if cls then
        local r, g, b = GuildOS:GetClassColor(cls)
        if r then return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name) end
    end
    return name
end

-- An achievement in the game's tooltip (#373, as approved): its title, what it asks when the site sends
-- that, then when and by whom it was earned, or how far along it is.
local function showTip(owner, e)
    if not (GameTooltip and type(e) == "table") then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.title or "", C.text.r, C.text.g, C.text.b)
    if type(e.rule) == "string" and e.rule ~= "" then
        GameTooltip:AddLine(e.rule, C.textSoft.r, C.textSoft.g, C.textSoft.b, true)
    end
    local target = tonumber(e.target)
    if target and target > 0 then
        local current = math.floor(tonumber(e.current) or 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("%d / %d  (%d%%)", current, math.floor(target), math.floor(current / target * 100 + 0.5)),
            C.text.r, C.text.g, C.text.b)
    elseif (tonumber(e.at) or 0) > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Earned %s"], day(e.at)), C.label.r, C.label.g, C.label.b)
        if e.key then GameTooltip:AddLine(string.format(L["by %s"], memberName(e.key)), C.label.r, C.label.g, C.label.b) end
    end
    GameTooltip:Show()
end

-- A group's tooltip ("Desbravadores"): its name, then each part with the day it was earned.
local function showGroupTip(owner, row)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.name or "", C.text.r, C.text.g, C.text.b)
    for i, part in ipairs(row.parts or {}) do
        local e = row.partEntries and row.partEntries[i]
        local at = e and tonumber(e.at) or 0
        GameTooltip:AddDoubleLine(part, at > 0 and day(at) or "", C.textSoft.r, C.textSoft.g, C.textSoft.b,
            C.label.r, C.label.g, C.label.b)
    end
    GameTooltip:Show()
end

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

-- Frames made as the screen needs them and kept: a redraw takes them again instead of making more.
local function newPool(make)
    local pool = { items = {}, used = 0 }
    function pool:Take()
        self.used = self.used + 1
        local item = self.items[self.used]
        if not item then
            item = make()
            self.items[self.used] = item
        end
        item:ClearAllPoints()
        item:Show()
        return item
    end
    function pool:Reset()
        for _, item in ipairs(self.items) do item:Hide() end
        self.used = 0
    end
    return pool
end

-- The Chronicle's mockup (#449 phase 3): the renown in a dark card (the insignia, or a gold medal with the
-- renown's number, the title in the soft gold and "Renown N · P points" under it); Nearest in a parchment card
-- of small paper boxes (the title in the title face, the bar and how far along); Earned in a parchment card,
-- each row its name in the title face with its date on the right and, under it, the series' tier pills or the
-- group's parts.
local HEAD_H = INSIGNIA + 2 * 16
local CARD_TOP = UI.SP.TOP        -- a card's first line, under its title
local PAD = UI.SP.PAD      -- a card's padding (UI.CARD_PAD)
local NAME_H = 16          -- a row's name line

function GuildOS:CreateAchievementsPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSAchievementsScroll")
    scroll:SetPoint("TOPLEFT", 0, -GAP)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- The content keeps the list's width, less the scroll bar's gutter: every card hangs from both of
    -- its top corners, never from a width read while the tab was hidden.
    UI:BindScrollChildWidth(scroll, content)

    -- The width to lay the cards and the pills out in, read on every draw (on show and on every resize,
    -- #373). A tab built hidden reads 0: then the boxes stack, hung by both sides, until it is shown.
    local function width()
        local w = UI:LaidWidth(scroll)
        return (type(w) == "number" and w > GUTTER + 1) and (w - GUTTER) or 0
    end

    -- The three cards, hung by both top corners from the content.
    local head = UI:CreateCard(content, "", { dark = true })
    local near = UI:CreateCard(content, L["Nearest"])
    local earnedCard = UI:CreateCard(content, L["Earned"])
    local function place(card, top, h)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -top)
        card:SetPoint("TOPRIGHT", 0, -top)
        card:SetHeight(h)
        card:Show()
        return top + h + GAP + 4
    end

    -- The header: the insignia, or the medal with the renown's number; the title beside it, the renown under.
    local insignia = head:CreateTexture(nil, "ARTWORK")
    insignia:SetSize(INSIGNIA, INSIGNIA)
    insignia:Hide()
    local medal = UI:CreateGlyph(head, INSIGNIA)
    GuildOS:ApplyFont(medal.letter, 22, "metricValue")
    medal.letter:SetTextColor(0.29, 0.15, 0.03)
    medal:Hide()
    local nameFS = UI:CreateTitle(head, "", 18)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b)
    local renownFS = UI:CreateText(head, "", 13, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    renownFS:SetJustifyH("LEFT")

    local texts = newPool(function() return UI:CreateText(earnedCard, "", 12) end)
    local names = newPool(function()
        local fs = UI:CreateText(earnedCard, "", 12)
        GuildOS:ApplyFont(fs, 12, "sectionTitle")
        return fs
    end)
    local numbers = newPool(function()
        local fs = UI:CreateText(earnedCard, "", 11)
        GuildOS:ApplyFont(fs, nil, "tableNum")
        return fs
    end)
    -- A pill shows its tier's tooltip; above the row's own hover area, so the pill wins under the cursor.
    local pills = newPool(function()
        local p = UI:CreateBadge(earnedCard, "")
        p:SetFrameLevel((earnedCard:GetFrameLevel() or 1) + 2)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) showTip(self, self.entry) end)
        p:SetScript("OnLeave", hideTip)
        return p
    end)
    -- A row's hover area, under its text and pills: the row's tooltip anywhere else on it.
    local hits = newPool(function()
        local f = CreateFrame("Frame", nil, earnedCard)
        f:SetFrameLevel((earnedCard:GetFrameLevel() or 1) + 1)
        f:EnableMouse(true)
        f:SetScript("OnLeave", hideTip)
        return f
    end)
    -- A nearest box (the mockup's paper box in "Mais perto"): its title in the title face (two lines at most),
    -- the bar and how far along.
    local cards = newPool(function()
        local card = CreateFrame("Frame", nil, near)
        card:SetFrameLevel((near:GetFrameLevel() or 1) + 1)   -- before its children, so they sit on it
        local fill = GuildOS.Style:Nine(card, "card", 5, "BACKGROUND", 1)
        fill:SetRGBA(0.937, 0.878, 0.741, 1)
        local edge = GuildOS.Style:Nine(card, "card-line", 5, "BORDER", 0)
        edge:SetColor(C.paperRule)
        card.title = UI:CreateText(card, "", 12, C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
        GuildOS:ApplyFont(card.title, 12, "sectionTitle")
        card.title:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
        card.title:SetPoint("TOPRIGHT", -BOX_PAD, -BOX_PAD)
        card.title:SetJustifyH("LEFT")
        card.title:SetJustifyV("TOP")
        card.title:SetWordWrap(true)
        if card.title.SetMaxLines then card.title:SetMaxLines(2) end
        card.count = UI:CreateText(card, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(card.count, nil, "tableNum")
        card.count:SetPoint("BOTTOMRIGHT", -BOX_PAD, BOX_PAD)
        card.count:SetJustifyH("RIGHT")
        card.bar = UI:CreateProgressBar(card, CARD_MIN, BAR_H)
        card:EnableMouse(true)
        card:SetScript("OnEnter", function(self) showTip(self, self.entry) end)
        card:SetScript("OnLeave", hideTip)
        return card
    end)
    -- What the harness reads back: the cards and the earned rows as drawn.
    content.cards, content.rows = {}, {}
    content.head, content.near, content.earned = head, near, earnedCard
    -- No achievements yet: a centred block on the screen (#449), never a grey line in its corner.
    local empty = UI.CreateEmptyState and UI:CreateEmptyState(parent, UI.Initial and UI.Initial(L["Achievements"]) or "A") or UI:CreateText(content, "", UI.SP.BODY)
    empty:SetPoint("CENTER", parent, "CENTER", 0, 20)
    empty:Hide()

    local function take(pool, col)
        local fs = pool:Take()
        fs:SetTextColor(col.r, col.g, col.b)
        fs:SetWidth(0)
        fs:SetJustifyH("LEFT")
        return fs
    end

    local function header(A, level, points)
        local tex, title = A:Insignia()
        local guild = GetGuildInfo and GetGuildInfo("player")
        local renown = string.format(L["Renown %d"], level)
        -- The heading is the insignia's title, else the guild's name; with neither, the renown alone.
        local name = title or guild
        local x = PAD + INSIGNIA + INSIGNIA_GAP
        insignia:ClearAllPoints()
        insignia:SetPoint("TOPLEFT", PAD, -16)
        medal:ClearAllPoints()
        medal:SetPoint("TOPLEFT", PAD, -16)
        if tex then
            insignia:SetTexture(tex)
            insignia:Show()
            medal:Hide()
        else
            medal:Set(tostring(level), C.metal2)
            medal:Show()
        end
        GuildOS:SetTitleText(nameFS, name or renown)
        renownFS:SetText((name and (renown .. " \194\183 ") or "") .. string.format(L["%d points"], points or 0))
        local avail = width() - x - PAD
        if avail > 1 then nameFS:SetWidth(avail) end
        local nameH = nameFS:GetStringHeight() or 20
        local textH = nameH + 4 + (renownFS:GetStringHeight() or 14)
        local textTop = 16 + math.max(0, math.floor((INSIGNIA - textH) / 2))
        nameFS:ClearAllPoints()
        nameFS:SetPoint("TOPLEFT", x, -textTop)
        nameFS:SetPoint("TOPRIGHT", -PAD, -textTop)
        nameFS:Show()
        renownFS:ClearAllPoints()
        renownFS:SetPoint("TOPLEFT", x, -(textTop + nameH + 4))
        renownFS:SetPoint("TOPRIGHT", -PAD, -(textTop + nameH + 4))
        renownFS:Show()
        return math.max(HEAD_H, textTop + textH + 16)
    end

    -- The nearest boxes (#373): side by side as many as fit at CARD_MIN, wrapping onto more rows.
    local function nearestCards(nearest)
        local W = width()
        local inner = W > 0 and (W - 2 * PAD) or 0
        local cols = inner > 0 and math.max(1, math.floor((inner + GAP) / (CARD_MIN + GAP))) or 1
        local cardW = inner > 0 and math.floor((inner - GAP * (cols - 1)) / cols) or nil
        local rows = 0
        for i, n in ipairs(nearest) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            rows = row + 1
            local top = CARD_TOP + row * (CARD_H + GAP)
            local card = cards:Take()
            if cardW then
                card:SetPoint("TOPLEFT", PAD + col * (cardW + GAP), -top)
                card:SetWidth(cardW)
            else
                card:SetPoint("TOPLEFT", PAD, -top)
                card:SetPoint("TOPRIGHT", -PAD, -top)
            end
            card:SetHeight(CARD_H)
            card.entry = n
            card.title:SetText(n.title)

            local current, target = tonumber(n.current) or 0, tonumber(n.target) or 0
            card.count:SetText(string.format("%d / %d", math.floor(current), math.floor(target)))
            local countW = card.count:GetStringWidth() or 0
            local bar = card.bar
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", BOX_PAD, BOX_PAD + math.floor((NUM_H - BAR_H) / 2))
            if cardW then
                -- A set width, so the fill is measured against the bar as drawn.
                bar:SetWidth(math.max(1, cardW - 2 * BOX_PAD - countW - GAP))
            else
                bar:SetPoint("RIGHT", card.count, "LEFT", -GAP, 0)
            end
            bar:SetProgress(target > 0 and current / target or 0)
            content.cards[#content.cards + 1] = card
        end
        return CARD_TOP + rows * CARD_H + math.max(0, rows - 1) * GAP + PAD
    end

    -- One earned row: its name in the title face with the date on the right, and under it the series' tier
    -- pills or the group's parts; a single is its name alone.
    local function earnedRow(r, W, y)
        local drawn = { row = r, pills = {} }
        local inner = W > 0 and (W - 2 * PAD) or 0
        local dateFS = take(numbers, C.paperSoft)
        dateFS:SetPoint("TOPRIGHT", -PAD, -y)
        dateFS:SetWidth(COL_W)
        dateFS:SetJustifyH("RIGHT")
        dateFS:SetText(r.at > 0 and day(r.at) or "")
        drawn.date = dateFS

        local title = take(names, C.paperTitle)
        GuildOS:SetTitleText(title, r.name)
        title:SetPoint("TOPLEFT", PAD, -y)
        title:SetPoint("TOPRIGHT", -(PAD + COL_W + GAP), -y)
        drawn.name = title
        local h = math.max(NAME_H, title:GetStringHeight() or 14)
        if r.kind == "group" then
            local parts = take(texts, C.paperInk)
            parts:SetPoint("TOPLEFT", PAD, -(y + h + 4))
            parts:SetPoint("TOPRIGHT", -PAD, -(y + h + 4))
            parts:SetText(table.concat(r.parts, " \194\183 "))
            drawn.parts = parts
            h = h + 4 + (parts:GetStringHeight() or 14)
        elseif r.kind == "series" then
            -- Earned tiers as the gold-brown pills (the mockup's .tier); the one being worked on dim after
            -- them, so the collection shows what comes next.
            local tiers = {}
            for _, t in ipairs(r.tiers) do tiers[#tiers + 1] = { label = t.label, earned = true, entry = t.entry } end
            if r.following then
                tiers[#tiers + 1] = { label = r.following.label, earned = false, entry = r.following.entry }
            end
            local avail = inner > 0 and inner or math.huge
            local px, py = PAD, h + 5
            for _, t in ipairs(tiers) do
                local pill = pills:Take()
                pill:SetText(t.label, t.earned and C.text or C.label)
                local pw = pill:GetWidth() or PILL_H
                if px > PAD and px + pw > PAD + avail then px, py = PAD, py + PILL_H + PILL_GAP end
                pill:SetPoint("TOPLEFT", px, -(y + py))
                pill.earned = t.earned
                pill.entry = t.entry
                drawn.pills[#drawn.pills + 1] = pill
                px = px + pw + PILL_GAP
            end
            h = py + PILL_H
        end
        -- The row's tooltip: a single's own, a series' newest tier, or a group's parts with their days.
        local hit = hits:Take()
        hit:SetPoint("TOPLEFT", PAD, -y)
        hit:SetPoint("TOPRIGHT", -PAD, -y)
        hit:SetHeight(math.max(h, 14))
        hit:SetScript("OnEnter", function(self)
            if r.kind == "group" then showGroupTip(self, r)
            else showTip(self, r.kind == "single" and r.entry or (r.tiers[#r.tiers] or {}).entry) end
        end)
        drawn.hit = hit
        content.rows[#content.rows + 1] = drawn
        return y + math.max(h, 14) + 12
    end

    local function refresh()
        local A = GuildOS.Achievements
        if not A then return end
        texts:Reset()
        names:Reset()
        numbers:Reset()
        pills:Reset()
        hits:Reset()
        cards:Reset()
        insignia:Hide()
        medal:Hide()
        head:Hide()
        near:Hide()
        earnedCard:Hide()
        empty:Hide()
        content.cards, content.rows = {}, {}

        local level, points = A:Renown()
        if not level then
            local line = L["Achievements come from guildos.me: the web companion brings them here when your guild has them."]
            if empty.Set then empty:Set(line) else empty:SetText(line) end
            empty:Show()
            content:SetHeight(1)
            return
        end
        local y = place(head, 2, header(A, level, points))

        local nearest = A:Next()
        if #nearest > 0 then y = place(near, y, nearestCards(nearest)) end

        local earned = A:Earned()
        local W = width()
        local ey = CARD_TOP
        if #earned == 0 then
            local fs = take(texts, C.paperSoft)
            fs:SetPoint("TOPLEFT", PAD, -ey)
            fs:SetText(L["Nothing earned yet."])
            ey = ey + 20
        end
        for _, r in ipairs(GuildOS:AchievementCollection(earned, nearest)) do ey = earnedRow(r, W, ey) end
        y = place(earnedCard, y, ey + PAD - 8)
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
