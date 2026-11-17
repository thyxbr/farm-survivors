"""Gera o kit de UI do jogo (assets/ui/kit/*.png): botões, painéis, campos de texto e abas.

Estilo da logo: madeira escura por dentro, moldura dourada com bisel, contorno quase preto e rebites
nos cantos. Cada peça é uma textura 9-slice (os cantos não esticam): o UITheme usa StyleBoxTexture com as
margens de MARGINS. Desenha cada peça 4x maior com uma "distância até a borda" (SDF de retângulo
arredondado) e reduz no fim, então as curvas saem suaves.

Uso:  python tools/ui_kit/make_ui_kit.py
"""
import os

import numpy as np
from PIL import Image

SS = 4  # supersampling
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui", "kit")

GOLD_HI = np.array([255, 233, 160])
GOLD = np.array([222, 168, 72])
GOLD_LO = np.array([128, 82, 28])
INK = np.array([22, 12, 6])


def sd_round_rect(w, h, r, inset=0.0):
    """Distância (px, na escala final) de cada pixel até a borda; negativa dentro."""
    ys, xs = np.mgrid[0:h * SS, 0:w * SS].astype(np.float32)
    px = (xs + 0.5) / SS - w / 2
    py = (ys + 0.5) / SS - h / 2
    hx, hy = w / 2 - inset - r, h / 2 - inset - r
    qx, qy = np.abs(px) - hx, np.abs(py) - hy
    out = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    ins = np.minimum(np.maximum(qx, qy), 0)
    return out + ins - r, px, py


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def band(d, outer, inner):
    """1 entre as distâncias -outer..-inner (de fora para dentro), com 0,5 px de suavização."""
    return smooth(-d, outer - 0.5, outer + 0.5) * (1 - smooth(-d, inner - 0.5, inner + 0.5))


def mix(base, col, a):
    a = a[..., None]
    return base * (1 - a) + np.asarray(col, np.float32) * a


def grain(h, w, seed, strength):
    """Veios de madeira: ruído esticado na horizontal."""
    rng = np.random.default_rng(seed)
    n = rng.random((h * SS // 6 + 2, 3)).astype(np.float32)
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w * SS, h * SS), Image.BICUBIC),
                 np.float32) / 255.0
    return (n - 0.5) * strength


def finish(rgb, alpha, name):
    img = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    im = Image.fromarray(img, "RGBA")
    w, h = im.size
    im = im.resize((w // SS, h // SS), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".png"))
    print("salvo", name, im.size)


def gold_gradient(py, h, d, outer, inner, bright=1.0):
    """Ouro com bisel: claro em cima e na borda de fora, escuro embaixo."""
    v = np.clip(0.5 - py / h, 0, 1)        # 1 no topo
    edge = smooth(-d, outer, (outer + inner) / 2)  # brilho na aresta de fora
    c = GOLD_LO + (GOLD - GOLD_LO) * v[..., None]
    c = c + (GOLD_HI - c) * (0.55 * (1 - edge) * v)[..., None]
    return c * bright


def rivet(rgb, alpha, px, py, cx, cy, r, bright=1.0):
    dd = np.hypot(px - cx, py - cy)
    body = 1 - smooth(dd, r - 0.4, r + 0.4)
    ring = 1 - smooth(dd, r + 0.4, r + 1.2)
    rgb = mix(rgb, INK, ring)
    hl = np.clip(1 - np.hypot(px - cx + r * 0.35, py - cy + r * 0.35) / r, 0, 1)
    col = (GOLD_LO + (GOLD_HI - GOLD_LO) * hl[..., None]) * bright
    rgb = mix(rgb, col, body)
    return rgb, np.maximum(alpha, ring)


def button(name, wood_top, wood_bot, gold_bright=1.0, pressed=False, glow=None, gray=False):
    w, h, r = 72, 44, 11
    pad = 3  # espaço para o brilho de fora
    d, px, py = sd_round_rect(w, h, r, inset=pad)
    inside = 1 - smooth(d, -0.5, 0.5)
    rgb = np.zeros(d.shape + (3,), np.float32)
    # madeira: gradiente vertical + veios
    v = np.clip(0.5 + py / (h - 2 * pad), 0, 1)[..., None]
    if pressed:
        v = 1 - v
    wood = np.asarray(wood_top, np.float32) * (1 - v) + np.asarray(wood_bot, np.float32) * v
    wood = wood * (1 + grain(h, w, 3, 0.18)[..., None])
    rgb = mix(rgb, wood, inside)
    # brilho interno no topo (ou sombra, se pressionado)
    top = np.clip(1 - (py + h / 2 - pad - 4) / 7, 0, 1) * band(d, 4.5, 99)
    rgb = mix(rgb, (255, 220, 150) if not pressed else (0, 0, 0), top * (0.18 if not pressed else 0.45))
    # moldura: contorno, ouro, filete escuro
    rgb = mix(rgb, INK, band(d, 0, 1.4))
    rgb = mix(rgb, gold_gradient(py, h, d, 1.4, 4.2, gold_bright), band(d, 1.4, 4.2))
    rgb = mix(rgb, INK * 1.5, band(d, 4.2, 5.2))
    alpha = inside
    if glow is not None:
        g = np.clip(1 - d / pad, 0, 1) ** 2 * (d > 0)
        rgb = np.where((d > 0)[..., None], np.asarray(glow, np.float32), rgb)
        alpha = np.maximum(alpha, g * 0.55)
    # rebites nos quatro cantos (ficam fora da área que estica)
    for sx in (-1, 1):
        for sy in (-1, 1):
            rgb, alpha = rivet(rgb, alpha, px, py, sx * (w / 2 - pad - 7.5), sy * (h / 2 - pad - 7.5), 1.6,
                               gold_bright)
    if gray:
        lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
        rgb = np.repeat(lum[..., None], 3, -1) * 0.75
    finish(rgb, alpha, name)


def focus_ring():
    w, h, r = 72, 44, 11
    d, _, _ = sd_round_rect(w, h, r, inset=1)
    a = band(d, -1.0, 1.2) * 0.9
    rgb = np.zeros(d.shape + (3,), np.float32) + np.array([255, 236, 170], np.float32)
    finish(rgb, a, "focus")


def panel(name, inner_top, inner_bot, margin_line=True, w=128, h=128, r=12, alpha_in=0.96):
    pad = 6  # sombra
    d, px, py = sd_round_rect(w, h, r, inset=pad)
    inside = 1 - smooth(d, -0.5, 0.5)
    rgb = np.zeros(d.shape + (3,), np.float32)
    v = np.clip(0.5 + py / (h - 2 * pad), 0, 1)[..., None]
    fill = np.asarray(inner_top, np.float32) * (1 - v) + np.asarray(inner_bot, np.float32) * v
    fill = fill * (1 + grain(h, w, 7, 0.10)[..., None])
    # vinheta interna: escurece perto da moldura
    vig = np.clip(1 + d / 18, 0, 1) * inside
    fill = fill * (1 - 0.35 * vig[..., None])
    rgb = mix(rgb, fill, inside)
    alpha = inside * alpha_in
    frame = band(d, 0, 6.5)
    alpha = np.maximum(alpha, frame)
    rgb = mix(rgb, INK, band(d, 0, 1.6))
    rgb = mix(rgb, gold_gradient(py, h, d, 1.6, 5.0), band(d, 1.6, 5.0))
    rgb = mix(rgb, INK * 1.4, band(d, 5.0, 6.5))
    if margin_line:  # segundo filete dourado, fino, por dentro (moldura dupla)
        rgb = mix(rgb, GOLD * 0.75, band(d, 10.0, 11.0))
    # sombra fora
    sh = np.clip(1 - d / pad, 0, 1) ** 2 * (d > 0) * 0.5
    alpha = np.maximum(alpha, sh)
    # cantoneiras: rebite maior nos cantos
    for sx in (-1, 1):
        for sy in (-1, 1):
            rgb, alpha = rivet(rgb, alpha, px, py, sx * (w / 2 - pad - 3.6), sy * (h / 2 - pad - 3.6), 3.0)
    finish(rgb, alpha, name)


def field(name, rim):
    w, h, r = 48, 36, 7
    d, px, py = sd_round_rect(w, h, r, inset=0)
    inside = 1 - smooth(d, -0.5, 0.5)
    v = np.clip(0.5 + py / h, 0, 1)[..., None]
    rgb = np.array([10, 8, 7], np.float32) * (1 - v) + np.array([28, 22, 18], np.float32) * v
    # sombra interna no topo (campo afundado)
    sh = np.clip(1 - (py + h / 2) / 8, 0, 1)
    rgb = mix(rgb, (0, 0, 0), sh * 0.6)
    rgb = mix(rgb, np.asarray(rim, np.float32), band(d, 0, 1.6))
    rgb = mix(rgb, INK, band(d, 1.6, 2.6))
    finish(rgb, inside, name)


def tab(name, top, bot, bright):
    # aba: só os cantos de cima arredondados (a parte de baixo encosta no painel)
    w, h, r = 64, 40, 10
    d, px, py = sd_round_rect(w, h + 20, r, inset=0)
    d, px, py = d[: h * SS], px[: h * SS], py[: h * SS]
    py = py + 10
    inside = 1 - smooth(d, -0.5, 0.5)
    v = np.clip(0.5 + py / h, 0, 1)[..., None]
    rgb = np.asarray(top, np.float32) * (1 - v) + np.asarray(bot, np.float32) * v
    rgb = rgb * (1 + grain(h, w, 11, 0.15)[..., None])
    rgb = mix(rgb, INK, band(d, 0, 1.2))
    rgb = mix(rgb, gold_gradient(py, h, d, 1.2, 3.4, bright), band(d, 1.2, 3.4))
    finish(rgb, inside, name)


def slot():
    """Moldura de espaço de item/ícone: quadrado afundado com aro dourado fino."""
    w = h = 48
    d, px, py = sd_round_rect(w, h, 6, inset=0)
    inside = 1 - smooth(d, -0.5, 0.5)
    rgb = np.zeros(d.shape + (3,), np.float32) + np.array([16, 13, 11], np.float32)
    rgb = mix(rgb, (0, 0, 0), np.clip(1 + d / 9, 0, 1) * 0.6)
    rgb = mix(rgb, INK, band(d, 0, 1.0))
    rgb = mix(rgb, gold_gradient(py, h, d, 1.0, 2.6, 0.8), band(d, 1.0, 2.6))
    finish(rgb, inside, "slot")


def check(name, checked, dim=1.0):
    """Caixa de marcar 22 px: quadrado afundado com aro dourado; marcada, um visto dourado."""
    w = h = 22
    d, px, py = sd_round_rect(w, h, 4, inset=1)
    inside = 1 - smooth(d, -0.5, 0.5)
    rgb = np.zeros(d.shape + (3,), np.float32) + np.array([14, 11, 9], np.float32)
    rgb = mix(rgb, (0, 0, 0), np.clip(1 - (py + h / 2) / 6, 0, 1) * 0.5)
    rgb = mix(rgb, INK, band(d, 0, 1.0))
    rgb = mix(rgb, gold_gradient(py, h, d, 1.0, 2.6, 0.9 * dim), band(d, 1.0, 2.6))
    if checked:
        # visto: dois segmentos grossos
        def seg(ax, ay, bx, by, t):
            vx, vy = bx - ax, by - ay
            u = np.clip(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0, 1)
            dd = np.hypot(px - ax - u * vx, py - ay - u * vy)
            return 1 - smooth(dd, t - 0.5, t + 0.5)
        m = np.maximum(seg(-5, 0, -1.5, 4, 1.6), seg(-1.5, 4, 5.5, -5, 1.6))
        col = (GOLD_LO + (GOLD_HI - GOLD_LO) * np.clip(0.6 - py / 12, 0, 1)[..., None]) * dim
        rgb = mix(rgb, INK, np.maximum(seg(-5, 0.6, -1.5, 4.6, 2.4), seg(-1.5, 4.6, 5.5, -4.4, 2.4)) * 0.8)
        rgb = mix(rgb, col, m)
    finish(rgb, inside, name)


def knob(name, bright):
    """Botão do deslizador: rebite dourado de 20 px."""
    w = h = 20
    d, px, py = sd_round_rect(w, h, 9, inset=1)
    rgb = np.zeros(d.shape + (3,), np.float32)
    alpha = np.zeros(d.shape, np.float32)
    rgb, alpha = rivet(rgb, alpha, px, py, 0, 0, 7.5, bright)
    finish(rgb, alpha, name)


if __name__ == "__main__":
    WOOD_T, WOOD_B = (92, 58, 34), (48, 28, 16)
    button("button_normal", WOOD_T, WOOD_B, 0.88)
    button("button_hover", (128, 82, 44), (70, 42, 22), 1.12, glow=(255, 200, 110))
    button("button_pressed", (60, 36, 20), (36, 20, 11), 1.0, pressed=True)
    button("button_disabled", WOOD_T, WOOD_B, 0.7, gray=True)
    focus_ring()
    panel("panel", (34, 26, 22), (16, 12, 11))
    panel("panel_inset", (24, 19, 16), (14, 11, 9), margin_line=False, w=64, h=64, r=8, alpha_in=0.9)
    field("field", (150, 112, 52))
    field("field_focus", (240, 200, 110))
    tab("tab_selected", (110, 72, 38), (70, 44, 24), 1.1)
    tab("tab_unselected", (44, 32, 24), (30, 22, 17), 0.65)
    tab("tab_hover", (78, 54, 32), (50, 34, 20), 0.85)
    slot()
    check("check_off", False)
    check("check_on", True)
    check("check_off_disabled", False, 0.5)
    check("check_on_disabled", True, 0.5)
    knob("knob", 1.0)
    knob("knob_hover", 1.25)
