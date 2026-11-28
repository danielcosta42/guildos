-- The alliance end to end, two guilds at once (#449): every client is the real addon (Core, Compat, Utils,
-- LibDeflate, CompanionExport, CompanionImport, Mesh, Alliance, AllianceChat, GuildChat, AllianceLink, BanList)
-- loaded into an environment of its own, all of them on one fake server: a channel registry with passwords and
-- notices, CHAT_MSG_CHANNEL with each client's channel numbers and the base name, CHAT_MSG_GUILD, the guild's
-- addon messages (SyncService), the roster with the guild master's public note, and timers.
--
-- "Filhos da Horda" and "Ordem do Dragão", each with an officer whose companion brings guildos.me's blocks,
-- members without the companion, a reload and a relog, on TBC Anniversary (cross-realm names) and on WoW: Forever
-- (names with a surname). Walks:
--   (a) the site's code reaches both officers in GOSGILD1, both join the same hidden channel (its name from the key,
--       within the game's limit); members without the companion get the code relayed by an officer and join;
--   (b) the shared /g: a line of A's /g is in B's guild chat tagged with A's real name, never "Allied guild", and
--       back; once, however many of A are online; no echo; a long line, UTF-8 and an item link in parts that the
--       server takes; a chat lockdown costs the crossing and nothing else; a protocol 1 line still reads;
--   (c) the alliance room both ways; (d) a player's shared-/g switch; (e) blocking a guild hides its lines;
--   (f) a key rotation: B removed on the site, A's clients move to the new channel, a B client left in the old one
--       reads nobody of A and is read by nobody;
--   (g) a pasted code, no site: the chat only, guilds named all the same;
--   (h) GOSALLY1's directory and open raids: both guilds named, online counts from the channel;
--   (i) the alliance's bans warn an officer before an invite;
--   (j) a reload and a relog mid-way keep the state; (k) Forever's "First Surname" and a cross-realm "Name-Realm";
--   and a channel the server refuses (wrong password, a refused name, no answer) is said, with its fix, and
--   /gos ally status says what the maintainer needs.
--
--   luajit -e 'ADDON="."' tools/alliance-two-guilds.lua
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

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- ── The world: one server, its clock, its channels ─────────────────────
local W

local function newWorld(flavor)
  W = { t = 1791000000, timers = {}, seq = 0, channels = {}, clients = {}, guilds = {}, lineID = 0,
        flavor = flavor, rejected = 0, policy = { maxLen = 31, pattern = "^[%w]+$" } }
end

local function after(c, delay, fn)
  W.seq = W.seq + 1
  W.timers[#W.timers + 1] = { at = W.t + (tonumber(delay) or 0), fn = fn, c = c, gen = c and c.gen, seq = W.seq }
end

local function run(seconds)
  local target = W.t + seconds
  while true do
    local best, bi
    for i, tm in ipairs(W.timers) do
      if tm.at <= target and (not best or tm.at < best.at or (tm.at == best.at and tm.seq < best.seq)) then
        best, bi = tm, i
      end
    end
    if not best then break end
    table.remove(W.timers, bi)
    if best.at > W.t then W.t = best.at end
    if not best.c or (best.c.online and best.c.gen == best.gen) then best.fn() end
  end
  W.t = target
end

local function fire(c, event, ...)
  for _, f in ipairs(c.frames) do
    if f.events[event] and f.fn then f.fn(f, event, ...) end
  end
end

-- What a chat frame would print of a channel line: the frame lists the channel and no filter hides it.
local function display(c, event, ...)
  local args = { ... }
  for _, fn in ipairs(c.filters[event] or {}) do
    if fn(c.env.ChatFrame1, event, unpack(args, 1, 12)) == true then return end
  end
  c.raw[#c.raw + 1] = { event = event, msg = args[1], base = args[9] }
end

local function guildOf(c) return W.guilds[c.guild] end

local function online(guildName)
  local out = {}
  for _, m in ipairs(W.guilds[guildName].roster) do if m.online then out[#out + 1] = m end end
  return out
end

-- The server's own check of a chat line: within 255 bytes, every link whole.
local function serverTakes(msg)
  if #msg > 255 then return false end
  local stripped = msg:gsub("|c%x%x%x%x%x%x%x%x|H[^|]+|h%[[^|%]]+%]|h|r", "")
  return not stripped:find("|H", 1, true) and not stripped:find("|h", 1, true)
end

local function channelNotice(c, kind, name, idx)
  local str = idx and (idx .. ". " .. name) or name
  fire(c, "CHAT_MSG_CHANNEL_NOTICE", kind, "", "", str, "", "", 0, idx or 0, name)
  display(c, "CHAT_MSG_CHANNEL_NOTICE", kind, "", "", str, "", "", 0, idx or 0, name)
end

local function serverJoin(c, name, password)
  local lower = name:lower()
  if W.policy.drop then return end
  if #name > W.policy.maxLen or not name:match(W.policy.pattern) then
    return channelNotice(c, "INVALID_NAME", name)
  end
  local ch = W.channels[lower]
  if ch and ch.members[c] then return end
  if ch and ch.pass ~= password then
    return channelNotice(c, "WRONG_PASSWORD", name)
  end
  if not ch then
    ch = { name = name, pass = password, members = {} }
    W.channels[lower] = ch
  end
  ch.members[c] = true
  local idx = 3
  while c.chans[idx] do idx = idx + 1 end
  c.chans[idx] = ch.name
  -- The game lists a joined channel in the first chat frame.
  table.insert(c.frameChannels[1], ch.name)
  table.insert(c.frameChannels[1], 0)
  channelNotice(c, "YOU_JOINED", ch.name, idx)
  for m in pairs(ch.members) do
    if m ~= c and m.env then fire(m, "CHAT_MSG_CHANNEL_JOIN", "", c.wire, "", "", "", "", 0, 0, ch.name) end
  end
  fire(c, "CHANNEL_UI_UPDATE")
end

local function serverLeave(c, name)
  local lower = tostring(name):lower()
  local ch = W.channels[lower]
  if not ch or not ch.members[c] then return end
  ch.members[c] = nil
  for idx, n in pairs(c.chans) do if n:lower() == lower then c.chans[idx] = nil end end
  for m in pairs(ch.members) do
    if m.env then fire(m, "CHAT_MSG_CHANNEL_LEAVE", "", c.wire, "", "", "", "", 0, 0, ch.name) end
  end
  if next(ch.members) == nil then W.channels[lower] = nil end
end

local function inChannel(c, name)
  local ch = W.channels[tostring(name):lower()]
  return ch ~= nil and ch.members[c] == true
end

local function channelSay(c, msg, idx)
  local name = c.chans[idx]
  local ch = name and W.channels[name:lower()]
  if not ch or not ch.members[c] then return end
  if not serverTakes(msg) then W.rejected = W.rejected + 1; return end
  W.lineID = W.lineID + 1
  for m in pairs(ch.members) do
    local mi
    for i, n in pairs(m.chans) do if n:lower() == name:lower() then mi = i end end
    local args = { msg, c.wire, "", mi .. ". " .. ch.name, "", "", 0, mi, ch.name, 0, W.lineID, c.guid }
    fire(m, "CHAT_MSG_CHANNEL", unpack(args, 1, 12))
    display(m, "CHAT_MSG_CHANNEL", unpack(args, 1, 12))
  end
end

local function guildSay(c, msg)
  W.lineID = W.lineID + 1
  for _, m in ipairs(online(c.guild)) do
    fire(m, "CHAT_MSG_GUILD", msg, c.wire, "", "", "", "", 0, 0, "", 0, W.lineID, c.guid)
    for i = 1, 2 do
      local f = m.env["ChatFrame" .. i]
      if f.shows then m.env.ChatFrame_MessageEventHandler(f, "CHAT_MSG_GUILD", msg, c.wire) end
    end
  end
end

-- ── A client: the real addon in an environment of its own ───────────────
local FILES = {
  "Core/Core.lua", "Core/Compat.lua", "Core/Utils.lua", "Libs/LibDeflate.lua",
  "Modules/CompanionExport.lua", "Modules/CompanionImport.lua", "Modules/Mesh.lua",
  "Modules/Alliance.lua", "Modules/AllianceChat.lua", "Modules/GuildChat.lua", "Modules/AllianceLink.lua",
  "Modules/BanList.lua",
}
local CHUNKS = {}
for _, path in ipairs(FILES) do CHUNKS[path] = assert(loadfile(ADDON .. "/" .. path)) end

local function ambiguate(name, how)
  name = tostring(name or "")
  if how == "short" then return (name:gsub("%-.*$", "")) end
  return name
end

local function makeEnv(c)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  local forever = W.flavor == "forever"
  if forever then
    env.GetBuildInfo = function() return "1.60.1", "70790", "", 16001 end
    env.WOW_PROJECT_ID = 99
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    env.GetBuildInfo = function() return "2.5.5", "60000", "", 20505 end
    env.WOW_PROJECT_ID = 5
  end
  env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, env.WOW_PROJECT_MAINLINE = 5, 1
  env.GetServerTime = function() return W.t end
  env.GetTime = function() return W.t end
  env.time = function() return W.t end
  env.date = os.date
  env.debugstack = function() return "" end
  env.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  env.strsplit = function(sep, s, n)
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
  env.tinsert, env.tremove, env.format = table.insert, table.remove, string.format
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.Ambiguate = ambiguate
  env.UnitName = function() return c.name end
  env.UnitFullName = function() return c.name, forever and c.surname or c.realm end
  env.GetRealmName = function() return c.realm end
  env.GetNormalizedRealmName = function() return (c.realm:gsub("%s", "")) end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return c.guild, "Rank", c.rank, nil end
  local function roster() return guildOf(c).roster end
  env.GetNumGuildMembers = function() return #roster() end
  env.GetGuildRosterInfo = function(i)
    local m = roster()[i]
    if not m then return nil end
    return m.full, "Rank", m.rank, 60, "Mage", "Zone", guildOf(c).notes[m.full] or "", "", m.online, 0, "MAGE",
      0, 0, false, false, 0, m.guid
  end
  env.CanEditPublicNote = function() return c.rank <= 1 end
  env.GuildRosterSetPublicNote = function(i, note)
    local m = roster()[i]
    if not m then return end
    guildOf(c).notes[m.full] = note
    for _, o in ipairs(online(c.guild)) do after(o, 0.5, function() fire(o, "GUILD_ROSTER_UPDATE") end) end
  end
  env.GetPlayerInfoByGUID = function() return "Mage", "MAGE" end
  env.issecretvalue = nil
  -- Chat: frames, the edit box, filters.
  env.NUM_CHAT_WINDOWS = 2
  env.CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: "
  env.ChatFrame1 = { shows = true, AddMessage = function() end }
  env.ChatFrame2 = { shows = false, AddMessage = function() end }
  env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  env.ChatFrame_ContainsMessageGroup = function(f, group) return group == "GUILD" and f.shows end
  env.ChatFrame_MessageEventHandler = function(frame, event, msg, author)
    if frame == env.ChatFrame1 and event == "CHAT_MSG_GUILD" then
      c.gchat[#c.gchat + 1] = { msg = msg, author = author }
    end
    return true
  end
  env.ChatFrame_AddMessageEventFilter = function(event, fn)
    c.filters[event] = c.filters[event] or {}
    table.insert(c.filters[event], fn)
  end
  env.GetChatWindowChannels = function(i) return unpack(c.frameChannels[i] or {}) end
  env.ChatFrame_RemoveChannel = function(_, name)
    local list = c.frameChannels[1]
    for j = #list - 1, 1, -2 do if list[j] == name then table.remove(list, j + 1); table.remove(list, j) end end
  end
  local box = { attrs = {}, text = "" }
  function box:GetAttribute(k) return self.attrs[k] end
  function box:GetText() return self.text end
  function box:ParseText() end
  env.ChatFrame1EditBox = box
  c.box = box
  env.hooksecurefunc = function(a, b, fn)
    if type(a) == "table" then
      local orig = a[b]
      a[b] = function(...) local r = orig(...); fn(...); return r end
    end
  end
  env.C_FriendList = { IsIgnored = function(name) return c.ignored[name] == true end }
  env.C_ChatInfo = { InChatMessagingLockdown = function() return c.lockdown == true end }
  env.SendChatMessage = function(msg, chatType, _, target)
    if chatType == "CHANNEL" then channelSay(c, msg, target)
    elseif chatType == "GUILD" then guildSay(c, msg) end
  end
  env.JoinTemporaryChannel = function(name, password)
    c.joins = (c.joins or 0) + 1
    after(c, 0.3, function() serverJoin(c, name, password) end)
  end
  env.LeaveChannelByName = function(name)
    c.left[#c.left + 1] = name
    serverLeave(c, name)
  end
  env.GetChannelName = function(id)
    if type(id) == "number" then
      local n = c.chans[id]
      if n then return id, n end
      return 0
    end
    for idx, n in pairs(c.chans) do if n:lower() == tostring(id):lower() then return idx, n end end
    return 0
  end
  env.C_Timer = {
    After = function(delay, fn) after(c, delay, fn) end,
    NewTicker = function(every, fn)
      local t = { cancelled = false }
      local function arm() after(c, every, function() if not t.cancelled then fn(); arm() end end) end
      arm()
      function t:Cancel() self.cancelled = true end
      return t
    end,
  }
  env.CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(_, fn) self.fn = fn end
    function f:HookScript() end
    c.frames[#c.frames + 1] = f
    return f
  end
  env.Enum = { SendAddonMessageResult = {} }
  local registry = {}
  env.LibStub = setmetatable({
    NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
    GetLibrary = function(_, name) return registry[name] end,
  }, { __call = function(_, name) return registry[name] end })
  -- The presence mesh: every online client running GuildOS with the mesh on, by its short name.
  env.ChehulNet = { Peers = function()
    local out = {}
    for _, o in ipairs(W.clients) do
      if o ~= c and o.online and o.mesh and o.env and o.env.GuildOS.Mesh then
        out[ambiguate(o.wire, "short")] = { caps = o.env.GuildOS.Mesh:BuildCaps() }
      end
    end
    return out
  end }
  env.GuildOSInbox = c.inbox
  env.GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "1.44.0",
                  SelfTest = { Register = function() end } }
  return env
end

local function login(c, keepChannels)
  c.gen = (c.gen or 0) + 1
  c.online = true
  c.frames, c.filters = {}, {}
  c.gchat, c.raw, c.printed, c.left, c.dialogs = c.gchat or {}, {}, {}, {}, {}
  c.frameChannels = { {}, {} }
  if not keepChannels then
    for _, ch in pairs(W.channels) do if ch.members[c] then serverLeave(c, ch.name) end end
    c.chans = {}
  else
    for _, n in pairs(c.chans) do table.insert(c.frameChannels[1], n); table.insert(c.frameChannels[1], 0) end
  end
  local env = makeEnv(c)
  c.env = env
  for _, path in ipairs(FILES) do
    setfenv(CHUNKS[path], env)
    CHUNKS[path]()
  end
  local G = env.GuildOS
  G.State = G.State or {}
  G.State.errors = G.State.errors or {}
  G.State.coalesce = G.State.coalesce or { at = {}, waiting = {} }
  G.isGuilded = true
  c.db.settings = c.db.settings or {}
  c.db.settings.companion = c.companion and true or nil
  c.db.members = c.db.members or {}
  G.db = c.db
  G.Print = function(_, msg) c.printed[#c.printed + 1] = tostring(msg) end
  G.ShowDialog = function(_, which, text, _, data) c.dialogs[#c.dialogs + 1] = { which = which, text = text, data = data } end
  c.sync = {}
  G.SyncService = {
    On = function(_, dom, fn) c.sync[dom] = fn end,
    Publish = function(_, dom, act, data)
      c.published[#c.published + 1] = { dom = dom, act = act, data = copy(data) }
      local env2 = { act = act, data = copy(data) }
      for _, o in ipairs(online(c.guild)) do
        if o ~= c then
          after(o, 0.2, function() if o.sync[dom] then o.sync[dom](copy(env2), c.sender) end end)
        end
      end
    end,
  }
  G.Alliance:Initialize()
  G.AllianceChat:Initialize()
  G.AllianceLink:Initialize()
  fire(c, "PLAYER_ENTERING_WORLD")
  fire(c, "GUILD_ROSTER_UPDATE")
  return G
end

local function logout(c)
  c.online = false
  for _, ch in pairs(W.channels) do if ch.members[c] then serverLeave(c, ch.name) end end
  c.chans = {}
end

-- A /reload: the client keeps its channels on the server, the addon starts over with the same SavedVariables.
local function reload(c) return login(c, true) end

local function newClient(o)
  local forever = W.flavor == "forever"
  local c = {
    id = o.id, name = o.name, surname = o.surname, realm = o.realm or (forever and "Forever" or "Realm"),
    guild = o.guild, rank = o.rank or 4, companion = o.companion, inbox = o.inbox or {}, db = {}, ignored = {},
    published = {}, mesh = o.mesh, chans = {},
  }
  if forever then
    c.full, c.wire = c.name .. " " .. c.surname, c.name .. "-" .. c.surname
  else
    c.full, c.wire = c.name .. "-" .. c.realm, c.name .. "-" .. c.realm
  end
  c.sender = c.wire
  c.guid = "Player-1-" .. o.id
  local g = W.guilds[o.guild]
  if not g then
    g = { name = o.guild, roster = {}, notes = {} }
    W.guilds[o.guild] = g
  end
  c.full_ = c.full
  table.insert(g.roster, c)
  c.rank = o.rank or 4
  W.clients[#W.clients + 1] = c
  return c
end

-- The player types a line of /g and presses Enter: the game's ParseText (post-hooked), then its own send.
local function typeGuild(c, text)
  c.box.attrs.chatType, c.box.text = "GUILD", text
  c.box:ParseText(1)
  guildSay(c, text)
end

local function G(c) return c.env.GuildOS end
local function errorsOf(c) return G(c).State.errors end
local function noErrors(c, what)
  local e = errorsOf(c)
  check(#e == 0, (what or "no errors") .. " on " .. c.id .. (e[1] and (": " .. e[1].msg) or ""))
end

-- The guild lines a client's first chat frame shows since `from`, as { msg, author }.
local function gsince(c, from) local out = {} for i = from + 1, #c.gchat do out[#out + 1] = c.gchat[i] end return out end

-- ── The site's blocks, made as the site's encoder makes them ───────────
local TOOL
local function pack(fmt, t)
  if not TOOL then
    newWorld("anniversary")
    local tc = newClient({ id = "tool", name = "Tool", guild = "Tool" })
    login(tc)
    TOOL = tc.env
  end
  local LD = TOOL.LibStub("LibDeflate")
  return fmt .. ":" .. LD:EncodeForPrint(LD:CompressDeflate(TOOL.GuildOS.Companion.EncodeJson(t)))
end

local GA, GB = "Filhos da Horda", "Ordem do Dragão"
local KEY1, KEY2 = "Kx7Pq2Lm9Z", "Rt5Yu8Io1P"
local CODE1, CODE2 = "GOS=FDH:" .. KEY1, "GOS=FDH:" .. KEY2
local ALLY_NAME = "Pacto da Horda"

local function gild(guild, alliance, bans)
  return pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = guild, at = W.t - 3600, alliance = alliance,
                            allianceBans = bans })
end

local function ally(guild, version, members, raids)
  local guilds = {}
  for _, g in ipairs({ GA, GB }) do
    if g == guild then
      guilds[#guilds + 1] = { name = g, self = true, via = g == GA and "founder" or "invite", members = {} }
    else
      guilds[#guilds + 1] = { name = g, via = g == GA and "founder" or "invite", members = members[g] or {} }
    end
  end
  return pack("GOSALLY1", { fmt = "GOSALLY1", v = 1, guild = guild, at = W.t - 3600,
                            alliance = { name = ALLY_NAME, tag = "FDH", version = version },
                            guilds = guilds, raids = raids or {} })
end

-- ════════════════════════════════════════════════════════════════════════
-- I. TBC Anniversary: the site's alliance, two guilds
-- ════════════════════════════════════════════════════════════════════════
pack("GOSGILD1", {})   -- the tool client, before the world
newWorld("anniversary")
local MEMBERS = {
  [GA] = { { key = "Ana-Realm", name = "Ana", class = "MAGE", level = 70 },
           { key = "Duda-Realm", name = "Duda", class = "PRIEST", level = 70 } },
  [GB] = { { key = "Bia-Realm", name = "Bia", class = "WARRIOR", level = 70, role = "TANK" },
           { key = "Caio-Realm", name = "Caio", class = "ROGUE", level = 68 },
           { key = "Bob-Outro", name = "Bob", class = "HUNTER", level = 70 } },
}
local RAIDS = { { id = "r1", guild = GB, title = "Karazhan", where = "Karazhan", startsAt = W.t + 86400, size = 10,
                  lead = "Bia-Realm", going = 7 } }
local BANS = { { id = "b1", key = "Trapaceiro-Realm", name = "Trapaceiro", guild = GB, reason = "scam", at = W.t - 100 } }

-- The leader turned everything on (GOSGILD1.alliance.share, site spec 123).
local ALL_ON = {}
for _, item in ipairs({ "chat", "room", "raids", "directory", "crafters", "bans", "map" }) do
  ALL_ON[item] = { send = true, recv = true }
end
local site1 = { code = CODE1, name = ALLY_NAME, version = 1, share = ALL_ON }
local aGM  = newClient({ id = "aGM",  name = "Ana",  guild = GA, rank = 0, companion = true,
                         inbox = { gild(GA, site1, BANS), ally(GA, 1, MEMBERS, RAIDS) } })
local aMem = newClient({ id = "aMem", name = "Duda", guild = GA, rank = 4 })
local aAlt = newClient({ id = "aAlt", name = "Edu",  guild = GA, rank = 4 })
local bOff = newClient({ id = "bOff", name = "Bia",  guild = GB, rank = 1, companion = true,
                         inbox = { gild(GB, site1), ally(GB, 1, MEMBERS, RAIDS) } })
local bMem = newClient({ id = "bMem", name = "Caio", guild = GB, rank = 4 })
-- A cross-realm member of B whose name is also an A member's on another realm: "Ana-Outro".
local bX   = newClient({ id = "bX",   name = "Ana", realm = "Outro", guild = GB, rank = 4 })

for _, c in ipairs({ aGM, aMem, aAlt, bOff, bMem, bX }) do login(c) end
run(60)

-- (a) The site's code, the channel from the key, the relay to members without the companion.
local CH1 = G(aGM).AllianceLink.ChannelNameFor("FDH", KEY1)
check(#CH1 <= 31 and CH1:match("^[%w]+$") and CH1:sub(1, 7) == "GOSAFDH", "(a) the channel's name comes from the key, within the game's limit: " .. CH1)
for _, c in ipairs({ aGM, bOff }) do
  check(G(c).Alliance:FromSite() and G(c).AllianceLink:Source() == "site", "(a) " .. c.id .. " reads the site's code itself")
end
for _, c in ipairs({ aMem, aAlt, bMem, bX }) do
  check(G(c).Alliance:FromSite() and G(c).AllianceLink:Source() == "relay", "(a) " .. c.id .. " has it from an officer's relay")
end
for _, c in ipairs({ aGM, aMem, aAlt, bOff, bMem, bX }) do
  check(inChannel(c, CH1), "(a) " .. c.id .. " is in the alliance channel")
  check(G(c).AllianceChat:State() == "joined", "(a) " .. c.id .. "'s room says joined")
  check(G(c).Alliance:Name() == ALLY_NAME, "(a) " .. c.id .. " names the alliance")
end
for _, c in ipairs({ aGM, bOff }) do
  local sent = 0
  for _, p in ipairs(c.published) do if p.dom == "allylink" and p.act == "site" then sent = sent + 1 end end
  check(sent >= 1, "(a) " .. c.id .. " relays the site's code to the guild")
end
check(#aMem.raw == 0 and #bMem.raw == 0, "(a) the hidden channel's notices never print")
check(#aMem.frameChannels[1] == 0, "(a) the channel is taken out of the chat frames")
for _, c in ipairs({ aGM, aMem, aAlt, bOff, bMem, bX }) do noErrors(c, "(a)") end

-- (b) The shared /g, both ways, named.
local function marks() local m = {} for _, c in ipairs(W.clients) do m[c] = #(c.gchat or {}) end return m end
local m0 = marks()
typeGuild(aMem, "oi pessoal da ordem")
for _, c in ipairs({ bOff, bMem, bX }) do
  local got = gsince(c, m0[c])
  check(#got == 1, "(b) " .. c.id .. " sees A's line once, got " .. #got)
  check(got[1] and got[1].msg:find("[" .. GA .. "]", 1, true) and got[1].msg:find("oi pessoal da ordem", 1, true),
    "(b) tagged with A's real name: " .. tostring(got[1] and got[1].msg))
  check(not got[1].msg:find("Allied guild", 1, true), "(b) never \"Allied guild\"")
  check(got[1].author == "Duda-Realm", "(b) the speaker is the channel's sender")
end
for _, c in ipairs({ aGM, aMem, aAlt }) do
  local got = gsince(c, m0[c])
  check(#got == 1 and got[1].msg == "oi pessoal da ordem", "(b) " .. c.id .. " sees its own guild's /g once, as the game drew it")
end
m0 = marks()
typeGuild(bMem, "olá, filhos! ação às 20h")
for _, c in ipairs({ aGM, aMem, aAlt }) do
  local got = gsince(c, m0[c])
  check(#got == 1 and got[1].msg:find("[" .. GB .. "]", 1, true), "(b) " .. c.id .. " sees B's line tagged with B's UTF-8 name")
end
check(#gsince(bX, m0[bX]) == 1 and #gsince(bOff, m0[bOff]) == 1, "(b) B's own see it once")
-- No echo: one line said, one line on the channel.
local before = W.lineID
typeGuild(aAlt, "sem eco")
check(W.lineID - before == 2, "(b) one guild line and one channel line, no echo back")

-- A long line in UTF-8 with an item link where the cut would fall: the server takes every part, the link whole.
local LINK = "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r"
local long = string.rep("ação ", 25) .. LINK .. " fim"
check(#long > 230 and #long <= 255, "(b) the long line is near the game's 255")
local rej = W.rejected
m0 = marks()
typeGuild(aMem, long)
check(W.rejected == rej, "(b) the server took every part of the long line")
local got = gsince(bOff, m0[bOff])
check(#got == 2, "(b) a long line crosses in two parts, got " .. #got)
local joined = (got[1] and got[1].msg:gsub("^|cff%x+%[[^%]]+%]|r ", "") or "") .. " "
  .. (got[2] and got[2].msg:gsub("^|cff%x+%[[^%]]+%]|r ", "") or "")
check(joined:gsub("%s+", " ") == long:gsub("%s+", " "), "(b) and reads whole, the link intact")
check(got[2] and got[2].msg:find(LINK, 1, true), "(b) the item link is whole in its part")
for _, p in ipairs(got) do check(not p.msg:find("\195$") and not p.msg:find("[\192-\255]$"), "(b) no part ends in half a letter") end
local Link = G(aMem).AllianceLink
-- The channel's rate: one key press says at most MAX_PARTS lines, however long the text.
check(#Link.Split("G", "abc", string.rep("palavra ", 120), GA) == Link.MAX_PARTS, "(b) at most MAX_PARTS lines a key press")
for _, p in ipairs(Link.Split("G", "abc", string.rep("ção", 200), GB)) do
  check(#p <= 255 and select(4, Link.Decode(p)) == GB, "(b) every part within 255 bytes, each naming its guild")
end
-- A link of a protocol 2 frame at the very cut: LinkSafeCut moves it.
local s = string.rep("a", 10) .. LINK
check(Link.LinkSafeCut(s, 20) == 10 and Link.LinkSafeCut(s, 5) == 5 and Link.LinkSafeCut(s, #s) == #s,
  "(b) a cut inside a link goes before it")

-- A chat lockdown (combat on Forever): the game's own /g goes, the crossing does not, nothing errors.
aMem.lockdown = true
m0 = marks()
typeGuild(aMem, "em combate")
check(#gsince(bOff, m0[bOff]) == 0 and #gsince(aGM, m0[aGM]) == 1, "(b) in a lockdown /g goes, the crossing does not")
check((G(aMem).AllianceLink.stats.unsent or 0) >= 1, "(b) and the status counts it")
aMem.lockdown = false
noErrors(aMem, "(b) lockdown")

-- A protocol 1 line (a client from before #449) still reads: A's code is a guild heard before.
local before1 = #bOff.gchat
channelSay(aAlt, "G" .. Link.Code(GA) .. " linha antiga", aAlt.env.GetChannelName(CH1))
got = gsince(bOff, before1)
check(#got == 1 and got[1].msg:find("[" .. GA .. "]", 1, true) and got[1].msg:find("linha antiga", 1, true),
  "(b) a protocol 1 line is still read, named by the guilds heard")
-- A line whose name is not its code's is not believed: named by the code.
before1 = #bOff.gchat
channelSay(aAlt, "g" .. Link.Code(GA) .. " Guilda Falsa# mentira", aAlt.env.GetChannelName(CH1))
got = gsince(bOff, before1)
check(#got == 1 and got[1].msg:find("[" .. GA .. "]", 1, true) and not got[1].msg:find("Falsa", 1, true),
  "(b) a guild name that does not hash to the line's code is not believed")
-- Decode of both protocols, and a guild name that cannot ride the wire.
local k, code, text, said, proto = Link.Decode(Link.Encode("G", "abc", "oi", "Filhos da Horda"))
check(k == "G" and code == "abc" and text == "oi" and said == "Filhos da Horda" and proto == 2, "(b) protocol 2 round-trips")
k, code, text, said, proto = Link.Decode("Aabc oi gente")
check(k == "A" and text == "oi gente" and said == nil and proto == 1, "(b) protocol 1 decodes")
check(Link.Decode(Link.Encode("G", "abc", "oi", "Guild#Hash")):match("^G") and select(5, Link.Decode(Link.Encode("G", "abc", "oi", "Guild#Hash"))) == 1,
  "(b) a name with # falls back to protocol 1")

-- (c) The alliance room both ways.
local function roomSince(c, from) local out = {} local log = G(c).AllianceChat:Log() for i = from + 1, #log do out[#out + 1] = log[i] end return out end
local function rooms() local m = {} for _, c in ipairs(W.clients) do if c.env then m[c] = #G(c).AllianceChat:Log() end end return m end
local r0 = rooms()
check(G(aMem).AllianceChat:Send("bora raide? " .. LINK), "(c) A's member speaks in the room")
for _, c in ipairs({ bOff, bMem, bX, aGM, aAlt, aMem }) do
  local l = roomSince(c, r0[c])
  check(#l == 1 and l[1].g == GA and l[1].n == (c.realm == "Realm" and "Duda" or "Duda-Realm") and l[1].m:find(LINK, 1, true),
    "(c) " .. c.id .. " has the room line once, from A, the link whole: " .. #l .. " " .. tostring(l[1] and l[1].n) .. " " .. tostring(l[1] and l[1].m))
end
r0 = rooms()
check(G(bX).AllianceChat:Send("eu vou"), "(c) B's cross-realm member answers")
for _, c in ipairs({ aGM, aMem }) do
  local l = roomSince(c, r0[c])
  check(#l == 1 and l[1].g == GB and l[1].n == "Ana-Outro", "(c) " .. c.id .. " has it, the speaker with their realm: " .. tostring(l[1] and l[1].n))
end
-- (k) Ana-Outro is not Ana-Realm: aGM (Ana of Realm) does not take her line for its own echo.
check(#roomSince(aGM, r0[aGM]) == 1, "(k) a namesake on another realm is not the player")
check(#roomSince(bX, r0[bX]) == 1, "(c) the speaker's own line once (no echo)")

-- (d) The shared /g switch is each player's.
G(bMem).Alliance:HandleCommand("gchat off")
check(bMem.printed[#bMem.printed]:find("Allied /g: hidden", 1, true), "(d) /gos ally gchat off says so")
m0 = marks()
typeGuild(aMem, "só para quem quer")
check(#gsince(bMem, m0[bMem]) == 0 and #gsince(bOff, m0[bOff]) == 1, "(d) off on one player hides it there only")
r0 = rooms()
G(aMem).AllianceChat:Send("sala continua")
check(#roomSince(bMem, r0[bMem]) == 1, "(d) the room is not the shared /g's switch")
m0 = marks()
typeGuild(bMem, "eu ainda falo")
check(#gsince(aMem, m0[aMem]) == 1, "(d) a player with it off still reaches the allies")
G(bMem).Alliance:HandleCommand("gchat on")

-- (e) Blocking a guild hides its lines, typed as the officer reads it.
local ok = G(aGM).Alliance:Block("ordem do dragão")
check(ok, "(e) an officer blocks B")
m0, r0 = marks(), rooms()
typeGuild(bMem, "bloqueado?")
G(bMem).AllianceChat:Send("e aqui?")
check(#gsince(aGM, m0[aGM]) == 0 and #roomSince(aGM, r0[aGM]) == 0, "(e) its /g and room lines are hidden, capitals aside")
check(#gsince(aMem, m0[aMem]) == 1, "(e) on that account only")
check(select(1, G(aMem).Alliance:Block(GB)) == false, "(e) a member cannot block")
G(aGM).Alliance:Unblock("ordem do dragão")
m0 = marks()
typeGuild(bMem, "voltei")
check(#gsince(aGM, m0[aGM]) == 1, "(e) unblocked, it shows again")

-- (h) GOSALLY1: both guilds named, the directory and raids at the officers', online counts from the channel.
local gs = G(aGM).Alliance:Guilds()
check(#gs == 2 and gs[1].name == GA and gs[1].mine and gs[2].name == GB, "(h) Salão › Alliance names both guilds")
check(gs[2].online >= 2, "(h) B's speakers heard on the channel count as online: " .. tostring(gs[2].online))
check(#G(aGM).Alliance:Directory() == 1 and G(aGM).Alliance:Directory()[1].guild == GB, "(h) the directory: the allied guild")
local raids = G(aGM).Alliance:OpenRaids()
check(#raids == 1 and raids[1].guild == GB and raids[1].title == "Karazhan" and raids[1].leader == "Bia", "(h) B's open raid reaches A")
local gm = G(aMem).Alliance:Guilds()
check(#gm == 2 and gm[2].name == GB, "(h) a member without the companion names both guilds from the channel")
local on = G(aMem).Alliance:OnlineNow()
local names = {}
for _, p in ipairs(on) do names[#names + 1] = p.name .. "@" .. p.guild end
check(table.concat(names, ","):find("Ana%-Outro@" .. GB) and table.concat(names, ","):find("Caio@" .. GB),
  "(h, k) who is on now, cross-realm with the realm: " .. table.concat(names, ","))
-- A guild's name in UTF-8 longer than 24 bytes is kept whole: cut, it would hash to another code.
local RU = "Орден Серебряной Длани"
G(aMem).AllianceLink:Heard(RU)
check(G(aMem).AllianceLink:GuildOfCode(G(aMem).AllianceLink.Code(RU)) == RU, "(h) a long UTF-8 guild name is heard whole")
-- (status) /gos ally status says what the maintainer needs, never the key.
local pm = #aMem.printed
G(aMem).Alliance:HandleCommand("status")
local status = table.concat(aMem.printed, "\n", pm + 1)
check(status:find(CH1, 1, true) and status:find("joined: yes", 1, true) and status:find("source: relay", 1, true)
  and status:find("key version: 1", 1, true) and status:find("protocol 2", 1, true), "(status) channel, joined, source, version")
check(status:find(GB .. ": last", 1, true), "(status) the last line of each guild heard")
check(not status:find(KEY1, 1, true), "(status) never the key")

-- (i) The alliance's bans warn an officer before an invite.
local BL = G(aGM).BanList
check(BL:AllianceBansFor("Trapaceiro") ~= nil, "(i) the officer holds B's ban")
local invited = false
check(BL:HoldInvite("Trapaceiro", function() invited = true end) and aGM.dialogs[#aGM.dialogs].which == "GUILDOS_ALLIANCE_BAN_INVITE"
  and aGM.dialogs[#aGM.dialogs].text:find(GB, 1, true) and not invited, "(i) an invite asks first, naming the guild")
check(G(aMem).BanList:AllianceBansFor("Trapaceiro") == nil, "(i) a member's client holds none")

-- (j) A reload keeps the channel and the state; a relog joins again.
reload(aMem)
check(inChannel(aMem, CH1) and G(aMem).AllianceLink:Source() == "relay" and G(aMem).AllianceChat:State() == "joined",
  "(j) after a reload: the same channel, the relayed code")
m0 = marks()
typeGuild(aMem, "depois do reload")
check(#gsince(bOff, m0[bOff]) == 1, "(j) and the shared /g works at once")
local function onNow(c, who)
  for _, p in ipairs(G(c).Alliance:OnlineNow()) do if p.name == who then return true end end
  return false
end
check(onNow(aGM, "Caio"), "(h) Caio is on now at A's officer")
logout(bMem)
check(not inChannel(bMem, CH1), "(j) a logout leaves the channel")
check(not onNow(aGM, "Caio"), "(h) and is no longer on now: the channel said they left")
login(bMem)
run(40)
check(onNow(aGM, "Caio"), "(h) a member the directory names is on now when they join, before a word")
check(inChannel(bMem, CH1) and G(bMem).Alliance:FromSite(), "(j) a relog joins again with the code it kept")
m0 = marks()
typeGuild(aGM, "bem-vindo de volta")
check(#gsince(bMem, m0[bMem]) == 1, "(j) and reads A")
for _, c in ipairs({ aGM, aMem, aAlt, bOff, bMem, bX }) do noErrors(c, "(j)") end

-- A channel the server refuses: said with its fix.
local function ghost(c) c.online, c.gen, c.frames, c.filters, c.frameChannels, c.raw = true, 1, {}, {}, { {}, {} }, {} end
local squat = newClient({ id = "squat", name = "Zed", guild = "Outra", rank = 4 })
ghost(squat)
local CHX = G(aGM).AllianceLink.ChannelNameFor("ZZZ", "Qq1Ww2Ee3R")
serverJoin(squat, CHX, "outra-senha")
local fail = newClient({ id = "fail", name = "Fil", guild = "Guilda Teste", rank = 1 })
login(fail)
run(5)
check(G(fail).AllianceLink:SetCode("GOS=ZZZ:Qq1Ww2Ee3R"), "a pasted code")
run(5)
run(25)
local st, err = G(fail).AllianceChat:State()
check(st == "failed" and err and err.reason == "WRONG_PASSWORD", "a channel already keyed otherwise is a WRONG_PASSWORD: " .. tostring(st))
check(G(fail).AllianceLink.JoinErrorText(err):find("same code", 1, true), "said with its fix")
check(#fail.raw == 0, "the server's notice for our channel is hidden from the chat frames")
G(fail).Alliance:HandleCommand("status")
check(table.concat(fail.printed, "\n"):find("refused: WRONG_PASSWORD", 1, true), "/gos ally status says the refusal")
-- A refusal is not asked again on its own (the join loop): no join from the watchdog, the channel list's events or a
-- login while it stands, and it is said once in the chat frame.
local function saidJoinHint(c)
  local n = 0
  for _, line in ipairs(c.printed) do if line:find("/gos ally join to try again", 1, true) then n = n + 1 end end
  return n
end
check(saidJoinHint(fail) == 1, "the refusal is said once, with how to ask again")
local j0 = fail.joins
for _ = 1, 5 do fire(fail, "CHANNEL_UI_UPDATE") end
run(300)
check(fail.joins == j0, "five minutes of watchdog and channel events ask the refused channel nothing: " .. (fail.joins - j0))
check(saidJoinHint(fail) == 1, "and the chat frame hears it once")
check(G(fail).AllianceChat:State() == "failed", "the screens still say it failed")
G(fail).Alliance:HandleCommand("join")
run(5)
check(fail.joins == j0 + 1, "/gos ally join asks once more")
check(saidJoinHint(fail) == 2 and G(fail).AllianceLink:Refused(), "and the server's answer to it is said once more")
run(300)
check(fail.joins == j0 + 1, "then nothing again on its own")
W.policy.maxLen = 12
G(fail).AllianceLink._joinError = nil
G(fail).AllianceLink:SetCode("GOS=ZZY:Qq1Ww2Ee3R")
run(25)
st, err = G(fail).AllianceChat:State()
check(st == "failed" and err.reason == "INVALID_NAME" and G(fail).AllianceLink.JoinErrorText(err):find("shorter tag", 1, true),
  "a name the server refuses is INVALID_NAME, with the fix")
W.policy.maxLen, W.policy.drop = 31, true
G(fail).AllianceLink:SetCode("GOS=ZZW:Qq1Ww2Ee3R")
G(fail).AllianceLink._joinError = nil
j0 = fail.joins
local hints = saidJoinHint(fail)
check(hints == 3, "the bad name was a refusal too, said once: " .. hints)
for _ = 1, 20 do fire(fail, "CHANNEL_UI_UPDATE"); G(fail).AllianceChat:EnsureJoined() end
check(fail.joins - j0 <= 1, "a burst of channel events and watchdog calls is one join: " .. (fail.joins - j0))
run(90)
st, err = G(fail).AllianceChat:State()
check(st == "failed" and err.reason == "NO_ANSWER", "joins that go unanswered are said after a few tries")
check(fail.joins - j0 <= 90 / G(fail).AllianceLink.JOIN_GAP + 1, "at most one join every JOIN_GAP: " .. (fail.joins - j0))
check(saidJoinHint(fail) == hints, "a channel that does not answer is not a refusal said in the chat frame")
W.policy.drop = false
run(25)
check(G(fail).AllianceChat:State() == "joined" and G(fail).AllianceLink:JoinError() == nil, "and the error clears once it joins")
logout(fail)
noErrors(fail, "refusals")
-- The officers keep their site code all along (the pasted codes were another client's).
check(G(aGM).AllianceLink:ChannelName() == CH1, "the others are untouched")

-- (f) Key rotation: B is removed on the site. A gets a new key; B's block names no alliance.
logout(bX)   -- away during the rotation: comes back later holding the old code
local site2 = { code = CODE2, name = ALLY_NAME, version = 2, share = ALL_ON }
aGM.inbox[1] = gild(GA, site2, {})
aGM.inbox[2] = ally(GA, 2, { [GB] = {} }, {})
bOff.inbox[1] = gild(GB, nil)
bOff.inbox[2] = nil
reload(aGM)
reload(bOff)
run(40)
local CH2 = G(aGM).AllianceLink.ChannelNameFor("FDH", KEY2)
check(CH2 ~= CH1, "(f) a new key is a new channel")
for _, c in ipairs({ aGM, aMem, aAlt }) do
  check(inChannel(c, CH2) and not inChannel(c, CH1), "(f) " .. c.id .. " moved to the new channel")
  check(G(c).Alliance:Get().version == 2, "(f) " .. c.id .. " holds key version 2")
end
for _, c in ipairs({ bOff, bMem }) do
  check(not inChannel(c, CH1) and not inChannel(c, CH2) and G(c).Alliance:Get() == nil,
    "(f) " .. c.id .. " leaves the alliance: its block (or its officer) said it ended")
end
-- bX comes back with the old relayed code and no officer of B online: left alone in the old channel.
logout(bOff)
login(bX)
run(40)
check(inChannel(bX, CH1) and not inChannel(bX, CH2), "(f) a B client that missed the end is alone in the old channel")
m0 = marks()
typeGuild(bX, "alguém aí?")
check(#gsince(aGM, m0[aGM]) == 0 and #gsince(aMem, m0[aMem]) == 0, "(f) nobody of A reads it")
typeGuild(aMem, "só a horda")
check(#gsince(bX, m0[bX]) == 1, "(f) and it reads nobody of A (its own guild's line only)")
-- B's officer logs in: bX hears the end at its ask and leaves.
login(bOff)
run(40)
check(not inChannel(bX, CH1) and G(bX).Alliance:Get() == nil, "(f) once an officer of B is on, the end reaches it")
for _, c in ipairs({ aGM, aMem, aAlt, bOff, bMem, bX }) do noErrors(c, "(f)") end

-- ════════════════════════════════════════════════════════════════════════
-- II. WoW: Forever: a pasted code (no site), names with a surname
-- ════════════════════════════════════════════════════════════════════════
newWorld("forever")
local fOff = newClient({ id = "fOff", name = "Chehul", surname = "Costa", guild = GA, rank = 1 })
local fMem = newClient({ id = "fMem", name = "Ana", surname = "Lima-Souza", guild = GA, rank = 4 })
local gOff = newClient({ id = "gOff", name = "Bia", surname = "Rocha", guild = GB, rank = 0 })
local gMem = newClient({ id = "gMem", name = "Caio", surname = "Melo", guild = GB, rank = 4 })
-- A client of the old naming (GOSA .. TAG, before the key's hash): its own channel, nobody new meets it.
local OLDCH = "GOSAPACTO"
for _, c in ipairs({ fOff, fMem, gOff, gMem }) do login(c) end
run(20)
local PASTED = "GOS=PACTO:Zx9Cv8Bn7M"
check(G(fOff).AllianceLink:SetCode(PASTED), "(g) A's officer pastes the code")
check(G(gOff).AllianceLink:SetCode(PASTED), "(g) B's officer pastes the same code")
run(30)
local CHP = G(fOff).AllianceLink.ChannelNameFor("PACTO", "Zx9Cv8Bn7M")
for _, c in ipairs({ fOff, fMem, gOff, gMem }) do
  check(inChannel(c, CHP) and not G(c).Alliance:FromSite(), "(g) " .. c.id .. " is in the pasted code's channel, chat only")
end
check(G(fMem).AllianceLink:Source() == "pasted", "(g) the member's source is the officer's paste")
m0 = marks()
typeGuild(fMem, "oi ordem")
local gg = gsince(gMem, m0[gMem])
check(#gg == 1 and gg[1].msg:find("[" .. GA .. "]", 1, true) and not gg[1].msg:find("Allied guild", 1, true),
  "(g) no directory, no mesh: the line names its guild itself")
check(gg[1].author == "Ana-Lima-Souza", "(k) Forever's sender on the channel")
r0 = rooms()
G(fMem).AllianceChat:Send("sala")
local rl = roomSince(gMem, r0[gMem])
check(#rl == 1 and rl[1].n == "Ana Lima-Souza" and rl[1].g == GA, "(k) the room names a Forever speaker as the roster does: " .. tostring(rl[1] and rl[1].n))
check(#roomSince(fMem, r0[fMem]) == 1, "(k) and their own line is not echoed back (First-Surname is the player)")
local onl = G(gMem).Alliance:OnlineNow()
check(onl[1] and onl[1].name == "Ana Lima-Souza" and onl[1].guild == GA, "(k) on now with the whole name")
check(G(gMem).Alliance:Guilds()[2] and G(gMem).Alliance:Guilds()[2].name == GA, "(g) the guilds heard are the alliance's")
-- The old naming: a client from before stays in GOSA..TAG; this one left it once and never meets it.
local old = newClient({ id = "old", name = "Velho", surname = "Antigo", guild = GB, rank = 4 })
ghost(old)
serverJoin(old, OLDCH, "Zx9Cv8Bn7M")
serverJoin(gMem, OLDCH, "Zx9Cv8Bn7M")
G(gMem).AllianceChat:EnsureJoined()
check(not inChannel(gMem, OLDCH) and inChannel(gMem, CHP), "(g) the old-named channel is left once")
serverJoin(gMem, OLDCH, "Zx9Cv8Bn7M")
G(gMem).AllianceChat:EnsureJoined()
check(inChannel(gMem, OLDCH), "(g) once per character: a channel the player joins again by hand stays")
for _, c in ipairs({ fOff, fMem, gOff, gMem }) do noErrors(c, "(g)") end

print(string.format("alliance-two-guilds: %d checks passed", checks))
