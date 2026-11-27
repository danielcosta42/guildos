----------------------------------------------------------------------
-- Guild OS - What's new / Welcome (specs/salao/onboarding.md)
--
-- At login, once per version (Modules/Onboarding.lua decides): an account that used Guild OS before reads
-- what changed in this version (up to six cards, by rank and client); a new one gets the welcome (what Guild
-- OS is, how to open it with the guild button's choice, its raid roles, what is shared). A floating window
-- (the mockup's .fw), its cards one at a time: a picture drawn with the Salão's own textures (no screenshot,
-- nothing to translate but the room names), the card's dots, its title and its text. "Take the tour" on the
-- last card starts the member tour; "Later" (the close, Escape) shows it again at the next login, three times
-- at most, then only a red dot on the title bar's "?"; "Don't show again" closes it for good.
--
-- Through GuildOS:ShowWhenClear (never in combat, one popup at a time) and Onboarding:Clear (never inside an
-- instance or in a raid group), at most one onboarding popup each login.
--
-- UI.Picture draws the pictures: here, in the tour's callout and in the help's guides. Everything is pooled
-- per holder, so drawing another picture into it makes nothing new once it has drawn the biggest one.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

----------------------------------------------------------------------
-- The pictures
----------------------------------------------------------------------
local Picture = {}
UI.Picture = Picture

local function rgb(h, a)
    return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255, a = a or 1 }
end
local INK = {
    dark = rgb("0a0502", 0.62), arch = rgb("2a170b"), archLit = rgb("6b3412"), metal = rgb("6b5326"), metal2 = rgb("c9a24a"),
    gold = rgb("ffd24a"), gold2 = rgb("ffd77a"), soft = rgb("c9b48f"), paper = rgb("f3e4c2"), paperLine = rgb("c4a874"),
    flame = rgb("ff9a3c"), ember = rgb("ffcf6a"), red = rgb("9b2216"), green = rgb("4f8a3a"), greenLit = rgb("5fe05a"),
    sea = rgb("123241"), land = rgb("3d4a2a"), land2 = rgb("54603a"), tan = rgb("e6d2a5", 0.25), brown = rgb("5a3418"),
    T = rgb("2d6fb8"), H = rgb("2f8a3a"), D = rgb("9b2216"),
}
local CLASS = { rgb("C69B6D"), rgb("F48CBA"), rgb("AAD372"), rgb("FFF468"), rgb("FFFFFF"), rgb("3FC7EB"), rgb("8788EE"), rgb("FF7C0A") }

-- The holder's pools: boxes (a rounded fill and its line), single textures and texts.
local function pools(h)
    local p = h.__pic
    if not p then
        p = { box = {}, tex = {}, fs = {}, nb = 0, nt = 0, nf = 0 }
        h.__pic = p
        p.bg = GuildOS.Style:Texture(h, "wood", "BACKGROUND", 0, true)
        p.bg:SetAllPoints()
        local edge = GuildOS.Style:Nine(h, "card-line", 6, "BORDER", 7)
        edge:SetColor(INK.metal)
        p.edge = edge
    end
    return p
end

local function box(p, h)
    p.nb = p.nb + 1
    local b = p.box[p.nb]
    if not b then
        b = CreateFrame("Frame", nil, h)
        b.fill = GuildOS.Style:Nine(b, "card", 5, "BACKGROUND", 1)
        b.line = GuildOS.Style:Nine(b, "card-line", 5, "BORDER", 0)
        p.box[p.nb] = b
    end
    b:SetFrameLevel(h:GetFrameLevel() + 1)
    return b
end

local function tex(p, h)
    p.nt = p.nt + 1
    local t = p.tex[p.nt]
    if not t then
        t = h:CreateTexture(nil, "ARTWORK")
        p.tex[p.nt] = t
    end
    t:SetDrawLayer("ARTWORK", 2)
    t:SetTexCoord(0, 1, 0, 1)
    return t
end

local function fs(p, h)
    p.nf = p.nf + 1
    local f = p.fs[p.nf]
    if not f then
        f = h:CreateFontString(nil, "OVERLAY")
        f:SetShadowOffset(0, 0)
        f:SetWordWrap(false)
        p.fs[p.nf] = f
    end
    return f
end

-- Draw picture `key` into holder `h`, `w` x `hh` px. The scene is laid on a 512 x 180 grid, scaled to fit.
function Picture:Draw(h, key, w, hh)
    w, hh = math.max(40, w or h:GetWidth() or 200), math.max(30, hh or h:GetHeight() or 120)
    local p = pools(h)
    p.nb, p.nt, p.nf = 0, 0, 0
    local sx, sy = w / 512, hh / 180
    local s = math.min(sx, sy)
    local function X(v) return v * sx end
    local function Y(v) return v * sy end
    p.bg:SetVertexColor(1, 1, 1, 1)
    p.bg:SetTexture(GuildOS.Style.ART.wood, "REPEAT", "REPEAT")

    local D = {}
    -- A rounded box at (x, y) in the grid, w x h, filled `fill` with a `line`.
    function D.box(x, y, bw, bh, fill, line)
        local b = box(p, h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", h, "TOPLEFT", X(x), -Y(y))
        b:SetSize(math.max(2, X(bw)), math.max(2, Y(bh)))
        b.fill:SetColor(fill, fill.a)
        b.line:SetShown(line ~= nil)
        if line then b.line:SetColor(line, line.a) end
        b:Show()
        return b
    end
    -- One of the Salão's textures, centred at (x, y), `size` px of the grid (square, scaled evenly).
    function D.art(name, x, y, size, color, a, sw)
        local t = tex(p, h)
        t:SetTexture(GuildOS.Style.ART[name])
        t:ClearAllPoints()
        local px, ph = size * s * (sw or 1), size * s
        t:SetPoint("CENTER", h, "TOPLEFT", X(x), -Y(y))
        t:SetSize(math.max(2, px), math.max(2, ph))
        local c = color or { r = 1, g = 1, b = 1 }
        t:SetVertexColor(c.r, c.g, c.b, a or 1)
        t:Show()
        return t
    end
    function D.text(str, x, y, size, color, role, just)
        local f = fs(p, h)
        GuildOS:ApplyFont(f, math.max(8, math.floor(size * s + 0.5)), role)
        f:SetTextColor(color.r, color.g, color.b, color.a or 1)
        f:SetText(str)
        f:ClearAllPoints()
        f:SetPoint(just or "CENTER", h, "TOPLEFT", X(x), -Y(y))
        f:Show()
        return f
    end
    -- Rough lines of text, a bar each.
    function D.lines(x, y, bw, n, color)
        for i = 1, n do D.box(x, y + (i - 1) * 12, bw * (i == n and 0.6 or (i % 2 == 0 and 0.85 or 1)), 5, color or INK.tan) end
    end
    local function flame(x, y, k)
        D.art("halo", x, y - 8 * k, 70 * k, INK.flame, 0.55)
        D.art("disc", x, y, 16 * k, INK.ember, 0.9)
    end
    local function roomLabel(id)
        for _, r in ipairs(UI.ROOMS or {}) do if r.id == id then return r.label end end
        return id
    end

    if key == "salao" then
        local function arch(cx, aw, ah, lit, label)
            D.box(cx - aw / 2, 168 - ah, aw, ah, lit and INK.archLit or INK.arch, INK.metal2)
            if lit then D.art("halo", cx, 168 - ah / 2, ah * 1.1, INK.ember, 0.35) end
            D.text(label, cx, 168 - ah - 12, 13, lit and INK.gold or INK.soft, "sectionTitle")
        end
        arch(130, 66, 104, false, roomLabel("raids"))
        arch(256, 74, 128, true, roomLabel("salao"))
        arch(382, 66, 104, false, roomLabel("loot"))
        flame(40, 158, 0.8)
        flame(478, 158, 1)
    elseif key == "search" then
        D.box(40, 24, 290, 30, INK.dark, INK.metal)
        D.art("icon-search", 58, 39, 18, INK.soft)
        D.box(74, 36, 80, 6, INK.tan)
        for i, wv in ipairs({ 120, 64, 96 }) do
            local x0 = 40 + (i - 1) * 4
            for j = 1, i - 1 do x0 = x0 + ({ 120, 64, 96 })[j] + 6 end
            D.box(x0, 64, wv, 20, INK.paper, INK.paperLine)
            D.box(x0 + 10, 72, wv - 20, 4, INK.paperLine)
        end
        D.art("icon-search", 420, 60, 74, INK.gold2, 0.9)
        D.box(40, 130, 320, 28, INK.dark, INK.metal)
        D.art("orb", 58, 144, 16, INK.red)
        D.box(74, 141, 120, 6, INK.tan)
        D.art("disc", 340, 144, 16, INK.red)
        D.text("2", 340, 144, 10, INK.paper, "badge")
    elseif key == "officers" then
        D.box(40, 16, 150, 150, INK.dark, INK.metal)
        local y = 30
        for g = 1, 3 do
            D.box(54, y, 70, 5, INK.gold2)
            y = y + 14
            for i = 1, (g == 2 and 3 or 2) do
                D.box(54, y, 120, 12, (g == 1 and i == 1) and INK.gold2 or INK.tan)
                y = y + 16
            end
            y = y + 6
        end
        D.art("ring-dash", 340, 92, 150, INK.metal2, 0.45)
        D.art("ring-dash", 340, 92, 100, INK.metal2, 0.7)
        D.art("mark-banner", 340, 92, 64)
        D.art("disc", 196, 20, 18, INK.red)
        D.text("4", 196, 20, 10, INK.paper, "badge")
    elseif key == "members" then
        for i, n in ipairs({ "979", "60", "412" }) do
            D.box(40 + (i - 1) * 78, 16, 70, 38, INK.dark, INK.metal)
            D.text(n, 75 + (i - 1) * 78, 35, 16, INK.gold2, "windowTitle")
        end
        for i = 1, 4 do
            D.box(40, 64 + (i - 1) * 24, 290, 18, INK.dark)
            D.art("orb", 52, 73 + (i - 1) * 24, 11, CLASS[i])
            D.art("disc", 68, 73 + (i - 1) * 24, 10, INK.greenLit, 0.8)
            D.box(80, 71 + (i - 1) * 24, 200 - i * 20, 4, INK.tan)
        end
        D.box(370, 22, 104, 140, INK.paper, INK.paperLine)
        D.art("circle", 422, 52, 34, CLASS[2])
        D.art("ring", 422, 52, 38, INK.gold2)
        D.lines(384, 86, 76, 4, INK.paperLine)
    elseif key == "raids" then
        for i = 0, 20 do
            local col, row = i % 7, math.floor(i / 7)
            local ev = i == 3 or i == 12 or i == 17
            D.box(40 + col * 30, 24 + row * 30, 26, 26, ev and INK.red or INK.tan, ev and INK.metal2 or nil)
        end
        D.box(290, 24, 184, 54, INK.paper, INK.paperLine)
        for i, r in ipairs({ "T", "H", "D", "D" }) do
            D.box(302 + (i - 1) * 34, 37, 28, 28, INK[r], INK.metal2)
            D.text(r, 316 + (i - 1) * 34, 51, 12, INK.paper, "button")
        end
        D.box(290, 92, 184, 54, INK.paper, INK.paperLine)
        D.box(290, 92, 5, 54, INK.green)
        D.box(306, 104, 120, 5, INK.paperLine)
        D.box(306, 120, 64, 16, INK.green)
        D.art("disc", 316, 128, 8, INK.greenLit)
    elseif key == "map" then
        p.bg:SetTexture(WHITE)
        p.bg:SetVertexColor(INK.sea.r, INK.sea.g, INK.sea.b, 1)
        D.box(50, 22, 230, 128, INK.land, INK.land2)
        D.box(290, 40, 170, 100, INK.land, INK.land2)
        for i, pin in ipairs({ { 112, 58 }, { 170, 108 }, { 330, 74 }, { 380, 112 }, { 226, 70 } }) do
            D.art("orb", pin[1], pin[2], 14, CLASS[i + 1])
            D.art("ring", pin[1], pin[2], 16, INK.paper, 0.9)
        end
        if GuildOS.Onboarding and GuildOS.Onboarding.ClientKey() == "forever" then
            flame(206, 118, 0.7)
            flame(410, 72, 0.55)
        end
    elseif key == "bank" then
        D.box(206, 82, 100, 70, INK.brown, INK.metal2)
        D.box(206, 104, 100, 8, INK.metal2)
        D.art("disc", 256, 116, 14, INK.gold)
        for _, c in ipairs({ { 150, 130 }, { 176, 146 }, { 330, 140 }, { 352, 120 }, { 128, 150 } }) do
            D.art("disc", c[1], c[2], 16, INK.gold)
            D.art("ring", c[1], c[2], 16, INK.metal2)
        end
        flame(470, 156, 1)
    elseif key == "light" then
        D.art("halo", 160, 92, 140, INK.gold2, 0.25)
        D.box(124, 50, 72, 90, INK.tan, INK.metal2)
        D.lines(136, 66, 48, 5, INK.soft)
        D.art("mark-crest", 360, 92, 84)
        D.text("7d", 360, 150, 14, INK.gold2, "windowTitle")
    elseif key == "shield" then
        D.art("halo", 256, 90, 160, INK.gold2, 0.25)
        D.art("mark-crest", 256, 90, 96)
    elseif key == "compact" then
        D.box(60, 40, 392, 30, INK.dark, INK.metal)
        D.art("orb", 80, 55, 16, INK.red)
        D.box(96, 52, 140, 6, INK.tan)
        D.box(380, 52, 54, 6, INK.tan)
        D.box(60, 96, 180, 28, INK.dark, INK.metal)
        D.art("icon-search", 78, 110, 16, INK.soft)
        D.text("/guildos", 150, 110, 12, INK.soft)
    elseif key == "gm" then
        D.art("halo", 256, 70, 140, INK.gold2, 0.3)
        D.art("mark-banner", 256, 62, 70)
        D.box(206, 110, 100, 52, INK.brown, INK.metal2)
        D.box(206, 126, 100, 6, INK.metal2)
    elseif key == "departure" then
        D.box(140, 22, 232, 136, INK.paper, INK.paperLine)
        D.lines(158, 40, 150, 3, INK.paperLine)
        D.box(158, 92, 18, 18, INK.paper, INK.red)
        D.box(184, 98, 120, 5, INK.paperLine)
        D.box(290, 128, 66, 20, INK.red)
        D.art("mark-warn", 352, 40, 30)
        D.art("ring-dash", 440, 90, 70, INK.metal2, 0.5)
    end

    for i = p.nb + 1, #p.box do p.box[i]:Hide() end
    for i = p.nt + 1, #p.tex do p.tex[i]:Hide() end
    for i = p.nf + 1, #p.fs do p.fs[i]:Hide() end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local FULL_W, FULL_H, FULL_PIC = 560, 452, 180
local NARROW_W, NARROW_H, NARROW_PIC = 436, 480, 128
local PAD = 20

local function O() return GuildOS.Onboarding end

local function narrowNow()
    local win = GuildOS.RosterFrame
    if win and win:IsShown() and (win.band == "watch" or win.band == "narrow") then return true end
    local sw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1000
    return (tonumber(sw) or 1000) < 700
end

local function text(parent, size, color, role)
    local f = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f, size, role)
    f:SetShadowOffset(0, 0)
    f:SetTextColor(color.r, color.g, color.b)
    f:SetJustifyH("LEFT")
    f:SetJustifyV("TOP")
    return f
end

local function BuildFrame()
    local Kit = GuildOS.Kit
    local f = CreateFrame("Frame", "GuildOSOnboarding", UIParent, "BackdropTemplate")
    f:SetSize(FULL_W, FULL_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(50)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()
    Kit:Dress(f, L["What's new"], { onClose = function() f:Answer("later") end })
    Kit:Footer(f)

    f.pic = CreateFrame("Frame", nil, f)
    f.dots = {}
    f.cardTitle = text(f, UI.SP.TITLE + 2, C.gold2, "sectionTitle")
    f.cardTitle:SetWordWrap(true)
    f.tag = UI:CreateBadge(f, "", C.gold2)
    f.body = text(f, UI.SP.BODY, C.text, "reading")
    f.body:SetWordWrap(true)

    -- The welcome's two controls: the guild button's choice and the raid roles.
    local gb = UI:CreateCheckbox(f, L["Guild button opens Guild OS"], 18)
    gb.checkbox.onChanged = function(_, checked) GuildOS:SetSetting("hijackGuildButton", checked and true or false) end
    gb:Hide()
    f.gbToggle = gb
    local roles = GuildOS.CreateRolePicker and GuildOS:CreateRolePicker(f) or CreateFrame("Frame", nil, f)
    roles:Hide()
    f.rolePick = roles

    local foot = f.foot
    f.neverBtn = UI:SetButtonVariant(UI:CreateButton(foot, L["Don't show again"], 120, UI.SP.FIELD), "ghost")
    f.backBtn = UI:CreateButton(foot, L["Back"], 80, UI.SP.FIELD)
    f.laterBtn = UI:CreateButton(foot, L["Later"], 80, UI.SP.FIELD)
    f.nextBtn = UI:SetButtonVariant(UI:CreateButton(foot, L["Next"], 110, UI.SP.FIELD), "primary")
    f.neverBtn:SetScript("OnClick", function() f:Answer("never") end)
    f.backBtn:SetScript("OnClick", function() f:Go(-1) end)
    f.laterBtn:SetScript("OnClick", function() f:Answer("later") end)
    f.nextBtn:SetScript("OnClick", function() f:Go(1) end)

    -- Enter or Right: next; Left: back; Escape: Later. Every other key goes on to the game.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        local mine = key == "ENTER" or key == "RIGHT" or key == "LEFT" or key == "ESCAPE"
        if self.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
            self:SetPropagateKeyboardInput(not mine)
        end
        if not mine then return end
        if key == "ESCAPE" then self:Answer("later")
        elseif key == "LEFT" then self:Go(-1)
        else self:Go(1) end
    end)
    -- Closed any other way (a reload's hide does not count): as Later.
    f:SetScript("OnHide", function(self)
        if not self.answered and self.cards then self:Answer("later", true) end
    end)

    local function fit(b, min)
        b:SetWidth(math.max(min or 60, math.ceil(tonumber(b.label:GetStringWidth()) or 40) + 26))
    end

    function f:Render()
        local narrow = self.narrow
        local W, H = narrow and NARROW_W or FULL_W, narrow and NARROW_H or FULL_H
        local picH = narrow and NARROW_PIC or FULL_PIC
        self:SetSize(W, H)
        local inner = W - 2 * PAD
        local card = self.cards[self.i]
        local last = self.i == #self.cards
        local welcome = self.kind == "welcome"
        self:SetTitle(welcome and L["Welcome"] or L["What's new"],
            welcome and "Guild OS" or string.format(L["Guild OS %s"], L["2.0 \194\183 the Salão"]))
        local y = Kit.HEADER_H + 14
        self.pic:ClearAllPoints()
        self.pic:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
        self.pic:SetSize(inner, picH)
        Picture:Draw(self.pic, card.ill, inner, picH)
        y = y + picH + 12
        -- The cards as marks, the ones reached in the soft gold.
        local n = #self.cards
        local dw = math.floor((inner - (n - 1) * 4) / n)
        for i = 1, math.max(n, #self.dots) do
            local d = self.dots[i]
            if not d and i <= n then
                d = self:CreateTexture(nil, "ARTWORK")
                d:SetTexture(WHITE)
                d:SetHeight(4)
                self.dots[i] = d
            end
            if d then
                d:SetShown(i <= n)
                d:ClearAllPoints()
                d:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + (i - 1) * (dw + 4), -y)
                d:SetWidth(math.max(4, dw))
                local c = i <= self.i and C.gold2 or C.lineHi
                d:SetVertexColor(c.r, c.g, c.b, 1)
            end
        end
        y = y + 4 + 12
        self.tag:SetShown(card.tag ~= nil)
        local tagW = 0
        if card.tag then
            self.tag:SetText(card.tag)
            tagW = (tonumber(self.tag:GetWidth()) or 60) + 10
        end
        self.cardTitle:SetText(card.title)
        self.cardTitle:SetWidth(inner - tagW)
        self.cardTitle:ClearAllPoints()
        self.cardTitle:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
        if card.tag then
            self.tag:ClearAllPoints()
            self.tag:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -(y + 1))
        end
        local th = math.ceil(tonumber(self.cardTitle:GetStringHeight()) or 18)
        y = y + math.max(18, th) + 8
        self.body:SetText(card.body)
        self.body:SetWidth(inner)
        self.body:ClearAllPoints()
        self.body:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
        local bh = math.ceil(tonumber(self.body:GetStringHeight()) or 30)
        y = y + bh + 10
        self.gbToggle:SetShown(card.extra == "guildbutton")
        if card.extra == "guildbutton" then
            self.gbToggle.checkbox:SetChecked(GuildOS:IsGuildButtonHijacked())
            self.gbToggle:ClearAllPoints()
            self.gbToggle:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
            y = y + 24
        end
        self.rolePick:SetShown(card.extra == "roles")
        if card.extra == "roles" then
            if self.rolePick.refresh then self.rolePick.refresh() end
            self.rolePick:ClearAllPoints()
            self.rolePick:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
            y = y + 30
        end
        -- Taller in a language that needs it: the window grows downwards, never wider.
        local need = y + Kit.FOOT_H + 8
        if need > H then self:SetHeight(need) end
        self.neverBtn:SetShown(not welcome and not self.forced)
        self.backBtn:SetShown(self.i > 1)
        self.nextBtn.label:SetText(last and L["Take the tour"] or L["Next"])
        fit(self.nextBtn, 90); fit(self.laterBtn); fit(self.backBtn); fit(self.neverBtn, 40)
        self.neverBtn:ClearAllPoints()
        self.neverBtn:SetPoint("LEFT", self.foot, "LEFT", Kit.PAD - 3, -1)
        self.foot:Lay(self.nextBtn, self.laterBtn, self.backBtn)
    end

    function f:Go(dir)
        local i = self.i + dir
        if i < 1 then return end
        if i > #self.cards then return self:Answer("tour") end
        self.i = i
        self:Render()
    end

    -- "tour" (read to the end), "later" or "never".
    function f:Answer(what, hiding)
        if self.answered then return end
        self.answered = true
        local Ob = O()
        if what == "tour" then
            Ob:Seen()
        elseif what == "never" then
            Ob:Never()
        elseif not self.forced then
            Ob:Later()
            if UI.Tour then UI.Tour:OfferStart() end
        end
        if not hiding then self:Hide() end
        if what == "tour" and UI.Tour then
            GuildOS.Compat.After(0.1, function() UI.Tour:Start("member", "way") end)
        end
        if UI.Tour then UI.Tour:RefreshFooter() end
    end
    return f
end

-- Show the cards: `forced` when the player asked (Help, /gos whatsnew): "Later" then counts for nothing.
-- Returns the window.
function GuildOS:ShowWhatsNew(forced, kind)
    local Ob = O()
    if not Ob then return nil end
    if not self.onboardingFrame then self.onboardingFrame = BuildFrame() end
    local f = self.onboardingFrame
    f.kind = kind or Ob:Arrival()
    f.cards = Ob:Cards(f.kind)
    f.i, f.forced, f.answered = 1, forced and true or false, false
    f.narrow = narrowNow()
    f:Render()
    f:Show()
    return f
end

-- Kept for the callers that still ask: the window, as the player asked for it.
function GuildOS:ShowOnboarding()
    return self:ShowWhatsNew(true)
end

-- At login: what's new or the welcome, once a login, when nothing stands in the way. Inside an instance or
-- in a raid group it waits until the player is out (a zone change, a group change, the fight's end).
local waiter
local function queue()
    local Ob = O()
    GuildOS:ShowWhenClear("onboarding", function()
        if Ob.session.shown or not Ob:LoginKind() then return nil end
        if not Ob:Clear() then
            if waiter then
                waiter:RegisterEvent("ZONE_CHANGED_NEW_AREA")
                waiter:RegisterEvent("GROUP_ROSTER_UPDATE")
                waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            return nil
        end
        Ob.session.shown = true
        return GuildOS:ShowWhatsNew(false)
    end)
end

function GuildOS:MaybeShowOnboarding()
    if not IsInGuild() then return end
    local Ob = self.Onboarding
    if not Ob or Ob.session.shown or not Ob:LoginKind() then return end
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(w)
            if not Ob:Clear() then return end
            w:UnregisterAllEvents()
            queue()
        end)
    end
    queue()
end

-- Settings › Help's "Show tips again": the account's record forgotten, the cards at once.
GuildOS.Dialogs["GUILDOS_ONBOARD_RESET"] = {
    text = "%s", button1 = L["Show tips again"], button2 = L["Cancel"],
    OnAccept = function()
        if GuildOS.Onboarding then GuildOS.Onboarding:Reset() end
        if UI.Tour then UI.Tour:Stop() end
        if GuildOS.RosterFrame and GuildOS.RosterFrame.RefreshHelpDot then GuildOS.RosterFrame:RefreshHelpDot() end
        GuildOS:ShowWhatsNew(true)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The help's Settings button opens the window on the Help page.
function GuildOS:OpenHelp()
    return UI:OpenWindow("settings", "help")
end
