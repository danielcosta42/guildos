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

-- ── The request form and the officer's list (Tasks B4 and B5), drawn over a stand-in for the module ──
-- The rules are tools/join-requests.lua's; here what is checked is what the screens say and press.
function GetTime() return 1 end
function time() return NOW end   -- GuildOS:TimeAgo reads the clock
GuildOS.UI.CreateScrollFrame = function() return widget(), widget() end
local listeners, outbox, sentNote = {}, {}, nil
local stateOf = { state = "stored" }
local fake = {
  ONLINE_SECONDS = 360,
  Listen = function(_, fn) listeners[#listeners + 1] = fn end,
  Me = function() return { character = "Chehul Costa", class = "PALADIN", level = 12, role = "HEALER" } end,
  Latest = function(_, a) return outbox[a.u] end,
  Status = function() return stateOf.state, stateOf.by end,
  Send = function(_, a, note)
    if stateOf.refuse then return nil, stateOf.refuse end
    sentNote = note
    outbox[a.u] = { id = "abc123DEF4", guild = a.n, status = "open" }
    return outbox[a.u]
  end,
}
GuildOS.JoinRequests = fake
dofile(ADDON .. "/UI/GuildFinder.lua")
GuildOS:ShowJoinForm({ n = "Ordem do Crepusculo", u = "ordem", f = "H", w = "normal:us" })
local form = GuildOS.joinForm
check(form:IsShown() and has("Ordem do Crepusculo") and has("Ask to join"), "the form names the guild")
check(has("Goes to the officers: Chehul Costa, Paladin level 12, Healer"), "and who it goes with: name, class and level, role")
check(has("Note (optional)") and buttons["Send request"] and buttons["Back"], "a note, Send request and Back")
stateOf.refuse = "too-many"
press("Send request")
check(has("You already have 3 open requests."), "a refusal says why")
stateOf.refuse = nil
press("Send request")
check(sentNote ~= nil and has("Saved here"), "sent: with no answer it says Saved here, never delivered")
check(has("Nobody from the guild is online nearby. We deliver as soon as someone shows up. With the companion, the request goes to Discord when you leave the game."),
  "and what happens next, as the site can really do it")
check(buttons["Send request"].shown == false, "the form is gone once it is sent")
stateOf.state, stateOf.by = "officer", "Ana Lima"
for _, fn in ipairs(listeners) do fn() end
check(has("Delivered to Ana Lima") and has("An officer is online and has already seen your request."), "an officer's answer shows, live")
stateOf.state, stateOf.by = "member", "Bruno Reis"
for _, fn in ipairs(listeners) do fn() end
check(has("Delivered to a guild member")
  and has("No officer online right now. Bruno Reis kept the request and will pass it to the next officer who logs in."), "a member's answer")
stateOf.state = "invited"
for _, fn in ipairs(listeners) do fn() end
check(has("Invite from Ordem do Crepusculo") and has("Accept in the game window that just opened."), "an invite")
stateOf.state = "declined"
for _, fn in ipairs(listeners) do fn() end
check(has("Ordem do Crepusculo thanked you, but is not opening spots right now"), "a refusal from the guild")
press("Back")

print(("guild-finder: %d checks passed"):format(checks))
