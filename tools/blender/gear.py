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


# ------------------------------------------------------------------ sombreamento assado (AO por vértice)
# As referências têm sombra suave nas dobras (sob cinto, ombreiras, entre placas). Assamos oclusão de ambiente
# do Cycles na cor por vértice ("Col" -> COLOR_0); o jogo multiplica pelo albedo (KnightLook liga
# vertex_color_use_as_albedo). Antes do assado, o corpo padrão das outras regiões entra como oclusor
# (cabeça, mãos, pés, tronco), e sai antes de exportar.
AO_DIST = 0.11          # alcance da oclusão (m): dobras e sobreposições, não o corpo inteiro
AO_FLOOR = 0.36         # cor mínima (fundo da dobra)
AO_GAMMA = 1.35


def _occluders(style, P, R, M):
    """Corpo padrão das regiões que o estilo não cobre, só para fazer sombra no assado."""
    before = set(scn.objects)
    kind = style[0]
    if kind != "h":
        plain_head(R, M)
    if kind != "a":
        parts_a_shirt(P, R, M)
    if kind != "g":
        for n, s in (("L", 1), ("R", -1)):
            fist("Occ" + n, P, s, M["skin"], R["Elbow" + n])
    if kind != "f":
        parts_f_shoes(P, R, M)
    return [o for o in scn.objects if o not in before]


def bake_ao(targets, occ):
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = 48
    scn.cycles.device = 'CPU'
    if scn.world is None:
        scn.world = bpy.data.worlds.new("GearWorld")
    scn.world.light_settings.distance = AO_DIST
    vl = scn.view_layers[0]
    for o in scn.objects:
        o.select_set(False, view_layer=vl)
    for o in targets:
        me = o.data
        a = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
        me.color_attributes.active_color = a
        o.select_set(True, view_layer=vl)
    vl.objects.active = targets[0]
    with bpy.context.temp_override(scene=scn, view_layer=vl, active_object=targets[0],
                                   selected_objects=targets, selected_editable_objects=targets):
        bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
    for o in targets:
        for d in o.data.color_attributes["Col"].data:
            v = max(0.0, min(1.0, d.color[0])) ** AO_GAMMA
            c = AO_FLOOR + (1 - AO_FLOOR) * v
            d.color = (c, c, c, 1.0)
    for o in occ:
        bpy.data.objects.remove(o, do_unlink=True)


def g_export(style, P=None, R=None):
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    if P is not None and targets:
        occ = _occluders(style, P, R, g_mats())
        bake_ao(targets, occ)
    export("gear/" + style, export_vertex_color='ACTIVE')


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
        steel=gm("g_steel", "#A9B1BE", 0.45, 0.65),
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
          folds=0.012, thick=0.012, cy=0.0, matfn=None, hem=None, trim=None, border=0.0, hem_band=0.0, lines=0):
    """Saia/barra em anel (a de 0 = frente, + para +X). Aberta se a1 - a0 < 2pi (fendas, metades presas às pernas).
    matfn(a, t) -> índice do material por face; hem(a) -> deslocamento da barra (recorte, ponta).
    trim = material do debrum: faixa de largura `border` (m) nas bordas abertas e `hem_band` (m) na barra.
    lines = n: n fileiras com uma linha fina (material 1) no pé de cada uma (cota de malha)."""
    closed = a1 - a0 >= 2 * math.pi - 1e-3
    angs = [a0 + (a1 - a0) * j / cols for j in range(cols if closed else cols + 1)]
    if border and not closed:
        bw = border / max(min(rx0, rx1), 0.05)
        if bw < (a1 - a0) / cols * 0.8:
            angs = [angs[0], angs[0] + bw] + angs[1:-1] + [angs[-1] - bw, angs[-1]]
    ts = [i / rows for i in range(rows + 1)]
    line_rows = set()
    if lines:
        ts = [0.0]
        for k in range(lines):
            ts += [(k + 0.8) / lines, (k + 1.0) / lines]
            line_rows.add(len(ts) - 2)
    if hem_band:
        hb = hem_band / max(abs(z0 - z1), 0.05)
        if hb < 1.0 / rows * 0.8:
            ts = ts[:-1] + [1.0 - hb, 1.0]
    mats = list(mats) + ([trim] if trim is not None else [])
    ti = len(mats) - 1
    ncol = len(angs)
    bm = bmesh.new()
    grid = []
    for i, t in enumerate(ts):
        z = z0 + (z1 - z0) * t
        rx, ry = rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t
        row = []
        for j, a in enumerate(angs):
            edge = (not closed) and (j <= (1 if border else 0) or j >= ncol - (2 if border else 1))
            off = 0.0 if edge else folds * t * (1 if j % 2 else -1)
            zz = z + (hem(a) if hem and (i == len(ts) - 1 or (hem_band and i == len(ts) - 2)) else 0.0)
            row.append(bm.verts.new((math.sin(a) * (rx + off), cy - math.cos(a) * (ry + off), zz)))
        grid.append(row)
    for i in range(len(ts) - 1):
        for j in range(ncol if closed else ncol - 1):
            k = (j + 1) % ncol
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][k], grid[i][k]))
            am = (angs[j] + angs[k if k else j]) / 2
            if matfn:
                f.material_index = matfn(am, (ts[i] + ts[i + 1]) / 2)
            if i in line_rows:
                f.material_index = 1
            if trim is not None:
                if (border and not closed and (j == 0 or j == ncol - 2)) or (hem_band and i == len(ts) - 2):
                    f.material_index = ti
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


def arc_panel(name, secs, arc, material, parent, back=False, thick=0.012, trim=None, tw=0.016, hem=True):
    """Placa curva (peitoral, painel de tabardo) na frente (ou nas costas) com debrum nas laterais e na barra."""
    fwd = (0, 1, 0) if back else (0, -1, 0)
    parts = [loft(name, secs, material, parent, sides=8, phase=0, axis=ZUP, fwd=fwd, arc=arc, thick=thick)]
    if trim is not None:
        fr = _frames(secs, ZUP, fwd)
        edges = [_ring(sc, side, f, 1, 0, arc, 0.0) for sc, (t, side, f) in zip(secs, fr)]
        for e in (0, 1):
            pts = [r[e] for r in edges]
            out = [Vector((p.x - sc["c"].x, p.y - sc["c"].y, 0)).normalized() for p, sc in zip(pts, secs)]
            parts.append(loft(name + "Edge%d" % e, [sec(p + o * 0.003, tw / 2, thick * 0.5 + 0.003)
                                                     for p, o in zip(pts, out)], trim, parent, sides=4,
                              fwd=tuple(out[len(out) // 2])))
        if hem:
            b = secs[0]
            parts.append(loft(name + "Hem", [dict(b, rx=b["rx"] + 0.004, ry=b["ry"] + 0.004),
                                             dict(b, c=b["c"] + Vector((0, 0, tw)), rx=b["rx"] + 0.004,
                                                  ry=b["ry"] + 0.004)], trim, parent, sides=8, phase=0, axis=ZUP,
                              fwd=fwd, arc=arc, thick=thick + 0.004))
    return join_objs(name, parts)


def rivets(name, pts, material, parent, r=0.007):
    return join_objs(name, [tbox("%s%d" % (name, k), p, (r, r, r), material, bevel=r * 0.3, parent=parent)
                            for k, p in enumerate(pts)])


def torso_ring(secs, z, add=0.0, **over):
    s = grow([torso_at(secs, z)], 1.0, add)[0]
    s.update(over)
    return s


def stripes(ob, mat_dark):
    """Linhas finas escuras entre as fileiras de elos: as faces do degrau (viradas para baixo) da malha em degraus."""
    base = len(ob.data.materials)
    ob.data.materials.append(mat_dark)
    for p in ob.data.polygons:
        if p.normal.z < -0.45:
            p.material_index = base
    return ob


def dome_rivets(name, base, tilt, r, s, material, parent, angs=(-0.7, 0.0, 0.7), lift=0.012, size=0.008):
    """Rebites na borda de uma calota (ombreira): em volta do eixo tilt, do lado de fora (x = s)."""
    t = Vector(tilt).normalized()
    out = Vector((s, 0, 0)) - t * t.x * s
    out.normalize()
    side = t.cross(out).normalized()
    pts = [Vector(base) + t * lift + (out * math.cos(a) + side * math.sin(a)) * (r + 0.004) for a in angs]
    return rivets(name, pts, material, parent, r=size)


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


def sleeves(P, R, material, skin, upto=1.0, k=1.04, add=0.006, cap=True, cuff=None, flare=0.0, cap_mat=None,
            steps=0):
    """Manga: braço inteiro e antebraço até `upto` (fração); o resto do antebraço é pele.
    flare alarga a boca da manga (mantos); cuff = material da barra da manga."""
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        arm, elbow = R["Arm" + n], R["Elbow" + n]
        U = grow(span(S["upper"], 0.1, 1.0), k, add)
        if steps:
            U = stepped(U, [(i + 1) / (steps + 1) for i in range(steps)], drop=0.95, eps=0.008)
        up = [loft("Arm%s_Upper" % n, U, material, arm)]
        if cap:
            sh = mirror(P["shoulder"], s)
            tilt = Vector((s * math.sin(1.0), 0, math.cos(1.0)))
            up.append(dome("Arm%s_Cap" % n, sh + Vector((-s * 0.014, 0, -0.026)), tilt, 0.062, 0.066, 0.05,
                           cap_mat or material, arm, sides=8))
        join_objs("Arm%s_Upper" % n, up)
        F = grow(span(S["fore"], 0.0, upto), k, add)
        if steps:
            F = stepped(F, [(i + 1) / (steps + 1) for i in range(steps)], drop=0.95, eps=0.008)
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
    g_export("h_bare", P, R)


def build_h_hood():
    """Capuz de tecido: volume solto em volta da cabeça caindo para trás em ponta, abertura do rosto com
    borda grossa e forro escuro, gola sobre os ombros. t1 = tecido, t2 = forro/borda."""
    P, R = g_rig("h_hood")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    cl = gm("t1_hood", "#4E5E35", 0.95)
    cl_d = gm("t2_hood", "#2F3A20", 0.95)
    lin = gm("t1d_hood", "#25301A", 0.95)
    ARC = 4.35
    # (dz, rx, ry, recuo y): o capuz infla nas laterais e o alto pende para trás
    rows = [(-0.05, 0.15, 0.155, 0.02), (0.03, 0.142, 0.158, 0.02), (0.11, 0.138, 0.16, 0.022),
            (0.18, 0.13, 0.156, 0.028), (0.235, 0.108, 0.14, 0.04), (0.275, 0.07, 0.11, 0.06),
            (0.29, 0.03, 0.06, 0.09)]
    secs = [sec((0, cy, HEAD_CHIN + dz), rx, ry) for dz, rx, ry, cy in rows]
    parts = [loft("Hood", secs, cl, head, sides=12, phase=0, fwd=(0, 1, 0), axis=ZUP, arc=ARC, thick=0.022)]
    # forro escuro logo por dentro (aparece em volta do rosto)
    inner = [sec((0, cy + 0.004, HEAD_CHIN + dz), rx - 0.02, ry - 0.02) for dz, rx, ry, cy in rows[:5]]
    parts.append(loft("HoodLining", inner, lin, head, sides=12, phase=0, fwd=(0, 1, 0), axis=ZUP, arc=ARC + 0.5,
                      thick=0.008))
    # costuras: gomos do capuz (tiras finas escuras do alto até a gola)
    for k, ang in enumerate((-2.0, -1.0, 0.0, 1.0, 2.0)):
        a = math.pi + ang * 0.42
        pts = [Vector((math.sin(a) * (rx + 0.003), cy - math.cos(a) * (ry + 0.003), HEAD_CHIN + dz))
               for dz, rx, ry, cy in rows[:6]]
        parts.append(loft("HoodSeam%d" % k, [sec(q, 0.005, 0.004) for q in pts], lin, head, sides=4))
    # borda grossa contornando a abertura (laterais e arco da testa)
    a = (2 * math.pi - ARC) / 2
    side = [Vector((rx * math.sin(a), cy - ry * math.cos(a), HEAD_CHIN + dz)) for dz, rx, ry, cy in rows[:5]]
    for sgn, nm in ((1, "L"), (-1, "R")):
        pts = [Vector((sgn * p.x, p.y, p.z)) for p in side]
        parts.append(loft("HoodRim" + nm, [sec(p, 0.022, 0.018) for p in pts], cl_d, head, sides=6))
    top = side[-1]
    arch = [Vector((top.x * math.cos(t), top.y - 0.012 * math.sin(t) ** 2, top.z + 0.03 * math.sin(t)))
            for t in (0.0, 0.5, 1.0, 1.5708, 2.14, 2.64, 3.1416)]
    parts.append(loft("HoodRimTop", [sec(p, 0.022, 0.018) for p in arch], cl_d, head, sides=6))
    # ponta (liripipe) caindo nas costas
    parts.append(loft("HoodTail", [sec((0, 0.1, HEAD_CHIN + 0.27), 0.04, 0.035),
                                   sec((0, 0.175, HEAD_CHIN + 0.2), 0.03, 0.026),
                                   sec((0, 0.21, HEAD_CHIN + 0.06), 0.018, 0.016),
                                   sec((0, 0.215, HEAD_CHIN - 0.06), 0.006, 0.006)], cl, head, sides=6))
    # gola sobre os ombros: abre em V na frente, ponta nas costas
    parts.append(skirt("HoodCowl", HEAD_CHIN - 0.04, 1.33, 0.15, 0.15, 0.27, 0.2, [cl], head, cols=14, rows=2,
                       folds=0.012, thick=0.016, cy=0.02, trim=cl_d, hem_band=0.02, hem=lambda a: 0.07 * max(0.0, math.cos(a)) ** 2 -
                       0.05 * max(0.0, -math.cos(a)) ** 2))
    join_objs("Hood", parts)
    g_export("h_hood", P, R)


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
    # abas das orelhas: placa de couro com borda escura caindo até a mandíbula
    for sg, nm in ((1, "L"), (-1, "R")):
        parts.append(tbox("CapFlap" + nm, (sg * 0.118, 0.006, HEAD_CHIN + 0.075), (0.016, 0.085, 0.11), lea,
                          bottom=(1.0, 0.8), bevel=0.006, rot=(0, sg * 0.1, 0), parent=head))
        parts.append(tbox("CapFlapEdge" + nm, (sg * 0.12, 0.006, HEAD_CHIN + 0.022), (0.02, 0.07, 0.014), lea_d,
                          bevel=0.003, rot=(0, sg * 0.1, 0), parent=head))
    # tira do queixo
    parts.append(loft("CapStrap", [sec((0.1, 0.0, HEAD_CHIN + 0.05), 0.012, 0.004),
                                   sec((0.06, -0.06, HEAD_CHIN - 0.005), 0.012, 0.004),
                                   sec((0.0, -0.075, HEAD_CHIN - 0.012), 0.012, 0.004),
                                   sec((-0.06, -0.06, HEAD_CHIN - 0.005), 0.012, 0.004),
                                   sec((-0.1, 0.0, HEAD_CHIN + 0.05), 0.012, 0.004)], lea_d, head, sides=4,
                      fwd=(0, 0, -1)))
    join_objs("Cap", parts)
    g_export("h_cap", P, R)


def mail_coif(name, head, chain, open_face=True, bottom=1.36):
    """Cota de malha da cabeça até os ombros (anéis em degrau imitam as fileiras de elos)."""
    rows = [(0.2, 0.112, 0.126), (0.12, 0.118, 0.132), (0.04, 0.114, 0.13), (-0.03, 0.105, 0.12)]
    secs = head_shell_secs(rows, cy=0.012)
    chd = gm("g_chain_d", "#4A4F57", 0.8, 0.4)
    co = loft(name, stepped(secs, (0.33, 0.66), drop=0.96, eps=0.008), chain, head, sides=12, phase=0, fwd=(0, 1, 0),
              axis=(0, 0, -1), arc=4.3 if open_face else None, thick=0.014)
    parts = [stripes(co, chd)]
    parts.append(skirt(name + "Mantle", HEAD_CHIN - 0.02, bottom, 0.11, 0.122, 0.24, 0.19, [chain, chd], head,
                       cols=14, rows=3, folds=0.006, thick=0.012, cy=0.012, lines=4, trim=gm("g_bronze", "#A8702E",
                                                                                              0.5, 0.6),
                       hem_band=0.016, hem=lambda a: 0.03 * math.cos(a) ** 2))
    return parts


def build_h_kettle():
    """Chapéu de ferro (aba larga) sobre cota de malha com o rosto aberto."""
    P, R = g_rig("h_kettle")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_kettle", "#8E96A3", 0.5, 0.6)
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
    g_export("h_kettle", P, R)


def build_h_nasal():
    """Elmo cônico de nasal (gomos rebitados), com cota de malha pendendo da borda e o rosto aberto."""
    P, R = g_rig("h_nasal")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_nasal", "#A9B1BE", 0.5, 0.6)
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
    g_export("h_nasal", P, R)


def build_h_great():
    """Elmo fechado (balde): topo achatado, fenda dos olhos em degrau, respiros e cruz dourada na frente."""
    P, R = g_rig("h_great")
    M = g_mats()
    head = R["Head"]
    st = gm("t1_great", "#8D95A2", 0.5, 0.6)
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
    for i in range(3):                          # respiros em grade nas duas faces, abaixo da fenda
        for j in range(4):
            for sg in (1, -1):
                a = sg * (0.36 + 0.13 * i)
                z = 1.635 - j * 0.03
                p = Vector((math.sin(a) * 0.132 * 1.0, y0 - math.cos(a) * 0.142 * 1.1, z))
                parts.append(tbox("GreatBreath%d%d%s" % (i, j, "L" if sg > 0 else "R"), p, (0.013, 0.008, 0.013),
                                  M["slit"], rot=(0, 0, a), parent=head))
    # saia do elmo assentando nos ombros (placa em degrau)
    parts.append(loft("GreatSkirt", [sec((0, y0, 1.515), 0.114, 0.122), sec((0, y0, 1.47), 0.16, 0.15),
                                     sec((0, y0 + 0.004, 1.44), 0.19, 0.165)], st, head, sides=12, phase=0,
                      axis=ZUP, chamfer=(0.006, 0.0)))
    parts.append(rivets("GreatRivet", [Vector((math.sin(a) * 0.127, y0 - math.cos(a) * 0.137, 1.79))
                                       for a in [k * math.pi / 6 + math.pi / 12 for k in range(12)]],
                        M["brass"], head, r=0.009))
    gold = gm("t2_great", "#E6B544", 0.35, 0.8)
    fy = y0 - 0.142 * 1.08 * 1.1 - 0.004
    parts.append(loft("GreatCrossV", [sec((0, fy + 0.012, 1.545), 0.013, 0.006), sec((0, fy, 1.6), 0.014, 0.006),
                                      sec((0, fy + 0.002, 1.665), 0.014, 0.006)], gold, head, sides=4))
    parts.append(loft("GreatCrossT", [sec((0, fy + 0.006, 1.72), 0.014, 0.006), sec((0, fy + 0.004, 1.79), 0.014, 0.006)],
                      gold, head, sides=4))
    parts.append(band("GreatBrowTrim", sec((0, y0, 1.712), 0.135, 0.148, fr=1.07, keel=0.09), ZUP, 0.012, gold, head,
                      sides=12, phase=0, arc=2.6, out=0.002))
    parts.append(band("GreatRimTrim", sec((0, y0, 1.44), 0.19, 0.165), ZUP, 0.014, gold, head, sides=12, phase=0,
                      out=0.003))
    join_objs("Great", parts)
    g_export("h_great", P, R)


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
    g_export("h_wizard", P, R)


# ================================================================== PEITO
def build_a_shirt():
    """Sem armadura: camisa de linho solta com barra debruada e fendas, mangas arregaçadas, gola com cordão,
    cinto simples com ponta longa e bolsa; calça."""
    P, R = g_rig("a_shirt")
    parts_a_shirt(P, R, g_mats())
    g_export("a_shirt", P, R)


def parts_a_shirt(P, R, M):
    body = R["Body"]
    secs = clothed_torso(P, R, M["linen"], k=1.05, add=0.008)
    neck(R, M["skin"], collar=M["linen_d"], collar_z=1.45)
    fy = front_y(torso_at(secs, 1.42), 0.002)
    tbox("ShirtV", (0, fy + 0.004, 1.405), (0.06, 0.006, 0.075), M["skin"], bottom=(0.1, 1), parent=body)
    for k, z in enumerate((1.425, 1.395, 1.365)):
        torso_strap("ShirtLace%d" % k, secs, (0.024, z), (-0.024, z - 0.012), 0.006, M["lea_d"], body, n=2, out=0.005)
    sleeves(P, R, M["linen"], M["skin"], upto=0.45, k=1.08, cuff=M["linen_d"])
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    belt("Belt", secs, 1.0, 0.04, 0.02, M["lea"], M["brass"], body)
    for n, s in (("L", 1), ("R", -1)):     # barra solta por fora da calça, fendas nos lados
        front = (0.0, math.pi / 2 - 0.08) if s > 0 else (-math.pi / 2 + 0.08, 0.0)
        back = (math.pi / 2 + 0.08, math.pi) if s > 0 else (-math.pi, -math.pi / 2 - 0.08)
        for side, (a0, a1) in (("F", front), ("B", back)):
            skirt("ShirtHem%s%s" % (side, n), 1.0, 0.86, 0.178, 0.135, 0.19, 0.148, [M["linen"]], R["Leg" + n],
                  a0=a0, a1=a1, cols=3, rows=1, folds=0.006, thick=0.01, trim=M["linen_d"], border=0.012,
                  hem_band=0.016)
    pouch("Pouch", (0.15, -0.07, 0.94), M["lea"], M["lea_d"], body, size=(0.07, 0.05, 0.08), rotz=0.5)


def build_a_tunic():
    """Túnica até o meio da coxa em duas cores (heráldica) com debrum ocre na gola, no peitilho com cordões,
    nos punhos, nas fendas e na barra recortada; bandoleira com argola, cinto duplo com bolsa e faca.
    t1 = metade esquerda, t2 = metade direita."""
    P, R = g_rig("a_tunic")
    M = g_mats()
    body = R["Body"]
    c1 = gm("t1_tunic", "#8E2A22", 0.92)
    c2 = gm("t2_tunic", "#2F4A3A", 0.92)
    tr = gm("g_trim_ochre", "#B8893F", 0.85)
    secs = clothed_torso(P, R, c1, k=1.07, add=0.01)
    split_x(bpy.data.objects["Torso"], [c2], lambda c: 0 if c.x < 0 else None)
    neck(R, M["skin"], collar=tr)
    torso_strap("Placket", secs, (0.0, 1.455), (0.0, 1.27), 0.034, tr, body, n=4, out=0.004)
    for k, z in enumerate((1.42, 1.375, 1.33)):
        torso_strap("Lace%d" % k, secs, (0.03, z), (-0.03, z - 0.014), 0.007, M["lea_d"], body, n=2, out=0.008)
    sleeves(P, R, c1, M["skin"], upto=1.0, k=1.06, cuff=tr)
    for part in ("Upper", "Fore"):
        split_x(bpy.data.objects["ArmR_%s" % part], [c2], lambda c: 0)
    for n, s in (("L", 1), ("R", -1)):       # costura do ombro
        U = limb_sections(P, s)["upper"]
        band("Arm%s_Seam" % n, grow([sample(U, 0.2)], 1.08, 0.008)[0], U[-1]["c"] - U[0]["c"], 0.014, tr,
             R["Arm" + n], sides=8, out=0.003)
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.05, math.pi - 0.05) if s > 0 else (-math.pi + 0.05, -0.05)
        skirt("Skirt%s" % n, 1.0, 0.64, 0.178, 0.138, 0.218, 0.172, [c1 if s > 0 else c2], R["Leg" + n],
              a0=lo, a1=hi, cols=6, rows=2, folds=0.014, thick=0.012, trim=tr, border=0.016, hem_band=0.022,
              hem=lambda a: -0.028 * abs(math.sin(a * 3)))
    belt("Belt", secs, 1.0, 0.045, 0.022, M["lea"], M["brass"], body)
    # cinto de quadril caído na diagonal, com bolsa e faca
    hb = [loft("HipBelt", [sec((0.0, 0.0, 0.975), 0.205, 0.168), sec((0.0, 0.0, 0.955), 0.207, 0.17)],
               M["lea_d"], body, sides=12, phase=0, axis=(0.12, 0, 1))]
    hb.append(tbox("HipBeltBuckle", (0.12, -0.17, 0.965), (0.035, 0.012, 0.03), M["brass"], bevel=0.003,
                   rot=(0, 0, 0.6), parent=body))
    join_objs("HipBelt", hb)
    pouch("Pouch", (-0.19, -0.05, 0.92), M["lea"], M["lea_d"], body, size=(0.08, 0.055, 0.09), rotz=-0.9)
    kn = [tbox("KnifeSheath", (0.2, 0.06, 0.88), (0.03, 0.02, 0.15), M["lea_d"], bottom=(0.5, 0.7), bevel=0.004,
               rot=(0, 0.25, 0), parent=body),
          limb("KnifeGrip", (0.215, 0.06, 0.95), (0.226, 0.06, 1.0), 0.011, 0.011, M["lea"], sides=6, parent=body),
          tbox("KnifeGuard", (0.215, 0.06, 0.953), (0.012, 0.04, 0.008), M["brass"], parent=body)]
    join_objs("Knife", kn)
    torso_strap("Baldric", secs, (0.15, 1.43), (-0.17, 1.02), 0.045, M["lea"], body, n=7, out=0.016)
    torso_strap("BaldricBack", secs, (0.15, 1.43), (-0.17, 1.02), 0.045, M["lea"], body, back=True, n=7, out=0.016)
    p = on_torso(secs, 0.09, 1.355, out=0.02)
    limb("BaldricRing", p + Vector((0, 0, -0.012)), p + Vector((0, 0, 0.012)), 0.018, 0.018, M["brass"], sides=8,
         parent=body)
    g_export("a_tunic", P, R)


def build_a_leather():
    """Armadura de couro em camadas: gibão escuro por baixo, peitoral e espaldar moldados com debrum,
    duas lâminas na barriga, fivelas nos flancos, ombreiras em três lâminas rebitadas, braçal e avambraço,
    cinto largo, bandoleira e saiote de painéis separados (um com placa rebitada).
    t1 = couro, t1d = gibão, t2 = debrum/tiras."""
    P, R = g_rig("a_leather")
    M = g_mats()
    body = R["Body"]
    lea = gm("t1_leather", "#8A5A2B", 0.7)
    lead = gm("t1d_leather", "#4E3218", 0.85)
    tr = gm("t2_leather", "#3D2511", 0.85)
    secs = clothed_torso(P, R, lead, k=1.07, add=0.01)
    neck(R, M["skin"], collar=tr)
    zs = (1.2, 1.27, 1.34, 1.4, 1.445)
    arc_panel("Breast", [torso_ring(secs, z, 0.016, fr=1.1, keel=0.06 if z < 1.42 else 0.0) for z in zs], 3.2, lea,
              body, trim=tr, thick=0.016, tw=0.022)
    arc_panel("BackPlate", [torso_ring(secs, z, 0.016) for z in zs], 2.8, lea, body, back=True, trim=tr, thick=0.016,
              tw=0.022)
    band("BreastTop", torso_ring(secs, 1.43, 0.018, fr=1.1), ZUP, 0.016, tr, body, sides=12, phase=0, out=0.002)
    lames = []
    for i, (za, zb, add) in enumerate(((1.13, 1.215, 0.016), (1.06, 1.14, 0.02), (1.0, 1.07, 0.024))):
        a, b = torso_ring(secs, za, add), torso_ring(secs, zb, add - 0.004)
        lames.append(loft("Lame%d" % i, [a, b], lea if i % 2 else lead, body, sides=12, phase=0, axis=ZUP,
                          chamfer=(0.004, 0.004)))
        lames.append(band("LameTrim%d" % i, a, ZUP, 0.012, tr, body, sides=12, phase=0, out=0.002))
    join_objs("Lames", lames)
    side = []
    for sg in (1, -1):              # fivelas nos flancos ligando peitoral e espaldar
        for k, z in enumerate((1.22, 1.33)):
            p = surf(torso_at(secs, z), sg * math.pi / 2, 0.024)
            side.append(tbox("SideStrap%d%d" % (sg + 1, k), p, (0.012, 0.07, 0.02), tr, parent=body))
            side.append(tbox("SideBuckle%d%d" % (sg + 1, k), p + Vector((sg * 0.006, -0.012, 0)),
                             (0.008, 0.022, 0.026), M["steel"], bevel=0.002, parent=body))
    join_objs("SideStraps", side)
    sleeves(P, R, M["linen_d"], M["skin"], upto=1.0, k=1.04, cuff=tr)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        arm, elbow = R["Arm" + n], R["Elbow" + n]
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.75), 0, math.cos(0.75)))
        base = sh + Vector((s * 0.01, 0, -0.004))
        U = S["upper"]
        udir = -(U[-1]["c"] - U[0]["c"])
        pl = [dome("Arm%s_Pauldron" % n, base, tilt, 0.108, 0.104, 0.07, lea, arm, sides=10, lip=0.02)]
        pl.append(band("Arm%s_PauldronTrim" % n, sec(base - tilt * 0.02, 0.1, 0.097), tilt, 0.014, tr, arm, sides=10))
        for i, (t0, t1, a0, a1) in enumerate(((0.1, 0.26, 0.09, 0.098), (0.22, 0.38, 0.084, 0.092))):
            c0, c1 = sample(U, t0), sample(U, t1)
            lo = sec(c1["c"] + Vector((s * 0.006, 0, 0)), a1, a1 + 0.008)
            pl.append(loft("Arm%s_Lame%d" % (n, i), [sec(c0["c"], a0, a0 + 0.008), lo], lea, arm, sides=10,
                           chamfer=(0.0, 0.005)))
            pl.append(band("Arm%s_LameTrim%d" % (n, i), lo, udir, 0.01, tr, arm, sides=10, out=0.002))
        pl.append(dome_rivets("Arm%s_Rivets" % n, base, tilt, 0.104, s, M["brass"], arm, lift=0.0))
        pl.append(loft("Arm%s_Rerebrace" % n, grow(span(U, 0.5, 0.88), 1.16, 0.01), lea, arm, sides=8,
                       chamfer=(0.005, 0.005)))
        pl.append(band("Arm%s_RereStrap" % n, grow([sample(U, 0.7)], 1.16, 0.012)[0], -udir, 0.014, tr, arm,
                       sides=8, out=0.002))
        join_objs("Arm%s_Pauldron" % n, pl)
        F = S["fore"]
        fd = F[-1]["c"] - F[0]["c"]
        vb = [loft("Arm%s_Vambrace" % n, grow(span(F, 0.1, 0.66), 1.22, 0.012), lea, elbow, chamfer=(0.005, 0.005))]
        for k, t in enumerate((0.25, 0.55)):
            vb.append(band("Arm%s_VbStrap%d" % (n, k), grow([sample(F, t)], 1.22, 0.014)[0], fd, 0.014, tr, elbow,
                           sides=8, out=0.002))
        join_objs("Arm%s_Vambrace" % n, vb)
    hips(R, M["pants"])
    thighs(P, R, M["pants"])
    belt("Belt", secs, 1.0, 0.058, 0.032, tr, M["steel"], body)
    torso_strap("Baldric", secs, (-0.14, 1.43), (0.16, 1.02), 0.04, tr, body, n=7, out=0.034)
    # saiote: painéis separados (frente, lado, costas) presos às pernas, debruados
    for n, s in (("L", 1), ("R", -1)):
        for k, (a0, a1, off, z1) in enumerate(((0.06, 0.66, 0.014, 0.645), (0.62, 1.6, 0.0, 0.69),
                                               (1.56, 3.1, 0.007, 0.67))):
            lo, hi = (a0, a1) if s > 0 else (-a1, -a0)
            skirt("Tasset%s%d" % (n, k), 0.995, z1, 0.192 + off, 0.15 + off, 0.222 + off, 0.18 + off, [lea],
                  R["Leg" + n], a0=lo, a1=hi, cols=2, rows=1, folds=0.0, thick=0.014, trim=tr, border=0.013,
                  hem_band=0.016)
    a = 0.34
    t = (0.995 - 0.8) / (0.995 - 0.645)
    rr, ry_ = 0.192 + 0.014 + t * 0.03 + 0.019, 0.15 + 0.014 + t * 0.03 + 0.019
    c = Vector((math.sin(a) * rr, -math.cos(a) * ry_, 0.8))
    pq = [tbox("Plaque", c, (0.09, 0.008, 0.065), M["steel"], bevel=0.003, rot=(-0.09, 0, a), parent=R["LegL"])]
    ox, oy = Vector((math.cos(a), math.sin(a), 0)), Vector((math.sin(a), -math.cos(a), 0))
    pq.append(rivets("PlaqueRivet", [c + ox * dx + Vector((0, 0, dz)) + oy * 0.005 for dx in (-0.034, 0.034)
                                     for dz in (-0.022, 0.022)], M["steel_d"], R["LegL"], r=0.008))
    join_objs("Plaque", pq)
    pouch("Pouch", (0.2, -0.03, 0.93), tr, lea, body, size=(0.08, 0.055, 0.09), rotz=1.0)
    g_export("a_leather", P, R)


def build_a_mail():
    """Cota de malha até o joelho com fileiras de elos (listras), gola acolchoada, espaldares de aço
    rebitados, barra e punhos de couro, fendas debruadas, cinto largo e bandoleira. t1 = malha, t1d = fileiras."""
    P, R = g_rig("a_mail")
    M = g_mats()
    body = R["Body"]
    ch = gm("t1_mail", "#7C838E", 0.7, 0.5)
    chd = gm("t1d_mail", "#565C66", 0.75, 0.45)
    secs = clothed_torso(P, R, ch, k=1.09, add=0.012, steps=tuple(i / 12 for i in range(1, 12)))
    stripes(bpy.data.objects["Torso"], chd)
    neck(R, M["skin"])
    loft("Padding", [sec((0, 0.006, 1.425), 0.125, 0.105), sec((0, 0.008, 1.47), 0.1, 0.088),
                     sec((0, 0.01, 1.51), 0.085, 0.078)], M["linen_d"], R["Head"], sides=10, chamfer=(0.0, 0.006))
    sleeves(P, R, ch, M["skin"], upto=0.92, k=1.08, cuff=M["lea"], steps=5)
    for n in ("L", "R"):
        for part in ("Upper", "Fore"):
            stripes(bpy.data.objects["Arm%s_%s" % (n, part)], chd)
    for n, s in (("L", 1), ("R", -1)):
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.78), 0, math.cos(0.78)))
        base = sh + Vector((s * 0.012, 0, -0.004))
        sp = [dome("Arm%s_Spaulder" % n, base, tilt, 0.1, 0.098, 0.062, M["steel"], R["Arm" + n], sides=10, lip=0.018)]
        sp.append(band("Arm%s_SpaulderTrim" % n, sec(base - tilt * 0.018, 0.094, 0.092), tilt, 0.012, M["steel_d"],
                       R["Arm" + n], sides=10))
        sp.append(dome_rivets("Arm%s_SpRivet" % n, base, tilt, 0.096, s, M["brass"], R["Arm" + n], lift=0.0))
        join_objs("Arm%s_Spaulder" % n, sp)
    hips(R, ch)
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.1, math.pi - 0.1) if s > 0 else (-math.pi + 0.1, -0.1)
        skirt("Skirt%s" % n, 1.0, 0.56, 0.18, 0.14, 0.226, 0.182, [ch, chd], R["Leg" + n], a0=lo, a1=hi, cols=7,
              rows=10, folds=0.008, thick=0.012, lines=9, trim=M["lea"], border=0.012,
              hem_band=0.022, hem=lambda a: -0.022 * abs(math.cos(a)))
    belt("Belt", secs, 1.0, 0.065, 0.026, M["lea"], M["steel"], body)
    torso_strap("Baldric", secs, (0.14, 1.43), (-0.17, 1.0), 0.04, M["lea_d"], body, n=7, out=0.024)
    torso_strap("BaldricBack", secs, (0.14, 1.43), (-0.17, 1.0), 0.04, M["lea_d"], body, back=True, n=7, out=0.024)
    pouch("Pouch", (-0.2, -0.04, 0.93), M["lea"], M["lea_d"], body, size=(0.08, 0.055, 0.09), rotz=-0.9)
    g_export("a_mail", P, R)


def build_a_surcoat():
    """Sobreveste sobre cota de malha: painéis de frente e costas do ombro ao joelho, debruados em vermelho,
    com cruz no peito e nas costas e fenda no meio da saia; malha nos flancos, mangas e saia; espaldares de aço
    com friso dourado; cinto com fivela dourada. t1 = sobreveste, t2 = cruz e debrum."""
    P, R = g_rig("a_surcoat")
    M = g_mats()
    body = R["Body"]
    cl = gm("t1_surcoat", "#E3DCC6", 0.9)
    em = gm("t2_surcoat", "#A3202A", 0.85)
    chd = gm("g_chain_d", "#4A4F57", 0.8, 0.4)
    secs = clothed_torso(P, R, M["chain"], k=1.08, add=0.012, steps=tuple(i / 12 for i in range(1, 12)))
    stripes(bpy.data.objects["Torso"], chd)
    neck(R, M["skin"], collar=M["chain"])
    zs = (0.99, 1.1, 1.2, 1.3, 1.38, 1.445)
    arc_panel("SurcoatF", [torso_ring(secs, z, 0.014) for z in zs], 2.5, cl, body, trim=em, hem=False)
    arc_panel("SurcoatB", [torso_ring(secs, z, 0.014) for z in zs], 2.5, cl, body, back=True, trim=em, hem=False)
    for sg, nm in ((1, "L"), (-1, "R")):    # alças sobre os ombros ligando frente e costas
        x = sg * 0.105
        pts = [on_torso(secs, x, 1.43, out=0.014), Vector((x, 0.0, 1.462)), on_torso(secs, x, 1.43, True, 0.014)]
        loft("SurcoatStrap" + nm, [sec(p, 0.045, 0.006) for p in pts], cl, body, sides=4, fwd=(0, 0, 1))
    cross = []
    for back, tag in ((False, "F"), (True, "B")):
        fwd = (0, 1 if back else -1, 0)
        cross.append(loft("Cross%sV" % tag, [sec(on_torso(secs, 0.0, z, back, 0.03), 0.026, 0.004)
                                             for z in (1.08, 1.2, 1.32, 1.4)], em, body, sides=4, fwd=fwd))
        cross.append(loft("Cross%sH" % tag, [sec(on_torso(secs, x, 1.3, back, 0.031), 0.024, 0.004)
                                             for x in (-0.11, -0.055, 0.0, 0.055, 0.11)], em, body, sides=4, fwd=fwd))
    join_objs("Cross", cross)
    sleeves(P, R, M["chain"], M["skin"], upto=0.95, k=1.07, cuff=M["lea_d"], steps=5)
    for n in ("L", "R"):
        for part in ("Upper", "Fore"):
            stripes(bpy.data.objects["Arm%s_%s" % (n, part)], chd)
    for n, s in (("L", 1), ("R", -1)):
        sh = mirror(P["shoulder"], s)
        tilt = Vector((s * math.sin(0.72), 0, math.cos(0.72)))
        S = limb_sections(P, s)
        base = sh + Vector((s * 0.012, 0, -0.004))
        pl = [dome("Arm%s_Spaulder" % n, base, tilt, 0.11, 0.105, 0.07, M["steel"], R["Arm" + n], sides=10, lip=0.02)]
        c0, c1 = sample(S["upper"], 0.14), sample(S["upper"], 0.34)
        lo = sec(c1["c"] + Vector((s * 0.006, 0, 0)), 0.092, 0.096)
        pl.append(loft("Arm%s_SpaulderLame" % n, [sec(c0["c"], 0.086, 0.09), lo], M["steel"], R["Arm" + n], sides=10,
                       chamfer=(0.0, 0.005)))
        pl.append(band("Arm%s_SpaulderTrim" % n, sec(base - tilt * 0.012, 0.11, 0.105), tilt, 0.014, M["gold"],
                       R["Arm" + n]))
        pl.append(band("Arm%s_LameTrim" % n, lo, -(S["upper"][-1]["c"] - S["upper"][0]["c"]), 0.012, M["gold"],
                       R["Arm" + n], out=0.003))
        pl.append(dome_rivets("Arm%s_SpRivet" % n, base, tilt, 0.105, s, M["gold"], R["Arm" + n], lift=0.012))
        join_objs("Arm%s_Spaulder" % n, pl)
    hips(R, M["chain"])
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.1, math.pi - 0.1) if s > 0 else (-math.pi + 0.1, -0.1)
        skirt("Mail%s" % n, 0.98, 0.6, 0.176, 0.136, 0.205, 0.165, [M["chain"], chd], R["Leg" + n], a0=lo, a1=hi,
              cols=6, rows=8, folds=0.006, thick=0.01, lines=7)
        for side, (b0, b1) in (("F", (0.0, 0.98)), ("B", (math.pi - 0.98, math.pi))):
            a0_, a1_ = (b0, b1) if s > 0 else (-b1, -b0)
            skirt("Panel%s%s" % (side, n), 1.0, 0.48, 0.19, 0.152, 0.235, 0.2, [cl], R["Leg" + n], a0=a0_, a1=a1_,
                  cols=3, rows=3, folds=0.01, thick=0.012, trim=em, border=0.02, hem_band=0.03)
    belt("Belt", secs, 1.0, 0.05, 0.032, M["lea_d"], M["gold"], body)
    g_export("a_surcoat", P, R)


def build_a_robe():
    """Manto arcano até os tornozelos, transpassado na frente (debrum dourado na aba e em todas as barras),
    gola alta, murça debruada sobre os ombros, mangas largas com punho dourado e faixa dupla com nó e pontas.
    t1 = manto, t2 = murça, gola e faixa."""
    P, R = g_rig("a_robe")
    M = g_mats()
    body = R["Body"]
    rb = gm("t1_robe", "#3B3170", 0.92)
    rb2 = gm("t2_robe", "#231C45", 0.92)
    gold = M["gold"]
    secs = clothed_torso(P, R, rb, k=1.08, add=0.012)
    neck(R, M["skin"])
    torso_strap("WrapEdge", secs, (0.03, 1.45), (-0.07, 1.0), 0.02, gold, body, n=6, out=0.004)
    loft("Collar", [sec((0, 0.01, 1.435), 0.112, 0.1), sec((0, 0.012, 1.5), 0.105, 0.096),
                    sec((0, 0.016, 1.55), 0.118, 0.11)], rb2, R["Head"], sides=10, fwd=(0, 1, 0), arc=4.6,
         thick=0.012)
    band("CollarTrim", sec((0, 0.016, 1.537), 0.118, 0.11), ZUP, 0.014, gold, R["Head"], sides=10, fwd=(0, 1, 0),
         arc=4.6, out=0.003)
    sleeves(P, R, rb, M["skin"], upto=0.9, k=1.02, flare=0.045, cuff=gold, cap=False)
    hips(R, rb)
    thighs(P, R, M["pants"])
    for n, s in (("L", 1), ("R", -1)):
        lo, hi = (0.22, math.pi) if s > 0 else (-math.pi, -0.22)
        skirt("Robe%s" % n, 1.0, 0.1, 0.18, 0.14, 0.27, 0.24, [rb], R["Leg" + n], a0=lo, a1=hi, cols=7, rows=5,
              folds=0.016, thick=0.012, trim=gold, border=0.018, hem_band=0.026)
    sash = [ring_at("Sash", secs, 0.985, 1.045, 0.022, rb2, body),
            ring_at("Sash2", secs, 0.95, 0.975, 0.03, rb2, body)]
    sash.append(band("SashTrim", torso_ring(secs, 1.04, 0.022), ZUP, 0.008, gold, body, sides=12, phase=0))
    fy = front_y(torso_at(secs, 1.0), 0.022)
    sash.append(tbox("SashKnot", (0.06, fy - 0.008, 1.0), (0.055, 0.03, 0.06), rb2, bevel=0.012, parent=body))
    for k, (p0, p1, w) in enumerate((((0.05, fy - 0.012, 0.98), (0.075, fy - 0.035, 0.7), 0.05),
                                     ((0.075, fy - 0.012, 0.98), (0.12, fy - 0.03, 0.75), 0.045))):
        sash.append(strap("SashEnd%d" % k, p0, p1, w, rb2, body, (0.2, -1, 0)))
        d = (Vector(p1) - Vector(p0)).normalized()
        sash.append(strap("SashTip%d" % k, Vector(p1) - d * 0.003, Vector(p1) + d * 0.03, w * 0.9, gold, body,
                          (0.2, -1, 0), t=0.007))
    join_objs("Sash", sash)
    moz = [skirt("Mozzetta", 1.495, 1.462, 0.12, 0.105, 0.305, 0.215, [rb2], body, cols=16, rows=1, folds=0.0,
                 thick=0.014, cy=0.005),
           skirt("MozzettaDrop", 1.462, 1.29, 0.305, 0.215, 0.33, 0.235, [rb2], body, cols=16, rows=2, folds=0.008,
                 thick=0.014, cy=0.005, trim=gold, hem_band=0.018,
                 hem=lambda a: -0.045 * max(0.0, math.cos(a)) ** 2)]
    join_objs("Mozzetta", moz)
    g_export("a_robe", P, R)


# ================================================================== MÃOS
def build_g_bare():
    P, R = g_rig("g_bare")
    M = g_mats()
    for n, s in (("L", 1), ("R", -1)):
        fist("Arm" + n, P, s, M["skin"], R["Elbow" + n])
    g_export("g_bare", P, R)


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
        fd = F[-1]["c"] - F[0]["c"]
        c0 = grow([sample(F, 0.72)], 1.22, 0.014)[0]
        cuff = loft("Arm%s_GloveCuff" % n, [c0, grow([sample(F, 1.0)], 1.06, 0.006)[0]], gl2, elbow, sides=8,
                    chamfer=(0.006, 0.0))
        rim = band("Arm%s_CuffRim" % n, c0, fd, 0.014, gl, elbow, sides=8, out=0.003)
        # placa dos nós dos dedos e costura no dorso
        W = mirror(P["wrist"], s)
        hd = P["hd"]
        G = W + Vector((-s * 0.004, 0, -0.064 * hd))
        kn = tbox("Arm%s_KnucklePad" % n, G + Vector((s * 0.034 * hd, -0.0005, 0.03 * hd)), (0.012, 0.09 * hd, 0.026 * hd),
                  gl2, bevel=0.004, rot=(0, -s * 0.5, 0), parent=elbow)
        seam = tbox("Arm%s_GloveSeam" % n, W + Vector((s * 0.04 * hd, 0.0, -0.02 * hd)), (0.006, 0.05 * hd, 0.006),
                    gl2, parent=elbow)
        join_objs("Arm%s_Hand" % n, [h, cuff, rim, kn, seam])
    g_export("g_gloves", P, R)


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
    g_export("g_bracers", P, R)


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
    parts_f_shoes(P, R, g_mats())
    g_export("f_shoes", P, R)


def parts_f_shoes(P, R, M):
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        _shin_hose(P, R, n, s, M["pants"])
        parts = _shoe(P, R, n, s, M["lea"], M["lea_d"])
        parts.append(loft("Leg%s_Ankle" % n, grow(span(S["shin"], 0.86, 1.0), 1.14, 0.008), M["lea"], R["Knee" + n]))
        parts.append(band("Leg%s_AnkleStrap" % n, grow([sample(S["shin"], 0.9)], 1.14, 0.01)[0],
                          S["shin"][-1]["c"] - S["shin"][0]["c"], 0.014, M["lea_d"], R["Knee" + n], sides=8))
        join_objs("Leg%s_Shoe" % n, parts)


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
        parts.append(band("Leg%s_BootStrap2" % n, grow([sample(S["shin"], 0.45)], 1.15, 0.012)[0], dn, 0.014, bt2,
                          knee, sides=8))
        for t in (0.8, 0.47):
            c = sample(S["shin"], t)
            parts.append(tbox("Leg%s_BootBuckle%d" % (n, int(t * 100)), (c["c"].x + s * 0.05, c["c"].y - 0.02,
                                                                         c["c"].z - 0.02 + (0.0 if t > 0.5 else 0.008)),
                              (0.01, 0.026, 0.026), M["brass"], bevel=0.002, parent=knee))
        # costura na frente do cano e salto escuro
        fr = [dict(x, c=x["c"]) for x in grow(span(S["shin"], 0.32, 0.95), 1.14, 0.013)]
        parts.append(loft("Leg%s_BootSeam" % n, [sec(Vector((x["c"].x, x["c"].y - x["ry"] * x["fr"], x["c"].z)),
                                                    0.004, 0.003) for x in fr], bt2, knee, sides=4, fwd=(0, -1, 0)))
        ft = grow(S["foot"], 1.08, 0.006)
        K = mirror(P["knee"], s)
        parts.append(tbox("Leg%s_Heel" % n, (K.x, ft[0]["c"].y + 0.012, 0.03), (0.075, 0.06, 0.045), bt2, bevel=0.006,
                          parent=knee))
        join_objs("Leg%s_Boot" % n, parts)
    g_export("f_boots", P, R)


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
    g_export("f_plated", P, R)


GEAR = [(n, globals()["build_" + n]) for n in (
    "h_bare", "h_hood", "h_cap", "h_kettle", "h_nasal", "h_great", "h_wizard",
    "a_shirt", "a_tunic", "a_leather", "a_mail", "a_surcoat", "a_robe",
    "g_bare", "g_gloves", "g_bracers",
    "f_shoes", "f_boots", "f_plated")]
