class_name LoadingArt
## Ilustrações e trechos de história da tela de carregamento (Loading).
## Cada cena é uma imagem de assets/ui/loading com um título e um trecho curto do mundo de Valdoria.
## Regra pura: sem nó nem autoload, para o teste unitário ler.

const DIR := "res://assets/ui/loading/%s.webp"

const SCENES := [
	{
		"image": "vila",
		"title": "Vale de Valdoria",
		"text": "Uma vila pacata, com um poço, seis casas, uma ferraria barulhenta e um problema sério de slimes. "
			+ "O Ancião Bram jura que a profecia do herói é antiga. A tinta ainda parece fresca.",
	},
	{
		"image": "bosque",
		"title": "Bosque Sussurrante",
		"text": "Dizem que as árvores do bosque cochicham à noite. Ninguém sabe o quê. "
			+ "Os slimes sabem, mas só respondem com \"blop\".",
	},
	{
		"image": "mina",
		"title": "Mina de Cristal",
		"text": "O ferro bom de Valdoria vem das minas. Os cristais também. "
			+ "Os goblins acham que tudo isso é deles, e trouxeram porretes para discutir o assunto.",
	},
	{
		"image": "pico",
		"title": "Pico das Cinzas",
		"text": "No alto do vulcão vive um dragão de escamas em brasa. "
			+ "Kael, a Lâmina Carmesim, desenha dragões sorridentes no escudo. Este não sorri.",
	},
	{
		"image": "horta",
		"title": "A Horta do Portão Sul",
		"text": "Nem toda aventura termina em batalha. Algumas terminam num ensopado quente, "
			+ "abóboras no ponto e um slime que jura que só veio olhar.",
	},
	{
		"image": "estrada",
		"title": "A Estrada do Sul",
		"text": "Foi por esta estrada que o herói chegou: sem mapa, sem dinheiro e com uma fome considerável. "
			+ "Os mercadores dizem que todo caminho de Valdoria começa com um passo e termina com um desconto.",
	},
]


static func image_path(scene: Dictionary) -> String:
	return DIR % str(scene["image"])


## Índice da próxima cena: sorteia entre todas, menos a última mostrada (para não repetir seguido).
static func pick(last: int, roll: int) -> int:
	var n := SCENES.size()
	if n <= 1 or last < 0 or last >= n:
		return posmod(roll, n)
	return (last + 1 + posmod(roll, n - 1)) % n
