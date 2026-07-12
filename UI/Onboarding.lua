----------------------------------------------------------------------
-- Guild OS - First-run onboarding wizard
-- A small welcome flow shown once (settings.onboarded) so new users
-- understand what the addon does, how to open it, and what is shared.
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L

local STEPS = {
    {
        title = L["Welcome to Guild OS"],
        body  = L["An all-in-one guild suite: roster, raid attendance, loot, wishlists, attunements, leadership tools and audits — all synced between guildmates who run the addon."]
            .. "\n\n|cff888888" .. L["Made with care by "] .. "|cffFFD700Chehul|r|r",
    },
    {
        title = L["Getting started"],
        body  = L["Open it anytime with /guildos, the minimap button, or a key binding. Click any guildmate to see their full character — gear, professions and attunements."],
    },
    {
        title = L["The guild button"],
        body  = L["By default the guild button (and \"J\") opens Guild OS. Prefer Blizzard's own guild window — chat history, news? Turn this off; you can still open Guild OS from the minimap button."],
        guildButtonToggle = true,  -- render the hijack checkbox on this step
    },
    {
        title = L["Data & privacy"],
        body  = L["Guild OS shares your gear, professions, attunements, spec and wishlist with guildmates running the addon, so everyone sees the same roster. Officer notes and trials stay officer-only."],
    },
    {
        title = L["Officer tools"],
        body  = L["As an officer you unlock leadership tools. In Settings -> Officer, set which guild ranks count as officers. In Settings -> Loot, choose how the guild hands out loot: /roll, TMB, Wishlist or DKP."],
        officer = true,
    },
}

local function BuildFrame()
    local f = UI:CreatePanel(UIParent, "GuildOSOnboarding")
    f:SetSize(440, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(50)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UI:StylePopup(f, { shadowSize = 18 })

    local title = UI:CreateTitle(f, "", 18)
    title:SetPoint("TOP", 0, -18)
    f.title = title

    local stepLbl = UI:CreateText(f, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    stepLbl:SetPoint("TOP", title, "BOTTOM", 0, -4)
    f.stepLbl = stepLbl

    local body = UI:CreateText(f, "", 12, C.text.r, C.text.g, C.text.b)
    body:SetPoint("TOPLEFT", 24, -78)
    body:SetPoint("TOPRIGHT", -24, -78)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    f.body = body

    -- Per-step interactive control: the guild-button takeover toggle. Only shown on the
    -- step flagged guildButtonToggle; applies immediately (default on = opens Guild OS).
    local gbToggle = UI:CreateCheckbox(f, L["Guild button opens Guild OS"], 18)
    gbToggle:SetPoint("TOPLEFT", 24, -196)
    gbToggle.checkbox.onChanged = function(_, checked)
        BRutus:SetSetting("hijackGuildButton", checked and true or false)
    end
    gbToggle:Hide()
    f.gbToggle = gbToggle

    local backBtn = UI:CreateButton(f, L["Back"], 90, 24)
    backBtn:SetPoint("BOTTOMLEFT", 16, 16)
    f.backBtn = backBtn

    local nextBtn = UI:CreateButton(f, L["Next"], 90, 24)
    nextBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    f.nextBtn = nextBtn

    local settingsBtn = UI:CreateButton(f, L["Open Settings"], 120, 24)
    settingsBtn:SetPoint("BOTTOM", 0, 16)
    settingsBtn:SetScript("OnClick", function()
        BRutus:ToggleRoster()
        if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then
            BRutus.RosterFrame:SetActiveTab("settings")
        end
    end)
    f.settingsBtn = settingsBtn

    f.step = 1
    f.steps = STEPS  -- replaced per-show by ShowOnboarding (officer filtering)

    local function render()
        local s = f.steps[f.step]
        f.title:SetText(s.title)
        f.stepLbl:SetText(string.format(L["Step %d of %d"], f.step, #f.steps))
        f.body:SetText(s.body)
        f.backBtn:SetShown(f.step > 1)
        f.nextBtn.label:SetText(f.step < #f.steps and L["Next"] or L["Finish"])
        f.settingsBtn:SetShown(f.step == #f.steps)
        -- Guild-button takeover toggle: only on its step, reflecting the live setting.
        if s.guildButtonToggle then
            f.gbToggle.checkbox:SetChecked(BRutus:IsGuildButtonHijacked())
            f.gbToggle:Show()
        else
            f.gbToggle:Hide()
        end
    end

    backBtn:SetScript("OnClick", function()
        if f.step > 1 then f.step = f.step - 1; render() end
    end)
    nextBtn:SetScript("OnClick", function()
        if f.step < #f.steps then
            f.step = f.step + 1
            render()
        else
            BRutus:SetSetting("onboarded", true)
            f:Hide()
        end
    end)

    f.render = render
    return f
end

function BRutus:ShowOnboarding()
    if not self.onboardingFrame then
        self.onboardingFrame = BuildFrame()
    end
    -- Officer-only steps (e.g. loot system) are skipped for non-officers.
    local steps, officer = {}, self:IsOfficer()
    for _, s in ipairs(STEPS) do
        if not s.officer or officer then steps[#steps + 1] = s end
    end
    self.onboardingFrame.steps = steps
    self.onboardingFrame.step = 1
    self.onboardingFrame.render()
    self.onboardingFrame:Show()
end

-- Show the wizard once, on first run in a guild.
function BRutus:MaybeShowOnboarding()
    if not IsInGuild() then return end
    if self:GetSetting("onboarded") then return end
    self:ShowOnboarding()
end
