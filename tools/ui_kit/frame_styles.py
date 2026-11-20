"""Três molduras de janela para comparar (A, B, C), no mesmo tamanho e com as mesmas margens das 9 fatias,
para a troca ser só o nome da textura (UITheme.frame_style, `--frame=a|b|c`).

- A "Madeira e bronze": a moldura atual, com a faixa mais fina.
- B "Ferro forjado": aço escuro escovado, quinas com chapa triangular e rebites grandes.
- C "Couro costurado": couro escuro com costura clara tracejada e cantos de filigrana dourada.

Todas: faixa de ~10 px, pergaminho quente dentro, margem de 9 fatias SIZE_MARGIN.
"""
import math

from PIL import Image, ImageDraw

from make_window_kit import (BRONZE, BRONZE_DARK, BRONZE_LIGHT, OUTLINE, WOOD, WOOD_DARK, WOOD_LIGHT, apply_noise,
                             lerp, noise_layer, parchment)

SIZE = 128
MARGIN = 30        # margem das 9 fatias (o que não estica)
BAND = 10          # largura da faixa da moldura
SMALL_SIZE = 72
SMALL_MARGIN = 16
SMALL_BAND = 5


def _band_fill(img, base, amp, seed, streak):
    w, h = img.size
    band = Image.new("RGBA", (w, h), base + (255,))
    apply_noise(band, noise_layer(w, h, amp, seed, 0.4, streak=streak), 0.6)
    img.alpha_composite(band)


def _bevel(d, s, light, dark, n=2):
    for i in range(n):
        d.line([(i, i), (s - 1 - i, i)], fill=light + (255,))
        d.line([(i, i), (i, s - 1 - i)], fill=light + (255,))
        d.line([(i, s - 1 - i), (s - 1 - i, s - 1 - i)], fill=dark + (255,))
        d.line([(s - 1 - i, i), (s - 1 - i, s - 1 - i)], fill=dark + (255,))


def _paper(img, s, band, margin, seed, trim_dark, trim, trim_light):
    d = ImageDraw.Draw(img)
    t0 = band
    d.rectangle([t0, t0, s - 1 - t0, s - 1 - t0], outline=trim_dark + (255,), width=3)
    d.rectangle([t0 + 1, t0 + 1, s - 2 - t0, s - 2 - t0], outline=trim + (255,), width=1)
    d.line([(t0 + 1, t0 + 1), (s - 2 - t0, t0 + 1)], fill=trim_light + (255,))
    p0 = t0 + 3
    paper = parchment(s - 2 * p0, s - 2 * p0, max(4, margin - p0), seed + 7)
    img.paste(paper, (p0, p0))
    sh = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    for i in range(4):
        sd.rectangle([p0 + i, p0 + i, s - 1 - p0 - i, s - 1 - p0 - i], outline=(40, 24, 10, int(60 * (1 - i / 4))))
    img.alpha_composite(sh)


def _mirror_corners(img, draw_corner):
    """Desenha a quina de cima/esquerda numa camada e espelha para as outras três."""
    s = img.size[0]
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw_corner(ImageDraw.Draw(layer))
    for flip in [None, Image.Transpose.FLIP_LEFT_RIGHT, Image.Transpose.FLIP_TOP_BOTTOM, Image.Transpose.ROTATE_180]:
        img.alpha_composite(layer if flip is None else layer.transpose(flip))


def _rivet(d, x, y, r, dark, mid, light):
    d.ellipse([x - r, y - r, x + r, y + r], fill=dark + (255,))
    d.ellipse([x - r + 1, y - r + 1, x + r - 1, y + r - 1], fill=mid + (255,))
    d.ellipse([x - r + 1, y - r + 1, x, y], fill=light + (255,))


# ------------------------------------------------------------------ A: madeira e bronze
def frame_a(s=SIZE, margin=MARGIN, band=BAND, seed=3):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    _band_fill(img, WOOD, 18, seed, True)
    d = ImageDraw.Draw(img)
    _bevel(d, s, WOOD_LIGHT, WOOD_DARK)
    d.rectangle([0, 0, s - 1, s - 1], outline=OUTLINE + (255,))
    _paper(img, s, band, margin, seed, BRONZE_DARK, BRONZE, BRONZE_LIGHT)
    arm, th = (24, 8) if s >= 100 else (13, 5)

    def corner(cd):
        cd.rectangle([1, 1, 1 + arm, 1 + th], fill=BRONZE + (255,), outline=OUTLINE + (220,))
        cd.rectangle([1, 1, 1 + th, 1 + arm], fill=BRONZE + (255,), outline=OUTLINE + (220,))
        cd.line([(2, 2), (arm, 2)], fill=BRONZE_LIGHT + (255,))
        cd.line([(2, 2), (2, arm)], fill=BRONZE_LIGHT + (255,))
        _rivet(cd, 5, 5, 2 if s >= 100 else 1, BRONZE_DARK, BRONZE, BRONZE_LIGHT)

    _mirror_corners(img, corner)
    return img


# ------------------------------------------------------------------ B: ferro forjado
IRON = (64, 68, 74)
IRON_DARK = (30, 32, 36)
IRON_LIGHT = (128, 134, 142)
STEEL = (150, 156, 164)


def frame_b(s=SIZE, margin=MARGIN, band=BAND, seed=9):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    _band_fill(img, IRON, 12, seed, True)   # aço escovado: risco horizontal fino
    d = ImageDraw.Draw(img)
    _bevel(d, s, IRON_LIGHT, IRON_DARK, 2)
    d.rectangle([0, 0, s - 1, s - 1], outline=OUTLINE + (255,))
    _paper(img, s, band, margin, seed, IRON_DARK, STEEL, (200, 206, 212))
    g = 22 if s >= 100 else 12

    def corner(cd):
        # chapa triangular na quina, com chanfro claro e três rebites
        cd.polygon([(0, 0), (g, 0), (0, g)], fill=IRON_LIGHT + (255,), outline=OUTLINE + (255,))
        cd.polygon([(2, 2), (g - 4, 2), (2, g - 4)], fill=STEEL + (255,))
        cd.line([(g - 1, 1), (1, g - 1)], fill=IRON_DARK + (255,), width=2)
        r = 2 if s >= 100 else 1
        for (x, y) in ([(5, 5), (g - 7, 4), (4, g - 7)] if s >= 100 else [(4, 4)]):
            _rivet(cd, x, y, r, IRON_DARK, IRON_LIGHT, (230, 234, 238))
        # rebites ao longo da faixa, perto da quina
        if s >= 100:
            for k in (g + 8, g + 22):
                _rivet(cd, k, band // 2 + 1, 2, IRON_DARK, IRON_LIGHT, (220, 224, 230))
                _rivet(cd, band // 2 + 1, k, 2, IRON_DARK, IRON_LIGHT, (220, 224, 230))

    _mirror_corners(img, corner)
    return img


# ------------------------------------------------------------------ C: couro costurado
LEATHER = (92, 52, 30)
LEATHER_DARK = (52, 28, 14)
LEATHER_LIGHT = (134, 84, 50)
THREAD = (226, 204, 156)
GOLD = (214, 172, 84)
GOLD_DARK = (128, 92, 34)
GOLD_LIGHT = (250, 226, 150)


def frame_c(s=SIZE, margin=MARGIN, band=BAND, seed=5):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    _band_fill(img, LEATHER, 14, seed, False)   # couro: grão sem direção
    d = ImageDraw.Draw(img)
    _bevel(d, s, LEATHER_LIGHT, LEATHER_DARK, 2)
    d.rectangle([0, 0, s - 1, s - 1], outline=OUTLINE + (255,))
    # costura tracejada no meio da faixa
    m = band // 2
    dash, gap = (4, 3) if s >= 100 else (3, 2)
    x = m + 2
    while x < s - m - 2:
        d.line([(x, m), (min(x + dash, s - m - 2), m)], fill=THREAD + (255,))
        d.line([(x, s - 1 - m), (min(x + dash, s - m - 2), s - 1 - m)], fill=THREAD + (255,))
        d.line([(m, x), (m, min(x + dash, s - m - 2))], fill=THREAD + (255,))
        d.line([(s - 1 - m, x), (s - 1 - m, min(x + dash, s - m - 2))], fill=THREAD + (255,))
        x += dash + gap
    _paper(img, s, band, margin, seed, LEATHER_DARK, GOLD_DARK, GOLD)
    R = 13 if s >= 100 else 7

    def corner(cd):
        # filigrana: dois arcos enrolados e uma gota, em ouro com contorno
        for (cx, cy, r, a0, a1) in [(R, R, R - 2, 180, 270), (R + 6, 4, 5, 90, 270), (4, R + 6, 5, 0, 180)]:
            if s < 100 and r < 6:
                continue
            box = [cx - r, cy - r, cx + r, cy + r]
            cd.arc(box, a0, a1, fill=OUTLINE + (255,), width=4)
            cd.arc(box, a0, a1, fill=GOLD + (255,), width=2)
        cd.ellipse([1, 1, 2 + R // 2, 2 + R // 2], fill=GOLD_DARK + (255,))
        cd.ellipse([2, 2, 1 + R // 2, 1 + R // 2], fill=GOLD + (255,))
        cd.ellipse([3, 3, max(3, 1 + R // 4), max(3, 1 + R // 4)], fill=GOLD_LIGHT + (255,))

    _mirror_corners(img, corner)
    return img


STYLES = {"b": frame_b}   # a escolhida; frame_a e frame_c ficam para comparar de novo


def build(out_dir):
    import os
    for k, fn in STYLES.items():
        fn().save(os.path.join(out_dir, "win_frame_%s.png" % k))
        fn(SMALL_SIZE, SMALL_MARGIN, SMALL_BAND, seed=11).save(os.path.join(out_dir, "win_frame_small_%s.png" % k))
    # amostra lado a lado para olhar fora do jogo
    sheet = Image.new("RGBA", (SIZE * 3 + 40, SIZE + 20), (70, 90, 70, 255))
    for i, k in enumerate(STYLES):
        sheet.alpha_composite(Image.open(os.path.join(out_dir, "win_frame_%s.png" % k)), (10 + i * (SIZE + 10), 10))
    return sheet
