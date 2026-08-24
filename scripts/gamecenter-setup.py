#!/usr/bin/env python3
"""Legt Game-Center-Bestenlisten und Erfolge in App Store Connect an.

Voraussetzung: der App-Eintrag muss existieren — Apps selbst kann die API nicht
anlegen ("The resource 'apps' does not allow 'CREATE'"), Game-Center-Konfiguration
dagegen schon.

Die IDs stammen aus dem Quelltext und müssen genau übereinstimmen, sonst
schlucken die Aufrufe in der App still fehl:
  Bestenlisten  GameServices/Sources/GameCenterService.swift
  Erfolge       PuzzleKit/Sources/Progress/Achievement.swift

Aufruf:
    python3 scripts/gamecenter-setup.py            # zeigt nur, was fehlt
    python3 scripts/gamecenter-setup.py --anlegen  # legt es an
"""
import json, subprocess, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BUNDLE_ID = "com.kreuzwort.app"

# (vendorIdentifier, Name de, Name en, Name it, Sortierung, Formatierung)
LEADERBOARDS = [
    ("total_points", "Punkte insgesamt", "Total points", "Punti totali",
     "DESC", "INTEGER"),
    ("daily_points", "Punkte heute", "Points today", "Punti di oggi",
     "DESC", "INTEGER"),
    ("weekly_points", "Punkte diese Woche", "Points this week", "Punti settimanali",
     "DESC", "INTEGER"),
    # Namen höchstens 30 Zeichen. „Schnellstes Experte Schwedenrätsel" waren 34
    # und wurden abgelehnt — in einer Bash-Schleife mit Ausgabe nach /dev/null
    # fiel das nicht auf, und die Bestenliste stand danach nur auf Englisch da.
    # Die Doppelpunkt-Form ist kurz und in allen drei Sprachen symmetrisch.
    ("fastest_expert_classic", "Experte: klassisch",
     "Expert: classic", "Esperto: classico",
     "ASC", "ELAPSED_TIME_CENTISECOND"),
    ("fastest_expert_arrow", "Experte: Schwedenrätsel",
     "Expert: arrow puzzle", "Esperto: schema svedese",
     "ASC", "ELAPSED_TIME_CENTISECOND"),
]

# (vendorIdentifier, Punkte, Name de, Beschreibung de)
ACHIEVEMENTS = [
    ("first_solve", 5, "Erstes Rätsel", "Ein Rätsel gelöst."),
    ("solve_10", 10, "Zehn geschafft", "Zehn Rätsel gelöst."),
    ("solve_100", 25, "Hundert geschafft", "Hundert Rätsel gelöst."),
    ("solve_1000", 100, "Tausend geschafft", "Tausend Rätsel gelöst."),
    ("arrow_first", 5, "Erstes Schwedenrätsel", "Ein Schwedenrätsel gelöst."),
    ("arrow_100", 25, "Pfeilmeister", "Hundert Schwedenrätsel gelöst."),
    ("classic_100", 25, "Gittermeister", "Hundert klassische Rätsel gelöst."),
    ("ambidextrous", 15, "Beidhändig", "Beide Varianten am selben Tag gelöst."),
    ("all_difficulties", 15, "Alle Stufen", "Jede Schwierigkeitsstufe gelöst."),
    ("bent_arrows", 10, "Knickpfeile", "Ein Rätsel mit Knickpfeilen gelöst."),
    ("expert_clean", 30, "Experte ohne Hilfe", "Experte ohne Hinweis gelöst."),
    ("speedrun_mittel", 20, "Schnell auf Mittel", "Mittel unter der Zielzeit gelöst."),
    ("streak_7", 10, "Eine Woche", "Sieben Tage in Folge gespielt."),
    ("streak_30", 30, "Ein Monat", "Dreißig Tage in Folge gespielt."),
    ("streak_365", 100, "Ein Jahr", "Ein Jahr in Folge gespielt."),
    ("flawless_25", 25, "Fehlerfrei", "25 Rätsel ohne Fehleingabe gelöst."),
    ("vocab_5000", 25, "Wortschatz", "5.000 verschiedene Antworten gefunden."),
    ("night_owl", 5, "Nachteule", "Ein Rätsel nach Mitternacht gelöst."),
    ("early_bird", 5, "Frühaufsteher", "Ein Rätsel vor sechs Uhr gelöst."),
    ("comeback", 10, "Rückkehr", "Nach einer Pause wieder gespielt."),
    ("points_100k", 50, "Hunderttausend", "100.000 Punkte erreicht."),
    ("on_the_big_screen", 10, "Großer Schirm", "Ein Rätsel auf dem Mac gelöst."),
]


def api(method, path, body=None):
    """Ruft asc.py auf, damit die Token-Logik an einer Stelle bleibt."""
    here = os.path.dirname(os.path.abspath(__file__))
    cmd = ["python3", os.path.join(here, "asc.py"), method, path]
    if body is not None:
        cmd.append(json.dumps(body))
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    status, _, payload = out.partition("\n")
    return int(status.strip()), json.loads(payload or "{}")


def find_app():
    status, data = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if status != 200 or not data.get("data"):
        return None
    return data["data"][0]["id"]


NAME_LIMIT = 30


def check_names():
    """Namen vor dem Senden prüfen. Die API antwortet sonst mit einer 409, und
    wer die Antwort nicht liest, merkt es nie."""
    problems = []
    for vid, de, en, it, _, _ in LEADERBOARDS:
        for locale, name in (("de", de), ("en", en), ("it", it)):
            if len(name) > NAME_LIMIT:
                problems.append(f"{vid}/{locale}: {len(name)} > {NAME_LIMIT}")
    for vid, _, name, _ in ACHIEVEMENTS:
        if len(name) > NAME_LIMIT:
            problems.append(f"{vid}: {len(name)} > {NAME_LIMIT}")
    return problems


def main():
    anlegen = "--anlegen" in sys.argv
    if problems := check_names():
        print("Namen zu lang:")
        for p in problems:
            print("  " + p)
        return 1
    app_id = find_app()
    if not app_id:
        print(f"Kein App-Eintrag für {BUNDLE_ID}.")
        print("Der muss zuerst in App Store Connect angelegt werden — die API")
        print("erlaubt das Anlegen von Apps nicht. Danach diesen Aufruf erneut.")
        return 1
    print(f"App gefunden: {app_id}")

    status, data = api("GET", f"/v1/apps/{app_id}/gameCenterDetail")
    detail_id = (data.get("data") or {}).get("id")
    if not detail_id:
        if not anlegen:
            print("Game-Center-Konfiguration fehlt (mit --anlegen erstellen).")
            return 0
        status, data = api("POST", "/v1/gameCenterDetails", {
            "data": {"type": "gameCenterDetails",
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if status not in (200, 201):
            print("Anlegen fehlgeschlagen:", json.dumps(data)[:300])
            return 1
        detail_id = data["data"]["id"]
    print(f"Game-Center-Detail: {detail_id}")

    if not anlegen:
        print(f"\nWürde anlegen: {len(LEADERBOARDS)} Bestenlisten, "
              f"{len(ACHIEVEMENTS)} Erfolge.")
        print("Hinweis: Erfolge brauchen für die Veröffentlichung je ein Bild "
              "(512x512). Ohne Bild bleibt der Erfolg unvollständig.")
        return 0

    for vid, de, en, it, sort, fmt in LEADERBOARDS:
        status, data = api("POST", "/v1/gameCenterLeaderboards", {
            "data": {"type": "gameCenterLeaderboards", "attributes": {
                "referenceName": vid, "vendorIdentifier": vid,
                "defaultFormatter": fmt, "submissionType": "BEST_SCORE",
                "scoreSortType": sort},
                "relationships": {"gameCenterDetail": {
                    "data": {"type": "gameCenterDetails", "id": detail_id}}}}})
        ok = status in (200, 201)
        print(f"  Bestenliste {vid}: {'angelegt' if ok else json.dumps(data)[:160]}")
        if not ok:
            continue
        board_id = data["data"]["id"]
        for locale, name in (("de-DE", de), ("en-US", en), ("it", it)):
            api("POST", "/v1/gameCenterLeaderboardLocalizations", {
                "data": {"type": "gameCenterLeaderboardLocalizations",
                         "attributes": {"locale": locale, "name": name},
                         "relationships": {"gameCenterLeaderboard": {
                             "data": {"type": "gameCenterLeaderboards", "id": board_id}}}}})

    for vid, points, name, description in ACHIEVEMENTS:
        status, data = api("POST", "/v1/gameCenterAchievements", {
            "data": {"type": "gameCenterAchievements", "attributes": {
                "referenceName": vid, "vendorIdentifier": vid,
                "points": points, "showBeforeEarned": True, "repeatable": False},
                "relationships": {"gameCenterDetail": {
                    "data": {"type": "gameCenterDetails", "id": detail_id}}}}})
        ok = status in (200, 201)
        print(f"  Erfolg {vid}: {'angelegt' if ok else json.dumps(data)[:160]}")
        if not ok:
            continue
        ach_id = data["data"]["id"]
        api("POST", "/v1/gameCenterAchievementLocalizations", {
            "data": {"type": "gameCenterAchievementLocalizations",
                     "attributes": {"locale": "de-DE", "name": name,
                                    "beforeEarnedDescription": description,
                                    "afterEarnedDescription": description},
                     "relationships": {"gameCenterAchievement": {
                         "data": {"type": "gameCenterAchievements", "id": ach_id}}}}})
    return 0


if __name__ == "__main__":
    sys.exit(main())
