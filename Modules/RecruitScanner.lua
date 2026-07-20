----------------------------------------------------------------------
-- Guild OS - Recruit Scanner
-- Active recruiting: /who-scan unguilded candidates, mass-whisper a
-- template, capture replies. Officer-gated, OFF by default, fail-safe.
----------------------------------------------------------------------
local RecruitScanner = {}
BRutus.RecruitScanner = RecruitScanner
local L = BRutus.L

RecruitScanner.DEFAULTS = {
    template    = "Hi [player], we're recruiting — whisper me if interested!",
    minLevel    = 0,
    maxLevel    = 70,
    classes     = {},     -- set { WARRIOR=true }; empty = any
    batchMax    = 10,
    cooldownSec = 1800,
}

function RecruitScanner:Initialize()
    BRutus.db.recruitScanner = BRutus.db.recruitScanner or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.recruitScanner[k] == nil then
            BRutus.db.recruitScanner[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    BRutus.db.recruitScanner.inbox = BRutus.db.recruitScanner.inbox or {}
    self._results = {}
    self._contactCd = {}
    self._RegisterEvents = self._RegisterEvents or function() end
    self:_RegisterEvents()      -- real body in Task 2 (until then, a stub below)
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure logic (unit-tested)
----------------------------------------------------------------------
function RecruitScanner:_ExpandTemplate(tmpl, cand)
    tmpl = tmpl or ""
    cand = cand or {}
    local out = tmpl
    out = out:gsub("%[player%]", cand.name or "")
    out = out:gsub("%[class%]", cand.class or "")
    out = out:gsub("%[level%]", tostring(cand.level or ""))
    return out
end

function RecruitScanner:_CandidateOK(cand, filters, isBannedFn)
    if not cand or not cand.name then return false end
    if cand.guilded then return false end                       -- unguilded only
    filters = filters or {}
    if (filters.minLevel or 0) > 0 and (cand.level or 0) < filters.minLevel then return false end
    if filters.maxLevel and (cand.level or 0) > filters.maxLevel then return false end
    if filters.classes and next(filters.classes) ~= nil and not filters.classes[cand.class] then return false end
    if isBannedFn and isBannedFn(cand.name) then return false end
    return true
end

----------------------------------------------------------------------
-- /who scan (fail-safe)
----------------------------------------------------------------------
function RecruitScanner:Scan(onDone)
    if not BRutus:IsOfficer() then return end
    if self._scanBusy then return end
    self._scanBusy = true
    self._results = {}
    local cfg = BRutus.db.recruitScanner
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() RecruitScanner:_OnWhoResult() end)
    end
    self._whoFrame:RegisterEvent("WHO_LIST_UPDATE")
    self._onScanDone = onDone
    if SetWhoToUI then SetWhoToUI(1) end
    -- level-range query; Blizzard caps results (~50). classes filtered post-hoc.
    local q = string.format("%d-%d", (cfg.minLevel or 1) > 0 and cfg.minLevel or 1, cfg.maxLevel or 70)
    SendWho(q)
    BRutus.Compat.After(6, function()
        if RecruitScanner._scanBusy then RecruitScanner:_FinishScan() end
    end)
end

function RecruitScanner:_OnWhoResult()
    local cfg = BRutus.db.recruitScanner
    local isBanned = function(n) return BRutus.BanList and BRutus.BanList:IsBanned(n) end
    local out = {}
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName then
                local short = w.fullName:match("^([^-]+)") or w.fullName
                local cand = {
                    name = short, level = w.level, class = w.filename,
                    zone = w.area, guilded = (w.fullGuildName ~= nil and w.fullGuildName ~= ""),
                }
                if self:_CandidateOK(cand, cfg, isBanned) then out[#out + 1] = cand end
            end
        end
    end
    self._results = out
    self:_FinishScan()
end

function RecruitScanner:_FinishScan()
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    if SetWhoToUI then SetWhoToUI(0) end
    self._scanBusy = nil
    if self._onScanDone then BRutus:SafeCall(self._onScanDone) end
end

function RecruitScanner:GetResults() return self._results or {} end

----------------------------------------------------------------------
-- Mass-whisper (throttled, cooldown, batch-capped)
----------------------------------------------------------------------
function RecruitScanner:WhisperSelected(names)
    if not BRutus:IsOfficer() then return end
    local cfg = BRutus.db.recruitScanner
    local now = GetServerTime()
    local sent, delay = 0, 0
    for _, name in ipairs(names or {}) do
        if sent >= (cfg.batchMax or 10) then break end
        local cd = self._contactCd[name]
        if not (cd and cd > now) then
            local cand
            for _, r in ipairs(self._results) do if r.name == name then cand = r; break end end
            local msg = self:_ExpandTemplate(cfg.template, cand or { name = name })
            self._contactCd[name] = now + (cfg.cooldownSec or 1800)
            sent = sent + 1
            delay = delay + 1.5    -- throttle: 1.5s between whispers
            BRutus.Compat.After(delay, function()
                SendChatMessage(msg, "WHISPER", nil, name)
            end)
        end
    end
    if sent > 0 then
        BRutus:Print(string.format(BRutus.L["Whispering %d candidate(s)…"], sent))
    end
end

----------------------------------------------------------------------
-- Reply inbox
----------------------------------------------------------------------
function RecruitScanner:_RegisterEvents()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        local short = author and (author:match("^([^-]+)") or author)
        if short and RecruitScanner._contactCd[short] then
            local inbox = BRutus.db.recruitScanner.inbox
            table.insert(inbox, 1, { name = short, msg = msg, ts = GetServerTime() })
            while #inbox > 200 do table.remove(inbox) end
        end
    end)
end

function RecruitScanner:GetInbox() return (BRutus.db.recruitScanner and BRutus.db.recruitScanner.inbox) or {} end

----------------------------------------------------------------------
-- Whisper-selected confirmation (standard Blizzard popup; avoids an
-- accidental mass-whisper). Registered once at file load — same pattern
-- as UI/CalendarPanel.lua's GUILDOS_CALENDAR_DELETE.
----------------------------------------------------------------------
if not StaticPopupDialogs["GUILDOS_SCOUT_WHISPER_CONFIRM"] then
    StaticPopupDialogs["GUILDOS_SCOUT_WHISPER_CONFIRM"] = {
        text = L["Whisper %d players?"],
        button1 = YES, button2 = NO,
        OnAccept = function(dlg, data)
            local names = data or (dlg and dlg.data)
            if names then RecruitScanner:WhisperSelected(names) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- UI (self-contained popup — mirrors Modules/Bulletin.lua:Show())
----------------------------------------------------------------------
local ROW_HEIGHT = 20

function RecruitScanner:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSRecruitScannerFrame", UIParent, "BackdropTemplate")
        f:SetSize(480, 460)
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

        local title = UI:CreateTitle(f, L["Recruit Scanner"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        -- Officer gate is checked once at build time (mirrors Bulletin.lua's
        -- officer-only post box): non-officers get a static notice and no
        -- controls are ever created for them.
        f.isOfficer = BRutus:IsOfficer()
        if not f.isOfficer then
            local notice = UI:CreateText(f, L["Officers only."], 12, C.silver.r, C.silver.g, C.silver.b)
            notice:SetPoint("TOPLEFT", 16, -50)
        else
            self._selected = self._selected or {}
            self._view = self._view or "results"
            local cfg = BRutus.db.recruitScanner

            ------------------------------------------------------------
            -- Filters row: Min level / Max level / Scan
            ------------------------------------------------------------
            local minLbl = UI:CreateText(f, L["Min level"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
            minLbl:SetPoint("TOPLEFT", 16, -46)
            local minBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            minBox:SetSize(36, 20)
            minBox:SetPoint("LEFT", minLbl, "RIGHT", 8, 0)
            minBox:SetAutoFocus(false)
            minBox:SetNumeric(true)
            minBox:SetMaxLetters(2)
            minBox:SetText(tostring(cfg.minLevel or 0))
            minBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            local function commitMin(s)
                cfg.minLevel = math.max(0, math.min(70, tonumber(s:GetText()) or 0))
                s:SetText(tostring(cfg.minLevel))
                s:ClearFocus()
            end
            minBox:SetScript("OnEnterPressed", commitMin)
            minBox:SetScript("OnEditFocusLost", commitMin)

            local maxLbl = UI:CreateText(f, L["Max level"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
            maxLbl:SetPoint("LEFT", minBox, "RIGHT", 16, 0)
            local maxBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            maxBox:SetSize(36, 20)
            maxBox:SetPoint("LEFT", maxLbl, "RIGHT", 8, 0)
            maxBox:SetAutoFocus(false)
            maxBox:SetNumeric(true)
            maxBox:SetMaxLetters(2)
            maxBox:SetText(tostring(cfg.maxLevel or 70))
            maxBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            local function commitMax(s)
                cfg.maxLevel = math.max(0, math.min(70, tonumber(s:GetText()) or 70))
                s:SetText(tostring(cfg.maxLevel))
                s:ClearFocus()
            end
            maxBox:SetScript("OnEnterPressed", commitMax)
            maxBox:SetScript("OnEditFocusLost", commitMax)

            local scanBtn = UI:CreateButton(f, L["Scan"], 90, 24)
            scanBtn:SetPoint("LEFT", maxBox, "RIGHT", 16, 0)
            scanBtn:SetScript("OnClick", function()
                RecruitScanner:Scan(function()
                    self._selected = {}
                    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
                end)
                if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end -- immediate busy-state repaint
            end)
            f.scanBtn = scanBtn

            ------------------------------------------------------------
            -- Tabs: Results / Inbox (share a single scroll list)
            ------------------------------------------------------------
            local resultsTab = UI:CreateTab(f, L["Results"], 100)
            resultsTab:SetPoint("TOPLEFT", 16, -80)
            resultsTab:SetScript("OnClick", function()
                self._view = "results"
                if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
            end)
            local inboxTab = UI:CreateTab(f, L["Inbox"], 100)
            inboxTab:SetPoint("LEFT", resultsTab, "RIGHT", 6, 0)
            inboxTab:SetScript("OnClick", function()
                self._view = "inbox"
                if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
            end)
            f.tabs = { results = resultsTab, inbox = inboxTab }

            ------------------------------------------------------------
            -- Results/inbox list (ScrollFrame gotcha: CreateScrollFrame does
            -- NOT anchor the scroll frame itself — SetAllPoints() here, or
            -- content is clipped to 0x0.)
            ------------------------------------------------------------
            local holder = CreateFrame("Frame", nil, f)
            holder:SetPoint("TOPLEFT", 12, -112)
            holder:SetPoint("TOPRIGHT", -12, -112)
            holder:SetHeight(190)
            local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRecruitScannerScroll")
            scroll:SetAllPoints()
            f.child = child
            f.holder = holder

            ------------------------------------------------------------
            -- Message template + token hint
            ------------------------------------------------------------
            local tmplLbl = UI:CreateText(f, L["Message template"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
            tmplLbl:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 4, -10)
            local tmplBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            tmplBox:SetSize(420, 20)
            tmplBox:SetPoint("TOPLEFT", tmplLbl, "BOTTOMLEFT", 4, -6)
            tmplBox:SetAutoFocus(false)
            tmplBox:SetMaxLetters(255)
            tmplBox:SetText(cfg.template or "")
            tmplBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            local function commitTemplate(s)
                cfg.template = s:GetText()
                s:ClearFocus()
            end
            tmplBox:SetScript("OnEnterPressed", commitTemplate)
            tmplBox:SetScript("OnEditFocusLost", commitTemplate)

            local hint = UI:CreateText(f, L["Tokens: [player] [class] [level]"], 9, C.silver.r, C.silver.g, C.silver.b)
            hint:SetPoint("TOPLEFT", tmplBox, "BOTTOMLEFT", 0, -6)

            local whisperBtn = UI:CreateButton(f, L["Whisper selected"], 150, 24)
            whisperBtn:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -2, -10)
            whisperBtn:SetScript("OnClick", function()
                local names = {}
                for name in pairs(self._selected) do names[#names + 1] = name end
                if #names == 0 then return end
                local dlg = StaticPopup_Show("GUILDOS_SCOUT_WHISPER_CONFIRM", #names, nil, names)
                if dlg then dlg.data = names end
            end)
            f.whisperBtn = whisperBtn
        end

        self.frame = f
    end

    local function refresh()
        if not f:IsShown() or not f.isOfficer then return end

        if RecruitScanner._scanBusy then
            f.scanBtn:Disable()
            f.scanBtn.label:SetText(L["Scanning…"])
        else
            f.scanBtn:Enable()
            f.scanBtn.label:SetText(L["Scan"])
        end
        for view, tab in pairs(f.tabs) do tab:SetActive(view == self._view) end

        -- Reset ALL row state before repaint (regions and any child frames).
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local y = 0
        if self._view == "results" then
            local results = RecruitScanner:GetResults()
            for _, cand in ipairs(results) do
                local sel = UI:CreateCheckbox(child, "", 16)
                sel:SetPoint("TOPLEFT", 2, -y)
                sel.checkbox:SetChecked(self._selected[cand.name] and true or false)
                sel.checkbox.onChanged = function(_, checked)
                    if checked then self._selected[cand.name] = true
                    else self._selected[cand.name] = nil end
                end

                -- Every column below anchors TOPLEFT/TOPRIGHT with the SAME
                -- explicit -y offset against the SAME parent (child). Chaining
                -- "LEFT"/"RIGHT" anchors across sibling frames of different
                -- heights would make WoW resolve conflicting vertical centers
                -- (e.g. a row element vs. the whole scroll child) — explicit
                -- -y on every column sidesteps that entirely.
                local nameFS = UI:CreateText(child, cand.name or "?", 11, C.text.r, C.text.g, C.text.b)
                nameFS:SetPoint("TOPLEFT", 24, -y)
                nameFS:SetWidth(108)
                nameFS:SetJustifyH("LEFT")

                local lvlFS = UI:CreateText(child, tostring(cand.level or "?"), 11, C.textDim.r, C.textDim.g, C.textDim.b)
                lvlFS:SetPoint("TOPLEFT", 134, -y)
                lvlFS:SetWidth(24)

                local classLabel = LOCALIZED_CLASS_NAMES_MALE[cand.class] or cand.class or "?"
                local cc = RAID_CLASS_COLORS[cand.class]
                local classFS = UI:CreateText(child, classLabel, 11,
                    cc and cc.r or C.textDim.r, cc and cc.g or C.textDim.g, cc and cc.b or C.textDim.b)
                classFS:SetPoint("TOPLEFT", 160, -y)
                classFS:SetWidth(84)
                classFS:SetJustifyH("LEFT")

                local zoneFS = UI:CreateText(child, cand.zone or "", 10, C.silver.r, C.silver.g, C.silver.b)
                zoneFS:SetPoint("TOPLEFT", 248, -y)
                zoneFS:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -y)
                zoneFS:SetJustifyH("LEFT")

                y = y + ROW_HEIGHT
            end
            if #results == 0 then
                local empty = UI:CreateText(child, L["No candidates."], 11, C.silver.r, C.silver.g, C.silver.b)
                empty:SetPoint("TOPLEFT", 4, -4)
                y = 20
            end
        else -- inbox
            local inbox = RecruitScanner:GetInbox()
            for _, entry in ipairs(inbox) do
                local nameFS = UI:CreateText(child, entry.name or "?", 11, C.gold.r, C.gold.g, C.gold.b)
                nameFS:SetPoint("TOPLEFT", 4, -y)
                nameFS:SetWidth(88)
                nameFS:SetJustifyH("LEFT")

                local msgFS = UI:CreateText(child, entry.msg or "", 10, C.text.r, C.text.g, C.text.b)
                msgFS:SetPoint("TOPLEFT", 98, -y)
                msgFS:SetPoint("TOPRIGHT", child, "TOPRIGHT", -54, -y)
                msgFS:SetJustifyH("LEFT")
                msgFS:SetWordWrap(false)

                local tsFS = UI:CreateText(child, date("%H:%M", entry.ts or 0), 9, C.silver.r, C.silver.g, C.silver.b)
                tsFS:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -y)

                local rowH = math.max(nameFS:GetStringHeight() or 14, msgFS:GetStringHeight() or 14)
                y = y + rowH + 6
            end
            if #inbox == 0 then
                local empty = UI:CreateText(child, L["No replies yet."], 11, C.silver.r, C.silver.g, C.silver.b)
                empty:SetPoint("TOPLEFT", 4, -4)
                y = 20
            end
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function RecruitScanner:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("scanner.template", function()
        local s = RecruitScanner:_ExpandTemplate("Hi [player] ([level] [class])",
            { name = "Bob", level = 68, class = "MAGE" })
        if s ~= "Hi Bob (68 MAGE)" then return false, s end
        return true
    end)
    S:Register("scanner.candidate_ok", function()
        local f = { minLevel = 60, maxLevel = 70, classes = { MAGE = true } }
        local ok = RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = false }, f)
        if not ok then return false, "should pass" end
        return true
    end)
    S:Register("scanner.reject_guilded", function()
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = true }, {}) then
            return false, "guilded must be rejected"
        end
        return true
    end)
    S:Register("scanner.reject_banned", function()
        local banned = function(n) return n == "Bob" end
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, guilded = false }, {}, banned) then
            return false, "banned must be rejected"
        end
        return true
    end)
end
