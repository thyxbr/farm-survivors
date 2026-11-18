# Penteados do herói, escolhidos na criação (scripts/character/hair_styles.gd). Cada penteado vira um GLB de
# equipamento preso ao pivô Head: gear/hair_<id>.glb (cabeça nua, coroas) e gear/hair_<id>_tight.glb (o mesmo
# penteado rente ao crânio em cima e nos lados, para caber sob capuz e chapéu; franja, nuca e o que cai abaixo
# da orelha ficam iguais). Os penteados do corpo feminino saem só em _f (deformados como as roupas).
# O jogo escolhe qual vestir (KnightLook.HEAD_HAIR). Referências: cabelo anime e estilizado em folhas largas,
# com pontas, em camadas (calota no tom médio, nuca escura, mechas claras), como anime_hair.
# Executado dentro de build_assets.py depois de female.py (usa anime_hair, _lock, _scalp, plain_head...).

def _hair_mats():
    return {"hair": gm("g_hair", "#4A2C17", 0.9), "mid": gm("g_hair_mid", "#6E4428", 0.9),
            "under": gm("g_hair_under", "#2B190C", 0.9)}


def _sp(H, lf):
    def sp(th, ph, lift):
        return _scalp(H, th, ph, lift * H["s"] * lf)
    return sp


def _nrm(H):
    s = H["s"]
    C = Vector((0, H["cy"], H["chin"] + 12.0 * s))

    def nrm(p):
        r = p - C
        return Vector((r.x / 7.5 ** 2, r.y / 9.5 ** 2, r.z * (1.0 if r.z > 0 else 0.35) / 11.0 ** 2)).normalized()
    return nrm


# ------------------------------------------------------------------ penteados
# Cada um recebe H (marcos da cabeça), os materiais, o pivô Head e tight (rente ao crânio). `lf` multiplica o
# afastamento das mechas: 1 = volume normal; sob capuz o topo e os lados descem para perto da pele.
def _lift(tight, k=1.0):
    return 0.45 if tight else k


def hair_m_curto(H, HM, head, tight):
    st = dict(MALE_HAIR_STYLE)
    st["lift"] = st["lift"] * _lift(tight)
    return anime_hair("", H, HM, head, st)


def hair_m_penteado(H, HM, head, tight):
    """Penteado para trás e para o lado: testa à mostra, topete com volume que sai do repartido e vira para trás,
    lados rentes acima da orelha."""
    lf = _lift(tight, 1.0)
    extra = []
    # topete: folhas largas da linha do cabelo, passando por cima, até atrás da coroa
    for th0, dth in ((-34, 30), (-14, 34), (6, 40), (26, 46), (46, 40)):
        up = 1.0 if tight else 2.4 - abs(th0 - 6) * 0.02
        extra.append(([(th0, 40, 0.6), (th0 + dth * 0.3, 66, up), (th0 + dth * 0.7, 84, up * 0.8),
                       (th0 + dth + 110, 64, 0.9)], 4.2, "hair", 0.34))
    st = {"fringe": 34, "side": 9, "back": -22, "part": -30, "sweep": 1, "top": 9, "bangs": False, "frame": False,
          "w": 1.15, "lift": 1.1 * lf, "seed": 21, "extra": extra,
          "hairline": [(0, 40), (35, 37), (60, 27), (78, 18), (97, 15), (112, 5), (135, -16), (180, -24)]}
    return anime_hair("", H, HM, head, st)


def hair_m_franja(H, HM, head, tight):
    """Tigela: franja reta e cheia até a sobrancelha, lados cobrindo o alto da orelha, nuca curta."""
    lf = _lift(tight, 1.0)
    extra = []
    for th in (-54, -36, -18, 0, 18, 36, 54):        # franja: folhas retas do alto da cabeça até a sobrancelha
        extra.append(([(th * 0.5, 80, 0.6), (th * 0.8, 56, 1.6), (th, 30, 1.5), (th * 1.04, 8, 1.2)],
                      3.9, "hair", 0.34))
    st = {"fringe": 10, "side": 2, "back": -22, "part": 0, "sweep": 1, "top": 10, "bangs": False, "frame": True,
          "w": 1.2, "lift": 1.45 * lf, "seed": 23, "extra": extra}
    return anime_hair("", H, HM, head, st)


def hair_m_raspado(H, HM, head, tight):
    """Bem curto, rente à cabeça: só a calota no tom do cabelo e pontinhas curtas na testa e na coroa."""
    hm = dict(HM, mid=HM["hair"])
    extra = []
    for th in (-36, -18, 0, 18, 36):
        extra.append(([(th, 70, 0.25), (th * 1.05, 48, 0.3), (th * 1.08, 38, 0.25)], 2.6, "hair", 0.3))
    st = {"top": 0, "bangs": False, "frame": False, "nape": False, "lift": 2.4, "seed": 25, "extra": extra,
          "hairline": [(0, 40), (35, 37), (60, 29), (78, 20), (97, 17), (112, 6), (135, -14), (180, -22)]}
    return anime_hair("", H, hm, head, st)


def hair_f_longo(H, HM, head, tight):
    """O de sempre: franja larga para o lado, mechas do rosto até o colo, cabelo solto nas costas e rabo de
    cavalo alto (nó Ponytail, que o jogo balança)."""
    st = dict(FEM_HAIR_STYLE)
    st["lift"] = st["lift"] * _lift(tight)
    out = anime_hair("", H, HM, head, st)
    nrm = _hair_nrm(H)
    s = H["s"]
    sp = _sp(H, _lift(tight))
    fb = bmesh.new()
    for sg in (1, -1):        # mechas do rosto: da têmpora, na frente da orelha, até abaixo do queixo
        _lock(fb, [sp(sg * 56, 46, 1.2), sp(sg * 70, 18, 1.8), sp(sg * 78, -12, 1.9),
                   Vector((sg * 0.074, -0.022, H["chin"] - 0.012)), Vector((sg * 0.07, -0.05, H["chin"] - 0.062))],
              0.024, nrm, th_k=0.32, k=3, root=0.6)
    out.append(_hair_obj("HairFrame", fb, HM["hair"], head))
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
    # rabo de cavalo: o prendedor fica por fora do cabelo, mesmo apertado sob o capuz
    root, tie, path = ponytail_path(H)
    tail = build_ponytail(root, tie, path, head, dict(fem_hair_mats(), **HM))
    out.append(tail)
    return out


def hair_f_chanel(H, HM, head, tight):
    """Chanel: franja reta até a sobrancelha, lados e nuca retos na altura do queixo."""
    lf = _lift(tight, 1.0)
    extra = []
    for th in (-48, -32, -16, 0, 16, 32, 48):
        extra.append(([(th * 0.5, 80, 0.6), (th * 0.8, 56, 1.5), (th, 30, 1.4), (th * 1.03, 10, 1.1)],
                      3.6, "hair", 0.32))
    for sg in (1, -1):        # cortina dos lados: da têmpora até o queixo, por fora da orelha
        for th in (64, 84, 104, 126, 150):
            extra.append(([(sg * th * 0.9, 60, 1.0), (sg * th, 20, 1.9), (sg * th, -22, 2.1), (sg * th * 1.02, -46, 1.9)],
                          4.0, "hair", 0.3))
    for th in (166, 180, 194):
        extra.append(([(th, 60, 1.0), (th, 10, 1.9), (th, -30, 2.0), (th, -50, 1.8)], 4.2, "hair", 0.3))
    st = {"fringe": 12, "side": -40, "back": -46, "part": 0, "top": 9, "bangs": False, "frame": False,
          "w": 1.25, "lift": 1.4 * lf, "seed": 31, "extra": extra}
    return anime_hair("", H, HM, head, st)


def hair_f_curto(H, HM, head, tight):
    """Curto repicado: franja de lado, mechas pontudas por cima, lados até o meio da orelha e mechas do rosto até
    a mandíbula."""
    lf = _lift(tight, 1.0)
    extra = []
    for sg in (1, -1):
        extra.append(([(sg * 58, 50, 1.0), (sg * 68, 22, 1.6), (sg * 74, -8, 1.6), (sg * 76, -26, 1.4)], 2.8, "hair", 0.3))
    st = {"fringe": 14, "side": -6, "back": -30, "part": 30, "sweep": -1, "top": 11, "w": 1.25, "lift": 1.6 * lf,
          "seed": 33, "extra": extra}
    return anime_hair("", H, HM, head, st)


def hair_f_marias(H, HM, head, tight):
    """Marias-chiquinhas: franja de lado e duas mechas presas acima das orelhas, caindo até o ombro."""
    lf = _lift(tight, 1.0)
    out = anime_hair("", H, HM, head, {"fringe": 14, "side": 0, "back": -28, "part": 30, "sweep": -1, "top": 9,
                                         "w": 1.25, "lift": 1.5 * lf, "seed": 35})
    s = H["s"]
    sp = _sp(H, lf)
    nrm = _hair_nrm(H)
    tb = bmesh.new()
    for sg in (1, -1):
        tie = sp(sg * 112, 30, 2.4)
        out.append(anime_bun("HairTie" + ("L" if sg > 0 else "R"), tie, (0.034, 0.03, 0.034),
                             fem_hair_mats()["tie"], head))
        out_d = Vector((sg, 0.25, 0)).normalized()
        for k, (dy, w) in enumerate(((-0.008, 0.042), (0.01, 0.036))):
            p0 = tie + Vector((0, dy, 0))
            ctrl = [p0, p0 + out_d * 0.03 + Vector((0, 0, -0.01)), p0 + out_d * 0.05 + Vector((0, 0.01, -0.07)),
                    p0 + out_d * 0.045 + Vector((0, 0.02, -0.15)), p0 + out_d * 0.03 + Vector((0, 0.03, -0.22))]
            _lock(tb, ctrl, w, lambda p, sg=sg: Vector((sg, 0.3, 0)).normalized(), th_k=0.55, k=3, root=0.75)
    out.append(_hair_obj("HairTwin", tb, HM["hair"], head))
    return out


HAIR_STYLES = {"m": ("m_curto", "m_penteado", "m_franja", "m_raspado"),
               "f": ("f_longo", "f_chanel", "f_curto", "f_marias")}


# ------------------------------------------------------------------ montagem e exportação
def build_hair(hid, tight):
    female = hid.startswith("f_")
    style = "hair_%s%s" % (hid, "_tight" if tight else "")
    P, R = g_rig(style)
    M = g_mats()
    head = R["Head"]
    before = set(coll.all_objects)
    H = (fem_plain_head if female else plain_head)(R, M)       # a cabeça só faz sombra; não é exportada
    head_objs = [o for o in coll.all_objects if o not in before and o.type == 'MESH']
    before = set(coll.all_objects)
    globals()["hair_" + hid](H, _hair_mats(), head, tight)
    targets = [o for o in coll.all_objects if o not in before and o.type == 'MESH']
    occ = head_objs + _occluders("h", P, R, M)
    if female:
        fem_warp()
    drop_head("h_", targets + head_objs)
    g_smooth(targets)
    bake_ao(targets, occ)
    loose_world(style + ("_f" if female else ""), targets)
    export("gear/" + style + ("_f" if female else ""), export_vertex_color='ACTIVE')


HAIR_BUILDERS = []
for _b, _ids in HAIR_STYLES.items():
    for _id in _ids:
        for _t in (False, True):
            _name = "hair_%s%s%s" % (_id, "_tight" if _t else "", "_f" if _b == "f" else "")
            HAIR_BUILDERS.append((_name, _gear_builder(lambda i=_id, t=_t: build_hair(i, t))))
