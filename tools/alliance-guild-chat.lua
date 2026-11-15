-- The alliance's guild chat (issue #344), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Libs (LibDeflate, LibSerialize), Modules/AllianceSync.lua, Modules/Alliance.lua,
-- Modules/AllianceChat.lua, Modules/GuildChat.lua, Modules/Mesh.lua and Modules/AllianceGuildChat.lua
-- under a stubbed client and mesh.
--
-- One client of "Guilda A", in a pact with "Guilda B" and "Guilda C". Proves:
--   * the bridge whispers each batch of /g to one compatible client of each allied guild, and only
--     the bridge does; officer chat is never read;
--   * a whisper is taken only from somebody who speaks for the guild it claims (ambassador or synced
--     roster), never for our own guild or a blocked one; it is shown once, in the frames that show
--     /g, with the guild's tag, and said once on GUILD; a GUILD hop is shown and never sent on;
--   * the same line twice is shown once; an ignored speaker and a hidden line are not shown; the
--     preference hides the lines without stopping the guild hop;
--   * only allowed links survive, any other pipe is literal;
--   * routes learned from traffic win over the mesh and die on "No player named";
--   * the Guild tab merges the allied lines with ours;
--   * the data ops (HEAD) take a bridge on a member guild's roster, the pact's ops (PACT) do not;
--   * the HELLO advertises the capability.
--
--   luajit -e 'ADDON="."' tools/alliance-guild-chat.lua
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
local NOW = 1791000000
function GetServerTime() return NOW end
time = function() return NOW end
function GetTime() return NOW end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function GetNormalizedRealmName() return "Realm" end
function UnitName() return "Ana" end
function GetGuildInfo() return "Guilda A", "Member", 3, nil end
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function Ambiguate(name) return (tostring(name):gsub("%-Realm$", ""):gsub("%-.*$", "")) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
  local out, start = {}, 1
  while true do
    if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
  return unpack(out)
end
function hooksecurefunc() end
function GetPlayerInfoByGUID(guid) if guid == "Player-1-A" then return "Mage", "MAGE" end end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" } }
CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: "
ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25, id = 4 } }
NUM_CHAT_WINDOWS = 2
local printed = { {}, {} }
ChatFrame1 = { AddMessage = function(_, t) printed[1][#printed[1] + 1] = t end, shows = true }
ChatFrame2 = { AddMessage = function(_, t) printed[2][#printed[2] + 1] = t end, shows = false }
function ChatFrame_ContainsMessageGroup(f, group) return group == "GUILD" and f.shows end
DEFAULT_CHAT_FRAME = ChatFrame1
local ignored = {}
C_FriendList = { IsIgnored = function(name) return ignored[name] == true end }

local timers = {}
C_Timer = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  NewTicker = function() return { Cancel = function() end } end,
}
local function runTimers()
  while #timers > 0 do
    local fn = table.remove(timers, 1)
    fn()
  end
end

local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(_, fn) self.fn = fn end
  function f:HookScript() end
  function f:SetPoint() end
  function f:Hide() end
  function f:Show() end
  frames[#frames + 1] = f
  return f
end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
}, { __call = function(_, name, silent)
  if registry[name] or silent then return registry[name] end
  error("no lib " .. name)
end })

-- The mesh: what we whisper and say on GUILD, and the handler we register.
local whispers, guildSaid, handler = {}, {}, nil
ChehulMesh = {
  Register = function(_, prefix, fn) if prefix == "ChehulAllyChat" then handler = fn end end,
  Whisper = function(_, prefix, payload, target)
    whispers[#whispers + 1] = { prefix = prefix, payload = payload, target = target }
    return true
  end,
  Guild = function(_, prefix, payload) guildSaid[#guildSaid + 1] = { prefix = prefix, payload = payload }; return true end,
}
local peers = {
  Bea = { caps = "gosv=1.23.0,gosg=Guilda B,gosa=NUCLEO,gosc=1", ts = NOW - 5 },
  Cal = { caps = "gosv=1.20.0,gosg=Guilda C,gosa=NUCLEO", ts = NOW - 5 },   -- an older client
}
ChehulNet = { Peers = function() return peers end }

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
            SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Modules/AllianceSync.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
dofile(ADDON .. "/Modules/AllianceChat.lua")
dofile(ADDON .. "/Modules/GuildChat.lua")
dofile(ADDON .. "/Modules/Mesh.lua")
dofile(ADDON .. "/Modules/AllianceGuildChat.lua")
GuildOS.State = GuildOS.State or {}
GuildOS.isGuilded = true
GuildOS.db = {
  members = {},
  alliance = {
    tag = "NUCLEO", name = "Nucleo", owner = "Guilda A", revision = 1,
    guilds = {
      ["Guilda A"] = { ambassadors = { "Ana" } },
      ["Guilda B"] = { ambassadors = { "Bia" } },
      ["Guilda C"] = { ambassadors = { "Cid" } },
      ["Guilda D"] = { ambassadors = { "Duda" } },
    },
    blocked = { ["Guilda D"] = true },
  },
}
local A, AGC, GC = GuildOS.Alliance, GuildOS.AllianceGuildChat, GuildOS.GuildChat
local index = { bob = { guild = "Guilda B", row = { n = "Bob" } }, eve = { guild = "Guilda Z", row = { n = "Eve" } } }
GuildOS.AllianceSync.MemberIndex = function() return index end
local bridge = true
A.AmBridge = function() return bridge end

GuildOS.AllianceChat:Prefs()
AGC:Initialize()
check(type(handler) == "function", "the chat prefix is registered on the mesh")

local ours
for _, f in ipairs(frames) do if f.events.CHAT_MSG_GUILD and f.fn then ours = f end end
check(ours ~= nil, "the module listens to /g")
check(not ours.events.CHAT_MSG_OFFICER, "officer chat is never read")

local function sayInGuild(msg, author, guid)
  ours.fn(ours, "CHAT_MSG_GUILD", msg, author, "", "", "", "", 0, 0, "", nil, 1, guid)
end
local function decode(payload)
  local proto, op, blob = strsplit("|", payload, 3)
  return proto, op, A.Decode(blob)
end
local function receive(op, tbl, sender, dist)
  handler(AGC.PROTO .. "|" .. op .. "|" .. A.Encode(tbl), sender, dist)
end
local function reset() whispers, guildSaid, printed[1], printed[2] = {}, {}, {}, {} end

-- ── 1. Out: the bridge whispers its guild's /g ─────────────────────────
sayInGuild("alguem pra kara?", "Ana-Realm", "Player-1-A")
sayInGuild("eu vou", "Leo-Realm")
check(#whispers == 0, "lines wait for the batch")
runTimers()
check(#whispers == 1, "one whisper per allied guild with a route: B only (C's client is too old, D is blocked)")
check(whispers[1].target == "Bea" and whispers[1].prefix == "ChehulAllyChat", "to the compatible client of B")
local proto, op, data = decode(whispers[1].payload)
check(proto == "AC1" and op == "L", "an L frame")
check(data.g == "Guilda A" and #data.l == 2, "both lines in one whisper, under our guild")
check(data.l[1].m == "alguem pra kara?" and data.l[1].c == "MAGE", "the line and the speaker's class")

reset()
bridge = false
AGC._bridgeAt = nil
sayInGuild("ninguem ouve", "Leo-Realm")
runTimers()
check(#whispers == 0, "a client that is not the bridge sends nothing")
bridge = true
AGC._bridgeAt = nil

-- ── 2. In: a whisper from who speaks for B ─────────────────────────────
reset()
receive("L", { g = "Guilda B", l = { { n = "Bob-Realm", m = "bora", c = "MAGE" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 1, "shown in the frame that shows /g")
check(#printed[2] == 0, "and not in a frame that does not")
check(printed[1][1]:find("[Guilda B]", 1, true) and printed[1][1]:find("bora", 1, true), "tagged with B")
check(printed[1][1]:find("|Hplayer:Bob-Realm|h", 1, true), "the name whispers the speaker")
check(printed[1][1]:find("|Hchannel:GUILD|h[Guild]|h", 1, true), "drawn as a line of /g")
check(#guildSaid == 1, "said once on GUILD for the rest of the guild")
local _, fop, fdata = decode(guildSaid[1].payload)
check(fop == "F" and fdata.g == "Guilda B" and fdata.r == "Bob-Realm", "an F frame naming the guild and the route")
check(#whispers == 0, "a received line is never whispered on")
local entries = GC:Entries(nil)
check(#entries == 1 and entries[1].g == "Guilda B" and entries[1].n == "Bob", "the Guild tab has it, with its guild")

reset()
receive("L", { g = "Guilda B", l = { { n = "Bob-Realm", m = "bora" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 0, "the same line twice is shown once")
check(#guildSaid == 0, "and a line already shown is not said on GUILD again")

-- ── 3. Trust ───────────────────────────────────────────────────────────
reset()
receive("L", { g = "Guilda B", l = { { n = "Eve", m = "spam" } } }, "Eve-Realm", "WHISPER")
check(#printed[1] == 0 and #guildSaid == 0, "somebody not on B's roster cannot speak for B")
receive("L", { g = "Guilda A", l = { { n = "Bob", m = "falso" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 0, "nobody speaks for our own guild")
receive("L", { g = "Guilda D", l = { { n = "Duda", m = "bloqueado" } } }, "Duda-Realm", "WHISPER")
check(#printed[1] == 0, "a blocked guild is not shown")
receive("L", { g = "Guilda Z", l = { { n = "Eve", m = "fora" } } }, "Eve-Realm", "WHISPER")
check(#printed[1] == 0, "a guild outside the pact is not shown")
receive("L", { g = "Guilda B", l = { { n = "Bob", m = "pelo guild" } } }, "Bob-Realm", "GUILD")
check(#printed[1] == 0, "an L frame counts only as a whisper")
receive("F", { g = "Guilda B", l = { { n = "Bob", m = "sussurro" } } }, "Leo-Realm", "WHISPER")
check(#printed[1] == 0, "an F frame counts only on GUILD")
receive("L", { g = "Guilda C", l = { { n = "Cid-Realm", m = "oi do C" } } }, "Cid-Realm", "WHISPER")
check(#printed[1] == 1 and printed[1][1]:find("[Guilda C]", 1, true), "an ambassador speaks for their guild")

-- ── 4. The GUILD hop ───────────────────────────────────────────────────
reset()
receive("F", { g = "Guilda B", r = "Bob-Realm", l = { { n = "Bea", m = "pelo bridge" } } }, "Leo-Realm", "GUILD")
check(#printed[1] == 1 and #guildSaid == 0 and #whispers == 0, "an F line is shown and never sent on")
handler(AGC.PROTO .. "|F|" .. A.Encode({ g = "Guilda B", l = { { n = "Bea", m = "eco" } } }), "Ana-Realm", "GUILD")
check(#printed[1] == 1, "our own GUILD echo is ignored")

-- ── 5. Ignore, hide, preference ────────────────────────────────────────
reset()
ignored["Bob-Realm"] = true
receive("L", { g = "Guilda B", l = { { n = "Bob-Realm", m = "ignorado" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 0, "an ignored speaker is not shown")
ignored["Bob-Realm"] = nil
GuildOS.db.allianceHidden = { { n = "Bob", m = "oculto" } }
receive("L", { g = "Guilda B", l = { { n = "Bob-Realm", m = "oculto" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 0, "a line the ambassadors hid is not shown")
GuildOS.AllianceChat:Prefs().guildBridge = false
receive("L", { g = "Guilda B", l = { { n = "Bob-Realm", m = "desligado" } } }, "Bob-Realm", "WHISPER")
check(#printed[1] == 0, "the preference off shows nothing")
check(#guildSaid >= 1, "but the rest of the guild still gets it")
GuildOS.AllianceChat:Prefs().guildBridge = true

-- ── 6. Links ───────────────────────────────────────────────────────────
local item = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
local clean = AGC.CleanText("olha " .. item .. " |TInterface\\Icons\\x:0|t |cffff0000vermelho|r")
check(clean:find(item, 1, true), "an item link survives whole")
check(clean:find("||TInterface", 1, true) and clean:find("||cffff0000", 1, true), "a texture and a colour become text")
local retail = "|cnIQ4:|Hitem:1::::::::80:::::|h[Coisa]|h|r"
check(AGC.CleanText(retail) == retail, "a retail quality link survives")
check(AGC.CleanText("|Hurl:x|h[x]|h"):sub(1, 2) == "||", "a link kind outside the list becomes text")
check(not AGC.CleanText("a\nb"):find("\n"), "a line break goes")

-- ── 7. Routes ──────────────────────────────────────────────────────────
reset()
sayInGuild("rota", "Leo-Realm")
runTimers()
local to = {}
for _, w in ipairs(whispers) do to[w.target] = true end
check(to["Bob-Realm"] and to["Cid-Realm"], "who sent us a guild's chat is its route, the older client of C is not used")
GuildOS:OnWhisperNotFound(function() end)   -- the listener list exists
for _, fn in ipairs(GuildOS.State.whispers.gone) do fn("Cid-Realm") end
check(AGC.routes["Guilda C"] == nil, "a route that answered No player named is gone")
NOW = NOW + AGC.ROUTE_TTL + 1
check(AGC:Route("Guilda B") == "Bea", "a stale route falls back to the mesh")

-- ── 8. The Guild tab merges ────────────────────────────────────────────
local merged = GC.Merge({ { t = 1, n = "x" }, { t = 5, n = "y" } }, { { t = 3, n = "z", g = "G" } }, 2)
check(#merged == 2 and merged[1].n == "z" and merged[2].n == "y", "merged by time, newest kept")
local own = { { t = 1 } }
check(GC.Merge(own, {}, 10) == own, "no allied lines hands ours back untouched")

-- ── 9. The data ops take a bridge from the roster, the pact's ops do not ──
local got
A.ops.HEAD = function(_, _, guild) got = guild end
handler = nil
A:OnMessage(A.PROTO .. "|HEAD|" .. A.Encode({ revs = {} }), "Bob-Realm", "WHISPER")
check(got == "Guilda B", "a HEAD from a non-ambassador on B's roster speaks for B")
got = nil
A:OnMessage(A.PROTO .. "|HEAD|" .. A.Encode({ revs = {} }), "Eve-Realm", "WHISPER")
check(got == nil, "a name on a guild outside the pact speaks for nobody")
local pacts = 0
local was = A._OnPact
A._OnPact = function() pacts = pacts + 1 end
A:OnMessage(A.PROTO .. "|PACT|" .. A.Encode({}), "Bob-Realm", "WHISPER")
check(pacts == 0, "a PACT stays with the ambassadors")
A:OnMessage(A.PROTO .. "|PACT|" .. A.Encode({}), "Bia-Realm", "WHISPER")
check(pacts == 1, "and an ambassador still sends it")
A._OnPact = was

-- ── 10. The HELLO says this client takes the chat ──────────────────────
check(GuildOS.Mesh:BuildCaps():find("gosc=1", 1, true), "the caps advertise the chat while in the pact")
local pact = GuildOS.db.alliance
GuildOS.db.alliance = nil
check(not GuildOS.Mesh:BuildCaps():find("gosc", 1, true), "and nothing outside one")
GuildOS.db.alliance = pact

print(("alliance-guild-chat: %d checks passed"):format(checks))
