"""Brejeiro gerado por IA local (monstro do Pântano, docs/EQUIPAMENTO_POR_IA.md, seção Monstros).

  blender -b --factory-startup --python tools/blender/brejeiro_ia_build.py -- [pintado.glb] [pasta_previa]

Entrada: a malha pintada pela IA (D:/ia3d/saida/brejeiro/pintura/pintado.glb, folha de três vistas do usuário).
Saída: assets/models/brejeiro_ia.glb com os pivôs do goblin (LegL/LegR e Body na raiz; Head, ArmL/ArmR dentro do
Body; ElbowL/ElbowR dentro dos braços), um esqueleto com um osso `<pivô>_skin` por pivô e a malha com pele. No jogo
o PivotSkin faz cada osso seguir o seu pivô e a animação é a do goblin (EnemyPose: golpe, arco, cajado).

Uma malha só para os três papéis: a IA faz o corpo de mãos vazias e as armas são peças rígidas feitas aqui, como no
goblin de código (`Opt_<Nome>`, EnemyGear deixa só as do `gear` do tipo):
- Opt_Club (batedor): clava de raiz com nós, na mão direita, apontando para a frente;
- Opt_Bow e Opt_Quiver (arqueiro): arco de junco na mão esquerda e aljava de folha trançada nas costas;
- Opt_Staff e Opt_Mask (xamã): cajado de galho com gema verde na mão direita e uma coroa de casca com galhos.
Peça fina (corda, cabo) a IA faz mal; por isso as armas são por código.

Pesos por regra, cada uma com limite no eixo do membro:
- braço: raio em volta da linha ombro-cotovelo-punho-mão (abaixo do ombro e fora do tronco em x); o antebraço e a mão
  inteira no ElbowX, com mistura pela altura ao longo do eixo no cotovelo;
- perna: a coluna da perna abaixo da virilha (|x| 0,03..0,28), misturando com o Body entre z 0,30 e 0,42; o pé inteiro
  (abaixo de z 0,1) vai na perna; as abas da tanga (frente e trás, |x| < 0,1) ficam no Body;
- cabeça: acima do pescoço (mistura z 0,93..1,03);
- o resto (tronco, capa de folhas, cinto) fica no Body.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if ARGS else os.path.join(os.environ.get("IA3D", "D:/ia3d"), "saida/brejeiro/pintura/pintado.glb")
PREVIA = ARGS[1] if len(ARGS) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/models/brejeiro_ia.glb")

HEIGHT = 1.3       # da sola ao alto dos olhos (como o goblin; o jogo ainda multiplica pela escala do tipo)
FACES = 8000       # malha do jogo (a IA entrega 40 mil); 16 brejeiros no Pântano
TEX = 1024

# ---------------------------------------------------------------- pivôs, medidos na malha normalizada
# frente = -Y, esquerda = +X. Mapa de ocupação por faixa de z e centro do braço a cada 3 cm (|x| > 0,28).
BODY = Vector((0, 0.02, 0.40))      # na altura do quadril, como o goblin
HIP = Vector((0.15, 0.02, 0.40))    # coluna da perna: centro |x| 0,16, y 0,03; virilha em z 0,30
HEAD = Vector((0, 0.0, 0.95))       # pescoço: a frente recua até y -0,18 em z 0,95
# braço: entra no tronco sob a capa (z 0,78); centro em |x| 0,36 de z 0,74 a 0,62, 0,39 em z 0,5; a faixa do
# antebraço (z 0,44..0,56); a mão aberta de z 0,25 a 0,41, |x| 0,37..0,52, y -0,17..0,02
SHOULDER = Vector((0.28, 0.05, 0.78))
ELBOW = Vector((0.37, 0.03, 0.60))
WRIST = Vector((0.405, -0.05, 0.43))
HAND_TIP = Vector((0.45, -0.08, 0.25))
GRIP = Vector((0.44, -0.075, 0.33))  # onde a arma passa (meio da palma); EnemyPose lê a mão daqui (Opt_*)


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def mirror(v, s):
    return Vector((v.x * s, v.y, v.z))


def seg(p, a, b):
    """Distância de p ao segmento a-b e o parâmetro t (0..1)."""
    d = b - a
    t = max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))
    return (p - (a + d * t)).length, t


bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
ob = next(o for o in scn.objects if o.type == 'MESH')
for o in list(scn.objects):
    if o is not ob:
        bpy.data.objects.remove(o)
me = ob.data
me.transform(ob.matrix_world)
ob.matrix_world = Matrix.Identity(4)
ob.parent = None

# ---------------------------------------------------------------- normaliza: altura HEIGHT, sola em z 0, centro em x e y
zs = [v.co.z for v in me.vertices]
me.transform(Matrix.Scale(HEIGHT / (max(zs) - min(zs)), 4) @ Matrix.Translation((0, 0, -min(zs))))
P = [v.co for v in me.vertices]
cx = (min(p.x for p in P) + max(p.x for p in P)) / 2
cy = (min(p.y for p in P) + max(p.y for p in P)) / 2
me.transform(Matrix.Translation((-cx, -cy, 0)))

bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-6)
bpy.ops.object.mode_set(mode='OBJECT')
antes = len(me.polygons)
mod = ob.modifiers.new("dec", "DECIMATE")
mod.ratio = min(1.0, FACES / len(me.polygons))
mod.delimit = {'UV'}
bpy.ops.object.modifier_apply(modifier="dec")
print("MALHA %d -> %d faces" % (antes, len(me.polygons)))

img = next((i for i in bpy.data.images if i.size[0] > 0), None)
if img:
    img.scale(TEX, TEX)
    img.name = "brejeiro_ia_albedo"
me.materials.clear()
paint = bpy.data.materials.new("bjia_paint_flat")     # _flat: a luz já vem pintada, o toon não soma sombra de forma
paint.use_nodes = True
bsdf = next(nd for nd in paint.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
if img:
    tx = paint.node_tree.nodes.new("ShaderNodeTexImage")
    tx.image = img
    paint.node_tree.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.85
me.materials.append(paint)
for a in list(me.color_attributes):
    me.color_attributes.remove(a)
for p in me.polygons:
    p.use_smooth = True
ob.name = me.name = "BrejeiroIA"


# ---------------------------------------------------------------- pintura: o lado de dentro da canela
# A IA pinta pelas três vistas; o lado de dentro das pernas não aparece em nenhuma e veio com manchas quase pretas, que
# o andar mostra na perna de trás. Os texels escuros das faces de dentro da perna (entre as pernas, abaixo da virilha)
# viram o verde médio da própria perna.
def fix_inner_legs():
    import numpy as np
    if not img:
        return
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    lum = px[..., :3] @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    uv = me.uv_layers.active.data
    BAND = 0.02

    def face_mask(p):
        pts = [uv[li].uv for li in p.loop_indices]
        xs = [q.x * (w - 1) for q in pts]
        ys = [q.y * (h - 1) for q in pts]
        x0, x1 = int(max(0, min(xs) - 1)), int(min(w - 1, max(xs) + 1))
        y0, y1 = int(max(0, min(ys) - 1)), int(min(h - 1, max(ys) + 1))
        if (x1 - x0) * (y1 - y0) > 4000:      # face cortada na costura do UV: pula
            return None
        m = np.zeros((y1 - y0 + 1, x1 - x0 + 1), dtype=bool)
        gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        gx = gx + 0.5
        gy = gy + 0.5
        for k in range(1, len(pts) - 1):      # leque de triângulos: só os texels dentro da face (o UV tem ilhas vizinhas)
            (ax_, ay_), (bx_, by_), (cx_, cy_) = (xs[0], ys[0]), (xs[k], ys[k]), (xs[k + 1], ys[k + 1])
            d = (by_ - cy_) * (ax_ - cx_) + (cx_ - bx_) * (ay_ - cy_)
            if abs(d) < 1e-9:
                continue
            l1 = ((by_ - cy_) * (gx - cx_) + (cx_ - bx_) * (gy - cy_)) / d
            l2 = ((cy_ - ay_) * (gx - cx_) + (ax_ - cx_) * (gy - cy_)) / d
            m |= (l1 >= -0.15) & (l2 >= -0.15) & (1 - l1 - l2 >= -0.15)
        return (slice(y0, y1 + 1), slice(x0, x1 + 1)), m

    # cor de cada altura pelo lado de fora da perna (pele ou faixa), que a IA pintou bem
    outer = {}
    inner = []
    for p in me.polygons:
        c = p.center
        sg = 1 if c.x > 0 else -1
        if not (0.04 < c.z < 0.31 and 0.03 < abs(c.x) < 0.30):
            continue
        nx = p.normal.x * sg
        fm = face_mask(p)
        if fm is None:
            continue
        if nx > 0.5:
            sl, m = fm
            outer.setdefault(int(c.z / BAND), []).append(px[sl][m][:, :3])
        elif nx < -0.2 and abs(c.x) < 0.165:   # só as faces viradas para a outra perna
            inner.append((int(c.z / BAND), fm))
    ref = {}
    for k, lst in outer.items():
        a = np.concatenate(lst)
        l = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        ref[k] = np.median(a[l > np.percentile(l, 30)], axis=0)
    allc = np.median(np.array(list(ref.values())), axis=0)
    n = 0
    for k, ((sy, sx), m) in inner:
        base = ref.get(k, ref.get(k - 1, ref.get(k + 1, allc)))
        lb = float(base @ np.array([0.299, 0.587, 0.114], dtype=np.float32))
        sub = px[sy, sx]
        dark = m & (lum[sy, sx] < 0.6 * lb)
        sub[dark, :3] = base
        n += int(dark.sum())
    img.pixels.foreach_set(px.ravel())
    img.pack()
    print("CANELA %d faces de dentro, %d texels escuros trocados pela cor de fora na mesma altura" % (len(inner), n))


fix_inner_legs()


# ---------------------------------------------------------------- pivôs (empties), hierarquia do goblin
def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    scn.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation
    else:
        e.location = loc
    bpy.context.view_layer.update()
    return e


root = empty("Brejeiro", (0, 0, 0))
piv = {}
for s, sd in ((1, "L"), (-1, "R")):
    piv["Leg" + sd] = empty("Leg" + sd, mirror(HIP, s), root)
piv["Body"] = empty("Body", BODY, root)
piv["Head"] = empty("Head", HEAD, piv["Body"])
for s, sd in ((1, "L"), (-1, "R")):
    piv["Arm" + sd] = empty("Arm" + sd, mirror(SHOULDER, s), piv["Body"])
    piv["Elbow" + sd] = empty("Elbow" + sd, mirror(ELBOW, s), piv["Arm" + sd])

# ---------------------------------------------------------------- esqueleto: um osso por pivô, a cabeça do osso no pivô
arm = bpy.data.armatures.new("BrejeiroIA_Rig")
rig = bpy.data.objects.new("BrejeiroIA_Rig", arm)
scn.collection.objects.link(rig)
rig.parent = root
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
BONES = {"Body": (None, BODY, BODY + Vector((0, 0, 0.3))),
         "Head": ("Body", HEAD, HEAD + Vector((0, 0, 0.25)))}
for s, sd in ((1, "L"), (-1, "R")):
    BONES["Leg" + sd] = (None, mirror(HIP, s), mirror(HIP, s) - Vector((0, 0, 0.35)))
    BONES["Arm" + sd] = ("Body", mirror(SHOULDER, s), mirror(ELBOW, s))
    BONES["Elbow" + sd] = ("Arm" + sd, mirror(ELBOW, s), mirror(WRIST, s))
SK = "_skin"     # osso "<pivô>_skin": o PivotSkin tira o sufixo (com o mesmo nome do pivô o Godot renomeia o osso)
for name, (par, h, t) in BONES.items():
    b = arm.edit_bones.new(name + SK)
    b.head, b.tail = h, t
for name, (par, h, t) in BONES.items():
    if par:
        arm.edit_bones[name + SK].parent = arm.edit_bones[par + SK]
bpy.ops.object.mode_set(mode='OBJECT')

# normal do plano do cotovelo: a mistura braço/antebraço é pela altura ao longo do eixo, não pela distância ao ponto
EL_N = ((ELBOW - SHOULDER).normalized() + (WRIST - ELBOW).normalized()).normalized()


# ---------------------------------------------------------------- pesos por regra
def weights(co):
    s = 1 if co.x > 0 else -1
    sd = "L" if s > 0 else "R"
    ax = co.x * s       # distância ao meio, do lado do ponto
    c = mirror(co, s)   # o ponto espelhado para o lado esquerdo (as medidas são do lado +x)
    # braço: raio em volta da linha ombro-cotovelo-punho-mão; a mão é mais larga (até 0,1 do eixo)
    r = min(seg(c, SHOULDER, ELBOW)[0], seg(c, ELBOW, WRIST)[0], seg(c, WRIST, HAND_TIP)[0])
    rmax = 0.115 if c.z < 0.45 else 0.10
    arm_w = (1 - smooth(rmax - 0.015, rmax + 0.01, r)) * smooth(0.22, 0.27, ax)
    # perto do ombro a pele passa para o Body (a capa de folhas por cima fica no Body)
    along = (c - SHOULDER).dot((ELBOW - SHOULDER).normalized())
    arm_w *= smooth(0.0, 0.08, along)
    # abaixo do ombro o braço pende longe do tronco (o tronco vai até |x| 0,25): tudo fora dele é braço, para que os
    # dedos e o polegar, fora do raio, não fiquem no Body e rasguem
    if 0.2 < c.z < 0.62:     # a mão acaba em z 0,25; abaixo disso é o pé (que também chega a |x| 0,3)
        arm_w = max(arm_w, smooth(0.255, 0.285, ax))
    # perna: coluna abaixo da virilha; o pé inteiro
    leg_w = (1 - smooth(0.30, 0.42, co.z)) * smooth(0.03, 0.06, ax) * (1 - smooth(0.26, 0.30, ax))
    if co.z < 0.10 and ax > 0.03:
        leg_w = 1.0
    # abas da tanga (frente e trás, entre as pernas) ficam no Body
    if co.z > 0.18 and ax < 0.11 and (co.y < -0.10 or co.y > 0.12):
        leg_w *= smooth(0.08, 0.11, ax)
    if arm_w > 0 and leg_w > 0:      # nunca braço e perna no mesmo vértice (a mão pende na altura da coxa)
        if arm_w >= leg_w:
            leg_w = 0.0
        else:
            arm_w = 0.0
    head_w = smooth(0.93, 1.03, co.z) * (1 - arm_w)
    W = {}
    if arm_w > 0:
        h = (c - ELBOW).dot(EL_N)
        fore = smooth(-0.045, 0.045, h)
        W["Arm" + sd] = arm_w * (1 - fore)
        W["Elbow" + sd] = arm_w * fore
    if leg_w > 0:
        W["Leg" + sd] = leg_w
    if head_w > 0:
        W["Head"] = head_w
    body = 1.0 - arm_w - leg_w - head_w
    if body > 0:
        W["Body"] = body
    return {k: w for k, w in W.items() if w > 1e-4}


ob.parent = rig
md = ob.modifiers.new("rig", "ARMATURE")
md.object = rig
groups = {name: ob.vertex_groups.new(name=name + SK) for name in BONES}
for v in me.vertices:
    W = weights(v.co)
    tot = sum(W.values()) or 1.0
    for k, w in W.items():
        groups[k].add([v.index], w / tot, 'REPLACE')

# ---------------------------------------------------------------- conferência: combinação de grupos por vértice
# (a cor do osso dominante esconde mistura): Body + um membro, ossos do mesmo braço, ou Body + Head
gi = {g.index: g.name[:-len(SK)] for g in ob.vertex_groups}
combos, ERRADO = {}, 0
for v in me.vertices:
    names = tuple(sorted(gi[g.group] for g in v.groups if g.weight > 0.05))
    combos[names] = combos.get(names, 0) + 1
for names, n in sorted(combos.items(), key=lambda kv: -kv[1]):
    limbs = {nm for nm in names if nm != "Body"}
    fams = {("A" if nm[:3] in ("Arm", "Elb") else nm[:3]) + nm[-1] if nm != "Head" else "Head" for nm in limbs}
    bad = len(fams) > 1
    ERRADO += n if bad else 0
    print("GRUPOS %-30s %5d%s" % ("+".join(names), n, "  <- ERRO" if bad else ""))
print("GRUPOS errados: %d vértices" % ERRADO)

bm = bmesh.new()
bm.from_mesh(me)
seen, parts = set(), 0
for v in bm.verts:
    if v.index in seen:
        continue
    parts += 1
    stack = [v]
    while stack:
        u = stack.pop()
        if u.index in seen:
            continue
        seen.add(u.index)
        stack.extend(e.other_vert(u) for e in u.link_edges)
bm.free()
print("PEDACOS malha=%d (esperado 1)" % parts)


# ---------------------------------------------------------------- armas (peças rígidas, Opt_<Nome>)
def mat(name, hexs, rough=0.85, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(nd for nd in m.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
    h = hexs.lstrip("#")
    col = tuple(((int(h[i:i + 2], 16) / 255.0) ** 2.2) for i in (0, 2, 4)) + (1.0,)
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = col     # cor da prévia (workbench)
    if emit:
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = strength
    return m


WOOD = mat("bj_wood", "#6B4A2B")
WOOD_D = mat("bj_wood_d", "#45301B")
REED = mat("bj_reed", "#B3A85A")
REED_D = mat("bj_reed_d", "#6E6A2C")
STRING = mat("bj_string", "#DCD3AE")
LEAF = mat("bj_leaf", "#5E8A2E")
LEAF_D = mat("bj_leaf_d", "#3E6522")
BARK = mat("bj_bark", "#5A4330")
BONE = mat("bj_bone", "#E6DCC0")
GEM = mat("bj_gem", "#3DFF5A", 0.3, emit=True, strength=4.5)
WEAPON_PARTS = []


def _obj(name, bm_, mat_, parent):
    m = bpy.data.meshes.new(name)
    bm_.to_mesh(m)
    bm_.free()
    m.materials.append(mat_)
    for p in m.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, m)
    scn.collection.objects.link(o)
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()
    WEAPON_PARTS.append(o)
    return o


def tube(name, pts, radii, mat_, parent, sides=8, cap=True, flat=1.0):
    """Tubo liso por uma linha de pontos (coordenadas do modelo), raio por ponto; `flat` achata um eixo da seção."""
    pts = [Vector(p) for p in pts]
    bm_ = bmesh.new()
    rings = []
    prev_side = None
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = prev_side if prev_side is not None else (Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))
        a = d.cross(side).normalized()
        b = d.cross(a).normalized()
        prev_side = b
        ring = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            ring.append(bm_.verts.new(p + (a * math.cos(ang) * flat + b * math.sin(ang)) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm_.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    if cap:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            if all((v.co - ring[0].co).length < 1e-6 for v in ring):
                continue
            bm_.faces.new(list(reversed(ring)) if rev else ring)
    bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces)
    return _obj(name, bm_, mat_, parent)


def ball(name, c, r, mat_, parent, sc=(1, 1, 1)):
    bm_ = bmesh.new()
    bmesh.ops.create_uvsphere(bm_, u_segments=10, v_segments=7, radius=r)
    for v in bm_.verts:
        v.co = Vector((v.co.x * sc[0], v.co.y * sc[1], v.co.z * sc[2])) + Vector(c)
    return _obj(name, bm_, mat_, parent)


def gem(name, c, r, mat_, parent, tall=1.5):
    bm_ = bmesh.new()
    bmesh.ops.create_icosphere(bm_, subdivisions=1, radius=r)
    for v in bm_.verts:
        v.co = Vector((v.co.x, v.co.y, v.co.z * tall)) + Vector(c)
    o = _obj(name, bm_, mat_, parent)
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def leaf(name, base, tip, width, mat_, parent, bend=0.02):
    """Folha larga e grossa (volume, não lâmina): fuso achatado da base à ponta."""
    base, tip = Vector(base), Vector(tip)
    n = 6
    pts, rr = [], []
    up = Vector((0, 0, 1)) if abs((tip - base).normalized().z) < 0.9 else Vector((1, 0, 0))
    off = (tip - base).cross(up).normalized() * bend
    for i in range(n + 1):
        t = i / n
        pts.append(base.lerp(tip, t) + off * math.sin(math.pi * t))
        rr.append(width * max(0.08, math.sqrt(math.sin(math.pi * min(t * 0.9 + 0.08, 1.0)))))
    return tube(name, pts, rr, mat_, parent, sides=6, flat=0.28)


def opt(name, loc, parent):
    return empty("Opt_" + name, loc, parent)


hR = mirror(GRIP, -1)
hL = mirror(GRIP, 1)

# --- clava de raiz (batedor): cabo na mão direita apontando para a frente, a cabeça grossa e nodosa
o = opt("Club", hR, piv["ElbowR"])
x, y, z = hR
tube("Club", [(x, y + 0.08, z), (x, y - 0.06, z + 0.005), (x + 0.01, y - 0.22, z + 0.02), (x - 0.005, y - 0.36, z + 0.04),
              (x, y - 0.48, z + 0.05), (x, y - 0.53, z + 0.05)],
     [0.032, 0.034, 0.045, 0.072, 0.086, 0.04], WOOD, o, sides=9)
tube("ClubGrip", [(x, y + 0.07, z), (x, y - 0.07, z + 0.006)], [0.033, 0.033], REED_D, o, sides=9)
for k, (dx, dy, dz, r) in enumerate(((0.05, -0.40, 0.06, 0.035), (-0.05, -0.44, 0.03, 0.033), (0.0, -0.36, 0.1, 0.03),
                                     (0.01, -0.47, -0.01, 0.032), (-0.03, -0.30, 0.06, 0.025))):
    ball("ClubKnot%d" % k, (x + dx * 1.2, y + dy, z + dz * 1.2), r * 1.3, WOOD_D, o)
leaf("ClubLeaf", (x + 0.02, y - 0.25, z + 0.05), (x + 0.1, y - 0.3, z + 0.14), 0.035, LEAF, o)

# --- arco de junco (arqueiro): na mão esquerda, na vertical; as pontas curvam para trás (+Y), a corda por fora
o = opt("Bow", hL, piv["ElbowL"])
x, y, z = hL
bx = x + 0.075
H_BOW, BEND = 0.7, 0.15
pts = []
for i in range(9):
    t = i / 8 * 2 - 1
    pts.append((bx, y - 0.02 + BEND * t * t, z + t * H_BOW / 2))
tube("Bow", pts, [0.016, 0.021, 0.026, 0.029, 0.031, 0.029, 0.026, 0.021, 0.016], REED, o, sides=7)
for k, t in enumerate((-0.62, -0.3, 0.3, 0.62)):
    c = Vector((bx, y - 0.02 + BEND * t * t, z + t * H_BOW / 2))
    tube("BowNode%d" % k, [c - Vector((0, 0, 0.014)), c + Vector((0, 0, 0.014))], [0.034, 0.034], REED_D, o, sides=7)
tube("BowGrip", [(bx, y - 0.02, z - 0.06), (bx, y - 0.02, z + 0.06)], [0.036, 0.036], REED_D, o, sides=7)
tube("BowString", [pts[0], pts[-1]], [0.006, 0.006], STRING, o, sides=4)
leaf("BowLeaf", (bx, y - 0.02, z + 0.06), (bx + 0.07, y - 0.05, z + 0.13), 0.03, LEAF, o)

# --- aljava de folha trançada (arqueiro): nas costas, por baixo da capa, a boca para cima e à direita
o = opt("Quiver", (0, 0.30, 0.62), piv["Body"])
q0, q1 = Vector((0.13, 0.27, 0.40)), Vector((-0.10, 0.34, 0.80))
qd = (q1 - q0).normalized()
tube("Quiver", [q0, q0.lerp(q1, 0.5), q1], [0.05, 0.06, 0.062], LEAF_D, o, sides=9)
tube("QuiverRim", [q1 - qd * 0.02, q1 + qd * 0.015], [0.072, 0.072], REED_D, o, sides=9)
tube("QuiverBand", [q0.lerp(q1, 0.3) - qd * 0.015, q0.lerp(q1, 0.3) + qd * 0.015], [0.064, 0.064], REED_D, o, sides=9)
for k, (dx, dy) in enumerate(((0.0, 0.0), (0.025, 0.014), (-0.022, 0.016))):
    a = q1 + Vector((dx, dy, 0))
    b = a + qd * (0.14 + 0.02 * k)
    tube("Arrow%d" % k, [a - qd * 0.05, b], [0.007, 0.007], REED, o, sides=5)
    leaf("Fletch%d" % k, b - qd * 0.06, b + qd * 0.02, 0.022, LEAF if k != 1 else BONE, o, bend=0.0)

# --- cajado de galho (xamã): na mão direita, em pé; galho torto com forquilha segurando a gema verde
o = opt("Staff", hR, piv["ElbowR"])
x, y, z = hR
top = Vector((x - 0.01, y - 0.02, 1.22))
tube("Staff", [(x + 0.005, y + 0.005, 0.02), (x - 0.01, y, 0.3), (x + 0.012, y - 0.01, 0.62), (x - 0.008, y - 0.02, 0.95),
               top], [0.026, 0.029, 0.031, 0.033, 0.038], WOOD, o, sides=8)
for k, zz in enumerate((0.27, 0.40)):
    tube("StaffWrap%d" % k, [(x - 0.01, y, zz - 0.03), (x - 0.008, y, zz + 0.03)], [0.04, 0.04], REED_D, o, sides=8)
for k, sg in enumerate((1, -1)):
    tube("StaffFork%d" % k, [top, top + Vector((sg * 0.05, 0, 0.08)), top + Vector((sg * 0.035, 0, 0.17))],
         [0.03, 0.02, 0.009], WOOD, o, sides=6)
gem("StaffGem", top + Vector((0, 0, 0.11)), 0.065, GEM, o, tall=1.4)
leaf("StaffLeaf0", top + Vector((0.02, 0, -0.03)), top + Vector((0.1, 0.02, -0.15)), 0.035, LEAF, o)
leaf("StaffLeaf1", top + Vector((-0.02, 0.01, -0.05)), top + Vector((-0.08, 0.03, -0.17)), 0.03, LEAF_D, o)
ball("StaffSkull", top + Vector((0.0, -0.035, -0.07)), 0.035, BONE, o, sc=(1, 0.8, 1.1))

# --- coroa de casca (xamã): arco de casca em volta do alto da cabeça, por trás dos olhos (alto da cabeça em z 1,25:
# |x| 0,15, y -0,23..0,035), uma gema verde no meio do alto e dois galhos como chifres
o = opt("Mask", (0, -0.09, 1.25), piv["Head"])
band = []
for i in range(11):
    a = math.radians(55 + 250 * i / 10)       # 0 = frente; o arco passa por trás e para antes dos olhos
    band.append((math.sin(a) * 0.185, -0.09 - math.cos(a) * 0.16, 1.235 - 0.02 * math.cos(a)))
tube("Mask", band, [0.024] * 11, BARK, o, sides=7, flat=1.5)
for k, sg in enumerate((1, -1)):
    b0 = Vector((sg * 0.15, -0.06, 1.245))
    tube("MaskHorn%d" % k, [b0, b0 + Vector((sg * 0.05, 0.03, 0.1)), b0 + Vector((sg * 0.06, 0.05, 0.21))],
         [0.024, 0.016, 0.006], BARK, o, sides=6)
    tube("MaskTwig%d" % k, [b0 + Vector((sg * 0.05, 0.03, 0.1)), b0 + Vector((sg * 0.12, 0.04, 0.15))],
         [0.012, 0.004], BARK, o, sides=5)
    leaf("MaskLeaf%d" % k, b0 + Vector((sg * 0.01, 0.03, -0.01)), b0 + Vector((sg * 0.1, 0.12, -0.06)), 0.03, LEAF, o)
tube("MaskStem", [(0, 0.06, 1.24), (0, -0.02, 1.31)], [0.02, 0.016], BARK, o, sides=6)
gem("MaskGem", (0, -0.04, 1.335), 0.032, GEM, o, tall=1.3)

# ---------------------------------------------------------------- prévia: pesos, armas e uma pose de teste
if PREVIA:
    os.makedirs(PREVIA, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    sh = scn.display.shading
    sh.light, sh.color_type = "FLAT", "TEXTURE"
    scn.view_settings.view_transform = "Standard"
    scn.world = bpy.data.worlds.new("w")
    scn.world.color = (0.45, 0.47, 0.52)
    scn.render.resolution_x = scn.render.resolution_y = 600
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scn.camera = cam
    C = Vector((0, 0, 0.68))
    VIEWS = (("frente", C + Vector((0, -4, 0)), (math.pi / 2, 0, 0), 1.75),
             ("lado", C + Vector((-4, 0, 0)), (math.pi / 2, 0, -math.pi / 2), 1.75),
             ("costas", C + Vector((0, 4, 0)), (math.pi / 2, 0, math.pi), 1.75),
             ("tres_quartos", C + Vector((-3, -3, 2.0)), None, 1.9))

    def shoot(prefix):
        for nm, loc, rotc, sc in VIEWS:
            cam.location = loc
            cam.rotation_euler = rotc if rotc else (C - loc).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = sc
            scn.render.filepath = os.path.join(PREVIA, "%s_%s.png" % (prefix, nm))
            bpy.ops.render.render(write_still=True)

    PAL = {"Body": (0.55, 0.55, 0.55), "Head": (1.0, 0.85, 0.2), "ArmL": (0.9, 0.1, 0.1), "ElbowL": (1, 0.55, 0.55),
           "ArmR": (0.1, 0.8, 0.1), "ElbowR": (0.55, 1, 0.55), "LegL": (0.1, 0.4, 1.0), "LegR": (0.9, 0.2, 0.8)}
    for w in WEAPON_PARTS:
        w.hide_render = True
    ca = me.color_attributes.new("peso", 'FLOAT_COLOR', 'POINT')
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        ca.data[v.index].color = (*(PAL.get(gi[g.group], (0, 0, 0)) if g else (0, 0, 0)), 1)
    sh.color_type = "VERTEX"
    shoot("pesos")
    me.color_attributes.remove(me.color_attributes["peso"])
    sh.color_type = "MATERIAL"
    for w in WEAPON_PARTS:
        w.hide_render = False
    shoot("armas")
    sh.color_type = "TEXTURE"
    pb = rig.pose.bones
    # giro em x do mundo (como o jogo: x negativo leva braço/perna para a frente; no cotovelo dobra o antebraço)
    POSES = {"passo": {"LegL": -0.6, "LegR": 0.6, "ArmL": 0.5, "ArmR": -0.5, "ElbowL": -0.5, "ElbowR": -0.5},
             "golpe": {"ArmR": -2.7, "ElbowR": -1.1, "ArmL": -0.6, "ElbowL": -0.9, "Head": 0.0}}
    for pose, rot in POSES.items():
        for b in pb:
            b.rotation_mode = 'XYZ'
            b.rotation_euler = (0, 0, 0)
        for k, a in rot.items():
            b = pb[k + SK]
            mw = (rig.matrix_world @ b.bone.matrix_local).to_3x3()
            axl = mw.inverted() @ Vector((1, 0, 0))
            b.rotation_mode = 'AXIS_ANGLE'
            b.rotation_axis_angle = (a, *axl)
        bpy.context.view_layer.update()
        for w in WEAPON_PARTS:
            w.hide_render = True
        shoot(pose)
    for b in pb:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

for o in scn.objects:
    o.select_set(o.type != 'CAMERA')
    o.hide_render = False
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_skins=True,
                          export_def_bones=False)
print("EXPORT", OUT)
