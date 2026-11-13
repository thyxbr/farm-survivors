# Ecos de Valdoria — protótipo de RPG de ação 3D (Godot 4.7)

Abra a pasta no Godot 4.7 e aperte **F5**, ou rode:

```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path C:/Games/godot-3d
```

## Controles
| Ação | Tecla |
|---|---|
| Mover / correr / pular | WASD · Shift · Espaço |
| Câmera | Mouse |
| Atacar (combo de 3 golpes) | Clique esquerdo |
| Esquivar (invulnerável) | Clique direito ou Ctrl |
| Magias | 1 Bola de Fogo · 2 Cura (nível 2) · 3 Nova Gélida (nível 4) |
| Poções | R vida · F mana |
| Interagir / falar | E |
| Inventário · Personagem · Missões | I (ou Tab) · C · J |
| Salvar / carregar rápido | F5 / F9 |
| Pausa | Esc |
| Esconder ajuda | H |

## Conteúdo
- **Vila** com o Ancião Bram (missões) e a Mira (loja: compra e venda).
- **3 missões em cadeia**: slimes nos campos → batedores goblins na floresta a leste → **Rei Goblin** nas ruínas ao norte (chefe com ataque em área, fúria e invocação).
- **Progressão**: XP, níveis, 3 pontos de atributo por nível (Força, Inteligência, Vitalidade, Agilidade), magias liberadas por nível.
- **Itens**: armas e armaduras (mudam o visual do cavaleiro), poções, materiais para vender, loot aleatório.
- **Save/Load** em JSON (`user://savegame.json`), opções persistentes (volume, sensibilidade, inverter Y, tela cheia).
- Morte com opção de renascer na vila (perde 10% do ouro) ou carregar o save.

## Desafio da Horda (modo sobrevivência)
Entre no **Portal do Desafio** (perto do portão norte da vila, tecla E) para ir à **Arena** a oeste do mapa:
- Hordas de slimes e goblins surgem sem parar, cada rodada (45 s) mais fortes e numerosas; a cada 5 rodadas vem o **Rei Goblin**.
- Armas automáticas atacam sozinhas (**Orbe de Fogo**, **Lâminas Orbitais**, **Relâmpago**, **Aura Gélida**); espada, esquiva, magias e poções continuam valendo.
- Inimigos soltam **gemas de XP**: ao subir o nível da partida você escolhe 1 de 3 cartas (arma nova, melhoria ou passiva) — teclas 1/2/3 ou clique.
- Ao fim de cada rodada a arena é limpa, você recupera 30% da vida e escolhe uma **bênção**, ou se retira com as recompensas.
- Ao sair (retirada, morte ou "Abandonar desafio" na pausa) você volta à vila sem perder ouro e ganha XP do RPG (abates×2 + rodadas×25). O recorde fica salvo.
- Os bônus da partida são temporários; não é possível salvar durante o desafio.

Para editar as melhorias veja `scripts/survival/upgrades.gd`; o ritmo das rodadas fica em `scripts/survival/survival_mode.gd`.

## Estrutura
```
assets/models/        GLBs low-poly gerados pelo Blender
tools/blender/        build_assets.py (cenário + chama characters.py), characters.py (personagens detalhados),
                      preview_assets.py / preview_characters.py / preview_closeup.py (renders de conferência)
scripts/autoload/     game.gd (estado, save/load), item_db.gd (itens/magias/missões), sfx.gd (sons sintetizados)
scripts/player/       player.gd (controle, combate, magias), fireball.gd
scripts/enemies/      enemy.gd (slime, goblin, rei goblin — IA e animação procedural)
scripts/world/        world.gd (monta o mapa e gerencia UI modal), npc.gd, pickup.gd, challenge_portal.gd
scripts/survival/     survival_mode.gd (rodadas, spawn, XP), auto_weapons.gd, xp_gem.gd, upgrades.gd
scripts/ui/           hud, diálogo, inventário/personagem/missões, loja, pausa/morte, opções, menu principal
tests/smoke_test.gd   teste automatizado do gameplay
```
O mapa, a UI e as animações são montados por código; para mudar dados de itens, missões e
inimigos edite `item_db.gd` e a tabela `TYPES` em `enemy.gd`.

## Regerar os modelos
```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py
```
Para gerar só alguns modelos: defina `ASSETS=knight,elder` no ambiente antes do comando.
(Rodar via CLI em segundo plano: exportar de uma cena que não é a ativa faz o Blender 5.2 travar.)

## Teste automatizado
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/world.tscn -- --smoketest
```
Cobre diálogo/missões, combate, loot, magias, loja, equipamento, save/load, chefe, IA, morte e o Desafio da Horda.
Para começar direto na arena: `... res://scenes/world.tscn -- --survival`.
Para tirar um screenshot da arena: `... -- --survival --shot=shot.png --delay=15` (o PNG vai para a pasta atual;
evite a raiz `C:/`, que o Windows não deixa gravar sem administrador).
Usa um arquivo de save separado, então não mexe no seu save.
