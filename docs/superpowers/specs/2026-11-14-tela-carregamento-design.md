# Tela de carregamento — design

Data: 2026-11-14 · Branch: `tela-carregamento` (worktree `../godot-3d-loading`)

## Intenção

Hoje as trocas de cena são diretas: a tela congela na cena antiga, o mundo novo aparece de uma vez e
o personagem, que volta à última posição salva, já pode estar apanhando antes de o jogador enxergar
ou controlar qualquer coisa. Online, os inimigos ainda chegam do servidor depois que a cena abre.

A tela de carregamento cobre a troca e só abre quando o mundo está pronto. Enquanto ela cobre, o
personagem não se mexe nem sofre dano.

## Objetivos

- Tela cheia escura com o título do jogo, o destino ("Viajando para Valdoria…"), uma dica e uma
  animação de carregamento.
- Vale para todas as trocas de cena do cliente: menu, praça, Valdoria, Defesa da Cidade, F9.
- A tela abre quando: a cena nova está montada, alguns quadros já foram desenhados (os primeiros
  travam compilando shaders) e, em Valdoria online, o primeiro snapshot de inimigos chegou
  (ou 1,5 s sem nenhum, caso não haja inimigo por perto).
- Proteção: coberto, o jogador fica sem controle e imune; ao abrir, mais 2 s de imunidade.

## Fora do escopo

- Barra com porcentagem real (exigiria montar o mundo em etapas por vários quadros).
- Servidor dedicado (não tem tela) e a entrada na Horda dentro de Valdoria (não troca de cena).

## Abordagens

1. **Autoload `Loading` com `Loading.go(cena)`** no lugar de `change_scene_to_file` — escolhida.
   Um ponto só controla cobertura, espera e proteção; as cenas não mudam.
2. Carregamento em segundo plano (`ResourceLoader.load_threaded_request`) — não ajuda: os `.tscn`
   são quase vazios, o custo está no `_ready` que monta o mapa por código.
3. Montar o mundo em etapas com `await` entre elas — dá barra real, mas muda a base de Valdoria e os
   testes que contam com o mundo pronto ao carregar a cena.

## Como

- `scripts/autoload/loading.gd` (CanvasLayer, camada 100, processa mesmo em pausa).
- `go(path)`: escurece (0,15 s), troca a cena, espera as condições acima (mínimo 0,7 s, teto 10 s),
  dá a imunidade e clareia (0,4 s). Um `go` novo durante outro substitui o anterior.
- Em modo headless (testes e servidor) a troca é direta, sem tela; `Loading.force` liga a tela num teste.
- `player.gd`: sem controle enquanto `Loading.covering`.
