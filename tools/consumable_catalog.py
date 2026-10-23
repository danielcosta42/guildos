"""Retail's raid consumables from wago.tools DB2 exports (issue #187).

    python tools/consumable_catalog.py                          # self-test on tools/consumable-catalog-fixture/
    python tools/consumable_catalog.py <build> [--cache <dir>]  # writes Data/ConsumablesRetail.lua

The consumable check matches a raider's auras by spell id, so the catalog is the buffs the current
expansion's consumables put on a character. The current expansion is the highest ExpansionID any
consumable (Item class 0) carries: 11, Midnight, on 12.1.5.70448.

- flask: a Flask (subclass 3) whose on-use spell raises a rating or a stat (aura 189 MOD_RATING or
  29 MOD_STAT). The Haranir profession phials (aura 511) and the PvP flask (a dummy aura) are out.
- rune: an Other consumable (subclass 8) whose on-use spell raises a stat (aura 29): the augment rune.
- food: Well Fed is the server's, not the item's. The food's Refreshment ticks "Become Well Fed"
  (aura 23, a periodic trigger) and the buff that follows is linked to nothing in the client's data.
  The buffs are the spells named "Well Fed" or "Hearty Well Fed" that raise a rating or a stat, above
  the expansion's own Become Well Fed (the one its food triggers most): each expansion has its own,
  and its Well Fed spells come after it (The War Within's last is 465481, Midnight's Become Well Fed
  1219179). The names are wago's enUS; the client matches by id.

Weapon oils and stones put a temporary enchant on the weapon (Effect 54), not an aura: the check reads
the player's own with GetWeaponEnchantInfo and needs no table. Rerun on every retail patch: a new flask
or food is a new spell id.
"""
import collections
import csv
import io
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Data", "ConsumablesRetail.lua")
FIXTURE = os.path.join(HERE, "consumable-catalog-fixture")
TABLES = ["Item", "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellEffect", "SpellName"]
CONSUMABLE, FLASK, FOOD, OTHER = 0, 3, 5, 8       # Item class and subclasses
APPLY_AURA, ON_USE = 6, 0                          # SpellEffect.Effect, ItemEffect.TriggerType
MOD_STAT, MOD_RATING, PERIODIC_TRIGGER = 29, 189, 23
STAT_AURAS = (MOD_STAT, MOD_RATING)
WELL_FED = ("Well Fed", "Hearty Well Fed")
BECOME_WELL_FED = "Become Well Fed"


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
    req = urllib.request.Request(url, headers={"User-Agent": "guildos-consumable-catalog/1.0"})
    text = urllib.request.urlopen(req, timeout=300).read().decode("utf-8")
    if path:
        os.makedirs(cache, exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    return text


def build_catalog(t):
    items = {num(r["ID"]): num(r["SubclassID"]) for r in t["Item"] if num(r["ClassID"]) == CONSUMABLE}
    expansion_of = {num(r["ID"]): num(r["ExpansionID"]) for r in t["ItemSparse"] if num(r["ID"]) in items}
    expansion = max(expansion_of.values())
    current = {i: sub for i, sub in items.items() if expansion_of.get(i) == expansion}
    effect_of = {num(r["ID"]): r for r in t["ItemEffect"]}
    on_use = collections.defaultdict(list)   # item -> its on-use spells
    for r in t["ItemXItemEffect"]:
        e = effect_of.get(num(r["ItemEffectID"]))
        if e and num(r["ItemID"]) in current and num(e["TriggerType"]) == ON_USE and num(e["SpellID"]):
            on_use[num(r["ItemID"])].append(num(e["SpellID"]))
    effects = collections.defaultdict(list)
    for r in t["SpellEffect"]:
        effects[num(r["SpellID"])].append(r)
    names = {num(r["ID"]): r["Name_lang"] for r in t["SpellName"]}

    def auras(spell):
        return {num(e["EffectAura"]) for e in effects.get(spell, []) if num(e["Effect"]) == APPLY_AURA}

    def raises_stat(spell):
        return bool(auras(spell) & set(STAT_AURAS))

    def buffs_of(subclass, aura_set):
        return sorted({s for i, sub in current.items() if sub == subclass
                       for s in on_use[i] if auras(s) & set(aura_set)})

    become = collections.Counter()
    for i, sub in current.items():
        if sub != FOOD:
            continue
        for s in on_use[i]:
            for e in effects.get(s, []):
                trigger = num(e["EffectTriggerSpell"])
                if num(e["EffectAura"]) == PERIODIC_TRIGGER and names.get(trigger) == BECOME_WELL_FED:
                    become[trigger] += 1
    anchor = become.most_common(1)[0][0] if become else None
    food = sorted(s for s, n in names.items()
                  if anchor and s > anchor and n in WELL_FED and raises_stat(s))
    return {"expansion": expansion, "become": anchor,
            "flask": buffs_of(FLASK, STAT_AURAS), "rune": buffs_of(OTHER, (MOD_STAT,)), "food": food}


def lua_list(ids, per_line=8):
    lines = [", ".join(map(str, ids[i:i + per_line])) for i in range(0, len(ids), per_line)]
    if len(lines) <= 1:
        return "{ " + (lines[0] if lines else "") + " }"
    return "{\n" + "".join(f"        {line},\n" for line in lines) + "    }"


def render(cat, build):
    out = [f"-- Generated by tools/consumable_catalog.py from wago.tools DB2, build {build}. Do not edit.",
           "-- Retail's raid consumables, the current expansion's (issue #187): the buff spell ids a raider's",
           "-- auras are matched against. The client names them.",
           "if not GuildOS.Client.isRetail then return end",
           "",
           "GuildOS.ConsumableCatalog = {",
           f'    build = "{build}",',
           f"    expansion = {cat['expansion']},",
           f"    flask = {lua_list(cat['flask'])},",
           f"    rune = {lua_list(cat['rune'])},",
           f"    food = {lua_list(cat['food'])},",
           "}",
           ""]
    return "\n".join(out)


def selftest():
    t = {name: read_csv(open(os.path.join(FIXTURE, f"{name}.fixture.csv"), encoding="utf-8").read())
         for name in TABLES}
    cat = build_catalog(t)
    assert cat["expansion"] == 11, "the current expansion is the highest a consumable carries"
    assert cat["flask"] == [1235108], f"a combat flask; no profession phial, no PvP flask, no older one: {cat['flask']}"
    assert cat["rune"] == [1264426], (
        f"the augment rune raises a stat; a weightstone is an enchant, a charm that raises a rating no rune: {cat['rune']}")
    assert cat["become"] == 1219179, (
        "the Become Well Fed the expansion's food ticks most, not the lowest one any of it ticks (the last expansion's)")
    assert cat["food"] == [1232318, 1233703], (
        f"Well Fed and Hearty Well Fed above it that raise a stat: not the older one, not a dummy, not "
        f"another name: {cat['food']}")
    no_food = dict(t, SpellEffect=[r for r in t["SpellEffect"] if r["EffectAura"] != str(PERIODIC_TRIGGER)])
    assert build_catalog(no_food)["food"] == [], "with no Become Well Fed to stand on, no food is guessed"
    lua = render(cat, "fixture")
    assert lua.startswith("-- Generated") and "if not GuildOS.Client.isRetail then return end" in lua
    assert "flask = { 1235108 }," in lua and "food = { 1232318, 1233703 }," in lua, lua
    many = render(dict(cat, food=list(range(1, 11))), "fixture")
    assert "food = {\n        1, 2, 3, 4, 5, 6, 7, 8,\n        9, 10,\n    }," in many, many
    print(f"consumable_catalog: self-test passed ({len(cat['flask'])} flask, {len(cat['rune'])} rune, "
          f"{len(cat['food'])} food)")


def main(argv):
    if not argv:
        return selftest()
    build = argv[0]
    cache = argv[argv.index("--cache") + 1] if "--cache" in argv else None
    cat = build_catalog({name: read_csv(fetch(name, build, cache)) for name in TABLES})
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(cat, build))
    print(f"{OUT}: expansion {cat['expansion']}, {len(cat['flask'])} flask buffs, {len(cat['rune'])} rune, "
          f"{len(cat['food'])} food buffs above Become Well Fed {cat['become']}")


if __name__ == "__main__":
    main(sys.argv[1:])
