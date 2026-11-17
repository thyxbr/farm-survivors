"""Script de uma vez (progressão, parte 3): monta o catálogo do craft a partir dos itens que já existem.

- items.json: materiais das 5 camadas (minério, madeira, couro, essência), peças raras de chefe, os itens novos
  que tapam buracos das camadas 3–5 e um pergaminho por receita de pergaminho.
- recipes.json: mantém a cozinha e gera alquimia (poções e essências) e o equipamento de forja, couraria e
  alquimia. Cada equipamento não nomeado vira receita no nível dele; a de maior nível de cada camada em cada
  profissão pede a peça do chefe da camada e se aprende por pergaminho (a camada 5 inteira também).
- shop.json: só o básico (poções, sementes, materiais da camada 1, equipamento comum de nível <= 10).
- enemies.json: peças raras e pergaminhos no loot dos chefes.

Depois de rodar, tudo fica editável à mão no JSON (rodar de novo sobrescreve recipes.json e shop.json).
Uso (na raiz do projeto): python tools/balance/make_recipes.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BAL = ROOT / "data" / "balance"
sys.path.insert(0, str(Path(__file__).parent))
import jsonfmt  # noqa: E402

TIERS = [(1, 10), (11, 20), (21, 30), (31, 40), (41, 50)]
ORE = ["copper_ore", "iron_ore", "silver_ore", "mithril_ore", "astralite_ore"]
LOG = ["pine_log", "oak_log", "silverbirch_log", "ashwood_log", "soulwood_log"]
HIDE = ["hide_t1", "hide_t2", "hide_t3", "hide_t4", "hide_t5"]
ESS = ["essence_t1", "essence_t2", "essence_t3", "essence_t4", "essence_t5"]
BOSS_PIECE = ["goblin_crown", "royal_jelly", "knight_sigil", "lich_phylactery", "abyss_core"]
# parte de monstro da essência de cada camada
ESS_PART = ["slime_gel", "frost_drop", "bone_shard", "shadow_fang", "arcane_crystal"]
# chefe que solta os pergaminhos da camada (a 5 vem das dungeons na parte 4; até lá, o Lich)
TIER_BOSS = ["goblin_king", "slime_rainha", "esqueleto_cavaleiro", "lich", "lich"]
SCROLL_CHANCE = [0.3, 0.3, 0.04, 0.25, 0.08]

MATERIALS = {
    "copper_ore": ("Minério de Cobre", "common", 4, "Avermelhado e macio. O primeiro metal de todo ferreiro."),
    "silver_ore": ("Minério de Prata", "uncommon", 14, "Brilha mesmo no escuro das galerias da Mina."),
    "mithril_ore": ("Minério de Mithril", "rare", 24, "Leve como pena e duro como diamante. Só no Pico."),
    "astralite_ore": ("Minério de Astralita", "epic", 40, "Cai do céu, dizem. Pulsa num violeta frio."),
    "pine_log": ("Tora de Pinho", "common", 3, "Madeira macia e cheirosa dos bosques do Vale."),
    "oak_log": ("Tora de Carvalho", "common", 7, "Firme e pesada. Boa para arcos e cabos."),
    "silverbirch_log": ("Tora de Bétula-prata", "uncommon", 13, "Casca prateada, fibra que não racha."),
    "ashwood_log": ("Tora de Freixo-cinza", "rare", 22, "Cresce entre as cinzas do Pico. Quase não queima."),
    "soulwood_log": ("Tora de Madeira-de-alma", "epic", 38, "Sussurra quando a lâmina corta."),
    "hide_t1": ("Couro Cru", "common", 3, "Couro grosso de monstro do Vale. Precisa de curtume."),
    "hide_t2": ("Couro Curtido", "common", 7, "Couro dos monstros do Bosque, firme e flexível."),
    "hide_t3": ("Couro Reforçado", "uncommon", 13, "Couro dos monstros da Mina, duro como sola."),
    "hide_t4": ("Couro Sombrio", "rare", 22, "Couro dos monstros do Pico. Frio ao toque."),
    "hide_t5": ("Couro Astral", "epic", 38, "Couro dos monstros mais fortes do mundo."),
    "essence_t1": ("Essência Tênue", "common", 8, "Base de todo equipamento da camada 1. Feita na alquimia."),
    "essence_t2": ("Essência Viva", "common", 16, "Base de todo equipamento da camada 2. Feita na alquimia."),
    "essence_t3": ("Essência Vibrante", "uncommon", 28, "Base de todo equipamento da camada 3. Feita na alquimia."),
    "essence_t4": ("Essência Ancestral", "rare", 45, "Base de todo equipamento da camada 4. Feita na alquimia."),
    "essence_t5": ("Essência Astral", "epic", 70, "Base de todo equipamento da camada 5. Feita na alquimia."),
    "royal_jelly": ("Geleia Real", "epic", 120, "Da Slime Rainha. A ponta das receitas da camada 2 pede uma."),
    "knight_sigil": ("Selo do Cavaleiro", "epic", 150, "De um Cavaleiro Esqueleto. A ponta da camada 3 pede um."),
    "lich_phylactery": ("Filactério do Lich", "legendary", 300, "A alma de Morgrath. A ponta da camada 4 pede um."),
    "abyss_core": ("Núcleo do Abismo", "legendary", 400, "Das profundezas. A ponta da camada 5 pede um."),
}
# itens novos (buracos das camadas 3–5): id -> (base copiada, nome, nível, raridade, descrição, cor)
NEW_GEAR = {
    "silver_gauntlets": ("iron_gauntlets", "Manoplas de Prata", 27, "rare", "Prata batida sobre couro reforçado.", [0.8, 0.82, 0.9]),
    "silver_greaves": ("iron_greaves", "Grevas de Prata", 26, "rare", "Leves e firmes nas galerias.", [0.8, 0.82, 0.9]),
    "mithril_longbow": ("goblin_warbow", "Arco Longo de Mithril", 36, "epic", "A corda canta como sino.", [0.6, 0.85, 0.9]),
    "ashwood_staff": ("void_staff", "Cajado de Freixo-cinza", 34, "epic", "Cinza que nunca esfria.", [1.0, 0.55, 0.3]),
    "mithril_helm": ("guard_greathelm", "Elmo de Mithril", 33, "epic", "Pesa quase nada; aguenta quase tudo.", [0.6, 0.85, 0.9]),
    "mithril_gauntlets": ("iron_gauntlets", "Manoplas de Mithril", 37, "epic", "Os dedos se movem sem barulho.", [0.6, 0.85, 0.9]),
    "mithril_greaves": ("iron_greaves", "Grevas de Mithril", 36, "epic", "Passos firmes nas encostas do Pico.", [0.6, 0.85, 0.9]),
    "astral_blade": ("titan_cleaver", "Lâmina Astral", 46, "legendary", "Corta o ar e deixa estrelas no rastro.", [0.75, 0.6, 1.0]),
    "astral_bow": ("storm_bow", "Arco Astral", 46, "legendary", "Cada flecha leva um pedaço do céu.", [0.75, 0.6, 1.0]),
    "soulwood_staff": ("archmage_staff", "Cajado de Madeira-de-alma", 46, "legendary", "As vozes da madeira ajudam a mirar.", [0.7, 0.55, 1.0]),
    "sc_astral_scepter": ("sc_halo_scepter", "Cetro Astral", 46, "legendary", "Cura com a luz de outra estrela.", [0.85, 0.75, 1.0]),
    "astral_plate": ("dragon_plate", "Placas Astrais", 47, "legendary", "Forjada com o metal que caiu do céu.", [0.75, 0.6, 1.0]),
    "astral_helm": ("guard_greathelm", "Elmo Astral", 45, "legendary", "O visor brilha num violeta frio.", [0.75, 0.6, 1.0]),
    "astral_gauntlets": ("iron_gauntlets", "Manoplas Astrais", 45, "legendary", "Seguram até o que não tem peso.", [0.75, 0.6, 1.0]),
    "astral_greaves": ("iron_greaves", "Grevas Astrais", 45, "legendary", "Não deixam pegadas.", [0.75, 0.6, 1.0]),
}
# alquimia além do equipamento: poções (camada 1)
POTIONS = [("health_potion", {"mint": 1, "slime_gel": 1}, 1, 2), ("mana_potion", {"mint": 1, "frog_tongue": 1}, 4, 2)]
ARCANE_NAMES = {"mage_robe", "wizard_hat", "spellweaver_gloves", "arcane_orb"}


def tier_of(level: int) -> int:
    for i, (lo, hi) in enumerate(TIERS):
        if lo <= level <= hi:
            return i
    return len(TIERS) - 1


def load(name):
    return json.loads((BAL / (name + ".json")).read_text(encoding="utf-8"))


def predict(items, key, pick, level):
    """Dano/defesa pela reta dos itens não nomeados do mesmo grupo (mínimos quadrados)."""
    pts = [(v["level"], v[key]) for v in items.values() if pick(v) and key in v and not v.get("named") and "level" in v]
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    b = sum((p[0] - mx) * (p[1] - my) for p in pts) / max(1e-6, sum((p[0] - mx) ** 2 for p in pts))
    return max(1, round(my + b * (level - mx)))


def profession(it):
    t = it.get("type")
    if t == "weapon":
        return {"sword": "smithing", "bow": "leatherwork", "staff": "alchemy", "scepter": "alchemy"}[it["class"]]
    if it.get("metal") or it.get("needs") == "sword" or it.get("slot") == "ring":
        return "smithing"
    if it.get("slot") in ("amulet",) or it.get("needs") == "staff":
        return "alchemy"
    return "leatherwork"


STATION = {"smithing": "forge", "leatherwork": "leather", "alchemy": "alchemy"}


def gear_ingredients(prof, it, t, level):
    lo = TIERS[t][0]
    extra = (level - lo) // 4
    big = it.get("type") in ("weapon", "armor")
    ing = {}
    if prof == "smithing":
        ing[ORE[t]] = 3 + extra + (2 if big else 0)
        if it.get("type") == "weapon":
            ing[LOG[t]] = 1
    elif prof == "leatherwork":
        ing[HIDE[t]] = 2 + extra + (2 if big else 0)
        if it.get("type") == "weapon" or it.get("needs") == "bow":
            ing[LOG[t]] = 2 + extra
    else:
        if it.get("type") == "weapon":
            ing[LOG[t]] = 2 + extra
            ing["arcane_crystal"] = 1
        else:
            ing[HIDE[t]] = 2 + extra
    ing[ESS[t]] = 1 + (1 if big else 0) + extra // 2
    return ing


def main():
    items = load("items")
    # materiais e peças de chefe
    for mid, (name, rarity, price, desc) in MATERIALS.items():
        if mid not in items:
            items[mid] = {"name": name, "type": "material", "rarity": rarity, "price": price, "stack": True, "desc": desc}
    # itens novos copiando o visual do base
    for nid, (base, name, level, rarity, desc, col) in NEW_GEAR.items():
        b = dict(items[base])
        b.pop("named", None)
        b.update({"name": name, "level": level, "rarity": rarity, "desc": desc, "craft": True,
                  "color": {"$c": col + [1.0]}})
        if "damage" in b:
            cls = b["class"]
            b["damage"] = predict(items, "damage", lambda v, c=cls: v.get("class") == c, level)
        if "defense" in b:
            slot = b.get("slot", "")
            b["defense"] = predict(items, "defense",
                lambda v, t=b["type"], s=slot: v.get("type") == t and v.get("slot", "") == s, level)
        if "stats" in b:
            m = 1.0 + (level - items[base]["level"]) * 0.04
            b["stats"] = {k: (round(v * m) if isinstance(v, int) else round(v * m, 3)) for k, v in b["stats"].items()}
        b["price"] = round(items[base]["price"] * (1.0 + (level - items[base]["level"]) * 0.06))
        items[nid] = b

    recipes = {}
    old = load("recipes")
    for rid, r in old.items():
        if r.get("station") == "kitchen":
            recipes[rid] = r
    # poções e essências (alquimia)
    for pid, ing, lv, qty in POTIONS:
        recipes[pid] = {"station": "alchemy", "prof": "alchemy", "level": lv, "ingredients": ing, "gold": 0,
                        "out": pid, "qty": qty, "xp": 8 + 2 * lv, "learn": "npc"}
    for t, (lo, _hi) in enumerate(TIERS):
        recipes[ESS[t]] = {"station": "alchemy", "prof": "alchemy", "level": lo,
                           "ingredients": {HIDE[t]: 2, ESS_PART[t]: 1}, "gold": 2 * lo, "out": ESS[t], "qty": 1,
                           "xp": 10 + 3 * lo, "learn": "npc"}
    # equipamento
    gear = []
    for iid, it in items.items():
        if it.get("type") not in ("weapon", "armor", "gear") or it.get("named") or "@" in iid:
            continue
        if iid in ("wooden_sword",):   # a de treino continua só da loja/kit
            continue
        gear.append((it["level"], iid))
    gear.sort()
    top = {}
    for level, iid in gear:
        it = items[iid]
        prof = profession(it)
        t = tier_of(level)
        recipes[iid] = {"station": STATION[prof], "prof": prof, "level": level,
                        "ingredients": gear_ingredients(prof, it, t, level), "gold": 5 * level, "out": iid,
                        "qty": 1, "xp": 10 + 3 * level, "learn": "scroll" if t == 4 else "npc"}
        key = (prof, t)
        if key not in top or level >= recipes[top[key]]["level"]:
            top[key] = iid
    for (prof, t), rid in top.items():
        recipes[rid]["ingredients"][BOSS_PIECE[t]] = 1
        recipes[rid]["learn"] = "scroll"
    # pergaminhos
    scrolls_by_tier = {t: [] for t in range(len(TIERS))}
    for rid, r in recipes.items():
        if r["learn"] != "scroll":
            continue
        sid = "scroll_" + rid
        out_name = items[r["out"]]["name"]
        items[sid] = {"name": "Pergaminho: " + out_name, "type": "scroll", "rarity": items[r["out"]].get("rarity", "rare"),
                      "price": 20 + 4 * r["level"], "stack": True, "recipe": rid, "art": "recipe_scroll",
                      "desc": "Use para aprender a receita de %s." % out_name}
        scrolls_by_tier[tier_of(r["level"])].append(sid)

    # escreve
    jsonfmt.write(BAL / "items.json", items)
    lines = ["\t%s: %s" % (json.dumps(k), json.dumps(v, ensure_ascii=False)) for k, v in recipes.items()]
    (BAL / "recipes.json").write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    seeds = [i for i, v in items.items() if v.get("type") == "seed"]
    basic = [i for i, v in items.items() if v.get("type") in ("weapon", "armor", "gear") and v.get("rarity") == "common"
             and int(v.get("level", 1)) <= 10 and not v.get("named") and "@" not in i]
    stock = ["health_potion", "mana_potion"] + seeds + ["copper_ore", "pine_log", "hide_t1"] + basic
    jsonfmt.write(BAL / "shop.json", {"stock": stock})
    enemies = load("enemies")
    drops = {"slime_rainha": [["royal_jelly", 1.0]], "esqueleto_cavaleiro": [["knight_sigil", 0.04]],
             "lich": [["lich_phylactery", 1.0], ["abyss_core", 0.25]]}
    for t, boss in enumerate(TIER_BOSS):
        for sid in scrolls_by_tier[t]:
            drops.setdefault(boss, []).append([sid, SCROLL_CHANCE[t]])
    for kind, extra in drops.items():
        have = {e[0] for e in enemies[kind]["loot"]}
        enemies[kind]["loot"] += [e for e in extra if e[0] not in have]
    (BAL / "enemies.json").write_text(json.dumps(enemies, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8", newline="\n")
    print("receitas: %d (pergaminho: %d) · itens novos: %d · loja: %d" % (
        len(recipes), sum(1 for r in recipes.values() if r["learn"] == "scroll"),
        len(MATERIALS) + len(NEW_GEAR) + sum(len(v) for v in scrolls_by_tier.values()), len(stock)))


if __name__ == "__main__":
    main()
