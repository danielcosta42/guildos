----------------------------------------------------------------------
-- Guild OS - LFG Board
-- Members mark themselves available for a group (role + note + TTL).
-- Everyone sees a live board. An entry is always keyed by the comm
-- envelope sender, so nobody can publish availability for someone else.
----------------------------------------------------------------------
local LFGBoard = {}
BRutus.LFGBoard = LFGBoard
local L = BRutus.L
local LibSerialize = LibStub("LibSerialize")

local DEFAULT_TTL = 5400   -- 90 minutes
local NOTE_MAX    = 60

LFGBoard.DEFAULTS = { notify = false, lastRole = "ANY", lastNote = "", lastTtl = DEFAULT_TTL }
LFGBoard.ROLES    = { "ANY", "TANK", "HEALER", "DPS" }

function LFGBoard:Initialize()
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    BRutus.db.lfgPrefs = BRutus.db.lfgPrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.lfgPrefs[k] == nil then BRutus.db.lfgPrefs[k] = v end
    end
    self:Prune()
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------------
function LFGBoard:_IsActive(entry, now)
    if not entry or not entry.ts then return false end
    return (entry.ts + (entry.ttl or DEFAULT_TTL)) > (now or 0)
end

function LFGBoard:_Remaining(entry, now)
    if not self:_IsActive(entry, now) then return 0 end
    return math.floor(((entry.ts + (entry.ttl or DEFAULT_TTL)) - (now or 0)) / 60)
end

-- onlineSet (optional): { [key] = true } of members currently online.
function LFGBoard:ActiveList(store, now, onlineSet)
    local out = {}
    for key, e in pairs(store or {}) do
        if self:_IsActive(e, now) and (not onlineSet or onlineSet[key]) then
            out[#out + 1] = {
                key = key, name = key:match("^([^-]+)") or key,
                role = e.role or "ANY", note = e.note or "", ts = e.ts, ttl = e.ttl,
            }
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

function LFGBoard:Prune(now, store)
    store = store or BRutus.db.lfgBoard
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for k, e in pairs(store) do
        if not self:_IsActive(e, now) then store[k] = nil; removed = removed + 1 end
    end
    return removed
end

-- Whitelist an incoming role against the known set. Anything that is not a
-- string, or not one of LFGBoard.ROLES (a forged length, a color/texture
-- escape sequence, a number/boolean/table that survived LibSerialize), falls
-- back to "ANY". Shared by HandleEntry and the self test so the rule cannot
-- drift between production and the test that pins it.
function LFGBoard:_SanitizeRole(role)
    return (type(role) == "string" and tContains(self.ROLES, role) and role) or "ANY"
end

----------------------------------------------------------------------
-- Self declare (publishes only your OWN entry)
----------------------------------------------------------------------
local function myKey()
    return BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
end

function LFGBoard:SetAvailable(role, note, ttl)
    note = (note or ""):sub(1, NOTE_MAX)
    ttl = ttl or BRutus.db.lfgPrefs.lastTtl or DEFAULT_TTL
    role = role or BRutus.db.lfgPrefs.lastRole or "ANY"
    local entry = { role = role, note = note, ts = GetServerTime(), ttl = ttl }
    BRutus.db.lfgBoard[myKey()] = entry
    BRutus.db.lfgPrefs.lastRole, BRutus.db.lfgPrefs.lastNote, BRutus.db.lfgPrefs.lastTtl = role, note, ttl
    if BRutus.CommSystem then
        BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ role = role, note = note, ttl = ttl }))
    end
    self:Refresh()
end

function LFGBoard:ClearAvailable()
    BRutus.db.lfgBoard[myKey()] = nil
    if BRutus.CommSystem then
        BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ clear = true }))
    end
    self:Refresh()
end

function LFGBoard:AmAvailable()
    return self:_IsActive(BRutus.db.lfgBoard[myKey()], GetServerTime())
end

-- Incoming: the key ALWAYS comes from the envelope sender, never the payload.
function LFGBoard:HandleEntry(sender, data)
    if not sender then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(short, realm)
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    if p.clear then
        BRutus.db.lfgBoard[key] = nil
    else
        local wasActive = self:_IsActive(BRutus.db.lfgBoard[key], GetServerTime())
        BRutus.db.lfgBoard[key] = {
            role = self:_SanitizeRole(p.role),
            note = tostring(p.note or ""):sub(1, NOTE_MAX),
            ts = GetServerTime(),
            ttl = tonumber(p.ttl) or DEFAULT_TTL,
        }
        if not wasActive and BRutus.db.lfgPrefs.notify and key ~= myKey() then
            BRutus:Print(string.format(L["%s is available: %s"], short,
                (p.note ~= "" and p.note) or L["(no note)"]))
        end
    end
    self:Refresh()
end

function LFGBoard:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI (self-contained popup -- mirrors Modules/GuildAnalytics.lua:Show())
----------------------------------------------------------------------
local ROW_HEIGHT = 22
local DURATIONS  = { 1800, 3600, 5400, 7200 }   -- 30m / 60m / 90m / 120m

local function roleDisplay(role)
    if role == "TANK" then return L["Tank"] end
    if role == "HEALER" then return L["Healer"] end
    if role == "DPS" then return L["DPS"] end
    return L["Any"]
end

local function durationDisplay(seconds)
    return string.format(L["%dm"], math.floor((seconds or 0) / 60))
end

-- Online guild roster snapshot for the board's online-only filter: an
-- { [key] = true } set plus a { [key] = classFile } lookup for row colors.
-- Keys are normalized exactly like HandleEntry (short name + realm through
-- BRutus:GetPlayerKey) -- the recurring key-form gotcha in this codebase.
function LFGBoard:_BuildOnlineRoster()
    local onlineSet, classByKey = {}, {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            onlineSet[key] = true
            classByKey[key] = classFile
        end
    end
    return onlineSet, classByKey
end

-- A small button that cycles through `values` on click, painting itself
-- via labelFn(value). Starts on initValue (falls back to the first entry
-- when initValue isn't found, e.g. a stale pref).
local function makeCycleButton(parent, width, values, labelFn, initValue)
    local btn = BRutus.UI:CreateButton(parent, "", width, 22)
    local idx = 1
    for i, v in ipairs(values) do if v == initValue then idx = i end end
    local function paint() btn.label:SetText(labelFn(values[idx])) end
    paint()
    btn:SetScript("OnClick", function()
        idx = (idx % #values) + 1
        paint()
    end)
    function btn:GetValue() return values[idx] end
    return btn
end

function LFGBoard:Show()
    local UI = BRutus.UI
    local C = BRutus.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSLFGBoardFrame", UIParent, "BackdropTemplate")
        f:SetSize(560, 460)
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

        local title = UI:CreateTitle(f, L["LFG Board"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        ------------------------------------------------------------
        -- Row 1: You: Role [ Any ]   Looking for [ .............. ]
        -- All row anchors are fixed pixel offsets straight off `f`
        -- (not chained sibling-to-sibling), so row 1 and row 2 line
        -- up under each other regardless of localized label widths.
        ------------------------------------------------------------
        local youLbl = UI:CreateText(f, L["You:"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        youLbl:SetPoint("TOPLEFT", 16, -47)

        local roleLbl = UI:CreateText(f, L["Role"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        roleLbl:SetPoint("TOPLEFT", 60, -47)

        local roleBtn = makeCycleButton(f, 90, LFGBoard.ROLES, roleDisplay, BRutus.db.lfgPrefs.lastRole)
        roleBtn:SetPoint("TOPLEFT", 94, -45)
        f.roleBtn = roleBtn

        local noteLbl = UI:CreateText(f, L["Looking for"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        noteLbl:SetPoint("TOPLEFT", 196, -47)

        local noteBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        noteBox:SetHeight(20)
        noteBox:SetPoint("TOPLEFT", 272, -46)
        noteBox:SetPoint("TOPRIGHT", -16, -46)
        noteBox:SetAutoFocus(false)
        noteBox:SetMaxLetters(NOTE_MAX)
        noteBox:SetText(BRutus.db.lfgPrefs.lastNote or "")
        noteBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        f.noteBox = noteBox

        ------------------------------------------------------------
        -- Row 2: Duration [ 90m ]                 [ I'm available ]
        ------------------------------------------------------------
        local durLbl = UI:CreateText(f, L["Duration"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
        durLbl:SetPoint("TOPLEFT", 60, -79)

        local durationBtn = makeCycleButton(f, 90, DURATIONS, durationDisplay, BRutus.db.lfgPrefs.lastTtl)
        durationBtn:SetPoint("TOPLEFT", 94, -77)
        f.durationBtn = durationBtn

        local actionBtn = UI:CreateButton(f, L["I'm available"], 150, 24)
        actionBtn:SetPoint("TOPRIGHT", -16, -77)
        actionBtn:SetScript("OnClick", function()
            if LFGBoard:AmAvailable() then
                LFGBoard:ClearAvailable()
            else
                LFGBoard:SetAvailable(roleBtn:GetValue(), noteBox:GetText(), durationBtn:GetValue())
            end
        end)
        f.actionBtn = actionBtn

        ------------------------------------------------------------
        -- Separator, right-aligned count, column header.
        ------------------------------------------------------------
        local sep = UI:CreateSeparator(f)
        sep:SetPoint("TOPLEFT", 12, -106)
        sep:SetPoint("TOPRIGHT", -12, -106)

        local countText = UI:CreateText(f, "", 11, C.silver.r, C.silver.g, C.silver.b)
        countText:SetPoint("TOPRIGHT", -16, -114)
        f.countText = countText

        local hPlayer = UI:CreateText(f, L["PLAYER"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hPlayer:SetPoint("TOPLEFT", 16, -132)
        local hRole = UI:CreateText(f, L["ROLE"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hRole:SetPoint("TOPLEFT", 180, -132)
        local hFor = UI:CreateText(f, L["FOR"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hFor:SetPoint("TOPLEFT", 250, -132)
        local hNote = UI:CreateText(f, L["LOOKING FOR"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
        hNote:SetPoint("TOPLEFT", 310, -132)

        ------------------------------------------------------------
        -- Scroll list -- fills all remaining space below the column
        -- header. ScrollFrame gotcha: CreateScrollFrame does NOT
        -- anchor the scroll frame itself -- SetAllPoints() here, or
        -- content is clipped to 0x0. Holder starts at -150, well
        -- clear of the column header text painted at -132 (10pt,
        -- ~13px tall -> bottom edge around -145).
        ------------------------------------------------------------
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, -150)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSLFGBoardScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end
        self:Prune()

        local amAvailable = self:AmAvailable()
        f.actionBtn.label:SetText(amAvailable and L["Stop"] or L["I'm available"])
        if amAvailable then
            f.actionBtn:SetBaseColor(C.red.r * 0.30, C.red.g * 0.16, C.red.b * 0.16, 0.92)
        else
            f.actionBtn:SetBaseColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.92)
        end

        local onlineSet, classByKey = self:_BuildOnlineRoster()
        local now = GetServerTime()
        local list = self:ActiveList(BRutus.db.lfgBoard, now, onlineSet)
        f.countText:SetText(string.format(L["%d available"], #list))

        -- Reset ALL row state before repaint (children and regions),
        -- the pattern every list in this addon uses.
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local myKeyVal = BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
        local y = 0
        for _, entry in ipairs(list) do
            local isMe = (entry.key == myKeyVal)
            local classFile = classByKey[entry.key]
            local cc = (classFile and RAID_CLASS_COLORS[classFile]) or C.text

            local nameBtn = CreateFrame("Button", nil, child)
            nameBtn:SetPoint("TOPLEFT", 4, -(y + 2))
            nameBtn:SetSize(158, ROW_HEIGHT - 4)
            local nameFS = UI:CreateText(nameBtn, entry.name, 11, cc.r, cc.g, cc.b)
            nameFS:SetPoint("LEFT", 0, 0)
            nameFS:SetWidth(150)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            if not isMe then
                nameBtn:EnableMouse(true)
                nameBtn:SetScript("OnClick", function() ChatFrame_SendTell(entry.name) end)
                nameBtn:SetScript("OnEnter", function() nameFS:SetTextColor(C.gold.r, C.gold.g, C.gold.b) end)
                nameBtn:SetScript("OnLeave", function() nameFS:SetTextColor(cc.r, cc.g, cc.b) end)
            end

            local roleFS = UI:CreateText(child, roleDisplay(entry.role), 11, C.text.r, C.text.g, C.text.b)
            roleFS:SetPoint("TOPLEFT", 168, -(y + 4))
            roleFS:SetWidth(64)
            roleFS:SetJustifyH("LEFT")
            roleFS:SetWordWrap(false)

            local forFS = UI:CreateText(child, string.format(L["%dm"], self:_Remaining(entry, now)), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            forFS:SetPoint("TOPLEFT", 238, -(y + 4))
            forFS:SetWidth(54)
            forFS:SetJustifyH("LEFT")
            forFS:SetWordWrap(false)

            if isMe then
                local youFS = UI:CreateText(child, L["(you)"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
                youFS:SetPoint("TOPRIGHT", -8, -(y + 4))
            else
                local inviteBtn = UI:CreateButton(child, L["Invite"], 56, 18)
                inviteBtn:SetPoint("TOPRIGHT", -4, -(y + 2))
                inviteBtn:SetScript("OnClick", function() InviteUnit(entry.name) end)
            end

            local noteFS = UI:CreateText(child, entry.note or "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
            noteFS:SetPoint("TOPLEFT", 298, -(y + 4))
            noteFS:SetWidth(math.max(10, child:GetWidth() - 298 - 66))
            noteFS:SetJustifyH("LEFT")
            noteFS:SetWordWrap(false)

            y = y + ROW_HEIGHT
        end

        if #list == 0 then
            local empty = UI:CreateText(child, L["Nobody is available right now. Be the first!"], 11,
                C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
            y = 20
        end

        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end

----------------------------------------------------------------------
-- Self tests
----------------------------------------------------------------------
function LFGBoard:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("lfg.active", function()
        if not LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 130) then return false, "should be active" end
        if LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 200) then return false, "should be expired" end
        return true
    end)
    S:Register("lfg.remaining", function()
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 300) ~= 5 then return false, "5 min left" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 999) ~= 0 then return false, "expired => 0" end
        return true
    end)
    S:Register("lfg.activelist_sorted_and_filtered", function()
        local store = {
            ["A-R"] = { ts = 100, ttl = 600, note = "a" },
            ["B-R"] = { ts = 200, ttl = 600, note = "b" },
            ["C-R"] = { ts = 1,   ttl = 5,   note = "expired" },
        }
        local out = LFGBoard:ActiveList(store, 300)
        if #out ~= 2 or out[1].key ~= "B-R" then return false, "newest first, expired dropped" end
        local only = LFGBoard:ActiveList(store, 300, { ["A-R"] = true })
        if #only ~= 1 or only[1].key ~= "A-R" then return false, "online filter" end
        return true
    end)
    S:Register("lfg.prune", function()
        local store = { ["X-R"] = { ts = 1, ttl = 5 }, ["Y-R"] = { ts = 100, ttl = 600 } }
        local n = LFGBoard:Prune(300, store)
        if n ~= 1 or store["X-R"] ~= nil or store["Y-R"] == nil then return false, "prune" end
        return true
    end)
    S:Register("lfg.role_whitelist", function()
        if LFGBoard:_SanitizeRole("TANK") ~= "TANK" then return false, "valid role kept" end
        if LFGBoard:_SanitizeRole("|cffff0000EVIL|r") ~= "ANY" then return false, "escape string rejected" end
        if LFGBoard:_SanitizeRole(42) ~= "ANY" then return false, "non string rejected" end
        if LFGBoard:_SanitizeRole(nil) ~= "ANY" then return false, "nil defaults" end
        return true
    end)
end
