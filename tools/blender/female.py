# Corpo feminino do herói (knight_f.glb e gear/<estilo>_f.glb).
# Executado por exec() dentro de build_assets.py, depois de characters.py, gear.py e body_mesh.py.
#
# Como funciona: cada modelo é montado primeiro no corpo masculino (mesmo código, mesmos nomes de nós e de
# ossos) e depois DEFORMADO para o corpo feminino por fem_warp(). A deformação é feita por região, como um
# esqueleto: o tronco (Body) passa por um campo de forma (mais baixo, ombros e cintura mais estreitos,
# quadril mais largo, glúteos e busto); braços e pernas são transformações afins em volta do ombro e do
# quadril (mais finos e um pouco mais curtos, mãos e pés menores); a cabeça só desce junto com o pescoço
# (fica do mesmo tamanho). Pivôs (empties) e ossos vão para as articulações novas, então as animações por
# pivô e o PivotSkin continuam valendo. Malhas com pesos misturam as regiões pelos pesos, sem frestas.
#
# O busto é um campo no próprio tronco: dois volumes com vinco no meio na pele, vinco mais suave no tecido
# (a roupa passa por cima) e um volume só, sem vinco, no metal (o peitoral cobre o busto).
#
# Cabelo: o rosto e o cabelo de cima (franja, mechas do rosto, cabelo solto nas costas) ficam no estilo de
# cabeça (gear/h_bare_f.glb); o rabo de cavalo alto fica no próprio knight_f.glb (nó "Ponytail", filho de
# Head, com origem no prendedor), então continua aparecendo atrás de qualquer elmo.
import math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

FEM_Z = 0.95                       # altura
FEM_ARM = (0.95, 0.88)             # braço: ao longo do eixo, na seção
FEM_LEG = (0.95, 0.92)             # perna: ao longo do eixo, na seção (pé mais curto junto)
FEM_ABDUCT = math.radians(4.5)     # braço um pouco mais aberto (o quadril mais largo passa perto da mão)
FEM_NECK = 0.86                    # pescoço mais fino
# largura (x) e profundidade (y) do tronco por altura (z do corpo masculino)
FEM_SX = [(0.0, 1.1), (0.95, 1.1), (1.09, 0.77), (1.18, 0.8), (1.29, 0.88), (1.40, 0.86), (1.47, 0.85),
          (3.0, 0.85)]
FEM_SY = [(0.0, 1.0), (0.95, 1.0), (1.09, 0.9), (1.29, 0.93), (1.45, 0.88), (3.0, 0.86)]
# busto (medidas no corpo masculino): altura do centro, quedas para baixo/para cima, centro de cada volume,
# largura de cada volume e projeção para a frente
BUST_Z, BUST_LO, BUST_HI = 1.265, 0.05, 0.085
BUST_X, BUST_W, BUST_A = 0.072, 0.05, 0.064
BUST_LO_CLOTH = 0.06               # tecido: cai um pouco abaixo do busto (dobra/sombra embaixo dele)
BUST_LO_PLATE = 0.07               # peitoral: curva de baixo um pouco mais marcada (o plackart cobre embaixo)


def _ftab(T, z):
    if z <= T[0][0]:
        return T[0][1]
    for (z0, a), (z1, b) in zip(T, T[1:]):
        if z0 <= z <= z1:
            return a + (b - a) * (z - z0) / (z1 - z0)
    return T[-1][1]


def _bust(x, y, z, mode):
    """Quanto o ponto (x, y, z) da frente do tronco vai para a frente (m)."""
    if y >= -0.02:
        return 0.0
    fw = min(1.0, (-y - 0.02) / 0.06) ** 1.5
    d = z - BUST_Z
    lo = {"skin": BUST_LO, "cloth": BUST_LO_CLOTH, "plate": BUST_LO_PLATE}[mode]
    gz = math.exp(-(d / (lo if d < 0 else BUST_HI)) ** 2)
    ax = abs(x)
    two = math.exp(-((ax - BUST_X) / BUST_W) ** 2)                    # dois volumes (vinco no meio)
    one = 1.0 if ax < BUST_X else two                                 # um volume só, plano no meio
    gx = {"skin": two, "cloth": 0.6 * two + 0.4 * one, "plate": one}[mode]
    return BUST_A * fw * gz * gx


def fem_torso(p, mode="cloth"):
    x, y, z = p
    sx, sy = _ftab(FEM_SX, z), _ftab(FEM_SY, z)
    if y > 0:   # glúteos
        sy *= 1.0 + 0.13 * math.exp(-((z - 0.93) / 0.07) ** 2)
    ny = y * sy
    if y < 0:
        ny -= _bust(x, y, z, mode)
    return Vector((x * sx, ny, z * FEM_Z))


class FemWarp:
    """Transformações por região do corpo masculino (GEAR_P) para o feminino."""

    def __init__(self):
        P = body_proportions(**GEAR_P)
        self.J = J = {n: P[n].copy() for n in ("pelvis", "neck", "shoulder", "elbow", "wrist", "hip", "knee",
                                                "ankle")}
        self.dN = fem_torso(J["neck"]) - J["neck"]
        self.arm, self.leg = {}, {}
        for s, n in ((1, "L"), (-1, "R")):
            S, W = mirror(J["shoulder"], s), mirror(J["wrist"], s)
            a = (W - S).normalized()
            ka, kp = FEM_ARM
            M = Matrix.Identity(3) * kp + (ka - kp) * _outer(a)
            Rm = Matrix.Rotation(-s * FEM_ABDUCT, 3, 'Y')
            self.arm[n] = (S, fem_torso(S), Rm @ M)
            Hp, A = mirror(J["hip"], s), mirror(J["ankle"], s)
            a = (A - Hp).normalized()
            ka, kp = FEM_LEG
            self.leg[n] = (Hp, fem_torso(Hp), Matrix.Identity(3) * kp + (ka - kp) * _outer(a))

    def region(self, name):
        """Região de um pivô/osso pelo nome (None = desconhecido)."""
        for pre in ("Arm", "Elbow"):
            if name.startswith(pre) and name[len(pre):] in ("L", "R"):
                return "arm" + name[-1]
        for pre in ("Leg", "Knee", "Ankle"):
            if name.startswith(pre) and name[len(pre):] in ("L", "R"):
                return "leg" + name[-1]
        if name == "Head":
            return "head"
        if name == "Body":
            return "body"
        return None

    def xf(self, reg, p, mode="cloth"):
        p = Vector(p)
        if reg == "body" or reg is None:
            return fem_torso(p, mode)
        if reg == "head":
            return p + self.dN
        if reg == "neck":       # pescoço da pele contínua (pesos do osso Head): desce e afina
            q = p + self.dN
            return Vector((q.x * FEM_NECK, q.y * FEM_NECK, q.z))
        side = reg[-1]
        if reg.startswith("arm"):
            S, S2, M = self.arm[side]
            return S2 + M @ (p - S)
        Hp, H2, M = self.leg[side]
        return H2 + M @ (p - Hp)


def _outer(a):
    return Matrix(((a.x * a.x, a.x * a.y, a.x * a.z), (a.y * a.x, a.y * a.y, a.y * a.z),
                   (a.z * a.x, a.z * a.y, a.z * a.z)))


def _obj_mode(ob):
    mats = [m for m in ob.data.materials if m is not None]
    if mats and all("skin" in m.name for m in mats):
        return "skin"
    metal = 0
    for m in mats:
        b = next((nd for nd in m.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED'), None) if m.node_tree else None
        if b is not None and b.inputs["Metallic"].default_value > 0.55:
            metal += 1
    return "plate" if mats and metal * 2 >= len(mats) else "cloth"


def _pivot_region(W, ob):
    o = ob.parent
    while o is not None:
        r = W.region(o.name)
        if r is not None:
            return r
        o = o.parent
    return "body"


def fem_warp(objs=None):
    """Deforma a cena inteira (ou objs) do corpo masculino para o feminino. Empties, ossos e malhas."""
    W = FemWarp()
    objs = list(objs if objs is not None else coll.all_objects)
    empties = [o for o in objs if o.type == 'EMPTY']
    arms = [o for o in objs if o.type == 'ARMATURE']
    meshes = [o for o in objs if o.type == 'MESH']
    bpy.context.view_layer.update()
    old_w = {o.name: o.matrix_world.copy() for o in objs}
    # ---- malhas: posições novas em coordenadas de mundo
    new_v, new_o = {}, {}
    for ob in meshes:
        mw = old_w[ob.name]
        mode = _obj_mode(ob)
        groups = {g.index: g.name for g in ob.vertex_groups}
        rigid = None
        if groups:
            if len(groups) == 1:
                rigid = W.region(next(iter(groups.values())))
        else:
            rigid = _pivot_region(W, ob)
        pts = []
        for v in ob.data.vertices:
            p = mw @ v.co
            if rigid is not None or not v.groups:
                pts.append(W.xf(rigid or _pivot_region(W, ob), p, mode))
                continue
            acc, tw = Vector((0, 0, 0)), 0.0
            for g in v.groups:
                if g.weight <= 0:
                    continue
                r = W.region(groups[g.group])
                if r == "head":
                    r = "neck"
                acc += W.xf(r, p, mode) * g.weight
                tw += g.weight
            pts.append(acc / tw if tw > 0 else W.xf("body", p, mode))
        new_v[ob.name] = pts
        o0 = mw.to_translation()
        reg = rigid if rigid is not None else _pivot_region(W, ob)
        new_o[ob.name] = W.xf(reg, o0, mode) if ob.parent is not None and ob.parent.type == 'EMPTY' else o0
    # ---- pivôs
    new_e = {}
    for e in empties:
        p = old_w[e.name].to_translation()
        reg = W.region(e.name)
        new_e[e.name] = W.xf(reg, p) if reg is not None else p
    for e in empties:
        par = new_e.get(e.parent.name, Vector((0, 0, 0))) if e.parent is not None else Vector((0, 0, 0))
        e.location = new_e[e.name] - par
        e["wloc"] = list(new_e[e.name])
    # ---- ossos
    for rig in arms:
        vl = bpy.context.view_layer
        vl.objects.active = rig
        with bpy.context.temp_override(active_object=rig, object=rig):
            bpy.ops.object.mode_set(mode='EDIT')
        for b in rig.data.edit_bones:
            reg = W.region(b.name)
            b.head, b.tail = W.xf(reg, b.head), W.xf(reg, b.tail)
        with bpy.context.temp_override(active_object=rig, object=rig):
            bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()
    for ob in meshes:
        if ob.parent is not None and ob.parent.type == 'EMPTY':
            ob.location = new_o[ob.name] - new_e.get(ob.parent.name, Vector((0, 0, 0)))
        bpy.context.view_layer.update()
        inv = ob.matrix_world.inverted()
        for v, p in zip(ob.data.vertices, new_v[ob.name]):
            v.co = inv @ p
        ob.data.update()
    bpy.context.view_layer.update()
    return W


# ------------------------------------------------------------------ conferência de peças soltas (mundo)
def loose_world(asset, objs=None, touch=0.0015):
    objs = [o for o in (objs or coll.all_objects) if o.type == 'MESH']
    bpy.context.view_layer.update()
    wv = {o.name: [o.matrix_world @ v.co for v in o.data.vertices] for o in objs}
    trees = {o.name: BVHTree.FromPolygons(wv[o.name], [tuple(p.vertices) for p in o.data.polygons]) for o in objs}
    group = {o.name: i for i, o in enumerate(objs)}
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            if group[a.name] == group[b.name]:
                continue
            ta, tb = trees[a.name], trees[b.name]
            hit = bool(ta.overlap(tb))
            if not hit:
                for n, t in ((a.name, tb), (b.name, ta)):
                    if any(t.find_nearest(v, touch)[0] is not None for v in wv[n]):
                        hit = True
                        break
            if hit:
                old, new = group[b.name], group[a.name]
                for k in group:
                    if group[k] == old:
                        group[k] = new
    comps = {}
    for k, g in group.items():
        comps.setdefault(g, []).append(k)
    comps = sorted(comps.values(), key=len, reverse=True)
    if len(comps) > 1:
        print("LOOSE %s: %s" % (asset, " | ".join(", ".join(sorted(c)) for c in comps[1:])), flush=True)
    else:
        print("CONNECTED %s" % asset, flush=True)
    return comps


# ------------------------------------------------------------------ cabelo
def fem_hair_mats(M=None):
    return {"hair": gm("g_hair", "#4A2C17", 0.9), "mid": gm("g_hair_mid", "#6E4428", 0.9),
            "under": gm("g_hair_under", "#2B190C", 0.9), "tie": gm("g_hair_tie", "#8E2430", 0.85)}


def strand(name, pts, widths, thick, material, parent, center):
    """Mecha em losango (aresta viva no meio, ponta fina) por pts; center = centro da cabeça: acima dele a
    espessura sai do centro, abaixo sai na horizontal (mechas caídas)."""
    bm = bmesh.new()
    secs, last = [], len(pts) - 1
    for i, p in enumerate(pts):
        if i == last:
            secs.append([bm.verts.new(p)])
            continue
        tan = (pts[min(i + 1, last)] - pts[max(i - 1, 0)]).normalized()
        c = Vector((center.x, center.y, min(p.z, center.z)))
        out = p - c
        if out.length < 1e-5:
            out = Vector((0, 1, 0))
        out = (out - tan * out.dot(tan)).normalized()
        side = tan.cross(out).normalized()
        w, t = widths[i] / 2, thick[i]
        secs.append([bm.verts.new(p - side * w), bm.verts.new(p + out * t), bm.verts.new(p + side * w),
                     bm.verts.new(p - out * t * 0.35)])
    bm.faces.new(secs[0])
    for a, b in zip(secs, secs[1:]):
        for k in range(4):
            if len(b) == 1:
                bm.faces.new((a[k], a[(k + 1) % 4], b[0]))
            else:
                bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    _place(bm, (0, 0, 0), parent)
    return _finish(name, bm, material, parent)


def _fscalp(H, phi, th, k=1.07, lift=0.0):
    s = H["s"]
    C = Vector((0, H["cy"], H["chin"] + 12.0 * s))
    d = _hdir(phi, th)
    P = C + Vector((d.x * 7.25 * s * k, d.y * (9.6 if d.y < 0 else 9.8) * s * k, d.z * 11.0 * s * k))
    return P + (P - C).normalized() * lift


def _back_y(x, z, add):
    """y das costas (corpo masculino da roupa padrão) em (x, z), mais add."""
    T = CB_TORSO
    for (z0, rx0, ry0, e0), (z1, rx1, ry1, e1) in zip(T, T[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            rx = rx0 + (rx1 - rx0) * t
            ry = ry0 * e0.get("bk", 1.0) + (ry1 * e1.get("bk", 1.0) - ry0 * e0.get("bk", 1.0)) * t
            yo = e0.get("y", 0.0) + (e1.get("y", 0.0) - e0.get("y", 0.0)) * t
            q = max(0.0, 1.0 - (abs(x) / rx) ** 2.12) if abs(x) < rx else 0.0
            return yo + ry * q ** (1 / 2.12) + add
    return add


# mechas soltas de trás: (direção em graus, z da ponta no corpo masculino); o meio desce mais (barra em V)
BACK_LOCKS = [(100, 1.43), (122, 1.385), (146, 1.345), (169, 1.32), (191, 1.32), (214, 1.345), (238, 1.385),
              (260, 1.43)]
HAIR_CLEAR = 0.04            # distância do cabelo solto às costas (pele); cobre camisa e couro
# cabelo de cima no estilo dos NPCs (anime.py): franja larga repartida caindo para um lado com a testa e os
# olhos à mostra, camada de cima com volume, mechas pontudas
FEM_HAIR_STYLE = {"fringe": 24, "side": 4, "back": -30, "part": 30, "sweep": -1, "top": 9, "w": 1.3,
                  "lift": 1.7, "seed": 7}


def _hair_nrm(H):
    s = H["s"]
    C = Vector((0, H["cy"], H["chin"] + 12.0 * s))

    def nrm(p):
        r = p - C
        if r.z > 0:
            return Vector((r.x / 7.5 ** 2, r.y / 9.5 ** 2, r.z / 11.0 ** 2)).normalized()
        h = Vector((r.x, r.y, 0))
        return h.normalized() if h.length > 1e-5 else Vector((0, 1, 0))
    return nrm


def fem_hair(H, head, HM, back=True):
    """Cabelo comprido: camadas anime (calota, camada de cima com volume, franja larga para o lado, nuca),
    duas mechas largas emoldurando o rosto até o colo e (back) cabelo solto nas costas até as escápulas."""
    s = H["s"]
    out = anime_hair("", H, HM, head, FEM_HAIR_STYLE)
    nrm = _hair_nrm(H)

    def sp(th, ph, lift):
        return _scalp(H, th, ph, lift * s)
    fb = bmesh.new()
    for sg in (1, -1):        # mechas do rosto: da têmpora, na frente da orelha, até abaixo do queixo
        _lock(fb, [sp(sg * 56, 46, 1.2), sp(sg * 70, 18, 1.8), sp(sg * 78, -12, 1.9),
                   Vector((sg * 0.074, -0.022, H["chin"] - 0.012)), Vector((sg * 0.07, -0.05, H["chin"] - 0.062))],
              0.024, nrm, th_k=0.32, k=3, root=0.6)
    out.append(_hair_obj("HairFrame", fb, HM["hair"], head))
    if back:
        bb = bmesh.new()
        for th, z_end in BACK_LOCKS:
            ctrl = [sp(180 + (th - 180) * 0.6, 74, 1.0), sp(th, 38, 1.8), sp(th, 0, 2.0), sp(th, -26, 1.8)]
            pe = ctrl[-1]
            for j in (1, 2, 3):
                t = j / 3
                z = pe.z + (z_end - pe.z) * t
                x = pe.x * (1 - 0.3 * t)
                ctrl.append(Vector((x, max(pe.y + 0.01 * t, _back_y(x, z, HAIR_CLEAR + 0.004 * j)), z)))
            _lock(bb, ctrl, 0.036 if abs(th - 180) < 30 else 0.032, nrm, th_k=0.3, k=3, root=0.7)
        out.append(_hair_obj("HairLong", bb, HM["under"], head))
    return out


def ponytail_path(H):
    """Rabo de cavalo alto (medidas do corpo masculino, região da cabeça): do prendedor no alto da nuca
    sobe um pouco para trás e cai pelas costas, por fora do cabelo solto, até abaixo das escápulas."""
    tie = _fscalp(H, 180, 34, lift=0.024)
    root = _fscalp(H, 180, 40, k=0.7)
    path = [tie + Vector((0, 0.04, 0.004)), tie + Vector((0, 0.066, -0.03)), tie + Vector((0, 0.074, -0.078))]
    for z in (1.6, 1.545, 1.49):
        y = max(_back_y(0, z, HAIR_CLEAR + 0.06), path[-1].y - 0.008)
        path.append(Vector((0, y, z)))
    path.append(path[-1] + Vector((0, -0.004, -0.045)))
    return root, tie, path


def build_ponytail(root, tie, path, head, HM):
    """Malha do rabo de cavalo (coordenadas de mundo; origem final no prendedor)."""
    # volume principal: seção oval (larga em x), cheia logo depois do prendedor, afina para a ponta
    rad = [(0.044, 0.04), (0.054, 0.046), (0.052, 0.044), (0.046, 0.038), (0.038, 0.032), (0.028, 0.024),
           (0.018, 0.015), (0.01, 0.009)]
    secs = [sec(root, 0.022, 0.02), sec(tie, 0.024, 0.021)] + [sec(p, rx, ry) for p, (rx, ry) in zip(path, rad)]
    parts = [loft("Ponytail", secs, HM["hair"], head, sides=7, phase=0.5)]
    # pontas: três mechas pontudas saindo do fim (anime) e duas mechas soltas por fora do volume
    end, prev = path[-1], path[-2]
    d = (end - prev).normalized()
    axis = Vector((0, 0, 9.0))
    for k, (dx, dy, ln, w, m) in enumerate(((0.0, 0.004, 0.1, 0.034, "hair"), (0.022, -0.006, 0.075, 0.028, "mid"),
                                            (-0.022, -0.004, 0.08, 0.028, "under"))):
        a = prev.lerp(end, 0.4) + Vector((dx * 0.6, dy, 0))
        b = end + Vector((dx, dy, 0)) + d * ln * 0.5
        c = end + Vector((dx * 1.5, dy + 0.004, 0)) + d * ln
        parts.append(strand("PonyTip%d" % k, [a, b, c], [w, w * 0.6, 0.0], [0.012, 0.009, 0.0], HM[m], head, axis))
    # mechas largas e pontudas por cima do volume (estilo anime): meio e dois lados, em tons diferentes
    for k, (sg, m, ln) in enumerate(((0, "mid", 0.07), (1, "hair", 0.05), (-1, "under", 0.055))):
        def at(i, f=1.0):
            rx, ry = rad[i]
            return path[i] + Vector((sg * rx * 0.62, ry * (0.82 if sg else 0.98) + 0.004, 0)) * f
        ctrl = [at(0), at(1), at(3), at(5), path[6] + Vector((sg * 0.016, 0.012, -ln))]
        lb = bmesh.new()
        _lock(lb, ctrl, 0.03 if sg == 0 else 0.026, lambda p_, sg=sg: Vector((sg * 0.6, 1, 0)).normalized(),
              th_k=0.3, k=3, root=0.8)
        parts.append(_hair_obj("PonyLock%d" % k, lb, HM[m], head))
    # prendedor: aro de fita em volta do começo do rabo
    ax = (path[0] - tie).normalized()
    parts.append(loft("PonyTie", [sec(tie - ax * 0.008, 0.03, 0.027), sec(tie + ax * 0.016, 0.031, 0.028)],
                      HM["tie"], head, sides=8, axis=ax, chamfer=(0.003, 0.003)))
    ob = join_objs("Ponytail", parts)
    for pl in ob.data.polygons:      # liso como o cabelo anime da cabeça
        pl.use_smooth = True
    # origem no prendedor (o jogo pode balançar o nó em volta dele)
    off = tie - _wloc(head)
    for v in ob.data.vertices:
        v.co -= off
    ob.data.update()
    ob.location = ob.location + off
    return ob


# ------------------------------------------------------------------ rosto feminino
FEM_FACE = {"eye_w": 1.12, "eye_h": 1.15, "lash": 1.5, "brow": 0.7, "brow_dz": 0.4, "nose": 0.55, "jaw": 0.86,
            "mouth_w": 0.85}


def fem_plain_head(R, M, beard=False, hair=True):
    """plain_head do corpo feminino (barba nunca): rosto anime liso (anime.py) com olhos grandes e brilho,
    cílios marcados, sobrancelha fina e alta, nariz pequeno, queixo fino e boca rosada; cabelo comprido sem o
    rabo de cavalo (que mora no knight_f.glb)."""
    head = R["Head"]
    am = anime_mats("hf", hexc("#D29A74"), hexc("#5B3A22"), hexc("#3A2213"), hexc("#1E120A"), hexc("#C25D68"))
    H = anime_head("", HEAD_CHIN, HEAD_H, head, am, FEM_FACE)
    if hair:
        fem_hair(H, head, fem_hair_mats(M), back=True)
    return H


def fem_head_marks():
    """Marcos da cabeça (sem criar nada), para o rabo de cavalo."""
    s = HEAD_H / 23.0
    return {"s": s, "chin": HEAD_CHIN, "cy": 0.45 * s}


# ------------------------------------------------------------------ montagem
def knight_f_finish(R):
    """Chamado por build_knight(female=True) antes de assar e exportar: deforma o cavaleiro e põe o rabo de
    cavalo, afastado da armadura e da capa."""
    W = fem_warp()
    H = fem_head_marks()
    # a capa fica de fora: o rabo deita por cima dela (e sem capa ficaria solto no ar, longe das costas)
    body_objs = [o for o in coll.all_objects if o.type == 'MESH' and _pivot_region(W, o) == "body"
                 and o.name != "Cape"]
    trees = [BVHTree.FromPolygons([o.matrix_world @ v.co for v in o.data.vertices],
                                  [tuple(p.vertices) for p in o.data.polygons]) for o in body_objs]
    chin = H["chin"] + W.dN.z

    def push(p):
        q = p + W.dN
        for _ in range(20):
            hits = [h for h in (t.find_nearest(q) for t in trees) if h[0] is not None]
            if not hits or min(h[3] for h in hits) >= 0.03 or q.z > chin + 0.06:
                break
            q.y += 0.008
        return q

    root, tie, path = ponytail_path(H)
    path = [push(p) for p in path]
    for i in range(1, len(path)):          # sem voltar para a frente depois de empurrado
        if path[i].z < path[i - 1].z and path[i].y < path[i - 1].y - 0.012:
            path[i].y = path[i - 1].y - 0.012
    build_ponytail(root + W.dN, tie + W.dN, path, R["Head"], fem_hair_mats())
    loose_world("knight_f")


def build_knight_f():
    build_knight(female=True)


# roupas e elmos: a mesma montagem dos estilos masculinos, com cabeça feminina, deformada antes de assar
_g_export_m = g_export


def _g_export_f(style, P=None, R=None):
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    occ = []
    if P is not None and targets:
        occ = _occluders(style, P, R, g_mats())
    fem_warp()
    if P is not None and targets:
        bake_ao(targets, occ)
    export("gear/" + style + "_f", export_vertex_color='ACTIVE')


def fem_gear(style, fn):
    def run():
        global g_export, plain_head, band
        g0, h0, b0 = g_export, plain_head, band
        # band: armory.py redefine band() depois de characters.py; as roupas usam a do cavaleiro
        g_export, plain_head, band = _g_export_f, fem_plain_head, _knight_band
        try:
            fn()
        finally:
            g_export, plain_head, band = g0, h0, b0
    return run


FEM_GEAR = [(n + "_f", fem_gear(n, f)) for n, f in GEAR]
