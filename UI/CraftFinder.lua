----------------------------------------------------------------------
-- Guild OS - Search the realm (the Workshop's screen, #449)
-- Who crafts an item, the guild's crafters first. A screen of the Crafts tab, not a popup: on the left a
-- parchment card with the item (shift-clicked, its id, or its name picked from the names the client knows),
-- the item chosen and who answered; on the right a dark card that says how the search works. Guild crafters
-- are known at once (RecipeTracker); the alliance's come from guildos.me's directory; the realm's trickle in
-- over the Chehul mesh (GuildOS.CraftNet) as each player running Guild OS answers for itself.
--
-- GuildOS:ShowCraftFinder(itemId) and /gos craft open the Workshop on it, the item filled in. The data half
-- (ResolveItemId, Suggest) is frame-free: tools/crafts-tab.lua tests it and drives the screen.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local CraftFinder = {}
GuildOS.CraftFinder = CraftFinder

local ROW_H      = 26
local MAX_ROWS   = 60      -- results drawn at most; the rest counted
local SUGGEST_N  = 8
local HOW_W      = 300
local TWO_COLS   = 760     -- from this width the "How it works" card sits beside the search
local CARD_PAD   = UI.SP.PAD
local CARD_TOP   = UI.SP.TOP
local WHITE8     = "Interface\\Buttons\\WHITE8x8"
local QUESTION   = "Interface\\Icons\\INV_Misc_QuestionMark"

----------------------------------------------------------------------
-- Data (frame-free)
----------------------------------------------------------------------

-- An item:12345 link, a raw id or an [item] hyperlink: the item id; nil for anything else (a name).
function CraftFinder.ResolveItemId(text)
    if not text or text == "" then return nil end
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    return tonumber((text:gsub("%s", "")):match("^(%d+)$"))
end

-- Names the client knows: every item the professions catalog makes (its name from the item cache, else the
-- recipe's), the recipes the guild shared (Anniversary) and any item this screen looked up. id -> name.
CraftFinder.known = {}
function CraftFinder.Remember(id, name)
    id = tonumber(id)
    if id and type(name) == "string" and name ~= "" then CraftFinder.known[id] = name end
end

-- The catalog's part, built once per catalog: the recipe's own name (a crafted item's is the item's), never an
-- item lookup (asking the client for two thousand uncached items would send as many queries to the server).
local catIndex, catFor
local function index()
    local out = {}
    local cat, D = GuildOS.ProfCatalog, GuildOS.ProfDirectory
    if cat and cat.recipes and cat.F and D and D.RecipeName then
        if catFor ~= cat then
            catIndex, catFor = {}, cat
            for rid, r in pairs(cat.recipes) do
                local item = r[cat.F.out]
                if item and item > 0 and not catIndex[item] then
                    local ok, rn = pcall(D.RecipeName, rid)
                    if ok and type(rn) == "string" and rn ~= "" then catIndex[item] = rn end
                end
            end
        end
        for id, n in pairs(catIndex) do out[id] = n end
    end
    local RT = GuildOS.RecipeTracker
    if RT and RT.Search and not D then
        local ok, list = pcall(RT.Search, RT, "", "All")
        for _, e in ipairs(ok and list or {}) do
            if e.itemId and e.name then out[e.itemId] = e.name end
        end
    end
    -- The names the item cache gave this screen win: they are the item's own.
    for id, n in pairs(CraftFinder.known) do out[id] = n end
    return out
end

-- Up to `max` items whose name holds `text` (case-insensitive, two letters at least): those that start with
-- it first, then by name. { { id, name } }.
function CraftFinder.Suggest(text, max)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #text < 2 or CraftFinder.ResolveItemId(text) then return {} end
    local q = text:lower()
    local hits = {}
    for id, name in pairs(index()) do
        local low = name:lower()
        local at = low:find(q, 1, true)
        if at then hits[#hits + 1] = { id = id, name = name, starts = at == 1 } end
    end
    table.sort(hits, function(a, b)
        if a.starts ~= b.starts then return a.starts end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, math.min(#hits, max or SUGGEST_N) do out[i] = hits[i] end
    return out
end

-- A guild crafter's skill in the profession named (English) `profEn`, from the professions model (Forever).
local function skillOf(key, profEn)
    local P, cat = GuildOS.Professions, GuildOS.ProfCatalog
    if not (key and P and P.Get and cat and cat.professions) then return nil end
    local rec = P:Get(key)
    for line, e in pairs(rec and rec.profs or {}) do
        local p = cat.professions[line]
        if p and p.en == profEn then return e.rank end
    end
end

----------------------------------------------------------------------
-- The screen
----------------------------------------------------------------------
local function hex(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

function GuildOS:CreateRealmSearch(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()

    local card = UI:CreateCard(f, L["Search the realm"])
    local how = UI:CreateCard(f, L["How it works"], { dark = true })
    f.card, f.how = card, how

    -- The item: shift-click one, type its id, or its name and pick it from the list.
    local input = UI:CreateInput(card, 300, 26, { placeholder = L["Shift-click an item, or type its name or id"], max = 100 })
    input:SetPoint("TOPLEFT", CARD_PAD, -CARD_TOP)
    input:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    f.input = input

    local suggest = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI:PaintMenu(suggest)
    suggest:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -2)
    suggest:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, -2)
    suggest:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
    suggest:Hide()
    suggest.rows = {}
    f.suggest = suggest

    -- The item chosen: its icon framed in its quality, its name in the paper's quality ink, and the order to
    -- every guild crafter of it.
    local itemIcon = UI:CreateIcon(card, 22)
    itemIcon:SetPoint("TOPLEFT", CARD_PAD, -(CARD_TOP + 36))
    itemIcon:Hide()
    local itemName = UI:CreateText(card, "", 14)
    itemName:SetPoint("LEFT", itemIcon, "RIGHT", 8, 0)
    itemName:SetJustifyH("LEFT"); itemName:SetWordWrap(false)
    local orderAll = UI:SetButtonVariant(UI:CreateButton(card, L["Order from the guild"], 150, 22), "primary")
    orderAll:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_TOP + 36))
    orderAll:Hide()
    itemName:SetPoint("RIGHT", orderAll, "LEFT", -8, 0)
    orderAll:SetScript("OnClick", function()
        if f.query and GuildOS.ShowCraftFor then GuildOS:ShowCraftFor(f.query.itemId) end
    end)
    f.itemIcon, f.itemName, f.orderAll = itemIcon, itemName, orderAll

    local status = UI:CreateText(card, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    status:SetPoint("TOPLEFT", CARD_PAD, -(CARD_TOP + 68))
    status:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    status:SetJustifyH("LEFT")
    f.status = status

    -- The results: Crafter, Profession, Where, and the row's links.
    local header = UI:CreateTableHeader(card, 22)
    header:SetPoint("TOPLEFT", CARD_PAD, -(CARD_TOP + 88))
    header:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_TOP + 88))
    local hName = UI:CreateHeaderText(header, L["Crafter"], UI.SP.META)
    local hProf = UI:CreateHeaderText(header, L["Profession"], UI.SP.META)
    local hWhere = UI:CreateHeaderText(header, L["Where"], UI.SP.META)
    for _, h in ipairs({ hName, hProf, hWhere }) do h:SetJustifyH("LEFT"); h:SetWordWrap(false) end
    f.header = header

    local scroll, list = UI:CreateScrollFrame(card, nil)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -(CARD_PAD - 4), CARD_PAD)
    list.__paper = true
    f.scroll, f.list = scroll, list

    local empty = UI:CreateText(list, "", 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    empty:SetPoint("TOPLEFT", 4, -12)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)
    f.empty = empty

    -- The columns, laid at the list's width.
    local cols = { name = 0, prof = 0, where = 0, w = 300 }
    local function columns(w)
        w = math.max(260, w)
        local actions = 120
        cols.w = w
        cols.name = 18
        cols.prof = math.floor(18 + (w - 18 - actions) * 0.42)
        cols.where = math.floor(18 + (w - 18 - actions) * 0.72)
        cols.actions = w - actions
        hName:ClearAllPoints(); hName:SetPoint("LEFT", cols.name, 0)
        hProf:ClearAllPoints(); hProf:SetPoint("LEFT", cols.prof, 0)
        hWhere:ClearAllPoints(); hWhere:SetPoint("LEFT", cols.where, 0)
    end
    columns(300)

    f.rows = {}
    local function row(i)
        local r = f.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, list)
        r:SetHeight(ROW_H)
        r.rule = UI:CreateSeparator(r)
        r.rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
        r.rule:SetPoint("BOTTOMLEFT", 0, 0)
        r.rule:SetPoint("BOTTOMRIGHT", 0, 0)
        -- Online: a drawn dot (the fonts have no bullet glyph).
        r.dot = r:CreateTexture(nil, "OVERLAY")
        r.dot:SetTexture(WHITE8)
        r.dot:SetSize(6, 6)
        r.dot:SetPoint("LEFT", 4, 0)
        r.name = UI:CreateText(r, "", 12)
        r.prof = UI:CreateText(r, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        r.where = UI:CreateText(r, "", 11)
        for _, fs in ipairs({ r.name, r.prof, r.where }) do fs:SetJustifyH("LEFT"); fs:SetWordWrap(false) end
        r.whisper = UI:SetButtonVariant(UI:CreateButton(r, L["Whisper"], 50, 18), "ghost")
        r.whisper:SetWidth(math.ceil(r.whisper.label:GetStringWidth() or 40) + 4)
        r.whisper:SetPoint("RIGHT", -2, 0)
        -- A guild crafter takes an order sent to them alone (issue #389).
        r.order = UI:SetButtonVariant(UI:CreateButton(r, L["Order"], 40, 18), "ghost")
        r.order:SetWidth(math.ceil(r.order.label:GetStringWidth() or 30) + 4)
        r.order:SetPoint("RIGHT", r.whisper, "LEFT", -10, 0)
        f.rows[i] = r
        return r
    end

    local function placeRow(r, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", cols.name, 0); r.name:SetWidth(math.max(30, cols.prof - cols.name - 8))
        r.prof:ClearAllPoints(); r.prof:SetPoint("LEFT", cols.prof, 0); r.prof:SetWidth(math.max(30, cols.where - cols.prof - 8))
        r.where:ClearAllPoints(); r.where:SetPoint("LEFT", cols.where, 0); r.where:SetWidth(math.max(30, cols.actions - cols.where - 6))
    end

    local function paintEmpty()
        local q = f.query
        local msg
        if not q then
            msg = L["Choose an item above: who crafts it shows here, the guild first."]
        elseif q.count == 0 and q.done then
            msg = L["Nobody answered for this item. A crafter has to be online with Guild OS to answer."]
        elseif q.count == 0 then
            msg = L["Nobody in the guild crafts this. Waiting for the realm's answers…"]
        end
        empty:SetWidth(math.max(120, cols.w - 8))
        empty:SetText(msg or "")
        empty:SetShown(msg ~= nil)
        header:SetShown(q ~= nil and q.count > 0)
    end

    local function setStatus()
        local q = f.query
        if not q then status:SetText(""); return end
        local txt
        if q.done then
            txt = string.format(L["%d crafter(s) found"], q.count)
        else
            txt = string.format(L["Searching the realm… %d answered"], q.answered)
        end
        if q.overflow > 0 then txt = txt .. string.format(L[" (+%d more)"], q.overflow) end
        status:SetText(txt)
    end

    -- One crafter. `where`: "guild", "ally" (with `guild`, their guild's name) or "realm". `key`: a guild member's
    -- key (the order goes to them). `whisperTo`: who the whisper goes to when it is not `name`.
    local function addResult(c)
        local q = f.query
        if not q or q.seen[c.name] then return end
        q.seen[c.name] = true
        q.count = q.count + 1
        if q.count > MAX_ROWS then q.overflow = q.overflow + 1; return end
        local r = row(q.count)
        placeRow(r, q.count)
        local cr, cg, cb = UI:InkFor("paper", "class", c.class)
        if not c.class then cr, cg, cb = C.paperInk.r, C.paperInk.g, C.paperInk.b end
        r.name:SetText(c.name)
        r.name:SetTextColor(cr, cg, cb)
        local okc = UI.STATUS_INK and UI.STATUS_INK.ok or C.ok
        r.dot:SetVertexColor(okc.r, okc.g, okc.b, 1)
        -- A realm crafter answered: online by definition. A guild member's state is the roster's.
        r.dot:SetShown(c.online ~= false)
        local prof = c.prof and L[c.prof] or ""
        if c.skill then prof = prof .. "  |cff" .. hex(C.paperInk) .. c.skill .. "|r" end
        r.prof:SetText(prof)
        local where, wink = L["Realm"], C.paperSoft
        if c.where == "guild" then where, wink = L["Guild"], C.paperInk
        elseif c.where == "ally" then where = c.guild or L["Alliance"] end
        r.where:SetText(where)
        r.where:SetTextColor(wink.r, wink.g, wink.b)
        local itemId = q.itemId
        local me = GuildOS.CraftOrders and GuildOS.CraftOrders:MyKey()
        r.order:SetShown(c.key ~= nil and c.key ~= me and GuildOS.ShowCraftFor ~= nil)
        r.order:SetScript("OnClick", function() GuildOS:ShowCraftFor(itemId, c.key) end)
        r.whisper:SetShown(c.key == nil or c.key ~= me)
        r.whisper:SetScript("OnClick", function()
            local link = itemId and select(2, GuildOS.Compat.GetItemInfo(itemId))
            local subject = link or (f.itemName:GetText() ~= "" and f.itemName:GetText()) or L["this item"]
            if ChatFrame_OpenChat then
                ChatFrame_OpenChat("/w " .. GuildOS:WhisperTarget(c.whisper or c.name) .. " " .. string.format(L["Can you craft %s?"], subject))
            end
        end)
        r:Show()
        list:SetHeight(math.max(1, math.min(q.count, MAX_ROWS) * ROW_H + 8))
        paintEmpty()
    end
    f.AddResult = addResult

    -- A fresh search for itemId.
    function f.RunQuery(itemId)
        itemId = tonumber(itemId)
        if not itemId then return end
        f.query = { itemId = itemId, seen = {}, count = 0, overflow = 0, answered = 0, done = false }
        for _, r in ipairs(f.rows) do r:Hide() end
        scroll:SetVerticalScroll(0)
        suggest:Hide()

        local name, _, quality, _, _, _, _, _, _, tex = GuildOS.Compat.GetItemInfo(itemId)
        CraftFinder.Remember(itemId, name)
        itemName:SetText(name or ("item:" .. itemId))
        itemName:SetTextColor(UI:InkFor("paper", "quality", quality or 1))
        itemIcon.icon:SetTexture(tex or QUESTION)
        UI:SetIconQuality(itemIcon, quality or 1)
        itemIcon:Show()

        -- The guild's crafters, known here already.
        local guild = GuildOS.RecipeTracker and GuildOS.RecipeTracker:GetCraftersForItem(itemId)
        orderAll:SetShown(guild ~= nil and GuildOS.ShowCraftFor ~= nil)
        local who = GuildOS.ProfDirectory and GuildOS.ProfDirectory.Roster and GuildOS.ProfDirectory.Roster() or {}
        local guildList = {}
        for _, c in ipairs(guild or {}) do
            local w = c.playerKey and who[c.playerKey]
            local online = c.isOnline
            if online == nil and w then online = w.online end
            guildList[#guildList + 1] = { name = c.playerName, prof = c.profName, class = c.class or (w and w.class),
                key = c.playerKey, where = "guild", online = online ~= false, skill = skillOf(c.playerKey, c.profName) }
        end
        table.sort(guildList, function(a, b)
            if a.online ~= b.online then return a.online end
            return (a.name or "") < (b.name or "")
        end)
        for _, c in ipairs(guildList) do addResult(c) end

        -- The alliance: guildos.me's directory, so an allied crafter is found even while offline.
        local A = GuildOS.Alliance
        if A and A:Get() then
            for _, c in ipairs(A:FindCrafters(itemId)) do
                addResult({ name = c.name, prof = c.prof, class = c.class, where = "ally", guild = c.guild,
                            online = c.online, whisper = c.whisper })
            end
        end

        -- The realm: answers arrive over a few seconds.
        local net = GuildOS.CraftNet
        if net and net.Query and net:Query(itemId, function(short, label)
            local q = f.query
            if not q or q.itemId ~= itemId then return end   -- an older search
            q.answered = q.answered + 1
            addResult({ name = short, prof = label, where = "realm" })
            setStatus()
        end) then
            GuildOS.Compat.After((net.TTL or 45) + 1, function()
                if f.query and f.query.itemId == itemId then
                    f.query.done = true
                    setStatus()
                    paintEmpty()
                end
            end)
        else
            f.query.done = true
        end
        setStatus()
        paintEmpty()
    end

    -- The suggestions under the field while a name is typed.
    local function pick(id)
        input:SetText("")
        input:ClearFocus()
        f.RunQuery(id)
    end
    local function paintSuggest(text)
        local hits = CraftFinder.Suggest(text, SUGGEST_N)
        for _, r in ipairs(suggest.rows) do r:Hide() end
        if #hits == 0 then suggest:Hide(); return end
        for i, h in ipairs(hits) do
            local r = suggest.rows[i]
            if not r then
                r = UI:MenuRow(suggest, 22)
                r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
                r:SetPoint("RIGHT", suggest, "RIGHT", -4, 0)
                suggest.rows[i] = r
            end
            r.label:SetText(h.name)
            r:SetScript("OnClick", function() pick(h.id) end)
            r:Show()
        end
        suggest.hits = hits
        suggest:SetHeight(#hits * 22 + 8)
        suggest:Show()
    end
    input:HookScript("OnTextChanged", function(self, user)
        if user == false then return end
        paintSuggest(self:GetText())
    end)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local id = CraftFinder.ResolveItemId(text)
        if not id and suggest:IsShown() and suggest.hits and suggest.hits[1] then id = suggest.hits[1].id end
        if id then pick(id) else self:ClearFocus() end
    end)
    input:HookScript("OnEditFocusLost", function()
        GuildOS.Compat.After(0.2, function() if not input:HasFocus() then suggest:Hide() end end)
    end)

    -- How it works: four steps, each a numbered disc and a line.
    local STEPS = {
        L["Guild crafters show at once: the guild's data already knows who makes what."],
        L["In an alliance, its guilds' crafters come from guildos.me, online or not."],
        L["Other players on the realm running Guild OS answer for themselves while online. Answers arrive over a few seconds, and only who answered shows."],
        L["Nothing is posted in public chat: the question travels hidden, addon to addon."],
    }
    how.steps = {}
    for i, t in ipairs(STEPS) do
        local g = UI:CreateGlyph(how, 22)
        g:Set(tostring(i), C.gold2)
        local fs = UI:CreateText(how, t, 12, C.text.r, C.text.g, C.text.b)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        how.steps[i] = { glyph = g, text = fs }
    end

    function f:Relayout(w)
        w = w or UI:LaidWidth(parent)
        if not w or w < 1 then return end
        local two = w >= TWO_COLS
        card:ClearAllPoints()
        how:ClearAllPoints()
        local cardW
        if two then
            cardW = w - 20 - HOW_W - 12
            card:SetPoint("TOPLEFT", 10, -8)
            card:SetPoint("BOTTOMLEFT", 10, 10)
            card:SetWidth(cardW)
            how:SetPoint("TOPRIGHT", -10, -8)
            how:SetWidth(HOW_W)
        else
            cardW = w - 20
            how:SetPoint("BOTTOMLEFT", 10, 10)
            how:SetPoint("BOTTOMRIGHT", -10, 10)
        end
        local inner = (two and HOW_W or (w - 20)) - 2 * CARD_PAD
        local y = CARD_TOP + 2
        for _, s in ipairs(how.steps) do
            s.glyph:ClearAllPoints()
            s.glyph:SetPoint("TOPLEFT", CARD_PAD, -y)
            s.text:ClearAllPoints()
            s.text:SetPoint("TOPLEFT", CARD_PAD + 32, -(y + 3))
            s.text:SetWidth(math.max(80, inner - 32))
            y = y + math.max(26, math.ceil(s.text:GetStringHeight() or 14) + 10)
        end
        how:SetHeight(y + CARD_PAD - 6)
        if not two then
            card:SetPoint("TOPLEFT", 10, -8)
            card:SetPoint("BOTTOMRIGHT", how, "TOPRIGHT", 0, 12)
        end
        columns(cardW - 2 * CARD_PAD - 14)
        list:SetWidth(math.max(1, cardW - 2 * CARD_PAD - 14))
        if f.query then
            for i, r in ipairs(f.rows) do if i <= math.min(f.query.count, MAX_ROWS) then placeRow(r, i) end end
        end
        paintEmpty()
    end
    UI:MakeResponsive(parent, function(_, w) f:Relayout(w) end)

    -- Shift-click an item anywhere while the screen shows: it is searched.
    if HandleModifiedItemClick and hooksecurefunc then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not f:IsVisible() or not IsShiftKeyDown() or type(link) ~= "string" then return end
            local id = tonumber(link:match("item:(%d+)"))
            if id then pick(id) end
        end)
    end

    setStatus()
    paintEmpty()
    GuildOS.craftFinder = f
    return f
end

----------------------------------------------------------------------
-- Public entry: the Workshop's Search the realm, on an item when one is given.
----------------------------------------------------------------------
function GuildOS:ShowCraftFinder(prefillItemId)
    return UI:OpenWindow("recipes", "realm", tonumber(prefillItemId))
end
