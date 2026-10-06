----------------------------------------------------------------------
-- Guild OS - Call to Arms (issue #108)
-- An officer rallies the guild: a world boss is up, a fight in the open world, a zone to
-- defend, an event farm. Everyone running the addon gets a popup at the top of the screen
-- with a sound, sees how many are coming and can answer "On my way"; a plain guild chat line
-- goes out with it, for members without the addon.
--
-- Officer-authoritative: SyncService only takes a "cta" call from an officer over GUILD
-- (OFFICER_DOMAINS); the answer, "going", is a member action. The call is a live alert, not
-- a record: nothing is saved but an officer's own templates and each player's settings.
----------------------------------------------------------------------
local CTA = {}
BRutus.CallToArms = CTA
local L = BRutus.L

CTA.COOLDOWN  = 60    -- seconds between two calls from one officer
CTA.FROM_GAP  = 30    -- a second call from the same sender inside this is dropped on arrival
CTA.POPUP_GAP = 10    -- a popup inside this of the last one, from anybody, is a chat line instead
CTA.MAX_AGE   = 600   -- a call older than this is not shown
CTA.SKEW      = 300   -- a call stamped further ahead than this is not believed
CTA.SHOW_FOR  = 30    -- seconds the popup stays up
CTA.TEXT_MAX  = 140
CTA.NAME_MAX  = 24
CTA.KEEP      = 10    -- recent calls the panel lists
CTA.TEMPLATES_MAX = 12

local RAID_WARNING = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local READY_CHECK  = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960

-- The ready-made kinds. `text` is the default message; {zone} becomes where the caller is.
CTA.KINDS = {
    { id = "worldboss", title = L["World Boss"], text = L["World boss up in {zone}, come now!"],
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", sound = RAID_WARNING },
    { id = "pvp", title = L["World PvP"], text = L["Fight in {zone}, everyone we can get!"],
      icon = "Interface\\Icons\\Ability_DualWield", sound = RAID_WARNING },
    { id = "defend", title = L["Defend"], text = L["{zone} is under attack, defend it!"],
      icon = "Interface\\Icons\\INV_Shield_06", sound = RAID_WARNING },
    { id = "event", title = L["Event / Farm"], text = L["Event farm in {zone}, join us!"],
      icon = "Interface\\Icons\\INV_Misc_Bag_08", sound = READY_CHECK },
    { id = "rally", title = L["Rally"], text = L["Gather in {zone}!"],
      icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = READY_CHECK },
}
local BY_ID = {}
for _, k in ipairs(CTA.KINDS) do BY_ID[k.id] = k end

function CTA:Kind(id)
    return BY_ID[id] or BY_ID.rally
end

CTA.recent = {}     -- newest first: { call fields..., sender, at, going = { [name] = true }, mine }
CTA.seen = {}       -- call id -> true
CTA.lastFrom = {}   -- sender -> server time of their last call shown

function CTA:Initialize()
    BRutus.db.cta = BRutus.db.cta or {}
    BRutus.db.cta.templates = BRutus.db.cta.templates or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("cta", function(env, sender) CTA:OnSync(env, sender) end)
    end
end

----------------------------------------------------------------------
-- Settings: each player's own, true unless switched off
----------------------------------------------------------------------
local function on(key)
    return BRutus:GetSetting(key) ~= false
end
function CTA:PopupsOn() return on("ctaPopups") end
function CTA:SoundOn() return on("ctaSound") end
function CTA:QuietOn() return on("ctaQuiet") end
function CTA:ChatOn() return on("ctaChat") end
function CTA:Muted(kind) return BRutus:GetSetting("ctaMute_" .. tostring(kind)) == true end

----------------------------------------------------------------------
-- Templates: the ready-made kinds, then an officer's own
----------------------------------------------------------------------
function CTA:Templates()
    local out = {}
    for _, k in ipairs(self.KINDS) do
        out[#out + 1] = { id = k.id, name = k.title, text = k.text, kind = k.id, builtin = true }
    end
    for _, t in ipairs((BRutus.db.cta and BRutus.db.cta.templates) or {}) do
        out[#out + 1] = { id = t.id, name = t.name, text = t.text, kind = t.kind }
    end
    return out
end

function CTA:Template(id)
    for _, t in ipairs(self:Templates()) do
        if t.id == id then return t end
    end
end

function CTA:SaveTemplate(name, text, kind)
    name = BRutus:SanitizeUserText(name, self.NAME_MAX)
    text = BRutus:SanitizeUserText(text, self.TEXT_MAX)
    if name == "" or text == "" then return false, L["A template needs a name and a message."] end
    local list = BRutus.db.cta.templates
    if #list >= self.TEMPLATES_MAX then return false, L["Too many templates: delete one first."] end
    list[#list + 1] = { id = string.format("c%X%04X", GetServerTime(), math.random(0, 0xFFFF)),
                        name = name, text = text, kind = BY_ID[kind] and kind or "rally" }
    return true
end

function CTA:DeleteTemplate(id)
    local list = BRutus.db.cta.templates
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
end

----------------------------------------------------------------------
-- Where the caller is: the zone (and subzone) and the map position, if the client gives it
----------------------------------------------------------------------
function CTA:Where()
    local zone = GetZoneText and GetZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local label = (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
    local x, y
    local ok = pcall(function()
        local mapID = BRutus.Compat.GetBestMapForUnit("player")
        local px, py = BRutus.Compat.GetPlayerMapPosition(mapID, "player")
        if px and py and not BRutus.Compat.IsSecret(px, py) and px > 0 and py > 0 then
            x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10
        end
    end)
    if not ok then x, y = nil, nil end
    return label, x, y
end

local function fill(text, zone)
    return (text:gsub("{zone}", function() return zone ~= "" and zone or L["here"] end))
end

----------------------------------------------------------------------
-- Sending (officers, from a click or a command: the guild chat line needs that on Forever)
----------------------------------------------------------------------
function CTA:Send(templateId, text)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return false
    end
    local now = GetServerTime()
    local last = BRutus.db.cta.lastSent   -- saved, so a /reload does not skip the cooldown
    if last and now - last < self.COOLDOWN and now >= last then
        BRutus:Print(string.format(L["Wait %ds before the next call."], self.COOLDOWN - (now - last)))
        return false
    end
    local t = self:Template(templateId) or self:Template("rally")
    local zone, x, y = self:Where()
    local body = BRutus:SanitizeUserText((text and strtrim(text) ~= "") and text or t.text, self.TEXT_MAX)
    local call = {
        id = string.format("%X%04X", now, math.random(0, 0xFFFF)),
        kind = t.kind,
        title = BRutus:SanitizeUserText(t.name, self.NAME_MAX),
        text = BRutus:SanitizeUserText(fill(body, zone), self.TEXT_MAX),
        zone = BRutus:SanitizeUserText(zone, 60),
        x = x, y = y, ts = now,
    }
    -- The guild line first, so the call can say it went: a player who takes calls as chat lines
    -- already has it there, and is not told twice. Forever drops a refused line without an
    -- error, so an encounter's chat lockdown is asked first rather than inferred.
    if self:ChatOn() and IsInGuild() then
        local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
        call.chat = not locked
            and pcall(SendChatMessage, string.format(L["[Call to Arms] %s: %s"], call.title, call.text), "GUILD")
            or nil
    end
    if BRutus.SyncService then BRutus.SyncService:Publish("cta", "call", call) end
    BRutus.db.cta.lastSent = now
    self:Remember(call, BRutus.Compat.PlayerName(), true)
    BRutus:Print(string.format(L["Call to Arms sent: %s"], call.title))
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
    return true
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local function clean(s, max)
    return type(s) == "string" and BRutus:SanitizeUserText(s, max) or ""
end

function CTA:Remember(call, sender, mine)
    self.seen[call.id] = true
    local entry = {}
    for k, v in pairs(call) do entry[k] = v end
    entry.sender, entry.at, entry.going, entry.mine = sender, GetServerTime(), {}, mine
    table.insert(self.recent, 1, entry)
    while #self.recent > self.KEEP do table.remove(self.recent) end
    return entry
end

function CTA:Find(id)
    for _, e in ipairs(self.recent) do
        if e.id == id then return e end
    end
end

function CTA:OnSync(env, sender)
    local d = env and env.data
    if type(d) ~= "table" or type(sender) ~= "string" then return end
    if env.act == "call" then
        self:OnCall(d, sender)
    elseif env.act == "going" then
        local e = type(d.id) == "string" and self:Find(d.id)
        if e and not e.going[sender] then
            e.going[sender] = true
            if self.popup and self.popup.callId == e.id then self:PaintCount(e) end
            if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
        end
    end
end

function CTA:OnCall(d, sender)
    if type(d.id) ~= "string" or d.id == "" or self.seen[d.id] then return end
    local now = GetServerTime()
    local ts = tonumber(d.ts) or 0
    if now - ts > self.MAX_AGE or ts - now > self.SKEW then return end
    if self.lastFrom[sender] and now - self.lastFrom[sender] < self.FROM_GAP then return end
    self.lastFrom[sender] = now
    local x, y = tonumber(d.x), tonumber(d.y)
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then x, y = nil, nil end
    local call = {
        id = d.id, kind = BY_ID[d.kind] and d.kind or "rally", ts = ts,
        title = clean(d.title, self.NAME_MAX), text = clean(d.text, self.TEXT_MAX), zone = clean(d.zone, 60),
        x = x, y = y, chat = d.chat == true or nil,
    }
    if call.title == "" then call.title = self:Kind(call.kind).title end
    local e = self:Remember(call, sender, false)
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
    self:Alert(e)
end

-- How a call reaches this player: a popup, a chat line only, or nothing. A line the caller
-- already put in guild chat is not printed again. Popups from several officers at once are
-- one popup and lines for the rest.
function CTA:Alert(e)
    if self:Muted(e.kind) then return "muted" end
    local now = GetServerTime()
    local quiet = self:QuietOn() and ((IsInInstance and select(2, IsInInstance()) ~= "none")
        or (InCombatLockdown and InCombatLockdown()))
    local crowded = self.lastPopup and now - self.lastPopup < self.POPUP_GAP
    if not self:PopupsOn() or quiet or crowded then
        if not e.chat then BRutus:Print(self:Line(e)) end
        return "line"
    end
    self.lastPopup = now
    self:ShowPopup(e)
    return "popup"
end

local function short(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or (name or "")
end

function CTA:Line(e)
    return string.format(L["|cffFF8800[Call to Arms]|r %s: %s |cff888888(%s, %s)|r"], e.title, e.text,
        short(e.sender), e.zone or "")
end

function CTA:Answer(id)
    local e = self:Find(id)
    if not e or e.answered then return end
    e.answered = true
    e.going[BRutus.Compat.PlayerName()] = true
    if BRutus.SyncService then BRutus.SyncService:Publish("cta", "going", { id = id }) end
    if self.popup and self.popup.callId == id then self:PaintCount(e) end
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

function CTA:GoingCount(e)
    local n = 0
    for _ in pairs(e.going or {}) do n = n + 1 end
    return n
end

----------------------------------------------------------------------
-- The popup: one at a time, the newest call wins
----------------------------------------------------------------------
local function ago(ts)
    local d = math.max(0, GetServerTime() - (tonumber(ts) or 0))
    if d < 60 then return L["just now"] end
    return string.format(L["%d min ago"], math.floor(d / 60))
end

function CTA:BuildPopup()
    local C = BRutus.Colors
    local f = CreateFrame("Frame", "GuildOSCallToArms", UIParent, "BackdropTemplate")
    f:SetSize(440, 132)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    f:SetBackdropColor(0.05, 0.03, 0.03, 0.94)
    f:SetBackdropBorderColor(1, 0.53, 0, 0.9)
    f:EnableMouse(true)
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(52, 52)
    f.icon:SetPoint("TOPLEFT", 12, -12)

    f.title = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.title, 16)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 0)
    f.title:SetTextColor(1, 0.53, 0)

    f.text = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.text, 12)
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.text:SetWidth(350)
    f.text:SetJustifyH("LEFT")
    if f.text.SetMaxLines then f.text:SetMaxLines(3) end   -- 140 wide letters would be four
    f.text:SetTextColor(C.white.r, C.white.g, C.white.b)

    f.close = BRutus.UI:CreateButton(f, L["Dismiss"], 90, 22)
    f.close:SetPoint("BOTTOMRIGHT", -12, 10)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.go = BRutus.UI:CreateButton(f, L["On my way"], 100, 22)
    f.go:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.go:SetScript("OnClick", function() CTA:Answer(f.callId) end)

    -- Where, who and when: the popup's full width, on one line above the buttons, so a long
    -- zone with its position does not push the sender off it.
    f.meta = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.meta, 10)
    f.meta:SetPoint("BOTTOMLEFT", 12, 40)
    f.meta:SetPoint("BOTTOMRIGHT", -12, 40)
    f.meta:SetJustifyH("LEFT")
    f.meta:SetWordWrap(false)
    f.meta:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    -- How many are coming, beside the buttons and stopping short of them.
    f.count = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.count, 10)
    f.count:SetPoint("BOTTOMLEFT", 12, 16)
    f.count:SetPoint("BOTTOMRIGHT", f.go, "BOTTOMLEFT", -8, 6)
    f.count:SetJustifyH("LEFT")
    f.count:SetWordWrap(false)
    f.count:SetTextColor(C.gold.r, C.gold.g, C.gold.b)

    self.popup = f
    return f
end

function CTA:PaintCount(e)
    local f = self.popup
    if not f then return end
    local n = self:GoingCount(e)
    f.count:SetText(n > 0 and string.format(L["%d on the way"], n) or "")
    if e.answered then f.go:Disable() else f.go:Enable() end
end

function CTA:ShowPopup(e)
    local f = self.popup or self:BuildPopup()
    local k = self:Kind(e.kind)
    f.callId = e.id
    f.icon:SetTexture(k.icon)
    f.title:SetText(e.title)
    f.text:SetText(e.text)
    local where = e.zone or ""
    if e.x and e.y then where = string.format("%s (%.1f, %.1f)", where, e.x, e.y) end
    f.meta:SetText(string.format(L["%s · by %s · %s"], where, short(e.sender), ago(e.ts)))
    self:PaintCount(e)
    f:Show()
    if self:SoundOn() and PlaySound then pcall(PlaySound, k.sound, "Master") end
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(self.SHOW_FOR, function()
        if f.callId == e.id then f:Hide() end
    end)
end
