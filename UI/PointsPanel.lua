----------------------------------------------------------------------
-- Guild OS - Accounts (DKP / EPGP / the rule's own accounts)
-- The Loot window's Accounts tab (issue #346): what was the standalone points window. A core and an
-- account to read; for the officers, the award row (who, a named reason or a typed one, how many
-- times, Award or Charge), the raid's award, the decay and the points' own settings; for everyone,
-- the standings and the movements. Visual layer only — all logic lives in GuildOS.Points, run on the
-- pool of the core picked (Points:InCore).
----------------------------------------------------------------------
local C = GuildOS.Colors
local L = GuildOS.L

-- The Accounts are parchment cards (#449): on the paper a colour of the wood takes the paper's shade, and a
-- switch's label its ink.
local function same(r, g, b, c) return c and math.abs(r - c.r) < 1e-3 and math.abs(g - c.g) < 1e-3 and math.abs(b - c.b) < 1e-3 end
local function onPaper(r, g, b)
    if same(r, g, b, C.text) then return C.paperInk.r, C.paperInk.g, C.paperInk.b end
    if same(r, g, b, C.textSoft) or same(r, g, b, C.label) or same(r, g, b, C.labelDim) then
        return C.paperSoft.r, C.paperSoft.g, C.paperSoft.b
    end
    if (r + g + b) / 3 > 0.55 then return r * 0.6, g * 0.6, b * 0.6 end
    return r, g, b
end
local function paperOf(parent) return GuildOS.UI.OnPaper ~= nil and GuildOS.UI:OnPaper(parent) end
local UI = setmetatable({
    CreateText = function(self, parent, text, size, r, g, b)
        if r and paperOf(parent) then r, g, b = onPaper(r, g, b) end
        return GuildOS.UI.CreateText(self, parent, text, size, r, g, b)
    end,
}, { __index = function(_, k) return GuildOS.UI[k] end })

local ROW_H    = 28
local OTHER    = "__other"   -- the reason the officer types
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll
-- frame's right edge sits SCROLL_R from the panel's. Numbers even where a test stands in for the UI.
local GAP      = tonumber(UI.GAP) or 8
local GUTTER   = tonumber(UI.SCROLL_GUTTER) or 12
local SCROLL_R = GUTTER - GAP
local TOP_H    = 22      -- the selectors' row
local HINT_H   = 14      -- a hint over a box
local HEAD_ABOVE = 20    -- room over a later section title for its rule (UI:CreateSectionTitle)

local PAD      = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
local TWO_COLS = 760     -- px: two columns of cards from here
local function hex(h) return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 } end
local PAPER_OK, PAPER_BAD = hex("2f6e33"), hex("8f1b0b")
-- A class's colour as the paper prints it (the mockup's .card .c-*).
local PAPER_CLASS = {
    PRIEST = hex("666666"), ROGUE = hex("857612"), HUNTER = hex("4f7319"), MAGE = hex("16758d"),
    PALADIN = hex("a8457a"), DRUID = hex("b35400"), SHAMAN = hex("0b4fa0"), WARRIOR = hex("7e5a33"),
    WARLOCK = hex("4b4cb0"),
}
local function paperClass(class)
    local c = PAPER_CLASS[type(class) == "string" and class:upper() or ""]
    if c then return c.r, c.g, c.b end
    local r, g, b = GuildOS:GetClassColor(class)
    return r * 0.6, g * 0.6, b * 0.6
end

-- A box: the shared field (#371), whose border turns gold while it has the keyboard.
local function input(parent, width, numeric, maxLetters)
    return UI:CreateInput(parent, width, 22, { numeric = numeric and true or nil, max = maxLetters or 64 })
end

-- `/gos points` and `/gos dkp` (and every button that said "Open DKP Window") open the tab.
function GuildOS:ShowPointsFrame(coreName)
    return UI:OpenWindow("loot", "accounts", coreName)
end

-- The standings' columns, by priority: the name and the balance always.
local STAND_COLS = {
    { key = "rank",   min = 24,  weight = 0, priority = 3 },
    { key = "name",   min = 110, weight = 3, priority = 6, required = true },
    { key = "cur",    min = 56,  weight = 1, priority = 5, required = true },
    { key = "earned", min = 56,  weight = 1, priority = 2 },
    { key = "spent",  min = 56,  weight = 1, priority = 1 },
}

-- The points' own settings, in the order the guild's settings had them. `epgp`/`dkp`: shown in one
-- mode only. Each saves on its own (Points:SetConfigKey).
local NUMBER_FIELDS = {
    { key = "bossAward",      label = L["Points per boss:"],       hint = L["Awarded to raiders on each boss kill"] },
    { key = "raidAward",      label = L["Points per raid:"],       hint = L["Given to everyone in the raid when it ends"] },
    { key = "onTimeAward",    label = L["On time:"],               hint = L["In the raid when it started"] },
    { key = "lateAward",      label = L["Late:"],                  hint = L["Arrived after the raid started"] },
    { key = "stayedAward",    label = L["Stayed until the end:"] },
    { key = "leftEarlyAward", label = L["Left early:"] },
    { key = "decayPct",       label = L["Weekly decay (%):"],      hint = L["Use the Apply Decay button to apply"] },
    { key = "itemCost",       label = L["GP of a chest piece:"],   hint = L["Other slots cost a share of it; 0 = items cost nothing"], epgp = true },
    { key = "gpRefIlvl",      label = L["Reference item level:"],  hint = L["GP doubles every 26 item levels above it; 0 = ignore item level"], epgp = true },
    { key = "baseGP",         label = L["Base GP:"],               hint = L["Added to everyone's GP, so a first item does not end all priority"], epgp = true },
    { key = "minEP",          label = L["Minimum EP:"],            hint = L["Below it, after everyone who has it"], epgp = true },
    { key = "startingPoints", label = L["Starting points:"],       hint = L["Default for a player's first entry"], dkp = true },
    { key = "cap",            label = L["Points cap:"],            hint = L["Earnings above it do not add (0 = no cap)"], dkp = true },
    { key = "itemCost",       label = L["Cost per item:"],         hint = GuildOS.Client.isRetail
        and L["Charged to the winner when the trade of an award is recorded (0 = off)"]
        or L["Charged to the winner when the ML awards (0 = off)"], dkp = true },
    { key = "entryCost",      label = L["Cost to enter a roll:"],  hint = L["Paid by everyone who rolls for the item (0 = off)"] },
    { key = "refundPct",      label = L["Back to whoever loses (%):"], hint = L["Share of the entry cost given back"] },
}

function GuildOS:BuildLootAccounts(panel)
    local P = GuildOS.Points
    local scope = GuildOS:DefaultLootScope()
    local shownAcct = nil
    local settingsOpen = false

    -- The core picked may be gone since (renamed or closed on Discord, by another officer, #339): the
    -- guild's then, as SetScope does, and never a read of a pool that is no one's.
    local function scopeHolds()
        if scope ~= "" and not (GuildOS.db.cores and GuildOS.db.cores[scope]) then scope = ""; return false end
        return true
    end
    local function inScope(fn, ...) return P:InCore(scope, fn, ...) end
    local function ruleOf() return GuildOS.LootRule and GuildOS.LootRule:For(scope) end
    local function ownAccounts()
        local LR, rule = GuildOS.LootRule, ruleOf()
        return (LR and rule) and LR:OwnAccounts(rule) or {}
    end

    -- The mockup's saque-contas: parchment cards on the wood. "Balances" on the left (the core and the account,
    -- what the pool plays, the standings); on the right "Give or charge points" (officers) over "Movements".
    -- One column where the tab is narrow: the officers' card over the balances, and the movements drop.
    local isOfficer = GuildOS:IsOfficer()
    local balCard = UI:CreateCard(panel, L["Balances"])
    local giveCard = isOfficer and UI:CreateCard(panel, L["Give or charge points"]) or nil
    local moveCard = UI:CreateCard(panel, L["Movements"])

    -- ── The selectors ───────────────────────────────────────────────
    local top = CreateFrame("Frame", nil, balCard)
    top:SetPoint("TOPLEFT", PAD, -CARD_TOP + 2)
    top:SetPoint("TOPRIGHT", -PAD, -CARD_TOP + 2)
    top:SetHeight(TOP_H)
    local coreLbl = UI:CreateText(top, L["Core"], 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    coreLbl:SetPoint("LEFT", 0, 0)
    local coreDD = UI:CreateDropdown(top, 150, 24)
    coreDD:SetPoint("LEFT", coreLbl, "RIGHT", 8, 0)
    coreDD.isScope = true
    local acctLbl = UI:CreateText(top, L["Account"], 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    acctLbl:SetPoint("LEFT", coreDD, "RIGHT", 14, 0)
    local acctDD = UI:CreateDropdown(top, 150, 24)
    acctDD:SetPoint("LEFT", acctLbl, "RIGHT", 8, 0)
    acctDD.isAccount = true
    local summary = UI:CreateText(balCard, "", 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    summary:SetPoint("TOPLEFT", PAD, -(CARD_TOP + TOP_H + 10))
    summary:SetPoint("RIGHT", balCard, "RIGHT", -PAD, 0)
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(false) end

    local listTop = CARD_TOP + TOP_H + 10 + 14 + GAP
    local status

    -- ── The award row (officers) ────────────────────────────────────
    local reasonDD, amountBox, nameBox, noteBox, settingsBtn
    local flow   -- the officer's rows, laid out again at every width
    if isOfficer then
        local row = CreateFrame("Frame", nil, giveCard)
        row:SetPoint("TOPLEFT", PAD, -(CARD_TOP + HINT_H))
        row:SetPoint("TOPRIGHT", -PAD, -(CARD_TOP + HINT_H))
        row:SetHeight(24)
        nameBox = input(row, 130, false, 48)
        nameBox:SetPoint("LEFT", 0, 0)
        local nameHint = UI:CreateText(row, L["Who"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        nameHint:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 0, 2)
        reasonDD = UI:CreateDropdown(row, 200, 22)
        reasonDD:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
        reasonDD.isReason = true
        local reasonHint = UI:CreateText(row, L["Reason"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        reasonHint:SetPoint("BOTTOMLEFT", reasonDD, "TOPLEFT", 0, 2)
        amountBox = input(row, 50, true, 6)
        amountBox:SetPoint("LEFT", reasonDD, "RIGHT", 6, 0)
        local amountHint = UI:CreateText(row, L["Times"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        amountHint:SetPoint("BOTTOMLEFT", amountBox, "TOPLEFT", 0, 2)
        noteBox = input(row, 140, false, 60)
        noteBox:SetPoint("LEFT", amountBox, "RIGHT", 6, 0)
        local awardBtn = UI:CreateButton(row, L["Award"], 64, 22)
        awardBtn:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
        UI:SetButtonVariant(awardBtn, "primary")
        local chargeBtn = UI:CreateButton(row, L["Charge"], 64, 22)
        chargeBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)
        UI:SetButtonVariant(chargeBtn, "danger")
        reasonDD.onSelect = function(_, v)
            local other = v == OTHER
            noteBox:SetShown(other)
            amountHint:SetText(other and L["Points"] or L["Times"])
        end
        local function doRow(charge)
            if not scopeHolds() then panel.Refresh(); return end   -- nothing given on a core that is gone
            local v = reasonDD:GetValue()
            local e, why = inScope(P.AwardRow, P, {
                name = nameBox:GetText(), reason = v ~= OTHER and v or nil, times = amountBox:GetText(),
                amount = amountBox:GetText(), note = noteBox:GetText(), charge = charge,
            })
            if e then
                status:SetText(string.format(L["%s: %+d points (%s)"], e.name or "?", e.delta or 0, e.reason or ""))
                amountBox:SetText(""); noteBox:SetText(""); nameBox:ClearFocus()
            elseif why == "name" then
                status:SetText("|cffFF4444" .. L["Type who first."] .. "|r")
            elseif why == "amount" then
                status:SetText("|cffFF4444" .. L["Type how many points."] .. "|r")
            end
        end
        awardBtn:SetScript("OnClick", function() doRow(false) end)
        chargeBtn:SetScript("OnClick", function() doRow(true) end)

        local row2 = CreateFrame("Frame", nil, giveCard)
        row2:SetPoint("TOPLEFT", PAD, -(CARD_TOP + HINT_H + 30))
        row2:SetPoint("TOPRIGHT", -PAD, -(CARD_TOP + HINT_H + 30))
        row2:SetHeight(22)
        local raidBtn = UI:CreateButton(row2, L["Award Raid"], 100, 20)
        raidBtn:SetPoint("LEFT", 0, 0)
        raidBtn:SetScript("OnClick", function()
            if not scopeHolds() then panel.Refresh(); return end   -- nothing given on a core that is gone
            local amt = inScope(function() return P:Pool().config.bossAward or 0 end)
            local n = inScope(P.AwardRaidGroup, P, amt, L["Manual raid award"])
            if n and n > 0 then status:SetText(string.format(L["Awarded %d points to %d raiders."], amt, n)) end
        end)
        local decayBtn = UI:CreateButton(row2, L["Apply Decay"], 100, 20)
        decayBtn:SetPoint("LEFT", raidBtn, "RIGHT", 6, 0)
        decayBtn:SetScript("OnClick", function()
            if not scopeHolds() then panel.Refresh(); return end
            local n = inScope(P.ApplyDecay, P)
            status:SetText(string.format(L["Decay applied to %d player(s)."], n or 0))
        end)
        local syncBtn = UI:CreateButton(row2, L["Send to guild"], 110, 20)   -- it only sends (audit B26)
        syncBtn:SetPoint("LEFT", decayBtn, "RIGHT", 6, 0)
        syncBtn:SetScript("OnClick", function()
            P:BroadcastSnapshot(scope)
            status:SetText(L["Points snapshot sent to guild."])
        end)
        settingsBtn = UI:CreateButton(row2, L["Account settings"], 130, 20)
        settingsBtn:SetPoint("RIGHT", 0, 0)
        settingsBtn:ClearAllPoints()
        status = UI:CreateText(giveCard, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        status:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -4)
        status:SetPoint("RIGHT", giveCard, "RIGHT", -PAD, 0)
        status:SetJustifyH("LEFT")
        if status.SetWordWrap then status:SetWordWrap(false) end
        -- Both rows wrap where the card is too narrow for them (FlowBar), the hints over the boxes
        -- keeping their room. Returns the card's height.
        flow = function(w)
            row:SetWidth(w)
            row2:SetWidth(w)
            local h1 = UI:FlowBar(row, { nameBox, reasonDD, amountBox, noteBox, awardBtn, chargeBtn }, { gap = 6, rowGap = HINT_H + 4, rowH = 22 })
            local top2 = CARD_TOP + HINT_H + h1 + GAP
            row2:ClearAllPoints()
            row2:SetPoint("TOPLEFT", PAD, -top2)
            row2:SetPoint("TOPRIGHT", -PAD, -top2)
            local h2 = UI:FlowBar(row2, { raidBtn, decayBtn, syncBtn, settingsBtn }, { gap = 6, rowGap = 4, rowH = 20 })
            return top2 + h2 + 4 + 16 + 10
        end
    end

    -- ── The standings and the movements ─────────────────────────────
    -- The standings in the balances' card, under its selectors and its line.
    local body = CreateFrame("Frame", nil, balCard)
    body:SetPoint("TOPLEFT", PAD, -listTop)
    body:SetPoint("BOTTOMRIGHT", -PAD + GAP, 10)
    -- The tables' header rows: the shared one, no fill and a 1px rule under it (#371).
    local standHead = UI:CreateTableHeader(body)
    standHead:SetPoint("TOPLEFT", 0, 0)
    local heads = {}
    for _, col in ipairs(STAND_COLS) do heads[col.key] = UI:CreateHeaderText(standHead, "", 10) end
    local standScroll, standChild = UI:CreateScrollFrame(body, nil)
    standScroll:SetPoint("TOPLEFT", standHead, "BOTTOMLEFT", 0, 0)
    -- The movements: their own card, the newest first, two lines each.
    local logHead = CreateFrame("Frame", nil, moveCard)
    logHead:SetPoint("TOPLEFT", PAD, -CARD_TOP + 4)
    logHead:SetPoint("TOPRIGHT", -PAD, -CARD_TOP + 4)
    logHead:SetHeight(1)
    local logScroll, logChild = UI:CreateScrollFrame(moveCard, nil)
    logScroll:SetPoint("TOPLEFT", logHead, "BOTTOMLEFT", 0, 0)
    logScroll:SetPoint("BOTTOMRIGHT", -PAD + GUTTER - 4, 10)
    UI:BindScrollChildWidth(logScroll, logChild)
    local standRows, logRows = {}, {}

    -- ── The points' settings (officers): in place of the tables, while open ──
    local setScroll, setChild = UI:CreateScrollFrame(body, nil)
    setScroll:SetPoint("TOPLEFT", 0, 0)
    setScroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(setScroll, setChild)
    setScroll:Hide()

    local function standRow(i)
        local row = standRows[i]
        if not row then
            row = CreateFrame("Frame", nil, standChild)
            row:SetHeight(ROW_H)
            local rule = row:CreateTexture(nil, "BACKGROUND")
            rule:SetTexture("Interface\\Buttons\\WHITE8x8")
            rule:SetHeight(1)
            rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
            rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
            row.cells = {}
            for _, col in ipairs(STAND_COLS) do
                local fs = UI:CreateText(row, "", 11)
                fs:SetJustifyH(col.key == "name" and "LEFT" or "RIGHT")
                if fs.SetWordWrap then fs:SetWordWrap(false) end
                row.cells[col.key] = fs
            end
            standRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:Show()
        return row
    end

    local function logRow(i)
        local row = logRows[i]
        if not row then
            row = CreateFrame("Frame", nil, logChild)
            row:SetHeight(30)
            local rule = row:CreateTexture(nil, "BACKGROUND")
            rule:SetTexture("Interface\\Buttons\\WHITE8x8")
            rule:SetHeight(1)
            rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
            rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
            row.line = UI:CreateText(row, "", 11)
            row.line:SetPoint("TOPLEFT", 4, 0)
            row.line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.line:SetJustifyH("LEFT")
            row.sub = UI:CreateText(row, "", 10, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
            row.sub:SetPoint("TOPLEFT", 12, -14)
            row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.sub:SetJustifyH("LEFT")
            for _, fs in ipairs({ row.line, row.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
            logRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * 30)
        row:Show()
        return row
    end

    local empty = UI:CreateText(standChild, "", 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    empty:SetPoint("TOPLEFT", 4, -4)
    local logEmpty = UI:CreateText(logChild, L["No history."], 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    logEmpty:SetPoint("TOPLEFT", 4, -4)

    local drawSettings   -- below

    local function refresh()
        if not panel:IsVisible() then return end
        scopeHolds()
        coreDD:SetOptions(GuildOS.LootScopeOptions())
        coreDD:SetValue(scope)
        local accounts = ownAccounts()
        local account
        local opts = { { value = false, text = L["Points"] } }
        for _, a in ipairs(accounts) do
            opts[#opts + 1] = { value = a.key, text = a.name or a.key }
            if a.key == shownAcct then account = a end
        end
        if not account then shownAcct = nil end
        acctDD:SetOptions(opts)
        acctDD:SetValue(shownAcct or false)
        for _, w in ipairs({ acctDD, acctLbl }) do
            if #accounts > 0 then w:Show() else w:Hide() end
        end
        if reasonDD then
            local ropts = {}
            for _, r in ipairs(inScope(P.GetReasons, P)) do
                local text = (r.weekly or 0) > 0 and string.format(L["%s: %d points, up to %d a week"], r.name, r.value, r.weekly)
                    or string.format(L["%s: %d points"], r.name, r.value)
                ropts[#ropts + 1] = { value = r.key, text = text }
            end
            ropts[#ropts + 1] = { value = OTHER, text = L["Other (type it)"] }
            reasonDD:SetOptions(ropts)
            local keep = false
            for _, o in ipairs(ropts) do keep = keep or o.value == reasonDD:GetValue() end
            if not keep then reasonDD:Select(ropts[1].value) end
        end

        -- The cards: two columns where the tab is wide, else the officers' over the balances.
        local Wp = (panel:GetWidth() or 0) - GAP
        if Wp < 100 then Wp = 700 end
        local two = Wp >= TWO_COLS
        local leftW = two and math.floor((Wp - GAP - 4) * 0.52) or Wp
        local rightX, rightW = leftW + GAP + 4, Wp - leftW - GAP - 4
        balCard:ClearAllPoints()
        moveCard:ClearAllPoints()
        local giveH = 0
        if giveCard then
            giveCard:ClearAllPoints()
            giveH = flow((two and rightW or Wp) - 2 * PAD)
            giveCard:SetHeight(giveH)
            if two then
                giveCard:SetPoint("TOPLEFT", rightX, -GAP)
                giveCard:SetWidth(rightW)
            else
                giveCard:SetPoint("TOPLEFT", 0, -GAP)
                giveCard:SetWidth(Wp)
            end
        end
        if two then
            balCard:SetPoint("TOPLEFT", 0, -GAP)
            balCard:SetPoint("BOTTOMLEFT", 0, GAP)
            balCard:SetWidth(leftW)
            moveCard:SetPoint("TOPLEFT", rightX, -(GAP + (giveCard and (giveH + GAP + 4) or 0)))
            moveCard:SetPoint("BOTTOMRIGHT", -GAP, GAP)
        else
            balCard:SetPoint("TOPLEFT", 0, -(GAP + (giveCard and (giveH + GAP + 4) or 0)))
            balCard:SetPoint("BOTTOMRIGHT", -GAP, GAP)
        end
        moveCard:SetShown(two)
        local mode = inScope(P.GetMode, P)
        local cfg = inScope(function() return P:Pool().config end) or {}
        local MODE_NAME = { dkp = "DKP", epgp = "EPGP", council = L["Loot Council"] }
        summary:SetText(string.format(L["%s · Boss award: %d · Decay: %d%% · Auto-award: %s"], MODE_NAME[mode] or tostring(mode),
            cfg.bossAward or 0, cfg.decayPct or 0, cfg.autoAward and L["on"] or L["off"]))

        if settingsOpen then
            standScroll:Hide(); standHead:Hide()
            setScroll:Show()
            drawSettings()
            return
        end
        setScroll:Hide()
        standScroll:Show(); standHead:Show()

        -- The movements keep their column while the window leaves room for it; then they drop. The
        -- content stops GAP short of the right edge; the standings' scroll bar sits in its gutter.
        local W = (body:GetWidth() or 0) - GAP
        if W < 60 then W = (two and leftW or Wp) - 2 * PAD end
        local withLog = two
        local standW = math.max(1, W)
        standHead:SetWidth(standW)
        standChild:SetWidth(standW)
        standScroll:ClearAllPoints()
        standScroll:SetPoint("TOPLEFT", standHead, "BOTTOMLEFT", 0, 0)
        standScroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMLEFT", standW + GUTTER, 0)
        local layout = UI:ResolveColumns(STAND_COLS, standW, 6)
        local epgp = mode == "epgp"
        local queue = account and account.type == "queue"
        local TITLES = {
            rank = "", name = L["Member"],
            cur = (queue and L["Place"]) or (epgp and not account and "PR") or L["Balance"],
            earned = account and "" or (epgp and "EP" or L["Earned"]),
            spent = account and "" or (epgp and "GP" or L["Spent"]),
        }
        for _, col in ipairs(STAND_COLS) do
            local fs, at = heads[col.key], layout.byKey[col.key]
            fs:SetText(TITLES[col.key])
            fs:ClearAllPoints()
            if col.key == "name" then
                fs:SetPoint("LEFT", standHead, "LEFT", at.x + 4, 0)
            else
                fs:SetPoint("RIGHT", standHead, "LEFT", at.x + at.w - 4, 0)
            end
            fs:SetShown(at.shown)
        end

        local list
        if account then
            list = queue and inScope(P.QueueStandings, P, account.key) or inScope(P.CounterStandings, P, account.key)
        else
            list = inScope(P.GetStandings, P)
        end
        for i, s in ipairs(list) do
            local row = standRow(i)
            local cr, cg, cb = paperClass(s.class)
            local values = {
                -- A bonus kept per item (issue #433): the row is the player's on that item.
                rank = tostring(i), name = s.itemId and string.format("%s \194\183 %s", s.name,
                    GuildOS.Compat.GetItemInfo(s.itemId) or ("#" .. s.itemId)) or s.name,
                cur = account and (queue and ("#" .. s.value) or tostring(s.value))
                    or (epgp and string.format("%.2f", math.max(0, s.pr or 0)) or tostring(s.current)),
                earned = account and "" or tostring(s.earned),
                spent = account and "" or tostring(epgp and inScope(P.GP, P, s.key) or s.spent),
            }
            for _, col in ipairs(STAND_COLS) do
                local fs, at = row.cells[col.key], layout.byKey[col.key]
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", at.x + 4, 0)
                fs:SetWidth(math.max(1, at.w - 8))
                fs:SetShown(at.shown)
                fs:SetText(values[col.key])
            end
            -- The member in their class's colour as the paper prints it, the figures in the paper's ink.
            row.cells.name:SetTextColor(cr, cg, cb)
            GuildOS:ApplyFont(row.cells.name, 12, "button")
            row.cells.cur:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
            row.cells.earned:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
            row.cells.spent:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
            row.cells.rank:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        end
        for i = #list + 1, #standRows do standRows[i]:Hide() end
        empty:SetText(account and L["Nobody on this account yet."] or L["No points recorded yet."])
        empty:SetShown(#list == 0)
        standChild:SetHeight(math.max(1, #list * ROW_H))

        if withLog then
            local log = inScope(P.GetLog, P, 60)
            for i, e in ipairs(log) do
                local row = logRow(i)
                local up = (e.delta or 0) >= 0
                local col = up and PAPER_OK or PAPER_BAD
                row.line:SetText(GuildOS:ColorText((up and "+" or "") .. (e.delta or 0), col.r, col.g, col.b) .. " " .. (e.name or "?")
                    .. ((e.reason and e.reason ~= "") and (" \194\183 " .. e.reason) or ""))
                row.sub:SetText(string.format(L["%s, by %s"], GuildOS:DateText(e.ts or 0, " %H:%M"), e.author or "?"))
            end
            for i = #log + 1, #logRows do logRows[i]:Hide() end
            logEmpty:SetShown(#log == 0)
            logChild:SetHeight(math.max(1, #log * 30))
        end
    end

    -- The points' settings of the core picked, for its officers: one place for each (issue #346).
    drawSettings = function()
        local content = setChild
        for _, child in pairs({ content:GetChildren() }) do child:Hide() end
        for _, region in pairs({ content:GetRegions() }) do region:Hide() end
        local mode = inScope(P.GetMode, P)
        local cfg = inScope(function() return P:Pool().config end) or {}
        local epgp = GuildOS:GetLootSystem(scope) == "epgp" or mode == "epgp"
        local y = 0
        -- A form's label: the left column, in the text colour (#371).
        local function lbl(text, yy)
            local t = UI:CreateText(content, text, 12, C.text.r, C.text.g, C.text.b)
            t:SetPoint("TOPLEFT", 0, -(yy + 4))
            return t
        end
        -- The label column: past the widest label, never before 200; the form's every field starts there.
        local widths = {}
        for i, f in ipairs(NUMBER_FIELDS) do
            local probe = UI:CreateText(content, f.label, 12)
            widths[i] = probe:GetStringWidth() or 0
            probe:Hide()
        end
        for _, text in ipairs({ L["Mode:"], L["Decay rounding:"] }) do
            local probe = UI:CreateText(content, text, 12)
            widths[#widths + 1] = probe:GetStringWidth() or 0
            probe:Hide()
        end
        local x = UI.LabelColumn(widths, 0, 12, 200)

        -- Mode: DKP; EPGP is the loot system's own (issue #319). The "Loot Council" mode is gone: it did
        -- nothing DKP does not (audit R9, B16).
        if GuildOS:GetLootSystem(scope) ~= "epgp" then
            lbl(L["Mode:"], y)
            local modes = { { value = "dkp", text = "DKP" } }
            if mode == "epgp" then table.insert(modes, 2, { value = "epgp", text = "EPGP" }) end
            local modeDD = UI:CreateDropdown(content, 160, 22)
            modeDD:SetPoint("TOPLEFT", x, -y)
            modeDD:SetOptions(modes)
            modeDD:SetValue(mode)
            modeDD.isMode = true
            modeDD.onSelect = function(_, m) P:SetMode(m, scope); refresh() end
            y = y + 30
        end
        for _, f in ipairs(NUMBER_FIELDS) do
            if not ((f.epgp and not epgp) or (f.dkp and epgp)) then
                lbl(f.label, y)
                local box = input(content, 60, true, 6)
                box:SetPoint("TOPLEFT", x, -y)
                box:SetText(tostring(cfg[f.key] or 0))
                box.pointsKey = f.key
                local key = f.key
                UI:AttachSaveButton(box, function(b2)
                    local kept = P:SetConfigKey(key, b2:GetText(), scope)
                    if kept ~= nil then b2:SetText(tostring(kept)) end
                end, { state = true })
                if f.hint then
                    local h = UI:CreateText(content, f.hint, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                    h:SetPoint("LEFT", box.saveButton, "RIGHT", 8, 0)
                    h:SetPoint("RIGHT", content, "RIGHT", -4, 0)
                    h:SetJustifyH("LEFT")
                    if h.SetWordWrap then h:SetWordWrap(false) end
                end
                y = y + 28
            end
        end
        lbl(L["Decay rounding:"], y)
        local roundDD = UI:CreateDropdown(content, 140, 22)
        roundDD:SetPoint("TOPLEFT", x, -y)
        roundDD:SetOptions({ { value = "near", text = L["Nearest"] }, { value = "up", text = L["Up"] }, { value = "down", text = L["Down"] } })
        roundDD:SetValue(cfg.decayRound or "near")
        roundDD.onSelect = function(_, v) P:SetConfigKey("decayRound", v, scope) end
        y = y + 30
        -- A switch at the content's edge, its box flush with the labels above it (#371).
        local function switch(key, text)
            local cb = UI:CreateCheckbox(content, text, 14)
            cb:SetPoint("TOPLEFT", 0, -(y + 4))
            cb.checkbox:SetChecked(cfg[key] == true)
            cb.checkbox.pointsKey = key
            cb.checkbox.onChanged = function(_, checked) P:SetConfigKey(key, checked, scope) end
            y = y + 26
        end
        switch("raidEndAwards", L["Pay the raid-end awards (the raid leader's client pays)"])
        switch("autoAward", L["Auto-award on boss kill (raid leader only)"])

        -- The guild's own reasons to earn (issue #309): each with what it gives and how much a week.
        -- A section of the form, under the shared title (#371).
        y = y + HEAD_ABOVE
        local rsTitle = UI:CreateSectionTitle(content, L["Other reasons to earn points"])
        rsTitle:SetPoint("TOPLEFT", 0, -y)
        y = y + 26
        for _, r in ipairs(inScope(P.GetReasons, P)) do
            local line = UI:CreateText(content, string.format(
                (r.weekly or 0) > 0 and L["%s: %d points, up to %d a week"] or L["%s: %d points"],
                r.name, r.value, r.weekly), 12, C.text.r, C.text.g, C.text.b)
            line:SetPoint("TOPLEFT", 0, -(y + 4))
            local del = UI:CreateButton(content, L["Remove"], 70, 22)
            del:SetPoint("TOPLEFT", x + 160, -y)
            local rk = r.key
            del:SetScript("OnClick", function() inScope(P.SetReason, P, rk); refresh() end)
            y = y + 28
        end
        y = y + HINT_H + 2
        local function reasonBox(width, numeric, bx, tip)
            local box = input(content, width, numeric, numeric and 4 or 40)
            box:SetPoint("TOPLEFT", bx, -y)
            local h = UI:CreateText(content, tip, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            h:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)
            return box
        end
        local rsName = reasonBox(180, false, 0, L["Reason"])
        local rsValue = reasonBox(50, true, 186, L["Points"])
        local rsWeekly = reasonBox(50, true, 242, L["Per week"])
        local rsAdd = UI:CreateButton(content, L["Add reason"], 100, 22)
        rsAdd:SetPoint("TOPLEFT", 302, -y)
        rsAdd:SetScript("OnClick", function()
            local name = strtrim(rsName:GetText() or "")
            if name == "" or not tonumber(rsValue:GetText()) then return end
            inScope(P.SetReason, P, name, name, rsValue:GetText(), rsWeekly:GetText())
            refresh()
        end)
        y = y + 34
        content:SetHeight(math.max(1, y))
    end

    if settingsBtn then
        settingsBtn:SetScript("OnClick", function()
            settingsOpen = not settingsOpen
            settingsBtn.label:SetText(settingsOpen and L["Back to the standings"] or L["Account settings"])
            refresh()
        end)
    end
    coreDD.onSelect = function(_, v) scope = v; refresh() end
    acctDD.onSelect = function(_, v) shownAcct = v or nil; refresh() end

    panel.SetScope = function(v)
        if v ~= "" and not (GuildOS.db.cores and GuildOS.db.cores[v]) then v = "" end
        scope = v
        refresh()
    end
    panel.Refresh = refresh
    panel.Scope = function() return scope end
    P.uiRefresh = refresh
    panel:SetScript("OnShow", refresh)
    UI:MakeResponsive(body, function() refresh() end)
end
