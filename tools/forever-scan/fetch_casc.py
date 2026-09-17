"""Download files of one WoW build from wago.tools' CASC endpoint, by path prefix.

    python fetch_casc.py <build> <out_dir> <path-prefix> [<path-prefix> ...]

Writes each file under out_dir/<path> and prints how many came back per prefix.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

build, out, prefixes = sys.argv[1], sys.argv[2], sys.argv[3:]
UA = {"User-Agent": "guildos-addon-research/1.0"}


def get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 403):
                return e.code, b""
            time.sleep(1.5 * (i + 1))
        except Exception:
            time.sleep(1.5 * (i + 1))
    return 0, b""


def fetch(item):
    fdid, path = item
    dest = os.path.join(out, *path.split("/"))
    if os.path.exists(dest):
        return "cached"
    code, body = get(f"https://wago.tools/api/casc/{fdid}?version={urllib.parse.quote(build)}")
    if code != 200:
        return f"http{code}"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(body)
    return "ok"


for prefix in prefixes:
    code, body = get("https://wago.tools/api/files?search=" + urllib.parse.quote(prefix))
    listing = json.loads(body or b"{}") if code == 200 else {}
    items = [(k, v) for k, v in listing.items() if v.startswith(prefix) and (v.endswith(".lua") or v.endswith(".toc"))]
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(fetch, items))
    counts = {r: results.count(r) for r in set(results)}
    print(f"{prefix}: listed={len(items)} {counts}", flush=True)
