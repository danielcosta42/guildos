----------------------------------------------------------------------
-- Guild OS - the Collection as a shelf (guildos-web#673, the site's specs/122 addon.md)
-- Three columns of 128 px globes on planks, each framed in its rarity's colour, and the detail on the right: the
-- globe at 192 (the 256 file), from whom, and the note as a card. Epic and legendary get rays turning, in the detail
-- only; a legendary on the shelf gets a band of light crossing it every 3.6 s. Hovering a globe lifts it 3 px and
-- rocks it once. Two rows show at a time; the mouse wheel moves by a row.
-- Layout only: the list is GuildOS.WinterVeil:Collection(), newest first, as the site sent it.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local Fx = GuildOS.VeilFx

local Shelf = {}
GuildOS.VeilShelf = Shelf

Shelf.COLS = 3
Shelf.ROWS = 2
Shelf.SLOT = 132    -- a 128 globe in a 1px frame, and a pixel of air
Shelf.GAP = 16
Shelf.LEFT = 12
Shelf.TOP = 34
Shelf.DETAIL_X = 452

local function slotXY(i)
    local c, r = (i - 1) % Shelf.COLS, math.floor((i - 1) / Shelf.COLS)
    return c * (Shelf.SLOT + Shelf.GAP), r * (Shelf.SLOT + Shelf.GAP)
end

-- Pure: the page of `n` globes that starts at row `top` (0-based), clamped. Returns the first index shown, how many
-- slots (always full rows, at least two), and the top row actually used.
function Shelf.Window(n, top)
    local per = Shelf.COLS * Shelf.ROWS
    local rows = math.max(Shelf.ROWS, math.ceil((n + 1) / Shelf.COLS))
    top = math.max(0, math.min(top or 0, rows - Shelf.ROWS))
    return top * Shelf.COLS + 1, per, top
end

function Shelf.Create(parent, scope, T)
    local sh = { scope = scope, T = T, top = 0, selected = 1, list = {} }
    setmetatable(sh, { __index = Shelf })

    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", Shelf.LEFT, -Shelf.TOP)
    area:SetSize(Shelf.COLS * Shelf.SLOT + (Shelf.COLS - 1) * Shelf.GAP, Shelf.ROWS * (Shelf.SLOT + Shelf.GAP))
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        sh.top = sh.top - delta
        GuildOS:SafeCall(function() sh:Set(sh.list) end)
    end)
    sh.area = area

    -- The planks under each row.
    sh.planks = {}
    for r = 1, Shelf.ROWS do
        local p = area:CreateTexture(nil, "BACKGROUND")
        p:SetColorTexture(0.29, 0.227, 0.18, 1)
        p:SetPoint("TOPLEFT", 0, -(r * Shelf.SLOT + (r - 1) * Shelf.GAP + 4))
        p:SetSize(Shelf.COLS * Shelf.SLOT + (Shelf.COLS - 1) * Shelf.GAP, 7)
        local lip = area:CreateTexture(nil, "BORDER")
        lip:SetColorTexture(0.42, 0.333, 0.267, 1)
        lip:SetPoint("TOPLEFT", p, "TOPLEFT")
        lip:SetPoint("TOPRIGHT", p, "TOPRIGHT")
        lip:SetHeight(1)
        sh.planks[r] = p
    end

    sh.slots = {}
    for i = 1, Shelf.COLS * Shelf.ROWS do sh.slots[i] = sh:NewSlot(i) end

    -- The detail.
    local det = CreateFrame("Frame", nil, parent)
    det:SetPoint("TOPLEFT", Shelf.DETAIL_X, -12)
    det:SetPoint("BOTTOMRIGHT", -12, 12)
    det:SetClipsChildren(true)
    local rule = det:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetWidth(1)
    sh.det = det

    local stage = CreateFrame("Frame", nil, det)
    stage:SetSize(208, 200)
    stage:SetPoint("TOP", det, "TOP", 7, 0)
    sh.stage = stage
    sh.rays1, sh.rays1G = scope:Rays(stage, 300, Fx.Rarity("legendary").text, 0.45, 22)
    sh.rays2, sh.rays2G = scope:Rays(stage, 300, { r = 0.63, g = 0.91, b = 1 }, 0.3, -31)
    sh.rays1G.tag, sh.rays2G.tag = "shelf", "shelf"
    local globe = stage:CreateTexture(nil, "ARTWORK")
    globe:SetSize(192, 192)
    globe:SetPoint("TOPLEFT", 8, -4)
    sh.globe = globe

    local name = UI:CreateText(det, "", 18, C.text.r, C.text.g, C.text.b)
    name:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 14 - 7, -4)
    local sub = UI:CreateText(det, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    local from = UI:CreateText(det, "", 12, C.text.r, C.text.g, C.text.b)
    from:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -6)
    from:SetPoint("RIGHT", det, "RIGHT", 0, 0)
    from:SetJustifyH("LEFT")
    local card = Fx.Card(det, 220)
    card:SetPoint("TOPLEFT", from, "BOTTOMLEFT", 0, -14)
    local noNote = UI:CreateText(det, L["No note."], 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
    noNote:SetPoint("TOPLEFT", from, "BOTTOMLEFT", 0, -10)
    local hint = UI:CreateText(det, L["The globe and the year are public on your character's page; the note and who gave it are for your guild only."], 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
    hint:SetPoint("BOTTOMLEFT", 14, 0)
    hint:SetPoint("RIGHT", det, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    sh.name, sh.sub, sh.from, sh.card, sh.noNote, sh.hint = name, sub, from, card, noNote, hint

    -- Empty: Frimm, oops.
    local face = Fx.Frimm(parent, 64, "oops")
    face:SetPoint("TOPLEFT", Shelf.DETAIL_X + 14, -42)
    local bubble = Fx.Bubble(parent, 200)
    bubble:SetPoint("TOPLEFT", face, "TOPRIGHT", 12, 0)
    bubble:Say(L["FRIMM"], L["Empty shelf! It wasn't me. The globes you open show here, on the site and in the game."])
    sh.emptyFace, sh.emptyBubble = face, bubble
    return sh
end

function Shelf:NewSlot(i)
    local area, scope = self.area, self.scope
    local x, y = slotXY(i)
    local s = CreateFrame("Button", nil, area)
    s:SetSize(Shelf.SLOT, Shelf.SLOT)
    s.x, s.y = x, y
    s:SetPoint("TOPLEFT", x, -y)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.well.r, C.well.g, C.well.b, 1)
    s.border = Fx.Border(s, C.line, 1, 0)
    -- The corner brackets: top-left and bottom-right, 10 px, 2 px thick, 3 px out.
    s.corners = {}
    local function bracket(point, sx, sy)
        local h = s:CreateTexture(nil, "OVERLAY")
        h:SetSize(10, 2)
        h:SetPoint(point, sx * 3, sy * 3)
        local v = s:CreateTexture(nil, "OVERLAY")
        v:SetSize(2, 10)
        v:SetPoint(point, sx * 3, sy * 3)
        s.corners[#s.corners + 1] = h
        s.corners[#s.corners + 1] = v
    end
    bracket("TOPLEFT", -1, 1)
    bracket("BOTTOMRIGHT", 1, -1)
    s.sel = Fx.Border(s, C.line, 0.7, 2)
    s.sel:SetShown(false)

    local clip = CreateFrame("Frame", nil, s)
    clip:SetPoint("TOPLEFT", 1, -1)
    clip:SetPoint("BOTTOMRIGHT", -1, 1)
    clip:SetClipsChildren(true)
    s.glow = Fx.Piece(clip, "flash", 128, 128, "BORDER", true, nil, 0.16)
    s.glow:SetPoint("CENTER")
    s.globe = clip:CreateTexture(nil, "ARTWORK")
    s.globe:SetSize(128, 128)
    s.globe:SetPoint("CENTER")
    s.shine = Fx.Piece(clip, "flash", 30, 128, "OVERLAY", true, { r = 1, g = 0.86, b = 0.63 }, 0.35)
    s.shine:SetPoint("TOPLEFT", -40, 0)
    s.shineG = scope:Group(s.shine, { { "move", 190, 0, 1.6, 2.0 } }, { loop = "REPEAT", smooth = "IN_OUT", tag = "shelf" })
    s.wobG = scope:Group(s.globe, { { "turn", 4, 0.15 }, { "turn", -7, 0.175, 0, 2 }, { "turn", 3, 0.175, 0, 3 } }, { smooth = "OUT", tag = "shelf" })
    s.empty = UI:CreateText(s, "", 10, C.disabled.r, C.disabled.g, C.disabled.b)
    s.empty:SetPoint("CENTER")

    s:SetScript("OnEnter", function(btn)
        if not btn.item then return end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", btn.x, -btn.y + 3)
        btn.wobG:Play()
        local o, T = btn.item, self.T
        if GameTooltip then
            local c = Fx.Rarity(o.rarity).text
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(T.sceneName(o.scene) .. " · " .. T.rarityName(o.rarity), c.r, c.g, c.b)
            GameTooltip:AddLine(string.format(L["Snow globe · Winter Veil %d"], o.year), C.textSoft.r, C.textSoft.g, C.textSoft.b)
            GameTooltip:AddLine(string.format(L["From %s"], T.fromOf(o)), 1, 1, 1)
            if o.note and o.note ~= "" then GameTooltip:AddLine("\"" .. o.note .. "\"", 1, 1, 1, true) end
            GameTooltip:AddLine(L["Click to see it up close"], C.gold.r, C.gold.g, C.gold.b)
            GameTooltip:Show()
        end
    end)
    s:SetScript("OnLeave", function(btn)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", btn.x, -btn.y)
        if GameTooltip then GameTooltip:Hide() end
    end)
    s:SetScript("OnClick", function(btn)
        if not btn.index then return end
        self.selected = btn.index
        Fx.Sound("pick")
        GuildOS:SafeCall(function() self:Set(self.list) end)
    end)
    return s
end

-- Draws `list` (the Collection). Returns how many globes it holds.
function Shelf:Set(list)
    self.list = list or {}
    local n = #self.list
    local first, per, top = Shelf.Window(n, self.top)
    self.top = top
    self.selected = math.min(math.max(1, self.selected), math.max(1, n))
    local live = self.scope:Live()
    for k = 1, per do
        local s, idx = self.slots[k], first + k - 1
        local o = self.list[idx]
        s.item, s.index = o, o and idx or nil
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", s.x, -s.y)
        if o then
            local rc = Fx.Rarity(o.rarity)
            s.border:SetColor(rc.frame, 1)
            for _, t in ipairs(s.corners) do t:SetColorTexture(rc.frame.r, rc.frame.g, rc.frame.b, 1); t:Show() end
            s.globe:SetTexture(Fx.GlobePath(o.scene, o.rarity))
            s.globe:Show()
            local glows = o.rarity == "epic" or o.rarity == "legendary"
            s.glow:SetVertexColor(rc.frame.r, rc.frame.g, rc.frame.b)
            s.glow:SetShown(glows)
            local leg = o.rarity == "legendary"
            s.shine:SetShown(leg)
            if leg and live then s.shineG:Play() else s.shineG:Stop() end
            s.sel:SetColor(rc.frame, 0.7)
            s.sel:SetShown(idx == self.selected)
            s.empty:SetText("")
            s:EnableMouse(true)
        else
            s.border:SetColor(C.line, 1)
            for _, t in ipairs(s.corners) do t:Hide() end
            s.globe:Hide()
            s.glow:Hide()
            s.shine:Hide()
            s.shineG:Stop()
            s.sel:SetShown(false)
            s.empty:SetText(idx == n + 1 and L["next globe"] or "")
            s:EnableMouse(false)
        end
    end

    -- The detail.
    local o = self.list[self.selected]
    local has = o ~= nil
    self.emptyFace:SetShown(not has)
    self.emptyBubble:SetShown(not has)
    for _, region in ipairs({ self.stage, self.name, self.sub, self.from, self.hint }) do region:SetShown(has) end
    self.card:SetShown(has and o.note ~= nil and o.note ~= "")
    self.noNote:SetShown(has and not (o.note and o.note ~= ""))
    self.rays1:SetShown(has and (o.rarity == "epic" or o.rarity == "legendary"))
    self.rays2:SetShown(has and o.rarity == "legendary")
    if not has then
        self.rays1G:Stop(); self.rays2G:Stop()
        return n
    end
    local T, rc = self.T, Fx.Rarity(o.rarity)
    self.globe:SetTexture(Fx.GlobePath(o.scene, o.rarity, true))
    if o.rarity == "epic" then
        local ep = Fx.Rarity("epic").text
        self.rays1:SetVertexColor(ep.r, ep.g, ep.b)
        self.rays1:SetAlpha(0.3)
    else
        self.rays1:SetVertexColor(1, 0.67, 0.27)
        self.rays1:SetAlpha(0.45)
    end
    if (o.rarity == "epic" or o.rarity == "legendary") and live then self.rays1G:Play() else self.rays1G:Stop() end
    if o.rarity == "legendary" and live then self.rays2G:Play() else self.rays2G:Stop() end
    self.name:SetText(T.rarityName(o.rarity))
    self.name:SetTextColor(rc.text.r, rc.text.g, rc.text.b)
    self.sub:SetText(T.sceneName(o.scene) .. " · " .. T.baseName(o.rarity) .. " · " .. o.year)
    self.from:SetText(string.format(L["From %s"], T.fromOf(o)) .. "  |cff6f6878· " .. T.dayOf(o.openedAt) .. "/" .. o.year .. "|r")
    if o.note and o.note ~= "" then self.card:SetNote(o.note) end
    return n
end
