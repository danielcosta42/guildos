----------------------------------------------------------------------
-- Guild OS - Craft Finder
-- Realm-wide "who can craft this?" popup. Guild crafters are known locally
-- (RecipeTracker); realm/out-of-guild crafters trickle in over the Chehul mesh
-- via GuildOS.CraftNet as each peer answers for itself.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local FRAME_W  = 460   -- room for Order beside Whisper (issue #389)
local ROW_H    = 22
local MAX_ROWS = 12
local LIST_TOP = -126   -- y of the first result row (below input, item line, status and header)

-- item:12345 link, a raw item id, or an [item] hyperlink → itemId
local function ResolveItemId(text)
    if not text or text == "" then return nil end
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    return tonumber((text:gsub("%s", "")):match("^(%d+)$"))
end

----------------------------------------------------------------------
-- Build the singleton popup.
----------------------------------------------------------------------
local function BuildFinder()
    local f = CreateFrame("Frame", "GuildOSCraftFinder", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, 138 + MAX_ROWS * ROW_H)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
    })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    UI:StylePopup(f)   -- the popup's lineHi border
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSCraftFinder")

    -- Title
    local title = UI:CreateTitle(f, L["Search the realm"], 13)
    title:SetPoint("TOPLEFT", 12, -10)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Item input: the shared field, its hint its own (input.placeholder), #371.
    local input = UI:CreateInput(f, FRAME_W - 24, 24, { placeholder = L["Shift-click an item or type its id"] })
    input:SetPoint("TOPLEFT", 12, -34)

    -- Item line (icon + name of the resolved item)
    local itemIcon = f:CreateTexture(nil, "ARTWORK")
    itemIcon:SetSize(18, 18)
    itemIcon:SetPoint("TOPLEFT", 12, -62)
    itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    itemIcon:Hide()
    f.itemIcon = itemIcon

    local itemName = UI:CreateText(f, "", 12, C.text.r, C.text.g, C.text.b)   -- a name, in `text` (#371)
    itemName:SetPoint("LEFT", itemIcon, "RIGHT", 6, 0)
    f.itemName = itemName

    -- Status line
    local status = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    status:SetPoint("TOPLEFT", 12, -86)
    f.status = status

    -- An order open to every guild crafter of the item (issue #389).
    local orderAll = UI:CreateButton(f, L["Order from the guild"], 140, 20)
    UI:SetButtonVariant(orderAll, "primary")
    orderAll:SetPoint("TOPRIGHT", -12, -60)
    orderAll:Hide()
    orderAll:SetScript("OnClick", function() if f.query then GuildOS:ShowCraftOrderDialog(f.query.itemId) end end)
    f.orderAll = orderAll
    itemName:SetPoint("RIGHT", orderAll, "LEFT", -8, 0)
    itemName:SetJustifyH("LEFT")
    itemName:SetWordWrap(false)

    -- Column headers: the shared header row over the rows, its labels over their cells (#371).
    local header = UI:CreateTableHeader(f)
    header:SetPoint("TOPLEFT", 10, LIST_TOP + 22)
    header:SetPoint("TOPRIGHT", -10, LIST_TOP + 22)
    local function Hdr(text, x)
        local h = UI:CreateHeaderText(header, text, 10)
        h:SetPoint("LEFT", x, 0)
        return h
    end
    Hdr(L["PLAYER"],     4)
    Hdr(L["PROFESSION"], 140)
    Hdr(L["WHERE"],      260)

    f.rows = {}
    f.query = nil

    -- Get (or lazily build) result row #i.
    local function GetRow(i)
        local row = f.rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, f, "BackdropTemplate")
        row:SetSize(FRAME_W - 20, ROW_H)
        row:SetPoint("TOPLEFT", 10, LIST_TOP - (i - 1) * ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local bg = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)

        row.nameFS = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(row.nameFS, 11)
        row.nameFS:SetPoint("LEFT", 4, 0)
        row.nameFS:SetWidth(132); row.nameFS:SetJustifyH("LEFT"); row.nameFS:SetWordWrap(false)

        row.profFS = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(row.profFS, 10)
        row.profFS:SetPoint("LEFT", 140, 0)
        row.profFS:SetWidth(115); row.profFS:SetJustifyH("LEFT"); row.profFS:SetWordWrap(false)
        row.profFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

        row.scopeFS = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(row.scopeFS, 9)
        row.scopeFS:SetPoint("LEFT", 260, 0)
        row.scopeFS:SetWidth(56); row.scopeFS:SetJustifyH("LEFT")

        local wb = UI:CreateButton(row, L["Whisper"], 56, 18)
        wb:SetPoint("RIGHT", -4, 0)
        row.whisperBtn = wb
        -- A guild crafter takes an order sent to them alone (issue #389).
        local ob = UI:CreateButton(row, L["Order"], 50, 18)
        ob:SetPoint("RIGHT", wb, "LEFT", -4, 0)
        row.orderBtn = ob

        f.rows[i] = row
        return row
    end

    local function HideRows(fromIdx)
        for i = fromIdx, #f.rows do
            f.rows[i]:Hide()
        end
    end

    -- Append one crafter result. class may be nil (unknown, e.g. realm peer).
    local function AddResult(name, prof, scope, class, key)
        local q = f.query
        if not q then return end
        q.count = q.count + 1
        if q.count > MAX_ROWS then
            q.overflow = (q.overflow or 0) + 1
            return
        end
        local row = GetRow(q.count)
        local cr, cg, cb = C.text.r, C.text.g, C.text.b
        if class then cr, cg, cb = GuildOS:GetClassColor(class) end
        row.nameFS:SetTextColor(cr, cg, cb)
        row.nameFS:SetText(name)
        row.profFS:SetText(prof or "")
        -- Our own guild in `text`, an ally or the realm softer: no gold, no colour of its own (#371).
        local ink = (scope == L["Guild"]) and C.text or C.textSoft
        row.scopeFS:SetTextColor(ink.r, ink.g, ink.b)
        row.scopeFS:SetText(scope)

        local itemId = q.itemId
        local me = GuildOS.CraftOrders and GuildOS.CraftOrders:MyKey()
        row.orderBtn:SetShown(key ~= nil and key ~= me and GuildOS.ShowCraftOrderDialog ~= nil)
        row.orderBtn:SetScript("OnClick", function() GuildOS:ShowCraftOrderDialog(itemId, key) end)
        row.whisperBtn:SetScript("OnClick", function()
            local link = itemId and select(2, GuildOS.Compat.GetItemInfo(itemId))
            local subject = link or (f.itemName:GetText() ~= "" and f.itemName:GetText()) or L["this item"]
            ChatFrame_OpenChat("/w " .. name .. " " .. string.format(L["Can you craft %s?"], subject))
        end)
        row:Show()
    end
    f.AddResult = AddResult

    local function SetStatus()
        local q = f.query
        if not q then return end
        local txt = string.format(L["%d crafter(s) found"], q.count)
        if q.overflow and q.overflow > 0 then
            txt = txt .. string.format(L[" (+%d more)"], q.overflow)
        end
        if not q.done then
            txt = txt .. L["  -  querying the realm..."]
        end
        f.status:SetText(txt)
    end

    -- Run a fresh query for itemId.
    function f.RunQuery(itemId)
        itemId = tonumber(itemId)
        if not itemId then return end
        f.query = { itemId = itemId, seen = {}, count = 0, overflow = 0, done = false }
        HideRows(1)

        -- Item line
        local name, _, _, _, _, _, _, _, _, tex = GuildOS.Compat.GetItemInfo(itemId)
        f.itemName:SetText(name or ("item:" .. itemId))
        if tex then f.itemIcon:SetTexture(tex); f.itemIcon:Show() else f.itemIcon:Hide() end

        -- Guild crafters (already synced locally).
        local guild = GuildOS.RecipeTracker and GuildOS.RecipeTracker:GetCraftersForItem(itemId)
        f.orderAll:SetShown(guild ~= nil and GuildOS.ShowCraftOrderDialog ~= nil)
        if guild then
            for _, c in ipairs(guild) do
                if not f.query.seen[c.playerName] then
                    f.query.seen[c.playerName] = true
                    AddResult(c.playerName, c.profName and L[c.profName], L["Guild"], c.class, c.playerKey)
                end
            end
        end

        -- Alliance: read straight from the synced directory, so an allied
        -- crafter is found even while they are offline. No query, no waiting.
        if GuildOS.Alliance and GuildOS.Alliance:Get() then
            for _, c in ipairs(GuildOS.Alliance:FindCrafters(itemId)) do
                if not f.query.seen[c.name] then
                    f.query.seen[c.name] = true
                    local label = L[c.prof or "?"]
                    if not c.online then
                        label = label .. " " .. L["(offline)"]
                    end
                    AddResult(c.name, label, c.guild, nil)
                end
            end
        end

        -- Realm-wide: answers arrive over time.
        if GuildOS.CraftNet then
            GuildOS.CraftNet:Query(itemId, function(short, label)
                if not f.query or f.query.itemId ~= itemId then return end  -- stale
                if f.query.seen[short] then return end
                f.query.seen[short] = true
                AddResult(short, label and L[label], L["Realm"], nil)
                SetStatus()
            end)
            -- Close the "querying" state after the realm TTL so the status settles.
            if C_Timer and C_Timer.After then
                C_Timer.After((GuildOS.CraftNet.TTL or 45) + 1, function()
                    if f.query and f.query.itemId == itemId then
                        f.query.done = true
                        SetStatus()
                    end
                end)
            end
        else
            f.query.done = true
        end
        SetStatus()
    end

    -- Input handling: Escape and the hint are the field's own.
    input:SetScript("OnEnterPressed", function(self)
        local id = ResolveItemId(self:GetText())
        if id then
            f.RunQuery(id)
            self:SetText("")
        end
        self:ClearFocus()
    end)

    -- Shift-click an item anywhere → query it (only while the finder is open).
    if not f._clickHooked and HandleModifiedItemClick then
        f._clickHooked = true
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not f:IsShown() or not IsShiftKeyDown() or not link then return end
            local id = tonumber(link:match("item:(%d+)"))
            if id then f.RunQuery(id) end
        end)
    end

    return f
end

----------------------------------------------------------------------
-- Public entry: open the finder, optionally pre-running a query.
----------------------------------------------------------------------
function GuildOS:ShowCraftFinder(prefillItemId)
    local f = self.craftFinder or BuildFinder()
    self.craftFinder = f
    f:Show()
    f:Raise()
    if prefillItemId then
        f.RunQuery(prefillItemId)
    end
end
