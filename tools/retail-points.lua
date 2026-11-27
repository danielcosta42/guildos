-- Points and the guild's loot system on retail (issue #185), run against the real Core, Compat, Utils,
-- SyncService, Points, ExportImport, the slash router and the feature registry, under a stubbed retail
-- client on Tol Barad and a stubbed WoW: Forever one.
--
-- Retail has no Master Loot, but a guild still keeps points: boss-kill EP, manual awards, decay,
-- standings and their export load there as on Forever, every guildmate keyed and named by their own
-- realm. Charging for an item happens when an award by trade is recorded (tools/retail-loot-council.lua),
-- never from Master Loot. The guild's loot system decides who may award an offered item, so on retail
-- an officer's choice reaches every member (`guildcfg`/`lootsys`, newest stamp wins), and since audit R1
-- Forever's too. TMB is no more (audit R8, B16): it was the wishlist, and reads as it.
--
--   luajit -e 'ADDON="."' tools/retail-points.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

local NOW = 1791000000
local printed, published = {}, {}
local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end })
-- The guild, across connected realms, as retail's roster writes it; rank 1 is an officer.
local ROSTER = { { "Chehul-TolBarad", 1 }, { "Ana-TolBarad", 4 }, { "Ana-Gallywix", 1 }, { "Bob-TolBarad", 4 } }
-- My group: me, Ana from Gallywix, and Bob from my realm with the realm spelled with a space.
local GROUP = { { "Chehul" }, { "Ana", "Gallywix" }, { "Bob", "Tol Barad" } }
local leader, officer = true, true

local function load(retail)
  printed, published = {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function issecretvalue(v) return rawequal(v, SECRET) end
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  function GetTime() return 0 end
  time = function() return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function wipe(t) for k in pairs(t) do t[k] = nil end return t end
  function IsInGuild() return true end
  function GetGuildInfo() return "Jardim Escola", "Officer", officer and 1 or 4, "Azralon" end
  function GetRealmName() return retail and "Tol Barad" or "Classic Beta PvE" end
  function GetNormalizedRealmName() return retail and "TolBarad" or "ClassicBetaPvE" end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1], "Rank", r[2] end
  end
  function IsInRaid() return true end
  function GetNumGroupMembers() return #GROUP end
  function UnitExists(unit) return GROUP[tonumber(unit:match("%d+") or "")] ~= nil end
  function UnitIsUnit(a, b) return a == b or (b == "player" and a == "raid1") end
  function UnitIsGroupLeader() return leader end
  function UnitName(unit)
    local g = unit == "player" and GROUP[1] or GROUP[tonumber(unit:match("%d+") or "")]
    if g then return g[1], g[2] end
  end
  function UnitClass() return "Mage", "MAGE" end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.db = { settings = { modules = {} }, members = {}, sync = { rev = {} } }
  dofile(ADDON .. "/Modules/SyncService.lua")
  GuildOS.SyncService:Initialize()
  GuildOS.SyncService.Publish = function(_, dom, act, data, opts)
    published[#published + 1] = { dom = dom, act = act, data = data, rev = opts and opts.rev }
    return "id"
  end
  dofile(ADDON .. "/Modules/Points.lua")
end

local function said(text) return table.concat(printed, "\n"):find(text, 1, true) ~= nil end
local function last(dom, act)
  for i = #published, 1, -1 do
    if published[i].dom == dom and published[i].act == act then return published[i] end
  end
end

-- ── 1. Retail: points are here ────────────────────────────────────────
load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
local P = GuildOS.Points
check(P ~= nil, "Points loads on retail (issue #185)")
check(GuildOS:StartModule({ "Points", feature = "points", ui = "dkp" }), "and starts")
check(P:GetMode() == "dkp" and P:Get("Ana-Gallywix") == 0, "a new guild starts in DKP mode at zero")

-- ── 2. Every guildmate keyed and named by their own realm ─────────────
local e = P:Award("Ana-Gallywix", 30, "Bench")
check(e and e.key == "Ana-Gallywix" and e.name == "Ana-Gallywix", "an award names the whole key on retail")
P:Award("Ana-TolBarad", 10, "Bench")
check(P:Get("Ana-Gallywix") == 30 and P:Get("Ana-TolBarad") == 10, "two namesakes on connected realms are two standings")
local delta = last("points", "delta")
check(delta and delta.data.entries[1].key == "Ana-TolBarad", "each award goes out as a delta")
P:Charge("Ana-Gallywix", 12, "Voidforged Helm")
check(P:Get("Ana-Gallywix") == 18, "a charge takes points away")
local names = {}
for _, s in ipairs(P:GetStandings()) do names[s.name] = s.current end
check(names["Ana-Gallywix"] == 18 and names["Ana-TolBarad"] == 10 and names.Ana == nil,
  "the standings list them apart, by their whole name")

-- The raid award reads each unit's realm; a realm with a space is normalized, as the roster writes it.
check(P:AwardRaidGroup(5, "On time") == 3, "the whole raid is awarded")
check(P:Get("Chehul-TolBarad") == 5 and P:Get("Ana-Gallywix") == 23 and P:Get("Bob-TolBarad") == 5,
  "each raider by their own realm")

-- Boss-kill EP: a boss whose name the client keeps secret is never the reason.
P:GetDB().config.autoAward = true
P:GetDB().config.bossAward = 7
check(pcall(P.OnBossKill, P, nil), "a kill with no readable boss name does not raise")
check(P:Get("Bob-TolBarad") == 12 and P:GetLog(1)[1].reason == "Boss kill", "and awards the raid as a boss kill")
leader = false
P:OnBossKill("Imperator Averzian")
check(P:Get("Bob-TolBarad") == 12, "only the raid leader's client awards a kill")
leader = true

-- A name typed in the points window: with its realm on retail, else this realm's.
check(P:KeyOf("Ana-Gallywix") == "Ana-Gallywix" and P:KeyOf("Bob") == "Bob-TolBarad"
  and P:KeyOf("Bob-Tol Barad") == "Bob-TolBarad", "a typed name is keyed by its own realm on retail")

-- Decay.
check(P:ApplyDecay(50) == 4 and P:Get("Ana-Gallywix") == 15, "decay takes its share of everyone")

-- ── 3. The standings export and the verbs ─────────────────────────────
dofile(ADDON .. "/Modules/ExportImport.lua")
local Ex = GuildOS.Exporter
check(Ex:Has("standings"), "the DKP export is on retail")
check((Ex:Build("standings", "csv") or ""):find("Ana-Gallywix", 1, true), "and lists the standings")
dofile(ADDON .. "/Core/Commands.lua")
local opened = 0
GuildOS.ShowPointsFrame = function() opened = opened + 1 end
GuildOS.ShowExportPopup = function() end
local NOT_HERE = "Not available on this client."
for _, verb in ipairs({ "points", "dkp" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb) and not said(NOT_HERE), "/gos " .. verb .. " answers on retail")
end
check(opened == 2, "and opens the points window")
printed = {}
check(pcall(SlashCmdList.GUILDOS, "export standings") and not said(NOT_HERE), "/gos export standings exports on retail")
for _, verb in ipairs({ "lm", "lootmaster", "softres" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb) and said(NOT_HERE), "/gos " .. verb .. " is still not on retail")
end
printed = {}
SlashCmdList.GUILDOS("help")
check(said("/gos points") and not said("/gos lm"), "the help lists points, not the loot master")

-- ── 4. The tab and the Settings toggles ───────────────────────────────
GuildOS.UI = {}
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Features.lua")
local UI = GuildOS.UI
check(not UI:IsFeatureAbsent(UI:GetFeature("dkp")), "the DKP tab is on retail")
check(UI:IsFeatureAbsent(UI:GetFeature("lootMaster")), "the loot master still is not")

-- ── 5. The loot systems retail offers ─────────────────────────────────
local offered = {}
for _, sys in ipairs(GuildOS:LootSystemsHere()) do offered[sys.key] = GuildOS:LootSystemLabel(sys) end
check(offered.rolls and offered.wishlist and offered.dkp and offered.external, "retail offers the four it can run")
check(offered.tmb == nil, "TMB, Classic only, is not offered on retail")
check(offered.rolls == "Free roll", "the roll is the free roll on retail: the holder awards")

-- ── 6. The guild's loot system reaches every member ───────────────────
published = {}
check(GuildOS:GetLootSystem() == "rolls", "a new guild rolls")
GuildOS:SetLootSystem("dkp")
local sent = last("guildcfg", "lootsys")
check(GuildOS:GetLootSystem() == "dkp" and sent and sent.data.sys == "dkp" and sent.rev == NOW,
  "an officer's choice goes out to the guild, stamped")
NOW = NOW + 1
GuildOS:SetLootSystem("wishlist")
check(last("guildcfg", "lootsys").rev == NOW, "a later choice carries a later stamp")
-- A member's client.
local handler = GuildOS.SyncService.handlers.guildcfg
GuildOS.db.settings = { modules = {} }
handler({ dom = "guildcfg", act = "lootsys", rev = NOW - 1, data = { sys = "dkp" } })
check(GuildOS:GetLootSystem() == "dkp", "a member takes the guild's loot system")
handler({ dom = "guildcfg", act = "lootsys", rev = NOW - 5, data = { sys = "external" } })
check(GuildOS:GetLootSystem() == "dkp", "an older one does not replace it")
handler({ dom = "guildcfg", act = "lootsys", rev = NOW, data = { sys = "plus1" } })
handler({ dom = "guildcfg", act = "lootsys", rev = NOW, data = { sys = "nonsense" } })
handler({ dom = "guildcfg", act = "lootsys", rev = NOW, data = { sys = SECRET } })
check(GuildOS:GetLootSystem() == "dkp", "one retail does not run, or none at all, is turned away")
handler({ dom = "guildcfg", act = "lootsys", rev = NOW, data = { sys = "wishlist" } })
check(GuildOS:GetLootSystem() == "wishlist", "the newest is taken")
handler({ dom = "guildcfg", act = "officers", rev = NOW, data = { max = 2 } })
check(GuildOS.db.settings.officerMaxRank == 2 and GuildOS:GetLootSystem() == "wishlist",
  "the officer threshold still travels on the same domain, apart")
-- The officer re-sends it with the threshold, for a client that missed the change.
published = {}
GuildOS.db.settings.lootSystemAt = NOW
GuildOS:PublishLootSystem()
check(last("guildcfg", "lootsys") ~= nil, "an officer re-publishes the loot system")
officer = false
published = {}
GuildOS:PublishLootSystem()
GuildOS:SetLootSystem("external")
check(#published == 0, "a member publishes nothing")
officer = true

-- ── 7. Forever: as before ─────────────────────────────────────────────
NOW = 1791000000
load(false)
check(not GuildOS.Client.isRetail and GuildOS.Points ~= nil, "Forever has points, as before")
GuildOS.Points:Initialize()
check(GuildOS.Points:Award("Ana", 5, "x").name == "Ana", "and names a member as before")
check(GuildOS.Points:KeyOf("Ana") == GuildOS:GetPlayerKey("Ana", GetRealmName()), "and keys a typed name as before")
offered = {}
for _, sys in ipairs(GuildOS:LootSystemsHere()) do offered[sys.key] = GuildOS:LootSystemLabel(sys) end
check(offered.tmb == nil and offered.wishlist and offered.plus1 and offered.rolls == "/roll (MS/OS)",
  "Forever offers every loot system, TMB no longer among them (audit R8, B16: it was the wishlist)")
-- Audit R1: the officer's choice reaches every client, not only retail's.
published = {}
GuildOS:SetLootSystem("dkp")
local fsent = last("guildcfg", "lootsys")
check(GuildOS:GetLootSystem() == "dkp" and fsent and fsent.data.sys == "dkp", "Forever's officer publishes the choice too")
GuildOS.db.settings = { modules = {}, lootSystem = "rolls" }
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 10, data = { sys = "external" } })
check(GuildOS:GetLootSystem() == "external", "and a Forever member takes the guild's (a raider set to external)")
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 5, data = { sys = "dkp" } })
check(GuildOS:GetLootSystem() == "external", "the newest stamp still wins on Forever")
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 11, data = { sys = "plus1" } })
check(GuildOS:GetLootSystem() == "plus1", "a Classic-only system is taken where the client offers it")
-- Audit R8, B16: "tmb" from an officer's client before, or saved, reads as the wishlist.
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 12, data = { sys = "tmb" } })
check(GuildOS.db.settings.lootSystem == "wishlist" and GuildOS:GetLootSystem() == "wishlist", "an old officer's TMB is taken as the wishlist")
GuildOS.db.settings.lootSystem = "tmb"
check(GuildOS:GetLootSystem() == "wishlist" and GuildOS:LootSystemShowsWishlist() == (GuildOS.Wishlist ~= nil),
  "a guild saved with TMB reads as the wishlist")

-- Audit R1 migration: a guild that chose its system before the stamp existed publishes it, with the lowest stamp.
GuildOS.db.settings = { modules = {}, lootSystem = "dkp" }
published = {}
GuildOS:PublishLootSystem()
local mig = last("guildcfg", "lootsys")
check(GuildOS.db.settings.lootSystemAt == 1 and mig and mig.rev == 1 and mig.data.sys == "dkp",
  "R1: an officer's unstamped system gets stamp 1 and goes out")
GuildOS.db.settings = { modules = {} }
published = {}
GuildOS:PublishLootSystem()
check(#published == 0 and GuildOS.db.settings.lootSystemAt == nil, "R1: no system chosen, nothing to migrate")
GuildOS.db.settings = { modules = {}, lootSystem = "rolls", lootSystemAt = NOW, lootRule = { v = 1 } }
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = 1, data = { sys = "dkp" } })
check(GuildOS:GetLootSystem() == "rolls", "R1: any real stamp beats a migrated one")
GuildOS.db.settings = { modules = {}, lootRule = { v = 1 } }
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = 1, data = { sys = "dkp" } })
check(GuildOS.db.settings.lootSystem == "dkp" and GuildOS.db.settings.lootRule ~= nil,
  "R1: a client with none takes the migrated one, and it drops no rule")

-- Audit L7: the guild's own rule travels on Forever too, over GUILD (guildcfg, never the OFFICER channel), and a
-- newer loot system than a client's own old rule replaces it.
dofile(ADDON .. "/Modules/LootRule.lua")
local LR = GuildOS.LootRule
check(not GuildOS.SyncService.OFFICER_CHANNEL_DOMAINS.guildcfg, "guildcfg goes over GUILD, which Forever has")
published = {}
local rule = { v = 1, model = "plus1", order = { { k = "response" }, { k = "roll" } } }
check(LR:Set(rule) and last("guildcfg", "lootrule") and last("guildcfg", "lootrule").data.rule == rule,
  "Forever's officer publishes the guild's rule")
GuildOS.db.settings = { modules = {}, lootSystem = "rolls" }
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootrule", rev = NOW + 20, data = { rule = rule } })
check(GuildOS.db.settings.lootRule and GuildOS.db.settings.lootRule.model == "plus1" and LR:For("").model == "plus1",
  "and a Forever member takes it")
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 15, data = { sys = "dkp" } })
check(LR:For("").model == "plus1", "a loot system older than the rule leaves the rule")
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootsys", rev = NOW + 30, data = { sys = "dkp" } })
check(GuildOS.db.settings.lootRule == nil and LR:For("").model == "dkp", "a newer one clears the older rule: the guild reads DKP")
GuildOS.SyncService.handlers.guildcfg({ dom = "guildcfg", act = "lootrule", rev = NOW + 20, data = { rule = rule } })
check(GuildOS.db.settings.lootRule == nil, "and the old rule re-sent is turned away")

print(("retail-points: %d checks passed"):format(checks))
