----------------------------------------------------------------------
-- Guild OS - Guild Analytics
-- Composition distributions (class / level / rank / zone) as pure
-- aggregation over the guild roster, shown as bars in a /gos analytics window.
----------------------------------------------------------------------
local GuildAnalytics = {}
BRutus.GuildAnalytics = GuildAnalytics

GuildAnalytics.DIMENSIONS = { "class", "level", "rank", "zone" }

function GuildAnalytics:Initialize()
    self:_RegisterTests()
end

function GuildAnalytics:_LevelBracket(level)
    level = level or 0
    if level >= 70 then return "70" end
    local lo = math.floor(level / 10) * 10
    if lo == 0 then return "1-9" end
    return lo .. "-" .. (lo + 9)
end

function GuildAnalytics:BuildRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { class = classFile, level = level, rank = rank, zone = zone, online = online }
        end
    end
    return roster
end

function GuildAnalytics:Distribution(dim, onlineOnly, roster)
    roster = roster or self:BuildRoster()
    local counts, order, total = {}, {}, 0
    for _, m in ipairs(roster) do
        if (not onlineOnly) or m.online then
            local key, colorKey
            if dim == "class" then key = m.class or "?"; colorKey = m.class
            elseif dim == "level" then key = self:_LevelBracket(m.level)
            elseif dim == "rank" then key = m.rank or "?"
            elseif dim == "zone" then key = (m.zone and m.zone ~= "" and m.zone) or "?"
            else key = "?" end
            if not counts[key] then counts[key] = { count = 0, colorKey = colorKey }; order[#order + 1] = key end
            counts[key].count = counts[key].count + 1
            total = total + 1
        end
    end
    local out = {}
    for _, k in ipairs(order) do
        out[#out + 1] = { label = k, count = counts[k].count, colorKey = counts[k].colorKey }
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.label) < tostring(b.label)
    end)
    for _, e in ipairs(out) do e.pct = total > 0 and (e.count / total * 100) or 0 end
    return out, total
end

-- (Note: for dim=="class", label is the class file token; the UI localizes via
-- LOCALIZED_CLASS_NAMES_MALE and colors via RAID_CLASS_COLORS. Keeping the raw
-- token here keeps Distribution pure and testable.)

----------------------------------------------------------------------
-- UI (self-contained popup — mirrors Modules/Bulletin.lua:Show())
----------------------------------------------------------------------
local BAR_MAX     = 200  -- max pixel width of a fully-filled (100%) bar
local LABEL_WIDTH = 110  -- left column width for the dimension label
local ROW_HEIGHT  = 22

function GuildAnalytics:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors
    local L = BRutus.L

    self._dim = self._dim or "class"
    if self._onlineOnly == nil then self._onlineOnly = false end

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSAnalyticsFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 420)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Guild Analytics"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        -- Dimension selector: Class / Levels / Ranks / Zones
        local tabDefs = {
            { dim = "class", label = L["Class"] },
            { dim = "level", label = L["Levels"] },
            { dim = "rank",  label = L["Ranks"] },
            { dim = "zone",  label = L["Zones"] },
        }
        local tabs = {}
        local tabX = 16
        for _, def in ipairs(tabDefs) do
            local tab = UI:CreateTab(f, def.label, 100)
            tab:SetPoint("TOPLEFT", tabX, -42)
            tab:SetScript("OnClick", function()
                self._dim = def.dim
                if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
            end)
            tabs[def.dim] = tab
            tabX = tabX + 106
        end
        f.tabs = tabs

        -- Online-only toggle
        local onlineCB = UI:CreateCheckbox(f, L["Online only"], 18)
        onlineCB:SetPoint("TOPLEFT", 16, -78)
        onlineCB.checkbox:SetChecked(self._onlineOnly)
        onlineCB.checkbox.onChanged = function(_, checked)
            self._onlineOnly = checked and true or false
            if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
        end

        -- Bar list (ScrollFrame gotcha: CreateScrollFrame does NOT anchor the
        -- scroll frame itself — SetAllPoints() here, or content is clipped to 0x0).
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, -108)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSAnalyticsScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end

        for dim, tab in pairs(f.tabs) do
            tab:SetActive(dim == self._dim)
        end

        -- Reset ALL row state before repaint (regions and any child frames).
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local entries = self:Distribution(self._dim, self._onlineOnly)
        local y = 0
        for _, e in ipairs(entries) do
            local label = e.label
            if self._dim == "class" then
                label = LOCALIZED_CLASS_NAMES_MALE[e.label] or e.label
            end

            local labelFS = UI:CreateText(child, label, 11, C.text.r, C.text.g, C.text.b)
            labelFS:SetPoint("TOPLEFT", 4, -(y + 4))
            labelFS:SetWidth(LABEL_WIDTH - 8)
            labelFS:SetJustifyH("LEFT")

            local barBG = child:CreateTexture(nil, "BACKGROUND")
            barBG:SetTexture("Interface\\Buttons\\WHITE8x8")
            barBG:SetPoint("TOPLEFT", LABEL_WIDTH, -(y + 3))
            barBG:SetSize(BAR_MAX, ROW_HEIGHT - 6)
            barBG:SetVertexColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.6)

            local bar = child:CreateTexture(nil, "ARTWORK")
            bar:SetTexture("Interface\\Buttons\\WHITE8x8")
            bar:SetPoint("TOPLEFT", LABEL_WIDTH, -(y + 3))
            bar:SetSize(math.max(1, (e.pct / 100) * BAR_MAX), ROW_HEIGHT - 6)
            if self._dim == "class" and e.colorKey and RAID_CLASS_COLORS[e.colorKey] then
                local cc = RAID_CLASS_COLORS[e.colorKey]
                bar:SetVertexColor(cc.r, cc.g, cc.b)
            else
                bar:SetVertexColor(C.accent.r, C.accent.g, C.accent.b)
            end

            local valueFS = UI:CreateText(child,
                e.count .. " (" .. string.format("%.0f%%", e.pct) .. ")",
                11, C.textDim.r, C.textDim.g, C.textDim.b)
            valueFS:SetPoint("TOPLEFT", LABEL_WIDTH + BAR_MAX + 8, -(y + 4))

            y = y + ROW_HEIGHT
        end

        if #entries == 0 then
            local empty = UI:CreateText(child, L["No data."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
            y = 20
        end

        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end

function GuildAnalytics:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("analytics.class", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false }, { class = "WARRIOR", online = true } }
        local out, total = GuildAnalytics:Distribution("class", false, roster)
        if total ~= 3 then return false, "total" end
        if out[1].label ~= "MAGE" or out[1].count ~= 2 then return false, "top bucket" end
        return true
    end)
    S:Register("analytics.online_filter", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false } }
        local _, total = GuildAnalytics:Distribution("class", true, roster)
        if total ~= 1 then return false, "online-only" end
        return true
    end)
    S:Register("analytics.level_bracket", function()
        if GuildAnalytics:_LevelBracket(70) ~= "70" then return false, "70" end
        if GuildAnalytics:_LevelBracket(65) ~= "60-69" then return false, "60-69" end
        if GuildAnalytics:_LevelBracket(5) ~= "1-9" then return false, "1-9" end
        return true
    end)
    S:Register("analytics.pct", function()
        local roster = { { class = "MAGE" }, { class = "MAGE" }, { class = "ROGUE" }, { class = "ROGUE" } }
        local out = GuildAnalytics:Distribution("class", false, roster)
        if math.abs(out[1].pct - 50) > 0.01 then return false, "pct" end
        return true
    end)
end
