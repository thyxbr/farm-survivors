# Classes e criação de personagem — Parte 1 (design)

Data: 2026-11-15 · Status: rascunho para aprovação

## Contexto e intenção

O usuário quer que a classe seja a **identidade fixa do personagem**: cada classe com a sua arma, as
suas habilidades e (mais tarde) a sua árvore de passivas. Hoje não existe classe: as habilidades
seguem a arma equipada (`ItemDB.kit(weapon_class())`), e o kit inicial dá espada, cajado e arco para
"experimentar". Não há tela de criação: há um personagem solo por PC e um online por conta.

O pedido completo foi dividido em quatro partes, nesta ordem:

1. **Classes e tela de criação** (este documento).
2. Buffs de comida viram habilidades de classe; a comida passa a curar + um bônus pequeno e genérico
   (opção B: XP, ouro, ímã — nada de combate).
3. Árvore de passivas por classe (pontos por nível; reaproveita o padrão de `meta_passives`).
4. Modelo feminino (corpo novo no Blender + ajuste do equipamento).

## Metas

- Quatro classes: **Guerreiro** (espada), **Arqueiro** (arco), **Mago** (cajado), **Healer** (cetro, arma nova).
- A classe é escolhida uma vez, na criação, e não muda. Ela decide qual arma pode ser equipada e qual
  kit de habilidades aparece na barra.
- Tela de criação: escolher classe e sexo (masculino/feminino), com prévia 3D.
- Personagens já existentes escolhem classe e sexo na primeira entrada depois da atualização.
- Online, a regra vale no servidor (`CharRules`), não só na interface.

## Não-metas (desta parte)

- Converter os buffs de comida em habilidades (parte 2). A comida continua como está até lá.
- Árvore de passivas (parte 3).
- Corpo feminino (parte 4). Nesta parte o sexo é gravado e escolhido, mas o modelo continua o atual.
- Trocar de classe depois de criado (não haverá "respec" de classe).
- Nome de personagem (online continua o nome da conta).

## Anti-metas (falharia mesmo funcionando)

- Personagem antigo perder itens ou ficar sem arma equipável.
- Dar para equipar arma de outra classe online mandando o pedido direto (burlar a interface).
- Mago e healer disputando os mesmos drops.

## Abordagens consideradas

- **Classe gravada no personagem e validada em `CharRules`** (escolhida). Uma regra única, roda igual
  no solo e no servidor; o equipamento, o kit e a loja derivam dela.
- Classe só no cliente (a interface esconde armas de outras classes). Descartada: online daria para burlar.
- Arma do healer: **linha nova de cetros** (escolhida pelo usuário) vs. healer usar os 13 cajados do
  mago. Os cajados compartilhados foram descartados porque mago e healer disputariam os drops e o healer
  pareceria um "mago com outra barra".

## Design

### Dados

- `CharState` ganha `char_class: String` (`"" | "warrior" | "archer" | "mage" | "healer"`) e
  `body: String` (`"" | "m" | "f"`). `to_dict`/`from_dict` gravam e leem; valor desconhecido vira `""`.
  `""` significa "ainda não escolheu".
- Tabela de classes (`data/balance/classes.json`, carregada pelo `Balance`): por classe, `name`,
  `weapon_class` (`sword|bow|staff|scepter`), `starter_weapon`, `desc`, cor/ícone.
- `CharRules.CLASS_NAMES` ganha `"scepter": "Cetro"`.
- Itens `type: weapon` com `class: "scepter"` em `items.json`: **5 cetros** (um por raridade, como os
  arcos), com números na escala dos cajados. *Decisão minha.* Ataque básico escala com **INT**
  (como o cajado); a cura também. *Decisão minha.*
- Sem mão secundária para cetro nesta parte. *Decisão minha.*

### Regras (`CharRules`, valem no solo e no servidor)

- Nova operação `choose_class(class, body)`: só funciona com `char_class == ""`; valida os dois
  valores; grava; aplica a migração do equipamento (abaixo). Fica disponível no `Econ.request` e no
  `CharacterService._dispatch`/`_args_ok`.
- `equip`: arma cuja `class` não é a `weapon_class` da classe do personagem → `_fail("exige_classe")`
  com aviso "X é arma de <classe>.". Com `char_class == ""` nada pode ser equipado (o fluxo de criação
  impede chegar ao mundo assim).
- Migração ao escolher (personagem antigo): se a arma equipada já for da classe, fica. Senão ela volta
  para a mochila e é equipada a melhor arma da classe que já está na mochila (maior raridade, depois
  maior dano); sem nenhuma, a `starter_weapon` é criada e equipada. *Decisão minha.* Mão
  secundária incompatível volta para a mochila. Nada é apagado; armas de outras classes ficam na
  mochila e podem ser vendidas.
- `new_character`: sem arma e sem o kit "experimente as três classes"; a arma inicial é dada no
  `choose_class`. Poções, sementes e pão continuam.

### Kit de habilidades

- `Game.ability_kit()` passa a usar a classe do personagem (`classes[char_class].weapon_class`), não a
  arma equipada. Na prática dá o mesmo resultado, já que a arma sempre é da classe.
- `ItemDB.ABILITIES`: `heal` sai do cajado e vai para `class: "scepter"`, slot 1, nível 1. Os slots 2 e
  4 do healer entram como `ready: false` ("Em breve") e serão preenchidos na parte 2. O mago fica com
  Bola de Fogo, Nova Gélida e Chuva de Meteoros (slot 3 vazio, como as outras classes).
- **Cura do healer atinge a si mesmo e qualquer aliado perto** (decisão do usuário): todo jogador a até
  8 m, esteja ou não no mesmo grupo formado, em Valdoria e no Desafio da Horda (que tem vida própria
  em `survival_mode.gd` e precisa do mesmo caminho). Como vida e mana são do cliente, a cura dos aliados
  chega como evento de rede para o cliente de cada aliado, que aplica a cura em si. O servidor confere a
  distância e limita o valor (teto por evento, por remetente, por janela de tempo), como já faz com
  outros eventos.
- Ataque básico do cetro: esfera de luz de curto alcance (projétil com o mesmo caminho do
  `_staff_shot`, outra cor e efeito). Novo módulo `scepter_abilities.gd` segue o padrão de
  `sword/bow/staff_abilities.gd`.

### Loja e loot

- A loja continua mostrando todas as armas (decisão do usuário). As de outra classe aparecem marcadas
  ("arma de Mago") e podem ser compradas, mas não equipadas.
- Drops de arma comuns (sorteio por raridade): a arma sorteada é trocada por uma arma aleatória da
  classe do personagem, da mesma raridade (função em `LootRules`, roda no solo e no servidor). O
  servidor conhece a classe. *Decisão minha, para evitar que cada drop de arma vire lixo para 3 de 4 classes.*
- Drops com nome (assinatura de chefe) e recompensas de missão com arma fixa (`archmage_staff`,
  `elven_bow`, `guardian_greatsword`...) **não** são trocados: ficam como troféu vendável. *Decisão minha.*
- **O balanceamento dos drops fica para depois** (pedido do usuário): esta parte entrega a troca
  simples acima. Contagem de armas por raridade e por classe, chance de drop e preço de venda das armas de
  outras classes serão revistos num passo próprio de balanceamento, depois da parte 1.

### Bloqueio sem classe

- Personagem com `char_class == ""` não entra em nenhum modo (Valdoria, Desafio da Horda, qualquer
  rota): o `CharacterService` recusa entrar/começar partida e só aceita `choose_class`; o cliente abre a
  tela de criação. *Decisão minha: o bloqueio fica no servidor para cobrir todas as rotas.*

### Tela de criação

- Nova tela (`scripts/ui/char_create.gd`), aberta:
  - no solo, por "Novo jogo" e por "Continuar" quando o personagem salvo tem `char_class == ""`;
  - online, depois do login, quando o personagem que veio do servidor tem `char_class == ""`, antes de
    entrar no mundo.
- Esboço:

```
 ┌───────────────────────────────────────────────┐
 │  Crie seu herói                               │
 │  Sexo:  [ Masculino ] [ Feminino ]            │
 │                                               │
 │  [Guerreiro] [Arqueiro] [Mago] [Healer]       │
 │   ┌──────────┐   Guerreiro                    │
 │   │ prévia3D │   Espada · força · combo       │
 │   │ com arma │   Investida, Golpe Sísmico,    │
 │   └──────────┘   Turbilhão                    │
 │                         [Voltar] [Começar]    │
 └───────────────────────────────────────────────┘
```

- Prévia: `CharPreview` com a arma inicial da classe. Feminino mostra o mesmo corpo até a parte 4, com
  o texto "visual feminino chega em breve".
- Personagem antigo: o título muda para "Escolha sua classe" e um aviso diz que a arma atual vai para a
  mochila se não for da classe.

### Restante do jogo

- Desafio da Horda: as cartas de arma da horda continuam como estão; o ataque básico é o da classe.
- Rede: réplicas já recebem a arma equipada; `body` entra no que é replicado (para a parte 4).
- Testes: unitários para `choose_class` (classe inválida, escolher duas vezes, migração da arma),
  `equip` com arma de outra classe, `from_dict` sem os campos novos; smoke test passa pela tela de
  criação; net test cobre a cura em grupo.

## Fica para quem construir

- Nomes, números e modelos dos 5 cetros (modelos via Blender CLI, ver `tools/blender`).
- Visual da esfera de luz e da cura em grupo.
- Detalhe de layout da tela de criação dentro do `UITheme`.
- Versão: subir a versão menor (0.21.0), como nas outras features.
