----------------------------------------------------------------------
-- Guild OS - The founding letter (issue #208)
-- The GM records the guild's founding day; an officer who is not the GM suggests one. Every decision
-- is Modules/Founding.lua's: this only draws and calls it (Rule 10).
-- WoW: Forever only: the module does not exist elsewhere, and nothing here runs without it.
----------------------------------------------------------------------
local UI = GuildOS.UI
local L = GuildOS.L
local C = GuildOS.Colors

local DAY = 86400

local function build()
    local f = UI:CreatePanel(UIParent, "GuildOSFoundingLetter")
    f:SetSize(440, 250)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(50)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UI:StylePopup(f, { shadowSize = 18 })

    local title = UI:CreateTitle(f, L["Found your guild on Guild OS"], 18)
    title:SetPoint("TOP", 0, -18)

    local body = UI:CreateText(f, L["Your guild was born with WoW: Forever. Record its founding date and everyone who joins in the next 14 days becomes a founding member — forever in your guild's book."], 12, C.text.r, C.text.g, C.text.b)
    body:SetPoint("TOPLEFT", 24, -56)
    body:SetPoint("TOPRIGHT", -24, -56)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)

    local dateFS = UI:CreateText(f, "", 13, C.gold.r, C.gold.g, C.gold.b)
    dateFS:SetPoint("TOP", 0, -138)
    f.date = dateFS
    local prev = UI:CreateButton(f, "<", 26, 22)
    prev:SetPoint("RIGHT", dateFS, "LEFT", -12, 0)
    local nextB = UI:CreateButton(f, ">", 26, 22)
    nextB:SetPoint("LEFT", dateFS, "RIGHT", 12, 0)
    local function move(days)
        local now = GetServerTime()
        local t = f.day + days * DAY
        if GuildOS.Founding.ValidDay(t, now) then f.day = t end
        f.render()
    end
    prev:SetScript("OnClick", function() move(-1) end)
    nextB:SetScript("OnClick", function() move(1) end)

    local note = UI:CreateText(f, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    note:SetPoint("TOP", dateFS, "BOTTOM", 0, -6)
    f.note = note

    local ok = UI:CreateButton(f, "", 190, 26)
    ok:SetPoint("BOTTOMRIGHT", -24, 18)
    f.ok = ok
    local later = UI:CreateButton(f, L["Later"], 110, 26)
    later:SetPoint("BOTTOMLEFT", 24, 18)
    later:SetScript("OnClick", function()
        if f.prompted then GuildOS.Founding:Later(GetServerTime()) end
        f:Hide()
    end)

    ok:SetScript("OnClick", function()
        local F = GuildOS.Founding
        if F:IsGM() then
            if F:Record(f.day, f.source) then
                GuildOS:Print(string.format(L["Founding recorded: %s"], date("!%Y-%m-%d", f.day)))
                f:Hide()
            end
        elseif F:Suggest(f.day) then
            GuildOS:Print(L["Suggestion sent to your GM"])
            f:Hide()
        end
    end)

    function f.render()
        local F = GuildOS.Founding
        f.date:SetText(string.format(L["Founding date: %s"], date("!%Y-%m-%d", f.day)))
        f.ok.label:SetText(F:IsGM() and L["Record founding"] or L["Suggest founding date to your GM"])
        local s = GuildOS.db.foundingSuggested
        f.note:SetText(s and F:IsGM() and string.format(L["Suggested by %s"], (s.by or ""):match("^([^-]+)") or "") or "")
    end
    return f
end

-- Open the letter. `prompted`: it came by itself, so "Later" counts towards putting it away.
function GuildOS:ShowFoundingLetter(prompted)
    if not self.Founding then return end
    self.foundingFrame = self.foundingFrame or build()
    local f = self.foundingFrame
    local held = self.Founding:Get()
    if held then
        f.day, f.source = held.foundedAt, "declared"
    else
        f.day, f.source = self.Founding:SuggestedDay(GetServerTime())
    end
    f.prompted = prompted and true or false
    f.render()
    f:Show()
end

-- At login, to the GM of a guild with no founding yet (Core.lua after the onboarding).
function GuildOS:MaybeShowFoundingLetter()
    if self.Founding and self.Founding:ShouldPrompt(GetServerTime()) then self:ShowFoundingLetter(true) end
end
