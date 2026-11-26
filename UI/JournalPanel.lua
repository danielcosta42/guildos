----------------------------------------------------------------------
-- Guild OS - The Journal tab (issue #211, guildos.me #242)
-- This week (the guild as a whole), the guild's first clear of each new dungeon, and my own
-- milestones. No ranking of anybody. Modules/Journal.lua answers every question; this draws.
-- WoW: Forever only: the Guild tab's Journal sub-tab since issue #367, offered only where the
-- feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
--
-- Laid out as "Highlights with art" (#373) in the Chronicle's mockup (#449 phase 3): parchment cards, in two
-- columns from a 700px tab and one under it below. On the left the week as three metric blocks and each guild
-- first as a paper box (under its dungeon's art when there is one: the Groups tiles' own picture and crop); on
-- the right my journal as a timeline, a gold dot on a rail per entry, what happened in bold and its day under it.
-- tools/journal-layout.lua checks the structure against fixture data.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

-- Laid out as every Guild sub-tab is (#371): flush left, the first line GAP down.
local GAP = UI.GAP
local FALLBACK_W = 400     -- a hidden tab reads no width: this until OnSizeChanged gives the real one
local TWO_COLUMNS, LEFT_SHARE, GUTTER = 700, 0.535, 12   -- the mockup's .g2
local PAD, TOP = 14, 38    -- a card's padding, and its first line under the title
-- The chips share the card's width out, three to a row, never under CHIP_MIN_W (#373).
local CHIP_MIN_W, CHIP_GAP = 80, GAP
-- The cards: about three in a row at 1000px, never narrower than CARD_MIN_W (#373).
local CARD_MIN_W, CARD_IDEAL_W = 180, 200
local BAND_H = 64          -- the art band on top of a card
local ART_ALPHA = 0.55     -- the art under a Groups tile, so a dungeon looks the same on both screens
-- The timeline: the rail with a gold dot per entry, then the entry in bold with its day under it.
local RAIL_W, DOT = 14, 10
local LINE_H = 16          -- one line of an entry, the least an entry takes
local ROW_GAP = 12
-- A scroll child past 15000px is not drawn at all; 300 entries (two lines each, #449) stay under it, and
-- the rest are counted on a last line. A month of one player's journal is far below that in practice.
local MAX_ENTRIES = 300

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
            parts[i] = GuildOS:ColorText(n, C.paperInk.r, C.paperInk.g, C.paperInk.b)
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

    -- The three cards; their titles are the sections' heads.
    local weekCard = UI:CreateCard(content, L["This week"])
    local firstsCard = UI:CreateCard(content, L["Guild firsts in dungeons"])
    local mineCard = UI:CreateCard(content, L["Your journal"])
    local heads = { week = weekCard.title, firsts = firstsCard.title, mine = mineCard.title }
    local blocks = { week = weekCard, firsts = firstsCard, mine = mineCard }

    -- This week: the same three numbers the line used to say, one block each, made once.
    local chips = {}
    for i, caption in ipairs({ L["Level milestones"], L["Members leveling"], L["Dungeon clears"] }) do
        chips[i] = UI:CreateMetricChip(weekCard, "0", caption)
        chips[i].label:SetWordWrap(false)
        chips[i].label:SetJustifyH("LEFT")
    end

    local function textLine(card)
        local fs = UI:CreateText(card, "", 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        fs:SetJustifyH("LEFT")
        return fs
    end
    local empty = { firsts = textLine(firstsCard), mine = textLine(mineCard) }
    empty.firsts:SetText(L["No new dungeon cleared by the guild yet."])
    empty.mine:SetText(L["Nothing yet: your milestones and dungeon clears appear here."])
    local more = textLine(mineCard)   -- "... and N more." under a timeline cut at MAX_ENTRIES

    -- Pools: the client never frees a frame, so a redraw reuses what the last one made.
    local cards, rows = {}, {}

    -- A first's box: the art band when there is art, a 1px rule under it, then the dungeon in the title face,
    -- its date and bosses, and who was there.
    local function makeCard()
        local card = CreateFrame("Frame", nil, firstsCard)
        card:SetFrameLevel(firstsCard:GetFrameLevel() + 1)
        card.fill = GuildOS.Style:Nine(card, "card", 5, "BACKGROUND", 1)
        card.fill:SetRGBA(0.937, 0.878, 0.741, 1)
        card.edge = GuildOS.Style:Nine(card, "card-line", 5, "BORDER", 0)
        card.edge:SetColor(C.paperRule)
        card.band = card:CreateTexture(nil, "BORDER", nil, 1)
        card.band:SetTexture(WHITE)
        card.band:SetPoint("TOPLEFT", 1, -1)
        card.band:SetPoint("TOPRIGHT", -1, -1)
        card.band:SetHeight(BAND_H)
        card.art = card:CreateTexture(nil, "ARTWORK")
        card.art:SetAllPoints(card.band)
        card.art:SetTexCoord(0, 1, 0.08, 0.72)   -- the Groups tile's crop of the game's LFG art
        card.art:SetAlpha(ART_ALPHA)
        card.rule = card:CreateTexture(nil, "ARTWORK", nil, 1)
        card.rule:SetTexture(WHITE)
        UI:Hairline(card.rule)
        card.rule:SetPoint("TOPLEFT", card.band, "BOTTOMLEFT", 0, 0)
        card.rule:SetPoint("TOPRIGHT", card.band, "BOTTOMRIGHT", 0, 0)
        card.name = UI:CreateText(card, "", 13)
        GuildOS:ApplyFont(card.name, 13, "sectionTitle")
        card.name:SetPoint("TOPLEFT", card.band, "BOTTOMLEFT", 10, -10)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.meta = UI:CreateText(card, "", 11)
        card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
        card.meta:SetJustifyH("LEFT")
        card.meta:SetWordWrap(false)
        card.who = UI:CreateText(card, "", 11)
        card.who:SetPoint("TOPLEFT", card.meta, "BOTTOMLEFT", 0, -4)
        card.who:SetJustifyH("LEFT")
        card.who:SetWordWrap(true)
        return card
    end

    -- A timeline entry: its dot on the rail, what happened, its day under it.
    local function makeRow()
        local r = {}
        r.dot = GuildOS.Style:Texture(mineCard, "orb", "OVERLAY", 1)
        r.dot:SetSize(DOT, DOT)
        r.text = UI:CreateText(mineCard, "", 14)
        GuildOS:ApplyFont(r.text, 14, "itemName")
        r.text:SetJustifyH("LEFT")
        r.date = UI:CreateText(mineCard, "", 11)
        GuildOS:ApplyFont(r.date, 11, "tableNum")   -- a date is a number
        r.date:SetJustifyH("LEFT")
        return r
    end
    -- One line from the first dot to the last, under them.
    local rail = mineCard:CreateTexture(nil, "ARTWORK")
    rail:SetTexture(WHITE)
    rail:SetWidth(2)

    local function place(fs, y, x)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", x or PAD, -y)
    end

    -- A line across a card, wrapped.
    local function line(fs, y)
        place(fs, y)
        fs:SetPoint("TOPRIGHT", -PAD, -y)
        fs:Show()
        return y + (fs:GetStringHeight() or 14) + GAP
    end

    local function paintWeek(week, y, width)
        local values = { week.milestones or 0, week.members or 0, week.clears or 0 }
        local inner = width - 2 * PAD
        local w = math.max(CHIP_MIN_W, math.floor((inner - 2 * CHIP_GAP) / 3))
        local perRow = math.max(1, math.min(3, math.floor((inner + CHIP_GAP) / (w + CHIP_GAP))))
        local h = chips[1]:GetHeight() or 52
        for i, chip in ipairs(chips) do
            chip:SetValue(tostring(values[i]))
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", PAD + col * (w + CHIP_GAP), -(y + row * (h + CHIP_GAP)))
            chip:SetWidth(w)
            chip.label:SetWidth(w - 20)
        end
        return y + math.ceil(3 / perRow) * (h + CHIP_GAP) - CHIP_GAP
    end

    -- Each first as a box, in rows that wrap; a row's boxes share the tallest one's height.
    local function paintFirsts(firsts, y, width)
        for _, card in ipairs(cards) do card:Hide() end
        empty.firsts:Hide()
        if #firsts == 0 then return line(empty.firsts, y) - GAP end
        local inner = width - 2 * PAD
        local cols = math.max(1, math.min(math.floor((inner + GAP) / (CARD_MIN_W + GAP)),
                                          math.floor((inner + GAP) / (CARD_IDEAL_W + GAP) + 0.5)))
        local w = math.floor((inner - GAP * (cols - 1)) / cols)
        local textW = math.max(1, w - 20)
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
            card:SetPoint("TOPLEFT", PAD + col * (w + GAP), -y)
            card:SetWidth(w)
            local art = artOf(f.dungeonId)
            -- No art (no WoW: Forever dungeon has any yet): no band, rather than an empty block in the
            -- box's own colour over the name (#373).
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
            card.rule:SetVertexColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
            card.name:SetWidth(textW)
            card.name:SetText(f.name or f.dungeonId or "?")
            setColor(card.name, C.paperTitle)
            -- The date where the dungeon's name stood in the line this replaced, so the existing
            -- string serves: "2026-11-17 · 4 bosses".
            card.meta:SetWidth(textW)
            card.meta:SetText(string.format(L["%s · %d bosses"], day(f.at), f.bosses or 0))
            setColor(card.meta, C.paperSoft)
            card.who:SetWidth(textW)
            local who = whoText(f.who, classes)
            card.who:SetText(UI:PaperText(who, card.who))   -- class colours in the paper's inks (#449)
            setColor(card.who, C.paperSoft)
            local h = 1 + bandH + (art and 1 or 0) + 10 + (card.name:GetStringHeight() or 12) + 5
                + (card.meta:GetStringHeight() or 12)
            if who ~= "" then h = h + 4 + (card.who:GetStringHeight() or 12) end
            h = math.ceil(h + 10)
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
        local dotX = PAD
        local textX = PAD + RAIL_W + GAP
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
            place(r.text, y, textX)
            r.text:SetPoint("TOPRIGHT", -PAD, -y)
            r.text:SetText(what)
            setColor(r.text, C.paperInk)
            r.text:Show()
            local th = math.max(r.text:GetStringHeight() or LINE_H, LINE_H)
            place(r.date, y + th + 2, textX)
            r.date:SetText(day(e.at))
            setColor(r.date, C.paperSoft)
            r.date:Show()
            r.dot:ClearAllPoints()
            r.dot:SetPoint("TOPLEFT", dotX, -(y + dotY))
            r.dot:SetVertexColor(C.metal2.r, C.metal2.g, C.metal2.b, 1)
            r.dot:Show()
            firstDot = firstDot or (y + dotY)
            lastDot = y + dotY
            y = y + th + 2 + (r.date:GetStringHeight() or 12) + ROW_GAP
        end
        -- Through the dots' middle, from the first to past the last entry's day.
        local x = dotX + math.floor(DOT / 2) - 1
        rail:ClearAllPoints()
        rail:SetPoint("TOPLEFT", x, -(firstDot + math.floor(DOT / 2)))
        rail:SetPoint("BOTTOMLEFT", mineCard, "TOPLEFT", x, -(y - ROW_GAP))
        rail:SetVertexColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
        rail:SetShown(lastDot ~= firstDot)
        if #mine > MAX_ENTRIES then
            -- The Groups lists' own line for what they leave out: its counters fit entries in every
            -- language ("and %d more" counts people in Korean).
            more:SetText(string.format(L["... and %d more."], #mine - MAX_ENTRIES))
            place(more, y, textX)
            more:SetPoint("TOPRIGHT", -PAD, -y)
            more:Show()
            y = y + (more:GetStringHeight() or LINE_H) + ROW_GAP
        end
        return y - ROW_GAP
    end

    local function refresh()
        local J = GuildOS.Journal
        if not J then return end
        -- Read only here, on show and on resize: hidden, the tab reads no width (#373).
        local sw = UI:LaidWidth(scroll) or 0
        local width = math.max(1, (sw > 1 and sw or FALLBACK_W) - UI.SCROLL_GUTTER)
        local two = width >= TWO_COLUMNS
        local lw = two and math.floor((width - GUTTER) * LEFT_SHARE) or width
        local rw = two and (width - GUTTER - lw) or width
        local function put(card, x, y, w, h)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", x, -y)
            card:SetSize(w, h)
            return y + h + GUTTER
        end
        -- 2px in, so the paper's shadow is not cut at the scroll area's edge.
        local yl = put(weekCard, 0, 2, lw, paintWeek(J:ThisWeek(GetServerTime()), TOP, lw) + PAD)
        yl = put(firstsCard, 0, yl, lw, paintFirsts(J:GuildFirsts(), TOP, lw) + PAD)
        local yr = put(mineCard, two and (lw + GUTTER) or 0, two and 2 or yl, rw, paintMine(J:Mine(), TOP) + PAD)
        content:SetHeight(math.max(1, math.max(yl, yr)))
    end

    -- What tools/journal-layout.lua reads back (#373).
    parent.journal = { content = content, heads = heads, blocks = blocks, chips = chips, cards = cards, rows = rows,
                       rail = rail, more = more, empty = empty }

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    -- ponytail: drawn on show and on resize; a clear that syncs in while it is open waits for the next show.
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
