"""What a WoW: Forever build means for Guild OS, without launching the game.

    python tools/forever-scan/scan.py <forever-build> <anniversary-build> <work-dir> [<forever-exe> <anniversary-exe>]

  e.g. python tools/forever-scan/scan.py 1.60.1.69893 2.5.6.69795 %TEMP%/forever-scan \
         "E:/World of Warcraft/_classic_beta_/WowB.exe" "E:/World of Warcraft/_anniversary_/WowClassic.exe"

Steps (docs/forever/README.md has the reasoning):
1. Download both builds' Blizzard_APIDocumentationGenerated from wago.tools' CASC endpoint,
   and every Blizzard_* Lua and TOC the community listfile names for the Forever build.
2. Index each build's documentation with luajit (index_docs.lua): every function, event and
   enum, with the Secret*/Restrict* fields it declares.
3. Read the probe's inventory (Core/Probe.lua) and classify each API and event:
   removed (documented on Anniversary, not on Forever), new, flagged, present, undocumented.
4. For the undocumented legacy globals: look for a Lua definition in the Forever UI files, and
   for the name in each executable. Present in Anniversary's executable and nowhere in Forever
   is the strong signal that a function is gone. (Presence in an executable proves little: a
   namespaced function is registered under its short name too.)

Writes <work-dir>/report.txt. Needs python 3, luajit on PATH, and network access to wago.tools.
"""
import mmap
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(os.path.dirname(HERE))
DOCS = "interface/addons/blizzard_apidocumentationgenerated/"


def run(*cmd, stdout=None):
    subprocess.run(cmd, check=True, stdout=stdout)


def index(build_dir, out):
    with open(out, "w", encoding="utf-8") as f:
        run("luajit", os.path.join(HERE, "index_docs.lua"), os.path.join(build_dir, *DOCS.split("/")), stdout=f)
    table = {}
    for line in open(out, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3:
            table[(parts[0], parts[1])] = parts[2]
    return table


def exe_has(path, name):
    if not path or not os.path.exists(path):
        return None
    with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        return m.find(b"\x00" + name.encode() + b"\x00") != -1


def main():
    forever, anniversary, work = sys.argv[1], sys.argv[2], sys.argv[3]
    fexe = sys.argv[4] if len(sys.argv) > 4 else None
    aexe = sys.argv[5] if len(sys.argv) > 5 else None
    fdir, adir = os.path.join(work, "forever"), os.path.join(work, "anniversary")
    fetch = os.path.join(HERE, "fetch_casc.py")
    run(sys.executable, fetch, forever, fdir, DOCS, "interface/addons/blizzard_")
    run(sys.executable, fetch, anniversary, adir, DOCS)
    fv = index(fdir, os.path.join(work, "forever.tsv"))
    an = index(adir, os.path.join(work, "anniversary.tsv"))

    inv_path = os.path.join(work, "inventory.tsv")
    with open(inv_path, "w", encoding="utf-8") as f:
        run("luajit", os.path.join(HERE, "dump_probe.lua"), os.path.join(ADDON, "Core", "Probe.lua"), stdout=f)
    inventory = [l.rstrip("\n").split("\t") for l in open(inv_path, encoding="utf-8") if l.strip()]

    ui = {}
    for d, _, files in os.walk(os.path.join(fdir, "interface", "addons")):
        for name in files:
            if name.endswith(".lua") and "apidocumentation" not in d:
                p = os.path.join(d, name)
                ui[p] = open(p, encoding="utf-8", errors="replace").read()

    groups = {k: [] for k in ("removed", "new", "flagged", "present", "undocumented: gone", "undocumented: defined in Forever Lua", "undocumented: unknown")}
    for kind, name in inventory:
        key = ("function" if kind == "api" else "event", name)
        in_f, in_a, flags = key in fv, key in an, fv.get(key, "")
        if in_a and not in_f:
            groups["removed"].append(name)
        elif in_f and not in_a:
            groups["new"].append(f"{name} [{flags}]" if flags else name)
        elif in_f:
            groups["flagged" if flags else "present"].append(f"{name} [{flags}]" if flags else name)
        else:
            short = name.split(".")[-1]
            pat = re.compile(r"^\s*(?:function\s+" + re.escape(name) + r"\s*\(|" + re.escape(name) + r"\s*=)", re.M)
            defined = next((os.path.relpath(p, fdir) for p, s in ui.items() if pat.search(s)), None)
            if defined:
                groups["undocumented: defined in Forever Lua"].append(f"{name} ({defined})")
            elif exe_has(aexe, short) and exe_has(fexe, short) is False:
                groups["undocumented: gone"].append(name)
            else:
                groups["undocumented: unknown"].append(name)

    counts = {k: sum(1 for (kind, _), v in table.items() if "Secret" in v) for k, table in (("forever", fv), ("anniversary", an))}
    report = os.path.join(work, "report.txt")
    with open(report, "w", encoding="utf-8") as f:
        f.write(f"Forever {forever} vs Anniversary {anniversary}\n")
        f.write(f"documented functions {sum(1 for k in fv if k[0] == 'function')} vs {sum(1 for k in an if k[0] == 'function')}; "
                f"entries with Secret fields {counts['forever']} vs {counts['anniversary']}\n\n")
        for k, names in groups.items():
            f.write(f"== {k} ({len(names)})\n")
            for n in names:
                f.write(f"  {n}\n")
    print(report)


if __name__ == "__main__":
    main()
