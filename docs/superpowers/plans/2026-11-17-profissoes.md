# Profissões e craft (parte 3 da progressão): plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sete profissões com nível 1–50 por personagem (coleta: mineração, lenhador, fazenda; produção: ferraria,
couraria, alquimia, culinária), materiais em 5 camadas ligadas às regiões, receitas de todas as estações num só
`recipes.json`, qualidade de craft (normal/fina/obra-prima), pergaminhos de receita e a loja cortada ao básico.

**Architecture:** Regras puras novas em `scripts/character/craft_rules.gd` (nível/XP de profissão, fabricar,
aprender, qualidade), chamadas pelo `CharacterService` como hoje o `cook`. O estado ganha `professions` e
`recipes` no `CharState` (save e rede). A qualidade é um sufixo no id (`iron_sword@fina`) e as variantes são
geradas a partir dos itens base quando as tabelas carregam (`ItemQuality.expand`), então inventário e equipamento
continuam guardando só ids. Coleta (veios, árvores, horta) dá XP pela mesma regra.

**Tech Stack:** Godot 4.7 / GDScript; testes `tests/unit/run.gd`, smoke, vila, net (skill smoke-check).

**Spec:** `docs/superpowers/specs/2026-11-16-progressao-design.md`, seção "3. Profissões e craft", seção 0 e
"Decisões do usuário na revisão" (loja só com o básico). O usuário pediu para seguir sem perguntas: as chamadas
abaixo marcadas *chamada minha* ficam documentadas no `docs/BALANCEAMENTO.md`.

## Global Constraints

- Todo número em `data/balance/*.json` (professions.json novo, recipes.json, world_nodes.json, progression.json,
  shop.json, items.json). Nada de número de balanceamento fixo em `.gd`.
- Regras puras sem autoload (`CraftRules`, `ItemQuality`, `CharRules`, `CharState`).
- Saves antigos carregam: `professions`/`recipes` ausentes = vazio (nível 1). Item com sufixo de qualidade cujo
  base sumiu é descartado como qualquer id desconhecido.
- Solo e online iguais (o servidor decide craft e coleta).
- Ícones: material novo precisa de arte em `assets/ui/items/<id>.png` (teste `test_item_art`). *Chamada minha:*
  arte provisória gerada por script (recolor das pinturas existentes e desenho simples), listada no
  `docs/ICONES_PROMPTS.md` para o usuário trocar pela pintura de verdade.
- PR sobe `config/version` (0.31.0 → 0.32.0).

## Decisões (chamadas minhas)

- **Quem fabrica o quê:** Ferraria (forja do Doran) = espadas e peças de metal (cota, elmo de ferro, manoplas,
  grevas, escudos, anéis). Couraria (bancada nova na vila, ao lado do empório) = arcos, aljavas e peças leves
  (couro, capuz, luvas, botas, túnica, colete). Alquimia (Pip) = poções, as **essências** de cada camada (que
  todo equipamento pede) e as armas arcanas (cajados, cetros, orbes, amuletos, chapéu e manto de mago).
  Culinária = a cozinha de hoje.
- **Materiais por camada** (t = 1..5): minério (`copper_ore`, `iron_ore`, `silver_ore`, `mithril_ore`,
  `astralite_ore`), madeira (`pine_log`, `oak_log`, `silverbirch_log`, `ashwood_log`, `soulwood_log`), couro
  (`hide_t1..t5`, cai de qualquer monstro do mundo com nível na camada, chance em progression.json
  `tier_drop`) e essência (`essence_t1..t5`, só da alquimia: 2 couros da camada + 1 parte de monstro).
  As partes de monstro de hoje (gosma, orelha, osso...) continuam caindo e entram nas receitas.
- **Peças raras de chefe** (receita de ponta de cada camada): t1 `goblin_crown` (Rei Goblin), t2 `royal_jelly`
  (Slime Rainha), t3 `knight_sigil` (Cavaleiro Esqueleto do Salão, nível 30), t4 `lich_phylactery` (Lich),
  t5 `abyss_core` (região de elite agora; dungeons na parte 4).
- **Aprender:** receita com `"learn": "npc"` é conhecida por todos; `"learn": "scroll"` pede o pergaminho
  `scroll_<receita>` (item `type: "scroll"`, usar = aprender). Pergaminhos caem dos chefes (e das dungeons na parte 4).
  Ponta de cada camada e toda a camada 5 são por pergaminho.
- **Variar receitas:** a primeira fabricação de cada receita rende `first_craft_mult` (3×) de XP.
- **Itens novos** (só buracos): t3 `silver_gauntlets`, `silver_greaves`; t4 `mithril_longbow`, `ashwood_staff`,
  `mithril_helm`, `mithril_gauntlets`, `mithril_greaves`; t5 `astral_blade`, `astral_bow`, `soulwood_staff`,
  `astral_scepter`, `astral_plate`, `astral_helm`, `astral_gauntlets`, `astral_greaves`. Reaproveitam modelos.
- **Veios e árvores:** 2–3 golpes; mineração/lenhador têm nível por tipo de nó. Árvores coletáveis são nós
  `resource_node` novos (o modelo da árvore do mapa), não as árvores de enfeite.

## Review Focus

- Save antigo sem `professions`/`recipes` e com itens que mudaram de preço/loja: carrega igual → teste em CharState.
- Fabricar sem ingredientes, sem ouro, abaixo do nível, sem conhecer a receita, com `times` absurdo → recusa
  sem mexer no inventário → testes em CraftRules.
- Qualidade: variante `@fina` equipa, vende, encanta (encanto do item base) e volta do save → testes.
- Coleta online: XP da profissão vem do servidor junto com o item (net_test já coleta ferro).
- Loja cortada: o smoke compra itens que saíram da loja → ajustar o smoke, não a loja.

---

### Task 1: Tabelas e regras puras de profissão e craft

**Files:** Create `data/balance/professions.json`, `scripts/character/craft_rules.gd`,
`scripts/character/item_quality.gd`, `tests/unit/test_craft_rules.gd`. Modify `data/balance/recipes.json`
(novo formato), `data/balance/progression.json` (`quality_chance`, `quality_mult`, `tier_drop`),
`scripts/balance/balance_tables.gd` (NAMES += "professions"; expand de qualidade ao carregar),
`scripts/character/char_state.gd` (`professions`, `recipes`), `scripts/character/char_rules.gd` (`cook` →
CraftRules, `consume` de pergaminho), `scripts/character/character_service.gd` (op `craft`),
`scripts/character/enchant_rules.gd` (id base).

**Interfaces:**
- `professions.json`: `{"professions": {id: {"name", "kind": "gather"|"craft", "station"?}}, "max_level": 50,
  "xp_curve": {"base", "exp"}, "xp_diff": [[de, até, mult]...], "first_craft_mult": 3}`.
- `recipes.json`: `{id: {"station": "kitchen"|"forge"|"leather"|"alchemy", "prof", "level", "ingredients":
  {item: qtd}, "gold", "out", "qty", "xp", "learn": "npc"|"scroll"}}`.
- `CraftRules.level(s, prof) -> int`, `xp_to_next(bt, lv) -> int`, `gain(s, bt, prof, base_xp, src_level) ->
  Array` (eventos; sobe de nível), `knows(s, bt, rid) -> bool`, `can_craft(s, bt, rid) -> Dictionary`
  (`{"n", "err"}`), `craft(s, bt, rid, times, rng) -> Dictionary` (resultado como o de `cook`, com `"n"`),
  `learn(s, bt, rid) -> Dictionary`, `quality_roll(bt, prof_lv, recipe_lv, rng) -> String` ("", "fina", "obra").
- `ItemQuality.base(id) -> String`, `quality(id) -> String`, `expand(items, recipes, prog) -> Dictionary`.

- [ ] Testes primeiro (`test_craft_rules.gd`): curva e subida de nível; XP cai com receita bem abaixo; primeira
  vez 3×; craft gasta ingredientes e ouro e dá o item; recusas (`faltam_ingredientes`, `ouro`, `nivel`,
  `desconhecida`, `args`) sem mexer no estado; lote (`times`); qualidade: chance cresce com a diferença, variante
  existe na tabela com dano maior; pergaminho ensina e some; save ida-e-volta com professions/recipes; save antigo.
- [ ] Implementar; `cook` passa a chamar `craft` (o que a cozinha já faz continua igual); `test_char_rules`
  (`test_cook`) continua passando.

### Task 2: Materiais, ícones, catálogo e loja

**Files:** `data/balance/items.json` (materiais t1–t5, peças de chefe, pergaminhos, 15 itens novos),
`data/balance/recipes.json` (gerado por `tools/balance/make_recipes.py`, depois editável à mão),
`data/balance/enemies.json` (peças de chefe e pergaminhos no loot dos chefes), `data/balance/shop.json`,
`scripts/character/loot_rules.gd` (couro da camada), `assets/ui/items/*.png` (arte provisória por
`tools/icons/make_material_icons.py`), `scripts/ui/item_icon_models.gd` (família scroll), `docs/ICONES_PROMPTS.md`.

- [ ] Teste `test_recipe_catalog`: cada camada tem ≥ 1 arma por classe (espada, arco, cajado, cetro) e 1 peça por
  espaço de armadura (head, armor, hands, feet) fabricável; toda receita aponta para itens existentes; a de maior
  nível de cada camada pede a peça de chefe e é por pergaminho; todo pergaminho tem receita; loja só com poções,
  sementes, materiais da camada 1 e equipamento comum de nível ≤ 10.
- [ ] Gerar, rodar os testes de arte/ícone 3D, `test_balance` (snapshot sem as chaves novas).

### Task 3: Coleta com XP (veios, árvores, horta)

**Files:** `data/balance/world_nodes.json` (tipos por camada com `prof`, `level`, `xp`, `hits` 2–3, modelo),
`data/balance/crops.json` (`level` da semente), `scripts/world/world_harvest.gd`, `scripts/world/world_resource_node.gd`
(visual de árvore e tinta do minério), `scripts/autoload/econ.gd` (coleta concede XP de profissão),
`scripts/character/character_service.gd`/`char_rules.gd` (plantar pede nível de fazenda; colher dá XP),
cenas `scenes/maps/*.tscn` (nós de coleta novos com `node_id` novos).

- [ ] Testes: `WorldHarvest.node_def` traz prof/nível/xp; coletar dá item + XP (pura, via CraftRules.gain);
  plantar semente acima do nível recusa; colher dá XP; validação dos mapas (node_id único) passa.

### Task 4: Telas: estações e aba Profissões

**Files:** Create `scripts/ui/crafting_ui.gd`, `scripts/world/crafting_station.gd`. Modify `story_dialogue.gd`
(serviços "Forjar" no Doran, "Alquimia" na Pip), `world.gd` (`open_crafting(station)`, fábrica da bancada de
couraria via MapEntity `kind = "station"`, `ref = "leather"`), `scenes/maps/vale.tscn` (a bancada),
`game_menu.gd` (aba "Profissões" com nível/XP e receitas conhecidas), `game.gd` (espelho de professions/recipes,
`craft()`), `cooking_ui.gd` (lê o formato novo).

- [ ] Smoke: abrir cada estação, fabricar uma receita de nível 1 com os ingredientes dados, conferir XP e item;
  aba Profissões abre.

### Task 5: Documentação, versão, testes e PR

- [ ] `docs/BALANCEAMENTO.md`: seção Profissões e craft (cada campo, valor seguro). `docs/EDITOR_MAPA.md`: nó de
  coleta por camada e a bancada.
- [ ] `config/version` 0.32.0; skill smoke-check completa; PR; merge.
