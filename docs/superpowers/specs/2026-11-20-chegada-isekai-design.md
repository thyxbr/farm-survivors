# Chegada isekai e trava do quadro da Guilda

## Ideia

A história já se chama "Um Herói Caiu na Vila". A abertura agora leva isso ao pé da letra, no
clichê do anime isekai: o jogador é uma alma de outro mundo que "nasce" dentro de Valdoria, montado
de fragmentos de cristal, como se fosse teleportado para dentro do jogo.

Referências usadas na decisão:
- **Isekai**: a transferência/invocação como abertura, a "janela de status" do sistema e o humor do
  "sistema" (corpo montado com o material local, 99,7%). O Bram, que já inventa a profecia na hora,
  encaixa o herói de cristal nela.
- Primeira versão era um meteoro caindo de cabeça na carroça de feno do Beto; o herói de ponta-cabeça
  no feno lia como um pilar, então virou materialização.
- **Onboarding de RPG**: abertura curta e marcante que dá contexto e escala (o plano do céu sobre a
  vila), devolve o controle rápido (~25 s, pulável a qualquer momento) e ensina o resto no contexto
  (a narração termina com "fale com o Bram, E para interagir").

## A cena (scripts/story/arrival_cutscene.gd)

| Tempo | Plano | O que acontece |
|---|---|---|
| 0–5 s | tela preta | "A última coisa de que você se lembra é uma luz muito forte..." / "...e uma voz dizendo: Ops." |
| 5–12 s | janela de SISTEMA | alma de outro mundo, nome, classe, nível 1, título "Forasteiro de Outro Mundo", habilidade ??? e o aviso "corpo original indisponível... material local: cristal, montagem 99,7%" |
| 12–16 s | céu sobre Valdoria | título "Valdoria"; um feixe de luz desce do céu até a estrada e a câmera acompanha |
| 16–19 s | estrada do sul | um selo se acende no chão; fragmentos de cristal descem em espiral (rastro azul e dourado) e montam um casulo |
| 19–21 s | o casulo | pulsa de luz duas vezes e treme; estoura em cacos com flash |
| 21–24 s | de frente para o herói | ele desce flutuando, o brilho se apaga: "Eu fui... montado de cristal? Isso é... OUTRO MUNDO?!" |
| 24–26 s | volta ao jogo | a câmera desliza até trás do herói, olhando a vila; abre a narração |

Depois, a narração (`StoryDialogue.intro()`): o Beto viu tudo e grita, o herói olha as mãos ainda
brilhando num mundo que não é o dele, e o Bram, da praça, já anuncia a profecia. A primeira fala do Bram e
a descrição da missão "chegada" citam o cristal; a escolha "Eu vim de OUTRO MUNDO!" entra na profecia
("Linha dois. Acabei de lembrar.").

Alguns cristais pequenos ficam cravados na estrada (só neste cliente, até sair do mapa).

Regras: roda só para personagem novo (`Game.quests` vazio e nenhum abate), nunca em headless,
`--smoketest`, `--nettest` ou `--nointro`. Espaço, Enter ou Esc pulam. `-- --introdemo` força a cena
num personagem descartável (capturas: `--introdemo --shot=x.png --delay=20`).

## Trava das missões

Campo novo em quests.json: `"requires"` (id ou lista de ids da história) e `"requires_hint"` (o
aviso quando falta). Vale no servidor (`CharRules.start_quest`, erro `requisito`) e no cliente
(`StoryRules.side_available`: sem "+" sobre o NPC, sem oferta).

- Todos os contratos do Quadro da Guilda exigem `registro` (capítulo 7, "Rank D?!"). Antes disso o
  quadro mostra o carimbo "SOMENTE AVENTUREIROS REGISTRADOS" em vez da lista.
- Secundárias de NPC só depois de conhecê-lo na história: Doran (`forja`), Pip (`gel`), Sylvi
  (`bosque`), Bolgar (`mina`), Kael no pico (`kael_sumiu`); Ravi e Sir Osvaldo exigem o registro.
- O modo admin passa por cima, igual ao rank.
