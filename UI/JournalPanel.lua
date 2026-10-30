----------------------------------------------------------------------
-- Guild OS - The Journal tab (issue #211, guildos.me #242)
-- This week (the guild as a whole), the guild's first clear of each new dungeon, and my own
-- milestones. No ranking of anybody. Modules/Journal.lua answers every question; this draws.
-- WoW: Forever only: the tab is offered only where the module exists (UI/Features.lua).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day

function GuildOS:CreateJournalPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSJournalScroll")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local pool, used, y = {}, 0, 0
    local function width()
        local w = scroll:GetWidth() or 0
        return w > 1 and w or 400   -- 0 before the first layout, not nil
    end

    local function line(text, size, col, indent, gap)
        used = used + 1
        local fs = pool[used]
        if not fs then
            fs = UI:CreateText(content, "", size, col.r, col.g, col.b)
            fs:SetJustifyH("LEFT")
            pool[used] = fs
        end
        GuildOS:ApplyFont(fs, size)
        fs:SetTextColor(col.r, col.g, col.b)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", indent or 4, -y)
        fs:SetWidth(math.max(1, width() - (indent or 4) - 8))
        fs:SetText(text)
        fs:Show()
        y = y + (fs:GetStringHeight() or size) + (gap or 6)
    end

    local function refresh()
        local J = GuildOS.Journal
        if not J then return end
        for _, fs in ipairs(pool) do fs:Hide() end
        used, y = 0, 4
        content:SetWidth(width())

        local week = J:ThisWeek(GetServerTime())
        line(L["THIS WEEK"], 12, C.gold)
        line(string.format(L["%d level milestones · %d members leveling · %d dungeon clears"], week.milestones, week.members, week.clears),
            11, C.text, 8, 14)

        line(L["GUILD FIRSTS"], 12, C.gold)
        local firsts = J:GuildFirsts()
        if #firsts == 0 then line(L["No new dungeon cleared by the guild yet."], 11, C.textDim, 8) end
        for _, f in ipairs(firsts) do
            line(string.format(L["%s · %d bosses"], f.name, f.bosses or 0) .. "  ·  " .. day(f.at), 11, C.text, 8, 2)
            line(table.concat(f.who, " · "), 10, C.textDim, 16)
        end
        y = y + 8

        line(L["YOUR JOURNAL"], 12, C.gold)
        local mine = J:Mine()
        if #mine == 0 then line(L["Nothing yet: your milestones and dungeon clears appear here."], 11, C.textDim, 8) end
        for _, e in ipairs(mine) do
            local what
            if e.type == "dungeon.clear" then
                what = string.format(L["%s · %d bosses"], e.data.dungeonName or e.data.dungeonId or "?", e.data.bosses or 0)
            else
                what = string.format(L["Level %d"], e.type == "member.level60" and GuildOS.Client.maxLevel or e.data.level or 0)
            end
            line(what .. "  ·  " .. day(e.at), 11, C.text, 8, 2)
        end
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    -- ponytail: drawn on show and on resize; a clear that syncs in while it is open waits for the next show.
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
