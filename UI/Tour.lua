----------------------------------------------------------------------
-- Guild OS - The guided tour (specs/salao/onboarding.md)
--
-- One step at a time over the window: the window dimmed but for a hole round the frame the step is about,
-- a gold ring round that hole, and a parchment callout beside it (below, above or beside; docked to the
-- window's bottom at the watch band) that says what it is, with Back, Next and Skip. The tour opens the room
-- and the entry of each step itself. A step's frame comes from UI:TourAnchor(key): the screens register
-- theirs with UI:RegisterTourAnchor(key, frame | function); a key "prefix.rest" falls back to the function
-- registered under "prefix" (the window's doors, pills and side bar). A step whose frame cannot be found is
-- skipped; a "picture" step has none and shows its picture in the callout instead.
--
-- Never over a fight: combat hides it and it comes back on the same step when combat ends. The window closed
-- pauses it, and the footer offers to resume. Enter or Right: next; Left: back; Escape: skip.
-- Everything is built once and reused (tools/frame-leaks.lua). The placement is a pure function
-- (Tour.Place) and the rectangle of a frame is Tour.RectOf, so tools/tour.lua tests both without a client.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local L = GuildOS.L

local Tour = {}
UI.Tour = Tour

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CALLOUT_W = 320        -- the callout's width: it grows in height, never in width
local MARGIN    = 8          -- the callout never comes nearer the window's edge
local GAP       = 14         -- the hole to the callout
local HOLE_PAD  = 5          -- the hole round the frame
local NARROW_W  = 600        -- under this window width the callout docks to the bottom (the watch band, 452)
local TOP_SAFE  = 56         -- docked at the top, under the title bar
local FOOT_SAFE = 30         -- docked at the bottom, over the footer
local PAD       = 14
local ILL_H     = 96
local DIM_A     = 0.62
local MAX_SKIP  = 40

----------------------------------------------------------------------
-- Anchors
----------------------------------------------------------------------
local anchors = {}
Tour.anchors = anchors

-- `target`: a frame, or a function returning one (given the rest of the key after its prefix).
function UI:RegisterTourAnchor(key, target)
    if type(key) == "string" and target ~= nil then anchors[key] = target end
    return target
end

local function usable(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    if not f:IsVisible() then return false end
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    return w > 0 and h > 0
end
Tour.Usable = usable

-- The frame registered for `key`, while it is on screen; nil otherwise.
function UI:TourAnchor(key)
    if type(key) ~= "string" then return nil end
    local t = anchors[key]
    local f
    if type(t) == "function" then
        local ok, r = pcall(t)
        f = ok and r or nil
    else
        f = t
    end
    if not usable(f) then
        f = nil
        local prefix, rest = key:match("^([^.]+)%.(.+)$")
        local fn = prefix and anchors[prefix]
        if type(fn) == "function" then
            local ok, r = pcall(fn, rest)
            if ok and usable(r) then f = r end
        end
    end
    return f
end

-- The first of `keys` on screen, and its key.
function Tour.Resolve(keys)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
        local f = UI:TourAnchor(k)
        if f then return f, k end
    end
    return nil
end

----------------------------------------------------------------------
-- Geometry (pure)
----------------------------------------------------------------------
-- A frame's rectangle in the window's space, y down from its top-left: { x, y, w, h }, or nil when the
-- client cannot say yet. Replaced in the render harness by its own resolver.
function Tour.RectOf(fr, win)
    if not (fr and win and fr.GetLeft and win.GetLeft) then return nil end
    local l, t = fr:GetLeft(), fr:GetTop()
    local wl, wt = win:GetLeft(), win:GetTop()
    if not (l and t and wl and wt) then return nil end
    local fs = fr.GetEffectiveScale and fr:GetEffectiveScale() or 1
    local ws = win.GetEffectiveScale and win:GetEffectiveScale() or 1
    local k = fs / ws
    return { x = l * k - wl, y = wt - t * k, w = (fr:GetWidth() or 0) * k, h = (fr:GetHeight() or 0) * k }
end

local function clamp(v, lo, hi) if hi < lo then return lo end return math.max(lo, math.min(hi, v)) end

-- Where the callout goes in a window `ww` x `wh` for the hole round `r` (nil: no frame, centred), the
-- callout `ch` tall: x, y, width, side ("below" | "above" | "beside" | "center" | "bottom" | "top").
-- Narrow windows dock it across the bottom, or the top when the frame is in the lower half.
function Tour.Place(ww, wh, r, ch, narrow)
    if narrow then
        local w = math.max(120, ww - 2 * MARGIN)
        if r and (r.y + r.h / 2) > wh / 2 then
            return MARGIN, TOP_SAFE, w, "top"
        end
        return MARGIN, math.max(TOP_SAFE, wh - FOOT_SAFE - ch), w, "bottom"
    end
    local cw = math.min(CALLOUT_W, ww - 2 * MARGIN)
    if not r then
        return math.floor((ww - cw) / 2), math.floor(clamp((wh - ch) / 2, MARGIN, wh - ch - MARGIN)), cw, "center"
    end
    local hx, hy, hw, hh = r.x - HOLE_PAD, r.y - HOLE_PAD, r.w + 2 * HOLE_PAD, r.h + 2 * HOLE_PAD
    local cx = clamp(hx + hw / 2 - cw / 2, MARGIN, ww - cw - MARGIN)
    local cy, side
    if hy + hh + GAP + ch <= wh - MARGIN then
        cy, side = hy + hh + GAP, "below"
    elseif hy - GAP - ch >= MARGIN then
        cy, side = hy - GAP - ch, "above"
    else
        side = "beside"
        if hx + hw + GAP + cw <= ww - MARGIN then cx = hx + hw + GAP
        elseif hx - GAP - cw >= MARGIN then cx = hx - GAP - cw
        else cx = clamp(cx, MARGIN, ww - cw - MARGIN) end
        cy = clamp(hy + hh / 2 - ch / 2, MARGIN, wh - ch - MARGIN)
    end
    return math.floor(cx), math.floor(cy), cw, side
end
Tour.CALLOUT_W, Tour.NARROW_W = CALLOUT_W, NARROW_W

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
-- mode: "tour" (a track), "one" (a single step: Getting started's Show me) or "end" (the tour's last card).
Tour.state = {}

local function O() return GuildOS.Onboarding end
local function window() return UI.GetMainWindow and UI:GetMainWindow() or nil end

function Tour:Running() return self.state.mode ~= nil end
function Tour:Paused() return self.state.mode ~= nil and self.state.paused ~= nil end

-- What the window's footer offers: { text, run } or nil.
function Tour:FooterOffer()
    local s = self.state
    if s.mode == "tour" and s.paused == "closed" then
        return { text = L["Resume the tour"], run = function() Tour:Resume() end }
    end
    if s.offerStart then
        return { text = L["Tour: 2 min"], run = function() s.offerStart = nil; Tour:Start("member") end }
    end
    return nil
end

-- What's new closed with Later: the footer offers the tour for the rest of the session.
function Tour:OfferStart() self.state.offerStart = true; self:RefreshFooter() end

function Tour:RefreshFooter()
    local f = GuildOS.RosterFrame
    if f and f.RefreshTourOffer then GuildOS:SafeCall(f.RefreshTourOffer, f) end
end

----------------------------------------------------------------------
-- Frames (built once)
----------------------------------------------------------------------
local C, P
local function inks()
    local Kit = rawget(GuildOS, "Kit")
    C = GuildOS.Colors
    P = Kit and Kit.PAPER or C
end

local function newText(parent, size, color, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function textH(fs)
    local h = tonumber(fs.GetStringHeight and fs:GetStringHeight()) or 0
    return h > 0 and math.ceil(h) or 14
end

local function build(win)
    inks()
    local ov = CreateFrame("Frame", "GuildOSTour", win)
    ov:SetAllPoints(win)
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(120)
    ov:Hide()

    -- The dim: four mouse-catching frames round the hole, so only the frame in it takes a click.
    ov.dims = {}
    for i = 1, 4 do
        local d = CreateFrame("Frame", nil, ov)
        d:EnableMouse(true)
        d:SetFrameLevel(ov:GetFrameLevel() + 1)
        local t = d:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(WHITE)
        t:SetAllPoints()
        t:SetVertexColor(0, 0, 0, DIM_A)
        d.tex = t
        ov.dims[i] = d
    end

    -- The gold ring round the hole, and a soft glow under it.
    local ring = CreateFrame("Frame", nil, ov)
    ring:SetFrameLevel(ov:GetFrameLevel() + 2)
    ring.glow = GuildOS.Style:Nine(ring, "card-line", 9, "BACKGROUND", 0, { -3, -3, -3, -3 })
    ring.glow:SetRGBA(C.gold2.r, C.gold2.g, C.gold2.b, 0.35)
    ring.line = GuildOS.Style:Nine(ring, "card-line", 8, "BORDER", 0)
    ring.line:SetColor(C.gold2)
    ring.line2 = GuildOS.Style:Nine(ring, "card-line", 8, "BORDER", 1, { 1, 1, 1, 1 })
    ring.line2:SetColor(C.gold2)
    ring:Hide()
    ov.ring = ring

    -- The callout: a parchment card.
    local co = CreateFrame("Frame", nil, ov, "BackdropTemplate")
    co:SetFrameLevel(ov:GetFrameLevel() + 5)
    GuildOS.Style:Paint(co, "paper")
    co:EnableMouse(true)
    co:SetSize(CALLOUT_W, 160)
    ov.co = co

    co.head = newText(co, UI.SP.META, P.textSoft)
    co.head:SetWordWrap(false)
    co.count = newText(co, UI.SP.META, P.textSoft, "tableNum")
    co.count:SetJustifyH("RIGHT")
    co.count:SetWordWrap(false)
    co.dots = {}
    co.pic = CreateFrame("Frame", nil, co)
    co.pic:SetHeight(ILL_H)
    co.title = newText(co, UI.SP.TITLE, P.paperTitle or C.paperTitle, "sectionTitle")
    co.title:SetWordWrap(true)
    co.body = newText(co, UI.SP.BODY, P.paperInk or C.paperInk, "reading")
    co.body:SetWordWrap(true)
    co.note = newText(co, UI.SP.META, P.warn or C.warn)
    co.note:SetWordWrap(true)
    co.noteIcon = GuildOS.Style:Texture(co, "mark-warn", "ARTWORK", 0)
    co.noteIcon:SetSize(14, 14)
    co.keys = newText(co, UI.SP.META, P.textSoft)
    co.keys:SetWordWrap(true)

    co.skip = UI:SetButtonVariant(UI:CreateButton(co, L["Skip tour"], 60, UI.SP.HIT), "ghost")
    co.back = UI:CreateButton(co, L["Back"], 60, UI.SP.HIT)
    co.next = UI:SetButtonVariant(UI:CreateButton(co, L["Next"], 60, UI.SP.HIT), "primary")
    co.skip:SetScript("OnClick", function() Tour:Skip() end)
    co.back:SetScript("OnClick", function() Tour:Back() end)
    co.next:SetScript("OnClick", function() Tour:Next() end)

    -- Keys: Enter / Right next, Left back, Escape skip; every other key goes on to the game.
    co:EnableKeyboard(true)
    co:SetScript("OnKeyDown", function(self, key)
        local mine = key == "ENTER" or key == "RIGHT" or key == "LEFT" or key == "ESCAPE"
        if self.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
            self:SetPropagateKeyboardInput(not mine)
        end
        if not mine then return end
        if key == "ESCAPE" then Tour:Skip()
        elseif key == "LEFT" then Tour:Back()
        else Tour:Next() end
    end)

    -- Combat hides it; the same step comes back when combat ends.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then Tour:CombatStarted() else Tour:CombatEnded() end
    end)
    ov.events = ev

    -- The window closed pauses it.
    win:HookScript("OnHide", function() Tour:WindowClosed() end)
    win:HookScript("OnSizeChanged", function() if Tour.state.mode and not Tour.state.paused then Tour:Repaint() end end)
    return ov
end

function Tour:Frame()
    local win = window()
    if not win then return nil end
    if not self.overlay or self.overlay.win ~= win then
        self.overlay = build(win)
        self.overlay.win = win
    end
    return self.overlay
end

----------------------------------------------------------------------
-- Drawing a step
----------------------------------------------------------------------
local function setDots(co, n, on)
    for i = 1, math.max(n, #co.dots) do
        local d = co.dots[i]
        if not d and i <= n then
            d = co:CreateTexture(nil, "ARTWORK")
            d:SetTexture(WHITE)
            d:SetHeight(4)
            co.dots[i] = d
        end
        if d then
            d:SetShown(i <= n)
            local c = (i <= on) and (P.paperTitle or C.paperTitle) or (C.paperLine or C.line)
            d:SetVertexColor(c.r, c.g, c.b, 1)
        end
    end
end

local function fitButton(b, min)
    b:SetWidth(math.max(min or 50, math.ceil(tonumber(b.label:GetStringWidth()) or 40) + 24))
end

-- Fill the callout for `view` = { head, count, dots = { n, on }, title, body, note, ill, skip, back, next,
-- keys } at width `cw`; returns its height.
local function fill(co, view, cw)
    co:SetWidth(cw)
    local inner = cw - 2 * PAD
    co.head:SetText(view.head or "")
    co.count:SetText(view.count or "")
    co.count:ClearAllPoints()
    co.count:SetPoint("TOPRIGHT", co, "TOPRIGHT", -PAD, -PAD)
    co.head:ClearAllPoints()
    co.head:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -PAD)
    co.head:SetWidth(math.max(20, inner - math.ceil(tonumber(co.count:GetStringWidth()) or 30) - 8))
    local y = PAD + 14 + 6
    local nd, on = view.dots and view.dots[1] or 0, view.dots and view.dots[2] or 0
    setDots(co, nd, on)
    if nd > 0 then
        local dw = math.floor((inner - (nd - 1) * 4) / nd)
        for i = 1, nd do
            co.dots[i]:ClearAllPoints()
            co.dots[i]:SetPoint("TOPLEFT", co, "TOPLEFT", PAD + (i - 1) * (dw + 4), -y)
            co.dots[i]:SetWidth(math.max(4, dw))
        end
        y = y + 4 + 10
    end
    co.pic:SetShown(view.ill ~= nil)
    if view.ill and UI.Picture then
        co.pic:ClearAllPoints()
        co.pic:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -y)
        co.pic:SetSize(inner, ILL_H)
        UI.Picture:Draw(co.pic, view.ill, inner, ILL_H)
        y = y + ILL_H + 10
    end
    co.title:SetText(view.title or "")
    co.title:SetWidth(inner)
    co.title:ClearAllPoints()
    co.title:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -y)
    y = y + textH(co.title) + 6
    co.body:SetText(view.body or "")
    co.body:SetWidth(inner)
    co.body:ClearAllPoints()
    co.body:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -y)
    y = y + textH(co.body)
    local hasNote = view.note ~= nil and view.note ~= ""
    co.note:SetShown(hasNote)
    co.noteIcon:SetShown(hasNote)
    if hasNote then
        y = y + 8
        co.noteIcon:ClearAllPoints()
        co.noteIcon:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -y)
        co.note:SetText(view.note)
        co.note:SetWidth(inner - 20)
        co.note:ClearAllPoints()
        co.note:SetPoint("TOPLEFT", co, "TOPLEFT", PAD + 20, -(y + 1))
        y = y + math.max(14, textH(co.note))
    end
    y = y + 12
    -- The buttons: Skip at the left, Back and Next at the right.
    co.skip.label:SetText(view.skip or "")
    co.skip:SetShown((view.skip or "") ~= "")
    fitButton(co.skip, 30)
    co.back.label:SetText(view.back or "")
    co.back:SetShown((view.back or "") ~= "")
    fitButton(co.back)
    co.next.label:SetText(view.next or L["Next"])
    fitButton(co.next, 70)
    co.skip:ClearAllPoints()
    co.skip:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -(y + 3))
    co.next:ClearAllPoints()
    co.next:SetPoint("TOPRIGHT", co, "TOPRIGHT", -PAD, -y)
    co.back:ClearAllPoints()
    co.back:SetPoint("RIGHT", co.next, "LEFT", -8, 0)
    -- Buttons that do not fit beside Skip go under it.
    local used = (co.skip:IsShown() and (co.skip:GetWidth() + 12) or 0) + co.next:GetWidth()
        + (co.back:IsShown() and (co.back:GetWidth() + 8) or 0)
    if used > inner and co.skip:IsShown() then
        co.skip:ClearAllPoints()
        co.skip:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -(y + UI.SP.HIT + 8 + 3))
        y = y + UI.SP.HIT + 8
    end
    y = y + UI.SP.HIT
    co.keys:SetShown((view.keys or "") ~= "")
    if co.keys:IsShown() then
        y = y + 8
        co.keys:SetText(view.keys)
        co.keys:SetWidth(inner)
        co.keys:ClearAllPoints()
        co.keys:SetPoint("TOPLEFT", co, "TOPLEFT", PAD, -y)
        y = y + textH(co.keys)
    end
    y = y + PAD
    co:SetHeight(y)
    return y
end
Tour.Fill = fill

-- The dims round the hole `h` = { x, y, w, h } (nil: the whole window dimmed) in a window ww x wh.
local function dims(ov, ww, wh, h)
    local d = ov.dims
    local function put(f, x, y, w, hh)
        f:ClearAllPoints()
        if w <= 0 or hh <= 0 then f:Hide(); return end
        f:SetPoint("TOPLEFT", ov, "TOPLEFT", x, -y)
        f:SetSize(w, hh)
        f:Show()
    end
    if not h then
        put(d[1], 0, 0, ww, wh)
        for i = 2, 4 do d[i]:Hide() end
        return
    end
    local x0, y0 = math.max(0, h.x), math.max(0, h.y)
    local x1, y1 = math.min(ww, h.x + h.w), math.min(wh, h.y + h.h)
    put(d[1], 0, 0, ww, y0)                    -- above
    put(d[2], 0, y1, ww, wh - y1)              -- below
    put(d[3], 0, y0, x0, y1 - y0)              -- left
    put(d[4], x1, y0, ww - x1, y1 - y0)        -- right
end

-- A frame inside a scroll area brought into view.
local function scrollIntoView(fr)
    local p, child = fr:GetParent(), fr
    local depth = 0
    while p and depth < 12 do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" and p.GetVerticalScrollRange and p.SetVerticalScroll then
            local top, bottom, ct = fr:GetTop(), fr:GetBottom(), child:GetTop()
            local sTop, sBottom = p:GetTop(), p:GetBottom()
            if top and bottom and ct and sTop and sBottom and (top > sTop or bottom < sBottom) then
                local range = p:GetVerticalScrollRange() or 0
                p:SetVerticalScroll(clamp((ct - top) - 8, 0, range))
            end
            return
        end
        child, p = p, p:GetParent()
        depth = depth + 1
    end
end

-- Lay the overlay out for the current view.
function Tour:Repaint()
    local s = self.state
    local ov = self.overlay
    if not (ov and s.view) then return end
    local win = ov.win
    local ww, wh = win:GetWidth() or 0, win:GetHeight() or 0
    local narrow = ww < NARROW_W
    local r
    if s.anchorFrame then
        GuildOS:SafeCall(scrollIntoView, s.anchorFrame)
        r = self.RectOf(s.anchorFrame, win)
        -- Still out of the window (a scroll area that could not bring it in): no hole, the callout centred.
        if r and (r.y >= wh or r.y + r.h <= 0 or r.x >= ww or r.x + r.w <= 0) then r = nil end
    end
    local cwWanted = narrow and (ww - 2 * MARGIN) or math.min(CALLOUT_W, ww - 2 * MARGIN)
    local ch = fill(ov.co, s.view, cwWanted)
    local x, y, cw, side = self.Place(ww, wh, r, ch, narrow)
    if cw ~= cwWanted then ch = fill(ov.co, s.view, cw) end
    ov.co:ClearAllPoints()
    ov.co:SetPoint("TOPLEFT", ov, "TOPLEFT", x, -y)
    local hole = r and { x = r.x - HOLE_PAD, y = r.y - HOLE_PAD, w = r.w + 2 * HOLE_PAD, h = r.h + 2 * HOLE_PAD } or nil
    dims(ov, ww, wh, hole)
    ov.ring:SetShown(hole ~= nil)
    if hole then
        ov.ring:ClearAllPoints()
        ov.ring:SetPoint("TOPLEFT", ov, "TOPLEFT", hole.x, -hole.y)
        ov.ring:SetSize(math.max(1, hole.w), math.max(1, hole.h))
    end
    s.placed = { x = x, y = y, w = cw, h = ch, side = side, hole = hole, ww = ww, wh = wh }
end

----------------------------------------------------------------------
-- Moving through a track
----------------------------------------------------------------------
-- Open the room and entry a step is on (the window on screen, unfolded).
local function openFor(roomId, entryId)
    local f = window()
    if not f then return false end
    if not f:IsShown() then f:Show() end
    if f.band == "bar" and f.ToggleCollapsed then f:ToggleCollapsed() end
    if f.searchOpen and f.CloseSearch then f:CloseSearch() end
    if not roomId then return true end
    if entryId then
        for _, e in ipairs(UI:RoomEntries(roomId)) do
            if e.id == entryId then
                if f.activeRoom == roomId and f.activeEntry and f.activeEntry.id == entryId then return true end
                return f:SelectEntry(roomId, e, false)
            end
        end
    end
    if f.activeRoom == roomId then return true end
    return f:OpenRoom(roomId, false)
end
Tour.OpenFor = openFor

local function viewFor(s)
    local step = s.steps[s.i]
    local O_ = O()
    local track = O_.TRACKS[s.track]
    local chapters = O_:Chapters(s.track, s.steps)
    local cIndex, inCh, iCh, chObj = 1, 0, 0, nil
    for ci, c in ipairs(chapters) do
        if c.id == step.ch then cIndex, chObj = ci, c end
    end
    if chObj then inCh, iCh = chObj.count, s.i - chObj.first + 1 end
    local last = s.i == #s.steps
    local lastInCh = iCh == inCh
    return {
        head = (track and track.label or "") .. " \194\183 " .. (chObj and chObj.label or ""),
        count = string.format("%d / %d", s.i, #s.steps),
        dots = { inCh, iCh },
        title = step.title, body = step.body, note = step.note,
        ill = step.ill,
        skip = L["Skip tour"],
        back = s.i > 1 and L["Back"] or nil,
        next = last and L["Finish"] or (lastInCh and L["Next chapter"] or L["Next"]),
        keys = string.format(L["Enter next \194\183 Esc skip \194\183 chapter %d of %d"], cIndex, #chapters),
    }
end

-- Show step `i`, skipping in direction `dir` past the ones whose frame is not there.
function Tour:Show(i, dir)
    local s = self.state
    dir = dir or 1
    local tries = 0
    while s.steps[i] and tries < MAX_SKIP do
        tries = tries + 1
        local step = s.steps[i]
        openFor(step.room, step.entry)
        local fr = Tour.Resolve(step.anchor)
        if fr or step.picture then
            s.i = i
            s.anchorFrame = fr
            s.view = viewFor(s)
            if s.mode == "tour" then O():Reached(s.track, i, s.steps) end
            local ov = self:Frame()
            if not ov then return false end
            ov:Show()
            self:Repaint()
            -- Laid out once more next frame: a screen just opened sizes its cards a frame later.
            GuildOS.Compat.After(0, function() if Tour.state == s and s.i == i and s.mode then Tour:Repaint() end end)
            return true
        end
        i = i + dir
    end
    -- Nothing left that way: past the end the tour is done, before the start it stays where it was.
    if dir > 0 then return self:Finish() end
    return false
end

-- Start `track` (at chapter `ch`, else where it was left). Returns whether it started.
function Tour:Start(track, ch)
    local O_ = O()
    if not (O_ and O_.TRACKS[track]) then return false end
    if not O_:TrackAllowed(track) then return false end
    local steps = O_:Steps(track)
    if #steps == 0 then
        GuildOS:Print(L["This tour has nothing to show on this client."])
        return false
    end
    self:Stop()
    local s = { mode = "tour", track = track, steps = steps, i = O_:StartIndex(track, steps, ch) }
    self.state = s
    if GuildOS:InCombat() then
        s.paused = "combat"
        return true
    end
    if not window() then self.state = {}; return false end
    local ok = self:Show(s.i, 1)
    self:RefreshFooter()
    return ok ~= false
end

-- One step on its own (Getting started's "Show me", a guide's): go = { room, entry, anchor }, with the
-- title and the text.
function Tour:ShowMe(go, title, body, ill)
    self:Stop()
    if GuildOS:InCombat() then return false end
    local s = { mode = "one", go = go }
    self.state = s
    if go.run then GuildOS:SafeCall(go.run) end
    openFor(go.room, go.entry)
    s.anchorFrame = go.anchor and Tour.Resolve(go.anchor) or nil
    s.view = {
        head = L["Get started"], count = L["Show me"], title = title,
        body = body and (body .. ". " .. L["It ticks itself in the card once it's true."]) or nil,
        ill = (not s.anchorFrame) and ill or nil,
        skip = L["Back to the list"], next = L["Got it"],
    }
    local ov = self:Frame()
    if not ov then self.state = {}; return false end
    ov:Show()
    self:Repaint()
    GuildOS.Compat.After(0, function() if Tour.state == s then Tour:Repaint() end end)
    return true
end

function Tour:Next()
    local s = self.state
    if s.mode == "one" then return self:Stop() end
    if s.mode == "end" then return self:EndAction() end
    if s.mode ~= "tour" then return end
    if s.i >= #s.steps then return self:Finish() end
    return self:Show(s.i + 1, 1)
end

function Tour:Back()
    local s = self.state
    if s.mode ~= "tour" or s.i <= 1 then return end
    self:Show(s.i - 1, -1)
end

-- Skip (Escape, the link): the tour stops where it is, to resume from "?"; Getting started goes back to its list.
function Tour:Skip()
    local s = self.state
    local mode = s.mode
    if mode == "one" then
        self:Stop()
        local f = window()
        if f and O():Role() == "member" then
            for _, e in ipairs(UI:RoomEntries("settings")) do if e.id == "help" then f:SelectEntry("settings", e, true) end end
        elseif f then
            f:OpenRoom("salao", true)
        end
        return
    end
    self:Stop()
    if mode == "tour" or mode == "end" then
        local f = window()
        if f then
            for _, e in ipairs(UI:RoomEntries("settings")) do if e.id == "help" then f:SelectEntry("settings", e, true) end end
        end
    end
end

-- The last step done: the track finished and its card, with what comes next.
function Tour:Finish()
    local s = self.state
    local O_ = O()
    O_:Finished(s.track)
    s.mode, s.anchorFrame = "end", nil
    local role = O_.Role()
    local nextTrack
    if s.track == "member" and role ~= "member" then nextTrack = "officer"
    elseif s.track == "officer" and role == "gm" then nextTrack = "gm" end
    s.nextTrack = nextTrack
    local label = O_.TRACKS[s.track].label
    local body = string.format(L["That's the %s. Replay it, or any chapter, from ? > Tours."], label)
    if nextTrack == "officer" then body = body .. " " .. L["There is an Officers' Room tour too."] end
    s.view = {
        head = label, count = L["Done"], title = L["Tour complete"], body = body,
        ill = s.track == "member" and "salao" or (s.track == "gm" and "gm" or "officers"),
        back = L["Done"],
        next = nextTrack == "officer" and O_.TRACKS.officer.label or (nextTrack == "gm" and O_.TRACKS.gm.label or L["Getting started"]),
    }
    local ov = self:Frame()
    if not ov then return false end
    ov:Show()
    self:Repaint()
    return true
end

-- The end card's main button: the next track, or Getting started.
function Tour:EndAction()
    local s = self.state
    local nextTrack = s.nextTrack
    self:Stop()
    if nextTrack then return self:Start(nextTrack) end
    local O_ = O()
    local f = window()
    if not f then return end
    if O_.Role() == "member" then
        for _, e in ipairs(UI:RoomEntries("settings")) do if e.id == "help" then f:SelectEntry("settings", e, true) end end
    else
        f:OpenRoom("salao", true)
    end
end

function Tour:Stop()
    local s = self.state
    self.state = { offerStart = s.offerStart }
    if self.overlay then self.overlay:Hide() end
    self:RefreshFooter()
end

-- Back to the step where it paused (combat, or the window closed).
function Tour:Resume()
    local s = self.state
    if not s.mode then return false end
    if GuildOS:InCombat() then s.paused = "combat"; return false end
    s.paused = nil
    self:RefreshFooter()
    if s.mode == "tour" then return self:Show(s.i or 1, 1) end
    local ov = self:Frame()
    if ov then ov:Show(); self:Repaint() end
    return true
end

function Tour:CombatStarted()
    local s = self.state
    if not s.mode then return end
    if not s.paused then s.paused = "combat" end
    if self.overlay then self.overlay:Hide() end
end

function Tour:CombatEnded()
    local s = self.state
    if s.mode and s.paused == "combat" then
        local f = window()
        -- A window the player closed during the fight stays closed; the footer offers to resume.
        if f and not f:IsShown() then
            if s.mode == "tour" then s.paused = "closed" else self.state = { offerStart = s.offerStart } end
            return self:RefreshFooter()
        end
        self:Resume()
    end
end

function Tour:WindowClosed()
    local s = self.state
    if not s.mode then return end
    if s.mode == "one" or s.mode == "end" then return self:Stop() end
    if s.paused ~= "combat" then s.paused = "closed" end
    if self.overlay then self.overlay:Hide() end
end
