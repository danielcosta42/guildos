----------------------------------------------------------------------
-- Guild OS - Accounts (DKP / EPGP / the rule's own accounts)
-- The Loot window's Accounts tab (issue #346): what was the standalone points window. A core and an
-- account to read; for the officers, the award row (who, a named reason or a typed one, how many
-- times, Award or Charge), the raid's award, the decay and the points' own settings; for everyone,
-- the standings and the movements. Visual layer only — all logic lives in GuildOS.Points, run on the
-- pool of the core picked (Points:InCore).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local PAD      = 12
local ROW_H    = 22
local LOG_W    = 260     -- the movements column, when the table leaves room for it
local LOG_MIN  = 640     -- below this the movements go under the standings' place (they drop)
local OTHER    = "__other"   -- the reason the officer types

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
    local input = GuildOS.LootInput
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

    -- ── The selectors ───────────────────────────────────────────────
    local top = CreateFrame("Frame", nil, panel)
    top:SetPoint("TOPLEFT", PAD, -8)
    top:SetPoint("TOPRIGHT", -PAD, -8)
    top:SetHeight(24)
    local coreLbl = UI:CreateHeaderText(top, L["CORE"], 10)
    coreLbl:SetPoint("LEFT", 0, 0)
    local coreDD = UI:CreateDropdown(top, 160, 22)
    coreDD:SetPoint("LEFT", coreLbl, "RIGHT", 8, 0)
    coreDD.isScope = true
    local acctLbl = UI:CreateHeaderText(top, L["ACCOUNT"], 10)
    acctLbl:SetPoint("LEFT", coreDD, "RIGHT", 16, 0)
    local acctDD = UI:CreateDropdown(top, 170, 22)
    acctDD:SetPoint("LEFT", acctLbl, "RIGHT", 8, 0)
    acctDD.isAccount = true
    local summary = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    summary:SetPoint("TOPLEFT", PAD, -36)
    summary:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(false) end

    local isOfficer = GuildOS:IsOfficer()
    local listTop = 56
    local status

    -- ── The award row (officers) ────────────────────────────────────
    local reasonDD, amountBox, nameBox, noteBox, settingsBtn
    local flow   -- the officer's rows, laid out again at every width
    if isOfficer then
        local row = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT", PAD, -56)
        row:SetPoint("TOPRIGHT", -PAD, -56)
        row:SetHeight(24)
        nameBox = input(row, 130, false, 48)
        nameBox:SetPoint("LEFT", 0, 0)
        local nameHint = UI:CreateText(row, L["Who"], 9, C.textDim.r, C.textDim.g, C.textDim.b)
        nameHint:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 0, 1)
        reasonDD = UI:CreateDropdown(row, 200, 22)
        reasonDD:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
        reasonDD.isReason = true
        local reasonHint = UI:CreateText(row, L["Reason"], 9, C.textDim.r, C.textDim.g, C.textDim.b)
        reasonHint:SetPoint("BOTTOMLEFT", reasonDD, "TOPLEFT", 0, 1)
        amountBox = input(row, 50, true, 6)
        amountBox:SetPoint("LEFT", reasonDD, "RIGHT", 6, 0)
        local amountHint = UI:CreateText(row, L["Times"], 9, C.textDim.r, C.textDim.g, C.textDim.b)
        amountHint:SetPoint("BOTTOMLEFT", amountBox, "TOPLEFT", 0, 1)
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

        local row2 = CreateFrame("Frame", nil, panel)
        row2:SetPoint("TOPLEFT", PAD, -86)
        row2:SetPoint("TOPRIGHT", -PAD, -86)
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
        local syncBtn = UI:CreateButton(row2, L["Sync"], 70, 20)
        syncBtn:SetPoint("LEFT", decayBtn, "RIGHT", 6, 0)
        syncBtn:SetScript("OnClick", function()
            P:BroadcastSnapshot(scope)
            status:SetText(L["Points snapshot sent to guild."])
        end)
        settingsBtn = UI:CreateButton(row2, L["Account settings"], 130, 20)
        settingsBtn:SetPoint("RIGHT", 0, 0)
        settingsBtn:ClearAllPoints()
        status = UI:CreateText(panel, "", 10, C.silver.r, C.silver.g, C.silver.b)
        status:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -4)
        status:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        status:SetJustifyH("LEFT")
        if status.SetWordWrap then status:SetWordWrap(false) end
        listTop = 132
        -- Both rows wrap where the window is too narrow for them (FlowBar), the hints over the boxes
        -- keeping their room; what is under them follows.
        flow = function(body)
            local h1 = UI:FlowBar(row, { nameBox, reasonDD, amountBox, noteBox, awardBtn, chargeBtn }, { gap = 6, rowGap = 14, rowH = 22 })
            local top2 = 56 + h1 + 8
            row2:ClearAllPoints()
            row2:SetPoint("TOPLEFT", PAD, -top2)
            row2:SetPoint("TOPRIGHT", -PAD, -top2)
            local h2 = UI:FlowBar(row2, { raidBtn, decayBtn, syncBtn, settingsBtn }, { gap = 6, rowGap = 4, rowH = 20 })
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", PAD, -(top2 + h2 + 20))
            body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        end
    end

    -- ── The standings and the movements ─────────────────────────────
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", PAD, -listTop)
    body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local standHead = CreateFrame("Frame", nil, body)
    standHead:SetPoint("TOPLEFT", 0, 0)
    standHead:SetHeight(18)
    local heads = {}
    for _, col in ipairs(STAND_COLS) do heads[col.key] = UI:CreateHeaderText(standHead, "", 10) end
    local standScroll, standChild = UI:CreateScrollFrame(body, nil)
    standScroll:SetPoint("TOPLEFT", 0, -20)
    local logHead = UI:CreateHeaderText(body, L["MOVEMENTS"], 10)
    logHead:SetPoint("TOPRIGHT", -(LOG_W - 60), 0)
    local logScroll, logChild = UI:CreateScrollFrame(body, nil)
    logScroll:SetPoint("TOPRIGHT", -10, -20)
    logScroll:SetPoint("BOTTOMRIGHT", -10, 0)
    logScroll:SetWidth(LOG_W - 10)
    local standRows, logRows = {}, {}

    -- ── The points' settings (officers): in place of the tables, while open ──
    local setScroll, setChild = UI:CreateScrollFrame(body, nil)
    setScroll:SetPoint("TOPLEFT", 0, 0)
    setScroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:BindScrollChildWidth(setScroll, setChild, 4)
    setScroll:Hide()

    local function standRow(i)
        local row = standRows[i]
        if not row then
            row = CreateFrame("Frame", nil, standChild, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
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
        local bg = (i % 2 == 1) and C.row1 or C.row2
        row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.4)
        row:Show()
        return row
    end

    local function logRow(i)
        local row = logRows[i]
        if not row then
            row = CreateFrame("Frame", nil, logChild)
            row:SetHeight(30)
            row.line = UI:CreateText(row, "", 10)
            row.line:SetPoint("TOPLEFT", 4, 0)
            row.line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.line:SetJustifyH("LEFT")
            row.sub = UI:CreateText(row, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
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

    local empty = UI:CreateText(standChild, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 4, -4)
    local logEmpty = UI:CreateText(logChild, L["No history."], 10, C.silver.r, C.silver.g, C.silver.b)
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

        if flow then flow(body) end
        local mode = inScope(P.GetMode, P)
        local cfg = inScope(function() return P:Pool().config end) or {}
        local MODE_NAME = { dkp = "DKP", epgp = "EPGP", council = L["Loot Council"] }
        summary:SetText(string.format(L["%s  |  Boss award: %d  |  Decay: %d%%  |  Auto-award: %s"], MODE_NAME[mode] or tostring(mode),
            cfg.bossAward or 0, cfg.decayPct or 0, cfg.autoAward and L["on"] or L["off"]))

        if settingsOpen then
            standScroll:Hide(); logScroll:Hide(); standHead:Hide(); logHead:Hide()
            setScroll:Show()
            drawSettings()
            return
        end
        setScroll:Hide()
        standScroll:Show(); standHead:Show()

        -- The movements keep their column while the window leaves room for it; then they drop.
        local W = body:GetWidth() or 0
        local withLog = W >= LOG_MIN
        logScroll:SetShown(withLog)
        logHead:SetShown(withLog)
        standScroll:ClearAllPoints()
        standScroll:SetPoint("TOPLEFT", 0, -20)
        standScroll:SetPoint("BOTTOMRIGHT", withLog and -(LOG_W + 8) or -10, 0)
        standHead:SetWidth(math.max(1, (withLog and W - LOG_W - 8 or W) - 10))
        standChild:SetWidth(math.max(1, standHead:GetWidth()))
        local layout = UI:ResolveColumns(STAND_COLS, standHead:GetWidth(), 6)
        local epgp = mode == "epgp"
        local queue = account and account.type == "queue"
        local TITLES = {
            rank = "#", name = L["MEMBER"],
            cur = (queue and L["PLACE"]) or (epgp and not account and "PR") or L["BALANCE"],
            earned = account and "" or (epgp and "EP" or L["EARNED"]),
            spent = account and "" or (epgp and "GP" or L["SPENT"]),
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
            local cr, cg, cb = GuildOS:GetClassColor(s.class)
            local values = {
                rank = tostring(i), name = s.name,
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
            row.cells.name:SetTextColor(cr, cg, cb)
            row.cells.cur:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            row.cells.earned:SetTextColor(C.green.r, C.green.g, C.green.b)
            row.cells.spent:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            row.cells.rank:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        end
        for i = #list + 1, #standRows do standRows[i]:Hide() end
        empty:SetText(account and L["Nobody on this account yet."] or L["No points recorded yet."])
        empty:SetShown(#list == 0)
        standChild:SetHeight(math.max(1, #list * ROW_H))

        if withLog then
            logChild:SetWidth(LOG_W - 22)
            local log = inScope(P.GetLog, P, 60)
            for i, e in ipairs(log) do
                local row = logRow(i)
                local up = (e.delta or 0) >= 0
                local col = up and C.green or C.red
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
        local function lbl(text, yy)
            local t = UI:CreateText(content, text, 11, C.text.r, C.text.g, C.text.b)
            t:SetPoint("TOPLEFT", 4, -(yy + 4))
            return t
        end
        -- The label column: past the widest label, never before 200.
        local widths = {}
        for i, f in ipairs(NUMBER_FIELDS) do
            local probe = UI:CreateText(content, f.label, 11)
            widths[i] = probe:GetStringWidth() or 0
            probe:Hide()
        end
        local x = UI.LabelColumn(widths, 4, 12, 200)

        -- Mode: DKP or Loot Council; EPGP is the loot system's own (issue #319).
        if GuildOS:GetLootSystem(scope) ~= "epgp" then
            lbl(L["Mode:"], y)
            local modes = { { value = "dkp", text = "DKP" }, { value = "council", text = L["Loot Council"] } }
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
                    local h = UI:CreateText(content, f.hint, 9, C.textDim.r, C.textDim.g, C.textDim.b)
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
        local function switch(key, text)
            local cb = UI:CreateCheckbox(content, text, 18)
            cb:SetPoint("TOPLEFT", 0, -y)
            cb.checkbox:SetChecked(cfg[key] == true)
            cb.checkbox.pointsKey = key
            cb.checkbox.onChanged = function(_, checked) P:SetConfigKey(key, checked, scope) end
            y = y + 26
        end
        switch("raidEndAwards", L["Pay the raid-end awards (the raid leader's client pays)"])
        switch("autoAward", L["Auto-award on boss kill (raid leader only)"])

        -- The guild's own reasons to earn (issue #309): each with what it gives and how much a week.
        y = y + 6
        local rsTitle = UI:CreateHeaderText(content, L["OTHER REASONS TO EARN POINTS"], 10)
        rsTitle:SetPoint("TOPLEFT", 0, -y)
        y = y + 20
        for _, r in ipairs(inScope(P.GetReasons, P)) do
            local line = UI:CreateText(content, string.format(
                (r.weekly or 0) > 0 and L["%s: %d points, up to %d a week"] or L["%s: %d points"],
                r.name, r.value, r.weekly), 10, C.silver.r, C.silver.g, C.silver.b)
            line:SetPoint("TOPLEFT", 12, -(y + 2))
            local del = UI:CreateButton(content, L["Remove"], 70, 18)
            del:SetPoint("TOPLEFT", x + 160, -y)
            local rk = r.key
            del:SetScript("OnClick", function() inScope(P.SetReason, P, rk); refresh() end)
            y = y + 22
        end
        y = y + 14
        local function reasonBox(width, numeric, bx, tip)
            local box = input(content, width, numeric, numeric and 4 or 40)
            box:SetPoint("TOPLEFT", bx, -y)
            local h = UI:CreateText(content, tip, 9, C.textDim.r, C.textDim.g, C.textDim.b)
            h:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 1)
            return box
        end
        local rsName = reasonBox(180, false, 12, L["Reason"])
        local rsValue = reasonBox(50, true, 198, L["Points"])
        local rsWeekly = reasonBox(50, true, 254, L["Per week"])
        local rsAdd = UI:CreateButton(content, L["Add reason"], 100, 22)
        rsAdd:SetPoint("TOPLEFT", 314, -y)
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
