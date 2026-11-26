----------------------------------------------------------------------
-- Guild OS - Raid Tools
-- Composition / buff coverage / cooldown coverage for the current group
-- (or online guild members when not grouped). Business logic only.
----------------------------------------------------------------------
local RaidTools = {}
GuildOS.RaidTools = RaidTools
local L = GuildOS.L

-- Class display order for the composition breakdown: this game's classes (thirteen on retail).
RaidTools.CLASS_ORDER = GuildOS.Client.classes

-- Key raid-wide buffs and the classes that provide them (TBC).
RaidTools.BUFFS = {
    { name = L["Stamina"],        classes = { PRIEST = true } },
    { name = L["Intellect"],      classes = { MAGE = true } },
    { name = L["Spirit"],         classes = { PRIEST = true } },
    { name = L["Stats (GotW)"],   classes = { DRUID = true } },
    { name = L["Attack Power"],    classes = { WARRIOR = true, PALADIN = true } },
    { name = L["Blessings"],      classes = { PALADIN = true } },
    { name = L["Totems"],         classes = { SHAMAN = true } },
}

-- Key raid cooldowns and their provider classes: the one list Raid Tools' coverage and the raid
-- cooldown HUD both read (audit B19). For the HUD, an entry it tracks has `key`, `iconID` (the icon's
-- spell), `spellIDs` (every rank that counts as a use), `cooldown` (approximate seconds, for the
-- timer only) and `short`, its label in the HUD's narrow column; one without spellIDs is coverage only.
RaidTools.COOLDOWNS = {
    { name = L["Bloodlust/Heroism"], short = L["Bloodlust/Hero"], classes = { SHAMAN = true }, tbc = true,  -- TBC spells (ADR-0014)
      key = "bloodlust", iconID = 2825, cooldown = 600, spellIDs = { 2825, 32182 } },
    { name = L["Battle Rez"], classes = { DRUID = true },
      key = "rebirth", iconID = 20484, cooldown = 1800, spellIDs = { 20484, 20748, 20747, 20742, 20739, 20737 } },
    { name = L["Innervate"], classes = { DRUID = true },
      key = "innervate", iconID = 29166, cooldown = 360, spellIDs = { 29166 } },
    { name = L["Power Infusion"], classes = { PRIEST = true },
      key = "pi", iconID = 10060, cooldown = 180, spellIDs = { 10060 } },
    { name = L["Misdirection"], classes = { HUNTER = true }, tbc = true,
      key = "md", iconID = 34477, cooldown = 30, spellIDs = { 34477 } },
    { name = L["Soulstone"],         classes = { WARLOCK = true } },
    { name = L["Salvation"],         classes = { PALADIN = true } },
    { name = L["Lay on Hands"], classes = { PALADIN = true },
      key = "loh", iconID = 633, cooldown = 3600, spellIDs = { 633, 2800, 10310 } },
    { name = L["Div. Intervention"], classes = { PALADIN = true },
      key = "di", iconID = 19752, cooldown = 3600, spellIDs = { 19752 } },
    { name = L["Pain Suppression"], classes = { PRIEST = true }, tbc = true,
      key = "ps", iconID = 33206, cooldown = 180, spellIDs = { 33206 } },
    { name = L["Shadowfiend"], classes = { PRIEST = true }, tbc = true,
      key = "sf", iconID = 34433, cooldown = 300, spellIDs = { 34433 } },
    { name = L["Tranquility"], classes = { DRUID = true },
      key = "tranquility", iconID = 740, cooldown = 300, spellIDs = { 740, 8918, 9862, 9863 } },
    { name = L["Shield Wall"], classes = { WARRIOR = true },
      key = "shieldwall", iconID = 871, cooldown = 1800, spellIDs = { 871 } },
    { name = L["Last Stand"], classes = { WARRIOR = true },
      key = "laststand", iconID = 12975, cooldown = 480, spellIDs = { 12975 } },
}

-- Retail's (Midnight, ADR-0026): one class per raid buff, and the cooldowns several classes share.
-- `spell` names the entry in the reader's language; `name` is the fallback while the client has no
-- name for it. Checked against build 12.1.5.70448's SpellName.
if GuildOS.Client.isRetail then
    RaidTools.BUFFS = {
        { spell = 21562,  name = "Power Word: Fortitude",  classes = { PRIEST = true } },
        { spell = 1459,   name = "Arcane Intellect",       classes = { MAGE = true } },
        { spell = 1126,   name = "Mark of the Wild",       classes = { DRUID = true } },
        { spell = 6673,   name = "Battle Shout",           classes = { WARRIOR = true } },
        { spell = 462854, name = "Skyfury",                classes = { SHAMAN = true } },
        { spell = 364342, name = "Blessing of the Bronze", classes = { EVOKER = true } },
        { spell = 8647,   name = "Mystic Touch",           classes = { MONK = true } },
        { spell = 1490,   name = "Chaos Brand",            classes = { DEMONHUNTER = true } },
        { spell = 257284, name = "Hunter's Mark",          classes = { HUNTER = true } },
        { spell = 465,    name = "Devotion Aura",          classes = { PALADIN = true } },
    }
    RaidTools.COOLDOWNS = {
        { spell = 2825,  name = "Bloodlust",      classes = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true } },
        { spell = 20484, name = "Rebirth",        classes = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true } },
        { spell = 29166, name = "Innervate",      classes = { DRUID = true } },
        { spell = 10060, name = "Power Infusion", classes = { PRIEST = true } },
        { spell = 20707, name = "Soulstone",      classes = { WARLOCK = true } },
    }
end

-- The cooldowns the raid HUD tracks: COOLDOWNS' entries with spells, this game's only (ADR-0014).
function RaidTools:TrackedCooldowns()
    local out = {}
    for _, def in ipairs(self.COOLDOWNS) do
        if def.spellIDs and (not def.tbc or GuildOS.Client.isAnniversary) then out[#out + 1] = def end
    end
    return out
end

-- The tracked cooldown a spell id is a use of, or nil.
function RaidTools:CooldownOfSpell(spellID)
    if not self._bySpell then
        self._bySpell = {}
        for _, def in ipairs(self:TrackedCooldowns()) do
            for _, sid in ipairs(def.spellIDs) do self._bySpell[sid] = def end
        end
    end
    return self._bySpell[spellID]
end

-- The combat log's affiliation bits are its flags' lowest three: mine, my party's, my raid's (the
-- client's COMBATLOG_OBJECT_AFFILIATION_MINE 0x1, _PARTY 0x2 and _RAID 0x4); outsiders have 0x8.
local AFFILIATION_GROUP_BITS = 8   -- flags modulo this keep the three group bits
-- Whether a combat log caster is one of the raid (audit B19): the HUD logs nobody else's cooldowns.
function RaidTools:IsRaidCaster(srcFlags)
    local flags = tonumber(srcFlags)
    return flags ~= nil and flags >= 0 and flags % AFFILIATION_GROUP_BITS ~= 0
end

-- Returns (list, sourceLabel). list = { { name, class }, ... }.
-- Uses the raid/party if grouped, otherwise online guild members.
function RaidTools:GetSource()
    local list = {}
    if IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            -- A member the client keeps secret cannot be matched or counted (issue #184).
            if name and not GuildOS.Compat.IsSecret(name, classFile) then
                list[#list + 1] = { name = name:match("^([^-]+)") or name, class = classFile or "" }
            end
        end
        return list, L["Current raid"]
    elseif IsInGroup() then
        local _, classFile = UnitClass("player")
        list[#list + 1] = { name = GuildOS.Compat.PlayerName(), class = classFile or "" }
        for i = 1, (GetNumGroupMembers() or 1) - 1 do
            local unit = "party" .. i
            local nm, _, cf
            if UnitExists(unit) then nm, _, cf = GuildOS.Compat.UnitIdentity(unit) end
            if nm then
                list[#list + 1] = { name = nm, class = cf or "" }
            end
        end
        return list, L["Current party"]
    end
    -- Fallback: online guild members.
    local num = GetNumGuildMembers() or 0
    for i = 1, num do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            list[#list + 1] = { name = name:match("^([^-]+)") or name, class = classFile or "" }
        end
    end
    return list, L["Online guild members"]
end

-- Count members per class for a source list.
function RaidTools:GetClassCounts(list)
    local counts = {}
    for _, m in ipairs(list) do
        if m.class and m.class ~= "" then
            counts[m.class] = (counts[m.class] or 0) + 1
        end
    end
    return counts
end

-- For each definition in `defs` (BUFFS or COOLDOWNS), resolve which present
-- classes provide it. Returns { { name, covered, providers = {classFile,...} }, ... }.
function RaidTools:ResolveCoverage(defs, classCounts)
    local result = {}
    for _, def in ipairs(defs) do
        if not def.tbc or GuildOS.Client.isAnniversary then  -- TBC-only spells stay off other clients (ADR-0014)
            local providers = {}
            for classFile in pairs(def.classes) do
                if (classCounts[classFile] or 0) > 0 then
                    providers[#providers + 1] = classFile
                end
            end
            result[#result + 1] = {
                name = (def.spell and GuildOS.Compat.GetSpellInfo(def.spell)) or def.name,
                covered = #providers > 0,
                providers = providers,
            }
        end
    end
    return result
end

----------------------------------------------------------------------
-- The raid leader's night (#449; specs/salao/raidtools.md)
--
-- Four moments, one screen (UI/RaidToolsPanel.lua): build the raid before the pull (who signed up,
-- the roles against what the instance needs, who is missing, the invites), organise the five parties
-- (totems, auras and buffs per party, a suggestion, applying it, saying it in raid chat), the readiness
-- of the raid (consumables, enchants, attunement, the fight's resistance, who lacks the addon, the
-- ready and role checks) and the fight (who tanks, heals and interrupts what, per boss, saved per
-- instance and pre-filled from the site's plan; the pull timer and the marks). The in-combat part is
-- the cooldown HUD (Modules/RaidHUD.lua). Who the screen reads is chosen on the spot: the group as it
-- is, the site's raid (GOSROST1, Modules/CompanionImport.lua) or the guild members online.
-- Business logic only; everything a test needs is a function of plain tables where it can be.
----------------------------------------------------------------------
local ROLES = { "TANK", "HEALER", "DPS" }
RaidTools.ROLES = ROLES
RaidTools.SOURCES = { "group", "site", "guild" }
RaidTools.PARTS = { "build", "groups", "ready", "fight" }
local PARTY_MAX, RAID_GROUPS, RAID_MAX = 5, 8, 40
local FIRST_WAVE = PARTY_MAX - 1
local INVITE_WAIT = 60      -- seconds an invite is left to its answer before a click asks again
local SAY_GAP = 8           -- seconds between two announcements of one kind
local CHAT_LINE = 240       -- bytes of a chat line (the game's limit is 255)
local SAY_LINES = 3         -- an announcement is one to three lines

-- What each raid of this game needs: its size, the tanks and healers a sensible night brings, the
-- attunement and the resistance its fights ask for, and its bosses (the boss picker of the Fight part).
-- The raid leader edits the targets per raid (SetTarget); the rest is fixed. Keys are the site's.
RaidTools.TBC_INSTANCES = {
    { key = "kara",  name = "Karazhan", map = 532, size = 10, tank = 2, healer = 3, attune = "Kara",
      bosses = { "Attumen the Huntsman", "Moroes", "Maiden of Virtue", "Opera Event", "The Curator", "Terestian Illhoof",
                 "Shade of Aran", "Netherspite", "Chess Event", "Prince Malchezaar", "Nightbane" } },
    { key = "za",    name = "Zul'Aman", map = 568, size = 10, tank = 2, healer = 3,
      bosses = { "Nalorakk", "Akil'zon", "Jan'alai", "Halazzi", "Hex Lord Malacrass", "Zul'jin" } },
    { key = "gruul", name = "Gruul's Lair", map = 565, size = 25, tank = 3, healer = 6, attune = "Gruul",
      bosses = { "High King Maulgar", "Gruul the Dragonkiller" } },
    { key = "mag",   name = "Magtheridon's Lair", map = 544, size = 25, tank = 3, healer = 6, attune = "Mag", bosses = { "Magtheridon" } },
    { key = "ssc",   name = "Serpentshrine Cavern", map = 548, size = 25, tank = 3, healer = 7, attune = "SSC", resist = "nature",
      bosses = { "Hydross the Unstable", "The Lurker Below", "Leotheras the Blind", "Fathom-Lord Karathress",
                 "Morogrim Tidewalker", "Lady Vashj" } },
    { key = "tk",    name = "Tempest Keep", map = 550, size = 25, tank = 3, healer = 7, attune = "TK", resist = "arcane",
      bosses = { "Al'ar", "Void Reaver", "High Astromancer Solarian", "Kael'thas Sunstrider" } },
    { key = "hyjal", name = "Hyjal Summit", map = 534, size = 25, tank = 3, healer = 7, attune = "Hyjal",
      bosses = { "Rage Winterchill", "Anetheron", "Kaz'rogal", "Azgalor", "Archimonde" } },
    { key = "bt",    name = "Black Temple", map = 564, size = 25, tank = 3, healer = 7, attune = "BT", resist = "shadow",
      bosses = { "High Warlord Naj'entus", "Supremus", "Shade of Akama", "Teron Gorefiend", "Gurtogg Bloodboil",
                 "Reliquary of Souls", "Mother Shahraz", "The Illidari Council", "Illidan Stormrage" } },
    { key = "swp",   name = "Sunwell Plateau", map = 580, size = 25, tank = 3, healer = 7,
      bosses = { "Kalecgos", "Brutallus", "Felmyst", "Eredar Twins", "M'uru", "Kil'jaeden" } },
}
-- WoW: Forever: the raids Modules/RaidTracker.lua has a map for (FOREVER_RAID_KEYS). The others come by
-- the site's roster and take the targets of their size.
RaidTools.FOREVER_INSTANCES = {
    { key = "forever-onyxia", name = "Onyxia's Lair", map = 249, size = 40, tank = 3, healer = 9, bosses = { "Onyxia" } },
}
-- The targets of a raid nobody listed, by its size.
local SIZE_TARGETS = { [5] = { 1, 1 }, [10] = { 2, 3 }, [20] = { 2, 5 }, [25] = { 3, 7 }, [30] = { 3, 7 }, [40] = { 4, 10 } }

local function instances()
    local c = GuildOS.Client
    if c.isAnniversary then return RaidTools.TBC_INSTANCES end
    if c.isRetail then return {} end
    return RaidTools.FOREVER_INSTANCES
end

--- This game's raids, in their order.
function RaidTools:InstanceList()
    return instances()
end

--- The raid of this game with the site's `key`, or nil.
function RaidTools:Instance(key)
    for _, def in ipairs(instances()) do
        if def.key == key then return def end
    end
    return nil
end

--- The raid's name in the reader's language where the client knows the map, else its English one.
function RaidTools:InstanceName(def)
    if not def then return "" end
    local name = def.map and GuildOS.Compat.InstanceName(def.map)
    return name or def.name or def.key
end

----------------------------------------------------------------------
-- Saved choices (GuildOS.db.raidTools): the source, the raid, the part, the targets and the assignments
----------------------------------------------------------------------
function RaidTools:Store()
    local db = GuildOS.db
    if not db then return { targets = {}, assign = {} } end
    db.raidTools = type(db.raidTools) == "table" and db.raidTools or {}
    local s = db.raidTools
    s.targets = type(s.targets) == "table" and s.targets or {}
    s.assign = type(s.assign) == "table" and s.assign or {}
    return s
end

function RaidTools:SourceKind()
    local k = self:Store().source
    for _, v in ipairs(self.SOURCES) do
        if v == k then return k end
    end
    -- Nothing chosen: the group when there is one, else the site's raid when one is in hand, else the guild.
    if IsInGroup and IsInGroup() then return "group" end
    if self:SiteRoster() then return "site" end
    return "guild"
end

function RaidTools:SetSourceKind(kind)
    for _, v in ipairs(self.SOURCES) do
        if v == kind then self:Store().source = kind; return true end
    end
    return false
end

----------------------------------------------------------------------
-- The site's raids (GOSROST1)
----------------------------------------------------------------------

--- The raids the companion carries for this guild: the kept roster and this session's inbox, each raid
--- once, soonest first.
function RaidTools:SiteRaids()
    local I = GuildOS.CompanionImport
    if not I then return {} end
    local out, seen = {}, {}
    local function add(r)
        if type(r) ~= "table" then return end
        if not r.pasted and I.OfThisGuild and not I.OfThisGuild(r) then return end
        local id = r.raidId or r
        if seen[id] then return end
        seen[id] = true
        out[#out + 1] = r
    end
    add(I.Current and I:Current())
    for _, r in ipairs(I._webRaids or {}) do add(r) end
    table.sort(out, function(a, b) return (tonumber(a.startsAt) or 0) < (tonumber(b.startsAt) or 0) end)
    return out
end

--- The site's raid the screen reads: the one chosen (RosterOf), else the raid of the window (ActiveRoster),
--- else the next one to start, else the last one; nil with none.
function RaidTools:SiteRoster(now)
    local I = GuildOS.CompanionImport
    if not I then return nil end
    local id = self:Store().raidId
    local chosen = id ~= nil and I.RosterOf and I:RosterOf(id)
    if chosen then return chosen end
    local active = I.ActiveRoster and I:ActiveRoster(now)
    if active then return active end
    local list = self:SiteRaids()
    now = now or GetServerTime()
    for _, r in ipairs(list) do
        if (tonumber(r.startsAt) or 0) >= now - 3 * 3600 then return r end
    end
    return list[#list]
end

function RaidTools:ChooseSiteRaid(raidId)
    self:Store().raidId = raidId
end

----------------------------------------------------------------------
-- The raid the night is for, and what it needs
----------------------------------------------------------------------

--- The raid key the screen measures against, and the size: the site's raid when the source is the site
--- (or the group is the site's raid), the instance the player stands in, the raid picked by hand, else the
--- first of this game's list. Returns key, size (either may be nil on retail).
function RaidTools:CurrentInstance(kind, roster)
    kind = kind or self:SourceKind()
    if kind == "site" then
        roster = roster or self:SiteRoster()
        if roster and roster.instanceKey then return roster.instanceKey, tonumber(roster.size) end
    end
    local picked = self:Store().instance
    if picked and self:Instance(picked) then return picked, self:Instance(picked).size end
    local mapID = GuildOS.Compat.CurrentInstance and GuildOS.Compat.CurrentInstance()
    local RTr = GuildOS.RaidTracker
    local here = mapID and RTr and RTr.RaidKeyOf and RTr:RaidKeyOf(mapID)
    if here and self:Instance(here) then return here, self:Instance(here).size end
    -- Nowhere known: no raid, and the size of this game's main raid until the raid leader picks one.
    return nil, GuildOS.Client.defaultRaidSize
end

function RaidTools:PickInstance(key)
    self:Store().instance = key
end

--- What a raid needs: { size, tank, healer, dps, edited }. The raid leader's own numbers for this raid
--- first, then the list's, then those of its size.
function RaidTools:Targets(key, size)
    local def = key and self:Instance(key)
    size = tonumber(size) or (def and def.size) or (GuildOS.Client.defaultRaidSize) or 25
    local base = SIZE_TARGETS[size]
    local tank, healer = def and def.tank or (base and base[1]) or math.max(1, math.floor(size / 8)),
                         def and def.healer or (base and base[2]) or math.max(1, math.floor(size / 4))
    local own = key and self:Store().targets[key]
    local edited = false
    if type(own) == "table" then
        if tonumber(own.tank) then tank, edited = tonumber(own.tank), true end
        if tonumber(own.healer) then healer, edited = tonumber(own.healer), true end
    end
    return { size = size, tank = tank, healer = healer, dps = math.max(0, size - tank - healer), edited = edited }
end

--- The raid leader sets how many `role` ("tank" or "healer") this raid needs; nil puts the default back.
function RaidTools:SetTarget(key, role, n)
    if not key or (role ~= "tank" and role ~= "healer") then return false end
    local t = self:Store().targets
    t[key] = type(t[key]) == "table" and t[key] or {}
    n = tonumber(n)
    t[key][role] = n and math.max(0, math.min(40, math.floor(n))) or nil
    if not t[key].tank and not t[key].healer then t[key] = nil end
    return true
end

----------------------------------------------------------------------
-- People: who the screen reads, each with a role and where they stand
----------------------------------------------------------------------
local ROLE_OF_CORE = { tank = "TANK", healer = "HEALER", mdps = "DPS", rdps = "DPS" }
-- Classes with one role in every game here: nobody needs to say what a mage does.
local DPS_ONLY = { HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true, DEMONHUNTER = false }

--- A person's role: the site's slot (what they signed up as), then the raiders' roster (an officer's word or
--- their own), then their seat on a core, then their class when it has one role. Returns role (TANK, HEALER,
--- DPS or nil) and whether it is a guess (the class's).
function RaidTools:RoleOf(key, class, slot)
    if slot == "TANK" or slot == "HEALER" then return slot, false end
    if slot == "MELEE" or slot == "RANGED" or slot == "DPS" then return "DPS", false end
    local RR = GuildOS.RaiderRoster
    local roles = key and RR and RR.EffectiveRoles and RR:EffectiveRoles(key)
    if type(roles) == "table" then
        for _, r in ipairs(ROLES) do
            if roles[r] then return r, false end
        end
    end
    local CM = GuildOS.CoreManager
    if key and CM and CM.GetSortedNames and CM.GetMembers then
        for _, name in ipairs(CM:GetSortedNames()) do
            local rec = CM:GetMembers(name)[key]
            local role = type(rec) == "table" and ROLE_OF_CORE[rec.role]
            if role then return role, false end
        end
    end
    if class and DPS_ONLY[class] then return "DPS", true end
    return nil, false
end

local function shortName(name)
    if type(name) ~= "string" then return "?" end
    if GuildOS.Client.has and GuildOS.Client.has.surnames then return name end
    return name:match("^([^-]+)") or name
end
RaidTools.ShortName = shortName

-- The group as the client lists it: { [key] = { group = 1..8 or 0, index = raid index or nil } }, me included,
-- each also under "~" and the first name on a client with surnames (a raid line may come without it).
local function groupIndex()
    local Compat = GuildOS.Compat
    local out = {}
    local function put(name, realm, group, index, class)
        if type(name) ~= "string" or name == "" or Compat.IsSecret(name) then return end
        local key = GuildOS:GetPlayerKey(shortName(name), realm)
        if not key then return end
        local e = { group = group or 0, index = index, name = shortName(name), class = class }
        out[key] = e
        if GuildOS.Client.has and GuildOS.Client.has.surnames then out["~" .. (name:match("^([^%s%-]+)") or name)] = e end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(GetNumGroupMembers() or 0, RAID_MAX) do
            local name, _, subgroup, _, _, classFile = GetRaidRosterInfo(i)
            if not Compat.IsSecret(name) and type(name) == "string" then
                local realm = name:match("^[^-]+%-(.+)$")
                if GuildOS.Client.has and GuildOS.Client.has.surnames then realm = nil end
                put(name, realm, not Compat.IsSecret(subgroup) and tonumber(subgroup) or 0, i, classFile)
            end
        end
    elseif IsInGroup and IsInGroup() then
        local _, myClass = UnitClass("player")
        put(Compat.PlayerName(), nil, 1, nil, myClass)
        for i = 1, (GetNumGroupMembers() or 1) - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local nm, realm, cf = Compat.UnitIdentity(unit)
                if GuildOS.Client.has and GuildOS.Client.has.surnames then
                    if type(realm) == "string" and realm ~= "" and nm and not nm:find(" ", 1, true) then nm = nm .. " " .. realm end
                    realm = nil
                end
                put(nm, realm, 1, nil, cf)
            end
        end
    end
    return out
end
RaidTools._GroupIndex = groupIndex

local function inGroupOf(index, key, name)
    local e = index[key]
    if e then return e end
    if GuildOS.Client.has and GuildOS.Client.has.surnames and type(name) == "string" then
        return index["~" .. (name:match("^([^%s%-]+)") or name)]
    end
    return nil
end

-- A site signup's place: signed (coming), standby, tentative, pending (no answer the site can act on) or
-- declined. `rescued` is CompanionImport:Rescued's: somebody the guild roster vouches for is coming.
local function siteStatus(s, rescued)
    if s.invite or (rescued and rescued[s.name]) then return "signed" end
    if s.why == "wait" or s.why == "bench" then return "standby" end
    if s.why == "tentative" then return "tentative" end
    if s.why == "unknown" or s.why == "pending" then return "pending" end
    if s.status == "yes" and not s.why then return "signed" end
    return "declined"
end
RaidTools.SiteStatus = siteStatus

local function keyOfSite(entry)
    if GuildOS.Client.isRetail and type(entry.key) == "string" and entry.key ~= "" then return entry.key end
    return GuildOS:GetPlayerKey(entry.name)
end

--- Who the screen reads, as a list of people: { name, key, class, role, guessed, status, inGroup, group,
--- index, online }, and the source's label. `kind`: "group", "site" or "guild" (the saved choice when nil).
--- status: "signed", "standby", "tentative", "pending", "declined" (site), "extra" (in the group, not on the
--- site's raid), "here" (group and guild sources). Declined signups are left out of the list.
function RaidTools:People(kind, roster)
    kind = kind or self:SourceKind()
    local index = groupIndex()
    local list, seen = {}, {}
    local function add(p)
        if not p.key or seen[p.key] then return end
        seen[p.key] = true
        local g = inGroupOf(index, p.key, p.name)
        p.inGroup = g ~= nil
        p.group = g and g.group or nil
        p.index = g and g.index or nil
        if (not p.class or p.class == "") and g then p.class = g.class or "" end
        if not p.role then p.role, p.guessed = self:RoleOf(p.key, p.class, p.slot) end
        list[#list + 1] = p
    end
    local label
    -- Off the site's source, what somebody signed up as on the site's raid still says their role.
    if kind ~= "site" then
        local site = self:SiteRoster()
        local slots = {}
        for _, e in ipairs(site and site.signups or {}) do
            if type(e) == "table" and type(e.name) == "string" and e.slot then slots[keyOfSite(e)] = e.slot end
        end
        local plain = add
        add = function(p)
            if p.key and not p.slot then p.slot = slots[p.key] end
            return plain(p)
        end
    end
    if kind == "site" then
        roster = roster or self:SiteRoster()
        label = roster and (roster.title ~= "" and roster.title) or L["The site's raid"]
        if roster then
            local I = GuildOS.CompanionImport
            local rescued = I and I.Rescued and I:Rescued(roster) or {}
            local signups = roster.signups
            if type(signups) ~= "table" then
                signups = {}
                for _, m in ipairs(roster.members or {}) do
                    signups[#signups + 1] = { name = m.name, key = m.key, class = m.class, slot = m.slot, invite = true }
                end
            end
            for _, s in ipairs(signups) do
                local status = siteStatus(s, rescued)
                if status ~= "declined" and type(s.name) == "string" then
                    add({ name = s.name, key = keyOfSite(s), class = s.class or "", slot = s.slot, status = status,
                          wait = tonumber(s.wait), plannedGroup = tonumber(s.group) })
                end
            end
            for key, e in pairs(index) do
                if key:sub(1, 1) ~= "~" and not seen[key] then
                    add({ name = e.name, key = key, class = e.class or "", status = "extra" })
                end
            end
        end
    elseif kind == "guild" then
        label = L["Online guild members"]
        for i = 1, (GetNumGuildMembers() or 0) do
            local full, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if full and online and not GuildOS.Compat.IsSecret(full) then
                add({ name = shortName(full), key = GuildOS:KeyOfRosterName(full), class = classFile or "", status = "here", online = true })
            end
        end
    else
        label = (IsInRaid and IsInRaid()) and L["Current raid"] or ((IsInGroup and IsInGroup()) and L["Current party"] or L["Not in a group"])
        local keys = {}
        for key in pairs(index) do if key:sub(1, 1) ~= "~" then keys[#keys + 1] = key end end
        table.sort(keys, function(a, b)
            local ea, eb = index[a], index[b]
            if (ea.group or 0) ~= (eb.group or 0) then return (ea.group or 0) < (eb.group or 0) end
            return (ea.index or 0) < (eb.index or 0)
        end)
        for _, key in ipairs(keys) do
            local e = index[key]
            add({ name = e.name, key = key, class = e.class or "", status = "here" })
        end
    end
    return list, label
end

--- How many of each role among the people who count (the site's: those signed and the extras already
--- here; standby, tentative and pending do not). Pure. Returns { TANK, HEALER, DPS, UNKNOWN, total }.
function RaidTools.CountRoles(people)
    local c = { TANK = 0, HEALER = 0, DPS = 0, UNKNOWN = 0, total = 0 }
    for _, p in ipairs(people) do
        local counts = p.status == nil or p.status == "signed" or p.status == "here" or p.status == "extra"
        if counts then
            local r = p.role
            if r == "TANK" or r == "HEALER" or r == "DPS" then c[r] = c[r] + 1 else c.UNKNOWN = c.UNKNOWN + 1 end
            c.total = c.total + 1
        end
    end
    return c
end

--- The roles against the targets: { { role, have, want, short } } in TANK, HEALER, DPS order. Pure.
function RaidTools.RoleGaps(counts, targets)
    local want = { TANK = targets.tank or 0, HEALER = targets.healer or 0, DPS = targets.dps or 0 }
    local out = {}
    for _, r in ipairs(ROLES) do
        local have = counts[r] or 0
        out[#out + 1] = { role = r, have = have, want = want[r], short = math.max(0, want[r] - have) }
    end
    return out
end

--- Who signed up and is not in the group yet (the site's source): the names to chase.
function RaidTools.Missing(people)
    local out = {}
    for _, p in ipairs(people) do
        if p.status == "signed" and not p.inGroup then out[#out + 1] = p end
    end
    return out
end

----------------------------------------------------------------------
-- Invites: the site's list, one step a click
----------------------------------------------------------------------
RaidTools._asked = {}

-- Whether `name` is banned here or by the alliance (BanList); the invite passes them over and names them.
local function banned(name)
    local BL = GuildOS.BanList
    if not BL or type(name) ~= "string" then return false end
    if BL.IsBanned and BL:IsBanned(name) then return true end
    if BL.AllianceBansFor and BL:AllianceBansFor(name) then return true end
    return false
end
RaidTools._Banned = banned

-- Who the guild roster shows offline, by key: an invite to them goes nowhere.
local function offlineKeys()
    local out = {}
    for i = 1, (GetNumGuildMembers() or 0) do
        local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if full and not GuildOS.Compat.IsSecret(online) and online == false then
            out[GuildOS:KeyOfRosterName(full)] = true
        end
    end
    return out
end

--- Who the invite would ask, from `people`: signed, not in the group, not me. Banned, offline and those asked
--- less than a minute ago are passed over and returned apart. Returns pending, skipped = { banned, offline,
--- waiting } (lists of people). `now` and `offline` are the tests' handles.
function RaidTools:InvitePlan(people, now, offline)
    now = now or GetTime()
    offline = offline or offlineKeys()
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName() or "")
    local pending, skipped = {}, { banned = {}, offline = {}, waiting = {} }
    for _, p in ipairs(people) do
        if p.status == "signed" and not p.inGroup and p.key ~= me then
            local at = self._asked[p.key]
            if at and now - at >= INVITE_WAIT then self._asked[p.key], at = nil, nil end
            if banned(p.name) then
                skipped.banned[#skipped.banned + 1] = p
            elseif offline[p.key] then
                skipped.offline[#skipped.offline + 1] = p
            elseif at then
                skipped.waiting[#skipped.waiting + 1] = p
            else
                pending[#pending + 1] = p
            end
        end
    end
    return pending, skipped
end

--- The name the invite API takes for a person.
local function inviteName(p)
    local I = GuildOS.CompanionImport
    if GuildOS.Client.isRetail and I and I.PlainName then return I.PlainName(p.key or p.name) end
    return p.name
end

--- One click of "Invite all missing": the invites the group has room for (alone, the first four; a party, its
--- free seats; a raid, everyone) or, in a party too small for the rest, turning it into a raid. On a client
--- where an invite needs a click of its own (WoW: Forever, Compat.NeedsClick) one person a click. Returns
--- { kind = "invite", names } / { kind = "convert" } / { kind = "wait" } / { kind = "done" } /
--- { kind = "blocked", reason }, with `skipped` (InvitePlan's) on all but blocked.
function RaidTools:InviteStep(people, now)
    local Compat = GuildOS.Compat
    if Compat.InCombat() then return { kind = "blocked", reason = L["Not during combat."] } end
    if not Compat.CanInvite() then return { kind = "blocked", reason = L["Only the group's leader or an assistant can invite."] } end
    now = now or GetTime()
    local pending, skipped = self:InvitePlan(people, now)
    if #pending == 0 then return { kind = #skipped.waiting > 0 and "wait" or "done", skipped = skipped } end
    local inRaid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers() or 0
    local room
    if inRaid then
        room = #pending
    elseif n >= 2 and n + #skipped.waiting + #pending > PARTY_MAX then
        if Compat.ConvertToRaid() then return { kind = "convert", skipped = skipped } end
        room = math.max(0, PARTY_MAX - n - #skipped.waiting)
    else
        room = math.max(0, (n <= 1 and FIRST_WAVE or PARTY_MAX - n) - #skipped.waiting)
    end
    if room == 0 then return { kind = "wait", skipped = skipped } end
    local oneByOne = Compat.NeedsClick()
    if oneByOne then room = 1 end
    local names = {}
    for i = 1, math.min(room, #pending) do
        local p = pending[i]
        Compat.InviteUnit(inviteName(p))
        self._asked[p.key] = now
        names[#names + 1] = p.name
    end
    -- One a click: the rest wait in the officer action queue too, one a key press of its binding (#449). Each is
    -- checked again at its press: who was asked meanwhile (this button again) is passed over.
    local AQ = GuildOS.ActionQueue
    if oneByOne and AQ then
        for i = room + 1, #pending do
            local p = pending[i]
            AQ:Add({ kind = "groupInvite", key = "raid:" .. tostring(p.key), name = p.name,
                     valid = function()
                         local asked = self._asked[p.key]
                         return not (asked and GetTime() - asked < INVITE_WAIT)
                     end,
                     run = function()
                         if Compat.InCombat() or not Compat.CanInvite() then return false end
                         Compat.InviteUnit(inviteName(p))
                         self._asked[p.key] = GetTime()
                         return true
                     end })
        end
    end
    return { kind = "invite", names = names, left = #pending - #names, skipped = skipped }
end

--- One person's invite from their row: a ban holds it behind the ban's dialog ("Invite anyway").
function RaidTools:InviteOne(p)
    if GuildOS.Compat.InCombat() then return false, L["Not during combat."] end
    if not GuildOS.Compat.CanInvite() then return false, L["Only the group's leader or an assistant can invite."] end
    local function go()
        GuildOS.Compat.InviteUnit(inviteName(p))
        RaidTools._asked[p.key] = GetTime()
    end
    local BL = GuildOS.BanList
    if BL and BL.HoldInvite and BL:HoldInvite(p.name, go) then return true, "held" end
    go()
    return true
end

----------------------------------------------------------------------
-- Groups: the parties, a suggestion, applying it
----------------------------------------------------------------------
local MELEE_SPEC = { Enhancement = true, Feral = true, ["Feral Combat"] = true, Retribution = true }

--- Where a person fights, for the parties: "tank", "healer", "melee", "hunter" or "caster". Pure but for the
--- spec the member data holds (`p.spec` wins).
function RaidTools.Cluster(p)
    if p.role == "TANK" then return "tank" end
    if p.role == "HEALER" then return "healer" end
    local c = p.class
    if c == "HUNTER" then return "hunter" end
    if c == "WARRIOR" or c == "ROGUE" or c == "DEATHKNIGHT" or c == "DEMONHUNTER" or c == "MONK" then return "melee" end
    if c == "MAGE" or c == "WARLOCK" or c == "PRIEST" or c == "EVOKER" then return "caster" end
    local spec = p.spec
    if not spec and p.key and GuildOS.db and GuildOS.db.members and GuildOS.db.members[p.key] then
        spec = GuildOS.db.members[p.key].spec
    end
    if type(spec) == "string" and MELEE_SPEC[spec] then return "melee" end
    if c == "PALADIN" then return "melee" end
    return "caster"
end

-- Which parties want a shaman's totems first, and a paladin's aura: melee and their Windfury, casters and
-- their mana; the tanks and their Devotion.
local SHAMAN_WANT = { melee = 1, caster = 2, healer = 3, hunter = 4, tank = 5 }
local PALADIN_WANT = { tank = 1, melee = 2, healer = 3, caster = 4, hunter = 5 }
local CLUSTER_ORDER = { tank = 1, melee = 2, hunter = 3, caster = 4, healer = 5 }

--- The parties a raid of `people` could stand in: tanks together in the first, then melee, hunters, casters
--- and healers, a seat in each kept for the shamans (one a party, melee first) and the paladins (one a party,
--- tanks first). Never more than five a party, everyone once. Pure. Returns parties: a list of lists.
function RaidTools.SuggestGroups(people, groups)
    local n = #people
    groups = math.max(1, math.min(RAID_GROUPS, groups or math.ceil(n / PARTY_MAX)))
    local core, shamans, paladins = {}, {}, {}
    for _, p in ipairs(people) do
        local cl = RaidTools.Cluster(p)
        local entry = { p = p, cluster = cl }
        if p.class == "SHAMAN" and cl ~= "tank" then shamans[#shamans + 1] = entry
        elseif p.class == "PALADIN" and cl ~= "tank" then paladins[#paladins + 1] = entry
        else core[#core + 1] = entry end
    end
    local function byCluster(a, b)
        local ca, cb = CLUSTER_ORDER[a.cluster] or 9, CLUSTER_ORDER[b.cluster] or 9
        if ca ~= cb then return ca < cb end
        return (a.p.name or "") < (b.p.name or "")
    end
    table.sort(core, byCluster)
    table.sort(shamans, byCluster)
    table.sort(paladins, byCluster)
    -- Seats held for the supports: one shaman and one paladin a party while they last.
    local held = {}
    for g = 1, groups do held[g] = 0 end
    for i = 1, math.min(#shamans, groups) do held[i] = held[i] + 1 end
    for i = 1, math.min(#paladins, groups) do held[i] = held[i] + 1 end
    local parties, kind = {}, {}
    for g = 1, groups do parties[g] = {} end
    local g = 1
    for _, e in ipairs(core) do
        while g <= groups and #parties[g] >= PARTY_MAX - held[g] do g = g + 1 end
        if g > groups then
            -- More people than the held seats leave: the first party with any room.
            for h = 1, groups do if #parties[h] < PARTY_MAX then g = h break end end
            if g > groups then break end
        end
        table.insert(parties[g], e.p)
        kind[g] = kind[g] or e.cluster
    end
    -- Each support to the party that wants them most and has none of their class yet, then any with room.
    local function place(list, want, class)
        for _, e in ipairs(list) do
            local best, bestRank
            for h = 1, groups do
                local has = false
                for _, q in ipairs(parties[h]) do if q.class == class then has = true break end end
                if not has and #parties[h] < PARTY_MAX then
                    local rank = want[kind[h] or "caster"] or 9
                    if not bestRank or rank < bestRank then best, bestRank = h, rank end
                end
            end
            if not best then
                for h = 1, groups do if #parties[h] < PARTY_MAX then best = h break end end
            end
            if best then
                table.insert(parties[best], e.p)
                kind[best] = kind[best] or e.cluster
            end
        end
    end
    place(shamans, SHAMAN_WANT, "SHAMAN")
    place(paladins, PALADIN_WANT, "PALADIN")
    return parties
end

--- What a party brings itself: totems (a shaman), an aura (a paladin), Battle Shout (a warrior), and the
--- party's ranged-or-melee kind. Pure. Returns { totems, aura, shout, trueshot? } booleans.
function RaidTools.PartyCoverage(members)
    local has = {}
    for _, p in ipairs(members) do has[p.class or ""] = true end
    return { totems = has.SHAMAN or false, aura = has.PALADIN or false, shout = has.WARRIOR or false,
             spirit = has.PRIEST or false }
end

--- The coverage as words: what the party has, and what it lacks with "no" before it.
function RaidTools.CoverageWords(members)
    if #members == 0 then return {} end
    local cov = RaidTools.PartyCoverage(members)
    local out = {}
    out[#out + 1] = { text = L["Totems"], ok = cov.totems }
    if not GuildOS.Client.isRetail then out[#out + 1] = { text = L["Aura"], ok = cov.aura } end
    if cov.shout then out[#out + 1] = { text = L["Shout"], ok = true } end
    return out
end

--- The raid as it stands, as parties of people (the group source's list): parties[1..8].
function RaidTools.PartiesOf(people)
    local parties = {}
    for g = 1, RAID_GROUPS do parties[g] = {} end
    for _, p in ipairs(people) do
        local g = tonumber(p.group) or 0
        if p.inGroup and g >= 1 and g <= RAID_GROUPS then table.insert(parties[g], p) end
    end
    return parties
end

--- The moves that take the raid's `lines` ({ index, group, key }) to `want` ({ [key] = group }): a move where
--- the group has a seat, a swap with somebody who does not belong there where it is full (one whose own target
--- is the mover's group first), none at all for somebody already in place. Pure; `canSwap` false plans no swap.
function RaidTools.PlanMoves(lines, want, canSwap)
    local count = {}
    for g = 1, RAID_GROUPS do count[g] = 0 end
    for _, l in ipairs(lines) do if count[l.group] then count[l.group] = count[l.group] + 1 end end
    local moves = {}
    for _, p in ipairs(lines) do
        local target = want[p.key]
        if target and p.group ~= target and count[target] then
            if count[target] < PARTY_MAX then
                count[p.group] = count[p.group] - 1
                count[target] = count[target] + 1
                p.group = target
                moves[#moves + 1] = { index = p.index, group = target }
            elseif canSwap then
                local best, bestRank
                for _, q in ipairs(lines) do
                    if q.group == target and want[q.key] ~= target then
                        local rank = (want[q.key] == p.group and 1) or (want[q.key] == nil and 2) or 3
                        if not bestRank or rank < bestRank then best, bestRank = q, rank end
                    end
                end
                if best then
                    best.group, p.group = p.group, target
                    moves[#moves + 1] = { index = p.index, swap = best.index }
                end
            end
        end
    end
    return moves
end

--- Whether the groups may be moved now, and why not.
function RaidTools:CanArrange()
    local Compat = GuildOS.Compat
    if not (IsInRaid and IsInRaid()) then return false, L["You need to be in a raid to organise groups."] end
    if not Compat.IsLeaderOrAssist() then return false, L["Only the raid leader or an assistant can organise groups."] end
    if Compat.InCombat() then return false, L["Not during combat."] end
    return true
end

--- Puts the raid into `parties` (lists of people with keys). Returns (moves made, err).
function RaidTools:ApplyGroups(parties)
    local ok, why = self:CanArrange()
    if not ok then return nil, why end
    local Compat = GuildOS.Compat
    local want, lines = {}, {}
    for g, list in ipairs(parties) do
        for _, p in ipairs(list) do want[p.key] = g end
    end
    for key, e in pairs(groupIndex()) do
        if key:sub(1, 1) ~= "~" and e.index and e.group and e.group >= 1 then
            lines[#lines + 1] = { index = e.index, group = e.group, key = key }
        end
    end
    table.sort(lines, function(a, b) return a.index < b.index end)
    local done = 0
    for _, m in ipairs(self.PlanMoves(lines, want, Compat.CanSwapRaidSubgroup())) do
        local moved
        if m.swap then moved = Compat.SwapRaidSubgroup(m.index, m.swap) else moved = Compat.SetRaidSubgroup(m.index, m.group) end
        if moved then done = done + 1 end
    end
    return done, nil
end

----------------------------------------------------------------------
-- Saying it in raid chat: one to three lines, never twice in a few seconds
----------------------------------------------------------------------

-- `s` cut to `n` bytes on a whole UTF-8 character (GuildOS:CutBytes), plain where the addon's utils are absent.
local function cutBytes(s, n)
    if GuildOS.CutBytes then return GuildOS:CutBytes(s, n) end
    s = s:sub(1, n)
    while #s > 0 do
        local b = s:byte(#s)
        if b < 0x80 then break end
        local i = #s
        while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
        local lead, need = s:byte(i), 1
        if lead >= 0xF0 then need = 4 elseif lead >= 0xE0 then need = 3 elseif lead >= 0xC0 then need = 2 end
        if #s - i + 1 >= need then break end
        s = s:sub(1, i - 1)
    end
    return s
end

--- `parts` (strings) joined with `sep` into at most SAY_LINES chat lines, `head` before the first; what does
--- not fit is cut with "…". A part longer than a line is split on its ", " items, an item longer than a line cut on
--- a whole character; a line is never the head alone. The game raises on a bare "|" in chat (a site's note or a
--- boss name can carry one), so every "|" goes. Pure.
local ELLIPSIS = "\226\128\166"
function RaidTools.Lines(head, parts, sep)
    sep = sep or " \194\183 "
    head = (head or ""):gsub("|", "")
    -- The pieces to lay: each part, or the items of one too long for a line.
    local pieces = {}
    for _, part in ipairs(parts or {}) do
        part = tostring(part or ""):gsub("|", "")
        if part ~= "" then
            if #head + #part <= CHAT_LINE then
                pieces[#pieces + 1] = { text = part, sep = sep }
            else
                local first = true
                for item in (part .. ", "):gmatch("(.-), ") do
                    if item ~= "" then
                        if #item > CHAT_LINE - #head then item = cutBytes(item, CHAT_LINE - #head - #ELLIPSIS) .. ELLIPSIS end
                        pieces[#pieces + 1] = { text = item, sep = first and sep or ", " }
                        first = false
                    end
                end
            end
        end
    end
    local lines, cur = {}, head
    for _, pc in ipairs(pieces) do
        local add = (cur == head) and pc.text or (pc.sep .. pc.text)
        if #cur + #add > CHAT_LINE and cur ~= head then
            lines[#lines + 1] = cur
            if #lines >= SAY_LINES then
                lines[#lines] = cutBytes(lines[#lines], CHAT_LINE - #ELLIPSIS) .. ELLIPSIS
                return lines
            end
            cur = pc.text
        else
            cur = cur .. add
        end
    end
    if cur ~= "" and cur ~= head then lines[#lines + 1] = cur end
    return lines
end

RaidTools._said = {}

--- Says `lines` in the raid's chat (the party's in a party), at most three, `kind` at most once every few
--- seconds. Out of a group it prints them here. Returns (lines said, err): no line gone is an error, and does not
--- hold the next try back.
function RaidTools:Say(kind, lines, now)
    now = now or GetTime()
    if #lines == 0 then return nil, L["Nothing to say."] end
    local last = self._said[kind]
    if last and now - last < SAY_GAP then return nil, L["Just said: wait a few seconds."] end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    local said = 0
    for i = 1, math.min(SAY_LINES, #lines) do
        if channel then
            if GuildOS.Compat.SendChatMessage(lines[i], channel) ~= false then said = said + 1 end
        else
            GuildOS:Print(lines[i])
            said = said + 1
        end
    end
    if said == 0 then return nil, L["The chat did not take the message."] end
    self._said[kind] = now
    return said
end

--- The parties as chat lines: "G1: A, B, C · G2: …".
function RaidTools.GroupLines(parties)
    local parts = {}
    for g, list in ipairs(parties) do
        if #list > 0 then
            local names = {}
            for i, p in ipairs(list) do names[i] = shortName(p.name) end
            parts[#parts + 1] = string.format(L["G%d: %s"], g, table.concat(names, ", "))
        end
    end
    return RaidTools.Lines("", parts, " / ")
end

--- Who is missing as chat lines: the roles short and the names signed up and not here.
function RaidTools.MissingLines(gaps, missing)
    local parts = {}
    for _, g in ipairs(gaps) do
        if g.short > 0 then parts[#parts + 1] = string.format(L["%d %s short"], g.short, RaidTools.RoleWord(g.role, g.short)) end
    end
    if #missing > 0 then
        local names = {}
        for i, p in ipairs(missing) do names[i] = shortName(p.name) end
        parts[#parts + 1] = string.format(L["not here yet: %s"], table.concat(names, ", "))
    end
    if #parts == 0 then return {} end
    return RaidTools.Lines(L["Raid: "], parts)
end

function RaidTools.RoleWord(role, n)
    if role == "TANK" then return n == 1 and L["tank"] or L["tanks"] end
    if role == "HEALER" then return n == 1 and L["healer"] or L["healers"] end
    return L["dps"]
end

----------------------------------------------------------------------
-- Readiness: each person's checks
----------------------------------------------------------------------

--- One row a person: { name, key, class, status, cons (missing count or nil), ench (missing count, nil
--- without gear data), attuned (true/false/nil), resist (value or nil), resistOk, addon (true/false) } and the
--- raid's resistance school (nil when its fights ask for none). From Modules/Readiness.lua's report, the
--- resistance scan and who has synced the addon.
function RaidTools:ReadyRows(people, instKey)
    local def = instKey and self:Instance(instKey)
    local R = GuildOS.Readiness
    local report = {}
    if R and R.GetReport then
        for _, r in ipairs(R:GetReport(def and def.attune or nil)) do report[r.key] = r end
    end
    local school
    local Res = GuildOS.Resistances
    if def and def.resist and Res then
        for _, sc in ipairs(Res.SCHOOLS) do if sc.key == def.resist then school = sc end end
    end
    local members = GuildOS.db and GuildOS.db.members or {}
    local rows = {}
    for _, p in ipairs(people) do
        if p.status ~= "standby" and p.status ~= "pending" and p.status ~= "tentative" then
            local r = report[p.key]
            local m = members[p.key]
            local row = { name = p.name, key = p.key, class = p.class, inGroup = p.inGroup }
            row.addon = (m and (tonumber(m.lastUpdate) or 0) > 0) and true or false
            if r then
                row.cons = r.missCons
                row.ench = r.hasGear and r.missEnch or nil
                row.attuned = r.targetOk
                row.ilvl = (r.ilvl or 0) > 0 and r.ilvl or nil
            end
            if school and m and type(m.resistances) == "table" then
                row.resist = tonumber(m.resistances[school.key]) or 0
                row.resistOk = row.resist >= school.target
            end
            row.status = self.ReadyStatus(row, school ~= nil)
            rows[#rows + 1] = row
        end
    end
    local RANK = { notready = 0, warn = 1, nodata = 2, ready = 3 }
    table.sort(rows, function(a, b)
        if a.status ~= b.status then return (RANK[a.status] or 9) < (RANK[b.status] or 9) end
        return (a.name or "") < (b.name or "")
    end)
    return rows, school
end

--- A row's verdict: "notready" (not attuned), "warn" (a consumable or an enchant missing, the fight's
--- resistance short), "nodata" (no addon and nothing synced), "ready". Pure.
function RaidTools.ReadyStatus(row, needsResist)
    if row.attuned == false then return "notready" end
    if (row.cons or 0) > 0 or (row.ench or 0) > 0 or (needsResist and row.resist ~= nil and not row.resistOk) then return "warn" end
    if not row.addon and row.ench == nil and row.cons == nil then return "nodata" end
    return "ready"
end

--- Counts of each verdict. Pure.
function RaidTools.ReadySummary(rows)
    local c = { ready = 0, warn = 0, notready = 0, nodata = 0, total = #rows }
    for _, r in ipairs(rows) do c[r.status] = (c[r.status] or 0) + 1 end
    return c
end

--- What is missing, as chat lines: consumables, enchants, attunement, no addon. Pure.
function RaidTools.ReadyLines(rows)
    local cons, ench, att, addon = {}, {}, {}, {}
    for _, r in ipairs(rows) do
        local n = shortName(r.name)
        if (r.cons or 0) > 0 then cons[#cons + 1] = n end
        if (r.ench or 0) > 0 then ench[#ench + 1] = n end
        if r.attuned == false then att[#att + 1] = n end
        if not r.addon then addon[#addon + 1] = n end
    end
    local parts = {}
    if #cons > 0 then parts[#parts + 1] = string.format(L["consumables: %s"], table.concat(cons, ", ")) end
    if #ench > 0 then parts[#parts + 1] = string.format(L["enchants: %s"], table.concat(ench, ", ")) end
    if #att > 0 then parts[#parts + 1] = string.format(L["not attuned: %s"], table.concat(att, ", ")) end
    if #addon > 0 then parts[#parts + 1] = string.format(L["no GuildOS: %s"], table.concat(addon, ", ")) end
    if #parts == 0 then return {} end
    return RaidTools.Lines(L["Missing: "], parts)
end

function RaidTools:ReadyCheck()
    local Compat = GuildOS.Compat
    if not (IsInGroup and IsInGroup()) then return false, L["You are not in a group."] end
    if not Compat.IsLeaderOrAssist() then return false, L["Only the raid leader or an assistant can do this."] end
    if not Compat.CanReadyCheck() then return false, L["Not available on this client."] end
    return Compat.DoReadyCheck()
end

function RaidTools:RoleCheck()
    local Compat = GuildOS.Compat
    if not (IsInGroup and IsInGroup()) then return false, L["You are not in a group."] end
    if not Compat.IsLeaderOrAssist() then return false, L["Only the raid leader or an assistant can do this."] end
    if not Compat.CanRolePoll() then return false, L["Not available on this client."] end
    return Compat.DoRolePoll()
end

----------------------------------------------------------------------
-- The fight: who does what on each boss, saved per raid; the pull timer; the marks
----------------------------------------------------------------------
RaidTools.MARKS = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local MARK_INDEX = {}
for i, m in ipairs(RaidTools.MARKS) do MARK_INDEX[m] = i end
RaidTools.MARK_INDEX = MARK_INDEX
-- The rows a boss starts with when neither the raid leader nor the site wrote any.
RaidTools.DEFAULT_TASKS = { L["Main tank"], L["Off tank"], L["Tank healer"], L["Interrupt"] }
local TASKS_MAX = 12
local TASK_MAX = 60

--- The site's plan for `boss` (Modules/RaidPlan.lua: the roster's GOSROST1 plan), as assignment rows.
function RaidTools:PlanRows(boss, roster)
    local plan = roster and roster.plan
    if not plan then
        local P = GuildOS.RaidPlan
        plan = P and P.Current and P:Current()
    end
    local rows = {}
    if not plan then return rows end
    local P = GuildOS.RaidPlan
    for _, a in ipairs(plan.assignments or {}) do
        if a.boss == boss and #rows < TASKS_MAX then
            local kind = (P and P.KINDS and P.KINDS[a.kind]) or (a.kind ~= "other" and a.kind) or nil
            local task = kind or ""
            if a.note and a.note ~= "" then task = task ~= "" and (task .. ": " .. a.note) or a.note end
            local mark = a.target and MARK_INDEX[a.target:lower()] and a.target:lower() or nil
            rows[#rows + 1] = { task = task:sub(1, TASK_MAX), who = a.name, mark = mark }
        end
    end
    return rows
end

--- The bosses of a raid: the list's, then any the site's plan names that the list does not.
function RaidTools:Bosses(instKey, roster)
    local out, seen = {}, {}
    local def = instKey and self:Instance(instKey)
    for _, b in ipairs(def and def.bosses or {}) do seen[b:lower()] = true; out[#out + 1] = b end
    local plan = roster and roster.plan
    if not plan and GuildOS.RaidPlan and GuildOS.RaidPlan.Current then plan = GuildOS.RaidPlan:Current() end
    for _, list in ipairs({ plan and plan.notes or {}, plan and plan.assignments or {} }) do
        for _, n in ipairs(list) do
            if type(n.boss) == "string" and not seen[n.boss:lower()] then seen[n.boss:lower()] = true; out[#out + 1] = n.boss end
        end
    end
    return out
end

-- The plan's own spelling of `boss`, whatever the capitals.
local function planBoss(boss, roster)
    local plan = roster and roster.plan
    if not plan and GuildOS.RaidPlan and GuildOS.RaidPlan.Current then plan = GuildOS.RaidPlan:Current() end
    for _, a in ipairs(plan and plan.assignments or {}) do
        if type(a.boss) == "string" and a.boss:lower() == boss:lower() then return a.boss end
    end
    return boss
end

--- The rows of `boss` in raid `instKey`: what the raid leader saved, else the site's plan (from = "plan"),
--- else the default tasks with nobody (from = "default"). Copies: edit and Save them.
function RaidTools:Assignments(instKey, boss, roster)
    local saved = instKey and boss and self:Store().assign[instKey]
    saved = saved and saved[boss]
    local rows, from = {}, "saved"
    if type(saved) == "table" then
        for i, r in ipairs(saved) do rows[i] = { task = r.task, who = r.who, mark = r.mark } end
        return rows, from
    end
    rows = boss and self:PlanRows(planBoss(boss, roster), roster) or {}
    if #rows > 0 then return rows, "plan" end
    for i, t in ipairs(self.DEFAULT_TASKS) do rows[i] = { task = t } end
    return rows, "default"
end

--- Saves `rows` for `boss` of raid `instKey`: each { task, who, mark }, rows with neither task nor person
--- dropped, texts cut, at most twelve. Nil rows forget the boss (back to the plan or the defaults).
function RaidTools:SaveAssignments(instKey, boss, rows)
    if not instKey or not boss then return false end
    local a = self:Store().assign
    a[instKey] = type(a[instKey]) == "table" and a[instKey] or {}
    if rows == nil then a[instKey][boss] = nil; return true end
    local out = {}
    for _, r in ipairs(rows) do
        local task = type(r.task) == "string" and strtrim(r.task):sub(1, TASK_MAX) or ""
        local who = type(r.who) == "string" and r.who ~= "" and r.who:sub(1, 64) or nil
        local mark = MARK_INDEX[r.mark or ""] and r.mark or nil
        if (task ~= "" or who) and #out < TASKS_MAX then out[#out + 1] = { task = task, who = who, mark = mark } end
    end
    a[instKey][boss] = out
    return true
end

--- A boss's assignments as chat lines: "Boss: Main tank Brakk {skull} · Interrupt Kaelis …". Pure.
function RaidTools.AssignmentLines(boss, rows)
    local parts = {}
    for _, r in ipairs(rows) do
        if r.who and r.who ~= "" then
            local s = (r.task and r.task ~= "") and (r.task .. " " .. shortName(r.who)) or shortName(r.who)
            if r.mark and MARK_INDEX[r.mark] then s = s .. " {" .. r.mark .. "}" end
            parts[#parts + 1] = s
        end
    end
    if #parts == 0 then return {} end
    return RaidTools.Lines(boss .. ": ", parts)
end

--- The pull timer: the game's countdown where the client has one, else "Pull in N" said as a raid warning.
function RaidTools:Pull(seconds)
    seconds = math.max(3, math.min(60, tonumber(seconds) or 10))
    local Compat = GuildOS.Compat
    if not (IsInGroup and IsInGroup()) then return false, L["You are not in a group."] end
    if not Compat.IsLeaderOrAssist() then return false, L["Only the raid leader or an assistant can do this."] end
    if Compat.CanCountdown() and Compat.DoCountdown(seconds) then return true end
    local channel = (IsInRaid and IsInRaid()) and "RAID_WARNING" or "PARTY"
    Compat.SendChatMessage(string.format(L["Pull in %d"], seconds), channel)
    if not Compat.NeedsClick() then
        Compat.After(seconds, function() Compat.SendChatMessage(L["Pull!"], channel) end)
    end
    return true
end

--- A mark on my target (0 clears it).
function RaidTools:MarkTarget(index)
    if not (UnitExists and UnitExists("target")) then return false, L["Target something first."] end
    return GuildOS.Compat.SetRaidTarget("target", tonumber(index) or 0)
end
