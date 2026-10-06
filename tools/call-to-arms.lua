-- Call to Arms (issue #108), run against the real Core, Compat, Utils, SyncService, CallToArms
-- and Commands under a stubbed client.
--
-- An officer rallies the guild; everyone running the addon gets a popup with a sound, sees how
-- many are coming and can answer "On my way"; a plain guild chat line goes out with it. Only an
-- officer over GUILD may call; the answer is any member's. Members choose how a call reaches
-- them: a popup, a chat line only (popups off, or in an instance or combat), or not at all for
-- a type they muted.
--
--   luajit -e 'ADDON="."' tools/call-to-arms.lua
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

-- ── The client ──────────────────────────────────────────────────────────
local stub
stub = setmetatable({}, { __index = function() return stub end, __call = function() return stub end })
local function widget()
  local w = setmetatable({ scripts = {} }, { __index = stub })
  function w:SetScript(k, fn) self.scripts[k] = fn end
  function w:SetText(t) self.text = t end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:SetShown(v) self.shown = v and true or false end
  function w:Enable() self.enabled = true end
  function w:Disable() self.enabled = false end
  function w:SetTexture(t) self.texture = t end
  function w:CreateFontString() local fs = widget(); return fs end
  function w:CreateTexture() return widget() end
  return w
end

local now, officers, chat, sounds, published, printed, timers = 1791000000, {}, {}, {}, {}, {}, {}
local zone, subzone, instance, combat, chatFails, lockdown = "Feralas", "Dire Maul", "none", false, false, false
-- `db` carries the saved variables across a /reload.
local function load(db)
  chat, sounds, published, printed, timers = {}, {}, {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  function CreateFrame() return widget() end
  function hooksecurefunc() end
  function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  function UnitName() return "Off" end
  function GetRealmName() return "Realm" end
  function GetServerTime() return now end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Rank", officers.me and 1 or 5 end
  function GetNumGuildMembers() return 0, 0 end
  function GetZoneText() return zone end
  function GetSubZoneText() return subzone end
  function IsInInstance() return instance ~= "none", instance end
  function InCombatLockdown() return combat end
  function PlaySound(id) sounds[#sounds + 1] = id end
  function SendChatMessage(msg, channel)
    if chatFails then error("chat refused") end
    chat[#chat + 1] = { msg = msg, channel = channel }
  end
  function Ambiguate(name) return (name or ""):match("^([^-]+)") or name end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Map = nil
  C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end }
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function(secs, fn)
                local t = { secs = secs, fn = fn, Cancel = function(self) self.cancelled = true end }
                timers[#timers + 1] = t
                return t
              end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs, UISpecialFrames = {}, {}
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return { Serialize = function() return "x" end } end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Modules/SyncService.lua")
  BRutus.db = db or { settings = {}, members = {} }
  -- Who is an officer by name; the transport is not the question here.
  BRutus.IsOfficerByName = function(_, name) return officers[(name or ""):match("^([^-]+)")] == true end
  BRutus.SyncService.Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end
  local handlers = {}
  BRutus.SyncService.On = function(_, dom, fn) handlers[dom] = fn end
  BRutus.UI = setmetatable({ CreateButton = function() return widget() end, OpenWindow = function(_, id, sub)
    published[#published + 1] = { opened = id .. "/" .. tostring(sub) } end }, { __index = function() return function() return widget() end end })
  dofile(ADDON .. "/Modules/CallToArms.lua")
  BRutus.CallToArms:Initialize()
  SlashCmdList = {}
  dofile(ADDON .. "/Core/Commands.lua")
  return BRutus.CallToArms, handlers
end
local function last(list) return list[#list] end
local function said(pattern)
  for _, m in ipairs(printed) do if m:find(pattern, 1, true) then return true end end
end

-- ── Who may call ───────────────────────────────────────────────────────
local CTA, handlers = load()
local S = BRutus.SyncService
officers = { Ann = true }
local function valid(dom, act, who, channel) return S:Validate({ v = 1, id = "e", dom = dom, act = act }, who, channel) end
check(valid("cta", "call", "Ann-Realm", "GUILD"), "an officer's call over GUILD is taken")
check(not valid("cta", "call", "Bob-Realm", "GUILD"), "a member's call is refused")
check(not valid("cta", "call", "Ann-Realm", "WHISPER"), "a call outside GUILD is refused")
check(valid("cta", "going", "Bob-Realm", "GUILD"), "a member's 'On my way' is taken")
check(not valid("cta", "going", "Bob-OtherRealm", "WHISPER"), "but only over GUILD")
check(not valid("guildcfg", "going", "Bob-Realm", "GUILD") and not valid("bulletin", "going", "Bob-Realm", "GUILD"),
  "and 'going' opens nothing outside the call to arms")
check(not valid("cta", "rsvp", "Bob-Realm", "GUILD") and valid("event", "rsvp", "Bob-Realm", "GUILD"),
  "as an RSVP opens only the calendar")

-- ── Templates ──────────────────────────────────────────────────────────
local tpls = CTA:Templates()
check(#tpls == 5 and tpls[1].id == "worldboss" and tpls[1].builtin, "five ready-made templates, World Boss first")
check(not CTA:SaveTemplate("", "x", "pvp") and not CTA:SaveTemplate("Ony", "", "pvp"), "a template needs a name and a message")
check(CTA:SaveTemplate("Ony |cffff0000raid", "Onyxia in {zone}!", "worldboss"), "an officer saves one")
local mine = CTA:Templates()[6]
check(mine and mine.name == "Ony cffff0000raid" and mine.kind == "worldboss" and not mine.builtin,
  "it is listed after the ready-made ones, its name cleaned of escape codes")
CTA:DeleteTemplate(mine.id)
check(#CTA:Templates() == 5, "and deleted")
CTA:SaveTemplate("Odd", "x", "nope")
check(CTA:Templates()[6].kind == "rally", "a template of no known type is a rally")
CTA:DeleteTemplate(CTA:Templates()[6].id)
for i = 1, CTA.TEMPLATES_MAX do CTA:SaveTemplate("t" .. i, "x", "rally") end
check(not CTA:SaveTemplate("one more", "x", "rally"), "there is a cap")

-- ── Sending ────────────────────────────────────────────────────────────
CTA, handlers = load()
officers = { Off = true }
officers.me = false
check(not CTA:Send("worldboss") and #published == 0, "a member cannot call")
officers.me = true
check(CTA:Send("worldboss"), "an officer can")
local sent = last(published)
check(sent.dom == "cta" and sent.act == "call" and sent.data.kind == "worldboss" and sent.data.title == "World Boss",
  "the call goes out on the cta domain with its type and title")
check(sent.data.text == "World boss up in Dire Maul, Feralas, come now!" and sent.data.zone == "Dire Maul, Feralas",
  "{zone} becomes where the caller is")
check(last(chat) and last(chat).channel == "GUILD" and last(chat).msg:find("World Boss", 1, true),
  "a plain guild chat line goes with it")
check(CTA.recent[1] and CTA.recent[1].mine, "and the officer sees it among the recent calls")
-- The caller sees what the guild sees (issue #110).
check(CTA.popup and CTA.popup.shown and CTA.popup.callId == sent.data.id and CTA.popup.title.text == "World Boss",
  "the officer who called gets the popup too")
check(CTA.popup.go.shown == false, "without 'On my way': they made the call")
local ownTimer = last(timers)
check(#sounds == 1 and sounds[1] == 8959 and ownTimer.secs == CTA.SHOW_FOR, "with the sound, for thirty seconds")
handlers.cta({ act = "call", data = { id = "R7", kind = "pvp", title = "Other", text = "Go", zone = "Z", ts = now } }, "Dee-Realm")
check(CTA.popup.callId == sent.data.id, "another officer's call a moment later does not cover it")
handlers.cta({ act = "going", data = { id = sent.data.id } }, "Bob-Realm")
check(CTA.popup.count.text == "1 on the way", "and watches the guild answer it")
ownTimer.fn()
check(not CTA.popup.shown, "until it goes away on its own")
now = now + CTA.FROM_GAP
handlers.cta({ act = "call", data = { id = "R9", kind = "pvp", title = "Other", text = "Go", zone = "Z", ts = now } }, "Ann-Realm")
check(CTA.popup.callId == "R9" and CTA.popup.go.shown == true, "a call from somebody else has the button again")
handlers.cta({ act = "call", data = { id = "R8", kind = "pvp", title = "Third", text = "Go", zone = "Z", ts = now } }, "Cid-Realm")
check(CTA.popup.callId == "R9", "and a call landing within ten seconds of a popup does not cover it")
local before = #published
check(not CTA:Send("pvp") and #published == before, "a second call inside the cooldown is refused")
now = now + CTA.COOLDOWN
BRutus:SetSetting("ctaChat", false)
local chats = #chat
check(CTA:Send("pvp", "Crossroads under attack") and #chat == chats, "with the guild line switched off, only the call goes")
check(last(published).data.text == "Crossroads under attack", "a typed message replaces the template's")
check(sent.data.chat == true and not last(published).data.chat, "the call says whether the guild line went")

-- What goes out is clean, whatever was typed or wherever the caller stands.
now = now + CTA.COOLDOWN
zone, subzone = "|cffff0000Feralas|r", ""
-- A saved template is cleaned when saved; this one was edited in the saved variables by hand.
table.insert(BRutus.db.cta.templates, { id = "raw", name = "|Hx|hOny", text = "x", kind = "worldboss" })
check(CTA:Send("raw", "Come to {zone} |cffff0000now|r |Tskull:0|t"), "a call from an officer's own template")
local out = last(published).data
check(not out.text:find("|", 1, true) and not out.zone:find("|", 1, true) and not out.title:find("|", 1, true)
  and out.title == "HxhOny", "no escape code goes out in its title, message or zone")
zone, subzone = "Feralas", "Dire Maul"

-- The chat refusing (an encounter's lockdown) does not stop the call.
now = now + CTA.COOLDOWN
BRutus:SetSetting("ctaChat", true)
chatFails = true
local nPub = #published
check(CTA:Send("rally") and #published == nPub + 1 and not last(published).data.chat,
  "a guild line the chat refused: the call still goes, and does not claim the line")
chatFails = false
-- Forever drops a line refused by an encounter's chat lockdown without an error.
now = now + CTA.COOLDOWN
lockdown = true
local nChat = #chat
check(CTA:Send("rally") and #chat == nChat and not last(published).data.chat,
  "in a chat lockdown the line is not tried, and the call does not claim it")
lockdown = false

-- The cooldown survives a /reload.
local saved = BRutus.db
now = now + 5
CTA, handlers = load(saved)
officers = { Off = true, me = true }
check(not CTA:Send("pvp"), "a /reload does not skip the cooldown")
now = now + CTA.COOLDOWN
check(CTA:Send("pvp"), "which still runs out")
handlers.cta({ act = "call", data = last(published).data }, "Off-Realm")
check(#CTA.recent == 1, "the officer's own call, heard back, is not a second one")

-- The caller's popup keeps the caller's own settings.
CTA, handlers = load()
officers = { Off = true, me = true }
BRutus:SetSetting("ctaPopups", false)
check(CTA:Send("worldboss") and not (CTA.popup and CTA.popup.shown), "with popups off, the caller gets no popup either")
CTA, handlers = load()
officers = { Off = true, me = true }
combat = true
check(CTA:Send("pvp") and not (CTA.popup and CTA.popup.shown) and #sounds == 0, "nor mid-fight with quiet on")
BRutus:SetSetting("ctaQuiet", false)
now = now + CTA.COOLDOWN
check(CTA:Send("pvp") and CTA.popup and CTA.popup.shown, "unless they want popups there too")
combat = false

-- ── Receiving ──────────────────────────────────────────────────────────
CTA, handlers = load()
officers = { Ann = true }
local function call(id, over)
  local d = { id = id, kind = "pvp", title = "World PvP", text = "Go", zone = "Ashenvale", ts = now }
  for k, v in pairs(over or {}) do d[k] = v end
  handlers.cta({ act = "call", data = d }, "Ann-Realm")
end
call("A1")
check(CTA.popup and CTA.popup.shown and CTA.popup.title.text == "World PvP" and CTA.popup.text.text == "Go",
  "a call shows the popup with its title and message")
check(#sounds == 1, "with a sound")
call("A1")
check(#CTA.recent == 1, "the same call twice is one call")
now = now + 5
call("A2")
check(#CTA.recent == 1, "a second call from the same officer inside 30s is dropped")
now = now + 60
call("A3", { ts = now - 700 })
check(#CTA.recent == 1, "a call older than ten minutes is not shown")
call("A4", { kind = "nope", title = "|cffff0000Hi|r", text = "x|Hlink|h" })
check(CTA.recent[1].kind == "rally" and CTA.recent[1].title == "cffff0000Hir" and not CTA.recent[1].text:find("|", 1, true),
  "an unknown type is a rally, and no escape code gets through")
now = now + CTA.FROM_GAP
call("A5", { zone = "|Hz|hAsh" .. ("e"):rep(100), title = ("T"):rep(80), text = ("x"):rep(400), x = "45.2", y = 67.8 })
local got = CTA.recent[1]
check(got.zone:sub(1, 6) == "HzhAsh" and #got.zone <= 60 and #got.title <= CTA.NAME_MAX and #got.text <= CTA.TEXT_MAX,
  "its zone is cleaned too, and every field is cut to size")
check(got.x == 45.2 and got.y == 67.8, "the map position is a number")
for i, pos in ipairs({ { 1e300, 5 }, { -1, 5 }, { 5, 101 }, { "far", 5 } }) do
  now = now + CTA.FROM_GAP
  call("P" .. i, { x = pos[1], y = pos[2] })
  check(CTA.recent[1].id == "P" .. i and CTA.recent[1].x == nil and CTA.recent[1].y == nil,
    "a map position off the map (" .. tostring(pos[1]) .. ", " .. tostring(pos[2]) .. ") is dropped, not the call")
end
now = now + CTA.FROM_GAP
call("F1", { ts = now + CTA.SKEW + 60 })
check(CTA.recent[1].id ~= "F1", "a call stamped from the future is not believed")
call("F2", { ts = now + 30 })
check(CTA.recent[1].id == "F2", "a clock a little ahead is fine")

-- Several officers.
CTA, handlers = load()
officers = { Ann = true, Cid = true }
call("O1")
handlers.cta({ act = "call", data = { id = "O2", kind = "pvp", title = "Other", text = "Go", zone = "Z", ts = now } }, "Cid-Realm")
check(#CTA.recent == 2, "the gap is per officer: another officer's call a second later is taken")
check(CTA.popup.title.text == "World PvP" and said("[Call to Arms]"),
  "but one popup at a time: the second, inside ten seconds of the first, is a chat line")
for i = 1, CTA.KEEP + 3 do
  now = now + CTA.FROM_GAP
  call("K" .. i)
end
check(#CTA.recent == CTA.KEEP and CTA.recent[1].id == "K" .. (CTA.KEEP + 3), "the newest ten calls are kept")

-- The popup goes away on its own; a newer one is not taken down by the older one's timer.
CTA, handlers = load()
officers = { Ann = true }
call("T1")
local firstTimer = timers[1]
now = now + CTA.FROM_GAP
call("T2")
check(firstTimer.secs == 30 and firstTimer.cancelled and #timers == 2,
  "a popup stays thirty seconds, and a newer one cancels the older one's timer")
firstTimer.fn()
check(CTA.popup.shown and CTA.popup.title.text == "World PvP", "and the older timer firing anyway does not hide it")
timers[2].fn()
check(not CTA.popup.shown, "its own timer does")

CTA, handlers = load()
officers = { Ann = true }
call("D1")
now = now + CTA.FROM_GAP + 1
call("D1")
check(#CTA.recent == 1, "the same call heard again later, say relayed, is still one call")

-- How it reaches this player.
local function mode(over)
  CTA, handlers = load()
  officers = { Ann = true }
  for k, v in pairs(over or {}) do BRutus:SetSetting(k, v) end
  call("M" .. math.random(1, 1e9))
  return (CTA.popup and CTA.popup.shown) and "popup" or (said("[Call to Arms]") and "line") or "none"
end
check(mode() == "popup", "by default a call is a popup")
check(sounds[1] == 8959, "a fight's call sounds the raid warning")
check(mode({ ctaPopups = false }) == "line", "popups off: a chat line")
CTA, handlers = load()
officers = { Ann = true }
BRutus:SetSetting("ctaPopups", false)
call("C1", { chat = true })
check(not said("[Call to Arms]"), "a chat line the caller already put in guild chat is not printed again")
CTA, handlers = load()
officers = { Ann = true }
call("S1", { kind = "event" })
check(sounds[1] == 8960, "an event farm's, the ready check")
check(mode({ ctaMute_pvp = true }) == "none", "a muted type: nothing at all")
check(mode({ ctaMute_worldboss = true }) == "popup", "muting another type changes nothing")
for _, kind in ipairs({ "raid", "party", "pvp", "arena" }) do
  instance = kind
  check(mode() == "line", "in an instance (" .. kind .. "): a chat line, not a popup")
end
check(mode({ ctaQuiet = false }) == "popup", "unless the player wants popups there too")
instance, combat = "none", true
check(mode() == "line", "in combat: a chat line")
combat = false
mode({ ctaSound = false })
check(#sounds == 0, "a player can switch the sound off")

-- ── On my way ──────────────────────────────────────────────────────────
CTA, handlers = load()
officers = { Ann = true }
call("G1")
CTA:Answer("G1")
check(last(published).act == "going" and last(published).data.id == "G1", "'On my way' answers the call")
check(CTA:GoingCount(CTA.recent[1]) == 1 and CTA.popup.go.enabled == false, "it counts, and the button is spent")
local repaints = 0
CTA.uiRefresh = function() repaints = repaints + 1 end
handlers.cta({ act = "going", data = { id = "G1" } }, "Bob-Realm")
for _ = 1, 50 do handlers.cta({ act = "going", data = { id = "G1" } }, "Bob-Realm") end
check(CTA:GoingCount(CTA.recent[1]) == 2 and CTA.popup.count.text == "2 on the way", "others' answers count once each")
check(repaints == 1, "and the same answer again repaints nothing")
now = now + CTA.FROM_GAP
call("G2")
handlers.cta({ act = "going", data = { id = "G1" } }, "Cid-Realm")
handlers.cta({ act = "going", data = { id = "nope" } }, "Dee-Realm")
check(CTA:GoingCount(CTA.recent[1]) == 0 and CTA:GoingCount(CTA.recent[2]) == 3,
  "an answer counts on the call it names, and one naming no call counts nowhere")
local n = #published
CTA:Answer("G1")
check(#published == n, "answering twice sends once")
check(CTA.popup.callId == "G2" and CTA.popup.count.text == "" and CTA.popup.go.enabled ~= false,
  "the newer call's popup is untouched by answers to the older one")

-- ── The command ────────────────────────────────────────────────────────
CTA, handlers = load()
officers = { Off = true }
officers.me = true
SlashCmdList.GUILDOS("cta WorldBoss Onyxia is UP")
check(last(published).data and last(published).data.kind == "worldboss" and last(published).data.text == "Onyxia is UP",
  "/gos cta <type> <message> sends it, the type in any case and the message as typed")
SlashCmdList.GUILDOS("cta")
check(last(published).opened == "guild/cta", "/gos cta opens the panel")
SlashCmdList.GUILDOS("cta nonsense")
check(said("Usage: /gos cta"), "an unknown type says how to use it")

print(("call-to-arms: %d checks passed"):format(checks))
