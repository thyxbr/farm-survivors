# Corpo-base humanoide low poly: malhas contínuas feitas de anéis de seção transversal ligados (loft),
# facetadas (shading flat), com proporções parametrizadas e o rig de pivôs que o jogo anima.
# Executado por exec() dentro de characters.py (usa bpy, bmesh, Vector, coll, empty, _wloc, _finish, _place).
# Reutilizável: o cavaleiro usa hoje; ancião, mercadora e soldados podem usar depois.
#
# Seção (anel) = dict criado por sec():
#   c        centro (mundo)
#   rx, ry   meia-largura (eixo lateral) e meia-profundidade (eixo "frente" do loft)
#   fr, bk   multiplicam a metade da frente / de trás (peito estufado, panturrilha, sola reta)
#   sq       expoente da superelipse: 2 = elipse, 3-4 = mais quadrado
#   keel     quilha: empurra só o vértice da frente (crista do peitoral, da canela, do visor)
#
# Membros afinam de forma contínua (ombro -> cotovelo -> pulso, coxa -> joelho -> tornozelo). Como o jogo
# anima girando pivôs (sem armature), cada segmento é uma malha presa ao seu pivô; as seções nas
# articulações coincidem, então o corpo parado lê como uma peça só.
import bmesh, math
from mathutils import Vector

REF_HEIGHT = 1.84


# ------------------------------------------------------------------ seções
def sec(c, rx, ry, fr=1.0, bk=1.0, sq=2.0, keel=0.0):
    return dict(c=Vector(c), rx=rx, ry=ry, fr=fr, bk=bk, sq=sq, keel=keel)


def _mix(a, b, t):
    out = {k: a[k] + (b[k] - a[k]) * t for k in ("rx", "ry", "fr", "bk", "sq", "keel")}
    out["c"] = a["c"].lerp(b["c"], t)
    return out


def _cum(secs):
    d = [0.0]
    for a, b in zip(secs, secs[1:]):
        d.append(d[-1] + (b["c"] - a["c"]).length)
    return d


def sample(secs, t):
    """Seção interpolada no ponto t (0..1, pelo comprimento do caminho)."""
    d = _cum(secs)
    L = d[-1] or 1.0
    x = max(0.0, min(1.0, t)) * L
    for i in range(len(secs) - 1):
        if x <= d[i + 1] or i == len(secs) - 2:
            seg = d[i + 1] - d[i]
            return _mix(secs[i], secs[i + 1], 0.0 if seg <= 0 else (x - d[i]) / seg)
    return dict(secs[-1])


def span(secs, t0, t1):
    """Trecho do caminho entre t0 e t1, mantendo as seções originais do meio."""
    d = _cum(secs)
    L = d[-1] or 1.0
    out = [sample(secs, t0)]
    out += [dict(s) for s, x in zip(secs, d) if t0 * L + 1e-4 < x < t1 * L - 1e-4]
    out.append(sample(secs, t1))
    return out


def grow(secs, k=1.0, add=0.0, **over):
    """Infla as seções (armadura sobre o corpo): r * k + add. over substitui campos (ex.: keel=0.1)."""
    out = []
    for s in secs:
        n = dict(s)
        n["rx"] = s["rx"] * k + add
        n["ry"] = s["ry"] * k + add
        n.update(over)
        out.append(n)
    return out


def stepped(secs, ts, drop=0.9, eps=0.012, keep_bottom=False):
    """Insere degraus (placas sobrepostas) nos pontos ts: a placa de cima termina maior que a de baixo.
    keep_bottom mantém a face de trás (sola) reta ao encolher."""
    d = _cum(secs)
    L = d[-1] or 1.0
    marks = []
    for t in ts:
        a = sample(secs, t)
        b = sample(secs, t + eps / L)
        b["rx"] *= drop
        b["ry"] *= drop
        if keep_bottom:
            b["bk"] /= drop
        marks.append((t * L, a))
        marks.append((t * L + eps, b))
    pts = [(x, dict(s)) for s, x in zip(secs, d)] + marks
    pts.sort(key=lambda p: p[0])
    out = []
    for x, s in pts:
        if out and abs(x - out[-1][0]) < 1e-5:
            continue
        out.append((x, s))
    return [s for _, s in out]


# ------------------------------------------------------------------ loft
def _frames(secs, axis, fwd):
    n = len(secs)
    out = []
    prev_side = None
    for i, s in enumerate(secs):
        if axis is not None:
            t = Vector(axis).normalized()
        else:
            a, b = secs[max(i - 1, 0)]["c"], secs[min(i + 1, n - 1)]["c"]
            t = (b - a).normalized()
        f = Vector(fwd)
        f = f - t * f.dot(t)
        if f.length < 1e-4:
            f = Vector((0, 0, 1)) - t * t.z
            if f.length < 1e-4:
                f = Vector((1, 0, 0)) - t * t.x
        f.normalize()
        side = f.cross(t).normalized()
        if prev_side is not None and side.dot(prev_side) < 0:
            side = -side
        prev_side = side
        out.append((t, side, f))
    return out


def _ring(s, side, front, sides, phase, arc, thick):
    e = 2.0 / s["sq"]

    def pt(a, shrink=0.0):
        ca, sa = math.cos(a), math.sin(a)
        ex = math.copysign(abs(ca) ** e, ca)
        ey = math.copysign(abs(sa) ** e, sa)
        kp = 1.0 + s["keel"] * max(0.0, sa) ** 6
        rx = (s["rx"] - shrink) * kp
        ry = (s["ry"] - shrink) * kp * (s["fr"] if ey > 0 else s["bk"])
        return s["c"] + side * (rx * ex) + front * (ry * ey)

    if arc is None:
        return [pt(2 * math.pi * (k + phase) / sides) for k in range(sides)]
    angs = [math.pi / 2 - arc / 2 + arc * k / sides for k in range(sides + 1)]
    return [pt(a) for a in angs] + [pt(a, thick) for a in reversed(angs)]


def loft(name, secs, material, parent, sides=8, phase=0.5, chamfer=(0.0, 0.0), caps=(True, True), axis=None,
         fwd=(0, -1, 0), arc=None, thick=0.012):
    """Liga as seções num tubo fechado facetado. phase=0 com sides múltiplo de 4 põe um vértice na frente
    (necessário para keel). chamfer=(início, fim): anel extra encolhido antes da tampa = chanfro de 1 segmento.
    arc (rad) faz uma placa curva (só a frente do anel, com espessura thick) em vez de um tubo."""
    if isinstance(chamfer, (int, float)):
        chamfer = (chamfer, chamfer)
    fr = _frames(secs, axis, fwd)
    rings = [_ring(s, side, f, sides, phase, arc, thick) for s, (t, side, f) in zip(secs, fr)]
    for end, amt in ((0, chamfer[0]), (-1, chamfer[1])):
        if not amt or not caps[0 if end == 0 else 1]:
            continue
        s, (t, _, _) = secs[end], fr[end]
        out = -t if end == 0 else t
        c = s["c"] + out * amt * 0.8
        r = [c + (p - s["c"]) * max(0.25, 1.0 - amt / max((p - s["c"]).length, 1e-6)) for p in rings[end]]
        if end == 0:
            rings.insert(0, r)
        else:
            rings.append(r)
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    m = len(vr[0])
    for a, b in zip(vr, vr[1:]):
        for j in range(m):
            k = (j + 1) % m
            bm.faces.new((a[j], a[k], b[k], b[j]))
    if caps[0]:
        bm.faces.new(vr[0])
    if caps[1]:
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    print("PART", name, "loft", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    return _finish(name, bm, material, parent)


def dome(name, base, axis, rx, ry, h, material, parent, sides=8, phase=0.5, fwd=(0, -1, 0), keel=0.0, lip=0.0):
    """Calota fechada (ombreira, cotoveleira, joelheira) assentada em base, crescendo ao longo de axis."""
    ax = Vector(axis).normalized()
    base = Vector(base)
    secs = []
    if lip:
        secs.append(sec(base - ax * lip, rx * 0.93, ry * 0.93))
    for t, f in ((0.0, 1.0), (0.45, 0.89), (0.78, 0.63), (1.0, 0.3)):
        secs.append(sec(base + ax * (h * t), rx * f, ry * f, keel=keel * (1 - t)))
    return loft(name, secs, material, parent, sides=sides, phase=phase, axis=ax, fwd=fwd)


def join_objs(name, objs):
    """Junta malhas (podem ter pivôs/materiais diferentes) num objeto; fica no pivô da primeira."""
    objs = [o for o in objs if o is not None]
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                       selected_editable_objects=objs):
            bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]
    return objs[0]


# ------------------------------------------------------------------ proporções e rig
def body_proportions(height=1.84, heads=7.5, shoulders=1.0, chest=1.0, waist=1.0, hips=1.0, limbs=1.0,
                     hands=1.0, feet=1.0):
    """Marcos do corpo (lado esquerdo, x > 0). Alturas do tronco em 'cabeças a partir do topo';
    pernas em fração da altura do quadril (funciona também para 5-6 cabeças)."""
    H = height / heads
    k = height / REF_HEIGHT

    def z(n):
        return height - n * H

    hip_z = z(3.63)
    P = dict(H=H, k=k, z=z, height=height, sh=shoulders, ch=chest, wa=waist, hp=hips, lb=limbs, hd=hands * k,
             ft=feet * k)
    sx = 0.1685 * k * shoulders
    P["neck"] = Vector((0, 0, z(1.43)))
    P["shoulder"] = Vector((sx, 0.004 * k, z(1.70)))
    # braços levemente abertos: o antebraço passa longe da cintura e a mão longe do quadril
    P["elbow"] = Vector((sx + 0.03 * k, 0.016 * k, z(2.87)))
    P["wrist"] = Vector((sx + 0.056 * k, -0.004 * k, z(3.78)))
    P["pelvis"] = Vector((0, 0, hip_z))
    P["hip"] = Vector((0.1 * k * hips, 0, hip_z))
    P["knee"] = Vector((0.095 * k * hips, -0.005 * k, hip_z * 0.544))
    P["ankle"] = Vector((0.097 * k * hips, 0, hip_z * 0.0925))
    return P


def mirror(v, s):
    return Vector((v.x * s, v.y, v.z))


def humanoid_rig(root_name, P):
    """Empty raiz + pivôs: LegL/LegR (quadril) > KneeL/KneeR > AnkleL/AnkleR, Body (quadril) > Head (pescoço),
    ArmL/ArmR (ombro) > ElbowL/ElbowR. A posição de cada empty é a articulação."""
    R = {"root": empty(root_name, (0, 0, 0))}
    for n, s in (("L", 1), ("R", -1)):
        R["Leg" + n] = empty("Leg" + n, mirror(P["hip"], s), R["root"])
        R["Knee" + n] = empty("Knee" + n, mirror(P["knee"], s), R["Leg" + n])
        R["Ankle" + n] = empty("Ankle" + n, mirror(P["ankle"], s), R["Knee" + n])
    R["Body"] = empty("Body", P["pelvis"], R["root"])
    R["Head"] = empty("Head", P["neck"], R["Body"])
    for n, s in (("R", -1), ("L", 1)):
        R["Arm" + n] = empty("Arm" + n, mirror(P["shoulder"], s), R["Body"])
        R["Elbow" + n] = empty("Elbow" + n, mirror(P["elbow"], s), R["Arm" + n])
    return R


def _along(a, b, rows, k):
    """rows = [(t, rx, ry, extras...)] ao longo do segmento a->b (t pode passar de 0..1)."""
    out = []
    for r in rows:
        t, rx, ry = r[0], r[1], r[2]
        ex = r[3] if len(r) > 3 else {}
        out.append(sec(a.lerp(b, t), rx * k, ry * k, **ex))
    return out


def limb_sections(P, s):
    """Seções dos membros do lado s (+1 = esquerdo, -1 = direito)."""
    k, lb = P["k"], P["lb"]
    hip, knee, ankle = (mirror(P[n], s) for n in ("hip", "knee", "ankle"))
    sh, el, wr = (mirror(P[n], s) for n in ("shoulder", "elbow", "wrist"))
    S = {}
    # coxa cheia em cima (quadríceps na frente), afina até o joelho
    S["thigh"] = _along(hip, knee, [(-0.1, 0.09, 0.094), (0.12, 0.092, 0.096, {"fr": 1.08}), (0.45, 0.079, 0.083, {"fr": 1.06}),
                                    (0.8, 0.063, 0.066), (1.0, 0.055, 0.058)], k * lb)
    # canela: panturrilha saltada atrás no terço de cima, tornozelo fino
    S["shin"] = _along(knee, ankle, [(-0.04, 0.055, 0.058), (0.22, 0.056, 0.062, {"bk": 1.3}),
                                     (0.5, 0.047, 0.05, {"bk": 1.15}), (0.83, 0.035, 0.037), (1.0, 0.033, 0.035)],
                       k * lb)
    ft = P["ft"]
    S["foot"] = [sec((ankle.x, dy * ft, dz * ft), rx * ft, ry * ft, sq=3.0)
                 for dy, dz, rx, ry in ((0.05, 0.05, 0.042, 0.045), (0.0, 0.065, 0.048, 0.06),
                                        (-0.07, 0.05, 0.052, 0.045), (-0.14, 0.035, 0.054, 0.032),
                                        (-0.2, 0.03, 0.042, 0.025))]
    # braço: entra no deltoide (que fecha o ombro), bíceps saltado na frente, estreita no cotovelo
    # o topo fecha arredondado (deltoide), mais largo que o resto do braço e cobrindo a junção com o tronco
    S["upper"] = _along(sh, el, [(-0.09, 0.022, 0.026), (-0.06, 0.047, 0.051), (0.0, 0.058, 0.061),
                                 (0.16, 0.055, 0.058), (0.3, 0.049, 0.054, {"fr": 1.1}), (0.5, 0.047, 0.053, {"fr": 1.12}),
                                 (0.78, 0.042, 0.046), (1.0, 0.039, 0.042)], k * lb)
    # antebraço: massa logo abaixo do cotovelo, afina até o pulso (achatado)
    S["fore"] = _along(el, wr, [(-0.03, 0.04, 0.043), (0.2, 0.046, 0.046, {"bk": 1.1}), (0.6, 0.037, 0.034),
                                (1.0, 0.03, 0.024)], k * lb)
    return S


def torso_sections(P):
    """Tronco do gancho à base do pescoço (anéis horizontais). Forma em V: peito e dorsais largos, cintura
    fina, quadril um pouco mais estreito que o peito; em cima o trapézio desce em rampa do pescoço ao ombro
    (o topo do tronco não é reto) e termina num anel do tamanho do pescoço."""
    z, k = P["z"], P["k"]
    rows = (  # (cabeças do topo, rx, ry, extras, fator de largura)
        (3.78, 0.1, 0.08, {}, P["hp"]),
        (3.62, 0.16, 0.11, {"bk": 1.12}, P["hp"]),
        (3.3, 0.155, 0.103, {}, P["hp"]),
        (2.85, 0.138, 0.098, {}, P["wa"]),
        (2.45, 0.155, 0.108, {"fr": 1.06}, P["ch"]),
        (2.12, 0.172, 0.115, {"fr": 1.14}, P["ch"]),
        (1.88, 0.178, 0.108, {"fr": 1.08}, P["sh"]),
        (1.66, 0.158, 0.088, {}, P["sh"]),
        (1.5, 0.108, 0.07, {}, 1.0),
        (1.38, 0.068, 0.062, {}, 1.0),
    )
    return [sec((0, 0, z(n)), rx * k * f, ry * k, **ex) for n, rx, ry, ex, f in rows]


# ------------------------------------------------------------------ mãos
def fist(prefix, P, s, material, parent):
    """Mão fechada em punho (luva de placas): dorso e palma num bloco, quatro dedos curvados em volta de um
    eixo ao longo de Y (o cabo da espada passa por ali), em gomos com degrau nas juntas, fileira de nós dos
    dedos e o polegar fechando por cima do indicador. Devolve <prefix>_Hand (tudo junto, um material)."""
    hd = P["hd"]
    W = mirror(P["wrist"], s)
    o = Vector((s, 0, 0))                       # lado de fora (dorso da mão)
    up = Vector((0, 0, 1))
    G = W + Vector((-s * 0.004, 0, -0.064 * hd))  # eixo do punho fechado (= cabo da espada)
    parts = [loft(prefix + "_Hand", [
        sec(W + Vector((0, 0, 0.005 * hd)), 0.03 * hd, 0.036 * hd),
        sec(W + Vector((s * 0.002, -0.002 * hd, -0.026 * hd)), 0.036 * hd, 0.048 * hd, sq=2.6),
        sec(G + Vector((-s * 0.002 * hd, -0.003 * hd, 0.016 * hd)), 0.038 * hd, 0.052 * hd, sq=3.0),
    ], material, parent, sides=8, axis=(0, 0, 1), chamfer=(0.0, 0.006))]
    # miolo do punho fechado (preenche o vão quando a mão está vazia; o cabo da espada passa por dentro)
    parts.append(loft(prefix + "_Core", [sec(G + Vector((0, -0.044 * hd, 0)), 0.02 * hd, 0.02 * hd),
                                         sec(G + Vector((0, 0.042 * hd, 0.002 * hd)), 0.018 * hd, 0.018 * hd)],
                      material, parent, sides=6, fwd=(0, 0, 1)))
    # dedos: do indicador (frente, -Y) ao mindinho, cada um um arco em volta de G no plano XZ
    for i, (dy, r, w, dz) in enumerate(((-0.037, 0.028, 0.0125, -0.003), (-0.012, 0.029, 0.0125, 0.0),
                                        (0.013, 0.028, 0.012, 0.0), (0.036, 0.025, 0.0105, 0.004))):
        c = G + Vector((0, dy * hd, dz * hd))
        pts = [c + (o * math.cos(t) + up * math.sin(t)) * r * hd
               for t in (math.radians(a) for a in (55, 10, -40, -95, -145, -185))]
        secs = [sec(p, w * hd * 0.95, w * hd, sq=2.6) for p in pts]
        secs[-1] = dict(secs[-1], rx=secs[-1]["rx"] * 0.8, ry=secs[-1]["ry"] * 0.85)
        parts.append(loft(prefix + "_Finger%d" % i, stepped(secs, (0.34, 0.66), drop=0.86, eps=0.004),
                          material, parent, sides=6, phase=0.5, chamfer=(0.0, 0.003)))
    # nós dos dedos: placa articulada em cima da fileira de dedos, do lado de fora
    k = G + o * 0.026 * hd + up * 0.03 * hd
    parts.append(tbox(prefix + "_Knuckles", (k.x, k.y - 0.0005, k.z), (0.018 * hd, 0.088 * hd, 0.02 * hd), material,
                      top=(0.8, 0.94), bevel=0.004, rot=(0, -s * 0.5, 0), parent=parent))
    # polegar: sai da palma (lado de dentro, frente) e fecha por cima do indicador
    t0 = W + Vector((-s * 0.024 * hd, -0.036 * hd, -0.026 * hd))
    t1 = G + Vector((-s * 0.03 * hd, -0.058 * hd, 0.0))
    t2 = G + Vector((s * 0.004 * hd, -0.06 * hd, -0.016 * hd))
    parts.append(loft(prefix + "_Thumb", stepped([sec(t0, 0.016 * hd, 0.016 * hd), sec(t1, 0.014 * hd, 0.0135 * hd),
                                                  sec(t2, 0.011 * hd, 0.011 * hd)], (0.55,), drop=0.86, eps=0.004),
                      material, parent, sides=6, fwd=(0, 0, 1), chamfer=(0.0, 0.003)))
    return join_objs(prefix + "_Hand", parts)


# ------------------------------------------------------------------ pescoço
def neck_mesh(P, material, parent, k=1.0):
    """Pescoço curto e grosso (~70% da largura da cabeça), levemente inclinado para a frente: nasce dentro do
    trapézio e entra por baixo do queixo."""
    z, kk = P["z"], P["k"] * k
    return loft("Neck", [sec((0, 0.014 * kk, z(1.58)), 0.07 * kk, 0.066 * kk),
                         sec((0, 0.006 * kk, z(1.3)), 0.06 * kk, 0.058 * kk),
                         sec((0, -0.002 * kk, z(0.95)), 0.054 * kk, 0.052 * kk)], material, parent, sides=8)


# ------------------------------------------------------------------ corpo-base completo
BASE_PARTS = ("torso", "neck", "thigh", "shin", "foot", "upper", "fore", "hand")


def humanoid_base(P, R, mats, parts=BASE_PARTS):
    """Constrói o corpo-base nos pivôs de R. mats: {"skin": mat, "<parte>": mat opcional por parte}.
    Nomes: Chest, Neck, LegX_Thigh/_Shin/_Foot, ArmX_Upper/_Fore/_Hand."""
    def m(p):
        return mats.get(p, mats["skin"])

    out = {}
    if "torso" in parts:
        out["Chest"] = loft("Chest", torso_sections(P), m("torso"), R["Body"], sides=12, phase=0, axis=(0, 0, 1))
    if "neck" in parts:
        z, k = P["z"], P["k"]
        out["Neck"] = neck_mesh(P, m("neck"), R["Head"])
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        leg, knee, arm, elbow = R["Leg" + n], R["Knee" + n], R["Arm" + n], R["Elbow" + n]
        if "thigh" in parts:
            out["Leg%s_Thigh" % n] = loft("Leg%s_Thigh" % n, S["thigh"], m("thigh"), leg)
        if "shin" in parts:
            out["Leg%s_Shin" % n] = loft("Leg%s_Shin" % n, S["shin"], m("shin"), knee)
        if "foot" in parts:
            out["Leg%s_Foot" % n] = loft("Leg%s_Foot" % n, S["foot"], m("foot"), R["Ankle" + n], fwd=(0, 0, 1),
                                         chamfer=(0.01, 0.012))
        if "upper" in parts:
            out["Arm%s_Upper" % n] = loft("Arm%s_Upper" % n, S["upper"], m("upper"), arm)
        if "fore" in parts:
            out["Arm%s_Fore" % n] = loft("Arm%s_Fore" % n, S["fore"], m("fore"), elbow)
        if "hand" in parts:
            out["Arm%s_Hand" % n] = fist("Arm" + n, P, s, m("hand"), elbow)
    return out
