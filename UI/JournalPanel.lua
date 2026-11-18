----------------------------------------------------------------------
-- Guild OS - The Journal tab (issue #211, guildos.me #242)
-- This week (the guild as a whole), the guild's first clear of each new dungeon, and my own
-- milestones. No ranking of anybody. Modules/Journal.lua answers every question; this draws.
-- WoW: Forever only: the Guild tab's Journal sub-tab since issue #367, offered only where the
-- feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
--
-- Laid out as "Highlights with art" (#373): the week as three metric chips, each guild first as a
-- card under its dungeon's art (the Groups tiles' own picture and crop), and my journal as a
-- timeline. Flat surfaces and 1px lines; the only gold is the chips' rule, which the chip draws.
-- tools/journal-layout.lua checks the structure against fixture data.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

-- Laid out as every Guild sub-tab is (#371): flush left, the first line GAP down, a section title
-- over each block.
local GAP = UI.GAP
local SECTION_SPACE = 20   -- over a later section title: its rule sits 12px above it
local FALLBACK_W = 400     -- a hidden tab reads no width: this until OnSizeChanged gives the real one
-- The chips share one width, the widest caption's and never under CHIP_MIN_W, so the three rules
-- line up; a window too narrow for three of them shares its width out instead (#373).
local CHIP_MIN_W, CHIP_GAP = 120, 3 * GAP
-- The cards: about three in a row at 1000px, never narrower than CARD_MIN_W (#373).
local CARD_MIN_W, CARD_IDEAL_W = 180, 300
local BAND_H = 64          -- the art band on top of a card
local ART_ALPHA = 0.55     -- the art under a Groups tile, so a dungeon looks the same on both screens
-- The timeline: the date in its own column, then the rail with a dot per entry, then the entry.
local DATE_W = 80          -- "2026-11-17" in Mono with room to spare
local RAIL_W, DOT = 13, 5
local LINE_H = 14          -- one line of an entry, the least an entry takes
local ROW_GAP = 8
-- A scroll child past 15000px is not drawn at all; 400 entries stay well under it, and the rest are
-- counted on a last line. A month of one player's journal is far below that in practice.
local MAX_ENTRIES = 400

-- The dungeon's art is the Groups tile's (Data/GroupActivities.lua, issue #341), guarded the way the
-- tile guards it: a path the client does not have draws a green square. Asked once per path.
local artChecked = {}
local function artOf(dungeonId)
    local cat = GuildOS.GroupActivities
    local it = cat and cat.byId and cat.byId[dungeonId]
    local path = it and it.art
    if type(path) ~= "string" then return nil end
    if artChecked[path] == nil then artChecked[path] = GuildOS.Compat.TextureExists(path) == true end
    return artChecked[path] and path or nil
end

-- Journal:GuildFirsts names who was there by their key less its realm; the member data knows their
-- class. A name two members share with different classes is left uncoloured rather than guessed.
local function classesByName()
    local out = {}
    local members = GuildOS.db and GuildOS.db.members
    for k, m in pairs(type(members) == "table" and members or {}) do
        if type(k) == "string" and type(m) == "table" and type(m.class) == "string" and m.class ~= "" then
            local n = k:match("^(.-)%-[^-]*$") or k
            if out[n] == nil then out[n] = m.class elseif out[n] ~= m.class then out[n] = false end
        end
    end
    return out
end

local function whoText(names, classes)
    local parts = {}
    for i, n in ipairs(names or {}) do
        local cls = classes[n]
        if cls then
            parts[i] = GuildOS:ColorText(n, GuildOS:GetClassColor(cls))
        else
            parts[i] = GuildOS:ColorText(n, C.text.r, C.text.g, C.text.b)
        end
    end
    return table.concat(parts, " · ")   -- the separators keep the line's own textSoft
end

local function setColor(fs, col) fs:SetTextColor(col.r, col.g, col.b) end

function GuildOS:CreateJournalPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSJournalScroll")
    scroll:SetPoint("TOPLEFT", 0, -GAP)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- The content keeps the list's width, less the scroll bar's gutter.
    UI:BindScrollChildWidth(scroll, content)

    local heads = {
        week   = UI:CreateSectionTitle(content, L["THIS WEEK"], true),
        firsts = UI:CreateSectionTitle(content, L["GUILD FIRSTS"]),
        mine   = UI:CreateSectionTitle(content, L["YOUR JOURNAL"]),
    }

    -- This week: the same three numbers the line used to say, one chip each, made once.
    local chips = {}
    for i, caption in ipairs({ L["Level milestones"], L["Members leveling"], L["Dungeon clears"] }) do
        chips[i] = UI:CreateMetricChip(content, "0", caption)
        chips[i].label:SetWordWrap(false)
    end

    local function textLine()
        local fs = UI:CreateText(content, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        fs:SetJustifyH("LEFT")
        return fs
    end
    local empty = { firsts = textLine(), mine = textLine() }
    empty.firsts:SetText(L["No new dungeon cleared by the guild yet."])
    empty.mine:SetText(L["Nothing yet: your milestones and dungeon clears appear here."])
    local more = textLine()   -- "... and N more." under a timeline cut at MAX_ENTRIES

    -- Pools: the client never frees a frame, so a redraw reuses what the last one made.
    local cards, rows = {}, {}

    -- A card: the art band (or a flat `panel` band), a 1px rule under it, then the dungeon, its
    -- bosses and date, and who was there.
    local function makeCard()
        -- Above the content's level: CreatePanel's default (1) could sit under a painted ancestor.
        local card = UI:CreatePanel(content, nil, content:GetFrameLevel() + 1)
        card.band = card:CreateTexture(nil, "BORDER")
        card.band:SetTexture(WHITE)
        card.band:SetPoint("TOPLEFT", 1, -1)
        card.band:SetPoint("TOPRIGHT", -1, -1)
        card.band:SetHeight(BAND_H)
        card.art = card:CreateTexture(nil, "ARTWORK")
        card.art:SetAllPoints(card.band)
        card.art:SetTexCoord(0, 1, 0.08, 0.72)   -- the Groups tile's crop of the game's LFG art
        card.art:SetAlpha(ART_ALPHA)
        card.rule = UI:CreateSeparator(card)
        card.rule:SetPoint("TOPLEFT", card.band, "BOTTOMLEFT", 0, 0)
        card.rule:SetPoint("TOPRIGHT", card.band, "BOTTOMRIGHT", 0, 0)
        card.name = UI:CreateText(card, "", 12)
        card.name:SetPoint("TOPLEFT", card.band, "BOTTOMLEFT", GAP - 1, -GAP)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.meta = UI:CreateText(card, "", 11)
        card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
        card.meta:SetJustifyH("LEFT")
        card.meta:SetWordWrap(false)
        card.who = UI:CreateText(card, "", 11)
        card.who:SetPoint("TOPLEFT", card.meta, "BOTTOMLEFT", 0, -4)
        card.who:SetJustifyH("LEFT")
        card.who:SetWordWrap(true)
        return card
    end

    -- A timeline entry: its date, its dot on the rail, what happened.
    local function makeRow()
        local r = {}
        r.date = UI:CreateText(content, "", 11)
        GuildOS:ApplyFont(r.date, 11, "tableNum")   -- a date is a number: Plex Mono (#361)
        r.date:SetJustifyH("LEFT")
        r.dot = content:CreateTexture(nil, "OVERLAY")
        r.dot:SetTexture(WHITE)
        r.dot:SetSize(DOT, DOT)
        r.text = UI:CreateText(content, "", 12)
        r.text:SetJustifyH("LEFT")
        return r
    end
    -- One 1px line from the first dot to the last, under them.
    local rail = content:CreateTexture(nil, "ARTWORK")
    rail:SetTexture(WHITE)
    UI:Hairline(rail, "Width")

    local function place(fs, y, x)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", x or 0, -y)
    end

    local function heading(fs, y, first)
        if not first then y = y + SECTION_SPACE end
        place(fs, y)
        return y + (fs:GetStringHeight() or 14) + GAP
    end

    -- A line across the content, wrapped.
    local function line(fs, y)
        place(fs, y)
        fs:SetPoint("TOPRIGHT", 0, -y)
        fs:Show()
        return y + (fs:GetStringHeight() or 14) + GAP
    end

    local function paintWeek(week, y, width)
        local values = { week.milestones or 0, week.members or 0, week.clears or 0 }
        local w = CHIP_MIN_W
        for i, chip in ipairs(chips) do
            chip:SetValue(tostring(values[i]))
            chip.label:SetWidth(0)
            w = math.max(w, math.ceil(chip.value:GetStringWidth() or 0), math.ceil(chip.label:GetStringWidth() or 0))
        end
        w = math.max(34, math.min(w, math.floor((width - 2 * CHIP_GAP) / 3)))
        for i, chip in ipairs(chips) do
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", (i - 1) * (w + CHIP_GAP), -y)
            chip:SetWidth(w)
            chip.label:SetWidth(w)
            setColor(chip.value, C.text)
            setColor(chip.label, C.label)
        end
        return y + (chips[1]:GetHeight() or 52)
    end

    -- Each first as a card, in rows that wrap; a row's cards share the tallest one's height.
    local function paintFirsts(firsts, y, width)
        for _, card in ipairs(cards) do card:Hide() end
        empty.firsts:Hide()
        if #firsts == 0 then return line(empty.firsts, y) - GAP end
        local cols = math.max(1, math.min(math.floor((width + GAP) / (CARD_MIN_W + GAP)),
                                          math.floor((width + GAP) / (CARD_IDEAL_W + GAP) + 0.5)))
        local w = math.floor((width - GAP * (cols - 1)) / cols)
        local inner = math.max(1, w - 2 * GAP)
        local classes = classesByName()
        local rowCards, rowH = {}, 0
        local function closeRow()
            for _, card in ipairs(rowCards) do card:SetHeight(rowH) end
            y = y + rowH + GAP
            rowCards, rowH = {}, 0
        end
        for i, f in ipairs(firsts) do
            local card = cards[i]
            if not card then card = makeCard(); cards[i] = card end
            local col = (i - 1) % cols
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", col * (w + GAP), -y)
            card:SetWidth(w)
            local art = artOf(f.dungeonId)
            -- No art (no WoW: Forever dungeon has any yet): no band, rather than an empty block in the
            -- card's own colour over the name (#373).
            local bandH = art and BAND_H or 0
            card.band:SetHeight(math.max(bandH, 0.01))
            card.band:SetShown(art ~= nil)
            card.rule:SetShown(art ~= nil)
            card.band:SetVertexColor(C.well.r, C.well.g, C.well.b, 1)
            if art then
                card.art:SetTexture(art)
                card.art:Show()
            else
                card.art:Hide()
            end
            card.rule:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
            card.name:SetWidth(inner)
            card.name:SetText(f.name or f.dungeonId or "?")
            setColor(card.name, C.text)
            -- The date where the dungeon's name stood in the line this replaced, so the existing
            -- string serves: "2026-11-17 · 4 bosses".
            card.meta:SetWidth(inner)
            card.meta:SetText(string.format(L["%s · %d bosses"], day(f.at), f.bosses or 0))
            setColor(card.meta, C.textSoft)
            card.who:SetWidth(inner)
            local who = whoText(f.who, classes)
            card.who:SetText(who)
            setColor(card.who, C.textSoft)
            local h = 1 + bandH + (art and 1 or 0) + GAP + (card.name:GetStringHeight() or 12) + 2
                + (card.meta:GetStringHeight() or 12)
            if who ~= "" then h = h + 4 + (card.who:GetStringHeight() or 12) end
            h = math.ceil(h + GAP + 1)
            card:Show()
            rowCards[#rowCards + 1] = card
            rowH = math.max(rowH, h)
            if col == cols - 1 then closeRow() end
        end
        if #rowCards > 0 then closeRow() end
        return y - GAP
    end

    -- My entries, newest first, down the rail.
    local function paintMine(mine, y)
        for _, r in ipairs(rows) do r.date:Hide(); r.dot:Hide(); r.text:Hide() end
        rail:Hide()
        more:Hide()
        empty.mine:Hide()
        if #mine == 0 then return line(empty.mine, y) - GAP end
        local railX = DATE_W + GAP
        local dotX = railX + math.floor((RAIL_W - DOT) / 2)
        local textX = railX + RAIL_W + GAP
        local dotY = math.floor((LINE_H - DOT) / 2)
        local firstDot, lastDot
        for i = 1, math.min(#mine, MAX_ENTRIES) do
            local e = mine[i]
            local r = rows[i]
            if not r then r = makeRow(); rows[i] = r end
            local what
            if e.type == "dungeon.clear" then
                what = string.format(L["%s · %d bosses"], e.data.dungeonName or e.data.dungeonId or "?", e.data.bosses or 0)
            else
                what = string.format(L["Level %d"], e.type == "member.level60" and GuildOS.Client.maxLevel or e.data.level or 0)
            end
            place(r.date, y)
            r.date:SetWidth(DATE_W)
            r.date:SetText(day(e.at))
            setColor(r.date, C.textSoft)
            r.date:Show()
            place(r.text, y, textX)
            r.text:SetPoint("TOPRIGHT", 0, -y)
            r.text:SetText(what)
            setColor(r.text, C.text)
            r.text:Show()
            r.dot:ClearAllPoints()
            r.dot:SetPoint("TOPLEFT", dotX, -(y + dotY))
            r.dot:SetVertexColor(C.label.r, C.label.g, C.label.b, 1)
            r.dot:Show()
            firstDot = firstDot or (y + dotY)
            lastDot = y + dotY
            y = y + math.max(r.text:GetStringHeight() or LINE_H, LINE_H) + ROW_GAP
        end
        if lastDot ~= firstDot then
            -- Through the dots' middle pixel: a 5px dot's third column.
            local x = dotX + math.floor(DOT / 2)
            rail:ClearAllPoints()
            rail:SetPoint("TOPLEFT", x, -(firstDot + math.floor(DOT / 2)))
            rail:SetPoint("BOTTOMLEFT", content, "TOPLEFT", x, -(lastDot + math.floor(DOT / 2)))
            rail:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
            rail:Show()
        end
        if #mine > MAX_ENTRIES then
            -- The Groups lists' own line for what they leave out: its counters fit entries in every
            -- language ("and %d more" counts people in Korean).
            more:SetText(string.format(L["... and %d more."], #mine - MAX_ENTRIES))
            place(more, y, textX)
            more:SetPoint("TOPRIGHT", 0, -y)
            more:Show()
            y = y + (more:GetStringHeight() or LINE_H) + ROW_GAP
        end
        return y - ROW_GAP
    end

    local function refresh()
        local J = GuildOS.Journal
        if not J then return end
        -- Read only here, on show and on resize: hidden, the tab reads no width (#373).
        local sw = scroll:GetWidth() or 0
        local width = math.max(1, (sw > 1 and sw or FALLBACK_W) - UI.SCROLL_GUTTER)
        local y = heading(heads.week, 0, true)
        y = paintWeek(J:ThisWeek(GetServerTime()), y, width)
        y = heading(heads.firsts, y)
        y = paintFirsts(J:GuildFirsts(), y, width)
        y = heading(heads.mine, y)
        y = paintMine(J:Mine(), y)
        content:SetHeight(math.max(1, y + GAP))   -- a GAP of air under the last line
    end

    -- What tools/journal-layout.lua reads back (#373).
    parent.journal = { content = content, heads = heads, chips = chips, cards = cards, rows = rows,
                       rail = rail, more = more, empty = empty }

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    -- ponytail: drawn on show and on resize; a clear that syncs in while it is open waits for the next show.
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
