----------------------------------------------------------------------
-- Guild OS - Raid HUD (#449; specs/salao/raidtools.md)
--
-- The one part of Raid Tools that shows in combat: a small, movable, collapsible list of the raid's key
-- cooldowns (Bloodlust/Heroism, Rebirth, Innervate, …), how many of each are ready and when the next one
-- is back. Nothing else is drawn in combat: the link to Raid Tools shows out of combat only, and the
-- consumables popup and the Raid Tools window open from a click, never by themselves.
--
-- It shows in a raid while its switch is on (Settings › the "Raid CD Tracker" switch, or the Fight part's
-- box) and it is not hidden: × hides it until the next raid, and the raid leader turns it off for good with
-- the switch. TBC content (ADR-0014): the combat log is read on TBC Anniversary only (Compat.CanReadCombatLog:
-- WoW: Forever has the cooldown list, but its combat log arrives as Secret Values inside an encounter, so no
-- timer could be read there), and the cooldowns are Raid Tools' one list (RaidTools:TrackedCooldowns, audit B19).
-- The log is listened to only while the HUD shows, the raid's members are read on a roster change (never on
-- the half-second tick), and the tick redraws into the same tables (#449 review).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local RaidHUD = {}
GuildOS.RaidHUD = RaidHUD
local L = GuildOS.L

local RT_TOOLS = GuildOS.RaidTools
local WHITE = "Interface\\Buttons\\WHITE8x8"

RaidHUD.WIDTH = 196
RaidHUD.HEADER_H = 18
RaidHUD.ROW_H = 17
local TICK = 0.5

-- [casterName][cdKey] = { usedAt = GetTime(), duration }
RaidHUD.state = {}

----------------------------------------------------------------------
-- Pure parts
----------------------------------------------------------------------

--- Whether the HUD shows: its switch on, not hidden, in a raid, as its leader or an assistant (or with
--- `everyone`), with cooldowns to track. In combat or not makes no difference to the HUD itself; a HUD that
--- is off never comes up in combat. `s` = { enabled, hidden, inRaid, lead, tracked, everyone }.
function RaidHUD.ShouldShow(s)
    if not s.enabled or s.hidden then return false end
    if not s.inRaid or (s.tracked or 0) == 0 then return false end
    return (s.lead or s.everyone) and true or false
end

--- The seconds as the HUD prints them: "4m", "45s".
function RaidHUD.Clock(s)
    s = math.floor(s or 0)
    if s >= 60 then return string.format("%dm", math.ceil(s / 60)) end
    return string.format("%ds", s)
end

--- The HUD's rows: one per tracked cooldown somebody in `members` ({ [name] = classFile }) can cast, with how
--- many are ready, how many there are and the seconds until the next one is back (nil when one is ready or
--- none was used). `state` is RaidHUD.state's shape. Pure.
function RaidHUD.Rows(defs, members, state, now)
    return RaidHUD.RowsInto({}, defs, members, RaidHUD.CasterLists(defs, members), state, now)
end

--- Who can cast each cooldown: { [cd.key] = sorted names } of `members`. Built when the roster changes. Pure.
function RaidHUD.CasterLists(defs, members)
    local lists = {}
    for _, cd in ipairs(defs) do
        local names = {}
        for name, class in pairs(members) do
            if cd.classes[class] then names[#names + 1] = name end
        end
        table.sort(names)
        lists[cd.key] = names
    end
    return lists
end

--- Rows' rows written into `out` (its tables reused, the ones left over dropped), from the caster lists
--- (CasterLists'). The HUD's tick calls this: no table is made once the rows exist. Returns `out`.
function RaidHUD.RowsInto(out, defs, members, lists, state, now)
    local n = 0
    for _, cd in ipairs(defs) do
        local names = lists[cd.key]
        if names and #names > 0 then
            n = n + 1
            local row = out[n] or {}
            out[n] = row
            local who = row.who or {}
            row.who = who
            local ready, nextIn = 0, nil
            for i, name in ipairs(names) do
                local st = state[name] and state[name][cd.key]
                local left = st and (st.duration - (now - st.usedAt)) or 0
                if left > 0 then
                    if not nextIn or left < nextIn then nextIn = left end
                else
                    ready = ready + 1
                end
                local w = who[i] or {}
                who[i] = w
                w.name, w.left, w.class = name, left > 0 and left or nil, members[name]
            end
            for i = #names + 1, #who do who[i] = nil end
            row.key, row.label, row.name, row.iconID = cd.key, cd.short or cd.name, cd.name, cd.iconID
            row.ready, row.total, row.nextIn, row.soonest = ready, #names, ready == 0 and nextIn or nil, nextIn
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return out
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
local function settings()
    return GuildOS.db and GuildOS.db.settings or {}
end

--- The switch: the Settings feature "raidHUD", on unless turned off.
function RaidHUD:IsEnabled()
    local s = settings()
    return not (s.modules and s.modules.raidHUD == false)
end

function RaidHUD:SetEnabled(on)
    local s = GuildOS.db and GuildOS.db.settings
    if not s then return end
    s.modules = s.modules or {}
    s.modules.raidHUD = on and true or false
    if on then s.raidHUDDismissed = false end
    self:Update()
end

--- Hidden until the next raid (×); cleared when the player leaves the raid.
function RaidHUD:IsHidden()
    return settings().raidHUDDismissed == true
end

function RaidHUD:SetHidden(on)
    local s = GuildOS.db and GuildOS.db.settings
    if s then s.raidHUDDismissed = on and true or false end
    self:Update()
end

function RaidHUD:Tracked()
    if not self._tracked then self._tracked = RT_TOOLS and RT_TOOLS:TrackedCooldowns() or {} end
    return self._tracked
end

----------------------------------------------------------------------
-- The raid as the HUD reads it
----------------------------------------------------------------------
local function raidMembers()
    local out = {}
    if not IsInRaid() then return out end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
        if type(name) == "string" and not GuildOS.Compat.IsSecret(name, classFile) then out[name] = classFile end
    end
    return out
end
RaidHUD._RaidMembers = raidMembers

function RaidHUD:State()
    return {
        enabled = self:IsEnabled() and GuildOS.Compat.CanReadCombatLog(),
        hidden = self:IsHidden(),
        inRaid = IsInRaid() and true or false,
        lead = IsInRaid() and GuildOS.Compat.IsLeaderOrAssist() or false,
        tracked = #self:Tracked(),
        everyone = settings().raidHUDEveryone == true,
    }
end

----------------------------------------------------------------------
-- Drawing: one row a cooldown, shared by the HUD and its preview on the Fight part
----------------------------------------------------------------------
local function paintRow(row, data)
    local C = GuildOS.Colors
    local tex = GuildOS.Compat.GetSpellTexture(data.iconID)
    row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetDesaturated(data.ready == 0)
    row.label:SetText(data.label)
    local col = data.ready > 0 and C.text or C.label
    row.label:SetTextColor(col.r, col.g, col.b)
    row.count:SetText(data.ready .. "/" .. data.total)
    local cc = data.ready > 0 and C.ok or C.danger
    row.count:SetTextColor(cc.r, cc.g, cc.b)
    row.timer:SetText(data.soonest and RaidHUD.Clock(data.soonest) or "")
    row.data = data
end

--- A row frame on `parent`: the spell's icon, its short name, ready/total and the next one back.
function RaidHUD:MakeRow(parent)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(self.ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
    row.label:SetPoint("LEFT", 24, 0)
    row.label:SetJustifyH("LEFT")
    row.timer = UI:CreateText(row, "", 11, C.label.r, C.label.g, C.label.b)
    row.timer:SetPoint("RIGHT", -6, 0)
    row.timer:SetWidth(30)
    row.timer:SetJustifyH("RIGHT")
    row.count = UI:CreateText(row, "", 11, C.ok.r, C.ok.g, C.ok.b)
    row.count:SetPoint("RIGHT", row.timer, "LEFT", -4, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local d = self.data
        if not d or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(d.name, C.gold.r, C.gold.g, C.gold.b)
        for _, w in ipairs(d.who) do
            local status = w.left and RaidHUD.Clock(w.left) or L["Ready"]
            local sc = w.left and C.danger or C.ok
            GameTooltip:AddDoubleLine(w.name, status, 1, 1, 1, sc.r, sc.g, sc.b)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.Paint = paintRow
    return row
end

--- Lays `rows` (Rows') out on `body` from its top, reusing its row frames. Returns the height they take.
function RaidHUD:FillBody(body, rows)
    body.__rows = body.__rows or {}
    for i, data in ipairs(rows) do
        local row = body.__rows[i]
        if not row then
            row = self:MakeRow(body)
            body.__rows[i] = row
            row:SetPoint("TOPLEFT", 0, -(i - 1) * self.ROW_H)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * self.ROW_H)
        end
        paintRow(row, data)
        row:Show()
    end
    for i = #rows + 1, #body.__rows do body.__rows[i]:Hide() end
    return #rows * self.ROW_H
end

----------------------------------------------------------------------
-- The HUD
----------------------------------------------------------------------
local function headerButton(parent, glyph)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b.text = UI:CreateText(b, glyph, 12, C.label.r, C.label.g, C.label.b)
    b.text:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(C.label.r, C.label.g, C.label.b) end)
    return b
end

function RaidHUD:Create()
    if self.frame then return self.frame end
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = CreateFrame("Frame", "GuildOSRaidHUD", UIParent, "BackdropTemplate")
    f:SetSize(self.WIDTH, self.HEADER_H + 4)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
    f:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 0.82)
    f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    local pos = GuildOS.db and GuildOS.db.raidHUDPos
    if type(pos) == "table" and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -250, -180)
    end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if GuildOS.db then GuildOS.db.raidHUDPos = { point = point, relPoint = relPoint, x = math.floor(x or 0), y = math.floor(y or 0) } end
    end)

    local title = UI:CreateText(f, L["Cooldowns"], 11, C.gold2.r, C.gold2.g, C.gold2.b)
    title:SetPoint("TOPLEFT", 6, -3)
    f.title = title
    local close = headerButton(f, "\195\151")   -- ×
    close:SetPoint("TOPRIGHT", -2, -1)
    close:SetScript("OnClick", function() RaidHUD:SetHidden(true) end)
    UI:AddTooltip(close, L["Hide until the next raid"], { L["Turn it back on in Raids › Raid Tools › Fight."] })
    local fold = headerButton(f, "\226\128\147")   -- –
    fold:SetPoint("RIGHT", close, "LEFT", -2, 0)
    fold:SetScript("OnClick", function()
        local s = GuildOS.db and GuildOS.db.settings
        if s then s.raidHUDCollapsed = not s.raidHUDCollapsed end
        RaidHUD:Refresh()
    end)
    f.fold = fold

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -self.HEADER_H)
    body:SetPoint("TOPRIGHT", 0, -self.HEADER_H)
    body:SetHeight(1)
    f.body = body

    -- Out of combat only: the way to the rest of Raid Tools.
    local link = UI:SetButtonVariant(UI:CreateButton(f, L["Raid Tools"], 60, 16), "ghost")
    link:SetWidth(math.ceil(link.label:GetStringWidth() or 50) + 4)
    link:SetPoint("BOTTOMLEFT", 6, 3)
    link:SetScript("OnClick", function()
        if GuildOS.UI and GuildOS.UI.OpenWindow and not GuildOS.Compat.InCombat() then GuildOS.UI:OpenWindow("raids", "raidtools") end
    end)
    f.link = link

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < TICK then return end
        elapsed = 0
        RaidHUD:Refresh()
    end)
    f:Hide()
    self.frame = f
    return f
end

--- Redraws the rows and the size: folded, the header only; in combat, no link.
function RaidHUD:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local collapsed = settings().raidHUDCollapsed == true
    f.fold.text:SetText(collapsed and "+" or "\226\128\147")
    local h = 0
    if collapsed then
        f.body:Hide()
    else
        f.body:Show()
        if not self._lists then self:ReadRoster() end
        self._rows = self.RowsInto(self._rows or {}, self:Tracked(), self._members, self._lists, self.state, GetTime())
        h = self:FillBody(f.body, self._rows)
        f.body:SetHeight(math.max(1, h))
    end
    local combat = GuildOS.Compat.InCombat()
    f.link:SetShown(not combat and not collapsed)
    f:SetHeight(self.HEADER_H + h + ((not combat and not collapsed) and 20 or 4))
end

--- The raid's members and who of them casts each cooldown, read again (on a roster change, never per tick).
function RaidHUD:ReadRoster()
    self._members = raidMembers()
    self._lists = self.CasterLists(self:Tracked(), self._members)
end

--- Shows or hides the HUD by ShouldShow. Leaving the raid clears ×. The combat log is listened to only while
--- it shows; the roster is read here, on the events that call this (a roster change, combat's edges, login).
function RaidHUD:Update()
    local s = self:State()
    if not s.inRaid and GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.raidHUDDismissed then
        GuildOS.db.settings.raidHUDDismissed = false
        s.hidden = false
    end
    local show = self.ShouldShow(s)
    if show and not self.frame then self:Create() end
    if not self.frame then return end
    -- Out of the raid the consumables popup it opened goes with it; one opened elsewhere stays.
    if not s.inRaid and self.frame:IsShown() and GuildOS.HideConsumablePopup then GuildOS:HideConsumablePopup() end
    self:ListenToLog(show)
    if show then self:ReadRoster() end
    self.frame:SetShown(show)
    if show then self:Refresh() end
end

-- What the old UI/RaidHUD.lua named: the settings switch and the slash command still call these.
function GuildOS:CreateRaidHUD() return RaidHUD:Create() end
function GuildOS:UpdateRaidHUDVisibility() return RaidHUD:Update() end

----------------------------------------------------------------------
-- The combat log: a raid member's cast of a tracked cooldown starts its timer
----------------------------------------------------------------------
function RaidHUD:OnCombatLog(event, srcName, srcFlags, spellID, now)
    if event ~= "SPELL_CAST_SUCCESS" or type(srcName) ~= "string" then return false end
    local cd = RT_TOOLS and RT_TOOLS:CooldownOfSpell(spellID)
    -- Only the raid's own (audit B19): a stranger's cast nearby is nobody the HUD shows.
    if not cd or not RT_TOOLS:IsRaidCaster(srcFlags) then return false end
    self.state[srcName] = self.state[srcName] or {}
    self.state[srcName][cd.key] = { usedAt = now or GetTime(), duration = cd.cooldown }
    return true
end

local clFrame = CreateFrame("Frame")
RaidHUD._logFrame = clFrame
-- The combat log only while the HUD shows, and only where it may be read (Compat.CanReadCombatLog).
function RaidHUD:ListenToLog(on)
    on = on and GuildOS.Compat.CanReadCombatLog() or false
    if on == (self._listening or false) then return end
    if on then
        GuildOS.Compat.RegisterEvent(clFrame, "COMBAT_LOG_EVENT_UNFILTERED")
    elseif clFrame.UnregisterEvent then
        clFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
    self._listening = on
end
clFrame:SetScript("OnEvent", function()
    local _, event, _, _, srcName, srcFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    RaidHUD:OnCombatLog(event, srcName, srcFlags, spellID)
end)

local evFrame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    GuildOS.Compat.RegisterEvent(evFrame, e)
end
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        GuildOS.Compat.After(2, function() if GuildOS.db then GuildOS:SafeCall(RaidHUD.Update, RaidHUD) end end)
    elseif GuildOS.db then
        GuildOS:SafeCall(RaidHUD.Update, RaidHUD)
    end
end)
