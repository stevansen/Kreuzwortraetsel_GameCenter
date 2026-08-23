#!/usr/bin/env python3
"""Leipzig Corpora Collection → Worthäufigkeiten.

Ersetzt den Aufrufzahlen-Proxy durch ein echtes Frequenzmaß. Artikelaufrufe
messen Popularität („Brot" wird seltener angeklickt als eine aktuelle
Berühmtheit), Korpusfrequenzen messen Wortgebrauch — und nur das gehört in die
Schwierigkeitsberechnung.

Ausgabe: raw/leipzig/de-frequencies.tsv mit `NORMALISIERT \t Häufigkeit`,
aggregiert über Groß-/Kleinschreibung (brot + Brot -> BROT), aber **nicht** über
Flexion (BROTE bleibt eine eigene Gitterantwort).

Quelle: Leipzig Corpora Collection, CC BY 4.0.
  D. Goldhahn, T. Eckart, U. Quasthoff: Building Large Monolingual Dictionaries
  at the Leipzig Corpora Collection. LREC 2012.
"""
import json, os, sys, tarfile, argparse

UMLAUTS = str.maketrans({"ß": "SS", "ẞ": "SS"})
ALLOWED = set("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ")


def normalize(word):
    w = word.upper().translate(UMLAUTS)
    if not w or not all(c in ALLOWED for c in w):
        return None
    if not (3 <= len(w) <= 15):
        return None
    return w


def read_archive(path, counts):
    """Addiert ein Korpus in `counts`. Gibt (Rohzeilen, Tokens) zurück."""
    raw_lines, total = 0, 0
    with tarfile.open(path, "r:gz") as tf:
        member = next((m for m in tf.getmembers() if m.name.endswith("-words.txt")), None)
        if member is None:
            print(f"  ! keine *-words.txt in {path}", file=sys.stderr)
            return 0, 0
        print(f"  {member.name} ({member.size / 1e6:.1f} MB)", flush=True)
        for line in tf.extractfile(member):
            parts = line.decode("utf-8", "replace").rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            raw_lines += 1
            try:
                freq = int(parts[2])
            except ValueError:
                continue
            # Gesamtzahl VOR dem Filtern: die Zipf-Skala braucht die echte
            # Korpusgröße, sonst verschiebt sich die ganze Verteilung.
            total += freq
            key = normalize(parts[1])
            if key:
                counts[key] = counts.get(key, 0) + freq
    return raw_lines, total


def main():
    ap = argparse.ArgumentParser()
    # Mehrere Korpora zusammenzuführen ist bei Frequenzlisten übliche Praxis:
    # ein Nachrichtenkorpus allein kennt konkrete Substantive schlecht. Vier
    # 1M-Korpora unterschiedlicher Textsorten geben ~4x Tokens und eine deutlich
    # verlässlichere Zipf-Schätzung als eines allein.
    ap.add_argument("--archives", nargs="+", default=None)
    ap.add_argument("--archive", default="raw/leipzig/deu_news_2024_1M.tar.gz")
    ap.add_argument("--out", default="raw/leipzig/de-frequencies.tsv")
    a = ap.parse_args()

    archives = a.archives or [a.archive]
    archives = [p for p in archives if os.path.exists(p)]
    if not archives:
        sys.exit("kein Korpus gefunden")

    counts, total_tokens, raw_lines = {}, 0, 0
    for path in sorted(archives):
        print(f"lese {os.path.basename(path)}", flush=True)
        rl, tt = read_archive(path, counts)
        raw_lines += rl
        total_tokens += tt

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as out:
        for w in sorted(counts, key=lambda k: (-counts[k], k)):
            out.write(f"{w}\t{counts[w]}\n")

    meta = {
        "corpus": "+".join(os.path.basename(p).replace(".tar.gz", "") for p in sorted(archives)),
        "corpusCount": len(archives),
        "rawWordForms": raw_lines,
        "normalizedForms": len(counts),
        "totalTokens": total_tokens,
        "license": "CC BY 4.0",
        "attribution": ("Leipzig Corpora Collection / Wortschatz Leipzig; "
                        "Goldhahn, Eckart, Quasthoff (LREC 2012)"),
        "url": "https://wortschatz.uni-leipzig.de/",
        "note": ("Haeufigkeiten aggregiert ueber Gross-/Kleinschreibung, nicht "
                 "ueber Flexion. zipf = log10(freq / totalTokens * 1e6) + 3."),
    }
    with open(os.path.join(os.path.dirname(a.out), "leipzig-meta.json"), "w",
              encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    print(f"{raw_lines} Wortformen gelesen, {len(counts)} gitterfähig, "
          f"{total_tokens} Tokens gesamt -> {a.out}")
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:12]
    print("häufigste gitterfähige Wörter:")
    for w, c in top:
        import math
        z = math.log10(c / total_tokens * 1e6) + 3
        print(f"  {w:14} {c:>9}  zipf {z:.2f}")


if __name__ == "__main__":
    main()
