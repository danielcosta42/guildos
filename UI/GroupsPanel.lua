----------------------------------------------------------------------
-- Guild OS - The Groups tab (issue #341)
-- The guild's own group finder. One card on top says what I play, lets me say I am looking (for an
-- activity picked from a list by level and instance, with a note) and form a group; under it the
-- figures (groups forming, players looking, groups for me) and the filters as pills. Then, when I lead
-- a group, its card with its queue and the players who fit it, and the two lists: the groups being
-- formed, a card each, and the players looking, a row each. Modules/Groups.lua and
-- Modules/LFGBoard.lua answer; this draws and calls their methods.
--
-- The spacing standard (#449, specs/salao/fase3.md, "Espaçamento"): cards 16 in and 14 apart, sections
-- 18 apart with their title 8 over the content, fields 26 high, rows 28 (32 with an avatar), body text
-- 13, meta 11, titles 15, figures 22. Two columns from 900px; the lists grow to the height left.
--
-- Everything is repainted from pools: a repaint that created its rows would leak them, because the
-- client never frees a frame.
----------------------------------------------------------------------
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
local CHIP = 26                      -- a role toggle in the composer
local TAB_MIN_W, TAB_PAD, TAB_H = 70, 20, 28
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

-- A role's square (the composer's): a shared button with the role's icon, or its letter where the
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
-- The activity picker (#449): one list, by level and by instance
----------------------------------------------------------------------
-- The options of an activity dropdown: "Anything" (when `any`), then what my level runs, then every
-- section of the catalogue under its title; a title is a row that cannot be picked. Each activity
-- says its level range and, where there are any, how many groups and players it has.
local function activityOptions(any, myLevel, counts)
    local B, Cat = GuildOS.LFGBoard, GuildOS.GroupActivities
    local out = {}
    if any then out[#out + 1] = { value = "", text = L["Anything"] } end
    local function opt(it)
        local parts = { B:ActivityName(it.id) }
        local range = rangeOf(it)
        if range ~= "" then parts[#parts + 1] = range end
        local c = counts and counts[it.id]
        if c and c.groups > 0 then parts[#parts + 1] = string.format(L["%d forming"], c.groups) end
        if c and c.seekers > 0 then parts[#parts + 1] = string.format(L["%d looking"], c.seekers) end
        out[#out + 1] = { value = it.id, text = table.concat(parts, DOT) }
    end
    local function header(title)
        out[#out + 1] = { value = "\1" .. title, text = title, disabled = true, color = C.label }
    end
    local mine, seen = {}, {}
    for _, s in ipairs(Cat:Sections("dungeon")) do
        for _, it in ipairs(s.items) do
            if it.min and it.max and myLevel >= it.min and myLevel <= it.max and not seen[it.id] then
                seen[it.id] = true
                mine[#mine + 1] = it
            end
        end
    end
    if #mine > 0 then
        header(L["For your level"])
        for _, it in ipairs(mine) do opt(it) end
    end
    for _, cat in ipairs(Cat.CATS) do
        for _, s in ipairs(Cat:Sections(cat)) do
            header(s.title)
            for _, it in ipairs(s.items) do opt(it) end
        end
    end
    return out
end

----------------------------------------------------------------------
-- The composer: one popup, two modes (I am looking; I am forming a group)
----------------------------------------------------------------------
local composer

local function defaultNeed(act)
    local need = { T = 1, H = 1, D = 3 }
    local mine = GuildOS.LFGBoard:Pref("roles") or ""
    if #mine == 1 and need[mine] > 0 then need[mine] = need[mine] - 1 end
    local room = GuildOS.Groups:SizeOf(act) - 1
    return GuildOS.Groups:_SanitizeNeed(need, room)
end

local function buildComposer()
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    local W = 400
    local f = CreateFrame("Frame", "GuildOSGroupComposer", UIParent, "BackdropTemplate")
    f:SetSize(W, 520)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    f:Hide()

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    local PAD, y = SP.PAD, -SP.PAD
    local IW = W - 2 * PAD
    -- A form label (#371, #449): body text in the soft ink, 4 over its field.
    local function label(str)
        local fs = UI:CreateText(f, str, SP.BODY, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        fs:SetPoint("TOPLEFT", PAD, y)
        y = y - 16 - SP.LABEL_GAP
        return fs
    end

    -- Mode
    local tabs = {}
    local function modeTab(mode, str, x)
        local t = UI:CreateTab(f, str, TAB_MIN_W, true)
        t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
        t:SetPoint("TOPLEFT", x, y)
        t:SetScript("OnClick", function() f:SetMode(mode) end)
        tabs[mode] = t
        return t
    end
    local seekTab = modeTab("seek", L["I am looking"], PAD)
    modeTab("group", L["Form a group"], PAD + seekTab:GetWidth() + 6)
    y = y - TAB_H - SP.SECTION

    -- Activity: the picker, and under it (looking) the activities I listed
    label(L["Activity"])
    local pick = UI:CreateDropdown(f, IW, SP.FIELD)
    pick:SetPoint("TOPLEFT", PAD, y)
    pick:SetPlaceholder(L["Pick what the group is for."])
    pick.isActivityPicker = true
    y = y - SP.FIELD - 6
    local actText = UI:CreateText(f, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    actText:SetPoint("TOPLEFT", PAD, y)
    actText:SetWidth(IW - 120)
    actText:SetJustifyH("LEFT")
    actText:SetWordWrap(true)
    actText:SetHeight(28)
    actText:SetJustifyV("TOP")
    local onlyBtn = UI:CreateButton(f, L["Only this one"], 110, SP.HIT)
    onlyBtn:SetPoint("TOPRIGHT", -PAD, y + 2)
    y = y - 28 - SP.FIELD_GAP

    -- Roles (looking) or open spots (group): the same line, one of the two shown
    local rolesLabel = label("")
    local chips, steppers = {}, {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(f, letter)
        chip:SetPoint("TOPLEFT", PAD + (i - 1) * (CHIP + 6), y)
        chip:SetScript("OnClick", function(self) self:SetOn(not self.on) end)
        chips[letter] = chip

        local st = CreateFrame("Frame", nil, f)
        st:SetSize(112, CHIP)
        st:SetPoint("TOPLEFT", PAD + (i - 1) * 122, y)
        local mark = createRoleMark(st, letter)
        mark:SetPoint("LEFT")
        local minus = UI:CreateButton(st, "-", SP.HIT, CHIP)
        minus:SetPoint("LEFT", mark, "RIGHT", 4, 0)
        local value = UI:CreateText(st, "0", SP.BODY)
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(24)
        value:SetJustifyH("CENTER")
        local plus = UI:CreateButton(st, "+", SP.HIT, CHIP)
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        st.value = value
        minus:SetScript("OnClick", function() f:Step(letter, -1) end)
        plus:SetScript("OnClick", function() f:Step(letter, 1) end)
        steppers[letter] = st
    end
    y = y - CHIP - SP.FIELD_GAP

    -- Note
    label(L["Note"])
    local note = UI:CreateInput(f, IW, SP.FIELD, { max = 60 })   -- the shared field (#371)
    note:SetPoint("TOPLEFT", PAD, y)
    note:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    y = y - SP.FIELD - SP.FIELD_GAP

    -- Duration
    label(L["LISTED FOR"])
    local durations = {}
    local x = PAD
    for _, seconds in ipairs(B.DURATIONS) do
        local b = UI:CreateButton(f, B:DurationName(seconds), 56, SP.HIT)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() f:SetDuration(seconds) end)
        durations[seconds] = b
        x = x + b:GetWidth() + 6
    end
    y = y - SP.HIT - SP.FIELD_GAP

    -- When a group starts (#378): now, or a little later, so guildmates can plan around it.
    local startLabel = label(L["STARTS"])
    local starts = {}
    x = PAD
    for _, seconds in ipairs(G.STARTS) do
        local b = UI:CreateButton(f, seconds == 0 and L["Now"] or B:DurationName(seconds), 56, SP.HIT)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            f.start = seconds
            f.Repaint()
        end)
        starts[seconds] = b
        x = x + b:GetWidth() + 6
    end
    y = y - SP.HIT - SP.FIELD_GAP

    local chat = UI:CreateCheckbox(f, L["Also post in guild chat"], 18)
    chat:SetPoint("TOPLEFT", PAD - 2, y)
    chat.checkbox.onChanged = function(_, checked) B:SetPref("postToGuild", checked and true or false) end
    y = y - SP.HIT - 4

    -- A group's own (#378): whoever asks, with the addon or by whispering "inv", is invited at once.
    local auto = UI:CreateCheckbox(f, L["Invite whoever asks"], 18)
    auto:SetPoint("TOPLEFT", PAD - 2, y)
    auto.checkbox.onChanged = function(_, checked) B:SetPref("autoInvite", checked and true or false) end
    y = y - SP.HIT - 4

    local hint = UI:CreateText(f, "", SP.META, C.danger.r, C.danger.g, C.danger.b)
    hint:SetPoint("TOPLEFT", PAD, y)
    hint:SetWidth(IW)
    hint:SetJustifyH("LEFT")
    f:SetHeight(-y + 16 + SP.FIELD + PAD + 8)

    local publish = UI:SetButtonVariant(UI:CreateButton(f, L["Publish"], 120, SP.FIELD), "primary")
    publish:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local down = UI:SetButtonVariant(UI:CreateButton(f, L["Take down"], 110, SP.FIELD), "danger")
    down:SetPoint("BOTTOMLEFT", PAD, PAD)

    local function paint()
        local seek = f.mode == "seek"
        for mode, t in pairs(tabs) do t:SetActive(mode == f.mode) end
        rolesLabel:SetText(seek and L["MY ROLES (NONE IS ANY)"] or L["OPEN SPOTS"])
        pick:SetOptions(activityOptions(false, UnitLevel("player") or 1))
        local names = {}
        if seek then
            for _, id in ipairs(f.acts) do names[#names + 1] = B:ActivityName(id) end
            actText:SetText(#names > 0 and table.concat(names, ", ") or L["Anything"])
            pick:SetValue(f.picked)
        else
            actText:SetText(f.act and B:ActivityName(f.act) or L["Pick what the group is for."])
            pick:SetValue(f.act)
        end
        onlyBtn:SetShown(seek and #f.acts > 1 and f.picked ~= nil)
        auto:SetShown(not seek)
        startLabel:SetShown(not seek)
        for seconds, b in pairs(starts) do
            b:SetShown(not seek)
            UI:SetSelected(b, seconds == f.start)
        end
        for _, letter in ipairs(LETTERS) do
            chips[letter]:SetShown(seek)
            steppers[letter]:SetShown(not seek)
            steppers[letter].value:SetText(tostring(f.need[letter] or 0))
        end
        for seconds, b in pairs(durations) do UI:SetSelected(b, seconds == f.ttl) end
        local listed = (seek and B:Mine() ~= nil) or (not seek and G:Mine() ~= nil)
        publish.label:SetText(listed and L["Update"] or L["Publish"])
        down:SetShown(listed)
        if seek or f.act then publish:Enable() else publish:Disable() end
    end

    function f:SetMode(mode)
        self.mode = mode
        B:SetPref("lastMode", mode)
        hint:SetText("")
        paint()
    end
    function f:SetDuration(seconds)
        self.ttl = seconds
        paint()
    end
    -- One spot more or less, never past the room a group of this size has besides its leader.
    function f:Step(letter, by)
        local want = {}
        for _, k in ipairs(LETTERS) do want[k] = self.need[k] or 0 end
        want[letter] = math.max(0, want[letter] + by)
        if G:OpenSpots(want) > G:SizeOf(self.act) - 1 then return end
        self.need = want
        paint()
    end
    -- An activity picked: looking, it joins the ones I listed (as a tile's click did); forming, it is
    -- what the group is for, with the spots such a group has.
    function f:Pick(act)
        if not act or act == "" or act:byte(1) == 1 then return end
        self.picked = act
        local have = false
        for _, id in ipairs(self.acts) do have = have or id == act end
        if not have then self.acts[#self.acts + 1] = act end
        self.acts = B:_SanitizeActs(self.acts)
        if self.act ~= act then
            self.act = act
            local group = G:Mine()
            self.need = (group and group.act == act) and G:_SanitizeNeed(group.need) or defaultNeed(act)
        end
        paint()
    end
    pick.onSelect = function(_, act) f:Pick(act) end

    onlyBtn:SetScript("OnClick", function()
        f.acts = { f.picked }
        paint()
    end)
    down:SetScript("OnClick", function()
        if f.mode == "seek" then B:ClearAvailable() else G:Disband() end
        f:Hide()
    end)
    publish:SetScript("OnClick", function()
        local toGuild = B:Pref("postToGuild") and true or false
        if f.mode == "seek" then
            local roles = ""
            for _, letter in ipairs(LETTERS) do
                if chips[letter].on then roles = roles .. letter end
            end
            B:SetPref("roles", roles)
            B:SetAvailable(nil, note:GetText(), f.ttl, toGuild, roles, f.acts)
        else
            local ok, why = G:Create(f.act, f.need, note:GetText(), f.ttl, toGuild, f.start)
            if not ok then
                hint:SetText(why or "")
                return
            end
        end
        f:Hide()
    end)

    -- Open on `act` (one picked), or on what I already have listed. `mode` nil is the one used last,
    -- unless I am leading a group, which is then what there is to change.
    function f:Open(act, mode)
        local mine, group = B:Mine(), G:Mine()
        mode = mode or (group and "group") or (mine and "seek") or B:Pref("lastMode") or "seek"
        self.picked = act
        self.acts = {}
        for _, id in ipairs(mine and mine.acts or {}) do self.acts[#self.acts + 1] = id end
        if act then
            local have = false
            for _, id in ipairs(self.acts) do have = have or id == act end
            if not have then self.acts[#self.acts + 1] = act end
            self.acts = B:_SanitizeActs(self.acts)
        end
        self.act = act or (group and group.act) or nil
        self.need = (group and (not act or act == group.act)) and G:_SanitizeNeed(group.need) or defaultNeed(self.act)
        self.ttl = B:_ClampTtl(GuildOS.db.lfgPrefs.lastTtl)
        -- A group I change keeps the start it has, to the second; a new one starts now.
        self.start = (group and (not act or act == group.act) and G:StartsIn(group)) or 0
        local roles = (mine and mine.roles) or B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do chips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        local current = (mode == "group" and group) or (mode == "seek" and mine) or nil
        note:SetText(current and current.note or "")
        chat.checkbox:SetChecked(B:Pref("postToGuild") and true or false)
        auto.checkbox:SetChecked(B:Pref("autoInvite") and true or false)
        hint:SetText("")
        self.mode = mode
        paint()
        self:Show()
        self:Raise()
    end

    f.Repaint = paint
    return f
end

local function openComposer(act, mode)
    composer = composer or buildComposer()
    composer:Open(act, mode)
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
        local body = string.format("%s: %s", n.name, B:ActivityName(n.act)) .. DOT ..
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

-- An activity's icon: its LFG art cut square where the client has it, a glyph with its initial
-- otherwise (WoW: Forever's new dungeons have no art).
local function activityIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.art:SetAllPoints()
    f.glyph = UI:CreateGlyph(f, size)
    f.glyph:SetPoint("CENTER")
    function f:SetActivity(act)
        local it = GuildOS.GroupActivities.byId[act]
        if it and hasArt(it) then
            self.art:SetTexture(it.art)
            self.art:SetTexCoord(ART_TC[1], ART_TC[2], ART_TC[3], ART_TC[4])
            self.art:Show()
            self.glyph:Hide()
        else
            self.art:Hide()
            self.glyph:Show()
            local name = GuildOS.LFGBoard:ActivityName(act)
            self.glyph:Set(UI.Initial and UI.Initial(name) or name:sub(1, 1), (it and it.cat == "raid") and C.count or C.paperSoft)
        end
    end
    return f
end

function GuildOS:CreateGroupsPanel(parent)
    local B, G, Cat = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.GroupActivities
    parent.activeSub = "active"
    local P = newPools()
    local V = { pick = "", dirty = false }   -- the card's own state: the activity picked, an edit not sent
    local paint   -- forward: the handlers below repaint

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

    local lookBtn = UI:SetButtonVariant(UI:CreateButton(top, L["I am looking"], 110, SP.FIELD), "chip")
    lookBtn.isLookToggle = true
    local actDD = UI:CreateDropdown(top, 240, SP.FIELD)
    actDD.isActivityPicker = true
    local noteBox = UI:CreateInput(top, 200, SP.FIELD, { max = 60, placeholder = L["Note"] })
    noteBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    local updateBtn = UI:CreateButton(top, L["Update"], 80, SP.FIELD)
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
        local y = SP.TOP
        -- Row 1: I play, the three roles; Form a group on the right.
        playLabel:ClearAllPoints()
        playLabel:SetPoint("TOPLEFT", SP.PAD, -(y + 5))
        local x = SP.PAD + math.ceil(playLabel:GetStringWidth() or 40) + SP.CELL
        for _, letter in ipairs(LETTERS) do
            local t = myChips[letter]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", x, -y)
            x = x + t:GetWidth() + 6
        end
        fit(formBtn, G:Mine() and L["My group"] or L["+ Form a group"], 120)
        formBtn:ClearAllPoints()
        formBtn:SetPoint("TOPRIGHT", -SP.PAD, -y)
        y = y + SP.FIELD + SP.FIELD_GAP

        -- Row 2: I am looking, the activity, the note (and Update); my listing's time and its actions.
        local mine = B:Mine()
        UI:SetSelected(lookBtn, mine ~= nil)
        lookBtn:ClearAllPoints()
        lookBtn:SetPoint("TOPLEFT", SP.PAD, -y)
        x = SP.PAD + lookBtn:GetWidth() + SP.CELL
        local ddW = math.max(170, math.min(260, math.floor(IW * 0.3)))
        actDD:SetWidth(ddW)
        actDD:ClearAllPoints()
        actDD:SetPoint("TOPLEFT", x, -y)
        x = x + ddW + SP.CELL
        local right = {}
        if mine then
            lookMeta:SetText(string.format(L["%dm left"], B:_Remaining(mine, GetServerTime())))
            right = { stopBtn, changeBtn, extendBtn }
        end
        lookMeta:SetShown(mine ~= nil)
        stopBtn:SetShown(mine ~= nil)
        changeBtn:SetShown(mine ~= nil)
        extendBtn:SetShown(mine ~= nil)
        local rightW = 0
        for _, b in ipairs(right) do rightW = rightW + b:GetWidth() + 6 end
        if mine then rightW = rightW + math.ceil(lookMeta:GetStringWidth() or 40) + 6 end
        local showUpdate = mine ~= nil and V.dirty
        updateBtn:SetShown(showUpdate)
        local updW = showUpdate and (updateBtn:GetWidth() + SP.CELL) or 0
        local edge = SP.PAD + IW
        local noteW = edge - x - updW - (rightW > 0 and (rightW + SP.CELL) or 0)
        local wrap = rightW > 0 and noteW < 140
        if wrap then noteW = edge - x - updW end
        noteW = math.max(100, math.min(320, noteW))
        noteBox:SetWidth(noteW)
        noteBox:ClearAllPoints()
        noteBox:SetPoint("TOPLEFT", x, -y)
        updateBtn:ClearAllPoints()
        updateBtn:SetPoint("TOPLEFT", x + noteW + SP.CELL, -y)
        local ry = wrap and (y + SP.FIELD + 8) or y
        if mine then
            local taken = rightAlign(top, right, -(ry + 1), SP.PAD)
            lookMeta:ClearAllPoints()
            lookMeta:SetPoint("TOPRIGHT", top, "TOPRIGHT", -(SP.PAD + taken + 6), -(ry + 6))
        end
        y = ry + SP.FIELD + SP.SECTION

        -- Row 3, under a hairline: the figures, then the filters (on a line of their own when narrow).
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
        e.icon:SetActivity(g.act)

        -- Line 1: the activity, "for you" on a group of my level with a spot in a role I play (#378),
        -- and how long ago it was listed.
        e.title:ClearAllPoints()
        e.title:SetPoint("TOPLEFT", X, -12)
        e.title:SetText(B:ActivityName(g.act))
        e.ago:ClearAllPoints()
        e.ago:SetPoint("TOPRIGHT", -12, -14)
        e.ago:SetText(GuildOS:TimeAgo(g.ts))
        local agoW = math.ceil(e.ago:GetStringWidth() or 40)
        local badgeW = forMe and 80 or 0
        oneLine(e.title, math.min(math.ceil(e.title:GetStringWidth() or 100) + 4, inner - X - agoW - badgeW - 12))
        if forMe then
            e.badge:SetText(L["for you"], C.ok)
            e.badge:ClearAllPoints()
            e.badge:SetPoint("LEFT", e.title, "RIGHT", 8, 0)
            e.badge:Show()
        else
            e.badge:Hide()
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
        local range = rangeOf(it)
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

    local function seekerRow(card, e, now, classByKey, levelByKey, mine, y, w, cols)
        local row = P.acquire("seeker" .. card.pk, function()
            local f = CreateFrame("Frame", nil, card)
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
        f.edit:SetScript("OnClick", function() openComposer(nil, "group") end)
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
        f.title:SetText(string.format(L["Your group: %s"], B:ActivityName(g.act)))
        f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local y = SP.TOP
        f.icon:ClearAllPoints()
        f.icon:SetPoint("TOPLEFT", SP.PAD, -y)
        f.icon:SetActivity(g.act)
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

    local function lookingFromCard()
        local acts = (V.pick ~= nil and V.pick ~= "") and { V.pick } or {}
        V.dirty = false
        B:SetAvailable(nil, noteBox:GetText(), GuildOS.db.lfgPrefs.lastTtl, B:Pref("postToGuild") and true or false,
            B:Pref("roles") or "", acts)
    end
    local function openForm()
        if G:Mine() then openComposer(nil, "group") return end
        openComposer((V.pick ~= nil and V.pick ~= "") and V.pick or nil, "group")
    end

    ------------------------------------------------------------------
    -- Painting
    ------------------------------------------------------------------
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

        -- The top card: my roles, my listing as the card shows it, the figures, the filters.
        for _, letter in ipairs(LETTERS) do myChips[letter]:SetOn(myRoles:find(letter, 1, true) ~= nil) end
        local myEntry = B:Mine()
        if not V.dirty then
            V.pick = myEntry and (myEntry.acts or {})[1] or V.pick or ""
            if myEntry then noteBox:SetText(myEntry.note or "") end
        end
        actDD:SetOptions(activityOptions(true, myLevel, G:Counts(now, onlineSet)))
        actDD:SetValue(V.pick or "")

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
        local seekers = {}
        for _, e in ipairs(B:ActiveList(GuildOS.db.lfgBoard, now, onlineSet)) do
            if keepsSeeker(e, cat, levelOnly, myLevel) then seekers[#seekers + 1] = e end
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

        -- The scroll: my group, then the two lists, side by side from TWO_COLS.
        local sw = UI:LaidWidth(scroll) or 0
        local W = (sw > 1 and sw or topW + UI.SCROLL_GUTTER - M) - UI.SCROLL_GUTTER
        content:SetWidth(W)
        local availH = scroll:GetHeight() or 0
        local y = 0
        local myGroup = G:Mine()
        mine.card:SetShown(myGroup ~= nil)
        if myGroup then
            mine.card:ClearAllPoints()
            mine.card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            y = y + paintMine(myGroup, now, onlineSet, classByKey, levelByKey, W) + SP.GAP
        end

        local two = W >= SP.TWO_COLS
        local gw = two and math.floor((W - SP.GAP) * 0.55) or W
        local swd = two and (W - SP.GAP - gw) or W

        -- Groups being formed
        titled(groupsCard, L["Groups being formed"], #groups)
        local gy = SP.TOP
        local gInner = gw - 2 * SP.PAD
        if #groups == 0 then
            local room = two and (availH - y - SP.TOP - SP.PAD) or 0
            gy = emptyState(groupsCard, "+", L["No group is being formed right now. Pick an activity to start one."],
                G:Mine() and L["My group"] or L["+ Form a group"], openForm, gy, gInner, room)
        else
            for i = 1, math.min(#groups, GROUPS_MAX) do
                gy = groupEntry(groupsCard, groups[i], now, classByKey, gy, gInner, forMe[groups[i].key])
            end
            if #groups > GROUPS_MAX then gy = line(groupsCard, string.format(L["... and %d more."], #groups - GROUPS_MAX), gy, gInner) end
        end
        local gh = gy + SP.PAD - 10

        -- Looking for a group
        titled(seekersCard, L["Looking for a group"], #seekers)
        local sy = SP.TOP
        local sInner = swd - 2 * SP.PAD
        if #seekers == 0 then
            local room = availH - (two and y or (y + gh + SP.GAP)) - SP.TOP - SP.PAD
            sy = emptyState(seekersCard, "?", L["Nobody is available right now. Be the first!"], L["I am looking"], function()
                if not B:Mine() then lookingFromCard() end
            end, sy, sInner, room)
        else
            local cols = seekerCols(sInner)
            sy = seekerHeader(seekersCard, sy, sInner, cols)
            for i = 1, math.min(#seekers, SEEKERS_MAX) do
                sy = seekerRow(seekersCard, seekers[i], now, classByKey, levelByKey, me, sy, sInner, cols)
            end
            if #seekers > SEEKERS_MAX then sy = line(seekersCard, string.format(L["... and %d more."], #seekers - SEEKERS_MAX), sy, sInner) end
            sy = sy + 6
        end
        local sh = sy + SP.PAD - 6

        groupsCard:ClearAllPoints()
        seekersCard:ClearAllPoints()
        if two then
            -- Side by side, as tall as each other and as the room left (the lists grow to fill it).
            local h = math.max(gh, sh, availH - y)
            groupsCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            groupsCard:SetSize(gw, h)
            seekersCard:SetPoint("TOPLEFT", content, "TOPLEFT", gw + SP.GAP, -y)
            seekersCard:SetSize(swd, h)
            y = y + h
        else
            groupsCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            groupsCard:SetSize(W, gh)
            y = y + gh + SP.GAP
            seekersCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local h = math.max(sh, availH - y)
            seekersCard:SetSize(W, h)
            y = y + h
        end
        content:SetHeight(math.max(1, y))

        if composer and composer:IsShown() then composer.Repaint() end
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
    actDD.onSelect = function(_, act)
        if type(act) == "string" and act:byte(1) == 1 then return end
        V.pick = act or ""
        V.dirty = B:Mine() ~= nil
        GuildOS:SafeCall(paint)
    end
    noteBox:HookScript("OnTextChanged", function(_, user)
        if user and B:Mine() and not V.dirty then
            V.dirty = true
            GuildOS:SafeCall(paint)
        end
    end)
    lookBtn:SetScript("OnClick", function()
        if B:Mine() then B:ClearAvailable() else lookingFromCard() end
    end)
    updateBtn:SetScript("OnClick", lookingFromCard)
    stopBtn:SetScript("OnClick", function()
        V.dirty = false
        B:ClearAvailable()
    end)
    extendBtn:SetScript("OnClick", function() B:Extend() end)
    changeBtn:SetScript("OnClick", function() openComposer(nil, "seek") end)
    formBtn:SetScript("OnClick", openForm)

    -- The board's refresh hook: every change the modules make lands here.
    B.uiRefresh = paint

    parent:SetScript("OnShow", function() selectSub("active") end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(paint)
    end)
    UI:MakeResponsive(parent, function() GuildOS:SafeCall(paint) end)
end
