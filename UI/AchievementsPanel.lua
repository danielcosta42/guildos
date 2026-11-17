----------------------------------------------------------------------
-- Guild OS - The Achievements tab (issue #216, guildos.me #245)
-- The guild's renown, what is nearest to done, and what it earned. Modules/Achievements.lua answers;
-- this draws. WoW: Forever only: the tab is offered only where the module exists (UI/Features.lua).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local function day(t) return date("%Y-%m-%d", t) end   -- the reader's own day
local BADGE = 48   -- the insignia beside the renown

function GuildOS:CreateAchievementsPanel(parent)
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSAchievementsScroll")
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

    local badge = content:CreateTexture(nil, "ARTWORK")
    badge:SetSize(BADGE, BADGE)
    badge:Hide()

    local function refresh()
        local A = GuildOS.Achievements
        if not A then return end
        for _, fs in ipairs(pool) do fs:Hide() end
        badge:Hide()
        used, y = 0, 4
        content:SetWidth(width())

        local level, points = A:Renown()
        if not level then
            line(L["Achievements come from guildos.me: the web companion brings them here when your guild has them."], 11, C.textDim, 8)
            content:SetHeight(math.max(1, y))
            return
        end
        -- The insignia beside the renown, its title above it. With neither, an older site: the line alone.
        local tex, title = A:Insignia()
        local top, indent = y, tex and BADGE + 12 or 4
        if tex then
            badge:SetTexture(tex)
            badge:ClearAllPoints()
            badge:SetPoint("TOPLEFT", 4, -y)
            badge:Show()
        end
        if title then line(title, 13, C.gold, indent, 2) end
        line(string.format(L["Renown %d · %d points"], level, points), 12, title and C.text or C.gold, indent, 14)
        if tex then y = math.max(y, top + BADGE + 8) end

        local nearest = A:Next()
        if #nearest > 0 then
            line(L["NEAREST"], 12, C.gold)
            for _, n in ipairs(nearest) do
                line(string.format("%s  ·  %d/%d", n.title, n.current, n.target), 11, C.text, 8, 2)
            end
            y = y + 12
        end

        line(L["EARNED"], 12, C.gold)
        local earned = A:Earned()
        if #earned == 0 then line(L["Nothing earned yet."], 11, C.textDim, 8) end
        for _, e in ipairs(earned) do
            line(e.title .. "  ·  " .. day(e.at), 11, C.text, 8, 2)
        end
        content:SetHeight(math.max(1, y))
    end

    parent:HookScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    scroll:HookScript("OnSizeChanged", function() if parent:IsShown() then GuildOS:SafeCall(refresh) end end)
    GuildOS:SafeCall(refresh)
    return refresh
end
