#!/usr/bin/env python3
"""Atribui `level` aos itens equipáveis de data/balance/items.json (migração da progressão).

Equipável = type weapon, armor ou gear (o mesmo critério de CharRules.slot_of).
Dentro de cada raridade, ordena pela força (damage; senão defense; senão price) e interpola
linearmente na banda da raridade. Armas, armaduras e acessórios são ordenados em grupos
separados (unidades diferentes), cada grupo cobrindo a banda inteira. Itens `named`
(de chefe) recebem o topo da banda. Armas iniciais das classes ficam no nível 1. Itens que já têm `level` não mudam: pode rodar de novo.
A edição é textual (insere uma linha `"level"` depois de `"rarity"`) para o diff só ter linhas novas.
Uso: python tools/balance/assign_item_levels.py
"""
import json
import re
import sys
from pathlib import Path

BANDS = {"common": (1, 8), "uncommon": (8, 15), "rare": (14, 24), "epic": (22, 35), "legendary": (35, 45)}
EQUIPABLE = ("weapon", "armor", "gear")
ROOT = Path(__file__).resolve().parents[2] / "data" / "balance"
PATH = ROOT / "items.json"


def strength(it):
    for k in ("damage", "defense", "price"):
        if k in it:
            return k, it[k]
    return "price", 0


def starter_weapons():
    """Armas iniciais das classes: nível 1, para o jogador poder reequipar a arma com que nasceu."""
    classes = json.load(open(ROOT / "classes.json", encoding="utf-8"))
    return {c["starter_weapon"] for c in classes.values() if "starter_weapon" in c}


def assign(items):
    """Devolve {id: level} só para os itens equipáveis sem level."""
    starters = starter_weapons()
    groups, out = {}, {}
    for iid, it in items.items():
        if it.get("type") not in EQUIPABLE or "level" in it:
            continue
        if iid in starters:
            out[iid] = 1
            continue
        kind, val = strength(it)
        groups.setdefault((it["rarity"], kind), []).append((val, iid))
    for (rar, _kind), lst in groups.items():
        lo, hi = BANDS[rar]
        regular = sorted((v, i) for v, i in lst if not items[i].get("named"))
        for pos, (_v, iid) in enumerate(regular):
            frac = pos / (len(regular) - 1) if len(regular) > 1 else 0.0
            out[iid] = lo + int(round(frac * (hi - lo)))
        for _v, iid in lst:
            if items[iid].get("named"):
                out[iid] = hi
    return out


def main():
    text = open(PATH, encoding="utf-8", newline="").read()
    levels = assign(json.loads(text))
    lines = text.split("\n")
    out, cur, done = [], None, set()
    for ln in lines:
        m = re.match(r'^\t"([^"]+)": \{$', ln)
        if m:
            cur = m.group(1)
        out.append(ln)
        if cur in levels and cur not in done and re.match(r'^\t\t"rarity": ', ln):
            out.append('\t\t"level": %d,' % levels[cur])
            done.add(cur)
    if done != set(levels):
        sys.exit("sem linha rarity: %s" % sorted(set(levels) - done))
    PATH.write_text("\n".join(out), encoding="utf-8", newline="")
    json.load(open(PATH, encoding="utf-8"))   # confere que continua JSON válido
    print("itens com level novo: %d" % len(done))


main()
