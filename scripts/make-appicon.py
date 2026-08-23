#!/usr/bin/env python3
"""Erzeugt das App-Icon als PNG — ohne Bildbibliothek.

Weder Pillow noch cairosvg sind hier installiert, und eine Abhängigkeit für ein
Icon einzuführen wäre in einem Projekt mit null Abhängigkeiten verkehrt. Ein PNG
ist zlib plus ein Header; ein Kreuzworträtselgitter besteht aus Rechtecken.

Motiv: ein 5x5-Ausschnitt mit Sperrfeldern und den Buchstaben K und W. Bewusst
ohne Farbverlauf und ohne feine Linien, weil das Icon auch bei 16 px lesbar sein
muss (macOS zeigt es in der Größe im Finder).
"""
import struct, sys, zlib
from pathlib import Path

# Farben: dunkles Blaugrau als Grund, weiße Zellen, kräftiges Rot für die Pfeile.
GROUND = (0x1C, 0x2B, 0x3A)
CELL = (0xF7, 0xF7, 0xF4)
BLOCK = (0x2E, 0x44, 0x58)
INK = (0x1C, 0x2B, 0x3A)
ACCENT = (0xD8, 0x43, 0x2F)

GRID = 5
# Sperrfelder des Motivs (Zeile, Spalte).
BLOCKS = {(0, 4), (1, 2), (2, 0), (3, 3), (4, 1)}

# Buchstaben werden als **Striche** gezeichnet, nicht als Punktraster. Der erste
# Versuch nahm ein 5x7-Bitmap: das K war ein Treppenmuster und das W las sich als
# U. Bei 1024 px stehen solche Kanten neben den scharfen Zellen sichtbar billig da.
#
# Koordinaten sind Anteile der Zelle (0..1), damit dieselbe Beschreibung für jede
# Größe gilt. Jeder Eintrag ist ein Strich von (x0,y0) nach (x1,y1).
STROKES = {
    "K": [(0.20, 0.10, 0.20, 0.90),      # Stamm
          (0.20, 0.52, 0.74, 0.10),      # oberer Arm
          (0.20, 0.52, 0.74, 0.90)],     # unterer Arm
    "W": [(0.10, 0.12, 0.30, 0.90),
          (0.30, 0.90, 0.50, 0.38),
          (0.50, 0.38, 0.70, 0.90),
          (0.70, 0.90, 0.90, 0.12)],
}
LETTERS = {(0, 0): "K", (2, 2): "W"}


def draw_line(px, size, x0, y0, x1, y1, thick, color):
    """Dicke Linie, gerastert über die längere Achse.

    Kein Antialiasing: das Icon ist sonst überall hart, und ein einzelner
    weicher Strich fällt mehr auf als die Treppe, die er ersetzt.
    """
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    steps = int(steps * 2)
    r = thick / 2
    for i in range(steps + 1):
        t = i / steps
        cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for yy in range(int(cy - r), int(cy + r) + 1):
            if 0 <= yy < size:
                row = px[yy]
                for xx in range(int(cx - r), int(cx + r) + 1):
                    if 0 <= xx < size and (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                        row[xx] = color


def render(size: int) -> bytes:
    px = [[GROUND] * size for _ in range(size)]
    # Randabstand: bei kleinen Größen relativ mehr, sonst wirkt es gedrängt.
    margin = max(1, round(size * 0.09))
    inner = size - 2 * margin
    step = inner / GRID
    gap = max(1, round(size * 0.008))

    def fill(x0, y0, x1, y1, color):
        for y in range(max(0, y0), min(size, y1)):
            row = px[y]
            for x in range(max(0, x0), min(size, x1)):
                row[x] = color

    for r in range(GRID):
        for c in range(GRID):
            x0 = margin + round(c * step) + gap
            y0 = margin + round(r * step) + gap
            x1 = margin + round((c + 1) * step) - gap
            y1 = margin + round((r + 1) * step) - gap
            fill(x0, y0, x1, y1, BLOCK if (r, c) in BLOCKS else CELL)

            if letter := LETTERS.get((r, c)):
                cw, ch = x1 - x0, y1 - y0
                thick = max(1.6, min(cw, ch) * 0.13)
                for sx0, sy0, sx1, sy1 in STROKES[letter]:
                    draw_line(px, size,
                              x0 + sx0 * cw, y0 + sy0 * ch,
                              x0 + sx1 * cw, y0 + sy1 * ch, thick, INK)

    # Ein roter Pfeil als Zitat des Schwedenrätsels — nur groß genug sichtbar.
    if size >= 64:
        r, c = 3, 0
        x0 = margin + round(c * step) + gap
        y0 = margin + round(r * step) + gap
        h = round(step) - 2 * gap
        thick = max(2, round(size * 0.022))
        cy = y0 + h // 2
        fill(x0 + round(h * 0.22), cy - thick // 2,
             x0 + round(h * 0.78), cy - thick // 2 + thick, ACCENT)
        for i in range(round(h * 0.20)):
            fill(x0 + round(h * 0.78) - i, cy - i - thick // 2,
                 x0 + round(h * 0.78) - i + thick, cy + i + thick, ACCENT)

    raw = b"".join(b"\x00" + bytes(v for pxl in row for v in pxl) for row in px)
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


# iOS reicht ein 1024er (Xcode leitet ab); macOS braucht den ganzen Satz.
SIZES = [1024, 512, 256, 128, 64, 32, 16]

def main(out: Path):
    icon = out / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    images = []
    for size in SIZES:
        name = f"icon-{size}.png"
        (icon / name).write_bytes(render(size))
        print(f"  {name}")
    # Ein einziger 1024er für iOS, plus die macOS-Leiter.
    images.append({"filename": "icon-1024.png", "idiom": "universal",
                   "platform": "ios", "size": "1024x1024"})
    for pt, files in [(16, (16, 32)), (32, (32, 64)), (128, (128, 256)),
                      (256, (256, 512)), (512, (512, 1024))]:
        for scale, px in zip(("1x", "2x"), files):
            images.append({"filename": f"icon-{px}.png", "idiom": "mac",
                           "scale": scale, "size": f"{pt}x{pt}"})
    import json
    (icon / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (out / "Contents.json").write_text(json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print(f"geschrieben: {icon}")

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "Apps/Kreuzwort/Assets.xcassets"))
