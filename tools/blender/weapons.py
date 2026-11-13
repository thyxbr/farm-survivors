# Espadas do jogo (GLB w_<id>.glb). Carregado por build_assets.py via exec (usa mat, part, hull, empty,
# join_all, export, hexc). Convenção: centro do cabo na origem, lâmina subindo em +Z, largura em X,
# espessura em Y. O empty "Tip" marca a ponta (o jogo usa para rastro/alcance).
# knight_look.gd instancia o GLB no WeaponHolder quando o item tem "model".
import math
from mathutils import Vector

WEAPONS = []   # nomes dos builders, registrados em BUILDERS


def _m(name, hx, rough=0.4, metal=0.0, glow=0.0):
    c = hexc(hx)
    return mat(name, c, rough, metal, emit=c if glow > 0 else None, strength=glow)


def _cr(p0, p1, p2, p3, t):
    """Catmull-Rom escalar."""
    t2, t3 = t * t, t * t * t
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def _resample(keys, n):
    """keys: [(x, z, wl, wr, th)] -> n estações suavizadas (Catmull-Rom em todas as colunas)."""
    k = [keys[0]] + list(keys) + [keys[-1]]
    out = []
    segs = len(keys) - 1
    for i in range(n):
        u = i / (n - 1) * segs
        s = min(int(u), segs - 1)
        t = u - s
        row = [_cr(k[s][c], k[s + 1][c], k[s + 2][c], k[s + 3][c], t) for c in range(5)]
        row[2], row[3], row[4] = max(row[2], 0.0), max(row[3], 0.0), max(row[4], 0.0006)
        out.append(row)
    return out


def blade(name, keys, material, n=12, ridge=0.0):
    """Lâmina com seção em losango seguindo uma espinha curva no plano XZ.
    keys: (x, z, largura_esq, largura_dir, meia_espessura). 'esq' = lado -X quando a espinha sobe.
    ridge desloca a quina central na direção da esquerda (fração da largura esquerda)."""
    print("PART", name, "blade", flush=True)
    st = _resample(keys, n) if n > len(keys) else [list(k) for k in keys]
    bm = bmesh.new()
    rows = []
    for i, (x, z, wl, wr, th) in enumerate(st):
        a = st[max(i - 1, 0)]
        b = st[min(i + 1, len(st) - 1)]
        t = Vector((b[0] - a[0], b[1] - a[1]))
        t = t.normalized() if t.length > 1e-6 else Vector((0, 1))
        nl = Vector((-t.y, t.x))           # normal à esquerda
        p = Vector((x, z))
        L = p + nl * wl
        R = p - nl * wr
        C = p + nl * (wl * ridge)
        rows.append([bm.verts.new((L.x, 0, L.y)), bm.verts.new((C.x, -th, C.y)),
                     bm.verts.new((R.x, 0, R.y)), bm.verts.new((C.x, th, C.y))])
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        for j in range(4):
            j2 = (j + 1) % 4
            try:
                bm.faces.new((a[j], a[j2], b[j2], b[j]))
            except ValueError:
                pass
    for r in (rows[0], rows[-1]):
        try:
            bm.faces.new(r)
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0004, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def spike(name, x, z, ang, length, w, th, material):
    """Espinho triangular saindo de (x, z); ang em radianos a partir de +Z (positivo = para +X)."""
    d = Vector((math.sin(ang), math.cos(ang)))
    pr = Vector((d.y, -d.x)) * (w / 2)
    b = Vector((x, z))
    tip = b + d * length
    pts = [(b.x + pr.x, 0, b.y + pr.y), (b.x - pr.x, 0, b.y - pr.y),
           (b.x, -th, b.y), (b.x, th, b.y), (tip.x, 0, tip.y)]
    return hull(name, pts, material)


def tube(name, pts, r, material, seg=6):
    """Cilindros ligando pontos 3D (cipós, alças)."""
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        d = b - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
        part(f"{name}{i}", "cyl", tuple((a + b) / 2), (r * 2, r * 2, d.length + r), material, rot=tuple(rot), seg=seg)


def grip(L, r, m, rings=0, ring_m=None, z0=0.0, seg=8):
    part("Grip", "cyl", (0, 0, z0), (r * 2, r * 2, L), m, seg=seg)
    for i in range(rings):
        z = z0 - L / 2 + L * (i + 0.5) / rings
        part(f"GripRing{i}", "cyl", (0, 0, z), (r * 2.35, r * 2.35, L / rings * 0.35), ring_m or m, seg=seg)


def gem(name, x, z, r, m, y=0.0):
    part(name, "ico", (x, y, z), (r * 2, r * 1.3, r * 2), m, sub=1)


def finish(asset, tip_x, tip_z):
    join_all("Weapon")
    empty("Tip", (tip_x, 0, tip_z))
    export(asset)


def _sym(fn, *a):
    """Chama fn para os dois lados (x e ângulo espelhados)."""
    fn(1, *a)
    fn(-1, *a)


# ------------------------------------------------------------------ 1. Gume Celeste (arma inicial)
def build_w_azure_edge():
    steel = _m("w_steel", "#B9C3CE", 0.25, 0.9)
    edge = _m("w_cyan", "#55DDF5", 0.2, 0.3, glow=1.2)
    dark = _m("w_black", "#1E2026", 0.6)
    grey = _m("w_grey", "#8C939C", 0.35, 0.8)
    sp = [(0.0, 0.14), (0.004, 0.45), (0.012, 0.75), (0.026, 1.0)]
    blade("BladeBack", [(x, z, w, 0.0, 0.011) for (x, z), w in zip(sp, (0.026, 0.026, 0.024, 0.02))]
          + [(0.04, 1.08, 0.0, 0.0, 0.002)], steel, n=10)
    blade("BladeEdge", [(x, z, 0.0, w, 0.007) for (x, z), w in zip(sp, (0.018, 0.018, 0.017, 0.016))]
          + [(0.04, 1.08, 0.0, 0.0, 0.002)], edge, n=10)
    for i in range(3):
        part(f"Notch{i}", "cube", (-0.012, 0, 0.2 + i * 0.035), (0.024, 0.026, 0.008), dark, rot=(0, -0.5, 0))
    part("Collar", "cube", (0, 0, 0.125), (0.052, 0.03, 0.04), grey)
    part("Guard", "cube", (0.0, 0, 0.095), (0.075, 0.042, 0.025), dark, rot=(0, 0.15, 0))
    grip(0.17, 0.016, dark, rings=5, ring_m=grey)
    part("Pommel", "cyl", (0, 0, -0.1), (0.038, 0.038, 0.035), grey, seg=8)
    finish("w_azure_edge", 0.04, 1.08)


# ------------------------------------------------------------------ 2. Espinho da Raiz
def build_w_thorn_root():
    bone = _m("w_bone", "#ECE6DA", 0.55)
    vine = _m("w_vine", "#86664C", 0.85)
    vine_d = _m("w_vine_dark", "#55402F", 0.85)
    blade("Spine", [(0, 0.1, 0.016, 0.016, 0.014), (0, 0.6, 0.015, 0.015, 0.013), (0, 1.12, 0.004, 0.004, 0.005),
                    (0, 1.16, 0, 0, 0.002)], bone, n=6)
    for i in range(9):
        z = 0.46 + i * 0.075
        ln = 0.075 - i * 0.005
        _sym(lambda s, z=z, ln=ln, i=i: spike(f"Thorn{i}{s}", s * 0.012, z, s * 1.05, ln, 0.03, 0.009, bone))
    # cipós trançados subindo pelo cabo e pela base da lâmina
    for k, (m, ph) in enumerate(((vine, 0.0), (vine_d, math.pi))):
        pts = []
        for i in range(15):
            z = -0.2 + i * 0.045
            a = ph + i * 0.9
            rr = 0.03 if z < 0.1 else 0.024
            pts.append((math.cos(a) * rr, math.sin(a) * rr, z))
        tube(f"Vine{k}_", pts, 0.013, m)
    tube("Curl", [(0.02, 0, 0.42), (0.07, 0, 0.47), (0.1, 0, 0.43), (0.085, 0, 0.39)], 0.011, vine)
    tube("CurlB", [(-0.02, 0, 0.36), (-0.065, 0, 0.32), (-0.06, 0, 0.27)], 0.01, vine_d)
    part("Core", "cyl", (0, 0, 0.0), (0.03, 0.03, 0.42), vine_d, seg=6)
    for i, a in enumerate((0.5, 2.6, 4.4)):
        tube(f"Root{i}_", [(0, 0, -0.18), (math.cos(a) * 0.04, math.sin(a) * 0.03, -0.24),
                           (math.cos(a) * 0.06, math.sin(a) * 0.04, -0.28)], 0.008, vine)
    finish("w_thorn_root", 0, 1.16)


# ------------------------------------------------------------------ 3. Lâmina de Cristal
def build_w_crystal_frost():
    ice = _m("w_ice", "#A8EDE8", 0.15, 0.1, glow=0.35)
    ice_d = _m("w_ice_dark", "#5FBFC0", 0.25, 0.2)
    keys = [(0, 0.13, 0.028, 0.028, 0.014), (0, 0.24, 0.046, 0.046, 0.017), (0, 0.31, 0.03, 0.03, 0.014),
            (0, 0.5, 0.05, 0.05, 0.018), (0, 0.58, 0.032, 0.032, 0.014), (0, 0.8, 0.046, 0.046, 0.017),
            (0, 0.88, 0.03, 0.03, 0.013), (0, 1.06, 0.03, 0.03, 0.012), (0, 1.18, 0.0, 0.0, 0.002)]
    blade("Blade", keys, ice, n=len(keys))
    part("Guard", "cube", (0, 0, 0.105), (0.34, 0.03, 0.03), ice_d)
    _sym(lambda s: spike(f"GuardEnd{s}", s * 0.165, 0.105, s * 1.5708, 0.09, 0.06, 0.016, ice_d))
    _sym(lambda s: spike(f"GuardTop{s}", s * 0.07, 0.115, s * 0.15, 0.08, 0.022, 0.01, ice))
    _sym(lambda s: spike(f"GuardTip{s}", s * 0.135, 0.115, s * 0.2, 0.06, 0.02, 0.009, ice))
    _sym(lambda s: spike(f"GuardLow{s}", s * 0.11, 0.095, s * 2.8, 0.045, 0.02, 0.008, ice))
    grip(0.18, 0.016, ice_d)
    gem("Pommel", 0, -0.11, 0.028, ice)
    finish("w_crystal_frost", 0, 1.18)


# ------------------------------------------------------------------ 4. Crescente Lunar
def build_w_moon_crescent():
    silver = _m("w_silver", "#C8CDD6", 0.25, 0.9)
    pink = _m("w_pink", "#F06A8E", 0.3, 0.2, glow=0.4)
    rose = _m("w_rose", "#9E3552", 0.6)
    sp = [(0.0, 0.15), (-0.035, 0.42), (-0.03, 0.72), (0.03, 0.95), (0.13, 1.06)]
    w = (0.05, 0.06, 0.06, 0.045, 0.0)
    blade("Blade", [(x, z, ww, ww * 0.8, 0.012 if ww else 0.002) for (x, z), ww in zip(sp, w)], silver, n=14)
    blade("Core", [(x + 0.004, z, ww * 0.62, ww * 0.42, 0.016 if ww else 0.002) for (x, z), ww in zip(sp[:-1], w[:-1])]
          + [(0.06, 0.99, 0, 0, 0.002)], pink, n=12)
    spike("Barb", -0.06, 0.62, -0.9, 0.09, 0.05, 0.01, silver)
    part("GemRing", "cyl", (0, 0, 0.12), (0.07, 0.07, 0.03), silver, rot=(1.5708, 0, 0), seg=8)
    gem("Gem", 0, 0.12, 0.024, pink, y=0.0)
    for i, a in enumerate((2.1, 2.4, 2.7)):
        spike(f"Feather{i}", 0.03, 0.1, a, 0.11 - i * 0.015, 0.03, 0.008, silver)
    spike("FeatherL", -0.03, 0.1, -2.5, 0.07, 0.03, 0.008, silver)
    grip(0.22, 0.015, rose, rings=3, ring_m=silver)
    gem("Pommel", 0, -0.135, 0.022, pink)
    part("PommelCap", "cone", (0, 0, -0.16), (0.03, 0.03, 0.03), silver, rot=(3.1416, 0, 0), seg=6)
    finish("w_moon_crescent", 0.13, 1.06)


# ------------------------------------------------------------------ 5. Asa Real
def build_w_royal_wings():
    steel = _m("w_navy_steel", "#3E5683", 0.3, 0.8)
    core = _m("w_magenta", "#E4386F", 0.3, 0.2, glow=0.8)
    gold = _m("w_gold", "#EDB735", 0.3, 1.0)
    ivory = _m("w_ivory", "#F3EFE6", 0.5)
    keys = [(0, 0.16, 0.06, 0.06, 0.014), (0, 0.5, 0.075, 0.075, 0.016), (0, 0.95, 0.07, 0.07, 0.015),
            (0, 1.15, 0.05, 0.05, 0.013), (0, 1.3, 0.0, 0.0, 0.002)]
    blade("Blade", keys, steel, n=8)
    blade("Core", [(0, 0.16, 0.045, 0.045, 0.018), (0, 0.45, 0.04, 0.04, 0.02), (0, 0.85, 0.026, 0.026, 0.019),
                   (0, 1.12, 0.0, 0.0, 0.004)], core, n=8)
    part("GuardCenter", "cube", (0, 0, 0.13), (0.1, 0.05, 0.07), gold)
    gem("Gem", 0, 0.13, 0.03, core, y=0.0)
    for s in (1, -1):
        blade(f"Wing{s}", [(s * 0.04, 0.12, 0.035, 0.035, 0.014), (s * 0.13, 0.17, 0.03, 0.03, 0.012),
                           (s * 0.2, 0.28, 0.015, 0.015, 0.01), (s * 0.21, 0.36, 0, 0, 0.002)], gold, n=8)
        spike(f"WingSpur{s}", s * 0.1, 0.18, s * 0.5, 0.12, 0.035, 0.01, gold)
        spike(f"Low{s}", s * 0.04, 0.1, s * 2.2, 0.13, 0.05, 0.012, ivory)
        spike(f"LowGold{s}", s * 0.03, 0.09, s * 2.75, 0.08, 0.03, 0.01, gold)
    grip(0.22, 0.018, steel, rings=2, ring_m=gold)
    part("Pommel", "ico", (0, 0, -0.13), (0.045, 0.04, 0.04), gold, sub=1)
    spike("PommelSpike", 0, -0.14, 3.1416, 0.07, 0.025, 0.01, gold)
    finish("w_royal_wings", 0, 1.3)


# ------------------------------------------------------------------ 6. Folha Peçonhenta
def build_w_venom_leaf():
    leafm = _m("w_venom", "#CBD43A", 0.4, 0.1, glow=0.2)
    leaf_d = _m("w_venom_dark", "#8C9A22", 0.5)
    black = _m("w_black", "#1E2026", 0.6)
    keys = [(0, 0.12, 0.025, 0.025, 0.012), (0.01, 0.4, 0.045, 0.04, 0.014), (0.025, 0.7, 0.05, 0.04, 0.014),
            (0.02, 0.92, 0.03, 0.025, 0.011), (0.0, 1.06, 0.0, 0.0, 0.002)]
    blade("Blade", keys, leafm, n=12)
    blade("Vein", [(0.002, 0.12, 0.006, 0.006, 0.016), (0.012, 0.7, 0.006, 0.006, 0.016), (0.012, 0.95, 0, 0, 0.004)],
          leaf_d, n=6)
    for i, (z, s) in enumerate(((0.3, -1), (0.42, 1), (0.55, -1), (0.66, 1), (0.78, -1), (0.86, 1), (0.48, -1))):
        x = 0.01 + 0.012 + s * 0.042
        spike(f"Leaf{i}", x, z, s * 0.75, 0.09, 0.05, 0.009, leafm)
    grip(0.18, 0.014, black)
    part("Guard", "cube", (0, 0, 0.1), (0.04, 0.03, 0.025), leaf_d)
    gem("Pommel", 0, -0.115, 0.026, leaf_d)
    spike("PommelTip", 0, -0.13, 3.1416, 0.03, 0.02, 0.008, leaf_d)
    finish("w_venom_leaf", 0, 1.06)


# ------------------------------------------------------------------ 7. Lâmina Neon
def build_w_neon_edge():
    body = _m("w_violet", "#2E2244", 0.4, 0.5)
    neon = _m("w_neon", "#30DCEB", 0.2, 0.0, glow=2.0)
    white = _m("w_white", "#ECEDF0", 0.45)
    keys_b = [(0, 0.16, 0.038, 0.0, 0.013), (0, 0.9, 0.038, 0.0, 0.013), (0, 1.02, 0.03, 0.0, 0.011),
              (0, 1.16, 0.0, 0.0, 0.003)]
    blade("Blade", keys_b, body, n=len(keys_b))
    blade("Edge", [(0, 0.16, 0.0, 0.022, 0.008), (0, 1.0, 0.0, 0.022, 0.008), (0, 1.16, 0.0, 0.0, 0.002)], neon, n=3)
    for i, z in enumerate((0.3, 0.55, 0.8)):
        part(f"Line{i}", "cube", (-0.016, 0, z), (0.006, 0.03, 0.12), neon)
    part("Guard", "cube", (-0.004, 0, 0.115), (0.09, 0.05, 0.06), white)
    part("GuardFin", "cube", (0.04, 0, 0.09), (0.04, 0.04, 0.08), white, rot=(0, 0.5, 0))
    part("GuardLight", "cube", (-0.004, 0, 0.115), (0.04, 0.054, 0.012), neon)
    grip(0.2, 0.017, body, rings=3, ring_m=neon, seg=6)
    part("PommelBlock", "cube", (0.0, 0, -0.12), (0.05, 0.045, 0.045), white)
    for i, (x, z) in enumerate(((0.035, -0.14), (0.055, -0.1), (0.055, -0.04))):
        part(f"Hook{i}", "cube", (x, 0, z), (0.035 if i == 0 else 0.018, 0.035, 0.018 if i == 0 else 0.06), white)
    finish("w_neon_edge", 0, 1.16)


# ------------------------------------------------------------------ 8. Cutelo do Titã
def build_w_titan_cleaver():
    silver = _m("w_silver", "#C8CDD6", 0.3, 0.9)
    violet = _m("w_lilac", "#A57FD0", 0.45, 0.2)
    green = _m("w_jade", "#3E6E59", 0.5, 0.4)
    navy = _m("w_navy", "#283450", 0.6)
    pearl = _m("w_pearl", "#F4DDF6", 0.2, 0.0, glow=0.6)
    blade("Blade", [(0.01, 0.15, 0.08, 0.08, 0.02), (0.01, 0.92, 0.08, 0.08, 0.02), (0.01, 0.98, 0.08, 0.06, 0.019),
                    (0.01, 1.06, 0.08, 0.0, 0.016)], silver, n=4, ridge=0.0)
    part("Panel", "cube", (-0.04, 0, 0.32), (0.07, 0.044, 0.3), violet)
    part("PanelCut", "cube", (-0.05, 0, 0.5), (0.05, 0.044, 0.08), violet, rot=(0, 0.6, 0))
    gem("Pearl", 0.005, 0.28, 0.026, pearl, y=0.0)
    for i in range(3):
        part(f"Rivet{i}", "cube", (0.055, 0, 0.3 + i * 0.07), (0.012, 0.046, 0.012), navy)
    part("Crack", "cube", (0.02, 0, 0.7), (0.006, 0.044, 0.25), navy, rot=(0, 0.2, 0))
    part("Guard", "cube", (0.0, 0, 0.12), (0.2, 0.06, 0.06), green)
    part("GuardSide", "cube", (-0.08, 0, 0.085), (0.06, 0.055, 0.06), green, rot=(0, 0.6, 0))
    grip(0.24, 0.017, navy, rings=4, ring_m=green, z0=-0.02)
    part("Pommel", "cube", (0, 0, -0.16), (0.04, 0.04, 0.04), green, rot=(0, 0.785, 0))
    finish("w_titan_cleaver", 0.05, 1.04)


# ------------------------------------------------------------------ 9. Presa de Âmbar
def build_w_amber_fang():
    amber = _m("w_amber", "#F2A443", 0.3, 0.2, glow=0.5)
    silver = _m("w_silver", "#C8CDD6", 0.3, 0.9)
    keys = [(0, 0.14, 0.022, 0.022, 0.009), (-0.012, 0.5, 0.026, 0.024, 0.01), (-0.01, 0.85, 0.022, 0.02, 0.009),
            (0.02, 1.08, 0.012, 0.01, 0.006), (0.05, 1.18, 0.0, 0.0, 0.002)]
    blade("Blade", keys, amber, n=12)
    part("Guard", "cube", (0, 0, 0.11), (0.06, 0.035, 0.05), silver)
    for i, (z, ln) in enumerate(((0.1, 0.1), (0.14, 0.08), (0.18, 0.06))):
        _sym(lambda s, z=z, ln=ln, i=i: spike(f"Wing{i}{s}", s * 0.025, z, s * (0.9 - i * 0.2), ln, 0.03, 0.009, silver))
    grip(0.22, 0.013, silver, rings=3, ring_m=silver)
    for i, z in enumerate((-0.02, -0.09)):
        _sym(lambda s, z=z, i=i: spike(f"GripSpike{i}{s}", s * 0.012, z, s * 2.3, 0.05, 0.025, 0.007, silver))
    spike("PommelHook", 0, -0.11, 2.8, 0.08, 0.03, 0.009, silver)
    spike("PommelHook2", 0, -0.11, -2.9, 0.05, 0.025, 0.008, silver)
    finish("w_amber_fang", 0.05, 1.18)


# ------------------------------------------------------------------ 10. Espinha Coral
def build_w_coral_spine():
    magenta = _m("w_coral", "#DA3C9C", 0.35, 0.2, glow=0.4)
    gold = _m("w_gold", "#EDB735", 0.3, 1.0)
    teal = _m("w_teal", "#2FA9A6", 0.35, 0.5)
    blade("Shaft", [(0, 0.15, 0.022, 0.022, 0.012), (0, 0.72, 0.026, 0.026, 0.013), (0, 0.8, 0.026, 0.026, 0.013)],
          gold, n=3)
    blade("Crest", [(0, 0.72, 0.03, 0.03, 0.014), (-0.01, 0.92, 0.05, 0.03, 0.015), (-0.03, 1.08, 0.04, 0.02, 0.012),
                    (-0.06, 1.16, 0.0, 0.0, 0.002)], magenta, n=8)
    for i, z in enumerate((0.78, 0.86, 0.94, 1.02)):
        spike(f"Fin{i}", -0.05, z, -1.2 - i * 0.05, 0.11 - i * 0.012, 0.05, 0.011, magenta)
    spike("FinR", 0.025, 0.85, 1.0, 0.05, 0.04, 0.01, magenta)
    for i, z in enumerate((0.3, 0.5)):
        _sym(lambda s, z=z, i=i: spike(f"Barb{i}{s}", s * 0.022, z, s * 1.0, 0.04, 0.03, 0.008, teal))
    part("Guard", "cube", (0, 0, 0.12), (0.06, 0.04, 0.05), teal)
    for i, a in enumerate((1.0, 1.6, 2.2)):
        _sym(lambda s, a=a, i=i: spike(f"GuardSpike{i}{s}", s * 0.025, 0.12, s * a, 0.1 - i * 0.015, 0.03, 0.009, teal))
    grip(0.2, 0.014, teal, rings=4, ring_m=gold)
    tube("Loop", [(0, 0, -0.1), (0.03, 0, -0.13), (0.015, 0, -0.17), (-0.02, 0, -0.16), (-0.02, 0, -0.12)], 0.008, teal)
    finish("w_coral_spine", -0.06, 1.16)


# ------------------------------------------------------------------ 11. Asa de Marfim
def build_w_ivory_wing():
    rim = _m("w_graphite", "#45474E", 0.4, 0.7)
    white = _m("w_ivory", "#F3F2EE", 0.45)
    silver = _m("w_silver", "#C8CDD6", 0.3, 0.9)
    keys = [(0, 0.17, 0.065, 0.065, 0.013), (0, 0.65, 0.085, 0.085, 0.015), (0, 1.02, 0.08, 0.08, 0.014),
            (0, 1.3, 0.0, 0.0, 0.002)]
    blade("Rim", keys, rim, n=8)
    blade("Face", [(0, 0.17, 0.054, 0.054, 0.017), (0, 0.65, 0.073, 0.073, 0.019), (0, 1.02, 0.068, 0.068, 0.018),
                   (0, 1.26, 0.0, 0.0, 0.006)], white, n=8)
    blade("Fuller", [(0, 0.22, 0.008, 0.008, 0.021), (0, 0.85, 0.008, 0.008, 0.021), (0, 0.95, 0, 0, 0.012)], silver, n=3)
    part("Guard", "cube", (0, 0, 0.14), (0.16, 0.05, 0.05), silver)
    for i, (a, ln) in enumerate(((1.9, 0.16), (2.25, 0.14), (2.6, 0.11), (2.9, 0.08))):
        _sym(lambda s, a=a, ln=ln, i=i: spike(f"Feather{i}{s}", s * (0.03 + i * 0.008), 0.13, s * a, ln, 0.04, 0.011,
                                              white if i % 2 == 0 else silver))
    grip(0.22, 0.017, white, rings=4, ring_m=silver)
    gem("Pommel", 0, -0.13, 0.03, silver)
    spike("PommelSpike", 0, -0.15, 3.1416, 0.06, 0.025, 0.01, silver)
    finish("w_ivory_wing", 0, 1.3)


# ------------------------------------------------------------------ 12. Garra Escarlate
def build_w_scarlet_talon():
    red = _m("w_scarlet", "#EA5A2E", 0.35, 0.3, glow=0.5)
    teal = _m("w_teal", "#2FA9A6", 0.35, 0.5)
    dark = _m("w_maroon", "#5A1E22", 0.6)
    sp = [(0.0, 0.15), (0.04, 0.42), (0.1, 0.7), (0.08, 0.95), (-0.04, 1.14)]
    ww = (0.05, 0.075, 0.08, 0.05, 0.0)
    blade("Blade", [(x, z, w * 0.55, w, 0.014 if w else 0.002) for (x, z), w in zip(sp, ww)], red, n=14)
    blade("Back", [(x - 0.03 - (0.01 if i in (2, 3) else 0), z, w * 0.35, 0.0, 0.012 if w else 0.002)
                   for i, ((x, z), w) in enumerate(zip(sp, ww))], teal, n=14)
    for i, (x, z, a) in enumerate(((0.01, 0.5, -0.8), (0.04, 0.72, -0.6), (0.02, 0.9, -0.3))):
        spike(f"Spine{i}", x, z, a, 0.08, 0.05, 0.01, teal)
    tube("Rib", [(0.05, 0, 0.3), (0.09, 0, 0.5), (0.11, 0, 0.66)], 0.011, dark)
    part("Guard", "cube", (0.01, 0, 0.12), (0.09, 0.045, 0.05), teal)
    spike("Claw", 0.04, 0.11, 2.4, 0.12, 0.04, 0.012, teal)
    spike("ClawL", -0.03, 0.12, -1.2, 0.08, 0.035, 0.01, red)
    grip(0.2, 0.016, dark, rings=3, ring_m=red)
    spike("Pommel", 0, -0.1, 3.0, 0.07, 0.035, 0.012, red)
    finish("w_scarlet_talon", -0.04, 1.14)


# ------------------------------------------------------------------ 13. Junco Carmesim
def build_w_crimson_reed():
    red = _m("w_crimson", "#DC4C5C", 0.3, 0.4, glow=0.3)
    teal = _m("w_sea", "#63B8B1", 0.3, 0.6)
    grey = _m("w_slate", "#5D6A72", 0.6)
    sp = [(0.0, 0.13), (0.004, 0.5), (0.018, 0.9), (0.04, 1.18)]
    blade("Edge", [(x, z, 0.0, w, 0.007) for (x, z), w in zip(sp, (0.014, 0.013, 0.012, 0.0))], red, n=12)
    blade("Back", [(x, z, w, 0.0, 0.009) for (x, z), w in zip(sp, (0.012, 0.011, 0.009, 0.0))], teal, n=12)
    part("Tsuba", "cyl", (0, 0, 0.11), (0.07, 0.05, 0.016), teal, seg=8)
    part("Habaki", "cube", (0, 0, 0.135), (0.032, 0.024, 0.03), teal)
    grip(0.24, 0.014, grey, rings=6, ring_m=teal, z0=-0.02)
    part("Kashira", "cyl", (0, 0, -0.145), (0.032, 0.032, 0.02), teal, seg=8)
    gem("Bead", 0, 0.06, 0.012, red, y=0.0)
    finish("w_crimson_reed", 0.04, 1.18)


# ------------------------------------------------------------------ 14. Foice Pálida
def build_w_pale_crescent():
    pale = _m("w_pale", "#DEE3EC", 0.3, 0.5)
    frost = _m("w_frostblue", "#AFC0D8", 0.35, 0.4)
    grey = _m("w_grey", "#8C939C", 0.35, 0.8)
    sp = [(0.0, 0.14), (0.02, 0.36), (-0.03, 0.55), (-0.16, 0.66), (-0.33, 0.62)]
    ww = (0.05, 0.1, 0.11, 0.07, 0.0)
    blade("Blade", [(x, z, w * 0.25, w, 0.015 if w else 0.002) for (x, z), w in zip(sp, ww)], pale, n=14)
    blade("Back", [(x, z, w * 0.25 + 0.012, 0.0, 0.01 if w else 0.002) for (x, z), w in zip(sp, ww)], frost, n=14)
    for i, (x, z, a, ln) in enumerate(((0.07, 0.62, 0.6, 0.07), (0.0, 0.73, 0.2, 0.06), (-0.12, 0.76, -0.4, 0.05))):
        spike(f"Notch{i}", x, z, a, ln, 0.05, 0.01, pale)
    part("Collar", "cube", (0, 0, 0.12), (0.07, 0.04, 0.04), grey)
    grip(0.19, 0.016, grey)
    # guarda em D: alça retangular ligando a base da lâmina ao pomo
    part("LoopTop", "cube", (0.055, 0, 0.11), (0.07, 0.028, 0.022), grey)
    part("LoopSide", "cube", (0.085, 0, 0.0), (0.022, 0.028, 0.22), grey)
    part("LoopBot", "cube", (0.045, 0, -0.105), (0.1, 0.028, 0.022), grey)
    part("Pommel", "cube", (0, 0, -0.105), (0.04, 0.036, 0.03), grey)
    finish("w_pale_crescent", -0.33, 0.62)


# ------------------------------------------------------------------ 15. Chama Rosada
def build_w_rose_flame():
    pink = _m("w_rosefire", "#EC4C9E", 0.3, 0.2, glow=0.6)
    peach = _m("w_peach", "#FF9C8A", 0.35, 0.1, glow=0.4)
    plum = _m("w_plum", "#6E2C72", 0.6)
    cyan = _m("w_cyan", "#55DDF5", 0.2, 0.3, glow=1.2)
    sp = [(0.0, 0.15), (-0.01, 0.4), (0.01, 0.65), (0.05, 0.88), (0.12, 1.06)]
    ww = (0.035, 0.05, 0.06, 0.045, 0.0)
    blade("Blade", [(x, z, w, w * 0.6, 0.013 if w else 0.002) for (x, z), w in zip(sp, ww)], pink, n=14)
    blade("Edge", [(x + 0.004, z, 0.0, w * 0.6 + 0.008, 0.007 if w else 0.002) for (x, z), w in zip(sp, ww)],
          peach, n=14)
    for i, (x, z, a, ln) in enumerate(((-0.04, 0.42, -0.5, 0.11), (-0.04, 0.6, -0.35, 0.12),
                                         (-0.01, 0.8, -0.2, 0.12), (0.03, 0.95, 0.0, 0.1))):
        spike(f"Flame{i}", x, z, a, ln, 0.06, 0.011, pink)
    part("Guard", "cube", (0, 0, 0.12), (0.09, 0.04, 0.035), peach)
    part("GemRing", "cyl", (0, 0, 0.09), (0.065, 0.065, 0.028), cyan, rot=(1.5708, 0, 0), seg=8)
    gem("Gem", 0, 0.09, 0.02, peach)
    _sym(lambda s: spike(f"GuardHorn{s}", s * 0.04, 0.12, s * 1.2, 0.05, 0.03, 0.009, cyan))
    grip(0.17, 0.016, plum, rings=4, ring_m=peach, z0=-0.02)
    spike("Pommel", 0, -0.11, 3.1416, 0.05, 0.035, 0.012, cyan)
    finish("w_rose_flame", 0.12, 1.06)


for _f in (build_w_azure_edge, build_w_thorn_root, build_w_crystal_frost, build_w_moon_crescent,
           build_w_royal_wings, build_w_venom_leaf, build_w_neon_edge, build_w_titan_cleaver, build_w_amber_fang,
           build_w_coral_spine, build_w_ivory_wing, build_w_scarlet_talon, build_w_crimson_reed,
           build_w_pale_crescent, build_w_rose_flame):
    WEAPONS.append((_f.__name__[len("build_"):], _f))
