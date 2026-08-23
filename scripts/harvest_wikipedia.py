#!/usr/bin/env python3
"""Erntet Kandidaten für den Fragenkatalog aus der deutschen Wikipedia.

Zwei Quellen, weil sie unterschiedliche Vokabularien liefern:

  1. `topviews`   — die meistaufgerufenen Artikel je Monat. Liefert Popularität
                    (Proxy für Häufigkeit), aber stark eigennamenlastig.
  2. `categories` — kuratierte Alltagskategorien (Lebensmittel, Säugetiere,
                    Werkzeuge …). Liefert genau das Gattungsvokabular, von dem
                    Kreuzworträtsel leben und das in `topviews` fehlt.

Ausgabe: JSON-Lines nach raw/wikipedia/, unveränderlich. Diese Stufe ist
absichtlich vom deterministischen Teil getrennt: Netzzugriffe sind nicht
reproduzierbar, `catalogbuild` muss es sein.

Beschreibungen kommen über prop=description mit `descriptionsource`:
  central = Wikidata               -> CC0
  local   = Wikipedia-Kurzbeschr.  -> CC BY-SA 4.0 (attributionspflichtig)
  extract = erster Artikelsatz     -> CC BY-SA 4.0 (nur als Lückenfüller)
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error, argparse
from collections import OrderedDict

API = "https://de.wikipedia.org/w/api.php"
REST = "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/de.wikipedia/all-access"
UA = ("KreuzwortCatalogBuild/0.1 (crossword clue catalog research; "
      "contact: maintainer of com.kreuzwort)")

# Wikimedia drosselt anonyme Clients. Ein fester Mindestabstand plus
# exponentielles Backoff auf 429 ist der Unterschied zwischen "Kategorie LEER"
# und echten Daten — der erste Lauf lief genau darin auf.
MIN_INTERVAL = 2.0
_last = [0.0]

EVERYDAY_CATEGORIES = [
    "Lebensmittel", "Gemüse", "Obst", "Getränk", "Gewürz", "Backware", "Käse",
    "Speise", "Süßware", "Fleischgericht", "Suppe",
    "Säugetiere", "Vögel", "Fische", "Insekten", "Reptilien", "Amphibien",
    "Haustier", "Spinnentiere", "Pilzart", "Baum", "Blume", "Zierpflanze",
    "Musikinstrument", "Werkzeug", "Kleidung", "Möbel", "Küchengerät",
    "Fahrzeug", "Wasserfahrzeug", "Luftfahrzeug", "Schienenfahrzeug",
    "Beruf", "Handwerksberuf", "Sportart", "Ballsport", "Kampfsport",
    "Spiel", "Kartenspiel", "Brettspiel", "Tanz", "Musikgenre",
    "Chemisches Element", "Mineral", "Schmuckstein", "Planet", "Sternbild",
    "Meteorologie", "Farbmittel",
    "Staat in Europa", "Hauptstadt in Europa", "Insel", "Gebirge", "See",
    "Griechische Gottheit", "Römische Gottheit", "Germanische Gottheit",
    "Körperteil", "Anatomie", "Organ", "Krankheit",
    "Bauwerk", "Schrift", "Sprache", "Währungseinheit",
    "Maßeinheit", "Metall", "Textilfaser", "Holzart",
]


def fetch(url, tries=6):
    for attempt in range(tries):
        wait = MIN_INTERVAL - (time.monotonic() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.monotonic()
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                ra = e.headers.get("Retry-After") or ""
                delay = float(ra) if ra.isdigit() else 2 ** (attempt + 1)
                print(f"  · {e.code}, warte {min(delay, 60):.0f}s", file=sys.stderr)
                time.sleep(min(delay, 60))
                continue
            if attempt == tries - 1:
                print(f"  ! aufgegeben: {e}  ({url[:110]})", file=sys.stderr)
                return None
            time.sleep(2 ** attempt)
        except Exception as e:
            if attempt == tries - 1:
                print(f"  ! aufgegeben: {e}  ({url[:110]})", file=sys.stderr)
                return None
            time.sleep(2 ** attempt)
    return None


def api(params):
    p = dict(params)
    p["format"] = "json"
    p["formatversion"] = "2"
    return fetch(API + "?" + urllib.parse.urlencode(p))


def batch(seq, n):
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def harvest_topviews(months):
    seen = OrderedDict()
    for (y, m) in months:
        d = fetch(f"{REST}/{y}/{m:02d}/all-days")
        if not d or "items" not in d:
            print(f"  topviews {y}-{m:02d}: nichts", file=sys.stderr)
            continue
        arts = d["items"][0].get("articles", [])
        added = 0
        for a in arts:
            t = a["article"].replace("_", " ")
            if ":" in t or t == "Hauptseite":
                continue
            v = a.get("views", 0)
            if t not in seen or seen[t] < v:
                seen[t] = v
                added += 1
        print(f"  topviews {y}-{m:02d}: {len(arts)} Artikel, {added} neu/besser", flush=True)
    return seen


def category_members(cat, depth, budget):
    out, subcats, cont = [], [], None
    while True:
        p = {"action": "query", "list": "categorymembers",
             "cmtitle": f"Kategorie:{cat}", "cmlimit": "500",
             "cmtype": "page|subcat", "cmnamespace": "0|14"}
        if cont:
            p["cmcontinue"] = cont
        d = api(p)
        if not d or "query" not in d:
            break
        for m in d["query"].get("categorymembers", []):
            if m["ns"] == 14:
                subcats.append(m["title"].split(":", 1)[-1])
            else:
                out.append(m["title"])
        cont = d.get("continue", {}).get("cmcontinue")
        if not cont or len(out) >= budget:
            break
    if depth > 0:
        for sc in subcats[:5]:
            if len(out) >= budget:
                break
            out.extend(category_members(sc, depth - 1, budget - len(out)))
    return out


def harvest_categories(cats, depth, budget_per_cat):
    result = {}
    for cat in cats:
        titles = category_members(cat, depth, budget_per_cat)
        if not titles:
            print(f"  Kategorie:{cat}: LEER (Name prüfen)", file=sys.stderr, flush=True)
            continue
        print(f"  Kategorie:{cat}: {len(titles)}", flush=True)
        for t in titles:
            result.setdefault(t, set()).add(cat)
    return result


def enrich(titles):
    info, done = {}, 0
    for chunk in batch(titles, 50):
        d = api({"action": "query", "prop": "description|pageviews",
                 "titles": "|".join(chunk), "pvipdays": "60"})
        done += len(chunk)
        if not d or "query" not in d:
            continue
        for pg in d["query"].get("pages", []):
            if pg.get("missing"):
                continue
            pv = pg.get("pageviews") or {}
            vals = [v for v in pv.values() if isinstance(v, int)]
            info[pg["title"]] = {
                "description": pg.get("description"),
                "descriptionsource": pg.get("descriptionsource"),
                "pageviews60": sum(vals),
                "pageviewDays": len(vals),
                "pageid": pg.get("pageid"),
            }
        if done % 500 < 50:
            print(f"    … {done} Titel angereichert", flush=True)
    return info


def enrich_extracts(titles):
    """Fallback für Titel ohne Wikidata-Beschreibung: erster Artikelsatz.

    Lizenzlich teurer (CC BY-SA statt CC0), deshalb nur als Lückenfüller — und
    in der Ausgabe klar als `descriptionSource: "extract"` markiert.
    """
    out = {}
    for chunk in batch(titles, 20):
        d = api({"action": "query", "prop": "extracts", "titles": "|".join(chunk),
                 "exintro": "1", "explaintext": "1", "exsentences": "1", "exlimit": "20"})
        if not d or "query" not in d:
            continue
        for pg in d["query"].get("pages", []):
            t = (pg.get("extract") or "").strip().replace("\n", " ")
            if 15 <= len(t) <= 300:
                out[pg["title"]] = t
    return out


def load_cache(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def save_cache(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="raw/wikipedia")
    ap.add_argument("--months", type=int, default=14)
    ap.add_argument("--cat-depth", type=int, default=1)
    ap.add_argument("--cat-budget", type=int, default=400)
    ap.add_argument("--max-extracts", type=int, default=4000)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    months, y, m = [], 2026, 6
    for _ in range(a.months):
        months.append((y, m))
        m -= 1
        if m == 0:
            y -= 1
            m = 12

    print("== topviews ==", flush=True)
    top = harvest_topviews(months)
    print(f"   {len(top)} eindeutige Titel aus topviews", flush=True)

    print("== Alltagskategorien ==", flush=True)
    cat_cache_path = os.path.join(a.out, "_cache_categories.json")
    cat_cache = load_cache(cat_cache_path, {})
    for cat in EVERYDAY_CATEGORIES:
        if cat in cat_cache:
            print(f"  Kategorie:{cat}: {len(cat_cache[cat])} (Cache)", flush=True)
            continue
        titles = category_members(cat, a.cat_depth, a.cat_budget)
        cat_cache[cat] = titles
        save_cache(cat_cache_path, cat_cache)
        print(f"  Kategorie:{cat}: {len(titles)}"
              + ("  << LEER, Name pruefen" if not titles else ""), flush=True)
    cats = {}
    for cat, titles in cat_cache.items():
        for t in titles:
            cats.setdefault(t, set()).add(cat)
    print(f"   {len(cats)} eindeutige Titel aus Kategorien", flush=True)

    all_titles = OrderedDict()
    for t in cats:
        all_titles[t] = None
    for t in top:
        all_titles.setdefault(t, None)
    info_cache_path = os.path.join(a.out, "_cache_info.json")
    info = load_cache(info_cache_path, {})
    todo = [t for t in all_titles if t not in info]
    print(f"== Anreicherung: {len(todo)} offen von {len(all_titles)} ==", flush=True)
    for chunk in batch(todo, 50):
        info.update(enrich(chunk))
        save_cache(info_cache_path, info)
    print(f"   {len(info)} Titel im Cache", flush=True)

    missing = [t for t, i in info.items()
               if not i.get("description") and i.get("descriptionsource") != "none"]
    missing = missing[:a.max_extracts]
    print(f"== Fallback-Extrakte für {len(missing)} Titel ==", flush=True)
    for chunk in batch(missing, 20):
        got = enrich_extracts(chunk)
        for t in chunk:
            if t in got:
                info[t]["description"] = got[t]
                info[t]["descriptionsource"] = "extract"
            else:
                info[t]["descriptionsource"] = "none"   # nicht erneut versuchen
        save_cache(info_cache_path, info)

    path = os.path.join(a.out, "de-candidates.jsonl")
    n = 0
    with open(path, "w", encoding="utf-8") as f:
        for t in all_titles:
            i = info.get(t)
            if not i:
                continue
            f.write(json.dumps({
                "title": t,
                "description": i["description"],
                "descriptionSource": i["descriptionsource"],
                "pageviews60": i["pageviews60"],
                "topviewsMonthly": top.get(t),
                "categories": sorted(cats.get(t, [])),
                "pageid": i["pageid"],
                "source": "de.wikipedia",
            }, ensure_ascii=False) + "\n")
            n += 1
    with open(os.path.join(a.out, "harvest-meta.json"), "w", encoding="utf-8") as f:
        json.dump({
            "harvestedTitles": n,
            "months": [f"{yy}-{mm:02d}" for (yy, mm) in months],
            "categories": EVERYDAY_CATEGORIES,
            "licenses": {
                "descriptionSource=central": "Wikidata, CC0",
                "descriptionSource=local": "Wikipedia Kurzbeschreibung, CC BY-SA 4.0",
                "descriptionSource=extract": "Wikipedia Artikeltext, CC BY-SA 4.0",
                "titles/pageviews": "Wikimedia, CC0 (Daten)",
            },
            "note": "Rohdaten. Unveraendert lassen; catalogbuild liest hieraus.",
        }, f, ensure_ascii=False, indent=2)
    print(f"== fertig: {n} Datensätze -> {path}", flush=True)


if __name__ == "__main__":
    main()
