----------------------------------------------------------------------
-- Guild OS - First-run onboarding wizard
-- A small welcome flow shown once (settings.onboarded) so new users
-- understand what the addon does, how to open it, and what is shared.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local Style = GuildOS.Style
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Retail has no loot master and no attunements (ADR-0026): its welcome, getting-started, privacy and
-- officer steps say what it does have (issues #177, #185: the wishlist and the Loot settings are retail's).
local RETAIL = GuildOS.Client.isRetail

local STEPS = {
    {
        -- First, where the client draws both styles (#375): the look, before anything else. A pick is
        -- saved at once; the reload it needs waits until the wizard is finished.
        title = L["Choose your style"],
        body  = string.format(L["How should Guild OS look? You can change it later in %s > %s."], L["Settings"], L["Interface"]),
        styleStep = true,
    },
    {
        title = L["Welcome to Guild OS"],
        body  = (RETAIL and L["An all-in-one guild suite: roster, raid attendance, cores, recruitment, professions, leadership tools and audits — all synced between guildmates who run the addon."]
            or L["An all-in-one guild suite: roster, raid attendance, loot, wishlists, attunements, leadership tools and audits — all synced between guildmates who run the addon."])
            .. "\n\n|cff888888" .. L["Made with care by "] .. "|cffFFD700Chehul|r|r",
    },
    {
        title = L["Getting started"],
        body  = RETAIL and L["Open it anytime with /guildos, the minimap button, or a key binding. Click any guildmate to see their full character — gear, spec and professions."]
            or L["Open it anytime with /guildos, the minimap button, or a key binding. Click any guildmate to see their full character — gear, professions and attunements."],
    },
    {
        title = L["The guild button"],
        body  = L["By default the guild button (and \"J\") opens Guild OS. Prefer Blizzard's own guild window — chat history, news? Turn this off; you can still open Guild OS from the minimap button."],
        guildButtonToggle = true,  -- render the hijack checkbox on this step
    },
    {
        title = L["Data & privacy"],
        body  = RETAIL and L["Guild OS shares your gear, professions, spec and wishlist with guildmates running the addon, so everyone sees the same roster. Officer notes and trials stay officer-only."]
            or L["Guild OS shares your gear, professions, attunements, spec and wishlist with guildmates running the addon, so everyone sees the same roster. Officer notes and trials stay officer-only."],
    },
    {
        title = L["Your raid roles"],
        body  = L["Which roles can you play? Pick any that apply. Your guild's Raiders list picks this up automatically, so officers don't have to set it for you. You can change it later in Settings."],
        roleStep = true,  -- render the self-service role picker on this step
    },
    {
        title = L["Officer tools"],
        body  = RETAIL and L["As an officer you unlock leadership tools. In Settings > Guild rules, set which guild ranks count as officers. In the Loot window's Rule tab, choose how the guild hands out loot: free roll, Wishlist or DKP."]
            or L["As an officer you unlock leadership tools. In Settings > Guild rules, set which guild ranks count as officers. In the Loot window's Rule tab, choose how the guild hands out loot: /roll, TMB, Wishlist or DKP."],
        officer = true,
    },
}

local function BuildFrame()
    local f = UI:CreatePanel(UIParent, "GuildOSOnboarding")
    f:SetSize(440, 300)   -- 300: the style step's cards and the buttons under them (#375)
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
        GuildOS:SetSetting("hijackGuildButton", checked and true or false)
    end
    gbToggle:Hide()
    f.gbToggle = gbToggle

    -- Per-step self-service role picker (shown only on the roleStep).
    local rolePick = GuildOS:CreateRolePicker(f)
    rolePick:SetPoint("TOPLEFT", 24, -186)
    rolePick:Hide()
    f.rolePick = rolePick

    -- The style step's cards (#375): each one its style's name, a sample of the look (a flat button, or
    -- the game's red button) and what it is; the chosen one marked as every selection is.
    local CARD_W, CARD_H, CARD_GAP = 188, 112, 16
    local cards = {}
    for i, id in ipairs(Style.ORDER) do
        local card = UI:CreateButton(f, "", CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", 24 + (i - 1) * (CARD_W + CARD_GAP), -118)
        card.id = id
        card.title = UI:CreateText(card, Style:Name(id), 13, C.text.r, C.text.g, C.text.b)
        card.title:SetPoint("TOPLEFT", 10, -10)
        local sample = CreateFrame("Frame", nil, card, "BackdropTemplate")
        sample:SetSize(110, 22)
        sample:SetPoint("TOPLEFT", 10, -32)
        sample:EnableMouse(false)   -- a click on it is the card's
        if id == "forever" then
            Style:_PaintThree(sample, Style.FOREVER.button.rest, "ARTWORK")
        else
            sample:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(sample) })
            sample:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
            sample:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        end
        local word = UI:CreateText(sample, L["Apply"], 11, C.text.r, C.text.g, C.text.b)
        word:SetPoint("CENTER", 0, 0)
        card.sample = sample
        card.desc = UI:CreateText(card, Style:Description(id), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        card.desc:SetPoint("TOPLEFT", 10, -62)
        card.desc:SetPoint("TOPRIGHT", -10, -62)
        card.desc:SetJustifyH("LEFT")
        card.desc:SetWordWrap(true)
        card:SetScript("OnClick", function()
            if Style:Choose(id) then
                f.chosen = id
                f.render()
            end
        end)
        card:Hide()
        cards[#cards + 1] = card
    end
    f.styleCards = cards

    local backBtn = UI:CreateButton(f, L["Back"], 90, 24)
    backBtn:SetPoint("BOTTOMLEFT", 16, 16)
    f.backBtn = backBtn

    local nextBtn = UI:CreateButton(f, L["Next"], 90, 24)
    nextBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    f.nextBtn = nextBtn

    local settingsBtn = UI:CreateButton(f, L["Open Settings"], 120, 24)
    -- Beside Next, not centred: "Finish and reload" grows Next leftwards past the middle in the longer
    -- languages, and a centred button sat under it (ruRU, frFR; #375).
    settingsBtn:SetPoint("BOTTOMRIGHT", nextBtn, "BOTTOMLEFT", -8, 0)
    settingsBtn:SetScript("OnClick", function()
        GuildOS.UI:OpenWindow("settings")
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
        -- A style picked that is not the one on screen: the last button says it reloads (#375).
        local reload = f.chosen ~= nil and f.chosen ~= f.startStyle
        f.nextBtn.label:SetText(f.step < #f.steps and L["Next"] or (reload and L["Finish and reload"] or L["Finish"]))
        for _, card in ipairs(f.styleCards) do
            card:SetShown(s.styleStep and Style:Has(card.id) or false)
            UI:SetSelected(card, card.id == f.chosen)
        end
        f.settingsBtn:SetShown(f.step == #f.steps)
        -- Guild-button takeover toggle: only on its step, reflecting the live setting.
        if s.guildButtonToggle then
            f.gbToggle.checkbox:SetChecked(GuildOS:IsGuildButtonHijacked())
            f.gbToggle:Show()
        else
            f.gbToggle:Hide()
        end
        -- Self-service role picker: only on the role step.
        if s.roleStep then
            f.rolePick.refresh()
            f.rolePick:Show()
        else
            f.rolePick:Hide()
        end
    end

    backBtn:SetScript("OnClick", function()
        if f.step > 1 then f.step = f.step - 1; render() end
    end)
    -- The game refuses a reload in combat (ADDON_ACTION_BLOCKED, seen in game): finished then, the wizard
    -- closes as ever and the style's reload is offered the moment combat ends, behind the click of the
    -- same dialog Settings uses (#375).
    local afterCombat = CreateFrame("Frame")
    afterCombat:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        -- The style saved by then, not the wizard's: a replay or Settings during the fight may have changed it.
        local want = type(GuildOSDB) == "table" and GuildOSDB.style or nil
        if want and want ~= Style:Current() then
            GuildOS:ShowDialog("GUILDOS_STYLE_RELOAD",
                string.format(L["Reload the interface now to use the %s style?"], Style:Name(want)))
        end
    end)
    f.afterCombat = afterCombat

    nextBtn:SetScript("OnClick", function()
        if f.step < #f.steps then
            f.step = f.step + 1
            render()
        else
            GuildOS:SetSetting("onboarded", true)
            -- The style picked on the first step, if it is not the one on screen: its reload, now that the
            -- wizard is done and nothing of it is lost (#375). Before the wizard is hidden: on WoW: Forever
            -- a click that hid its window first could not reload (ADDON_ACTION_BLOCKED out of combat, seen in
            -- game), while Web's "Publish now", which only calls ReloadUI, reloads.
            if f.chosen ~= nil and f.chosen ~= f.startStyle then
                if not InCombatLockdown() then
                    ReloadUI()
                    return
                end
                GuildOS:Print(L["Can't reload during combat."])
                afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            f:Hide()
        end
    end)

    f.render = render
    return f
end

function GuildOS:ShowOnboarding()
    if not self.onboardingFrame then
        self.onboardingFrame = BuildFrame()
    end
    -- Officer-only steps (e.g. loot system) are skipped for non-officers, and the style step where the
    -- client draws one style only (#375).
    local steps, officer = {}, self:IsOfficer()
    local both = #Style:Available() > 1
    for _, s in ipairs(STEPS) do
        if (not s.officer or officer) and (not s.styleStep or both) then steps[#steps + 1] = s end
    end
    self.onboardingFrame.steps = steps
    self.onboardingFrame.step = 1
    -- The style on screen, and the one already chosen: a style applied in Settings with its reload left for
    -- later is the chosen card, and finishing reloads to it (#375).
    local saved = type(GuildOSDB) == "table" and GuildOSDB.style or nil
    self.onboardingFrame.startStyle = Style:Current()
    self.onboardingFrame.chosen = (saved and Style:Has(saved)) and saved or Style:Current()
    self.onboardingFrame.render()
    self.onboardingFrame:Show()
end

-- Show the wizard once, on first run in a guild.
function GuildOS:MaybeShowOnboarding()
    if not IsInGuild() then return end
    if self:GetSetting("onboarded") then return end
    -- Never in combat, and one login popup at a time (audit B21).
    self:ShowWhenClear("onboarding", function()
        if self:GetSetting("onboarded") then return nil end
        self:ShowOnboarding()
        return self.onboardingFrame
    end)
end
