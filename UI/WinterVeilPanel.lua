----------------------------------------------------------------------
-- Guild OS - Winter Veil panel (issue #437; the site's specs/119, 121 and 122, guildos-web#673)
-- The approved prototype (specs/winter-veil/ui/prototipo-addon.html) in the game:
--   left        the Chimney (UI/VeilChimney.lua), always in view
--   Mine        joining; whom I drew, the scene and the note I wrap with (wrapped into a gift box); the wrapped box and
--               the countdown; from the opening on, the gift box I got, opened in one click (the click asks, Frimm
--               "goes to fetch it", and the ceremony plays once when the opened globe reaches this client and the tab
--               is in view); the result: who gave it, the note as a card, the caprice tag
--   Collection  the shelf (UI/VeilShelf.lua)
--   Chain       after the opening, who gave whom what, of the globes already opened
--   Organize    officers: who is in and who wrapped, never a pair
-- Visual layout only: the data, the rules and the requests are GuildOS.WinterVeil's (Rule 10). The rarity is the
-- site's, drawn when the receiver opens: this panel only asks and shows. Every effect is GuildOS.VeilFx's, counted,
-- clipped to the window and stopped when the tab hides or the "Winter Veil animations" option is off.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local Fx = GuildOS.VeilFx

local ROW_H = 26
local SITE = "guildos.me"
local MAIN_X = 276

local function rarityName(r)
    if r == "rare" then return L["Rare"] end
    if r == "epic" then return L["Epic"] end
    if r == "legendary" then return L["Legendary"] end
    return L["Common"]
end

local function baseName(r)
    if r == "rare" then return L["silver base"] end
    if r == "epic" then return L["gold base"] end
    if r == "legendary" then return L["crystal base"] end
    return L["wood base"]
end

local function sceneName(s)
    if s == "cabin" then return L["Cabin"] end
    if s == "snowman" then return L["Snowman"] end
    if s == "fire" then return L["Campfire"] end
    if s == "mountain" then return L["Mountain"] end
    return L["Tree"]
end

local function colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

local function nameOf(key)
    local short = type(key) == "string" and (key:match("^([^-]+)") or key) or "?"
    local rec = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    local cc = rec and rec.class and GuildOS.ClassColors and GuildOS.ClassColors[rec.class]
    return cc and colored(short, cc) or short
end

local function dayOf(t) return date("%d/%m", t) end

local function fromOf(o)
    return o.host and L["Frimm, the host"] or (o.from and nameOf(o.from) or "?")
end

local T = { sceneName = sceneName, rarityName = rarityName, baseName = baseName, nameOf = nameOf, dayOf = dayOf, fromOf = fromOf }

local function mono(fs, size, role)
    if GuildOS.ApplyFont then GuildOS:ApplyFont(fs, size, role or "caption") end
    return fs
end

-- A kicker: the mono uppercase line over a block.
local function kick(parent, text)
    return UI:CreateHeaderText(parent, text or "", UI.SP.META)
end

-- A pool of rows under `parent`, each a button with an optional globe on the left, a name and a value on the right.
local function rowPool(parent, withIcon)
    local rows = {}
    return function(i)
        local r = rows[i]
        if not r then
            r = CreateFrame("Button", nil, parent)
            r:SetHeight(ROW_H)
            if withIcon then
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(24, 24)
                r.icon:SetPoint("LEFT", 8, 0)
            end
            r.text = UI:CreateText(r, "", 12, C.text.r, C.text.g, C.text.b)
            r.text:SetPoint("LEFT", withIcon and 40 or 8, 0)
            r.text:SetJustifyH("LEFT")
            r.value = UI:CreateText(r, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            r.value:SetPoint("RIGHT", -8, 0)
            r.text:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
            r.sel = r:CreateTexture(nil, "BACKGROUND")
            r.sel:SetAllPoints()
            r.sel:SetColorTexture(C.popup.r, C.popup.g, C.popup.b, 1)
            r.rule = r:CreateTexture(nil, "BORDER")
            r.rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
            r.rule:SetPoint("BOTTOMLEFT")
            r.rule:SetPoint("BOTTOMRIGHT")
            r.rule:SetHeight(1)
            rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        r.sel:Hide()
        r:SetScript("OnClick", nil)
        r:Show()
        return r
    end, function(from)
        for i = from, #rows do rows[i]:Hide() end
    end
end

-- The page of this guild's event on the site: the key comes with the event (the guild's key is the site's to say), and
-- is encoded as the site encodes it. Without one, the public page, which at least exists.
local function siteLink()
    local e = GuildOS.WinterVeil and GuildOS.WinterVeil:Event()
    local key = e and e.guildKey
    if not key then return SITE .. "/winter-veil" end
    return string.format("%s/guild/%s/winter-veil", SITE, (key:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end)))
end

local function whyText(why)
    return L["Winter Veil: "] .. (
        why == "note" and L["that note is not allowed: up to 80 characters, no links, no @, no markdown."]
        or why == "phase" and L["the wrapping is closed."]
        or why == "companion" and L["wrap it on the site: this needs the companion."]
        or tostring(why))
end

local function countdown(left)
    left = math.max(0, left)
    local d, h, m = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60)
    if d > 0 then return string.format("%02dd %02dh", d, h) end
    return string.format("%02dh %02dm", h, m)
end

-- The gift box at `size` on `parent`: the closed box (ribbon and bow on, Media/Veil/giftbox) over the open one (the lid
-- off beside it, giftbox-open), and a loose bow and two strips of ribbon from the atlas, hidden, that fly off when it opens.
local function giftBox(parent, size)
    local big = size > 128
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local opened = f:CreateTexture(nil, "ARTWORK", nil, 1)
    opened:SetTexture(big and Fx.PATH.giftOpen256 or Fx.PATH.giftOpen)
    opened:SetAllPoints()
    local closed = f:CreateTexture(nil, "ARTWORK", nil, 2)
    closed:SetTexture(big and Fx.PATH.giftbox256 or Fx.PATH.giftbox)
    closed:SetAllPoints()
    local bow = Fx.Piece(f, "bow", size * 0.42, size * 0.21, "OVERLAY", false, nil, 0)
    bow:SetPoint("CENTER", f, "TOP", 0, -size * 0.2)
    local ribA = Fx.Piece(f, "ribbon", size * 0.08, size * 0.5, "OVERLAY", false, nil, 0)
    ribA:SetPoint("CENTER", f, "TOP", -size * 0.06, -size * 0.5)
    local ribB = Fx.Piece(f, "ribbon", size * 0.5, size * 0.08, "OVERLAY", false, nil, 0)
    ribB:SetPoint("CENTER", f, "TOP", size * 0.06, -size * 0.55)
    f.closed, f.opened, f.bow, f.ribA, f.ribB = closed, opened, bow, ribA, ribB
    -- Closed and still: the closed box at `alpha`, the open one and the loose pieces out of sight.
    function f:Reset(alpha)
        self.closed:SetAlpha(alpha or 1); self.closed:Show()
        self.opened:SetAlpha(0); self.opened:Show()
        for _, t in ipairs({ self.bow, self.ribA, self.ribB }) do t:SetAlpha(0); t:Show() end
    end
    f:Reset(1)
    return f
end

function GuildOS:CreateWinterVeilPanel(container)
    local WV = GuildOS.WinterVeil
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()
    panel:SetClipsChildren(true)
    local scope = Fx.Scope(panel)
    local view = "mine"
    local scene, pickedTo, formFor, editing = "tree", nil, nil, false
    local listTop = 0 -- the chain's and the officers' list: the first row shown
    local wrapping = false -- the wrap animation is running

    -- No event: one line, nothing else.
    local none = UI:CreateText(panel, L["The guild has not opened this year's Secret Santa yet. Officers open it on guildos.me."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    none:SetPoint("TOPLEFT", 0, -8)
    none:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    none:SetJustifyH("LEFT")

    -- The Chimney, on the left.
    local chimney = GuildOS.VeilChimney.Create(panel, scope)

    -- The rest, on the right.
    local main = CreateFrame("Frame", nil, panel)
    main:SetPoint("TOPLEFT", MAIN_X, 0)
    main:SetPoint("BOTTOMRIGHT", 0, 0)

    local title = UI:CreateTitle(main, L["Winter Veil Secret Santa"], 18)
    title:SetPoint("TOPLEFT", 0, -2)
    local sub = UI:CreateText(main, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local chipWrapped = UI:CreateMetricChip(main, "0", L["wrapped"])
    chipWrapped:SetPoint("TOPRIGHT", 0, -2)
    local chipIn = UI:CreateMetricChip(main, "0", L["taking part"])
    chipIn:SetPoint("TOPRIGHT", chipWrapped, "TOPLEFT", -16, 0)

    local tabs = {}
    local show
    local function addTab(id, text, anchor)
        local t = UI:CreateTab(main, text, 130, true)
        if anchor then t:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else t:SetPoint("TOPLEFT", 0, -56) end
        t:SetScript("OnClick", function()
            if view ~= id then Fx.Sound("tab"); listTop = 0; editing = false end
            view = id
            GuildOS:SafeCall(panel.Draw)
        end)
        tabs[id] = t
        return t
    end
    local tMine = addTab("mine", L["My secret friend"])
    local tColl = addTab("collection", L["Collection"], tMine)
    local tChain = addTab("chain", L["The guild's chain"], tColl)
    addTab("board", L["Organize"], tChain)

    local body = UI:CreatePanel(main)
    body:SetPoint("TOPLEFT", 0, -82)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    body:SetClipsChildren(true)

    -- The darkening of a legendary opening, over the body and under the stage.
    local dimFrame = CreateFrame("Frame", nil, body)
    dimFrame:SetAllPoints()
    local dimmer = dimFrame:CreateTexture(nil, "BACKGROUND")
    dimmer:SetAllPoints()
    dimmer:SetColorTexture(0, 0, 0, 1)
    dimmer:SetAlpha(0)

    local function section()
        local f = CreateFrame("Frame", nil, body)
        f:SetAllPoints()
        if f.SetFrameLevel and dimFrame.GetFrameLevel then
            local lvl = tonumber(dimFrame:GetFrameLevel())
            if lvl then f:SetFrameLevel(lvl + 2) end
        end
        return f
    end

    -- Frimm's toast, at the bottom of the right side.
    local toast = CreateFrame("Frame", nil, main)
    toast:SetSize(360, 60)
    toast:SetPoint("BOTTOMLEFT", 12, 10)
    do
        local bg = toast:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.popup.r, C.popup.g, C.popup.b, 1)
        Fx.Border(toast, C.gold, 1, 0)
    end
    toast.face = Fx.Frimm(toast, 44, "happy")
    toast.face:SetPoint("LEFT", 8, 0)
    toast.title = UI:CreateText(toast, "", 12, C.text.r, C.text.g, C.text.b)
    toast.title:SetPoint("TOPLEFT", toast.face, "TOPRIGHT", 10, -2)
    toast.body = UI:CreateText(toast, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -2)
    toast.body:SetWidth(280)
    toast.body:SetJustifyH("LEFT")
    toast:SetFrameLevel((tonumber(body:GetFrameLevel()) or 1) + 20)
    toast:Hide()
    local toastIn = scope:Group(toast, { { "alpha", 0, 1, 0.26 } }, { final = true, n = 1 })
    local toastOut = scope:Group(toast, { { "alpha", 1, 0, 0.4 } }, { final = true, n = 1, done = function() toast:Hide() end })
    panel:HookScript("OnHide", function() toast:Hide() end)
    local function sayToast(face, head, line)
        if not scope:Live() then return end
        toast.face:SetFace(face)
        toast.title:SetText(head)
        toast.body:SetText(line)
        toast:SetAlpha(0)
        toast:Show()
        toastOut:Stop()
        toastIn:Play()
        scope:After(4.2, function() toastOut:Play() end)
    end

    ------------------------------------------------------------------
    -- Mine
    ------------------------------------------------------------------
    local mine = section()
    local views = {}
    local function subview()
        local f = CreateFrame("Frame", nil, mine)
        f:SetAllPoints()
        f:Hide()
        views[#views + 1] = f
        return f
    end

    -- In-game participation (a quest of the event turned in): counts for the Chimney, kept by the addon or the site's block.
    local mPlay = UI:CreateText(mine, "", 11, C.label.r, C.label.g, C.label.b)
    mPlay:SetPoint("BOTTOMLEFT", 12, 12)
    mPlay:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mPlay:SetJustifyH("LEFT")
    -- A line for what is not one of the views (no pair yet, joining closed, no globe yet).
    local mLine = UI:CreateText(mine, "", 14, C.text.r, C.text.g, C.text.b)
    mLine:SetPoint("TOPLEFT", 12, -34)
    mLine:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mLine:SetJustifyH("LEFT")
    local mKicker = kick(mine, "")
    mKicker:SetPoint("TOPLEFT", 12, -12)
    local mNote = UI:CreateText(mine, "", 11, C.label.r, C.label.g, C.label.b)
    mNote:SetPoint("TOPLEFT", 12, -58)
    mNote:SetPoint("RIGHT", mine, "RIGHT", -12, 0)
    mNote:SetJustifyH("LEFT")

    -- Joining ----------------------------------------------------------
    local vJoin = subview()
    local jKick = kick(vJoin, "")
    jKick:SetPoint("TOPLEFT", 12, -12)
    local jFace = Fx.Frimm(vJoin, 72, "rush")
    jFace:SetPoint("TOPLEFT", 12, -30)
    local jSay = Fx.Bubble(vJoin, 420)
    jSay:SetPoint("TOPLEFT", jFace, "TOPRIGHT", 12, 0)
    local steps = {}
    for i = 1, 4 do
        local s = CreateFrame("Frame", nil, vJoin)
        s:SetHeight(48)
        local bg = s:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.well.r, C.well.g, C.well.b, 1)
        Fx.Border(s, C.line, 1, 0)
        s.when = mono(UI:CreateText(s, "", 11, C.gold.r, C.gold.g, C.gold.b), 11, "tableNum")
        s.when:SetPoint("TOPLEFT", 8, -7)
        s.what = UI:CreateText(s, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        s.what:SetPoint("TOPLEFT", s.when, "BOTTOMLEFT", 0, -3)
        s.what:SetPoint("RIGHT", s, "RIGHT", -8, 0)
        s.what:SetJustifyH("LEFT")
        steps[i] = s
    end
    for i, id in ipairs(WV.SCENES) do
        local b = CreateFrame("Button", nil, vJoin)
        b:SetSize(64, 64)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 72, -184)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexture(Fx.GlobePath(id, "common"))
        b:SetScript("OnEnter", function(btn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(sceneName(id), 1, 1, 1)
            local e = WV:Event()
            GameTooltip:AddLine(string.format(L["One of the five scenes of the %d globe."], e and e.year or 0), C.textSoft.r, C.textSoft.g, C.textSoft.b, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    local jCap = mono(UI:CreateText(vJoin, L["The five scenes. The rarity (a base of wood, silver, gold or crystal) only comes out at the opening."], UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    jCap:SetPoint("TOPLEFT", 12, -254)
    local volCheck = UI:CreateCheckbox(vJoin, L["I can give one more globe if somebody does not wrap"], 18)
    volCheck:SetPoint("TOPLEFT", 12, -280)
    local joinBtn = UI:CreateButton(vJoin, L["Join the Secret Santa"], 200, 28)
    joinBtn:SetPoint("TOPLEFT", 12, -310)
    UI:SetButtonVariant(joinBtn, "primary")

    -- Joined, before the draw ------------------------------------------
    local vJoined = subview()
    local inKick = kick(vJoined, L["YOU ARE IN"])
    inKick:SetPoint("TOPLEFT", 12, -12)
    inKick:SetTextColor(C.ok.r, C.ok.g, C.ok.b)
    local inFace = Fx.Frimm(vJoined, 72, "happy")
    inFace:SetPoint("TOPLEFT", 12, -30)
    local inSay = Fx.Bubble(vJoined, 420)
    inSay:SetPoint("TOPLEFT", inFace, "TOPRIGHT", 12, 0)
    local inLine = UI:CreateText(vJoined, L["Until then the Chimney stays out: it lights at the draw and warms up with every globe wrapped."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    inLine:SetPoint("TOPLEFT", 12, -120)
    inLine:SetPoint("RIGHT", vJoined, "RIGHT", -12, 0)
    inLine:SetJustifyH("LEFT")
    local leaveBtn = UI:CreateButton(vJoined, L["Leave"], 100, 28)
    leaveBtn:SetPoint("TOPLEFT", 12, -150)

    -- Wrapping ------------------------------------------------------------
    local vWrap = subview()
    local wKick = kick(vWrap, L["YOU DREW"])
    wKick:SetPoint("TOPLEFT", 12, -12)
    local wName = UI:CreateText(vWrap, "", 20, C.text.r, C.text.g, C.text.b)
    wName:SetPoint("TOPLEFT", 12, -28)
    -- The preview: the globe in the scene picked, and the gift box it is wrapped into.
    local pv = CreateFrame("Frame", nil, vWrap)
    pv:SetSize(192, 192)
    pv:SetPoint("TOPLEFT", 20, -74)
    local pvGlobe = pv:CreateTexture(nil, "ARTWORK")
    pvGlobe:SetAllPoints()
    local pvBox = giftBox(pv, 192)
    pvBox:SetPoint("TOPLEFT")
    pvBox:Hide()
    local pvCap = mono(UI:CreateText(vWrap, L["Preview. The rarity is drawn when they open the globe."], UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    pvCap:SetPoint("TOP", pv, "BOTTOM", 0, -6)
    pvCap:SetWidth(208)
    pvCap:SetJustifyH("CENTER")
    local pvPop = scope:Pop(pv, 1.04, 0.26, 1)

    local form = CreateFrame("Frame", nil, vWrap)
    form:SetPoint("TOPLEFT", 232, -74)
    form:SetPoint("BOTTOMRIGHT", -12, 12)
    local sKick = kick(form, L["THE SCENE"])
    sKick:SetPoint("TOPLEFT", 0, 0)
    local sceneBtns = {}
    for i, id in ipairs(WV.SCENES) do
        local b = CreateFrame("Button", nil, form)
        b:SetSize(84, 98)
        b.x = (i - 1) * 92
        b:SetPoint("TOPLEFT", b.x, -16)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.well.r, C.well.g, C.well.b, 1)
        b.border = Fx.Border(b, C.line, 1, 0)
        b.inner = Fx.Border(b, C.gold, 1, -1)
        b.globe = b:CreateTexture(nil, "ARTWORK")
        b.globe:SetSize(64, 64)
        b.globe:SetPoint("TOP", 0, -6)
        b.globe:SetTexture(Fx.GlobePath(id, "common"))
        b.label = UI:CreateText(b, sceneName(id), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        b.label:SetPoint("BOTTOM", 0, 7)
        b:SetScript("OnEnter", function(btn) btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", btn.x, -14) end)
        b:SetScript("OnLeave", function(btn) btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", btn.x, -16) end)
        b:SetScript("OnClick", function()
            if scene ~= id then Fx.Sound("pick"); pvPop:Play() end
            scene = id
            GuildOS:SafeCall(panel.Draw)
        end)
        sceneBtns[id] = b
    end
    local nKick = kick(form, L["THE NOTE"])
    nKick:SetPoint("TOPLEFT", 0, -128)
    local noteCount = mono(UI:CreateText(form, "", UI.SP.META, C.label.r, C.label.g, C.label.b), 10, "tableNum")
    noteCount:SetPoint("TOPRIGHT", form, "TOPLEFT", 452, -128)
    local noteBox = UI:CreateTextArea(form, 452, 54, { max = WV.NOTE_MAX, placeholder = L["A few words for them."] })
    noteBox:SetPoint("TOPLEFT", 0, -144)
    -- The meter: the note's length out of 80, a gold mark at 40 (the caprice, the site's §7).
    local meter = CreateFrame("Frame", nil, form)
    meter:SetSize(452, 4)
    meter:SetPoint("TOPLEFT", 0, -204)
    do
        local bg = meter:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.well.r, C.well.g, C.well.b, 1)
        Fx.Border(meter, C.line, 1, 1)
        local mark = meter:CreateTexture(nil, "OVERLAY")
        mark:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
        mark:SetSize(1, 12)
        mark:SetPoint("CENTER", meter, "LEFT", 452 * WV.CAPRICE_MIN / WV.NOTE_MAX, 0)
    end
    local meterFill = meter:CreateTexture(nil, "ARTWORK")
    meterFill:SetPoint("TOPLEFT")
    meterFill:SetPoint("BOTTOMLEFT")
    local capLine = mono(UI:CreateText(form, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    capLine:SetPoint("TOPLEFT", 0, -214)
    capLine:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    capLine:SetJustifyH("LEFT")
    local wrapBtn = UI:CreateButton(form, L["Wrap"], 110, 28)
    wrapBtn:SetPoint("TOPLEFT", 0, -236)
    UI:SetButtonVariant(wrapBtn, "primary")
    local formNote = mono(UI:CreateText(form, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    formNote:SetPoint("LEFT", wrapBtn, "RIGHT", 12, 0)
    formNote:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    formNote:SetJustifyH("LEFT")
    local giveRow = CreateFrame("Frame", nil, form)
    giveRow:SetPoint("TOPLEFT", 0, -272)
    giveRow:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    giveRow:SetHeight(ROW_H * 3)
    local giveRowAt, giveHide = rowPool(giveRow)

    -- The wrapping: the globe goes, the box comes over it, bounces, stars. About 1.1 s.
    local wrapFx = {
        scope:Group(pvGlobe, { { "alpha", 1, 0, 0.38 } }, { final = true, tag = "wrap" }),
        scope:Group(pvBox.closed, { { "alpha", 0, 1, 0.38 }, { "scale", 0.8, 1, 0.38 } }, { final = true, tag = "wrap" }),
    }
    local wrapPop = scope:Pop(pvBox, 1.08, 0.26, 1)
    wrapPop.tag = "wrap"
    local function playWrap(done)
        if not scope:Live() then done(); return end
        wrapping = true
        pvBox:Show()
        pvBox:Reset(0)
        pvGlobe:SetAlpha(1)
        for _, g in ipairs(wrapFx) do g:Play() end
        Fx.Sound("wrap")
        scope:After(0.5, function() wrapPop:Play() end, "wrap")
        scope:After(0.8, function() scope:Burst(pv, 96, 30, 8, { r = 1, g = 0.85, b = 0.54 }, 70) end, "wrap")
        scope:After(1.4, function() wrapping = false; done() end, "wrap")
    end

    -- Wrapped: the box and the countdown --------------------------------
    local vWrapped = subview()
    local wdKick = kick(vWrapped, L["WRAPPED"])
    wdKick:SetPoint("TOPLEFT", 12, -12)
    wdKick:SetTextColor(C.ok.r, C.ok.g, C.ok.b)
    local wdName = UI:CreateText(vWrapped, "", 20, C.text.r, C.text.g, C.text.b)
    wdName:SetPoint("TOPLEFT", 12, -28)
    local wdBox = giftBox(vWrapped, 192)
    wdBox:SetPoint("TOPLEFT", 20, -74)
    local wdBob = scope:Group(wdBox, { { "move", 0, 3, 1.3 } }, { loop = "BOUNCE", smooth = "IN_OUT", n = 5 })
    local wdCard = Fx.Card(vWrapped, 300)
    wdCard:SetPoint("TOPLEFT", 244, -80)
    local wdNoNote = UI:CreateText(vWrapped, L["(no note)"], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    wdNoNote:SetPoint("TOPLEFT", 244, -80)
    local wdCount = mono(UI:CreateText(vWrapped, "", 38, C.text.r, C.text.g, C.text.b), 38, "countdown")
    wdCount:SetPoint("TOPLEFT", 244, -150)
    local wdUntil = mono(UI:CreateText(vWrapped, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    wdUntil:SetPoint("TOPLEFT", wdCount, "BOTTOMLEFT", 0, -4)
    local wdFace = Fx.Frimm(vWrapped, 44, "happy")
    wdFace:SetPoint("TOPLEFT", 244, -222)
    local wdSay = Fx.Bubble(vWrapped, 340)
    wdSay:SetPoint("LEFT", wdFace, "RIGHT", 12, 0)
    wdSay:Say(nil, L["Double ribbon. No shaking it before the time."])
    local rewrapBtn = UI:CreateButton(vWrapped, L["Wrap again"], 140, 28)
    rewrapBtn:SetPoint("TOPLEFT", 244, -284)
    rewrapBtn:SetScript("OnClick", function() editing = true; formFor = nil; GuildOS:SafeCall(panel.Draw) end)
    local wdClosed = UI:CreateText(vWrapped, "", 11, C.label.r, C.label.g, C.label.b)
    wdClosed:SetPoint("TOPLEFT", 244, -284)
    wdClosed:SetPoint("RIGHT", vWrapped, "RIGHT", -12, 0)
    wdClosed:SetJustifyH("LEFT")

    -- The opening -------------------------------------------------------
    local vOpen = subview()
    local oKick = kick(vOpen, L["YOUR GLOBE"])
    oKick:SetPoint("TOPLEFT", 12, -12)
    local stage = CreateFrame("Frame", nil, vOpen)
    stage:SetSize(300, 330)
    stage:SetPoint("TOPLEFT", 20, -44)
    local CX, CY = 150, 150 -- the globe's centre in the stage
    local fxAt = CreateFrame("Frame", nil, stage)
    fxAt:SetSize(1, 1)
    fxAt:SetPoint("CENTER", stage, "TOPLEFT", CX, -CY)
    local rays1, rays1G = scope:Rays(fxAt, 420, { r = 1, g = 0.67, b = 0.27 }, 0, 22)
    local rays2, rays2G = scope:Rays(fxAt, 420, { r = 0.63, g = 0.91, b = 1 }, 0, -31)
    rays1G.tag, rays2G.tag = "open", "open"
    local og = CreateFrame("Frame", nil, stage)
    og:SetSize(256, 256)
    og:SetPoint("TOPLEFT", 22, -22)
    local sceneA = og:CreateTexture(nil, "ARTWORK", nil, 1)
    sceneA:SetAllPoints()
    local sceneB = og:CreateTexture(nil, "ARTWORK", nil, 2)
    sceneB:SetAllPoints()
    sceneB:SetAlpha(0)
    local frosted = og:CreateTexture(nil, "ARTWORK", nil, 3)
    frosted:SetAllPoints()
    frosted:SetTexture(Fx.GlobePath(nil, nil, true))
    local obox = giftBox(og, 256)
    obox:SetPoint("TOPLEFT")
    obox:SetFrameLevel((tonumber(og:GetFrameLevel()) or 1) + 1)
    local swirl = {}
    for i = 1, 4 do
        local t = og:CreateTexture(nil, "OVERLAY")
        t:SetTexture(Fx.PATH.atlas)
        t:SetTexCoord(Fx.SnowCoords(i))
        t:SetSize(200, 200)
        t:SetPoint("CENTER", og, "TOPLEFT", 128, -100)
        t:SetAlpha(0)
        swirl[i] = t
    end
    local ring1 = scope:Ring(fxAt, 150)
    local ring2 = scope:Ring(fxAt, 150)
    -- The flash goes over the globe; the rings and rays stay behind it, as in the prototype.
    local fxTop = CreateFrame("Frame", nil, stage)
    fxTop:SetSize(1, 1)
    fxTop:SetPoint("CENTER", stage, "TOPLEFT", CX, -CY)
    fxTop:SetFrameLevel((tonumber(og:GetFrameLevel()) or 1) + 3)
    local flash = Fx.Piece(fxTop, "flash", 320, 320, "OVERLAY", true, nil, 0)
    flash:SetPoint("CENTER")
    local dust = {}
    do
        local r = Fx.Rng(31)
        for i = 1, 8 do
            local t = Fx.Piece(stage, "flake", 4, 4, "OVERLAY", true, { r = 1, g = 0.886, b = 0.65 }, 0)
            t:SetPoint("CENTER", stage, "TOPLEFT", 60 + r() * 180, -(40 + r() * 60))
            local dur = 2.4 + r() * 2
            dust[i] = { tex = t, g = scope:Group(t, { { "move", (r() - 0.5) * 30, -150, dur }, { "alpha", 0, 0.9, dur * 0.15 }, { "alpha", 0.9, 0, dur * 0.85, dur * 0.15 } }, { loop = "REPEAT", tag = "open" }) }
        end
    end
    -- The ceremony's groups, made once.
    local O = { tag = "open" }
    local function grp(region, stepsList, opts)
        opts = opts or {}
        opts.tag = "open"
        return scope:Group(region, stepsList, opts)
    end
    -- The ribbon falls (the bow and two strips fly off the box as it shakes), the lid comes off (the closed box gives way
    -- to the open one), the frosted globe rises out of it.
    O.bow = grp(obox.bow, { { "alpha", 0, 1, 0.01 }, { "move", -40, 30, 0.6 }, { "turn", 50, 0.6 }, { "scale", 1, 1.2, 0.6 }, { "alpha", 1, 0, 0.45, 0.15 } }, { final = true, smooth = "OUT" })
    O.ribA = grp(obox.ribA, { { "alpha", 0, 1, 0.01 }, { "move", 30, -100, 0.7 }, { "turn", -24, 0.7 }, { "alpha", 1, 0, 0.5, 0.2 } }, { final = true, smooth = "IN" })
    O.ribB = grp(obox.ribB, { { "alpha", 0, 1, 0.01 }, { "move", -10, -90, 0.65 }, { "turn", 14, 0.65 }, { "alpha", 1, 0, 0.45, 0.2 } }, { final = true, smooth = "IN" })
    O.boxShake = grp(obox.closed, { { "turn", 9, 0.13, 0, 1, { "BOTTOM", 0, 0 } }, { "turn", -17, 0.13, 0, 2, { "BOTTOM", 0, 0 } }, { "turn", 14, 0.13, 0, 3, { "BOTTOM", 0, 0 } }, { "turn", -6, 0.13, 0, 4, { "BOTTOM", 0, 0 } } })
    O.lidOff = grp(obox.closed, { { "alpha", 1, 0, 0.3 } }, { final = true })
    O.boxOpen = grp(obox.opened, { { "alpha", 0, 1, 0.3 } }, { final = true })
    O.boxGone = grp(obox.opened, { { "alpha", 1, 0, 0.5, 0.3 } }, { final = true })
    O.rise = grp(frosted, { { "alpha", 0, 1, 0.3 }, { "move", 0, -40, 0.01 }, { "move", 0, 40, 0.5, 0, 2 } }, { final = true, smooth = "OUT" })
    O.unfog = grp(frosted, { { "alpha", 1, 0, 0.8 } }, { final = true })
    O.swirl = {}
    for i = 1, 4 do
        local seq, d = {}, 0
        for _, k in ipairs({ 1, 2, 3, 4, 3, 2, 1 }) do
            if k == i then seq[#seq + 1] = { "alpha", 0, 1, 0.065, d }; seq[#seq + 1] = { "alpha", 1, 0, 0.065, d + 0.065 } end
            d = d + 0.13
        end
        O.swirl[i] = grp(swirl[i], seq, { final = true })
    end
    O.trem = {}
    local function tremble(amp)
        local key = string.format("%.1f", amp)
        if not O.trem[key] then O.trem[key] = grp(og, { { "move", amp, 0, 0.035 }, { "move", -2 * amp, 0, 0.07, 0, 2 }, { "move", amp, 0, 0.035, 0, 3 } }, { loop = "REPEAT", n = 4 }) end
        return O.trem[key]
    end
    O.ring = grp(ring1, { { "scale", 0.5, 2.1, 0.62 }, { "alpha", 1, 0, 0.62 } }, { final = true, smooth = "OUT" })
    O.ringBig = grp(ring1, { { "scale", 0.5, 3, 0.9 }, { "alpha", 1, 0, 0.9 } }, { final = true, smooth = "OUT" })
    O.ring2 = grp(ring2, { { "scale", 0.4, 3.6, 1.2, 0.12 }, { "alpha", 0.9, 0, 1.2, 0.12 } }, { final = true, smooth = "OUT" })
    O.flash = grp(flash, { { "alpha", 0, 0.75, 0.14 }, { "alpha", 0.75, 0, 0.34, 0.14 }, { "scale", 0.6, 1.2, 0.48 } }, { final = true })
    O.flashBig = grp(flash, { { "alpha", 0, 1, 0.27 }, { "alpha", 1, 0, 0.63, 0.27 }, { "scale", 0.6, 1.6, 0.9 } }, { final = true })
    O.swap = grp(sceneB, { { "alpha", 0, 1, 0.16 } }, { final = true })
    O.pop = grp(og, { { "scale", 1, 1.06, 0.15 }, { "scale", 1, 1 / 1.06, 0.15, 0, 2 } }, { n = 3 })
    O.popBig = grp(og, { { "scale", 1, 1.12, 0.15 }, { "scale", 1, 1 / 1.12, 0.15, 0, 2 } }, { n = 3 })
    O.dimIn = grp(dimmer, { { "alpha", 0, 0.62, 0.5 } }, { final = true })
    O.dimOut = grp(dimmer, { { "alpha", 0.62, 0.3, 1.2 } }, { final = true })
    O.rays1In = grp(rays1, { { "alpha", 0, 0.8, 0.9 } }, { final = true, n = 0 })
    O.rays2In = grp(rays2, { { "alpha", 0, 0.55, 0.9 } }, { final = true, n = 0 })

    -- The info column.
    local info = CreateFrame("Frame", nil, vOpen)
    info:SetPoint("TOPLEFT", 340, -40)
    info:SetPoint("BOTTOMRIGHT", -16, 12)
    local iHead = UI:CreateText(info, "", 18, C.text.r, C.text.g, C.text.b)
    iHead:SetPoint("TOPLEFT")
    iHead:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    iHead:SetJustifyH("LEFT")
    local iSoft = UI:CreateText(info, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    iSoft:SetPoint("TOPLEFT", iHead, "BOTTOMLEFT", 0, -8)
    iSoft:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    iSoft:SetJustifyH("LEFT")
    local openBtn = UI:CreateButton(info, L["Open the globe"], 160, 28)
    openBtn:SetPoint("TOPLEFT", iSoft, "BOTTOMLEFT", 0, -12)
    UI:SetButtonVariant(openBtn, "primary")
    local iFace = Fx.Frimm(info, 56, "rush")
    iFace:SetPoint("TOPLEFT", 0, 0)
    local iSay = Fx.Bubble(info, 250)
    iSay:SetPoint("LEFT", iFace, "RIGHT", 12, 0)
    local iFaceBob = scope:Group(iFace, { { "move", 0, 3, 1.3 } }, { loop = "BOUNCE", smooth = "IN_OUT", tag = "open" })
    local iCap = mono(UI:CreateText(info, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    iCap:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -10)
    iCap:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    iCap:SetJustifyH("LEFT")
    -- The result.
    local rName = UI:CreateText(info, "", 26, C.text.r, C.text.g, C.text.b)
    rName:SetPoint("TOPLEFT")
    local rSub = UI:CreateText(info, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    rSub:SetPoint("TOPLEFT", rName, "BOTTOMLEFT", 0, -8)
    local rFrom = UI:CreateText(info, "", 16, C.text.r, C.text.g, C.text.b)
    rFrom:SetPoint("TOPLEFT", rSub, "BOTTOMLEFT", 0, -12)
    local rCard = Fx.Card(info, 300)
    rCard:SetPoint("TOPLEFT", rFrom, "BOTTOMLEFT", 0, -14)
    local tags = CreateFrame("Frame", nil, info)
    tags:SetSize(320, 18)
    local function tag(text, gold)
        local f = CreateFrame("Frame", nil, tags)
        f:SetHeight(18)
        local c = gold and C.gold or C.line
        Fx.Border(f, c, 1, 0)
        f.text = mono(UI:CreateText(f, text, UI.SP.META, gold and C.gold.r or C.textSoft.r, gold and C.gold.g or C.textSoft.g, gold and C.gold.b or C.textSoft.b))
        f.text:SetPoint("LEFT", 6, 0)
        f:SetWidth((tonumber(f.text:GetStringWidth()) or 120) + 12)
        return f
    end
    local tagFull = tag(L["Chimney full: double odds"], true)
    tagFull:SetPoint("TOPLEFT")
    local tagCaprice = tag(L["caprice note: drawn twice"], false)
    local rBadges = mono(UI:CreateText(info, "", UI.SP.META, C.gold.r, C.gold.g, C.gold.b))
    rBadges:SetPoint("TOPLEFT", tags, "BOTTOMLEFT", 0, -6)
    local keepBtn = UI:CreateButton(info, L["See it in the Collection"], 180, 28)
    UI:SetButtonVariant(keepBtn, "primary")
    keepBtn:SetScript("OnClick", function() view = "collection"; Fx.Sound("tab"); GuildOS:SafeCall(panel.Draw) end)
    local rMine = mono(UI:CreateText(info, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b))
    rMine:SetPoint("BOTTOMLEFT", 0, 0)
    rMine:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    rMine:SetJustifyH("LEFT")
    local resultParts = { rName, rSub, rFrom, rCard, tags, keepBtn, rBadges }
    -- What the giver left on the box (up to two clues) and whom I guessed on the site: hidden when the block has none.
    local iClues = UI:CreateText(info, "", 12, C.text.r, C.text.g, C.text.b)
    iClues:SetPoint("TOPLEFT", iCap, "BOTTOMLEFT", 0, -14)
    iClues:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    iClues:SetJustifyH("LEFT")
    iClues:Hide()
    local readyParts = { iHead, iSoft, openBtn, iCap }
    local waitParts = { iFace, iSay }

    local cer = { playing = false }
    local function stageClosed()
        scope:StopTag("open")
        dimmer:SetAlpha(0)
        rays1:SetAlpha(0); rays2:SetAlpha(0)
        ring1:SetAlpha(0); ring2:SetAlpha(0); flash:SetAlpha(0)
        for _, d in ipairs(dust) do d.tex:SetAlpha(0) end
        for _, t in ipairs(swirl) do t:SetAlpha(0) end
        obox:Show()
        obox:Reset(1)
        -- Before it opens the receiver sees the box and nothing of the globe (the site's §9).
        frosted:SetAlpha(0)
        sceneA:SetAlpha(0)
        sceneB:SetAlpha(0)
    end
    -- The globe as it ends: the scene in its rarity, with rays (epic: one, legendary: two) and gold dust (legendary).
    local function stageOpen(o)
        obox:Hide()
        frosted:SetAlpha(0)
        sceneA:SetTexture(Fx.GlobePath(o.scene, o.rarity, true))
        sceneA:SetAlpha(1)
        sceneB:SetAlpha(0)
        local leg, epic = o.rarity == "legendary", o.rarity == "epic"
        if epic then local ep = Fx.Rarity("epic").text; rays1:SetVertexColor(ep.r, ep.g, ep.b); rays1:SetAlpha(0.6) end
        if leg then rays1:SetVertexColor(1, 0.67, 0.27); rays1:SetAlpha(0.8); rays2:SetAlpha(0.55) end
        rays1:SetShown(leg or epic)
        rays2:SetShown(leg)
        if (leg or epic) then rays1G:Play() end
        if leg then rays2G:Play() end
        for _, d in ipairs(dust) do
            d.tex:SetShown(leg)
            if leg then d.g:Play() end
        end
    end
    local function showParts(list, on) for _, p in ipairs(list) do p:SetShown(on) end end

    local function showResult(o, e, animate)
        showParts(readyParts, false)
        showParts(waitParts, false)
        showParts(resultParts, true)
        oKick:SetText(L["YOUR GLOBE"] .. " · " .. sceneName(o.scene))
        local rc = Fx.Rarity(o.rarity)
        local nm = rarityName(o.rarity)
        rName:SetText(o.rarity == "legendary" and nm:upper() or nm)
        rName:SetTextColor(rc.text.r, rc.text.g, rc.text.b)
        rSub:SetText(sceneName(o.scene) .. " · " .. baseName(o.rarity) .. " · Winter Veil " .. o.year)
        rFrom:SetText(string.format(L["From %s"], fromOf(o)))
        local hasNote = o.note ~= nil and o.note ~= ""
        rCard:SetShown(hasNote)
        if hasNote then rCard:SetNote(o.note) end
        tags:ClearAllPoints()
        tags:SetPoint("TOPLEFT", hasNote and rCard or rFrom, "BOTTOMLEFT", 0, -14)
        local full = e and (tonumber(e.chimney) or 0) >= 100
        tagFull:SetShown(full)
        -- Frimm's globes always count as a caprice note (the site's §7).
        local capr = o.caprice == true or o.host == true
        tagCaprice:SetShown(capr)
        tagCaprice:ClearAllPoints()
        if full then tagCaprice:SetPoint("LEFT", tagFull, "RIGHT", 6, 0) else tagCaprice:SetPoint("TOPLEFT") end
        keepBtn:ClearAllPoints()
        rBadges:SetShown(o.badges ~= nil)
        rBadges:SetText(o.badges and string.format(L["Badges: %s"], table.concat(o.badges, " · ")) or "")
        keepBtn:SetPoint("TOPLEFT", tags, "BOTTOMLEFT", 0, ((full or capr) and -12 or 6) - (o.badges and 18 or 0))
        if animate then
            for i, p in ipairs({ rFrom, rCard, tags, keepBtn, rMine }) do scope:Reveal(p, 0.25 + (i - 1) * 0.26) end
        end
    end

    -- The ceremony: once, when the opened globe is here and the tab is in view (the site's §9, specs/122).
    local function playCeremony(o, e)
        cer.playing, cer.id = true, o.id
        stageClosed()
        showParts(readyParts, false)
        showParts(waitParts, false)
        showParts(resultParts, false)
        rName:Show()
        rName:SetText("…")
        rName:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b)
        local target = Fx.Rarity(o.rarity).step
        local list = {}
        local function add(wait, fn) list[#list + 1] = { wait = wait, fn = fn } end
        -- The ribbon falls, the lid comes off, the glass clears: none of it depends on the rarity.
        add(0.55, function() Fx.Sound("shake"); O.boxShake:Play(); O.bow:Play(); O.ribA:Play(); O.ribB:Play() end)
        add(0.35, function() O.lidOff:Play(); O.boxOpen:Play() end)
        add(0.85, function() frosted:SetAlpha(0); O.rise:Play(); O.boxGone:Play() end)
        add(0.9, function()
            obox:Hide()
            sceneA:SetTexture(Fx.GlobePath(o.scene, "common", true))
            sceneA:SetAlpha(1)
            frosted:SetAlpha(1)
            O.unfog:Play()
            for _, g in ipairs(O.swirl) do g:Play() end
            oKick:SetText(L["YOUR GLOBE"] .. " · " .. sceneName(o.scene))
        end)
        local function trem(ms, amp)
            add(0, function() tremble(amp):Play() end)
            add(ms / 1000, function() tremble(amp):Stop() end)
        end
        local function pulse(k, big)
            local rar = Fx.RARITY_ORDER[k + 1]
            local c = Fx.Rarity(rar).text
            add(0, function()
                ring1:SetVertexColor(c.r, c.g, c.b)
                flash:SetVertexColor(c.r, c.g, c.b)
                if big then O.ringBig:Play(); ring2:SetVertexColor(1, 1, 1); O.ring2:Play(); O.flashBig:Play(); O.popBig:Play()
                else O.ring:Play(); O.flash:Play(); O.pop:Play() end
                sceneB:SetTexture(Fx.GlobePath(o.scene, rar, true))
                O.swap:Play()
                rName:SetText(rarityName(rar))
                rName:SetTextColor(c.r, c.g, c.b)
                scope:Burst(stage, CX, CY, big and 18 or 5 + k * 3, c, big and 190 or 110, false)
                Fx.Sound("step")
            end)
            add(0.17, function() sceneA:SetTexture(Fx.GlobePath(o.scene, rar, true)); sceneB:SetAlpha(0) end)
        end
        trem(650, 1.5)
        pulse(0, false)
        for k = 1, target do
            if k == 3 then
                add(0, function()
                    O.dimIn:Play()
                    rays1:SetVertexColor(1, 0.67, 0.27); rays1:Show(); rays2:Show()
                    O.rays1In:Play(); O.rays2In:Play(); rays1G:Play(); rays2G:Play()
                end)
                trem(1300, 3.5)
                pulse(3, true)
                add(0.9, function() O.dimOut:Play() end)
            else
                trem(420 + k * 220, 1.5 + k * 0.6)
                pulse(k, false)
            end
        end
        if target < 3 then trem(520, 1.2) end
        add(target == 3 and 0.5 or 0.15, function() end)
        add(0, function()
            cer.playing = false
            WV:MarkSeen("open:" .. o.id)
            stageOpen(o)
            if target < 3 then dimmer:SetAlpha(0) end
            Fx.Sound(target >= 2 and "big" or "reveal")
            showResult(o, e, true)
        end)
        local i = 0
        local function nextStep()
            i = i + 1
            local s = list[i]
            if not s then return end
            s.fn()
            if s.wait > 0 then
                if not scope:After(s.wait, nextStep, "open") then cer.playing = false end
            else
                nextStep()
            end
        end
        nextStep()
    end
    -- A ceremony cut short (the tab or the window hid, the sub-tab changed) starts again from the box next time.
    local function abortCeremony()
        if cer.playing then cer.playing = false end
        scope:StopTag("open")
        dimmer:SetAlpha(0)
    end
    panel:HookScript("OnHide", abortCeremony)

    ------------------------------------------------------------------
    -- Collection: the shelf
    ------------------------------------------------------------------
    local coll = section()
    local cTitle = kick(coll, "")
    cTitle:SetPoint("TOPLEFT", 12, -12)
    local shelf = GuildOS.VeilShelf.Create(coll, scope, T)

    ------------------------------------------------------------------
    -- Chain and officers' table
    ------------------------------------------------------------------
    -- The chain and the officers' table (Organize) on a dark card of their own, never straight on the wood (#449).
    local chainHost = section()
    local chain
    if UI.CreateCard then
        chain = UI:CreateCard(chainHost, "", { dark = true })
        chain.title:Hide()
    else
        chain = CreateFrame("Frame", nil, chainHost)   -- a harness without the shared card
    end
    chain:SetAllPoints()
    local PADV = UI.SP.PAD
    local chTitle = UI:CreateSectionTitle(chain, "", true)
    chTitle:SetPoint("TOPLEFT", PADV, -PADV)
    local chNote = UI:CreateText(chain, "", UI.SP.META, C.label.r, C.label.g, C.label.b)
    chNote:SetPoint("TOPLEFT", PADV, -(PADV + UI.SP.TITLE_H + UI.SP.TITLE_GAP))
    chNote:SetPoint("RIGHT", chain, "RIGHT", -PADV, 0)
    chNote:SetJustifyH("LEFT")
    local chList = CreateFrame("Frame", nil, chain)
    chList:SetPoint("TOPLEFT", PADV, -(PADV + UI.SP.TITLE_H + UI.SP.TITLE_GAP + 16 + UI.SP.FIELD_GAP))
    chList:SetPoint("BOTTOMRIGHT", -PADV, PADV)
    local chRow, chHide = rowPool(chList, true)
    local chPage = mono(UI:CreateText(chain, "", UI.SP.META, C.labelDim.r, C.labelDim.g, C.labelDim.b), UI.SP.META, "tableNum")
    chPage:SetPoint("TOPRIGHT", chain, "TOPRIGHT", -PADV, -PADV)
    -- Hundreds of rows (the officers' table holds up to a thousand): the wheel moves through them, a row at a time.
    chList:EnableMouseWheel(true)
    chList:SetScript("OnMouseWheel", function(_, delta)
        listTop = math.max(0, listTop - delta * 3)
        GuildOS:SafeCall(panel.Draw)
    end)

    local shownSection
    function show(which)
        if shownSection ~= which then
            if shownSection == "mine" then abortCeremony(); scope:StopTag("wrap"); wrapping = false end
            if shownSection == "collection" then scope:StopTag("shelf") end
            shownSection = which
        end
        mine:SetShown(which == "mine")
        coll:SetShown(which == "collection")
        chainHost:SetShown(which == "chain" or which == "board")
    end
    local function only(v) for _, f in ipairs(views) do f:SetShown(f == v) end end

    local draw
    local function drawOpen(e, gives, got)
        only(vOpen)
        local g = gives[1]
        local o = got and got.ornament
        local mineLines = {}
        if got and got.guess then
            local right = o and o.from and o.from == got.guess
            mineLines[#mineLines + 1] = string.format(L["Your guess: %s"], nameOf(got.guess)) .. (right and ("  " .. colored(L["right!"], C.ok)) or "")
        end
        if g and g.rarity then
            mineLines[#mineLines + 1] = string.format(L["Yours for %s was %s."], nameOf(g.to), colored(rarityName(g.rarity), Fx.Rarity(g.rarity).text))
        end
        if g and g.thanks and g.thanks ~= "" then
            mineLines[#mineLines + 1] = string.format(L["%s thanked you: \"%s\""], nameOf(g.to), g.thanks)
        end
        rMine:SetText(table.concat(mineLines, "\n"))
        local clues = {}
        if got and got.clues then
            clues[1] = colored(L["CLUES FROM WHOEVER WRAPPED IT"], C.label)
            for _, c in ipairs(got.clues) do clues[#clues + 1] = "\"" .. c .. "\"" end
        end
        iClues:SetText(table.concat(clues, "\n"))
        iClues:SetShown(not o and #clues > 0)
        if o then
            if cer.playing and cer.id == o.id then return end
            if not WV:Seen("open:" .. o.id) then
                if scope:Live() then playCeremony(o, e); return end
                -- Seen with the option off: no ceremony, and it does not wait for one either.
                if panel:IsVisible() == true then WV:MarkSeen("open:" .. o.id) end
            end
            stageOpen(o)
            showResult(o, e, false)
            return
        end
        abortCeremony()
        stageClosed()
        showParts(resultParts, false)
        oKick:SetText(L["YOUR GLOBE"])
        if got and got.ready then
            if WV:OpenRequested() then
                -- Frimm went to fetch it: the ceremony waits for the companion's next sync.
                showParts(readyParts, false)
                showParts(waitParts, true)
                iFace:SetFace("rush")
                iSay:Say(L["FRIMM"], L["Went to fetch it from the site. Be right back!"])
                iFaceBob:Play()
                tremble(1):Play()
                openBtn:Show()
                openBtn:ClearAllPoints()
                openBtn:SetPoint("TOPLEFT", iFace, "BOTTOMLEFT", 0, -16)
                openBtn:SetText(L["Asked: waiting for the site"])
                openBtn:SetEnabled(false)
                iCap:Show()
                iCap:SetText(L["In the game: until the companion's next sync (1 to 5 min). The ceremony waits for the answer and plays once."]
                    .. "\n" .. L["Sync the companion to see it here, or open it on the site."])
            else
                showParts(waitParts, false)
                showParts(readyParts, true)
                iHead:SetText(L["Somebody in the guild wrapped a globe for you."])
                iSoft:SetText(L["The rarity is drawn by the site when you open it. The game only asks and shows."])
                openBtn:ClearAllPoints()
                openBtn:SetPoint("TOPLEFT", iSoft, "BOTTOMLEFT", 0, -12)
                openBtn:SetText(L["Open the globe"])
                openBtn:SetEnabled(WV:HasCompanion())
                iCap:SetText(WV:HasCompanion() and "" or string.format(L["Open it on the site: %s"], siteLink()))
                openBtn:SetScript("OnClick", function()
                    local ok, why = WV:RequestOpen()
                    if not ok then GuildOS:Print(whyText(why)) end
                    Fx.Sound("pick")
                    GuildOS:SafeCall(draw)
                end)
            end
        else
            showParts(waitParts, false)
            showParts(readyParts, false)
            obox:Hide()
            frosted:SetAlpha(0)
            iHead:Show()
            iHead:SetText(L["There is no globe for you to open yet."])
            iSoft:Show()
            iSoft:SetText(string.format(L["Open it on the site: %s"], siteLink()))
        end
    end

    local function drawJoin(e, phase)
        if phase == "joining" then
            only(vJoin)
            jKick:SetText(string.format(L["SECRET SANTA · JOINING UNTIL %s"], dayOf(e.joinUntil - 1)))
            jSay:Say(L["FRIMM, THE WRAPPER"], L["The workshop is open! Join the guild's Secret Santa and pick your globe. I wrap, you only need to want it."])
            local W = (tonumber(body:GetWidth()) or 700) - 24
            local sw = math.floor((W - 24) / 4)
            local texts = {
                { string.format(L["until %s"], dayOf(e.joinUntil - 1)), L["Join. One per player."] },
                { dayOf(e.joinUntil), L["The draw: you get somebody."] },
                { string.format(L["until %s"], dayOf(e.wrapUntil - 1)), L["Pick the scene, write the note, wrap."] },
                { dayOf(e.openAt), L["Open your globe and find out its rarity."] },
            }
            for i, s in ipairs(steps) do
                s:SetWidth(sw)
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", 12 + (i - 1) * (sw + 8), -118)
                s.when:SetText(texts[i][1])
                s.what:SetText(texts[i][2])
            end
            joinBtn:SetScript("OnClick", function()
                WV:Join(volCheck.checkbox:GetChecked())
                Fx.Sound("pick")
                GuildOS:SafeCall(draw)
            end)
        else
            only(nil)
            mKicker:SetText(L["SECRET SANTA"])
            mLine:SetText(L["Joining has closed."])
        end
    end

    local function drawJoined(e, phase)
        only(vJoined)
        inSay:Say(L["FRIMM"], string.format(L["Noted! The draw is on %s. I shuffle the names. More or less. Trust me."], dayOf(e.joinUntil)))
        leaveBtn:SetShown(phase == "joining")
        leaveBtn:SetScript("OnClick", function() WV:Leave(); GuildOS:SafeCall(draw) end)
    end

    -- Wrapped: the box, the note, the countdown.
    local function drawWrapped(e, phase, t, g)
        only(vWrapped)
        wdName:SetText(string.format(L["For %s"], nameOf(g.to)))
        wdBox:Reset(1)
        wdBob:Play()
        local hasNote = g.note ~= nil and g.note ~= ""
        wdCard:SetShown(hasNote)
        wdNoNote:SetShown(not hasNote)
        if hasNote then wdCard:SetNote(g.note) end
        wdCount:SetText(countdown(e.openAt - t))
        -- A wrap made here that the site has not confirmed yet: say so, louder near the deadline.
        -- WinterVeil:PendingSync() names it; WinterVeil.SyncWarningAt says when a deadline is less than a day away.
        local pending = false
        for _, x in ipairs(WV:PendingSync()) do if x.to == g.to then pending = true end end
        local warn = pending and phase == "wrapping" and WV.SyncWarningAt(e, 1, t) or nil
        if warn and warn.kind == "reassign" then
            wdFace:SetFace("oops")
            wdSay:Say(nil, L["In less than a day the site hands the unwrapped pairs to somebody else, and it does not have yours yet: sync the companion."])
        elseif warn then
            wdFace:SetFace("oops")
            wdSay:Say(nil, L["The wrapping closes in less than a day and the site does not have yours yet: sync the companion."])
        elseif pending and phase == "wrapping" then
            wdFace:SetFace("rush")
            wdSay:Say(nil, L["Waiting to sync: the site does not have this wrap yet. Sync the companion."])
        else
            wdFace:SetFace("happy")
            wdSay:Say(nil, L["Double ribbon. No shaking it before the time."])
        end
        wdUntil:SetText(string.format(L["UNTIL THE OPENING · %s"], date("%d/%m %H:%M", e.openAt)))
        local open_ = phase == "wrapping"
        rewrapBtn:SetShown(open_)
        rewrapBtn:SetEnabled(WV:HasCompanion())
        wdClosed:ClearAllPoints()
        wdClosed:SetPoint("TOPLEFT", 244, open_ and -320 or -284)
        wdClosed:SetPoint("RIGHT", vWrapped, "RIGHT", -12, 0)
        wdClosed:SetShown(not open_ or not WV:HasCompanion())
        wdClosed:SetText(not open_ and L["The wrapping is closed."]
            or string.format(L["Wrap it on the site: this needs the companion. %s"], siteLink()))
        -- The countdown moves by the minute while the tab is in view, with no OnUpdate.
        scope:After(60, function() if view == "mine" then GuildOS:SafeCall(draw) end end, "clock")
    end

    local function drawForm(g, gives)
        only(vWrap)
        wName:SetText(nameOf(g.to))
        -- The form follows the pair it is for: picking the other pair (a volunteer holds two) brings its scene and note.
        -- SetText fires OnTextChanged, which draws again: `formFor` is set first, so that draw does not set it again.
        if formFor ~= g.to then
            formFor = g.to
            scene = g.scene or "tree"
            noteBox.edit:SetText(g.note or "")
        end
        pvBox:Hide()
        pvGlobe:SetAlpha(1)
        pvGlobe:SetTexture(Fx.GlobePath(scene, "common", true))
        for id, b in pairs(sceneBtns) do
            local on = id == scene
            b.border:SetColor(on and C.gold or C.line, 1)
            b.inner:SetShown(on)
            local tc = on and C.text or C.textSoft
            b.label:SetTextColor(tc.r, tc.g, tc.b)
        end
        local note = noteBox.edit and noteBox.edit:GetText() or ""
        -- Counted as the site counts it: the clean note (spaces collapsed). A caprice note (the site's §7): 40 characters
        -- or more and 6 different letters, the rarity then drawn twice; WinterVeil.Caprice is the site's rule, a hint here.
        local clean = WV.CleanNote(note)
        local n = WV.CharCount(clean or note)
        noteCount:SetText(string.format("%d/%d", n, WV.NOTE_MAX))
        local caprice = WV.Caprice(note)
        local fc = caprice and C.ok or C.lineHi
        meterFill:SetColorTexture(fc.r, fc.g, fc.b, 1)
        meterFill:SetWidth(math.max(0.01, 452 * math.min(n, WV.NOTE_MAX) / WV.NOTE_MAX))
        if not clean then
            capLine:SetText(colored(L["not allowed"], C.danger) .. "  " .. L["Up to 80 characters, no links, no @, no markdown."])
        elseif caprice then
            capLine:SetText(colored(L["Caprice note: the rarity is drawn twice and the better one stays."], C.ok))
        elseif n >= WV.CAPRICE_MIN then
            capLine:SetText(string.format(L["A caprice note needs %d different letters."], WV.CAPRICE_LETTERS))
        else
            capLine:SetText(string.format(L["With %d characters or more and %d different letters, the rarity is drawn twice. %d to go."], WV.CAPRICE_MIN, WV.CAPRICE_LETTERS, WV.CAPRICE_MIN - n))
        end
        wrapBtn:SetText((g.wrapped or g.pending) and L["Wrap again"] or L["Wrap"])
        wrapBtn:SetEnabled(clean ~= nil and WV:HasCompanion())
        wrapBtn:SetScript("OnClick", function()
            local ok, why = WV:Wrap(g.to, scene, noteBox.edit:GetText())
            if not ok then GuildOS:Print(whyText(why)); GuildOS:SafeCall(draw); return end
            playWrap(function()
                editing = false
                GuildOS:SafeCall(draw)
                sayToast("happy", L["Wrapped!"], L["It goes to the site with the companion's next sync."])
            end)
        end)
        formNote:SetText(WV:HasCompanion() and L["The newest between the site and the game wins."]
            or string.format(L["Wrap it on the site: this needs the companion. %s"], siteLink()))
        -- Two pairs (one taken over): pick which one the form is for.
        local i = 0
        if #gives > 1 then
            for _, x in ipairs(gives) do
                i = i + 1
                local row = giveRowAt(i)
                row.text:SetText(nameOf(x.to))
                row.value:SetText((x.wrapped or x.pending) and L["wrapped"] or L["not wrapped yet"])
                if x.to == g.to then row.sel:Show() end
                row:SetScript("OnClick", function() pickedTo = x.to; GuildOS:SafeCall(draw) end)
            end
        end
        giveHide(i + 1)
    end

    local function drawMine(e, phase, t)
        local joined = WV:Joined()
        local gives = WV:MyGives()
        local got = WV:Got()
        mKicker:SetText(""); mLine:SetText(""); mNote:SetText("")
        giveHide(1)
        wdBob:Stop()
        iFaceBob:Stop()
        if joined and phase ~= "open" then
            mPlay:SetText((WV:Played() or WV:PlaySeen()) and L["In-game participation: registered"]
                or L["In-game participation: not yet, complete a Winter Veil quest"])
        else
            mPlay:SetText("")
        end

        -- The opening: the gift box I received, then the globe.
        if phase == "open" then drawOpen(e, gives, got); return end
        if not joined then drawJoin(e, phase); return end
        if not e.drawn then drawJoined(e, phase); return end

        -- Drawn: whom I drew, and the wrapping.
        if #gives == 0 then
            only(nil)
            mKicker:SetText(L["YOU DREW"])
            mLine:SetText(L["Your pair has not reached this client yet."])
            mNote:SetText(L["It comes with the companion. You can also wrap on the site."] .. "  " .. siteLink())
            return
        end
        local g = gives[1]
        for _, x in ipairs(gives) do if x.to == pickedTo then g = x end end
        pickedTo = g.to

        if wrapping then return end
        -- A wrap made here and not on the site yet (`pending`) shows as wrapped, "waiting to sync".
        if (g.wrapped or g.pending) and not (editing and phase == "wrapping") then drawWrapped(e, phase, t, g); return end
        if phase ~= "wrapping" then
            only(nil)
            mKicker:SetText(L["YOU DREW"])
            mLine:SetText(nameOf(g.to))
            mNote:SetText(L["The wrapping is closed. If you did not wrap, Frimm sends it for you."])
            return
        end

        drawForm(g, gives)
    end

    function draw()
        local e = WV:Event()
        local t = GetServerTime()
        local phase = WV.PhaseOf(e, t)
        none:SetShown(not e)
        main:SetShown(e ~= nil)
        chimney.frame:SetShown(e ~= nil)
        if not e then
            sub:SetText("")
            show(nil)
            scope:StopAll()
            return
        end
        tabs.board:SetShown(GuildOS:IsOfficer())
        if view == "board" and not GuildOS:IsOfficer() then view = "mine" end
        for id, tab in pairs(tabs) do tab:SetActive(id == view) end
        scope:StopTag("clock")

        -- Head.
        local days = math.max(0, math.ceil((e.openAt - t) / 86400))
        sub:SetText(phase == "open" and L["The globes can be opened."]
            or phase == "wrapping" and string.format(L["Wrap until %s · opens in %d day(s)"], dayOf(e.wrapUntil), days)
            or phase == "joining" and string.format(L["Joining until %s"], dayOf(e.joinUntil))
            or string.format(L["Opens in %d day(s)"], days))
        chipIn:SetValue(tostring(e.counts.entrants))

        -- The Chimney.
        local cs = WV.ChimneyState(e, t)
        chipWrapped:SetValue(cs.state == "off" and "—" or string.format("%d/%d", e.counts.wrapped, math.max(e.counts.pairs, e.counts.entrants)))
        chimney:Set(cs, { wrapped = e.counts.wrapped, pairs = math.max(e.counts.pairs, e.counts.entrants), joinUntil = e.joinUntil, wrapUntil = e.wrapUntil })
        if cs.state == "full" and not WV:Seen("chimneyFull") and scope:Live() then
            WV:MarkSeen("chimneyFull")
            chimney:Celebrate()
            sayToast("happy", L["The Chimney is full!"], L["Double odds of rare, epic and legendary at the opening."])
        end

        show(view)
        if view == "mine" then drawMine(e, phase, t); return end

        if view == "collection" then
            local list = WV:Collection()
            cTitle:SetText(string.format(L["COLLECTION · %d"], #list))
            shelf:Set(list)
            return
        end

        local rows = {}
        if view == "chain" then
            chTitle:SetText(L["THE GUILD'S CHAIN"])
            if phase ~= "open" or not e.reveal then
                chNote:SetText(L["After the opening, the globes already opened show here: who gave whom, the scene and the rarity."])
            else
                chNote:SetText(string.format(L["Only the globes already opened: %d of %d. A closed one stays a secret."], #e.reveal, e.counts.pairs))
                for _, r in ipairs(e.reveal) do
                    rows[#rows + 1] = { icon = Fx.GlobePath(r.scene, r.rarity),
                        text = (r.host and L["Frimm"] or nameOf(r.giver)) .. "  |cff6f6878" .. L["gave"] .. "|r  " .. nameOf(r.to),
                        value = sceneName(r.scene) .. " · " .. colored(rarityName(r.rarity), Fx.Rarity(r.rarity).text) }
                end
            end
        else
            chTitle:SetText(L["Participants"])
            chNote:SetText(string.format(L["Nobody sees the pairs, officers included. The rules and the draw are on the site: %s"], siteLink()))
            for _, r in ipairs(e.entrants or {}) do
                -- Who wrapped in the ok ink, who has not yet in the warn's (the mockup's badges), never a pair.
                rows[#rows + 1] = { text = nameOf(r.key), value = r.wrapped and colored(L["wrapped"], C.ok) or colored(L["not wrapped yet"], C.warn) }
            end
        end
        -- Only the rows that fit, from `listTop`.
        local fit = math.max(1, math.floor((tonumber(chList:GetHeight()) or 0) / ROW_H))
        if fit <= 1 then fit = 13 end
        listTop = math.max(0, math.min(listTop, #rows - fit))
        local i = 0
        for k = listTop + 1, math.min(#rows, listTop + fit) do
            local d = rows[k]
            i = i + 1
            local row = chRow(i)
            if d.icon then row.icon:SetTexture(d.icon); row.icon:Show() else row.icon:Hide() end
            row.text:SetText(d.text)
            row.value:SetText(d.value)
        end
        chHide(i + 1)
        chPage:SetText(#rows > fit and string.format(L["%d–%d of %d"], listTop + 1, listTop + i, #rows) or "")
    end

    noteBox.edit:HookScript("OnTextChanged", function() GuildOS:SafeCall(draw) end)
    panel.Draw = draw
    panel.scope = scope
    scope.onOption = function() if panel:IsVisible() == true then draw() end end
    panel.chimney = chimney
    panel.shelf = shelf
    panel:SetScript("OnShow", function() GuildOS:SafeCall(draw) end)
    return panel
end
