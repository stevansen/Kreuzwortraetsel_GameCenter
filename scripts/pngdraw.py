#!/usr/bin/env python3
"""Minimale Zeichenfläche mit PNG-Ausgabe — ohne Bildbibliothek.

Weder Pillow noch cairo sind auf der Maschine installiert, und eine Abhängigkeit
für Icons einzuführen wäre in einem Projekt mit null Abhängigkeiten verkehrt.
Ein PNG ist zlib plus Header; alles hier Gezeichnete besteht aus Rechtecken,
Kreisen und dicken Linien.

Kein Antialiasing. Das ist Absicht: die Motive sind flächig, und ein einzelner
weicher Rand fällt neben harten Kanten mehr auf als die Treppe, die er ersetzt.
"""
import struct, zlib

# Farbwelt, gemeinsam mit dem App-Icon.
GROUND = (0x1C, 0x2B, 0x3A)
CELL = (0xF7, 0xF7, 0xF4)
BLOCK = (0x2E, 0x44, 0x58)
INK = (0x1C, 0x2B, 0x3A)
ACCENT = (0xD8, 0x43, 0x2F)
GOLD = (0xE0, 0xA8, 0x30)


# Vollständig durchsichtig. Nur mit `alpha=True` sinnvoll.
TRANSPARENT = (0, 0, 0, 0)


def _rgba(color):
    return color if len(color) == 4 else (*color, 255)


class Canvas:
    """Zeichenfläche, wahlweise mit Alphakanal.

    Alpha ist keine Spielerei: tvOS setzt sein App-Icon aus **Ebenen**
    zusammen, und ohne Transparenz verdeckt die vorderste Ebene alle darunter —
    das geschichtete Icon zeigte dann nur die oberste Schicht.
    """

    def __init__(self, size, background=GROUND, alpha=False, height=None):
        self.size = size
        self.height = height or size
        self.alpha = alpha
        fill = _rgba(background) if alpha else background
        self.px = [[fill] * size for _ in range(self.height)]

    # --- Grundformen ---

    def rect(self, x0, y0, x1, y1, color):
        color = _rgba(color) if self.alpha else color
        for y in range(max(0, int(y0)), min(self.height, int(y1))):
            row = self.px[y]
            for x in range(max(0, int(x0)), min(self.size, int(x1))):
                row[x] = color

    def disc(self, cx, cy, r, color):
        color = _rgba(color) if self.alpha else color
        rr = r * r
        for y in range(max(0, int(cy - r)), min(self.height, int(cy + r) + 1)):
            row = self.px[y]
            dy2 = (y - cy) ** 2
            for x in range(max(0, int(cx - r)), min(self.size, int(cx + r) + 1)):
                if (x - cx) ** 2 + dy2 <= rr:
                    row[x] = color

    def ring(self, cx, cy, r, thick, color):
        color = _rgba(color) if self.alpha else color
        outer, inner = r * r, (r - thick) ** 2
        for y in range(max(0, int(cy - r)), min(self.height, int(cy + r) + 1)):
            row = self.px[y]
            dy2 = (y - cy) ** 2
            for x in range(max(0, int(cx - r)), min(self.size, int(cx + r) + 1)):
                d = (x - cx) ** 2 + dy2
                if inner <= d <= outer:
                    row[x] = color

    def line(self, x0, y0, x1, y1, thick, color):
        steps = max(int(max(abs(x1 - x0), abs(y1 - y0)) * 2), 1)
        r = thick / 2
        for i in range(steps + 1):
            t = i / steps
            self.disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, color)

    def triangle_right(self, x, y, height, color):
        """Pfeilspitze, nach rechts zeigend."""
        for i in range(int(height / 2) + 1):
            self.rect(x + i, y - height / 2 + i, x + i + 1, y + height / 2 - i, color)

    # --- Ausgabe ---

    def png(self):
        raw = b"".join(b"\x00" + bytes(v for pxl in row for v in pxl)
                       for row in self.px)

        def chunk(tag, data):
            return (struct.pack(">I", len(data)) + tag + data
                    + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

        # Farbtyp 6 = RGBA, 2 = RGB.
        return (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", self.size, self.height,
                                             8, 6 if self.alpha else 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


# Ziffern und Buchstaben als **Striche**, in Anteilen einer Zelle (0..1).
# Ein Punktraster war der erste Anlauf und sah bei 1024 px nach Treppe aus.
STROKES = {
    "0": [(0.25, 0.15, 0.25, 0.85), (0.75, 0.15, 0.75, 0.85),
          (0.25, 0.15, 0.75, 0.15), (0.25, 0.85, 0.75, 0.85)],
    "1": [(0.35, 0.28, 0.55, 0.15), (0.55, 0.15, 0.55, 0.85),
          (0.32, 0.85, 0.78, 0.85)],
    "2": [(0.22, 0.25, 0.75, 0.25), (0.75, 0.25, 0.75, 0.5),
          (0.75, 0.5, 0.25, 0.5), (0.25, 0.5, 0.25, 0.85),
          (0.25, 0.85, 0.78, 0.85)],
    "3": [(0.22, 0.15, 0.75, 0.15), (0.75, 0.15, 0.75, 0.85),
          (0.35, 0.5, 0.75, 0.5), (0.22, 0.85, 0.75, 0.85)],
    "4": [(0.25, 0.15, 0.25, 0.55), (0.25, 0.55, 0.78, 0.55),
          (0.66, 0.15, 0.66, 0.85)],
    "5": [(0.78, 0.15, 0.25, 0.15), (0.25, 0.15, 0.25, 0.5),
          (0.25, 0.5, 0.75, 0.5), (0.75, 0.5, 0.75, 0.85),
          (0.75, 0.85, 0.22, 0.85)],
    "6": [(0.75, 0.15, 0.25, 0.15), (0.25, 0.15, 0.25, 0.85),
          (0.25, 0.85, 0.75, 0.85), (0.75, 0.85, 0.75, 0.5),
          (0.75, 0.5, 0.25, 0.5)],
    "7": [(0.22, 0.15, 0.78, 0.15), (0.78, 0.15, 0.45, 0.85)],
    "8": [(0.25, 0.15, 0.75, 0.15), (0.25, 0.15, 0.25, 0.85),
          (0.75, 0.15, 0.75, 0.85), (0.25, 0.5, 0.75, 0.5),
          (0.25, 0.85, 0.75, 0.85)],
    "9": [(0.25, 0.15, 0.75, 0.15), (0.25, 0.15, 0.25, 0.5),
          (0.25, 0.5, 0.75, 0.5), (0.75, 0.15, 0.75, 0.85),
          (0.22, 0.85, 0.75, 0.85)],
    "K": [(0.20, 0.10, 0.20, 0.90), (0.20, 0.52, 0.74, 0.10),
          (0.20, 0.52, 0.74, 0.90)],
    "W": [(0.10, 0.12, 0.30, 0.90), (0.30, 0.90, 0.50, 0.38),
          (0.50, 0.38, 0.70, 0.90), (0.70, 0.90, 0.90, 0.12)],
    "k": [(0.30, 0.15, 0.30, 0.85), (0.30, 0.60, 0.70, 0.30),
          (0.30, 0.60, 0.70, 0.85)],
}


def draw_text(canvas, text, cx, cy, height, thick, color, spacing=0.62,
              max_width=None):
    """Zeichnet eine kurze Zeichenkette zentriert. Nur Zeichen aus STROKES.

    `max_width` verkleinert die Höhe, bis die Zeichenkette hineinpasst — sonst
    läuft „1000" bei fester Höhe über den Rand, wie im ersten Testbild.
    """
    glyphs = [c for c in text if c in STROKES]
    if not glyphs:
        return
    if max_width is not None:
        needed = height * spacing * len(glyphs)
        if needed > max_width:
            factor = max_width / needed
            height *= factor
            thick *= factor
    width = height * spacing
    total = width * len(glyphs)
    x = cx - total / 2
    for ch in glyphs:
        for sx0, sy0, sx1, sy1 in STROKES[ch]:
            canvas.line(x + sx0 * width, cy - height / 2 + sy0 * height,
                        x + sx1 * width, cy - height / 2 + sy1 * height,
                        thick, color)
        x += width
