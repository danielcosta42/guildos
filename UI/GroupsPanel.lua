----------------------------------------------------------------------
-- Guild OS - The Groups tab (issue #341)
-- The guild's own group finder. One card on top says what I play, I am looking (and, while I am, how
-- long is left, Change, +30 min, Stop) and Form a group; under it the figures (groups forming, players
-- looking, groups for me) and the filters as pills. Then two columns: the groups being formed (or, when
-- I lead one, its card with its queue and the players who fit it), a card each, and the players
-- looking, a row each. Modules/Groups.lua and Modules/LFGBoard.lua answer; this draws and calls their
-- methods.
--
-- The forms have no window of their own (#449, "option E"): Form a group turns the left column into
-- the form, in place, in two steps (what it is for, picked from cards; who and when), while the right
-- column lights who would fit; I am looking does the same in the right column, several cards at once.
--
-- The spacing standard (#449, specs/salao/fase3.md, "Espaçamento"): cards 16 in and 14 apart, sections
-- 18 apart with their title 8 over the content, fields 26 high, rows 28 (32 with an avatar), body text
-- 13, meta 11, titles 15, figures 22. Two columns from 900px; the lists grow to the height left.
--
-- Everything is repainted from pools: a repaint that created its rows would leak them, because the
-- client never frees a frame.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SP = UI.SP                              -- the spacing standard (#449, UI/Helpers.lua)
local M = tonumber(UI.GAP) or 8               -- the room's margin around a screen (#371)

local ICON = 16
local AVATAR = 24
local ACT_ICON = 36                  -- a group's activity, as its card's icon
local SLOT, SLOT_GAP = 16, 4         -- a group's seats
local NAME_W, LEVEL_W, ROLES_W = 128, 48, 66
local REPAINT_EVERY = 30             -- seconds: the time left on a listing
local CHIP = 26                      -- a role's square (a stepper's mark)
local ART_TC = { 0.32, 0.68, 0.12, 0.84 }   -- the middle of an activity's LFG art, square enough for an icon
-- A scroll child past ~15000px stops drawing: a guild of hundreds all looking must not get there.
local GROUPS_MAX, SEEKERS_MAX = 50, 200
local DOT = "  \194\183  "

local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }
local FILTERS = {
    { key = "all",     label = L["All"] },
    { key = "dungeon", label = L["Dungeons"] },
    { key = "raid",    label = L["Raids"] },
    { key = "other",   label = L["Quests and more"] },
}

local function roleColor(letter)
    return (letter == "T" and C.info) or (letter == "H" and C.ok) or C.danger
end

local function roleNames(roles)
    local B, out = GuildOS.LFGBoard, {}
    for _, k in ipairs(LETTERS) do
        if roles:find(k, 1, true) then out[#out + 1] = B:RoleName(ROLE_OF[k]) end
    end
    return #out > 0 and table.concat(out, ", ") or B:RoleName("ANY")
end

local function hexOf(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A name in its class's ink: the paper's (UI:InkFor) where `paper`, the game's on the wood.
local function coloured(name, classFile, paper)
    if not classFile then return name end
    if paper then return "|cff" .. hexOf(UI:InkFor("paper", "class", classFile)) .. name .. "|r" end
    return "|cff" .. GuildOS:GetClassColorHex(classFile) .. name .. "|r"
end

-- A colour of the wood as `frame` prints it (the paper's shade on a parchment card).
local function ink(frame, c)
    return UI:Ink(UI:OnPaper(frame) and "paper" or "wood", c)
end

local function whisper(name)
    local target = GuildOS:WhisperTarget(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end
end

local function oneLine(fs, width)
    fs:SetWidth(math.max(10, width))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
end

local function text(parent, size, c, role)
    local fs = UI:CreateText(parent, "", size or SP.BODY)
    if c then
        local k = ink(parent, c)
        fs:SetTextColor(k.r, k.g, k.b)
    end
    if role then GuildOS:ApplyFont(fs, size or SP.BODY, role) end
    return fs
end

-- "68-70", or the one level, or nothing for an activity with no range.
local function rangeOf(it)
    if not it or not it.min then return "" end
    return it.min == it.max and tostring(it.min) or (it.min .. "\226\128\147" .. it.max)
end

-- Whether the client has an activity's art, asked once: a path it lacks draws a green square.
local function hasArt(it)
    if it.artOk == nil then it.artOk = it.art ~= nil and GuildOS.Compat.TextureExists(it.art) end
    return it.artOk
end

-- A card as the standard draws it (#449): the shared card, its title 15px at 16 in, `isCard` for the
-- test that nothing drawn on it leaves it.
local function newCard(parent, title, dark)
    local c = UI:CreateCard(parent, title or "", { dark = dark and true or nil })
    c.isCard = true
    c.title:ClearAllPoints()
    c.title:SetPoint("TOPLEFT", SP.PAD, -SP.PAD)
    c.title:SetPoint("RIGHT", c, "RIGHT", -SP.PAD, 0)
    GuildOS:ApplyFont(c.title, SP.TITLE, "sectionTitle")
    return c
end

-- A button as wide as its label, never under `min` (60).
local function fit(b, label, min)
    b.label:SetText(label)
    b:SetWidth(math.max(min or 60, math.ceil(b.label:GetStringWidth() or 0) + 22))
    return b
end

-- Lay buttons out from x (a frame's right edge less `right`) inwards, at `top`; returns the width taken.
local function rightAlign(frame, buttons, top, right)
    local x = -(right or 0)
    for _, b in ipairs(buttons) do
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, top)
        x = x - b:GetWidth() - 6
    end
    return -x - (right or 0)
end

----------------------------------------------------------------------
-- The game's role icons (#373)
----------------------------------------------------------------------
-- The group finder's own atlases, where the client lists all three: retail, TBC Anniversary and
-- WoW: Forever name both sets (tools/data/forever-atlas-elements.txt, neither marked Forever-only),
-- and on Forever an element resolves to its own -c60 art. Then the LFG frame's file, cut where
-- Blizzard's GetTexCoordsForRole cuts it (67px cells of a 256px sheet). Then nothing: a role keeps
-- its letter, because a path the client does not have draws a green square.
local ROLE_ATLASES = {
    { T = "groupfinder-icon-role-large-tank", H = "groupfinder-icon-role-large-heal", D = "groupfinder-icon-role-large-dps" },
    { T = "UI-LFG-RoleIcon-Tank", H = "UI-LFG-RoleIcon-Healer", D = "UI-LFG-RoleIcon-DPS" },
}
local ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local CELL = 67 / 256
local ROLE_CELL = { T = { 0, CELL, CELL, 2 * CELL }, H = { CELL, 2 * CELL, 0, CELL }, D = { CELL, 2 * CELL, CELL, 2 * CELL } }
local roleArt   -- the atlas set, "file", or false; asked once a session: the client's files do not change

local function roleArtKind()
    if roleArt ~= nil then return roleArt end
    roleArt = false
    local get = C_Texture and C_Texture.GetAtlasInfo
    for _, set in ipairs(get and ROLE_ATLASES or {}) do
        local all = true
        for _, letter in ipairs(LETTERS) do
            local ok, info = pcall(get, set[letter])
            all = all and ok and info ~= nil
        end
        if all then
            roleArt = set
            return roleArt
        end
    end
    if GuildOS.Compat.TextureExists(ROLE_FILE) then roleArt = "file" end
    return roleArt
end

-- Paint a role's icon on `tex` and show it. False, with `tex` hidden, where the client has none: the
-- caller then shows the role's letter or name.
local function setRoleIcon(tex, letter)
    local kind = roleArtKind()
    if type(kind) == "table" then
        tex:SetAtlas(kind[letter])
    elseif kind == "file" then
        tex:SetTexture(ROLE_FILE)
        tex:SetTexCoord(unpack(ROLE_CELL[letter]))
    else
        tex:Hide()
        return false
    end
    tex:Show()
    return true
end

local function roleTooltip(btn, letter)
    local B = GuildOS.LFGBoard
    -- Hooked, not set: the button's own hover and press states live on OnEnter and OnLeave.
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(B:RoleName(ROLE_OF[letter]), C.text.r, C.text.g, C.text.b)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A role's square: a shared button with the role's icon, or its letter where the
-- client has no icon (#373). A chosen role takes the shared selection mark (UI:SetSelected); an icon
-- not chosen is greyed, as the game's own role picker greys it.
local function createRoleChip(parent, letter)
    local chip = UI:CreateButton(parent, letter, CHIP, CHIP)
    chip.letter = letter
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(CHIP - 8, CHIP - 8)
    chip.icon:SetPoint("CENTER")
    if setRoleIcon(chip.icon, letter) then chip.label:SetText("") end
    function chip:SetOn(on)
        self.on = on and true or false
        UI:SetSelected(self, self.on)
        self.icon:SetDesaturated(not self.on)
    end
    chip:SetOn(false)
    roleTooltip(chip, letter)
    return chip
end

-- A role's toggle with its name (the card's "I play", #449): the icon, then "Tank", as a pill that is
-- lit while I play it. Where the client has no icon the name alone says it.
local function createRoleToggle(parent, letter)
    local B = GuildOS.LFGBoard
    local t = UI:SetButtonVariant(UI:CreateButton(parent, "", 80, SP.FIELD), "chip")
    t.letter = letter
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(ICON, ICON)
    t.icon:SetPoint("LEFT", 10, 0)
    local drawn = setRoleIcon(t.icon, letter)
    t.label:SetText(B:RoleName(ROLE_OF[letter]))
    t.label:ClearAllPoints()
    t.label:SetPoint("LEFT", drawn and (10 + ICON + 6) or 12, 0)
    t:SetWidth((drawn and (10 + ICON + 6) or 12) + math.ceil(t.label:GetStringWidth() or 30) + 12)
    function t:SetOn(on)
        self.on = on and true or false
        UI:SetSelected(self, self.on)
        self.icon:SetDesaturated(not self.on)
    end
    t:SetOn(false)
    roleTooltip(t, letter)
    return t
end

-- A role's square that only names the role (a stepper's), never chosen: its icon in full colour, or
-- its letter in the role's colour.
local function createRoleMark(parent, letter)
    local mark = createRoleChip(parent, letter)
    local c = roleColor(letter)
    mark.baseLabelColor = { c.r, c.g, c.b }
    UI:_ButtonState(mark, "rest")
    mark.icon:SetDesaturated(false)
    mark:EnableMouse(false)
    return mark
end

----------------------------------------------------------------------
-- What a group is for, as cards (#449, option E): the activities of a category, the spots a new group
-- opens with
----------------------------------------------------------------------
-- The activities of one category (Cat.CATS), each once, in the catalogue's order; with `levelOnly` only
-- those of my level (Groups:FitsLevel: an activity with no range is anybody's).
local function activitiesOf(cat, levelOnly, myLevel)
    local Cat, G = GuildOS.GroupActivities, GuildOS.Groups
    local out, seen = {}, {}
    for _, s in ipairs(Cat:Sections(cat)) do
        for _, it in ipairs(s.items) do
            if not seen[it.id] and (not levelOnly or G:FitsLevel(it.id, myLevel)) then
                seen[it.id] = true
                out[#out + 1] = it
            end
        end
    end
    return out
end

-- The spots a new group for `act` opens with: a tank, a healer and three DPS, less the one role I play
-- myself, never more than a group of that size has besides its leader.
local function defaultNeed(act)
    local need = { T = 1, H = 1, D = 3 }
    local mine = GuildOS.LFGBoard:Pref("roles") or ""
    if #mine == 1 and need[mine] > 0 then need[mine] = need[mine] - 1 end
    local room = GuildOS.Groups:SizeOf(act) - 1
    return GuildOS.Groups:_SanitizeNeed(need, room)
end

----------------------------------------------------------------------
-- The notice (#378): a small card at the top of the screen that goes away by itself. Three kinds,
-- which Modules/Groups.lua decides: a guildmate formed a group I fit ("group"), somebody asks for a
-- spot in mine and I do not invite whoever asks ("request"), my listing is about to end ("expiring").
-- One at a time, never in combat: GuildOS:ShowWhenClear holds it, and when its turn comes it shows
-- only if what it says is still true (Groups:StillTrue, #449).
----------------------------------------------------------------------
local TOAST_W, TOAST_H = 320, 84
local TOAST_SECONDS = { group = 12, request = 30, expiring = 60 }
local toast

local function buildToast()
    local t = CreateFrame("Button", "GuildOSGroupsToast", UIParent, "BackdropTemplate")
    t:SetSize(TOAST_W, TOAST_H)
    t:SetPoint("TOP", 0, -110)
    t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(t) })
    t:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.96)
    t:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    t:SetFrameStrata("DIALOG")
    t:SetMovable(true)
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", function(self) self:StartMoving() end)
    t:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    t.title = UI:CreateTitle(t, "", 13)
    t.title:SetPoint("TOPLEFT", 12, -10)
    t.title:SetWidth(TOAST_W - 48)
    t.title:SetJustifyH("LEFT")
    t.title:SetWordWrap(false)
    t.body = UI:CreateText(t, "", SP.BODY - 1)
    t.body:SetPoint("TOPLEFT", 12, -30)
    t.body:SetWidth(TOAST_W - 24)
    t.body:SetJustifyH("LEFT")
    t.body:SetWordWrap(false)
    local close = UI:CreateCloseButton(t)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() t:Hide() end)
    t.primary = UI:SetButtonVariant(UI:CreateButton(t, "", 110, SP.HIT), "primary")
    t.primary:SetPoint("BOTTOMRIGHT", -12, 10)
    t.secondary = UI:CreateButton(t, "", 90, SP.HIT)
    t.secondary:SetPoint("RIGHT", t.primary, "LEFT", -6, 0)
    -- The card itself opens the tab, where the rest is.
    t:SetScript("OnClick", function(self)
        self:Hide()
        GuildOS.LFGBoard:Show()
    end)
    t:Hide()
    return t
end

local function fitButton(b, str)
    b.label:SetText(str)
    b:SetWidth(math.max(70, math.ceil(b.label:GetStringWidth()) + 22))
end

-- n = { kind, key, name, act?, need?, note?, role? }, from Modules/Groups.lua. Nil, showing nothing,
-- when what it says stopped being true while it waited.
local function groupsToastNow(n)
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    if not G:StillTrue(n) then return nil end
    toast = toast or buildToast()
    local key = n.key
    if n.kind == "group" then
        -- The group as it is now, not as it was queued: a spot filled while the toast waited is not offered
        -- (#449 review).
        local live = GuildOS.db and GuildOS.db.lfgGroups and GuildOS.db.lfgGroups[key]
        local need = (type(live) == "table" and live.need) or n.need
        local role = G:BestRole(need, B:Pref("roles") or "")
        toast.title:SetText(L["Groups being formed"])
        local body = string.format("%s: %s", n.name, G:Title(n)) .. DOT ..
            string.format(L["open: %s"], G:NeedText(need))
        toast.body:SetText(body)
        fitButton(toast.primary, string.format(L["Ask as %s"], B:RoleName(ROLE_OF[role] or "ANY")))
        toast.primary:SetShown(role ~= nil)
        toast.primary:SetScript("OnClick", function()
            toast:Hide()
            if role then G:RequestSpot(key, role) end
        end)
        fitButton(toast.secondary, L["Whisper"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            whisper(n.name)
        end)
    elseif n.kind == "expiring" then
        -- My listing is about to end (#378): 30 minutes more, or down now.
        local group = n.what == "group"
        toast.title:SetText(L["Your listing ends soon"])
        toast.body:SetText(L["Your listing ends in 5 minutes."])
        fitButton(toast.primary, L["+30 min"])
        toast.primary:Show()
        toast.primary:SetScript("OnClick", function()
            toast:Hide()
            if group then G:Extend() else B:Extend() end
        end)
        fitButton(toast.secondary, L["Take down"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            if group then G:Disband() else B:ClearAvailable() end
        end)
    else
        toast.title:SetText(L["Asking for a spot"])
        toast.body:SetText(string.format(L["%s asks for a spot in your group as %s."], n.name,
            B:RoleName(ROLE_OF[n.role])))
        fitButton(toast.primary, L["Invite"])
        toast.primary:Show()
        toast.primary:SetScript("OnClick", function()
            toast:Hide()
            G:Invite(key)
        end)
        fitButton(toast.secondary, L["Decline"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            G:Decline(key)
        end)
    end
    local shownAt = GetTime()
    toast.shownAt = shownAt
    toast:Show()
    GuildOS.Compat.After(TOAST_SECONDS[n.kind], function()
        if toast and toast.shownAt == shownAt then toast:Hide() end
    end)
    return toast
end

-- Never in combat, one popup at a time (audit B21): the toast waits for combat to end.
function GuildOS:GroupsToast(n)
    if not (n and n.kind and TOAST_SECONDS[n.kind]) then return end
    self:ShowWhenClear("groups:" .. n.kind .. ":" .. tostring(n.key or n.what), function() return groupsToastNow(n) end)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
-- Pools: a frame is made the first time a paint needs that many and kept (`kind` names the pool).
local function newPools()
    local pools = {}
    local P = {}
    function P.acquire(kind, make)
        local pool = pools[kind]
        if not pool then
            pool = { used = 0, items = {} }
            pools[kind] = pool
        end
        pool.used = pool.used + 1
        local item = pool.items[pool.used]
        if not item then
            item = make()
            pool.items[pool.used] = item
        end
        item:Show()
        return item
    end
    function P.releaseAll()
        for _, pool in pairs(pools) do
            for _, item in ipairs(pool.items) do item:Hide() end
            pool.used = 0
        end
    end
    return P
end

-- A box inside a parchment card (a group's): the paper's light fill and its line, 6px corners.
local function paperBox(parent)
    local f = CreateFrame("Frame", nil, parent)
    if GuildOS.Style and GuildOS.Style.Nine then
        GuildOS.Style:Nine(f, "card", 6, "BACKGROUND", -6):SetColor(C.paperLight, 0.55)
        GuildOS.Style:Nine(f, "card-line", 6, "BACKGROUND", -5):SetColor(C.paperLine)
    end
    return f
end

-- A row's hairline at its foot.
local function rowRule(f)
    local r = f:CreateTexture(nil, "BACKGROUND")
    r:SetTexture(WHITE)
    r:SetHeight(1)
    r:SetPoint("BOTTOMLEFT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", 0, 0)
    local c = ink(f, C.line)
    if UI:OnPaper(f) then c = C.paperLine end
    r:SetVertexColor(c.r, c.g, c.b, 1)
    f.rule = r
    return r
end

-- The colour of an activity's disc where the client has no art for it: one per category.
local CAT_TINT = { dungeon = C.info, raid = C.count, other = C.ok }

-- An activity's icon: its LFG art where the client has it, a glyph with its initial on its category's
-- colour otherwise (WoW: Forever's new dungeons have no art). `round`: the art cut round inside a gold
-- ring (the form's cards, #449); where a client has no mask it stays square inside the ring.
local function activityIcon(parent, size, round)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.glyph = UI:CreateGlyph(f, size)
    f.glyph:SetPoint("CENTER")
    local Style = GuildOS.Style
    local Compat = GuildOS.Compat
    if round and Style and Style.ART then
        local inset = 2
        f.art:SetPoint("TOPLEFT", inset, -inset)
        f.art:SetPoint("BOTTOMRIGHT", -inset, inset)
        local mask = Compat.NewMask(f, Style.ART.circle, inset)
        if mask then Compat.AddMask(f.art, mask) end
        f.ring = Style:Texture(f, "ring", "OVERLAY", 1)
        f.ring:SetAllPoints()
        f.ring:SetVertexColor(C.metal2.r, C.metal2.g, C.metal2.b, 1)
    else
        f.art:SetAllPoints()
    end
    function f:SetActivity(act, named)
        local it = GuildOS.GroupActivities.byId[act]
        local drawn = not named and it ~= nil and hasArt(it)
        if drawn then
            self.art:SetTexture(it.art)
            self.art:SetTexCoord(ART_TC[1], ART_TC[2], ART_TC[3], ART_TC[4])
            self.art:Show()
            self.glyph:Hide()
        else
            self.art:Hide()
            self.glyph:Show()
            local name = named or GuildOS.LFGBoard:ActivityName(act)
            self.glyph:Set(UI.Initial and UI.Initial(name) or name:sub(1, 1), (it and CAT_TINT[it.cat]) or C.paperSoft)
        end
        if self.ring then self.ring:SetShown(drawn) end
    end
    return f
end

-- The mark of a chosen card (#449): a small green disc with the game's tick on it, or a white dot where the
-- client has no tick (a glyph would need a font that has one: none of the addon's do).
local TICK = "Interface\\Buttons\\UI-CheckBox-Check"
local function checkMark(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    local Style = GuildOS.Style
    if Style and Style.ART then
        f.disc = Style:Texture(f, "circle", "ARTWORK", 0)
        f.disc:SetAllPoints()
        local ok = UI:Ink("paper", C.ok)
        f.disc:SetVertexColor(ok.r, ok.g, ok.b, 1)
    end
    f.tick = f:CreateTexture(nil, "OVERLAY")
    f.tick:SetPoint("CENTER", 0, 0)
    if GuildOS.Compat.TextureExists(TICK) then
        f.tick:SetTexture(TICK)
        f.tick:SetSize(16, 16)
        f.tick:SetVertexColor(1, 1, 1, 1)
    else
        f.tick:SetTexture(WHITE)
        f.tick:SetSize(6, 6)
    end
    return f
end

-- "My quests" (#450): the category of the forms' cards read from my quest log. A quest's card has the
-- id "q:<quest id>", which never crosses the wire.
local QUEST_CAT = "quests"
local function questOf(id)
    local n = type(id) == "string" and id:match("^q:(%d+)$")
    return n and tonumber(n) or nil
end
local function questItems()
    local out, Q = {}, GuildOS.GroupQuests
    for _, q in ipairs(Q and Q:List() or {}) do out[#out + 1] = { id = "q:" .. q.id, quest = q } end
    return out
end

function GuildOS:CreateGroupsPanel(parent)
    local B, G, Cat, Q = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.GroupActivities, GuildOS.GroupQuests
    parent.activeSub = "active"
    local P = newPools()
    -- The forms' state (#449, option E): `form` is nil (the lists), "group" (forming one, in the left column)
    -- or "seek" (I am looking, in the right one). The rest is what the open form holds.
    local V = { form = nil, step = 1, cat = "dungeon", levelOnly = true, act = nil, need = { T = 0, H = 0, D = 0 },
                start = 0, ttl = 3600, acts = {}, roles = "", chat = false, auto = false, hint = "",
                quest = nil, quests = {}, share = false }
    local paint   -- forward: the handlers below repaint
    local openGroupForm, openSeekForm, closeForm   -- forward: the forms below

    ------------------------------------------------------------------
    -- The top card: what I play, I am looking, form a group; the figures and the filters
    ------------------------------------------------------------------
    local top = newCard(parent, L["Guild groups"], true)
    top:SetPoint("TOPLEFT", 0, -M)
    top:SetPoint("TOPRIGHT", -M, -M)
    top:SetHeight(200)
    parent.card = top

    local playLabel = text(top, SP.BODY, C.textSoft)
    playLabel:SetText(L["I play"])
    local myChips = {}
    for _, letter in ipairs(LETTERS) do myChips[letter] = createRoleToggle(top, letter) end

    local formBtn = UI:SetButtonVariant(UI:CreateButton(top, L["+ Form a group"], 140, SP.FIELD), "primary")

    -- A hairline between what I play and whether I am looking.
    local divider = top:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE)
    divider:SetSize(1, 20)
    divider:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    local lookBtn = fit(UI:SetButtonVariant(UI:CreateButton(top, "", 110, SP.FIELD), "chip"), L["I am looking"], 100)
    lookBtn.isLookToggle = true
    local lookMeta = text(top, SP.META, C.textSoft)
    local extendBtn = fit(UI:SetButtonVariant(UI:CreateButton(top, "", 60, SP.HIT), "ghost"), L["+30 min"])
    local changeBtn = fit(UI:SetButtonVariant(UI:CreateButton(top, "", 60, SP.HIT), "ghost"), L["Change"])
    local stopBtn = fit(UI:CreateButton(top, "", 60, SP.HIT), L["Stop looking"])

    local stripRule = UI:CreateSeparator(top)
    local kpis = {}
    for i, caption in ipairs({ L["groups forming"], L["looking"], L["for you"] }) do
        local v = text(top, SP.KPI, C.gold2, "metricValue")
        local c = text(top, SP.BODY, C.textSoft)
        c:SetText(caption)
        kpis[i] = { value = v, caption = c }
    end
    local filterBtns = {}
    for _, def in ipairs(FILTERS) do
        local b = fit(UI:SetButtonVariant(UI:CreateButton(top, "", 60, SP.HIT), "chip"), def.label, 44)
        local key = def.key
        b:SetScript("OnClick", function()
            B:SetPref("filterCat", key)
            paint()
        end)
        filterBtns[#filterBtns + 1] = { key = key, button = b }
    end
    local levelBtn = fit(UI:SetButtonVariant(UI:CreateButton(top, "", 60, SP.HIT), "chip"), L["My level only"])
    levelBtn:SetScript("OnClick", function()
        B:SetPref("filterLevel", not B:Pref("filterLevel"))
        paint()
    end)

    -- Where the top card's parts go at the card's width; returns its height.
    local function layoutTop(IW)
        -- The title's line: Form a group (My group while I lead one) on the right.
        fit(formBtn, G:Mine() and L["My group"] or L["+ Form a group"], 120)
        formBtn:ClearAllPoints()
        formBtn:SetPoint("TOPRIGHT", -SP.PAD, -(SP.PAD - 4))

        -- Row 1: I play, the three roles | I am looking, and while I am, its time and what to do with it.
        local y = SP.TOP
        playLabel:ClearAllPoints()
        playLabel:SetPoint("TOPLEFT", SP.PAD, -(y + 5))
        local x = SP.PAD + math.ceil(playLabel:GetStringWidth() or 40) + SP.CELL
        for _, letter in ipairs(LETTERS) do
            local t = myChips[letter]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", x, -y)
            x = x + t:GetWidth() + 6
        end
        x = x + SP.CELL - 6
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", x, -(y + 3))
        x = x + 1 + SP.CELL
        local mine = B:Mine()
        UI:SetSelected(lookBtn, mine ~= nil or V.form == "seek")
        lookBtn:ClearAllPoints()
        lookBtn:SetPoint("TOPLEFT", x, -y)
        x = x + lookBtn:GetWidth() + SP.CELL
        lookMeta:SetShown(mine ~= nil)
        stopBtn:SetShown(mine ~= nil)
        changeBtn:SetShown(mine ~= nil)
        extendBtn:SetShown(mine ~= nil)
        if mine then
            lookMeta:SetText(string.format(L["%dm left"], B:_Remaining(mine, GetServerTime())))
            local parts = { lookMeta, changeBtn, extendBtn, stopBtn }
            local need = 0
            for _, p in ipairs(parts) do need = need + math.ceil(p == lookMeta and (p:GetStringWidth() or 40) or p:GetWidth()) + 6 end
            -- Past the card's edge: the status goes on a line of its own, under the roles.
            local sy = y
            if x + need > SP.PAD + IW then
                sy = y + SP.FIELD + 8
                x = SP.PAD
            end
            lookMeta:ClearAllPoints()
            lookMeta:SetPoint("TOPLEFT", x, -(sy + 7))
            x = x + math.ceil(lookMeta:GetStringWidth() or 40) + 6
            for i = 2, #parts do
                parts[i]:ClearAllPoints()
                parts[i]:SetPoint("TOPLEFT", x, -(sy + 1))
                x = x + parts[i]:GetWidth() + 6
            end
            y = sy
        end
        y = y + SP.FIELD + SP.SECTION

        -- Row 2, under a hairline: the figures, then the filters (on a line of their own when narrow).
        stripRule:ClearAllPoints()
        stripRule:SetPoint("TOPLEFT", SP.PAD, -(y - SP.SECTION / 2))
        stripRule:SetPoint("TOPRIGHT", -SP.PAD, -(y - SP.SECTION / 2))
        x = SP.PAD
        for _, k in ipairs(kpis) do
            k.value:ClearAllPoints()
            k.value:SetPoint("TOPLEFT", x, -y)
            x = x + math.ceil(k.value:GetStringWidth() or 12) + 6
            k.caption:ClearAllPoints()
            k.caption:SetPoint("TOPLEFT", x, -(y + 8))
            x = x + math.ceil(k.caption:GetStringWidth() or 40) + 24
        end
        local pills = { levelBtn }
        for i = #filterBtns, 1, -1 do pills[#pills + 1] = filterBtns[i].button end
        local need = 0
        for _, b in ipairs(pills) do need = need + b:GetWidth() + 6 end
        local fy = (x + need <= SP.PAD + IW) and y or (y + SP.KPI + 8 + 8)
        rightAlign(top, pills, -fy, SP.PAD)
        return fy + SP.KPI + 6 + SP.PAD
    end

    ------------------------------------------------------------------
    -- The scroll under it: my group, the two lists
    ------------------------------------------------------------------
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSGroupsScroll")
    scroll:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -SP.GAP)
    -- The scroll child stops UI.SCROLL_GUTTER short of the frame (BindScrollChildWidth): the frame
    -- reaches that far past the top card's right edge, so the cards end where it does (#371).
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(M - UI.SCROLL_GUTTER), M)
    UI:BindScrollChildWidth(scroll, content)

    local groupsCard = newCard(content, L["Groups being formed"])
    local seekersCard = newCard(content, L["Looking for a group"])
    local mineCard = newCard(content, "")
    groupsCard.pk, seekersCard.pk, mineCard.pk = "g", "s", "m"   -- each card's own pools

    -- A card's title with its count after it, in the soft ink.
    local function titled(card, str, n)
        local c = ink(card, C.label)
        card.title:SetText(str .. "  |cff" .. hexOf(c.r, c.g, c.b) .. tostring(n) .. "|r")
    end

    -- A section title inside a card (the queue's, the matches'): the shared one at 15px, its rule
    -- SECTION/2 over it, the content TITLE_GAP under it. Returns the y under it.
    local function section(card, str, n, y, width)
        local s = P.acquire("section" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            f:SetHeight(SP.TITLE_H)
            f.title = UI:CreateSectionTitle(f, "", false)
            GuildOS:ApplyFont(f.title, SP.TITLE, "sectionTitle")
            f.title:SetPoint("TOPLEFT", 0, 0)
            return f
        end)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        s:SetWidth(width)
        local c = ink(card, C.label)
        s.title:SetText(str .. (n and ("  |cff" .. hexOf(c.r, c.g, c.b) .. tostring(n) .. "|r") or ""))
        return y + SP.TITLE_H + SP.TITLE_GAP
    end

    -- A line of soft text inside a card. Returns the y under it.
    local function line(card, str, y, width)
        local fs = P.acquire("line" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            f:SetHeight(18)
            f.text = text(f, SP.BODY, C.textSoft)
            f.text:SetPoint("TOPLEFT", 0, 0)
            f.text:SetJustifyH("LEFT")
            return f
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        fs:SetWidth(width)
        local c = ink(card, C.textSoft)
        fs.text:SetTextColor(c.r, c.g, c.b)
        fs.text:SetWidth(width)
        fs.text:SetText(str)
        return y + 18 + 6
    end

    -- The empty state of a list (#449): a glyph, one line and the action that fills it, centred in the
    -- room `h` from `y`. Returns the y under it.
    local function emptyState(card, glyph, str, action, onClick, y, width, h)
        local e = P.acquire("empty" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            f.glyph = UI:CreateGlyph(f, 36)
            f.glyph:SetPoint("TOP", 0, 0)
            f.text = text(f, SP.BODY, C.textSoft)
            f.text:SetPoint("TOP", f.glyph, "BOTTOM", 0, -10)
            f.text:SetJustifyH("CENTER")
            f.text:SetWordWrap(true)
            f.button = UI:SetButtonVariant(UI:CreateButton(f, "", 120, SP.FIELD), "primary")
            f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -12)
            return f
        end)
        local blockH = 36 + 10 + 36 + 12 + SP.FIELD
        local at = y + math.max(SP.FIELD_GAP, math.floor(((h or 0) - blockH) / 2))
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -at)
        e:SetSize(width, blockH)
        e.glyph:Set(glyph, C.paperSoft)
        e.text:SetWidth(math.max(40, width - 2 * SP.PAD))
        e.text:SetText(str)
        fit(e.button, action, 120)
        e.button:SetScript("OnClick", onClick)
        return at + blockH + SP.FIELD_GAP
    end

    ------------------------------------------------------------------
    -- A group being formed: a box in the list, its activity, who leads, its seats, what I can do
    ------------------------------------------------------------------
    local function slotOf(e, i)
        local s = e.slots[i]
        if not s then
            s = CreateFrame("Frame", nil, e, "BackdropTemplate")
            s:SetSize(SLOT, SLOT)
            s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(s) })
            s.icon = s:CreateTexture(nil, "ARTWORK")
            s.icon:SetPoint("TOPLEFT", 1, -1)
            s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            s.mark = UI:CreateText(s, "", UI.SP.META)
            s.mark:SetPoint("CENTER", 0, 0)
            e.slots[i] = s
        end
        s:Show()
        return s
    end

    -- A seat somebody has (`letter` nil) is a solid pip: the listing counts its members, never their
    -- roles, so it names none. An open one is an empty seat with the role it is for.
    local function paintSlot(s, letter)
        s.role, s.filled = letter, letter == nil
        local paper = UI:OnPaper(s)
        if letter then
            local bg = paper and C.paperLight or C.well
            local edge = paper and C.paperEdge or C.line
            s:SetBackdropColor(bg.r, bg.g, bg.b, 1)
            s:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
            local drawn = setRoleIcon(s.icon, letter)
            local c = ink(s, roleColor(letter))
            s.mark:SetTextColor(c.r, c.g, c.b)
            s.mark:SetText(drawn and "" or letter)
        else
            local c = paper and C.paperSoft or C.label
            s:SetBackdropColor(c.r, c.g, c.b, 1)
            s:SetBackdropBorderColor(c.r, c.g, c.b, 1)
            s.icon:Hide()
            s.mark:SetText("")
        end
    end

    -- The seats from x, at `top`: one a member, then one an open spot, by role, in `room` px at most;
    -- a raid's surplus reads as "+N", open spots kept first. Returns the open roles and the x after.
    local function paintSeats(e, g, x, y, room)
        local open = {}
        for _, letter in ipairs(LETTERS) do
            for _ = 1, (g.need[letter] or 0) do open[#open + 1] = letter end
        end
        local members = g.n or 1
        local cap = math.max(1, math.floor(room / (SLOT + SLOT_GAP)))
        local showOpen = math.min(#open, cap)
        local showFilled = math.min(members, cap - showOpen)
        local hidden = (members - showFilled) + (#open - showOpen)
        local n = 0
        local function seat(letter)
            n = n + 1
            local s = slotOf(e, n)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", x + (n - 1) * (SLOT + SLOT_GAP), -y)
            paintSlot(s, letter)
        end
        for _ = 1, showFilled do seat(nil) end
        for i = 1, showOpen do seat(open[i]) end
        for i = n + 1, #e.slots do e.slots[i]:Hide() end
        local after = x + n * (SLOT + SLOT_GAP) + 2
        e.more:ClearAllPoints()
        e.more:SetPoint("TOPLEFT", e, "TOPLEFT", after, -(y + 1))
        e.more:SetText(hidden > 0 and ("+" .. hidden) or "")
        if hidden > 0 then after = after + math.ceil(e.more:GetStringWidth() or 0) + 6 end
        return open, after + 4
    end

    -- How full a group is and how long it stays up: "1/5 · starts in 15m · 60m".
    local function whenText(g, now)
        local parts = { string.format("%d/%d", g.n or 1, g.max or 5) }
        local startIn = G:StartsIn(g, now)
        if startIn then parts[#parts + 1] = string.format(L["starts in %dm"], math.ceil(startIn / 60)) end
        parts[#parts + 1] = string.format(L["%dm"], B:_Remaining(g, now))
        return table.concat(parts, DOT)
    end

    local function groupEntry(card, g, now, classByKey, y, w, forMe)
        local e = P.acquire("group" .. card.pk, function()
            local f = paperBox(card)
            f.icon = activityIcon(f, ACT_ICON)
            f.icon:SetPoint("TOPLEFT", 12, -12)
            f.title = text(f, SP.BODY, nil, "button")
            f.badge = UI:CreateBadge(f, "", C.ok)
            f.questBadge = UI:CreateBadge(f, "", C.ok)
            f.ago = text(f, SP.META, C.labelDim)
            f.avatar = UI:CreateAvatar(f, 18, false)
            f.lead = text(f, SP.BODY)
            f.range = text(f, SP.META, C.textSoft)
            f.when = text(f, SP.META, C.textSoft)
            f.note = text(f, SP.BODY, C.textSoft)
            f.slots = {}
            f.more = text(f, SP.META, C.labelDim)
            f.missing = text(f, SP.META, C.textSoft)
            f.status = text(f, SP.META, C.textSoft)
            f.whisper = fit(UI:CreateButton(f, "", 60, SP.HIT), L["Whisper"])
            f.cancel = fit(UI:CreateButton(f, "", 60, SP.HIT), L["Take it back"])
            f.join = {}
            for _, letter in ipairs(LETTERS) do
                local b = UI:CreateButton(f, "", 60, SP.HIT)
                fit(b, B:RoleName(ROLE_OF[letter]))
                -- Worn once as each look it takes (the one I would ask as is the primary): a look's art
                -- is made the first time a button wears it, never on a later repaint.
                UI:SetButtonVariant(b, "primary")
                UI:SetButtonVariant(b, nil)
                f.join[letter] = b
            end
            return f
        end)
        local key, name = g.key, g.name
        local inner = w - 24
        local X = 12 + ACT_ICON + 12
        local quest = g.quest and Q and Q:Get(g.quest.id)
        e.icon:SetActivity(g.act, g.quest and G:Title(g) or nil)

        -- Line 1: the activity, "for you" on a group of my level with a spot in a role I play (#378),
        -- "you have this quest" on a group for a quest in my log (#450), and how long ago it was listed.
        e.title:ClearAllPoints()
        e.title:SetPoint("TOPLEFT", X, -12)
        e.title:SetText(G:Title(g))
        e.ago:ClearAllPoints()
        e.ago:SetPoint("TOPRIGHT", -12, -14)
        e.ago:SetText(GuildOS:TimeAgo(g.ts))
        local agoW = math.ceil(e.ago:GetStringWidth() or 40)
        if quest then e.questBadge:SetText(L["you have this quest"], C.ok) end
        local badgeW = (forMe and 80 or 0) + (quest and (e.questBadge:GetWidth() or 100) + 8 or 0)
        oneLine(e.title, math.min(math.ceil(e.title:GetStringWidth() or 100) + 4, inner - X - agoW - badgeW - 12))
        if forMe then
            e.badge:SetText(L["for you"], C.ok)
            e.badge:ClearAllPoints()
            e.badge:SetPoint("LEFT", e.title, "RIGHT", 8, 0)
            e.badge:Show()
        else
            e.badge:Hide()
        end
        e.questBadge:SetShown(quest ~= nil)
        if quest then
            e.questBadge:ClearAllPoints()
            e.questBadge:SetPoint("LEFT", forMe and e.badge or e.title, "RIGHT", 8, 0)
        end

        -- Line 2: who leads, in their class's ink, the level range; how full and for how long.
        local classFile = classByKey[key]
        e.avatar:ClearAllPoints()
        e.avatar:SetPoint("TOPLEFT", X, -34)
        e.avatar:SetMember(name, classFile)
        e.lead:ClearAllPoints()
        e.lead:SetPoint("TOPLEFT", X + 18 + 6, -35)
        e.lead:SetText(string.format(L["led by %s"], coloured(name, classFile, true)))
        local it = Cat.byId[g.act]
        local range = (quest and quest.level) and tostring(quest.level) or (not g.quest and rangeOf(it) or "")
        e.range:SetText(range ~= "" and string.format(L["Level %s"], range) or "")
        e.when:SetText(whenText(g, now))
        e.when:ClearAllPoints()
        e.when:SetPoint("TOPRIGHT", -12, -37)
        local whenW = math.ceil(e.when:GetStringWidth() or 60)
        local leadW = math.min(math.ceil(e.lead:GetStringWidth() or 80) + 4, inner - X - 24 - whenW - 12)
        oneLine(e.lead, leadW)
        e.range:ClearAllPoints()
        e.range:SetPoint("TOPLEFT", e.lead, "TOPRIGHT", 8, -2)
        oneLine(e.range, math.max(10, inner - X - 24 - leadW - whenW - 24))
        e.range:SetShown(inner - X - 24 - leadW - whenW - 24 > 30)

        -- Line 3: the note, when there is one.
        local noteY = 58
        local hasNote = (g.note or "") ~= ""
        e.note:ClearAllPoints()
        e.note:SetPoint("TOPLEFT", X, -noteY)
        e.note:SetText(g.note or "")
        oneLine(e.note, inner - X)
        e.note:SetShown(hasNote)
        local seatsY = hasNote and (noteY + 24) or noteY

        -- The actions (#341): ask for a spot in a role it has open, or take the ask back.
        local asked = G:Asked(key)
        local buttons = { e.whisper }
        e.whisper:SetScript("OnClick", function() whisper(name) end)
        e.cancel:Hide()
        for _, letter in ipairs(LETTERS) do e.join[letter]:Hide() end
        local status
        if asked and asked.state == "pending" then
            e.cancel:Show()
            e.cancel:SetScript("OnClick", function() G:CancelRequest(key) end)
            buttons[#buttons + 1] = e.cancel
            status = string.format(L["asked as %s"], B:RoleName(ROLE_OF[asked.role]))
        elseif asked then
            status = L["no spot for you"]
        else
            local best = G:BestRole(g.need, B:Pref("roles") or "")
            for i = #LETTERS, 1, -1 do
                local letter = LETTERS[i]
                if (g.need[letter] or 0) > 0 then
                    local b = e.join[letter]
                    UI:SetButtonVariant(b, letter == best and "primary" or nil)
                    b:Show()
                    b:SetScript("OnClick", function() G:RequestSpot(key, letter) end)
                    buttons[#buttons + 1] = b
                end
            end
            status = L["ask for a spot as"]
        end
        local taken = rightAlign(e, buttons, -(seatsY - 4), 12)
        e.status:SetText(status)
        local statusW = math.ceil(e.status:GetStringWidth() or 60)
        e.status:ClearAllPoints()
        e.status:SetPoint("TOPRIGHT", e, "TOPRIGHT", -(12 + taken + 8), -(seatsY + 2))

        -- The seats and what is missing, in what the buttons leave.
        local room = inner - X - taken - statusW - 24
        local open, after = paintSeats(e, g, X, seatsY, math.max(SLOT, math.floor(room * 0.6)))
        e.missing:ClearAllPoints()
        e.missing:SetPoint("TOPLEFT", e, "TOPLEFT", after, -(seatsY + 2))
        e.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        -- What the buttons say goes first where there is no room for both.
        local showStatus = room > 40 + 120
        e.status:SetShown(showStatus)
        local missW = (12 + inner) - after - taken - (showStatus and (statusW + 8) or 0) - 20
        oneLine(e.missing, missW)
        e.missing:SetShown(missW > 30)

        local h = seatsY + SP.HIT + 12
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        e:SetSize(w, h)
        return y + h + 10
    end

    ------------------------------------------------------------------
    -- A player looking: a row of the list
    ------------------------------------------------------------------
    local function seekerHeader(card, y, w, cols)
        local h = P.acquire("seekhead" .. card.pk, function()
            local f = UI:CreateTableHeader(card)
            f.cols = {}
            for i = 1, 4 do f.cols[i] = UI:CreateHeaderText(f, "", UI.SP.META) end
            return f
        end)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        h:SetWidth(w)
        local titles = { { L["Member"], 0 }, { cols.level and L["Lv "] or "", cols.level or 0 }, { L["Role"], cols.roles },
            { L["Activity"], cols.what } }
        for i, t in ipairs(titles) do
            h.cols[i]:ClearAllPoints()
            h.cols[i]:SetPoint("LEFT", t[2] + (i == 1 and (AVATAR + 8) or 0), 0)
            h.cols[i]:SetText(t[1])
        end
        return y + 24
    end

    local function seekerRow(card, e, now, classByKey, levelByKey, mine, y, w, cols, fits, questMark)
        local row = P.acquire("seeker" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            -- A player who fits the group being formed (#449): a green wash and a bar at the row's left.
            local okInk = UI:Ink("paper", C.ok)
            f.fitWash = f:CreateTexture(nil, "BACKGROUND")
            f.fitWash:SetTexture(WHITE)
            f.fitWash:SetPoint("TOPLEFT", -8, 0)
            f.fitWash:SetPoint("BOTTOMRIGHT", 0, 1)
            f.fitWash:SetVertexColor(okInk.r, okInk.g, okInk.b, 0.10)
            f.fitBar = f:CreateTexture(nil, "ARTWORK")
            f.fitBar:SetTexture(WHITE)
            f.fitBar:SetWidth(3)
            f.fitBar:SetPoint("TOPLEFT", -8, 0)
            f.fitBar:SetPoint("BOTTOMLEFT", -8, 1)
            f.fitBar:SetVertexColor(okInk.r, okInk.g, okInk.b, 1)
            f.avatar = UI:CreateAvatar(f, AVATAR, false)
            f.avatar:SetPoint("LEFT", 0, 0)
            f.nameBtn = CreateFrame("Button", nil, f)
            f.nameBtn:SetPoint("LEFT", AVATAR + 8, 0)
            f.nameBtn:SetSize(NAME_W, SP.HIT)
            f.name = text(f.nameBtn, SP.BODY, nil, "memberName")
            f.name:SetPoint("LEFT")
            oneLine(f.name, NAME_W - 6)
            f.levelText = text(f, SP.META, C.textSoft)
            f.roleIcons = {}
            for i = 1, #LETTERS do
                local t = f:CreateTexture(nil, "ARTWORK")
                t:SetSize(ICON, ICON)
                t:Hide()
                f.roleIcons[i] = t
            end
            f.roles = text(f, SP.META, C.textSoft)
            f.what = text(f, SP.BODY, C.textSoft)
            f.time = text(f, SP.META, C.labelDim)
            f.questMark = text(f, SP.META, C.ok)
            f.invite = fit(UI:CreateButton(f, "", 60, SP.HIT), L["Invite"])
            f.whisper = fit(UI:SetButtonVariant(UI:CreateButton(f, "", 60, SP.HIT), "ghost"), L["Whisper"])
            f.you = text(f, SP.META, C.textSoft)
            f.you:SetText(L["(you)"])
            f.extend = fit(UI:CreateButton(f, "", 60, SP.HIT), L["+30 min"])
            f.extend:SetScript("OnClick", function() B:Extend() end)
            rowRule(f)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        row:SetSize(w, SP.ROW_AV)
        row.fits = fits and true or false
        row.fitWash:SetShown(row.fits)
        row.fitBar:SetShown(row.fits)
        local isMe = e.key ~= nil and e.key == mine
        local name = e.name
        -- An allied listing carries no key, so no class or level: those stay blank, never guessed.
        local classFile = e.key and classByKey[e.key]
        row.avatar:SetMember(name, classFile)
        row.name:SetText(coloured(name, classFile, true))
        local level = e.key and levelByKey[e.key]
        row.levelText:SetText(level and (L["Lv "] .. level) or "")
        row.levelText:ClearAllPoints()
        row.levelText:SetPoint("LEFT", cols.level or 0, 0)
        row.levelText:SetShown(cols.level ~= nil)
        -- The roles as the game's icons; spelled out where the client has none, and "Any" for none.
        local roles, shown = e.roles or "", 0
        if roleArtKind() then
            for _, letter in ipairs(LETTERS) do
                if roles:find(letter, 1, true) then
                    shown = shown + 1
                    local t = row.roleIcons[shown]
                    t:ClearAllPoints()
                    t:SetPoint("LEFT", cols.roles + (shown - 1) * (ICON + 4), 0)
                    setRoleIcon(t, letter)
                end
            end
        end
        for i = shown + 1, #LETTERS do row.roleIcons[i]:Hide() end
        row.roles:ClearAllPoints()
        row.roles:SetPoint("LEFT", cols.roles, 0)
        row.roles:SetText(shown > 0 and "" or roleNames(roles))
        oneLine(row.roles, ROLES_W - 4)
        -- An allied listing is read, not acted on (as the board before #341).
        local allied = e.key == nil
        row.nameBtn:EnableMouse(not isMe and not allied)
        row.nameBtn:SetScript("OnClick", function() whisper(name) end)
        local buttons = {}
        row.invite:Hide()
        row.whisper:Hide()
        row.extend:SetShown(isMe)
        row.you:SetShown(isMe)
        if isMe then
            buttons = { row.extend }
        elseif not allied then
            -- Who invites: the leader of a listed group invites in the role they fit, keeping their spot
            -- (#378); anybody free to invite invites them into a party. Whisper always.
            buttons = { row.whisper }
            if GuildOS.Compat.CanInvite() then
                buttons[#buttons + 1] = row.invite
                row.invite:SetScript("OnClick", function()
                    local g = G:Mine()
                    local role = g and G:BestRole(g.need, e.roles or "")
                    if role and G:InviteSeeker(e.key, name, role) then return end
                    GuildOS.Compat.InviteUnit(name)
                end)
            end
            row.whisper:SetScript("OnClick", function() whisper(name) end)
        end
        for _, b in ipairs(buttons) do b:Show() end
        local taken = #buttons > 0 and rightAlign(row, buttons, -((SP.ROW_AV - SP.HIT) / 2), 0) or 0
        if isMe then
            row.you:ClearAllPoints()
            row.you:SetPoint("RIGHT", row, "RIGHT", -(taken + 8), 0)
            taken = taken + math.ceil(row.you:GetStringWidth() or 30) + 8
        end
        row.time:ClearAllPoints()
        row.time:SetPoint("RIGHT", row, "RIGHT", -(taken + 8), 0)
        row.time:SetText(string.format(L["%dm"], B:_Remaining(e, now)))
        local timeW = math.ceil(row.time:GetStringWidth() or 24) + 8
        -- On a quest of mine, or of the group being formed (#450): said in the green ink, before the time.
        row.questMark:SetText(questMark or "")
        row.questMark:SetShown(questMark ~= nil)
        if questMark then
            row.questMark:ClearAllPoints()
            row.questMark:SetPoint("RIGHT", row, "RIGHT", -(taken + timeW), 0)
            timeW = timeW + math.ceil(row.questMark:GetStringWidth() or 60) + 8
        end
        local what = e.guild and e.note or B:Describe(e)
        row.what:ClearAllPoints()
        row.what:SetPoint("LEFT", cols.what, 0)
        row.what:SetText(what ~= "" and what or L["Anything"])
        local whatW = w - cols.what - taken - timeW - SP.CELL - 8
        oneLine(row.what, whatW)
        row.what:SetShown(whatW > 30)
        return y + SP.ROW_AV
    end

    ------------------------------------------------------------------
    -- My group, as the leader sees it (#378): its seats, how full it is, what a leader does from
    -- here, the queue and who fits it
    ------------------------------------------------------------------
    local mine = {}
    do
        local f = mineCard
        f.icon = activityIcon(f, ACT_ICON)
        f.slots = {}
        f.more = text(f, SP.META, C.labelDim)
        f.missing = text(f, SP.META, C.textSoft)
        f.badge = UI:CreateBadge(f, "", C.info)
        f.left = text(f, SP.META, C.textSoft)
        f.fill = UI:CreateProgressBar(f, 120, 6)
        f.fillText = text(f, SP.META, C.textSoft)
        f.meta = text(f, SP.BODY, C.textSoft)
        f.down = fit(UI:SetButtonVariant(UI:CreateButton(f, "", 60, SP.FIELD), "danger"), L["Take down"])
        f.down:SetScript("OnClick", function() G:Disband() end)
        f.edit = fit(UI:CreateButton(f, "", 60, SP.FIELD), L["Change"])
        f.edit:SetScript("OnClick", function() openGroupForm() end)
        f.extend = fit(UI:CreateButton(f, "", 60, SP.FIELD), L["+30 min"])
        f.extend:SetScript("OnClick", function() G:Extend() end)
        f.post = UI:CreateButton(f, "", 60, SP.FIELD)
        f.post:SetScript("OnClick", function()
            G:PostNow()
            paint()
        end)
        f.ready = fit(UI:CreateButton(f, "", 60, SP.FIELD), L["Ready check"])
        f.ready:SetScript("OnClick", function() G:ReadyCheck() end)
        mine.card = f
    end

    local function requestRow(card, r, classByKey, y, w)
        local row = P.acquire("request" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            f.avatar = UI:CreateAvatar(f, AVATAR, false)
            f.avatar:SetPoint("LEFT", 0, 0)
            f.name = text(f, SP.BODY)
            f.name:SetPoint("LEFT", AVATAR + 8, 0)
            f.state = text(f, SP.META, C.textSoft)
            f.invite = fit(UI:SetButtonVariant(UI:CreateButton(f, "", 60, SP.HIT), "primary"), L["Invite"])
            f.decline = fit(UI:CreateButton(f, "", 60, SP.HIT), L["Decline"])
            rowRule(f)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        row:SetSize(w, SP.ROW_AV)
        row.avatar:SetMember(r.name, classByKey[r.key])
        local c = ink(card, roleColor(r.role))
        row.name:SetText(coloured(r.name, classByKey[r.key], true) .. "  " ..
            GuildOS:ColorText(B:RoleName(ROLE_OF[r.role]), c.r, c.g, c.b))
        local taken = rightAlign(row, { row.decline, row.invite }, -((SP.ROW_AV - SP.HIT) / 2), 0)
        row.state:ClearAllPoints()
        row.state:SetPoint("RIGHT", row, "RIGHT", -(taken + 8), 0)
        row.state:SetText(r.state == "invited" and L["invited"] or "")
        oneLine(row.name, w - AVATAR - 8 - taken - 70)
        local key = r.key
        row.invite:SetScript("OnClick", function() G:Invite(key) end)
        row.decline:SetScript("OnClick", function() G:Decline(key) end)
        return y + SP.ROW_AV
    end

    -- A player looking who fits my group (#378): who, their level, what they wrote, and one click to
    -- invite them in the role they fit.
    local function matchRow(card, m, classByKey, levelByKey, y, w)
        local row = P.acquire("match" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
            f.avatar = UI:CreateAvatar(f, AVATAR, false)
            f.avatar:SetPoint("LEFT", 0, 0)
            f.name = text(f, SP.BODY)
            f.name:SetPoint("LEFT", AVATAR + 8, 0)
            f.what = text(f, SP.BODY, C.textSoft)
            f.invite = UI:SetButtonVariant(UI:CreateButton(f, "", 60, SP.HIT), "primary")
            rowRule(f)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", SP.PAD, -y)
        row:SetSize(w, SP.ROW_AV)
        row.avatar:SetMember(m.name, classByKey[m.key])
        local level = levelByKey[m.key]
        local soft = ink(card, C.textSoft)
        row.name:SetText(coloured(m.name, classByKey[m.key], true) ..
            (level and ("  |cff" .. hexOf(soft.r, soft.g, soft.b) .. L["Lv "] .. level .. "|r") or ""))
        oneLine(row.name, NAME_W + LEVEL_W)
        fit(row.invite, string.format(L["Invite as %s"], B:RoleName(ROLE_OF[m.role])))
        local taken = rightAlign(row, { row.invite }, -((SP.ROW_AV - SP.HIT) / 2), 0)
        local what = B:Describe(m.entry)
        if m.quest then
            local k = ink(card, C.ok)
            what = GuildOS:ColorText(L["also on this quest"], k.r, k.g, k.b) .. (what ~= "" and (DOT .. what) or "")
        end
        row.what:ClearAllPoints()
        row.what:SetPoint("LEFT", AVATAR + 8 + NAME_W + LEVEL_W + SP.CELL, 0)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, w - (AVATAR + 8 + NAME_W + LEVEL_W + SP.CELL) - taken - 8)
        local key, name, role = m.key, m.name, m.role
        row.invite:SetScript("OnClick", function() G:InviteSeeker(key, name, role) end)
        return y + SP.ROW_AV
    end

    local function paintMine(g, now, onlineSet, classByKey, levelByKey, w)
        local f = mine.card
        f:SetWidth(w)
        local inner = w - 2 * SP.PAD
        f.title:SetText(string.format(L["Your group: %s"], G:Title(g)))
        f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local y = SP.TOP
        f.icon:ClearAllPoints()
        f.icon:SetPoint("TOPLEFT", SP.PAD, -y)
        f.icon:SetActivity(g.act, g.quest and G:Title(g) or nil)
        local X = SP.PAD + ACT_ICON + 12

        -- Right of the line: when it starts, how long it stays up.
        local startIn = G:StartsIn(g, now)
        f.left:SetText(string.format(L["%dm left"], B:_Remaining(g, now)))
        f.left:ClearAllPoints()
        f.left:SetPoint("TOPRIGHT", -SP.PAD, -(y + 1))
        local leftW = math.ceil(f.left:GetStringWidth() or 50)
        if startIn then
            f.badge:SetText(string.format(L["starts in %dm"], math.ceil(startIn / 60)), C.info)
            f.badge:ClearAllPoints()
            f.badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(SP.PAD + leftW + 10), -y)
            f.badge:Show()
            leftW = leftW + 10 + (f.badge:GetWidth() or 80)
        else
            f.badge:Hide()
        end

        -- The seats and what is missing, then how full it is as a bar.
        local room = SP.PAD + inner - X - leftW - 12
        local open, after = paintSeats(f, g, X, y, math.max(SLOT, math.floor(room * 0.6)))
        f.missing:ClearAllPoints()
        f.missing:SetPoint("TOPLEFT", f, "TOPLEFT", after, -(y + 2))
        f.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        oneLine(f.missing, math.max(10, SP.PAD + inner - leftW - 12 - after))
        local max = g.max or 5
        f.fill:ClearAllPoints()
        f.fill:SetPoint("TOPLEFT", X, -(y + SLOT + 8))
        f.fill:SetWidth(math.max(60, math.min(240, math.floor(inner * 0.3))))
        f.fill:SetProgress((g.n or 1) / max)
        f.fillText:ClearAllPoints()
        f.fillText:SetPoint("LEFT", f.fill, "RIGHT", 8, 0)
        f.fillText:SetText(string.format("%d/%d", g.n or 1, max))
        y = y + ACT_ICON + SP.FIELD_GAP

        -- The actions, right; the note, left, in what they leave.
        local wait = B:GuildLineWait(now)
        fit(f.post, wait > 0 and (L["Post in chat"] .. " (" .. string.format(L["in %dm"], math.ceil(wait / 60)) .. ")")
            or L["Post in chat"])
        if wait > 0 then f.post:Disable() else f.post:Enable() end
        local buttons = { f.down, f.edit, f.extend, f.post }
        if G:CanReadyCheck() then
            f.ready:Show()
            buttons[#buttons + 1] = f.ready
        else
            f.ready:Hide()
        end
        local taken = rightAlign(f, buttons, -y, SP.PAD)
        f.meta:ClearAllPoints()
        f.meta:SetPoint("TOPLEFT", SP.PAD, -(y + 5))
        f.meta:SetText(g.note or "")
        oneLine(f.meta, inner - taken - 12)
        y = y + SP.FIELD + SP.SECTION

        -- The queue, and who is looking and fits.
        local requests = G:Requests()
        if #requests == 0 then
            y = line(f, L["Nobody asked for a spot yet. Guildmates see your group here and in the tiles."], y, inner)
        else
            y = section(f, L["Asking for a spot"], #requests, y, inner)
            for _, r in ipairs(requests) do y = requestRow(f, r, classByKey, y, inner) end
            y = y + SP.FIELD_GAP
        end
        local matches = G:Matches(now, onlineSet)
        if #matches > 0 then
            y = y + SP.SECTION - SP.FIELD_GAP
            y = section(f, L["Fits your group"], #matches, y, inner)
            for i = 1, math.min(#matches, SEEKERS_MAX) do y = matchRow(f, matches[i], classByKey, levelByKey, y, inner) end
        end
        f:SetHeight(y + SP.PAD - 6)
        return f:GetHeight()
    end

    ------------------------------------------------------------------
    -- Reading what is there
    ------------------------------------------------------------------
    -- The levels of the guildmates online, keyed as the board keys them (LFGBoard:_BuildOnlineRoster).
    local function rosterLevels()
        local out = {}
        for i = 1, GetNumGuildMembers() or 0 do
            local full, _, _, level, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if full and isOnline and type(level) == "number" and level > 0 then
                local short = full:match("^([^-]+)") or full
                out[GuildOS:GetPlayerKey(short, full:match("-(.+)$") or GetRealmName())] = level
            end
        end
        return out
    end

    -- Which activities a filter keeps (#378): its category, and with "my level only" those of my level.
    local function keeps(act, cat, levelOnly, myLevel)
        local it = Cat.byId[act]
        if cat ~= "all" and (not it or it.cat ~= cat) then return false end
        return not levelOnly or G:FitsLevel(act, myLevel)
    end
    -- A player looking with no activity named wants anything: every filter keeps them.
    local function keepsSeeker(e, cat, levelOnly, myLevel)
        if #(e.acts or {}) == 0 then return true end
        for _, act in ipairs(e.acts) do
            if keeps(act, cat, levelOnly, myLevel) then return true end
        end
        return false
    end

    -- The columns of the players' list at its width: the level and the roles go where there is room.
    local function seekerCols(w)
        local x = AVATAR + 8 + NAME_W + SP.CELL
        local cols = {}
        if w >= 460 then cols.level = x; x = x + LEVEL_W end
        cols.roles = x
        x = x + ROLES_W + SP.CELL
        cols.what = x
        return cols
    end

    ------------------------------------------------------------------
    -- The forms (#449, option E): no window of their own. "+ Form a group" turns the left column into
    -- "Form a group", in two steps: what it is for, picked as a card, then who and when. "I am looking"
    -- turns the right one into the same cards, several at once, with my roles and how long. Each is a
    -- parchment card laid out by UI/Forms.lua's rows; Esc or Cancel goes back to the lists. While a group
    -- is being formed, the players' list lights who would fit it.
    ------------------------------------------------------------------
    local Forms = GuildOS.Forms
    local TILE_H, TILE_GAP = 64, 8
    local GRID_TWO = 440                 -- a grid's width from which its cards go two to a row
    local GRID_MIN_ROWS = 2              -- the rows a grid shows before its column's room gives it more
    local HEAD_H = 16 + SP.LABEL_GAP     -- a field group's small-caps title over its controls
    local NOTE_MAX = 60

    local function has(list, id)
        for _, x in ipairs(list) do if x == id then return true end end
        return false
    end

    -- A checkbox as wide as its label (UI:CreateCheckbox), with the Place(w) a Forms pair lays it by.
    local function smallCheck(host, label)
        local f = UI:CreateCheckbox(host, label, 18)
        if f.checkbox then
            f.checkbox:ClearAllPoints()
            f.checkbox:SetPoint("LEFT", f, "LEFT", 2, 0)
        end
        if f.label then
            f.label:ClearAllPoints()
            f.label:SetPoint("LEFT", f, "LEFT", 24, 0)
            f.label:SetJustifyH("LEFT")
            f.label:SetWordWrap(false)
        end
        local function natural() return 24 + math.ceil(f.label and f.label:GetStringWidth() or 60) + 2 end
        f:SetSize(natural(), 18)
        function f:Place(w)
            self:SetSize(math.max(24, math.min(w, natural())), 18)
            if self.label then self.label:SetWidth(math.max(1, self:GetWidth() - 24)) end
            return 18
        end
        return f
    end

    -- Items along a line from `y` in `holder`, wrapping at `w`; returns the y under them.
    local function flowAt(holder, items, y, w)
        local x = 0
        for _, it in ipairs(items) do
            if x > 0 and x + it:GetWidth() > w then
                x = 0
                y = y + SP.HIT + 6
            end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
            x = x + it:GetWidth() + 6
        end
        return y + SP.HIT
    end

    -- A light box on the paper (a card of the grid, the picked one, the chat line): `on` is the chosen look,
    -- the soft gold with the bright metal's line.
    local function paperFill(f)
        local Style = GuildOS.Style
        if Style and Style.Nine then
            f.fill = Style:Nine(f, "card", 6, "BACKGROUND", -6)
            f.edge = Style:Nine(f, "card-line", 6, "BACKGROUND", -5)
        end
        function f:SetChosen(on)
            if not self.fill then return end
            self.fill:SetColor(on and C.gold2 or C.paperLight, on and 0.45 or 0.55)
            self.edge:SetColor(on and C.metal2 or C.paperLine)
        end
        f:SetChosen(false)
        return f
    end

    -- An activity as a card (#449): its emblem, its name, "Level a-b · group of n", and who is already
    -- forming or looking for it, in the green ink, or "quiet". A chosen one is gold, with the tick.
    local function newTile(host)
        local t = paperFill(CreateFrame("Button", nil, host))
        t.isActivityTile = true
        t.icon = activityIcon(t, ACT_ICON, true)
        t.icon:SetPoint("LEFT", 12, 0)
        t.name = text(t, SP.BODY, nil, "button")
        t.meta = text(t, SP.META, C.textSoft)
        t.live = text(t, SP.META, C.ok)
        t.check = checkMark(t)
        t.check:SetPoint("TOPRIGHT", -8, -8)
        t:SetScript("OnEnter", function(self) if self.edge and not self.on then self.edge:SetColor(C.paperEdge) end end)
        t:SetScript("OnLeave", function(self) self:SetChosen(self.on) end)
        return t
    end

    local function liveText(act)
        local c = V.counts and V.counts[questOf(act) or act]
        local parts = {}
        if c and c.groups > 0 then parts[#parts + 1] = string.format(L["%d forming"], c.groups) end
        if c and c.seekers > 0 then parts[#parts + 1] = string.format(L["%d looking"], c.seekers) end
        return table.concat(parts, DOT)
    end

    local function metaText(it)
        local parts = {}
        local range = rangeOf(it)
        if range ~= "" then parts[#parts + 1] = string.format(L["Level %s"], range) end
        parts[#parts + 1] = string.format(L["group of %d"], it.size or 5)
        return table.concat(parts, DOT)
    end

    -- A quest of my log as a card (#450): "Level 62 · Elite · group of 3", then who is on it, or its zone.
    local function questMeta(q)
        local parts = {}
        if q.level then parts[#parts + 1] = string.format(L["Level %s"], tostring(q.level)) end
        local tag = q.tag or (q.elite and L["Elite"]) or nil
        if tag then parts[#parts + 1] = tag end
        if (q.size or 0) > 1 then parts[#parts + 1] = string.format(L["group of %d"], q.size) end
        return table.concat(parts, DOT)
    end

    local function paintTile(t, it, on, w)
        t:SetSize(w, TILE_H)
        t.act, t.on = it.id, on and true or false
        if it.quest then
            local q = it.quest
            t.quest = q.id
            t.icon:SetActivity(B.QUEST_ACT, q.title)
            local X = 12 + ACT_ICON + 10
            t.name:ClearAllPoints()
            t.name:SetPoint("TOPLEFT", X, -10)
            t.name:SetText(q.title)
            oneLine(t.name, w - X - 12 - (t.on and 20 or 0))
            t.meta:ClearAllPoints()
            t.meta:SetPoint("TOPLEFT", X, -28)
            t.meta:SetText(questMeta(q))
            oneLine(t.meta, w - X - 12)
            local live = liveText(it.id)
            local k = ink(t, live ~= "" and C.ok or C.textSoft)
            t.live:SetTextColor(k.r, k.g, k.b)
            t.live:ClearAllPoints()
            t.live:SetPoint("TOPLEFT", X, -43)
            t.live:SetText(live ~= "" and live or (q.zone or L["quiet"]))
            oneLine(t.live, w - X - 12)
            t.check:SetShown(t.on)
            t:SetChosen(t.on)
            return
        end
        t.quest = nil
        t.icon:SetActivity(it.id)
        local X = 12 + ACT_ICON + 10
        t.name:ClearAllPoints()
        t.name:SetPoint("TOPLEFT", X, -10)
        t.name:SetText(B:ActivityName(it.id))
        oneLine(t.name, w - X - 12 - (t.on and 20 or 0))
        t.meta:ClearAllPoints()
        t.meta:SetPoint("TOPLEFT", X, -28)
        t.meta:SetText(metaText(it))
        oneLine(t.meta, w - X - 12)
        local live = liveText(it.id)
        local k = ink(t, live ~= "" and C.ok or C.textSoft)
        t.live:SetTextColor(k.r, k.g, k.b)
        t.live:ClearAllPoints()
        t.live:SetPoint("TOPLEFT", X, -43)
        t.live:SetText(live ~= "" and live or L["quiet"])
        oneLine(t.live, w - X - 12)
        t.check:SetShown(t.on)
        t:SetChosen(t.on)
    end

    -- A form's card: its title, the step on the right of it, the rows (UI/Forms.lua's) and the foot: a
    -- hairline, Cancel on the left, the form's action on the right.
    local function formCard(title)
        local c = newCard(content, title)
        c.rows = {}
        for k, fn in pairs(Forms.CardMethods) do c[k] = fn end
        c.stepText = text(c, SP.META, C.textSoft)
        c.stepText:SetPoint("TOPRIGHT", -SP.PAD, -(SP.PAD + 3))
        c.stepText:SetJustifyH("RIGHT")
        c.foot = CreateFrame("Frame", nil, c)
        c.foot:SetPoint("BOTTOMLEFT", SP.PAD, SP.PAD)
        c.foot:SetPoint("BOTTOMRIGHT", -SP.PAD, SP.PAD)
        c.foot:SetHeight(SP.FIELD + SP.FIELD_GAP)
        local rule = UI:CreateSeparator(c.foot)
        rule:SetPoint("TOPLEFT", 0, 0)
        rule:SetPoint("TOPRIGHT", 0, 0)
        c.cancel = Forms:Button(c.foot, L["Cancel"])
        c.cancel:SetPoint("BOTTOMLEFT", 0, 0)
        c.cancel:SetScript("OnClick", function() closeForm() end)
        c.action = Forms:Button(c.foot, "", "primary")
        c.action:SetPoint("BOTTOMRIGHT", 0, 0)
        c:Hide()
        return c
    end

    -- Lay a form out at `w`, at least `minH` tall: the rows from the top, the foot at the bottom, the grid
    -- (the fill row) taking the room between. Returns the height.
    local function layoutForm(c, w, minH)
        local footH = c.foot:GetHeight()
        local function total(extra) return (c:LayoutRows(w, extra) - SP.PAD) + SP.FIELD_GAP + footH + SP.PAD end
        local h = total(0)
        if (minH or 0) > h then h = math.max(minH, total(minH - h)) end
        c:SetSize(w, h)
        return h
    end

    -- The categories as pills and "My level only", the line over a grid.
    local function addCategoryRow(c, shown)
        local holder = CreateFrame("Frame", nil, c)
        holder:SetSize(1, 1)
        holder.pills = {}
        for _, def in ipairs(FILTERS) do
            if def.key ~= "all" then
                local p = Forms:Pill(holder, def.label)
                local key = def.key
                p.catKey = key
                p:SetScript("OnClick", function()
                    V.cat = key
                    paint()
                end)
                holder.pills[#holder.pills + 1] = p
            end
        end
        local mq = Forms:Pill(holder, L["My quests"])
        mq.catKey = QUEST_CAT
        mq:SetScript("OnClick", function()
            V.cat = QUEST_CAT
            paint()
        end)
        holder.pills[#holder.pills + 1] = mq
        local lv = smallCheck(holder, L["My level only"])
        lv.isLevelOnly = true
        lv.checkbox.onChanged = function(_, checked)
            V.levelOnly = checked and true or false
            paint()
        end
        c:Add(holder, { shown = shown, place = function(_, w)
            local x, py = 0, 0
            for _, p in ipairs(holder.pills) do
                Forms:SetOn(p, p.catKey == V.cat)
                if x > 0 and x + p:GetWidth() > w then x, py = 0, py + SP.HIT + 6 end
                p:ClearAllPoints()
                p:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -py)
                x = x + p:GetWidth() + 6
            end
            lv.checkbox:SetChecked(V.levelOnly)
            lv:SetShown(V.cat ~= QUEST_CAT)   -- the quests of my log are mine whatever my level
            lv:Place(w)
            local h = py + SP.HIT
            lv:ClearAllPoints()
            if x + SP.CELL + lv:GetWidth() <= w then
                lv:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(py + 3))
            else
                lv:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(py + SP.HIT + 8))
                h = py + SP.HIT + 8 + 18
            end
            holder:SetSize(math.max(1, w), h)
            return h
        end })
        return holder
    end

    -- The cards of the category picked, as a grid that scrolls inside the form once it outgrows its room.
    -- `isOn(id)`: whether a card is chosen; `onPick(id)`: its click.
    local function addGrid(c, isOn, onPick, shown)
        local holder = CreateFrame("Frame", nil, c)
        holder:SetSize(1, 1)
        local sc, child = UI:CreateScrollFrame(holder)
        sc:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        child:SetSize(1, 1)
        local empty = text(holder, SP.BODY, C.textSoft)
        empty:SetPoint("TOPLEFT", 0, -2)
        empty:SetText(L["No activity of this kind for your level."])
        holder.scroll, holder.child, holder.tiles = sc, child, {}
        local lastCat
        c:Add(holder, { shown = shown, fill = true, place = function(_, w, extra)
            local items = V.cat == QUEST_CAT and questItems() or activitiesOf(V.cat, V.levelOnly, UnitLevel("player") or 1)
            empty:SetText(V.cat == QUEST_CAT and L["Your quest log has no quest."] or L["No activity of this kind for your level."])
            -- What is busy tonight first (somebody forming or looking for it), the catalogue's order kept.
            local rank = {}
            for i, it in ipairs(items) do rank[it] = (liveText(it.id) ~= "" and 0 or 10000) + i end
            table.sort(items, function(a, b) return rank[a] < rank[b] end)
            local cols = w >= GRID_TWO and 2 or 1
            local rows = math.ceil(#items / cols)
            local needed = rows > 0 and (rows * TILE_H + (rows - 1) * TILE_GAP) or 0
            local base = math.min(needed, GRID_MIN_ROWS * TILE_H + (GRID_MIN_ROWS - 1) * TILE_GAP)
            local h = math.min(needed, base + (extra or 0))
            empty:SetShown(#items == 0)
            sc:SetShown(#items > 0)
            if #items == 0 then
                empty:SetWidth(math.max(1, w))
                h = 20
            end
            local cw = (needed > h + 0.5) and (w - UI.SCROLL_GUTTER) or w
            sc:SetSize(math.max(1, w), math.max(1, h))
            child:SetSize(math.max(1, cw), math.max(1, needed))
            -- Another category or level: the grid starts from its top again.
            local shownNow = V.cat .. (V.levelOnly and "+" or "-")
            if shownNow ~= lastCat then
                sc:SetVerticalScroll(0)
                lastCat = shownNow
            end
            local tw = math.floor((cw - (cols - 1) * TILE_GAP) / cols)
            for i, it in ipairs(items) do
                local t = holder.tiles[i] or newTile(child)
                holder.tiles[i] = t
                t:Show()
                local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", child, "TOPLEFT", col * (tw + TILE_GAP), -row * (TILE_H + TILE_GAP))
                paintTile(t, it, isOn(it.id), tw)
                local id = it.id
                t:SetScript("OnClick", function() onPick(id) end)
            end
            for i = #items + 1, #holder.tiles do holder.tiles[i]:Hide() end
            holder:SetSize(math.max(1, w), math.max(1, h))
            return h
        end })
        return holder
    end

    -- A group of pills under a small-caps title (Starts, Listed for, My roles): `values` and the label of
    -- each; `pick(v)` on a click, `isOn(v)` lights it. Returns { head, pills, Lay(holder, y, w) -> y }.
    local function pillGroup(holder, title, values, label, pick, isOn)
        local g = { head = UI:CreateHeaderText(holder, title), pills = {} }
        g.head:SetJustifyH("LEFT")
        for _, v in ipairs(values) do
            local p = Forms:Pill(holder, label(v))
            p.value = v
            p:SetScript("OnClick", function()
                pick(v)
                paint()
            end)
            g.pills[#g.pills + 1] = p
        end
        function g.Lay(_, y, w)
            g.head:ClearAllPoints()
            g.head:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
            for _, p in ipairs(g.pills) do Forms:SetOn(p, isOn(p.value)) end
            return flowAt(holder, g.pills, y + HEAD_H, w)
        end
        return g
    end

    local function noteInput(host)
        local box = UI:CreateInput(host, 200, SP.FIELD, { max = NOTE_MAX })
        box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(s)
            s:ClearFocus()
            closeForm()
        end)
        return box
    end

    ------------------------------------------------------------------
    -- Form a group (the left column)
    ------------------------------------------------------------------
    local formG = formCard(L["Form a group"])
    formG.isGroupForm = true
    local function onStep(n) return function() return V.step == n end end

    local function pickAct(id)
        -- A quest's card (#450): the group is for it, under the catalogue's Elite quests.
        local qid = questOf(id)
        local q = qid and Q and Q:Get(qid)
        local quest = q and { id = q.id, t = q.title } or nil
        local act = quest and B.QUEST_ACT or id
        if act ~= V.act or not V.need then
            local group = G:Mine()
            V.need = (group and group.act == act) and G:_SanitizeNeed(group.need) or defaultNeed(act)
        end
        V.act, V.quest, V.step, V.hint = act, quest, 2, ""
        paint()
    end
    -- One spot more or less, never past the room a group of this size has besides its leader.
    local function stepNeed(letter, by)
        local want = {}
        for _, k in ipairs(LETTERS) do want[k] = V.need[k] or 0 end
        want[letter] = math.max(0, want[letter] + by)
        if G:OpenSpots(want) > G:SizeOf(V.act) - 1 then return end
        V.need, V.hint = want, ""
        paint()
    end

    -- Step 1: what it is for.
    formG.cats = addCategoryRow(formG, onStep(1))
    formG.grid = addGrid(formG, function(id)
        local qid = questOf(id)
        if qid then return V.quest ~= nil and V.quest.id == qid end
        return V.quest == nil and V.act == id
    end, pickAct, onStep(1))
    formG:Note(L["Each card shows who is already forming or looking for it. Pick one to set the spots and the time."],
        { shown = onStep(1) })

    -- Step 2: the card picked, with Change; the open spots beside when it starts and how long it is up.
    local picked = paperFill(CreateFrame("Frame", nil, formG))
    picked:SetChosen(true)
    picked.icon = activityIcon(picked, ACT_ICON, true)
    picked.icon:SetPoint("LEFT", 12, 0)
    picked.name = text(picked, SP.BODY + 1, nil, "button")
    picked.meta = text(picked, SP.META, C.textSoft)
    picked.change = Forms:SmallButton(picked, L["Change"])
    picked.change:SetPoint("RIGHT", -12, 0)
    picked.change:SetScript("OnClick", function()
        V.step, V.hint = 1, ""
        paint()
    end)
    formG.picked = picked
    formG:Add(picked, { shown = onStep(2), place = function(_, w)
        picked:SetSize(w, 56)
        local it = Cat.byId[V.act]
        local q = V.quest and Q and Q:Get(V.quest.id)
        local title = V.quest and G:Title(V) or (V.act and B:ActivityName(V.act) or "")
        picked.icon:SetActivity(V.act, V.quest and title or nil)
        local X = 12 + ACT_ICON + 12
        local room = w - X - picked.change:GetWidth() - 24
        picked.name:ClearAllPoints()
        picked.name:SetPoint("TOPLEFT", X, -12)
        picked.name:SetText(title)
        oneLine(picked.name, room)
        picked.meta:ClearAllPoints()
        picked.meta:SetPoint("TOPLEFT", X, -31)
        picked.meta:SetText((q and questMeta(q)) or (not V.quest and it and metaText(it)) or "")
        oneLine(picked.meta, room)
        return 56
    end })

    local spots = CreateFrame("Frame", nil, formG)
    spots:SetSize(1, 1)
    spots.head = UI:CreateHeaderText(spots, L["OPEN SPOTS"])
    spots.head:SetJustifyH("LEFT")
    spots.head:SetPoint("TOPLEFT", 0, 0)
    spots.rows = {}
    for _, letter in ipairs(LETTERS) do
        local r = { mark = createRoleMark(spots, letter) }
        r.name = text(spots, SP.BODY)
        r.name:SetText(B:RoleName(ROLE_OF[letter]))
        r.minus = UI:CreateButton(spots, "-", SP.HIT, SP.HIT)
        r.minus:SetScript("OnClick", function() stepNeed(letter, -1) end)
        r.value = text(spots, SP.BODY)
        r.value:SetJustifyH("CENTER")
        r.value:SetWidth(28)
        r.plus = UI:CreateButton(spots, "+", SP.HIT, SP.HIT)
        r.plus:SetScript("OnClick", function() stepNeed(letter, 1) end)
        r.minus.stepRole, r.plus.stepRole = letter, letter
        spots.rows[letter] = r
    end
    spots.total = text(spots, SP.META, C.textSoft)
    function spots.Place(_, w)
        local y = HEAD_H
        local sx = math.max(CHIP + 8 + 20, math.min(w - (2 * SP.HIT + 28), CHIP + 8 + 72))
        for _, letter in ipairs(LETTERS) do
            local r = spots.rows[letter]
            r.mark:ClearAllPoints()
            r.mark:SetPoint("TOPLEFT", spots, "TOPLEFT", 0, -y)
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", spots, "TOPLEFT", CHIP + 8, -(y + 6))
            oneLine(r.name, sx - CHIP - 12)
            r.minus:ClearAllPoints()
            r.minus:SetPoint("TOPLEFT", spots, "TOPLEFT", sx, -(y + 1))
            r.value:ClearAllPoints()
            r.value:SetPoint("LEFT", r.minus, "RIGHT", 0, 0)
            r.value:SetText(tostring(V.need[letter] or 0))
            r.plus:ClearAllPoints()
            r.plus:SetPoint("LEFT", r.value, "RIGHT", 0, 0)
            y = y + CHIP + 6
        end
        spots.total:ClearAllPoints()
        spots.total:SetPoint("TOPLEFT", spots, "TOPLEFT", 0, -y)
        spots.total:SetText(string.format(L["You + %d open of %d"], G:OpenSpots(V.need), G:SizeOf(V.act)))
        oneLine(spots.total, w)
        spots:SetSize(math.max(1, w), y + 16)
        return y + 16
    end

    local when = CreateFrame("Frame", nil, formG)
    when:SetSize(1, 1)
    when.starts = pillGroup(when, L["STARTS"], G.STARTS,
        function(s) return s == 0 and L["Now"] or string.format(L["in %dm"], math.floor(s / 60)) end,
        function(s) V.start = s end, function(s) return V.start == s end)
    when.ttls = pillGroup(when, L["LISTED FOR"], B.DURATIONS, function(s) return B:DurationName(s) end,
        function(s) V.ttl = s end, function(s) return V.ttl == s end)
    function when.Place(_, w)
        local y = when.starts.Lay(nil, 0, w)
        y = when.ttls.Lay(nil, y + SP.FIELD_GAP, w)
        when:SetSize(math.max(1, w), y)
        return y
    end
    formG:Pair(spots, when, { shown = onStep(2), split = 0.45 })

    local noteG = noteInput(formG)
    formG:Field(L["Note"], noteG, { shown = onStep(2) })

    local chatG = smallCheck(formG, L["Also post in guild chat"])
    local autoG = smallCheck(formG, L["Invite whoever asks"])
    formG:Pair(chatG, autoG, { shown = onStep(2) })

    -- The line guild chat would get, as Modules/Groups.lua words it; or who sees the group without it.
    local prev = paperFill(CreateFrame("Frame", nil, formG))
    prev.label = text(prev, SP.META, C.textSoft)
    prev.label:SetText(L["Guild chat:"])
    prev.line = text(prev, SP.META, C.ok)
    local function previewLine()
        local _, count = GuildOS.Compat.GroupRoster()
        count = math.max(1, count or 1)
        local g = { act = V.act, quest = V.quest, need = V.need, note = GuildOS:SanitizeUserText(noteG:GetText(), NOTE_MAX), n = count,
                    max = math.max(G:SizeOf(V.act), count),
                    start = (V.start or 0) > 0 and (GetServerTime() + V.start) or nil }
        -- The line says "whisper inv" by the saved choice: the form's, until it is published.
        local prefs = GuildOS.db.lfgPrefs
        local was = prefs.autoInvite
        prefs.autoInvite = V.auto
        local ok, said = pcall(G._GuildLine, G, g)
        prefs.autoInvite = was
        return ok and said or ""
    end
    function prev.Paint(_, w)
        prev:SetSize(math.max(1, w), SP.FIELD)
        prev.label:ClearAllPoints()
        prev.line:ClearAllPoints()
        if V.chat and V.act then
            prev.label:Show()
            prev.label:SetPoint("LEFT", prev, "LEFT", 10, 0)
            local lw = math.ceil(prev.label:GetStringWidth() or 50) + 8
            prev.line:SetPoint("LEFT", prev, "LEFT", 10 + lw, 0)
            local k = ink(prev, C.ok)
            prev.line:SetTextColor(k.r, k.g, k.b)
            prev.line:SetText(previewLine())
            oneLine(prev.line, w - 20 - lw)
        else
            prev.label:Hide()
            prev.line:SetPoint("LEFT", prev, "LEFT", 10, 0)
            local k = ink(prev, C.textSoft)
            prev.line:SetTextColor(k.r, k.g, k.b)
            prev.line:SetText(L["Only guildmates with Guild OS will see it (in this list and as a tile)."])
            oneLine(prev.line, w - 20)
        end
        return SP.FIELD
    end
    formG.preview = prev
    formG:Add(prev, { shown = onStep(2), gap = 8, place = function(_, w) return prev.Paint(nil, w) end })
    noteG:HookScript("OnTextChanged", function()
        if V.form == "group" and V.step == 2 then prev.Paint(nil, prev:GetWidth()) end
    end)

    -- Why the module refused the group (no open spot, not the leader), until something changes.
    local hintG = formG:Note("", { ink = UI:Ink("paper", C.danger), shown = function() return V.step == 2 and V.hint ~= "" end })

    chatG.checkbox.onChanged = function(_, checked)
        V.chat = checked and true or false
        paint()
    end
    autoG.checkbox.onChanged = function(_, checked)
        V.auto = checked and true or false
        paint()
    end
    formG.action:SetScript("OnClick", function()
        if V.step ~= 2 or not V.act then return end
        -- The two boxes are remembered choices (as the board's): saved when the group goes up.
        B:SetPref("postToGuild", V.chat)
        B:SetPref("autoInvite", V.auto)
        local ok, why = G:Create(V.act, V.need, noteG:GetText(), V.ttl, V.chat, V.start, V.quest)
        if not ok then
            V.hint = why or ""
            paint()
            return
        end
        closeForm()
    end)

    ------------------------------------------------------------------
    -- I am looking (the right column)
    ------------------------------------------------------------------
    local formS = formCard(L["I am looking"])
    formS.isSeekForm = true
    local function toggleAct(id)
        local qid = questOf(id)
        if qid then
            -- A quest of my log (#450): picked or taken back, never more than the listing carries.
            local out, had = {}, false
            for _, q in ipairs(V.quests) do
                if q.id == qid then had = true else out[#out + 1] = q end
            end
            local q = Q and Q:Get(qid)
            if not had and q and #out < Q.PICK_MAX then out[#out + 1] = { id = q.id, t = q.title } end
            V.quests = out
            paint()
            return
        end
        local out = {}
        for _, x in ipairs(V.acts) do if x ~= id then out[#out + 1] = x end end
        if #out == #V.acts then out[#out + 1] = id end
        V.acts = B:_SanitizeActs(out)
        paint()
    end
    formS.cats = addCategoryRow(formS)
    formS.grid = addGrid(formS, function(id)
        local qid = questOf(id)
        if not qid then return has(V.acts, id) end
        for _, q in ipairs(V.quests) do if q.id == qid then return true end end
        return false
    end, toggleAct)

    local sep = CreateFrame("Frame", nil, formS)
    sep:SetSize(1, 1)
    local sepLine = UI:CreateSeparator(sep)
    sepLine:SetPoint("TOPLEFT", 0, 0)
    sepLine:SetPoint("TOPRIGHT", 0, 0)
    formS:Add(sep, { place = function(_, w)
        sep:SetSize(math.max(1, w), 1)
        return 1
    end })

    local rolesBox = CreateFrame("Frame", nil, formS)
    rolesBox:SetSize(1, 1)
    rolesBox.head = UI:CreateHeaderText(rolesBox, L["MY ROLES (NONE IS ANY)"])
    rolesBox.head:SetJustifyH("LEFT")
    rolesBox.toggles = {}
    for _, letter in ipairs(LETTERS) do
        local t = createRoleToggle(rolesBox, letter)
        t:SetScript("OnClick", function()
            local out = ""
            for _, k in ipairs(LETTERS) do
                local on = V.roles:find(k, 1, true) ~= nil
                if k == letter then on = not on end
                if on then out = out .. k end
            end
            V.roles = out
            paint()
        end)
        rolesBox.toggles[#rolesBox.toggles + 1] = t
    end
    function rolesBox.Place(_, w)
        rolesBox.head:ClearAllPoints()
        rolesBox.head:SetPoint("TOPLEFT", rolesBox, "TOPLEFT", 0, 0)
        for _, t in ipairs(rolesBox.toggles) do t:SetOn(V.roles:find(t.letter, 1, true) ~= nil) end
        local y = flowAt(rolesBox, rolesBox.toggles, HEAD_H, w)
        rolesBox:SetSize(math.max(1, w), y)
        return y
    end
    local ttlBox = CreateFrame("Frame", nil, formS)
    ttlBox:SetSize(1, 1)
    ttlBox.ttls = pillGroup(ttlBox, L["LISTED FOR"], B.DURATIONS, function(s) return B:DurationName(s) end,
        function(s) V.ttl = s end, function(s) return V.ttl == s end)
    function ttlBox.Place(_, w)
        local y = ttlBox.ttls.Lay(nil, 0, w)
        ttlBox:SetSize(math.max(1, w), y)
        return y
    end
    formS:Pair(rolesBox, ttlBox)

    local noteS = noteInput(formS)
    formS:Field(L["Note"], noteS)
    local chatS = smallCheck(formS, L["Also post in guild chat"])
    formS:Add(chatS, { place = function(_, w) return chatS:Place(w) end })
    chatS.checkbox.onChanged = function(_, checked) V.chat = checked and true or false end
    -- The opt-in (#450), off by default: the ids of the group quests in my log go out with my listing.
    local shareS = smallCheck(formS, L["Share the group quests in my log with the guild LFG"])
    formS:Add(shareS, { place = function(_, w) return shareS:Place(w) end })
    shareS.checkbox.onChanged = function(_, checked) V.share = checked and true or false end
    formS.share = shareS
    formS.action:SetScript("OnClick", function()
        B:SetPref("roles", V.roles)
        B:SetPref("postToGuild", V.chat)
        B:SetPref("shareQuests", V.share)
        B:SetAvailable(nil, noteS:GetText(), V.ttl, V.chat, V.roles, V.acts, V.quests)
        closeForm()
    end)

    ------------------------------------------------------------------
    -- Opening and closing a form. Escape closes it (and only it): the panel takes the keyboard while a form
    -- is open and lets every other key through; never touched in combat, where a frame may not change that.
    ------------------------------------------------------------------
    local function takeKeys(on)
        if GuildOS.Compat.InCombat() then return end
        if parent.EnableKeyboard then parent:EnableKeyboard(on and true or false) end
        if on and parent.SetPropagateKeyboardInput then parent:SetPropagateKeyboardInput(true) end
    end
    parent:SetScript("OnKeyDown", function(self, key)
        local fight = GuildOS.Compat.InCombat()
        if key == "ESCAPE" and V.form then
            if not fight and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            closeForm()
        elseif not fight and self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- The category a form opens on: the activity's, else the board's filter, else the dungeons.
    local function catOf(act)
        local it = act and Cat.byId[act]
        if it then return it.cat end
        local f = B:Pref("filterCat")
        return (f == "dungeon" or f == "raid" or f == "other") and f or "dungeon"
    end

    closeForm = function(quiet)
        V.form, V.hint = nil, ""
        noteG:ClearFocus()
        noteS:ClearFocus()
        takeKeys(false)
        if not quiet then paint() end
    end

    -- Form a group: on the cards, or, leading one already, on its spots and times to change.
    openGroupForm = function()
        -- Not in combat: a form takes the keyboard and the screen, and nothing waits on it mid-fight.
        if GuildOS:InCombat() then GuildOS:Print(L["Not during combat."]); return end
        local group = G:Mine()
        V.form, V.hint = "group", ""
        V.ttl = B:_ClampTtl(GuildOS.db.lfgPrefs.lastTtl)
        V.chat = B:Pref("postToGuild") and true or false
        V.auto = B:Pref("autoInvite") and true or false
        V.quest = group and group.quest and { id = group.quest.id, t = group.quest.t } or nil
        if group then
            V.act, V.step = group.act, 2
            V.need = G:_SanitizeNeed(group.need)
            -- A group I change keeps the start it has, to the second.
            V.start = G:StartsIn(group) or 0
            noteG:SetText(group.note or "")
        else
            V.act, V.step, V.start = nil, 1, 0
            V.need = { T = 0, H = 0, D = 0 }
            noteG:SetText("")
        end
        V.cat = V.quest and QUEST_CAT or catOf(V.act)
        chatG.checkbox:SetChecked(V.chat)
        autoG.checkbox:SetChecked(V.auto)
        takeKeys(true)
        scroll:SetVerticalScroll(0)
        paint()
    end

    -- I am looking: on what I have listed, or on nothing (anything) with the roles I play.
    openSeekForm = function()
        if GuildOS:InCombat() then GuildOS:Print(L["Not during combat."]); return end
        local listing = B:Mine()
        V.form = "seek"
        V.acts, V.quests = {}, {}
        -- Elite quests that went out for the quests picked (#450) is not a card I picked.
        for _, id in ipairs(listing and listing.acts or {}) do
            if not (listing.questAct and id == B.QUEST_ACT) then V.acts[#V.acts + 1] = id end
        end
        for _, q in ipairs(listing and listing.quests or {}) do V.quests[#V.quests + 1] = { id = q.id, t = q.t } end
        V.share = B:Pref("shareQuests") and true or false
        shareS.checkbox:SetChecked(V.share)
        V.roles = (listing and listing.roles) or B:Pref("roles") or ""
        V.ttl = B:_ClampTtl(GuildOS.db.lfgPrefs.lastTtl)
        V.chat = B:Pref("postToGuild") and true or false
        V.cat = (#V.acts == 0 and #V.quests > 0) and QUEST_CAT or catOf(V.acts[1])
        noteS:SetText(listing and listing.note or "")
        chatS.checkbox:SetChecked(V.chat)
        takeKeys(true)
        scroll:SetVerticalScroll(0)
        paint()
    end

    -- A form's parts that change with what it holds: the step, the action's words, whether it may go.
    local function paintFormChrome()
        if V.form == "group" then
            formG.stepText:SetText(V.step == 1 and L["1 · What is it for?"] or L["2 · Who and when"])
            formG.action:SetShown(V.step == 2)
            formG.action.label:SetText(G:Mine() and L["Update"] or L["Publish group"])
            Forms:FitPill(formG.action)
            if G:OpenSpots(V.need) > 0 then formG.action:Enable() else formG.action:Disable() end
            hintG:SetText(V.hint or "")
        elseif V.form == "seek" then
            local n = #V.acts + #V.quests
            formS.stepText:SetText(n > 0 and string.format(L["%d picked"], n) or L["none picked: anything"])
            formS.action.label:SetText(B:Mine() and L["Update"] or L["Start looking"])
            Forms:FitPill(formS.action)
        end
    end

    -- Whether a player looking would fit a group for `act` with spots `need`: they want it (or anything),
    -- play a role it has a spot for, are of its level where the roster says theirs, and are a guildmate (an
    -- allied listing is read, not invited).
    local function fitsAct(e, act, need, me, levelByKey, qid)
        if not act or not e.key or e.key == me then return false end
        local onQuest = qid ~= nil and Q ~= nil and Q:Lists(e, qid)
        if #(e.acts or {}) > 0 and not has(e.acts, act) and not onQuest then return false end
        if not G:BestRole(need, e.roles or "") then return false end
        local level = levelByKey[e.key]
        return not level or G:FitsLevel(act, level)
    end
    ------------------------------------------------------------------
    -- Painting
    ------------------------------------------------------------------
    -- The chip on the players' list while a group is being formed: "3 would fit Karazhan", where the
    -- card's title leaves room for it.
    local fitChip = UI:CreateBadge(seekersCard, "", C.ok)
    fitChip:Hide()

    paint = function()
        if not parent:IsVisible() then return end
        B:Prune()
        G:Prune()
        P.releaseAll()
        local now = GetServerTime()
        local onlineSet, classByKey = B:_BuildOnlineRoster()
        local me = B:MyKey()
        local myLevel = UnitLevel("player") or 1
        local myRoles = B:Pref("roles") or ""
        local cat, levelOnly = B:Pref("filterCat") or "all", B:Pref("filterLevel") and true or false
        local known = false
        for _, def in ipairs(FILTERS) do known = known or def.key == cat end
        if not known then cat = "all" end
        local levelByKey = rosterLevels()
        V.counts = G:Counts(now, onlineSet)
        local myGroup = G:Mine()
        -- What the players' list measures against: the group being formed, else the one I lead.
        local fitAct = (V.form == "group" and V.step == 2 and V.act) or (V.form == nil and myGroup and myGroup.act) or nil
        -- And its quest (#450): whoever names it is "also on this quest".
        local fitQuest = fitAct and ((V.form == "group" and V.quest) or (V.form == nil and myGroup and myGroup.quest)) or nil
        local fitQid = fitQuest and fitQuest.id or nil

        -- The top card: my roles, my listing's status, the figures, the filters.
        for _, letter in ipairs(LETTERS) do myChips[letter]:SetOn(myRoles:find(letter, 1, true) ~= nil) end

        local groups, forMe, nForMe = {}, {}, 0
        for _, g in ipairs(G:ActiveList(GuildOS.db.lfgGroups, now, onlineSet)) do
            if g.key ~= me and keeps(g.act, cat, levelOnly, myLevel) then
                groups[#groups + 1] = g
                if G:FitsMe(g, myLevel, myRoles) then
                    forMe[g.key] = true
                    nForMe = nForMe + 1
                end
            end
        end
        -- Those for me first (#378), then the newest.
        table.sort(groups, function(a, b)
            if (forMe[a.key] or false) ~= (forMe[b.key] or false) then return forMe[a.key] == true end
            if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
            return a.key < b.key
        end)
        -- Leading a group, who fits it is the module's answer (the same as its card's "Fits your group").
        local matched
        if fitAct and V.form == nil then
            matched = {}
            for _, m in ipairs(G:Matches(now, onlineSet)) do matched[m.key] = true end
        end
        local seekers, fits, nFit, questMarks = {}, {}, 0, {}
        for _, e in ipairs(B:ActiveList(GuildOS.db.lfgBoard, now, onlineSet)) do
            if keepsSeeker(e, cat, levelOnly, myLevel) then
                seekers[#seekers + 1] = e
                local fitting
                if matched then fitting = e.key ~= nil and matched[e.key] == true
                else fitting = fitsAct(e, fitAct, V.need, me, levelByKey, fitQid) end
                if fitting then
                    fits[e] = true
                    nFit = nFit + 1
                end
                -- The green word on the row (#450): on the group's quest, else on a quest of my log.
                if Q and e.key ~= me then
                    if fitQid and Q:Lists(e, fitQid) then questMarks[e] = L["also on this quest"]
                    elseif Q:InMyLog(e) then questMarks[e] = L["you have this quest"] end
                end
            end
        end
        -- Who would fit first, the board's order kept otherwise.
        if nFit > 0 then
            local order = {}
            for i, e in ipairs(seekers) do order[e] = i end
            table.sort(seekers, function(a, b)
                if (fits[a] or false) ~= (fits[b] or false) then return fits[a] == true end
                return order[a] < order[b]
            end)
        end
        kpis[1].value:SetText(tostring(#groups))
        kpis[2].value:SetText(tostring(#seekers))
        kpis[3].value:SetText(tostring(nForMe))
        for _, def in ipairs(filterBtns) do UI:SetSelected(def.button, def.key == cat) end
        UI:SetSelected(levelBtn, levelOnly)

        local topW = UI:LaidWidth(top)
        if not topW or topW < 2 then topW = (UI:LaidWidth(parent) or 0) - M end
        if topW < 2 then topW = 900 end
        top:SetHeight(layoutTop(topW - 2 * SP.PAD))

        -- The scroll: two columns from TWO_COLS (the left one forms a group or lists them, the right one
        -- says I am looking or lists who is), one under the other below.
        local sw = UI:LaidWidth(scroll) or 0
        local W = (sw > 1 and sw or topW + UI.SCROLL_GUTTER - M) - UI.SCROLL_GUTTER
        content:SetWidth(W)
        local availH = scroll:GetHeight() or 0
        local two = W >= SP.TWO_COLS
        local gw = two and math.floor((W - SP.GAP) * 0.55) or W
        local swd = two and (W - SP.GAP - gw) or W
        paintFormChrome()

        -- The left column: the form, or my group (and the others' under it), or the groups.
        local left, right = {}, {}
        local groupForm, seekForm = V.form == "group", V.form == "seek"
        formG:SetShown(groupForm)
        formS:SetShown(seekForm)
        mine.card:SetShown(not groupForm and myGroup ~= nil)
        local showGroups = not groupForm and (myGroup == nil or #groups > 0)
        groupsCard:SetShown(showGroups)
        local leftUsed = 0
        if groupForm then
            left[#left + 1] = { card = formG, h = layoutForm(formG, gw, 0), form = true }
        elseif myGroup then
            local h = paintMine(myGroup, now, onlineSet, classByKey, levelByKey, gw)
            left[#left + 1] = { card = mine.card, h = h }
            leftUsed = h + SP.GAP
        end
        if showGroups then
            titled(groupsCard, L["Groups being formed"], #groups)
            local gy = SP.TOP
            local gInner = gw - 2 * SP.PAD
            if #groups == 0 then
                local room = two and (availH - leftUsed - SP.TOP - SP.PAD) or 0
                gy = emptyState(groupsCard, "+", L["No group is being formed right now. Pick an activity to start one."],
                    L["+ Form a group"], function() openGroupForm() end, gy, gInner, room)
            else
                for i = 1, math.min(#groups, GROUPS_MAX) do
                    gy = groupEntry(groupsCard, groups[i], now, classByKey, gy, gInner, forMe[groups[i].key])
                end
                if #groups > GROUPS_MAX then gy = line(groupsCard, string.format(L["... and %d more."], #groups - GROUPS_MAX), gy, gInner) end
            end
            left[#left + 1] = { card = groupsCard, h = gy + SP.PAD - 10 }
        end

        -- The right column: I am looking, or the players looking.
        seekersCard:SetShown(not seekForm)
        if seekForm then
            right[#right + 1] = { card = formS, h = layoutForm(formS, swd, 0), form = true }
        else
            titled(seekersCard, L["Looking for a group"], #seekers)
            -- The chip after the title, while a group is being formed and there is room for it.
            fitChip:Hide()
            if fitAct and nFit > 0 then
                fitChip:SetText(string.format(L["%d would fit %s"], nFit,
                    fitQuest and G:Title({ quest = fitQuest }) or B:ActivityName(fitAct)), C.ok)
                local titleW = math.ceil(seekersCard.title:GetStringWidth() or 120)
                local x = SP.PAD + titleW + SP.CELL
                if x + fitChip:GetWidth() <= swd - SP.PAD then
                    fitChip:ClearAllPoints()
                    fitChip:SetPoint("TOPLEFT", seekersCard, "TOPLEFT", x, -(SP.PAD + 1))
                    fitChip:Show()
                end
            end
            local sy = SP.TOP
            local sInner = swd - 2 * SP.PAD
            if #seekers == 0 then
                local leftH = 0
                for _, it in ipairs(left) do leftH = leftH + it.h + SP.GAP end
                local room = availH - (two and 0 or leftH) - SP.TOP - SP.PAD
                sy = emptyState(seekersCard, "?", L["Nobody is available right now. Be the first!"], L["I am looking"],
                    function() openSeekForm() end, sy, sInner, room)
            else
                local cols = seekerCols(sInner)
                sy = seekerHeader(seekersCard, sy, sInner, cols)
                for i = 1, math.min(#seekers, SEEKERS_MAX) do
                    sy = seekerRow(seekersCard, seekers[i], now, classByKey, levelByKey, me, sy, sInner, cols, fits[seekers[i]],
                        questMarks[seekers[i]])
                end
                if #seekers > SEEKERS_MAX then sy = line(seekersCard, string.format(L["... and %d more."], #seekers - SEEKERS_MAX), sy, sInner) end
                sy = sy + 6
            end
            right[#right + 1] = { card = seekersCard, h = sy + SP.PAD - 6 }
        end

        -- Stack each column; the last card of a column grows to the height left (a form lays out again,
        -- its grid taking the room).
        local function stack(list, x, y0, w, colH)
            local used = 0
            for i, it in ipairs(list) do used = used + it.h + (i > 1 and SP.GAP or 0) end
            local y = y0
            for i, it in ipairs(list) do
                local h = it.h
                if i == #list and colH and used < colH then h = h + (colH - used) end
                if it.form then h = layoutForm(it.card, w, h) end
                it.card:ClearAllPoints()
                it.card:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
                it.card:SetSize(w, h)
                y = y + h + SP.GAP
            end
            return y - SP.GAP
        end
        local function sum(list)
            local s = 0
            for i, it in ipairs(list) do s = s + it.h + (i > 1 and SP.GAP or 0) end
            return s
        end
        local y
        if two then
            local colH = math.max(sum(left), sum(right), availH)
            stack(left, 0, 0, gw, colH)
            stack(right, gw + SP.GAP, 0, swd, colH)
            y = colH
        else
            -- One under the other: the left column's cards, then the right's, the last one filling the view;
            -- an open form takes the top slot, where it is seen.
            local all = {}
            local first, second = left, right
            if seekForm then first, second = right, left end
            for _, it in ipairs(first) do all[#all + 1] = it end
            for _, it in ipairs(second) do all[#all + 1] = it end
            local yy = 0
            for i, it in ipairs(all) do
                local h = it.h
                if i == #all and not it.form then h = math.max(h, availH - yy) end
                -- A form fills the view it opens in: its grid takes the room.
                if it.form then h = layoutForm(it.card, W, math.max(h, availH - yy)) end
                it.card:ClearAllPoints()
                it.card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yy)
                it.card:SetSize(W, h)
                yy = yy + h + (i < #all and SP.GAP or 0)
            end
            y = yy
        end
        content:SetHeight(math.max(1, y))
    end

    -- Deep links (/gos avail, Call to Arms): a category opens the board on that filter.
    local function selectSub(key)
        for _, def in ipairs(FILTERS) do
            if def.key == key then B:SetPref("filterCat", key) end
        end
        parent.activeSub = "active"
        scroll:SetVerticalScroll(0)
        GuildOS:SafeCall(paint)
    end
    parent.SelectSub = selectSub

    for _, letter in ipairs(LETTERS) do
        myChips[letter]:SetScript("OnClick", function()
            local roles, out = B:Pref("roles") or "", ""
            for _, k in ipairs(LETTERS) do
                local on = roles:find(k, 1, true) ~= nil
                if k == letter then on = not on end
                if on then out = out .. k end
            end
            B:SetPref("roles", out)
            GuildOS:SafeCall(paint)
        end)
    end
    -- I am looking opens its form, or closes it when open; the status beside it changes or stops a listing.
    lookBtn:SetScript("OnClick", function()
        if V.form == "seek" then closeForm() else openSeekForm() end
    end)
    stopBtn:SetScript("OnClick", function()
        if V.form == "seek" then closeForm(true) end
        B:ClearAvailable()
    end)
    extendBtn:SetScript("OnClick", function() B:Extend() end)
    changeBtn:SetScript("OnClick", function() openSeekForm() end)
    formBtn:SetScript("OnClick", function()
        if V.form == "group" and not G:Mine() then closeForm() else openGroupForm() end
    end)

    -- The board's refresh hook: every change the modules make lands here.
    B.uiRefresh = paint

    parent:SetScript("OnShow", function() selectSub("active") end)
    -- A form left open is closed with the tab: coming back shows the lists.
    parent:HookScript("OnHide", function() if V.form then closeForm(true) end end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(paint)
    end)
    UI:MakeResponsive(parent, function() GuildOS:SafeCall(paint) end)
end
