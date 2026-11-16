"""Script de uma vez (progressão, parte 1): escreve `level` e `level_max` nos EnemySpawn dos mapas.

Para cada bloco [node ...] com o script enemy_spawn.gd em vale/bosque/mina/pico, insere ou atualiza
`level = A` e `level_max = B` pela faixa do tipo (`kind`) naquele mapa, sem tocar no resto da cena.
Nível fixo (A == B) grava só `level` (level_max 0 = fixo). Tipo sem faixa na tabela: para com erro.

Uso (na raiz do projeto): python tools/balance/set_spawn_levels.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAPS = ROOT / "scenes" / "maps"

# mapa -> lista de (prefixo ou nome exato do kind, nível mín, nível máx); a primeira que casar vale.
# "*" no fim = prefixo; sem "*" = nome exato; "" = qualquer tipo.
TABLE = {
    "vale": [
        ("slime_gelo", 6, 9),
        ("slime*", 1, 4),          # slime, slime_veloz, slime_explosivo, slime_mae
        ("goblin_xama", 8, 11), ("goblin_bruto", 8, 11), ("goblin_dourado", 8, 11), ("goblin_campeao", 8, 11),
        ("goblin", 5, 8), ("goblin_arqueiro", 5, 8), ("goblin_bombardeiro", 5, 8),
        ("raptor*", 4, 9), ("tecela", 4, 9), ("flor_faminta", 4, 9), ("bocarrao", 4, 9), ("asa_couro", 4, 9),
        ("esqueleto*", 10, 13),
    ],
    "bosque": [("slime_rainha", 20, 20), ("", 12, 20)],
    "mina": [("esqueleto_cavaleiro", 30, 30), ("", 20, 30)],
    "pico": [("lich", 42, 42), ("", 30, 40)],
}


def level_range(map_id: str, kind: str) -> tuple[int, int]:
    for key, lo, hi in TABLE[map_id]:
        if key == "" or key == kind or (key.endswith("*") and kind.startswith(key[:-1])):
            return lo, hi
    raise SystemExit(f"{map_id}: tipo sem faixa na tabela: {kind}")


def process(map_id: str) -> int:
    path = MAPS / f"{map_id}.tscn"
    text = path.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource type="Script" path="res://scripts/map/enemy_spawn\.gd" id="([^"]+)"\]', text)
    if not m:
        raise SystemExit(f"{map_id}: sem enemy_spawn.gd")
    script_line = f'script = ExtResource("{m.group(1)}")'
    lines = text.split("\n")
    out: list[str] = []
    changed = 0
    i = 0
    while i < len(lines):
        if not lines[i].startswith("[node "):
            out.append(lines[i])
            i += 1
            continue
        # bloco do nó: do cabeçalho até a linha em branco (ou o próximo "[")
        j = i + 1
        while j < len(lines) and lines[j] != "" and not lines[j].startswith("["):
            j += 1
        block = lines[i:j]
        if script_line in block:
            kind = "slime"   # valor padrão do @export (não aparece na cena)
            for ln in block:
                km = re.match(r'kind = "([^"]*)"$', ln)
                if km:
                    kind = km.group(1)
            lo, hi = level_range(map_id, kind)
            body = [ln for ln in block[1:] if not ln.startswith(("level = ", "level_max = "))]
            # `elite` vem depois de level/level_max na ordem do script
            at = next((k for k, ln in enumerate(body) if ln.startswith("elite = ")), len(body))
            add = [f"level = {lo}"] + ([f"level_max = {hi}"] if hi > lo else [])
            new = [block[0]] + body[:at] + add + body[at:]
            if new != block:
                changed += 1
            block = new
        out.extend(block)
        i = j
    path.write_text("\n".join(out), encoding="utf-8", newline="")
    return changed


def main() -> None:
    for map_id in TABLE:
        print(f"{map_id}: {process(map_id)} pontos de nascimento")


if __name__ == "__main__":
    sys.exit(main())
