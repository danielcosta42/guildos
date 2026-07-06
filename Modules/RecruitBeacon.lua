----------------------------------------------------------------------
-- RecruitBeacon — guild recruitment over the Chehul mesh.
--
-- Two sides, both riding the shared transport _G.ChehulMesh:
--   * Officers compose a recruitment ad (roles/classes wanted, days, a note)
--     and their client re-broadcasts it while enabled.
--   * Anyone (guildless players looking for a guild) receives ads into a
--     runtime inbox, filters them, and sees which ads want THEIR class.
--
-- Reach reality (LibChehulMesh v3): the wide bus is YELL — zone/city-wide and
-- same-faction/same-layer, NOT the literal realm. That is exactly where
-- guildless players gather (Shattrath/Orgrimmar/IF), so a beacon yelled from a
-- capital reaches them. Guildmates also get it over the Guild bus.
--
-- ── OPEN PROTOCOL (shared contract; any Chehul addon may broadcast/consume) ──
--   prefix : "ChehulRecruit"
--   ad     : "CR1|<guild>|<faction>|<needs>|<days>|<note>"
--     guild   : guild name (no '|')
--     faction : "A" | "H"
--     needs   : '+'-joined tokens — roles (TANK/HEALER/DPS) and/or class tokens
--               (WARRIOR, MAGE, …), e.g. "HEALER+PRIEST+SHAMAN"
--     days    : short free text, e.g. "Tue,Thu 20-23" (no '|')
--     note    : free text (no '|'; sanitised on store)
----------------------------------------------------------------------
local RB = {}
GuildOS.RecruitBeacon = RB

RB.PREFIX = "ChehulRecruit"   -- shared suite-level prefix
RB.PROTO  = "CR1"
RB.AD_TTL = 900               -- forget a received ad after 15 min unheard
RB.BROADCAST_INTERVAL = 60    -- officer re-broadcast cadence (seconds)

-- The vocabulary an officer picks from and a recruit filters on.
RB.ROLE_TOKENS  = { "TANK", "HEALER", "DPS" }
RB.CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                    "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

RB.inbox = {}   -- [guildName] = { guild, faction, needs=set, days, note, from, ts }
RB.onUpdate = nil  -- UI hook, set by the inbox panel

local function sanitize(s)
    return (tostring(s or ""):gsub("|", "/"))
end

----------------------------------------------------------------------
-- Officer ad (persisted per officer client). Shape:
--   db.recruitBeacon = { enabled=bool, needs={token,…}, days="", note="" }
----------------------------------------------------------------------
function RB:GetAd()
    if not BRutus.db then return nil end
    if not BRutus.db.recruitBeacon then
        BRutus.db.recruitBeacon = { enabled = false, needs = {}, days = "", note = "" }
    end
    return BRutus.db.recruitBeacon
end

function RB:SetAdField(key, value)
    local ad = self:GetAd()
    if ad then ad[key] = value end
end

----------------------------------------------------------------------
-- Init: register receive + start the officer broadcast ticker.
----------------------------------------------------------------------
function RB:Initialize()
    local mesh = _G.ChehulMesh
    if mesh and not self._registered then
        self._registered = true
        mesh:Register(self.PREFIX, function(payload, sender, dist)
            RB:OnMessage(payload, sender, dist)
        end)
    end
    if C_Timer and C_Timer.NewTicker and not self._ticker then
        self._ticker = C_Timer.NewTicker(self.BROADCAST_INTERVAL, function() RB:Broadcast() end)
        if C_Timer.After then C_Timer.After(8, function() RB:Broadcast() end) end
    end
end

----------------------------------------------------------------------
-- Officer side: broadcast the guild's ad (guild bus + zone-wide YELL).
----------------------------------------------------------------------
function RB:Broadcast()
    local ad = self:GetAd()
    if not ad or not ad.enabled then return end
    if not (BRutus.IsOfficer and BRutus:IsOfficer()) then return end
    if IsInGuild and not IsInGuild() then return end
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild or guild == "" then return end
    local mesh = _G.ChehulMesh
    if not mesh then return end

    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A" or "H"
    local needs = table.concat(ad.needs or {}, "+")
    local payload = table.concat({
        self.PROTO, sanitize(guild), faction, needs, sanitize(ad.days), sanitize(ad.note),
    }, "|")

    mesh:Guild(self.PREFIX, payload)                 -- guildmates (informational)
    mesh:Realm(self.PREFIX, payload, self.PREFIX)    -- zone-wide YELL (the recruits)
end

----------------------------------------------------------------------
-- Receive side: store incoming ads (dedup by guild, ignore our own guild).
----------------------------------------------------------------------
function RB:OnMessage(payload, sender, _dist)
    if type(payload) ~= "string" then return end
    local proto, guild, faction, needs, days, note = strsplit("|", payload)
    if proto ~= self.PROTO or not guild or guild == "" then return end

    -- Don't inbox our own guild's ad (we're not a recruit for it).
    local myGuild = GetGuildInfo and GetGuildInfo("player")
    if myGuild and myGuild == guild then return end

    local needsSet = {}
    for t in string.gmatch(needs or "", "[^+]+") do needsSet[t] = true end

    self.inbox[guild] = {
        guild   = guild,
        faction = faction,
        needs   = needsSet,
        days    = days or "",
        note    = note or "",
        from    = sender,
        ts      = time(),
    }
    if self.onUpdate then pcall(self.onUpdate) end
end

----------------------------------------------------------------------
-- Received ads (freshest first), pruning stale ones past AD_TTL.
----------------------------------------------------------------------
function RB:GetInbox()
    local now = time()
    local list = {}
    for g, ad in pairs(self.inbox) do
        if (now - (ad.ts or 0)) > self.AD_TTL then
            self.inbox[g] = nil
        else
            list[#list + 1] = ad
        end
    end
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return list
end

-- Does an ad want the local player's class? (auto-highlight for recruits.)
function RB:AdMatchesMe(ad)
    if not ad or not ad.needs then return false end
    local _, class = UnitClass("player")
    return class ~= nil and ad.needs[class] == true
end
