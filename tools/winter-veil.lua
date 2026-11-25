-- Winter Veil's snow globe in the game (issue #437; the site's specs/119), run against the real CompanionImport and
-- WinterVeil under stubbed WoW APIs.
--
-- The site holds the event, the pairs and every rarity; the addon reads two blocks and tells the site what the player
-- asked. This proves: the seal is the site's byte for byte (the vector is the site's own test's); the guild's block
-- and a person's block (GOSVEIL1 v2) are read to their shape and refused when they are not theirs; a note is held to
-- the site's rules before it is sent; a pair a carrier whispers opens only for its owner; on the guild channel a
-- player speaks only for themselves and never about wrapping or opening; a request to open never carries a
-- rarity; and the export (GOSCOMP1.veil: joins, leaves, wrap, open) stays within the site's limits.
--
--   luajit -e 'ADDON="."' tools/winter-veil.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── WoW API surface ───────────────────────────────────────────────────
local NOW = 1765800000
local GUILD = "Curva-Mor"
local ME = "Chehul"
function GetServerTime() return NOW end
function GetTime() return 0 end
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Member", 3 end
function GetRealmName() return "Nightslayer" end
function UnitName() return ME end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end
local roster = { { "Thalindra-Nightslayer", true }, { "Kaelthos-Nightslayer", true } }
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) local r = roster[i]; return r[1], nil, nil, nil, nil, nil, nil, nil, r[2] end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

GuildOS = {
  VERSION = "1.42.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
  Client = { isAnniversary = true, defaultRaidSize = 25 },
  Compat = {
    PlayerName = function() return ME end,
  },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:Print() end
function GuildOS:IsOfficer() return false end
dofile(ADDON .. "/Core/Utils.lua")

local published = {}
GuildOS.SyncService = {
  Publish = function(_, dom, act, data, opts) published[#published + 1] = { dom = dom, act = act, data = data, opts = opts } end,
  On = function() end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/WinterVeil.lua")
local Import, WV = GuildOS.CompanionImport, GuildOS.WinterVeil

local function pack(fmt, t)
  return fmt .. ":" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local SALT = "00112233445566778899aabbccddeeff"
local function veil(extra)
  local v = { year = 2025, joinUntil = NOW - 86400, wrapUntil = NOW + 5 * 86400, openAt = NOW + 6 * 86400, reassignDays = 3,
              drawn = true, salt = SALT, chimney = 60, counts = { entrants = 5, wrapped = 3, pairs = 5, opened = 0 } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
local function inbox(gild, personal)
  GuildOSInbox = {}
  if gild then GuildOSInbox[#GuildOSInbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, veil = gild }) end
  if personal then
    local p = { fmt = "GOSVEIL1", v = 2, guild = GUILD, realm = "Nightslayer", at = NOW - 60, year = 2025, mine = {}, relay = {}, collection = {} }
    for k, x in pairs(personal) do p[k] = x end
    GuildOSInbox[#GuildOSInbox + 1] = pack("GOSVEIL1", p)
  end
  Import._blockRaw, Import._veilRaw = nil, nil
end
local ME_KEY = "Chehul-Nightslayer"
local function personal(gives, got, extra)
  local p = { mine = { { key = ME_KEY, volunteer = false, gives = gives or {}, got = got } } }
  for k, x in pairs(extra or {}) do p[k] = x end
  return p
end

-- ── 1. The seal is the site's, byte for byte ──────────────────────────
check(WV.Fnv1a("abc") == 0x1a47e90b, "FNV-1a matches the site's")
check(WV.Seal("Winter Veil", "salt:Key") == "6c969bcc2c44b67092fb17", "the seal matches the site's frozen vector")
check(WV.Unseal(WV.Seal('{"to":"X"}', "k"), "k") == '{"to":"X"}', "a seal opens with its key")
check(WV.Unseal("zz", "k") == nil and WV.Unseal("abc", "k") == nil, "and refuses what is not hex")

-- ── 2. The guild's block ──────────────────────────────────────────────
inbox(nil)
check(WV:Event() == nil, "no block, no event")
inbox(veil({ wrapUntil = "soon" }))
check(WV:Event() == nil, "a date that is not a number is no event")
inbox(veil({ reassignDays = 30 }))
check(WV:Event() == nil, "a term the site never sends is no event")
inbox(veil({ entrants = { { key = "Thalindra-Nightslayer", wrapped = true }, { key = "bad|key" } },
  carriers = { { giver = "Chehul-Nightslayer", carrier = "Kaelthos-Nightslayer" } } }))
local e = WV:Event()
check(e and e.drawn and e.salt == SALT and e.chimney == 60 and e.counts.wrapped == 3, "the event is read, with the Chimney")
check(#e.entrants == 1 and e.entrants[1].key == "Thalindra-Nightslayer" and e.entrants[1].wrapped, "an entrant with a key that is not one is passed over")
check(e.carriers["Chehul-Nightslayer"] == "Kaelthos-Nightslayer", "the carriers are read")
check(WV.PhaseOf(e, NOW) == "wrapping" and WV.PhaseOf(e, NOW + 5 * 86400 + 1) == "wrapped" and WV.PhaseOf(e, NOW + 7 * 86400) == "open", "the phase is the event's own clock")
check(WV.PhaseOf(veil({ drawn = false }) and { joinUntil = NOW + 10, wrapUntil = NOW + 20, openAt = NOW + 30, drawn = false }, NOW) == "joining", "joining before the draw")
inbox(veil({ chimney = 140 }))
check(WV:Event() == nil, "a Chimney over 100% is no event")
inbox(veil({ reveal = {
  { giver = "Kaelthos-Nightslayer", to = "Chehul-Nightslayer", scene = "cabin", rarity = "epic" },
  { giver = "Frimm", to = "Thalindra-Nightslayer", scene = "tree", rarity = "common", host = true },
  { giver = "Kaelthos-Nightslayer", to = "Thalindra-Nightslayer", scene = "castle", rarity = "epic" },
  { giver = "Kaelthos-Nightslayer", to = "Thalindra-Nightslayer", scene = "fire", rarity = "mythic" } } }))
e = WV:Event()
check(#e.reveal == 2 and e.reveal[1].scene == "cabin" and e.reveal[2].host == true and e.reveal[2].giver == "Frimm", "the chain keeps the globes whose scene and rarity are the site's, and the host's")
-- Before the site opens it to everybody, a tester's own block carries the event and the guild's says nothing.
inbox(nil, { mine = {}, event = veil() })
check(WV:Event() and WV:Event().chimney == 60, "a tester's own block carries the event before the opening")
inbox({ nothing = true }, { mine = {}, event = veil({ chimney = 10 }) })
check(WV:Event().chimney == 10, "a guild block with no valid event leaves the tester's")

-- ── 3. My block (GOSVEIL1 v2) ─────────────────────────────────────────
local OPENED = { id = "o1", year = 2025, scene = "cabin", rarity = "epic", openedAt = NOW - 100, from = "Kaelthos-Nightslayer", note = "Que o seu inverno seja quente" }
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", toClass = "MAGE", wrapped = false } }, { ready = true, ornament = OPENED },
  { collection = { OPENED, { id = "o0", year = 2024, scene = "castle", rarity = "rare", openedAt = NOW - 5000 }, { id = "o2", year = 2024, scene = "fire", rarity = "legendary", openedAt = NOW - 5000, host = true } },
    relay = { { giver = "Kaelthos-Nightslayer", seal = WV.Seal('{"to":"Chehul-Nightslayer"}', SALT .. ":Kaelthos-Nightslayer") } } }))
local p = WV:Personal()
check(p and #p.mine == 1 and p.mine[1].gives[1].to == "Thalindra-Nightslayer" and not p.mine[1].gives[1].wrapped, "my block says whom I drew")
check(#p.relay == 1, "and the pair I carry")
check(WV:Got().ornament.rarity == "epic" and WV:Got().ornament.from == "Kaelthos-Nightslayer", "the globe I got comes with its rarity, as the site drew it")
check(#WV:Collection() == 2 and WV:Collection()[2].host == true, "the Collection keeps the globes the site sends and drops a scene it never sends")
GuildOSInbox = { pack("GOSVEIL1", { fmt = "GOSVEIL1", v = 1, guild = GUILD, at = NOW - 60, year = 2025, mine = {}, relay = {} }) }
Import._veilRaw = nil
check(WV:Personal() == nil, "the first design's v1 block is refused")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", scene = "volcano", note = string.rep("a", 400), wrapped = true } }))
check(WV:MyGives()[1].scene == nil and WV:MyGives()[1].note == nil, "a scene outside the five and a note past the limit are dropped")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", note = "Feliz |cffff0000Natal|r", wrapped = true, scene = "tree" } }))
check(not WV:MyGives()[1].note:find("|", 1, true), "a note off the network opens no colour code")

-- ── 4. The note: the site's rules, checked here first ──────────────────
check(WV.CleanNote("  Feliz   Natal \n ") == "Feliz Natal", "whitespace collapses")
check(WV.CleanNote(nil) == "" and WV.CleanNote("") == "", "no note is fine")
check(WV.CleanNote(string.rep("a", 80)) and not WV.CleanNote(string.rep("a", 81)), "80 characters, not 81")
check(WV.CleanNote(string.rep("\195\169", 80)) and not WV.CleanNote(string.rep("\195\169", 81)), "a character counts once, not by its bytes")
for _, bad in ipairs({ "oi @fulano", "veja https://x.y", "www.site.pt", "ver site.com agora", "a `b`", "*forte*", "a_b", "a~b", "<b>", "[x]", "a|b", "a\\b", "#tag", "ctl\1x", "bell\127", "zero\226\128\139width", "c1\194\133x", "dir\226\128\174x", "iso\226\129\166x" }) do
  check(WV.CleanNote(bad) == nil, "the note is refused: " .. bad:gsub("%c", "?"))
end
check(WV.CleanNote("2025.me") == nil and WV.CleanNote("Natal; paz, amor!") == "Natal; paz, amor!", "a link by its end is refused, punctuation is not")

-- ── 5. Wrapping: a scene and a note, whole ────────────────────────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", toClass = "MAGE", wrapped = false } }))
check(WV:Wrap("Kaelthos-Nightslayer", "tree", "oi") == false, "a globe for somebody I did not draw is refused")
check(select(2, WV:Wrap("Thalindra-Nightslayer", "castle", "oi")) == "scene", "a scene outside the five is refused")
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "oi @x")) == "note", "a note the site would refuse is refused")
check(WV:Wrap("Thalindra-Nightslayer", "cabin", "Feliz Natal!") == true, "a globe within the rules is kept")
local g = WV:MyGives()[1]
check(g.wrapped and g.scene == "cabin" and g.note == "Feliz Natal!", "and shows at once, before the site's next block")
check(#published == 0 or published[#published].act ~= "wrap", "wrapping is never said on the guild channel")
check(WV:Wrap("Thalindra-Nightslayer", "fire", "Outra") == true and WV:MyGives()[1].scene == "fire", "wrapping again replaces the scene and the note")
inbox(veil({ wrapUntil = NOW - 10, openAt = NOW + 86400 }), personal({ { to = "Thalindra-Nightslayer" } }))
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "")) == "phase", "after the deadline nothing is wrapped")
inbox(veil(), nil)
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "")) == "companion", "without the companion's block the game does not wrap")
-- Two pairs (one taken over from somebody who did not wrap): the line names the receiver.
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" }, { to = "Gorbash-Nightslayer", extra = true } }))
WV._store().wraps = {}
check(WV:Wrap("Gorbash-Nightslayer", "snowman", "Para o urso") == true, "the extra pair can be wrapped")
local out = WV:ForExport()
check(#out.wrap == 1 and out.wrap[1].giver == ME_KEY and out.wrap[1].to == "Gorbash-Nightslayer" and out.wrap[1].scene == "snowman" and out.wrap[1].note == "Para o urso", "with two pairs the export line names the receiver")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" } }))
WV._store().wraps = {}
WV:Wrap("Thalindra-Nightslayer", "tree", "")
out = WV:ForExport()
check(#out.wrap == 1 and out.wrap[1].to == nil and out.wrap[1].note == "", "with one pair the receiver is implied")

-- ── 6. Opening: the game asks, the site draws ─────────────────────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true }))
check(select(2, WV:RequestOpen()) == "phase", "nothing opens before the opening date")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = false }))
check(select(2, WV:RequestOpen()) == "nothing", "a globe that is not there cannot be opened")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true }))
check(WV:RequestOpen() == true and WV:OpenRequested(), "the receiver asks to open")
out = WV:ForExport()
check(#out.open == 1 and out.open[1].receiver == ME_KEY and out.open[1].at == NOW, "the export carries the request")
local json = GuildOS.Companion.EncodeJson(out)
check(not json:find("rarity", 1, true) and not json:find("common", 1, true), "and never a rarity: the server draws it")
check(#published == 0 or published[#published].act ~= "open", "opening is never said on the guild channel")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = OPENED }))
check(select(2, WV:RequestOpen()) == "nothing", "an opened globe is not asked for twice")

-- ── 7. The relay: a whispered pair opens only for its owner ───────────
inbox(veil({ carriers = { { giver = "Chehul-Nightslayer", carrier = "Kaelthos-Nightslayer" } } }),
      { mine = {}, relay = { { giver = "Kaelthos-Nightslayer", seal = WV.Seal('{"to":"Chehul-Nightslayer"}', SALT .. ":Kaelthos-Nightslayer") } } })
local before = #published
check(WV:Relay() == 1 and published[#published].act == "pair" and published[#published].opts.target == "Kaelthos-Nightslayer", "I whisper the pair I carry to its owner, online")
check(WV:Relay() == 0 and #published == before + 1, "and not again within the hour")
local sealed = WV.Seal('{"to":"Thalindra-Nightslayer"}', SALT .. ":Chehul-Nightslayer")
local forged = WV.Seal('{"to":"Kaelthos-Nightslayer"}', SALT .. ":Chehul-Nightslayer")
WV:OnEnvelope({ act = "pair", data = { g = "Chehul-Nightslayer", s = forged } }, "Thalindra-Nightslayer")
check(#WV:MyGives() == 0, "a pair whispered by anybody but my carrier is not believed: every member holds the salt")
WV:OnEnvelope({ act = "pair", data = { g = "Chehul-Nightslayer", s = sealed } }, "Kaelthos-Nightslayer")
check(WV:MyGives()[1] and WV:MyGives()[1].to == "Thalindra-Nightslayer", "a pair whispered to me opens with the guild's salt")
check(published[#published].act == "got", "and I say I have it")
check(WV:OpenPair(WV.Seal('{"to":"X-Nightslayer"}', SALT .. ":Someone-Nightslayer")) == false or WV:MyGives()[1].to ~= "X-Nightslayer", "another's pair does not open as mine")
check(WV:OpenPair(WV.Seal('{"nope":1}', SALT .. ":Chehul-Nightslayer")) == false, "a pair with no target is no pair")

-- ── 8. The guild channel: a player speaks only for themselves ─────────
local s = WV._store()
WV:OnEnvelope({ act = "join", data = { k = "Thalindra-Nightslayer", v = false, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Thalindra-Nightslayer"] == nil, "an entry announced for somebody else is dropped")
WV:OnEnvelope({ act = "join", data = { k = "Kaelthos-Nightslayer", v = true, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join.volunteer == true, "a player's own entry is kept")
WV:OnEnvelope({ act = "leave", data = { k = "Kaelthos-Nightslayer", at = NOW - 9 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join ~= nil, "an older leave does not undo a newer entry")
WV:OnEnvelope({ act = "leave", data = { k = "Kaelthos-Nightslayer", at = NOW - 1 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join == nil and s.people["Kaelthos-Nightslayer"].left == NOW - 1, "a newer one does")
WV:OnEnvelope({ act = "wrap", data = { g = "Kaelthos-Nightslayer", sc = "tree", n = "x", at = NOW - 5 } }, "Kaelthos-Nightslayer")
WV:OnEnvelope({ act = "open", data = { r = "Kaelthos-Nightslayer", at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(next(s.wraps) == nil or s.wraps["Kaelthos-Nightslayer"] == nil, "a line about wrapping or opening is not a thing of the channel")
WV:OnEnvelope({ act = "join", data = { k = "Gorbash-Nightslayer", v = false, at = NOW + 4000 } }, "Gorbash-Nightslayer")
check(s.people["Gorbash-Nightslayer"] == nil, "a stamp from the future is dropped")

-- ── 9. Joining, and the export within the site's limits ───────────────
inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
check(WV:Join(true) == true and WV:Joined(), "I can join before it closes")
check(published[#published].act == "join" and published[#published].data.k == ME_KEY, "and say so, as myself")
out = WV:ForExport()
check(out.year == 2025 and #out.joins >= 1 and #out.leaves >= 0, "the export names the year and the entries")
check(WV:Leave() == true and not WV:Joined(), "I can leave before the draw")
inbox(veil({ drawn = true }), { mine = {} })
check(WV:Join(false) == false and WV:Leave() == false, "and neither after it")
inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
for i = 1, 150 do GuildOS.db.winterVeil.people["P" .. i .. "-Nightslayer"] = { join = { volunteer = false, at = NOW - i } } end
check(#WV:ForExport().joins == 100, "a guild of hundreds stays within the site's cap, newest first")
local enc = GuildOS.Companion.EncodeJson(WV:ForExport())
check(not enc:find('"prices"', 1, true) and not enc:find('"needs"', 1, true) and not enc:find('"deliveries"', 1, true), "nothing of the first design is in the export")
check(not WV.RecordDelivery and not WV.ScanPrices and not WV.SetList, "and the module has none of it")

-- ── 10. The panel draws every state without an error, and shows what the site said ──
do
  local Frame = {}
  -- Unknown methods are no-ops; a field the panel keeps for itself ("_seen") is nil until set, as on a real frame.
  Frame.__index = function(_, k) if type(k) == "string" and k:sub(1, 1) == "_" then return nil end return Frame[k] or function(self) return self end end
  local function new() return setmetatable({ shown = true, scripts = {}, text = "" }, Frame) end
  -- The game fires OnTextChanged when SetText is called, even with the same text: the stub does too, and counts how deep
  -- the handlers nest, so a draw that sets the text of its own edit box and re-enters itself is caught (the game would
  -- end it with a C stack overflow, which SafeCall swallows).
  local depth, maxDepth = 0, 0
  function Frame:SetText(t)
    self.text = t
    local hooks = rawget(self, "hooks")
    local hook = hooks and hooks.OnTextChanged
    if hook then
      depth = depth + 1; maxDepth = math.max(maxDepth, depth)
      if depth <= 30 then pcall(hook, self, false) end
      depth = depth - 1
    end
  end
  function Frame:GetText() return self.text end
  function Frame:SetShown(v) self.shown = v and true or false end
  function Frame:Show() self.shown = true end
  function Frame:Hide() self.shown = false end
  function Frame:SetScript(n, fn) self.scripts[n] = fn end
  function Frame:HookScript(name, fn) local h = rawget(self, "hooks"); if not h then h = {}; self.hooks = h end; h[name] = fn end
  function Frame:SetTexture(t) self.tex = t end
  function Frame:CreateTexture() return new() end
  function Frame:SetEnabled(v) self.enabled = v end
  local tabs, texts = {}, {}
  local UI = {}
  for _, name in ipairs({ "CreateTitle", "CreateText", "CreateSectionTitle", "CreateMetricChip", "CreateProgressBar", "CreateButton",
                          "CreateCheckbox", "CreatePanel", "SetButtonVariant" }) do
    UI[name] = function(_, a, b)
      local f = new()
      if type(b) == "string" then f.text = b elseif type(a) == "string" then f.text = a end
      texts[#texts + 1] = f
      return f
    end
  end
  UI.CreateCheckbox = function() local f = new(); f.checkbox = new(); return f end
  UI.CreateTextArea = function() local f = new(); f.edit = new(); return f end
  UI.CreateTab = function(_, _, text) local f = new(); f.tabName = text; function f:SetActive() end; tabs[text] = f; return f end
  GuildOS.UI = UI
  GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  GuildOS.QualityColors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  GuildOS.L = setmetatable({}, { __index = function(_, k) return k end })
  function CreateFrame() return new() end
  function date(...) return os.date(...) end
  local officer = false
  function GuildOS:IsOfficer() return officer end
  dofile(ADDON .. "/UI/WinterVeilPanel.lua")
  local container = new()
  local panel = GuildOS:CreateWinterVeilPanel(container)
  local function say(text)
    for _, f in ipairs(texts) do if f.shown and f.text and tostring(f.text):find(text, 1, true) then return true end end
    return false
  end
  local function draw() local ok, err = pcall(panel.Draw); check(ok, "the panel draws: " .. tostring(err)) end
  local function tab(name) tabs[name].scripts.OnClick(); end

  inbox(nil); draw()
  check(true, "no event, no error")
  inbox(veil({ drawn = false, joinUntil = NOW + 86400 }), { mine = {} }); draw()
  check(say("Join the Secret Santa"), "before joining closes, it offers to join")
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("YOU DREW") and say("Wrap"), "after the draw it shows whom I drew and the wrapping")
  inbox(veil({ chimney = 100 }), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "fire", note = "oi" } })); draw()
  check(say("full: better odds"), "a full Chimney says the odds are better")

  inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer", rarity = "rare" } }, { ready = true }))
  GuildOS.db.winterVeil.opens = {}
  draw()
  check(say("Open the globe") and say("Yours for"), "at the opening the receiver is offered the globe, and sees the rarity of the one given")
  inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = OPENED })); draw()
  check(say("Epic") and say("Que o seu inverno seja quente"), "an opened globe shows its rarity and note, as the site drew them")
  check(say("Asked: waiting for the site") == false, "the request is not shown once the site has answered")
  tab("Collection"); draw()
  check(say("COLLECTION"), "the Collection tab draws")
  tab("The guild's chain"); draw()
  check(say("THE GUILD'S CHAIN"), "the chain tab draws")
  officer = true; tab("Organize"); draw()
  check(say("PARTICIPANTS"), "the officers' table draws")
  tab("My secret friend"); draw()

  -- The link to the page says the guild's key, encoded; without a key it is the public page.
  inbox(veil({ guildKey = "us:Curva Mor" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  check(GuildOS.WinterVeil:Event().guildKey == "us:Curva Mor", "the event carries the guild's key")
  inbox(veil({ guildKey = "bad|key" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  check(GuildOS.WinterVeil:Event().guildKey == nil, "a key that is not one line is dropped")
  local hadCompanion = GuildOS.WinterVeil.HasCompanion
  GuildOS.WinterVeil.HasCompanion = function() return false end
  inbox(veil({ guildKey = "us:Curva Mor" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("guildos.me/guild/us%3ACurva%20Mor/winter-veil"), "a player without the companion is sent to the guild's page of the event")
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("guildos.me/winter-veil"), "and, with no key, to the public page")
  GuildOS.WinterVeil.HasCompanion = hadCompanion

  -- A wrap kept here with an empty note (allowed: the note is optional): a panel just opened fills its note box from
  -- it, and must not re-enter itself through the box's OnTextChanged (the game fires it on SetText, same text or not).
  GuildOS.db.winterVeil.wraps["Thalindra-Nightslayer"] = { scene = "fire", note = "", at = NOW }
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  local fresh = GuildOS:CreateWinterVeilPanel(new())
  maxDepth = 0
  local okf, errf = pcall(fresh.Draw)
  check(okf, "a panel with a locally wrapped globe of an empty note draws: " .. tostring(errf))
  check(maxDepth <= 2, "and does not re-enter itself through the note box (depth " .. maxDepth .. ")")
end

print(string.format("winter-veil: %d checks passed", checks))
