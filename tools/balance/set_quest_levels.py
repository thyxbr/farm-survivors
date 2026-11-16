"""Script de uma vez (progressão, parte 1): escreve `level` e recalcula `reward_xp` em data/balance/quests.json.

Nível da missão:
  - tipo `kill`: nível médio da faixa do alvo (`target`) no mapa de `where` (tabela de set_spawn_levels.py;
    alvo fora da tabela, como o Rei Goblin, usa o `ref_level` de enemies.json; sem alvo = goblin);
  - outros tipos da corrente principal: nível da missão anterior da corrente (começa em 1);
  - outros tipos secundários: nível mais baixo do mapa de `where` (sem `where` = 1).
O nível fica editável no JSON; rodar de novo sobrescreve.
XP: reward_xp = round(quest_xp_share × xp_to_next(level) × peso), peso 1,5 principal / 1,0 secundária /
0,6 contrato do quadro (giver_id "board"). xp_to_next espelha ProgressionRules.xp_to_next.

Uso (na raiz do projeto): python tools/balance/set_quest_levels.py [--write]
"""
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BAL = ROOT / "data" / "balance"
W_MAIN, W_SIDE, W_BOARD = 1.5, 1.0, 0.6

_spec = importlib.util.spec_from_file_location("set_spawn_levels", Path(__file__).with_name("set_spawn_levels.py"))
spawn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(spawn)


def map_at(x: float, z: float) -> str:
    """Espelha Regions.region_at: fora das regiões = vale."""
    for mid, ox, oz, half in (("bosque", 0, 800, 70), ("mina", 800, 0, 70), ("pico", 800, 800, 62)):
        if abs(x - ox) <= half + 30 and abs(z - oz) <= half + 30:
            return mid
    return "vale"


def xp_to_next(prog: dict, level: int) -> int:
    if level >= prog["max_level"]:
        return 0
    c = prog["xp_curve"]
    return int(c["base"] * max(level, 1) ** c["exp"] * c.get("late", {}).get(str(level), 1.0))


def kill_level(enemies: dict, map_id: str, kind: str) -> int:
    try:
        lo, hi = spawn.level_range(map_id, kind)
        return round((lo + hi) / 2)
    except SystemExit:
        return int(enemies[kind]["ref_level"])


def main() -> None:
    prog = json.loads((BAL / "progression.json").read_text(encoding="utf-8"))
    enemies = json.loads((BAL / "enemies.json").read_text(encoding="utf-8"))
    path = BAL / "quests.json"
    quests = json.loads(path.read_text(encoding="utf-8"))
    share = float(prog["quest_xp_share"])
    chain_level = 1
    rows = []
    for qid, q in quests.items():
        where = q.get("where")
        map_id = map_at(*where) if where else "vale"
        side = bool(q.get("side", False))
        if q.get("type") == "kill":
            level = kill_level(enemies, map_id, q.get("target") or "goblin")
        elif side:
            level = spawn.level_range(map_id, "")[0] if map_id != "vale" else 1
        else:
            level = chain_level
        if not side:
            chain_level = level
        level = max(1, min(int(prog["max_level"]), level))
        weight = W_BOARD if q.get("giver_id") == "board" else (W_SIDE if side else W_MAIN)
        new_xp = max(1, round(share * xp_to_next(prog, level) * weight))
        rows.append((qid, level, q["reward_xp"], new_xp))
        # `level` entra logo depois de reward_xp (diff pequeno); se já existe, só atualiza
        out = {}
        for k, v in q.items():
            if k == "level":
                continue
            out[k] = new_xp if k == "reward_xp" else v
            if k == "reward_xp":
                out["level"] = level
        quests[qid] = out
    print(f"{'id':<22}{'nivel':>6}{'xp antigo':>11}{'xp novo':>9}")
    for r in rows:
        print(f"{r[0]:<22}{r[1]:>6}{r[2]:>11}{r[3]:>9}")
    if "--write" in sys.argv:
        path.write_text(json.dumps(quests, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="")
        print("gravado:", path)


if __name__ == "__main__":
    sys.exit(main())
