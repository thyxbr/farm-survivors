# Craft: tela nova, atributo aleatório, chance de falha e animação

## Intenção
Fabricar equipamento deve ter mais valor e mais emoção: o item pode sair com um bônus sorteado, receitas
raras podem falhar, e a tela mostra claramente o que vai sair, o que se gasta e o desfecho.

## Objetivos
- Tela de craft refeita: imagem do item que vai sair, ícone em cada material, chances visíveis.
- Bônus aleatório no equipamento fabricado (raro ou acima).
- Chance de falha que cresce com a raridade e cai com o nível da profissão.
- Animação durante o craft, com desfecho de sucesso ou de falha.

## Fora do escopo
- Instâncias de item (valores em faixa, vários bônus livres por item).
- Falha na cozinha, em poções e em materiais (essências): só equipamento falha.

## Abordagens
1. **Sufixo no id + variantes na tabela (escolhida).** Igual à qualidade: `iron_sword@fina~urso`. Inventário,
   rede e save continuam guardando só ids. Limite: um bônus por item, valor fixo pelo nível da receita.
2. **Instâncias de item** (`{"id", "mods"}` no inventário). Permite faixas e vários bônus, mas muda save, rede,
   loja, troca e toda tela que lê o inventário. Grande demais para este pedido.
3. **Bônus só no personagem** (como o encanto, por tipo de arma). Não dá valor ao item em si.

## Design
- **Id:** `base[@qualidade][~afixo]`. `ItemQuality` passa a ler e montar as três partes; as variantes são
  geradas em `ItemQuality.expand` só para saídas de receita de raridade `rare`, `epic` ou `legendary`.
- **Afixos** (`progression.json` → `craft_affix`): Urso (vit), Touro (str), Coruja (int), Raposa (agi),
  Águia (crítico), Lebre (velocidade), Tartaruga (vida), Morcego (roubo de vida). Valor = `base + per_level ×
  nível da receita`; a qualidade multiplica o bônus junto com o resto. Nome: "Lâmina do Cavaleiro Fina da Águia".
  Preço × `price_mult`.
- **Sorteio:** todo equipamento raro+ fabricado com sucesso sai com um afixo sorteado por igual.
- **Falha** (`progression.json` → `craft_fail`): comum 0%, incomum 5%, raro 15%, épico 25%, lendário 35%;
  −1 ponto por nível de profissão acima da receita, nunca abaixo de 40% da chance base.
- **Na falha (decidido pelo usuário: perde metade):** o ouro é gasto; de cada material volta a metade (a unidade
  ímpar volta em 50% das vezes); XP de profissão × 0,5; não conta como "primeira vez".
- **Sem `rng`** (testes determinísticos): nunca falha e não sorteia afixo, como já é com a qualidade.
- **Eventos:** `looted` por item que saiu e `craft_fail {n, back}` com o que voltou.
- **Tela:** lista de receitas com ícone, nível e quantas dá para fazer; à direita o item grande com atributos,
  chances (sucesso, Fina, Obra-prima, bônus), materiais com ícone e tenho/preciso, ouro e XP.
- **Animação:** ao fabricar, o item aparece no centro sendo trabalhado (batidas, faíscas, barra); o desfecho só
  aparece quando o servidor responde: brilho na cor da raridade e nome completo no sucesso; rachadura, fumaça e
  materiais devolvidos na falha. Clique ou tecla fecha.
- **Correção junto:** variantes de qualidade passam a usar a arte do item base (hoje ficam sem ícone pintado).

## Deixado para quem implementa
Números finos dos afixos, tempos e desenho da animação.
