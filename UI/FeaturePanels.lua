----------------------------------------------------------------------
-- Guild OS - Feature Panels UI
-- UI panels for: Raids, Loot, Trials
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

-- A "25-man" label as this game says it ("10+" on WoW: Forever, issues #90, #321).
local function Prog(text)
    return GuildOS.RaidTracker and GuildOS.RaidTracker:ProgLabel(text) or text
end

-- Session filter state: true = 25-man only, false = all raids
local _raidFilter25 = true

----------------------------------------------------------------------
-- Core Sign-up Frame: the Raids tab's button and /gos signup open it, for any player (#377)
----------------------------------------------------------------------
local _coreSignupFrame = nil

local WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- The space between blocks and under a sub-tab bar (UI.GAP, #371), read the way Layout.lua reads
-- UI.SCROLL_GUTTER: a stubbed UI in the tools answers a function for it.
local GAP = type(UI.GAP) == "number" and UI.GAP or 8

-- A numeric cell: drawn through the tableNum role (#363).
local function Num(fs)
    GuildOS:ApplyFont(fs, nil, "tableNum")
    return fs
end

local function RefreshCoreSignupFrame()
    local f = _coreSignupFrame
    if not f or not f:IsShown() then return end
    local CM = GuildOS.CoreManager
    if not CM then return end

    -- Identify the current player
    local playerName  = GuildOS.Compat.PlayerName() or ""
    local _, pClass   = UnitClass("player")
    local playerKey   = GuildOS:GetPlayerKey(playerName, GetRealmName())
    local playerRole  = CM:RoleFor(pClass, f.pickedRole, playerKey)   -- the one picked, else my own (#94, #184)
    local rc          = CM.ROLE_COLORS[playerRole] or { r=1, g=1, b=1 }

    -- The role buttons: the picked one lit in its colour
    for role, b in pairs(f.roleBtns or {}) do
        local col = CM.ROLE_COLORS[role] or { r=1, g=1, b=1 }
        local on  = role == playerRole
        b:SetBackdropColor(col.r * (on and 0.30 or 0.08), col.g * (on and 0.30 or 0.08), col.b * (on and 0.30 or 0.08), 0.9)
        b:SetBackdropBorderColor(col.r, col.g, col.b, on and 0.9 or 0.3)
        b.lbl:SetTextColor(col.r, col.g, col.b, on and 1 or 0.55)
    end

    -- Update role label
    f.playerRoleLbl:SetText(string.format(
        "%s |cff%02X%02X%02X%s|r  |cff888888(%s)|r",
        L["Your role:"],
        rc.r * 255, rc.g * 255, rc.b * 255,
        CM.ROLE_LABELS[playerRole] or playerRole,
        pClass:sub(1,1) .. pClass:sub(2):lower()
    ))

    local content = f.content
    local W       = content:GetWidth()

    -- Clear previous content (fontstrings/textures on content, child frames = buttons/inputs)
    for _, c in ipairs({ content:GetChildren() }) do c:Hide() end
    for _, r in pairs({ content:GetRegions() }) do r:Hide() end

    -- Sort core names alphabetically
    local coreNames = {}
    for name in pairs(CM:GetAll()) do coreNames[#coreNames + 1] = name end
    table.sort(coreNames)

    if #coreNames == 0 then
        local noL = content:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(noL, 11)
        noL:SetPoint("TOPLEFT", 8, -12)
        noL:SetTextColor(0.45, 0.45, 0.45)
        noL:SetText(L["No cores configured yet."])
        content:SetHeight(40)
        return
    end

    -- One card a core (issue #346, Inscricao.dc.html): its name and size and where the player
    -- stands with it, always in sight; when it raids and who leads it; its loot rule in one line;
    -- the role coverage; and the one action that applies, Cancel request as visible as Ask.
    -- Each card is parchment on the popup's dark (the mockup's raides-core): its text takes the paper's ink.
    local y = 0
    local CARD_PAD = 12
    local function ink(col)
        if col == C.text then return C.paperInk end
        if col == C.textDim or col == C.silver or col == C.textSoft or col == C.labelDim or col == C.label then return C.paperSoft end
        return { r = col.r * 0.6, g = col.g * 0.6, b = col.b * 0.6 }
    end
    local function line(text, size, col, x, yy, w)
        col = ink(col)
        local fs = UI:CreateText(content, text, size, col.r, col.g, col.b)
        fs:SetPoint("TOPLEFT", x, yy)
        if w then fs:SetWidth(w) end
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    for _, coreName in ipairs(coreNames) do
        local comp     = CM:GetComposition(coreName)
        local roles    = comp.roleCounts or {}
        local st       = CM:SignupState(coreName, playerKey) or { missing = {} }
        local raidSize = CM:GetRaidSize(coreName)
        local top      = y

        -- The card's surface: the parchment, under the texts drawn on the list.
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetPoint("TOPLEFT", 0, y)
        card:SetWidth(W)
        if GuildOS.Style then GuildOS.Style:Paint(card, "paper") end
        card:SetFrameLevel(content:GetFrameLevel())

        -- Name, size, and the state on the right, as the mockup's badge.
        local nameFS = line(coreName, nil, C.text, CARD_PAD, y - CARD_PAD)
        GuildOS:ApplyFont(nameFS, nil, "sectionTitle")
        nameFS:SetTextColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
        local sizeBadge = UI:CreateBadge(content, tostring(raidSize))
        sizeBadge:SetPoint("LEFT", nameFS, "RIGHT", 8, 0)
        local state, stateCol
        if st.member then
            state, stateCol = st.bench and L["you are in reserve"] or L["you are a starter"], C.ok
        elseif st.pending then
            state, stateCol = type(st.pending) == "number" and string.format(L["request sent %s"], GuildOS:TimeAgo(st.pending))
                or L["request sent"], C.textSoft
        elseif st.full then
            state, stateCol = L["full"], C.labelDim
        else
            local short = {}
            for _, role in ipairs({ "tank", "healer", "mdps", "rdps" }) do
                local n = st.missing[role] or 0
                if n > 0 then short[#short + 1] = string.format(L["%d %s"], n, CM.ROLE_LABELS[role] or role) end
            end
            state, stateCol = #short > 0 and string.format(L["missing %s"], table.concat(short, ", ")) or "", C.warn
        end
        if state ~= "" then
            local stateBadge = UI:CreateBadge(content, state, stateCol)
            stateBadge:SetPoint("TOPRIGHT", -CARD_PAD, y - CARD_PAD - 1)
        end
        f.states = f.states or {}
        f.states[coreName] = state
        y = y - 26

        -- When it raids and who leads it, as far as the site said.
        line((st.schedule or L["no schedule set"]) .. "  \194\183  "
            .. (st.leader and string.format(L["leader %s"], st.leader) or L["no leader set"]), 10, C.textDim, CARD_PAD, y)
        y = y - 16
        -- The core's loot rule, in one line, and the player's presence on its nights.
        local LR = GuildOS.LootRule
        if LR then
            local site = CM.LootRuleFromSite and CM:LootRuleFromSite(coreName)
            line(string.format(L["Loot: %s"], LR:ModelName(site or LR:For(coreName))), 10, C.text, CARD_PAD, y, W - 2 * CARD_PAD - 130)
        end
        if st.presence then
            local presFS = UI:CreateText(content, string.format(L["your presence %d%%"], st.presence), 10, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
            presFS:SetPoint("TOPRIGHT", -CARD_PAD, y)
        end
        y = y - 18

        -- The role coverage, the player's own role larger and underlined.
        local T = CM:RaidTargets(raidSize)
        local ROLE_DEFS = {
            { key="tank",   short="T", target=T.tank },
            { key="healer", short="H", target=T.healer },
            { key="mdps",   short="M", target=T.mdps },
            { key="rdps",   short="R", target=T.rdps },
        }
        local rx = CARD_PAD
        for _, rd in ipairs(ROLE_DEFS) do
            local cnt  = roles[rd.key] or 0
            local rcol = ink(CM.ROLE_COLORS[rd.key] or C.text)
            local isMine = (rd.key == playerRole)
            local rlbl = content:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(rlbl, isMine and 12 or 10)
            rlbl:SetPoint("TOPLEFT", rx, y - 2)
            rlbl:SetTextColor(rcol.r, rcol.g, rcol.b)
            rlbl:SetText(string.format("%s:%d/%d", rd.short, cnt, rd.target))
            if isMine then
                local ul = content:CreateTexture(nil, "ARTWORK")
                ul:SetTexture(WHITE8); GuildOS.UI:Hairline(ul, "Height")
                ul:SetPoint("TOPLEFT", rx, y - 16)
                ul:SetWidth(44)
                ul:SetVertexColor(rcol.r, rcol.g, rcol.b, 0.7)
            end
            rx = rx + 56
        end

        -- The action: a note and Ask for a place, or Cancel request; nothing to do once on the core.
        local capCore = coreName
        if not st.member then
            -- The shared field, its hint the component's placeholder (#371).
            local noteInp = UI:CreateInput(content, math.max(90, math.min(160, W - rx - 150)), 22,
                { max = 80, placeholder = L["Note (optional)"] })
            noteInp:SetPoint("TOPRIGHT", -(CARD_PAD + 124), y + 2)
            noteInp:HookScript("OnTextChanged", function(self)
                f.notes[capCore] = self:GetText()   -- kept across a redraw, such as a role click (#94)
            end)
            noteInp:SetText(f.notes[coreName] or "")
            if st.pending then noteInp:Hide() end
            local actBtn = UI:CreateButton(content, st.pending and L["Cancel request"] or L["Ask for a place"], 120, 22)
            actBtn:SetPoint("TOPRIGHT", -CARD_PAD, y + 2)
            if st.pending then
                UI:SetButtonVariant(actBtn, "danger")
                actBtn:SetScript("OnClick", function()
                    CM:DeclineSignup(playerKey, capCore)
                    if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
                    RefreshCoreSignupFrame()
                end)
            else
                UI:SetButtonVariant(actBtn, "primary")
                actBtn:SetScript("OnClick", function()
                    local note = strtrim(noteInp:GetText() or "")
                    CM:BroadcastSignup(capCore, note, playerRole)
                    f.notes[capCore] = nil
                    noteInp:SetText("")
                    if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
                    RefreshCoreSignupFrame()
                end)
            end
        end
        -- The rule, read whole in the Loot window.
        local ruleBtn = UI:CreateButton(content, L["See the rule"], 100, 20)
        ruleBtn:SetPoint("TOPRIGHT", -CARD_PAD, y - 26)
        UI:SetButtonVariant(ruleBtn, "ghost")
        ruleBtn:SetScript("OnClick", function() UI:OpenWindow("loot", "rule", capCore) end)
        y = y - 52
        card:SetHeight(top - y)
        y = y - 8
    end

    -- Where the requests of a Discord core go, under the cards.
    if CM:IsLinked() then
        local foot = UI:CreateText(content, L["The requests for a Discord core go to Discord: its leader answers there and the answer comes back here."],
            10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        foot:SetPoint("TOPLEFT", 2, y)
        foot:SetWidth(W - 4)
        foot:SetJustifyH("LEFT")
        y = y - 30
    end
    content:SetHeight(math.abs(y) + 8)
end

local function BuildCoreSignupFrame()
    local FRAME_W, FRAME_H = 460, 480

    local f = CreateFrame("Frame", "GuildOSCoreSignupFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    UI:StylePopup(f)
    f:Hide()
    table.insert(UISpecialFrames, "GuildOSCoreSignupFrame")

    -- Title bar
    local tTitle = UI:CreateTitle(f, L["Core Sign-ups"], 14)
    tTitle:SetPoint("TOPLEFT", 12, -9)
    local tLine = UI:CreateSeparator(f)
    tLine:SetPoint("TOPLEFT", 2, -30)
    tLine:SetPoint("TOPRIGHT", -2, -30)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -6, -5)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Player role strip: "I play as", and the roles the class can play.

    f.playerRoleLbl = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.playerRoleLbl, 10)
    f.playerRoleLbl:SetPoint("TOPLEFT", 10, -37)
    f.playerRoleLbl:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    -- The role to sign up as: one button per role the class can play, laid out from the right,
    -- and none when there is only the one (issue #94).
    f.roleBtns, f.notes = {}, {}
    local CM = GuildOS.CoreManager
    local _, cls = UnitClass("player")
    local roles = CM and CM:RolesFor(cls) or {}
    if #roles > 1 then
        local x = -8
        for i = #roles, 1, -1 do
            local role = roles[i]
            local b = CreateFrame("Button", nil, f, "BackdropTemplate")
            b:SetBackdrop({ bgFile=WHITE8, edgeFile=WHITE8, edgeSize = GuildOS.UI:Edge(b) })
            b.lbl = b:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(b.lbl, 10)
            b.lbl:SetPoint("CENTER")
            b.lbl:SetText(CM.ROLE_LABELS[role] or role)
            -- As wide as its name ("Curandeiro" is wider than "Healer"), never less than 54.
            local bw = math.max(54, math.ceil(b.lbl:GetStringWidth() or 0) + 14)
            b:SetSize(bw, 18)
            b:SetPoint("TOPRIGHT", x, -35)
            b:SetScript("OnClick", function()
                f.pickedRole = role
                RefreshCoreSignupFrame()
            end)
            f.roleBtns[role] = b
            x = x - bw - 4
        end
    end

    -- Scroll area for core list
    local scroll = CreateFrame("ScrollFrame", "GuildOSCoreSignupScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -60)
    scroll:SetPoint("BOTTOMRIGHT", -14, 8)
    UI:SkinScrollBar(scroll, "GuildOSCoreSignupScroll")

    -- The cards take the scroll area's width, whatever the frame's.
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(FRAME_W - 30)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    UI:BindScrollChildWidth(scroll, content, 4)
    -- The cards on it are parchment: its fields and buttons are the paper's (every text sets its own ink).
    content.__paper = true

    f.content = content
    return f
end

function GuildOS:ShowCoreSignupFrame()
    if not _coreSignupFrame then
        _coreSignupFrame = BuildCoreSignupFrame()
    end
    if _coreSignupFrame:IsShown() then
        _coreSignupFrame:Hide()
        return
    end
    -- Anchor next to the main window; fall back to screen center if unavailable
    _coreSignupFrame:ClearAllPoints()
    local main = GuildOS.RosterFrame
    if main and main:IsShown() then
        _coreSignupFrame:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, 0)
    else
        _coreSignupFrame:SetPoint("CENTER")
    end
    _coreSignupFrame:Show()
    RefreshCoreSignupFrame()
end

----------------------------------------------------------------------
-- RAID ATTENDANCE PANEL
----------------------------------------------------------------------
-- The Raids room's Sessions (the mockup's raides-presenca): a dark card with the lockouts, each a row with
-- its raid's glyph that opens its nights and a night its players; under it a parchment card with each
-- member's attendance. The attendance table's columns are shared by its header and its rows (#371: the
-- header stays put while the rows scroll).
local ATT_COLS = { player = 6, group = 150, pct = 250, raids = 305, avg = 365, last = 450, form = 540 }
local ATT_CARD_H = 250   -- px the attendance card keeps under the sessions while there are sessions
local SESS_PAD   = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
local CARD_TOP   = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
local SESS_TOP   = CARD_TOP + 28   -- the card's title and its filter chips over the list

-- The paper's own shades of a state (the mockup's .b-ok, .b-warn, .b-bad) and a class's colour as the paper
-- prints it (.card .c-*): the game's colours, darkened where they would not read on the parchment.
-- The paper's statuses (UI/Helpers.lua's one mapping, #449); a test that loads no Helpers gets the same hex.
local STATUS = type(GuildOS.UI.STATUS_INK) == "table" and GuildOS.UI.STATUS_INK or {}
local function hexc(h) return { r = tonumber(h:sub(1, 2), 16) / 255, g = tonumber(h:sub(3, 4), 16) / 255, b = tonumber(h:sub(5, 6), 16) / 255 } end
local PAPER_OK, PAPER_WARN, PAPER_BAD = STATUS.ok or hexc("2f6e33"), STATUS.warn or hexc("8f4a0c"), STATUS.bad or hexc("8f1b0b")
local function paperClass(class)
    return GuildOS.UI:InkFor("paper", "class", class)   -- the paper's class inks (UI/Helpers.lua, #449)
end

-- A 1px rule across the top of a row: the row lines of the mockup's tables, on the wood or the paper.
local function rowRule(row, col)
    local t = row:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE8)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT")
    t:SetPoint("TOPRIGHT")
    t:SetVertexColor(col.r, col.g, col.b, 1)
    return t
end
-- The soft gold wash a row takes under the cursor (the mockup's .t tr.click:hover).
local function rowHover(row)
    local t = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetTexture(WHITE8)
    t:SetAllPoints()
    t:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 0.07)
    t:Hide()
    row:HookScript("OnEnter", function() t:Show() end)
    row:HookScript("OnLeave", function() t:Hide() end)
    return t
end

function GuildOS:CreateRaidsPanel(parent, _mainFrame)
    -- Flush with the sub-tab bar's left edge, the first line UI.GAP under it (#371).
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", 0, -GAP)
    scrollParent:SetPoint("BOTTOMRIGHT", -GAP, GAP)

    ----------------------------------------------------------------
    -- Sessions: a dark card, its title and the tracker's state on one line, the filter as chips
    ----------------------------------------------------------------
    local sessCard = UI:CreateCard(scrollParent, L["Raid Attendance"], { dark = true })
    sessCard:SetPoint("TOPLEFT", 0, 0)
    sessCard:SetPoint("TOPRIGHT", 0, 0)
    local title = sessCard.title
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", SESS_PAD, -12)

    -- The count and the tracker's state, after the title they qualify.
    local statusText = UI:CreateText(sessCard, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    statusText:SetPoint("LEFT", title, "RIGHT", 8, 0)
    statusText:SetJustifyH("LEFT")
    if statusText.SetWordWrap then statusText:SetWordWrap(false) end

    -- The filter: the shown one marked by UI:SetSelected, as every choice of a set (#371), as pills.
    local filterAllBtn = UI:SetButtonVariant(UI:CreateButton(sessCard, L["All"], 44, 22), "chip")
    local filter25Btn  = UI:SetButtonVariant(UI:CreateButton(sessCard, Prog(L["25-man"]), 52, 22), "chip")
    filterAllBtn:SetPoint("TOPLEFT", SESS_PAD, -CARD_TOP + 4)
    filter25Btn:SetPoint("LEFT", filterAllBtn, "RIGHT", 6, 0)

    local sessionScroll, sessionContent = UI:CreateScrollFrame(sessCard, "GuildOSRaidSessionScroll")
    sessionScroll:SetPoint("TOPLEFT", SESS_PAD, -SESS_TOP)
    sessionScroll:SetPoint("BOTTOMRIGHT", -SESS_PAD + 6, 10)
    sessionContent:SetSize(1, 1)
    UI:BindScrollChildWidth(sessionScroll, sessionContent)

    ----------------------------------------------------------------
    -- Attendance: a parchment card, a table header that stays put, the rows that scroll
    ----------------------------------------------------------------
    local attCard = UI:CreateCard(scrollParent, Prog(L["Member Attendance — 25-man only"]))
    attCard:SetPoint("BOTTOMLEFT", 0, 0)
    attCard:SetPoint("BOTTOMRIGHT", 0, 0)
    local attHdr = UI:CreateTableHeader(attCard)
    attHdr:SetPoint("TOPLEFT", SESS_PAD, -CARD_TOP + 2)
    attHdr:SetPoint("TOPRIGHT", -SESS_PAD, -CARD_TOP + 2)
    local function AHdr(txt, x)
        UI:CreateHeaderText(attHdr, txt):SetPoint("LEFT", x, 0)
    end
    AHdr(L["Player"], ATT_COLS.player); AHdr(L["Group"], ATT_COLS.group); AHdr(L["Att%"], ATT_COLS.pct)
    AHdr(L["Raids"], ATT_COLS.raids); AHdr(L["Avg score"], ATT_COLS.avg); AHdr(L["Last raid"], ATT_COLS.last)

    local attScroll, attContent = UI:CreateScrollFrame(attCard, "GuildOSAttendanceScroll")
    attScroll:SetPoint("TOPLEFT", attHdr, "BOTTOMLEFT", 0, 0)
    attScroll:SetPoint("BOTTOMRIGHT", -SESS_PAD + 6, 10)
    attContent:SetSize(1, 1)
    UI:BindScrollChildWidth(attScroll, attContent)

    -- With sessions, the sessions take the room the attendance leaves them; with none, the sessions' card
    -- folds to its title and chips and the attendance takes the rest (#371: it was a 400px black block).
    sessionContent.placeBlocks = function(hasSessions)
        sessCard:ClearAllPoints()
        attCard:ClearAllPoints()
        sessCard:SetPoint("TOPLEFT", 0, 0)
        sessCard:SetPoint("TOPRIGHT", 0, 0)
        attCard:SetPoint("BOTTOMLEFT", 0, 0)
        attCard:SetPoint("BOTTOMRIGHT", 0, 0)
        if hasSessions then
            attCard:SetHeight(ATT_CARD_H)
            sessCard:SetPoint("BOTTOM", attCard, "TOP", 0, GAP + 4)
        else
            sessCard:SetHeight(SESS_TOP + 6)
            attCard:SetPoint("TOP", sessCard, "BOTTOM", 0, -GAP - 4)
        end
        sessionScroll:SetShown(hasSessions)
    end
    sessionContent.placeBlocks(true)

    ----------------------------------------------------------------
    -- Filter button wiring
    ----------------------------------------------------------------
    local function SetFilterActive(only25)
        _raidFilter25 = only25
        UI:SetSelected(filterAllBtn, not only25)
        UI:SetSelected(filter25Btn, only25)
        GuildOS:RefreshRaidsPanel(sessionContent, attContent, statusText)
    end

    filterAllBtn:SetScript("OnClick", function() SetFilterActive(false) end)
    filter25Btn:SetScript("OnClick",  function() SetFilterActive(true)  end)

    parent:SetScript("OnShow", function()
        -- Store refs so remote deletions can refresh the panel
        GuildOS.RaidsPanelOpen = {
            sessionContent = sessionContent,
            attContent     = attContent,
            statusText     = statusText,
        }
        SetFilterActive(_raidFilter25)
    end)
    parent:SetScript("OnHide", function()
        GuildOS.RaidsPanelOpen = nil
    end)
end

-- Session expand state (persists while panel is shown)
local _sessionExpanded = {}
local _groupExpanded   = {}

local function hexOf(c) return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

function GuildOS:RefreshRaidsPanel(sessionContent, attContent, statusText)
    if not GuildOS.RaidTracker then return end

    -- Clear existing children
    for _, child in pairs({ sessionContent:GetChildren() }) do child:Hide() end
    for _, child in pairs({ attContent:GetChildren()     }) do child:Hide() end

    local totalAll  = GuildOS.RaidTracker:GetTotalSessions()
    local total25   = GuildOS.RaidTracker:GetTotal25ManSessions()
    local curGroup  = GuildOS.RaidTracker:GetCurrentGroup()
    local groupStr  = curGroup ~= "" and (curGroup .. "  ·  ") or ""
    local trackStr  = GuildOS.RaidTracker.trackingActive
                      and hexOf(C.ok) .. L["Tracking"] .. "|r" or hexOf(C.labelDim) .. L["Idle"] .. "|r"
    statusText:SetText("·  " .. groupStr .. totalAll .. L[" lockouts ("] .. total25 .. Prog(L[" 25-man)  |  "]) .. trackStr)

    ----------------------------------------------------------------
    -- Sessions grouped by instance + the region's reset week (guildos-web#199)
    ----------------------------------------------------------------
    local sessions = GuildOS.RaidTracker:GetRecentSessions(200, _raidFilter25, true)

    -- Build groups keyed by "instanceID_weekNum"
    local groups     = {}
    local groupOrder = {}

    for _, s in ipairs(sessions) do
        local sd        = s.data
        local startTime = sd.startTime or s.id
        local weekNum   = GuildOS.RaidTracker:GetWeekNum(startTime)
        local sgTag     = sd.groupTag or ""
        -- A retail raid's difficulties are separate lockouts, so separate groups (issue #177).
        local diff      = GuildOS.RaidTracker:DifficultyLabel(sd)
        local groupKey  = (sd.instanceID or 0) .. "_" .. weekNum .. "|" .. sgTag .. "|" .. (diff or "")

        if not groups[groupKey] then
            local wStart = GuildOS.RaidTracker:WeekStart(weekNum)
            groups[groupKey] = {
                key        = groupKey,
                instanceID = sd.instanceID,
                size       = 0,
                name       = sd.name or L["Unknown"],
                difficulty = diff,
                difficultyID = tonumber(sd.difficulty),   -- what counts on retail (issue #182)
                groupTag   = sgTag,
                weekNum    = weekNum,
                weekStart  = wStart,
                sessions   = {},
                allPlayers = {},
                kills      = 0,
                wipes      = 0,
            }
            table.insert(groupOrder, groupKey)
        end

        local g = groups[groupKey]
        g.size = math.max(g.size, tonumber(sd.size) or 0)
        table.insert(g.sessions, s)

        for k in pairs(sd.players or {}) do g.allPlayers[k] = true end
        for _, enc in ipairs(sd.encounters or {}) do
            if enc.success then g.kills = g.kills + 1
            else                g.wipes = g.wipes + 1 end
        end
    end

    -- Sort groups: most recent week first; within same week, raid name A-Z
    table.sort(groupOrder, function(a, b)
        local ga, gb = groups[a], groups[b]
        if ga.weekNum ~= gb.weekNum then return ga.weekNum > gb.weekNum end
        return ga.name < gb.name
    end)

    local soft, dim = C.textSoft, C.labelDim
    local function kills(k, w)
        local s = k .. L[" kills"]
        if w > 0 then s = s .. " / " .. w .. L[" wipes"] end
        return s
    end

    local yOff = 0

    for gIdx, groupKey in ipairs(groupOrder) do
        local g          = groups[groupKey]
        local isGroupExp = _groupExpanded[groupKey]
        local is25       = GuildOS.RaidTracker:Is25Man(g.instanceID, g.size, g.difficultyID)
        local gRowH      = 48

        -- Count unique players
        local uPlayers = 0
        for _ in pairs(g.allPlayers) do uPlayers = uPlayers + 1 end

        -- The lockout's row, hung by both top corners: a width read while the tab is hidden is 0 (#371).
        -- Its raid's glyph, the name and the week, the nights, players and kills under them, and the button
        -- that opens it.
        local gRow = CreateFrame("Button", nil, sessionContent)
        gRow:SetHeight(gRowH)
        gRow:SetPoint("TOPLEFT", 0, -yOff)
        gRow:SetPoint("TOPRIGHT", 0, -yOff)
        if gIdx > 1 then rowRule(gRow, C.line) end
        rowHover(gRow)

        local glyph = UI:CreateGlyph(gRow, 26)
        glyph:SetPoint("LEFT", 0, 0)
        glyph:Set(UI.Initial and UI.Initial(g.name) or g.name:sub(1, 1), is25 and C.count or C.paperSoft)

        -- Raid name (the ink for a 25-man, the soft ink for a 10-man); the core's tag in brackets.
        local nameClr = is25 and C.text or C.textSoft
        local nameLabel = g.difficulty and (g.name .. " (" .. g.difficulty .. ")") or g.name
        if g.groupTag and g.groupTag ~= "" then
            nameLabel = "[" .. g.groupTag .. "] " .. nameLabel
        end
        local weekLabel = GuildOS:DateText(g.weekStart) .. " – " .. GuildOS:DateText(g.weekStart + 6 * 86400)
        local nameFS = UI:CreateText(gRow, nameLabel, 13, nameClr.r, nameClr.g, nameClr.b)
        GuildOS:ApplyFont(nameFS, 13, "button")
        nameFS:SetPoint("TOPLEFT", 36, -7)
        local weekFS = Num(UI:CreateText(gRow, "·  " .. weekLabel, 12, soft.r, soft.g, soft.b))
        weekFS:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)

        local sub = #g.sessions .. L[" sess."] .. "  ·  " .. uPlayers .. L[" players"] .. "  ·  "
            .. (g.kills > 0 and hexOf(C.ok) or "") .. kills(g.kills, g.wipes) .. (g.kills > 0 and "|r" or "")
        UI:CreateText(gRow, sub, 11, soft.r, soft.g, soft.b):SetPoint("TOPLEFT", 36, -26)

        local openBtn = UI:CreateButton(gRow, isGroupExp and L["Close"] or L["Open"], 56, 24)
        openBtn:SetPoint("RIGHT", 0, 0)

        local capturedGKey = groupKey
        local function toggleGroup()
            _groupExpanded[capturedGKey] = not _groupExpanded[capturedGKey]
            GuildOS:RefreshRaidsPanel(sessionContent, attContent, statusText)
        end
        gRow:SetScript("OnClick", toggleGroup)
        openBtn:SetScript("OnClick", toggleGroup)

        yOff = yOff + gRowH

        -- If expanded, show individual sessions inside this group (indented)
        if isGroupExp then
            for _, s in ipairs(g.sessions) do
                local sd    = s.data
                local isExp = _sessionExpanded[s.id]
                local rowH  = 26

                local row = CreateFrame("Button", nil, sessionContent)
                row:SetHeight(rowH)
                row:SetPoint("TOPLEFT", 36, -yOff)
                row:SetPoint("TOPRIGHT", 0, -yOff)
                rowRule(row, C.line)
                rowHover(row)

                -- Open or shut: ASCII marks, the addon's fonts have no ▶ or ▼ glyph.
                UI:CreateText(row, isExp and "-" or "+", 11, C.gold2.r, C.gold2.g, C.gold2.b)
                    :SetPoint("LEFT", 2, 0)

                -- Date + time
                local dateStr = GuildOS:LocalDate("%a ", sd.startTime or 0) .. GuildOS:DateText(sd.startTime or 0, "  %H:%M")
                Num(UI:CreateText(row, dateStr, 12, C.text.r, C.text.g, C.text.b)):SetPoint("LEFT", 16, 0)

                -- Duration
                local dur = sd.duration or (sd.endTime and sd.startTime and (sd.endTime - sd.startTime))
                if dur then
                    local durStr = format("%dh%02dm", floor(dur / 3600), floor((dur % 3600) / 60))
                    Num(UI:CreateText(row, durStr, 11, soft.r, soft.g, soft.b)):SetPoint("LEFT", 165, 0)
                end

                -- Player count
                local pCount = GuildOS.RaidTracker:CountTable(sd.players or {})
                UI:CreateText(row, pCount .. L[" players"], 11, soft.r, soft.g, soft.b):SetPoint("LEFT", 225, 0)

                -- Boss kills / wipes
                local sk, sw = 0, 0
                for _, enc in ipairs(sd.encounters or {}) do
                    if enc.success then sk = sk + 1 else sw = sw + 1 end
                end
                local sEncClr = sk > 0 and C.ok or soft
                UI:CreateText(row, kills(sk, sw), 11, sEncClr.r, sEncClr.g, sEncClr.b):SetPoint("LEFT", 310, 0)

                -- Delete button (officer only)
                if GuildOS:IsOfficer() then
                    local delBtn = UI:SetButtonVariant(UI:CreateButton(row, L["X"], 22, 20), "danger")
                    delBtn:SetPoint("RIGHT", 0, 0)
                    local capturedSID = s.id
                    delBtn:SetScript("OnClick", function()
                        GuildOS.RaidTracker:DeleteSession(capturedSID)
                        _sessionExpanded[capturedSID] = nil
                        GuildOS:RefreshRaidsPanel(sessionContent, attContent, statusText)
                    end)
                end

                local capturedID = s.id
                row:SetScript("OnClick", function()
                    _sessionExpanded[capturedID] = not _sessionExpanded[capturedID]
                    GuildOS:RefreshRaidsPanel(sessionContent, attContent, statusText)
                end)

                yOff = yOff + rowH

                -- Expanded: the night's players, a table of their own
                if isExp then
                    -- The night's presence and its score, as the attendance reads them (audit R5, R17).
                    local roll      = GuildOS.RaidTracker:RollUp(sd)
                    local pen       = GuildOS.RaidTracker:GetPenalties(sd.groupTag)

                    local playerList = {}
                    for key in pairs(sd.players or {}) do
                        local shortName  = key:match("^([^-]+)") or key
                        local memberData = GuildOS.db.members and GuildOS.db.members[key]
                        local class      = memberData and memberData.class or nil

                        local score, wasLate, leftEarly, noConsumes, consumeHits, consumeChecks =
                            GuildOS.RaidTracker:NightScore(key, roll, pen)

                        table.insert(playerList, {
                            key = key, name = shortName, class = class,
                            score = score, wasLate = wasLate, leftEarly = leftEarly,
                            noConsumes = noConsumes, consumeHits = consumeHits, consumeChecks = consumeChecks,
                        })
                    end

                    table.sort(playerList, function(a, b)
                        if a.score ~= b.score then return a.score > b.score end
                        local ca = a.class or "ZZZZ"; local cb2 = b.class or "ZZZZ"
                        if ca ~= cb2 then return ca < cb2 end
                        return a.name < b.name
                    end)

                    -- The shared table header: Cinzel in gold, a 1px rule under it (#371).
                    local hdrFrame = UI:CreateTableHeader(sessionContent)
                    hdrFrame:SetPoint("TOPLEFT", 52, -yOff - 4)
                    hdrFrame:SetPoint("TOPRIGHT", 0, -yOff - 4)
                    local function Hdr(txt, x)
                        UI:CreateHeaderText(hdrFrame, txt):SetPoint("LEFT", x, 0)
                    end
                    Hdr(L["Player"], 6); Hdr(L["Score"], 140); Hdr(L["Late"], 200); Hdr(L["Left early"], 270)
                    if GuildOS.ConsumableChecker then Hdr(L["No cons."], 360) end   -- TBC only (issue #184)
                    yOff = yOff + 4 + hdrFrame:GetHeight()

                    for pIdx, p in ipairs(playerList) do
                        local pRow = CreateFrame("Frame", nil, sessionContent)
                        pRow:SetHeight(22)
                        pRow:SetPoint("TOPLEFT", 52, -yOff)
                        pRow:SetPoint("TOPRIGHT", 0, -yOff)
                        if pIdx > 1 then rowRule(pRow, C.line) end

                        local cr, cg, cb = GuildOS:GetClassColor(p.class)
                        local nameT = UI:CreateText(pRow, p.name, 12, cr, cg, cb)
                        GuildOS:ApplyFont(nameT, 12, "button")
                        nameT:SetPoint("LEFT", 6, 0); nameT:SetWidth(128); nameT:SetJustifyH("LEFT")

                        local sc = (p.score < 50 and C.danger) or (p.score < 75 and C.warn) or C.text
                        Num(UI:CreateText(pRow, p.score .. "%", 12, sc.r, sc.g, sc.b)):SetPoint("LEFT", 140, 0)

                        -- A flag: the fault in red, or a dash where there is none.
                        local function Flag(x, val, text)
                            local col = val and C.danger or dim
                            UI:CreateText(pRow, val and text or "—", 11, col.r, col.g, col.b):SetPoint("LEFT", x, 0)
                        end
                        Flag(200, p.wasLate,   L["Late"])
                        Flag(270, p.leftEarly, L["Left early"])

                        if GuildOS.ConsumableChecker then
                            local consStr = p.consumeChecks > 0 and format("%d/%d", p.consumeHits, p.consumeChecks) or "-"
                            local cr2 = p.noConsumes and C.danger or C.text
                            Num(UI:CreateText(pRow, consStr, 11, cr2.r, cr2.g, cr2.b)):SetPoint("LEFT", 360, 0)
                        end

                        yOff = yOff + 22
                    end
                    yOff = yOff + 8
                end
            end -- for sessions in group
        end -- if isGroupExp
    end -- for groups
    sessionContent:SetHeight(math.max(1, yOff))
    if sessionContent.placeBlocks then sessionContent.placeBlocks(#groupOrder > 0) end

    ----------------------------------------------------------------
    -- Attendance list — always 25-man stats regardless of filter
    -- Nested structure: attendance[groupTag][playerKey]
    ----------------------------------------------------------------
    local attData = GuildOS.db.raidTracker and GuildOS.db.raidTracker.attendance or {}
    local attList = {}
    for groupTag, groupAtt in pairs(attData) do
        if type(groupAtt) == "table" then
            for key, att in pairs(groupAtt) do
                if (att.raids25 or 0) > 0 then
                    table.insert(attList, { key = key, data = att, groupTag = groupTag })
                end
            end
        end
    end
    table.sort(attList, function(a, b)
        -- Sort by group first, then by attendance % descending
        if a.groupTag ~= b.groupTag then return a.groupTag < b.groupTag end
        local pa = GuildOS.RaidTracker:GetAttendance25ManPercent(a.key, a.groupTag)
        local pb = GuildOS.RaidTracker:GetAttendance25ManPercent(b.key, b.groupTag)
        if pa == pb then
            return (a.data.raids25 or 0) > (b.data.raids25 or 0)
        end
        return pa > pb
    end)

    -- The rows on the parchment: the paper's ink, its lines, its shades of a state.
    local ink, psoft = C.paperInk, C.paperSoft
    -- The column labels are the card's own header, outside the scroll (CreateRaidsPanel, #371).
    yOff = 0
    local lastGroupTag = nil
    local groupsSeen = 0
    for _, entry in pairs(attList) do
        if entry.groupTag ~= lastGroupTag then groupsSeen = groupsSeen + 1; lastGroupTag = entry.groupTag end
    end
    lastGroupTag = nil
    for _, entry in ipairs(attList) do
        -- A group's own heading when there are more than one: the tag and its raids, in the title's red.
        if groupsSeen > 1 and entry.groupTag ~= lastGroupTag then
            local ghRow = CreateFrame("Frame", nil, attContent)
            ghRow:SetHeight(22)
            ghRow:SetPoint("TOPLEFT", 0, -yOff)
            ghRow:SetPoint("TOPRIGHT", 0, -yOff)
            local groupLabel = entry.groupTag ~= "" and entry.groupTag or L["(no group)"]
            local total25g = GuildOS.RaidTracker:GetTotal25ManSessions(entry.groupTag)
            local ghText = UI:CreateText(ghRow, groupLabel .. "  ·  " .. total25g .. Prog(L[" 25-man raids"]),
                11, C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
            GuildOS:ApplyFont(ghText, 11, "sectionTitle")
            ghText:SetPoint("LEFT", ATT_COLS.player, -2)
            yOff = yOff + 22
        end
        lastGroupTag = entry.groupTag

        local row = CreateFrame("Frame", nil, attContent)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("TOPRIGHT", 0, -yOff)
        rowRule(row, C.paperLine)

        local shortName = entry.key:match("^([^-]+)") or entry.key
        local memberData = GuildOS.db.members and GuildOS.db.members[entry.key]
        local class = memberData and memberData.class
        local cr, cg, cb = paperClass(class)
        local nameText = UI:CreateText(row, shortName, 12, cr, cg, cb)
        GuildOS:ApplyFont(nameText, 12, "button")
        nameText:SetPoint("LEFT", ATT_COLS.player, 0)

        -- Group tag column
        local gtLabel = entry.groupTag ~= "" and entry.groupTag or "-"
        UI:CreateText(row, gtLabel, 11, psoft.r, psoft.g, psoft.b):SetPoint("LEFT", ATT_COLS.group, 0)

        local total25g = GuildOS.RaidTracker:GetTotal25ManSessions(entry.groupTag)
        local pct      = GuildOS.RaidTracker:GetAttendance25ManPercent(entry.key, entry.groupTag)
        local pctClr   = pct >= 75 and PAPER_OK or (pct >= 50 and PAPER_WARN or PAPER_BAD)
        local pctText  = Num(UI:CreateText(row, pct .. "%", 12, pctClr.r, pctClr.g, pctClr.b))
        pctText:SetPoint("LEFT", ATT_COLS.pct, 0)

        local raids25  = entry.data.raids25 or 0
        local fracText = Num(UI:CreateText(row, raids25 .. "/" .. total25g, 12, ink.r, ink.g, ink.b))
        fracText:SetPoint("LEFT", ATT_COLS.raids, 0)

        local avgScore = 0
        if raids25 > 0 and entry.data.totalScore25 then
            avgScore = math.floor(entry.data.totalScore25 / raids25 + 0.5)
        end
        local ac = (avgScore < 60 and PAPER_BAD) or (avgScore < 80 and PAPER_WARN) or PAPER_OK
        local asr, asg, asb = ac.r, ac.g, ac.b
        local avgScoreText = Num(UI:CreateText(row, avgScore .. " pts", 12, asr, asg, asb))
        avgScoreText:SetPoint("LEFT", ATT_COLS.avg, 0)

        local lastStr = entry.data.lastRaid and entry.data.lastRaid > 0
            and GuildOS:DateText(entry.data.lastRaid, "/%Y") or "-"
        local lastText = Num(UI:CreateText(row, lastStr, 12, ink.r, ink.g, ink.b))
        lastText:SetPoint("LEFT", ATT_COLS.last, 0)

        -- Recent form: flag members who missed the latest guild raid(s), as a badge.
        local missed = GuildOS.RaidTracker:GetMissedStreak(entry.key, entry.groupTag, 5)
        if missed >= 1 then
            local b = UI:CreateBadge(row, missed >= 2 and string.format(L["missed last %d"], missed) or L["missed last raid"],
                missed >= 2 and C.danger or C.warn)
            b:SetPoint("LEFT", ATT_COLS.form, 0)
        end

        local capturedEntry = entry
        row:EnableMouse(true)
        rowHover(row)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local tr, tg, tb = GuildOS:GetClassColor(class)
            GameTooltip:AddLine(shortName, tr, tg, tb)
            local gLabel = capturedEntry.groupTag ~= "" and capturedEntry.groupTag or L["(no group)"]
            GameTooltip:AddLine(L["Group: "] .. gLabel, C.label.r, C.label.g, C.label.b)
            GameTooltip:AddLine(Prog(L["25-man Attendance"]), C.text.r, C.text.g, C.text.b)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["Raids:"], raids25 .. "/" .. total25g, 1,1,1, C.silver.r,C.silver.g,C.silver.b)
            GameTooltip:AddDoubleLine(L["Attendance %:"], pct .. "%", 1,1,1, pctClr.r,pctClr.g,pctClr.b)
            if avgScore > 0 then
                GameTooltip:AddDoubleLine(L["Avg score/raid:"], avgScore .. L[" pts"], 1,1,1, asr,asg,asb)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Score starts at 100 per raid."], 0.6,0.6,0.6)
            local pen = GuildOS.RaidTracker:GetPenalties(capturedEntry.groupTag)
            if pen.LATE > 0 then GameTooltip:AddLine("-" .. pen.LATE .. L[" Arrived late"], 0.7,0.5,0.5) end
            if pen.LEFT_EARLY > 0 then GameTooltip:AddLine("-" .. pen.LEFT_EARLY .. L[" Left early"], 0.7,0.5,0.5) end
            -- Only where consumables are checked (TBC, ADR-0014): elsewhere it never costs anything (issue #184).
            if pen.NO_CONSUMES > 0 and GuildOS.ConsumableChecker then
                GameTooltip:AddLine("-" .. pen.NO_CONSUMES .. L[" No consumables"], 0.7,0.5,0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        yOff = yOff + 24
    end

    -- One empty line, kept: a new one each redraw stayed on screen under the rows that came later.
    if not attContent.emptyText then
        attContent.emptyText = UI:CreateText(attContent, "", 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        attContent.emptyText:SetPoint("TOPLEFT", ATT_COLS.player, -8)
    end
    attContent.emptyText:SetText(Prog(L["No 25-man attendance data yet."]))
    attContent.emptyText:SetShown(#attList == 0)
    if #attList == 0 then yOff = yOff + 22 end

    attContent:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- TRIAL TRACKER PANEL
----------------------------------------------------------------------
-- Trials is drawn on the Officers' Room's parchment card (specs/salao/fase3.md): P is the paper's inks, a class
-- its colour on the paper (UI/Kit.lua); where the kit is absent, the shared colours.
local function trialKit() return rawget(GuildOS, "Kit") end
local P = setmetatable({}, { __index = function(_, k)
    local Kit = trialKit()
    return (Kit and Kit.PAPER or C)[k]
end })
local function trialClassInk(class)
    local Kit = trialKit()
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end
local function trialCheckbox(parent, text, size)
    local Kit = trialKit()
    if Kit then return Kit:Checkbox(parent, text, size) end
    return UI:CreateCheckbox(parent, text, size)
end

function GuildOS:CreateTrialsPanel(parent, _mainFrame)
    -- Flush with the Recruitment sub-tab bar's left edge, the first line UI.GAP under it (#371).
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", 0, -GAP)
    scrollParent:SetPoint("BOTTOMRIGHT", -GAP, GAP)

    -- The card's title says what this is ("Members on trial"); the count leads, under it.
    local statusText = UI:CreateText(scrollParent, "", 10, P.textSoft.r, P.textSoft.g, P.textSoft.b)
    statusText:SetPoint("TOPLEFT", 0, 0)

    -- The guild's length and its switch for new members (issue #249): an officer's, for the whole guild.
    -- The shared field (#371): it had a gold border and no inset, so "30" touched its edge.
    local TT = GuildOS.TrialTracker
    local ROW_Y = -18
    local daysLabel = UI:CreateText(scrollParent, L["Trial length (days)"], 11, P.text.r, P.text.g, P.text.b)
    daysLabel:SetPoint("LEFT", scrollParent, "TOPLEFT", 0, ROW_Y - 11)
    -- Room for a 100 to be refused, not cut to 10.
    local daysBox = UI:CreateInput(scrollParent, 48, 22, { numeric = true, max = 3 })
    daysBox:SetPoint("LEFT", daysLabel, "RIGHT", 8, 0)
    daysBox:HookScript("OnEscapePressed", function(self)
        self:SetText(tostring(TT and TT:GetDays() or ""))
    end)
    UI:AttachSaveButton(daysBox, function(box)
        local ok, why = TT:SetDays(box:GetText())
        if ok then
            GuildOS:Print(string.format(L["Trials now last %d days, the running ones included."], TT:GetDays()))
        elseif why == "range" then
            GuildOS:Print(string.format(L["Trial length must be a whole number of days from %d to %d."], TT.MIN_DAYS, TT.MAX_DAYS))
        end
        box:SetText(tostring(TT:GetDays()))
        GuildOS:RefreshTrialsPanel(parent)
    end)

    local autoCb = trialCheckbox(scrollParent, L["Every new member starts as a trial"], 18)
    autoCb:SetPoint("LEFT", daysBox.saveButton, "RIGHT", 16, 0)
    autoCb.checkbox.onChanged = function(cb, checked)
        TT:SetAuto(checked)
        cb:SetChecked(TT:IsAutoOn())
    end

    -- Under the row it explains, left-aligned (#371).
    local configHint = UI:CreateText(scrollParent,
        L["A new length moves the end of every running trial. Nobody already in the guild becomes a trial."],
        10, P.textSoft.r, P.textSoft.g, P.textSoft.b)
    configHint:SetPoint("TOPLEFT", 0, ROW_Y - 22 - 6)

    -- Column headers: the shared header, no band, its 1px rule under it (#371).
    local HEADER_Y = ROW_Y - 22 - 6 - 14 - GAP
    local colHeader = UI:CreateTableHeader(scrollParent)
    colHeader:SetPoint("TOPLEFT", 0, HEADER_Y)
    colHeader:SetPoint("TOPRIGHT", 0, HEADER_Y)

    local hName = UI:CreateHeaderText(colHeader, L["Member"], 10)
    hName:SetPoint("LEFT", 6, 0)
    local hIlvl = UI:CreateHeaderText(colHeader, L["iLvl"], 10)
    hIlvl:SetPoint("LEFT", 140, 0)
    if GuildOS.AttunementTracker then   -- attunements are TBC's (ADR-0014; issue #184)
        local hAtt = UI:CreateHeaderText(colHeader, L["Attuned"], 10)
        hAtt:SetPoint("LEFT", 210, 0)
    end
    local hSponsor = UI:CreateHeaderText(colHeader, L["Sponsor"], 10)
    hSponsor:SetPoint("LEFT", 290, 0)
    local hDays = UI:CreateHeaderText(colHeader, L["Remaining"], 10)
    hDays:SetPoint("LEFT", 390, 0)
    local hStatus = UI:CreateHeaderText(colHeader, L["Status"], 10)
    hStatus:SetPoint("LEFT", 455, 0)

    local trialScroll = CreateFrame("ScrollFrame", "GuildOSTrialScroll", scrollParent, "UIPanelScrollFrameTemplate")
    trialScroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
    trialScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(trialScroll, "GuildOSTrialScroll")

    local trialContent = CreateFrame("Frame", nil, trialScroll)
    trialContent:SetSize(1, 1)
    trialScroll:SetScrollChild(trialContent)
    UI:BindScrollChildWidth(trialScroll, trialContent)

    parent.trialContent = trialContent
    parent.statusText = statusText
    parent.expandedTrials = {}
    parent.trialDaysBox = daysBox
    parent.trialAutoCb = autoCb.checkbox

    parent:SetScript("OnShow", function()
        GuildOS:RefreshTrialsPanel(parent)
    end)
    -- An officer's change or the other officers' trials arriving redraw it while it is open (#249).
    if TT then
        TT.uiRefresh = function()
            if parent:IsVisible() then GuildOS:RefreshTrialsPanel(parent) end
        end
    end
end

function GuildOS:RefreshTrialsPanel(parent)
    local content = parent.trialContent
    local statusText = parent.statusText
    if not content or not GuildOS.TrialTracker then return end

    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    -- The guild's settings as this client holds them now: another officer's change may have arrived.
    if parent.trialDaysBox and not parent.trialDaysBox:HasFocus() then
        parent.trialDaysBox:SetText(tostring(GuildOS.TrialTracker:GetDays()))
    end
    if parent.trialAutoCb then parent.trialAutoCb:SetChecked(GuildOS.TrialTracker:IsAutoOn()) end

    -- Ready to review first (GetAllTrials' order), then running, then decided and left the guild.
    local trials = GuildOS.TrialTracker:GetAllTrials()
    statusText:SetText(#GuildOS.TrialTracker:GetActiveTrials() .. L[" active trials"])

    local expanded = parent.expandedTrials or {}
    local yOff = 0

    for _, trial in ipairs(trials) do
        local data = trial.data
        local isExpanded = expanded[trial.key]
        local memberData = GuildOS.db.members[trial.key]
        local progress = GuildOS.TrialTracker:GetProgress(trial.key)
        local state = GuildOS.TrialTracker:GetState(trial.key)

        -- Main row, hung by both top corners: a width read while the tab is hidden is 0 (#371).
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("TOPRIGHT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local Kit = trialKit()
        if Kit then Kit:Rule(row) end

        -- The table's zebra only: a trial waiting for a decision says so in its status column, and gold
        -- is the selection's colour, not a wash (#371).
        local rowIdx = math.floor(yOff / 26) % 2
        local altIdx = (rowIdx == 0) and P.row1 or P.row2
        row:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)

        -- Expand arrow
        local arrow = UI:CreateText(row, isExpanded and "v" or ">", 10, P.label.r, P.label.g, P.label.b)
        arrow:SetPoint("LEFT", 2, 0)

        -- Name with class color
        local shortName = trial.key:match("^([^-]+)") or trial.key
        local pClass = memberData and memberData.class
        local pr, pg, pb = P.text.r, P.text.g, P.text.b
        if pClass then pr, pg, pb = trialClassInk(pClass) end

        local nameText = UI:CreateText(row, shortName, 10, pr, pg, pb)
        nameText:SetPoint("LEFT", 14, 0)

        -- iLvl with delta
        if progress then
            local ilvlSign = progress.ilvlDelta > 0 and "+" or ""
            local ilvlColor = progress.ilvlDelta > 0 and P.green or (progress.ilvlDelta < 0 and P.red or P.silver)
            local ilvlStr = format("%d (%s%d)", progress.currentIlvl, ilvlSign, progress.ilvlDelta)
            local ilvlText = Num(UI:CreateText(row, ilvlStr, 9, ilvlColor.r, ilvlColor.g, ilvlColor.b))
            ilvlText:SetPoint("LEFT", 140, 0)

            -- Attunement progress
            if GuildOS.AttunementTracker then
                local attColor = progress.attDelta > 0 and P.green or P.silver
                local attStr = format("%d/%d (+%d)", progress.currentAttDone, progress.attTotal, progress.attDelta)
                local attText = Num(UI:CreateText(row, attStr, 9, attColor.r, attColor.g, attColor.b))
                attText:SetPoint("LEFT", 210, 0)
            end
        else
            local ilvlVal = memberData and memberData.avgIlvl or 0
            if ilvlVal > 0 then
                local ilvlText = Num(UI:CreateText(row, tostring(ilvlVal), 9, P.silver.r, P.silver.g, P.silver.b))
                ilvlText:SetPoint("LEFT", 140, 0)
            end
            if GuildOS.AttunementTracker then
                local noProgText = UI:CreateText(row, "-", 9, P.silver.r, P.silver.g, P.silver.b)
                noProgText:SetPoint("LEFT", 210, 0)
            end
        end

        local sponsorText = UI:CreateText(row, data.sponsor or "?", 10, P.silver.r, P.silver.g, P.silver.b)
        sponsorText:SetPoint("LEFT", 290, 0)

        local daysRem = GuildOS.TrialTracker:GetDaysRemaining(trial.key)
        local daysStr = daysRem and (daysRem .. "d") or "-"
        local daysColor = P.text
        if daysRem then
            daysColor = daysRem > 14 and P.green or (daysRem > 7 and P.warn or P.red)
        end
        local daysText = Num(UI:CreateText(row, daysStr, 10, daysColor.r, daysColor.g, daysColor.b))
        daysText:SetPoint("LEFT", 390, 0)

        -- Status badge: the state worked out from the start and the guild's length, so a trial an older
        -- client stored as "expired" reads as running again once the guild lengthens its trials (#249).
        local statusColor = P.silver
        local statusStr = tostring(data.status or "?")
        if state == "trial" then
            statusColor = P.textSoft; statusStr = L["on trial"]
        elseif state == "review" then
            statusColor = P.red; statusStr = L["ready to review"]
        elseif state == "left" then
            statusColor = P.silver; statusStr = L["left the guild"]
        elseif state == "approved" then
            statusColor = P.green; statusStr = L["approved"]
        elseif state == "denied" then
            statusColor = P.red; statusStr = L["denied"]
        end
        local sText = UI:CreateText(row, statusStr, 10, statusColor.r, statusColor.g, statusColor.b)
        sText:SetPoint("LEFT", 455, 0)
        sText:SetWidth(140)
        sText:SetJustifyH("LEFT")
        sText:SetWordWrap(false)

        -- Approve / deny for every trial nobody has decided yet, running or ready to review
        if GuildOS.TrialTracker:IsUnresolved(data) then
            local approveBtn = UI:CreateButton(row, L["OK"], 30, 18)
            approveBtn:SetPoint("LEFT", 600, 0)
            approveBtn:SetScript("OnClick", function()
                GuildOS.TrialTracker:UpdateStatus(trial.key, GuildOS.TrialTracker.STATUS.APPROVED)
                GuildOS:RefreshTrialsPanel(parent)
            end)

            local denyBtn = UI:CreateButton(row, L["X"], 24, 18)
            denyBtn:SetPoint("LEFT", approveBtn, "RIGHT", 4, 0)
            denyBtn:SetScript("OnClick", function()
                GuildOS.TrialTracker:UpdateStatus(trial.key, GuildOS.TrialTracker.STATUS.DENIED)
                GuildOS:RefreshTrialsPanel(parent)
            end)
        end

        -- Click to expand/collapse
        row:SetScript("OnClick", function()
            expanded[trial.key] = not expanded[trial.key]
            parent.expandedTrials = expanded
            GuildOS:RefreshTrialsPanel(parent)
        end)

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(P.rowHover.r, P.rowHover.g, P.rowHover.b, P.rowHover.a)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(altIdx.r, altIdx.g, altIdx.b, altIdx.a)
        end)

        yOff = yOff + 28

        -- Expanded detail section
        if isExpanded then
            local detailFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
            detailFrame:SetPoint("TOPLEFT", 10, -yOff)
            detailFrame:SetPoint("TOPRIGHT", -10, -yOff)
            detailFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            detailFrame:SetBackdropColor(0.937, 0.878, 0.741, 1)   -- the paper's light box

            local dY = -6

            -- Start date
            local startStr = GuildOS:DateText(data.startDate or 0, "/%y")
            local daysSince = GuildOS.TrialTracker:GetDaysSinceStart(trial.key)
            local infoFS = detailFrame:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(infoFS, 9)
            infoFS:SetPoint("TOPLEFT", 10, dY)
            infoFS:SetTextColor(P.silver.r, P.silver.g, P.silver.b)
            infoFS:SetText(format(L["Started: %s  |  Day %d  |  Sponsor: %s"], startStr, daysSince or 0, data.sponsor or "?"))
            infoFS:Show()
            dY = dY - 16

            -- Officer comments
            if data.notes and #data.notes > 0 then
                local notesLabel = detailFrame:CreateFontString(nil, "OVERLAY")
                GuildOS:ApplyFont(notesLabel, 9)
                notesLabel:SetPoint("TOPLEFT", 10, dY)
                notesLabel:SetTextColor(P.label.r, P.label.g, P.label.b)
                notesLabel:SetText(L["Comments:"])
                notesLabel:Show()
                dY = dY - 14

                for _, note in ipairs(data.notes) do
                    local noteFS = detailFrame:CreateFontString(nil, "OVERLAY")
                    GuildOS:ApplyFont(noteFS, 9)
                    noteFS:SetPoint("TOPLEFT", 14, dY)
                    -- A set width, not a second anchor: GetStringHeight below measures the wrap at once, before
                    -- an anchored width would be resolved. `content` is bound to the scroll's width (#371).
                    noteFS:SetWidth(UI:TextWidth(content, 60))
                    noteFS:SetJustifyH("LEFT")
                    noteFS:SetWordWrap(true)
                    local dateStr = note.timestamp and GuildOS:DateText(note.timestamp, " %H:%M") or ""
                    noteFS:SetText(format("|cffAAAAAA[%s %s]|r %s", note.author or "?", dateStr, note.text or ""))
                    noteFS:Show()
                    dY = dY - (noteFS:GetStringHeight() + 3)
                end
            end

            -- Inline add note: the shared field with its hint, running up to the Add button (#371).
            local addBtn = UI:CreateButton(detailFrame, L["Add"], 50, 22)
            addBtn:SetPoint("TOPRIGHT", -10, dY - 4)
            local addBox = UI:CreateInput(detailFrame, 200, 22, { max = 200, placeholder = L["Add comment..."] })
            addBox:SetPoint("TOPLEFT", 10, dY - 4)
            addBox:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
            addBtn:SetScript("OnClick", function()
                local text = addBox:GetText()
                if text and strtrim(text) ~= "" then
                    GuildOS.TrialTracker:AddTrialNote(trial.key, strtrim(text))
                    addBox:SetText("")
                    addBox:ClearFocus()
                    GuildOS:RefreshTrialsPanel(parent)
                end
            end)
            addBox:SetScript("OnEnterPressed", function(self)
                local text = self:GetText()
                if text and strtrim(text) ~= "" then
                    GuildOS.TrialTracker:AddTrialNote(trial.key, strtrim(text))
                    self:SetText("")
                    self:ClearFocus()
                    GuildOS:RefreshTrialsPanel(parent)
                end
            end)

            dY = dY - 30
            detailFrame:SetHeight(math.abs(dY) + 6)
            yOff = yOff + math.abs(dY) + 8
        end
    end

    -- One empty line, kept: a new one each redraw stayed on screen under the trials that came later.
    if not parent.trialEmpty then
        parent.trialEmpty = UI:CreateText(content, L["No trial members tracked."], 11, P.textSoft.r, P.textSoft.g, P.textSoft.b)
        parent.trialEmpty:SetPoint("TOPLEFT", 6, -6)
    end
    parent.trialEmpty:SetShown(#trials == 0)
    if #trials == 0 then yOff = 30 end

    content:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- EXPORT CHOOSER — pick a dataset and format from the UI (not just chat)
----------------------------------------------------------------------
function GuildOS:ShowExportChooser()
    if self.exportChooser then self.exportChooser:Show(); return end

    local f = CreateFrame("Frame", "GuildOSExportChooser", UIParent, "BackdropTemplate")
    f:SetSize(390, 300)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)
    self.exportChooser = f

    local title = UI:CreateTitle(f, L["Export Data"], 16)
    title:SetPoint("TOP", 0, -12)
    local hint = UI:CreateText(f, L["Pick a dataset and format. CSV = spreadsheets, Discord = pastebox."], 9, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    -- A dataset this client does not have (retail's loot, ADR-0026) is left out.
    local datasets = {
        { key = "roster",     label = L["Roster"] },
        { key = "attendance", label = L["Attendance"] },
        { key = "loot",       label = L["Loot History"] },
        { key = "readiness",  label = L["Readiness"] },
        { key = "equity",     label = L["Loot Equity"] },
        { key = "standings",  label = L["DKP Standings"] },
        -- The officers' own (issue #425).
        { key = "log",        label = L["Audit Log"], officer = true },
        { key = "former",     label = L["Former members"], officer = true },
    }
    local y = -56
    for _, d in ipairs(datasets) do
        if GuildOS.Exporter:Has(d.key) and (not d.officer or GuildOS:IsOfficer()) then
            local lbl = UI:CreateText(f, d.label, 11, C.text.r, C.text.g, C.text.b)
            lbl:SetPoint("TOPLEFT", 16, y)
            local fx = 150
            for _, fmt in ipairs({ "csv", "tsv", "discord" }) do
                local b = UI:CreateButton(f, fmt:upper(), 66, 20)
                b:SetPoint("TOPLEFT", fx, y + 3)
                b:SetScript("OnClick", function()
                    if not GuildOS.Exporter then return end
                    local text, t = GuildOS.Exporter:Build(d.key, fmt)
                    if text then GuildOS:ShowExportPopup(string.format("%s (%s)", t or d.label, fmt), text) end
                end)
                fx = fx + b:GetWidth() + 4  -- a button its label grew pushes the next one (issue #28)
            end
            y = y - 32
        end
    end
    f:SetHeight(math.max(300, -y + 16))   -- the officers' two rows (#425) need room below the six
end

----------------------------------------------------------------------
-- EXPORT POPUP (copyable text box)
----------------------------------------------------------------------
function GuildOS:ShowExportPopup(titleStr, text)
    if self.exportPopup then self.exportPopup:Hide() end

    local f = CreateFrame("Frame", "GuildOSExportPopup", UIParent, "BackdropTemplate")
    f:SetSize(500, 350)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, nil, "sectionTitle")
    titleText:SetPoint("TOP", 0, -10)
    titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
    titleText:SetText(titleStr or L["Export"])

    local hint = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(hint, 10)
    hint:SetPoint("TOP", 0, -28)
    hint:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    hint:SetText(L["Press Ctrl+A to select all, then Ctrl+C to copy"])

    -- Scroll frame for the edit box
    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSExportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 40)
    UI:SkinScrollBar(scrollFrame, "GuildOSExportScroll")

    -- The shared field, multi-line (#371). It grows with its text; the scroll frame keeps it clear of
    -- the bar, and Escape still closes the window after the field lets go.
    local editBox = UI:CreateInput(scrollFrame, 460, 262, { multiline = true })
    editBox:SetAutoFocus(true)
    editBox:SetText(text or "")
    editBox:HighlightText()
    editBox:HookScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    UI:BindScrollChildWidth(scrollFrame, editBox)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local closeTextBtn = UI:CreateButton(f, L["Close"], 80, 24)
    closeTextBtn:SetPoint("BOTTOM", 0, 10)
    closeTextBtn:SetScript("OnClick", function() f:Hide() end)

    f:Show()
    self.exportPopup = f
end

----------------------------------------------------------------------
-- SoftRes import popup: paste Gargul export string or CSV
----------------------------------------------------------------------
function GuildOS:ShowSoftResImportPopup()
    if self.srImportPopup then self.srImportPopup:Hide() end

    local f = CreateFrame("Frame", "GuildOSSRImportPopup", UIParent, "BackdropTemplate")
    f:SetSize(520, 360)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
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

    local titleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, nil, "sectionTitle")
    titleText:SetPoint("TOP", 0, -10)
    titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
    titleText:SetText(L["Import SoftRes from softres.it"])

    local hint = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(hint, 10)
    hint:SetPoint("TOP", 0, -28)
    hint:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    hint:SetText(L["Paste the Gargul export string (or CSV) from softres.it, then click Import."])

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSSRImportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 44)
    UI:SkinScrollBar(scrollFrame, "GuildOSSRImportScroll")

    -- The shared field, multi-line (#371); Escape still closes the window after the field lets go.
    local editBox = UI:CreateInput(scrollFrame, 480, 250, { multiline = true })
    editBox:SetAutoFocus(true)
    editBox:HookScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    UI:BindScrollChildWidth(scrollFrame, editBox)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local importBtn = UI:CreateButton(f, L["Import"], 100, 26)
    importBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    importBtn:SetScript("OnClick", function()
        local raw = editBox:GetText()
        if GuildOS.SoftRes then
            GuildOS.SoftRes:Import(raw)
        end
        f:Hide()
    end)

    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 26)
    cancelBtn:SetPoint("RIGHT", importBtn, "LEFT", -6, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f:Show()
    self.srImportPopup = f
end

----------------------------------------------------------------------
-- Companion import popup: paste the roster string from the website.
-- Invite and group sit on the same window because they are the next two
-- things a raid leader does, and making them hunt for a slash command
-- while twenty-five people wait is how a feature goes unused.
----------------------------------------------------------------------
function GuildOS:ShowImportPopup()
    if self.companionImportPopup then self.companionImportPopup:Hide() end

    local f = CreateFrame("Frame", "GuildOSCompanionImportPopup", UIParent, "BackdropTemplate")
    f:SetSize(520, 380)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
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

    local titleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, nil, "sectionTitle")
    titleText:SetPoint("TOP", 0, -10)
    titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
    titleText:SetText(L["Raid roster from the website"])

    local hint = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(hint, 10)
    hint:SetPoint("TOP", 0, -26)
    hint:SetWidth(496)
    hint:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    hint:SetText(L["Paste the roster string, then Load. Invite and Groups work after that."] .. " "
        .. L["A cores code from guildos.me goes here too."])

    local status = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(status, 11)
    status:SetPoint("BOTTOMLEFT", 14, 16)
    status:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    -- Whatever was loaded earlier survives a reload, so say so on open.
    local existing = GuildOS.CompanionImport and GuildOS.CompanionImport:Current()
    if existing then
        status:SetText(string.format(L["Loaded: %s (%d)"], existing.title, #existing.members))
    end

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSCompanionImportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -56)   -- below a hint of two lines
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 76)
    UI:SkinScrollBar(scrollFrame, "GuildOSCompanionImportScroll")

    -- The shared field, multi-line (#371); Escape still closes the window after the field lets go.
    local editBox = UI:CreateInput(scrollFrame, 480, 250, { multiline = true })
    editBox:SetAutoFocus(true)
    editBox:HookScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    UI:BindScrollChildWidth(scrollFrame, editBox)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local loadBtn = UI:CreateButton(f, L["Load"], 90, 26)
    loadBtn:SetPoint("BOTTOMRIGHT", -12, 44)
    loadBtn:SetScript("OnClick", function()
        local n, err, said = GuildOS.CompanionImport:Load(editBox:GetText())
        if err then
            status:SetTextColor(1, 0.35, 0.35)
            status:SetText(err)
        elseif said then
            -- A GOSCORE1 pasted here: the guild's cores, not a raid's roster (issue #347).
            status:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            status:SetText(said)
        else
            local r = GuildOS.CompanionImport:Current()
            status:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            status:SetText(string.format(L["Loaded: %s (%d)"], r.title, n))
        end
    end)

    -- This window's two buttons act on the roster it holds, the one just loaded, not the raid of the window
    -- the Web tab's buttons act on (issue #400).
    local inviteBtn = UI:CreateButton(f, L["Invite all"], 90, 26)
    inviteBtn:SetPoint("RIGHT", loadBtn, "LEFT", -6, 0)
    inviteBtn:SetScript("OnClick", function()
        local I = GuildOS.CompanionImport
        local n, here, err, offline = I:InviteAll(I:Current())
        if err then
            status:SetTextColor(1, 0.35, 0.35)
            status:SetText(err)
        else
            status:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            status:SetText(string.format(L["Invited %d, already here %d."], n, here))
        end
        local off = I.OfflineLine(offline)
        if off then GuildOS:Print(off) end
    end)

    local groupsBtn = UI:CreateButton(f, L["Groups"], 90, 26)
    groupsBtn:SetPoint("RIGHT", inviteBtn, "LEFT", -6, 0)
    groupsBtn:SetScript("OnClick", function()
        local moved, err = GuildOS.CompanionImport:OrganizeGroups(GuildOS.CompanionImport:Current())
        if err then
            status:SetTextColor(1, 0.35, 0.35)
            status:SetText(err)
        else
            status:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            status:SetText(string.format(L["Moved %d into their groups."], moved))
        end
    end)

    f:Show()
    self.companionImportPopup = f
end

----------------------------------------------------------------------
-- WISHLIST FRAME — standalone frame for each member's own wishlist
-- Accessible via /gos wish  or the "My Wishlist" button in roster.
----------------------------------------------------------------------
-- WISH_VISIBLE × WISH_ROW_HEIGHT must fit within the scroll area.
-- Frame=520, title+header=66, bottom bar=50 → scroll area=404px → max rows=floor(404/28)=14
local WISH_ROW_HEIGHT = 28
local WISH_VISIBLE    = 14

-- The addresses the "Edit on the site" buttons show (#385). The first is the player's own page; the
-- second is the site's root, because the core's page needs the guild key and the addon cannot build it.
local SITE_WISHLIST_URL = "https://guildos.me/wishlist"
local SITE_URL = "https://guildos.me"

local function BuildWishlistFrame()
    local f = CreateFrame("Frame", "GuildOSWishlistFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 520)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:Hide()

    table.insert(UISpecialFrames, "GuildOSWishlistFrame")

    -- Refresh rows whenever a queued item arrives from the server
    GuildOS.Compat.RegisterEvent(f, "GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" and self:IsShown() then
            if not self._itemInfoTimer then
                self._itemInfoTimer = true
                C_Timer.After(0.3, function()
                    self._itemInfoTimer = nil
                    if f:IsShown() then
                        GuildOS:RefreshWishlistFrame()
                    end
                end)
            end
        end
    end)

    -- Title bar
    local titleBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetPoint("TOPLEFT",  1, -1)
    titleBg:SetPoint("TOPRIGHT", -1, -1)
    titleBg:SetHeight(39)
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, nil, "sectionTitle")
    titleText:SetPoint("LEFT", 14, 0)
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
    titleText:SetText(L["MY WISHLIST"])
    f.titleText = titleText

    -- Counter (N/50)
    local counterText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(counterText, 11)
    counterText:SetPoint("RIGHT", -42, 0)
    counterText:SetPoint("TOP",    0, -14)
    counterText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    counterText:SetText("0/50")
    f.counterText = counterText

    -- A 1px line under the title: gold is the selection's, not a rule's (#371).
    local titleLine = UI:CreateSeparator(f)
    titleLine:SetPoint("TOPLEFT",  0, -40)
    titleLine:SetPoint("TOPRIGHT", 0, -40)

    -- Close button
    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Column headers: the shared header, no band, its 1px rule where the gold one was (#371).
    local hdr = UI:CreateTableHeader(f)
    hdr:SetPoint("TOPLEFT",  1, -42)
    hdr:SetPoint("TOPRIGHT", -1, -42)
    local function Hdr(lbl, x, w, justify)
        local t = UI:CreateHeaderText(hdr, lbl)
        t:SetPoint("LEFT", x - 1, 0)
        t:SetWidth(w)
        t:SetJustifyH(justify or "LEFT")
        return t
    end
    Hdr("#",      10,  24, "CENTER")
    Hdr(L["ITEM"],   38, 262, "LEFT")
    Hdr(L["TYPE"],  308,  50, "CENTER")
    Hdr(L["ORDER"], 366,  60, "CENTER")

    -- Scroll area: TOPLEFT at y=-65, BOTTOMRIGHT at y=+50 (50px bottom bar)
    -- Available height: 520 - 65 - 50 = 405px; 14 rows × 28px = 392px ✓
    local scrollContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    scrollContainer:SetPoint("TOPLEFT",     1, -65)
    scrollContainer:SetPoint("BOTTOMRIGHT", -1, 50)
    scrollContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    scrollContainer:SetBackdropColor(0.035, 0.035, 0.050, 1.0)

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSWishlistScroll", scrollContainer, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 0)
    UI:SkinScrollBar(scrollFrame, "GuildOSWishlistScroll")
    f.scrollFrame = scrollFrame

    -- Rows (parented to scrollContainer, clipped by it)
    f.rows = {}
    for i = 1, WISH_VISIBLE do
        local row = CreateFrame("Button", "GuildOSWishRow" .. i, scrollContainer, "BackdropTemplate")
        row:SetHeight(WISH_ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  0, -((i - 1) * WISH_ROW_HEIGHT))
        row:SetPoint("RIGHT",  scrollContainer, "RIGHT", -18, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        local bgColor = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        row.defaultBg = bgColor

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            if self.itemLink and self.itemLink ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            local bg = self.defaultBg
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            GameTooltip:Hide()
        end)

        -- Order number
        local numText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(numText, nil, "tableNum")
        numText:SetPoint("LEFT", 10, 0)
        numText:SetWidth(24)
        numText:SetJustifyH("CENTER")
        numText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        row.numText = numText

        -- Item link text
        local itemText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(itemText, 12)
        itemText:SetPoint("LEFT", 38, 0)
        itemText:SetWidth(262)
        itemText:SetJustifyH("LEFT")
        itemText:SetWordWrap(false)
        row.itemText = itemText

        -- MS/OS badge
        local typeText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(typeText, 10)
        typeText:SetPoint("LEFT", 308, 0)
        typeText:SetWidth(50)
        typeText:SetJustifyH("CENTER")
        row.typeText = typeText

        -- ↑ button
        local upBtn = CreateFrame("Button", nil, row)
        upBtn:SetSize(18, 18)
        upBtn:SetPoint("LEFT", 366, 0)
        upBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetScript("OnClick", function()
            if row.itemId and GuildOS.Wishlist then
                GuildOS.Wishlist:ReorderWishlist(row.itemId, -1)
            end
        end)
        upBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)

        -- ↓ button
        local downBtn = CreateFrame("Button", nil, row)
        downBtn:SetSize(18, 18)
        downBtn:SetPoint("LEFT", 386, 0)
        downBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetScript("OnClick", function()
            if row.itemId and GuildOS.Wishlist then
                GuildOS.Wishlist:ReorderWishlist(row.itemId, 1)
            end
        end)
        downBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)

        -- × remove button
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(18, 18)
        removeBtn:SetPoint("LEFT", 410, 0)
        local removeTex = removeBtn:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(removeTex, 14)
        removeTex:SetPoint("CENTER")
        removeTex:SetTextColor(0.7, 0.2, 0.2)
        removeTex:SetText("×")
        removeBtn:SetScript("OnClick", function()
            if row.itemId and GuildOS.Wishlist then
                GuildOS.Wishlist:RemoveFromWishlist(row.itemId)
            end
        end)
        removeBtn:SetScript("OnLeave", function()
            local bg = row.defaultBg
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end)
        removeBtn:SetScript("OnEnter", function()
            removeTex:SetTextColor(1, 0.3, 0.3)
        end)
        row.upBtn, row.downBtn, row.removeBtn = upBtn, downBtn, removeBtn

        row:Hide()
        f.rows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, WISH_ROW_HEIGHT, function()
            GuildOS:RefreshWishlistFrame()
        end)
    end)

    -- Bottom bar (50px): a 1px line (not gold, #371) + dark background
    local bottomLine = UI:CreateSeparator(f)
    bottomLine:SetPoint("BOTTOMLEFT",  0, 50)
    bottomLine:SetPoint("BOTTOMRIGHT", 0, 50)

    local bottomBg = f:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottomBg:SetPoint("BOTTOMLEFT",  1, 1)
    bottomBg:SetPoint("BOTTOMRIGHT", -1, 1)
    bottomBg:SetHeight(49)
    bottomBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    -- MS/OS radio buttons
    -- Layout (500px frame): [10] [msBtn 56] [4] [osBtn 56] [6] [addBox 132] [6] [addBtn 88] [8] [syncBtn 110] [8]
    -- Total: 10+56+4+56+6+132+6+88+8+110+8 = 484, centred with margins ✓
    f.isOS = false   -- false = Main Spec, true = Off Spec

    local msBtn = UI:CreateButton(f, L["MS"], 56, 28)
    msBtn:SetPoint("BOTTOMLEFT", 10, 11)
    f.msBtn = msBtn

    local osBtn = UI:CreateButton(f, L["OS"], 56, 28)
    osBtn:SetPoint("BOTTOMLEFT", msBtn, "BOTTOMRIGHT", 4, 0)
    f.osBtn = osBtn

    -- The spec the next item goes to: one of two, marked by UI:SetSelected (#371), not a gold fill
    -- and a dot of its own.
    local function SetSpecType(isOS)
        f.isOS = isOS
        UI:SetSelected(msBtn, not isOS)
        UI:SetSelected(osBtn, isOS)
    end

    msBtn:SetScript("OnClick", function() SetSpecType(false) end)
    osBtn:SetScript("OnClick", function() SetSpecType(true)  end)

    -- The tooltips hook the buttons' own hover, which keeps painting the selection.
    msBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Main Spec"], C.text.r, C.text.g, C.text.b)
        GameTooltip:AddLine(L["Item and priority for your main spec."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    msBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    osBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Off Spec"], C.text.r, C.text.g, C.text.b)
        GameTooltip:AddLine(L["Item for a secondary spec."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    osBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    SetSpecType(false)   -- initialise with MS selected

    -- Add item: the shared field and its placeholder (#371).
    local addBox = UI:CreateInput(f, 132, 28, { max = 200, placeholder = L["Search item or paste link..."] })
    addBox:SetPoint("BOTTOMLEFT", osBtn, "BOTTOMRIGHT", 6, 0)

    -- Search dropdown — appears above the addBox
    local DROP_ROWS  = 6
    local DROP_ROW_H = 22

    local dropdown = CreateFrame("Frame", nil, f, "BackdropTemplate")
    dropdown:SetWidth(280)
    dropdown:SetHeight(DROP_ROWS * DROP_ROW_H + 2)
    dropdown:SetPoint("BOTTOMLEFT", addBox, "TOPLEFT", 0, 2)
    dropdown:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(dropdown),
    })
    -- A dropdown is elevation 4: popup surface, lineHi border.
    dropdown:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    dropdown:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    UI:StylePopup(dropdown, { shadowSize = 10 })
    dropdown:SetFrameLevel(f:GetFrameLevel() + 20)
    dropdown:Hide()
    f.dropdown = dropdown

    dropdown.rows = {}
    for i = 1, DROP_ROWS do
        local dr = CreateFrame("Button", nil, dropdown)
        dr:SetHeight(DROP_ROW_H)
        dr:SetPoint("TOPLEFT",  1, -((i - 1) * DROP_ROW_H) - 1)
        dr:SetPoint("TOPRIGHT", -1, -((i - 1) * DROP_ROW_H) - 1)
        dr:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        dr:GetHighlightTexture():SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
        local drText = dr:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(drText, 11)
        drText:SetPoint("LEFT", 6, 0)
        drText:SetPoint("RIGHT", -6, 0)
        drText:SetJustifyH("LEFT")
        drText:SetWordWrap(false)
        dr.label = drText
        dr:SetScript("OnClick", function()
            f.selectedItemId   = dr.itemId
            f.selectedItemLink = dr.itemLink
            f.selectedItemName = dr.itemName
            f.suppressSearch   = true
            addBox:SetText(dr.itemName or "")
            f.suppressSearch   = nil
            dropdown:Hide()
        end)
        dropdown.rows[i] = dr
        dr:Hide()
    end

    local function UpdateDropdown(query)
        query = strlower(strtrim(query or ""))
        -- Skip search for empty input, pasted links, or raw IDs — handled directly in DoAdd
        if query == "" or query:find("item:", 1, true) or tonumber(query) then
            dropdown:Hide()
            return
        end
        local results = {}
        if GuildOS.Wishlist and GuildOS.Wishlist.itemIndex then
            for itemId in pairs(GuildOS.Wishlist.itemIndex) do
                -- The journal's name stands in for an item not cached yet (retail, issue #185).
                local name, link, quality = GuildOS.Wishlist:ItemFacts(itemId)
                if name and strlower(name):find(query, 1, true) then
                    tinsert(results, { itemId = itemId, name = name, link = link, quality = quality or 1 })
                end
            end
        end
        table.sort(results, function(a, b) return a.name < b.name end)
        if #results == 0 then
            dropdown:Hide()
            return
        end
        local shown = math.min(#results, DROP_ROWS)
        dropdown:SetHeight(shown * DROP_ROW_H + 2)
        for i = 1, DROP_ROWS do
            local dr = dropdown.rows[i]
            if i <= shown then
                local entry = results[i]
                local r, g, b = GuildOS.Compat.GetItemQualityColor(entry.quality)
                dr.label:SetText(entry.name)
                UI:SetInk(dr.label, r, g, b)   -- the paper's quality ink on a card (#449)
                dr.itemId   = entry.itemId
                dr.itemLink = entry.link
                dr.itemName = entry.name
                dr:Show()
            else
                dr:Hide()
            end
        end
        dropdown:Show()
    end

    -- Hooked: the field shows and hides its own placeholder (#371).
    addBox:HookScript("OnTextChanged", function(self)
        local t = self:GetText()
        if f.suppressSearch then return end
        -- Guard: WoW may fire OnTextChanged twice after SetText; don't clear
        -- the selection if the text still matches what was just selected.
        if f.selectedItemId and t == f.selectedItemName then return end
        f.selectedItemId   = nil
        f.selectedItemLink = nil
        f.selectedItemName = nil
        UpdateDropdown(t)
    end)

    local function DoAdd()
        local text = strtrim(addBox:GetText() or "")
        if text == "" then return end
        local itemId, itemLink
        if f.selectedItemId then
            -- Came from dropdown click
            itemId   = f.selectedItemId
            itemLink = f.selectedItemLink or ""
        elseif text:find("item:") then
            -- Pasted a full item hyperlink
            itemId   = tonumber(text:match("item:(%d+)"))
            itemLink = text
        elseif tonumber(text) then
            -- Typed a raw item ID
            itemId = tonumber(text)
            local _, lnk = GuildOS.Compat.GetItemInfo(itemId)
            itemLink = lnk or ""
        end
        if not itemId then
            GuildOS:Print(L["[Wishlist] Select from the list, paste an item link, or type the item ID."])
            return
        end
        if GuildOS.Wishlist then
            GuildOS.Wishlist:AddToWishlist(itemId, itemLink, f.isOS)
        end
        addBox:SetText("")
        addBox:ClearFocus()
        f.selectedItemId   = nil
        f.selectedItemLink = nil
        f.selectedItemName = nil
        dropdown:Hide()
    end

    addBox:SetScript("OnEnterPressed", function(self) DoAdd(); self:ClearFocus() end)
    addBox:HookScript("OnEscapePressed", function() dropdown:Hide() end)
    f.addBox = addBox

    local addBtn = UI:CreateButton(f, L["+ Add"], 88, 28)
    addBtn:SetPoint("BOTTOMLEFT", addBox, "BOTTOMRIGHT", 6, 0)
    addBtn:SetScript("OnClick", DoAdd)
    f.addBtn = addBtn

    -- Sync button — anchored to the right, with guaranteed gap from addBtn
    local syncBtn = UI:CreateButton(f, L["Send to guild"], 110, 28)   -- it only sends (audit B26)
    syncBtn:SetPoint("BOTTOMRIGHT", -8, 11)
    syncBtn:SetScript("OnClick", function()
        if GuildOS.Wishlist then GuildOS.Wishlist:BroadcastMyWishlist(true) end
        GuildOS:Print(L["[Wishlist] Sent to the guild."])
    end)
    f.syncBtn = syncBtn

    -- When the site holds the list the editor is read-only and these two stand where the controls were
    -- (shown by RefreshWishlistFrame, never here).
    local siteLine = UI:CreateText(f, L["Your list comes from the site."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    siteLine:SetPoint("BOTTOMLEFT", 14, 19)
    siteLine:Hide()
    f.siteLine = siteLine
    local siteBtn = UI:CreateButton(f, L["Edit on the site"], 140, 28)
    siteBtn:SetPoint("BOTTOMRIGHT", -8, 11)
    -- The line takes the width the button leaves and wraps, so a long translation never runs under it.
    siteLine:ClearAllPoints()
    siteLine:SetPoint("BOTTOMLEFT", 14, 11)
    siteLine:SetPoint("RIGHT", siteBtn, "LEFT", -8, 0)
    siteLine:SetHeight(28)
    siteLine:SetJustifyH("LEFT")
    siteLine:SetJustifyV("MIDDLE")
    siteLine:SetWordWrap(true)
    siteBtn:SetScript("OnClick", function() GuildOS:ShowExportPopup(L["Edit on the site"], SITE_WISHLIST_URL) end)
    siteBtn:Hide()
    f.siteBtn = siteBtn

    GuildOS.WishlistFrame = f
    return f
end

function GuildOS:ShowWishlistFrame()
    if not self.WishlistFrame then
        BuildWishlistFrame()
    end
    -- Pre-request item info for all wishlist entries so the client
    -- fetches any uncached items before (or just after) we display them: the site's list when it holds mine.
    local site = GuildOS.Wishlist and GuildOS.Wishlist:SiteListInForce()
    local list = (site and site.wishlist) or (GuildOS.Wishlist and GuildOS.Wishlist:GetMyList()) or {}
    for _, entry in ipairs(list) do
        GuildOS.Compat.GetItemInfo(entry.itemId)
    end
    self:RefreshWishlistFrame()
    self.WishlistFrame:Show()
end

function GuildOS:RefreshWishlistFrame()
    local f = self.WishlistFrame
    if not f then return end

    -- The site is the source of this list: the editor only shows it, and what it shows is the site's list in
    -- force (#385, R23), never the game's own list under the site's name.
    local site = GuildOS.Wishlist and GuildOS.Wishlist:SiteListInForce()
    local fromSite = site ~= nil
    local rawList = (site and site.wishlist) or (GuildOS.Wishlist and GuildOS.Wishlist:GetMyList()) or {}
    for _, n in ipairs({ "msBtn", "osBtn", "addBox", "addBtn", "syncBtn" }) do
        if fromSite then f[n]:Hide() else f[n]:Show() end
    end
    if fromSite then f.dropdown:Hide(); f.siteLine:Show(); f.siteBtn:Show() else f.siteLine:Hide(); f.siteBtn:Hide() end

    -- Split into active and delivered; delivered entries appear at the bottom.
    local active    = {}
    local delivered = {}
    for _, entry in ipairs(rawList) do
        local isDelivered = GuildOS.Wishlist and GuildOS.Wishlist:IsItemDelivered(entry.itemId)
        if isDelivered then
            table.insert(delivered, entry)
        else
            table.insert(active, entry)
        end
    end
    local list = {}
    for _, e in ipairs(active)    do table.insert(list, { entry = e, delivered = false }) end
    for _, e in ipairs(delivered) do table.insert(list, { entry = e, delivered = true  }) end

    local total = #list
    f.counterText:SetText(#rawList .. "/50")

    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)
    FauxScrollFrame_Update(f.scrollFrame, total, WISH_VISIBLE, WISH_ROW_HEIGHT)

    for i = 1, WISH_VISIBLE do
        local row     = f.rows[i]
        local dataIdx = offset + i

        if dataIdx <= total then
            local item        = list[dataIdx]
            local entry       = item.entry
            local isDelivered = item.delivered

            -- Background: delivered rows use a darker, muted colour
            local bgColor
            if isDelivered then
                bgColor = { r=0.08, g=0.08, b=0.08, a=0.9 }
            else
                bgColor = (i % 2 == 0) and C.row2 or C.row1
            end
            row.defaultBg = bgColor
            row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

            row.itemId   = entry.itemId
            row.itemLink = entry.itemLink or ""

            -- Order number, or for a delivered item the game's ready mark: a texture, since a check-mark
            -- character drew a box in the client's font (the "game font" setting, Korean and Chinese
            -- clients), which has no such glyph (issue #391).
            if isDelivered then
                row.numText:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t")
            else
                row.numText:SetText(entry.order or dataIdx)
            end

            -- Item display
            local localName, localLink = GuildOS.Compat.GetItemInfo(entry.itemId)
            local displayText
            if localLink then
                displayText = localLink
            elseif localName then
                displayText = localName
            elseif entry.itemLink and entry.itemLink ~= "" then
                displayText = entry.itemLink
            else
                displayText = L["Item #"] .. entry.itemId
            end
            row.itemText:SetText(displayText)

            -- Dim delivered item text
            if isDelivered then
                row.itemText:SetTextColor(0.45, 0.45, 0.45)
            else
                row.itemText:SetTextColor(C.text.r, C.text.g, C.text.b)
            end

            -- The spec in the text colours, main spec first: no blue of its own (#371).
            local typeInk = entry.isOffspec and C.textSoft or C.text
            row.typeText:SetTextColor(typeInk.r, typeInk.g, typeInk.b)
            row.typeText:SetText("  " .. (entry.isOffspec and L["OS"] or L["MS"]))

            -- Show/hide action buttons based on delivered state
            for _, child in pairs({ row:GetChildren() }) do
                local childType = child:GetObjectType()
                if childType == "Button" or childType == "Frame" then
                    if isDelivered then
                        child:Hide()
                    else
                        child:Show()
                    end
                end
            end
            if fromSite then row.upBtn:Hide(); row.downBtn:Hide(); row.removeBtn:Hide() end

            row:Show()
        else
            row:Hide()
        end
    end
end

----------------------------------------------------------------------
-- OFFICER PRIO MODAL — manage item priorities (officer-only)
-- Accessible via the Wishlist panel "Gerenciar Prios" button.
----------------------------------------------------------------------
local PRIO_ROW_HEIGHT = 28
local PRIO_SITE_ROW = 40   -- the bar's extra height while the site line shows (three lines at size 9)
local PRIO_VISIBLE    = 14

local function BuildPrioModal()
    local f = CreateFrame("Frame", "GuildOSPrioModal", UIParent, "BackdropTemplate")
    f:SetSize(560, 500)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)   -- a popup's line, not gold (#371)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(60)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:Hide()

    table.insert(UISpecialFrames, "GuildOSPrioModal")

    -- Title bar
    local titleBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetPoint("TOPLEFT"); titleBg:SetPoint("TOPRIGHT"); titleBg:SetHeight(40)
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local titleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(titleText, nil, "sectionTitle")
    titleText:SetPoint("LEFT", 14, 0); titleText:SetPoint("TOP", 0, -12)
    titleText:SetTextColor(C.text.r, C.text.g, C.text.b)
    titleText:SetText(L["MANAGE PRIORITIES"])
    f.titleText = titleText

    local titleLine = UI:CreateSeparator(f)   -- a 1px line: gold is the selection's (#371)
    titleLine:SetPoint("TOPLEFT", 0, -40); titleLine:SetPoint("TOPRIGHT", 0, -40)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Subtitle: shows currently loaded item
    local subtitleText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(subtitleText, 11)
    subtitleText:SetPoint("LEFT", 14, 0); subtitleText:SetPoint("TOP", 0, -28)
    subtitleText:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.7)
    subtitleText:SetText(L["Search for an item to manage priorities"])

    -- Item search bar
    local searchBg = f:CreateTexture(nil, "BACKGROUND")
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetPoint("TOPLEFT", 1, -42); searchBg:SetPoint("TOPRIGHT", -1, -42)
    searchBg:SetHeight(36)
    searchBg:SetVertexColor(0.08, 0.08, 0.12, 1.0)

    local LoadItem  -- forward declaration

    -- The shared field and its placeholder (#371).
    local searchBox = UI:CreateInput(f, 320, 26, { max = 200, placeholder = L["Search item, paste link or ID..."] })
    searchBox:SetPoint("LEFT", 10, 0); searchBox:SetPoint("TOP", 0, -52)

    -- Search dropdown
    local PDROP_ROWS  = 6
    local PDROP_ROW_H = 22

    local prioDropdown = CreateFrame("Frame", nil, f, "BackdropTemplate")
    prioDropdown:SetWidth(320)
    prioDropdown:SetHeight(PDROP_ROWS * PDROP_ROW_H + 2)
    prioDropdown:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -2)
    prioDropdown:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(prioDropdown),
    })
    -- A dropdown is elevation 4: popup surface, lineHi border.
    prioDropdown:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    prioDropdown:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    UI:StylePopup(prioDropdown, { shadowSize = 10 })
    prioDropdown:SetFrameLevel(f:GetFrameLevel() + 20)
    prioDropdown:Hide()

    prioDropdown.rows = {}
    for i = 1, PDROP_ROWS do
        local dr = CreateFrame("Button", nil, prioDropdown)
        dr:SetHeight(PDROP_ROW_H)
        dr:SetPoint("TOPLEFT",  1, -((i - 1) * PDROP_ROW_H) - 1)
        dr:SetPoint("TOPRIGHT", -1, -((i - 1) * PDROP_ROW_H) - 1)
        dr:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        dr:GetHighlightTexture():SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
        local drText = dr:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(drText, 11)
        drText:SetPoint("LEFT", 6, 0)
        drText:SetPoint("RIGHT", -6, 0)
        drText:SetJustifyH("LEFT")
        drText:SetWordWrap(false)
        dr.label = drText
        dr:SetScript("OnClick", function()
            f.prioSearchItemId   = dr.itemId
            f.prioSearchItemName = dr.itemName
            f.suppressPrioSearch = true
            searchBox:SetText(dr.itemName or "")
            f.suppressPrioSearch = nil
            prioDropdown:Hide()
            if LoadItem then LoadItem() end
        end)
        prioDropdown.rows[i] = dr
        dr:Hide()
    end

    local function UpdatePrioDropdown(query)
        query = strlower(strtrim(query or ""))
        if query == "" or query:find("item:", 1, true) or tonumber(query) then
            prioDropdown:Hide()
            return
        end
        local results = {}
        if GuildOS.Wishlist and GuildOS.Wishlist.itemIndex then
            for itemId in pairs(GuildOS.Wishlist.itemIndex) do
                local name, _, quality = GuildOS.Wishlist:ItemFacts(itemId)
                if name and strlower(name):find(query, 1, true) then
                    tinsert(results, { itemId = itemId, name = name, quality = quality or 1 })
                end
            end
        end
        table.sort(results, function(a, b) return a.name < b.name end)
        if #results == 0 then
            prioDropdown:Hide()
            return
        end
        local shown = math.min(#results, PDROP_ROWS)
        prioDropdown:SetHeight(shown * PDROP_ROW_H + 2)
        for i = 1, PDROP_ROWS do
            local dr = prioDropdown.rows[i]
            if i <= shown then
                local entry = results[i]
                local r, g, b = GuildOS.Compat.GetItemQualityColor(entry.quality)
                dr.label:SetText(entry.name)
                UI:SetInk(dr.label, r, g, b)   -- the paper's quality ink on a card (#449)
                dr.itemId   = entry.itemId
                dr.itemName = entry.name
                dr:Show()
            else
                dr:Hide()
            end
        end
        prioDropdown:Show()
    end

    -- Hooked: the field shows and hides its own placeholder and lets go on Escape (#371).
    searchBox:HookScript("OnTextChanged", function(self)
        local t = self:GetText()
        if f.suppressPrioSearch then return end
        if f.prioSearchItemName and t == f.prioSearchItemName then return end
        f.prioSearchItemId   = nil
        f.prioSearchItemName = nil
        UpdatePrioDropdown(t)
    end)
    searchBox:HookScript("OnEscapePressed", function() prioDropdown:Hide() end)

    local loadBtn = UI:CreateButton(f, L["Load"], 90, 26)
    f.searchBox, f.loadBtn = searchBox, loadBtn
    loadBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

    -- Status line
    local statusText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(statusText, 10)
    statusText:SetPoint("LEFT", loadBtn, "RIGHT", 10, 0)
    statusText:SetWidth(120)
    statusText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    statusText:SetText("")
    f.statusText = statusText

    -- Column headers: #PRIO | NOME | WL# | ACOES, on the shared header: no band, a 1px rule (#371).
    local hdr = UI:CreateTableHeader(f)
    hdr:SetPoint("TOPLEFT", 1, -78); hdr:SetPoint("TOPRIGHT", -1, -78)

    local function PrioHdr(lbl, x, w, justify)
        local t = UI:CreateHeaderText(hdr, lbl)
        t:SetPoint("LEFT", x - 1, 0)
        t:SetWidth(w); t:SetJustifyH(justify or "LEFT")
    end
    PrioHdr(L["#PRIO"],  10,  40, "CENTER")
    PrioHdr(L["NAME"],   56, 170, "LEFT")
    PrioHdr(L["WL #"],  230,  50, "CENTER")
    PrioHdr(L["ACTIONS"], 290,  80, "CENTER")

    -- Scroll area
    local scrollCont = CreateFrame("Frame", nil, f)
    scrollCont:SetPoint("TOPLEFT",     1, -100)
    scrollCont:SetPoint("BOTTOMRIGHT", -1,  44)
    f.scrollCont = scrollCont

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSPrioScroll", scrollCont, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0); scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scrollFrame, "GuildOSPrioScroll")
    f.scrollFrame = scrollFrame

    f.rows = {}
    for i = 1, PRIO_VISIBLE do
        local row = CreateFrame("Frame", "GuildOSPrioRow" .. i, scrollCont, "BackdropTemplate")
        row:SetHeight(PRIO_ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  0, -((i - 1) * PRIO_ROW_HEIGHT))
        row:SetPoint("RIGHT", scrollCont, "RIGHT", -18, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local bgColor = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        row.defaultBg = bgColor

        -- #PRIO number
        local prioOrderText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(prioOrderText, nil, "tableNum")
        prioOrderText:SetPoint("LEFT", 10, 0); prioOrderText:SetWidth(40); prioOrderText:SetJustifyH("CENTER")
        prioOrderText:SetTextColor(C.text.r, C.text.g, C.text.b)
        row.prioOrderText = prioOrderText

        -- Character name (class-colored)
        local nameText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(nameText, 12)
        nameText:SetPoint("LEFT", 56, 0); nameText:SetWidth(170); nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- WL order
        local wlOrderText = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(wlOrderText, nil, "tableNum")
        wlOrderText:SetPoint("LEFT", 230, 0); wlOrderText:SetWidth(50); wlOrderText:SetJustifyH("CENTER")
        row.wlOrderText = wlOrderText

        -- ↑ reorder up
        local upBtn = CreateFrame("Button", nil, row)
        upBtn:SetSize(18, 18); upBtn:SetPoint("LEFT", 292, 0)
        upBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        upBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Up-Up")
        row.upBtn = upBtn

        -- ↓ reorder down
        local downBtn = CreateFrame("Button", nil, row)
        downBtn:SetSize(18, 18); downBtn:SetPoint("LEFT", 313, 0)
        downBtn:SetNormalTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        downBtn:SetHighlightTexture("Interface\\BUTTONS\\Arrow-Down-Up")
        row.downBtn = downBtn

        -- × remove
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(18, 18); removeBtn:SetPoint("LEFT", 338, 0)
        local removeTex = removeBtn:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(removeTex, 14)
        removeTex:SetPoint("CENTER")
        removeTex:SetTextColor(0.7, 0.2, 0.2)
        removeTex:SetText("x")
        removeBtn:SetScript("OnEnter", function() removeTex:SetTextColor(1, 0.3, 0.3) end)
        removeBtn:SetScript("OnLeave", function() removeTex:SetTextColor(0.7, 0.2, 0.2) end)
        row.removeBtn = removeBtn

        row:Hide()
        f.rows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PRIO_ROW_HEIGHT, function()
            GuildOS:RefreshPrioModal()
        end)
    end)

    -- Bottom bar
    local bottomBg = f:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottomBg:SetPoint("BOTTOMLEFT"); bottomBg:SetPoint("BOTTOMRIGHT"); bottomBg:SetHeight(44)
    bottomBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
    local bottomLine = UI:CreateSeparator(f)   -- a 1px line, not gold (#371)
    bottomLine:SetPoint("BOTTOMLEFT", 0, 44); bottomLine:SetPoint("BOTTOMRIGHT", 0, 44)
    f.bottomBg, f.bottomLine = bottomBg, bottomLine

    local saveBtn = UI:CreateButton(f, L["Save and Sync"], 130, 26)
    saveBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    f.saveBtn = saveBtn
    saveBtn:SetScript("OnClick", function()
        if not f.prioData or not f.currentItemId then
            f.statusText:SetText(L["|cffFF4444No item loaded.|r"])
            return
        end
        if not GuildOS.db.lootPrios then GuildOS.db.lootPrios = {} end
        local prioList = {}
        for order, entry in ipairs(f.prioData) do
            table.insert(prioList, {
                name  = entry.name,
                class = entry.class,
                order = order,
            })
        end
        GuildOS.db.lootPrios[f.currentItemId] = prioList
        if GuildOS.Wishlist then
            GuildOS.Wishlist:BroadcastLootPrios()
        end
        f.statusText:SetText(L["|cff4CFF4CSaved and sent!|r"])
        GuildOS:Print(L["[Prio] Priorities saved and synced."])
    end)

    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", saveBtn, "BOTTOMLEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
    f.cancelBtn = cancelBtn

    -- Help text in bottom bar
    local bottomHelp = UI:CreateText(f, L["Reorder with the arrows. Only you see this before saving."], 9, 0.4, 0.4, 0.5)
    bottomHelp:SetPoint("BOTTOMLEFT", 10, 14)
    f.bottomHelp = bottomHelp

    -- Some core's nights play by the site's priorities: the modal still edits the game's (R22, #385), and
    -- this line, in the help's place, says that those nights use the site's, beside "Edit on the site".
    local siteBtn = UI:CreateButton(f, L["Edit on the site"], 130, 26)
    siteBtn:SetPoint("BOTTOMRIGHT", cancelBtn, "BOTTOMLEFT", -8, 0)
    siteBtn:SetScript("OnClick", function() GuildOS:ShowExportPopup(L["Edit on the site"], SITE_URL) end)
    siteBtn:Hide()
    f.siteBtn = siteBtn
    local siteLine = UI:CreateText(f, L["Nights of cores whose priorities live on the site use the site's."], 9,
        C.textSoft.r, C.textSoft.g, C.textSoft.b)
    -- Its own row above the buttons, across the modal's width, with room for three wrapped lines (the German,
    -- French and Russian texts are long): ApplyPrioSource grows the bar by PRIO_SITE_ROW while it shows.
    siteLine:SetPoint("BOTTOMLEFT", 10, 48)
    siteLine:SetPoint("BOTTOMRIGHT", -10, 48)
    siteLine:SetHeight(PRIO_SITE_ROW - 6)
    siteLine:SetJustifyH("LEFT")
    siteLine:SetJustifyV("MIDDLE")
    siteLine:SetWordWrap(true)
    siteLine:Hide()
    f.siteLine = siteLine

    -- Wire up LoadItem
    LoadItem = function()
        local itemId = f.prioSearchItemId
        f.prioSearchItemId = nil
        if not itemId then
            local text = strtrim(searchBox:GetText() or "")
            if text == "" then return end
            itemId = tonumber(text:match("item:(%d+)")) or tonumber(text)
        end
        if not itemId then
            f.statusText:SetText(L["|cffFF4444Invalid item.|r"])
            return
        end

        f.currentItemId = itemId
        f.prioData = {}

        -- Collect who has this item on their wishlist
        local wishEntries = {}
        if GuildOS.db.guildWishlists then
            for _, charData in pairs(GuildOS.db.guildWishlists) do
                for _, wItem in ipairs(charData.wishlist or {}) do
                    if wItem.itemId == itemId then
                        table.insert(wishEntries, {
                            name         = charData.name or "",
                            class        = charData.class or "",
                            wishlistOrder = wItem.order or 999,
                        })
                        break
                    end
                end
            end
        end

        -- Start from saved prios (if any), then append remaining wishlist members
        local savedPrios = GuildOS.db.lootPrios and GuildOS.db.lootPrios[itemId]
        if savedPrios and #savedPrios > 0 then
            local inPrio = {}
            for _, pEntry in ipairs(savedPrios) do
                local wlOrd = 999
                for _, we in ipairs(wishEntries) do
                    if strlower(we.name) == strlower(pEntry.name or "") then
                        wlOrd = we.wishlistOrder
                        break
                    end
                end
                table.insert(f.prioData, {
                    name         = pEntry.name or "",
                    class        = pEntry.class or "",
                    wishlistOrder = wlOrd,
                })
                inPrio[strlower(pEntry.name or "")] = true
            end
            table.sort(wishEntries, function(a, b) return a.wishlistOrder < b.wishlistOrder end)
            for _, we in ipairs(wishEntries) do
                if not inPrio[strlower(we.name)] then
                    table.insert(f.prioData, we)
                end
            end
        else
            table.sort(wishEntries, function(a, b) return a.wishlistOrder < b.wishlistOrder end)
            f.prioData = wishEntries
        end

        local itemName = GuildOS.Compat.GetItemInfo(itemId) or (L["Item #"] .. itemId)
        f.statusText:SetText(itemName .. "  " .. format(L["%d interested"], #f.prioData))
        subtitleText:SetText(itemName)
        GuildOS:RefreshPrioModal()
    end

    loadBtn:SetScript("OnClick", function()
        prioDropdown:Hide()
        LoadItem()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        prioDropdown:Hide()
        LoadItem()
        self:ClearFocus()
    end)

    GuildOS.PrioModal = f
    return f
end

function GuildOS:ShowPrioModal()
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Only officers can manage priorities.|r"])
        return
    end
    if not self.PrioModal then BuildPrioModal() end
    self:ApplyPrioSource()
    self:RefreshPrioModal()
    self.PrioModal:Show()
end

-- The modal always edits the game's priorities (R22, #385). While some raid of the site's plays by the site's
-- priorities, one line in the help's place says that those nights use the site's, with "Edit on the site".
function GuildOS:ApplyPrioSource()
    local f = self.PrioModal
    if not f then return end
    local fromSite = GuildOS.Wishlist:PriosAreFromSite()
    if fromSite then
        f.bottomHelp:Hide(); f.siteLine:Show(); f.siteBtn:Show()
    else
        f.bottomHelp:Show(); f.siteLine:Hide(); f.siteBtn:Hide()
    end
    -- The site line takes a row of its own above the buttons: the bar, its rule and the list's bottom follow.
    local bar = 44 + (fromSite and PRIO_SITE_ROW or 0)
    f.bottomBg:SetHeight(bar)
    f.bottomLine:SetPoint("BOTTOMLEFT", 0, bar); f.bottomLine:SetPoint("BOTTOMRIGHT", 0, bar)
    f.scrollCont:SetPoint("BOTTOMRIGHT", -1, bar)
end

function GuildOS:RefreshPrioModal()
    local f = self.PrioModal
    if not f or not f.prioData then return end

    self:ApplyPrioSource()
    local data   = f.prioData
    local total  = #data
    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)
    FauxScrollFrame_Update(f.scrollFrame, total, PRIO_VISIBLE, PRIO_ROW_HEIGHT)

    for i = 1, PRIO_VISIBLE do
        local row     = f.rows[i]
        local dataIdx = offset + i

        if dataIdx <= total then
            local entry = data[dataIdx]
            local bgColor = (i % 2 == 0) and C.row2 or C.row1
            row.defaultBg = bgColor
            row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

            -- Prio position number
            row.prioOrderText:SetText("#" .. dataIdx)

            -- Character name (class-colored)
            local cr, cg, cb = GuildOS:GetClassColor(entry.class or "")
            row.nameText:SetText(entry.name or "?")
            UI:SetInk(row.nameText, cr, cg, cb)

            -- Wishlist order
            if entry.wishlistOrder and entry.wishlistOrder < 999 then
                row.wlOrderText:SetText("#" .. entry.wishlistOrder)
                row.wlOrderText:SetTextColor(0.3, 0.7, 1.0)
            else
                row.wlOrderText:SetText("-")
                row.wlOrderText:SetTextColor(0.4, 0.4, 0.4)
            end

            -- Wire ↑/↓
            row.upBtn:SetScript("OnClick", function()
                if dataIdx > 1 then
                    data[dataIdx], data[dataIdx - 1] = data[dataIdx - 1], data[dataIdx]
                    GuildOS:RefreshPrioModal()
                end
            end)
            row.downBtn:SetScript("OnClick", function()
                if dataIdx < total then
                    data[dataIdx], data[dataIdx + 1] = data[dataIdx + 1], data[dataIdx]
                    GuildOS:RefreshPrioModal()
                end
            end)

            -- Remove
            row.removeBtn:SetScript("OnClick", function()
                table.remove(data, dataIdx)
                GuildOS:RefreshPrioModal()
            end)

            row:Show()
        else
            row:Hide()
        end
    end
end
