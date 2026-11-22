-- The officers' chat alerts on screen (issues #404, #405): the real UI/ModAlerts.lua and
-- Modules/ModAlerts.lua under generic frame stubs. The alert window and the Leadership sub-tabs build,
-- draw the alerts and the rules, reuse their rows across repaints, draw nothing off screen, and their
-- buttons reach the module (Warn hands the line to #403).
--
--   luajit -e 'ADDON="."' tools/mod-alerts-ui.lua
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

-- A frame that takes any call, keeps its scripts and its children.
local created, visible = 0, true
local Frame = {}
Frame.__index = function(_, k)
  return Frame[k] or function(self) return self end
end
function Frame.new(parent)
  created = created + 1
  local f = setmetatable({ children = {}, shown = true, scripts = {} }, Frame)
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  return f
end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetWidth() return 600 end
function Frame:GetHeight() return 400 end
function Frame:IsVisible() return visible end
function Frame:IsShown() return self.shown end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:HookScript(k, fn) self.scripts[k] = fn end
function Frame:Click() return self.scripts.OnClick and self.scripts.OnClick(self) end
function Frame:CreateTexture() return Frame.new(nil) end
function Frame:CreateFontString() return Frame.new(nil) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return rawget(self, "text") end
function Frame:HasFocus() return false end
function CreateFrame(_, _, parent) return Frame.new(parent) end
UIParent = Frame.new(nil)
local NOW = 1794000000
function GetServerTime() return NOW end
function GetTime() return NOW end
function GetLocale() return "enUS" end
function date(...) return os.date(...) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local function mkWidget(_, parent, text)
  local f = Frame.new(type(parent) == "table" and parent or nil)
  f.label = Frame.new(nil)
  f.label.text = type(text) == "string" and text or nil
  f.checkbox = Frame.new(nil)
  function f.checkbox:GetChecked() return rawget(self, "checked") end
  function f.checkbox:SetChecked(v) self.checked = v end
  function f:SetValue(v) self.value = v end
  function f:GetValue() return rawget(self, "value") end
  return f
end
GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end }),
  UI = setmetatable({}, { __index = function() return mkWidget end }),
  Compat = {
    IsSecret = function() return false end,
    InChatLockdown = function() return false end,
    PlayerName = function() return "Arthas" end,
    RegisterEvent = function() end,
    After = function(_, fn) fn() end,
  },
  db = { settings = {} },
}
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:IsOfficer() return true end
function GuildOS:IsOfficerByName() return false end
function GuildOS:ApplyFont() end
function GuildOS:KeyOfRosterName(n) return n end
function GuildOS:CutBytes(s) return s end
function GuildOS.Finite(v) return tonumber(v) end
local warned
function GuildOS:ShowWarnDialog(key, name, opts) warned = { key = key, name = name, opts = opts } end

dofile(ADDON .. "/Modules/ModAlerts.lua")
dofile(ADDON .. "/Modules/ModFlood.lua")
dofile(ADDON .. "/UI/ModAlerts.lua")
local M, F = GuildOS.ModAlerts, GuildOS.ModFlood
M:Initialize()
F:Initialize()

-- The two sub-tabs build.
local alertsPanel, rulesPanel = Frame.new(nil), Frame.new(nil)
local drawAlerts = GuildOS:BuildModAlertsSub(alertsPanel)
local drawRules = GuildOS:BuildModRulesSub(rulesPanel)
check(type(drawAlerts) == "function" and type(drawRules) == "function", "both sub-tabs build and hand back their repaint")
drawAlerts(); drawRules()

-- Alerts in, drawn.
for i = 1, 10 do M:Deliver({ kind = "subject", who = "Thrall", key = "Thrall", line = "sell gold " .. i,
  context = { { n = "Jaina", m = "hi" } }, cat = "trade", sev = "high", rule = "W:sell gold", claim = string.format("%08x", i) }) end
check(GuildOS.modAlertFrame and GuildOS.modAlertFrame.shown, "a medium or high alert opens the window")
check(GuildOS.modAlertFrame.line.text:find("sell gold 10", 1, true), "the window shows the line")
check(GuildOS.modAlertFrame.context.text == "Jaina: hi", "and the line before it")
local afterFirst = created
for _ = 1, 300 do drawAlerts(); drawRules() end
check(created == afterFirst, "300 repaints reuse the rows (" .. (created - afterFirst) .. " made)")

-- Off screen nothing is drawn.
visible = false
for i = 11, 30 do M:Deliver({ kind = "subject", who = "Thrall", key = "Thrall", line = "x " .. i, cat = "trade", sev = "low", claim = string.format("%08x", i) }) end
check(created == afterFirst, "off screen, nothing is drawn")
visible = true

-- The window's buttons reach the module.
local f = GuildOS.modAlertFrame
local shownAlert = f.alert
f.warn:Click()
check(warned and warned.opts.excerpt == shownAlert.line and warned.opts.reason == "trade" and shownAlert.state == "warned",
      "Warn opens #403 with the line")
check(not f.shown, "and closes the window")
M:Deliver({ kind = "subject", who = "Garrosh", key = "Garrosh", line = "wts boost", cat = "trade", sev = "med", rule = "W:wts boost", claim = "000000aa" })
GuildOS.modAlertFrame.mute:Click()
check(M.mutes["W:wts boost"] and M.mutes["W:wts boost"] > NOW, "Mute for an hour from the window")

-- The rules tab adds through the module, and says why it refused.
local function find(panel, pred)
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if pred(c) then return c end
      local hit = walk(c)
      if hit then return hit end
    end
  end
  return walk(panel)
end
local added
local realAdd = M.AddRule
M.AddRule = function(_, p, cat, sev, isLua) added = { p, cat, sev, isLua }; return false, "invalid" end
local addBtn = find(rulesPanel, function(c) local l = rawget(c, "label"); return l and rawget(l, "text") == "Add" end)
check(addBtn ~= nil, "the Add button")
addBtn:Click()
check(added and added[1] == nil and added[2] == "custom" and added[3] == "med" and added[4] == false, "it adds with the chosen category and severity")
M.AddRule = realAdd
local nRules = #M:GetRules()
local del = find(rulesPanel, function(c) local l = rawget(c, "label"); return l and rawget(l, "text") == "\195\151" and c.shown end)
check(del ~= nil, "each rule has its remove button")
del:Click()
check(#M:GetRules() == nRules - 1, "and it removes the rule")

-- The anti-flood's limits (#405) on the same tab.
check(type(rulesPanel.floodRefresh) == "function", "the anti-flood's section builds under the rules")
local nInputs = 0
local function walkAll(fr, fn) for _, c in ipairs(fr.children) do fn(c); walkAll(c, fn) end end
walkAll(rulesPanel, function(c) if rawget(c, "text") == "5" or rawget(c, "text") == "10" then nInputs = nInputs + 1 end end)
check(nInputs >= 2, "its fields show the guild's limits")
local saveBtn = find(rulesPanel, function(c) local l = rawget(c, "label"); return l and rawget(l, "text") == "Save limits" end)
local got
local realSet = F.SetConfig
F.SetConfig = function(_, cfg) got = cfg; return true end
saveBtn:Click()
check(got and got.burst.n == 5 and got.burst.secs == 10 and got.caps.pct == 70 and got.caps.min == 12 and got.links.n == 2,
      "Save sends what the fields hold")
F.SetConfig = realSet
-- A surge's alert names its signals.
M:Deliver({ kind = "flood", signals = { "burst", "repeat" }, who = "Thrall", key = "Thrall", line = "x", lines = { "a", "b", "x" },
  count = 3, cat = "flood", sev = "med", rule = "F:burst", claim = "000000bb" })
check(GuildOS.modAlertFrame.title.text:find("too many lines, the same line repeated", 1, true), "the window names a surge's signals")
check(GuildOS.modAlertFrame.line.text:find("(3 lines)", 1, true) and GuildOS.modAlertFrame.context.text == "Thrall: a\nThrall: b",
      "with its count and its lines")

print(("mod-alerts-ui: %d checks passed"):format(checks))
