-- The alliance's screens (specs/salao/alianca.md §3.5, audit #448), run against the real
-- Modules/Alliance.lua, Modules/AllianceChat.lua and UI/AlliancePanel.lua with stubbed frames.
--
-- Proves:
--   * Salão › Alliance names the alliance and its guilds as the code and the channel tell, ours
--     marked, who of them is on now with the note that it is a best effort, the alliance room and
--     the shared /g's switch; with no alliance it says so and where alliances live now;
--   * the raids open to the alliance show only once the site's hook has some;
--   * with the site's code in force: the alliance's name and its guilds from the directory with how many
--     it lists, the open raids with where, who leads, "as of" and that signing up is on the site or in
--     Discord; Officers' Room › Alliance says "From guildos.me", managed there, with no paste field; a
--     pasted code or another key version gets none of the block; the guilds blocked here (review A);
--   * Officers' Room › Alliance offers the code by hand with the line that it is the chat only, and
--     the alliance's bans only while the guild has an alliance on guildos.me (audit B7);
--   * the rooms open the two screens, the officers' one in the Officers' Room only;
--   * the Manage tab, its founding, ambassador and code sections are gone.
--
--   luajit -e 'ADDON="."' tools/alliance-panel.lua
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

local function read(path)
  local fh = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = fh:read("*a")
  fh:close()
  return s
end

-- A frame that takes any call; texts and shown states are kept.
local Frame = {}
Frame.__index = function(_, k)
  return Frame[k] or function(self) return self end
end
local all = {}
function Frame.new(parent)
  local f = setmetatable({ children = {}, shown = true, scripts = {} }, Frame)
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  all[#all + 1] = f
  return f
end
function Frame:GetWidth() return 700 end
function Frame:GetHeight() return 400 end
function Frame:GetStringWidth() return 40 end
function Frame:GetStringHeight() return 12 end
function Frame:IsVisible() return true end
function Frame:IsShown() return self.shown end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:HasFocus() return false end
function Frame:CreateTexture() return Frame.new(self) end
function Frame:CreateFontString() return Frame.new(self) end
function CreateFrame(_, _, parent) return Frame.new(parent) end

local NOW = 1794000000
function GetServerTime() return NOW end
time = function() return NOW end
function date(...) return os.date(...) end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function GetGuildInfo() return "Guilda A", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function GetRealmName() return "Realm" end
function Ambiguate(name) return (tostring(name):gsub("%-.*$", "")) end

local officer = true
GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end }),
  Compat = { After = function() end, PlayerName = function() return "Ana" end },
  db = { members = {} },
}
function GuildOS:IsOfficer() return officer end
function GuildOS:SafeCall(fn, ...) return true, fn(...) end
function GuildOS:SanitizeUserText(t) return tostring(t or "") end
function GuildOS:GetPlayerKey(n, r) return n .. "-" .. r end
function GuildOS:LocalDate(fmt, ts) return os.date(fmt, ts) end
function GuildOS:GetClassColor() return 1, 1, 1 end
function GuildOS:Print() end
function GuildOS.FoldCase(x) return tostring(x or ""):lower() end
function GuildOS.SameGuildName(a, b) return type(a) == "string" and type(b) == "string" and a:lower() == b:lower() end
GuildOS.UI = setmetatable({ GAP = 8, SCROLL_GUTTER = 22 }, { __index = function(_, name)
  return function(_, parent, text)
    local f = Frame.new(type(parent) == "table" and parent or nil)
    f.helper = name
    f.label = Frame.new(f)
    if name == "CreateScrollFrame" then return f, Frame.new(f) end
    if type(text) == "string" then
      if name == "CreateButton" or name == "CreateTab" then f.label.text = text else f.text = text end
    end
    return f
  end
end })
function GuildOS.UI:CollapsibleSubBar(host) host.SetSubBarShown = function() end end
function GuildOS.UI:MakeResponsive() end

dofile(ADDON .. "/Modules/Alliance.lua")
dofile(ADDON .. "/Modules/AllianceChat.lua")
local A, Chat = GuildOS.Alliance, GuildOS.AllianceChat
Chat:Prefs()

local pact
GuildOS.AllianceLink = {
  Pact = function() return pact end,
  Active = function() return pact ~= nil end,
  ChannelName = function() return pact and "GOSANUCLEO" end,
  Config = function()
    return pact and { tag = "NUCLEO", key = "Kx7Pq2Lm9Z", open = true, line = "GOS=NUCLEO:Kx7Pq2Lm9Z", guilds = {}, order = {},
                      site = pact.site, name = pact.site and pact.name or nil, version = pact.version }
  end,
  Suggest = function() return pact and "GOS=NUCLEO:Kx7Pq2Lm9Z" end,
  Parse = function() return { tag = "NUCLEO" } end,
}
local siteAlliance, bans = false, nil
GuildOS.BanList = {
  AllianceBans = function() return bans end,
  HasSiteAlliance = function() return siteAlliance end,
  AllianceLine = function(b) return "Banned in " .. b.guild .. " for " .. b.reason end,
}

dofile(ADDON .. "/UI/AlliancePanel.lua")
local parent = Frame.new(nil)
GuildOS:CreateAlliancePanel(parent, nil)
check(type(parent.SelectSub) == "function" and parent.subPanels.hall and parent.subPanels.setup,
  "the panel builds its two screens and exposes them")

-- Every text drawn under a frame, for the checks.
local function texts(root)
  local out = {}
  local function walk(f)
    if f.shown ~= false then
      if type(f.text) == "string" then out[#out + 1] = f.text end
      for _, c in ipairs(f.children) do walk(c) end
    end
  end
  walk(root)
  return table.concat(out, "\n")
end
local hall, setup = parent.subPanels.hall.panel, parent.subPanels.setup.panel

-- ── 1. No alliance ─────────────────────────────────────────────────────
parent.SelectSub("hall")
local t = texts(hall)
check(t:find("This guild is not in an alliance yet.", 1, true) and t:find("Alliances now live on guildos.me.", 1, true),
  "no alliance: the Salão says so, and where alliances live now")
check(not t:find("Alliance room", 1, true), "and shows no room")

-- ── 2. Salão › Alliance ────────────────────────────────────────────────
pact = { source = "link", tag = "NUCLEO", name = "NUCLEO", open = true,
         guilds = { ["Guilda A"] = {}, ["Guilda B"] = {}, ["Guilda C"] = {} } }
A:Heard("Bob-Realm", "Guilda B")
A:Heard("Gui-Realm", "Guilda A")   -- ours: never counted as an ally on now
parent.SelectSub("hall")
t = texts(hall)
check(t:find("NUCLEO", 1, true), "the alliance's name")
check(t:find("Guilda A|r (you)", 1, true) and t:find("Guilda B|r", 1, true) and t:find("Guilda C|r", 1, true),
  "its guilds, ours marked")
check(t:find("Guilda B|r |cffffffff1 online", 1, true) and not t:find("Guilda C|r |cff", 1, true), "how many of an allied guild are seen on")
check(t:find("Online now", 1, true) and t:find("Bob |cff", 1, true) and not t:find("Gui |cff", 1, true),
  "who is on now, never ours")
check(t:find("Best effort: only who spoke on the alliance channel or runs GuildOS is seen.", 1, true),
  "saying it is a best effort")
check(t:find("Alliance room", 1, true), "the alliance room")
check(t:find("Allied /g: shown", 1, true), "and the shared /g's switch, on by default")
check(not t:find("Open raids", 1, true), "no open raids until the site sends some")
local gchat
for _, f in ipairs(all) do local l = rawget(f, "label"); if l and l.text == "Allied /g: shown" then gchat = f end end
check(gchat and gchat.scripts.OnClick, "the switch is a button")
gchat.scripts.OnClick()
check(Chat:Prefs().guildBridge == false and gchat.label.text == "Allied /g: hidden", "a click turns the shared /g off")
gchat.scripts.OnClick()
check(Chat:Prefs().guildBridge == true, "and on again")

-- The site's open raids (GOSALLY1's hook): shown once there are some.
local ownRaids = A.OpenRaids
A.OpenRaids = function() return { { guild = "Guilda B", title = "Karazhan", when = NOW + 3600, going = 7, size = 10 } } end
parent.SelectSub("hall")
t = texts(hall)
check(t:find("Open raids", 1, true) and t:find("Karazhan (7/10)", 1, true), "an open raid, with how many are going")
A.OpenRaids = ownRaids   -- back to the module's own (an empty list)
check(#A:OpenRaids() == 0, "the hook answers nothing by itself")

-- ── 3. Officers' Room › Alliance ───────────────────────────────────────
parent.SelectSub("setup")
t = texts(setup)
check(t:find("Active: NUCLEO, 3 guilds.", 1, true), "the code in force")
-- The setup is a parchment card titled with what it is (specs/salao/fase3.md).
check(read("UI/AlliancePanel.lua"):find('UI:CreateCard(parent, L["Alliance code"])', 1, true), "under the card's title, Alliance code")
check(t:find("Chat only: the shared /g and the alliance room. Members, crafters, raids and bans come from guildos.me.", 1, true),
  "pasted by hand, it is the chat only, and the rest comes from the site")
check(t:find("Save for the guild", 1, true) and t:find("Generate", 1, true), "the field to paste it, and its buttons")
check(not t:find("The alliance's bans", 1, true), "B7: no alliance on guildos.me, no alliance's bans")
siteAlliance = true
parent.SelectSub("setup")
t = texts(setup)
check(t:find("The alliance's bans", 1, true) and t:find("No bans from the alliance.", 1, true),
  "with one, the alliance's bans, none yet")
bans = { { name = "Thrall", guild = "Guilda B", reason = "ninja" } }
parent.SelectSub("setup")
t = texts(setup)
check(t:find("Thrall", 1, true) and t:find("Banned in Guilda B for ninja", 1, true) and not t:find("No bans from the alliance.", 1, true),
  "each ban with the guild that banned and why")
officer = false
parent.SelectSub("setup")
t = texts(setup)
check(not t:find("The alliance's bans", 1, true) and not t:find("Save for the guild", 1, true), "a member sees neither")
officer = true

-- ── 3b. The site's code in force (alianca.md §3.2, §3.5) ───────────────
local allyBlock = {
  at = NOW - 1800, alliance = { name = "Pacto do Sul", tag = "NUCLEO", version = 2 },
  guilds = { { name = "Guilda A", self = true, members = {} },
             { name = "Guilda B", members = { { key = "Bob", name = "Bob", class = "MAGE", level = 70 },
                                              { key = "Bea", name = "Bea", class = "PRIEST", level = 70 } } },
             { name = "Guilda E", members = { { key = "Edu", name = "Edu", class = "ROGUE", level = 60 } } } },
  raids = { { id = "r1", guild = "Guilda B", title = "Gruul", where = "Gruul's Lair", startsAt = NOW + 7200,
              size = 25, lead = "Bob-Realm", going = 11 },
            { id = "r0", guild = "Guilda E", title = "Ontem", startsAt = NOW - 4 * 3600, size = 10, going = 2 } },
}
GuildOS.CompanionImport = { AllianceBlock = function() return allyBlock end }
pact.blocked = {}
check(#A:Directory() == 0 and #A:OpenRaids() == 0, "a pasted code gets none of the site's block: the chat only (§3.3)")
pact.site, pact.name, pact.version = true, "Pacto do Sul", 2
parent.SelectSub("hall")
t = texts(hall)
check(t:find("Pacto do Sul [NUCLEO]", 1, true), "Salão › Alliance names the alliance as the site does")
check(t:find("Guilda E|r", 1, true) and t:find("Guilda B|r |cffffffff(2 in the directory)", 1, true),
  "and its guilds from the directory, one nobody heard on the channel included, with how many it lists")
check(t:find("Gruul (11/25)", 1, true) and t:find("Gruul's Lair", 1, true) and t:find("led by Bob", 1, true)
  and not t:find("Ontem", 1, true), "the open raids: where, who leads, how many go; one long begun is not")
check(t:find("(as of ", 1, true) and t:find("Sign up in Discord or on the website.", 1, true),
  "as of when the site built them, and that signing up is on the site or in Discord")
pact.version = 3
check(#A:OpenRaids() == 0 and #A:Directory() == 0, "a block of another key version is not this alliance's")
pact.version = 2
check(A:Block("Guilda B"))
check(#A:OpenRaids() == 0 and #A:Directory() == 1, "a blocked guild's raids and members are left out")
check(A:Unblock("Guilda B") and #A:Directory() == 2, "and back once unblocked")

parent.SelectSub("setup")
t = texts(setup)
check(t:find("From guildos.me: Pacto do Sul [NUCLEO]", 1, true) and t:find("This alliance is managed on guildos.me", 1, true),
  "Officers' Room › Alliance: From guildos.me, with the alliance's name, managed there")
check(not t:find("Save for the guild", 1, true) and not t:find("Generate", 1, true) and not t:find("Chat only:", 1, true),
  "and no field to paste a code")
check(t:find("The alliance's bans", 1, true), "the alliance's bans stay")
-- Blocking a guild here (review A).
check(t:find("Ignore a guild locally", 1, true) and t:find("Lines from a blocked guild are not shown on this account.", 1, true),
  "the block list, empty")
local blockBox, blockBtn, unblockBtn
for _, f in ipairs(all) do
  local l = rawget(f, "label")
  if l and l.text == "Block" then blockBtn = f elseif l and l.text == "Unblock" then unblockBtn = f end
end
for _, f in ipairs(all) do if f.helper == "CreateInput" and f.scripts and blockBtn and f ~= blockBtn then blockBox = f end end
GuildOS.AllianceChat._Notify = function() end
A.Block = function(_, g) pact.blocked[g] = true; return true end
A.Unblock = function(_, g) pact.blocked[g] = nil; return true end
blockBox:SetText("Guilda E")
blockBtn.scripts.OnClick()
t = texts(setup)
check(pact.blocked["Guilda E"] and t:find("Blocked: Guilda E", 1, true), "Block adds the guild, and the list says it")
blockBox:SetText("Guilda E")
unblockBtn.scripts.OnClick()
check(not pact.blocked["Guilda E"], "Unblock lifts it")
pact.site, pact.name, pact.version = nil, "NUCLEO", nil
GuildOS.CompanionImport = nil

-- ── 4. The rooms and what is gone ──────────────────────────────────────
local rooms = read("UI/Rooms.lua")
check(rooms:find('{ id = "alliance", label = L["Alliance"],     feature = "alliance", sub = "hall" }', 1, true),
  "the Salão's Alliance opens the hall")
local officersAt = rooms:find('{ id = "officers"', 1, true)
local setupAt = rooms:find('feature = "alliance",    sub = "setup"', 1, true)
check(officersAt and setupAt and setupAt > officersAt, "the Officers' Room's Alliance opens the setup")
local panelSrc = read("UI/AlliancePanel.lua")
for _, gone in ipairs({ "BuildManage", "BuildBulletin", "Claim ambassador", "Join code", "Found an alliance",
                        "PromoteAmbassadors", "RequestAllianceSlot", "ShowAllyCard" }) do
  check(not panelSrc:find(gone, 1, true), "the panel has no " .. gone)
end

print(("alliance-panel: %d checks passed"):format(checks))
