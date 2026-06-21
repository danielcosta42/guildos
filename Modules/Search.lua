----------------------------------------------------------------------
-- Guild OS - Global Search
-- One box to find anything the guild knows: members by name, who can
-- craft a recipe, and items in the loot history. Read-only.
----------------------------------------------------------------------
local Search = {}
BRutus.Search = Search
local L = BRutus.L

local CAP = 20   -- max results per category

----------------------------------------------------------------------
-- Query everything. Returns { members = {...}, recipes = {...}, loot = {...} }.
----------------------------------------------------------------------
function Search:Query(text)
    text = strlower(strtrim(text or ""))
    local res = { members = {}, recipes = {}, loot = {} }
    if #text < 2 then return res end

    -- Members
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            if strlower(short):find(text, 1, true) and #res.members < CAP then
                res.members[#res.members + 1] = { name = short, class = classFile or "", level = level or 0, online = online }
            end
        end
    end

    -- Recipes — who can craft something matching the query
    local hits = {}
    for key, profs in pairs(BRutus.db.recipes or {}) do
        local crafter = key:match("^([^-]+)") or key
        for _, recipes in pairs(profs) do
            if type(recipes) == "table" then
                for _, r in pairs(recipes) do
                    local rname = (type(r) == "table" and (r.name or r.itemName)) or (type(r) == "string" and r) or nil
                    if rname and strlower(rname):find(text, 1, true) then
                        hits[rname] = hits[rname] or {}
                        hits[rname][crafter] = true
                    end
                end
            end
        end
    end
    for rname, set in pairs(hits) do
        if #res.recipes < CAP then
            local crafters = {}
            for c in pairs(set) do crafters[#crafters + 1] = c end
            table.sort(crafters)
            res.recipes[#res.recipes + 1] = { name = rname, crafters = crafters }
        end
    end
    table.sort(res.recipes, function(a, b) return a.name:lower() < b.name:lower() end)

    -- Loot history items
    for _, e in ipairs(BRutus.db.lootHistory or {}) do
        local iname = (e.itemLink and GetItemInfo(e.itemLink)) or e.itemName or ""
        if iname ~= "" and strlower(iname):find(text, 1, true) and #res.loot < CAP then
            res.loot[#res.loot + 1] = { item = iname, player = e.player or "?", ts = e.timestamp or 0 }
        end
    end

    return res
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Search:Show(initial)
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSSearchFrame", UIParent, "BackdropTemplate")
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

        local title = UI:CreateTitle(f, L["Search"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        box:SetPoint("TOPLEFT", 16, -42)
        box:SetSize(428, 26)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0.05, 0.05, 0.066, 1)
        box:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
        box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        box:SetTextColor(C.white.r, C.white.g, C.white.b)
        box:SetTextInsets(8, 8, 0, 0)
        box:SetAutoFocus(true)
        box:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
        local ph = box:CreateFontString(nil, "OVERLAY")
        ph:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        ph:SetPoint("LEFT", 8, 0)
        ph:SetTextColor(0.4, 0.4, 0.4)
        ph:SetText(L["Search members, recipes, loot..."])
        f.box = box
        f.ph = ph

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, -78)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSSearchScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder

        local function run()
            if f.box:GetText() ~= "" then f.ph:Hide() else f.ph:Show() end
            f:Render()
        end
        box:SetScript("OnTextChanged", run)
        self.frame = f
    end

    function f:Render()
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local res = Search:Query(f.box:GetText())
        local y = 0
        local function header(t)
            local h = UI:CreateHeaderText(child, t, 10)
            h:SetPoint("TOPLEFT", 2, -y)
            y = y + 18
        end
        local function line(t, color)
            color = color or C.text
            local fs = UI:CreateText(child, t, 11, color.r, color.g, color.b)
            fs:SetPoint("TOPLEFT", 10, -y)
            fs:SetWidth(child:GetWidth() - 14)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            y = y + 16
        end

        if #res.members > 0 then
            header(L["MEMBERS"])
            for _, m in ipairs(res.members) do
                local cr, cg, cb = BRutus:GetClassColor(m.class)
                line(string.format("%s  |cff888888L%d%s|r", m.name, m.level, m.online and "" or " ·offline"),
                    { r = cr, g = cg, b = cb })
            end
            y = y + 6
        end
        if #res.recipes > 0 then
            header(L["RECIPES"])
            for _, r in ipairs(res.recipes) do
                line(string.format("%s  |cff888888→ %s|r", r.name, table.concat(r.crafters, ", ")))
            end
            y = y + 6
        end
        if #res.loot > 0 then
            header(L["LOOT"])
            for _, e in ipairs(res.loot) do
                line(string.format("%s  |cff888888→ %s · %s|r", e.item, e.player, date("%m/%d", e.ts)))
            end
            y = y + 6
        end

        if #res.members == 0 and #res.recipes == 0 and #res.loot == 0 then
            local msg = (#strtrim(f.box:GetText()) < 2) and L["Type at least 2 characters."] or L["No matches."]
            local empty = UI:CreateText(child, msg, 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end

    f:Show()
    f.box:SetText(initial or "")
    f.box:SetFocus()
    f:Render()
end
