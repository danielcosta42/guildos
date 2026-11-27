----------------------------------------------------------------------
-- Guild OS - The Salão (specs/salao, #445)
-- The first screen, in place of the Now tab: a place that answers in three seconds what is on tonight,
-- who is home and what this player still has to do. Drawn as the approved mockup's Início (phase 3, #449),
-- in two columns, stacked when the window is narrow. On the left, parchment cards: Get started (an officer's,
-- while the guild is not set up: specs/salao/onboarding.md, WoW: Forever's activation folded in), For you (three lines at most, each a coloured square, a line
-- under it and one button), the Notice board (the next events as pinned notes, this player's answer
-- outlining each, and the newest notice under them) and, filling the column's height under it, the Guild chat
-- (a dark card: the last lines of /g, an officer's channel too for an officer, and a box to answer). On the right: the countdown to the raids (Forever),
-- the Chimney while a Winter Veil event is on, By the fire (a dark card of round class avatars and a "+n"
-- disc) and the Guild wall (a glyph, the line, its time). Every line opens the screen that owns it.
--
-- The data half is frame-free (tools/salao.lua tests it); it reads what UI/Agora.lua, Calendar and
-- WinterVeil already know and decides nothing of its own.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local Salao = {}
UI.Salao = Salao

local MAX_FOR_YOU  = 3
local MAX_BOARD    = 3
local MAX_NOTICES  = 3          -- the bulletin's newest notices under the notes, as 1.39.0 promised
local MAX_FIRE     = 7          -- seven faces and the "+n" disc fill two rows of four
local MAX_WALL     = 5
local TWO_COLUMNS  = 700        -- from this content width the cards sit in two columns
local LEFT_SHARE   = 0.535      -- the mockup's 1.15fr : 1fr
local GUTTER       = 12
local CARD_PAD     = UI.SP.PAD
local ROW_H        = 26         -- a countdown's line
local TODO_H       = 44         -- a For you line: the square, two lines of text, a button
local TITLE_H      = 26
local FACE_H       = 78
local AVATAR       = 40
local NOTE_H       = 74
local NOTE_GAP     = 10
local GLYPH        = 26
local WALL_H       = 30
local REFRESH_S    = 15
local CHAT_LINES   = 40         -- the Guild chat card's lines at most (pooled)
local OFFICER_GREEN = { r = 0.25, g = 0.75, b = 0.25 }   -- an Officers channel line's body
local CHAT_MIN     = 180        -- its least height beside the right column
local CHAT_STACKED = 260        -- its height in one column
local CHAT_AV      = 18
local CHAT_FIELD   = 24

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

-- For you: the Winter Veil line first, then what UI.Agora's NeedsMe says. At most three.
-- { text, action, id, sub, filter, count, urgent } each. The guild's setup has its own card (Salao:Setup).
function Salao:ForYou()
    local out = {}
    -- A member's getting started (specs/salao/onboarding.md): one line, the whole list in Settings › Help.
    local Ob = GuildOS.Onboarding
    local gs = Ob and Ob.MemberLine and Ob:MemberLine(now())
    if gs then
        out[#out + 1] = { text = L["Getting started"], action = L["Open"], id = "settings", sub = "help",
                          mark = string.format("%d/%d", gs.done, gs.total), gettingStarted = true,
                          small = L["Settings \226\128\186 Help \194\183 a few small things to set up"] }
    end
    local veil = self:VeilLine()
    if veil then out[#out + 1] = veil end
    local A = UI.Agora
    for _, n in ipairs(A and A:NeedsMe() or {}) do
        out[#out + 1] = { text = n.text, action = L["Open"], id = n.id, sub = n.sub, filter = n.filter, count = n.count,
                          urgent = n.urgent }
    end
    for i = #out, MAX_FOR_YOU + 1, -1 do out[i] = nil end
    return out
end

-- Get started, the officers' card (specs/salao/onboarding.md; Modules/Onboarding.lua): { items, done, total, all,
-- staleDays }, or nil while it does not show. On WoW: Forever the site's item carries the activation's five
-- steps (Modules/Activation.lua), so there is one card, not two.
function Salao:Setup()
    local Ob = GuildOS.Onboarding
    local card = Ob and Ob.OfficerCard and Ob:OfficerCard(now())
    if not card then return nil end
    local act = GuildOS.Activation
    if act and act.Read then card.staleDays = act:Read(now()).staleDays end
    if card.celebrate then GuildOS:Print(L["The guild is set up. Well done!"]) end
    return card
end

-- The notice board: the next events still to start, { title, when, rsvp }, and the newest notice. The raids
-- the allied guilds opened to the alliance (guildos.me's, Alliance:OpenRaids) take their place in time among the
-- guild's own, { title, when, guild, going, size, allied = true }: read-only, signed up to on the site or Discord.
function Salao:Board()
    local events, cal = {}, GuildOS.Calendar
    local t = now()
    if cal and cal.GetUpcoming and GuildOS.db and GuildOS.db.calendar then
        for _, e in ipairs(cal:GetUpcoming(false)) do
            if (e.when or 0) > t then
                events[#events + 1] = { title = clean(e.title or "?"), when = e.when,
                                        rsvp = cal.MyRsvp and cal:MyRsvp(e) or nil }
                if #events >= MAX_BOARD then break end
            end
        end
    end
    local ally = GuildOS.Alliance
    for _, r in ipairs(ally and ally:OpenRaids(t) or {}) do
        if (r.when or 0) > t then
            events[#events + 1] = { title = clean(r.title or "?"), when = r.when, guild = r.guild,
                                    going = r.going, size = r.size, allied = true }
        end
    end
    table.sort(events, function(a, b)
        if a.when ~= b.when then return a.when < b.when end
        return (a.allied and 1 or 0) < (b.allied and 1 or 0)
    end)
    for i = #events, MAX_BOARD + 1, -1 do events[i] = nil end
    local A = UI.Agora
    return events, (A and A:Notices(MAX_NOTICES) or {})
end

-- By the fire: who is online now, this player left out, { name, full, class, classFile, zone, level, rank }; how
-- many that is; and how many are away (offline).
function Salao:Fireside()
    local out, me, total, away = {}, GuildOS.Compat.PlayerName(), 0, 0
    for i = 1, GetNumGuildMembers() or 0 do
        local full, rank, rankIndex, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if full and not online then away = away + 1 end
        if full and online and short(full) ~= me then
            total = total + 1
            if #out < MAX_FIRE then
                out[#out + 1] = { name = short(full), full = full, class = class, classFile = classFile, zone = zone,
                                  level = level, rank = rank, rankIndex = rankIndex }
            end
        end
    end
    return out, total, away
end

-- The Chimney while a Winter Veil event is on: { entrants, wrapped, opened, lit }. Counts only: who wrapped
-- stays the officers' (specs/winter-veil).
function Salao:Chimney()
    local WV = GuildOS.WinterVeil
    local e = WV and WV:Event()
    if not e then return nil end
    local c = type(e.counts) == "table" and e.counts or {}
    local entrants = math.max(0, math.floor(tonumber(c.entrants) or 0))
    return { entrants = entrants, wrapped = math.min(entrants, math.max(0, math.floor(tonumber(c.wrapped) or 0))),
             opened = math.max(0, math.floor(tonumber(c.opened) or 0)), lit = WV.PhaseOf(e) == "open" }
end

-- The Guild chat card's lines: the newest `max` of /g (the server's history where it keeps one, else the
-- addon's log), and for an officer the Officers channel where the server keeps it, each of those marked; oldest
-- first, so the newest is at the bottom. { name, class, ts, text, guild (an ally's line), officer }. Nil in a chat
-- lockdown, when nothing of the server's can be read (the card keeps what it shows).
local function byChatTime(a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    return a.at < b.at
end
-- `pool`: the caller's tables, filled again (the card draws at every line of /g; memoria.md).
function Salao:ChatLines(max, pool)
    local GC = GuildOS.GuildChat
    if not GC then return {} end
    if GC.Locked and GC:Locked() then return nil end
    local lines = {}
    local function add(list, officer)
        for _, e in ipairs(list or {}) do
            if type(e) == "table" and e.m then
                local n = #lines
                local l = pool and pool[n + 1] or {}
                if pool then pool[n + 1] = l end
                l.name, l.class, l.ts, l.text, l.guild = e.n, e.c, tonumber(e.t) or 0, tostring(e.m), e.g
                l.officer, l.at = officer or nil, n
                lines[n + 1] = l
            end
        end
    end
    max = max or CHAT_LINES
    -- The newest `max` of each: nothing older can be drawn (the server's history holds 200).
    add((GC:Entries(nil, max)))
    if GuildOS:IsOfficer() and GC.Streams then
        for _, st in ipairs(GC:Streams() or {}) do
            if type(st) == "table" and st.kind == "officer" then add((GC:Entries(st, max)), true) end
        end
    end
    table.sort(lines, byChatTime)
    if #lines > max then
        local cut = {}
        for i = #lines - max + 1, #lines do cut[#cut + 1] = lines[i] end
        lines = cut
    end
    return lines
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
    if not (R and R.Countdown and (R.LevelRows or R.GetReport)) then return nil end
    local t = now()
    if self._cdAt and t - self._cdAt < COUNTDOWN_S then return self._cd end
    -- The levels alone (Readiness:LevelRows): the countdown reads nothing else of the report.
    self._cdRows = self._cdRows or {}
    local ok, cd = GuildOS:SafeCall(function()
        return R:Countdown(R.LevelRows and R:LevelRows(self._cdRows) or R:GetReport(), t)
    end)
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

local function hex(h)
    return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
end

-- The coloured squares of For you and the glyphs of the wall, by the screen a line opens (the mockup's).
local TODO_COLOR = {
    trials = hex("6c2fb0"), management = hex("6f5a3c"), recruitment = hex("1d4f99"), guild = hex("1d4f99"),
    winterveil = hex("1f5a2a"), web = hex("a0560f"),
}
local URGENT = hex("8f1b0b")
local WALL_COLOR = {
    management = hex("3e8e41"), loot = hex("1d4f99"), roster = hex("b38a1a"), raids = hex("b0261b"),
}
-- A note's outline for this player's answer: going, maybe, not going (and standby, as maybe).
local ANSWER = {
    yes = hex("3e8e41"), tentative = hex("b37b12"), wait = hex("b37b12"), no = hex("8f1b0b"),
}
-- The answer as the note's line prints it: the paper's deep shades, the wood's own on the dark paper.
local ANSWER_INK = {
    yes = GuildOS:PaperInk("2f6e33", C.ok), tentative = GuildOS:PaperInk("8a5a00", C.warn),
    wait = GuildOS:PaperInk("8a5a00", C.warn), no = GuildOS:PaperInk("8f1b0b", C.danger),
}
local WALL_SIDE = GuildOS:PaperInk("8a6a3a", C.label)   -- a wall line's "when"

local function open(item)
    return function() UI:OpenWindow(item.id, item.sub, item.filter) end
end

-- This player's answer, as Calendar keeps it (Calendar.STATUS: yes, tentative, no; "wait" on a full raid).
local function rsvpOf(rsvp)
    local status = type(rsvp) == "table" and rsvp.status or nil
    if status == "yes" then return status, L["You are going"] end
    if status == "tentative" then return status, L["Maybe"] end
    if status == "no" then return status, L["Not going"] end
    if status == "wait" then return status, L["Standby"] end
    return nil, nil
end

-- The room and entry a line opens, as its small line ("Officers' Room · Trials").
local function whereOf(item)
    if not UI.RoomOf then return nil end
    local room, entry = UI:RoomOf(item.id, item.sub)
    -- A feature that lives in another's sub-tab (Trials in Recruitment) is found where it opens.
    local def = not room and UI.GetFeature and UI:GetFeature(item.id)
    if def and def.opens then room, entry = UI:RoomOf(def.opens[1], item.sub or def.opens[2]) end
    if not room then return nil end
    if entry and entry.label ~= room.label and #UI:RoomEntries(room.id) > 1 then
        return room.label .. " \194\183 " .. entry.label
    end
    return room.label
end

-- A countdown's line: its text, a side text at the right.
local function line(cardFrame, i)
    local r = cardFrame.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, cardFrame)
    r:SetHeight(ROW_H)
    r.main = text(r, 12, cardFrame.ink)
    r.main:SetPoint("LEFT", 0, 0)
    r.side = text(r, 11, cardFrame.soft)
    r.side:SetJustifyH("RIGHT")
    r.side:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function() if r.run then r.run() end end)
    cardFrame.rows[i] = r
    return r
end

local function fillLines(cardFrame, items, width)
    for _, r in ipairs(cardFrame.rows) do r:Hide() end
    local y = CARD_PAD + TITLE_H
    for i, item in ipairs(items) do
        local r = line(cardFrame, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", CARD_PAD, -y)
        r:SetWidth(width - 2 * CARD_PAD)
        r.main:SetText(item.text or "")
        r.side:SetText(item.side or "")
        r.main:SetWidth(math.max(40, width - 2 * CARD_PAD - math.ceil(r.side:GetStringWidth()) - 8))
        r.run = item.run
        r:Show()
        y = y + ROW_H
    end
    return y + CARD_PAD - 4
end

-- A For you line (the mockup's .todo): a coloured square with a number or a letter, the line and a smaller one
-- under it, a button at the right. A thin line of the paper's above every line but the first.
local function todo(cardFrame, i)
    local r = cardFrame.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, cardFrame)
    r:SetHeight(TODO_H)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    UI:Hairline(r.rule)
    r.rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
    r.rule:SetPoint("TOPLEFT", 0, 0)
    r.rule:SetPoint("TOPRIGHT", 0, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexture(GuildOS.Style.ART.card)
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("LEFT", 0, 0)
    r.mark = text(r, 12, { r = 1, g = 1, b = 1 }, "button")
    r.mark:SetJustifyH("CENTER")
    r.mark:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
    r.main = text(r, 13, cardFrame.ink)
    r.main:SetPoint("TOPLEFT", 40, -6)
    r.side = text(r, 11, cardFrame.soft)
    r.side:SetPoint("TOPLEFT", r.main, "BOTTOMLEFT", 0, -2)
    r.btn = UI:CreateButton(r, "", 70, 24)
    r.btn:SetPoint("RIGHT", 0, 0)
    r.btn:SetScript("OnClick", function() if r.run then r.run() end end)
    r:SetScript("OnClick", function() if r.run then r.run() end end)
    cardFrame.rows[i] = r
    return r
end

local function fillTodos(cardFrame, items, width)
    for _, r in ipairs(cardFrame.rows) do r:Hide() end
    local y = CARD_PAD + TITLE_H
    for i, item in ipairs(items) do
        local r = todo(cardFrame, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", CARD_PAD, -y)
        r:SetWidth(width - 2 * CARD_PAD)
        r.rule:SetShown(i > 1)
        local c = item.color or C.paperSoft
        r.icon:SetVertexColor(c.r, c.g, c.b, 1)
        r.icon:SetShown(item.mark ~= nil)
        r.mark:SetText(item.mark or "")
        r.main:ClearAllPoints()
        r.main:SetPoint(item.small and "TOPLEFT" or "LEFT", item.mark and 40 or 0, item.small and -6 or 0)
        r.main:SetText(item.text or "")
        r.side:SetText(item.small or "")
        r.side:SetShown(item.small ~= nil)
        r.run = item.run
        local right = 0
        if item.action then
            UI:SetButtonVariant(r.btn, item.primary and "primary" or "secondary")
            r.btn.label:SetText(item.action)
            r.btn:SetWidth(math.max(60, math.ceil(r.btn.label:GetStringWidth()) + 22))
            r.btn:Show()
            right = r.btn:GetWidth() + 10
        else
            r.btn:Hide()
        end
        local tw = math.max(40, width - 2 * CARD_PAD - (item.mark and 40 or 0) - right)
        r.main:SetWidth(tw)
        r.side:SetWidth(tw)
        r:SetHeight(item.small and TODO_H or 32)
        r:Show()
        y = y + r:GetHeight()
    end
    return y + CARD_PAD - 4
end

-- A pinned note (the mockup's .pinn): a cream note with a red pin, its title in the title serif and dark red,
-- when under it, and a line of meta; this player's answer outlines it green, amber or red.
local function note(cardFrame, i)
    local r = cardFrame.notes[i]
    if r then return r end
    r = CreateFrame("Button", nil, cardFrame)
    r:SetHeight(NOTE_H)
    local shade = GuildOS.Style:Nine(r, "shadow", 12, "BACKGROUND", 0, { -6, -5, -8, -10 })
    shade:SetRGBA(0, 0, 0, 0.25)
    local fill = GuildOS.Style:Nine(r, "card", 3, "BACKGROUND", 1)
    fill:SetColor(C.paperLight)
    r.outline = { GuildOS.Style:Nine(r, "card-line", 3, "BORDER", 0),
                  GuildOS.Style:Nine(r, "card-line", 3, "BORDER", 1, { 1, 1, 1, 1 }) }
    r.pin = GuildOS.Style:Texture(r, "orb", "OVERLAY", 1)
    r.pin:SetSize(11, 11)
    r.pin:SetPoint("CENTER", r, "TOP", 0, 0)
    r.pin:SetVertexColor(0.85, 0.2, 0.15, 1)
    r.main = text(r, 12, C.paperTitle, "sectionTitle")
    r.main:SetPoint("TOPLEFT", 10, -12)
    r.main:SetPoint("TOPRIGHT", -8, -12)
    r.side = text(r, 11, C.paperInk)
    r.side:SetPoint("TOPLEFT", r.main, "BOTTOMLEFT", 0, -4)
    r.side:SetPoint("TOPRIGHT", r.main, "BOTTOMRIGHT", 0, -4)
    r.meta = text(r, 11, C.paperSoft)
    r.meta:SetPoint("TOPLEFT", r.side, "BOTTOMLEFT", 0, -4)
    r.meta:SetPoint("TOPRIGHT", r.side, "BOTTOMRIGHT", 0, -4)
    r:SetScript("OnClick", function() if r.run then r.run() end end)
    cardFrame.notes[i] = r
    return r
end

-- By the fire's faces: a round avatar in the class's colours, the name in it under it, the zone smaller.
local function face(fire, i)
    local b = fire.faces[i]
    if b then return b end
    b = CreateFrame("Button", nil, fire)
    b:SetHeight(FACE_H)
    b.avatar = UI:CreateAvatar(b, AVATAR, true)
    b.avatar:SetPoint("TOP", 0, -2)
    b.avatar:EnableMouse(false)
    b.name = text(b, 12, C.text)
    b.name:SetJustifyH("CENTER")
    b.name:SetPoint("TOP", b.avatar, "BOTTOM", 0, -4)
    b.zone = text(b, UI.SP.META, C.textSoft)
    b.zone:SetJustifyH("CENTER")
    b.zone:SetPoint("TOP", b.name, "BOTTOM", 0, -1)
    b:SetScript("OnClick", function(self)
        if self.run then return self.run() end
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

-- A wall line (the mockup's .mi): a glyph in the colour of the screen it opens with the line's first letter,
-- the line, and when at the right.
local function wallLine(wall, i)
    local r = wall.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, wall)
    r:SetHeight(WALL_H)
    r.glyph = UI:CreateGlyph(r, GLYPH)
    r.glyph:SetPoint("LEFT", 0, 0)
    r.main = text(r, 12, wall.ink)
    r.main:SetPoint("LEFT", GLYPH + 9, 0)
    r.side = text(r, 11, WALL_SIDE)
    r.side:SetJustifyH("RIGHT")
    r.side:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function() if r.run then r.run() end end)
    wall.rows[i] = r
    return r
end

-- A line of the Guild chat card (the mockup's .chat .ln): a small round class avatar, the name in the class's
-- colour and the time softer beside it, the text under them. Pooled: the card repaints on every line of /g.
local function chatLine(chat, i)
    local r = chat.lines[i]
    if r then return r end
    r = CreateFrame("Frame", nil, chat.content)
    -- A link in the line opens as it does in the chat frame.
    r:EnableMouse(true)
    if r.SetHyperlinksEnabled then r:SetHyperlinksEnabled(true) end
    r:SetScript("OnHyperlinkClick", function(_, link, linkText, button)
        if SetItemRef then SetItemRef(link, linkText, button) end
    end)
    r.avatar = UI:CreateAvatar(r, CHAT_AV, false)
    r.avatar:SetPoint("TOPLEFT", 0, -1)
    r.avatar:EnableMouse(false)
    r.name = text(r, 12, C.text, "itemName")
    r.name:SetPoint("TOPLEFT", CHAT_AV + 8, 0)
    r.time = text(r, UI.SP.META, C.textSoft)
    r.time:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.body = text(r, 12, C.text)
    r.body:SetPoint("TOPLEFT", CHAT_AV + 8, -15)
    r.body:SetWordWrap(true)
    chat.lines[i] = r
    return r
end

-- A stocking of the Chimney (#449): a leg, a foot to the right and a white cuff, drawn, never a bare block.
-- stocking.color is its leg's colour (what the tests read); stocking:Paint(c) colours it, stocking:Place(x, y).
local function stocking(chimney, i)
    local sk = chimney.stockings[i]
    if sk then return sk end
    local WHITE = "Interface\\Buttons\\WHITE8x8"
    sk = chimney:CreateTexture(nil, "ARTWORK")
    sk:SetTexture(WHITE)
    sk:SetSize(10, 15)
    sk.foot = chimney:CreateTexture(nil, "ARTWORK")
    sk.foot:SetTexture(WHITE)
    sk.foot:SetSize(15, 7)
    sk.foot:SetPoint("TOPLEFT", sk, "BOTTOMLEFT", 0, 2)
    sk.cuff = chimney:CreateTexture(nil, "OVERLAY")
    sk.cuff:SetTexture(WHITE)
    sk.cuff:SetSize(12, 5)
    sk.cuff:SetPoint("BOTTOMLEFT", sk, "TOPLEFT", -1, -2)
    function sk:Paint(col, full)
        self:SetVertexColor(col.r, col.g, col.b, 1)
        self.foot:SetVertexColor(col.r, col.g, col.b, 1)
        local cuff = full and { r = 0.96, g = 0.93, b = 0.86 } or { r = 0.62, g = 0.52, b = 0.45 }
        self.cuff:SetVertexColor(cuff.r, cuff.g, cuff.b, 1)
    end
    function sk:Place(x, y)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", x + 1, -(y + 3))
    end
    function sk:SetAll(on)
        self:SetShown(on); self.foot:SetShown(on); self.cuff:SetShown(on)
    end
    chimney.stockings[i] = sk
    return sk
end

local GS_ROW, GS_SUB = 40, 22

function GuildOS:CreateSalaoPanel(panel)
    local scroll, content = UI:CreateScrollFrame(panel, "GuildOSSalaoScroll")
    scroll:SetAllPoints(panel)
    UI:BindScrollChildWidth(scroll, content)
    panel.scroll, panel.content = scroll, content

    local setup    = UI:CreateCard(content, L["Get started"], { link = L["Hide for 30 days"] })
    local forYou   = UI:CreateCard(content, L["For you"])
    local board    = UI:CreateCard(content, L["Notice board"], { link = L["Calendar"] })
    local chimney  = UI:CreateCard(content, L["The Chimney"], { dark = true })
    local fire     = UI:CreateCard(content, L["By the fire"], { dark = true, link = L["Members"] })
    local wall     = UI:CreateCard(content, L["Guild wall"], { link = L["Activity"] })
    local raidsIn  = UI:CreateCard(content, "", { dark = true })
    local chat     = UI:CreateCard(content, L["Guild chat"], { dark = true, link = L["Chat"] })
    for _, c in ipairs({ setup, forYou, board, chimney, fire, wall, raidsIn, chat }) do c.rows = {} end
    panel.cards = { setup = setup, forYou = forYou, board = board, chimney = chimney, fire = fire, wall = wall,
                    countdown = raidsIn, chat = chat }
    chat.link:SetScript("OnClick", open({ id = "guild", sub = "chat" }))
    board.link:SetScript("OnClick", open({ id = "guild", sub = "calendar" }))
    fire.link:SetScript("OnClick", open({ id = "roster" }))
    wall.link:SetScript("OnClick", open({ id = "guild", sub = "activity" }))

    -- The Chimney (the mockup's .chim): a deep red card, the bright metal round it.
    chimney.__look.fill:SetRGBA(0.357, 0.102, 0.071, 1)
    chimney.__look.line:SetColor(C.metal2)

    -- Get started: how far the guild got (a line and a bar), then each item with its tick, what counts, and
    -- Show me (a one-step tour) or Done; the site's item on WoW: Forever carries the activation's steps as pills.
    setup.items, setup.pills = {}, {}
    setup.meta = text(setup, UI.SP.META, C.paperSoft)
    setup.track = setup:CreateTexture(nil, "ARTWORK")
    setup.track:SetTexture("Interface\\Buttons\\WHITE8x8")
    setup.track:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
    setup.track:SetHeight(5)
    setup.bar = setup:CreateTexture(nil, "ARTWORK", nil, 1)
    setup.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
    setup.bar:SetVertexColor(0.608, 0.133, 0.086, 1)
    setup.bar:SetHeight(5)
    setup.line = text(setup, UI.SP.META, C.paperSoft)
    setup.line:SetWordWrap(true)
    local refresh
    setup.link:SetScript("OnClick", function()
        if GuildOS.Onboarding then GuildOS.Onboarding:HideOfficerCard(now()) end
        if refresh then GuildOS:SafeCall(refresh) end
    end)
    if UI.RegisterTourAnchor then
        UI:RegisterTourAnchor("salao.setup", setup)
        UI:RegisterTourAnchor("salao.foryou", forYou)
        UI:RegisterTourAnchor("salao.board", board)
        UI:RegisterTourAnchor("salao.fire", fire)
        UI:RegisterTourAnchor("salao.wall", wall)
        UI:RegisterTourAnchor("salao.chat", chat)
    end

    -- Start raid (#400), under the notes, while this player may lead the invites of the site's raid in its window:
    -- the same stepper the Web screen has. The raid's name over it when it is not the board's first event.
    local stepRoster, stepFor
    local start = UI.CreateRaidStepper and UI:CreateRaidStepper(board, { roster = function() return stepRoster end })
    local startFor = text(board, 11, C.paperSoft)
    if start then
        start:Hide()
        start.why:Hide()
        start.why:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    end
    startFor:Hide()
    panel.startRaid, panel.startFor = start, startFor

    -- The notice board: pinned notes, then the newest notices (MAX_NOTICES at most, newest first), each in a box
    -- of the paper's darker shade. The boxes are made once and kept, so a refresh never makes frames.
    board.notes = {}
    board.empty = text(board, 12, C.paperSoft)
    board.notices = {}
    for i = 1, MAX_NOTICES do
        local notice = CreateFrame("Button", nil, board)
        local noticeBg = GuildOS.Style:Nine(notice, "card", 5, "BACKGROUND", 1)
        noticeBg:SetColor(C.paperBox)
        notice.text = text(notice, 12, C.paperInk, "reading")
        notice.text:SetPoint("TOPLEFT", 10, -7)
        notice.text:SetPoint("TOPRIGHT", -10, -7)
        notice.text:SetWordWrap(true)
        notice:SetScript("OnClick", function() if notice.run then notice.run() end end)
        notice:Hide()
        board.notices[i] = notice
    end
    board.notice = board.notices[1]

    fire.faces = {}
    fire.more = text(fire, 12, C.textSoft)
    fire.away = face(fire, 0)
    -- "By the fire" read as a riddle to some (supporters' feedback): how many are online now at the title's right,
    -- and a tooltip on the title saying what the card is.
    fire.count = text(fire, UI.SP.META, C.textSoft)
    fire.count:SetPoint("RIGHT", fire.link, "LEFT", -8, 0)
    fire.title:SetPoint("RIGHT", fire.count, "LEFT", -6, 0)
    fire.hint = CreateFrame("Frame", nil, fire)
    fire.hint:SetPoint("TOPLEFT", fire.title, "TOPLEFT", 0, 2)
    fire.hint:SetPoint("BOTTOMRIGHT", fire.count, "BOTTOMRIGHT", 0, -2)
    UI:AddTooltip(fire.hint, L["By the fire"], {
        L["The guildmates online right now and the zone each one is in."],
        L["Click a face for that member's menu; Members opens the whole roster."] })

    -- The Chimney: one stocking per entrant, filled for each who wrapped.
    chimney.stockings = {}
    chimney.line = text(chimney, 12, { r = 0.949, g = 0.843, b = 0.690 })
    chimney.line:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_H - 4))

    -- The Guild chat (#449): the last lines of /g under the Notice board, newest at the bottom, a box to answer.
    -- The feed follows new lines while the reader is at its bottom, never pulling one who scrolled up.
    local cscroll, ccontent = UI:CreateScrollFrame(chat, nil)
    cscroll:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_H))
    cscroll:SetPoint("BOTTOMRIGHT", -(CARD_PAD - 4), CARD_PAD + CHAT_FIELD + 8)
    chat.scroll, chat.content, chat.lines = cscroll, ccontent, {}
    chat.empty = text(ccontent, 12, C.textSoft)
    chat.empty:SetPoint("TOPLEFT", 0, -4)
    chat.empty:SetWordWrap(true)
    local say = UI:CreateInput(chat, 200, CHAT_FIELD, { placeholder = L["Say to the guild…"] })
    say:SetMaxBytes(241)   -- what GuildChat:Send keeps (240 bytes), plus the terminator, as the Chat entry's box
    say:SetPoint("BOTTOMLEFT", CARD_PAD, CARD_PAD)
    say:SetPoint("BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
    chat.say = say
    -- Enter is the player's own key press, which chat needs on Forever. The text stays in a chat lockdown.
    say:SetScript("OnEnterPressed", function(self)
        local GC = GuildOS.GuildChat
        local msg = self:GetText() or ""
        if not GC or msg:gsub("%s", "") == "" then self:ClearFocus(); return end
        local ok, why = GC:Send(msg)
        if ok then
            self:SetText("")
            chat.follow = true
        elseif why == "locked" then
            GuildOS:Print(L["Chat is locked right now: your message is still in the box."])
        end
    end)

    -- Drawn again only when something changed: a line (GuildChat's version), the card's size or the day (the
    -- times say "Mon 21:04" past midnight). The 15 s refresh redrew 40 lines and read the server's history.
    local chatSig, chatPool = {}, {}
    local function fillChat(width, height)
        local GC = GuildOS.GuildChat
        local day = date and date("%Y%m%d", now()) or ""
        local version = GC and GC.version
        if version and chatSig.version == version and chatSig.w == width and chatSig.h == height
            and chatSig.day == day and not chat.follow then
            return
        end
        local lines = Salao:ChatLines(CHAT_LINES, chatPool)
        if not lines then return end       -- a chat lockdown: what is drawn stays
        local w = math.max(120, width - 2 * CARD_PAD - 14)
        ccontent:SetWidth(w)
        local range = cscroll.GetVerticalScrollRange and cscroll:GetVerticalScrollRange() or 0
        local follow = chat.follow or (cscroll:GetVerticalScroll() or 0) >= (range or 0) - 4
        chat.follow = nil
        local today = date and date("%Y%m%d", now()) or ""
        local y = 0
        for i, l in ipairs(lines) do
            local r = chatLine(chat, i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:SetWidth(w)
            r.avatar:SetMember(l.name or "?", l.class)
            local who = l.name or "?"
            if l.guild then who = "[" .. clean(l.guild) .. "] " .. who end
            -- An officer's line, in the Officers channel's green, says so.
            if l.officer then who = "|cff40c040" .. L["Officer"] .. "|r  " .. who end
            r.name:SetText(who)
            local cr, cg, cb = GuildOS:GetClassColor(l.class)
            r.name:SetTextColor(cr, cg, cb)
            r.time:SetText(l.ts > 0 and GuildOS:LocalDate((date and date("%Y%m%d", l.ts) == today) and "%H:%M" or "%a %H:%M", l.ts) or "")
            r.body:SetWidth(w - CHAT_AV - 8)
            r.body:SetText(l.text)
            local c = l.officer and OFFICER_GREEN or C.text
            r.body:SetTextColor(c.r, c.g, c.b)
            local h = math.max(CHAT_AV + 2, 15 + math.ceil(r.body:GetStringHeight() or 12))
            r:SetHeight(h)
            r:Show()
            y = y + h + 6
        end
        for i = #lines + 1, #chat.lines do chat.lines[i]:Hide() end
        chat.empty:SetShown(#lines == 0)
        if #lines == 0 then
            chat.empty:SetWidth(w)
            chat.empty:SetText(L["Nothing said in the guild chat yet."])
            y = 20
        end
        ccontent:SetHeight(math.max(1, y))
        chat.shownLines = lines
        chatSig.version, chatSig.w, chatSig.h, chatSig.day = version, width, height, day
        -- A frame later: the scroll range follows the new height only after it lands.
        if follow then
            local view = math.max(1, (height or 0) - (CARD_PAD + TITLE_H) - (CARD_PAD + CHAT_FIELD + 8))
            local target = math.max(0, y - view)
            GuildOS.Compat.After(0, function()
                if panel:IsVisible() then cscroll:SetVerticalScroll(target) end
            end)
        end
    end
    -- Live: a line of /g (GuildChat's own CHAT_MSG_GUILD) repaints the card, coalesced, while it shows.
    if GuildOS.GuildChat and GuildOS.GuildChat.OnRefresh then
        -- At the size the last layout gave the card (the refresh's), so a line and the refresh agree on it; one
        -- function for every line, not a closure each.
        -- 0.3 s after the first of a burst: one line of /g notifies twice (CHAT_MSG_GUILD, then the server's
        -- CLUB_MESSAGE_ADDED), and each drawing reads the server's history again.
        local pending = false
        local function repaintChat()
            pending = false
            if chat:IsVisible() then
                GuildOS:SafeCall(fillChat, chatSig.w or UI:LaidWidth(chat), chatSig.h or chat:GetHeight())
            end
        end
        GuildOS.GuildChat:OnRefresh(function()
            if pending or not chat:IsVisible() then return end
            pending = true
            GuildOS.Compat.After(0.3, repaintChat)
        end)
    end

    -- One item's row, made once and kept.
    local function gsRow(i)
        local r = setup.items[i]
        if r then return r end
        r = CreateFrame("Frame", nil, setup)
        r:SetHeight(GS_ROW)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetTexture("Interface\\Buttons\\WHITE8x8")
        UI:Hairline(r.rule)
        r.rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
        r.rule:SetPoint("TOPLEFT", 0, 0)
        r.rule:SetPoint("TOPRIGHT", 0, 0)
        r.tick = GuildOS.Style:Texture(r, "circle", "ARTWORK", 0)
        r.tick:SetSize(16, 16)
        r.tick:SetPoint("TOPLEFT", 0, -9)
        r.ring = GuildOS.Style:Texture(r, "ring", "ARTWORK", 1)
        r.ring:SetSize(18, 18)
        r.ring:SetPoint("CENTER", r.tick, "CENTER", 0, 0)
        r.main = text(r, 13, C.paperInk, "button")
        r.main:SetPoint("TOPLEFT", 26, -6)
        r.side = text(r, 11, C.paperSoft)
        r.side:SetPoint("TOPLEFT", r.main, "BOTTOMLEFT", 0, -2)
        r.btn = UI:CreateButton(r, L["Show me"], 70, 22)
        r.btn:SetPoint("TOPRIGHT", 0, -8)
        r.btn:SetScript("OnClick", function()
            local it = r.item
            if it and UI.Tour then UI.Tour:ShowMe(it.go, it.title, it.desc) end
        end)
        r.hand = UI:SetButtonVariant(UI:CreateButton(r, L["We promote by hand"], 90, 18), "ghost")
        r.hand:SetScript("OnClick", function()
            if GuildOS.Onboarding then GuildOS.Onboarding:PromoteByHand() end
            if refresh then GuildOS:SafeCall(refresh) end
        end)
        r.done = UI:CreateBadge(r, L["Done"], C.ok)
        r.done:SetPoint("TOPRIGHT", 0, -11)
        setup.items[i] = r
        return r
    end

    local function fillSetup(width)
        local st = Salao:Setup()
        for _, r in ipairs(setup.items) do r:Hide() end
        for _, p in ipairs(setup.pills) do p:Hide() end
        setup.meta:SetShown(st ~= nil)
        if not st then return 0 end
        local inner = width - 2 * CARD_PAD
        local y = CARD_PAD + TITLE_H
        setup.meta:SetText(string.format(L["%d of %d \194\183 for officers"], st.done, st.total))
        setup.meta:ClearAllPoints()
        setup.meta:SetPoint("TOPLEFT", CARD_PAD, -y)
        local mw = math.ceil(setup.meta:GetStringWidth() or 60)
        local barW = math.max(30, inner - mw - 12)
        setup.track:ClearAllPoints()
        setup.track:SetPoint("TOPLEFT", CARD_PAD + mw + 12, -(y + 5))
        setup.track:SetWidth(barW)
        setup.bar:ClearAllPoints()
        setup.bar:SetPoint("TOPLEFT", setup.track, "TOPLEFT", 0, 0)
        setup.bar:SetWidth(math.max(1, math.floor(barW * st.done / math.max(1, st.total))))
        setup.bar:SetShown(st.done > 0)
        y = y + 18
        local np = 0
        for i, it in ipairs(st.items) do
            local r = gsRow(i)
            r.item = it
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", CARD_PAD, -y)
            r:SetWidth(inner)
            r.rule:SetShown(i > 1)
            local c = it.done and C.ok or C.paperLine
            r.tick:SetVertexColor(c.r, c.g, c.b, it.done and 1 or 0.3)
            r.ring:SetVertexColor(c.r, c.g, c.b, 1)
            r.main:SetText(it.title)
            r.side:SetText(it.desc)
            r.btn:SetShown(not it.done)
            r.done:SetShown(it.done)
            r.btn:SetWidth(math.max(60, math.ceil(r.btn.label:GetStringWidth() or 50) + 20))
            local right = it.done and (r.done:GetWidth() + 8) or (r.btn:GetWidth() + 8)
            r.main:SetWidth(math.max(40, inner - 26 - right))
            r.side:SetWidth(math.max(40, inner - 26 - right))
            local h = GS_ROW
            -- The ranks' second way to be done.
            r.hand:SetShown(it.byHand and not it.done or false)
            if r.hand:IsShown() then
                r.hand:SetWidth(math.ceil(r.hand.label:GetStringWidth() or 80) + 4)
                r.hand:ClearAllPoints()
                r.hand:SetPoint("TOPLEFT", r, "TOPLEFT", 26, -(GS_ROW - 2))
                h = h + 16
            end
            -- The activation's steps (WoW: Forever) as pills, green when done.
            if it.sub then
                local x, py = 26, h - 4
                for _, stp in ipairs(it.sub) do
                    np = np + 1
                    local p = setup.pills[np]
                    if not p then
                        p = CreateFrame("Frame", nil, setup)
                        p:SetHeight(18)
                        p.fill = GuildOS.Style:Three(p, "pill", "BACKGROUND", 1)
                        p.label = text(p, 11, C.paperSoft)
                        p.label:SetPoint("CENTER", 0, 0)
                        setup.pills[np] = p
                    end
                    p:SetParent(r)
                    p.label:SetText((stp.done and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t " or "") .. stp.label)
                    local pw = math.ceil(p.label:GetStringWidth() or 40) + 14
                    if x + pw > inner and x > 26 then x, py = 26, py + GS_SUB end
                    p:SetWidth(pw)
                    if stp.done then
                        p.fill:SetRGBA(0.184, 0.431, 0.2, 1)
                        p.label:SetTextColor(1, 1, 1)
                    else
                        p.fill:SetRGBA(C.paperShade.r, C.paperShade.g, C.paperShade.b, 1)
                        p.label:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
                    end
                    p:ClearAllPoints()
                    p:SetPoint("TOPLEFT", r, "TOPLEFT", x, -py)
                    p:Show()
                    x = x + pw + 4
                end
                h = py + GS_SUB + 2
            end
            r:SetHeight(h)
            r:Show()
            y = y + h
        end
        local msg
        if st.all then msg = L["All done. This card leaves the Hall tomorrow; it stays in Settings \226\128\186 Help."]
        elseif st.staleDays then msg = string.format(L["Checked %d days ago."], st.staleDays) end
        setup.line:SetShown(msg ~= nil)
        if msg then
            setup.line:SetText(msg)
            setup.line:ClearAllPoints()
            setup.line:SetPoint("TOPLEFT", CARD_PAD, -(y + 6))
            setup.line:SetWidth(inner)
            y = y + 6 + math.ceil(setup.line:GetStringHeight() or 14)
        end
        return y + CARD_PAD
    end

    local function fillBoard(width, events, bulletins)
        for _, n in ipairs(board.notes) do n:Hide() end
        local y = CARD_PAD + TITLE_H + 6
        local inner = width - 2 * CARD_PAD
        local perRow = inner >= 300 and 3 or (inner >= 190 and 2 or 1)
        local noteW = math.floor((inner - (perRow - 1) * NOTE_GAP) / perRow)
        for i, e in ipairs(events) do
            local n = note(board, i)
            local col, rowI = (i - 1) % perRow, math.floor((i - 1) / perRow)
            n:ClearAllPoints()
            n:SetPoint("TOPLEFT", CARD_PAD + col * (noteW + NOTE_GAP), -(y + rowI * (NOTE_H + NOTE_GAP)))
            n:SetWidth(noteW)
            GuildOS:SetTitleText(n.main, e.title)
            n.side:SetText(e.when)
            n.meta:SetText(e.meta or "")
            local oc = e.answer and ANSWER[e.answer]
            for _, o in ipairs(n.outline) do
                o:SetShown(oc ~= nil)
                if oc then o:SetColor(oc) end
            end
            local mc = (e.answer and ANSWER_INK[e.answer]) or C.paperSoft
            n.meta:SetTextColor(mc.r, mc.g, mc.b)
            n.run = e.run
            n:Show()
        end
        local rows = math.ceil(#events / perRow)
        if #events == 0 then
            board.empty:SetText(L["Nothing on the calendar yet."])
            board.empty:ClearAllPoints()
            board.empty:SetPoint("TOPLEFT", CARD_PAD, -y)
            board.empty:Show()
            y = y + 22
        else
            board.empty:Hide()
            y = y + rows * (NOTE_H + NOTE_GAP)
        end
        for i, notice in ipairs(board.notices) do
            local bulletin = bulletins and bulletins[i]
            if bulletin then
                notice:ClearAllPoints()
                notice:SetPoint("TOPLEFT", CARD_PAD, -y)
                notice:SetWidth(inner)
                notice.text:SetText(bulletin.text or "")
                notice:SetHeight(math.max(28, (notice.text:GetStringHeight() or 14) + 14))
                notice.run = open(bulletin)
                notice:Show()
                y = y + notice:GetHeight() + 8
            else
                notice.run = nil
                notice:Hide()
            end
        end
        return y + CARD_PAD - 8
    end

    local function fillFire(width)
        local list, total, awayN = Salao:Fireside()
        fire.count:SetText(string.format(L["online now \194\183 %d"], total))
        for _, b in ipairs(fire.faces) do b:Hide() end
        local perRow = 4
        local cellW = math.floor((width - 2 * CARD_PAD) / perRow)
        local y = CARD_PAD + TITLE_H
        local cells = #list + 1
        for i = 1, cells do
            local b = (i <= #list) and face(fire, i) or fire.away
            local col, rowI = (i - 1) % perRow, math.floor((i - 1) / perRow)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", CARD_PAD + col * cellW, -(y + rowI * FACE_H))
            b:SetWidth(cellW)
            b.name:SetWidth(cellW - 4)
            b.zone:SetWidth(cellW - 4)
            if i <= #list then
                local m = list[i]
                b.member, b.run = m, nil
                b.avatar:SetMember(m.name, m.classFile)
                local cc = m.classFile and GuildOS.ClassColors[m.classFile] or C.text
                b.name:SetText(m.name)
                b.name:SetTextColor(cc.r, cc.g, cc.b)
                b.zone:SetText(clean(m.zone or ""))
            else
                -- The "+n" disc: who else is online past the faces, or else who is away; it opens the members.
                local moreOnline = total - #list
                b.member, b.run = nil, open({ id = "roster" })
                b.avatar:SetCount(moreOnline > 0 and moreOnline or awayN)
                b.name:SetText(moreOnline > 0 and L["online"] or L["away"])
                b.name:SetTextColor(C.text.r, C.text.g, C.text.b)
                b.zone:SetText("")
            end
            b:Show()
        end
        y = y + math.ceil(cells / perRow) * FACE_H
        fire.more:ClearAllPoints()
        fire.more:SetPoint("TOPLEFT", CARD_PAD, -y)
        if #list == 0 then
            fire.more:SetText(L["Nobody else is online right now."])
            fire.more:Show()
            y = y + 20
        else
            fire.more:SetText("")
            fire.more:Hide()
        end
        return y + CARD_PAD - 6
    end

    local function fillWall(width)
        for _, r in ipairs(wall.rows) do r:Hide() end
        local A = UI.Agora
        local items = A and A:Activity(MAX_WALL) or {}
        local y = CARD_PAD + TITLE_H
        if #items == 0 then
            local r = wallLine(wall, 1)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", CARD_PAD, -y)
            r:SetWidth(width - 2 * CARD_PAD)
            r.glyph:Hide()
            r.main:SetText(L["Nothing new in the guild yet."])
            r.side:SetText("")
            r.run = nil
            r:Show()
            return y + WALL_H + CARD_PAD - 4
        end
        for i, a in ipairs(items) do
            local r = wallLine(wall, i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", CARD_PAD, -y)
            r:SetWidth(width - 2 * CARD_PAD)
            r.glyph:Show()
            local plain = tostring(a.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            r.glyph:Set(UI.Initial(plain), WALL_COLOR[a.id] or C.paperSoft)
            r.main:SetText(a.text)
            r.side:SetText(GuildOS:TimeAgo(a.ts))
            r.main:SetWidth(math.max(40, width - 2 * CARD_PAD - GLYPH - 9 - math.ceil(r.side:GetStringWidth()) - 8))
            r.run = open(a)
            r:Show()
            y = y + WALL_H
        end
        return y + CARD_PAD - 4
    end

    local function fillChimney(width)
        local c = Salao:Chimney()
        for _, sk in ipairs(chimney.stockings) do sk:SetAll(false) end
        if not c then return 0 end
        GuildOS:SetTitleText(chimney.title, c.lit and L["The Chimney is lit"] or L["The Chimney"])
        local y0 = CARD_PAD + TITLE_H + 16
        -- Nobody has entered yet: said, not a row of nothing.
        if c.entrants == 0 then
            chimney.line:SetText(L["No stockings yet: they hang here as the guild joins the Secret Santa."])
            chimney.line:SetWordWrap(true)
            chimney.line:SetWidth(width - 2 * CARD_PAD)
            return y0 + 4 + CARD_PAD - 4
        end
        chimney.line:SetWordWrap(false)
        chimney.line:SetWidth(width - 2 * CARD_PAD)
        chimney.line:SetText(c.lit and string.format(L["%d of %d globes opened"], math.min(c.opened, c.entrants), c.entrants)
            or string.format(L["%d of %d entrants wrapped their globe"], c.wrapped, c.entrants))
        local w, h, gap = 16, 22, 6
        local perRow = math.max(1, math.floor((width - 2 * CARD_PAD + gap) / (w + gap)))
        for i = 1, c.entrants do
            local sk = stocking(chimney, i)
            local full = c.lit or i <= c.wrapped
            sk:Paint(full and C.danger or { r = 0.45, g = 0.27, b = 0.22 }, full)
            local cx, cy = (i - 1) % perRow, math.floor((i - 1) / perRow)
            sk:Place(CARD_PAD + cx * (w + gap), y0 + cy * (h + 6))
            sk:SetAll(true)
        end
        return y0 + math.ceil(c.entrants / perRow) * (h + 6) + CARD_PAD - 4
    end

    refresh = function()
        local w = UI:LaidWidth(content) or 0
        if w <= 1 then w = (panel:GetWidth() or 0) - (UI.SCROLL_GUTTER or 0) end
        if w <= 1 then return end
        content:SetWidth(w)
        local two = w >= TWO_COLUMNS
        local leftW = two and math.floor((w - GUTTER) * LEFT_SHARE) or w
        local rightW = two and (w - GUTTER - leftW) or w

        local hSetup = fillSetup(leftW)

        -- For you
        local items = {}
        for i, it in ipairs(Salao:ForYou()) do
            local mark = it.mark or (it.count and tostring(it.count)) or (it.id == "guild" and "?") or UI.Initial(it.text)
            items[#items + 1] = { text = it.text, small = it.small or whereOf(it), action = it.action, run = open(it), mark = mark,
                                  color = it.gettingStarted and URGENT or it.urgent and URGENT or TODO_COLOR[it.id] or C.paperSoft,
                                  primary = i == 1 }
        end
        if #items == 0 then items[1] = { text = L["All caught up."] } end
        local hYou = fillTodos(forYou, items, leftW)

        -- Notice board
        local events, bulletins = Salao:Board()
        local notes = {}
        for _, e in ipairs(events) do
            local when = GuildOS:LocalDate(L["%a %d %b, %H:%M"], e.when)
            if e.allied then
                -- An allied guild's raid: its guild in the meta line with the count; it opens the Salão's Alliance,
                -- where it says that signing up is on the site or in Discord.
                local count = e.size and string.format(" \194\183 %d/%d", e.going or 0, e.size) or ""
                notes[#notes + 1] = { title = e.title, when = when, meta = "[" .. clean(e.guild or "?") .. "]" .. count,
                                      run = open({ id = "alliance", sub = "hall" }) }
            else
                local answer, said = rsvpOf(e.rsvp)
                notes[#notes + 1] = { title = e.title, when = when, meta = said, answer = answer,
                                      run = open({ id = "guild", sub = "calendar", filter = e.when }) }
            end
        end
        board.items = notes
        local hBoard = fillBoard(leftW, notes, bulletins)
        local A0 = UI.Agora
        stepRoster, stepFor = nil, nil
        if A0 and start then stepRoster, stepFor = A0:StartRaid(A0:NextRaid()) end
        local stepping = start ~= nil and stepRoster ~= nil
        startFor:SetShown(stepping and stepFor ~= nil)
        if start then start:SetShown(stepping); start.why:SetShown(stepping) end
        if stepping then
            local y = hBoard - CARD_PAD + 4
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

        local hWall = fillWall(rightW)

        local hCount = 0
        local cd = Salao:Countdown()
        if cd then
            local title, lines = Salao:CountdownLines(cd)
            raidsIn.title:SetText(title)
            hCount = fillLines(raidsIn, lines, rightW)
        else
            fillLines(raidsIn, {}, rightW)
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
        -- 2px in, so the paper's shadow is not cut at the scroll area's edge.
        local yl = place(setup, 0, 2, leftW, hSetup)
        yl = place(forYou, 0, yl, leftW, hYou)
        yl = place(board, 0, yl, leftW, hBoard)
        -- The Guild chat under the board: in two columns as tall as the rest of the view (or of the right column,
        -- when that is taller), at least CHAT_MIN; in one column a fixed height, the right column under it.
        local hChat = CHAT_STACKED
        local yc = yl
        if two then
            local yr0 = 2 + (hCount > 0 and hCount + GUTTER or 0) + (hChimney > 0 and hChimney + GUTTER or 0)
                + hFire + GUTTER + hWall
            local view = UI:LaidWidth(panel) > 0 and (panel:GetHeight() or 0) or 0
            hChat = math.max(CHAT_MIN, math.max(yr0, view - 10) - yc)
        end
        yl = place(chat, 0, yc, leftW, hChat)
        GuildOS:SafeCall(fillChat, leftW, hChat)
        local xr, yr = two and (leftW + GUTTER) or 0, two and 2 or yl
        yr = place(raidsIn, xr, yr, rightW, hCount)
        yr = place(chimney, xr, yr, rightW, hChimney)
        yr = place(fire, xr, yr, rightW, hFire)
        yr = place(wall, xr, yr, rightW, hWall)
        content:SetHeight(math.max(yl, yr) + 8)
    end
    panel.Refresh = refresh

    panel:SetScript("OnShow", function()
        chat.follow = true
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
