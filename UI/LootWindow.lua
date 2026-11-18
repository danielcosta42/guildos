----------------------------------------------------------------------
-- Guild OS - Loot window (issue #346)
-- One tab, four sub-tabs: Rule · Accounts · Lists · History. Every member opens it: an officer edits
-- the rule and the accounts, a raider reads the rule as players will read it and their own balances.
-- The rule and its settings are edited here and nowhere else (Settings and the core's Config tab
-- point here). Visual layer only: every change goes through LootRule, LootMaster, Points and
-- CoreManager, which keep the same keys as always.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local SUB_H      = 28    -- the sub-tab bar
-- Between blocks, and under the sub-tab bar before a screen's first line (#371). A number even where a
-- test stands in for the UI.
local GAP        = tonumber(UI.GAP) or 8
local FIELD_H    = 28    -- a form's line
local LABEL_GAP  = 12    -- between the widest label and its field
local LABEL_MIN  = 180   -- the field column never starts before this
-- A screen's content ends GAP short of its panel's right edge. A scroll child stops UI.SCROLL_GUTTER
-- short of its frame (BindScrollChildWidth), so a scroll frame's right edge sits SCROLL_R from the
-- panel's: its rows then end where the toolbars over them do, and nothing runs under the bar (#371).
local GUTTER     = tonumber(UI.SCROLL_GUTTER) or 12
local SCROLL_R   = GUTTER - GAP
local HEAD_ABOVE = 20    -- room over a later section title for its rule (UI:CreateSectionTitle)
local HEAD_H     = 26    -- a section title's line and the space under it
local TOOLBAR_H  = 22    -- a row of buttons over a list
local MODEL_ROW_H = 24
local MODEL_GAP   = 4

-- An edit box: the shared field (#371), whose border turns gold while it has the keyboard.
local function input(parent, width, numeric, maxLetters)
    return UI:CreateInput(parent, width, 22, { numeric = numeric and true or nil, max = maxLetters or 64 })
end

-- The cores a selector offers, the guild first.
local function scopeOptions()
    local opts = { { value = "", text = L["The guild"] } }
    local CM = GuildOS.CoreManager
    for _, name in ipairs(CM and CM:GetSortedNames() or {}) do opts[#opts + 1] = { value = name, text = name } end
    return opts
end

-- The core a selector starts on: the raid's active core when it is one, else the guild.
function GuildOS:DefaultLootScope()
    local CM = self.CoreManager
    local active = CM and CM:GetActiveName() or ""
    if active ~= "" and self.db and self.db.cores and self.db.cores[active] then return active end
    return ""
end
GuildOS.LootScopeOptions = scopeOptions

-- A section title (#371): the shared one, at the content's left edge. A later one leaves HEAD_ABOVE
-- over itself for its rule. Returns the y under it.
local function sectionTitle(content, text, y, first)
    if not first then y = y + HEAD_ABOVE end
    local t = UI:CreateSectionTitle(content, text, first)
    t:SetPoint("TOPLEFT", 0, -y)
    return y + HEAD_H
end

-- Where the fields of a form start: past its widest label, never before LABEL_MIN (#371: one column
-- for the whole form; the settings started at one x, the rule's rows at another).
local function labelColumn(content, texts)
    local widths = {}
    for i, text in ipairs(texts) do
        local probe = UI:CreateText(content, text, 12)
        widths[i] = probe:GetStringWidth() or 0
        probe:Hide()
    end
    return UI.LabelColumn(widths, 0, LABEL_GAP, LABEL_MIN)
end

-- A form's label: the left column, in the text colour (#371).
local function formLabel(content, text, y)
    local t = UI:CreateText(content, text, 12, C.text.r, C.text.g, C.text.b)
    t:SetPoint("TOPLEFT", 0, -(y + 4))
    return t
end

-- A secondary line beside a field (a range, what an empty box means).
local function hint(content, text, after)
    local t = UI:CreateText(content, text, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    t:SetPoint("LEFT", after, "RIGHT", 8, 0)
    return t
end

-- The labels of the rule's own rows, as BuildLootRuleEditor draws them: the form's one label column is
-- measured on these and the settings' together.
local function ruleLabels(rule)
    local LR = GuildOS.LootRule
    local out = { L["Time to answer (seconds):"] }
    if LR:HasBids(rule) then
        out[#out + 1] = L["Bids:"]
        out[#out + 1] = L["Minimum bid:"]
        out[#out + 1] = L["Bid step:"]
        out[#out + 1] = L["The winner pays:"]
    end
    for _, a in ipairs(LR:Counters(rule)) do out[#out + 1] = string.format(L["Counter %s starts over:"], a.name or a.key) end
    out[#out + 1] = L["Who decides:"]
    if GuildOS.LootCouncil and LR:Council(rule) then
        out[#out + 1] = L["Ranks that vote:"]
        out[#out + 1] = L["Members by name:"]
        out[#out + 1] = L["Hide who voted for whom:"]
        out[#out + 1] = L["A candidate votes on their own item:"]
        out[#out + 1] = L["Every answer needs a note:"]
        out[#out + 1] = L["Votes that close the vote:"]
    end
    for _, q in ipairs(LR:Queues(rule)) do
        out[#out + 1] = string.format(L["Queue %s, when the winner drops:"], q.name or q.key)
        out[#out + 1] = string.format(L["Queue %s, a newcomer joins:"], q.name or q.key)
    end
    return out
end

-- Everything a drawing left on `content`, frames and texts, goes (as the settings panel does).
local function clear(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
    for _, region in pairs({ content:GetRegions() }) do region:Hide() end
end

-- A paragraph across the content from `x`: a description in textSoft unless a colour is given.
-- Returns the y under it.
local function paragraph(content, text, y, x, size, col)
    col = col or C.textSoft
    local t = UI:CreateText(content, text, size or 11, col.r, col.g, col.b)
    t:SetPoint("TOPLEFT", x or 0, -y)
    t:SetWidth(math.max(120, (content:GetWidth() or 0) - (x or 0)))
    t:SetJustifyH("LEFT")
    if t.SetWordWrap then t:SetWordWrap(true) end
    return y + math.max(14, math.ceil(t:GetStringHeight() or 14)) + 4
end

----------------------------------------------------------------------
-- The loot rule's editor (issue #334): how raiders answer, drawn into `content` from `yOff` down.
-- Every change goes through GuildOS.LootRule, which keeps the rule and refuses one that is not a rule;
-- this only shows it. `coreName` (issue #338) edits that core's own rule; nil is the guild's. Moved
-- here from Settings > Loot (issue #346): the Rule tab is where it is drawn. `redraw` draws the host
-- again after a change. `col` is where its fields start: the column of the settings above it, so the
-- tab is one form with one label column (#371). Returns the new yOff.
----------------------------------------------------------------------
function GuildOS:BuildLootRuleEditor(content, yOff, coreName, redraw, col)
    col = col or LABEL_MIN
    local ofCore = coreName ~= nil and coreName ~= ""
    local CM = GuildOS.CoreManager
    local settings = (CM and CM:GetLootConfig(coreName or "")) or {}
    local LR = GuildOS.LootRule
    local rule = LR:For(coreName)
    local answers = LR:Responses(rule)
    -- What a change came to: said when the rule refused it, and the panel drawn again either way.
    local function changed(ok)
        if not ok then GuildOS:Print(L["|cffFF4444That change does not make a rule the loot master can use.|r"]) end
        redraw()
    end
    local function ruleBox(width, numeric, maxLetters, x, text)
        local box = input(content, width, numeric, maxLetters)
        box:SetPoint("TOPLEFT", x, -yOff)
        box:SetText(text or "")
        return box
    end
    -- How far a row may run before it wraps (#346: the window's narrow band).
    local maxX = math.max(col + 200, content:GetWidth() or 0)
    -- A row of buttons of which one is the choice in force (two values: a dropdown for more). The
    -- choice is the shared selection mark (#371); a row that wraps goes on in the field column.
    local function choices(x, list, current, onPick)
        local start = x
        for _, c in ipairs(list) do
            local b = UI:CreateButton(content, c.n, 80, 22)
            if x > start and x + b:GetWidth() > maxX then
                x = start
                yOff = yOff + 26
            end
            b:SetPoint("TOPLEFT", x, -yOff)
            UI:SetSelected(b, c.k == current)
            b:SetScript("OnClick", function() onPick(c.k) end)
            x = x + b:GetWidth() + 4
        end
    end
    -- One of more than two values: a dropdown (issue #346).
    local function pick(x, width, list, current, onPick)
        local dd = UI:CreateDropdown(content, width, 22)
        dd:SetPoint("TOPLEFT", x, -yOff)
        local opts = {}
        for i, c in ipairs(list) do opts[i] = { value = c.k, text = c.n } end
        dd:SetOptions(opts)
        dd:SetValue(current)
        dd.onSelect = function(_, k) onPick(k) end
        return dd
    end

    yOff = sectionTitle(content, L["How raiders answer:"], yOff)
    yOff = paragraph(content, L["The buttons of the roll popup, in order of priority. Without GuildOS, /roll 1-100 is the first and /roll 1-99 the second; the loot master types in any other answer."], yOff)
    yOff = yOff + 4

    -- Whether winning with an answer can count for a +1: only a rule that keeps the counter.
    local countsPlus = false
    for _, e in ipairs(rule.effects or {}) do
        if e.k == "add" then countsPlus = true end
    end
    local ASKS = { { k = "roll", n = L["Roll"] }, { k = "bid", n = L["Bid"] }, { k = "none", n = L["No roll"] } }
    -- An answer's controls wrap onto a second line where the window is too narrow for one (#346).
    local rowX
    local function at(w, width)
        if rowX > col and rowX + width > maxX then
            rowX = col
            yOff = yOff + 26
        end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", rowX, -yOff)
        rowX = rowX + width + 4
    end
    for i, r in ipairs(answers) do
        rowX = col
        -- The answer's key heads its row in the label column, as text (#371: it was gold).
        formLabel(content, r.key, yOff)
        local labelBox = ruleBox(110, false, 24, col, LR:ResponseLabel(r))
        UI:AttachSaveButton(labelBox, function(box)
            changed(LR:SetResponseField(i, "label", box:GetText(), coreName))
        end)
        at(labelBox, 110 + 6 + labelBox.saveButton:GetWidth())
        local askDD = pick(rowX, 90, ASKS, r.ask or "roll", function(k) changed(LR:SetResponseField(i, "ask", k, coreName)) end)
        at(askDD, askDD:GetWidth())
        if countsPlus then
            local plusBtn = UI:CreateButton(content, "+1", 36, 22)
            UI:SetSelected(plusBtn, r.plus)
            plusBtn:SetScript("OnClick", function() changed(LR:SetResponseField(i, "plus", not r.plus, coreName)) end)
            at(plusBtn, plusBtn:GetWidth())
        end
        local costBox = ruleBox(40, false, 4, rowX, tostring(r.cost or 1))
        UI:AttachSaveButton(costBox, function(box)
            changed(LR:SetResponseField(i, "cost", box:GetText(), coreName))
        end)
        at(costBox, 40 + 6 + costBox.saveButton:GetWidth())
        if i > 1 then
            local up = UI:CreateButton(content, L["Up"], 40, 22)
            up:SetScript("OnClick", function() changed(LR:MoveResponse(i, -1, coreName)) end)
            at(up, up:GetWidth())
        end
        if i < #answers then
            local down = UI:CreateButton(content, L["Down"], 40, 22)
            down:SetScript("OnClick", function() changed(LR:MoveResponse(i, 1, coreName)) end)
            at(down, down:GetWidth())
        end
        if #answers > 1 then
            local del = UI:CreateButton(content, L["Remove"], 70, 22)
            del:SetScript("OnClick", function() changed(LR:RemoveResponse(i, coreName)) end)
            at(del, del:GetWidth())
        end
        yOff = yOff + FIELD_H
    end
    yOff = paragraph(content, L["Each answer: the button's name, what it asks for, and the share of the item's price it pays (1 = all, 0.5 = half, 0 = free)."], yOff)

    -- A new answer: its key where the answers' keys are, its button's name where their names are.
    if #answers < LR.MAX_RESPONSES then
        yOff = yOff + 14   -- the hints over the boxes
        local newKey = ruleBox(70, false, 8, 0)
        local keyHint = UI:CreateText(content, L["Key (A-Z, 0-9)"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        keyHint:SetPoint("BOTTOMLEFT", newKey, "TOPLEFT", 0, 2)
        local newLabel = ruleBox(130, false, 24, col)
        local labelHint = UI:CreateText(content, L["Button"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        labelHint:SetPoint("BOTTOMLEFT", newLabel, "TOPLEFT", 0, 2)
        local addBtn = UI:CreateButton(content, L["Add answer"], 100, 22)
        addBtn:SetPoint("LEFT", newLabel, "RIGHT", 6, 0)
        addBtn:SetScript("OnClick", function()
            if LR:CleanKey(newKey:GetText()) == "" then return end
            changed(LR:AddResponse(newKey:GetText(), newLabel:GetText(), coreName))
        end)
        yOff = yOff + FIELD_H + 4
    end

    formLabel(content, L["Time to answer (seconds):"], yOff)
    local timeBox = ruleBox(60, true, 3, col, tostring(rule.time or settings.rollDuration or 30))
    timeBox.ruleKey = "time"
    UI:AttachSaveButton(timeBox, function(box) changed(LR:SetTime(box:GetText(), coreName)) end)
    hint(content, L["5 to 300"], timeBox.saveButton)
    yOff = yOff + FIELD_H

    -- Bids, when an answer asks for one: open or sealed, the least bid, the step, and the price.
    if LR:HasBids(rule) then
        local sealed, minBid, step = LR:BidRules(rule)
        formLabel(content, L["Bids:"], yOff)
        choices(col, { { k = false, n = L["Open"] }, { k = true, n = L["Sealed"] } }, sealed,
            function(k) changed(LR:SetBidField("sealed", k, coreName)) end)
        yOff = yOff + FIELD_H
        formLabel(content, L["Minimum bid:"], yOff)
        local minBox = ruleBox(60, true, 6, col, tostring(minBid))
        UI:AttachSaveButton(minBox, function(box) changed(LR:SetBidField("min", box:GetText(), coreName)) end)
        yOff = yOff + FIELD_H
        formLabel(content, L["Bid step:"], yOff)
        local stepBox = ruleBox(60, true, 6, col, tostring(step))
        UI:AttachSaveButton(stepBox, function(box) changed(LR:SetBidField("step", box:GetText(), coreName)) end)
        hint(content, L["An open bid goes over the best one by at least this"], stepBox.saveButton)
        yOff = yOff + FIELD_H
        formLabel(content, L["The winner pays:"], yOff)
        local charge = LR:ChargeEffect(rule)
        pick(col, 220, {
            { k = "table", n = L["The item's price"] }, { k = "bid", n = L["Their bid"] },
            { k = "second", n = L["The second bid, plus a step"] },
        }, charge and charge.price or "table", function(k) changed(LR:SetPrice(k, coreName)) end)
        yOff = yOff + FIELD_H
    end

    -- The counters the rule keeps (the +1): when each goes back to nothing.
    for _, a in ipairs(LR:Counters(rule)) do
        formLabel(content, string.format(L["Counter %s starts over:"], a.name or a.key), yOff)
        local acct = a.key
        pick(col, 160, {
            { k = "night", n = L["Each raid night"] }, { k = "lockout", n = L["Each lockout"] },
            { k = "never", n = L["Never"] },
        }, a.reset or "never", function(k) changed(LR:SetCounterReset(acct, k, coreName)) end)
        yOff = yOff + FIELD_H
    end

    -- Who decides (issue #336): the order alone, the master looter, or a council that votes among the
    -- candidates when the answers close. The council is by guild rank and by name; where there is no
    -- master looter (retail) there is no vote to offer.
    local decideBy = rule.decide and rule.decide.by or "auto"
    local deciders = { { k = "auto", n = L["The order"] }, { k = "ml", n = L["The master looter"] } }
    if GuildOS.LootCouncil then deciders[#deciders + 1] = { k = "council", n = L["A council's vote"] } end
    formLabel(content, L["Who decides:"], yOff)
    if #deciders > 2 then
        pick(col, 180, deciders, decideBy, function(k) changed(LR:SetDecide(k, coreName)) end)
    else
        choices(col, deciders, decideBy, function(k) changed(LR:SetDecide(k, coreName)) end)
    end
    yOff = yOff + FIELD_H
    local council = GuildOS.LootCouncil and LR:Council(rule)
    if council then
        yOff = paragraph(content, L["Council: when the answers close, its members with GuildOS see the candidates in the rule's order and vote. The master looter confirms who the council proposes."], yOff)
        yOff = yOff + 4
        -- Who votes: a button a guild rank, marked as chosen when the rank is on the council.
        formLabel(content, L["Ranks that vote:"], yOff)
        local onCouncil = GuildOS.LootCouncil:Ranks(council)
        local rx = col
        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for ri = 1, math.min(10, numRanks) do
            local rankName = GuildControlGetRankName and GuildControlGetRankName(ri) or ""
            if rankName ~= "" then
                local rankIndex = ri - 1
                local rb = UI:CreateButton(content, rankName, 90, 22)
                if rx > col and rx + rb:GetWidth() > maxX then
                    rx = col
                    yOff = yOff + 26
                end
                rb:SetPoint("TOPLEFT", rx, -yOff)
                UI:SetSelected(rb, onCouncil[rankIndex])
                rb:SetScript("OnClick", function() changed(LR:SetCouncilField("rank", rankIndex, coreName)) end)
                rx = rx + rb:GetWidth() + 4
            end
        end
        yOff = yOff + FIELD_H
        formLabel(content, L["Members by name:"], yOff)
        -- As wide as the row leaves beside its Save button, up to 300.
        local namesBox = ruleBox(math.max(120, math.min(300, maxX - col - 70)), false, 240, col,
            table.concat(council.names or {}, ", "))
        UI:AttachSaveButton(namesBox, function(box) changed(LR:SetCouncilField("names", box:GetText(), coreName)) end)
        yOff = yOff + FIELD_H
        local YES_NO = { { k = true, n = L["Yes"] }, { k = false, n = L["No"] } }
        local function flag(label, field)
            formLabel(content, label, yOff)
            choices(col, YES_NO, council[field] == true, function(k) changed(LR:SetCouncilField(field, k, coreName)) end)
            yOff = yOff + FIELD_H
        end
        flag(L["Hide who voted for whom:"], "anon")
        flag(L["A candidate votes on their own item:"], "self")
        flag(L["Every answer needs a note:"], "note")
        formLabel(content, L["Votes that close the vote:"], yOff)
        local quorumBox = ruleBox(60, true, 2, col, council.quorum and tostring(council.quorum) or "")
        UI:AttachSaveButton(quorumBox, function(box) changed(LR:SetCouncilField("quorum", box:GetText(), coreName)) end)
        hint(content, L["Empty: the vote runs until the master looter ends it or the time is up"], quorumBox.saveButton)
        yOff = yOff + FIELD_H
    end

    -- The queues the rule keeps (Suicide Kings, issue #337): who moves up when the winner drops, and
    -- where somebody the list never saw joins it.
    for _, q in ipairs(LR:Queues(rule)) do
        local acct = q.key
        formLabel(content, string.format(L["Queue %s, when the winner drops:"], q.name or q.key), yOff)
        choices(col, {
            { k = false, n = L["Everyone below moves up"] }, { k = true, n = L["Only who is in the raid moves up"] },
        }, q.frozen == true, function(k) changed(LR:SetQueueField(acct, "frozen", k, coreName)) end)
        yOff = yOff + FIELD_H
        formLabel(content, string.format(L["Queue %s, a newcomer joins:"], q.name or q.key), yOff)
        choices(col, {
            { k = "bottom", n = L["At the end"] }, { k = "random", n = L["At a random place"] },
        }, q.newcomer or "bottom", function(k) changed(LR:SetQueueField(acct, "newcomer", k, coreName)) end)
        yOff = yOff + FIELD_H
    end

    -- Exceptions (issue #335): the items that follow another rule. One line each, and a row to add one:
    -- which items, and either where they go with no roll or the order that decides them.
    yOff = sectionTitle(content, L["Exceptions:"], yOff)
    yOff = paragraph(content, L["Items that follow another rule: sent to the bank or to the disenchanter with no roll, or decided by an order of their own. The most specific wins: an item, then a boss, then a category, then a raid."], yOff)
    yOff = yOff + 4
    local exceptions = rule.exceptions or {}
    for i, x in ipairs(exceptions) do
        local what
        if x.to == "bank" then
            what = L["to the bank"]
        elseif x.to == "de" then
            what = L["to the disenchanter"]
        elseif x.set and x.set.order and not (x.set.filters or x.set.responses or x.set.decide or x.set.effects) then
            local names = {}
            for n, entry in ipairs(x.set.order) do names[n] = LR:Label(entry.k) end
            what = string.format(L["decided by: %s"], table.concat(names, ", "))
        else
            what = L["a rule of its own"]
        end
        local excDel = UI:CreateButton(content, L["Remove"], 70, 22)
        excDel:SetPoint("TOPRIGHT", 0, -yOff)
        excDel:SetScript("OnClick", function() changed(LR:RemoveException(i, coreName)) end)
        -- An exception is a line of text up to its Remove button (#371: it was gold).
        local excText = UI:CreateText(content, LR:ExceptionLabel(x) .. "  -  " .. what, 12, C.text.r, C.text.g, C.text.b)
        excText:SetPoint("TOPLEFT", 0, -(yOff + 4))
        excText:SetPoint("TOPRIGHT", excDel, "TOPLEFT", -8, -4)
        excText:SetJustifyH("LEFT")
        yOff = yOff + FIELD_H
    end
    if #exceptions < LR.MAX_EXCEPTIONS then
        -- What is being added, kept on the host between drawings: a choice draws again.
        local adding = content.__lootException or { kind = "cat", cat = "recipe", to = "bank", order = {} }
        content.__lootException = adding
        local KINDS = {
            { k = "cat", n = L["Category"] }, { k = "items", n = L["Item ids"] },
            { k = "boss", n = L["Boss (encounter id)"] }, { k = "raid", n = L["Raid (instance id)"] },
        }
        local TOS = { { k = "bank", n = L["To the bank"] }, { k = "de", n = L["To the disenchanter"] }, { k = "order", n = L["Another order"] } }
        local CATS = {}
        for n, cat in ipairs(LR.CATEGORY_ORDER) do CATS[n] = { k = cat, n = LR:CategoryLabel(cat) } end
        local function dd(x, width, list, current, onPick)
            local box = UI:CreateDropdown(content, width, 22)
            box:SetPoint("TOPLEFT", x, -yOff)
            local opts = {}
            for n, c in ipairs(list) do opts[n] = { value = c.k, text = c.n } end
            box:SetOptions(opts)
            box:SetValue(current)
            box.onSelect = function(_, k) onPick(k) end
            return box
        end
        -- The row starts at the content's edge, under its section's title, and wraps where the window
        -- is too narrow for it, as an answer's does.
        local excX = 0
        local function place(w, width)
            if excX > 0 and excX + width > maxX then
                excX = 0
                yOff = yOff + 26
            end
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", excX, -yOff)
            excX = excX + width + 4
        end
        local kindDD = dd(excX, 150, KINDS, adding.kind, function(k) adding.kind = k; redraw() end)
        place(kindDD, kindDD:GetWidth())
        local valueBox
        if adding.kind == "cat" then
            local catDD = dd(excX, 160, CATS, adding.cat, function(k) adding.cat = k; redraw() end)
            place(catDD, catDD:GetWidth())
        else
            valueBox = ruleBox(150, false, 120, excX, adding.value or "")
            -- Hooked: the shared field keeps its own handlers on OnTextChanged (#371).
            valueBox:HookScript("OnTextChanged", function(self) adding.value = self:GetText() end)
            place(valueBox, 150)
        end
        local toDD = dd(excX, 150, TOS, adding.to, function(k) adding.to = k; redraw() end)
        place(toDD, toDD:GetWidth())
        local addExc = UI:CreateButton(content, L["Add exception"], 110, 22)
        place(addExc, addExc:GetWidth())
        addExc:SetScript("OnClick", function()
            local spec = { kind = adding.kind, value = adding.kind == "cat" and adding.cat or (valueBox and valueBox:GetText()) }
            if adding.to == "order" then spec.order = adding.order else spec.to = adding.to end
            local ok = LR:AddException(spec, coreName)
            if ok then adding.order, adding.value = {}, nil end
            changed(ok)
        end)
        yOff = yOff + FIELD_H
        if adding.to == "order" then
            -- The order of its own: each click on a criterion puts it next.
            local names = {}
            for n, k in ipairs(adding.order) do names[n] = LR:Label(k) end
            yOff = paragraph(content, string.format(L["Order: %s"],
                #names > 0 and table.concat(names, ", ") or L["click the criteria below, first to last"]), yOff)
            local cx = 0
            local function criterion(k)
                local used = false
                for _, have in ipairs(adding.order) do used = used or have == k end
                if used then return end
                local cb = UI:CreateButton(content, LR:Label(k), 100, 20)
                if cx > 0 and cx + cb:GetWidth() > maxX then
                    cx = 0
                    yOff = yOff + 24
                end
                cb:SetPoint("TOPLEFT", cx, -yOff)
                cb:SetScript("OnClick", function()
                    if #adding.order < LR.MAX_CRITERIA then adding.order[#adding.order + 1] = k end
                    redraw()
                end)
                cx = cx + cb:GetWidth() + 4
            end
            for _, k in ipairs(LR.CRITERIA_ORDER) do criterion(k) end
            criterion("bid")
            if #adding.order > 0 then
                local clearBtn = UI:CreateButton(content, L["Clear order"], 100, 20)
                if cx + clearBtn:GetWidth() > maxX then
                    cx = 0
                    yOff = yOff + 24
                end
                clearBtn:SetPoint("TOPLEFT", cx, -yOff)
                clearBtn:SetScript("OnClick", function() adding.order = {}; redraw() end)
            end
            yOff = yOff + FIELD_H
        end
    end

    -- A rule an officer changed stays the guild's (or the core's) until a loot system is picked again.
    if LR:IsCustom(coreName) then
        yOff = yOff + GAP
        local backBtn = UI:CreateButton(content, L["Back to the loot system's rule"], 220, 22)
        backBtn:SetPoint("TOPLEFT", 0, -yOff)
        backBtn:SetScript("OnClick", function() changed(LR:Set(nil, coreName)) end)
        local backHint = UI:CreateText(content, ofCore
            and L["This core's own rule is in force: its loot system's other settings no longer change who wins."]
            or L["The guild's own rule is in force: the loot system's other settings no longer change who wins."], 11,
            C.textSoft.r, C.textSoft.g, C.textSoft.b)
        backHint:SetPoint("LEFT", backBtn, "RIGHT", 10, 0)
        backHint:SetWidth(math.max(120, (content:GetWidth() or 0) - 240))
        backHint:SetJustifyH("LEFT")
        yOff = yOff + 30
    end
    return yOff
end

-- The editor of one core's rule (issue #338) is the Rule tab on that core (issue #346).
function GuildOS:ShowLootRuleEditor(coreName)
    if not GuildOS.LootRule then return end
    UI:OpenWindow("loot", "rule", coreName or "")
end

-- Where the loot rule of `scope` is edited, for the screens that used to edit it (Settings > Loot,
-- the core's Config tab): its name in one line and the way to the Loot window. Returns the new y.
function GuildOS:DrawLootPointer(content, y, scope, x)
    x = x or 0
    local LR, CM = self.LootRule, self.CoreManager
    local site = scope ~= "" and CM and CM.LootRuleFromSite and CM:LootRuleFromSite(scope)
    local name = LR and LR:ModelName(site or LR:For(scope)) or L["Loot"]
    if GuildOS:GetLootSystem(scope) == "external" then name = L["External / Off"] end
    local line = UI:CreateText(content, string.format(L["Loot: %s"], name), 12, C.text.r, C.text.g, C.text.b)
    line:SetPoint("TOPLEFT", x, -(y + 4))
    local open = UI:CreateButton(content, L["Open Loot"], 110, 22)
    open:SetPoint("LEFT", line, "RIGHT", 12, 0)
    open:SetScript("OnClick", function() UI:OpenWindow("loot", "rule", scope) end)
    content.lootPointer = open
    return y + 30
end

----------------------------------------------------------------------
-- The Rule tab, drawn into `content` for `scope` (a core's name, "" the guild's): the selector, the
-- model, its settings and the answers' editor (officers), and the rule as players will read it
-- (everyone). Drawn again after every change. Returns the height drawn.
----------------------------------------------------------------------

-- The model of a core or of the guild: the loot systems this client offers as one list, the choice
-- in force marked; a core adds "Follow the guild".
local function drawModels(content, y, scope, redraw)
    local CM = GuildOS.CoreManager
    local ofCore = scope ~= ""
    local own
    if ofCore then own = CM:GetLootSystem(scope) else own = GuildOS:GetLootSystem("") end
    local list = {}
    if ofCore then list[1] = { key = false, label = L["Follow the guild"] } end
    for _, sys in ipairs(GuildOS:LootSystemsHere()) do
        list[#list + 1] = { key = sys.key, label = GuildOS:LootSystemLabel(sys) }
    end
    local W = content:GetWidth() or 0
    local grid = UI:ChipGrid(#list, W, MODEL_GAP, W >= 560 and 5 or 8)
    for i, choice in ipairs(list) do
        local col, row = grid:Cell(i)
        local b = UI:CreateButton(content, choice.label, math.floor(grid.w), MODEL_ROW_H - 2)
        b:SetPoint("TOPLEFT", math.floor(col * (grid.w + MODEL_GAP)), -(y + row * MODEL_ROW_H))
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 8, 0)
        b.label:SetJustifyH("LEFT")
        b.modelKey = choice.key
        -- The model in force: the shared selection mark, a gold border and a gold label (#371).
        UI:SetSelected(b, (choice.key or nil) == own)
        b:SetScript("OnClick", function()
            local pickKey = choice.key or nil
            if GuildOS:SetLootSystem(pickKey, ofCore and scope or nil) then
                GuildOS:Print(ofCore and string.format(L["Loot system of %s: %s."], scope, choice.label)
                    or string.format(L["Loot system set to %s."], choice.label))
            end
            redraw()
        end)
    end
    y = y + grid.rows * MODEL_ROW_H + 4
    if ofCore and not own then
        local followed = GuildOS:GetLootSystem("")
        for _, sys in ipairs(GuildOS:LootSystemsHere()) do
            if sys.key == followed then followed = GuildOS:LootSystemLabel(sys) end
        end
        y = paragraph(content, string.format(L["Following the guild: %s."], followed), y, 0, 11, C.label)
    end
    return y
end

-- The loot master's settings' labels, in the order they are drawn.
local function settingsLabels(inForce)
    local labels = {
        { key = "rollDuration", text = L["Roll duration (sec):"] },
        { key = "minAttendancePct", text = L["Min attendance % for MS:"] },
    }
    if inForce == "dkpbid" or inForce == "dkpsealed" then
        labels[#labels + 1] = { key = "dkpMinBid", text = L["Min bid (DKP):"] }
        labels[#labels + 1] = { key = "dkpBidTime", text = L["Bid duration (sec):"] }
    end
    labels[#labels + 1] = { key = "lootThreshold", text = L["Loot threshold:"] }
    labels[#labels + 1] = { key = "disenchanter", text = L["Disenchanter:"] }
    labels[#labels + 1] = { key = "bank", text = L["Bank character:"] }
    return labels
end

-- The loot master's settings of the scope, whatever its loot system: each field saves on its own.
-- `col` is the form's field column (labelColumn).
local function drawLootSettings(content, y, scope, inForce, col)
    local LM = GuildOS.LootMaster
    local cfg = LM:LootSettings(scope)
    local function saved(key, value)
        local kept, why = LM:SetLootSetting(key, value, scope)
        if kept == nil and why == "range" and key == "rollDuration" then
            GuildOS:Print(L["Duration must be between 5 and 120 seconds."])
        end
        return kept
    end

    local texts = {}
    for _, f in ipairs(settingsLabels(inForce)) do texts[f.key] = f.text end
    local function line(key) formLabel(content, texts[key], y) end
    local function numberField(key, width, maxLetters, default)
        line(key)
        local box = input(content, width, true, maxLetters)
        box:SetPoint("TOPLEFT", col, -y)
        box:SetText(tostring(cfg[key] or default))
        box.lootKey = key
        UI:AttachSaveButton(box, function(b)
            local kept = saved(key, b:GetText())
            b:SetText(tostring(kept or LM:LootSettings(scope)[key] or default))
        end, { state = true })
        y = y + FIELD_H
        return box
    end
    local function nameField(key)
        line(key)
        local box = input(content, 160, false, 64)
        box:SetPoint("TOPLEFT", col, -y)
        box:SetText(cfg[key] or "")
        box.lootKey = key
        UI:AttachSaveButton(box, function(b) saved(key, b:GetText()) end, { state = true })
        y = y + FIELD_H
    end
    -- A switch at the content's edge, its box flush with the labels above it (#371).
    local function check(key, text, on)
        local cb = UI:CreateCheckbox(content, text, 14)
        cb:SetPoint("TOPLEFT", 0, -(y + 4))
        cb.checkbox:SetChecked(on)
        cb.checkbox.lootKey = key
        cb.checkbox.onChanged = function(_, checked) saved(key, checked and true or false) end
        y = y + 24
    end

    numberField("rollDuration", 50, 3, 30)
    numberField("minAttendancePct", 50, 3, 0)
    check("autoAnnounce", L["Auto-announce loot when ML opens loot window"], cfg.autoAnnounce ~= false)
    -- The one control of `wishlistOnlyMode` (issue #346): the loot table and the Config tab had their own.
    check("wishlistOnlyMode", L["Wishlist Auto-Council (check wishlist before rolling)"], cfg.wishlistOnlyMode and true or false)
    check("attTiebreaker", L["Attendance tiebreaker"], cfg.attTiebreaker ~= false)
    check("recvPenalty", L["Penalize Players Who Received Items This Lockout"], cfg.recvPenalty ~= false)
    y = y + 4
    if inForce == "dkpbid" or inForce == "dkpsealed" then
        numberField("dkpMinBid", 60, 6, 0)
        numberField("dkpBidTime", 50, 3, 30)
    end
    line("lootThreshold")
    local thr = UI:CreateDropdown(content, 180, 22)
    thr:SetPoint("TOPLEFT", col, -y)
    local opts = {}
    for q = 2, 5 do
        opts[#opts + 1] = { value = q, text = LM.THRESHOLD_NAMES[q] or tostring(q), color = GuildOS.QualityColors[q] }
    end
    thr:SetOptions(opts)
    thr:SetValue(cfg.lootThreshold or 3)
    thr.lootKey = "lootThreshold"
    thr.onSelect = function(_, q) saved("lootThreshold", q) end
    y = y + FIELD_H
    nameField("disenchanter")
    nameField("bank")
    return y
end

function GuildOS:RefreshLootRuleTab(content, scope)
    clear(content)
    local CM, LR, LM = self.CoreManager, self.LootRule, self.LootMaster
    if scope == nil then scope = content.__lootScope or self:DefaultLootScope() end
    if scope ~= "" and not (self.db.cores and self.db.cores[scope]) then scope = "" end
    content.__lootScope = scope
    local isOfficer = self:IsOfficer()
    local function redraw()
        GuildOS:RefreshLootRuleTab(content, content.__lootScope)
        if content.onRedraw then content.onRedraw() end
    end
    local y = 0

    -- Whose rule: the guild's or a core's.
    local ofLbl = UI:CreateHeaderText(content, L["RULE OF"], 10)
    ofLbl:SetPoint("TOPLEFT", 0, -(y + 6))
    local scopeDD = UI:CreateDropdown(content, 200, 22)
    scopeDD:SetPoint("TOPLEFT", (ofLbl:GetStringWidth() or 50) + 10, -y)
    scopeDD:SetOptions(scopeOptions())
    scopeDD:SetValue(scope)
    scopeDD.isScope = true
    scopeDD.onSelect = function(_, v) content.__lootScope = v; redraw() end
    y = y + 28
    if scope == "" and CM then
        local followers = {}
        for _, name in ipairs(CM:GetSortedNames()) do
            if not CM:GetLootSystem(name) and not LR:IsCustom(name) and not (CM.LootRuleFromSite and CM:LootRuleFromSite(name)) then
                followers[#followers + 1] = name
            end
        end
        if #followers > 0 then
            y = paragraph(content, string.format(L["%s follow the guild."], table.concat(followers, ", ")), y, 0, 11, C.label)
        end
    end

    local siteRule = scope ~= "" and CM and CM.LootRuleFromSite and CM:LootRuleFromSite(scope)
    local inForce = GuildOS:GetLootSystem(scope)
    local rule = siteRule or LR:For(scope)
    y = y + GAP

    -- 1 · The model: the screen's first section, and so no rule over it (#371).
    y = sectionTitle(content, L["1 \194\183 MODEL"], y, true)
    if siteRule then
        y = paragraph(content, L["This core's loot rule is set on guildos.me, which sends it with the raid's roster."], y, 0, 11, C.label)
        y = paragraph(content, string.format(L["Model: %s"], LR:ModelName(siteRule)), y, 0, 12, C.text)
    elseif isOfficer then
        y = drawModels(content, y, scope, redraw)
    else
        y = paragraph(content, string.format(L["Model: %s"], LR:ModelName(rule)), y, 0, 12, C.text)
    end
    if inForce == "external" then
        y = paragraph(content, L["GuildOS won't touch loot: no roll popups, wishlists, or history. Pick this if your guild distributes loot with Gargul, RCLootCouncil, etc."], y)
    elseif GuildOS.Client.isRetail then
        y = paragraph(content, inForce == "rolls"
            and L["Free roll: whoever received the item awards it to the best answer, Need before Greed, then the roll. Officers may award too."]
            or L["An officer awards an item a guildmate offers; whoever holds it then trades it to the winner."], y)
    end
    -- Retail's loot council by trade, for every member: offering an item, answering one (issue #185).
    -- A Settings quick button until issue #367, on the same terms: the module (retail only) and a
    -- guild loot system GuildOS runs.
    local council
    if GuildOS.TradeCouncil and GuildOS:LootSystemActive() then
        council = UI:SetButtonVariant(UI:CreateButton(content, L["Loot Council"], 120, 22), "secondary")
        council:SetPoint("TOPLEFT", 0, -(y + 2))
        council:SetScript("OnClick", function() GuildOS:ShowTradeCouncil() end)
        y = y + 30
    end
    content.councilButton = council

    -- 2 · The model's settings and the answers (officers): one form, one label column for the
    -- settings and the rule's rows alike (#371).
    if isOfficer and not siteRule and inForce ~= "external" and LM then
        y = sectionTitle(content, L["2 \194\183 SETTINGS OF THE MODEL"], y)
        local labels = {}
        for _, f in ipairs(settingsLabels(inForce)) do labels[#labels + 1] = f.text end
        if LR then
            for _, text in ipairs(ruleLabels(LR:For(scope ~= "" and scope or nil))) do labels[#labels + 1] = text end
        end
        local col = labelColumn(content, labels)
        y = drawLootSettings(content, y, scope, inForce, col)
        if LR then y = GuildOS:BuildLootRuleEditor(content, y, scope ~= "" and scope or nil, redraw, col) end
    end
    -- What the model spends lives in Accounts: one place for each setting.
    if isOfficer and GuildOS.Points and GuildOS:LootSystemUsesPoints(inForce) then
        y = y + GAP
        local note = UI:CreateText(content, L["This model spends points: what they earn and cost is set in Accounts."], 11,
            C.textSoft.r, C.textSoft.g, C.textSoft.b)
        note:SetPoint("TOPLEFT", 0, -(y + 4))
        local open = UI:CreateButton(content, L["Open Accounts"], 120, 22)
        open:SetPoint("LEFT", note, "RIGHT", 10, 0)
        open:SetScript("OnClick", function() if content.openSub then content.openSub("accounts", scope) end end)
        y = y + 30
    end

    -- How players will read it (everyone). Plain text: the lead-ins were painted white (#371).
    if inForce ~= "external" then
        y = sectionTitle(content, L["HOW PLAYERS WILL READ IT"], y)
        local d = LR:Describe(rule, LM and LM:LootSettings(scope).rollDuration)
        y = paragraph(content, L["Who may ask."] .. " " .. d.who, y, 0, 12, C.text)
        y = paragraph(content, L["How to ask."] .. " " .. d.how, y, 0, 12, C.text)
        y = paragraph(content, L["Who takes it."], y, 0, 12, C.text)
        for i, line in ipairs(d.order) do
            y = paragraph(content, string.format("%d. %s", i, line), y, 12, 12, C.text)
        end
        if d.decide then y = paragraph(content, d.decide, y, 0, 12, C.text) end
        if d.exceptions then
            y = paragraph(content, L["Exceptions."] .. " " .. d.exceptions, y, 0, 12, C.text)
        end
        local at = LR:SavedAt(scope)
        y = paragraph(content, at > 0 and string.format(L["Saved %s. The night's rule is locked when the raid starts."], GuildOS:DateText(at, " %H:%M"))
            or L["The rule of the loot system. The night's rule is locked when the raid starts."], y + 4, 0, 11, C.label)
    end

    content:SetHeight(math.max(1, y + 12))
    return y
end

----------------------------------------------------------------------
-- The Lists tab: the wishlists (each raider's own, and the guild's for the officers), the officers'
-- priorities and the soft reserves, where they were.
----------------------------------------------------------------------
local function buildLists(panel)
    -- The views' toolbar: flush with the sub-tab bar's left edge, GAP under it (#371).
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, -GAP)
    bar:SetPoint("TOPRIGHT", -GAP, -GAP)
    bar:SetHeight(TOOLBAR_H)
    local wishBtn = UI:CreateButton(bar, L["Wishlists"], 110, 22)
    wishBtn:SetPoint("LEFT", 0, 0)
    local srBtn = GuildOS.SoftRes and UI:CreateButton(bar, L["Soft Reserves"], 110, 22)
    if srBtn then srBtn:SetPoint("LEFT", wishBtn, "RIGHT", 6, 0) end
    -- "My Wishlist" is the guild list's own, beside Manage Prios: one here too showed it twice (#371).
    local viewTop = GAP + TOOLBAR_H + GAP

    -- Wishlists: the guild's, as the officers' Wishlist tab had it; a raider's own opens from the bar.
    local wishView = CreateFrame("Frame", nil, panel)
    wishView:SetPoint("TOPLEFT", 0, -viewTop)
    wishView:SetPoint("BOTTOMRIGHT", 0, 0)
    local guildWish
    local memberNote = UI:CreateText(wishView, L["Your wishlist is yours to keep: the officers read every raider's here, beside their priorities."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    memberNote:SetPoint("TOPLEFT", 0, 0)
    memberNote:SetPoint("RIGHT", wishView, "RIGHT", -GAP, 0)
    memberNote:SetJustifyH("LEFT")

    -- Soft reserves: the list, and for the officers the import and the clear.
    local srView = CreateFrame("Frame", nil, panel)
    srView:SetPoint("TOPLEFT", 0, -viewTop)
    srView:SetPoint("BOTTOMRIGHT", 0, GAP)
    srView:Hide()
    local srImportBtn = UI:CreateButton(srView, L["Import from softres.it"], 160, 22)
    srImportBtn:SetPoint("TOPLEFT", 0, 0)
    local srClearBtn = UI:CreateButton(srView, L["Clear"], 70, 22)
    srClearBtn:SetPoint("LEFT", srImportBtn, "RIGHT", 6, 0)
    local srCount = UI:CreateText(srView, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    srCount:SetPoint("TOPRIGHT", -GAP, -4)
    -- The table's header row: the shared one, no fill and a 1px rule under it (#371).
    local srHeader = UI:CreateTableHeader(srView)
    srHeader:SetPoint("TOPLEFT", 0, -(TOOLBAR_H + GAP))
    srHeader:SetPoint("TOPRIGHT", -GAP, -(TOOLBAR_H + GAP))
    local srCols = {
        { key = "item", min = 140, weight = 3, priority = 3, required = true },
        { key = "res",  min = 120, weight = 3, priority = 2, required = true },
        { key = "raid", min = 70,  weight = 1, priority = 1 },
    }
    local srHead = {
        item = UI:CreateHeaderText(srHeader, L["ITEM"], 10),
        res = UI:CreateHeaderText(srHeader, L["RESERVED BY"], 10),
        raid = UI:CreateHeaderText(srHeader, L["IN RAID"], 10),
    }
    local srScroll, srContent = UI:CreateScrollFrame(srView, "GuildOSLootSoftResScroll")
    srScroll:SetPoint("TOPLEFT", srHeader, "BOTTOMLEFT", 0, 0)
    srScroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(srScroll, srContent)
    local srRows = {}

    local function refreshSR()
        if not GuildOS.SoftRes then return end
        local officer = GuildOS:IsOfficer()
        srImportBtn:SetShown(officer)
        srClearBtn:SetShown(officer)
        local items = GuildOS.SoftRes:GetAllItems()
        srCount:SetText(#items .. " " .. L["items"])
        local layout = UI:ResolveColumns(srCols, math.max(1, srContent:GetWidth() or 0), 8)
        for key, fs in pairs(srHead) do
            local col = layout.byKey[key]
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", srHeader, "LEFT", col.x + 6, 0)
            fs:SetShown(col.shown)
        end
        for i, entry in ipairs(items) do
            local row = srRows[i]
            if not row then
                row = CreateFrame("Frame", nil, srContent, "BackdropTemplate")
                row:SetHeight(22)
                row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                row.item = UI:CreateText(row, "", 11)
                row.res = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                row.raid = UI:CreateText(row, "", 11)
                for _, k in ipairs({ "item", "res", "raid" }) do
                    row[k]:SetJustifyH("LEFT")
                    if row[k].SetWordWrap then row[k]:SetWordWrap(false) end
                end
                srRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
            local bg = (i % 2 == 0) and C.row1 or C.row2
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.4)
            local itemName = GuildOS.Compat.GetItemInfo(entry.itemId)
            row.item:SetText(itemName or ("Item #" .. entry.itemId))
            local reserves = GuildOS.SoftRes:GetReservesForDisplay(entry.itemId)
            local inRaid, names = 0, {}
            for _, r in ipairs(reserves) do
                if r.inRaid then inRaid = inRaid + 1 end
                names[#names + 1] = r.name
            end
            row.res:SetText(table.concat(names, ", "))
            local raidColor = inRaid > 0 and C.ok or C.textSoft
            row.raid:SetTextColor(raidColor.r, raidColor.g, raidColor.b)
            row.raid:SetText(inRaid > 0 and (inRaid .. "/" .. #reserves .. " " .. L["in raid"]) or "-")
            for _, k in ipairs({ "item", "res", "raid" }) do
                local col = layout.byKey[k]
                row[k]:ClearAllPoints()
                row[k]:SetPoint("LEFT", row, "LEFT", col.x + 6, 0)
                row[k]:SetWidth(math.max(1, col.w - 4))
                row[k]:SetShown(col.shown)
            end
            row:Show()
        end
        for i = #items + 1, #srRows do srRows[i]:Hide() end
        srContent:SetHeight(math.max(1, #items * 22))
    end
    GuildOS.softResRefresh = refreshSR
    srImportBtn:SetScript("OnClick", function() GuildOS:ShowSoftResImportPopup() end)
    srClearBtn:SetScript("OnClick", function()
        if GuildOS.SoftRes then GuildOS.SoftRes:Clear() end
        refreshSR()
    end)

    local view = "wishlists"
    local function show(which)
        view = which
        wishView:SetShown(which == "wishlists")
        srView:SetShown(which == "softres")
        -- The view shown: the shared selection mark (#371).
        UI:SetSelected(wishBtn, which == "wishlists")
        if srBtn then UI:SetSelected(srBtn, which == "softres") end
        if which == "wishlists" then
            local officer = GuildOS:IsOfficer() and GuildOS.CreateWishlistGuildPanel
            if officer and not guildWish then
                guildWish = CreateFrame("Frame", nil, wishView)
                guildWish:SetAllPoints()
                GuildOS:CreateWishlistGuildPanel(guildWish)
            end
            if guildWish then guildWish:SetShown(officer and true or false) end
            memberNote:SetShown(not officer)
        else
            refreshSR()
        end
    end
    wishBtn:SetScript("OnClick", function() show("wishlists") end)
    if srBtn then srBtn:SetScript("OnClick", function() show("softres") end) end
    panel:SetScript("OnShow", function() show(view) end)
    panel.ShowView = show
    UI:MakeResponsive(srView, function() if srView:IsShown() then refreshSR() end end)
end

----------------------------------------------------------------------
-- The loot history and the equity, as tables whose columns drop by priority at narrow widths
-- (issue #346; before, fixed at 300, 450 and 600 px). `header` takes the column titles.
----------------------------------------------------------------------
local HISTORY_COLS = {
    { key = "item",   min = 140, weight = 4, priority = 5, required = true },
    { key = "player", min = 90,  weight = 2, priority = 4, required = true },
    { key = "raid",   min = 90,  weight = 2, priority = 2 },
    { key = "date",   min = 96,  weight = 1, priority = 3 },
}
local EQUITY_COLS = {
    { key = "name",  min = 110, weight = 3, priority = 6, required = true },
    { key = "items", min = 50,  weight = 1, priority = 5, required = true },
    { key = "att",   min = 50,  weight = 1, priority = 4 },
    { key = "raids", min = 50,  weight = 1, priority = 2 },
    { key = "per",   min = 70,  weight = 1, priority = 3 },
    { key = "flag",  min = 70,  weight = 1, priority = 1 },
}

-- Column titles in `header`, made once and moved to where `layout` puts them.
local function placeHeader(header, titles, layout)
    header.titles = header.titles or {}
    for key, text in pairs(titles) do
        local fs = header.titles[key]
        if not fs then
            fs = UI:CreateHeaderText(header, text, 10)
            header.titles[key] = fs
        end
        local col = layout.byKey[key]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", header, "LEFT", col.x + 6, 0)
        fs:SetShown(col.shown)
    end
end

-- A row of `content`, made once and reused; its cells are FontStrings by column key.
local function tableRow(content, i, keys)
    content.rows = content.rows or {}
    local row = content.rows[i]
    if not row then
        row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetHeight(22)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.cells = {}
        for _, k in ipairs(keys) do
            local fs = UI:CreateText(row, "", 11)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            row.cells[k] = fs
        end
        content.rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
    local bg = (i % 2 == 1) and C.row1 or C.row2
    row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.4)
    row.bg = bg
    row:Show()
    return row
end

local function placeCells(row, layout)
    for key, fs in pairs(row.cells) do
        local col = layout.byKey[key]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", col.x + 6, 0)
        fs:SetWidth(math.max(1, col.w - 6))
        fs:SetShown(col.shown)
    end
end

local function hideRowsFrom(content, n)
    for i = n, #(content.rows or {}) do content.rows[i]:Hide() end
    if content.empty then content.empty:Hide() end
end

local function emptyLine(content, text)
    if not content.empty then
        content.empty = UI:CreateText(content, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        content.empty:SetPoint("TOPLEFT", 6, -4)
    end
    content.empty:SetText(text)
    content.empty:Show()
end

function GuildOS:RefreshLootPanel(content, countText, header)
    if not GuildOS.LootTracker then return end
    local history = GuildOS.LootTracker:GetHistory(100)
    countText:SetText(#GuildOS.db.lootHistory .. L[" items tracked"])
    local layout = UI:ResolveColumns(HISTORY_COLS, math.max(1, content:GetWidth() or 0), 6)
    if header then placeHeader(header, { item = L["ITEM"], player = L["PLAYER"], raid = L["RAID"], date = L["DATE"] }, layout) end
    hideRowsFrom(content, 1)
    for i, entry in ipairs(history) do
        local row = tableRow(content, i, { "item", "player", "raid", "date" })
        placeCells(row, layout)
        -- The item in its quality's colour, by the name this client's language gives it.
        local qColor = GuildOS.QualityColors[entry.quality] or GuildOS.QualityColors[1]
        local localName, _, _, _, _, _, _, _, _, _, localQuality = GuildOS.Compat.GetItemInfo(entry.itemLink or entry.itemId or 0)
        if localQuality then qColor = GuildOS.QualityColors[localQuality] or qColor end
        row.cells.item:SetText(localName or entry.itemName or "?")
        row.cells.item:SetTextColor(qColor.r, qColor.g, qColor.b)
        local member = GuildOS.db.members[entry.playerKey]
        local pr, pg, pb = 1, 1, 1
        if member and member.class then pr, pg, pb = GuildOS:GetClassColor(member.class) end
        row.cells.player:SetText(entry.player or "?")
        row.cells.player:SetTextColor(pr, pg, pb)
        row.cells.raid:SetText(entry.raid or "")
        row.cells.raid:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.cells.date:SetText(GuildOS:DateText(entry.timestamp or 0, " %H:%M"))
        row.cells.date:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row:EnableMouse(entry.itemLink ~= nil)
        row:SetScript("OnEnter", entry.itemLink and function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.itemLink)
            GameTooltip:Show()
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
        end or nil)
        row:SetScript("OnLeave", entry.itemLink and function(self)
            GameTooltip:Hide()
            self:SetBackdropColor(self.bg.r, self.bg.g, self.bg.b, self.bg.a or 0.4)
        end or nil)
        -- My own personal item, still in my bags to trade: offered to the raid from here (retail, #185).
        local offerable = GuildOS.TradeCouncil and not entry.awarded and entry.itemLink
            and GetServerTime() - (entry.timestamp or 0) < GuildOS.TradeCouncil.OFFER_TTL
            and entry.playerKey == GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
        if offerable and not row.offer then
            row.offer = UI:CreateButton(row, L["Offer"], 56, 18)
            row.offer:SetPoint("RIGHT", -4, 0)
        end
        if row.offer then
            row.offer:SetShown(offerable and true or false)
            local link = entry.itemLink
            row.offer:SetScript("OnClick", function() GuildOS.TradeCouncil:Offer(link) end)
        end
    end
    if #history == 0 then emptyLine(content, L["No loot recorded yet."]) end
    content:SetHeight(math.max(1, #history * 22))
end

function GuildOS:RefreshLootEquity(content, countText, header)
    if not GuildOS.LootTracker then return end
    local rows = GuildOS.LootTracker:GetGuildLootEquity()
    countText:SetText(string.format(L["%d members with loot/raid history"], #rows))
    local layout = UI:ResolveColumns(EQUITY_COLS, math.max(1, content:GetWidth() or 0), 6)
    if header then
        placeHeader(header, { name = L["MEMBER"], items = L["ITEMS"], att = L["ATT%"], raids = L["RAIDS"],
            per = L["ITEMS/RAID"], flag = "" }, layout)
    end
    hideRowsFrom(content, 1)
    for i, r in ipairs(rows) do
        local row = tableRow(content, i, { "name", "items", "att", "raids", "per", "flag" })
        placeCells(row, layout)
        local cr, cg, cb = GuildOS:GetClassColor(r.class)
        row.cells.name:SetText(r.name)
        row.cells.name:SetTextColor(cr, cg, cb)
        row.cells.items:SetText(tostring(r.items))
        row.cells.items:SetTextColor(C.text.r, C.text.g, C.text.b)
        -- Attendance: ok when high, warn in the middle, danger when low (#371: the middle was gold).
        local attColor = r.attendance >= 70 and C.ok or (r.attendance >= 40 and C.warn or C.danger)
        row.cells.att:SetText(r.attendance .. "%")
        row.cells.att:SetTextColor(attColor.r, attColor.g, attColor.b)
        row.cells.raids:SetText(tostring(r.raids))
        row.cells.raids:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.cells.per:SetText(string.format("%.2f", r.perRaid))
        row.cells.per:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        -- Dry (deserves loot) or well fed, for a quick read.
        if r.attendance >= 70 and r.items == 0 then
            row.cells.flag:SetText(L["dry"])
            row.cells.flag:SetTextColor(C.ok.r, C.ok.g, C.ok.b)
        elseif r.raids > 0 and r.perRaid >= 1.0 then
            row.cells.flag:SetText(L["well-fed"])
            row.cells.flag:SetTextColor(C.danger.r, C.danger.g, C.danger.b)
        else
            row.cells.flag:SetText("")
        end
    end
    if #rows == 0 then emptyLine(content, L["No loot or attendance data yet."]) end
    content:SetHeight(math.max(1, #rows * 22))
end

----------------------------------------------------------------------
-- The History tab: the loot history and the equity, as the officers' Loot tab had them.
----------------------------------------------------------------------
local function buildHistory(panel)
    -- Flush with the sub-tab bar's left edge, GAP under it (#371).
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -GAP)
    holder:SetPoint("BOTTOMRIGHT", 0, GAP)

    local histBtn = UI:CreateButton(holder, L["History"], 90, 22)
    histBtn:SetPoint("TOPLEFT", 0, 0)
    local eqBtn = UI:CreateButton(holder, L["Equity"], 90, 22)
    eqBtn:SetPoint("LEFT", histBtn, "RIGHT", 6, 0)
    local exportBtn = UI:CreateButton(holder, L["Export"], 90, 22)
    exportBtn:SetPoint("LEFT", eqBtn, "RIGHT", 6, 0)
    exportBtn:SetScript("OnClick", function() GuildOS:ShowExportPopup(L["Loot Export"], GuildOS:ExportLoot()) end)
    local countText = UI:CreateText(holder, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    countText:SetPoint("TOPRIGHT", -GAP, -4)
    local lmText = UI:CreateText(holder, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    lmText:SetPoint("TOPLEFT", 0, -(TOOLBAR_H + GAP))
    lmText:SetPoint("RIGHT", holder, "RIGHT", -GAP, 0)
    lmText:SetJustifyH("LEFT")
    if lmText.SetWordWrap then lmText:SetWordWrap(false) end
    if GuildOS.LootMaster then
        local lmEvents = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(lmEvents, "PARTY_LOOT_METHOD_CHANGED")
        GuildOS.Compat.RegisterEvent(lmEvents, "GROUP_ROSTER_UPDATE")
        lmEvents:SetScript("OnEvent", function()
            if panel:IsVisible() then lmText:SetText(GuildOS:LootMasterStatus() or "") end
        end)
    end

    local function view(top)
        local v = CreateFrame("Frame", nil, holder)
        v:SetPoint("TOPLEFT", 0, -top)
        v:SetPoint("BOTTOMRIGHT", 0, 0)
        -- The shared header row: no fill, its own 1px rule under it (#371).
        local header = UI:CreateTableHeader(v)
        header:SetPoint("TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", -GAP, 0)
        local scroll, content = UI:CreateScrollFrame(v, nil)
        scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
        UI:BindScrollChildWidth(scroll, content)
        v.header, v.content = header, content
        return v
    end
    -- Under the buttons and the master looter's line.
    local viewTop = TOOLBAR_H + GAP + 14 + GAP
    local historyView = view(viewTop)
    local equityView = view(viewTop)
    equityView:Hide()

    local current = "history"
    local function show(which)
        current = which
        historyView:SetShown(which == "history")
        equityView:SetShown(which == "equity")
        UI:SetSelected(histBtn, which == "history")
        UI:SetSelected(eqBtn, which == "equity")
        lmText:SetText(GuildOS:LootMasterStatus() or "")
        if which == "history" then
            GuildOS:RefreshLootPanel(historyView.content, countText, historyView.header)
        else
            GuildOS:RefreshLootEquity(equityView.content, countText, equityView.header)
        end
    end
    histBtn:SetScript("OnClick", function() show("history") end)
    eqBtn:SetScript("OnClick", function() show("equity") end)
    panel:SetScript("OnShow", function() show(current) end)
    panel.ShowView = show
    UI:MakeResponsive(holder, function() if panel:IsVisible() then show(current) end end)
end

----------------------------------------------------------------------
-- The tab: the sub-tab bar and the four panels, each built the first time it is shown.
----------------------------------------------------------------------
function GuildOS:CreateLootWindow(container, _mainFrame)
    local subBar = CreateFrame("Frame", nil, container)
    subBar:SetPoint("TOPLEFT", 0, 0)
    subBar:SetPoint("TOPRIGHT", 0, 0)
    subBar:SetHeight(SUB_H)
    UI:StyleSubTabBar(subBar)

    local SUBS = {
        { key = "rule",     label = L["Rule"] },
        { key = "accounts", label = L["Accounts"], absent = not GuildOS.Points },
        { key = "lists",    label = L["Lists"],    absent = not (GuildOS.Wishlist or GuildOS.SoftRes) },
        { key = "history",  label = L["History"] },
    }
    local panels, tabs, built = {}, {}, {}
    local active
    local select

    local builders = {
        rule = function(p)
            -- Flush with the sub-tab bar's left edge, GAP under it; the child ends GAP short of the
            -- right edge, the scroll bar in the gutter past it (#371).
            local scroll, content = UI:CreateScrollFrame(p, "GuildOSLootRuleScroll")
            scroll:SetPoint("TOPLEFT", 0, -GAP)
            scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, GAP)
            UI:BindScrollChildWidth(scroll, content)
            content.openSub = function(sub, scope) select(sub, scope) end
            p.content = content
            p.Draw = function(scope) GuildOS:RefreshLootRuleTab(content, scope) end
            p:SetScript("OnShow", function() p.Draw(content.__lootScope) end)
            UI:MakeResponsive(scroll, function() if p:IsVisible() then p.Draw(content.__lootScope) end end)
        end,
        accounts = function(p)
            GuildOS:BuildLootAccounts(p)
        end,
        lists = buildLists,
        history = buildHistory,
    }

    select = function(key, filter)
        local def
        for _, s in ipairs(SUBS) do
            if s.key == key and not s.absent then def = s end
        end
        if not def then key = "rule" end
        active = key
        for _, t in ipairs(tabs) do t:SetActive(t.key == key) end
        for k, p in pairs(panels) do if k ~= key then p:Hide() end end
        local p = panels[key]
        if not built[key] then
            built[key] = true
            builders[key](p)
        end
        -- A core named by whoever opened the tab (the core's Config tab, /gos points).
        if filter ~= nil and p.content then p.content.__lootScope = filter end
        if filter ~= nil and p.SetScope then p.SetScope(filter) end
        local was = p:IsShown()
        p:Show()
        if was and filter ~= nil and p.Draw then p.Draw(p.content.__lootScope) end
    end

    local prev
    for _, s in ipairs(SUBS) do
        if not s.absent then
            local p = CreateFrame("Frame", nil, container)
            p:SetPoint("TOPLEFT", 0, -SUB_H)
            p:SetPoint("BOTTOMRIGHT", 0, 0)
            p:Hide()
            panels[s.key] = p
            local tab = UI:CreateTab(subBar, s.label, 100, true)
            if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tab:SetPoint("LEFT", 4, 0) end
            tab.key = s.key
            tab:SetScript("OnClick", function() select(s.key) end)
            tabs[#tabs + 1] = tab
            prev = tab
        end
    end

    container:SetScript("OnShow", function() if not active then select("rule") end end)
    select("rule")
    container.SelectSub = select
    container.ActiveSub = function() return active end
    container.panels = panels
end
