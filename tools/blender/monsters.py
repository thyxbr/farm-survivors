# Monstros humanoides (goblin e esqueleto).
# Executado por exec() dentro de build_assets.py, depois de characters.py (usa mat, empty, export, tbox, limb,
# shell, ring, cloth, pouch, strap, hexc, human_head, hair_locks, sec, loft, span, grow, dome, PI).
#
# Pivôs animados por scripts/enemies/enemy.gd: LegL, LegR, Body, Head, ArmL, ArmR e, dentro dos braços, ElbowL e
# ElbowR (antebraço, mão e a arma da mão).
# Peças opcionais: todo nó "Opt_<Nome>" é equipamento de variante. data/balance/enemies.json diz em "gear"
# quais ficam (nomes sem o prefixo) e EnemyGear.apply remove o resto ao instanciar. Uma variante nova que só
# troca equipamento é só uma linha no JSON.
import math


def opt(name, loc, parent):
    return empty("Opt_" + name, loc, parent)


# ------------------------------------------------------------------ equipamento compartilhado
def m_bow(o, hx, hy, hz, s, wood, grip, string, h=0.62, bend=0.13):
    """Arco na vertical, empunhado no meio; as pontas curvam para trás (+Y) e a corda fica por fora do braço."""
    x = hx + s * 0.05
    n = 6
    pts = []
    for i in range(n + 1):
        t = i / n * 2 - 1
        pts.append((x, hy - 0.03 + bend * t * t, hz + t * h / 2))
    for i in range(n):
        ta, tb = abs(i / n * 2 - 1), abs((i + 1) / n * 2 - 1)
        limb("Bow%d" % i, pts[i], pts[i + 1], 0.019 - 0.011 * ta, 0.019 - 0.011 * tb, wood, sides=5, parent=o)
    limb("BowGrip", (x, hy - 0.03, hz - 0.055), (x, hy - 0.03, hz + 0.055), 0.023, 0.023, grip, sides=5, parent=o)
    limb("BowString", pts[0], pts[-1], 0.0035, 0.0035, string, sides=3, parent=o)


def m_quiver(o, p0, p1, leather, trim, shaft, fletch):
    """Aljava nas costas, de p0 (fundo) a p1 (boca), com três flechas aparecendo."""
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0).normalized()
    limb("Quiver", p0, p1, 0.04, 0.05, leather, sides=6, parent=o)
    limb("QuiverRim", p1 - d * 0.02, p1 + d * 0.012, 0.055, 0.055, trim, sides=6, parent=o)
    for k, (dx, dy) in enumerate(((0.0, 0.0), (0.022, 0.012), (-0.02, 0.014))):
        a = p1 + Vector((dx, dy, 0))
        b = a + d * (0.13 + 0.02 * k)
        limb("Arrow%d" % k, a - d * 0.05, b, 0.006, 0.006, shaft, sides=4, parent=o)
        limb("Fletch%d" % k, b - d * 0.07, b, 0.02, 0.012, fletch, sides=4, flat=0.25, twist=k * 0.8, parent=o)


def m_blade(o, name, hx, hy, hz, length, width, steel, edge, dark, grip, guard=0.2):
    """Espada apontando para a frente (-Y), fio na vertical."""
    y0 = hy - 0.07
    limb(name + "Grip", (hx, hy + 0.09, hz), (hx, y0, hz), 0.017, 0.017, grip, sides=6, parent=o)
    tbox(name + "Pommel", (hx, hy + 0.105, hz), (0.04, 0.04, 0.04), dark, bevel=0.01, parent=o)
    tbox(name + "Guard", (hx, y0 - 0.012, hz), (0.03, 0.028, guard), dark, bevel=0.008, parent=o)
    limb(name + "Blade", (hx, y0 - 0.02, hz), (hx, y0 - length * 0.84, hz), width, width * 0.8, steel, sides=4,
         flat=0.22, twist=PI / 2, parent=o)
    limb(name + "Tip", (hx, y0 - length * 0.84, hz), (hx, y0 - length, hz), width * 0.8, 0.0, steel, sides=4,
         flat=0.22, twist=PI / 2, parent=o)
    limb(name + "Fuller", (hx, y0 - 0.04, hz), (hx, y0 - length * 0.7, hz), width * 0.3, width * 0.2, edge, sides=4,
         flat=0.55, twist=PI / 2, parent=o)


def m_staff(o, hx, hy, z0, z1, wood, wrap):
    """Cajado na vertical passando pela mão; devolve o ponto do topo."""
    limb("Staff", (hx, hy, z0), (hx, hy - 0.015, z1), 0.016, 0.021, wood, sides=6, jitter=0.002, parent=o)
    for k in range(2):
        z = z0 + (z1 - z0) * (0.36 + 0.3 * k)
        limb("StaffWrap%d" % k, (hx, hy - 0.006, z - 0.03), (hx, hy - 0.007, z + 0.03), 0.024, 0.024, wrap, sides=6, parent=o)
    return Vector((hx, hy - 0.015, z1))


# ================================================================== GOBLIN
# Tronco e membros em loft (seções ligadas que afinam), cabeça "desenhada" (head.py) com proporções de goblin.
def build_goblin():
    gskin = mat("g_skin", hexc("#5E8C2E"), 0.85)
    gskin_d = mat("g_skin_d", hexc("#3F6620"), 0.85)
    gskin_l = mat("g_skin_l", hexc("#86B04A"), 0.85)
    cloth_m = mat("g_cloth", hexc("#7A5A34"), 0.95)
    cloth_d = mat("g_cloth_d", hexc("#4F3820"), 0.95)
    cloth_l = mat("g_cloth_l", hexc("#A07C4C"), 0.95)
    lea = mat("g_leather", hexc("#5A3A20"), 0.85)
    lea_d = mat("g_leather_d", hexc("#37220F"), 0.85)
    bone = mat("g_bone", hexc("#E6DCC0"), 0.7)
    eye = mat("g_eye", (1.0, 0.75, 0.05), 0.4, 0.0, emit=(1.0, 0.6, 0.0), strength=3.5)
    dark = mat("g_dark", hexc("#1A120E"), 0.6)
    hair = mat("g_hair", hexc("#2A2018"), 0.9)
    wood = mat("g_wood", hexc("#6B4423"), 0.9)
    wood_d = mat("g_wood_d", hexc("#40280F"), 0.9)
    iron = mat("g_iron", hexc("#7A7D86"), 0.45, 0.8)
    iron_d = mat("g_iron_d", hexc("#4B4E58"), 0.5, 0.8)
    goldm = mat("g_gold", hexc("#E6B544"), 0.35, 0.8)
    ruby = mat("g_ruby", (0.7, 0.02, 0.05), 0.2, 0.0, emit=(0.6, 0.0, 0.05), strength=1.5)
    red = mat("g_red", hexc("#8E2A22"), 0.9)
    red_d = mat("g_red_d", hexc("#5A1814"), 0.9)
    fur = mat("g_fur", hexc("#CFC6B0"), 0.95)
    fire = mat("g_fire", (1.0, 0.5, 0.08), 0.5, 0.0, emit=(1.0, 0.4, 0.05), strength=4.0)
    magic = mat("g_magic", (0.55, 0.3, 1.0), 0.3, 0.0, emit=(0.5, 0.25, 1.0), strength=3.5)
    feather = mat("g_feather", hexc("#B8402E"), 0.9)

    root = empty("Goblin", (0, 0, 0))
    # ---------------- pernas arqueadas: coxa grossa, joelho fino, panturrilha para trás, pé largo
    for side, x in (("LegL", 0.1), ("LegR", -0.1)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0, 0.55), root)
        knee = Vector((x + s * 0.03, -0.05, 0.31))
        leg_secs = [sec((x, 0.005, 0.585), 0.078, 0.084),
                    sec((x + s * 0.014, -0.02, 0.46), 0.071, 0.08, bk=1.1),
                    sec(knee, 0.047, 0.05),
                    sec((x + s * 0.028, -0.03, 0.225), 0.054, 0.058, bk=1.3),
                    sec((x + s * 0.02, 0.0, 0.075), 0.036, 0.04)]
        loft(side + "_Leg", leg_secs, gskin, leg, sides=6, chamfer=(0.0, 0.012))
        tbox(side + "_Knee", (knee.x, knee.y - 0.036, knee.z), (0.062, 0.036, 0.07), gskin_l, top=(0.8, 1), bottom=(0.7, 1),
             bevel=0.012, parent=leg)
        loft(side + "_Wrap", grow(span(leg_secs, 0.6, 0.86), add=0.007), cloth_m, leg, sides=6)
        loft(side + "_WrapTrim", grow(span(leg_secs, 0.585, 0.63), add=0.012), cloth_d, leg, sides=6)
        loft(side + "_WrapTrim2", grow(span(leg_secs, 0.83, 0.875), add=0.012), cloth_d, leg, sides=6)
        fx = x + s * 0.022
        loft(side + "_Foot", [sec((fx, 0.06, 0.045), 0.04, 0.036), sec((fx, -0.02, 0.052), 0.056, 0.05),
                              sec((fx + s * 0.006, -0.12, 0.04), 0.07, 0.034), sec((fx + s * 0.008, -0.175, 0.03), 0.058, 0.022)],
             gskin, leg, sides=6, fwd=(0, 0, 1), chamfer=0.01)
        for k in range(3):
            limb(side + "_Toe%d" % k, (fx + (k - 1) * 0.036, -0.17, 0.028), (fx + (k - 1) * 0.046, -0.235, 0.012),
                 0.019, 0.004, bone, sides=4, parent=leg)

    body = empty("Body", (0, 0, 0.55), root)
    # ---------------- tronco curvado numa peça só: quadril estreito, barriga para a frente, ombros largos, corcunda
    torso = [sec((0, 0.0, 0.535), 0.135, 0.1),
             sec((0, -0.008, 0.655), 0.125, 0.1),
             sec((0, -0.03, 0.76), 0.152, 0.122, fr=1.28),
             sec((0, -0.012, 0.88), 0.19, 0.125, fr=1.1, bk=1.22),
             sec((0, 0.01, 0.97), 0.205, 0.108, bk=1.25),
             sec((0, -0.01, 1.02), 0.1, 0.075)]
    loft("Torso", torso, gskin, body, sides=8, chamfer=(0.012, 0.0))
    loft("Belly", grow(span(torso, 0.2, 0.6), add=0.005), gskin_l, body, sides=5, arc=1.9, thick=0.012)
    for k in range(3):   # crista de vértebras na corcunda
        limb("Spine%d" % k, (0, 0.135 + k * 0.012, 0.8 + k * 0.07), (0, 0.185 + k * 0.012, 0.83 + k * 0.07), 0.024, 0.0,
             gskin_d, sides=4, parent=body)
    # tanga com barra escura, abas na frente e atrás, cinto com fivela de osso
    cloth("LoinSkirt", 0.62, 0.4, 0.148, 0.19, 2 * PI, 2 * PI, [cloth_m, cloth_d], [(0.55, 0), (0.78, 0), (1.0, 1)],
          back=0.76, cols=10, folds=0.012, thick=0.014, parent=body)
    for nm, y, rx in (("Front", -1, 0.12), ("Back", 1, -0.12)):
        tbox("Loin" + nm, (0, y * 0.118, 0.43), (0.14, 0.018, 0.22), cloth_l, bottom=(1.25, 1), rot=(y * -rx, 0, 0),
             jitter=0.004, parent=body)
        tbox("LoinHem" + nm, (0, y * 0.131, 0.33), (0.172, 0.02, 0.03), cloth_d, rot=(y * -rx, 0, 0), parent=body)
    loft("Belt", grow(span(torso, 0.17, 0.26), add=0.012), lea, body, sides=8)
    tbox("BeltBuckle", (0, -0.122, 0.635), (0.05, 0.016, 0.05), bone, bevel=0.006, rot=(0, PI / 4, 0), parent=body)
    pouch("Pouch", (0.135, -0.085, 0.575), lea, lea_d, body, size=(0.07, 0.05, 0.08), rotz=0.6)
    # alça de couro atravessando o peito e colar de dentes
    sp = [(0.15, -0.105, 0.975), (0.03, -0.176, 0.87), (-0.07, -0.19, 0.77), (-0.135, -0.11, 0.665)]
    for k in range(3):
        strap("Strap%d" % k, sp[k], sp[k + 1], 0.04, lea, body, (0, -1, 0), t=0.006)
    for k in range(5):
        a = -0.8 + k * 0.4
        limb("Tooth%d" % k, (math.sin(a) * 0.125, -0.115 - math.cos(a) * 0.03, 0.975),
             (math.sin(a) * 0.135, -0.135 - math.cos(a) * 0.035, 0.915), 0.012, 0.0, bone, sides=4, parent=body)
    # ombreira de couro com espinhos (lado esquerdo)
    shell("ShoulderPad", (0.2, 0.02, 0.985), (0.17, 0.19, 0.14), lea, cut=-0.3, rot=(0, 0.4, 0), parent=body)
    ring("ShoulderPadTrim", 0.955, 0.088, 0.018, lea_d, parent=body, sides=8, x=0.22, y=0.02)
    for k in range(3):
        limb("PadSpike%d" % k, (0.22 + k * 0.01, -0.04 + k * 0.05, 1.02), (0.27 + k * 0.01, -0.04 + k * 0.05, 1.1),
             0.02, 0.0, bone, sides=4, parent=body)

    # ---------------- cabeça "desenhada" de goblin: larga, nariz enorme, sobrancelha pesada, olhos amarelos
    head = empty("Head", (0, -0.04, 0.98), body)
    limb("Neck", (0, 0.0, 0.95), (0, -0.05, 1.05), 0.062, 0.056, gskin, sides=6, parent=head)
    face_mats = {"skin": gskin, "pupil": eye, "brow": gskin_d, "lip": dark, "mouth": dark}
    H = human_head("", 0.99, 0.3, head, face_mats,
                   {"width": 1.32, "jaw": 1.12, "chin": 0.6, "nose": 2.2, "nose_w": 1.55, "brow": 1.9, "eye_size": 1.75,
                    "eye_depth": 1.4, "mouth_w": 2.1, "ear": 0.6, "cheek": 1.4}, y0=-0.075)
    for sg, n in ((1, "L"), (-1, "R")):
        tbox("Pupil" + n, (sg * H["eye_x"], H["eye_y"] - 0.004, H["eye_z"]), (0.01, 0.006, 0.026), dark, parent=head)
        limb("Tusk" + n, (sg * 0.03, H["mouth_y"] + 0.004, H["mouth_z"] - 0.012),
             (sg * 0.038, H["mouth_y"] - 0.006, H["mouth_z"] + 0.03), 0.012, 0.0, bone, sides=4, parent=head)
        ex, ez = sg * (H["half_w"] - 0.01), H["eye_z"] - 0.005
        limb("Ear" + n, (ex, H["cy"] - 0.01, ez), (sg * 0.37, H["cy"] + 0.08, ez + 0.13), 0.075, 0.008, gskin,
             sides=4, flat=0.35, parent=head)
        limb("EarIn" + n, (ex + sg * 0.012, H["cy"] - 0.024, ez), (sg * 0.32, H["cy"] + 0.055, ez + 0.1), 0.048, 0.006,
             gskin_d, sides=4, flat=0.2, parent=head)
        tbox("Earring" + n, (sg * 0.2, H["cy"] + 0.015, ez - 0.035), (0.02, 0.02, 0.03), goldm, rot=(0, 0, sg * 0.5),
             parent=head)
    tuft = [dict(a=(0, 52), b=(180, 58), w=0.05, t=0.014, bulge=0.026, n=5),
            dict(a=(-10, 62), b=(-170, 30), w=0.042, t=0.012, bulge=0.02, n=5),
            dict(a=(10, 62), b=(170, 30), w=0.042, t=0.012, bulge=0.02, n=5)]
    hair_locks("Hair", H, tuft, hair, head, scale=1.02)
    top_z, cy = H["chin"] + 20.4 * H["s"], H["cy"]

    # ---------------- braços longos: ombro redondo, cotovelo fino, antebraço forte, mãos grandes com garras
    hands = {}
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        arm = empty(side, (sx, 0, 0.97), body)
        elbow = Vector((sx + s * 0.055, 0.035, 0.73))
        arm_secs = [sec((sx - s * 0.01, 0.0, 0.985), 0.062, 0.064),
                    sec((sx + s * 0.03, 0.012, 0.87), 0.058, 0.06),
                    sec(elbow, 0.04, 0.042),
                    sec((sx + s * 0.062, 0.005, 0.64), 0.052, 0.054),
                    sec((sx + s * 0.06, -0.03, 0.53), 0.034, 0.037)]
        # cotovelo (ElbowL/ElbowR): o antebraço, a mão e o que ela segura dobram juntos (IK do arco e do cajado)
        fore = empty("Elbow" + side[-1], tuple(elbow), arm)
        loft(side + "_Arm", arm_secs[:3], gskin, arm, sides=6, chamfer=(0.014, 0.0))
        loft(side + "_Forearm", [sec(elbow, 0.043, 0.045)] + arm_secs[3:], gskin, fore, sides=6, chamfer=(0.0, 0.0))
        tbox(side + "_ElbowCap", tuple(elbow), (0.07, 0.07, 0.07), gskin, bevel=0.02, parent=fore)
        tbox(side + "_Elbow", (elbow.x, elbow.y + 0.034, elbow.z), (0.05, 0.03, 0.055), gskin_l, bevel=0.01, parent=arm)
        loft(side + "_Wrap", grow(span(arm_secs, 0.7, 0.93), add=0.007), cloth_m, fore, sides=6)
        loft(side + "_WrapTrim", grow(span(arm_secs, 0.69, 0.73), add=0.012), cloth_d, fore, sides=6)
        hx, hy, hz = sx + s * 0.06, -0.04, 0.475
        hands[side] = (fore, hx, hy, hz, s)
        tbox(side + "_Hand", (hx, hy, hz), (0.06, 0.095, 0.085), gskin, bottom=(0.9, 0.85), bevel=0.014, parent=fore)
        tbox(side + "_Thumb", (hx - s * 0.036, hy - 0.03, hz + 0.005), (0.024, 0.03, 0.05), gskin, bevel=0.008,
             rot=(0.3, 0, 0), parent=fore)
        for k in range(3):
            y = hy - 0.034 + k * 0.034
            limb(side + "_Finger%d" % k, (hx, y, hz - 0.035), (hx - s * 0.006, y - 0.004, hz - 0.075), 0.017, 0.013, gskin,
                 sides=4, parent=fore)
            limb(side + "_Claw%d" % k, (hx - s * 0.006, y - 0.004, hz - 0.07), (hx - s * 0.02, y - 0.012, hz - 0.115),
                 0.011, 0.002, bone, sides=4, parent=fore)

    arm_r, hx, hy, hz, _ = hands["ArmR"]
    arm_l, lx, ly, lz, _ = hands["ArmL"]

    # ================= equipamento das variantes
    # --- clava com espinhos (batedor, rei)
    o = opt("Club", (hx, hy, hz), arm_r)
    limb("Club", (hx, 0.06, hz), (hx, -0.52, hz + 0.05), 0.03, 0.075, wood, sides=7, jitter=0.004, parent=o)
    limb("ClubGrip", (hx, 0.06, hz), (hx, -0.06, hz + 0.01), 0.034, 0.036, lea, sides=7, parent=o)
    for k, yy in enumerate((-0.3, -0.44)):
        limb("ClubBand%d" % k, (hx, yy, hz + 0.03), (hx, yy - 0.035, hz + 0.033), 0.072, 0.075, wood_d if k else iron,
             sides=7, parent=o)
    for k, (dx, dz) in enumerate(((0.07, 0.0), (-0.07, 0.0), (0.0, 0.075), (0.0, -0.07))):
        limb("ClubSpike%d" % k, (hx + dx * 0.8, -0.46, hz + 0.045 + dz * 0.8),
             (hx + dx * 1.5, -0.47, hz + 0.045 + dz * 1.5), 0.018, 0.0, iron, sides=4, parent=o)

    # --- picareta de mineiro (kobold): cabo reto e cabeça de ferro com bico para cima e pá para baixo
    o = opt("Pickaxe", (hx, hy, hz), arm_r)
    limb("PickHaft", (hx, 0.1, hz), (hx, -0.6, hz + 0.03), 0.02, 0.023, wood, sides=6, parent=o)
    limb("PickGrip", (hx, 0.08, hz), (hx, -0.07, hz + 0.006), 0.026, 0.026, lea, sides=6, parent=o)
    tbox("PickEye", (hx, -0.58, hz + 0.03), (0.05, 0.06, 0.07), iron_d, bevel=0.008, parent=o)
    limb("PickBeak", (hx, -0.58, hz + 0.06), (hx, -0.54, hz + 0.24), 0.026, 0.0, iron, sides=4, parent=o)
    limb("PickBlade", (hx, -0.58, hz), (hx, -0.55, hz - 0.15), 0.03, 0.01, iron, sides=4, flat=0.4, parent=o)

    # --- clava enorme de tronco com cintas de ferro (bruto)
    o = opt("BigClub", (hx, hy, hz), arm_r)
    limb("BigClub", (hx, 0.1, hz), (hx, -0.78, hz + 0.07), 0.034, 0.125, wood, sides=7, jitter=0.006, parent=o)
    limb("BigClubGrip", (hx, 0.1, hz), (hx, -0.07, hz + 0.012), 0.039, 0.045, lea, sides=7, parent=o)
    limb("BigClubKnob", (hx, 0.1, hz), (hx, 0.14, hz - 0.004), 0.05, 0.04, wood_d, sides=7, parent=o)
    for k, yy in enumerate((-0.42, -0.58, -0.72)):
        zz = hz + 0.07 * (0.1 - yy) / 0.88
        rr = 0.034 + 0.091 * (0.1 - yy) / 0.88
        limb("BigClubBand%d" % k, (hx, yy, zz), (hx, yy - 0.04, zz + 0.003), rr + 0.006, rr + 0.011, iron_d, sides=7, parent=o)
        for j in range(4):
            a = j * PI / 2 + k * 0.6
            dx, dz = math.cos(a), math.sin(a)
            limb("BigClubSpike%d_%d" % (k, j), (hx + dx * rr, yy - 0.02, zz + dz * rr),
                 (hx + dx * (rr + 0.085), yy - 0.03, zz + dz * (rr + 0.085)), 0.022, 0.0, iron, sides=4, parent=o)

    # --- machado de duas lâminas (campeão)
    o = opt("Axe", (hx, hy, hz), arm_r)
    limb("AxeHaft", (hx, 0.14, hz), (hx, -0.74, hz + 0.04), 0.022, 0.024, wood_d, sides=6, parent=o)
    limb("AxeGrip", (hx, 0.1, hz), (hx, -0.07, hz + 0.008), 0.027, 0.027, lea, sides=6, parent=o)
    limb("AxeCap", (hx, -0.72, hz + 0.04), (hx, -0.8, hz + 0.043), 0.03, 0.0, iron, sides=4, parent=o)
    tbox("AxeEye", (hx, -0.63, hz + 0.036), (0.05, 0.1, 0.07), iron_d, bevel=0.01, parent=o)
    for k, sg in enumerate((1, -1)):
        tbox("AxeBlade%d" % k, (hx, -0.63, hz + 0.036 + sg * 0.13), (0.02, 0.1, 0.2), iron,
             top=(0.35, 2.7) if sg > 0 else (1, 1), bottom=(0.35, 2.7) if sg < 0 else (1, 1), parent=o)
        tbox("AxeEdge%d" % k, (hx, -0.63, hz + 0.036 + sg * 0.235), (0.008, 0.275, 0.022), bone, parent=o)

    # --- tocha acesa (bombardeiro)
    o = opt("Torch", (hx, hy, hz), arm_r)
    limb("Torch", (hx, 0.05, hz), (hx, -0.3, hz + 0.1), 0.017, 0.022, wood_d, sides=6, parent=o)
    limb("TorchWrap", (hx, -0.27, hz + 0.09), (hx, -0.36, hz + 0.118), 0.034, 0.04, cloth_d, sides=6, parent=o)
    limb("TorchFlame", (hx, -0.34, hz + 0.115), (hx, -0.4, hz + 0.27), 0.05, 0.0, fire, sides=5, parent=o)
    limb("TorchFlame2", (hx + 0.02, -0.35, hz + 0.11), (hx + 0.05, -0.38, hz + 0.2), 0.03, 0.0, fire, sides=4, parent=o)

    # --- cajado de xamã: crânio de pássaro, penas e pedra brilhante
    o = opt("Staff", (hx, hy, hz), arm_r)
    top = m_staff(o, hx, hy - 0.02, 0.04, 1.2, wood, lea)
    limb("StaffFork0", top, top + Vector((0.07, 0, 0.13)), 0.018, 0.008, wood, sides=5, parent=o)
    limb("StaffFork1", top, top + Vector((-0.07, 0, 0.13)), 0.018, 0.008, wood, sides=5, parent=o)
    tbox("StaffGem", top + Vector((0, 0, 0.1)), (0.06, 0.06, 0.085), magic, bevel=0.02, rot=(0, 0, PI / 4), parent=o)
    tbox("StaffSkull", top + Vector((0, -0.03, -0.04)), (0.06, 0.07, 0.06), bone, bottom=(0.6, 0.7), bevel=0.012, parent=o)
    for k in range(3):
        b = top + Vector((0.03 + k * 0.012, 0.005, -0.03))
        limb("StaffFeather%d" % k, b, b + Vector((0.06 + k * 0.025, 0.02, -0.14)), 0.02, 0.004,
             feather if k != 1 else bone, sides=4, flat=0.25, parent=o)

    # --- arco e aljava (arqueiro)
    o = opt("Bow", (lx, ly, lz), arm_l)
    m_bow(o, lx, ly, lz, 1, wood, lea, bone)
    o = opt("Quiver", (0, 0.15, 0.85), body)
    m_quiver(o, (-0.1, 0.165, 0.7), (0.09, 0.175, 1.0), lea, lea_d, wood, feather)

    # --- máscara de osso com chifres e penas (xamã)
    o = opt("Mask", (0, H["front_y"], H["eye_z"]), head)
    fy = H["front_y"] - 0.035
    tbox("Mask", (0, fy, H["eye_z"] + 0.012), (0.2, 0.02, 0.17), bone, top=(1.1, 1), bottom=(0.55, 1), bevel=0.008,
         rot=(0.1, 0, 0), parent=o)
    tbox("MaskBrow", (0, fy - 0.012, H["eye_z"] + 0.06), (0.21, 0.024, 0.03), lea_d, parent=o)
    for sg in (1, -1):
        tbox("MaskEye%d" % sg, (sg * 0.048, fy - 0.012, H["eye_z"] + 0.018), (0.05, 0.012, 0.028), dark, rot=(0, sg * 0.3, 0),
             parent=o)
        tbox("MaskGlow%d" % sg, (sg * 0.048, fy - 0.019, H["eye_z"] + 0.018), (0.018, 0.006, 0.014), magic, parent=o)
        limb("MaskHorn%d" % sg, (sg * 0.085, fy + 0.01, H["eye_z"] + 0.08), (sg * 0.17, fy - 0.01, H["eye_z"] + 0.26),
             0.028, 0.0, bone, sides=5, parent=o)
        tbox("MaskPaint%d" % sg, (sg * 0.06, fy - 0.012, H["eye_z"] - 0.035), (0.012, 0.008, 0.06), feather,
             rot=(0, sg * 0.25, 0), parent=o)
    for k in range(5):
        a = (k - 2) * 0.32
        limb("MaskFeather%d" % k, (math.sin(a) * 0.07, fy + 0.04, H["eye_z"] + 0.09),
             (math.sin(a) * 0.16, fy + 0.09, H["eye_z"] + 0.2 + math.cos(a) * 0.08), 0.026, 0.004,
             feather if k % 2 == 0 else bone, sides=4, flat=0.25, parent=o)

    # --- saco de ouro nas costas (dourado)
    o = opt("Sack", (0, 0.2, 0.85), body)
    shell("Sack", (0, 0.24, 0.8), (0.36, 0.3, 0.42), cloth_l, cut=-1.0, seg=8, rings=6, thick=0, jitter=0.008, parent=o)
    limb("SackNeck", (0, 0.24, 0.99), (0, 0.22, 1.07), 0.06, 0.085, cloth_l, sides=7, parent=o)
    ring("SackRope", 1.0, 0.066, 0.022, lea_d, parent=o, sides=7, y=0.238)
    tbox("SackPatch", (0.1, 0.375, 0.78), (0.09, 0.012, 0.09), cloth_d, rot=(0, 0, -0.5), parent=o)
    for k, (dx, dy, dz) in enumerate(((0.0, 0.0, 0.0), (0.035, -0.01, -0.006), (-0.03, 0.012, -0.004), (0.01, 0.03, 0.012))):
        limb("SackCoin%d" % k, (dx, 0.22 + dy, 1.065 + dz), (dx, 0.22 + dy, 1.078 + dz), 0.028, 0.028, goldm, sides=6, parent=o)
    for k in range(2):
        strap("SackStrap%d" % k, ((0.11 - k * 0.22), -0.1, 0.99), ((0.13 - k * 0.26), 0.12, 0.98), 0.035, lea, o, (0, 0, 1))

    # --- barril de pólvora nas costas com pavio (bombardeiro)
    o = opt("Barrel", (0, 0.2, 0.85), body)
    limb("Barrel", (0, 0.25, 0.64), (0, 0.25, 0.83), 0.115, 0.14, wood, sides=8, parent=o)
    limb("BarrelTop", (0, 0.25, 0.83), (0, 0.25, 1.02), 0.14, 0.115, wood, sides=8, parent=o)
    for k, z in enumerate((0.69, 0.83, 0.97)):
        ring("BarrelHoop%d" % k, z, 0.146 if k == 1 else 0.132, 0.03, iron_d, parent=o, sides=8, y=0.25)
    tbox("BarrelMark", (0, 0.392, 0.83), (0.09, 0.01, 0.09), red, rot=(0, PI / 4, 0), parent=o)
    limb("BarrelFuse", (0.04, 0.25, 1.02), (0.09, 0.22, 1.13), 0.008, 0.008, cloth_l, sides=4, parent=o)
    tbox("BarrelSpark", (0.092, 0.218, 1.14), (0.035, 0.035, 0.035), fire, rot=(0.6, 0.6, 0), parent=o)
    for k in range(2):
        strap("BarrelStrap%d" % k, ((0.11 - k * 0.22), -0.1, 0.99), ((0.12 - k * 0.24), 0.14, 0.97), 0.035, lea, o, (0, 0, 1))

    # --- peitoral de ferro, ombreira direita e saiote de placas (campeão)
    o = opt("Armor", (0, 0, 0.85), body)
    loft("ArmorChest", grow(span(torso, 0.42, 0.9), add=0.03, keel=0.06), iron, o, sides=6, phase=0.0, arc=2.9, thick=0.016)
    loft("ArmorBack", grow(span(torso, 0.5, 0.9), add=0.03), iron_d, o, sides=6, arc=2.6, thick=0.016, fwd=(0, 1, 0))
    loft("ArmorTrim", grow(span(torso, 0.415, 0.45), add=0.037), goldm, o, sides=6, arc=2.95, thick=0.012)
    dome("ArmorPauldron", (-0.215, 0.01, 0.955), (-0.5, 0, 1), 0.105, 0.115, 0.1, iron, o, sides=8, lip=0.02)
    for k in range(2):
        limb("ArmorSpike%d" % k, (-0.25, -0.03 + k * 0.07, 1.03), (-0.31, -0.03 + k * 0.07, 1.12), 0.022, 0.0, bone,
             sides=4, parent=o)
    for k in range(3):
        a = (k - 1) * 0.55
        tbox("ArmorTasset%d" % k, (math.sin(a) * 0.15, -math.cos(a) * 0.135, 0.56), (0.1, 0.016, 0.13), iron_d,
             bottom=(0.8, 1), bevel=0.005, rot=(0.12, 0, -a), parent=o)

    # --- elmo de ferro com crista e protetor de nariz (campeão)
    o = opt("Helm", (0, cy, top_z), head)
    dome("Helm", (0, cy, top_z - 0.085), (0, 0, 1), 0.118, 0.14, 0.13, iron, o, sides=8, lip=0.02)
    ring("HelmBand", top_z - 0.08, 0.121, 0.03, iron_d, parent=o, sides=8, flat=1.19, y=cy)
    tbox("HelmNasal", (0, H["front_y"] - 0.012, top_z - 0.125), (0.03, 0.014, 0.11), iron_d, bevel=0.004, parent=o)
    for k in range(3):
        limb("HelmCrest%d" % k, (0, cy - 0.07 + k * 0.07, top_z + 0.03), (0, cy - 0.05 + k * 0.08, top_z + 0.13 - k * 0.012),
             0.03, 0.0, red, sides=4, flat=0.3, twist=PI / 2, parent=o)

    # --- ombreira direita, cinturão de ferro e braçadeira de espinhos nas costas (bruto)
    o = opt("Pads", (0, 0, 0.85), body)
    shell("PadR", (-0.2, 0.02, 0.985), (0.2, 0.22, 0.16), iron_d, cut=-0.3, rot=(0, -0.4, 0), parent=o)
    for k in range(3):
        limb("PadRSpike%d" % k, (-0.22 - k * 0.01, -0.05 + k * 0.06, 1.03), (-0.29 - k * 0.01, -0.05 + k * 0.06, 1.14),
             0.026, 0.0, bone, sides=4, parent=o)
    loft("GutPlate", grow(span(torso, 0.2, 0.5), add=0.02), iron_d, o, sides=5, arc=1.7, thick=0.018)
    for k in range(3):
        limb("GutStud%d" % k, ((k - 1) * 0.075, -0.2, 0.735), ((k - 1) * 0.085, -0.25, 0.74), 0.022, 0.0, iron, sides=4, parent=o)
    for k in range(2):
        strap("GutStrap%d" % k, ((0.16 - k * 0.32), -0.07, 0.72), ((0.15 - k * 0.3), 0.1, 0.72), 0.05, lea_d, o,
              ((1 - 2 * k), 0, 0))

    # --- capacete de mineiro com lampião aceso na testa (kobold)
    o = opt("MinerHelmet", (0, cy, top_z), head)
    dome("MinerHelmet", (0, cy, top_z - 0.085), (0, 0, 1), 0.122, 0.144, 0.12, lea, o, sides=8, lip=0.03)
    ring("MinerHelmetBand", top_z - 0.08, 0.126, 0.028, lea_d, parent=o, sides=8, flat=1.19, y=cy)
    lamp_y = cy - 0.144 * 1.0 - 0.01
    tbox("MinerLampBase", (0, lamp_y, top_z - 0.04), (0.06, 0.03, 0.06), iron_d, bevel=0.006, parent=o)
    limb("MinerLampCup", (0, lamp_y - 0.01, top_z - 0.04), (0, lamp_y - 0.055, top_z - 0.04), 0.03, 0.04, iron,
         sides=8, parent=o)
    limb("MinerLampGlow", (0, lamp_y - 0.045, top_z - 0.04), (0, lamp_y - 0.06, top_z - 0.04), 0.032, 0.03, fire,
         sides=8, parent=o)

    # --- cinto de couro com bananas de dinamite (kobold)
    # cinto mais grosso por cima do cinto da tanga; as bananas encostam nele, em volta da cintura (fivela no meio)
    o = opt("DynamiteBelt", (0, 0, 0.62), body)
    loft("DynBelt", grow(span(torso, 0.16, 0.27), add=0.026), lea_d, o, sides=8)
    tbox("DynBuckle", (0, -0.138, 0.625), (0.06, 0.016, 0.05), iron, bevel=0.006, parent=o)
    for k, a in enumerate((-1.15, -0.6, 0.6, 1.15)):
        bx, by = math.sin(a) * 0.168, -math.cos(a) * 0.136 - 0.006
        limb("Dyn%d" % k, (bx, by, 0.56), (bx, by, 0.7), 0.026, 0.026, red, sides=6, parent=o)
        limb("DynFuse%d" % k, (bx, by, 0.698), (bx * 1.08, by * 1.08, 0.74), 0.006, 0.004, cloth_l, sides=4, parent=o)

    # --- coroa (rei): aro facetado sentado no crânio
    cz, cr = top_z, 0.094
    o = opt("Crown", (0, cy, cz), head)
    ring("CrownBand", cz, cr, 0.045, goldm, parent=o, sides=8, flat=1.22, y=cy)
    for i in range(6):
        a = i / 6 * 2 * PI + PI / 2
        limb("CrownSpike%d" % i, (math.cos(a) * cr * 0.95, cy + math.sin(a) * cr * 1.17, cz + 0.02),
             (math.cos(a) * cr * 1.02, cy + math.sin(a) * cr * 1.26, cz + 0.09), 0.032, 0.0, goldm, sides=4, parent=o)
    tbox("CrownGem", (0, cy - cr * 1.24, cz), (0.04, 0.02, 0.036), ruby, bevel=0.006, parent=o)

    # --- capa vermelha com barra escura e gola de pele (rei)
    o = opt("Cape", (0, 0.1, 0.9), body)
    cloth("Cape", 1.0, 0.2, 0.2, 0.32, 2.5, 3.0, [red, red_d, goldm], [(0.8, 0), (0.93, 1), (1.0, 2)], center=(0, 0.03),
          back=0.85, cols=8, folds=0.022, thick=0.014, parent=o)
    for k in range(7):
        a = (k - 3) * 0.5
        tbox("CapeFur%d" % k, (math.sin(a) * 0.215, 0.03 + math.cos(a) * 0.135, 1.0), (0.11, 0.09, 0.075), fur, bevel=0.02,
             rot=(0, 0, -a), jitter=0.006, seed=k, parent=o)
    tbox("CapeClasp", (0, -0.12, 1.0), (0.05, 0.02, 0.05), goldm, bevel=0.008, rot=(0, PI / 4, 0), parent=o)
    for sg in (1, -1):
        strap("CapeChain%d" % sg, (sg * 0.02, -0.122, 1.0), (sg * 0.2, -0.04, 1.01), 0.022, goldm, o, (0, -1, 0))
    export("goblin")


# ================================================================== ESQUELETO
# Altura de humano magro (~1,72 m). Ossos longos com nós nas juntas, costelas vazadas, crânio com órbitas
# escuras e brasa nos olhos, trapos na cintura.
def build_skeleton():
    bone = mat("sk_bone", hexc("#E2D9BC"), 0.75)
    bone_d = mat("sk_bone_d", hexc("#A99E7E"), 0.8)
    bone_l = mat("sk_bone_l", hexc("#F5EFDC"), 0.7)
    dark = mat("sk_dark", hexc("#15110E"), 0.7)
    glow = mat("sk_eye", (0.1, 0.95, 0.5), 0.4, 0.0, emit=(0.05, 1.0, 0.45), strength=2.5)
    rag = mat("sk_rag", hexc("#4A4258"), 0.95)
    rag_d = mat("sk_rag_d", hexc("#2E2838"), 0.95)
    rust = mat("sk_rust", hexc("#9A8E80"), 0.6, 0.35)
    rust_d = mat("sk_rust_d", hexc("#6A5648"), 0.65, 0.35)
    steel = mat("sk_steel", hexc("#9A9EA8"), 0.45, 0.8)
    wood = mat("sk_wood", hexc("#8A6842"), 0.9)
    wood_d = mat("sk_wood_d", hexc("#66492C"), 0.9)
    lea = mat("sk_leather", hexc("#4E3524"), 0.85)
    robe = mat("sk_robe", hexc("#3E2A5C"), 0.95)
    robe_d = mat("sk_robe_d", hexc("#261A3C"), 0.95)
    robe_l = mat("sk_robe_l", hexc("#8A6CB8"), 0.95)
    magic = mat("sk_magic", (0.65, 0.3, 1.0), 0.3, 0.0, emit=(0.6, 0.25, 1.0), strength=4.0)
    red = mat("sk_red", hexc("#6E211C"), 0.95)
    red_d = mat("sk_red_d", hexc("#431411"), 0.95)

    def knob(name, p, r, parent, m=None):
        tbox(name, p, (r * 2, r * 2, r * 2), m or bone_d, bevel=r * 0.55, parent=parent)

    root = empty("Skeleton", (0, 0, 0))
    HIP, SH, NECK = 0.86, 1.37, 1.44
    # ---------------- pernas: fêmur, joelho, tíbia e fíbula, pé de ossinhos
    for side, x in (("LegL", 0.09), ("LegR", -0.09)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0, HIP), root)
        knee = Vector((x + s * 0.012, -0.025, 0.47))
        ankle = Vector((x + s * 0.004, 0.005, 0.085))
        knob(side + "_HipBall", (x, 0, HIP), 0.036, leg)
        limb(side + "_Femur", (x, 0, HIP), knee, 0.028, 0.022, bone, sides=6, parent=leg)
        knob(side + "_Knee", knee, 0.036, leg)
        tbox(side + "_KneeCap", knee + Vector((0, -0.035, 0.005)), (0.045, 0.02, 0.05), bone_l, bevel=0.008, parent=leg)
        limb(side + "_Tibia", knee, ankle, 0.025, 0.018, bone, sides=6, parent=leg)
        limb(side + "_Fibula", knee + Vector((s * 0.028, 0.012, -0.02)), ankle + Vector((s * 0.022, 0.01, 0.02)), 0.01, 0.009,
             bone_d, sides=4, parent=leg)
        knob(side + "_Ankle", ankle, 0.028, leg)
        tbox(side + "_Heel", ankle + Vector((0, 0.03, -0.05)), (0.055, 0.075, 0.06), bone, bevel=0.014, parent=leg)
        tbox(side + "_Foot", ankle + Vector((0, -0.07, -0.055)), (0.075, 0.13, 0.045), bone, top=(0.75, 0.9), bevel=0.012,
             shift_top=(0, 0.015), parent=leg)
        for k in range(3):
            tx = ankle.x + (k - 1) * 0.027
            limb(side + "_Toe%d" % k, (tx, -0.125, 0.026), (tx + (k - 1) * 0.008, -0.205, 0.014), 0.013, 0.007, bone_l,
                 sides=4, parent=leg)

    body = empty("Body", (0, 0, HIP), root)
    # ---------------- bacia: bloco central, asas do ilíaco e trapos
    tbox("Pelvis", (0, 0.01, HIP + 0.03), (0.2, 0.1, 0.1), bone, top=(1.1, 1), bottom=(0.5, 0.8), bevel=0.02, parent=body)
    for sg in (1, -1):
        tbox("Ilium%d" % sg, (sg * 0.105, 0.02, HIP + 0.075), (0.11, 0.07, 0.13), bone, top=(1.0, 0.7), bottom=(0.6, 1),
             bevel=0.02, rot=(0, sg * 0.35, sg * 0.25), parent=body)
    tbox("Sacrum", (0, 0.045, HIP + 0.02), (0.07, 0.04, 0.11), bone_d, bottom=(0.4, 0.8), bevel=0.01, parent=body)
    cloth("Rags", HIP + 0.1, HIP - 0.22, 0.125, 0.15, 2 * PI, 2 * PI, [rag, rag_d], [(0.5, 0), (0.8, 0), (1.0, 1)], back=0.7,
          cols=9, folds=0.016, thick=0.01, parent=body)
    tbox("RagFront", (0.03, -0.1, HIP - 0.22), (0.11, 0.012, 0.22), rag, bottom=(0.5, 1), rot=(0.08, 0, 0.1), jitter=0.006,
         parent=body)
    tbox("RagBack", (-0.03, 0.105, HIP - 0.2), (0.12, 0.012, 0.2), rag_d, bottom=(0.6, 1), rot=(-0.08, 0, -0.1), jitter=0.006,
         parent=body)
    ring("RagBelt", HIP + 0.09, 0.13, 0.03, lea, parent=body, sides=8, flat=0.72)
    # ---------------- coluna e costelas vazadas
    for k in range(7):
        z = HIP + 0.11 + k * 0.064
        y = 0.05 + 0.012 * math.sin(k * 0.75)
        tbox("Vert%d" % k, (0, y, z), (0.046, 0.05, 0.046), bone_d if k % 2 else bone, bevel=0.012, parent=body)
        limb("VertSpur%d" % k, (0, y + 0.02, z), (0, y + 0.06, z - 0.015), 0.012, 0.004, bone_d, sides=4, parent=body)
    ribs = [(1.035, 0.098, 0.08), (1.1, 0.128, 0.098), (1.165, 0.145, 0.108), (1.23, 0.146, 0.106), (1.295, 0.128, 0.094)]
    for k, (z, rx, ry) in enumerate(ribs):
        c = Vector((0, -0.006, z))
        loft("Rib%d" % k, [sec(c + Vector((0, 0.012, 0.022)), rx, ry), sec(c + Vector((0, -0.012, -0.018)), rx * 0.97, ry * 0.97)],
             bone if k % 2 == 0 else bone_l, body, sides=9, arc=5.5, thick=0.02, axis=(0, 0, -1))
    tbox("Sternum", (0, -0.108, 1.19), (0.045, 0.02, 0.24), bone_l, top=(1.3, 1), bottom=(0.6, 1), bevel=0.006, parent=body)
    # clavículas, escápulas e nós dos ombros
    for sg in (1, -1):
        limb("Clavicle%d" % sg, (sg * 0.02, -0.07, 1.335), (sg * 0.2, 0.0, SH), 0.016, 0.014, bone, sides=5, parent=body)
        tbox("Scapula%d" % sg, (sg * 0.115, 0.1, 1.26), (0.1, 0.02, 0.15), bone_d, top=(1.15, 1), bottom=(0.45, 1), bevel=0.006,
             rot=(0.12, 0, sg * -0.2), parent=body)
        knob("Shoulder%d" % sg, (sg * 0.2, 0, SH), 0.038, body, bone)

    # ---------------- crânio
    head = empty("Head", (0, 0.02, NECK), body)
    for k in range(2):
        tbox("NeckVert%d" % k, (0, 0.035 - k * 0.012, 1.375 + k * 0.05), (0.04, 0.042, 0.04), bone_d if k else bone, bevel=0.01,
             parent=head)
    SZ = 1.575
    shell("Skull", (0, 0.005, SZ), (0.2, 0.235, 0.2), bone, cut=-1.0, seg=8, rings=6, thick=0, parent=head)
    tbox("Cheeks", (0, -0.062, SZ - 0.085), (0.15, 0.1, 0.085), bone, bottom=(0.72, 0.8), bevel=0.016, parent=head)
    tbox("Jaw", (0, -0.055, SZ - 0.158), (0.118, 0.11, 0.04), bone_d, bottom=(0.7, 0.85), shift_bottom=(0, -0.006), bevel=0.012,
         parent=head)
    for sg in (1, -1):
        tbox("Socket%d" % sg, (sg * 0.046, -0.108, SZ - 0.008), (0.056, 0.03, 0.052), dark, bottom=(0.8, 1), bevel=0.01,
             rot=(0.12, 0, sg * -0.22), parent=head)
        tbox("EyeGlow%d" % sg, (sg * 0.046, -0.117, SZ - 0.01), (0.018, 0.01, 0.018), glow, rot=(0, PI / 4, 0), parent=head)
        tbox("BrowRidge%d" % sg, (sg * 0.05, -0.112, SZ + 0.026), (0.07, 0.03, 0.02), bone_l, rot=(0, sg * -0.32, 0), bevel=0.005,
             parent=head)
        tbox("CheekBone%d" % sg, (sg * 0.078, -0.085, SZ - 0.05), (0.036, 0.06, 0.022), bone_l, bevel=0.006, parent=head)
        tbox("JawHinge%d" % sg, (sg * 0.066, -0.01, SZ - 0.12), (0.02, 0.04, 0.09), bone_d, bevel=0.005, parent=head)
    limb("NoseHole", (0, -0.112, SZ - 0.042), (0, -0.112, SZ - 0.084), 0.004, 0.022, dark, sides=3, flat=0.4, parent=head)
    tbox("TeethTop", (0, -0.112, SZ - 0.118), (0.09, 0.012, 0.022), bone_l, parent=head)
    tbox("TeethLow", (0, -0.108, SZ - 0.143), (0.08, 0.012, 0.018), bone_l, parent=head)
    for k in range(5):
        tbox("TeethGap%d" % k, ((k - 2) * 0.019, -0.119, SZ - 0.128), (0.004, 0.004, 0.044), dark, parent=head)
    tbox("SkullCrack", (0.05, -0.085, SZ + 0.07), (0.006, 0.006, 0.07), dark, rot=(0.9, 0, 0.5), parent=head)

    # ---------------- braços: úmero, cotovelo, rádio e ulna, mão de falanges
    hands = {}
    for side, sx in (("ArmR", -0.2), ("ArmL", 0.2)):
        s = 1 if sx > 0 else -1
        arm = empty(side, (sx, 0, SH), body)
        elbow = Vector((sx + s * 0.03, 0.025, 1.09))
        wrist = Vector((sx + s * 0.04, -0.035, 0.85))
        limb(side + "_Humerus", (sx, 0, SH), elbow, 0.024, 0.019, bone, sides=6, parent=arm)
        fore = empty("Elbow" + side[-1], tuple(elbow), arm)  # cotovelo: antebraço e mão dobram juntos
        knob(side + "_Elbow", elbow, 0.03, fore)
        limb(side + "_Radius", elbow + Vector((s * 0.012, 0, 0)), wrist + Vector((s * 0.014, 0, 0)), 0.014, 0.012, bone,
             sides=5, parent=fore)
        limb(side + "_Ulna", elbow + Vector((-s * 0.012, 0.006, 0)), wrist + Vector((-s * 0.012, 0.004, 0)), 0.012, 0.01,
             bone_d, sides=4, parent=fore)
        knob(side + "_Wrist", wrist, 0.024, fore)
        hx, hy, hz = wrist.x, wrist.y - 0.008, wrist.z - 0.055
        hands[side] = (fore, hx, hy, hz, s)
        tbox(side + "_Palm", (hx, hy, hz + 0.01), (0.03, 0.075, 0.06), bone, bevel=0.008, parent=fore)
        limb(side + "_Thumb", (hx - s * 0.012, hy - 0.035, hz + 0.02), (hx - s * 0.034, hy - 0.055, hz - 0.02), 0.01, 0.006,
             bone_l, sides=4, parent=fore)
        for k in range(4):
            y = hy - 0.03 + k * 0.02
            limb(side + "_Finger%d" % k, (hx, y, hz - 0.02), (hx - s * 0.014, y - 0.004, hz - 0.085), 0.009, 0.005, bone_l,
                 sides=4, parent=fore)

    arm_r, hx, hy, hz, _ = hands["ArmR"]
    arm_l, lx, ly, lz, _ = hands["ArmL"]

    # ================= equipamento das variantes
    # --- espada enferrujada e escudo redondo (guerreiro)
    o = opt("Sword", (hx, hy, hz), arm_r)
    m_blade(o, "Sword", hx, hy, hz, 0.72, 0.04, rust, rust_d, rust_d, lea)
    o = opt("Shield", (lx, ly, lz), arm_l)
    sx0 = lx + 0.045
    limb("Shield", (sx0, ly - 0.02, lz + 0.09), (sx0 + 0.025, ly - 0.02, lz + 0.09), 0.215, 0.2, wood, sides=8, parent=o)
    limb("ShieldRim", (sx0 + 0.006, ly - 0.02, lz + 0.09), (sx0 + 0.03, ly - 0.02, lz + 0.09), 0.225, 0.225, rust_d, sides=8,
         parent=o)
    limb("ShieldFace", (sx0 + 0.022, ly - 0.02, lz + 0.09), (sx0 + 0.036, ly - 0.02, lz + 0.09), 0.19, 0.185, wood_d, sides=8,
         parent=o)
    limb("ShieldBoss", (sx0 + 0.03, ly - 0.02, lz + 0.09), (sx0 + 0.075, ly - 0.02, lz + 0.09), 0.06, 0.02, rust, sides=6,
         parent=o)
    tbox("ShieldBarV", (sx0 + 0.038, ly - 0.02, lz + 0.09), (0.008, 0.03, 0.37), rust, parent=o)
    tbox("ShieldBarH", (sx0 + 0.038, ly - 0.02, lz + 0.09), (0.008, 0.37, 0.03), rust, parent=o)

    # --- arco e aljava (arqueiro)
    o = opt("Bow", (lx, ly, lz), arm_l)
    m_bow(o, lx, ly, lz, 1, wood_d, lea, bone_l, h=0.86, bend=0.16)
    o = opt("Quiver", (0, 0.15, 1.2), body)
    m_quiver(o, (-0.11, 0.15, 0.98), (0.1, 0.165, 1.36), lea, rust_d, wood, red)

    # --- cajado com crânio de corvo e pedra roxa (mago)
    o = opt("Staff", (hx, hy, hz), arm_r)
    top = m_staff(o, hx, hy - 0.01, 0.04, 1.62, wood_d, rag)
    for k in range(3):
        a = k * 2.1 + 0.3
        limb("StaffClaw%d" % k, top, top + Vector((math.cos(a) * 0.065, math.sin(a) * 0.065, 0.11)), 0.014, 0.005, bone_d,
             sides=4, parent=o)
    tbox("StaffGem", top + Vector((0, 0, 0.11)), (0.075, 0.075, 0.11), magic, bevel=0.028, rot=(0, 0, PI / 4), parent=o)
    tbox("StaffCharm", top + Vector((0.035, 0, -0.08)), (0.03, 0.03, 0.04), bone_l, bevel=0.008, parent=o)

    # --- capuz rasgado com mantelete (mago)
    o = opt("Hood", (0, 0.02, SZ), head)
    shell("Hood", (0, 0.03, SZ + 0.005), (0.275, 0.3, 0.29), robe, cut=-0.25, seg=8, rings=6, rot=(-1.0, 0, 0), thick=0.014,
          parent=o)
    limb("HoodTail", (0, 0.15, SZ + 0.06), (0, 0.27, SZ - 0.06), 0.07, 0.0, robe_d, sides=5, parent=o)
    cloth("Mantle", 1.44, 1.2, 0.09, 0.27, 2 * PI, 2 * PI, [robe, robe_d, robe_l], [(0.6, 0), (0.9, 1), (1.0, 2)], center=(0, 0.01),
          back=0.8, cols=10, folds=0.02, thick=0.012, parent=o)
    for sg in (1, -1):
        tbox("MantleTatter%d" % sg, (sg * 0.09, -0.19, 1.1), (0.07, 0.012, 0.2), robe_d, bottom=(0.3, 1), rot=(-0.12, 0, sg * 0.15),
             parent=o)
    tbox("MantleClasp", (0, -0.1, 1.4), (0.045, 0.02, 0.045), bone_l, bevel=0.008, rot=(0, PI / 4, 0), parent=o)

    # --- espadão (cavaleiro)
    o = opt("Greatsword", (hx, hy, hz), arm_r)
    m_blade(o, "Greatsword", hx, hy, hz, 1.12, 0.062, steel, rust_d, rust_d, red, guard=0.32)
    tbox("GreatswordGem", (hx, hy - 0.082, hz), (0.036, 0.03, 0.05), glow, bevel=0.008, parent=o)

    # --- elmo com viseira aberta e penacho (cavaleiro)
    o = opt("Helm", (0, 0.005, SZ), head)
    dome("Helm", (0, 0.005, SZ + 0.0), (0, 0, 1), 0.118, 0.137, 0.125, steel, o, sides=8, lip=0.03, keel=0.05, phase=0.0)
    ring("HelmBand", SZ + 0.0, 0.122, 0.035, rust_d, parent=o, sides=8, flat=1.16, y=0.005)
    for sg in (1, -1):
        tbox("HelmCheek%d" % sg, (sg * 0.098, -0.04, SZ - 0.075), (0.02, 0.11, 0.13), steel, bottom=(1, 0.55), bevel=0.005,
             parent=o)
    tbox("HelmNasal", (0, -0.128, SZ - 0.04), (0.026, 0.014, 0.12), rust_d, bevel=0.004, parent=o)
    for k in range(4):
        limb("HelmPlume%d" % k, (0, -0.05 + k * 0.05, SZ + 0.12), (0, 0.02 + k * 0.07, SZ + 0.25 - k * 0.035), 0.034, 0.0, red,
             sides=4, flat=0.3, twist=PI / 2, parent=o)

    # --- peitoral e ombreiras de aço gasto, capa rasgada (cavaleiro)
    o = opt("Armor", (0, 0, 1.2), body)
    chest = [sec((0, -0.004, 1.0), 0.125, 0.105), sec((0, -0.008, 1.14), 0.165, 0.125, keel=0.07),
             sec((0, -0.006, 1.27), 0.17, 0.122, keel=0.07), sec((0, 0.0, 1.35), 0.13, 0.1)]
    loft("ArmorChest", chest, steel, o, sides=8, phase=0.0, arc=3.0, thick=0.016)
    loft("ArmorBack", grow(chest, add=0.002), rust_d, o, sides=6, arc=2.9, thick=0.016, fwd=(0, 1, 0))
    loft("ArmorTrim", grow(span(chest, 0.0, 0.1), add=0.008), rust_d, o, sides=8, phase=0.0, arc=3.05, thick=0.012)
    tbox("ArmorCrest", (0, -0.145, 1.2), (0.06, 0.012, 0.085), red, bottom=(0.2, 1), bevel=0.004, parent=o)
    for sg in (1, -1):
        dome("ArmorPauldron%d" % sg, (sg * 0.2, 0.0, SH - 0.005), (sg * 0.45, 0, 1), 0.1, 0.11, 0.095, steel, o, sides=8, lip=0.02)
        ring("ArmorPauldronTrim%d" % sg, SH - 0.02, 0.103, 0.02, rust_d, parent=o, sides=8, x=sg * 0.195)
    cloth("ArmorCape", 1.36, 0.42, 0.16, 0.27, 2.2, 2.6, [red, red_d], [(0.7, 0), (1.0, 1)], center=(0, 0.02), back=0.8,
          cols=7, folds=0.03, thick=0.012, parent=o)
    for k in range(3):
        a = (k - 1) * 0.6
        tbox("ArmorTasset%d" % k, (math.sin(a) * 0.135, -math.cos(a) * 0.1, HIP + 0.02), (0.095, 0.014, 0.15), steel if k == 1 else rust,
             bottom=(0.75, 1), bevel=0.005, rot=(0.1, 0, -a), parent=o)
    export("skeleton")


# ------------------------------------------------------------------ feras lisas (raptor, aranha)
# Peças em sloft (anime_body.py) com sombreado suave; o que fica preso na pele (dentes, olhos) é posto pela
# superfície do loft (fera_surf), para nascer do lugar certo.
def fera_dense(secs, n, cut=2):
    """Arredonda o caminho (corta os cantos, Chaikin) e reamostra em n anéis: a dobra do joelho e do
    pescoço vira curva, e a sombra em dois tons do toon não desenha quina."""
    for _ in range(cut):
        out = [secs[0]]
        for a, b in zip(secs, secs[1:]):
            out += [_mix(a, b, 0.25), _mix(a, b, 0.75)]
        secs = out + [secs[-1]]
    return [sample(secs, i / (n - 1)) for i in range(n)]

def fera_tip(name, p0, p1, r0, material, parent, sides=6, flat=1.0):
    """Ponta cônica lisa (espinho, dente, garra)."""
    return smooth_sharp(limb(name, p0, p1, r0, 0.0, material, sides=sides, flat=flat, parent=parent), 70.0)

def fera_curve(name, pts, r0, r1, material, parent, sides=8):
    """Tubo liso afinando por uma linha de pontos, fechado em ponta."""
    n = len(pts)
    secs = [sec(p, r0 + (r1 - r0) * i / (n - 1), r0 + (r1 - r0) * i / (n - 1)) for i, p in enumerate(pts)]
    return sloft(name, secs, material, parent, sides=sides, fwd=(0, 0, 1))

def fera_surf(secs, y, deg, out=0.0, tilt=False):
    """Ponto da superfície de um loft feito ao longo de Y (frente do anel para cima) na altura y, no ângulo
    deg do anel (0 = lado +X, 90 = em cima, -90 = embaixo); out empurra para fora (negativo: para dentro).
    tilt=True segue a inclinação do anel onde o loft sobe ou desce (dorso de sapo); sem ele, o anel é tomado
    como vertical (bom para peças quase retas)."""
    for a, b in zip(secs, secs[1:]):
        if min(a["c"].y, b["c"].y) <= y <= max(a["c"].y, b["c"].y):     # loft para a frente ou para trás
            d = b["c"].y - a["c"].y
            s = _mix(a, b, (y - a["c"].y) / d if abs(d) > 1e-6 else 0.0)
            t = (b["c"] - a["c"]).normalized()
            break
    else:
        s, t = secs[-1], Vector((0, -1, 0))
    r = math.radians(deg)
    k = s["fr"] if math.sin(r) > 0 else s["bk"]
    if not tilt:
        return Vector((math.cos(r) * (s["rx"] + out), y, s["c"].z + math.sin(r) * (s["ry"] * k + out)))
    f = Vector((0, 0, 1)) - t * t.z
    f.normalize()
    side = Vector((1, 0, 0))
    return s["c"] + side * (math.cos(r) * (s["rx"] + out)) + f * (math.sin(r) * (s["ry"] * k + out))


# ================================================================== RAPTOR-CAPIM
# Fera de duas patas dos campos (bando de 3). Corpo na horizontal, frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd: LegL, LegR, Body, Head, ArmL, ArmR e, só no raptor, Tail
# (dentro de Body) e Jaw (dentro de Head).
# Estilo toon liso: tudo em sloft (anime_body.py), sombreado suave com aresta só onde dobra muito; as listras e a
# barriga são faixas de material na mesma malha, não placas por cima.
def build_raptor():
    skin = mat("r_skin", hexc("#5F7A3E"), 0.85)
    skin_d = mat("r_skin_d", hexc("#3C5226"), 0.85)
    belly = mat("r_belly", hexc("#C9B88A"), 0.9)
    crest = mat("r_crest", hexc("#B8452A"), 0.8)
    crest_d = mat("r_crest_d", hexc("#7A2A1A"), 0.8)
    bone = mat("r_bone", hexc("#EFE6D0"), 0.6)
    claw = mat("r_claw", hexc("#2A2420"), 0.55)
    mouth = mat("r_mouth", hexc("#5A1814"), 0.9)
    eye = mat("r_eye_flat", (1.0, 0.8, 0.1), 0.4, 0.0, emit=(1.0, 0.65, 0.0), strength=3.0)
    pupil = mat("r_pupil_flat", hexc("#140E0A"), 0.4)
    up = (0, 0, 1)
    SIDES = 16
    TOP, BOTTOM = (2, 3, 4), (10, 11, 12)   # colunas de face (16 lados, frente do anel = para cima)
    dense, tip, curve, surf = fera_dense, fera_tip, fera_curve, fera_surf


    def bands(stripes, top=TOP, bottom=BOTTOM, belly_from=0):
        """matf: barriga clara embaixo e listras escuras no dorso nos segmentos de stripes."""
        def f(i, j):
            if j in bottom and i >= belly_from:
                return 2
            if j in top and i in stripes:
                return 1
            return 0
        return f



    root = empty("Raptor", (0, 0, 0))
    body = empty("Body", (0, 0.05, 0.8), root)

    # ---------------- tronco na horizontal: quadril alto, barriga funda, peito que sobe para o pescoço
    torso = dense([sec((0, 0.5, 0.89), 0.1, 0.1),
                   sec((0, 0.3, 0.87), 0.18, 0.19),
                   sec((0, 0.06, 0.84), 0.2, 0.21, bk=1.15),
                   sec((0, -0.18, 0.84), 0.18, 0.2, bk=1.2),
                   sec((0, -0.36, 0.9), 0.12, 0.14),
                   sec((0, -0.42, 0.95), 0.07, 0.08)], 18)
    sloft("Torso", torso, skin, body, sides=SIDES, fwd=up, mats=(skin_d, belly),
          matf=bands({4, 5, 8, 9, 12, 13}, belly_from=2))

    # ---------------- cauda grossa na base, fina e reta atrás (equilíbrio), em continuação do tronco
    tail = empty("Tail", (0, 0.42, 0.88), body)
    tsecs = dense([sec((0, 0.32, 0.88), 0.14, 0.14), sec((0, 0.72, 0.92), 0.085, 0.085),
                   sec((0, 1.08, 0.96), 0.055, 0.05), sec((0, 1.42, 0.98), 0.03, 0.027),
                   sec((0, 1.64, 0.99), 0.012, 0.011)], 18)
    sloft("TailMesh", tsecs, skin, tail, sides=12, fwd=up, mats=(skin_d, belly),
          matf=bands({4, 5, 8, 9, 12}, top=(1, 2, 3), bottom=(7, 8, 9)))

    # ---------------- crista de espinhos curvados para trás, do pescoço até a ponta da cauda
    ridge = [(-0.34, 1.02, 0.08), (-0.2, 1.04, 0.1), (-0.05, 1.04, 0.11), (0.1, 1.05, 0.1), (0.25, 1.04, 0.09),
             (0.4, 0.99, 0.075)]
    for k, (y, z, h) in enumerate(ridge):
        tip("Spike%d" % k, (0, y, z - 0.05), (0, y + 0.08, z + h * 0.75), 0.045, crest, body, flat=0.45)
    for k, (y, z, h) in enumerate(((0.62, 0.98, 0.06), (0.86, 0.99, 0.05), (1.1, 1.0, 0.04), (1.32, 0.99, 0.03))):
        tip("TailSpike%d" % k, (0, y, z - 0.03), (0, y + 0.06, z + h), 0.03, crest, tail, flat=0.45)

    # ---------------- pescoço e cabeça (cabeça baixa, focinho longo, mandíbula separada)
    head = empty("Head", (0, -0.36, 0.92), body)
    neck = dense([sec((0, -0.26, 0.88), 0.13, 0.14), sec((0, -0.46, 0.99), 0.09, 0.095),
                  sec((0, -0.58, 1.12), 0.08, 0.085)], 10)
    sloft("Neck", neck, skin, head, sides=SIDES, fwd=(0, -0.4, 1), mats=(skin_d, belly), matf=bands(set()))
    # Crânio e mandíbula: tudo o que fica na cabeça (dentes, lábio, olho, sobrancelha) é posto pela superfície do
    # crânio (surf), então nasce do lugar certo. A boca é a metade de baixo do crânio pintada de escuro (o lábio
    # onde os dentes nascem e o céu da boca); os dentes de cima descem por fora da mandíbula, que é mais estreita.
    skull = dense([sec((0, -0.5, 1.17), 0.075, 0.075),
                   sec((0, -0.6, 1.18), 0.095, 0.088, bk=0.8),
                   sec((0, -0.72, 1.17), 0.088, 0.075, bk=0.75),
                   sec((0, -0.86, 1.14), 0.064, 0.056, bk=0.7),
                   sec((0, -0.96, 1.12), 0.046, 0.044, bk=0.7),
                   sec((0, -1.0, 1.115), 0.03, 0.03, bk=0.8),
                   sec((0, -1.025, 1.112), 0.01, 0.01)], 18, cut=1)


    in_mouth = lambda i: skull[min(i, len(skull) - 1)]["c"].y < -0.6
    sloft("Skull", skull, skin, head, sides=SIDES, fwd=up, mats=(skin_d, mouth),
          matf=lambda i, j: 2 if (j in (9, 10, 11, 12, 13) and in_mouth(i)) else 1 if (j in TOP and i >= 6) else 0)
    # dentes de cima: nascem no lábio (40° abaixo do lado), descem retos e um pouco para fora, por fora da mandíbula
    for s in (1, -1):
        nm = "L" if s > 0 else "R"
        for k in range(6):
            y = -0.64 - 0.29 * k / 5
            p = surf(skull, y, -40, -0.004)
            p.x *= s
            ln = 0.036 - 0.012 * k / 5 + (0.008 if k == 1 else 0.0)      # o segundo é a presa maior
            tip("Tooth%s%d" % (nm, k), p, p + Vector((s * 0.006, 0.006, -ln)), 0.0105 - 0.003 * k / 5, bone, head)
    # olho amendoado em fenda, assentado no lado do crânio, sob uma sobrancelha óssea baixa
    for s, nm in ((1, "L"), (-1, "R")):
        e0, e1, e2 = surf(skull, -0.635, 14, -0.004), surf(skull, -0.665, 16, 0.004), surf(skull, -0.7, 12, -0.004)
        for e in (e0, e1, e2):
            e.x *= s
        sloft("Eye" + nm, [sec(e0, 0.003, 0.006), sec(e1, 0.008, 0.017), sec(e2, 0.003, 0.005)], eye, head, sides=8,
              fwd=(s, 0, 0.25))
        pc = surf(skull, -0.665, 16, 0.009)
        pc.x *= s
        sloft("Pupil" + nm, [sec(pc + Vector((0, 0.006, 0)), 0.002, 0.003), sec(pc, 0.003, 0.015),
                             sec(pc - Vector((0, 0.006, 0)), 0.002, 0.003)], pupil, head, sides=6, fwd=(s, 0, 0.25))
        brow = [surf(skull, y, d, -0.006) for y, d in ((-0.6, 42), (-0.655, 34), (-0.71, 28))]
        for b in brow:
            b.x *= s
        curve("Brow" + nm, brow, 0.02, 0.01, skin_d, head, sides=8)
    for k, (y, h) in enumerate(((-0.64, 0.1), (-0.56, 0.09), (-0.48, 0.07))):
        base = surf(skull, y, 90, -0.03) if y < -0.5 else Vector((0, y, 1.16))
        tip("HeadSpike%d" % k, base, base + Vector((0, 0.07, h)), 0.035, crest_d if k == 0 else crest, head,
            flat=0.45)

    # mandíbula: mais estreita que o crânio (os dentes de cima ficam por fora), encostada embaixo dele,
    # queixo redondo; o miolo de cima é boca (aparece quando abre) com a língua deitada nele
    jaw = empty("Jaw", (0, -0.56, 1.1), head)
    jraw = []
    for y, w, h in ((-0.52, 0.72, 0.04), (-0.62, 0.66, 0.034), (-0.74, 0.64, 0.03), (-0.86, 0.64, 0.026),
                    (-0.95, 0.66, 0.022), (-0.99, 0.6, 0.016), (-1.005, 0.4, 0.008)):
        bot = surf(skull, y, -90).z
        jraw.append(sec((0, y, bot - h * 0.8), surf(skull, y, 0).x * w, h, bk=1.25))
    jsecs = dense(jraw, 12, cut=1)
    sloft("JawMesh", jsecs, skin, jaw, sides=12, fwd=up, mats=(belly, mouth),
          matf=lambda i, j: 1 if j in (7, 8, 9) else 2 if (j in (1, 2, 3) and 1 <= i <= 10) else 0)
    sloft("Tongue", [sec(surf(jsecs, -0.6, 90, -0.012), 0.03, 0.01), sec(surf(jsecs, -0.78, 90, -0.01), 0.024, 0.009),
                     sec(surf(jsecs, -0.86, 90, -0.012), 0.01, 0.005)], mouth, jaw, sides=8, fwd=up)
    for s in (1, -1):   # dentes de baixo: escondidos com a boca fechada, aparecem no bote
        nm = "L" if s > 0 else "R"
        for k in range(4):
            y = -0.68 - 0.24 * k / 3
            p = surf(jsecs, y, 50, -0.004)
            p.x *= s
            tip("LowTooth%s%d" % (nm, k), p, p + Vector((-s * 0.002, 0.004, 0.026 - 0.006 * k / 3)), 0.008, bone, jaw)

    # ---------------- bracinhos dobrados com três garras
    for side, s in (("ArmL", 1), ("ArmR", -1)):
        x = s * 0.13
        arm = empty(side, (x, -0.3, 0.82), root)
        a0, a1 = Vector((x, -0.28, 0.85)), Vector((x + s * 0.045, -0.36, 0.69))
        a2 = Vector((x + s * 0.035, -0.48, 0.64))
        sloft(side + "_Mesh", dense([sec(a0, 0.055, 0.055), sec(a0.lerp(a1, 0.5), 0.045, 0.048),
                                     sec(a1, 0.032, 0.032), sec(a1.lerp(a2, 0.5), 0.03, 0.03),
                                     sec(a2, 0.028, 0.026)], 9), skin, arm, sides=10, fwd=(0, -1, 0))
        for k in range(3):
            d = (k - 1) * 0.02
            c0 = a2 + Vector((d, -0.01, 0))
            curve(side + "_Claw%d" % k, [c0, c0 + Vector((d * 0.3, -0.045, -0.015)),
                                         c0 + Vector((d * 0.5, -0.07, -0.055))], 0.012, 0.002, claw, arm, sides=6)

    # ---------------- pernas de ave numa peça só: coxa forte, joelho para a frente, tarso longo, garra em foice
    for side, s in (("LegL", 1), ("LegR", -1)):
        x = s * 0.13
        leg = empty(side, (x, 0.14, 0.8), root)
        hip, knee = Vector((x, 0.16, 0.84)), Vector((x + s * 0.01, -0.1, 0.5))
        ankle, foot = Vector((x - s * 0.01, 0.2, 0.2)), Vector((x - s * 0.01, 0.08, 0.06))
        lsecs = [sec(hip + Vector((0, 0.02, 0.05)), 0.07, 0.09),
                 sec(hip, 0.105, 0.145),
                 sec(hip.lerp(knee, 0.45), 0.09, 0.115, fr=0.9, bk=1.15),
                 sec(hip.lerp(knee, 0.85), 0.06, 0.068),
                 sec(knee + Vector((0, 0.005, -0.02)), 0.052, 0.056),
                 sec(knee.lerp(ankle, 0.35), 0.05, 0.055, bk=1.2),
                 sec(knee.lerp(ankle, 0.8), 0.036, 0.04),
                 sec(ankle, 0.034, 0.037),
                 sec(ankle.lerp(foot, 0.5), 0.031, 0.032),
                 sec(foot, 0.033, 0.03)]
        lsecs = dense(lsecs, 18)
        sloft(side + "_Mesh", lsecs, skin, leg, sides=14, fwd=(0, -1, 0), mats=(skin_d,),
              matf=lambda i, j: 1 if i >= 12 else 0)
        for k in range(2):   # dois dedos de apoio, com a unha preta curvada para o chão
            dx = s * (0.012 if k == 0 else -0.026)
            t0 = foot + Vector((dx, 0.02, -0.02))
            t1 = foot + Vector((dx * 1.6, -0.14, -0.035))
            sloft(side + "_Toe%d" % k, [sec(t0, 0.028, 0.026), sec(t0.lerp(t1, 0.6), 0.022, 0.019),
                                        sec(t1, 0.017, 0.015)], skin_d, leg, sides=8, fwd=up)
            curve(side + "_ToeClaw%d" % k, [t1 + Vector((0, 0.01, 0)), t1 + Vector((dx * 0.2, -0.045, -0.005)),
                                            t1 + Vector((dx * 0.3, -0.07, -0.03))], 0.016, 0.002, claw, leg, sides=6)
        # garra em foice no dedo de dentro, erguida do chão
        c0 = foot + Vector((-s * 0.03, 0.0, 0.0))
        c1 = c0 + Vector((-s * 0.005, -0.055, 0.06))
        curve(side + "_SickleToe", [c0, c0.lerp(c1, 0.5), c1], 0.024, 0.017, skin_d, leg, sides=8)
        curve(side + "_Sickle", [c1, c1 + Vector((0, -0.05, 0.03)), c1 + Vector((0, -0.1, 0.0)),
                                 c1 + Vector((0, -0.12, -0.05))], 0.017, 0.002, claw, leg, sides=6)
        tip(side + "_Heel", ankle + Vector((0, -0.01, 0.01)), ankle + Vector((0, 0.06, -0.03)), 0.028, skin_d, leg)

    # só dobra seca de verdade (ponta de espinho, garra) fica com aresta; joelho, tornozelo e focinho arredondam
    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("raptor")
    export("raptor")


# ================================================================== TECELÃ (aranha do bosque)
# Aranha grande da orla da floresta: cefalotórax baixo, abdômen enorme com marca vermelha, oito pernas altas
# com joelho acima do corpo, seis olhos vermelhos e quelíceras com presas de marfim. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (só a aranha): Body (corpo todo), Abdomen (dentro de Body),
# Head (quelíceras e palpos, dentro de Body) e Leg0L..Leg3L / Leg0R..Leg3R (as pernas, no quadril de cada uma;
# 0 é o par da frente).
SPIDER_LEGS = ((-0.3, -58.0), (-0.2, -24.0), (-0.08, 12.0), (0.02, 44.0))   # (y do quadril, ângulo da perna)


def build_spider():
    chit = mat("s_chitin", hexc("#3B2F3E"), 0.6)
    chit_d = mat("s_chitin_d", hexc("#241C27"), 0.6)
    chit_l = mat("s_chitin_l", hexc("#5A4760"), 0.6)     # quelíceras
    mark = mat("s_mark", hexc("#C23B4A"), 0.7)
    fang = mat("s_fang", hexc("#EFE6D0"), 0.5)
    eye = mat("s_eye_flat", (1.0, 0.12, 0.15), 0.3, 0.0, emit=(1.0, 0.05, 0.08), strength=3.5)
    up = (0, 0, 1)

    root = empty("Spider", (0, 0, 0))
    body = empty("Body", (0, 0, 0.5), root)

    # ---------------- cefalotórax: baixo e largo, afinando na frente onde ficam os olhos
    ceph = fera_dense([sec((0, 0.07, 0.5), 0.1, 0.085),
                       sec((0, -0.04, 0.52), 0.18, 0.13),
                       sec((0, -0.2, 0.53), 0.19, 0.135, bk=0.8),
                       sec((0, -0.33, 0.51), 0.15, 0.115, bk=0.8),
                       sec((0, -0.41, 0.49), 0.1, 0.085),
                       sec((0, -0.44, 0.483), 0.072, 0.062),
                       sec((0, -0.458, 0.479), 0.04, 0.035),
                       sec((0, -0.466, 0.478), 0.012, 0.012)], 16, cut=1)
    # sulco escuro no meio das costas e a fronte mais clara em volta dos olhos
    sloft("Ceph", ceph, chit, body, sides=14, fwd=up, mats=(chit_d,),
          matf=lambda i, j: 1 if (j == 2 and 2 <= i <= 9) else 0)
    # seis olhos: o par grande na frente, dois pares menores em cima e dos lados
    for k, (y, deg, r) in enumerate(((-0.415, 66, 0.024), (-0.415, 114, 0.024), (-0.385, 48, 0.016),
                                     (-0.385, 132, 0.016), (-0.35, 80, 0.014), (-0.35, 100, 0.014))):
        c = fera_surf(ceph, y, deg, 0.004)
        sloft("Eye%d" % k, [sec(c + Vector((0, 0.008, 0)), r * 0.5, r * 0.5), sec(c + Vector((0, -r * 0.3, 0)), r, r),
                            sec(c + Vector((0, -r * 0.75, 0)), r * 0.8, r * 0.8),
                            sec(c + Vector((0, -r * 1.0, 0)), r * 0.35, r * 0.35)], eye, body, sides=10, fwd=up)

    # ---------------- abdômen enorme, mais alto que o corpo, com a marca vermelha em divisas no dorso
    abd = empty("Abdomen", (0, 0.06, 0.52), body)
    asecs = fera_dense([sec((0, 0.02, 0.51), 0.075, 0.07),
                        sec((0, 0.12, 0.56), 0.25, 0.23),
                        sec((0, 0.36, 0.64), 0.32, 0.3, bk=0.85),
                        sec((0, 0.6, 0.63), 0.27, 0.26, bk=0.85),
                        sec((0, 0.77, 0.57), 0.15, 0.14),
                        sec((0, 0.83, 0.54), 0.05, 0.05),
                        sec((0, 0.845, 0.535), 0.012, 0.012)], 22, cut=1)
    sloft("AbdomenMesh", asecs, chit, abd, sides=16, fwd=up, mats=(chit_d,),
          matf=lambda i, j: 1 if (j in (10, 11, 12, 13) and 3 <= i <= 17) else 0)
    # marca vermelha em relevo liso assentado no dorso (borda limpa, sem degrau de face): duas divisas em V
    # apontando para a frente e uma gota atrás
    for k, y0 in enumerate((0.27, 0.43)):
        for s in (1, -1):
            pts = [fera_surf(asecs, y0 + 0.11 * u, 90 - s * 55 * u, -0.008) for u in (0.0, 0.35, 0.7, 1.0)]
            fera_curve("Mark%d%s" % (k, "L" if s > 0 else "R"), pts, 0.034, 0.014, mark, abd, sides=8)
    drop = [fera_surf(asecs, y, 90, -0.012) for y in (0.56, 0.6, 0.66, 0.7)]
    sloft("MarkDrop", [sec(drop[0], 0.012, 0.012), sec(drop[1], 0.045, 0.03), sec(drop[2], 0.04, 0.028),
                       sec(drop[3], 0.008, 0.008)], mark, abd, sides=10, fwd=up)
    for s in (1, -1):   # fiandeiras
        fera_tip("Spinner%s" % ("L" if s > 0 else "R"), (s * 0.025, 0.82, 0.53), (s * 0.04, 0.9, 0.49), 0.022,
                 chit_d, abd)
    for k, (y, deg) in enumerate(((0.3, 30), (0.3, 150), (0.5, 25), (0.5, 155), (0.66, 40), (0.66, 140))):
        p = fera_surf(asecs, y, deg, -0.01)   # cerdas duras nos flancos
        n = Vector((p.x, 0, p.z - 0.6)).normalized()
        fera_tip("Bristle%d" % k, p, p + n * 0.07 + Vector((0, 0.04, 0)), 0.014, chit_d, abd)

    # ---------------- quelíceras grossas com presas de marfim curvadas para dentro, e os palpos
    head = empty("Head", (0, -0.4, 0.44), body)
    for s, nm in ((1, "L"), (-1, "R")):
        c0 = fera_surf(ceph, -0.42, -60 if s > 0 else -120, -0.02)
        c1 = Vector((s * 0.055, -0.48, 0.38))
        c2 = Vector((s * 0.05, -0.5, 0.3))
        # quelícera e presa numa peça só (sem dois tubos se cruzando): a cor troca para marfim num anel limpo
        c3 = c2 + Vector((0, -0.004, -0.035))
        csecs = fera_dense([sec(c0, 0.05, 0.05), sec(c1, 0.048, 0.044), sec(c2, 0.038, 0.034), sec(c3, 0.026, 0.026),
                            sec(c3 + Vector((-s * 0.004, -0.008, -0.04)), 0.017, 0.017),
                            sec(c3 + Vector((-s * 0.026, -0.006, -0.075)), 0.009, 0.009),
                            sec(c3 + Vector((-s * 0.046, 0.016, -0.092)), 0.002, 0.002)], 16, cut=1)
        sloft("Chelicera" + nm, csecs, chit_l, head, sides=10, fwd=(0, -1, 0), mats=(fang,),
              matf=lambda i, j, cs=csecs, z=c3.z: 1 if cs[i]["c"].z < z else 0)
        p0 = fera_surf(ceph, -0.38, -25 if s > 0 else -155, -0.015)
        p1 = Vector((s * 0.17, -0.52, 0.44))
        p2 = Vector((s * 0.15, -0.6, 0.3))
        sloft("Palp" + nm, fera_dense([sec(p0, 0.028, 0.028), sec(p1, 0.024, 0.024), sec(p2, 0.02, 0.02),
                                       sec(p2 + Vector((0, -0.01, -0.03)), 0.008, 0.008)], 10),
              chit, head, sides=8, fwd=(0, -1, 0), mats=(chit_d,), matf=lambda i, j: 1 if i >= 6 else 0)

    # ---------------- oito pernas: sobem do quadril até o joelho acima do corpo e descem em arco até a ponta
    for k, (hy, ang) in enumerate(SPIDER_LEGS):
        for s, nm in ((1, "L"), (-1, "R")):
            hip = fera_surf(ceph, hy, 0 if s > 0 else 180, -0.03)
            leg = empty("Leg%d%s" % (k, nm), hip, root)
            a = math.radians(ang)
            d = Vector((s * math.cos(a), math.sin(a), 0))
            reach = 1.0 if k in (0, 3) else 0.9
            pts = [(hip, 0.052), (hip + d * 0.12 + Vector((0, 0, 0.12)), 0.05),
                   (hip + d * 0.36 * reach + Vector((0, 0, 0.4)), 0.042),
                   (hip + d * 0.6 * reach + Vector((0, 0, 0.16)), 0.034),
                   (hip + d * 0.8 * reach + Vector((0, 0, -0.28)), 0.024),
                   (Vector((hip.x, hip.y, 0)) + d * 0.88 * reach + Vector((0, 0, 0.015)), 0.012)]
            lsecs = fera_dense([sec(p, r, r) for p, r in pts], 16)
            # anéis escuros nas juntas (joelho e tornozelo) e a ponta preta
            sloft("Leg%d%s_Mesh" % (k, nm), lsecs, chit, leg, sides=8, fwd=up, mats=(chit_d,),
                  matf=lambda i, j: 1 if i in (5, 6, 10, 11) or i >= 14 else 0)

    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("spider")
    export("spider")


# ================================================================== CENTOPEIA DE TÚNEL (mina)
# Centopeia gigante das galerias: corpo comprido e baixo (~2,2 m) em gomos de quitina vermelho-ferrugem com placas
# escuras no dorso, oito pares de patas ocre, antenas longas e forcípulas (as "presas" da frente). Frente = -Y.
# Usa os MESMOS pivôs da tecelã para reaproveitar a animação dela (enemy.gd trata "centipede" como "spider"):
# Body (metade da frente; ao armar o bote ergue a cabeça), Abdomen (metade de trás, dentro de Body), Head
# (forcípulas e antenas, dentro de Body) e Leg0L..Leg3L / Leg0R..Leg3R (cada pivô leva dois pares de patas
# vizinhos; 0 é o da frente).
CENTI_SEGS = 9                                   # gomos, da cabeça (0) à cauda
CENTI_Y0, CENTI_Y1 = -0.95, 1.2                  # frente e trás do corpo
CENTI_LEG_Y = [-0.62, -0.38, -0.14, 0.1, 0.34, 0.58, 0.8, 1.0]   # um par de patas por gomo (sem a cabeça)


def _centi_secs(y0, y1, n_seg, z, rx, ry, taper_front=0.0, taper_back=0.0):
    """Seções de um trecho do corpo: cada gomo incha no meio e afina na junta (anel liso, sem degrau)."""
    secs = []
    steps = n_seg * 4
    for i in range(steps + 1):
        u = i / steps
        y = y0 + (y1 - y0) * u
        bulge = 0.86 + 0.14 * math.sin(math.pi * ((u * n_seg) % 1.0))
        tf = 1.0 - taper_front * max(0.0, 1.0 - u * 3.0)
        tb = 1.0 - taper_back * max(0.0, u * 3.0 - 2.0)
        k = bulge * tf * tb
        secs.append(sec((0, y, z), rx * k, ry * k, bk=0.75))
    return secs


def build_centipede():
    chit = mat("c_chitin", hexc("#8A3A22"), 0.55)
    chit_d = mat("c_chitin_d", hexc("#3E1A10"), 0.55)
    belly = mat("c_belly", hexc("#C98F45"), 0.7)
    leg_m = mat("c_leg", hexc("#D9A04E"), 0.6)
    tip_m = mat("c_tip", hexc("#2A140C"), 0.5)
    eye = mat("c_eye_flat", (1.0, 0.65, 0.1), 0.3, 0.0, emit=(1.0, 0.5, 0.05), strength=3.0)
    up = (0, 0, 1)
    Z = 0.24                                    # altura do eixo do corpo (rente ao chão)

    root = empty("Centipede", (0, 0, 0))
    body = empty("Body", (0, 0.2, Z), root)

    # ---------------- metade da frente (Body) e de trás (Abdomen): dois tubos que se encostam na junta y=0.2
    # 8 anéis por gomo (n = gomos * 8 + 1): a junta cai no anel múltiplo de 8 e a faixa escura do dorso
    # (metade de cima do anel) fica logo depois dela, uma por gomo
    front = fera_dense(_centi_secs(CENTI_Y0, 0.26, 5, Z, 0.17, 0.11, taper_front=0.45), 41, cut=1)
    sloft("BodyFront", front, chit, body, sides=14, fwd=up, mats=(chit_d, belly),
          matf=lambda i, j: 2 if j in (10, 11, 12) else (1 if 1 <= j <= 6 and i % 8 in (0, 1) else 0))
    abd = empty("Abdomen", (0, 0.2, Z), body)
    back = fera_dense(_centi_secs(0.14, CENTI_Y1, 4, Z, 0.165, 0.105, taper_back=0.6), 33, cut=1)
    sloft("BodyBack", back, chit, abd, sides=14, fwd=up, mats=(chit_d, belly),
          matf=lambda i, j: 2 if j in (10, 11, 12) else (1 if 1 <= j <= 6 and i % 8 in (0, 1) else 0))
    # dois cercos (gonópodes) na ponta da cauda, para trás
    for s, nm in ((1, "L"), (-1, "R")):
        p = fera_surf(back, CENTI_Y1 - 0.05, 0 if s > 0 else 180, -0.02)
        fera_curve("Cercus" + nm, [p, p + Vector((s * 0.06, 0.16, 0.02)), p + Vector((s * 0.1, 0.3, 0.0))],
                   0.025, 0.006, tip_m, abd, sides=6)

    # ---------------- cabeça: olhos âmbar, antenas longas e forcípulas em gancho
    head = empty("Head", (0, CENTI_Y0 + 0.12, Z), body)
    for s, nm in ((1, "L"), (-1, "R")):
        c = fera_surf(front, CENTI_Y0 + 0.1, 40 if s > 0 else 140, -0.006)
        sloft("Eye" + nm, [sec(c + Vector((0, 0.006, 0)), 0.01, 0.01), sec(c + Vector((0, -0.006, 0.004)), 0.02, 0.02),
                           sec(c + Vector((0, -0.016, 0.006)), 0.008, 0.008)], eye, head, sides=8, fwd=up)
        a0 = fera_surf(front, CENTI_Y0 + 0.05, 55 if s > 0 else 125, -0.01)
        fera_curve("Antenna" + nm, [a0, a0 + Vector((s * 0.08, -0.16, 0.12)), a0 + Vector((s * 0.2, -0.36, 0.16)),
                                    a0 + Vector((s * 0.32, -0.5, 0.1))], 0.016, 0.004, chit_d, head, sides=6)
        f0 = fera_surf(front, CENTI_Y0 + 0.08, -20 if s > 0 else -160, -0.02)
        fsecs = fera_dense([sec(f0, 0.035, 0.03), sec(f0 + Vector((s * 0.05, -0.1, -0.03)), 0.03, 0.026),
                            sec(f0 + Vector((s * 0.02, -0.2, -0.05)), 0.02, 0.018),
                            sec(f0 + Vector((-s * 0.04, -0.25, -0.05)), 0.008, 0.008),
                            sec(f0 + Vector((-s * 0.07, -0.25, -0.05)), 0.002, 0.002)], 12)
        sloft("Forcipule" + nm, fsecs, chit_d, head, sides=8, fwd=(0, -1, 0), mats=(tip_m,),
              matf=lambda i, j: 1 if i >= 7 else 0)

    # ---------------- oito pares de patas finas em arco até o chão; cada pivô LegN leva dois pares vizinhos
    pivots = {}
    for k, y in enumerate(CENTI_LEG_Y):
        g = k // 2
        secs_src = front if y < 0.2 else back
        for s, nm in ((1, "L"), (-1, "R")):
            hip = fera_surf(secs_src, y, -15 if s > 0 else -165, -0.025)
            name = "Leg%d%s" % (g, nm)
            leg = pivots.get(name)
            if leg is None:
                leg = pivots[name] = empty(name, hip, root)
            sweep = 0.06 * (1.5 - g)                # as da frente apontam um pouco para a frente
            pts = [(hip, 0.03), (hip + Vector((s * 0.14, -sweep * 0.5, 0.08)), 0.026),
                   (hip + Vector((s * 0.3, -sweep, 0.02)), 0.02),
                   (Vector((hip.x + s * 0.4, hip.y - sweep * 1.3, 0.012)), 0.01)]
            lsecs = fera_dense([sec(p, r, r) for p, r in pts], 12)
            sloft("Leg%d%s_Mesh" % (k, nm), lsecs, leg_m, leg, sides=8, fwd=up, mats=(tip_m,),
                  matf=lambda i, j: 1 if i >= 9 else 0)

    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("centipede")
    export("centipede")


# ================================================================== GOLEM DE CRISTAL (mina)
# Golem do Veio de Cristal (~2,4 m): tronco de rocha escura curvado para a frente, cabeça pequena afundada entre
# os ombros com olhos de cristal, braços enormes com punhos de pedra quase no chão e pernas curtas e grossas.
# Aglomerados de cristal ciano brotam dos ombros e das costas. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_golem): LegL, LegR (no quadril), Body (tronco), Head e
# ArmL/ArmR (no ombro, dentro de Body). Rotação x positiva leva perna/braço para trás.
def _vsurf(secs, z, deg, out=0.0):
    """Ponto da superfície de um loft vertical (ao longo de Z) na altura z: deg 0 = +X, 90 = frente (-Y),
    180 = -X, 270 = costas. out empurra para fora (negativo: para dentro)."""
    for a, b in zip(secs, secs[1:]):
        if a["c"].z <= z <= b["c"].z:
            s = _mix(a, b, (z - a["c"].z) / max(1e-6, b["c"].z - a["c"].z))
            break
    else:
        s = secs[-1]
    r = math.radians(deg)
    return Vector((s["c"].x + math.cos(r) * (s["rx"] + out), s["c"].y - math.sin(r) * (s["ry"] + out), z))


def _crystal(name, base, direction, length, r, mats, parent):
    """Cristal hexagonal: prisma que nasce de dentro da rocha e fecha em ponta (corpo claro, ponta mais escura)."""
    d = Vector(direction).normalized()
    p0 = Vector(base) - d * 0.05
    p1 = Vector(base) + d * length * 0.7
    p2 = Vector(base) + d * length
    sloft(name, [sec(p0, r, r), sec(p1, r * 0.95, r * 0.95), sec(p2, r * 0.05, r * 0.05)], mats[0], parent,
          sides=6, phase=0.0, fwd=(0, 0, 1) if abs(d.z) < 0.9 else (0, -1, 0), mats=(mats[1],),
          matf=lambda i, j: 1 if i >= 1 else 0)


def _rock(name, c, r, material, parent, squash=(1.0, 1.0, 1.0), sides=7, prof=None):
    """Pedra facetada: loft curto ao longo de Z com poucas faces (aresta viva entre elas = leitura de rocha)."""
    c = Vector(c)
    rx, ry, rz = r * squash[0], r * squash[1], r * squash[2]
    prof = prof or ((-1.0, 0.35), (-0.6, 0.85), (0.0, 1.0), (0.55, 0.88), (0.92, 0.45), (1.0, 0.08))
    secs = [sec(c + Vector((0, 0, rz * t)), rx * k, ry * k) for t, k in prof]
    return sloft(name, secs, material, parent, sides=sides, phase=0.0)


def build_golem():
    rock = mat("gm_rock", hexc("#5E5A58"), 0.92)
    rock_d = mat("gm_rock_d", hexc("#3A3634"), 0.92)
    rock_l = mat("gm_rock_l", hexc("#86807A"), 0.92)
    crys = mat("gm_crystal", hexc("#3FD2F2"), 0.25, 0.0, emit=(0.15, 0.8, 1.0), strength=2.4)
    crys_d = mat("gm_crystal_d", hexc("#1B78B8"), 0.25, 0.0, emit=(0.05, 0.45, 0.9), strength=1.8)
    eye = mat("gm_eye_flat", (0.6, 0.95, 1.0), 0.2, 0.0, emit=(0.4, 0.9, 1.0), strength=4.0)
    up = (0, 0, 1)
    HIP = 0.85

    root = empty("Golem", (0, 0, 0))

    # ---------------- tronco em triângulo invertido: cintura de pedra estreita, peito e ombros largos, corcunda
    body = empty("Body", (0, 0, HIP), root)
    torso = fera_dense([sec((0, 0.02, HIP - 0.12), 0.3, 0.26), sec((0, 0.0, HIP + 0.1), 0.4, 0.32),
                        sec((0, -0.04, 1.3), 0.6, 0.44), sec((0, -0.06, 1.62), 0.66, 0.46),
                        sec((0, -0.04, 1.86), 0.56, 0.42), sec((0, 0.0, 2.0), 0.34, 0.3),
                        sec((0, 0.02, 2.06), 0.06, 0.06)], 14, cut=1)
    sloft("Torso", torso, rock, body, sides=9, phase=0.0, mats=(rock_d,),
          matf=lambda i, j: 1 if j in (3, 4, 5) and i < 5 else 0)
    # bacia de pedra onde as pernas entram
    _rock("Pelvis", (0, 0.02, HIP - 0.06), 0.42, rock_d, body, squash=(1.0, 0.8, 0.45), sides=8)
    # placas do peito (duas lajes claras inclinadas) e laje da barriga, meio enterradas no tronco
    for s in (1, -1):
        p = _vsurf(torso, 1.48, 90 - s * 32, -0.06)
        _rock("Pec%d" % (0 if s > 0 else 1), p, 0.24, rock_l, body, squash=(1.2, 0.45, 0.7), sides=6)
    _rock("Belly", _vsurf(torso, 1.08, 90, -0.06), 0.2, rock_l, body, squash=(1.1, 0.4, 0.75), sides=6)
    # veios de cristal rachando o peito
    for k, pts in enumerate((((1.7, 70), (1.52, 82), (1.3, 76), (1.12, 86)), ((1.66, 112), (1.45, 104), (1.24, 112)))):
        fera_curve("Vein%d" % k, [_vsurf(torso, z, d, 0.004) for z, d in pts], 0.022, 0.012, crys, body, sides=5)

    # ---------------- cabeça pequena e afundada, mandíbula saliente, sobrancelha grossa e olhos de cristal
    head = empty("Head", (0, -0.36, 1.86), body)
    _rock("HeadMesh", (0, -0.42, 1.9), 0.21, rock_d, head, squash=(1.0, 0.95, 0.85), sides=7)
    _rock("Jaw", (0, -0.5, 1.77), 0.17, rock, head, squash=(1.25, 0.8, 0.5), sides=6)
    _rock("Brow", (0, -0.55, 1.99), 0.14, rock_l, head, squash=(1.7, 0.5, 0.35), sides=6)
    for s in (1, -1):
        c = Vector((s * 0.085, -0.6, 1.92))
        sloft("Eye%d" % (0 if s > 0 else 1), [sec(c + Vector((0, 0.05, 0)), 0.02, 0.02), sec(c, 0.042, 0.036),
                                              sec(c + Vector((0, -0.025, 0)), 0.03, 0.025),
                                              sec(c + Vector((0, -0.035, 0)), 0.005, 0.005)], eye, head, sides=8, fwd=up)

    # ---------------- pernas curtas em coluna, mais largas embaixo, pé de laje
    for side, x in (("LegL", 0.24), ("LegR", -0.24)):
        s = 1 if x > 0 else -1
        leg = empty(side, (x, 0, HIP), root)
        lsecs = [sec((x, 0.0, HIP + 0.05), 0.2, 0.2), sec((x + s * 0.03, -0.02, 0.55), 0.21, 0.21),
                 sec((x + s * 0.05, 0.0, 0.25), 0.25, 0.25), sec((x + s * 0.05, 0.0, 0.12), 0.26, 0.26)]
        sloft(side + "_Mesh", lsecs, rock, leg, sides=7, phase=0.0)
        _rock(side + "_Knee", (x + s * 0.03, -0.14, 0.52), 0.13, rock_l, leg, squash=(1.0, 0.7, 1.0), sides=6)
        _rock(side + "_Foot", (x + s * 0.05, -0.08, 0.1), 0.3, rock_d, leg, squash=(1.0, 1.25, 0.36), sides=7)

    # ---------------- braços de gorila: pedra do ombro cravada no tronco, braço fino, cotovelo, antebraço grosso e
    # punho enorme. O pivô fica DENTRO do tronco: girando, a pedra do ombro continua enterrada no corpo.
    arms = {}
    for side, x in (("ArmL", 0.66), ("ArmR", -0.66)):
        s = 1 if x > 0 else -1
        arm = arms[side] = empty(side, (s * 0.45, -0.04, 1.68), body)
        _rock(side + "_Shoulder", (x, -0.04, 1.7), 0.34, rock, arm, squash=(1.0, 0.95, 0.85), sides=7)
        _rock(side + "_ShoulderCap", (x + s * 0.06, -0.04, 1.86), 0.24, rock_l, arm, squash=(1.0, 0.95, 0.55), sides=6)
        elbow = Vector((x + s * 0.14, -0.08, 1.18))
        sloft(side + "_Upper", [sec((x + s * 0.04, -0.05, 1.62), 0.17, 0.17), sec(elbow + Vector((0, 0, 0.1)), 0.15, 0.15),
                                sec(elbow, 0.15, 0.15)], rock, arm, sides=7, phase=0.0)
        _rock(side + "_Elbow", elbow, 0.19, rock_d, arm, sides=7)
        wrist = Vector((x + s * 0.16, -0.18, 0.62))
        sloft(side + "_Fore", [sec(elbow, 0.2, 0.2), sec(elbow.lerp(wrist, 0.5), 0.26, 0.26), sec(wrist, 0.27, 0.26)],
              rock, arm, sides=7, phase=0.0)
        _rock(side + "_Bracer", elbow.lerp(wrist, 0.55) + Vector((s * 0.12, -0.08, 0)), 0.2, rock_l, arm,
              squash=(0.5, 0.9, 1.3), sides=6)
        fist_c = Vector((x + s * 0.16, -0.22, 0.42))
        _rock(side + "_Fist", fist_c, 0.3, rock_d, arm, squash=(1.0, 1.05, 0.85), sides=7)
        for k, dx in enumerate((-0.13, 0.0, 0.13)):   # nós dos dedos para a frente e para baixo
            _rock(side + "_Knuckle%d" % k, fist_c + Vector((dx, -0.24, -0.1)), 0.1, rock, arm, sides=6)

    # ---------------- cristais: aglomerado grande no ombro direito, menor no esquerdo, e na corcunda
    for side, s, big in (("ArmR", -1, True), ("ArmL", 1, False)):
        base = Vector((s * 0.72, -0.04, 1.9))
        spec = ((((0.3, 0.0, 1.0), 0.75, 0.12), ((0.7, 0.2, 0.7), 0.55, 0.09), ((0.5, -0.4, 0.8), 0.5, 0.085),
                 ((0.9, 0.3, 0.3), 0.4, 0.07)) if big else
                (((0.4, 0.1, 1.0), 0.5, 0.09), ((0.8, -0.2, 0.5), 0.36, 0.07)))
        for k, (d, ln, rr) in enumerate(spec):
            _crystal("%s_Crystal%d" % (side, k), base, (s * d[0], d[1], d[2]), ln, rr, (crys, crys_d), arms[side])
    for k, (z, dx, ln, rr) in enumerate(((1.9, 0.0, 0.6, 0.1), (1.76, 0.2, 0.42, 0.075), (1.72, -0.22, 0.48, 0.08),
                                         (1.5, 0.1, 0.34, 0.065), (1.42, -0.12, 0.3, 0.06))):
        base = _vsurf(torso, z, 270, -0.04) + Vector((dx, 0, 0))
        _crystal("BackCrystal%d" % k, base, (dx * 1.5, 0.75, 0.65), ln, rr, (crys, crys_d), body)

    # rocha facetada: aresta viva entre as faces (35°), em vez do liso das feras
    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 35.0)
    loose_parts("golem")
    export("golem")


# ================================================================== TOUPEIRA-BROCA (mina)
# Toupeira grande dos fossos (~1,4 m), curvada para a frente: corpo em pera de pelo cinza-escuro com barriga clara,
# pernas curtas, braços de cavar com mãos em pá e garras enormes, focinho comprido que termina numa broca de
# metal enferrujado em espiral e óculos de mineiro na testa. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_mole): LegL, LegR (no quadril, dentro do corpo), Body,
# Head (focinho, dentro de Body), Drill (a broca, dentro de Head; gira no eixo do focinho) e ArmL/ArmR (no ombro,
# DENTRO do tronco: o ombro é uma massa de pelo enterrada no corpo, então o braço não se solta ao girar).
def build_mole():
    fur = mat("ml_fur", hexc("#4A4442"), 0.95)
    fur_d = mat("ml_fur_d", hexc("#2E2928"), 0.95)
    belly = mat("ml_belly", hexc("#8C7F76"), 0.95)
    skin = mat("ml_skin", hexc("#D98C8C"), 0.8)          # palmas e nariz
    claw = mat("ml_claw", hexc("#E8DCC0"), 0.6)
    rust = mat("ml_rust", hexc("#9A5A2E"), 0.55, 0.6)
    rust_d = mat("ml_rust_d", hexc("#5E331A"), 0.6, 0.6)
    steel = mat("ml_steel", hexc("#9097A0"), 0.4, 0.8)
    lens = mat("ml_lens", hexc("#F2C04A"), 0.2, 0.0, emit=(1.0, 0.7, 0.2), strength=1.5)
    lea = mat("ml_leather", hexc("#5A3A20"), 0.85)
    up = (0, 0, 1)
    HIP = 0.38

    root = empty("Mole", (0, 0, 0))

    # ---------------- corpo em pera, curvado para a frente; barriga clara na frente
    body = empty("Body", (0, 0, HIP), root)
    torso = fera_dense([sec((0, 0.04, 0.16), 0.3, 0.28), sec((0, 0.0, 0.42), 0.46, 0.42),
                        sec((0, -0.06, 0.72), 0.44, 0.38), sec((0, -0.14, 0.98), 0.34, 0.3),
                        sec((0, -0.2, 1.14), 0.2, 0.19), sec((0, -0.22, 1.2), 0.05, 0.05)], 24, cut=2)
    sloft("Torso", torso, fur, body, sides=24, sharp=80.0)
    # barriga clara: elipsoide liso e denso, só a frente para fora do corpo
    fy = _vsurf(torso, 0.6, 90).y
    _blob("Belly", (0, fy + 0.22, 0.6), 0.3, 0.24, 0.36, belly, body, sides=24, rings=14)
    for k, (z, dx) in enumerate(((1.05, 0.0), (0.92, 0.12), (0.92, -0.12), (0.78, 0.0))):   # tufos nas costas
        p = _vsurf(torso, z, 270, -0.03) + Vector((dx, 0, 0))
        fera_tip("Tuft%d" % k, p, p + Vector((dx * 0.6, 0.14, 0.08)), 0.05, fur_d, body)

    # ---------------- cabeça: focinho comprido para a frente, nariz rosado em volta da broca, óculos na testa
    head = empty("Head", (0, -0.24, 1.04), body)
    snout = fera_dense([sec((0, -0.14, 1.06), 0.24, 0.23), sec((0, -0.32, 1.06), 0.22, 0.2),
                        sec((0, -0.5, 1.03), 0.15, 0.13), sec((0, -0.6, 1.01), 0.12, 0.11)], 12)
    sloft("Snout", snout, fur, head, sides=14, fwd=up)
    sloft("Nose", [sec((0, -0.57, 1.01), 0.125, 0.115), sec((0, -0.63, 1.01), 0.14, 0.13),
                   sec((0, -0.66, 1.01), 0.11, 0.1)], skin, head, sides=14, fwd=up)
    for s in (1, -1):   # olhinhos quase escondidos
        c = fera_surf(snout, -0.36, 90 - s * 45, -0.004)
        sloft("Eye%d" % (0 if s > 0 else 1), [sec(c + Vector((0, 0.01, 0)), 0.012, 0.012), sec(c, 0.022, 0.02),
                                              sec(c + Vector((0, -0.012, 0)), 0.006, 0.006)],
              mat("ml_eye_flat", hexc("#120C0A"), 0.3), head, sides=8, fwd=up)
    # óculos de mineiro na testa: tira de couro em volta da cabeça e duas lentes âmbar em aros de metal
    sloft("GoggleStrap", fera_dense([sec(fera_surf(snout, -0.16, a, 0.012), 0.03, 0.022)
                                     for a in (200, 160, 120, 90, 60, 20, -20)], 14), lea, head, sides=6, fwd=up)
    for s in (1, -1):
        c = fera_surf(snout, -0.22, 90 - s * 28, 0.02)
        sloft("GoggleRim%d" % (0 if s > 0 else 1), [sec(c + Vector((0, 0.03, -0.01)), 0.055, 0.055),
                                                    sec(c + Vector((0, -0.01, 0.0)), 0.06, 0.06),
                                                    sec(c + Vector((0, -0.02, 0.0)), 0.05, 0.05)], steel, head, sides=10,
              fwd=up)
        sloft("GoggleLens%d" % (0 if s > 0 else 1), [sec(c + Vector((0, -0.015, 0)), 0.045, 0.045),
                                                     sec(c + Vector((0, -0.028, 0)), 0.035, 0.035)], lens, head, sides=10,
              fwd=up)
    # broca: cone de metal enferrujado com rosca em espiral, encaixada num colar de aço dentro do nariz
    drill = empty("Drill", (0, -0.62, 1.01), head)
    sloft("DrillCollar", [sec((0, -0.6, 1.01), 0.1, 0.1), sec((0, -0.68, 1.01), 0.11, 0.11)], steel, drill, sides=10,
          fwd=up)
    sloft("DrillCone", [sec((0, -0.66, 1.01), 0.1, 0.1), sec((0, -0.82, 1.01), 0.065, 0.065),
                        sec((0, -0.98, 1.01), 0.008, 0.008)], rust, drill, sides=10, fwd=up)
    helix = []
    for i in range(22):
        u = i / 21
        a = u * 3.2 * 2 * math.pi
        y = -0.67 - u * 0.29
        r = (0.1 + (0.008 - 0.1) * (u * 0.29 / 0.32)) + 0.012
        helix.append(Vector((math.cos(a) * r, y, 1.01 + math.sin(a) * r)))
    fera_curve("DrillThread", helix, 0.018, 0.006, rust_d, drill, sides=5)

    # ---------------- pernas em dois ossos: coxa (LegL/LegR, no quadril dentro do corpo) e canela + pé (KneeL/KneeR).
    # Cada osso é um tubo liso; o joelho é uma junta redonda que cobre a dobra.
    for side, x in (("LegL", 0.2), ("LegR", -0.2)):
        s = 1 if x > 0 else -1
        k_side = "Knee" + side[-1]
        leg = empty(side, (x, 0.02, HIP), root)
        knee = Vector((x + s * 0.06, -0.05, 0.22))
        thigh = fera_dense([sec((x, 0.02, HIP + 0.16), 0.16, 0.16), sec((x + s * 0.04, -0.02, 0.36), 0.165, 0.16),
                            sec(knee + Vector((0, 0, 0.04)), 0.125, 0.125), sec(knee, 0.12, 0.12)], 14, cut=2)
        sloft(side + "_Thigh", thigh, fur, leg, sides=16, sharp=80.0)
        _blob(side + "_KneeJoint", knee, 0.125, 0.125, 0.125, fur, leg)
        shin_p = empty(k_side, tuple(knee), leg)
        ankle = Vector((x + s * 0.07, -0.02, 0.08))
        shin = fera_dense([sec(knee + Vector((0, 0, 0.02)), 0.118, 0.118), sec(knee.lerp(ankle, 0.5), 0.11, 0.11),
                           sec(ankle, 0.095, 0.095)], 12, cut=2)
        sloft(side + "_Shin", shin, fur, shin_p, sides=16, sharp=80.0)
        foot = fera_dense([sec(ankle + Vector((0, 0.06, -0.01)), 0.08, 0.05), sec(ankle + Vector((0, -0.04, -0.025)), 0.12, 0.06),
                           sec(ankle + Vector((0, -0.15, -0.035)), 0.1, 0.045),
                           sec(ankle + Vector((0, -0.18, -0.037)), 0.05, 0.025)], 12, cut=2)
        sloft(side + "_Foot", foot, skin, shin_p, sides=14, fwd=up, sharp=80.0)
        for k, dx in enumerate((-0.06, 0.0, 0.06)):
            t0 = ankle + Vector((dx, -0.17, -0.035))
            fera_curve("%s_Toe%d" % (side, k), [t0 + Vector((0, 0.03, 0)), t0 + Vector((0, -0.05, -0.005)),
                                                t0 + Vector((0, -0.09, -0.04))], 0.022, 0.004, claw, shin_p, sides=6)

    # ---------------- braços de cavar em dois ossos: braço (ArmL/ArmR, pivô dentro do tronco; o tubo nasce de dentro
    # do corpo e incha no ombro) e antebraço + mão (ElbowL/ElbowR). Antebraço e mão-pá são UMA malha lisa (pelo até
    # o pulso, pele na palma); o cotovelo é uma junta redonda que cobre a dobra.
    for side, x in (("ArmL", 0.34), ("ArmR", -0.34)):
        s = 1 if x > 0 else -1
        arm = empty(side, (s * 0.24, -0.1, 0.84), body)
        elbow = Vector((s * 0.5, -0.3, 0.66))
        upper = fera_dense([sec((s * 0.14, -0.06, 0.9), 0.15, 0.15), sec((s * 0.34, -0.12, 0.85), 0.175, 0.17),
                            sec((s * 0.45, -0.21, 0.76), 0.145, 0.14), sec(elbow, 0.12, 0.12)], 16, cut=2)
        sloft(side + "_Upper", upper, fur, arm, sides=16, sharp=80.0)
        _blob(side + "_ElbowJoint", elbow, 0.127, 0.127, 0.127, fur, arm)
        fore_p = empty("Elbow" + side[-1], tuple(elbow), arm)
        wrist = Vector((s * 0.49, -0.5, 0.56))
        palm = Vector((s * 0.5, -0.61, 0.52))
        fore = fera_dense([sec(elbow + Vector((0, 0.02, 0.01)), 0.118, 0.118), sec(elbow.lerp(wrist, 0.5), 0.13, 0.125),
                           sec(wrist, 0.105, 0.095), sec(palm, 0.17, 0.07),
                           sec(palm + Vector((0, -0.08, -0.03)), 0.15, 0.05),
                           sec(palm + Vector((0, -0.105, -0.04)), 0.09, 0.03)], 20, cut=2)
        sloft(side + "_Fore", fore, fur, fore_p, sides=16, fwd=up, mats=(skin,), sharp=80.0,
              matf=lambda i, j, cs=fore, wy=wrist.y + 0.02: 1 if cs[i]["c"].y < wy else 0)
        for k, dx in enumerate((-0.1, -0.035, 0.035, 0.1)):
            c0 = palm + Vector((dx, -0.07, -0.03))
            fera_curve("%s_Claw%d" % (side, k), [c0 + Vector((0, 0.03, 0)), c0 + Vector((dx * 0.2, -0.12, -0.02)),
                                                 c0 + Vector((dx * 0.3, -0.22, -0.1)),
                                                 c0 + Vector((dx * 0.3, -0.25, -0.18))], 0.035, 0.006, claw, fore_p,
                       sides=8)

    # tudo liso: aresta viva só em dobra muito fechada (ponta de garra, aro dos óculos)
    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("mole")
    export("mole")


def _blob(name, c, rx, ry, rz, material, parent, sides=18, rings=10):
    """Elipsoide liso e denso (junta de cotovelo/joelho, barriga): borda limpa onde cruza outra malha."""
    c = Vector(c)
    secs = []
    for i in range(rings + 1):
        a = -math.pi / 2 + math.pi * i / rings
        k = max(0.02, math.cos(a))
        secs.append(sec(c + Vector((0, 0, rz * math.sin(a))), rx * k, ry * k))
    return sloft(name, secs, material, parent, sides=sides, sharp=89.0)


# ================================================================== MÃE-VERME DAS PROFUNDEZAS (chefe da mina)
# Verme gigante (~4,4 m fora do chão) que sai de um anel de terra revirada: corpo em gomos de couro marrom com
# sulcos escuros, couraça de placas de pedra e cristais ciano no dorso, pescoço que se curva para a frente e uma
# boca redonda que abre em cinco pétalas, com três anéis de dentes descendo pela garganta. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (_animate_worm), dois ossos de corpo como os membros:
# Body (trecho de baixo; sobe do chão ao emergir), Neck (trecho de cima, dentro de Body; a emenda fica sob o colar
# de pedra e os dois tubos se cruzam por dentro), Head (a boca, dentro de Neck) e Jaw (as pétalas; abre por escala).
WORM_SEG = 0.44        # altura de um gomo


def _worm_secs(path, r0, r1, n, seg_len, phase=0.0):
    """Seções de um tubo em gomos ao longo de path(u) -> Vector (u de 0 a 1): o raio vai de r0 a r1 e incha no meio
    de cada gomo (sulco liso na junta). Devolve (seções, lista 'é sulco' por anel)."""
    secs, groove = [], []
    length = 0.0
    prev = path(0.0)
    for i in range(n + 1):
        u = i / n
        p = path(u)
        length += (p - prev).length
        prev = p
        w = (length / seg_len + phase) % 1.0
        bulge = 0.9 + 0.1 * math.sin(math.pi * w)
        r = (r0 + (r1 - r0) * u) * bulge
        secs.append(sec(p, r, r * 0.96))
        groove.append(w < 0.12 or w > 0.88)
    return secs, groove


def _rune(name, c, out, size, material, parent):
    """Runa acesa (um "V" com uma barra em cima) desenhada na face de uma placa que olha para `out`."""
    out = Vector(out).normalized()
    side = Vector((1, 0, 0))
    up = out.cross(side).normalized()
    c = Vector(c) - out * 0.03
    v = [c + side * -size + up * size * 0.6, c + up * -size * 0.7, c + side * size + up * size * 0.6]
    fera_curve(name + "V", v, 0.05, 0.045, material, parent, sides=6)
    fera_curve(name + "Bar", [c + side * -size * 0.55 + up * size * 0.85, c + side * size * 0.55 + up * size * 0.85],
               0.045, 0.045, material, parent, sides=6)


def build_worm():
    skin = mat("wv_skin", hexc("#7A5E4C"), 0.8)
    skin_d = mat("wv_skin_d", hexc("#4A3428"), 0.85)
    lip = mat("wv_lip", hexc("#B07A6A"), 0.7)
    gum = mat("wv_gum", hexc("#7A2630"), 0.7)
    throat = mat("wv_throat_flat", hexc("#2A0C10"), 0.9)
    throat.use_backface_culling = False      # a garganta é vista por dentro: dupla face no glTF
    tooth = mat("wv_tooth", hexc("#EFE6D0"), 0.5)
    stone = mat("wv_stone", hexc("#5E5A58"), 0.92)
    stone_l = mat("wv_stone_l", hexc("#86807A"), 0.92)
    dirt = mat("wv_dirt", hexc("#4A3524"), 1.0)
    crys = mat("wv_crystal", hexc("#3FD2F2"), 0.25, 0.0, emit=(0.15, 0.8, 1.0), strength=2.4)
    crys_d = mat("wv_crystal_d", hexc("#1B78B8"), 0.25, 0.0, emit=(0.05, 0.45, 0.9), strength=1.8)
    eye = mat("wv_eye_flat", hexc("#FFB23A"), 0.3, 0.0, emit=(1.0, 0.6, 0.1), strength=3.0)
    rune = mat("wv_rune_flat", hexc("#7FE8F5"), 0.3, 0.0, emit=(0.2, 0.85, 1.0), strength=2.6)
    up = (0, 0, 1)

    root = empty("Worm", (0, 0, 0))

    # ---------------- terra revirada em volta da base (fica no chão; o corpo sobe por dentro dela)
    # anel irregular: montes de terra de tamanhos diferentes, encavalados, mais altos junto do corpo
    _blob("Mound", (0, 0.0, -0.05), 1.25, 1.2, 0.3, dirt, root, sides=24, rings=10)
    for k in range(9):
        a = k / 9 * 2 * math.pi + 0.3
        rr = 1.05 + 0.18 * math.sin(k * 2.3)
        size = 0.42 + 0.12 * math.sin(k * 1.7)
        _blob("Heap%d" % k, (math.cos(a) * rr, math.sin(a) * rr, 0.0), size * 1.2, size, size * (0.55 + 0.2 * (k % 2)),
              dirt, root, sides=14, rings=8)
    for k in range(6):
        a = k / 6 * 2 * math.pi + 0.9
        _rock("Clod%d" % k, (math.cos(a) * 1.15, math.sin(a) * 1.12, 0.14), 0.2 - 0.03 * (k % 3), stone, root,
              squash=(1.0, 0.9, 0.6), sides=7)

    # ---------------- trecho de baixo (Body): quase reto, leve inclinação para a frente
    body = empty("Body", (0, 0, 0), root)
    low_path = lambda u: Vector((0.0, 0.1 - 0.15 * u, -0.5 + 2.75 * u))
    low, low_g = _worm_secs(low_path, 0.82, 0.76, 40, WORM_SEG)
    sloft("BodyLow", low, skin, body, sides=22, mats=(skin_d,), sharp=80.0,
          matf=lambda i, j, g=low_g: 1 if g[i] else 0)

    # ---------------- trecho de cima (Neck): começa DENTRO do de baixo e se curva para a frente até a boca
    neck_base = Vector((0.0, -0.05, 2.0))
    neck = empty("Neck", tuple(neck_base), body)
    up_path = lambda u: Vector((0.0, -0.02 - 1.0 * u * u, 1.8 + 2.0 * u - 0.25 * u * u))
    upp, up_g = _worm_secs(up_path, 0.74, 0.64, 40, WORM_SEG, phase=0.5)
    sloft("BodyUp", upp, skin, neck, sides=22, mats=(skin_d,), sharp=80.0, caps=(True, False),
          matf=lambda i, j, g=up_g: 1 if g[i] else 0)
    # colar de pedra cobrindo a emenda dos dois ossos (no osso de baixo: o de cima gira por dentro dele)
    _blob("Collar", (0, -0.06, 2.05), 0.9, 0.86, 0.2, stone, body, sides=24, rings=8)

    # ---------------- boca: o fim do tubo abre em funil (garganta escura), lábio grosso, dentes e pétalas
    top = up_path(1.0)
    tan = (up_path(1.0) - up_path(0.97)).normalized()
    head = empty("Head", tuple(top), neck)
    mouth_c = top + tan * 0.32
    sloft("HeadFlare", [sec(top - tan * 0.15, 0.66, 0.64), sec(top + tan * 0.12, 0.72, 0.7),
                        sec(mouth_c, 0.8, 0.78)], skin, head, sides=22, axis=tuple(tan), caps=(False, False), sharp=80.0)
    sloft("Lip", [sec(mouth_c - tan * 0.04, 0.82, 0.8), sec(mouth_c + tan * 0.06, 0.86, 0.84),
                  sec(mouth_c + tan * 0.1, 0.78, 0.76), sec(mouth_c + tan * 0.06, 0.66, 0.64)], lip, head, sides=22,
          axis=tuple(tan), caps=(False, False), sharp=80.0)
    # garganta: funil escuro descendo para dentro do pescoço (o que se vê ao olhar a boca)
    sloft("Throat", [sec(mouth_c + tan * 0.06, 0.68, 0.66), sec(mouth_c - tan * 0.3, 0.45, 0.43),
                     sec(mouth_c - tan * 0.7, 0.12, 0.12)], throat, head, sides=20, axis=tuple(tan), caps=(False, True),
          sharp=80.0)
    # três anéis de dentes descendo pela garganta, apontando para o centro
    side_v = Vector((1, 0, 0))
    up_v = tan.cross(side_v).normalized()
    for ring_i, (depth, rr, n, ln) in enumerate(((0.0, 0.64, 12, 0.2), (-0.18, 0.52, 10, 0.16), (-0.36, 0.38, 8, 0.12))):
        for t in range(n):
            a = t / n * 2 * math.pi + ring_i * 0.25
            radial = side_v * math.cos(a) + up_v * math.sin(a)
            base = mouth_c + tan * depth + radial * rr
            fera_tip("Tooth%d_%d" % (ring_i, t), base + radial * 0.03, base - radial * ln + tan * 0.05, 0.045, tooth,
                     head, sides=6)
    # pétalas: cinco abas grossas saindo do lábio, curvadas para fora (no Jaw: abrem pela escala)
    # coroa de cristais em volta da boca (no Head: não abre com as pétalas) e seis olhos acesos logo abaixo do lábio
    for t in range(8):
        a = t / 8 * 2 * math.pi + math.pi / 8
        radial = side_v * math.cos(a) + up_v * math.sin(a)
        base = mouth_c - tan * 0.12 + radial * 0.74
        _crystal("Crown%d" % t, base, tuple(radial * 0.75 + tan * 0.65), 0.8 if t % 2 else 0.58, 0.1 if t % 2 else 0.08,
                 (crys, crys_d), head)
    for t in range(6):
        a = math.pi * (1.15 + t * 0.14)            # na metade de baixo da boca, virados para a frente
        radial = side_v * math.cos(a) + up_v * math.sin(a)
        c = mouth_c - tan * 0.22 + radial * 0.7
        _blob("Eye%d" % t, c, 0.115, 0.115, 0.115, eye, head, sides=14, rings=8)
    jaw = empty("Jaw", tuple(mouth_c), head)
    for t in range(5):
        a = t / 5 * 2 * math.pi + math.pi / 2
        radial = side_v * math.cos(a) + up_v * math.sin(a)
        # aba larga e fina (como pétala de flor carnívora): nasce dentro do lábio, sobe e vira para fora
        p0 = mouth_c + radial * 0.66
        p1 = p0 + radial * 0.14 + tan * 0.3
        p2 = p1 + radial * 0.26 + tan * 0.14
        p3 = p2 + radial * 0.2 - tan * 0.04
        psecs = fera_dense([sec(p0, 0.34, 0.07), sec(p1, 0.36, 0.06), sec(p2, 0.28, 0.045), sec(p3, 0.06, 0.03)], 16,
                           cut=2)
        sloft("Petal%d" % t, psecs, lip, jaw, sides=14, fwd=tuple(radial), sharp=80.0)

    # ---------------- couraça: placas de pedra e cristais no dorso (+Y) de cada osso
    for k, u in enumerate((0.25, 0.5, 0.75)):
        p = low_path(u)
        _rock("PlateLow%d" % k, (p.x, p.y + 0.72, p.z), 0.36, stone, body, squash=(1.3, 0.55, 0.7), sides=8)
        _rune("RuneLow%d" % k, Vector((p.x, p.y + 0.72 + 0.17, p.z)), Vector((0, 1, 0)), 0.2, rune, body)
    for k, u in enumerate((0.2, 0.45, 0.7, 0.9)):
        p = up_path(u)
        tn = (up_path(min(1.0, u + 0.02)) - up_path(max(0.0, u - 0.02))).normalized()
        back = Vector((0, 1, 0)) - tn * tn.y
        back.normalize()
        _rock("PlateUp%d" % k, tuple(p + back * 0.6), 0.32, stone_l if k % 2 else stone, neck,
              squash=(1.25, 0.55, 0.7), sides=8)
        _rune("RuneUp%d" % k, p + back * (0.6 + 0.15), back, 0.17, rune, neck)
        if k in (1, 2):
            for c, (dx, ln) in enumerate(((-0.18, 0.55), (0.16, 0.42))):
                _crystal("NeckCrystal%d_%d" % (k, c), p + back * 0.62 + Vector((dx, 0, 0)), tuple(back + up_v * 0.3),
                         ln, 0.085, (crys, crys_d), neck)
    for c, (z, dx, ln) in enumerate(((1.0, -0.22, 0.5), (1.2, 0.2, 0.62), (1.55, 0.0, 0.45))):
        p = low_path((z + 0.5) / 2.75)
        _crystal("BodyCrystal%d" % c, (p.x + dx, p.y + 0.72, p.z), (dx, 1.0, 0.55), ln, 0.09, (crys, crys_d), body)

    loose_parts("worm")
    export("worm")


# ================================================================== FLOR-FAMINTA (planta carnívora)
# Planta da beira das trilhas: roseta de folhas no chão, caule grosso que se curva para a frente e uma cabeça de
# duas mandíbulas (como uma dioneia) com dentes que se cruzam; dois cipós com espinhos saem da base. Não anda.
# Pivôs animados por scripts/enemies/enemy.gd (só a planta): Body (caule e cabeça), Head (mandíbula de cima),
# Jaw (de baixo), VineL e VineR (cipós).
def build_plant():
    leaf = mat("p_leaf", hexc("#3E6A2C"), 0.8)
    leaf_d = mat("p_leaf_d", hexc("#284A1C"), 0.8)
    leaf_l = mat("p_leaf_l", hexc("#6E9A44"), 0.8)
    inner = mat("p_inner", hexc("#C23B4A"), 0.7)
    throat = mat("p_throat", hexc("#6A1622"), 0.8)
    tooth = mat("p_tooth", hexc("#EFE6D0"), 0.6)
    thorn = mat("p_thorn", hexc("#2A2420"), 0.6)
    up = (0, 0, 1)

    root = empty("Plant", (0, 0, 0))
    # ---------------- roseta de folhas largas no chão (fixa)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        lsecs = fera_dense([sec(d * 0.03 + Vector((0, 0, 0.05)), 0.05, 0.02),
                            sec(d * 0.28 + Vector((0, 0, 0.13)), 0.15, 0.025),
                            sec(d * 0.52 + Vector((0, 0, 0.1)), 0.13, 0.02),
                            sec(d * 0.7 + Vector((0, 0, 0.03)), 0.03, 0.01)], 10)
        sloft("Leaf%d" % k, lsecs, leaf, root, sides=8, fwd=up, mats=(leaf_l,),
              matf=lambda i, j: 1 if j in (1, 2) else 0)

    body = empty("Body", (0, 0, 0.05), root)
    # ---------------- caule grosso, curvado para a frente, com veios claros
    stem = fera_dense([sec((0, 0.02, 0.0), 0.11, 0.11), sec((0, 0.05, 0.4), 0.085, 0.085),
                       sec((0, 0.0, 0.82), 0.072, 0.072), sec((0, -0.12, 1.07), 0.066, 0.066),
                       sec((0, -0.21, 1.16), 0.06, 0.06)], 16)
    sloft("Stem", stem, leaf, body, sides=10, fwd=(0, -1, 0), mats=(leaf_l,),
          matf=lambda i, j: 1 if j in (2, 7) else 0)
    for s, z in ((1, 0.45), (-1, 0.7)):   # duas folhinhas no caule
        b = Vector((s * 0.06, 0.04, z))
        sloft("StemLeaf%s" % ("L" if s > 0 else "R"),
              fera_dense([sec(b, 0.03, 0.012), sec(b + Vector((s * 0.15, 0.02, 0.08)), 0.07, 0.014),
                          sec(b + Vector((s * 0.28, 0.0, 0.08)), 0.01, 0.006)], 7), leaf, body, sides=8, fwd=up)

    # ---------------- cabeça: mandíbula de cima (Head) e de baixo (Jaw), presas no fim do caule
    head = empty("Head", (0, -0.2, 1.19), body)
    upper = fera_dense([sec((0, -0.17, 1.2), 0.065, 0.05),
                        sec((0, -0.3, 1.25), 0.2, 0.12, bk=0.3),
                        sec((0, -0.48, 1.26), 0.23, 0.12, bk=0.3),
                        sec((0, -0.64, 1.23), 0.17, 0.1, bk=0.3),
                        sec((0, -0.72, 1.21), 0.07, 0.05, bk=0.3),
                        sec((0, -0.745, 1.205), 0.012, 0.01)], 16, cut=1)
    sloft("UpperLobe", upper, leaf, head, sides=16, fwd=up, mats=(inner, leaf_d),
          matf=lambda i, j: 1 if 8 <= j <= 14 else 2 if j in (3,) else 0)
    jaw = empty("Jaw", (0, -0.2, 1.15), body)
    lower = fera_dense([sec((0, -0.17, 1.13), 0.065, 0.05),
                        sec((0, -0.3, 1.1), 0.19, 0.11, fr=0.3),
                        sec((0, -0.48, 1.085), 0.21, 0.11, fr=0.3),
                        sec((0, -0.63, 1.1), 0.15, 0.09, fr=0.3),
                        sec((0, -0.7, 1.115), 0.06, 0.04, fr=0.3),
                        sec((0, -0.72, 1.12), 0.01, 0.01)], 16, cut=1)
    sloft("LowerLobe", lower, leaf, jaw, sides=16, fwd=up, mats=(inner, throat),
          matf=lambda i, j: 2 if (0 <= j <= 6 and 3 <= i <= 6) else 1 if 0 <= j <= 6 else 0)
    # dentes na borda das duas mandíbulas, cruzando na boca fechada
    for k in range(7):
        y = -0.29 - 0.4 * k / 6
        ln = 0.075 - 0.025 * abs(k - 3) / 3
        for deg in (-6, 186):
            p = fera_surf(upper, y, deg, -0.012)
            tip_dir = Vector((-0.25 if p.x > 0 else 0.25, 0, -1)).normalized()
            fera_tip("UpTooth%d_%d" % (k, deg), p, p + tip_dir * ln, 0.014, tooth, head)
        for deg in (6, 174):
            q = fera_surf(lower, y + 0.03, deg, -0.012)
            tip_dir = Vector((-0.25 if q.x > 0 else 0.25, 0, 1)).normalized()
            fera_tip("LowTooth%d_%d" % (k, deg), q, q + tip_dir * ln * 0.9, 0.013, tooth, jaw)

    # ---------------- dois cipós com espinhos, saindo da base para os lados e para a frente
    for s, nm in ((1, "L"), (-1, "R")):
        vine = empty("Vine" + nm, (s * 0.07, 0.02, 0.12), root)
        pts = [Vector((s * 0.05, 0.03, 0.1)), Vector((s * 0.22, 0.06, 0.24)), Vector((s * 0.42, 0.02, 0.34)),
               Vector((s * 0.6, -0.1, 0.33)), Vector((s * 0.74, -0.26, 0.24)), Vector((s * 0.8, -0.42, 0.14))]
        vs = fera_dense([sec(p, 0.04 - 0.032 * i / 5, 0.04 - 0.032 * i / 5) for i, p in enumerate(pts)], 14)
        sloft("Vine%sMesh" % nm, vs, leaf_d, vine, sides=8, fwd=up)
        for k, t in enumerate((0.3, 0.5, 0.7, 0.85)):
            c = sample(vs, t)
            out = Vector((s * 0.4, -0.3, 1.0 if k % 2 == 0 else -0.2)).normalized()
            fera_tip("Thorn%s%d" % (nm, k), c["c"] + out * c["rx"] * 0.4, c["c"] + out * (c["rx"] + 0.05), 0.012,
                     thorn, vine)

    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("plant")
    export("plant")


# ================================================================== BOCARRÃO (sapo gigante)
# Sapo enorme da lagoa do oeste: corpo largo e verruguento, olhos saltados com pálpebra pesada (cara de poucos
# amigos), boca de lado a lado e língua que estica. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (só o sapo): Body (corpo todo), Jaw (queixo, dentro de Body),
# Tongue (língua, dentro de Jaw; estica no ataque), ArmL/ArmR (patas da frente) e LegL/LegR (de trás).
def build_frog():
    skin = mat("f_skin", hexc("#6B6A3A"), 0.8)
    skin_d = mat("f_skin_d", hexc("#46461F"), 0.8)
    belly = mat("f_belly", hexc("#C9B67A"), 0.85)
    mouth = mat("f_mouth", hexc("#6A2230"), 0.85)
    tongue_m = mat("f_tongue", hexc("#C2455A"), 0.6)
    eye = mat("f_eye_flat", (0.9, 0.62, 0.08), 0.4, 0.0, emit=(0.8, 0.5, 0.0), strength=1.5)
    pupil = mat("f_pupil_flat", hexc("#120C08"), 0.4)
    up = (0, 0, 1)

    root = empty("Frog", (0, 0, 0))
    body = empty("Body", (0, 0, 0.4), root)
    bsecs = fera_dense([sec((0, 0.62, 0.32), 0.12, 0.1),
                        sec((0, 0.46, 0.43), 0.44, 0.34, bk=0.8),
                        sec((0, 0.16, 0.56), 0.6, 0.47, bk=0.85),
                        sec((0, -0.2, 0.68), 0.58, 0.4, bk=0.8),
                        sec((0, -0.45, 0.76), 0.46, 0.29, bk=0.7),
                        sec((0, -0.62, 0.78), 0.3, 0.17, bk=0.7),
                        sec((0, -0.7, 0.78), 0.12, 0.08),
                        sec((0, -0.72, 0.78), 0.02, 0.02)], 20, cut=1)
    # dorso oliva com manchas escuras; embaixo, atrás da boca, a barriga clara; na frente, o céu da boca
    def body_mat(i, j):
        y = bsecs[min(i, len(bsecs) - 1)]["c"].y
        if 10 <= j <= 15:
            return 3 if y < 0.0 else 2
        return 0
    sloft("BodyMesh", bsecs, skin, body, sides=18, fwd=up, mats=(skin_d, belly, mouth), matf=body_mat)
    for k, (y, deg) in enumerate(((0.3, 70), (0.3, 110), (0.1, 50), (0.1, 130), (0.42, 90), (-0.02, 75),
                                  (-0.02, 105), (0.2, 90), (0.45, 55), (0.45, 125))):
        c = fera_surf(bsecs, y, deg, -0.01, tilt=True)
        r = 0.035 if k % 3 else 0.045
        sloft("Wart%d" % k, [sec(c + Vector((0, 0.0, -0.01)), r * 0.6, r * 0.6), sec(c + Vector((0, 0, 0.012)), r, r),
                             sec(c + Vector((0, 0, 0.03)), r * 0.4, r * 0.4)], skin_d, body, sides=8, fwd=(0, 1, 0),
              axis=(0, 0, 1))

    # ---------------- olhos saltados no alto, com pálpebra pesada caída para dentro
    for s, nm in ((1, "L"), (-1, "R")):
        base = fera_surf(bsecs, -0.3, 90 - s * 38, -0.06, tilt=True)
        c = base + Vector((s * 0.02, 0, 0.1))
        sloft("Eye" + nm, [sec(c + Vector((0, 0.1, 0)), 0.03, 0.03), sec(c + Vector((0, 0.05, 0)), 0.1, 0.1),
                           sec(c + Vector((0, -0.04, 0)), 0.1, 0.1), sec(c + Vector((0, -0.1, 0)), 0.03, 0.03)],
              eye, body, sides=12, fwd=up)
        pc = c + Vector((s * 0.02, -0.098, 0.0))
        sloft("Pupil" + nm, [sec(pc + Vector((0, 0, -0.06)), 0.006, 0.006), sec(pc, 0.016, 0.012),
                             sec(pc + Vector((0, 0, 0.06)), 0.006, 0.006)], pupil, body, sides=8, fwd=(0, -1, 0))
        # sobrancelha grossa por cima do olho, baixa no lado de dentro (cara fechada)
        fera_curve("Brow" + nm, [c + Vector((-s * 0.1, -0.05, 0.04)), c + Vector((-s * 0.04, -0.08, 0.075)),
                                 c + Vector((s * 0.04, -0.05, 0.1)), c + Vector((s * 0.1, 0.02, 0.09))],
                   0.04, 0.02, skin_d, body, sides=10)
        sloft("EyeBase" + nm, [sec(base, 0.1, 0.1), sec(base + Vector((0, 0, 0.06)), 0.1, 0.09),
                               sec(c + Vector((0, 0.02, -0.02)), 0.07, 0.07)], skin, body, sides=12, fwd=(0, -1, 0),
              axis=(0, 0, 1))

    # ---------------- queixo: casca por baixo da frente do corpo; a linha onde encosta é a boca
    jaw = empty("Jaw", (0, 0.02, 0.5), body)
    jsecs = []
    for y in (0.04, -0.12, -0.3, -0.48, -0.62, -0.69, -0.715):
        sc = fera_surf(bsecs, y, 0, tilt=True)
        bot = fera_surf(bsecs, y, -90, tilt=True)
        half = (sc.z - bot.z)
        jsecs.append(sec((0, y, bot.z + half * 0.45), abs(sc.x) * 1.03 + 0.008, half * 0.55 + 0.012, fr=0.9))
    jsecs = fera_dense(jsecs, 14, cut=1)
    # lábio escuro na borda de cima do queixo (a linha da boca), miolo da boca escondido por dentro
    sloft("JawMesh", jsecs, skin, jaw, sides=18, fwd=up, mats=(belly, mouth),
          matf=lambda i, j: 1 if 10 <= j <= 15 else 2 if (0 <= j <= 8 or j == 17) and i >= 1 else 0)
    tongue = empty("Tongue", (0, -0.05, 0.5), jaw)
    tz = jsecs[3]["c"].z + jsecs[3]["ry"] * 0.6
    sloft("TongueMesh", fera_dense([sec((0, -0.04, tz - 0.02), 0.06, 0.025), sec((0, -0.3, tz), 0.075, 0.028),
                                    sec((0, -0.5, tz + 0.005), 0.085, 0.035), sec((0, -0.58, tz + 0.01), 0.06, 0.03),
                                    sec((0, -0.6, tz + 0.01), 0.015, 0.01)], 10), tongue_m, tongue, sides=12, fwd=up)

    # ---------------- patas da frente curtas e firmes, com três dedos de ponta redonda
    for s, nm in ((1, "L"), (-1, "R")):
        sh = fera_surf(bsecs, -0.32, -90 + s * 55, -0.06, tilt=True)
        arm = empty("Arm" + nm, sh, root)
        hand = Vector((s * 0.46, -0.52, 0.05))
        elbow = sh.lerp(hand, 0.5) + Vector((s * 0.12, 0.1, 0.02))   # cotovelo para fora e para trás
        sloft("Arm%sMesh" % nm, fera_dense([sec(sh, 0.12, 0.12), sec(elbow, 0.1, 0.1),
                                            sec(hand + Vector((0, 0, 0.04)), 0.075, 0.065)], 11),
              skin, arm, sides=10, fwd=(0, -1, 0))
        for k in range(3):
            a = math.radians(-90 + s * (k - 1) * 32)
            d = Vector((math.cos(a) * 0.6 + s * 0.15, math.sin(a), 0)).normalized()
            f0 = hand + Vector((0, 0, 0.02))
            sloft("Arm%sFinger%d" % (nm, k), [sec(f0, 0.045, 0.032), sec(f0 + d * 0.11 + Vector((0, 0, -0.01)), 0.03, 0.02),
                                              sec(f0 + d * 0.15 + Vector((0, 0, -0.012)), 0.04, 0.026),
                                              sec(f0 + d * 0.18 + Vector((0, 0, -0.012)), 0.01, 0.01)],
                  skin_d, arm, sides=8, fwd=up)

    # ---------------- pernas de trás dobradas (coxa grossa para a frente, pé comprido no chão)
    for s, nm in ((1, "L"), (-1, "R")):
        hip = fera_surf(bsecs, 0.36, s * -35 if s > 0 else 180 + 35, -0.12, tilt=True)
        leg = empty("Leg" + nm, hip, root)
        # coxa grossa colada no flanco, joelho baixo na frente, canela voltando por baixo dela, pé largo no chão
        knee = Vector((s * 0.68, -0.04, 0.24))
        ankle = Vector((s * 0.62, 0.42, 0.13))
        foot = Vector((s * 0.68, 0.12, 0.05))
        sloft("Leg%sMesh" % nm, fera_dense([sec(hip, 0.2, 0.2), sec(hip.lerp(knee, 0.5) + Vector((s * 0.05, 0, 0.04)), 0.2,
                                                                      0.18),
                                            sec(knee, 0.13, 0.12), sec(knee.lerp(ankle, 0.5) + Vector((s * 0.06, 0, -0.04)),
                                                                       0.11, 0.1),
                                            sec(ankle, 0.08, 0.075), sec(ankle.lerp(foot, 0.5), 0.07, 0.05),
                                            sec(foot, 0.065, 0.04)], 20), skin, leg, sides=14, fwd=up)
        for k in range(4):
            a = math.radians(-90 + s * (k - 1.5) * 18)
            d = Vector((math.cos(a) + s * 0.1, math.sin(a), 0)).normalized()
            sloft("Leg%sToe%d" % (nm, k), [sec(foot, 0.045, 0.028), sec(foot + d * 0.17 + Vector((0, 0, -0.02)), 0.028, 0.018),
                                           sec(foot + d * 0.22 + Vector((0, 0, -0.025)), 0.04, 0.022),
                                           sec(foot + d * 0.25 + Vector((0, 0, -0.025)), 0.01, 0.01)],
                  skin_d, leg, sides=8, fwd=up)

    for ob in coll.all_objects:
        if ob.type == 'MESH':
            smooth_sharp(ob, 80.0)
    loose_parts("frog")
    export("frog")


# ================================================================== ASA-COURO (morcego grande)
# Morcego das ruínas, só de noite: voa a ~1,5 m do chão (o corpo físico fica no chão e o modelo é montado no ar),
# orelhonas pontudas, focinho com presas para fora e asas de pele esticadas entre os dedos. Frente = -Y.
# Pivôs animados por scripts/enemies/enemy.gd (só o morcego): Body (corpo todo, sobe e desce no voo), Head,
# WingL/WingR (no ombro; batem girando no eixo da frente) e LegL/LegR (pezinhos pendurados).
def _membrane(name, pts, material, parent, hub, thick=0.012):
    """Pele de asa: leque de triângulos a partir do pulso (hub) passando por pts, com espessura (dos dois lados
    aparece) e sombreado chapado."""
    bm = bmesh.new()
    h = bm.verts.new(hub)
    vs = [bm.verts.new(p) for p in pts]
    for a, b in zip(vs, vs[1:]):
        bm.faces.new((h, a, b))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    print("PART", name, "membrane", flush=True)
    bmesh.ops.translate(bm, vec=-_wloc(parent), verts=bm.verts)
    return _finish(name, bm, material, parent)


def build_bat():
    fur = mat("b_fur", hexc("#5E4A3C"), 0.9)
    fur_d = mat("b_fur_d", hexc("#3A2C24"), 0.9)
    chest = mat("b_chest", hexc("#8A6E52"), 0.9)
    skin = mat("b_skin", hexc("#4A3A48"), 0.75)
    skin_d = mat("b_skin_d", hexc("#2E2230"), 0.75)
    fang = mat("b_fang", hexc("#EFE6D0"), 0.5)
    mouth = mat("b_mouth", hexc("#6A1E2A"), 0.8)
    eye = mat("b_eye_flat", (1.0, 0.8, 0.1), 0.4, 0.0, emit=(1.0, 0.65, 0.0), strength=3.0)
    claw = mat("b_claw", hexc("#1E1612"), 0.5)
    up = (0, 0, 1)

    root = empty("Bat", (0, 0, 0))
    body = empty("Body", (0, 0, 1.5), root)
    tsecs = fera_dense([sec((0, 0.27, 1.44), 0.04, 0.04), sec((0, 0.14, 1.47), 0.13, 0.12),
                        sec((0, -0.03, 1.52), 0.155, 0.15), sec((0, -0.17, 1.56), 0.12, 0.12),
                        sec((0, -0.25, 1.58), 0.085, 0.085)], 12)
    sloft("Torso", tsecs, fur, body, sides=12, fwd=up, mats=(chest, fur_d),
          matf=lambda i, j: 1 if 7 <= j <= 10 else 2 if j in (2, 3) and i >= 6 else 0)

    # ---------------- cabeça: orelhonas, olho em fenda sob a testa, focinho curto com presas para fora
    head = empty("Head", (0, -0.24, 1.58), body)
    hsecs = fera_dense([sec((0, -0.19, 1.6), 0.08, 0.08), sec((0, -0.28, 1.63), 0.13, 0.12),
                        sec((0, -0.38, 1.62), 0.11, 0.1, bk=0.9), sec((0, -0.46, 1.585), 0.065, 0.06),
                        sec((0, -0.5, 1.575), 0.035, 0.035), sec((0, -0.515, 1.572), 0.008, 0.008)], 12, cut=1)
    sloft("HeadMesh", hsecs, fur, head, sides=12, fwd=up, mats=(skin_d, mouth),
          matf=lambda i, j: 1 if i >= 8 and j in (1, 2, 3, 4) else 2 if i >= 6 and j in (7, 8, 9, 10) else 0)
    for s, nm in ((1, "L"), (-1, "R")):
        e0 = fera_surf(hsecs, -0.29, 90 - s * 58, -0.02)
        tipp = Vector((s * 0.22, -0.2, 1.93))
        sloft("Ear" + nm, fera_dense([sec(e0, 0.065, 0.02), sec(e0.lerp(tipp, 0.45), 0.075, 0.018),
                                      sec(e0.lerp(tipp, 0.85), 0.03, 0.012), sec(tipp, 0.005, 0.005)], 10),
              fur, head, sides=8, fwd=(0, -1, 0), mats=(skin_d,), matf=lambda i, j: 1 if 0 < i < 8 and j in (1, 2, 3) else 0)
        ec = fera_surf(hsecs, -0.38, 90 - s * 40, -0.004)
        sloft("Eye" + nm, [sec(ec + Vector((s * 0.03, 0.015, 0.012)), 0.004, 0.004),
                           sec(ec, 0.022, 0.009), sec(ec + Vector((-s * 0.02, -0.015, -0.006)), 0.004, 0.004)],
              eye, head, sides=8, fwd=up, axis=(-s, -0.6, -0.3))
        fera_curve("Brow" + nm, [fera_surf(hsecs, -0.33, 90 - s * 42, -0.005), fera_surf(hsecs, -0.37, 90 - s * 30, 0.0),
                                 fera_surf(hsecs, -0.41, 90 - s * 16, -0.01)], 0.022, 0.01, fur_d, head, sides=8)
        f0 = fera_surf(hsecs, -0.47, -90 + s * 50, -0.01)
        fera_tip("Fang" + nm, f0, f0 + Vector((0, -0.006, -0.065)), 0.015, fang, head)

    # ---------------- asas: braço e dedos (ossos) com a pele esticada entre eles e a borda de trás recortada
    for s, nm in ((1, "L"), (-1, "R")):
        sh = Vector((s * 0.11, -0.1, 1.58))
        wing = empty("Wing" + nm, sh, body)
        el = Vector((s * 0.42, 0.0, 1.7))
        wr = Vector((s * 0.82, -0.1, 1.72))
        tips = [Vector((s * 1.12, -0.28, 1.64)), Vector((s * 1.26, 0.04, 1.56)), Vector((s * 1.06, 0.36, 1.46)),
                Vector((s * 0.66, 0.42, 1.44))]
        fera_curve(nm + "Humerus", [sh, sh.lerp(el, 0.5) + Vector((0, 0, 0.02)), el], 0.045, 0.03, skin_d, wing)
        fera_curve(nm + "Forearm", [el, el.lerp(wr, 0.5) + Vector((0, 0, 0.02)), wr], 0.03, 0.022, skin_d, wing)
        for k, t in enumerate(tips[:3]):
            fera_curve(nm + "Finger%d" % k, [wr, wr.lerp(t, 0.5) + Vector((0, 0, 0.015)), t], 0.02, 0.005, skin_d, wing)
        fera_tip(nm + "Thumb", wr + Vector((0, 0, 0.01)), wr + Vector((s * 0.03, -0.08, 0.07)), 0.022, claw, wing)
        side = Vector((s * 0.1, 0.2, 1.48))

        def scallop(a, b, k=0.22):
            return a.lerp(b, 0.5).lerp(wr, k)
        ring = [sh, el, tips[0], scallop(tips[0], tips[1], 0.12), tips[1], scallop(tips[1], tips[2]), tips[2],
                scallop(tips[2], tips[3], 0.18), tips[3], scallop(tips[3], side, 0.1), side, sh]
        _membrane(nm + "Membrane", ring, skin, wing, wr)

    # ---------------- pezinhos pendurados atrás, com garras
    for s, nm in ((1, "L"), (-1, "R")):
        hp = Vector((s * 0.07, 0.17, 1.45))
        leg = empty("Leg" + nm, hp, body)
        ft = Vector((s * 0.1, 0.3, 1.3))
        fera_curve(nm + "LegMesh", [hp, hp.lerp(ft, 0.5) + Vector((0, 0.02, 0)), ft], 0.03, 0.018, skin_d, leg)
        for k in range(3):
            c0 = ft + Vector(((k - 1) * 0.015, 0, 0))
            fera_curve(nm + "FootClaw%d" % k, [c0, c0 + Vector((0, 0.02, -0.03)), c0 + Vector((0, -0.01, -0.05))],
                       0.01, 0.002, claw, leg, sides=6)

    for ob in coll.all_objects:
        if ob.type == 'MESH' and not ob.name.endswith("Membrane"):
            smooth_sharp(ob, 80.0)
    loose_parts("bat")
    export("bat")
