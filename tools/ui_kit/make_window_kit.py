"""Gera as texturas das janelas laterais (assets/ui/kit/win_*.png), desenhadas por código com PIL.

Material: moldura de madeira escura com friso de bronze e cantoneiras de metal com rebites; dentro,
pergaminho quente com fibra e as bordas um pouco mais escuras. Tudo em 9 fatias: os cantos não esticam
(margens em MARGINS, lidas por UITheme). Rodar de novo depois de mudar uma cor:

    python tools/ui_kit/make_window_kit.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui", "kit")

WOOD = (62, 40, 26)
WOOD_DARK = (34, 21, 13)
WOOD_LIGHT = (98, 66, 42)
BRONZE = (176, 134, 72)
BRONZE_LIGHT = (232, 196, 128)
BRONZE_DARK = (104, 72, 34)
PARCH = (233, 214, 172)
PARCH_EDGE = (205, 178, 128)
OUTLINE = (20, 12, 7)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def noise_layer(w, h, amp, seed, blur=0.0, streak=False):
    rnd = random.Random(seed)
    img = Image.new("L", (w, h), 128)
    px = img.load()
    for y in range(h):
        row = rnd.uniform(-amp, amp) * 0.6 if streak else 0.0
        for x in range(w):
            px[x, y] = int(128 + row + rnd.uniform(-amp, amp))
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    return img


def apply_noise(img, noise, strength):
    base = img.load()
    nz = noise.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            c = base[x, y]
            d = (nz[x, y] - 128) * strength
            base[x, y] = (max(0, min(255, int(c[0] + d))), max(0, min(255, int(c[1] + d))),
                          max(0, min(255, int(c[2] + d * 0.8))), c[3])


def parchment(w, h, edge_px, seed):
    """Pergaminho com fibra e as bordas escurecidas em `edge_px` (dentro da margem que não estica)."""
    img = Image.new("RGBA", (w, h), PARCH + (255,))
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            t = max(0.0, 1.0 - d / edge_px) ** 1.6 if edge_px > 0 else 0.0
            px[x, y] = lerp(PARCH, PARCH_EDGE, t) + (255,)
    apply_noise(img, noise_layer(w, h, 10, seed, 0.6), 0.55)
    apply_noise(img, noise_layer(w, h, 30, seed + 1, 3.0), 0.35)   # manchas largas
    return img


def wood_band(draw_img, rect, seed):
    """Faixa de madeira com veios horizontais e bisel (luz em cima/esquerda)."""
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    band = Image.new("RGBA", (w, h), WOOD + (255,))
    apply_noise(band, noise_layer(w, h, 18, seed, 0.4, streak=True), 0.6)
    draw_img.paste(band, (x0, y0))


def frame(size=192, margin=44, band=14, seed=3, arm=38, thick=11):
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # madeira em toda a área; o pergaminho entra por cima
    wood_band(img, (0, 0, s, s), seed)
    d = ImageDraw.Draw(img)
    # bisel da madeira
    for i in range(3):
        d.line([(i, i), (s - 1 - i, i)], fill=lerp(WOOD_LIGHT, WOOD, i / 3) + (255,))
        d.line([(i, i), (i, s - 1 - i)], fill=lerp(WOOD_LIGHT, WOOD, i / 3) + (255,))
        d.line([(i, s - 1 - i), (s - 1 - i, s - 1 - i)], fill=WOOD_DARK + (255,))
        d.line([(s - 1 - i, i), (s - 1 - i, s - 1 - i)], fill=WOOD_DARK + (255,))
    d.rectangle([0, 0, s - 1, s - 1], outline=OUTLINE + (255,))
    # friso de bronze em volta do papel
    t0 = band
    d.rectangle([t0, t0, s - 1 - t0, s - 1 - t0], outline=BRONZE_DARK + (255,), width=4)
    d.rectangle([t0 + 1, t0 + 1, s - 2 - t0, s - 2 - t0], outline=BRONZE + (255,), width=2)
    d.line([(t0 + 1, t0 + 1), (s - 2 - t0, t0 + 1)], fill=BRONZE_LIGHT + (255,))
    d.line([(t0 + 1, t0 + 1), (t0 + 1, s - 2 - t0)], fill=BRONZE_LIGHT + (255,))
    # pergaminho
    p0 = t0 + 4
    paper = parchment(s - 2 * p0, s - 2 * p0, margin - p0, seed + 7)
    img.paste(paper, (p0, p0))
    # sombra do friso sobre o papel
    sh = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    for i in range(6):
        sd.rectangle([p0 + i, p0 + i, s - 1 - p0 - i, s - 1 - p0 - i], outline=(40, 24, 10, int(70 * (1 - i / 6))))
    img = Image.alpha_composite(img, sh)
    # cantoneiras de metal com rebites
    for cx, cy in [(0, 0), (1, 0), (0, 1), (1, 1)]:
        corner(img, cx, cy, s, arm, thick)
    return img


def corner(img, fx, fy, s, arm=38, thick=11):
    """Cantoneira em L sobre a quina (fx/fy: 0 = esquerda/cima, 1 = direita/baixo)."""
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def X(x):
        return x if fx == 0 else s - 1 - x

    def Y(y):
        return y if fy == 0 else s - 1 - y

    def rect(a, b, c, e, **kw):
        xs = sorted([X(a), X(c)])
        ys = sorted([Y(b), Y(e)])
        d.rectangle([xs[0], ys[0], xs[1], ys[1]], **kw)

    o = 2
    rect(o, o, o + arm, o + thick, fill=BRONZE_DARK + (255,))
    rect(o, o, o + thick, o + arm, fill=BRONZE_DARK + (255,))
    rect(o + 1, o + 1, o + arm - 1, o + thick - 2, fill=BRONZE + (255,))
    rect(o + 1, o + 1, o + thick - 2, o + arm - 1, fill=BRONZE + (255,))
    # brilho no lado de cima/esquerda da peça
    rect(o + 1, o + 1, o + arm - 1, o + 2, fill=BRONZE_LIGHT + (255,))
    rect(o + 1, o + 1, o + 2, o + arm - 1, fill=BRONZE_LIGHT + (255,))
    # pontas cortadas em ângulo
    for (a, b) in [(o + arm, o + thick // 2), (o + thick // 2, o + arm)]:
        rect(a - 3, b - 1, a, b + 1, fill=BRONZE_DARK + (255,))
    # rebites
    rivets = [(o + 6, o + 6), (o + arm - 7, o + 5), (o + 5, o + arm - 7)] if thick >= 9 else [(o + 4, o + 4)]
    for (a, b) in rivets:
        cx, cy = X(a), Y(b)
        d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=BRONZE_DARK + (255,))
        d.ellipse([cx - 2, cy - 2, cx + 1, cy + 1], fill=BRONZE_LIGHT + (255,))
    # contorno escuro
    rect(o, o, o + arm, o + thick, outline=OUTLINE + (200,))
    rect(o, o, o + thick, o + arm, outline=OUTLINE + (200,))
    img.alpha_composite(layer)


def button(fill, border, light, dark, w=64, h=36, r=4):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], r, fill=border + (255,))
    d.rounded_rectangle([2, 2, w - 3, h - 3], r - 1, fill=fill + (255,))
    # bisel: luz em cima, sombra embaixo
    d.line([(3, 2), (w - 4, 2)], fill=light + (255,))
    d.line([(3, h - 3), (w - 4, h - 3)], fill=dark + (255,))
    for y in range(3, h - 3):
        t = (y - 3) / max(1, h - 7)
        c = lerp(lerp(fill, light, 0.25), lerp(fill, dark, 0.2), t)
        d.line([(3, y), (w - 4, y)], fill=c + (255,))
    apply_noise(img, noise_layer(w, h, 6, w + h, 0.5), 0.4)
    return img


def close_button(fill, size=34):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, size - 1, size - 1], fill=OUTLINE + (255,))
    d.ellipse([1, 1, size - 2, size - 2], fill=BRONZE_DARK + (255,))
    d.ellipse([2, 2, size - 3, size - 3], fill=BRONZE + (255,))
    d.arc([2, 2, size - 3, size - 3], 180, 300, fill=BRONZE_LIGHT + (255,), width=2)
    d.ellipse([5, 5, size - 6, size - 6], fill=fill + (255,))
    return img


def divider(w=240, h=14):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = h // 2
    for x in range(w):
        t = 1.0 - abs(x - w / 2) / (w / 2)
        a = int(200 * min(1.0, t * 2.5))
        d.point((x, cy), fill=BRONZE_DARK + (a,))
        d.point((x, cy + 1), fill=BRONZE_LIGHT + (a // 3,))
    c = w // 2
    d.polygon([(c - 7, cy), (c, cy - 6), (c + 7, cy), (c, cy + 6)], fill=BRONZE_DARK + (255,))
    d.polygon([(c - 4, cy), (c, cy - 3), (c + 4, cy), (c, cy + 3)], fill=BRONZE_LIGHT + (255,))
    return img


def inset(w=96, h=96):
    """Quadro rebaixado dentro do papel (seções): papel um pouco mais escuro com sombra interna."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], 5, fill=(150, 116, 74, 255))
    inner = Image.new("RGBA", (w - 2, h - 2), (223, 202, 158, 255))
    apply_noise(inner, noise_layer(w - 2, h - 2, 8, 11, 0.6), 0.5)
    img.paste(inner, (1, 1))
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    for i in range(5):
        sd.line([(1, 1 + i), (w - 2, 1 + i)], fill=(60, 36, 14, int(55 * (1 - i / 5))))
        sd.line([(1 + i, 1), (1 + i, h - 2)], fill=(60, 36, 14, int(40 * (1 - i / 5))))
    img = Image.alpha_composite(img, sh)
    d = ImageDraw.Draw(img)
    d.line([(2, h - 2), (w - 3, h - 2)], fill=(250, 238, 210, 160))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    frame().save(os.path.join(OUT, "win_frame.png"))
    # dica de item e quadros pequenos: friso fino, cantoneiras curtas
    frame(size=96, margin=20, band=6, seed=5, arm=18, thick=7).save(os.path.join(OUT, "win_frame_small.png"))
    paper_btn = dict(fill=(218, 196, 150), border=(92, 62, 36), light=(246, 232, 200), dark=(170, 140, 96))
    button(**paper_btn).save(os.path.join(OUT, "win_btn.png"))
    button(fill=(230, 210, 166), border=(120, 84, 44), light=(255, 244, 214), dark=(184, 154, 108)).save(
        os.path.join(OUT, "win_btn_hover.png"))
    # ligado (aba ativa, filtro escolhido): couro escuro com aro de bronze, texto claro
    button(fill=(86, 56, 34), border=BRONZE_DARK, light=(128, 90, 58), dark=(52, 32, 18)).save(
        os.path.join(OUT, "win_btn_on.png"))
    button(fill=(206, 190, 158), border=(150, 128, 98), light=(222, 210, 184), dark=(186, 168, 136)).save(
        os.path.join(OUT, "win_btn_off.png"))
    # ação principal (Comprar, Fabricar): vermelho
    button(fill=(150, 40, 28), border=(70, 16, 10), light=(206, 92, 70), dark=(98, 22, 14)).save(
        os.path.join(OUT, "win_btn_red.png"))
    close_button((70, 44, 28)).save(os.path.join(OUT, "win_close.png"))
    close_button((120, 36, 24)).save(os.path.join(OUT, "win_close_hover.png"))
    divider().save(os.path.join(OUT, "win_divider.png"))
    inset().save(os.path.join(OUT, "win_inset.png"))
    print("ok:", OUT)


if __name__ == "__main__":
    main()
