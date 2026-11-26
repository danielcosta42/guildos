----------------------------------------------------------------------
-- Guild OS - Web panel
-- The web companion's four slash commands, as buttons that explain
-- themselves. A disabled button prints its reason underneath rather
-- than making you click and then read the refusal in chat.
--
-- What this panel may claim is bounded by what the addon can know: it
-- writes GuildOSDB.__companion at logout and the Go companion forwards
-- it. The addon never sees the send, so this still says "written" about
-- its own half — but the companion now leaves what the site answered in
-- the inbox, and that line is allowed to say "the site has it".
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local SITE    = "guildos.me"
-- Where every tab's content starts (#371): 10px in, as the other tabs' sub-tab bars, the first line
-- UI.GAP from the top, and the content ends UI.GAP short of that 10px on the right.
local INSET   = 10
local GAP     = UI.GAP   -- between stacked lines
local RIGHT_INSET = INSET + GAP
local SECTION = 20   -- over a later section title, for the rule UI:CreateSectionTitle draws 12px above it
local TITLE_H = 24   -- a section title and the gap under it
local BTN_H   = 22
local ROW_H   = 16

-- The cut for both lists. This is a column inside another panel, not a roster
-- browser: a standby of eight people is a question for the website, and the two
-- names a raid leader is about to call are the two at the top.
local LIST_ROWS = 5

-- How old the companion's last word can be before it is worth saying something.
--
-- Days rather than hours, and deliberately generous: the game reads Inbox.lua
-- when the client loads, so somebody logged in all evening is looking at a value
-- that was already hours old when they saw it. The companion refreshes it every
-- hour while it can reach the site, so three days means three days of failing.
local ACK_STALE = 3 * 24 * 60 * 60

-- A countdown in the shape the Now cards had ("2d 4h", "4:12"), kept local.
local function fmtCountdown(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format(L["in %dd %dh"], d, h) end
    if h > 0 then return string.format(L["in %dh %dm"], h, m) end
    return string.format(L["in %dm"], math.max(1, m))
end

local function stamp(at)
    if not at or at <= 0 then return L["never"] end
    local dt = (GetServerTime() or time()) - at
    if dt < 120 then return L["just now"] end
    return GuildOS:DateText(at, " %H:%M")
end

local function writtenAgo()
    return stamp(GuildOSDB and GuildOSDB.__companionAt)
end

-- "WARRIOR" is a token, not a word. The client already holds the word, in the
-- player's own language, so nothing here needs translating.
local function className(token)
    if type(token) ~= "string" or token == "" then return "" end
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return (names and names[token]) or token
end

----------------------------------------------------------------------
-- What the panel says about a roster, out of the v2 signup list.
--
-- Returns nil for a v1 payload, where `signups` is absent. Absent is not empty:
-- an older website sends no list at all, and reporting "0 declined" from that
-- would be an invention dressed as a measurement.
----------------------------------------------------------------------
local function summarise(roster)
    local list = roster and roster.signups
    if type(list) ~= "table" then return nil end

    -- Same answer the invite button acts on. Listing somebody under "the game has never
    -- seen this character" a second after inviting them off the guild roster is exactly
    -- the disagreement this panel exists to remove.
    local I = GuildOS.CompanionImport
    local rescued = (I and I.Rescued) and I:Rescued(roster) or {}

    local s = {
        size = tonumber(roster.size) or 0,
        coming = 0, tanks = 0, healers = 0, dps = 0,
        declined = 0, tentative = 0,
        standby = {}, look = {},
    }

    for _, p in ipairs(list) do
        if p.invite or rescued[p.name] then
            s.coming = s.coming + 1
            if p.slot == "TANK" then
                s.tanks = s.tanks + 1
            elseif p.slot == "HEALER" then
                s.healers = s.healers + 1
            else
                s.dps = s.dps + 1
            end
        elseif p.why == "wait" then
            s.standby[#s.standby + 1] = p
        elseif p.why == "unknown" or p.why == "pending" then
            -- The only two anybody can act on from here. Somebody who said no has
            -- already said no; that is not a surprise and it does not earn a row.
            s.look[#s.look + 1] = p
        elseif p.why == "tentative" then
            s.tentative = s.tentative + 1
        else
            -- "no" and "refused" together. From this chair they are one fact: not
            -- coming, and not waiting on anything that can be done tonight.
            s.declined = s.declined + 1
        end
    end

    table.sort(s.standby, function(a, b) return (a.wait or 99) < (b.wait or 99) end)
    return s
end

----------------------------------------------------------------------
-- Can the reload-to-publish button run? Same shape as the import
-- predicates in Modules/CompanionImport.lua, and for the same reason:
-- the button and the action must not disagree about the rule.
----------------------------------------------------------------------
local function canPublishNow()
    local co = GuildOS.Companion
    if not (co and co:IsEnabled()) then return false, L["Turn publishing on first."] end
    if InCombatLockdown() then return false, L["Can't reload during combat."] end
    return true
end

----------------------------------------------------------------------
-- The Iniciar raide button (issue #400; specs/115 in guildos-web)
--
-- One stepper wherever it sits: the owner's prompt, the Now tab's next
-- raid and this tab. Its label is RaidStart:Next's and its click is
-- RaidStart:Click, so the three can never say different things. Next
-- reads the guild roster, so it is never asked from OnUpdate: on the
-- group, combat and roster events, after a click, and every STEP_TICK
-- seconds while one of them is on screen. A step that cannot run now
-- (invites awaiting their answer, combat, somebody else's group) leaves
-- the button greyed with the reason under it, never hidden.
----------------------------------------------------------------------
local STEP_TICK = 5   -- seconds between repaints while a button shows: an invite's minute runs out, people log in
local STEP_GAP  = 1   -- seconds: a burst of group events repaints once
local WEB_GROUP_GAP = 0.5   -- seconds: a burst of group events refreshes the Web tab once
local STEP_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GUILD_ROSTER_UPDATE" }

local steppers, stepTicker, stepEvents = {}, nil, nil

local function anyStepperShown()
    for _, s in ipairs(steppers) do
        if s.btn:IsVisible() then return true end
    end
    return false
end

-- Paints one button from its step: the label, on or off, and the line under it (why it is off, or who was passed
-- over for being offline). `cache` holds the steps read in this pass, by roster: two buttons on one raid read once.
local function paintStepper(s, cache)
    local RS, I = GuildOS.RaidStart, GuildOS.CompanionImport
    local roster = s.roster()
    local step = roster and cache[roster]
    if not step then
        step = RS and RS:Next(roster) or { kind = "blocked", label = L["Start raid"] }
        if roster then cache[roster] = step end
    end
    s.btn.label:SetText(step.label or L["Start raid"])
    -- Ready is a click only where the host gives it one (the prompt closes); elsewhere it is a state.
    if step.kind ~= "blocked" and (step.kind ~= "done" or s.done) then s.btn:Enable() else s.btn:Disable() end
    -- The host may know better what to say (the Web tab with nothing loaded: what to do about it).
    local note = s.note and s.note(roster)
    s.why:SetText(note or (step.kind == "blocked" and step.reason) or (I and I.OfflineLine(step.offline)) or "")
    if s.paint then s.paint(step) end
end

--- Repaints every Iniciar raide button on screen and, while one is, asks the server for a fresh guild roster
--- (RaidStart:AskGuildRoster, at most every 30 seconds). With none on screen the ticker stops.
function GuildOS:RefreshRaidSteppers()
    local cache, shown = {}, false
    for _, s in ipairs(steppers) do
        if s.btn:IsVisible() then
            shown = true
            paintStepper(s, cache)
        end
    end
    if shown and GuildOS.RaidStart then GuildOS.RaidStart:AskGuildRoster() end
    if not shown and stepTicker then
        stepTicker:Cancel()
        stepTicker = nil
    end
end

local function startStepTicker()
    if stepTicker then return end
    stepTicker = GuildOS.Compat.NewTicker(STEP_TICK, function() GuildOS:RefreshRaidSteppers() end)
end

-- The click: the step and its lines in chat (RaidStart:Click, which repaints every button); "Raid ready" does what
-- its host gave it to.
local function stepperClick(s)
    if not GuildOS.RaidStart then return end
    local result = GuildOS.RaidStart:Click(s.roster())
    if result.kind == "done" and s.done then s.done() end
end

--- An Iniciar raide button on `parent`. opts: roster (a function: the roster it acts on), done (a function: what a
--- click on "Raid ready" does; without it the button is off once the raid is ready), note (a function(roster): a line
--- to say under the button in place of the step's, or nil), paint (a function(step): the host's own lines, repainted
--- with it), width, height. Returns the button; the line under it is btn.why, for the host to place.
function UI:CreateRaidStepper(parent, opts)
    local btn = UI:CreateButton(parent, L["Start raid"], opts.width or 150, opts.height or BTN_H)
    local why = UI:CreateText(parent, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    why:SetJustifyH("LEFT")
    why:SetWordWrap(true)
    btn.why = why
    local s = { btn = btn, why = why, roster = opts.roster, done = opts.done, note = opts.note, paint = opts.paint }
    steppers[#steppers + 1] = s
    btn:SetScript("OnClick", function() stepperClick(s) end)
    btn:HookScript("OnShow", function()
        paintStepper(s, {})
        if GuildOS.RaidStart then GuildOS.RaidStart:AskGuildRoster() end
        startStepTicker()
    end)
    if not stepEvents then
        stepEvents = CreateFrame("Frame")
        for _, ev in ipairs(STEP_EVENTS) do GuildOS.Compat.RegisterEvent(stepEvents, ev) end
        stepEvents:SetScript("OnEvent", function()
            if anyStepperShown() then
                GuildOS:Coalesce("raidstepper", STEP_GAP, function() GuildOS:RefreshRaidSteppers() end)
            end
        end)
    end
    return btn
end

----------------------------------------------------------------------
-- The owner's prompt (issue #400): what RaidStart decided to ask, shown.
-- The raid's name, when it starts, how many are coming, the button, and
-- Later. Built the first time, as the login digest is (Modules/Digest.lua),
-- and at the digest's place: it takes the digest's turn at login, and in
-- the game it closes one still open (Digest:ShowOnLogin gives way to it).
----------------------------------------------------------------------
local PROMPT_W, PROMPT_H = 340, 168
local PROMPT_BTN_H = 26
local PROMPT_WHY_LINES = 2   -- the reason line's room between the button and Later
local MINUTE = 60

-- "Starts in 20 min", "Starts now", "Started 45 min ago", and how many are coming.
local function promptWhen(roster)
    local dt = (tonumber(roster.startsAt) or 0) - GetServerTime()
    local when
    if dt >= MINUTE then
        when = string.format(L["Starts in %d min"], math.ceil(dt / MINUTE))
    elseif dt > -MINUTE then
        when = L["Starts now"]
    else
        when = string.format(L["Started %d min ago"], math.floor(-dt / MINUTE))
    end
    return when .. " · " .. string.format(L["%d going"], #(roster.members or {}))
end

local prompt

local function buildPrompt()
    local f = CreateFrame("Frame", "GuildOSRaidPromptFrame", UIParent, "BackdropTemplate")
    f:SetSize(PROMPT_W, PROMPT_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)

    -- Put off (Later, or the close button), not done: the digest that gave way to it at login has its turn.
    -- Later asks again in a while (audit B18); the close button does not.
    local function putOff(later)
        f:Hide()
        if GuildOS.RaidStart then GuildOS.RaidStart:PromptDismissed(f.roster, later == true) end
    end
    -- A floating window (the mockup's .fw): the raid's name in Cinzel gold in its header, the round red close.
    local Kit = rawget(GuildOS, "Kit")
    local DY = 0
    if Kit then
        Kit:Dress(f, "", { onClose = function() putOff(false) end })
        f.title, f.close = f.titleText, f.closeBtn
        DY = Kit.HEADER_H - 30
        f:SetHeight(PROMPT_H + DY)
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(f) })
        f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.98)
        UI:StylePopup(f, { shadowSize = 16 })
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        f.title = UI:CreateTitle(f, "", 15)
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.title:SetPoint("RIGHT", f, "RIGHT", -36, 0)
        f.title:SetJustifyH("LEFT")
        f.title:SetWordWrap(false)
        f.close = UI:CreateCloseButton(f)
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function() putOff(false) end)
    end

    f.when = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
    f.when:SetPoint("TOPLEFT", 16, -(42 + DY))
    f.when:SetJustifyH("LEFT")

    -- The button on the raid this prompt is about, in its newest copy (a roster pasted since the inbox was read, with
    -- new groups or a moved start: CompanionImport:Freshest); "Raid ready" closes the prompt.
    local function raid()
        local I = GuildOS.CompanionImport
        return I and I:Freshest(f.roster) or f.roster
    end
    f.go = UI:SetButtonVariant(UI:CreateRaidStepper(f, {
        roster = raid,
        done = function() f:Hide() end,
        paint = function() if f.roster then f.when:SetText(promptWhen(raid())) end end,
        width = 200, height = PROMPT_BTN_H,
    }), "primary")
    f.go:SetPoint("TOPLEFT", 16, -(70 + DY))
    f.go.why:SetPoint("TOPLEFT", f.go, "BOTTOMLEFT", 0, -6)
    f.go.why:SetWidth(PROMPT_W - 32)
    -- Two lines fit above Later: a long list of who is offline is cut there, not drawn under the button.
    f.go.why:SetMaxLines(PROMPT_WHY_LINES)

    f.later = UI:CreateButton(f, L["Later"], 90, PROMPT_BTN_H)
    f.later:SetPoint("BOTTOMRIGHT", -16, 14)
    f.later:SetScript("OnClick", function() putOff(true) end)

    f:Hide()
    return f
end

--- The roster the prompt is up for, or nil when it is not on screen (RaidStart:Due holds a second raid's prompt back
--- while this one's step is not done).
function GuildOS:RaidPromptShowing()
    return prompt and prompt:IsShown() and prompt.roster or nil
end

--- The owner's prompt for `roster` (RaidStart:Prompt decides when): its name, when it starts, how many are coming,
--- the Iniciar raide button and Later. A second raid's prompt takes the place of the first once that one is done.
function GuildOS:ShowRaidPrompt(roster)
    if type(roster) ~= "table" then return end
    prompt = prompt or buildPrompt()
    local digest = GuildOS.Digest and GuildOS.Digest.frame
    if digest and digest:IsShown() then digest:Hide() end
    local title = roster.title
    if not title or title == "" then title = roster.instance or L["Raid"] end
    GuildOS:SetTitleText(prompt.title, GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(title) or title)
    prompt.roster = roster
    prompt.when:SetText(promptWhen(roster))
    if prompt:IsShown() then GuildOS:RefreshRaidSteppers() end
    prompt:Show()
    prompt:Raise()
    return prompt
end

function GuildOS:CreateWebPanel(parent, _win)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- A section title as every screen draws it (#371). A later one's rule stops where the content
    -- does, not at the panel's edge.
    local function sectionTitle(text, first)
        local fs = UI:CreateSectionTitle(panel, text, first)
        if fs.rule then fs.rule:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_INSET, 0) end
        return fs
    end

    ----------------------------------------------------------------
    -- PUBLISHING
    ----------------------------------------------------------------
    local pubHead = sectionTitle(L["PUBLISHING"], true)

    local stateDot = panel:CreateTexture(nil, "OVERLAY")
    stateDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    stateDot:SetSize(6, 6)

    local stateText = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    local toggleBtn = UI:CreateButton(panel, L["Turn on"], 90, BTN_H)
    -- /gos web: the string to paste into the companion, while it is on (#142).
    local pasteBtn = UI:CreateButton(panel, L["Show the paste text"], 170, BTN_H)
    pasteBtn:SetScript("OnClick", function() GuildOS:ShowWebString() end)

    local countText   = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    -- On the state's line, after "On": it says when that state last reached the disk (#371).
    local writtenText = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    writtenText:SetJustifyH("LEFT")
    -- The other half of the round trip, and the only line on this panel that is not
    -- about what the game did. The companion leaves it in the inbox after the site
    -- accepts an export.
    local ackText     = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(true)
    ackText:SetJustifyH("LEFT")
    ackText:SetWordWrap(true)   -- the no-ack lines say what to do, and run past one row

    -- Why a button is off: a hint in `textSoft`, not gold (#371).
    local publishBtn  = UI:CreateButton(panel, L["Publish now"], 120, BTN_H)
    local publishWhy  = UI:CreateText(panel, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    local publishNote = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    publishNote:SetWordWrap(true)
    publishNote:SetJustifyH("LEFT")
    publishWhy:SetJustifyH("LEFT")

    ----------------------------------------------------------------
    -- PLANNED RAID
    ----------------------------------------------------------------
    local raidHead  = sectionTitle(L["PLANNED RAID"])
    -- How many are coming follows the title as secondary text, not gold in the far corner (#371).
    local raidCount = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    local raidTitle = UI:CreateText(panel, "", 12, C.text.r, C.text.g, C.text.b)
    local raidWhen  = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    raidTitle:SetJustifyH("LEFT")
    raidTitle:SetWordWrap(false)
    raidWhen:SetJustifyH("LEFT")

    -- The composition, and the people who are not in it. Both are silent on a v1
    -- payload: an older site sends no `signups`, and inventing zeroes from that
    -- would report a raid nobody declined as one nobody wanted.
    local raidRoles = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    local raidOut   = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    raidRoles:SetJustifyH("LEFT")
    raidOut:SetJustifyH("LEFT")

    local bringBtn  = UI:CreateButton(panel, L["Bring roster"], 110, BTN_H)
    -- Iniciar raide (issue #400): invite, convert, invite the rest and arrange, one click a step, on the raid of the
    -- window, in place of the Invite and Groups buttons it walks through. The screen's one primary. Under it, why it
    -- is off, or who was passed over for being offline, in `textSoft` (#371).
    local startBtn  = UI:SetButtonVariant(UI:CreateRaidStepper(panel, {
        roster = function()
            local I = GuildOS.CompanionImport
            return I and I:ActiveRoster()
        end,
        -- The site's raids all another guild's: say whose (ForeignLine). With nothing loaded, what to do about it.
        note = function(roster)
            local I = GuildOS.CompanionImport
            -- Only with nothing to act on: a roster in hand (one pasted, another guild's included) has its own reason.
            local foreign = I and I:ForeignLine()
            if foreign and not roster then return foreign end
            if not roster then return L["Import a roster first."] end
        end,
        -- A repaint between two Refreshes moves the rows under the line; Refresh lays out once on its own.
        paint = function()
            if panel:IsShown() and panel.Relayout and not panel.refreshing then panel:Relayout() end
        end,
        width = 160,
    }), "primary")
    local raidWhy   = startBtn.why
    -- Out of the group whoever is not in the plan, after a confirmation naming them (issue #292).
    local trimBtn   = UI:CreateButton(panel, L["Fit to plan"], 100, BTN_H)
    -- The night's plan from the site, of the raid the button acts on: notes, tasks and loot rules (issue #296).
    local planBtn   = UI:CreateButton(panel, L["Raid plan"], 90, BTN_H)

    ----------------------------------------------------------------
    -- STANDBY / NEEDS A LOOK
    --
    -- Two fixed pools rather than frames created per refresh: this panel
    -- redraws every ten seconds while it is open, and a raid roster that
    -- allocates on a ticker is a garbage collector pause during a pull.
    ----------------------------------------------------------------
    local function makeList(headText)
        -- Zeroed, not nil: a resize can reach Relayout before the first Refresh has
        -- ever run, and the layout reads these to decide it can skip the section.
        local list = { head = sectionTitle(headText), rows = {}, shown = 0, rest = 0 }
        for i = 1, LIST_ROWS do
            local left  = UI:CreateText(panel, "", 10, C.text.r, C.text.g, C.text.b)
            local right = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
            left:SetJustifyH("LEFT");  left:SetWordWrap(false)
            right:SetJustifyH("LEFT"); right:SetWordWrap(false)
            list.rows[i] = { left = left, right = right }
        end
        list.more = UI:CreateText(panel, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        list.more:SetJustifyH("LEFT")
        return list
    end

    local standby = makeList(L["STANDBY"])
    local look    = makeList(L["NEEDS A LOOK"])
    for _, list in ipairs({ standby, look }) do
        list.head:Hide()
        list.head.rule:Hide()
        list.more:Hide()
        for _, row in ipairs(list.rows) do row.left:Hide(); row.right:Hide() end
    end

    ----------------------------------------------------------------
    -- FIRST TIME?
    ----------------------------------------------------------------
    local firstHead = sectionTitle(L["FIRST TIME?"])
    local step1 = UI:CreateText(panel, string.format(L["1. Open %s"], SITE),
        10, C.text.r, C.text.g, C.text.b)
    local step2 = UI:CreateText(panel, L["2. Download the companion and paste the token"],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    local step3 = UI:CreateText(panel, L["3. Log out of the game once"],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    for _, fs in ipairs({ step1, step2, step3 }) do
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    local copyBtn = UI:CreateButton(panel, L["Copy"], 70, 18)

    -- WoW cannot open a browser, so the address goes into a pre-selected
    -- read-only box for Ctrl+C. Same idiom as GuildOS:ShowExportPopup.
    -- The shared field (#371): its Escape and focus handlers are its own.
    local copyBox = UI:CreateInput(panel, 200, 20)
    copyBox:SetText(SITE)
    copyBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    -- Read-only: any edit snaps back to the full address, still selected. Hooked, as the field's own
    -- text handlers must stay.
    copyBox:HookScript("OnTextChanged", function(s)
        if s:GetText() ~= SITE then
            s:SetText(SITE)
            s:HighlightText()
        end
    end)
    copyBox:Hide()

    copyBtn:SetScript("OnClick", function()
        copyBox:Show()
        copyBox:SetText(SITE)
        copyBox:HighlightText()
        copyBox:SetFocus()
        GuildOS:Print(L["Address selected — press Ctrl+C"])
        panel:Relayout()
    end)

    ----------------------------------------------------------------
    -- Wiring
    ----------------------------------------------------------------
    toggleBtn:SetScript("OnClick", function()
        local co = GuildOS.Companion
        if not co then return end
        co:SetEnabled(not co:IsEnabled())
        panel:Refresh()
    end)

    publishBtn:SetScript("OnClick", function()
        -- Re-checked here rather than trusting the greyed state: combat can
        -- start between the last refresh and the click.
        if not canPublishNow() then return end
        ReloadUI()
    end)

    bringBtn:SetScript("OnClick", function()
        GuildOS:ShowImportPopup()
    end)

    planBtn:SetScript("OnClick", function() GuildOS.RaidPlan:Show() end)

    trimBtn:SetScript("OnClick", function()
        local I = GuildOS.CompanionImport
        if I then I:AskTrim() end
        panel:Refresh()
    end)

    ----------------------------------------------------------------
    -- Refresh: recompute every state, then lay out what is visible.
    ----------------------------------------------------------------
    -- These are UI:CreateButton buttons: their own disabled state already greys
    -- the label, and dimming the whole button on top of that made it vanish.
    local function setEnabled(btn, ok)
        if ok then
            btn:Enable()
        else
            btn:Disable()
        end
    end

    --- lines is an array of { leftText, rightText }. Everything past LIST_ROWS
    --- becomes one "+N on the site", because the site is where the rest of them
    --- can actually be dealt with.
    local function fillList(list, lines)
        local shown = math.min(#lines, LIST_ROWS)
        for i = 1, LIST_ROWS do
            local row = list.rows[i]
            if i <= shown then
                row.left:SetText(lines[i][1] or "")
                row.right:SetText(lines[i][2] or "")
            end
            row.left:SetShown(i <= shown)
            row.right:SetShown(i <= shown)
        end

        local rest = #lines - shown
        list.more:SetText(rest > 0 and string.format(L["+%d on the site"], rest) or "")
        list.more:SetShown(rest > 0)
        list.head:SetShown(#lines > 0)
        list.head.rule:SetShown(#lines > 0)

        -- Read by Relayout, so an empty list costs no height at all.
        list.shown = shown
        list.rest = rest
    end

    function panel:Refresh()
        local co = GuildOS.Companion
        local on = (co and co:IsEnabled()) and true or false
        self.publishing = on

        local dot = on and C.online or C.textDim
        stateDot:SetVertexColor(dot.r, dot.g, dot.b, 1)
        stateText:SetText(on and L["On"] or L["Off"])
        toggleBtn.label:SetText(on and L["Turn off"] or L["Turn on"])

        local I = GuildOS.CompanionImport

        if on then
            -- Build walks the whole guild, so it runs here and nowhere else.
            local _, count = co:Build()
            -- A retail region the site has no world for says so here (issue #182).
            countText:SetText(type(count) == "number"
                and string.format(L["%d members go out next time"], count) or co:Refused() or "")
            writtenText:SetText(string.format(L["Last written: %s"], writtenAgo()))

            -- The companion's side of the round trip, and the only place in the
            -- game that can tell somebody their companion has stopped working.
            --
            -- It is worth the three branches: this is the one warning that reaches
            -- a person whose companion is pointed at an address that no longer
            -- answers, because nothing here depends on that address.
            local ackAt, ackCount = nil, 0
            if I then ackAt, ackCount = I:Ack() end

            -- A companion that is silent or stale is a warning: `warn`, not gold (#371).
            local dim, warn = C.textDim, C.warn
            if not ackAt then
                -- No ack: a companion that wrote blocks without one has no guild link for this
                -- folder; an empty inbox is the one the addon package ships, not written over yet.
                local msg
                if I and I:InboxHasBlocks() then
                    msg = L["The companion is working, but none of its guild links sends this guild's raids here. Link the guild at %s"]
                else
                    msg = L["No word from the companion yet. If it is running, wait a few minutes; if not, download it at %s"]
                end
                ackText:SetText(string.format(msg, SITE))
                ackText:SetTextColor(warn.r, warn.g, warn.b)
            elseif (GetServerTime() or time()) - ackAt > ACK_STALE then
                ackText:SetText(string.format(L["The companion has sent nothing since %s"], stamp(ackAt)))
                ackText:SetTextColor(warn.r, warn.g, warn.b)
            else
                ackText:SetText(string.format(L["Site updated %s, %d members"], stamp(ackAt), ackCount))
                ackText:SetTextColor(dim.r, dim.g, dim.b)
            end

            -- Only an officer's client puts the site's raids on the guild calendar (UpsertWebRaid).
            local note = L["Writes and reloads the interface. The companion sends it on from your PC."]
            if not GuildOS:IsOfficer() then
                note = note .. "\n" .. L["Raids from the site go on the calendar from an officer's client. Your rank is above the guild's officer ranks, so here they only show in this tab."]
            end
            publishNote:SetText(note)
        else
            -- The guild's: a member's own pack goes out with the switch off, through their own companion.
            countText:SetText(L["The guild's data stays in the game while this is off."])
            writtenText:SetText("")
            ackText:SetText("")
            publishNote:SetText("")
        end
        ackText:SetShown(on)

        local pubOk, pubWhy = canPublishNow()
        setEnabled(publishBtn, pubOk)
        publishWhy:SetText(pubOk and "" or (pubWhy or ""))

        -- The raid the buttons below act on: the one of the window when there is one (issue #400).
        local roster = I and I:ActiveRoster()
        local sum
        if roster then
            local title = roster.title
            if not title or title == "" then title = roster.instance or "?" end
            raidTitle:SetText(title)
            local when = tonumber(roster.startsAt) or 0
            if when > 0 then
                raidWhen:SetText(string.format("%s · %s", GuildOS:LocalDate("%a %H:%M", when),
                    fmtCountdown(when - (GetServerTime() or time()))))
            else
                raidWhen:SetText("")
            end

            sum = summarise(roster)
            if sum then
                -- The denominator is the point. "18 signed up" does not answer the
                -- question being asked, which is whether anybody is missing.
                raidCount:SetText(string.format(L["%d of %d coming"], sum.coming, sum.size))
                raidRoles:SetText(string.format(L["%d tanks · %d healers · %d dps"],
                    sum.tanks, sum.healers, sum.dps))
                raidOut:SetText((sum.declined + sum.tentative) > 0
                    and string.format(L["%d declined · %d tentative"], sum.declined, sum.tentative)
                    or "")
            else
                raidCount:SetText(string.format(L["%d signed up"], #roster.members))
                raidRoles:SetText("")
                raidOut:SetText("")
            end
        else
            raidTitle:SetText(L["Nothing loaded."])
            raidWhen:SetText("")
            raidCount:SetText("")
            raidRoles:SetText("")
            raidOut:SetText("")
        end

        local standbyLines, lookLines = {}, {}
        if sum then
            for _, p in ipairs(sum.standby) do
                standbyLines[#standbyLines + 1] =
                    { string.format("%d  %s", p.wait or 0, p.name or "?"), className(p.class) }
            end
            for _, p in ipairs(sum.look) do
                lookLines[#lookLines + 1] = {
                    p.name or "?",
                    p.why == "pending" and L["waiting for your approval on the site"]
                        or L["the game has never seen this character"],
                }
            end
        end
        fillList(standby, standbyLines)
        fillList(look, lookLines)

        -- Default to refused. If the import module is missing the actions
        -- cannot run, and an enabled button that does nothing when clicked is
        -- the exact failure this panel exists to remove.
        local trimOk = I and I:CanTrim() or false
        setEnabled(bringBtn, on)
        setEnabled(trimBtn, trimOk and true or false)
        -- Iniciar raide paints its own label, gate and reason line, the prompt's and the Now tab's with it: one reason
        -- line, the first thing standing in the way (RaidStart:Next), not a wall of them. Laid out below, once.
        self.refreshing = true
        GuildOS:RefreshRaidSteppers()
        self.refreshing = nil

        -- Exposed so the layout tests can assert the contract this panel
        -- exists for: a button that is off has to say why, and one that is
        -- on must not be nagging about nothing.
        self.state = {
            publishing = on,
            reason     = raidWhy:GetText() or "",
            publishWhy = pubOk and "" or (pubWhy or ""),
            enabled    = {
                publish = pubOk and true or false,
                bring   = on,
                start   = startBtn:IsEnabled() and true or false,
            },
        }

        -- The toggle already answers "has this person set it up", so the
        -- first-run block needs no state of its own.
        self.showFirstRun = not on
        for _, r in ipairs({ firstHead, firstHead.rule, step1, step2, step3, copyBtn }) do
            r:SetShown(self.showFirstRun)
        end
        if not self.showFirstRun then copyBox:Hide() end

        self:Relayout()
    end

    ----------------------------------------------------------------
    -- Layout: one vertical stack; a hidden section costs no height.
    ----------------------------------------------------------------
    function panel:Relayout(w, _h)
        w = w or parent:GetWidth()
        if not w or w < 1 then return end
        local inner = math.max(120, w - INSET - RIGHT_INSET)
        local y = GAP

        local function place(region, dx, dy)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET + (dx or 0), -(y + (dy or 0)))
        end

        place(pubHead)
        y = y + TITLE_H

        -- One line says the state and when it was last written, and its two buttons follow it
        -- there instead of sitting in the far corner (#371). The texts take the width they need.
        place(stateDot, 2, 8)
        place(stateText, 14, 4)
        writtenText:ClearAllPoints()
        writtenText:SetPoint("LEFT", stateText, "RIGHT", GAP * 2, 0)
        toggleBtn:ClearAllPoints()
        toggleBtn:SetPoint("LEFT", writtenText, "RIGHT", GAP * 2, 0)
        pasteBtn:ClearAllPoints()
        pasteBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
        pasteBtn:SetShown(self.publishing and true or false)
        y = y + BTN_H + 4

        place(countText); countText:SetWidth(inner)
        y = y + ROW_H
        if ackText:IsShown() then
            place(ackText); ackText:SetWidth(inner)
            y = y + math.max(ROW_H, math.ceil(ackText:GetStringHeight() or 0) + 2)
        end
        y = y + GAP

        local on = self.publishing
        publishBtn:SetShown(on)
        publishWhy:SetShown(on)
        publishNote:SetShown(on)
        if on then
            publishBtn:ClearAllPoints()
            publishBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -y)
            place(publishWhy, 128, 6)
            publishWhy:SetWidth(math.max(60, inner - 128))
            y = y + BTN_H + 2
            place(publishNote); publishNote:SetWidth(inner)
            y = y + math.max(ROW_H * 2, math.ceil(publishNote:GetStringHeight() or 0) + 2)
        end

        y = y + SECTION
        place(raidHead)
        raidCount:ClearAllPoints()
        raidCount:SetPoint("LEFT", raidHead, "RIGHT", GAP, 0)
        y = y + TITLE_H
        place(raidTitle); raidTitle:SetWidth(inner)
        y = y + ROW_H + 2
        place(raidWhen); raidWhen:SetWidth(inner)
        y = y + ROW_H

        -- Both go quiet on a v1 payload rather than drawing an empty row.
        if raidRoles:GetText() ~= "" then
            place(raidRoles); raidRoles:SetWidth(inner)
            y = y + ROW_H
        end
        if raidOut:GetText() ~= "" then
            place(raidOut); raidOut:SetWidth(inner)
            y = y + ROW_H
        end
        y = y + GAP

        -- Iniciar raide on a row of its own: its label grows with the step ("Convert to raid (12 to invite)"), and
        -- its reason line under it. Then the roster's other three.
        startBtn:ClearAllPoints()
        startBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -y)
        y = y + BTN_H + 4
        place(raidWhy); raidWhy:SetWidth(inner)
        y = y + math.max(ROW_H, math.ceil(raidWhy:GetStringHeight() or 0) + 2) + 2
        bringBtn:ClearAllPoints()
        bringBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -y)
        trimBtn:ClearAllPoints()
        trimBtn:SetPoint("LEFT", bringBtn, "RIGHT", 6, 0)
        planBtn:ClearAllPoints()
        planBtn:SetPoint("LEFT", trimBtn, "RIGHT", 6, 0)
        y = y + BTN_H + 4

        -- The name column is fixed rather than measured: two columns that reflow per
        -- row read as a ragged mess, and a name long enough to reach the second
        -- column is a name the player chose to make everybody's problem.
        local NAME_W = math.min(120, math.floor(inner * 0.38))
        local function placeList(list)
            if list.shown == 0 and list.rest == 0 then return end
            y = y + SECTION
            place(list.head)
            y = y + TITLE_H
            for i = 1, list.shown do
                local row = list.rows[i]
                place(row.left); row.left:SetWidth(NAME_W)
                place(row.right, NAME_W + 8)
                row.right:SetWidth(math.max(40, inner - NAME_W - 8))
                y = y + ROW_H
            end
            if list.rest > 0 then
                place(list.more); list.more:SetWidth(inner)
                y = y + ROW_H
            end
        end
        placeList(standby)
        placeList(look)

        if self.showFirstRun then
            y = y + SECTION
            place(firstHead)
            y = y + TITLE_H
            -- The address and its Copy button on one line, side by side (#371).
            place(step1)
            copyBtn:ClearAllPoints()
            copyBtn:SetPoint("LEFT", step1, "RIGHT", GAP, 0)
            y = y + ROW_H + 4
            place(step2); step2:SetWidth(inner)
            y = y + ROW_H
            place(step3); step3:SetWidth(inner)
            y = y + ROW_H + 4
            if copyBox:IsShown() then
                place(copyBox); copyBox:SetWidth(inner)
                y = y + 20
            end
        end

        self.contentHeight = y + GAP
    end

    ----------------------------------------------------------------
    -- Live while shown: combat gates the publish button, group changes
    -- gate the raid buttons, and the countdown moves on its own.
    ----------------------------------------------------------------
    GuildOS.Compat.RegisterEvent(panel, "PLAYER_REGEN_DISABLED")
    GuildOS.Compat.RegisterEvent(panel, "PLAYER_REGEN_ENABLED")
    GuildOS.Compat.RegisterEvent(panel, "GROUP_ROSTER_UPDATE")
    -- Combat at once; the group in a burst (forty accepts, issue #400) as one Refresh every WEB_GROUP_GAP seconds.
    local function visibleRefresh()
        if panel:IsShown() then panel:Refresh() end
    end
    panel:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" then
            GuildOS:Coalesce("webpanel", WEB_GROUP_GAP, visibleRefresh)
        else
            visibleRefresh()
        end
    end)
    panel:SetScript("OnShow", function(self)
        self:Refresh()
        if self.__ticker then return end
        self.__ticker = C_Timer.NewTicker(10, function()
            if self:IsShown() then self:Refresh() end
        end)
    end)
    panel:SetScript("OnHide", function(self)
        if self.__ticker then self.__ticker:Cancel(); self.__ticker = nil end
    end)

    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    return panel
end
