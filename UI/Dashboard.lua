----------------------------------------------------------------------
-- Guild OS - Home Dashboard
-- The default landing tab: a card grid that surfaces the most useful
-- at-a-glance info (next raid + your RSVP, your readiness, guild pulse,
-- recruitment, your loot, recent activity), each card clicking through to
-- its full tab. Everything is read from existing modules; nothing here
-- owns state. Refreshes on show.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

-- Font-safe status marks (FRIZQT lacks many symbol glyphs, so use the native
-- Indicator textures instead of unicode ticks/dots — see the circle-glyph bug).
local TICK  = "|TInterface\\COMMON\\Indicator-Green:12|t "
local CROSS = "|TInterface\\COMMON\\Indicator-Red:12|t "

local function CAL() return BRutus.Calendar end
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function myKey() return BRutus:GetPlayerKey(UnitName("player"), GetRealmName()) end

-- Hide everything a previous fill created inside a card body.
local function clearBody(body)
    for _, c in pairs({ body:GetChildren() }) do c:Hide() end
    for _, r in pairs({ body:GetRegions() }) do r:Hide() end
end

-- "in 2d 4h" / "in 3h 10m" / "in 25m" / "now".
local function fmtCountdown(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format(L["in %dd %dh"], d, h) end
    if h > 0 then return string.format(L["in %dh %dm"], h, m) end
    return string.format(L["in %dm"], math.max(1, m))
end

local function truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return s:sub(1, n - 1) .. "..."
end

----------------------------------------------------------------------
-- Build the dashboard into a tab panel; return its refresh fn.
----------------------------------------------------------------------
function BRutus:CreateDashboardPanel(panel, mainFrame)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- Navigate to a tab (and optional sub-tab of a hub panel).
    local function goTab(tabKey, subKey)
        if not (mainFrame and mainFrame.SetActiveTab) then return end
        mainFrame:SetActiveTab(tabKey)
        if subKey then
            local gp = mainFrame.tabPanels and mainFrame.tabPanels[tabKey]
            if gp and gp.SelectSub then gp.SelectSub(subKey) end
        end
    end

    -- Card = dark panel with a gold header + a body frame + click-through.
    local function makeCard(title, tabKey, subKey)
        local card = UI:CreateDarkPanel(f)
        card:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
        local hdr = UI:CreateHeaderText(card, title, 11)
        hdr:SetPoint("TOPLEFT", 12, -9)
        card.hdr = hdr

        local arrow = UI:CreateText(card, ">", 13, C.silver.r, C.silver.g, C.silver.b)
        arrow:SetPoint("TOPRIGHT", -10, -8)

        local body = CreateFrame("Frame", nil, card)
        body:SetPoint("TOPLEFT", 12, -28)
        body:SetPoint("BOTTOMRIGHT", -10, 10)
        card.body = body

        if tabKey then
            card:EnableMouse(true)
            card:SetScript("OnMouseUp", function() goTab(tabKey, subKey) end)
            card:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
                arrow:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            end)
            card:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
                arrow:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            end)
        end
        return card
    end

    local cNext     = makeCard(L["NEXT EVENT"],      "guild",       "calendar")
    local cReady    = makeCard(L["YOUR READINESS"],  "raids")
    local cPulse    = makeCard(L["GUILD PULSE"],     "roster")
    local cRecruit  = makeCard(L["RECRUITMENT"],     "recruitment")
    local cLoot     = makeCard(L["YOUR LOOT"],       "loot")
    local cActivity = makeCard(L["GUILD ACTIVITY"],  "guild", "activity")

    ------------------------------------------------------------------
    -- Card fills (each clears its body and rebuilds from live data)
    ------------------------------------------------------------------
    local function fillNext(body)
        clearBody(body)
        local e = CAL() and CAL():NextEvent()
        if not e then
            local none = UI:CreateText(body, L["No upcoming events scheduled."], 11, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 2, -2)
            return
        end
        local kindTxt = (CAL().KindLabel and CAL():KindLabel(e.kind)) or ""
        local title = UI:CreateText(body, "|cffFFFFFF" .. truncate(e.title or "?", 34) .. "|r", 14, C.gold.r, C.gold.g, C.gold.b)
        title:SetPoint("TOPLEFT", 2, -2)
        local sub = UI:CreateText(body, string.format("%s  ·  %s  ·  |cff9AA0AA%s|r",
            date("%a %d %b, %H:%M", e.when), fmtCountdown((e.when or 0) - nowT()), kindTxt),
            10, C.silver.r, C.silver.g, C.silver.b)
        sub:SetPoint("TOPLEFT", 2, -24)

        local comp = CAL():GetComposition(e)
        local compFS = UI:CreateText(body, string.format(L["%d going · %d tentative  |  %dT %dH %dD"],
            comp.yes, comp.tentative, comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS),
            10, C.textDim.r, C.textDim.g, C.textDim.b)
        compFS:SetPoint("TOPLEFT", 2, -42)

        -- Quick RSVP row (keeps the player's current role).
        local mine = CAL():MyRsvp(e)
        local role = (mine and mine.role) or "DPS"
        local myLbl = UI:CreateText(body, L["You:"], 10, C.silver.r, C.silver.g, C.silver.b)
        myLbl:SetPoint("TOPLEFT", 2, -66)
        local function rsvpBtn(text, status, anchor, xoff, col)
            local b = UI:CreateButton(body, text, 58, 20)
            if anchor then b:SetPoint("LEFT", anchor, "RIGHT", xoff, 0)
            else b:SetPoint("TOPLEFT", 40, -64) end
            if mine and mine.status == status then
                b:SetBaseColor(col.r * 0.34, col.g * 0.34, col.b * 0.34, 0.95)
            end
            b:SetScript("OnClick", function() CAL():Rsvp(e.id, status, role); f.Refresh() end)
            return b
        end
        local bYes = rsvpBtn(L["Going"],     "yes",       nil, 0,  C.online)
        local bTen = rsvpBtn(L["Tentative"], "tentative", bYes, 6, C.gold)
        rsvpBtn(L["Absent"], "no", bTen, 6, C.red)
    end

    local function fillReady(body, myRow)
        clearBody(body)
        if not myRow then
            local none = UI:CreateText(body, L["No readiness data yet — open the roster to sync."], 10, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 2, -2); none:SetWidth(body:GetWidth() - 4); none:SetJustifyH("LEFT")
            return
        end
        local y = 0
        local function line(ok, txt, warnTxt)
            local fs = UI:CreateText(body, (ok and TICK or CROSS) .. (ok and txt or (warnTxt or txt)), 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 2, -y); y = y + 20
        end
        -- Attunements
        if (myRow.attTotal or 0) > 0 then
            line(myRow.attDone >= myRow.attTotal,
                string.format(L["Attunements (%d/%d)"], myRow.attDone, myRow.attTotal),
                string.format(L["Attunements (%d/%d)"], myRow.attDone, myRow.attTotal))
        end
        -- Enchants
        if myRow.hasGear then
            line((myRow.missEnch or 0) == 0, L["Enchants complete"],
                string.format(L["Enchants: %d missing"], myRow.missEnch or 0))
        end
        -- Consumables (nil = never checked this raid)
        if myRow.missCons ~= nil then
            line(myRow.missCons == 0, L["Consumables stocked"],
                string.format(L["Consumables: %d missing"], myRow.missCons))
        end
        -- Overall verdict
        local verdict, vcol
        if myRow.status == "ready" then verdict, vcol = L["You're raid-ready!"], C.online
        elseif myRow.status == "warn" or myRow.status == "notready" then verdict, vcol = L["Needs attention"], C.gold
        else verdict, vcol = L["Not enough data yet"], C.silver end
        local v = UI:CreateText(body, verdict, 11, vcol.r, vcol.g, vcol.b)
        v:SetPoint("TOPLEFT", 2, -(y + 4))
    end

    local function fillPulse(body, rows)
        clearBody(body)
        local total, online, iSum, iN = 0, 0, 0, 0
        for _, r in ipairs(rows or {}) do
            total = total + 1
            if r.online then online = online + 1 end
            if (r.ilvl or 0) > 0 then iSum = iSum + r.ilvl; iN = iN + 1 end
        end
        local avgIlvl = iN > 0 and math.floor(iSum / iN) or 0

        -- Raid-ready = max-level (70) members, counted straight from the guild
        -- roster so offline members count too — a stable, motivating number even
        -- with the guild offline. Level is a roster field known for everyone, so
        -- this needs no synced data. (Future: also gate on attunement.)
        local ready = 0
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local _, _, _, level = GetGuildRosterInfo(i)
            if (level or 0) >= 70 then ready = ready + 1 end
        end
        local stats = {
            { string.format("%d", online),  L["online"],     C.online },
            { string.format("%d", total),   L["members"],    C.text },
            { avgIlvl > 0 and tostring(avgIlvl) or "—", L["avg iLvl"], C.gold },
            { string.format("%d", ready),   L["raid-ready"], C.accent },
        }
        local colW = math.floor((body:GetWidth()) / 2)
        for i, s in ipairs(stats) do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            local val = UI:CreateText(body, s[1], 18, s[3].r, s[3].g, s[3].b)
            val:SetPoint("TOPLEFT", col * colW + 2, -(row * 42))
            local lbl = UI:CreateText(body, s[2], 9, C.textDim.r, C.textDim.g, C.textDim.b)
            lbl:SetPoint("TOPLEFT", col * colW + 2, -(row * 42 + 22))
        end
    end

    local function fillRecruit(body)
        clearBody(body)
        local info = BRutus.db and BRutus.db.guildRecruitment
        local isOfficer = BRutus:IsOfficer()
        if not info or not info.enabled or not info.message or info.message == "" then
            local txt = isOfficer and L["Recruitment is off. Set it up in the Recruitment tab."]
                                   or L["Your guild isn't recruiting right now."]
            local none = UI:CreateText(body, txt, 10, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 2, -2); none:SetWidth(body:GetWidth() - 4); none:SetJustifyH("LEFT")
            return
        end
        local status = UI:CreateText(body, "|TInterface\\COMMON\\Indicator-Green:12|t |cff4CFF4C" .. L["Guild is recruiting"] .. "|r", 12, C.text.r, C.text.g, C.text.b)
        status:SetPoint("TOPLEFT", 2, -2)
        local msg = UI:CreateText(body, "\"" .. truncate(info.message, 90) .. "\"", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        msg:SetPoint("TOPLEFT", 2, -22); msg:SetWidth(body:GetWidth() - 4); msg:SetJustifyH("LEFT")

        if isOfficer then
            local b = UI:CreateButton(body, L["Broadcast now"], 110, 20)
            b:SetPoint("BOTTOMLEFT", 2, 2)
            b:SetScript("OnClick", function() if BRutus.Recruitment then BRutus.Recruitment:BroadcastStatus() end end)
        else
            local participating = BRutus.db.recruitParticipate == true
            local b = UI:CreateButton(body, participating and L["Helping"] or L["Help spread it"], 120, 20)
            if participating then b:SetBaseColor(C.online.r * 0.32, C.online.g * 0.32, C.online.b * 0.32, 0.9) end
            b:SetPoint("BOTTOMLEFT", 2, 2)
            b:SetScript("OnClick", function()
                if BRutus.Recruitment then BRutus.Recruitment:SetParticipation(not participating) end
                f.Refresh()
            end)
        end
    end

    local function fillLoot(body)
        clearBody(body)
        local items = BRutus.LootTracker and BRutus.LootTracker:GetPlayerLoot(myKey(), 4) or {}
        if #items == 0 then
            local none = UI:CreateText(body, L["No loot recorded for you yet."], 10, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 2, -2)
            return
        end
        local y = 0
        for _, it in ipairs(items) do
            local where = (it.raid and it.raid ~= "") and ("  |cff777777" .. truncate(it.raid, 16) .. "|r") or ""
            local fs = UI:CreateText(body, "|cffEDCC7B*|r " .. (it.itemLink or it.itemName or "?") .. where, 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 2, -y); fs:SetWidth(body:GetWidth() - 4); fs:SetJustifyH("LEFT")
            y = y + 18
        end
    end

    local function fillActivity(body)
        clearBody(body)
        local lines = {}
        if BRutus.Digest then
            local since = nowT() - 7 * 86400
            lines = BRutus.Digest:Build(since) or {}
        end
        if #lines == 0 then
            local none = UI:CreateText(body, L["Nothing new in the last 7 days."], 10, C.silver.r, C.silver.g, C.silver.b)
            none:SetPoint("TOPLEFT", 2, -2)
            return
        end
        local colW = math.floor(body:GetWidth() / 2) - 6
        local y0, y1 = 0, 0
        for i = 1, math.min(#lines, 8) do
            local col = (i - 1) % 2
            local x = 2 + col * (colW + 12)
            local yy = (col == 0) and y0 or y1
            local dot = UI:CreateText(body, "|cffEDCC7B*|r", 11, C.gold.r, C.gold.g, C.gold.b)
            dot:SetPoint("TOPLEFT", x, -yy)
            local fs = UI:CreateText(body, lines[i], 10, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", x + 12, -yy); fs:SetWidth(colW - 14); fs:SetJustifyH("LEFT")
            local adv = math.max(18, (fs:GetStringHeight() or 12) + 6)
            if col == 0 then y0 = y0 + adv else y1 = y1 + adv end
        end
    end

    ------------------------------------------------------------------
    -- Layout (responsive) + fill
    ------------------------------------------------------------------
    function f.Refresh()
        local W = f:GetWidth();  if not W or W < 200 then W = 1000 end
        local H = f:GetHeight(); if not H or H < 200 then H = 520 end
        local M, G = 12, 10
        local innerW = W - 2 * M

        -- Row 1: Next Raid (wider) + Readiness
        local r1h = 126
        local leftW = math.floor((innerW - G) * 0.56)
        local rightW = innerW - G - leftW
        cNext:ClearAllPoints();  cNext:SetPoint("TOPLEFT", M, -M);                 cNext:SetSize(leftW, r1h)
        cReady:ClearAllPoints(); cReady:SetPoint("TOPLEFT", M + leftW + G, -M);    cReady:SetSize(rightW, r1h)

        -- Row 2: Pulse + Recruitment + Loot
        local r2y = M + r1h + G
        local r2h = 120
        local w3 = math.floor((innerW - 2 * G) / 3)
        cPulse:ClearAllPoints();   cPulse:SetPoint("TOPLEFT", M, -r2y);                       cPulse:SetSize(w3, r2h)
        cRecruit:ClearAllPoints(); cRecruit:SetPoint("TOPLEFT", M + w3 + G, -r2y);            cRecruit:SetSize(w3, r2h)
        cLoot:ClearAllPoints();    cLoot:SetPoint("TOPLEFT", M + 2 * (w3 + G), -r2y);         cLoot:SetSize(innerW - 2 * (w3 + G), r2h)

        -- Row 3: Activity (full width, fills remaining height)
        local r3y = r2y + r2h + G
        local r3h = math.max(90, H - r3y - M)
        cActivity:ClearAllPoints(); cActivity:SetPoint("TOPLEFT", M, -r3y); cActivity:SetSize(innerW, r3h)

        -- One readiness scan powers both the readiness + pulse cards.
        local rows = BRutus.Readiness and BRutus.Readiness:GetReport() or {}
        local myShort = UnitName("player")
        local myRow
        for _, r in ipairs(rows) do if r.name == myShort then myRow = r break end end

        fillNext(cNext.body)
        fillReady(cReady.body, myRow)
        fillPulse(cPulse.body, rows)
        fillRecruit(cRecruit.body)
        fillLoot(cLoot.body)
        fillActivity(cActivity.body)
    end

    -- Refresh whenever the tab becomes visible.
    panel:HookScript("OnShow", function() BRutus:SafeCall(f.Refresh) end)

    return f.Refresh
end
