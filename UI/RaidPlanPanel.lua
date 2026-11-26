----------------------------------------------------------------------
-- Guild OS - Raid Plan panel (issue #296)
--
-- The frames for Modules/RaidPlan.lua: the whole plan of the roster in hand (loot rules, then each
-- boss's tasks with mine marked, and its note), and the small window with my own task when I target
-- a boss out of combat. Built once, filled on Show: nothing here redraws on a ticker.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L
local Plan = GuildOS.RaidPlan

local W, H = 460, 440
local PAD = 12

local function popup(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    UI:StylePopup(f)   -- the popup's lineHi border
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- The shared title, in `text`: gold is for selection, not a heading (#371).
    f.title = UI:CreateTitle(f, title, 14)
    f.title:SetPoint("TOPLEFT", PAD, -10)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)
    tinsert(UISpecialFrames, name)
    return f
end

----------------------------------------------------------------------
-- The whole plan
----------------------------------------------------------------------
local panel

-- The plan reads as the mockup's raides-plano: a parchment sheet, the bosses in the title's red, my task on
-- a pale green band. The paper's shades of the wood's colours.
local function hex(h) return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 } end
local MINE_FILL, MINE_INK, BAD_INK = hex("d6ecd0"), hex("2f6e33"), hex("8f1b0b")

local function build()
    local f = popup("GuildOSRaidPlan", W, H, L["Raid plan"])
    -- The sheet: the parchment over the popup's dark, its title in the paper's red.
    if GuildOS.Style then
        local sheet = CreateFrame("Frame", nil, f)
        sheet:SetPoint("TOPLEFT", 3, -3)
        sheet:SetPoint("BOTTOMRIGHT", -3, 3)
        sheet:SetFrameLevel(f:GetFrameLevel())
        GuildOS.Style:Paint(sheet, "paper")
        f.title:SetTextColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
    end
    f.boxes = {}
    f.sub = UI:CreateText(f, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    f.sub:SetPoint("TOPLEFT", PAD, -28)
    -- The frame reaches the scroll gutter past the content's right edge, and the child (fixed: the
    -- popup is) is the content's width, so the "Say in raid" buttons stop clear of the bar (#371).
    f.scroll, f.child = UI:CreateScrollFrame(f, "GuildOSRaidPlanScroll")
    f.scroll:SetPoint("TOPLEFT", PAD, -46)
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD + UI.SCROLL_GUTTER, PAD)
    f.child:SetWidth(W - 2 * PAD)
    f.child.__paper = GuildOS.Style ~= nil or nil   -- on the sheet: its buttons are the paper's cream ones
    f.texts, f.buttons = {}, {}
    f.status = UI:CreateText(f, "", 10, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    f.status:SetPoint("BOTTOMLEFT", PAD, 2)
    return f
end

-- A text from the pool, laid at `y` in the content, full width; returns the y below it. `role`: a
-- heading takes the section title's font (#371).
local function line(f, i, y, text, size, color, role)
    local fs = f.texts[i]
    if not fs then
        fs = UI:CreateText(f.child, "", size)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        f.texts[i] = fs
    end
    GuildOS:ApplyFont(fs, size, role)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetWidth(f.child:GetWidth())
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, -y)
    GuildOS:SetTitleText(fs, text)   -- a heading is an officer's text: Cinzel only when it is Latin
    fs:Show()
    return y + (fs:GetStringHeight() or 12) + 4
end

local function sayButton(f, i, y, boss)
    local b = f.buttons[i]
    if not b then
        b = UI:CreateButton(f.child, L["Say in raid"], 96, 18)
        f.buttons[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", 0, -y + 2)
    b:SetScript("OnClick", function()
        local said, err = Plan:Announce(boss)
        f.status:SetText(err or string.format(L["Said the note for %s in raid chat."], boss))
        -- Status: said is `ok`, not said a `warn` (gold is no status colour, #371).
        if said and said > 0 then f.status:SetTextColor(MINE_INK.r, MINE_INK.g, MINE_INK.b)
        else f.status:SetTextColor(BAD_INK.r, BAD_INK.g, BAD_INK.b) end
    end)
    b:Show()
end

function Plan:Show()
    panel = panel or build()
    local f = panel
    for _, fs in ipairs(f.texts) do fs:Hide() end
    for _, b in ipairs(f.buttons) do b:Hide() end
    for _, t in ipairs(f.boxes) do t:Hide() end
    f.status:SetText("")
    local plan, roster = self:Current()
    f.sub:SetText(roster and roster.title or "")
    local y, n, nb, nbox = 0, 0, 0, 0
    -- The wood's colours as the paper prints them.
    local INK = { [C.text] = C.paperInk, [C.silver] = C.paperSoft, [C.red] = BAD_INK, [C.green] = MINE_INK }
    local function add(text, size, color, role)
        n = n + 1
        y = line(f, n, y, text, size, INK[color] or color, role)
    end
    -- A heading of the plan (the loot rules, a boss): the section title's font, in the paper's red.
    local function heading(text)
        add(text, 13, C.paperTitle, "sectionTitle")
    end
    -- My task on its pale green band, in the reading face.
    local function mineBand(text)
        nbox = nbox + 1
        local box = f.boxes[nbox]
        if not box then
            box = f.child:CreateTexture(nil, "BACKGROUND")
            box:SetTexture("Interface\\Buttons\\WHITE8x8")
            f.boxes[nbox] = box
        end
        local top = y
        y = y + 6
        n = n + 1
        local fs = f.texts[n] or UI:CreateText(f.child, "", 13)
        f.texts[n] = fs
        GuildOS:ApplyFont(fs, 13, "reading")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
        fs:SetWidth(f.child:GetWidth() - 20)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 10, -y)
        fs:SetText(text)
        fs:Show()
        y = y + (fs:GetStringHeight() or 14) + 8
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 0, -top)
        box:SetPoint("TOPRIGHT", 0, -top)
        box:SetHeight(y - top)
        box:SetVertexColor(MINE_FILL.r, MINE_FILL.g, MINE_FILL.b, 1)
        box:Show()
        y = y + 4
    end
    -- The rule the raid plays by, or why this client does not play by it (the site's #516).
    local ruleLine, ruleWarning = self:LootRuleLine()
    if ruleLine then
        add(ruleLine, 12, ruleWarning and C.red or C.text)
        y = y + 4
    end
    if not plan then
        add(L["No plan for this raid yet: it comes from guildos.me with the roster."], 11, C.silver)
    else
        if plan.loot then
            heading(L["Loot rules"] .. (plan.loot.system and (": " .. (Plan.LOOT[plan.loot.system] or plan.loot.system)) or ""))
            if plan.loot.rules then add(plan.loot.rules, 11, C.text) end
            y = y + 6
        end
        local leader = self:CanAnnounce()
        for _, boss in ipairs(self:Bosses()) do
            if leader and self:NoteFor(boss) then
                nb = nb + 1
                sayButton(f, nb, y, boss)
            end
            heading(boss)
            -- Mine says so in words and in `ok`; no marker in front of it (#371).
            for _, a in ipairs(self:TasksFor(boss)) do
                if self:IsMine(a) then
                    mineBand(L["Your task"] .. ": " .. self:TaskLine(a))
                else
                    add(a.name .. ": " .. self:TaskLine(a), 11, C.text)
                end
            end
            local note = self:NoteFor(boss)
            if note then add(note, 10, C.silver) end
            y = y + 6
        end
    end
    f.child:SetHeight(math.max(1, y))
    f:Show()
end

----------------------------------------------------------------------
-- My task, when I target a boss of the plan out of combat
----------------------------------------------------------------------
local task

function Plan:ShowTask(boss)
    if not task then
        task = popup("GuildOSRaidPlanTask", 320, 150, "")
        task:ClearAllPoints()
        task:SetPoint("TOP", 0, -140)
        task.body = UI:CreateText(task, "", 11, C.text.r, C.text.g, C.text.b)
        task.body:SetPoint("TOPLEFT", PAD, -32)
        task.body:SetWidth(320 - 2 * PAD)
        task.body:SetJustifyH("LEFT")
        task.body:SetWordWrap(true)
        task.say = UI:CreateButton(task, L["Say in raid"], 96, 20)
        task.say:SetPoint("BOTTOMLEFT", PAD, 10)
        task.all = UI:CreateButton(task, L["Raid plan"], 96, 20)
        task.all:SetPoint("BOTTOMRIGHT", -PAD, 10)
        task.all:SetScript("OnClick", function() task:Hide(); Plan:Show() end)
    end
    GuildOS:SetTitleText(task.title, boss)
    local lines = {}
    for _, a in ipairs(self:MyTasks(boss)) do lines[#lines + 1] = L["Your task"] .. ": " .. self:TaskLine(a) end
    task.body:SetText(table.concat(lines, "\n"))
    task:SetHeight(math.max(110, (task.body:GetStringHeight() or 12) + 80))
    task.say:SetShown(self:CanAnnounce() and self:NoteFor(boss) ~= nil)
    task.say:SetScript("OnClick", function()
        local _, err = Plan:Announce(boss)
        if err then GuildOS:Print(err) end
    end)
    task:Show()
end
