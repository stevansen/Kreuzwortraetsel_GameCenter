#!/usr/bin/env python3
"""Reichert eine Stichprobe aus dem Kategorie-Cache an.

Zweck: die deterministische Pipeline (catalogbuild) an echten Wikipedia-Daten
prüfen, ohne auf den vollständigen, gedrosselten Volllauf zu warten. Schreibt
nach de-candidates-sample.jsonl; der Volllauf schreibt eine andere Datei.
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error

API = "https://de.wikipedia.org/w/api.php"
UA = ("KreuzwortCatalogBuild/0.1 (crossword clue catalog research; "
      "contact: maintainer of com.kreuzwort)")
MIN_INTERVAL = 2.0
_last = [0.0]

def fetch(url, tries=5):
    for attempt in range(tries):
        w = MIN_INTERVAL - (time.monotonic() - _last[0])
        if w > 0: time.sleep(w)
        _last[0] = time.monotonic()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                ra = e.headers.get("Retry-After") or ""
                d = float(ra) if ra.isdigit() else 2 ** (attempt + 1)
                print(f"  · {e.code}, warte {min(d,60):.0f}s", file=sys.stderr)
                time.sleep(min(d, 60)); continue
            if attempt == tries - 1: return None
            time.sleep(2 ** attempt)
        except Exception:
            if attempt == tries - 1: return None
            time.sleep(2 ** attempt)
    return None

def api(p):
    p = dict(p); p["format"] = "json"; p["formatversion"] = "2"
    return fetch(API + "?" + urllib.parse.urlencode(p))

def chunks(xs, n):
    xs = list(xs)
    for i in range(0, len(xs), n): yield xs[i:i+n]

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 1200
outdir = "raw/wikipedia"
cats = json.load(open(os.path.join(outdir, "_cache_categories.json"), encoding="utf-8"))

# Vorauswahl: nur Titel, die als Gitterantwort überhaupt Chancen haben.
# Spart Anfragen, die der Normalisierer ohnehin verwerfen würde.
def plausible(t):
    if any(c in t for c in " -–/().,'’0123456789"): return False
    return 3 <= len(t) <= 16

bycat = {}
for cat, titles in cats.items():
    bycat[cat] = [t for t in titles if plausible(t)]

# Round-Robin über die Kategorien, damit die Stichprobe breit statt tief ist.
picked, i = [], 0
order = sorted(bycat)
while len(picked) < limit:
    added = False
    for cat in order:
        if i < len(bycat[cat]):
            picked.append((bycat[cat][i], cat)); added = True
            if len(picked) >= limit: break
    if not added: break
    i += 1

titlecats = {}
for t, c in picked: titlecats.setdefault(t, set()).add(c)
titles = sorted(titlecats)
print(f"{len(titles)} plausible Titel aus {len(order)} Kategorien", flush=True)

info = {}
for ch in chunks(titles, 50):
    d = api({"action": "query", "prop": "description|pageviews",
             "titles": "|".join(ch), "pvipdays": "60"})
    if not d or "query" not in d: continue
    for pg in d["query"].get("pages", []):
        if pg.get("missing"): continue
        pv = pg.get("pageviews") or {}
        vals = [v for v in pv.values() if isinstance(v, int)]
        info[pg["title"]] = {"description": pg.get("description"),
                             "src": pg.get("descriptionsource"),
                             "views": sum(vals), "pageid": pg.get("pageid")}
    print(f"  … {len(info)}/{len(titles)}", flush=True)

missing = [t for t, v in info.items() if not v["description"]]
print(f"Extrakt-Fallback für {len(missing)}", flush=True)
for ch in chunks(missing, 20):
    d = api({"action": "query", "prop": "extracts", "titles": "|".join(ch),
             "exintro": "1", "explaintext": "1", "exsentences": "1", "exlimit": "20"})
    if not d or "query" not in d: continue
    for pg in d["query"].get("pages", []):
        t = (pg.get("extract") or "").strip().replace("\n", " ")
        if 15 <= len(t) <= 300 and pg["title"] in info:
            info[pg["title"]]["description"] = t
            info[pg["title"]]["src"] = "extract"

path = os.path.join(outdir, "de-candidates-sample.jsonl")
n = 0
with open(path, "w", encoding="utf-8") as f:
    for t in titles:
        v = info.get(t)
        if not v: continue
        f.write(json.dumps({
            "title": t, "description": v["description"], "descriptionSource": v["src"],
            "pageviews60": v["views"], "topviewsMonthly": None,
            "categories": sorted(titlecats[t]), "pageid": v["pageid"],
            "source": "de.wikipedia",
        }, ensure_ascii=False) + "\n")
        n += 1
print(f"fertig: {n} → {path}")
