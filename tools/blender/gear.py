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
import random
from mathutils import Vector

GEAR_P = dict(height=1.84, heads=7.5, shoulders=1.08, waist=0.92, limbs=1.06, hands=1.15, feet=1.1)
HEAD_CHIN, HEAD_H = 1.555, 0.262        # cabeça humana sob os elmos (olhos ~1,68, na fenda do elmo do cavaleiro)
# Com o queixo fino da cabeça lisa (anime.py) o pescoço ficava comprido: tudo o que é da cabeça (rosto, cabelo,
# chapéus, elmos e capuzes: os estilos h_*) desce HEAD_DROP na exportação. As peças continuam modeladas nas
# alturas de sempre (muitas usam z absoluto), e descem juntas.
HEAD_DROP = 0.022
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
            soft_fist("Occ" + n, P, s, M["skin"], R["Elbow" + n])
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
        me = o.data
        col = me.color_attributes["Col"].data
        # a sombra assada sai por canto de face; com o sombreado liso cada face ficava com um tom (xadrez).
        # Vira uma média por vértice, e a sombra passa a ser um degradê contínuo
        acc = [[0.0, 0] for _ in me.vertices]
        for lp in me.loops:
            a = acc[lp.vertex_index]
            a[0] += col[lp.index].color[0]
            a[1] += 1
        for lp in me.loops:
            a = acc[lp.vertex_index]
            v = max(0.0, min(1.0, a[0] / a[1])) ** AO_GAMMA
            c = AO_FLOOR + (1 - AO_FLOOR) * v
            col[lp.index].color = (c, c, c, 1.0)
    for o in occ:
        bpy.data.objects.remove(o, do_unlink=True)


def g_export(style, P=None, R=None):
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    drop_head(style, targets)
    g_smooth(targets)
    if P is not None and targets:
        occ = _occluders(style, P, R, g_mats())
        bake_ao(targets, occ)
    export("gear/" + style, export_vertex_color='ACTIVE')


def g_smooth(objs, angle=48.0):
    """Corpo e roupas lisos, como o rosto: sombreado liso em tudo, com aresta viva só onde as faces vizinhas
    dobram mais que angle graus (bordas de placas, barras, fivelas). Peças que já são lisas ficam como estão."""
    for o in objs:
        me = o.data
        if me.polygons and not all(p.use_smooth for p in me.polygons):
            for p in me.polygons:
                p.use_smooth = True
            me.set_sharp_from_angle(angle=math.radians(angle))


def drop_head(style, objs):
    """Desce as malhas dos estilos de cabeça (h_*) em HEAD_DROP (ver a constante)."""
    if style.startswith("h_"):
        for me in set(o.data for o in objs):
            me.transform(Matrix.Translation((0, 0, -HEAD_DROP)))
            me.update()


# ------------------------------------------------------------------ UV da galáxia (Ceifador do Vazio)
# O shader da galáxia (assets/shaders/gear_galaxy.gdshader) desenha a partir da posição de repouso, vista por
# trás: u = x + 0,5 e v = z / 2 (metros, cabem em 0..1). Vai no UV porque a roupa tem esqueleto e a posição do
# vértice muda com a pose. Faces de outro material, ou viradas para a frente, ficam em (0, 0) = sem galáxia.
GALAXY_UV = {"a_reaper": (("rb_reaper_cloth",), 0.3), "a_celestial": (("cs_sky", "cs_void_flat"), None), "h_reaper": (("eg_reaper_space_gem_flat",), None)}


def g_galaxy_uv(style):
    if style not in GALAXY_UV:
        return
    names, facing = GALAXY_UV[style]
    for ob in [o for o in scn.objects if o.type == 'MESH']:
        me = ob.data
        uv = (me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")).data
        mw = ob.matrix_world
        rot = mw.to_3x3()
        mats = [m.name if m else "" for m in me.materials]
        for pl in me.polygons:
            ok = mats[pl.material_index] in names and (facing is None or (rot @ pl.normal).normalized().y > facing)
            for li in pl.loop_indices:
                w = mw @ me.vertices[me.loops[li].vertex_index].co
                uv[li].uv = (w.x + 0.5, w.z / 2) if ok else (0.0, 0.0)


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


# rosto masculino sobre a cabeça lisa (anime.py): olho mais fechado, sobrancelha grossa e baixa com cenho,
# mandíbula larga e queixo mais quadrado
MALE_FACE = {"eye_w": 0.98, "eye_h": 0.74, "lash": 0.8, "brow": 1.55, "brow_dz": -0.3, "brow_tilt": 0.14,
             "nose": 1.15, "jaw": 1.07, "chin": 0.5, "mouth_w": 1.1}
# cabelo curto: franja repartida de lado com a testa à mostra, lados acima da orelha, nuca curta
MALE_HAIR_STYLE = {"fringe": 12, "side": 2, "back": -27, "part": -24, "sweep": 1, "top": 10, "w": 1.25,
                   "lift": 1.5, "seed": 11,
                   "hairline": [(0, 37), (35, 35), (60, 27), (78, 18), (97, 15), (112, 5), (135, -22), (180, -31)]}


def plain_head(R, M, beard=False, hair=False):
    """Cabeça do herói: rosto liso desenhado (anime.py) e, com beard, barba curta. O cabelo é um equipamento à
    parte (hair.py, penteado escolhido na criação): os estilos h_* saem sem cabelo e `hair` só serve para as
    prévias de rosto."""
    head = R["Head"]
    am = anime_mats("hm", hexc("#D29A74"), hexc("#4E6A8A"), hexc("#3A2213"), hexc("#1E120A"), hexc("#9A5648"))
    H = anime_head("", HEAD_CHIN, HEAD_H, head, am, MALE_FACE)
    hm = {"hair": M["hair"], "mid": gm("g_hair_mid", "#6E4428", 0.9), "under": gm("g_hair_under", "#2B190C", 0.9)}
    if hair:
        anime_hair("", H, hm, head, MALE_HAIR_STYLE)
    if beard:
        anime_beard("", H, hm, head, {"length": 3.2, "full": 0.8})
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
    """Capuz de Couro (touca de armas): copa baixa de quatro gomos com costuras salientes e botão no alto; rolo
    acolchoado de couro escuro em volta da testa com tachas de latão; saia de couro que cobre as orelhas e a nuca,
    mais funda nas orelhas e curta atrás, com borda escura e fivela; sem tira sob o queixo.
    Copa rente à cabeça (folga medida em h_bare): couro, não um balão."""
    P, R = g_rig("h_cap")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    lea = gm("t1_cap", "#7A4E26", 0.8)
    lea_d = gm("t1d_cap", "#3E2613", 0.85)
    brass = gm("gw_cap_brass", "#B8822F", 0.4, 0.7)
    C = Vector((0, 0.012, 1.722))
    TOP = 0.118

    def prof(z):
        if z >= C.z:
            d = min(1.0, (z - C.z) / TOP)
            k = max(0.0, 1 - d ** 2.3) ** 0.5
            return 0.101 * k, 0.12 * k, 0.118 * k, 2.4 + 0.3 * (1 - d)
        return 0.101, 0.12, 0.118, 2.7

    def hp(th, z, out=0.0):
        a, bf, bb, n = prof(z)
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / n), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / n), c) * (b + out)
        return Vector((x, C.y + y, z))

    def nrm(th):
        return Vector((math.sin(th), -math.cos(th), 0))

    parts = []
    NP = 48
    zs = [C.z - 0.012 + (TOP + 0.012) * (i / 16) ** 0.85 for i in range(17)]
    parts.append(g_smooth_mesh("CapCrown", [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs], lea, head,
                               cap_end=True, outward=True))
    # costuras dos gomos: da testa à nuca e de orelha a orelha, cruzando no botão do alto
    for k, th in enumerate((0.0, math.pi / 2, math.pi, -math.pi / 2)):
        seam = [hp(th, C.z + 0.014 + (TOP - 0.016) * (i / 10) ** 0.8, 0.0015) for i in range(11)]
        parts.append(g_pipe("CapSeam%d" % k, seam, 0.0032, lea_d, head, sides=6))
    parts.append(g_cap("CapButton", C + Vector((0, 0, TOP - 0.004)), (0, 0, 1), (1, 0, 0), 0.011, 0.011, 0.008,
                       lea_d, head, sides=12))
    # saia: cobre orelhas e nuca; funda nas orelhas, curta atrás, aberta no rosto
    T0 = 1.0

    def depth(th):
        d = min(abs(th - math.pi / 2), abs(th - 3 * math.pi / 2))
        ear = max(0.0, 1 - (d / 0.75) ** 2)
        front = min(1.0, (th - T0) / 0.3, (2 * math.pi - T0 - th) / 0.3)
        front = front * front * (3 - 2 * front)
        return (0.118 - 0.012 * ear) * (0.35 + 0.65 * front)

    ths = [T0 + (2 * math.pi - 2 * T0) * j / 44 for j in range(45)]

    def sk(th, u, out=0.0):
        return hp(th, C.z - 0.004 - depth(th) * u, 0.003 + 0.007 * u ** 1.5 + out)
    skirt = [[sk(th, i / 8) for th in ths] for i in range(9)]
    parts.append(g_smooth_mesh("CapSkirt", skirt, lea, head, cap_end=False, closed=False, thick=0.005, outward=True))
    edge = [sk(T0, i / 8) for i in range(8)] + [sk(th, 1.0) for th in ths] + \
           [sk(2 * math.pi - T0, i / 8) for i in range(7, -1, -1)]
    parts.append(g_pipe("CapSkirtEdge", edge, 0.0034, lea_d, head, sides=6))
    # pesponto: linha de couro escuro acompanhando a borda por dentro
    parts.append(g_pipe("CapStitch", [sk(th, 0.8, 0.0015) for th in ths[2:-2]], 0.0016, lea_d, head, sides=5))
    for sn, sg in (("L", 1), ("R", -1)):
        th = sg * (math.pi / 2 + 0.15)
        c = sk(th if th > 0 else th + 2 * math.pi, 0.72, 0.003)
        parts.append(g_cap("CapBuckle" + sn, c, nrm(th), (0, 0, 1), 0.008, 0.01, 0.004, brass, head, sides=12))
    # rolo acolchoado na testa, em volta da cabeça toda, com tachas de latão na frente
    roll = [hp(2 * math.pi * j / NP, C.z + 0.002, 0.009) for j in range(NP)]
    parts.append(g_pipe("CapRoll", roll, 0.0095, lea_d, head, sides=10, loop=True))
    for k in range(7):
        th = -0.9 + 0.3 * k
        parts.append(g_cap("CapStud%d" % k, hp(th, C.z + 0.002, 0.018), nrm(th), (0, 0, 1), 0.004, 0.004, 0.0035,
                           brass, head, sides=10))
    g_head_done("h_cap", "Cap", parts, P, R)


def build_h_kettle():
    """Chapéu de Ferro (kettle hat): copa justa em superelipse com crista alta da testa à nuca; faixa escura rebitada
    na base; aba inclinada para baixo, curta na frente (deixa ver os olhos) e mais larga nos lados e atrás, com
    borda de latão enrolada; cortina de malha nos lados e na nuca, até o pescoço.
    A silhueta vem da aba e da crista, não de uma bola: a copa fica rente à cabeça (folga medida em h_bare)."""
    P, R = g_rig("h_kettle")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_kettle", "#A3ABB8", 0.42, 0.65)
    st_d = gm("t1d_kettle", "#5E6674", 0.5, 0.6)
    brass = gm("gw_kettle_brass", "#B8822F", 0.4, 0.7)
    chain = gm("gw_kettle_chain", "#868C96", 0.85, 0.3)
    chd = gm("gw_kettle_chain_d", "#555B65", 0.7, 0.45)
    C = Vector((0, 0.012, 1.722))
    TOP = 0.13

    def prof(z):
        """meia largura, profundidade da frente, profundidade de trás, expoente da superelipse."""
        if z >= C.z:
            d = min(1.0, (z - C.z) / TOP)
            k = max(0.0, 1 - d ** 2.1) ** 0.55
            return 0.106 * k, 0.125 * k, 0.122 * k, 2.4 + 0.4 * (1 - d)
        return 0.106, 0.125, 0.122, 2.8

    def hp(th, z, out=0.0):
        a, bf, bb, n = prof(z)
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / n), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / n), c) * (b + out)
        return Vector((x, C.y + y, z))

    def nrm(th):
        return Vector((math.sin(th), -math.cos(th), 0))

    parts = []
    NP = 56
    zs = [C.z - 0.012 + (TOP + 0.012) * (i / 16) ** 0.85 for i in range(17)]
    parts.append(g_smooth_mesh("KettleCrown", [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs], st,
                               head, cap_end=True, outward=True))
    # aba: sai da base da copa e cai para fora; curta na frente, larga nos lados e atrás
    def brim_w(th):
        c = math.cos(th)
        return 0.054 - 0.018 * max(0.0, c) ** 2 + 0.006 * max(0.0, -c)

    brim = []
    for i in range(7):
        u = i / 6
        row = []
        for j in range(NP):
            th = 2 * math.pi * j / NP
            w = brim_w(th)
            p = hp(th, C.z - 0.004, w * u)
            p.z = C.z - 0.004 - 0.05 * u ** 1.25 * (1 - 0.62 * max(0.0, math.cos(th)) ** 2)   # na frente quase reta: olhos à mostra
            row.append(p)
        row.append(row[0])
        brim.append(row)
    parts.append(g_smooth_mesh("KettleBrim", brim, st, head, cap_end=False, closed=False, thick=0.0045,
                               outward=True))
    parts.append(g_pipe("KettleBrimRoll", brim[-1][:-1], 0.0055, brass, head, sides=8, loop=True))
    # faixa escura rebitada na base da copa
    band = [[hp(2 * math.pi * j / NP, C.z - 0.004 + 0.024 * v, 0.004) for j in range(NP)] for v in (0, 0.5, 1)]
    for r in band:
        r.append(r[0])
    parts.append(g_smooth_mesh("KettleBand", band, st_d, head, cap_end=False, closed=False, thick=0.004,
                               outward=True))
    for k in range(14):
        th = 2 * math.pi * (k + 0.5) / 14
        parts.append(g_cap("KettleRivet%d" % k, hp(th, C.z + 0.008, 0.0075), nrm(th), (0, 0, 1), 0.0045, 0.0045,
                           0.003, brass, head, sides=10))
    # crista: lâmina no plano do meio, da faixa da frente até a de trás, mais alta no topo, com fio de latão
    crest, ridge = [], []
    for i in range(23):
        b = 0.12 + (math.pi - 0.24) * i / 22                # 0 frente, pi/2 topo, pi nuca
        z = C.z + 0.02 + (TOP - 0.02) * math.sin(b)
        y = hp(0.0 if b < math.pi / 2 else math.pi, z).y
        n = Vector((0, -math.cos(b) * 0.6, math.sin(b))).normalized()
        hgt = 0.003 + 0.007 * math.sin(math.pi * i / 22) ** 0.8
        base = Vector((0, y, z)) - n * 0.004
        crest.append([base + Vector((-0.009, 0, 0)), base + n * hgt, base + Vector((0.009, 0, 0))])
        ridge.append(base + n * (hgt + 0.0015))
    parts.append(g_smooth_mesh("KettleCrest", crest, st, head, cap_end=False, closed=False, thick=0.004,
                               outward=True))
    parts.append(g_pipe("KettleCrestBrass", ridge[2:-2], 0.003, brass, head, sides=6))
    # cortina de malha: pende de baixo da aba só nos lados e na nuca, até o pescoço; sem gola sob o queixo,
    # para não cobrir a gola da armadura

    def mail(th, z, out=0.0):
        w = max(0.0, min(1.0, (C.z - z) / (C.z - ZB + 0.05)))
        a = 0.102 + 0.004 * w ** 1.5
        bf, bb = 0.114 + 0.004 * w, 0.112 + 0.008 * w ** 1.5
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / 2.6), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / 2.6), c) * (b + out)
        return Vector((x, C.y + y, z))
    ZB = 1.585
    T0 = 1.0
    def zb(th):
        return ZB - 0.05 * max(0.0, -math.cos(th)) ** 1.5      # atrás desce até encostar na gola

    def cz(th, t):
        return C.z - 0.006 - (C.z - 0.006 - zb(th)) * t
    ths = [T0 + (2 * math.pi - 2 * T0) * j / 40 for j in range(41)]
    curtain = [[mail(th, cz(th, i / 10)) for th in ths] for i in range(11)]
    parts.append(g_smooth_mesh("KettleMail", curtain, chain, head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    for i, t in enumerate([0.35, 0.7]):
        pts = [mail(th, cz(th, t), 0.004) for th in [T0 + (2 * math.pi - 2 * T0) * j / 48 for j in range(49)]]
        parts.append(g_pipe("KettleMailRow%d" % i, pts, 0.0022, chd, head, sides=6))
    parts.append(g_pipe("KettleMailHem", [mail(th, zb(th), 0.004) for th in [T0 + (2 * math.pi - 2 * T0) * j / 48 for j in range(49)]],
                        0.004, brass, head, sides=8))
    for sn, sg in (("L", 1), ("R", -1)):
        parts.append(g_pipe("KettleMailEdge" + sn, [mail(sg * T0, z, 0.004) for z in (C.z - 0.006, 1.68, 1.64,
                                                                                         1.61, ZB)],
                            0.0032, brass, head, sides=6))
    g_head_done("h_kettle", "Kettle", parts, P, R)


def build_h_nasal():
    """Elmo de Ferro (nasal): crânio liso em ponta com quatro nervuras de latão até o pino do topo; faixa de latão
    rebitada na testa, que desce em ponta para a nasal colada ao nariz; bochecheiras arredondadas nos lados; cota de
    malha lisa por baixo, aberta no rosto, fechando sob o queixo e assentando nos ombros.
    Casca em superelipse e folga medida na cabeça lisa (h_bare): o elmo não pode virar um balão na cabeça."""
    P, R = g_rig("h_nasal")
    M = g_mats()
    head = R["Head"]
    plain_head(R, M, hair=False)
    st = gm("t1_nasal", "#A9B1BE", 0.42, 0.65)
    brass = gm("gw_nasal_brass", "#B8822F", 0.4, 0.7)
    chain = gm("gw_nasal_chain", "#6A707A", 0.7, 0.5)
    chd = gm("gw_nasal_chain_d", "#3E434B", 0.8, 0.4)
    C = Vector((0, 0.012, 1.715))
    TOP = 0.15

    def prof(z):
        """meia largura, profundidade da frente, profundidade de trás, expoente da superelipse."""
        if z >= C.z:
            d = min(1.0, (z - C.z) / TOP)
            k = max(0.0, 1 - d ** 1.7) ** 0.62                  # cúpula que termina em ponta, não bola
            return 0.104 * k, 0.128 * k, 0.12 * k, 2.4
        return 0.104, 0.128, 0.12, 2.6

    def hp(th, z, out=0.0):
        a, bf, bb, n = prof(z)
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / n), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / n), c) * (b + out)
        return Vector((x, C.y + y, z))

    parts = []
    NP = 48
    zs = [C.z - 0.012 + (TOP + 0.012) * (i / 16) ** 0.85 for i in range(17)]
    parts.append(g_smooth_mesh("NasalSkull", [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs], st,
                               head, cap_end=True, outward=True))
    # nervuras de latão: quatro arcos da faixa até o topo, nas diagonais
    for k, th in enumerate((math.pi / 4, 3 * math.pi / 4, -3 * math.pi / 4, -math.pi / 4)):
        rib = [hp(th, C.z + 0.02 + (TOP - 0.025) * (i / 10) ** 0.9, 0.003) for i in range(11)]
        parts.append(g_pipe("NasalRib%d" % k, rib, 0.0048, brass, head, sides=8))
    parts.append(g_cap("NasalFinial", C + Vector((0, 0, TOP - 0.006)), (0, 0, 1), (1, 0, 0), 0.013, 0.013, 0.016,
                       brass, head, sides=14))
    # faixa da testa: larga, com a borda de baixo descendo em ponta no meio (vira a nasal)
    def band_z(th, top):
        dip = 0.018 * max(0.0, math.cos(th)) ** 16
        return (C.z + 0.022 if top else C.z - 0.008 - dip)
    band = [[hp(2 * math.pi * j / NP, band_z(2 * math.pi * j / NP, False) * (1 - v) + band_z(0, True) * v,
                0.007 - 0.002 * v) for j in range(NP)] for v in (0.0, 0.33, 0.66, 1.0)]
    for r in band:
        r.append(r[0])
    parts.append(g_smooth_mesh("NasalBand", band, brass, head, cap_end=False, closed=False, thick=0.005,
                               outward=True))
    parts.append(g_pipe("NasalBandLip", band[0], 0.0035, brass, head, sides=8))
    for k in range(12):
        th = 2 * math.pi * (k + 0.5) / 12
        c = hp(th, C.z + 0.007, 0.01)
        nb = Vector((math.sin(th), -math.cos(th), 0))
        parts.append(g_cap("NasalRivet%d" % k, c, nb, (0, 0, 1), 0.0048, 0.0048, 0.003, st, head, sides=10))
    # nasal: lâmina que sai da ponta da faixa e desce rente ao nariz, alargando na ponta
    nas = []
    for i in range(9):
        u = i / 8
        z = C.z - 0.02 - 0.085 * u
        y = C.y - 0.128 - 0.004 - 0.011 * u ** 1.3
        w = 0.0062 - 0.0015 * math.sin(math.pi * u) + 0.004 * u ** 4
        nas.append([Vector((sx * w, y + 0.0045 * abs(sx) ** 1.5, z)) for sx in (-1, -0.5, 0, 0.5, 1)])
    parts.append(g_smooth_mesh("NasalGuard", nas, st, head, cap_end=False, closed=False, thick=0.005, outward=True))
    parts.append(g_pipe("NasalGuardEdgeL", [r[0] for r in nas], 0.0022, brass, head, sides=6))
    parts.append(g_pipe("NasalGuardEdgeR", [r[-1] for r in nas], 0.0022, brass, head, sides=6))
    # bochecheiras: placas arredondadas que pendem da faixa nos lados, na frente das orelhas
    for sn, sg in (("L", 1), ("R", -1)):
        def ck(u, v, sg=sg):
            t0, t1 = 0.95, 1.85                            # da frente (perto do olho) até atrás da orelha
            th = sg * (t0 + (t1 - t0) * v)
            depth = 0.112 * max(0.0, 1 - (2 * v - 1) ** 4) ** 0.5 + 0.012    # borda de baixo arredondada
            z = C.z - 0.004 - depth * u
            return hp(th, z, 0.005 + 0.012 * u)
        rows = [[ck(i / 6, j / 10) for j in range(11)] for i in range(7)]
        parts.append(g_smooth_mesh("NasalCheek" + sn, rows, st, head, cap_end=False, closed=False, thick=0.005,
                                   outward=True))
        border = [r[0] for r in rows] + rows[-1][1:-1] + [r[-1] for r in rows][::-1]
        parts.append(g_pipe("NasalCheekEdge" + sn, border, 0.0026, brass, head, sides=6, loop=True))
        c = hp(sg * 1.4, C.z - 0.03, 0.02)
        nb = Vector((math.sin(sg * 1.4), -math.cos(sg * 1.4), 0))
        parts.append(g_cap("NasalCheekRivet" + sn, c, nb, (0, 0, 1), 0.006, 0.006, 0.004, brass, head, sides=10))
    # cota de malha: lados e nuca da faixa até os ombros, e a gola que fecha sob o queixo

    def mail(th, z, out=0.0):
        """Ponto da malha: justa no pescoço, abrindo como uma pelerine curta sobre os ombros."""
        a0, bf0, bb0 = 0.102, 0.122, 0.118
        if z > 1.6:
            w = (z - 1.6) / (C.z - 1.6)
            a, bf, bb = 0.1 + 0.004 * w, 0.112 + 0.01 * w, 0.11 + 0.008 * w
        else:
            f = max(0.0, (1.6 - z) / 0.1) ** 1.6
            a, bf, bb = 0.1 + 0.05 * f, 0.112 + 0.022 * f, 0.11 + 0.03 * f
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / 2.6), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / 2.6), c) * (b + out)
        return Vector((x, C.y + y, z))
    ZB = 1.5
    mz = [C.z - 0.004 - (C.z - 0.004 - ZB) * i / 14 for i in range(15)]
    back = [[mail(0.82 + (2 * math.pi - 1.64) * j / 40, z) for j in range(41)] for z in mz]
    parts.append(g_smooth_mesh("NasalMail", back, chain, head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    tz = [1.556 - (1.556 - ZB) * i / 8 for i in range(9)]
    throat = [[mail(-0.95 + 1.9 * j / 20, z, 0.002) for j in range(21)] for z in tz]
    parts.append(g_smooth_mesh("NasalMailThroat", throat, chain, head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    for i, z in enumerate([1.665, 1.615, 1.565, 1.525]):     # fileiras de elos
        th0 = 0.82 if z > 1.556 else 0.0
        pts = [mail(th0 + (2 * math.pi - 2 * th0) * j / 48, z, 0.004) for j in range(49)]
        parts.append(g_pipe("NasalMailRow%d" % i, pts, 0.0022, chd, head, sides=6, loop=(th0 == 0.0)))
    parts.append(g_pipe("NasalMailHem", [mail(2 * math.pi * j / 48, ZB, 0.004) for j in range(48)], 0.0045, brass,
                        head, sides=8, loop=True))
    parts.append(g_pipe("NasalMailEdgeL", [mail(0.82, z, 0.004) for z in (C.z - 0.004, 1.66, 1.62, 1.585, 1.57)],
                        0.003, chd, head, sides=6))
    parts.append(g_pipe("NasalMailEdgeR", [mail(-0.82, z, 0.004) for z in (C.z - 0.004, 1.66, 1.62, 1.585, 1.57)],
                        0.003, chd, head, sides=6))
    g_head_done("h_nasal", "Nasal", parts, P, R)


def build_h_great():
    """Elmo fechado da guarda (armet): crânio baixo e justo com crista do nariz à nuca; faixa dourada saliente na
    testa fazendo sombra sobre a fenda dos olhos; viseira em bico com respiros; bochecheiras e guarda-nuca que
    abrem para baixo, com aro dourado; penacho vermelho saindo do alto da crista para trás.
    Seções em superelipse (lados quase retos), não elipsoide: o elmo não pode virar um balão na cabeça."""
    P, R = g_rig("h_great")
    head = R["Head"]
    st = gm("t1_great", "#9AA3B1", 0.42, 0.65)
    st_d = gm("t1d_great", "#5C6472", 0.5, 0.6)
    gold = gm("t2_great", "#D9A93E", 0.35, 0.8)
    slit = gm("gw_great_slit", "#141419", 0.95)
    plume = gm("gw_great_plume", "#A8282C", 0.9)
    C = Vector((0, 0.012, 1.69))
    TOP = 0.145
    # Folga medida sobre a cabeça lisa (h_bare): meia largura 0,093 e nuca a y 0,11 na altura dos olhos, topo
    # a 1,817. O elmo fica a ~0,015 dos lados, ~0,02 atrás e ~0,018 em cima; a frente guarda o espaço do bico.

    def prof(z):
        """meia largura, profundidade da frente, profundidade de trás e expoente da superelipse na altura z."""
        if z >= C.z:
            d = min(1.0, (z - C.z) / TOP)
            k = max(0.0, 1 - d ** 2.4) ** (1 / 2.4)             # topo achatado, quina arredondada
            return 0.108 * k, 0.133 * k - 0.016 * d ** 1.5, 0.118 * k + 0.004 * d ** 1.5, 2.3 + 0.5 * (1 - d)
        t = min(1.0, (C.z - z) / 0.2)
        fl = 0.03 * max(0.0, (1.575 - z) / 0.085) ** 1.6       # bochecheiras e nuca abrem para baixo
        u = min(1.0, (C.z - z) / 0.12)
        tuck = 0.04 * u * u * (3 - 2 * u)                       # de lado, a nuca desce em diagonal até o pescoço
        return (0.108 * (1 - 0.06 * t) + fl, 0.133 * (1 - 0.05 * t) + fl * 0.8 + 0.01 * t,
                0.118 - tuck + fl * 0.5, 2.8)

    def hp(th, z, out=0.0, beak=True):
        """Ponto da casca no ângulo th (0 = frente, + = esquerda do boneco) e altura z, afastado out."""
        a, bf, bb, n = prof(z)
        back = 0.0
        s, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s) ** (2 / n), s) * (a + out)
        y = -math.copysign(abs(c) ** (2 / n), c) * (b + out)
        face = max(0.0, c)
        keel = 0.01 * face ** 10 * (1.0 if z < 1.83 else max(0.0, (1.86 - z) / 0.03))
        bk = 0.0
        if beak:                                                # bico da viseira, mais saliente embaixo do nariz
            bk = 0.034 * face ** 6 * max(0.0, 1 - ((z - 1.6) / 0.06) ** 2)
        return Vector((x, C.y + back + y - keel - bk, z))

    def patch(name, th0, th1, z0, z1, out, mat, nt=40, nz=8, thick=0.005, beak=True, closed=False, cap=False):
        rows = [[hp(th0 + (th1 - th0) * j / (nt if closed else nt), z0 + (z1 - z0) * i / nz, out, beak)
                 for j in range(nt if closed else nt + 1)] for i in range(nz + 1)]
        return g_smooth_mesh(name, rows, mat, head, cap_end=cap, closed=closed, thick=thick, outward=True), rows

    parts = []
    # forro escuro atrás da fenda dos olhos (só aparece pela fenda)
    p, _ = patch("GreatLining", -1.25, 1.25, 1.635, 1.71, -0.004, slit, nz=4, thick=0.003)
    parts.append(p)
    # crânio: do alto da fenda até o topo, fechado
    NP = 48
    zs = [1.686 + (C.z + TOP - 1.686) * (i / 14) ** 0.8 for i in range(15)]
    skull = [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs]
    parts.append(g_smooth_mesh("GreatSkull", skull, st, head, cap_end=True, outward=True))
    # bochecheiras e nuca: dos lados e atrás, do aro até a testa (a frente fica para a viseira)
    p, low = patch("GreatCheeks", 0.95, 2 * math.pi - 0.95, 1.49, 1.7, 0.0, st, nt=40, nz=10, thick=0.006)
    parts.append(p)
    # viseira em bico, por cima das bochecheiras, da borda de baixo até a fenda
    p, vis = patch("GreatVisor", -1.22, 1.22, 1.495, 1.652, 0.006, st, nt=36, nz=10, thick=0.006)
    parts.append(p)
    # faixa da testa: saliente, a borda de baixo mais para fora, fazendo aba sobre a fenda
    brow = [[hp(-1.7 + 3.4 * j / 40, 1.686 + 0.03 * i / 3, 0.014 - 0.011 * i / 3) for j in range(41)] for i in range(4)]
    parts.append(g_smooth_mesh("GreatBrow", brow, gold, head, cap_end=False, closed=False, thick=0.006, outward=True))
    parts.append(g_pipe("GreatBrowLip", brow[0], 0.004, gold, head, sides=8))
    # aro dourado em toda a borda de baixo (viseira e bochecheiras)
    parts.append(g_pipe("GreatRimV", [hp(-1.22 + 2.44 * j / 36, 1.497, 0.012) for j in range(37)], 0.0055, gold, head))
    parts.append(g_pipe("GreatRimC", [hp(0.95 + (2 * math.pi - 1.9) * j / 40, 1.492, 0.007) for j in range(41)], 0.0055,
                        gold, head))
    # borda de cima da viseira, logo abaixo da fenda, e a quina do bico
    parts.append(g_pipe("GreatVisorEdge", [hp(-1.2 + 2.4 * j / 36, 1.651, 0.01) for j in range(37)], 0.0035, st_d, head))
    parts.append(g_pipe("GreatBeak", [hp(0.0, z, 0.009) for z in (1.505, 1.54, 1.575, 1.61, 1.635, 1.65)], 0.004,
                        st_d, head))
    # respiros: fendas curtas nos dois lados do bico
    for sn, sg in (("L", 1), ("R", -1)):
        for i in range(3):
            for k in range(2):
                th = sg * (0.42 + 0.14 * i)
                z = 1.6 - 0.028 * k
                q = hp(th, z, 0.009)
                nrm = Vector((math.sin(th), -math.cos(th), 0))
                tu = Vector((math.cos(th), math.sin(th), 0))
                parts.append(g_plate("GreatBreath%s%d%d" % (sn, i, k), [(-0.004, -0.0025), (0.004, -0.0025),
                                                                        (0.004, 0.0025), (-0.004, 0.0025)],
                                     q, tu, (0, 0, 1), 0.008, slit, head))
        # pino da viseira: rebite dourado onde a viseira gira, na têmpora
        c = hp(sg * 1.2, 1.645, 0.012)
        nb = Vector((math.sin(sg * 1.2), -math.cos(sg * 1.2), 0))
        parts.append(g_cap("GreatPivot" + sn, c, nb, (0, 0, 1), 0.012, 0.012, 0.006, gold, head, sides=14))
    # crista: lâmina no plano do meio, da testa até a nuca, com fio dourado por cima
    crest, ridge = [], []
    for i in range(25):
        b = 0.25 + (math.pi * 0.98 - 0.25) * i / 24        # ângulo na vista de lado: 0 frente, pi/2 topo
        z = C.z + TOP * math.sin(b) * 0.995
        yb = hp(0.0 if b < math.pi / 2 else math.pi, z).y
        nrm = Vector((0, -math.cos(b), math.sin(b)))
        hgt = 0.006 + 0.028 * math.sin(math.pi * min(1.0, i / 22)) ** 0.6
        base = Vector((0, yb, z)) - nrm * 0.004
        crest.append([base + Vector((-0.007, 0, 0)), base + nrm * hgt, base + Vector((0.007, 0, 0))])
        ridge.append(base + nrm * (hgt + 0.002))
    parts.append(g_smooth_mesh("GreatCrest", crest, st, head, cap_end=False, closed=False, thick=0.004, outward=True))
    parts.append(g_pipe("GreatCrestGold", ridge[1:-1], 0.0045, gold, head, sides=8))
    # rebites dourados na faixa da testa
    for k, th in enumerate((-1.45, -0.95, -0.5, 0.5, 0.95, 1.45)):
        c = hp(th, 1.7, 0.018)
        nb = Vector((math.sin(th), -math.cos(th), 0))
        parts.append(g_cap("GreatRivet%d" % k, c, nb, (0, 0, 1), 0.0055, 0.0055, 0.0035, gold, head, sides=10))
    # penacho: tufo de crina vermelha saindo do alto da crista, caindo para trás
    i0 = 15
    root = ridge[i0] - Vector((0, 0, 0.004))
    parts.append(g_cap("GreatPlumeSeat", root, Vector((0, 0.35, 1)), (1, 0, 0), 0.016, 0.02, 0.012, gold, head,
                       sides=14))
    # mechas grossas e juntas: de longe leem como um tufo só, não como fios soltos
    for q, (dx, ln, lift) in enumerate(((0.0, 1.0, 1.0), (0.009, 0.93, 0.85), (-0.009, 0.93, 0.85),
                                       (0.016, 0.82, 0.6), (-0.016, 0.82, 0.6), (0.005, 0.8, 1.25),
                                       (-0.005, 0.8, 1.25), (0.0, 0.66, 1.45), (0.021, 0.7, 0.35), (-0.021, 0.7, 0.35))):
        b0 = root + Vector((dx * 0.4, 0, 0.004))
        parts.append(g_cone("GreatPlume%d" % q, [b0, b0 + Vector((dx, 0.04 * ln, 0.06 * lift)),
                                                  b0 + Vector((dx * 2.0, 0.13 * ln, 0.05 * lift)),
                                                  b0 + Vector((dx * 2.6, 0.2 * ln, -0.03 * lift))],
                            0.019, plume, head, sides=10, n=14, r1=0.003, pw=2.2))
    g_head_done("h_great", "Great", parts, P, R)


def build_h_celestial():
    """Elmo Astral (cavaleiro celeste), na receita do armet aprovada para os elmos de guerreiro: crânio baixo e
    justo de lados quase retos e topo achatado, crista do nariz à nuca; aba saliente em ouro claro sobre a fenda
    escura dos olhos, com um sol pequeno no meio; viseira em bico com quina e respiros; bochecheiras e nuca
    abrindo um pouco embaixo até o aro; nuca descendo em diagonal até o pescoço. Silhueta do conjunto: a coroa
    de raios de sol em leque atrás do alto da cabeça, com o buraco negro no centro (o mostrador do peito e o
    broche da capa), e a crina azul da capa correndo pela crista."""
    P, R = g_rig("h_celestial")
    head = R["Head"]
    plain_head(R, g_mats(), hair=False)    # olhos e bochechas aparecem pelas aberturas dos lados
    K = celestial_mats()
    st, st_d, trim = K["plate"], K["plate_d"], K["dial"]
    slit = gm("cs_helm_slit", "#120C06", 0.95)
    plume = gm("cs_plume", "#2E3D96", 0.9)
    plume_d = gm("cs_plume_d", "#1C2766", 0.9)
    C = Vector((0, 0.012, 1.69))
    TOP = 0.145

    def prof(z):
        if z >= C.z:
            d = min(1.0, (z - C.z) / TOP)
            k = max(0.0, 1 - d ** 2.4) ** (1 / 2.4)
            return 0.108 * k, 0.133 * k - 0.016 * d ** 1.5, 0.118 * k + 0.004 * d ** 1.5, 2.3 + 0.5 * (1 - d)
        t = min(1.0, (C.z - z) / 0.2)
        fl = 0.03 * max(0.0, (1.575 - z) / 0.085) ** 1.6
        u = min(1.0, (C.z - z) / 0.12)
        tuck = 0.04 * u * u * (3 - 2 * u)
        return (0.108 * (1 - 0.06 * t) + fl, 0.133 * (1 - 0.05 * t) + fl * 0.8 + 0.01 * t,
                0.118 - tuck + fl * 0.5, 2.8)

    def hp(th, z, out=0.0, beak=True):
        a, bf, bb, n = prof(z)
        s_, c = math.sin(th), math.cos(th)
        b = bf if c > 0 else bb
        x = math.copysign(abs(s_) ** (2 / n), s_) * (a + out)
        y = -math.copysign(abs(c) ** (2 / n), c) * (b + out)
        face = max(0.0, c)
        keel = 0.01 * face ** 10 * (1.0 if z < 1.83 else max(0.0, (1.86 - z) / 0.03))
        bk = 0.034 * face ** 6 * max(0.0, 1 - ((z - 1.6) / 0.06) ** 2) if beak else 0.0
        return Vector((x, C.y + y - keel - bk, z))

    def patch(name, th0, th1, z0, z1, out, mat, nt=40, nz=8, thick=0.005):
        rows = [[hp(th0 + (th1 - th0) * j / nt, z0 + (z1 - z0) * i / nz, out) for j in range(nt + 1)]
                for i in range(nz + 1)]
        return g_smooth_mesh(name, rows, mat, head, cap_end=False, closed=False, thick=thick, outward=True), rows

    parts = []
    # frente: o meio coberto por uma placa vertical da testa ao queixo; dos lados, entre ela e as bochecheiras,
    #      duas aberturas mostram olhos e bochechas (o T do capacete de Star Wars ao contrário)
    TH0, TH1 = 0.17, 0.95
    NP = 48
    zs = [1.686 + (C.z + TOP - 1.686) * (i / 14) ** 0.8 for i in range(15)]
    parts.append(g_smooth_mesh("CsHelmSkull", [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs], st, head,
                               cap_end=True, outward=True))
    p, _ = patch("CsHelmCheeks", 0.95, 2 * math.pi - 0.95, 1.49, 1.7, 0.0, st, nt=40, nz=10, thick=0.006)
    parts.append(p)
    rows = [[hp(-TH0 + 2 * TH0 * j / 12, 1.495 + 0.195 * i / 12, 0.014, beak=False) for j in range(13)] for i in range(13)]
    parts.append(g_smooth_mesh("CsHelmVisor", rows, st, head, cap_end=False, closed=False, thick=0.006, outward=True))
    for sg, col in ((1, -1), (-1, 0)):
        parts.append(g_pipe("CsHelmVisorSide%d" % (sg > 0), [r[col] for r in rows], 0.0042, trim, head, sides=8))
        parts.append(g_pipe("CsHelmCheekEdge%d" % (sg > 0), [hp(sg * TH1, 1.49 + 0.2 * i / 10, 0.002, beak=False)
                                                            for i in range(11)], 0.0042, trim, head, sides=8))
    parts.append(g_pipe("CsHelmRimV", rows[0], 0.0055, trim, head, sides=8))
    parts.append(g_pipe("CsHelmBeak", [hp(0.0, z, 0.017, beak=False) for z in (1.505, 1.54, 1.575, 1.61, 1.645, 1.675)], 0.004,
                        st_d, head, sides=6))
    # aba da testa em ouro claro, a borda de baixo mais para fora (sombra sobre a fenda)
    brow = [[hp(-1.7 + 3.4 * j / 40, 1.686 + 0.03 * i / 3, 0.014 - 0.011 * i / 3) for j in range(41)] for i in range(4)]
    parts.append(g_smooth_mesh("CsHelmBrow", brow, trim, head, cap_end=False, closed=False, thick=0.006, outward=True))
    parts.append(g_pipe("CsHelmBrowLip", brow[0], 0.004, trim, head, sides=8))
    parts.append(g_pipe("CsHelmRimC", [hp(TH1 + (2 * math.pi - 2 * TH1) * j / 40, 1.492, 0.007) for j in range(41)], 0.0055,
                        trim, head))
    for sn, sg in (("L", 1), ("R", -1)):
        for i in range(3):             # respiros na placa do meio, dos dois lados da quina
            th = sg * 0.09
            z = 1.53 + 0.022 * i
            q = hp(th, z, 0.0175, beak=False)
            tu = Vector((math.cos(th), math.sin(th), 0))
            parts.append(g_plate("CsHelmBreath%s%d" % (sn, i), [(-0.004, -0.0022), (0.004, -0.0022),
                                                                (0.004, 0.0022), (-0.004, 0.0022)],
                                 q, tu, (0, 0, 1), 0.008, slit, head))
        c = hp(sg * 1.2, 1.645, 0.012)
        nb = Vector((math.sin(sg * 1.2), -math.cos(sg * 1.2), 0))
        parts.append(g_cap("CsHelmPivot" + sn, c, nb, (0, 0, 1), 0.012, 0.012, 0.006, trim, head, sides=14))
    # crista do nariz à nuca, com fio claro
    crest, ridge = [], []
    for i in range(25):
        b_ = 0.25 + (math.pi * 0.98 - 0.25) * i / 24
        z = C.z + TOP * math.sin(b_) * 0.995
        yb = hp(0.0 if b_ < math.pi / 2 else math.pi, z).y
        nrm = Vector((0, -math.cos(b_), math.sin(b_)))
        hgt = 0.006 + 0.022 * math.sin(math.pi * min(1.0, i / 22)) ** 0.6
        base = Vector((0, yb, z)) - nrm * 0.004
        crest.append([base + Vector((-0.007, 0, 0)), base + nrm * hgt, base + Vector((0.007, 0, 0))])
        ridge.append(base + nrm * (hgt + 0.002))
    parts.append(g_smooth_mesh("CsHelmCrest", crest, st, head, cap_end=False, closed=False, thick=0.004, outward=True))
    parts.append(g_pipe("CsHelmCrestGold", ridge[1:-1], 0.0045, trim, head, sides=8))
    # sol na aba da testa: disco com raios em volta de um buraco negro (o mostrador do peito em miniatura)
    sc = hp(0.0, 1.703, 0.017)
    fw = Vector((0, -1, 0))
    e1, e2 = Vector((1, 0, 0)), Vector((0, 0, 1))
    parts.append(g_cap("CsHelmSunDisc", sc, fw, (0, 0, 1), 0.016, 0.016, 0.005, trim, head, sides=20))
    parts.append(g_cap("CsHelmSunHole", sc + fw * 0.004, fw, (0, 0, 1), 0.0075, 0.0075, 0.003, K["void"], head,
                       sides=16))
    for k in range(10):
        t = 2 * math.pi * k / 10 + math.pi / 2
        dv = e1 * math.cos(t) + e2 * math.sin(t)
        L = 0.03 if k % 2 == 0 else 0.024
        parts.append(g_pipe("CsHelmSunRay%d" % k, [sc + dv * 0.017 + fw * 0.002, sc + dv * L - fw * 0.002], 0.0022,
                            trim, head, sides=6))
    # coroa de raios de sol atrás do alto da cabeça: aro com buraco negro no centro (o mostrador do peito) e
    #      raios em leque num meio-disco inclinado para trás, alternando longos e curtos
    hc = Vector((0, hp(math.pi, 1.79).y + 0.004, 1.815))
    nrm = Vector((0, 1, 0.55)).normalized()            # o disco olha para trás e um pouco para cima
    ex = Vector((1, 0, 0))
    ey = nrm.cross(ex).normalized()                    # "para cima" no plano do disco
    if ey.z < 0:
        ey = -ey
    ring = [hc + (ex * math.cos(t) + ey * math.sin(t)) * 0.05 for t in (2 * math.pi * m / 28 for m in range(28))]
    parts.append(g_smooth_mesh("CsHaloDisc", [[hc] * 28, [hc + (q - hc) * 0.98 for q in ring]], trim, head,
                               cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("CsHaloRing", ring, 0.006, st, head, sides=8, loop=True))
    parts.append(g_cap("CsHaloHole", hc - nrm * 0.0035 * -1, nrm, ex, 0.024, 0.024, 0.004, K["void"], head, sides=18))
    parts.append(g_pipe("CsHaloHoleRim", [hc + nrm * 0.004 + (ex * math.cos(t) + ey * math.sin(t)) * 0.025
                                         for t in (2 * math.pi * m / 20 for m in range(20))], 0.0028, st_d, head,
                        sides=6, loop=True))
    for k in range(13):                # leque de -100° a +100° a partir do alto
        t = math.radians(-100 + 200 * k / 12) + math.pi / 2
        dv = ex * math.cos(t) + ey * math.sin(t)
        side = nrm.cross(dv).normalized()
        L = 0.15 if k % 2 == 0 else 0.095
        L *= 1.0 - 0.3 * abs(k - 6) / 6
        base = hc + dv * 0.052
        tip = hc + dv * (0.052 + L)
        w = 0.014 if k % 2 == 0 else 0.01
        parts.append(g_plate("CsHaloRay%d" % k, [(-w, 0.0), (w, 0.0), (0.0015, L), (-0.0015, L)], base, side, dv,
                             0.005, trim, head))
        parts.append(g_pipe("CsHaloRayRib%d" % k, [base + nrm * 0.003 + dv * 0.004, tip + nrm * 0.003 - dv * 0.012],
                            0.0018, st_d, head, sides=6))
    # crista de crina azul ao longo da crista, da testa até a nuca, mais alta no alto e caindo para trás
    for i in range(3, 14):             # a crina para antes da coroa de sol
        t = i / 24
        b0 = ridge[i]
        up = (b0 - Vector((0, C.y, C.z))).normalized()
        hgt = 0.014 + 0.028 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.8
        back = Vector((0, 1, 0)) * (0.025 + 0.04 * t)
        for k, dx in enumerate((-0.003, 0.003)):
            q0 = b0 + Vector((dx, 0, 0))
            parts.append(g_cone("CsHelmMane%d%d" % (i, k), [q0, q0 + up * hgt * 0.6 + back * 0.4,
                                                            q0 + up * hgt + back],
                                0.0125, plume if (i + k) % 3 else plume_d, head, sides=8, n=8, r1=0.003, pw=1.3))
    g_head_done("h_celestial", "CelestialHelm", parts, P, R)


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
        k = max(0, min(T, int(round(u * o.get("mantle_cut", 1.0) * T))))      # mantle_cut < 1: murça mais curta
        rx, ry, z = prof[0][k], prof[1][k], prof[2][k]
        c2 = math.cos(2 * a)
        wing, vee = max(0.0, -c2) ** 2, max(0.0, c2) ** 2
        z -= 0.055 * u * math.cos(a) ** 2 + o.get("vee", 0.11) * vee * u ** 3 + drop * u
        z += 0.03 * wing * u ** 4
        z -= o.get("tatter", 0.0) * u ** 3 * abs(math.sin(o.get("tatter_n", 9) * a))      # barra em farrapos
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

    N, rows = o.get("mantle_n", 48), 14
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
    if o.get("brooch", True):
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

    if o.get("mantle_extra"):          # enfeites próprios do conjunto (ver mx_* adiante)
        o["mantle_extra"](dict(M=M, normal=normal, frame=frame, motif=motif, soft=soft, orn=orn, body=body, A=A))

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
                    mat_fn=lambda f: 1 if (o.get("plastron", True) and abs(f.calc_center_median().x) < 0.05 and f.calc_center_median().y < 0
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
    for sn, s in ((("L", 1), ("R", -1)) if o.get("plastron", True) else ()):
        parts.append(g_pipe("Plastron" + sn, [hit_x(s * 0.052, 1.36 - 0.03 * i, 0.003) for i in range(10)], 0.0045,
                            gold, body))
    for k, z in enumerate((1.3, 1.24, 1.18, 1.125) if o.get("plastron", True) else ()):
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
    if o.get("buckle", True):
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
    if o.get("torso_extra"):          # peças próprias do conjunto (ver tx_* adiante)
        o["torso_extra"](dict(hit_a=hit_a, hit_x=hit_x, below=below, rad=rad, parts=parts, tails=tails, body=body, A=A,
                              bc=bc))
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
    S, n = o.get("bell_sides", 28), 16
    for sn, s in (("L", 1), ("R", -1)):
        elbow = R["Elbow" + sn]
        sh, el, wr = (cb_mirror(CB_J[k], s) for k in ("shoulder", "elbow", "wrist"))
        d = (wr - el).normalized()
        out = Vector((s, 0, 0))
        ctrl = [sh.lerp(el, 0.5), el + out * 0.004, el.lerp(wr, 0.45) + out * 0.01, el.lerp(wr, 0.78) + out * 0.02,
                wr + d * o.get("bell_len", -0.02) + out * 0.026]
        path = g_spline(ctrl, n)
        rx = g_spline(list(o.get("bell_rx", (0.073, 0.08, 0.08 + 0.007 * bl, 0.08 + 0.01 * bl, 0.08 + 0.01 * bl))), n)       # para os lados
        ry = g_spline(list(o.get("bell_ry", (0.075, 0.084, 0.084 + 0.014 * bl, 0.084 + 0.03 * bl, 0.084 + 0.036 * bl))), n)     # para a frente e para trás
        rings = g_curved_tube(path, list(zip(rx, ry)), sides=S, side0=(1, 0, 0))
        for i, ring in enumerate(rings):                         # boca em diagonal: atrás cai mais, em ponta
            k = max(0.0, (i / n - 0.4) / 0.6) ** 2
            for j in range(S):
                a = 2 * math.pi * j / S
                back = ((1 - math.cos(a)) / 2)
                ring[j] = ring[j] + d * (o.get("droop", 0.15) * k * back ** 2.2 - 0.045 * k * (1 - back))
                if i >= n - 1:          # boca em farrapos
                    ring[j] = ring[j] - d * (o.get("bell_tatter", 0.0) * (1.0 if i == n else 0.45)
                                             * abs(math.sin(o.get("bell_tatter_n", 7) * a)))
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
        if o.get("sleeve_extra"):          # enfeites próprios do conjunto (ver sx_* adiante)
            o["sleeve_extra"](dict(sn=sn, s=s, rings=rings, cen=cen, n=n, S=S, d=d, el=el, wr=wr, parts=parts,
                                   elbow=elbow, A=A))
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
    NC = o.get("coat_n", 64)
    H = NC // 2

    def hem(a):
        return (o.get("coat_hem", 0.2) - o.get("hem_depth", 0.07) * max(0.0, math.cos(o.get("hem_pts", 3) * (a - math.pi))) ** 2
                - 0.07 * ((1 - math.cos(a)) / 2) ** 2
                + o.get("coat_tatter", 0.0) * abs(math.sin(o.get("coat_tatter_n", 9) * a)))      # barra em farrapos

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
        if not o.get("back_seam", True):       # sem debrum na fenda de trás (as costas ficam lisas: galáxia do Ceifador)
            edge = edge[:rows + H + 1] if half == 0 else edge[rows:]
        soft.append(g_pipe("CoatPiping%d" % half, edge, 0.0075, gold, body))
        soft.append(g_pipe("CoatThread%d" % half, [q + Vector((q.x, q.y, 0)).normalized() * 0.003
                                                   for q in out_h[rows - 2]], 0.0034, gold, body, sides=6))
        outer = out_h if half == 0 else [a + b[1:] for a, b in zip(outer, out_h)]

    def motif(name, outline, q, q_up, size, thick=0.005):
        nr = Vector((q.x, q.y, 0)).normalized()
        up = (q_up - q).normalized()
        return g_plate(name, [(x * size, y * size) for x, y in outline], q + nr * 0.004, up.cross(nr), up, thick, mot,
                       body)
    for j in (range(3 * NC // 64, NC - 2, 3 * NC // 64) if o.get("coat_diamonds", True) else ()):
        orn.append(motif("CoatDiamond%d" % j, g_shape(o, j, G_DIAMOND), (outer[rows - 1][j] + outer[rows][j]) / 2, outer[rows - 1][j],
                         0.013))
    for k, (j, i) in enumerate(((7, 8), (16, 6), (25, 9), (32, 5), (39, 9), (48, 6), (57, 8)) if o.get("coat_stars", True) else ()):
        j = j * NC // 64
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
    if o.get("skirt_extra"):          # peças próprias do conjunto (ver kx_* adiante)
        o["skirt_extra"](dict(outer=outer, rows=rows, NC=NC, H=H, soft=soft, orn=orn, body=body, A=A))
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
    g_galaxy_uv(style)
    g_export_skinned(style)          # no corpo feminino/anão deforma antes e exporta _f/_d (não sobrescreve o masculino)


def build_a_archmage():
    build_robe("a_archmage", archmage_mats())


# ------------------------------------------------------------------ Gibão acolchoado (tier I, malha lisa)
# Referência: "Light leather armor", Graeme Hughes (artstation.com/artwork/xNDv4). Mesmo princípio do manto:
# o pano sai da malha do corpo (cb_piece) e dobra com ele; enfeites rígidos ficam no osso Body.
def gambeson_mats():
    return dict(
        cloth=gm("gb_cloth", "#77736B", 0.95), cloth_d=gm("gb_cloth_d", "#5A5751", 0.95),
        quilt=gm("gb_quilt", "#504F53", 0.9), seam=gm("gb_seam", "#3B3A3F", 0.9),
        lea=gm("gb_leather", "#2F2D33", 0.8), band=gm("gb_band", "#A88B4C", 0.95),
        band_d=gm("gb_band_d", "#7A6334", 0.95), cord=gm("gb_cord", "#6E6A66", 0.9),
        metal=gm("gb_metal", "#A8AEB4", 0.45, 0.6),
    )


def _g_ray_tools(ob):
    """Funções que acham a superfície de ob por raios horizontais (ver archmage_torso)."""
    from mathutils.bvhtree import BVHTree
    me = ob.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    def rad(a):
        return Vector((math.sin(a), -math.cos(a), 0))

    def hit_a(a, z, out=0.0, strict=False):
        r = rad(a)
        loc = bvh.ray_cast(Vector((0, 0, z)) + r * 0.8, -r)[0]
        if loc is None:
            if strict:
                return None
            loc = Vector((0, 0, z)) + r * 0.13
        return loc + r * out
    return rad, hit_a


def g_loose_world(asset, tol=0.002):
    """Como loose_parts (armory.py), mas em coordenadas do mundo: as cascas tiradas do corpo ficam no espaço do
    esqueleto e as peças g_* no do pivô, então comparar vértices locais acusa peças que encostam."""
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update()
    objs = [o for o in scn.objects if o.type == 'MESH' and o.name != "BodySrc"]
    pts = {o.name: [o.matrix_world @ v.co for v in o.data.vertices] for o in objs}
    trees = {o.name: BVHTree.FromPolygons(pts[o.name], [tuple(p.vertices) for p in o.data.polygons]) for o in objs}
    group = {o.name: i for i, o in enumerate(objs)}

    def touch(a, b):
        if trees[a].overlap(trees[b]):
            return True
        return any(trees[b].find_nearest(p, tol)[0] is not None for p in pts[a]) or \
            any(trees[a].find_nearest(p, tol)[0] is not None for p in pts[b])
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            if group[a.name] != group[b.name] and touch(a.name, b.name):
                old, new = group[b.name], group[a.name]
                for k in group:
                    if group[k] == old:
                        group[k] = new
    comps = {}
    for k, g in group.items():
        comps.setdefault(g, []).append(k)
    comps = sorted(comps.values(), key=len, reverse=True)
    print(("LOOSE %s: %s" % (asset, " | ".join(", ".join(sorted(c)) for c in comps[1:]))) if len(comps) > 1
          else "CONNECTED %s" % asset, flush=True)


def g_border_pipes(ob, name, r, material, parent, smooth=4, step=0.012):
    """Debrum nas bordas abertas de uma casca: acha cada laço de arestas de borda, alisa o contorno (a casca
    tirada do corpo tem borda em degraus, face a face) e passa um cordão por ele."""
    me = ob.data
    nb = {}
    count = {}
    for p in me.polygons:
        for k in p.edge_keys:
            count[k] = count.get(k, 0) + 1
    for (a, b), c in count.items():
        if c == 1:
            nb.setdefault(a, []).append(b)
            nb.setdefault(b, []).append(a)
    seen, out = set(), []
    for start in list(nb):
        if start in seen:
            continue
        loop, prev, cur = [start], None, start
        seen.add(start)
        while True:
            nxt = [v for v in nb[cur] if v != prev and v not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        if len(loop) < 6:
            continue
        pts = [me.vertices[i].co.copy() for i in loop]
        for _ in range(smooth):                 # alisa sem encolher demais (média com os vizinhos)
            pts = [(pts[i - 1] + pts[i] * 2 + pts[(i + 1) % len(pts)]) / 4 for i in range(len(pts))]
        res, acc = [pts[0]], 0.0                # reamostra em passos regulares
        for i in range(1, len(pts)):
            acc += (pts[i] - pts[i - 1]).length
            if acc >= step:
                res.append(pts[i])
                acc = 0.0
        if len(res) >= 4:
            out.append(g_pipe("%s%d" % (name, len(out)), res, r, material, parent, sides=8, loop=True))
    return out


def _g_quilt(ob, fn, depth):
    """Estofa a casca: cada vértice sai pela normal depth * fn(posição) (0 = costura, 1 = gomo cheio)."""
    me = ob.data
    nr = [v.normal.copy() for v in me.vertices]
    for v, n in zip(me.vertices, nr):
        v.co += n * depth * fn(v.co)


def _g_shoulder_dome(src, s, lames, phis=28, rows=8, pull=0.55, cap=None, taper=False):
    """Grades curvas em volta do ombro do lado s: direção (θ, φ) a partir da articulação, θ = 0 subindo pelo eixo
    do braço (topo do ombro), φ = 0 para fora. O raio vem do corpo (raio de fora para dentro), alisado por cima
    (envelope) e puxado para o máximo da fileira, o que arredonda a quina do ombro.
    lames = [(θa, θb, φmax, folga, aba)] -> [(anéis, direções, centro)] por lâmina."""
    from mathutils.bvhtree import BVHTree
    mw = src.matrix_world
    bvh = BVHTree.FromPolygons([mw @ v.co for v in src.data.vertices], [tuple(p.vertices) for p in src.data.polygons])
    sh, el = cb_mirror(CB_J["shoulder"], s), cb_mirror(CB_J["elbow"], s)
    ax = (el - sh).normalized()
    o = Vector((s, 0, 0))
    o = (o - ax * o.dot(ax)).normalized()
    f = ax.cross(o).normalized()
    C = sh + o * -0.012

    HL = 0.075                         # passado de θ = π/2 vira cilindro: desce HL metros por radiano no braço

    def base(t):
        return C + ax * max(0.0, t - math.pi / 2) * HL

    def dirv(t, ph):
        t = min(t, math.pi / 2)
        return -ax * math.cos(t) + (o * math.cos(ph) + f * math.sin(ph)) * math.sin(t)

    def body_r(t, ph):
        d = dirv(t, ph)
        h = bvh.ray_cast(base(t) + d * 0.45, -d)
        return 0.45 - h[3] if h[0] is not None else 0.06
    out = []
    for ta, tb, pm, off, flare in lames:
        grid = []
        for i in range(rows + 1):
            row = []
            for j in range(phis + 1):
                u = -1 + 2 * j / phis
                ph = u * pm
                tbe = ta + (tb - ta) * (1 - abs(u) ** 4) ** 0.35        # pontas arredondadas
                t = ta + (tbe - ta) * i / rows
                row.append((t, ph, i / rows))
            grid.append(row)
        R = [[body_r(t, ph) for t, ph, _ in row] for row in grid]
        if cap is not None:            # raio batendo no pescoço/trapézio não estica a copa: nem acima da mediana
            for i in range(rows + 1):  # da fileira, nem (de baixo para cima) acima da fileira de baixo
                med = sorted(R[i])[len(R[i]) // 2]
                R[i] = [min(r, med + cap) for r in R[i]]
            for i in range(rows - 1, -1, -1):
                R[i] = [min(r, rb + cap) for r, rb in zip(R[i], R[i + 1])]
        for _ in range(6):             # envelope alisado: nunca entra no corpo, perde os degraus
            S = [[(R[i][max(j - 1, 0)] + 2 * R[i][j] + R[i][min(j + 1, phis)] +
                   R[max(i - 1, 0)][j] + R[min(i + 1, rows)][j]) / 6 for j in range(phis + 1)] for i in range(rows + 1)]
            R = [[max(R[i][j], S[i][j]) for j in range(phis + 1)] for i in range(rows + 1)]
        for i in range(rows + 1):      # puxa cada fileira para o seu máximo: arco redondo de frente
            m = max(R[i])
            if taper:                  # nas pontas arredondadas (t volta para o topo) não puxa: senão a ponta
                tm = max(t for t, _, _ in grid[i])     # da barra sobe acima da copa e vira uma aleta
                R[i] = [r + (m - r) * pull * ((t - ta) / max(1e-6, tm - ta)) for r, (t, _, _) in zip(R[i], grid[i])]
            else:
                R[i] = [r + (m - r) * pull for r in R[i]]
        rings = [[base(t) + dirv(t, ph) * (R[i][j] + off + flare * w ** 2.5) for j, (t, ph, w) in enumerate(row)]
                 for i, row in enumerate(grid)]
        out.append((rings, [[dirv(t, ph) for t, ph, _ in row] for row in grid], C))
    return out


def gambeson_pauldron(G, src, body, s, hit_y):
    """Ombreira do gibão: copa acolchoada e três lâminas que descem pelo braço, cada uma por cima da de baixo,
    com debrum de couro, costura no meio, rebites na barra, emblema de couro e metal na copa e alça diagonal."""
    sn = "L" if s > 0 else "R"
    lames = [(0.05, 1.3, 1.6, 0.034, 0.008), (1.15, 2.05, 1.85, 0.03, 0.012),
             (1.9, 2.75, 1.9, 0.026, 0.012), (2.6, 3.45, 1.9, 0.022, 0.012)]
    parts = []
    for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, s, lames)):
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), rings, G["quilt"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        n = len(rings[0])
        low = [rings[-1][j] + dirs[-1][j] * 0.003 for j in range(n)]
        parts.append(g_pipe("PauldronHem%s%d" % (sn, k), low, 0.0055, G["lea"], body, sides=8))
        mid = len(rings) // 2
        parts.append(g_pipe("PauldronSeam%s%d" % (sn, k), [rings[mid][j] + dirs[mid][j] * 0.001 for j in range(2, n - 2)],
                            0.0018, G["seam"], body, sides=6))
        for side in (0, n - 1):        # debrum nas pontas da lâmina
            parts.append(g_pipe("PauldronEnd%s%d_%d" % (sn, k, side), [r[side] + d[side] * 0.003 for r, d in
                                                                        zip(rings, dirs)], 0.005, G["lea"], body,
                                sides=8))
        if k > 0:
            for j in range(3, n - 2, 4):
                q = rings[-2][j] + dirs[-2][j] * 0.004
                parts.append(g_bead("PauldronRivet%s%d_%d" % (sn, k, j), q, 0.0055, G["metal"], body))
        else:                           # emblema da copa: placa de couro em losango, aro e botão de metal
            i0, j0 = len(rings) // 2, n // 2
            q, dn = rings[i0][j0], dirs[i0][j0]
            up = (rings[i0 - 2][j0] - rings[i0 + 2][j0]).normalized()
            side = up.cross(dn).normalized()
            up = dn.cross(side).normalized()
            parts.append(g_plate("PauldronBadge" + sn, [(x * 0.034, y * 0.05) for x, y in G_DIAMOND],
                                 q + dn * 0.004, side, up, 0.006, G["lea"], body))
            parts.append(g_pipe("PauldronBadgeRim" + sn, [q + dn * 0.009 + side * x * 0.026 + up * y * 0.04
                                                          for x, y in G_DIAMOND], 0.0028, G["metal"], body, sides=6,
                                loop=True))
            parts.append(g_bead("PauldronBoss" + sn, q + dn * 0.009, 0.011, G["metal"], body))
            for m, (x, y) in enumerate(G_DIAMOND):
                parts.append(g_bead("PauldronBadgeRivet%s%d" % (sn, m),
                                    q + dn * 0.008 + side * x * 0.034 * 0.7 + up * y * 0.05 * 0.7, 0.004,
                                    G["metal"], body))
    # alça diagonal: da frente e de trás da ombreira até debaixo do braço oposto, fivela no peito
    for nm, a0, a1 in (("Front", 0.95, -1.35), ("Back", math.pi - 0.95, 2 * math.pi - 1.35)):
        a0, a1 = a0 * s, a1 * s
        path = [hit_y(a0 + (a1 - a0) * i / 10, 1.41 - 0.14 * i / 10, 0.011) for i in range(11)]
        parts.append(g_smooth_mesh("Strap%s%s" % (sn, nm), g_curved_tube(path, [(0.016, 0.003)] * 11, sides=10,
                                                                         side0=(0, 0, 1)), G["lea"], body))
        if nm == "Front":
            bc = path[4]
            nn = Vector((bc.x, bc.y, 0)).normalized()
            t = (path[5] - path[3]).normalized()
            w = nn.cross(t).normalized()
            rim = [bc + nn * 0.005 + t * x + w * y for x, y in ((-0.016, 0.02), (0.016, 0.02), (0.018, 0),
                                                                 (0.016, -0.02), (-0.016, -0.02), (-0.018, 0))]
            parts.append(g_pipe("StrapBuckle" + sn, rim, 0.0035, G["metal"], body, sides=6, loop=True))
            parts.append(g_pipe("StrapPin" + sn, [bc + nn * 0.006 - t * 0.016, bc + nn * 0.007 + t * 0.016], 0.0022,
                                G["metal"], body, sides=6))
    return parts


def gambeson_cap(G, src, body, s):
    """Capa redonda do outro ombro: cúpula de gomos verticais, costuras entre os gomos e debrum na barra."""
    sn = "L" if s > 0 else "R"
    (rings, dirs, C), = _g_shoulder_dome(src, s, [(0.3, 2.7, 1.9, 0.028, 0.004)], phis=36, rows=12,
                                          pull=0.2)
    n = len(rings[0])
    NR = 6
    for i, row in enumerate(rings):    # gomos: estofa entre as costuras ao longo de φ
        for j in range(n):
            u = j / (n - 1)
            row[j] = row[j] + dirs[i][j] * 0.007 * abs(math.sin(math.pi * u * NR)) ** 0.5
    parts = [g_smooth_mesh("Cap" + sn, rings, G["quilt"], body, cap_end=False, closed=False, thick=0.006,
                           outward=True)]
    for k in range(1, NR):
        j = round(k * (n - 1) / NR)
        parts.append(g_pipe("CapSeam%s%d" % (sn, k), [r[j] + d[j] * 0.001 for r, d in zip(rings[1:], dirs[1:])],
                            0.002, G["seam"], body, sides=6))
    parts.append(g_pipe("CapHem" + sn, [rings[-1][j] + dirs[-1][j] * 0.003 for j in range(n)], 0.006, G["lea"],
                        body, sides=8))
    for side in (0, n - 1):
        parts.append(g_pipe("CapEnd%s%d" % (sn, side), [r[side] + d[side] * 0.003 for r, d in zip(rings, dirs)],
                            0.0055, G["lea"], body, sides=8))
    return parts


def gambeson_torso(G, src, body):
    """Tronco: gibão de gomos verticais (casca do corpo), placa do peito em losangos acolchoados com debrum,
    gola alta acolchoada que cobre o pescoço, cinto largo de couro com fivela e passadeira, sobre uma cinta de pano.
    Devolve (casca do gibão, peças rígidas)."""
    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.51

    coat = cb_piece(src, "Coat", is_torso, 0.014, G["cloth"])
    g_subdiv(coat, 2)

    NG = 9                                 # gomos verticais largos: costura a cada 2π/18 em volta do tronco

    def channels(p):
        a = math.atan2(p.x, -p.y)
        return abs(math.sin(a * NG)) ** 0.4
    _g_quilt(coat, channels, 0.008)
    rad, hit_a = _g_ray_tools(coat)
    parts = []
    for k in range(2 * NG):                # costuras dos gomos, de baixo da pala até a barra
        a = math.pi * k / NG
        parts.append(g_pipe("Seam%d" % k, [hit_a(a, 0.96 + 0.02 * i, 0.0005) for i in range(16)], 0.002,
                            G["cloth_d"], body, sides=6))

    # ---- pala acolchoada: casca do corpo do peito para cima (peito, ombros e costas), losangos estofados e
    #      costurados em tom próximo ao do pano, debrum de couro em todas as bordas
    YZ, RS, D = 1.255, 0.15, 0.04          # borda de baixo, raio médio (ângulo -> arco) e passo do losango

    def yoke_keep(c, b, n):
        return is_torso(c, b, n) and c.z >= YZ

    def diamond(p):
        s, v = math.atan2(p.x, -p.y) * RS / D, (p.z - YZ) / D
        return (abs(math.sin(math.pi * (s + v))) * abs(math.sin(math.pi * (s - v)))) ** 0.5
    yoke = cb_piece(src, "Yoke", yoke_keep, 0.026, G["quilt"])
    g_subdiv(yoke, 2)
    _g_quilt(yoke, diamond, 0.005)
    _, hit_y = _g_ray_tools(yoke)
    for fam in (1, -1):
        for k in range(int(2 * math.pi * RS / D) + 1):
            segs, cur = [], []
            for i in range(18):
                z = YZ + 0.004 + 0.014 * i
                a = (k * D + fam * (z - YZ)) / RS
                q = hit_y(a, z, 0.0, strict=True)
                if q is None:              # cava do braço: a costura para e recomeça do outro lado
                    segs.append(cur)
                    cur = []
                else:
                    cur.append(q)
            segs.append(cur)
            for m, sg in enumerate(s for s in segs if len(s) >= 2):
                parts.append(g_pipe("YokeSeam%d_%d_%d" % (fam + 1, k, m), sg, 0.0018, G["seam"], body, sides=6))
    parts += g_border_pipes(yoke, "YokeEdge", 0.0065, G["lea"], body)

    # ---- ombros: cúpulas curvas em volta da articulação (não a casca do braço, que fazia quina). Esquerdo:
    #      ombreira de lâminas sobrepostas com rebites e emblema na copa, presa por uma alça diagonal no peito;
    #      direito: capa redonda de gomos verticais.
    shoulder = []
    shoulder += gambeson_pauldron(G, src, body, 1, hit_y)
    shoulder += gambeson_cap(G, src, body, -1)

    # ---- gola alta acolchoada: do material da pala, abre um pouco em cima, com costuras verticais;
    def ring(z, rx, ry, y0=0.012, n=32):
        return [Vector((math.sin(2 * math.pi * j / n) * rx, y0 - math.cos(2 * math.pi * j / n) * ry, z))
                for j in range(n)]
    col = [ring(1.45, 0.118, 0.106), ring(1.49, 0.1, 0.09), ring(1.53, 0.097, 0.088), ring(1.56, 0.104, 0.094)]
    parts.append(g_smooth_mesh("Collar", col, G["quilt"], body, cap_end=False, thick=0.009, outward=True))
    parts.append(g_pipe("CollarRoll", ring(1.562, 0.106, 0.096), 0.005, G["lea"], body, sides=8, loop=True))
    for j in range(10):
        a = 2 * math.pi * j / 10
        parts.append(g_pipe("CollarSeam%d" % j, [Vector((math.sin(a) * rx, 0.012 - math.cos(a) * ry, z))
                                                 for z, rx, ry in ((1.495, 0.104, 0.094), (1.525, 0.102, 0.093),
                                                                   (1.555, 0.108, 0.098))], 0.0018, G["seam"], body,
                            sides=6))

    # ---- cinta mostarda e cinto largo de couro com tachas, fivela de aro e passadeira
    N = 48
    belt_rows = [[hit_a(2 * math.pi * j / N, z, out) for j in range(N)]
                 for z, out in ((0.985, 0.014), (0.99, 0.021), (1.06, 0.021), (1.065, 0.014))]
    parts.append(g_smooth_mesh("Belt", belt_rows, G["lea"], body, cap_end=False, outward=True))
    for nm, z in (("BeltPipeLo", 0.991), ("BeltPipeHi", 1.059)):
        parts.append(g_pipe(nm, [hit_a(2 * math.pi * j / N, z, 0.022) for j in range(N)], 0.0025, G["seam"], body,
                            loop=True))
    for k in range(16):                    # tachas em volta do cinto (menos na fivela)
        a = 0.45 + (2 * math.pi - 0.9) * k / 15
        parts.append(g_bead("Stud%d" % k, hit_a(a, 1.025, 0.022), 0.0065, G["metal"], body))
    bc = hit_a(0.0, 1.025, 0.026)
    W, H = 0.04, 0.042
    rim = [bc + Vector((x, -0.002, z)) for x, z in ((-W, H), (0, H + 0.004), (W, H), (W + 0.004, 0), (W, -H),
                                                    (0, -H - 0.004), (-W, -H), (-W - 0.004, 0))]
    parts.append(g_pipe("Buckle", rim, 0.006, G["metal"], body, sides=8, loop=True))
    parts.append(g_pipe("BuckleBar", [bc + Vector((-0.004, -0.004, H)), bc + Vector((-0.004, -0.008, 0)),
                                      bc + Vector((-0.004, -0.004, -H))], 0.0045, G["metal"], body, sides=8))
    parts.append(g_pipe("BucklePin", [bc + Vector((-0.004, -0.008, 0)), bc + Vector((W * 0.9, -0.01, 0))], 0.003,
                        G["metal"], body, sides=6))
    tip = [hit_a(a, 1.025, 0.027) for a in (0.0, 0.1, 0.2, 0.3)]           # ponta do cinto saindo da fivela
    parts.append(g_smooth_mesh("BeltTip", g_curved_tube(tip, [(0.03, 0.004)] * 4, sides=10, side0=(0, 0, 1)),
                               G["lea"], body))
    keep = hit_a(0.38, 1.025, 0.026)
    parts.append(g_plate("BeltKeeper", [(-0.008, 0.038), (0.008, 0.038), (0.008, -0.038), (-0.008, -0.038)], keep,
                         Vector((math.cos(0.38), math.sin(0.38), 0)), (0, 0, 1), 0.005, G["lea"], body))
    return coat, parts, shoulder


GB_SKIRT_Z1 = 0.4            # barra da saia (meia canela)
GB_SLIT_Z = 0.78             # a fenda de trás começa aqui; abaixo, cada metade é de uma perna


def _gb_skirt_w(p):
    """Pesos da saia do gibão: no alto vai com o tronco, descendo passa para a coxa e a canela do lado em que está
    (no meio da frente e de trás as duas pernas dividem, até a fenda)."""
    knee_z = CB_J["knee"].z
    leg = max(0.0, min(1.0, (0.97 - p.z) / 0.24)) * 0.9
    left = max(0.0, min(1.0, 0.5 + p.x / 0.12))
    cut = max(0.0, min(1.0, (GB_SLIT_Z - p.z) / 0.08))
    left = left * (1 - cut) + (1.0 if p.x > 0 else 0.0) * cut
    kn = max(0.0, min(1.0, (knee_z + 0.06 - p.z) / 0.2)) * 0.75
    fa = math.atan2(abs(p.x), -p.y)        # meio da frente (barriga da faixa): sem joelho
    if fa < 0.56:
        k = max(0.0, min(1.0, (fa - 0.46) / 0.1))
        kn *= k
    w = {"Body": 1.0 - leg}
    for n, sh in (("L", left), ("R", 1.0 - left)):
        w["Leg" + n] = leg * sh * (1 - kn)
        w["Knee" + n] = leg * sh * kn
    return {b: v for b, v in w.items() if v > 1e-4}


def gambeson_skirt(G, body, coat):
    """Saia longa do gibão: tiras verticais acolchoadas do cinto até a canela, aberta na frente (aparece a calça)
    e fendida atrás; no lado direito, um painel
    acolchoado em losangos até o joelho, preso ao cinto por uma alça. Debrum de couro em todas as barras.
    Devolve as peças (pesos por _gb_skirt_w)."""
    _, hit_a = _g_ray_tools(coat)
    Z0, Z1 = 0.985, GB_SKIRT_Z1
    NS = 13                                # tiras por meia volta

    r0_cache = {}

    def r0(a):                             # raio do pano no alto: por fora do gibão (e do glúteo) na cintura
        k = round(a, 4)
        if k not in r0_cache:
            r0_cache[k] = max(Vector((q.x, q.y)).length for q in (hit_a(a, 0.99), hit_a(a, 0.93), hit_a(a, 0.88)))
        return r0_cache[k]

    def pt(a, t, out=0.0):
        r = r0(a) + 0.014 + 0.07 * t ** 0.9 + out
        r += 0.006 * abs(math.sin(NS * a)) ** 0.4 * min(1.0, t * 8)       # gomo de cada tira
        return Vector((math.sin(a) * r, -math.cos(a) * r, Z0 - t * (Z0 - Z1)))

    def fo(t):                             # meia abertura da frente (rad)
        return 0.3 + 0.16 * t

    def tslit(t):                          # meia abertura da fenda de trás
        tz = (Z0 - GB_SLIT_Z) / (Z0 - Z1)
        return 0.09 * max(0.0, (t - tz) / (1 - tz)) ** 0.8

    parts = []
    rows, NC = 18, 30
    for sn, s in (("L", 1), ("R", -1)):
        grid = []
        for i in range(rows + 1):
            t = i / rows
            a0, a1 = fo(t), math.pi - tslit(t)
            grid.append([pt((a0 + (a1 - a0) * j / NC) * s, t) for j in range(NC + 1)])
        parts.append(g_smooth_mesh("Skirt" + sn, grid, G["cloth"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        for k in range(1, NS + 1):         # costura entre as tiras: só onde o pano existe
            a = math.pi * (k - 0.5) / NS
            seg = []
            for i in range(1, rows + 1):
                t = i / rows
                if fo(t) + 0.02 < a < math.pi - tslit(t) - 0.02:
                    seg.append(pt(a * s, t, 0.0005))
            if len(seg) >= 2:
                parts.append(g_pipe("SkirtSeam%s%d" % (sn, k), seg, 0.0018, G["cloth_d"], body, sides=6))
        parts.append(g_pipe("SkirtHem" + sn, [pt((fo(1) + (math.pi - tslit(1) - fo(1)) * j / NC) * s, 1.0, 0.002)
                                               for j in range(NC + 1)], 0.0055, G["lea"], body, sides=8))
        parts.append(g_pipe("SkirtFront" + sn, [pt(fo(i / rows) * s, i / rows, 0.002) for i in range(4, rows + 1)],
                            0.005, G["lea"], body, sides=8))
        sl = [pt((math.pi - tslit(i / rows)) * s, i / rows, 0.002) for i in range(rows + 1)
              if tslit(i / rows) > 0.004]
        if len(sl) >= 2:
            parts.append(g_pipe("SkirtSlit" + sn, sl, 0.005, G["lea"], body, sides=8))

    # ---- painel acolchoado do lado direito: losangos estofados, costura em losango, debrum, alça no cinto
    TA0, TA1, TT, rows_t, NT = -1.6, -0.5, 0.7, 14, 18
    RS, D = 0.24, 0.045

    def tasset_t(u):
        return TT - 0.06 * abs(u) ** 3

    def tp(u, v, out=0.0):                 # u em -1..1 pela largura, v em 0..1 descendo
        a = TA0 + (TA1 - TA0) * (u + 1) / 2
        t = tasset_t(u) * v
        q = pt(a, t, 0.042 + 0.006 * v + out)
        dz = (Z0 - q.z) / D
        da = a * RS / D
        bump = (abs(math.sin(math.pi * (da + dz))) * abs(math.sin(math.pi * (da - dz)))) ** 0.5
        return q + Vector((math.sin(a), -math.cos(a), 0)) * 0.006 * bump * min(1.0, v * 10)
    tgrid = [[tp(-1 + 2 * j / NT, i / rows_t) for j in range(NT + 1)] for i in range(rows_t + 1)]
    parts.append(g_smooth_mesh("Tasset", tgrid, G["quilt"], body, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    # costuras diagonais: seguem a*RS/D ± dz = inteiro dentro do painel
    for fam in (1, -1):
        for k in range(-30, 30):
            seg = []
            for i in range(1, 60):
                v = i / 60
                # resolve u na linha: da = k - fam*dz  ->  a = (k - fam*dz) * D / RS
                zq = Z0 - tasset_t(0) * v * (Z0 - Z1)
                dz = (Z0 - zq) / D
                a = (k - fam * dz) * D / RS
                u = (a - TA0) / (TA1 - TA0) * 2 - 1
                if -0.93 < u < 0.93 and v * tasset_t(0) < tasset_t(u) - 0.01:
                    seg.append(tp(u, v * tasset_t(0) / tasset_t(u), 0.0015))
                elif len(seg) >= 2:
                    break
            if len(seg) >= 2:
                parts.append(g_pipe("TassetSeam%d_%d" % (fam + 1, k + 30), seg, 0.0018, G["seam"], body, sides=6))
    tedge = [r[0] for r in tgrid][1:] + tgrid[-1][1:-1] + [r[-1] for r in tgrid][::-1][:-1]
    parts.append(g_pipe("TassetEdge", tedge, 0.0055, G["lea"], body, sides=8))
    for k in range(0, NT + 1, 3):
        q = tgrid[-2][k]
        parts.append(g_bead("TassetRivet%d" % k, q + Vector((q.x, q.y, 0)).normalized() * 0.004,
                            0.0045, G["metal"], body))
    am = (TA0 + TA1) / 2
    strap = [hit_a(am, 1.03, 0.026), pt(am, 0.0, 0.045), pt(am, 0.06, 0.05)]
    parts.append(g_smooth_mesh("TassetStrap", g_curved_tube(strap, [(0.017, 0.003)] * 3, sides=10, side0=(math.cos(am), math.sin(am), 0)),
                               G["lea"], body))
    parts.append(g_bead("TassetStrapRivet", pt(am, 0.05, 0.055), 0.006, G["metal"], body))

    # ---- faixa mostarda: enrolada sob o cinto e caída na frente em barriga (mais baixa um pouco à esquerda),
    #      com dobras que seguem a barriga; a ponta desce pela borda da frente da saia até a barra; um cordão
    #      pende do cinto do lado direito
    NB, rows_b = 64, 10

    def sag(a):                            # quanto a barra da faixa cai (0 atrás, 1 no ponto mais baixo)
        return max(0.0, math.cos(a - 0.25)) ** 1.6

    def sash_pt(a, v, out=0.0):
        z = 1.0 - v * (0.07 + 0.1 * sag(a))
        t = max(0.0, (Z0 - z) / (Z0 - Z1))
        fold = 0.005 * math.sin(2 * math.pi * (v * 2.5 + 0.15 * math.cos(a))) * v * sag(a)
        q = pt(a, t, 0.009 + v ** 0.8 * (0.012 + 0.036 * sag(a)) + fold + out)
        return Vector((q.x, q.y, z))
    sgrid = [[sash_pt(-math.pi + 2 * math.pi * j / NB, i / rows_b) for j in range(NB)] for i in range(rows_b + 1)]
    parts.append(g_smooth_mesh("Sash", sgrid, G["band"], body, cap_end=False, thick=0.006, outward=True))
    for k, v in enumerate((0.35, 0.6, 0.82)):      # vincos das dobras: só na barriga da frente
        seg = [sash_pt(a, v, 0.001) for a in (0.25 + 1.5 * (-1 + 2 * j / 24) for j in range(25))
               if sag(a) > 0.15]
        parts.append(g_pipe("SashFold%d" % k, seg, 0.0022, G["band_d"], body, sides=6))
    parts.append(g_pipe("SashHem", [sash_pt(-math.pi + 2 * math.pi * j / NB, 1.0, 0.002) for j in range(NB)], 0.003,
                        G["band_d"], body, sides=6, loop=True))
    ta = fo(0.25) + 0.07                   # ponta: desce pela borda da frente da saia esquerda
    tail = [sash_pt(ta, 0.9, 0.004)] + [pt(fo(t) + 0.07, t, 0.012 + 0.004 * math.sin(9 * t))
                                         for t in (0.3, 0.42, 0.54, 0.66, 0.78, 0.9, 0.98)]
    tw = [(0.03, 0.004)] + [(0.026 - 0.004 * k / 6, 0.004) for k in range(7)]
    parts.append(g_smooth_mesh("SashTail", g_curved_tube(tail, tw, sides=10, side0=(math.cos(ta), math.sin(ta), 0)),
                               G["band"], body))
    c0, c1 = hit_a(-0.55, 0.99, 0.024), hit_a(-0.95, 0.99, 0.024)          # cordão em laço
    mid = (c0 + c1) / 2
    mid = Vector((mid.x, mid.y, 0)).normalized() * (Vector((mid.x, mid.y)).length + 0.06) + Vector((0, 0, 0.89))
    parts.append(g_pipe("Cord", g_spline([c0, (c0 + mid) / 2 + Vector((0, 0, -0.01)), mid,
                                           (c1 + mid) / 2 + Vector((0, 0, -0.01)), c1], 16)
                        , 0.0035, G["cord"], body, sides=6))
    return parts


def _gb_arm_frame(s):
    """Eixo do braço do lado s no repouso: ombro -> cotovelo -> pulso, com comprimento corrido u (m)."""
    sh, el, wr = (cb_mirror(CB_J[k], s) for k in ("shoulder", "elbow", "wrist"))
    L1, L2 = (el - sh).length, (wr - el).length

    def at(u):                          # ponto do eixo e direção do eixo no comprimento u
        if u <= L1:
            return sh + (el - sh) * (u / L1), (el - sh).normalized()
        return el + (wr - el) * min(1.0, (u - L1) / L2), (wr - el).normalized()

    def frame(ax):
        o = Vector((s, 0, 0))
        o = (o - ax * o.dot(ax)).normalized()
        return o, ax.cross(o).normalized()

    def coords(p):                      # (u, φ) do ponto p: φ = 0 para fora, cresce para a frente
        t1 = _cb_t(p, sh, el)
        u = t1 * L1 if t1 <= 1.0 else L1 + _cb_t(p, el, wr) * L2
        c, ax = at(u)
        o, f = frame(ax)
        d = p - c
        return u, math.atan2(d.dot(f), d.dot(o))

    def ring(ob_bvh, u, out=0.0, n=28, phis=None):
        c, ax = at(u)
        o, f = frame(ax)
        pts = []
        for ph in (phis if phis is not None else [2 * math.pi * j / n for j in range(n)]):
            d = o * math.cos(ph) + f * math.sin(ph)
            h = ob_bvh.ray_cast(c + d * 0.25, -d)[0]
            pts.append(None if h is None else h + d * out)
        return pts
    return L1, L2, at, coords, ring


def gambeson_sleeves(G, src, body):
    """Mangas inteiras: no alto do braço (sob a capa e a ombreira) o pano de gomos do gibão, uma faixa mostarda
    no bíceps e, dali ao pulso, manga escura acolchoada em losangos com costura em losango; no braço da ombreira
    uma braçadeira de couro do cotovelo ao pulso, aberta em cima, com três correias de fivela e rebites.
    Devolve (cascas tiradas do corpo, enfeites)."""
    from mathutils.bvhtree import BVHTree
    shells, orn = [], []
    TS, TB0, TB1 = 0.5, 0.57, 0.63      # fim do pano de gomos e faixa mostarda: fração do braço (ombro -> cotovelo)
    RA, D = 0.045, 0.034                # raio médio do braço e passo do losango
    for sn, s in (("L", 1), ("R", -1)):
        sh, el = cb_mirror(CB_J["shoulder"], s), cb_mirror(CB_J["elbow"], s)
        L1, L2, at, coords, ring = _gb_arm_frame(s)

        def arm(b, c, s=s):
            return (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0 and \
                (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86)

        def t_of(c, sh=sh, el=el):
            return _cb_t(c, sh, el)
        upper = cb_piece(src, "SleeveUp" + sn, lambda c, b, n: arm(b, c) and b.startswith("Arm") and t_of(c) < TS,
                         0.012, G["cloth"])
        g_subdiv(upper, 2)
        _g_quilt(upper, lambda p, coords=coords: abs(math.sin(4 * coords(p)[1])) ** 0.4, 0.005)
        lower = cb_piece(src, "SleeveLow" + sn, lambda c, b, n: arm(b, c) and
                         (not b.startswith("Arm") or t_of(c) >= TS), 0.012, G["quilt"])
        g_subdiv(lower, 2)

        def dia(p, coords=coords):
            u, ph = coords(p)
            a, v = ph * RA / D, u / D
            return (abs(math.sin(math.pi * (a + v))) * abs(math.sin(math.pi * (a - v)))) ** 0.5
        _g_quilt(lower, dia, 0.005)
        shells += [upper, lower]
        lb = BVHTree.FromPolygons([v.co.copy() for v in lower.data.vertices],
                                  [tuple(p.vertices) for p in lower.data.polygons])
        ub = BVHTree.FromPolygons([v.co.copy() for v in upper.data.vertices],
                                  [tuple(p.vertices) for p in upper.data.polygons])
        # costuras em losango: hélices nos dois sentidos, achadas por raios contra a manga
        u0, u1 = TS * L1 + 0.006, L1 + 0.84 * L2
        if s > 0:
            u1 = L1 + 0.1 * L2          # sob a braçadeira não precisa
        for fam in (1, -1):
            for k in range(int(2 * math.pi * RA / D) + 1):
                seg, steps = [], 40
                for i in range(steps + 1):
                    u = u0 + (u1 - u0) * i / steps
                    ph = (k * D + fam * u) / RA
                    q = ring(lb, u, 0.0005, phis=[ph])[0]
                    if q is None:
                        if len(seg) >= 2:
                            orn.append(g_pipe("SleeveSeam%s%d_%d_%d" % (sn, fam + 1, k, i), seg, 0.0016, G["seam"],
                                              body, sides=6))
                        seg = []
                    else:
                        seg.append(q)
                if len(seg) >= 2:
                    orn.append(g_pipe("SleeveSeam%s%d_%d" % (sn, fam + 1, k), seg, 0.0016, G["seam"], body, sides=6))
        for j in range(8):              # costura dos gomos do alto do braço
            ph = (j + 0.5) * math.pi / 4
            seg = [q for q in (ring(ub, u, 0.0005, phis=[ph])[0] for u in
                               [TS * L1 * i / 10 for i in range(3, 10)]) if q is not None]
            if len(seg) >= 2:
                orn.append(g_pipe("SleeveRib%s%d" % (sn, j), seg, 0.0016, G["cloth_d"], body, sides=6))
        # faixa mostarda: anéis por cima da manga (raios contra ela), bojuda no meio, debrum escuro nas bordas
        brs = []
        for i in range(7):
            v = i / 6
            pts = ring(lb, (TB0 + (TB1 - TB0) * v) * L1, 0.004 + 0.005 * math.sin(math.pi * v), n=32)
            if None in pts:
                break
            brs.append(pts)
        if len(brs) == 7:
            orn.append(g_smooth_mesh("SleeveBand" + sn, brs, G["band"], body, cap_end=False, outward=True,
                                     thick=0.004))
            for nm, r in (("Hi", brs[0]), ("Lo", brs[-1])):
                orn.append(g_pipe("SleeveBandEdge%s%s" % (sn, nm), r, 0.003, G["band_d"], body, sides=6, loop=True))
        cuff = ring(lb, L1 + 0.82 * L2, 0.002)
        if None not in cuff and s < 0:
            orn.append(g_pipe("SleeveCuff" + sn, cuff, 0.006, G["lea"], body, sides=8, loop=True))

        if s > 0:                        # ---- braçadeira de couro
            FV0, FV1 = 0.1, 0.84

            def vk(c, b, n):
                return arm(b, c) and b.startswith("Elbow") and FV0 <= _cb_fore_t(c) <= FV1
            vb = cb_piece(src, "Vambrace" + sn, vk, 0.026, G["lea"])
            g_subdiv(vb, 2)
            me = vb.data
            for v in me.vertices:        # boca larga no cotovelo, aperta no pulso
                ft = _cb_fore_t(v.co)
                v.co += v.normal * (0.014 * max(0.0, 1 - (ft - FV0) / 0.3) ** 2 - 0.004 * max(0.0, ft - 0.6))
            shells.append(vb)
            orn += g_border_pipes(vb, "VambraceEdge" + sn, 0.005, G["lea"], body)
            vbv = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
            for k, ft in enumerate((0.3, 0.52, 0.74)):
                u = L1 + ft * L2
                pts = ring(vbv, u, 0.004, n=32)
                if None in pts:
                    continue
                orn.append(g_smooth_mesh("VambraceStrap%s%d" % (sn, k),
                                         g_curved_tube(pts + pts[:2], [(0.0095, 0.0025)] * (len(pts) + 2), sides=8,
                                                       side0=tuple(at(u)[1])), G["lea"], body, cap_end=False))
                c, ax = at(u)
                q = pts[len(pts) // 4]   # fivela no lado de fora-frente
                nn = (q - c - ax * (q - c).dot(ax)).normalized()
                w = ax.cross(nn).normalized()
                rim = [q + nn * 0.004 + ax * y + w * x for x, y in ((-0.01, 0.012), (0.01, 0.012), (0.012, 0),
                                                                     (0.01, -0.012), (-0.01, -0.012), (-0.012, 0))]
                orn.append(g_pipe("VambraceBuckle%s%d" % (sn, k), rim, 0.0026, G["metal"], body, sides=6, loop=True))
                orn.append(g_pipe("VambraceTip%s%d" % (sn, k), [q + nn * 0.004 + w * 0.012, q + nn * 0.005 + w * 0.03],
                                  0.003, G["lea"], body, sides=6))
            for k in range(6):           # rebites na boca do cotovelo
                q = ring(vbv, L1 + 0.16 * L2, 0.003, phis=[-1.3 + 2.6 * k / 5])[0]
                if q is not None:
                    orn.append(g_bead("VambraceRivet%s%d" % (sn, k), q, 0.0045, G["metal"], body))
    return shells, orn


def g_skinned_pants(src, material):
    """Calça com pele (coxa) para as roupas de casca: o alto da coxa fica mais com o tronco, então na passada
    não sai pela frente da roupa (a loft rígida furava a faixa e a saia)."""
    pants = cb_piece(src, "Pants", lambda c, b, n: b.startswith("Leg") and c.z < 0.97, 0.006, material)
    g_subdiv(pants)
    gb = pants.vertex_groups.get("Body") or pants.vertex_groups.new(name="Body")
    for v in pants.data.vertices:
        f = max(0.0, min(1.0, (v.co.z - 0.78) / 0.16)) * 0.7
        if f <= 0:
            continue
        moved = 0.0
        for ge in v.groups:
            if ge.group != gb.index and pants.vertex_groups[ge.group].name.startswith("Leg"):
                moved += ge.weight * f
                ge.weight *= 1 - f
        if moved:
            gb.add([v.index], moved + sum(ge.weight for ge in v.groups if ge.group == gb.index), 'REPLACE')
    return pants


def g_export_skinned(style):
    """Exporta uma roupa de casca: rodando como <style>_f (female.py), deforma para o corpo feminino antes."""
    if globals().get("g_export") is globals().get("_g_export_f", 0):
        fem_warp()                     # cascas, enfeites e ossos vão para o corpo feminino pelos pesos
        export("gear/" + style + "_f", export_vertex_color='ACTIVE')
        return
    if globals().get("g_export") is globals().get("_g_export_d", 0):
        dwarf_warp()                   # o mesmo para o corpo do anão (dwarf.py)
        export("gear/" + style + "_d", export_vertex_color='ACTIVE')
        return
    export("gear/" + style, export_vertex_color='ACTIVE')


# ------------------------------------------------------------------ cavaleiro branco (tier III, malha lisa)
# Referência: Avetetsuya Studios, "White Knight". Placa clara de prata sobre gibão escuro arroxeado: peitoral
# com quilha no meio e borda dobrada, gorjal alto, lâminas da barriga em V, cachecol vermelho enrolado no
# pescoço, talabarte de camurça com pingente de estrela, cinto de couro sobre faixa vermelha. Placas são peças
# rígidas no Body; o pano vermelho é t2_ (color2 do item).
def wknight_mats():
    return dict(
        plate=gm("wk_plate", "#D3D9E0", 0.32, 0.75), plate_d=gm("wk_plate_d", "#8E98A5", 0.4, 0.75),
        under=gm("wk_under", "#3B3644", 0.9), red=gm("t2_wk_red", "#A3242B", 0.9),
        suede=gm("wk_suede", "#B59A72", 0.95), lea=gm("wk_leather", "#5A4334", 0.8),
        star=gm("wk_star", "#BFE6FF", 0.2, 0.3),
    )


def _wk_torso_sec(z):
    """Seção do tronco do corpo na altura z (interpolada de CB_TORSO): (rx, ry, fr, bk, y0)."""
    rows = CB_TORSO
    for (z0, rx0, ry0, e0), (z1, rx1, ry1, e1) in zip(rows, rows[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)

            def L(a, b):
                return a + (b - a) * t
            return (L(rx0, rx1), L(ry0, ry1), L(e0.get("fr", 1.0), e1.get("fr", 1.0)),
                    L(e0.get("bk", 1.0), e1.get("bk", 1.0)), L(e0.get("y", 0.0), e1.get("y", 0.0)))
    z0, rx0, ry0, e0 = rows[-1]
    return rx0, ry0, e0.get("fr", 1.0), e0.get("bk", 1.0), e0.get("y", 0.0)


def wk_plate_pt(a, z, off, keel=0.0, sq=2.0, fr_max=None):
    """Ponto da placa no ângulo a (0 = frente) e altura z, off metros por fora do corpo. A placa não segue o
    relevo do peito: a seção é a do corpo alisada (maior entre a altura e as vizinhas)."""
    secs = [_wk_torso_sec(z + dz) for dz in (-0.012, 0.0, 0.012)]
    rx = max(s[0] for s in secs) + off
    ry = max(s[1] for s in secs) + off
    fr = max(s[2] for s in secs)
    if fr_max is not None:             # peito liso: a placa não acompanha o volume do peitoral
        fr = min(fr, fr_max)
    bk = max(s[3] for s in secs)
    y0 = secs[1][4]
    x, y = cb_spt(a, rx, ry, fr, bk, sq=sq, keel=keel)
    return Vector((x, y + y0, z))


def _wk_plate(name, rows_fn, n_rows, n_cols, material, parent, thick=0.006):
    """Placa lisa: rows_fn(i, j) -> ponto (grade aberta), engrossada, com as normais para fora."""
    rings = [[rows_fn(i / n_rows, j / n_cols) for j in range(n_cols + 1)] for i in range(n_rows + 1)]
    return g_smooth_mesh(name, rings, material, parent, cap_end=False, closed=False, thick=thick, outward=True), rings


def wknight_torso(K, src, body):
    """Tronco: gibão escuro (casca), peitoral e costal lisos com quilha, borda dobrada e frisos, gorjal alto em
    volta do pescoço, três lâminas da barriga em V com rebites, cachecol vermelho, talabarte com pingente,
    cinto sobre faixa vermelha. Devolve (casca, peças)."""
    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52

    def under_keep(c, b, n):           # gibão desce pela virilha e pelo alto das coxas (entre as placas)
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.7 <= c.z < 1.52
    under = cb_piece(src, "Under", under_keep, 0.006, K["under"])
    g_subdiv(under, 2)
    parts = []
    # ---- peitoral: frente, da linha sob o peito até a gola, com a borda de baixo em V e a de cima em arco
    A = 1.3                            # meia largura (rad) do peitoral; o costal cobre o resto menos as axilas

    def top_z(a):                      # borda de cima: sobe para os ombros, desce na frente (decote do gorjal)
        return 1.49 - 0.06 * math.cos(a) ** 2 - 0.07 * (abs(a) / A) ** 4

    def bot_z(a):                      # borda de baixo: ponta em V no meio
        return 1.165 + 0.055 * min(1.0, abs(a) / 1.0) ** 1.3

    def breast(u, v):                  # u: 0 em cima -> 1 embaixo; v: -A -> A
        a = -A + 2 * A * v
        z = top_z(a) + (bot_z(a) - top_z(a)) * u
        bulge = 0.004 * math.sin(math.pi * min(1.0, u * 1.15)) * max(0.0, math.cos(a)) ** 1.5   # peito abaulado
        return wk_plate_pt(a, z, 0.016 + bulge, keel=0.025)   # justo no masculino; o busto vem do fem_warp
    bp, br = _wk_plate("Breastplate", breast, 16, 40, K["plate"], body)
    parts.append(bp)
    # borda dobrada (cordão) em volta do peitoral, um friso paralelo por dentro e o friso da quilha
    outline = br[0] + [r[-1] for r in br[1:]] + br[-1][::-1][1:] + [r[0] for r in br[::-1][1:-1]]
    parts.append(g_pipe("BreastRim", outline, 0.0065, K["plate"], body, sides=8, loop=True))
    inner = [breast(0.12, 0.04 + 0.92 * j / 30) for j in range(31)]
    parts.append(g_pipe("BreastFlute", [q + Vector((0, -0.002, 0)) for q in inner], 0.0022, K["plate_d"], body,
                        sides=6))
    parts.append(g_pipe("BreastKeel", [breast(u, 0.5) + Vector((0, -0.003, 0)) for u in (0.1, 0.4, 0.7, 0.98)],
                        0.003, K["plate_d"], body, sides=6))
    # ---- costal: costas inteiras entre as axilas
    B = math.pi - 1.25

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.48 - 0.07 * abs(2 * v - 1) ** 4             # cantos de cima arredondados (sob a ombreira)
        z = zt + (1.06 - zt) * u                           # desce até a faixa: as costas ficam fechadas
        return wk_plate_pt(a, z, 0.017)
    bk, bkr = _wk_plate("Backplate", back, 12, 30, K["plate"], body)
    parts.append(bk)
    parts.append(g_pipe("BackRim", bkr[0] + [r[-1] for r in bkr[1:]] + bkr[-1][::-1][1:] + [r[0] for r in bkr[::-1][1:-1]],
                        0.006, K["plate"], body, sides=8, loop=True))
    # ---- gorjal: colar de placa em pé em volta do pescoço, mais alto na frente, borda dobrada em cima
    def ring(z, rx, ry, y0=0.012, n=36):
        return [Vector((math.sin(2 * math.pi * j / n) * rx, y0 - math.cos(2 * math.pi * j / n) * ry, z))
                for j in range(n)]
    gor = []
    for k, (z0, rx, ry) in enumerate(((1.44, 0.135, 0.118), (1.49, 0.112, 0.1), (1.535, 0.094, 0.086),
                                      (1.575, 0.09, 0.084))):
        r = ring(z0, rx, ry)
        gor.append([q + Vector((0, 0, 0.03 * max(0.0, -math.cos(2 * math.pi * j / 36)) * (k / 3)))
                    for j, q in enumerate(r)])
    parts.append(g_smooth_mesh("Gorget", gor, K["plate"], body, cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("GorgetRim", gor[-1], 0.006, K["plate"], body, sides=8, loop=True))
    parts.append(g_pipe("GorgetLine", [q + (q - Vector((0, 0.012, q.z))).normalized() * 0.002 for q in gor[1]],
                        0.0022, K["plate_d"], body, sides=6, loop=True))
    # ---- lâminas da barriga: três faixas em V, cada uma por baixo da de cima, com rebite nas pontas
    for k in range(3):
        zt = 1.185 - 0.05 * k
        AL = 1.15 - 0.05 * k

        def lame(u, v, zt=zt, AL=AL, k=k):
            a = -AL + 2 * AL * v
            vv = 0.03 * min(1.0, abs(a) / 1.0) ** 1.3
            z = zt + vv - 0.058 * u
            return wk_plate_pt(a, z, 0.015 + 0.006 * u)
        lm, lr = _wk_plate("Lame%d" % k, lame, 4, 30, K["plate"], body)
        parts.append(lm)
        parts.append(g_pipe("LameRim%d" % k, lr[-1], 0.005, K["plate"], body, sides=8))
        for end in (0, -1):
            q = lr[2][end]
            nn = Vector((q.x, q.y, 0)).normalized()
            parts.append(g_bead("LameRivet%d_%d" % (k, end), q + nn * 0.004 - (Vector((q.x, 0, 0)).normalized() * 0.012),
                                0.0055, K["plate_d"], body))
    # ---- faixa vermelha e cinto de couro (a faixa sai por baixo do cinto)
    N = 48
    from mathutils.bvhtree import BVHTree
    ub = BVHTree.FromPolygons([v.co.copy() for v in under.data.vertices], [tuple(p.vertices) for p in under.data.polygons])

    def on_under(a, z, out):
        d = Vector((math.sin(a), -math.cos(a), 0))
        h = ub.ray_cast(Vector((0, 0, z)) + d * 0.6, -d)[0]
        return (h if h is not None else Vector((0, 0, z)) + d * 0.15) + d * out
    sash = [[on_under(2 * math.pi * j / N, z, out) for j in range(N)]
            for z, out in ((0.94, 0.012), (0.96, 0.024), (1.03, 0.026), (1.05, 0.014))]
    parts.append(g_smooth_mesh("Sash", sash, K["red"], body, cap_end=False, outward=True))
    belt = [[on_under(2 * math.pi * j / N, z, out) for j in range(N)]
            for z, out in ((0.975, 0.026), (0.98, 0.034), (1.012, 0.034), (1.017, 0.026))]
    parts.append(g_smooth_mesh("Belt", belt, K["lea"], body, cap_end=False, outward=True))
    for k, a in enumerate((-0.35, 0.1, 0.55)):          # passadores de metal no cinto
        q = on_under(a, 0.996, 0.036)
        w = Vector((math.cos(a), math.sin(a), 0))
        parts.append(g_pipe("BeltLoop%d" % k, [q - w * 0.006 + Vector((0, 0, 0.02)), q - w * 0.006 - Vector((0, 0, 0.02))],
                            0.003, K["plate_d"], body, sides=6))
    # ---- talabarte: do ombro direito ao quadril esquerdo, por cima do peitoral (raios contra ele)
    bpy.context.view_layer.update()
    pb = BVHTree.FromPolygons([bp.matrix_world @ v.co for v in bp.data.vertices], [tuple(p.vertices) for p in bp.data.polygons])
    path = []
    for i in range(13):
        t = i / 12
        a = -0.95 + 1.9 * t
        z = 1.44 - 0.33 * t
        d = Vector((math.sin(a), -math.cos(a), 0))
        h = pb.ray_cast(Vector((0, 0, z)) + d * 0.6, -d)[0] if t < 0.85 else None
        path.append((h if h is not None else wk_plate_pt(a, z, 0.05)) + d * 0.008)
    tube = g_curved_tube(path, [(0.022, 0.003)] * len(path), sides=10, side0=(0.4, 0, 1))
    parts.append(g_smooth_mesh("Baldric", tube, K["suede"], body))
    for sgn in (1, -1):                 # debrum de couro nas duas bordas
        edge = []
        for i, q in enumerate(path):
            a = -0.95 + 1.9 * i / 12
            d = Vector((math.sin(a), -math.cos(a), 0))
            tg = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
            edge.append(q + tg.cross(d).normalized() * 0.021 * sgn + d * 0.002)
        parts.append(g_pipe("BaldricEdge%d" % (sgn > 0), edge, 0.003, K["lea"], body, sides=6))
    ring_c = path[3]
    parts.append(g_pipe("BaldricRing", [ring_c + Vector((math.cos(2 * math.pi * j / 10) * 0.014, -0.006,
                                                         math.sin(2 * math.pi * j / 10) * 0.014)) for j in range(10)],
                        0.003, K["plate_d"], body, sides=6, loop=True))
    # ---- pingente de estrela: corrente do gorjal até o peito e a estrela de oito pontas
    star_c = breast(0.45, 0.62) + Vector((0, -0.009, 0))   # encostada no peitoral
    top = gor[0][22]
    chain = [top.lerp(star_c, t) + Vector((0, -0.01 * math.sin(math.pi * t), 0)) for t in (0, 0.25, 0.5, 0.75, 1.0)]
    parts.append(g_pipe("StarChain", chain, 0.0018, K["plate_d"], body, sides=6))
    pts8 = []
    for j in range(16):
        r = 0.04 if j % 2 == 0 else 0.013
        if j % 4 == 2:
            r = 0.026
        an = math.pi * j / 8
        pts8.append((math.cos(an) * r, math.sin(an) * r))
    parts.append(g_plate("Star", pts8, star_c, (1, 0, 0), (0, 0, 1), 0.008, K["star"], body))
    # ---- cachecol vermelho enrolado no gorjal, com uma ponta caída nas costas
    M_ = 40

    def sc_pt(j):
        a = 2 * math.pi * j / M_
        return Vector((math.sin(a) * 0.118, 0.01 - math.cos(a) * 0.106, 1.505 + 0.012 * math.cos(2 * a)))
    path_s = [sc_pt(j) for j in range(M_)]
    rr = [(0.026 + 0.008 * abs(math.sin(3 * 2 * math.pi * j / M_)), 0.016) for j in range(M_)]
    parts.append(g_smooth_mesh("Scarf", g_curved_tube(path_s + path_s[:2], rr + rr[:2], sides=14, side0=(0, 0, 1)),
                               K["red"], body, cap_end=False))
    # ponta longa do cachecol: sai da volta nas costas (lado direito), passa por cima do costal e cai solta
    # até a dobra do joelho, alargando e ondulando um pouco; um corte em ponta dupla na barra
    a0 = 2 * math.pi * 26 / M_
    path, wid = [sc_pt(26)], [(0.042, 0.006)]
    for i in range(1, 15):
        t = i / 14
        z = 1.47 - (1.47 - 0.5) * t
        a = a0 + (math.pi - 0.25 - a0) * min(1.0, t * 2.2)
        off = 0.035 + 0.11 * max(0.0, 1.2 - z) + 0.012 * math.sin(t * 7)
        q = wk_plate_pt(a, max(z, 0.9), off)
        path.append(Vector((q.x + 0.014 * math.sin(t * 5.5), q.y, z)))
        wid.append((0.045 + 0.05 * t ** 0.8, 0.0055))
    K_back = g_smooth_mesh("BackCloth", g_curved_tube(path, wid, sides=12,
                                                      side0=(math.cos(a0), math.sin(a0), 0)), K["red"], body)
    parts.append(K_back)
    cloth = [K_back]
    return under, parts, cloth



def wknight_pauldron(K, src, body, s):
    """Ombreira de placa: copa grande e lisa em cúpula sobre o ombro e duas lâminas que descem pelo braço, cada
    uma por baixo da de cima, com borda dobrada em volta, friso paralelo à barra da copa e rebites nas pontas."""
    sn = "L" if s > 0 else "R"
    lames = [(0.05, 1.95, 1.8, 0.05, 0.004), (1.78, 2.7, 1.95, 0.042, 0.005), (2.55, 3.45, 2.0, 0.034, 0.005)]
    parts = []
    for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, s, lames, phis=32, rows=10)):
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), rings, K["plate"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        n = len(rings[0])
        edge = [rings[-1][j] + dirs[-1][j] * 0.002 for j in range(n)]
        r0 = 4 if k == 0 else 0         # na copa a borda das pontas começa abaixo do topo (lá as pontas se juntam)
        ends = [[r[side] + d[side] * 0.002 for r, d in zip(rings[r0:], dirs[r0:])] for side in (0, n - 1)]
        parts.append(g_pipe("PauldronRim%s%d" % (sn, k), ends[0][::-1] + edge[1:-1] + ends[1], 0.006, K["plate"], body,
                            sides=8))
        fi = len(rings) - 3            # friso paralelo à barra
        parts.append(g_pipe("PauldronFlute%s%d" % (sn, k), [rings[fi][j] + dirs[fi][j] * 0.001 for j in range(2, n - 2)],
                            0.0022, K["plate_d"], body, sides=6))
        for j in (3, n - 4):            # rebites nas pontas
            q = rings[-3][j] + dirs[-3][j] * 0.003
            parts.append(g_bead("PauldronRivet%s%d_%d" % (sn, k, j), q, 0.0055, K["plate_d"], body))
    return parts


def wknight_arm(K, src, body, s):
    """Placas do braço: braçal do antebraço (tubo liso do cotovelo ao pulso, com aresta na linha de fora, boca
    alargada no pulso, borda dobrada e friso), cotoveleira em cúpula com asa de placa do lado de fora."""
    from mathutils.bvhtree import BVHTree
    sn = "L" if s > 0 else "R"
    # medida só contra o braço: com o corpo inteiro, os raios do lado de dentro batiam no quadril
    tmp = cb_piece(src, "ArmProbe" + sn, lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
    bpy.data.objects.remove(tmp, do_unlink=True)
    L1, L2, at, coords, ring = _gb_arm_frame(s)
    parts = []
    # ---- braçal: anéis em volta do eixo do antebraço, raio do corpo + folga, aresta para fora e boca no pulso
    T0, T1, NR, NP = 0.1, 0.9, 16, 32
    rings, dirs = [], []
    for i in range(NR + 1):
        t = T0 + (T1 - T0) * i / NR
        u = L1 + t * L2
        c, ax = at(u)
        o = Vector((s, 0, 0))
        o = (o - ax * o.dot(ax)).normalized()
        f = ax.cross(o).normalized()
        row, drow, rs = [], [], []
        for j in range(NP):
            ph = 2 * math.pi * j / NP
            d = o * math.cos(ph) + f * math.sin(ph)
            h = bvh.ray_cast(c + d * 0.25, -d)
            r = (0.25 - h[3]) if h[0] is not None else 0.04
            rs.append(r)
            row.append((c, d))
        # seção redonda pela média (o corpo tem degraus), afinando para o pulso, e oito faces chanfradas
        rm = sum(rs) / len(rs)
        rs = [(rs[j - 1] + 2 * rs[j] + rs[(j + 1) % NP]) / 4 for j in range(NP)]
        add = 0.01 + 0.006 * max(0.0, (t - 0.86) / (T1 - 0.86)) ** 1.5      # borda do pulso levemente aberta
        seg = 2 * math.pi / 8
        row = [c + d * ((max(rs[j], 0.5 * (rs[j] + rm)) + add) /
                        math.cos(((2 * math.pi * j / NP + seg / 2) % seg) - seg / 2) ** 0.35)
               for j, (c, d) in enumerate(row)]
        drow = [o * math.cos(2 * math.pi * j / NP) + f * math.sin(2 * math.pi * j / NP) for j in range(NP)]
        rings.append(row)
        dirs.append(drow)
    parts.append(g_smooth_mesh("Vambrace" + sn, rings, K["plate"], body, cap_end=False, thick=0.005, outward=True))
    for nm, i in (("Top", 0), ("Cuff", NR)):
        parts.append(g_pipe("VambraceRim%s%s" % (sn, nm), [q + d * 0.002 for q, d in zip(rings[i], dirs[i])], 0.0055,
                            K["plate"], body, sides=8, loop=True))
    i = int(NR * 0.68)                  # friso antes da boca do pulso
    parts.append(g_pipe("VambraceBand" + sn, [q + d * 0.002 for q, d in zip(rings[i], dirs[i])], 0.0035,
                        K["plate_d"], body, sides=6, loop=True))
    parts.append(g_pipe("VambraceRidge" + sn, [r[0] + d[0] * 0.0015 for r, d in zip(rings[1:-1], dirs[1:-1])],
                        0.0022, K["plate_d"], body, sides=6))
    # ---- cotoveleira: cúpula na ponta do cotovelo (para trás e um pouco para fora) e asa do lado de fora
    el = cb_mirror(CB_J["elbow"], s)
    n0 = (Vector((0, 1, 0)) * 0.8 + Vector((s, 0, 0)) * 0.6).normalized()
    a1 = n0.cross(Vector((0, 0, 1))).normalized()
    a2 = n0.cross(a1).normalized()
    cop, cdir = [], []
    for i in range(1, 8):
        al = 1.15 * i / 7
        row, drow = [], []
        for j in range(24):
            ph = 2 * math.pi * j / 24
            d = (n0 * math.cos(al) + (a1 * math.cos(ph) + a2 * math.sin(ph)) * math.sin(al)).normalized()
            h = bvh.ray_cast(el + d * 0.25, -d)
            r = ((0.25 - h[3]) if h[0] is not None else 0.045) + 0.024
            row.append(el + d * r)
            drow.append(d)
        cop.append(row)
        cdir.append(drow)
    tip = el + n0 * (((0.25 - bvh.ray_cast(el + n0 * 0.25, -n0)[3]) if bvh.ray_cast(el + n0 * 0.25, -n0)[0] is not None
                      else 0.045) + 0.026)
    parts.append(g_smooth_mesh("Couter" + sn, [[tip] * 24] + cop, K["plate"], body, cap_end=False, thick=0.005,
                               outward=True))
    parts.append(g_pipe("CouterRim" + sn, [q + d * 0.002 for q, d in zip(cop[-1], cdir[-1])], 0.005, K["plate"], body,
                        sides=8, loop=True))
    parts.append(g_bead("CouterBoss" + sn, tip + n0 * 0.002, 0.009, K["plate_d"], body))
    o = Vector((s, 0, 0))
    wc = el + o * 0.062 + Vector((0, 0.012, 0))       # asa: placa em gota do lado de fora, apontando para baixo
    leaf = [(math.sin(2 * math.pi * j / 20) * 0.03 * (1 - 0.35 * max(0.0, -math.cos(2 * math.pi * j / 20))),
             math.cos(2 * math.pi * j / 20) * 0.045 - 0.008) for j in range(20)]
    parts.append(g_plate("CouterWing" + sn, leaf, wc, (0, 1, 0), (0, 0, 1), 0.006, K["plate"], body))
    parts.append(g_pipe("CouterWingRim" + sn, [wc + o * 0.0045 + Vector((0, x, y)) for x, y in leaf], 0.003,
                        K["plate_d"], body, sides=6, loop=True))
    return parts


def _wk_hip_pt(a, z, off):
    """Ponto em volta do quadril (a: 0 = frente), cone que abre para baixo a partir da seção da cintura alta,
    largo o bastante para passar por fora das coxas."""
    rx, ry, fr, bk, y0 = _wk_torso_sec(0.95)
    drop = max(0.0, 0.96 - z)
    rx, ry = rx + off + 0.12 * drop, ry + off + 0.12 * drop
    x, y = cb_spt(a, rx, ry, fr, bk)
    return Vector((x, y + y0, z))


def _wk_center_w(p):
    """Peso da placa do meio: desce junto com as duas coxas pela média (a placa não dobra no meio)."""
    leg = max(0.0, min(1.0, (0.975 - p.z) / 0.15)) * 0.85
    return {"Body": 1.0 - leg, "LegL": leg / 2, "LegR": leg / 2}


def _wk_cloth_w(p):
    """Pano vermelho comprido (frente e costas): no alto com o tronco, a parte de baixo vai pela média das duas
    coxas, como um pano solto que balança pouco."""
    leg = max(0.0, min(1.0, (0.92 - p.z) / 0.35)) * 0.6
    return {"Body": 1.0 - leg, "LegL": leg / 2, "LegR": leg / 2}


def _wk_tasset_w(p):
    """Peso das escarcelas: logo abaixo do cinto já vão com a coxa do seu lado (a coxa que sobe na passada
    leva a placa junto, em vez de atravessá-la)."""
    leg = max(0.0, min(1.0, (0.985 - p.z) / 0.1)) * 0.95
    return {"Body": 1.0 - leg, ("LegL" if p.x > 0 else "LegR"): leg}


def wknight_tassets(K, body):
    """Escarcelas: em cada coxa três lâminas que descem do cinto, cada uma por cima da de baixo, a última com a
    barra em ponta para fora; borda dobrada, friso e rebites. No meio da frente, a placa em escudo com a
    filigrana em relevo (espinha, volutas e losango). Devolve (escarcelas, placa do meio)."""
    tas, mid = [], []
    for sn, s in (("L", 1), ("R", -1)):
        A0, A1 = 0.42, 1.42               # frente e lado da frente: a mão passa por fora
        for k in range(3):
            zt = 0.965 - 0.085 * k
            last = k == 2

            def lame(u, v, zt=zt, last=last):
                a = (A0 + (A1 - A0) * v) * s
                h = 0.1 + (0.06 * v ** 1.4 if last else 0.0)            # a última desce em ponta para fora
                z = zt - h * u
                return _wk_hip_pt(a, z, 0.03 + 0.008 * u)
            ob, rr = _wk_plate("Tasset%s%d" % (sn, k), lame, 6, 26, K["plate"], body, thick=0.005)
            tas.append(ob)
            edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
            tas.append(g_pipe("TassetRim%s%d" % (sn, k), edge, 0.0055, K["plate"], body, sides=8))
            tas.append(g_pipe("TassetFlute%s%d" % (sn, k), [lame(0.72, 0.06 + 0.88 * j / 20) for j in range(21)],
                              0.002, K["plate_d"], body, sides=6))
            for j in ((0.08, 0.92) if not last else (0.08, 0.5, 0.92)):
                q = lame(0.35, j)
                tas.append(g_bead("TassetRivet%s%d_%d" % (sn, k, int(j * 100)), q + Vector((q.x, q.y, 0)).normalized() * 0.004,
                                  0.0055, K["plate_d"], body))
    # ---- placa do meio: escudo pendurado do cinto, ponta para baixo, curvado com o corpo
    W, Z0, Z1 = 0.36, 0.975, 0.7

    def shield(u, v):
        half = W * (1 - u ** 1.8 * 0.95)          # estreita até a ponta
        a = -half + 2 * half * v
        z = Z0 - (Z0 - Z1) * u
        return _wk_hip_pt(a, z, 0.05 + 0.03 * u)
    sh, sr = _wk_plate("CenterPlate", shield, 12, 16, K["plate"], body, thick=0.006)
    mid.append(sh)
    edge = [r[0] for r in sr] + [r[-1] for r in sr][::-1]
    mid.append(g_pipe("CenterRim", edge + edge[:1], 0.0055, K["plate"], body, sides=8))
    out = 0.0045

    def on(u, v):
        q = shield(u, v)
        return q + Vector((q.x, q.y, 0)).normalized() * out
    F = K["plate_d"]
    mid.append(g_pipe("FiliSpine", [on(u, 0.5) for u in (0.08, 0.3, 0.55, 0.8, 0.95)], 0.0035, F, body, sides=6))
    for side, vs in (("L", 1), ("R", -1)):     # volutas: sobem do meio, enrolam para fora
        curl = []
        for i in range(14):
            t = i / 13
            ang = 3.6 * t
            rad = 0.3 * (1 - 0.75 * t)
            vv = 0.5 + vs * (0.08 + rad * math.sin(ang) * 0.9)
            uu = 0.3 - rad * math.cos(ang) * 0.55 + 0.12 * t
            curl.append(on(max(0.05, min(0.9, uu)), max(0.06, min(0.94, vv))))
        mid.append(g_pipe("FiliCurl" + side, g_spline(curl, 30), 0.003, F, body, sides=6))
        mid.append(g_pipe("FiliLeaf" + side, [on(0.45, 0.5), on(0.6, 0.5 + vs * 0.22), on(0.78, 0.5 + vs * 0.08)],
                          0.0028, F, body, sides=6))
    dia = [on(0.2, 0.5), on(0.28, 0.6), on(0.36, 0.5), on(0.28, 0.4)]
    mid.append(g_pipe("FiliDiamond", dia, 0.003, F, body, sides=6, loop=True))
    # ---- pano vermelho da frente: sai da faixa atrás da placa do meio e cai entre as pernas até a canela
    lp, lw = [], []
    for i in range(13):
        t = i / 12
        z = 0.97 - (0.97 - 0.34) * t
        q = _wk_hip_pt(0.0, min(z, 0.95), 0.03)
        y = q.y + 0.03 * t                       # cai quase reto, voltando um pouco para as pernas
        lp.append(Vector((0.01 * math.sin(t * 6), y, z)))
        lw.append((0.055 + 0.012 * t, 0.005))
    loin = g_smooth_mesh("Loincloth", g_curved_tube(lp, lw, sides=12, side0=(1, 0, 0)), K["red"], body)
    return tas, mid, [loin]

def build_a_whiteknight():
    """Cavaleiro branco (tier III). Rodada 1: tronco (peitoral, costal, gorjal, lâminas, cachecol, talabarte,
    pingente, cinto e faixa); braços e pernas com o gibão escuro até as próximas peças."""
    style = "a_whiteknight"
    P, R = g_rig(style)
    M = g_mats()
    K = wknight_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["under"])
    g_skinned_pants(src, M["pants"])
    under, parts, cloth = wknight_torso(K, src, body)
    shoulder = wknight_pauldron(K, src, body, 1) + wknight_pauldron(K, src, body, -1)
    arms = wknight_arm(K, src, body, 1) + wknight_arm(K, src, body, -1)
    tas, mid, loin = wknight_tassets(K, body)
    KL = dict(K, lining=K["plate"])    # culote e coxeiras da couraça de ferro, com a borda dobrada em prata
    culet = firstplate_culet(KL, body)
    cuis, cuis_trim = firstplate_cuisses(KL, src, body)
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["under"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 0.7),
                             (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (tas, "fn", _wk_tasset_w, 1.0), (mid, "fn", _wk_center_w, 1.0),
                             (cloth + loin, "fn", _wk_cloth_w, 1.0),
                             (culet, "fn", _gb_skirt_w, 1.0), (cuis_trim, "vert", ("LegL", "LegR"), 1.0)])
    join_objs("WhiteKnight", [o for o in parts if o not in cloth] + shoulder + arms + tas + mid + cloth + loin + culet
              + cuis_trim)
    g_export_skinned(style)



# ------------------------------------------------------------------ paladino real (tier IV, malha lisa)
# Referência: Bell, "Paladin". Couraça de prata comprida até o cinto sobre cota escura, com faixas douradas
# gravadas descendo dos lados do peito, cruz dourada escura com volutas no meio do peito, gola de ouro em
# pontas em volta do gorjal, cinto fino com fivela. Ouro e prata fixos; o pano (próximas peças) é t1_.
def _pal_hip_pt(a, z, off):
    """Como _wk_hip_pt, mas a folga e a abertura para baixo vão por igual em volta (não multiplicadas pelo
    glúteo): a roupa de placa cai reta atrás, sem marcar o glúteo."""
    rx, ry, fr, bk, y0 = _wk_torso_sec(0.95)
    bk = min(bk, 1.08)
    x, y = cb_spt(a, rx, ry, fr, bk)
    d = Vector((math.sin(a), -math.cos(a), 0))
    grow = off + 0.1 * max(0.0, 0.96 - z)
    return Vector((x, y + y0, z)) + d * grow


def paladin_mats():
    return dict(
        plate=gm("pa_plate", "#C8CED6", 0.3, 0.8), plate_d=gm("pa_plate_d", "#7F8894", 0.4, 0.8),
        gold=gm("pa_gold", "#D2A64A", 0.3, 0.85), gold_d=gm("pa_gold_d", "#6E4E1E", 0.45, 0.8),
        mail=gm("pa_mail", "#45464C", 0.6, 0.6), lea=gm("pa_leather", "#5A4130", 0.8),
        cloth=gm("t1_pal_cloth", "#C9A24E", 0.9), white=gm("pa_white", "#E4E2DC", 0.9),
        dark=gm("pa_dark", "#2E2B31", 0.9), hem=gm("pa_hem", "#B98A3A", 0.6, 0.3),
    )


def paladin_torso(K, src, body):
    """Tronco: cota escura (casca), couraça e costal lisos com borda dobrada, faixas douradas gravadas dos
    lados do peito, cruz dourada com volutas no meio, gorjal de prata com gola de ouro em pontas e cinto fino.
    Devolve (casca, peças)."""
    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52

    under = cb_piece(src, "Mail", is_torso, 0.006, K["mail"])
    g_subdiv(under, 2)
    parts = []
    A = 1.3

    def top_z(a):
        return 1.49 - 0.06 * math.cos(a) ** 2 - 0.07 * (abs(a) / A) ** 4

    def bot_z(a):                      # couraça comprida: termina no cinto, um pouco mais baixa na frente
        return 1.03 - 0.012 * math.cos(a) ** 2

    def breast(u, v):
        a = -A + 2 * A * v
        z = top_z(a) + (bot_z(a) - top_z(a)) * u
        bulge = 0.006 * math.sin(math.pi * min(1.0, u * 1.6)) * max(0.0, math.cos(a)) ** 1.5
        return wk_plate_pt(a, z, 0.016 + bulge, keel=0.03)
    bp, br = _wk_plate("Cuirass", breast, 20, 40, K["plate"], body)
    parts.append(bp)
    outline = br[0] + [r[-1] for r in br[1:]] + br[-1][::-1][1:] + [r[0] for r in br[::-1][1:-1]]
    parts.append(g_pipe("CuirassRim", outline, 0.0065, K["plate"], body, sides=8, loop=True))
    B = math.pi - 1.25

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.48 - 0.07 * abs(2 * v - 1) ** 4
        z = zt + (1.03 - zt) * u
        return wk_plate_pt(a, z, 0.017)
    bk, bkr = _wk_plate("Backplate", back, 16, 30, K["plate"], body)
    parts.append(bk)
    parts.append(g_pipe("BackRim", bkr[0] + [r[-1] for r in bkr[1:]] + bkr[-1][::-1][1:] + [r[0] for r in bkr[::-1][1:-1]],
                        0.006, K["plate"], body, sides=8, loop=True))

    def on(u, v, out=0.004):           # ponto por cima da couraça
        q = breast(u, v)
        return q + Vector((q.x, q.y, 0)).normalized() * out
    # ---- faixas douradas gravadas: descem dos lados do peito até o cinto, com folhas em V ao longo
    for sn, vc in (("L", 0.79), ("R", 0.21)):
        path = [on(u, vc + 0.03 * (u - 0.5) * (1 if vc > 0.5 else -1), 0.003) for u in (0.1 + 0.88 * i / 16 for i in range(17))]
        a = -A + 2 * A * vc
        side0 = (math.cos(a), math.sin(a), 0)
        parts.append(g_smooth_mesh("GoldBand" + sn, g_curved_tube(path, [(0.016, 0.0025)] * len(path), sides=8,
                                                                  side0=side0), K["gold"], body))
        w = Vector(side0)
        for k in range(1, 16, 2):     # folhas: pares de traços em V subindo pela faixa
            c = path[k]
            up = (path[k - 1] - path[k + 1]).normalized()
            nn = Vector((c.x, c.y, 0)).normalized()
            for sg in (1, -1):
                parts.append(g_pipe("GoldLeaf%s%d_%d" % (sn, k, sg > 0),
                                    [c + nn * 0.003 - up * 0.004, c + nn * 0.003 + up * 0.006 + w * 0.011 * sg],
                                    0.0018, K["gold_d"], body, sides=6))
        parts.append(g_pipe("GoldBandEdge%sA" % sn, [q + w * 0.016 + Vector((q.x, q.y, 0)).normalized() * 0.002 for q in path],
                            0.0022, K["gold_d"], body, sides=6))
        parts.append(g_pipe("GoldBandEdge%sB" % sn, [q - w * 0.016 + Vector((q.x, q.y, 0)).normalized() * 0.002 for q in path],
                            0.0022, K["gold_d"], body, sides=6))
    # ---- cruz no meio do peito: braços que alargam nas pontas (dourado escuro), aro e volutas douradas
    cc = on(0.36, 0.5, 0.004)
    for ang in (0, 90, 180, 270):      # cruz pátea: quatro braços que alargam (cada um convexo) e o miolo
        r = math.radians(ang)
        d = Vector((math.cos(r), math.sin(r)))
        p = Vector((-d.y, d.x))
        L = 0.066 if ang == 270 else 0.046
        quad = [d * 0.004 - p * 0.008, d * L - p * 0.019, d * L + p * 0.019, d * 0.004 + p * 0.008]
        parts.append(g_plate("CrossArm%d" % ang, [(q.x, q.y) for q in quad], cc, (1, 0, 0), (0, 0, 1), 0.007,
                             K["gold_d"], body))
        rim = [cc + Vector((0, -0.0055, 0)) + Vector((q.x, 0, q.y)) for q in (quad[1], quad[2])]
        parts.append(g_pipe("CrossTip%d" % ang, rim, 0.0028, K["gold"], body, sides=6))
        parts.append(g_pipe("CrossSide%d" % ang, [cc + Vector((0, -0.0055, 0)) + Vector((q.x, 0, q.y))
                                                   for q in (quad[0], quad[1])], 0.0022, K["gold"], body, sides=6))
        parts.append(g_pipe("CrossSideB%d" % ang, [cc + Vector((0, -0.0055, 0)) + Vector((q.x, 0, q.y))
                                                    for q in (quad[3], quad[2])], 0.0022, K["gold"], body, sides=6))
    parts.append(g_bead("CrossBoss", cc + Vector((0, -0.004, 0)), 0.009, K["gold"], body))
    for side, vs in (("L", 1), ("R", -1)):     # volutas: saem do braço da cruz e enrolam para baixo
        curl = []
        for i in range(18):
            t = i / 17
            ang = 4.6 * t
            rad = 0.09 * (1 - 0.72 * t)
            curl.append(on(0.36 + 0.03 + rad * math.sin(ang) * 0.75, 0.5 + vs * (0.13 + 0.06 * t - rad * math.cos(ang) * 0.5 + rad * 0.5),
                           0.004))
        parts.append(g_pipe("CrossCurl" + side, g_spline(curl, 34), 0.0028, K["gold"], body, sides=6))
    # ---- gorjal de prata e gola de ouro em pontas por cima da borda da couraça
    def ring(z, rx, ry, y0=0.012, n=36):
        return [Vector((math.sin(2 * math.pi * j / n) * rx, y0 - math.cos(2 * math.pi * j / n) * ry, z))
                for j in range(n)]
    gor = [ring(1.44, 0.132, 0.116), ring(1.49, 0.11, 0.098), ring(1.535, 0.094, 0.086), ring(1.565, 0.09, 0.084)]
    parts.append(g_smooth_mesh("Gorget", gor, K["plate"], body, cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("GorgetRim", gor[-1], 0.006, K["gold"], body, sides=8, loop=True))
    collar = [Vector((q.x * 1.04, 0.012 + (q.y - 0.012) * 1.04, q.z + 0.006)) for q in ring(1.452, 0.134, 0.118)]
    parts.append(g_pipe("GoldCollar", collar, 0.009, K["gold"], body, sides=10, loop=True))
    for k, ang in enumerate((-1.25, -0.75, -0.3, 0.3, 0.75, 1.25)):       # pontas de ouro abertas para fora
        base = Vector((math.sin(ang) * 0.138, 0.012 - math.cos(ang) * 0.122, 1.455))
        out = Vector((math.sin(ang), -math.cos(ang), 0))
        L = 0.06 if abs(ang) < 0.5 else 0.05
        tip = [base, base + out * L * 0.5 + Vector((0, 0, 0.004)), base + out * L + Vector((0, 0, 0.02))]   # abre para fora e sobe
        parts.append(g_smooth_mesh("CollarSpike%d" % k, g_curved_tube(g_spline(tip, 6),
                                                                       [(0.014 * (1 - i / 7) + 0.001, 0.003) for i in range(7)],
                                                                       sides=8, side0=(math.cos(ang), math.sin(ang), 0)),
                                   K["gold"], body))
    # ---- cinto fino de couro com fivela dourada
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update()
    cb = BVHTree.FromPolygons([bp.matrix_world @ v.co for v in bp.data.vertices], [tuple(p.vertices) for p in bp.data.polygons])
    N = 48

    def on_body(a, z, out):
        d = Vector((math.sin(a), -math.cos(a), 0))
        h = cb.ray_cast(Vector((0, 0, z)) + d * 0.6, -d)[0]
        return (h if h is not None else wk_plate_pt(a, z, 0.024)) + d * out
    belt = [[on_body(2 * math.pi * j / N, z, out) for j in range(N)]
            for z, out in ((1.04, 0.002), (1.043, 0.007), (1.067, 0.007), (1.07, 0.002))]
    parts.append(g_smooth_mesh("Belt", belt, K["lea"], body, cap_end=False, outward=True))
    bc = on_body(0.0, 1.055, 0.006)
    rim = [bc + Vector((x, 0, y)) for x, y in ((-0.02, 0.016), (0.02, 0.016), (0.02, -0.016), (-0.02, -0.016))]
    parts.append(g_pipe("Buckle", rim, 0.004, K["gold"], body, sides=8, loop=True))
    parts.append(g_pipe("BuckleBar", [bc + Vector((-0.006, 0.004, 0.017)), bc + Vector((-0.006, 0.004, -0.017))], 0.0035,
                        K["gold"], body, sides=6))
    return under, parts



def paladin_pauldron(K, src, body, s):
    """Ombreiras do paladino. Direita (s < 0): copa e três lâminas em leque, cada uma com debrum de ouro e uma
    lâmina em ponta que sai para trás e para fora (as pontas crescem de cima para baixo), voluta de ouro na
    copa. Esquerda (s > 0): copa redonda e três lâminas com debrum de ouro, medalhão de cruz num sol de ouro
    na frente (onde a capa prende)."""
    sn = "L" if s > 0 else "R"
    fan = s < 0
    lames = [(0.05, 1.85, 1.8, 0.05, 0.006), (1.7, 2.55, 1.95, 0.044, 0.016 if fan else 0.006),
             (2.4, 3.25, 2.0, 0.038, 0.02 if fan else 0.006), (3.1, 3.95, 2.05, 0.032, 0.024 if fan else 0.006)]
    parts = []
    for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, s, lames, phis=32, rows=10)):
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), rings, K["plate"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        n = len(rings[0])
        edge = [rings[-1][j] + dirs[-1][j] * 0.002 for j in range(n)]
        r0 = 4 if k == 0 else 0
        ends = [[r[side] + d[side] * 0.002 for r, d in zip(rings[r0:], dirs[r0:])] for side in (0, n - 1)]
        parts.append(g_pipe("PauldronGold%s%d" % (sn, k), ends[0][::-1] + edge[1:-1] + ends[1], 0.0062, K["gold"], body,
                            sides=8))
        fi = len(rings) - 3
        parts.append(g_pipe("PauldronFlute%s%d" % (sn, k), [rings[fi][j] + dirs[fi][j] * 0.001 for j in range(3, n - 3)],
                            0.0022, K["plate_d"], body, sides=6))
        if fan and k > 0:              # lâmina em ponta saindo da ponta de trás, para fora e para baixo
            j = int(n * 0.6)           # do lado de fora, um pouco para trás: aparece de frente como um leque
            base = rings[-2][j]
            dn = dirs[-2][j]
            back = (rings[-2][min(n - 1, j + 4)] - rings[-2][j - 4]).normalized()
            L = 0.07 + 0.025 * k
            path = [base, base + back * L * 0.2 + dn * L * 0.5 + Vector((0, 0, 0.01)),
                    base + back * L * 0.35 + dn * L + Vector((0, 0, 0.022 - 0.014 * k))]
            sp = g_spline(path, 8)
            w = [(0.022 * (1 - i / 9) ** 0.8 + 0.001, 0.0035) for i in range(9)]
            side0 = back.cross(dn).normalized()
            parts.append(g_smooth_mesh("PauldronBlade%s%d" % (sn, k), g_curved_tube(sp, w, sides=8, side0=tuple(side0)),
                                       K["plate"], body))
            parts.append(g_pipe("PauldronBladeGold%s%d" % (sn, k), [q + side0 * ww[0] for q, ww in zip(sp, w)][:-1],
                                0.0028, K["gold"], body, sides=6))
        if k == 0:
            i0, j0 = len(rings) // 2, n // 2
            q, dn = rings[i0][j0], dirs[i0][j0]
            up = (rings[i0 - 2][j0] - rings[i0 + 2][j0]).normalized()
            side = up.cross(dn).normalized()
            up = dn.cross(side).normalized()
            if fan:                    # voluta de ouro na copa
                curl = []
                for i in range(16):
                    t = i / 15
                    ang = 4.4 * t
                    rad = 0.04 * (1 - 0.7 * t)
                    curl.append(q + dn * 0.002 + side * (rad * math.cos(ang) - 0.02 + 0.03 * t) + up * (rad * math.sin(ang)))
                parts.append(g_pipe("PauldronCurl" + sn, g_spline(curl, 30), 0.003, K["gold"], body, sides=6))
            else:                      # medalhão: sol de ouro com cruz escura, na frente da copa
                jm = int(n * 0.8)
                im = len(rings) - 3
                mq, mdn = rings[im][jm], dirs[im][jm]
                mup = (rings[im - 2][jm] - rings[im + 2][jm]).normalized()
                ms = mup.cross(mdn).normalized()
                mup = mdn.cross(ms).normalized()
                sun = []
                for i in range(32):
                    r = 0.042 if i % 2 == 0 else 0.026
                    an = math.pi * i / 16
                    sun.append((math.cos(an) * r, math.sin(an) * r))
                parts.append(g_plate("MedalSun" + sn, sun, mq + mdn * 0.006, ms, mup, 0.006, K["gold"], body))
                parts.append(g_pipe("MedalRing" + sn, [mq + mdn * 0.011 + ms * math.cos(2 * math.pi * i / 20) * 0.024
                                                       + mup * math.sin(2 * math.pi * i / 20) * 0.024 for i in range(20)],
                                    0.003, K["gold_d"], body, sides=6, loop=True))
                for ang in (0, 90, 180, 270):
                    r = math.radians(ang)
                    d2 = Vector((math.cos(r), math.sin(r)))
                    p2 = Vector((-d2.y, d2.x))
                    quad = [d2 * 0.003 - p2 * 0.005, d2 * 0.022 - p2 * 0.011, d2 * 0.022 + p2 * 0.011, d2 * 0.003 + p2 * 0.005]
                    parts.append(g_plate("MedalCross%s%d" % (sn, ang), [(v.x, v.y) for v in quad], mq + mdn * 0.012, ms, mup,
                                         0.005, K["gold_d"], body))
                parts.append(g_bead("MedalBoss" + sn, mq + mdn * 0.014, 0.006, K["gold"], body))
    return parts


def paladin_faulds(K, body):
    """Escarcelas do paladino: na frente uma faixa de placa com o arco aberto no meio (borda dobrada e rebites);
    em cada coxa quatro lâminas de barra arredondada, cada uma por cima da de baixo, com uma faixa de ouro
    gravada descendo pelo meio e um rebite de cada lado dela. Devolve (lâminas das coxas, placa da frente)."""
    tas, mid = [], []
    for sn, s in (("L", 1), ("R", -1)):
        A0, A1, AC = 0.3, 1.45, 0.85
        for k in range(4):
            zt = 1.055 - 0.075 * k             # a primeira sai de baixo do cinto (presa nele)

            def lame(u, v, zt=zt, k=k):
                a = (A0 + (A1 - A0) * v) * s
                h = 0.09 - 0.02 * abs(2 * v - 1) ** 3                   # barra arredondada (pontas sobem)
                z = zt - h * u
                return _pal_hip_pt(a, z, (0.004 if k == 0 else 0.022) + 0.012 * u)
            ob, rr = _wk_plate("Tasset%s%d" % (sn, k), lame, 6, 24, K["plate"], body, thick=0.005)
            tas.append(ob)
            edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
            tas.append(g_pipe("TassetRim%s%d" % (sn, k), edge, 0.0052, K["plate"], body, sides=8))
            vc = (AC - A0) / (A1 - A0)

            def on(u, v, out=0.0035, lame=lame):
                q = lame(u, v)
                return q + Vector((q.x, q.y, 0)).normalized() * out
            stripe = [on(u, vc) for u in (0.05, 0.35, 0.65, 0.95)]
            a = AC * s
            w = Vector((math.cos(a), math.sin(a), 0))
            tas.append(g_smooth_mesh("TassetGold%s%d" % (sn, k), g_curved_tube(stripe, [(0.018, 0.0022)] * 4, sides=8,
                                                                              side0=tuple(w)), K["gold"], body))
            for sg in (1, -1):
                tas.append(g_pipe("TassetGoldEdge%s%d_%d" % (sn, k, sg > 0), [q + w * 0.018 * sg for q in stripe], 0.0018,
                                  K["gold_d"], body, sides=6))
                q = on(0.45, vc + sg * 0.24, 0.004)
                tas.append(g_bead("TassetRivet%s%d_%d" % (sn, k, sg > 0), q, 0.0055, K["plate_d"], body))
            for i in (1, 2):           # folhas gravadas na faixa
                c = on(0.33 * i, vc, 0.005)
                tas.append(g_pipe("TassetLeaf%s%d_%d" % (sn, k, i), [c - w * 0.01 + Vector((0, 0, 0.006)), c,
                                                                   c + w * 0.01 + Vector((0, 0, 0.006))], 0.0016,
                                  K["gold_d"], body, sides=6))
    # ---- faixa da frente com o arco aberto no meio
    AF = 0.62

    def front(u, v):
        a = -AF + 2 * AF * v
        x = a / 0.36
        arch = 0.075 * max(0.0, 1 - x * x) ** 0.5                       # arco: a barra sobe no meio
        z = 1.06 - (0.12 - arch) * u
        return _pal_hip_pt(a, z, 0.008 + 0.03 * u)
    fp, fr = _wk_plate("FrontFauld", front, 8, 36, K["plate"], body, thick=0.006)
    mid.append(fp)
    mid.append(g_pipe("FrontFauldRim", [r[0] for r in fr] + fr[-1][1:] + [r[-1] for r in fr][::-1][1:], 0.0058,
                      K["plate"], body, sides=8))
    mid.append(g_pipe("FrontFauldArch", [front(0.97, 0.5 + (j / 20 - 0.5) * 0.62) +
                                         Vector((0, -0.003, 0.004)) for j in range(21)], 0.0024, K["gold"], body, sides=6))
    for v in (0.12, 0.88, 0.3, 0.7):
        q = front(0.55, v)
        mid.append(g_bead("FrontFauldRivet%d" % int(v * 100), q + Vector((q.x, q.y, 0)).normalized() * 0.005, 0.0055,
                          K["plate_d"], body))
    return tas, mid


def paladin_skirt(K, body):
    """Saia do paladino: dois panos que saem por baixo das escarcelas até a canela, dourado à direita (cor do
    item) e branco à esquerda, com pregas soltas, aberta na frente e fendida atrás; barra larga bordada (faixa de
    ouro com zigue-zague e losangos) e um painel escuro no meio da frente. Devolve as peças (pesos da saia)."""
    Z0, Z1 = 0.99, 0.43
    out = []

    def pt(a, t, add=0.0):
        z = Z0 - (Z0 - Z1) * t
        fold = (0.02 * math.sin(9 * a + 0.6) + 0.007 * math.sin(23 * a)) * min(1.0, t * 2.5)   # pregas soltas
        return _pal_hip_pt(a, z, 0.006 + 0.03 * t ** 1.1 + fold + add)

    def fo(t):
        return 0.16 + 0.08 * t

    def slit(t):
        return 0.06 * max(0.0, (t - 0.35) / 0.65) ** 0.8
    rows, NC = 16, 34
    for sn, s, mat in (("L", 1, K["white"]), ("R", -1, K["cloth"])):
        def ga(j, t):
            a0, a1 = fo(t), math.pi - slit(t)
            return (a0 + (a1 - a0) * j / NC) * s
        grid = [[pt(ga(j, i / rows), i / rows) for j in range(NC + 1)] for i in range(rows + 1)]
        out.append(g_smooth_mesh("Skirt" + sn, grid, mat, body, cap_end=False, closed=False, thick=0.005, outward=True))
        # barra bordada: faixa por cima do pano na altura da barra, debrum, zigue-zague e losangos
        th = [0.88, 0.94, 1.0]
        band = [[pt(ga(j, t), t, 0.003) for j in range(NC + 1)] for t in th]
        out.append(g_smooth_mesh("SkirtHem" + sn, band, K["hem"], body, cap_end=False, closed=False, thick=0.003,
                                 outward=True))
        for nm, t in (("Hi", 0.88), ("Lo", 1.0)):
            out.append(g_pipe("SkirtHemEdge%s%s" % (sn, nm), [pt(ga(j, t), t, 0.006) for j in range(NC + 1)], 0.0028,
                              K["gold"], body, sides=6))
        zz = [pt(ga(j * 0.5, 0.91 if j % 2 == 0 else 0.97), 0.91 if j % 2 == 0 else 0.97, 0.007) for j in range(2 * NC + 1)]
        out.append(g_pipe("SkirtZig" + sn, zz, 0.0018, K["gold_d"], body, sides=6))
        out.append(g_pipe("SkirtFrontEdge" + sn, [pt(fo(i / rows) * s, i / rows, 0.003) for i in range(1, rows + 1)],
                          0.0035, K["gold"], body, sides=6))
    # painel escuro no meio da frente (aparece pela abertura), do cinto até a barra
    lp = [_pal_hip_pt(0.0, Z0 - (Z0 - Z1) * t, 0.004 + 0.02 * t) + Vector((0, 0.004, 0)) for t in (i / 10 for i in range(11))]
    out.append(g_smooth_mesh("CenterCloth", g_curved_tube(lp, [(0.085 + 0.02 * i / 10, 0.004) for i in range(11)], sides=10,
                                                          side0=(1, 0, 0)), K["dark"], body))
    return out


def _pal_cape_w(p):
    """Capa: no alto com o tronco; da cintura para baixo um pouco com a média das coxas (balança pouco e não
    deixa a coxa que sobe atravessar o pano)."""
    leg = max(0.0, min(1.0, (0.95 - p.z) / 0.45)) * 0.45
    return {"Body": 1.0 - leg, "LegL": leg / 2, "LegR": leg / 2}


def paladin_cape(K, body):
    """Capa dourada comprida (cor do item): presa no alto do costal entre as ombreiras, cai pelas costas até a
    canela abrindo em pregas largas e passando por fora da saia; debrum de ouro na barra e nas bordas e dois
    fechos de ouro em losango no alto."""
    rows, NC = 18, 30
    ZT, ZB = 1.455, 0.34

    WRAP = 1.2                         # curva das bordas para a frente (y -= WRAP * x²)

    def need(a, z):                    # ponto mínimo por fora do costal, da saia e das escarcelas
        if z > 1.0:
            q = wk_plate_pt(a, z, 0.03)
        else:
            q = _pal_hip_pt(a, min(z, 0.99), 0.03 + 0.015 * (1.0 - z))
        return q

    def center_need(z):                # y que o meio da capa precisa ter para a casca curva passar por fora
        return max(q.y + WRAP * q.x ** 2 for q in (need(math.pi + 0.07 * k, z) for k in range(-9, 10)))
    zs = [ZT - (ZT - ZB) * i / 24 for i in range(25)]
    nd = [center_need(z) for z in zs]
    # reta mais em pé possível: a menor inclinação cujo alto fique no máximo 2,5 cm atrás do costal
    for k in range(81):
        slope = 0.005 * k
        yt = max(n - slope * (ZT - z) for n, z in zip(nd, zs))
        if yt - nd[0] <= 0.025:
            break

    def cpt(u, v, out=0.0):            # u: 0 em cima -> 1 embaixo; v: 0 -> 1 de um lado ao outro
        """Capa reta: o meio desce numa reta do alto do costal (inclinada só o bastante para passar por fora
        do glúteo e da saia, sem marcá-lo), as bordas curvam um pouco para a frente."""
        z = ZT - (ZT - ZB) * u
        x = (0.15 + 0.09 * u ** 0.8) * (2 * v - 1)
        fold = 0.016 * math.sin(2 * math.pi * v * 5.5) * u ** 0.9
        y = yt + slope * (ZT - z) - WRAP * x * x + fold + out
        return Vector((x, y, z))
    grid = [[cpt(i / rows, j / NC) for j in range(NC + 1)] for i in range(rows + 1)]
    parts = [g_smooth_mesh("Cape", grid, K["cloth"], body, cap_end=False, closed=False, thick=0.006, outward=True)]
    parts.append(g_pipe("CapeEdge", [cpt(i / rows, 0, 0.002) for i in range(rows, 0, -1)], 0.004, K["gold"], body, sides=6))
    parts.append(g_pipe("CapeEdgeR", [cpt(i / rows, 1, 0.002) for i in range(1, rows + 1)], 0.004, K["gold"], body, sides=6))
    parts.append(g_pipe("CapeHem", [cpt(1.0, j / NC, 0.003) for j in range(NC + 1)], 0.006, K["gold"], body, sides=8))
    parts.append(g_pipe("CapeHemIn", [cpt(0.965, j / NC, 0.004) for j in range(NC + 1)], 0.0025, K["gold_d"], body,
                        sides=6))
    for k, v in enumerate((0.08, 0.92)):  # fechos no alto
        q = cpt(0.03, v, 0.006)
        d = Vector((q.x, q.y, 0)).normalized()
        w = d.cross(Vector((0, 0, 1))).normalized()
        parts.append(g_plate("CapeClasp%d" % k, [(x * 0.024, y * 0.032) for x, y in G_DIAMOND], q, w, (0, 0, 1), 0.006,
                             K["gold"], body))
        parts.append(g_bead("CapeClaspGem%d" % k, q + d * 0.005, 0.008, K["gold_d"], body))
    return parts


def paladin_arm(K, src, body, s):
    """Braços do paladino: o braçal e a cotoveleira do cavaleiro branco com os frisos em ouro, mais o braçal de
    cima (do pé da ombreira ao cotovelo) com duas lâminas e debrum de ouro."""
    from mathutils.bvhtree import BVHTree
    sn = "L" if s > 0 else "R"
    parts = wknight_arm(K, src, body, s)
    for o in parts:                    # frisos e bordas em ouro
        if any(o.name.startswith(n) for n in ("VambraceRim", "VambraceBand", "CouterRim", "CouterWingRim", "CouterBoss")):
            o.data.materials.clear()
            o.data.materials.append(K["gold"])
    tmp = cb_piece(src, "ArmProbeU" + sn, lambda c, b, n: b.startswith("Arm") and c.x * s > 0)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
    bpy.data.objects.remove(tmp, do_unlink=True)
    L1, L2, at, coords, ring = _gb_arm_frame(s)
    NP = 32
    for k, (t0, t1) in enumerate(((0.5, 0.74), (0.7, 0.93))):
        rings, dirs = [], []
        for i in range(7):
            t = t0 + (t1 - t0) * i / 6
            c, ax = at(t * L1)
            o = Vector((s, 0, 0))
            o = (o - ax * o.dot(ax)).normalized()
            f = ax.cross(o).normalized()
            ds = [o * math.cos(2 * math.pi * j / NP) + f * math.sin(2 * math.pi * j / NP) for j in range(NP)]
            rs = []
            for d in ds:
                h = bvh.ray_cast(c + d * 0.25, -d)
                rs.append((0.25 - h[3]) if h[0] is not None else 0.045)
            rm = sum(rs) / NP
            rs = [(rs[j - 1] + 2 * rs[j] + rs[(j + 1) % NP]) / 4 for j in range(NP)]
            add = 0.011 + 0.004 * k + 0.004 * i / 6
            rings.append([c + d * (max(r, 0.5 * (r + rm)) + add) for d, r in zip(ds, rs)])
            dirs.append(ds)
        parts.append(g_smooth_mesh("Rerebrace%s%d" % (sn, k), rings, K["plate"], body, cap_end=False, thick=0.005,
                                   outward=True))
        parts.append(g_pipe("RerebraceGold%s%d" % (sn, k), [q + d * 0.002 for q, d in zip(rings[-1], dirs[-1])], 0.0045,
                            K["gold"], body, sides=8, loop=True))
        parts.append(g_pipe("RerebraceRim%s%d" % (sn, k), [q + d * 0.002 for q, d in zip(rings[0], dirs[0])], 0.004,
                            K["plate"], body, sides=8, loop=True))
    return parts

def build_a_paladin():
    """Paladino real (tier IV). Rodada 1: tronco (couraça, faixas e cruz de ouro, gorjal com gola em pontas,
    cinto); braços e pernas com a cota escura até as próximas peças."""
    style = "a_paladin"
    P, R = g_rig(style)
    M = g_mats()
    K = paladin_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["mail"])
    g_skinned_pants(src, M["pants"])
    under, parts = paladin_torso(K, src, body)
    shoulder = paladin_pauldron(K, src, body, 1) + paladin_pauldron(K, src, body, -1)
    tas, mid = paladin_faulds(K, body)
    skirt = paladin_skirt(K, body)
    cape = paladin_cape(K, body)
    arms = paladin_arm(K, src, body, 1) + paladin_arm(K, src, body, -1)
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.008, K["mail"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 0.7),
                             (tas, "fn", _wk_tasset_w, 1.0), (mid, "fn", _wk_center_w, 1.0),
                             (skirt, "fn", _gb_skirt_w, 1.0), (cape, "fn", _pal_cape_w, 1.0),
                             (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0)])
    join_objs("Paladin", parts + shoulder + tas + mid + skirt + cape + arms)
    g_export_skinned(style)


# ------------------------------------------------------------------ primeira placa (tier II, malha lisa)
# Referência: Lara Jenn, "Armor design study". Poucas placas grandes de ferro claro, curvas e lisas: peitoral
# com quilha forte no meio e ponta em V embaixo, borda de cima virada para fora em volta do pescoço, forro de
# couro claro aparecendo nas bordas, cota escura por baixo. Sem dourado e sem capa (tier de ferro).
def firstplate_mats():
    return dict(
        plate=gm("fp_plate", "#C9CDD2", 0.35, 0.7), plate_d=gm("fp_plate_d", "#868C95", 0.45, 0.7),
        lining=gm("fp_lining", "#C2A47C", 0.9), mail=gm("fp_mail", "#2F3035", 0.65, 0.5),
        lea=gm("fp_leather", "#3A2F2A", 0.8),
    )


def firstplate_torso(K, src, body):
    """Tronco: cota escura (casca), peitoral com quilha forte e ponta em V até a barriga, borda de cima virada
    para fora, costal, gorjal baixo de placa; forro de couro claro em todas as bordas e rebites nos cantos.
    Devolve (casca, peças)."""
    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52

    def mail_keep(c, b, n):            # cota desce pela virilha e pelo alto das coxas (aparece entre as placas)
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.7 <= c.z < 1.52
    under = cb_piece(src, "Mail", mail_keep, 0.006, K["mail"])
    g_subdiv(under, 2)
    parts = []
    A = 1.32

    def top_z(a):                      # decote redondo, sobe para os ombros
        return 1.475 - 0.05 * math.cos(a) ** 2 - 0.06 * (abs(a) / A) ** 4

    def bot_z(a):                      # ponta em V no meio, sobe para os lados
        return 1.0 + 0.14 * min(1.0, abs(a) / 1.15) ** 1.1

    def breast(u, v, out=0.0):
        a = -A + 2 * A * v
        z = top_z(a) + (bot_z(a) - top_z(a)) * u
        return wk_plate_pt(a, z, 0.03 + out, keel=0.12, fr_max=1.03)   # liso, sem marcar o peitoral
    bp, br = _wk_plate("Breastplate", breast, 18, 40, K["plate"], body)
    parts.append(bp)
    # borda: forro de couro por baixo (cordão largo) e a placa dobrada por cima (cordão fino de ferro)
    side_l = [r[0] for r in br]
    side_r = [r[-1] for r in br]
    outline = br[0] + side_r[1:] + br[-1][::-1][1:] + side_l[::-1][1:-1]
    parts.append(g_pipe("BreastLining", outline, 0.0085, K["lining"], body, sides=8, loop=True))
    parts.append(g_pipe("BreastRim", [q + Vector((q.x, q.y, 0)).normalized() * 0.004 for q in outline], 0.0045,
                        K["plate"], body, sides=8, loop=True))
    # borda de cima virada para fora: tira curva em volta do decote
    lip = []
    for j in range(31):
        v = 0.2 + 0.6 * j / 30         # só no decote: nas pontas a ombreira cobre (e a aba ficava em pé)
        q = breast(0.0, v)
        a = -A + 2 * A * v
        d = Vector((math.sin(a), -math.cos(a), 0))
        lip.append([q + d * 0.003 + Vector((0, 0, 0.002)), q + d * 0.03 + Vector((0, 0, 0.022))])
    rings = [[p[0] for p in lip], [p[1] for p in lip]]
    parts.append(g_smooth_mesh("BreastLip", rings, K["plate"], body, cap_end=False, closed=False, thick=0.004,
                               outward=True))
    parts.append(g_pipe("BreastLipRim", rings[1], 0.004, K["lining"], body, sides=6))
    # quilha: aresta marcada no meio, do decote à ponta
    parts.append(g_pipe("BreastKeel", [breast(u, 0.5, 0.002) for u in (0.08, 0.35, 0.65, 0.95)], 0.0026, K["plate_d"],
                        body, sides=6))
    for v in (0.2, 0.8):               # rebites nos lados de baixo
        for u in (0.6, 0.8):
            q = breast(u, v, 0.004)
            parts.append(g_bead("BreastRivet%d_%d" % (int(v * 10), int(u * 10)), q, 0.005, K["plate_d"], body))
    # ---- costal
    B = math.pi - 1.25

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.49 - 0.07 * abs(2 * v - 1) ** 4
        z = zt + (1.0 - zt) * u            # desce até o cinto: as costas ficam fechadas
        return wk_plate_pt(a, z, 0.018)
    bk, bkr = _wk_plate("Backplate", back, 14, 30, K["plate"], body)
    parts.append(bk)
    bo = bkr[0] + [r[-1] for r in bkr[1:]] + bkr[-1][::-1][1:] + [r[0] for r in bkr[::-1][1:-1]]
    parts.append(g_pipe("BackLining", bo, 0.008, K["lining"], body, sides=8, loop=True))
    # ---- gorjal baixo: colar de placa em volta do pescoço, alto atrás (protege a nuca)
    def ring(z, rx, ry, y0=0.012, n=36):
        return [Vector((math.sin(2 * math.pi * j / n) * rx, y0 - math.cos(2 * math.pi * j / n) * ry, z))
                for j in range(n)]
    gor = []
    for k, (z0, rx, ry) in enumerate(((1.45, 0.128, 0.114), (1.49, 0.106, 0.096), (1.525, 0.094, 0.087))):
        r = ring(z0, rx, ry)
        gor.append([q + Vector((0, 0, 0.03 * max(0.0, math.cos(2 * math.pi * j / 36)) * (k / 2)))
                    for j, q in enumerate(r)])
    parts.append(g_smooth_mesh("Gorget", gor, K["plate"], body, cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("GorgetRim", gor[-1], 0.005, K["lining"], body, sides=8, loop=True))
    # ---- cinto de couro escuro sobre a cota, com fivela de ferro
    from mathutils.bvhtree import BVHTree
    ub = BVHTree.FromPolygons([v.co.copy() for v in under.data.vertices], [tuple(p.vertices) for p in under.data.polygons])
    N = 48

    def on_under(a, z, out):
        d = Vector((math.sin(a), -math.cos(a), 0))
        h = ub.ray_cast(Vector((0, 0, z)) + d * 0.6, -d)[0]
        return (h if h is not None else Vector((0, 0, z)) + d * 0.15) + d * out
    belt = [[on_under(2 * math.pi * j / N, z, out) for j in range(N)]
            for z, out in ((0.955, 0.004), (0.96, 0.012), (0.995, 0.012), (1.0, 0.004))]
    parts.append(g_smooth_mesh("Belt", belt, K["lea"], body, cap_end=False, outward=True))
    bc = on_under(0.0, 0.978, 0.014)
    parts.append(g_pipe("Buckle", [bc + Vector((x, 0, y)) for x, y in ((-0.018, 0.016), (0.018, 0.016), (0.018, -0.016),
                                                                       (-0.018, -0.016))], 0.0038, K["plate_d"], body,
                        sides=8, loop=True))
    return under, parts



def firstplate_pauldron(K, src, body, s):
    """Ombreira da primeira placa: copa grande, lisa e redonda que cobre o ombro e o alto do braço, e uma
    lâmina embaixo; forro de couro claro em todas as bordas e um
    rebite na frente."""
    sn = "L" if s > 0 else "R"
    lames = [(0.05, 2.35, 1.9, 0.055, 0.0), (2.2, 3.0, 2.0, 0.044, 0.004)]
    parts = []
    for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, s, lames, phis=32, rows=10, cap=0.006, taper=True)):
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), rings, K["plate"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        n = len(rings[0])
        edge = [rings[-1][j] + dirs[-1][j] * 0.002 for j in range(n)]
        if k == 0:                     # na copa as pontas da barra sobem até o topo: o debrum para antes
            loop = edge[4:-4]
        else:
            ends = [[r[side] + d[side] * 0.002 for r, d in zip(rings, dirs)] for side in (0, n - 1)]
            loop = ends[0][::-1] + edge[1:-1] + ends[1]
        parts.append(g_pipe("PauldronLining%s%d" % (sn, k), loop, 0.008, K["lining"], body, sides=8))
        parts.append(g_pipe("PauldronRim%s%d" % (sn, k), [q + (q - C).normalized() * 0.004 for q in loop], 0.0042,
                            K["plate"], body, sides=8))
        if k == 0:
            jf = int(n * 0.82)         # rebite na frente
            q = rings[len(rings) // 2][jf] + dirs[len(rings) // 2][jf] * 0.004
            parts.append(g_bead("PauldronRivet" + sn, q, 0.006, K["plate_d"], body))
    return parts


def firstplate_faulds(K, body):
    """Escarcelas da primeira placa: em cada lado do quadril uma placa grande e comprida que desce do cinto
    até o meio da coxa, curvada com o corpo e com a barra em ponta para fora; na frente uma placa curta em
    escudo sob a ponta do peitoral. Forro de couro claro nas bordas, rebites no alto. Devolve (laterais, frente)."""
    tas, mid = [], []
    for sn, s in (("L", 1), ("R", -1)):
        A0, A1 = 0.5, 1.5

        def lame(u, v):
            a0 = A0 + 0.18 * u ** 1.3           # afina para baixo pelo lado de dentro: abre a frente
            a = (a0 + (A1 - a0) * v) * s
            h = 0.23 + 0.05 * v ** 1.5          # mais comprida do lado de fora, barra em diagonal
            z = 0.995 - h * u
            return _pal_hip_pt(a, z, 0.02 + 0.03 * u)
        ob, rr = _wk_plate("Tasset" + sn, lame, 10, 22, K["plate"], body, thick=0.006)
        tas.append(ob)
        edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
        tas.append(g_pipe("TassetLining" + sn, edge, 0.0075, K["lining"], body, sides=8))
        tas.append(g_pipe("TassetRim" + sn, [q + Vector((q.x, q.y, 0)).normalized() * 0.004 for q in edge], 0.004,
                          K["plate"], body, sides=8))
        tas.append(g_pipe("TassetRidge" + sn, [lame(u, 0.55) + Vector((lame(u, 0.55).x, lame(u, 0.55).y, 0)).normalized() * 0.002
                                               for u in (0.1, 0.4, 0.7, 0.95)], 0.0024, K["plate_d"], body, sides=6))
        for v in (0.15, 0.85):
            q = lame(0.08, v)
            tas.append(g_bead("TassetRivet%s%d" % (sn, int(v * 10)), q + Vector((q.x, q.y, 0)).normalized() * 0.005,
                              0.0055, K["plate_d"], body))
    AF = 0.3

    def front(u, v):
        a = -AF + 2 * AF * v
        x = abs(2 * v - 1)
        z = 1.005 - (0.1 - 0.06 * x ** 1.5) * u
        return _pal_hip_pt(a, z, 0.032 + 0.008 * u)
    fp, fr = _wk_plate("FrontPlate", front, 6, 16, K["plate"], body, thick=0.006)
    mid.append(fp)
    fe = [r[0] for r in fr] + fr[-1][1:] + [r[-1] for r in fr][::-1][1:]
    mid.append(g_pipe("FrontPlateLining", fe, 0.007, K["lining"], body, sides=8))
    return tas, mid



def firstplate_culet(K, body):
    """Culote: duas lâminas atrás, do cinto até a curva do glúteo, cada uma por cima da de baixo, forro de couro
    claro na barra e rebites nas pontas (fecha as costas abaixo do costal)."""
    out = []
    A = 1.45
    for k in range(2):
        zt = 1.0 - 0.075 * k

        def lame(u, v, zt=zt, k=k):
            a = math.pi - A + 2 * A * v
            z = zt - 0.085 * u
            return _pal_hip_pt(a, z, 0.026 + 0.004 * k + 0.012 * u)
        ob, rr = _wk_plate("Culet%d" % k, lame, 5, 26, K["plate"], body, thick=0.006)
        out.append(ob)
        edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
        out.append(g_pipe("CuletLining%d" % k, edge, 0.0065, K["lining"], body, sides=8))
        for v in (0.06, 0.94):
            q = lame(0.4, v)
            out.append(g_bead("CuletRivet%d_%d" % (k, int(v * 10)), q + Vector((q.x, q.y, 0)).normalized() * 0.005,
                              0.005, K["plate_d"], body))
    return out


def firstplate_cuisses(K, src, body):
    """Coxeiras: casca de placa em volta de cada coxa inteira (do lado de dentro termina mais baixo, longe da virilha), do quadril até logo acima do joelho, alisada e com o
    forro de couro claro em volta (a casca sai do corpo com pesos, então dobra com a perna). Devolve
    (cascas, debruns)."""
    shells, trims = [], []
    knee_z = CB_J["knee"].z
    for sn, s in (("L", 1), ("R", -1)):
        def keep(c, b, n, s=s):
            hip = cb_mirror(CB_J["hip"], s)
            d = Vector((c.x - hip.x, c.y - hip.y, 0)).normalized()
            # só a frente e o lado de fora da coxa (o lado de dentro some entre as pernas)
            return b.startswith("Leg") and c.x * s > 0 and knee_z + 0.03 < c.z < (0.77 if d.x * s > -0.3 else 0.7)
        sh = cb_piece(src, "Cuisse" + sn, keep, 0.016, K["plate"])
        g_subdiv(sh, 2)
        shells.append(sh)
        trims += g_border_pipes(sh, "CuisseLining" + sn, 0.0065, K["lining"], body, smooth=6, step=0.01)
    return shells, trims

def build_a_firstplate():
    """Primeira placa (tier II). Rodada 1: tronco (peitoral com quilha, costal, gorjal, cinto); braços e pernas
    com a cota escura até as próximas peças."""
    style = "a_firstplate"
    P, R = g_rig(style)
    M = g_mats()
    K = firstplate_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["mail"])
    g_skinned_pants(src, M["pants"])
    under, parts = firstplate_torso(K, src, body)
    shoulder = firstplate_pauldron(K, src, body, 1) + firstplate_pauldron(K, src, body, -1)
    KA = dict(K, gold=K["lining"])     # braços do paladino com as bordas em couro claro no lugar do ouro
    arms = paladin_arm(KA, src, body, 1) + paladin_arm(KA, src, body, -1)
    tas, mid = firstplate_faulds(K, body)
    cuis, cuis_trim = firstplate_cuisses(K, src, body)
    culet = firstplate_culet(K, body)
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.008, K["mail"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 0.7),
                             (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (tas, "fn", _wk_tasset_w, 1.0), (mid, "fn", _wk_center_w, 1.0),
                             (cuis_trim, "vert", ("LegL", "LegR"), 1.0), (culet, "fn", _gb_skirt_w, 1.0)])
    join_objs("FirstPlate", parts + shoulder + arms + tas + mid + cuis_trim + culet)
    g_export_skinned(style)


# ------------------------------------------------------------------ escamas de brasa (endgame, malha lisa)
# Referência: Sleeping Thunder, armadura de escamas negras com veias vermelhas acesas. Faixas de escama em V
# (chevron) da gola à cintura, na frente e atrás, com a brasa aparecendo na fresta entre uma faixa e a de baixo;
# gema em chama no esterno; gola alta de escamas. A brasa é material com emissão (vai pulsar pelo GearFx).
def ember_mats():
    return dict(
        scale=gm("ds_scale", "#2A2831", 0.55, 0.35), scale_d=gm("ds_scale_d", "#131217", 0.65, 0.3),
        under=gm("ds_under", "#17161B", 0.85), lea=gm("ds_leather", "#1E1B1E", 0.8),
        cloth=gm("ds_cloth", "#201E26", 0.9),
        vein=mat("ds_vein_glow_flat", hexc("#7E1512"), 0.5, 0.0, emit=hexc("#8A0C08"), strength=0.3),
        gem=mat("ds_gem_glow_flat", hexc("#FF8A3A"), 0.3, 0.0, emit=hexc("#FF5A1A"), strength=2.2),
    )


def g_surface_leaf(name, bvh, guide, half_w, material, parent, n=10, off0=0.012, lift=0.02, arch=0.006, thick=0.004,
                   stripe=None):
    """Escama em folha deitada sobre o corpo: a linha do meio é guide(s) (s = 0 raiz .. 1 ponta) projetada na
    superfície mais próxima (bvh do corpo), a off0 dela e levantando até off0 + lift na ponta; half_w(s) dá a
    meia largura; a seção é arqueada (arch)."""
    cs, ns = [], []
    for i in range(n):
        t = i / (n - 1)
        loc, nrm, _, _ = bvh.find_nearest(guide(t))
        cs.append(loc)
        ns.append(nrm)
    for _ in range(3):                 # alisa a linha e as normais (a projeção no corpo vem em degraus)
        cs = [cs[0]] + [(cs[i - 1] + cs[i] * 2 + cs[i + 1]) / 4 for i in range(1, n - 1)] + [cs[-1]]
        ns = [ns[0]] + [(ns[i - 1] + ns[i] * 2 + ns[i + 1]).normalized() for i in range(1, n - 1)] + [ns[-1]]
    ns[-1] = ns[-2]
    cs = [c + nr * (off0 + lift * (i / (n - 1)) ** 2) for i, (c, nr) in enumerate(zip(cs, ns))]
    rows = []
    for i in range(n):
        tg = (cs[min(i + 1, n - 1)] - cs[max(i - 1, 0)]).normalized()
        w = tg.cross(ns[i]).normalized()
        hw = max(0.0012, half_w(i / (n - 1)))
        rows.append([cs[i] + w * hw * x + ns[i] * arch * (1 - x * x) for x in (-1.0, -0.5, 0.0, 0.5, 1.0)])
    leaf = g_smooth_mesh(name, rows, material, parent, cap_end=False, closed=False, thick=thick, outward=True)
    if stripe is None:
        return leaf
    # faixa de brasa larga ao longo da folha, na metade de cima dela (a brasa que aparece sob a folha de cima)
    srows = []
    for i in range(1, n - 1):
        tg = (cs[min(i + 1, n - 1)] - cs[max(i - 1, 0)]).normalized()
        w = tg.cross(ns[i]).normalized()
        if w.z < 0:
            w = -w
        hw = max(0.0012, half_w(i / (n - 1)))
        srows.append([cs[i] + w * hw * x + ns[i] * (arch * (1 - x * x) + 0.001) for x in (0.12, 0.4, 0.68)])
    return [leaf, g_smooth_mesh(name + "Glow", srows, stripe, parent, cap_end=False, closed=False, outward=True)]


def ember_torso(K, src, body):
    """Tronco das escamas de brasa. Por baixo de tudo, um fundo de brasa aceso (casca do corpo) da cintura à
    gola e por cima dos ombros. Sobre ele, escamas escuras: no peito e nas costas, quatro fileiras em V de
    placas grandes (o vermelho aparece em faixas largas entre as fileiras); nos ombros, um leque de escamas
    em folha que sai da gema (na frente) e da espinha (atrás) e passa da ponta do ombro, com o vermelho entre
    uma folha e outra; a gema em chama fica no esterno, num engaste escuro cercado de escamas pequenas.
    Devolve (casca, peças rígidas, escamas dos ombros)."""
    from mathutils.bvhtree import BVHTree

    def keep(c, b, n):                 # até o quadril: abaixo disso a calça com pele tem a mesma folga (serrilhava)
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.9 <= c.z < 1.52

    under = cb_piece(src, "Under", keep, 0.006, K["under"])
    g_subdiv(under, 2)
    parts, mantle = [], []
    NB, Z0, Z1 = 5, 1.43, 1.0          # a primeira fileira fica logo abaixo da gema (só no meio da frente)
    step = (Z0 - Z1) / NB
    VD = 0.1                           # V fundo e reto (a ponta desce no meio da frente e das costas)

    def band_z(k, a):
        x = min(1.0, abs(math.sin(a)) / 0.85)
        return Z0 - step * k - VD * (1 - x)

    # ---- fundo em brasa: da cintura à gola, e o alto dos braços (sob as escamas dos ombros)
    def ember_keep(c, b, n):
        if b.startswith("Arm"):
            sd = 1 if c.x > 0 else -1
            return _cb_t(c, cb_mirror(CB_J["shoulder"], sd), cb_mirror(CB_J["elbow"], sd)) < 0.34
        a = math.atan2(c.x, -c.y)
        return keep(c, b, n) and band_z(NB, a) - 0.01 < c.z < 1.5
    bed = cb_piece(src, "EmberBed", ember_keep, 0.011, K["vein"])
    g_subdiv(bed, 2)
    # ---- peito e costas: fileiras em V de placas grandes (duas por lado na frente), cada placa encosta a raiz
    #      no fundo e levanta a barra por cima da fileira de baixo; entre as fileiras fica a faixa de brasa
    NSC = 8
    for k in range(NB):
        for m in range(NSC):
            a0 = -math.pi + 2 * math.pi * m / NSC + 0.012
            span = 2 * math.pi / NSC - 0.024
            am = a0 + span / 2
            aw = abs(math.atan2(math.sin(am), math.cos(am)))
            if (k == 0 and aw > 0.8) or (k == 1 and 1.15 < aw < 2.0):
                continue               # fileira de cima só no peito; axila fica sob o braço

            def scale(u, v, k=k, a0=a0, span=span):
                a = a0 + span * v
                top = band_z(k, a) + 0.004
                x = 2 * v - 1
                h = step * (0.6 + 0.1 * (1 - abs(x) ** 1.5))
                z = top - h * u
                puff = 0.008 * math.sin(math.pi * min(1.0, u * 1.1)) * (1 - 0.4 * x * x)
                return wk_plate_pt(a, z, 0.008 + puff + 0.012 * u, fr_max=1.03)
            rows = [[scale(i / 5, j / 10) for j in range(11)] for i in range(6)]
            parts.append(g_smooth_mesh("Scale%d_%d" % (k, m), rows, K["scale"], body, cap_end=False, closed=False,
                                       thick=0.005, outward=True))
    # ---- placas lisas das omoplatas (acima das fileiras, nas costas)
    for sn, sg in (("L", 1), ("R", -1)):
        def blade(u, v, sg=sg):
            a = math.pi - sg * (0.06 + 0.95 * v)
            top = 1.455 - 0.05 * v
            bot = band_z(1, a) - 0.004
            return wk_plate_pt(a, top + (bot - top) * u, 0.009 + 0.011 * u + 0.006 * math.sin(math.pi * u))
        rows = [[blade(i / 6, j / 8) for j in range(9)] for i in range(7)]
        parts.append(g_smooth_mesh("BackBlade" + sn, rows, K["scale"], body, cap_end=False, closed=False,
                                   thick=0.005, outward=True))
    # ---- gola alta de escama
    def ring(z, rx, ry, y0=0.012, n=36):
        return [Vector((math.sin(2 * math.pi * j / n) * rx, y0 - math.cos(2 * math.pi * j / n) * ry, z))
                for j in range(n)]
    col = [ring(1.43, 0.13, 0.115), ring(1.48, 0.104, 0.094), ring(1.53, 0.09, 0.083), ring(1.575, 0.088, 0.082)]
    parts.append(g_smooth_mesh("Collar", col, K["scale"], body, cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("CollarRim", col[-1], 0.004, K["scale_d"], body, sides=6, loop=True))
    # ---- gema em chama no esterno, em engaste escuro, cercada de escamas pequenas
    mw = src.matrix_world
    bvh = BVHTree.FromPolygons([mw @ v.co for v in src.data.vertices], [tuple(p.vertices) for p in src.data.polygons])
    g0, gn, _, _ = bvh.find_nearest(wk_plate_pt(0.0, 1.405, 0.02, fr_max=1.03))
    RT, UP = Vector((1, 0, 0)), Vector((0, 0, 1))
    flame = [(0.0, 0.046), (0.015, 0.016), (0.02, -0.008), (0.0, -0.034), (-0.02, -0.008), (-0.015, 0.016)]
    parts.append(g_plate("ChestGemSeat", [(x * 1.45, y * 1.35) for x, y in flame], g0 + gn * 0.024, RT, UP, 0.008,
                         K["scale_d"], body))
    parts.append(g_plate("ChestGem", flame, g0 + gn * 0.033, RT, UP, 0.01, K["gem"], body))
    for q, (deg, L, W) in enumerate(((62, 0.05, 0.014), (118, 0.05, 0.014), (22, 0.062, 0.017), (158, 0.062, 0.017),
                                     (-22, 0.066, 0.018), (202, 0.066, 0.018), (-62, 0.07, 0.016),
                                     (242, 0.07, 0.016), (270, 0.105, 0.015))):
        t = math.radians(deg)
        d = RT * math.cos(t) + UP * math.sin(t)
        parts.append(g_surface_leaf("GemScale%d" % q, bvh, lambda u, d=d, L=L: g0 + d * (0.014 + L * u),
                                    lambda u, W=W: W * (0.6 + 0.4 * min(1.0, u * 3.5)) * (1 - u ** 2.2),
                                    K["scale"], body, n=8, off0=0.014, lift=0.012, arch=0.004))
    # ---- leque curto de escamas em folha em volta da gema (frente) e no alto das costas: fica no tronco, não
    #      sobe no ombro
    b0 = bvh.find_nearest(wk_plate_pt(math.pi, 1.44, 0.02))[0]
    fans = (("F", g0 + UP * 0.012, ((60, 0.085), (34, 0.105), (12, 0.125), (-10, 0.12), (-32, 0.1))),
            ("B", b0, ((48, 0.085), (26, 0.1), (6, 0.12), (-14, 0.115))))
    for fn, org, leaves in fans:
        for sn, sg in (("L", 1), ("R", -1)):
            for q, (deg, L) in enumerate(leaves):
                t = math.radians(deg)
                d = RT * (sg * math.cos(t)) + UP * math.sin(t)
                parts += g_surface_leaf("Fan%s%s%d" % (fn, sn, q), bvh,
                                        lambda u, d=d, L=L, org=org: org + d * (0.035 + L * u),
                                        lambda u: 0.024 * (0.5 + 0.5 * min(1.0, u * 2.5)) * (1 - u ** 3.0),
                                        K["scale"], body, n=10, off0=0.02 - 0.0025 * q, lift=0.012, arch=0.006,
                                        thick=0.005, stripe=K["vein"])
    # ---- ombros: ombreira de três placas de escama empilhadas, cada uma por cima da de baixo, com a barra
    #      recortada em três pontas de folha e uma faixa de brasa ao longo
    for sn, sg in (("L", 1), ("R", -1)):
        lames = [(0.08, 1.7, 1.75, 0.04, 0.004), (1.3, 2.55, 1.9, 0.036, 0.016), (2.1, 3.35, 1.95, 0.03, 0.02)]
        for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, sg, lames, phis=30, rows=8, cap=0.006, taper=True)):
            n, nr = len(rings[0]), len(rings)

            def col(j, u, rings=rings, nr=nr):         # ponto da coluna j na fração u da altura
                x = u * (nr - 1)
                i0 = min(nr - 2, int(x))
                return rings[i0][j].lerp(rings[i0 + 1][j], x - i0)
            NL = 3
            grid = []
            for i in range(nr):
                row = []
                for j in range(n):
                    tip = abs(math.sin(math.pi * NL * j / (n - 1))) ** 1.3     # 0 entre as folhas, 1 na ponta
                    row.append(col(j, (i / (nr - 1)) * (0.5 + 0.5 * tip)))
                grid.append(row)
            mantle.append(g_smooth_mesh("ShoulderScale%s%d" % (sn, k), grid, K["scale"], body, cap_end=False,
                                        closed=False, thick=0.006, outward=True))
            glow = [[col(j, u) + dirs[min(nr - 1, int(u * (nr - 1)))][j] * 0.0012 for j in range(3, n - 3)]
                    for u in (0.2, 0.3, 0.4)]
            mantle.append(g_smooth_mesh("ShoulderGlow%s%d" % (sn, k), glow, K["vein"], body, cap_end=False,
                                        closed=False, outward=True))
    parts.append(bed)
    return under, parts, mantle


def ember_arms(K, src, body):
    """Braços das escamas de brasa. Alto do braço: placa escura (casca do corpo) com um rasgo de brasa em amêndoa
    do lado de fora. Antebraço: casca escura e escamas grandes em folha trançadas em duas colunas, com a brasa
    na costura do meio; cotoveleira redonda. Devolve as peças que seguem o braço."""
    from mathutils.bvhtree import BVHTree
    orn = []
    NP = 28
    for sn, s in (("L", 1), ("R", -1)):
        sh, el = cb_mirror(CB_J["shoulder"], s), cb_mirror(CB_J["elbow"], s)

        def arm_side(c, s=s):
            return c.x * s > 0
        up = cb_piece(src, "ArmScale" + sn, lambda c, b, n, sh=sh, el=el: b.startswith("Arm") and arm_side(c)
                      and _cb_t(c, sh, el) >= 0.3, 0.013, K["scale"])
        g_subdiv(up, 2)
        bed = cb_piece(src, "ForeShell" + sn, lambda c, b, n: b.startswith("Elbow") and arm_side(c)
                       and _cb_fore_t(c) < 0.88, 0.008, K["scale_d"])
        g_subdiv(bed, 2)
        tmp = cb_piece(src, "ArmProbe" + sn, lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow")) and arm_side(c))
        bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
        bpy.data.objects.remove(tmp, do_unlink=True)
        L1, L2, at, coords, ring = _gb_arm_frame(s)
        # rasgo de brasa em amêndoa no lado de fora do alto do braço, com moldura escura
        o = Vector((s, 0, 0))
        slit = lambda u: sh.lerp(el, 0.42 + 0.42 * u) + o * 0.2
        orn.append(g_surface_leaf("ArmSlitRim" + sn, bvh, slit, lambda u: 0.02 * math.sin(math.pi * u) ** 0.7 + 0.002,
                                  K["scale_d"], body, n=10, off0=0.014, lift=0.0, arch=0.003, thick=0.004))
        orn.append(g_surface_leaf("ArmSlit" + sn, bvh, slit, lambda u: 0.013 * math.sin(math.pi * u) ** 0.8 + 0.001,
                                  K["vein"], body, n=10, off0=0.023, lift=0.0, arch=0.002, thick=0.003))
        # antebraço trançado: duas colunas de escamas grandes em folha, uma de cada lado da linha de fora, que
        # descem em diagonal para o meio e se encaixam alternadas (cada uma cobre a raiz da seguinte); na costura
        # do meio aparece a brasa. As escamas são grades limpas em coordenadas do braço (posição no eixo, ângulo),
        # sobre o raio médio do antebraço: projetar na malha amassava as folhas em volta do braço fino.
        def arm_pt(pos, ph):
            c, ax = at(min(pos, L1 + 0.96 * L2))
            oo = (o - ax * o.dot(ax)).normalized()
            f = ax.cross(oo).normalized()
            return c + (oo * math.cos(ph) + f * math.sin(ph)) * 0.2
        rcache = {}

        def rmean(pos):
            k = round(pos, 3)
            if k not in rcache:
                c, ax = at(min(pos, L1 + 0.96 * L2))
                oo = (o - ax * o.dot(ax)).normalized()
                f = ax.cross(oo).normalized()
                rs = []
                for m in range(12):
                    d = oo * math.cos(m * math.pi / 6) + f * math.sin(m * math.pi / 6)
                    h = bvh.ray_cast(c + d * 0.25, -d)
                    rs.append((0.25 - h[3]) if h[0] is not None else 0.04)
                rcache[k] = sum(rs) / 12
            return rcache[k]

        def surf(pos, ph, out):
            pos = min(max(pos, L1 - 0.02), L1 + 0.95 * L2)
            c, ax = at(pos)
            oo = (o - ax * o.dot(ax)).normalized()
            f = ax.cross(oo).normalized()
            return c + (oo * math.cos(ph) + f * math.sin(ph)) * (rmean(pos) + out)
        T0, T1, NR, RA = 0.02, 0.93, 5, 0.045
        step = (T1 - T0) * L2 / (NR + 0.75)  # a última escama (1,75 passo) ainda cabe antes do pulso
        seam = [[surf(L1 + (T0 + 0.05 + (T1 - T0 - 0.09) * i / 14) * L2, ph, 0.0105) for ph in (-1.2, -0.6, 0.0, 0.6, 1.2)]
                for i in range(15)]
        orn.append(g_smooth_mesh("ForeSeam" + sn, seam, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                                 outward=True))
        for k in range(NR):
            for q, sg in enumerate((1, -1)):
                p0 = L1 + T0 * L2 + step * k - 0.012       # os dois lados na mesma altura: o par forma um V

                def center(u, p0=p0, sg=sg):       # linha do meio da escama em (posição, ângulo)
                    return p0 + step * 1.75 * u, sg * (2.2 - 2.12 * u ** 0.9)
                def grid(dpos, out0, lift, arch, wk=1.0):
                    rows = []
                    for i in range(11):
                        u = i / 10
                        pa, pha = center(max(0.0, u - 0.05))
                        pb, phb = center(min(1.0, u + 0.05))
                        tp, tph = pb - pa, (phb - pha) * RA
                        ln = math.hypot(tp, tph) or 1.0
                        np_, nph = -tph / ln, tp / ln                   # perpendicular no plano desenrolado
                        pc, phc = center(u)
                        # larga na raiz (as escamas se cobrem no lado do braço) e fina para a ponta (no meio sobra
                        # um V de brasa entre um par e o seguinte)
                        hw = (0.03 - 0.021 * u) * (0.7 + 0.3 * min(1.0, u * 4.0)) * (1 - u ** 5.0) ** 0.7 * wk
                        hw = max(hw, 0.0015)
                        rows.append([surf(pc + dpos + np_ * hw * x, phc + nph * hw * x / RA,
                                          out0 + lift * u + arch * (1 - x * x))
                                     for x in (-1.0, -0.6, -0.2, 0.2, 0.6, 1.0)])
                    return rows
                rows = grid(0.0, 0.011, 0.015, 0.007)
                nm = "ForeScale%s%d_%d" % (sn, k, q)
                orn.append(g_smooth_mesh(nm, rows, K["scale"], body, cap_end=False, closed=False, thick=0.005,
                                         outward=True))
                # contorno escuro da escama e a brasa por baixo da borda dela (cópia deslocada para a ponta)
                border = [r[0] for r in rows] + rows[-1][1:-1] + [r[-1] for r in rows][::-1]
                orn.append(g_pipe(nm + "Edge", border, 0.0024, K["scale_d"], body, sides=6, loop=True))
        # cotoveleira: escama redonda grande sobre o cotovelo
        orn.append(g_surface_leaf("ElbowScale" + sn, bvh, lambda u: arm_pt(L1 - 0.07 + 0.14 * u, 0.0) + Vector((0, 0.1, 0)),
                                  lambda u: 0.04 * math.sin(math.pi * (0.12 + 0.8 * u)) ** 0.6,
                                  K["scale"], body, n=9, off0=0.014, lift=0.004, arch=0.012, thick=0.005))
    return orn


def ember_fringe(K, body):
    """Franja da cintura: escamas grandes em folha que pendem do fim do tronco e abrem para fora, em duas
    camadas desencontradas (a de cima mais curta), em toda a volta menos no meio da frente (onde a saia abre);
    atrás, a folha do meio é mais comprida. Escuras, sem brasa, cada uma com o contorno marcado."""
    out = []
    N = 12
    for layer, (L0, zt, off0, wid) in enumerate(((0.19, 1.0, 0.02, 0.062), (0.12, 1.03, 0.032, 0.054))):
        for m in range(N):
            a = 2 * math.pi * (m + 0.5 * layer) / N
            aw = abs(math.atan2(math.sin(a), math.cos(a)))
            if aw < 0.4:
                continue                       # meio da frente: aberto
            L = L0 * (1.25 if aw > 2.9 else 1.0) * (1.0 + 0.15 * abs(math.sin(a)))

            def leaf(u, x, a=a, L=L, zt=zt, off0=off0, wid=wid):
                hw = wid * (0.7 + 0.3 * min(1.0, u * 4.0)) * (1 - u ** 3.0) ** 0.8
                z = zt - L * u
                q = _pal_hip_pt(a + hw * x / 0.17, z, off0 + 0.05 * u ** 1.3 + 0.008 * (1 - x * x))
                return q
            rows = [[leaf(i / 9, x) for x in (-1.0, -0.6, -0.2, 0.2, 0.6, 1.0)] for i in range(10)]
            nm = "Fringe%d_%d" % (layer, m)
            out.append(g_smooth_mesh(nm, rows, K["scale"], body, cap_end=False, closed=False, thick=0.005,
                                     outward=True))
            border = [r[0] for r in rows] + rows[-1][1:-1] + [r[-1] for r in rows][::-1]
            out.append(g_pipe(nm + "Edge", border, 0.0024, K["scale_d"], body, sides=6, loop=True))
            out.append(g_pipe(nm + "Rib", [leaf(u, 0.0) + Vector((0, 0, 0)) for u in (0.08, 0.35, 0.65, 0.92)], 0.002,
                              K["scale_d"], body, sides=6))
    return out


def ember_skirt(K, body):
    """Saia longa das escamas de brasa: pano negro do quadril ao tornozelo em duas metades, aberta na frente (as
    pernas aparecem) e fechada atrás em repouso; barra e bordas da frente em brasa, losangos de brasa nas
    costas (um grande no meio, dois menores acima e abaixo) e uma fileira de losangos pequenos junto de cada
    borda da frente. Devolve as peças (pesos da saia)."""
    Z0, Z1 = 0.995, 0.17
    out = []
    cloth = K["cloth"]

    def pt(a, t, add=0.0):
        z = Z0 - (Z0 - Z1) * t
        fold = (0.016 * math.sin(7 * a + 0.4) + 0.006 * math.sin(17 * a)) * min(1.0, t * 2.5)
        return _pal_hip_pt(a, z, 0.006 + 0.012 * t + fold + add)

    def fo(t):                         # meia abertura da frente
        return 0.42 + 0.2 * t
    rows, NC = 20, 36
    for sn, s in (("L", 1), ("R", -1)):
        def ga(j, t, s=s):
            return (fo(t) + (math.pi - fo(t)) * j / NC) * s
        grid = [[pt(ga(j, i / rows), i / rows) for j in range(NC + 1)] for i in range(rows + 1)]
        out.append(g_smooth_mesh("Skirt" + sn, grid, cloth, body, cap_end=False, closed=False, thick=0.005,
                                 outward=True))
        # barra de brasa (faixa) e borda da frente
        hem = [[pt(ga(j, t), t, 0.002) for j in range(NC + 1)] for t in (0.955, 0.972, 0.99)]
        out.append(g_smooth_mesh("SkirtHem" + sn, hem, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                                 outward=True))
        edge = [[pt((fo(t) + da) * s, t, 0.002) for da in (0.0, 0.03, 0.06)] for t in (i / rows for i in range(2, rows + 1))]
        out.append(g_smooth_mesh("SkirtEdge" + sn, edge, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                                 outward=True))

        # ---- desenhos de brasa sobre o pano. Coordenadas do desenho: x = distância horizontal (m) a partir da
        #      costura das costas ("B") ou da borda da frente ("F"), t = altura na saia (0 cintura .. 1 barra)
        H = Z0 - Z1

        def Rt(t):
            return 0.17 + 0.1 * t

        def at_(mode, x, t, s=s):
            a = (math.pi - x / Rt(t)) if mode == "B" else (fo(t) + x / Rt(t))
            return pt(a * s, min(max(t, 0.02), 0.995), 0.002)

        def stroke(nm, mode, pts, w=0.0042):
            """Traço: linha curva pelos pontos (x, t), mais fina nas pontas."""
            sp = g_spline([Vector((x, t * H, 0)) for x, t in pts], max(8, len(pts) * 7))
            rows = []
            for k, q in enumerate(sp):
                tg = (sp[min(k + 1, len(sp) - 1)] - sp[max(k - 1, 0)]).normalized()
                pr = Vector((-tg.y, tg.x, 0))
                ww = w * (0.35 + 0.65 * math.sin(math.pi * k / (len(sp) - 1)) ** 0.5)
                rows.append([at_(mode, max(0.0, q.x + pr.x * ww * sg), (q.y + pr.y * ww * sg) / H) for sg in (-1, 1)])
            out.append(g_smooth_mesh("%s%s" % (nm, sn), rows, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                                     outward=True))

        def almond(nm, mode, xc, tc, hw, ht, seam=False):
            """Amêndoa cheia (olho/folha de chama); seam = metade encostada na costura do meio."""
            rows = []
            for k in range(9):
                v = k / 8 * 2 - 1
                w = hw * math.cos(v * math.pi / 2) ** 1.2
                xs = (0.0, w / 2, w) if seam else (xc - w, xc, xc + w)
                rows.append([at_(mode, max(0.0, x), tc + ht * v) for x in xs])
            out.append(g_smooth_mesh("%s%s" % (nm, sn), rows, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                                     outward=True))

        def dots(nm, mode, pts, r=0.006):
            for k, (x, t) in enumerate(pts):
                almond("%s%d" % (nm, k), mode, x, t, r, r / H)
        # costas, eixo do meio: losangos pequenos, olho grande com contorno, olho pequeno e linhas até a barra
        almond("BkEye", "B", 0, 0.585, 0.022, 0.085, seam=True)
        stroke("BkEyeRim", "B", [(0.004, 0.42), (0.02, 0.47), (0.048, 0.58), (0.03, 0.67), (0.006, 0.74)])
        almond("BkEyeLo", "B", 0, 0.845, 0.012, 0.045, seam=True)
        stroke("BkEyeLoRim", "B", [(0.006, 0.75), (0.03, 0.83), (0.022, 0.9), (0.03, 0.975)])
        stroke("BkAxis", "B", [(0.004, 0.2), (0.005, 0.3), (0.004, 0.41)], 0.004)
        almond("BkDiaHi", "B", 0, 0.235, 0.011, 0.028, seam=True)
        almond("BkDiaMid", "B", 0, 0.34, 0.013, 0.034, seam=True)
        # costas, lado: rasgo de brasa na cintura, losango vazado, linhas que abrem em chamas até a barra
        almond("BkSlash", "B", 0.155, 0.12, 0.012, 0.1)
        dots("BkDotHi", "B", [(0.195, 0.25), (0.2, 0.29)])
        stroke("BkDiaA", "B", [(0.215, 0.33), (0.245, 0.375), (0.215, 0.42), (0.185, 0.375), (0.215, 0.33)], 0.003)
        almond("BkDiaIn", "B", 0.215, 0.375, 0.008, 0.022)
        stroke("BkRayOut", "B", [(0.225, 0.42), (0.275, 0.52), (0.31, 0.6)])
        stroke("BkRayIn", "B", [(0.205, 0.42), (0.17, 0.5), (0.13, 0.58)])
        dots("BkDotMid", "B", [(0.12, 0.6), (0.112, 0.63), (0.105, 0.66)], 0.005)
        stroke("BkFlameA", "B", [(0.31, 0.6), (0.27, 0.74), (0.275, 0.88), (0.3, 0.975)])
        stroke("BkFlameB", "B", [(0.31, 0.62), (0.335, 0.78), (0.325, 0.9), (0.34, 0.975)])
        stroke("BkFlameC", "B", [(0.1, 0.68), (0.14, 0.78), (0.15, 0.9), (0.13, 0.975)])
        stroke("BkFlameD", "B", [(0.205, 0.7), (0.235, 0.82), (0.22, 0.975)])
        almond("BkLeaf", "B", 0.285, 0.83, 0.01, 0.05)
        # frente: gota e riscos junto da cintura, pontos, e embaixo as curvas que saem da borda e enrolam
        almond("FrDrop", "F", 0.035, 0.07, 0.007, 0.03)
        stroke("FrTickA", "F", [(0.03, 0.13), (0.07, 0.19), (0.115, 0.225)])
        stroke("FrTickB", "F", [(0.04, 0.14), (0.055, 0.22), (0.06, 0.31)])
        dots("FrDot", "F", [(0.062, 0.34), (0.066, 0.375), (0.07, 0.41)], 0.005)
        stroke("FrSweep", "F", [(0.21, 0.6), (0.14, 0.7), (0.06, 0.78), (0.03, 0.8)])
        stroke("FrCurl", "F", [(0.05, 0.785), (0.1, 0.84), (0.15, 0.84), (0.17, 0.81)])
        dots("FrCurlDot", "F", [(0.185, 0.8), (0.2, 0.79)], 0.004)
        stroke("FrArc", "F", [(0.04, 0.8), (0.055, 0.88), (0.1, 0.94), (0.15, 0.965)])
    return out


def g_limb_braid(prefix, bvh, A, B, fdir, K, body, pairs=4, t0=0.05, t1=0.95, ra=0.07, hw0=0.042, hw1=0.014,
                 seam_ph=1.2, ph0=2.2):
    """Trança de escamas em volta de um membro reto (eixo A -> B): faixa de brasa na linha da frente (fdir) e
    `pairs` pares de escamas em folha que nascem dos lados e descem em diagonal até se encontrarem na frente,
    largas na raiz (cobrem a de baixo) e finas na ponta (sobra um V de brasa entre os pares), cada uma com o
    contorno escuro. Grades limpas em coordenadas do membro (posição no eixo, ângulo) sobre o raio médio."""
    ax = (B - A).normalized()
    Ltot = (B - A).length
    oo = (Vector(fdir) - ax * Vector(fdir).dot(ax)).normalized()
    f = ax.cross(oo).normalized()
    rcache = {}

    def rmean(pos):
        k = round(pos, 3)
        if k not in rcache:
            c = A + ax * pos
            rs = []
            for m in range(12):
                d = oo * math.cos(m * math.pi / 6) + f * math.sin(m * math.pi / 6)
                h = bvh.ray_cast(c + d * 0.3, -d)
                rs.append((0.3 - h[3]) if h[0] is not None else ra)
            rcache[k] = sum(rs) / 12
        return rcache[k]

    def surf(pos, ph, out):
        pos = min(max(pos, 0.0), Ltot)
        return A + ax * pos + (oo * math.cos(ph) + f * math.sin(ph)) * (rmean(pos) + out)
    out = []
    step = (t1 - t0) * Ltot / (pairs + 0.75)
    seam = [[surf((t0 + 0.04 + (t1 - t0 - 0.08) * i / 14) * Ltot, ph, 0.0105)
             for ph in (-seam_ph, -seam_ph / 2, 0.0, seam_ph / 2, seam_ph)] for i in range(15)]
    out.append(g_smooth_mesh(prefix + "Seam", seam, K["vein"], body, cap_end=False, closed=False, thick=0.003,
                             outward=True))
    for k in range(pairs):
        for q, sg in enumerate((1, -1)):
            p0 = t0 * Ltot + step * k

            def center(u, p0=p0, sg=sg):
                return p0 + step * 1.75 * u, sg * (ph0 - (ph0 - 0.08) * u ** 0.9)
            rows = []
            for i in range(11):
                u = i / 10
                pa, pha = center(max(0.0, u - 0.05))
                pb, phb = center(min(1.0, u + 0.05))
                tp, tph = pb - pa, (phb - pha) * ra
                ln = math.hypot(tp, tph) or 1.0
                np_, nph = -tph / ln, tp / ln
                pc, phc = center(u)
                hw = (hw0 - (hw0 - hw1) * u) * (0.7 + 0.3 * min(1.0, u * 4.0)) * (1 - u ** 5.0) ** 0.7
                hw = max(hw, 0.0015)
                rows.append([surf(pc + np_ * hw * x, phc + nph * hw * x / ra, 0.011 + 0.015 * u + 0.008 * (1 - x * x))
                             for x in (-1.0, -0.6, -0.2, 0.2, 0.6, 1.0)])
            nm = "%sScale%d_%d" % (prefix, k, q)
            out.append(g_smooth_mesh(nm, rows, K["scale"], body, cap_end=False, closed=False, thick=0.005, outward=True))
            border = [r[0] for r in rows] + rows[-1][1:-1] + [r[-1] for r in rows][::-1]
            out.append(g_pipe(nm + "Edge", border, 0.0024, K["scale_d"], body, sides=6, loop=True))
    return out


def ember_legs(K, src, body):
    """Coxas das escamas de brasa: casca escura em volta da coxa e, na frente, a mesma trança de escamas do
    antebraço (quatro pares em V com a brasa entre eles), do quadril até logo acima do joelho."""
    from mathutils.bvhtree import BVHTree
    orn = []
    knee_z = CB_J["knee"].z
    for sn, s in (("L", 1), ("R", -1)):
        shell = cb_piece(src, "ThighShell" + sn, lambda c, b, n, s=s: b.startswith("Leg") and c.x * s > 0
                         and knee_z + 0.02 < c.z < 0.9, 0.009, K["scale_d"])
        g_subdiv(shell, 2)
        tmp = cb_piece(src, "LegProbe" + sn, lambda c, b, n, s=s: (b.startswith("Leg") or b.startswith("Knee"))
                       and c.x * s > 0 and c.z < 0.95)
        bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
        bpy.data.objects.remove(tmp, do_unlink=True)
        hip, kn = cb_mirror(CB_J["hip"], s), cb_mirror(CB_J["knee"], s)
        orn += g_limb_braid("Thigh" + sn, bvh, hip, kn, (0, -1, 0), K, body, pairs=4, t0=0.2, t1=0.93, ra=0.075,
                            hw0=0.042, hw1=0.014, seam_ph=0.9, ph0=1.35)
    return orn


def build_a_emberscale():
    """Escamas de brasa (endgame). Rodada 1: tronco (faixas de escama em V com veias acesas, gola, gema);
    braços e pernas com o gibão negro até as próximas peças."""
    style = "a_emberscale"
    P, R = g_rig(style)
    M = g_mats()
    K = ember_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["under"])
    g_skinned_pants(src, M["pants"])
    under, parts, mantle = ember_torso(K, src, body)
    arms = ember_arms(K, src, body)
    fringe = ember_fringe(K, body)
    skirt = ember_skirt(K, body)
    legs = ember_legs(K, src, body)
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.008, K["under"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin", K["vein"].name, K["gem"].name))
    g_skin_finish(rig, src, [(mantle, "vert", ("Body", "ArmL", "ArmR"), 0.7),
                             (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (fringe, "fn", _gb_skirt_w, 1.0), (skirt, "fn", _gb_skirt_w, 1.0),
                             (legs, "vert", ("Body", "LegL", "LegR", "KneeL", "KneeR"), 1.0)])
    join_objs("EmberScale", parts + mantle + arms + fringe + skirt + legs)
    g_export_skinned(style)

def build_a_gambeson():
    """Gibão acolchoado (tier I). Rodada 1: tronco (gibão, placa do peito, gola e cinto); mangas são a casca
    lisa do braço e as pernas usam a calça simples até as próximas peças."""
    style = "a_gambeson"
    P, R = g_rig(style)
    M = g_mats()
    G = gambeson_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, G["cloth"])
    g_skinned_pants(src, M["pants"])
    coat, parts, shoulder = gambeson_torso(G, src, body)
    skirt = gambeson_skirt(G, body, coat)
    sl_shells, sl_orn = gambeson_sleeves(G, src, body)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 0.7), (skirt, "fn", _gb_skirt_w, 1.0),
                             (sl_orn, "vert", ("Body", "ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0)])
    join_objs("Gambeson", parts + shoulder + skirt + sl_orn)
    g_export_skinned(style)


# ------------------------------------------------------------------ patrulheiro (linha leve, malha lisa)
# Referência: Tina Yeh, "Ranger" (artstation.com/artwork/4beWlq). Colete oliva fechado no meio por fechos de
# tira trançada com ponteiras de metal, sobre camisa branca folgada; duas correias de couro em X com debrum
# claro, cachecol escuro de tricô, cinto escuro com chapa de couro tachada. Cores fixas (rg_), como o gibão.
def ranger_mats():
    return dict(
        vest=gm("rg_vest", "#586034", 0.95), vest_d=gm("rg_vest_d", "#3A4022", 0.95),
        strap=gm("rg_strap", "#3C4630", 0.9), lea=gm("rg_leather", "#7C4A26", 0.8),
        lea_l=gm("rg_leather_l", "#B98A4E", 0.85), lea_d=gm("rg_leather_d", "#472A18", 0.85),
        belt=gm("rg_belt", "#2C2622", 0.85), scarf=gm("rg_scarf", "#2E3036", 0.95),
        scarf_d=gm("rg_scarf_d", "#15161A", 0.95), linen=gm("rg_linen", "#E2DBC8", 0.95),
        linen_d=gm("rg_linen_d", "#B4AB95", 0.95), metal=gm("rg_metal", "#B4B8BC", 0.45, 0.6),
        brc=gm("rg_bracer", "#6E4A34", 0.8), brc_d=gm("rg_bracer_d", "#3E2618", 0.85),
        brc2=gm("rg_bracer2", "#4E302C", 0.8),
    )


def rg_snap(bvh, guide, n, out, loop=False, smooth=6):
    """Linha deitada numa superfície: guide (pontos aproximados) vira n pontos regulares, alisados e projetados
    no ponto mais próximo da malha (bvh). Devolve (pontos a `out` da superfície, normais alisadas)."""
    g = list(guide) + ([guide[0]] if loop else [])
    d = [0.0]
    for a, b in zip(g, g[1:]):
        d.append(d[-1] + (b - a).length)
    m = n if loop else n - 1
    pts = []
    for i in range(n):
        x = d[-1] * i / m
        k = max(j for j in range(len(d) - 1) if d[j] <= x + 1e-9)
        pts.append(g[k].lerp(g[k + 1], (x - d[k]) / max(d[k + 1] - d[k], 1e-6)))
    C = Vector((0, 0, 1.2))

    def avg(L, i):
        if loop:
            return L[i - 1] + L[i] * 2 + L[(i + 1) % n]
        return L[i] * 4 if i in (0, n - 1) else L[i - 1] + L[i] * 2 + L[i + 1]
    nrm = [Vector((0, -1, 0))] * n
    for _ in range(3):
        for _ in range(smooth):
            pts = [avg(pts, i) / 4 for i in range(n)]
        hits = [bvh.find_nearest(p) for p in pts]
        pts = [h[0] for h in hits]
        nrm = [h[1] if (h[0] - C).dot(h[1]) >= 0 else -h[1] for h in hits]
    for _ in range(smooth):
        nrm = [avg(nrm, i).normalized() for i in range(n)]
    return [p + nr * out for p, nr in zip(pts, nrm)], nrm


def rg_band(name, pts, nrms, hw, th, material, parent, loop=False, sides=10, taper=0):
    """Correia chata deitada: seção achatada de cantos redondos (meia largura hw, espessura th) ao longo de pts,
    com a base na superfície (normais nrms). taper = quantos pontos afinam em cada ponta."""
    n = len(pts)
    rings = []
    for i in range(n):
        t = (pts[(i + 1) % n] - pts[i - 1]) if loop else (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        t.normalize()
        nr = (nrms[i] - t * nrms[i].dot(t)).normalized()
        sd = t.cross(nr).normalized()
        k = 1.0
        if taper and not loop:
            k = min(1.0, 0.35 + 0.65 * min(i, n - 1 - i) / taper)
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            cx, sy = math.cos(a), math.sin(a)
            x = math.copysign(abs(cx) ** 0.45, cx) * hw * k
            y = math.copysign(abs(sy) ** 0.45, sy) * th / 2
            ring.append(pts[i] + sd * x + nr * (y + th / 2 - 0.0015))
        rings.append(ring)
    if loop:
        rings += rings[:2]
    return g_smooth_mesh(name, rings, material, parent, cap_end=not loop)


def rg_edges(name, pts, nrms, hw, th, r, material, parent, loop=False):
    """Debrum nas duas bordas de uma correia de rg_band."""
    n = len(pts)
    out = []
    for sg in (-1, 1):
        ln = []
        for i in range(n):
            t = (pts[(i + 1) % n] - pts[i - 1]) if loop else (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
            t.normalize()
            nr = (nrms[i] - t * nrms[i].dot(t)).normalized()
            ln.append(pts[i] + t.cross(nr).normalized() * hw * sg * 0.86 + nr * (th - 0.001))
        out.append(g_pipe("%s%d" % (name, sg + 1), ln, r, material, parent, sides=6, loop=loop))
    return out


def rg_buckle(name, q, u, v, nr, w, h, material, parent, r=0.0028, pin=True):
    """Fivela de aro retangular em q: u ao longo da correia, v atravessado, nr para fora."""
    u, v, nr = Vector(u).normalized(), Vector(v).normalized(), Vector(nr).normalized()
    rim = [q + nr * 0.004 + u * x + v * y for x, y in ((-w, h), (0, h * 1.04), (w, h), (w * 1.05, 0), (w, -h),
                                                       (0, -h * 1.04), (-w, -h), (-w * 1.05, 0))]
    out = [g_pipe(name, rim, r, material, parent, sides=6, loop=True)]
    if pin:
        out.append(g_pipe(name + "Pin", [q + nr * 0.005 - u * w, q + nr * 0.007, q + nr * 0.005 + u * w], r * 0.8,
                          material, parent, sides=6))
    return out


def ranger_torso(K, src, body):
    """Tronco do patrulheiro: colete oliva (casca do corpo) com costuras, três fechos de tira com ponteiras de
    metal, duas tiras verdes de fivela no alto do peito, correias em X com debrum claro (dão a volta pelas
    costas), ponta de correia furada pendurada no peito direito, cachecol de tricô e cinto com chapa tachada.
    Devolve (casca do colete, peças rígidas)."""
    from mathutils.bvhtree import BVHTree

    def is_torso(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.51

    vest = cb_piece(src, "Vest", is_torso, 0.014, K["vest"])
    g_subdiv(vest, 2)
    rad, hit_a = _g_ray_tools(vest)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in vest.data.vertices], [tuple(p.vertices) for p in vest.data.polygons])
    parts = []

    def tan(a):
        return Vector((math.cos(a), math.sin(a), 0))
    UP = Vector((0, 0, 1))

    # ---- costuras do colete: fecho do meio (duas bordas encostadas), recortes da frente e meio das costas
    for nm, a, z0, z1, r in (("SeamFrontL", 0.028, 0.99, 1.43, 0.0024), ("SeamFrontR", -0.028, 0.99, 1.43, 0.0024),
                             ("SeamSideL", 0.8, 1.05, 1.3, 0.002), ("SeamSideR", -0.8, 1.05, 1.3, 0.002),
                             ("SeamBack", math.pi, 1.0, 1.45, 0.002)):
        parts.append(g_pipe(nm, [hit_a(a, z0 + (z1 - z0) * i / 15, 0.0006) for i in range(16)], r, K["vest_d"],
                            body, sides=6))

    # ---- fechos: tira trançada verde-escura com ponteira de metal arredondada e rebite em cada ponta
    cap_o = [(-0.01, -0.0105), (0.004, -0.0105), (0.011, -0.007), (0.0135, 0.0), (0.011, 0.007), (0.004, 0.0105),
             (-0.01, 0.0105)]
    for k, z in enumerate((1.225, 1.15, 1.08)):
        A = 0.36
        pts = [hit_a(-A + 2 * A * i / 8, z, 0.0) for i in range(9)]
        nr = [rad(-A + 2 * A * i / 8) for i in range(9)]
        parts.append(rg_band("ClaspStrap%d" % k, pts, nr, 0.009, 0.005, K["strap"], body))
        for sg in (-1, 1):
            a = sg * A
            q = hit_a(a, z, 0.0045)
            parts.append(g_plate("ClaspCap%d_%d" % (k, sg + 1), cap_o, q, tan(a) * sg, UP, 0.004, K["metal"], body))
            parts.append(g_bead("ClaspRivet%d_%d" % (k, sg + 1), hit_a(a + sg * 0.03, z, 0.008), 0.0035, K["metal"],
                                body))

    # ---- duas tiras verdes de fivela no alto do peito (a de baixo mais larga, com dois rebites na ponta)
    for k, (z, a0, a1, hw, ab, rv) in enumerate(((1.345, -0.46, 0.5, 0.0115, -0.05, (0.36, 0.43)),
                                                 (1.405, -0.34, 0.3, 0.009, 0.07, ()))):
        aa = [a0 + (a1 - a0) * i / 12 for i in range(13)]
        parts.append(rg_band("ChestStrap%d" % k, [hit_a(a, z, 0.0) for a in aa], [rad(a) for a in aa], hw, 0.005,
                             K["strap"], body))
        parts += rg_buckle("ChestBuckle%d" % k, hit_a(ab, z, 0.004), tan(ab), UP, rad(ab), 0.012, hw + 0.004,
                           K["metal"], body)
        for j, a in enumerate(rv):
            parts.append(g_bead("ChestRivet%d_%d" % (k, j), hit_a(a, z, 0.0055), 0.0038, K["metal"], body))

    # ---- correias em X: cada uma sai de um ombro, cruza o peito, passa sob o braço do outro lado e volta pelas
    #      costas ao mesmo ombro; debrum claro nas bordas. A que desce para o quadril esquerdo fica por cima e tem
    #      fivela no lado.
    for sn, s, out in (("A", 1, 0.0075), ("B", -1, 0.002)):          # s = lado do quadril onde ela chega
        guide = [Vector(p) for p in ((-0.1 * s, 0.0, 1.5), (-0.085 * s, -0.1, 1.42), (0.0, -0.13, 1.325),
                                     (0.1 * s, -0.11, 1.2), (0.16 * s, 0.0, 1.12), (0.1 * s, 0.11, 1.17),
                                     (0.0, 0.13, 1.28), (-0.085 * s, 0.1, 1.42))]
        pts, nr = rg_snap(bvh, guide, 96, out, loop=True)
        parts.append(rg_band("Cross" + sn, pts, nr, 0.019, 0.0055, K["lea"], body, loop=True))
        parts += rg_edges("CrossEdge" + sn, pts, nr, 0.019, 0.0055, 0.0028, K["lea_l"], body, loop=True)
        if s > 0:                        # fivela da correia, no lado esquerdo da cintura
            i = min(range(96), key=lambda j: (pts[j] - Vector((0.135, -0.085, 1.16))).length)
            t = (pts[i + 1] - pts[i - 1]).normalized()
            parts += rg_buckle("CrossBuckle", pts[i] + nr[i] * 0.004, t, t.cross(nr[i]), nr[i], 0.014, 0.024,
                               K["metal"], body, r=0.0034)

    # ---- ponta de correia pendurada no peito direito: couro claro, furos e passador de metal
    hg = [Vector(p) for p in ((-0.082, -0.1, 1.455), (-0.08, -0.12, 1.4), (-0.078, -0.13, 1.35), (-0.076, -0.13, 1.3))]
    hp, hn = rg_snap(bvh, hg, 14, 0.011, smooth=3)
    parts.append(rg_band("HangStrap", hp, hn, 0.012, 0.005, K["lea_l"], body, taper=2))
    for j in (4, 6, 8):
        parts.append(g_bead("HangHole%d" % j, hp[j] + hn[j] * 0.0035, 0.003, K["lea_d"], body))
    t = (hp[11] - hp[10]).normalized()
    parts += rg_buckle("HangKeeper", hp[11] + hn[11] * 0.001, t.cross(hn[11]), t, hn[11], 0.015, 0.004, K["metal"],
                       body, pin=False)

    # ---- cachecol de tricô: gola larga e fofa em volta do pescoço, caída na frente, com dobras
    N = 44
    rows = []
    for k, (z, rx, ry, sag) in enumerate(((1.435, 0.1, 0.092, 0.05), (1.452, 0.134, 0.118, 0.06),
                                          (1.484, 0.143, 0.128, 0.048), (1.514, 0.13, 0.117, 0.03),
                                          (1.54, 0.106, 0.098, 0.012), (1.556, 0.086, 0.082, 0.006),
                                          (1.548, 0.064, 0.062, 0.0))):
        row = []
        for j in range(N):
            a = 2 * math.pi * j / N
            fr = max(0.0, math.cos(a)) ** 2
            w = 1.0 + (0.045 * math.sin(3 * a + 1.7 * k) + 0.025 * math.sin(7 * a + k)) * (0 < k < 6)
            row.append(Vector((math.sin(a) * rx * w, 0.014 - math.cos(a) * ry * w - 0.012 * fr, z - sag * fr)))
        rows.append(row)
    parts.append(g_smooth_mesh("Scarf", rows, K["scarf"], body, cap_end=False))
    for k, i in enumerate((2, 3, 4)):    # vincos entre as voltas do cachecol
        parts.append(g_pipe("ScarfFold%d" % k, [(p + q) / 2 + Vector((0, 0, -0.004)) for p, q in zip(rows[i], rows[i + 1])],
                            0.003, K["scarf_d"], body, sides=6, loop=True))

    # ---- cinto escuro com debrum e, na frente, chapa de couro com quatro tachas
    NB = 48
    belt_rows = [[hit_a(2 * math.pi * j / NB, z, o) for j in range(NB)]
                 for z, o in ((0.992, 0.004), (0.996, 0.013), (1.04, 0.013), (1.044, 0.004))]
    parts.append(g_smooth_mesh("Belt", belt_rows, K["belt"], body, cap_end=False, outward=True))
    aa = [-0.3 + 0.6 * i / 10 for i in range(11)]
    parts.append(rg_band("BeltPlate", [hit_a(a, 1.014, 0.012) for a in aa], [rad(a) for a in aa], 0.034, 0.006,
                         K["lea"], body))
    for i, (a, dz) in enumerate(((-0.17, 0.014), (0.17, 0.014), (-0.17, -0.014), (0.17, -0.014))):
        parts.append(g_bead("BeltStud%d" % i, hit_a(a, 1.014 + dz, 0.019), 0.0055, K["metal"], body))
    return vest, parts


def ranger_shoulder(K, src, body, s):
    """Ombro do patrulheiro: capa curta verde do colete sobre o alto do braço e, por cima, pala de couro com
    debrum claro. No direito a pala é de couro claro em duas camadas, presa à capa por uma fileira de passadores;
    no esquerdo é de couro escuro, com dois passadores só na borda de fora."""
    sn = "L" if s > 0 else "R"
    # raio limitado à mediana da fileira (cap): sem isso a fileira puxa para o raio que bate no peito e nas
    # costas e a barra abre para fora como dragona
    (cr, cd, _), = _g_shoulder_dome(src, s, [(0.3, 2.95, 1.8, 0.013, 0.002)], phis=36, rows=14, pull=0.12,
                                    cap=0.006, taper=True)
    (yr, yd, _), = _g_shoulder_dome(src, s, [(0.05, 2.45 if s < 0 else 2.25, 1.65, 0.022, 0.002)], phis=32,
                                    rows=12, pull=0.15, cap=0.006, taper=True)
    n = len(cr[0])
    parts = [g_smooth_mesh("ShCap" + sn, cr, K["vest"], body, cap_end=False, closed=False, thick=0.006, outward=True)]
    edge = [r[0] for r in cr] + cr[-1][1:-1] + [r[-1] for r in cr][::-1]
    edir = [r[0] for r in cd] + cd[-1][1:-1] + [r[-1] for r in cd][::-1]
    parts.append(g_pipe("ShCapHem" + sn, [q + d * 0.003 for q, d in zip(edge, edir)], 0.0042, K["vest_d"], body,
                        sides=8))
    lea = K["lea"] if s < 0 else K["lea_d"]
    parts.append(g_smooth_mesh("ShYoke" + sn, yr, lea, body, cap_end=False, closed=False, thick=0.007, outward=True))
    edge = [r[0] for r in yr] + yr[-1][1:-1] + [r[-1] for r in yr][::-1]
    edir = [r[0] for r in yd] + yd[-1][1:-1] + [r[-1] for r in yd][::-1]
    parts.append(g_pipe("ShYokeHem" + sn, [q + d * 0.004 for q, d in zip(edge, edir)], 0.005, K["lea_l"], body, sides=8))
    n = len(yr[0])
    if s < 0:                            # segunda camada: faixa clara por dentro da borda
        i = len(yr) - 4
        parts.append(g_pipe("ShYokeBand" + sn, [yr[i][j] + yd[i][j] * 0.005 for j in range(3, n - 3)], 0.0045,
                            K["lea_l"], body, sides=8))
    cols = range(4, n - 3, 4) if s < 0 else (n // 2 - 3, n // 2 + 3)
    flat = [(q, d) for r, dr in zip(cr, cd) for q, d in zip(r, dr)]
    for j in cols:                       # passadores de couro: tira deitada que atravessa a borda da pala e
        d = yd[-1][j]                    # assenta na capa verde logo abaixo
        dn = (yr[-1][j] - yr[-4][j]).normalized()
        q, dq = min(flat, key=lambda e: (e[0] - (yr[-1][j] + dn * 0.02)).length)
        pts = [yr[-4][j] + d * 0.006, yr[-2][j] + d * 0.007, yr[-1][j] + d * 0.009, q + dq * 0.004]
        parts.append(rg_band("ShTab%s%d" % (sn, j), pts, [d, d, d, dq], 0.0055, 0.004,
                             K["lea_d"] if s < 0 else K["lea_l"], body))
    return parts


def ranger_arms(K, src, body):
    """Braços do patrulheiro: manga de linho bufante (casca do braço estufada do meio do braço até o cotovelo,
    com dobras macias) e braçadeira longa de couro do cotovelo ao pulso, boca larga no cotovelo. Direita:
    couro castanho com três ganchos de amarração no lado de dentro e dobra enrolada perto do pulso; esquerda:
    couro castanho-avermelhado com faixa verde e argola de metal abaixo do cotovelo.
    Devolve (cascas tiradas do corpo, enfeites)."""
    from mathutils.bvhtree import BVHTree
    shells, orn = [], []
    for sn, s in (("L", 1), ("R", -1)):
        L1, L2, at, coords, ring = _gb_arm_frame(s)

        def arm(b, c, s=s):
            return (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0
        sl = cb_piece(src, "Sleeve" + sn, lambda c, b, n: arm(b, c) and (b.startswith("Arm") or _cb_fore_t(c) < 0.12),
                      0.008, K["linen"])
        g_subdiv(sl, 2)
        for v in sl.data.vertices:       # bufante: estufa do meio do braço até o cotovelo, dobras em volta
            u, ph = coords(v.co)
            t = u / L1
            up = max(0.0, min(1.0, (t - 0.3) / 0.4))
            dn = max(0.0, min(1.0, (t - 0.82) / 0.18))   # recolhe para entrar na boca da braçadeira
            bl = 0.024 * up * up * (3 - 2 * up) * (1 - 0.6 * dn)
            fold = 0.007 * abs(math.sin(3 * ph + 2.4 * t)) ** 0.6 * bl / 0.024
            v.co += v.normal * (bl + fold)
        shells.append(sl)

        FV0, FV1 = 0.04, 0.9
        mat, rim = (K["brc"], K["brc_d"]) if s < 0 else (K["brc2"], K["lea_d"])
        vb = cb_piece(src, "Bracer" + sn, lambda c, b, n: arm(b, c) and b.startswith("Elbow") and
                      FV0 <= _cb_fore_t(c) <= FV1, 0.02, mat)
        g_subdiv(vb, 2)
        fl = 0.017 if s < 0 else 0.011
        for v in vb.data.vertices:       # boca larga no cotovelo, aperta no pulso
            ft = _cb_fore_t(v.co)
            v.co += v.normal * (fl * max(0.0, 1 - (ft - FV0) / 0.3) ** 2 - 0.003 * max(0.0, ft - 0.6))
        shells.append(vb)
        orn += g_border_pipes(vb, "BracerEdge" + sn, 0.0045, rim, body)
        bvh = BVHTree.FromPolygons([v.co.copy() for v in vb.data.vertices], [tuple(p.vertices) for p in vb.data.polygons])

        def frame(u, ph):
            c, ax = at(u)
            q = ring(bvh, u, 0.0, phis=[ph])[0]
            nn = (q - c - ax * (q - c).dot(ax)).normalized()
            return q, nn, ax, ax.cross(nn).normalized()
        if s < 0:
            hooks = []
            ph = s * (math.pi / 2 + 0.6)                 # frente, puxado para o lado do corpo
            for k, ft in enumerate((0.13, 0.24, 0.35)):
                q, nn, ax, w = frame(L1 + ft * L2, ph)
                hooks.append((q, nn, w))
                orn.append(g_pipe("BracerHook%s%d" % (sn, k), [q - w * 0.005 + nn * 0.001, q - w * 0.004 + nn * 0.006,
                                                              q + w * 0.002 + nn * 0.008, q + w * 0.006 + nn * 0.005],
                                  0.0022, K["metal"], body, sides=6))
            lace = []
            for k, (q, nn, w) in enumerate(hooks):
                lace += [q + w * 0.009 + nn * 0.002, q + nn * 0.006, q - w * 0.008 + nn * 0.002]
            orn.append(g_pipe("BracerLace" + sn, g_spline(lace, 24), 0.0016, K["lea_d"], body, sides=6))
            for k, ft in enumerate((0.6, 0.65)):         # dobra enrolada perto do pulso
                pts = ring(bvh, L1 + ft * L2, 0.002, n=32)
                if None not in pts:
                    orn.append(g_pipe("BracerRoll%s%d" % (sn, k), pts, 0.0048, mat, body, sides=8, loop=True))
        else:
            brs = []
            for i in range(6):           # faixa verde enrolada, bojuda no meio, com argola de metal por fora
                v = i / 5
                pts = ring(bvh, L1 + (0.17 + 0.09 * v) * L2, 0.002 + 0.004 * math.sin(math.pi * v), n=32)
                if None in pts:
                    break
                brs.append(pts)
            if len(brs) == 6:
                orn.append(g_smooth_mesh("BracerBand" + sn, brs, K["vest"], body, cap_end=False, outward=True,
                                         thick=0.004))
                for nm, r in (("Hi", brs[0]), ("Lo", brs[-1])):
                    orn.append(g_pipe("BracerBandEdge%s%s" % (sn, nm), r, 0.0025, K["vest_d"], body, sides=6,
                                      loop=True))
            q, nn, ax, w = frame(L1 + 0.215 * L2, 0.25)
            orn.append(g_pipe("BracerRing" + sn, [q + nn * 0.008 + ax * 0.011 * math.cos(2 * math.pi * j / 12) +
                                                  w * 0.017 * math.sin(2 * math.pi * j / 12) for j in range(12)],
                              0.0032, K["metal"], body, sides=6, loop=True))
            for k, ft in enumerate((0.45, 0.68)):        # vincos do couro
                pts = ring(bvh, L1 + ft * L2, 0.0005, n=32)
                if None not in pts:
                    orn.append(g_pipe("BracerFold%s%d" % (sn, k), pts, 0.0026, K["lea_d"], body, sides=6, loop=True))
    return shells, orn


def _rg_skirt_w(p):
    """Pesos da saia do patrulheiro: os painéis são abertos no meio da frente e de trás, então cada um vai inteiro
    com a perna do seu lado; os da frente passam para a coxa logo abaixo do cinto (a coxa na passada não fura o
    pano), os de trás mais devagar."""
    a = math.atan2(abs(p.x), -p.y)
    front = a < 1.62
    leg = max(0.0, min(1.0, (0.975 - p.z) / (0.13 if front else 0.22))) * (0.97 if front else 0.85)
    w = {"Body": 1.0 - leg, "LegL" if p.x > 0 else "LegR": leg}
    return {b: v for b, v in w.items() if v > 1e-4}


def ranger_skirt(K, body, vest):
    """Saia do colete: quatro painéis de pano oliva do cinto até pouco acima do joelho, abertos no meio da
    frente, nos lados (fenda que abre descendo) e no meio das costas; debrum escuro nas bordas, contorno de
    bolso costurado nos painéis da frente, presilhas de couro junto às fendas dos lados e duas tiras finas de
    couro penduradas na frente direita. Devolve as peças (pesos por _rg_skirt_w)."""
    _, hit_a = _g_ray_tools(vest)
    Z0 = 0.995
    SPL = 1.62                             # fenda do lado (rad a partir da frente)
    r0_cache = {}

    def r0(a):                             # raio do pano no alto: por fora do colete (e do glúteo)
        k = round(a, 4)
        if k not in r0_cache:
            r0_cache[k] = max(Vector((q.x, q.y)).length for q in (hit_a(a, 0.99), hit_a(a, 0.93), hit_a(a, 0.88)))
        return r0_cache[k]

    def pt(a, t, z1, out=0.0):
        r = r0(a) + 0.011 + 0.032 * t ** 0.9 + 0.005 * math.sin(7 * a) * t + out
        return Vector((math.sin(a) * r, -math.cos(a) * r, Z0 - t * (Z0 - z1)))

    def fo(t):                             # meia abertura da frente
        return 0.03 + 0.05 * t

    def sg(t):                             # meia abertura da fenda do lado: fechada no quadril
        return 0.004 + 0.07 * max(0.0, (t - 0.2) / 0.8) ** 1.2

    def bk(t):                             # meia abertura de trás
        return 0.004 + 0.05 * max(0.0, (t - 0.3) / 0.7)
    rows, NC = 16, 14
    parts = []
    for side, s in (("L", 1), ("R", -1)):
        for nm, a0f, a1f, z1 in (("Front", fo, lambda t: SPL - sg(t), 0.6),
                                 ("Back", lambda t: SPL + sg(t), lambda t: math.pi - bk(t), 0.575)):
            def P(u, t, out=0.0, a0f=a0f, a1f=a1f, z1=z1, s=s):
                return pt(s * (a0f(t) + (a1f(t) - a0f(t)) * u), t, z1, out)
            grid = [[P(j / NC, i / rows) for j in range(NC + 1)] for i in range(rows + 1)]
            pn = "Skirt%s%s" % (nm, side)
            parts.append(g_smooth_mesh(pn, grid, K["vest"], body, cap_end=False, closed=False, thick=0.005,
                                       outward=True))
            edge = [P(0.0, i / rows, 0.003) for i in range(2, rows + 1)] + \
                   [P(j / NC, 1.0, 0.003) for j in range(1, NC)] + [P(1.0, i / rows, 0.003) for i in range(rows, 1, -1)]
            parts.append(g_pipe(pn + "Edge", edge, 0.0034, K["vest_d"], body, sides=8))
            if nm == "Front":              # bolso costurado: aba e contorno
                u0, u1, t0, t1 = 0.22, 0.78, 0.42, 0.82
                box = [P(u0 + (u1 - u0) * k / 8, t0, 0.0012) for k in range(9)] + \
                      [P(u1, t0 + (t1 - t0) * k / 6, 0.0012) for k in range(1, 7)] + \
                      [P(u1 - (u1 - u0) * k / 8, t1, 0.0012) for k in range(1, 9)] + \
                      [P(u0, t1 - (t1 - t0) * k / 6, 0.0012) for k in range(1, 6)]
                parts.append(g_pipe(pn + "Pocket", box, 0.0018, K["vest_d"], body, sides=6, loop=True))
                parts.append(g_pipe(pn + "Flap", [P(u0 + (u1 - u0) * k / 8, t0 + 0.07, 0.0012) for k in range(9)],
                                    0.0018, K["vest_d"], body, sides=6))
                for k, t in enumerate((0.28, 0.55)):     # presilhas de couro junto à fenda do lado
                    q, q2 = P(0.92, t, 0.004), P(0.92, t + 0.06, 0.004)
                    a = s * (a0f(t) + (a1f(t) - a0f(t)) * 0.92)
                    parts.append(g_plate("%sTab%d" % (pn, k), [(-0.007, -0.016), (0.007, -0.016), (0.007, 0.016),
                                                               (-0.007, 0.016)], q,
                                         Vector((math.cos(a), math.sin(a), 0)), q - q2, 0.004, K["lea"], body))
                if s < 0:                  # tiras finas de couro penduradas, com ponta enrolada
                    for k, u in enumerate((0.3, 0.55)):
                        top = P(u, 0.03, 0.006)
                        tie = [P(u + 0.02 * math.sin(3 * t), t, 0.006) for t in (0.03, 0.12, 0.22, 0.32, 0.4)]
                        parts.append(g_pipe("%sTie%d" % (pn, k), tie, 0.0028, K["lea"], body, sides=6))
                        parts.append(g_bead("%sTieKnot%d" % (pn, k), top, 0.006, K["lea_d"], body))
                        parts.append(g_bead("%sTieEnd%d" % (pn, k), tie[-1], 0.0045, K["lea_d"], body))
    return parts


def build_a_ranger():
    """Patrulheiro (linha leve). Rodada 1: tronco (colete, fechos, correias em X, cachecol e cinto); as mangas
    são a casca lisa de linho e as pernas a calça simples até as próximas peças."""
    style = "a_ranger"
    P, R = g_rig(style)
    M = g_mats()
    K = ranger_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, M["pants"])
    g_skinned_pants(src, M["pants"])
    vest, parts = ranger_torso(K, src, body)
    shoulder = ranger_shoulder(K, src, body, 1) + ranger_shoulder(K, src, body, -1)
    arm_shells, arm_orn = ranger_arms(K, src, body)
    skirt = ranger_skirt(K, body, vest)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 0.7),
                             (arm_orn, "vert", ("Body", "ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (skirt, "fn", _rg_skirt_w, 1.0)])
    join_objs("Ranger", parts + shoulder + arm_orn + skirt)
    g_export_skinned(style)


# ------------------------------------------------------------------ placa élfica de mithril (tier III, malha lisa)
# Referência: Un Lee, "Elven Knight". Placa justa de prata azulada sobre gibão verde-escuro, gorjal alto com
# babador em V, quilha no meio do peito, árvore de folhas incrustadas (azul-claro, com sulco escuro em volta)
# subindo do fim do peitoral até a gola, quatro lâminas na cintura presas por fivelas do lado esquerdo.
def mithril_mats():
    return dict(
        plate=gm("mt_plate", "#C3CBD3", 0.3, 0.75), plate_d=gm("mt_plate_d", "#7A8693", 0.4, 0.75),
        leaf=gm("mt_leaf", "#A6DCF0", 0.35, 0.3), groove=gm("mt_groove", "#33404D", 0.6, 0.4),
        under=gm("mt_under", "#2C372D", 0.9), green=gm("mt_green", "#1F6E55", 0.85),
        lea=gm("mt_leather", "#4A3A2E", 0.8), mail=gm("mt_mail", "#7C8C38", 0.7, 0.3),
        joint=gm("mt_joint", "#49515B", 0.5, 0.5), mail_d=gm("mt_mail_d", "#2E3518", 0.7, 0.4), olive=gm("mt_olive", "#38371C", 0.9), mail_dk=gm("mt_mail_dk", "#2A3022", 0.75, 0.3), mail_dd=gm("mt_mail_dd", "#171A12", 0.8, 0.2),
    )


def _mt_bvh(objs):
    """BVH em coordenadas do mundo de uma ou mais malhas (para deitar folhas e correias nelas)."""
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update()
    vs, fs = [], []
    for o in objs:
        base = len(vs)
        vs += [o.matrix_world @ v.co for v in o.data.vertices]
        fs += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    return BVHTree.FromPolygons(vs, fs)


def mt_leaf(name, bvh, a, z, s, ang, L, W, K, parent, curl=0.22, off=0.0018):
    """Folha incrustada na placa: raiz no ângulo a / altura z (projetada na malha do bvh), apontando ang graus a
    partir da vertical para o lado s (90 = deitada para fora, 180 = para baixo), comprimento L, meia largura W,
    ponta curvando para fora (curl). Por baixo, uma folha escura um pouco maior faz o sulco em volta."""
    p0 = bvh.find_nearest(wk_plate_pt(a, z, 0.02, fr_max=1.03))[0]
    tg = Vector((math.cos(a), math.sin(a), 0)) * (s if s else 1)
    up = Vector((0, 0, 1))
    t = math.radians(ang)
    d0 = up * math.cos(t) + tg * math.sin(t)
    sd = tg * math.cos(t) - up * math.sin(t)
    return mt_leaf_at(name, bvh, p0, d0, sd, L, W, K, parent, curl, off)


def mt_leaf_at(name, bvh, p0, d0, sd, L, W, K, parent, curl=0.22, off=0.0018):
    """Folha incrustada com raiz p0, direção d0 e lado da curva sd (vetores tangentes à malha do bvh)."""
    def guide(u):
        return p0 + (d0 * u + sd * curl * u * u) * L

    def hw(u):
        return W * math.sin(math.pi * u) ** 0.75 * (1 - 0.3 * u)
    seat = g_surface_leaf(name + "Seat", bvh, guide, lambda u: hw(u) + 0.0022, K["groove"], parent, n=12,
                          off0=off * 0.45, lift=0.0, arch=0.0, thick=0.001)
    leaf = g_surface_leaf(name, bvh, guide, hw, K["leaf"], parent, n=12, off0=off, lift=0.0, arch=0.0008,
                          thick=0.0012)
    return [seat, leaf]


def mithril_torso(K, src, body):
    """Tronco da placa élfica: gibão verde-escuro (casca), peitoral liso com quilha e frisos dos lados, costal
    fechado, gorjal alto com gola verde e babador em V por cima do peito, quatro lâminas da cintura (a barra
    de cada uma desce um pouco no meio da frente) com correia e fivela do lado esquerdo, e as folhas
    incrustadas: árvore no peitoral, ramo no babador e um par em cada lâmina. Devolve (casca, peças)."""
    def under_keep(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52
    # a casca de baixo fica toda coberta pelas placas: aço escuro, para uma fresta na corrida ler como junta
    under = cb_piece(src, "Under", under_keep, 0.006, K["joint"])
    g_subdiv(under, 2)
    parts = []
    # ---- peitoral: da linha das lâminas até sob o babador
    A = 1.3

    def breast(u, v):
        a = -A + 2 * A * v
        top = 1.48 - 0.06 * (abs(a) / A) ** 4
        bot = 1.1 + 0.02 * min(1.0, abs(a) / 1.2) ** 2
        z = top + (bot - top) * u
        bulge = 0.003 * math.sin(math.pi * min(1.0, u * 1.1)) * max(0.0, math.cos(a)) ** 1.5
        return wk_plate_pt(a, z, 0.016 + bulge, keel=0.02, fr_max=1.03)
    bp, br = _wk_plate("Breastplate", breast, 16, 40, K["plate"], body)
    parts.append(bp)
    parts.append(g_pipe("BreastRim", br[-1], 0.006, K["plate"], body, sides=8))
    for nm, v in (("Keel", 0.5), ("FluteL", 0.5 + 0.75 / (2 * A)), ("FluteR", 0.5 - 0.75 / (2 * A))):
        parts.append(g_pipe("Breast" + nm, [breast(u, v) + (breast(u, v) - Vector((0, 0.01, breast(u, v).z))).normalized()
                                            * 0.0015 for u in (0.25, 0.45, 0.65, 0.85, 0.97)],
                            0.0028 if nm == "Keel" else 0.0022, K["plate_d"], body, sides=6))
    # ---- costal: costas inteiras entre as axilas, do gorjal às lâminas
    B = math.pi - 1.25

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.48 - 0.07 * abs(2 * v - 1) ** 4
        z = zt + (1.1 - zt) * u
        return wk_plate_pt(a, z, 0.017)
    bk, bkr = _wk_plate("Backplate", back, 12, 30, K["plate"], body)
    parts.append(bk)
    parts.append(g_pipe("BackRim", bkr[-1], 0.006, K["plate"], body, sides=8))
    parts.append(g_pipe("BackKeel", [back(u, 0.5) + Vector((0, 0.0015, 0)) for u in (0.1, 0.4, 0.7, 0.97)], 0.0025,
                        K["plate_d"], body, sides=6))

    # ---- gorjal: uma peça só, do colar em pé em volta do pescoço até o babador em V no peito (ponta no esterno);
    #      atrás e nos ombros ele desce só um pouco sobre o costal. Gola verde saindo por cima do colar.
    NG, AB = 48, 1.0

    def gz_bot(a):                     # barra de baixo: V na frente; nos ombros desce sobre o alto do ombro
        x = min(1.0, abs(a) / AB)
        return 1.35 + (1.452 - 1.35) * x ** 1.15 - 0.03 * abs(math.sin(a)) ** 6

    def gor_pt(j, u):                  # u: 0 no alto do colar -> 1 na barra
        a = math.atan2(math.sin(2 * math.pi * j / NG), math.cos(2 * math.pi * j / NG))
        if u <= 0.4:                   # colar: anéis em volta do pescoço
            t = u / 0.4
            z = 1.578 - (1.578 - 1.488) * t
            rx = 0.088 + (0.104 - 0.088) * t ** 1.6
            ry = 0.082 + (0.098 - 0.082) * t ** 1.6
            return Vector((math.sin(a) * rx, 0.012 - math.cos(a) * ry, z))
        t = (u - 0.4) / 0.6            # placa sobre o peito, os ombros e as costas
        z = 1.472 + (gz_bot(a) - 1.472) * t
        q = wk_plate_pt(a, z, 0.024 + 0.003 * (1 - t), keel=0.02, fr_max=1.03)
        if t < 0.34:                   # dobra do colar para a placa: arredonda o canto
            c = Vector((math.sin(a) * 0.104, 0.012 - math.cos(a) * 0.098, 1.488))
            q = c.lerp(q, 0.55 + 0.45 * (t / 0.34))
        return q
    US = [0.0, 0.13, 0.26, 0.4, 0.47, 0.55, 0.65, 0.76, 0.88, 1.0]
    gor = [[gor_pt(j, u) for j in range(NG)] for u in US]
    gorget = g_smooth_mesh("Gorget", gor, K["plate"], body, cap_end=False, thick=0.006, outward=True)
    parts.append(gorget)
    parts.append(g_pipe("GorgetRim", gor[0], 0.0045, K["plate"], body, sides=8, loop=True))
    nb = (lambda q: Vector((q.x, q.y - 0.012, 0)).normalized())
    parts.append(g_pipe("GorgetHem", [q + nb(q) * 0.002 for q in gor[-1]], 0.0055, K["plate"], body, sides=8,
                        loop=True))
    parts.append(g_pipe("GorgetLine", [q + nb(q) * 0.003 for q in gor[3]], 0.0022, K["plate_d"], body, sides=6,
                        loop=True))
    collar = [[q + Vector((0, 0, dz)) + nb(q) * dr for q in gor[0]]
              for dz, dr in ((-0.006, -0.004), (0.005, -0.004), (0.011, -0.002), (0.015, -0.007))]
    parts.append(g_smooth_mesh("CollarCloth", collar, K["green"], body, cap_end=False, thick=0.003, outward=True))
    # ---- lâminas da cintura: quatro voltas inteiras, cada uma por baixo da de cima, barra descendo no meio
    lames, lame_obs = [], []
    for k in range(4):
        zt = 1.118 - 0.036 * k

        def lame(u, v, zt=zt):
            a = -math.pi + 2 * math.pi * v
            dip = 0.012 * max(0.0, math.cos(a)) ** 2
            z = zt - (0.046 + dip) * u
            return wk_plate_pt(a, z, 0.015 + 0.006 * u)
        lm, lr = _wk_plate("Lame%d" % k, lame, 4, 64, K["plate"], body)
        lame_obs.append(lm)
        parts.append(lm)
        parts.append(g_pipe("LameRim%d" % k, lr[-1], 0.0045, K["plate"], body, sides=8))
        lames.append(lame)
        # correia de couro e fivela do lado esquerdo
        a = 1.3
        q0, q1 = lame(0.15, 0.5 + a / (2 * math.pi)), lame(0.85, 0.5 + a / (2 * math.pi))
        nr = Vector((math.sin(a), -math.cos(a), 0))
        parts.append(g_pipe("LameStrap%d" % k, [q0 + nr * 0.004, q1 + nr * 0.004], 0.0042, K["lea"], body, sides=6))
        parts += rg_buckle("LameBuckle%d" % k, q0.lerp(q1, 0.4) + nr * 0.003, Vector((0, 0, 1)),
                           Vector((math.cos(a), math.sin(a), 0)), nr, 0.008, 0.007, K["plate_d"], body, r=0.0022)
    # ---- folhas incrustadas, medidas na referência (segmentação das folhas do lado iluminado, espelhadas):
    #      (distância da raiz ao meio da frente, altura, graus da vertical para fora, comprimento, meia largura,
    #      curva). A árvore abre de ±15 cm no fim do peitoral e afina até o babador.
    leaves = []
    TREE = [(0.0, 1.312, 0, 0.034, 0.0075, 0.0)]
    for z, row in ((1.112, ((0.006, 24, 0.078, 0.0118, 0.12), (0.052, 52, 0.078, 0.013, 0.14),
                            (0.098, 76, 0.07, 0.012, 0.1))),
                   (1.165, ((0.006, 20, 0.07, 0.0103, 0.12), (0.047, 46, 0.068, 0.0115, 0.14))),
                   (1.212, ((0.006, 18, 0.062, 0.0095, 0.12), (0.04, 42, 0.056, 0.01, 0.14))),
                   (1.255, ((0.005, 16, 0.052, 0.0085, 0.1), (0.036, 38, 0.042, 0.008, 0.12)))):
        TREE += [(lat * 1.2, z + 0.016 + 0.04 * lat, ang, L * 1.08, W * 1.2, cu) for lat, ang, L, W, cu in row]
    BIB = ((0.006, 1.37, 58, 0.075, 0.0105, -0.05), (0.004, 1.392, 20, 0.045, 0.0085, 0.08),
           (0.004, 1.44, 34, 0.028, 0.0065, 0.05))

    def lay(prefix, bvh, table, off_z=0.0):
        out = []
        for i, (lat, z, ang, L, W, cu) in enumerate(table):
            for s in ((1, -1) if (lat or ang) else (0,)):
                rx = _wk_torso_sec(z)[0] + 0.02
                out += mt_leaf("%s%s%d" % (prefix, "L" if s > 0 else "R", i), bvh, s * min(1.25, lat / rx), z + off_z,
                               s, ang, L, W, K, body, curl=cu)
        return out
    leaves += lay("Leaf", _mt_bvh([bp]), TREE)
    bvh_g = _mt_bvh([gorget])
    leaves += lay("BibLeaf", bvh_g, BIB)
    leaves += mt_leaf("BibLeafTop", bvh_g, 0.0, 1.462, 0, 0, 0.026, 0.006, K, body, curl=0.0)
    for k, lame in enumerate(lames):   # nas lâminas, um par de folhinhas no meio e uma ponta para baixo
        bl = _mt_bvh([lame_obs[k]])
        z = lame(0.25, 0.5).z
        for s in (1, -1):
            leaves += mt_leaf("LameLeaf%d%s" % (k, "L" if s > 0 else "R"), bl, s * 0.3, z, s, 62, 0.03, 0.007,
                              K, body, curl=0.1)
        if k < 2:
            leaves += mt_leaf("LameDrop%d" % k, bl, 0.0, lame(0.15, 0.5).z, 0, 180, 0.026, 0.007, K, body, curl=0.0)
    parts += leaves
    return under, parts


def mithril_pauldron(K, src, body, s):
    """Ombreira élfica: copa grande e três lâminas que descem pelo braço (cada uma por cima da de baixo), a barra
    de cada uma recortada numa ponta de folha virada para a frente; borda dobrada, friso escuro paralelo à barra,
    fileira de rebites na borda da frente da copa. No alto da copa, a crista de três pontas subindo do topo do
    ombro para fora, com folhas incrustadas na base. Malha verde de anéis na axila, por baixo."""
    sn = "L" if s > 0 else "R"
    lames = [(0.05, 2.0, 2.35, 0.04, 0.003), (1.75, 2.6, 2.35, 0.034, 0.004), (2.35, 3.2, 2.35, 0.028, 0.004)]
    parts, leaves = [], []
    vf = 0.8 if s > 0 else 0.2          # coluna da frente (φ > 0 é a frente no lado esquerdo)
    domes = _g_shoulder_dome(src, s, lames, phis=36, rows=10, pull=0.3, cap=0.008, taper=True)
    for k, (rings, dirs, C) in enumerate(domes):
        n, nr = len(rings[0]), len(rings)

        def col(j, u, rings=rings, nr=nr):
            x = u * (nr - 1)
            i0 = min(nr - 2, int(x))
            return rings[i0][j].lerp(rings[i0 + 1][j], x - i0)

        def reach(j):                  # barra em diagonal (desce para a frente) com ponta de folha na frente
            v = j / (n - 1)
            fr = v if s > 0 else 1 - v
            tip = max(0.0, 1 - abs(v - vf) / 0.3) ** 1.8
            return 0.42 + 0.58 * max(0.0, 1 - abs(2 * v - 1) ** 1.5) ** 0.8
        grid = [[col(j, (i / (nr - 1)) * reach(j)) for j in range(n)] for i in range(nr)]
        dgrid = [[dirs[min(nr - 1, int(round(i * reach(j))))][j] for j in range(n)] for i in range(nr)]
        parts.append(g_smooth_mesh("Pauldron%s%d" % (sn, k), grid, K["plate"], body, cap_end=False, closed=False,
                                   thick=0.006, outward=True))
        edge = [grid[-1][j] + dgrid[-1][j] * 0.002 for j in range(n)]
        r0 = 3 if k == 0 else 0
        ends = [[grid[i][sd] + dgrid[i][sd] * 0.002 for i in range(r0, nr)] for sd in (0, n - 1)]
        parts.append(g_pipe("PauldronRim%s%d" % (sn, k), ends[0][::-1] + edge[1:-1] + ends[1], 0.0055, K["plate"],
                            body, sides=8))
        if k == 0:
            fi = nr - 3
            parts.append(g_pipe("PauldronFlute" + sn, [grid[fi][j] + dgrid[fi][j] * 0.0012 for j in range(2, n - 2)],
                                0.002, K["plate_d"], body, sides=6))
            jf = n - 3 if s > 0 else 2  # rebites descendo pela borda da frente
            for i in range(3, nr - 1, 2):
                parts.append(g_bead("PauldronRivet%s%d" % (sn, i), grid[i][jf] + dgrid[i][jf] * 0.003, 0.0045,
                                    K["plate_d"], body))
    # ---- placas de cima: duas telhas menores empilhadas sobre a copa, subindo para o topo do ombro, cada uma
    #      com a barra em ponta de folha para fora e a borda dobrada (o perfil escalonado da referência)
    tops = [(0.05, 1.3, 1.55, 0.05, 0.002), (0.05, 0.75, 1.2, 0.058, 0.002)]
    for k, (rings, dirs, C) in enumerate(_g_shoulder_dome(src, s, tops, phis=30, rows=8, pull=0.3, cap=0.008,
                                                          taper=True)):
        n, nr = len(rings[0]), len(rings)

        def col(j, u, rings=rings, nr=nr):
            x = u * (nr - 1)
            i0 = min(nr - 2, int(x))
            return rings[i0][j].lerp(rings[i0 + 1][j], x - i0)

        def reach(j):
            v = j / (n - 1)
            return 0.62 + 0.38 * max(0.0, 1 - abs(2 * v - 1) / 0.55) ** 1.4
        grid = [[col(j, (i / (nr - 1)) * reach(j)) for j in range(n)] for i in range(nr)]
        dgrid = [[dirs[min(nr - 1, int(round(i * reach(j))))][j] for j in range(n)] for i in range(nr)]
        parts.append(g_smooth_mesh("PauldronTop%s%d" % (sn, k), grid, K["plate"], body, cap_end=False, closed=False,
                                   thick=0.005, outward=True))
        edge = [grid[-1][j] + dgrid[-1][j] * 0.002 for j in range(n)]
        ends = [[grid[i][sd] + dgrid[i][sd] * 0.002 for i in range(3, nr)] for sd in (0, n - 1)]
        parts.append(g_pipe("PauldronTopRim%s%d" % (sn, k), ends[0][::-1] + edge[1:-1] + ends[1], 0.005, K["plate"],
                            body, sides=8))
    return parts + leaves


def mithril_mail(K, src):
    """Malha de anéis verde-oliva no alto do braço (aparece na axila, entre a ombreira e o peitoral)."""
    def keep(c, b, n):
        if not b.startswith("Arm"):
            return False
        sd = 1 if c.x > 0 else -1
        sh = cb_mirror(CB_J["shoulder"], sd)
        return _cb_t(c, sh, cb_mirror(CB_J["elbow"], sd)) < 0.42 and c.z < sh.z - 0.06 and abs(c.x) < abs(sh.x) + 0.01
    mail = cb_piece(src, "ArmMail", keep, 0.011, K["mail"])
    g_subdiv(mail, 2)
    return mail


def _mt_tube(bvh, at, s, u0, u1, NR=14, NP=32, add=lambda t: 0.01):
    """Tubo liso de placa em volta do eixo do braço entre os comprimentos u0 e u1: raio do braço (medido só
    contra ele, alisado e puxado para a média) mais add(t). Devolve (anéis, direções, centros)."""
    rings, dirs, cs = [], [], []
    for i in range(NR + 1):
        t = i / NR
        c, ax = at(u0 + (u1 - u0) * t)
        o = Vector((s, 0, 0))
        o = (o - ax * o.dot(ax)).normalized()
        f = ax.cross(o).normalized()
        rs, ds = [], []
        for j in range(NP):
            ph = 2 * math.pi * j / NP
            d = o * math.cos(ph) + f * math.sin(ph)
            h = bvh.ray_cast(c + d * 0.25, -d)
            rs.append((0.25 - h[3]) if h[0] is not None else 0.045)
            ds.append(d)
        rm = sum(rs) / NP
        for _ in range(2):
            rs = [(rs[j - 1] + 2 * rs[j] + rs[(j + 1) % NP]) / 4 for j in range(NP)]
        rings.append([c + d * (max(r, 0.5 * (r + rm)) + add(t)) for r, d in zip(rs, ds)])
        dirs.append(ds)
        cs.append(c)
    return rings, dirs, cs


def mithril_arm(K, src, body, s):
    """Braço élfico: braçal de cima (tubo liso do fim da ombreira ao cotovelo, com dois frisos de lâmina e rebites
    na frente), cotoveleira em cúpula atrás, duas taças redondas na dobra do cotovelo com a malha verde aparecendo
    dentro, e braçal do antebraço afinando para o pulso, com a borda de cima subindo numa ponta do lado de
    fora, rebites na costura de dentro e um ramo de folhas incrustadas pelo lado de fora. Devolve (placas, malha)."""
    from mathutils.bvhtree import BVHTree
    sn = "L" if s > 0 else "R"
    tmp = cb_piece(src, "ArmProbe" + sn, lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
    bpy.data.objects.remove(tmp, do_unlink=True)
    L1, L2, at, coords, ring = _gb_arm_frame(s)
    parts, mail = [], []
    PF = math.pi / 2 * s               # φ da frente (no braço direito o eixo f aponta para trás)

    def at_phi(rings, dirs, i, ph, out=0.0):
        NP = len(rings[0])
        x = (ph % (2 * math.pi)) / (2 * math.pi) * NP
        j = int(x) % NP
        k = (j + 1) % NP
        return rings[i][j].lerp(rings[i][k], x - int(x)) + dirs[i][j].lerp(dirs[i][k], x - int(x)) * out
    # ---- braçal de cima
    ur, ud, _ = _mt_tube(bvh, at, s, 0.42 * L1, 0.93 * L1, NR=12, add=lambda t: 0.011)
    parts.append(g_smooth_mesh("Rerebrace" + sn, ur, K["plate"], body, cap_end=False, thick=0.005, outward=True))
    for nm, i in (("Top", 0), ("Bot", len(ur) - 1)):
        parts.append(g_pipe("RerebraceRim%s%s" % (sn, nm), [q + d * 0.002 for q, d in zip(ur[i], ud[i])], 0.005,
                            K["plate"], body, sides=8, loop=True))
    for i in (4,):                     # friso de lâmina
        parts.append(g_pipe("RerebraceLine%s%d" % (sn, i), [q + d * 0.0015 for q, d in zip(ur[i], ud[i])], 0.0022,
                            K["plate_d"], body, sides=6, loop=True))
    for i in (2, 5, 8, 10):            # rebites na frente, um pouco para fora
        parts.append(g_bead("RerebraceRivet%s%d" % (sn, i), at_phi(ur, ud, i, PF * 0.55, 0.003), 0.0042,
                            K["plate_d"], body))
    # ---- braçal do antebraço: alarga no cotovelo, afina e abre de leve no pulso
    NR = 16

    def vadd(t):
        return 0.009 + 0.008 * max(0.0, 1 - t / 0.2) ** 2 + 0.005 * max(0.0, (t - 0.88) / 0.12) ** 1.5
    vr, vd, vc = _mt_tube(bvh, at, s, L1 + 0.05 * L2, L1 + 0.9 * L2, NR=NR, add=vadd)
    # borda de cima sobe numa ponta do lado de fora e de trás
    PT = -PF * 0.45
    NP = len(vr[0])
    c0, ax0 = at(L1 + 0.05 * L2)
    for j in range(NP):
        ph = 2 * math.pi * j / NP
        w = max(0.0, math.cos(ph - PT)) ** 6
        if w > 0.01:
            vr[0][j] = vr[0][j] - ax0 * 0.05 * w + vd[0][j] * 0.006 * w
            vr[1][j] = vr[1][j] - ax0 * 0.025 * w + vd[1][j] * 0.003 * w
    vamb = g_smooth_mesh("Vambrace" + sn, vr, K["plate"], body, cap_end=False, thick=0.005, outward=True)
    parts.append(vamb)
    for nm, i in (("Top", 0), ("Cuff", NR)):
        parts.append(g_pipe("VambraceRim%s%s" % (sn, nm), [q + d * 0.002 for q, d in zip(vr[i], vd[i])], 0.005,
                            K["plate"], body, sides=8, loop=True))
    for i in (3, 7, 11, 14):           # rebites na costura de dentro
        parts.append(g_bead("VambraceRivet%s%d" % (sn, i), at_phi(vr, vd, i, math.pi, 0.003), 0.004, K["plate_d"], body))
    # folhas pelo lado de fora: ramo subindo do pulso para o cotovelo, pares alternados e uma no topo
    bv = _mt_bvh([vamb])
    PO = PF * 0.2                      # do lado de fora, um pouco para a frente (aparece de frente)
    for q, (i, sg, L, W) in enumerate(((13, 1, 0.04, 0.008), (11, -1, 0.042, 0.0085), (9, 1, 0.044, 0.009),
                                      (7, -1, 0.044, 0.009), (5, 1, 0.042, 0.0085), (3, -1, 0.038, 0.008))):
        p0 = at_phi(vr, vd, i, PO)
        upv = (at_phi(vr, vd, i - 2, PO) - p0).normalized()
        side = (at_phi(vr, vd, i, PO + 0.35 * sg) - p0).normalized()
        parts += mt_leaf_at("ArmLeaf%s%d" % (sn, q), bv, p0 + side * 0.006, (upv + side * 0.75).normalized(), side,
                            L, W, K, body, curl=0.15)
    p0 = at_phi(vr, vd, 2, PO)
    parts += mt_leaf_at("ArmLeafTop" + sn, bv, p0, (at_phi(vr, vd, 0, PO) - p0).normalized(),
                        (at_phi(vr, vd, 2, PO + 0.3) - p0).normalized(), 0.036, 0.0075, K, body, curl=0.0)
    # ---- cotoveleira: cúpula atrás do cotovelo com rebite no meio
    el = cb_mirror(CB_J["elbow"], s)
    n0 = (Vector((0, 1, 0)) * 0.85 + Vector((s, 0, 0)) * 0.5).normalized()
    a1 = n0.cross(Vector((0, 0, 1))).normalized()
    a2 = n0.cross(a1).normalized()

    def rad_el(d, extra):
        h = bvh.ray_cast(el + d * 0.25, -d)
        return ((0.25 - h[3]) if h[0] is not None else 0.045) + extra
    cop, cdir = [], []
    for i in range(1, 8):
        al = 1.0 * i / 7
        row, drow = [], []
        for j in range(24):
            ph = 2 * math.pi * j / 24
            d = (n0 * math.cos(al) + (a1 * math.cos(ph) + a2 * math.sin(ph)) * math.sin(al)).normalized()
            row.append(el + d * rad_el(d, 0.015))
            drow.append(d)
        cop.append(row)
        cdir.append(drow)
    tip = el + n0 * rad_el(n0, 0.018)
    parts.append(g_smooth_mesh("Couter" + sn, [[tip] * 24] + cop, K["plate"], body, cap_end=False, thick=0.005,
                               outward=True))
    parts.append(g_pipe("CouterRim" + sn, [q + d * 0.002 for q, d in zip(cop[-1], cdir[-1])], 0.005, K["plate"], body,
                        sides=8, loop=True))
    parts.append(g_bead("CouterBoss" + sn, tip + n0 * 0.002, 0.0075, K["plate_d"], body))
    # ---- taças da dobra: duas aberturas redondas na frente (fim do braçal de cima e começo do de baixo), aro
    #      grosso de placa e a malha verde no fundo, com os anéis desenhados em linha
    for nm, u in (("Up", 0.9 * L1), ("Dn", L1 + 0.1 * L2)):
        c, ax = at(u)
        o = Vector((s, 0, 0))
        o = (o - ax * o.dot(ax)).normalized()
        f = ax.cross(o).normalized()
        d = (o * math.cos(PF * 1.12) + f * math.sin(PF * 1.12)).normalized()   # frente, um pouco para dentro
        h = bvh.ray_cast(c + d * 0.25, -d)
        q = (h[0] if h[0] is not None else c + d * 0.04)
        e1 = ax.cross(d).normalized()
        e2 = d.cross(e1).normalized()
        R0 = 0.019

        def circ(rr, out, n=20):
            return [q + d * out + (e1 * math.cos(2 * math.pi * j / n) + e2 * math.sin(2 * math.pi * j / n)) * rr
                    for j in range(n)]
        disc = [[x - d * 0.003 * (1 - k * k) for x in circ(R0 * k, 0.019)] for k in (0.02, 0.5, 1.0)]
        mail.append(g_smooth_mesh("ElbowMail%s%s" % (sn, nm), disc, K["mail"], body, cap_end=False, thick=0.002))
        parts.append(g_pipe("ElbowCup%s%s" % (sn, nm), circ(R0 + 0.004, 0.022), 0.0065, K["plate"], body, sides=8,
                            loop=True))
        parts.append(g_smooth_mesh("ElbowCupWall%s%s" % (sn, nm), [circ(R0 + 0.004, 0.008), circ(R0 + 0.004, 0.022)],
                                   K["plate"], body, cap_end=False, thick=0.003))
        for k in range(3):
            rr = R0 * (0.35 + 0.28 * k)
            mail.append(g_pipe("ElbowMailRing%s%s%d" % (sn, nm, k),
                               [x - d * 0.003 * (1 - (rr / R0) ** 2) for x in circ(rr, 0.0202, 18)], 0.0014,
                               K["mail_d"], body, sides=5, loop=True))
    return parts, mail


def mithril_skirt(K, src, body):
    """Cintura para baixo: em cada coxa uma escarcela grande pendurada da última lâmina, com a borda de dentro
    abrindo em arco no meio da frente, borda dobrada, frisos descendo e folhas incrustadas no alto; no arco, o
    painel de malha verde com debrum verde-água e, por baixo, o pano oliva caindo em ponta entre as pernas;
    atrás, culote de duas lâminas; nas coxas, coxeiras de placa (casca com pele) com duas lâminas no alto e
    rebites. Devolve (escarcelas, culote, painel do meio, pano, coxeiras, debruns das coxeiras)."""
    tas, mid, cloth = [], [], []
    for sn, s in (("L", 1), ("R", -1)):
        def plate(u, v, s=s):
            a_in = 0.2 + 0.32 * u ** 1.3            # arco do meio: a borda de dentro abre descendo
            a = (a_in + (2.7 - a_in) * v) * s       # da frente até as costas, por fora do culote
            zb = 0.7 + 0.085 * v ** 1.8             # barra em curva: sobe para o lado de fora e para trás
            z = 0.968 + (zb - 0.968) * u
            return _wk_hip_pt(a, z, 0.032 + 0.012 * u)
        ob, rr = _wk_plate("Tasset" + sn, plate, 14, 44, K["plate"], body, thick=0.005)
        tas.append(ob)
        edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
        tas.append(g_pipe("TassetRim" + sn, edge, 0.0055, K["plate"], body, sides=8))
        for k, v in enumerate((0.26, 0.38, 0.5, 0.64, 0.78)):
            tas.append(g_pipe("TassetFlute%s%d" % (sn, k), [plate(u, v) + Vector((plate(u, v).x, plate(u, v).y, 0))
                                                           .normalized() * 0.0015 for u in (0.5, 0.65, 0.8, 0.95)],
                              0.002, K["plate_d"], body, sides=6))
        for v in (0.06, 0.3, 0.55, 0.8):        # rebites onde a escarcela pendura da lâmina
            q = plate(0.06, v)
            tas.append(g_bead("TassetRivet%s%d" % (sn, int(v * 10)), q + Vector((q.x, q.y, 0)).normalized() * 0.004,
                              0.0045, K["plate_d"], body))
        bv = _mt_bvh([ob])
        for q, (u, v, L, W) in enumerate(((0.3, 0.08, 0.05, 0.0095), (0.24, 0.19, 0.054, 0.01), (0.36, 0.27, 0.05, 0.0095),
                                          (0.2, 0.34, 0.044, 0.0085))):
            p0 = plate(u, v)
            upv = (plate(u - 0.12, v) - p0).normalized()
            side = (plate(u, v + 0.04) - p0).normalized()
            tas += mt_leaf_at("TassetLeaf%s%d" % (sn, q), bv, p0, (upv + side * 0.7).normalized(), side, L, W, K, body,
                              curl=0.12)
    # ---- culote atrás
    culet = firstplate_culet(dict(K, lining=K["plate"]), body)
    # ---- fundo do arco: malha escura (sem debrum e sem pano), um pouco atrás das escarcelas, da última lâmina
    #      até o meio da coxa e alargando com o arco; anéis em zigue-zague quase da mesma cor
    def panel(u, v):
        z = 0.962 - (0.962 - 0.8) * u
        ut = (0.968 - z) / (0.968 - 0.7)
        half = 0.2 + 0.32 * ut ** 1.3 + 0.1
        return _wk_hip_pt(-half + 2 * half * v, z, 0.022)
    pm, pr = _wk_plate("MailPanel", panel, 8, 16, K["mail_dk"], body, thick=0.003)
    mid.append(pm)
    for k in range(5):
        zz = []
        for j in range(21):
            u = 0.1 + 0.2 * k + (0.04 if j % 2 else -0.04)
            q = panel(u, 0.1 + 0.8 * j / 20)
            zz.append(q + Vector((q.x, q.y, 0)).normalized() * 0.002)
        mid.append(g_pipe("MailZig%d" % k, zz, 0.0014, K["mail_dd"], body, sides=5))
    # ---- coxeiras: casca de placa na frente e no lado de fora da coxa, do quadril a acima do joelho
    shells, trims = [], []
    knee_z = CB_J["knee"].z
    for sn, s in (("L", 1), ("R", -1)):
        def keep(c, b, n, s=s):
            hip = cb_mirror(CB_J["hip"], s)
            d = Vector((c.x - hip.x, c.y - hip.y, 0)).normalized()
            return b.startswith("Leg") and c.x * s > 0 and knee_z + 0.03 < c.z < (0.8 if d.x * s > -0.3 else 0.7)
        sh = cb_piece(src, "Cuisse" + sn, keep, 0.016, K["plate"])
        g_subdiv(sh, 2)
        shells.append(sh)
        trims += g_border_pipes(sh, "CuisseRim" + sn, 0.0055, K["plate"], body, smooth=6, step=0.01)
        from mathutils.bvhtree import BVHTree
        bvh = BVHTree.FromPolygons([v.co.copy() for v in sh.data.vertices], [tuple(p.vertices) for p in sh.data.polygons])
        hip = cb_mirror(CB_J["hip"], s)
        kn = cb_mirror(CB_J["knee"], s)
        for k, z in enumerate((0.74, 0.7)):     # lâminas do alto da coxa
            c = hip.lerp(kn, (hip.z - z) / (hip.z - kn.z))
            line = []
            for j in range(15):
                a = -1.4 + 2.8 * j / 14         # da frente para fora
                d = Vector((math.sin(a) * s, -math.cos(a), 0))
                h = bvh.ray_cast(Vector((c.x, c.y, z)) + d * 0.3, -d)[0]
                if h is not None:
                    line.append(h + d * 0.0015)
            if len(line) > 2:
                trims.append(g_pipe("CuisseLame%s%d" % (sn, k), line, 0.0022, K["plate_d"], body, sides=6))
        for k, z in enumerate((0.66, 0.58, 0.5)):  # rebites na costura de fora
            c = hip.lerp(kn, (hip.z - z) / (hip.z - kn.z))
            d = Vector((s, -0.2, 0)).normalized()
            h = bvh.ray_cast(Vector((c.x, c.y, z)) + d * 0.3, -d)[0]
            if h is not None:
                trims.append(g_bead("CuisseRivet%s%d" % (sn, k), h + d * 0.003, 0.004, K["plate_d"], body))
    return tas, culet, mid, cloth, shells, trims


def build_a_mithril():
    """Placa élfica de mithril (tier III). Rodada 1: tronco (peitoral, costal, gorjal com babador, lâminas da
    cintura e folhas incrustadas); braços e pernas com o gibão verde-escuro até as próximas peças."""
    style = "a_mithril"
    P, R = g_rig(style)
    M = g_mats()
    K = mithril_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["joint"])
    g_skinned_pants(src, M["pants"])
    under, parts = mithril_torso(K, src, body)
    shoulder = mithril_pauldron(K, src, body, 1) + mithril_pauldron(K, src, body, -1)
    tas, culet, mid, fcloth, cuis, cuis_trim = mithril_skirt(K, src, body)
    arms, email = [], []
    for sd in (1, -1):
        a_, m_ = mithril_arm(K, src, body, sd)
        arms += a_
        email += m_
    def upper_t(c):
        sd = 1 if c.x > 0 else -1
        return _cb_t(c, cb_mirror(CB_J["shoulder"], sd), cb_mirror(CB_J["elbow"], sd))
    # manga toda em aço escuro: fica coberta pelos braçais; se aparecer numa fresta, lê como junta
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["joint"])
    g_subdiv(sleeves)
    mithril_mail(K, src)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 1.0),
                             (arms + email, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (tas, "fn", _wk_tasset_w, 1.0), (mid, "fn", _wk_center_w, 1.0),
                             (fcloth, "fn", _wk_cloth_w, 1.0), (culet, "fn", _gb_skirt_w, 1.0),
                             (cuis_trim, "vert", ("LegL", "LegR"), 1.0)])
    join_objs("Mithril", parts + shoulder + arms + email + tas + mid + fcloth + culet + cuis_trim)
    g_export_skinned(style)


# ------------------------------------------------------------------ Placas Astrais (cavaleiro celeste)
def celestial_mats():
    return dict(
        plate=gm("cs_gold", "#A88433", 0.38, 0.8), plate_d=gm("cs_gold_d", "#5E4216", 0.45, 0.8),
        groove=gm("cs_groove", "#3A2610", 0.6, 0.6), dial=gm("cs_dial", "#C4A256", 0.38, 0.8),
        joint=gm("cs_joint", "#4A3720", 0.5, 0.5),
        void=mat("cs_void_flat", hexc("#06050C"), 0.9, 0.0),
        cloth=gm("cs_cloth", "#263075", 0.85), night=gm("cs_night", "#0E1236", 0.9),
        sky=gm("cs_sky", "#1A2560", 0.9), sun=gm("cs_sun", "#D2A23C", 0.35, 0.8),
    )


def _cs_mantle_w(p):
    """Peso do manto: no meio vai com o tronco; passando do pé do pescoço para o ombro passa para o braço do seu
    lado (por cima da ombreira, que vai inteira com o braço). Sem isso o braço puxava o pano do peito."""
    t = max(0.0, min(1.0, (abs(p.x) - 0.11) / 0.08))
    t = t * t * (3 - 2 * t)
    return {"Body": 1.0 - t, ("ArmL" if p.x > 0 else "ArmR"): t}


def _cs_cape_w(p):
    """Peso da capa: no alto igual ao manto (o pano dos ombros vai com o braço); descendo passa em parte para as
    pernas, mais para a do seu lado, para a perna de trás na passada não furar o pano."""
    w = _cs_mantle_w(p)
    k = max(0.0, min(1.0, (p.z - 1.12) / 0.2))
    w = {b: (v if b == "Body" else v * k) for b, v in w.items()}
    w["Body"] = 1.0 - sum(v for b, v in w.items() if b != "Body")
    leg = max(0.0, min(1.0, (0.95 - p.z) / 0.45)) * 0.55
    left = max(0.0, min(1.0, 0.5 + p.x / 0.22))
    w = {b: v * (1 - leg) for b, v in w.items()}
    w["LegL"] = leg * left
    w["LegR"] = leg * (1 - left)
    return {b: v for b, v in w.items() if v > 1e-4}


def celestial_haute(K, body, s):
    """Placa em pé no alto do ombro, de frente (como na referência): chapa larga em cima da linha do ombro, um
    pouco atrás do meio, abaulada para a frente, subindo até a altura do queixo com o topo arredondado; borda
    dobrada e um friso paralelo ao topo. A base fica escondida sob o manto."""
    sn = "L" if s > 0 else "R"
    NV, NU = 20, 8

    def pt(u, v):
        x = s * (0.085 + 0.15 * v)
        top = 1.47 + 0.085 * math.sin(math.pi * (0.15 + 0.85 * v)) ** 0.7
        z = 1.41 + (top - 1.41) * u
        y = 0.035 - 0.022 * math.sin(math.pi * v) - 0.012 * u
        return Vector((x + s * 0.02 * u, y, z))
    grid = [[pt(i / NU, j / NV) for j in range(NV + 1)] for i in range(NU + 1)]
    parts = [g_smooth_mesh("Haute" + sn, grid, K["plate"], body, cap_end=False, closed=False, thick=0.005,
                           outward=True)]
    edge = [pt(i / NU, 0.0) for i in range(NU, 2, -1)] + [pt(1.0, j / NV) for j in range(NV + 1)] +            [pt(i / NU, 1.0) for i in range(NU - 1, 2, -1)]
    parts.append(g_pipe("HauteRim" + sn, edge, 0.005, K["plate"], body, sides=8))
    parts.append(g_pipe("HauteLine" + sn, [pt(0.8, j / NV) + Vector((0, -0.004, 0)) for j in range(3, NV - 2)],
                        0.002, K["plate_d"], body, sides=6))
    return parts


def celestial_mantle(K, body, objs):
    """Manto azul sobre os ombros: casca de pano que desce do pé do gorjal e assenta por cima das ombreiras
    (raio medido por raios horizontais contra corpo e placas, nunca encolhendo ao descer, alisado). Na frente a
    barra cruza o alto do peito por cima do mostrador; nos lados cobre a copa da ombreira; atrás desce até as
    escápulas, onde a capa vai pendurar. Broche de sol no peito, do lado direito."""
    bvh = _mt_bvh(objs)
    NA, NU = 72, 12

    def hem(a):
        x = abs(math.atan2(math.sin(a), math.cos(a)))
        if x < 1.5:                    # frente: arco raso no peito, descendo para os ombros
            return 1.425 - 0.07 * (x / 1.5) ** 1.6
        return 1.355 + 0.02 * min(1.0, (x - 1.5) / 1.0)              # lado e costas: a capa cobre as costas
    R = []
    for j in range(NA):
        a = 2 * math.pi * j / NA
        d = Vector((math.sin(a), -math.cos(a), 0))
        col, rp = [], 0.0
        for i in range(NU + 1):
            z = 1.49 + (hem(a) - 1.49) * (i / NU)
            c = Vector((0, 0.012, z))
            h = bvh.ray_cast(c + d * 0.5, -d)
            r = (0.5 - h[3] if h[0] is not None else 0.1) + 0.016
            rp = max(rp, r)
            col.append(rp)
        R.append(col)
    for _ in range(4):                 # alisa em volta, sem entrar nas placas
        S = [[(R[j - 1][i] + 2 * R[j][i] + R[(j + 1) % NA][i]) / 4 for i in range(NU + 1)] for j in range(NA)]
        R = [[max(R[j][i], S[j][i]) for i in range(NU + 1)] for j in range(NA)]
    rings = []
    for i in range(NU + 1):
        row = []
        for j in range(NA):
            a = 2 * math.pi * j / NA
            z = 1.49 + (hem(a) - 1.49) * (i / NU)
            row.append(Vector((math.sin(a) * R[j][i], 0.012 - math.cos(a) * R[j][i], z)))
        rings.append(row)
    # o manto usa o mesmo pano do céu (cs_sky): no alto o shader pinta o azul liso e desce em degradê até o céu
    parts = [g_smooth_mesh("Mantle", rings, K["sky"], body, cap_end=False, thick=0.004, outward=True)]
    parts.append(g_pipe("MantleHem", rings[-1], 0.004, K["sky"], body, sides=8, loop=True))
    parts.append(g_pipe("MantleNeck", rings[0], 0.005, K["sky"], body, sides=8, loop=True))
    # ---- capa de céu estrelado: continua o manto dos lados e atrás, aberta na frente (a borda da frente desce
    #      em curva do ombro), larga e caindo até a canela; raio medido contra corpo, braços e placas, alargando
    #      para baixo. O pano recebe o céu animado (cs_sky, GearFx).
    A0, NC, NR = 1.2, 72, 26

    def rb(a):                         # raio do manto na barra, interpolado entre as colunas
        x = (a % (2 * math.pi)) / (2 * math.pi) * NA
        j = int(x) % NA
        return R[j][NU] + (R[(j + 1) % NA][NU] - R[j][NU]) * (x - int(x))

    def fold(a):                       # perfil das dobras: cristas cheias e vales fundos, seis em volta
        v = math.sin(6 * (a - A0) + 0.6)
        return math.copysign(abs(v) ** 0.6, v)

    def chem(x, a):                    # barra da capa; x = distância angular ao meio da frente
        zb = 0.4 - 0.03 * fold(a)      # a crista da dobra cai mais que o vale: barra irregular
        if x < 2.0:
            return hem(x) - (hem(x) - zb) * ((x - A0) / (2.0 - A0)) ** 0.55
        return zb
    cape = []
    for j in range(NC + 1):
        a = A0 + (2 * math.pi - 2 * A0) * j / NC
        x = abs(math.atan2(math.sin(a), math.cos(a)))
        d = Vector((math.sin(a), -math.cos(a), 0))
        zt, zb = hem(a), chem(x, a)
        col, rp = [], rb(a)
        for i in range(NR + 1):
            t = i / NR
            z = zt + (zb - zt) * t
            h = bvh.ray_cast(Vector((0, 0.012, z)) + d * 0.6, -d)
            r = (0.6 - h[3] if h[0] is not None else 0.1) + 0.022
            rp = max(rp, r)
            fl = 0.055 * t ** 1.2 * (0.5 + 0.5 * max(0.0, -math.cos(a)))
            fl += 0.058 * t ** 0.8 * fold(a) * min(1.0, (x - A0) / 0.4)   # dobras desde as escápulas
            col.append(Vector((math.sin(a) * (rp + fl), 0.012 - math.cos(a) * (rp + fl), z)))
        cape.append(col)
    for _ in range(1):                 # alisa entre colunas (menos a fileira de cima, presa no manto)
        cape = [[cape[j][i] if (i == 0 or j in (0, NC)) else
                 (cape[j - 1][i] + cape[j][i] * 2 + cape[j + 1][i]) / 4 for i in range(NR + 1)] for j in range(NC + 1)]
    grid = [[cape[j][i] for j in range(NC + 1)] for i in range(NR + 1)]
    parts.append(g_smooth_mesh("Cape", grid, K["sky"], body, cap_end=False, closed=False, thick=0.004, outward=True))
    edge = [cape[0][i] for i in range(NR, -1, -1)][::-1]
    parts.append(g_pipe("CapeEdgeR", [cape[0][i] for i in range(NR + 1)], 0.004, K["sky"], body, sides=8))
    parts.append(g_pipe("CapeEdgeL", [cape[NC][i] for i in range(NR + 1)], 0.004, K["sky"], body, sides=8))
    parts.append(g_pipe("CapeHem", [cape[j][NR] for j in range(NC + 1)], 0.0045, K["sky"], body, sides=8))
    # broche de sol: aro e doze raios, os de baixo mais longos (medido: centro a 8 cm do meio, 1,40 m)
    mb = _mt_bvh([parts[0]])
    c = _cs_on(mb, Vector((-0.085, -0.3, 1.438)), out=0.004)
    n = (c - Vector((0, 0.012, c.z))).normalized()
    e1 = Vector((0, 0, 1)).cross(n).normalized()
    e2 = n.cross(e1).normalized()
    parts.append(g_pipe("SunRing", [c + (e1 * math.cos(t) + e2 * math.sin(t)) * 0.02
                                    for t in (2 * math.pi * k / 20 for k in range(20))], 0.0035, K["sun"], body,
                        sides=8, loop=True))
    for k in range(12):
        t = 2 * math.pi * k / 12 + math.pi / 2
        L = 0.048 if abs(math.sin(t) + 1) < 0.3 else (0.042 if k % 2 == 0 else 0.034)
        dv = e1 * math.cos(t) + e2 * math.sin(t)
        parts.append(g_pipe("SunRay%d" % k, [c + dv * 0.025, c + dv * L - n * 0.002], 0.0026, K["sun"], body,
                            sides=6))
    return parts


def _cs_on(bvh, p, d=Vector((0, -1, 0)), out=0.0):
    """Projeta p na malha do bvh pela direção -d (vindo de fora) e afasta out metros pela normal."""
    h = bvh.ray_cast(p + d * 0.3, -d)
    if h[0] is None:
        return p
    return h[0] + h[1].normalized() * out


def celestial_torso(K, src, body):
    """Tronco do cavaleiro celeste: casca de baixo em bronze escuro, peitoral dourado liso com quilha leve,
    costal fechado, gorjal alto (colar em volta do pescoço e babador curto no alto do peito), no esterno o
    mostrador de sol (anel com raios em pé em volta de um buraco negro), sulcos curvos descendo dos lados do
    mostrador até o meio da cintura e três lâminas da cintura em V. Devolve (casca, peças)."""
    def under_keep(c, b, n):
        return not (b.startswith("Arm") or b.startswith("Elbow") or b.startswith("Knee")) and 0.86 <= c.z < 1.52
    under = cb_piece(src, "Under", under_keep, 0.006, K["joint"])
    g_subdiv(under, 2)
    parts = []
    # ---- peitoral
    A = 1.3

    def breast(u, v):
        a = -A + 2 * A * v
        top = 1.48 - 0.06 * (abs(a) / A) ** 4
        bot = 1.1 + 0.02 * min(1.0, abs(a) / 1.2) ** 2
        z = top + (bot - top) * u
        bulge = 0.003 * math.sin(math.pi * min(1.0, u * 1.1)) * max(0.0, math.cos(a)) ** 1.5
        return wk_plate_pt(a, z, 0.016 + bulge, keel=0.012, fr_max=1.03)
    bp, br = _wk_plate("Breastplate", breast, 16, 40, K["plate"], body)
    parts.append(bp)
    parts.append(g_pipe("BreastRim", br[-1], 0.006, K["plate"], body, sides=8))
    # ---- costal
    B = math.pi - 1.25

    def back(u, v):
        a = math.pi - B + 2 * B * v
        zt = 1.48 - 0.07 * abs(2 * v - 1) ** 4
        z = zt + (1.1 - zt) * u
        return wk_plate_pt(a, z, 0.017)
    bk, bkr = _wk_plate("Backplate", back, 12, 30, K["plate"], body)
    parts.append(bk)
    parts.append(g_pipe("BackRim", bkr[-1], 0.006, K["plate"], body, sides=8))
    parts.append(g_pipe("BackKeel", [back(u, 0.5) + Vector((0, 0.0015, 0)) for u in (0.1, 0.4, 0.7, 0.97)], 0.0025,
                        K["plate_d"], body, sides=6))
    # ---- gorjal: colar alto em volta do pescoço e babador curto, barra em arco raso no alto do peito
    NG = 48

    def gz_bot(a):
        x = min(1.0, abs(a) / 1.2)
        return 1.405 + (1.452 - 1.405) * x ** 1.4 - 0.03 * abs(math.sin(a)) ** 6

    def gor_pt(j, u):
        a = math.atan2(math.sin(2 * math.pi * j / NG), math.cos(2 * math.pi * j / NG))
        if u <= 0.45:                  # colar mais alto que o élfico: sobe até sob o queixo
            t = u / 0.45
            z = 1.6 - (1.6 - 1.488) * t
            rx = 0.086 + (0.104 - 0.086) * t ** 1.6
            ry = 0.08 + (0.098 - 0.08) * t ** 1.6
            return Vector((math.sin(a) * rx, 0.012 - math.cos(a) * ry, z))
        t = (u - 0.45) / 0.55
        z = 1.472 + (gz_bot(a) - 1.472) * t
        q = wk_plate_pt(a, z, 0.024 + 0.003 * (1 - t), keel=0.012, fr_max=1.03)
        if t < 0.34:
            c = Vector((math.sin(a) * 0.104, 0.012 - math.cos(a) * 0.098, 1.488))
            q = c.lerp(q, 0.55 + 0.45 * (t / 0.34))
        return q
    US = [0.0, 0.12, 0.24, 0.36, 0.45, 0.52, 0.62, 0.74, 0.87, 1.0]
    gor = [[gor_pt(j, u) for j in range(NG)] for u in US]
    parts.append(g_smooth_mesh("Gorget", gor, K["plate"], body, cap_end=False, thick=0.006, outward=True))
    parts.append(g_pipe("GorgetRim", gor[0], 0.0045, K["plate"], body, sides=8, loop=True))
    nb = (lambda q: Vector((q.x, q.y - 0.012, 0)).normalized())
    parts.append(g_pipe("GorgetHem", [q + nb(q) * 0.002 for q in gor[-1]], 0.0055, K["plate"], body, sides=8,
                        loop=True))
    for i in (2, 4):                   # frisos de lâmina no colar
        parts.append(g_pipe("GorgetLine%d" % i, [q + nb(q) * 0.0025 for q in gor[i]], 0.002, K["plate_d"], body,
                            sides=6, loop=True))
    # ---- mostrador de sol no esterno, medido na referência (centro 1,32 m, aro 8 cm, buraco 2,8 cm): um funil
    #      que afunda do aro alto até o buraco negro, com nervuras em raio na parede do funil
    bvh = _mt_bvh([bp])
    C = Vector((0.0, -0.3, 1.322))
    e1, e2 = Vector((1, 0, 0)), Vector((0, 0, 1))
    R_HOLE, R_IN, R_OUT, ND = 0.028, 0.032, 0.078, 48

    def cone(r):                       # altura da parede do funil sobre o peitoral
        return 0.0035 + 0.0075 * max(0.0, (r - R_IN) / (R_OUT - R_IN)) ** 0.8

    def dial_pt(r, th, out):
        return _cs_on(bvh, C + (e1 * math.cos(th) + e2 * math.sin(th)) * r, out=out)
    rings = [[dial_pt(r, 2 * math.pi * j / ND, cone(r)) for j in range(ND)]
             for r in (R_IN, 0.042, 0.054, 0.066, R_OUT)]
    rings.append([dial_pt(R_OUT + 0.008, 2 * math.pi * j / ND, 0.002) for j in range(ND)])
    parts.append(g_smooth_mesh("Dial", rings, K["dial"], body, cap_end=False, thick=0.003, outward=True))
    parts.append(g_pipe("DialRimOut", [dial_pt(R_OUT + 0.002, 2 * math.pi * j / ND, cone(R_OUT) + 0.001)
                                       for j in range(ND)], 0.0055, K["plate"], body, sides=8, loop=True))
    parts.append(g_pipe("DialRimIn", [dial_pt(R_IN, 2 * math.pi * j / ND, cone(R_IN) + 0.001) for j in range(ND)],
                        0.0035, K["plate_d"], body, sides=8, loop=True))
    for k in range(24):                # nervuras em raio na parede do funil
        th = 2 * math.pi * k / 24 + math.pi / 2
        parts.append(g_pipe("DialRay%d" % k, [dial_pt(r, th, cone(r) + 0.0012) for r in (0.037, 0.05, 0.064, 0.073)],
                            0.0024, K["plate_d"], body, sides=6))
    hole = [[dial_pt(R_HOLE * f, 2 * math.pi * j / ND, cone(R_IN) - 0.001 * (1 - f)) for j in range(ND)]
            for f in (0.02, 0.5, 1.0)]
    parts.append(g_smooth_mesh("DialHole", hole, K["void"], body, cap_end=False, thick=0.002, outward=True))
    # ---- sulcos curvos: saem dos lados do mostrador e descem convergindo para o meio da cintura
    for s in (1, -1):
        for k, (a0, z0, a1) in enumerate(((0.62, 1.29, 0.06), (0.9, 1.31, 0.12), (1.16, 1.33, 0.2))):
            line = []
            for i in range(14):
                t = i / 13
                a = a1 + (a0 - a1) * (1 - t) ** 1.6
                z = z0 + (1.125 - z0) * t
                line.append(_cs_on(bvh, wk_plate_pt(s * a, z, 0.016, keel=0.012, fr_max=1.03),
                                   d=Vector((math.sin(s * a), -math.cos(a), 0)), out=0.0012))
            parts.append(g_pipe("BreastGroove%s%d" % ("L" if s > 0 else "R", k), line, 0.0022, K["groove"], body,
                                sides=6))
    # ---- lâminas da cintura: três voltas em V na frente
    for k in range(3):
        zt = 1.118 - 0.04 * k

        def lame(u, v, zt=zt):
            a = -math.pi + 2 * math.pi * v
            dip = 0.022 * max(0.0, math.cos(a)) ** 3
            z = zt - (0.05 + dip) * u
            return wk_plate_pt(a, z, 0.015 + 0.006 * u)
        lm, lr = _wk_plate("Lame%d" % k, lame, 4, 64, K["plate"], body)
        parts.append(lm)
        parts.append(g_pipe("LameRim%d" % k, lr[-1], 0.0045, K["plate"], body, sides=8))
        parts.append(g_pipe("LameLine%d" % k, [q + Vector((q.x, q.y, 0)).normalized() * 0.0014
                                                for q in lr[1]], 0.0018, K["plate_d"], body, sides=6))
    return under, parts


def celestial_arm(K, src, body, s):
    """Braço do cavaleiro celeste: braçal de cima liso com dois frisos de lâmina; cotoveleira em cúpula atrás do
    cotovelo com a aleta grande em ponta virada para fora e para trás (o recorte anguloso da referência), com
    nervura no meio; braçal do antebraço comprido, abrindo de leve no cotovelo e no pulso, a borda de cima
    subindo numa ponta do lado de fora, friso na costura de fora."""
    from mathutils.bvhtree import BVHTree
    sn = "L" if s > 0 else "R"
    tmp = cb_piece(src, "ArmProbe" + sn, lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow")) and c.x * s > 0)
    bvh = BVHTree.FromPolygons([v.co.copy() for v in tmp.data.vertices], [tuple(p.vertices) for p in tmp.data.polygons])
    bpy.data.objects.remove(tmp, do_unlink=True)
    L1, L2, at, coords, ring = _gb_arm_frame(s)
    parts = []
    PF = math.pi / 2 * s
    # ---- braçal de cima
    ur, ud, _ = _mt_tube(bvh, at, s, 0.42 * L1, 0.9 * L1, NR=12, add=lambda t: 0.011)
    parts.append(g_smooth_mesh("Rerebrace" + sn, ur, K["plate"], body, cap_end=False, thick=0.005, outward=True))
    for nm, i in (("Top", 0), ("Bot", len(ur) - 1)):
        parts.append(g_pipe("RerebraceRim%s%s" % (sn, nm), [q + d * 0.002 for q, d in zip(ur[i], ud[i])], 0.005,
                            K["plate"], body, sides=8, loop=True))
    for i in (4, 8):
        parts.append(g_pipe("RerebraceLine%s%d" % (sn, i), [q + d * 0.0015 for q, d in zip(ur[i], ud[i])], 0.002,
                            K["plate_d"], body, sides=6, loop=True))
    # ---- braçal do antebraço
    NR = 16

    def vadd(t):
        return 0.009 + 0.009 * max(0.0, 1 - t / 0.2) ** 2 + 0.008 * max(0.0, (t - 0.8) / 0.2) ** 1.5
    vr, vd, vc = _mt_tube(bvh, at, s, L1 + 0.04 * L2, L1 + 0.92 * L2, NR=NR, add=vadd)
    PT = -PF * 0.45
    NP = len(vr[0])
    c0, ax0 = at(L1 + 0.04 * L2)
    for j in range(NP):
        ph = 2 * math.pi * j / NP
        w = max(0.0, math.cos(ph - PT)) ** 6
        if w > 0.01:
            vr[0][j] = vr[0][j] - ax0 * 0.055 * w + vd[0][j] * 0.007 * w
            vr[1][j] = vr[1][j] - ax0 * 0.028 * w + vd[1][j] * 0.0035 * w
    parts.append(g_smooth_mesh("Vambrace" + sn, vr, K["plate"], body, cap_end=False, thick=0.005, outward=True))
    for nm, i in (("Top", 0), ("Cuff", NR)):
        parts.append(g_pipe("VambraceRim%s%s" % (sn, nm), [q + d * 0.002 for q, d in zip(vr[i], vd[i])], 0.005,
                            K["plate"], body, sides=8, loop=True))

    def at_phi(rings, dirs, i, ph, out=0.0):
        n = len(rings[0])
        x = (ph % (2 * math.pi)) / (2 * math.pi) * n
        j = int(x) % n
        k = (j + 1) % n
        return rings[i][j].lerp(rings[i][k], x - int(x)) + dirs[i][j].lerp(dirs[i][k], x - int(x)) * out
    parts.append(g_pipe("VambraceSeam" + sn, [at_phi(vr, vd, i, 0.0, 0.0015) for i in range(2, NR - 1)], 0.002,
                        K["plate_d"], body, sides=6))
    # ---- cotoveleira: cúpula atrás do cotovelo
    el = cb_mirror(CB_J["elbow"], s)
    n0 = (Vector((0, 1, 0)) * 0.85 + Vector((s, 0, 0)) * 0.5).normalized()
    a1 = n0.cross(Vector((0, 0, 1))).normalized()
    a2 = n0.cross(a1).normalized()

    def rad_el(d, extra):
        h = bvh.ray_cast(el + d * 0.25, -d)
        return ((0.25 - h[3]) if h[0] is not None else 0.045) + extra
    cop, cdir = [], []
    for i in range(1, 8):
        al = 1.05 * i / 7
        row, drow = [], []
        for j in range(24):
            ph = 2 * math.pi * j / 24
            d = (n0 * math.cos(al) + (a1 * math.cos(ph) + a2 * math.sin(ph)) * math.sin(al)).normalized()
            row.append(el + d * rad_el(d, 0.016))
            drow.append(d)
        cop.append(row)
        cdir.append(drow)
    tip = el + n0 * rad_el(n0, 0.019)
    parts.append(g_smooth_mesh("Couter" + sn, [[tip] * 24] + cop, K["plate"], body, cap_end=False, thick=0.005,
                               outward=True))
    parts.append(g_pipe("CouterRim" + sn, [q + d * 0.002 for q, d in zip(cop[-1], cdir[-1])], 0.005, K["plate"], body,
                        sides=8, loop=True))
    # ---- aleta: chapa em ponta saindo da cúpula para fora e para trás, um pouco caída; a base entra na cúpula
    ax = (cb_mirror(CB_J["wrist"], s) - el).normalized() if "wrist" in CB_J else at(L1 + 0.5 * L2)[1]
    out = (Vector((s, 0, 0)) * 1.0 + Vector((0, 1, 0)) * 0.22)
    out = (out - ax * out.dot(ax)).normalized()
    base_r = rad_el(out, 0.012)
    NU, NV = 12, 8

    def wing(u, v):                    # u: -1 (em cima) .. 1 (embaixo); v: 0 na cúpula .. 1 na ponta
        reach = 0.068 * (1 - abs(u)) ** 1.25
        hz = 0.075 * (1 - 0.55 * v)    # altura ao longo do braço encolhe para a ponta
        p = el + ax * (u * hz + 0.022 * v ** 1.5) + out * (base_r + reach * v)
        side = ax.cross(out).normalized()
        return p + side * 0.008 * math.sin(math.pi * v) * (1 - abs(u))     # leve concha
    wg = [[wing(-1 + 2 * j / NU, i / NV) for j in range(NU + 1)] for i in range(NV + 1)]
    parts.append(g_smooth_mesh("CouterWing" + sn, wg, K["plate"], body, cap_end=False, closed=False, thick=0.005,
                               outward=True))
    # contorno = fileira da ponta (as colunas das pontas de cima e de baixo fecham na cúpula)
    parts.append(g_pipe("CouterWingRim" + sn, wg[NV], 0.004, K["plate"], body, sides=8))
    parts.append(g_pipe("CouterWingRib" + sn, [wing(0.0, v) for v in (0.05, 0.35, 0.65, 0.9)], 0.0025, K["plate_d"],
                        body, sides=6))
    parts.append(g_bead("CouterBoss" + sn, tip + n0 * 0.002, 0.007, K["plate_d"], body))
    return parts


def _cs_tasset_w(p):
    """Escarcela: logo abaixo do cinto já vai inteira com a coxa do seu lado (na passada a coxa não passa por
    cima da barra)."""
    leg = max(0.0, min(1.0, (0.975 - p.z) / 0.08))
    return {"Body": 1.0 - leg, ("LegL" if p.x > 0 else "LegR"): leg}


def celestial_skirt(K, src, body):
    """Cintura para baixo: escarcela grande em cada quadril, da última lâmina até o meio da coxa, aberta em arco
    no meio da frente, com borda dobrada, três frisos e rebites; culote atrás; no arco, pano azul-noite caindo
    entre as pernas; nas coxas, coxeira dourada em volta da coxa inteira, com duas lâminas no alto.
    Devolve (escarcelas, culote, pano do meio, coxeiras, debruns das coxeiras)."""
    tas = []
    for sn, s in (("L", 1), ("R", -1)):
        def plate(u, v, s=s):
            a_in = 0.28 + 0.3 * u ** 1.3
            a = (a_in + (2.6 - a_in) * v) * s
            zb = 0.775 + 0.06 * v ** 1.8
            z = 0.968 + (zb - 0.968) * u
            return _wk_hip_pt(a, z, 0.034 + 0.024 * u)
        ob, rr = _wk_plate("Tasset" + sn, plate, 12, 40, K["plate"], body, thick=0.005)
        tas.append(ob)
        edge = [r[0] for r in rr] + rr[-1][1:] + [r[-1] for r in rr][::-1][1:]
        tas.append(g_pipe("TassetRim" + sn, edge, 0.0055, K["plate"], body, sides=8))
        for k, v in enumerate((0.22, 0.42, 0.62)):
            tas.append(g_pipe("TassetFlute%s%d" % (sn, k), [plate(u, v) + Vector((plate(u, v).x, plate(u, v).y, 0))
                                                           .normalized() * 0.0015 for u in (0.3, 0.5, 0.7, 0.92)],
                              0.002, K["plate_d"], body, sides=6))
        for v in (0.06, 0.3, 0.55, 0.8):
            q = plate(0.06, v)
            tas.append(g_bead("TassetRivet%s%d" % (sn, int(v * 10)), q + Vector((q.x, q.y, 0)).normalized() * 0.004,
                              0.0045, K["plate_d"], body))
    culet = firstplate_culet(dict(K, lining=K["plate"]), body)
    # ---- pano azul-noite no arco da frente, da última lâmina até o meio da coxa, um pouco atrás das escarcelas
    def panel(u, v):
        z = 0.962 - (0.962 - 0.76) * u
        ut = (0.968 - z) / (0.968 - 0.775)
        half = 0.28 + 0.3 * ut ** 1.3 + 0.08
        return _wk_hip_pt(-half + 2 * half * v, z, 0.022)
    pm, pr = _wk_plate("FrontCloth", panel, 8, 16, K["night"], body, thick=0.003)
    mid = [pm]
    # ---- coxas: casca iridescente por inteiro e a coxeira dourada por cima, do lado de fora
    shells, trims = [], []
    knee_z = CB_J["knee"].z
    for sn, s in (("L", 1), ("R", -1)):
        hip = cb_mirror(CB_J["hip"], s)

        def keep_g(c, b, n, s=s):      # coxa inteira em placa, do joelho até sob a escarcela
            return b.startswith("Leg") and c.x * s > 0 and knee_z + 0.02 < c.z < 0.8
        sh = cb_piece(src, "Cuisse" + sn, keep_g, 0.016, K["plate"])
        g_subdiv(sh, 2)
        shells.append(sh)
        for rim in g_border_pipes(sh, "CuisseRim" + sn, 0.0055, K["plate"], body, smooth=6, step=0.01):
            mz = sum((rim.matrix_world @ v.co).z for v in rim.data.vertices) / len(rim.data.vertices)
            if mz > 0.74:              # debrum de cima fica sob a escarcela; na passada saía por baixo dela
                bpy.data.objects.remove(rim, do_unlink=True)
            else:
                trims.append(rim)
        from mathutils.bvhtree import BVHTree
        bvh = BVHTree.FromPolygons([v.co.copy() for v in sh.data.vertices], [tuple(p.vertices) for p in sh.data.polygons])
        kn = cb_mirror(CB_J["knee"], s)
        for k, z in enumerate((0.74, 0.7)):
            c = hip.lerp(kn, (hip.z - z) / (hip.z - kn.z))
            line = []
            for j in range(15):
                a = -0.2 + 2.6 * j / 14
                d = Vector((math.sin(a) * s, -math.cos(a), 0))
                h = bvh.ray_cast(Vector((c.x, c.y, z)) + d * 0.3, -d)[0]
                if h is not None:
                    line.append(h + d * 0.0015)
            if len(line) > 2:
                trims.append(g_pipe("CuisseLame%s%d" % (sn, k), line, 0.0022, K["plate_d"], body, sides=6))
    return tas, culet, mid, shells, trims


def build_a_celestial():
    """Placas Astrais, cavaleiro celeste (lendário nv 47). Rodada 1: tronco; braços e pernas com a casca de
    bronze escuro até as próximas peças."""
    style = "a_celestial"
    P, R = g_rig(style)
    M = g_mats()
    K = celestial_mats()
    body = R["Body"]
    rig, src = _cb_start(M)
    neck(R, M["skin"])
    hips(R, K["joint"])
    g_skinned_pants(src, M["pants"])
    under, parts = celestial_torso(K, src, body)
    shoulder = mithril_pauldron(K, src, body, 1) + mithril_pauldron(K, src, body, -1)
    haute = celestial_haute(K, body, 1) + celestial_haute(K, body, -1)
    arms = celestial_arm(K, src, body, 1) + celestial_arm(K, src, body, -1)
    tas, culet, mid, cuis, cuis_trim = celestial_skirt(K, src, body)
    mantle = celestial_mantle(K, body, [src, under] + shoulder + parts + arms + tas + culet)
    cape = [o for o in mantle if o.name.startswith("Cape")]
    mantle = [o for o in mantle if not o.name.startswith("Cape")]
    sleeves = cb_piece(src, "Sleeves", lambda c, b, n: (b.startswith("Arm") or b.startswith("Elbow"))
                       and (not b.startswith("Elbow") or _cb_fore_t(c) < 0.86), 0.01, K["joint"])
    g_subdiv(sleeves)
    g_loose_world(style)
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    bake_ao(targets, _occluders(style, P, R, M))
    cel_paint(targets, skip=("g_skin",))
    g_skin_finish(rig, src, [(shoulder, "vert", ("Body", "ArmL", "ArmR"), 1.0),
                             (haute, "vert", ("Body", "ArmL", "ArmR"), 0.3),
                             (mantle, "fn", _cs_mantle_w, 1.0), (cape, "fn", _cs_cape_w, 1.0),
                             (arms, "vert", ("ArmL", "ArmR", "ElbowL", "ElbowR"), 1.0),
                             (tas, "fn", _cs_tasset_w, 1.0), (mid, "fn", _wk_center_w, 1.0),
                             (culet, "fn", _gb_skirt_w, 1.0),
                             (cuis_trim, "vert", ("Body", "LegL", "LegR"), 1.0)])
    join_objs("Celestial", parts + shoulder + haute + mantle + cape + arms + tas + mid + culet + cuis_trim)
    g_galaxy_uv(style)
    g_export_skinned(style)


def build_hood(style, A, o, extra=None):
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
    if extra:          # peças próprias do conjunto por cima do capuz (coroa, aro): extra(head, hp, hc)
        parts += extra(head, hp, hc)
    if "loose_parts" in globals():
        loose_parts(style)
    join_objs("Hood", parts)
    g_galaxy_uv(style)
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
        elif sp["head"] == "hood":          # "own": a cabeça do conjunto tem construtor próprio
            globals()["build_h_" + key] = lambda sp=sp, key=key, pre=pre: build_hood("h_" + key, robe_mats(pre, sp),
                                                                                    sp["o"])


# ------------------------------------------------------------------ gola e ombros dos conjuntos de fim de jogo
# Cada conjunto desliga os enfeites do Arquimago (ombreira, corrente, broche...) e põe os seus por cima da
# murça, por um gancho: o["mantle_extra"](X), com X = funções da murça (M, normal, frame, motif) e as listas
# soft (pano que dobra) e orn (enfeites que vão inteiros).
MX_OFF = dict(pauldron=False, fringe=False, lapel=False, chains=False, stars=False, hem_diamonds=False, back="none",
              brooch=False)


def mx_skull(nm, c, n, side, up, bone, glow, body, k=1.0):
    """Caveira de broche: calota, queixo e dois olhos acesos."""
    out = [g_cap(nm, c + n * 0.004, n, side, 0.034 * k, 0.04 * k, 0.03 * k, bone, body, sides=18),
           g_cap(nm + "Jaw", c - up * 0.036 * k + n * 0.004, n, side, 0.021 * k, 0.02 * k, 0.017 * k, bone, body, sides=14)]
    dark = gm("eg_skull_dark", "#15151A", 0.9)
    for i, sx in enumerate((-1, 1)):
        e = c + side * sx * 0.015 * k - up * 0.003 * k + n * 0.027 * k
        out.append(g_plate("%sSocket%d" % (nm, i), [(x * 0.011 * k, y * 0.01 * k) for x, y in
                                                    ((-1, 0.6), (0.2, 1), (1, 0.3), (0.7, -0.8), (-0.6, -1))],
                           e, side * sx, up, 0.006 * k, dark, body))
        out.append(g_plate("%sPupil%d" % (nm, i), [(x * 0.006 * k, y * 0.005 * k) for x, y in G_DIAMOND], e + n * 0.004 * k,
                           side, up, 0.003 * k, glow, body))
    out.append(g_plate(nm + "Nose", [(0, 0.008 * k), (0.005 * k, -0.006 * k), (-0.005 * k, -0.006 * k)],
                       c - up * 0.019 * k + n * 0.027 * k, side, up, 0.006 * k, dark, body))
    return out


def mx_lich(X):
    """Costelas de osso por cima de cada ombro, com nós e espinhos na cumeeira, e caveira de broche."""
    M, nrm, frame, orn, body = X["M"], X["normal"], X["frame"], X["orn"], X["body"]
    E = eg_mats("eg_lich", bone="#D9D1B8", glow=("#B8FFC0", "#5CFF7A", 2.0))
    for sn, s in (("L", 1), ("R", -1)):
        for k in range(4):
            u, span = 0.42 + 0.15 * k, 0.85 - 0.08 * k
            path = []
            for i in range(15):
                a = s * (math.pi / 2 - span + 2 * span * i / 14)
                path.append(M(a, u) + nrm(a, u) * (-0.004 + 0.042 * math.sin(math.pi * i / 14)))
            rad = [(0.0035 + 0.0085 * max(0.0, math.sin(math.pi * i / 14)) ** 0.7,) * 2 for i in range(15)]
            orn.append(g_smooth_mesh("LichRib%s%d" % (sn, k), g_curved_tube(path, rad, sides=8, side0=(0, 0, 1)),
                                     E["bone"], body))
            a = s * math.pi / 2
            top = M(a, u) + nrm(a, u) * 0.036
            orn.append(g_bead("LichKnob%s%d" % (sn, k), top, 0.015, E["bone"], body))
            orn.append(g_cone("LichSpine%s%d" % (sn, k), [top, top + nrm(a, u) * (0.075 - 0.01 * k) + Vector((s * 0.02, 0, 0.02))],
                              0.01, E["bone"], body, sides=6, n=3))
    c, n, side, up = frame(0.0, 0.7)
    orn += mx_skull("LichSkull", c, n, side, up, E["bone"], E["glow"], body, 1.15)


def mx_hiero(X):
    """Pálio dourado em volta dos ombros com losangos vermelhos, faixa descendo na frente e nas costas, sol de
    raios no peito e borlas douradas na barra dos ombros."""
    M, nrm, frame, soft, orn, body, A = X["M"], X["normal"], X["frame"], X["soft"], X["orn"], X["body"], X["A"]
    gold, jewel, red = A["gold2"], A["gem"], A["lining"]
    on = lambda a, u, d=0.005: M(a, u) + nrm(a, u) * d
    band = [[on(2 * math.pi * j / 64, u) for j in range(64)] for u in (0.4, 0.46, 0.52, 0.58)]
    soft.append(g_smooth_mesh("Pallium", band, gold, body, cap_end=False, thick=0.006))
    for nm, a0 in (("F", 0.0), ("B", math.pi)):
        strip = [[on(a0 + da, 0.56 + 0.44 * i / 9) for da in (-0.11, -0.055, 0.0, 0.055, 0.11)] for i in range(10)]
        soft.append(g_smooth_mesh("PalliumStrip" + nm, strip, gold, body, cap_end=False, closed=False, thick=0.006,
                                  outward=True))
        for i, u in enumerate((0.7, 0.82, 0.94)):
            c, n, side, up = frame(a0, u)
            orn.append(g_plate("PalliumGem%s%d" % (nm, i), [(x * 0.014, y * 0.016) for x, y in G_DIAMOND], c + n * 0.006,
                               side, up, 0.012, red, body))
    for j in range(8):
        a = 2 * math.pi * (j + 0.5) / 8
        c, n, side, up = frame(a, 0.49)
        orn.append(g_plate("PalliumDia%d" % j, [(x * 0.018, y * 0.02) for x, y in G_DIAMOND], c + n * 0.006, side, up,
                           0.012, red, body))
    c, n, side, up = frame(0.0, 0.49)
    c = c + n * 0.012
    orn.append(g_cap("SunGorget", c, n, side, 0.05, 0.05, 0.014, gold, body, sides=24))
    orn.append(g_cap("SunGorgetGem", c + n * 0.008, n, side, 0.027, 0.027, 0.014, jewel, body, rings=5, sides=18))
    for i in range(12):
        rd = side * math.cos(2 * math.pi * i / 12) + up * math.sin(2 * math.pi * i / 12)
        ln = 0.05 if i % 2 == 0 else 0.03
        orn.append(g_plate("SunGorgetRay%d" % i, [(x * 0.014, y * ln / 2) for x, y in G_DIAMOND],
                           c + rd * (0.048 + ln / 2), rd.cross(n), rd, 0.006, gold, body))
    for sn, s in (("L", 1), ("R", -1)):
        for k in range(7):
            a = s * (math.pi / 2 + (k - 3) * 0.17)
            orn.append(g_tassel("CopeTassel%s%d" % (sn, k), M(a, 0.985) + Vector((0, 0, 0.004)), 0.07, gold, body))


def mx_reaper(X):
    """Ombreiras de aço em três placas sobrepostas, cada uma com esporão, gema roxa no alto, e caveira de broche
    com raios acesos."""
    M, nrm, frame, orn, body = X["M"], X["normal"], X["frame"], X["orn"], X["body"]
    E = eg_mats("eg_reaper", steel="#8E93A3", iron="#24222C", bone="#D6D0C4", glow=("#E0B8FF", "#A050FF", 2.2))
    for sn, s in (("L", 1), ("R", -1)):
        a = s * math.pi / 2
        for k in range(3):
            u = 0.88 - 0.22 * k
            r1, r2, h = 0.115 - 0.02 * k, 0.078 - 0.008 * k, 0.03 + 0.009 * k
            c, n = M(a, u), nrm(a, u)
            c = c + n * 0.004
            nm = "ReaperPauldron%s%d" % (sn, k)
            orn.append(g_cap(nm, c, n, (0, -1, 0), r1, r2, h, E["steel"], body))
            orn.append(g_pipe(nm + "Rim", [g_cap_pt(c, n, (0, -1, 0), r1, r2, h, 2 * math.pi * j / 24, 0.1, 0.002)
                                           for j in range(24)], 0.0055, E["iron"], body, loop=True))
            b = c + n * h * 0.3
            orn.append(g_cone(nm + "Spur", [b, b + Vector((s * 0.05, 0, 0.03)), b + Vector((s * (0.1 - 0.015 * k), 0, 0.1 + 0.02 * k))],
                              0.017, E["steel"], body, sides=8))
            if k == 2:
                orn.append(g_cap("ReaperPauldronGem" + sn, c + n * (h - 0.004), n, (0, -1, 0), 0.028, 0.022, 0.016,
                                 E["glow"], body, rings=5, sides=16))
    c, n, side, up = frame(0.0, 0.68)
    for i in range(12):
        rd = side * math.cos(2 * math.pi * i / 12) + up * math.sin(2 * math.pi * i / 12)
        ln = 0.075 if i % 2 == 0 else 0.05
        orn.append(g_plate("ReaperRay%d" % i, [(x * 0.012, y * ln / 2) for x, y in G_DIAMOND],
                           c + n * 0.006 + rd * (0.03 + ln / 2), rd.cross(n), rd, 0.005, E["glow"], body))
    orn += mx_skull("ReaperSkull", c, n, side, up, E["bone"], E["glow"], body, 1.2)


def mx_raven(X):
    """Murça de penas: três fiadas desencontradas em volta, penas compridas saindo dos ombros e fecho de
    crânio de corvo no peito."""
    M, nrm, frame, orn, body = X["M"], X["normal"], X["frame"], X["orn"], X["body"]
    E = eg_mats("eg_raven", feather="#1C1E2C", sheen="#2F4270", silver="#AEB4C2", bone="#DCD4BC",
                glow=("#D8B0FF", "#A060FF", 1.8))
    for r, (u, cnt, ln) in enumerate(((0.26, 18, 0.105), (0.52, 24, 0.12), (0.78, 30, 0.135))):
        for j in range(cnt):
            a = 2 * math.pi * (j + 0.5 * (r % 2)) / cnt
            c, n, side, up = frame(a, u)
            orn.append(g_feather("MantleFeather%d_%d" % (r, j), c - n * 0.003, -up + n * (0.1 + 0.04 * (j % 2)), n, ln,
                                 0.027, E["sheen" if (j + r) % 3 == 0 else "feather"], body, curl=0.07))
    for sn, s in (("L", 1), ("R", -1)):
        for k in range(6):
            a = s * (math.pi / 2 + (k - 2.5) * 0.2)
            c, n, side, up = frame(a, 0.86)
            orn.append(g_feather("ShoulderFeather%s%d" % (sn, k), c - n * 0.003, -up * 0.75 + n * 0.65, n,
                                 0.22 - 0.012 * abs(k - 2.5), 0.034, E["sheen" if k % 2 else "feather"], body, curl=-0.18))
    c, n, side, up = frame(0.0, 0.4)
    orn.append(g_cap("RavenClasp", c + n * 0.006, n, side, 0.032, 0.036, 0.03, E["bone"], body, sides=16))
    orn.append(g_cone("RavenClaspBeak", [c + n * 0.02 - up * 0.01, c + n * 0.035 - up * 0.06, c + n * 0.022 - up * 0.115],
                      0.016, E["bone"], body, sides=8))
    for i, sx in enumerate((-1, 1)):
        orn.append(g_cap("RavenClaspEye%d" % i, c + side * sx * 0.017 + n * 0.026 - up * 0.004, n + side * sx * 0.6, up,
                         0.008, 0.008, 0.006, E["glow"], body, rings=4, sides=10))


def mx_dragon(X):
    """Assimétrico: ombro esquerdo com três lâminas de escama e três chifres, direito com uma lâmina e um
    chifre; gola de pele em tufos; olho de dragão com garras no peito; barra de escamas."""
    M, nrm, frame, orn, body, A, motif = X["M"], X["normal"], X["frame"], X["orn"], X["body"], X["A"], X["motif"]
    E = eg_mats("eg_dragon", scale="#7A1E26", gold="#D09A3A", horn="#D8CCB0", fur="#E6DCC8",
                glow=("#FFD0A0", "#FF7A2A", 1.8))
    for sn, s, lames in (("L", 1, 3), ("R", -1, 1)):
        a = s * math.pi / 2
        for k in range(lames):
            u = (0.9 - 0.22 * k) if lames > 1 else 0.74
            r1, r2, h = 0.125 - 0.02 * k, 0.085 - 0.01 * k, 0.036 + 0.01 * k
            c, n = M(a, u), nrm(a, u)
            c = c - n * 0.006
            nm = "DragonLame%s%d" % (sn, k)
            orn.append(g_cap(nm, c, n, (0, -1, 0), r1, r2, h, E["scale"], body))
            orn.append(g_pipe(nm + "Rim", [g_cap_pt(c, n, (0, -1, 0), r1, r2, h, 2 * math.pi * j / 24, 0.1, 0.002)
                                           for j in range(24)], 0.006, E["gold"], body, loop=True))
            if k == lames - 1:
                for i in (range(-1, 2) if lames > 1 else (0,)):
                    b = c + n * h * 0.6 + Vector((0, -i * 0.042, 0))
                    ln = 0.17 - 0.03 * abs(i)
                    orn.append(g_cone("DragonSpike%s%d" % (sn, i + 1),
                                      [b, b + Vector((s * 0.05, -i * 0.01, ln * 0.4)), b + Vector((s * 0.07, -i * 0.03, ln))],
                                      0.022, E["horn"], body, sides=10, ridge=0.002))
    for r in range(2):                     # gola de pele: duas fiadas de tufos
        for j in range(22):
            a = 2 * math.pi * (j + 0.5 * r) / 22
            c, n, side, up = frame(a, 0.1 + 0.11 * r)
            d = n * 0.6 - up * 0.7 + side * 0.25 * (1 if j % 2 else -1)
            orn.append(g_cone("FurTuft%d_%d" % (r, j), [c - d.normalized() * 0.012, c + n * 0.022 + d.normalized() * 0.03,
                                                       c + n * 0.016 + d.normalized() * (0.07 + 0.012 * (j % 3))],
                              0.03, E["fur"], body, sides=8, n=6))
    c, n, side, up = frame(0.0, 0.62)
    c = c + n * 0.006
    orn.append(g_cap("DragonEye", c, n, side, 0.064, 0.044, 0.02, E["gold"], body, sides=22))
    orn.append(g_cap("DragonEyeGem", c + n * 0.01, n, side, 0.044, 0.028, 0.018, E["glow"], body, rings=5, sides=18))
    orn.append(g_plate("DragonEyeSlit", [(x * 0.008, y * 0.028) for x, y in G_DIAMOND], c + n * 0.028, side, up, 0.004,
                       A["lining"], body))
    for i, (sx, sy) in enumerate(((-1, 1), (1, 1), (-1, -1), (1, -1))):
        b = c + side * sx * 0.066 + up * sy * 0.04
        orn.append(g_cone("DragonClaw%d" % i, [b, b + n * 0.02 - side * sx * 0.012 - up * sy * 0.008,
                                              b + n * 0.012 - side * sx * 0.03 - up * sy * 0.018], 0.009, E["horn"], body,
                          sides=6, n=6))
    for j in range(26):
        a = 2 * math.pi * (j + 0.5) / 26
        orn.append(motif("HemScale%d" % j, [(-1, 0.9), (1, 0.9), (0, -1.5)], a, 0.92, 0.02, thick=0.006))


def mx_astral(X):
    """Estrela grande deitada em cada ombro com gema, aro em pé com um planeta, lua crescente no peito e
    constelações de contas ligadas por fio."""
    M, nrm, frame, orn, body, A, motif = X["M"], X["normal"], X["frame"], X["orn"], X["body"], X["A"], X["motif"]
    gold, jewel = A["gold2"], A["gem"]
    for sn, s in (("L", 1), ("R", -1)):
        c, n, side, up = frame(s * math.pi / 2, 0.6)
        orn.append(g_plate("ShoulderStar" + sn, [(x / 1.35 if i % 4 == 0 else x, y / 1.35 if i % 4 == 0 else y)
                                                 for i, (x, y) in enumerate(g_star4(0.125, 0.036))], c + n * 0.008, side, up,
                           0.008, gold, body))
        orn.append(g_cap("ShoulderStarSeat" + sn, c + n * 0.01, n, side, 0.036, 0.036, 0.014, gold, body, sides=18))
        orn.append(g_cap("ShoulderStarGem" + sn, c + n * 0.018, n, side, 0.024, 0.024, 0.016, jewel, body, rings=5,
                         sides=16))
        cc = c + n * 0.03
        orn.append(g_pipe("ShoulderOrbit" + sn, g_circle(cc, up, n, 0.062, 32), 0.0045, gold, body, loop=True))
        orn.append(g_bead("ShoulderPlanet" + sn, cc + n * 0.062, 0.016, jewel, body))
        orn.append(g_bead("ShoulderMoonlet" + sn, cc + (n * 0.5 + up * 0.87).normalized() * 0.062, 0.009, gold, body))
    c, n, side, up = frame(0.0, 0.52)
    orn.append(g_crescent("Gorget", c + n * 0.006, up, side, 0.01, gold, body, r=0.078, r_in=0.068, d=0.032))
    orn.append(motif("GorgetStar", g_star4(1.0, 0.3), 0.0, 0.45, 0.03))
    orn.append(g_gem("GorgetGem", c + n * 0.014 - up * 0.062, 0.014, 0.02, 0.008, jewel, body))
    for nm, a0, sg in (("FL", 0.0, 1), ("FR", 0.0, -1), ("BL", math.pi, 1), ("BR", math.pi, -1)):
        pts = [M(a0 + sg * a, u) + nrm(a0 + sg * a, u) * 0.007
               for a, u in ((0.95, 0.5), (1.18, 0.7), (0.8, 0.82), (0.52, 0.7), (0.66, 0.93))]
        for i, q in enumerate(pts):
            orn.append(g_bead("Constel%s%d" % (nm, i), q, 0.0085 if i % 2 else 0.0065, jewel, body))
        for i, (q, q2) in enumerate(zip(pts, pts[1:])):
            orn.append(g_cone("ConstelLine%s%d" % (nm, i), [q, q2], 0.0026, gold, body, sides=5, n=2, r1=0.0026))


def mx_frost(X):
    """Gola grossa de pele, cacho de cristais de gelo em cada ombro sobre base de prata, franja de pingentes
    de gelo na barra e floco de neve no peito."""
    M, nrm, frame, soft, orn, body = X["M"], X["normal"], X["frame"], X["soft"], X["orn"], X["body"]
    E = eg_mats("eg_frost", silver="#C9D2E0", fur="#F2F6FA", ice=("#8FD0F2", "#5FB8F0", 0.35),
                deep=("#9FC4FF", "#3F7BE0", 1.5))
    path = [M(math.pi / 2 + 2 * math.pi * j / 44, 0.2) + nrm(math.pi / 2 + 2 * math.pi * j / 44, 0.2) * 0.03
            for j in range(44)]
    path += path[:2]
    fur = g_curved_tube(path, [(0.046, 0.04)] * len(path), sides=16,
                        wob=lambda i, a: 0.007 * math.sin(i * 2.3) * math.sin(3 * a + i) + 0.004 * math.sin(5 * a))
    soft.append(g_smooth_mesh("FurCollar", fur, E["fur"], body, cap_end=False))
    up = Vector((0, 0, 1))
    for sn, s in (("L", 1), ("R", -1)):
        a = s * math.pi / 2
        c, n = M(a, 0.66), nrm(a, 0.66)
        orn.append(g_cap("FrostPauldron" + sn, c + n * 0.004, n, (0, -1, 0), 0.105, 0.07, 0.026, E["silver"], body))
        fwd = Vector((0, -1, 0))
        sd = fwd.cross(n).normalized()
        for k in range(8):                 # cacho: um cristal alto no meio e os outros abrindo em volta
            ph, rho = k * 2.4, (0.0 if k == 0 else 0.3 + 0.12 * (k % 3))
            sp = fwd * math.cos(ph) + sd * math.sin(ph)
            d = ((n + up * 0.45).normalized() + sp * rho).normalized()
            ln = 0.2 if k == 0 else 0.15 - 0.012 * k
            b = c + n * 0.014 + sp * rho * 0.11
            orn.append(g_shard("FrostShard%s%d" % (sn, k), b - d * 0.014, b + d * ln, 0.032 if k == 0 else 0.024, E["ice"],
                               body, twist=k * 0.9))
    for j in range(30):
        a = 2 * math.pi * (j + 0.5) / 30
        q = M(a, 0.99)
        orn.append(g_shard("Icicle%d" % j, q + up * 0.01, q - up * (0.045 + 0.03 * (j % 2)), 0.011, E["ice"], body,
                           twist=j * 0.5))
    c, n, side, upv = frame(0.0, 0.62)
    c = c + n * 0.007
    for i in range(6):
        rd = side * math.cos(math.pi * i / 3) + upv * math.sin(math.pi * i / 3)
        orn.append(g_plate("Snowflake%d" % i, [(x * 0.014, y * 0.03) for x, y in G_DIAMOND], c + rd * 0.036,
                           rd.cross(n), rd, 0.006, E["silver"], body))
        orn.append(g_plate("SnowflakeTip%d" % i, [(x * 0.02, y * 0.012) for x, y in G_DIAMOND], c + rd * 0.05,
                           rd.cross(n), rd, 0.006, E["silver"], body))
    orn.append(g_cap("SnowflakeGem", c, n, side, 0.02, 0.02, 0.014, E["deep"], body, rings=5, sides=14))


ROBES.update({
    "lich": dict(head="own", colors=dict(cloth="#18211D", lining="#2F5A3C", lining2="#101613", trim="#D9D1B8", metal=0.0,
                                         under="#0F1512", sash="#24302A", tassel="#3E7A4E", gem="#B8FFC0", glow="#5CFF7A",
                                         glow_k=2.0),
                 o=dict(MX_OFF, mantle_extra=mx_lich, tatter=0.05, tatter_n=11, mantle_n=96, layers=3, vee=0.13, back="rune",
                        glow_motif=True, motif="rune", collar=1.15, cords=False, knot=False, open=0.2, hem_pts=4,
                        hem_depth=0.12, bell=2.4, droop=0.25)),
    "hierophant": dict(head="own", colors=dict(cloth="#ECE5D2", lining="#8E2030", lining2="#F6F1E4", trim="#E0B040",
                                               under="#F6F1E4", sash="#8E2030", tassel="#E0B040", gem="#FFE6A8",
                                               glow="#FFC050", glow_k=1.6),
                       o=dict(MX_OFF, mantle_extra=mx_hiero, wing=0.075, vee=0.03, layers=3, back="sun", hem_diamonds=True,
                              collar=0.6, cords=False, open=0.4, hem_pts=0, bell=2.2, droop=0.12)),
    "reaper": dict(head="own", colors=dict(cloth="#16141C", lining="#2A1F40", lining2="#0E0D13", trim="#8E93A3", metal=0.5,
                                           under="#0E0D13", sash="#2A1F40", tassel="#A050FF", gem="#E0B8FF", glow="#A050FF",
                                           glow_k=2.2),
                   o=dict(MX_OFF, mantle_extra=mx_reaper, tatter=0.07, tatter_n=14, mantle_n=112, layers=3, vee=0.14,
                          lapel=True, chains=True, collar=0.35, cords=False, knot=False, open=0.15, hem_pts=4,
                          hem_depth=0.12, bell=2.2, droop=0.22)),
    "raven": dict(head="own", colors=dict(cloth="#17161C", lining="#3A1F4A", trim="#AEB4C2", metal=0.5, under="#1C1E2C",
                                          sash="#2F4270", tassel="#2F4270", gem="#D8B0FF", glow="#A060FF", glow_k=1.8),
                  o=dict(MX_OFF, mantle_extra=mx_raven, vee=0.08, wing=0.05, collar=0.9, cords=False, open=0.35, hem_pts=2,
                         bell=1.8, droop=0.15)),
    "dragon": dict(head="own", colors=dict(cloth="#6A1820", lining="#22161A", trim="#D09A3A", under="#2A1A1C",
                                           sash="#22161A", tassel="#D09A3A", gem="#FFD0A0", glow="#FF7A2A", glow_k=1.8),
                   o=dict(MX_OFF, mantle_extra=mx_dragon, vee=0.1, wing=0.04, collar=0.35, cords=False,
                          open=0.3, hem_pts=2, bell=1.5, droop=0.1, tabard=False)),
    "astral": dict(head="own", colors=dict(cloth="#232A66", lining="#D5DAE6", trim="#E2C06A", under="#F0EEF6",
                                           sash="#3A4AA0", tassel="#E2C06A", gem="#CFEAFF", glow="#6FB8FF", glow_k=1.8),
                   o=dict(MX_OFF, mantle_extra=mx_astral, vee=0.16, wing=0.02, stars=True, hem_diamonds=True,
                          back="moon", collar=1.35, open=0.45, hem_pts=2, bell=2.0, droop=0.15)),
    "frost": dict(head="own", colors=dict(cloth="#DCE8F4", lining="#4A78B8", trim="#C9D2E0", metal=0.5, under="#7FA8D8",
                                          sash="#4A78B8", tassel="#C9D2E0", gem="#9FC4FF", glow="#3F7BE0", glow_k=1.5),
                  o=dict(MX_OFF, mantle_extra=mx_frost, vee=0.1, wing=0.03, collar=0.5, cords=False, open=0.3, hem_pts=0,
                         bell=1.7, droop=0.1)),
})


# ------------------------------------------------------------------ tronco e faixa dos conjuntos de fim de jogo
# Gancho o["torso_extra"](X): X = funções do tronco (hit_a, hit_x, below, rad), o centro da fivela (bc) e as
# listas parts (peças presas ao tronco) e tails (panos que caem e dobram com a perna direita).
def tx_hang(nm, path, w, material, body, t=0.006, tip=0.12, side0=(1, 0, 0)):
    """Pano pendurado ao longo de path, terminando em ponta."""
    n = len(path) - 1
    radii = [(w * (max(0.1, (1 - i / n) / tip) if i / n > 1 - tip else 1.0), t) for i in range(n + 1)]
    return g_smooth_mesh(nm, g_curved_tube(path, radii, sides=14, side0=side0), material, body)


def tx_lich(X):
    """Costelas de osso abraçando o tronco a partir de um esterno, cinto de vértebras, caveira no lugar da
    fivela e duas caveiras pequenas penduradas nos quadris."""
    hit_a, hit_x, below, rad, parts, body, bc = X["hit_a"], X["hit_x"], X["below"], X["rad"], X["parts"], X["body"], X["bc"]
    E = eg_mats("eg_lich", bone="#D9D1B8", glow=("#B8FFC0", "#5CFF7A", 2.0))
    parts.append(g_pipe("Sternum", [hit_x(0.0, 1.37 - 0.03 * i, 0.012) for i in range(10)], 0.011, E["bone"], body))
    for sn, s in (("L", 1), ("R", -1)):
        for k in range(5):
            z = 1.13 + 0.055 * k
            path = [hit_a(s * (0.06 + 1.2 * i / 12), z + 0.035 * (i / 12) - 0.03 * (i / 12) ** 2,
                          0.007 + 0.014 * math.sin(math.pi * i / 12)) for i in range(13)]
            rad_ = [(0.004 + 0.0075 * max(0.0, math.sin(math.pi * (0.2 + 0.8 * i / 12))) ** 0.6,) * 2 for i in range(13)]
            parts.append(g_smooth_mesh("TorsoRib%s%d" % (sn, k), g_curved_tube(path, rad_, sides=8, side0=(0, 0, 1)),
                                       E["bone"], body))
    for j in range(22):
        a = 2 * math.pi * (j + 0.5) / 22
        if abs((a + math.pi) % (2 * math.pi) - math.pi) < 0.3:
            continue
        q = hit_a(a, 1.006, 0.03)
        parts.append(g_bead("Vertebra%d" % j, q, 0.021, E["bone"], body))
        if j % 2 == 0:
            parts.append(g_cone("VertebraSpur%d" % j, [q, q + rad(a) * 0.05 + Vector((0, 0, 0.012))], 0.009, E["bone"],
                                body, sides=6, n=3))
    fwd = Vector((0, -1, 0))
    parts += mx_skull("BeltSkull", bc + Vector((0, 0.004, 0.012)), fwd, Vector((1, 0, 0)), Vector((0, 0, 1)), E["bone"],
                      E["glow"], body, 1.55)
    for k, a in enumerate((0.85, -0.85)):
        pts = [below(a, 0.97 - 0.018 * q, 0.045) for q in range(9)]
        parts.append(g_pipe("HipCord%d" % k, pts, 0.004, E["bone"], body, sides=6))
        side = Vector((math.cos(a), math.sin(a), 0))
        parts += mx_skull("HipSkull%d" % k, pts[-1] + Vector((0, 0, -0.02)) - rad(a) * 0.012, rad(a), side,
                          Vector((0, 0, 1)), E["bone"], E["glow"], body, 0.85)


def tx_hiero(X):
    """Raios de sol em volta da fivela e um escapulário vermelho comprido caindo na frente, com losangos
    dourados e barra dourada."""
    below, parts, tails, body, bc, A = X["below"], X["parts"], X["tails"], X["body"], X["bc"], X["A"]
    gold, red = A["gold2"], A["lining"]
    fwd = Vector((0, -1, 0))
    for i in range(12):
        an = 2 * math.pi * i / 12
        rd = Vector((math.cos(an), 0, math.sin(an)))
        ln = 0.06 if i % 2 == 0 else 0.036
        parts.append(g_plate("BuckleRay%d" % i, [(x * 0.016, y * ln / 2) for x, y in G_DIAMOND],
                             bc + Vector((0, 0.008, 0)) + rd * (0.056 + ln / 2), rd.cross(fwd), rd, 0.008, gold, body))
    path = [below(0.0, 0.975 - 0.56 * i / 16, 0.03 + 0.022 * min(1.0, i / 3) + 0.03 * i / 16) for i in range(17)]
    tails.append(tx_hang("Scapular", path, 0.082, red, body))
    for i in (4, 8, 12):
        tails.append(g_plate("ScapularDia%d" % i, [(x * 0.03, y * 0.04) for x, y in G_DIAMOND], path[i], (1, 0, 0),
                             (0, 0, 1), 0.012, gold, body))
    tails.append(g_smooth_mesh("ScapularHem", g_curved_tube(path[13:15], [(0.085, 0.009)] * 2, sides=14), gold, body,
                               cap_end=False, outward=True))


def tx_reaper(X):
    """Faixa roxa acesa descendo pelo meio do peito e continuando abaixo do cinto, e três cintas de aço de
    cada lado abraçando o tronco."""
    hit_a, hit_x, below, parts, tails, body = X["hit_a"], X["hit_x"], X["below"], X["parts"], X["tails"], X["body"]
    E = eg_mats("eg_reaper", steel="#8E93A3", glow=("#E0B8FF", "#A050FF", 2.2))
    strip = [hit_x(0.0, 1.4 - 0.035 * i, 0.005) for i in range(11)]
    parts.append(g_smooth_mesh("VoidStrip", g_curved_tube(strip, [(0.016, 0.004)] * 11, sides=10), E["glow"], body))
    path = [below(0.0, 0.95 - 0.5 * i / 14, 0.034 + 0.02 * min(1.0, i / 3) + 0.028 * i / 14) for i in range(15)]
    tails.append(tx_hang("VoidStripLow", path, 0.024, E["glow"], body, t=0.005, tip=0.25))
    for sn, s in (("L", 1), ("R", -1)):
        for k in range(3):
            z0 = 1.3 - 0.07 * k
            pts = [hit_a(s * (0.13 + 1.0 * i / 10), z0 - 0.045 * (i / 10), 0.006) for i in range(11)]
            parts.append(g_smooth_mesh("SteelBand%s%d" % (sn, k), g_curved_tube(pts, [(0.012, 0.004)] * 11, sides=10,
                                                                             side0=(0, 0, 1)), E["steel"], body))
            parts.append(g_cap("SteelBandStud%s%d" % (sn, k), pts[0], (0, -1, 0), (1, 0, 0), 0.012, 0.012, 0.009,
                               E["steel"], body, rings=4, sides=10))


def tx_raven(X):
    """Duas fileiras de botões de prata, bandoleira atravessada com tachas e penas penduradas no quadril."""
    hit_a, hit_x, below, rad, parts, tails, body = (X["hit_a"], X["hit_x"], X["below"], X["rad"], X["parts"], X["tails"],
                                                    X["body"])
    E = eg_mats("eg_raven", feather="#1C1E2C", sheen="#2F4270", silver="#AEB4C2")
    for sx in (-1, 1):
        for k, z in enumerate((1.33, 1.27, 1.21, 1.15, 1.09)):
            parts.append(g_cap("VestButton%d%d" % (sx + 1, k), hit_x(sx * 0.034, z, -0.002), (0, -1, 0), (1, 0, 0), 0.0095,
                               0.0095, 0.008, E["silver"], body, rings=4, sides=10))
    pts = [hit_a(-0.95 + 1.9 * i / 16, 1.42 - 0.38 * i / 16, 0.011) for i in range(17)]
    parts.append(g_smooth_mesh("Bandolier", g_curved_tube(pts, [(0.02, 0.005)] * 17, sides=10, side0=(0, 0, 1)),
                               E["sheen"], body))
    for i in range(1, 16, 2):
        parts.append(g_cap("BandolierStud%d" % i, pts[i] + Vector((0, 0.001, 0)), rad(-0.95 + 1.9 * i / 16), (0, 0, 1), 0.008,
                           0.008, 0.008, E["silver"], body, rings=4, sides=10))
    for k in range(5):
        a = -0.9 + (k - 2) * 0.13
        b = below(a, 0.975, 0.04)
        tails.append(g_feather("HipFeather%d" % k, b, Vector((0, 0, -1)) + rad(a) * 0.12, rad(a), 0.27 - 0.03 * abs(k - 2), 0.032,
                               E["sheen" if k % 2 else "feather"], body, curl=0.08))
    tails.append(g_cap("HipFeatherPin", below(-0.9, 0.975, 0.04), rad(-0.9), (0, 0, 1), 0.026, 0.045, 0.014, E["silver"],
                       body, sides=14))


def tx_dragon(X):
    """Couraça de escamas em fiadas desencontradas no peito e no ventre, chifres na fivela e duas escarcelas
    de escama em cada quadril."""
    hit_a, rad, parts, body, bc = X["hit_a"], X["rad"], X["parts"], X["body"], X["bc"]
    E = eg_mats("eg_dragon", scale="#7A1E26", plate="#4E1218", gold="#D09A3A", horn="#D8CCB0")
    sc = [(-1, 0.8), (1, 0.8), (1, -0.2), (0, -1.25), (-1, -0.2)]
    for r in range(7):
        z = 1.37 - 0.047 * r
        for j in range(-3, 4):
            a = (j + 0.5 * (r % 2)) * 0.21
            p = hit_a(a, z, 0.005 + 0.002 * (r % 2))
            parts.append(g_plate("ChestScale%d_%d" % (r, j + 3), [(x * 0.024, y * 0.027) for x, y in sc], p,
                                 (math.cos(a), math.sin(a), 0), (0, 0, 1), 0.009,
                                 E["gold" if (j == 0 and r % 2 == 0) else ("scale" if (j + r) % 2 else "plate")], body))
    for k, sx in enumerate((-1, 1)):
        b = bc + Vector((sx * 0.04, 0.004, 0.035))
        parts.append(g_cone("BuckleHorn%d" % k, [b, b + Vector((sx * 0.035, -0.012, 0.03)),
                                                b + Vector((sx * 0.075, -0.02, 0.085))], 0.015, E["horn"], body, sides=8,
                            ridge=0.0015))
    for sn, s in (("L", 1), ("R", -1)):
        a = s * 1.05
        for k, (z, r1, r2) in enumerate(((0.9, 0.085, 0.07), (0.8, 0.07, 0.058))):
            c = hit_a(a, max(z, 0.9), 0.022 + 0.03 * k)
            c.z = z
            nm = "Tasset%s%d" % (sn, k)
            parts.append(g_cap(nm, c, rad(a), (0, 0, 1), r1, r2, 0.03, E["scale"], body))
            parts.append(g_pipe(nm + "Rim", [g_cap_pt(c, rad(a), (0, 0, 1), r1, r2, 0.03, 2 * math.pi * j / 22, 0.1, 0.002)
                                             for j in range(22)], 0.0055, E["gold"], body, loop=True))


def tx_astral(X):
    """Estrela de oito pontas atrás da fivela, fases da lua em fileira acima da faixa e astrolábio pendurado
    por uma corrente no quadril."""
    hit_a, below, rad, parts, body, bc, A = X["hit_a"], X["below"], X["rad"], X["parts"], X["body"], X["bc"], X["A"]
    gold, jewel = A["gold2"], A["gem"]
    even = lambda pts: [(x / 1.35 if i % 4 == 0 else x, y / 1.35 if i % 4 == 0 else y) for i, (x, y) in enumerate(pts)]
    parts.append(g_plate("BuckleStar", even(g_star4(0.115, 0.034)), bc + Vector((0, 0.008, 0)), (1, 0, 0), (0, 0, 1),
                         0.009, gold, body))
    parts.append(g_plate("BuckleStarB", even(g_star4(0.085, 0.03)), bc + Vector((0, 0.006, 0)), (1, 0, 1), (-1, 0, 1),
                         0.009, gold, body))
    for i in range(-2, 3):
        a = i * 0.17
        q = hit_a(a, 1.118, 0.006)
        tn = Vector((math.cos(a), math.sin(a), 0))
        if i == 0:
            parts.append(g_cap("MoonFull", q, rad(a), (0, 0, 1), 0.016, 0.016, 0.01, jewel, body, rings=4, sides=14))
        elif abs(i) == 1:
            parts.append(g_cap("MoonHalf%d" % i, q, rad(a), (0, 0, 1), 0.013, 0.013, 0.008, gold, body, rings=4, sides=12))
        else:
            parts.append(g_crescent("MoonNew%d" % i, q, tn * (1 if i > 0 else -1), (0, 0, 1), 0.007, gold, body, r=0.014,
                                    r_in=0.012, d=0.006))
    a = 0.62
    pts = [below(a, 0.97 - 0.014 * q, 0.05) for q in range(9)]
    nr = [rad(a)] * 9
    parts += g_links("AstroChain", pts, nr, gold, body)
    c = pts[-1] + Vector((0, 0, -0.05))
    tn = Vector((math.cos(a), math.sin(a), 0))
    parts.append(g_pipe("AstroRing", g_circle(c, tn, (0, 0, 1), 0.046, 28), 0.0055, gold, body, loop=True))
    parts.append(g_pipe("AstroRing2", g_circle(c, tn, (0, 0, 1), 0.03, 22), 0.0035, gold, body, loop=True))
    for i, d in enumerate((tn, Vector((0, 0, 1)))):
        parts.append(g_cone("AstroBar%d" % i, [c - d * 0.046, c + d * 0.046], 0.0035, gold, body, sides=6, n=2, r1=0.0035))
    parts.append(g_bead("AstroBead", c, 0.012, jewel, body))


def tx_frost(X):
    """Cinto grosso de pele, floco de neve de prata no lugar da fivela, franja de pingentes de gelo abaixo do
    cinto e botões de gelo no peito."""
    hit_a, hit_x, rad, parts, body, bc = X["hit_a"], X["hit_x"], X["rad"], X["parts"], X["body"], X["bc"]
    E = eg_mats("eg_frost", silver="#C9D2E0", fur="#F2F6FA", ice=("#8FD0F2", "#5FB8F0", 0.35),
                deep=("#9FC4FF", "#3F7BE0", 1.5))
    path = [hit_a(math.pi / 2 + 2 * math.pi * j / 44, 1.005, 0.03) for j in range(44)]
    path += path[:2]
    fur = g_curved_tube(path, [(0.045, 0.036)] * len(path), sides=16,
                        wob=lambda i, a: 0.006 * math.sin(i * 2.3) * math.sin(3 * a + i) + 0.004 * math.sin(5 * a))
    parts.append(g_smooth_mesh("FurBelt", fur, E["fur"], body, cap_end=False))
    fwd, up = Vector((0, -1, 0)), Vector((0, 0, 1))
    c = bc + Vector((0, -0.03, 0))
    parts.append(g_cap("SnowBuckle", c + Vector((0, 0.02, 0)), fwd, (1, 0, 0), 0.04, 0.04, 0.02, E["silver"], body, sides=18))
    for i in range(6):
        rd = Vector((math.cos(math.pi * i / 3 + math.pi / 6), 0, math.sin(math.pi * i / 3 + math.pi / 6)))
        parts.append(g_plate("SnowArm%d" % i, [(x * 0.018, y * 0.045) for x, y in G_DIAMOND], c + rd * 0.055, rd.cross(fwd), rd,
                             0.012, E["silver"], body))
        parts.append(g_plate("SnowArmTip%d" % i, [(x * 0.03, y * 0.016) for x, y in G_DIAMOND], c + rd * 0.078, rd.cross(fwd),
                             rd, 0.012, E["silver"], body))
    parts.append(g_cap("SnowBuckleGem", c + Vector((0, 0.008, 0)), fwd, (1, 0, 0), 0.024, 0.024, 0.018, E["deep"], body, rings=5,
                       sides=14))
    for j in range(16):
        a = (j - 7.5) * 0.19
        q = hit_a(a, 0.975, 0.04)
        parts.append(g_shard("BeltIcicle%d" % j, q + up * 0.012, q - up * (0.075 + 0.045 * (j % 2)) + rad(a) * 0.012, 0.014,
                             E["ice"], body, twist=j * 0.6))
    for k, z in enumerate((1.3, 1.24, 1.18, 1.125)):
        parts.append(g_gem("IceButton%d" % k, hit_x(0.0, z, 0.004), 0.011, 0.017, 0.007, E["deep"], body))


for _k, _fn, _o in (("lich", tx_lich, dict(wraps=2, plastron=False, buckle=False, fang=False, belt_chains=False,
                                           mantle_cut=0.7, vee=0.07)),
                    ("hierophant", tx_hiero, dict(fang=False, belt_chains=False, knot=False, tabard=False)),
                    ("reaper", tx_reaper, dict(plastron=False, belt_swags=1, tabard=False, mantle_cut=0.85)),
                    ("raven", tx_raven, dict(plastron=False, fang=False, belt_chains=False, knot=False)),
                    ("dragon", tx_dragon, dict(wraps=2, plastron=False, belt_chains=False, knot=False, mantle_cut=0.7,
                                               vee=0.05)),
                    ("astral", tx_astral, dict(fang=False, belt_swags=1)),
                    ("frost", tx_frost, dict(wraps=1, plastron=False, buckle=False, fang=False, belt_chains=False,
                                             knot=False))):
    ROBES[_k]["o"].update(_o, torso_extra=_fn)


# ------------------------------------------------------------------ mangas dos conjuntos de fim de jogo
# Gancho o["sleeve_extra"](X), chamado uma vez por braço: X = anéis do sino (rings, cen, n, S), eixo do
# antebraço (d), lado (s, sn) e a lista parts (enfeites rígidos no antebraço).
def sx_pt(X, i, j, lift=0.0):
    q, c = X["rings"][i][j % X["S"]], X["cen"][i]
    return q + (q - c).normalized() * lift


def sx_nrm(X, i, j):
    return (X["rings"][i][j % X["S"]] - X["cen"][i]).normalized()


def sx_loop(X, i, lift):
    """Volta do sino no anel i, começando de lado (o cordão não pode começar andando em x)."""
    S = X["S"]
    return [sx_pt(X, i, j + S // 4, lift) for j in range(S)]


def sx_outer(X):
    return X["S"] // 4 if X["s"] > 0 else 3 * X["S"] // 4


def sx_lich(X):
    """Três esporões de osso pela aresta de fora do antebraço."""
    E = eg_mats("eg_lich", bone="#D9D1B8")
    n, d, jo = X["n"], X["d"], sx_outer(X)
    for k, i in enumerate((n - 9, n - 6, n - 3)):
        b, nr = sx_pt(X, i, jo, -0.004), sx_nrm(X, i, jo)
        X["parts"].append(g_cone("SleeveSpur%s%d" % (X["sn"], k), [b, b + nr * 0.035 - d * 0.012, b + nr * 0.08 - d * 0.045],
                                 0.013, E["bone"], X["elbow"], sides=8))


def sx_hiero(X):
    """Punho largo dourado fechando a manga bufante, com losangos vermelhos."""
    A, n, S = X["A"], X["n"], X["S"]
    band = [[sx_pt(X, i, j, 0.004) for j in range(S)] for i in (n - 3, n - 2, n - 1, n)]
    X["parts"].append(g_smooth_mesh("SleeveCuffBand" + X["sn"], band, A["gold2"], X["elbow"], cap_end=False, thick=0.008))
    for j in range(0, S, 4):
        q, nr = sx_pt(X, n - 2, j, 0.006), sx_nrm(X, n - 2, j)
        up = (X["rings"][n - 3][j] - X["rings"][n - 1][j]).normalized()
        X["parts"].append(g_plate("SleeveCuffDia%s%d" % (X["sn"], j), [(x * 0.013, y * 0.017) for x, y in G_DIAMOND], q,
                                  up.cross(nr), up, 0.012, A["lining"], X["elbow"]))


def sx_reaper(X):
    """Aro roxo aceso perto da boca da manga e três lâminas de aço pela aresta de fora do antebraço."""
    E = eg_mats("eg_reaper", steel="#8E93A3", glow=("#E0B8FF", "#A050FF", 2.2))
    n, d, jo = X["n"], X["d"], sx_outer(X)
    X["parts"].append(g_pipe("SleeveGlow" + X["sn"], sx_loop(X, n - 4, 0.003), 0.005, E["glow"], X["elbow"], loop=True))
    for k, i in enumerate((n - 10, n - 7, n - 4)):
        b, nr = sx_pt(X, i, jo, -0.004), sx_nrm(X, i, jo)
        pth = [b, b + nr * 0.03 - d * 0.02, b + nr * 0.075 - d * 0.06]
        rad = [(0.006, 0.026), (0.005, 0.018), (0.001, 0.002)]
        X["parts"].append(g_smooth_mesh("SleeveBlade%s%d" % (X["sn"], k), g_curved_tube(pth, rad, sides=10, side0=(0, 1, 0)),
                                        E["steel"], X["elbow"]))


def sx_raven(X):
    """Asa: penas compridas penduradas pela linha de trás do antebraço, cada vez maiores rumo ao pulso."""
    E = eg_mats("eg_raven", feather="#1C1E2C", sheen="#2F4270")
    n, d, s, jb = X["n"], X["d"], X["s"], X["S"] // 2
    for k, i in enumerate(range(n - 10, n + 1, 2)):
        b, nr = sx_pt(X, i, jb, -0.004), sx_nrm(X, i, jb)
        X["parts"].append(g_feather("SleeveFeather%s%d" % (X["sn"], k), b, nr * 0.8 + d * 0.55, (s * 0.75, -0.65, 0),
                                    0.15 + 0.03 * k, 0.032, E["sheen" if k % 2 else "feather"], X["elbow"], curl=0.1))


def sx_dragon(X):
    """Braçadeira de três lâminas de escama por fora do antebraço e um chifre no cotovelo."""
    E = eg_mats("eg_dragon", scale="#7A1E26", gold="#D09A3A", horn="#D8CCB0")
    n, d, jo, jb = X["n"], X["d"], sx_outer(X), X["S"] // 2
    for k, i in enumerate((7, 10, 13)):
        c, nr = sx_pt(X, i, jo, -0.004), sx_nrm(X, i, jo)
        nm = "Vambrace%s%d" % (X["sn"], k)
        X["parts"].append(g_cap(nm, c, nr, d, 0.052, 0.042, 0.024, E["scale"], X["elbow"], sides=16))
        X["parts"].append(g_pipe(nm + "Rim", [g_cap_pt(c, nr, d, 0.052, 0.042, 0.024, 2 * math.pi * j / 20, 0.1, 0.002)
                                              for j in range(20)], 0.005, E["gold"], X["elbow"], loop=True))
    b, nr = sx_pt(X, 5, jb, -0.006), sx_nrm(X, 5, jb)
    X["parts"].append(g_cone("ElbowHorn" + X["sn"], [b, b + nr * 0.05 - d * 0.02, b + nr * 0.1 - d * 0.075], 0.02, E["horn"],
                             X["elbow"], sides=10, ridge=0.002))


def sx_astral(X):
    """Estrelas grandes bordadas por fora do sino e um pingente de estrela preso à ponta de trás da boca."""
    A, n, S, jo, jb = X["A"], X["n"], X["S"], sx_outer(X), X["S"] // 2
    for k, dj in enumerate((-6, 0, 6)):
        j = jo + dj
        q, nr = sx_pt(X, n - 6, j, 0.004), sx_nrm(X, n - 6, j)
        up = (X["rings"][n - 7][j % S] - X["rings"][n - 5][j % S]).normalized()
        X["parts"].append(g_plate("SleeveStar%s%d" % (X["sn"], k), g_star4(0.03 if dj == 0 else 0.022, 0.008), q,
                                  up.cross(nr), up, 0.008, A["gold2"], X["elbow"]))
    tip = sx_pt(X, n, jb, 0.0)
    dn = Vector((0, 0, -1))
    X["parts"].append(g_cone("SleeveCharmCord" + X["sn"], [tip + dn * -0.004, tip + dn * 0.05], 0.003, A["gold2"], X["elbow"],
                             sides=6, n=2, r1=0.003))
    X["parts"].append(g_bead("SleeveCharmBead" + X["sn"], tip + dn * 0.055, 0.01, A["gem"], X["elbow"]))
    X["parts"].append(g_plate("SleeveCharm" + X["sn"], g_star4(0.03, 0.01), tip + dn * 0.1, (1, 0, 0), (0, 0, 1), 0.007,
                              A["gold2"], X["elbow"]))


def sx_frost(X):
    """Punho de pele em volta da boca da manga e três cristais de gelo pela aresta de fora do antebraço."""
    E = eg_mats("eg_frost", fur="#F2F6FA", ice=("#8FD0F2", "#5FB8F0", 0.35))
    n, d, jo = X["n"], X["d"], sx_outer(X)
    path = sx_loop(X, n - 1, 0.012)
    path += path[:2]
    fur = g_curved_tube(path, [(0.032, 0.028)] * len(path), sides=14, side0=tuple(d),
                        wob=lambda i, a: 0.005 * math.sin(i * 2.3) * math.sin(3 * a + i))
    X["parts"].append(g_smooth_mesh("SleeveFur" + X["sn"], fur, E["fur"], X["elbow"], cap_end=False))
    for k, i in enumerate((n - 10, n - 7, n - 4)):
        b, nr = sx_pt(X, i, jo, 0.0), sx_nrm(X, i, jo)
        X["parts"].append(g_shard("SleeveIce%s%d" % (X["sn"], k), b - nr * 0.012, b + nr * (0.085 - 0.012 * k) - d * 0.03, 0.017,
                                  E["ice"], X["elbow"], twist=k * 0.8))


for _k, _fn, _o in (("lich", sx_lich, dict(bell=2.4, droop=0.25, bell_tatter=0.05, bell_tatter_n=7, bell_sides=56,
                                           bell_diamonds=False)),
                    ("hierophant", sx_hiero, dict(bell_rx=(0.073, 0.086, 0.112, 0.122, 0.072),
                                                  bell_ry=(0.075, 0.092, 0.128, 0.138, 0.078), droop=0.0, bell_len=-0.03,
                                                  bell_diamonds=False)),
                    ("reaper", sx_reaper, dict(bell=2.2, droop=0.22, bell_tatter=0.06, bell_tatter_n=9, bell_sides=56,
                                               bell_diamonds=False)),
                    ("raven", sx_raven, dict(bell=1.2, droop=0.08, bell_diamonds=False)),
                    ("dragon", sx_dragon, dict(bell=0.3, droop=0.0, bell_len=-0.06, bell_diamonds=False)),
                    ("astral", sx_astral, dict(bell=2.0, droop=0.2)),
                    ("frost", sx_frost, dict(bell=1.5, droop=0.1, bell_diamonds=False))):
    ROBES[_k]["o"].update(_o, sleeve_extra=_fn)


# ------------------------------------------------------------------ saia dos conjuntos de fim de jogo
# Gancho o["skirt_extra"](X): X = grade de fora do casaco (outer[fiada][coluna], rows, NC, H) e as listas soft
# (pano, pesos por vértice) e orn (enfeites, pesos do ponto onde estão).
def kx_nr(q):
    return Vector((q.x, q.y, 0)).normalized()


def kx_halves(X):
    return (range(0, X["H"] + 1), range(X["H"] + 1, X["NC"] + 1))


def kx_front(z, out=0.03):
    t = (1.0 - z) / 0.9
    return Vector((0, 0.005 - (0.14 + 0.13 * t ** 0.8 + 0.016 + out), z))


def kx_lich(X):
    """Espinha de vértebras caindo da caveira da fivela até a canela, com esporões, e uma caveira na ponta."""
    E = eg_mats("eg_lich", bone="#D9D1B8", glow=("#B8FFC0", "#5CFF7A", 2.0))
    orn, body = X["orn"], X["body"]
    for k in range(13):
        q = kx_front(0.945 - 0.033 * k, 0.0)
        orn.append(g_bead("SkirtVertebra%d" % k, q, 0.022 - 0.0006 * k, E["bone"], body))
        if k % 2 == 0:
            for i, sx in enumerate((-1, 1)):
                orn.append(g_cone("SkirtSpur%d_%d" % (k, i), [q, q + Vector((sx * (0.06 - 0.002 * k), -0.006, -0.02))], 0.009,
                                  E["bone"], body, sides=6, n=3))
    q = kx_front(0.945 - 0.033 * 13 - 0.012, 0.0)
    orn += mx_skull("SkirtSkull", q + Vector((0, 0.012, 0)), Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)),
                    E["bone"], E["glow"], body, 1.0)


def kx_hiero(X):
    """Barra larga dourada em volta do casaco, com losangos vermelhos."""
    A, outer, rows, soft, orn, body = X["A"], X["outer"], X["rows"], X["soft"], X["orn"], X["body"]
    for h, js in enumerate(kx_halves(X)):
        band = [[outer[i][j] + kx_nr(outer[i][j]) * 0.004 for j in js] for i in (rows - 4, rows - 3, rows - 2)]
        soft.append(g_smooth_mesh("HemBand%d" % h, band, A["gold2"], body, cap_end=False, closed=False, thick=0.006,
                                  outward=True))
    for j in range(4, X["NC"] - 3, 6):
        if abs(j - X["H"]) < 2:
            continue
        q = outer[rows - 3][j]
        nr, up = kx_nr(q), (outer[rows - 4][j] - outer[rows - 2][j]).normalized()
        orn.append(g_plate("HemBandDia%d" % j, [(x * 0.02, y * 0.026) for x, y in G_DIAMOND], q + nr * 0.005, up.cross(nr), up,
                           0.012, A["lining"], body))


def kx_reaper(X):
    """Fio roxo aceso acima da barra em tiras."""
    E = eg_mats("eg_reaper", glow=("#E0B8FF", "#A050FF", 2.2))
    for h, js in enumerate(kx_halves(X)):
        X["soft"].append(g_pipe("HemGlow%d" % h, [X["outer"][X["rows"] - 4][j] + kx_nr(X["outer"][X["rows"] - 4][j]) * 0.004
                                                  for j in js], 0.005, E["glow"], X["body"]))


def kx_raven(X):
    """Duas fiadas de penas compridas na metade de baixo do casaco, a de baixo passando da barra."""
    E = eg_mats("eg_raven", feather="#1C1E2C", sheen="#2F4270")
    outer, rows, NC = X["outer"], X["rows"], X["NC"]
    for r, (i, cnt, ln) in enumerate(((rows - 6, 24, 0.21), (rows - 3, 32, 0.25))):
        for k in range(cnt):
            j = min(NC, int(round((k + 0.5 * r) * NC / cnt)))
            if abs(j - X["H"]) < 1:
                continue
            q = outer[i][j]
            nr = kx_nr(q)
            dn = (outer[min(i + 1, rows)][j] - outer[i - 1][j]).normalized()
            X["orn"].append(g_feather("SkirtFeather%d_%d" % (r, k), q - nr * 0.003, dn + nr * 0.08, nr, ln, 0.036,
                                      E["sheen" if (k + r) % 3 == 0 else "feather"], X["body"], curl=0.05))


def kx_dragon(X):
    """Três fiadas de escamas desencontradas na parte de baixo do casaco."""
    E = eg_mats("eg_dragon", scale="#7A1E26", plate="#4E1218", gold="#D09A3A")
    outer, rows, NC = X["outer"], X["rows"], X["NC"]
    sc = [(-1, 0.8), (1, 0.8), (1, -0.2), (0, -1.25), (-1, -0.2)]
    for r, i in enumerate((rows - 6, rows - 4, rows - 2)):
        for j in range(2 + r % 2, NC - 1, 2):
            if abs(j - X["H"]) < 1:
                continue
            q = outer[i][j]
            nr, up = kx_nr(q), (outer[i - 1][j] - outer[i + 1][j]).normalized()
            X["orn"].append(g_plate("SkirtScale%d_%d" % (r, j), [(x * 0.03, y * 0.036) for x, y in sc], q + nr * 0.004,
                                    up.cross(nr), up, 0.009, E["gold" if (r == 2 and j % 4 == 0) else
                                                               ("scale" if (j // 2 + r) % 2 else "plate")], X["body"]))


def kx_astral(X):
    """Anel dourado inclinado em volta dos quadris, como o de um planeta, com dois astros presos."""
    A, orn, body = X["A"], X["orn"], X["body"]
    ring = lambda th, k=1.0: Vector((math.cos(th) * 0.268 * k, 0.005 + math.sin(th) * 0.37 * k, 0.72 - math.sin(th) * 0.1))
    orn.append(g_pipe("SaturnRing", [ring(2 * math.pi * i / 56) for i in range(56)], 0.008, A["gold2"], body, loop=True))
    orn.append(g_pipe("SaturnRing2", [ring(2 * math.pi * i / 56, 1.07) for i in range(56)], 0.0035, A["gold2"], body, loop=True))
    for i in range(8):
        th = 2 * math.pi * (i + 0.5) / 8
        orn.append(g_cone("SaturnTie%d" % i, [ring(th), ring(th, 1.07)], 0.003, A["gold2"], body, sides=5, n=2, r1=0.003))
    orn.append(g_bead("SaturnPlanet", ring(-1.15, 1.035), 0.03, A["gem"], body))
    orn.append(g_bead("SaturnMoon", ring(-2.3, 1.035), 0.018, A["gold2"], body))
    orn.append(g_bead("SaturnMoon2", ring(2.0, 1.035), 0.02, A["gem"], body))


def kx_frost(X):
    """Barra de pele grossa em volta do casaco."""
    E = eg_mats("eg_frost", fur="#F2F6FA")
    for h, js in enumerate(kx_halves(X)):
        path = [X["outer"][X["rows"]][j] + kx_nr(X["outer"][X["rows"]][j]) * 0.012 + Vector((0, 0, 0.02)) for j in js]
        fur = g_curved_tube(path, [(0.036, 0.04)] * len(path), sides=14, side0=(0, 0, 1),
                            wob=lambda i, a: 0.006 * math.sin(i * 2.3) * math.sin(3 * a + i))
        X["soft"].append(g_smooth_mesh("HemFur%d" % h, fur, E["fur"], X["body"]))


def kx_void(X):
    """Fendas de energia (ref. "Celestial Knight", Natam Antony): faixas finas que descem pelo casaco do peito
    até perto da barra, mais largas no meio e em ponta nas duas pontas, ondulando um pouco de lado. Ficam por
    cima do pano (2 mm) e com os pesos do casaco; o brilho vem do shader gear_energy (GearFx, rb_void_slit)."""
    outer, rows, NC = X["outer"], X["rows"], X["NC"]
    slit = gm("rb_void_slit", "#2F7BFF", 0.9)

    def on_coat(i, jf):
        j0 = int(jf)
        f = jf - j0
        q = outer[i][j0] * (1 - f) + outer[i][min(j0 + 1, NC)] * f
        return q + kx_nr(q) * 0.002
    # (coluna em fração da volta, fiada de cima, fiada de baixo, meia largura, fase da ondulação)
    for k, (u, i0, i1, w, ph) in enumerate(((0.034, 0, 12, 0.013, 0.0), (0.16, 1, 11, 0.013, 1.7),
                                            (0.32, 0, 12, 0.013, 3.1))):
        for side, uu in (("L", u), ("R", 1.0 - u)):
            n = 16
            path, radii = [], []
            for q in range(n + 1):
                t = q / n
                i = i0 + (i1 - i0) * t
                jf = uu * NC + 1.1 * math.sin(math.pi * t * 1.3 + ph) * (1 if side == "L" else -1)
                ia = int(min(i, rows - 1))
                path.append(on_coat(ia, jf).lerp(on_coat(ia + 1, jf), i - ia))
                radii.append((w * max(0.08, math.sin(math.pi * min(1.0, 0.04 + t * 0.96)) ** 0.6), 0.0016))
            p0 = path[0]
            tang = Vector((-p0.y, p0.x, 0)).normalized()          # largura em volta do casaco, face no pano
            X["soft"].append(g_smooth_mesh("VoidSlit%s%d" % (side, k), g_curved_tube(path, radii, sides=10, side0=tang),
                                           slit, X["body"]))


for _k, _fn, _o in (("lich", kx_lich, dict(coat_tatter=0.08, coat_tatter_n=9, coat_n=128, hem_pts=4, tabard=False,
                                           coat_diamonds=False)),
                    ("hierophant", kx_hiero, dict(open=0.3, hem_pts=0, coat_stars=False, coat_diamonds=False)),
                    ("reaper", kx_reaper, dict(coat_tatter=0.11, coat_tatter_n=12, coat_n=128, coat_stars=False,
                                               coat_diamonds=False, back_seam=False)),
                    ("raven", kx_raven, dict(tabard=False, coat_stars=False, coat_diamonds=False, hem_pts=0)),
                    ("dragon", kx_dragon, dict(coat_hem=0.3, hem_pts=2, coat_stars=False, coat_diamonds=False)),
                    ("astral", kx_astral, dict(hem_pts=5)),
                    ("frost", kx_frost, dict(tabard=False, hem_pts=0, coat_diamonds=False)),
                    ("void", kx_void, dict())):
    ROBES[_k]["o"].update(_o, skirt_extra=_fn)


_robe_builders()


# ================================================================== CABEÇAS DE FIM DE JOGO (nível 50)
# Sete conjuntos de silhueta própria (não são recolorações do Arquimago): Lich Soberano, Hierofante Solar,
# Ceifador do Vazio, Senhor dos Corvos, Mago de Guerra Dracônico, Astrônomo Celeste e Soberano do Gelo.
SKULL_C = Vector((0, 0.012, 1.69))


def g_skull(th, z, out=0.0):
    """Ponto na cabeça com cabelo, na altura z e no ângulo th (0 = frente, pi = nuca), afastado out."""
    k = math.sqrt(max(0.05, 1 - ((z - SKULL_C.z) / 0.142) ** 2))
    return Vector((math.sin(th) * (0.131 * k + out), SKULL_C.y - math.cos(th) * (0.145 * k + out), z))


def g_headring(zf, out=0.004, n=40):
    """Volta em torno da cabeça, começando do lado (o cordão de g_pipe não pode começar andando em x)."""
    return [g_skull(math.pi / 2 + 2 * math.pi * i / n, zf(math.pi / 2 + 2 * math.pi * i / n), out) for i in range(n)]


def g_circle(c, u, v, r, n=32):
    c, u, v = Vector(c), Vector(u).normalized(), Vector(v).normalized()
    return [c + (u * math.cos(2 * math.pi * i / n) + v * math.sin(2 * math.pi * i / n)) * r for i in range(n)]


def g_side(path):
    t = (path[-1] - path[0]).normalized()
    return (0, 0, 1) if abs(t.x) > 0.75 else (1, 0, 0)


def g_cone(name, ctrl, r0, material, parent, sides=10, r1=0.0015, n=10, pw=1.0, ridge=0.0, side0=None):
    """Chifre, espinho ou haste: tubo liso pela curva de ctrl, afinando de r0 a r1 (ridge = anéis em relevo)."""
    ctrl = [Vector(c) for c in ctrl]
    path = g_spline(ctrl, n) if len(ctrl) > 2 else [ctrl[0].lerp(ctrl[1], i / n) for i in range(n + 1)]
    radii = [(r0 + (r1 - r0) * (i / n) ** pw,) * 2 for i in range(n + 1)]
    wob = (lambda i, a: ridge * math.sin(i * 2.4) * (1 - i / n)) if ridge else None
    return g_smooth_mesh(name, g_curved_tube(path, radii, sides=sides, wob=wob, side0=side0 or g_side(path)),
                         material, parent)


def g_ribbon(name, ctrl, w, material, parent, t=0.004, n=14, side0=(1, 0, 0)):
    """Fita lisa pela curva de ctrl: meia largura w ao longo de side0, meia espessura t."""
    path = g_spline([Vector(c) for c in ctrl], n)
    return g_smooth_mesh(name, g_curved_tube(path, [(w, t)] * (n + 1), sides=12, side0=side0), material, parent)


def g_feather(name, base, d, up, ln, w, material, parent, curl=0.2, n=9):
    """Pena: lâmina fina que sai de base na direção d e encurva para up; a face larga olha para up."""
    base, d, up = Vector(base), Vector(d).normalized(), Vector(up).normalized()
    path = [base + d * (ln * i / n) + up * (curl * ln * (i / n) ** 2) for i in range(n + 1)]
    radii = [(w * max(0.06, math.sin(math.pi * (0.1 + 0.9 * i / n)) ** 0.7), 0.0045) for i in range(n + 1)]
    return g_smooth_mesh(name, g_curved_tube(path, radii, sides=10, side0=tuple(d.cross(up))), material, parent)


def g_shard(name, base, tip, r, material, parent, sides=6, waist=0.7, twist=0.0):
    """Cristal facetado: prisma de base a tip, mais largo em waist e fechado em ponta."""
    base, tip = Vector(base), Vector(tip)
    ax = tip - base
    ln = ax.length
    ax.normalize()
    s = Vector((1, 0, 0)) if abs(ax.x) < 0.8 else Vector((0, 0, 1))
    s = (s - ax * s.dot(ax)).normalized()
    f = ax.cross(s)
    bm = bmesh.new()

    def ring(dist, rr):
        return [bm.verts.new(base + ax * dist + (s * math.cos(twist + 2 * math.pi * j / sides)
                                                 + f * math.sin(twist + 2 * math.pi * j / sides)) * rr)
                for j in range(sides)]
    a, b = ring(0.0, r * 0.62), ring(ln * waist, r)
    t = bm.verts.new(tip)
    bm.faces.new(a[::-1])
    for j in range(sides):
        k = (j + 1) % sides
        bm.faces.new((a[j], a[k], b[k], b[j]))
        bm.faces.new((b[j], b[k], t))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    print("PART", name, "shard", flush=True)
    return _finish(name, bm, material, parent)


def g_head(style, hair=True):
    P, R = g_rig(style)
    plain_head(R, g_mats(), hair=hair)
    return P, R, R["Head"]


def g_head_done(style, name, parts, P, R):
    if "loose_parts" in globals():
        loose_parts(style)
    join_objs(name, parts)
    g_export(style, P, R)


def eg_mats(pre, **c):
    """Materiais de um conjunto: cor simples, ou (cor, brilho, força) para o que acende."""
    out = {}
    for k, v in c.items():
        if isinstance(v, tuple):
            out[k] = mat("%s_%s_gem_flat" % (pre, k), hexc(v[0]), 0.3, 0.0, emit=hexc(v[1]), strength=v[2])
        else:
            metal = k in ("gold", "silver", "steel")
            out[k] = gm("%s_%s" % (pre, k), v, 0.45 if metal or k in ("bone", "horn", "lacquer") else 0.92,
                        0.3 if metal else 0.0)
    return out


# ------------------------------------------------------------------ 1. Lich Soberano
def build_h_lich():
    """Capuz fundo com coroa de espinhos de osso no alto e, atrás da cabeça, um aro de ferro com espinhos."""
    A = eg_mats("eg_lich", cloth="#18211D", lining="#2F5A3C", bone="#D9D1B8", iron="#2B2F2C",
                glow=("#B8FFC0", "#5CFF7A", 2.0))
    HA = dict(felt=A["cloth"], hatlining=A["lining"], gold2=A["bone"], gem=A["glow"], motif=A["glow"])

    def extra(head, hp, hc):
        parts = []
        ax_of = lambda p: (p - Vector((0, hc.y, p.z))).normalized()
        ring = [hp(math.pi / 2 + 2 * math.pi * i / 36, 1.0) for i in range(36)]
        parts.append(g_pipe("LichBand", [p + ax_of(p) * 0.004 for p in ring], 0.012, A["bone"], head, loop=True))
        lens = [0.22, 0.12, 0.17, 0.11, 0.15, 0.15, 0.11, 0.17, 0.12]
        for k, ln in enumerate(lens):
            th = 2 * math.pi * k / len(lens)
            b = hp(th, 1.0)
            od = Vector((math.sin(th), -math.cos(th), 0))
            up = Vector((0, 0, 1))
            parts.append(g_cone("LichSpike%d" % k, [b - up * 0.014, b + od * 0.04 + up * 0.4 * ln,
                                                    b + od * 0.068 + up * 0.75 * ln, b + od * 0.05 + up * ln],
                                0.015, A["bone"], head, sides=8))
            if ln > 0.14:
                parts.append(g_cap("LichJewel%d" % k, b + od * 0.012 + up * 0.004, od + up * 0.3, up, 0.009, 0.012,
                                   0.008, A["glow"], head, rings=4, sides=10))
        # aro de espinhos atrás da cabeça, preso por raios a um botão na nuca do capuz
        C = Vector((0, hc.y + 0.2, 1.765))
        rr = 0.215
        parts.append(g_pipe("LichHalo", g_circle(C, (1, 0, 0), (0, 0, 1), rr, 40), 0.009, A["iron"], head, loop=True))
        for i in range(16):
            a = 2 * math.pi * i / 16
            rd = Vector((math.cos(a), 0, math.sin(a)))
            ln = 0.095 if i % 2 == 0 else 0.05
            parts.append(g_cone("LichThorn%d" % i, [C + rd * (rr - 0.006), C + rd * (rr + ln)], 0.01, A["bone"], head,
                                sides=6, n=3))
            if i % 2 == 0:
                parts.append(g_cone("LichSpoke%d" % i, [C + rd * 0.02, C + rd * rr], 0.006, A["iron"], head,
                                    sides=6, n=2, r1=0.004))
        parts.append(g_cap("LichBoss", C + Vector((0, -0.03, 0)), (0, 1, 0), (1, 0, 0), 0.04, 0.04, 0.04, A["iron"],
                           head, sides=14))
        parts.append(g_cap("LichBossEye", C + Vector((0, 0.004, 0)), (0, 1, 0), (1, 0, 0), 0.02, 0.02, 0.014, A["glow"],
                           head, rings=4, sides=12))
        return parts
    build_hood("h_lich", HA, dict(tail=0.3, crest="none"), extra=extra)


# ------------------------------------------------------------------ 2. Hierofante Solar
def build_h_hierophant():
    """Mitra alta de dois painéis em ogiva (frente e trás), friso e gema, duas ínfulas caindo na nuca e um
    disco solar de raios atrás da cabeça."""
    P, R, head = g_head("h_hierophant")
    A = eg_mats("eg_hiero", cloth="#ECE5D2", red="#8E2030", gold="#E0B040", glow=("#FFE6A8", "#FFC050", 1.6))
    cy, z0, hh = SKULL_C.y, 1.752, 0.3
    parts = []

    def pan(sg, s, u, out=0.0):
        w = max(0.03, 1 - u ** 1.8) ** 0.62
        th = s * (math.pi / 2) * w + (math.pi if sg > 0 else 0.0)
        k = 1 + 0.2 * math.sin(math.pi * u ** 0.85) + out
        return Vector((math.sin(th) * 0.124 * k, cy - math.cos(th) * 0.137 * k * (1 - 0.5 * u), z0 + u * hh))
    for sg, nm in ((-1, "F"), (1, "B")):
        rows = [[pan(sg, -1 + 2 * j / 16, i / 12) for j in range(17)] for i in range(13)]
        parts.append(g_smooth_mesh("Mitre" + nm, rows, A["cloth"], head, cap_end=False, closed=False, thick=0.01,
                                   outward=True))
        edge = [pan(sg, -1, i / 12, 0.012) for i in range(13)] + [pan(sg, 1, i / 12, 0.012) for i in range(11, -1, -1)]
        parts.append(g_pipe("MitreEdge" + nm, edge, 0.007, A["gold"], head))
        orph = [pan(sg, 0, i / 12, 0.014) for i in range(12)]
        parts.append(g_smooth_mesh("MitreOrph" + nm, g_curved_tube(orph, [(0.016, 0.005)] * 12, sides=10),
                                   A["gold"], head))
    band = [[Vector((math.sin(a) * 0.124 * k, cy - math.cos(a) * 0.137 * k, z0 + dz))
             for a in (math.pi / 2 + 2 * math.pi * j / 40 for j in range(40))]
            for dz, k in ((-0.018, 1.03), (0.004, 1.075), (0.03, 1.115))]
    parts.append(g_smooth_mesh("MitreBand", band, A["gold"], head, cap_end=False, thick=0.008))
    parts.append(g_cap("MitreCap", (0, cy, z0), (0, 0, 1), (1, 0, 0), 0.118, 0.13, 0.1, A["red"], head, sides=24))
    f = pan(-1, 0, 0.42, 0.03)
    nf = Vector((0, -1, 0.2))
    parts.append(g_cap("MitreSeat", f, nf, (1, 0, 0), 0.027, 0.034, 0.012, A["gold"], head, sides=16))
    parts.append(g_cap("MitreGem", f + nf.normalized() * 0.008, nf, (1, 0, 0), 0.016, 0.022, 0.012, A["glow"], head,
                       rings=5, sides=14))
    for u in (0.2, 0.66):
        parts.append(g_plate("MitreDia%d" % int(u * 100), [(x * 0.02, y * 0.022) for x, y in G_DIAMOND],
                             pan(-1, 0, u, 0.045), (1, 0, 0), (0, 0, 1), 0.012, A["glow"], head))
    for sx, nm in ((-1, "L"), (1, "R")):
        parts.append(g_ribbon("Lappet" + nm, [(sx * 0.05, cy + 0.14, z0 - 0.005), (sx * 0.064, cy + 0.168, 1.66),
                                              (sx * 0.074, cy + 0.152, 1.54), (sx * 0.086, cy + 0.172, 1.42)],
                              0.025, A["cloth"], head))
        parts.append(g_ribbon("LappetEnd" + nm, [(sx * 0.083, cy + 0.168, 1.452), (sx * 0.0855, cy + 0.171, 1.43),
                                                 (sx * 0.087, cy + 0.173, 1.412)], 0.028, A["gold"], head, t=0.006, n=4))
    # disco solar: aro, aro de dentro, raios longos e curtos, preso à mitra por uma haste
    C = Vector((0, cy + 0.215, 1.83))
    parts.append(g_pipe("SunRing", g_circle(C, (1, 0, 0), (0, 0, 1), 0.2, 40), 0.011, A["gold"], head, loop=True))
    parts.append(g_pipe("SunRing2", g_circle(C, (1, 0, 0), (0, 0, 1), 0.15, 36), 0.006, A["gold"], head, loop=True))
    for i in range(16):
        a = 2 * math.pi * i / 16 + math.pi / 16
        rd = Vector((math.cos(a), 0, math.sin(a)))
        tn = Vector((-math.sin(a), 0, math.cos(a)))
        ln = 0.11 if i % 2 == 0 else 0.06
        parts.append(g_plate("SunRay%d" % i, [(x * 0.03, y * ln / 2) for x, y in G_DIAMOND],
                             C + rd * (0.2 + ln / 2 - 0.008), tn, rd, 0.01, A["gold"], head))
        if i % 2 == 0:
            parts.append(g_cone("SunSpoke%d" % i, [C + rd * 0.02, C + rd * 0.2], 0.005, A["gold"], head, sides=6, n=2,
                                r1=0.005))
    parts.append(g_cone("SunStem", [(0, cy + 0.13, 1.83), C + Vector((0, 0.021, 0))], 0.014, A["gold"], head, sides=8, n=2, r1=0.012))
    parts.append(g_cap("SunBoss", C - Vector((0, 0.012, 0)), (0, 1, 0), (1, 0, 0), 0.036, 0.036, 0.03, A["gold"], head,
                       sides=16))
    parts.append(g_cap("SunBossGem", C + Vector((0, 0.012, 0)), (0, 1, 0), (1, 0, 0), 0.02, 0.02, 0.014, A["glow"], head,
                       rings=4, sides=12))
    g_head_done("h_hierophant", "Mitre", parts, P, R)


# ------------------------------------------------------------------ 3. Ceifador do Vazio
def build_h_reaper():
    """Capuz fundo com máscara de caveira de olhos acesos, lâmina em cruz no alto da testa e, atrás da cabeça,
    três foices em arco de cada lado em volta de um disco com uma galáxia (animada no jogo)."""
    A = eg_mats("eg_reaper", cloth="#16141C", lining="#2A1F40", bone="#D6D0C4", steel="#8E93A3", iron="#24222C",
                glow=("#E0B8FF", "#A050FF", 2.2), space=("#120A30", "#22145C", 0.7))
    HA = dict(felt=A["cloth"], hatlining=A["lining"], gold2=A["steel"], gem=A["glow"], motif=A["glow"])

    def extra(head, hp, hc):
        parts = []
        mc = Vector((0, 0.012, 1.685))

        def mp(th, ph, out=0.0):
            jaw = 1 - 0.38 * max(0.0, (-0.25 - ph) / 0.55)
            return Vector((math.sin(th) * math.cos(ph) ** 0.7 * (0.118 + out) * jaw,
                           mc.y - math.cos(th) * math.cos(ph) ** 0.55 * (0.16 + out), mc.z + math.sin(ph) * (0.16 + out)))

        def frame(p):
            n = (p - mc).normalized()
            u = Vector((0, 0, 1)).cross(n).normalized()
            return n, u, n.cross(u)
        rows = [[mp(-0.95 + 1.9 * j / 20, -0.98 + 1.83 * i / 18) for j in range(21)] for i in range(19)]
        parts.append(g_smooth_mesh("SkullMask", rows, A["bone"], head, cap_end=False, closed=False, thick=0.008,
                                   outward=True))
        eye = [(-1, 0.55), (-0.2, 0.75), (0.8, 0.35), (1, -0.1), (0.4, -0.65), (-0.5, -0.6), (-1, -0.2)]
        for k, sx in enumerate((-1, 1)):
            e = mp(sx * 0.37, 0.05, 0.003)
            n, u, v = frame(e)
            parts.append(g_plate("SkullEye%d" % k, [(-sx * x * 0.027, y * 0.021) for x, y in eye], e, u, v, 0.004,
                                 A["iron"], head))
            parts.append(g_plate("SkullPupil%d" % k, [(x * 0.013, y * 0.011) for x, y in G_DIAMOND], e + n * 0.003, u, v,
                                 0.003, A["glow"], head))
        e = mp(0, -0.19, 0.003)
        n, u, v = frame(e)
        parts.append(g_plate("SkullNose", [(0, 0.02), (0.011, -0.016), (0, -0.008), (-0.011, -0.016)], e, u, v, 0.004,
                             A["iron"], head))
        for j in range(-3, 4):
            e = mp(j * 0.09, -0.5, 0.003)
            n, u, v = frame(e)
            parts.append(g_plate("SkullTooth%d" % (j + 3), [(-0.0028, 0.017), (0.0028, 0.017), (0.0028, -0.017),
                                                            (-0.0028, -0.017)], e, u, v, 0.004, A["iron"], head))
        # lâmina em cruz no alto da testa
        b = hp(0, 1.0) + Vector((0, -0.012, 0.075))
        parts.append(g_plate("ReaperCrest", [(0, 0.105), (0.012, 0.06), (0.008, -0.09), (-0.008, -0.09), (-0.012, 0.06)],
                             b, (1, 0, 0), (0, 0, 1), 0.008, A["steel"], head))
        parts.append(g_plate("ReaperCrestBar", [(-0.045, 0.006), (-0.05, 0), (-0.045, -0.006), (0.045, -0.006), (0.05, 0),
                                                (0.045, 0.006)], b + Vector((0, 0, 0.03)), (1, 0, 0), (0, 0, 1), 0.008,
                             A["steel"], head))
        parts.append(g_gem("ReaperCrestGem", b + Vector((0, -0.01, -0.045)), 0.012, 0.018, 0.007, A["glow"], head))
        # atrás da cabeça: disco, aro, raios e três foices em arco de cada lado
        C = Vector((0, hc.y + 0.2, 1.765))
        rv = 0.172
        # disco liso dos dois lados: a galáxia (névoa, braços em espiral, miolo e estrelas) é desenhada e animada
        # no jogo por assets/shaders/gear_galaxy.gdshader, a partir do UV gravado por g_galaxy_uv
        bm = bmesh.new()
        for sy in (-1, 1):          # fundo em grade fina (as estrelas encostam em vértices), uma face para cada lado
            grid = [[bm.verts.new(C + Vector((math.cos(2 * math.pi * j / 48) * rv * i / 14, sy * 0.003,
                                              math.sin(2 * math.pi * j / 48) * rv * i / 14))) for j in range(48)]
                    for i in range(1, 15)]
            cen = bm.verts.new(C + Vector((0, sy * 0.003, 0)))
            for j in range(48):
                k = (j + 1) % 48
                bm.faces.new((cen, grid[0][j], grid[0][k]) if sy < 0 else (cen, grid[0][k], grid[0][j]))
                for a, b2 in zip(grid, grid[1:]):
                    bm.faces.new((a[j], b2[j], b2[k], a[k]) if sy < 0 else (a[k], b2[k], b2[j], a[j]))
        bmesh.ops.translate(bm, vec=-_wloc(head), verts=bm.verts)
        parts.append(_finish("ReaperSpace", bm, A["space"], head))

        parts.append(g_pipe("ReaperRing", g_circle(C, (1, 0, 0), (0, 0, 1), rv + 0.006, 44), 0.009, A["iron"], head,
                            loop=True))
        parts.append(g_pipe("ReaperGlowRing", g_circle(C, (1, 0, 0), (0, 0, 1), rv + 0.02, 44), 0.0045, A["glow"], head,
                            loop=True))
        parts.append(g_cap("ReaperBoss", C + Vector((0, -0.03, 0)), (0, 1, 0), (1, 0, 0), 0.04, 0.04, 0.04, A["iron"],
                           head, sides=14))
        parts.append(g_cap("ReaperBossEye", C + Vector((0, 0.004, 0)), (0, 1, 0), (1, 0, 0), 0.022, 0.022, 0.014,
                           A["glow"], head, rings=4, sides=12))
        for s_i, sx in enumerate((-1, 1)):
            for k, r in enumerate((0.215, 0.29, 0.365)):
                d = r * 0.66
                be = math.radians(38 - 6 * k)
                bd = Vector((sx * math.cos(be), 0, math.sin(be)))
                parts.append(g_crescent("Scythe%d%d" % (s_i, k), C + Vector((0, 0.003 * k, 0)), -bd,
                                        Vector((-sx * math.sin(be), 0, math.cos(be))), 0.009, A["steel"], head, r=r,
                                        r_in=math.sqrt(r * r + d * d + r * d), d=d, n=22, blunt=0.05))
            bd = Vector((sx * math.cos(math.radians(32)), 0, math.sin(math.radians(32))))
            parts.append(g_cone("ScytheArm%d" % s_i, [C + bd * 0.15, C + bd * 0.36], 0.008, A["iron"], head, sides=6,
                                n=4, r1=0.006))
        return parts
    build_hood("h_reaper", HA, dict(tail=0.3, crest="none"), extra=extra)


# ------------------------------------------------------------------ 4. Senhor dos Corvos
def build_h_raven():
    """Chapéu de aba larga caída na frente, copa baixa amassada, crânio de corvo na faixa e leque de penas
    negras varrendo para trás."""
    P, R, head = g_head("h_raven")
    A = eg_mats("eg_raven", felt="#17161C", lining="#3A1F4A", feather="#1C1E2C", sheen="#2F4270", silver="#AEB4C2",
                bone="#DCD4BC", glow=("#D8B0FF", "#A060FF", 1.8))
    z0, cy, N, n = HEAD_CHIN + 0.2, 0.01, 32, 24
    path = g_spline([Vector(c) for c in ((0, cy, z0 - 0.012), (0, cy + 0.004, z0 + 0.05), (0.008, cy + 0.018, z0 + 0.11),
                                         (0.02, cy + 0.036, z0 + 0.15), (0.026, cy + 0.042, z0 + 0.16))], n)
    rx = [max(0.004, v) for v in g_spline([0.125, 0.119, 0.108, 0.075, 0.02], n)]
    ry = [max(0.004, v) for v in g_spline([0.137, 0.13, 0.116, 0.08, 0.02], n)]
    fold = lambda i, a: math.sin(math.pi * i / n) * 0.005 * math.sin(i / n * 20.0 + 2.0 * math.sin(a))
    crown = g_curved_tube(path, list(zip(rx, ry)), sides=N, wob=fold)
    parts = [g_smooth_mesh("RavenHat", crown, A["felt"], head)]

    def brim_pt(a, u, dz=0.0):
        r_x = 0.123 + (0.31 - 0.123) * u
        r_y = 0.135 + (0.33 - 0.135) * u
        ca = math.cos(a)
        z = (z0 + 0.004 - 0.03 * max(u, 0.0) ** 1.5
             + u ** 2 * (0.06 * math.sin(a) ** 2 - 0.04 * max(ca, 0.0) ** 2 + 0.03 * max(-ca, 0.0)))
        return Vector((math.sin(a) * r_x, cy - ca * r_y, z + dz))
    rows = 9
    top = [[brim_pt(2 * math.pi * j / N, i / rows) for j in range(N)] for i in range(rows + 1)]
    under = [[brim_pt(2 * math.pi * j / N, i / rows, -0.005 - 0.011 * (1 - (i / rows) ** 4)) for j in range(N)]
             for i in range(rows, -1, -1)]
    under.append([brim_pt(2 * math.pi * j / N, -0.3, -0.03) for j in range(N)])
    brim = g_smooth_mesh("RavenBrim", top + under, A["felt"], head, cap_end=False)
    brim.data.materials.append(A["lining"])
    if brim.data.polygons[0].normal.z < 0:
        brim.data.flip_normals()
    for pl in brim.data.polygons[(rows + 1) * N:]:
        pl.material_index = 1
    parts.append(brim)
    band = [[q + (q - path[i]).normalized() * 0.006 for q in crown[i]] for i in range(2, 6)]
    parts.append(g_smooth_mesh("RavenBand", band, A["sheen"], head, cap_end=False, thick=0.004))
    # crânio de corvo na frente da faixa: calota, bico comprido e olhos acesos
    front = min(band[1], key=lambda q: q.y)
    parts.append(g_cap("RavenSkull", front + Vector((0, 0.004, 0.012)), (0, -1, 0.3), (1, 0, 0), 0.03, 0.036, 0.034,
                       A["bone"], head, sides=16))
    parts.append(g_cone("RavenBeak", [front + Vector((0, -0.02, 0.016)), front + Vector((0, -0.075, 0.0)),
                                      front + Vector((0, -0.12, -0.034))], 0.017, A["bone"], head, sides=8))
    for k, sx in enumerate((-1, 1)):
        parts.append(g_cap("RavenEye%d" % k, front + Vector((sx * 0.017, -0.026, 0.02)), (sx * 0.6, -1, 0.2), (0, 0, 1),
                           0.008, 0.008, 0.006, A["glow"], head, rings=4, sides=10))
    # penas: leque grande à direita, três menores à esquerda
    for side, cnt, l0 in ((1, 7, 0.38), (-1, 3, 0.25)):
        b = Vector((side * 0.1, cy + 0.03, z0 + 0.04))
        for i in range(cnt):
            el = math.radians(6 + i * (11 if side > 0 else 15))
            d = Vector((side * 0.24, math.cos(el), math.sin(el)))
            parts.append(g_feather("RavenFeather%d_%d" % (side + 1, i), b + Vector((0, 0, 0.004 * i)), d,
                                   (side * 0.85, -0.45, 0.25), l0 - 0.024 * i, 0.036, A["sheen" if i % 2 else "feather"],
                                   head, curl=0.14))
        if side > 0:
            parts.append(g_cap("RavenPin", b + Vector((0.02, 0.004, 0.0)), (1, -0.25, 0), (0, 0, 1), 0.024, 0.024, 0.014,
                               A["silver"], head, sides=14))
            parts.append(g_cap("RavenPinGem", b + Vector((0.03, 0.002, 0.0)), (1, -0.25, 0), (0, 0, 1), 0.012, 0.012,
                               0.01, A["glow"], head, rings=4, sides=10))
    g_head_done("h_raven", "RavenHat", parts, P, R)


# ------------------------------------------------------------------ 5. Mago de Guerra Dracônico
def build_h_dragon():
    """Elmo aberto de escamas: casco com guarda-nuca, dois chifres grandes varrendo para trás, dois menores
    no queixo, crista de espinhas pelo alto e gema na testa."""
    P, R, head = g_head("h_dragon", hair=False)
    A = eg_mats("eg_dragon", scale="#6A1820", dark="#22161A", gold="#D09A3A", horn="#D8CCB0",
                glow=("#FFD0A0", "#FF7A2A", 1.8))
    hc = Vector((0, 0.016, 1.69))
    ax, ay, az, PB = 0.14, 0.158, 0.152, -0.3

    def open_half(ph):
        if ph > 0.62:
            return 0.0
        if ph > -0.1:
            return 0.82 * math.sqrt(max(0.0, 1 - ((ph + 0.1) / 0.72) ** 2))
        return 0.82 - 0.3 * min(1.0, (-0.1 - ph) / 0.35)

    def hp(th, ph, inset=0.0, bump=0.0):
        if ph >= PB:
            rr, z = math.cos(ph), hc.z + math.sin(ph) * (az - inset + bump)
        else:
            k = PB - ph
            rr, z = math.cos(PB) * (1 + 0.9 * k), hc.z + math.sin(PB) * az - 0.2 * k
        return Vector((math.sin(th) * rr * (ax - inset + bump), hc.y - math.cos(th) * rr * (ay - inset + bump), z))

    def scale_bump(th, ph, i):          # escamas: gomos desencontrados a cada fiada, só dos lados e atrás
        side = min(1.0, max(0.0, (min(th, 2 * math.pi - th) - 0.95) / 0.45))
        fade = 1.0 if ph < 0.95 else max(0.0, 1 - (ph - 0.95) / 0.4)
        return 0.0065 * abs(math.sin(9 * th + (i % 2) * math.pi / 2)) * side * fade
    na, rows = 72, 22
    rings, edge_l, edge_r, top_i = [], [], [], rows
    for i in range(rows + 1):
        ph = -0.75 + 2.25 * i / rows
        t0 = open_half(ph)
        angs = [t0 + (2 * math.pi - 2 * t0) * j / na for j in range(na + 1)]

        def lip(th, t0=t0):          # a borda da abertura avança: viseira e guarda das faces
            if t0 < 0.05:
                return Vector()
            return Vector((0, -0.022 * math.exp(-min(th - t0, 2 * math.pi - t0 - th) / 0.2), 0))
        rings.append([hp(a, ph, bump=scale_bump(a, ph, i)) + lip(a) for a in angs]
                     + [hp(a, ph, 0.011) + lip(a) for a in reversed(angs)])
        if t0 >= 0.05:
            edge_l.append(rings[-1][0])
            edge_r.append(rings[-1][na])
        else:
            top_i = min(top_i, i)
    helm = g_smooth_mesh("DragonHelm", rings, A["scale"], head)
    helm.data.materials.append(A["dark"])
    per = 2 * (na + 1)
    for pl in helm.data.polygons[:rows * per]:
        if na < pl.index % per < per - 1:
            pl.material_index = 1
    parts = [helm, g_pipe("HelmPiping", edge_l + [rings[top_i][0]] + edge_r[::-1], 0.009, A["gold"], head),
             g_pipe("HelmHem", rings[0][:na + 1], 0.007, A["gold"], head),
             g_cap("HelmPad", (0, hc.y, 1.79), (0, 0, 1), (1, 0, 0), 0.07, 0.08, 0.045, A["dark"], head, rings=4, sides=12)]
    c = rings[top_i][0] + Vector((0, -0.004, -0.014))
    nb = Vector((0, -1, 0.35)).normalized()
    parts.append(g_cap("HelmSeat", c, nb, (1, 0, 0), 0.03, 0.038, 0.014, A["gold"], head, sides=16))
    parts.append(g_cap("HelmGem", c + nb * 0.009, nb, (1, 0, 0), 0.017, 0.024, 0.014, A["glow"], head, rings=5, sides=14))
    for k, sx in enumerate((-1, 1)):
        b = hp(sx * 1.95, 0.5)
        o = (b - hc).normalized()
        ctrl = [b - o * 0.025, b + Vector((sx * 0.07, 0.03, 0.055)), b + Vector((sx * 0.14, 0.1, 0.115)),
                b + Vector((sx * 0.175, 0.21, 0.195)), b + Vector((sx * 0.15, 0.31, 0.32))]
        parts.append(g_cone("DragonHorn%d" % k, ctrl, 0.04, A["horn"], head, sides=14, n=18, ridge=0.004, pw=0.85))
        d0 = (ctrl[1] - b).normalized()
        u = d0.cross(Vector((0, 0, 1))).normalized()
        parts.append(g_smooth_mesh("HornRing%d" % k, g_curved_tube(
            [b - d0 * 0.004, b + d0 * 0.012, b + d0 * 0.026], [(0.047, 0.047), (0.05, 0.05), (0.045, 0.045)], sides=16,
            side0=tuple(u)), A["gold"], head, cap_end=False, thick=0.006))
        b2 = hp(sx * 2.15, -0.22)
        o2 = (b2 - hc).normalized()
        parts.append(g_cone("JawHorn%d" % k, [b2 - o2 * 0.016, b2 + Vector((sx * 0.035, 0.07, 0.005)),
                                              b2 + Vector((sx * 0.055, 0.165, 0.055))], 0.022, A["horn"], head, sides=10,
                            ridge=0.002))
    for i in range(7):                 # crista: espinhas chatas pelo meio, da testa à nuca
        be = 0.85 + (math.pi + 0.15 - 0.85) * i / 6
        th, ph = (0.0, be) if be <= math.pi / 2 else (math.pi, math.pi - be)
        b = hp(th, ph)
        o = (b - hc).normalized()
        ln = 0.06 + 0.07 * math.sin(math.pi * (i + 0.6) / 7.2)
        back = Vector((0, 1, 0.15))
        pth = g_spline([b - o * 0.014, b + o * ln * 0.55 + back * ln * 0.18, b + o * ln + back * ln * 0.6], 8)
        rad = [(0.009 * (1 - j / 8) + 0.0012, 0.03 * (1 - j / 8) ** 0.8 + 0.0015) for j in range(9)]
        parts.append(g_smooth_mesh("DragonFin%d" % i, g_curved_tube(pth, rad, sides=10, side0=(1, 0, 0)), A["horn"], head))
    g_head_done("h_dragon", "DragonHelm", parts, P, R)


# ------------------------------------------------------------------ 6. Astrônomo Celeste
def build_h_astral():
    """Diadema dourado com estrela alta na testa e asas nas têmporas; atrás da cabeça, uma esfera armilar:
    três aros cruzados com astro no centro, estrelas e planetas presos aos aros."""
    P, R, head = g_head("h_astral")
    A = eg_mats("eg_astral", gold="#E2C06A", silver="#D5DAE6", glow=("#CFEAFF", "#6FB8FF", 1.8))
    zf = lambda th: 1.757 + 0.01 * math.cos(th)
    parts = [g_pipe("Circlet", g_headring(zf, 0.005), 0.008, A["gold"], head, loop=True),
             g_pipe("Circlet2", g_headring(lambda th: zf(th) + 0.021, 0.006), 0.0045, A["gold"], head, loop=True)]
    tiara = [g_headring(lambda th, dz=dz: zf(th) + dz, 0.003, 48) for dz in (-0.006, 0.01, 0.026)]
    parts.append(g_smooth_mesh("CircletPlate", tiara, A["gold"], head, cap_end=False, thick=0.006))
    for i in range(10):
        th = math.pi / 10 + 2 * math.pi * i / 10
        parts.append(g_bead("CircletBead%d" % i, g_skull(th, zf(th) + 0.011, 0.007), 0.0085, A["glow"], head))
    f = g_skull(0, zf(0), 0.012)
    parts.append(g_plate("DiademStar", g_star4(0.06, 0.017), f + Vector((0, -0.004, 0.085)), (1, 0, 0), (0, 0, 1), 0.008,
                         A["gold"], head))
    parts.append(g_gem("DiademGem", f + Vector((0, -0.008, 0.016)), 0.015, 0.022, 0.008, A["glow"], head))
    for k, sx in enumerate((-1, 1)):
        th = sx * 0.6
        q = g_skull(th, zf(th), 0.012)
        parts.append(g_plate("DiademStar%d" % k, g_star4(0.034, 0.011), q + Vector((0, 0, 0.05)),
                             (math.cos(th), math.sin(th), 0), (0, 0, 1), 0.007, A["silver"], head))
        b = g_skull(sx * 1.3, zf(1.3) + 0.008, 0.002)
        for i, (el, ln) in enumerate(((22, 0.21), (40, 0.175), (58, 0.135))):
            d = Vector((sx * 0.32, math.cos(math.radians(el)), math.sin(math.radians(el))))
            parts.append(g_feather("DiademWing%d_%d" % (k, i), b, d, (sx * 0.9, -0.35, 0.2), ln, 0.03,
                                   A["gold" if i % 2 == 0 else "silver"], head, curl=0.1))
    # esfera armilar atrás da cabeça
    C = Vector((0, SKULL_C.y + 0.25, 1.8))
    rr = 0.19
    planes = (((1, 0, 0), (0, 0, 1), 0.0075, "gold"), ((0.77, 0.64, 0), (0, 0, 1), 0.0055, "silver"),
              ((1, 0, 0), (0, 0.5, 0.87), 0.0055, "gold"))
    for i, (u, v, r, m) in enumerate(planes):
        parts.append(g_pipe("Armil%d" % i, g_circle(C, u, v, rr, 44), r, A[m], head, loop=True))
    parts.append(g_cone("ArmilAxis", [C - Vector((0, 0, rr)), C + Vector((0, 0, rr))], 0.004, A["gold"], head, sides=6,
                        n=2, r1=0.004))
    parts.append(g_bead("ArmilOrb", C, 0.034, A["glow"], head))
    parts.append(g_cone("ArmilStem", [(0, SKULL_C.y + 0.135, 1.757), (0, SKULL_C.y + 0.2, 1.775), C], 0.008, A["gold"],
                        head, sides=8, r1=0.005))
    for i, (pl, a, kind) in enumerate(((0, 0.7, "star"), (0, 2.6, "star"), (0, 4.4, "star"), (1, 1.2, "orb"),
                                       (2, 3.5, "orb"), (2, 0.6, "star"))):
        u, v = Vector(planes[pl][0]).normalized(), Vector(planes[pl][1]).normalized()
        rd = u * math.cos(a) + v * math.sin(a)
        tn = -u * math.sin(a) + v * math.cos(a)
        if kind == "star":
            parts.append(g_plate("ArmilStar%d" % i, g_star4(0.026, 0.008), C + rd * rr, tn, rd, 0.007, A["gold"], head))
        else:
            parts.append(g_bead("ArmilPlanet%d" % i, C + rd * rr, 0.015, A["glow" if i % 2 else "silver"], head))
    g_head_done("h_astral", "Diadem", parts, P, R)


# ------------------------------------------------------------------ 7. Soberano do Gelo
def build_h_frost():
    """Coroa de gelo: aro de prata com cristais facetados altos na frente e mais baixos atrás, cristais menores
    entre eles, gema azul na testa e pingentes de gelo nas têmporas."""
    P, R, head = g_head("h_frost")
    A = eg_mats("eg_frost", silver="#C9D2E0", ice=("#8FD0F2", "#5FB8F0", 0.35), deep=("#9FC4FF", "#3F7BE0", 1.5))
    zf = lambda th: 1.757 + 0.01 * math.cos(th)
    band = [g_headring(lambda th, dz=dz: zf(th) + dz, out, 48) for dz, out in ((-0.016, 0.004), (0.0, 0.009),
                                                                               (0.016, 0.004))]
    parts = [g_smooth_mesh("FrostBand", band, A["silver"], head, cap_end=False, thick=0.006)]
    for i, dz in enumerate((-0.016, 0.016)):
        parts.append(g_pipe("FrostRim%d" % i, g_headring(lambda th, dz=dz: zf(th) + dz, 0.006, 48), 0.0045, A["silver"],
                            head, loop=True))
    up = Vector((0, 0, 1))
    K = 11
    for k in range(K):
        for big in (True, False):
            th = 2 * math.pi * (k + (0.0 if big else 0.5)) / K
            fr = ((1 + math.cos(th)) / 2) ** 1.4
            ln = (0.085 + 0.14 * fr) * (1.0 if big else 0.52)
            b = g_skull(th, zf(th) + 0.004, 0.004)
            od = Vector((math.sin(th), -math.cos(th), 0))
            tip = b + up * ln + od * ln * (0.26 if big else 0.5)
            parts.append(g_shard("Ice%d%s" % (k, "a" if big else "b"), b - up * 0.012, tip,
                                 (0.02 + 0.008 * fr) if big else 0.014, A["ice"], head, twist=k * 0.7))
    for k, sx in enumerate((-1, 1)):
        for j, (th, ln) in enumerate(((1.25, 0.085), (1.55, 0.06))):
            b = g_skull(sx * th, zf(th) - 0.006, 0.008)
            od = Vector((math.sin(sx * th), -math.cos(sx * th), 0))
            parts.append(g_shard("IceDrop%d%d" % (k, j), b + up * 0.012, b - up * ln + od * 0.012, 0.012, A["ice"], head))
    parts.append(g_gem("FrostGem", g_skull(0, zf(0), 0.014), 0.017, 0.024, 0.009, A["deep"], head))
    g_head_done("h_frost", "FrostCrown", parts, P, R)


# ================================================================== MÃOS
def build_g_bare():
    P, R = g_rig("g_bare")
    M = g_mats()
    for n, s in (("L", 1), ("R", -1)):
        soft_fist("Arm" + n, P, s, M["skin"], R["Elbow" + n])
    g_export("g_bare", P, R)


def build_g_gloves():
    """Luvas de couro com punho largo virado. t1 = luva, t2 = punho."""
    P, R = g_rig("g_gloves")
    gl = gm("t1_gloves", "#6B4423", 0.8)
    gl2 = gm("t2_gloves", "#3A2412", 0.85)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        h = soft_fist("Arm" + n, P, s, gl, elbow)
        F = S["fore"]
        fd = F[-1]["c"] - F[0]["c"]
        c0 = grow([sample(F, 0.72)], 1.22, 0.014)[0]
        cuff = loft("Arm%s_GloveCuff" % n, [c0, grow([sample(F, 1.0)], 1.06, 0.006)[0]], gl2, elbow, sides=8,
                    chamfer=(0.006, 0.0))
        rim = band("Arm%s_CuffRim" % n, c0, fd, 0.014, gl, elbow, sides=8, out=0.003)
        relaxed_hand("Arm" + n, P, s, gl, elbow)       # mão aberta (vazia): o jogo fica com uma das duas
        join_objs("Arm%s_GloveCuff" % n, [cuff, rim])
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
        h = soft_fist("Arm" + n, P, s, br2, elbow)
        relaxed_hand("Arm" + n, P, s, br2, elbow)      # mão aberta (vazia): o jogo fica com uma das duas
        parts = [loft("Arm%s_Bracer" % n, grow(span(F, 0.25, 0.95), 1.18, 0.01), br, elbow, chamfer=(0.006, 0.006))]
        fdown = (F[-1]["c"] - F[0]["c"]).normalized()
        for k, t in enumerate((0.42, 0.72)):
            parts.append(band("Arm%s_BracerStrap%d" % (n, k), grow([sample(F, t)], 1.18, 0.012)[0], fdown, 0.018, br2,
                              elbow, sides=8, out=0.004))
        join_objs("Arm%s_Bracer" % n, parts)
    g_export("g_bracers", P, R)


def build_g_ranger():
    """Luvas do patrulheiro: direita de couro castanho (continua a braçadeira da armadura); esquerda de couro
    escuro com pano azul enrolado no pulso e na palma e uma tira avermelhada cruzada por cima. Punho curto com
    friso, que entra sob a braçadeira."""
    from mathutils import Matrix
    P, R = g_rig("g_ranger")
    K = ranger_mats()
    tan, dark = gm("rg_glove", "#6E4A34", 0.8), gm("rg_glove_d", "#3A3230", 0.8)
    blue, red = gm("rg_wrap", "#46526A", 0.95), gm("rg_wrap_r", "#6A3A34", 0.9)
    N = 24
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        hd, o, ay, up, pt = _hand_frame(P, s)
        mat = dark if s > 0 else tan
        fist = soft_fist("Arm" + n, P, s, mat, elbow)
        hand = relaxed_hand("Arm" + n, P, s, mat, elbow)
        fp, op = [fist], [hand]
        cuff = [_rg_ring(sample(F, t), 1.08, add, n=N) for t, add in ((0.8, 0.006), (0.9, 0.008), (1.0, 0.009))]
        cp = [g_smooth_mesh("Arm%s_GloveCuff" % n, cuff, mat, elbow, cap_end=False, thick=0.003, outward=True),
              g_pipe("Arm%s_GloveCuffRim" % n, _rg_ring(sample(F, 0.95), 1.08, 0.012, n=N), 0.0035,
                     K["lea_d"] if s < 0 else red, elbow, sides=6, loop=True)]
        if s > 0:
            # pano azul no pulso: voltas levemente tortas, borda esfiapada
            for k, (t0, t1, tw) in enumerate(((0.8, 0.88, 0.01), (0.87, 0.95, -0.012), (0.93, 1.0, 0.008))):
                rows = [_rg_ring(sample(F, t0 + (t1 - t0) * v), 1.08, 0.012 + 0.004 * math.sin(math.pi * v), n=N,
                                 dz=lambda a, tw=tw: tw * math.sin(a)) for v in (0.0, 0.5, 1.0)]
                cp.append(g_smooth_mesh("Arm%s_Wrap%d" % (n, k), rows, blue, elbow, cap_end=False, thick=0.003,
                                        outward=True))
            # tira vermelha cruzada em X sobre as voltas
            for k, ph in enumerate((0.0, math.pi)):
                pts = [_rg_ring(sample(F, 0.82 + 0.16 * v), 1.08, 0.018, n=N)[int((ph / (2 * math.pi) * N + v * N * 0.6))
                                                                                % N] for v in [i / 10 for i in range(11)]]
                cp.append(g_pipe("Arm%s_WrapStrap%d" % (n, k), pts, 0.0045, red, elbow, sides=6))
            # volta de pano na palma da mão (fechada e aberta)
            bpy.context.view_layer.update()
            W = pt(0, 0, 0)
            for lst, ob, nm in ((fp, fist, "Fist"), (op, hand, "Open")):
                rows = []                # volta medida na própria malha da mão: faixa logo abaixo do pulso
                for z, add in ((-0.026, 0.0), (-0.04, 0.003), (-0.054, 0.0)):
                    zz = W.z + z * hd
                    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
                    vs = [v for v in vs if abs(v.z - zz) < 0.006]
                    x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
                    y0, y1 = min(v.y for v in vs), max(v.y for v in vs)
                    c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, zz))
                    rows.append([c + Vector((math.cos(2 * math.pi * j / N) * ((x1 - x0) / 2 + 0.004 + add),
                                             math.sin(2 * math.pi * j / N) * ((y1 - y0) / 2 + 0.004 + add), 0))
                                 for j in range(N)])
                lst.append(g_smooth_mesh("Arm%s_PalmWrap%s" % (n, nm), rows, blue, elbow, cap_end=False, thick=0.003,
                                         outward=True))
        join_objs("Arm%s_Hand" % n, fp)
        join_objs("Arm%s_HandOpen" % n, op)
        join_objs("Arm%s_Gauntlet" % n, cp)
    g_export("g_ranger", P, R)


def build_g_mithril():
    """Manoplas de mithril: mão de placa (fechada e aberta, o jogo usa uma das duas) com friso dos nós dos dedos
    e três folhas incrustadas nas costas da mão (medidas por raios na própria malha da mão); punho curto de placa
    abrindo para o cotovelo, com borda dobrada, que entra sob o braçal da armadura."""
    from mathutils.bvhtree import BVHTree
    P, R = g_rig("g_mithril")
    K = mithril_mats()
    N = 24
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        hd, o, ay, up, pt = _hand_frame(P, s)
        fist = soft_fist("Arm" + n, P, s, K["plate"], elbow)
        hand = relaxed_hand("Arm" + n, P, s, K["plate"], elbow)
        fp, op = [fist], [hand]
        bpy.context.view_layer.update()
        for lst, ob, nm in ((fp, fist, "Fist"), (op, hand, "Open")):
            vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
            bvh = BVHTree.FromPolygons(vs, [tuple(p.vertices) for p in ob.data.polygons])

            def back(y, z):            # ponto das costas da mão: raio de fora (+o) para dentro
                c = pt(0, y, z)
                h = bvh.ray_cast(c + o * 0.2, -o)
                return h[0], h[1]
            # friso dos nós dos dedos: linha atravessada nas costas da mão, perto dos dedos
            zs = [v.z for v in vs]
            zk = (max(zs) - min(zs))
            W = pt(0, 0, 0)
            line = []
            for j in range(11):
                y = -0.035 + 0.07 * j / 10
                q, nr = back(y / hd, -(0.5 * zk) / hd)
                if q is not None:
                    line.append(q + o * 0.0025)
            if len(line) > 3:
                lst.append(g_pipe("Arm%s_Knuckles%s" % (n, nm), line, 0.0035, K["plate_d"], elbow, sides=6))
            # folhas nas costas da mão: uma no meio para os dedos e duas abrindo para os lados
            q0, nr0 = back(0.0, -(0.18 * zk) / hd)
            if q0 is None:
                continue
            down = (-up - nr0 * (-up).dot(nr0)).normalized()
            side = nr0.cross(down).normalized()
            for k, (ang, L, W_, dx, dz) in enumerate(((0, 0.042, 0.0072, 0.0, 0.004), (38, 0.03, 0.0055, 0.011, -0.002),
                                                      (-38, 0.03, 0.0055, -0.011, -0.002))):
                t = math.radians(ang)
                d = (down * math.cos(t) + side * math.sin(t)).normalized()
                sd = side if ang >= 0 else -side
                lst += mt_leaf_at("Arm%s_HandLeaf%s%d" % (n, nm, k), bvh, q0 + nr0 * 0.01 + side * dx + down * dz, d, sd,
                                  L, W_, K, elbow, curl=0.1)
        # punho curto de placa: abre para o cotovelo, borda dobrada em cima e friso no pulso
        cuff = [_rg_ring(sample(F, t), 1.08, add, n=N) for t, add in ((0.84, 0.008), (0.92, 0.007), (1.0, 0.007))]
        cp = [g_smooth_mesh("Arm%s_Cuff" % n, cuff, K["plate"], elbow, cap_end=False, thick=0.004, outward=True),
              g_pipe("Arm%s_CuffRim" % n, cuff[-1], 0.0035, K["plate"], elbow, sides=8, loop=True)]
        join_objs("Arm%s_Hand" % n, fp)
        join_objs("Arm%s_HandOpen" % n, op)
        join_objs("Arm%s_Gauntlet" % n, cp)
    g_export("g_mithril", P, R)


def build_g_celestial():
    """Manoplas Astrais (cavaleiro celeste): mão de placa dourada (fechada e aberta) com friso dos nós dos dedos e
    duas lâminas atravessadas nas costas da mão (medidas por raios na própria malha); punho de placa que abre em
    sino para o cotovelo, com a borda subindo numa ponta do lado de fora e friso no pulso."""
    from mathutils.bvhtree import BVHTree
    P, R = g_rig("g_celestial")
    K = celestial_mats()
    N = 24
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        hd, o, ay, up, pt = _hand_frame(P, s)
        fist = soft_fist("Arm" + n, P, s, K["plate"], elbow)
        hand = relaxed_hand("Arm" + n, P, s, K["plate"], elbow)
        fp, op = [fist], [hand]
        bpy.context.view_layer.update()
        for lst, ob, nm in ((fp, fist, "Fist"), (op, hand, "Open")):
            vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
            bvh = BVHTree.FromPolygons(vs, [tuple(p.vertices) for p in ob.data.polygons])
            zs = [v.z for v in vs]
            zk = (max(zs) - min(zs))
            for k, (fz, r) in enumerate(((0.5, 0.0035), (0.12, 0.0022), (-0.12, 0.0022))):
                line = []
                for j in range(11):
                    y = -0.035 + 0.07 * j / 10
                    c = pt(0, y / hd, -(fz * zk) / hd)
                    h = bvh.ray_cast(c + o * 0.2, -o)
                    if h[0] is not None:
                        line.append(h[0] + o * (0.0025 if k == 0 else 0.0015))
                if len(line) > 3:
                    lst.append(g_pipe("Arm%s_Lame%s%d" % (n, nm, k), line, r, K["plate_d"], elbow, sides=6))
        # punho: abre em sino para o cotovelo; a borda de cima sobe numa ponta do lado de fora
        def peak(a):
            d = math.atan2(math.sin(a - s * math.pi / 2), math.cos(a - s * math.pi / 2))
            return max(0.0, math.cos(d)) ** 6
        cuff = [_rg_ring(sample(F, t), 1.08, add, n=N, dz=(lambda a, w=w: w * peak(a)))
                for t, add, w in ((0.76, 0.014, 0.045), (0.82, 0.011, 0.022), (0.9, 0.008, 0.0), (1.0, 0.007, 0.0))]
        cp = [g_smooth_mesh("Arm%s_Cuff" % n, cuff, K["plate"], elbow, cap_end=False, thick=0.004, outward=True),
              g_pipe("Arm%s_CuffRim" % n, cuff[0], 0.0035, K["plate"], elbow, sides=8, loop=True),
              g_pipe("Arm%s_CuffWrist" % n, cuff[-1], 0.003, K["plate_d"], elbow, sides=6, loop=True)]
        join_objs("Arm%s_Hand" % n, fp)
        join_objs("Arm%s_HandOpen" % n, op)
        join_objs("Arm%s_Gauntlet" % n, cp)
    g_export("g_celestial", P, R)


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


def _rg_ring(sc, k=1.0, add=0.0, n=32, bump=None, dz=None):
    """Anel liso em volta de uma seção de membro (sample/span): elipse com a frente e as costas da seção,
    bump(a) soma ao raio e dz(a) sobe/desce o ponto (a = 0 na frente, cresce para +x)."""
    c = sc["c"]
    out = []
    for j in range(n):
        a = 2 * math.pi * j / n
        f = sc.get("fr", 1.0) if math.cos(a) > 0 else sc.get("bk", 1.0)
        rx = sc["rx"] * k + add + (bump(a) if bump else 0.0)
        ry = (sc["ry"] * f) * k + add + (bump(a) if bump else 0.0)
        out.append(c + Vector((math.sin(a) * rx, -math.cos(a) * ry, dz(a) if dz else 0.0)))
    return out


def build_f_ranger():
    """Botas do patrulheiro: cano de couro escuro do joelho ao tornozelo, cingido por cinco tiras sobrepostas
    (borda de cima mais clara), dobra larga no topo que sobe em ponta atrás e por fora; joelho e canela repostos
    com a calça (tp_, a cor da calça da armadura); sapato de bico fino com lingueta sobre o peito do pé e tira
    no tornozelo com fivela por fora."""
    P, R = g_rig("f_ranger")
    M = g_mats()
    K = ranger_mats()
    boot, boot_l = gm("rg_boot", "#3A2A24", 0.85), gm("rg_boot_l", "#5C4436", 0.85)
    shoe, sole = gm("rg_shoe", "#46302A", 0.8), gm("rg_sole", "#24180F", 0.9)
    N = 32
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        sh, th = S["shin"], S["thigh"]
        knee = R["Knee" + n]
        # ---- joelho e alto da canela: calça (o espaço dos pés esconde o joelho do corpo)
        kn = grow(span(th, 0.86, 1.0), 1.05, 0.006) + grow(span(sh, 0.0, 0.2), 1.05, 0.006)[1:]
        parts = [g_smooth_mesh("Leg%s_Knee" % n, [_rg_ring(x, n=N) for x in kn], M["pants"], knee, cap_end=False)]
        # ---- cano
        cano = [sample(sh, 0.12 + 0.86 * i / 14) for i in range(15)]
        parts.append(g_smooth_mesh("Leg%s_Shaft" % n, [_rg_ring(x, 1.04, 0.009, n=N) for x in cano], boot, knee,
                                   cap_end=False))
        # ---- tiras sobrepostas, um pouco inclinadas, cada uma com a borda de cima clara
        # faixas largas empilhadas: cada uma sai em degrau por cima da de baixo (borda de cima grossa e clara,
        # afinando para baixo, onde entra sob a seguinte)
        for k, t in enumerate((0.4, 0.53, 0.66, 0.79)):
            def dz(a):
                return 0.01 * math.sin(a) * s
            rows = [_rg_ring(sample(sh, t + dt), 1.04, 0.009 + ad, n=N, dz=dz)
                    for dt, ad in ((-0.05, 0.003), (-0.046, 0.012), (-0.035, 0.014), (0.0, 0.011), (0.035, 0.007),
                                   (0.05, 0.002))]
            parts.append(g_smooth_mesh("Leg%s_Wrap%d" % (n, k), rows, boot, knee, cap_end=False))
            parts.append(g_pipe("Leg%s_WrapEdge%d" % (n, k), rows[1], 0.0026, boot_l, knee, sides=6, loop=True))
        # ---- dobra do topo: larga, sobe em ponta atrás e por fora
        aout = s * (math.pi - 0.75)

        def peak(a, aout=aout):
            d = math.atan2(math.sin(a - aout), math.cos(a - aout))
            return max(0.0, math.cos(d)) ** 5

        cuff = [_rg_ring(sample(sh, 0.04), 1.3, 0.016, n=N, bump=lambda a: 0.012 * peak(a), dz=lambda a: 0.05 * peak(a)),
                _rg_ring(sample(sh, 0.1), 1.26, 0.016, n=N, bump=lambda a: 0.008 * peak(a), dz=lambda a: 0.03 * peak(a)),
                _rg_ring(sample(sh, 0.19), 1.18, 0.015, n=N),
                _rg_ring(sample(sh, 0.25), 1.04, 0.009, n=N)]
        parts.append(g_smooth_mesh("Leg%s_Cuff" % n, cuff, boot, knee, cap_end=False, thick=0.004, outward=True))
        parts.append(g_pipe("Leg%s_CuffRim" % n, cuff[0], 0.004, boot_l, knee, sides=6, loop=True))
        parts.append(g_pipe("Leg%s_CuffHem" % n, cuff[2], 0.0035, boot_l, knee, sides=6, loop=True))
        # ---- tira do tornozelo com fivela por fora
        an = _rg_ring(sample(sh, 0.94), 1.18, 0.014, n=N)
        parts.append(g_pipe("Leg%s_AnkleStrap" % n, an, 0.0055, K["lea_d"], knee, sides=8, loop=True))
        q = an[N // 4] if s > 0 else an[3 * N // 4]
        parts += rg_buckle("Leg%s_AnkleBuckle" % n, q, Vector((0, -1, 0)), Vector((0, 0, 1)), Vector((s, 0, 0)),
                           0.011, 0.009, K["metal"], knee, r=0.0024)
        join_objs("Leg%s_Boot" % n, parts)
        # ---- sapato: bico fino, salto baixo, lingueta sobre o peito do pé
        ankle = R["Ankle" + n]
        f = P["ft"]
        ft = _foot_secs(P, s, 1.04, 0.004)
        tip = ft[-1]                     # bico fino: a última seção avança e afina
        ft[-1] = dict(tip, c=tip["c"] + Vector((0, -0.016 * f, -0.002 * f)), rx=tip["rx"] * 0.5, ry=tip["ry"] * 0.6)
        zmin = 0.02 * f                  # o cabedal assenta na sola (lisa, não facetada)

        def fring(sc, k=1.0):
            return [sc["c"] + Vector((math.sin(a) * sc["rx"] * k, 0, 0)) +
                    Vector((0, 0, max(zmin - sc["c"].z, math.cos(a) * sc["ry"] * k * 0.86)))
                    for a in (2 * math.pi * j / N for j in range(N))]
        h0 = ft[0]
        hc = dict(h0, c=h0["c"] + Vector((0, 0.014 * f, 0.006)))
        rings = [fring(hc, 0.02), fring(dict(h0, c=h0["c"] + Vector((0, 0.011 * f, 0.004))), 0.5), fring(h0, 0.9)]
        rings += [fring(x) for x in ft]
        rings.append(fring(dict(ft[-1], c=ft[-1]["c"] + Vector((0, -0.012 * f, -0.002))), 0.4))
        foot = [g_smooth_mesh("Leg%s_Foot" % n, rings, shoe, ankle),
                foot_sole("Leg%s_Sole" % n, ft, sole, ankle, f, heel=0.012 * f)]
        b = ft[1]                        # tira sobre o peito do pé
        arc = [b["c"] + Vector((math.sin(t) * (b["rx"] + 0.003), 0, max(zmin - b["c"].z + 0.004, math.cos(t) * (b["ry"] + 0.003))))
               for t in (-1.9 + 3.8 * m / 14 for m in range(15))]
        foot.append(g_pipe("Leg%s_Instep" % n, arc, 0.0045, K["lea_d"], ankle, sides=8))
        join_objs("Leg%s_BootFoot" % n, foot)
    g_loose_world("f_ranger")
    g_export("f_ranger", P, R)


def build_f_mithril():
    """Grevas de mithril (placa élfica): malha escura fechando a volta do joelho, joelheira em cúpula com leque de
    folhas, placa em V sob o joelho com uma folha grande em escudo, greva lisa com quilha, dois frisos e duas
    folhas longas descendo pela frente, duas fivelas do lado de fora da panturrilha e a barra descendo sobre o
    pé atrás; sapato de placa de bico longo e fino com quatro lâminas e três folhas no bico."""
    P, R = g_rig("f_mithril")
    K = mithril_mats()
    sole = gm("mt_sole", "#2A221C", 0.9)
    N = 32
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        sh, th = S["shin"], S["thigh"]
        knee, ankle = R["Knee" + n], R["Ankle" + n]
        KJ = mirror(P["knee"], s)
        parts = []
        # ---- malha escura fechando o joelho (o espaço dos pés esconde o joelho do corpo)
        kn = grow(span(th, 0.86, 1.0), 1.05, 0.006) + grow(span(sh, 0.0, 0.24), 1.05, 0.006)[1:]
        parts.append(g_smooth_mesh("Leg%s_KneeMail" % n, [_rg_ring(x, n=N) for x in kn], K["joint"], knee,
                                   cap_end=False))

        def gp(t, a, add):             # ponto da greva: seção da canela + folga, quilha suave na frente
            q = sample(sh, t)
            rx, ry = q["rx"] * 1.06 + add, q["ry"] * 1.06 + add
            x, y = cb_spt(a, rx, ry, q.get("fr", 1.0), q.get("bk", 1.0), keel=0.06)
            return Vector((q["c"].x + x, q["c"].y + y, q["c"].z))
        # ---- greva: da joelheira ao pé; atrás a barra desce sobre o calcanhar
        ts = [0.13 + 0.85 * i / 14 for i in range(15)]
        rings = []
        for i, t in enumerate(ts):
            fl = 0.012 * max(0.0, (t - 0.85) / 0.13) ** 1.5
            row = []
            for j in range(N):
                a = 2 * math.pi * j / N
                p = gp(t, a, 0.012 + fl)
                row.append(p)
            rings.append(row)
        greave = g_smooth_mesh("Leg%s_Greave" % n, rings, K["plate"], knee, cap_end=False, thick=0.005, outward=True)
        parts.append(greave)
        for nm, rr in (("Top", rings[0]), ("Bot", rings[-1])):
            parts.append(g_pipe("Leg%s_GreaveRim%s" % (n, nm), rr, 0.005, K["plate"], knee, sides=8, loop=True))
        parts.append(g_pipe("Leg%s_GreaveKeel" % n, [gp(t, 0.0, 0.0135) for t in (0.4, 0.55, 0.7, 0.85, 0.96)], 0.0026,
                            K["plate_d"], knee, sides=6))
        for sg in (1, -1):
            parts.append(g_pipe("Leg%s_GreaveFlute%d" % (n, sg > 0), [gp(t, sg * 0.75, 0.0135) for t in (0.3, 0.5, 0.7, 0.9)],
                                0.002, K["plate_d"], knee, sides=6))
        # fivelas do lado de fora da panturrilha
        for k, t in enumerate((0.42, 0.58)):
            a = s * 2.1
            q = gp(t, a, 0.016)
            nr = (q - sample(sh, t)["c"]).normalized()
            parts.append(rg_band("Leg%s_CalfStrap%d" % (n, k), [gp(t, s * (1.8 + 0.08 * m), 0.0135) for m in range(9)],
                                 [nr] * 9, 0.006, 0.004, K["lea"], knee))
            parts += rg_buckle("Leg%s_CalfBuckle%d" % (n, k), q, Vector((0, 0, 1)), nr.cross(Vector((0, 0, 1))), nr,
                               0.007, 0.008, K["plate_d"], knee, r=0.002)
        # ---- placa em V sob o joelho, por cima da greva, ponta para baixo no meio da frente
        AV = 1.0

        def vplate(u, v):
            a = -AV + 2 * AV * v
            tb = 0.17 + 0.22 * (1 - abs(a) / AV) ** 1.2
            return gp(0.13 + (tb - 0.13) * u, a, 0.019)
        vp, vr = _wk_plate("Leg%s_KneeV" % n, vplate, 6, 24, K["plate"], knee, thick=0.005)
        parts.append(vp)
        parts.append(g_pipe("Leg%s_KneeVRim" % n, vr[-1], 0.0045, K["plate"], knee, sides=8))
        # ---- joelheira: cúpula na frente do joelho
        kc = Vector((KJ.x, KJ.y - 0.01, KJ.z - 0.004))
        fwd = Vector((0, -1, 0.12)).normalized()
        u_ = Vector((1, 0, 0))
        v_ = fwd.cross(u_).normalized()
        RAD = 0.078
        cap = []
        for i in range(1, 9):
            al = 1.55 * i / 8
            cap.append([kc + (fwd * math.cos(al) + (u_ * math.cos(2 * math.pi * j / N) * 1.05 +
                                                     v_ * math.sin(2 * math.pi * j / N)) * math.sin(al)) * RAD
                        for j in range(N)])
        tip = kc + fwd * RAD
        poleyn = g_smooth_mesh("Leg%s_Poleyn" % n, [[tip] * N] + cap, K["plate"], knee, cap_end=False, thick=0.005,
                               outward=True)
        parts.append(poleyn)
        parts.append(g_pipe("Leg%s_PoleynRim" % n, cap[-1], 0.0055, K["plate"], knee, sides=8, loop=True))
        # asa lisa do lado de fora
        wc = kc + u_ * (s * 0.066) + Vector((0, 0.006, -0.004))
        leafo = [(math.sin(2 * math.pi * j / 20) * 0.028 * (1 - 0.3 * max(0.0, -math.cos(2 * math.pi * j / 20))),
                  math.cos(2 * math.pi * j / 20) * 0.044 - 0.006) for j in range(20)]
        parts.append(g_plate("Leg%s_PoleynWing" % n, leafo, wc, (0, 1, 0), (0, 0, 1), 0.006, K["plate"], knee))
        parts.append(g_pipe("Leg%s_PoleynWingRim" % n, [wc + Vector((s * 0.004, x, y)) for x, y in leafo], 0.003,
                            K["plate_d"], knee, sides=6, loop=True))
        # ---- folhas: leque na joelheira, escudo na placa em V, duas longas na greva
        bp = _mt_bvh([poleyn])
        root = kc + (fwd * math.cos(0.7) - v_ * math.sin(0.7)) * (RAD + 0.03)   # por fora: pega a face de fora
        root = bp.find_nearest(root)[0]
        UP = Vector((0, 0, 1))
        RT = Vector((1, 0, 0))
        for q, (deg, L, W) in enumerate(((0, 0.05, 0.008), (24, 0.046, 0.0075), (-24, 0.046, 0.0075),
                                         (50, 0.04, 0.0065), (-50, 0.04, 0.0065))):
            t = math.radians(deg)
            d = (UP * math.cos(t) + RT * math.sin(t)).normalized()
            parts += mt_leaf_at("Leg%s_KneeLeaf%d" % (n, q), bp, root + d * 0.006 + (root - kc).normalized() * 0.01, d, RT * (1 if deg >= 0 else -1),
                                L, W, K, knee, curl=0.1)
        bvv = _mt_bvh([vp])
        top = bvv.find_nearest(vplate(0.1, 0.5) + Vector((0, -0.02, 0)))[0]
        parts += mt_leaf_at("Leg%s_ShieldLeaf" % n, bvv, top + Vector((0, -0.004, 0)), -UP, RT, 0.075, 0.022, K, knee, curl=0.0)
        bg = _mt_bvh([greave])
        for sg in (1, -1):
            p0 = bg.find_nearest(gp(0.43, sg * 0.28, 0.03))[0]
            d = (gp(0.75, sg * 0.4, 0.012) - p0).normalized()
            parts += mt_leaf_at("Leg%s_ShinLeaf%d" % (n, sg > 0), bg, p0, d, RT * sg, 0.1, 0.0095, K, knee, curl=0.08)
        join_objs("Leg%s_Boot" % n, parts)
        # ---- sapato de placa: bico longo e fino, quatro lâminas, três folhas no bico
        f = P["ft"]
        ft = _foot_secs(P, s, 1.06, 0.006)
        tipf = ft[-1]
        ft[-1] = dict(tipf, c=tipf["c"] + Vector((0, -0.03 * f, -0.002 * f)), rx=tipf["rx"] * 0.42, ry=tipf["ry"] * 0.5)
        zmin = 0.02 * f

        def fring(sc, k=1.0):
            return [sc["c"] + Vector((math.sin(a) * sc["rx"] * k, 0, 0)) +
                    Vector((0, 0, max(zmin - sc["c"].z, math.cos(a) * sc["ry"] * k * 0.86)))
                    for a in (2 * math.pi * j / N for j in range(N))]
        h0 = ft[0]
        hc = dict(h0, c=h0["c"] + Vector((0, 0.014 * f, 0.006)))
        frs = [fring(hc, 0.02), fring(dict(h0, c=h0["c"] + Vector((0, 0.011 * f, 0.004))), 0.5), fring(h0, 0.9)]
        frs += [fring(x) for x in ft]
        frs.append(fring(dict(ft[-1], c=ft[-1]["c"] + Vector((0, -0.02 * f, -0.001))), 0.25))
        shoe = g_smooth_mesh("Leg%s_Foot" % n, frs, K["plate"], ankle)
        foot = [shoe, foot_sole("Leg%s_Sole" % n, ft, sole, ankle, f, heel=0.01 * f)]
        for k, i in enumerate((1, 2, 3, 4)):
            if i >= len(ft) - 1:
                break
            b = ft[i]
            arc = [b["c"] + Vector((math.sin(t) * (b["rx"] * 1.0 + 0.003), 0,
                                    max(zmin - b["c"].z + 0.004, math.cos(t) * (b["ry"] * 0.86 + 0.003))))
                   for t in (-1.7 + 3.4 * m / 14 for m in range(15))]
            foot.append(g_pipe("Leg%s_SabatonLame%d" % (n, k), arc, 0.0032, K["plate_d"], ankle, sides=6))
        bs = _mt_bvh([shoe])
        tc = ft[-2]["c"] + Vector((0, 0.004, tipf["ry"] * 0.8))
        tc = bs.find_nearest(tc + Vector((0, 0, 0.02)))[0]
        FW = Vector((0, -1, 0))
        for q, (deg, L, W) in enumerate(((0, 0.04, 0.0075), (35, 0.032, 0.006), (-35, 0.032, 0.006))):
            t = math.radians(deg)
            d = (FW * math.cos(t) + RT * math.sin(t)).normalized()
            foot += mt_leaf_at("Leg%s_ToeLeaf%d" % (n, q), bs, tc, d, RT * (1 if deg >= 0 else -1), L, W, K, ankle,
                               curl=0.08)
        join_objs("Leg%s_BootFoot" % n, foot)
    g_loose_world("f_mithril")
    g_export("f_mithril", P, R)


def build_f_celestial():
    """Grevas Astrais (cavaleiro celeste): bronze escuro fechando a volta do joelho, joelheira em cúpula com a
    aleta em ponta do lado de fora (como a do cotovelo), placa em V sob o joelho, greva lisa com quilha e dois
    frisos, abrindo em sino sobre o tornozelo com um anel de lâmina; sapato de placa de bico longo, fino e
    pontudo, com quatro lâminas e nervura no peito do pé."""
    P, R = g_rig("f_celestial")
    K = celestial_mats()
    sole = gm("cs_sole", "#2A1E12", 0.9)
    N = 32
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        sh, th = S["shin"], S["thigh"]
        knee, ankle = R["Knee" + n], R["Ankle" + n]
        KJ = mirror(P["knee"], s)
        parts = []
        kn = grow(span(th, 0.86, 1.0), 1.05, 0.006) + grow(span(sh, 0.0, 0.24), 1.05, 0.006)[1:]
        parts.append(g_smooth_mesh("Leg%s_KneeJoint" % n, [_rg_ring(x, n=N) for x in kn], K["joint"], knee,
                                   cap_end=False))

        def gp(t, a, add):
            q = sample(sh, t)
            rx, ry = q["rx"] * 1.06 + add, q["ry"] * 1.06 + add
            x, y = cb_spt(a, rx, ry, q.get("fr", 1.0), q.get("bk", 1.0), keel=0.06)
            return Vector((q["c"].x + x, q["c"].y + y, q["c"].z))
        # ---- greva: abre em sino no tornozelo
        ts = [0.13 + 0.86 * i / 15 for i in range(16)]
        rings = []
        for t in ts:
            fl = 0.02 * max(0.0, (t - 0.8) / 0.19) ** 1.6
            rings.append([gp(t, 2 * math.pi * j / N, 0.012 + fl) for j in range(N)])
        parts.append(g_smooth_mesh("Leg%s_Greave" % n, rings, K["plate"], knee, cap_end=False, thick=0.005, outward=True))
        for nm, rr in (("Top", rings[0]), ("Bot", rings[-1])):
            parts.append(g_pipe("Leg%s_GreaveRim%s" % (n, nm), rr, 0.005, K["plate"], knee, sides=8, loop=True))
        parts.append(g_pipe("Leg%s_GreaveCuff" % n, [gp(0.86, 2 * math.pi * j / N, 0.0145 + 0.02 * (0.06 / 0.19) ** 1.6)
                                                     for j in range(N)], 0.0026, K["plate_d"], knee, sides=6, loop=True))
        parts.append(g_pipe("Leg%s_GreaveKeel" % n, [gp(t, 0.0, 0.0135) for t in (0.4, 0.55, 0.7, 0.82)], 0.0026,
                            K["plate_d"], knee, sides=6))
        for sg in (1, -1):
            parts.append(g_pipe("Leg%s_GreaveFlute%d" % (n, sg > 0), [gp(t, sg * 0.75, 0.0135) for t in (0.3, 0.5, 0.68, 0.82)],
                                0.002, K["plate_d"], knee, sides=6))
        # ---- placa em V sob o joelho
        AV = 1.0

        def vplate(u, v):
            a = -AV + 2 * AV * v
            tb = 0.17 + 0.2 * (1 - abs(a) / AV) ** 1.2
            return gp(0.13 + (tb - 0.13) * u, a, 0.019)
        vp, vr = _wk_plate("Leg%s_KneeV" % n, vplate, 6, 24, K["plate"], knee, thick=0.005)
        parts.append(vp)
        parts.append(g_pipe("Leg%s_KneeVRim" % n, vr[-1], 0.0045, K["plate"], knee, sides=8))
        # ---- joelheira
        kc = Vector((KJ.x, KJ.y - 0.01, KJ.z - 0.004))
        fwd = Vector((0, -1, 0.12)).normalized()
        u_ = Vector((1, 0, 0))
        v_ = fwd.cross(u_).normalized()
        RAD = 0.078
        cap = []
        for i in range(1, 9):
            al = 1.55 * i / 8
            cap.append([kc + (fwd * math.cos(al) + (u_ * math.cos(2 * math.pi * j / N) * 1.05 +
                                                     v_ * math.sin(2 * math.pi * j / N)) * math.sin(al)) * RAD
                        for j in range(N)])
        tip = kc + fwd * RAD
        parts.append(g_smooth_mesh("Leg%s_Poleyn" % n, [[tip] * N] + cap, K["plate"], knee, cap_end=False, thick=0.005,
                                   outward=True))
        parts.append(g_pipe("Leg%s_PoleynRim" % n, cap[-1], 0.0055, K["plate"], knee, sides=8, loop=True))
        parts.append(g_pipe("Leg%s_PoleynLine" % n, cap[4], 0.002, K["plate_d"], knee, sides=6, loop=True))
        parts.append(g_bead("Leg%s_PoleynBoss" % n, tip + fwd * 0.002, 0.007, K["plate_d"], knee))
        # aleta em ponta do lado de fora, descendo um pouco para trás
        wc = kc + u_ * (s * 0.07) + Vector((0, 0.008, -0.004))
        wing = [(0.0, 0.05), (0.016, 0.03), (0.024, 0.0), (0.02, -0.03), (0.008, -0.062), (-0.004, -0.04),
                (-0.012, -0.012), (-0.014, 0.02)]
        wing = [(x + 0.01, y) for x, y in wing]
        parts.append(g_plate("Leg%s_PoleynWing" % n, wing, wc, (0, 1, 0), (0, 0, 1), 0.006, K["plate"], knee))
        parts.append(g_pipe("Leg%s_PoleynWingRim" % n, [wc + Vector((s * 0.0045, x, y)) for x, y in wing], 0.003,
                            K["plate_d"], knee, sides=6, loop=True))
        join_objs("Leg%s_Boot" % n, parts)
        # ---- sapato de placa: bico longo, fino e pontudo
        f = P["ft"]
        ft = _foot_secs(P, s, 1.06, 0.006)
        tipf = ft[-1]
        ft[-1] = dict(tipf, c=tipf["c"] + Vector((0, -0.045 * f, -0.002 * f)), rx=tipf["rx"] * 0.32, ry=tipf["ry"] * 0.4)
        zmin = 0.02 * f

        def fring(sc, k=1.0):
            return [sc["c"] + Vector((math.sin(a) * sc["rx"] * k, 0, 0)) +
                    Vector((0, 0, max(zmin - sc["c"].z, math.cos(a) * sc["ry"] * k * 0.86)))
                    for a in (2 * math.pi * j / N for j in range(N))]
        h0 = ft[0]
        hc = dict(h0, c=h0["c"] + Vector((0, 0.014 * f, 0.006)))
        frs = [fring(hc, 0.02), fring(dict(h0, c=h0["c"] + Vector((0, 0.011 * f, 0.004))), 0.5), fring(h0, 0.9)]
        frs += [fring(x) for x in ft]
        frs.append(fring(dict(ft[-1], c=ft[-1]["c"] + Vector((0, -0.035 * f, -0.001))), 0.12))
        shoe = g_smooth_mesh("Leg%s_Foot" % n, frs, K["plate"], ankle)
        foot = [shoe, foot_sole("Leg%s_Sole" % n, ft, sole, ankle, f, heel=0.01 * f)]
        for k, i in enumerate((1, 2, 3, 4)):
            if i >= len(ft) - 1:
                break
            b = ft[i]
            arc = [b["c"] + Vector((math.sin(t) * (b["rx"] * 1.0 + 0.003), 0,
                                    max(zmin - b["c"].z + 0.004, math.cos(t) * (b["ry"] * 0.86 + 0.003))))
                   for t in (-1.7 + 3.4 * m / 14 for m in range(15))]
            foot.append(g_pipe("Leg%s_SabatonLame%d" % (n, k), arc, 0.0032, K["plate_d"], ankle, sides=6))
        bs = _mt_bvh([shoe])
        ridge = []
        for i in range(2, len(ft)):
            c = ft[i]["c"]
            h = bs.ray_cast(c + Vector((0, 0, 0.2)), Vector((0, 0, -1)))[0]
            if h is not None:
                ridge.append(h + Vector((0, 0, 0.0015)))
        if len(ridge) > 1:
            foot.append(g_pipe("Leg%s_ToeRidge" % n, ridge, 0.0026, K["plate_d"], ankle, sides=6))
        join_objs("Leg%s_BootFoot" % n, foot)
    g_loose_world("f_celestial")
    g_export("f_celestial", P, R)


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



# ------------------------------------------------------------------ grevas e manoplas da primeira placa
# Combinam com a Couraça de Ferro (a_firstplate): ferro claro e liso com forro de couro claro nas bordas.
# Peças rígidas nos pivôs (Knee / Ankle / Elbow), como as outras botas e luvas; malha lisa (loft de muitos lados).
def _ip_mats():
    return dict(
        plate=gm("fp_plate", "#C9CDD2", 0.35, 0.7), plate_d=gm("fp_plate_d", "#868C95", 0.45, 0.7),
        lining=gm("fp_lining", "#C2A47C", 0.9), lea=gm("fp_leather", "#3A2F2A", 0.8),
        mail=gm("fp_mail", "#2F3035", 0.65, 0.5),
    )


def build_f_ironplate():
    _plate_greaves("f_ironplate", _ip_mats())


def build_f_knightplate():
    """Grevas de prata: as do cavaleiro branco (prata clara, bordas dobradas em prata, malha no gibão escuro)."""
    K = wknight_mats()
    _plate_greaves("f_knightplate", dict(K, lining=K["plate"], mail=K["under"]))


def build_f_royalplate():
    """Grevas reais: as do paladino (prata com frisos de ouro, malha escura)."""
    K = paladin_mats()
    _plate_greaves("f_royalplate", dict(K, lining=K["gold"]))


def _plate_greaves(style, K):
    """Grevas de placa: greva lisa fechada em volta da canela (segue a panturrilha, aresta suave na frente, boca
    um pouco aberta no tornozelo), joelheira em cúpula com asa em gota do lado de fora, pé de placa com três
    lâminas sobre o peito do pé; forro de couro claro nas bocas, na joelheira, na asa e nas lâminas."""
    P, R = g_rig(style)
    NP = 28
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        knee, ankle = R["Knee" + n], R["Ankle" + n]
        KJ = mirror(P["knee"], s)
        sh = S["shin"]
        parts = []
        # o espaço dos pés esconde o joelho do corpo: calça na canela e cota de malha fechando a volta do joelho
        # (atrás ficava um buraco, via-se o lado de dentro da joelheira)
        M = g_mats()
        _shin_hose(P, R, n, s, M["pants"])
        th = S["thigh"]
        kn = grow(span(th, 0.9, 1.0), 1.0, 0.004) + grow(span(sh, 0.0, 0.22), 1.0, 0.004)[1:]
        parts.append(loft("Leg%s_KneeMail" % n, kn, K["mail"], knee, sides=NP))

        def ring(t, add, flare=0.0):
            q = sample(sh, t)
            c = q["c"]
            rx, ry = q["rx"] * 1.06 + add + flare, q["ry"] * 1.06 + add + flare
            fr, bk = q.get("fr", 1.0), q.get("bk", 1.0)
            out = []
            for j in range(NP):
                a = 2 * math.pi * j / NP
                x, y = cb_spt(a, rx, ry, fr, bk, keel=0.06)
                out.append(Vector((c.x + x, c.y + y, c.z)))
            return out
        ts = [0.2 + 0.78 * i / 12 for i in range(13)]
        rings = [ring(t, 0.012, 0.012 * max(0.0, (t - 0.85) / 0.13) ** 1.5) for t in ts]
        parts.append(g_smooth_mesh("Leg%s_Greave" % n, rings, K["plate"], knee, cap_end=False, thick=0.005,
                                   outward=True))
        for nm, rr in (("Top", rings[0]), ("Bot", rings[-1])):
            parts.append(g_pipe("Leg%s_GreaveLining%s" % (n, nm), rr, 0.0055, K["lining"], knee, sides=8, loop=True))
        parts.append(g_pipe("Leg%s_GreaveBand" % n, ring(0.78, 0.0155), 0.003, K["plate_d"], knee, sides=6, loop=True))
        # joelheira: calota na frente do joelho (centro um pouco para trás), borda forrada
        kc = Vector((KJ.x, KJ.y - 0.014, KJ.z - 0.012))
        fwd = Vector((0, -1, 0.15)).normalized()
        u = Vector((1, 0, 0))
        v = fwd.cross(u).normalized()
        RAD = 0.07
        cap = []
        for i in range(1, 9):
            al = 1.45 * i / 8
            cap.append([kc + (fwd * math.cos(al) + (u * math.cos(2 * math.pi * j / NP) * 1.05 +
                                                     v * math.sin(2 * math.pi * j / NP)) * math.sin(al)) * RAD
                        for j in range(NP)])
        tip = kc + fwd * RAD
        parts.append(g_smooth_mesh("Leg%s_Poleyn" % n, [[tip] * NP] + cap, K["plate"], knee, cap_end=False,
                                   thick=0.005, outward=True))
        parts.append(g_pipe("Leg%s_PoleynLining" % n, cap[-1], 0.006, K["lining"], knee, sides=8, loop=True))
        parts.append(g_bead("Leg%s_PoleynBoss" % n, tip + fwd * 0.002, 0.008, K["plate_d"], knee))
        # asa em gota do lado de fora do joelho, forrada
        wc = kc + u * (s * 0.07) + Vector((0, 0.006, -0.004))
        leaf = [(math.sin(2 * math.pi * j / 20) * 0.03 * (1 - 0.3 * max(0.0, -math.cos(2 * math.pi * j / 20))),
                 math.cos(2 * math.pi * j / 20) * 0.048 - 0.006) for j in range(20)]
        parts.append(g_plate("Leg%s_PoleynWing" % n, leaf, wc, (0, 1, 0), (0, 0, 1), 0.006, K["plate"], knee))
        parts.append(g_pipe("Leg%s_PoleynWingLining" % n, [wc + Vector((s * 0.004, x, y)) for x, y in leaf], 0.0035,
                            K["lining"], knee, sides=6, loop=True))
        join_objs("Leg%s_Boot" % n, parts)
        # pé: sapato de placa com sola de couro e três lâminas forradas sobre o peito do pé
        foot = _shoe(P, R, n, s, K["plate"], K["lea"])
        ft = _foot_secs(P, s, 1.08, 0.006)
        for k, i in enumerate((1, 2, 3)):
            a = ft[i]
            c = a["c"]
            arc = [c + Vector((math.sin(th) * (a["rx"] + 0.004), 0.0, math.cos(th) * (a["ry"] + 0.004)))
                   for th in (-1.25 + 2.5 * m / 12 for m in range(13))]
            foot.append(g_pipe("Leg%s_SabatonLame%d" % (n, k), arc, 0.0045, K["lining"], ankle, sides=8))
        join_objs("Leg%s_BootFoot" % n, foot)
    g_export(style, P, R)


def build_g_ironplate():
    _plate_gauntlets("g_ironplate", _ip_mats())


def build_g_knightplate():
    K = wknight_mats()
    _plate_gauntlets("g_knightplate", dict(K, lining=K["plate"]))


def build_g_royalplate():
    K = paladin_mats()
    _plate_gauntlets("g_royalplate", dict(K, lining=K["gold"]))


def _plate_gauntlets(style, K):
    """Manoplas de placa: mão de placa (fechada e aberta, o jogo usa uma das duas) e punho de placa que abre
    em sino para o cotovelo, com forro de couro claro na boca e um friso no pulso."""
    P, R = g_rig(style)
    SD = 20
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        fd = (F[-1]["c"] - F[0]["c"]).normalized()
        soft_fist("Arm" + n, P, s, K["plate"], elbow)
        relaxed_hand("Arm" + n, P, s, K["plate"], elbow)
        c0 = grow([sample(F, 0.62)], 1.36, 0.02)[0]
        c1 = grow([sample(F, 0.82)], 1.16, 0.012)[0]
        c2 = grow([sample(F, 1.0)], 1.12, 0.009)[0]
        parts = [loft("Arm%s_Cuff" % n, [c0, c1, c2], K["plate"], elbow, sides=SD, caps=(False, False), thick=0.006)]
        parts.append(band("Arm%s_CuffLining" % n, c0, -fd, 0.012, K["lining"], elbow, sides=SD, out=0.002))
        parts.append(band("Arm%s_CuffBand" % n, c2, -fd, 0.008, K["plate_d"], elbow, sides=SD, out=0.002))
        join_objs("Arm%s_Gauntlet" % n, parts)
    g_export(style, P, R)



# ------------------------------------------------------------------ garras e grevas das escamas de brasa
def build_g_emberscale():
    """Garras de escama: mão negra (fechada e aberta), garras compridas nas pontas dos dedos da mão aberta, brasa
    em amêndoa nas costas da mão e punho de escama com anel de brasa."""
    P, R = g_rig("g_emberscale")
    K = ember_mats()
    SD = 20
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        elbow = R["Elbow" + n]
        F = S["fore"]
        fd = (F[-1]["c"] - F[0]["c"]).normalized()
        hd, o, ay, up, pt = _hand_frame(P, s)
        almond = [(math.sin(2 * math.pi * j / 16) * 0.011 * hd, (math.cos(2 * math.pi * j / 16) * 0.026 - 0.05) * hd)
                  for j in range(16)]
        fist = soft_fist("Arm" + n, P, s, K["scale"], elbow)
        fparts = [fist, g_plate("Arm%s_FistGlow" % n, almond, pt(0.034, -0.002, 0.0), ay, up, 0.004, K["vein"], elbow)]
        join_objs("Arm%s_Hand" % n, fparts)
        hand = relaxed_hand("Arm" + n, P, s, K["scale"], elbow)
        oparts = [hand, g_plate("Arm%s_OpenGlow" % n, almond, pt(0.014, -0.002, 0.0), ay, up, 0.004, K["vein"], elbow)]
        # garras: continuam a última falange de cada dedo da mão aberta (mesma conta de relaxed_hand)
        for q, (y, sp, zb, f, w, cu) in enumerate(((-0.0325, -0.007, -0.086, 0.95, 1.0, 0), (-0.0108, -0.002, -0.089, 1.0, 1.04, 4),
                                                   (0.0108, 0.003, -0.087, 0.93, 0.98, 9), (0.0315, 0.008, -0.081, 0.76, 0.86, 14))):
            cur = (-0.006, zb)
            for L, a in ((0.042, 14 + cu), (0.027, 36 + cu * 1.5), (0.023, 54 + cu * 2)):
                t = math.radians(a)
                d = (-math.sin(t), -math.cos(t))
                cur = (cur[0] + d[0] * L * f, cur[1] + d[1] * L * f)
            yy = y + sp
            oparts.append(g_cone("Arm%s_Claw%d" % (n, q), [pt(cur[0] - d[0] * 0.006, yy, cur[1] - d[1] * 0.006),
                                                          pt(cur[0] + d[0] * 0.018, yy, cur[1] + d[1] * 0.02),
                                                          pt(cur[0] + d[0] * 0.03 - 0.008, yy, cur[1] + d[1] * 0.044)],
                                 0.0078 * hd * w, K["scale_d"], elbow, sides=8))
        oparts.append(g_cone("Arm%s_ClawThumb" % n, [pt(-0.016, -0.0625, -0.088), pt(-0.02, -0.065, -0.105),
                                                     pt(-0.028, -0.064, -0.122)], 0.0075 * hd, K["scale_d"], elbow,
                             sides=8))
        join_objs("Arm%s_HandOpen" % n, oparts)
        c0 = grow([sample(F, 0.66)], 1.34, 0.018)[0]
        c1 = grow([sample(F, 0.84)], 1.16, 0.011)[0]
        c2 = grow([sample(F, 1.0)], 1.12, 0.008)[0]
        cuff = [loft("Arm%s_Cuff" % n, [c0, c1, c2], K["scale"], elbow, sides=SD, caps=(False, False), thick=0.006)]
        cuff.append(band("Arm%s_CuffRim" % n, c0, -fd, 0.01, K["scale_d"], elbow, sides=SD, out=0.002))
        cuff.append(band("Arm%s_CuffGlow" % n, c2, -fd, 0.008, K["vein"], elbow, sides=SD, out=0.002))
        join_objs("Arm%s_Gauntlet" % n, cuff)
    g_export("g_emberscale", P, R)


def build_f_emberscale():
    """Grevas de escama: canela e volta do joelho em casca negra, trança de escamas na frente da canela (pares em
    V com a brasa entre eles), escama em calota no joelho, pé de escama com três garras e uma faixa de brasa."""
    from mathutils.bvhtree import BVHTree
    P, R = g_rig("f_emberscale")
    K = ember_mats()
    NP = 24
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        knee, ankle = R["Knee" + n], R["Ankle" + n]
        sh, th = S["shin"], S["thigh"]
        KJ, AJ = mirror(P["knee"], s), mirror(P["ankle"], s)
        hose = loft("Leg%s_Shin" % n, grow(sh, 1.07, 0.006), K["scale_d"], knee, sides=NP)
        kn = grow(span(th, 0.9, 1.0), 1.0, 0.004) + grow(span(sh, 0.0, 0.22), 1.0, 0.004)[1:]
        parts = [loft("Leg%s_KneeShell" % n, kn, K["scale_d"], knee, sides=NP)]
        bpy.context.view_layer.update()
        mw = hose.matrix_world
        bvh = BVHTree.FromPolygons([mw @ v.co for v in hose.data.vertices], [tuple(p.vertices) for p in hose.data.polygons])
        parts += g_limb_braid("Shin" + n, bvh, KJ, AJ, (0, -1, 0), K, knee, pairs=4, t0=0.14, t1=0.93, ra=0.05,
                              hw0=0.036, hw1=0.012, seam_ph=1.0, ph0=1.9)
        # escama do joelho: calota com a ponta para cima
        kc = Vector((KJ.x, KJ.y - 0.014, KJ.z - 0.012))
        fwd = Vector((0, -1, 0.15)).normalized()
        u = Vector((1, 0, 0))
        v = fwd.cross(u).normalized()
        cap = []
        for i in range(1, 8):
            al = 1.35 * i / 7
            cap.append([kc + (fwd * math.cos(al) + (u * math.cos(2 * math.pi * j / NP) +
                                                     v * math.sin(2 * math.pi * j / NP) * 1.15) * math.sin(al)) * 0.068
                        for j in range(NP)])
        tip = kc + fwd * 0.068
        parts.append(g_smooth_mesh("Leg%s_KneeScale" % n, [[tip] * NP] + cap, K["scale"], knee, cap_end=False,
                                   thick=0.005, outward=True))
        parts.append(g_pipe("Leg%s_KneeScaleEdge" % n, cap[-1], 0.004, K["scale_d"], knee, sides=6, loop=True))
        join_objs("Leg%s_Boot" % n, parts)
        foot = _shoe(P, R, n, s, K["scale"], K["scale_d"])
        ft = _foot_secs(P, s, 1.08, 0.006)
        a = ft[2]
        arc = [a["c"] + Vector((math.sin(t) * (a["rx"] + 0.004), 0.0, math.cos(t) * (a["ry"] + 0.004)))
               for t in (-1.2 + 2.4 * m / 12 for m in range(13))]
        foot.append(g_pipe("Leg%s_FootGlow" % n, arc, 0.0055, K["vein"], ankle, sides=8))
        tipc = ft[-1]["c"]
        k = P["ft"]
        for q, dx in enumerate((-0.024, 0.0, 0.024)):
            foot.append(g_cone("Leg%s_ToeClaw%d" % (n, q), [tipc + Vector((dx * k, 0.012, 0.004)),
                                                           tipc + Vector((dx * k * 1.15, -0.028 * k, 0.006)),
                                                           tipc + Vector((dx * k * 1.25, -0.06 * k, -0.014 * k))],
                               0.012 * k, K["scale_d"], ankle, sides=8))
        join_objs("Leg%s_BootFoot" % n, foot)
    g_export("f_emberscale", P, R)



# ------------------------------------------------------------------ elmo das escamas de brasa
def build_h_emberscale():
    """Elmo de escamas: casco negro fechado e justo; máscara com olhos grandes de brasa sob a sobrancelha, quilha no
    nariz, grade triangular na boca com barras de brasa e placas nas bochechas; casco liso atrás, só com a
    crista de brasa da testa à nuca, dois chifres para trás e guarda-nuca curta."""
    P, R = g_rig("h_emberscale")
    K = ember_mats()
    head = R["Head"]
    C = Vector((0, 0.012, 1.69))

    def hp(th, z, out=0.0):
        """Ponto do casco, em forma de cabeça de dragão: têmporas largas, rosto que afunila em V até o queixo,
        quilha no meio do rosto com focinho, e o alto do crânio mais alto e puxado para trás."""
        dz = z - C.z
        if dz >= 0:
            k = math.sqrt(max(0.03, 1 - (dz / 0.158) ** 2))
            back = 0.03 * (dz / 0.158) ** 1.5              # crânio puxado para trás
        else:
            k = 1 - 0.5 * min(1.0, -dz / 0.19) ** 1.4       # afunila até o queixo
            back = 0.0
        face = max(0.0, math.cos(th))
        kx = k * (1 - 0.1 * face)                           # rosto mais estreito que a nuca
        keel = 0.018 * face ** 7                            # aresta no meio do rosto
        snout = 0.028 * face ** 4 * max(0.0, min(1.0, (1.71 - z) / 0.09)) * max(0.0, min(1.0, (z - 1.5) / 0.05))
        return Vector((math.sin(th) * (0.12 * kx + out),
                       C.y + back - math.cos(th) * (0.136 * k + out + keel + snout), z))
    NP = 40
    zs = [1.5, 1.53, 1.57, 1.61, 1.65, 1.69, 1.73, 1.77, 1.8, 1.825, 1.84, 1.846]
    shell = [[hp(2 * math.pi * j / NP, z) for j in range(NP)] for z in zs]
    parts = [g_smooth_mesh("EmberHelm", shell, K["scale"], head, cap_end=True)]
    # guarda-nuca curta: aba de escama que abre um pouco para baixo e assenta na gola (lados e nuca)
    NA = 36
    flare = []
    for i in range(4):
        u = i / 3
        row = []
        for j in range(NA + 1):
            th = 1.0 + (2 * math.pi - 2.0) * j / NA
            side = min(1.0, min(th - 1.0, 2 * math.pi - 1.0 - th) / 0.5)
            row.append(hp(th, 1.56 - 0.06 * u, 0.003 + (0.004 + 0.03 * u ** 1.5) * (0.4 + 0.6 * side)))
        flare.append(row)
    parts.append(g_smooth_mesh("HelmSkirt", flare, K["scale_d"], head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    parts.append(g_pipe("HelmSkirtGlow", flare[-1], 0.004, K["vein"], head, sides=6))
    # olhos de brasa: amêndoas inclinadas, com sobrancelha em quilha por cima
    for sn, sg in (("L", 1), ("R", -1)):
        th = sg * 0.46
        q = hp(th, 1.695, 0.002)
        nrm = Vector((math.sin(th), -math.cos(th), 0))
        tu = Vector((math.cos(th), math.sin(th), 0)) * sg
        eye = [(-0.026, -0.014), (-0.024, 0.004), (-0.004, 0.016), (0.024, 0.018), (0.034, 0.006), (0.012, -0.012)]
        parts.append(g_plate("HelmEye" + sn, eye, q, tu, (0, 0, 1), 0.006, K["gem"], head))
        brow = [hp(sg * a, 1.712 + 0.05 * (a / 0.9) ** 1.2, 0.009) for a in (0.04, 0.25, 0.5, 0.75, 1.0)]
        parts.append(g_pipe("HelmBrow" + sn, brow, 0.008, K["scale_d"], head, sides=8))
    # quilha do nariz, grade da boca e placas das bochechas em V com fresta de brasa
    parts.append(g_pipe("HelmNose", [hp(0.0, z, 0.004) for z in (1.74, 1.7, 1.66, 1.625)], 0.007,
                        K["scale_d"], head, sides=8))
    # grade da boca: triângulo escuro abaixo do nariz, com barras verticais de brasa
    def gr(x, z, out):                  # x em rad a partir do meio
        return hp(x, z, out)
    tri = [[gr(-0.34 * (1 - u), 1.615 - 0.085 * u, 0.006), gr(0.0, 1.615 - 0.085 * u, 0.012),
            gr(0.34 * (1 - u), 1.615 - 0.085 * u, 0.006)] for u in (0.0, 0.25, 0.5, 0.75, 0.97)]
    parts.append(g_smooth_mesh("HelmGrille", tri, K["scale_d"], head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    for q, x in enumerate((-0.2, -0.1, 0.0, 0.1, 0.2)):
        ln = 0.085 * (1 - abs(x) / 0.34) * 0.9
        parts.append(g_pipe("HelmGrilleBar%d" % q, [gr(x, 1.61, 0.013), gr(x, 1.61 - ln, 0.013)], 0.003, K["vein"],
                            head, sides=6))
    for sn, sg in (("L", 1), ("R", -1)):
        def cheek(u, v, sg=sg):
            a = sg * (0.16 + 0.95 * v)
            top = 1.665 - 0.02 * v
            bot = 1.52 + 0.1 * v ** 1.2                      # borda de baixo sobe para a orelha: V de frente
            return hp(a, top + (bot - top) * u, 0.005 + 0.008 * u)
        rows = [[cheek(i / 5, j / 8) for j in range(9)] for i in range(6)]
        parts.append(g_smooth_mesh("HelmCheek" + sn, rows, K["scale"], head, cap_end=False, closed=False, thick=0.005,
                                   outward=True))
        border = [r[0] for r in rows] + rows[-1][1:-1] + [r[-1] for r in rows][::-1]
        parts.append(g_pipe("HelmCheekEdge" + sn, border, 0.0028, K["scale_d"], head, sides=6, loop=True))
        parts.append(g_pipe("HelmCheekGlow" + sn, [hp(sg * (0.16 + 0.95 * v), 1.672 - 0.02 * v, 0.004) for v in
                                                    (0.0, 0.25, 0.5, 0.75, 1.0)], 0.0035, K["vein"], head, sides=6))
    # crista de brasa: arco no plano do meio, do alto da testa, por cima, até a nuca
    crest = []
    for i in range(21):
        b = 0.55 + (math.pi - 0.75) * i / 20          # 90 graus = topo; menos = frente, mais = nuca
        nrm = Vector((0, -math.cos(b), math.sin(b)))
        base = C + Vector((0, -0.136 * math.cos(b) + 0.03 * max(0.0, math.sin(b)) ** 1.5, 0.158 * math.sin(b)))
        w = 0.008 * math.sin(math.pi * i / 20) ** 0.5 + 0.002
        crest.append([base + Vector((sgx * w, 0, 0)) + nrm * (0.004 + 0.01 * math.sin(math.pi * i / 20)) for sgx in (-1, 0, 1)])
    parts.append(g_smooth_mesh("HelmCrest", crest, K["vein"], head, cap_end=False, closed=False, thick=0.006,
                               outward=True))
    # chifres: saem acima das têmporas e curvam para trás e para cima
    for sn, sg in (("L", 1), ("R", -1)):
        b = hp(sg * 1.45, 1.785, -0.008)
        parts.append(g_cone("HelmHorn" + sn, [b, b + Vector((sg * 0.05, 0.04, 0.045)), b + Vector((sg * 0.075, 0.12, 0.085)),
                                              b + Vector((sg * 0.07, 0.17, 0.125))], 0.019, K["scale_d"], head, sides=10,
                            n=14, ridge=0.0025))
        parts.append(g_pipe("HelmHornGlow" + sn, g_circle(b + Vector((sg * 0.012, 0.01, 0.012)),
                                                           Vector((0, 1, -0.4)), Vector((sg * 0.6, 0, -1)), 0.021, n=14),
                            0.004, K["vein"], head, sides=6, loop=True))
    join_objs("EmberHelm", parts)
    g_export("h_emberscale", P, R)


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


# Elmo do Cavaleiro Dragão (h_dragonknight): rosto esculpido carregado de um .blend preparado
exec(open(OUT.replace("assets/models/", "tools/blender/dragon_helm.py"), encoding="utf-8").read(), globals())

GEAR = [(n, _gear_builder(globals()["build_" + n])) for n in (
    "h_bare", "h_hood", "h_cap", "h_kettle", "h_nasal", "h_great", "h_wizard", "h_archmage", "h_sage", "h_void", "h_oracle", "h_ember",
    "h_lich", "h_hierophant", "h_reaper", "h_raven", "h_dragon", "h_astral", "h_frost", "h_emberscale", "h_celestial",
    "h_dragonknight",
    "a_shirt", "a_tunic", "a_leather", "a_gambeson", "a_ranger", "a_mithril", "a_celestial", "a_whiteknight", "a_paladin", "a_firstplate", "a_emberscale", "a_mail", "a_surcoat", "a_robe", "a_archmage", "a_sage", "a_void", "a_oracle", "a_ember",
    "a_lich", "a_hierophant", "a_reaper", "a_raven", "a_dragon", "a_astral", "a_frost",
    "g_bare", "g_gloves", "g_bracers", "g_ironplate", "g_knightplate", "g_royalplate", "g_emberscale", "g_ranger", "g_mithril", "g_celestial",
    "f_shoes", "f_boots", "f_plated", "f_ironplate", "f_knightplate", "f_royalplate", "f_emberscale", "f_ranger", "f_mithril", "f_celestial")]
