-- Names the saved data keeps in English are shown in the reader's language (issue #114), run
-- against the real Locales and Modules/ModPresets.lua as a French client.
--
-- A member's professions are stored by their English name, so that every client agrees on
-- them, and they were shown as stored: "Métiers : Cooking 98 / 150" on a French client. The
-- moderation presets saved the name they were created with, so a guild whose presets were
-- seeded before the French existed read "Purge inactive" for good. Both are now shown through
-- L, and every screen that showed them raw is checked here.
--
--   luajit -e 'ADDON="."' tools/stored-names.lua
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
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

BRutus = {}
function GetLocale() return "frFR" end
dofile(ADDON .. "/Locales/Locale.lua")
dofile(ADDON .. "/Locales/frFR.lua")
local L = BRutus.L

-- ── Professions ─────────────────────────────────────────────────────────
for en, fr in pairs({ Tailoring = "Couture", Enchanting = "Enchantement", ["First Aid"] = "Secourisme",
                      Jewelcrafting = "Joaillerie", Poisons = "Poisons" }) do
  check(L[en] == fr, en .. " reads " .. fr .. " in French")
end

-- Every screen that shows a stored profession shows it through L.
for path, raw in pairs({
  ["UI/RosterFrame.lua"]  = { "Utf8Head(prof.name,", "%s  %d / %d\", prof.name,", "(\"  \" .. prof.name)" },
  ["UI/MemberDetail.lua"] = { "SetText(prof.name)" },
  ["UI/RecipesPanel.lua"] = { "Utf8Head(profName, 3)", "SetText(profName, 1, 1, 1)", "SetText(entry.profName or \"\")" },
  ["UI/CraftFinder.lua"]  = { "AddResult(c.playerName, c.profName,", "local label = c.prof or \"?\"",
                              "AddResult(short, label, L[\"Realm\"]" },
  ["Modules/RecipeTracker.lua"] = { "status, c.profName, cc.r", "#recipes, profName))" },
  ["UI/AlliancePanel.lua"] = { "p.n or \"?\", p.r" },                  -- an ally member's card
  ["Core/Commands.lua"]    = { "itemName, c.prof or \"?\")", "itemName, label or \"?\"))" },
}) do
  local src = read(path)
  for _, s in ipairs(raw) do
    check(not src:find(s, 1, true), path .. " shows no stored profession raw: " .. s)
  end
end

-- ── Moderation presets ──────────────────────────────────────────────────
function BRutus:Print() end
function BRutus:IsOfficer() return true end
BRutus.db = { modPresets = { { type = "purge_inactive", name = "Purge inactive", thresholds = {} },
                             { type = "promote_regulars", name = "Promote regulars", thresholds = {} },
                             { type = "gone", name = "Old one", thresholds = {} } } }
dofile(ADDON .. "/Modules/ModPresets.lua")
local MP = BRutus.ModPresets
local P = MP:GetPresets()
check(MP:Name(P[1]) == "Purge des membres inactifs" and MP:Name(P[2]) == "Promouvoir les membres réguliers",
  "a preset saved with its English name reads in French")
check(MP:Name(P[3]) == "Old one" and MP:Name({}) == "?", "one of no known type keeps the name it has")
local ui = read("UI/ManagementPanel.lua")
check(not ui:find("preset.name or \"?\"", 1, true), "the presets screen shows the name from MP:Name")

-- The login reminder lists them translated, keeping the English names as its keys.
check(read("Core/Utils.lua"):find("shown[i] = L[name]", 1, true), "the login reminder shows the professions translated")

-- Forever's crafters carry the English name, as Anniversary's, so they are translated once.
check(not read("Modules/ProfDirectory.lua"):find("profName = line and ProfDirectory.DisplayName(line)", 1, true),
  "Forever's crafter list names the profession in English, for the screens to translate")

-- ── The publishing toggle reads as one word in French ───────────────────
check(L["On"] == "active" and L["Off"] == "inactive", "Publication active / inactive")
check(not read("UI/ManagementPanel.lua"):find('return L["Off"], C.textDim', 1, true) and L["Opted out"] == "Désinscrit",
  "a member's engagement status has its own word, not the toggle's")

print(("stored-names: %d checks passed"):format(checks))
