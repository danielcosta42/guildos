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
local TTL_MIN     = 1800   -- 30 minutes, the shortest duration the UI offers
local TTL_MAX     = 7200   -- 120 minutes, the longest duration the UI offers
local NOTE_MAX    = 60
local ENTRY_COOLDOWN = 5   -- accept at most one entry per sender per 5s

LFGBoard.DEFAULTS = { notify = false, lastRole = "ANY", lastNote = "", lastTtl = DEFAULT_TTL }
LFGBoard.ROLES    = { "ANY", "TANK", "HEALER", "DPS" }

function LFGBoard:Initialize()
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    BRutus.db.lfgPrefs = BRutus.db.lfgPrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.lfgPrefs[k] == nil then BRutus.db.lfgPrefs[k] = v end
    end
    self._cd = self._cd or {}
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

-- Minutes left on an entry, as shown in the board's FOR column. Rounds UP so
-- an entry that is still active never renders "0m": flooring made the last 59
-- seconds of every listing read as expired while the row was still on screen.
-- An inactive entry is still 0 (the row is gone by then anyway).
function LFGBoard:_Remaining(entry, now)
    if not self:_IsActive(entry, now) then return 0 end
    return math.max(1, math.ceil(((entry.ts + (entry.ttl or DEFAULT_TTL)) - (now or 0)) / 60))
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
    -- Newest first, then by key. Without the key tie-break two members who
    -- posted in the same second fall back to pairs() order, so the rows swap
    -- places on every repaint and an Invite click can land on a row that just
    -- moved. Keys are table keys, so they are unique and the order is total.
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return a.key < b.key
    end)
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

-- Clamp a lifetime to the range the UI actually offers (30m to 120m). An
-- unclamped ttl is a permanent entry: ttl = 1e12 keeps _IsActive true forever,
-- so Prune can never drop it and it survives in SavedVariables long after the
-- sender left the guild. Applied on BOTH the local post path and the receive
-- path so the two can never disagree. Anything unparseable (nil, a table, a
-- string, NaN) falls back to the default.
function LFGBoard:_ClampTtl(ttl)
    local n = tonumber(ttl)
    if not n or n ~= n then return DEFAULT_TTL end   -- nil / not a number / NaN
    if n < TTL_MIN then return TTL_MIN end
    if n > TTL_MAX then return TTL_MAX end
    return math.floor(n)
end

-- Turns a received payload into the entry we store, plus the age it claimed.
-- Pure (injectable `now`) so the self test can pin it without comm state.
--
-- `age` is how many seconds ago the sender originally posted. A fresh post
-- omits it (age 0, ts = now, exactly the old behavior); a Rebroadcast sends
-- the real elapsed time so the entry keeps its ORIGINAL deadline instead of
-- restarting the clock on every relog. Age is clamped to [0, ttl]: it can
-- only ever move ts backwards, never into the future, so the entry always
-- expires at or before now + clamped ttl and cannot be stretched.
function LFGBoard:_BuildEntry(p, now)
    now = now or 0
    local ttl = self:_ClampTtl(p and p.ttl)
    local age = tonumber(p and p.age) or 0
    if age ~= age or age < 0 then age = 0 end
    if age > ttl then age = ttl end
    return {
        role = self:_SanitizeRole(p and p.role),
        note = BRutus:SanitizeUserText(p and p.note, NOTE_MAX),
        ts = now - age,
        ttl = ttl,
    }, age
end

-- Per-sender cooldown for incoming entries. Every accepted entry repaints the
-- board, and a repaint allocates a fresh Button per row (WoW never frees
-- frames), so an unthrottled peer looping LFG messages leaks frames in every
-- viewer's session. Returns true when the message must be dropped silently.
-- Same self-clearing _cd table pattern as Modules/NoteCommand.lua, so the
-- table can never grow past the senders currently on cooldown.
-- store/schedule are injectable for the self test; production passes neither.
function LFGBoard:_RateLimited(sender, store, schedule)
    if not sender then return true end
    store = store or self._cd
    if not store then
        self._cd = {}
        store = self._cd
    end
    if store[sender] then return true end
    store[sender] = true
    local after = schedule or BRutus.Compat.After
    after(ENTRY_COOLDOWN, function() store[sender] = nil end)
    return false
end

-- Default role for a fresh Role cycle button. The player's own last pick
-- wins whenever it is anything other than the untouched default "ANY". If
-- it is still "ANY", fall back to their self-service raid role profile
-- (BRutus:GetMyRoles(), a { [ROLE] = true } set, see Core/Core.lua) but
-- ONLY when exactly one role is configured there -- with two or more (or
-- zero) we cannot guess which one they mean for this LFG post, so it stays
-- "ANY". Always sanitized on the way out, so this can never return a value
-- outside LFGBoard.ROLES.
-- rolesOverride / lastRoleOverride are injectable so the self test can pin
-- every branch without touching live db/profile state; production calls
-- this with no arguments.
function LFGBoard:_DefaultRole(rolesOverride, lastRoleOverride)
    local lastRole = lastRoleOverride or (BRutus.db.lfgPrefs and BRutus.db.lfgPrefs.lastRole) or "ANY"
    if lastRole ~= "ANY" then return self:_SanitizeRole(lastRole) end

    local roles = rolesOverride
    if roles == nil and BRutus.GetMyRoles then roles = BRutus:GetMyRoles() end
    roles = roles or {}

    local only
    for role, on in pairs(roles) do
        if on then
            if only then return "ANY" end -- more than one role configured, don't guess
            only = role
        end
    end
    return self:_SanitizeRole(only)
end

----------------------------------------------------------------------
-- Self declare (publishes only your OWN entry)
----------------------------------------------------------------------
local function myKey()
    return BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
end

-- Returns the stored entry so callers print exactly what was published
-- (sanitized note, clamped ttl) instead of what they passed in.
function LFGBoard:SetAvailable(role, note, ttl)
    note = BRutus:SanitizeUserText(note, NOTE_MAX)
    ttl = self:_ClampTtl(ttl or BRutus.db.lfgPrefs.lastTtl or DEFAULT_TTL)
    role = self:_SanitizeRole(role or BRutus.db.lfgPrefs.lastRole or "ANY")
    local entry = { role = role, note = note, ts = GetServerTime(), ttl = ttl }
    BRutus.db.lfgBoard[myKey()] = entry
    BRutus.db.lfgPrefs.lastRole, BRutus.db.lfgPrefs.lastNote, BRutus.db.lfgPrefs.lastTtl = role, note, ttl
    if BRutus.CommSystem then
        BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ role = role, note = note, ttl = ttl }))
    end
    self:Refresh()
    return entry
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
    local store = BRutus.db and BRutus.db.lfgBoard
    return self:_IsActive(store and store[myKey()], GetServerTime())
end

-- Re-publish our own live entry. Availability was only ever sent once, so a
-- guildmate who logged in after the post saw an empty board until we posted
-- again. CommSystem:HandleRequest calls this, which is the pull every other
-- synced domain already answers on. The original deadline is carried across
-- as `age` (seconds since the post) rather than as a timestamp, so answering
-- requests or relogging can never extend the listing.
function LFGBoard:Rebroadcast()
    if not BRutus.CommSystem then return false end
    local store = BRutus.db and BRutus.db.lfgBoard
    local entry = store and store[myKey()]
    local now = GetServerTime()
    if not self:_IsActive(entry, now) then return false end
    local age = now - entry.ts
    if age < 0 then age = 0 end
    BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
        LibSerialize:Serialize({ role = entry.role, note = entry.note, ttl = entry.ttl, age = age }))
    return true
end

-- Incoming: the key ALWAYS comes from the envelope sender, never the payload.
function LFGBoard:HandleEntry(sender, data)
    if not sender then return end
    -- Cooldown first, before the deserialize and before any repaint, so a
    -- flooding peer costs us nothing. Keyed on the short name so "Bob" and
    -- "Bob-Realm" share one bucket.
    if self:_RateLimited(sender:match("^([^-]+)") or sender) then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(short, realm)
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    if p.clear then
        BRutus.db.lfgBoard[key] = nil
    else
        local now = GetServerTime()
        local wasActive = self:_IsActive(BRutus.db.lfgBoard[key], now)
        local entry, age = self:_BuildEntry(p, now)
        BRutus.db.lfgBoard[key] = entry
        -- Print the SANITIZED note, never the raw payload: string.format("%s")
        -- does not call tostring in Lua 5.1, so a peer sending a boolean or a
        -- table would raise inside this (unprotected) CHAT_MSG_ADDON handler,
        -- and an oversized note would bypass the cap and flood the chat frame.
        -- age > 0 means this is a rebroadcast of an older post, not news.
        local prefs = BRutus.db.lfgPrefs
        if age == 0 and not wasActive and prefs and prefs.notify and key ~= myKey() then
            BRutus:Print(string.format(L["%s is available: %s"], short,
                (entry.note ~= "" and entry.note) or L["(no note)"]))
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
-- 30m / 60m / 90m / 120m. The ends are the same constants _ClampTtl enforces,
-- so the offered range and the accepted range cannot drift apart.
local DURATIONS  = { TTL_MIN, 3600, DEFAULT_TTL, TTL_MAX }

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

        local roleBtn = makeCycleButton(f, 90, LFGBoard.ROLES, roleDisplay, self:_DefaultRole())
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

        local myKeyVal = myKey()
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
-- Chat command: /gos avail [off | notify [on|off] | [role] <text>]
----------------------------------------------------------------------

-- Role tokens accepted as an optional LEADING word of "/gos avail ...".
-- Lowercased on the way in, mapped to the canonical LFGBoard.ROLES spelling.
local ROLE_TOKENS = { tank = "TANK", healer = "HEALER", dps = "DPS", any = "ANY" }

-- Pure: turns the /gos avail argument list into an action plus its data.
-- Reads no db, sends no comm, touches no frame, so the self test can pin
-- every branch. Inputs:
--   args         token array built from rest
--   rest         raw remainder, internal spacing intact
--   defaultRole  role to use when no leading role token is given. The caller
--                passes self:_DefaultRole(); nil sanitizes to "ANY".
-- Returns action, role, note, value:
--   "show"                      -> open the board
--   "clear"                     -> stop being available
--   "notify", nil, nil, value   -> value true/false sets it, nil = report only
--   "set", role, note           -> post availability (note already capped)
function LFGBoard:_ParseAvailArgs(args, rest, defaultRole)
    args = args or {}
    rest = strtrim(rest or "")
    local first = args[1] and args[1]:lower()
    if not first or first == "" then return "show" end
    -- Delisting only when the token stands alone, otherwise "/gos avail stop
    -- by if you need a healer" would delist instead of post. notify keeps
    -- taking its on/off value.
    if (first == "off" or first == "stop") and #args == 1 then return "clear" end
    if first == "notify" then
        local v = args[2] and args[2]:lower()
        if v == "on" then return "notify", nil, nil, true end
        if v == "off" then return "notify", nil, nil, false end
        return "notify"
    end
    -- Only a leading token counts as a role, so "need 2 dps" stays all note.
    local role, note = ROLE_TOKENS[first], rest
    if role then note = strtrim(rest:match("^%S+%s*(.*)$") or "") end
    return "set", self:_SanitizeRole(role or defaultRole), BRutus:SanitizeUserText(note, NOTE_MAX)
end

function LFGBoard:HandleCommand(args, rest)
    local prefs = BRutus.db and BRutus.db.lfgPrefs
    if not prefs then return end
    local action, role, note, value = self:_ParseAvailArgs(args, rest, self:_DefaultRole())
    if action == "clear" then
        self:ClearAvailable()
        BRutus:Print(L["You are no longer listed as available."])
    elseif action == "notify" then
        if value ~= nil then prefs.notify = value end
        BRutus:Print(prefs.notify and L["LFG notify |cff4CFF4Con|r."] or L["LFG notify |cffFF4444off|r."])
    elseif action == "set" then
        -- Print the stored entry, so the confirmation shows the sanitized note
        -- and the clamped duration that guildmates will actually see.
        local entry = self:SetAvailable(role, note, prefs.lastTtl or DEFAULT_TTL)
        BRutus:Print(string.format(L["You are available as %s for %s: %s"],
            roleDisplay(entry.role), durationDisplay(entry.ttl),
            (entry.note ~= "" and entry.note) or L["(no note)"]))
    else
        self:Show()
    end
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
        -- Rounds up: a part minute is still time on the board.
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 305) ~= 5 then return false, "part minute rounds up" end
        -- The old floor made the last 59 seconds of every listing render "0m".
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 541) ~= 1 then return false, "sub minute => 1m" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 599) ~= 1 then return false, "last second => 1m" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 999) ~= 0 then return false, "expired => 0" end
        return true
    end)
    S:Register("lfg.ttl_clamp", function()
        if LFGBoard:_ClampTtl(3600) ~= 3600 then return false, "in range kept" end
        if LFGBoard:_ClampTtl(TTL_MIN) ~= TTL_MIN then return false, "lower bound kept" end
        if LFGBoard:_ClampTtl(TTL_MAX) ~= TTL_MAX then return false, "upper bound kept" end
        if LFGBoard:_ClampTtl(1e12) ~= TTL_MAX then return false, "forged huge ttl clamped" end
        if LFGBoard:_ClampTtl(0) ~= TTL_MIN then return false, "zero clamped up" end
        if LFGBoard:_ClampTtl(-1) ~= TTL_MIN then return false, "negative clamped up" end
        if LFGBoard:_ClampTtl("nope") ~= DEFAULT_TTL then return false, "garbage defaults" end
        if LFGBoard:_ClampTtl(nil) ~= DEFAULT_TTL then return false, "nil defaults" end
        if LFGBoard:_ClampTtl({}) ~= DEFAULT_TTL then return false, "table defaults" end
        -- The clamp is what keeps Prune able to do its job: without it a forged
        -- ttl pins the entry on the board (and in SavedVariables) forever.
        local e = LFGBoard:_BuildEntry({ ttl = 1e12 }, 100)
        if LFGBoard:_IsActive(e, 100 + TTL_MAX) then return false, "entry must still expire" end
        return true
    end)
    S:Register("lfg.entry_age", function()
        local fresh, freshAge = LFGBoard:_BuildEntry({ role = "TANK", note = "heroic", ttl = 3600 }, 1000)
        if fresh.ts ~= 1000 or fresh.ttl ~= 3600 or freshAge ~= 0 then return false, "fresh post starts now" end
        -- A rebroadcast keeps its original deadline instead of restarting it.
        local old, age = LFGBoard:_BuildEntry({ ttl = 3600, age = 600 }, 1000)
        if old.ts ~= 400 or age ~= 600 then return false, "rebroadcast keeps its deadline" end
        -- Age only ever moves ts backwards, so relogging cannot stretch a listing.
        local far = LFGBoard:_BuildEntry({ ttl = 3600, age = 99999 }, 1000)
        if far.ts ~= (1000 - 3600) then return false, "age capped at ttl" end
        if LFGBoard:_IsActive(far, 1000) then return false, "over aged entry is dead on arrival" end
        local future = LFGBoard:_BuildEntry({ ttl = 3600, age = -5000 }, 1000)
        if future.ts ~= 1000 then return false, "negative age cannot post date an entry" end
        -- Payload text is sanitized, so a texture escape never reaches a row.
        local evil = LFGBoard:_BuildEntry({ note = "|TInterface\\Icons\\X:64|t", role = 7 }, 0)
        if evil.note:find("|", 1, true) then return false, "note escape survived" end
        if evil.role ~= "ANY" then return false, "forged role rejected" end
        return true
    end)
    S:Register("lfg.rate_limit", function()
        local cd, pending = {}, {}
        local function fakeAfter(_, fn) pending[#pending + 1] = fn end
        if LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "first entry accepted" end
        if not LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "flood dropped" end
        if not LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "still dropped" end
        if LFGBoard:_RateLimited("Bob", cd, fakeAfter) then return false, "other senders unaffected" end
        if #pending ~= 2 then return false, "one self clear per accepted entry" end
        for _, fn in ipairs(pending) do fn() end
        if next(cd) ~= nil then return false, "cooldown table must self clear" end
        if LFGBoard:_RateLimited("Ann", cd, fakeAfter) then return false, "accepted again after cooldown" end
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
    S:Register("lfg.activelist_tiebreak", function()
        -- Two members posting in the same second must not swap rows between
        -- repaints, or an Invite click can land on a row that just moved.
        local store = {
            ["Cara-R"] = { ts = 100, ttl = 600 },
            ["Ann-R"]  = { ts = 100, ttl = 600 },
            ["Bob-R"]  = { ts = 200, ttl = 600 },
        }
        local out = LFGBoard:ActiveList(store, 300)
        if #out ~= 3 then return false, "all three active" end
        if out[1].key ~= "Bob-R" then return false, "newest first" end
        if out[2].key ~= "Ann-R" or out[3].key ~= "Cara-R" then return false, "equal ts sorts by key" end
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
    S:Register("lfg.default_role", function()
        if LFGBoard:_DefaultRole({ HEALER = true }, "ANY") ~= "HEALER" then return false, "single role maps" end
        if LFGBoard:_DefaultRole({ TANK = true, DPS = true }, "ANY") ~= "ANY" then return false, "multiple roles -> ANY" end
        if LFGBoard:_DefaultRole({}, "ANY") ~= "ANY" then return false, "no roles -> ANY" end
        if LFGBoard:_DefaultRole({ TANK = true }, "HEALER") ~= "HEALER" then return false, "lastRole wins over roles" end
        return true
    end)
    S:Register("lfg.avail_parse_show_clear", function()
        if LFGBoard:_ParseAvailArgs({}, "") ~= "show" then return false, "bare -> show" end
        if LFGBoard:_ParseAvailArgs(nil, nil) ~= "show" then return false, "nil args -> show" end
        if LFGBoard:_ParseAvailArgs({ "off" }, "off") ~= "clear" then return false, "off -> clear" end
        if LFGBoard:_ParseAvailArgs({ "stop" }, "stop") ~= "clear" then return false, "stop -> clear" end
        -- Only the bare token delists. "/gos avail stop by if you need a
        -- healer" is a post, not a delist.
        local action, role, note = LFGBoard:_ParseAvailArgs(
            { "stop", "by", "if", "you", "need", "a", "healer" }, "stop by if you need a healer", "DPS")
        if action ~= "set" then return false, "stop plus text must post" end
        if role ~= "DPS" or note ~= "stop by if you need a healer" then return false, "whole line is the note" end
        if LFGBoard:_ParseAvailArgs({ "off", "for", "now" }, "off for now", "ANY") ~= "set" then
            return false, "off plus text must post"
        end
        return true
    end)
    S:Register("lfg.avail_parse_notify", function()
        local action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify" }, "notify")
        if action ~= "notify" or value ~= nil then return false, "bare notify reports only" end
        action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify", "on" }, "notify on")
        if action ~= "notify" or value ~= true then return false, "notify on -> true" end
        action, _, _, value = LFGBoard:_ParseAvailArgs({ "notify", "off" }, "notify off")
        if action ~= "notify" or value ~= false then return false, "notify off -> false" end
        return true
    end)
    S:Register("lfg.avail_parse_role_token", function()
        local action, role, note = LFGBoard:_ParseAvailArgs({ "tank", "heroic", "SP" }, "tank heroic SP", "DPS")
        if action ~= "set" or role ~= "TANK" or note ~= "heroic SP" then return false, "leading role consumed" end
        action, role, note = LFGBoard:_ParseAvailArgs({ "need", "2", "dps" }, "need 2 dps", "HEALER")
        if action ~= "set" or role ~= "HEALER" or note ~= "need 2 dps" then return false, "trailing dps is note" end
        action, role, note = LFGBoard:_ParseAvailArgs({ "tankk", "lol" }, "tankk lol", "ANY")
        if action ~= "set" or role ~= "ANY" or note ~= "tankk lol" then return false, "tankk is not a role" end
        return true
    end)
    S:Register("lfg.avail_parse_note_cap", function()
        local long = string.rep("x", NOTE_MAX + 30)
        local action, _, note = LFGBoard:_ParseAvailArgs({ long }, long, "ANY")
        if action ~= "set" or #note ~= NOTE_MAX then return false, "note capped at NOTE_MAX" end
        return true
    end)
end
