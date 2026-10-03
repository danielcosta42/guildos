----------------------------------------------------------------------
-- BRutus Guild Manager - Recruitment System
-- Automatic recruitment messages + right-click guild invite
-- Only officers (rank index <= 1) or configurable rank can use this
----------------------------------------------------------------------
local Recruitment = {}
BRutus.Recruitment = Recruitment
local L = BRutus.L

-- TBC class list (used by UI and broadcast)
Recruitment.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Defaults
Recruitment.DEFAULT_SETTINGS = {
    enabled = false,
    interval = 120,           -- seconds between messages
    message = "",             -- recruitment message text
    channels = {},            -- list of channel names to post to (e.g. {"LookingForGroup", "Trade"})
    minRankIndex = 2,         -- max rank index allowed (0 = GM, 1 = first officer, 2 = second officer, etc.)
    welcomeEnabled = true,
    welcomeMessage = "",      -- auto-filled on init
    discord = "",
}

-- Auto-invite defaults (merged into db.recruitment.autoInvite on Initialize).
Recruitment.AUTOINVITE_DEFAULTS = {
    enabled     = false,
    keyword     = "ginv",
    minLevel    = 0,
    classes     = {},        -- set: { WARRIOR = true, ... }; empty = any class
    cooldownSec = 300,
    whoFallback = "skip",    -- "skip" (fail-safe) or "invite" when /who can't confirm
}

Recruitment.ticker       = nil   -- officer auto-send ticker
Recruitment.memberTicker = nil   -- member opt-in auto-send ticker
Recruitment.lastSend     = 0

-- Content policy for the auto-post (T2 hardening). These cap the rate and the
-- volume of what a member can be made to post under their own name, so a forged
-- or aggressive config cannot spam them into a Blizzard silence.
Recruitment.SEND_MIN_GAP     = 30   -- min seconds between two sends from this client
Recruitment.AUTO_SESSION_CAP = 40   -- max AUTO popups per session before self-pausing
Recruitment.MSG_MAX          = 255  -- SendChatMessage byte cap; the consent popup previews the SAME
                                    -- length that is sent, so what the member sees is what posts

----------------------------------------------------------------------
-- Auto-invite: pure helpers (deterministic; unit-tested via /gos selftest)
----------------------------------------------------------------------
function Recruitment:_MatchKeyword(msg, keyword)
    local m = strtrim(msg or ""):lower()
    local k = (keyword or ""):lower()
    if k == "" then return false end
    return m == k or m:sub(1, #k + 1) == (k .. " ")
end

function Recruitment:_OnInviteCooldown(name, now, store)
    store = store or self._inviteCd or {}
    local exp = store[name]
    return exp ~= nil and exp > (now or 0)
end

function Recruitment:_MarkInvited(name, now, cooldownSec, store)
    store = store or self._inviteCd
    if not store then self._inviteCd = {}; store = self._inviteCd end
    store[name] = (now or 0) + (cooldownSec or 300)
end

function Recruitment:_PassesFilters(info, cfg)
    if not info then return false end
    if (cfg.minLevel or 0) > 0 and (info.level or 0) < cfg.minLevel then return false end
    if cfg.classes and next(cfg.classes) ~= nil then
        if not cfg.classes[info.class] then return false end
    end
    return true
end

----------------------------------------------------------------------
-- Settings, one door for the slash commands and the Recruitment screen (issue #59), so both
-- hold the same rules. Each takes the table it writes and returns what it stored, or nil/false.
----------------------------------------------------------------------
Recruitment.KEYWORD_MAX = 20

-- A keyword is one word, lowercase: the whisper is matched on its first word.
function Recruitment:SetAutoInviteKeyword(cfg, word)
    local kw = strtrim(tostring(word or "")):lower():match("^(%S+)")
    if not kw or #kw > self.KEYWORD_MAX then return nil end
    cfg.keyword = kw
    return kw
end

-- 0 means any level; nothing above the game's cap.
function Recruitment:SetAutoInviteMinLevel(cfg, n)
    n = tonumber(n)
    if not n then return nil end
    cfg.minLevel = math.max(0, math.min(BRutus.Client.maxLevel, math.floor(n)))
    return cfg.minLevel
end

function Recruitment:IsClass(token)
    for _, c in ipairs(self.CLASSES) do
        if c == token then return true end
    end
    return false
end

-- The command used to store whatever was typed: a "MAEG" left in the filter counted as a
-- filter, matched nobody, and showed nowhere, so auto-invite went quiet. Dropped at start.
function Recruitment:_DropUnknownClasses(classes)
    for c in pairs(classes or {}) do
        if not self:IsClass(c) then classes[c] = nil end
    end
end

-- Only a class the game has.
function Recruitment:SetAutoInviteClass(cfg, class, on)
    class = tostring(class or ""):upper()
    if not self:IsClass(class) then return false end
    cfg.classes[class] = on and true or nil
    return true
end

-- What to do when /who cannot confirm the player's level or class.
function Recruitment:SetAutoInviteFallback(cfg, mode)
    if mode ~= "skip" and mode ~= "invite" then return false end
    cfg.whoFallback = mode
    return true
end

-- A recruitment channel is listed once, whatever the case.
function Recruitment:AddChannel(list, name)
    name = strtrim(tostring(name or ""))
    if name == "" then return false end
    for _, c in ipairs(list) do
        if c:lower() == name:lower() then return false end
    end
    list[#list + 1] = name
    return true
end

function Recruitment:RemoveChannel(list, name)
    name = strtrim(tostring(name or "")):lower()
    local removed = false
    for i = #list, 1, -1 do
        if list[i]:lower() == name then
            table.remove(list, i)
            removed = true
        end
    end
    return removed
end

----------------------------------------------------------------------
-- Recruitment sync: pure trust + rate decisions (deterministic; unit-tested)
----------------------------------------------------------------------

-- Pure trust decision for an incoming recruitment config. Identity comes from
-- the comm ENVELOPE, never the payload body: the config is applied only when it
-- arrives over GUILD, the CLAIMED author (info.updatedBy) is a current officer,
-- and the envelope SENDER is a current guildmate (either the officer's own
-- broadcast, or a member relaying it). Newest content edit wins, so an older
-- stamp is rejected and a relay can never roll the ad back. Kept pure so a self
-- test pins the rule with no comm/db in play.
function Recruitment:_AcceptConfig(channel, claimedAuthorIsOfficer, senderIsGuildmate, incomingAt, curAt)
    if channel ~= "GUILD" then return false end
    if not claimedAuthorIsOfficer then return false end
    if not senderIsGuildmate then return false end
    if curAt and incomingAt < curAt then return false end
    return true
end

-- Min-gap decision for an outgoing send. First send (lastAt nil) is allowed.
function Recruitment:_CanSendNow(lastAt, now, gap)
    if not lastAt then return true end
    return (now - lastAt) >= (gap or 0)
end

----------------------------------------------------------------------
-- Raid icons where the server hides them (issue #64). On WoW: Forever, Trade (and General,
-- LocalDefense, Services) shows "{rt8}" as text while LookingForGroup shows the skull
-- (Compat.ChannelHidesRaidIcons). The copy posted there leaves the codes out.
----------------------------------------------------------------------
-- `{rt1}`..`{rt8}` and the icon words the game knows (ICON_TAG_LIST, localized) come out; a
-- code between two words leaves a space, so "LFM{rt8}Heroic" stays two words. Braces that are
-- no icon stay.
function Recruitment:_StripRaidIcons(msg)
    local words = ICON_TAG_LIST or {}
    local out = tostring(msg or ""):gsub("%b{}", function(tag)
        local t = tag:sub(2, -2):lower()
        if t:match("^rt[1-8]$") or words[t] then return " " end
    end)
    return strtrim((out:gsub("%s%s+", " ")))
end

-- Should the member AUTO ticker keep firing given how many popups it has shown
-- this session? Pure so a self test pins the cap without a live ticker.
function Recruitment:_AutoShouldContinue(popupCount, cap)
    return (popupCount or 0) < (cap or 0)
end

-- Is a name resolvable on the current guild roster? The envelope sender must be
-- a real guildmate for a relayed ad to be trusted. Realm suffix is tolerated.
function Recruitment:_IsGuildmate(fullName)
    if not fullName or not IsInGuild() then return false end
    local short = fullName:match("^([^-]+)") or fullName
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local memberShort = name:match("^([^-]+)") or name
            if memberShort == short then return true end
        end
    end
    return false
end

function Recruitment:_RegisterAutoInviteTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("autoinvite.keyword_exact", function()
        if not Recruitment:_MatchKeyword("  GINV ", "ginv") then return false, "exact should match" end
        return true
    end)
    S:Register("autoinvite.keyword_prefix", function()
        if not Recruitment:_MatchKeyword("ginv please", "ginv") then return false, "prefix should match" end
        if Recruitment:_MatchKeyword("ginvite me", "ginv") then return false, "must not match 'ginvite'" end
        return true
    end)
    S:Register("autoinvite.cooldown", function()
        local store = { Bob = 500 }
        if not Recruitment:_OnInviteCooldown("Bob", 400, store) then return false, "should be on cd" end
        if Recruitment:_OnInviteCooldown("Bob", 600, store) then return false, "cd should be over" end
        return true
    end)
    S:Register("autoinvite.filters", function()
        local cfg = { minLevel = 60, classes = { WARRIOR = true } }
        if not Recruitment:_PassesFilters({ level = 70, class = "WARRIOR" }, cfg) then return false, "should pass" end
        if Recruitment:_PassesFilters({ level = 58, class = "WARRIOR" }, cfg) then return false, "level fail" end
        if Recruitment:_PassesFilters({ level = 70, class = "MAGE" }, cfg) then return false, "class fail" end
        return true
    end)
    S:Register("recruit.participation_opt_out", function()
        -- Opt-out: the untouched default (nil) and an explicit true both help;
        -- only a stored false stays out.
        if not Recruitment:_ParticipatingFrom(nil) then return false, "nil default must participate" end
        if not Recruitment:_ParticipatingFrom(true) then return false, "true participates" end
        if Recruitment:_ParticipatingFrom(false) then return false, "false opts out" end
        return true
    end)
    S:Register("recruit.accept_config", function()
        local T = 100
        -- Happy path: GUILD + officer author + guildmate sender + newer stamp.
        if not Recruitment:_AcceptConfig("GUILD", true, true, T + 1, T) then return false, "valid should accept" end
        -- First receipt (no current stamp yet) accepts.
        if not Recruitment:_AcceptConfig("GUILD", true, true, T, nil) then return false, "first receipt" end
        -- External whisper injection: non-GUILD channel rejects.
        if Recruitment:_AcceptConfig("WHISPER", true, true, T + 1, T) then return false, "whisper must reject" end
        -- Payload attributed to a non-officer rejects.
        if Recruitment:_AcceptConfig("GUILD", false, true, T + 1, T) then return false, "non-officer author" end
        -- Envelope sender not on the roster rejects.
        if Recruitment:_AcceptConfig("GUILD", true, false, T + 1, T) then return false, "non-guildmate sender" end
        -- Stale stamp rejects (a relay cannot roll the ad back).
        if Recruitment:_AcceptConfig("GUILD", true, true, T - 1, T) then return false, "stale must reject" end
        return true
    end)
    S:Register("recruit.disable_convergence", function()
        -- A later disable (T_disable > T_enable) is accepted over a stale enable,
        -- so a member who was offline at disable time converges when they pull.
        local tEnable, tDisable = 100, 200
        if not Recruitment:_AcceptConfig("GUILD", true, true, tDisable, tEnable) then
            return false, "disable must win over stale enable"
        end
        return true
    end)
    S:Register("recruit.send_gap", function()
        if not Recruitment:_CanSendNow(nil, 0, 30) then return false, "first send allowed" end
        if Recruitment:_CanSendNow(100, 129, 30) then return false, "29s < 30s must block" end
        if not Recruitment:_CanSendNow(100, 130, 30) then return false, "exactly 30s allowed" end
        if not Recruitment:_CanSendNow(100, 200, 30) then return false, "well past gap allowed" end
        return true
    end)
    S:Register("recruit.auto_cap", function()
        if not Recruitment:_AutoShouldContinue(0, 40) then return false, "0 of 40 continues" end
        if not Recruitment:_AutoShouldContinue(39, 40) then return false, "39 of 40 continues" end
        if Recruitment:_AutoShouldContinue(40, 40) then return false, "40 of 40 stops" end
        if Recruitment:_AutoShouldContinue(41, 40) then return false, "over cap stops" end
        return true
    end)
end

----------------------------------------------------------------------
-- Auto-invite: whisper hook + invite flow
----------------------------------------------------------------------
function Recruitment:RegisterAutoInviteEvent()
    local f = CreateFrame("Frame")
    BRutus.Compat.RegisterEvent(f, "CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        if BRutus.Compat.IsSecret(msg, author) then return end  -- chat in lockdown: nothing readable
        local cfg = BRutus.db.recruitment and BRutus.db.recruitment.autoInvite
        if not cfg or not cfg.enabled then return end
        if not CanGuildInvite() then return end
        if not Recruitment:_MatchKeyword(msg, cfg.keyword) then return end
        local sender = author and (author:match("^([^-]+)") or author)
        if sender and sender ~= "" then
            Recruitment:_HandleKeywordWhisper(sender, author)
        end
    end)
end

-- An invite the whisper earned. On WoW: Forever the game only invites from a click, so the
-- name waits in the auto-invite popup for the officer (issue #61); elsewhere it goes now.
-- `full` is the name exactly as the whisper carried it, which is what an Alt-click's link
-- invites with; Forever invites with it.
function Recruitment:_DoInvite(name, full)
    if BRutus.Compat.NeedsClick() then
        self:QueueInvite(name, full)
        return
    end
    self:_InviteNow(name)
end

function Recruitment:_InviteNow(name, full)
    local cfg = BRutus.db.recruitment.autoInvite
    GuildInvite(full or name)
    if BRutus.RecruitEngagement then BRutus.RecruitEngagement:RecordInvite(name) end
    self:_MarkInvited(name, GetServerTime(), cfg.cooldownSec)
    BRutus:Print(string.format(L["Auto-invited |cffFFFFFF%s|r to the guild."], name))
end

function Recruitment:_HandleKeywordWhisper(sender, author)
    local cfg = BRutus.db.recruitment.autoInvite
    -- Ban gate (BanList already alerts on a banned whisper)
    if BRutus.BanList and BRutus.BanList:IsBanned(sender) then return end
    -- Cooldown
    if self:_OnInviteCooldown(sender, GetServerTime()) then return end
    -- Filters need a /who, which Forever runs only from a click: there the officer's click on
    -- the popup is the check, and the filters stay for Anniversary.
    local filtered = (cfg.minLevel or 0) > 0 or (cfg.classes and next(cfg.classes) ~= nil)
    if filtered and not BRutus.Compat.NeedsClick() then
        self:_QualifyAndInvite(sender)
    else
        self:_DoInvite(sender, author)
    end
end

----------------------------------------------------------------------
-- What waits for a click on WoW: Forever (issue #61): the welcome for whoever joined, and the
-- invites whispers asked for. A queue each, so a burst of joins or whispers is one popup.
----------------------------------------------------------------------
local function addOnce(list, name, entry)
    for _, n in ipairs(list) do
        if (type(n) == "table" and n.name or n) == name then return false end
    end
    list[#list + 1] = entry or name
    return true
end

function Recruitment:QueueWelcome(name)
    self._pendingWelcomes = self._pendingWelcomes or {}
    addOnce(self._pendingWelcomes, name)
    self:ShowWelcomePopup()
end

-- The click: one welcome in guild chat for everyone waiting. False when nobody is.
function Recruitment:SendPendingWelcome()
    local list = self._pendingWelcomes
    local msg = BRutus.db.recruitment and BRutus.db.recruitment.welcomeMessage
    if not list or #list == 0 or not msg or msg == "" then return false end
    SendChatMessage(msg, "GUILD")
    BRutus:Print(L["Welcome message sent for |cffFFFFFF"] .. table.concat(list, ", ") .. L["|r in guild chat."])
    self._pendingWelcomes = {}
    return true
end

function Recruitment:DismissPendingWelcome()
    self._pendingWelcomes = {}
end

function Recruitment:QueueInvite(name, full)
    self._pendingInvites = self._pendingInvites or {}
    if addOnce(self._pendingInvites, name, { name = name, full = full }) then
        BRutus:Print(string.format(L["|cffFFFFFF%s|r whispered the keyword: invite them from the popup."], name))
    end
    self:ShowInvitePopup()
end

-- The click: invite the one the popup shows, and only that one: on Forever the click is the
-- only check there is. If they were banned since they were queued (a ban can arrive from
-- another officer meanwhile) or already invited, they are dropped and the next waits for its
-- own click. Returns how many are left.
function Recruitment:InviteNext()
    local list = self._pendingInvites or {}
    local cfg = BRutus.db.recruitment and BRutus.db.recruitment.autoInvite
    local e = table.remove(list, 1)
    if not (e and cfg) then return #list end
    if BRutus.BanList and BRutus.BanList:IsBanned(e.name) then
        BRutus:Print(string.format(L["|cffFFFFFF%s|r is banned: not invited."], e.name))
    elseif not self:_OnInviteCooldown(e.name, GetServerTime()) then
        self:_InviteNow(e.name, e.full)
    end
    return #list
end

-- Skipped: not invited, and not asked about again until the cooldown runs out.
function Recruitment:SkipNext()
    local list = self._pendingInvites or {}
    local e = table.remove(list, 1)
    local cfg = BRutus.db.recruitment and BRutus.db.recruitment.autoInvite
    if e and cfg then self:_MarkInvited(e.name, GetServerTime(), cfg.cooldownSec) end
    return #list
end

-- Async /who lookup, one query at a time. Fail-safe: on timeout / no result,
-- apply whoFallback ("skip" = do NOT invite).
function Recruitment:_QualifyAndInvite(sender)
    if self._whoBusy then
        -- one lookup at a time; drop extra concurrent triggers (cooldown will let them retry)
        return
    end
    self._whoBusy = sender
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() Recruitment:_OnWhoResult() end)
    end
    BRutus.Compat.RegisterEvent(self._whoFrame, "WHO_LIST_UPDATE")
    BRutus.Compat.SetWhoToUI(true)   -- results to the API, not the Social frame
    BRutus.Compat.SendWho(BRutus.Compat.WhoExact(sender))
    -- Timeout: /who is throttled; give it 6s then fail-safe.
    BRutus.Compat.After(6, function()
        if Recruitment._whoBusy == sender then Recruitment:_FinishWho(sender, nil) end
    end)
end

function Recruitment:_OnWhoResult()
    local sender = self._whoBusy
    if not sender then return end
    local info
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName and (w.fullName:match("^([^-]+)") or w.fullName) == sender then
                info = { level = w.level, class = w.filename }
                break
            end
        end
    end
    self:_FinishWho(sender, info)
end

function Recruitment:_FinishWho(sender, info)
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    BRutus.Compat.SetWhoToUI(false)
    self._whoBusy = nil
    local cfg = BRutus.db.recruitment.autoInvite
    -- Re-check cooldown/ban in case time passed.
    if BRutus.BanList and BRutus.BanList:IsBanned(sender) then return end
    if self:_OnInviteCooldown(sender, GetServerTime()) then return end
    if info then
        if self:_PassesFilters(info, cfg) then self:_DoInvite(sender) end
    else
        -- couldn't confirm → fail-safe
        if cfg.whoFallback == "invite" then self:_DoInvite(sender) end
    end
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function Recruitment:Initialize()
    -- Ensure DB settings exist
    if not BRutus.db.recruitment then
        BRutus.db.recruitment = BRutus:DeepCopy(self.DEFAULT_SETTINGS)
    end
    local r = BRutus.db.recruitment
    -- Fill missing keys
    for k, v in pairs(self.DEFAULT_SETTINGS) do
        if r[k] == nil then
            if type(v) == "table" then
                r[k] = BRutus:DeepCopy(v)
            else
                r[k] = v
            end
        end
    end

    -- Auto-invite config (fill missing keys the same way)
    r.autoInvite = r.autoInvite or {}
    for k, v in pairs(self.AUTOINVITE_DEFAULTS) do
        if r.autoInvite[k] == nil then
            r.autoInvite[k] = (type(v) == "table") and BRutus:DeepCopy(v) or v
        end
    end
    self:_DropUnknownClasses(r.autoInvite.classes)
    self._inviteCd = {}
    self:_RegisterAutoInviteTests()

    -- Set default channels if empty
    if #r.channels == 0 then
        r.channels = { "LookingForGroup" }
    end

    -- Set default message if empty
    if r.message == "" then
        local guildName = GetGuildInfo("player") or L["our guild"]
        r.message = guildName .. L[" is recruiting! All classes and roles welcome. Whisper me for info or invite!"]
    end

    -- Hook right-click menu for guild invite
    self:HookChatInvite()

    -- Set default welcome message if empty
    if r.welcomeMessage == "" then
        local guildName = GetGuildInfo("player") or L["our guild"]
        if r.discord ~= "" then
            r.welcomeMessage = L["Welcome to "] .. guildName .. L["! Join our Discord: "] .. r.discord .. L[" - Have fun!"]
        else
            r.welcomeMessage = L["Welcome to "] .. guildName .. L[" - Have fun!"]
        end
    end

    -- Listen for new guild members joining
    self:RegisterWelcomeEvent()

    -- Listen for keyword whispers requesting an auto-invite
    self:RegisterAutoInviteEvent()

    -- Resume if was enabled
    if r.enabled and self:CanUseRecruitment() then
        self:StartAutoRecruit()
    end
end

----------------------------------------------------------------------
-- Permission check: is the player officer or above?
----------------------------------------------------------------------
function Recruitment:CanUseRecruitment()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if not rankIndex then return false end
    return rankIndex <= (BRutus.db.recruitment.minRankIndex or 2) or CanGuildInvite()
end

----------------------------------------------------------------------
-- Start automatic recruitment
----------------------------------------------------------------------
function Recruitment:StartAutoRecruit()
    if not self:CanUseRecruitment() then
        BRutus:Print(L["|cffFF4444You don't have permission to use recruitment.|r"])
        return false
    end

    local settings = BRutus.db.recruitment
    settings.enabled = true

    -- Stop existing ticker
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    local interval = math.max(settings.interval, 60) -- minimum 60s safety

    -- NOTE: SendChatMessage("CHANNEL") requires a hardware event (Blizzard restriction).
    -- We show a clickable popup instead of sending automatically.
    self.ticker = C_Timer.NewTicker(interval, function()
        self:ShowSendPopup()
    end)

    -- Show first popup after a short delay
    C_Timer.After(2, function()
        self:ShowSendPopup()
    end)

     BRutus:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    -- Push the (now enabled) config to guild members so they can help spread it.
    self:BroadcastStatus(true)
    return true
end

----------------------------------------------------------------------
-- Stop automatic recruitment
----------------------------------------------------------------------
function Recruitment:StopAutoRecruit()
    BRutus.db.recruitment.enabled = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.popupFrame then
        self.popupFrame:Hide()
    end
    -- Push the disabled state so members stop spreading it (newest wins).
    if BRutus:IsOfficer() then self:BroadcastStatus(true) end
    BRutus:Print(L["Recruitment |cffFF4444stopped|r."])
end

----------------------------------------------------------------------
-- Toggle recruitment
----------------------------------------------------------------------
function Recruitment:Toggle()
    if BRutus.db.recruitment.enabled then
        self:StopAutoRecruit()
    else
        self:StartAutoRecruit()
    end
    return BRutus.db.recruitment.enabled
end

----------------------------------------------------------------------
-- Broadcast recruitment status (class needs, discord, message) to all
-- guild members who have Guild OS installed.
----------------------------------------------------------------------
-- reassert=true re-pushes the CURRENT config with its EXISTING updatedAt (an
-- idempotent re-broadcast); reassert false/nil is a genuine edit and stamps
-- time() as the new "last content edit". Keeping the stamp on a re-push means
-- newest-wins never mistakes a re-broadcast for a newer edit, so a re-push can
-- refresh a stale member without ever clobbering a genuinely newer change.
function Recruitment:BroadcastStatus(quiet, reassert)
    if not BRutus.CommSystem or not IsInGuild() then return end
    if not (BRutus.IsOfficer and BRutus:IsOfficer()) then return end
    local r = BRutus.db.recruitment
    if not (reassert and r.updatedAt) then
        r.updatedAt = time()   -- genuine edit: stamp "last content edit"
    end
    local payload = LibStub("LibSerialize"):Serialize({
        enabled    = r.enabled,
        discord    = r.discord or "",
        message    = r.message or "",
        channels   = r.channels or {},
        interval   = r.interval or 120,
        updatedBy  = BRutus.Compat.PlayerName(),
        updatedAt  = r.updatedAt,
    })
    BRutus.CommSystem:SendMessage("RI", payload)
    -- Mirror into the guild-synced slot so this account's own member-rank alts
    -- (they share the per-guild DB) get the ad immediately, with no round-trip.
    BRutus.db.guildRecruitment = {
        enabled = r.enabled, discord = r.discord or "", message = r.message or "",
        channels = r.channels or {}, interval = r.interval or 120,
        updatedAt = r.updatedAt, updatedBy = BRutus.Compat.PlayerName(),
    }
    if not quiet then BRutus:Print(L["Recruitment status broadcast to guild members."]) end
end

----------------------------------------------------------------------
-- Member auto-send: opt-in ticker using guild-broadcast config
----------------------------------------------------------------------
function Recruitment:StartMemberRecruit(quiet)
    local info = BRutus.db.guildRecruitment
    if not info or not info.message or info.message == "" then
        if not quiet then
            BRutus:Print(L["|cffFF4444No recruitment data received yet. Ask an officer to broadcast.|r"])
        end
        return false
    end
    if self.memberTicker then self.memberTicker:Cancel() end
    local interval = math.max(info.interval or 120, 60)
    self.memberTicker = C_Timer.NewTicker(interval, function() Recruitment:_AutoTick() end)
    C_Timer.After(2, function() Recruitment:_AutoTick() end)
    if not quiet then
        BRutus:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    end
    return true
end

-- One tick of the member AUTO popup. Enforces the per-session cap so a member
-- can never be nagged into a Blizzard silence: after AUTO_SESSION_CAP popups it
-- self-pauses the ticker and says so once. The manual "Send Now" button calls
-- ShowSendPopup directly and never routes through here, so it is never capped.
function Recruitment:_AutoTick()
    if not self:_AutoShouldContinue(self._autoPopups or 0, self.AUTO_SESSION_CAP) then
        self._autoCapReached = true
        if self.memberTicker then self.memberTicker:Cancel(); self.memberTicker = nil end
        if self.popupFrame then self.popupFrame:Hide() end
        BRutus:Print(L["Auto recruit paused for this session (limit reached). Re-enable it from the Recruitment tab."])
        return
    end
    self._autoPopups = (self._autoPopups or 0) + 1
    self:ShowSendPopup()
end

function Recruitment:StopMemberRecruit()
    if self.memberTicker then
        self.memberTicker:Cancel()
        self.memberTicker = nil
    end
    if self.popupFrame then self.popupFrame:Hide() end
    BRutus:Print(L["Recruitment |cffFF4444stopped|r."])
end

function Recruitment:IsMemberRecruitActive()
    return self.memberTicker ~= nil
end

----------------------------------------------------------------------
-- Guild-wide sharing + opt-OUT participation
--
-- The officer's config is relayed member-to-member (not just pushed once by
-- the officer), so alts and late-loggers reliably end up with it. Helping is
-- opt-out: db.recruitParticipate is nil when the member has never touched it
-- (they participate by default so a recruiting guild actually gets help),
-- true when explicitly kept on, and false when the member opted out. The
-- choice is remembered across sessions. There is no join prompt: the member
-- leaves any time with the Auto-Send toggle in the Recruitment tab.
----------------------------------------------------------------------

-- Re-share the guild's recruitment config in response to a sync REQUEST.
-- Officers send their own authoritative copy; members relay the cached one so
-- the ad reaches newcomers even when no officer is online.
function Recruitment:RespondToSync()
    if not BRutus.CommSystem or not IsInGuild() then return end
    if BRutus:IsOfficer() then
        local r = BRutus.db.recruitment
        -- Re-assert the current ad REGARDLESS of enabled, so a stale-enabled
        -- member who pulls converges onto a later disable. reassert=true keeps
        -- the existing stamp: idempotent, and it can never roll a newer edit back.
        if r and r.updatedAt then self:BroadcastStatus(true, true) end
        return
    end
    local info = BRutus.db.guildRecruitment
    -- Members relay the cached ad REGARDLESS of enabled so a disabled state
    -- still spreads member-to-member with no officer online. Gate on it being a
    -- real received ad, and carry its EXISTING updatedBy/updatedAt unchanged.
    if info and info.updatedAt and info.updatedBy and info.message and info.message ~= "" then
        local payload = LibStub("LibSerialize"):Serialize({
            enabled = info.enabled, discord = info.discord or "", message = info.message or "",
            channels = info.channels or {}, interval = info.interval or 120,
            updatedBy = info.updatedBy, updatedAt = info.updatedAt,
        })
        BRutus.CommSystem:SendMessage("RI", payload)
    end
end

-- Apply an incoming config (direct officer broadcast OR a member relay).
--
-- Identity is bound to the comm ENVELOPE, never the payload body (the bug class
-- already fixed for ALT_LINK and SELF_ALT). Trust rule, all four required:
--   1. the message arrived over GUILD (channel arg from the addon event),
--   2. the CLAIMED author (info.updatedBy) is a current officer (attribution),
--   3. the envelope SENDER is a current guildmate (the officer, or a relayer),
--   4. it is not older than what we hold (newest-wins; a relay can't roll back).
--
-- Residual risk, accepted on purpose because we keep the member-to-member relay:
-- a malicious CURRENT guildmate can still forge info.updatedBy to a real
-- officer's name and push arbitrary content over GUILD. We cannot distinguish a
-- genuine relay from a forged one without a signature, and dropping the relay
-- would break the "config stays alive with no officer online" requirement. That
-- residual is capped by the Task 3 content policy on the receiving side
-- (sanitize + 30s send gap + per-session popup cap + 60s interval floor + the
-- consent popup), so a forged ad cannot silently spam or inject chat escapes
-- under a member's name. updatedBy is stored as the CLAIMED author, for display.
-- One more axis the content policy does NOT cover: newest-wins trusts the
-- payload updatedAt, so a forged FUTURE stamp would pin the ad and freeze out a
-- real officer's later edit (their time() stamp being smaller). We clamp
-- incomingAt to now + a small slack so a far-future value cannot outlast a
-- genuine update.
local FUTURE_SLACK = 300   -- accept at most 5 min of clock skew ahead of us
function Recruitment:ApplyIncoming(info, sender, channel)
    if type(info) ~= "table" then return end
    local claimedAuthor = (info.updatedBy and info.updatedBy ~= "" and info.updatedBy) or sender
    local claimedAuthorIsOfficer =
        (BRutus.IsOfficerByName and BRutus:IsOfficerByName(claimedAuthor)) or false
    local senderIsGuildmate = self:_IsGuildmate(sender)
    local incomingAt = math.min(tonumber(info.updatedAt) or 0, time() + FUTURE_SLACK)
    local cur = BRutus.db.guildRecruitment
    local curAt = cur and cur.updatedAt or nil
    if not self:_AcceptConfig(channel, claimedAuthorIsOfficer, senderIsGuildmate, incomingAt, curAt) then
        return
    end
    BRutus.db.guildRecruitment = {
        enabled   = info.enabled,
        discord   = info.discord or "",
        message   = info.message or "",
        channels  = info.channels or {},
        interval  = info.interval or 120,
        updatedAt = incomingAt > 0 and incomingAt or time(),
        updatedBy = claimedAuthor,
    }
    if BRutus.recruitmentPanelRefresh then BRutus.recruitmentPanelRefresh() end
    self:SyncMemberParticipation()
end

-- Member opt-out choice (persisted). nil = never touched, true = kept on,
-- false = opted out.
function Recruitment:SetParticipation(v)
    BRutus.db.recruitParticipate = v
    if v ~= false then
        -- A manual re-enable clears any per-session auto-pause and popup count,
        -- so turning Auto-Send back on from the tab actually resumes popups.
        self._autoCapReached = false
        self._autoPopups = 0
    end
    self:SyncMemberParticipation()
end

-- Pure opt-out semantics for a stored choice: nil (untouched) and true both
-- participate; only an explicit false opts out. Kept separate so a self test
-- pins the nil-counts-as-participating rule the whole change hinges on.
function Recruitment:_ParticipatingFrom(choice)
    return choice ~= false
end

-- Opt-out: a member helps unless they explicitly turned it off.
function Recruitment:IsParticipating()
    return self:_ParticipatingFrom(BRutus.db.recruitParticipate)
end

-- Reconcile the member popup ticker with the current guild config and the
-- stored choice. Safe to call repeatedly.
function Recruitment:SyncMemberParticipation()
    if BRutus:IsOfficer() then return end   -- officers use their own flow
    local info = BRutus.db.guildRecruitment
    local active = info and info.enabled and info.message and info.message ~= ""
    if not active or not self:IsParticipating() then
        if self:IsMemberRecruitActive() then self:StopMemberRecruit() end
        return
    end
    -- Self-paused for the session after hitting the popup cap: stay stopped
    -- until the member manually re-enables (SetParticipation clears the flag),
    -- so a routine re-sync never re-nags a member who was already capped.
    if self._autoCapReached then return end
    if not self:IsMemberRecruitActive() then
        self:StartMemberRecruit(true)   -- quiet: no per-login "started" spam
        self:_HintOptOutOnce()
    end
end

-- The first time auto-participation kicks in for a member who never chose,
-- tell them once (persisted) how to opt out, so the popups are never a mystery.
function Recruitment:_HintOptOutOnce()
    if BRutus.db.recruitParticipate ~= nil then return end
    if BRutus.db.recruitOptOutHinted then return end
    BRutus.db.recruitOptOutHinted = true
    BRutus:Print(L["Your guild is recruiting and you're set to help post it. Turn this off with the Auto-Send toggle in the Recruitment tab."])
end

----------------------------------------------------------------------
-- Member-side setup — runs for EVERY player (unlike the officer-only
-- Initialize). Reconciles participation against the persisted/synced config on
-- login. Opt-out: unless the member turned it off, they auto-fire the recruit
-- popup once the guild is recruiting, without any officer action on their
-- client and without a join prompt.
----------------------------------------------------------------------
function Recruitment:InitParticipation()
    C_Timer.After(15, function()
        if BRutus.Recruitment then BRutus.Recruitment:SyncMemberParticipation() end
    end)
end

----------------------------------------------------------------------
-- Which config drives the popup/send: officers post their own configured ad,
-- members post the guild-broadcast (relayed) copy. Returns the settings table
-- or nil.
----------------------------------------------------------------------
function Recruitment:_ActiveConfig()
    return BRutus:IsOfficer() and BRutus.db.recruitment or BRutus.db.guildRecruitment
end

-- Configured channel names, and how many of them the player has actually joined
-- right now. GetChannelName returns 0 for a channel the player is not in, so
-- with zero joined there is nothing to post to.
function Recruitment:_ResolveChannels(settings)
    local names, joined = {}, 0
    for _, ch in ipairs(settings and settings.channels or {}) do
        names[#names + 1] = ch
        local num = GetChannelName(ch)
        if num and num > 0 then joined = joined + 1 end
    end
    return names, joined
end

----------------------------------------------------------------------
-- Create the consent popup (one-time). Shows the actual target channel and the
-- message text so the member consents to real content, not a blind click.
----------------------------------------------------------------------
function Recruitment:CreatePopupFrame()
    if self.popupFrame then return end

    local C  = BRutus.Colors
    local UI = BRutus.UI
    local PAD, WIDTH = 14, 360
    local cw = WIDTH - PAD * 2

    local f = CreateFrame("Frame", "BRutusRecruitPopup", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 150)
    f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.082, 0.082, 0.105, 0.97)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    f:SetFrameStrata("DIALOG")
    UI:StylePopup(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    -- Title: brand + localized subtitle ("Guild OS  ·  Recruitment").
    local title = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(title, 13)
    title:SetPoint("TOPLEFT", PAD, -12)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText("Guild OS  |cff6c6c78" .. L["Recruitment"] .. "|r")

    local sep = UI:CreateSeparator(f)
    sep:SetPoint("TOPLEFT", PAD, -30)
    sep:SetPoint("TOPRIGHT", -PAD, -30)

    -- x dismiss (top-right).
    local dismiss = CreateFrame("Button", nil, f)
    dismiss:SetSize(20, 20)
    dismiss:SetPoint("TOPRIGHT", -4, -6)
    local dText = dismiss:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(dText, 14)
    dText:SetPoint("CENTER")
    dText:SetText("x")
    dText:SetTextColor(0.6, 0.6, 0.6)
    dismiss:SetScript("OnEnter", function() dText:SetTextColor(1, 0.3, 0.3) end)
    dismiss:SetScript("OnLeave", function() dText:SetTextColor(0.6, 0.6, 0.6) end)
    dismiss:SetScript("OnClick", function() f:Hide() end)

    -- Target channel line.
    local channelLine = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(channelLine, 11)
    channelLine:SetPoint("TOPLEFT", PAD, -38)
    channelLine:SetWidth(cw)
    channelLine:SetJustifyH("LEFT")
    channelLine:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    f.channelLine = channelLine

    -- Message preview (wrapped; sized in ShowSendPopup).
    local msgText = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(msgText, 12)
    msgText:SetPoint("TOPLEFT", PAD, -58)
    msgText:SetWidth(cw)
    msgText:SetJustifyH("LEFT")
    msgText:SetTextColor(C.text.r, C.text.g, C.text.b)
    f.msgText = msgText

    -- "Join a channel" hint, shown instead of a dead Postar when nothing is joined.
    local hint = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(hint, 11)
    hint:SetWidth(cw)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(C.red.r, C.red.g, C.red.b)
    hint:Hide()
    f.hint = hint

    -- Postar (the send): a hardware OnClick so SendChatMessage to a channel works.
    local postBtn = UI:CreateButton(f, L["Post"], 120, 26)
    postBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 14)
    postBtn:SetBaseColor(C.online.r * 0.30, C.online.g * 0.30, C.online.b * 0.30, 0.9)
    postBtn:SetScript("OnClick", function()
        Recruitment:DoSendRecruitmentMessage()
        f:Hide()
    end)
    f.postBtn = postBtn

    -- "Agora nao" / dismiss.
    local laterBtn = UI:CreateButton(f, L["Not now"], 120, 26)
    laterBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 14)
    laterBtn:SetScript("OnClick", function() f:Hide() end)
    f.laterBtn = laterBtn

    self.popupFrame = f
end

----------------------------------------------------------------------
-- The popups that carry a click on WoW: Forever (issue #61), in the recruit popup's style:
-- a title, a line, a note, and two buttons whose OnClick is the hardware event the game wants.
----------------------------------------------------------------------
local function ActionPopup(title, y, okText, laterText)
    local C, UI = BRutus.Colors, BRutus.UI
    local PAD, WIDTH = 14, 360
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 120)
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.082, 0.082, 0.105, 0.97)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    f:SetFrameStrata("DIALOG")
    UI:StylePopup(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(t, 13)
    t:SetPoint("TOPLEFT", PAD, -12)
    t:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    t:SetText("Guild OS  |cff6c6c78" .. title .. "|r")
    local sep = UI:CreateSeparator(f)
    sep:SetPoint("TOPLEFT", PAD, -30)
    sep:SetPoint("TOPRIGHT", -PAD, -30)

    f.line = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.line, 12)
    f.line:SetPoint("TOPLEFT", PAD, -38)
    f.line:SetWidth(WIDTH - PAD * 2)
    f.line:SetJustifyH("LEFT")
    f.line:SetTextColor(C.text.r, C.text.g, C.text.b)

    f.note = f:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(f.note, 10)
    f.note:SetPoint("TOPLEFT", f.line, "BOTTOMLEFT", 0, -4)
    f.note:SetWidth(WIDTH - PAD * 2)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    f.okBtn = UI:CreateButton(f, okText, 140, 26)
    f.okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 12)
    f.okBtn:SetBaseColor(C.online.r * 0.30, C.online.g * 0.30, C.online.b * 0.30, 0.9)
    f.laterBtn = UI:CreateButton(f, laterText, 140, 26)
    f.laterBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 12)
    -- Grow to the text, like the recruit popup: the note is the line the click posts.
    function f:Fit()
        self:SetHeight(38 + self.line:GetStringHeight() + 4 + self.note:GetStringHeight() + 12 + 26 + 12)
    end
    return f
end

function Recruitment:ShowWelcomePopup()
    local f = self.welcomePopup
    if not f then
        -- Below the recruit popup (TOP -80), which grows with a long ad.
        f = ActionPopup(L["Welcome"], -300, L["Send welcome"], L["Dismiss"])
        f.okBtn:SetScript("OnClick", function() Recruitment:SendPendingWelcome(); f:Hide() end)
        f.laterBtn:SetScript("OnClick", function() Recruitment:DismissPendingWelcome(); f:Hide() end)
        self.welcomePopup = f
    end
    local list = self._pendingWelcomes or {}
    if #list == 0 then f:Hide() return end
    f.line:SetText(string.format(L["|cffFFFFFF%s|r joined the guild."], table.concat(list, ", ")))
    f.note:SetText((BRutus.db.recruitment and BRutus.db.recruitment.welcomeMessage) or "")
    f:Fit()
    f:Show()
    -- An invite popup already up moves under this one instead of being covered by it.
    if self.invitePopup and self.invitePopup:IsShown() then self:ShowInvitePopup() end
end

function Recruitment:ShowInvitePopup()
    local f = self.invitePopup
    if not f then
        f = ActionPopup(L["Auto-Invite"], -300, L["Invite"], L["Skip"])
        f.okBtn:SetScript("OnClick", function() Recruitment:InviteNext(); Recruitment:ShowInvitePopup() end)
        f.laterBtn:SetScript("OnClick", function() Recruitment:SkipNext(); Recruitment:ShowInvitePopup() end)
        self.invitePopup = f
    end
    local list = self._pendingInvites or {}
    if #list == 0 then f:Hide() return end
    local line = string.format(L["|cffFFFFFF%s|r whispered the keyword."], list[1].name)
    if #list > 1 then line = line .. " " .. string.format(L["(+%d waiting)"], #list - 1) end
    f.line:SetText(line)
    f.note:SetText(L["On WoW: Forever the game only invites from a click, and level and class are not checked."])
    f:Fit()
    if not f.moved then
        f:ClearAllPoints()
        local w = self.welcomePopup
        if w and w:IsShown() then
            f:SetPoint("TOP", w, "BOTTOM", 0, -8)
        else
            f:SetPoint("TOP", UIParent, "TOP", 0, -300)
        end
    end
    f:Show()
end

----------------------------------------------------------------------
-- Show the consent popup, populated from the active config.
----------------------------------------------------------------------
function Recruitment:ShowSendPopup()
    if InCombatLockdown() then return end

    -- Officers use their own config; members use the guild-broadcast config.
    local settings = self:_ActiveConfig()
    if BRutus:IsOfficer() then
        if not settings or not settings.enabled then return end
    else
        if not settings or not settings.enabled or not settings.message or settings.message == "" then return end
    end
    local raw = settings.message
    if not raw or raw == "" then return end

    self:CreatePopupFrame()
    local f = self.popupFrame
    local PAD = 14

    -- Channel line.
    local names, joined = self:_ResolveChannels(settings)
    local chLabel = (#names > 0) and table.concat(names, ", ") or "-"
    f.channelLine:SetText(string.format(L["Post to channel: %s"], chLabel))

    -- Message preview == exactly what DoSendRecruitmentMessage will post (same
    -- source, same sanitize, same MSG_MAX cap), so the member consents to the
    -- real content with no hidden tail (a channel that hides raid icons gets it without
    -- their codes, issue #64). The frame auto-sizes to the wrapped text.
    local full = BRutus:SanitizeUserText(raw, self.MSG_MAX)
    f.msgText:SetText("\"" .. full .. "\"")

    -- Layout: size the frame to the wrapped message, then the button row (or the
    -- join-channel hint if nothing is joined).
    local y = 58 + math.max(f.msgText:GetStringHeight() or 14, 14) + 12
    if joined == 0 then
        f.hint:ClearAllPoints()
        f.hint:SetPoint("TOPLEFT", PAD, -y)
        f.hint:SetText(L["Join a channel to post the recruitment message."])
        f.hint:Show()
        y = y + math.max(f.hint:GetStringHeight() or 14, 14) + 12
        f.postBtn:Hide()
    else
        f.hint:Hide()
        f.postBtn:Show()
    end
    f:SetHeight(y + 26 + 14)
    f:Show()

    -- Auto-hide after 30s if not acted on.
    C_Timer.After(30, function()
        if self.popupFrame and self.popupFrame:IsShown() then
            self.popupFrame:Hide()
        end
    end)
end

----------------------------------------------------------------------
-- Actually send the message (called from the Postar button = hardware event).
----------------------------------------------------------------------
function Recruitment:DoSendRecruitmentMessage()
    if not IsInGuild() then return end

    -- Min send gap: refuse a send too soon after the last one. Covers reflexive
    -- rapid clicking and any forged low interval. Silent no-op when throttled.
    if not self:_CanSendNow(self._lastSendAt, GetTime(), self.SEND_MIN_GAP) then return end

    -- Officers use their own config; members use the guild-broadcast config.
    local settings = self:_ActiveConfig()
    if not settings then
        BRutus:Print(L["|cffFF4444No recruitment data. Ask an officer to broadcast.|r"])
        return
    end
    local msg = settings.message
    if not msg or msg == "" then
        BRutus:Print(L["|cffFF4444No recruitment message set.|r"])
        return
    end
    -- Sanitize before it ever reaches a public channel under the player's name:
    -- strip chat escapes (textures / unterminated colour / fake links) and cap
    -- at the SendChatMessage limit. Officer and member paths alike. Same cap the
    -- consent popup previewed, so the member posts exactly what they saw (minus raid-icon
    -- codes where the channel would show them as text, issue #64).
    msg = BRutus:SanitizeUserText(msg, self.MSG_MAX)
    if msg == "" then
        BRutus:Print(L["|cffFF4444No recruitment message set.|r"])
        return
    end

    local sent, iconsOnly = false, false
    for _, channelName in ipairs(settings.channels or {}) do
        local channelNum = GetChannelName(channelName)
        if channelNum and channelNum > 0 then
            -- Where the server hides raid icons, the copy goes without their codes (issue #64).
            local text = BRutus.Compat.ChannelHidesRaidIcons(channelName, channelNum) and self:_StripRaidIcons(msg) or msg
            if text ~= "" then
                SendChatMessage(text, "CHANNEL", nil, channelNum)
                sent = true
            else
                iconsOnly = true
            end
        end
    end

    if sent then
        self._lastSendAt = GetTime()
        self.lastSend = GetTime()
        if BRutus.RecruitEngagement then BRutus.RecruitEngagement:RecordPost() end
        BRutus:Print(L["Recruitment message sent!"])
    elseif iconsOnly then
        BRutus:Print(L["|cffFF4444The message is only raid icons, which this channel does not show: nothing posted.|r"])
    else
        BRutus:Print(L["|cffFF4444No valid channels found. Join a channel first.|r"])
    end
end

----------------------------------------------------------------------
-- Right-click guild invite (slash command based - no dropdown hook to avoid taint)
-- Usage: /brutus invite PlayerName
----------------------------------------------------------------------
function Recruitment:HookChatInvite()
    -- No dropdown hooks - they cause taint errors.
    -- Guild invite is available via /brutus invite <name>
end

----------------------------------------------------------------------
-- Slash command handler
----------------------------------------------------------------------
function Recruitment:HandleCommand(args)
    local cmd = args[1]
    -- The settings exist once an officer's client has started recruitment; a member's never
    -- has, and every branch below but `invite` reads them.
    if not BRutus.db.recruitment and cmd and cmd ~= "invite" then
        BRutus:Print(L["Recruitment settings are available to officers after login."])
        return
    end

    if cmd == "on" or cmd == "start" then
        self:StartAutoRecruit()
    elseif cmd == "off" or cmd == "stop" then
        self:StopAutoRecruit()
    elseif cmd == "msg" or cmd == "message" then
        table.remove(args, 1)
        local newMsg = table.concat(args, " ")
        if newMsg and newMsg ~= "" then
            BRutus.db.recruitment.message = newMsg
            BRutus:Print(L["Recruitment message set to: |cffFFFFFF"] .. newMsg .. "|r")
        else
            BRutus:Print(L["Current message: |cffFFFFFF"] .. (BRutus.db.recruitment.message or L["(empty)"]) .. "|r")
        end
    elseif cmd == "interval" then
        local secs = tonumber(args[2])
        if secs and secs >= 60 then
            BRutus.db.recruitment.interval = secs
            BRutus:Print(string.format(L["Recruitment interval set to |cffFFFFFF%ds|r."], secs))
            -- Restart if active
            if BRutus.db.recruitment.enabled then
                self:StopAutoRecruit()
                self:StartAutoRecruit()
            end
        else
            BRutus:Print(L["Usage: /guildos recruit interval <seconds> (min 60)"])
        end
    elseif cmd == "channel" then
        local action = args[2]
        local chName = args[3]
        if action == "add" and chName then
            if self:AddChannel(BRutus.db.recruitment.channels, chName) then
                BRutus:Print(L["Added channel: |cffFFFFFF"] .. chName .. "|r")
            else
                BRutus:Print(L["Already posting to: |cffFFFFFF"] .. chName .. "|r")
            end
        elseif action == "remove" and chName then
            if self:RemoveChannel(BRutus.db.recruitment.channels, chName) then
                BRutus:Print(L["Removed channel: |cffFFFFFF"] .. chName .. "|r")
            else
                BRutus:Print(L["Channel not found: "] .. chName)
            end
        elseif action == "list" then
            local list = table.concat(BRutus.db.recruitment.channels, ", ")
            BRutus:Print(L["Channels: |cffFFFFFF"] .. (list ~= "" and list or L["(none)"]) .. "|r")
        else
            BRutus:Print(L["Usage: /guildos recruit channel <add|remove|list> [name]"])
        end
    elseif cmd == "status" then
        local s = BRutus.db.recruitment
        local status = s.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        local wStatus = s.welcomeEnabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        BRutus:Print(L["--- Recruitment Status ---"])
        BRutus:Print(L["Active: "] .. status)
        BRutus:Print(string.format(L["Interval: |cffFFFFFF%ds|r"], s.interval))
        BRutus:Print(L["Channels: |cffFFFFFF"] .. table.concat(s.channels, ", ") .. "|r")
        BRutus:Print(L["Message: |cffFFFFFF"] .. s.message .. "|r")
        BRutus:Print(L["Welcome: "] .. wStatus)
        BRutus:Print(L["Welcome msg: |cffFFFFFF"] .. s.welcomeMessage .. "|r")
        BRutus:Print(L["Discord: |cffFFFFFF"] .. s.discord .. "|r")
    elseif cmd == "welcome" then
        local sub = args[2]
        if sub == "on" then
            BRutus.db.recruitment.welcomeEnabled = true
            BRutus:Print(L["Welcome message |cff4CFF4Cenabled|r."])
        elseif sub == "off" then
            BRutus.db.recruitment.welcomeEnabled = false
            BRutus:Print(L["Welcome message |cffFF4444disabled|r."])
        elseif sub == "msg" then
            table.remove(args, 1)
            table.remove(args, 1)
            local newMsg = table.concat(args, " ")
            if newMsg and newMsg ~= "" then
                BRutus.db.recruitment.welcomeMessage = newMsg
                BRutus:Print(L["Welcome message set to: |cffFFFFFF"] .. newMsg .. "|r")
            else
                BRutus:Print(L["Current: |cffFFFFFF"] .. BRutus.db.recruitment.welcomeMessage .. "|r")
            end
        else
            BRutus:Print(L["Usage: /guildos recruit welcome <on|off|msg> [text]"])
        end
    elseif cmd == "discord" then
        local link = args[2]
        if link and link ~= "" then
            BRutus.db.recruitment.discord = link
            BRutus:Print(L["Discord link set to: |cffFFFFFF"] .. link .. "|r")
        else
            BRutus:Print(L["Discord: |cffFFFFFF"] .. BRutus.db.recruitment.discord .. "|r")
        end
    elseif cmd == "invite" then
        local target = args[2]
        if target and target ~= "" then
            if not CanGuildInvite() then
                BRutus:Print(L["|cffFF4444You don't have permission to invite.|r"])
                return
            end
            GuildInvite(target)
            if BRutus.RecruitEngagement then BRutus.RecruitEngagement:RecordInvite(target) end
            BRutus:Print(L["Guild invite sent to |cffFFFFFF"] .. target .. "|r.")
        else
            BRutus:Print(L["Usage: /guildos recruit invite <PlayerName>"])
        end
    elseif cmd == "autoinvite" or cmd == "ai" then
        table.remove(args, 1)
        Recruitment:HandleAutoInviteCommand(args)
    else
        BRutus:Print(L["|cffFFD700Recruitment commands:|r"])
        BRutus:Print("  /guildos recruit on/off")
        BRutus:Print("  /guildos recruit status")
        BRutus:Print("  /guildos recruit msg <text>")
        BRutus:Print("  /guildos recruit interval <seconds>")
        BRutus:Print("  /guildos recruit channel add/remove/list <name>")
        BRutus:Print("  /guildos recruit welcome on/off/msg <text>")
        BRutus:Print("  /guildos recruit discord <link>")
        BRutus:Print("  /guildos recruit invite <PlayerName>")
    end
end

----------------------------------------------------------------------
-- Auto-invite command handler
----------------------------------------------------------------------
function Recruitment:HandleAutoInviteCommand(args)
    local cfg = BRutus.db.recruitment and BRutus.db.recruitment.autoInvite
    if not cfg then
        BRutus:Print(L["Auto-invite is available to officers after login."])
        return
    end
    local sub = args[1]
    if sub == "on" then
        cfg.enabled = true
        BRutus:Print(L["Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"] .. cfg.keyword .. "|r).")
    elseif sub == "off" then
        cfg.enabled = false
        BRutus:Print(L["Auto-invite |cffFF4444disabled|r."])
    elseif sub == "keyword" then
        local kw = args[2] and self:SetAutoInviteKeyword(cfg, args[2])
        if kw then
            BRutus:Print(L["Auto-invite keyword set to |cffFFFFFF"] .. kw .. "|r.")
        elseif args[2] then
            BRutus:Print(string.format(L["A keyword is one word of up to %d characters."], self.KEYWORD_MAX))
        else
            BRutus:Print(L["Current keyword: |cffFFFFFF"] .. cfg.keyword .. "|r.")
        end
    elseif sub == "minlevel" then
        local n = self:SetAutoInviteMinLevel(cfg, args[2])
        if n then
            BRutus:Print(string.format(L["Auto-invite min level set to |cffFFFFFF%d|r."], n))
        else
            BRutus:Print(string.format(L["Usage: /gos autoinvite minlevel <0-%d>"], BRutus.Client.maxLevel))
        end
    elseif sub == "class" then
        local op, cls = args[2], args[3]
        if op == "clear" then
            cfg.classes = {}
            BRutus:Print(L["Auto-invite class filter cleared."])
        elseif (op == "add" or op == "remove") and cls then
            if self:SetAutoInviteClass(cfg, cls, op == "add") then
                BRutus:Print(L["Auto-invite class filter updated."])
            else
                BRutus:Print(L["Unknown class: "] .. cls .. " (" .. table.concat(self.CLASSES, ", ") .. ")")
            end
        else
            BRutus:Print(L["Usage: /gos autoinvite class <add|remove|clear> <CLASS>"])
        end
    elseif sub == "fallback" then
        if self:SetAutoInviteFallback(cfg, args[2]) then
            BRutus:Print(L["When /who cannot confirm a player: |cffFFFFFF"] .. cfg.whoFallback .. "|r")
        else
            BRutus:Print(L["Usage: /gos autoinvite fallback <skip|invite>"])
        end
    else
        local st = cfg.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        local classes = {}
        for _, c in ipairs(self.CLASSES) do
            if cfg.classes[c] then classes[#classes + 1] = c end
        end
        BRutus:Print(L["Auto-invite: "] .. st .. L[" · keyword: |cffFFFFFF"] .. cfg.keyword ..
            L["|r · min level: |cffFFFFFF"] .. tostring(cfg.minLevel) .. "|r · " .. L["classes: "] ..
            (#classes > 0 and table.concat(classes, ", ") or L["any"]) .. " · " .. L["unconfirmed: "] .. cfg.whoFallback)
        BRutus:Print(L["Usage: /gos autoinvite <on|off|keyword|minlevel|class|fallback|status>"])
        BRutus:Print(string.format(L["Also in the %s tab, under %s."], L["Recruitment"], L["Recruiting"]))
    end
end

----------------------------------------------------------------------
-- Welcome message for new guild members
----------------------------------------------------------------------
function Recruitment:RegisterWelcomeEvent()
    -- Track guild roster to detect new joins
    self._knownMembers = {}
    self._rosterReady = false
    self._welcomedRecently = {}
    self._welcomeIntents   = {}  -- [memberName] = { [officerName] = true, ... }

    -- Build initial roster snapshot
    local function SnapshotRoster()
        local members = {}
        local numMembers = GetNumGuildMembers() or 0
        for i = 1, numMembers do
            local fullName = GetGuildRosterInfo(i)
            if fullName then
                local shortName = fullName:match("^([^-]+)") or fullName
                members[shortName] = true
            end
        end
        return members
    end

    -- Initialize roster snapshot after a delay (guild data needs to load)
    C_Timer.After(8, function()
        Recruitment._knownMembers = SnapshotRoster()
        Recruitment._rosterReady = true
    end)

    local frame = CreateFrame("Frame")
    BRutus.Compat.RegisterEvent(frame, "CHAT_MSG_SYSTEM")
    frame:SetScript("OnEvent", function(_, event, msg)
        if BRutus.Compat.IsSecret(msg) then return end  -- chat in lockdown: nothing readable
        if event ~= "CHAT_MSG_SYSTEM" then return end
        if not IsInGuild() then return end
        if not Recruitment._rosterReady then return end

        -- Detect "%s has joined the guild."
        local joinPattern = ERR_GUILD_JOIN_S and ERR_GUILD_JOIN_S:gsub("%%s", "(.+)") or nil
        local newMember

        if joinPattern then
            newMember = msg:match(joinPattern)
        end

        -- Fallback patterns for PT/EN clients
        if not newMember then
            newMember = msg:match("(.+) entrou na guilda%.")
                     or msg:match("(.+) has joined the guild%.")
        end

        if not newMember then return end

        -- Don't act on our own join.
        local myName = BRutus.Compat.PlayerName()
        if newMember == myName then return end

        -- Credit a recruitment join to whoever invited this player. This runs
        -- regardless of the welcome feature (engagement tracking is independent);
        -- RecordJoin only credits when THIS client has a matching pending invite.
        if BRutus.RecruitEngagement then BRutus.RecruitEngagement:RecordJoin(newMember) end

        -- The welcome message itself is opt-in and gated separately.
        if not BRutus.db.recruitment.welcomeEnabled then return end

        -- Dedup: if already handled on this client, skip
        if Recruitment._welcomedRecently[newMember] then return end
        Recruitment._welcomedRecently[newMember] = true
        C_Timer.After(90, function()
            Recruitment._welcomedRecently[newMember] = nil
            Recruitment._welcomeIntents[newMember]  = nil
        end)

        -- Add to known members
        Recruitment._knownMembers[newMember] = true

        -- Phase 1: broadcast intent immediately so all online officers can collect intents.
        -- After 2 seconds the officer with the lexicographically lowest name wins and sends.
        -- This is deterministic across all clients — no race condition.
        Recruitment._welcomeIntents[newMember] = Recruitment._welcomeIntents[newMember] or {}
        Recruitment._welcomeIntents[newMember][myName] = true

        if BRutus.CommSystem then
            BRutus.CommSystem:SendMessage(
                BRutus.CommSystem.MSG_TYPES.WELCOME_INTENT, newMember, nil, "NORMAL")
        end

        C_Timer.After(2, function()
            -- Already suppressed by a WC claim from another officer?
            if Recruitment._welcomedRecently[newMember .. "_sent"] then return end

            -- Tiebreak: lowest name alphabetically among intents wins
            local intents = Recruitment._welcomeIntents[newMember] or {}
            local winner = myName
            for name in pairs(intents) do
                if name < winner then winner = name end
            end
            if winner ~= myName then return end  -- someone else wins

            Recruitment._welcomedRecently[newMember .. "_sent"] = true

            if BRutus.CommSystem then
                BRutus.CommSystem:SendMessage(
                    BRutus.CommSystem.MSG_TYPES.WELCOME_CLAIM, newMember, nil, "NORMAL")
            end

            local settings = BRutus.db.recruitment
            local welcomeMsg = settings.welcomeMessage
            if welcomeMsg and welcomeMsg ~= "" then
                if BRutus.Compat.NeedsClick() then
                    -- Forever drops a line sent from this timer: the officer's click sends it (#61).
                    -- The claim above already went out, so the other officers stand down: the
                    -- popup stays up until this officer sends or dismisses it.
                    Recruitment:QueueWelcome(newMember)
                else
                    SendChatMessage(welcomeMsg, "GUILD")
                    BRutus:Print(L["Welcome message sent for |cffFFFFFF"] .. newMember .. L["|r in guild chat."])
                end
            end
        end)
    end)
end
