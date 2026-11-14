---
name: patch-notes
description: "Escreve as notas de atualização do Ecos de Valdoria para jogadores, em português, a partir do histórico git entre duas versões (tags v0.x.y) e dos PRs. Filtra commits de ferramenta (CI, testes, skills, deploy) e traduz linguagem de código para o que o jogador sente. Use quando pedirem notas da versão, novidades, changelog para jogadores ou texto da release."
argument-hint: "[versão, ex.: 0.7.1] [--estilo curto|detalhado]"
license: MIT
metadata:
  adapted-from: https://github.com/Donchitos/Claude-Code-Game-Studios (.claude/skills/patch-notes)
  version: "1.0.0"
---

# Patch Notes (Ecos de Valdoria)

## Como as versões funcionam aqui

- A versão está em `config/version` no `project.godot`.
- Cada versão publicada tem uma tag `vX.Y.Z` e uma release no GitHub criada pelo CI
  (`.github/workflows/deploy.yml`), com um texto genérico. O auto update do jogo baixa
  dessa release.
- Os commits e PRs já são escritos em português, frase descritiva no presente
  ("Salva o personagem a cada 2 minutos no multiplayer (0.6.1)"). Merges trazem
  "Mescla main ... e sobe a versão para X".

## Fase 1: Intervalo

- Versão pelo argumento; sem argumento, use `config/version` do `project.godot`.
- Início: a tag anterior (`git tag --sort=-v:refname`). Fim: a tag da versão, ou `HEAD`
  se ela ainda não foi publicada (diga isso no texto: "prévia, versão ainda não lançada").
- Estilo padrão: `detalhado`.

```bash
git log vANTERIOR..vVERSAO --no-merges --format='%h %s%n%b'
gh pr list --state merged --search "merged:>=DATA_DA_TAG_ANTERIOR" --json number,title,body --limit 50
```

Se o intervalo não tiver commits, pare e diga isso. Não invente novidades.

## Fase 2: Filtrar commit por commit

Classifique **cada** commit em um destes:

- **Jogo**: muda o que o jogador vê ou joga: mecânicas, conteúdo, balanceamento,
  modelos, sons, interface, rede percebida (lag, desconexão), save, auto update visto
  pelo jogador, correção de bug em qualquer um desses.
- **Ferramenta**: `.github/`, `tests/`, `.claude/` (skills), `tools/` (scripts do
  Blender), `Dockerfile`, deploy no Easypanel, docs internas, "Mescla main e sobe a
  versão". **Fica fora das notas.**
- **Incerto**: trate como ferramenta.

Use os arquivos tocados para decidir (`git show --stat <hash>`), não só o título.
Informe no fim quantos commits entraram ("12 de 19 commits viraram notas").
Se nenhum commit for de jogo, diga que esta versão só tem mudanças internas e pare.

## Fase 3: Categorizar e traduzir

Categorias (omita as vazias):

- **Novidades**: modos, regiões, inimigos, itens, magias, missões, NPCs
- **Mudanças de jogo**: balanceamento, dificuldade, progressão, economia
- **Qualidade de vida**: HUD, menus, controles, atalhos, acessibilidade
- **Praça e progressão permanente**: praça da cidade, Ecos, passivas do Mestre Orin, base compartilhada (Forja, Muralha, Celeiro), recordes, emotes
- **Multiplayer**: praça online, grupo, Horda e Defesa da Cidade em grupo, chat
- **Correções**: agrupadas por sistema
- **Desempenho**
- **Problemas conhecidos**: só se o usuário informar ou houver issue aberta

Traduza para o jogador, sem nome de arquivo, função ou classe:

- "Corrige teste instável do kit inicial" → é ferramenta, fica fora
- "Som posicional: combate longe do jogador não é mais ouvido" → "O som das lutas
  agora diminui com a distância: brigas longe de você não se ouvem mais."
- "Protege a troca de versão entre cliente e servidor" → o corpo do commit mostra
  duas partes: a do CI é ferramenta; a que o jogador vê vira "Se o servidor ainda
  está sendo atualizado, o jogo avisa isso em vez de pedir para você atualizar."
  Leia o corpo do commit, não só o título.

Números de balanceamento entram quando o jogador sente a diferença ("hordas da rodada
10 em diante têm mais inimigos"); leia o diff para pegar o valor real. Não exagere:
"melhorado" só se for melhora de fato; nada de "épico", "revolucionário".

Nomes do jogo como aparecem para o jogador: Desafio da Horda, Defesa da Cidade,
Rei Goblin, Ancião Bram, Mira, Valdoria. Teclas como no README (Tab, E, I, F5...).

## Fase 4: Texto

**Curto:** título `## Ecos de Valdoria vX.Y.Z` e uma lista de 3 a 8 itens.

**Detalhado:**

```
## Ecos de Valdoria vX.Y.Z

[1 ou 2 frases com o destaque da versão]

### Novidades
- ...

### Mudanças de jogo
- ...

### Correções
- ...

Quem já tem o jogo recebe esta versão pelo auto update ao abrir o menu.
```

Mostre o texto no chat e informe quantos commits entraram e quais ficaram de fora.

## Fase 5: Publicar (só com permissão)

Ofereça, e só faça com um "sim" explícito do usuário:

- Salvar em `docs/notas/vX.Y.Z.md`.
- Trocar o texto da release no GitHub (é público e visível para os jogadores):
  `gh release edit vX.Y.Z --notes-file docs/notas/vX.Y.Z.md`.

Lembre que o CI recria a release quando uma execução é cancelada no meio
(`gh release delete` + `create`) e, nesse caso, o texto volta ao genérico. Se o usuário
quiser notas sempre, a mudança certa é o workflow ler `docs/notas/v$ver.md` quando
existir; proponha isso em vez de editar à mão a cada versão.
