#!/usr/bin/env python3
"""Lädt Screenshots nach App Store Connect.

Screenshots hängen nicht an der Version, sondern an der **Sprachfassung** — die
gleichen Bilder gehen also einmal je Sprache hoch. Der Upload läuft in drei
Schritten, weil die API keine Datei direkt annimmt: Reservierung anlegen, Bytes
an die genannte Adresse schicken, Reservierung als abgeschlossen melden.

Die Anzeigetypen sind ein festes Vokabular der API; sie nennt es in der
Fehlermeldung, wenn man einen falschen Wert schickt.

    python3 scripts/store-screenshots.py            # zeigt, was hochginge
    python3 scripts/store-screenshots.py --laden     # lädt hoch
"""
import json, os, subprocess, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
APP = "6804496902"

# (Anzeigetyp, Verzeichnis) — Reihenfolge im Store ist die Sortierung der Namen.
SOURCES = [
    ("APP_IPHONE_67", ROOT / "store/screenshots/iphone-69"),
    ("APP_IPAD_PRO_3GEN_129", ROOT / "store/screenshots/ipad-13"),
    ("APP_APPLE_TV", ROOT / "store/screenshots/tv"),
    ("APP_DESKTOP", ROOT / "store/screenshots/mac"),
]
PLATFORM_FOR_TYPE = {
    "APP_IPHONE_67": "IOS", "APP_IPAD_PRO_3GEN_129": "IOS",
    "APP_APPLE_TV": "TV_OS", "APP_DESKTOP": "MAC_OS",
}


def api(method, path, body=None):
    cmd = ["python3", str(HERE / "asc.py"), method, path]
    if body is not None:
        cmd.append(json.dumps(body))
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    st, _, payload = out.partition("\n")
    return int(st.strip()), json.loads(payload or "{}")


def upload(operations, data):
    for op in operations:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req) as r:
            if r.status not in (200, 201):
                return False
    return True


def main():
    laden = "--laden" in sys.argv
    st, data = api("GET", f"/v1/apps/{APP}/appStoreVersions"
                          "?fields[appStoreVersions]=platform")
    versions = {x["attributes"]["platform"]: x["id"] for x in data.get("data", [])}

    for display, directory in SOURCES:
        files = sorted(directory.glob("*.png")) if directory.exists() else []
        platform = PLATFORM_FOR_TYPE[display]
        version = versions.get(platform)
        if not files:
            print(f"{display}: keine Bilder in {directory.relative_to(ROOT)} — übersprungen")
            continue
        if not version:
            print(f"{display}: keine {platform}-Version — übersprungen")
            continue

        st, data = api("GET", f"/v1/appStoreVersions/{version}"
                              "/appStoreVersionLocalizations?limit=10"
                              "&fields[appStoreVersionLocalizations]=locale")
        locales = {x["attributes"]["locale"]: x["id"] for x in data.get("data", [])}
        print(f"{display}: {len(files)} Bilder × {len(locales)} Sprachen")
        if not laden:
            continue

        for locale, loc_id in sorted(locales.items()):
            st, data = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}"
                                  "/appScreenshotSets?limit=20"
                                  "&fields[appScreenshotSets]=screenshotDisplayType")
            existing = {x["attributes"]["screenshotDisplayType"]: x["id"]
                        for x in data.get("data", [])}
            set_id = existing.get(display)
            if not set_id:
                st, resp = api("POST", "/v1/appScreenshotSets",
                               {"data": {"type": "appScreenshotSets",
                                         "attributes": {"screenshotDisplayType": display},
                                         "relationships": {
                                             "appStoreVersionLocalization": {
                                                 "data": {"type":
                                                          "appStoreVersionLocalizations",
                                                          "id": loc_id}}}}})
                if st not in (200, 201):
                    print(f"  {locale}: Satz {json.dumps(resp)[:150]}")
                    continue
                set_id = resp["data"]["id"]

            st, data = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots"
                                  "?limit=20&fields[appScreenshots]=fileName")
            have = {x["attributes"].get("fileName") for x in data.get("data", [])}
            done = []
            for path in files:
                if path.name in have:
                    done.append(f"{path.name} (war da)")
                    continue
                blob = path.read_bytes()
                st, resp = api("POST", "/v1/appScreenshots",
                               {"data": {"type": "appScreenshots",
                                         "attributes": {"fileSize": len(blob),
                                                        "fileName": path.name},
                                         "relationships": {"appScreenshotSet": {
                                             "data": {"type": "appScreenshotSets",
                                                      "id": set_id}}}}})
                if st not in (200, 201):
                    print(f"  {locale}/{path.name}: {json.dumps(resp)[:160]}")
                    continue
                shot = resp["data"]["id"]
                ops = resp["data"]["attributes"].get("uploadOperations") or []
                if not upload(ops, blob):
                    print(f"  {locale}/{path.name}: Upload fehlgeschlagen")
                    continue
                st, resp = api("PATCH", f"/v1/appScreenshots/{shot}",
                               {"data": {"type": "appScreenshots", "id": shot,
                                         "attributes": {"uploaded": True}}})
                done.append(path.name if st in (200, 201)
                            else f"{path.name} (Abschluss {st})")
            print(f"  {locale}: {', '.join(done)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
