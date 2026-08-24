#!/usr/bin/env python3
"""Vervollständigt Game Center: Erfolgstexte in drei Sprachen und die Bilder.

Apple verlangt je Erfolgs-Lokalisierung ein Bild; ohne bleibt der Erfolg
unveröffentlicht. Der Upload läuft in drei Schritten, weil die API keine
Datei direkt annimmt: Reservierung anlegen, Bytes an die genannte Adresse
schicken, Reservierung als abgeschlossen melden.

    python3 scripts/gamecenter-images.py            # zeigt den Stand
    python3 scripts/gamecenter-images.py --anlegen  # legt an und lädt hoch
"""
import json, os, subprocess, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMAGES = HERE.parent / "store" / "achievements"
APP_ID = "6804496902"

# (id, Name de, Beschreibung de, Name en, Beschreibung en, Name it, Beschreibung it)
TEXTS = [
    ("first_solve", "Erstes Rätsel", "Ein Rätsel gelöst.",
     "First puzzle", "Solve one puzzle.", "Primo schema", "Risolvi uno schema."),
    ("solve_10", "Zehn geschafft", "Zehn Rätsel gelöst.",
     "Ten down", "Solve ten puzzles.", "Dieci fatti", "Risolvi dieci schemi."),
    ("solve_100", "Hundert geschafft", "Hundert Rätsel gelöst.",
     "Hundred down", "Solve a hundred puzzles.",
     "Cento fatti", "Risolvi cento schemi."),
    ("solve_1000", "Tausend geschafft", "Tausend Rätsel gelöst.",
     "Thousand down", "Solve a thousand puzzles.",
     "Mille fatti", "Risolvi mille schemi."),
    ("arrow_first", "Erstes Schwedenrätsel", "Ein Schwedenrätsel gelöst.",
     "First arrow puzzle", "Solve one arrow puzzle.",
     "Primo schema svedese", "Risolvi uno schema svedese."),
    ("arrow_100", "Pfeilmeister", "Hundert Schwedenrätsel gelöst.",
     "Arrow master", "Solve a hundred arrow puzzles.",
     "Maestro delle frecce", "Risolvi cento schemi svedesi."),
    ("classic_100", "Gittermeister", "Hundert klassische Rätsel gelöst.",
     "Grid master", "Solve a hundred classic puzzles.",
     "Maestro della griglia", "Risolvi cento cruciverba classici."),
    ("ambidextrous", "Beidhändig", "Beide Varianten am selben Tag gelöst.",
     "Ambidextrous", "Solve both variants on the same day.",
     "Ambidestro", "Risolvi entrambe le varianti nello stesso giorno."),
    ("all_difficulties", "Alle Stufen", "Jede Schwierigkeitsstufe gelöst.",
     "Every level", "Solve a puzzle on every difficulty.",
     "Tutti i livelli", "Risolvi uno schema per ogni livello."),
    ("bent_arrows", "Knickpfeile", "Ein Rätsel mit Knickpfeilen gelöst.",
     "Bent arrows", "Solve a puzzle containing bent arrows.",
     "Frecce piegate", "Risolvi uno schema con frecce piegate."),
    ("expert_clean", "Experte ohne Hilfe", "Experte ohne Hinweis gelöst.",
     "Expert unaided", "Solve an expert puzzle without hints.",
     "Esperto senza aiuti", "Risolvi uno schema esperto senza suggerimenti."),
    ("speedrun_mittel", "Schnell auf Mittel", "Mittel unter der Zielzeit gelöst.",
     "Quick on medium", "Solve a medium puzzle under par time.",
     "Veloce su medio", "Risolvi uno schema medio sotto il tempo previsto."),
    ("streak_7", "Eine Woche", "Sieben Tage in Folge gespielt.",
     "One week", "Play seven days in a row.",
     "Una settimana", "Gioca sette giorni di fila."),
    ("streak_30", "Ein Monat", "Dreißig Tage in Folge gespielt.",
     "One month", "Play thirty days in a row.",
     "Un mese", "Gioca trenta giorni di fila."),
    ("streak_365", "Ein Jahr", "Ein Jahr in Folge gespielt.",
     "One year", "Play a full year in a row.",
     "Un anno", "Gioca un anno intero di fila."),
    ("flawless_25", "Fehlerfrei", "25 Rätsel ohne Fehleingabe gelöst.",
     "Flawless", "Solve 25 puzzles without a wrong letter.",
     "Senza errori", "Risolvi 25 schemi senza errori."),
    ("vocab_5000", "Wortschatz", "5.000 verschiedene Antworten gefunden.",
     "Vocabulary", "Find 5,000 different answers.",
     "Vocabolario", "Trova 5.000 risposte diverse."),
    ("night_owl", "Nachteule", "Ein Rätsel nach Mitternacht gelöst.",
     "Night owl", "Solve a puzzle after midnight.",
     "Nottambulo", "Risolvi uno schema dopo mezzanotte."),
    ("early_bird", "Frühaufsteher", "Ein Rätsel vor sechs Uhr gelöst.",
     "Early bird", "Solve a puzzle before six in the morning.",
     "Mattiniero", "Risolvi uno schema prima delle sei."),
    ("comeback", "Rückkehr", "Nach einer Pause wieder gespielt.",
     "Comeback", "Come back after a break.",
     "Ritorno", "Torna a giocare dopo una pausa."),
    ("points_100k", "Hunderttausend", "100.000 Punkte erreicht.",
     "Hundred thousand", "Reach 100,000 points.",
     "Centomila", "Raggiungi 100.000 punti."),
    ("on_the_big_screen", "Großer Schirm", "Ein Rätsel auf dem Mac gelöst.",
     "On the big screen", "Solve a puzzle on the Mac.",
     "Sul grande schermo", "Risolvi uno schema sul Mac."),
]

LOCALES = ["de-DE", "en-US", "it"]


def api(method, path, body=None):
    cmd = ["python3", str(HERE / "asc.py"), method, path]
    if body is not None:
        cmd.append(json.dumps(body))
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    status, _, payload = out.partition("\n")
    return int(status.strip()), json.loads(payload or "{}")


def upload(operations, data):
    """Bytes an die von Apple genannten Adressen schicken."""
    for op in operations:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"])
        for header in op.get("requestHeaders", []):
            req.add_header(header["name"], header["value"])
        with urllib.request.urlopen(req) as response:
            if response.status not in (200, 201):
                return False
    return True


def main():
    anlegen = "--anlegen" in sys.argv
    status, data = api("GET", f"/v1/apps/{APP_ID}/gameCenterDetail")
    detail_id = (data.get("data") or {}).get("id")
    if not detail_id:
        print("Keine Game-Center-Konfiguration — erst scripts/gamecenter-setup.py")
        return 1

    status, data = api("GET", f"/v1/gameCenterDetails/{detail_id}"
                              "/gameCenterAchievements?limit=50"
                              "&fields[gameCenterAchievements]=vendorIdentifier")
    achievements = {x["attributes"]["vendorIdentifier"]: x["id"]
                    for x in data.get("data", [])}
    print(f"{len(achievements)} Erfolge im Account")

    texts = {t[0]: t for t in TEXTS}
    missing_images = [k for k in achievements if not (IMAGES / f"{k}.png").exists()]
    if missing_images:
        print("Bilder fehlen:", ", ".join(missing_images))
        print("→ python3 scripts/make-achievement-images.py")
        return 1

    if not anlegen:
        print(f"Würde je Erfolg {len(LOCALES)} Sprachen und ein Bild setzen "
              f"({len(achievements) * len(LOCALES)} Lokalisierungen).")
        return 0

    for vid, ach_id in sorted(achievements.items()):
        entry = texts.get(vid)
        if not entry:
            print(f"  {vid}: kein Text hinterlegt — übersprungen")
            continue
        _, de_n, de_d, en_n, en_d, it_n, it_d = entry
        by_locale = {"de-DE": (de_n, de_d), "en-US": (en_n, en_d),
                     "it": (it_n, it_d)}

        st, data = api("GET", f"/v1/gameCenterAchievements/{ach_id}"
                              "/localizations?limit=20"
                              "&fields[gameCenterAchievementLocalizations]=locale")
        existing = {x["attributes"]["locale"]: x["id"] for x in data.get("data", [])}

        image_bytes = (IMAGES / f"{vid}.png").read_bytes()
        done = []
        for locale in LOCALES:
            name, description = by_locale[locale]
            attributes = {"name": name,
                          "beforeEarnedDescription": description,
                          "afterEarnedDescription": description}
            if loc_id := existing.get(locale):
                api("PATCH", f"/v1/gameCenterAchievementLocalizations/{loc_id}",
                    {"data": {"type": "gameCenterAchievementLocalizations",
                              "id": loc_id, "attributes": attributes}})
            else:
                attributes["locale"] = locale
                st, resp = api("POST", "/v1/gameCenterAchievementLocalizations",
                               {"data": {"type": "gameCenterAchievementLocalizations",
                                         "attributes": attributes,
                                         "relationships": {"gameCenterAchievement": {
                                             "data": {"type": "gameCenterAchievements",
                                                      "id": ach_id}}}}})
                if st not in (200, 201):
                    print(f"  {vid}/{locale}: {json.dumps(resp)[:140]}")
                    continue
                loc_id = resp["data"]["id"]

            # Bild: nur hochladen, wenn noch keines hängt.
            st, img = api("GET", f"/v1/gameCenterAchievementLocalizations/{loc_id}"
                                 "/gameCenterAchievementImage")
            if (img.get("data") or {}).get("id"):
                done.append(f"{locale} (Bild war da)")
                continue
            st, resp = api("POST", "/v1/gameCenterAchievementImages",
                           {"data": {"type": "gameCenterAchievementImages",
                                     "attributes": {"fileSize": len(image_bytes),
                                                    "fileName": f"{vid}.png"},
                                     "relationships": {
                                         "gameCenterAchievementLocalization": {
                                             "data": {"type":
                                                      "gameCenterAchievementLocalizations",
                                                      "id": loc_id}}}}})
            if st not in (200, 201):
                print(f"  {vid}/{locale}: Reservierung {json.dumps(resp)[:140]}")
                continue
            image_id = resp["data"]["id"]
            ops = resp["data"]["attributes"].get("uploadOperations") or []
            if not upload(ops, image_bytes):
                print(f"  {vid}/{locale}: Upload fehlgeschlagen")
                continue
            st, resp = api("PATCH", f"/v1/gameCenterAchievementImages/{image_id}",
                           {"data": {"type": "gameCenterAchievementImages",
                                     "id": image_id,
                                     "attributes": {"uploaded": True}}})
            done.append(locale if st in (200, 201)
                        else f"{locale} (Abschluss {st})")
        print(f"  {vid}: {', '.join(done)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
