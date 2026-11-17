"""Arte PROVISÓRIA dos materiais das profissões (parte 3), no estilo das pinturas de assets/ui/items:
recolore pinturas existentes (minérios, essências, peças de chefe) e desenha com contorno grosso o que não tem
base (toras, couros, pergaminho). Troque pela pintura de verdade (docs/ICONES_PROMPTS.md, "Profissões").

Uso (na raiz do projeto):  python tools/icons/make_material_icons.py
"""
import colorsys
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

DIR = os.path.join("assets", "ui", "items")
S = 256
OUT_C = (34, 24, 20, 255)


def load(name):
    return Image.open(os.path.join(DIR, name + ".png")).convert("RGBA")


def save(im, name):
    im.save(os.path.join(DIR, name + ".png"))
    print("ok", name)


def recolor(im, hue, sat_mult=1.0, val_mult=1.0, min_sat=0.25, gray_tint=None):
    """Troca o matiz dos pixels coloridos (saturação >= min_sat) por `hue`; os cinzas podem ganhar `gray_tint`."""
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s >= min_sat and v > 0.12:
                h, s, v = hue, min(1.0, s * sat_mult), min(1.0, v * val_mult)
            elif gray_tint is not None and v > 0.12:
                th, ts = gray_tint
                h, s = th, max(s, ts)
            r2, g2, b2 = colorsys.hsv_to_rgb(h % 1.0, s, v)
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


def shade(c, f):
    return tuple(max(0, min(255, int(x * f))) for x in c[:3]) + (255,)


def log_icon(bark, wood):
    im = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # tora deitada na diagonal: corpo + ponta com anéis (desenhado em 2x e reduzido)
    body = [(110, 300), (300, 110), (410, 220), (220, 410)]
    d.polygon(body, fill=bark, outline=OUT_C, width=14)
    for i in range(5):
        t = 0.15 + i * 0.17
        x0, y0 = 110 + (300 - 110) * t, 300 + (110 - 300) * t
        d.line([(x0 + 20, y0 + 20), (x0 + 95, y0 + 95)], fill=shade(bark, 0.7), width=8)
    d.line([(150, 300), (300, 150)], fill=shade(bark, 1.25), width=10)
    d.ellipse((60, 250, 230, 420), fill=wood, outline=OUT_C, width=14)
    for r in (55, 35, 16):
        d.ellipse((145 - r, 335 - r, 145 + r, 335 + r), outline=shade(wood, 0.72), width=6)
    d.ellipse((330, 120, 380, 170), fill=shade(bark, 0.8), outline=OUT_C, width=10)
    return im.resize((S, S), Image.LANCZOS)


def hide_icon(c, seed):
    rnd = random.Random(seed)
    im = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(14):
        a = i / 14 * math.tau
        r = 190 + rnd.uniform(-25, 25) + (40 if i % 7 in (1, 5) else 0)
        pts.append((256 + math.cos(a) * r * 1.05, 256 + math.sin(a) * r * 0.85))
    d.polygon(pts, fill=c, outline=OUT_C, width=14)
    d.polygon([(256 + (x - 256) * 0.62, 256 + (y - 256) * 0.62) for x, y in pts], fill=shade(c, 1.15))
    for _ in range(16):
        x, y = rnd.uniform(150, 360), rnd.uniform(170, 340)
        d.line([(x, y), (x + rnd.uniform(-18, 18), y + 22)], fill=shade(c, 0.75), width=6)
    return im.resize((S, S), Image.LANCZOS)


def scroll_icon():
    im = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    paper = (238, 220, 170, 255)
    d.rectangle((120, 110, 392, 400), fill=paper, outline=OUT_C, width=14)
    for y in (180, 225, 270, 315):
        d.line([(165, y), (350, y)], fill=(150, 120, 80, 255), width=8)
    for y in (100, 410):
        d.rounded_rectangle((90, y - 34, 422, y + 34), 30, fill=shade(paper, 0.86), outline=OUT_C, width=14)
    d.ellipse((300, 330, 390, 420), fill=(185, 40, 40, 255), outline=OUT_C, width=12)
    d.ellipse((328, 358, 362, 392), fill=(225, 80, 70, 255))
    return im.resize((S, S), Image.LANCZOS)


def main():
    ore = load("iron_ore")
    for name, hue, gray in [("copper_ore", 0.06, None), ("silver_ore", 0.58, (0.6, 0.05)),
            ("mithril_ore", 0.5, (0.55, 0.12)), ("astralite_ore", 0.78, (0.75, 0.15))]:
        sm = 0.25 if name == "silver_ore" else 1.2
        save(recolor(ore, hue, sat_mult=sm, val_mult=1.25, gray_tint=gray), name)
    potion = load("mana_potion")
    for i, hue in enumerate([0.28, 0.45, 0.72, 0.12, 0.88], start=1):
        save(recolor(potion, hue, sat_mult=1.1, val_mult=1.05), "essence_t%d" % i)
    woods = [("pine_log", (120, 82, 50), (220, 180, 120)), ("oak_log", (95, 65, 40), (200, 150, 95)),
        ("silverbirch_log", (220, 220, 210), (230, 210, 170)), ("ashwood_log", (90, 88, 86), (180, 170, 150)),
        ("soulwood_log", (70, 50, 110), (170, 140, 230))]
    for name, bark, wood in woods:
        save(log_icon(bark + (255,), wood + (255,)), name)
    hides = [(160, 120, 80), (125, 85, 50), (110, 100, 90), (70, 60, 80), (120, 150, 210)]
    for i, c in enumerate(hides, start=1):
        save(hide_icon(c + (255,), i), "hide_t%d" % i)
    save(recolor(load("slime_gel"), 0.12, sat_mult=1.1, val_mult=1.1), "royal_jelly")
    save(recolor(load("champion_badge"), 0.6, sat_mult=0.35, val_mult=1.05), "knight_sigil")
    save(recolor(load("arcane_crystal"), 0.36, sat_mult=0.9, val_mult=0.8), "lich_phylactery")
    save(recolor(load("arcane_crystal"), 0.98, sat_mult=1.1, val_mult=0.75), "abyss_core")
    save(scroll_icon(), "recipe_scroll")


if __name__ == "__main__":
    main()
