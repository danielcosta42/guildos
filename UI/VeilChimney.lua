----------------------------------------------------------------------
-- Guild OS - the Chimney, the Winter Veil tab's left column (guildos-web#673, the site's specs/122 addon.md)
-- 264x512, always in view while the tab is. Two textures of the same drawing, cold and in embers: the hot one shows
-- from the bottom up by a clip (SetHeight + SetTexCoord), so the snow on top "melts" by itself. Fire, embers and
-- smoke grow with the level. Out before the draw ("lights at the draw"), live while wrapping, frozen at the site's
-- number from the deadline. Full is said three times: the plate turns "FULL", the odds bar moves from the base odds
-- to the doubled ones, and Frimm says so (the panel's toast) — with a sweep of light and stars, once.
-- The numbers are the site's (lib/veil-rules.ts rarityOf: cuts 60/85/97, full 20/70/94): the game only shows them.
-- Layout only: the state is GuildOS.WinterVeil.ChimneyState's.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local Fx = GuildOS.VeilFx

local Chimney = {}
GuildOS.VeilChimney = Chimney

Chimney.W, Chimney.H = 264, 512
-- The odds at the opening, from the site's rarityOf: base and with the Chimney full (common, rare, epic, legendary).
Chimney.ODDS = { 60, 25, 12, 3 }
Chimney.ODDS_FULL = { 20, 50, 24, 6 }
Chimney.EMBERS_MAX = 14
Chimney.SMOKE_MAX = 4
Chimney.STARS = 8
Chimney.TRANSITION = 0.9

local ART_W, ART_H = Fx.CHIMNEY_W, Fx.CHIMNEY_H
local GOLD = C.gold
local BLUE = C.info

-- Pure: what the column draws at `pct` (nil = out). Height of the hot part, the fire's size, how many embers,
-- puffs and stars.
function Chimney.Layout(pct)
    if pct == nil then return { hot = 0, fire = 0, embers = 0, smoke = 0, stars = 0, lit = false, full = false } end
    local full = pct >= 100
    local lit = pct > 0
    return {
        hot = math.min(ART_H, 6 + pct * 3.58),
        fire = lit and (full and 140 or 44 + pct * 0.66) or 0,
        embers = lit and math.min(Chimney.EMBERS_MAX, 3 + math.floor(pct / 11) + (full and 2 or 0)) or 0,
        smoke = lit and (2 + (pct > 50 and 1 or 0) + (pct > 85 and 1 or 0)) or 0,
        stars = full and Chimney.STARS or 0,
        glow = lit and (0.25 + pct / 140) or 0,
        lit = lit, full = full,
    }
end

local function mono(fs, size)
    if GuildOS.ApplyFont then GuildOS:ApplyFont(fs, size, "caption") end
    return fs
end

local function solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(c.r, c.g, c.b, a or 1)
    return t
end

local function dayOf(t) return t and date("%d/%m", t) or "" end

function Chimney.Create(parent, scope)
    local ch = { scope = scope, shownH = 0, target = nil, info = nil }
    local col = CreateFrame("Frame", nil, parent)
    col:SetSize(Chimney.W, Chimney.H)
    col:SetPoint("TOPLEFT", 0, 0)
    col:SetClipsChildren(true)
    col:EnableMouse(true)
    ch.frame = col

    local art = CreateFrame("Frame", nil, col)
    art:SetSize(ART_W, ART_H)
    art:SetPoint("TOPLEFT")
    art:SetClipsChildren(true)
    ch.art = art

    local cold = art:CreateTexture(nil, "BACKGROUND")
    cold:SetTexture(Fx.PATH.cold)
    cold:SetTexCoord(Fx.ChimneyCoords(ART_H))
    cold:SetAllPoints()
    local hot = art:CreateTexture(nil, "BORDER")
    hot:SetTexture(Fx.PATH.hot)
    hot:SetPoint("BOTTOMLEFT")
    hot:SetWidth(ART_W)
    hot:Hide()
    ch.cold, ch.hot = cold, hot

    -- The heat's edge, riding the top of the hot part.
    local heat = Fx.Piece(art, "flash", 248, 14, "ARTWORK", true, { r = 1, g = 0.77, b = 0.38 }, 0.55)
    heat:Hide()
    ch.heat = heat

    -- The mouth's glow, flickering.
    local glow = Fx.Piece(art, "flash", 180, 130, "ARTWORK", true, { r = 1, g = 0.59, b = 0.2 }, 0)
    glow:SetPoint("CENTER", art, "TOPLEFT", 128, -365)
    ch.glow = glow
    ch.glowG = scope:Group(glow, { { "scale", 0.94, 1.07, 0.85 } }, { loop = "BOUNCE", smooth = "IN_OUT" })

    -- The fire: two textures of the atlas, one flipbook.
    local f1 = art:CreateTexture(nil, "ARTWORK", nil, 2)
    f1:SetTexture(Fx.PATH.atlas)
    f1:SetBlendMode("ADD")
    local f2 = art:CreateTexture(nil, "ARTWORK", nil, 1)
    f2:SetTexture(Fx.PATH.atlas)
    f2:SetBlendMode("ADD")
    f2:SetAlpha(0.75)
    ch.f1, ch.f2 = f1, f2
    ch.flip = scope:Flipbook(f1, f2)

    -- Embers, smoke and the stars of a full Chimney, made once.
    local r = Fx.Rng(13)
    ch.embers = {}
    for i = 1, Chimney.EMBERS_MAX do
        local tex, g = scope:Ember(art, 98 + r() * 60, 372 + r() * 18, r)
        ch.embers[i] = { tex = tex, g = g }
    end
    ch.smoke = {}
    r = Fx.Rng(7)
    for i = 1, Chimney.SMOKE_MAX do
        local tex, g = scope:Smoke(art, 128, 64, r, i - 1, 0.45)
        ch.smoke[i] = { tex = tex, g = g }
    end
    ch.stars = {}
    r = Fx.Rng(99)
    for i = 1, Chimney.STARS do
        local a = -math.pi / 2 + (r() - 0.5) * 2.2
        local tex, g = scope:Star(art, 128, 64, math.cos(a) * 90, math.sin(a) * 70 + 10, 2.4, (i - 1) * 0.3, true, { r = 1, g = 0.86, b = 0.55 })
        ch.stars[i] = { tex = tex, g = g }
    end

    -- The sweep of light the instant it fills.
    local sweep = Fx.Piece(art, "flash", 70, 430, "OVERLAY", true, { r = 1, g = 0.93, b = 0.75 }, 0)
    sweep:SetPoint("TOPLEFT", art, "TOPLEFT", -90, 0)
    ch.sweepG = scope:Group(sweep, { { "move", 420, 0, 1.1 }, { "alpha", 0, 1, 0.22 }, { "alpha", 1, 0, 0.88, 0.22 } })

    -- The plate.
    local plate = CreateFrame("Frame", nil, art)
    plate:SetSize(84, 26)
    plate:SetPoint("TOPLEFT", 86, -254)
    local edge = solid(plate, "BACKGROUND", Fx.hex("6d4e1c"))
    edge:SetAllPoints()
    local fill = solid(plate, "BORDER", Fx.hex("d9a94f"))
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    local shine = solid(plate, "ARTWORK", C.white, 0.22)
    shine:SetPoint("TOPLEFT", 1, -1)
    shine:SetPoint("TOPRIGHT", -1, -1)
    shine:SetHeight(11)
    local plateText = mono(UI:CreateText(plate, "—", 15, 0.165, 0.11, 0.024), 15)
    plateText:SetPoint("CENTER")
    ch.plate, ch.plateFill, ch.plateText = plate, fill, plateText
    ch.plateG = scope:Pop(plate, 1.25, 0.5, 3)

    -- The ruler: 25, 50, 75, 100, lit up to the level.
    ch.ticks = {}
    for i, p in ipairs({ 25, 50, 75, 100 }) do
        local y = 422 - p * 3.58
        local line = solid(col, "ARTWORK", C.line)
        line:SetSize(22, 1)
        line:SetPoint("TOPRIGHT", col, "TOPLEFT", ART_W, -y)
        local t = mono(UI:CreateText(col, tostring(p), UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b), 10)
        t:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, -1)
        ch.ticks[i] = { p = p, line = line, text = t }
    end

    -- The share, split: gold for the globes wrapped, blue for the quests of the game's event (the site's §10).
    local gauge = solid(col, "BACKGROUND", C.well)
    gauge:SetSize(3, 358)
    gauge:SetPoint("BOTTOMLEFT", col, "TOPLEFT", ART_W + 4, -422)
    local gWrap = solid(col, "ARTWORK", GOLD)
    gWrap:SetWidth(3)
    gWrap:SetPoint("BOTTOM", gauge, "BOTTOM")
    local gQuest = solid(col, "ARTWORK", BLUE)
    gQuest:SetWidth(3)
    gQuest:SetPoint("BOTTOM", gWrap, "TOP")
    ch.gWrap, ch.gQuest = gWrap, gQuest

    local cap = mono(UI:CreateText(col, "", UI.SP.META, C.label.r, C.label.g, C.label.b), 10)
    cap:SetPoint("TOP", col, "TOPLEFT", ART_W / 2, -432)
    cap:SetWidth(ART_W)
    cap:SetJustifyH("CENTER")
    ch.cap = cap

    -- The odds at the opening.
    local oddsT = mono(UI:CreateText(col, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b), 10)
    oddsT:SetPoint("TOPLEFT", 0, -454)
    local oddsR = mono(UI:CreateText(col, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b), 10)
    oddsR:SetPoint("TOPRIGHT", col, "TOPLEFT", ART_W, -454)
    ch.oddsT, ch.oddsR = oddsT, oddsR
    ch.bars, ch.labels = {}, {}
    for i, rar in ipairs(Fx.RARITY_ORDER) do
        local c = Fx.Rarity(rar).text
        local b = solid(col, "ARTWORK", c)
        b:SetHeight(8)
        local lab = mono(UI:CreateText(col, "", UI.SP.META, c.r, c.g, c.b), 10)
        lab:SetJustifyH("LEFT")
        ch.bars[i], ch.labels[i] = b, lab
    end
    ch.odds = { unpack(Chimney.ODDS) }

    col:SetScript("OnEnter", function(f)
        local info = ch.info
        if not (info and GameTooltip) then return end
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetText(info.pct and string.format(L["The Chimney · %d%%"], info.pct) or L["The Chimney"], 1, 1, 1)
        if info.state == "off" then
            GameTooltip:AddLine(L["It lights after the draw and warms up with every globe wrapped."], C.textSoft.r, C.textSoft.g, C.textSoft.b, true)
        else
            GameTooltip:AddLine(ch.capText or "", C.textSoft.r, C.textSoft.g, C.textSoft.b, true)
            if info.questPct > 0 then
                GameTooltip:AddLine(string.format(L["%d%% came from Winter Veil quests done in the game."], info.questPct), BLUE.r, BLUE.g, BLUE.b, true)
            end
        end
        GameTooltip:AddLine(info.full and L["Full: the odds of rare, epic and legendary doubled."]
            or L["When full, the odds of rare, epic and legendary double. The Chimney at the wrapping deadline counts."],
            GOLD.r, GOLD.g, GOLD.b, true)
        local names = { L["Common"], L["Rare"], L["Epic"], L["Legendary"] }
        for i, rar in ipairs(Fx.RARITY_ORDER) do
            local c = Fx.Rarity(rar).text
            GameTooltip:AddDoubleLine(names[i], string.format("%d%%  >  %d%%", Chimney.ODDS[i], Chimney.ODDS_FULL[i]), c.r, c.g, c.b, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    col:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- The temporary OnUpdate of a transition: the hot part's height and the odds bars, then it removes itself.
    local tween = CreateFrame("Frame", nil, col)
    ch.tween = tween
    scope.root:HookScript("OnHide", function() ch:Settle() end)

    setmetatable(ch, { __index = Chimney })
    ch:ApplyHot(0)
    ch:ApplyOdds(ch.odds)
    return ch
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
function Chimney:ApplyHot(h)
    self.shownH = h
    if h <= 0 then
        self.hot:Hide()
        self.heat:Hide()
        return
    end
    self.hot:Show()
    self.hot:SetHeight(h)
    self.hot:SetTexCoord(Fx.ChimneyCoords(h))
    local full = self.info and self.info.full
    self.heat:SetShown(not full)
    self.heat:ClearAllPoints()
    self.heat:SetPoint("CENTER", self.art, "BOTTOMLEFT", ART_W / 2, h)
end

function Chimney:ApplyOdds(o)
    local x = 0
    for i = 1, 4 do
        local w = math.max(1, ART_W * o[i] / 100 - 2)
        self.bars[i]:ClearAllPoints()
        self.bars[i]:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -470)
        self.bars[i]:SetWidth(w)
        self.labels[i]:ClearAllPoints()
        self.labels[i]:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -481)
        self.labels[i]:SetText(string.format("%d%%", math.floor(o[i] + 0.5)))
        x = x + w + 2
    end
    self.odds = o
end

-- Ends a transition at its target (the tab hid, or the option went off).
function Chimney:Settle()
    self.tween:SetScript("OnUpdate", nil)
    if self.target then
        self:ApplyHot(self.target.hot)
        self:ApplyOdds(self.target.odds)
    end
end

local function ease(x) return 1 - (1 - x) ^ 3 end

function Chimney:Transition(toH, toOdds)
    self.target = { hot = toH, odds = toOdds }
    if not self.scope:Live() or (self.shownH == toH and self.odds[1] == toOdds[1]) then
        self:Settle()
        return
    end
    local fromH, fromOdds, t = self.shownH, { unpack(self.odds) }, 0
    self.tween:SetScript("OnUpdate", function(f, elapsed)
        t = t + elapsed
        local k = ease(math.min(1, t / Chimney.TRANSITION))
        self:ApplyHot(fromH + (toH - fromH) * k)
        local o = {}
        for i = 1, 4 do o[i] = fromOdds[i] + (toOdds[i] - fromOdds[i]) * k end
        self:ApplyOdds(o)
        if t >= Chimney.TRANSITION then f:SetScript("OnUpdate", nil); self:ApplyOdds(toOdds) end
    end)
end

-- `info` is WinterVeil.ChimneyState; `ctx` = { wrapped, pairs, joinUntil, wrapUntil }.
function Chimney:Set(info, ctx)
    local was = self.info
    self.info = info
    local lay = Chimney.Layout(info.pct)
    self.lay = lay

    -- The fire, by the level.
    local sz = lay.fire
    for i, f in ipairs({ self.f1, self.f2 }) do
        local s = i == 1 and sz or sz * 0.74
        f:SetSize(math.max(1, s), math.max(1, s))
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", self.art, "TOPLEFT", 128 - s / 2 + (i == 1 and -4 or 10), -399)
        f:SetShown(lay.lit)
    end
    self.glow:SetAlpha(lay.glow or 0)
    self.glow:SetShown(lay.lit)
    for i, e in ipairs(self.embers) do e.tex:SetShown(i <= lay.embers) end
    for i, s in ipairs(self.smoke) do s.tex:SetShown(i <= lay.smoke) end
    for i, s in ipairs(self.stars) do s.tex:SetShown(i <= lay.stars) end

    -- The plate, the ruler, the split.
    local full = info.full
    if info.pct == nil then
        self.plateText:SetText("—")
    elseif full then
        self.plateText:SetText(L["FULL"])
    else
        self.plateText:SetText(string.format("%d%%", info.pct))
    end
    if GuildOS.ApplyFont then GuildOS:ApplyFont(self.plateText, full and 12 or 15, "caption") end
    local pf = full and Fx.hex("f6d98c") or Fx.hex("d9a94f")
    self.plateFill:SetColorTexture(pf.r, pf.g, pf.b, 1)
    for _, t in ipairs(self.ticks) do
        local hit = lay.lit and info.pct >= t.p
        local c = hit and GOLD or C.line
        t.line:SetColorTexture(c.r, c.g, c.b, 1)
        local tc = hit and GOLD or C.labelDim
        t.text:SetTextColor(tc.r, tc.g, tc.b)
    end
    local wrapH, questH = 358 * (info.wrappedPct or 0) / 100, 358 * (info.questPct or 0) / 100
    self.gWrap:SetHeight(math.max(0.01, wrapH))
    self.gWrap:SetShown(wrapH > 0)
    self.gQuest:SetHeight(math.max(0.01, questH))
    self.gQuest:SetShown(questH > 0)

    -- The caption.
    local text
    if info.state == "off" then
        text = string.format(L["Lights at the draw, on %s"], dayOf(ctx.joinUntil))
    elseif info.state == "frozen" then
        text = string.format(L["Closed at %d%% on %s"], info.pct, dayOf(ctx.wrapUntil))
    else
        text = string.format(L["%d%% of the pairs wrapped or played the event"], info.pct)
    end
    if info.questPct and info.questPct > 0 then
        text = text .. "  |cff" .. string.format("%02x%02x%02x", BLUE.r * 255, BLUE.g * 255, BLUE.b * 255)
            .. string.format(L["+%d%% quests"], info.questPct) .. "|r"
    end
    self.capText = text
    self.cap:SetText(text)

    -- The odds.
    self.oddsT:SetText(full and L["DOUBLE ODDS"] or L["ODDS AT THE OPENING"])
    local tc = full and GOLD or C.labelDim
    self.oddsT:SetTextColor(tc.r, tc.g, tc.b)
    self.oddsR:SetText((info.state == "off" or full) and "" or L["full: they double"])
    self:Transition(lay.hot, full and Chimney.ODDS_FULL or Chimney.ODDS)

    self:Animate()
    -- True when it is full now and was not at the last draw (the first look at an already full one counts too):
    -- the panel plays the moment once a year (WinterVeil:Seen).
    return info.state == "full" and not (was and was.full)
end

-- (Re)starts what should move at this level, stops the rest. Nothing moves when the scope is not live.
function Chimney:Animate()
    local lay = self.lay
    if not lay then return end
    if not self.scope:Live() then self.scope:StopAll(); return end
    if lay.lit then self.flip:Start(); self.glowG:Play() else self.flip:Stop(); self.glowG:Stop() end
    for i, e in ipairs(self.embers) do if i <= lay.embers then e.g:Play() else e.g:Stop() end end
    for i, s in ipairs(self.smoke) do if i <= lay.smoke then s.g:Play() else s.g:Stop() end end
    for i, s in ipairs(self.stars) do if i <= lay.stars then s.g:Play() else s.g:Stop() end end
end

-- The moment it fills: the sweep, the plate's bounce, 14 stars out of the stack, the sound.
function Chimney:Celebrate()
    if not self.scope:Live() then return false end
    self.sweepG:Play()
    self.plateG:Play()
    self.scope:Burst(self.art, 128, 64, 14, { r = 1, g = 0.85, b = 0.54 }, 110, true)
    Fx.Sound("full")
    return true
end
