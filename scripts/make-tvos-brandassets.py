#!/usr/bin/env python3
"""Erzeugt die tvOS-Markenbilder („Brand Assets").

Ohne diese Bilder ist eine tvOS-App **nicht einreichbar** — der Build hatte gar
kein Icon. tvOS verlangt kein einzelnes PNG, sondern:

  * ein **geschichtetes** App-Icon (1280x768 für den Store, 400x240 für den
    Startbildschirm). Die Ebenen bewegen sich beim Fokussieren gegeneinander,
    das ist der Parallax-Effekt der Fernsehoberfläche.
  * ein **Top-Shelf-Bild** in zwei Formaten (1920x720 und breit 2320x720), das
    erscheint, wenn die App in der obersten Reihe steht.

Aufteilung der Ebenen: hinten der Grund, in der Mitte das Gitter, vorne die
Buchstaben und der Pfeil. So laufen beim Fokussieren Buchstaben über dem Gitter —
und nicht das ganze Bild als starre Fläche.

    python3 scripts/make-tvos-brandassets.py [Zielverzeichnis]
"""
import json, sys, os
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngdraw import (Canvas, STROKES, TRANSPARENT, GROUND, CELL, BLOCK,
                     INK, ACCENT)

GRID = 5
BLOCKS = {(0, 4), (1, 2), (2, 0), (3, 3), (4, 1)}
LETTERS = {(0, 0): "K", (2, 2): "W"}
ARROW_CELL = (3, 0)


def scene(width, height, layer):
    """Zeichnet eine Ebene.

    `layer` ist "back" (Grund), "middle" (Gitter), "front" (Buchstaben und
    Pfeil) oder "flat" (alles in einem, für das Top-Shelf-Bild).

    Die oberen Ebenen sind **durchsichtig**, sonst verdeckt die vorderste alle
    darunter — daran war der erste Anlauf gescheitert. Und weil `INK` und
    `GROUND` dieselbe Farbe sind, waren die Buchstaben zusätzlich unsichtbar.
    """
    transparent = layer in ("middle", "front")
    c = Canvas(width, TRANSPARENT if transparent else GROUND,
               alpha=True, height=height)
    side = min(width, height) * 0.86 / GRID
    ox = (width - side * GRID) / 2
    oy = (height - side * GRID) / 2
    gap = max(1, side * 0.03)

    if layer == "back":
        return c

    for r in range(GRID):
        for col in range(GRID):
            x0, y0 = ox + col * side + gap, oy + r * side + gap
            x1, y1 = ox + (col + 1) * side - gap, oy + (r + 1) * side - gap
            if layer in ("middle", "flat"):
                c.rect(x0, y0, x1, y1, BLOCK if (r, col) in BLOCKS else CELL)
            if layer in ("front", "flat"):
                if letter := LETTERS.get((r, col)):
                    cw, ch = x1 - x0, y1 - y0
                    thick = max(2.0, min(cw, ch) * 0.13)
                    for sx0, sy0, sx1, sy1 in STROKES[letter]:
                        c.line(x0 + sx0 * cw, y0 + sy0 * ch,
                               x0 + sx1 * cw, y0 + sy1 * ch, thick, INK)
                if (r, col) == ARROW_CELL:
                    h = y1 - y0
                    cy = (y0 + y1) / 2
                    thick = max(3.0, h * 0.14)
                    c.line(x0 + h * 0.22, cy, x0 + h * 0.72, cy, thick, ACCENT)
                    c.triangle_right(x0 + h * 0.72, cy, h * 0.42, ACCENT)
    return c


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def imageset(directory: Path, files):
    """`files` sind (Dateiname, scale)-Paare."""
    directory.mkdir(parents=True, exist_ok=True)
    write_json(directory / "Contents.json", {
        "images": [{"filename": name, "idiom": "tv", "scale": scale}
                   for name, scale in files],
        "info": {"author": "xcode", "version": 1}})


def imagestack(directory: Path, width, height, scales):
    """Geschichtetes Icon: drei Ebenen, jede ein eigenes Bildset."""
    directory.mkdir(parents=True, exist_ok=True)
    # **Reihenfolge von vorne nach hinten.** actool liest den letzten Eintrag
    # als unterste Ebene und verlangt, dass sie deckend ist. Mit
    # ["Back", "Middle", "Front"] galt „Front" als unterste und der Build brach
    # ab: „The last image stack layer with content, ‚Front', must be a fully
    # opaque bitmap."
    layers = ["Front", "Middle", "Back"]
    write_json(directory / "Contents.json", {
        "layers": [{"filename": f"{name}.imagestacklayer"} for name in layers],
        "info": {"author": "xcode", "version": 1}})
    for name in layers:
        layer = directory / f"{name}.imagestacklayer"
        layer.mkdir(parents=True, exist_ok=True)
        write_json(layer / "Contents.json", {"info": {"author": "xcode", "version": 1}})
        content = layer / "Content.imageset"
        files = []
        for scale, factor in scales:
            w, h = width * factor, height * factor
            filename = f"{name.lower()}-{w}x{h}.png"
            (content / filename).parent.mkdir(parents=True, exist_ok=True)
            (content / filename).write_bytes(scene(w, h, name.lower()).png())
            files.append((filename, scale))
        imageset(content, files)


def main():
    # Der Name muss zu ASSETCATALOG_COMPILER_APPICON_NAME passen. Mit
    # „Brand Assets" warnte actool: „None of the input catalogs contained a
    # matching App Icon & Top Shelf Image brand assets collection named
    # ‚AppIcon'" — und das tvOS-Bundle blieb ohne Icon.
    out = Path(sys.argv[1] if len(sys.argv) > 1
               else "Apps/Kreuzwort/Assets.xcassets") / "AppIcon.brandassets"
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / "Contents.json", {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
             "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv",
             "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": {"author": "xcode", "version": 1}})

    # Store-Icon nur @1x, Startbildschirm-Icon @1x und @2x.
    imagestack(out / "App Icon - App Store.imagestack", 1280, 768, [("1x", 1)])
    imagestack(out / "App Icon.imagestack", 400, 240, [("1x", 1), ("2x", 2)])

    for name, w, h in [("Top Shelf Image", 1920, 720),
                       ("Top Shelf Image Wide", 2320, 720)]:
        directory = out / f"{name}.imageset"
        directory.mkdir(parents=True, exist_ok=True)
        files = []
        for scale, factor in [("1x", 1), ("2x", 2)]:
            filename = f"{name.lower().replace(' ', '-')}-{w*factor}x{h*factor}.png"
            # Das Top-Shelf-Bild ist flach und braucht keine Ebenen: alles in
            # einem Durchgang, durchsichtige Stellen auf den Grund gesetzt.
            flat = scene(w * factor, h * factor, "flat")
            for row in flat.px:
                for x in range(len(row)):
                    if row[x][3] == 0:
                        row[x] = (*GROUND, 255)
            (directory / filename).write_bytes(flat.png())
            files.append((filename, scale))
        imageset(directory, files)

    print(f"geschrieben: {out}")


if __name__ == "__main__":
    main()
