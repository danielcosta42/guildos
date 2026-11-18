----------------------------------------------------------------------
-- Guild OS - The Achievements tab (issue #216, guildos.me #245)
-- The guild's renown, what is nearest to done, and what it earned. Modules/Achievements.lua answers;
-- this draws. WoW: Forever only: the Guild tab's Achievements sub-tab since issue #367, offered only
-- where the feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
--
-- "Insignia and collection" (#373): the insignia and the renown head the screen, with the points as
-- its metric; what is nearest to done is a row of cards; and what was earned reads as a collection:
-- a numbered series on one row of tier pills (with the tier being worked on shown dim after them),
-- "Prefix: part" titles under their prefix, the rest a row each.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

-- GAP and the gutter are the shared grid's (#371); a test's stand-in UI carries neither.
local GAP = type(UI.GAP) == "number" and UI.GAP or 8
local GUTTER = type(UI.SCROLL_GUTTER) == "number" and UI.SCROLL_GUTTER or 12
local SECTION_SPACE = 20   -- over a later section title: its rule sits 12px above it
local ROW_GAP = 6
local COL_W = 80           -- the right-hand column: a date

local INSIGNIA = 64        -- the renown insignia, the screen's one picture (#373)
local INSIGNIA_GAP = 12
local CHIP_MIN = 34        -- as UI:CreateMetricChip sizes it: never narrower than this

local CARD_MIN = 200       -- a nearest card is never narrower; the row takes as many as fit
local CARD_PAD = 10
local TITLE_H = 30         -- two lines of 12px: every card keeps room for two, so the bars line up
local NUM_H = 13           -- a line of the mono number font
local BAR_H = 8
local CARD_H = CARD_PAD + TITLE_H + GAP + NUM_H + CARD_PAD

local NAME_W = 200         -- a series' or a group's name, so their pills and parts start in one column
local NAME_SHARE = 0.4     -- at most this much of a narrow screen
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

function GuildOS:CreateAchievementsPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSAchievementsScroll")
    scroll:SetPoint("TOPLEFT", 0, -GAP)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- The content keeps the list's width, less the scroll bar's gutter: every line hangs from both of
    -- its top corners, never from a width read while the tab was hidden.
    UI:BindScrollChildWidth(scroll, content)

    -- The width to lay the cards and the pills out in, read on every draw (on show and on every resize,
    -- #373). A tab built hidden reads 0: then the cards stack, hung by both sides, until it is shown.
    local function width()
        local w = scroll:GetWidth()
        return (type(w) == "number" and w > GUTTER + 1) and (w - GUTTER) or 0
    end

    -- The header (#373): the insignia, its title (or the guild's name) with the renown under it, and
    -- the points as the screen's metric on the right.
    local insignia = content:CreateTexture(nil, "ARTWORK")
    insignia:SetSize(INSIGNIA, INSIGNIA)
    insignia:Hide()
    local nameFS = UI:CreateTitle(content, "", 18)
    nameFS:SetJustifyH("LEFT")
    local renownFS = UI:CreateText(content, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    renownFS:SetJustifyH("LEFT")
    local chip = UI:CreateMetricChip(content, "", L["points"])
    chip:Hide()
    -- The chip sizes itself to the value it was made with; the points change after that.
    local function fitChip()
        local v, l = chip.value, chip.label
        if type(v) ~= "table" or type(l) ~= "table" then return end   -- a test's stand-in UI
        chip:SetWidth(math.max(CHIP_MIN, v:GetStringWidth() or 0, l:GetStringWidth() or 0))
    end

    -- A later section in a frame of its own, so the title and the rule over it hide together.
    local function section(text)
        local box = CreateFrame("Frame", nil, content)
        box.title = UI:CreateSectionTitle(box, text)
        box.title:SetPoint("TOPLEFT", 0, 0)
        return box
    end
    local nearHead, earnedHead = section(L["NEAREST"]), section(L["EARNED"])

    local texts = newPool(function() return UI:CreateText(content, "", 12) end)
    local numbers = newPool(function()
        local fs = UI:CreateText(content, "", 11)
        GuildOS:ApplyFont(fs, nil, "tableNum")
        return fs
    end)
    -- A pill shows its tier's tooltip; above the row's own hover area, so the pill wins under the cursor.
    local pills = newPool(function()
        local p = UI:CreateBadge(content, "")
        p:SetFrameLevel((content:GetFrameLevel() or 1) + 2)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) showTip(self, self.entry) end)
        p:SetScript("OnLeave", hideTip)
        return p
    end)
    -- A row's hover area, under its text and pills: the row's tooltip anywhere else on it.
    local hits = newPool(function()
        local f = CreateFrame("Frame", nil, content)
        f:SetFrameLevel((content:GetFrameLevel() or 1) + 1)
        f:EnableMouse(true)
        f:SetScript("OnLeave", hideTip)
        return f
    end)
    -- A nearest card: a panel with the title (two lines at most), the bar, and how far along.
    local cards = newPool(function()
        local card = UI:CreatePanel(content)
        card:SetFrameLevel((content:GetFrameLevel() or 1) + 1)   -- before its children, so they sit on it
        card.title = UI:CreateText(card, "", 12)
        card.title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
        card.title:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_PAD)
        card.title:SetJustifyH("LEFT")
        card.title:SetJustifyV("TOP")
        card.title:SetWordWrap(true)
        if card.title.SetMaxLines then card.title:SetMaxLines(2) end
        card.count = UI:CreateText(card, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        GuildOS:ApplyFont(card.count, nil, "tableNum")
        card.count:SetPoint("BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
        card.count:SetJustifyH("RIGHT")
        card.bar = UI:CreateProgressBar(card, CARD_MIN, BAR_H)
        card:EnableMouse(true)
        card:SetScript("OnEnter", function(self) showTip(self, self.entry) end)
        card:SetScript("OnLeave", hideTip)
        return card
    end)
    -- What the harness reads back: the cards and the earned rows as drawn.
    content.cards, content.rows = {}, {}

    local y = 0

    local function take(pool, col)
        local fs = pool:Take()
        fs:SetTextColor(col.r, col.g, col.b)
        fs:SetWidth(0)
        fs:SetJustifyH("LEFT")
        return fs
    end

    local function heading(box)
        y = y + SECTION_SPACE
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 0, -y)
        box:SetPoint("TOPRIGHT", 0, -y)
        local h = box.title:GetStringHeight() or 14
        box:SetHeight(h)
        box:Show()
        y = y + h + GAP
    end

    -- A line across the content, wrapped.
    local function line(text, col)
        local fs = take(texts, col)
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetPoint("TOPRIGHT", 0, -y)
        fs:SetText(text)
        y = y + (fs:GetStringHeight() or 14) + ROW_GAP
    end

    local function header(A, level, points)
        local tex, title = A:Insignia()
        local guild = GetGuildInfo and GetGuildInfo("player")
        local renown = string.format(L["Renown %d"], level)
        -- The heading is the insignia's title, else the guild's name; with neither, the renown alone.
        local name = title or guild
        local top = y

        chip:SetValue(tostring(points or 0))
        fitChip()
        chip:ClearAllPoints()
        chip:SetPoint("TOPRIGHT", 0, -top)
        chip:Show()
        local chipW = chip:GetWidth() or CHIP_MIN

        local x = 0
        if tex then
            insignia:SetTexture(tex)
            insignia:ClearAllPoints()
            insignia:SetPoint("TOPLEFT", 0, -top)
            insignia:Show()
            x = INSIGNIA + INSIGNIA_GAP
        end
        nameFS:SetText(name or renown)
        renownFS:SetText(renown)
        renownFS:SetShown(name ~= nil)
        -- Its width before its height: GetStringHeight measures the wrap at the width the title has now,
        -- and anchors set below would not be resolved yet (#373).
        local right = -(chipW + 2 * GAP)
        local avail = width() - x + right
        if avail > 1 then nameFS:SetWidth(avail) end
        local nameH = nameFS:GetStringHeight() or 20
        local textH = nameH + (name and 4 + (renownFS:GetStringHeight() or 14) or 0)
        -- Beside the insignia the two lines sit in its middle; without one, at the top.
        local textTop = top + (tex and math.max(0, math.floor((INSIGNIA - textH) / 2)) or 0)
        nameFS:ClearAllPoints()
        nameFS:SetPoint("TOPLEFT", x, -textTop)
        nameFS:SetPoint("TOPRIGHT", right, -textTop)
        nameFS:Show()
        renownFS:ClearAllPoints()
        renownFS:SetPoint("TOPLEFT", x, -(textTop + nameH + 4))
        renownFS:SetPoint("TOPRIGHT", right, -(textTop + nameH + 4))

        local chipH = chip:GetHeight() or 0
        y = top + math.max(tex and INSIGNIA or 0, textTop - top + textH, chipH)
    end

    -- The nearest cards (#373): side by side as many as fit at CARD_MIN, wrapping onto more rows.
    local function nearestCards(nearest)
        local W = width()
        local cols = W > 0 and math.max(1, math.floor((W + GAP) / (CARD_MIN + GAP))) or 1
        local cardW = W > 0 and math.floor((W - GAP * (cols - 1)) / cols) or nil
        local rows = 0
        for i, n in ipairs(nearest) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            rows = row + 1
            local top = y + row * (CARD_H + GAP)
            local card = cards:Take()
            if cardW then
                card:SetPoint("TOPLEFT", col * (cardW + GAP), -top)
                card:SetWidth(cardW)
            else
                card:SetPoint("TOPLEFT", 0, -top)
                card:SetPoint("TOPRIGHT", 0, -top)
            end
            card:SetHeight(CARD_H)
            card.entry = n
            card.title:SetText(n.title)

            local current, target = tonumber(n.current) or 0, tonumber(n.target) or 0
            card.count:SetText(string.format("%d / %d", math.floor(current), math.floor(target)))
            local countW = card.count:GetStringWidth() or 0
            local bar = card.bar
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", CARD_PAD, CARD_PAD + math.floor((NUM_H - BAR_H) / 2))
            if cardW then
                -- A set width, so the fill is measured against the bar as drawn.
                bar:SetWidth(math.max(1, cardW - 2 * CARD_PAD - countW - GAP))
            else
                bar:SetPoint("RIGHT", card.count, "LEFT", -GAP, 0)
            end
            bar:SetProgress(target > 0 and current / target or 0)
            content.cards[#content.cards + 1] = card
        end
        y = y + rows * CARD_H + math.max(0, rows - 1) * GAP + ROW_GAP
    end

    -- One earned row: the date on the right always; on the left a single title, or a name followed by
    -- the series' tier pills or the group's parts.
    local function earnedRow(r, W)
        local drawn = { row = r, pills = {} }
        local dateFS = take(numbers, C.textSoft)
        dateFS:SetPoint("TOPRIGHT", 0, -y)
        dateFS:SetWidth(COL_W)
        dateFS:SetJustifyH("RIGHT")
        dateFS:SetText(r.at > 0 and day(r.at) or "")
        drawn.date = dateFS

        local title = take(texts, C.text)
        title:SetText(r.name)
        drawn.name = title
        local h
        if r.kind == "single" then
            title:SetPoint("TOPLEFT", 0, -y)
            title:SetPoint("TOPRIGHT", -(COL_W + GAP), -y)
            h = title:GetStringHeight() or 14
        else
            local nameW = W > 0 and math.min(NAME_W, math.floor(W * NAME_SHARE)) or NAME_W
            title:SetPoint("TOPLEFT", 0, -y)
            title:SetWidth(nameW)
            h = title:GetStringHeight() or 14
            local x = nameW + GAP
            if r.kind == "group" then
                local parts = take(texts, C.textSoft)
                parts:SetPoint("TOPLEFT", x, -y)
                parts:SetPoint("TOPRIGHT", -(COL_W + GAP), -y)
                parts:SetText(table.concat(r.parts, " · "))
                drawn.parts = parts
                h = math.max(h, parts:GetStringHeight() or 14)
            else
                -- Earned tiers in text on a lineHi frame; the one being worked on in label on a line
                -- frame, dim beside them, so the collection shows what comes next. No gold: a pill is
                -- not a selection.
                local tiers = {}
                for _, t in ipairs(r.tiers) do tiers[#tiers + 1] = { label = t.label, earned = true, entry = t.entry } end
                if r.following then
                    tiers[#tiers + 1] = { label = r.following.label, earned = false, entry = r.following.entry }
                end
                local avail = W > 0 and (W - x - COL_W - GAP) or math.huge
                local px, py = x, 0
                for _, t in ipairs(tiers) do
                    local pill = pills:Take()
                    pill:SetText(t.label, t.earned and C.text or C.label)
                    if t.earned then pill:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1) end
                    local pw = pill:GetWidth() or PILL_H
                    if px > x and px + pw > x + avail then px, py = x, py + PILL_H + PILL_GAP end
                    pill:SetPoint("TOPLEFT", px, -(y + py) + 1)   -- 1px up: centred on the 12px name
                    pill.earned = t.earned
                    pill.entry = t.entry
                    drawn.pills[#drawn.pills + 1] = pill
                    px = px + pw + PILL_GAP
                end
                h = math.max(h, py + PILL_H - 1)
            end
        end
        -- The row's tooltip: a single's own, a series' newest tier, or a group's parts with their days.
        local hit = hits:Take()
        hit:SetPoint("TOPLEFT", 0, -y)
        hit:SetPoint("TOPRIGHT", 0, -y)
        hit:SetHeight(math.max(h, 14))
        hit:SetScript("OnEnter", function(self)
            if r.kind == "group" then showGroupTip(self, r)
            else showTip(self, r.kind == "single" and r.entry or (r.tiers[#r.tiers] or {}).entry) end
        end)
        drawn.hit = hit
        content.rows[#content.rows + 1] = drawn
        y = y + math.max(h, 14) + ROW_GAP
    end

    local function refresh()
        local A = GuildOS.Achievements
        if not A then return end
        texts:Reset()
        numbers:Reset()
        pills:Reset()
        hits:Reset()
        cards:Reset()
        insignia:Hide()
        nameFS:Hide()
        renownFS:Hide()
        chip:Hide()
        nearHead:Hide()
        earnedHead:Hide()
        content.cards, content.rows = {}, {}
        y = 0

        local level, points = A:Renown()
        if not level then
            line(L["Achievements come from guildos.me: the web companion brings them here when your guild has them."], C.textSoft)
            content:SetHeight(math.max(1, y))
            return
        end
        header(A, level, points)

        local nearest = A:Next()
        if #nearest > 0 then
            heading(nearHead)
            nearestCards(nearest)
        end

        heading(earnedHead)
        local earned = A:Earned()
        if #earned == 0 then line(L["Nothing earned yet."], C.textSoft) end
        local W = width()
        for _, r in ipairs(GuildOS:AchievementCollection(earned, nearest)) do earnedRow(r, W) end
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
