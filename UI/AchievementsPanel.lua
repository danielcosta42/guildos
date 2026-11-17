----------------------------------------------------------------------
-- Guild OS - The Achievements tab (issue #216, guildos.me #245)
-- The guild's renown, what is nearest to done, and what it earned. Modules/Achievements.lua answers;
-- this draws. WoW: Forever only: the Guild tab's Achievements sub-tab since issue #367, offered only
-- where the feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day
local BADGE = 48   -- the insignia beside the renown

-- Laid out as every Guild sub-tab is (#371): flush left, the first line GAP down, a section title
-- over each block, and a list whose date (or count) stands in a right-hand column of its own.
-- GAP is 8 where a test's stand-in UI carries no grid.
local GAP = type(UI.GAP) == "number" and UI.GAP or 8
local SECTION_SPACE = 20   -- over a later section title: its rule sits 12px above it
local ROW_GAP = 6
local COL_W = 80           -- the right-hand column: a date, or how far along
local BAR_W = 120          -- the progress bar beside it, a fixed width so the bars line up

function GuildOS:CreateAchievementsPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSAchievementsScroll")
    scroll:SetPoint("TOPLEFT", 0, -GAP)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- The content keeps the list's width, less the scroll bar's gutter: every line hangs from both of
    -- its top corners, never from a width read while the tab was hidden.
    UI:BindScrollChildWidth(scroll, content)

    -- The renown's title (or the renown alone, from an older site) is the screen's first heading.
    local nameFS = UI:CreateSectionTitle(content, "", true)
    -- A later section in a frame of its own, so the title and the rule over it hide together.
    local function section(text)
        local box = CreateFrame("Frame", nil, content)
        box.title = UI:CreateSectionTitle(box, text)
        box.title:SetPoint("TOPLEFT", 0, 0)
        return box
    end
    local nearHead, earnedHead = section(L["NEAREST"]), section(L["EARNED"])

    local pool, used, bars, usedBars, y = {}, 0, {}, 0, 0

    local function fontString(col)
        used = used + 1
        local fs = pool[used]
        if not fs then
            fs = UI:CreateText(content, "", 12)
            pool[used] = fs
        end
        fs:SetTextColor(col.r, col.g, col.b)
        fs:ClearAllPoints()
        fs:SetWidth(0)
        fs:SetJustifyH("LEFT")
        fs:Show()
        return fs
    end

    local function progressBar()
        usedBars = usedBars + 1
        local bar = bars[usedBars]
        if not bar then
            bar = UI:CreateProgressBar(content, BAR_W, 8)
            bars[usedBars] = bar
        end
        bar:ClearAllPoints()
        bar:Show()
        return bar
    end

    local function heading(box)
        y = y + SECTION_SPACE
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 0, -y)
        box:SetPoint("TOPRIGHT", 0, -y)
        local h = box.title:GetStringHeight() or 14
        box:SetHeight(h)
        box:Show()
        y = y + h + GAP
    end

    -- A line across the content from `indent`, wrapped.
    local function line(text, col, indent, gap)
        local fs = fontString(col)
        fs:SetPoint("TOPLEFT", indent or 0, -y)
        fs:SetPoint("TOPRIGHT", 0, -y)
        fs:SetText(text)
        y = y + (fs:GetStringHeight() or 14) + (gap or ROW_GAP)
    end

    -- What on the left; `right` (a date, or "8/10") right-aligned in its own column, and when `value`
    -- is given a progress bar just before it.
    local function row(text, right, value)
        local r = fontString(C.textSoft)
        r:SetPoint("TOPRIGHT", 0, -y)
        r:SetWidth(COL_W)
        r:SetJustifyH("RIGHT")
        r:SetText(right)
        local stop, dy = r, 0
        if value then
            local bar = progressBar()
            bar:SetPoint("TOPRIGHT", r, "TOPLEFT", -GAP, -4)
            bar:SetProgress(value)
            stop, dy = bar, 4
        end
        local fs = fontString(C.text)
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetPoint("TOPRIGHT", stop, "TOPLEFT", -GAP, dy)
        fs:SetText(text)
        y = y + math.max(fs:GetStringHeight() or 14, 14) + ROW_GAP
    end

    local badge = content:CreateTexture(nil, "ARTWORK")
    badge:SetSize(BADGE, BADGE)
    badge:Hide()

    local function refresh()
        local A = GuildOS.Achievements
        if not A then return end
        for _, fs in ipairs(pool) do fs:Hide() end
        for _, bar in ipairs(bars) do bar:Hide() end
        badge:Hide()
        nameFS:Hide()
        nearHead:Hide()
        earnedHead:Hide()
        used, usedBars, y = 0, 0, 0

        local level, points = A:Renown()
        if not level then
            line(L["Achievements come from guildos.me: the web companion brings them here when your guild has them."], C.textSoft)
            content:SetHeight(math.max(1, y))
            return
        end
        -- The insignia beside the renown, its title above it. With neither, an older site: the line alone,
        -- as the heading.
        local tex, title = A:Insignia()
        local top, indent = y, tex and BADGE + 12 or 0
        if tex then
            badge:SetTexture(tex)
            badge:ClearAllPoints()
            badge:SetPoint("TOPLEFT", 0, -y)
            badge:Show()
        end
        local renown = string.format(L["Renown %d · %d points"], level, points)
        nameFS:SetText(title or renown)
        nameFS:ClearAllPoints()
        nameFS:SetPoint("TOPLEFT", indent, -y)
        nameFS:Show()
        y = y + (nameFS:GetStringHeight() or 14) + 4
        if title then line(renown, C.text, indent) end
        if tex then y = math.max(y, top + BADGE + GAP) end

        local nearest = A:Next()
        if #nearest > 0 then
            heading(nearHead)
            for _, n in ipairs(nearest) do
                local target = tonumber(n.target) or 0
                row(n.title, string.format("%d/%d", n.current, n.target), target > 0 and (tonumber(n.current) or 0) / target or 0)
            end
        end

        heading(earnedHead)
        local earned = A:Earned()
        if #earned == 0 then line(L["Nothing earned yet."], C.textSoft) end
        for _, e in ipairs(earned) do
            row(e.title, day(e.at))
        end
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
