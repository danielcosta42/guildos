----------------------------------------------------------------------
-- Guild OS - Winter Veil's snow (issue guildos-web#662, the site's specs/121)
-- Before the cutoff: a small panel of falling snow in a corner of the window, and its tooltip is the teaser for the
-- Secret Santa. From the cutoff to the end of December: snow over the whole Guild OS window. Never over the game's
-- own interface: the layers are children of the window and clip to it. Nothing here reads the guild's data.
-- The date is the client's clock (time()); the cutoff is the one constant below.
-- Cheap by design: at most MAX_FLAKES textures, one OnUpdate moving them every STEP seconds, and no OnUpdate at all
-- while the window is closed. The corner also holds a parcel on the ground and Frimm's cap, which peeks up on hover
-- (the site's specs/122): flat colour textures and one short Translation, no OnUpdate.
-- The `snow` option is shown as "Winter Veil animations": it also stops the embers and rays of the Winter Veil tab
-- (UI/VeilFx.lua). The saved key stays `snow`.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local L = GuildOS.L

local Snow = {}
GuildOS.Snow = Snow
UI.Snow = Snow

-- 2026-12-01 00:00 in São Paulo (UTC-3, no daylight saving) and 2027-01-01 00:00 there: the one place the dates live.
Snow.CUTOFF_AT = 1796094000
Snow.END_AT = 1798772400
Snow.MAX_FLAKES = 20
Snow.STEP = 0.05
local TEASER_W, TEASER_H = 72, 72
local TEASER_FLAKES = 8
-- The teaser stands on the window's footer, left of the sync line (`footRight`), where nothing else is: the footer
-- keeps that width free of its welcome (`footReserve`, UI/Window.lua). Only the parcel and Frimm's cap take the mouse; the snow over them
-- lets every click through to what is under it.
local GIFT_GAP = 6

local function clock() return time() end

-- "teaser" before the cutoff, "season" from it to the end of December, "off" after. The `snow` option can only turn
-- the snow off; unset it is on.
function Snow:Phase(t)
    t = t or clock()
    if t < self.CUTOFF_AT then return "teaser" end
    if t < self.END_AT then return "season" end
    return "off"
end

function Snow:Enabled()
    return GuildOS:GetSetting("snow") ~= false
end

-- What shows now: "teaser", "season" or nil.
function Snow:Mode(t)
    local p = self:Phase(t)
    if p == "off" or not self:Enabled() then return nil end
    return p
end

----------------------------------------------------------------------
-- Flakes
----------------------------------------------------------------------
local function respawn(fl, w, h, anywhere)
    fl.x = math.random() * w
    fl.y = anywhere and (math.random() * h) or 0
    fl.speed = 14 + math.random() * 22
    fl.drift = (math.random() - 0.5) * 10
    fl.size = 2 + math.floor(math.random() * 3)
end

local function place(fl, frame)
    fl.tex:ClearAllPoints()
    fl.tex:SetPoint("TOPLEFT", frame, "TOPLEFT", fl.x, -fl.y)
    fl.tex:SetSize(fl.size, fl.size)
end

-- A layer: a frame holding up to `count` flakes, moved in steps of STEP.
local function newLayer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)
    frame.flakes = {}
    frame:Hide()
    return frame
end

function Snow:Fill(layer, count)
    count = math.min(count, self.MAX_FLAKES)
    local w, h = layer:GetWidth() or 0, layer:GetHeight() or 0
    if w < 1 or h < 1 then w, h = 100, 100 end
    for i = #layer.flakes + 1, count do
        local tex = layer:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 0.55 + math.random() * 0.35)
        local fl = { tex = tex }
        respawn(fl, w, h, true)
        layer.flakes[i] = fl
    end
    for i, fl in ipairs(layer.flakes) do
        fl.tex:SetShown(i <= count)
        if i <= count then place(fl, layer) end
    end
    layer.count = count
end

-- Advance every flake by `dt`; the caller has already limited how often.
function Snow:Step(layer, dt)
    local w, h = layer:GetWidth() or 0, layer:GetHeight() or 0
    if w < 1 or h < 1 then return end
    for i = 1, layer.count or 0 do
        local fl = layer.flakes[i]
        fl.y = fl.y + fl.speed * dt
        fl.x = fl.x + fl.drift * dt
        if fl.y > h or fl.x < -4 or fl.x > w then
            respawn(fl, w, h, false)
            fl.y = -fl.size
        end
        place(fl, layer)
    end
end

local function startLayer(self, layer)
    layer.acc = 0
    layer.running = true
    layer:SetScript("OnUpdate", function(f, elapsed)
        f.acc = f.acc + elapsed
        if f.acc < self.STEP then return end
        local dt = f.acc
        f.acc = 0
        self:Step(f, dt)
    end)
end

local function stopLayer(layer)
    layer.running = false
    layer:SetScript("OnUpdate", nil)
    layer:Hide()
end

-- Flakes in motion now (for the Winter Veil tab's ceiling of textures in motion, UI/VeilFx.lua).
function Snow:Moving()
    local n = 0
    for _, layer in ipairs({ self.full, self.corner }) do
        if layer and layer.running then n = n + (layer.count or 0) end
    end
    return n
end

----------------------------------------------------------------------
-- The corner's parcel and Frimm's cap: colour blocks. The cap rises 22 px on hover and sinks back on leave.
----------------------------------------------------------------------
local HAT_X, HAT_LOW, HAT_RISE = 40, -16, 22
local PARCEL_X, PARCEL_W, HAT_W = 24, 24, 22
-- The width of the corner that takes the mouse (the parcel's left edge to the cap's right edge), and what lies right of it.
Snow.MOUSE_W = HAT_X + HAT_W - PARCEL_X
Snow.MOUSE_RIGHT = TEASER_W - (HAT_X + HAT_W)
local MOUSE_RIGHT = Snow.MOUSE_RIGHT

local function block(parent, layer, r, g, b, w, h, x, y)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, 1)
    t:SetSize(w, h)
    t:SetPoint("BOTTOMLEFT", x, y)
    return t
end

local function buildCorner(box)
    -- The parcel: red, a gold band and a gold loop on top.
    local parcel = CreateFrame("Frame", nil, box)
    parcel:SetSize(PARCEL_W, 26)
    parcel:SetPoint("BOTTOMLEFT", PARCEL_X, 2)
    block(parcel, "ARTWORK", 0.72, 0.263, 0.227, 24, 20, 0, 0)
    block(parcel, "OVERLAY", 0.851, 0.663, 0.31, 4, 20, 10, 0)
    block(parcel, "OVERLAY", 0.851, 0.663, 0.31, 12, 2, 6, 24)
    block(parcel, "OVERLAY", 0.851, 0.663, 0.31, 2, 5, 6, 20)
    block(parcel, "OVERLAY", 0.851, 0.663, 0.31, 2, 5, 16, 20)
    -- The cap: a red cone leaning right, a white brim and a pompom.
    local hat = CreateFrame("Frame", nil, box)
    hat:SetSize(HAT_W, 26)
    hat:SetPoint("BOTTOMLEFT", HAT_X, HAT_LOW)
    block(hat, "ARTWORK", 0.72, 0.263, 0.227, 17, 8, 2, 4)
    block(hat, "ARTWORK", 0.72, 0.263, 0.227, 12, 7, 6, 12)
    block(hat, "ARTWORK", 0.72, 0.263, 0.227, 7, 5, 11, 19)
    block(hat, "OVERLAY", 0.953, 0.918, 0.851, 21, 5, 0, 0)
    block(hat, "OVERLAY", 1, 1, 1, 5, 5, 17, 21)
    local function slide(dy, over)
        local ag = hat:CreateAnimationGroup()
        local a = ag:CreateAnimation("Translation")
        a:SetOffset(0, dy + over)
        a:SetDuration(0.25)
        a:SetSmoothing("OUT")
        if over ~= 0 then
            local b = ag:CreateAnimation("Translation")
            b:SetOffset(0, -over)
            b:SetDuration(0.1)
            b:SetOrder(2)
        end
        return ag
    end
    local up, down = slide(HAT_RISE, 4), slide(-HAT_RISE, 0)
    local function rest(y) hat:ClearAllPoints(); hat:SetPoint("BOTTOMLEFT", HAT_X, y) end
    up:SetScript("OnFinished", function() rest(HAT_LOW + HAT_RISE) end)
    down:SetScript("OnFinished", function() rest(HAT_LOW) end)
    box.parcel, box.hat = parcel, hat
    function box:RaiseHat(on)
        if on == self.hatUp then return end
        self.hatUp = on
        up:Stop(); down:Stop()
        if on then rest(HAT_LOW); up:Play() else rest(HAT_LOW + HAT_RISE); down:Play() end
    end
    box:HookScript("OnHide", function() up:Stop(); down:Stop(); box.hatUp = false; rest(HAT_LOW) end)
end

----------------------------------------------------------------------
-- The window's two layers: the whole-window snow and the corner teaser.
----------------------------------------------------------------------
function Snow:Teaser()
    return L["Someone is wrapping something for the guild. Keep an eye out. — Frimm"]
end

-- Called when the window shows, and when the option changes.
function Snow:Refresh()
    local win = self.window
    if not win then return end
    local mode = win:IsShown() and self:Mode() or nil
    if mode == "season" then
        local layer = self.full
        layer:ClearAllPoints()
        layer:SetAllPoints(win)
        layer:SetFrameLevel(win:GetFrameLevel() + 50)
        self:Fill(layer, self.MAX_FLAKES)
        layer:Show()
        startLayer(self, layer)
    elseif self.full then
        stopLayer(self.full)
    end
    if mode == "teaser" then
        -- The parcel and the cap stand on the footer, GIFT_GAP left of the sync line (the footer is 24 px high: the
        -- box's floor is its floor); the window's footer keeps their width free of its welcome.
        local box = self.corner
        box:ClearAllPoints()
        if win.footRight then
            box:SetPoint("BOTTOMRIGHT", win.footRight, "LEFT", MOUSE_RIGHT - GIFT_GAP - 13, -12)
        else
            box:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 30)
        end
        box:SetSize(TEASER_W, TEASER_H)
        box:SetFrameLevel(win:GetFrameLevel() + 50)
        self:Fill(box, TEASER_FLAKES)
        box:Show()
        startLayer(self, box)
    elseif self.corner then
        stopLayer(self.corner)
    end
    local reserve = mode == "teaser" and win.footRight and (self.MOUSE_W + 2 * GIFT_GAP) or 0
    if win.footReserve ~= reserve then
        win.footReserve = reserve
        if win.LayoutFooter then win:LayoutFooter() end
    end
end

-- Hang the snow on the window (once).
function Snow:Attach(win)
    if self.window then return end
    self.window = win
    self.full = newLayer(win)
    self.full:EnableMouse(false)
    self.corner = newLayer(win)
    -- Only the parcel and the cap take the mouse: the rest of the corner lets clicks through to the window.
    self.corner:EnableMouse(false)
    buildCorner(self.corner)
    local box = self.corner
    for _, part in ipairs({ box.parcel, box.hat }) do
        part:EnableMouse(true)
        part:SetScript("OnEnter", function(f)
            box:RaiseHat(true)
            GameTooltip:SetOwner(f, "ANCHOR_LEFT")
            GameTooltip:SetText(Snow:Teaser(), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        part:SetScript("OnLeave", function()
            box:RaiseHat(false)
            GameTooltip:Hide()
        end)
    end
    win:HookScript("OnShow", function() Snow:Refresh() end)
    win:HookScript("OnHide", function() Snow:Refresh() end)
    self:Refresh()
end

function Snow:SetEnabled(on)
    GuildOS:SetSetting("snow", on and true or false)
    self:Refresh()
    if GuildOS.VeilFx then GuildOS.VeilFx.OptionChanged() end
end
