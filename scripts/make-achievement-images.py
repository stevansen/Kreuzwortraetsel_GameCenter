#!/usr/bin/env python3
"""Erzeugt die 22 Erfolgsbilder für Game Center.

Apple verlangt je Erfolg ein Bild (512x512); ohne bleibt der Erfolg
unveröffentlicht. Gezeichnet wird programmatisch, im Stil des App-Icons: dunkler
Grund, eine Kreuzworträtsel-Zelle, darin das unterscheidende Motiv.

Der Zweck ist Erkennbarkeit, nicht Kunst. Zwei Erfolge müssen sich auf einen
Blick unterscheiden — deshalb tragen die Zähl-Erfolge ihre Zahl und die übrigen
ein eigenes Zeichen.

    python3 scripts/make-achievement-images.py [Zielverzeichnis]
"""
import sys, os
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngdraw import Canvas, draw_text, GROUND, CELL, INK, ACCENT, GOLD

SIZE = 512
MARGIN = 52          # Rand zum Bildrand
TILE = SIZE - 2 * MARGIN


def frame(accent=None):
    """Grund plus Zelle. `accent` färbt einen schmalen Streifen unten."""
    c = Canvas(SIZE, GROUND)
    c.rect(MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN, CELL)
    if accent:
        c.rect(MARGIN, SIZE - MARGIN - 26, SIZE - MARGIN, SIZE - MARGIN, accent)
    return c


def number(text, accent=None):
    c = frame(accent)
    draw_text(c, text, SIZE / 2, SIZE / 2 - 8, 210, 26, INK,
              max_width=TILE - 56)
    return c


def arrow(bent=False, label=None):
    c = frame()
    cy = SIZE / 2 - (30 if label else 0)
    x0, x1 = MARGIN + 70, SIZE - MARGIN - 90
    if bent:
        c.line(x0, cy - 60, x0, cy, 28, ACCENT)
        c.line(x0, cy, x1, cy, 28, ACCENT)
    else:
        c.line(x0, cy, x1, cy, 28, ACCENT)
    c.triangle_right(x1, cy, 96, ACCENT)
    if label:
        draw_text(c, label, SIZE / 2, SIZE - MARGIN - 78, 96, 14, INK,
                  max_width=TILE - 80)
    return c


def grid_motif(label=None):
    """Kleines Gitter mit Sperrfeldern — steht für die klassische Variante."""
    c = frame()
    n, side = 4, 62
    total = n * side
    ox = SIZE / 2 - total / 2
    oy = (SIZE / 2 - total / 2) - (36 if label else 0)
    blocks = {(0, 3), (1, 1), (2, 2), (3, 0)}
    for r in range(n):
        for col in range(n):
            x, y = ox + col * side, oy + r * side
            c.rect(x + 3, y + 3, x + side - 3, y + side - 3,
                   INK if (r, col) in blocks else GROUND if False else CELL)
            if (r, col) in blocks:
                c.rect(x + 3, y + 3, x + side - 3, y + side - 3, INK)
            else:
                c.rect(x + 5, y + 5, x + side - 5, y + side - 5, CELL)
                c.rect(x + 3, y + 3, x + side - 3, y + 6, INK)
                c.rect(x + 3, y + side - 6, x + side - 3, y + side - 3, INK)
                c.rect(x + 3, y + 3, x + 6, y + side - 3, INK)
                c.rect(x + side - 6, y + 3, x + side - 3, y + side - 3, INK)
    if label:
        draw_text(c, label, SIZE / 2, SIZE - MARGIN - 74, 92, 14, INK,
                  max_width=TILE - 80)
    return c


def letters():
    c = frame()
    draw_text(c, "KW", SIZE / 2, SIZE / 2, 200, 26, INK, max_width=TILE - 56)
    return c


def bars():
    """Vier Balken steigender Höhe — alle Schwierigkeitsstufen."""
    c = frame()
    w, gap = 58, 22
    total = 4 * w + 3 * gap
    x = SIZE / 2 - total / 2
    base = SIZE - MARGIN - 70
    for i in range(4):
        h = 70 + i * 62
        color = ACCENT if i == 3 else INK
        c.rect(x + i * (w + gap), base - h, x + i * (w + gap) + w, base, color)
    return c


def clock():
    c = frame()
    cx, cy, r = SIZE / 2, SIZE / 2, TILE / 2 - 40
    c.ring(cx, cy, r, 22, INK)
    c.line(cx, cy, cx, cy - r * 0.58, 20, INK)
    c.line(cx, cy, cx + r * 0.42, cy + r * 0.18, 20, ACCENT)
    return c


def star():
    c = frame()
    cx, cy, r = SIZE / 2, SIZE / 2, TILE / 2 - 44
    import math
    pts = [(cx + r * math.sin(math.radians(a)), cy - r * math.cos(math.radians(a)))
           for a in range(0, 360, 72)]
    for i in range(5):
        a, b = pts[i], pts[(i + 2) % 5]
        c.line(a[0], a[1], b[0], b[1], 24, GOLD)
    return c


def check(label=None):
    c = frame()
    cy = SIZE / 2 - (30 if label else 0)
    c.line(SIZE / 2 - 90, cy + 6, SIZE / 2 - 20, cy + 72, 30, ACCENT)
    c.line(SIZE / 2 - 20, cy + 72, SIZE / 2 + 100, cy - 76, 30, ACCENT)
    if label:
        draw_text(c, label, SIZE / 2, SIZE - MARGIN - 76, 92, 14, INK,
                  max_width=TILE - 80)
    return c


def moon():
    c = frame()
    cx, cy, r = SIZE / 2 + 18, SIZE / 2, TILE / 2 - 46
    c.disc(cx, cy, r, INK)
    c.disc(cx + r * 0.52, cy - r * 0.12, r * 0.86, CELL)
    return c


def sun():
    c = frame()
    cx, cy, r = SIZE / 2, SIZE / 2, TILE / 2 - 96
    c.disc(cx, cy, r, GOLD)
    import math
    for a in range(0, 360, 45):
        rad = math.radians(a)
        c.line(cx + math.cos(rad) * (r + 26), cy + math.sin(rad) * (r + 26),
               cx + math.cos(rad) * (r + 66), cy + math.sin(rad) * (r + 66),
               20, GOLD)
    return c


def comeback():
    """Ring mit Lücke und Spitze — Rückkehr."""
    c = frame()
    cx, cy, r = SIZE / 2, SIZE / 2, TILE / 2 - 52
    c.ring(cx, cy, r, 24, INK)
    # Lücke oben rechts freistellen, dann Spitze setzen.
    c.rect(cx, cy - r - 30, cx + r + 30, cy - r * 0.42, CELL)
    c.triangle_right(cx + r * 0.1, cy - r, 86, ACCENT)
    return c


def screen():
    c = frame()
    x0, x1 = MARGIN + 56, SIZE - MARGIN - 56
    y0, y1 = MARGIN + 84, SIZE - MARGIN - 150
    c.rect(x0, y0, x1, y1, INK)
    c.rect(x0 + 22, y0 + 22, x1 - 22, y1 - 22, CELL)
    c.rect(SIZE / 2 - 70, y1, SIZE / 2 + 70, y1 + 26, INK)
    c.rect(SIZE / 2 - 130, y1 + 26, SIZE / 2 + 130, y1 + 52, INK)
    return c


BADGES = {
    "first_solve": lambda: number("1"),
    "solve_10": lambda: number("10"),
    "solve_100": lambda: number("100"),
    "solve_1000": lambda: number("1000", ACCENT),
    "arrow_first": lambda: arrow(),
    "arrow_100": lambda: arrow(label="100"),
    "classic_100": lambda: grid_motif(label="100"),
    "ambidextrous": letters,
    "all_difficulties": bars,
    "bent_arrows": lambda: arrow(bent=True),
    "expert_clean": star,
    "speedrun_mittel": clock,
    "streak_7": lambda: number("7"),
    "streak_30": lambda: number("30"),
    "streak_365": lambda: number("365", ACCENT),
    "flawless_25": lambda: check(label="25"),
    "vocab_5000": lambda: number("5000"),
    "night_owl": moon,
    "early_bird": sun,
    "comeback": comeback,
    "points_100k": lambda: number("100k", ACCENT),
    "on_the_big_screen": screen,
}


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "store/achievements")
    out.mkdir(parents=True, exist_ok=True)
    for name, make in BADGES.items():
        (out / f"{name}.png").write_bytes(make().png())
    print(f"{len(BADGES)} Bilder à {SIZE}x{SIZE} → {out}")


if __name__ == "__main__":
    main()
