"""Static profession catalog for WoW: Forever from wago.tools DB2 exports (issue #31).

    python tools/prof_catalog.py                           # self-test on tools/prof-catalog-fixture/
    python tools/prof_catalog.py <build> [--cache <dir>]   # writes Data/ProfCatalogForever.lua

Recipes sit on the parent profession skill line. Each recipe keeps IDs and numbers only; the
client localizes names at run time. Rerun on every beta build.
"""
import collections
import csv
import io
import os
import sys
import urllib.request

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
    count_key = ("EffectBasePointsF" if t["SpellEffect"] and "EffectBasePointsF" in t["SpellEffect"][0]
                 else "EffectBasePoints")
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
    t = {name: read_csv(open(os.path.join(FIXTURE, f"{name}.fixture.csv"), encoding="utf-8").read())
         for name in TABLES}
    cat = build_catalog(t)
    F = {f: i for i, f in enumerate(FIELDS)}
    assert cat["professions"][186] == {"child": 2946, "primary": True, "en": "Mining"}, cat["professions"].get(186)
    assert 2933 not in cat["professions"], "the test profession is not a profession"
    smelt = cat["recipes"][2657]
    assert smelt[F["line"]] == 186 and smelt[F["out"]] == 2840 and smelt[F["outCount"]] == 1, smelt
    assert smelt[F["reagents"]] == [2770, 1] and smelt[F["src"]] == 3 and smelt[F["focus"]] > 0, smelt
    assert cat["recipes"][3304][F["src"]] == 1, "a recipe no item teaches comes from a trainer"
    assert all(ids == sorted(ids) for ids in cat["byLine"].values()), "byLine is sorted"
    assert all(cat["recipes"][i][F["line"]] == line for line, ids in cat["byLine"].items() for i in ids)
    assert cat["specs"].get(9788) == 164, cat["specs"]
    plan = cat["recipes"][15296]
    assert plan[F["spec"]] == 9788 and plan[F["src"]] == 2 and plan[F["recipeItem"]] == 11612, plan
    assert plan[F["reqSkill"]] > 0, plan
    ench = cat["recipes"][7418]
    assert ench[F["out"]] == 0 and ench[F["enchant"]] > 0 and ench[F["line"]] == 333, ench
    assert 2018 not in cat["recipes"], "a rank spell creates nothing and is left out"
    assert 1240345 not in cat["recipes"], "the test profession's recipes are left out"
    retired = [num(r["Spell"]) for r in t["SkillLineAbility"] if num(r.get("AcquireMethod")) == 3]
    assert retired and all(s not in cat["recipes"] for s in retired), "retired rows are left out"
    assert cat["stations"] and all(name for name in cat["stations"].values()), cat["stations"]
    lua = render(cat, "fixture")
    assert lua.startswith("-- Generated") and "if BRutus.Client.isAnniversary then return end" in lua
    assert "[2657] = {186," in lua and 'en = "Mining"' in lua and "[9788] = 164," in lua
    print(f"prof_catalog: self-test passed ({len(cat['recipes'])} fixture recipes)")


def main(argv):
    if not argv:
        return selftest()
    build = argv[0]
    cache = argv[argv.index("--cache") + 1] if "--cache" in argv else None
    cat = build_catalog({name: read_csv(fetch(name, build, cache)) for name in TABLES})
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(cat, build))
    print(f"{OUT}: {len(cat['recipes'])} recipes on {len(cat['byLine'])} lines, "
          f"{len(cat['specs'])} specializations, {len(cat['stations'])} stations")


if __name__ == "__main__":
    main(sys.argv[1:])
