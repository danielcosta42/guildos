----------------------------------------------------------------------
-- Guild OS - The Groups tab (issue #341)
-- The guild's own group finder: what is being formed and who is looking (Active), and the game's
-- activities as tiles (Dungeons, Raids, Quests and more), each with how many groups and players it
-- has. Modules/Groups.lua and Modules/LFGBoard.lua answer; this draws and calls their methods.
--
-- Activity cards (#373): the roles are the game's own icons, a group being formed is a card with its
-- activity's art and one seat per place it has or offers, a player looking is a row with class, level
-- and roles, and Dungeons opens on the tiles of my level. Nothing here is new data: every figure is
-- one the modules already keep.
--
-- One scroll area, repainted from pools: a repaint that created its rows would leak them, because
-- the client never frees a frame.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local TAB_H, TAB_MIN_W, TAB_PAD = 28, 70, 20   -- as the Guild hub's sub-tabs
local TILE_MIN_W, TILE_H, GAP = 150, 60, UI.GAP
local ROW_H, HEAD_H = 24, 26
local HEAD_ABOVE = 20           -- room over a later section title for its rule (UI:CreateSectionTitle)
local CHIP = 22
local ART_ALPHA = 0.55          -- the game's art under a tile's text
local OFF_LEVEL_ALPHA = 0.5     -- a tile outside my level
local LEVEL_SLACK = 5           -- levels past an activity's range it still reads as mine
local REPAINT_EVERY = 30        -- seconds: the time left on a listing
local NAME_W, ROLES_W, TIME_W = 130, 96, 44

-- A forming group's card (#373). Its rows sit at fixed heights so the cards of one row line up
-- whatever each says: the art band, who leads, the seats, the note, the actions.
-- Never narrower than its widest action row: Whisper and three Join buttons at 60px, 4px apart, 8px in
-- from each side (264 + 16). Three a row on the default window, two or one on a narrower one.
local GROUP_MIN_W = 280
local BAND_H = 48
local SLOT, SLOT_GAP = 16, 3
local ROW_LEAD = BAND_H + 8
local ROW_SEATS = ROW_LEAD + 18
local ROW_NOTE = ROW_SEATS + SLOT + 6
local ROW_STATUS = ROW_NOTE + 18   -- what the buttons below do ("ask for a spot as"), on a line of its own
local ROW_ACT = ROW_STATUS + 16
local GROUP_H = ROW_ACT + 20 + 8
-- My group as the leader's panel, and the summary over Active (#378), in one table: the tab's builder
-- is one function, and Lua 5.1 lets a function reach at most 60 of the file's locals.
local K = {}
K.SEATS = BAND_H + 10
K.FILL = K.SEATS + SLOT + 10
K.META = K.FILL + 14
K.ACT = K.META + 22
K.H = K.ACT + 22 + 10
K.TIME_BAR_H = 2           -- the time a listing has left, under a card's band
K.SUMMARY_H, K.FILTER_H = 46, 22
K.FILTERS = {
    { key = "all",     label = L["All"] },
    { key = "dungeon", label = L["Dungeons"] },
    { key = "raid",    label = L["Raids"] },
    { key = "other",   label = L["Quests and more"] },
}
-- A player looking (#373): class icon, name, level, roles, what they want.
local ICON, CLASS_W, LEVEL_W = 16, 20, 44
local ROLE_ICONS_W = 3 * (ICON + 2) + 6
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"   -- as the Roster's
-- A scroll child past ~15000px stops drawing: a guild of hundreds all looking must not get there.
local GROUPS_MAX, SEEKERS_MAX = 50, 200   -- one column, both full: under 14,000px with the status row
local DOT = "  \194\183  "

local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }
local SUBS = {
    { key = "active",  label = L["Active now"] },
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

local function coloured(name, classFile)
    if not classFile then return name end
    return "|cff" .. GuildOS:GetClassColorHex(classFile) .. name .. "|r"
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

-- A role's square: a shared button with the role's icon, or its letter where the client has no icon
-- (#373). A chosen role takes the shared selection mark (UI:SetSelected), not a border tinted in the
-- role's colour (#371); an icon not chosen is greyed, as the game's own role picker greys it.
local function createRoleChip(parent, letter)
    local chip = UI:CreateButton(parent, letter, CHIP, CHIP)
    chip.letter = letter
    chip.baseLabelColor = { C.label.r, C.label.g, C.label.b }
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(CHIP - 6, CHIP - 6)
    chip.icon:SetPoint("CENTER")
    if setRoleIcon(chip.icon, letter) then chip.label:SetText("") end
    function chip:SetOn(on)
        self.on = on and true or false
        UI:SetSelected(self, self.on)
        self.icon:SetDesaturated(not self.on)
    end
    chip:SetOn(false)
    -- Hooked, not set: the button's own hover and press states live on OnEnter and OnLeave.
    local B = GuildOS.LFGBoard
    chip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(B:RoleName(ROLE_OF[letter]), C.text.r, C.text.g, C.text.b)
        GameTooltip:Show()
    end)
    chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return chip
end

-- A role's square that only names the role (a stepper's), never chosen: its icon in full colour, or
-- its letter in the role's colour.
local function createRoleMark(parent, letter)
    local mark = createRoleChip(parent, letter)
    local ink = roleColor(letter)
    mark.baseLabelColor = { ink.r, ink.g, ink.b }
    UI:_ButtonState(mark, "rest")
    mark.icon:SetDesaturated(false)
    mark:EnableMouse(false)
    return mark
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
    local f = CreateFrame("Frame", "GuildOSGroupComposer", UIParent, "BackdropTemplate")
    f:SetSize(380, 448)
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
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local PAD, y = 16, -14
    -- A form label (#371): body text in `text`, not a column header.
    local function label(text)
        local fs = UI:CreateText(f, text, 11)
        fs:SetPoint("TOPLEFT", PAD, y)
        y = y - 16
        return fs
    end

    -- Mode
    local tabs = {}
    local function modeTab(mode, text, x)
        local t = UI:CreateTab(f, text, TAB_MIN_W, true)
        t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
        t:SetPoint("TOPLEFT", x, y)
        t:SetScript("OnClick", function() f:SetMode(mode) end)
        tabs[mode] = t
        return t
    end
    local seekTab = modeTab("seek", L["I am looking"], PAD)
    modeTab("group", L["Form a group"], PAD + seekTab:GetWidth() + 4)
    y = y - TAB_H - 10

    -- Activity
    label(L["ACTIVITY"])
    local actText = UI:CreateText(f, "", 12)
    actText:SetPoint("TOPLEFT", PAD, y)
    actText:SetWidth(f:GetWidth() - PAD * 2)
    actText:SetJustifyH("LEFT")
    actText:SetWordWrap(true)
    actText:SetHeight(28)
    actText:SetJustifyV("TOP")
    local onlyBtn = UI:CreateButton(f, L["Only this one"], 110, 18)
    onlyBtn:SetPoint("TOPRIGHT", -PAD, y + 20)
    y = y - 34

    -- Roles (looking) or open spots (group): the same line, one of the two shown
    local rolesLabel = label("")
    local chips, steppers = {}, {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(f, letter)
        chip:SetPoint("TOPLEFT", PAD + (i - 1) * (CHIP + 4), y)
        chip:SetScript("OnClick", function(self)
            self:SetOn(not self.on)
        end)
        chips[letter] = chip

        local st = CreateFrame("Frame", nil, f)
        st:SetSize(104, CHIP)
        st:SetPoint("TOPLEFT", PAD + (i - 1) * 112, y)
        local mark = createRoleMark(st, letter)
        mark:SetPoint("LEFT")
        local minus = UI:CreateButton(st, "-", 20, CHIP)
        minus:SetPoint("LEFT", mark, "RIGHT", 4, 0)
        local value = UI:CreateText(st, "0", 12)
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(24)
        value:SetJustifyH("CENTER")
        local plus = UI:CreateButton(st, "+", 20, CHIP)
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        st.value = value
        minus:SetScript("OnClick", function() f:Step(letter, -1) end)
        plus:SetScript("OnClick", function() f:Step(letter, 1) end)
        steppers[letter] = st
    end
    y = y - CHIP - 12

    -- Note
    label(L["NOTE"])
    local note = UI:CreateInput(f, f:GetWidth() - PAD * 2, 22, { max = 60 })   -- the shared field (#371)
    note:SetPoint("TOPLEFT", PAD, y)
    note:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    y = y - 22 - 12

    -- Duration
    label(L["LISTED FOR"])
    local durations = {}
    local x = PAD
    for _, seconds in ipairs(B.DURATIONS) do
        local b = UI:CreateButton(f, B:DurationName(seconds), 52, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() f:SetDuration(seconds) end)
        durations[seconds] = b
        x = x + b:GetWidth() + 4
    end
    y = y - 22 - 12

    -- When a group starts (#378): now, or a little later, so guildmates can plan around it.
    local startLabel = label(L["STARTS"])
    local starts = {}
    x = PAD
    for _, seconds in ipairs(G.STARTS) do
        local b = UI:CreateButton(f, seconds == 0 and L["Now"] or B:DurationName(seconds), 52, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            f.start = seconds
            f.Repaint()
        end)
        starts[seconds] = b
        x = x + b:GetWidth() + 4
    end
    y = y - 22 - 12

    local chat = UI:CreateCheckbox(f, L["Also post in guild chat"], 18)
    chat:SetPoint("TOPLEFT", PAD - 2, y)
    chat.checkbox.onChanged = function(_, checked) B:SetPref("postToGuild", checked and true or false) end
    y = y - 26

    -- A group's own (#378): whoever asks, with the addon or by whispering "inv", is invited at once.
    local auto = UI:CreateCheckbox(f, L["Invite whoever asks"], 18)
    auto:SetPoint("TOPLEFT", PAD - 2, y)
    auto.checkbox.onChanged = function(_, checked) B:SetPref("autoInvite", checked and true or false) end
    y = y - 26

    local hint = UI:CreateText(f, "", 11, C.danger.r, C.danger.g, C.danger.b)
    hint:SetPoint("TOPLEFT", PAD, y)
    hint:SetWidth(f:GetWidth() - PAD * 2)
    hint:SetJustifyH("LEFT")

    local publish = UI:SetButtonVariant(UI:CreateButton(f, L["Publish"], 110, 26), "primary")
    publish:SetPoint("BOTTOMRIGHT", -PAD, 14)
    local down = UI:SetButtonVariant(UI:CreateButton(f, L["Take down"], 100, 26), "danger")
    down:SetPoint("BOTTOMLEFT", PAD, 14)

    local function paint()
        local seek = f.mode == "seek"
        for mode, t in pairs(tabs) do t:SetActive(mode == f.mode) end
        rolesLabel:SetText(seek and L["MY ROLES (NONE IS ANY)"] or L["OPEN SPOTS"])
        local names = {}
        if seek then
            for _, id in ipairs(f.acts) do names[#names + 1] = B:ActivityName(id) end
            actText:SetText(#names > 0 and table.concat(names, ", ") or L["Anything"])
        else
            actText:SetText(f.act and B:ActivityName(f.act) or L["Pick what the group is for."])
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

    -- Open on `act` (a tile), or on what I already have listed. `mode` nil is the one used last,
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
-- The notice (#378): a small card at the top of the screen that goes away by itself. Two kinds,
-- which Modules/Groups.lua decides: a guildmate formed a group I fit ("group"), or somebody asks for
-- a spot in mine and I do not invite whoever asks ("request"). One at a time: the newer replaces it.
----------------------------------------------------------------------
local TOAST_W, TOAST_H = 300, 66
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
    t.title = UI:CreateTitle(t, "", 12)
    t.title:SetPoint("TOPLEFT", 10, -8)
    t.title:SetWidth(TOAST_W - 40)
    t.title:SetJustifyH("LEFT")
    t.title:SetWordWrap(false)
    t.body = UI:CreateText(t, "", 11)
    t.body:SetPoint("TOPLEFT", 10, -26)
    t.body:SetWidth(TOAST_W - 20)
    t.body:SetJustifyH("LEFT")
    t.body:SetWordWrap(false)
    local close = UI:CreateCloseButton(t)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() t:Hide() end)
    t.primary = UI:SetButtonVariant(UI:CreateButton(t, "", 110, 20), "primary")
    t.primary:SetPoint("BOTTOMRIGHT", -8, 8)
    t.secondary = UI:CreateButton(t, "", 90, 20)
    t.secondary:SetPoint("RIGHT", t.primary, "LEFT", -6, 0)
    -- The card itself opens the tab, where the rest is.
    t:SetScript("OnClick", function(self)
        self:Hide()
        GuildOS.LFGBoard:Show()
    end)
    t:Hide()
    return t
end

local function fitButton(b, text)
    b.label:SetText(text)
    b:SetWidth(math.max(70, math.ceil(b.label:GetStringWidth()) + 20))
end

-- n = { kind, key, name, act?, need?, note?, role? }, from Modules/Groups.lua.
local function groupsToastNow(n)
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    toast = toast or buildToast()
    local key = n.key
    if n.kind == "group" then
        local role = G:BestRole(n.need, B:Pref("roles") or "")
        toast.title:SetText(L["Groups being formed"])
        local body = string.format("%s: %s", n.name, B:ActivityName(n.act)) .. DOT ..
            string.format(L["open: %s"], G:NeedText(n.need))
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
function GuildOS:CreateGroupsPanel(parent)
    local B, G, Cat = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.GroupActivities
    parent.activeSub = "active"
    -- With the game's icons a player's roles take three squares; spelled out they need the room.
    local rolesW = roleArtKind() and ROLE_ICONS_W or ROLES_W

    -- Sub-tabs. Anchored on the left only: UI:FlowBar reads GetWidth to wrap (as the Guild hub).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    local subTabs, subList = {}, {}

    -- Actions: what I play, listing myself, forming a group. Flush with the bar's left edge, UI.GAP
    -- under it, and ending UI.GAP short of its right edge, as every screen's content does (#371).
    local actions = CreateFrame("Frame", nil, parent)
    actions:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
    actions:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -UI.GAP, -UI.GAP)
    actions:SetHeight(26)

    local rolesLabel = UI:CreateText(actions, L["I PLAY"], 11)   -- a form label (#371)
    rolesLabel:SetPoint("LEFT", 0, 0)
    local myChips = {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(actions, letter)
        if i == 1 then
            chip:SetPoint("LEFT", rolesLabel, "RIGHT", 8, 0)
        else
            chip:SetPoint("LEFT", myChips[LETTERS[i - 1]], "RIGHT", 4, 0)
        end
        myChips[letter] = chip
    end

    local groupBtn = UI:SetButtonVariant(UI:CreateButton(actions, L["+ Form a group"], 130, 26), "primary")
    groupBtn:SetPoint("RIGHT", 0, 0)
    local seekBtn = UI:CreateButton(actions, L["I am looking..."], 120, 26)
    seekBtn:SetPoint("RIGHT", groupBtn, "LEFT", -6, 0)

    -- The scroll child stops UI.SCROLL_GUTTER short of the frame (BindScrollChildWidth), so the frame
    -- reaches that far past the actions' right edge: the content then ends where the actions do, and
    -- nothing on its right (the scope button) runs under the bar (#371).
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSGroupsScroll")
    scroll:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -UI.GAP)
    scroll:SetPoint("BOTTOMRIGHT", -(10 + UI.GAP - UI.SCROLL_GUTTER), 8)
    UI:BindScrollChildWidth(scroll, content)

    ------------------------------------------------------------------
    -- Pools
    ------------------------------------------------------------------
    local pools = {}
    local function acquire(kind, make)
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
    local function releaseAll()
        for _, pool in pairs(pools) do
            for _, item in ipairs(pool.items) do item:Hide() end
            pool.used = 0
        end
    end

    local y, width = 0, 400
    local paint   -- forward: the handlers below repaint

    -- A section title (#371): the shared one, held by a strip across the content so its rule reaches
    -- the right edge and goes with it when the pool hides it. The view's first title has no rule.
    -- Returns the strip, for what sits on the title's line (the scope button).
    local function head(text, extra)
        local strip = acquire("head", function()
            local s = CreateFrame("Frame", nil, content)
            s:SetHeight(18)
            s.title = UI:CreateSectionTitle(s, "", false)
            s.title:SetPoint("TOPLEFT", 0, 0)
            return s
        end)
        local first = y == 0
        if not first then y = y + HEAD_ABOVE end
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", 0, -y)
        strip:SetPoint("TOPRIGHT", 0, -y)
        strip.title.rule:SetShown(not first)
        strip.title:SetText(extra and (text .. "  |cff" .. string.format("%02x%02x%02x", C.label.r * 255, C.label.g * 255,
            C.label.b * 255) .. extra .. "|r") or text)
        y = y + HEAD_H
        return strip
    end

    -- What a view says when it has nothing to list: secondary text, not a heading (#371).
    local function line(text)
        local fs = acquire("line", function()
            local t = UI:CreateText(content, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            t:SetJustifyH("LEFT")
            return t
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetWidth(math.max(10, width))
        fs:SetText(text)
        y = y + math.max(16, fs:GetStringHeight() or 16) + 6
    end

    local function smallButton(parentFrame, variant)
        local b = UI:CreateButton(parentFrame, "", 60, 20)
        if variant then UI:SetButtonVariant(b, variant) end
        return b
    end

    -- A button as wide as its label, never under the 60px of the others.
    local function fit(b, text)
        b.label:SetText(text)
        b:SetWidth(math.max(60, math.ceil(b.label:GetStringWidth() or 0) + 18))
        return b
    end

    -- Lay buttons out from a frame's right edge inwards; returns the width they took. `inset`: 6 inside
    -- a card's border, none on a bare row, which ends flush with the content's right edge (#371).
    local function rightAlign(frame, buttons, top, inset)
        local x = -(inset or 6)
        for _, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, top)
            x = x - b:GetWidth() - 4
        end
        return -x
    end

    local function panelFrame()
        local f = CreateFrame("Frame", nil, content, "BackdropTemplate")
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
        f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        return f
    end

    ------------------------------------------------------------------
    -- Active: my group and its queue, the groups being formed, who is looking
    ------------------------------------------------------------------
    local function requestRow(r, classByKey)
        local row = acquire("request", function()
            local f = CreateFrame("Frame", nil, content)
            f.name = UI:CreateText(f, "", 11)
            f.name:SetPoint("LEFT", 0, 0)
            f.state = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.decline = smallButton(f)
            f.decline.label:SetText(L["Decline"])
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ROW_H)
        local ink = roleColor(r.role)
        row.name:SetText(coloured(r.name, classByKey[r.key]) .. "  " ..
            GuildOS:ColorText(B:RoleName(ROLE_OF[r.role]), ink.r, ink.g, ink.b))
        local taken = rightAlign(row, { row.decline, row.invite }, -2, 0)
        row.state:ClearAllPoints()
        row.state:SetPoint("RIGHT", row, "RIGHT", -(taken + 6), 0)
        row.state:SetText(r.state == "invited" and L["invited"] or "")
        oneLine(row.name, width - taken - 70)
        local key = r.key
        row.invite:SetScript("OnClick", function() G:Invite(key) end)
        row.decline:SetScript("OnClick", function() G:Decline(key) end)
        y = y + ROW_H
    end

    -- The activity's art as a band across a card's top, cut as the tiles cut it, over `well` where the
    -- client has no art for it; with the time the listing has left as a hairline under it (#378).
    local function addBand(f)
        f.band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.band:SetTexture(WHITE)
        f.band:SetVertexColor(C.well.r, C.well.g, C.well.b, 1)
        f.band:SetPoint("TOPLEFT", 1, -1)
        f.band:SetPoint("TOPRIGHT", -1, -1)
        f.band:SetHeight(BAND_H)
        f.art = f:CreateTexture(nil, "ARTWORK")
        f.art:SetAllPoints(f.band)
        f.art:SetTexCoord(0, 1, 0.08, 0.72)
        f.art:SetAlpha(ART_ALPHA)
        f.bandRule = UI:CreateSeparator(f)
        f.bandRule:SetPoint("TOPLEFT", f.band, "BOTTOMLEFT", 0, 0)
        f.bandRule:SetPoint("TOPRIGHT", f.band, "BOTTOMRIGHT", 0, 0)
        f.timeBar = f:CreateTexture(nil, "OVERLAY")
        f.timeBar:SetTexture(WHITE)
        f.timeBar:SetPoint("TOPLEFT", f.band, "BOTTOMLEFT", 0, 0)
        f.timeBar:SetHeight(K.TIME_BAR_H)
        f.title = UI:CreateText(f, "", 13)
        f.title:SetPoint("BOTTOMLEFT", f.band, "BOTTOMLEFT", 8, 6)
        f.range = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        f.range:SetPoint("TOPRIGHT", f.band, "TOPRIGHT", -6, -5)
        f.badge = UI:CreateBadge(f, "", C.ok)
        f.badge:SetPoint("TOPLEFT", f.band, "TOPLEFT", 6, -5)
        f.badge:Hide()
    end

    -- Paint a band: the art, the title, the range, an optional badge, and the time left as a share of
    -- the listing's whole duration (`label` ink, `warn` in its last ten minutes).
    local function paintBand(card, g, now, w, title, badgeText, badgeColor)
        local it = Cat.byId[g.act]
        if it and hasArt(it) then
            card.art:SetTexture(it.art)
            card.art:Show()
        else
            card.art:Hide()
        end
        card.title:SetText(title)
        oneLine(card.title, w - 16)
        card.range:SetText(rangeOf(it))
        if badgeText then
            card.badge:SetText(badgeText, badgeColor)
            card.badge:Show()
        else
            card.badge:Hide()
        end
        local total = math.max(1, g.ttl or 1)
        local left = math.max(0, (g.ts or now) + total - now)
        card.timeBar:SetWidth(math.max(1, (w - 2) * math.min(1, left / total)))
        local ink = left <= 600 and C.warn or C.label
        card.timeBar:SetVertexColor(ink.r, ink.g, ink.b, 0.9)
    end

    -- What a card says about time: how full, when it starts (if later), how long it stays up.
    local function whenText(g, now)
        local parts = { string.format("%d/%d", g.n or 1, g.max or 5) }
        local startIn = G:StartsIn(g, now)
        if startIn then parts[#parts + 1] = string.format(L["starts in %dm"], math.ceil(startIn / 60)) end
        parts[#parts + 1] = string.format(L["%dm"], B:_Remaining(g, now))
        return table.concat(parts, DOT)
    end

    -- One seat of a card, made the first time a card needs that many and kept with the card.
    local function slotOf(card, i)
        local s = card.slots[i]
        if not s then
            s = CreateFrame("Frame", nil, card, "BackdropTemplate")
            s:SetSize(SLOT, SLOT)
            s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(s) })
            s.icon = s:CreateTexture(nil, "ARTWORK")
            s.icon:SetPoint("TOPLEFT", 1, -1)
            s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            s.mark = UI:CreateText(s, "", 9)
            s.mark:SetPoint("CENTER", 0, 0)
            card.slots[i] = s
        end
        s:Show()
        return s
    end

    -- A seat somebody has (`letter` nil) is a solid block: the listing counts its members, never their
    -- roles, so it names none. An open one is an empty seat with the role it is for.
    local function paintSlot(s, letter)
        s.role, s.filled = letter, letter == nil
        if letter then
            s:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
            s:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            local drawn = setRoleIcon(s.icon, letter)
            local ink = roleColor(letter)
            s.mark:SetTextColor(ink.r, ink.g, ink.b)
            s.mark:SetText(drawn and "" or letter)
        else
            s:SetBackdropColor(C.label.r, C.label.g, C.label.b, 1)
            s:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, 1)
            s.icon:Hide()
            s.mark:SetText("")
        end
    end

    -- The seats: one a member, then one an open spot, by role, from `top`. `share` of the card at most,
    -- so what is missing stays legible beside them; a raid's surplus reads as "+N", open spots kept
    -- first. Returns the open roles and the x where the seats end.
    local function paintSeats(card, g, w, top, share)
        local open = {}
        for _, letter in ipairs(LETTERS) do
            for _ = 1, (g.need[letter] or 0) do open[#open + 1] = letter end
        end
        local members = g.n or 1
        local cap = math.max(1, math.floor((w - 20) * share / (SLOT + SLOT_GAP)))
        local showOpen = math.min(#open, cap)
        local showFilled = math.min(members, cap - showOpen)
        local hidden = (members - showFilled) + (#open - showOpen)
        local n = 0
        local function seat(letter)
            n = n + 1
            local s = slotOf(card, n)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", 10 + (n - 1) * (SLOT + SLOT_GAP), -top)
            paintSlot(s, letter)
        end
        for _ = 1, showFilled do seat(nil) end
        for i = 1, showOpen do seat(open[i]) end
        for i = n + 1, #card.slots do card.slots[i]:Hide() end
        local after = 10 + n * (SLOT + SLOT_GAP) + 4
        card.more:ClearAllPoints()
        card.more:SetPoint("LEFT", card, "TOPLEFT", after, -(top + SLOT / 2))
        card.more:SetText(hidden > 0 and ("+" .. hidden) or "")
        if hidden > 0 then after = after + math.ceil(card.more:GetStringWidth() or 0) + 6 end
        return open, after
    end

    -- My group, as the leader sees it (#378): the band with when it starts, the seats, a bar of how
    -- full it is, and everything a leader does from here: change it, give it 30 minutes more, say it
    -- in guild chat now, run a ready check, take it down.
    local function leaderPanel(g, now)
        local card = acquire("mine", function()
            local f = panelFrame()
            addBand(f)
            f.slots = {}
            f.more = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.missing = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.fill = UI:CreateProgressBar(f, 100, 8)
            f.fill:SetPoint("TOPLEFT", 10, -K.FILL)
            f.fillText = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.fillText:SetPoint("LEFT", f.fill, "RIGHT", 8, 0)
            f.meta = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.meta:SetPoint("TOPLEFT", 10, -K.META)
            f.down = fit(smallButton(f, "danger"), L["Take down"])
            f.down:SetScript("OnClick", function() G:Disband() end)
            f.edit = fit(smallButton(f), L["Change"])
            f.edit:SetScript("OnClick", function() openComposer(nil, "group") end)
            f.extend = fit(smallButton(f), L["+30 min"])
            f.extend:SetScript("OnClick", function() G:Extend() end)
            f.post = smallButton(f)
            f.post:SetScript("OnClick", function()
                G:PostNow()
                paint()
            end)
            f.ready = fit(smallButton(f), L["Ready check"])
            f.ready:SetScript("OnClick", function() G:ReadyCheck() end)
            return f
        end)
        -- Hung by both top corners (#371). My own group is told apart by the brighter `lineHi` border:
        -- gold is only for what is selected or focused.
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card:SetPoint("TOPRIGHT", 0, -y)
        card:SetHeight(K.H)
        card:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local startIn = G:StartsIn(g, now)
        paintBand(card, g, now, width, string.format(L["Your group: %s"], B:ActivityName(g.act)),
            startIn and string.format(L["starts in %dm"], math.ceil(startIn / 60)) or nil, C.info)

        local open, after = paintSeats(card, g, width, K.SEATS, 0.6)
        card.missing:ClearAllPoints()
        card.missing:SetPoint("LEFT", card, "TOPLEFT", after, -(K.SEATS + SLOT / 2))
        card.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        oneLine(card.missing, width - after - 10)

        local max = g.max or 5
        card.fill:SetWidth(math.max(60, math.floor(width * 0.4)))
        card.fill:SetProgress((g.n or 1) / max)
        card.fillText:SetText(string.format("%d/%d", g.n or 1, max))

        local parts = { string.format(L["%dm"], B:_Remaining(g, now)) }
        if (g.note or "") ~= "" then parts[#parts + 1] = g.note end
        card.meta:SetText(table.concat(parts, DOT))
        oneLine(card.meta, width - 20)

        local wait = B:GuildLineWait(now)
        fit(card.post, wait > 0 and (L["Post in chat"] .. " (" .. string.format(L["in %dm"], math.ceil(wait / 60)) .. ")")
            or L["Post in chat"])
        if wait > 0 then card.post:Disable() else card.post:Enable() end
        local buttons = { card.down, card.edit, card.extend, card.post }
        if G:CanReadyCheck() then
            card.ready:Show()
            buttons[#buttons + 1] = card.ready
        else
            card.ready:Hide()
        end
        rightAlign(card, buttons, -K.ACT, 8)
        y = y + K.H + GAP
    end

    local function groupCard(g, now, classByKey, x, w, forMe)
        local card = acquire("group", function()
            local f = panelFrame()
            addBand(f)
            f.lead = UI:CreateText(f, "", 11)
            f.lead:SetPoint("TOPLEFT", 10, -ROW_LEAD)
            f.when = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.when:SetPoint("TOPRIGHT", -8, -(ROW_LEAD + 1))
            f.slots = {}
            f.more = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.missing = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.note = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.note:SetPoint("TOPLEFT", 10, -ROW_NOTE)
            f.status = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.whisper = smallButton(f)
            f.whisper.label:SetText(L["Whisper"])
            f.cancel = smallButton(f)
            f.cancel.label:SetText(L["Take it back"])
            f.join = {}
            for _, letter in ipairs(LETTERS) do
                local b = smallButton(f)
                b.label:SetText(B:RoleName(ROLE_OF[letter]))
                local ink = roleColor(letter)
                b.baseLabelColor = { ink.r, ink.g, ink.b }
                UI:_ButtonState(b, "rest")
                f.join[letter] = b
            end
            return f
        end)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", x, -y)
        card:SetSize(w, GROUP_H)

        -- The band: art, name and level range, as the activity's tile shows them, and "for you" on a
        -- group of my level with a spot in a role I play (#378).
        paintBand(card, g, now, w, B:ActivityName(g.act), forMe and L["for you"] or nil, C.ok)

        -- Who leads, in their class colour; how full and for how long.
        local key, name = g.key, g.name
        card.when:SetText(whenText(g, now))
        card.lead:SetText(string.format(L["led by %s"], coloured(name, classByKey[key])))
        oneLine(card.lead, w - 20 - math.ceil(card.when:GetStringWidth() or 0) - 8)

        local open, after = paintSeats(card, g, w, ROW_SEATS, 0.5)
        card.missing:ClearAllPoints()
        card.missing:SetPoint("LEFT", card, "TOPLEFT", after, -(ROW_SEATS + SLOT / 2))
        card.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        oneLine(card.missing, w - after - 8)

        card.note:SetText(g.note or "")
        oneLine(card.note, w - 20)

        -- The actions, as before #373: ask for a spot in a role it has open, or take the ask back.
        local asked = G:Asked(key)
        local buttons = { card.whisper }
        card.whisper:SetScript("OnClick", function() whisper(name) end)
        card.cancel:Hide()
        card.status:SetText("")
        for _, letter in ipairs(LETTERS) do card.join[letter]:Hide() end
        if asked and asked.state == "pending" then
            card.cancel:Show()
            card.cancel:SetScript("OnClick", function() G:CancelRequest(key) end)
            buttons[#buttons + 1] = card.cancel
            card.status:SetText(string.format(L["asked as %s"], B:RoleName(ROLE_OF[asked.role])))
        elseif asked then
            card.status:SetText(L["no spot for you"])
        else
            for i = #LETTERS, 1, -1 do
                local letter = LETTERS[i]
                if (g.need[letter] or 0) > 0 then
                    local b = card.join[letter]
                    b:Show()
                    b:SetScript("OnClick", function() G:RequestSpot(key, letter) end)
                    buttons[#buttons + 1] = b
                end
            end
            card.status:SetText(L["ask for a spot as"])
        end
        rightAlign(card, buttons, -ROW_ACT, 8)
        -- Over the buttons, the card's width to itself: beside three Join buttons it had 20px and was
        -- hidden, on the composer's most common group (#373).
        card.status:ClearAllPoints()
        card.status:SetPoint("TOPLEFT", 10, -ROW_STATUS)
        oneLine(card.status, w - 20)
        card.status:Show()
    end

    -- The cards wrap, two or three a row, each as wide as the row allows.
    local function groupGrid(groups, now, classByKey, forMe)
        local cols = math.max(1, math.min(3, math.floor((width + GAP) / (GROUP_MIN_W + GAP))))
        local w = math.floor((width - GAP * (cols - 1)) / cols)
        local shown = math.min(#groups, GROUPS_MAX)
        for i = 1, shown do
            local col = (i - 1) % cols
            if col == 0 and i > 1 then y = y + GROUP_H + GAP end
            groupCard(groups[i], now, classByKey, col * (w + GAP), w, forMe[groups[i].key])
        end
        if shown > 0 then y = y + GROUP_H + GAP end
        if #groups > shown then line(string.format(L["... and %d more."], #groups - shown)) end
    end

    -- The levels of the guildmates online, keyed as the board keys them (LFGBoard:_BuildOnlineRoster):
    -- the roster already has them, so a row can say a player's level without asking anybody.
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

    local function seekerRow(e, now, classByKey, levelByKey, mine)
        local row = acquire("seeker", function()
            local f = CreateFrame("Frame", nil, content)
            f.class = f:CreateTexture(nil, "ARTWORK")
            f.class:SetSize(ICON, ICON)
            f.class:SetPoint("LEFT", 0, 0)
            f.nameBtn = CreateFrame("Button", nil, f)
            f.nameBtn:SetPoint("LEFT", CLASS_W, 0)
            f.nameBtn:SetSize(NAME_W, ROW_H - 4)
            f.name = UI:CreateText(f.nameBtn, "", 11)
            f.name:SetPoint("LEFT")
            oneLine(f.name, NAME_W - 6)
            f.level = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.level:SetPoint("LEFT", CLASS_W + NAME_W, 0)
            oneLine(f.level, LEVEL_W - 4)
            local x = CLASS_W + NAME_W + LEVEL_W
            f.roleIcons = {}
            for i = 1, #LETTERS do
                local t = f:CreateTexture(nil, "ARTWORK")
                t:SetSize(ICON, ICON)
                t:SetPoint("LEFT", x + (i - 1) * (ICON + 2), 0)
                t:Hide()
                f.roleIcons[i] = t
            end
            f.roles = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.roles:SetPoint("LEFT", x, 0)
            oneLine(f.roles, rolesW - 6)
            f.what = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
            f.what:SetPoint("LEFT", x + rolesW, 0)
            f.time = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.you = UI:CreateText(f, L["(you)"], 10, C.label.r, C.label.g, C.label.b)
            f.extend = fit(smallButton(f), L["+30 min"])
            f.extend:SetScript("OnClick", function() B:Extend() end)
            f.rule = UI:CreateSeparator(f)
            f.rule:SetPoint("BOTTOMLEFT", 0, 0)
            f.rule:SetPoint("BOTTOMRIGHT", 0, 0)
            f.rule:SetAlpha(0.4)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ROW_H)
        local isMe = e.key ~= nil and e.key == mine
        local name = e.name
        -- An allied listing carries no key, so no class or level: those stay blank, never guessed.
        local classFile = e.key and classByKey[e.key]
        local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            row.class:SetTexture(CLASS_ICONS)
            row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            row.class:Show()
        else
            row.class:Hide()
        end
        row.name:SetText(coloured(name, classFile))
        local level = e.key and levelByKey[e.key]
        row.level:SetText(level and (L["Lv "] .. level) or "")
        -- The roles as the game's icons; spelled out where the client has none, and "Any" for none.
        local roles, shown = e.roles or "", 0
        if roleArtKind() then
            for _, letter in ipairs(LETTERS) do
                if roles:find(letter, 1, true) then
                    shown = shown + 1
                    setRoleIcon(row.roleIcons[shown], letter)
                end
            end
        end
        for i = shown + 1, #LETTERS do row.roleIcons[i]:Hide() end
        row.roles:SetText(shown > 0 and "" or roleNames(roles))
        -- An allied listing is read, not acted on (as the board before #341).
        local allied = e.key == nil
        row.nameBtn:EnableMouse(not isMe and not allied)
        row.nameBtn:SetScript("OnClick", function() whisper(name) end)
        row.invite:SetShown(not isMe and not allied)
        row.you:SetShown(isMe)
        row.extend:SetShown(isMe)
        local taken = 0
        if not isMe and not allied then
            taken = rightAlign(row, { row.invite }, -2, 0)
            row.invite:SetScript("OnClick", function() GuildOS.Compat.InviteUnit(name) end)
        elseif isMe then
            -- My own row gives it 30 minutes more, beside the mark that says it is mine (#378).
            taken = rightAlign(row, { row.extend }, -2, 0)
            row.you:ClearAllPoints()
            row.you:SetPoint("RIGHT", row, "RIGHT", -(taken + 2), 0)
            taken = taken + math.ceil(row.you:GetStringWidth() or 30) + 6
        end
        row.time:ClearAllPoints()
        row.time:SetPoint("RIGHT", row, "RIGHT", -(taken + 6), 0)
        row.time:SetText(string.format(L["%dm"], B:_Remaining(e, now)))
        local what = e.guild and e.note or B:Describe(e)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, width - CLASS_W - NAME_W - LEVEL_W - rolesW - taken - TIME_W - 10)
        y = y + ROW_H
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

    -- Over Active (#378): how many groups, how many looking, how many for me, and the filters. On a
    -- narrow window the filters take a line of their own under the figures.
    local function summary(nGroups, nSeekers, nForMe)
        local strip = acquire("summary", function()
            local f = CreateFrame("Frame", nil, content)
            f.chips = {
                UI:CreateMetricChip(f, "0", L["groups forming"]),
                UI:CreateMetricChip(f, "0", L["looking"]),
                UI:CreateMetricChip(f, "0", L["for you"]),
            }
            for i, chip in ipairs(f.chips) do chip:SetPoint("TOPLEFT", (i - 1) * 110, 0) end
            f.filters = {}
            for _, def in ipairs(K.FILTERS) do
                local b = fit(smallButton(f), def.label)
                local key = def.key
                b:SetScript("OnClick", function()
                    B:SetPref("filterCat", key)
                    paint()
                end)
                f.filters[#f.filters + 1] = { key = key, button = b }
            end
            f.level = fit(smallButton(f), L["My level only"])
            f.level:SetScript("OnClick", function()
                B:SetPref("filterLevel", not B:Pref("filterLevel"))
                paint()
            end)
            return f
        end)
        strip.chips[1]:SetValue(tostring(nGroups))
        strip.chips[2]:SetValue(tostring(nSeekers))
        strip.chips[3]:SetValue(tostring(nForMe))
        local cat = B:Pref("filterCat") or "all"
        local row = { strip.level }
        for i = #strip.filters, 1, -1 do row[#row + 1] = strip.filters[i].button end
        local need = 0
        for _, b in ipairs(row) do need = need + b:GetWidth() + 4 end
        local wide = width - 3 * 110 >= need
        local top = wide and 0 or -K.SUMMARY_H
        local x = 0
        for _, b in ipairs(row) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", strip, "TOPRIGHT", x, top)
            x = x - b:GetWidth() - 4
        end
        for _, def in ipairs(strip.filters) do UI:SetSelected(def.button, def.key == cat) end
        UI:SetSelected(strip.level, B:Pref("filterLevel") and true or false)
        local h = wide and K.SUMMARY_H or (K.SUMMARY_H + K.FILTER_H + 4)
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", 0, -y)
        strip:SetPoint("TOPRIGHT", 0, -y)
        strip:SetHeight(h)
        y = y + h + GAP
    end

    -- A player looking who fits my group (#378): who, their level, the role they would take, what they
    -- wrote, and one click to invite them in that role.
    local function matchRow(m, classByKey, levelByKey)
        local row = acquire("match", function()
            local f = CreateFrame("Frame", nil, content)
            f.name = UI:CreateText(f, "", 11)
            f.name:SetPoint("LEFT", 0, 0)
            f.what = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
            f.invite = smallButton(f, "primary")
            f.rule = UI:CreateSeparator(f)
            f.rule:SetPoint("BOTTOMLEFT", 0, 0)
            f.rule:SetPoint("BOTTOMRIGHT", 0, 0)
            f.rule:SetAlpha(0.4)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ROW_H)
        local level = levelByKey[m.key]
        local ink = roleColor(m.role)
        row.name:SetText(coloured(m.name, classByKey[m.key]) .. (level and ("  |cff999999" .. L["Lv "] .. level .. "|r") or ""))
        oneLine(row.name, NAME_W + LEVEL_W)
        fit(row.invite, string.format(L["Invite as %s"], GuildOS:ColorText(B:RoleName(ROLE_OF[m.role]), ink.r, ink.g, ink.b)))
        local taken = rightAlign(row, { row.invite }, -2, 0)
        local what = B:Describe(m.entry)
        row.what:ClearAllPoints()
        row.what:SetPoint("LEFT", NAME_W + LEVEL_W + 8, 0)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, width - NAME_W - LEVEL_W - taken - 16)
        local key, name, role = m.key, m.name, m.role
        row.invite:SetScript("OnClick", function() G:InviteSeeker(key, name, role) end)
        y = y + ROW_H
    end

    -- On its section title's line, flush with the content's right edge, which already stops clear of
    -- the scroll bar (#371).
    local function scopeButton(strip)
        local b = acquire("scope", function()
            local s = smallButton(content)
            s:SetScript("OnClick", function()
                B:SetPref("allianceScope", not B:Pref("allianceScope"))
                paint()
            end)
            return s
        end)
        b.label:SetText(B:Pref("allianceScope") and L["Scope: Alliance"] or L["Scope: Guild"])
        b:ClearAllPoints()
        b:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    end

    local function paintActive()
        local now = GetServerTime()
        local onlineSet, classByKey = B:_BuildOnlineRoster()
        local mine = B:MyKey()
        local myLevel = UnitLevel("player") or 1
        local myRoles = B:Pref("roles") or ""
        local cat, levelOnly = B:Pref("filterCat") or "all", B:Pref("filterLevel") and true or false
        local known = false
        for _, def in ipairs(K.FILTERS) do known = known or def.key == cat end
        if not known then cat = "all" end
        local levelByKey = rosterLevels()

        -- The groups of others that pass the filter, those for me first (#378), then newest.
        local groups, forMe, nForMe = {}, {}, 0
        for _, g in ipairs(G:ActiveList(GuildOS.db.lfgGroups, now, onlineSet)) do
            if g.key ~= mine and keeps(g.act, cat, levelOnly, myLevel) then
                groups[#groups + 1] = g
                if G:FitsMe(g, myLevel, myRoles) then
                    forMe[g.key] = true
                    nForMe = nForMe + 1
                end
            end
        end
        table.sort(groups, function(a, b)
            if (forMe[a.key] or false) ~= (forMe[b.key] or false) then return forMe[a.key] == true end
            if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
            return a.key < b.key
        end)

        local seekers = {}
        for _, e in ipairs(B:ActiveList(GuildOS.db.lfgBoard, now, onlineSet)) do
            if keepsSeeker(e, cat, levelOnly, myLevel) then seekers[#seekers + 1] = e end
        end
        local ally = GuildOS.Alliance
        local inAlliance = ally and ally:Get() ~= nil
        if inAlliance and B:Pref("allianceScope") then
            for _, row in ipairs(B:AllianceList(now)) do seekers[#seekers + 1] = row end
        end

        summary(#groups, #seekers, nForMe)

        local myGroup = G:Mine()
        if myGroup then
            leaderPanel(myGroup, now)
            local requests = G:Requests()
            if #requests == 0 then
                line(L["Nobody asked for a spot yet. Guildmates see your group here and in the tiles."])
            else
                head(L["Asking for a spot"], tostring(#requests))
                for _, r in ipairs(requests) do requestRow(r, classByKey) end
                y = y + GAP
            end
            -- Who is looking and would fit (#378): the leader invites them without waiting to be asked.
            local matches = G:Matches(now, onlineSet)
            if #matches > 0 then
                head(L["Fits your group"], tostring(#matches))
                for i = 1, math.min(#matches, SEEKERS_MAX) do matchRow(matches[i], classByKey, levelByKey) end
                y = y + GAP
            end
        end

        head(L["Groups being formed"], tostring(#groups))
        if #groups == 0 then
            line(L["No group is being formed right now. Pick an activity to start one."])
        else
            groupGrid(groups, now, classByKey, forMe)
        end

        local strip = head(L["Looking for a group"], tostring(#seekers))
        if inAlliance then scopeButton(strip) end
        if #seekers == 0 then
            line(L["Nobody is available right now. Be the first!"])
            return
        end
        for i = 1, math.min(#seekers, SEEKERS_MAX) do seekerRow(seekers[i], now, classByKey, levelByKey, mine) end
        if #seekers > SEEKERS_MAX then line(string.format(L["... and %d more."], #seekers - SEEKERS_MAX)) end
    end

    ------------------------------------------------------------------
    -- Tiles
    ------------------------------------------------------------------
    local function makeTile()
        local t = CreateFrame("Button", nil, content, "BackdropTemplate")
        t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(t) })
        t:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        t.art = t:CreateTexture(nil, "ARTWORK")
        t.art:SetPoint("TOPLEFT", 1, -1)
        t.art:SetPoint("BOTTOMRIGHT", -1, 1)
        t.art:SetTexCoord(0, 1, 0.08, 0.72)
        t.art:SetAlpha(ART_ALPHA)
        t.name = UI:CreateText(t, "", 12)   -- in `text`, set per tile below (#371)
        t.name:SetPoint("BOTTOMLEFT", 8, 6)
        t.name:SetJustifyH("LEFT")
        t.name:SetJustifyV("BOTTOM")
        t.name:SetWordWrap(true)
        t.level = UI:CreateText(t, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        t.level:SetPoint("TOPRIGHT", -6, -5)
        t.groups = UI:CreateText(t, "", 10, C.ok.r, C.ok.g, C.ok.b)
        t.groups:SetPoint("TOPLEFT", 8, -5)
        t.seekers = UI:CreateText(t, "", 10, C.info.r, C.info.g, C.info.b)
        -- Hovered, a tile lights its border as a secondary button does (`label`): gold is for selection.
        t:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.title, C.text.r, C.text.g, C.text.b)
            if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1) end
            GameTooltip:AddLine(L["Click to form a group or list yourself."], C.label.r, C.label.g, C.label.b, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            GameTooltip:Hide()
        end)
        return t
    end

    local function tile(it, x, w, counts, myLevel)
        local t = acquire("tile", makeTile)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(w, TILE_H)
        t:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        -- A tile with no art of its own (WoW: Forever's new dungeons) is a flat `panel` card, not the
        -- dark well the art sits on, so it reads as a tile beside the others and not an empty box (#371).
        local artOk = hasArt(it)
        local fill = artOk and C.well or C.panel
        t:SetBackdropColor(fill.r, fill.g, fill.b, 1)
        if artOk then
            t.art:SetTexture(it.art)
            t.art:Show()
        else
            t.art:Hide()
        end
        local name = B:ActivityName(it.id)
        t.title = name
        t.name:SetWidth(w - 16)
        t.name:SetText(name)
        local range = rangeOf(it)
        t.level:SetText(range)
        local details = {}
        if it.min then details[#details + 1] = string.format(L["Level %s"], range) end
        details[#details + 1] = string.format(L["%d players"], it.size)
        t.detail = table.concat(details, DOT)
        local c = counts[it.id]
        t.groups:SetText(c and c.groups > 0 and string.format(L["%d forming"], c.groups) or "")
        t.seekers:ClearAllPoints()
        if c and c.groups > 0 then
            t.seekers:SetPoint("LEFT", t.groups, "RIGHT", 8, 0)
        else
            t.seekers:SetPoint("TOPLEFT", 8, -5)
        end
        t.seekers:SetText(c and c.seekers > 0 and string.format(L["%d looking"], c.seekers) or "")
        local mine = not it.min or (myLevel >= it.min and myLevel <= it.max + LEVEL_SLACK)
        t:SetAlpha(mine and 1 or OFF_LEVEL_ALPHA)
        local ink = mine and C.text or C.label   -- a dimmed tile's title steps down too (#371)
        t.name:SetTextColor(ink.r, ink.g, ink.b)
        local id = it.id
        t:SetScript("OnClick", function() openComposer(id) end)
    end

    local function tileSection(title, items, counts, myLevel, cols, w)
        head(title)
        for i, it in ipairs(items) do
            local col = (i - 1) % cols
            if col == 0 and i > 1 then y = y + TILE_H + GAP end
            tile(it, col * (w + GAP), w, counts, myLevel)
        end
        y = y + TILE_H
    end

    local function paintTiles(cat)
        local now = GetServerTime()
        local onlineSet = B:_BuildOnlineRoster()
        local counts = G:Counts(now, onlineSet)
        local myLevel = UnitLevel("player") or 1
        local cols = math.max(1, math.floor((width + GAP) / (TILE_MIN_W + GAP)))
        local w = math.floor((width - GAP * (cols - 1)) / cols)
        local sections = Cat:Sections(cat)
        -- Dungeons open on what I can run now (#373): every tile whose range holds my level, once,
        -- before the sections that list them all. Strictly the range: the slack that keeps a tile lit
        -- a few levels past it is for reading the full list, not for recommending.
        if cat == "dungeon" then
            local mine, seen = {}, {}
            for _, s in ipairs(sections) do
                for _, it in ipairs(s.items) do
                    if it.min and it.max and myLevel >= it.min and myLevel <= it.max and not seen[it.id] then
                        seen[it.id] = true
                        mine[#mine + 1] = it
                    end
                end
            end
            if #mine > 0 then tileSection(L["For your level"], mine, counts, myLevel, cols, w) end
        end
        for _, s in ipairs(sections) do tileSection(s.title, s.items, counts, myLevel, cols, w) end
    end

    ------------------------------------------------------------------
    -- Painting
    ------------------------------------------------------------------
    paint = function()
        if not parent:IsVisible() then return end
        B:Prune()
        G:Prune()
        releaseAll()
        -- Read only while shown (the early return above), and minus the gutter BindScrollChildWidth
        -- keeps, so the tiles and the text that is cut to fit stop clear of the scroll bar (#371).
        local w = scroll:GetWidth() or 0
        width = (w > 1 and w or 400) - UI.SCROLL_GUTTER
        content:SetWidth(width)
        y = 0
        if parent.activeSub == "active" then paintActive() else paintTiles(parent.activeSub) end
        content:SetHeight(math.max(1, y + 8))

        local roles = B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do myChips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        seekBtn.label:SetText(B:Mine() and L["Stop looking"] or L["I am looking..."])
        groupBtn.label:SetText(G:Mine() and L["My group"] or L["+ Form a group"])
        if composer and composer:IsShown() then composer.Repaint() end
    end

    local function selectSub(key)
        local known = false
        for _, t in ipairs(SUBS) do known = known or t.key == key end
        parent.activeSub = known and key or "active"
        for k, btn in pairs(subTabs) do btn:SetActive(k == parent.activeSub) end
        scroll:SetVerticalScroll(0)
        GuildOS:SafeCall(paint)
    end
    parent.SelectSub = selectSub   -- deep links: /gos avail, Guild > Call to Arms

    for _, t in ipairs(SUBS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabs[t.key] = btn
        subList[#subList + 1] = btn
    end
    UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })

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
    seekBtn:SetScript("OnClick", function()
        if B:Mine() then B:ClearAvailable() else openComposer(nil, "seek") end
    end)
    groupBtn:SetScript("OnClick", function()
        if G:Mine() then
            openComposer(nil, "group")
        elseif parent.activeSub == "active" then
            -- A group is for something: the tiles are where that is picked.
            selectSub("dungeon")
        else
            openComposer(nil, "group")
        end
    end)

    -- The board's refresh hook: every change the modules make lands here.
    B.uiRefresh = paint

    parent:SetScript("OnShow", function() selectSub(parent.activeSub or "active") end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(paint)
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })
        GuildOS:SafeCall(paint)
    end)
end
