# Mantos épicos — plano de implementação

**Objetivo:** texturas animadas e partículas nos sete conjuntos de mago de nível 50, com a galáxia do
Ceifador no disco do capuz e nas costas do manto.

**Arquitetura:** `GearFx` (novo, `scripts/player/gear_fx.gd`) roda no fim de `KnightLook.apply`: lê o
nome do material original de cada superfície das peças `Gear_*` e troca por um `ShaderMaterial` animado
(cache por nome); também prende as partículas do conjunto ao modelo e as registra em `look_nodes`.
Os shaders ficam em `assets/shaders/gear_*.gdshader`. A galáxia usa UV em metros (projeção plana das
costas), gravado por `g_export` em `tools/blender/gear.py` só para `h_reaper` e `a_reaper`.

**Spec:** `docs/superpowers/specs/2026-11-18-mantos-epicos-design.md`

## Restrições
- Funciona com e sem toon (`--notoon`); nada de partícula ou shader no servidor sem janela.
- Nenhuma peça solta (`LOOSE` no build do Blender).
- Subir `config/version` antes do merge.

## Pontos de atenção na revisão
- Roupa com esqueleto (PivotSkin): a galáxia tem que acompanhar o tecido (por isso UV, não posição).
- Troca de equipamento: partículas antigas somem, materiais não vazam para outra peça.
- Corpo feminino: sem `_f.glb` próprio cai no GLB masculino; o efeito tem que valer igual.
- Material tingido (`t1_`/`t2_`) não pode ser trocado por engano: só nomes da tabela do `GearFx`.
- Horda com vários jogadores: poucas partículas por personagem (≤ 24 vivas).

## Tarefas
1. **Galáxia do Ceifador**
   - `assets/shaders/gear_galaxy.gdshader`: espiral, nebulosa e estrelas a partir de UV em metros;
     parâmetros `center`, `radius`, `cloth` (cor do tecido sob a galáxia), `spin`.
   - `gear.py`: `g_galaxy_uv(style)` em `g_export`; capuz sem braços/estrelas de geometria.
   - Reconstruir `h_reaper` e `a_reaper` (Blender CLI, `ASSETS=h_reaper,a_reaper`), conferir `LOOSE`.
2. **`GearFx`**: tabela material → efeito, `apply(model, made)`, partículas por conjunto; chamada em
   `KnightLook.apply`. Teste unitário `tests/unit/test_gear_fx.gd`: todo material da tabela existe em
   algum GLB de `assets/models/gear`, e todo estilo de fim de jogo tem pelo menos um efeito.
3. **Captura do Ceifador no jogo** (frente, costas, câmera do jogo) e validação com o Henrique.
4. **Outros seis conjuntos**: `gear_glow.gdshader` (pulso/energia correndo, por posição) com variações
   por conjunto, e partículas próprias.
5. **Fechamento**: testes unitários, smoke test, versão 0.46.0, PR.
