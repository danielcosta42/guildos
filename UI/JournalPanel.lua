----------------------------------------------------------------------
-- Guild OS - The Journal tab (issue #211, guildos.me #242)
-- This week (the guild as a whole), the guild's first clear of each new dungeon, and my own
-- milestones. No ranking of anybody. Modules/Journal.lua answers every question; this draws.
-- WoW: Forever only: the Guild tab's Journal sub-tab since issue #367, offered only where the
-- feature exists and is on (UI/CommunityPanel.lua, UI/Features.lua).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

-- Laid out as every Guild sub-tab is (#371): flush left, the first line GAP down, a section title
-- over each block, and a list whose date stands in a right-hand column of its own.
local GAP = UI.GAP
local SECTION_SPACE = 20   -- over a later section title: its rule sits 12px above it
local ROW_GAP = 6
local COL_W = 80           -- the date column: "2026-11-17" with room to spare

function GuildOS:CreateJournalPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSJournalScroll")
    scroll:SetPoint("TOPLEFT", 0, -GAP)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- The content keeps the list's width, less the scroll bar's gutter: every line hangs from both of
    -- its top corners, never from a width read while the tab was hidden.
    UI:BindScrollChildWidth(scroll, content)

    local heads = {
        week   = UI:CreateSectionTitle(content, L["THIS WEEK"], true),
        firsts = UI:CreateSectionTitle(content, L["GUILD FIRSTS"]),
        mine   = UI:CreateSectionTitle(content, L["YOUR JOURNAL"]),
    }
    local pool, used, y = {}, 0, 0

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

    local function heading(fs, first)
        if not first then y = y + SECTION_SPACE end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        y = y + (fs:GetStringHeight() or 14) + GAP
    end

    -- A line across the content, wrapped.
    local function line(text, col, gap)
        local fs = fontString(col)
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetPoint("TOPRIGHT", 0, -y)
        fs:SetText(text)
        y = y + (fs:GetStringHeight() or 14) + (gap or ROW_GAP)
    end

    -- What happened on the left, its date right-aligned in its own column.
    local function row(text, when, gap)
        local d = fontString(C.textSoft)
        d:SetPoint("TOPRIGHT", 0, -y)
        d:SetWidth(COL_W)
        d:SetJustifyH("RIGHT")
        d:SetText(day(when))
        local fs = fontString(C.text)
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetPoint("TOPRIGHT", d, "TOPLEFT", -GAP, 0)
        fs:SetText(text)
        y = y + math.max(fs:GetStringHeight() or 14, 14) + (gap or ROW_GAP)
    end

    local function refresh()
        local J = GuildOS.Journal
        if not J then return end
        for _, fs in ipairs(pool) do fs:Hide() end
        used, y = 0, 0

        local week = J:ThisWeek(GetServerTime())
        heading(heads.week, true)
        line(string.format(L["%d level milestones · %d members leveling · %d dungeon clears"], week.milestones, week.members, week.clears),
            C.text)

        heading(heads.firsts)
        local firsts = J:GuildFirsts()
        if #firsts == 0 then line(L["No new dungeon cleared by the guild yet."], C.textSoft) end
        for _, f in ipairs(firsts) do
            row(string.format(L["%s · %d bosses"], f.name, f.bosses or 0), f.at, 2)
            line(table.concat(f.who, " · "), C.textSoft)
        end

        heading(heads.mine)
        local mine = J:Mine()
        if #mine == 0 then line(L["Nothing yet: your milestones and dungeon clears appear here."], C.textSoft) end
        for _, e in ipairs(mine) do
            local what
            if e.type == "dungeon.clear" then
                what = string.format(L["%s · %d bosses"], e.data.dungeonName or e.data.dungeonId or "?", e.data.bosses or 0)
            else
                what = string.format(L["Level %d"], e.type == "member.level60" and GuildOS.Client.maxLevel or e.data.level or 0)
            end
            row(what, e.at)
        end
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    -- ponytail: drawn on show and on resize; a clear that syncs in while it is open waits for the next show.
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
