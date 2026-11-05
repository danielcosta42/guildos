-- The guild finder a character with no guild opens (specs/071-o-recrutamento in guildos-web, Task B1),
-- run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/RecruitBeacon.lua
-- and Modules/GuildFinder.lua.
--
-- The rules: a wrong faction or world drops out, every filter cuts what it should, the order is the
-- site's, a retail guild must be on a realm that can invite me, raid nights are read on the player's
-- clock (a night across midnight, a reader east of UTC), zero and one ad do not break anything, an
-- old CR2 ad still shows (heard, never verified), and nothing off the network can open a colour
-- code, run onto a second line or be cut in the middle of a character.
--
--   luajit -e 'ADDON="."' tools/guild-finder.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = {}
RAID_CLASS_COLORS = {}

-- Any method does nothing, except what the screen reads back: its text, whether it is shown, and the
-- scripts it sets, so a test can press the real button.
local textures = {}
local function widget(extra)
  local w = extra or {}
  w.scripts = {}
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "GetText" then return function(self) return self.text or "" end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if k == "IsShown" then return function(self) return self.shown == true end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    if k == "CreateTexture" then return function() local t = widget(); textures[#textures + 1] = t; return t end end
    if k == "GetWidth" then return function() return 300 end end
    return function() end
  end })
end
function CreateFrame() return widget() end
function GetBuildInfo() return "1.60.1", "70245", "", 11500 end
WOW_PROJECT_ID = 99
function GetRealmName() return "Realm" end
function UnitName() return "Ana" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitFactionGroup() return "Horde" end
function GetLocale() return "ptBR" end
function GetCurrentRegion() return 1 end
local NOW = 1790000000
function GetServerTime() return NOW end
time, date = os.time, os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
C_Timer = { After = function() end, NewTicker = function() end }
function GetNumGuildMembers() return 0 end
-- strsplit keeps the empty fields, which is the whole point of a '|' protocol.
function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local at = s:find(delim, from, true)
    if not at then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
  return unpack(out)
end
local guilded = false
function IsInGuild() return guilded end
function GetGuildInfo() return nil end
-- hooksecurefunc as the client does it: the original runs, then the hook.
function hooksecurefunc(tbl, name, hook)
  local orig = tbl[name]
  tbl[name] = function(...) local r = orig(...); hook(...); return r end
end
GuildOSDB = {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildFinder.lua")
dofile(ADDON .. "/Modules/RecruitBeacon.lua")
GuildOS.db = {}

local GF, RB = GuildOS.GuildFinder, GuildOS.RecruitBeacon
check(GF and GF.Ads and GF.Matches and GF.Rank and GF.LocalTimes and GF.Available, "the module has the interface B2 to B4 rely on")

local errors = {}
GuildOS.RecordError = function(_, msg) errors[#errors + 1] = msg end

-- Ads straight in the normalized shape, so a rule is tested without the wire in the way.
local function ad(over)
  local a = { n = "Guild", f = "H", w = "normal:us", v = 1000, x = NOW + 3600, heard = false, verified = true }
  for k, v in pairs(over or {}) do a[k] = v end
  return a
end
local function names(list)
  local out = {}
  for i, a in ipairs(list) do out[i] = a.n end
  return table.concat(out, ",")
end
local function only(ads)
  GF.sources = {}
  GF:AddSource("test", function() return ads end)
end

-- ── An old CR2 ad still shows ───────────────────────────────────────────
RB:Initialize()
RB:Ingest("CR2|Ordem do Crepusculo|H|HEALER+PALADIN|Ter e Qui|Raide duas noites|ptBR+enUS+itIT|RAID+SOCIAL+CASUAL|"
  .. (NOW - 100) .. "|" .. (NOW + 86400) .. "|Ana-Realm", "Bruno")
local old = GF:All()
check(#old == 1, "the CR2 ad in RecruitBeacon's cache is a finder ad")
local o = old[1]
check(o.n == "Ordem do Crepusculo" and o.f == "H", "name and faction")
check(o.heard == true and o.verified == false, "a CR2 ad is heard and never verified")
check(table.concat(o.r, "+") == "HEALER" and table.concat(o.c, "+") == "PALADIN", "roles and classes are told apart")
check(table.concat(o.l, "+") == "pt+en", "languages land on the site's codes, and Italian is left out")
check(table.concat(o.fo, "+") == "RAID+SOCIAL" and o.pc == "casual", "CASUAL was a focus and is a pace now")
check(o.dt == "Ter e Qui" and o.p == "Raide duas noites" and o.ct[1] == "Ana-Realm", "the free days, the note and the contact survive")
check(o.w == nil and o.d == nil and o.s == nil, "an old ad has no world and no nights")
check(GF:Schedule(o, 0) == "Ter e Qui", "the card falls back to the free-text days")
check(#GF:Ads({}) == 1, "and it passes with no filter")
check(#GF:Ads({ locale = "pt", faction = "H", region = "us", class = "PALADIN" }) == 1, "an ad with no world fits any world")
check(#GF:Ads({ faction = "A" }) == 0, "but its faction still counts")

-- ── Sources, one ad per guild ───────────────────────────────────────────
only({ ad({ n = "Same", v = 10, p = "old" }), ad({ n = "same", v = 20, p = "new" }) })
check(#GF:All() == 1 and GF:All()[1].p == "new", "the newer version of a guild wins")
only({ ad({ n = "Tie", v = 10, verified = false, heard = true }), ad({ n = "Tie", v = 10, verified = true }) })
check(GF:All()[1].verified == true, "at the same version the verified one wins")
-- The same name on two worlds is two guilds: a newer ad from elsewhere must not shadow the one I can join.
only({ ad({ n = "Twin", w = "normal:us", v = 10, p = "mine" }), ad({ n = "Twin", w = "normal:eu", v = 99, p = "theirs" }) })
check(#GF:All() == 2, "one name on two worlds is two ads")
check(names(GF:Ads({ region = "us" })) == "Twin" and GF:Ads({ region = "us" })[1].p == "mine", "and the one on my world survives the filter")
only({ ad({ n = "Slugged", u = "slug-a", v = 1 }), ad({ n = "Renamed", u = "slug-a", v = 2 }), ad({ n = "Other", u = "slug-b" }) })
check(names(GF:All()) == "Other,Renamed","a slug names one guild, whatever it is called now")
only({ ad({ n = "Old", x = NOW - 1 }), ad({ n = "Fresh" }) })
check(names(GF:All()) == "Fresh", "an expired ad is gone")
GF:AddSource("second", function() return { ad({ n = "Other" }) } end)
check(#GF:All() == 2, "a second source adds to the first without anything else changing")
GF:AddSource("boom", function() error("bad source") end)
check(#GF:All() == 2 and #errors == 1, "a source that fails is recorded and the others still show")

-- ── Faction and world ───────────────────────────────────────────────────
only({ ad({ n = "Horde" }), ad({ n = "Ally", f = "A" }), ad({ n = "Unknown", f = false }) })
check(names(GF:Ads({ faction = "H" })) == "Horde,Unknown", "the other faction drops out; an unknown one stays")
check(names(GF:Ads({ faction = "A" })) == "Ally,Unknown", "and the other way")

only({ ad({ n = "Us" }), ad({ n = "Eu", w = "normal:eu" }), ad({ n = "Pvp", w = "pvp:us" }) })
check(names(GF:Ads({ region = "us" })) == "Pvp,Us", "another region's guild drops out")
check(names(GF:Ads({ region = "us", world = "pvp:us" })) == "Pvp", "the World filter picks one ruleset")
check(names(GF:Ads({ region = "eu" })) == "Eu", "the region is the client's")
check(table.concat(GF:Worlds({ region = "us" }), ",") == "normal:us,pvp:us", "the World menu offers the rulesets that exist in my region")

-- retail: only realms that can invite me
GuildOS.Client.isRetail = true
function GetAutoCompleteRealms() return { "Tol Barad", "Draenor" } end
only({ ad({ n = "Mine", w = "Realm:us" }), ad({ n = "Linked", w = "TolBarad:us" }),
       ad({ n = "Spaced", w = "Draenor:us" }), ad({ n = "Far", w = "Stormrage:us" }) })
local ctx = GF:Context()
check(ctx.realms and ctx.realms["realm"] and ctx.realms["tolbarad"] and not ctx.realms["stormrage"], "retail reads my realm and the connected ones")
check(names(GF:Ads({ realms = ctx.realms })) == "Linked,Mine,Spaced", "a guild on a realm that cannot invite me is left out")
GuildOS.Client.isRetail = false
check(GF:Context().realms == nil, "Forever has no realms to check")

-- ── Every filter cuts ───────────────────────────────────────────────────
only({
  ad({ n = "A", l = { "pt" }, c = { "PALADIN" }, pc = "regular", fo = { "RAID" }, lo = "council", t = "week2" }),
  ad({ n = "B", l = { "en" }, c = { "MAGE" }, pc = "casual", fo = { "SOCIAL", "RP" }, lo = "dkp", t = "none" }),
  ad({ n = "C" }),
})
check(names(GF:Ads({ locale = "pt" })) == "A,C", "language: the guild that says another one drops out, one that says nothing stays")
check(names(GF:Ads({ class = "PALADIN" })) == "A,C", "wants my class: naming other classes drops out, naming none is anyone")
check(names(GF:Ads({ pace = "casual" })) == "B", "pace: a guild that did not say is out")
check(names(GF:Ads({ focus = "RP" })) == "B", "focus")
check(names(GF:Ads({ loot = "council" })) == "A", "loot")
check(names(GF:Ads({ trial = "none" })) == "B", "trial")
check(names(GF:Ads({ pace = "regular", focus = "RAID", loot = "council" })) == "A", "filters add up")
check(#GF:Ads({ pace = "hardcore" }) == 0, "a filter nobody fits gives an empty list, not an error")

-- ── Order: the site's ───────────────────────────────────────────────────
only({
  ad({ n = "Plain", v = 500, l = { "en" } }),
  ad({ n = "Language", v = 100, l = { "pt" } }),
  ad({ n = "Class", v = 50, l = { "en" }, c = { "PALADIN" } }),
  ad({ n = "Both", v = 10, l = { "pt" }, c = { "PALADIN" } }),
  ad({ n = "Recent", v = 900, l = { "pt" } }),
})
check(names(GF:Rank(GF:All(), { class = "PALADIN", locale = "pt" })) == "Both,Class,Recent,Language,Plain",
  "class first, then the reader's language, then the most recently confirmed")
check(names(GF:Rank(GF:All(), { locale = "pt" })) == "Both,Class,Recent,Language,Plain", "the class defaults to the player's own")
check(names(GF:Rank({}, {})) == "", "ranking nothing is nothing")
check(names(GF:Rank({ ad({ n = "Solo" }) })) == "Solo", "ranking one is one")

-- ── Raid nights on the player's clock ───────────────────────────────────
-- Tuesday 21:00 to Wednesday 03:00 UTC: d = Tuesday, s = 21:00, e = 03:00.
local night = ad({ n = "Night", d = { 2 }, s = 1260, e = 180 })
local function t1(offset) return GF:LocalTimes(night, offset)[1] end
check(t1(0).day == 2 and t1(0).from == 1260 and t1(0).to == 1260 + 360, "UTC reader: Tuesday 21:00, six hours")
check(t1(-180).day == 2 and t1(-180).from == 1080 and t1(-180).to == 1440, "west of UTC (Sao Paulo): Tuesday 18:00, midnight")
check(t1(540).day == 3 and t1(540).from == 360 and t1(540).to == 720, "east of UTC (Tokyo): it is Wednesday morning")
check(GF:Schedule(night, 540) == "Wed \194\183 06:00 to 12:00", "the card says what the clock says")
check(GF:Schedule(ad({ n = "Two", d = { 2, 4 }, s = 1260, e = 0 }), 0) == "Tue and Thu \194\183 21:00 to 00:00", "two nights with one window read like the mock")
check(GF:Schedule(ad({ n = "Three", d = { 1, 3, 5 }, s = 600, e = 720 }), 0) == "Mon, Wed, Fri \194\183 10:00 to 12:00", "three nights are a comma list")
check(GF:Schedule(ad({ n = "Days", d = { 5 } }), 0) == "Fri", "days with no clock time are only days")
check(GF:Schedule(ad({ n = "None" }), 0) == nil, "no nights, nothing to say")

local function touches(a, offset)
  local out = {}
  for _, p in ipairs(GF:Touches(a, offset)) do out[#out + 1] = p.day .. tostring(p.period) end
  table.sort(out)
  return table.concat(out, ",")
end
check(touches(night, 0) == "2night,3late", "a night across midnight counts in both days and both periods")
check(touches(night, -180) == "2night", "the same night at Sao Paulo's clock is an evening")
check(touches(night, 540) == "3morning", "and in Tokyo a morning")
check(touches(night, 60) == "2night,3late", "an hour east still crosses midnight")
check(touches(ad({ n = "Noon", d = { 1 }, s = 720, e = 840 }), 0) == "1afternoon", "noon belongs to the afternoon")
check(touches(ad({ n = "Dawn", d = { 1 }, s = 300, e = 420 }), 0) == "1late,1morning", "05:00 to 07:00 touches late night and morning")
check(touches(ad({ n = "DayOnly", d = { 6 } }), 0) == "6false", "a day with no clock time has no period")

only({ night, ad({ n = "Other", d = { 4 }, s = 600, e = 720 }) })
check(names(GF:Ads({ day = 3 }, 0)) == "Night", "Wednesday finds the night that runs into it")
check(names(GF:Ads({ day = 2, period = "late" }, 0)) == "", "Tuesday late night is not that night")
check(names(GF:Ads({ day = 3, period = "late" }, 0)) == "Night", "Wednesday late night is")
check(names(GF:Ads({ period = "morning" }, 0)) == "Other", "morning finds the 10:00 to 12:00 one")
check(names(GF:Ads({ period = "morning" }, 540)) == "Night", "and for somebody in Tokyo, the other")
only({ ad({ n = "NoNights" }) })
check(#GF:Ads({ day = 1 }, 0) == 0, "a guild that names no night is out of a day filter")
check(#GF:Ads({}, 0) == 1, "and in without one")

local off = GF:UtcOffset()
check(type(off) == "number" and off == math.floor(off) and off >= -840 and off <= 840, "the computer's offset is whole minutes")

-- ── Zero and one ────────────────────────────────────────────────────────
only({})
check(#GF:Ads() == 0 and #GF:All() == 0, "no ads at all is an empty list")
only({ ad({ n = "Only" }) })
check(names(GF:Ads({})) == "Only", "one ad is one ad")

-- ── Text off the network ────────────────────────────────────────────────
local cjk = string.rep("\228\184\173", 300)    -- 300 characters of three bytes
only({ ad({ n = "Bad|cffff0000Name|r", p = "line one\nline two |Hurl:x|h[click]|h " .. cjk, ct = { "A|b", "B", "C", "D" } }) })
local bad = GF:All()[1]
check(not bad.n:find("|", 1, true) and not bad.p:find("|", 1, true) and not bad.p:find("\n", 1, true), "the pitch is inert and one line")
check(#bad.ct == 3 and not bad.ct[1]:find("|", 1, true), "at most three contacts, inert")
local chars = select(2, bad.p:gsub("[^\128-\191]", ""))
check(chars <= 120, "the pitch is cut at 120 characters")
local ok = true
for i = 1, #bad.p do
  local b = bad.p:byte(i)
  if b >= 224 and b < 240 then
    local b2, b3 = bad.p:byte(i + 1), bad.p:byte(i + 2)
    if not (b2 and b3 and b2 >= 128 and b2 < 192 and b3 >= 128 and b3 < 192) then ok = false end
  end
end
check(ok, "no CJK character is cut in the middle")
only({ ad({ n = "Wild", pc = "turbo", lo = "free", t = "x", l = { "klingon", "pt" }, fo = { "RAID", "NOPE" }, d = { 9, 2, 2.5 }, s = 99999, m = { n = -3, a = 150 } }) })
local w = GF:All()[1]
check(w.pc == nil and w.lo == nil and w.t == nil, "a pace, loot or trial outside the vocabulary is absent")
check(#w.l == 1 and w.l[1] == "pt" and #w.fo == 1, "unknown languages and foci are dropped")
check(#w.d == 1 and w.d[1] == 2 and w.s == nil and w.m == nil, "bad days, minutes and numbers are dropped, absent and never zero")
-- classes are this game's own tokens: nothing else reaches the screen
only({ ad({ n = "Klass", c = { "PALADIN", "|cffff0000RED|r", string.rep("X", 500), "NOTACLASS", "WARRIOR" } }) })
local klass = GF:All()[1]
check(table.concat(klass.c, ",") == "PALADIN,WARRIOR", "a class off the network that is not one of this game's tokens is dropped")
only({ ad({ n = "Nothing", c = { "|cffff0000RED|r" } }) })
check(GF:All()[1].c == nil, "and a list of nothing but those is absent")
only({ { n = "" }, { n = 5 }, "string", {} })
check(#GF:All() == 0, "records that are not ads are not ads")

-- ── Saved filters ───────────────────────────────────────────────────────
GuildOSDB = {}
local cur = GF:Current()
check(cur.locale == "pt" and cur.faction == "H" and cur.region == "us" and cur.class == "PALADIN", "by default: my language, my faction, my region, my class")
GF:SetFilter("locale", false)
check(GF:Current().locale == nil, "any language is a saved choice too")
GF:SetFilter("locale", "de"); GF:SetFilter("wantsMe", false); GF:SetFilter("world", "pvp:us"); GF:SetFilter("day", 3)
cur = GF:Current()
check(cur.locale == "de" and cur.class == nil and cur.world == "pvp:us" and cur.day == 3, "the filters are what was saved")
check(GuildOSDB.guildFinder.world == "pvp:us", "and they live in GuildOSDB, for every character on the account")

-- ── Available, and the first guild lights the minimap ───────────────────
check(GF:Available() == true, "available on Forever and retail")
GuildOS.Client.isAnniversary = true
check(GF:Available() == false, "not on Anniversary")
GuildOS.Client.isAnniversary = false

local lit = 0
function GuildOS:GuildFinderHeard() lit = lit + 1 end
GF.sources = {}
GF:AddSource("CR2", GF.HeardAds)
GuildOS.db.recruitRelay = {}
GuildOSDB = {}
GF:Initialize()
guilded = true
RB:Ingest("CR2|Guilded One|H|||x|ptBR||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed", "Zed")
check(lit == 0, "a character in a guild is not looking: nothing lights")
guilded = false
GuildOS.db.recruitRelay = {}
RB:Ingest("CR2|Wrong Side|A|||x|ptBR||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed", "Zed")
check(lit == 0, "an ad of the other faction is not a guild to look at")
RB:Ingest("CR2|English Only|H|||x|enUS||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed", "Zed")
check(lit == 0, "nor one the language filter the finder opens with would hide: the button never promises a guild the screen then hides")
RB:Ingest("CR2|Right Side|H|||x|ptBR||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed", "Zed")
check(lit == 1, "the first guild of the session lights the minimap")
RB:Ingest("CR2|Another|H|||x|ptBR||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed", "Zed")
check(lit == 1, "once")

-- ── The screen, pressed like a player would ────────────────────────────
local texts, buttons, allButtons = {}, {}, {}
local printed, opened, alert = {}, {}, nil
UISpecialFrames = {}
LOCALIZED_CLASS_NAMES_MALE = { PALADIN = "Paladin", WARRIOR = "Warrior" }
function Ambiguate(name) return name end
function ChatFrame_OpenChat(line) opened[#opened + 1] = line end
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
GuildOS.ApplyFont = function() end
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
GuildOS.SetMinimapAlert = function(_, on) alert = on end
local function textMaker()
  return function(_, _, text) local w = widget({ text = text }); texts[#texts + 1] = w; return w end
end
GuildOS.UI = {
  StylePopup = function() end, SetButtonVariant = function() end,
  CreateTitle = textMaker(), CreateText = textMaker(), CreateHeaderText = textMaker(),
  CreateCloseButton = function() return widget() end,
  CreateButton = function(_, _, label)
    local b = widget({ label = widget({ text = label }) })
    function b:SetEnabled(v) self.enabled = v and true or false end
    buttons[label] = b
    allButtons[#allButtons + 1] = b
    return b
  end,
  CreateCheckbox = function()
    local cb = widget()
    function cb:SetChecked(v) self.checked = v end
    return widget({ checkbox = cb })
  end,
}
local function has(str)
  for _, w in ipairs(texts) do if w.text == str then return true end end
  return false
end
local function hasLike(pat)
  for _, w in ipairs(texts) do if w.text and w.text:find(pat) then return true end end
  return false
end
local function press(label, mouse) buttons[label].scripts.OnClick(buttons[label], mouse or "LeftButton") end

local ARROW = " |TInterface\\Buttons\\Arrow-Down-Up:12:12|t"
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t "
function GF:UtcOffset() return 0 end    -- the card's times are read at a known clock
GuildOSDB = {}
GuildOS.db.recruitRelay = {}
GF.sources = {}
GF:AddSource("CR2", GF.HeardAds)
RB:Ingest("CR2|Alpha Guild|H|HEALER+PALADIN+WARRIOR|Seg e Qua|Raide de noite|ptBR|RAID|"
  .. (NOW - 10) .. "|" .. (NOW + 86400) .. "|Ana-Realm", "Ana")
RB:Ingest("CR2|Beta Guild|H|||Chill|enUS||" .. (NOW - 20) .. "|" .. (NOW + 86400) .. "|Bia", "Bia")
dofile(ADDON .. "/UI/GuildFinder.lua")
check(GuildOS.ShowGuildFinder and GuildOS.GuildFinderHeard, "the screen has the entries the plan names")

alert = true
GuildOS:ShowGuildFinder()
local finder = GuildOS.guildFinder
check(finder:IsShown() and alert == false, "opening it puts the minimap out")
check(has("Alpha Guild") and has("1 of 1"), "in Portuguese only the Portuguese guild is on the deck")
check(has("Heard in the game, not verified"), "a CR2 ad is heard, not verified")
check(has("\226\128\156Raide de noite\226\128\157") and has("Seg e Qua"), "the pitch and the nights are on the card")
check(hasLike("Healer, Warrior, Paladin %(you!%)"), "who the guild wants, with my class marked")
check(buttons["Any language"].label.text == "Portuguese" .. ARROW, "the language chip says the language it is on, with the drop-down arrow")
check(has("Not stated \194\183 Raid"), "a heard ad with no pace reads Not stated, then its focus")
check(buttons["Any world"].shown ~= false and buttons["Any focus"].shown == false, "World is in the top row; focus, loot and trial wait behind More filters")
check(buttons["Any trial"].shown == false and buttons["Any loot rule"].shown == false, "and so do loot and trial")
local dotsShown = 0
for _, t in ipairs(textures) do if t.shown then dotsShown = dotsShown + 1 end end
check(dotsShown == 1, "one dot per guild under the card")
check(buttons["Whisper"].shown == true, "a contact can be whispered")
press("Whisper")
check(opened[1] == "/w Ana-Realm ", "and the whisper opens addressed to them")

local asked
GuildOS.ShowJoinForm = function(_, a) asked = a end
press("Ask to join")
check(asked and asked.n == "Alpha Guild", "Ask to join opens the request form for the guild on the card")
GuildOS.ShowJoinForm = nil
check(pcall(press, "Ask to join"), "without the form the button does nothing, quietly")

-- the language chip: right click goes back one, from Portuguese to any
press("Any language", "RightButton")
check(GuildOSDB.guildFinder.locale == false, "a right click on the language chip goes back to any language")
check(has("2 of 2") == false and has("1 of 2"), "both guilds are on the deck now")
press(">")
check(has("Beta Guild") and has("2 of 2") and has("\226\128\156Chill\226\128\157"),"the arrow moves to the next guild")
press(">")
check(has("Alpha Guild") and finder.index == 1, "and wraps round")
press("<")
check(finder.index == 2, "the other arrow goes back")
press("Any language")
check(GuildOSDB.guildFinder.locale == "pt", "a click on the chip goes forward to the first language")
check(finder.index == 1, "a filter sends the deck back to its first card")

-- a chip is a real drop-down where the client has one
local menuItems, menuAnchor
function UIDropDownMenu_Initialize(frame, fn) frame.initFn = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems + 1] = info end
function ToggleDropDownMenu(_, _, frame, anchor) menuItems = {}; menuAnchor = anchor; frame.initFn(frame, 1) end
press("Any day")
check(menuAnchor == buttons["Any day"] and #menuItems == 8, "a click on a chip opens its menu under it: any, and the seven days")
check(menuItems[1].text == "Any day" and menuItems[1].checked == true and menuItems[4].text == "Tue" and menuItems[4].checked == false, "any is ticked while no day is picked")
menuItems[4].func()
check(GuildOSDB.guildFinder.day == 2 and finder.index == 1, "picking a day from the menu saves it")
press("Any day")
check(menuItems[4].checked == true and menuItems[1].checked == false, "and the menu ticks what is picked")
menuItems[1].func()
check(GuildOSDB.guildFinder.day == nil, "any clears it")
press("Any language", "RightButton")
check(GuildOSDB.guildFinder.locale == false, "a right click still steps back, menu or not")
GF:SetFilter("locale", "pt")
menuItems = nil
UIDropDownMenu_Initialize, ToggleDropDownMenu = nil, nil
press("Any day")
check(GuildOSDB.guildFinder.day == 0, "with no drop-down in the client the chip cycles to the next value")
GF:SetFilter("day", nil)

-- more filters, and a filter nobody fits
press("More filters")
check(buttons["Any focus"].shown == true and buttons["More filters"].label.text == "Fewer filters", "more filters opens the second row")
GF:SetFilter("pace", "hardcore")
finder.Refresh()
check(has("No guild fits these filters") and buttons[">"].shown == false and buttons["<"].shown == false, "filters that cut everything say so, and the arrows go")
GF:SetFilter("pace", nil)

-- a verified ad from the site's block: the seal, the schedule, the measured numbers as three blocks
GF:AddSource("block", function()
  return { ad({ n = "Sigma Order", u = "sigma", w = "normal:us", l = { "pt" }, c = { "PALADIN" }, d = { 2, 4 }, s = 1260, e = 0,
                pc = "regular", fo = { "RAID" }, lo = "council", t = "week2", p = "Two nights a week.",
                m = { n = 38, nt = 2, a = 86 }, v = NOW }) }
end)
finder.Refresh()
check(has("Sigma Order") and has("2 of 2") == false and has("1 of 2"), "the site's guild joins the deck, first: it names my class")
check(has(CHECK .. "Verified by GuildOS"), "a verified seal has its check")
check(hasLike("Horde \194\183 Normal \194\183 Americas"), "faction, ruleset and region on the card")
check(has("Tue and Thu \194\183 21:00 to 00:00"), "the days read as in the mock: Tue and Thu, 21:00 to 00:00")
check(has("Regular \194\183 Raid") and has("Loot council \194\183 2 week trial"), "pace with focus; loot with trial")
check(has("38") and has("members") and has("2") and has("nights a week") and has("86%") and has("attendance"), "the measured numbers are three blocks, a figure and its caption")
local shownDots = 0
for _, t in ipairs(textures) do if t.shown then shownDots = shownDots + 1 end end
check(shownDots == 2, "two guilds, two dots")
GF.sources[#GF.sources] = nil

-- nothing heard at all
GuildOS.db.recruitRelay = {}
finder.Refresh()
check(has("No guild heard yet"), "no guild heard says so")
press("Show the list at guildos.me")
check(printed[#printed] == "Address selected — press Ctrl+C", "and offers the address to copy")
RB:Ingest("CR2|Gamma Guild|H|||x|ptBR||" .. (NOW - 5) .. "|" .. (NOW + 86400) .. "|Cai", "Cai")
check(has("Gamma Guild") and buttons[">"].shown == true, "a guild heard while it is open joins the deck")

-- the ways in
local inboxed, built = 0, 0
GuildOS.ShowRecruitInbox = function() inboxed = inboxed + 1 end
local realShow = GuildOS.ShowGuildFinder
GuildOS.ShowGuildFinder = function(self) built = built + 1; return realShow(self) end
finder:Hide()
guilded = false
GuildOS:ToggleRoster()
check(built == 1 and finder:IsShown() and inboxed == 0, "no guild: the roster button opens the finder")
finder:Hide()
SlashCmdList = {}
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("lfg")
check(built == 2 and finder:IsShown() and inboxed == 0, "no guild: /gos lfg opens the finder")
guilded = true
SlashCmdList.GUILDOS("lfg")
check(built == 2 and inboxed == 1, "in a guild /gos lfg is still the inbox of what was heard")
guilded = false
GuildOS.Client.isAnniversary = true
GuildOS:ToggleRoster()
check(built == 2 and inboxed == 2, "Anniversary does not change: the old inbox")
GuildOS.Client.isAnniversary = false
GuildOS.ShowGuildFinder = function() error("could not build") end
local before = #errors
GuildOS:ToggleRoster()
check(inboxed == 3 and #errors == before + 1 and errors[#errors]:find("could not build", 1, true), "a finder that fails to build is recorded and the old inbox opens")

check(GuildOS.GuildFinderHeard ~= nil, "the minimap entry exists")
GuildOS:GuildFinderHeard()
check(alert == true, "hearing a guild lights the minimap")

-- ── The list's age on the screen's sub-line (Task B3) ───────────────────
GuildOS.CompanionImport = nil
check(GF:UpdatedAgo() == nil, "no list, no line")
local listAt
GuildOS.CompanionImport = { RecruitDirectory = function() return listAt and { at = listAt, ads = {} } or nil end }
check(GF:UpdatedAgo() == nil, "a companion with no list says nothing")
listAt = NOW - 30
check(GF:UpdatedAgo() == "The list was updated 1 min ago.", "under a minute reads as one")
listAt = NOW - 25 * 60
check(GF:UpdatedAgo() == "The list was updated 25 min ago.", "minutes")
listAt = NOW - 5 * 3600 - 59
check(GF:UpdatedAgo() == "The list was updated 5 h ago.", "hours")
listAt = NOW - 3 * 86400
check(GF:UpdatedAgo() == "The list was updated 3 d ago.", "days")
GuildOS.CompanionImport = nil

-- ── One guild, however many roads it came by (Task B3) ─
local function bare(a) a.w, a.u = nil, nil; return a end
only({ bare(ad({ n = "Same Name", f = "H", v = 50, heard = true, verified = false })),
       ad({ n = "same name", u = "same-name-normal-us", v = 10 }) })
check(#GF:All() == 1 and GF:All()[1].u == "same-name-normal-us", "an old client's CR2 gives way to the full ad of the same guild, whatever its version")
only({ bare(ad({ n = "Same Name", f = "A", v = 50, heard = true, verified = false })),
       ad({ n = "Same Name", u = "same-name-normal-us", f = "H" }) })
check(#GF:All() == 2, "but one of the other faction is another guild")
only({ bare(ad({ n = "Lonely", f = "H", heard = true, verified = false })) })
check(#GF:All() == 1, "and a CR2 alone stays")

-- What the site's list says in numbers goes through the same door as what a peer says.
for _, bad in ipairs({ "nan", "-nan", "inf", "-inf", "1e999" }) do
  local n = GF:Normalize({ n = "Numero", v = bad, x = bad, s = bad, e = bad, d = { bad, 2 }, m = { n = bad, nt = bad, a = bad } })
  check(n.v == 0 and n.x == 0, bad .. ": no version and no validity")
  check(n.s == nil and n.e == nil and n.m == nil and #n.d == 1, bad .. ": and no night, no number")
end
check(GuildOS.Finite("12") == 12 and GuildOS.Finite(1.5) == 1.5 and GuildOS.Finite(0) == 0, "a number is a number")
check(GuildOS.Finite(nil) == nil and GuildOS.Finite("x") == nil and GuildOS.Finite({}) == nil, "and what is none is nil")
check(GuildOS.Finite(0 / 0) == nil and GuildOS.Finite(1 / 0) == nil and GuildOS.Finite(-1 / 0) == nil, "NaN and inf are none")

-- Retail has thirteen classes: a guild that wants them all keeps the last, or with "Wants my class" on that
-- class never sees it.
local gameClasses = GuildOS.Client.classes
GuildOS.Client.classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
                           "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local everyClass = GF:Normalize({ n = "Todas", c = GuildOS.Client.classes, v = 1, x = NOW + 3600 })
check(#everyClass.c == 13 and everyClass.c[13] == "EVOKER", "the thirteen classes survive: " .. #everyClass.c)
check(GF:Matches(everyClass, { class = "EVOKER" }), "and the last class still sees the guild")
GuildOS.Client.classes = gameClasses

-- ── The request form (Task B4), over the REAL JoinRequests ──────────────────────────────────────────
-- A stand-in once hid a form that did nothing for a guild heard only by CR2; the module is the real one.
-- The officer's list below is drawn over a stand-in: its rules are tools/join-requests.lua's.
function GetTime() return 1 end
function time() return NOW end   -- GuildOS:TimeAgo reads the clock
function UnitLevel() return 12 end
GuildOS.UI.CreateScrollFrame = function() return widget(), widget() end
GuildOSDB = {}
GuildOS.db = { profile = { prefRoles = { HEALER = true } } }
dofile(ADDON .. "/Modules/JoinRequests.lua")
local realJR = GuildOS.JoinRequests
local fake = realJR
dofile(ADDON .. "/UI/GuildFinder.lua")
-- The card is the one a CR2 made: no slug (C1).
local oldAd = { n = "Ordem do Crepusculo", f = "H", w = "normal:us", ct = { "Zed Rocha" } }
GuildOS:ShowJoinForm(oldAd)
local form = GuildOS.joinForm
check(form:IsShown() and has("Ordem do Crepusculo") and has("Ask to join"), "the form names the guild")
check(has("Goes to the officers: Ana, Paladin level 12, Healer"), "and who it goes with: name, class and level, role")
check(has("Message (optional)") and buttons["Send request"] and buttons["Back"], "a message, Send request and Back")
press("Send request")
local sentReq = realJR:Latest(oldAd)
check(sentReq ~= nil, "Send request on a card with no slug sends")
check(has("Saved here"), "and with no answer says Saved here, never delivered")
-- WriteWire passes over a request with no slug: this one can never go by the companion.
check(has("Nothing can be sent from the game this session. The request stays saved here for the next one."),
  "a session that cannot whisper says the truth, and a card with no slug promises no companion")
check(not hasLike("goes to Discord when you leave the game"), "not a word about Discord")
check(buttons["Send request"].shown == false, "the form is gone once it is sent")
-- every reason the module can refuse with has a line
local REFUSALS = { ["in-guild"] = "You are already in a guild.", ["no-ad"] = "This guild cannot be asked right now.",
  ["too-many"] = "You already have 3 open requests.", already = "You already asked this guild." }
for why, line in pairs(REFUSALS) do
  GuildOS.joinForm.ad = { n = "Another Guild " .. why }
  local realSend = realJR.Send
  realJR.Send = function() return nil, why end
  GuildOS.joinForm.Refresh()
  press("Send request")
  realJR.Send = realSend
  check(has(line), "a refusal for " .. why .. " is said: " .. line)
end
GuildOS.joinForm.ad = oldAd
GuildOS.joinForm.Refresh()
GuildOS.ChehulGossip = { CanWhisper = function() return true end }
GuildOS.joinForm.Refresh()
check(has("Nobody from the guild is online nearby. We deliver as soon as someone shows up."),
  "where whispers work, the line with the same promise left out")
check(not hasLike("goes to Discord when you leave the game"), "for a card with no slug")
-- A card with a slug has the companion's road, and says so both ways.
local sluggedAd = { n = "Third Guild", u = "third-guild", f = "H", w = "normal:us", ct = { "Zed Rocha" } }
GuildOS.ChehulGossip.PeerFor, GuildOS.ChehulGossip.Whisper = function() end, function() return false end
GuildOS:ShowJoinForm(sluggedAd)
press("Send request")
check(realJR:Latest(sluggedAd), "the card with a slug is asked too")
check(has("Nobody from the guild is online nearby. We deliver as soon as someone shows up. With the companion, the request goes to Discord when you leave the game."),
  "and its line keeps the companion")
GuildOS.ChehulGossip = nil
GuildOS.joinForm.Refresh()
check(has("Nothing can be sent from the game this session. With the companion, the request goes to Discord when you leave the game."),
  "with no whisper too: the companion's queue is real for it")
GuildOS:ShowJoinForm(oldAd)
realJR:OnCRA("CRA|" .. sentReq.id .. "|officer|Ana Lima", "Ana Lima", "WHISPER")
check(has("Delivered to Ana Lima") and has("An officer is online and has already seen your request."), "an officer's answer shows, live")
realJR:OnCRA("CRA|" .. sentReq.id .. "|member|Bruno Reis", "Bruno Reis", "WHISPER")
check(has("Delivered to Ana Lima"), "a member's after it does not take the officer back")
-- a second card, to see the member's text alone
local second = { n = "Second Guild", ct = { "Zed Rocha" } }
GuildOS:ShowJoinForm(second)
press("Send request")
local secondReq = realJR:Latest(second)
realJR:OnCRA("CRA|" .. secondReq.id .. "|member|Bruno Reis", "Bruno Reis", "WHISPER")
check(has("Delivered to a guild member")
  and has("No officer online right now. Bruno Reis kept the request and will pass it to the next officer who logs in."), "a member's answer")
realJR:OnCRA("CRA|" .. secondReq.id .. "|invited|Ana Lima", "Ana Lima", "WHISPER")
check(has("Invite from Second Guild") and has("Accept in the game window that just opened."), "an invite names the window while it is fresh")
NOW = NOW + 600
GuildOS.joinForm.Refresh()
check(has("The invite window has closed. Ask an officer to invite you again."), "and stops naming it when it can no longer be there")
GuildOS:ShowJoinForm(oldAd)
realJR:OnCRA("CRA|" .. sentReq.id .. "|declined|Ana Lima", "Ana Lima", "WHISPER")
check(has("The guild thanked you, but is not opening spots right now"), "a refusal from the guild, as the mock says it")
only({ ad({ n = "Ordem do Crepusculo" }), ad({ n = "Other One" }) })
GuildOS.joinForm.Refresh()
check(has("There is 1 other guild to look at."), "with one other guild it says so in the singular")
only({ ad({ n = "Ordem do Crepusculo" }), ad({ n = "Other One" }), ad({ n = "Other Two" }) })
GuildOS.joinForm.Refresh()
check(has("There are 2 other guilds to look at."), "and in the plural for more")
press("Back")

-- the officer's list
local rows = {
  { id = "r1", character = "Chehul Costa", class = "PALADIN", level = 12, role = "HEALER", note = "Jogo toda noite", at = NOW - 240, seen = NOW - 30, status = "open", source = "addon" },
  { id = "r2", character = "Marta Vilar", class = "WARRIOR", level = 9, role = "TANK", at = NOW - 3600, status = "open", source = "site" },
  { id = "r3", character = "Davi Rocha", class = "MAGE", level = 14, role = "DPS", at = NOW - 86400, seen = NOW - 86000, status = "open", source = "addon", relayedBy = "Bruno Reis" },
}
local invited, decided = {}, {}
fake.List = function() return rows end
fake.OpenCount = function() return 3 end
fake.CanInvite = function(_, id) return id ~= "r3" end
fake.Invite = function(_, id) invited[#invited + 1] = id; return true end
fake.Decide = function(_, id, st) decided[#decided + 1] = id .. ":" .. st; return true end
fake.Refresh = function() end
LOCALIZED_CLASS_NAMES_MALE.MAGE = "Mage"
GuildOS.Client.has.surnames = true
dofile(ADDON .. "/UI/JoinRequests.lua")
check(GuildOS.ShowJoinRequests and GuildOS.JoinRequestsHeard, "the list and the notice have their entries")
alert = false
GuildOS:JoinRequestsHeard(rows[1])
check(alert == true and has("New guild request") and has("Chehul Costa, Paladin 12, Healer") and has("Click to see"), "the notice names who asked, and lights the minimap")
GuildOS:ShowJoinRequests()
check(GuildOS.joinRequestsFrame:IsShown() and alert == false, "the list opens from it, and puts the light out")
check(has("Join requests") and has("3 open"), "the list says how many are open")
check(has("Paladin 12 \194\183 Healer") and has("Warrior 9 \194\183 Tank"), "each request: class, level and role")
check(has("\226\128\156Jogo toda noite\226\128\157"), "the note, quoted")
check(hasLike("^4m ago \194\183 online now$") and hasLike("^1h ago \194\183 came from the site$")
  and hasLike("^1d ago \194\183 offline \194\183 delivered by Bruno Reis$"), "when, whether the player is there, where it came from")
local function labelled(label)
  local list = {}
  for _, w in ipairs(allButtons) do if w.label.text == label then list[#list + 1] = w end end
  return list
end
-- The game lets no addon invite off Anniversary (#256), and these requests are Forever's and retail's.
local invites = labelled("Invite")
check(#invites == 3 and not invites[1].shown and not invites[2].shown and not invites[3].shown,
  "no Invite on any request: whoever invites types /ginvite")
labelled("Decline")[2].scripts.OnClick()
check(decided[1] == "r2:declined", "Decline decides that request")
opened = {}
labelled("Whisper")[2].scripts.OnClick()   -- [1] is the finder card's
check(opened[1] == "/w Chehul-Costa ", "Whisper opens /w with the hyphen the game's chat takes")

-- Who can invite and is no officer sees no Decline: it would do nothing.
fake.CanDecide = function() return true end
GuildOS.joinRequestsFrame.Refresh()
check(labelled("Decline")[1].shown == true, "an officer sees Decline")
fake.CanDecide = function() return false end
GuildOS.joinRequestsFrame.Refresh()
check(labelled("Decline")[1].shown == false and labelled("Decline")[2].shown == false, "who cannot decide does not")

-- The card's Whisper is the reserve for a session with no addon whisper. On WoW: Forever "/w Ana Lima " is Ana
-- with the message "Lima ": the card takes the hyphen, the same as the officer's list.
GuildOSDB.guildFinder = { locale = false, wantsMe = false }
only({ ad({ n = "Com Sobrenome", ct = { "Ana Lima" } }) })
finder.Refresh()
opened = {}
labelled("Whisper")[1].scripts.OnClick()
check(opened[1] == "/w Ana-Lima ", "the card whispers with the hyphen: " .. tostring(opened[1]))
GuildOS.Client.has.surnames = false
finder.Refresh()
opened = {}
labelled("Whisper")[1].scripts.OnClick()
check(opened[1] == "/w Ana Lima ", "and with no surnames in the game the name is left as it came")

print(("guild-finder: %d checks passed"):format(checks))
