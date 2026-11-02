----------------------------------------------------------------------
-- Guild OS - Guild Finder screen (specs/071-o-recrutamento in guildos-web, tabs 1 and 4 of the mockup)
-- What a character with no guild opens on WoW: Forever and retail: one guild at a time on a large
-- card with arrows, filters on top, the times on the player's own clock. Every rule lives in
-- Modules/GuildFinder.lua; this file only draws it and calls it (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local function GF() return GuildOS.GuildFinder end

local WIDTH, HEIGHT = 580, 470
local CHIP_W, CHIP_H, CHIP_GAP = 104, 22, 6
local ROW_PITCH = 20           -- a card row
local LABEL_W   = 84           -- the grey word before a row's value
local VALUE_W   = 330

local LANG_NAME = {
    pt = L["Portuguese"], en = L["English"], es = L["Spanish"], de = L["German"], fr = L["French"],
    ru = L["Russian"], ko = L["Korean"], ["zh-CN"] = L["Chinese (Simplified)"], ["zh-TW"] = L["Chinese (Traditional)"],
}
local PERIOD_NAME = { morning = L["Morning"], afternoon = L["Afternoon"], night = L["Night"], late = L["Late night"] }
local PACE_NAME   = { casual = L["Casual"], regular = L["Regular"], hardcore = L["Hardcore"] }
local FOCUS_NAME  = { RAID = L["Raid"], PVP = L["PvP"], SOCIAL = L["Social"], LEVELING = L["Leveling"], RP = L["RP"] }
local LOOT_NAME   = { council = L["Loot council"], councilWishlist = L["Council + wishlist"], dkp = "DKP", epgp = "EPGP",
                      softres = L["Soft reserve"], msos = L["MS>OS roll"], personal = L["Personal loot"], other = L["Other"] }
local TRIAL_NAME  = { none = L["No trial"], week1 = L["1 week trial"], week2 = L["2 week trial"],
                      days30 = L["30 day trial"], other = L["Other"] }
local RULESET_NAME = { normal = L["Normal"], pvp = L["PvP"], rp = L["Roleplay"], hardcore = L["Hardcore"] }
local REGION_NAME  = { us = L["Americas"], eu = L["Europe"], kr = L["Korea"], tw = L["Taiwan"] }
local ROLE_NAME    = { TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] }

-- The word for a world as it sits on a card and in the menu: "Normal · Americas" on WoW: Forever, the
-- realm as it was sent on retail.
local function worldName(w)
    local place, region = GF():WorldParts(w)
    if not place then return w end
    local where = REGION_NAME[region] or region
    if GuildOS.Client.isRetail then return place .. " \194\183 " .. where end
    return (RULESET_NAME[place] or place) .. " \194\183 " .. where
end

local function factionName(f)
    if f == "H" then return FACTION_HORDE or L["Horde"] end
    if f == "A" then return FACTION_ALLIANCE or L["Alliance"] end
    return nil
end

local FACTION_TINT = { H = { 0.55, 0.15, 0.12 }, A = { 0.16, 0.30, 0.58 } }

-- The first character of a name, whole: a CJK guild's initial is three bytes.
local function initial(name)
    return name:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
end

-- The filter chips, in the order they sit: key in the saved filters, the menu's values, how a value
-- reads, and what "any" says. A click moves to the next value, a right click to the one before.
local ROW1 = {
    { key = "locale", any = L["Any language"], values = function() return GF().LOCALES end, name = function(v) return LANG_NAME[v] end,
      write = function(v) if v == nil then return false end return v end },
    { key = "day",    any = L["Any day"],      values = function() return { 0, 1, 2, 3, 4, 5, 6 } end,
      name = function(v) return L[GF().DAY_KEYS[v]] end },
    { key = "period", any = L["Any time of day"], values = function() return GF().PERIODS end, name = function(v) return PERIOD_NAME[v] end },
    { key = "pace",   any = L["Any pace"],     values = function() return GF().PACES end, name = function(v) return PACE_NAME[v] end },
}
local ROW2 = {
    { key = "world",  any = L["Any world"],    values = function() return GF():Worlds() end, name = worldName },
    { key = "focus",  any = L["Any focus"],    values = function() return GF().FOCUS end, name = function(v) return FOCUS_NAME[v] end },
    { key = "loot",   any = L["Any loot rule"], values = function() return GF().LOOTS end, name = function(v) return LOOT_NAME[v] end },
    { key = "trial",  any = L["Any trial"],    values = function() return GF().TRIALS end, name = function(v) return TRIAL_NAME[v] end },
}

local function chipValue(chip, direction)
    local values = chip.values()
    local cur = GF():Current()[chip.key]
    local at = 0
    for i, v in ipairs(values) do if v == cur then at = i end end
    local nextAt = (at + direction) % (#values + 1)
    local v = nextAt > 0 and values[nextAt] or nil
    return v
end

local function BuildFinder()
    local f = CreateFrame("Frame", "GuildOSGuildFinder", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSGuildFinder")

    local title = UI:CreateTitle(f, L["Find your guild"], 14)
    title:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    f.index = 1
    f.more = false

    ------------------------------------------------------------------
    -- Filters
    ------------------------------------------------------------------
    local chips = {}
    local function MakeChips(specs, y)
        for i, spec in ipairs(specs) do
            local b = UI:CreateButton(f, spec.any, CHIP_W, CHIP_H)
            b:SetPoint("TOPLEFT", 14 + (i - 1) * (CHIP_W + CHIP_GAP), y)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", function(_, mouse)
                local v = chipValue(spec, mouse == "RightButton" and -1 or 1)
                if spec.write then v = spec.write(v) end
                GF():SetFilter(spec.key, v)
                f.index = 1
                f.Refresh()
            end)
            b.spec = spec
            chips[#chips + 1] = b
        end
    end
    MakeChips(ROW1, -38)
    local moreBtn = UI:CreateButton(f, L["More filters"], CHIP_W, CHIP_H)
    moreBtn:SetPoint("TOPLEFT", 14 + #ROW1 * (CHIP_W + CHIP_GAP), -38)
    MakeChips(ROW2, -66)

    local wants = UI:CreateCheckbox(f, L["Wants my class"], 16)
    wants:SetPoint("TOPLEFT", 12, -92)
    wants.checkbox.onChanged = function(_, checked)
        GF():SetFilter("wantsMe", checked and true or false)
        f.index = 1
        f.Refresh()
    end

    moreBtn:SetScript("OnClick", function()
        f.more = not f.more
        f.Refresh()
    end)

    ------------------------------------------------------------------
    -- The card
    ------------------------------------------------------------------
    local CARD_TOP = -120
    local prev = UI:CreateButton(f, "<", 30, 60)
    prev:SetPoint("TOPLEFT", 10, CARD_TOP - 90)
    prev:SetScript("OnClick", function() f.Step(-1) end)
    local nxt = UI:CreateButton(f, ">", 30, 60)
    nxt:SetPoint("TOPRIGHT", -10, CARD_TOP - 90)
    nxt:SetScript("OnClick", function() f.Step(1) end)

    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetSize(WIDTH - 100, 300)
    card:SetPoint("TOPLEFT", 50, CARD_TOP)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    card:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.8)

    local shield = CreateFrame("Frame", nil, card, "BackdropTemplate")
    shield:SetSize(46, 46)
    shield:SetPoint("TOPLEFT", 14, -14)
    shield:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    local shieldText = UI:CreateTitle(shield, "?", 20)
    shieldText:SetPoint("CENTER")

    local gname = UI:CreateTitle(card, "", 15)
    gname:SetPoint("TOPLEFT", shield, "TOPRIGHT", 12, -2)
    local gworld = UI:CreateText(card, "", 10, C.label.r, C.label.g, C.label.b)
    gworld:SetPoint("TOPLEFT", gname, "BOTTOMLEFT", 0, -4)
    local seal = UI:CreateText(card, "", 10, C.ok.r, C.ok.g, C.ok.b)
    seal:SetPoint("TOPLEFT", gworld, "BOTTOMLEFT", 0, -4)

    local pitch = UI:CreateText(card, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    pitch:SetPoint("TOPLEFT", 14, -74)
    pitch:SetWidth(WIDTH - 130)
    pitch:SetJustifyH("LEFT")
    pitch:SetWordWrap(true)

    local rows = {}
    for i = 1, 5 do
        local label = UI:CreateHeaderText(card, "", 10)
        label:SetWidth(LABEL_W); label:SetJustifyH("LEFT")
        local value = UI:CreateText(card, "", 11)
        value:SetWidth(VALUE_W); value:SetJustifyH("LEFT"); value:SetWordWrap(false)
        rows[i] = { label = label, value = value }
    end

    local proof = UI:CreateText(card, "", 11, C.gold.r, C.gold.g, C.gold.b)
    proof:SetPoint("BOTTOMLEFT", 14, 50)

    local join = UI:CreateButton(card, L["Ask to join"], 130, 26)
    join:SetPoint("BOTTOMLEFT", 14, 12)
    UI:SetButtonVariant(join, "primary")
    join:SetScript("OnClick", function()
        local ad = f.ads and f.ads[f.index]
        -- The request flow is the next task's (JoinRequests); until it is loaded this does nothing.
        if ad and GuildOS.JoinRequests then GuildOS.JoinRequests:Send(ad) end
    end)
    local whisper = UI:CreateButton(card, L["Whisper"], 90, 26)
    whisper:SetPoint("LEFT", join, "RIGHT", 8, 0)
    local count = UI:CreateText(card, "", 10, C.label.r, C.label.g, C.label.b)
    count:SetPoint("BOTTOMRIGHT", -14, 18)

    local clock = UI:CreateText(f, L["Times are on your clock."], 10, C.label.r, C.label.g, C.label.b)
    clock:SetPoint("BOTTOMLEFT", 14, 12)

    ------------------------------------------------------------------
    -- Nothing to show: no guild heard yet, or the filters cut them all
    ------------------------------------------------------------------
    local empty = CreateFrame("Frame", nil, f)
    empty:SetSize(WIDTH - 100, 300)
    empty:SetPoint("TOPLEFT", 50, CARD_TOP)
    local eShield = CreateFrame("Frame", nil, empty, "BackdropTemplate")
    eShield:SetSize(46, 46)
    eShield:SetPoint("TOP", 0, -20)
    eShield:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    eShield:SetBackdropColor(0.23, 0.18, 0.12, 1)
    local eMark = UI:CreateTitle(eShield, "?", 20)
    eMark:SetPoint("CENTER")
    local eTitle = UI:CreateTitle(empty, "", 14)
    eTitle:SetPoint("TOP", eShield, "BOTTOM", 0, -14)
    local eText = UI:CreateText(empty, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    eText:SetPoint("TOP", eTitle, "BOTTOM", 0, -10)
    eText:SetWidth(WIDTH - 150); eText:SetWordWrap(true)
    local eCompanion = UI:CreateText(empty, L["With the companion, the whole list at guildos.me arrives at once."], 10, C.label.r, C.label.g, C.label.b)
    eCompanion:SetPoint("TOP", eText, "BOTTOM", 0, -12)
    eCompanion:SetWidth(WIDTH - 150); eCompanion:SetWordWrap(true)
    local site = UI:CreateButton(empty, L["Show the list at guildos.me"], 220, 26)
    site:SetPoint("BOTTOM", 0, 50)
    UI:SetButtonVariant(site, "primary")

    -- WoW cannot open a browser: the address goes into a pre-selected read-only box for Ctrl+C.
    local ADDRESS = "https://" .. GF().SITE
    local box = CreateFrame("EditBox", nil, empty, "BackdropTemplate")
    box:SetSize(220, 22)
    box:SetPoint("BOTTOM", 0, 20)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    GuildOS:ApplyFont(box, 11)
    box:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetText(ADDRESS)
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    box:SetScript("OnTextChanged", function(s)
        if s:GetText() ~= ADDRESS then s:SetText(ADDRESS); s:HighlightText() end
    end)
    box:Hide()
    site:SetScript("OnClick", function()
        box:Show()
        box:SetText(ADDRESS)
        box:HighlightText()
        box:SetFocus()
        GuildOS:Print(L["Address selected — press Ctrl+C"])
    end)

    ------------------------------------------------------------------
    -- Drawing
    ------------------------------------------------------------------
    local function Row(i, label, value, r, g, b)
        local row = rows[i]
        row.label:SetText(label)
        row.value:SetText(value)
        row.value:SetTextColor(r or C.text.r, g or C.text.g, b or C.text.b)
    end

    local function LookingFor(ad)
        local me = select(2, UnitClass("player"))
        local parts = {}
        for _, role in ipairs(ad.r or {}) do parts[#parts + 1] = ROLE_NAME[role] or role end
        for _, class in ipairs(ad.c or {}) do
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
            if GuildOS.ClassColors and GuildOS.ClassColors[class] then
                local r, g, b = GuildOS:GetClassColor(class)
                name = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
            end
            if class == me then name = name .. " " .. L["(you!)"] end
            parts[#parts + 1] = name
        end
        if #parts == 0 then return L["Any class"] end
        return table.concat(parts, ", ")
    end

    local function DrawCard(ad)
        local tint = FACTION_TINT[ad.f] or { 0.25, 0.25, 0.28 }
        shield:SetBackdropColor(tint[1], tint[2], tint[3], 1)
        shieldText:SetText(initial(ad.n))
        gname:SetText(ad.n)
        local world = {}
        if factionName(ad.f) then world[#world + 1] = factionName(ad.f) end
        if ad.w then world[#world + 1] = worldName(ad.w) end
        gworld:SetText(table.concat(world, " \194\183 "))
        if ad.verified then
            seal:SetTextColor(C.ok.r, C.ok.g, C.ok.b)
            seal:SetText(L["Verified by GuildOS"])
        else
            seal:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            seal:SetText(L["Heard in the game, not verified"])
        end
        pitch:SetText(ad.p and ("\226\128\156" .. ad.p .. "\226\128\157") or "")

        -- A row with nothing to say is left out, never shown empty.
        local lines = {}
        local nights = GF():Schedule(ad)
        if nights then lines[#lines + 1] = { L["Nights"], nights } end
        local pace = {}
        if ad.pc then pace[#pace + 1] = PACE_NAME[ad.pc] end
        for _, tok in ipairs(ad.fo or {}) do pace[#pace + 1] = FOCUS_NAME[tok] end
        if #pace > 0 then lines[#lines + 1] = { L["Pace"], table.concat(pace, " \194\183 ") } end
        if ad.l then
            local names = {}
            for _, code in ipairs(ad.l) do names[#names + 1] = LANG_NAME[code] end
            lines[#lines + 1] = { L["Language"], table.concat(names, ", ") }
        end
        lines[#lines + 1] = { L["Looking for"], LookingFor(ad) }
        local loot = {}
        if ad.lo then loot[#loot + 1] = LOOT_NAME[ad.lo] end
        if ad.t then loot[#loot + 1] = TRIAL_NAME[ad.t] end
        if #loot > 0 then lines[#lines + 1] = { L["Loot"], table.concat(loot, " \194\183 ") } end

        -- The pitch can take two lines: the rows start under whatever it used.
        local top = -78 - math.max(14, pitch:GetStringHeight() or 14) - 12
        for i, row in ipairs(rows) do
            local line = lines[i]
            if line then
                row.label:ClearAllPoints(); row.value:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", card, "TOPLEFT", 14, top - (i - 1) * ROW_PITCH)
                row.value:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
                Row(i, line[1], line[2])
                row.label:Show(); row.value:Show()
            else
                row.label:Hide(); row.value:Hide()
            end
        end

        local m = ad.m
        local numbers = {}
        if m and m.n then numbers[#numbers + 1] = string.format(L["%d members"], m.n) end
        if m and m.nt then numbers[#numbers + 1] = string.format(L["%d nights a week"], m.nt) end
        if m and m.a then numbers[#numbers + 1] = string.format(L["%d%% attendance"], m.a) end
        proof:SetText(table.concat(numbers, "     "))

        local contact = ad.ct and ad.ct[1]
        whisper:SetShown(contact ~= nil)
        whisper:SetScript("OnClick", function()
            if contact then ChatFrame_OpenChat("/w " .. Ambiguate(contact, "none") .. " ") end
        end)
    end

    function f.Step(d)
        local n = f.ads and #f.ads or 0
        if n == 0 then return end
        f.index = (f.index - 1 + d) % n + 1
        f.Refresh()
    end

    function f.Refresh()
        local cur = GF():Current()
        for _, b in ipairs(chips) do
            local spec = b.spec
            local v = cur[spec.key]
            local shown = v ~= nil and spec.name(v) or nil
            b.label:SetText(shown or spec.any)
        end
        for i = #ROW1 + 1, #chips do chips[i]:SetShown(f.more) end
        moreBtn.label:SetText(f.more and L["Fewer filters"] or L["More filters"])
        wants.checkbox:SetChecked(GF():Saved().wantsMe ~= false)

        f.ads = GF():Ads(cur)
        if f.index > #f.ads then f.index = 1 end
        local ad = f.ads[f.index]
        card:SetShown(ad ~= nil); prev:SetShown(ad ~= nil); nxt:SetShown(ad ~= nil)
        empty:SetShown(ad == nil)
        if ad then
            DrawCard(ad)
            count:SetText(string.format(L["%d of %d"], f.index, #f.ads))
        elseif #GF():All() > 0 then
            eTitle:SetText(L["No guild fits these filters"])
            eText:SetText(L["Loosen a filter to see the others."])
            eCompanion:Hide()
        else
            eTitle:SetText(L["No guild heard yet"])
            eText:SetText(L["Guilds are being born right now. The network listens for you while you play, and the minimap button lights up when one shows up."])
            eCompanion:Show()
        end
    end

    return f
end

function GuildOS:ShowGuildFinder()
    local f = self.guildFinder or BuildFinder()
    self.guildFinder = f
    -- Live while open: a guild heard now joins the deck without moving the one being read.
    if self.RecruitBeacon then
        self.RecruitBeacon.onUpdate = function()
            if f:IsShown() then f.Refresh() end
        end
    end
    if self.SetMinimapAlert then self:SetMinimapAlert(false) end
    f.Refresh()
    f:Show(); f:Raise()
end

-- The first guild heard this session: the minimap button, which is what is on screen while the
-- player plays, lights up. The finder never opens by itself.
function GuildOS:GuildFinderHeard()
    if self.SetMinimapAlert then self:SetMinimapAlert(true) end
end
