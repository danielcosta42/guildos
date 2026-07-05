----------------------------------------------------------------------
-- Guild OS - Craft Finder
-- Realm-wide "who can craft this?" popup. Guild crafters are known locally
-- (RecipeTracker); realm/out-of-guild crafters trickle in over the Chehul mesh
-- via GuildOS.CraftNet as each peer answers for itself.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local FRAME_W  = 400
local ROW_H    = 22
local MAX_ROWS = 12
local LIST_TOP = -108   -- y of the first result row (below input + item line)

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
    f:SetSize(FRAME_W, 120 + MAX_ROWS * ROW_H)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSCraftFinder")

    -- Title
    local title = UI:CreateTitle(f, L["Find a Crafter"], 13)
    title:SetPoint("TOPLEFT", 12, -10)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Item input
    local input = CreateFrame("EditBox", "GuildOSCraftFinderInput", f, "BackdropTemplate")
    input:SetSize(FRAME_W - 24, 24)
    input:SetPoint("TOPLEFT", 12, -34)
    input:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    input:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    input:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    input:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    input:SetTextColor(C.white.r, C.white.g, C.white.b)
    input:SetTextInsets(8, 8, 0, 0)
    input:SetAutoFocus(false)

    local placeholder = input:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    placeholder:SetText(L["Shift-click an item or type its id"])
    input.placeholder = placeholder

    -- Item line (icon + name of the resolved item)
    local itemIcon = f:CreateTexture(nil, "ARTWORK")
    itemIcon:SetSize(18, 18)
    itemIcon:SetPoint("TOPLEFT", 12, -62)
    itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    itemIcon:Hide()
    f.itemIcon = itemIcon

    local itemName = UI:CreateText(f, "", 12, C.gold.r, C.gold.g, C.gold.b)
    itemName:SetPoint("LEFT", itemIcon, "RIGHT", 6, 0)
    f.itemName = itemName

    -- Status line
    local status = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    status:SetPoint("TOPLEFT", 12, -86)
    f.status = status

    -- Column headers
    local function Hdr(text, x)
        local h = UI:CreateHeaderText(f, text, 9)
        h:SetPoint("TOPLEFT", x, LIST_TOP + 14)
        return h
    end
    Hdr(L["PLAYER"],     14)
    Hdr(L["PROFESSION"], 150)
    Hdr(L["WHERE"],      270)

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
        row.nameFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        row.nameFS:SetPoint("LEFT", 4, 0)
        row.nameFS:SetWidth(132); row.nameFS:SetJustifyH("LEFT"); row.nameFS:SetWordWrap(false)

        row.profFS = row:CreateFontString(nil, "OVERLAY")
        row.profFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        row.profFS:SetPoint("LEFT", 140, 0)
        row.profFS:SetWidth(115); row.profFS:SetJustifyH("LEFT"); row.profFS:SetWordWrap(false)
        row.profFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

        row.scopeFS = row:CreateFontString(nil, "OVERLAY")
        row.scopeFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        row.scopeFS:SetPoint("LEFT", 260, 0)
        row.scopeFS:SetWidth(56); row.scopeFS:SetJustifyH("LEFT")

        local wb = UI:CreateButton(row, L["Whisper"], 56, 18)
        wb:SetPoint("RIGHT", -4, 0)
        row.whisperBtn = wb

        f.rows[i] = row
        return row
    end

    local function HideRows(fromIdx)
        for i = fromIdx, #f.rows do
            f.rows[i]:Hide()
        end
    end

    -- Append one crafter result. class may be nil (unknown, e.g. realm peer).
    local function AddResult(name, prof, scope, class)
        local q = f.query
        if not q then return end
        q.count = q.count + 1
        if q.count > MAX_ROWS then
            q.overflow = (q.overflow or 0) + 1
            return
        end
        local row = GetRow(q.count)
        local cr, cg, cb = C.white.r, C.white.g, C.white.b
        if class then cr, cg, cb = BRutus:GetClassColor(class) end
        row.nameFS:SetTextColor(cr, cg, cb)
        row.nameFS:SetText(name)
        row.profFS:SetText(prof or "")
        if scope == L["Guild"] then
            row.scopeFS:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        else
            row.scopeFS:SetTextColor(0.6, 0.8, 1.0)
        end
        row.scopeFS:SetText(scope)

        local itemId = q.itemId
        row.whisperBtn:SetScript("OnClick", function()
            local link = itemId and select(2, GetItemInfo(itemId))
            local subject = link or (f.itemName:GetText() ~= "" and f.itemName:GetText()) or L["this item"]
            ChatFrame_OpenChat("/w " .. name .. L[" Can you craft "] .. subject .. L[" ?"])
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
        local name, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
        f.itemName:SetText(name or ("item:" .. itemId))
        if tex then f.itemIcon:SetTexture(tex); f.itemIcon:Show() else f.itemIcon:Hide() end

        -- Guild crafters (already synced locally).
        local guild = BRutus.RecipeTracker and BRutus.RecipeTracker:GetCraftersForItem(itemId)
        if guild then
            for _, c in ipairs(guild) do
                if not f.query.seen[c.playerName] then
                    f.query.seen[c.playerName] = true
                    AddResult(c.playerName, c.profName, L["Guild"], c.class)
                end
            end
        end

        -- Realm-wide: answers arrive over time.
        if BRutus.CraftNet then
            BRutus.CraftNet:Query(itemId, function(short, label)
                if not f.query or f.query.itemId ~= itemId then return end  -- stale
                if f.query.seen[short] then return end
                f.query.seen[short] = true
                AddResult(short, label, L["Realm"], nil)
                SetStatus()
            end)
            -- Close the "querying" state after the realm TTL so the status settles.
            if C_Timer and C_Timer.After then
                C_Timer.After((BRutus.CraftNet.TTL or 45) + 1, function()
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

    -- Input handling
    input:SetScript("OnTextChanged", function(self)
        placeholder:SetShown((self:GetText() or "") == "")
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
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
function BRutus:ShowCraftFinder(prefillItemId)
    local f = self.craftFinder or BuildFinder()
    self.craftFinder = f
    f:Show()
    f:Raise()
    if prefillItemId then
        f.RunQuery(prefillItemId)
    end
end
