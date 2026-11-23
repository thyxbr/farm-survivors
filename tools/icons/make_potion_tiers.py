"""Arte PROVISÓRIA das poções de vida maiores (Maior, Superior, Suprema): recolore a pintura da Poção de Vida
(assets/ui/items/health_potion.png). O líquido escurece/brilha conforme o nível, a rolha vira prata e depois
ouro, e cada nível ganha um brilho a mais em volta do frasco. Troque pela pintura de verdade
(docs/ICONES_PROMPTS.md).

Uso (na raiz do projeto):  python tools/icons/make_potion_tiers.py
"""
import colorsys
import math
import os

from PIL import Image, ImageDraw

DIR = os.path.join("assets", "ui", "items")

# id: (matiz do líquido, mult. de saturação, mult. de valor, cor da rolha (None = mantém), brilhos)
TIERS = {
    "health_potion_greater": (0.975, 1.05, 0.78, None, 1),
    "health_potion_superior": (0.93, 1.0, 0.82, (0.0, 0.0, 0.80), 2),
    "health_potion_supreme": (0.055, 1.0, 1.08, (0.12, 0.85, 1.0), 3),
}
STAR = (255, 226, 120, 255)
STAR_OUT = (120, 70, 20, 255)


def _is_liquid(h, s, v):
    return (h < 0.04 or h > 0.93) and s > 0.35 and v > 0.2


def _is_cork(h, s, v):
    return 0.04 <= h <= 0.14 and 0.2 < s < 0.8 and v > 0.25


def recolor(im, hue, sat_mult, val_mult, cork):
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if _is_liquid(h, s, v):
                h, s, v = hue, min(1.0, s * sat_mult), min(1.0, v * val_mult)
            elif cork is not None and _is_cork(h, s, v):
                ch, cs, cv = cork
                h, s, v = ch, cs * (0.6 + 0.4 * s), min(1.0, cv * (0.55 + 0.6 * v))
            else:
                continue
            rr, gg, bb = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return out


def star(d, cx, cy, r):
    pts = []
    for i in range(8):
        ang = -math.pi / 2 + i * math.pi / 4
        rad = r if i % 2 == 0 else r * 0.32
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    d.polygon(pts, fill=STAR, outline=STAR_OUT, width=3)


def main():
    base = Image.open(os.path.join(DIR, "health_potion.png")).convert("RGBA")
    spots = [(212, 70, 26), (44, 92, 20), (214, 200, 18)]
    for name, (hue, sm, vm, cork, n) in TIERS.items():
        im = recolor(base, hue, sm, vm, cork)
        d = ImageDraw.Draw(im)
        for cx, cy, r in spots[:n]:
            star(d, cx, cy, r)
        im.save(os.path.join(DIR, name + ".png"))
        print("ok", name)


if __name__ == "__main__":
    main()
