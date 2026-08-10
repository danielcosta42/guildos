----------------------------------------------------------------------
-- Guild OS - Layout primitives
-- Container-driven geometry: how many columns fit, how many rows fit,
-- how a button bar wraps. The three resolvers are pure functions of
-- their arguments so /gos selftest can exercise them with no frames.
----------------------------------------------------------------------
local UI = BRutus.UI

----------------------------------------------------------------------
-- How many of these columns fit in `width`, and where does each go?
-- Columns are dropped lowest-priority-first until the minimums fit,
-- then the leftover is shared out by weight. `required` columns are
-- never dropped: if even they do not fit they shrink below their
-- minimum and their text truncates, because a squeezed table is more
-- useful than an empty one.
--   spec  -> { { key, min, weight, priority, required }, ... }
--   ret   -> { { key, x, w, min, shown }, ... } plus .byKey[key]
----------------------------------------------------------------------
function UI:ResolveColumns(spec, width, gap)
    gap = gap or 0
    width = math.max(width or 0, 0)

    local shown = {}
    for i = 1, #spec do shown[i] = true end

    local function needed()
        local total, n = 0, 0
        for i, c in ipairs(spec) do
            if shown[i] then
                total = total + c.min
                n = n + 1
            end
        end
        if n > 1 then total = total + gap * (n - 1) end
        return total, n
    end

    -- Drop the lowest-priority droppable column until the minimums fit.
    while true do
        local total = needed()
        if total <= width then break end
        local victim, worst
        for i, c in ipairs(spec) do
            if shown[i] and not c.required then
                if not worst or c.priority < worst then
                    victim, worst = i, c.priority
                end
            end
        end
        if not victim then break end   -- only required columns left: floor case
        shown[victim] = false
    end

    local total, count = needed()
    local slack = width - total
    local weightSum, minSum = 0, 0
    for i, c in ipairs(spec) do
        if shown[i] then
            weightSum = weightSum + (c.weight or 0)
            minSum = minSum + c.min
        end
    end

    -- Floor case: not even the required columns fit their minimums. Give up
    -- the gaps first, then shrink every survivor in proportion to its
    -- minimum. A flat per-column deduction cannot be used here: it drives
    -- narrow columns negative, and clamping those back to 1px pushes the
    -- total straight back over the available width.
    local effGap = gap
    local widths = {}
    if slack < 0 then
        if count > 1 and (width - gap * (count - 1)) < count then effGap = 0 end
        local avail = math.max(0, width - effGap * math.max(0, count - 1))
        local used = 0
        for i, c in ipairs(spec) do
            if shown[i] then
                local w = math.floor(avail * c.min / minSum)
                if avail >= count then w = math.max(1, w) end
                widths[i] = w
                used = used + w
            end
        end
        -- Hand whatever the flooring left over to the widest survivor.
        local spare, widest, widestMin = avail - used, nil, -1
        for i, c in ipairs(spec) do
            if shown[i] and c.min > widestMin then widest, widestMin = i, c.min end
        end
        if widest and spare > 0 then widths[widest] = widths[widest] + spare end
    else
        local used = 0
        for i, c in ipairs(spec) do
            if shown[i] then
                local w = c.min
                if weightSum > 0 then
                    w = w + math.floor(slack * (c.weight or 0) / weightSum)
                end
                widths[i] = w
                used = used + w
            end
        end
        -- Same rounding remainder, so the table fills its area exactly.
        local spare, flex = width - effGap * math.max(0, count - 1) - used, nil
        for i, c in ipairs(spec) do
            if shown[i] and (c.weight or 0) > 0 then flex = flex or i end
        end
        if flex and spare > 0 then widths[flex] = widths[flex] + spare end
    end

    local layout = { byKey = {} }
    local x = 0
    for i, c in ipairs(spec) do
        local entry = { key = c.key, x = 0, w = 0, min = c.min, shown = shown[i] }
        if shown[i] then
            entry.x, entry.w = x, widths[i]
            x = x + widths[i] + effGap
        end
        layout[#layout + 1] = entry
        layout.byKey[c.key] = entry
    end
    return layout
end

----------------------------------------------------------------------
-- How many rows of `rowH` fit in `height` once `reserved` (column
-- header, footer, paging strip) is carved out. Replaces every
-- VISIBLE_ROWS constant in the addon.
----------------------------------------------------------------------
function UI:ResolveRows(height, rowH, reserved)
    if not rowH or rowH <= 0 then return 0 end
    local usable = (height or 0) - (reserved or 0)
    if usable <= 0 then return 0 end
    return math.floor(usable / rowH)
end

----------------------------------------------------------------------
-- Break a list of button widths into rows that each fit `available`.
-- A button wider than the whole bar gets a row to itself rather than
-- looping forever.
----------------------------------------------------------------------
function UI:FlowRows(widths, available, gap)
    gap = gap or 0
    local rows, current, used = {}, {}, 0
    for i, w in ipairs(widths) do
        local advance = (#current > 0) and (gap + w) or w
        if #current > 0 and used + advance > available then
            rows[#rows + 1] = current
            current, used = {}, 0
            advance = w
        end
        current[#current + 1] = i
        used = used + advance
    end
    if #current > 0 then rows[#rows + 1] = current end
    return rows
end

----------------------------------------------------------------------
-- Lay `buttons` out inside `bar`, wrapping as needed. Returns the total
-- height so whatever sits below the bar can anchor to it.
----------------------------------------------------------------------
function UI:FlowBar(bar, buttons, opts)
    opts = opts or {}
    local gap    = opts.gap or 4
    local rowGap = opts.rowGap or 4
    local rowH   = opts.rowH or 26

    local widths = {}
    for i, b in ipairs(buttons) do widths[i] = b:GetWidth() end

    local rows = self:FlowRows(widths, bar:GetWidth(), gap)
    for r, row in ipairs(rows) do
        local x = 0
        for _, idx in ipairs(row) do
            local b = buttons[idx]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -((r - 1) * (rowH + rowGap)))
            x = x + widths[idx] + gap
        end
    end

    local height = #rows * rowH + math.max(0, #rows - 1) * rowGap
    bar:SetHeight(height)
    return height
end

----------------------------------------------------------------------
-- Keep a scroll frame's child as wide as the frame itself.
--
-- A scroll child is sized in code, not by anchors: SetScrollChild ignores
-- the child's points for width. That is why every scrolling panel in the
-- addon had a hardcoded width baked in, which either clipped its rows or
-- let them spill once the window stopped being the one fixed size.
----------------------------------------------------------------------
function UI:BindScrollChildWidth(scrollFrame, child, inset)
    inset = inset or 0
    local function apply()
        local w = scrollFrame:GetWidth()
        if w and w > 1 then child:SetWidth(math.max(1, w - inset)) end
    end
    scrollFrame:SetScript("OnSizeChanged", apply)
    scrollFrame:HookScript("OnShow", apply)
    apply()
    return apply
end

----------------------------------------------------------------------
-- Re-run `layoutFn` whenever the container is resized. A grip drag
-- fires OnSizeChanged many times per second, so the work is coalesced
-- into one call per frame. Also fires once on the first OnShow, so the
-- initial layout is right before the user touches anything.
----------------------------------------------------------------------
function UI:MakeResponsive(container, layoutFn)
    container.__layout = layoutFn

    local function apply()
        container.__layoutPending = false
        local w, h = container:GetWidth(), container:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        BRutus:SafeCall(function() layoutFn(container, w, h) end)
    end

    container:SetScript("OnSizeChanged", function(self)
        if self.__layoutPending then return end
        self.__layoutPending = true
        C_Timer.After(0, apply)
    end)

    container:HookScript("OnShow", function(self)
        if self.__layoutDone then return end
        self.__layoutDone = true
        C_Timer.After(0, apply)
    end)

    -- A container that is already visible never fires OnShow again.
    if container:IsVisible() then
        container.__layoutDone = true
        C_Timer.After(0, apply)
    end
end

function UI:_RegisterLayoutTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    -- The roster spec from the design doc, section 5.3.
    local ROSTER = {
        { key = "name",        min = 150, weight = 3, priority = 100, required = true },
        { key = "level",       min = 34,  weight = 0, priority = 95,  required = true },
        { key = "class",       min = 74,  weight = 1, priority = 90,  required = true },
        { key = "avgIlvl",     min = 46,  weight = 0, priority = 80 },
        { key = "race",        min = 70,  weight = 1, priority = 60 },
        { key = "lastSeen",    min = 78,  weight = 1, priority = 50 },
        { key = "professions", min = 160, weight = 2, priority = 40 },
        { key = "zone",        min = 120, weight = 2, priority = 30 },
    }

    local function shownKeys(width)
        local out = {}
        for _, c in ipairs(UI:ResolveColumns(ROSTER, width, 10)) do
            if c.shown then out[#out + 1] = c.key end
        end
        return table.concat(out, ",")
    end

    S:Register("layout.columns_drop_by_priority", function()
        local cases = {
            -- table width -> expected shown set, from design doc 5.3
            { 1060, "name,level,class,avgIlvl,race,lastSeen,professions,zone" },
            {  720, "name,level,class,avgIlvl,race,lastSeen,professions" },
            {  520, "name,level,class,avgIlvl,race,lastSeen" },
            {  440, "name,level,class,avgIlvl,race" },
            {  340, "name,level,class,avgIlvl" },
            {  200, "name,level,class" },
        }
        for _, c in ipairs(cases) do
            local got = shownKeys(c[1])
            if got ~= c[2] then
                return false, string.format("at %d got [%s] want [%s]", c[1], got, c[2])
            end
        end
        return true
    end)

    S:Register("layout.columns_fit", function()
        -- Every pixel from the floor case up past the widest realistic
        -- window. Off-by-ones in the slack maths only show up at the
        -- exact width where a column drops.
        for width = 120, 1400 do
            local layout = UI:ResolveColumns(ROSTER, width, 10)
            local last
            for _, c in ipairs(layout) do
                if c.shown then
                    if c.w < 1 then return false, "zero-width column at " .. width end
                    last = c
                end
            end
            if not last then return false, "no columns shown at " .. width end
            local right = last.x + last.w
            if right > width then
                return false, string.format("overflow at %d: right edge %d", width, right)
            end
            -- And it must actually fill the area, not leave a ragged gap.
            if right < width - 1 then
                return false, string.format("underflow at %d: right edge %d", width, right)
            end
        end
        return true
    end)

    S:Register("layout.columns_respect_min_when_room", function()
        local layout = UI:ResolveColumns(ROSTER, 1400, 10)
        for _, c in ipairs(layout) do
            if c.shown and c.w < c.min then
                return false, c.key .. " below min at a width where everything fits"
            end
        end
        return true
    end)

    S:Register("layout.columns_required_never_dropped", function()
        for _, width in ipairs({ 400, 200, 90, 10, 0 }) do
            local byKey = UI:ResolveColumns(ROSTER, width, 10).byKey
            for _, key in ipairs({ "name", "level", "class" }) do
                if not byKey[key].shown then
                    return false, key .. " dropped at width " .. width
                end
            end
        end
        return true
    end)

    S:Register("layout.rows_fit", function()
        local cases = {
            { 400, 32, 36, 11 },
            { 400, 32, 0,  12 },
            { 0,   32, 36, 0  },
            { 10,  32, 36, 0  },
            { 480, 24, 96, 16 },
        }
        for _, c in ipairs(cases) do
            local n = UI:ResolveRows(c[1], c[2], c[3])
            if n ~= c[4] then
                return false, string.format("h=%d rowH=%d res=%d got %d want %d",
                    c[1], c[2], c[3], n, c[4])
            end
            if n > 0 and n * c[2] + c[3] > c[1] then
                return false, "rows overflow the available height"
            end
        end
        return true
    end)

    S:Register("layout.flow_wraps", function()
        local widths = { 116, 116, 116, 116, 116, 116, 116, 116 }
        local rows = UI:FlowRows(widths, 740, 4)
        if #rows ~= 2 then return false, "8 tabs in 740px want 2 rows, got " .. #rows end
        if #rows[1] ~= 6 then return false, "first row want 6 tabs, got " .. #rows[1] end
        if #rows[2] ~= 2 then return false, "second row want 2 tabs, got " .. #rows[2] end

        local wide = UI:FlowRows(widths, 2000, 4)
        if #wide ~= 1 then return false, "everything fits, want 1 row, got " .. #wide end

        local narrow = UI:FlowRows(widths, 40, 4)
        if #narrow ~= 8 then return false, "nothing fits, want 8 rows, got " .. #narrow end
        return true
    end)

    -- Regression guard for the dead-close-button bug. A title bar is
    -- mouse-enabled and drag-registered across its full width, so a button
    -- sitting on it at the same frame level never receives the click: the
    -- bar swallows it. UI/RosterFrame.lua had the fix inline; every other
    -- title bar was missing it, which killed every close button in the
    -- addon. UI:TitleBarButton is now the only way to build one.
    S:Register("layout.scroll_child_follows_frame", function()
        if not UI.BindScrollChildWidth then return false, "BindScrollChildWidth missing" end
        local scroll = CreateFrame("ScrollFrame", nil, UIParent)
        local child  = CreateFrame("Frame", nil, scroll)
        scroll:SetWidth(600)
        UI:BindScrollChildWidth(scroll, child, 10)
        if child:GetWidth() ~= 590 then
            return false, "initial width " .. child:GetWidth() .. ", want 590"
        end
        scroll:SetWidth(300)
        local onSize = scroll:GetScript("OnSizeChanged")
        if not onSize then return false, "OnSizeChanged was not registered" end
        onSize(scroll)
        if child:GetWidth() ~= 290 then
            return false, "after resize width " .. child:GetWidth() .. ", want 290"
        end
        return true
    end)

    S:Register("ui.titlebar_button_outranks_bar", function()
        if not UI.TitleBarButton then return false, "UI:TitleBarButton missing" end
        local host = CreateFrame("Frame", nil, UIParent)
        local bar  = CreateFrame("Frame", nil, host)
        bar:EnableMouse(true)
        for _, kind in ipairs({ "close", "text" }) do
            local btn = UI:TitleBarButton(bar, kind, "x", 20, 18)
            if btn:GetParent() ~= bar then
                return false, kind .. " button is not parented to the bar"
            end
            if btn:GetFrameLevel() <= bar:GetFrameLevel() then
                return false, string.format("%s button level %d does not outrank bar level %d",
                    kind, btn:GetFrameLevel(), bar:GetFrameLevel())
            end
        end
        return true
    end)
end

UI:_RegisterLayoutTests()
