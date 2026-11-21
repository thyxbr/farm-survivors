# Corpo do anão (knight_d.glb e gear/<estilo>_d.glb). PROTÓTIPO.
# Executado por exec() dentro de build_assets.py, depois de female.py (usa fem_warp, _outer, _ftab, plain_head).
#
# Mesmo caminho do corpo feminino: cada modelo é montado no corpo masculino e DEFORMADO para o anão por
# dwarf_warp() (fem_warp com outra deformação). Proporções do anão:
#   - tronco mais baixo (D_KT) e bem mais largo e fundo (D_SX/D_SY), com barriga na frente;
#   - pernas curtas e grossas (D_LEG); abaixo do tornozelo o pé NÃO encurta (bota com a altura de sempre) e
#     fica mais largo e comprido;
#   - braços curtos e grossos (D_ARM); a mão não encurta, só engrossa;
#   - a cabeça fica do mesmo tamanho (desce junto com o pescoço), então elmos e penteados servem sem mudança;
#     a cabeça nua (h_bare_d) e as cabeças sob elmos ganham barba cheia.
# Os pivôs e ossos vão para as articulações novas: as animações por pivô e o PivotSkin continuam valendo.
from mathutils import Vector, Matrix

D_KT = 0.84                        # tronco: altura (do quadril para cima)
D_LEG = (0.60, 1.15)               # perna: ao longo do eixo, na seção
D_FOOT = 1.0                       # pé (abaixo do tornozelo): altura; a seção segue a da perna
D_TOE, D_TOE_R = 1.08, 0.05       # bico do pé: escala do avanço à frente de D_TOE_R (m) do eixo da perna
D_ARM = (0.78, 1.12)               # braço: ao longo do eixo, na seção
D_HAND = 1.0                       # mão (além do punho): comprimento; a seção segue a do braço
D_ABDUCT = math.radians(5.0)       # braço mais aberto: passa por fora da barriga e do quadril largo
D_NECK = 1.1                       # pescoço grosso
# largura (x) e profundidade (y) do tronco por altura (z do corpo masculino)
D_SX = [(0.0, 1.12), (0.95, 1.12), (1.05, 1.15), (1.20, 1.17), (1.32, 1.16), (1.43, 1.14), (1.50, 1.08),
        (3.0, 1.05)]
D_SY = [(0.0, 1.08), (0.95, 1.08), (1.10, 1.12), (1.30, 1.12), (1.45, 1.08), (3.0, 1.05)]
# barriga: centro (z masculino), queda para baixo/para cima e projeção para a frente (m)
BELLY_Z, BELLY_LO, BELLY_HI, BELLY_A = 1.10, 0.10, 0.14, 0.025
# parâmetros da barba do anão (anime_beard): mais comprida e cheia que a do herói
D_BEARD = {"length": 9.0, "full": 1.4}

# estilos do protótipo (ASSETS=dwarf): corpo base, tecido, couro, placa e manto comprido
DWARF_STYLES = ["h_bare", "a_shirt", "g_bare", "f_shoes",
                "a_tunic", "h_hood", "f_boots",
                "a_gambeson", "h_cap", "g_gloves",
                "a_paladin", "h_great", "g_ironplate", "f_ironplate",
                "a_robe", "h_wizard"]


def _belly(x, y, z):
    if y >= -0.02:
        return 0.0
    fw = min(1.0, (-y - 0.02) / 0.06) ** 1.5
    d = z - BELLY_Z
    gz = math.exp(-(d / (BELLY_LO if d < 0 else BELLY_HI)) ** 2)
    gx = math.exp(-(x / 0.16) ** 2)
    return BELLY_A * fw * gz * gx


class DwarfWarp:
    """Transformações por região do corpo masculino (GEAR_P) para o do anão (mesma interface de FemWarp)."""

    def __init__(self):
        P = body_proportions(**GEAR_P)
        self.J = J = {n: P[n].copy() for n in ("pelvis", "neck", "shoulder", "elbow", "wrist", "hip", "knee",
                                                "ankle")}
        self.hip_z = J["hip"].z
        # altura nova do quadril: a sola do pé (z = 0) continua no chão
        Hp, A = J["hip"], J["ankle"]
        a = (A - Hp).normalized()
        ka, kp = D_LEG
        M = Matrix.Identity(3) * kp + (ka - kp) * _outer(a)
        self.hip2 = D_FOOT * A.z - (M @ (A - Hp)).z
        self.dN = self.torso(J["neck"]) - J["neck"]
        self.arm, self.leg = {}, {}
        for s, n in ((1, "L"), (-1, "R")):
            S, W = mirror(J["shoulder"], s), mirror(J["wrist"], s)
            a = (W - S).normalized()
            ka, kp = D_ARM
            Rm = Matrix.Rotation(-s * D_ABDUCT, 3, 'Y')
            M = Rm @ (Matrix.Identity(3) * kp + (ka - kp) * _outer(a))
            Mh = Rm @ (Matrix.Identity(3) * kp + (D_HAND - kp) * _outer(a))
            self.arm[n] = (S, self.torso(S), M, a, (W - S).length, Mh)
            Hp, A = mirror(J["hip"], s), mirror(J["ankle"], s)
            a = (A - Hp).normalized()
            ka, kp = D_LEG
            M = Matrix.Identity(3) * kp + (ka - kp) * _outer(a)
            Mf = Matrix.Identity(3) * kp + (D_FOOT - kp) * _outer(a)
            self.leg[n] = (Hp, self.torso(Hp), M, a, (A - Hp).length, Mf)

    def torso(self, p, mode="cloth"):
        x, y, z = p
        sx, sy = _ftab(D_SX, z), _ftab(D_SY, z)
        ny = y * sy
        if y < 0:
            ny -= _belly(x, y, z)
        return Vector((x * sx, ny, (z - self.hip_z) * D_KT + self.hip2))

    def region(self, name):
        return FemWarp.region(self, name)

    def xf(self, reg, p, mode="cloth"):
        p = Vector(p)
        if reg == "body" or reg is None:
            return self.torso(p, mode)
        if reg == "head":
            # o que a peça da cabeça tem abaixo do pescoço (gola do capuz, ponta da barba) vai aos poucos com o
            # tronco largo, senão some dentro dele
            zn = self.J["neck"].z + 0.03
            if p.z >= zn:
                return p + self.dN
            w = min(1.0, (zn - p.z) / 0.09)
            w = w * w * (3 - 2 * w)
            return (p + self.dN).lerp(self.torso(p, mode), w)
        if reg == "neck":
            q = p + self.dN
            return Vector((q.x * D_NECK, q.y * D_NECK, q.z))
        side = reg[-1]
        S, S2, M, a, L, Me = (self.arm if reg.startswith("arm") else self.leg)[side]
        d = p - S
        t = d.dot(a)
        if reg.startswith("leg"):
            # bico do pé: a seção grossa da perna deixaria a bota comprida demais; à frente de D_TOE_R o
            # avanço cresce D_TOE em vez da seção inteira (só perto do pé, contínuo com a canela)
            f = max(0.0, min(1.0, (t / L - 0.82) / 0.12))
            ex = -d.y - D_TOE_R
            if f > 0 and ex > 0:
                d = d + Vector((0, ex * f * (1 - D_TOE / D_LEG[1]), 0))
        if t <= L:
            return S2 + M @ d
        # além do punho / tornozelo: mão e pé não encurtam (só engrossam com o membro)
        E = S + a * L
        return S2 + M @ (E - S) + Me @ (S + d - E)


def dwarf_warp(objs=None):
    return fem_warp(objs, DwarfWarp())


def dwarf_plain_head(R, M, beard=False, hair=False):
    """Cabeça do herói com barba cheia de anão (a cabeça e o rosto são os mesmos do masculino)."""
    H = _plain_head_m(R, M, beard=False, hair=hair)
    hm = {"hair": M["hair"], "mid": gm("g_hair_mid", "#6E4428", 0.9), "under": gm("g_hair_under", "#2B190C", 0.9)}
    anime_beard("", H, hm, R["Head"], D_BEARD)
    return H


# ------------------------------------------------------------------ montagem
def knight_d_finish(R):
    """Chamado por build_knight(dwarf=True) antes de assar e exportar: deforma o cavaleiro."""
    dwarf_warp()
    loose_world("knight_d")


def build_knight_d():
    build_knight(dwarf=True)


_plain_head_m = plain_head


def _g_export_d(style, P=None, R=None):
    os.makedirs(OUT + "gear", exist_ok=True)
    targets = [o for o in scn.objects if o.type == 'MESH']
    occ = []
    if P is not None and targets:
        occ = _occluders(style, P, R, g_mats())
    dwarf_warp()
    drop_head(style, targets)
    g_smooth(targets)
    if P is not None and targets:
        bake_ao(targets, occ)
    loose_world(style + "_d", targets)
    export("gear/" + style + "_d", export_vertex_color='ACTIVE')


def dwarf_gear(style, fn):
    def run():
        global g_export, plain_head, band
        g0, h0, b0 = g_export, plain_head, band
        g_export, plain_head, band = _g_export_d, dwarf_plain_head, _knight_band
        try:
            fn()
        finally:
            g_export, plain_head, band = g0, h0, b0
    return run


DWARF_GEAR = [(n + "_d", dwarf_gear(n, f)) for n, f in GEAR]          # todos os estilos (DWARF_STYLES = amostra)
