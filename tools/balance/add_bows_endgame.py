"""Script de uma vez: os 6 arcos míticos de endgame (níveis 48 a 50) e a raridade Mítico.

- rarity.json: "mythic" (Mítico, coral), acima de Lendário.
- progression.json: falha de fabricação e peso de sorteio do Mítico (0: nunca cai pela janela de nível) e
  "chase_drops" (o Rei dos Ventos: 0,5% em elite ou chefe de nível 48+, LootRules.roll).
- items.json: os arcos (nomeados: não entram no sorteio por nível) e os pergaminhos da Alvorada e do Crescente.
- recipes.json: todas por pergaminho (pedem peça de chefe). Presa do Dragão pede um troféu de cada chefe
  ("Provas do Caçador"); Raiz-Mãe consome o Arco Élfico e a colheita da horta.
- progression.json dungeons: Suspiro do Abismo e os pergaminhos da Alvorada e da Presa no chefe do Abismo; o do
  Crescente no chefe do Pico; o da Raiz-Mãe no chefe do Bosque.

Idempotente. Uso (na raiz do projeto): python tools/balance/add_bows_endgame.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BAL = ROOT / "data" / "balance"
sys.path.insert(0, str(Path(__file__).parent))
import jsonfmt  # noqa: E402

# id: (nome, nível, dano, preço, cor, glow, stats, fx, descrição)
BOWS = {
    "abyss_bow": ("Suspiro do Abismo", 50, 58, 2000, (0.55, 0.32, 0.95), 1.4, {"agi": 8, "str": 3, "crit": 0.12},
                  "vortex", "Costelas de algo que dorme no fundo do Abismo. O tiro tensionado ao máximo abre uma "
                  "fenda que puxa os inimigos e implode."),
    "dawn_bow": ("Alvorada, a Asa da Fênix", 49, 55, 1900, (1.0, 0.72, 0.25), 1.6, {"agi": 8, "int": 4, "crit": 0.1},
                 "solar", "Penas da fênix que se abrem como asas ao puxar. Cada flecha marca o alvo; a terceira "
                 "marca derruba uma coluna de sol."),
    "dragon_bow": ("Presa do Dragão Ancestral", 50, 60, 2100, (0.95, 0.35, 0.15), 1.5,
                   {"agi": 7, "str": 5, "crit": 0.1}, "dragonfire",
                   "Feito com um troféu de cada grande caçada. O tiro tensionado ao máximo chama uma chuva de flechas "
                   "de fogo sobre o alvo."),
    "wind_bow": ("Rei dos Ventos", 48, 52, 1800, (0.6, 0.92, 1.0), 1.2, {"agi": 9, "speed": 0.1, "crit": 0.08},
                 "gale", "Toda flecha empurra. A tensionada ricocheteia de inimigo em inimigo e o vento joga o "
                 "arqueiro para trás."),
    "crescent_bow": ("Crescente Gêmeo", 49, 54, 1900, (0.82, 0.86, 1.0), 1.3, {"agi": 8, "crit": 0.18},
                     "crescent", "Forjado sob a lua. Solte no instante exato da tensão máxima: crítico garantido e uma "
                     "flecha fantasma repete o tiro."),
    "root_bow": ("Raiz-Mãe", 50, 54, 1900, (0.45, 0.85, 0.35), 1.2, {"agi": 7, "vit": 5, "hp": 60}, "bramble",
                 "O Arco Élfico criou raízes e floresceu. As flechas viram espinheiros; cada abate faz nascer uma flor "
                 "que cura quem estiver perto."),
}
SCROLLS = ("dawn_bow", "crescent_bow", "dragon_bow", "root_bow")
RECIPES = {
    "dawn_bow": ({"hide_t5": 6, "soulwood_log": 3, "essence_t5": 3, "phoenix_staff": 1, "abyss_core": 1}, "scroll"),
    "crescent_bow": ({"hide_t5": 6, "soulwood_log": 3, "essence_t5": 3, "mithril_ore": 8, "lich_phylactery": 2},
                     "scroll"),
    "dragon_bow": ({"hide_t5": 6, "soulwood_log": 3, "essence_t5": 3, "goblin_crown": 1, "royal_jelly": 1,
                    "knight_sigil": 1, "lich_phylactery": 1, "abyss_core": 1}, "scroll"),
    "root_bow": ({"elven_bow": 1, "soulwood_log": 4, "essence_t5": 3, "pumpkin": 10, "mint": 10, "wheat": 10,
                  "carrot": 10, "abyss_core": 1}, "scroll"),
}
DUNGEON_LOOT = {"dg_final": [["abyss_bow", 0.06], ["scroll_dawn_bow", 0.15], ["scroll_dragon_bow", 0.12]],
                "dg_pico": [["scroll_crescent_bow", 0.12]], "dg_bosque": [["scroll_root_bow", 0.1]]}
CHASE = [{"item": "wind_bow", "chance": 0.005, "min_level": 48, "elite": True}]


def load(name):
    return json.loads((BAL / (name + ".json")).read_text(encoding="utf-8"))


def insert_text(path, after, block, have):
    """Entradas novas logo depois do bloco de `after`, em texto (não reformata o resto do arquivo)."""
    block = {k: v for k, v in block.items() if k not in have}
    if not block:
        return
    text = path.read_text(encoding="utf-8")
    body = jsonfmt.dumps(block).strip()[1:-1].strip("\n")
    start = text.index('\n\t"%s": {' % after)
    end = text.index("\n\t},", start) + len("\n\t},")
    text = text[:end] + "\n" + body + "," + text[end:]
    json.loads(text)
    path.write_text(text, encoding="utf-8", newline="\n")


def main():
    rarity = load("rarity")
    if "mythic" not in rarity:
        rarity["mythic"] = {"name": "Mítico", "color": {"$c": [1.0, 0.42, 0.36, 1.0]}, "rank": 5}
        jsonfmt.write(BAL / "rarity.json", rarity)

    # progression.json é formatado à mão: edições pontuais no texto
    path = BAL / "progression.json"
    text = path.read_text(encoding="utf-8")
    if '"mythic"' not in text:
        text = text.replace('"epic": 2, "legendary": 0}', '"epic": 2, "legendary": 0, "mythic": 0}', 1)
        text = text.replace('"epic": 0.25, "legendary": 0.35}', '"epic": 0.25, "legendary": 0.35, "mythic": 0.4}', 1)
    for dg, extra in DUNGEON_LOOT.items():
        start = text.index('"%s": {"monster"' % dg)
        end = text.index("]]}", start)
        add = "".join(', ["%s", %s]' % (e[0], e[1]) for e in extra if '"%s"' % e[0] not in text[start:end])
        text = text[:end] + "]" + add + text[end + 1:]
    if '"chase_drops"' not in text:
        anchor = text.index('\t"dungeons": {')
        text = text[:anchor] + '\t"chase_drops": %s,\n' % json.dumps(CHASE) + text[anchor:]
    prog = json.loads(text)
    assert prog["gear_drop"]["rarity_weight"]["mythic"] == 0 and prog["craft_fail"]["chance"]["mythic"] == 0.4
    path.write_text(text, encoding="utf-8", newline="\n")

    items = load("items")
    new_items, new_scrolls = {}, {}
    for bid, (name, lv, dmg, price, col, glow, stats, fx, desc) in BOWS.items():
        new_items[bid] = {"name": name, "type": "weapon", "class": "bow", "rarity": "mythic", "level": lv,
                          "named": True, "damage": dmg, "price": price,
                          "color": {"$c": [col[0], col[1], col[2], 1.0]}, "glow": glow, "fx": fx, "stats": stats,
                          "desc": desc, "model": "bw_" + bid}
        if bid in SCROLLS:
            new_scrolls["scroll_" + bid] = {"name": "Pergaminho: " + name, "type": "scroll", "rarity": "mythic",
                                            "price": 20 + 4 * lv, "stack": True, "recipe": bid,
                                            "art": "recipe_scroll",
                                            "desc": "Use para aprender a receita de %s." % name}
    insert_text(BAL / "items.json", "yeti_bow", new_items, items)
    insert_text(BAL / "items.json", "scroll_mithril_longbow", new_scrolls, items)

    recipes = load("recipes")
    for bid, (ing, learn) in RECIPES.items():
        lv = BOWS[bid][1]
        recipes.pop(bid, None)
        recipes[bid] = {"station": "leather", "prof": "leatherwork", "level": lv, "ingredients": ing,
                        "gold": 5 * lv, "out": bid, "qty": 1, "xp": 3 * lv + 10, "learn": learn}
    lines = ["\t%s: %s" % (json.dumps(k), json.dumps(v, ensure_ascii=False)) for k, v in recipes.items()]
    (BAL / "recipes.json").write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    print("arcos: %d · pergaminhos: %d · receitas: %d" % (len(new_items), len(new_scrolls), len(RECIPES)))


if __name__ == "__main__":
    main()
