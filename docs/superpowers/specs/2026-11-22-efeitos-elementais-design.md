# Efeitos elementais de status — design

Data: 2026-11-22 · Branch: `efeitos-elementais`

## Intenção

Elemento hoje só muda o número de dano. A ideia é que ele *aconteça* no alvo: um golpe de fogo pode deixar o
monstro em chamas, e um monstro de veneno pode envenenar o jogador. Enquanto o efeito dura, o alvo mostra o
elemento no corpo (chamas subindo, gelo, bolhas verdes). A resistência do alvo decide se o efeito pega.
Vale para os dois lados: arma encantada → monstro, e monstro elemental → jogador.

## Objetivos

- Toda fonte com elemento (arma encantada, monstro temático) tem **chance** de aplicar o efeito do elemento.
- A resistência do alvo reduz essa chance; com 100% ou mais, o efeito nunca pega e aparece "Resistiu".
- O alvo afetado mostra o efeito no corpo (contorno de luz + partículas do elemento), visível para todos
  os jogadores do mundo.
- O jogador ganha resistências elementais vindas de **equipamento, poções e comida**.
- O raio é instantâneo: salta em cadeia.

## Fora do escopo

- Magias e habilidades aplicando status (Bola de Fogo, Nova Gélida...). Ficam só com o elemento no dano,
  como hoje. Pode vir depois usando o mesmo componente.
- Armas automáticas da Horda.
- Efeitos entre jogadores (não há PvP).
- Variante anã (`_d`) de qualquer peça nova.

## Anti-objetivos (falhou mesmo funcionando)

- Um jogador ver o monstro em chamas e o outro não.
- Ticks de dano chegando duplicados ao servidor (um por cliente).
- Tela poluída: partículas demais em horda grande, ou efeito que esconde o modelo.
- Efeito em monstro imune (imune a fogo pegando fogo).

## Regras

### Chance e resistência (opção escolhida: a resistência corta a chance)

```
chance_final = chance_base × (1 − resistência)
```

- `resistência` é uma fração: 0.25 = 25%. Com `resistência ≥ 1.0` a chance é 0 e o número de dano mostra
  "Resistiu" no lugar do efeito.
- **Monstro:** resistência = `1 − element_pct / 100` do Bestiário (`BestiaryRules.element_pct`), cortada em
  [0, 1]. Afinidade 75 → 25% de resistência; 125 (fraco) → 0 (a fraqueza não aumenta a chance além da base);
  0 (imune) → 100%.
- **Jogador:** resistência = soma de `Game.mod("res_<elemento>")` (equipamento, buff de poção, buff de
  comida, talentos se algum dia houver), cortada em [0, 1].
- A mesma resistência do jogador também reduz o dano daquele elemento (`dano × (1 − resistência)`), como o %
  do Bestiário já faz nos monstros.

### Efeitos

| Elemento | Efeito | Cor | Notas |
|---|---|---|---|
| Fogo | Queimadura: dano em 3 ticks por ~3 s | laranja | igual ao de hoje, agora com chance |
| Gelo | Lentidão; 3 aplicações dentro da duração congelam ~1 s | azul-claro | congelado não anda nem ataca |
| Veneno | Dano em ticks por ~5 s, mais fraco por tick que o fogo | verde | **substitui** a marca tóxica (amplificação de dano sai) |
| Raio | Instantâneo: salta para até N alvos próximos (1 a 3 conforme o nível) | amarelo | no jogador: choque curto que interrompe o ataque em curso; faíscas ~0.5 s no corpo |
| Sombra | Roubo de vida para quem bateu + cura reduzida no alvo | roxo | cura reduzida só importa no jogador (monstro não se cura) |
| Sagrado | Dano extra em chefes/elites (como hoje) + "marcado": o próximo golpe recebido é crítico | dourado | a marca some ao ser consumida |

- **Acúmulo:** o mesmo efeito não empilha; aplicar de novo renova a duração (e fica o valor mais forte).
  Efeitos de elementos diferentes coexistem.
- Um efeito nunca dispara outro (o tick da queimadura não rola chance de nada), como hoje.
- Os números (chance por nível, dano, duração, alvos do raio, cura reduzida) ficam em
  `data/balance/enchant.json` ("effects") para a arma e num bloco novo para os ataques dos monstros.

### Monstros com ataque elemental

Campo novo em `data/balance/enemies.json`, por exemplo `"attack_el": {"el": "fogo", "chance": 0.25}`.
Só os temáticos recebem na primeira entrega: Slime Explosivo (fogo), Slime Veloz (gelo), Goblin Xamã (raio),
Slime Mãe (veneno). O `chill` atual continua existindo (é outra mecânica: lentidão garantida de certos
golpes); `chill_venom` passa a aplicar o veneno novo.

### Resistências do jogador

- **Equipamento:** chave `res_<elemento>` no bloco `stats` do item (`"stats": {"res_fogo": 0.10}`). Entram
  pelos mesmos caminhos dos outros stats.
- **Comida e poção:** chave `res_<elemento>` no `add` do buff em `data/balance/buffs.json`. Uma poção de
  resistência é um consumível que aplica um buff, igual às comidas.
- Primeira entrega: algumas peças/comidas/poções de exemplo para dar para testar (ex.: Poção de Resistência ao
  Fogo, uma comida "quente" com res_gelo). Distribuição completa em itens é trabalho de balanceamento depois.
- Tooltip do item e painel de atributos mostram as resistências.

## Abordagem

Consideradas:

1. **O cliente pede, o servidor decide — escolhida.** Mesmo caminho da marca tóxica de hoje
   (`Enemy.apply_venom` → `Network.client_mark_enemy` → `_mark_enemy` com `HitGuard` e valores limitados).
   Quem bate rola a chance e pede o status; o servidor confere alcance, zona, resistência e limites da
   tabela, guarda o estado, roda os ticks e replica quais efeitos estão ativos. Todos veem o mesmo; ticks
   saem de um lugar só.
2. **Tudo no cliente, como os efeitos de hoje.** Rápido, mas os outros não veem o efeito e os ticks viram
   acertos pela rede de cada cliente. Viola dois anti-objetivos.
3. **Tudo no servidor, inclusive a rolagem.** Mais seguro contra trapaça, mas o combate inteiro é do cliente;
   mudaria muito mais coisa do que o recurso pede.

### Como fica

- **`StatusRules`** (script puro, sem autoload, testável no runner `-s`): chance final, resistência a partir do
  Bestiário, regra de acúmulo/renovação, contagem do congelamento, valores por nível. Nada de `Game` dentro
  (ver regra do runner de unitários).
- **`StatusEffects`** (componente, nó filho do `Enemy` e do `Player`): guarda os efeitos ativos
  `{el: {timer, valor, ...}}`, roda os ticks no dono (servidor ou solo), expõe um bitmask de efeitos ativos.
  Substitui `venom_amp/venom_timer` e a `enchant_burn` em meta.
- **Monstros:** o bitmask entra nos `flags` do snapshot de inimigo (`Network`, linha que monta
  `flags` com `slow_timer`/`enraged`); `Enemy.apply_snapshot` repassa para o componente da réplica, que só
  desenha.
- **Jogador:** o servidor avisa o jogador atingido (como `server_chill_player` → `_you_were_chilled`); o
  jogador aplica no próprio componente, roda os ticks localmente (é dono da própria vida, como já é hoje com
  dano recebido) e põe o bitmask nos `flags` do `send_player_state`, para os outros verem o efeito no avatar.
- **RPC novo** genérico `client_apply_status(net_id, el, valor, secs)` no lugar de `client_mark_enemy`, com a
  mesma conferência, e valores cortados ao máximo da tabela para aquele elemento.
- **`EnchantHit.on_hit`** passa a: rolar chance com `StatusRules`, pedir o status (ou aplicar direto no solo),
  e manter o raio/sombra/sagrado instantâneos onde já estão.
- **Visual: `StatusAura`**, na mesma base do `BuffAura` (contorno de luz no corpo + poucas partículas pequenas
  do elemento). Estilo desenhado do jogo: chamas e gelo em puffs arredondados, sem espinhos. Um efeito por
  vez ganha partículas (o mais recente); os outros ativos só tingem o contorno. Limite de auras com partícula
  ao mesmo tempo para hordas grandes (os que passarem disso ficam só com o contorno).
- **Número de dano:** "Resistiu" quando a resistência ≥ 100% barrou um efeito que teria rolado.

### Decisões tomadas na revisão (escolhas do Claude, conferir)

- **Crédito dos ticks:** `StatusEffects` guarda o peer que aplicou o efeito; os ticks rodados no servidor
  contam como acerto desse peer (`last_hitter`), inclusive a morte, XP e loot. Se ele saiu do mundo, o tick
  ainda dá dano, mas a morte vai para o último que bateu de verdade.
- **Rede:** os bits de efeito ganham um campo próprio no snapshot de inimigo (`SNAP_STRIDE` +1) em vez de
  disputar os bits altos de `flags`, que já estão ocupados. Cliente e servidor atualizam juntos (auto update
  obrigatório); não há compatibilidade com cliente antigo.
- **Sagrado "marcado":** o estado fica no servidor. O próximo golpe que o servidor aceitar naquele alvo, de
  qualquer jogador, leva o multiplicador de crítico ali mesmo e a marca some. O cliente não decide.
- **Sombra e sagrado com chance:** o roubo de vida e o dano extra em chefes continuam em todo golpe (são
  bônus de quem bate, não status no alvo), mas zeram em alvo imune ao elemento. A cura reduzida (sombra) e a
  marca (sagrado) são status: passam pela chance e pela resistência.
- **Congelamento (decidido pelo usuário):** chefes e elites nunca congelam, só ficam lentos. Depois de
  congelar, o alvo fica ~5 s imune a novo congelamento. O jogador nunca congela: gelo nele é só lentidão
  (somada ao `chill` existente, ficando a mais longa).
- **Dano elemental no jogador (decidido pelo usuário):** só os golpes de monstros com `attack_el` levam
  elemento e respeitam `res_<elemento>`. Ataques já existentes que parecem elementais (sopro gelado do Ieti e
  da Sentinela, dinamite do kobold, magias de chefe) continuam sem elemento nesta entrega.
- **`chill_venom`:** continua dando a lentidão garantida e passa a rolar a chance do veneno novo junto.

## Entregas sugeridas (um PR cada)

1. `StatusRules` + `StatusEffects` no monstro + rede + visual, só com a arma encantada (fogo, gelo, veneno
   novo). Raio, sombra e sagrado continuam como hoje.
2. Raio em cadeia de 1–3 alvos, sagrado "marcado", sombra com cura reduzida.
3. Resistências do jogador (stats, buffs, tooltip, painel) + poções/comidas de exemplo.
4. Ataques elementais dos monstros temáticos aplicando status no jogador, com a aura no avatar.

## Deixado para quem for construir

- Números exatos (chance por nível do encanto, dano por tick do veneno, duração do congelamento, alcance do
  salto). Começar pelo que `enchant.json` já tem e passar pelo `balance-check`.
- Forma exata das partículas de cada elemento, conferidas na câmera do jogo (não só no vfx_lab).
- Teto de auras com partícula em horda (medir com `perf-profile` se houver dúvida).
