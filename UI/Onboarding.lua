----------------------------------------------------------------------
-- Guild OS - What's new / Welcome (specs/salao/onboarding.md)
--
-- At login, once per version (Modules/Onboarding.lua decides): an account that used Guild OS before reads
-- what changed in this version (up to six cards, by rank and client); a new one gets the welcome (what Guild
-- OS is, how to open it with the guild button's choice, its raid roles, what is shared). A floating window
-- (the mockup's .fw), its cards one at a time: a picture drawn with the Salão's own textures (no screenshot,
-- nothing to translate but the room names), the card's dots, its title and its text. "Take the tour" on the
-- last card starts the member tour; "Later" (the close, Escape) shows it again at the next login, three times
-- at most, then only a red dot on the title bar's "?"; "Got it" closes it until the next release, which opens it again.
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
--
-- Each key is a painting, Media/Salao/onboarding/<key>.tga (512 x 256, drawn by tools/onboarding_art.py):
-- no words in it, so nothing to translate. It is shown cropped by texcoords to the holder's shape, never
-- stretched (what matters sits in the painting's middle band), inside a metal line, in a holder that clips
-- its children. A holder makes two regions once (the line and the painting); drawing the same key at the
-- same size again does nothing, so a relayout costs nothing.
----------------------------------------------------------------------
local Picture = {}
UI.Picture = Picture

-- The keys that have a painting. "map" shows the campfires on WoW: Forever ("map-fires").
Picture.KEYS = {}
for _, key in ipairs({ "salao", "search", "officers", "members", "raids", "map", "map-fires", "bank", "light",
                       "shield", "compact", "gm", "departure", "notes", "done", "signup", "groups", "alts",
                       "wishlist", "crafts", "site", "moderation" }) do
    Picture.KEYS[key] = true
end
-- The help's guides, each its own painting where its `ill` is shared with another guide.
Picture.GUIDE = { signup = "signup", groups = "groups", alts = "alts", loot = "wishlist", crafts = "crafts",
                  site = "site", moderate = "moderation" }
local ART_W, ART_H = 512, 256
local LINE = 1
local EDGE = { r = 0x8a / 255, g = 0x6c / 255, b = 0x32 / 255 }

-- The painting's path for `key`, or nil for a key that has none.
function Picture:Path(key)
    if key == "map" and GuildOS.Onboarding and GuildOS.Onboarding.ClientKey() == "forever" then key = "map-fires" end
    if not (key and self.KEYS[key]) then return nil end
    return GuildOS.Style.ART_DIR .. "onboarding\\" .. key .. ".tga"
end

-- The picture key for guide `g` ({ id, ill }).
function Picture:GuideKey(g)
    return g and (self.GUIDE[g.id] or g.ill)
end

-- The texcoords that show the middle of the painting at the holder's shape `w` x `hh`.
function Picture:Crop(w, hh)
    local a, art = w / hh, ART_W / ART_H
    if a >= art then
        local half = art / a / 2
        return 0, 1, 0.5 - half, 0.5 + half
    end
    local half = a / art / 2
    return 0.5 - half, 0.5 + half, 0, 1
end

local function regions(h)
    local p = h.__pic
    if p then return p end
    p = {}
    h.__pic = p
    if h.SetClipsChildren then h:SetClipsChildren(true) end
    p.edge = h:CreateTexture(nil, "BACKGROUND", nil, 0)
    p.edge:SetTexture(WHITE)
    p.edge:SetVertexColor(EDGE.r, EDGE.g, EDGE.b, 1)
    p.edge:SetAllPoints()
    p.art = h:CreateTexture(nil, "ARTWORK", nil, 1)
    p.art:SetPoint("TOPLEFT", LINE, -LINE)
    p.art:SetPoint("BOTTOMRIGHT", -LINE, LINE)
    return p
end

-- No painting for the key: the guild's crest in its light, over the wood (made only when needed).
local function fallback(h, p, shown, s)
    if not p.crest then
        if not shown then return end
        p.bg = GuildOS.Style:Texture(h, "wood", "BACKGROUND", 1, true)
        p.bg:SetPoint("TOPLEFT", LINE, -LINE)
        p.bg:SetPoint("BOTTOMRIGHT", -LINE, LINE)
        p.halo = GuildOS.Style:Texture(h, "halo", "ARTWORK", 2)
        p.halo:SetPoint("CENTER")
        p.halo:SetVertexColor(1, 0.84, 0.48, 0.3)
        p.crest = GuildOS.Style:Texture(h, "mark-crest", "ARTWORK", 3)
        p.crest:SetPoint("CENTER")
    end
    p.halo:SetSize(s * 1.3, s * 1.3)
    p.crest:SetSize(s * 0.5, s * 0.5)
    p.bg:SetShown(shown)
    p.halo:SetShown(shown)
    p.crest:SetShown(shown)
end

-- Draw picture `key` into holder `h`, `w` x `hh` px.
function Picture:Draw(h, key, w, hh)
    w, hh = math.max(40, w or h:GetWidth() or 200), math.max(30, hh or h:GetHeight() or 120)
    local p = regions(h)
    local path = self:Path(key)
    if p.key == key and p.path == path and p.w == w and p.h == hh then return end
    p.key, p.path, p.w, p.h = key, path, w, hh
    if path then
        p.art:SetTexture(path)
        p.art:SetTexCoord(self:Crop(w - 2 * LINE, hh - 2 * LINE))
    end
    p.art:SetShown(path ~= nil)
    fallback(h, p, path == nil, math.min(w, hh))
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
    -- The look card's switch: dark mode, applied by a reload (the button beside it).
    local dm = UI:CreateCheckbox(f, L["Dark mode"], 18)
    dm.checkbox.onChanged = function(_, checked)
        if GuildOS.Style and GuildOS.Style.SetDarkMode then GuildOS.Style:SetDarkMode(checked) end
        if O() then O():LookSeen() end
        if f.Render and f:IsShown() then f:Render() end   -- the Reload now row comes or goes
    end
    dm:Hide()
    f.darkToggle = dm
    local dmReload = UI:CreateButton(f, L["Reload now"], 110, UI.SP.FIELD)
    dmReload:SetScript("OnClick", function() GuildOS.Style:Reload() end)
    dmReload:Hide()
    f.dmReload = dmReload
    local roles = GuildOS.CreateRolePicker and GuildOS:CreateRolePicker(f) or CreateFrame("Frame", nil, f)
    roles:Hide()
    f.rolePick = roles

    local foot = f.foot
    f.neverBtn = UI:SetButtonVariant(UI:CreateButton(foot, L["Got it"], 120, UI.SP.FIELD), "ghost")
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
        -- The big 2.0 cards carry the release's name; a later release's notes, its number.
        local sub = self.notesOnly and string.format(L["Guild OS %s"], O():Version())
            or string.format(L["Guild OS %s"], L["2.0 \194\183 the Salão"])
        self:SetTitle(welcome and L["Welcome"] or L["What's new"], welcome and "Guild OS" or sub)
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
        self.darkToggle:SetShown(card.extra == "darkmode")
        if card.extra == "darkmode" then
            if O() then O():LookSeen() end
            local want = GuildOS.Style.WantsDarkMode and GuildOS.Style:WantsDarkMode() or false
            self.darkToggle.checkbox:SetChecked(want)
            self.darkToggle:ClearAllPoints()
            self.darkToggle:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
            -- "Reload now" on its own row under the switch: it never runs past a narrow window or a long label.
            local again = want ~= (GuildOS.Style.darkMode == true)
            self.dmReload:ClearAllPoints()
            self.dmReload:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(y + 28))
            self.dmReload:SetShown(again)
            y = y + 28 + (again and (UI.SP.FIELD + 6) or 0)
        else
            self.dmReload:Hide()
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
        self.nextBtn.label:SetText(last and (self.notesOnly and L["Done"] or L["Take the tour"]) or L["Next"])
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
        if what == "tour" and UI.Tour and not self.notesOnly then
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
    -- Only a release's notes: "Done" closes them, no tour after.
    -- (the look card may come first, asked of whoever never chose: the rest is still a release's notes)
    f.notesOnly = Ob:IsNotesOnly(f.cards)
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
