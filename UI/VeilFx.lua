----------------------------------------------------------------------
-- Guild OS - Winter Veil's effects (guildos-web#673, the site's specs/122 addon.md)
-- The one place that knows the art: the files under Media/Veil and Media/Globes, the veil-fx atlas's layout, the
-- rarity colours, the sounds. And the one place that moves anything on the Winter Veil tab: the fire's flipbook (one
-- OnUpdate at 10 Hz for both flames) and every AnimationGroup, created once and counted against a ceiling of
-- BUDGET textures in motion. Nothing here runs with the tab hidden or with the option off: each scope (a tab's root
-- frame) stops all of its groups, its flipbook and its timers on OnHide, and Play refuses while the root is not
-- visible, while the `snow` option ("Winter Veil animations") is off, or past the ceiling.
-- Everything is a child of the Guild OS window and clipped by it: no effect ever reaches the game's own interface.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Fx = {}
GuildOS.VeilFx = Fx

local MEDIA = "Interface\\AddOns\\GuildOS\\Media\\"
Fx.PATH = {
    atlas = MEDIA .. "Veil\\veil-fx",          -- 512x512, layout below
    cold = MEDIA .. "Veil\\chimney-cold",      -- 256x512, the Chimney with snow
    hot = MEDIA .. "Veil\\chimney-hot",        -- 256x512, the same in embers, shown from the bottom up by a clip
    frimm = MEDIA .. "Veil\\frimm",            -- 512x128, three faces (+1 spare)
    giftbox = MEDIA .. "Veil\\giftbox",        -- 128x128, the wrapped globe: a gift box, ribbon and bow on
    giftbox256 = MEDIA .. "Veil\\giftbox-256", -- 256x256
    giftOpen = MEDIA .. "Veil\\giftbox-open",  -- the same box, the lid off beside it
    giftOpen256 = MEDIA .. "Veil\\giftbox-open-256",
    globes = MEDIA .. "Globes\\",              -- <scene>-<rarity> and closed, 128x128 with alpha
    globes256 = MEDIA .. "Globes\\256\\",      -- the same at 256x256 (closed-256 sits beside them in Globes\)
}

Fx.BUDGET = 64       -- textures in motion at most, the tab open (addon.md "Desempenho")
Fx.FIRE_STEP = 0.1   -- the flipbook's 10 Hz
Fx.FIRE_FRAMES = 8
Fx.FIRE_BACK_AHEAD = 3 -- the back flame plays the same frames, mirrored and 3 ahead

----------------------------------------------------------------------
-- The veil-fx atlas (512x512). Rows 1-2: the fire, 8 frames of 128 (4x2). Row 3: the shaking snow, 4 frames of 128.
-- Row 4: rays 128, ring 128, flash 128, smoke 64, star 32, ember 32, flake 32, ribbon 32, bow 128x64. White pieces,
-- tinted with SetVertexColor. Pixel rectangles { x, y, w, h }.
----------------------------------------------------------------------
Fx.ATLAS = 512
Fx.PIECES = {
    rays = { 0, 384, 128, 128 },
    ring = { 128, 384, 128, 128 },
    flash = { 256, 384, 128, 128 },
    smoke = { 384, 384, 64, 64 },
    star = { 448, 384, 32, 32 },
    ember = { 480, 384, 32, 32 },
    flake = { 448, 416, 32, 32 },
    ribbon = { 480, 416, 32, 32 },
    bow = { 384, 448, 128, 64 },
}

local function rect(x, y, w, h)
    local s = Fx.ATLAS
    return x / s, (x + w) / s, y / s, (y + h) / s
end

-- left, right, top, bottom of a piece.
function Fx.Coords(name)
    local p = Fx.PIECES[name]
    return rect(p[1], p[2], p[3], p[4])
end

-- A fire frame, 1..8 (wraps).
function Fx.FireCoords(i)
    i = (i - 1) % Fx.FIRE_FRAMES
    return rect((i % 4) * 128, math.floor(i / 4) * 128, 128, 128)
end

-- A frame of the shaking snow, 1..4.
function Fx.SnowCoords(i)
    i = (i - 1) % 4
    return rect(i * 128, 256, 128, 128)
end

-- The Chimney's art: the drawing is 256x428, against the bottom of its 256x512 file (84 px clear on top).
Fx.CHIMNEY_W, Fx.CHIMNEY_H = 256, 428
Fx.CHIMNEY_TOP = 84 / 512
-- The texture coordinates of the bottom `h` pixels of the drawing (h = 428 is all of it).
function Fx.ChimneyCoords(h)
    return 0, 1, 1 - h / 512, 1
end

-- Frimm's faces in his 512x128 file.
Fx.FACES = { rush = 0, happy = 1, oops = 2 }
function Fx.FaceCoords(face)
    local i = Fx.FACES[face] or 0
    return i * 0.25, (i + 1) * 0.25, 0, 1
end

----------------------------------------------------------------------
-- Rarities: the text colour, the frame's colour and the base each one is (wood, silver, gold, crystal).
----------------------------------------------------------------------
local function hex(h)
    return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 }
end
Fx.hex = hex
Fx.RARITY_ORDER = { "common", "rare", "epic", "legendary" }
Fx.RARITY = {
    common = { step = 0, text = hex("e8eef5"), frame = hex("7f8797") },
    rare = { step = 1, text = hex("4ea3ff"), frame = hex("4ea3ff") },
    epic = { step = 2, text = hex("b56bff"), frame = hex("b56bff") },
    legendary = { step = 3, text = hex("ff9a2e"), frame = hex("ff9a2e") },
}
function Fx.Rarity(r) return Fx.RARITY[r] or Fx.RARITY.common end

-- A globe's file: the scene in its rarity, or the frosted one ("closed"). `big` takes the 256 set.
function Fx.GlobePath(scene, rarity, big)
    if not (scene and rarity) then return Fx.PATH.globes .. (big and "closed-256" or "closed") end
    return (big and Fx.PATH.globes256 or Fx.PATH.globes) .. scene .. "\45" .. rarity
end

----------------------------------------------------------------------
-- Sounds: the client's own, by id (all of them a conferir on 2.5.x), on the SFX channel, inside pcall, and only
-- while the `veilSounds` option is on.
----------------------------------------------------------------------
Fx.SOUND = {
    tab = 841,      -- IG_CHARACTER_INFO_TAB
    pick = 856,     -- IG_MAINMENU_OPTION_CHECKBOX_ON: a scene, the box
    wrap = 863,     -- IG_BACKPACK_CLOSE
    shake = 862,    -- IG_BACKPACK_OPEN: the ribbon falls
    step = 3175,    -- MAP_PING: a rarity step
    reveal = 878,   -- IG_QUEST_LIST_COMPLETE: common, rare
    big = 888,      -- LEVELUP: epic, legendary
    full = 8960,    -- READY_CHECK: the Chimney fills
}

function Fx.SoundsOn() return GuildOS:GetSetting("veilSounds") ~= false end

function Fx.Sound(name)
    local id = Fx.SOUND[name]
    if not id or not Fx.SoundsOn() or type(PlaySound) ~= "function" then return false end
    return (pcall(PlaySound, id, "SFX"))
end

----------------------------------------------------------------------
-- The option: the `snow` key, shown as "Winter Veil animations" (snow, embers, rays). Unset is on.
----------------------------------------------------------------------
function Fx.Enabled() return GuildOS:GetSetting("snow") ~= false end

----------------------------------------------------------------------
-- Scopes, groups and the count
----------------------------------------------------------------------
local scopes = {}
Fx._scopes = scopes

local function visible(frame) return frame ~= nil and frame:IsVisible() == true end

-- Textures in motion right now: every playing group's weight, the flipbooks running, and the window's snow.
function Fx.Moving()
    local n = 0
    for _, sc in ipairs(scopes) do
        for _, g in ipairs(sc.groups) do if g.playing then n = n + g.n end end
        if sc.fire and sc.fire.running then n = n + 2 end
    end
    local snow = GuildOS.Snow
    if snow and snow.Moving then n = n + snow:Moving() end
    return n
end

local Scope = {}
Scope.__index = Scope

-- A scope for `root`: what it creates stops when it hides.
function Fx.Scope(root)
    local sc = setmetatable({ root = root, groups = {}, timers = {}, idle = {} }, Scope)
    scopes[#scopes + 1] = sc
    root:HookScript("OnHide", function() sc:StopAll() end)
    return sc
end

function Scope:Live() return Fx.Enabled() and visible(self.root) end

-- The option changed: off stops every scope at once; either way each scope redraws (scope.onOption).
function Fx.OptionChanged()
    for _, sc in ipairs(scopes) do
        if not Fx.Enabled() then sc:StopAll() end
        if sc.onOption then GuildOS:SafeCall(sc.onOption) end
    end
end

function Scope:StopTag(tag)
    for _, g in ipairs(self.groups) do if g.tag == tag then g:Stop() end end
    for _, t in ipairs(self.timers) do if t.tag == tag then t:Stop() end end
end

function Scope:StopAll()
    for _, g in ipairs(self.groups) do g:Stop() end
    for _, t in ipairs(self.timers) do t:Stop() end
    if self.fire then self.fire:Stop() end
end

local function setScale(a, fx, fy, tx, ty)
    if a.SetScaleFrom and a.SetScaleTo then a:SetScaleFrom(fx, fy); a:SetScaleTo(tx, ty)
    elseif a.SetFromScale and a.SetToScale then a:SetFromScale(fx, fy); a:SetToScale(tx, ty)
    else a:SetScale(tx / fx, ty / fy) end
end

-- One AnimationGroup on `region`, built from steps:
--   { "move", x, y, dur, delay?, order? } { "alpha", from, to, dur, delay?, order? }
--   { "scale", from, to, dur, delay?, order?, origin?, axis? }
--   { "turn", degrees, dur, delay?, order?, origin? }   (origin = { point, x, y })
-- opts: loop ("REPEAT" | "BOUNCE"), n (textures it moves, default 1), smooth ("IN" | "OUT" | "IN_OUT"), done (fn),
--   final (the region keeps the last alpha), tag (Scope:StopTag stops every group and timer with it).
-- Returns a group: :Play() (false when refused), :Stop(), .playing.
function Scope:Group(region, steps, opts)
    opts = opts or {}
    local ag = region:CreateAnimationGroup()
    local g = { ag = ag, n = opts.n or 1, playing = false, scope = self, region = region, tag = opts.tag }
    for _, s in ipairs(steps) do
        local kind, a = s[1], nil
        if kind == "move" then
            a = ag:CreateAnimation("Translation"); a:SetOffset(s[2], s[3])
            a:SetDuration(s[4]); a:SetStartDelay(s[5] or 0); a:SetOrder(s[6] or 1)
        elseif kind == "alpha" then
            a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(s[2]); a:SetToAlpha(s[3])
            a:SetDuration(s[4]); a:SetStartDelay(s[5] or 0); a:SetOrder(s[6] or 1)
        elseif kind == "scale" then
            -- s[8]: "x" or "y" stretches one axis only
            local ax = s[8]
            a = ag:CreateAnimation("Scale")
            setScale(a, ax == "y" and 1 or s[2], ax == "x" and 1 or s[2], ax == "y" and 1 or s[3], ax == "x" and 1 or s[3])
            a:SetDuration(s[4]); a:SetStartDelay(s[5] or 0); a:SetOrder(s[6] or 1)
            if s[7] then a:SetOrigin(s[7][1], s[7][2] or 0, s[7][3] or 0) end
        elseif kind == "turn" then
            a = ag:CreateAnimation("Rotation"); a:SetDegrees(s[2])
            a:SetDuration(s[3]); a:SetStartDelay(s[4] or 0); a:SetOrder(s[5] or 1)
            if s[6] then a:SetOrigin(s[6][1], s[6][2] or 0, s[6][3] or 0) end
        end
        if a and opts.smooth then a:SetSmoothing(opts.smooth) end
    end
    if opts.loop then ag:SetLooping(opts.loop) end
    if opts.final and ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
    ag:SetScript("OnFinished", function()
        g.playing = false
        if opts.done then GuildOS:SafeCall(opts.done) end
    end)
    function g:Play()
        if self.playing then return true end
        local sc = self.scope
        if not sc:Live() or Fx.Moving() + self.n > Fx.BUDGET then return false end
        self.playing = true
        self.ag:Play()
        return true
    end
    function g:Stop()
        if not self.playing then return end
        self.playing = false
        self.ag:Stop()
    end
    self.groups[#self.groups + 1] = g
    return g
end

-- Run `fn` after `sec` seconds, with no OnUpdate: an empty group on a frame of the scope. Refused (nil) when the
-- scope is not live; stopped with the scope. Timers are reused.
function Scope:After(sec, fn, tag)
    if not self:Live() then return nil end
    local t = table.remove(self.idle)
    if not t then
        local holder = CreateFrame("Frame", nil, self.root)
        holder:SetSize(1, 1)
        holder:SetPoint("TOPLEFT")
        local ag = holder:CreateAnimationGroup()
        local a = ag:CreateAnimation("Animation")
        t = { ag = ag, a = a, scope = self }
        ag:SetScript("OnFinished", function()
            local f = t.fn
            t.fn = nil
            self.idle[#self.idle + 1] = t
            if f then GuildOS:SafeCall(f) end
        end)
        function t:Stop()
            if self.fn then
                self.fn = nil
                self.ag:Stop()
                self.scope.idle[#self.scope.idle + 1] = self
            end
        end
        self.timers[#self.timers + 1] = t
    end
    t.fn, t.tag = fn, tag
    t.a:SetDuration(math.max(0.01, sec))
    t.ag:Play()
    return t
end

----------------------------------------------------------------------
-- The fire's flipbook: two textures on the atlas, the back one mirrored and FIRE_BACK_AHEAD frames ahead, one
-- OnUpdate at FIRE_STEP. Stopped, it rests on its first frame.
----------------------------------------------------------------------
function Scope:Flipbook(front, back)
    local driver = CreateFrame("Frame", nil, self.root)
    local fb = { front = front, back = back, frame = 1, acc = 0, running = false, driver = driver, scope = self }
    local function paint()
        local l, r, t, b = Fx.FireCoords(fb.frame)
        front:SetTexCoord(l, r, t, b)
        l, r, t, b = Fx.FireCoords(fb.frame + Fx.FIRE_BACK_AHEAD)
        back:SetTexCoord(r, l, t, b)
    end
    fb.paint = paint
    function fb:Start()
        if self.running or not self.scope:Live() or Fx.Moving() + 2 > Fx.BUDGET then return self.running end
        self.running = true
        self.acc = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            fb.acc = fb.acc + elapsed
            if fb.acc < Fx.FIRE_STEP then return end
            fb.acc = 0
            fb.frame = fb.frame % Fx.FIRE_FRAMES + 1
            paint()
        end)
        return true
    end
    function fb:Stop()
        if not self.running then return end
        self.running = false
        driver:SetScript("OnUpdate", nil)
    end
    paint()
    self.fire = fb
    return fb
end

----------------------------------------------------------------------
-- Pieces and factories
----------------------------------------------------------------------
-- A texture of the atlas: `piece` from PIECES, tinted, ADD or BLEND.
function Fx.Piece(parent, piece, w, h, layer, add, color, alpha)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture(Fx.PATH.atlas)
    tex:SetTexCoord(Fx.Coords(piece))
    tex:SetSize(w, h)
    if add then tex:SetBlendMode("ADD") end
    if color then tex:SetVertexColor(color.r, color.g, color.b) end
    tex:SetAlpha(alpha or 1)
    return tex
end

-- A Frimm portrait at `size` with `face`.
function Fx.Frimm(parent, size, face)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(Fx.PATH.frimm)
    tex:SetSize(size, size)
    tex:SetTexCoord(Fx.FaceCoords(face))
    function tex:SetFace(f) self:SetTexCoord(Fx.FaceCoords(f)) end
    return tex
end

-- A deterministic generator (Park-Miller), so a level always draws the same embers.
function Fx.Rng(seed)
    local a = (math.floor(seed) % 2147483646) + 1
    return function()
        a = (a * 16807) % 2147483647
        return (a - 1) / 2147483646
    end
end

-- An ember rising from (x, y): Translation + Alpha, REPEAT, its height, drift and pace drawn at creation.
function Scope:Ember(parent, x, y, r)
    local tex = Fx.Piece(parent, "ember", 6, 6, "OVERLAY", true, nil, 0)
    tex:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    local h, ex, dur, delay = 80 + r() * 150, (r() - 0.5) * 60, 1.8 + r() * 2.2, r() * 1.5
    local g = self:Group(tex, {
        { "move", ex, h, dur, delay },
        { "alpha", 0, 1, dur * 0.08, delay },
        { "alpha", 1, 0, dur * 0.92, delay + dur * 0.08 },
    }, { loop = "REPEAT" })
    return tex, g
end

-- A puff of smoke from the stack: Translation + Scale + Alpha, REPEAT.
function Scope:Smoke(parent, x, y, r, i, alpha)
    local tex = Fx.Piece(parent, "smoke", 40, 40, "ARTWORK", false, nil, 0)
    tex:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    local dur = 3.2 + r() * 1.6
    local g = self:Group(tex, {
        { "move", 10 + r() * 30, 80, dur, i * 1.1 },
        { "scale", 0.5, 1.7, dur, i * 1.1 },
        { "alpha", 0, alpha, dur * 0.25, i * 1.1 },
        { "alpha", alpha, 0, dur * 0.75, i * 1.1 + dur * 0.25 },
    }, { loop = "REPEAT", smooth = "OUT" })
    return tex, g
end

-- A star shooting out of (x, y) towards (dx, dy): once (burst) or REPEAT.
function Scope:Star(parent, x, y, dx, dy, dur, delay, loop, color)
    local tex = Fx.Piece(parent, "star", 14, 14, "OVERLAY", true, color, 0)
    tex:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    local g = self:Group(tex, {
        { "move", dx, -dy, dur, delay },
        { "scale", 0.4, 1.1, dur, delay },
        { "turn", -120, dur, delay },
        { "alpha", 0, 1, dur * 0.1, delay },
        { "alpha", 1, 0, dur * 0.9, delay + dur * 0.1 },
    }, { loop = loop and "REPEAT" or nil, smooth = "OUT" })
    return tex, g
end

-- A ring that grows and fades from the centre of `parent`.
function Scope:Ring(parent, size)
    local tex = Fx.Piece(parent, "ring", size, size, "OVERLAY", true, nil, 0)
    tex:SetPoint("CENTER")
    return tex
end

-- A burst of up to `n` stars out of (x, y) in `color`, spread over `radius`, from a pool kept on the scope.
function Scope:Burst(parent, x, y, n, color, radius, up)
    self.stars = self.stars or {}
    local pool = self.stars[parent]
    if not pool then pool = {}; self.stars[parent] = pool end
    local played = 0
    for i = 1, n do
        local s = pool[i]
        if not s then
            s = {}
            s.tex = Fx.Piece(parent, "star", 14, 14, "OVERLAY", true, nil, 0)
            pool[i] = s
        end
        if s.g then s.g:Stop() end
        local a = up and (-math.pi / 2 + (math.random() - 0.5) * 2.6) or math.random() * 6.283
        local d = radius * (0.5 + math.random() * 0.6)
        s.tex:ClearAllPoints()
        s.tex:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
        s.tex:SetVertexColor(color.r, color.g, color.b)
        s.tex:SetAlpha(0)
        local dur = 0.8 + math.random() * 0.7
        s.g = self:Group(s.tex, {
            { "move", math.cos(a) * d, -math.sin(a) * d, dur },
            { "scale", 0.3, 0.8 + math.random() * 0.8, dur },
            { "turn", -(90 + math.random() * 180), dur },
            { "alpha", 1, 0, dur },
        }, { smooth = "OUT" })
        if s.g:Play() then played = played + 1 end
    end
    return played
end

-- A tremble: a 70 ms back-and-forth Translation on `frame`, looping until stopped. `n` textures move with it.
function Scope:Tremble(frame, amp, n)
    return self:Group(frame, { { "move", amp, 0, 0.035 }, { "move", -2 * amp, 0, 0.07, 0, 2 }, { "move", amp, 0, 0.035, 0, 3 } },
        { loop = "REPEAT", n = n or 1 })
end

-- Rays turning around the centre of `parent`: one full turn in `period` seconds (negative turns the other way).
function Scope:Rays(parent, size, color, alpha, period)
    local tex = Fx.Piece(parent, "rays", size, size, "BACKGROUND", true, color, alpha)
    tex:SetPoint("CENTER")
    local g = self:Group(tex, { { "turn", period < 0 and 360 or -360, math.abs(period) } }, { loop = "REPEAT" })
    return tex, g
end

-- A fade-in of `region` after `delay`; it stays shown. With the scope not live it simply shows.
function Scope:Reveal(region, delay, dur)
    region:SetAlpha(0)
    local g = self:Group(region, { { "alpha", 0, 1, dur or 0.38, delay or 0 } }, { smooth = "OUT", final = true })
    if not g:Play() then region:SetAlpha(1) end
    return g
end

-- A bounce of `region`'s scale: 1 -> `peak` -> 1 over `dur`.
function Scope:Pop(region, peak, dur, n)
    return self:Group(region, { { "scale", 1, peak, dur / 2 }, { "scale", 1, 1 / peak, dur / 2, 0, 2 } }, { smooth = "OUT", n = n })
end

----------------------------------------------------------------------
-- Shared drawing: a 1px border, Frimm's speech bubble, the note as a card. Flat colour textures: no bytes.
----------------------------------------------------------------------
-- Four 1px lines around `frame`, `off` pixels out (negative = in). border:SetColor(c, a).
function Fx.Border(frame, c, a, off, layer)
    off = off or 0
    local b = {}
    for i = 1, 4 do b[i] = frame:CreateTexture(nil, layer or "BORDER") end
    b[1]:SetPoint("TOPLEFT", -off, off); b[1]:SetPoint("TOPRIGHT", off, off); b[1]:SetHeight(1)
    b[2]:SetPoint("BOTTOMLEFT", -off, -off); b[2]:SetPoint("BOTTOMRIGHT", off, -off); b[2]:SetHeight(1)
    b[3]:SetPoint("TOPLEFT", -off, off); b[3]:SetPoint("BOTTOMLEFT", -off, -off); b[3]:SetWidth(1)
    b[4]:SetPoint("TOPRIGHT", off, off); b[4]:SetPoint("BOTTOMRIGHT", off, -off); b[4]:SetWidth(1)
    local border = { lines = b }
    function border:SetColor(col, alpha)
        for _, t in ipairs(self.lines) do t:SetColorTexture(col.r, col.g, col.b, alpha or 1) end
    end
    function border:SetShown(v) for _, t in ipairs(self.lines) do t:SetShown(v) end end
    border:SetColor(c, a)
    return border
end

local function textHeight(fs, fallback)
    local h = tonumber(fs:GetStringHeight())
    return h and h > 0 and h or fallback
end
Fx.TextHeight = textHeight

-- Frimm's bubble: a popup surface with a gold mono label over the line. bubble:Say(label, text).
function Fx.Bubble(parent, width)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.popup.r, C.popup.g, C.popup.b, 1)
    Fx.Border(f, C.line, 1, 0)
    local label = UI:CreateText(f, "", 11, C.gold.r, C.gold.g, C.gold.b)
    if GuildOS.ApplyFont then GuildOS:ApplyFont(label, 11, "caption") end
    label:SetPoint("TOPLEFT", 10, -8)
    local text = UI:CreateText(f, "", 12, C.text.r, C.text.g, C.text.b)
    text:SetPoint("TOPLEFT", 10, -8)
    text:SetWidth(width - 20)
    text:SetJustifyH("LEFT")
    f.label, f.text = label, text
    function f:Say(lab, line)
        self.label:SetText(lab or "")
        self.label:SetShown(lab ~= nil and lab ~= "")
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", 10, (lab and lab ~= "") and -22 or -8)
        self.text:SetText(line or "")
        self:SetHeight(((lab and lab ~= "") and 30 or 16) + textHeight(self.text, 16))
    end
    return f
end

-- The note as a card: paper, a strip of gold tape, the note in quotes. card:SetNote(text).
function Fx.Card(parent, width)
    local UI = GuildOS.UI
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    local paper = Fx.hex("efe6d2")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(paper.r, paper.g, paper.b, 1)
    local tape = f:CreateTexture(nil, "ARTWORK")
    tape:SetSize(34, 12)
    tape:SetPoint("CENTER", f, "TOP", 0, 0)
    tape:SetColorTexture(0.85, 0.66, 0.31, 0.75)
    local ink = Fx.hex("3a2f1c")
    local text = UI:CreateText(f, "", 12, ink.r, ink.g, ink.b)
    text:SetPoint("TOPLEFT", 12, -10)
    text:SetWidth(width - 24)
    text:SetJustifyH("LEFT")
    f.text = text
    function f:SetNote(note)
        self.text:SetText(note and ("\"" .. note .. "\"") or "")
        self:SetHeight(20 + textHeight(self.text, 16))
    end
    return f
end
