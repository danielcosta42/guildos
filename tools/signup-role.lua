-- The role a core sign-up carries (issue #94), run against the real Core, Compat, Data,
-- CoreManager and UI/FeaturePanels.lua on a stubbed client and UI.
--
-- The sign-up window took the role from the class, with no choice: on WoW: Forever every class
-- starts on damage, so every sign-up arrived as melee or ranged and the core showed no tanks or
-- healers until the raid leader re-roled each person. Now the window offers the roles the class
-- can play (the site's lists), the class's own lit by default; the pick travels with the sign-up,
-- and the officer who stores it keeps it only if the class can play it.
--
--   luajit -e 'ADDON="."' tools/signup-role.lua
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

-- Any frame, any field, any method: numbers where the layout does arithmetic, itself elsewhere.
local NUM = { GetWidth = 400, GetHeight = 400, GetFrameLevel = 1, GetStringHeight = 12, GetStringWidth = 40,
              GetNumChildren = 0 }
local stub
stub = setmetatable({}, {
  __index = function(_, k)
    if NUM[k] then return function() return NUM[k] end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    return stub
  end,
  __call = function() return stub end,
})
local made, fonts = {}, {}
local function widget()
  local w = setmetatable({ scripts = {} }, { __index = stub })
  function w:SetScript(k, fn) self.scripts[k] = fn end
  function w:CreateFontString()
    local fs = setmetatable({ SetText = function(s, t) s.text = t end }, { __index = stub })
    fonts[#fonts + 1] = fs
    return fs
  end
  function w:SetText(t) self.text = t end
  function w:GetText() return rawget(self, "text") or "" end
  function w:SetPoint(_, x) self.x = x end
  function w:SetBackdropBorderColor(_, _, _, a) self.border = a end
  function w:IsShown() return self.shown end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  return w
end

local CLASS, published, handlers, GUILD = "PRIEST", {}, {}, {}
local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  made = {}
  function CreateFrame(kind, _, _, template)
    local w = widget(); w.kind, w.template = kind, template; made[#made + 1] = w; return w
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Pri", "Est" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Priest" end
  end
  function UnitClass() return CLASS:sub(1, 1) .. CLASS:sub(2):lower(), CLASS end
  function GetRealmName() return "Realm" end
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  function GetNumGuildMembers() return #GUILD, #GUILD end
  function GetGuildRosterInfo(i)
    local g = GUILD[i]
    if g then return g[1], "Rank", 3, 60, g[2], "", "", "", true, 0, g[2] end
  end
  function GetServerTime() return 1791000000 end
  time = os.time
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  UISpecialFrames, StaticPopupDialogs = {}, {}
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  -- One translated label, so a label shown untranslated is seen.
  GuildOS = { L = setmetatable({ Healer = "Heiler" }, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Data.lua")
  BRutus.ApplyFont = function(_, fs, size) if type(fs) == "table" then rawset(fs, "size", size) end end
  dofile(ADDON .. "/Modules/CoreManager.lua")
  BRutus.db = { settings = {}, members = {}, altLinks = {}, cores = {}, raidTracker = { sessions = {}, attendance = {} } }
  published, handlers = {}, {}
  BRutus.SyncService = { On = function(_, dom, fn) handlers[dom] = fn end,
                         Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, data = data } end }
  BRutus.CoreManager:InitSync()
  BRutus.UI = setmetatable({ GetFeature = function() return nil end, SkinScrollBar = function() end },
                           { __index = function() return function() return stub end end })
  dofile(ADDON .. "/UI/FeaturePanels.lua")
  SlashCmdList = {}
  dofile(ADDON .. "/Core/Commands.lua")
  return BRutus.CoreManager
end

-- What the site says each class can play (packages/wow: forever.ts, and anniversary.ts's specs
-- read as roles), in the window's order: tank, healer, melee, ranged.
local SITE = {
  WARRIOR = "tank mdps", PALADIN = "tank healer mdps", HUNTER = "rdps", ROGUE = "mdps", PRIEST = "healer rdps",
  SHAMAN = "healer mdps rdps", MAGE = "rdps", WARLOCK = "rdps", DRUID = "tank healer mdps rdps",
}

for _, game in ipairs({ "forever", "anniversary" }) do
  local function G(what) return game .. ": " .. what end
  local CM = load(game)

  -- ── The roles each class can play ──────────────────────────────────────
  for cls, want in pairs(SITE) do
    check(table.concat(CM:RolesFor(cls), " ") == want, G(cls .. " can play " .. want .. ", as the site says"))
    local own = CM.CLASS_DEFAULT_ROLE[cls]
    check(CM:RoleFor(cls, nil) == own and CM.CLASS_ROLES[cls][own], G(cls .. "'s own role is one it can play, and the default"))
  end
  check(CM:RoleFor("PRIEST", "healer") == "healer", G("a role the class can play is kept"))
  check(CM:RoleFor("MAGE", "tank") == "rdps", G("one it cannot is the class's own"))
  check(CM:RoleFor("NOPE", "tank") == "rdps" and CM:RoleFor(nil, nil) == "rdps", G("an unknown class is ranged, as before"))

  -- ── The sign-up carries the pick ───────────────────────────────────────
  CLASS = "PRIEST"
  CM = load(game)
  CM:Create("Main")
  local me = BRutus:GetPlayerKey(BRutus.Compat.PlayerName(), GetRealmName())
  CM:BroadcastSignup("Main", "", "healer")
  check(CM:GetSignups("Main")[me].role == "healer", G("my own sign-up shows the role I picked"))
  check(published[1] and published[1].dom == "core.signup" and published[1].data.info.role == "healer",
    G("and sends it to the officers"))
  CM:BroadcastSignup("Main", "", "tank")
  check(CM:GetSignups("Main")[me].role == CM.CLASS_DEFAULT_ROLE.PRIEST, G("a role a priest cannot play is not sent"))
  CM:BroadcastSignup("Main", "")
  check(CM:GetSignups("Main")[me].role == CM.CLASS_DEFAULT_ROLE.PRIEST, G("no pick is the class's own, as before"))

  -- ── The officer keeps it only if the class can play it ────────────────
  CM = load(game)
  CM:Create("Main")
  handlers["core.signup"]({ data = { coreName = "Main", info = { class = "DRUID", role = "tank" } } }, "Ann")
  local ann = CM:GetSignups("Main")[BRutus:GetPlayerKey("Ann")]
  check(ann and ann.role == "tank", G("an officer stores the role a druid picked"))
  handlers["core.signup"]({ data = { coreName = "Main", info = { class = "MAGE", role = "healer" } } }, "Bob")
  check(CM:GetSignups("Main")[BRutus:GetPlayerKey("Bob")].role == "rdps", G("and never a role the class cannot play"))
  handlers["core.signup"]({ data = { coreName = "Main", info = { class = "WARRIOR" } } }, "Cid")
  check(CM:GetSignups("Main")[BRutus:GetPlayerKey("Cid")].role == CM.CLASS_DEFAULT_ROLE.WARRIOR,
    G("a sign-up from an addon before this one carries the class's own"))
  GUILD = { { game == "forever" and "Dee" or "Dee-Realm", "PRIEST" } }
  BRutus.db.members[BRutus:GetPlayerKey("Dee")] = { class = "DRUID" }   -- what Dee's own broadcast claimed
  handlers["core.signup"]({ data = { coreName = "Main", info = { class = "DRUID", role = "tank" } } }, "Dee")
  local dee = CM:GetSignups("Main")[BRutus:GetPlayerKey("Dee")]
  check(dee.class == "PRIEST" and dee.role == CM.CLASS_DEFAULT_ROLE.PRIEST,
    G("a sender on the guild roster is the class the server says, whatever the payload or their own data claim"))
  GUILD = {}
  handlers["core.signup"]({ data = { coreName = "Main", info = { role = "tank" } } }, "Eve")
  local eve = CM:GetSignups("Main")[BRutus:GetPlayerKey("Eve")]
  check(eve.class == "WARRIOR" and eve.role == "tank", G("no class anywhere is a warrior, with a role a warrior can play"))
  handlers["core.signup"]({ data = { coreName = "Main", info = { class = {}, role = {} } } }, "Fay")
  local fay = CM:GetSignups("Main")[BRutus:GetPlayerKey("Fay")]
  check(fay.class == "WARRIOR" and fay.role == CM.CLASS_DEFAULT_ROLE.WARRIOR, G("a class or role that is not a string is neither"))
  CM:AcceptSignup(BRutus:GetPlayerKey("Ann"), "Main")
  check(BRutus.db.cores.Main.members[BRutus:GetPlayerKey("Ann")].role == "tank", G("accepted, the picked role is the roster's"))

  -- ── The window ─────────────────────────────────────────────────────────
  CLASS = "PRIEST"
  CM = load(game)
  CM:Create("Main")
  CM:Create("Zed")
  local sent
  CM.BroadcastSignup = function(_, core, note, role) sent = { core = core, note = note, role = role } end
  BRutus:ShowCoreSignupFrame()
  local frame
  for _, w in ipairs(made) do if rawget(w, "roleBtns") then frame = w end end
  check(frame and frame.roleBtns.healer and frame.roleBtns.rdps and not frame.roleBtns.tank and not frame.roleBtns.mdps,
    G("a priest is offered healer and ranged, and nothing else"))
  -- The first core's Sign Up drawn since `from` (not a role button, not the close box).
  local function signUp(from)
    for i = from, #made do
      local w = made[i]
      if w.kind == "Button" and w.scripts.OnClick and not rawget(w, "lbl") and w.template ~= "UIPanelCloseButton" then
        w.scripts.OnClick(w)
        return
      end
    end
  end
  local before = #made
  signUp(1)
  check(sent and sent.core == "Main" and sent.role == CM.CLASS_DEFAULT_ROLE.PRIEST, G("signing up untouched sends the class's own"))
  check(frame.roleBtns.healer.lbl.text == "Heiler" and frame.roleBtns.rdps.lbl.text == "Ranged", G("each button is its role's name, translated"))
  -- A priest's own is ranged on Forever and healer on Anniversary: the test picks the other one.
  local own = CM.CLASS_DEFAULT_ROLE.PRIEST
  local other = own == "healer" and "rdps" or "healer"
  local otherName = other == "healer" and "Heiler" or "Ranged"
  local short = { healer = "H:", rdps = "R:" }
  -- The coverage row's own role is drawn larger (12 against 10).
  local function coverage(role)
    for i = #fonts, 1, -1 do
      local t = rawget(fonts[i], "text")
      if type(t) == "string" and t:sub(1, 2) == short[role] then return rawget(fonts[i], "size") end
    end
  end
  check(frame.roleBtns[own].border == 0.9 and frame.roleBtns[other].border == 0.3, G("the class's own is lit until something is picked"))
  -- Cores are drawn A to Z: Main's box, then Zed's. Type in Main's.
  local function noteBoxes(from)
    local list = {}
    for i = from, #made do if made[i].kind == "EditBox" then list[#list + 1] = made[i] end end
    return list
  end
  local typed = noteBoxes(before + 1)[1]   -- the window as Sign Up redrew it
  typed:SetText("can heal if needed")
  typed.scripts.OnTextChanged(typed)
  local mark = #made
  frame.roleBtns[other].scripts.OnClick()
  check(frame.pickedRole == other and #made > mark, G("picking the other role redraws the window"))
  check(frame.playerRoleLbl.text:find(otherName, 1, true), G("the strip names the pick"))
  check(frame.roleBtns[other].border == 0.9 and frame.roleBtns[own].border == 0.3, G("and the pick is the one lit"))
  check(coverage(other) == 12 and coverage(own) == 10, G("and the one the core's coverage row marks"))
  local redrawn = noteBoxes(mark + 1)
  check(redrawn[1]:GetText() == "can heal if needed" and redrawn[2]:GetText() == "",
    G("a note typed before the pick is still there, in its own core's box"))
  sent = nil
  signUp(mark + 1)
  check(sent and sent.role == other and sent.note == "can heal if needed", G("and Sign Up sends the pick, with the note"))

  CLASS = "DRUID"
  CM = load(game)
  CM:Create("Main")
  BRutus:ShowCoreSignupFrame()
  frame = nil
  for _, w in ipairs(made) do if rawget(w, "roleBtns") then frame = w end end
  local b = frame.roleBtns
  check(b.tank and b.healer and b.mdps and b.rdps and b.tank.x < b.healer.x and b.healer.x < b.mdps.x and b.mdps.x < b.rdps.x,
    G("a druid gets all four, tank to ranged from left to right"))

  -- ── The slash command ──────────────────────────────────────────────────
  CLASS = "PRIEST"
  CM = load(game)
  CM:Create("Main")
  sent = nil
  CM.BroadcastSignup = function(_, core, note, role) sent = { core = core, note = note, role = role } end
  SlashCmdList.GUILDOS("signup Main healer back by 9")
  check(sent and sent.core == "Main" and sent.role == "healer" and sent.note == "back by 9", G("/gos signup Main healer <note> picks healer"))
  SlashCmdList.GUILDOS("signup Main Ranged")
  check(sent.role == "rdps" and sent.note == "", G("a role word in any case, with no note"))
  SlashCmdList.GUILDOS("signup Main back by 9")
  check(sent.role == nil and sent.note == "back by 9", G("a note that starts with no role word is all note"))
  SlashCmdList.GUILDOS("signup Main melee")
  check(sent.role == "mdps", G("melee is melee"))
  SlashCmdList.GUILDOS("signup Main heal")
  check(sent.role == "healer", G("and heal is healer"))

  CLASS = "MAGE"
  CM = load(game)
  CM:Create("Main")
  BRutus:ShowCoreSignupFrame()
  frame = nil
  for _, w in ipairs(made) do if rawget(w, "roleBtns") then frame = w end end
  check(frame and next(frame.roleBtns) == nil, G("a mage, who has one role, gets no buttons"))
end

print(("signup-role: %d checks passed"):format(checks))
