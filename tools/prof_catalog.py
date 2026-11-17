"""Static profession catalog for WoW: Forever and retail from wago.tools DB2 exports (issues #31, #167).

    python tools/prof_catalog.py                                    # self-test on tools/prof-catalog-fixture/
    python tools/prof_catalog.py <build> [--cache <dir>]            # writes Data/ProfCatalogForever.lua
    python tools/prof_catalog.py --retail <build> [--cache <dir>]   # writes Data/ProfCatalogRetail.lua

Recipes sit on the parent profession skill line. Each recipe keeps IDs and numbers only; the
client localizes names at run time. Rerun on every beta build, and on retail on every patch.

Retail keeps only the current expansion's recipes (the child line with the highest tier under each
profession): a row's SkillupSkillLineID names the expansion it levels. Most of them craft through
CraftingData (Effect 288) and many in quality tiers (CraftingDataItemQuality); an enchant crafts
through Effect 301, a feast through Effect 296. Their tiered reagents (ModifiedCraftingSpellSlot) are
left out: only the plain SpellReagents are listed. A row with no SkillupSkillLineID is left out too: on
12.1.5.70448 there are 208 that would make something, every one an older expansion's (spell 399040 and
below; Midnight's start at 471003), mostly WoD and Legion follower and garrison crafts (issue #177).
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
OUT_RETAIL = os.path.join(ROOT, "Data", "ProfCatalogRetail.lua")
FIXTURE = os.path.join(HERE, "prof-catalog-fixture")
TABLES = ["SkillLine", "SkillLineAbility", "SpellEffect", "SpellReagents", "SpellCastingRequirements",
          "SpellFocusObject", "Item", "ItemSparse", "ItemEffect", "ItemXItemEffect"]
# Forever's twelve professions. Poisons (40) and Comprehension (3012) are class skills,
# 2933/2934 is Blizzard's test profession. Primary = SkillLine category 11.
PROFESSIONS = [129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393]
# Retail's: no First Aid; Jewelcrafting (755) and Inscription (773) besides.
RETAIL_PROFESSIONS = [164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393, 755, 773]
CREATE_ITEM, ENCHANT_ITEM, ENCHANT_ITEM_TEMP = 24, 53, 54
CRAFT_ITEM, CRAFT_FEAST, CRAFT_ENCHANT = 288, 296, 301   # retail's crafting effects
RETAIL_TABLES = TABLES + ["CraftingData", "CraftingDataItemQuality"]
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


def build_catalog(t, retail=False):
    lines = RETAIL_PROFESSIONS if retail else PROFESSIONS
    skill = {num(r["ID"]): r for r in t["SkillLine"]}
    children, tiers = {}, {}
    for r in t["SkillLine"]:
        parent = num(r.get("ParentSkillLineID"))
        if parent not in lines:
            continue
        if retail:   # the current expansion: the highest tier under the profession
            if num(r.get("ParentTierIndex")) >= tiers.get(parent, -1):
                tiers[parent], children[parent] = num(r.get("ParentTierIndex")), num(r["ID"])
        else:
            children.setdefault(parent, num(r["ID"]))
    professions = {line: {"child": children.get(line, 0), "primary": num(skill[line].get("CategoryID")) == 11,
                          "en": skill[line].get("DisplayName_lang", "")}
                   for line in lines if line in skill}
    crafted = {num(r["ID"]): num(r.get("CraftedItemID")) for r in t.get("CraftingData", [])}
    tiered = collections.defaultdict(list)
    for r in t.get("CraftingDataItemQuality", []):
        tiered[num(r["CraftingDataID"])].append(num(r["ItemID"]))
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
        if retail and num(r.get("SkillupSkillLineID")) != professions[line]["child"]:
            continue   # another expansion's recipe
        effs = effects.get(spell, [])
        made = None   # (item, count): the item, or a crafting record's item, or its first quality tier
        for e in effs:
            kind = num(e["Effect"])
            # A feast's effect is retail's alone: Forever's catalog keeps what Effect 24 makes (issue #177).
            item = num(e.get("EffectItemType")) if kind == CREATE_ITEM or (retail and kind == CRAFT_FEAST) else 0
            if retail and not item and kind in (CRAFT_ITEM, CRAFT_FEAST):
                data = num(e.get("EffectMiscValue_0"))
                item = crafted.get(data) or min(tiered.get(data) or [0])
            if item:
                made = (item, max(1, num(e.get(count_key))))
                break
        kinds = (ENCHANT_ITEM, ENCHANT_ITEM_TEMP, CRAFT_ENCHANT) if retail else (ENCHANT_ITEM, ENCHANT_ITEM_TEMP)
        enchant = [e for e in effs if num(e["Effect"]) in kinds]
        if not made and not enchant:
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
        by_line[line].append(spell)
        # A recipe two professions learn (Synthetic Gordok Ogre Suit: Tailoring and
        # Leatherworking) is listed on both lines and recorded once, under the lowest line.
        if spell in recipes and recipes[spell][0] < line:
            continue
        recipes[spell] = [
            line, num(r.get("TrivialSkillLineRankLow")), num(r.get("TrivialSkillLineRankHigh")),
            made[0] if made else 0,
            made[1] if made else 0,
            num(enchant[0].get("EffectMiscValue_0")) if enchant else 0,
            min((num(s.get("RequiredSkillRank")) for s in req), default=0),
            spec, focus.get(spell, 0),
            3 if acquire in (1, 2) else 2 if items else 1,
            items[0] if items else 0,
            num(r.get("TradeSkillCategoryID")),
            flat,
        ]
    stations = {f: focus_names.get(f, "") for f in sorted({v[8] for v in recipes.values() if v[8]})}
    return {"professions": professions, "recipes": recipes, "specs": specs, "stations": stations,
            # A spell can have several rows on one line (per race or class): listed once.
            "byLine": {line: sorted(set(ids)) for line, ids in by_line.items()}}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(cat, build, retail=False):
    head = ([f"-- Generated by tools/prof_catalog.py --retail from wago.tools DB2, build {build}. Do not edit.",
             "-- Retail professions, the current expansion's (issue #167): IDs and numbers only; the client",
             "-- localizes names.",
             "if not GuildOS.Client.isRetail then return end"] if retail else
            [f"-- Generated by tools/prof_catalog.py from wago.tools DB2, build {build}. Do not edit.",
             "-- WoW: Forever professions (issue #31): IDs and numbers only; the client localizes names.",
             "if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end"])
    out = head + ["",
           "GuildOS.ProfCatalog = {", f"    build = {lua_str(build)},",
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
    assert all(ids == sorted(set(ids)) for ids in cat["byLine"].values()), "byLine is sorted, no duplicates"
    assert all(i in cat["recipes"] for ids in cat["byLine"].values() for i in ids), "every listed recipe exists"
    assert all(s in cat["byLine"][v[F["line"]]] for s, v in cat["recipes"].items()), "a recipe's line lists it"
    assert 461692 in cat["byLine"][165] and 461692 in cat["byLine"][197], "a two-profession recipe is on both lines"
    assert cat["recipes"][461692][F["line"]] == 165, "and recorded under the lowest one"
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
    assert lua.startswith("-- Generated")
    assert "[2657] = {186," in lua and 'en = "Mining"' in lua and "[9788] = 164," in lua
    assert "if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end" in lua, "Forever's catalog is Forever's"
    # A row whose only effect is retail's feast (296) makes nothing on Forever (issue #177).
    feast = dict(t["SpellEffect"][0], Effect=str(CRAFT_FEAST), EffectItemType="2840", SpellID="999296")
    row = dict(next(r for r in t["SkillLineAbility"] if r["Spell"] == "2657"), Spell="999296", AcquireMethod="1")
    t["SpellEffect"].append(feast)
    t["SkillLineAbility"].append(row)
    assert 999296 not in build_catalog(t)["recipes"], "Forever's path takes no Effect 296"
    print(f"prof_catalog: self-test passed ({len(cat['recipes'])} fixture recipes)")
    selftest_retail()


def selftest_retail():
    """Retail (issue #167): only the current expansion's recipes, recorded on their parent line."""
    fixture = os.path.join(FIXTURE, "retail")
    t = {name: read_csv(open(os.path.join(fixture, f"{name}.fixture.csv"), encoding="utf-8").read())
         for name in RETAIL_TABLES}
    cat = build_catalog(t, retail=True)
    F = {f: i for i, f in enumerate(FIELDS)}
    assert cat["professions"][164] == {"child": 2907, "primary": True, "en": "Blacksmithing"}, cat["professions"].get(164)
    assert cat["professions"][185]["child"] == 2908 and not cat["professions"][185]["primary"], cat["professions"].get(185)
    assert 438914 not in cat["recipes"], "a Khaz Algar recipe is not the current expansion's"
    assert 471041 not in cat["recipes"], "Recraft Equipment creates nothing"
    plate = cat["recipes"][1229598]
    assert plate[F["line"]] == 164 and plate[F["out"]] == 238018, plate
    assert plate[F["reagents"]] == [238528, 1, 237366, 2] and plate[F["src"]] == 1, plate
    assert (plate[F["yellow"]], plate[F["grey"]]) == (90, 100), plate
    quality = cat["recipes"][1230758]
    assert quality[F["out"]] == 237370 and quality[F["outCount"]] == 4, "a quality-tiered craft names its first tier"
    ench = cat["recipes"][1236054]
    assert ench[F["line"]] == 333 and ench[F["out"]] == 0 and ench[F["enchant"]] == 3795, ench
    assert ench[F["src"]] == 2 and ench[F["recipeItem"]] == 256737, "an enchant taught by a formula"
    feast = cat["recipes"][1232247]
    assert feast[F["line"]] == 185 and feast[F["out"]] == 228721 and feast[F["outCount"]] == 10, feast
    assert feast[F["src"]] == 3, "a recipe learned with the skill is automatic"
    assert cat["byLine"][164] == [1229598, 1230758], cat["byLine"]
    lua = render(cat, "fixture", retail=True)
    assert "if not GuildOS.Client.isRetail then return end" in lua, "the retail catalog is retail's"
    print(f"prof_catalog: retail self-test passed ({len(cat['recipes'])} fixture recipes)")


def main(argv):
    if not argv:
        return selftest()
    retail = "--retail" in argv
    argv = [a for a in argv if a != "--retail"]
    build = argv[0]
    cache = argv[argv.index("--cache") + 1] if "--cache" in argv else None
    tables = RETAIL_TABLES if retail else TABLES
    cat = build_catalog({name: read_csv(fetch(name, build, cache)) for name in tables}, retail=retail)
    out = OUT_RETAIL if retail else OUT
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(cat, build, retail=retail))
    print(f"{out}: {len(cat['recipes'])} recipes on {len(cat['byLine'])} lines, "
          f"{len(cat['specs'])} specializations, {len(cat['stations'])} stations")


if __name__ == "__main__":
    main(sys.argv[1:])
