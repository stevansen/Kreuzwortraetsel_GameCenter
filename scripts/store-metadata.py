#!/usr/bin/env python3
"""Schreibt die Store-Texte in App Store Connect.

Quelle der Texte ist store/metadata-*.md; hier stehen sie in der Form, die die
API erwartet. Zeichengrenzen: Beschreibung 4000, Schlüsselwörter 100,
Werbetext 170, Was-ist-neu 4000. Die Grenzen werden vor dem Senden geprüft,
weil die API sonst mit einer unspezifischen 409 antwortet.
"""
import json, subprocess, sys, os

APP_ID = "6804496902"
SUPPORT_URL = "https://github.com/stevansen/Kreuzwortraetsel_GameCenter/issues"

DE_DESC = """Kreuzwort erzeugt jedes Rätsel selbst. Kein Vorrat, der irgendwann leer ist: Gitter und Fragen entstehen im Moment des Spielens, aus einem Katalog mit über 128.000 Antworten und 164.000 Fragen aus dem deutschen Wiktionary.

ZWEI VARIANTEN
• Klassisch — numeriertes Gitter, Fragen in der Liste daneben
• Schwedenrätsel — Fragen stehen im Gitter, Pfeile zeigen die Laufrichtung

VIER STUFEN
Von Leicht mit alltäglichem Wortschatz bis Experte mit 15x15-Gittern und seltenen Wörtern.

TAGESRÄTSEL
Jeden Tag ein Rätsel, für alle gleich — ohne Konto und ohne Server.

GAME CENTER
Punkte je gelöstes Rätsel, Bestenlisten und 22 Erfolge. Der Fortschritt wandert über iPhone, iPad und Mac; ein angefangenes Rätsel setzen Sie auf dem nächsten Gerät fort, wo Sie aufgehört haben.

OHNE NETZ SPIELBAR
Der komplette Fragenkatalog steckt in der App. Kein Login, keine Werbung, keine Abos, kein Tracking."""

EN_DESC = """Kreuzwort builds every puzzle itself. No finite stock that eventually runs out: grid and clues are created the moment you play, from a catalogue of over 128,000 answers and 164,000 clues drawn from the German Wiktionary.

Please note: clues and answers are in German. The app interface is available in English.

TWO VARIANTS
• Classic — numbered grid with clues in a list beside it
• Arrow puzzle (Schwedenrätsel) — clues sit inside the grid, arrows show the direction

FOUR LEVELS
From Easy with everyday vocabulary to Expert with 15x15 grids and rare words.

DAILY PUZZLE
One puzzle a day, identical for everyone — no account, no server.

GAME CENTER
Points per solved puzzle, leaderboards and 22 achievements. Your progress follows you across iPhone, iPad and Mac; pick up an unfinished puzzle on the next device exactly where you left off.

PLAYABLE OFFLINE
The whole clue catalogue ships inside the app. No login, no ads, no subscriptions, no tracking."""

IT_DESC = """Kreuzwort genera ogni schema da sé. Nessuna scorta che prima o poi finisce: griglia e definizioni nascono nel momento in cui si gioca, da un catalogo di oltre 128.000 risposte e 164.000 definizioni dal Wiktionary tedesco.

Attenzione: le definizioni e le soluzioni sono in tedesco. L'interfaccia dell'app è disponibile in italiano.

DUE VARIANTI
• Classico — griglia numerata, definizioni nell'elenco accanto
• Schema svedese — le definizioni stanno nella griglia, le frecce indicano la direzione

QUATTRO LIVELLI
Da Facile con vocabolario quotidiano fino a Esperto con griglie 15x15 e parole rare.

SCHEMA DEL GIORNO
Ogni giorno uno schema, uguale per tutti — senza account e senza server.

GAME CENTER
Punti per ogni schema risolto, classifiche e 22 obiettivi. I progressi passano da iPhone a iPad al Mac; uno schema iniziato si riprende sul dispositivo successivo da dove si era interrotto.

SENZA RETE
L'intero catalogo è nell'app. Nessun login, nessuna pubblicità, nessun abbonamento, nessun tracciamento."""

LOCALES = {
    "de-DE": {
        "description": DE_DESC,
        "keywords": "kreuzworträtsel,schwedenrätsel,rätsel,wortspiel,denksport,gehirnjogging,tagesrätsel,offline",
        "promotionalText": "Jeden Tag ein neues Rätsel — weltweit dasselbe. Vier Schwierigkeitsstufen, klassisch und als Schwedenrätsel, komplett offline spielbar.",
        "whatsNew": "Erste Version.",
    },
    "en-US": {
        "description": EN_DESC,
        "keywords": "crossword,arrowword,swedish,puzzle,wordgame,brainteaser,daily,offline,german",
        "promotionalText": "A new puzzle every day, the same one worldwide. Four difficulty levels, classic and arrow-style, fully playable offline.",
        "whatsNew": "First release.",
    },
    "it": {
        "description": IT_DESC,
        "keywords": "cruciverba,schemasvedese,enigmi,giochidiparole,rebus,allenamentomentale,offline",
        "promotionalText": "Ogni giorno un nuovo schema, identico per tutti. Quattro livelli, cruciverba classico e schema svedese, giocabile completamente offline.",
        "whatsNew": "Prima versione.",
    },
}

# Bei der ersten Version im Store gibt es kein „Was ist neu".
IS_FIRST_RELEASE = True

LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170, "whatsNew": 4000}


def api(method, path, body=None):
    here = os.path.dirname(os.path.abspath(__file__))
    cmd = ["python3", os.path.join(here, "asc.py"), method, path]
    if body is not None:
        cmd.append(json.dumps(body))
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    status, _, payload = out.partition("\n")
    return int(status.strip()), json.loads(payload or "{}")


def check_limits():
    problems = []
    for locale, fields in LOCALES.items():
        for key, limit in LIMITS.items():
            n = len(fields.get(key, ""))
            if n > limit:
                problems.append(f"{locale}.{key}: {n} > {limit}")
    return problems


def main():
    if problems := check_limits():
        print("Zeichengrenzen verletzt:")
        for p in problems:
            print("  " + p)
        return 1

    platforms = sys.argv[1:] or ["IOS", "MAC_OS"]
    status, data = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions"
                              "?fields[appStoreVersions]=versionString,platform")
    versions = {x["attributes"]["platform"]: x["id"] for x in data.get("data", [])}

    for platform in platforms:
        version_id = versions.get(platform)
        if not version_id:
            print(f"{platform}: keine Version 1.0 gefunden")
            continue
        print(f"{platform} ({version_id})")
        def fetch_existing():
            # `fields` ausdrücklich anfragen: ohne das kam die Liste in einem
            # Lauf ohne `locale` zurück, das Skript hielt de-DE für neu und
            # bekam „Entity with locale: de-DE already exists".
            st, payload = api("GET", f"/v1/appStoreVersions/{version_id}"
                                     "/appStoreVersionLocalizations?limit=50"
                                     "&fields[appStoreVersionLocalizations]=locale")
            if st != 200:
                print(f"  Bestand nicht lesbar ({st}) — es wird nur angelegt")
                return {}
            return {x["attributes"]["locale"]: x["id"] for x in payload.get("data", [])}

        existing = fetch_existing()

        for locale, fields in LOCALES.items():
            attributes = dict(fields)
            attributes["supportUrl"] = SUPPORT_URL
            # „Was ist neu" gilt nur für Aktualisierungen. Bei der Erstversion
            # antwortet die API mit „Attribute 'whatsNew' cannot be edited at
            # this time" — und zwar für **alle** Sprachen, was den ganzen Lauf
            # scheitern liess. Der Text bleibt oben stehen, für die 1.1.
            if IS_FIRST_RELEASE:
                attributes.pop("whatsNew", None)
            if loc_id := existing.get(locale):
                st, resp = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}",
                               {"data": {"type": "appStoreVersionLocalizations",
                                         "id": loc_id, "attributes": attributes}})
                action = "aktualisiert"
            else:
                attributes["locale"] = locale
                st, resp = api("POST", "/v1/appStoreVersionLocalizations",
                               {"data": {"type": "appStoreVersionLocalizations",
                                         "attributes": attributes,
                                         "relationships": {"appStoreVersion": {
                                             "data": {"type": "appStoreVersions",
                                                      "id": version_id}}}}})
                action = "angelegt"
                # Apple legt für die Primärsprache eine leere Lokalisierung
                # selbst an. Wer sie nicht sieht, versucht sie anzulegen und
                # scheitert — dann hier auf Aktualisieren umschwenken.
                if st == 409:
                    existing = fetch_existing()
                    if loc_id := existing.get(locale):
                        del attributes["locale"]
                        st, resp = api("PATCH",
                                       f"/v1/appStoreVersionLocalizations/{loc_id}",
                                       {"data": {"type": "appStoreVersionLocalizations",
                                                 "id": loc_id,
                                                 "attributes": attributes}})
                        action = "aktualisiert (war schon da)"
            ok = st in (200, 201)
            print(f"  {locale}: {action if ok else json.dumps(resp)[:200]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
