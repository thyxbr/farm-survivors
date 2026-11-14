---
name: reverse-document
description: "Escreve o documento de design ou de arquitetura que falta para um sistema do Ecos de Valdoria, lendo o código que já existe (missões, combate, progressão, itens e loot, horta e cozinha, Desafio da Horda, Defesa da Cidade, praça e progressão permanente, multiplayer, auto update). Separa o que o código faz do que foi a intenção, e pergunta ao usuário a intenção em vez de inventar. Use quando pedirem para documentar um sistema, explicar como algo funciona por escrito, ou antes de mexer fundo num sistema sem documentação."
argument-hint: "<design|arquitetura> <sistema ou caminho> (ex.: 'design horda', 'arquitetura scripts/autoload/network.gd')"
license: MIT
metadata:
  adapted-from: https://github.com/Donchitos/Claude-Code-Game-Studios (.claude/skills/reverse-document)
  version: "1.0.0"
---

# Reverse Document (Ecos de Valdoria)

O jogo cresceu feature a feature sem documento de design; o `README.md` só lista
controles e conteúdo. Esta skill escreve, em `docs/design/` e `docs/arquitetura/`,
o que cada sistema **faz**, e registra a **intenção** só quando o usuário confirmar.

## Fase 1: Argumentos

- Tipo: `design` (regras, valores, fórmulas, fluxo do jogador) ou `arquitetura`
  (como o código está organizado e por quê: autoloads, rede, saves).
- Alvo: nome de sistema ou caminho. Mapa dos sistemas:

| Sistema | Arquivos principais |
|---|---|
| `missoes` (vila, Bram, Mira, cadeia até o Rei Goblin) | `scripts/world/npc.gd`, `QUESTS` em `scripts/autoload/item_db.gd`, `scripts/ui/dialogue_ui.gd`, `scripts/world/world.gd` |
| `combate` (espada, cajado, arco, esquiva, magias) | `scripts/player/player.gd`, `projectile.gd`, `fireball.gd`, `SPELLS` em `item_db.gd` |
| `inimigos` (IA, chefe, loot) | `scripts/enemies/enemy.gd`, `enemy_arrow.gd` |
| `progressao` (XP, níveis, atributos) | `scripts/autoload/game.gd` |
| `itens` (raridades, equipamento, loja) | `scripts/autoload/item_db.gd`, `scripts/ui/shop_ui.gd`, `item_slot.gd`, `item_tooltip.gd` |
| `comida` (horta, caldeirão, buffs) | `scripts/farm/`, `CROPS`/`RECIPES` em `item_db.gd`, `cooking_ui.gd`, `plant_ui.gd` |
| `horda` (Desafio da Horda, solo e em grupo) | `scripts/survival/`, `scripts/world/challenge_portal.gd`, `survival_hud.gd`, `horde_scoreboard.gd` |
| `cidade` (Defesa da Cidade) | `scripts/colony/`, `colony_hud.gd`, `colony_ui.gd` |
| `praca` (praça da cidade, pontos, emotes, Ecos, passivas, base compartilhada, recordes) | `scripts/autoload/hub.gd`, `scripts/hub/hub_world.gd`, `hub_point.gd`, `scripts/player/knight_emotes.gd`, `scripts/ui/hub_hud.gd`, `passive_master_ui.gd`, `base_building_ui.gd`, `records_ui.gd`, `war_table_ui.gd`, `horde_portal_ui.gd`, `scripts/character/reward_rules.gd`, `base_rules.gd`, `data/balance/rewards.json`, `meta_passives.json`, `base_buildings.json` |
| `multiplayer` (servidor, zonas praça/Valdoria/cidade, chat, sincronia) | `scripts/autoload/network.gd`, `lobby.gd`, `hub.gd`, `chat_ui.gd` |
| `saves` | `scripts/autoload/game.gd` (save/load, autosave) |
| `auto-update` | `scripts/autoload/updater.gd`, `update_panel.gd`, `.github/workflows/deploy.yml` |

Sem alvo, mostre esse mapa e pergunte qual.

## Fase 2: Ler o código

Leia os arquivos do sistema inteiros (não só os nomes de funções) e os testes que o
exercitam (`tests/smoke_test.gd`, `colony_test.gd`, `hub_test.gd`, `net_test.gd`): os testes mostram
o comportamento esperado de forma explícita.

**Design:** mecânicas com regras observáveis; fórmulas (ex.: `xp_to_next()` =
`int(60 * level^1.55)`); valores de ajuste com onde são usados; estados (ex.: `STATES`
dos inimigos em `network.gd`); casos de borda tratados; ligação com outros sistemas.

**Arquitetura:** papel de cada autoload; quem é autoridade (servidor ou cliente) em
cada coisa; o que vai por RPC e o que vai em snapshot; formato e caminho dos saves;
flags de linha de comando (`--server`, `--smoketest`, `--nettest` etc.); restrições
(ex.: cliente e servidor precisam da mesma versão).

## Fase 3: Há o suficiente?

Conte mecânicas, fórmulas e valores com uso encontrados. Se for quase nada (stub,
sistema só começado), pare e diga: documentar intenção a partir de comportamento
inexistente seria invenção com formato de documento.

## Fase 4: Mostrar achados e perguntar a intenção

Antes de redigir, mostre:

```
Analisei [sistema]. Encontrei:

MECÂNICAS: [lista, com arquivo:linha]
FÓRMULAS: [lista]   (ou "nenhuma encontrada no código")
VALORES: [lista dos principais]
DÚVIDAS DE INTENÇÃO:
1. [ex.: a horda escala por rodada com expoente 1,4; é proposital ou precisa de ajuste?]
2. [ex.: o roubo de vida não tem limite; é intencional?]
```

Pergunte as dúvidas ao usuário. Seção vazia diz "nenhuma encontrada no código",
nunca é preenchida com o que sistemas parecidos costumam ter.

Dúvida que o usuário não responder vai para o documento como
`INTENÇÃO NÃO CONFIRMADA — deduzida do código`.

## Fase 5: Redigir

Logo abaixo do título, sempre:

```markdown
> **Documentado a partir do código** em [data], commit `[hash curto]`, lendo [arquivos].
> Descreve o que o código **faz**. Trechos marcados INTENÇÃO NÃO CONFIRMADA foram
> deduzidos, não confirmados pelo autor. Se este documento e o código divergirem,
> não assuma que o documento é o requisito.
```

**Design** (`docs/design/<sistema>.md`):
1. Visão geral (2 ou 3 frases, como o jogador vive o sistema)
2. Regras detalhadas
3. Fórmulas e valores (tabela: nome, valor, arquivo:linha, efeito)
4. Casos de borda (tratados e não tratados)
5. Ligações com outros sistemas
6. Intenção (confirmada / não confirmada)
7. Lacunas e trabalho sugerido

**Arquitetura** (`docs/arquitetura/<tema>.md`):
1. Contexto
2. Como funciona (componentes, fluxo de dados, quem é autoridade)
3. Decisões e alternativas (com o motivo confirmado ou marcado como não confirmado)
4. Consequências e restrições
5. Riscos conhecidos

Escreva em português, com termos do jogo como o jogador os vê (Desafio da Horda,
Defesa da Cidade, Rei Goblin).

## Fase 6: Gravar e próximos passos

Mostre o rascunho e pergunte antes de criar o arquivo. Depois de gravado, sugira o que
o documento revelou: rodar a skill `balance-check` nas fórmulas suspeitas, casos de
borda sem tratamento para virar teste em `tests/`, decisões de arquitetura que mereçam
revisão. Mantenha o aviso do topo em revisões futuras; só o usuário o remove, quando
adotar o documento como design oficial.
