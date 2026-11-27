----------------------------------------------------------------------
-- Guild OS - Recruitment System
-- Automatic recruitment messages + right-click guild invite
-- Only officers (rank index <= 1) or configurable rank can use this
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Recruitment = {}
GuildOS.Recruitment = Recruitment
local L = GuildOS.L

-- This game's classes (used by UI and broadcast): nine, thirteen on retail.
Recruitment.CLASSES = GuildOS.Client.classes

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
    cfg.minLevel = math.max(0, math.min(GuildOS.Client.maxLevel, math.floor(n)))
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
-- The preset channels as each client names them: the game's own ChatChannels table
-- (Anniversary 2.5.6 and Forever 1.60.1). The English names were all the addon knew, and
-- GetChannelName("LookingForGroup") is 0 on a French client (issue #112). A zone channel goes by
-- its shortcut ("Commerce" for "Commerce - Hurlevent"), LookingForGroup by its name: they differ
-- only on Forever in Russian. Forever has no GuildRecruitment channel, and its Spanish
-- LookingForGroup is BuscarGrupo. Retail's table (12.1.5.70448) names both as Forever does and has
-- no GuildRecruitment either (issue #177). Only retail is in Italian (`retail`): Commercio and
-- CercaGruppo; Forever's (1.60.1.70450, 70532) and Anniversary's (2.5.6.70006) itIT rows are the
-- English ones (issue #184).
Recruitment.CHANNELS = {
    { enUS = "Trade", deDE = "Handel", esES = "Comercio", esMX = "Comercio", frFR = "Commerce",
      ptBR = "Comércio", ruRU = "Торговля", koKR = "거래", zhCN = "交易", zhTW = "交易",
      retail = { itIT = "Commercio" } },
    { enUS = "LookingForGroup", deDE = "SucheNachGruppe", esES = "BuscandoGrupo", esMX = "BuscarGrupo",
      frFR = "RechercheDeGroupe", ptBR = "ProcurandoGrupo", ruRU = "ПоискСпутников", koKR = "파티찾기",
      zhCN = "寻求组队", zhTW = "尋求組隊", forever = { esES = "BuscarGrupo", ruRU = "Поиск спутников" },
      retail = { itIT = "CercaGruppo" } },
    { enUS = "GuildRecruitment", deDE = "Gildenrekrutierung", esES = "BuscaHermandad", esMX = "BuscaHermandad",
      frFR = "RecrutementDeGuilde", ptBR = "RecrutamentoDeGuilda", ruRU = "Гильдии", koKR = "길드모집",
      zhCN = "公会招募", zhTW = "公會招募", anniversaryOnly = true },
}

local function channelFor(c)
    local loc = GetLocale and GetLocale() or "enUS"
    return (GuildOS.Client.isRetail and c.retail and c.retail[loc])
        or (not GuildOS.Client.isAnniversary and c.forever and c.forever[loc]) or c[loc] or c.enUS
end

-- This client's preset channels, in order.
function Recruitment:PresetChannels()
    local out = {}
    for _, c in ipairs(self.CHANNELS) do
        if GuildOS.Client.isAnniversary or not c.anniversaryOnly then out[#out + 1] = channelFor(c) end
    end
    return out
end

-- This client's name for a preset channel named in any language: saved before, typed, or sent
-- by an officer on a client in another. Any other channel comes back as it is, and so does a
-- preset this game does not have (on Forever a GuildRecruitment is a channel somebody made).
function Recruitment:ChannelName(name)
    local n = tostring(name or ""):lower()
    for _, c in ipairs(self.CHANNELS) do
        if GuildOS.Client.isAnniversary or not c.anniversaryOnly then
            for _, names in ipairs({ c, c.forever or {}, c.retail or {} }) do
                for _, v in pairs(names) do
                    if type(v) == "string" and v:lower() == n then return channelFor(c) end
                end
            end
        end
    end
    return name
end

local function sameChannel(a, b)
    return Recruitment:ChannelName(a):lower() == Recruitment:ChannelName(b):lower()
end

function Recruitment:HasChannel(list, name)
    for _, c in ipairs(list) do
        if sameChannel(c, name) then return true end
    end
    return false
end

-- The channel `saved` names, as this character has it: its name and number, or the name and 0 when it is not
-- joined. The game is asked by name first (a zone channel answers to its shortcut, "Trade"); then the joined
-- channels are read and compared in any case, so a "LookingforGuild" typed by hand finds the "LookingForGuild"
-- the player is in (#449), and a zone channel's full name ("Trade - City") answers to its shortcut too. A preset
-- named in any language is this client's first (ChannelName).
local function baseName(name)
    return (tostring(name):match("^(.-)%s+%-%s+") or tostring(name)):lower()
end
function Recruitment:ResolveChannel(saved)
    local name = self:ChannelName(strtrim(tostring(saved or "")))
    if name == "" then return name, 0 end
    local Compat = GuildOS.Compat
    local want = name:lower()
    local joined = Compat.JoinedChannels and Compat.JoinedChannels() or {}
    local num = Compat.ChannelId(name)
    if num > 0 then
        for _, ch in ipairs(joined) do
            if ch.num == num and ch.name:lower() == want then return ch.name, num end
        end
        return name, num
    end
    for _, ch in ipairs(joined) do
        if ch.name:lower() == want then return ch.name, ch.num end
    end
    for _, ch in ipairs(joined) do
        if baseName(ch.name) == want then return name, ch.num end
    end
    return name, 0
end

function Recruitment:AddChannel(list, name)
    name = strtrim(tostring(name or ""))
    if name == "" or self:HasChannel(list, name) then return false end
    -- Saved as the game names the channel when the player is in it: "lookingforguild" goes in as "LookingForGuild".
    local real, num = self:ResolveChannel(name)
    if num > 0 and real:lower() == self:ChannelName(name):lower() then name = real end
    list[#list + 1] = name
    return true
end

function Recruitment:RemoveChannel(list, name)
    name = strtrim(tostring(name or ""))
    local removed = false
    for i = #list, 1, -1 do
        if sameChannel(list[i], name) then
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
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
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
    S:Register("recruit.participation_opt_in", function()
        -- Opt-in (#150): only an explicit true helps; the untouched default (nil) and false stay out.
        if Recruitment:_ParticipatingFrom(nil) then return false, "nil default must not participate" end
        if not Recruitment:_ParticipatingFrom(true) then return false, "true participates" end
        if Recruitment:_ParticipatingFrom(false) then return false, "false stays out" end
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
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        if GuildOS.Compat.IsSecret(msg, author) then return end  -- chat in lockdown: nothing readable
        local cfg = GuildOS.db.recruitment and GuildOS.db.recruitment.autoInvite
        if not cfg or not cfg.enabled then return end
        -- Anniversary and retail invite (one key press each where the game wants it, #449); WoW: Forever lets
        -- no addon invite (#256), and there the officer gets the /ginvite line to copy.
        if not (GuildOS.Compat.AddonMayInvite() or Recruitment:_InviteIsTyped()) then return end
        if not Recruitment:_MatchKeyword(msg, cfg.keyword) then return end
        local sender = author and (author:match("^([^-]+)") or author)
        if sender and sender ~= "" then
            Recruitment:_HandleKeywordWhisper(sender, author)
        end
    end)
end

-- Whether an invite here is a line the officer copies and sends (WoW: Forever, #256): the game lets no addon
-- invite, from a click either.
function Recruitment:_InviteIsTyped()
    local c = GuildOS.Client
    return not (c.isAnniversary or c.isRetail) and (CanGuildInvite and CanGuildInvite()) == true
end

-- An invite the whisper earned (#449). Through the officer action queue: at once where the game lets an addon
-- invite from an event, else on the next key press of the queue's binding or a click of its toast. On WoW:
-- Forever, the /ginvite line to copy. Without the queue (a test), at once.
function Recruitment:_DoInvite(name)
    local AQ = GuildOS.ActionQueue
    if self:_InviteIsTyped() then
        if AQ then AQ:OfferTyped(name) end
        return
    end
    if not AQ then return self:_InviteNow(name) end
    AQ:Add({ kind = "guildInvite", key = "ginv:" .. name, name = name,
             valid = function()
                 local BL = GuildOS.BanList
                 if BL and (BL:IsBanned(name) or BL:AllianceBansFor(name)) then return false end
                 return not self:_OnInviteCooldown(name, GetServerTime())
             end,
             run = function() return self:_InviteNow(name) end })
end

function Recruitment:_InviteNow(name, full)
    local cfg = GuildOS.db.recruitment.autoInvite
    if not GuildOS.Compat.GuildInvite(full or name) then return false end
    if GuildOS.RecruitEngagement then GuildOS.RecruitEngagement:RecordInvite(name) end
    self:_MarkInvited(name, GetServerTime(), cfg.cooldownSec)
    GuildOS:Print(string.format(L["Auto-invited |cffFFFFFF%s|r to the guild."], name))
    return true
end

function Recruitment:_HandleKeywordWhisper(sender, author)
    local cfg = GuildOS.db.recruitment.autoInvite
    -- Ban gate (BanList already alerts on a banned whisper). The whole sender: on retail the realm
    -- tells a banned namesake from this realm's (issue #184).
    if GuildOS.BanList and GuildOS.BanList:IsBanned(author or sender) then return end
    -- The alliance's ban (audit M2): never invited by itself; the whisper's alert tells the officer why, and
    -- inviting is theirs to do by hand, where HoldInvite asks first.
    if GuildOS.BanList and GuildOS.BanList:AllianceBansFor(author or sender) then return end
    -- Cooldown
    if self:_OnInviteCooldown(sender, GetServerTime()) then return end
    -- Filters need a /who (#449). C_FriendList.SendWho wants a hardware event (wiki; /gos probe invite measures
    -- it): there the /who waits in the officer action queue, its key press runs it, and the invite follows (at
    -- once, or on the next key press). Where the officer copies the invite (Forever), the copy is the check.
    local filtered = (cfg.minLevel or 0) > 0 or (cfg.classes and next(cfg.classes) ~= nil)
    local AQ = GuildOS.ActionQueue
    if not filtered or self:_InviteIsTyped() then
        self:_DoInvite(sender)
    elseif GuildOS.Compat.NeedsHardware("who") and AQ then
        AQ:Add({ kind = "who", key = "who:" .. sender, name = sender,
                 valid = function() return not self:_OnInviteCooldown(sender, GetServerTime()) end,
                 run = function() return self:_QualifyAndInvite(sender) ~= false end })
    else
        self:_QualifyAndInvite(sender)
    end
end

----------------------------------------------------------------------
-- What waits for a click on WoW: Forever (issue #61): the welcome for whoever joined. A queue, so a
-- burst of joins is one popup.
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
    -- The queue's key press sends it too (#449); the popup is its window, so the toast stays out.
    local AQ = GuildOS.ActionQueue
    if AQ then
        AQ:Add({ kind = "chat", key = "welcome", name = table.concat(self._pendingWelcomes, ", "),
                 verb = L["welcome"], ownWindow = true,
                 run = function()
                     local went = self:SendPendingWelcome()
                     if self.welcomePopup then self.welcomePopup:Hide() end
                     return went
                 end })
    end
    -- Never in combat, one popup at a time (audit B21): a join mid-fight waits for its end.
    GuildOS:ShowWhenClear("welcome", function() self:ShowWelcomePopup(); return self.welcomePopup end)
end

-- Why the game would refuse `msg` as a chat line, in the reader's words, or nil (#270). A "|" that is
-- not one of the game's own codes ("Welcome! | have fun") raises inside SendChatMessage, and the
-- welcome then never came, with nothing said.
function Recruitment.ChatTextProblem(msg)
    if type(msg) ~= "string" or strtrim(msg) == "" then return L["Nothing to send."] end
    if msg:find("|", 1, true) then return L["The game refuses the || character in a chat message. Use / or - instead."] end
    if msg:find("[\r\n]") then return L["A chat message has one line."] end
    if #msg > 255 then return L["The game sends at most 255 characters."] end
    return nil
end

-- The welcome as it goes out: the officers' text and, when they chose it and the guild has rules, the
-- invitation to /gos rules (#407), only when the whole still fits the game's 255 bytes (else the text
-- alone, as before). Pure on its arguments.
function Recruitment.WelcomeWithRules(base, withRules, hasRules)
    if type(base) ~= "string" or base == "" or not (withRules and hasRules) then return base end
    local full = base .. " " .. L["Type /gos rules to read the guild's rules."]
    if #full > 255 then return base end
    return full
end

-- Several welcomes, one drawn each time (#419). `welcomeMessages` is the whole list; its first is
-- also `welcomeMessage`, the one setting a client before #419 reads and writes, and that one wins
-- for the first place: a text set by such a client, or by /gos recruit welcome msg, is not lost.
Recruitment.WELCOME_MAX = 10

-- The officers' welcomes in order, the empty ones left out. Pure on `r`.
function Recruitment.WelcomeList(r)
    local out = {}
    if type(r) ~= "table" then return out end
    local function add(t)
        if type(t) == "string" and t ~= "" and #out < Recruitment.WELCOME_MAX then out[#out + 1] = t end
    end
    add(r.welcomeMessage)
    local list = r.welcomeMessages
    if type(list) == "table" then
        for i = 2, #list do add(list[i]) end
    end
    return out
end

local function writeWelcomes(r, list)
    local copy = {}
    for i, t in ipairs(list) do copy[i] = t end
    r.welcomeMessages = copy
    r.welcomeMessage = copy[1] or ""
end

-- Puts `text` at place `i` of the list, or adds it at the end when `i` is past it. False and why
-- when the game would refuse it, or when the list is full.
function Recruitment:SetWelcome(i, text)
    local r = GuildOS.db.recruitment
    if not r then return false end
    local problem = Recruitment.ChatTextProblem(text)
    if problem then return false, problem end
    local list = Recruitment.WelcomeList(r)
    if i > #list then
        if #list >= Recruitment.WELCOME_MAX then return false end
        list[#list + 1] = text
    else
        list[i] = text
    end
    writeWelcomes(r, list)
    self:WelcomeChanged()
    return true
end

-- Takes place `i` off the list; the last welcome left stays.
function Recruitment:RemoveWelcome(i)
    local r = GuildOS.db.recruitment
    local list = Recruitment.WelcomeList(r)
    if #list <= 1 or not list[i] then return false end
    table.remove(list, i)
    writeWelcomes(r, list)
    self:WelcomeChanged()
    return true
end

-- One of `list`, never `last` while another one is there. `rnd(n)` gives 1..n (math.random). Pure.
function Recruitment.PickWelcome(list, last, rnd)
    if type(list) ~= "table" or #list == 0 then return nil end
    local pool = {}
    for _, t in ipairs(list) do
        if t ~= last then pool[#pool + 1] = t end
    end
    if #pool == 0 then pool = list end
    return pool[(rnd or math.random)(#pool)]
end

-- The welcomes for a member who returns (#449, specs/salao/saidas.md): a second list, empty by default, the empty
-- ones left out. Pure on `r`.
function Recruitment.WelcomeBackList(r)
    local out = {}
    local list = type(r) == "table" and r.welcomeBackMessages
    if type(list) ~= "table" then return out end
    for _, t in ipairs(list) do
        if type(t) == "string" and t ~= "" and #out < Recruitment.WELCOME_MAX then out[#out + 1] = t end
    end
    return out
end

-- Puts `text` at place `i` of the returning members' list, or adds it past the end. False and why when the game
-- would refuse it, or when the list is full.
function Recruitment:SetWelcomeBack(i, text)
    local r = GuildOS.db.recruitment
    if not r then return false end
    local problem = Recruitment.ChatTextProblem(text)
    if problem then return false, problem end
    local list = Recruitment.WelcomeBackList(r)
    if i > #list then
        if #list >= Recruitment.WELCOME_MAX then return false end
        list[#list + 1] = text
    else
        list[i] = text
    end
    r.welcomeBackMessages = list
    self:WelcomeChanged()
    return true
end

-- Takes place `i` off the returning members' list; the last one may go (the normal welcome is used then).
function Recruitment:RemoveWelcomeBack(i)
    local r = GuildOS.db.recruitment
    local list = Recruitment.WelcomeBackList(r)
    if not list[i] then return false end
    table.remove(list, i)
    r.welcomeBackMessages = list
    self:WelcomeChanged()
    return true
end

-- What the welcome back fills in, when `who` is one member the history knows as a former one (an officer's
-- client: the history is theirs): { days = days away, since = the date they left }. Nil otherwise: several who
-- joined at once get the welcome for everybody.
function Recruitment:BackInfo(who)
    local names = type(who) == "table" and who or { who }
    local MH = GuildOS.MemberHistory
    if #names ~= 1 or type(names[1]) ~= "string" or not (MH and MH.ReturnInfo) or not GuildOS:IsOfficer() then return nil end
    local key = MH:KeyOf(names[1])
    local info = key and MH:ReturnInfo(key)
    if not info then return nil end
    return { days = info.away, since = GuildOS:DateText(info.leftAt, "/%Y") }
end

-- The welcome this client would send now (and shows in the Forever popup before the click). The
-- one drawn stays until it is sent, so the popup shows the line the click posts; a draw no longer
-- on the list is drawn again. `back` (BackInfo's): one of the returning members' list, when it has any.
function Recruitment:WelcomeMessage(back)
    local r = GuildOS.db.recruitment
    local GR = GuildOS.GuildRules
    local backList = back and Recruitment.WelcomeBackList(r) or {}
    if #backList > 0 then
        local drawnBack = self._drawnBack
        local held = false
        for _, t in ipairs(backList) do
            if t == drawnBack then held = true break end
        end
        if not held then
            drawnBack = Recruitment.PickWelcome(backList, r and r.welcomeBackLast)
            self._drawnBack = drawnBack
        end
        self._usedBack = true
        return Recruitment.WelcomeWithRules(drawnBack, r ~= nil and r.welcomeRules == true, GR ~= nil and GR:HasRules())
    end
    self._usedBack = nil
    local list = Recruitment.WelcomeList(r)
    local drawn = self._drawnWelcome
    local still = false
    for _, t in ipairs(list) do
        if t == drawn then still = true break end
    end
    if not still then
        drawn = Recruitment.PickWelcome(list, r and r.welcomeLast)
        self._drawnWelcome = drawn
    end
    return Recruitment.WelcomeWithRules(drawn, r ~= nil and r.welcomeRules == true,
        GR ~= nil and GR:HasRules())
end

-- A welcome went out: the next one is drawn among the others.
function Recruitment:_WelcomeSent()
    local r = GuildOS.db.recruitment
    if self._usedBack then
        if r and self._drawnBack then r.welcomeBackLast = self._drawnBack end
        self._drawnBack, self._usedBack = nil, nil
        return
    end
    if r and self._drawnWelcome then r.welcomeLast = self._drawnWelcome end
    self._drawnWelcome = nil
end

-- The one way a welcome reaches guild chat, clicked (Forever) or on its own (Anniversary): the text
-- is checked first and a send the game raises on is said, never lost (#270). True when it went.
-- The welcome's placeholders: {name} (also {nome}, {player}) becomes who joined — several joined at once, their
-- names joined by commas — and {guild} the guild's name. Names go without their realm. Case does not matter.
-- `back` (a member who returns, BackInfo's): {days} (also {dias}) the days they were away, {since} (also {desde}) the
-- date they left; without it those stay as written.
function Recruitment.FillWelcome(msg, who, back)
    if type(msg) ~= "string" then return msg end
    local names = type(who) == "table" and who or (who and { who } or {})
    local short = {}
    for _, n in ipairs(names) do
        local nm = tostring(n)
        short[#short + 1] = (GuildOS.ShortName and GuildOS:ShortName(nm)) or nm:match("^([^-]+)") or nm
    end
    local joined = table.concat(short, ", ")
    local guild = (GetGuildInfo and GetGuildInfo("player")) or ""
    local out = msg:gsub("{(%a+)}", function(key)
        local k = key:lower()
        if k == "name" or k == "nome" or k == "player" then return joined end
        if k == "guild" or k == "guilda" then return guild end
        if back and (k == "days" or k == "dias") then return tostring(back.days or "?") end
        if back and (k == "since" or k == "desde") then return tostring(back.since or "?") end
        return nil
    end)
    -- A name placeholder with nobody to name (a test from /gos) leaves no stray comma.
    out = out:gsub("%s+([,!.?])", "%1"):gsub("^%s+", "")
    return out
end

function Recruitment:SendWelcomeText(msg, who, back)
    msg = Recruitment.FillWelcome(msg, who, back)
    local problem = Recruitment.ChatTextProblem(msg)
    if problem then
        GuildOS:Print(string.format(L["The welcome was not sent: %s"], problem))
        return false
    end
    local ok, err = pcall(SendChatMessage, msg, "GUILD")
    if not ok then
        GuildOS:Print(string.format(L["The welcome was not sent: %s"], tostring(err)))
        return false
    end
    self:_WelcomeSent()
    if who then
        local w = type(who) == "table" and table.concat(who, ", ") or tostring(who)
        GuildOS:Print(L["Welcome message sent for |cffFFFFFF"] .. w .. L["|r in guild chat."])
    end
    return true
end

-- The click: one welcome in guild chat for everyone waiting. False when nobody is, or when the
-- game would not take the text: whoever waits keeps waiting for the fixed one.
function Recruitment:SendPendingWelcome()
    local list = self._pendingWelcomes
    local back = list and self:BackInfo(list)
    local msg = self:WelcomeMessage(back)
    if not list or #list == 0 or not msg or msg == "" then return false end
    if not self:SendWelcomeText(msg, list, back) then return false end
    self._pendingWelcomes = {}
    if GuildOS.ActionQueue then GuildOS.ActionQueue:Remove("welcome") end
    return true
end

-- Another officer claimed a welcome this one also has waiting for a click (issue #128). The
-- tie-break gives the officers 2 seconds to hear each other's intents, and an addon message can
-- take longer behind the guild's sync traffic, so two of them can each believe they won. The
-- claims they then exchange settle it the same way on both sides: the lower name keeps it.
function Recruitment:OnWelcomeClaim(member, sender)
    -- Welcomed, guild-wide: this client never sends it within WELCOME_ONCE (#449).
    if GuildOS.db and GuildOS.db.recruitment then self:MarkWelcomed(member) end
    local list = self._pendingWelcomes
    if not list then return end
    -- The same order as the election (StableName): the realm plays no part; Forever's surnames are the roster's.
    if not Recruitment.SortsBefore(GuildOS:SenderName(sender) or sender, GuildOS.Compat.PlayerName()) then return end
    for i = #list, 1, -1 do
        if list[i] == member then table.remove(list, i) end
    end
    self:ShowWelcomePopup()   -- redrawn without them, or hidden when nobody is left
end

----------------------------------------------------------------------
-- The welcome is the guild's, not each officer's (#449): the switch, the welcomes (and the ones for members who
-- return), the Discord and the rules' ending travel as one snapshot on the officers' guild settings ("guildcfg",
-- act "welcome", over GUILD: WoW: Forever has no OFFICER channel, and the text is posted in guild chat anyway),
-- officer-signed (SyncService checks the sender), the newest stamp winning on every client; an equal stamp goes
-- to the lower author name, so two officers' first runs settle the same everywhere. A client before it reads the
-- act as an officer threshold with no `max`, which it ignores.
--   r.welcomeCfgAt, r.welcomeCfgBy   -- the stamp and the officer who last changed it
-- First run: an officer whose client holds a welcome the guild never stamped shares it with the lowest stamp
-- (MIGRATE_REV), so any officer's real change wins over it.
----------------------------------------------------------------------
Recruitment.MIGRATE_REV = 1
local function serverNow() return (GetServerTime and GetServerTime()) or (time and time()) or os.time() end
Recruitment.WELCOME_STAMP_SLACK = 300
local DISCORD_MAX = 100

-- The snapshot this client holds, as it travels. Pure on `r`.
function Recruitment.WelcomeSnapshot(r)
    if type(r) ~= "table" then return nil end
    return { on = r.welcomeEnabled and true or false, msgs = Recruitment.WelcomeList(r),
             back = Recruitment.WelcomeBackList(r), discord = type(r.discord) == "string" and r.discord or "",
             rules = r.welcomeRules == true, by = r.welcomeCfgBy }
end

-- A snapshot off the network, checked field by field, or nil.
function Recruitment.ValidWelcome(d)
    if type(d) ~= "table" then return nil end
    local function list(t)
        local out = {}
        if type(t) ~= "table" then return out end
        for i = 1, math.min(#t, Recruitment.WELCOME_MAX) do
            local x = t[i]
            if type(x) == "string" and x ~= "" and not Recruitment.ChatTextProblem(x) then out[#out + 1] = x end
        end
        return out
    end
    local discord = type(d.discord) == "string" and GuildOS:SanitizeUserText(d.discord, DISCORD_MAX) or ""
    local by = type(d.by) == "string" and d.by ~= "" and GuildOS:SanitizeUserText(d.by, 48) or nil
    return { on = d.on == true, msgs = list(d.msgs), back = list(d.back), discord = discord, rules = d.rules == true, by = by }
end

-- The officer changed the welcome here: a new stamp, and the snapshot to the officers a moment later (a card's Save
-- changes several things at once: one envelope).
function Recruitment:WelcomeChanged()
    local r = GuildOS.db and GuildOS.db.recruitment
    if not (r and GuildOS:IsOfficer()) then return end
    local now = serverNow()
    r.welcomeCfgAt = math.max(now, (tonumber(r.welcomeCfgAt) or 0) + 1)
    r.welcomeCfgBy = GuildOS:ShortName(GuildOS.Compat.PlayerName())
    if self._welcomePublishSoon then return end
    self._welcomePublishSoon = true
    GuildOS.Compat.After(1, function()
        Recruitment._welcomePublishSoon = nil
        GuildOS:SafeCall(Recruitment.PublishWelcome, Recruitment)
    end)
end

-- To the guild: on a change, on the officers' regular sync and their answer to a request. A client whose welcome
-- the guild never stamped shares it at MIGRATE_REV (the first run).
function Recruitment:PublishWelcome()
    local r = GuildOS.db and GuildOS.db.recruitment
    if not (r and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    if not r.welcomeCfgAt then
        if #Recruitment.WelcomeList(r) == 0 then return end
        r.welcomeCfgAt, r.welcomeCfgBy = Recruitment.MIGRATE_REV, GuildOS:ShortName(GuildOS.Compat.PlayerName())
    end
    GuildOS.SyncService:Publish("guildcfg", "welcome", Recruitment.WelcomeSnapshot(r), { rev = r.welcomeCfgAt })
end

-- From an officer over GUILD (SyncService checked it): the newest stamp wins; an equal one, the lower author.
function Recruitment:OnWelcomeConfigSync(env, sender)
    local r = GuildOS.db and GuildOS.db.recruitment
    if not r or type(env) ~= "table" or env.act ~= "welcome" then return false end
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return false end
    at = math.min(at, serverNow() + Recruitment.WELCOME_STAMP_SLACK)
    local d = Recruitment.ValidWelcome(env.data)
    if not d then return false end
    local by = d.by or (sender and GuildOS:ShortName(sender)) or "?"
    local held = tonumber(r.welcomeCfgAt)
    if held and (at < held or (at == held and (by or ""):lower() >= (r.welcomeCfgBy or ""):lower())) then return false end
    if #d.msgs > 0 then writeWelcomes(r, d.msgs) end
    r.welcomeBackMessages = d.back
    r.welcomeEnabled, r.discord, r.welcomeRules = d.on, d.discord, d.rules
    r.welcomeCfgAt, r.welcomeCfgBy = at, by
    self._drawnWelcome, self._drawnBack = nil, nil
    if self.welcomeUiRefresh then GuildOS:SafeCall(self.welcomeUiRefresh) end
    return true
end

-- "Shared with the officers · last changed by Ana, 03/11 21:40", or nil before anybody stamped it.
function Recruitment:WelcomeSharedText()
    local r = GuildOS.db and GuildOS.db.recruitment
    if not (r and r.welcomeCfgAt) then return L["Shared with the officers: saving here sets it for all of them."] end
    if r.welcomeCfgAt <= Recruitment.MIGRATE_REV then
        return string.format(L["Shared with the officers · from %s's client"], r.welcomeCfgBy or "?")
    end
    return string.format(L["Shared with the officers · last changed by %s, %s"], r.welcomeCfgBy or "?",
        GuildOS:DateText(r.welcomeCfgAt, " %H:%M"))
end

----------------------------------------------------------------------
-- Who sends the welcome (#449: "more than one officer always sends it"). No race: every officer's client reads the
-- same guild roster and ranks the officers online by their name (without the realm, lower case, as the roster
-- spells it on every client: WoW: Forever's "First Surname" alike), its own character always counted. The first
-- sends WELCOME_FIRST seconds after the game's line, each next one WELCOME_STEP seconds later only if no officer's
-- claim came by then (the first is offline in a way the roster has not shown, runs no Guild OS, or an old one). The
-- claim and the intent go on the ALERT priority, ahead of the guild's sync traffic; the intent still goes out for
-- the officers on a client before this, whose own tie-break reads it. A claim, sent or heard, marks the member
-- welcomed for WELCOME_ONCE seconds on this client (kept over a /reload): never welcomed twice in that time.
-- Only the game's line starts a welcome; the roster diff (MemberHistory) never does.
----------------------------------------------------------------------
Recruitment.WELCOME_FIRST = 1
Recruitment.WELCOME_STEP = 5
Recruitment.WELCOME_ONCE = 600

-- How a name is compared: the roster's name without the realm, lower case; the realm after it, apart.
function Recruitment.StableName(name)
    if type(name) ~= "string" or name == "" then return "" end
    local shortName = (GuildOS:ShortName(name) or name):lower()
    return shortName
end

-- Whether officer name `a` goes before `b` (StableName's order). Pure.
function Recruitment.SortsBefore(a, b)
    return Recruitment.StableName(a) < Recruitment.StableName(b)
end

-- This client's place (0 = first) among the officers online in the roster, by StableName.
function Recruitment:WelcomePlace()
    local me = Recruitment.StableName(GuildOS.Compat.PlayerName())
    local maxRank = (GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.officerMaxRank) or 1
    local before, seen = 0, {}
    for i = 1, GetNumGuildMembers() or 0 do
        local full, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local n = full and Recruitment.StableName(full)
        if n and n ~= "" and online and rankIndex and rankIndex <= maxRank and n ~= me and not seen[n] then
            seen[n] = true
            if n < me then before = before + 1 end
        end
    end
    return before
end

local function welcomedStore()
    local r = GuildOS.db and GuildOS.db.recruitment
    if not r then return {} end
    r.welcomedAt = type(r.welcomedAt) == "table" and r.welcomedAt or {}
    return r.welcomedAt
end

-- Whether `name` was welcomed (here or by a claim heard) within WELCOME_ONCE seconds.
function Recruitment:RecentlyWelcomed(name, now)
    now = now or serverNow()
    local t = welcomedStore()[Recruitment.StableName(name)]
    return t ~= nil and now - t < Recruitment.WELCOME_ONCE
end

-- `name` is welcomed (a claim sent or heard): kept WELCOME_ONCE seconds; the old marks go.
function Recruitment:MarkWelcomed(name, now)
    now = now or serverNow()
    local s = welcomedStore()
    for k, t in pairs(s) do
        if type(t) ~= "number" or now - t >= Recruitment.WELCOME_ONCE then s[k] = nil end
    end
    local k = Recruitment.StableName(name)
    if k ~= "" then s[k] = now end
end

function Recruitment:DismissPendingWelcome()
    self._pendingWelcomes = {}
    if GuildOS.ActionQueue then GuildOS.ActionQueue:Remove("welcome") end
end

-- Async /who lookup, one query at a time. Fail-safe: on timeout / no result,
-- apply whoFallback ("skip" = do NOT invite).
function Recruitment:_QualifyAndInvite(sender)
    if self._whoBusy then
        -- one lookup at a time; drop extra concurrent triggers (cooldown will let them retry)
        return false
    end
    self._whoBusy = sender
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() Recruitment:_OnWhoResult() end)
    end
    GuildOS.Compat.RegisterEvent(self._whoFrame, "WHO_LIST_UPDATE")
    GuildOS.Compat.SetWhoToUI(true)   -- results to the API, not the Social frame
    GuildOS.Compat.SendWho(GuildOS.Compat.WhoExact(sender))
    -- Timeout: /who is throttled; give it 6s then fail-safe.
    GuildOS.Compat.After(6, function()
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
    GuildOS.Compat.SetWhoToUI(false)
    self._whoBusy = nil
    local cfg = GuildOS.db.recruitment.autoInvite
    -- Re-check cooldown/ban in case time passed.
    if GuildOS.BanList and (GuildOS.BanList:IsBanned(sender) or GuildOS.BanList:AllianceBansFor(sender)) then return end
    if self:_OnInviteCooldown(sender, serverNow()) then return end
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
    -- An officer whose rank arrived late may have started as a member: the member's popups stop
    -- here, or the officer's own would run beside them, twice the rate all session (issue #79).
    if self.memberTicker then self.memberTicker:Cancel(); self.memberTicker = nil end
    -- Ensure DB settings exist
    if not GuildOS.db.recruitment then
        GuildOS.db.recruitment = GuildOS:DeepCopy(self.DEFAULT_SETTINGS)
    end
    local r = GuildOS.db.recruitment
    -- Fill missing keys
    for k, v in pairs(self.DEFAULT_SETTINGS) do
        if r[k] == nil then
            if type(v) == "table" then
                r[k] = GuildOS:DeepCopy(v)
            else
                r[k] = v
            end
        end
    end

    -- Auto-invite config (fill missing keys the same way)
    r.autoInvite = r.autoInvite or {}
    for k, v in pairs(self.AUTOINVITE_DEFAULTS) do
        if r.autoInvite[k] == nil then
            r.autoInvite[k] = (type(v) == "table") and GuildOS:DeepCopy(v) or v
        end
    end
    self:_DropUnknownClasses(r.autoInvite.classes)
    self._inviteCd = {}
    self:_RegisterAutoInviteTests()

    -- Set default channels if empty
    if #r.channels == 0 then
        r.channels = { self:ChannelName("LookingForGroup") }
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
            r.welcomeMessage = string.format(L["Welcome to %s! Join our Discord: %s - Have fun!"], guildName, r.discord)
        else
            r.welcomeMessage = string.format(L["Welcome to %s - Have fun!"], guildName)
        end
    end
    -- The list of welcomes (#419): today's one is its first; nothing else changes for it.
    writeWelcomes(r, Recruitment.WelcomeList(r))

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
    return rankIndex <= (GuildOS.db.recruitment.minRankIndex or 2) or CanGuildInvite()
end

----------------------------------------------------------------------
-- Start automatic recruitment
----------------------------------------------------------------------
function Recruitment:StartAutoRecruit()
    if not self:CanUseRecruitment() then
        GuildOS:Print(L["|cffFF4444You don't have permission to use recruitment.|r"])
        return false
    end
    -- /gos recruit on reaches here with the module switched off and its tab hidden (issue #84).
    if not GuildOS:IsFeatureEnabled("recruitment") then
        GuildOS:Print(L["The Recruitment module is off. Turn it on in Settings > Modules."])
        return false
    end

    local settings = GuildOS.db.recruitment
    settings.enabled = true

    -- Stop existing ticker
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    local interval = math.max(settings.interval, 60) -- minimum 60s safety

    -- NOTE: SendChatMessage("CHANNEL") requires a hardware event (Blizzard restriction).
    -- We show a clickable popup instead of sending automatically.
    self.ticker = C_Timer.NewTicker(interval, function() self:_OfficerTick() end)

    -- Show first popup after a short delay
    C_Timer.After(2, function() self:_OfficerTick() end)

     GuildOS:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    -- Push the (now enabled) config to guild members so they can help spread it.
    self:BroadcastStatus(true)
    return true
end

-- One officer popup. With the module switched off it shows nothing, and the ticker stays: the
-- switch has no hook to start it again, so a stopped ticker would leave the tab saying ACTIVE
-- with no popup ever coming. Running silent, the next tick after the module is back shows
-- one (issue #84).
function Recruitment:_OfficerTick()
    if not GuildOS:IsFeatureEnabled("recruitment") then return end
    -- Never in combat, one popup at a time (audit B21).
    GuildOS:ShowWhenClear("recruitsend", function() self:ShowSendPopup(); return self.popupFrame end)
end

----------------------------------------------------------------------
-- Stop automatic recruitment
----------------------------------------------------------------------
function Recruitment:StopAutoRecruit()
    GuildOS.db.recruitment.enabled = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.popupFrame then
        self.popupFrame:Hide()
    end
    -- Push the disabled state so members stop spreading it (newest wins).
    if GuildOS:IsOfficer() then self:BroadcastStatus(true) end
    GuildOS:Print(L["Recruitment |cffFF4444stopped|r."])
end

----------------------------------------------------------------------
-- Toggle recruitment
----------------------------------------------------------------------
function Recruitment:Toggle()
    if GuildOS.db.recruitment.enabled then
        self:StopAutoRecruit()
    else
        self:StartAutoRecruit()
    end
    return GuildOS.db.recruitment.enabled
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
    if not GuildOS.CommSystem or not IsInGuild() then return end
    if not (GuildOS.IsOfficer and GuildOS:IsOfficer()) then return end
    -- An officer who changed guild mid-session still has the old guild's db, ad and rank threshold
    -- loaded: none of it goes to the new guild (#150).
    if not GuildOS:IsOnGuildDB() then return end
    local r = GuildOS.db.recruitment
    if not (reassert and r.updatedAt) then
        -- Genuine edit: stamp "last content edit", always past the last one, so two edits in one
        -- second (a rank picked twice) are still told apart by newest-wins.
        r.updatedAt = math.max(time(), (r.updatedAt or 0) + 1)
    end
    local payload = LibStub("GuildOS-LibSerialize"):Serialize({
        enabled    = r.enabled,
        discord    = r.discord or "",
        message    = r.message or "",
        channels   = r.channels or {},
        interval   = r.interval or 120,
        -- The highest rank (0 = GM) whose members post it; false, every rank (#150). Sent as false
        -- rather than left out: a client from before #150 leaves it out, and that means "unknown".
        maxRank    = r.postMaxRank or false,
        updatedBy  = GuildOS.Compat.PlayerName(),
        updatedAt  = r.updatedAt,
    })
    GuildOS.CommSystem:SendMessage("RI", payload)
    -- Mirror into the guild-synced slot so this account's own member-rank alts
    -- (they share the per-guild DB) get the ad immediately, with no round-trip.
    GuildOS.db.guildRecruitment = {
        enabled = r.enabled, discord = r.discord or "", message = r.message or "",
        channels = r.channels or {}, interval = r.interval or 120, maxRank = r.postMaxRank,
        updatedAt = r.updatedAt, updatedBy = GuildOS.Compat.PlayerName(),
    }
    if not quiet then GuildOS:Print(L["Recruitment status broadcast to guild members."]) end
end

----------------------------------------------------------------------
-- Member auto-send: opt-in ticker using guild-broadcast config
----------------------------------------------------------------------
function Recruitment:StartMemberRecruit(quiet)
    local info = GuildOS.db.guildRecruitment
    if not info or not info.message or info.message == "" then
        if not quiet then
            GuildOS:Print(L["|cffFF4444No recruitment data received yet. Ask an officer to broadcast.|r"])
        end
        return false
    end
    if self.memberTicker then self.memberTicker:Cancel() end
    local interval = math.max(info.interval or 120, 60)
    self.memberTicker = C_Timer.NewTicker(interval, function() Recruitment:_AutoTick() end)
    C_Timer.After(2, function() Recruitment:_AutoTick() end)
    if not quiet then
        GuildOS:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    end
    return true
end

-- One tick of the member AUTO popup. Enforces the per-session cap so a member
-- can never be nagged into a Blizzard silence: after AUTO_SESSION_CAP popups it
-- self-pauses the ticker and says so once. The manual "Send Now" button calls
-- ShowSendPopup directly and never routes through here, so it is never capped.
function Recruitment:_AutoTick()
    -- The module switched off while the popups ran: nothing more, and the ticker goes quietly.
    -- The switch only refreshes the tabs, so this is where it is heard (issue #79).
    if not GuildOS:IsFeatureEnabled("recruitment") then
        if self.memberTicker then self.memberTicker:Cancel(); self.memberTicker = nil end
        return
    end
    if not self:_AutoShouldContinue(self._autoPopups or 0, self.AUTO_SESSION_CAP) then
        self._autoCapReached = true
        if self.memberTicker then self.memberTicker:Cancel(); self.memberTicker = nil end
        if self.popupFrame then self.popupFrame:Hide() end
        GuildOS:Print(L["Auto recruit paused for this session (limit reached). Re-enable it from the Recruitment tab."])
        return
    end
    -- Out of the guild, or past the officers' rank, since the ticker started: nothing to show, and no
    -- popup counted toward the session's cap (#150).
    if not self:MemberMayPost() then
        -- The guild's name missing for a moment (around a loading screen) is not a guild change:
        -- skip this tick, uncounted, and keep the ticker.
        if IsInGuild() and not GetGuildInfo("player") then return end
        return self:SyncMemberParticipation()
    end
    self._autoPopups = (self._autoPopups or 0) + 1
    GuildOS:ShowWhenClear("recruitsend", function() self:ShowSendPopup(); return self.popupFrame end)
end

function Recruitment:StopMemberRecruit()
    if self.memberTicker then
        self.memberTicker:Cancel()
        self.memberTicker = nil
    end
    if self.popupFrame then self.popupFrame:Hide() end
    GuildOS:Print(L["Recruitment |cffFF4444stopped|r."])
end

function Recruitment:IsMemberRecruitActive()
    return self.memberTicker ~= nil
end

----------------------------------------------------------------------
-- Guild-wide sharing + opt-in participation
--
-- The officer's config is relayed member-to-member (not just pushed once by
-- the officer), so alts and late-loggers reliably end up with it. Helping is
-- opt-in (#150): db.recruitParticipate is nil when the member has never touched
-- it, true once they said they help, and false when they turned it off; only
-- true posts. It was opt-out, and a player was asked to post an ad they never
-- chose to. The choice is remembered across sessions; the member turns it on and
-- off with the Auto-Send toggle in the Recruitment tab or the Dashboard's card.
----------------------------------------------------------------------

-- Re-share the guild's recruitment config in response to a sync REQUEST.
-- Officers send their own authoritative copy; members relay the cached one so
-- the ad reaches newcomers even when no officer is online.
function Recruitment:RespondToSync()
    if not GuildOS.CommSystem or not IsInGuild() then return end
    if not GuildOS:IsOnGuildDB() then return end   -- another guild's db: nothing of it is shared (#150)
    if GuildOS:IsOfficer() then
        local r = GuildOS.db.recruitment
        -- Re-assert the current ad REGARDLESS of enabled, so a stale-enabled
        -- member who pulls converges onto a later disable. reassert=true keeps
        -- the existing stamp: idempotent, and it can never roll a newer edit back.
        if r and r.updatedAt then self:BroadcastStatus(true, true) end
        return
    end
    local info = GuildOS.db.guildRecruitment
    -- Members relay the cached ad REGARDLESS of enabled so a disabled state
    -- still spreads member-to-member with no officer online. Gate on it being a
    -- real received ad, and carry its EXISTING updatedBy/updatedAt unchanged.
    if info and info.updatedAt and info.updatedBy and info.message and info.message ~= "" then
        local payload = LibStub("GuildOS-LibSerialize"):Serialize({
            enabled = info.enabled, discord = info.discord or "", message = info.message or "",
            channels = info.channels or {}, interval = info.interval or 120, maxRank = info.maxRank or false,
            updatedBy = info.updatedBy, updatedAt = info.updatedAt,
        })
        GuildOS.CommSystem:SendMessage("RI", payload)
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
-- A rank limit off the wire: a whole rank index, 0 (GM) to 9, or none.
local function rankLimit(v)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 0 or v > 9 then return nil end
    return v
end

function Recruitment:ApplyIncoming(info, sender, channel)
    if type(info) ~= "table" then return end
    -- Only into this guild's own db: never the guildless one (a character who joined mid-session),
    -- nor another guild's (one who changed guild mid-session) (#150).
    if not GuildOS:IsOnGuildDB() then return end
    local claimedAuthor = (info.updatedBy and info.updatedBy ~= "" and info.updatedBy) or sender
    local claimedAuthorIsOfficer =
        (GuildOS.IsOfficerByName and GuildOS:IsOfficerByName(claimedAuthor)) or false
    local senderIsGuildmate = self:_IsGuildmate(sender)
    local incomingAt = math.min(tonumber(info.updatedAt) or 0, time() + FUTURE_SLACK)
    local cur = GuildOS.db.guildRecruitment
    local curAt = cur and cur.updatedAt or nil
    if not self:_AcceptConfig(channel, claimedAuthorIsOfficer, senderIsGuildmate, incomingAt, curAt) then
        return
    end
    GuildOS.db.guildRecruitment = {
        enabled   = info.enabled,
        discord   = info.discord or "",
        message   = info.message or "",
        channels  = info.channels or {},
        interval  = info.interval or 120,
        -- Left out, the relay came from a client before #150, which never kept it: the same ad (same
        -- stamp) keeps the limit it has; false is an officer's "every rank".
        maxRank   = (info.maxRank == nil and cur and incomingAt == curAt) and cur.maxRank or rankLimit(info.maxRank),
        updatedAt = incomingAt > 0 and incomingAt or time(),
        updatedBy = claimedAuthor,
    }
    if GuildOS.recruitmentPanelRefresh then GuildOS.recruitmentPanelRefresh() end
    self:SyncMemberParticipation()
end

-- The rank limit for members, as the officer's Recruitment panel moves it: every rank, then each
-- member rank in turn (an officer rank would leave no member, and the last rank is every rank), and
-- back. Sent to the guild only while this officer's recruiting is on, so picking a rank never turns a
-- running campaign off; otherwise it goes out with the next broadcast (#150). Returns the new limit.
function Recruitment:CyclePostMaxRank()
    local r = GuildOS.db.recruitment
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    if n < 1 then n = 10 end
    local first = ((GuildOS.db.settings and GuildOS.db.settings.officerMaxRank) or 1) + 1
    local last = n - 2
    local nextLimit
    if r.postMaxRank == nil then nextLimit = first
    elseif r.postMaxRank + 1 <= last then nextLimit = r.postMaxRank + 1 end
    if nextLimit and nextLimit > last then nextLimit = nil end
    r.postMaxRank = nextLimit
    if r.enabled then self:BroadcastStatus(true) end
    return nextLimit
end

-- The limits CyclePostMaxRank goes through, in its order: nil (every rank), then each member rank. The
-- officer's Recruiting screen lists them in a select (#449). Returns a list of limits (nil first).
function Recruitment:PostMaxRankChoices()
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    if n < 1 then n = 10 end
    local first = ((GuildOS.db.settings and GuildOS.db.settings.officerMaxRank) or 1) + 1
    local out = { false }
    for limit = first, n - 2 do out[#out + 1] = limit end
    return out
end

-- Set the members' rank limit to `limit` (nil or false: every rank), as CyclePostMaxRank does: sent to the
-- guild only while this officer's recruiting is on. Returns the limit.
function Recruitment:SetPostMaxRank(limit)
    GuildOS.db.recruitment.postMaxRank = limit or nil
    if GuildOS.db.recruitment.enabled then self:BroadcastStatus(true) end
    return GuildOS.db.recruitment.postMaxRank
end

-- Member opt-in choice (persisted). nil = never touched, true = helping,
-- false = turned off.
function Recruitment:SetParticipation(v)
    GuildOS.db.recruitParticipate = v
    if v ~= false then
        -- A manual re-enable clears any per-session auto-pause and popup count,
        -- so turning Auto-Send back on from the tab actually resumes popups.
        self._autoCapReached = false
        self._autoPopups = 0
    end
    self:SyncMemberParticipation()
end

-- Pure opt-in semantics for a stored choice: only an explicit true helps. It was
-- opt-out, and a player was asked to post an ad they never chose to (#150). Kept
-- separate so a self test pins the rule.
function Recruitment:_ParticipatingFrom(choice)
    return choice == true
end

-- Opt-in: a member helps once they said so.
function Recruitment:IsParticipating()
    return self:_ParticipatingFrom(GuildOS.db.recruitParticipate)
end

-- May this member post the guild's ad? In a guild, on its own db (a character with no guild
-- shares an account-wide fallback, where a guild's ad must never reach it), and within the rank
-- the officers chose (#150).
function Recruitment:MemberMayPost()
    if not GuildOS:IsOnGuildDB() then return false end
    local info = GuildOS.db.guildRecruitment
    local limit = info and rankLimit(info.maxRank)
    if not limit then return true end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= limit
end

-- Reconcile the member popup ticker with the current guild config and the
-- stored choice. Safe to call repeatedly.
function Recruitment:SyncMemberParticipation()
    if GuildOS:IsOfficer() then return end   -- officers use their own flow
    local info = GuildOS.db.guildRecruitment
    local active = info and info.enabled and info.message and info.message ~= ""
    -- The module switched off in Settings skips InitParticipation, but an officer's ad still
    -- arrives and lands here: the ad is kept and relayed, the popups stay off (issue #79).
    if not active or not self:IsParticipating() or not GuildOS:IsFeatureEnabled("recruitment")
        or not self:MemberMayPost() then
        if self:IsMemberRecruitActive() then self:StopMemberRecruit() end
        return
    end
    -- Self-paused for the session after hitting the popup cap: stay stopped
    -- until the member manually re-enables (SetParticipation clears the flag),
    -- so a routine re-sync never re-nags a member who was already capped.
    if self._autoCapReached then return end
    if not self:IsMemberRecruitActive() then
        self:StartMemberRecruit(true)   -- quiet: no per-login "started" spam
    end
end

----------------------------------------------------------------------
-- Member-side setup — runs for EVERY player (unlike the officer-only
-- Initialize). Reconciles participation against the persisted/synced config on
-- login. Opt-in (#150): a member who said they help gets the recruit popup once
-- the guild is recruiting, within the rank the officers chose.
----------------------------------------------------------------------
function Recruitment:InitParticipation()
    C_Timer.After(15, function()
        if GuildOS.Recruitment then GuildOS.Recruitment:SyncMemberParticipation() end
    end)
end

----------------------------------------------------------------------
-- Which config drives the popup/send: officers post their own configured ad,
-- members post the guild-broadcast (relayed) copy. Returns the settings table
-- or nil.
----------------------------------------------------------------------
function Recruitment:_ActiveConfig()
    return GuildOS:IsOfficer() and GuildOS.db.recruitment or GuildOS.db.guildRecruitment
end

-- The post round's plan (#449): every configured channel once, whatever the case or the language it was saved in,
-- resolved against the channels the player is in. { targets = { { name, num } ... } in the saved order, one per
-- channel number; notJoined = { name ... } }.
function Recruitment:PostPlan(settings)
    local plan, seenName, seenNum = { targets = {}, notJoined = {} }, {}, {}
    for _, saved in ipairs(settings and settings.channels or {}) do
        local name, num = self:ResolveChannel(saved)
        local key = name:lower()
        if name ~= "" and not seenName[key] and not (num > 0 and seenNum[num]) then
            seenName[key] = true
            if num > 0 then
                seenNum[num] = true
                plan.targets[#plan.targets + 1] = { name = name, num = num }
            else
                plan.notJoined[#plan.notJoined + 1] = name
            end
        end
    end
    return plan
end

-- Configured channel names (once each), and how many of them the player has actually joined right now: with zero
-- joined there is nothing to post to.
function Recruitment:_ResolveChannels(settings)
    local names, joined = {}, 0
    local plan = self:PostPlan(settings)
    for _, t in ipairs(plan.targets) do
        names[#names + 1] = t.name
        joined = joined + 1
    end
    for _, n in ipairs(plan.notJoined) do names[#names + 1] = n end
    return names, joined
end

-- How many channel lines one key press or click may carry. Where the game wants a hardware event for a channel
-- line (Compat.NeedsHardware("channel"): WoW: Forever and retail, or as /gos debug probe invite measured it), the
-- maintainer saw a round post to the first channels and not to the last (#449): one line per key press there,
-- unless the probe heard a second line from the same key press come back. Elsewhere every channel at once.
-- One click posts in every channel (the maintainer, #449: the channel that stayed empty had dropped the line itself,
-- which the echo check now says; posting one channel per key press was not the cause and is gone).
function Recruitment:PostsPerClick()
    return math.huge
end

-- The consent popup's Post button: one click posts in every channel.
function Recruitment:PostButtonText()
    return L["Post"]
end

-- The line after a post round: "Sent to: [3] LookingForGroup, [4] Trade · Not joined: General · Waiting for a
-- key press: LookingForGuild", only the parts that apply. `round` = { posted = { {name, num} }, notJoined = { name },
-- waiting = { name }, iconsOnly = { name } }. Nil when nothing applies.
function Recruitment:RoundSummary(round)
    local parts = {}
    local function list(t, fmt)
        if t and #t > 0 then parts[#parts + 1] = string.format(fmt, table.concat(t, ", ")) end
    end
    local posted = {}
    for _, p in ipairs(round.posted or {}) do posted[#posted + 1] = string.format("[%d] %s", p.num, p.name) end
    list(posted, L["Sent to: %s"])
    list(round.notJoined, L["Not joined: %s"])
    list(round.iconsOnly, L["Only raid icons, which it hides: %s"])
    list(round.waiting, L["Waiting for a key press: %s"])
    list(round.throttled, L["Skipped, the server is limiting chat: %s"])
    if #parts == 0 then return nil end
    return table.concat(parts, " \194\183 ")
end

----------------------------------------------------------------------
-- Create the consent popup (one-time). Shows the actual target channel and the
-- message text so the member consents to real content, not a blind click.
----------------------------------------------------------------------
function Recruitment:CreatePopupFrame()
    if self.popupFrame then return end

    local C  = GuildOS.Colors
    local UI = GuildOS.UI
    local Kit = rawget(GuildOS, "Kit")
    local PAD, WIDTH = 14, 380
    local cw = WIDTH - PAD * 2

    -- A floating window (the mockup's .fw): the metal frame, the header with "Recruitment" in Cinzel gold
    -- and the round red close, the channel line and the ad on the dark body, Post and Not now in the footer.
    local f = CreateFrame("Frame", "GuildOSRecruitPopup", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 150)
    f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    local top
    if Kit then
        Kit:Dress(f, L["Recruitment"], { sub = "Guild OS" })
        Kit:Footer(f)
        top = Kit.HEADER_H + 10
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(0.082, 0.082, 0.105, 0.97)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local title = f:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(title, 13)
        title:SetPoint("TOPLEFT", PAD, -12)
        title:SetTextColor(C.text.r, C.text.g, C.text.b)
        title:SetText("Guild OS  " .. L["Recruitment"])
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -6, -6)
        close:SetScript("OnClick", function() f:Hide() end)
        top = 38
    end
    f.top = top

    -- Target channel line.
    local channelLine = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(channelLine, 11)
    channelLine:SetPoint("TOPLEFT", PAD, -top)
    channelLine:SetWidth(cw)
    channelLine:SetJustifyH("LEFT")
    channelLine:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.channelLine = channelLine

    -- Message preview (wrapped; sized in ShowSendPopup), in the reading face on the window's light wash
    -- (the mockup's `.fw .msg`).
    local msgText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(msgText, 12, "reading")
    msgText:SetPoint("TOPLEFT", PAD + 8, -(top + 26))
    msgText:SetWidth(cw - 16)
    msgText:SetJustifyH("LEFT")
    msgText:SetTextColor(C.text.r, C.text.g, C.text.b)
    f.msgText = msgText
    local wash = f:CreateTexture(nil, "BORDER")
    wash:SetTexture("Interface\\Buttons\\WHITE8x8")
    wash:SetVertexColor(1, 1, 1, 0.07)
    wash:SetPoint("TOPLEFT", msgText, "TOPLEFT", -8, 6)
    wash:SetPoint("BOTTOMRIGHT", msgText, "BOTTOMRIGHT", 8, -6)

    -- "Join a channel" hint, shown instead of a dead Postar when nothing is joined.
    local hint = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(hint, 11)
    hint:SetWidth(cw)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(C.danger.r, C.danger.g, C.danger.b)
    hint:Hide()
    f.hint = hint

    -- Postar (the send): a hardware OnClick so SendChatMessage to a channel works.
    -- The popup's one action is its primary button, not a green fill (#371).
    local postBtn = UI:CreateButton(f.foot or f, L["Post"], 110, 24)
    UI:SetButtonVariant(postBtn, "primary")
    postBtn:SetScript("OnClick", function()
        Recruitment:DoSendRecruitmentMessage()
        f:Hide()
    end)
    f.postBtn = postBtn

    -- "Agora nao" / dismiss.
    local laterBtn = UI:CreateButton(f.foot or f, L["Not now"], 110, 24)
    laterBtn:SetScript("OnClick", function() f:Hide() end)
    f.laterBtn = laterBtn
    -- The footer lays the answers from the right, the post first; with no kit, centred as before.
    function f:LayButtons()
        if self.foot then
            self.foot:Lay(postBtn, laterBtn)
        else
            postBtn:ClearAllPoints()
            postBtn:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -5, 14)
            laterBtn:ClearAllPoints()
            laterBtn:SetPoint("BOTTOMLEFT", self, "BOTTOM", 5, 14)
        end
    end
    f:LayButtons()

    self.popupFrame = f
end

----------------------------------------------------------------------
-- The popups that carry a click on WoW: Forever (issue #61), in the recruit popup's style:
-- a title, a line, a note, and two buttons whose OnClick is the hardware event the game wants.
----------------------------------------------------------------------
local function ActionPopup(title, y, okText, laterText)
    local C, UI = GuildOS.Colors, GuildOS.UI
    local Kit = rawget(GuildOS, "Kit")
    local PAD, WIDTH = 14, 380
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 120)
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    -- A floating window as the recruit popup (the mockup's .fw): the title in its header, the answers in its footer.
    local top
    if Kit then
        Kit:Dress(f, title, { sub = "Guild OS" })
        Kit:Footer(f)
        top = Kit.HEADER_H + 10
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(0.082, 0.082, 0.105, 0.97)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
        local t = f:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(t, 13)
        t:SetPoint("TOPLEFT", PAD, -12)
        t:SetTextColor(C.text.r, C.text.g, C.text.b)
        t:SetText("Guild OS  " .. title)
        top = 38
    end

    f.line = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.line, 12)
    f.line:SetPoint("TOPLEFT", PAD, -top)
    f.line:SetWidth(WIDTH - PAD * 2)
    f.line:SetJustifyH("LEFT")
    f.line:SetTextColor(C.text.r, C.text.g, C.text.b)

    f.note = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.note, 11, "reading")
    f.note:SetPoint("TOPLEFT", f.line, "BOTTOMLEFT", 0, -6)
    f.note:SetWidth(WIDTH - PAD * 2)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)

    f.okBtn = UI:CreateButton(f.foot or f, okText, 130, 24)
    UI:SetButtonVariant(f.okBtn, "primary")   -- the click the popup carries, not a green fill (#371)
    f.laterBtn = UI:CreateButton(f.foot or f, laterText, 130, 24)
    if f.foot then
        f.foot:Lay(f.okBtn, f.laterBtn)
    else
        f.okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 12)
        f.laterBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 12)
    end
    -- Grow to the text, like the recruit popup: the note is the line the click posts.
    local footH = Kit and Kit.FOOT_H or 50
    function f:Fit()
        self:SetHeight(top + self.line:GetStringHeight() + 6 + self.note:GetStringHeight() + 14 + footH)
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
    local back = self:BackInfo(list)
    f.note:SetText(Recruitment.FillWelcome(self:WelcomeMessage(back) or "", list, back))
    f:Fit()
    f:Show()
end

----------------------------------------------------------------------
-- Show the consent popup, populated from the active config.
----------------------------------------------------------------------
function Recruitment:ShowSendPopup()
    if InCombatLockdown() then return end
    -- Nobody is asked to post a guild's ad outside it, nor a member past the rank the officers chose (#150).
    if not GuildOS:IsOnGuildDB() then return end
    if not GuildOS:IsOfficer() and not self:MemberMayPost() then return end

    -- Officers use their own config; members use the guild-broadcast config.
    local settings = self:_ActiveConfig()
    if GuildOS:IsOfficer() then
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
    local full = GuildOS:SanitizeUserText(raw, self.MSG_MAX)
    f.msgText:SetText("\"" .. full .. "\"")

    -- Layout: size the frame to the wrapped message, then the button row (or the
    -- join-channel hint if nothing is joined).
    local y = (f.top or 38) + 26 + math.max(f.msgText:GetStringHeight() or 14, 14) + 16
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
    -- Where a click carries one channel line, the button says which of how many it posts (#449).
    if f.postBtn.label then f.postBtn.label:SetText(self:PostButtonText(joined)) end
    f:LayButtons()
    f:SetHeight(y + (f.foot and rawget(GuildOS, "Kit") and GuildOS.Kit.FOOT_H or 40))
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

    -- The server said "throttled" a moment ago: nothing goes until it has had its few seconds.
    if self:_Throttled() then
        GuildOS:Print("|cffFF9900" .. L["The server is limiting your chat lines. Wait a few seconds and click Post again."] .. "|r")
        return
    end
    -- Min send gap: refuse a send too soon after the last one. Covers reflexive
    -- rapid clicking and any forged low interval. Silent no-op when throttled.
    if not self:_CanSendNow(self._lastSendAt, GetTime(), self.SEND_MIN_GAP) then return end

    -- Officers use their own config; members use the guild-broadcast config.
    local settings = self:_ActiveConfig()
    if not settings then
        GuildOS:Print(L["|cffFF4444No recruitment data. Ask an officer to broadcast.|r"])
        return
    end
    local msg = settings.message
    if not msg or msg == "" then
        GuildOS:Print(L["|cffFF4444No recruitment message set.|r"])
        return
    end
    -- Sanitize before it ever reaches a public channel under the player's name:
    -- strip chat escapes (textures / unterminated colour / fake links) and cap
    -- at the SendChatMessage limit. Officer and member paths alike. Same cap the
    -- consent popup previewed, so the member posts exactly what they saw (minus raid-icon
    -- codes where the channel would show them as text, issue #64).
    msg = GuildOS:SanitizeUserText(msg, self.MSG_MAX)
    if msg == "" then
        GuildOS:Print(L["|cffFF4444No recruitment message set.|r"])
        return
    end

    self:PostRound(settings, msg)
end

-- The key of a channel's ad waiting in the officer action queue.
local function adKey(name) return "recruitAd:" .. tostring(name):lower() end

-- Posts `msg` to one resolved channel, raid icons left out where the server hides them (issue #64). "posted",
-- "icons" (nothing left to post there) or false (the game would not take it).
function Recruitment:_PostTo(name, num, msg)
    local text = GuildOS.Compat.ChannelHidesRaidIcons(name, num) and self:_StripRaidIcons(msg) or msg
    if text == "" then return "icons" end
    return GuildOS.Compat.SendChannelMessage(text, num) and "posted" or false
end

-- One post round, from a key press or a click. Every channel at once where one click may carry them all; else the
-- first now and each of the rest in the officer action queue, one per key press of its binding or click of its
-- toast ("Press [key] to post the ad in LookingForGuild · 2 more"). Ends with the round's line (RoundSummary).
function Recruitment:PostRound(settings, msg)
    local plan = self:PostPlan(settings)
    local AQ = GuildOS.ActionQueue
    -- A new round replaces what an older one left waiting.
    if AQ then
        for _, key in ipairs(self._queuedAds or {}) do AQ:Remove(key) end
    end
    self._queuedAds = {}
    self:_WatchThrottle()
    local targets, notJoined = plan.targets, plan.notJoined
    local per = self:PostsPerClick()
    if not AQ then per = math.huge end
    local round = { posted = {}, notJoined = notJoined, waiting = {}, iconsOnly = {}, throttled = {}, msg = msg }
    local went = 0
    for _, t in ipairs(targets) do
        if self:_Throttled() then
            -- The server said "throttled" during the round: the rest are skipped and said, not hammered.
            round.throttled[#round.throttled + 1] = t.name
        elseif went >= per then
            round.waiting[#round.waiting + 1] = t.name
        else
            local r = self:_PostTo(t.name, t.num, msg)
            if r == "posted" then
                went = went + 1
                round.posted[#round.posted + 1] = t
            elseif r == "icons" then
                round.iconsOnly[#round.iconsOnly + 1] = t.name
            end
        end
    end
    for _, name in ipairs(round.waiting) do self:_QueueAd(name, msg) end
    self:_FinishRound(round, false)
    return round
end

-- A channel's ad waiting in the officer action queue for a key press or a click of its toast.
function Recruitment:_QueueAd(name, msg)
    local AQ = GuildOS.ActionQueue
    if not AQ then return end
    local key = adKey(name)
    for _, k in ipairs(self._queuedAds) do if k == key then return end end
    self._queuedAds[#self._queuedAds + 1] = key
    AQ:Add({
        kind = "channel", key = key, name = name, verb = L["post the ad in"],
        run = function() return Recruitment:_PostQueued(name, msg) end,
    })
end

-- The server's "throttled" answer (a channel notice, or the chat error): THROTTLE_HOLD seconds without a channel line.
Recruitment.THROTTLE_HOLD = 10
function Recruitment:_Throttled()
    return self._throttledAt ~= nil and GetTime() - self._throttledAt < self.THROTTLE_HOLD
end

function Recruitment:_OnThrottle()
    self._throttledAt = GetTime()
end

function Recruitment:_WatchThrottle()
    if self._throttleFrame or not CreateFrame then return end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL_NOTICE")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, event, text)
        if GuildOS.Compat.IsSecret(text) then return end
        if (event == "CHAT_MSG_CHANNEL_NOTICE" and text == "THROTTLED")
            or (event == "CHAT_MSG_SYSTEM" and type(_G.ERR_CHAT_THROTTLED) == "string" and text == _G.ERR_CHAT_THROTTLED) then
            Recruitment:_OnThrottle()
        end
    end)
    self._throttleFrame = f
end

-- A queued channel's turn, from the key press or the click that runs it: resolved again (the player may have left
-- it, or its number changed), posted, and the line says what is left.
function Recruitment:_PostQueued(name, msg)
    local real, num = self:ResolveChannel(name)
    local round = { posted = {}, notJoined = {}, waiting = {}, iconsOnly = {} }
    local key = adKey(name)
    for i, k in ipairs(self._queuedAds or {}) do
        if k == key then table.remove(self._queuedAds, i) break end
    end
    if self:_Throttled() then
        -- Not now: said, and left (a channel that will not take it is not insisted on).
        round.throttled = { name }
        self:_FinishRound(round, true)
        return false
    end
    local r = num > 0 and self:_PostTo(real, num, msg)
    if r == "posted" then
        round.posted[1] = { name = real, num = num }
    elseif r == "icons" then
        round.iconsOnly[1] = real
    elseif num == 0 then
        round.notJoined[1] = real
    end
    local AQ = GuildOS.ActionQueue
    for _, item in ipairs(AQ and AQ._state and AQ._state.items or {}) do
        if item.kind == "channel" and tostring(item.key):find("^recruitAd:") and item.key ~= key then
            round.waiting[#round.waiting + 1] = item.name
        end
    end
    round.msg = msg
    self:_FinishRound(round, true)
    return r == "posted"
end

-- The game takes a channel line and may still not show it (a channel's moderator muted the player, a server spam
-- filter, a channel that only some may speak in): nothing says so. Each post waits for its own line to come back on
-- CHAT_MSG_CHANNEL; one that has not after ECHO_WAIT seconds is said to have been dropped (#449).
Recruitment.ECHO_WAIT = 5
function Recruitment:_WatchEcho(posted)
    if not (CreateFrame and GuildOS.Compat.After) then return end
    self._echo = self._echo or {}
    local watch = {}
    for _, p in ipairs(posted or {}) do
        watch[#watch + 1] = p
        self._echo[p.num] = { name = p.name, seen = false }
    end
    if #watch == 0 then return end
    if not self._echoFrame then
        local f = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL")
        f:SetScript("OnEvent", function(_, _, _, sender, _, _, _, _, _, num)
            local e = Recruitment._echo and Recruitment._echo[tonumber(num) or -1]
            if not e or e.seen then return end
            if GuildOS.Compat.IsSecret and GuildOS.Compat.IsSecret(sender) then return end
            local me = GuildOS.Compat.PlayerName and GuildOS.Compat.PlayerName()
            if me and GuildOS.SenderName and GuildOS:SenderName(sender) == me then e.seen = true end
        end)
        self._echoFrame = f
    end
    GuildOS.Compat.After(self.ECHO_WAIT, function()
        local dropped = {}
        for _, p in ipairs(watch) do
            local e = Recruitment._echo[p.num]
            if e and not e.seen then
                dropped[#dropped + 1] = string.format("[%d] %s", p.num, p.name)
            end
            Recruitment._echo[p.num] = nil
        end
        if #dropped > 0 then
            -- A channel that would not show it (Trade outside a city, a muted channel, the flood limit): said once,
            -- never insisted on (#449: the maintainer's "accept the errors and just say so").
            GuildOS:Print("|cffFF9900" .. string.format(L["Not shown in: %s"], table.concat(dropped, ", ")) .. "|r")
        end
    end)
end

-- The round's bookkeeping and its line. A queued channel's post counts as part of its round, not a new send.
function Recruitment:_FinishRound(round, queued)
    self:_WatchEcho(round.posted, round.msg)
    if #round.posted > 0 and not queued then
        self._lastSendAt = GetTime()
        self.lastSend = GetTime()
        if GuildOS.RecruitEngagement then GuildOS.RecruitEngagement:RecordPost() end
    end
    local line = self:RoundSummary(round)
    if line then GuildOS:Print(line) end
    if #round.posted == 0 and #round.waiting == 0 and #(round.throttled or {}) == 0 and not queued then
        if #round.iconsOnly > 0 then
            GuildOS:Print(L["|cffFF4444The message is only raid icons, which this channel does not show: nothing posted.|r"])
        else
            GuildOS:Print(L["|cffFF4444No valid channels found. Join a channel first.|r"])
        end
    end
end

----------------------------------------------------------------------
-- Right-click guild invite (slash command based - no dropdown hook to avoid taint)
-- Usage: /gos invite PlayerName
----------------------------------------------------------------------
function Recruitment:HookChatInvite()
    -- No dropdown hooks - they cause taint errors.
    -- Guild invite is available via /gos invite <name>
end

----------------------------------------------------------------------
-- Slash command handler
----------------------------------------------------------------------
function Recruitment:HandleCommand(args)
    local cmd = args[1]
    -- The settings exist once an officer's client has started recruitment; a member's never
    -- has, and every branch below but `invite` reads them.
    if not GuildOS.db.recruitment and cmd and cmd ~= "invite" then
        GuildOS:Print(GuildOS:IsFeatureEnabled("recruitment") and L["Recruitment settings are available to officers after login."]
            or L["The Recruitment module is off. Turn it on in Settings > Modules."])
        return
    end

    if cmd == "on" or cmd == "start" then
        self:StartAutoRecruit()
    elseif cmd == "off" or cmd == "stop" then
        self:StopAutoRecruit()
    elseif cmd == "msg" or cmd == "message" then
        table.remove(args, 1)
        local newMsg = table.concat(args, " ")
        local problem = newMsg ~= "" and Recruitment.ChatTextProblem(newMsg)
        if problem then
            GuildOS:Print(problem)
        elseif newMsg and newMsg ~= "" then
            GuildOS.db.recruitment.message = newMsg
            GuildOS:Print(L["Recruitment message set to: |cffFFFFFF"] .. newMsg .. "|r")
        else
            GuildOS:Print(L["Current message: |cffFFFFFF"] .. (GuildOS.db.recruitment.message or L["(empty)"]) .. "|r")
        end
    elseif cmd == "interval" then
        local secs = tonumber(args[2])
        if secs and secs >= 60 then
            GuildOS.db.recruitment.interval = secs
            GuildOS:Print(string.format(L["Recruitment interval set to |cffFFFFFF%ds|r."], secs))
            -- Restart if active. StartAutoRecruit replaces the ticker itself: going through
            -- StopAutoRecruit would switch the guild's recruitment off (enabled = false, a
            -- disabled ad broadcast) whenever the start then refused, as with the module off.
            if GuildOS.db.recruitment.enabled then
                -- With the module off the start refuses, so the silent ticker takes the new
                -- period here, or it would come back on at the old one.
                if self.ticker and not GuildOS:IsFeatureEnabled("recruitment") then
                    self.ticker:Cancel()
                    self.ticker = C_Timer.NewTicker(secs, function() self:_OfficerTick() end)
                end
                self:StartAutoRecruit()
            end
        else
            GuildOS:Print(L["Usage: /guildos recruit interval <seconds> (min 60)"])
        end
    elseif cmd == "channel" then
        local action = args[2]
        local chName = args[3]
        if action == "add" and chName then
            if self:AddChannel(GuildOS.db.recruitment.channels, chName) then
                GuildOS:Print(L["Added channel: |cffFFFFFF"] .. chName .. "|r")
            else
                GuildOS:Print(L["Already posting to: |cffFFFFFF"] .. chName .. "|r")
            end
        elseif action == "remove" and chName then
            if self:RemoveChannel(GuildOS.db.recruitment.channels, chName) then
                GuildOS:Print(L["Removed channel: |cffFFFFFF"] .. chName .. "|r")
            else
                GuildOS:Print(L["Channel not found: "] .. chName)
            end
        elseif action == "list" then
            local list = table.concat(GuildOS.db.recruitment.channels, ", ")
            GuildOS:Print(L["Channels: |cffFFFFFF"] .. (list ~= "" and list or L["(none)"]) .. "|r")
        else
            GuildOS:Print(L["Usage: /guildos recruit channel <add|remove|list> [name]"])
        end
    elseif cmd == "status" then
        local s = GuildOS.db.recruitment
        local status = s.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        local wStatus = s.welcomeEnabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        GuildOS:Print(L["--- Recruitment Status ---"])
        GuildOS:Print(L["Active: "] .. status)
        GuildOS:Print(string.format(L["Interval: |cffFFFFFF%ds|r"], s.interval))
        GuildOS:Print(L["Channels: |cffFFFFFF"] .. table.concat(s.channels, ", ") .. "|r")
        GuildOS:Print(L["Message: |cffFFFFFF"] .. s.message .. "|r")
        GuildOS:Print(L["Welcome: "] .. wStatus)
        GuildOS:Print(L["Welcome msg: |cffFFFFFF"] .. s.welcomeMessage .. "|r")
        local more = #Recruitment.WelcomeList(s) - 1
        if more > 0 then GuildOS:Print(string.format(L["(+%d more, one drawn at random each time)"], more)) end
        GuildOS:Print(L["Discord: |cffFFFFFF"] .. s.discord .. "|r")
    elseif cmd == "welcome" then
        local sub = args[2]
        if sub == "on" then
            GuildOS.db.recruitment.welcomeEnabled = true
            Recruitment:WelcomeChanged()
            GuildOS:Print(L["Welcome message |cff4CFF4Cenabled|r."])
        elseif sub == "off" then
            GuildOS.db.recruitment.welcomeEnabled = false
            Recruitment:WelcomeChanged()
            GuildOS:Print(L["Welcome message |cffFF4444disabled|r."])
        elseif sub == "msg" then
            table.remove(args, 1)
            table.remove(args, 1)
            local newMsg = table.concat(args, " ")
            local problem = newMsg ~= "" and Recruitment.ChatTextProblem(newMsg)
            if problem then
                GuildOS:Print(problem)
            elseif newMsg and newMsg ~= "" then
                Recruitment:SetWelcome(1, newMsg)
                GuildOS:Print(L["Welcome message set to: |cffFFFFFF"] .. newMsg .. "|r")
            else
                GuildOS:Print(L["Current: |cffFFFFFF"] .. GuildOS.db.recruitment.welcomeMessage .. "|r")
            end
        else
            GuildOS:Print(L["Usage: /guildos recruit welcome <on|off|msg> [text]"])
        end
    elseif cmd == "discord" then
        local link = args[2]
        if link and link ~= "" then
            GuildOS.db.recruitment.discord = link
            Recruitment:WelcomeChanged()
            GuildOS:Print(L["Discord link set to: |cffFFFFFF"] .. link .. "|r")
        else
            GuildOS:Print(L["Discord: |cffFFFFFF"] .. GuildOS.db.recruitment.discord .. "|r")
        end
    elseif cmd == "invite" then
        -- The whole name: on WoW: Forever "/gos recruit invite Chehul Costa" is one player (audit M14).
        local target = args[2] and strtrim(table.concat(args, " ", 2)) or nil
        if target and target ~= "" then
            if not CanGuildInvite() then
                GuildOS:Print(L["|cffFF4444You don't have permission to invite.|r"])
                return
            end
            local function invite()
                if GuildOS.Compat.GuildInvite(target) then
                    if GuildOS.RecruitEngagement then GuildOS.RecruitEngagement:RecordInvite(target) end
                    GuildOS:Print(L["Guild invite sent to |cffFFFFFF"] .. target .. "|r.")
                end
            end
            -- The alliance has banned them: the officer reads why first (#408).
            local BL = GuildOS.BanList
            if not (BL and BL.HoldInvite and BL:HoldInvite(target, invite)) then invite() end
        else
            GuildOS:Print(L["Usage: /guildos recruit invite <PlayerName>"])
        end
    elseif cmd == "autoinvite" or cmd == "ai" then
        table.remove(args, 1)
        Recruitment:HandleAutoInviteCommand(args)
    else
        GuildOS:Print(L["|cffFFD700Recruitment commands:|r"])
        GuildOS:Print("  /guildos recruit on/off")
        GuildOS:Print("  /guildos recruit status")
        GuildOS:Print("  /guildos recruit msg <text>")
        GuildOS:Print("  /guildos recruit interval <seconds>")
        GuildOS:Print("  /guildos recruit channel add/remove/list <name>")
        GuildOS:Print("  /guildos recruit welcome on/off/msg <text>")
        GuildOS:Print("  /guildos recruit discord <link>")
        GuildOS:Print("  /guildos recruit invite <PlayerName>")
    end
end

----------------------------------------------------------------------
-- Auto-invite command handler
----------------------------------------------------------------------
function Recruitment:HandleAutoInviteCommand(args)
    local cfg = GuildOS.db.recruitment and GuildOS.db.recruitment.autoInvite
    if not cfg then
        GuildOS:Print(L["Auto-invite is available to officers after login."])
        return
    end
    local sub = args[1]
    if sub == "on" then
        cfg.enabled = true
        GuildOS:Print(L["Auto-invite |cff4CFF4Cenabled|r (keyword: |cffFFFFFF"] .. cfg.keyword .. "|r).")
    elseif sub == "off" then
        cfg.enabled = false
        GuildOS:Print(L["Auto-invite |cffFF4444disabled|r."])
    elseif sub == "keyword" then
        local kw = args[2] and self:SetAutoInviteKeyword(cfg, args[2])
        if kw then
            GuildOS:Print(L["Auto-invite keyword set to |cffFFFFFF"] .. kw .. "|r.")
        elseif args[2] then
            GuildOS:Print(string.format(L["A keyword is one word of up to %d characters."], self.KEYWORD_MAX))
        else
            GuildOS:Print(L["Current keyword: |cffFFFFFF"] .. cfg.keyword .. "|r.")
        end
    elseif sub == "minlevel" then
        local n = self:SetAutoInviteMinLevel(cfg, args[2])
        if n then
            GuildOS:Print(string.format(L["Auto-invite min level set to |cffFFFFFF%d|r."], n))
        else
            GuildOS:Print(string.format(L["Usage: /gos autoinvite minlevel <0-%d>"], GuildOS.Client.maxLevel))
        end
    elseif sub == "class" then
        local op, cls = args[2], args[3]
        if op == "clear" then
            cfg.classes = {}
            GuildOS:Print(L["Auto-invite class filter cleared."])
        elseif (op == "add" or op == "remove") and cls then
            if self:SetAutoInviteClass(cfg, cls, op == "add") then
                GuildOS:Print(L["Auto-invite class filter updated."])
            else
                GuildOS:Print(L["Unknown class: "] .. cls .. " (" .. table.concat(self.CLASSES, ", ") .. ")")
            end
        else
            GuildOS:Print(L["Usage: /gos autoinvite class <add|remove|clear> <CLASS>"])
        end
    elseif sub == "fallback" then
        if self:SetAutoInviteFallback(cfg, args[2]) then
            GuildOS:Print(L["When /who cannot confirm a player: |cffFFFFFF"] .. cfg.whoFallback .. "|r")
        else
            GuildOS:Print(L["Usage: /gos autoinvite fallback <skip|invite>"])
        end
    else
        local st = cfg.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        local classes = {}
        for _, c in ipairs(self.CLASSES) do
            if cfg.classes[c] then classes[#classes + 1] = c end
        end
        GuildOS:Print(L["Auto-invite: "] .. st .. L[" · keyword: |cffFFFFFF"] .. cfg.keyword ..
            L["|r · min level: |cffFFFFFF"] .. tostring(cfg.minLevel) .. "|r · " .. L["classes: "] ..
            (#classes > 0 and table.concat(classes, ", ") or L["any"]) .. " · " .. L["unconfirmed: "] .. cfg.whoFallback)
        GuildOS:Print(L["Usage: /gos autoinvite <on|off|keyword|minlevel|class|fallback|status>"])
        GuildOS:Print(string.format(L["Also in the %s tab, under %s."], L["Recruitment"], L["Recruiting"]))
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
    GuildOS.Compat.RegisterEvent(frame, "CHAT_MSG_SYSTEM")
    frame:SetScript("OnEvent", function(_, event, msg)
        if GuildOS.Compat.IsSecret(msg) then return end  -- chat in lockdown: nothing readable
        if event ~= "CHAT_MSG_SYSTEM" then return end
        if not IsInGuild() then return end
        if not Recruitment._rosterReady then return end

        -- Detect "%s has joined the guild." ("%s" or a numbered "%1$s", #160)
        local args = GuildOS:MatchFormat(msg, ERR_GUILD_JOIN_S)
        local newMember = args and args[1]

        -- Fallback patterns for PT/EN clients
        if not newMember then
            newMember = msg:match("(.+) entrou na guilda%.")
                     or msg:match("(.+) has joined the guild%.")
        end

        if not newMember then return end

        -- Don't act on our own join.
        local myName = GuildOS.Compat.PlayerName()
        if newMember == myName then return end

        -- Credit a recruitment join to whoever invited this player. This runs
        -- regardless of the welcome feature (engagement tracking is independent);
        -- RecordJoin only credits when THIS client has a matching pending invite.
        if GuildOS.RecruitEngagement then GuildOS.RecruitEngagement:RecordJoin(newMember) end

        -- The welcome message itself is opt-in and gated separately.
        if not GuildOS.db.recruitment.welcomeEnabled then return end

        Recruitment._knownMembers[newMember] = true
        Recruitment:OnJoinWelcome(newMember)
    end)
end

-- The game's line said `newMember` joined, on an officer's client with the welcome on: the election (above) decides
-- whether this client sends it, after its place's delay, unless a claim came first.
function Recruitment:OnJoinWelcome(newMember)
    local myName = GuildOS.Compat.PlayerName()
    self._welcomedRecently = self._welcomedRecently or {}
    self._welcomeIntents = self._welcomeIntents or {}
    -- Dedup: already handled on this client, or welcomed within WELCOME_ONCE (a claim heard, a /reload since).
    if self._welcomedRecently[newMember] or self:RecentlyWelcomed(newMember) then return false end
    self._welcomedRecently[newMember] = true
    C_Timer.After(90, function()
        Recruitment._welcomedRecently[newMember] = nil
        Recruitment._welcomeIntents[newMember]  = nil
    end)
    self._welcomeIntents[newMember] = self._welcomeIntents[newMember] or {}
    self._welcomeIntents[newMember][myName] = true
    -- For an officer on a client before #449: its tie-break reads the intents.
    if GuildOS.CommSystem then
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.WELCOME_INTENT, newMember, nil, "ALERT")
    end
    local delay = self.WELCOME_FIRST + self:WelcomePlace() * self.WELCOME_STEP
    self._lastWelcomeDelay = delay   -- the tests read it
    C_Timer.After(delay, function()
        -- Another officer's claim came first (it marks the member welcomed here too).
        if Recruitment._welcomedRecently[newMember .. "_sent"] then return end
        if Recruitment:RecentlyWelcomed(newMember) then return end
        Recruitment._welcomedRecently[newMember .. "_sent"] = true
        Recruitment:MarkWelcomed(newMember)
        if GuildOS.CommSystem then
            GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.WELCOME_CLAIM, newMember, nil, "ALERT")
        end
        -- A member who returns gets the officers' welcome back, when they wrote one (#449).
        local back = Recruitment:BackInfo(newMember)
        local welcomeMsg = Recruitment:WelcomeMessage(back)
        if welcomeMsg and welcomeMsg ~= "" then
            if GuildOS.Compat.NeedsClick() then
                -- Forever drops a line sent from this timer: the officer's click sends it (#61).
                -- The claim above already went out, so the other officers stand down: the
                -- popup stays up until this officer sends or dismisses it.
                Recruitment:QueueWelcome(newMember)
            else
                Recruitment:SendWelcomeText(welcomeMsg, newMember, back)
            end
        end
    end)
    return true
end
