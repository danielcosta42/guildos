----------------------------------------------------------------------
-- Guild OS - Winter Veil's snow (issue guildos-web#662, the site's specs/121)
-- Before the cutoff: a small panel of falling snow in a corner of the window, and its tooltip is the teaser for the
-- Secret Santa. From the cutoff to the end of December: snow over the whole Guild OS window. Never over the game's
-- own interface: the layers are children of the window and clip to it. Nothing here reads the guild's data.
-- The date is the client's clock (time()); the cutoff is the one constant below.
-- Cheap by design: at most MAX_FLAKES textures, one OnUpdate moving them every STEP seconds, and no OnUpdate at all
-- while the window is closed.
----------------------------------------------------------------------
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
    layer:SetScript("OnUpdate", function(f, elapsed)
        f.acc = f.acc + elapsed
        if f.acc < self.STEP then return end
        local dt = f.acc
        f.acc = 0
        self:Step(f, dt)
    end)
end

local function stopLayer(layer)
    layer:SetScript("OnUpdate", nil)
    layer:Hide()
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
        local box = self.corner
        box:ClearAllPoints()
        box:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 30)
        box:SetSize(TEASER_W, TEASER_H)
        box:SetFrameLevel(win:GetFrameLevel() + 50)
        self:Fill(box, TEASER_FLAKES)
        box:Show()
        startLayer(self, box)
    elseif self.corner then
        stopLayer(self.corner)
    end
end

-- Hang the snow on the window (once).
function Snow:Attach(win)
    if self.window then return end
    self.window = win
    self.full = newLayer(win)
    self.full:EnableMouse(false)
    self.corner = newLayer(win)
    self.corner:EnableMouse(true)
    self.corner:SetScript("OnEnter", function(box)
        GameTooltip:SetOwner(box, "ANCHOR_LEFT")
        GameTooltip:SetText(Snow:Teaser(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.corner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win:HookScript("OnShow", function() Snow:Refresh() end)
    win:HookScript("OnHide", function() Snow:Refresh() end)
    self:Refresh()
end

function Snow:SetEnabled(on)
    GuildOS:SetSetting("snow", on and true or false)
    self:Refresh()
end
