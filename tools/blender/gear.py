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
HEAD_CHIN, HEAD_H = 1.555, 0.262        # cabeça humana sob os elmos (olhos ~1,68, na fenda do elmo do cavaleiro)
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
    """Seções do tronco para roupa: peito menos saltado e cintura solta (o tecido não entra na cintura).
    A rampa do trapézio até o pescoço já vem do corpo."""
    b = [dict(x) for x in torso_sections(P)]
    for x in b:
        x["fr"] = min(x["fr"], 1.06)
    b[3]["rx"] = (b[2]["rx"] + b[4]["rx"]) / 2 * 0.98
    b[3]["ry"] = (b[2]["ry"] + b[4]["ry"]) / 2
    return b


def clothed_torso(P, R, material, k=1.07, add=0.01, z_top=None, keel=0.0, steps=()):
    secs = grow(cloth_sections(P), k, add)
    if keel:
        secs = [dict(s, keel=keel * max(0.0, 1 - abs(s["c"].z - 1.3) / 0.25)) for s in secs]
    use = secs[1:] if z_top is None else [s for s in secs[1:] if s["c"].z <= z_top] + [torso_at(secs, z_top)]
    if steps:
        use = stepped(use, steps, drop=0.95, eps=0.01)
    loft("Torso", use, material, R["Body"], sides=12, phase=0, axis=ZUP, chamfer=(0.0, 0.008))
    return secs


def neck(R, skin, collar=None, collar_z=1.497):
    parts = [neck_mesh(body_proportions(**GEAR_P), skin, R["Head"])]
    if collar is not None:     # gola: aro em volta da boca da roupa, na base do pescoço
        parts.append(loft("Collar", [sec((0, 0.008, collar_z - 0.022), 0.104, 0.084),
                                     sec((0, 0.01, collar_z + 0.016), 0.08, 0.074)], collar, R["Head"], sides=10))
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
        U = grow(S["upper"], k, add)          # inteira: a manga fecha redonda sobre o deltoide
        if steps:
            U = stepped(U, [(i + 1) / (steps + 1) for i in range(steps)], drop=0.95, eps=0.008)
        up = [loft("Arm%s_Upper" % n, U, material, arm)]
        if cap and cap_mat is not None:     # costura do ombro em outra cor (opcional)
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
        f = HEAD_H / 0.245                                   # calotas medidas para a cabeça de 0,245 m
        shell("HairBase", (0, 0.006 * f, HEAD_CHIN + 0.165 * f), (0.156 * f, 0.208 * f, 0.2 * f), M["hair"], cut=0.25,
              seg=10, rings=6, rot=(-0.2, 0, 0), thick=0.008, parent=head)
        shell("HairBaseBack", (0, 0.006 * f, HEAD_CHIN + 0.14 * f), (0.162 * f, 0.27 * f, 0.2 * f), M["hair"], cut=0.1,
              seg=10, rings=6, rot=(-math.pi / 2, 0, 0), thick=0.008, parent=head)
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


# ------------------------------------------------------------------ peças de malha lisa (curvas)
# As roupas antigas são tubos facetados de poucos lados e ficam quadradas. As peças novas usam anéis de muitos
# pontos ao longo de uma curva suave, com sombreamento liso: o toon do jogo desenha a sombra em curva.
def g_spline(pts, n):
    """n + 1 pontos ao longo de uma Catmull-Rom que passa por pts (vetores ou números)."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(n + 1):
        x = i / n * (len(pts) - 1)
        k = min(int(x), len(pts) - 2)
        t = x - k
        a, b, c, d = P[k], P[k + 1], P[k + 2], P[k + 3]
        out.append(((-a + 3 * b - 3 * c + d) * t ** 3 + (2 * a - 5 * b + 4 * c - d) * t ** 2 + (c - a) * t + 2 * b)
                   * 0.5)
    return out


def g_smooth_mesh(name, rings, material, parent, cap_end=True, closed=True, thick=0.0, outward=False):
    """Malha lisa ligando anéis de pontos do mundo (todos com o mesmo número de pontos)."""
    bm = bmesh.new()
    vr = [[bm.verts.new(q) for q in r] for r in rings]
    m = len(vr[0])
    for a, b in zip(vr, vr[1:]):
        for j in range(m if closed else m - 1):
            k = (j + 1) % m
            bm.faces.new((a[j], a[k], b[k], b[j]))
    if cap_end:
        tip = bm.verts.new(sum((v.co for v in vr[-1]), Vector()) / m)
        for j in range(m):
            bm.faces.new((vr[-1][j], vr[-1][(j + 1) % m], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if outward:          # casca aberta: garante as faces viradas para fora do miolo
        mid = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        if sum(f.normal.dot(f.calc_center_median() - mid) for f in bm.faces) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    if thick:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    print("PART", name, "smooth", flush=True)
    return _finish(name, bm, material, parent, smooth=True)


def g_curved_tube(path, radii, sides=24, wob=None, side0=(1, 0, 0)):
    """Anéis perpendiculares a um caminho curvo. radii = [(rx, ry)] por ponto; wob(i, ang) soma ao raio (dobras)."""
    rings = []
    side = Vector(side0)
    for i, c in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized()          # transporte paralelo: o anel não torce
        fwd = t.cross(side).normalized()
        rx, ry = radii[i]
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            w = wob(i, a) if wob else 0.0
            ring.append(c + side * math.sin(a) * (rx + w) + fwd * math.cos(a) * (ry + w))
        rings.append(ring)
    return rings


def g_plate(name, outline, origin, u, v, thick, material, parent):
    """Chapa recortada (estrela, losango, runa): contorno 2D [(x, y)] no plano u/v em origin, com espessura
    para os dois lados do plano. É um prisma montado à mão: engrossar por solidify estoura os vértices nos
    contornos côncavos (as runas viravam barras de metros no jogo)."""
    u, v = Vector(u).normalized(), Vector(v).normalized()
    n = u.cross(v).normalized() * thick * 0.75
    bm = bmesh.new()
    top = [bm.verts.new(Vector(origin) + u * x + v * y + n) for x, y in outline]
    bot = [bm.verts.new(Vector(origin) + u * x + v * y - n) for x, y in outline]
    m = len(outline)
    caps = [bm.faces.new(top), bm.faces.new(bot[::-1])]
    for k in range(m):
        bm.faces.new((top[k], bot[k], bot[(k + 1) % m], top[(k + 1) % m]))
    bmesh.ops.triangulate(bm, faces=caps)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    print("PART", name, "plate", flush=True)
    return _finish(name, bm, material, parent)


def g_crescent(name, origin, u, v, thick, material, parent, r=0.05, r_in=0.042, d=0.02, n=16, blunt=0.1):
    """Lua crescente aberta para +u: tira entre o arco de fora e o de dentro, pontas rombudas, com espessura."""
    u, v = Vector(u).normalized(), Vector(v).normalized()
    al = math.acos((r * r + d * d - r_in * r_in) / (2 * r * d)) + blunt
    px, py = r * math.cos(al - blunt), r * math.sin(al - blunt)
    be = math.atan2(py, px - d) + blunt * 1.6
    bm = bmesh.new()
    rows = []
    for i in range(n + 1):
        ao = al + (2 * math.pi - 2 * al) * i / n
        ai = be + (2 * math.pi - 2 * be) * i / n
        rows.append((bm.verts.new(Vector(origin) + u * r * math.cos(ao) + v * r * math.sin(ao)),
                     bm.verts.new(Vector(origin) + u * (d + r_in * math.cos(ai)) + v * r_in * math.sin(ai))))
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], b[0], b[1], a[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    print("PART", name, "crescent", flush=True)
    return _finish(name, bm, material, parent)


def g_star4(r=0.03, r_in=0.01):
    """Estrela de quatro pontas, as de cima e de baixo mais compridas."""
    return [((r if i % 2 == 0 else r_in) * math.sin(i * math.pi / 4),
             (r if i % 2 == 0 else r_in) * math.cos(i * math.pi / 4) * (1.35 if i % 4 == 0 else 1.0))
            for i in range(8)]


def archmage_hat_mats():
    return dict(
        felt=gm("am_felt", "#20244C", 0.95),
        lining=gm("am_hatlining", "#6F7FD0", 0.9),
        gold=gm("am_hatgold", "#D6A63A", 0.45, 0.3),
        gem=mat("am_gem_flat", hexc("#7FE6F2"), 0.3, 0.0, emit=hexc("#5FD8F0"), strength=1.2),
        tassel=gm("am_tassel", "#3F6FC8", 0.9),
    )


def build_hat(style, A, o):
    """Chapéu de mago (referências: chapéu de bruxa de aba larga ondulada com lua, e chapéu de feltro mole
    de ponta caída). Malha lisa: aba larga que cai nos lados e levanta na frente e atrás, com forro lilás por
    baixo; copa mole que sobe, tomba para trás e para o lado em dobras e termina em ponta enrolada; faixa
    dourada com medalhão e gema; lua crescente dourada presa na copa; pingente de estrela com borla pendurado
    na aba. Cores fixas (não tinge pelo item)."""
    P, R = g_rig(style)
    M = g_mats()
    head = R["Head"]
    plain_head(R, M)
    z0, cy = HEAD_CHIN + 0.2, 0.01
    N = 32
    # ---- copa: caminho curvo; raio com dobras (o feltro amassa onde tomba)
    ctrl = [Vector((0, cy, z0 - 0.012)), Vector((0, cy + 0.004, z0 + 0.075)), Vector((0.006, cy + 0.03, z0 + 0.17)),
            Vector((0.03, cy + 0.085, z0 + 0.255)), Vector((0.075, cy + 0.165, z0 + 0.3)),
            Vector((0.125, cy + 0.235, z0 + 0.285)), Vector((0.15, cy + 0.27, z0 + 0.235)),
            Vector((0.14, cy + 0.262, z0 + 0.2))]
    rads = [(0.125, 0.137), (0.112, 0.12), (0.088, 0.092), (0.066, 0.068), (0.046, 0.046), (0.03, 0.03),
            (0.016, 0.016), (0.004, 0.004)]
    n = 40
    path = g_spline(ctrl, n)
    rx = g_spline([r[0] for r in rads], n)
    ry = g_spline([r[1] for r in rads], n)

    def fold(i, a):
        t = i / n
        if t < 0.12 or t > 0.9:
            return 0.0
        k = math.sin((t - 0.12) / 0.78 * math.pi)                 # some na base e na ponta
        return k * (0.007 * math.sin(t * 34.0) + 0.006 * math.sin(t * 19.0 + 2.5 * math.sin(a)))
    crown = g_curved_tube(path, list(zip(rx, ry)), sides=N, wob=fold)
    parts = [g_smooth_mesh("ArchHat", crown, A["felt"], head)]

    # ---- aba: anel largo e ondulado, com espessura; por baixo, forro
    def brim_pt(a, u, dz=0.0):
        r_x = 0.123 + (0.335 * o.get("brim", 1.0) - 0.123) * u
        r_y = 0.135 + (0.32 * o.get("brim", 1.0) - 0.135) * u
        z = (z0 + 0.004 - 0.06 * max(u, 0.0) ** 1.4 + u ** 2 * (0.065 * math.cos(2 * a) - 0.035 * math.cos(a) + 0.016 * math.sin(3 * a + 1.0))
             + 0.028 * u ** 3 * math.cos(5 * a + 0.6))
        return Vector((math.sin(a) * r_x, cy - math.cos(a) * r_y, z + dz))
    rows = 9
    top = [[brim_pt(2 * math.pi * j / N, i / rows) for j in range(N)] for i in range(rows + 1)]
    under = [[brim_pt(2 * math.pi * j / N, i / rows, -0.005 - 0.011 * (1 - (i / rows) ** 4)) for j in range(N)]
             for i in range(rows, -1, -1)]
    under.append([brim_pt(2 * math.pi * j / N, -0.3, -0.03) for j in range(N)])    # carneira: encosta na cabeça
    brim = g_smooth_mesh("ArchBrim", top + under, A["felt"], head, cap_end=False)
    brim.data.materials.append(A["lining"])
    if brim.data.polygons[0].normal.z < 0:
        brim.data.flip_normals()
    for pl in brim.data.polygons[(rows + 1) * N:]:
        pl.material_index = 1
    parts.append(brim)

    # ---- faixa dourada na base da copa, medalhão com gema na frente
    band_rings = []
    for i in range(2, 5):
        cen = path[i]
        band_rings.append([q + (q - cen).normalized() * 0.006 for q in crown[i]])
    parts.append(g_smooth_mesh("ArchBand", band_rings, A["gold"], head, cap_end=False, thick=0.004))
    front = min(band_rings[1], key=lambda q: q.y)
    disc = [[front + Vector((math.sin(2 * math.pi * j / 16) * r, yy, math.cos(2 * math.pi * j / 16) * r))
             for j in range(16)] for r, yy in ((0.036, 0.006), (0.036, -0.006), (0.027, -0.012), (0.014, -0.014))]
    parts.append(g_smooth_mesh("ArchMedal", disc, A["gold"], head))
    parts.append(g_gem("ArchMedalGem", front + Vector((0, -0.014, 0)), 0.016, 0.02, 0.007, A["gem"], head))

    # ---- lua crescente presa na copa (de frente, um pouco para o lado)
    ri = int(n * 0.36)
    cen = path[ri]
    q = max(crown[ri], key=lambda v: (v - cen).normalized().dot(Vector((0.62, -0.78, 0))))
    out = (q - cen).normalized()
    up = (path[ri + 1] - path[ri - 1]).normalized()
    sidev = up.cross(out).normalized()
    rot = 0.55
    u_ax = sidev * math.cos(rot) + up * math.sin(rot)
    v_ax = -sidev * math.sin(rot) + up * math.cos(rot)
    if o.get("emblem", "moon") == "moon":
        parts.append(g_crescent("ArchMoon", q + out * 0.01 + up * 0.01, u_ax, v_ax, 0.016, A["gold"], head,
                                r=0.06, r_in=0.05, d=0.026))
    elif o.get("emblem") == "sun":
        parts.append(g_cap("HatSun", q + out * 0.004, out, sidev, 0.032, 0.032, 0.012, A["gold"], head, sides=16))
        for i in range(8):
            rd = sidev * math.cos(2 * math.pi * i / 8) + up * math.sin(2 * math.pi * i / 8)
            parts.append(g_plate("HatRay%d" % i, [(x * 0.009, y * 0.02) for x, y in G_DIAMOND],
                                 q + out * 0.004 + rd * 0.046, rd.cross(out), rd, 0.012, A["gold"], head))

    if o.get("pendant", True):
        # ---- pingente: cordão na beira da aba, conta, estrela e borla
        e = brim_pt(1.05, 0.97)
        dn = Vector((0, 0, -1))
        parts.append(loft("ArchCord", [sec(e + Vector((0, 0, 0.004)), 0.0035, 0.0035), sec(e + dn * 0.03, 0.0035, 0.0035)],
                          A["gold"], head, sides=6))
        bead = [[e + dn * (0.03 + 0.011 - 0.011 * math.cos(math.pi * i / 6))
                 + Vector((math.sin(2 * math.pi * j / 12), -math.cos(2 * math.pi * j / 12), 0)) * 0.011
                 * max(math.sin(math.pi * i / 6), 0.05) for j in range(12)] for i in range(7)]
        parts.append(g_smooth_mesh("ArchBead", bead, A["gem"], head))
        parts.append(g_plate("ArchStar", g_star4(0.03, 0.01), e + dn * 0.083 + Vector((0, 0.005, 0)), (1, 0, 0), (0, 0, 1),
                           0.01, A["gold"], head))
        t0 = e + dn * 0.115
        tas = g_curved_tube([t0 + dn * x for x in (0.0, 0.01, 0.024, 0.044, 0.054)],
                          [(0.005, 0.005), (0.011, 0.011), (0.01, 0.01), (0.013, 0.013), (0.011, 0.011)], sides=12)
        parts.append(g_smooth_mesh("ArchTassel", tas, A["tassel"], head))

    if "loose_parts" in globals():
        loose_parts(style)
    join_objs("ArchHat", parts)
    g_export(style, P, R)


def build_h_archmage():
    build_hat("h_archmage", archmage_hat_mats(), {})


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
    neck(R, M["skin"], collar=M["linen_d"])
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


# ------------------------------------------------------------------ pintura anime (cor por vértice)
# Cada face inteira recebe um de três tons (luz / base / sombra), como numa ilustração: a pintura vai na cor por
# vértice e os materiais terminam em `_flat`, para o jogo não somar a sombra de forma dele por cima
# (ToonLook._is_flat). A luz da pintura vem de cima e da esquerda, pela frente E por trás: o personagem fica
# pintado igual visto de frente ou de costas, com a sombra no lado direito, por baixo e no fundo das dobras.
CEL_LIGHTS = (Vector((-0.45, -0.65, 0.6)).normalized(), Vector((-0.45, 0.65, 0.6)).normalized())
CEL_HI, CEL_MID, CEL_SHADE = (1.0, 1.0, 1.0), (0.7, 0.68, 0.76), (0.38, 0.34, 0.54)


def cel_paint(objs, skip=(), hi=0.7, mid=0.3):
    """Pinta por face: tom pela direção da face em relação a CEL_LIGHTS; face em dobra funda (AO assado baixo)
    vai para a sombra. Faces de materiais em skip ficam sem pintura (pele, gemas que brilham)."""
    for o in objs:
        me = o.data
        col = me.color_attributes["Col"]
        names = [m.name if m else "" for m in me.materials]
        for p in me.polygons:
            li = list(p.loop_indices)
            if names[p.material_index] in skip or not names[p.material_index].endswith("_flat"):
                for i in li:
                    col.data[i].color = (1, 1, 1, 1)
                continue
            ao = sum(col.data[i].color[0] for i in li) / len(li)
            d = max(p.normal.dot(L) for L in CEL_LIGHTS)
            tone = 0 if d > hi else (1 if d > mid else 2)
            if ao < 0.45:
                tone = 2
            c = (CEL_HI, CEL_MID, CEL_SHADE)[tone]
            for i in li:
                col.data[i].color = (c[0], c[1], c[2], 1.0)


def g_gem(name, c, w, h, t, material, parent):
    """Losango facetado de frente (gema, medalhão): meia largura w, meia altura h, meia espessura t."""
    c = Vector(c)
    return loft(name, [sec(c - Vector((0, 0, h)), w * 0.06, t * 0.4), sec(c, w, t),
                       sec(c + Vector((0, 0, h)), w * 0.06, t * 0.4)], material, parent, sides=4, phase=0, axis=ZUP)


def archmage_mats():
    return dict(
        coat=gm("am_coat_flat", "#27306A", 0.9),
        dark=gm("am_dark_flat", "#191D45", 0.9),
        cream=gm("am_cream_flat", "#D9D2BE", 0.9),
        gold=gm("am_gold_flat", "#D6A63A", 0.5),
        wine=gm("am_wine_flat", "#7A2342", 0.9),
        cloth=gm("am_cloth", "#20244C", 0.95),
        lining=gm("am_lining", "#6F7FD0", 0.9),
        gold2=gm("am_gold", "#D6A63A", 0.45, 0.3),
        cream2=gm("am_cream", "#E4DFD2", 0.9),
        wine2=gm("am_wine", "#5C1A34", 0.9),
        tassel=gm("am_tassel", "#3F6FC8", 0.9),
        gem=mat("am_gem_flat", hexc("#7FE6F2"), 0.3, 0.0, emit=hexc("#5FD8F0"), strength=1.2),
    )


# ------------------------------------------------------------------ gola e ombros do Arquimago (malha lisa)
def g_cap_pt(c, n, t1, r1, r2, h, th, ph, lift=0.0):
    """Ponto da calota de g_cap no ângulo th em volta do eixo e na elevação ph (0 = borda, pi/2 = topo)."""
    n = Vector(n).normalized()
    t1 = Vector(t1)
    t1 = (t1 - n * t1.dot(n)).normalized()
    t2 = n.cross(t1).normalized()
    d = (t1 * math.cos(th) * r1 + t2 * math.sin(th) * r2) * math.cos(ph) + n * h * math.sin(ph)
    return Vector(c) + d * (1.0 + lift / max(d.length, 1e-4))


def g_cap(name, c, n, t1, r1, r2, h, material, parent, rings=6, sides=20):
    """Calota lisa (ombreira, cabochão, engaste) assentada em c: eixo n, raio r1 ao longo de t1 e r2 no outro."""
    n = Vector(n).normalized()
    c = Vector(c)
    rows = [[g_cap_pt(c, n, t1, r1, r2, h, 2 * math.pi * j / sides, k / rings * math.pi / 2) for j in range(sides)]
            for k in range(rings)]
    base = [[c - n * 0.012 + (q - c) * 0.9 for q in rows[0]]]        # saia para dentro: afunda na peça de baixo
    return g_smooth_mesh(name, base + rows, material, parent)


def g_pipe(name, pts, r, material, parent, sides=8, loop=False):
    """Cordão roliço ao longo de pts (debrum, nervura, fio bordado). loop fecha o anel."""
    pts = list(pts) + (list(pts[:2]) if loop else [])
    return g_smooth_mesh(name, g_curved_tube(pts, [(r, r)] * len(pts), sides=sides), material, parent,
                         cap_end=not loop)


def g_links(name, pts, nrms, material, parent, step=0.021, ln=0.0135, wd=0.008, r=0.0028):
    """Corrente de elos ao longo de pts: elos ovais encaixados, um deitado na superfície e o seguinte em pé."""
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    out = []
    n = max(2, int(d[-1] / step))
    for i in range(n + 1):
        x = d[-1] * i / n
        k = max(j for j in range(len(d) - 1) if d[j] <= x + 1e-9)
        f = (x - d[k]) / max(d[k + 1] - d[k], 1e-6)
        c = pts[k].lerp(pts[k + 1], f)
        t = (pts[k + 1] - pts[k]).normalized()
        up = nrms[k].lerp(nrms[k + 1], f).normalized()
        side = t.cross(up).normalized()
        w = side if i % 2 == 0 else up
        loop = [c + t * math.cos(2 * math.pi * j / 8) * ln + w * math.sin(2 * math.pi * j / 8) * wd for j in range(8)]
        out.append(g_pipe("%s%d" % (name, i), loop, r, material, parent, sides=5, loop=True))
    return out


G_DIAMOND = [(0, 1), (0.62, 0), (0, -1), (-0.62, 0)]


def archmage_mantle(P, R, A, body):
    """Gola e ombros: murça em duas camadas que acompanha o trapézio e o ombro, com ponta em V na frente e
    atrás, debrum dourado roliço, fio bordado e fileira de losangos na barra, estrelas bordadas e uma lua nas
    costas; ombreiras douradas em duas placas com aro, nervuras, pérolas, gema e franja; gola alta com forro;
    no peito, um V dourado da gola ao broche, losangos no meio, broche oval com pérolas, asas em meia-lua e
    gema em gota, e duas voltas de corrente de elos até as ombreiras.
    Devolve (pano, enfeites): o pano dobra com o braço, os enfeites vão inteiros junto do ponto onde estão."""
    cloth, lining, gold, jewel = A["cloth"], A["lining"], A["gold2"], A["gem"]
    o = A.get("o", {})
    mot = A.get("motif", gold)
    cy = 0.008
    T = 200
    prof = [g_spline(col, T) for col in ((0.06, 0.145, 0.225, 0.262, 0.272), (0.056, 0.1, 0.128, 0.165, 0.182),
                                         (1.527, 1.517, 1.497, 1.442, 1.372))]

    def M(a, u, grow=0.0, drop=0.0):
        k = max(0, min(T, int(round(u * T))))
        rx, ry, z = prof[0][k], prof[1][k], prof[2][k]
        c2 = math.cos(2 * a)
        wing, vee = max(0.0, -c2) ** 2, max(0.0, c2) ** 2
        z -= 0.055 * u * math.cos(a) ** 2 + o.get("vee", 0.11) * vee * u ** 3 + drop * u
        z += 0.03 * wing * u ** 4
        rx += o.get("wing", 0.03) * wing * u ** 3 + grow + 0.006 * u ** 2 * math.sin(6 * a)
        ry += grow + 0.006 * u ** 2 * math.sin(6 * a)
        sx, cx = math.sin(a), math.cos(a)
        e = 2 / 2.5
        return Vector((math.copysign(abs(sx) ** e, sx) * rx, cy - math.copysign(abs(cx) ** e, cx) * ry, z))

    def normal(a, u):
        n = (M(a + 0.03, u) - M(a - 0.03, u)).cross(M(a, min(u + 0.03, 1.0)) - M(a, u - 0.03)).normalized()
        return n if n.z > 0 or abs(n.z) < 0.05 and n.dot(M(a, u) - Vector((0, cy, M(a, u).z))) > 0 else -n

    def frame(a, u):
        """Ponto, normal, lado (para a esquerda do personagem na frente) e cima (rumo à gola) na murça."""
        n = normal(a, u)
        up = (M(a, u - 0.03) - M(a, min(u + 0.03, 1.0))).normalized()
        side = up.cross(n).normalized()
        return M(a, u), n, side, up

    def motif(name, outline, a, u, size, thick=0.006, rot=0.0):
        c, n, side, up = frame(a, u)
        us = side * math.cos(rot) + up * math.sin(rot)
        vs = -side * math.sin(rot) + up * math.cos(rot)
        return g_plate(name, [(x * size, y * size) for x, y in outline], c + n * 0.0045, us, vs, thick, mot, body)

    N, rows = 48, 14
    soft, orn = [], []
    ud = o.get("under_drop", 0.075)
    layers = [("MantleUnder", lining, -0.004, ud, 0.006), ("Mantle", cloth, 0.0, 0.0, 0.0075)]
    if o.get("layers", 2) >= 3:          # terceira camada, mais comprida, por baixo das outras
        layers.insert(0, ("MantleUnder2", A.get("lining2", cloth), -0.008, ud * 2.0, 0.006))
    for nm, mt, grow, drop, r_pipe in layers:
        rings = [[M(2 * math.pi * j / N, i / rows, grow, drop) for j in range(N)] for i in range(rows + 1)]
        soft.append(g_smooth_mesh(nm, rings, mt, body, cap_end=False, thick=0.01))
        soft.append(g_pipe(nm + "Piping", rings[-1], r_pipe, gold, body, loop=True))

    # ---- bordado: fio dourado acima da barra, losangos entre o fio e a barra, estrelas, lua nas costas
    soft.append(g_pipe("MantleThread", [M(2 * math.pi * j / 96, 0.87) + normal(2 * math.pi * j / 96, 0.87) * 0.003
                                        for j in range(96)], 0.0032, gold, body, sides=6, loop=True))
    for j in (range(32) if o.get("hem_diamonds", True) else ()):
        a = 2 * math.pi * (j + 0.5) / 32
        aw = (a + math.pi) % (2 * math.pi) - math.pi
        if (o.get("pauldron", True) and abs(abs(aw) - math.pi / 2) < 0.62) or abs(aw) < 0.24:      # sob as ombreiras e sob a gema em gota
            continue
        orn.append(motif("HemDiamond%d" % j, g_shape(o, j, G_DIAMOND), a, 0.935, 0.0115, thick=0.005))
    for k, (a, u, sz) in enumerate(((0.78, 0.55, 0.02), (-0.78, 0.55, 0.02), (2.2, 0.6, 0.022), (-2.2, 0.6, 0.022),
                                    (2.75, 0.34, 0.015), (-2.75, 0.34, 0.015)) if o.get("stars", True) else ()):
        orn.append(motif("Star%d" % k, g_shape(o, k, g_star4(1.0, 0.32)), a, u, sz))
    back = o.get("back", "moon")
    c, n, side, up = frame(math.pi, 0.62)
    if back == "moon":
        orn.append(g_crescent("BackMoon", c + n * 0.0045 - up * 0.004, side * 0.5 + up * 0.87, -side * 0.87 + up * 0.5,
                              0.007, mot, body, r=0.052, r_in=0.043, d=0.022))
        orn.append(motif("BackStar", g_star4(1.0, 0.3), math.pi, 0.6, 0.017))
    elif back == "sun":
        orn.append(g_cap("BackSun", c + n * 0.002, n, side, 0.03, 0.03, 0.01, mot, body, sides=16))
        for i in range(8):
            rd = side * math.cos(2 * math.pi * i / 8) + up * math.sin(2 * math.pi * i / 8)
            orn.append(g_plate("BackRay%d" % i, [(x * 0.009, y * 0.02) for x, y in G_DIAMOND],
                               c + n * 0.0045 + rd * 0.044, rd.cross(n), rd, 0.006, mot, body))
    elif back == "rune":
        orn.append(motif("BackRune", G_RUNES[2], math.pi, 0.6, 0.05))
        for k, da in enumerate((-0.42, 0.42)):
            orn.append(motif("BackRune%d" % k, G_RUNES[k], math.pi + da, 0.62, 0.026))

    # ---- ombreiras: duas placas douradas; aro, nervuras e pérolas em relevo; gema em cima; franja de gotas
    for sn, s in ((("L", 1), ("R", -1)) if o.get("pauldron", True) else ()):
        a = s * math.pi / 2
        for k, (u, r1, r2, h) in enumerate(((0.84, 0.11, 0.07, 0.024), (0.56, 0.08, 0.062, 0.04))):
            c, n = M(a, u), normal(a, u)
            c = c + n * 0.004
            nm = "Pauldron%s%d" % (sn, k)
            cp = lambda th, ph, lift=0.0: g_cap_pt(c, n, (0, -1, 0), r1, r2, h, th, ph, lift)
            orn.append(g_cap(nm, c, n, (0, -1, 0), r1, r2, h, gold, body))
            orn.append(g_pipe(nm + "Rim", [cp(2 * math.pi * j / 24, 0.1, 0.002) for j in range(24)], 0.0052, gold,
                              body, loop=True))
            ribs = 8 if k == 0 else 6
            top = 0.75 if k == 0 else 1.05
            for i in range(ribs):
                th = 2 * math.pi * (i + 0.5) / ribs
                orn.append(g_pipe("%sRib%d" % (nm, i), [cp(th, 0.14 + (top - 0.14) * q / 6, 0.0015) for q in range(7)],
                                  0.0034, gold, body, sides=6))
                th = 2 * math.pi * i / ribs
                q = cp(th, 0.34)
                orn.append(g_cap("%sPearl%d" % (nm, i), q, q - c + n * 0.02, (0, -1, 0), 0.0075, 0.0075, 0.0075,
                                 jewel if k == 1 and i % 2 == 0 else gold, body, rings=4, sides=10))
            if k == 1:
                orn.append(g_pipe(nm + "Seat", [cp(2 * math.pi * j / 20, 1.12, 0.002) for j in range(20)], 0.0045, gold,
                                  body, loop=True))
                orn.append(g_cap("PauldronGem%s" % sn, c + n * (h - 0.004), n, (0, -1, 0), 0.03, 0.024, 0.016,
                                 jewel, body, rings=5, sides=16))
        for k in (range(5) if o.get("fringe", True) else ()):
            aa = a + s * (k - 2) * 0.2
            q = M(aa, 0.97) + Vector((0, 0, -0.004))
            drop = g_curved_tube([q + Vector((0, 0, -x)) for x in (0.0, 0.012, 0.03, 0.046, 0.054)],
                                 [(0.004, 0.004), (0.009, 0.009), (0.011, 0.011), (0.007, 0.007), (0.002, 0.002)],
                                 sides=10)
            orn.append(g_smooth_mesh("Fringe%s%d" % (sn, k), drop, gold, body))

    # ---- peito: V dourado da gola ao broche, losangos no meio, broche com pérolas, asas e gema em gota
    ub = 0.8
    bc, bn, bside, bup = frame(0.0, ub)
    for sn, s in ((("L", 1), ("R", -1)) if o.get("lapel", True) else ()):
        pts = []
        for i in range(13):
            t = i / 12
            a, u = s * 0.62 * (1 - t) ** 1.3, 0.1 + (ub - 0.05 - 0.1) * t
            pts.append(M(a, u) + normal(a, u) * 0.004)
        soft.append(g_pipe("Lapel" + sn, pts, 0.0058, gold, body))
        pts = []
        for i in range(13):
            t = i / 12
            a, u = s * 0.42 * (1 - t) ** 1.3, 0.2 + (ub - 0.1 - 0.2) * t
            pts.append(M(a, u) + normal(a, u) * 0.003)
        soft.append(g_pipe("LapelIn" + sn, pts, 0.003, gold, body, sides=6))
        c2 = bc + bside * s * 0.052 + bn * 0.004
        orn.append(g_crescent("BroochWing" + sn, c2, bside * s, bup, 0.009, gold, body, r=0.05, r_in=0.04, d=0.024))
    for k, (u, sz) in enumerate(((0.4, 0.011), (0.5, 0.015), (0.6, 0.02))):
        orn.append(motif("ChestDiamond%d" % k, G_DIAMOND, 0.0, u, sz))
    orn.append(g_cap("Brooch", bc + bn * 0.004, bn, (1, 0, 0), 0.043, 0.054, 0.016, gold, body, sides=24))
    orn.append(g_cap("BroochGem", bc + bn * 0.014, bn, (1, 0, 0), 0.025, 0.034, 0.015, jewel, body, rings=5, sides=20))
    for i in range(10):
        th = 2 * math.pi * i / 10
        q = g_cap_pt(bc + bn * 0.004, bn, (1, 0, 0), 0.043, 0.054, 0.016, th, 0.45)
        orn.append(g_cap("BroochPearl%d" % i, q, bn, (1, 0, 0), 0.006, 0.006, 0.006, gold, body, rings=4, sides=10))
    dc, dn_, dside, dup = frame(0.0, 0.985)
    orn.append(g_cap("DropSeat", dc + dn_ * 0.003 + dup * 0.012, dn_, dside, 0.022, 0.036, 0.01, gold, body, sides=16))
    orn.append(g_cap("DropGem", dc + dn_ * 0.009 + dup * 0.01, dn_, dside, 0.014, 0.027, 0.012, jewel, body, rings=5,
                     sides=14))

    # ---- duas voltas de corrente de elos, do broche a cada ombreira
    for sn, s in ((("L", 1), ("R", -1)) if o.get("chains", True) else ()):
        for k, (sag, u1) in enumerate(((0.07, 0.6), (0.2, 0.66))):
            pts, nr = [], []
            for i in range(33):
                t = i / 32
                a = s * (0.16 + (math.pi / 2 - 0.5 - 0.16) * t)
                u = min(0.97, ub + (u1 - ub) * t + sag * math.sin(math.pi * t))
                nr.append(normal(a, u))
                pts.append(M(a, u) + nr[-1] * 0.01)
            orn += g_links("Chain%s%d_" % (sn, k), pts, nr, gold, body)

    # ---- gola alta: abre para fora, sobe para a nuca, forro por dentro, debrum roliço na borda
    a0, na, nv = 0.42, 28, 8
    angs = [a0 + (2 * math.pi - 2 * a0) * j / na for j in range(na + 1)]

    def C(a, v, inset=0.0):
        e = min(1.0, min(a - a0, 2 * math.pi - a0 - a) / 0.75)
        hh = (0.07 + 0.085 * ((1 - math.cos(a)) / 2) ** 1.2) * (0.3 + 0.7 * e ** 0.6) * o.get("collar", 1.0)
        r = 0.012 * v + 0.05 * v ** 2 - inset
        return Vector((math.sin(a) * (0.078 + r), cy + 0.004 + 0.016 * v - math.cos(a) * (0.072 + r), 1.508 + hh * v))
    rings = []
    for i in range(nv + 1):
        v = i / nv
        rings.append([C(a, v) for a in angs] + [C(a, v, 0.009) for a in reversed(angs)])
    rings.append([(C(a, 1.0) + C(a, 1.0, 0.009)) / 2 for a in angs]
                 + [(C(a, 1.0) + C(a, 1.0, 0.009)) / 2 for a in reversed(angs)])     # fecha a borda de cima
    col = g_smooth_mesh("Collar", rings, cloth, body, cap_end=False)
    col.data.materials.append(lining)
    per = 2 * (na + 1)
    for pl in col.data.polygons:
        if pl.index % per > na and pl.index % per < per - 1:
            pl.material_index = 1
    rim = [C(angs[0], 0.0)] + [(C(a, 1.0) + C(a, 1.0, 0.009)) / 2 for a in angs] + [C(angs[-1], 0.0)]
    cparts = [col, g_pipe("CollarPiping", rim, 0.0065, gold, body)]
    for k, a in enumerate((math.pi - 0.9, math.pi, math.pi + 0.9) if o.get("collar", 1.0) > 0.8 else ()):          # losangos bordados na nuca
        q, q2 = C(a, 0.55), C(a, 0.75)
        out = Vector((q.x, q.y - cy, 0)).normalized()
        upv = (q2 - q).normalized()
        cparts.append(g_plate("CollarDiamond%d" % k, [(x * 0.013, y * 0.013) for x, y in G_DIAMOND], q + out * 0.003,
                              upv.cross(out), upv, 0.005, gold, body))
    join_objs("Collar", cparts)
    return soft, orn


def g_skin_finish(M, soft, orn, keep=("Body", "ArmL", "ArmR")):
    """Passa a roupa inteira para o esqueleto (roupa com pele, ver body_mesh.py): cada peça rígida fica 100% no
    osso do pivô em que estava; o pano de `soft` herda, vértice a vértice, os pesos do corpo logo abaixo (dobra
    com o braço); cada enfeite de `orn` herda os pesos do ponto onde está (vai inteiro, sem deformar)."""
    from mathutils.kdtree import KDTree
    bpy.context.view_layer.update()
    meshes = [o for o in scn.objects if o.type == 'MESH']
    bone_of = {o.name: (o.parent.name if o.parent else "Body") for o in meshes}
    world = {o.name: o.matrix_world.copy() for o in meshes}
    empties = [o for o in scn.objects if o.type == 'EMPTY']
    rig, src = _cb_start(M)
    kd = KDTree(len(src.data.vertices))
    for v in src.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    gname = {g.index: g.name for g in src.vertex_groups}

    def weights(p):
        acc = {}
        for co, idx, dist in kd.find_n(p, 10):
            w = 1.0 / (dist + 0.02) ** 2
            for ge in src.data.vertices[idx].groups:
                b = gname[ge.group]
                if b in keep:
                    acc[b] = acc.get(b, 0.0) + ge.weight * w
        tot = sum(acc.values())
        return {b: w / tot for b, w in acc.items()} if tot > 0 else {"Body": 1.0}

    def put(o, idx, W):
        for b, w in W.items():
            g = o.vertex_groups.get(b) or o.vertex_groups.new(name=b)
            g.add(idx, w, 'REPLACE')
    for o in meshes:
        mw = world[o.name]
        if o in soft:
            for v in o.data.vertices:
                put(o, [v.index], weights(mw @ v.co))
        elif o in orn:
            cen = sum((mw @ v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)
            put(o, [v.index for v in o.data.vertices], weights(cen))
        else:
            put(o, [v.index for v in o.data.vertices], {bone_of[o.name]: 1.0})
        o.parent = rig
        o.matrix_world = mw
        o.modifiers.new("Armature", 'ARMATURE').object = rig
    for e in empties:
        bpy.data.objects.remove(e, do_unlink=True)
    bpy.data.objects.remove(src, do_unlink=True)
    join_objs("Mantle", list(soft) + list(orn))


def g_skin_finish(rig, src, groups):
    """Passa a roupa inteira para o esqueleto (roupa com pele, ver body_mesh.py). groups = [(peças, modo, ossos,
    quanto)]: modo "vert" = o pano herda, vértice a vértice, os pesos do corpo logo abaixo (dobra com o membro);
    "island" = o enfeite herda os pesos do ponto onde está (vai inteiro, sem deformar); "fn" = `ossos` é uma
    função posição -> {osso: peso}. `ossos` limita a herança
    e `quanto` (0..1) é a parte do caminho que a peça faz com os ossos que não são o Body. Peças tiradas do corpo
    (cb_piece) já vêm com pesos; as demais ficam 100% no osso do pivô em que estavam."""
    from mathutils.kdtree import KDTree
    bpy.context.view_layer.update()
    meshes = [o for o in scn.objects if o.type == 'MESH' and o is not src]
    world = {o.name: o.matrix_world.copy() for o in meshes}
    empties = [o for o in scn.objects if o.type == 'EMPTY']
    kd = KDTree(len(src.data.vertices))
    for v in src.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    gname = {g.index: g.name for g in src.vertex_groups}

    def weights(p, keep, part):
        acc = {}
        for co, idx, dist in kd.find_n(p, 10):
            w = 1.0 / (dist + 0.02) ** 2
            for ge in src.data.vertices[idx].groups:
                b = gname[ge.group]
                if b in keep:
                    acc[b] = acc.get(b, 0.0) + ge.weight * w
        tot = sum(acc.values())
        if tot <= 0:
            return {"Body": 1.0}
        W = {b: w / tot for b, w in acc.items()}
        for b in [b for b in W if b != "Body"]:
            W["Body"] = W.get("Body", 0.0) + W[b] * (1 - part)
            W[b] *= part
        return W

    def put(o, idx, W):
        for b, w in W.items():
            g = o.vertex_groups.get(b) or o.vertex_groups.new(name=b)
            g.add(idx, w, 'REPLACE')
    mode = {}
    for objs, md, keep, part in groups:
        for o in objs:
            mode[o.name] = (md, keep, part)
    for o in meshes:
        if o.parent is rig:
            continue                                    # casca do corpo: já tem pesos e esqueleto
        mw = world[o.name]
        md, keep, part = mode.get(o.name, ("rigid", (), 1.0))
        if md == "vert":
            for v in o.data.vertices:
                put(o, [v.index], weights(mw @ v.co, keep, part))
        elif md == "fn":
            for v in o.data.vertices:
                put(o, [v.index], keep(mw @ v.co))
        elif md == "fn_island":
            cen = sum((mw @ v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)
            put(o, [v.index for v in o.data.vertices], keep(cen))
        elif md == "island":
            cen = sum((mw @ v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)
            put(o, [v.index for v in o.data.vertices], weights(cen, keep, part))
        else:
            put(o, [v.index for v in o.data.vertices], {o.parent.name if o.parent else "Body": 1.0})
        o.parent = rig
        o.matrix_world = mw
        o.modifiers.new("Armature", 'ARMATURE').object = rig
    for e in empties:
        bpy.data.objects.remove(e, do_unlink=True)
    bpy.data.objects.remove(src, do_unlink=True)


# ------------------------------------------------------------------ tronco e faixa do Arquimago (malha lisa)
def g_subdiv(ob, levels=1):
    """Alisa uma casca tirada do corpo: subdivide (os pesos acompanham) e liga o sombreamento liso."""
    md = ob.modifiers.new("Sub", 'SUBSURF')
    md.levels = levels
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    ob.modifiers.remove(md)
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def g_bead(name, c, r, material, parent):
    c = Vector(c)
    rows = [[c + Vector((math.sin(2 * math.pi * j / 12) * math.sin(math.pi * i / 6) * r,
                         -math.cos(2 * math.pi * j / 12) * math.sin(math.pi * i / 6) * r,
                         r * math.cos(math.pi * i / 6))) for j in range(12)] for i in range(1, 6)]
    return g_smooth_mesh(name, [[c + Vector((0, 0, r * 0.98)) + (q - c) * 0.05 for q in rows[0]]] + rows, material, parent)


def g_tassel(name, top, ln, material, parent, k=1.0):
    top = Vector(top)
    tube = g_curved_tube([top + Vector((0, 0, -ln * x)) for x in (0.0, 0.18, 0.45, 0.82, 1.0)],
                         [(r * k, r * k) for r in (0.005, 0.011, 0.01, 0.013, 0.011)], sides=12)
    return g_smooth_mesh(name, tube, material, parent)


def archmage_torso(A, src, body):
    """Tronco e faixa: casaco marinho justo tirado da malha do corpo (dobra junto com ele), com peitilho creme
    entre dois frisos e botões de pérola; faixa vinho enrolada em três voltas com debrum dourado; fivela redonda
    com aro, pérolas e gema sobre uma placa em V; correntes de elos da fivela aos quadris; dois cordões com conta
    e borla no quadril esquerdo; nó com duas pontas de pano caindo no quadril direito.
    Devolve (casaco, pontas): o casaco já vem com os pesos do corpo; as pontas dobram com a perna."""
    from mathutils.bvhtree import BVHTree
    cloth, cream, wine, gold, jewel = A["cloth"], A["cream2"], A["wine2"], A["gold2"], A["gem"]
    o = A.get("o", {})
    nw = o.get("wraps", 3)

    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.51

    coat = cb_piece(src, "Coat", is_torso, 0.016, cloth,
                    mat_fn=lambda f: 1 if (abs(f.calc_center_median().x) < 0.05 and f.calc_center_median().y < 0
                                           and 1.02 < f.calc_center_median().z < 1.46) else 0, mats=(cream,))
    g_subdiv(coat)
    me = coat.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    def rad(a):
        return Vector((math.sin(a), -math.cos(a), 0))

    def hit_a(a, z, out=0.0):
        r = rad(a)
        loc = bvh.ray_cast(Vector((0, 0, z)) + r * 0.8, -r)[0]
        if loc is None:
            loc = Vector((0, 0, z)) + r * 0.13
        return loc + r * out

    def hit_x(x, z, out=0.0):
        loc = bvh.ray_cast(Vector((x, -0.8, z)), Vector((0, 1, 0)))[0]
        return (loc if loc is not None else Vector((x, -0.12, z))) + Vector((0, -out, 0))

    parts = []
    # ---- peitilho: frisos nas bordas e botões de pérola no meio
    for sn, s in (("L", 1), ("R", -1)):
        parts.append(g_pipe("Plastron" + sn, [hit_x(s * 0.052, 1.36 - 0.03 * i, 0.003) for i in range(10)], 0.0045,
                            gold, body))
    for k, z in enumerate((1.3, 1.24, 1.18, 1.125)):
        parts.append(g_cap("Button%d" % k, hit_x(0.0, z, -0.002), (0, -1, 0), (1, 0, 0), 0.009, 0.009, 0.008, gold, body,
                           rings=4, sides=10))

    # ---- faixa enrolada: três voltas roliças, cada uma um pouco torta, a de cima por cima; debrum nas bordas
    N = 40
    wraps = ((0.957, 0.031, 0.011, 0.4), (1.006, 0.031, -0.013, 1.9), (1.055, 0.031, 0.01, 3.6))

    def wrap_pt(k, a, t):
        zc, hh, tilt, ph = wraps[k]
        return hit_a(a, zc + hh * t + tilt * math.sin(a + ph), 0.011 + 0.004 * k + 0.013 * (1 - t * t))
    for k in range(nw):
        rows = [[wrap_pt(k, 2 * math.pi * j / N, t) for j in range(N)] for t in (-1.0, -0.6, 0.0, 0.6, 1.0)]
        parts.append(g_smooth_mesh("Sash%d" % k, rows, wine, body, cap_end=False, outward=True))
    for nm, k, t in (("SashPipeLo", 0, -1.0), ("SashPipeHi", nw - 1, 1.0)):
        parts.append(g_pipe(nm, [wrap_pt(k, 2 * math.pi * j / N, t) + rad(2 * math.pi * j / N) * 0.003 for j in range(N)],
                            0.0058, gold, body, loop=True))

    # ---- fivela: placa em V com asas, disco com aro, pérolas e gema
    fwd = Vector((0, -1, 0))
    bc = hit_a(0.0, 1.008, 0.034)
    fang = [(-0.078, 0.02), (-0.046, 0.03), (-0.024, 0.002), (0, -0.01), (0.024, 0.002), (0.046, 0.03), (0.078, 0.02),
            (0.05, -0.014), (0.02, -0.05), (0, -0.14), (-0.02, -0.05), (-0.05, -0.014)]
    if o.get("fang", True):
        parts.append(g_plate("BuckleFang", fang, bc + Vector((0, 0.012, -0.01)), (1, 0, 0), (0, 0, 1), 0.012, gold, body))
        parts.append(g_cap("FangGem", bc + Vector((0, 0.0, -0.085)), fwd, (1, 0, 0), 0.011, 0.02, 0.009, jewel, body, rings=4,
                           sides=12))
    parts.append(g_cap("Buckle", bc, fwd, (1, 0, 0), 0.058, 0.058, 0.018, gold, body, sides=24))
    cp = lambda th, ph, lift=0.0: g_cap_pt(bc, fwd, (1, 0, 0), 0.058, 0.058, 0.018, th, ph, lift)
    parts.append(g_pipe("BuckleRim", [cp(2 * math.pi * j / 24, 0.1, 0.002) for j in range(24)], 0.0055, gold, body,
                        loop=True))
    for i in range(8):
        parts.append(g_cap("BucklePearl%d" % i, cp(2 * math.pi * i / 8, 0.5), fwd, (1, 0, 0), 0.007, 0.007, 0.007,
                           gold, body, rings=4, sides=10))
    parts.append(g_cap("BuckleGem", bc + fwd * 0.012, fwd, (1, 0, 0), 0.03, 0.03, 0.016, jewel, body, rings=5, sides=20))

    def below(a, z, out):
        """Ponto pendurado: na faixa enquanto z está nela; abaixo dela, cai abrindo junto com a saia."""
        q = hit_a(a, max(z, 0.9), out)
        q.z = z
        return q + rad(a) * max(0.0, 0.9 - z) * 0.3

    # ---- correntes de elos graúdos da fivela aos quadris, em duas voltas (a de baixo mais funda)
    for sn, s in ((("L", 1), ("R", -1)) if o.get("belt_chains", True) else ()):
        for k, (sag, a1) in enumerate(((0.07, 1.15), (0.17, 1.3))[:o.get("belt_swags", 2)]):
            pts, nr = [], []
            for i in range(25):
                t = i / 24
                a = s * (0.3 + (a1 - 0.3) * t)
                pts.append(below(a, 0.985 - sag * math.sin(math.pi * t) - 0.015 * t, 0.056 + 0.014 * math.sin(math.pi * t)))
                nr.append(rad(a))
            parts += g_links("BeltChain%s%d_" % (sn, k), pts, nr, gold, body, step=0.027, ln=0.0175, wd=0.0105,
                             r=0.0036)

    # ---- dois cordões grossos no quadril esquerdo: conta, arremate dourado e borla comprida
    for k, (a, ln) in enumerate(((0.92, 0.2), (1.14, 0.29)) if o.get("cords", True) else ()):
        pts = [below(a + 0.03 * math.sin(q * 0.9 + k), 0.945 - ln * q / 8, 0.054) for q in range(9)]
        parts.append(g_pipe("Cord%d" % k, pts, 0.0058, gold, body, sides=8))
        end = pts[-1]
        parts.append(g_bead("CordBead%d" % k, end + Vector((0, 0, -0.012)), 0.016, jewel, body))
        parts.append(g_cap("CordCap%d" % k, end + Vector((0, 0, -0.044)), (0, 0, 1), (1, 0, 0), 0.014, 0.014, 0.02, gold,
                           body, rings=4, sides=12))
        parts.append(g_tassel("CordTassel%d" % k, end + Vector((0, 0, -0.036)), 0.11, A["tassel"], body, k=1.6))

    # ---- nó no quadril direito, afastado da fivela: laço de duas alças e duas pontas largas de pano que caem
    ak = -0.9
    kc = hit_a(ak, 1.005, 0.03)
    tang = Vector((math.cos(ak), math.sin(ak), 0))
    if o.get("knot", True):
        parts.append(g_cap("SashKnot", kc, rad(ak), (0, 0, 1), 0.036, 0.034, 0.034, wine, body, sides=16))
    for k, sg in enumerate((1, -1) if o.get("knot", True) else ()):                      # alças do laço, uma para cada lado do nó
        loop = [kc + rad(ak) * (0.012 + 0.012 * math.sin(math.pi * q / 8))
                + tang * sg * (0.07 * math.sin(math.pi * q / 8) ** 0.8 + 0.006)
                + Vector((0, 0, 0.03 * math.cos(math.pi * q / 8) + 0.012)) for q in range(9)]
        parts.append(g_smooth_mesh("SashBow%d" % k, g_curved_tube(loop, [(0.006, 0.022 - 0.006 * abs(q - 4) / 4)
                                                                        for q in range(9)], sides=10,
                                                                 side0=rad(ak)), wine, body))
    tails = []
    for k, (da, ln) in enumerate(((0.16, 0.43), (-0.2, 0.33)) if o.get("knot", True) else ()):
        path, radii = [], []
        for q in range(15):
            t = q / 14
            a = ak + da * t + 0.075 * t * math.sin(t * 4.2 + k * 1.7)
            path.append(below(a, 0.985 - ln * t, 0.03 + 0.03 * min(1.0, t * 5) + 0.03 * t))
            w = 0.058 * (0.55 + 0.45 * min(1.0, t * 4)) * (1 + 0.12 * math.sin(t * 9.0 + k))
            if t > 0.88:
                w *= max(0.1, (1 - t) / 0.12)
            radii.append((w, 0.007))
        rings = g_curved_tube(path, radii, sides=14, side0=tang)
        tails.append(g_smooth_mesh("SashTail%d" % k, rings, wine, body))
        hem = []                                           # barra dourada perto da ponta
        for q in (11, 12):
            c = sum(rings[q], Vector()) / len(rings[q])
            hem.append([c + (v - c) * 1.0 + (v - c).normalized() * 0.003 for v in rings[q]])
        tails.append(g_smooth_mesh("SashTailHem%d" % k, hem, gold, body, cap_end=False, outward=True))
    join_objs("Sash", parts)
    return coat, tails


# ------------------------------------------------------------------ mangas do Arquimago (malha lisa)
def archmage_sleeves(A, src, R):
    """Mangas: braço justo tirado da malha do corpo; do meio do braço para baixo, um sino largo que abre até a
    mão, com a boca cortada em diagonal (cai mais comprida atrás, em ponta), forro lilás por dentro, debrum
    dourado roliço na boca, fio bordado e losangos perto da barra; por baixo, punho creme justo com bracelete.
    Devolve [(sino, pesos)]: o sino dobra no cotovelo (pesos pela posição ao longo do braço)."""
    cloth, lining, cream, gold = A["cloth"], A["lining"], A["cream2"], A["gold2"]
    o = A.get("o", {})
    mot = A.get("motif", gold)
    bl = o.get("bell", 1.0)      # quanto o sino abre

    def upper(c, b, n):
        return b.startswith("Arm") or (b.startswith("Elbow") and _cb_fore_t(c) < 0.3)

    def cuff(c, b, n):
        return b.startswith("Elbow") and _cb_fore_t(c) > 0.5

    g_subdiv(cb_piece(src, "SleeveUpper", upper, 0.019, cloth))
    g_subdiv(cb_piece(src, "SleeveCuff", cuff, 0.008, cream))

    bells = []
    S, n = 28, 16
    for sn, s in (("L", 1), ("R", -1)):
        elbow = R["Elbow" + sn]
        sh, el, wr = (cb_mirror(CB_J[k], s) for k in ("shoulder", "elbow", "wrist"))
        d = (wr - el).normalized()
        out = Vector((s, 0, 0))
        ctrl = [sh.lerp(el, 0.5), el + out * 0.004, el.lerp(wr, 0.45) + out * 0.01, el.lerp(wr, 0.78) + out * 0.02,
                wr + d * o.get("bell_len", -0.02) + out * 0.026]
        path = g_spline(ctrl, n)
        rx = g_spline([0.073, 0.08, 0.08 + 0.007 * bl, 0.08 + 0.01 * bl, 0.08 + 0.01 * bl], n)       # para os lados
        ry = g_spline([0.075, 0.084, 0.084 + 0.014 * bl, 0.084 + 0.03 * bl, 0.084 + 0.036 * bl], n)     # para a frente e para trás
        rings = g_curved_tube(path, list(zip(rx, ry)), sides=S, side0=(1, 0, 0))
        for i, ring in enumerate(rings):                         # boca em diagonal: atrás cai mais, em ponta
            k = max(0.0, (i / n - 0.4) / 0.6) ** 2
            for j in range(S):
                a = 2 * math.pi * j / S
                back = ((1 - math.cos(a)) / 2)
                ring[j] = ring[j] + d * (o.get("droop", 0.15) * k * back ** 2.2 - 0.045 * k * (1 - back))
        cen = [sum(r, Vector()) / S for r in rings]
        i0 = 6
        inner = [[cen[i] + (q - cen[i]) * (1 - 0.009 / max((q - cen[i]).length, 1e-4)) for q in rings[i]]
                 for i in range(n, i0 - 1, -1)]
        ob = g_smooth_mesh("Bell" + sn, rings + inner, cloth, elbow, cap_end=False, outward=True)
        ob.data.materials.append(lining)
        for pl in ob.data.polygons[(n + 1) * S:]:
            pl.material_index = 1

        def w(p, s=s, sn=sn, el=el, d=d):
            k = max(0.0, min(1.0, 0.5 + (p - el).dot(d) / 0.14))
            return {"Arm" + sn: 1 - k, "Elbow" + sn: k}
        bells.append((ob, w))

        # ---- enfeites rígidos no antebraço: debrum da boca, fio bordado, losangos, bracelete
        parts = [g_pipe("BellPiping" + sn, rings[n], 0.0075, gold, elbow, sides=8, loop=True),
                 g_pipe("BellThread" + sn, [q + (q - cen[n - 3]).normalized() * 0.003 for q in rings[n - 3]], 0.0034,
                        gold, elbow, sides=6, loop=True)]
        for j in (range(0, S, 2) if o.get("bell_diamonds", True) else ()):
            q = (rings[n - 1][j] + rings[n - 2][j]) / 2
            c = (cen[n - 1] + cen[n - 2]) / 2
            nr = (q - c).normalized()
            up = (rings[n - 2][j] - rings[n - 1][j]).normalized()
            parts.append(g_plate("BellDiamond%s%d" % (sn, j), [(x * 0.011, y * 0.011) for x, y in g_shape(o, j // 2, G_DIAMOND)],
                                 q + nr * 0.004, up.cross(nr), up, 0.005, mot, elbow))
        side = d.cross(Vector((0, -1, 0))).normalized()
        fw = side.cross(d).normalized()
        for k, (off, r) in enumerate(((-0.012, 0.047), (0.004, 0.045))):
            ring = [wr + d * off + (side * math.sin(2 * math.pi * j / 16) + fw * math.cos(2 * math.pi * j / 16)) * r
                    for j in range(16)]
            parts.append(g_pipe("Bracelet%s%d" % (sn, k), ring, 0.006, gold, elbow, sides=8, loop=True))
        join_objs("BellTrim" + sn, parts)
    return bells


# ------------------------------------------------------------------ saia do Arquimago (pano com esqueleto)
SLIT_T = 0.4                 # fração da altura da saia onde começa a fenda de trás
SLIT_Z = 1.0 - SLIT_T * 0.85      # a mesma altura em metros (a saia vai de 1,0 até ~0,15)


def archmage_skirt(A, body):
    """Saia: veste creme inteira até o tornozelo, em pregas macias; por cima, casaco marinho aberto na frente,
    com forro lilás, pregas mais fundas e barra em três pontas (uma grande atrás e uma em cada canto da frente),
    debrum dourado roliço na abertura e na barra, fio bordado, losangos e estrelas; na frente, um painel marinho
    que cai da fivela até a canela, com debrum, gema, estrela, losangos e uma lua com estrela na ponta.
    Devolve (panos, enfeites, pesos): o pano acompanha a coxa e a canela do lado em que está (metade do caminho
    no meio, onde as duas pernas se equilibram); os enfeites usam os pesos do ponto onde estão."""
    cloth, lining, cream, gold, jewel = A["cloth"], A["lining"], A["cream2"], A["gold2"], A["gem"]
    o = A.get("o", {})
    mot = A.get("motif", gold)
    knee_z = CB_J["knee"].z

    def W(p):
        back = max(0.0, min(1.0, 0.5 + p.y / 0.14))             # atrás o pano segue a canela quase inteiro:
        leg = max(0.0, min(1.0, (0.98 - p.z) / 0.22)) * (0.85 + 0.12 * back)     # o calcanhar levanta a barra
        left = max(0.0, min(1.0, 0.5 + p.x / 0.14))
        cut = back * max(0.0, min(1.0, (SLIT_Z - p.z) / 0.1))    # abaixo da fenda de trás, cada lado é de uma perna
        left = left * (1 - cut) + (1.0 if p.x > 0 else 0.0) * cut
        kn =max(0.0, min(1.0, (knee_z + 0.08 - p.z) / 0.2)) * (0.7 + 0.28 * back)
        w = {"Body": 1.0 - leg}
        for n, sh in (("L", left), ("R", 1.0 - left)):
            w["Leg" + n] = leg * sh * (1 - kn)
            w["Knee" + n] = leg * sh * kn
        return {b: v for b, v in w.items() if v > 1e-4}

    def pt(a, t, grow, z1, nf, amp, ph):
        e = t ** 0.8
        f = t * (amp * math.cos(nf * a + ph) + amp * 0.3 * math.cos((2 * nf - 1) * a))
        return Vector((math.sin(a) * (0.176 + 0.125 * e + grow + f), 0.005 - math.cos(a) * (0.14 + 0.13 * e + grow + f),
                       1.0 - t * (1.0 - z1)))

    soft, orn = [], []
    rows = 14

    def slit(t):
        """Meia abertura (rad) da fenda de trás: fechada até a coxa, abre até a barra."""
        return 0.11 * max(0.0, (t - SLIT_T) / (1 - SLIT_T)) ** 0.8

    # ---- veste creme: anel aberto atrás pela fenda
    N = 72

    def upt(j, t):
        g = slit(t)
        a = -math.pi + g + (2 * math.pi - 2 * g) * j / N
        return pt(a, t, 0.0, 0.1 + 0.006 * math.cos(9 * a), 9, 0.016, 0.6)
    under = [[upt(j, i / rows) for j in range(N + 1)] for i in range(rows + 1)]
    soft.append(g_smooth_mesh("Under", under, cream, body, cap_end=False, closed=False, outward=True))
    soft.append(g_pipe("UnderPiping", under[-1], 0.006, gold, body))

    # ---- casaco: aberto na frente (a abertura alarga para baixo) e fendido atrás, em duas metades; barra em
    # pontas (um par de caudas atrás e uma ponta em cada canto da frente), forro por dentro
    NC = 64
    H = NC // 2

    def hem(a):
        return (0.2 - o.get("hem_depth", 0.07) * max(0.0, math.cos(o.get("hem_pts", 3) * (a - math.pi))) ** 2
                - 0.07 * ((1 - math.cos(a)) / 2) ** 2)

    def cpt(j, t, inset=0.0, half=0):
        a0, g = o.get("open", 0.42) + 0.22 * t, slit(t)
        if half == 0:
            a = a0 + (math.pi - g - a0) * j / H
        else:
            a = math.pi + g + (math.pi - g - a0) * (j - H) / H
        return pt(a, t, 0.032 - inset, hem(a), 7, 0.024, 2.0)
    outer = []                                              # grade inteira (as duas metades), para os bordados
    for half, js in ((0, range(0, H + 1)), (1, range(H, NC + 1))):
        out_h = [[cpt(j, i / rows, 0.0, half) for j in js] for i in range(rows + 1)]
        in_h = [[cpt(j, i / rows, 0.009, half) for j in js] for i in range(rows, -1, -1)]
        coat = g_smooth_mesh("CoatSkirt%d" % half, out_h + in_h, cloth, body, cap_end=False, closed=False, outward=True)
        coat.data.materials.append(lining)
        for pl in coat.data.polygons[(rows + 1) * H:]:
            pl.material_index = 1
        soft.append(coat)
        edge = [out_h[i][0] for i in range(rows + 1)] + out_h[-1][1:-1] + [out_h[i][-1] for i in range(rows, -1, -1)]
        soft.append(g_pipe("CoatPiping%d" % half, edge, 0.0075, gold, body))
        soft.append(g_pipe("CoatThread%d" % half, [q + Vector((q.x, q.y, 0)).normalized() * 0.003
                                                   for q in out_h[rows - 2]], 0.0034, gold, body, sides=6))
        outer = out_h if half == 0 else [a + b[1:] for a, b in zip(outer, out_h)]

    def motif(name, outline, q, q_up, size, thick=0.005):
        nr = Vector((q.x, q.y, 0)).normalized()
        up = (q_up - q).normalized()
        return g_plate(name, [(x * size, y * size) for x, y in outline], q + nr * 0.004, up.cross(nr), up, thick, mot,
                       body)
    for j in (range(3, NC - 2, 3) if o.get("coat_diamonds", True) else ()):
        orn.append(motif("CoatDiamond%d" % j, g_shape(o, j, G_DIAMOND), (outer[rows - 1][j] + outer[rows][j]) / 2, outer[rows - 1][j],
                         0.013))
    for k, (j, i) in enumerate(((7, 8), (16, 6), (25, 9), (32, 5), (39, 9), (48, 6), (57, 8)) if o.get("coat_stars", True) else ()):
        orn.append(motif("CoatStar%d" % k, g_shape(o, k, g_star4(1.0, 0.32)), outer[i][j], outer[i - 1][j], 0.024 if k % 2 else 0.017))

    # ---- painel da frente (opcional)
    if o.get("tabard", True):
        # ---- painel da frente: cai da fivela, por fora da veste, até a canela; termina em ponta
        n = 14
        path, radii = [], []
        for q in range(n + 1):
            u = q / n
            z = 0.955 - 0.66 * u
            t = (1.0 - z) / 0.9
            path.append(Vector((0, 0.005 - (0.14 + 0.13 * t ** 0.8 + 0.03 + 0.012 * math.sin(math.pi * u)), z)))
            w = 0.07 - 0.012 * u
            if u > 0.84:
                w *= max(0.06, (1 - u) / 0.16)
            radii.append((w, 0.006))
        S = 16
        rings = g_curved_tube(path, radii, sides=S, side0=(1, 0, 0))
        soft.append(g_smooth_mesh("Tabard", rings, cloth, body))
        border = [rings[i][S // 4] for i in range(n + 1)] + [rings[i][3 * S // 4] for i in range(n, -1, -1)]
        soft.append(g_pipe("TabardPiping", border, 0.0058, gold, body, loop=True))

        def on_tab(i):
            fw = (rings[i][0] - path[i]).normalized()
            up = (path[max(i - 1, 0)] - path[min(i + 1, n)]).normalized()
            return path[i] + fw * 0.0095, fw, up.cross(fw).normalized(), up
        c, fw, side, up = on_tab(2)
        orn.append(g_cap("TabardSeat", c - fw * 0.004, fw, side, 0.03, 0.036, 0.012, gold, body, sides=16))
        orn.append(g_cap("TabardGem", c + fw * 0.004, fw, side, 0.018, 0.024, 0.012, jewel, body, rings=5, sides=14))
        for k, (i, shape, size) in enumerate(((5, g_star4(1.0, 0.3), 0.034), (7, G_DIAMOND, 0.013), (8, G_DIAMOND, 0.018),
                                              (10, g_star4(1.0, 0.3), 0.018))):
            c, fw, side, up = on_tab(i)
            orn.append(g_plate("TabardMotif%d" % k, [(x * size, y * size) for x, y in shape], c, side, up, 0.006, mot, body))
        c, fw, side, up = on_tab(11)
        orn.append(g_crescent("TabardMoon", c - up * 0.012, up, -side, 0.007, mot, body, r=0.036, r_in=0.03, d=0.016))
    return soft, orn, W


# ------------------------------------------------------------------ mantos de mago: molde com opções
# As quatro peças do manto (archmage_mantle, _torso, _sleeves, _skirt), o chapéu (build_hat) e o capuz
# (build_hood) leem as cores de A e as opções de A["o"]; sem opções, sai o Manto do Arquimago. Cada conjunto de
# ROBES vira dois estilos: a_<nome> (manto) e h_<nome> (chapéu ou capuz).
G_RUNES = [
    [(-0.5, 1), (0.5, 0), (-0.5, -1), (-0.12, -1), (0.88, 0), (-0.12, 1)],                    # ângulo
    [(-0.2, 1), (0.2, 1), (0.2, -1), (-0.2, -1)],                                             # traço
    [(-0.6, 1), (0, 0.28), (0.6, 1), (0.6, -1), (0, -0.28), (-0.6, -1)],                      # ampulheta
    [(0, 1), (0.7, 0.16), (0.24, 0.02), (0.24, -1), (-0.24, -1), (-0.24, 0.02), (-0.7, 0.16)],    # seta
]


def g_shape(o, k, default):
    """Contorno do bordado: o padrão da peça ou, nos mantos rúnicos, uma das runas."""
    return G_RUNES[k % len(G_RUNES)] if o.get("motif") == "rune" else default


def robe_mats(pre, sp):
    c = sp["colors"]
    trim = gm(pre + "_trim", c["trim"], 0.45, c.get("metal", 0.3))
    jewel = mat(pre + "_gem_flat", hexc(c["gem"]), 0.3, 0.0, emit=hexc(c["glow"]), strength=c.get("glow_k", 1.2))
    return dict(
        coat=gm(pre + "_hip", c["cloth"], 0.95), cloth=gm(pre + "_cloth", c["cloth"], 0.95),
        lining=gm(pre + "_lining", c["lining"], 0.9), lining2=gm(pre + "_lining2", c.get("lining2", c["cloth"]), 0.9),
        gold2=trim, cream2=gm(pre + "_under", c["under"], 0.9), wine2=gm(pre + "_sash", c["sash"], 0.9),
        tassel=gm(pre + "_tassel", c["tassel"], 0.9), gem=jewel,
        motif=jewel if sp["o"].get("glow_motif") else trim, o=sp["o"],
        felt=gm(pre + "_felt", c.get("felt", c["cloth"]), 0.95), hatlining=gm(pre + "_hatlining", c.get("hatlining", c["lining"]), 0.9),
    )


def build_robe(style, A):
    """Manto em malha lisa e com esqueleto (roupa com pele, ver body_mesh.py): gola e ombros (archmage_mantle),
    tronco e faixa (archmage_torso), mangas (archmage_sleeves) e saia (archmage_skirt). Pescoço, quadril e coxas
    por baixo continuam peças simples. Cores fixas (não tinge pelo item)."""
    P, R = g_rig(style)
    M = g_mats()
    body = R["Body"]
    rig, src = _cb_start(M)          # esqueleto + corpo com pesos: fonte das cascas e dos pesos do pano
    neck(R, M["skin"])
    hips(R, A["coat"])
    thighs(P, R, M["pants"])
    soft, orn = archmage_mantle(P, R, A, body)
    coat_ob, sash_tails = archmage_torso(A, src, body)
    bells = archmage_sleeves(A, src, R)
    sk_soft, sk_orn, sk_w = archmage_skirt(A, body)
    if "loose_parts" in globals():
        loose_parts(style)
    # sombra assada na cor por vértice; as peças antigas (_flat) ainda recebem a pintura por face
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin", A["gem"].name))
    arms = ("Body", "ArmL", "ArmR")
    g_skin_finish(rig, src, [(soft, "vert", arms, 0.5), (orn, "island", arms, 0.5),
                             (sash_tails, "vert", ("Body", "LegR"), 0.7)]
                  + [([ob], "fn", fn, 1.0) for ob, fn in bells]
                  + [(sk_soft, "fn", sk_w, 1.0), (sk_orn, "fn_island", sk_w, 1.0)])
    join_objs("Skirt", list(sk_soft) + list(sk_orn))
    join_objs("Mantle", list(soft) + list(orn))
    export("gear/" + style, export_vertex_color='ACTIVE')


def build_a_archmage():
    build_robe("a_archmage", archmage_mats())


def build_hood(style, A, o):
    """Capuz liso: casca dupla em volta da cabeça (pano por fora, forro por dentro), aberta na frente para o
    rosto, com a borda da abertura avançada, ponta caída para trás e gola larga que assenta nos ombros; debrum
    roliço na abertura e na barra, e um enfeite na testa (gema, lua ou runa)."""
    P, R = g_rig(style)
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    cloth, lining, trim, jewel, mot = A["felt"], A["hatlining"], A["gold2"], A["gem"], A["motif"]
    hc = Vector((0, 0.018, 1.688))
    ax, ay, az = 0.142, 0.162, 0.168
    PB = -0.45

    def open_half(ph):
        if ph > -0.1:
            return 0.98 * math.sqrt(max(0.0, 1 - ((ph + 0.1) / 1.08) ** 2))
        return 0.98 - 0.4 * min(1.0, (-0.1 - ph) / 0.8)

    def hp(th, ph, inset=0.0):
        if ph >= PB:
            rr, z = math.cos(ph), hc.z + math.sin(ph) * (az - inset)
        else:
            k = PB - ph
            rr, z = math.cos(PB) * (1 + 0.95 * k), hc.z + math.sin(PB) * az - 0.24 * k
        p = Vector((math.sin(th) * rr * (ax - inset), hc.y - math.cos(th) * rr * (ay - inset), z))
        w = max(0.0, -math.cos(th)) ** 3 * math.exp(-((ph - 0.75) / 0.42) ** 2) * o.get("tail", 1.0)
        return p + Vector((0, 0.15, -0.045)) * w

    na, rows = 30, 20
    rings, edge_l, edge_r, top_i = [], [], [], rows
    for i in range(rows + 1):
        ph = -0.9 + 2.4 * i / rows
        t0 = open_half(ph)
        angs = [t0 + (2 * math.pi - 2 * t0) * j / na for j in range(na + 1)]

        def lip(th, t0=t0):          # a borda da abertura avança sobre o rosto
            if t0 < 0.05:
                return Vector()
            return Vector((0, -0.035 * math.exp(-min(th - t0, 2 * math.pi - t0 - th) / 0.28), 0))
        rings.append([hp(a, ph) + lip(a) for a in angs] + [hp(a, ph, 0.012) + lip(a) for a in reversed(angs)])
        if t0 >= 0.05:
            edge_l.append(rings[-1][0])
            edge_r.append(rings[-1][na])
        else:
            top_i = min(top_i, i)
    hood = g_smooth_mesh("Hood", rings, cloth, head)
    hood.data.materials.append(lining)
    per = 2 * (na + 1)
    for pl in hood.data.polygons[:rows * per]:
        if na < pl.index % per < per - 1:
            pl.material_index = 1
    parts = [hood, g_pipe("HoodPiping", edge_l + [rings[top_i][0]] + edge_r[::-1], 0.007, trim, head),
             g_pipe("HoodHem", rings[0][:na + 1], 0.006, trim, head),
             # apoio escondido por dentro: o capuz assenta no alto da cabeça
             g_cap("HoodPad", (0, hc.y, 1.795), (0, 0, 1), (1, 0, 0), 0.07, 0.08, 0.05, lining, head, rings=4, sides=12)]
    c = rings[top_i][0] + Vector((0, -0.004, -0.012))
    n, side = Vector((0, -1, 0.35)).normalized(), Vector((1, 0, 0))
    crest = o.get("crest", "gem")
    if crest == "gem":
        parts.append(g_cap("HoodSeat", c, n, side, 0.026, 0.032, 0.012, trim, head, sides=16))
        parts.append(g_cap("HoodGem", c + n * 0.008, n, side, 0.015, 0.021, 0.012, jewel, head, rings=5, sides=14))
    elif crest == "moon":
        up = n.cross(side)
        parts.append(g_crescent("HoodMoon", c - n * 0.004, -up, side, 0.012, mot, head, r=0.036, r_in=0.03, d=0.016))
    elif crest == "rune":
        up = n.cross(side)
        parts.append(g_plate("HoodRune", [(x * 0.02, y * 0.02) for x, y in G_RUNES[3]], c - n * 0.004, side, -up, 0.012,
                             mot, head))
    if "loose_parts" in globals():
        loose_parts(style)
    join_objs("Hood", parts)
    g_export(style, P, R)


# Conjuntos: cores (pano, forro, friso, veste de baixo, faixa, borla, gema e brilho) e opções de forma.
ROBES = {
    # referência 2: sábio de branco e ouro sobre azul-marinho, mangas amplas, ombreiras e correntes
    "sage": dict(head="hat", colors=dict(cloth="#D8D4CA", lining="#27306A", trim="#D6A63A", under="#232A5E",
                                         sash="#5E4334", tassel="#A8482F", gem="#FFE2A0", glow="#F2B84A",
                                         felt="#20244C", hatlining="#5C1A34"),
                 o=dict(vee=0.07, wing=0.05, back="sun", stars=False, open=0.52, hem_pts=2, bell=2.3, bell_len=0.03,
                        droop=0.2, emblem="sun", brim=0.92)),
    # referência 3: arcanista de negro com linhas douradas e runas azuis que brilham, encapuzado
    "void": dict(head="hood", colors=dict(cloth="#15161F", lining="#1F4FA6", trim="#B08A36", under="#0F1018",
                                          sash="#1B2A55", tassel="#3FA8E8", gem="#9FE6FF", glow="#3FB8FF", glow_k=2.0),
                 o=dict(glow_motif=True, motif="rune", pauldron=False, fringe=False, chains=False, vee=0.14,
                        back="rune", collar=0.35, cords=False, belt_swags=1, open=0.2, hem_pts=4, bell=2.0,
                        droop=0.22, crest="moon")),
    # referência 4: oráculo de cinza-violeta com frisos de prata, murça em três camadas, encapuzado
    "oracle": dict(head="hood", colors=dict(cloth="#4A4460", lining="#2C5A64", lining2="#C4C8D4", trim="#C9CCD6",
                                            metal=0.5, under="#1B1925", sash="#35304A", tassel="#C9CCD6",
                                            gem="#E6DAFF", glow="#B79CFF"),
                   o=dict(pauldron=False, fringe=False, chains=False, layers=3, vee=0.09, wing=0.06, stars=False,
                          collar=0.35, fang=False, cords=False, knot=False, belt_swags=1, open=0.3, hem_pts=0,
                          tabard=False, bell=1.6, droop=0.1, crest="gem")),
    # referência 5: manto de carvão com runas de brasa, ombros em asas pontudas, mangas enormes, encapuzado
    "ember": dict(head="hood", colors=dict(cloth="#2A2B33", lining="#5A2A1E", lining2="#3B3C47", trim="#9C6B3A",
                                           under="#19191F", sash="#3A2E2A", tassel="#D9622B", gem="#FFC08A",
                                           glow="#FF7A2A", glow_k=2.0),
                  o=dict(glow_motif=True, motif="rune", pauldron=False, fringe=False, layers=3, wing=0.09, vee=0.12,
                         back="rune", collar=0.35, cords=False, knot=False, belt_chains=False, open=0.12, hem_pts=2,
                         hem_depth=0.12, tabard=False, bell=2.6, bell_len=0.05, droop=0.25, crest="rune", tail=1.3)),
}


def _robe_builders():
    for key, sp in ROBES.items():
        pre = "rb_" + key
        globals()["build_a_" + key] = lambda sp=sp, key=key, pre=pre: build_robe("a_" + key, robe_mats(pre, sp))
        if sp["head"] == "hat":
            def hat(sp=sp, key=key, pre=pre):
                A = robe_mats(pre, sp)
                build_hat("h_" + key, dict(felt=A["felt"], lining=A["hatlining"], gold=A["gold2"], gem=A["gem"],
                                           tassel=A["tassel"]), sp["o"])
            globals()["build_h_" + key] = hat
        else:
            globals()["build_h_" + key] = lambda sp=sp, key=key, pre=pre: build_hood("h_" + key, robe_mats(pre, sp),
                                                                                    sp["o"])


_robe_builders()


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


def _foot_secs(P, s, k, add):
    """Seções do pé do calçado, com uma seção a mais à frente, baixa e estreita, que arredonda o bico."""
    f = P["ft"]
    ft = grow(limb_sections(P, s)["foot"], k, add)
    tip = dict(ft[-1], c=ft[-1]["c"] + Vector((0, -0.022 * f, -0.006 * f)), rx=ft[-1]["rx"] * 0.62,
               ry=ft[-1]["ry"] * 0.6)
    return ft + [tip]


def _shoe(P, R, n, s, upper, sole, k=1.08, add=0.006, top=None, heel=0.0):
    """Pé do calçado e sola, no pivô do tornozelo (AnkleX): giram sem a canela na passada.
    A sola segue o contorno do pé (calcanhar e bico redondos, cintura no arco) com só uma borda fina para fora;
    heel > 0 engrossa a sola no calcanhar (salto da bota) na mesma peça."""
    ankle = R["Ankle" + n]
    f = P["ft"]
    ft = _foot_secs(P, s, k, add)
    parts = [loft("Leg%s_Foot" % n, ft, upper, ankle, fwd=(0, 0, 1), chamfer=(0.01, 0.006))]
    parts.append(foot_sole("Leg%s_Sole" % n, ft, sole, ankle, f, heel=heel))
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
        join_objs("Leg%s_ShoeFoot" % n, _shoe(P, R, n, s, M["lea"], M["lea_d"]))
        parts = []
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
        foot = _shoe(P, R, n, s, bt, bt2, heel=0.01 * P["ft"])
        parts = [loft("Leg%s_Shaft" % n, grow(span(S["shin"], 0.2, 1.0), 1.14, 0.01), bt, knee)]
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
        # costura na frente do cano
        fr = [dict(x, c=x["c"]) for x in grow(span(S["shin"], 0.32, 0.95), 1.14, 0.013)]
        parts.append(loft("Leg%s_BootSeam" % n, [sec(Vector((x["c"].x, x["c"].y - x["ry"] * x["fr"], x["c"].z)),
                                                    0.004, 0.003) for x in fr], bt2, knee, sides=4, fwd=(0, -1, 0)))
        join_objs("Leg%s_BootFoot" % n, foot)
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
        foot = _shoe(P, R, n, s, bt, M["lea_d"])
        parts = [loft("Leg%s_Shaft" % n, grow(span(S["shin"], 0.12, 1.0), 1.14, 0.01), bt, knee)]
        parts.append(loft("Leg%s_Greave" % n, grow(span(S["shin"], 0.1, 0.85), 1.24, 0.016, keel=0.14), st, knee,
                          phase=0, arc=2.4, thick=0.01, chamfer=(0.0, 0.0)))
        parts.append(loft("Leg%s_Poleyn" % n, [sec((K.x, K.y - 0.03, K.z + 0.01), 0.07, 0.074),
                                               sec((K.x, K.y - 0.074, K.z), 0.062, 0.066),
                                               sec((K.x, K.y - 0.098, K.z - 0.008), 0.04, 0.044)],
                          st, knee, fwd=(0, 0, 1), chamfer=(0.0, 0.008)))
        parts.append(wing("Leg%s_PoleynWing" % n, (K.x + s * 0.064, K.y - 0.035, K.z), 0.07, 0.09, 0.008, st, knee))
        ft = _foot_secs(P, s, 1.13, 0.012)
        foot.append(loft("Leg%s_ToeCap" % n, [dict(x) for x in ft[2:]], st, R["Ankle" + n], fwd=(0, 0, 1),
                         chamfer=(0.0, 0.01)))
        join_objs("Leg%s_BootFoot" % n, foot)
        for k, t in enumerate((0.3, 0.7)):
            parts.append(band("Leg%s_GreaveStrap%d" % (n, k), grow([sample(S["shin"], t)], 1.16, 0.012)[0],
                              S["shin"][-1]["c"] - S["shin"][0]["c"], 0.014, M["lea_d"], knee, sides=8))
        join_objs("Leg%s_Boot" % n, parts)
    g_export("f_plated", P, R)


def _gear_builder(fn):
    """armory.py redefine band() depois deste arquivo; as roupas usam a do cavaleiro (characters.py)."""
    def run():
        g = globals()
        old = g["band"]
        g["band"] = _knight_band
        try:
            fn()
        finally:
            g["band"] = old
    return run


GEAR = [(n, _gear_builder(globals()["build_" + n])) for n in (
    "h_bare", "h_hood", "h_cap", "h_kettle", "h_nasal", "h_great", "h_wizard", "h_archmage", "h_sage", "h_void", "h_oracle", "h_ember",
    "a_shirt", "a_tunic", "a_leather", "a_mail", "a_surcoat", "a_robe", "a_archmage", "a_sage", "a_void", "a_oracle", "a_ember",
    "g_bare", "g_gloves", "g_bracers",
    "f_shoes", "f_boots", "f_plated")]
