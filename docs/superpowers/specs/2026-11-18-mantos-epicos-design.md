# Mantos de fim de jogo: texturas animadas e efeitos

## Intenção
Os sete conjuntos de mago de nível 50 (0.45.0) são lendários de fim de jogo e precisam parecer épicos:
superfícies que se mexem e efeitos em volta do personagem. O Ceifador do Vazio é a peça principal, com
uma galáxia viva no disco atrás da cabeça **e nas costas do manto** (decisão do Henrique, 18/11/2026).

## Objetivos
- Galáxia animada (nebulosa girando, braços em espiral, estrelas cintilando) no disco do capuz e nas
  costas do manto do Ceifador.
- Cada um dos sete conjuntos com pelo menos uma superfície animada e um efeito de partículas próprio.
- Funcionar com o estilo toon ligado e desligado (`--notoon`), sem custo no servidor dedicado.

## Fora do escopo
- Mudar atributos, preço ou forma de obter os itens.
- Refazer a silhueta dos conjuntos.

## O que seria um fracasso
- Efeito que tampa o personagem ou polui a tela na Horda (muitos jogadores, muitos inimigos).
- Peças soltas no modelo (o `armory.py` imprime `LOOSE`).
- Queda de desempenho perceptível: partículas poucas e baratas, shaders sem textura pesada.

## Abordagens
1. **Shaders por nome de material, em tempo de execução (escolhida).** `ToonLook` reconhece os materiais
   `eg_<conjunto>_<papel>` e troca por um shader animado; `KnightLook` prende partículas quando a peça
   está equipada. Só o que precisa de UV (galáxia) é refeito no Blender.
2. Textura pintada rolando por UV: menos viva e exigiria refazer os 14 modelos com UV.
3. Só partículas: não atende "textura animada".

## Desenho
| Conjunto | Superfície animada | Em volta |
|---|---|---|
| Ceifador do Vazio | galáxia (disco e costas); fios roxos com energia correndo | fiapos de vazio subindo da barra |
| Lich Soberano | fogo-fátuo verde pulsando em olhos e costelas | almas verdes subindo |
| Hierofante Solar | raios do disco solar girando; brilho correndo no ouro | poeira de luz |
| Senhor dos Corvos | reflexo azul-violeta varrendo as penas; olhos pulsando | pena negra caindo de vez em quando |
| Mago Dracônico | brasa respirando entre as escamas | faíscas subindo |
| Astrônomo Celeste | cintilação nas constelações; brilho correndo nas gemas | poeira de estrelas orbitando |
| Soberano do Gelo | brilho interno correndo nos cristais | névoa fria descendo e cintilação |

- A galáxia é um shader procedural (sem textura): coordenada polar a partir do UV, espiral logarítmica,
  ruído para a nebulosa, estrelas por célula com cintilação. O disco ganha UV e perde os braços e
  estrelas de geometria; as costas do manto ganham um painel com UV, costurado ao manto.
- Os demais efeitos de superfície usam posição do objeto/mundo e tempo, sem UV, para não refazer GLBs.
- Ordem: Ceifador primeiro, com captura no jogo para validação; depois os outros seis.

## Deixado ao construtor
Nomes dos shaders, parâmetros finos (velocidade, intensidade), quantidade de partículas.
