"""Script de uma vez: os 11 arcos da Fase 1 (níveis 3 a 40), feitos das partes dos monstros de cada região.

- items.json: os arcos (depois do Arco Astral) e os pergaminhos dos dois que se aprendem com chefe.
- recipes.json: uma receita de couraria por arco, no nível dele, com o material do monstro da região.
- enemies.json: pergaminho do Arco Ossário no Cavaleiro Esqueleto e o da Quitina na Mãe-Verme.
(A loja não muda: foi reduzida ao básico na revisão da progressão; os arcos saem por receita e por drop.)

Idempotente: rodar de novo não duplica nada. Uso (na raiz do projeto): python tools/balance/add_bows_phase1.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BAL = ROOT / "data" / "balance"
sys.path.insert(0, str(Path(__file__).parent))
import jsonfmt  # noqa: E402

HIDE = ["hide_t1", "hide_t2", "hide_t3", "hide_t4", "hide_t5"]
LOG = ["pine_log", "oak_log", "silverbirch_log", "ashwood_log", "soulwood_log"]
ESS = ["essence_t1", "essence_t2", "essence_t3", "essence_t4", "essence_t5"]

# id: (nome, nível, raridade, dano, preço, cor, glow, stats, fx, descrição, modelo, material extra, aprende por)
BOWS = {
    "twig_bow": ("Arco de Galho", 3, "common", 10, 25, (0.55, 0.4, 0.24), 0.0, {}, "",
                 "Um galho torto e um barbante. Funciona melhor do que parece.", {}, "npc"),
    "raptor_bow": ("Arco de Osso de Raptor", 6, "common", 12, 55, (0.86, 0.8, 0.64), 0.0, {"agi": 1}, "",
                   "Costela de raptor amarrada com tendão. Ainda tem cheiro de capim.", {"raptor_claw": 3}, "npc"),
    "warden_bow": ("Arco do Vigia", 9, "common", 14, 70, (0.5, 0.36, 0.22), 0.0, {"agi": 1, "vit": 1}, "",
                   "O recurvo dos guardas da vila, com reforço de ferro no punho.", {"copper_ore": 2}, "npc"),
    "silk_bow": ("Arco de Seda Tecelã", 14, "uncommon", 17, 115, (0.92, 0.9, 0.86), 0.2, {"agi": 2}, "slow",
                 "Corda de seda de tecelã. As flechas deixam fios que grudam e deixam o alvo lento.",
                 {"spider_silk": 3}, "npc"),
    "frostfang_bow": ("Uivo da Geada", 17, "rare", 20, 170, (0.75, 0.88, 1.0), 0.5, {"agi": 3, "crit": 0.04}, "slow",
                      "Presas do Alfa da Matilha nas pontas. Cada flecha uiva e gela.", {"frost_pelt": 2}, "npc"),
    "lantern_bow": ("Arco Lanterna", 20, "rare", 22, 210, (0.95, 0.7, 0.3), 0.8, {"agi": 3, "speed": 0.04}, "splash",
                    "Dos kobolds das minas: uma lanterna no punho e pavio nas flechas, que estouram ao acertar.",
                    {"ember_core": 2}, "npc"),
    "crystal_bow": ("Arco de Cristal Cantante", 26, "rare", 26, 290, (0.7, 0.85, 1.0), 0.9, {"agi": 3, "crit": 0.05},
                    "pierce", "Lascas de um Golem de Cristal. A corda canta e a flecha atravessa como estilhaço.",
                    {"arcane_crystal": 2}, "npc"),
    "ossuary_bow": ("Arco Ossário", 29, "epic", 30, 370, (0.9, 0.86, 0.74), 0.4, {"agi": 3, "str": 2, "crit": 0.06},
                    "pierce", "Uma espinha inteira de Cavaleiro Esqueleto, vértebra por vértebra. Toda flecha perfura.",
                    {"bone_shard": 4}, "scroll"),
    "chitin_bow": ("Quitina da Mãe-Verme", 32, "epic", 32, 400, (0.62, 0.8, 0.95), 0.5, {"agi": 4, "vit": 2},
                   "splash", "Placas da carapaça da Mãe-Verme. As flechas espirram ácido em volta do alvo.",
                   {"iron_ore": 4, "arcane_crystal": 1}, "scroll"),
    "ashen_bow": ("Arco das Cinzas", 35, "epic", 34, 420, (0.45, 0.3, 0.26), 1.0, {"agi": 4, "crit": 0.06}, "splash",
                  "Freixo carbonizado da Encosta de Cinzas, com brasas vivas nas rachaduras. As flechas explodem em fagulhas.",
                  {"ember_core": 3}, "npc"),
    "yeti_bow": ("Arco do Ieti", 40, "epic", 40, 520, (0.82, 0.92, 1.0), 0.6, {"agi": 4, "str": 3, "hp": 25}, "slow",
                 "Chifre de Ieti Glacial curvado no frio. Pesado, gelado e implacável.", {"frost_pelt": 4}, "npc"),
}
# modelo provisório até cada arco ganhar o seu (um por rodada; trocar aqui e rodar de novo)
MODEL = {"twig_bow": "bw_twig_bow", "raptor_bow": "bw_raptor_bow", "warden_bow": "bw_warden_bow",
         "silk_bow": "bw_silk_bow", "frostfang_bow": "bw_frostfang_bow", "lantern_bow": "bw_lantern_bow",
         "crystal_bow": "bw_crystal_bow", "ossuary_bow": "bw_ossuary_bow", "chitin_bow": "bw_chitin_bow",
         "ashen_bow": "bw_ashen_bow", "yeti_bow": "bw_yeti_bow"}
SCROLL_DROP = {"ossuary_bow": ("esqueleto_cavaleiro", 0.04), "chitin_bow": ("mae_verme", 0.25)}


def tier(level):
    return min((level - 1) // 10, 4)


def load(name):
    return json.loads((BAL / (name + ".json")).read_text(encoding="utf-8"))


def insert_after(d, after, new):
    out = {}
    for k, v in d.items():
        if k in new:
            continue
        out[k] = v
        if k == after:
            out.update(new)
    return out


def main():
    items = load("items")
    new_items, new_scrolls = {}, {}
    for bid, (name, lv, rar, dmg, price, col, glow, stats, fx, desc, extra, learn) in BOWS.items():
        it = {"name": name, "type": "weapon", "class": "bow", "rarity": rar, "level": lv, "damage": dmg, "price": price,
              "color": {"$c": [col[0], col[1], col[2], 1.0]}}
        if glow:
            it["glow"] = glow
        if fx:
            it["fx"] = fx
        if stats:
            it["stats"] = stats
        it["desc"] = desc
        it["model"] = MODEL[bid]
        new_items[bid] = it
        if learn == "scroll":
            new_scrolls["scroll_" + bid] = {"name": "Pergaminho: " + name, "type": "scroll", "rarity": rar,
                                            "price": 20 + 4 * lv, "stack": True, "recipe": bid, "art": "recipe_scroll",
                                            "desc": "Use para aprender a receita de %s." % name}
    # inserção em texto: items.json tem trechos editados à mão em outro estilo, e regravar tudo sujaria o diff
    text = (BAL / "items.json").read_text(encoding="utf-8")
    for after, block in (("astral_bow", new_items), ("scroll_mithril_longbow", new_scrolls)):
        block = {k: v for k, v in block.items() if k not in items}
        if not block:
            continue
        body = jsonfmt.dumps(block).strip()[1:-1].strip("\n")         # entradas sem as chaves de fora
        start = text.index('\n\t"%s": {' % after)
        end = text.index("\n\t},", start) + len("\n\t},")             # fim do bloco do item `after`
        text = text[:end] + "\n" + body + "," + text[end:]
    (BAL / "items.json").write_text(text, encoding="utf-8", newline="\n")
    json.loads(text)                                                  # continua JSON válido

    recipes = load("recipes")
    for bid, b in BOWS.items():
        recipes.pop(bid, None)
    for bid, (name, lv, rar, dmg, price, col, glow, stats, fx, desc, extra, learn) in BOWS.items():
        t = tier(lv)
        ing = {HIDE[t]: 4 + (1 if rar == "epic" else 0), LOG[t]: 2, ESS[t]: 2}
        ing.update(extra)
        r = {"station": "leather", "prof": "leatherwork", "level": lv, "ingredients": ing, "gold": 5 * lv, "out": bid,
             "qty": 1, "xp": 3 * lv + 10, "learn": learn}
        # entra logo depois da última receita de nível <= lv (o arquivo segue a ordem de nível dentro das estações)
        keys = list(recipes)
        gear = [i for i, k in enumerate(keys) if items.get(recipes[k].get("out", ""), {}).get("type") in
                ("weapon", "armor", "gear")]
        pos = max([i for i in gear if int(recipes[keys[i]].get("level", 0)) <= lv], default=gear[0])
        recipes = insert_after(recipes, keys[pos], {bid: r})
    lines = ["\t%s: %s" % (json.dumps(k), json.dumps(v, ensure_ascii=False)) for k, v in recipes.items()]
    (BAL / "recipes.json").write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")

    enemies = load("enemies")
    for bid, (kind, chance) in SCROLL_DROP.items():
        loot = enemies[kind]["loot"]
        if not any(e[0] == "scroll_" + bid for e in loot):
            loot.append(["scroll_" + bid, chance])
    (BAL / "enemies.json").write_text(json.dumps(enemies, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8",
                                      newline="\n")

    print("arcos: %d · pergaminhos: %d" % (len(new_items), len(new_scrolls)))


if __name__ == "__main__":
    main()
