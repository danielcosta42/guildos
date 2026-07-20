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
    BRutus.Compat.SetWhoToUI(true)
    -- level-range query; Blizzard caps results (~50). classes filtered post-hoc.
    local q = string.format("%d-%d", (cfg.minLevel or 1) > 0 and cfg.minLevel or 1, cfg.maxLevel or 70)
    BRutus.Compat.SendWho(q)
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
    BRutus.Compat.SetWhoToUI(false)
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
-- UI (embeddable content + a self-contained popup wrapper — mirrors
-- Modules/Bulletin.lua:Show()). BuildInto() builds every scanner widget
-- as a child of whatever container it's given (the popup body, or a
-- Recruitment-tab sub-panel); Show() just supplies the popup chrome.
--
-- Layout (full-width; see docs/superpowers approved mock):
--   row 1  filters bar: min/max level, class cycle, Scan · "N found" (right)
--   ------ separator
--   row 2  view toggle: Results/Inbox tabs · Select all + "N selected" (right)
--   row 3  column header (Results view only) + separator
--   row 4  THE HERO: full-width, full-height scrolling list
--   ------ footer (pinned to the container bottom)
--          template label/hint, full-width template box, Whisper button
----------------------------------------------------------------------
local ROW_HEIGHT = 20

----------------------------------------------------------------------
-- Build all scanner controls (filters, Scan button, Results/Inbox tabs,
-- results list, template box, Whisper button) as children of `container`.
-- Safe to call more than once overall (e.g. popup body + an embedded
-- sub-tab), but a second call on the SAME container is a no-op, guarded
-- by container._scannerBuilt.
----------------------------------------------------------------------
function RecruitScanner:BuildInto(container)
    if not container then return end
    if container._scannerBuilt then return container._scannerRefresh end
    container._scannerBuilt = true

    local UI = BRutus.UI
    local C = BRutus.Colors
    local f = container
    -- Forward-declared: the button handlers below close over this LOCAL
    -- (not a shared self.uiRefresh) so each container's controls always
    -- repaint that same container — never a different popup/embed built
    -- later, which would otherwise steal a single shared refresh slot.
    local refresh

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
        cfg.classes = cfg.classes or {}

        ------------------------------------------------------------
        -- Row 1 — filters bar: Min level / Max level / Class / Scan,
        -- with a right-aligned "N found" count.
        ------------------------------------------------------------
        local minLbl = UI:CreateText(f, L["Min level"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        minLbl:SetPoint("TOPLEFT", 12, -12)
        local minBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        minBox:SetSize(32, 20)
        minBox:SetPoint("LEFT", minLbl, "RIGHT", 6, 0)
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
        maxLbl:SetPoint("LEFT", minBox, "RIGHT", 14, 0)
        local maxBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        maxBox:SetSize(32, 20)
        maxBox:SetPoint("LEFT", maxLbl, "RIGHT", 6, 0)
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

        -- Class cycle button: Any -> the 9 TBC classes -> Any. Reuses the
        -- class order already defined for the recruitment beacon instead
        -- of duplicating the list here.
        local classBtn = UI:CreateButton(f, "", 132, 24)
        classBtn:SetPoint("LEFT", maxBox, "RIGHT", 14, 0)
        local function currentClass()
            return next(cfg.classes)
        end
        local function classNameFor(cls)
            return cls and (LOCALIZED_CLASS_NAMES_MALE[cls] or cls) or L["Any"]
        end
        local function paintClassBtn()
            classBtn.label:SetText(string.format(L["Class: %s"], classNameFor(currentClass())))
        end
        classBtn:SetScript("OnClick", function()
            local order = (BRutus.Recruitment and BRutus.Recruitment.CLASSES) or {}
            local cur = currentClass()
            local nextCls
            if cur then
                for i, cls in ipairs(order) do
                    if cls == cur then nextCls = order[i + 1]; break end
                end
            else
                nextCls = order[1]
            end
            cfg.classes = nextCls and { [nextCls] = true } or {}
            paintClassBtn()
        end)
        paintClassBtn()
        f.classBtn = classBtn

        local scanBtn = UI:CreateButton(f, L["Scan"], 90, 24)
        scanBtn:SetPoint("LEFT", classBtn, "RIGHT", 14, 0)
        scanBtn:SetScript("OnClick", function()
            RecruitScanner:Scan(function()
                self._selected = {}
                BRutus:SafeCall(refresh)
            end)
            BRutus:SafeCall(refresh) -- immediate busy-state repaint
        end)
        f.scanBtn = scanBtn

        local foundText = UI:CreateText(f, string.format(L["%d found"], 0), 11, C.silver.r, C.silver.g, C.silver.b)
        foundText:SetPoint("TOPRIGHT", -16, -14)
        f.foundText = foundText

        ------------------------------------------------------------
        -- Separator under the filters bar.
        ------------------------------------------------------------
        local sep1 = UI:CreateSeparator(f)
        sep1:SetPoint("TOPLEFT", 12, -46)
        sep1:SetPoint("TOPRIGHT", -12, -46)

        ------------------------------------------------------------
        -- Row 2 — view toggle: Results / Inbox tabs (left) and a
        -- Select-all checkbox + "N selected" count (right).
        ------------------------------------------------------------
        local resultsTab = UI:CreateTab(f, L["Results"], 90)
        resultsTab:SetPoint("TOPLEFT", 12, -54)
        resultsTab:SetScript("OnClick", function()
            self._view = "results"
            BRutus:SafeCall(refresh)
        end)
        local inboxTab = UI:CreateTab(f, L["Inbox"], 90)
        inboxTab:SetPoint("LEFT", resultsTab, "RIGHT", 4, 0)
        inboxTab:SetScript("OnClick", function()
            self._view = "inbox"
            BRutus:SafeCall(refresh)
        end)
        f.tabs = { results = resultsTab, inbox = inboxTab }

        local selectedText = UI:CreateText(f, string.format(L["%d selected"], 0), 11,
            C.textDim.r, C.textDim.g, C.textDim.b)
        selectedText:SetPoint("TOPRIGHT", -16, -60)
        f.selectedText = selectedText

        local selectAllCb = UI:CreateCheckbox(f, L["Select all"], 16)
        -- CreateCheckbox pads its frame out to size+200 (room for long
        -- labels elsewhere in the app); shrink it to its visible content
        -- so it can be anchored snugly against selectedText instead of
        -- floating 200px past the label, per the ScrollFrame-gotcha-style
        -- lesson of not trusting a helper's default frame bounds.
        selectAllCb:SetWidth(16 + 6 + (selectAllCb.label:GetStringWidth() or 50) + 4)
        selectAllCb:SetPoint("TOPRIGHT", selectedText, "TOPLEFT", -14, 0)
        selectAllCb.checkbox.onChanged = function(_, checked)
            local results = RecruitScanner:GetResults()
            for _, cand in ipairs(results) do
                if checked then self._selected[cand.name] = true else self._selected[cand.name] = nil end
            end
            BRutus:SafeCall(refresh)
        end
        f.selectAllCb = selectAllCb

        ------------------------------------------------------------
        -- Row 3 — column header (Results view only) + separator. X
        -- offsets are HDR (holder's 12px inset + the scroll frame's own
        -- ~4px inset) plus the matching row column offset used below, so
        -- headers stay lined up with the data columns beneath them.
        ------------------------------------------------------------
        local HDR = 16
        local hName = UI:CreateText(f, L["PLAYER"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hName:SetPoint("TOPLEFT", HDR + 30, -92)
        local hLvl = UI:CreateText(f, L["LVL"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hLvl:SetPoint("TOPLEFT", HDR + 240, -92)
        local hClass = UI:CreateText(f, L["CLASS"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hClass:SetPoint("TOPLEFT", HDR + 290, -92)
        local hZone = UI:CreateText(f, L["ZONE"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hZone:SetPoint("TOPLEFT", HDR + 410, -92)
        local sep2 = UI:CreateSeparator(f)
        sep2:SetPoint("TOPLEFT", 12, -110)
        sep2:SetPoint("TOPRIGHT", -12, -110)
        f.colHeader = { hName, hLvl, hClass, hZone, sep2 }

        ------------------------------------------------------------
        -- Row 4 (THE HERO) — scroll list. Anchored TOPLEFT/TOPRIGHT just
        -- below the column header and BOTTOMLEFT/BOTTOMRIGHT just above
        -- the footer, so it fills the middle and grows with the window.
        -- ScrollFrame gotcha: CreateScrollFrame does NOT anchor the
        -- scroll frame itself — SetAllPoints() here, or content is
        -- clipped to 0x0.
        ------------------------------------------------------------
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, -118)
        holder:SetPoint("TOPRIGHT", -12, -118)
        holder:SetPoint("BOTTOMLEFT", 12, 100)
        holder:SetPoint("BOTTOMRIGHT", -12, 100)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRecruitScannerScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder

        ------------------------------------------------------------
        -- Footer — fixed at the container bottom: template label/hint,
        -- full-width template box, Whisper-selected button.
        ------------------------------------------------------------
        local whisperBtn = UI:CreateButton(f, string.format(L["Whisper selected (%d)"], 0), 190, 28)
        whisperBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        whisperBtn:SetScript("OnClick", function()
            local names = {}
            for name in pairs(self._selected) do names[#names + 1] = name end
            if #names == 0 then return end
            local dlg = StaticPopup_Show("GUILDOS_SCOUT_WHISPER_CONFIRM", #names, nil, names)
            if dlg then dlg.data = names end
        end)
        f.whisperBtn = whisperBtn

        local tmplBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        tmplBox:SetHeight(24)
        tmplBox:SetPoint("BOTTOMLEFT", 12, 48)
        tmplBox:SetPoint("BOTTOMRIGHT", -12, 48)
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

        local tmplLbl = UI:CreateText(f, L["Message template"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        tmplLbl:SetPoint("BOTTOMLEFT", tmplBox, "TOPLEFT", 0, 6)
        local dot = UI:CreateText(f, "·", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        dot:SetPoint("LEFT", tmplLbl, "RIGHT", 6, 0)
        local hint = UI:CreateText(f, L["Tokens: [player] [class] [level]"], 9, C.silver.r, C.silver.g, C.silver.b)
        hint:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    end

    refresh = function()
        if not f:IsShown() or not f.isOfficer then return end

        if RecruitScanner._scanBusy then
            f.scanBtn:Disable()
            f.scanBtn.label:SetText(L["Scanning…"])
        else
            f.scanBtn:Enable()
            f.scanBtn.label:SetText(L["Scan"])
        end
        for view, tab in pairs(f.tabs) do tab:SetActive(view == self._view) end

        local results = RecruitScanner:GetResults()
        f.foundText:SetText(string.format(L["%d found"], #results))

        local selCount = 0
        for _ in pairs(self._selected) do selCount = selCount + 1 end
        f.selectedText:SetText(string.format(L["%d selected"], selCount))
        f.whisperBtn.label:SetText(string.format(L["Whisper selected (%d)"], selCount))

        local isResults = (self._view == "results")
        for _, hdr in ipairs(f.colHeader) do hdr:SetShown(isResults) end

        if isResults then
            local allSelected = #results > 0
            for _, cand in ipairs(results) do
                if not self._selected[cand.name] then allSelected = false; break end
            end
            f.selectAllCb.checkbox:SetChecked(allSelected)
            f.selectAllCb.checkbox:Enable()
        else
            f.selectAllCb.checkbox:SetChecked(false)
            f.selectAllCb.checkbox:Disable()
        end

        -- Reset ALL row state before repaint (regions and any child frames).
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local y = 0
        if isResults then
            for _, cand in ipairs(results) do
                local sel = UI:CreateCheckbox(child, "", 16)
                sel:SetPoint("TOPLEFT", 4, -y)
                sel.checkbox:SetChecked(self._selected[cand.name] and true or false)
                sel.checkbox.onChanged = function(_, checked)
                    if checked then self._selected[cand.name] = true
                    else self._selected[cand.name] = nil end
                    BRutus:SafeCall(refresh) -- live-updates "N selected" + Whisper count
                end

                -- Every column below anchors TOPLEFT with the SAME explicit
                -- -y offset against the SAME parent (child). Chaining
                -- "LEFT"/"RIGHT" anchors across sibling frames of different
                -- heights would make WoW resolve conflicting vertical centers
                -- (e.g. a row element vs. the whole scroll child) — explicit
                -- -y on every column sidesteps that entirely. Offsets mirror
                -- the column header row above (HDR + this offset).
                local nameFS = UI:CreateText(child, cand.name or "?", 11, C.text.r, C.text.g, C.text.b)
                nameFS:SetPoint("TOPLEFT", 30, -y)
                nameFS:SetWidth(200)
                nameFS:SetJustifyH("LEFT")

                local lvlFS = UI:CreateText(child, tostring(cand.level or "?"), 11, C.textDim.r, C.textDim.g, C.textDim.b)
                lvlFS:SetPoint("TOPLEFT", 240, -y)
                lvlFS:SetWidth(40)

                local classLabel = LOCALIZED_CLASS_NAMES_MALE[cand.class] or cand.class or "?"
                local cc = RAID_CLASS_COLORS[cand.class]
                local classFS = UI:CreateText(child, classLabel, 11,
                    cc and cc.r or C.textDim.r, cc and cc.g or C.textDim.g, cc and cc.b or C.textDim.b)
                classFS:SetPoint("TOPLEFT", 290, -y)
                classFS:SetWidth(110)
                classFS:SetJustifyH("LEFT")

                local zoneFS = UI:CreateText(child, cand.zone or "", 10, C.silver.r, C.silver.g, C.silver.b)
                zoneFS:SetPoint("TOPLEFT", 410, -y)
                zoneFS:SetWidth(300)
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

    container._scannerRefresh = refresh
    f:SetScript("OnShow", refresh)
    refresh()
    return refresh
end

----------------------------------------------------------------------
-- Popup wrapper: chrome only (backdrop/title/close/drag). Content is
-- built by BuildInto() so the same widgets can be embedded elsewhere
-- (see UI/RosterFrame.lua's Recruitment > Scanner sub-tab).
----------------------------------------------------------------------
function RecruitScanner:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSRecruitScannerFrame", UIParent, "BackdropTemplate")
        -- Wider/taller than the old popup: the new layout's filters bar
        -- (min/max level + class cycle + Scan + right-aligned "N found")
        -- needs the room, and the fixed-height header+footer chrome
        -- (~218px combined) needs a taller body to leave the scroll list
        -- a usable height.
        f:SetSize(760, 520)
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

        -- BuildInto()'s filters bar starts at a fixed TOPLEFT(12,-12) of
        -- whatever container it's given, which is correct for the
        -- title-less RosterFrame sub-tab it was designed for but would
        -- run straight under this popup's title text if handed `f`
        -- directly. Give it its own body frame below the title/close row
        -- instead — same idiom as RosterFrame's bar+sub-panel split.
        local body = CreateFrame("Frame", nil, f)
        body:SetPoint("TOPLEFT", 0, -36)
        body:SetPoint("BOTTOMRIGHT", 0, 0)
        self.frame = f
        self.body = body
    end

    local refresh = self:BuildInto(self.body)
    f:Show()
    BRutus:SafeCall(refresh)
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
