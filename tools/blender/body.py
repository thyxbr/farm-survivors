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
    sx = 0.22 * k * shoulders
    P["neck"] = Vector((0, 0, z(1.43)))
    P["shoulder"] = Vector((sx, 0, z(1.70)))
    P["elbow"] = Vector((sx + 0.028 * k, 0.01 * k, z(2.95)))
    P["wrist"] = Vector((sx + 0.045 * k, -0.005 * k, z(3.78)))
    P["pelvis"] = Vector((0, 0, hip_z))
    P["hip"] = Vector((0.1 * k * hips, 0, hip_z))
    P["knee"] = Vector((0.095 * k * hips, -0.005 * k, hip_z * 0.544))
    P["ankle"] = Vector((0.097 * k * hips, 0, hip_z * 0.0925))
    return P


def mirror(v, s):
    return Vector((v.x * s, v.y, v.z))


def humanoid_rig(root_name, P):
    """Empty raiz + pivôs: LegL/LegR (quadril) > KneeL/KneeR, Body (quadril) > Head (pescoço),
    ArmL/ArmR (ombro) > ElbowL/ElbowR. A posição de cada empty é a articulação."""
    R = {"root": empty(root_name, (0, 0, 0))}
    for n, s in (("L", 1), ("R", -1)):
        R["Leg" + n] = empty("Leg" + n, mirror(P["hip"], s), R["root"])
        R["Knee" + n] = empty("Knee" + n, mirror(P["knee"], s), R["Leg" + n])
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
    S["thigh"] = _along(hip, knee, [(-0.1, 0.088, 0.09), (0.12, 0.09, 0.092, {"fr": 1.05}), (0.45, 0.077, 0.08),
                                    (0.8, 0.062, 0.064), (1.0, 0.055, 0.058)], k * lb)
    S["shin"] = _along(knee, ankle, [(-0.04, 0.055, 0.058), (0.2, 0.056, 0.06, {"bk": 1.25}),
                                     (0.47, 0.049, 0.05, {"bk": 1.15}), (0.83, 0.036, 0.038), (1.0, 0.034, 0.036)],
                       k * lb)
    ft = P["ft"]
    S["foot"] = [sec((ankle.x, dy * ft, dz * ft), rx * ft, ry * ft, sq=3.0)
                 for dy, dz, rx, ry in ((0.05, 0.05, 0.042, 0.045), (0.0, 0.065, 0.048, 0.06),
                                        (-0.07, 0.05, 0.052, 0.045), (-0.14, 0.035, 0.054, 0.032),
                                        (-0.2, 0.03, 0.042, 0.025))]
    S["upper"] = _along(sh, el, [(-0.13, 0.06, 0.065), (0.3, 0.058, 0.06), (0.75, 0.048, 0.05), (1.0, 0.042, 0.044)],
                        k * lb)
    S["fore"] = _along(el, wr, [(-0.03, 0.042, 0.044), (0.25, 0.046, 0.05), (0.7, 0.036, 0.04), (1.0, 0.03, 0.036)],
                       k * lb)
    return S


def torso_sections(P):
    """Tronco do gancho à base do pescoço (anéis horizontais)."""
    z, k = P["z"], P["k"]
    rows = (  # (cabeças do topo, rx, ry, extras, fator de largura)
        (3.78, 0.1, 0.08, {}, P["hp"]),
        (3.62, 0.16, 0.11, {}, P["hp"]),
        (3.3, 0.16, 0.105, {}, P["hp"]),
        (2.85, 0.14, 0.1, {}, P["wa"]),
        (2.4, 0.165, 0.115, {"fr": 1.1}, P["ch"]),
        (2.05, 0.18, 0.12, {"fr": 1.15}, P["ch"]),
        (1.72, 0.17, 0.1, {}, P["sh"]),
        (1.52, 0.08, 0.07, {}, 1.0),
    )
    return [sec((0, 0, z(n)), rx * k * f, ry * k, **ex) for n, rx, ry, ex, f in rows]


# ------------------------------------------------------------------ mãos
def fist(prefix, P, s, material, parent):
    """Mão fechada: dorso facetado, quatro dedos dobrados sugeridos por blocos e o polegar por cima.
    Devolve o objeto <prefix>_Hand (tudo junto, um material)."""
    hd = P["hd"]
    W = mirror(P["wrist"], s)
    parts = [loft(prefix + "_Hand", [
        sec(W + Vector((0, 0, 0.005 * hd)), 0.03 * hd, 0.036 * hd),
        sec(W + Vector((s * 0.002, 0, -0.03 * hd)), 0.037 * hd, 0.05 * hd, sq=2.6),
        sec(W + Vector((s * 0.004, -0.002, -0.064 * hd)), 0.04 * hd, 0.055 * hd, sq=3.0),
        sec(W + Vector((s * 0.002, -0.002, -0.08 * hd)), 0.036 * hd, 0.05 * hd, sq=3.0),
    ], material, parent, sides=8, axis=(0, 0, 1), chamfer=(0.0, 0.01))]
    # dedos dobrados: quatro rolos sob a palma, do indicador (frente) ao mindinho, levemente em leque
    for i in range(4):
        y = (-0.036 + i * 0.024) * hd
        parts.append(tbox(prefix + "_Finger%d" % i, (W.x - s * 0.008 * hd, W.y + y, W.z - (0.086 - 0.002 * i) * hd),
                          (0.066 * hd, 0.021 * hd, 0.03 * hd), material, bottom=(0.85, 0.9), bevel=0.006,
                          rot=(0, s * 0.18, 0), parent=parent))
    parts.append(tbox(prefix + "_Thumb", (W.x - s * 0.02 * hd, W.y - 0.05 * hd, W.z - 0.055 * hd),
                      (0.026 * hd, 0.028 * hd, 0.052 * hd), material, bottom=(0.8, 0.8), bevel=0.008,
                      rot=(0.35, 0, -s * 0.3), parent=parent))
    return join_objs(prefix + "_Hand", parts)


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
        out["Neck"] = loft("Neck", [sec((0, 0.005, z(1.55)), 0.06 * k, 0.058 * k),
                                    sec((0, 0.012, z(1.05)), 0.052 * k, 0.05 * k)], m("neck"), R["Head"], sides=8)
    for n, s in (("L", 1), ("R", -1)):
        S = limb_sections(P, s)
        leg, knee, arm, elbow = R["Leg" + n], R["Knee" + n], R["Arm" + n], R["Elbow" + n]
        if "thigh" in parts:
            out["Leg%s_Thigh" % n] = loft("Leg%s_Thigh" % n, S["thigh"], m("thigh"), leg)
        if "shin" in parts:
            out["Leg%s_Shin" % n] = loft("Leg%s_Shin" % n, S["shin"], m("shin"), knee)
        if "foot" in parts:
            out["Leg%s_Foot" % n] = loft("Leg%s_Foot" % n, S["foot"], m("foot"), knee, fwd=(0, 0, 1),
                                         chamfer=(0.01, 0.012))
        if "upper" in parts:
            out["Arm%s_Upper" % n] = loft("Arm%s_Upper" % n, S["upper"], m("upper"), arm)
        if "fore" in parts:
            out["Arm%s_Fore" % n] = loft("Arm%s_Fore" % n, S["fore"], m("fore"), elbow)
        if "hand" in parts:
            out["Arm%s_Hand" % n] = fist("Arm" + n, P, s, m("hand"), elbow)
    return out
