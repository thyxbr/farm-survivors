# Espadas do jogo (GLB w_<id>.glb). Carregado por build_assets.py via exec (usa mat, part, empty,
# join_all, export, hexc). Convenção: centro do cabo na origem, lâmina subindo em +Z, largura em X,
# espessura em Y. O empty "Tip" marca a ponta. knight_look.gd instancia o GLB quando o item tem "model".
#
# Visual: cor por vértice (atributo "Col", degradê ao longo e através da lâmina), sombreado suave com
# quina central e fio marcados, espinhos que nascem do próprio fio e contorno escuro (casca invertida,
# material "w_outline" com backface culling). Os materiais só definem brilho/metal/emissão.
import math
from mathutils import Vector

WEAPONS = []   # (nome, builder), registrados em BUILDERS


# ------------------------------------------------------------------ cor
def _rgb(c):
    return hexc(c) if isinstance(c, str) else tuple(c[:3])


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _grad(stops, t):
    """stops: "#hex" ou [(t, "#hex"), ...] -> cor linear em t."""
    if stops is None:
        return None
    if isinstance(stops, (str, tuple)):
        return _rgb(stops)
    s = [(a, _rgb(c)) for a, c in stops]
    if t <= s[0][0]:
        return s[0][1]
    for (a, ca), (b, cb) in zip(s, s[1:]):
        if t <= b:
            return _mix(ca, cb, (t - a) / max(b - a, 1e-6))
    return s[-1][1]


def _m(name, hx, rough=0.4, metal=0.0, glow=0.0):
    """Material que pega a cor do atributo "Col"; hx é a cor de fallback das peças lisas."""
    c = hexc(hx)
    # metal cheio fica escuro onde não há o que refletir (fundo liso, interior): no máximo 0,55
    m = mat(name, c, rough, min(metal, 0.55), emit=c if glow > 0 else None, strength=glow)
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    vc = next((n for n in nt.nodes if n.type == 'VERTEX_COLOR'), None) or nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    m["hex"] = hx
    return m


def _flat(ob, c):
    me = ob.data
    a = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    rgb = _rgb(c)
    for i in range(len(me.vertices)):
        a.data[i].color = (*rgb, 1.0)
    return ob


def P(name, kind, loc, size, material, c=None, smooth=None, **kw):
    """part() já pintado (c ou a cor do material). Cilindros e esferas saem suavizados."""
    if smooth is None:
        smooth = kind in ("cyl", "sphere")
    ob = part(name, kind, loc, size, material, smooth=smooth, **kw)
    return _flat(ob, c or material["hex"])


def _hullc(name, pts, cols, material):
    bm = bmesh.new()
    cl = bm.verts.layers.float_color.new("Col")
    for p, c in zip(pts, cols):
        v = bm.verts.new(p)
        v[cl] = (*_rgb(c), 1.0)
    bmesh.ops.convex_hull(bm, input=list(bm.verts))
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


# ------------------------------------------------------------------ lâmina
def _cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def _resample(keys, n):
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


class _St:
    __slots__ = ("p", "nl", "tan", "wl", "wr", "th", "t", "cl", "cr", "cc")


def blade(name, keys, material, n=16, grad=None, edge=None, edge_l=None, edge_r=None, band=0.5, rim=None,
          ridge=None, sharp_ridge=True):
    """Lâmina de seção lenticular seguindo uma espinha curva no plano XZ.
    keys: (x, z, largura_esq, largura_dir, meia_espessura); 'esq' = lado -X quando a espinha sobe.
    Cores: grad = cor do miolo ao longo da lâmina (t 0 = base, 1 = ponta); edge/edge_l/edge_r = cor do fio;
    o miolo vai até 'band' da largura e o fio fica puro a partir de 'rim'; ridge = cor da quina central.
    Devolve a lista de estações (para fin())."""
    print("PART", name, "blade", flush=True)
    st = _resample(keys, n) if n > len(keys) else [list(k) for k in keys]
    core = grad if grad is not None else material["hex"]
    el, er = edge_l or edge or core, edge_r or edge or core
    rim = max(rim if rim is not None else min(band + 0.3, 1.0), band)
    fr = [band] + ([rim] if rim < 0.999 and rim > band + 1e-3 else [])   # frações internas por lado
    bm = bmesh.new()
    cl = bm.verts.layers.float_color.new("Col")
    rings, info = [], []
    N = len(st)
    for i, (x, z, wl, wr, th) in enumerate(st):
        t = i / (N - 1)
        a, b = st[max(i - 1, 0)], st[min(i + 1, N - 1)]
        tg = Vector((b[0] - a[0], b[1] - a[1]))
        tg = tg.normalized() if tg.length > 1e-6 else Vector((0, 1))
        nl = Vector((-tg.y, tg.x))
        p = Vector((x, z))
        cc, cL, cR = _grad(core, t), _grad(el, t), _grad(er, t)
        cg = _grad(ridge, t) or cc

        def col(f, ce):
            if f <= band:
                return _mix(cg, cc, f / band) if band > 0 else cc
            if f >= rim:
                return ce
            return _mix(cc, ce, (f - band) / (rim - band))

        def vert(side, f, y):
            w = wl if side > 0 else wr
            q = p + nl * (side * w * f)
            v = bm.verts.new((q.x, y, q.y))
            v[cl] = (*col(f, cL if side > 0 else cR), 1.0)
            return v

        yf = lambda f: th * (1 - f * f)
        ring = [vert(1, 1.0, 0.0)]
        ring += [vert(1, f, -yf(f)) for f in reversed(fr)]
        ring.append(vert(1, 0.0, -th))
        ring += [vert(-1, f, -yf(f)) for f in fr]
        ring.append(vert(-1, 1.0, 0.0))
        ring += [vert(-1, f, yf(f)) for f in reversed(fr)]
        ring.append(vert(1, 0.0, th))
        ring += [vert(1, f, yf(f)) for f in fr]
        rings.append(ring)
        s = _St()
        s.p, s.nl, s.tan, s.wl, s.wr, s.th, s.t, s.cl, s.cr, s.cc = p, nl, tg, wl, wr, th, t, cL, cR, cc
        info.append(s)
    m = len(rings[0])
    k = len(fr)
    sharp = {0, k + 1 + k + 1}                       # fios L e R
    if sharp_ridge:
        sharp |= {k + 1, m - k - 1}                  # quina central (frente e trás)
    for i in range(N - 1):
        A, B = rings[i], rings[i + 1]
        for j in range(m):
            j2 = (j + 1) % m
            try:
                bm.faces.new((A[j], A[j2], B[j2], B[j]))
            except ValueError:
                pass
            if j in sharp:
                e = bm.edges.get((A[j], B[j]))
                if e:
                    e.smooth = False
    for r in (list(reversed(rings[0])), rings[-1]):    # tampas: base para -Z, ponta para +Z
        try:
            f = bm.faces.new(r)
            for e in f.edges:
                e.smooth = False
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0003, edges=bm.edges)
    # sem recalc_face_normals: a ordem do anel já dá normais para fora, e o recalc erra em lâmina fina
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return info


def fin(name, bl, t0, t1, side, length, ang=0.4, material=None, tipcol=None, depth=0.45, thick=0.9):
    """Espinho que nasce do fio da lâmina entre t0 e t1 (side +1 = fio esquerdo, -1 = direito).
    A base coincide com o fio e entra na lâmina, então ele sai do próprio corpo dela.
    ang inclina a ponta para a ponta da lâmina (positivo) ou para o cabo (negativo)."""
    N = len(bl)
    i0 = max(0, min(N - 2, round(t0 * (N - 1))))
    i1 = max(i0 + 1, min(N - 1, round(t1 * (N - 1))))
    pts, cols = [], []
    E = []
    for i in range(i0, i1 + 1):
        s = bl[i]
        w = s.wl if side > 0 else s.wr
        ce = s.cl if side > 0 else s.cr
        e = s.p + s.nl * (side * w)
        q = s.p + s.nl * (side * w * (1 - depth))
        f = 1 - depth
        y = s.th * (1 - f * f) * thick
        E.append(e)
        pts += [(e.x, 0, e.y), (q.x, -y, q.y), (q.x, y, q.y)]
        cols += [ce, _mix(ce, s.cc, 0.5), _mix(ce, s.cc, 0.5)]
    s = bl[(i0 + i1) // 2]
    d = s.nl * side * math.cos(ang) + s.tan * math.sin(ang)
    mid = (E[0] + E[-1]) / 2
    tip = mid + d * length
    pts.append((tip.x, 0, tip.y))
    cols.append(tipcol or (bl[i0].cl if side > 0 else bl[i0].cr))
    return _hullc(name, pts, cols, material)


def prong(name, pts, w0, th0, material, grad=None, edge=None, band=0.4, rim=1.0, ridge=None, n=7, w1=0.0):
    """Chifre/pena/asa curva e afinando: lâmina pequena ao longo de pts [(x, z)]; começa dentro da peça-mãe."""
    L = len(pts) - 1
    keys = []
    for i, (x, z) in enumerate(pts):
        u = i / L
        w = w0 + (w1 - w0) * u
        keys.append((x, z, w / 2, w / 2, max(th0 * (1 - u * 0.85), 0.0015)))
    return blade(name, keys, material, n=max(n, len(pts)), grad=grad, edge=edge, band=band, rim=rim, ridge=ridge)


def diamond(name, x, z, w, h, th, material, c=None, ctip=None):
    pts = [(x - w / 2, 0, z), (x + w / 2, 0, z), (x, 0, z - h / 2), (x, 0, z + h / 2), (x, -th, z), (x, th, z)]
    cc = c or material["hex"]
    cols = [cc, cc, cc, cc, ctip or cc, ctip or cc]
    return _hullc(name, pts, cols, material)


def tube(name, pts, r, material, c=None, seg=6, r_end=None):
    """Cilindros ligando pontos 3D, com esferas nas juntas (cipós, alças)."""
    c = c or material["hex"]
    n = len(pts) - 1
    for i in range(n):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        rr = r if r_end is None else r + (r_end - r) * (i + 0.5) / n
        dv = b - a
        rot = Vector((0, 0, 1)).rotation_difference(dv.normalized()).to_euler()
        P(f"{name}{i}", "cyl", tuple((a + b) / 2), (rr * 2, rr * 2, dv.length), material, c, rot=tuple(rot), seg=seg)
        if i < n - 1:
            P(f"{name}J{i}", "sphere", tuple(b), (rr * 2,) * 3, material, c, seg=seg + 1)


def grip(z0, z1, r, m, c=None, rings=0, ring_m=None, ring_c=None, seg=10):
    """Cabo de z0 (embaixo) a z1 (em cima), com anéis/tiras opcionais."""
    L = z1 - z0
    P("Grip", "cyl", (0, 0, (z0 + z1) / 2), (r * 2, r * 2, L), m, c, seg=seg)
    for i in range(rings):
        z = z0 + L * (i + 0.5) / rings
        P(f"GripRing{i}", "cyl", (0, 0, z), (r * 2.3, r * 2.3, L / rings * 0.38), ring_m or m, ring_c, seg=seg)


def gem(name, x, z, r, m, c=None, y=0.0):
    return P(name, "ico", (x, y, z), (r * 2, r * 1.5, r * 2), m, c, sub=1)


_OUTLINE = None


def _outline(ob, width):
    global _OUTLINE
    if _OUTLINE is None or _OUTLINE.name not in bpy.data.materials:
        _OUTLINE = _m("w_outline", "#141418", 1.0)
        _OUTLINE.use_backface_culling = True
    me = ob.data.copy()
    me.name = "Outline"
    o = bpy.data.objects.new("Outline", me)
    coll.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    cl = bm.verts.layers.float_color.get("Col")
    for v in bm.verts:
        v.co += v.normal * width
        if cl:
            c = v[cl]
            v[cl] = (c[0] * 0.12, c[1] * 0.12, c[2] * 0.12, 1.0)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
        f.material_index = 0
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(_OUTLINE)
    _active_col(me)
    return o


def _active_col(me):
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.find("Col")


def _join(objs, name):
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                       selected_editable_objects=objs):
            bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    _active_col(objs[0].data)
    return objs[0]


def finish(asset, tip_x, tip_z, outline=0.0048):
    """Junta as peças POR MATERIAL (um objeto = uma superfície): o exportador glTF do Blender 5.2 só preenche
    o COLOR_0 da primeira superfície de uma malha com vários materiais; as outras saem brancas."""
    groups = {}
    for o in list(coll.all_objects):
        if o.type == 'MESH':
            m = o.data.materials[0] if o.data.materials else None
            if "Col" not in o.data.color_attributes:
                _flat(o, m["hex"] if m and "hex" in m else "#808080")
            _active_col(o.data)    # sem isso a junção perde a cor quando a 1ª peça é uma lâmina
            groups.setdefault(m.name if m else "", []).append(o)
    parts = [_join(objs, f"Weapon_{k}") for k, objs in enumerate(groups.values())]
    if outline:
        _join([_outline(w, outline) for w in parts], "Outline")
    empty("Tip", (tip_x, 0, tip_z))
    export(asset)


def _sym(fn):
    fn(1)
    fn(-1)


# ================================================================== armas
# 1. Gume Celeste (arma inicial) — aço com fio largo azul-celeste, colar angular, cabo longo nervurado
def build_w_azure_edge():
    steel = _m("w_steel", "#AEB8C4", 0.25, 0.85)
    cyan = _m("w_cyan", "#55D2F2", 0.15, 0.3, glow=0.5)
    dark = _m("w_black", "#24272D", 0.6)
    grey = _m("w_grey", "#9AA3AD", 0.3, 0.85)
    sp = [(0.0, 0.17), (0.003, 0.45), (-0.004, 0.75), (-0.018, 0.97)]
    tipk = (-0.034, 1.07, 0.0, 0.0, 0.002)
    blade("Back", [(x, z, w, 0.0, 0.013) for (x, z), w in zip(sp, (0.02, 0.02, 0.018, 0.014))] + [tipk], steel,
          n=16, grad=[(0, "#7D8894"), (1, "#B9C3CE")], edge_l="#3A414A", band=0.45, rim=0.9, ridge="#DCE3EA")
    blade("Edge", [(x, z, 0.0, w, 0.009) for (x, z), w in zip(sp, (0.028, 0.028, 0.026, 0.022))] + [tipk], cyan,
          n=16, grad=[(0, "#1E9FD6"), (1, "#3CC4EE")], edge_r="#BFF3FF", band=0.15, rim=0.95)
    for i in range(3):
        P(f"Slash{i}", "cube", (0.014, 0, 0.23 + i * 0.03), (0.022, 0.02, 0.006), cyan, "#1F6F8C", rot=(0, -0.6, 0))
    # colar angular que desce para a esquerda
    pts, cols = [], []
    for y in (-0.021, 0.021):
        for (x, z), c in (((-0.03, 0.2), "#E3E8EE"), ((0.034, 0.2), "#E3E8EE"), ((0.036, 0.09), "#AAB3BE"),
                          ((-0.006, 0.03), "#7E8792"), ((-0.05, 0.085), "#8F98A3"), ((-0.044, 0.17), "#C6CDD5")):
            pts.append((x, y, z))
            cols.append(c)
    _hullc("Collar", pts, cols, grey)
    P("CollarBand", "cube", (0.0, 0, 0.13), (0.075, 0.046, 0.012), dark, "#3B4048")
    grip(-0.29, 0.05, 0.016, dark, "#262A30", rings=8, ring_m=grey, ring_c="#5E6670")
    P("GripCap", "cyl", (0, 0, 0.035), (0.04, 0.04, 0.03), grey, "#8C959F", seg=8)
    diamond("Pommel", 0, -0.31, 0.045, 0.06, 0.022, grey, "#C5CCD4", "#8C959F")
    finish("w_azure_edge", -0.034, 1.07)


# 2. Espinho da Raiz — espinha de osso com escamas em V, cipós lisos trançados e raízes
def build_w_thorn_root():
    bone = _m("w_bone", "#ECE6DA", 0.5)
    vine = _m("w_vine", "#86664C", 0.8)
    bl = blade("Spine", [(0, 0.06, 0.018, 0.018, 0.016), (0, 0.6, 0.016, 0.016, 0.014), (0, 1.1, 0.006, 0.006, 0.007),
                         (0, 1.17, 0.0, 0.0, 0.002)], bone, n=40, grad=[(0, "#CFC6B6"), (1, "#F5F1EA")],
               edge="#B5AB9A", band=0.4, rim=0.9, ridge="#FFFFFF")
    for i in range(10):
        t = 0.33 + i * 0.062
        for side in (1, -1):
            fin(f"Scale{i}_{side}", bl, t, t + 0.05, side, 0.09 - i * 0.005, 1.05, bone, "#A69B89", depth=0.65)
    tones = ("#B8957A", "#8E6E58")
    for k in range(2):
        pts = []
        for i in range(12):
            z = -0.3 + i * 0.066
            a = k * math.pi + i * 1.2
            rr = 0.028 if z < 0.14 else 0.024
            pts.append((math.cos(a) * rr, math.sin(a) * rr * 1.2, z))
        tube(f"Vine{k}_", pts, 0.019, vine, tones[k], r_end=0.011)
    tube("Curl", [(0.015, 0, 0.38), (0.06, 0, 0.44), (0.1, 0, 0.43), (0.11, 0, 0.38), (0.085, 0, 0.35)], 0.011, vine,
         "#A88A70", r_end=0.006)
    tube("CurlB", [(-0.015, 0, 0.3), (-0.06, 0, 0.27), (-0.07, 0, 0.21), (-0.05, 0, 0.19)], 0.01, vine, "#7B5E4C",
         r_end=0.005)
    P("Core", "cyl", (0, 0, 0.05), (0.036, 0.036, 0.7), vine, "#7A5C48", seg=8)
    for i, a in enumerate((0.4, 2.3, 4.2)):
        tube(f"Root{i}_", [(0, 0, -0.27), (math.cos(a) * 0.035, math.sin(a) * 0.03, -0.32),
                           (math.cos(a) * 0.065, math.sin(a) * 0.04, -0.37)], 0.011, vine, tones[i % 2], r_end=0.004)
    finish("w_thorn_root", 0, 1.17)


# 3. Lâmina de Cristal — cristal ondulado com nós pontudos, guarda fina com setas, cabo longo
def build_w_crystal_frost():
    ice = _m("w_ice", "#A8EDE8", 0.1, 0.1, glow=0.3)
    keys = [(0, 0.13, 0.02, 0.02, 0.012), (0, 0.2, 0.032, 0.032, 0.014), (0, 0.26, 0.04, 0.04, 0.016),
            (0, 0.32, 0.021, 0.021, 0.012), (0, 0.44, 0.034, 0.034, 0.015), (0, 0.52, 0.043, 0.043, 0.017),
            (0, 0.6, 0.023, 0.023, 0.012), (0, 0.72, 0.033, 0.033, 0.014), (0, 0.8, 0.04, 0.04, 0.016),
            (0, 0.87, 0.023, 0.023, 0.012), (0, 1.0, 0.021, 0.021, 0.011), (0, 1.12, 0.0, 0.0, 0.002)]
    blade("Blade", keys, ice, n=len(keys), grad=[(0, "#4FBFB8"), (0.5, "#86E2DC"), (1, "#C6F6F2")],
          edge="#EAFFFD", band=0.3, rim=0.85, ridge="#FFFFFF")
    g = dict(grad=[(0, "#8FDAD5"), (1, "#C9F6F2")], edge="#EFFFFE", band=0.3, rim=0.9)
    _sym(lambda s: prong(f"Guard{s}", [(0, 0.105), (s * 0.12, 0.105), (s * 0.2, 0.105)], 0.026, 0.011, ice, w1=0.012, **g))
    _sym(lambda s: diamond(f"Arrow{s}", s * 0.215, 0.105, 0.06, 0.05, 0.012, ice, "#BDF3EF", "#7ACFCA"))
    for x, h in ((0.05, 0.07), (0.12, 0.06), (0.17, 0.045)):
        _sym(lambda s, x=x, h=h: prong(f"Up{x}{s}", [(s * x, 0.1), (s * (x + 0.006), 0.1 + h * 0.6), (s * (x + 0.012), 0.1 + h)],
                                       0.018, 0.008, ice, **g))
    _sym(lambda s: prong(f"Down{s}", [(s * 0.09, 0.11), (s * 0.1, 0.075), (s * 0.11, 0.055)], 0.016, 0.007, ice, **g))
    grip(-0.24, 0.1, 0.012, ice, "#7CCFC9", rings=2, ring_c="#A8EDE8")
    P("Knob", "sphere", (0, 0, -0.255), (0.04, 0.04, 0.04), ice, "#C9F6F2", seg=10)
    finish("w_crystal_frost", 0, 1.12)


# 4. Crescente Lunar — lâmina larga em crescente, miolo rosa-pêssego, aro de prata, leque de penas na guarda
def build_w_moon_crescent():
    silver = _m("w_silver", "#D5DAE2", 0.25, 0.7)
    pink = _m("w_pink", "#F06A8E", 0.25, 0.1, glow=0.5)
    rose = _m("w_rose", "#7E2A45", 0.55)
    keys = [(0, 0.17, 0.04, 0.034, 0.013), (0.022, 0.4, 0.056, 0.044, 0.015), (0.022, 0.62, 0.058, 0.046, 0.015),
            (-0.012, 0.84, 0.046, 0.036, 0.013), (-0.085, 1.0, 0.0, 0.0, 0.003)]
    bl = blade("Blade", keys, silver, n=20, grad=[(0, "#FF9A5E"), (0.4, "#F5507A"), (0.8, "#E0386C"), (1, "#F2A0B8")],
               edge=[(0, "#9EA7B4"), (1, "#E4E8EE")], band=0.55, rim=0.7, ridge="#FFE6EC")
    for i, (t0, ln, a) in enumerate(((0.06, 0.07, -0.55), (0.16, 0.06, -0.45), (0.27, 0.05, -0.35))):
        fin(f"Barb{i}", bl, t0, t0 + 0.08, 1, ln, a, silver, "#8E97A4")
    fin("BarbR", bl, 0.5, 0.58, -1, 0.04, 0.6, silver, "#C4CBD4")
    sg = dict(grad=[(0, "#EEF1F5"), (1, "#98A2AF")], edge="#C8CED7")
    for k, (th, ln) in enumerate(((0.35, 0.15), (-0.05, 0.15), (-0.45, 0.13), (-0.85, 0.11), (-1.2, 0.09))):
        s = Vector((0.02, 0.12))
        d0, d1 = Vector((math.cos(th + 0.35), math.sin(th + 0.35))), Vector((math.cos(th), math.sin(th)))
        prong(f"FeatherR{k}", [tuple(s), tuple(s + d0 * ln * 0.5), tuple(s + d0 * ln * 0.5 + d1 * ln * 0.5)],
              0.03, 0.009, silver, **sg)
    for k, (th, ln) in enumerate(((2.75, 0.11), (3.25, 0.1), (3.7, 0.08))):
        s = Vector((-0.02, 0.12))
        d = Vector((math.cos(th), math.sin(th)))
        prong(f"FeatherL{k}", [tuple(s), tuple(s + d * ln * 0.5), tuple(s + d * ln)], 0.028, 0.009, silver, **sg)
    diamond("GemFrame", 0, 0.12, 0.07, 0.08, 0.02, silver, "#E6EAF0", "#B9C1CC")
    diamond("Gem", 0, 0.12, 0.045, 0.052, 0.026, pink, "#FF8FB0", "#FFE3EC")
    grip(-0.25, 0.08, 0.014, rose, "#7E2A45", rings=4, ring_m=silver, ring_c="#C8CED7")
    P("PommelBall", "sphere", (0, 0, -0.27), (0.04, 0.04, 0.04), silver, "#D5DAE2", seg=10)
    gem("PommelGem", 0, -0.295, 0.014, pink, "#FF8FB0")
    finish("w_moon_crescent", -0.085, 1.0)


# 5. Asa Real — lâmina azul-aço com núcleo magenta, asas de ouro, lâminas de marfim, coroa no pomo
def build_w_royal_wings():
    steel = _m("w_navy_steel", "#4D6A9E", 0.25, 0.75)
    core = _m("w_magenta", "#E4386F", 0.25, 0.2, glow=0.7)
    gold = _m("w_gold", "#EDB735", 0.25, 1.0)
    ivory = _m("w_ivory", "#F3EFE6", 0.45)
    keys = [(0, 0.24, 0.055, 0.055, 0.014), (0, 0.5, 0.072, 0.072, 0.016), (0, 0.95, 0.068, 0.068, 0.015),
            (0, 1.13, 0.05, 0.05, 0.013), (0, 1.3, 0.0, 0.0, 0.002)]
    blade("Blade", keys, steel, n=14, grad=[(0, "#6F8FC6"), (0.5, "#40598C"), (1, "#7896CC")], edge="#22304C",
          band=0.55, rim=0.88, ridge="#D5E1F7")
    blade("Core", [(0, 0.24, 0.05, 0.05, 0.018), (0, 0.5, 0.042, 0.042, 0.02), (0, 0.85, 0.022, 0.022, 0.019),
                   (0, 1.12, 0.0, 0.0, 0.004)], core, n=10, grad=[(0, "#FF5A86"), (0.6, "#E0306A"), (1, "#7A5AB0")],
          edge="#A42456", band=0.3, rim=0.9, ridge="#FFC2D4")
    gg = dict(grad=[(0, "#FFE48A"), (0.6, "#EDB735"), (1, "#C8861A")], edge="#9A6410")
    P("GuardCenter", "cube", (0, 0, 0.2), (0.12, 0.05, 0.12), gold, "#F2C54A")
    for s in (1, -1):
        prong(f"Wing{s}", [(s * 0.02, 0.2), (s * 0.1, 0.25), (s * 0.18, 0.32), (s * 0.2, 0.43)], 0.11, 0.018, gold,
              n=10, **gg)
        prong(f"WingLow{s}", [(s * 0.02, 0.17), (s * 0.13, 0.15), (s * 0.23, 0.19)], 0.07, 0.014, gold, **gg)
        prong(f"Ivory{s}", [(s * 0.02, 0.16), (s * 0.09, 0.09), (s * 0.18, 0.05)], 0.075, 0.013, ivory,
              grad=[(0, "#FFFFFF"), (1, "#D8D1C2")], edge="#B5AC9A")
        prong(f"GoldTooth{s}", [(s * 0.015, 0.15), (s * 0.03, 0.09), (s * 0.04, 0.05)], 0.026, 0.01, gold, **gg)
    diamond("Gem", 0, 0.2, 0.06, 0.1, 0.034, core, "#FF4F7E", "#FFD0DD")
    grip(-0.27, 0.15, 0.018, steel, "#3F63A8", rings=3, ring_m=gold, ring_c="#EDB735")
    P("Crown", "sphere", (0, 0, -0.29), (0.05, 0.045, 0.045), gold, "#F2C54A", seg=10)
    for k, a in enumerate((-0.6, 0.0, 0.6)):
        prong(f"CrownSpike{k}", [(0, -0.29), (math.sin(a) * 0.03, -0.32), (math.sin(a) * 0.05, -0.36)], 0.022, 0.009,
              gold, **gg)
    finish("w_royal_wings", 0, 1.3)


# 6. Folha Peçonhenta — folha curva com dentes em labareda no lado de trás, cabo preto, bulbo dourado
def build_w_venom_leaf():
    leafm = _m("w_venom", "#CBD43A", 0.3, 0.15, glow=0.2)
    black = _m("w_black", "#1E2026", 0.55)
    keys = [(0, 0.12, 0.028, 0.024, 0.013), (-0.012, 0.36, 0.046, 0.04, 0.015), (0.0, 0.6, 0.05, 0.036, 0.015),
            (0.022, 0.82, 0.036, 0.026, 0.012), (0.032, 0.99, 0.0, 0.0, 0.003)]
    bl = blade("Blade", keys, leafm, n=24, grad=[(0, "#C2CC18"), (0.5, "#E4EA30"), (1, "#F8F488")], edge="#8A9410",
               band=0.4, rim=0.85, ridge="#FBFBB8")
    for i, (t0, ln, a) in enumerate(((0.02, 0.1, 0.55), (0.13, 0.1, 0.6), (0.24, 0.09, 0.65), (0.35, 0.08, 0.7),
                                     (0.47, 0.06, 0.75), (0.6, 0.045, 0.8))):
        fin(f"ToothL{i}", bl, t0, t0 + 0.09, 1, ln, a, leafm, "#E6EC5A")
    for i, (t0, ln) in enumerate(((0.06, 0.06), (0.2, 0.05), (0.7, 0.035))):
        fin(f"ToothR{i}", bl, t0, t0 + 0.08, -1, ln, 0.75, leafm, "#E6EC5A")
    g = dict(grad=[(0, "#9DAA1E"), (1, "#E3E852")], edge="#6F7A16")
    for k, (th, ln) in enumerate(((2.5, 0.08), (2.9, 0.07), (0.6, 0.07), (0.25, 0.06))):
        d = Vector((math.cos(th), math.sin(th)))
        s = Vector((0, 0.11))
        prong(f"GuardLeaf{k}", [tuple(s), tuple(s + d * ln * 0.5 + Vector((0, 0.01))), tuple(s + d * ln + Vector((0, 0.03)))],
              0.035, 0.01, leafm, **g)
    grip(-0.17, 0.11, 0.014, black, "#1E2026")
    P("PommelBulb", "sphere", (0, 0, -0.195), (0.04, 0.04, 0.05), leafm, "#B7B92E", seg=10)
    prong("PommelTip", [(0, -0.21), (0, -0.235), (0, -0.255)], 0.02, 0.008, leafm, grad="#9DAA1E")
    finish("w_venom_leaf", 0.032, 0.99)


# 7. Lâmina Neon — lâmina ciano luminosa com painel violeta e trilhas, guarda mecânica branca, gancho no pomo
def build_w_neon_edge():
    body = _m("w_violet", "#2E2244", 0.35, 0.5)
    neon = _m("w_neon", "#30DCEB", 0.15, 0.0, glow=1.6)
    white = _m("w_white", "#ECEDF0", 0.4)
    keys = [(0, 0.17, 0.042, 0.036, 0.012), (0, 0.9, 0.042, 0.036, 0.012), (0, 1.0, 0.03, 0.03, 0.011),
            (-0.01, 1.16, 0.0, 0.0, 0.002)]
    blade("Blade", keys, neon, n=8, grad=[(0, "#08A8C8"), (1, "#22D2EA")], edge="#8FF2FF", band=0.35, rim=0.9,
          ridge="#9FF3FF")
    blade("Panel", [(-0.006, 0.19, 0.034, 0.022, 0.016), (-0.006, 0.84, 0.034, 0.022, 0.016),
                    (-0.012, 0.98, 0.0, 0.0, 0.006)], body, n=3, grad=[(0, "#2A1D44"), (1, "#4B2F74")],
          edge="#7A4FB0", band=0.6, rim=0.95)
    for i, (z, h) in enumerate(((0.28, 0.1), (0.46, 0.14), (0.66, 0.08))):
        P(f"Trace{i}", "cube", (-0.022, 0, z), (0.004, 0.035, h), neon, "#7FF4FF")
        P(f"TraceH{i}", "cube", (-0.012, 0, z + h / 2), (0.02, 0.035, 0.004), neon, "#7FF4FF")
    # guarda mecânica
    pts, cols = [], []
    for y in (-0.026, 0.026):
        for (x, z), c in (((-0.05, 0.19), "#FFFFFF"), ((0.046, 0.19), "#FFFFFF"), ((0.058, 0.13), "#D9DBE1"),
                          ((0.03, 0.09), "#B5B8C2"), ((-0.04, 0.09), "#C8CBD3"), ((-0.062, 0.14), "#E2E4E9")):
            pts.append((x, y, z))
            cols.append(c)
    _hullc("Guard", pts, cols, white)
    P("GuardLight", "cube", (-0.005, 0, 0.14), (0.05, 0.056, 0.01), neon, "#7FF4FF")
    grip(-0.24, 0.1, 0.016, body, "#241A36", rings=4, ring_m=neon, ring_c="#30DCEB", seg=8)
    P("PommelBlock", "cube", (0.0, 0, -0.26), (0.05, 0.044, 0.05), white, "#E3E5EA")
    P("HookBot", "cube", (0.045, 0, -0.27), (0.05, 0.036, 0.022), white, "#D9DBE1")
    P("HookSide", "cube", (0.068, 0, -0.19), (0.02, 0.036, 0.15), white, "#E8E9ED")
    P("HookTop", "cube", (0.05, 0, -0.115), (0.04, 0.036, 0.018), white, "#D9DBE1")
    P("HookLight", "cube", (0.068, 0, -0.19), (0.022, 0.04, 0.04), neon, "#30DCEB")
    finish("w_neon_edge", -0.01, 1.16)


# 8. Cutelo do Titã — placa de aço com degraus, painel lilás ornamentado com pérola, guarda jade
def build_w_titan_cleaver():
    silver = _m("w_silver", "#C8CDD6", 0.3, 0.85)
    violet = _m("w_lilac", "#A57FD0", 0.4, 0.2)
    green = _m("w_jade", "#3E6E59", 0.45, 0.4)
    navy = _m("w_navy", "#283450", 0.55)
    pearl = _m("w_pearl", "#F4DDF6", 0.15, 0.0, glow=0.5)
    blade("Blade", [(0.012, 0.16, 0.082, 0.082, 0.02), (0.012, 0.9, 0.082, 0.082, 0.02), (0.012, 0.97, 0.082, 0.06, 0.019),
                    (0.012, 1.06, 0.082, 0.0, 0.016)], silver, n=4, grad=[(0, "#AEB4BE"), (1, "#E1E5EB")],
          edge="#59606B", band=0.75, rim=0.93, ridge="#F4F6F9")
    blade("Step", [(0.06, 0.45, 0.004, 0.004, 0.022), (0.04, 0.62, 0.004, 0.004, 0.022), (0.04, 0.95, 0.004, 0.004, 0.022)],
          navy, n=3, grad="#5A6272")
    P("Notch", "cube", (0.05, 0, 0.535), (0.03, 0.046, 0.006), navy, "#5A6272", rot=(0, 0.9, 0))
    pts, cols = [], []
    for y in (-0.023, 0.023):
        for (x, z), c in (((-0.07, 0.17), "#7E5BB0"), ((0.0, 0.17), "#8F6BC2"), ((0.0, 0.42), "#B994E0"),
                          ((-0.03, 0.52), "#C9A8EC"), ((-0.07, 0.48), "#A884D6")):
            pts.append((x, y, z))
            cols.append(c)
    _hullc("Panel", pts, cols, violet)
    for i, z in enumerate((0.24, 0.32, 0.4)):
        P(f"Swirl{i}", "cube", (-0.04, 0, z), (0.05, 0.05, 0.006), violet, "#E2CCF7", rot=(0, 0.4 * (-1) ** i, 0))
    gem("Pearl", 0.0, 0.3, 0.026, pearl, "#F7E4FA")
    for i in range(3):
        P(f"Rivet{i}", "cube", (0.06, 0, 0.3 + i * 0.07), (0.012, 0.046, 0.012), navy, "#3A4560")
    pts, cols = [], []
    for y in (-0.03, 0.03):
        for (x, z), c in (((-0.09, 0.17), "#5C9A7E"), ((0.1, 0.17), "#5C9A7E"), ((0.1, 0.12), "#3E6E59"),
                          ((0.02, 0.07), "#2C5242"), ((-0.08, 0.04), "#2C5242"), ((-0.11, 0.1), "#3E6E59")):
            pts.append((x, y, z))
            cols.append(c)
    _hullc("Guard", pts, cols, green)
    P("GuardTrim", "cube", (0.0, 0, 0.17), (0.2, 0.064, 0.01), green, "#9FD3B6")
    grip(-0.3, 0.08, 0.017, navy, "#2E3B5C", rings=5, ring_m=green, ring_c="#3E6E59")
    diamond("Pommel", 0, -0.33, 0.05, 0.06, 0.03, green, "#5C9A7E", "#2C5242")
    finish("w_titan_cleaver", 0.05, 1.04)


# 9. Presa de Âmbar — lâmina âmbar ondulada, guarda de prata em camadas de espinhos, cabo de prata espinhoso
def build_w_amber_fang():
    amber = _m("w_amber", "#F2A443", 0.25, 0.2, glow=0.4)
    silver = _m("w_silver", "#C8CDD6", 0.25, 0.85)
    keys = [(0, 0.2, 0.022, 0.022, 0.009), (-0.012, 0.5, 0.027, 0.024, 0.01), (-0.008, 0.8, 0.024, 0.02, 0.009),
            (0.018, 1.06, 0.013, 0.01, 0.006), (0.05, 1.18, 0.0, 0.0, 0.002)]
    blade("Blade", keys, amber, n=18, grad=[(0, "#E8700E"), (0.6, "#F59A28"), (1, "#FFC060")], edge="#FFD8A0",
          band=0.4, rim=0.85, ridge="#FFF0D8")
    sg = dict(grad=[(0, "#EEF1F5"), (1, "#8D96A3")], edge="#B8C0CA")
    P("Guard", "cube", (0, 0, 0.17), (0.05, 0.03, 0.06), silver, "#D5DAE2")
    for i, (z, ln, a) in enumerate(((0.19, 0.11, 0.55), (0.15, 0.09, 0.25), (0.11, 0.07, -0.1), (0.07, 0.05, -0.4))):
        _sym(lambda s, z=z, ln=ln, a=a, i=i: prong(
            f"Wing{i}{s}", [(s * 0.015, z), (s * (0.015 + ln * 0.5 * math.cos(a)), z + ln * 0.5 * math.sin(a) + 0.01),
                            (s * (0.015 + ln * math.cos(a)), z + ln * math.sin(a) + 0.03)], 0.026, 0.009, silver, **sg))
    grip(-0.24, 0.14, 0.012, silver, "#AEB6C1", rings=4, ring_c="#D5DAE2")
    for i, z in enumerate((0.0, -0.1)):
        _sym(lambda s, z=z, i=i: prong(f"GripSpike{i}{s}", [(s * 0.008, z), (s * 0.03, z - 0.02), (s * 0.045, z - 0.05)],
                                       0.02, 0.007, silver, **sg))
    prong("PommelHook", [(0, -0.23), (0.01, -0.28), (0.035, -0.32), (0.06, -0.31)], 0.026, 0.009, silver, **sg)
    prong("PommelHook2", [(0, -0.23), (-0.02, -0.26), (-0.04, -0.27)], 0.02, 0.008, silver, **sg)
    finish("w_amber_fang", 0.05, 1.18)


# 10. Espinha Coral — crista magenta em espinha de peixe, haste em degradê dourado→laranja, guarda verde-água
def build_w_coral_spine():
    magenta = _m("w_coral", "#DA3C9C", 0.3, 0.2, glow=0.35)
    gold = _m("w_gold", "#EDB735", 0.25, 0.8)
    teal = _m("w_teal", "#2FA9A6", 0.3, 0.5)
    blade("Shaft", [(0, 0.16, 0.02, 0.02, 0.012), (0, 0.45, 0.024, 0.024, 0.013), (0, 0.66, 0.026, 0.026, 0.013)],
          gold, n=8, grad=[(0, "#2FB3AE"), (0.25, "#F0C848"), (0.7, "#F39A3A"), (1, "#EE5A7A")], edge="#B86A1E",
          band=0.4, rim=0.9, ridge="#FFF2C0")
    bl = blade("Crest", [(0, 0.6, 0.03, 0.03, 0.014), (-0.008, 0.82, 0.045, 0.032, 0.015), (-0.02, 1.0, 0.04, 0.022, 0.013),
                         (-0.05, 1.14, 0.0, 0.0, 0.002)], magenta, n=24,
               grad=[(0, "#F04A70"), (0.3, "#D42A90"), (1, "#EE5AB8")], edge="#7A1050", band=0.45, rim=0.9,
               ridge="#FFC7EA")
    for i, (t0, ln, a) in enumerate(((0.12, 0.13, 0.25), (0.28, 0.12, 0.3), (0.44, 0.11, 0.35), (0.6, 0.09, 0.45),
                                     (0.75, 0.06, 0.55))):
        fin(f"FinL{i}", bl, t0, t0 + 0.08, 1, ln, a, magenta, "#B02880")
    for i, (t0, ln) in enumerate(((0.2, 0.07), (0.38, 0.06), (0.55, 0.05))):
        fin(f"FinR{i}", bl, t0, t0 + 0.07, -1, ln, 0.4, magenta, "#B02880")
    tg = dict(grad=[(0, "#46C9C2"), (1, "#1E7F7E")], edge="#145E5E")
    for i, z in enumerate((0.3, 0.42)):
        _sym(lambda s, z=z, i=i: prong(f"Barb{i}{s}", [(s * 0.015, z), (s * 0.04, z + 0.015), (s * 0.06, z + 0.04)],
                                       0.022, 0.008, teal, **tg))
    P("Guard", "cube", (0, 0, 0.14), (0.06, 0.04, 0.05), teal, "#2FA9A6")
    for i, (a, ln) in enumerate(((0.9, 0.11), (0.35, 0.12), (-0.2, 0.1), (-0.7, 0.08))):
        _sym(lambda s, a=a, ln=ln, i=i: prong(
            f"GuardSpike{i}{s}", [(s * 0.02, 0.14), (s * (0.02 + ln * 0.55 * math.cos(a + 0.2)), 0.14 + ln * 0.55 * math.sin(a + 0.2)),
                                  (s * (0.02 + ln * math.cos(a)), 0.14 + ln * math.sin(a))], 0.03, 0.009, teal, **tg))
    grip(-0.22, 0.12, 0.014, teal, "#2A9C99", rings=5, ring_m=gold, ring_c="#EDB735")
    tube("Loop", [(0, 0, -0.22), (0.035, 0, -0.25), (0.03, 0, -0.3), (-0.01, 0, -0.31), (-0.025, 0, -0.27),
                  (-0.01, 0, -0.25)], 0.009, teal, "#2FA9A6")
    finish("w_coral_spine", -0.05, 1.14)


# 11. Asa de Marfim — montante branco de aro grafite e filete gravado, guarda de penas caídas
def build_w_ivory_wing():
    white = _m("w_ivory", "#F3F2EE", 0.4)
    silver = _m("w_silver", "#C8CDD6", 0.25, 0.85)
    keys = [(0, 0.2, 0.06, 0.06, 0.014), (0, 0.66, 0.085, 0.085, 0.016), (0, 1.02, 0.08, 0.08, 0.015),
            (0, 1.32, 0.0, 0.0, 0.002)]
    blade("Blade", keys, white, n=14, grad=[(0, "#E9E9E6"), (1, "#FFFFFF")], edge="#2F3036", band=0.7, rim=0.8,
          ridge="#C9CCD3")
    blade("Engrave", [(0, 0.24, 0.006, 0.006, 0.0175), (0, 0.6, 0.012, 0.012, 0.018), (0, 0.9, 0.004, 0.004, 0.017),
                      (0, 1.0, 0.0, 0.0, 0.012)], silver, n=8, grad="#A9AEB8", edge="#D6DAE0")
    sg = dict(grad=[(0, "#FFFFFF"), (1, "#B8BDC6")], edge="#7F8590", band=0.3, rim=0.8)
    P("Guard", "cube", (0, 0, 0.19), (0.18, 0.05, 0.05), silver, "#DDE1E7")
    for k, (th, ln) in enumerate(((-0.3, 0.22), (-0.65, 0.21), (-1.0, 0.19), (-1.3, 0.16), (-1.55, 0.12))):
        def f(s, th=th, ln=ln, k=k):
            st = Vector((s * (0.02 + k * 0.012), 0.19))
            d0 = Vector((s * math.cos(th + 0.4), math.sin(th + 0.4)))
            d1 = Vector((s * math.cos(th), math.sin(th)))
            prong(f"Feather{k}{s}", [tuple(st), tuple(st + d0 * ln * 0.5), tuple(st + d0 * ln * 0.5 + d1 * ln * 0.5)],
                  0.06, 0.013, white if k % 2 == 0 else silver, **sg)
        _sym(f)
    grip(-0.26, 0.17, 0.017, silver, "#B9BFC9", rings=5, ring_c="#E4E7EC")
    P("PommelBall", "sphere", (0, 0, -0.28), (0.05, 0.045, 0.045), silver, "#D5DAE2", seg=10)
    _sym(lambda s: prong(f"PommelWing{s}", [(0, -0.28), (s * 0.03, -0.3), (s * 0.04, -0.34)], 0.024, 0.009, silver, **sg))
    prong("PommelSpike", [(0, -0.29), (0, -0.33), (0, -0.37)], 0.024, 0.009, silver, **sg)
    finish("w_ivory_wing", 0, 1.32)


# 12. Garra Escarlate — lâmina curva vermelho-laranja, dorso verde-água com cristas, guarda em garra
def build_w_scarlet_talon():
    red = _m("w_scarlet", "#EA5A2E", 0.3, 0.25, glow=0.4)
    teal = _m("w_teal", "#2FA9A6", 0.3, 0.5)
    dark = _m("w_maroon", "#5A1E22", 0.55)
    sp = [(0.0, 0.17), (0.045, 0.42), (0.1, 0.7), (0.08, 0.95), (-0.045, 1.14)]
    ww = (0.05, 0.075, 0.08, 0.05, 0.0)
    bl = blade("Blade", [(x, z, w * 0.75, w, 0.015 if w else 0.002) for (x, z), w in zip(sp, ww)], red, n=22,
               grad=[(0, "#F2541E"), (0.5, "#E2361C"), (1, "#FF7A36")], edge_r="#FFA860", edge_l="#1FB0A8",
               band=0.3, rim=0.45, ridge="#FFB880")
    for i, (t0, ln, a) in enumerate(((0.18, 0.08, -0.5), (0.36, 0.08, -0.4), (0.54, 0.07, -0.25), (0.7, 0.05, 0.1))):
        fin(f"Crest{i}", bl, t0, t0 + 0.08, 1, ln, a, teal, "#17807C")
    tube("Rib", [(0.04, 0, 0.3), (0.085, 0, 0.5), (0.11, 0, 0.68), (0.1, 0, 0.82)], 0.01, dark, "#9C2E22", r_end=0.005)
    tg = dict(grad=[(0, "#46C9C2"), (1, "#1E7F7E")], edge="#145E5E")
    P("Guard", "cube", (0.01, 0, 0.15), (0.09, 0.045, 0.05), teal, "#2FA9A6")
    prong("Claw", [(0.03, 0.14), (0.08, 0.08), (0.075, -0.05), (0.04, -0.16), (0.01, -0.2)], 0.03, 0.011, teal, n=12, **tg)
    prong("ClawL", [(-0.03, 0.15), (-0.07, 0.13), (-0.1, 0.16)], 0.03, 0.01, red, grad=[(0, "#E84A2C"), (1, "#FF9A5C")],
          edge="#9C2E22")
    grip(-0.22, 0.13, 0.016, dark, "#6E2228", rings=4, ring_m=red, ring_c="#E84A2C")
    prong("Pommel", [(0, -0.21), (0.01, -0.25), (0.03, -0.29)], 0.034, 0.012, red, grad=[(0, "#E84A2C"), (1, "#FF9A5C")],
          edge="#9C2E22")
    finish("w_scarlet_talon", -0.045, 1.14)


# 13. Junco Carmesim — katana fina laranja-carmim com fio rosado e dorso verde-água, cabo trançado
def build_w_crimson_reed():
    red = _m("w_crimson", "#E85A50", 0.25, 0.35, glow=0.3)
    teal = _m("w_sea", "#63B8B1", 0.3, 0.6)
    pinkg = _m("w_pinkgrey", "#D6B4C0", 0.4, 0.3)
    sp = [(0.0, 0.16), (0.004, 0.5), (0.02, 0.9), (0.045, 1.2)]
    blade("Blade", [(x, z, wl, wr, 0.009 if wr else 0.002) for (x, z), (wl, wr) in
                    zip(sp, ((0.012, 0.024), (0.012, 0.023), (0.01, 0.02), (0.0, 0.0)))], red, n=18,
          grad=[(0, "#E84A1E"), (0.5, "#F05A30"), (1, "#F78A5A")], edge_r="#FF9AB0", edge_l="#2F9C95",
          band=0.3, rim=0.75, ridge="#FFD8C8")
    P("Tsuba", "cyl", (0, 0, 0.13), (0.07, 0.05, 0.016), teal, "#63B8B1", seg=10)
    P("Habaki", "cube", (0, 0, 0.155), (0.03, 0.024, 0.03), teal, "#8ED3CC")
    grip(-0.24, 0.12, 0.014, pinkg, "#C9A2B2", rings=7, ring_c="#F2E2E8")
    for i in range(6):
        diamond(f"Wrap{i}", 0, -0.2 + i * 0.055, 0.03, 0.04, 0.016, pinkg, "#8E5C70", "#8E5C70")
    P("Kashira", "cyl", (0, 0, -0.25), (0.032, 0.032, 0.022), teal, "#63B8B1", seg=10)
    finish("w_crimson_reed", 0.045, 1.2)


# 14. Foice Pálida — lâmina curta em gancho para a esquerda, entalhes no dorso, guarda em D
def build_w_pale_crescent():
    pale = _m("w_pale", "#DEE3EC", 0.25, 0.5)
    grey = _m("w_grey", "#8C939C", 0.3, 0.8)
    sp = [(0.02, 0.12), (0.045, 0.25), (0.0, 0.35), (-0.1, 0.39), (-0.21, 0.33)]
    ww = (0.05, 0.095, 0.11, 0.075, 0.0)
    bl = blade("Blade", [(x, z, w * 0.3, w, 0.016 if w else 0.002) for (x, z), w in zip(sp, ww)], pale, n=20,
               grad=[(0, "#C9D2E0"), (0.5, "#E9EEF5"), (1, "#F7F9FC")], edge_l="#8492A8", edge_r="#FFFFFF",
               band=0.35, rim=0.75, ridge="#AFC0D8")
    for i, (t0, ln, a) in enumerate(((0.4, 0.05, 0.5), (0.55, 0.045, 0.6))):
        fin(f"Notch{i}", bl, t0, t0 + 0.07, -1, ln, a, pale, "#FFFFFF")
    P("Collar", "cube", (0.02, 0, 0.125), (0.075, 0.045, 0.04), grey, "#A7AEB8")
    grip(-0.12, 0.11, 0.017, grey, "#7F8791", rings=3, ring_c="#A7AEB8")
    P("LoopTop", "cube", (0.065, 0, 0.11), (0.07, 0.03, 0.022), grey, "#A7AEB8")
    P("LoopSide", "cube", (0.095, 0, 0.0), (0.024, 0.03, 0.22), grey, "#B5BCC6")
    P("LoopBot", "cube", (0.05, 0, -0.11), (0.11, 0.03, 0.024), grey, "#959DA7")
    P("Pommel", "cube", (0, 0, -0.13), (0.04, 0.036, 0.03), grey, "#A7AEB8")
    finish("w_pale_crescent", -0.21, 0.33)


# 15. Chama Rosada — lâmina em labareda magenta→pêssego, filete azul, anel ciano com gema, cabo ameixa
def build_w_rose_flame():
    pink = _m("w_rosefire", "#E8488E", 0.25, 0.15, glow=0.35)
    silver = _m("w_silver", "#D5DAE2", 0.25, 0.85)
    cyan = _m("w_cyan", "#58D6F2", 0.15, 0.2, glow=0.7)
    plum = _m("w_plum", "#7A2D78", 0.5)
    keys = [(0, 0.16, 0.022, 0.02, 0.012), (-0.004, 0.34, 0.036, 0.034, 0.014), (-0.018, 0.54, 0.05, 0.046, 0.015),
            (-0.042, 0.74, 0.056, 0.04, 0.014), (-0.075, 0.9, 0.042, 0.024, 0.012), (-0.115, 1.02, 0.0, 0.0, 0.003)]
    bl = blade("Blade", keys, pink, n=24, grad=[(0, "#FF9AA8"), (0.3, "#F2589A"), (0.65, "#D82A7C"), (1, "#C01870")],
               edge=[(0, "#FFD0DA"), (1, "#FF86BC")], band=0.42, rim=0.85, ridge=[(0, "#FFFFFF"), (1, "#FFB3D4")])
    for i, (t0, ln, a) in enumerate(((0.16, 0.06, 0.7), (0.33, 0.085, 0.75), (0.51, 0.1, 0.8), (0.69, 0.085, 0.85))):
        fin(f"Flame{i}", bl, t0, t0 + 0.12, -1, ln, a, pink, "#FFB8D2")
    fin("FlameL", bl, 0.36, 0.48, 1, 0.06, 0.45, pink, "#F27BA9")
    fin("Hook", bl, 0.84, 0.93, 1, 0.05, 0.9, pink, "#FFC7DC")
    blade("Inlay", [(-0.012, 0.19, 0.006, 0.006, 0.0165), (-0.017, 0.32, 0.007, 0.007, 0.0175), (-0.026, 0.46, 0, 0, 0.012)],
          cyan, n=6, grad="#86DCF7", edge="#4CB8E0")
    sg = dict(grad=[(0, "#F2F4F8"), (1, "#9EA7B5")], edge="#7F8899")
    P("GuardCore", "cube", (0, 0, 0.145), (0.07, 0.036, 0.03), silver, "#E4E8EE")
    _sym(lambda s: prong(f"Guard{s}", [(s * 0.02, 0.145), (s * 0.06, 0.13), (s * 0.085, 0.09)], 0.034, 0.012, silver, **sg))
    P("Ring", "cyl", (0, 0, 0.09), (0.075, 0.075, 0.024), cyan, "#58D6F2", rot=(1.5708, 0, 0), seg=14)
    gem("Gem", 0, 0.09, 0.022, pink, "#FFB0A0")
    grip(-0.24, 0.06, 0.016, plum, "#7A2D78", rings=6, ring_c="#4E1C52")
    diamond("Pommel", 0, -0.27, 0.045, 0.07, 0.024, silver, "#E4E8EE", "#9EA7B5")
    finish("w_rose_flame", -0.115, 1.02)


for _f in (build_w_azure_edge, build_w_thorn_root, build_w_crystal_frost, build_w_moon_crescent,
           build_w_royal_wings, build_w_venom_leaf, build_w_neon_edge, build_w_titan_cleaver, build_w_amber_fang,
           build_w_coral_spine, build_w_ivory_wing, build_w_scarlet_talon, build_w_crimson_reed,
           build_w_pale_crescent, build_w_rose_flame):
    WEAPONS.append((_f.__name__[len("build_"):], _f))
