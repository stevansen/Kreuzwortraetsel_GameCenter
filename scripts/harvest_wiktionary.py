#!/usr/bin/env python3
"""Deutsches Wiktionary (Dump) → Lemmata mit Definitionen.

Warum der Dump und nicht die API: die deutschen Substantiv-Kategorien haben
sechsstellige Mitgliederzahlen. Über die gedrosselte MediaWiki-API wären das
Tage; ein 267-MB-Download ist Minuten. Und der Dump ist reproduzierbar — die
Datei bleibt, was sie ist.

Extrahiert wird ausschließlich der **deutsche** Abschnitt und daraus der Block
`{{Bedeutungen}}`. Genau der ist das, was ein Kreuzwortr. als Frage braucht:
„aus Mehl, Wasser und weiteren Zutaten gebackenes Lebensmittel" für BROT.

Ausgabe: raw/wiktionary/de-entries.jsonl
Quelle: de.wiktionary.org, CC BY-SA 4.0 (attributionspflichtig).
"""
import bz2, json, os, re, sys, argparse
import xml.etree.ElementTree as ET

# --- Wortarten -------------------------------------------------------------
# Flektierte Formen werden verworfen: ihre "Bedeutung" lautet "Genitiv Singular
# des Substantivs X" — als Frage nutzlos und sie verrät die Antwort.
KEEP_WORDCLASS = {
    "Substantiv": "noun", "Verb": "verb", "Adjektiv": "adjective",
    "Adverb": "adverb", "Eigenname": "propernoun", "Toponym": "propernoun",
    "Nachname": "propernoun", "Vorname": "propernoun",
    "Abkürzung": "abbreviation", "Interjektion": "interjection",
    "Numerale": "numeral", "Pronomen": "pronoun",
}
SKIP_WORDCLASS = {
    "Deklinierte Form", "Konjugierte Form", "Partizip", "Partizip I",
    "Partizip II", "Erweiterter Infinitiv", "Grammatischer Begriff",
    "Suffix", "Präfix", "Wortverbindung", "Redewendung", "Sprichwort",
    "Abfolge", "Buchstabe", "Symbol", "Gebundenes Lexem",
}

RE_GERMAN_SECTION = re.compile(
    r"==\s*[^=\n]*?\(\{\{Sprache\|Deutsch\}\}\)\s*==(.*?)(?=\n==\s[^=]|\Z)", re.S)
RE_WORDCLASS = re.compile(r"\{\{Wortart\|([^|}]+)\|Deutsch\}\}")
RE_BEDEUTUNGEN = re.compile(r"\{\{Bedeutungen\}\}(.*?)(?=\n\{\{[A-ZÄÖÜ]|\Z)", re.S)
RE_SENSE_LINE = re.compile(r"^:+\s*\[[^\]]*\]\s*(.+)$")
RE_KONTEXT = re.compile(r"\{\{K\|([^}]*)\}\}")
# Verweise auf andere Bedeutungen: „etwas nach der Form von [1] Hergestelltes"
# ist ohne Bedeutung [1] sinnlos und als eigenständige Frage unbrauchbar.
RE_CROSSREF = re.compile(r"\[\s*\d")

# Kontextmarker, die eine Bedeutung für ein Familienprodukt disqualifizieren.
# „Kartoffel" hat eine Bedeutung „Knollennase" — als Rätselfrage nicht tragbar.
BAD_CONTEXT = {
    "abwertend", "vulgär", "derb", "diskriminierend", "Schimpfwort",
    "beleidigend", "rassistisch", "sexuell", "Sexualität", "obszön",
    "Vulgärsprache", "pejorativ",
}
# Grammatik- und Gebrauchsmarker sind keine Themen.
NON_TOPIC = {
    "kPl.", "kSg.", "Pl.", "Sg.", "übertragen", "veraltet", "veraltend",
    "regional", "umgangssprachlich", "gehoben", "scherzhaft", "ironisch",
    "selten", "fachsprachlich", "bildlich", "kein Plural", "kein Singular",
    "veraltende Bedeutung", "salopp", "poetisch", "dichterisch",
}


def clean_wikitext(s):
    """Wikitext → Klartext, in der Reihenfolge, in der es sicher ist."""
    # Kontext-Vorlagen liefern Themenmarker; Inhalt merken, Vorlage entfernen.
    topics = []
    for m in RE_KONTEXT.finditer(s):
        topics += [p.strip() for p in m.group(1).split("|")
                   if p.strip() and "=" not in p]
    s = RE_KONTEXT.sub("", s)
    s = re.sub(r"<ref[^>]*>.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"<ref[^>]*/>", "", s)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", s)
    # Links: [[Ziel|Text]] -> Text, [[Ziel]] -> Ziel
    s = re.sub(r"\[\[([^\]|]*)\|([^\]]*)\]\]", r"\2", s)
    s = re.sub(r"\[\[([^\]]*)\]\]", r"\1", s)
    # Restliche Vorlagen: erstes Argument behalten, wenn es Text ist.
    for _ in range(3):
        s = re.sub(r"\{\{([^{}|]*)(\|[^{}]*)?\}\}", r"\1", s)
    s = s.replace("'''", "").replace("''", "")
    s = re.sub(r"\s+", " ", s).strip()
    s = s.strip(" ;:,")
    return s, topics


def _subsections(body):
    """Der deutsche Abschnitt enthält Unterabschnitte je Wortart.

    Ohne diese Aufteilung verwirft ein einziges `{{Wortart|Deklinierte Form}}`
    die ganze Seite — „Haus" fiel im ersten Lauf genau darüber, weil dort neben
    dem Substantiv auch die deklinierte Form steht.
    """
    parts = re.split(r"\n(?==== |=== )", body)
    return parts if len(parts) > 1 else [body]


def _senses_from(block):
    senses, topics, dropped = [], [], 0
    for line in block.split("\n"):
        sm = RE_SENSE_LINE.match(line.strip())
        if not sm:
            continue
        raw = sm.group(1)
        cleaned, tp = clean_wikitext(raw)
        if any(b.lower() in t.lower() for t in tp for b in BAD_CONTEXT):
            dropped += 1
            continue
        if RE_CROSSREF.search(raw.replace("[[", "").replace("]]", "")):
            dropped += 1
            continue
        topics += [t for t in tp if t not in NON_TOPIC and "." not in t]
        if 8 <= len(cleaned) <= 240:
            senses.append(cleaned)
        if len(senses) >= 4:
            break
    return senses, topics, dropped


def parse_page(title, text):
    m = RE_GERMAN_SECTION.search(text)
    if not m:
        return None

    for sub in _subsections(m.group(1)):
        classes = RE_WORDCLASS.findall(sub)
        if not classes or any(c in SKIP_WORDCLASS for c in classes):
            continue
        mapped = sorted({KEEP_WORDCLASS[c] for c in classes if c in KEEP_WORDCLASS})
        if not mapped:
            continue
        bm = RE_BEDEUTUNGEN.search(sub)
        if not bm:
            continue
        senses, topics, _ = _senses_from(bm.group(1))
        if not senses:
            continue
        # „Baum" hat auch einen Nachnamen-Abschnitt. Ist das Gattungswort dabei,
        # ist es kein Eigenname.
        if "noun" in mapped and "propernoun" in mapped:
            mapped = [c for c in mapped if c != "propernoun"]
        return {
            "lemma": title,
            "wordClasses": mapped,
            "senses": senses,
            "topics": sorted(set(t for t in topics if 2 <= len(t) <= 30))[:6],
            "source": "de.wiktionary",
        }
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", default="raw/wiktionary/dewiktionary-latest-pages-articles.xml.bz2")
    ap.add_argument("--out", default="raw/wiktionary/de-entries.jsonl")
    a = ap.parse_args()
    if not os.path.exists(a.dump):
        sys.exit(f"fehlt: {a.dump}")

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    pages = kept = 0
    NS = "{http://www.mediawiki.org/xml/export-0.11/}"
    with bz2.open(a.dump, "rb") as f, open(a.out, "w", encoding="utf-8") as out:
        title, ns, text = None, None, None
        for event, elem in ET.iterparse(f, events=("end",)):
            tag = elem.tag.split("}")[-1]
            if tag == "title":
                title = elem.text
            elif tag == "ns":
                ns = elem.text
            elif tag == "text":
                text = elem.text
            elif tag == "page":
                pages += 1
                if ns == "0" and title and text and ":" not in title:
                    rec = parse_page(title, text)
                    if rec:
                        out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                        kept += 1
                if pages % 200_000 == 0:
                    print(f"  … {pages} Seiten, {kept} Einträge", flush=True)
                title = ns = text = None
                elem.clear()

    meta = {
        "dump": os.path.basename(a.dump),
        "pagesScanned": pages,
        "entriesKept": kept,
        "license": "CC BY-SA 4.0",
        "attribution": "Deutsches Wiktionary, https://de.wiktionary.org/",
        "note": ("Nur der deutsche Abschnitt, nur der Block {{Bedeutungen}}. "
                 "Flektierte Formen verworfen (ihre Bedeutung verraet die Antwort)."),
    }
    with open(os.path.join(os.path.dirname(a.out), "wiktionary-meta.json"), "w",
              encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f"fertig: {pages} Seiten gescannt, {kept} Einträge -> {a.out}")


if __name__ == "__main__":
    main()
