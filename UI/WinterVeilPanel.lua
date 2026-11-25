----------------------------------------------------------------------
-- Guild OS - Winter Veil panel (issue #437; the site's specs/119)
-- Layout from the approved canvas: whom I drew and their list on the left, my own list on the right, the guild's
-- numbers on top; the officers' table of who is along (never a pair); the chain after the reveal. Visual layout
-- only: the data, the rules and the deliveries are GuildOS.WinterVeil's (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local ROW_H = 26
local SITE = "guildos.me"

local function gold(copper) return string.format("%dg", math.floor((copper or 0) / 10000 + 0.5)) end

local function nameOf(key)
    local short = type(key) == "string" and (key:match("^([^-]+)") or key) or "?"
    local rec = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    local cc = rec and rec.class and GuildOS.ClassColors and GuildOS.ClassColors[rec.class]
    if cc then return string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, short) end
    return short
end

local function wishName(w)
    if w.k == "gold" then return L["Gold"] end
    local P = GuildOS.ProfDirectory
    local name = P and P.RecipeName(w.recipe) or ("#" .. w.recipe)
    return (w.qty or 1) > 1 and (name .. " x" .. w.qty) or name
end

-- A pool of rows under `parent`, each a button with a name on the left, a value on the right and one action.
local function rowPool(parent)
    local rows = {}
    return function(i)
        local r = rows[i]
        if not r then
            r = CreateFrame("Button", nil, parent)
            r:SetHeight(ROW_H)
            r.text = UI:CreateText(r, "", 12, C.text.r, C.text.g, C.text.b)
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetJustifyH("LEFT")
            r.value = UI:CreateText(r, "", 11, C.text.r, C.text.g, C.text.b)
            r.action = UI:CreateButton(r, "", 70, ROW_H - 4)
            r.action:SetPoint("RIGHT", -2, 0)
            r.value:SetPoint("RIGHT", r.action, "LEFT", -8, 0)
            r.text:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
            r.sel = r:CreateTexture(nil, "BACKGROUND")
            r.sel:SetAllPoints()
            r.sel:SetColorTexture(C.popup.r, C.popup.g, C.popup.b, 1)
            rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        r.sel:Hide()
        r.action:Hide()
        r:SetScript("OnClick", nil)
        r:Show()
        return r
    end, function(from)
        for i = from, #rows do rows[i]:Hide() end
    end
end

local function siteLink()
    local key = GuildOS.Companion and GuildOS.Companion.GuildKey and GuildOS.Companion:GuildKey() or nil
    return key and string.format("%s/guild/%s/winter-veil", SITE, key) or (SITE .. "/winter-veil")
end

function GuildOS:CreateWinterVeilPanel(container)
    local WV = GuildOS.WinterVeil
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()
    local picked = {}

    -- Head: what the event is and where it stands.
    local title = UI:CreateTitle(panel, L["Winter Veil Secret Santa"], 18)
    title:SetPoint("TOPLEFT", 0, -4)
    local sub = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local chipGave = UI:CreateMetricChip(panel, "0", L["gifts delivered"])
    chipGave:SetPoint("TOPRIGHT", 0, -2)
    local chipIn = UI:CreateMetricChip(panel, "0", L["taking part"])
    chipIn:SetPoint("TOPRIGHT", chipGave, "TOPLEFT", -12, 0)

    local none = UI:CreateText(panel, L["The guild has not opened this year's Secret Santa yet. Officers open it on guildos.me."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    none:SetPoint("TOPLEFT", 0, -70)
    none:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    none:SetJustifyH("LEFT")

    -- Joining.
    local join = CreateFrame("Frame", nil, panel)
    join:SetPoint("TOPLEFT", 0, -70)
    join:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    join:SetHeight(80)
    local joinText = UI:CreateText(join, L["Join the Secret Santa: make a list of crafts or gold and give a gift to whoever you draw."], 12, C.text.r, C.text.g, C.text.b)
    joinText:SetPoint("TOPLEFT", 0, 0)
    local volunteer = UI:CreateCheckbox(join, L["I can give one more gift if somebody does not deliver"], 18)
    volunteer:SetPoint("TOPLEFT", 0, -24)
    local joinBtn = UI:CreateButton(join, L["Join"], 100, 26)
    joinBtn:SetPoint("TOPLEFT", 0, -50)
    UI:SetButtonVariant(joinBtn, "primary")

    -- The two columns.
    local left = UI:CreatePanel(panel)
    left:SetPoint("TOPLEFT", 0, -70)
    left:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -8, 0)
    local right = UI:CreatePanel(panel)
    right:SetPoint("TOPLEFT", panel, "TOP", 8, -70)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    local drewTitle = UI:CreateSectionTitle(left, L["WHO YOU DREW"], true)
    drewTitle:SetPoint("TOPLEFT", 12, -10)
    local drewWho = UI:CreateText(left, "", 14, C.text.r, C.text.g, C.text.b)
    drewWho:SetPoint("TOPLEFT", 12, -34)
    local drewNote = UI:CreateText(left, "", 11, C.label.r, C.label.g, C.label.b)
    drewNote:SetPoint("TOPLEFT", 12, -54)
    drewNote:SetPoint("RIGHT", left, "RIGHT", -12, 0)
    drewNote:SetJustifyH("LEFT")
    local drewList = CreateFrame("Frame", nil, left)
    drewList:SetPoint("TOPLEFT", 12, -80)
    drewList:SetPoint("RIGHT", left, "RIGHT", -12, 0)
    drewList:SetHeight(ROW_H * 8)
    local drewRow, drewHide = rowPool(drewList)
    local giveBtn = UI:CreateButton(left, "", 180, 28)
    giveBtn:SetPoint("BOTTOMLEFT", 12, 12)
    UI:SetButtonVariant(giveBtn, "primary")

    local listTitle = UI:CreateSectionTitle(right, L["WHAT YOU WANT"], true)
    listTitle:SetPoint("TOPLEFT", 12, -10)
    local capText = UI:CreateText(right, "", 11, C.label.r, C.label.g, C.label.b)
    capText:SetPoint("TOPLEFT", 12, -34)
    local capBar = UI:CreateProgressBar(right, 200, 6)
    capBar:SetPoint("TOPLEFT", 12, -50)
    capBar:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    local myList = CreateFrame("Frame", nil, right)
    myList:SetPoint("TOPLEFT", 12, -64)
    myList:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    myList:SetHeight(ROW_H * 8)
    local myRow, myHide = rowPool(myList)
    local goldBox = UI:CreateInput(right, 70, 22, { numeric = true, max = 6, placeholder = L["gold"] })
    goldBox:SetPoint("BOTTOMLEFT", 12, 72)
    local goldBtn = UI:CreateButton(right, L["Gold instead"], 110, 22)
    goldBtn:SetPoint("LEFT", goldBox, "RIGHT", 8, 0)
    local search = UI:CreateInput(right, 200, 22, { placeholder = L["Search a recipe somebody in the guild makes"] })
    search:SetPoint("BOTTOMLEFT", 12, 42)
    search:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    local status = UI:CreateText(right, "", 11, C.label.r, C.label.g, C.label.b)
    status:SetPoint("BOTTOMLEFT", 12, 14)
    status:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    status:SetJustifyH("LEFT")

    -- The officers' table and the chain share one list below the head when there is no entry of mine to show.
    local board = UI:CreatePanel(panel)
    board:SetPoint("TOPLEFT", 0, -70)
    board:SetPoint("BOTTOMRIGHT", 0, 0)
    local boardTitle = UI:CreateSectionTitle(board, "", true)
    boardTitle:SetPoint("TOPLEFT", 12, -10)
    local boardNote = UI:CreateText(board, "", 11, C.label.r, C.label.g, C.label.b)
    boardNote:SetPoint("TOPLEFT", 12, -32)
    boardNote:SetPoint("RIGHT", board, "RIGHT", -12, 0)
    boardNote:SetJustifyH("LEFT")
    local boardList = CreateFrame("Frame", nil, board)
    boardList:SetPoint("TOPLEFT", 12, -56)
    boardList:SetPoint("BOTTOMRIGHT", -12, 12)
    local boardRow, boardHide = rowPool(boardList)
    local officerBtn = UI:CreateButton(panel, L["Organize"], 90, 22)
    officerBtn:SetPoint("TOPRIGHT", chipIn, "TOPLEFT", -12, 0)
    local showBoard = false
    local scanFor

    local function draw()
        local e = WV:Event()
        local t = GetServerTime()
        local phase = WV.PhaseOf(e, t)
        none:SetShown(not e)
        chipGave:SetShown(e ~= nil)
        chipIn:SetShown(e ~= nil)
        officerBtn:SetShown(e ~= nil and GuildOS:IsOfficer())
        if not e then
            title:SetText(L["Winter Veil Secret Santa"])
            sub:SetText("")
            join:Hide(); left:Hide(); right:Hide(); board:Hide()
            return
        end
        local days = math.max(0, math.floor((e.revealAt - t) / 86400))
        sub:SetText(phase == "revealed" and L["Revealed"]
            or string.format(L["Reveal in %d day(s) · cap %s"], days, gold(e.cap)))
        chipGave:SetValue(string.format("%d/%d", e.counts.delivered, math.max(e.counts.pairs, e.counts.entrants)))
        chipIn:SetValue(tostring(e.counts.entrants))

        local entry = WV:MyEntry()
        local s = WV._store()
        local me = WV:MyKey()
        local joined = entry ~= nil or (s and me and s.people[me] and s.people[me].join ~= nil)

        -- The chain after the reveal, or the officers' table when they ask for it.
        if phase == "revealed" or showBoard then
            join:Hide(); left:Hide(); right:Hide(); board:Show()
            local i = 0
            if phase == "revealed" and e.reveal then
                boardTitle:SetText(L["THE GUILD'S CHAIN"])
                boardNote:SetText("")
                for _, r in ipairs(e.reveal) do
                    i = i + 1
                    local row = boardRow(i)
                    row.text:SetText(nameOf(r.giver) .. "  >  " .. nameOf(r.to))
                    local g = r.gift
                    local what = g and (g.recipe and wishName({ k = "item", recipe = g.recipe, qty = g.qty or 1 }) or gold(g.copper)) or L["not delivered"]
                    if r.lostBy then what = what .. "  " .. string.format(L["(reassigned from %s)"], nameOf(r.lostBy)) end
                    row.value:SetText(what)
                end
            else
                boardTitle:SetText(L["PARTICIPANTS"])
                boardNote:SetText(string.format(L["Nobody sees the pairs, officers included. The rules and the draw are on the site: %s"], siteLink()))
                for _, r in ipairs(e.entrants or {}) do
                    i = i + 1
                    local row = boardRow(i)
                    row.text:SetText(nameOf(r.key))
                    row.value:SetText((r.list and L["list ready"] or L["no list yet"]) .. "   " .. (r.gave and L["delivered"] or L["not delivered yet"]))
                end
            end
            boardHide(i + 1)
            return
        end
        board:Hide()

        if not joined then
            left:Hide(); right:Hide()
            join:SetShown(phase == "joining")
            if phase ~= "joining" then
                none:SetText(L["Joining has closed."])
                none:Show()
            end
            return
        end
        join:Hide(); left:Show(); right:Show()

        -- Left: whom I drew, their list, and what giving it takes.
        local gives = WV:MyGives()
        local g = gives[1]
        local i = 0
        if not g then
            drewWho:SetText("")
            drewNote:SetText(e.drawn and L["Your pair has not reached this client yet: it comes with the companion, or from a guildmate who has it."]
                or L["The draw happens after joining closes."])
            giveBtn:Hide()
        else
            drewWho:SetText(nameOf(g.to) .. (g.delivered and ("  |cff7dd88f" .. L["delivered"] .. "|r") or ""))
            drewNote:SetText(#g.wishes == 0 and L["No list yet."] or L["Pick a gift. A mail or a trade to them is recorded on its own."])
            for idx, w in ipairs(g.wishes) do
                i = i + 1
                local row = drewRow(i)
                row.text:SetText(wishName(w))
                local c = w.copper or WV.WishWorth(w, function(r) return WV:PriceOf(r) end)
                row.value:SetText(c and ("~" .. gold(c)) or L["no price"])
                if picked[g.to] == idx then row.sel:Show() end
                row:SetScript("OnClick", function() picked[g.to] = idx; GuildOS:SafeCall(draw) end)
            end
            local w = picked[g.to] and g.wishes[picked[g.to]]
            giveBtn:SetShown(w ~= nil and not g.delivered)
            if w and w.k == "gold" then
                giveBtn:SetText(string.format(L["Mail %s"], gold(w.copper)))
                giveBtn:SetScript("OnClick", function()
                    GuildOS.Compat.ShowSendMail()
                    GuildOS.Compat.FillSendMail(g.to:match("^([^-]+)") or g.to, L["Winter Veil"], w.copper)
                end)
            elseif w then
                local item = WV.ProductOf(w.recipe)
                giveBtn:SetText(L["Place a craft order"])
                giveBtn:SetScript("OnClick", function()
                    if item and GuildOS.ShowCraftOrderDialog then GuildOS:ShowCraftOrderDialog(item) end
                end)
            end
        end
        drewHide(i + 1)

        -- Right: my list.
        local list = WV:MyList()
        local worst = 0
        i = 0
        for idx, w in ipairs(list) do
            i = i + 1
            local row = myRow(i)
            row.text:SetText(wishName(w))
            local c = WV.WishWorth(w, function(r) return WV:PriceOf(r) end)
            worst = math.max(worst, c or 0)
            row.value:SetText(c and ("~" .. gold(c)) or L["no price"])
            if phase ~= "revealed" then
                row.action:SetText(L["Remove"])
                row.action:Show()
                row.action:SetScript("OnClick", function()
                    local next = {}
                    for j, x in ipairs(list) do if j ~= idx then next[#next + 1] = x end end
                    local ok, why = WV:SetList(next)
                    if not ok then GuildOS:Print(L["Winter Veil: "] .. tostring(why)) end
                    GuildOS:SafeCall(draw)
                end)
            end
        end
        -- Search results under the list, while somebody is typing.
        local q = search:GetText() or ""
        if q ~= "" and e.kind ~= "gold" and GuildOS.ProfDirectory then
            local rows = GuildOS.ProfDirectory.RecipeRows(nil, "guild", q)
            -- Prices are read (and shared with the guild) once a search is committed with Enter, never per keystroke.
            if scanFor == q then
                scanFor = nil
                local recipes = {}
                for n = 1, math.min(#rows, 6) do recipes[#recipes + 1] = rows[n].id end
                WV:ScanPrices(recipes)
            end
            for n = 1, math.min(#rows, 6) do
                local r = rows[n]
                i = i + 1
                local row = myRow(i)
                row.text:SetText("|cff97909f+|r " .. r.name)
                local c = WV:PriceOf(r.id)
                row.value:SetText(c and ("~" .. gold(c)) or L["no price"])
                row.action:SetText(L["Add"])
                row.action:Show()
                row.action:SetScript("OnClick", function()
                    local next = {}
                    for _, x in ipairs(list) do next[#next + 1] = x end
                    next[#next + 1] = { k = "item", recipe = r.id, qty = 1 }
                    local ok, why = WV:SetList(next)
                    if not ok then GuildOS:Print(L["Winter Veil: "] .. tostring(why)) end
                    search:SetText("")
                    GuildOS:SafeCall(draw)
                end)
            end
        end
        myHide(i + 1)
        capText:SetText(string.format(L["Each option fits the cap: highest %s of %s"], gold(worst), gold(e.cap)))
        capBar:SetProgress(math.min(1, worst / e.cap))
        goldBox:SetShown(e.kind ~= "item" and phase ~= "revealed")
        goldBtn:SetShown(e.kind ~= "item" and phase ~= "revealed")
        search:SetShown(e.kind ~= "gold" and phase ~= "revealed")
        status:SetText(entry and entry.got and L["Your gift arrived."] or L["Your gift has not arrived yet."])
    end

    joinBtn:SetScript("OnClick", function()
        WV:Join(volunteer.checkbox:GetChecked())
        GuildOS:SafeCall(draw)
    end)
    goldBtn:SetScript("OnClick", function()
        local e = WV:Event()
        local n = tonumber(goldBox:GetText())
        local next = {}
        for _, x in ipairs(WV:MyList()) do if x.k ~= "gold" then next[#next + 1] = x end end
        if n and n > 0 then next[#next + 1] = { k = "gold", copper = math.floor(n) * 10000 } end
        if e and e.kind == "gold" then next = n and n > 0 and { { k = "gold", copper = math.floor(n) * 10000 } } or {} end
        local ok, why = WV:SetList(next)
        if not ok then GuildOS:Print(L["Winter Veil: "] .. tostring(why)) end
        GuildOS:SafeCall(draw)
    end)
    search:HookScript("OnTextChanged", function() GuildOS:SafeCall(draw) end)
    search:HookScript("OnEnterPressed", function() scanFor = search:GetText(); GuildOS:SafeCall(draw) end)
    officerBtn:SetScript("OnClick", function() showBoard = not showBoard; GuildOS:SafeCall(draw) end)

    panel.Draw = draw
    panel:SetScript("OnShow", function() GuildOS:SafeCall(draw) end)
    return panel
end
