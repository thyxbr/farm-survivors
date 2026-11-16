# Classes — Partes 2, 3 e 4 (design)

Data: 2026-11-16 · Status: decisões tomadas pelo Claude a pedido do usuário ("tome todas as decisões")
Base: parte 1 (`docs/superpowers/specs/2026-11-15-classes-e-criacao-design.md`, PR #103).
Branch: `classes-partes-2-4`, empilhada sobre `classes-criacao`.

O usuário pediu: implementar todas as etapas em ordem, tomando as decisões, com **atenção à modelagem
da personagem feminina, principalmente cabelo e seios, para parecer uma mulher**.

Toda decisão abaixo é do Claude, salvo onde diz "usuário".

---

## Parte 2 — Buffs de comida viram habilidades de classe

### Intenção
Os 8 buffs de combate que vinham da comida passam a ser habilidades das classes. A comida fica com
cura + um bônus pequeno e genérico, sem efeito de combate (decisão do usuário: opção B).

### Sistema de buffs (base comum)
- `Game.food_buffs` vira `Game.buffs: {buff_id: segundos}` e `food_mods` vira `buff_mods` (soma de todos).
  `mod()` soma `buff_mods`. O lifesteal (`game.gd:701`) lê de `buff_mods`.
- Tabela nova `data/balance/buffs.json`: `{id: {name, time, add: {stat: valor}, aura, desc, color}}`.
  `aura` é um estilo de `BuffAura.STYLES` (substitui `FOOD_AURA`/`style_for(food_id)`).
- Itens de comida deixam de ter `"buff": {...}` e passam a ter `"buff": "<id em buffs.json>"`.
- Quadro do grupo (`PartyRules.clean_buffs`, `Party.buff_left`, chips): valida contra `buffs.json`
  em vez de itens com `buff`. Chips mostram buffs de comida e de habilidade.
- Save: `food_buffs` não é salvo hoje (só sessão); continua assim.

### Comida (opção B do usuário): cura + bônus genérico
Mantém `heal_hp`/`heal_mp`/`heal_full`/`special` como estão, e o `special` (fire_nova, frost_nova) sai
(é combate). Bônus genéricos (só `xp`, `gold`, `magnet`, `regen` fora de combate não existe → sem regen):

| Comida | Buff novo (id) | Efeito | Tempo |
|---|---|---|---|
| bread | `food_full` "Barriga Cheia" | ímã +20% | 120 s |
| carrot_stew | `food_garden` "Vigor da Horta" | XP +5% | 180 s |
| spicy_soup | `food_warm` "Calor Picante" | ouro +5% | 180 s |
| dragon_chili | `food_chili` "Coragem do Chili" | ouro +8%, ímã +20% | 180 s |
| mint_tea | `food_mint` "Mente Fresca" | XP +8% | 180 s |
| garden_salad | `food_eagle` "Olhos de Águia" | XP +10%, ímã +40% | 240 s |
| pumpkin_pie | `food_pie` "Doce Lar" | ouro +10% | 240 s |
| valdoria_feast | `food_feast` "Banquete do Herói" | XP +12%, ouro +12%, ímã +40% | 300 s |

Os nomes antigos de combate passam para as habilidades. A cura dos pratos não muda.

### Habilidades de classe (o slot 3 vazio de cada classe + slots 2 e 4 do healer)
Todas são buffs com aura (`BuffAura`), recarga própria e custo de mana só para mago/healer.
Valores vêm dos buffs antigos, com tempo curto (combate).

| Classe | Slot | id | Nome | Efeito | Duração | Recarga | Nível | Alvo |
|---|---|---|---|---|---|---|---|---|
| Guerreiro | 3 | `sword_fury` | Fúria Picante | dano +30%, roubo de vida 2/acerto | 10 s | 28 s | 5 | si |
| Arqueiro | 3 | `bow_focus` | Olhos de Águia | crítico +15%, velocidade +10% | 10 s | 26 s | 5 | si |
| Mago | 3 | `staff_ember` | Bafo de Dragão | dano +20%, crítico +10%, recarga −20% | 10 s | 30 s, 25 mana | 5 | si |
| Healer | 2 | `scepter_ward` | Escudo de Luz (já existe "Em breve") | vida máx. +30, defesa +4, regen +3/s | 12 s | 22 s, 30 mana | 3 | si + aliados 8 m |
| Healer | 4 | `scepter_ult` | Banquete do Herói (ultimate, renomeia "Luz Sagrada") | cura cheia em si e aliados 8 m + dano +25%, velocidade +12%, recarga −15% | 12 s | fúria | 8 | si + aliados 8 m |

- Buffs de si: aplicados no cliente (como a comida hoje); visual remoto pelo `send_event`.
- Buffs em aliados: mesmo caminho da Cura da parte 1. Servidor valida classe healer, intervalo mínimo
  (`HealRules`, ganha intervalo por habilidade), alvos a 8 m vivos na zona, e manda
  `_you_got_buff(buff_id)`; o cliente aplica o buff da tabela (o servidor não manda números).
  `scepter_ult` também manda `_you_were_healed` com cura cheia (o servidor manda `max_hp` não; manda
  um valor alto fixo `ULT_HEAL = 9999` e o cliente limita ao máximo).
- Buff de habilidade e de comida com o mesmo stat somam.
- O kit continua 1/2/3/4; o slot 3 aparece na barra para todas as classes.

---

## Parte 3 — Árvore de passivas por classe

### Regras
- **Pontos de talento**: 1 por nível a partir do 2 (nível N → N−1 pontos). Personagens antigos
  recebem os pontos retroativos (calculados, não gravados: `pontos = level − 1 − gastos`).
- **Árvore**: cada classe tem 3 ramos × 3 talentos = 9 talentos; cada talento tem 3 níveis.
  Linha 2 de um ramo exige 3 pontos no ramo; linha 3 exige 6 pontos no ramo.
- **Efeito**: soma bônus em `mod()` (como `meta_passives`), com as mesmas chaves de stat. Alguns
  talentos mexem em habilidades da classe por chaves novas lidas pelos módulos
  (ex.: `heal_power`, `ability_time`).
- **Redistribuir**: no Mestre da Guilda (NPC da guilda) por `50 × nível` de ouro. Grátis até o nível 5.
- Tudo validado em `CharRules`: `learn_talent(id)`, `reset_talents()`; `CharState.talents: {id: nível}`;
  migração SQLite nova (coluna `talents` JSON, default `'{}'`).

### Tabela (`data/balance/talents.json`)
Guerreiro — ramos Fúria / Muralha / Tempestade:
- Fúria: `w_edge` dano +4%/nível · `w_bloodlust` roubo de vida +1/nível · `w_rage` (linha 3) Fúria Picante dura +2 s/nível
- Muralha: `w_hide` defesa +2/nível · `w_vigor` vida máx. +5%/nível · `w_stand` (linha 3) regen +1/s/nível
- Tempestade: `w_swift` velocidade +3%/nível · `w_focus` recarga −4%/nível · `w_whirl` (linha 3) dano do Turbilhão +10%/nível
Arqueiro — Precisão / Caçador / Vento:
- `a_aim` crítico +3% · `a_power` dano +4% · `a_eagle` (L3) Olhos de Águia dura +2 s
- `a_hide` defesa +2 · `a_vigor` vida +5% · `a_trap` (L3) ímã +15% e ouro +3%
- `a_swift` velocidade +3% · `a_focus` recarga −4% · `a_gale` (L3) dano do Vendaval +10%
Mago — Fogo / Gelo / Arcano:
- `m_fire` dano +4% · `m_crit` crítico +3% · `m_dragon` (L3) Bafo de Dragão dura +2 s
- `m_frost` defesa +2 · `m_mana` mana máx. +8% · `m_nova` (L3) atordoamento da Nova Gélida +0,2 s
- `m_focus` recarga −4% · `m_wis` regen de mana +10% · `m_meteor` (L3) dano dos Meteoros +10%
Healer — Luz / Proteção / Graça:
- `h_heal` cura +6% (`heal_power`) · `h_light` dano +4% · `h_dawn` (L3) Banquete dura +2 s
- `h_hide` defesa +2 · `h_vigor` vida +5% · `h_ward` (L3) Escudo de Luz dura +2 s
- `h_focus` recarga −4% · `h_mana` mana +8% · `h_grace` (L3) alcance da Cura e buffs +1 m (servidor também)

### Interface
Nova aba **Talentos** no menu do jogo (`game_menu.gd`), ao lado de Atributos: 3 colunas (ramos),
cada talento um botão com ícone/cor, nível `x/3`, descrição no tooltip, bloqueados apagados, pontos
livres no topo, botão "Redistribuir" só perto do Mestre da Guilda (ou mostra o custo e onde ir).

---

## Parte 4 — Corpo feminino

### Intenção
A escolha "Feminino" (já gravada e replicada como `body`) passa a mostrar um corpo de mulher,
legível de longe no estilo low-poly anime do jogo. **Atenção do usuário: cabelo e seios.**

### Decisões
- Novo GLB `assets/models/knight_f.glb`, gerado por `build_knight(female=True)` em
  `tools/blender/characters.py`, com **o mesmo esqueleto e nomes de ossos/nós** do `knight.glb`,
  para reaproveitar animações (`knight_anim.gd`), `KnightLook`, `CapeRig`, emotes e pontos de
  equipamento.
- Proporções (STYLE.md, heroico estilizado, sem exagero):
  - altura ~0,95× (cerca de 1,72 m), cabeça igual (fica levemente maior em proporção);
  - ombros ~0,85× da largura masculina; cintura ~0,8×; quadril ~1,05–1,1× (mais largo que a cintura,
    perto da largura dos ombros);
  - **seios**: volume claro e modesto no peito, feito na própria malha do tronco (os anéis do loft
    ganham projeção frontal arredondada na altura do peito, dois volumes separados por um vinco
    central suave), legível de perfil e de 3/4 sob a camisa. Nada sexualizado: proporção de
    heroína de RPG vestida;
  - braços e pernas mais finos (~0,85–0,9×), mãos e pés um pouco menores; pescoço mais fino;
  - rosto: mandíbula mais estreita e queixo fino (`jaw` menor), olhos um pouco maiores, cílios
    mais marcados, sobrancelha fina, lábio com cor levemente mais rosada.
- **Cabelo**: comprido, com franja e mechas laterais emoldurando o rosto, caindo nas costas até a
  altura das escápulas, preso num **rabo de cavalo alto** que balança (osso/nó próprio animado de
  leve como a capa, ou parado se o rig não permitir). Feito com `anime_hair` + mechas em camadas
  (`hair_locks`), cor castanho-escura padrão, com tons `mid`/`under` como os outros NPCs. Volume no
  topo da cabeça (não "capacete"), mechas pontudas anime. Tem que ler como cabelo longo de mulher
  de qualquer ângulo, inclusive de costas (câmera em terceira pessoa).
- Roupa base igual em estilo (camisa, calça, botas), recortada no corpo novo.
- **Equipamento**: as peças (gear.py) continuam as mesmas; no corpo feminino o `KnightLook`
  aplica escala por osso/peça (ombreiras e peitoral mais estreitos, peitoral com profundidade a
  mais na frente para cobrir o busto; capacete esconde parte do cabelo mas o rabo de cavalo
  continua aparecendo por baixo/atrás). Nenhuma peça pode atravessar o busto ou o cabelo de forma
  visível nas capturas de teste.
- `KnightLook`/`CharPreview`/jogador local/réplicas escolhem `knight_f.glb` quando `body == "f"`.
- A tela de criação perde o aviso "visual feminino chega em breve".
- Sem peças soltas (`LOOSE` vazio), estilo toon (cel + `_flat`), conferido com capturas:
  frente, perfil, 3/4 e costas, sem e com armadura completa, e lado a lado com o masculino.

### Verificação extra do Claude
Cada rodada de modelagem compara capturas lado a lado; o critério de pronto é: de costas e de
perfil, sem o rosto, dá para ler que é uma mulher (cabelo longo + silhueta cintura/quadril/busto).

---

## Fora do escopo
- Balanceamento fino de drops e cetros (passo próprio, pedido do usuário).
- Mais de um penteado ou cor de cabelo/pele na criação.
- Modelos femininos para NPCs.
