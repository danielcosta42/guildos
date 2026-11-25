----------------------------------------------------------------------
-- Guild OS - The Salão (specs/salao, #445)
-- The first screen, in place of the Now tab: a place that answers in three seconds what is on tonight,
-- who is home and what this player still has to do. Four parchment cards in two columns, stacked when
-- the window is narrow: For you (three lines at most, each one action), the Notice board (the next
-- three events and the newest notice), By the fire (who is online) and the Guild wall (what just
-- happened). While a Winter Veil event is on, its Chimney sits above the fire and its line leads For
-- you. Every line opens the screen that owns it.
--
-- The data half is frame-free (tools/salao.lua tests it); it reads what UI/Agora.lua, Calendar and
-- WinterVeil already know and decides nothing of its own.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local Salao = {}
UI.Salao = Salao

local MAX_FOR_YOU  = 3
local MAX_BOARD    = 3
local MAX_FIRE     = 8
local MAX_WALL     = 5
local TWO_COLUMNS  = 700        -- from this content width the cards sit in two columns
local GUTTER       = 12
local CARD_PAD     = 12
local ROW_H        = 26
local TITLE_H      = 22
local FACE_W       = 92
local FACE_H       = 34
local REFRESH_S    = 15
local WHITE        = "Interface\\Buttons\\WHITE8x8"

local function now() return (GetServerTime and GetServerTime()) or time() end
local function short(full) return full and (full:match("^([^-]+)") or full) or "?" end
local function clean(text)
    return GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(text) or text
end

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------

-- The Winter Veil line, when the event asks something of this player now: { text, action, id }.
function Salao:VeilLine()
    local WV = GuildOS.WinterVeil
    local e = WV and WV:Event()
    if not e then return nil end
    local phase = WV.PhaseOf(e)
    if phase == "joining" and not WV:Joined() then
        return { text = L["Join this year's Secret Santa"], action = L["Join"], id = "winterveil" }
    end
    if phase == "wrapping" then
        for _, g in ipairs(WV:MyGives()) do
            if not g.wrapped then
                return { text = string.format(L["You drew %s in the Secret Santa"], short(g.to)), action = L["Wrap"],
                         id = "winterveil" }
            end
        end
    end
    if phase == "open" then
        local got = WV:Got()
        if got and got.ready and not got.ornament then
            return { text = L["Your snow globe arrived"], action = L["Open"], id = "winterveil" }
        end
    end
    return nil
end

-- For you: the Winter Veil line first, then what UI.Agora's NeedsMe says, then the guild's setup for an
-- officer while it is not done. At most three. { text, action, id, sub, filter } each.
function Salao:ForYou()
    local out = {}
    local veil = self:VeilLine()
    if veil then out[#out + 1] = veil end
    local A = UI.Agora
    for _, n in ipairs(A and A:NeedsMe() or {}) do
        out[#out + 1] = { text = n.text, action = L["Open"], id = n.id, sub = n.sub, filter = n.filter }
    end
    local act = GuildOS.Activation
    if act and act.ShouldShow and act:ShouldShow(now()) then
        local r = act:Read(now())
        local total = 0
        for _ in pairs(r.steps or {}) do total = total + 1 end
        out[#out + 1] = { text = string.format(L["Set up Guild OS for your guild: %d of %d steps"], r.done or 0, total),
                          action = L["Open"], id = "web" }
    end
    for i = #out, MAX_FOR_YOU + 1, -1 do out[i] = nil end
    return out
end

-- The notice board: the next events still to start, { title, when, rsvp }, and the newest notice.
function Salao:Board()
    local events, cal = {}, GuildOS.Calendar
    if cal and cal.GetUpcoming and GuildOS.db and GuildOS.db.calendar then
        local t = now()
        for _, e in ipairs(cal:GetUpcoming(false)) do
            if (e.when or 0) > t then
                events[#events + 1] = { title = clean(e.title or "?"), when = e.when,
                                        rsvp = cal.MyRsvp and cal:MyRsvp(e) or nil }
                if #events >= MAX_BOARD then break end
            end
        end
    end
    local A = UI.Agora
    local notice = A and A:Notices(1)[1] or nil
    return events, notice
end

-- By the fire: who is online now, this player left out, { name, full, class, classFile, zone, level, rank }.
function Salao:Fireside()
    local out, me, total = {}, GuildOS.Compat.PlayerName(), 0
    for i = 1, GetNumGuildMembers() or 0 do
        local full, rank, rankIndex, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if full and online and short(full) ~= me then
            total = total + 1
            if #out < MAX_FIRE then
                out[#out + 1] = { name = short(full), full = full, class = class, classFile = classFile, zone = zone,
                                  level = level, rank = rank, rankIndex = rankIndex }
            end
        end
    end
    return out, total
end

-- The Chimney while a Winter Veil event is on: { entrants, wrapped, opened, lit }. Counts only: who wrapped
-- stays the officers' (specs/winter-veil).
function Salao:Chimney()
    local WV = GuildOS.WinterVeil
    local e = WV and WV:Event()
    if not e then return nil end
    local c = type(e.counts) == "table" and e.counts or {}
    local entrants = math.max(0, math.floor(tonumber(c.entrants) or 0))
    if entrants == 0 then return nil end
    return { entrants = entrants, wrapped = math.min(entrants, math.max(0, math.floor(tonumber(c.wrapped) or 0))),
             opened = math.max(0, math.floor(tonumber(c.opened) or 0)), lit = WV.PhaseOf(e) == "open" }
end

-- WoW: Forever's countdown to the raids (issue #207), until a week after they open: Readiness:Countdown counts
-- (the days, each core at the level cap, the guild), this only reads it. Nil anywhere else.
-- The report walks the whole roster and its gear, so it is never built off Forever, and at most once every
-- COUNTDOWN_S: the 15s ticker and a resize redraw from the last answer.
local COUNTDOWN_S = 60
function Salao:Countdown()
    local client = GuildOS.Client or {}
    if client.isRetail or client.isAnniversary then return nil end
    local R = GuildOS.Readiness
    if not (R and R.Countdown and R.GetReport) then return nil end
    local t = now()
    if self._cdAt and t - self._cdAt < COUNTDOWN_S then return self._cd end
    local ok, cd = GuildOS:SafeCall(function() return R:Countdown(R:GetReport(), t) end)
    self._cd, self._cdAt = ok and cd or nil, t
    return self._cd
end

-- The countdown's title and lines, { text, side } each, as the Now card said them.
function Salao:CountdownLines(cd)
    local title = cd.open and L["The raids are open"]
        or cd.days == 0 and L["Raids open in under a day"]
        or cd.days == 1 and L["Raids open in 1 day"]
        or string.format(L["Raids open in %d days"], cd.days)
    local lines = {}
    for _, c in ipairs(cd.cores or {}) do
        lines[#lines + 1] = { text = c.name, side = string.format(L["%d / %d at %d"], c.ready, c.size, cd.cap) }
    end
    local g = cd.guild or { ready = 0, slices = {} }
    local sl = g.slices or {}
    local side
    if sl.short then
        side = sl.shortSize == (GuildOS.Readiness and GuildOS.Readiness.DUNGEON_GROUP)
            and string.format(L["%d at %d · %d more for a group"], g.ready, cd.cap, sl.short)
            or string.format(L["%d at %d · %d more for a %d"], g.ready, cd.cap, sl.short, sl.shortSize)
    else
        side = string.format(L["%d at %d"], g.ready, cd.cap)
    end
    lines[#lines + 1] = { text = L["Guild"], side = side }
    return title, lines
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function text(parent, size, color, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A parchment card: the paper, a bronze line, and its title in the paper's ink.
local function card(parent, title, dark)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
    local bg, ink = dark and C.well or C.paper, dark and C.gold or C.paperInk
    f:SetBackdropColor(bg.r, bg.g, bg.b, dark and 0.85 or 1)
    f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    f.title = text(f, 14, ink, "sectionTitle")
    f.title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    f.title:SetText(title)
    f.ink = dark and C.text or C.paperInk
    f.soft = dark and C.textSoft or C.paperSoft
    f.rows = {}
    return f
end

-- One line of a card: its text, a smaller line under it, and an action button at the right.
local function row(cardFrame, i)
    local r = cardFrame.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, cardFrame)
    r:SetHeight(ROW_H)
    r.main = text(r, 12, cardFrame.ink)
    r.main:SetPoint("LEFT", 0, 0)
    r.side = text(r, 11, cardFrame.soft)
    r.side:SetJustifyH("RIGHT")
    r.btn = UI:CreateButton(r, "", 70, 20)
    r.btn:SetPoint("RIGHT", 0, 0)
    r.btn:SetScript("OnClick", function() if r.run then r.run() end end)
    r:SetScript("OnClick", function() if r.run then r.run() end end)
    cardFrame.rows[i] = r
    return r
end

local function open(item)
    return function() UI:OpenWindow(item.id, item.sub, item.filter) end
end

-- Lays a card's lines from the top, returns its height.
local function fillRows(cardFrame, items, width)
    for _, r in ipairs(cardFrame.rows) do r:Hide() end
    local y = CARD_PAD + TITLE_H
    for i, item in ipairs(items) do
        local r = row(cardFrame, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", CARD_PAD, -y)
        r:SetWidth(width - 2 * CARD_PAD)
        r.main:SetText(item.text or "")
        r.run = item.run
        local right = 0
        if item.action then
            r.btn.label:SetText(item.action)
            r.btn:SetWidth(math.max(60, math.ceil(r.btn.label:GetStringWidth()) + 20))
            r.btn:Show()
            right = r.btn:GetWidth() + 8
        else
            r.btn:Hide()
        end
        r.side:ClearAllPoints()
        if item.side then
            r.side:SetText(item.side)
            r.side:SetPoint("RIGHT", -right, 0)
            r.side:Show()
            right = right + math.ceil(r.side:GetStringWidth()) + 8
        else
            r.side:Hide()
        end
        r.main:SetWidth(math.max(40, width - 2 * CARD_PAD - right))
        r:Show()
        y = y + ROW_H
    end
    return y + CARD_PAD
end

-- This player's answer, as Calendar keeps it (Calendar.STATUS: yes, tentative, no; "wait" on a full raid).
local function rsvpText(rsvp)
    local status = type(rsvp) == "table" and rsvp.status or nil
    if status == "yes" then return L["You are going"] end
    if status == "tentative" then return L["Maybe"] end
    if status == "no" then return L["Not going"] end
    if status == "wait" then return L["Standby"] end
    return nil
end

function GuildOS:CreateSalaoPanel(panel)
    local scroll, content = UI:CreateScrollFrame(panel, "GuildOSSalaoScroll")
    scroll:SetAllPoints(panel)
    UI:BindScrollChildWidth(scroll, content)
    panel.scroll, panel.content = scroll, content

    local forYou   = card(content, L["For you"])
    local board    = card(content, L["Notice board"])
    local chimney  = card(content, L["The Chimney"], true)
    local fire     = card(content, L["By the fire"], true)
    local wall     = card(content, L["Guild wall"])
    local raidsIn  = card(content, "", true)
    panel.cards = { forYou = forYou, board = board, chimney = chimney, fire = fire, wall = wall, countdown = raidsIn }

    -- Start raid (#400), under the board, while this player may lead the invites of the site's raid in its window:
    -- the same stepper the Web screen has. The raid's name over it when it is not the board's first event.
    local stepRoster, stepFor
    local start = UI.CreateRaidStepper and UI:CreateRaidStepper(board, { roster = function() return stepRoster end })
    local startFor = text(board, 11, C.paperSoft)
    if start then start:Hide(); start.why:Hide() end
    startFor:Hide()
    panel.startRaid, panel.startFor = start, startFor

    -- By the fire: one name per guildmate online, in its class colour, the zone under it.
    fire.faces = {}
    local function face(i)
        local b = fire.faces[i]
        if b then return b end
        b = CreateFrame("Button", nil, fire)
        b:SetSize(FACE_W, FACE_H)
        b.name = text(b, 12, C.text)
        b.name:SetPoint("TOPLEFT", 0, -2)
        b.name:SetWidth(FACE_W - 4)
        b.zone = text(b, 10, C.textSoft)
        b.zone:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
        b.zone:SetWidth(FACE_W - 4)
        b:SetScript("OnClick", function(self)
            local m = self.member
            if not m then return end
            GuildOS:SafeCall(function()
                GuildOS:ShowMemberContextMenu(self, {
                    name = m.name, fullName = m.full, key = GuildOS:KeyOfRosterName(m.full), class = m.class,
                    classFile = m.classFile, level = m.level, rank = m.rank, rankIndex = m.rankIndex,
                    zone = m.zone, online = true, isOnline = true,
                })
            end)
        end)
        fire.faces[i] = b
        return b
    end
    fire.more = text(fire, 11, C.textSoft)

    -- The Chimney: one stocking per entrant, filled for each who wrapped.
    chimney.stockings = {}
    chimney.line = text(chimney, 12, C.text)
    chimney.line:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_H))

    local function fillFire(width)
        local list, total = Salao:Fireside()
        for _, b in ipairs(fire.faces) do b:Hide() end
        local perRow = math.max(1, math.floor((width - 2 * CARD_PAD) / FACE_W))
        local y = CARD_PAD + TITLE_H
        for i, m in ipairs(list) do
            local b = face(i)
            b.member = m
            local cc = m.classFile and GuildOS.ClassColors[m.classFile] or C.text
            b.name:SetText(m.name)
            b.name:SetTextColor(cc.r, cc.g, cc.b)
            b.zone:SetText(clean(m.zone or ""))
            local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", CARD_PAD + col * FACE_W, -(y + line * (FACE_H + 4)))
            b:Show()
        end
        local lines = math.max(1, math.ceil(#list / perRow))
        y = y + lines * (FACE_H + 4)
        fire.more:ClearAllPoints()
        fire.more:SetPoint("TOPLEFT", CARD_PAD, -y)
        if #list == 0 then
            fire.more:SetText(L["Nobody else is online right now."])
        elseif total > #list then
            fire.more:SetText(string.format(L["and %d more online"], total - #list))
        else
            fire.more:SetText("")
        end
        return y + ROW_H + CARD_PAD
    end

    local function fillChimney(width)
        local c = Salao:Chimney()
        for _, s in ipairs(chimney.stockings) do s:Hide() end
        if not c then return 0 end
        chimney.title:SetText(c.lit and L["The Chimney is lit"] or L["The Chimney"])
        chimney.line:SetText(c.lit and string.format(L["%d of %d globes opened"], math.min(c.opened, c.entrants), c.entrants)
            or string.format(L["%d of %d entrants wrapped their globe"], c.wrapped, c.entrants))
        local size, gap = 14, 4
        local perRow = math.max(1, math.floor((width - 2 * CARD_PAD + gap) / (size + gap)))
        local y0 = CARD_PAD + TITLE_H + 20
        for i = 1, c.entrants do
            local s = chimney.stockings[i]
            if not s then
                s = chimney:CreateTexture(nil, "ARTWORK")
                s:SetTexture(WHITE)
                s:SetSize(size, size + 4)
                chimney.stockings[i] = s
            end
            local full = c.lit or i <= c.wrapped
            local col = full and C.danger or C.line
            s:SetVertexColor(col.r, col.g, col.b, 1)
            local cx, cy = (i - 1) % perRow, math.floor((i - 1) / perRow)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", CARD_PAD + cx * (size + gap), -(y0 + cy * (size + 8)))
            s:Show()
        end
        return y0 + math.ceil(c.entrants / perRow) * (size + 8) + CARD_PAD
    end

    local function refresh()
        local w = content:GetWidth() or 0
        if w <= 1 then w = (panel:GetWidth() or 0) - (UI.SCROLL_GUTTER or 0) end
        if w <= 1 then return end
        content:SetWidth(w)
        local two = w >= TWO_COLUMNS
        local leftW = two and math.floor((w - GUTTER) * 0.55) or w
        local rightW = two and (w - GUTTER - leftW) or w

        -- For you
        local items = {}
        for _, it in ipairs(Salao:ForYou()) do
            items[#items + 1] = { text = it.text, action = it.action, run = open(it) }
        end
        if #items == 0 then items[1] = { text = L["All caught up."] } end
        local hYou = fillRows(forYou, items, leftW)

        -- Notice board
        local events, notice = Salao:Board()
        local bItems = {}
        for _, e in ipairs(events) do
            local when = GuildOS:LocalDate(L["%a %d %b, %H:%M"], e.when)
            local answer = rsvpText(e.rsvp)
            bItems[#bItems + 1] = { text = e.title, side = answer and (when .. " · " .. answer) or when,
                                    run = open({ id = "guild", sub = "calendar", filter = e.when }) }
        end
        if notice then bItems[#bItems + 1] = { text = notice.text, run = open(notice) } end
        if #bItems == 0 then bItems[1] = { text = L["Nothing on the calendar yet."], run = open({ id = "guild", sub = "calendar" }) } end
        local hBoard = fillRows(board, bItems, leftW)
        local A0 = UI.Agora
        stepRoster, stepFor = nil, nil
        if A0 and start then stepRoster, stepFor = A0:StartRaid(A0:NextRaid()) end
        local stepping = start ~= nil and stepRoster ~= nil
        startFor:SetShown(stepping and stepFor ~= nil)
        if start then start:SetShown(stepping); start.why:SetShown(stepping) end
        if stepping then
            local y = hBoard - CARD_PAD
            if stepFor then
                startFor:SetText(stepFor)
                startFor:ClearAllPoints()
                startFor:SetPoint("TOPLEFT", CARD_PAD, -y)
                y = y + 16
            end
            start:ClearAllPoints()
            start:SetPoint("TOPLEFT", CARD_PAD, -(y + 4))
            start.why:ClearAllPoints()
            start.why:SetPoint("TOPLEFT", start, "BOTTOMLEFT", 0, -4)
            start.why:SetWidth(leftW - 2 * CARD_PAD)
            hBoard = y + 4 + start:GetHeight() + 4 + 28 + CARD_PAD
        end

        -- Guild wall
        local wItems = {}
        local A = UI.Agora
        for _, a in ipairs(A and A:Activity(MAX_WALL) or {}) do
            wItems[#wItems + 1] = { text = a.text, side = GuildOS:TimeAgo(a.ts), run = open(a) }
        end
        if #wItems == 0 then wItems[1] = { text = L["Nothing new in the guild yet."] } end
        local hWall = fillRows(wall, wItems, rightW)

        local hCount = 0
        local cd = Salao:Countdown()
        if cd then
            local title, lines = Salao:CountdownLines(cd)
            raidsIn.title:SetText(title)
            hCount = fillRows(raidsIn, lines, rightW)
        else
            fillRows(raidsIn, {}, rightW)
        end
        local hChimney = fillChimney(rightW)
        local hFire = fillFire(rightW)

        local function place(f, x, y, width, h)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", x, -y)
            f:SetSize(width, h)
            f:SetShown(h > 0)
            return h > 0 and (y + h + GUTTER) or y
        end
        local yl = place(forYou, 0, 0, leftW, hYou)
        yl = place(board, 0, yl, leftW, hBoard)
        local xr, yr = two and (leftW + GUTTER) or 0, two and 0 or yl
        yr = place(raidsIn, xr, yr, rightW, hCount)
        yr = place(chimney, xr, yr, rightW, hChimney)
        yr = place(fire, xr, yr, rightW, hFire)
        yr = place(wall, xr, yr, rightW, hWall)
        content:SetHeight(math.max(yl, yr))
    end
    panel.Refresh = refresh

    panel:SetScript("OnShow", function()
        GuildOS:SafeCall(refresh)
        if not panel.ticker then
            panel.ticker = C_Timer.NewTicker(REFRESH_S, function() if panel:IsVisible() then GuildOS:SafeCall(refresh) end end)
        end
    end)
    panel:SetScript("OnHide", function()
        if panel.ticker then panel.ticker:Cancel(); panel.ticker = nil end
    end)
    -- The scroll child stops short of the scroll bar (as BindScrollChildWidth); laid out again on a resize.
    -- A grip drag resizes every frame: the cards are laid out again once it settles, not each frame.
    UI:MakeResponsive(panel, function(_, w)
        content:SetWidth(math.max(1, (w or 0) - (UI.SCROLL_GUTTER or 0)))
        GuildOS:Coalesce("salaoLayout", 0.2, function()
            if panel:IsVisible() then GuildOS:SafeCall(refresh) end
        end)
    end)
    GuildOS:SafeCall(refresh)
end
