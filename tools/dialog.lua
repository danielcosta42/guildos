-- GuildOS's own confirmation dialog (issue #315), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Core/Data.lua, Core/Style.lua and UI/Helpers.lua: that nothing in the addon goes through Blizzard's
-- StaticPopup any more (its shared frames, tainted by an addon's dialog, block WoW: Forever's gamepad
-- UI), and that a dialog still accepts, cancels, times out and hands its edit box over as one did.
--
--   luajit -e 'ADDON="."' tools/dialog.lua
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

-- ── No StaticPopup anywhere the game loads ──────────────────────────────
local toc = assert(io.open(ADDON .. "/GuildOS.toc")):read("*a")
local files = 0
for path in toc:gmatch("[^\r\n]+") do
  if path:match("%.lua$") and not path:match("^#") and not path:match("^Libs") then
    local src = assert(io.open(ADDON .. "/" .. path:gsub("\\", "/")), path):read("*a")
    files = files + 1
    check(not src:find("StaticPopup_Show", 1, true) and not src:find("StaticPopupDialogs", 1, true),
      path .. " still goes through StaticPopup: use GuildOS.Dialogs and GuildOS:ShowDialog")
  end
end
check(files > 50, "the TOC's files were read")

-- ── A client with frames that show, hide and run their OnHide ───────────
local function frame(parent)
  local f = { shown = true, scripts = {}, parent = parent }
  function f:Show() self.shown = true end
  function f:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function f:SetShown(on) if on then self:Show() else self:Hide() end end
  function f:IsShown() return self.shown end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript() end
  function f:GetParent() return self.parent end
  function f:SetText(t) self.text_ = t end
  function f:GetText() return self.text_ end
  function f:SetMaxLetters(n) self.maxLetters = n end
  function f:SetFocus() self.focused = true end
  function f:GetStringHeight() return 20 end
  function f:GetStringWidth() return 10 end
  function f:GetWidth() return 100 end
  function f:GetFrameLevel() return 1 end
  function f:SetHeight(h) self.height = h end
  function f:IsEnabled() return true end
  function f:CreateFontString() return frame(self) end
  function f:CreateTexture() return frame(self) end
  -- A widget method is capitalised; a field the addon keeps on a frame is not, and reads as unset.
  -- GetEditBox is the game popup's alone: a plain frame has none, and Compat.PopupEditBox asks.
  return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") and k ~= "GetEditBox" then return function() end end end })
end
UIParent = frame()
function CreateFrame(_, _, parent) return frame(parent) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70888", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function GetTime() return 1 end
function UnitFullName() return "Lead", "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
CANCEL = "Cancel"
C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
-- The game's own popup: any call into it is the bug.
StaticPopupDialogs = setmetatable({}, { __newindex = function() error("wrote to StaticPopupDialogs") end })
function StaticPopup_Show() error("called StaticPopup_Show") end

GuildOSDB = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
GuildOS.db = { settings = {} }
dofile(ADDON .. "/UI/Helpers.lua")

check(GuildOS.Dialogs.GUILDOS_STYLE_RELOAD, "a definition written at file load lands in GuildOS.Dialogs")
check(GuildOS:ShowDialog("NOPE") == nil, "an unknown dialog is nothing, not an error")

-- ── Accept, cancel, replace ─────────────────────────────────────────────
local log = {}
GuildOS.Dialogs.T = {
  text = "Link %d to %s?", button1 = "Yes", button2 = "No",
  OnAccept = function(_, data, data2) log[#log + 1] = "accept:" .. tostring(data) .. ":" .. tostring(data2) end,
  OnCancel = function(_, data) log[#log + 1] = "cancel:" .. tostring(data) end,
  OnHide = function() log[#log + 1] = "hide" end,
}
local d = GuildOS:ShowDialog("T", 3, "Ana", "x")
check(d and d:IsShown() and d.text:GetText() == "Link 3 to Ana?" and d.data == "x", "shown, the text formatted, the data on the frame")
check(d.button1.label:GetText() == "Yes" and d.button2.label:GetText() == "No" and not d.editBox:IsShown(), "its two buttons, and no edit box unless asked")
d.data2 = "y"
d.button1.scripts.OnClick()
check(not d:IsShown() and table.concat(log, ",") == "accept:x:y,hide", "button1: OnAccept with data and data2, then OnHide, and no cancel")

log = {}
d = GuildOS:ShowDialog("T", 1, "Bo", "z")
d.button2.scripts.OnClick()
check(table.concat(log, ",") == "cancel:z,hide", "button2 is a cancel")

log = {}
d = GuildOS:ShowDialog("T", 1, "Bo", "esc")
d:Hide()   -- what ESC does, through UISpecialFrames
check(table.concat(log, ",") == "cancel:esc,hide", "and so is ESC")

log = {}
d = GuildOS:ShowDialog("T", 1, "Bo", "altz")
d.shown = true; d.scripts.OnHide(d)   -- hidden with the whole interface: OnHide runs, the frame is still shown
check(#log == 0 and d.def, "hidden with the interface is not an answer")
local again = GuildOS:ShowDialog("T", 2, "Cy", "second")
check(again == d and #log == 0 and d.data == "second", "asked again: the same frame, the first neither accepted nor cancelled")
local other = GuildOS:ShowDialog("GUILDOS_STYLE_RELOAD", "Reload?")
check(other ~= d and other:IsShown() and d:IsShown(), "a different question gets a frame of its own")
other:Hide(); d.button1.scripts.OnClick()

-- ── The timeout only closes the showing it was set for ──────────────────
GuildOS.Dialogs.TIMED = { text = "%s", button1 = "Yes", timeout = 60, OnCancel = function() log[#log + 1] = "timeout" end }
log, timers = {}, {}
d = GuildOS:ShowDialog("TIMED", "one")
d.button1.scripts.OnClick()
d = GuildOS:ShowDialog("TIMED", "two")
timers[1]()
check(d:IsShown() and #log == 0, "the first showing's timer leaves the second alone")
timers[2]()
check(not d:IsShown() and log[1] == "timeout", "its own timer closes it, as a cancel")

-- ── The edit box, as the note dialogs use it ────────────────────────────
local saved
GuildOS.Dialogs.NOTE = {
  text = "Note for %s", button1 = "Save", hasEditBox = true, maxLetters = 31,
  OnShow = function(self) GuildOS.Compat.PopupEditBox(self):SetText("old") end,
  OnAccept = function(self, data) saved = data .. "=" .. GuildOS.Compat.PopupEditBox(self):GetText() end,
  EditBoxOnEnterPressed = function(box, data)
    saved = "enter:" .. data .. "=" .. box:GetText()
    box:GetParent():Hide()
  end,
}
d = GuildOS:ShowDialog("NOTE", "Ana", nil, "Ana-Realm")
local box = GuildOS.Compat.PopupEditBox(d)
check(box and box:IsShown() and box.focused and box.maxLetters == 31 and box:GetText() == "old", "the box is shown, focused, capped, and OnShow fills it after it was emptied")
box:SetText("new"); d.button1.scripts.OnClick()
check(saved == "Ana-Realm=new", "Save reads the box")
d = GuildOS:ShowDialog("NOTE", "Ana", nil, "Ana-Realm")
box:SetText("typed"); box.scripts.OnEnterPressed(box)
check(saved == "enter:Ana-Realm=typed" and not d:IsShown(), "Enter goes to the definition's handler, with the data")
GuildOS.Dialogs.NOTE.EditBoxOnEnterPressed = nil
d = GuildOS:ShowDialog("NOTE", "Ana", nil, "Ana-Realm")
box:SetText("plain"); box.scripts.OnEnterPressed(box)
check(saved == "Ana-Realm=plain", "with no handler of its own, Enter is Save")
d = GuildOS:ShowDialog("NOTE", "Ana", nil, "Ana-Realm")
box.scripts.OnEscapePressed(box)
check(not d:IsShown() and saved == "Ana-Realm=plain", "Escape in the box closes it and saves nothing")

print(("dialog: %d checks passed"):format(checks))
