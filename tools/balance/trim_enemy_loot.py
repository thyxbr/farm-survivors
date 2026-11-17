"""Script de uma vez (progressão, parte 1): enxuga o loot dos monstros em data/balance/enemies.json.

- Monstro comum (sem `boss`): tira do `loot` toda entrada de equipamento (arma, armadura, peça);
  materiais, poções e sementes ficam com a mesma chance. O equipamento passa a vir do sorteio por nível
  (LootRules.roll, progression.json gear_drop).
- Chefes (goblin_king, slime_rainha, lich): mantêm materiais/poções/sementes; do equipamento ficam só as
  entradas `named` (se houver) ou, sem nomeadas, as de maior chance; no máximo 3, e a soma das chances de
  equipamento fica <= 1,0 (se passar, as chances são reduzidas na mesma proporção).

Uso (na raiz do projeto): python tools/balance/trim_enemy_loot.py
Reescrever o arquivo mantém o formato (tabulação, UTF-8); rode `git diff` para revisar.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOSSES = ("goblin_king", "slime_rainha", "lich")
GEAR_TYPES = ("weapon", "armor", "gear")
MAX_BOSS_GEAR = 3


def trim_boss(loot: list, items: dict) -> list:
    gear = [e for e in loot if items[e[0]]["type"] in GEAR_TYPES]
    rest = [e for e in loot if items[e[0]]["type"] not in GEAR_TYPES]
    named = [e for e in gear if items[e[0]].get("named", False)]
    pool = named if named else gear
    keep = sorted(pool, key=lambda e: -e[1])[:MAX_BOSS_GEAR]  # sort estável: empate fica na ordem original
    total = sum(e[1] for e in keep)
    if total > 1.0:
        keep = [[e[0], round(e[1] / total, 3)] for e in keep]
    return rest + keep


def main() -> None:
    path = ROOT / "data" / "balance" / "enemies.json"
    items = json.loads((ROOT / "data" / "balance" / "items.json").read_text(encoding="utf-8"))
    raw = path.read_text(encoding="utf-8")
    enemies = json.loads(raw)
    for kind, t in enemies.items():
        loot = t.get("loot", [])
        if kind in BOSSES:
            new = trim_boss(loot, items)
        elif not t.get("boss", False):
            new = [e for e in loot if items[e[0]]["type"] not in GEAR_TYPES]
        else:
            new = loot
        if new != loot:
            print(f"{kind}: {len(loot)} -> {len(new)} entradas")
            if kind in BOSSES:
                print("   antes :", [(e[0], e[1]) for e in loot if items[e[0]]["type"] in GEAR_TYPES])
                print("   depois:", [(e[0], e[1]) for e in new if items[e[0]]["type"] in GEAR_TYPES])
            t["loot"] = new
    path.write_text(json.dumps(enemies, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
