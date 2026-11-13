# Traça as espadas da folha de conceito (refs/espadas.webp) para o weapons.py:
#   - contornos (com furos) de cada peça plana, em pixels da folha;
#   - perfis de revolução (cabo, pomo) pela largura da máscara em cada linha;
#   - textura de cada espada: recorte da folha com o fundo preenchido pela cor da borda
#     (assim o UV projetado de frente nunca puxa o branco do fundo).
# python tools/blender/trace_swords.py            -> grava traced/espadas_trace.json e traced/tex/<id>.png
#   (refs/ é local, fora do git; traced/ é versionado: o build só precisa dele)
# python tools/blender/trace_swords.py grid <id>  -> grade 10 px da espada (para escolher os cortes)
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "refs", "espadas.webp")
BG = np.array([252, 251, 252])

# Peças de cada espada, em pixels da folha. Cada peça: (tipo, nome, y0, y1, x0, x1, extras)
#   slab  -> placa inflada do contorno da máscara dentro da caixa; extras: th, bevel (m)
#   lathe -> sólido de revolução; raio = meia largura da máscara por linha; extras: seg
# "grip": (y0, y1) do cabo -> origem no centro dele. Escala única: 1.2 m por 426 px (a da Chama Rosada).
def _b(th, bevel, **k):
    return {"th": th, "bevel": bevel, **k}


BLADE, GUARD, THIN, HILT = _b(0.011, 0.014), _b(0.017, 0.010), _b(0.009, 0.010), _b(0.016, 0.010)
SWORDS = {
    "w_thorn_root": {"box": (172, 7, 259, 520), "grip": (212, 435), "parts": [
        ("slab", "Spine", 5, 232, 172, 259, _b(0.008, 0.010)),
        ("slab", "Vines", 205, 520, 172, 259, _b(0.014, 0.012))]},
    "w_crystal_frost": {"box": (264, 3, 438, 529), "grip": (349, 435), "parts": [
        ("slab", "Blade", 3, 352, 264, 438, BLADE),
        ("slab", "Guard", 340, 380, 264, 438, GUARD),
        ("lathe", "Grip", 372, 500, 330, 370, {"seg": 8}),
        ("lathe", "Pommel", 495, 529, 325, 375, {"seg": 8})]},
    "w_azure_edge": {"box": (494, 5, 556, 530), "grip": (531, 460), "parts": [
        ("slab", "Blade", 5, 350, 494, 556, _b(0.009, 0.012)),
        ("slab", "Guard", 330, 405, 494, 556, GUARD),
        ("lathe", "Grip", 398, 530, 510, 552, {"seg": 6})]},
    "w_moon_crescent": {"box": (642, 69, 754, 512), "grip": (693, 430), "parts": [
        ("slab", "Blade", 69, 350, 642, 754, BLADE),
        ("slab", "Guard", 335, 392, 642, 754, GUARD),
        ("slab", "SpikeL", 388, 445, 642, 683, THIN),
        ("slab", "Feathers", 388, 420, 703, 754, _b(0.008, 0.008)),
        ("lathe", "Grip", 385, 472, 682, 704, {"seg": 8}),
        ("lathe", "Pommel", 470, 512, 675, 712, {"seg": 8})]},
    "w_royal_wings": {"box": (763, 0, 944, 530), "grip": (848, 446), "parts": [
        ("slab", "Blade", 0, 250, 763, 944, _b(0.012, 0.016)),
        ("slab", "Guard", 235, 405, 763, 944, _b(0.02, 0.014)),
        ("lathe", "Grip", 400, 492, 835, 862, {"seg": 8}),
        ("lathe", "Pommel", 488, 530, 830, 868, {"seg": 8})]},
    "w_venom_leaf": {"box": (962, 63, 1050, 490), "grip": (1009, 404), "parts": [
        ("slab", "Blade", 63, 365, 962, 1050, BLADE),
        ("lathe", "Grip", 360, 448, 1000, 1020, {"seg": 8}),
        ("lathe", "Pommel", 444, 490, 995, 1025, {"seg": 8})]},
    "w_neon_edge": {"box": (0, 530, 89, 1050), "grip": (47, 955), "parts": [
        ("slab", "Blade", 530, 885, 0, 89, BLADE),
        ("slab", "Hilt", 870, 1050, 0, 89, HILT)]},
    "w_titan_cleaver": {"box": (122, 584, 210, 1035), "grip": (155, 952), "parts": [
        ("slab", "Blade", 584, 895, 122, 210, _b(0.013, 0.014)),
        ("slab", "Guard", 878, 915, 122, 210, _b(0.019, 0.010)),
        ("lathe", "Grip", 905, 1000, 140, 170, {"seg": 8}),
        ("lathe", "Pommel", 995, 1035, 138, 172, {"seg": 6})]},
    "w_amber_fang": {"box": (248, 541, 322, 1071), "grip": (285, 967), "parts": [
        ("slab", "Blade", 541, 835, 248, 322, _b(0.010, 0.013)),
        ("slab", "Guard", 820, 940, 248, 322, _b(0.013, 0.010)),
        ("lathe", "Grip", 935, 1000, 275, 295, {"seg": 8}),
        ("slab", "Tail", 995, 1071, 248, 322, THIN)]},
    "w_coral_spine": {"box": (332, 602, 474, 1034), "grip": (405, 940), "parts": [
        ("slab", "Head", 602, 905, 332, 474, _b(0.012, 0.012)),
        ("lathe", "Grip", 900, 978, 396, 414, {"seg": 8}),
        ("slab", "Hook", 970, 1034, 332, 474, THIN)]},
    "w_ivory_wing": {"box": (491, 528, 622, 1062), "grip": (550, 992), "parts": [
        ("slab", "Blade", 528, 860, 491, 622, _b(0.012, 0.016)),
        ("slab", "Guard", 840, 958, 491, 622, _b(0.016, 0.012)),
        ("lathe", "Grip", 952, 1035, 540, 562, {"seg": 8}),
        ("lathe", "Pommel", 1030, 1062, 535, 568, {"seg": 8})]},
    "w_scarlet_talon": {"box": (654, 558, 791, 1034), "grip": (696, 940), "parts": [
        ("slab", "Body", 558, 1034, 654, 791, _b(0.013, 0.014)),
        ("lathe", "Grip", 905, 975, 684, 708, {"seg": 8})]},
    "w_crimson_reed": {"box": (830, 558, 894, 1020), "grip": (856, 968), "parts": [
        ("slab", "Blade", 558, 900, 830, 894, _b(0.009, 0.012)),
        ("slab", "Guard", 885, 930, 830, 894, GUARD),
        ("lathe", "Grip", 925, 1020, 845, 868, {"seg": 8})]},
    "w_pale_crescent": {"box": (886, 699, 1080, 994), "grip": (1008, 955), "parts": [
        ("slab", "Blade", 699, 900, 886, 1080, _b(0.012, 0.016)),
        ("slab", "Collar", 893, 925, 950, 1060, _b(0.022, 0.010)),
        ("slab", "Loop", 918, 994, 960, 1060, _b(0.016, 0.008))]},
}


def load():
    im = np.asarray(Image.open(SHEET).convert("RGB")).astype(np.int16)
    m = np.abs(im - BG).max(axis=2) > 7
    mi = Image.fromarray((m * 255).astype("uint8")).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    return im.astype(np.uint8), np.asarray(mi) > 0


def components(m):
    seen = np.zeros_like(m, bool)
    H, W = m.shape
    out = []
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        st, pix = [(y0, x0)], []
        seen[y0, x0] = True
        while st:
            y, x = st.pop()
            pix.append((y, x))
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    st.append((yy, xx))
        if len(pix) > 150:
            ys, xs = zip(*pix)
            out.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1, len(pix)))
    return out


def loops(m):
    """Bordas pixel/fundo em laços fechados (cantos de pixel), fg à esquerda: externos anti-horário
    (em y para baixo: horário na tela), furos no sentido contrário."""
    H, W = m.shape
    p = np.pad(m, 1)
    nxt = {}
    # arestas orientadas com o pixel cheio à esquerda (coordenadas de canto, y para baixo)
    for y in range(H + 1):
        for x in range(W + 1):
            pass
    ys, xs = np.nonzero(p[1:-1, 1:-1])
    for y, x in zip(ys, xs):
        P = p[y + 1 - 1:y + 1 + 2, x + 1 - 1:x + 1 + 2]
        if not P[0, 1]:
            nxt.setdefault((x + 1, y), []).append((x, y))          # topo: direita -> esquerda
        if not P[2, 1]:
            nxt.setdefault((x, y + 1), []).append((x + 1, y + 1))  # base: esquerda -> direita
        if not P[1, 0]:
            nxt.setdefault((x, y), []).append((x, y + 1))          # esquerda: cima -> baixo
        if not P[1, 2]:
            nxt.setdefault((x + 1, y + 1), []).append((x + 1, y))  # direita: baixo -> cima
    out = []
    while nxt:
        start = next(iter(nxt))
        loop, cur = [start], start
        while True:
            lst = nxt[cur]
            n = lst.pop()
            if not lst:
                del nxt[cur]
            if n == start:
                break
            loop.append(n)
            cur = n
            if cur not in nxt:
                break
        if len(loop) >= 8:
            out.append(loop)
    return out


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0], float), np.array(pts[-1], float)
    ab = b - a
    L = np.hypot(*ab) or 1e-9
    d = [abs(ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) / L for p in pts[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] > eps:
        return rdp(pts[:i + 1], eps)[:-1] + rdp(pts[i:], eps)
    return [pts[0], pts[-1]]


def simplify(loop, eps=0.9):
    # suaviza a escada dos cantos de pixel (média de 3) e simplifica
    n = len(loop)
    sm = [((loop[i - 1][0] + 2 * loop[i][0] + loop[(i + 1) % n][0]) / 4,
           (loop[i - 1][1] + 2 * loop[i][1] + loop[(i + 1) % n][1]) / 4) for i in range(n)]
    k = max(range(n), key=lambda i: (sm[i][1], sm[i][0]))
    sm = sm[k:] + sm[:k]
    f = max(range(n), key=lambda i: (sm[i][0] - sm[0][0]) ** 2 + (sm[i][1] - sm[0][1]) ** 2)
    out = rdp(sm[:f + 1], eps)[:-1] + rdp(sm[f:] + [sm[0]], eps)[:-1]   # laço fechado: duas metades
    return [(round(x, 1), round(y, 1)) for x, y in out]


def area(l):
    return 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(l, l[1:] + l[:1]))


def fill_bg(rgb, m, iters=14):
    """Fundo recebe a média dos vizinhos já cheios, anel por anel. Parte só do miolo com cor de verdade
    (longe do branco do fundo, ou 3 px para dentro da máscara): a borda anti-serrilhada da folha é clara,
    e o gume da malha, que fica sobre ela, sairia com calombos brancos."""
    def erode(a, k):
        return np.asarray(Image.fromarray((a * 255).astype("uint8")).filter(ImageFilter.MinFilter(k))) > 0
    solid = (np.abs(rgb.astype(np.int16) - BG).max(axis=2) > 30) & m
    core = erode(solid, 3) | erode(m, 7)       # pintura branca no miolo é cor, não fundo
    col = rgb.astype(float) * core[..., None]
    have = core.copy()
    for _ in range(iters):
        acc = np.zeros_like(col)
        cnt = np.zeros(have.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                acc += np.roll(np.roll(col * have[..., None], dy, 0), dx, 1)
                cnt += np.roll(np.roll(have, dy, 0), dx, 1)
        new = (~have) & (cnt > 0)
        col[new] = acc[new] / cnt[new][:, None]
        have |= new
    return col.clip(0, 255).astype(np.uint8)


def grid(rgb, box, out, k=3):
    x0, y0, x1, y1 = box
    c = Image.fromarray(rgb[y0:y1, x0:x1]).resize(((x1 - x0) * k, (y1 - y0) * k), Image.LANCZOS)
    d = ImageDraw.Draw(c)
    for x in range((x0 // 10 + 1) * 10, x1, 10):
        d.line([((x - x0) * k, 0), ((x - x0) * k, c.height)], fill=(0, 0, 255) if x % 50 == 0 else (0, 170, 0))
        if x % 50 == 0:
            d.text(((x - x0) * k + 2, 2), str(x), fill=(0, 0, 0))
    for y in range((y0 // 10 + 1) * 10, y1, 10):
        d.line([(0, (y - y0) * k), (c.width, (y - y0) * k)], fill=(0, 0, 255) if y % 50 == 0 else (0, 170, 0))
        if y % 50 == 0:
            d.text((2, (y - y0) * k + 2), str(y), fill=(0, 0, 0))
    c.save(out)


def trace(sid, cfg, rgb, m, filled):
    x0, y0, x1, y1 = cfg["box"]
    parts = []
    for kind, name, a, b, xa, xb, extra in cfg["parts"]:
        sub = np.zeros_like(m)
        sub[a:b, xa:xb] = m[a:b, xa:xb]
        if kind == "slab":
            ls = [simplify(l, extra.get("eps", 1.2)) for l in loops(sub)]
            ls = [l for l in ls if abs(area(l)) > extra.get("min_area", 30)]
            outer = [l for l in ls if area(l) < 0]   # y para baixo: externo sai negativo
            holes = [l for l in ls if area(l) > 0]
            for i, o in enumerate(outer):
                parts.append({"kind": "slab", "name": f"{name}{i}" if len(outer) > 1 else name, "outline": o,
                              "holes": holes, **extra})
        else:
            prof = []
            for y in range(a, b):
                xs = np.nonzero(sub[y])[0]
                if len(xs):
                    prof.append((y, (xs[0] + xs[-1] + 1) / 2, (xs[-1] + 1 - xs[0]) / 2))
            step = extra.get("step", 2)
            prof = prof[::step] + ([prof[-1]] if (len(prof) - 1) % step else [])
            parts.append({"kind": "lathe", "name": name, "prof": prof, **extra})
    tex_dir = os.path.join(HERE, "traced", "tex")
    os.makedirs(tex_dir, exist_ok=True)
    Image.fromarray(filled[y0:y1, x0:x1]).save(os.path.join(tex_dir, sid + ".png"))
    return {"box": cfg["box"], "grip": cfg["grip"], "parts": parts}


if __name__ == "__main__":
    rgb, m = load()
    if len(sys.argv) > 1 and sys.argv[1] == "comps":
        for c in sorted(components(m), key=lambda c: (c[1] > 520, c[0])):
            print(c)
        sys.exit(0)
    if len(sys.argv) > 2 and sys.argv[1] == "grid":
        grid(rgb, SWORDS[sys.argv[2]]["box"], sys.argv[3])
        sys.exit(0)
    filled = fill_bg(rgb, m)
    data = {sid: trace(sid, cfg, rgb, m, filled) for sid, cfg in SWORDS.items()}
    with open(os.path.join(HERE, "traced", "espadas_trace.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    for sid, d in data.items():
        print(sid, [(p["name"], len(p.get("outline", p.get("prof", [])))) for p in d["parts"]])
