----------------------------------------------------------------------
-- Guild OS - Hub
-- The front door: a 430px card with a feature rail on the left and a
-- live column on the right. The right column answers "what is happening
-- in the guild" and "what needs me", and every line in it clicks through
-- to the window that owns the answer, so the hub is a shortcut to the
-- action rather than a menu that only opens other menus.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local Hub = {}
UI.Hub = Hub

local WIDTH      = 430
local RAIL_W     = 150      -- left feature list
local SIDE_W     = WIDTH - RAIL_W
local TITLE_H    = 24
local SUMMARY_H  = 20       -- guild name . members . online, plus the chevron
local ROW_H      = 22
local FOOT_H     = 22
local BLOCK_HEAD = 16       -- section caption height in the right column
local BLOCK_ROW  = 14       -- one line inside a section
local BLOCK_GAP  = 6        -- space between two sections
local MAX_ONLINE = 5

local function cfg()
    local h = BRutus:GetSetting("hub")
    if type(h) ~= "table" then
        h = { collapsed = false, pulse = true }
        BRutus:SetSetting("hub", h)
    end
    return h
end

local function saveHubPos(f)
    local point, _, relPoint, x, y = f:GetPoint()
    local c = cfg()
    c.point, c.relPoint = point, relPoint or point
    c.x, c.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

-- Same shape as the dashboard's countdown (UI/Dashboard.lua:29), kept
-- local so the hub does not depend on the dashboard being built.
local function fmtCountdown(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format(L["in %dd %dh"], d, h) end
    if h > 0 then return string.format(L["in %dh %dm"], h, m) end
    return string.format(L["in %dm"], math.max(1, m))
end

local function myKey()
    return BRutus:GetPlayerKey(UnitName("player"))
end

function Hub:Create()
    if self.frame then return self.frame end
    local c = cfg()

    local f = UI:CreatePanel(UIParent, "GuildOSHub")
    f:SetWidth(WIDTH)
    f:SetHeight(TITLE_H + SUMMARY_H + FOOT_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    UI:StylePopup(f)
    f:ClearAllPoints()
    if c.point then
        f:SetPoint(c.point, UIParent, c.relPoint or c.point, c.x or 0, c.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -320, 120)
    end
    f:SetScale(BRutus:GetSetting("uiScale") or 1)
    self.frame = f

    -- Title bar: drag only. It is mouse-enabled across the full width, so
    -- anything clickable on it has to go through UI:TitleBarButton or the
    -- bar eats the click. Collapse used to live here as an OnClick, which
    -- is precisely what killed the three buttons below; the chevron on the
    -- summary line owns it now.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); saveHubPos(f) end)
    f.bar = bar

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = UI:CreateHeaderText(bar, "GUILD OS", 11)
    title:SetPoint("LEFT", 8, 0)

    local close = UI:TitleBarButton(bar, "close")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local gear = UI:TitleBarButton(bar, "text", "|TInterface\\Icons\\INV_Misc_Gear_01:12|t", 20, 18)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetScript("OnClick", function() UI:OpenWindow("settings") end)
    UI:AddTooltip(gear, L["Settings"])

    local expand = UI:TitleBarButton(bar, "text", "[ ]", 20, 18)
    expand:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    expand:SetScript("OnClick", function()
        if BRutus.ToggleExpanded then BRutus:ToggleExpanded() end
    end)
    UI:AddTooltip(expand, L["Expanded mode"])

    -- Summary line: guild identity plus the two numbers worth seeing
    -- without opening anything. Doubles as the collapsed-state content.
    local summary = CreateFrame("Frame", nil, f)
    summary:SetPoint("TOPLEFT", 0, -TITLE_H)
    summary:SetPoint("TOPRIGHT", 0, -TITLE_H)
    summary:SetHeight(SUMMARY_H)
    f.summary = summary

    f.summaryText = UI:CreateText(summary, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.summaryText:SetPoint("LEFT", 10, 0)
    f.summaryText:SetPoint("RIGHT", summary, "RIGHT", -28, 0)
    f.summaryText:SetJustifyH("LEFT")
    f.summaryText:SetWordWrap(false)

    local chevron = UI:CreateButton(summary, "v", 18, 16)
    chevron:SetPoint("RIGHT", -6, 0)
    chevron:SetFrameLevel(summary:GetFrameLevel() + 5)
    chevron:SetScript("OnClick", function()
        cfg().collapsed = not cfg().collapsed
        Hub:Refresh()
    end)
    UI:AddTooltip(chevron, L["Collapse"])
    f.chevron = chevron

    -- Left rail: one row per enabled feature.
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", 0, -(TITLE_H + SUMMARY_H))
    rail:SetWidth(RAIL_W)
    f.rail = rail
    f.rows = {}

    local railDiv = rail:CreateTexture(nil, "ARTWORK")
    railDiv:SetTexture("Interface\\Buttons\\WHITE8x8")
    railDiv:SetWidth(1)
    railDiv:SetPoint("TOPRIGHT", 0, 0)
    railDiv:SetPoint("BOTTOMRIGHT", 0, 0)
    railDiv:SetVertexColor(C.separator.r, C.separator.g, C.separator.b, C.separator.a)

    -- Right column: live blocks, drawn from a pooled line list.
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    side:SetWidth(SIDE_W)
    f.side = side
    f.sideLines = {}

    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetHeight(FOOT_H)

    local more = UI:CreateButton(f.footer, L["... more"], 70, 18)
    more:SetPoint("LEFT", 8, 0)
    more:SetScript("OnClick", function() Hub:ToggleMorePage() end)

    local closeAll = UI:CreateButton(f.footer, L["Close all"], 70, 18)
    closeAll:SetPoint("RIGHT", -8, 0)
    closeAll:SetScript("OnClick", function() UI:CloseAllWindows() end)

    -- The online list goes stale fast. Tick only while the card is up: a
    -- hidden hub must cost nothing.
    f:SetScript("OnShow", function(self)
        if self.__ticker then return end
        self.__ticker = C_Timer.NewTicker(10, function() Hub:Refresh() end)
    end)
    f:SetScript("OnHide", function(self)
        if self.__ticker then self.__ticker:Cancel(); self.__ticker = nil end
    end)
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(self) if self:IsShown() then Hub:Refresh() end end)

    table.insert(UISpecialFrames, "GuildOSHub")
    return f
end

----------------------------------------------------------------------
-- One rail row: dot (window open) + icon + label + optional badge.
----------------------------------------------------------------------
local function acquireRow(f, index)
    local row = f.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, f.rail, "BackdropTemplate")
    row:SetSize(RAIL_W - 12, ROW_H)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0)

    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("LEFT", 2, 0)
    row.dot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
    row.label:SetPoint("LEFT", 30, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.badge = UI:CreateText(row, "", 10, C.gold.r, C.gold.g, C.gold.b)
    row.badge:SetPoint("RIGHT", -4, 0)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)

    f.rows[index] = row
    return row
end

----------------------------------------------------------------------
-- One line in the right column. Pooled the same way the rail rows are:
-- Refresh only ever repositions and retexts, it never builds frames.
----------------------------------------------------------------------
local function acquireLine(f, index)
    local line = f.sideLines[index]
    if line then return line end

    line = CreateFrame("Button", nil, f.side, "BackdropTemplate")
    line:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    line:SetBackdropColor(0, 0, 0, 0)

    line.left = UI:CreateText(line, "", 10, C.text.r, C.text.g, C.text.b)
    line.left:SetPoint("LEFT", 0, 0)
    line.left:SetJustifyH("LEFT")
    line.left:SetWordWrap(false)

    line.right = UI:CreateText(line, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    line.right:SetPoint("RIGHT", 0, 0)
    line.right:SetJustifyH("RIGHT")

    line:SetScript("OnEnter", function(self)
        if self.__click then
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        end
    end)
    line:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
    line:SetScript("OnClick", function(self) if self.__click then self.__click() end end)

    f.sideLines[index] = line
    return line
end

----------------------------------------------------------------------
-- The right column's content, as flat description tables. Keeping the
-- data separate from the frames means Refresh only positions pooled
-- lines, and each block can be reasoned about on its own.
----------------------------------------------------------------------
function Hub:OnlineBlock()
    local list, total = {}, 0
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, class, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            total = total + 1
            if #list < MAX_ONLINE then
                local short = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$")
                list[#list + 1] = {
                    name      = short,
                    key       = BRutus:GetPlayerKey(short, realm),
                    level     = level or 0,
                    class     = class or "",
                    classFile = classFile,
                }
            end
        end
    end
    return list, total
end

-- Officer-only work queue. Every entry knows where it is dealt with, so
-- the line is a shortcut and not just a number.
function Hub:AlertBlock()
    local out = {}
    if not BRutus:IsOfficer() then return out end

    local gm = BRutus.GuildManager
    if gm and gm.GetInactiveMembers then
        local days = gm.DEFAULT_INACTIVE_DAYS or 30
        local n = #gm:GetInactiveMembers(days)
        if n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d inactive over %dd"], n, days),
                go   = function() UI:OpenWindow("management", "inactive") end,
            }
        end
    end

    local tt = BRutus.TrialTracker
    if tt and tt.GetActiveTrials and tt.GetDaysRemaining then
        local n = 0
        for _, t in ipairs(tt:GetActiveTrials()) do
            local left = tt:GetDaysRemaining(t.key)
            if left ~= nil and left <= 1 then n = n + 1 end
        end
        if n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d trials expiring"], n),
                go   = function() UI:OpenWindow("trials") end,
            }
        end
    end

    if gm and gm.GetSuggestions then
        local s = gm:GetSuggestions()
        local n = #(s.trialsReady or {}) + #(s.promoteCandidates or {})
        if n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d pending suggestions"], n),
                go   = function() UI:OpenWindow("management", "suggest") end,
            }
        end
    end

    local rs = BRutus.RecruitScanner
    if rs and rs.GetInbox then
        local n = 0
        for _ in pairs(rs:GetInbox()) do n = n + 1 end
        if n > 0 then
            out[#out + 1] = {
                text = string.format(L["%d applicants waiting"], n),
                go   = function() UI:OpenWindow("recruitment") end,
            }
        end
    end
    return out
end

-- What the hub is worth to a member who is not an officer.
function Hub:YouBlock()
    local bits, go = {}, nil
    local me = myKey()

    local pts = BRutus.Points
    if pts and pts.Get and BRutus:IsFeatureEnabled("dkp") then
        local n = pts:Get(me)
        if n then
            bits[#bits + 1] = string.format("%d %s", n, L["DKP"])
            go = go or function() UI:OpenWindow("dkp") end
        end
    end

    local rt = BRutus.RaidTracker
    if rt and rt.GetAttendancePercent then
        local pct = rt:GetAttendancePercent(me)
        if pct and pct > 0 then
            bits[#bits + 1] = string.format("%s %d%%", L["Attendance"], pct)
            go = go or function() UI:OpenWindow("raids") end
        end
    end

    local wl = BRutus.Wishlist
    if wl and wl.GetMyList then
        local n = #wl:GetMyList()
        if n > 0 then
            bits[#bits + 1] = string.format(L["%d on wishlist"], n)
            go = go or function() UI:OpenWindow("wishlist") end
        end
    end

    return table.concat(bits, " . "), go
end

----------------------------------------------------------------------
-- Rebuild the card. Cheap enough to run on every window open/close and
-- on the 10s ticker: it repositions pooled frames, it never creates any.
----------------------------------------------------------------------
function Hub:Refresh()
    local f = self.frame
    if not f then return end
    local c = cfg()

    local online, onlineTotal = self:OnlineBlock()
    local memberCount = GetNumGuildMembers() or 0
    f.chevron.label:SetText(c.collapsed and ">" or "v")

    if c.collapsed then
        -- Collapsed still says something: the point of the card is the
        -- numbers, so a blank bar would be a worse version of closing it.
        local bits = { string.format(L["%d online of %d"], onlineTotal, memberCount) }
        local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
        if e then
            bits[#bits + 1] = string.format("%s %s", e.title or "?",
                fmtCountdown((e.when or 0) - GetServerTime()))
        end
        local alerts = self:AlertBlock()
        if #alerts > 0 then
            bits[#bits + 1] = string.format("|cffFFD700%d !|r", #alerts)
        end
        f.summaryText:SetText(table.concat(bits, " . "))

        for _, row in pairs(f.rows) do row:Hide() end
        for _, line in pairs(f.sideLines) do line:Hide() end
        f.rail:Hide()
        f.side:Hide()
        f.footer:Hide()
        f:SetHeight(TITLE_H + SUMMARY_H)
        return
    end

    f.summaryText:SetText(string.format("%s . %d %s . %d online",
        GetGuildInfo("player") or "Guild OS", memberCount, L["members"], onlineTotal))
    f.rail:Show()
    f.side:Show()

    ----------------------------------------------------------------
    -- Left rail
    ----------------------------------------------------------------
    local defs = self.morePage and self:MoreEntries() or UI:VisibleFeatures("hub")
    local railY, shown = 4, 0
    for i, def in ipairs(defs) do
        local row = acquireRow(f, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.rail, "TOPLEFT", 6, -railY)
        row:SetWidth(RAIL_W - 12)
        row.label:SetText(def.label)
        if def.icon then row.icon:SetTexture(def.icon) else row.icon:SetTexture(nil) end
        row.dot:SetShown(UI:IsWindowOpen(def.id))
        local n = def.badge and def.badge() or 0
        row.badge:SetText((n and n > 0) and tostring(n) or "")
        row:SetScript("OnClick", function()
            if def.run then def.run()
            elseif def.sub then UI:OpenWindow(def.id, def.sub)
            else UI:ToggleWindow(def.id) end
        end)
        row:Show()
        railY = railY + ROW_H
        shown = i
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end

    ----------------------------------------------------------------
    -- Right column
    ----------------------------------------------------------------
    local sideY, used = 4, 0
    local function emit(kind, text, rightText, click, colour)
        used = used + 1
        local line = acquireLine(f, used)
        local h = (kind == "head") and BLOCK_HEAD or BLOCK_ROW
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", f.side, "TOPLEFT", 10, -sideY)
        line:SetPoint("TOPRIGHT", f.side, "TOPRIGHT", -8, -sideY)
        line:SetHeight(h)
        local font = line.left:GetFont()
        if kind == "head" then
            line.left:SetFont(font, 9, "OUTLINE")
            line.left:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            line.left:SetFont(font, 10, "OUTLINE")
            local col = colour or C.text
            line.left:SetTextColor(col.r, col.g, col.b)
        end
        line.left:SetText(text or "")
        line.right:SetText(rightText or "")
        line.__click = click
        line:Show()
        sideY = sideY + h
    end

    -- Online now
    emit("head", L["ONLINE NOW"], tostring(onlineTotal))
    if #online == 0 then
        emit("dim", L["Only you online"], nil, nil, C.textDim)
    else
        for _, m in ipairs(online) do
            local col = (m.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classFile]) or C.text
            emit("line", m.name, string.format("%d  %s", m.level, m.class), function()
                local data = BRutus.db and BRutus.db.members and BRutus.db.members[m.key]
                if data then
                    BRutus:ShowMemberDetail(data)
                else
                    UI:OpenWindow("roster")
                end
            end, col)
        end
        if onlineTotal > #online then
            emit("line", string.format(L["+%d more"], onlineTotal - #online), nil,
                function() UI:OpenWindow("roster") end, C.textDim)
        end
    end
    sideY = sideY + BLOCK_GAP

    -- Next event
    if BRutus:IsFeatureEnabled("guild") then
        emit("head", L["NEXT EVENT"])
        local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
        if e then
            local goCal = function() UI:OpenWindow("guild", "calendar") end
            emit("line", e.title or "?", nil, goCal)
            emit("line", string.format("%s . %s",
                date("%a %H:%M", e.when), fmtCountdown((e.when or 0) - GetServerTime())),
                nil, goCal, C.textDim)
        else
            emit("dim", L["No upcoming events scheduled."], nil, nil, C.textDim)
        end
        sideY = sideY + BLOCK_GAP
    end

    -- Needs you (officer only; the block and its caption go together, so a
    -- member never sees an empty officer section)
    if BRutus:IsOfficer() then
        local alerts = self:AlertBlock()
        emit("head", L["NEEDS YOU"], #alerts > 0 and tostring(#alerts) or nil)
        if #alerts == 0 then
            emit("dim", L["All caught up"], nil, nil, C.online)
        else
            for _, a in ipairs(alerts) do
                emit("line", "> " .. a.text, nil, a.go)
            end
        end
        sideY = sideY + BLOCK_GAP
    end

    -- You
    local you, youGo = self:YouBlock()
    if you ~= "" then
        emit("head", L["YOU"])
        emit("line", you, nil, youGo, C.textDim)
    end

    for i = used + 1, #f.sideLines do f.sideLines[i]:Hide() end

    local bodyH = math.max(railY, sideY) + 6
    f.rail:SetHeight(bodyH)
    f.side:SetHeight(bodyH)

    local y = TITLE_H + SUMMARY_H + bodyH
    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", 0, -(y + 2))
    f.footer:SetPoint("TOPRIGHT", 0, -(y + 2))
    f.footer:Show()
    f:SetWidth(WIDTH)
    f:SetHeight(y + 2 + FOOT_H)
end

----------------------------------------------------------------------
-- Second page: loose tools and sub-tab deep links, shown in the same
-- card so "more" never costs another window.
----------------------------------------------------------------------
function Hub:MoreEntries()
    local out = {}
    local function add(id, label, sub, fn)
        out[#out + 1] = { id = id, label = label, sub = sub, badge = nil, run = fn }
    end
    add("roster", L["Search"], nil)
    out[#out].run = function() if BRutus.Search then BRutus.Search:Show() end end
    if BRutus:IsFeatureEnabled("raids") then
        add("raids", L["Raids"] .. " > " .. L["Audit"], "audit")
        add("raids", L["Raids"] .. " > " .. L["Raid Tools"], "raidtools")
    end
    if BRutus:IsFeatureEnabled("guild") then
        add("guild", L["Guild"] .. " > " .. L["Calendar"], "calendar")
    end
    return out
end

function Hub:ToggleMorePage()
    self.morePage = not self.morePage
    self:Refresh()
end

function Hub:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
    else
        self.morePage = false
        self:Refresh()
        f:Show()
    end
end
