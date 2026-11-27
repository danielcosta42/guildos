-- The fonts (the Salão's phase 3, #449; the game's font of issue #57 before), run against the real
-- Core/Data.lua.
--
-- GuildOS draws its text in the mockup's three fonts: Cinzel for titles, Alegreya Sans for the interface,
-- Alegreya for reading, unless the player ticks "Use the game's font" (Settings > Interface, saved as
-- GuildOSDB.gameFont). A title in another script than Latin takes a face that has it.
--
--   luajit -e 'ADDON="."' tools/game-font.lua
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

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GuildOS = {}
dofile(ADDON .. "/Core/Data.lua")
local F = GuildOS.Fonts

local function fontString()
  local fs = {}
  function fs:SetFont(file, size, flags) self.file, self.size, self.flags = file, size, flags end
  return fs
end
local function apply(size, role)
  local fs = fontString()
  local file, px = GuildOS:ApplyFont(fs, size, role)
  check(fs.file == file and fs.size == px, "ApplyFont returns what it set")
  return fs
end

-- ── The Salão's fonts (phase 3, #449) ────────────────────────────────────
-- Cinzel Bold for titles, Alegreya Sans for the interface, Alegreya for reading. The game's font is no
-- longer anyone's choice (#445 took the switch away, phase 3 the forced game font): a saved
-- GuildOSDB.font = "game" from before draws in the addon's fonts like everyone else.
for _, db in ipairs({ {}, { font = "game" } }) do
  GuildOSDB = db
  local what = db.font and "a saved game font, ignored: " or ""
  check(apply(18).file == F.ui and F.ui:find("AlegreyaSans%-Regular"), what .. "18px is Alegreya Sans")
  check(apply(nil, "colHeader").file == F.title and F.title:find("Cinzel%-Bold"), what .. "a header is Cinzel Bold")
  check(apply(nil, "button").file == F.uiBold and F.uiBold:find("AlegreyaSans%-Bold"), what .. "a button is Alegreya Sans Bold")
  check(apply(nil, "memberName").file == F.uiMedium, what .. "a name is Alegreya Sans Medium")
  check(apply(nil, "reading").file == F.read and F.read:find("Alegreya%-Regular"), what .. "a text to read is Alegreya")
end
GuildOSDB = nil
check(apply(18).file == F.ui, "before the SavedVariables load, the same fonts")

-- Sizes: a size asked for draws one larger in Alegreya Sans (its small body), never under 11px; a title as asked,
-- never under 10px; a role's own size as it is.
local fs = apply(12)
check(fs.size == 13 and fs.flags == "", "12px asked is 13px drawn, no outline")
check(apply(7).size == 11, "nothing under the floor, 11px")
check(apply(nil, "body").size == F.body.size, "a role keeps its size")
check(apply(8, "colHeader").size == 10, "a title never under 10px")
check(apply(14, "sectionTitle").size == 14, "a title asked 14 is 14")

-- A title's text in another script draws in the interface's bold face, which has it; Latin stays in Cinzel.
local t = fontString()
GuildOS:ApplyFont(t, nil, "windowTitle")
function t:SetText(x) self.text = x end
GuildOS:SetTitleText(t, "Abaixo da Curva")
check(t.file == F.title and t.text == "Abaixo da Curva", "a Latin guild name is in Cinzel")
GuildOS:SetTitleText(t, "\208\147\208\184\208\187\209\140\208\180\208\184\209\143")
check(t.file == F.uiBold, "a Cyrillic one in Alegreya Sans Bold")
GuildOS:SetTitleText(t, "Guardi\195\181es \226\128\148 Forte")
check(t.file == F.title, "accents and a dash are still Latin")
check(GuildOS.IsLatinText("\234\184\184\235\147\156") == false, "Hangul is not")

-- Every title that is handed a player's or a site's text sets it through SetTitleText (#449): a guild, a
-- player or an event named in Cyrillic or Greek would draw as boxes in Cinzel on a non-ruRU client.
local function read(path)
  local fh = assert(io.open(ADDON .. "/" .. path, "rb"))
  local src = fh:read("*a")
  fh:close()
  return src
end
for _, site in ipairs({
  { "UI/MemberDetail.lua", "GuildOS:SetTitleText(frame.nameText," },
  { "UI/OfficerSheet.lua", "GuildOS:SetTitleText(f.title, string.format(L[\"Officer sheet: %s\"]" },
  { "UI/GuildFinder.lua", "GuildOS:SetTitleText(gname, ad.n)" },
  { "UI/GuildFinder.lua", "GuildOS:SetTitleText(shieldText, initial(ad.n))" },
  { "UI/GuildFinder.lua", "GuildOS:SetTitleText(stateTitle, head)" },
  { "UI/AlliancePanel.lua", "GuildOS:SetTitleText(title, name == pact.tag" },
  { "UI/GuildBankPanel.lua", "GuildOS:SetTitleText(title, string.format(\"%d \194\183 %s\"" },
  { "UI/WebPanel.lua", "GuildOS:SetTitleText(prompt.title," },
  { "Modules/CallToArms.lua", "GuildOS:SetTitleText(f.title, e.title)" },
  { "UI/AchievementsPanel.lua", "GuildOS:SetTitleText(nameFS, name or renown)" },
  { "UI/WarnDialog.lua", "GuildOS:SetTitleText(title, string.format(L[\"Warn %s\"], name))" },
  { "UI/RaidPlanPanel.lua", "GuildOS:SetTitleText(task.title, boss)" },
}) do
  check(read(site[1]):find(site[2], 1, true), site[1] .. " sets its title through SetTitleText: " .. site[2])
end
for _, bad in ipairs({
  { "UI/GuildFinder.lua", "gname:SetText(" }, { "UI/MemberDetail.lua", "frame.nameText:SetText(" },
  { "Modules/CallToArms.lua", "f.title:SetText(" }, { "UI/WebPanel.lua", "prompt.title:SetText(" },
}) do
  check(not read(bad[1]):find(bad[2], 1, true), bad[1] .. " no longer sets a title with SetText: " .. bad[2])
end

-- "Use the game's font" again (Settings > Interface, Discord 1556991354478010459): GuildOSDB.gameFont = true,
-- read once by Style:Resolve, draws every text in the game's face (titles in its quest-title font). The old
-- GuildOSDB.font = "game" stays ignored (above), so nobody is switched back to it unasked.
GuildOS.Style = { gameFont = true }
check(GuildOS:UsesGameFont(), "the choice read at load turns the game's font on")
check(apply(18).file == STANDARD_TEXT_FONT, "chosen: the interface's text is the game's font")
check(apply(nil, "reading").file == STANDARD_TEXT_FONT, "chosen: a text to read too")
QuestTitleFont = { GetFont = function() return "Fonts\\MORPHEUS.TTF", 14 end }
check(apply(nil, "windowTitle").file == "Fonts\\MORPHEUS.TTF", "chosen: a title takes the game's title face")
QuestTitleFont = nil
GuildOS.Style = { gameFont = false }
check(not GuildOS:UsesGameFont() and apply(18).file == F.ui, "not chosen: the addon's fonts")
GuildOS.Style = nil

print(("game-font: %d checks passed"):format(checks))
