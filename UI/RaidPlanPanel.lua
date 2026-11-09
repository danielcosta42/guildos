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
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = UI:CreateText(f, title, 13, C.gold.r, C.gold.g, C.gold.b)
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

local function build()
    local f = popup("GuildOSRaidPlan", W, H, L["Raid plan"])
    f.sub = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.sub:SetPoint("TOPLEFT", PAD, -28)
    f.scroll, f.child = UI:CreateScrollFrame(f, "GuildOSRaidPlanScroll")
    f.scroll:SetPoint("TOPLEFT", PAD, -46)
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD - 18, PAD)
    f.child:SetWidth(W - 2 * PAD - 22)
    f.texts, f.buttons = {}, {}
    f.status = UI:CreateText(f, "", 10, C.gold.r, C.gold.g, C.gold.b)
    f.status:SetPoint("BOTTOMLEFT", PAD, 2)
    return f
end

-- A text from the pool, laid at `y` in the content, full width; returns the y below it.
local function line(f, i, y, text, size, color)
    local fs = f.texts[i]
    if not fs then
        fs = UI:CreateText(f.child, "", size)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        f.texts[i] = fs
    end
    GuildOS:ApplyFont(fs, size)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetWidth(f.child:GetWidth())
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, -y)
    fs:SetText(text)
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
        if said and said > 0 then f.status:SetTextColor(C.green.r, C.green.g, C.green.b)
        else f.status:SetTextColor(C.gold.r, C.gold.g, C.gold.b) end
    end)
    b:Show()
end

function Plan:Show()
    panel = panel or build()
    local f = panel
    for _, fs in ipairs(f.texts) do fs:Hide() end
    for _, b in ipairs(f.buttons) do b:Hide() end
    f.status:SetText("")
    local plan, roster = self:Current()
    f.sub:SetText(roster and roster.title or "")
    local y, n, nb = 0, 0, 0
    local function add(text, size, color)
        n = n + 1
        y = line(f, n, y, text, size, color)
    end
    if not plan then
        add(L["No plan for this raid yet: it comes from guildos.me with the roster."], 11, C.silver)
    else
        if plan.loot then
            add(L["Loot rules"] .. (plan.loot.system and (": " .. (Plan.LOOT[plan.loot.system] or plan.loot.system)) or ""), 12, C.gold)
            if plan.loot.rules then add(plan.loot.rules, 11, C.white) end
            y = y + 6
        end
        local leader = self:CanAnnounce()
        for _, boss in ipairs(self:Bosses()) do
            if leader and self:NoteFor(boss) then
                nb = nb + 1
                sayButton(f, nb, y, boss)
            end
            add(boss, 12, C.gold)
            for _, a in ipairs(self:TasksFor(boss)) do
                local mine = self:IsMine(a)
                add((mine and ("> " .. L["Your task"] .. ": ") or (a.name .. ": ")) .. self:TaskLine(a), 11, mine and C.green or C.white)
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
        task.body = UI:CreateText(task, "", 11, C.white.r, C.white.g, C.white.b)
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
    task.title:SetText(boss)
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
