# Equipamentos modulares (roupas e armaduras) vestidos sobre o modelo do cavaleiro.
# Executado por exec() dentro de build_assets.py, depois de characters.py (usa loft, sec, grow, span, sample,
# stepped, dome, fist, human_head, hair_locks, tbox, limb, shell, band, wing, strap, pouch, join_objs, mat, hexc).
#
# Cada estilo vira assets/models/gear/<estilo>.glb com o MESMO rig de pivôs do knight.glb (LegL/LegR > KneeL/KneeR,
# Body > Head, ArmL/ArmR > ElbowL/ElbowR, nas mesmas posições). scripts/player/knight_look.gd instancia o GLB,
# muda cada malha para o pivô de mesmo nome do cavaleiro e oculta as peças de placas daquele espaço.
#
# Espaços e o que cada estilo cobre (o estilo substitui TUDO da região):
#   h_*  cabeça: rosto/cabelo ou elmo (acima do pescoço)
#   a_*  peito: tronco, pescoço, braço e antebraço (mangas), quadril e coxas (calça), saias
#   g_*  mãos: punhos (luvas/manoplas) e punho da manga
#   f_*  pés: canela (meia/calça, material tp_) e calçado
# Materiais com prefixo são tingidos pelo item equipado: t1_ = cor do item, t2_ = "color2" do item (ou a cor
# escurecida), tp_ = cor da calça (vem da peça de peito). Os demais ficam com a cor do GLB.
import math
from mathutils import Vector

GEAR_P = dict(height=1.84, heads=7.5, shoulders=1.08, waist=0.92, limbs=1.06, hands=1.15, feet=1.1)
HEAD_CHIN, HEAD_H = 1.555, 0.245        # cabeça humana sob os elmos (olhos ~1,68, na fenda do elmo do cavaleiro)
ZUP = (0, 0, 1)


def gm(name, hx, rough=0.85, metal=0.0):
    return mat(name, hexc(hx), rough, metal)


def g_rig(style):
    P = body_proportions(**GEAR_P)
    R = humanoid_rig("Gear", P)
    return P, R


def g_export(style):
    os.makedirs(OUT + "gear", exist_ok=True)
    export("gear/" + style)


# ------------------------------------------------------------------ materiais comuns
def g_mats():
    return dict(
        skin=gm("g_skin", "#D29A74", 0.8),
        hair=gm("g_hair", "#4A2C17", 0.9),
        eye=gm("g_eye", "#141010", 0.4),
        sclera=gm("g_sclera", "#E6E0D2", 0.5),
        lip=gm("g_lip", "#9C5A48", 0.7),
        linen=gm("g_linen", "#D9CCAA", 0.95),
        linen_d=gm("g_linen_d", "#A8987A", 0.95),
        lea=gm("g_leather", "#6B4423", 0.8),
        lea_d=gm("g_leather_d", "#3A2412", 0.85),
        steel=gm("g_steel", "#A9B1BE", 0.35, 0.85),
        steel_d=gm("g_steel_d", "#5D6573", 0.45, 0.85),
        chain=gm("g_chain", "#6A707A", 0.75, 0.45),
        gold=gm("g_gold", "#E6B544", 0.35, 0.8),
        brass=gm("g_brass", "#B88A3A", 0.45, 0.7),
        slit=gm("g_slit", "#050505", 0.9),
        pants=gm("tp_pants", "#5A4632", 0.9),
    )


# ------------------------------------------------------------------ geometria do tronco
def torso_at(secs, z):
    """Seção interpolada do tronco na altura z (secs em ordem crescente de z)."""
    if z <= secs[0]["c"].z:
        return dict(secs[0], c=Vector((secs[0]["c"].x, secs[0]["c"].y, z)))
    for a, b in zip(secs, secs[1:]):
        if a["c"].z <= z <= b["c"].z:
            return _mix(a, b, (z - a["c"].z) / max(b["c"].z - a["c"].z, 1e-6))
    return dict(secs[-1], c=Vector((secs[-1]["c"].x, secs[-1]["c"].y, z)))


def surf(s, a, out=0.0):
    """Ponto na superfície da seção s no ângulo a (0 = frente/-Y, positivo para +X)."""
    ca, sa = math.cos(a), math.sin(a)
    ry = s["ry"] * (s["fr"] if ca > 0 else s["bk"])
    return Vector((s["c"].x + (s["rx"] + out) * sa, s["c"].y - (ry + out) * ca, s["c"].z))


def front_y(s, out=0.0):
    return s["c"].y - (s["ry"] * s["fr"] + out)


def on_torso(secs, x, z, back=False, out=0.01):
    s = torso_at(secs, z)
    a = math.asin(max(-0.97, min(0.97, x / max(s["rx"], 1e-4))))
    if back:
        a = math.pi - a
    return surf(s, a, out)


def torso_strap(name, secs, p0, p1, width, material, parent, back=False, n=6, out=0.012, t=0.005):
    """Tira (alça, bandoleira) colada na frente (ou nas costas) do tronco, de (x0, z0) a (x1, z1)."""
    pts = [on_torso(secs, p0[0] + (p1[0] - p0[0]) * i / n, p0[1] + (p1[1] - p0[1]) * i / n, back, out)
           for i in range(n + 1)]
    return loft(name, [sec(p, width / 2, t) for p in pts], material, parent, sides=4,
                fwd=(0, 1 if back else -1, 0))


def ring_at(name, secs, z0, z1, add, material, parent, sides=12, chamfer=0.0):
    """Anel (cinto, faixa, barra) contornando o tronco entre z0 (baixo) e z1 (cima)."""
    a = grow([torso_at(secs, z0)], 1.0, add)[0]
    b = grow([torso_at(secs, z1)], 1.0, add)[0]
    return loft(name, [a, b], material, parent, sides=sides, phase=0, axis=ZUP, chamfer=(chamfer, chamfer))


def belt(name, secs, z, h, add, lea_m, metal_m, parent, tail=True, sides=12):
    parts = [ring_at(name, secs, z - h / 2, z + h / 2, add, lea_m, parent, sides=sides)]
    fy = front_y(torso_at(secs, z), add)
    parts.append(tbox(name + "Buckle", (0, fy - 0.004, z), (0.05, 0.012, h * 1.25), metal_m, bevel=0.003,
                      parent=parent))
    parts.append(tbox(name + "BuckleHole", (0, fy - 0.01, z), (0.028, 0.004, h * 0.6), lea_m, parent=parent))
    if tail:
        parts.append(strap(name + "End", (0.035, fy - 0.006, z - 0.005), (0.05, fy - 0.014, z - 0.1), 0.03, lea_m,
                           parent, (0.15, -1, 0)))
    return join_objs(name, parts)


def skirt(name, z0, z1, rx0, ry0, rx1, ry1, mats, parent, a0=-math.pi, a1=math.pi, cols=12, rows=2,
          folds=0.012, thick=0.012, cy=0.0, matfn=None, hem=None):
    """Saia/barra em anel (a de 0 = frente, + para +X). Aberta se a1 - a0 < 2pi (fendas, metades presas às pernas).
    matfn(a, t) -> índice do material por face; hem(a) -> deslocamento da barra (recorte, ponta)."""
    closed = a1 - a0 >= 2 * math.pi - 1e-3
    ncol = cols if closed else cols + 1
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        t = i / rows
        z = z0 + (z1 - z0) * t
        rx, ry = rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t
        row = []
        for j in range(ncol):
            a = a0 + (a1 - a0) * j / cols
            edge = (not closed) and (j == 0 or j == ncol - 1)
            off = 0.0 if edge else folds * t * (1 if j % 2 else -1)
            zz = z + (hem(a) if hem and i == rows else 0.0)
            row.append(bm.verts.new((math.sin(a) * (rx + off), cy - math.cos(a) * (ry + off), zz)))
        grid.append(row)
    for i in range(rows):
        for j in range(ncol if closed else ncol - 1):
            k = (j + 1) % ncol
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][k], grid[i][k]))
            if matfn:
                am = a0 + (a1 - a0) * (j + 0.5) / cols
                f.material_index = matfn(am, (i + 0.5) / rows)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:                      # normais para fora
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, c.y - cy, 0))) < 0:
            f.normal_flip()
    if thick:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    _place(bm, (0, 0, 0), parent)
    ob = _finish(name, bm, mats[0], parent)
    for m in mats[1:]:
        ob.data.materials.append(m)
    print("PART", name, "skirt", flush=True)
    return ob


def leg_skirt(name, R, z0, z1, rx0, ry0, rx1, ry1, mats, gap=0.0, **kw):
    """Saia dividida em duas metades presas às pernas (acompanham o passo sem atravessar a coxa)."""
    out = []
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (gap, math.pi - gap) if s > 0 else (-math.pi + gap, -gap)
        out.append(skirt("%s%s" % (name, n), z0, z1, rx0, ry0, rx1, ry1, mats, R["Leg" + n], a0=lo, a1=hi, **kw))
    return out


def split_x(ob, mats, fn):
    """Recolore faces de ob: fn(centro_mundo) -> índice em mats (anexados ao objeto)."""
    base = len(ob.data.materials)
    for m in mats:
        ob.data.materials.append(m)
    off = _wloc(ob.parent)
    for p in ob.data.polygons:
        i = fn(Vector(p.center) + off)
        if i is not None:
            p.material_index = base + i
    return ob


# ------------------------------------------------------------------ corpo vestido (peças reutilizadas)
def cloth_sections(P):
    """Seções do tronco para roupa: peito menos saltado, cintura solta e rampa do trapézio até o pescoço."""
    b = [dict(x) for x in torso_sections(P)]
    for x in b:
        x["fr"] = min(x["fr"], 1.06)
    b[3]["rx"] = (b[2]["rx"] + b[4]["rx"]) / 2 * 0.98
    b[3]["ry"] = (b[2]["ry"] + b[4]["ry"]) / 2
    top, nk = b[-2], b[-1]
    trap = sec((0, 0, top["c"].z + (nk["c"].z - top["c"].z) * 0.55), top["rx"] * 0.68, top["ry"] * 0.86)
    return b[:-1] + [trap, nk]


def clothed_torso(P, R, material, k=1.07, add=0.01, z_top=None, keel=0.0, steps=()):
    secs = grow(cloth_sections(P), k, add)
    if keel:
        secs = [dict(s, keel=keel * max(0.0, 1 - abs(s["c"].z - 1.3) / 0.25)) for s in secs]
    use = secs[1:] if z_top is None else [s for s in secs[1:] if s["c"].z <= z_top] + [torso_at(secs, z_top)]
    if steps:
        use = stepped(use, steps, drop=0.95, eps=0.01)
    loft("Torso", use, material, R["Body"], sides=12, phase=0, axis=ZUP, chamfer=(0.0, 0.008))
    return secs


def neck(R, skin, collar=None, collar_z=1.455):
    parts = [loft("Neck", [sec((0, 0.006, 1.43), 0.058, 0.056), sec((0, 0.01, 1.6), 0.05, 0.048)], skin, R["Head"],
                  sides=8)]
    if collar is not None:
        parts.append(loft("Collar", [sec((0, 0.004, collar_z - 0.02), 0.098, 0.085),
                                     sec((0, 0.006, collar_z + 0.025), 0.074, 0.07)], collar, R["Head"], sides=10))
    return join_objs("Neck", parts)


def hips(R, material, rx=0.158, ry=0.118):
    return loft("Hips", [sec((0, 0, 1.0), rx * 0.96, ry * 0.97), sec((0, 0, 0.865), rx, ry)], material, R["Body"],
                sides=12, phase=0)


def thighs(P, R, material, k=1.05, add=0.004):
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        loft("Leg%s_Thigh" % n, grow(S["thigh"], k, add), material, R["Leg" + n])


def sleeves(P, R, material, skin, upto=1.0, k=1.04, add=0.006, cap=True, cuff=None, flare=0.0, cap_mat=None):
    """Manga: braço inteiro e antebraço até `upto` (fração); o resto do antebraço é pele.
    flare alarga a boca da manga (mantos); cuff = material da barra da manga."""
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        arm, elbow = R["Arm" + n], R["Elbow" + n]
        up = [loft("Arm%s_Upper" % n, grow(span(S["upper"], 0.1, 1.0), k, add), material, arm)]
        if cap:
            sh = mirror(P["shoulder"], s)
            tilt = Vector((s * math.sin(1.0), 0, math.cos(1.0)))
            up.append(dome("Arm%s_Cap" % n, sh + Vector((-s * 0.012, 0, -0.022)), tilt, 0.066, 0.07, 0.062,
                           cap_mat or material, arm, sides=8))
        join_objs("Arm%s_Upper" % n, up)
        F = grow(span(S["fore"], 0.0, upto), k, add)
        if flare:
            F[-1] = dict(F[-1], rx=F[-1]["rx"] + flare, ry=F[-1]["ry"] + flare)
        fo = [loft("Arm%s_Fore" % n, F, material, elbow)]
        if cuff is not None:
            fdown = (F[-1]["c"] - F[0]["c"]).normalized()
            c0 = dict(F[-1], c=F[-1]["c"] - fdown * 0.03)
            fo.append(band("Arm%s_Cuff" % n, c0, fdown, 0.03, cuff, elbow, sides=8, out=0.003))
        if upto < 0.98:
            fo.append(loft("Arm%s_Skin" % n, span(S["fore"], max(0.0, upto - 0.06), 1.0), skin, elbow))
        join_objs("Arm%s_Fore" % n, fo)


def plain_head(R, M, beard=False, hair=True):
    head = R["Head"]
    face_mats = {"skin": M["skin"], "pupil": M["eye"], "sclera": M["sclera"], "brow": M["hair"], "lip": M["lip"]}
    H = human_head("", HEAD_CHIN, HEAD_H, head, face_mats, {"jaw": 1.08, "chin": 1.1, "brow": 1.2, "nose": 1.05})
    if hair:
        shell("HairBase", (0, 0.006, HEAD_CHIN + 0.165), (0.156, 0.208, 0.2), M["hair"], cut=0.25, seg=10, rings=6,
              rot=(-0.2, 0, 0), thick=0.008, parent=head)
        shell("HairBaseBack", (0, 0.006, HEAD_CHIN + 0.14), (0.162, 0.27, 0.2), M["hair"], cut=0.1, seg=10, rings=6,
              rot=(-math.pi / 2, 0, 0), thick=0.008, parent=head)
        locks = []
        for phi in (-48, -24, 0, 24, 48):                      # franja curta penteada para o lado
            locks.append(dict(a=(phi * 0.6 + 150, 75), b=(phi - 15, 22), w=0.055, t=0.011, bulge=0.004, n=5))
        for phi in (75, 105, 135, 165, -165, -135, -105, -75):  # laterais e nuca curtas
            locks.append(dict(a=(phi, 45), b=(phi, 2), drop=0.025, w=0.058, t=0.012, bulge=0.006, n=4))
        hair_locks("Hair", H, locks, M["hair"], head)
    if beard:
        limb("Beard", (0, -0.04, H["mouth_z"] - 0.002), (0, -0.075, HEAD_CHIN - 0.03), 0.07, 0.03, M["hair"],
             sides=7, flat=0.75, twist=math.pi / 7, parent=head)
    return H


def head_shell_secs(rows, cy=0.008):
    """rows = [(dz a partir do queixo, rx, ry)] -> seções em volta da cabeça."""
    return [sec((0, cy, HEAD_CHIN + dz), rx, ry) for dz, rx, ry in rows]


# ================================================================== CABEÇA
def build_h_bare():
    P, R = g_rig("h_bare")
    plain_head(R, g_mats())
    g_export("h_bare")


def build_h_hood():
    """Capuz de tecido: volume solto em volta da cabeça caindo para trás em ponta, abertura do rosto com
    borda grossa e forro escuro, gola sobre os ombros. t1 = tecido, t2 = forro/borda."""
    P, R = g_rig("h_hood")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    cl = gm("t1_hood", "#4E5E35", 0.95)
    cl_d = gm("t2_hood", "#2F3A20", 0.95)
    ARC = 4.35
    # (dz, rx, ry, recuo y): o capuz infla nas laterais e o alto pende para trás
    rows = [(-0.05, 0.15, 0.155, 0.02), (0.03, 0.142, 0.158, 0.02), (0.11, 0.138, 0.16, 0.022),
            (0.18, 0.13, 0.156, 0.028), (0.235, 0.108, 0.14, 0.04), (0.275, 0.07, 0.11, 0.06),
            (0.29, 0.03, 0.06, 0.09)]
    secs = [sec((0, cy, HEAD_CHIN + dz), rx, ry) for dz, rx, ry, cy in rows]
    parts = [loft("Hood", secs, cl, head, sides=12, phase=0, fwd=(0, 1, 0), axis=ZUP, arc=ARC, thick=0.022)]
    # forro escuro logo por dentro (aparece em volta do rosto)
    inner = [sec((0, cy + 0.004, HEAD_CHIN + dz), rx - 0.02, ry - 0.02) for dz, rx, ry, cy in rows[:5]]
    parts.append(loft("HoodLining", inner, cl_d, head, sides=12, phase=0, fwd=(0, 1, 0), axis=ZUP, arc=ARC + 0.3,
                      thick=0.008))
    # borda grossa contornando a abertura (laterais e arco da testa)
    a = (2 * math.pi - ARC) / 2
    side = [Vector((rx * math.sin(a), cy - ry * math.cos(a), HEAD_CHIN + dz)) for dz, rx, ry, cy in rows[:5]]
    for sgn, nm in ((1, "L"), (-1, "R")):
        pts = [Vector((sgn * p.x, p.y, p.z)) for p in side]
        parts.append(loft("HoodRim" + nm, [sec(p, 0.02, 0.016) for p in pts], cl, head, sides=6))
    top = side[-1]
    arch = [Vector((top.x * math.cos(t), top.y - 0.012 * math.sin(t) ** 2, top.z + 0.03 * math.sin(t)))
            for t in (0.0, 0.5, 1.0, 1.5708, 2.14, 2.64, 3.1416)]
    parts.append(loft("HoodRimTop", [sec(p, 0.02, 0.016) for p in arch], cl, head, sides=6))
    # ponta (liripipe) caindo nas costas
    parts.append(loft("HoodTail", [sec((0, 0.1, HEAD_CHIN + 0.27), 0.04, 0.035),
                                   sec((0, 0.175, HEAD_CHIN + 0.2), 0.03, 0.026),
                                   sec((0, 0.21, HEAD_CHIN + 0.06), 0.018, 0.016),
                                   sec((0, 0.215, HEAD_CHIN - 0.06), 0.006, 0.006)], cl, head, sides=6))
    # gola sobre os ombros: abre em V na frente, ponta nas costas
    parts.append(skirt("HoodCowl", HEAD_CHIN - 0.04, 1.33, 0.15, 0.15, 0.27, 0.2, [cl], head, cols=14, rows=2,
                       folds=0.012, thick=0.016, cy=0.02, hem=lambda a: 0.07 * max(0.0, math.cos(a)) ** 2 -
                       0.05 * max(0.0, -math.cos(a)) ** 2))
    join_objs("Hood", parts)
    g_export("h_hood")


def build_h_cap():
    """Capuz de couro (touca de armas): cobre topo, nuca e laterais com abas nas orelhas e tira no queixo;
    faixa de couro escuro com rebites na testa."""
    P, R = g_rig("h_cap")
    M = g_mats()
    head = R["Head"]
    H = plain_head(R, M, hair=False)
    lea = gm("t1_cap", "#7A4E26", 0.8)
    lea_d = gm("t2_cap", "#3E2613", 0.85)
    cap = head_shell_secs([(0.0, 0.108, 0.118), (0.06, 0.112, 0.124), (0.13, 0.112, 0.126),
                           (0.18, 0.108, 0.124)], cy=0.012)
    parts = [loft("Cap", cap, lea, head, sides=12, phase=0, fwd=(0, 1, 0), axis=ZUP, arc=4.2, thick=0.016)]
    top = head_shell_secs([(0.17, 0.11, 0.124), (0.215, 0.098, 0.112), (0.25, 0.07, 0.08), (0.268, 0.025, 0.03)],
                          cy=0.01)
    parts.append(loft("CapTop", top, lea, head, sides=12, phase=0, axis=ZUP))
    # costuras: gomos (4 cristas da testa à nuca)
    for k, ang in enumerate((0.0, math.pi / 2, math.pi, -math.pi / 2)):
        pts = []
        for dz, rx, ry in ((0.172, 0.112, 0.126), (0.215, 0.1, 0.114), (0.25, 0.072, 0.082), (0.268, 0.0, 0.0)):
            pts.append(Vector((math.sin(ang) * (rx + 0.002), 0.01 - math.cos(ang) * (ry + 0.002), HEAD_CHIN + dz)))
        parts.append(loft("CapSeam%d" % k, [sec(p, 0.006, 0.004) for p in pts], lea_d, head, sides=4))
    parts.append(band("CapBand", sec((0, 0.01, HEAD_CHIN + 0.15), 0.112, 0.126), ZUP, 0.03, lea_d, head, sides=12,
                      phase=0, out=0.006, thick=0.008))
    for k in range(7):                               # rebites na faixa
        a = -1.2 + k * 0.4
        p = Vector((math.sin(a) * 0.123, 0.01 - math.cos(a) * 0.137, HEAD_CHIN + 0.165))
        parts.append(tbox("CapRivet%d" % k, p, (0.012, 0.012, 0.012), M["brass"], bevel=0.003, parent=head))
    # tira do queixo
    parts.append(loft("CapStrap", [sec((0.1, 0.0, HEAD_CHIN + 0.05), 0.012, 0.004),
                                   sec((0.06, -0.06, HEAD_CHIN - 0.005), 0.012, 0.004),
                                   sec((0.0, -0.075, HEAD_CHIN - 0.012), 0.012, 0.004),
                                   sec((-0.06, -0.06, HEAD_CHIN - 0.005), 0.012, 0.004),
                                   sec((-0.1, 0.0, HEAD_CHIN + 0.05), 0.012, 0.004)], lea_d, head, sides=4,
                      fwd=(0, 0, -1)))
    join_objs("Cap", parts)
    g_export("h_cap")


def mail_coif(name, head, chain, open_face=True, bottom=1.36):
    """Cota de malha da cabeça até os ombros (anéis em degrau imitam as fileiras de elos)."""
    rows = [(0.2, 0.112, 0.126), (0.12, 0.118, 0.132), (0.04, 0.114, 0.13), (-0.03, 0.105, 0.12)]
    secs = head_shell_secs(rows, cy=0.012)
    parts = [loft(name, secs, chain, head, sides=12, phase=0, fwd=(0, 1, 0), axis=(0, 0, -1),
                  arc=4.3 if open_face else None, thick=0.014)]
    parts.append(skirt(name + "Mantle", HEAD_CHIN - 0.02, bottom, 0.11, 0.122, 0.24, 0.19, [chain], head, cols=14,
                       rows=3, folds=0.006, thick=0.012, cy=0.012, hem=lambda a: 0.03 * math.cos(a) ** 2))
    return parts


def build_h_kettle():
    """Chapéu de ferro (aba larga) sobre cota de malha com o rosto aberto."""
    P, R = g_rig("h_kettle")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_kettle", "#8E96A3", 0.4, 0.85)
    parts = mail_coif("Coif", head, M["chain"])
    z0 = HEAD_CHIN + 0.185
    parts.append(loft("Kettle", [sec((0, 0.01, z0), 0.126, 0.138), sec((0, 0.01, z0 + 0.05), 0.124, 0.136),
                                 sec((0, 0.01, z0 + 0.09), 0.106, 0.116, keel=0.06),
                                 sec((0, 0.01, z0 + 0.115), 0.06, 0.068), sec((0, 0.01, z0 + 0.122), 0.015, 0.02)],
                      st, head, sides=12, phase=0, axis=ZUP))
    parts.append(loft("KettleBrim", [sec((0, 0.01, z0 + 0.01), 0.126, 0.138),
                                     sec((0, 0.01, z0 - 0.02), 0.21, 0.22),
                                     sec((0, 0.01, z0 - 0.034), 0.214, 0.224),
                                     sec((0, 0.01, z0 - 0.004), 0.126, 0.138)], st, head, sides=16, phase=0, axis=ZUP))
    # crista central e faixa rebitada
    prof = [(-0.13, z0 + 0.05), (-0.11, z0 + 0.09), (-0.06, z0 + 0.115), (0.0, z0 + 0.124), (0.06, z0 + 0.115),
            (0.11, z0 + 0.09), (0.13, z0 + 0.05)]
    parts.append(loft("KettleCrest", [sec((0, y + 0.01, z + 0.002), 0.012, 0.008) for y, z in prof], st, head,
                      sides=4, phase=0, fwd=(1, 0, 0)))
    parts.append(band("KettleBand", sec((0, 0.01, z0 + 0.005), 0.126, 0.138), ZUP, 0.022, M["steel_d"], head,
                      sides=12, phase=0, out=0.004, thick=0.006))
    join_objs("Kettle", parts)
    g_export("h_kettle")


def build_h_nasal():
    """Elmo cônico de nasal (gomos rebitados), com cota de malha pendendo da borda e o rosto aberto."""
    P, R = g_rig("h_nasal")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_nasal", "#A9B1BE", 0.35, 0.85)
    parts = mail_coif("Aventail", head, M["chain"])
    z0 = HEAD_CHIN + 0.17
    parts.append(loft("Nasal", [sec((0, 0.012, z0), 0.124, 0.138), sec((0, 0.012, z0 + 0.04), 0.124, 0.138),
                                sec((0, 0.014, z0 + 0.09), 0.1, 0.112, keel=0.04),
                                sec((0, 0.02, z0 + 0.13), 0.05, 0.058), sec((0, 0.026, z0 + 0.155), 0.008, 0.01)],
                      st, head, sides=8, phase=0, axis=ZUP))
    parts.append(band("NasalBand", sec((0, 0.012, z0), 0.124, 0.138), ZUP, 0.03, M["brass"], head, sides=8,
                      phase=0, out=0.004, thick=0.006))
    for k, ang in enumerate((math.pi / 4, 3 * math.pi / 4, -3 * math.pi / 4, -math.pi / 4)):   # costelas dos gomos
        pts = [Vector((math.sin(ang) * (rx + 0.004), 0.012 - math.cos(ang) * (ry + 0.004), z))
               for z, rx, ry in ((z0 + 0.03, 0.124, 0.138), (z0 + 0.09, 0.1, 0.112), (z0 + 0.13, 0.05, 0.058),
                                 (z0 + 0.15, 0.012, 0.014))]
        parts.append(loft("NasalRib%d" % k, [sec(p, 0.008, 0.005) for p in pts], M["brass"], head, sides=4))
    # protetor de nariz
    fy = 0.012 - 0.138 * 1.0 - 0.006
    parts.append(loft("NasalGuard", [sec((0, fy, z0 + 0.03), 0.018, 0.006), sec((0, fy - 0.006, z0 - 0.05), 0.016, 0.006),
                                     sec((0, fy - 0.004, z0 - 0.085), 0.02, 0.006)], st, head, sides=4,
                      fwd=(0, -1, 0)))
    join_objs("Nasal", parts)
    g_export("h_nasal")


def build_h_great():
    """Elmo fechado (balde): topo achatado, fenda dos olhos em degrau, respiros e cruz dourada na frente."""
    P, R = g_rig("h_great")
    M = g_mats()
    head = R["Head"]
    st = gm("t1_great", "#8D95A2", 0.38, 0.85)
    y0 = 0.01
    body_s = [sec((0, y0, 1.5), 0.112, 0.12), sec((0, y0, 1.56), 0.128, 0.14, fr=1.08, keel=0.08),
              sec((0, y0, 1.67), 0.13, 0.142, fr=1.08, keel=0.1), sec((0, y0, 1.76), 0.128, 0.14, fr=1.05, keel=0.06),
              sec((0, y0, 1.8), 0.124, 0.134)]
    parts = [loft("Great", body_s, st, head, sides=12, phase=0, axis=ZUP, chamfer=(0.0, 0.0))]
    parts.append(loft("GreatTop", [sec((0, y0, 1.8), 0.124, 0.134), sec((0, y0, 1.83), 0.108, 0.118),
                                   sec((0, y0, 1.845), 0.07, 0.08)], st, head, sides=12, phase=0, axis=ZUP))
    # fenda dos olhos: faixa escura afundada, com a testa saliente por cima
    parts.append(loft("GreatSlit", [sec((0, y0, 1.668), 0.129, 0.141, fr=1.08, keel=0.1),
                                    sec((0, y0, 1.69), 0.129, 0.141, fr=1.08, keel=0.1)], M["slit"], head, sides=12,
                      phase=0, axis=ZUP, arc=2.4, thick=0.006))
    parts.append(loft("GreatBrow", [sec((0, y0, 1.69), 0.136, 0.149, fr=1.08, keel=0.1),
                                    sec((0, y0, 1.715), 0.135, 0.148, fr=1.07, keel=0.09)], st, head, sides=12,
                      phase=0, axis=ZUP, arc=2.6, thick=0.012))
    for k in range(5):                         # respiros (dois lados, abaixo da fenda)
        for sg in (1, -1):
            a = sg * (0.42 + 0.09 * (k % 3))
            z = 1.6 - (k // 3) * 0.035 - (k % 3) * 0.0
            p = Vector((math.sin(a) * 0.132, y0 - math.cos(a) * 0.152, z))
            parts.append(tbox("GreatBreath%d%s" % (k, "L" if sg > 0 else "R"), p, (0.012, 0.006, 0.022), M["slit"],
                              rot=(0, 0, a), parent=head))
    gold = gm("t2_great", "#E6B544", 0.35, 0.8)
    fy = y0 - 0.142 * 1.08 * 1.1 - 0.004
    parts.append(loft("GreatCrossV", [sec((0, fy + 0.012, 1.545), 0.013, 0.006), sec((0, fy, 1.6), 0.014, 0.006),
                                      sec((0, fy + 0.002, 1.665), 0.014, 0.006)], gold, head, sides=4))
    parts.append(loft("GreatCrossT", [sec((0, fy + 0.006, 1.72), 0.014, 0.006), sec((0, fy + 0.004, 1.79), 0.014, 0.006)],
                      gold, head, sides=4))
    parts.append(band("GreatBrowTrim", sec((0, y0, 1.712), 0.135, 0.148, fr=1.07, keel=0.09), ZUP, 0.012, gold, head,
                      sides=12, phase=0, arc=2.6, out=0.002))
    parts.append(band("GreatRimTrim", sec((0, y0, 1.5), 0.112, 0.12), ZUP, 0.018, gold, head, sides=12, phase=0,
                      out=0.004))
    join_objs("Great", parts)
    g_export("h_great")


def build_h_wizard():
    """Chapéu de mago de aba larga com ponta dobrada para trás, faixa e fivela; barba curta."""
    P, R = g_rig("h_wizard")
    M = g_mats()
    head = R["Head"]
    H = plain_head(R, M, beard=True)
    hat = gm("t1_wizard", "#4B3A8C", 0.9)
    band_m = gm("t2_wizard", "#E0B84A", 0.4, 0.6)
    z0 = HEAD_CHIN + 0.2
    parts = [loft("WizardBrim", [sec((0, 0.01, z0 + 0.012), 0.122, 0.134), sec((0, 0.0, z0 - 0.012), 0.27, 0.27),
                                 sec((0, 0.0, z0 - 0.026), 0.275, 0.275), sec((0, 0.01, z0), 0.122, 0.134)],
                  hat, head, sides=16, phase=0, axis=ZUP)]
    cone = [(0.0, 0.0, 0.124, 0.136), (0.0, 0.1, 0.1, 0.11), (0.012, 0.2, 0.07, 0.076), (0.04, 0.29, 0.045, 0.048),
            (0.1, 0.35, 0.026, 0.028), (0.17, 0.37, 0.004, 0.004)]
    parts.append(loft("WizardCone", [sec((0, 0.01 + dy, z0 + dz), rx, ry) for dy, dz, rx, ry in cone], hat, head,
                      sides=10, phase=0))
    parts.append(band("WizardBand", sec((0, 0.01, z0 + 0.005), 0.122, 0.134), ZUP, 0.035, band_m, head, sides=10,
                      phase=0, out=0.004, thick=0.006))
    parts.append(tbox("WizardBuckle", (0, 0.01 - 0.134 - 0.012, z0 + 0.022), (0.04, 0.008, 0.04), M["gold"],
                      bevel=0.003, parent=head))
    join_objs("Wizard", parts)
    g_export("h_wizard")


# ================================================================== PEITO
def build_a_shirt():
    """Sem armadura: camisa de linho com mangas arregaçadas, gola em V com cordão, cinto simples e calça."""
    P, R = g_rig("a_shirt")
    M = g_mats()
    body = R["Body"]
    secs = clothed_torso(P, R, M["linen"], k=1.05, add=0.008)
    neck(R, M["skin"])
    # decote em V (pele) e cordão
    fy = front_y(torso_at(secs, 1.42), 0.002)
    tbox("ShirtV", (0, fy + 0.004, 1.41), (0.07, 0.006, 0.07), M["skin"], bottom=(0.1, 1), parent=body)
    torso_strap("ShirtLace", secs, (0.02, 1.43), (-0.012, 1.37), 0.006, M["linen_d"], body, n=2, out=0.004)
    sleeves(P, R, M["linen"], M["skin"], upto=0.45, k=1.08, cuff=M["linen_d"])
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    belt("Belt", secs, 1.0, 0.04, 0.012, M["lea"], M["brass"], body)
    # barra da camisa por fora da calça
    skirt("ShirtHem", 1.0, 0.92, 0.172, 0.13, 0.18, 0.138, [M["linen"]], body, cols=12, rows=1, folds=0.006,
          thick=0.01)
    pouch("Pouch", (0.15, -0.07, 0.94), M["lea"], M["lea_d"], body, size=(0.07, 0.05, 0.08), rotz=0.5)
    g_export("a_shirt")


def build_a_tunic():
    """Túnica até o meio da coxa em duas cores (heráldica), gola, bandoleira de couro, cinto com bolsa,
    mangas compridas e braçadeiras. t1 = metade esquerda/mangas, t2 = metade direita."""
    P, R = g_rig("a_tunic")
    M = g_mats()
    body = R["Body"]
    c1 = gm("t1_tunic", "#8E2A22", 0.92)
    c2 = gm("t2_tunic", "#2F4A3A", 0.92)
    secs = clothed_torso(P, R, c1, k=1.07, add=0.01)
    tor = bpy.data.objects["Torso"]
    split_x(tor, [c2], lambda c: 0 if c.x < 0 else None)
    neck(R, M["skin"], collar=M["linen_d"])
    sleeves(P, R, c1, M["skin"], upto=1.0, k=1.06, cuff=M["lea_d"])
    for n in ("L", "R"):
        o = bpy.data.objects["Arm%s_Upper" % n]
        if n == "R":
            split_x(o, [c2], lambda c: 0)
        o = bpy.data.objects["Arm%s_Fore" % n]
        if n == "R":
            split_x(o, [c2], lambda c: 0)
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    # saia da túnica: metades presas às pernas, barra recortada em pontas, faixa escura na barra
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.0, math.pi) if s > 0 else (-math.pi, 0.0)
        skirt("Skirt%s" % n, 1.0, 0.66, 0.178, 0.138, 0.215, 0.17, [c1 if s > 0 else c2, M["lea_d"]], R["Leg" + n],
              a0=lo, a1=hi, cols=6, rows=3, folds=0.014, thick=0.012,
              matfn=lambda a, t: 1 if t > 0.82 else 0,
              hem=lambda a: -0.03 * abs(math.sin(a * 3)))
    belt("Belt", secs, 1.0, 0.045, 0.014, M["lea"], M["brass"], body)
    torso_strap("Baldric", secs, (0.15, 1.42), (-0.17, 1.02), 0.045, M["lea"], body, n=7, out=0.014)
    torso_strap("BaldricBack", secs, (0.15, 1.42), (-0.17, 1.02), 0.045, M["lea"], body, back=True, n=7, out=0.014)
    pouch("Pouch", (-0.17, -0.05, 0.94), M["lea"], M["lea_d"], body, size=(0.08, 0.055, 0.09), rotz=-0.6)
    g_export("a_tunic")


def build_a_leather():
    """Gibão de couro em placas sobrepostas, ombreiras de couro em duas lâminas, cinto largo, saiote de tiras e
    mangas de tecido por baixo. t1 = couro principal, t2 = couro escuro (bordas e ombreiras)."""
    P, R = g_rig("a_leather")
    M = g_mats()
    body = R["Body"]
    lea = gm("t1_leather", "#73471F", 0.8)
    lea_d = gm("t2_leather", "#3D2511", 0.85)
    secs = clothed_torso(P, R, lea, k=1.1, add=0.014, steps=(0.28, 0.52), keel=0.03)
    neck(R, M["skin"], collar=lea_d)
    sleeves(P, R, M["linen_d"], M["skin"], upto=1.0, k=1.04, cuff=lea_d)
    # ombreiras: duas lâminas de couro em degrau, inclinadas para fora
    for n, s in (("L", 1), ("R", -1)):
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.7), 0, math.cos(0.7)))
        pl = [dome("Arm%s_Pauldron" % n, sh + Vector((s * 0.01, 0, -0.005)), tilt, 0.105, 0.1, 0.065, lea_d,
                   R["Arm" + n], sides=8, lip=0.02)]
        S = limb_sections(P, s)
        c0, c1 = sample(S["upper"], 0.12), sample(S["upper"], 0.32)
        pl.append(loft("Arm%s_PauldronLame" % n, [sec(c0["c"], 0.082, 0.086), sec(c1["c"] + Vector((s * 0.006, 0, 0)),
                                                                                    0.088, 0.092)],
                       lea, R["Arm" + n], sides=8, chamfer=(0.0, 0.005)))
        join_objs("Arm%s_Pauldron" % n, pl)
    # bordas escuras (frisos de couro) na cava e no decote, costura central
    tor = bpy.data.objects["Torso"]
    split_x(tor, [lea_d], lambda c: 0 if abs(c.x) < 0.02 and c.y < 0 else None)
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    belt("Belt", secs, 1.0, 0.06, 0.02, lea_d, M["brass"], body)
    # saiote de tiras de couro em volta do quadril (metades nas pernas)
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.08, math.pi - 0.08) if s > 0 else (-math.pi + 0.08, -0.08)
        skirt("Tassets%s" % n, 0.985, 0.74, 0.185, 0.145, 0.215, 0.175, [lea, lea_d], R["Leg" + n], a0=lo, a1=hi,
              cols=8, rows=2, folds=0.0, thick=0.014, matfn=lambda a, t: 1 if t > 0.8 else 0,
              hem=lambda a: -0.035 * (1 if math.sin(a * 4) > 0 else 0))
    torso_strap("Strap", secs, (-0.13, 1.42), (0.15, 1.04), 0.035, lea_d, body, n=6, out=0.018)
    pouch("Pouch", (0.17, -0.06, 0.93), lea_d, lea, body, size=(0.08, 0.055, 0.09), rotz=0.6)
    g_export("a_leather")


def build_a_mail():
    """Cota de malha até o joelho (fileiras em degrau), fendas na frente e atrás, cinto largo de couro,
    gola acolchoada e mangas de malha até o punho. t1 = malha."""
    P, R = g_rig("a_mail")
    M = g_mats()
    body = R["Body"]
    ch = gm("t1_mail", "#7C838E", 0.72, 0.45)
    secs = clothed_torso(P, R, ch, k=1.09, add=0.012, steps=(0.15, 0.3, 0.45, 0.6, 0.75))
    neck(R, M["skin"], collar=M["lea"])
    sleeves(P, R, ch, M["skin"], upto=0.92, k=1.08, cuff=M["lea_d"])
    hips(R, ch)
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.12, math.pi - 0.12) if s > 0 else (-math.pi + 0.12, -0.12)
        skirt("Skirt%s" % n, 1.0, 0.56, 0.18, 0.14, 0.225, 0.18, [ch], R["Leg" + n], a0=lo, a1=hi, cols=7, rows=4,
              folds=0.008, thick=0.012, hem=lambda a: -0.025 * abs(math.cos(a)))
    belt("Belt", secs, 1.0, 0.065, 0.024, M["lea"], M["steel"], body)
    # tabardo curto de couro no peito (gibão sobre a malha): duas placas laterais com rebites
    pouch("Pouch", (-0.18, -0.04, 0.93), M["lea"], M["lea_d"], body, size=(0.08, 0.055, 0.09), rotz=-0.6)
    torso_strap("Baldric", secs, (0.14, 1.42), (-0.17, 1.0), 0.04, M["lea_d"], body, n=7, out=0.02)
    torso_strap("BaldricBack", secs, (0.14, 1.42), (-0.17, 1.0), 0.04, M["lea_d"], body, back=True, n=7, out=0.02)
    g_export("a_mail")


def build_a_surcoat():
    """Sobreveste sem mangas sobre cota de malha: painéis de frente e costas até o joelho com cruz no peito,
    espaldares de aço, cinto com fivela e malha nas mangas e na saia. t1 = sobreveste, t2 = cruz e barra."""
    P, R = g_rig("a_surcoat")
    M = g_mats()
    body = R["Body"]
    cl = gm("t1_surcoat", "#E3DCC6", 0.9)
    em = gm("t2_surcoat", "#A3202A", 0.85)
    secs = clothed_torso(P, R, cl, k=1.11, add=0.016)
    neck(R, M["skin"], collar=M["chain"])
    sleeves(P, R, M["chain"], M["skin"], upto=0.95, k=1.07, cuff=M["lea_d"])
    # espaldares (ombreira de aço em 2 lâminas)
    for n, s in (("L", 1), ("R", -1)):
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.72), 0, math.cos(0.72)))
        S = limb_sections(P, s)
        pl = [dome("Arm%s_Spaulder" % n, sh + Vector((s * 0.012, 0, -0.004)), tilt, 0.11, 0.105, 0.07, M["steel"],
                   R["Arm" + n], sides=10, lip=0.02)]
        c0, c1 = sample(S["upper"], 0.14), sample(S["upper"], 0.34)
        pl.append(loft("Arm%s_SpaulderLame" % n, [sec(c0["c"], 0.086, 0.09), sec(c1["c"] + Vector((s * 0.006, 0, 0)),
                                                                                    0.092, 0.096)],
                       M["steel"], R["Arm" + n], sides=10, chamfer=(0.0, 0.005)))
        pl.append(band("Arm%s_SpaulderTrim" % n, sec(sh + Vector((s * 0.012, 0, -0.004)) - tilt * 0.012, 0.11, 0.105),
                       tilt, 0.014, M["gold"], R["Arm" + n]))
        join_objs("Arm%s_Spaulder" % n, pl)
    # cruz no peito: placas finas sobre a frente do tronco
    fyc = front_y(torso_at(secs, 1.25), 0.004)
    cross = [loft("CrossV", [sec(on_torso(secs, 0.0, z, out=0.004), 0.026, 0.004) for z in (1.08, 1.2, 1.32, 1.4)],
                  em, body, sides=4, fwd=(0, -1, 0)),
             loft("CrossH", [sec(on_torso(secs, x, 1.3, out=0.005), 0.024, 0.004) for x in (-0.11, -0.05, 0.0, 0.05,
                                                                                             0.11)],
                  em, body, sides=4, fwd=(0, -1, 0))]
    join_objs("Cross", cross)
    hips(R, M["chain"])
    thighs(P, R, M["pants"])
    # malha por baixo (até o joelho) e painéis da sobreveste (frente e costas, abertos dos lados)
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.1, math.pi - 0.1) if s > 0 else (-math.pi + 0.1, -0.1)
        skirt("Mail%s" % n, 0.98, 0.6, 0.176, 0.136, 0.205, 0.165, [M["chain"]], R["Leg" + n], a0=lo, a1=hi, cols=6,
              rows=3, folds=0.006, thick=0.01)
        for side, (b0, b1) in (("F", (0.0, 0.95)), ("B", (math.pi - 0.95, math.pi))):
            a0_, a1_ = (b0, b1) if s > 0 else (-b1, -b0)
            skirt("Panel%s%s" % (side, n), 1.0, 0.5, 0.19, 0.152, 0.235, 0.2, [cl, em], R["Leg" + n], a0=a0_,
                  a1=a1_, cols=3, rows=4, folds=0.01, thick=0.012, matfn=lambda a, t: 1 if t > 0.86 else 0)
    belt("Belt", secs, 1.0, 0.05, 0.02, M["lea_d"], M["gold"], body)
    g_export("a_surcoat")


def build_a_robe():
    """Manto arcano até os tornozelos (aberto na frente para as pernas), mangas largas em sino, faixa na cintura
    com pontas caídas e murça (gola-capa) com friso dourado. t1 = manto, t2 = murça e faixa."""
    P, R = g_rig("a_robe")
    M = g_mats()
    body = R["Body"]
    rb = gm("t1_robe", "#3B3170", 0.92)
    rb2 = gm("t2_robe", "#231C45", 0.92)
    secs = clothed_torso(P, R, rb, k=1.08, add=0.012)
    neck(R, M["skin"])
    sleeves(P, R, rb, M["skin"], upto=0.9, k=1.06, flare=0.045, cuff=M["gold"])
    hips(R, rb)
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.22, math.pi) if s > 0 else (-math.pi, -0.22)
        skirt("Robe%s" % n, 1.0, 0.1, 0.18, 0.14, 0.27, 0.24, [rb, M["gold"]], R["Leg" + n], a0=lo, a1=hi, cols=7,
              rows=5, folds=0.016, thick=0.012, matfn=lambda a, t: 1 if t > 0.92 else 0)
    # faixa (sash) e pontas
    sash = [ring_at("Sash", secs, 0.97, 1.04, 0.02, rb2, body)]
    fy = front_y(torso_at(secs, 1.0), 0.02)
    sash.append(tbox("SashKnot", (0.05, fy - 0.006, 1.0), (0.05, 0.03, 0.06), rb2, bevel=0.01, parent=body))
    sash.append(strap("SashEnd0", (0.05, fy - 0.01, 0.98), (0.07, fy - 0.03, 0.7), 0.05, rb2, body, (0.1, -1, 0)))
    sash.append(strap("SashEnd1", (0.07, fy - 0.01, 0.98), (0.11, fy - 0.025, 0.76), 0.045, rb2, body, (0.3, -1, 0)))
    join_objs("Sash", sash)
    # murça: capinha sobre os ombros, recortada em pontas, com friso
    skirt("Mozzetta", 1.47, 1.3, 0.12, 0.1, 0.265, 0.185, [rb2, M["gold"]], body, cols=16, rows=2, folds=0.008,
          thick=0.014, cy=0.005, matfn=lambda a, t: 1 if t > 0.75 else 0,
          hem=lambda a: -0.045 * max(0.0, math.cos(a)) ** 2)
    g_export("a_robe")


# ================================================================== MÃOS
def build_g_bare():
    P, R = g_rig("g_bare")
    M = g_mats()
    for n, s in (("L", 1), ("R", -1)):
        fist("Arm" + n, P, s, M["skin"], R["Elbow" + n])
    g_export("g_bare")


def build_g_gloves():
    """Luvas de couro com punho largo virado. t1 = luva, t2 = punho."""
    P, R = g_rig("g_gloves")
    gl = gm("t1_gloves", "#6B4423", 0.8)
    gl2 = gm("t2_gloves", "#3A2412", 0.85)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        h = fist("Arm" + n, P, s, gl, elbow)
        F = S["fore"]
        cuff = loft("Arm%s_GloveCuff" % n, [grow([sample(F, 0.72)], 1.2, 0.012)[0], grow([sample(F, 1.0)], 1.06, 0.006)[0]],
                    gl2, elbow, sides=8, chamfer=(0.006, 0.0))
        join_objs("Arm%s_Hand" % n, [h, cuff])
    g_export("g_gloves")


def build_g_bracers():
    """Braçadeiras de couro com tiras e luvas sem dedos. t1 = braçadeira, t2 = luva/tiras."""
    P, R = g_rig("g_bracers")
    M = g_mats()
    br = gm("t1_bracers", "#5E6B3A", 0.8)
    br2 = gm("t2_bracers", "#3A2412", 0.85)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        h = fist("Arm" + n, P, s, br2, elbow)
        parts = [h, loft("Arm%s_Bracer" % n, grow(span(F, 0.25, 0.95), 1.18, 0.01), br, elbow, chamfer=(0.006, 0.006))]
        fdown = (F[-1]["c"] - F[0]["c"]).normalized()
        for k, t in enumerate((0.42, 0.72)):
            parts.append(band("Arm%s_BracerStrap%d" % (n, k), grow([sample(F, t)], 1.18, 0.012)[0], fdown, 0.018, br2,
                              elbow, sides=8, out=0.004))
        join_objs("Arm%s_Hand" % n, parts)
    g_export("g_bracers")


# ================================================================== PÉS
def _shin_hose(P, R, n, s, material):
    S = limb_sections(P, s)
    return loft("Leg%s_Shin" % n, grow(S["shin"], 1.05, 0.004), material, R["Knee" + n])


def _shoe(P, R, n, s, upper, sole, k=1.08, add=0.006, top=None):
    S = limb_sections(P, s)
    knee = R["Knee" + n]
    K = mirror(P["knee"], s)
    ft = grow(S["foot"], k, add)
    parts = [loft("Leg%s_Foot" % n, ft, upper, knee, fwd=(0, 0, 1), chamfer=(0.01, 0.012))]
    heel_y, toe_y = ft[0]["c"].y, ft[-1]["c"].y
    parts.append(tbox("Leg%s_Sole" % n, (K.x, (heel_y + toe_y) / 2 - 0.006, 0.012),
                      (0.13 * P["ft"], heel_y - toe_y + 0.07, 0.024), sole, bevel=0.006, parent=knee))
    return parts


def build_f_shoes():
    """Sem botas: sapato baixo de couro com tira no tornozelo, meia/calça na canela (tp_)."""
    P, R = g_rig("f_shoes")
    M = g_mats()
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        hose = _shin_hose(P, R, n, s, M["pants"])
        parts = _shoe(P, R, n, s, M["lea"], M["lea_d"])
        parts.append(loft("Leg%s_Ankle" % n, grow(span(S["shin"], 0.86, 1.0), 1.14, 0.008), M["lea"], R["Knee" + n]))
        parts.append(band("Leg%s_AnkleStrap" % n, grow([sample(S["shin"], 0.9)], 1.14, 0.01)[0],
                          S["shin"][-1]["c"] - S["shin"][0]["c"], 0.014, M["lea_d"], R["Knee" + n], sides=8))
        join_objs("Leg%s_Shoe" % n, parts)
    g_export("f_shoes")


def build_f_boots():
    """Botas de cano alto com dobra no topo e tira com fivela. t1 = bota, t2 = dobra e sola."""
    P, R = g_rig("f_boots")
    M = g_mats()
    bt = gm("t1_boots", "#6B4423", 0.8)
    bt2 = gm("t2_boots", "#3A2412", 0.85)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        knee = R["Knee" + n]
        _shin_hose(P, R, n, s, M["pants"])
        dn = S["shin"][-1]["c"] - S["shin"][0]["c"]
        parts = _shoe(P, R, n, s, bt, bt2)
        parts.append(loft("Leg%s_Shaft" % n, grow(span(S["shin"], 0.2, 1.0), 1.14, 0.01), bt, knee))
        top = grow([sample(S["shin"], 0.16)], 1.26, 0.016)[0]
        parts.append(loft("Leg%s_Fold" % n, [top, dict(grow([sample(S["shin"], 0.3)], 1.18, 0.014)[0])], bt2, knee,
                          sides=8, chamfer=(0.004, 0.0)))
        parts.append(band("Leg%s_BootStrap" % n, grow([sample(S["shin"], 0.78)], 1.15, 0.012)[0], dn, 0.016, bt2,
                          knee, sides=8))
        c = sample(S["shin"], 0.8)
        parts.append(tbox("Leg%s_BootBuckle" % n, (c["c"].x + s * 0.05, c["c"].y - 0.02, c["c"].z - 0.02),
                          (0.01, 0.026, 0.026), M["brass"], bevel=0.002, parent=knee))
        join_objs("Leg%s_Boot" % n, parts)
    g_export("f_boots")


def build_f_plated():
    """Botas reforçadas: bota de couro com greva de aço na frente da canela, joelheira com asa e biqueira de aço.
    t1 = couro, t2 = aço."""
    P, R = g_rig("f_plated")
    M = g_mats()
    bt = gm("t1_plated", "#5A3A1E", 0.8)
    st = gm("t2_plated", "#A9B1BE", 0.35, 0.85)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        knee = R["Knee" + n]
        K = mirror(P["knee"], s)
        _shin_hose(P, R, n, s, M["pants"])
        parts = _shoe(P, R, n, s, bt, M["lea_d"])
        parts.append(loft("Leg%s_Shaft" % n, grow(span(S["shin"], 0.12, 1.0), 1.14, 0.01), bt, knee))
        parts.append(loft("Leg%s_Greave" % n, grow(span(S["shin"], 0.1, 0.85), 1.24, 0.016, keel=0.14), st, knee,
                          phase=0, arc=2.4, thick=0.01, chamfer=(0.0, 0.0)))
        parts.append(loft("Leg%s_Poleyn" % n, [sec((K.x, K.y - 0.03, K.z + 0.01), 0.07, 0.074),
                                               sec((K.x, K.y - 0.074, K.z), 0.062, 0.066),
                                               sec((K.x, K.y - 0.098, K.z - 0.008), 0.04, 0.044)],
                          st, knee, fwd=(0, 0, 1), chamfer=(0.0, 0.008)))
        parts.append(wing("Leg%s_PoleynWing" % n, (K.x + s * 0.064, K.y - 0.035, K.z), 0.07, 0.09, 0.008, st, knee))
        ft = grow(S["foot"], 1.13, 0.012)
        parts.append(loft("Leg%s_ToeCap" % n, [dict(x) for x in ft[2:]], st, knee, fwd=(0, 0, 1), chamfer=(0.0, 0.01)))
        for k, t in enumerate((0.3, 0.7)):
            parts.append(band("Leg%s_GreaveStrap%d" % (n, k), grow([sample(S["shin"], t)], 1.16, 0.012)[0],
                              S["shin"][-1]["c"] - S["shin"][0]["c"], 0.014, M["lea_d"], knee, sides=8))
        join_objs("Leg%s_Boot" % n, parts)
    g_export("f_plated")


GEAR = [(n, globals()["build_" + n]) for n in (
    "h_bare", "h_hood", "h_cap", "h_kettle", "h_nasal", "h_great", "h_wizard",
    "a_shirt", "a_tunic", "a_leather", "a_mail", "a_surcoat", "a_robe",
    "g_bare", "g_gloves", "g_bracers",
    "f_shoes", "f_boots", "f_plated")]
