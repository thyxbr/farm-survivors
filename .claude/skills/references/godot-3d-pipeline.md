# Pipeline deste projeto (godot-3d) — LER ANTES DE QUALQUER SKILL BLENDER

Estas skills vieram do pacote genérico `arjun988/blender-skills` (MIT, ver `LICENSE-blender-skills`).
Quando algo aqui contradiz uma skill genérica, **este arquivo vence**.

## O jogo

- "Ecos de Valdoria": RPG de fantasia low-poly estilizado (Godot 4.7, Forward+), multiplayer.
- Visual: cores chapadas por material (Principled BSDF com Base Color/Roughness/Metallic/Emission),
  **sem texturas e sem UV** hoje. Leitura de silhueta e paleta valem mais que detalhe.
- Personagens **sem armature**: o jogo anima rotacionando nós (empties) por código.

## Como os modelos são feitos (código, não clique)

| Arquivo | Papel |
|---|---|
| `tools/blender/build_assets.py` | helpers `mat()`, `empty()`, `part()`, `export()` + builders dos props; registro `BUILDERS` |
| `tools/blender/characters.py` | personagens (`build_knight`, `build_elder`, `build_merchant`, `build_goblin`); helpers `limb`, `tbox`, `_finish`, `_place` |
| `tools/blender/preview_single.py` | folha frente / 3/4 / costas de um GLB; imprime `TRIS <nome> <n>`; modo `silhouette` |
| `tools/blender/preview_assets.py` | todos os GLBs lado a lado |
| `tools/blender/preview_closeup.py`, `preview_face.py` | close-ups de busto/rosto |
| `assets/models/*.glb` | saída (nome minúsculo, ex.: `knight.glb`) |

Novo asset = nova função `build_<nome>()` que usa os helpers e termina em `export("<nome>")`,
registrada em `BUILDERS`. Não crie arquivos `.blend` para assets do jogo.

### Executar (sempre via CLI em background)

```bash
# gera só os assets listados (sem ASSETS gera todos)
ASSETS=knight,chest "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py
# conferir visualmente (Read no PNG depois)
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/preview_single.py -- knight <scratchpad>/knight.png
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/preview_single.py -- knight <scratchpad>/knight_sil.png silhouette
```

**Não** rode `build_assets.py` pelo Blender MCP: exportar glTF de uma cena não ativa derrubou o Blender
(EXCEPTION_ACCESS_VIOLATION). O MCP (`mcp__Blender__*`, servidor oficial do Blender — não o
`ahujasid/blender-mcp` que as skills citam) serve para inspecionar/experimentar numa cena aberta;
o que for para o jogo vai para o script. Equivalências de nomes das skills:
`get_viewport_screenshot` → `mcp__Blender__render_viewport_to_path` / `get_screenshot_of_window_as_image`
ou, preferível, os scripts `preview_*.py`; `get_scene_info` → `mcp__Blender__get_objects_summary`;
`execute_blender_code` → `mcp__Blender__execute_blender_code`.

## Convenções que o código do jogo depende (NÃO quebrar)

- Unidade: metro. Personagem humano ~1,8–1,9 m; pés em Z=0; frente = **-Y no Blender** (+Z no Godot).
- Export: `export_format='GLB', export_yup=True, export_apply=True`, sem câmeras/luzes/animações.
- Hierarquia dos personagens: empty raiz (`Knight`, `Goblin`…) com filhos-pivô **`LegL`, `LegR`
  (quadril), `Body` (quadril), `Head` (pescoço), `ArmL`, `ArmR` (ombro)**. A posição do empty é a
  articulação; malhas penduradas nele. Usado por `scripts/enemies/enemy.gd`, `scripts/colony/soldier.gd`,
  `scripts/player/*`.
- **Nomes de peças são API**: `scripts/player/knight_look.gd` tinge/oculta peças pelo nome
  (`Helmet`, `Visor`, `Torso`, `ArmL_Gauntlet`, `LegL_Sabaton`, `Blade`, `Shield`…). Antes de
  renomear, mesclar ou remover uma peça, `grep` o nome em `scripts/`. As convenções `SM_`/`MAT_`/`COL_`
  das skills genéricas **não** se aplicam aos assets existentes.
- Materiais: nome curto com prefixo do asset (`k_steel`, `k_red`…); cor via `hexc("#RRGGBB")`.

## Orçamentos (calibrados nos modelos atuais, nov/2026)

| Tipo | Atual | Alvo |
|---|---|---|
| Prop pequeno (caixa, barril, baú, lamparina) | 36–108 tris | ≤ 200 |
| Prop médio (poço, fogueira, ruína, árvore) | 56–154 | ≤ 400 |
| Construção (casa) | 1.148 (1 objeto) | ≤ 1.200 |
| Inimigo simples (slime) | 224 | ≤ 600 |
| Personagem humanoide (knight, elder, merchant, goblin) | 2,4k–4,3k em 77–110 objetos | ≤ 5k tris, ≤ 20 materiais |

Godot gera LODs no import (`meshes/generate_lods=true`), então não crie LODs manuais.
Cada objeto vira um `MeshInstance3D`; ao criar personagens novos prefira juntar peças que nunca são
tingidas/ocultadas separadamente (mesmo pivô e material) para reduzir draw calls.

## Validação mínima antes de dizer "pronto"

1. Build via CLI sem erro; conferir linha `EXPORT <nome>`.
2. `preview_single.py` normal + `silhouette`, e olhar os PNGs (Read). Silhueta tem que dizer o que é.
3. `TRIS` dentro do orçamento acima.
4. Se mexeu em personagem: `grep` dos nomes de peças/pivôs em `scripts/` continua batendo.
5. Godot reimport + smoke test headless:
   `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import` e depois
   `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/world.tscn -- --smoketest`.
