# Professions foundation (WoW: Forever) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every guild member's professions, levels and recipes back on WoW: Forever, by ID, collected without opening a window and synced by hash.

**Architecture:** A generated static catalog (`Data/ProfCatalogForever.lua`) lists every Forever recipe by ID. `Modules/Professions.lua` reads the player's own professions (`GetProfessionInfo`) and recipes (`IsPlayerSpell` over the catalog), keeps a per-member model (addon records plus native Communities-roster records), and projects it into the legacy `members[].professions` / `db.recipes` shapes. `Modules/ProfSync.lua` is the `prof` SyncService domain: summaries with a hash per profession, lists fetched only when a hash changes. Everything loads only on Forever.

**Tech Stack:** Lua 5.1 (WoW addon), LibSerialize/LibDeflate (bundled), SyncService v2, Python 3 (catalog generator), luajit harnesses, luacheck.

**Spec:** `docs/superpowers/specs/2026-09-27-professions-foundation-design.md`

## Global Constraints

- Forever only: every new file starts with `if BRutus.Client.isAnniversary then return end`; Anniversary behaviour and data do not change.
- Professions keyed by skill-line ID, recipes by recipe (spell) ID; never by name.
- Version-sensitive API only through `Core/Compat.lua` (`tools/compat-guard.lua` enforces it).
- No `UnitName("player")` outside Compat (use `BRutus.Compat.PlayerName()`); no hand-built `.. "-" ..` member keys (use `BRutus:GetPlayerKey`).
- Caps: 7 lines per member, 1,500 recipe IDs and 200 extra IDs per line, IDs in 1..2^31-1.
- Received data: key from the sender, sender must be in the guild roster, malformed data dropped without raising.
- Sync timings: summary at login + 5–15s, 10s after a change, every 600s; `ask` answered after 1–8s; `req` after 2–6s; requests aggregated for 3s.
- Checks that must stay green: `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc`, `luajit tools/compat-guard.lua`, every `luajit -e 'ADDON="."' tools/<x>.lua`, every `python tools/*.py`.

## Review Focus

- A guildmate on 0.56.x (no `prof` domain, `absent.professions` in `BC`) next to one on this version: the old one must not wipe the new one's professions, and the new one shows the old one natively. Pinned in Task 5 (`CollectProfessions` never returns nil on Forever).
- A beta build newer than the catalog (recipe IDs the catalog lacks): they are kept as `extra` from the own window and synced. Pinned in Task 3.
- A profession with no rank (native record) reaching the roster, member detail and export: it renders as its name and is not exported. Pinned in Task 5.
- Thirty members logging in together asking one crafter for the same list: one guild answer, not thirty whispers. Pinned in Task 4.
- A lost list reply: the next summary asks again after 120s instead of never. Pinned in Task 4.

## File map

| File | Responsibility |
|---|---|
| `tools/prof_catalog.py` (new) | Generator from wago DB2 CSVs; no args = self-test on the fixture |
| `tools/prof-catalog-fixture/*.csv` (new) | Tiny DB2 subset for the self-test |
| `Data/ProfCatalogForever.lua` (new, generated) | `BRutus.ProfCatalog` |
| `Core/Compat.lua` | `GetProfessions`, `GetProfessionInfo`, `IsPlayerSpell`, `TradeSkillLearned`, `GuildMemberProfessions` |
| `Modules/Professions.lua` (new) | collection, model, native, query API, legacy adapter |
| `Modules/ProfSync.lua` (new) | `prof` domain |
| `Modules/DataCollector.lua` | `CollectProfessions` from Professions; no recipes in `BC` on Forever |
| `Core/Utils.lua` | reminder off on Forever; prune `db.professions` |
| `UI/RosterFrame.lua`, `UI/MemberDetail.lua`, `Modules/CompanionExport.lua` | rankless professions |
| `Core/Core.lua` | `MODULE_START` entries |
| `Core/Probe.lua` | new APIs + catalog/extra facts |
| `GuildOS.toc`, `.luacheckrc`, `tools/compat-guard.lua` | wiring |
| `tools/professions.lua` (new) | harness |

---

### Task 1: Catalog generator and generated catalog

**Files:**
- Create: `tools/prof_catalog.py`, `tools/prof-catalog-fixture/<Table>.fixture.csv` (10 tables), `Data/ProfCatalogForever.lua`
- Modify: `GuildOS.toc` (add `Data\ProfCatalogForever.lua` after `Modules\CraftNet.lua`), `.luacheckrc` (`exclude_files` += `"Data/ProfCatalogForever.lua"`)

**Interfaces:**
- Produces: `BRutus.ProfCatalog = { build, F = { line=1, yellow=2, grey=3, out=4, outCount=5, enchant=6, reqSkill=7, spec=8, focus=9, src=10, recipeItem=11, category=12, reagents=13 }, professions[line] = { child, primary, en }, specs[spellID] = line, stations[focusID] = englishName, byLine[line] = { sorted recipeIDs }, recipes[recipeID] = { positional per F } }`. `src`: 1 trainer/other, 2 recipe item, 3 automatic.

- [ ] **Step 1: Build the fixture** — filter the real 1.60.1.70009 CSVs (downloaded to the scratchpad `db2/` folder as `<Table>.forever.csv`) down to: SkillLine rows 164, 186, 2938, 2946, 2933; SkillLineAbility rows for spells 2657 (Smelt Copper), 3304, one Blacksmithing plan taught by a recipe item with `RequiredAbility` 9788, one Enchanting-effect recipe if present on those lines, one `AcquireMethod` 3 row, one rank spell (no create effect), one row on line 2933; and every SpellEffect/SpellReagents/SpellCastingRequirements/SpellFocusObject/Item/ItemSparse/ItemEffect/ItemXItemEffect row those spells and recipe items reference. Write them to `tools/prof-catalog-fixture/<Table>.fixture.csv` with the original headers.

- [ ] **Step 2: Write the generator with its self-test first (fails: no module)**

`tools/prof_catalog.py`:
```python
"""Static profession catalog for WoW: Forever from wago.tools DB2 exports (issue #31).

    python tools/prof_catalog.py                           # self-test on tools/prof-catalog-fixture/
    python tools/prof_catalog.py <build> [--cache <dir>]   # writes Data/ProfCatalogForever.lua

Recipes sit on the parent profession skill line. Each recipe keeps IDs and numbers only; the
client localizes names at run time. Rerun on every beta build.
"""
import collections, csv, io, os, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Data", "ProfCatalogForever.lua")
FIXTURE = os.path.join(HERE, "prof-catalog-fixture")
TABLES = ["SkillLine", "SkillLineAbility", "SpellEffect", "SpellReagents", "SpellCastingRequirements",
          "SpellFocusObject", "Item", "ItemSparse", "ItemEffect", "ItemXItemEffect"]
# Forever's twelve professions. Poisons (40) and Comprehension (3012) are class skills,
# 2933/2934 is Blizzard's test profession. Primary = SkillLine category 11.
PROFESSIONS = [129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393]
FIELDS = ["line", "yellow", "grey", "out", "outCount", "enchant", "reqSkill", "spec", "focus", "src",
          "recipeItem", "category", "reagents"]


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


def read_csv(text):
    return list(csv.DictReader(io.StringIO(text)))


def fetch(table, build, cache):
    path = os.path.join(cache, f"{table}.{build}.csv") if cache else None
    if path and os.path.exists(path):
        return open(path, encoding="utf-8").read()
    url = f"https://wago.tools/db2/{table}/csv?build={build}"
    req = urllib.request.Request(url, headers={"User-Agent": "guildos-prof-catalog/1.0"})
    text = urllib.request.urlopen(req, timeout=300).read().decode("utf-8")
    if path:
        os.makedirs(cache, exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    return text


def build_catalog(t):
    skill = {num(r["ID"]): r for r in t["SkillLine"]}
    children = {}
    for r in t["SkillLine"]:
        parent = num(r.get("ParentSkillLineID"))
        if parent in PROFESSIONS:
            children.setdefault(parent, num(r["ID"]))
    professions = {line: {"child": children.get(line, 0), "primary": num(skill[line].get("CategoryID")) == 11,
                          "en": skill[line].get("DisplayName_lang", "")}
                   for line in PROFESSIONS if line in skill}
    effects = collections.defaultdict(list)
    for r in t["SpellEffect"]:
        effects[num(r["SpellID"])].append(r)
    count_key = "EffectBasePointsF" if t["SpellEffect"] and "EffectBasePointsF" in t["SpellEffect"][0] else "EffectBasePoints"
    reagents = {num(r["SpellID"]): r for r in t["SpellReagents"]}
    focus = {num(r["SpellID"]): num(r.get("RequiresSpellFocus")) for r in t["SpellCastingRequirements"]}
    focus_names = {num(r["ID"]): r.get("Name_lang", "") for r in t["SpellFocusObject"]}
    sparse = {num(r["ID"]): r for r in t["ItemSparse"]}
    item_effect = {num(r["ID"]): r for r in t["ItemEffect"]}
    effects_of_item = collections.defaultdict(list)
    for r in t["ItemXItemEffect"]:
        e = item_effect.get(num(r["ItemEffectID"]))
        if e:
            effects_of_item[num(r["ItemID"])].append(e)
    taught_by = collections.defaultdict(list)   # recipe spell -> recipe items (item class 9, trigger 6 = learn)
    for r in t["Item"]:
        if num(r.get("ClassID")) != 9:
            continue
        for e in effects_of_item.get(num(r["ID"]), []):
            if num(e.get("TriggerType")) == 6 and num(e.get("SpellID")):
                taught_by[num(e["SpellID"])].append(num(r["ID"]))
    recipes, by_line, specs = {}, collections.defaultdict(list), {}
    for r in t["SkillLineAbility"]:
        line, spell = num(r["SkillLine"]), num(r["Spell"])
        if line not in professions or num(r.get("AcquireMethod")) == 3:
            continue
        effs = effects.get(spell, [])
        creates = [e for e in effs if num(e["Effect"]) == 24 and num(e.get("EffectItemType"))]
        enchant = [e for e in effs if num(e["Effect"]) in (53, 54)]
        if not creates and not enchant:
            continue
        items = sorted(taught_by.get(spell, []))
        req = [sparse.get(i, {}) for i in items]
        spec = next((num(s.get("RequiredAbility")) for s in req if num(s.get("RequiredAbility"))), 0)
        if spec:
            specs[spec] = line
        acquire = num(r.get("AcquireMethod"))
        rg = reagents.get(spell, {})
        flat = []
        for i in range(8):
            rid, cnt = num(rg.get(f"Reagent_{i}")), num(rg.get(f"ReagentCount_{i}"))
            if rid and cnt:
                flat += [rid, cnt]
        recipes[spell] = [
            line, num(r.get("TrivialSkillLineRankLow")), num(r.get("TrivialSkillLineRankHigh")),
            num(creates[0]["EffectItemType"]) if creates else 0,
            max(1, num(creates[0].get(count_key))) if creates else 0,
            num(enchant[0].get("EffectMiscValue_0")) if enchant else 0,
            min((num(s.get("RequiredSkillRank")) for s in req), default=0),
            spec, focus.get(spell, 0),
            3 if acquire in (1, 2) else 2 if items else 1,
            items[0] if items else 0,
            num(r.get("TradeSkillCategoryID")),
            flat,
        ]
        by_line[line].append(spell)
    stations = {f: focus_names.get(f, "") for f in sorted({v[8] for v in recipes.values() if v[8]})}
    return {"professions": professions, "recipes": recipes, "specs": specs, "stations": stations,
            "byLine": {line: sorted(ids) for line, ids in by_line.items()}}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(cat, build):
    out = [f"-- Generated by tools/prof_catalog.py from wago.tools DB2, build {build}. Do not edit.",
           "-- WoW: Forever professions (issue #31): IDs and numbers only; the client localizes names.",
           "if BRutus.Client.isAnniversary then return end", "",
           "BRutus.ProfCatalog = {", f"    build = {lua_str(build)},",
           "    F = { " + ", ".join(f"{f} = {i + 1}" for i, f in enumerate(FIELDS)) + " },",
           "    professions = {"]
    for line, p in sorted(cat["professions"].items()):
        out.append(f"        [{line}] = {{ child = {p['child']}, primary = {'true' if p['primary'] else 'false'}, "
                   f"en = {lua_str(p['en'])} }},")
    out += ["    },", "    specs = {"] + [f"        [{s}] = {l}," for s, l in sorted(cat["specs"].items())]
    out += ["    },", "    stations = {"] + [f"        [{f}] = {lua_str(n)}," for f, n in sorted(cat["stations"].items())]
    out += ["    },", "    byLine = {"]
    out += [f"        [{line}] = {{{','.join(map(str, ids))}}}," for line, ids in sorted(cat["byLine"].items())]
    out += ["    },", "    recipes = {"]
    for spell, v in sorted(cat["recipes"].items()):
        out.append(f"        [{spell}] = {{{','.join(map(str, v[:-1]))},{{{','.join(map(str, v[-1]))}}}}},")
    out += ["    },", "}", ""]
    return "\n".join(out)


def selftest():
    t = {name: read_csv(open(os.path.join(FIXTURE, f"{name}.fixture.csv"), encoding="utf-8").read()) for name in TABLES}
    cat = build_catalog(t)
    F = {f: i for i, f in enumerate(FIELDS)}
    assert cat["professions"][186] == {"child": 2946, "primary": True, "en": "Mining"}, cat["professions"].get(186)
    assert 2933 not in cat["professions"], "the test profession is not a profession"
    smelt = cat["recipes"][2657]
    assert smelt[F["line"]] == 186 and smelt[F["out"]] == 2840 and smelt[F["outCount"]] == 1, smelt
    assert smelt[F["reagents"]] == [2770, 1], smelt
    assert all(ids == sorted(ids) for ids in cat["byLine"].values()), "byLine is sorted"
    assert all(cat["recipes"][i][F["line"]] == line for line, ids in cat["byLine"].items() for i in ids)
    assert cat["specs"].get(9788) == 164, cat["specs"]
    plan = [v for v in cat["recipes"].values() if v[F["spec"]] == 9788]
    assert plan and plan[0][F["src"]] == 2 and plan[0][F["recipeItem"]] > 0 and plan[0][F["reqSkill"]] > 0, plan
    retired = [r for r in t["SkillLineAbility"] if num(r.get("AcquireMethod")) == 3]
    assert retired and all(num(r["Spell"]) not in cat["recipes"] for r in retired), "retired rows are left out"
    lua = render(cat, "fixture")
    assert lua.startswith("-- Generated") and "if BRutus.Client.isAnniversary then return end" in lua
    assert "[2657] = {186," in lua and 'en = "Mining"' in lua
    print(f"prof_catalog: self-test passed ({len(cat['recipes'])} fixture recipes)")


def main(argv):
    if not argv:
        return selftest()
    build = argv[0]
    cache = argv[argv.index("--cache") + 1] if "--cache" in argv else None
    cat = build_catalog({name: read_csv(fetch(name, build, cache)) for name in TABLES})
    open(OUT, "w", encoding="utf-8", newline="\n").write(render(cat, build))
    print(f"{OUT}: {len(cat['recipes'])} recipes on {len(cat['byLine'])} lines, "
          f"{len(cat['specs'])} specializations, {len(cat['stations'])} stations")


if __name__ == "__main__":
    main(sys.argv[1:])
```

- [ ] **Step 3: Run the self-test**

Run: `python tools/prof_catalog.py`
Expected: `prof_catalog: self-test passed (N fixture recipes)`. If an assertion names a fixture value (e.g. the plan's recipe item), fix the fixture selection from Step 1, not the assertion's intent.

- [ ] **Step 4: Generate the real catalog** — copy the scratchpad CSVs to a cache dir as `<Table>.1.60.1.70009.csv` (download the missing ones), then:

Run: `python tools/prof_catalog.py 1.60.1.70009 --cache <cache>`
Expected: `~2,500 recipes on 12 lines, ~10 specializations, N stations`.

- [ ] **Step 5: Wire it** — `GuildOS.toc`: add `Data\ProfCatalogForever.lua` right after `Modules\CraftNet.lua`; `.luacheckrc` `exclude_files`: add `"Data/ProfCatalogForever.lua",  -- generated data (tools/prof_catalog.py)`.

- [ ] **Step 6: Commit** — `git add tools/prof_catalog.py tools/prof-catalog-fixture Data/ProfCatalogForever.lua GuildOS.toc .luacheckrc && git commit -m "feat: catálogo estático das profissões do Forever (#31)"`

---

### Task 2: Compat wrappers, guard, luacheck, probe

**Files:**
- Modify: `Core/Compat.lua` (after `Compat.GetSkillLineInfo`), `tools/compat-guard.lua` (`GLOBALS` += `"GetProfessions", "GetProfessionInfo"`; `NAMESPACES` += `"C_TradeSkillUI", "C_Club"`), `.luacheckrc` (read_globals += `"GetProfessions", "GetProfessionInfo", "IsPlayerSpell", "C_Club"` where missing), `Core/Probe.lua` (APIS += `"GetProfessions", "GetProfessionInfo", "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.IsDataSourceChanging", "C_Club.GetGuildClubId", "C_Club.GetMemberInfo"` where missing; `Run` records `r.professions`)
- Test: `tools/professions.lua` (created here, extended by later tasks)

**Interfaces:**
- Produces: `Compat.GetProfessions() -> idx...`, `Compat.GetProfessionInfo(i) -> name, icon, rank, maxRank, numSpells, spellOffset, skillLine, ...`, `Compat.IsPlayerSpell(id) -> bool`, `Compat.TradeSkillLearned() -> line, {ids} | nil`, `Compat.GuildMemberProfessions() -> { {name, lines = {line...}} } | nil`.

- [ ] **Step 1: Create the harness with the Forever client stub and the Compat checks (fails: wrappers missing)**

`tools/professions.lua` (the preamble below is shared by every later task):
```lua
-- Professions on WoW: Forever (issue #31), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/Professions.lua, Modules/ProfSync.lua and DataCollector's hooks, under a
-- stubbed Forever client, a fixture catalog and a fake SyncService bus.
--
--   luajit -e 'ADDON="."' tools/professions.lua
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

-- ── The client: WoW: Forever ────────────────────────────────────────────
local NOW = 1790500000
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
local function runTimers()
  local guard = 0
  while #timers > 0 do
    guard = guard + 1
    assert(guard < 1000, "timer loop")
    table.remove(timers, 1)()
  end
end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end
function GetServerTime() return NOW end
function time() return NOW end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetRealmName() return "Classic Beta PvE 2" end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function UnitName(u) if u == "player" then return "Ana" end end
function UnitFullName(u) if u == "player" then return "Ana", "Silva" end end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }

-- The player's professions: GetProfessions() slots, GetProfessionInfo rows, known spells.
local SLOTS, PROFS, KNOWN = {}, {}, {}
function GetProfessions() return SLOTS[1], SLOTS[2], SLOTS[3], SLOTS[4], SLOTS[5] end
function GetProfessionInfo(i)
  local p = PROFS[i]
  if p then return p[1], 0, p[2], p[3], 0, 0, p[4], 0, -1, 0, p[1] end
end
function IsPlayerSpell(id) return KNOWN[id] == true end
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }

-- The profession window: nil when closed.
local WINDOW
C_TradeSkillUI = {
  IsDataSourceChanging = function() return false end,
  IsTradeSkillLinked = function() return WINDOW and WINDOW.linked or false end,
  IsTradeSkillGuild = function() return false end,
  IsTradeSkillGuildMember = function() return false end,
  GetBaseProfessionInfo = function() return { professionID = WINDOW and WINDOW.line or 0 } end,
  GetAllRecipeIDs = function() return WINDOW and WINDOW.all or {} end,
  GetRecipeInfo = function(id)
    for _, x in ipairs(WINDOW and WINDOW.learned or {}) do if x == id then return { learned = true } end end
    return { learned = false }
  end,
}

-- The guild: roster names and the Communities roster's profession fields.
local ROSTER = { "Ana Silva", "Bob", "Cid", "Dee" }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  if ROSTER[i] then return ROSTER[i], "Member", 3, 20, "Mage", "", "", "", true, 0, "MAGE" end
end
local CLUB = {}
C_Club = {
  GetGuildClubId = function() return 7 end,
  GetClubMembers = function() local t = {}; for i in ipairs(CLUB) do t[i] = i end; return t end,
  GetMemberInfo = function(_, i) return CLUB[i] end,
}

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local Compat = BRutus.Compat

-- ── 1. Compat ───────────────────────────────────────────────────────────
check(not BRutus.Client.isAnniversary, "the stub is a Forever client")
SLOTS = { 1, nil, 2 }
check(select("#", Compat.GetProfessions()) == 5 and select(3, Compat.GetProfessions()) == 2,
      "GetProfessions passes every slot through, nils included")
PROFS[1] = { "Mineração", 21, 75, 186 }
check(select(7, Compat.GetProfessionInfo(1)) == 186 and select(3, Compat.GetProfessionInfo(1)) == 21,
      "GetProfessionInfo passes rank and skill line through")
KNOWN[2657] = true
check(Compat.IsPlayerSpell(2657) == true and Compat.IsPlayerSpell(1) == false, "IsPlayerSpell is a boolean")
check(Compat.TradeSkillLearned() == nil, "no window, no learned list")
WINDOW = { line = 186, all = { 2657, 3304 }, learned = { 2657 } }
local line, learned = Compat.TradeSkillLearned()
check(line == 186 and #learned == 1 and learned[1] == 2657, "the own window gives its line and learned IDs")
WINDOW.linked = true
check(Compat.TradeSkillLearned() == nil, "a linked (someone else's) window is ignored")
WINDOW = nil
CLUB = { { name = "Bob", profession1ID = 186, profession2ID = 0 }, { name = "Cid", profession1ID = 164, profession2ID = 185 } }
local club = Compat.GuildMemberProfessions()
check(#club == 2 and club[1].name == "Bob" and #club[1].lines == 1 and #club[2].lines == 2,
      "the Communities roster gives each member's profession lines, zeros dropped")
issecretvalue = function(v) return v == "Cid" end
check(#Compat.GuildMemberProfessions() == 1, "a member whose fields are secret is skipped")
issecretvalue = nil
local saved = GetProfessions
GetProfessions = nil
check(select("#", Compat.GetProfessions()) == 0, "no API, nothing")
GetProfessions = saved
CLUB, SLOTS, PROFS, KNOWN = {}, {}, {}, {}

print("professions: " .. checks .. " checks passed")
```

- [ ] **Step 2: Run it to see it fail**

Run: `luajit -e 'ADDON="."' tools/professions.lua`
Expected: an error on `Compat.GetProfessions` (nil) or `FAIL: GetProfessions passes every slot through`.

- [ ] **Step 3: Add the wrappers** — in `Core/Compat.lua` after `Compat.GetSkillLineInfo`:
```lua
----------------------------------------------------------------------
-- Professions on the retail tradeskill API (WoW: Forever, issue #31)
----------------------------------------------------------------------

-- The spell-book indices of the player's professions (two primaries, First Aid, Fishing,
-- Cooking, ...), nils included; nothing on a client without the API.
function Compat.GetProfessions()
    if not GetProfessions then return end
    return GetProfessions()
end

-- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, ... for a GetProfessions index.
function Compat.GetProfessionInfo(index)
    if not GetProfessionInfo then return nil end
    return GetProfessionInfo(index)
end

-- Whether the player knows a spell. On Forever this answers for a recipe with the profession
-- window closed (verified 2026-09-27); C_SpellBook.IsSpellInSpellBook does not.
function Compat.IsPlayerSpell(spellID)
    if not IsPlayerSpell then return false end
    return IsPlayerSpell(spellID) and true or false
end

-- The profession window's skill line and learned recipe IDs, when it shows the player's OWN
-- profession and its data has settled. Nothing for a linked or guild view, a window still
-- loading, or a client without the API.
function Compat.TradeSkillLearned()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return nil end
    if T.IsDataSourceChanging and T.IsDataSourceChanging() then return nil end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember()) then
        return nil
    end
    local base = T.GetBaseProfessionInfo()
    local line = base and base.professionID
    if not line or line == 0 then return nil end
    local learned = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then learned[#learned + 1] = id end
    end
    return line, learned
end

-- Every guild member's primary professions as the Communities roster reports them, addon or
-- not: { { name = "First Last", lines = { skillLine, ... } }, ... }. The rank it gives is always
-- 1 on Forever and is left out. Secret fields (chat messaging lockdown) skip the member.
function Compat.GuildMemberProfessions()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end
    local ids = C_Club.GetClubMembers(clubId)
    if Compat.IsSecret(ids) or type(ids) ~= "table" then return nil end
    local out = {}
    for _, memberId in ipairs(ids) do
        local m = C_Club.GetMemberInfo(clubId, memberId)
        if m and not Compat.IsSecret(m.name, m.profession1ID, m.profession2ID) and type(m.name) == "string" then
            local lines = {}
            if type(m.profession1ID) == "number" and m.profession1ID > 0 then lines[#lines + 1] = m.profession1ID end
            if type(m.profession2ID) == "number" and m.profession2ID > 0 then lines[#lines + 1] = m.profession2ID end
            out[#out + 1] = { name = m.name, lines = lines }
        end
    end
    return out
end
```

- [ ] **Step 4: Guard, luacheck, probe** — `tools/compat-guard.lua`: add `"GetProfessions", "GetProfessionInfo"` to `GLOBALS` and `"C_TradeSkillUI", "C_Club"` to `NAMESPACES`. `.luacheckrc` read_globals: add the missing ones of `"GetProfessions"`, `"GetProfessionInfo"`, `"IsPlayerSpell"`, `"C_Club"`. `Core/Probe.lua`: add the missing API names listed in **Files**; in `Probe:Run`, before `r.apis, r.missingApis = {}, {}`:
```lua
    -- WoW: Forever professions (issue #31): which catalog build the client carries, and how many
    -- learned recipes it found that the catalog does not have (a sign to regenerate it).
    if BRutus.Professions and BRutus.ProfCatalog then
        local own = BRutus.db and BRutus.db.professions and BRutus.db.professions[BRutus.Professions.OwnKey()]
        local lines, extra = 0, 0
        for _, e in pairs((own and own.profs) or {}) do
            lines = lines + 1
            extra = extra + #(e.extra or {})
        end
        r.professions = { catalog = BRutus.ProfCatalog.build, lines = lines, extra = extra }
    end
```

- [ ] **Step 5: Run everything** — `luajit -e 'ADDON="."' tools/professions.lua` → `professions: N checks passed`; `luajit tools/compat-guard.lua` clean; luacheck 0/0; `luajit -e 'ADDON="."' tools/probe.lua` passes.

- [ ] **Step 6: Commit** — `git commit -am "feat: Compat lê profissões e receitas do Forever (#31)"` (plus `git add tools/professions.lua`).

---

### Task 3: `Modules/Professions.lua` — collection, model, native, API, adapter

**Files:**
- Create: `Modules/Professions.lua`
- Modify: `GuildOS.toc` (`Modules\Professions.lua` after `Data\ProfCatalogForever.lua`), `Core/Core.lua` (`MODULE_START`: `{ "Professions" },` after `{ "CraftNet" },`)
- Test: `tools/professions.lua` (sections 2 and 3)

**Interfaces:**
- Consumes: Task 1 `BRutus.ProfCatalog`; Task 2 Compat wrappers; `BRutus:GetPlayerKey`, `BRutus.Compat.PlayerName`, `BRutus.Compat.GetSpellInfo`, `LibStub("LibDeflate"):Adler32`.
- Produces: `Professions.MAX_LINES/MAX_RECIPES/MAX_EXTRA`, `Professions.IdList(t, cap) -> sorted ids | nil`, `Professions.Hash(recipes, extra) -> number`, `Professions.OwnKey() -> key`, `:Initialize()`, `:Scan() -> changed`, `:ReadWindow()`, `:ReadNative()`, `:Get(key)`, `:KnowsRecipe(key, id)`, `:CraftersOf(id) -> {keys}`, `:Members(line) -> {keys}`, `:OwnSummary() -> { [line] = {r,m,s,h,n} }`, `:OwnLine(line) -> entry|nil`, `:ApplySummary(key, p) -> {lines needing lists}|nil`, `:ApplyList(key, line, h, recipes, extra) -> bool`, `:Changed(key)`, `:Project(key)`, `:OwnLegacyList() -> list`. Record: `db.professions[key] = { src = "addon"|"native", ts, profs = { [line] = { rank, max, spec, h, n, recipes, extra } } }`. Calls `BRutus.ProfSync:ScheduleSummary()` when it exists.

- [ ] **Step 1: Add the failing tests** — in `tools/professions.lua`, before the final `print`, add the fixture catalog, the fake bus, the module load and sections 2–3:
```lua
-- ── Fixture catalog and a fake SyncService bus ──────────────────────────
BRutus.ProfCatalog = {
  build = "fixture",
  F = { line = 1, yellow = 2, grey = 3, out = 4, outCount = 5, enchant = 6, reqSkill = 7, spec = 8, focus = 9,
        src = 10, recipeItem = 11, category = 12, reagents = 13 },
  professions = { [186] = { child = 2946, primary = true, en = "Mining" },
                  [164] = { child = 2938, primary = true, en = "Blacksmithing" },
                  [185] = { child = 2939, primary = false, en = "Cooking" } },
  specs = { [9788] = 164 },
  stations = {},
  byLine = { [186] = { 2657, 3304 }, [164] = { 2660, 9950 }, [185] = { 2538 } },
  recipes = {
    [2657] = { 186, 1, 25, 2840, 1, 0, 0, 0, 0, 3, 0, 0, { 2770, 1 } },
    [3304] = { 186, 65, 90, 3576, 1, 0, 0, 0, 0, 1, 0, 0, { 2771, 1 } },
    [2660] = { 164, 1, 15, 2862, 1, 0, 0, 0, 0, 1, 0, 0, { 2835, 1 } },
    [9950] = { 164, 210, 230, 7934, 1, 0, 210, 9788, 0, 2, 7978, 0, {} },
    [2538] = { 185, 1, 45, 2679, 1, 0, 0, 0, 0, 1, 0, 0, { 2672, 1 } },
  },
}
local sent = {}
BRutus.SyncService = {
  handlers = {},
  On = function(self, dom, fn) self.handlers[dom] = fn end,
  Publish = function(_, dom, act, data, opts)
    sent[#sent + 1] = { dom = dom, act = act, data = data, target = opts and opts.target }
    return "id"
  end,
}
local function sentOf(act)
  local out = {}
  for _, m in ipairs(sent) do if m.act == act then out[#out + 1] = m end end
  return out
end
math.random = function(a) return a end
BRutus.db = { members = {}, settings = {} }
dofile(ADDON .. "/Modules/Professions.lua")
local P = BRutus.Professions
check(P ~= nil, "Professions exists on Forever")
local ME = P.OwnKey()
check(ME == "Ana Silva-Classic Beta PvE 2", "my key is my whole name and the client's realm: " .. tostring(ME))

-- ── 2. Collection ───────────────────────────────────────────────────────
check(P.Hash({ 3, 1, 2 }) == P.Hash({ 1, 2, 3 }) and P.Hash({ 1 }, { 2 }) == P.Hash({ 1, 2 }),
      "the hash ignores order and where an ID sits")
check(P.IdList({ 3, 1, 3 }, 10)[1] == 1 and #P.IdList({ 3, 1, 3 }, 10) == 2, "IdList sorts and drops duplicates")
check(P.IdList({ "x" }, 10) == nil and P.IdList({ 1.5 }, 10) == nil and P.IdList({ 1, 2 }, 1) == nil
      and P.IdList("x", 10) == nil, "IdList refuses non-IDs and lists past the cap")
SLOTS = { 1, nil, 2, 3 }
PROFS[1] = { "Mineração", 21, 75, 186 }
PROFS[2] = { "Culinária", 1, 75, 185 }
PROFS[3] = { "Venenos", 10, 300, 40 }
KNOWN[2657], KNOWN[2538] = true, true
P:Initialize()
runTimers()
local rec = BRutus.db.professions[ME]
check(rec and rec.src == "addon" and rec.profs[186].rank == 21 and rec.profs[186].max == 75,
      "rank and max come from GetProfessionInfo, keyed by skill line")
check(#rec.profs[186].recipes == 1 and rec.profs[186].recipes[1] == 2657 and rec.profs[186].n == 1
      and rec.profs[186].h == P.Hash({ 2657 }), "learned recipes come from IsPlayerSpell over the catalog")
check(rec.profs[185] and rec.profs[40] == nil, "a skill line the catalog does not list (Poisons) is ignored")
local legacy = BRutus.db.members[ME].professions
check(#legacy == 2 and legacy[1].name == "Cooking" and legacy[2].name == "Mining" and legacy[2].rank == 21
      and legacy[2].maxRank == 75 and legacy[2].isPrimary == true and legacy[1].isPrimary == false,
      "the adapter writes DataCollector's shape, canonical English names")
local mine = BRutus.db.recipes[ME].Mining
check(mine and mine[1].spellId == 2657 and mine[1].itemId == 2840 and mine[1].name == "Spell 2657",
      "the adapter writes the recipe tracker's shape, localized name and output item")
SLOTS[2], PROFS[4], KNOWN[9788], KNOWN[9950] = 4, { "Ferraria", 210, 300, 164 }, true, true
fire("SKILL_LINES_CHANGED")
runTimers()
rec = BRutus.db.professions[ME]
check(rec.profs[164] and rec.profs[164].spec == 9788 and rec.profs[164].recipes[1] == 9950,
      "a specialization is read from the catalog's spells")
SLOTS[2] = nil
fire("LEARNED_SPELL_IN_SKILL_LINE")
runTimers()
check(BRutus.db.professions[ME].profs[164] == nil and #BRutus.db.members[ME].professions == 2,
      "a profession dropped disappears on the next scan")
KNOWN[3304] = true
fire("NEW_RECIPE_LEARNED", 3304)
runTimers()
rec = BRutus.db.professions[ME]
check(#rec.profs[186].recipes == 2 and rec.profs[186].h == P.Hash({ 2657, 3304 }), "a new recipe is picked up")
check(P:Scan() == false, "a scan that finds nothing new changes nothing")
WINDOW = { line = 186, all = { 2657, 3304, 999001 }, learned = { 2657, 3304, 999001 } }
KNOWN[999001] = true
fire("TRADE_SKILL_LIST_UPDATE")
runTimers()
rec = BRutus.db.professions[ME]
check(rec.profs[186].extra[1] == 999001 and rec.profs[186].n == 3
      and rec.profs[186].h == P.Hash({ 2657, 3304 }, { 999001 }),
      "the own window adds a learned recipe the catalog lacks as extra")
check(BRutus.db.recipes[ME].Mining[3].spellId == 999001, "an extra recipe reaches the recipe tracker too")
WINDOW = { line = 186, linked = true, all = { 888001 }, learned = { 888001 } }
fire("TRADE_SKILL_LIST_UPDATE")
runTimers()
check(#BRutus.db.professions[ME].profs[186].extra == 1, "someone else's window adds nothing")
WINDOW = nil
check(P:Scan() == false, "an extra still known survives a scan")
KNOWN[999001] = nil
check(P:Scan() == true and #BRutus.db.professions[ME].profs[186].extra == 0, "an extra no longer known is dropped")

-- ── 3. Native records and queries ───────────────────────────────────────
CLUB = { { name = "Bob", profession1ID = 186, profession2ID = 333 }, { name = "Ana Silva", profession1ID = 164 } }
fire("GUILD_ROSTER_UPDATE")
runTimers()
local BOB = BRutus:GetPlayerKey("Bob")
check(BRutus.db.professions[BOB] and BRutus.db.professions[BOB].src == "native"
      and BRutus.db.professions[BOB].profs[186] and BRutus.db.professions[BOB].profs[333] == nil,
      "a member without the addon gets the catalog's professions the roster names")
check(BRutus.db.professions[ME].src == "addon" and BRutus.db.professions[ME].profs[186],
      "a native record never replaces an addon one")
local bobLegacy = BRutus.db.members[BOB].professions
check(#bobLegacy == 1 and bobLegacy[1].name == "Mining" and bobLegacy[1].rank == nil, "a native profession has no rank")
CLUB[1].profession1ID = 164
fire("GUILD_ROSTER_UPDATE")
runTimers()
check(BRutus.db.professions[BOB].profs[186], "the roster is read at most once a minute")
NOW = NOW + 61
fire("GUILD_ROSTER_UPDATE")
runTimers()
check(BRutus.db.professions[BOB].profs[164] and not BRutus.db.professions[BOB].profs[186],
      "a minute later the change is read")
check(P:KnowsRecipe(ME, 2657) and not P:KnowsRecipe(BOB, 2657), "KnowsRecipe")
check(#P:CraftersOf(2657) == 1 and P:CraftersOf(2657)[1] == ME and #P:CraftersOf(1) == 0, "CraftersOf")
check(#P:Members(186) == 1 and #P:Members(164) == 1, "Members by line")
local summary = P:OwnSummary()
check(summary[186].r == 21 and summary[186].h == BRutus.db.professions[ME].profs[186].h and summary[186].n == 2,
      "the own summary carries rank, hash and count per line")
check(P:OwnLine(186).recipes[1] == 2657 and P:OwnLine(999) == nil, "OwnLine")
```

- [ ] **Step 2: Run to see it fail** — `luajit -e 'ADDON="."' tools/professions.lua` → error loading `Modules/Professions.lua` (missing).

- [ ] **Step 3: Write `Modules/Professions.lua`**
```lua
----------------------------------------------------------------------
-- Guild OS - Professions (WoW: Forever, issue #31)
--
-- Every member's professions, levels and recipes, by skill-line and recipe ID. The player's
-- own come from GetProfessionInfo and, recipe by recipe, IsPlayerSpell over the static catalog
-- (Data/ProfCatalogForever.lua): nobody has to open a window. Members without the addon come
-- from the Communities roster (the profession, no rank). ProfSync carries the addon records
-- between guildmates; Project() keeps the legacy shapes (members[].professions, db.recipes)
-- that the roster, member detail, recipes panel, tooltips, CraftNet and the export read.
----------------------------------------------------------------------
if BRutus.Client.isAnniversary then return end

local Professions = {}
BRutus.Professions = Professions

local Compat = BRutus.Compat
local LibDeflate = LibStub("LibDeflate")

Professions.MAX_LINES = 7
Professions.MAX_RECIPES = 1500
Professions.MAX_EXTRA = 200
local SCAN_DELAY = 2      -- seconds of quiet before a rescan
local WINDOW_DELAY = 1    -- the window fires TRADE_SKILL_LIST_UPDATE in bursts
local NATIVE_EVERY = 60   -- the Communities roster is read at most this often

local function catalog() return BRutus.ProfCatalog end

function Professions.OwnKey()
    return BRutus:GetPlayerKey(Compat.PlayerName())
end

-- Sorted copy of a list of positive integer IDs, duplicates dropped; nil when it is not a
-- table of IDs or runs past cap.
function Professions.IdList(t, cap)
    if type(t) ~= "table" or #t > cap then return nil end
    local out, seen = {}, {}
    for i = 1, #t do
        local v = t[i]
        if type(v) ~= "number" or v < 1 or v > 2147483647 or v % 1 ~= 0 then return nil end
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out)
    return out
end

-- Adler-32 of the sorted recipe and extra IDs: what a summary announces and a list must match.
function Professions.Hash(recipes, extra)
    local all = {}
    for _, v in ipairs(recipes or {}) do all[#all + 1] = v end
    for _, v in ipairs(extra or {}) do all[#all + 1] = v end
    table.sort(all)
    return LibDeflate:Adler32(table.concat(all, ","))
end

function Professions:Initialize()
    BRutus.db.professions = BRutus.db.professions or {}
    self.index, self.scanned, self.nativeAt = nil, false, 0
    local f = CreateFrame("Frame")
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE",
                             "TRADE_SKILL_LIST_UPDATE", "GUILD_ROSTER_UPDATE" }) do
        Compat.RegisterEvent(f, event)
    end
    f:SetScript("OnEvent", function(_, event) Professions:OnEvent(event) end)
    Compat.After(4, function() Professions:Scan() end)
end

function Professions:OnEvent(event)
    if event == "TRADE_SKILL_LIST_UPDATE" then
        self:ScheduleWindow()
    elseif event == "GUILD_ROSTER_UPDATE" then
        self:ReadNative()
    else
        self:ScheduleScan()
    end
end

function Professions:ScheduleScan()
    if self.scanPending then return end
    self.scanPending = true
    Compat.After(SCAN_DELAY, function()
        self.scanPending = false
        self:Scan()
    end)
end

function Professions:ScheduleWindow()
    if self.windowPending then return end
    self.windowPending = true
    Compat.After(WINDOW_DELAY, function()
        self.windowPending = false
        self:ReadWindow()
    end)
end

----------------------------------------------------------------------
-- The player's own professions
----------------------------------------------------------------------
function Professions:ReadLine(line, rank, maxRank, old)
    local cat = catalog()
    local recipes, extra = {}, {}
    for _, id in ipairs(cat.byLine[line] or {}) do
        if Compat.IsPlayerSpell(id) then recipes[#recipes + 1] = id end
    end
    for _, id in ipairs((old and old.extra) or {}) do
        if Compat.IsPlayerSpell(id) then extra[#extra + 1] = id end
    end
    local spec
    for specID, specLine in pairs(cat.specs) do
        if specLine == line and Compat.IsPlayerSpell(specID) and (not spec or specID < spec) then spec = specID end
    end
    return { rank = tonumber(rank) or 0, max = tonumber(maxRank) or 0, spec = spec, recipes = recipes,
             extra = extra, n = #recipes + #extra, h = self.Hash(recipes, extra) }
end

local function sameLine(a, b)
    return b ~= nil and a.rank == b.rank and a.max == b.max and a.spec == b.spec and a.h == b.h
end

-- Read the player's professions, specializations and learned recipes. Returns true when the
-- record changed (and then republishes the summary).
function Professions:Scan()
    local cat = catalog()
    local key = self.OwnKey()
    if not (cat and key) then return false end
    self.scanned = true
    local old = BRutus.db.professions[key]
    local oldProfs = (old and old.src == "addon" and old.profs) or {}
    local profs = {}
    local slots = { Compat.GetProfessions() }
    for i = 1, table.maxn(slots) do
        local index = slots[i]
        if type(index) == "number" then
            local _, _, rank, maxRank, _, _, line = Compat.GetProfessionInfo(index)
            if type(line) == "number" and cat.professions[line] then
                profs[line] = self:ReadLine(line, rank, maxRank, oldProfs[line])
            end
        end
    end
    local changed = not old or old.src ~= "addon"
    for line, p in pairs(profs) do
        if not sameLine(p, oldProfs[line]) then changed = true end
    end
    for line in pairs(oldProfs) do
        if not profs[line] then changed = true end
    end
    if not changed then return false end
    BRutus.db.professions[key] = { src = "addon", ts = GetServerTime(), profs = profs }
    self:Changed(key)
    if BRutus.ProfSync then BRutus.ProfSync:ScheduleSummary() end
    return true
end

-- The own window, once settled: learned recipes the catalog lacks become the line's extra
-- (a beta build newer than the catalog).
function Professions:ReadWindow()
    local cat = catalog()
    local line, learned = Compat.TradeSkillLearned()
    local key = self.OwnKey()
    local rec = key and BRutus.db.professions[key]
    local p = line and rec and rec.src == "addon" and rec.profs[line]
    if not (cat and p) then return end
    local extra = {}
    for _, id in ipairs(learned) do
        if not cat.recipes[id] then extra[#extra + 1] = id end
    end
    extra = self.IdList(extra, self.MAX_EXTRA) or p.extra
    local h = self.Hash(p.recipes, extra)
    if h == p.h then return end
    p.extra, p.h, p.n = extra, h, #p.recipes + #extra
    rec.ts = GetServerTime()
    self:Changed(key)
    if BRutus.ProfSync then BRutus.ProfSync:ScheduleSummary() end
end

----------------------------------------------------------------------
-- Members without the addon: the Communities roster's professions, no rank
----------------------------------------------------------------------
function Professions:ReadNative()
    local now = GetServerTime()
    if now - (self.nativeAt or 0) < NATIVE_EVERY then return end
    self.nativeAt = now
    local cat = catalog()
    local members = Compat.GuildMemberProfessions()
    if not (cat and members) then return end
    local db = BRutus.db.professions
    for _, m in ipairs(members) do
        local short = m.name:match("^([^-]+)") or m.name
        local key = BRutus:GetPlayerKey(short, m.name:match("-(.+)$"))
        local rec = key and db[key]
        if key and (not rec or rec.src == "native") then
            local profs = {}
            for _, line in ipairs(m.lines) do
                if cat.professions[line] then profs[line] = {} end
            end
            local same = rec ~= nil
            for line in pairs(profs) do
                if not (rec and rec.profs[line]) then same = false end
            end
            for line in pairs((rec and rec.profs) or {}) do
                if not profs[line] then same = false end
            end
            if not next(profs) then
                if rec then
                    db[key] = nil
                    self:Changed(key)
                end
            elseif not same then
                db[key] = { src = "native", ts = now, profs = profs }
                self:Changed(key)
            end
        end
    end
end

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------
function Professions:Get(key) return BRutus.db.professions[key] end

function Professions:CraftersOf(recipeID)
    if not self.index then
        local index = {}
        for key, rec in pairs(BRutus.db.professions) do
            for _, e in pairs(rec.profs) do
                for _, list in ipairs({ e.recipes or {}, e.extra or {} }) do
                    for _, id in ipairs(list) do
                        index[id] = index[id] or {}
                        index[id][#index[id] + 1] = key
                    end
                end
            end
        end
        for _, keys in pairs(index) do table.sort(keys) end
        self.index = index
    end
    return self.index[recipeID] or {}
end

function Professions:KnowsRecipe(key, recipeID)
    for _, k in ipairs(self:CraftersOf(recipeID)) do
        if k == key then return true end
    end
    return false
end

function Professions:Members(line)
    local out = {}
    for key, rec in pairs(BRutus.db.professions) do
        if rec.profs[line] then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

----------------------------------------------------------------------
-- What ProfSync sends and applies
----------------------------------------------------------------------
function Professions:OwnSummary()
    if not self.scanned then self:Scan() end
    local rec = BRutus.db.professions[self.OwnKey()]
    local out = {}
    for line, e in pairs((rec and rec.src == "addon" and rec.profs) or {}) do
        out[line] = { r = e.rank, m = e.max, s = e.spec, h = e.h, n = e.n }
    end
    return out
end

function Professions:OwnLine(line)
    local rec = BRutus.db.professions[self.OwnKey()]
    return (rec and rec.src == "addon" and rec.profs[line]) or nil
end

local function int(v, lo, hi)
    return type(v) == "number" and v >= lo and v <= hi and v % 1 == 0
end

-- A guildmate's summary. Returns the lines whose recipe list this client still needs, or nil
-- when the summary is malformed (then nothing is applied).
function Professions:ApplySummary(key, p)
    local cat = catalog()
    if not cat or type(p) ~= "table" then return nil end
    local lines, count = {}, 0
    for line, s in pairs(p) do
        count = count + 1
        if count > self.MAX_LINES or type(s) ~= "table" or not cat.professions[line]
            or not int(s.r, 0, 1000) or not int(s.m, 0, 1000) or not int(s.h, 0, 4294967295)
            or not int(s.n, 0, self.MAX_RECIPES + self.MAX_EXTRA)
            or (s.s ~= nil and not int(s.s, 1, 2147483647)) then
            return nil
        end
        lines[line] = s
    end
    local db = BRutus.db.professions
    local old = db[key]
    local oldProfs = (old and old.src == "addon" and old.profs) or {}
    local profs, need = {}, {}
    for line, s in pairs(lines) do
        local o = oldProfs[line]
        local e = { rank = s.r, max = s.m, spec = s.s, h = s.h, n = s.n }
        if o and o.h == s.h and o.recipes then
            e.recipes, e.extra = o.recipes, o.extra
        elseif s.n == 0 then
            e.recipes, e.extra = {}, {}
        else
            need[#need + 1] = line
        end
        profs[line] = e
    end
    db[key] = { src = "addon", ts = GetServerTime(), profs = profs }
    self:Changed(key)
    table.sort(need)
    return need
end

-- A guildmate's recipe list for one line. Stored only when the IDs hash to what the list
-- says and to what that member's latest summary announced, and not already held.
function Professions:ApplyList(key, line, h, recipes, extra)
    local rec = BRutus.db.professions[key]
    local e = rec and rec.src == "addon" and rec.profs[line]
    if not e or e.h ~= h or e.recipes then return false end
    recipes = self.IdList(recipes or {}, self.MAX_RECIPES)
    extra = self.IdList(extra or {}, self.MAX_EXTRA)
    if not recipes or not extra or self.Hash(recipes, extra) ~= h then return false end
    e.recipes, e.extra = recipes, extra
    self:Changed(key)
    return true
end

----------------------------------------------------------------------
-- Legacy adapter
----------------------------------------------------------------------
function Professions:Changed(key)
    self.index = nil
    self:Project(key)
end

-- Write the shapes the existing surfaces read: members[key].professions (DataCollector's
-- { name, rank, maxRank, isPrimary }, canonical English name) and db.recipes[key][name]
-- (RecipeTracker's { name, itemId, spellId }). A native record has no rank.
function Professions:Project(key)
    local cat = catalog()
    local rec = BRutus.db.professions[key]
    local members = BRutus.db.members
    BRutus.db.recipes = BRutus.db.recipes or {}
    if not rec then
        if members[key] then members[key].professions = nil end
        BRutus.db.recipes[key] = nil
        return
    end
    local list, byProf = {}, {}
    for line, e in pairs(rec.profs) do
        local meta = cat.professions[line]
        if meta then
            list[#list + 1] = { name = meta.en, rank = e.rank, maxRank = e.max, isPrimary = meta.primary }
            if e.recipes then
                local out = {}
                for _, id in ipairs(e.recipes) do
                    local r = cat.recipes[id]
                    local item = r and r[cat.F.out]
                    out[#out + 1] = { name = Compat.GetSpellInfo(id) or ("#" .. id),
                                      itemId = (item and item > 0) and item or nil, spellId = id }
                end
                for _, id in ipairs(e.extra or {}) do
                    out[#out + 1] = { name = Compat.GetSpellInfo(id) or ("#" .. id), spellId = id }
                end
                byProf[meta.en] = out
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    members[key] = members[key] or {}
    members[key].professions = list
    BRutus.db.recipes[key] = next(byProf) and byProf or nil
end

-- The player's own professions in DataCollector's shape, for the member broadcast. Scans first
-- if the login scan has not run yet, so the broadcast never goes out empty.
function Professions:OwnLegacyList()
    if not self.scanned then self:Scan() end
    local m = BRutus.db.members[self.OwnKey()]
    return (m and m.professions) or {}
end
```

- [ ] **Step 4: Wire it** — `GuildOS.toc`: `Modules\Professions.lua` after `Data\ProfCatalogForever.lua`. `Core/Core.lua` `MODULE_START`: `{ "Professions" },` after `{ "CraftNet" },`.

- [ ] **Step 5: Run** — `luajit -e 'ADDON="."' tools/professions.lua` → passes; luacheck 0/0; `luajit -e 'ADDON="."' tools/member-keys.lua` (source scan) passes.

- [ ] **Step 6: Commit** — `git add Modules/Professions.lua && git commit -am "feat: profissões do próprio personagem e dos membros no Forever (#31)"`

---

### Task 4: `Modules/ProfSync.lua` — the `prof` domain

**Files:**
- Create: `Modules/ProfSync.lua`
- Modify: `GuildOS.toc` (`Modules\ProfSync.lua` after `Modules\Professions.lua`), `Core/Core.lua` (`{ "ProfSync" },` after `{ "Professions" },`)
- Test: `tools/professions.lua` (section 4)

**Interfaces:**
- Consumes: Task 3 API; `BRutus.SyncService:On(dom, fn(env, sender))`, `:Publish(dom, act, data, { target })`; `BRutus:GetMemberRecord(short, realm)`, `BRutus:GetClientRealm()`.
- Produces: `ProfSync:Initialize()`, `:PublishSummary()`, `:ScheduleSummary(delay)`, `:SenderKey(sender) -> key|nil`, `:OnEnvelope(env, sender)`, `:FlushLine(line)`. Wire: `sum {p}`, `ask {}`, `req {l = {lines}}`, `list {l, h, r, x}`.

- [ ] **Step 1: Add the failing tests** — before the final `print`:
```lua
-- ── 4. Sync ─────────────────────────────────────────────────────────────
dofile(ADDON .. "/Modules/ProfSync.lua")
local S = BRutus.ProfSync
sent = {}
S:Initialize()
runTimers()
check(#sentOf("sum") == 1 and #sentOf("ask") == 1 and sentOf("sum")[1].target == nil,
      "login publishes my summary and asks the guild for theirs")
check(sentOf("sum")[1].data.p[186].h == BRutus.db.professions[ME].profs[186].h, "the summary is my own")
local function deliver(act, data, sender)
  BRutus.SyncService.handlers.prof({ dom = "prof", act = act, data = data }, sender)
end
local h1 = P.Hash({ 2657 })
sent = {}
deliver("sum", { p = { [186] = { r = 50, m = 75, h = h1, n = 1 } } }, "Zed")
runTimers()
check(BRutus.db.professions[BRutus:GetPlayerKey("Zed")] == nil and #sent == 0, "a sender outside the guild is ignored")
deliver("sum", { p = { [186] = { r = 50, m = 75, h = h1, n = 1 } }, key = "Dee-Classic Beta PvE 2" }, "Bob")
check(BRutus.db.professions[BOB].src == "addon" and BRutus.db.professions[BOB].profs[186].rank == 50
      and BRutus.db.professions[BOB].profs[186].recipes == nil, "a summary replaces the native record, list pending")
check(BRutus.db.professions[BRutus:GetPlayerKey("Dee")] == nil, "the key comes from the sender, not the payload")
runTimers()
local req = sentOf("req")
check(#req == 1 and req[1].target == "Bob" and req[1].data.l[1] == 186, "a new hash asks the sender for that list")
sent = {}
deliver("sum", { p = { [186] = { r = 51, m = 75, h = h1, n = 1 } } }, "Bob")
runTimers()
check(#sentOf("req") == 0, "the same hash is not asked for again at once")
NOW = NOW + 121
deliver("sum", { p = { [186] = { r = 51, m = 75, h = h1, n = 1 } } }, "Bob")
runTimers()
check(#sentOf("req") == 1, "a list that never came is asked for again after two minutes")
deliver("list", { l = 186, h = h1 + 1, r = { 2657 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "a list whose hash is not the summary's is refused")
deliver("list", { l = 186, h = h1, r = { 2660 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "a list that does not hash to its h is refused")
deliver("list", { l = 186, h = h1, r = { "x" }, x = {} }, "Bob")
deliver("list", { l = 186, h = h1, r = "x" }, "Bob")
deliver("list", "junk", "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "malformed lists are dropped without raising")
deliver("list", { l = 186, h = h1, r = { 2657 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes[1] == 2657 and P:KnowsRecipe(BOB, 2657)
      and #P:CraftersOf(2657) == 2, "a list matching the summary is stored and indexed")
check(BRutus.db.recipes[BOB].Mining[1].itemId == 2840, "and reaches the recipe tracker's shape")
check(P:ApplyList(BOB, 186, h1, { 2657 }, {}) == false, "a list already held is not applied twice")
local before = BRutus.db.professions[BOB].profs[186].rank
deliver("sum", { p = { [186] = { r = "x", m = 75, h = h1, n = 1 } } }, "Bob")
deliver("sum", { p = { [999] = { r = 1, m = 75, h = h1, n = 1 } } }, "Bob")
deliver("sum", { p = { ["186"] = { r = 1, m = 75, h = h1, n = 1 } } }, "Bob")
local eight = {}
for i = 1, 8 do eight[i] = { r = 1, m = 75, h = h1, n = 1 } end
deliver("sum", { p = eight }, "Bob")
check(BRutus.db.professions[BOB].profs[186].rank == before, "a malformed summary changes nothing")
deliver("sum", { p = { [185] = { r = 5, m = 75, h = 1, n = 0 } } }, "Cid")
check(#BRutus.db.professions[BRutus:GetPlayerKey("Cid")].profs[185].recipes == 0, "a line with no recipes needs no list")
sent = {}
deliver("req", { l = { 186 } }, "Bob")
runTimers()
local lists = sentOf("list")
check(#lists == 1 and lists[1].target == "Bob" and lists[1].data.h == BRutus.db.professions[ME].profs[186].h
      and #lists[1].data.r == 2, "one requester gets my list by whisper")
sent = {}
deliver("req", { l = { 186 } }, "Bob")
deliver("req", { l = { 186 } }, "Cid")
runTimers()
lists = sentOf("list")
check(#lists == 1 and lists[1].target == nil, "two requesters within the window get one guild answer")
sent = {}
deliver("req", { l = { 164 } }, "Bob")
deliver("req", { l = { 186 } }, "Zed")
deliver("req", { l = "x" }, "Bob")
runTimers()
check(#sentOf("list") == 0, "a line I do not have, a stranger, or junk gets no answer")
sent = {}
deliver("ask", {}, "Cid")
runTimers()
check(#sentOf("sum") == 1, "an ask is answered with my summary")
```

- [ ] **Step 2: Run to see it fail** — missing `Modules/ProfSync.lua`.

- [ ] **Step 3: Write `Modules/ProfSync.lua`**
```lua
----------------------------------------------------------------------
-- Guild OS - Profession sync (WoW: Forever, issue #31)
--
-- The "prof" SyncService domain. A member announces a summary: rank, max, specialization
-- and a hash of the recipe list, per profession. A guildmate whose stored hash differs asks
-- for that one list; the crafter answers once, by whisper, or on the guild channel when
-- several asked within a few seconds. Lists travel once per change, never on a timer.
--
--   sum  GUILD    { p = { [line] = { r, m, s, h, n } } }
--   ask  GUILD    {}                              everyone answers with its own sum
--   req  WHISPER  { l = { line, ... } }
--   list WHISPER|GUILD { l = line, h = hash, r = { ids }, x = { extra ids } }
----------------------------------------------------------------------
if BRutus.Client.isAnniversary then return end

local ProfSync = {}
BRutus.ProfSync = ProfSync

local Compat = BRutus.Compat
local DOMAIN = "prof"
ProfSync.SUMMARY_EVERY = 600   -- heartbeat summary
ProfSync.CHANGE_DELAY = 10     -- one summary for a burst of changes
ProfSync.AGGREGATE = 3         -- requests for a line gathered before answering
ProfSync.REASK_AFTER = 120     -- a list that never came is asked for again

function ProfSync:Initialize()
    self.asked = {}      -- [sender .. ":" .. line] = { h = hash, at = time }
    self.outgoing = {}   -- [line] = { [requester] = true }
    BRutus.SyncService:On(DOMAIN, function(env, sender) ProfSync:OnEnvelope(env, sender) end)
    Compat.After(math.random(5, 15), function()
        ProfSync:PublishSummary()
        BRutus.SyncService:Publish(DOMAIN, "ask", {})
    end)
    Compat.NewTicker(self.SUMMARY_EVERY, function() ProfSync:PublishSummary() end)
end

function ProfSync:PublishSummary()
    self.summaryPending = false
    BRutus.SyncService:Publish(DOMAIN, "sum", { p = BRutus.Professions:OwnSummary() })
end

function ProfSync:ScheduleSummary(delay)
    if self.summaryPending then return end
    self.summaryPending = true
    Compat.After(delay or self.CHANGE_DELAY, function() self:PublishSummary() end)
end

-- The member key of a guildmate sender, or nil when the sender is not in the guild roster.
-- The key comes from who sent the message, never from what it says.
function ProfSync:SenderKey(sender)
    if type(sender) ~= "string" then return nil end
    local short = sender:match("^([^-]+)") or sender
    local suffix = sender:match("-(.+)$")
    if not BRutus:GetMemberRecord(short, suffix) then return nil end
    return BRutus:GetPlayerKey(short, (not BRutus:GetClientRealm()) and suffix or nil)
end

function ProfSync:OnEnvelope(env, sender)
    local key = self:SenderKey(sender)
    local data = env and env.data
    if not key or type(data) ~= "table" then return end
    if env.act == "sum" then
        self:OnSummary(key, sender, data.p)
    elseif env.act == "ask" then
        self:ScheduleSummary(math.random(1, 8))
    elseif env.act == "req" then
        self:OnRequest(sender, data.l)
    elseif env.act == "list" then
        BRutus.Professions:ApplyList(key, data.l, data.h, data.r, data.x)
    end
end

function ProfSync:OnSummary(key, sender, p)
    local need = BRutus.Professions:ApplySummary(key, p)
    if not need or #need == 0 then return end
    local rec = BRutus.Professions:Get(key)
    local now = GetServerTime()
    local ask = {}
    for _, line in ipairs(need) do
        local tag = sender .. ":" .. line
        local h = rec.profs[line].h
        local a = self.asked[tag]
        if not a or a.h ~= h or now - a.at > self.REASK_AFTER then
            self.asked[tag] = { h = h, at = now }
            ask[#ask + 1] = line
        end
    end
    if #ask == 0 then return end
    Compat.After(math.random(2, 6), function()
        BRutus.SyncService:Publish(DOMAIN, "req", { l = ask }, { target = sender })
    end)
end

function ProfSync:OnRequest(sender, lines)
    if type(lines) ~= "table" or #lines > BRutus.Professions.MAX_LINES then return end
    for _, line in ipairs(lines) do
        if type(line) == "number" and BRutus.Professions:OwnLine(line) then
            local waiting = self.outgoing[line]
            if not waiting then
                waiting = {}
                self.outgoing[line] = waiting
                Compat.After(self.AGGREGATE, function() self:FlushLine(line) end)
            end
            waiting[sender] = true
        end
    end
end

-- Answer everyone who asked for a line: a whisper for one, the guild channel for several.
function ProfSync:FlushLine(line)
    local waiting = self.outgoing[line]
    self.outgoing[line] = nil
    local e = BRutus.Professions:OwnLine(line)
    if not (waiting and e and e.recipes) then return end
    local only, count = nil, 0
    for name in pairs(waiting) do
        only, count = name, count + 1
    end
    BRutus.SyncService:Publish(DOMAIN, "list", { l = line, h = e.h, r = e.recipes, x = e.extra or {} },
        { target = count == 1 and only or nil })
end
```

- [ ] **Step 4: Wire it** — `GuildOS.toc`: `Modules\ProfSync.lua` after `Modules\Professions.lua`; `Core/Core.lua` `MODULE_START`: `{ "ProfSync" },` after `{ "Professions" },`.

- [ ] **Step 5: Run** — harness passes; luacheck 0/0; compat-guard clean.

- [ ] **Step 6: Commit** — `git add Modules/ProfSync.lua && git commit -am "feat: sync de profissões por hash no Forever (#31)"`

---

### Task 5: Integration points

**Files:**
- Modify: `Modules/DataCollector.lua` (`CollectProfessions`, `GetBroadcastData`), `Core/Utils.lua` (`CheckProfessionFreshness`, `PruneStaleData`), `UI/RosterFrame.lua` (profession cell ~1240 and tooltip ~1513), `UI/MemberDetail.lua` (`CreateProfessionRow` ~1155-1162), `Modules/CompanionExport.lua` (`professionsFor` ~191)
- Test: `tools/professions.lua` (section 5), `tools/companion-payload.lua` (one check)

**Interfaces:**
- Consumes: `Professions:OwnLegacyList()`, `Professions:Changed(key)`.

- [ ] **Step 1: Add the failing tests** — in `tools/professions.lua` before the final `print`:
```lua
-- ── 5. Integration points ───────────────────────────────────────────────
dofile(ADDON .. "/Modules/DataCollector.lua")
local DC = BRutus.DataCollector
local own = DC:CollectProfessions()
check(type(own) == "table" and #own == 2 and own[2].name == "Mining", "CollectProfessions reads Professions on Forever")
P.scanned = false
check(#DC:CollectProfessions() == 2, "and scans first when the login scan has not run, never nil")
BRutus.db.myData = { name = "Ana Silva", realm = "Classic Beta PvE 2", lastUpdate = NOW }
check(BRutus.db.recipes[ME] ~= nil and DC:GetBroadcastData().recipes == nil,
      "the member broadcast carries no recipes on Forever")
local reminded = false
BRutus.ShowProfessionReminder = function() reminded = true end
BRutus.db.myData.professions = own
BRutus:CheckProfessionFreshness()
check(not reminded, "the open-your-window reminder never shows on Forever")
ROSTER = { "Ana Silva", "Cid" }
BRutus:PruneStaleData()
check(BRutus.db.professions[BOB] == nil and BRutus.db.recipes[BOB] == nil and BRutus.db.professions[ME],
      "a member who left loses the profession record and its projection")
```
And in `tools/companion-payload.lua`, give the first fixture member a rankless profession next to the ranked ones (line ~176: `{ name = "Alchemy" },` appended) and, after the payload is built, check that member's exported professions contain Leatherworking and Skinning and no Alchemy (use the harness's existing access to the decoded payload members).

- [ ] **Step 2: Run to see them fail** — `CollectProfessions` returns nil on Forever (no skill-line API) → `FAIL: CollectProfessions reads Professions on Forever`; companion-payload exports `Alchemy` with rank 0.

- [ ] **Step 3: Implement**

`Modules/DataCollector.lua`, top of `CollectProfessions`:
```lua
function DataCollector:CollectProfessions()
    -- WoW: Forever reads them through Professions, by skill line and with no window (issue #31).
    if BRutus.Professions then return BRutus.Professions:OwnLegacyList() end
    local numSkills = BRutus.Compat.GetNumSkillLines()
```
`GetBroadcastData`, the recipes block:
```lua
    -- Include recipes (keyed by profession). On WoW: Forever ProfSync carries them, by hash,
    -- instead of every broadcast (issue #31).
    local myKey = BRutus:GetPlayerKey(myData.name, myData.realm or GetRealmName())
    if not BRutus.Professions and BRutus.db.recipes and BRutus.db.recipes[myKey] then
        clean.recipes = BRutus.db.recipes[myKey]
    end
```
`Core/Utils.lua` `CheckProfessionFreshness`, first line of the body:
```lua
    if self.Professions then return end   -- WoW: Forever reads recipes without a window (issue #31)
```
`Core/Utils.lua` `PruneStaleData`, after the `firstSeen` loop:
```lua
    for key in pairs(self.db.professions or {}) do
        if not roster[key] then
            self.db.professions[key] = nil
            if self.Professions then self.Professions:Changed(key) end
        end
    end
```
`UI/RosterFrame.lua` cell:
```lua
                table.insert(parts, BRutus:ColorText(prof.name:sub(1, 5) .. (prof.rank and (" " .. prof.rank) or ""), pr, pg, pb))
```
tooltip:
```lua
            local line = prof.rank and string.format("  %s  %d / %d", prof.name, prof.rank, prof.maxRank or 0)
                or ("  " .. prof.name)   -- a profession known from the guild roster only has no rank (issue #31)
            GameTooltip:AddLine(line, profColor.r, profColor.g, profColor.b)
```
`UI/MemberDetail.lua` `CreateProfessionRow`:
```lua
    skillText:SetText(prof.rank and string.format("%d / %d", prof.rank, prof.maxRank or 0) or "")
    ...
    progressBar:SetProgress((prof.rank and (prof.maxRank or 0) > 0) and (prof.rank / prof.maxRank) or 0)
```
`Modules/CompanionExport.lua` `professionsFor`:
```lua
        -- A profession known from the guild roster only has no rank: nothing to export (issue #31).
        if p.name and tonumber(p.rank) then out[#out + 1] = { name = p.name, rank = tonumber(p.rank) } end
```

- [ ] **Step 4: Run all checks** — every harness, luacheck, compat-guard, `python tools/*.py`.

- [ ] **Step 5: Commit** — `git commit -am "feat: telas e broadcast usam as profissões novas no Forever (#31)"`

---

### Task 6: Anniversary unchanged, real catalog smoke, docs

**Files:**
- Test: `tools/professions.lua` (sections 6 and 7)
- Modify: `docs/superpowers/specs/2026-09-27-professions-foundation-design.md` (§3.7: wrappers are `TradeSkillLearned` and `GuildMemberProfessions`; §3.5: a list needs the latest summary), `.memory/functions-catalog.md` (Professions, ProfSync, Compat entries), `.memory/decisions.md` (ADR: professions by ID on Forever, passive `IsPlayerSpell`, hash sync)

- [ ] **Step 1: Add the tests** — before the final `print`:
```lua
-- ── 6. The real catalog ─────────────────────────────────────────────────
local fixture = BRutus.ProfCatalog
dofile(ADDON .. "/Data/ProfCatalogForever.lua")
local real = BRutus.ProfCatalog
BRutus.ProfCatalog = fixture
check(real ~= fixture and real.build:match("^1%.60%.") ~= nil, "the generated catalog loads: " .. tostring(real.build))
check(real.recipes[2657] and real.recipes[2657][real.F.line] == 186 and real.recipes[2657][real.F.out] == 2840,
      "Smelt Copper is a Mining recipe making Copper Bar")
local total = 0
for line, ids in pairs(real.byLine) do
  check(real.professions[line] ~= nil, "byLine " .. line .. " is a profession")
  for i, id in ipairs(ids) do
    total = total + 1
    check(real.recipes[id] and real.recipes[id][real.F.line] == line, "recipe " .. id .. " sits on its line")
    check(i == 1 or ids[i - 1] < id, "byLine " .. line .. " is sorted")
  end
end
check(total > 2000 and real.professions[2933] == nil and real.professions[40] == nil,
      "about 2,500 recipes, no test profession, no Poisons")

-- ── 7. Anniversary: none of it exists ───────────────────────────────────
BRutus.Client.isAnniversary = true
local keep = { BRutus.Professions, BRutus.ProfSync, BRutus.ProfCatalog }
BRutus.Professions, BRutus.ProfSync, BRutus.ProfCatalog = nil, nil, nil
dofile(ADDON .. "/Data/ProfCatalogForever.lua")
dofile(ADDON .. "/Modules/Professions.lua")
dofile(ADDON .. "/Modules/ProfSync.lua")
check(BRutus.Professions == nil and BRutus.ProfSync == nil and BRutus.ProfCatalog == nil,
      "on Anniversary the catalog, Professions and ProfSync do not exist")
BRutus.Client.isAnniversary = false
BRutus.Professions, BRutus.ProfSync, BRutus.ProfCatalog = keep[1], keep[2], keep[3]
```
- [ ] **Step 2: Run** — harness passes (the real-catalog section needs Task 1's generated file).
- [ ] **Step 3: Docs** — update the spec lines named in **Files**; functions catalog gets a "v0.57 — Professions on Forever (#31)" table with every `Professions`, `ProfSync` and new `Compat` function and one line each; `decisions.md` gets ADR "Professions on Forever by ID: passive IsPlayerSpell over a generated catalog, hash-summarized sync" with context (2026-09-27 probe), decision, consequences (catalog regenerated per build; extras bridge the gap; Anniversary untouched).
- [ ] **Step 4: Full check run** — luacheck, compat-guard, all harnesses, `python tools/prof_catalog.py`, `python tools/beta-workflow.py`.
- [ ] **Step 5: Commit** — `git commit -am "docs: profissões do Forever no catálogo de funções e nas decisões (#31)"`
