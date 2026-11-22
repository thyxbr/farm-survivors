# Ícones do jogo — prompts para o Nano Banana (Gemini)

Duas partes, cada uma em **uma conversa separada** do Gemini (o estilo de fundo é diferente):

- **Parte 1 — Habilidades (37):** hoje são glifos vetoriais reaproveitados do `IconPainter`, sem
  relação com o que a habilidade faz. Ícone com fundo colorido, ocupa o quadro todo.
- **Parte 2 — Itens (113):** hoje são renders 3D dos modelos. Ícone com **fundo branco liso**
  (eu removo o fundo; a cor de raridade continua sendo desenhada pelo espaço do inventário).

---

# Parte 1 — Habilidades

## Como gerar

1. Abra **uma única conversa** no Gemini (modelo de imagem / Nano Banana) e cole primeiro o
   **prompt de estilo** abaixo junto com o primeiro ícone (`fireball`).
2. Quando o primeiro sair bom, gere os outros **na mesma conversa**, começando cada pedido com:
   `Same style, same framing and lighting as the previous icon. Subject:` + o texto do ícone.
   Isso mantém todos com a mesma cara.
3. Salve cada imagem como PNG em `assets/ui/skills/raw/<arquivo>.png` (nome da coluna "Arquivo").
   Não precisa recortar nem redimensionar: eu corto, reduzo para 128 px e ligo no jogo.
4. Se algum sair com texto, moldura ou borda, peça: `Remove any text, frame or border, keep the same art.`

## Prompt de estilo (cole antes do primeiro ícone)

```
Fantasy RPG skill icon for a stylized anime/toon 3D game. Square 1:1 image, 1024x1024.
Hand-painted look with cel shading: flat color areas, 2-3 tone shading, clean dark outlines,
vibrant saturated colors, strong glow on magic. One single bold subject, centered, filling
about 75% of the square, readable as a silhouette even at 48x48 pixels.
Background: soft radial gradient in the given color, darker at the corners, no scenery.
NO text, NO letters, NO numbers, NO frame, NO border, NO rounded corners, NO UI elements.
```

Depois disso, cada ícone é: `Subject: ... Background color: ...`

---

## Situação

- **Prontas e no jogo** (`assets/ui/skills/`): as 17 habilidades de classe, incluindo as 5 da
  tabela 0 e as 2 da 0b abaixo. A Cura do Cetro usa a mesma `heal`.
- **Horda (seções 2 a 5): adiada.** `potion_heal` e `h_fogo` já gerados ficaram guardados em
  `docs/icones_ref/horda/`.

## 0. Habilidades do slot 3 e do Cetro (5, prontas)

| Arquivo | Habilidade | Prompt (Subject + Background) |
|---|---|---|
| `staff_ember` | Bafo de Dragão (Cajado, 10 s de +dano, +crítico, −recarga) | Subject: a fierce dragon head in profile breathing a short burst of orange fire, embers around it, conveying a fiery power-up. Background color: deep orange-red. |
| `sword_fury` | Fúria Picante (Espada, 10 s de +dano e cura por abate) | Subject: a sword blade held upright engulfed in red-hot flames with a bright red chili pepper wrapped in fire at its base, angry rage aura. Background color: dark crimson. |
| `bow_focus` | Olhos de Águia (Arco, 10 s de +crítico e +velocidade) | Subject: the head of a golden eagle in profile with a sharp glowing yellow eye, a thin crosshair ring shining in the eye. Background color: dark forest green. |
| `scepter_ward` | Escudo de Luz (Cetro, escudo em você e nos aliados) | Subject: a dome-shaped shield of golden holy light with a radiant cross symbol in the center, soft light beams and sparkles. Background color: dark royal blue. |
| `scepter_ult` | Banquete do Herói (Cetro, ultimate: cura total e bônus ao grupo) | Subject: a golden goblet raised in a toast above a festive roast and bread, glowing with warm golden holy light and sparkles. Epic, celebratory. Background color: dark amber. |

## 0b. Habilidades novas do Cetro (2, prontas)

Na mesma conversa das outras (ou cole de novo o prompt de estilo antes da primeira). O Escudo de Luz
continua com a `scepter_ward` que já existe.

| Arquivo | Habilidade | Prompt (Subject + Background) |
|---|---|---|
| `scepter_lance` | Lança de Luz (Cetro, dano alto num alvo) | Subject: a radiant spear made of golden holy light flying diagonally toward the top-right, sharp white-gold spearhead, a small four-pointed star glint at the base of the spearhead, a short brushstroke trail of light behind it. Background color: dark indigo purple. |
| `scepter_judgment` | Julgamento de Luz (Cetro, área mirada no chão) | Subject: a wide pillar of golden holy light crashing down from the sky onto a glowing circular seal on the ground with a cross in its center, seen from a slight top-down angle, light rays and four-pointed sparkles bursting outward from the impact. Epic, powerful. Background color: dark slate teal. |

## 1. Habilidades de classe (barra de atalhos, 11)

| Arquivo | Habilidade | Prompt (Subject + Background) |
|---|---|---|
| `fireball` | Bola de Fogo | Subject: a blazing fireball flying diagonally toward the top-right, bright yellow core, orange flames, a short fiery trail behind it. Background color: deep crimson. |
| `frost_nova` | Nova Gélida | Subject: an explosive ring of ice shards bursting outward from a glowing frozen center, seen from above, sharp crystals radiating in all directions, frost mist. Background color: dark navy blue. |
| `heal` | Cura | Subject: a pair of open cupped hands releasing a soft green-gold healing light, small plus-shaped sparkles and leaves floating upward. Background color: deep emerald green. |
| `meteor_rain` | Chuva de Meteoros (ultimate) | Subject: three flaming meteors falling diagonally from the top-left toward the bottom-right, long fire trails, the lowest one about to impact with a burst of embers. Epic, powerful. Background color: dark purple turning into fiery orange at the bottom. |
| `sword_charge` | Investida | Subject: a knight's sword thrusting forward to the right with strong motion lines and a dust cloud behind it, conveying a fast dash attack, blade pointing right. Background color: dark steel blue. |
| `sword_quake` | Golpe Sísmico | Subject: a heavy greatsword stabbed point-down into the ground, the ground cracking open around it with glowing orange fissures and flying rock chunks, shockwave ring. Background color: dark brown. |
| `sword_whirl` | Turbilhão (ultimate) | Subject: a spinning whirlwind of sword blades seen from above, several silver blades in a circle leaving bright circular slash trails, a vortex of wind in the middle. Epic, powerful. Background color: dark teal. |
| `bow_triple` | Tiro Triplo | Subject: three arrows flying upward-right in a fan spread from a single point, each with a light motion trail, clean wooden shafts and steel tips. Background color: dark forest green. |
| `bow_frost` | Flecha Glacial | Subject: a single arrow made of blue ice with a crystalline arrowhead, flying diagonally, leaving a trail of snowflakes and frost, ice crystals forming around the tip. Background color: dark icy blue. |
| `bow_gale` | Flecha do Vendaval (ultimate) | Subject: a single glowing arrow tearing horizontally through the air, wrapped in a spiraling white-green wind tunnel, air rings bursting around it, extreme speed. Epic, powerful. Background color: dark jade green. |
| `potion_heal` | Poção Restauradora (carta de cura da Horda) | Subject: a round glass potion bottle full of bright red liquid with a cork stopper, small heart-shaped bubbles rising, warm glow. Background color: dark wine red. |

## 2. Armas automáticas da Horda (4)

| Arquivo | Arma | Prompt |
|---|---|---|
| `h_fogo` | Orbe de Fogo | Subject: a floating sphere of swirling fire with two small fireballs launching out of it, magic orb of flame. Background color: deep crimson. |
| `h_laminas` | Lâminas Orbitais | Subject: two curved silver blades orbiting in a circle around a small glowing center point, circular motion trails connecting them. Background color: dark steel blue. |
| `h_raio` | Relâmpago | Subject: a jagged bright yellow-white lightning bolt striking down from a small dark storm cloud at the top, electric sparks at the impact point. Background color: dark indigo. |
| `h_aura` | Aura Gélida | Subject: a glowing circle of frost on the ground seen at an angle, cold mist rising from the ring, ice crystals growing along its edge, empty center. Background color: dark navy blue. |

## 3. Passivas (cartas da Horda e Ecos permanentes, 8)

| Arquivo | Passiva | Prompt |
|---|---|---|
| `p_poder` | Poder | Subject: a clenched armored gauntlet fist raised, glowing red-orange power aura around it. Background color: dark red. |
| `p_celeridade` | Celeridade | Subject: a golden hourglass with sand flowing fast, small wind swirls around it, conveying faster cooldowns. Background color: dark teal. |
| `p_vigor` | Vigor | Subject: a big bright red heart with a strong glow and a subtle golden outline, healthy and full. Background color: dark crimson. |
| `p_botas` | Botas Velozes | Subject: a single leather boot with small white wings at the ankle and speed lines behind it. Background color: dark sky blue. |
| `p_ima` | Ímã | Subject: a red and silver horseshoe magnet pulling small glowing blue-green gems toward it. Background color: dark purple. |
| `p_alcance` | Alcance | Subject: concentric glowing rings expanding outward from a central point, like a ripple of energy growing larger. Background color: dark violet. |
| `p_armadura` | Armadura | Subject: a sturdy steel heater shield with a gold rim and rivets, front view. Background color: dark slate grey. |
| `p_regeneracao` | Regeneração | Subject: a small green sprout with two leaves growing from a glowing drop of water, soft green sparkles. Background color: dark green. |

## 4. Bênçãos (fim de rodada da Horda, 7)

Bênçãos são divinas: peça sempre um leve halo dourado atrás do símbolo.

| Arquivo | Bênção | Prompt |
|---|---|---|
| `b_furia` | Bênção da Fúria | Subject: two crossed axes engulfed in red flames, a faint golden halo behind them. Background color: dark blood red. |
| `b_vida` | Bênção da Vida | Subject: a glowing white-gold heart with small angel wings, a faint golden halo behind it. Background color: dark rose. |
| `b_sabedoria` | Bênção da Sabedoria | Subject: an open ancient book with glowing blue pages and a small star of light rising from it, a faint golden halo behind it. Background color: dark blue. |
| `b_sorte` | Bênção da Sorte | Subject: a green four-leaf clover with a sparkling golden glint, a faint golden halo behind it. Background color: dark green. |
| `b_sangue` | Sede de Sangue | Subject: a dark ornate chalice overflowing with glowing red liquid, a single red drop falling, a faint golden halo behind it. Background color: very dark maroon. |
| `b_vento` | Bênção do Vento | Subject: a stylized white-cyan gust of wind spiral with a single feather caught in it, a faint golden halo behind it. Background color: dark cyan. |
| `b_ouro` | Bênção do Ouro | Subject: a small pile of shining gold coins with one coin standing upright and sparkling, a faint golden halo behind it. Background color: dark amber brown. |

## 5. Combos em grupo da Horda (6)

Cada combo junta os elementos das duas armas.

| Arquivo | Combo | Prompt |
|---|---|---|
| `c_choque` | Choque Térmico (fogo + gelo) | Subject: a fireball and an ice crystal colliding in the center, a big burst of white steam exploding from the impact, half orange half blue. Background color: dark grey-blue. |
| `c_plasma` | Plasma (fogo + raio) | Subject: a crackling ball of purple-pink plasma with electric arcs jumping out to several small points around it. Background color: very dark magenta. |
| `c_brasas` | Ciclone de Brasas (lâminas + fogo) | Subject: curved blades spinning in a circle wrapped in flames, forming a ring of fire with flying embers. Background color: dark orange-brown. |
| `c_tempestade` | Tempestade Gélida (raio + gelo) | Subject: three pale-blue icy lightning bolts striking down from a frozen cloud, snowflakes and ice shards at the impact. Background color: dark navy. |
| `c_eletro` | Lâminas Elétricas (lâminas + raio) | Subject: a silver blade crackling with yellow electricity, lightning arcs jumping off its edge to the sides. Background color: dark indigo. |
| `c_nevasca` | Nevasca Cortante (lâminas + gelo) | Subject: a whirling storm of sharp ice shards and snow spinning in a circle like blades. Background color: dark icy blue. |

---

# Parte 2 — Itens

## Como gerar

1. Abra uma **conversa nova** (não a das habilidades) e cole o **prompt de estilo de itens** junto
   com o primeiro item.
2. **Equipamentos (seções A a E):** anexe a imagem de referência `docs/icones_ref/<arquivo>.png`
   (é o render 3D atual do modelo que o personagem veste). Assim o ícone continua batendo com o
   que aparece no boneco. Mande: `Redraw the attached object. Notes:` + o texto da tabela.
3. **Consumíveis, materiais, sementes, colheita e comida (seções F a I):** sem anexo, só o texto:
   `Same style as the previous icons. Subject:` + o texto da tabela.
4. Salve como `assets/ui/items/raw/<arquivo>.png`. O nome do arquivo é o id do item.
   Para recortar e tirar o fundo: `python -X utf8 tools/icons/slice_grid.py <imagem> <id1,id2,...>`
   (um id `-` pula um objeto repetido). A saída vai para `assets/ui/items/<id>.png` (256 px); rode
   o `--import` do Godot e troque `mipmaps/generate=false` para `true` no `.import` novo.
5. Se sair com sombra no chão, fundo que não é branco liso ou peças inventadas, peça:
   `Keep only the object on a pure flat white background, no shadow, no extra parts.`

## Prompt de estilo de itens (cole antes do primeiro item)

```
Fantasy RPG inventory item icon for a stylized anime/toon 3D game. Square 1:1 image, 1024x1024.
Hand-painted look with cel shading: flat color areas, 2-3 tone shading, light from the top-left,
clean dark outline around the whole object, vibrant saturated colors, small white highlights
on metal and gems. One single object, centered, filling about 80% of the square, readable as a
silhouette even at 48x48 pixels.
Background: pure flat white (#FFFFFF), completely plain. NO shadow on the ground, NO glow on the
background, NO text, NO frame, NO border.
When a reference image is attached: keep the exact same shape, proportions, colors and parts
of the object in the reference. Do not add, remove or invent parts. Only change the rendering
style to hand-painted cel shading. Swords, staffs and bows are shown diagonally, from
bottom-left (handle) to top-right (tip).
```

## Modo em grade: vários itens numa imagem só

> **Situação:** as 4 grades estão prontas (0.29.1) e os 39 itens das seções F a I já usam arte
> pintada. As grades originais ficam em `assets/ui/items/raw/`. Os equipamentos (A a E) ainda
> usam o render 3D.

Para não rodar um prompt por item, as seções F a I podem sair em **4 imagens em grade**. Eu recorto
cada objeto sozinho: acho as manchas que não são brancas, então a grade não precisa sair perfeita,
só **com bastante branco entre os objetos e nenhum objeto encostando em outro**.

Use a mesma conversa do prompt de estilo de itens e mande um bloco por vez. Salve como
`assets/ui/items/raw/grade_1.png`, `grade_2.png`, ... A ordem dos objetos é a da lista
(esquerda→direita, de cima para baixo). Se algum sair ruim, refaça só esse no modo de um por vez.

**Grade 1 — consumíveis e materiais (12, 4 colunas × 3 linhas)**

```
Create ONE square image, 2048x2048, that is a sprite sheet of 12 separate inventory item icons in
a grid of 4 columns and 3 rows, in the item icon style described before. Pure flat white background
everywhere. Each item sits centered in its own cell with wide empty white space around it; no item
touches another item or the edge of the image. No grid lines, no cell borders, no text, no numbers,
no shadows. All items drawn at a similar size and with the same dark outline.
Order, left to right, top to bottom:
1 a round glass potion bottle with bright red liquid and a cork stopper
2 a round glass potion bottle with bright blue liquid and a cork stopper
3 a wobbly blob of translucent green slime gel with a shine
4 a pointy green goblin ear, cartoonish
5 a broken off-white bone shard with a jagged end
6 a long curled pink sticky frog tongue
7 a single thin leathery bat wing, dark brown-purple membrane
8 a small spool wound with shiny white spider silk thread
9 a single curved sharp raptor claw like a sickle
10 a small dirty, dented gold crown with a few gems
11 a heavy dark grey rock chunk with rusty orange iron veins
12 a cluster of glowing purple arcane crystals
```

Ordem dos arquivos: `health_potion, mana_potion, slime_gel, goblin_ear, bone_shard, frog_tongue,
bat_wing, spider_silk, raptor_claw, goblin_crown, iron_ore, arcane_crystal`.

**Grade 2 — materiais raros (7, 4 colunas × 2 linhas)**

Mesmo texto da grade 1, trocando o começo para `8 separate inventory item icons in a grid of
4 columns and 2 rows` e a lista para:

```
1 a glowing hot ember core, dark rock cracked with orange light
2 a single droplet made of icy blue crystal, frosty sparkles
3 a small carved wooden goblin totem with a yellow lightning mark
4 a bulbous green-purple toxic gland dripping a drop of poison
5 a small open cloth pouch spilling sparkling golden dust
6 a single dark grey-purple fang with a faint shadowy aura
7 a gold medal badge with a star in the center and a red ribbon
8 leave this cell completely empty and white
```

Ordem dos arquivos: `ember_core, frost_drop, thunder_totem, toxic_gland, golden_dust,
shadow_fang, champion_badge`.

**Grade 3 — colheita e sementes (12, 4 colunas × 3 linhas)**

Mesmo texto da grade 1, com a lista:

```
1 a fresh orange carrot with green leafy top
2 a small bundle of golden wheat stalks tied with string
3 a shiny ripe red tomato with green stem
4 a bright red fire chili pepper with a tiny flame at its tip
5 a sprig of pale cyan-green mint leaves with tiny frost sparkles
6 a big round orange pumpkin with a curly stem and a leaf
7 a small tied burlap seed pouch with an orange label showing a carrot, a few seeds spilling out
8 the same burlap seed pouch with a yellow label showing a wheat ear
9 the same burlap seed pouch with a red label showing a tomato
10 the same burlap seed pouch with a fiery red label showing a chili pepper
11 the same burlap seed pouch with a pale cyan label showing a mint leaf
12 the same burlap seed pouch with an orange-brown label showing a pumpkin
```

Ordem dos arquivos: `carrot, wheat, tomato, pepper, mint, pumpkin, seed_carrot, seed_wheat,
seed_tomato, seed_pepper, seed_mint, seed_pumpkin`.

**Grade 4 — comida (8, 4 colunas × 2 linhas)**

Mesmo texto da grade 1, trocando o começo para `8 separate inventory item icons in a grid of
4 columns and 2 rows` e a lista para:

```
1 a rustic round loaf of bread with a scored golden crust
2 a wooden bowl of carrot stew with carrot chunks, a little steam
3 a wooden bowl of red spicy soup with a chili on the rim, steam
4 a clay bowl of dark red chili with small flames rising from it
5 a cup of pale cyan mint tea with a mint leaf and frosty cold mist
6 a wooden bowl of fresh green salad with tomato and carrot pieces
7 a round pumpkin pie with one slice cut out, golden crust
8 a grand platter with a roast chicken, bread and fruit, festive
```

Ordem dos arquivos: `bread, carrot_stew, spicy_soup, dragon_chili, mint_tea, garden_salad,
pumpkin_pie, valdoria_feast`.

**Equipamentos em grade (opcional).** Funciona igual, mas anexando as referências: anexe 4 imagens
de `docs/icones_ref/` e peça `a sprite sheet of 4 item icons in a grid of 2 columns and 2 rows,
redrawing the 4 attached objects in the same order, keeping each one's exact shape, colors and
parts`. Com mais de 4 o Gemini costuma misturar as peças de um item no outro.

## A. Espadas (23) — anexar referência

| Arquivo | Item | Notes |
|---|---|---|
| `wooden_sword` | Espada de Madeira | Training sword of plain light wood, simple crossguard. |
| `iron_sword` | Espada de Ferro | Simple straight iron sword, leather-wrapped grip. |
| `steel_saber` | Sabre de Aço | Light curved steel saber. |
| `knight_blade` | Lâmina do Cavaleiro | Tempered steel blade with faint glowing blue runes. |
| `frost_brand` | Marca Gélida | Steel sword with a frosted icy blue edge, tiny ice crystals. |
| `goblin_cleaver` | Cutelo do Rei Goblin | Heavy, crude, brutal cleaver, chipped edge. |
| `guardian_greatsword` | Montante do Guardião | Large ancient greatsword of ruin guardians. |
| `dragonfang` | Presa do Dragão | Greatsword carved from a dragon tooth, ivory-to-orange blade, red curved guard. |
| `azure_edge` | Gume Celeste | Light steel blade with a sky-blue edge. |
| `thorn_root` | Espinho da Raiz | Sharpened bone blade wrapped in green vines. |
| `venom_leaf` | Folha Peçonhenta | Serrated metal blade shaped like a leaf, poison green. |
| `crimson_reed` | Junco Carmesim | Very thin crimson saber. |
| `amber_fang` | Presa de Âmbar | Amber-colored blade, thorny handle. |
| `rose_flame` | Chama Rosada | Blade with pink flames frozen in the steel. |
| `crystal_frost` | Lâmina de Cristal | Faceted ice crystal blade. |
| `moon_crescent` | Crescente Lunar | Crescent-curved blade with a rose quartz heart. |
| `neon_edge` | Lâmina Neon | Relic blade with a glowing neon edge. |
| `pale_crescent` | Foice Pálida | Pale hooked blade with a ring-shaped guard. |
| `coral_spine` | Espinha Coral | Serrated coral crest blade, sea colors. |
| `scarlet_talon` | Garra Escarlate | Curved scarlet beast-claw cleaver. |
| `titan_cleaver` | Cutelo do Titã | Giant slab-of-steel cleaver. |
| `ivory_wing` | Asa de Marfim | White greatsword with a feather-shaped guard. |
| `royal_wings` | Asa Real | Ancient king's sword with golden wings on the guard and a glowing core. |

## B. Cajados (13) — anexar referência

| Arquivo | Item | Notes |
|---|---|---|
| `apprentice_staff` | Cajado de Aprendiz | Simple wooden apprentice staff, small arcane spark at the top. |
| `oak_staff` | Cajado de Carvalho Antigo | Gnarled ancient oak staff. |
| `ember_staff` | Cajado das Brasas | Staff topped with a glowing ember, small flames. |
| `frost_scepter` | Cetro da Geada | Scepter with an eternal ice crystal on top. |
| `archmage_staff` | Cajado do Arquimago | Ornate legendary archmage staff, glowing gem. |
| `willow_staff` | Cajado de Salgueiro | Willow branches holding a jade stone. |
| `bone_staff` | Cajado de Ossos | Bone staff with a small skull whose eyes glow. |
| `tide_staff` | Cajado das Marés | Coral and pearl staff, sea colors. |
| `sun_staff` | Cetro Solar | Golden sun ring around an amber gem. |
| `storm_staff` | Cajado da Tempestade | Dark steel staff holding two lightning bolts, small sparks. |
| `thorn_staff` | Cajado de Espinheiro | Thorny branch staff with a crimson rose at the top. |
| `void_staff` | Cajado do Vazio | Obsidian staff with a black crescent moon. |
| `phoenix_staff` | Cajado da Fênix | Staff with fiery phoenix wings at the top. |

## C. Arcos (5) — anexar referência

| Arquivo | Item | Notes |
|---|---|---|
| `short_bow` | Arco Curto | Simple short wooden bow with string. |
| `hunter_bow` | Arco do Caçador | Smoke-cured yew hunting bow. |
| `elven_bow` | Arco Élfico | Elegant light elven bow, leaf motifs. |
| `goblin_warbow` | Arco de Guerra Goblin | Ugly, crooked goblin war bow. |
| `storm_bow` | Arco da Tempestade | Bow crackling with small lightning sparks. |

## D. Armaduras e roupas (8) — anexar referência

| Arquivo | Item | Notes |
|---|---|---|
| `leather_armor` | Armadura de Couro | Tanned leather chest armor, front view. |
| `chain_mail` | Couraça de Ferro | Iron breastplate with a center ridge over dark chain mail, front view. |
| `mage_robe` | Manto Arcano | Mage robe with embroidery that glows faintly. |
| `ranger_vest` | Gibão do Patrulheiro | Olive green ranger vest with metal-tipped clasps, two crossed leather straps with light edging, a dark knit scarf and long split coat panels with stitched pockets, front view. |
| `royal_plate` | Placas Reais | Heroic plate armor. |
| `traveler_tunic` | Túnica de Viajante | Two-color wool tunic with bandolier and pouch. |
| `guard_surcoat` | Sobreveste da Guarda | Chain mail under a tabard with the guard's cross. |
| `dragon_plate` | Couraça de Escamas de Dragão | Dark dragon-scale armor with glowing red ember between the scales and a flame gem on the chest. |
| `mithril_plate` | Placa de Mithril | Fitted elven plate armor of bluish silver mithril with a tall gorget, a V-shaped bib, waist lames and inlaid pale blue leaves growing up the chest like a tree, front view. |
| `astral_plate` | Placas Astrais | Golden celestial knight plate armor with a high gorget, a sun dial on the chest that sinks like a funnel into a small black hole, curved grooves meeting at the waist, and a deep blue cape lined like a starry night sky, front view. |
| `blackdragon_plate` | Placas do Dragão Negro | Dark gunmetal dragon plate armor: a split breastplate with claw-shaped ridges and a dark green leather channel down the middle, a glowing golden dragon eye with a slit pupil set in a ring under the gorget, huge rounded pauldrons covered in overlapping dragon scales with gold trim and a sickle fin, forearm guards with a curved fin blade and gold bands, scale-patterned tassets and long pale grey cloth panels hanging at the front and sides, front view. |
| `cosmic_plate` | Armadura do Cavaleiro Cósmico | Cool lavender-silver legendary plate armor in stylized RPG style: a large almond window on the sternum showing a purple and magenta starry sky with small gold rings, framed in thick gold with gold feather blades sweeping to the shoulders, huge round pauldrons with a sky window on top and a wide horn blade rising diagonally outward, layered steel waist lames, a wide gold belt with a planet-ring buckle, a narrow starry sky tabard ending in an anchor point between split tassets, front view. |

## E. Acessórios e peças (25) — anexar referência

| Arquivo | Item | Notes |
|---|---|---|
| `leather_cap` | Capuz de Couro | Leather cap. |
| `iron_helm` | Elmo de Ferro | Iron helmet with a few dents. |
| `wizard_hat` | Chapéu do Mago | Pointy wizard hat. |
| `ranger_hood` | Capuz do Patrulheiro | Green ranger hood. |
| `knight_helm` | Elmo do Cavaleiro | Knight helmet with red plume and golden visor. |
| `wool_hood` | Capuz de Lã | Simple wool hood. |
| `kettle_hat` | Chapéu de Ferro | Wide-brimmed iron kettle hat over chain mail. |
| `guard_greathelm` | Elmo Fechado da Guarda | Closed great helm, narrow slit, golden cross. |
| `leather_gloves` | Luvas de Couro | Pair of leather gloves. |
| `iron_gauntlets` | Manoplas de Ferro | Pair of iron gauntlets. |
| `archer_bracers` | Braçadeiras do Arqueiro | Pair of leather archer bracers. |
| `spellweaver_gloves` | Luvas do Tecelão | Pair of gloves with small glowing runes. |
| `leather_boots` | Botas de Couro | Pair of leather boots. |
| `iron_greaves` | Grevas de Ferro | Pair of iron greaves. |
| `swift_boots` | Botas Velozes | Pair of boots with wings embroidered at the heel. |
| `reinforced_boots` | Botas Reforçadas | Leather boots with steel greaves and toe caps. |
| `royal_greaves` | Grevas Reais | Pair of silver greaves with gold trim and winged knee cops. |
| `royal_gauntlets` | Manoplas Reais | Pair of silver gauntlets with flared cuffs trimmed in gold. |
| `ember_helm` | Elmo de Escamas de Dragão | Black closed helm with glowing ember eyes, a mouth grille and swept-back horns. |
| `ember_claws` | Garras de Escamas de Dragão | Pair of black scale gauntlets with long claws and a glowing ember slit. |
| `ember_greaves` | Grevas de Escamas de Dragão | Pair of black scale greaves with clawed feet and ember between the scales. |
| `ranger_boots` | Botas do Patrulheiro | Pair of tall dark leather boots wrapped in stacked leather bands, a turned-down cuff and pointed shoes with a buckled ankle strap. |
| `ranger_gloves` | Luvas do Patrulheiro | Pair of archer gloves: one brown leather glove, the other dark leather wrapped in blue cloth with a red strap. |
| `mithril_greaves` | Grevas de Mithril | Pair of bluish silver elven greaves with a domed knee cop fanned with inlaid pale blue leaves, a V plate with a shield-shaped leaf and long pointed sabatons. |
| `mithril_gauntlets` | Manoplas de Mithril | Pair of bluish silver plate gauntlets with a knuckle ridge and three inlaid pale blue leaves on the back of each hand. |
| `astral_helm` | Elmo Astral | Golden armet-style helm with a light gold brow band carrying a small sun, a narrow vertical faceplate with open eye windows on both sides, a blue horsehair crest and a fan of sun rays around a black hole behind the head. |
| `astral_greaves` | Grevas Astrais | Pair of golden greaves with a domed knee cop and pointed side wing, a smooth shin plate flaring over the ankle and long, thin pointed sabatons. |
| `astral_gauntlets` | Manoplas Astrais | Pair of golden plate gauntlets with a knuckle ridge and a bell-shaped cuff rising to a point on the outer side. |
| `blackdragon_helm` | Elmo do Dragão Negro | Dark gunmetal dragon-skull helm: a mask narrowing to a pointed chin, a center ridge on the brow, angry almond eyes glowing gold under angled brow ridges, two pairs of horns (one rising and curving back, one sweeping out and down with the tips turning up), pointed side fins and a row of small spikes along the crest. |
| `blackdragon_greaves` | Grevas do Dragão Negro | Pair of dark graphite greaves with a shield-shaped dark green knee cop framed in thick gold with a gold spike rising from a notch, a dark green fin behind the calf, a gold line at the ankle, a blade spur on the heel and claw-tipped sabatons. |
| `blackdragon_gauntlets` | Manoplas do Dragão Negro | Pair of steel plate gauntlets with lames across the back of the hand, curved claws over the fingers and a short cuff. |
| `cosmic_helm` | Elmo do Cavaleiro Cósmico | Lavender-silver knight helm with a sculpted face: slanted shard-shaped eyes showing a purple starry sky (a small glowing gold four-point star in the left eye), a nose ridge between angled brow blades, angular mandible plates with short dark vents meeting at a pointed chin, a thick gold crescent fork rising from the brow with sky inlays, a short flat crest and a gold rim. |
| `cosmic_greaves` | Grevas do Cavaleiro Cósmico | Pair of lavender-silver greaves with a round knee cop bearing a gold four-point star and a small swept fin, a bell-flared shin plate with an almond starry sky window framed in gold, thick gold bands and pointed sabatons. |
| `cosmic_gauntlets` | Manoplas do Cavaleiro Cósmico | Pair of dark steel plate gauntlets with a round starry sky disc framed in gold on the back of the hand and a bell-shaped silver cuff with a thick gold ring. |
| `wooden_shield` | Escudo de Madeira | Wooden plank shield with nails, front view. |
| `knight_shield` | Escudo do Cavaleiro | Shield with the Valdoria guard crest, front view. |
| `arcane_orb` | Orbe Arcano | Floating glowing arcane orb. |
| `hunter_quiver` | Aljava do Caçador | Quiver full of feathered arrows. |
| `life_amulet` | Amuleto da Vida | Amulet with a red heart gem on a chain. |
| `sage_amulet` | Amuleto do Sábio | Amulet with a blue gem on a chain. |
| `strength_ring` | Anel da Força | Iron ring with a rough ruby. |
| `wind_ring` | Anel do Vento | Ring with a pale green-cyan gem, airy. |
| `vampire_ring` | Anel do Vampiro | Dark ring with a blood-red gem. |

## F. Consumíveis e materiais (19) — só texto

| Arquivo | Item | Subject |
|---|---|---|
| `health_potion` | Poção de Vida | A round glass potion bottle with bright red liquid and a cork stopper. |
| `mana_potion` | Poção de Mana | A round glass potion bottle with bright blue liquid and a cork stopper. |
| `slime_gel` | Gel de Slime | A wobbly blob of translucent green slime gel with a shine. |
| `goblin_ear` | Orelha de Goblin | A pointy green goblin ear, cartoonish, slightly gross. |
| `bone_shard` | Lasca de Osso | A broken off-white bone shard with a jagged end. |
| `frog_tongue` | Língua de Bocarrão | A long curled pink sticky frog tongue. |
| `bat_wing` | Asa de Couro | A single thin leathery bat wing, dark brown-purple membrane. |
| `spider_silk` | Seda de Tecelã | A small spool wound with shiny white spider silk thread. |
| `raptor_claw` | Garra de Raptor | A single curved sharp raptor claw like a sickle. |
| `goblin_crown` | Coroa do Rei Goblin | A small dirty, dented gold crown with a few gems. |
| `iron_ore` | Minério de Ferro | A heavy dark grey rock chunk with rusty orange iron veins. |
| `arcane_crystal` | Cristal Arcano | A cluster of glowing purple arcane crystals. |
| `ember_core` | Núcleo em Brasa | A glowing hot ember core, dark rock cracked with orange light. |
| `frost_drop` | Gota Gélida | A single droplet made of icy blue crystal, frosty sparkles. |
| `thunder_totem` | Totem Trovejante | A small carved wooden goblin totem with a yellow lightning mark. |
| `toxic_gland` | Glândula Tóxica | A bulbous green-purple toxic gland dripping a drop of poison. |
| `golden_dust` | Pó Dourado | A small open cloth pouch spilling sparkling golden dust. |
| `shadow_fang` | Presa Sombria | A single dark grey-purple fang with a faint shadowy aura. |
| `champion_badge` | Insígnia do Campeão | A gold medal badge with a star in the center and a red ribbon. |

## F2. Materiais das profissões (23) — só texto

Hoje com arte **provisória** gerada por `tools/icons/make_material_icons.py` (recolor das pinturas acima e desenho
simples). Gere estes e substitua o PNG do mesmo nome em `assets/ui/items/`.

| Arquivo | Item | Subject |
|---|---|---|
| `copper_ore` | Minério de Cobre | A dark rock chunk with bright copper-orange metal veins. |
| `silver_ore` | Minério de Prata | A grey rock chunk with shiny white-silver metal veins. |
| `mithril_ore` | Minério de Mithril | A dark rock chunk with glowing pale cyan mithril veins. |
| `astralite_ore` | Minério de Astralita | A black rock chunk with glowing violet star-like metal veins and tiny sparkles. |
| `pine_log` | Tora de Pinho | A short cut log of light brown pine wood with visible growth rings. |
| `oak_log` | Tora de Carvalho | A short cut log of dark sturdy oak with thick bark and rings. |
| `silverbirch_log` | Tora de Bétula-prata | A short cut log with white-silver birch bark with dark marks. |
| `ashwood_log` | Tora de Freixo-cinza | A short cut log with ash-grey bark and pale grey wood. |
| `soulwood_log` | Tora de Madeira-de-alma | A short cut log of purple wood with faintly glowing violet rings. |
| `hide_t1` | Couro Cru | A rough untreated light brown animal hide, stretched shape. |
| `hide_t2` | Couro Curtido | A tanned brown leather hide, smooth, with stitched edge. |
| `hide_t3` | Couro Reforçado | A thick grey-brown leather hide with metal studs. |
| `hide_t4` | Couro Sombrio | A dark purple-black leather hide with a cold sheen. |
| `hide_t5` | Couro Astral | A blue-violet leather hide with tiny star sparkles. |
| `essence_t1` | Essência Tênue | A round glass flask with pale green glowing essence. |
| `essence_t2` | Essência Viva | A round glass flask with teal swirling essence. |
| `essence_t3` | Essência Vibrante | A round glass flask with violet crackling essence. |
| `essence_t4` | Essência Ancestral | A round glass flask with amber-gold ancient essence and runes. |
| `essence_t5` | Essência Astral | A round glass flask with magenta-white starry essence. |
| `royal_jelly` | Geleia Real | A wobbly blob of glowing golden royal jelly with a tiny crown shape. |
| `knight_sigil` | Selo do Cavaleiro | A silver medal seal with a skull-and-sword emblem and a grey ribbon. |
| `lich_phylactery` | Filactério do Lich | A sickly green crystal phylactery cluster with dark wisps. |
| `abyss_core` | Núcleo do Abismo | A dark crimson crystal core pulsing with abyssal red light. |
| `recipe_scroll` | Pergaminho de Receita | A rolled parchment recipe scroll with a red wax seal. |

## G. Sementes (6) — só texto

Todas são o mesmo saquinho, muda só o desenho e a cor da etiqueta: assim dá para reconhecer o saco
de sementes de longe e a cultura de perto.

| Arquivo | Item | Subject |
|---|---|---|
| `seed_carrot` | Semente de Cenoura | A small tied burlap seed pouch with an orange label showing a carrot, a few seeds spilling out. |
| `seed_wheat` | Semente de Trigo | The same burlap seed pouch with a yellow label showing a wheat ear, a few seeds spilling out. |
| `seed_tomato` | Semente de Tomate | The same burlap seed pouch with a red label showing a tomato, a few seeds spilling out. |
| `seed_pepper` | Semente de Pimenta-de-Fogo | The same burlap seed pouch with a fiery red label showing a chili pepper, a few seeds spilling out. |
| `seed_mint` | Semente de Menta Gélida | The same burlap seed pouch with a pale cyan label showing a mint leaf, a few seeds spilling out. |
| `seed_pumpkin` | Semente de Abóbora | The same burlap seed pouch with an orange-brown label showing a pumpkin, a few seeds spilling out. |

### Semente nova (para sementes que entrarem depois)

Para o saquinho sair igual aos 6 que já existem, **não gere do zero**: anexe
`assets/ui/items/seed_carrot.png` e `assets/ui/items/<cultura>.png` (o ícone da colheita nova, que
já deve existir) e mande, na conversa do prompt de estilo de itens:

```
Redraw the first attached image (a burlap seed pouch) EXACTLY the same: same pouch shape, same
burlap color and stitching, same rope tie, same size and angle, same square label in the same
place, same few seeds spilling at the bottom right. Change ONLY the label: color it <cor da
etiqueta> and draw on it a tiny simple version of the second attached image (<cultura>).
Pure flat white background, no shadow, no text.
```

Depois recorte com `slice_grid.py` passando só o id (`seed_<cultura>`). O teste
`tests/unit/test_item_art.gd` falha se uma semente (ou qualquer item que não é equipamento) entrar
em `data/balance/items.json` sem arte em `assets/ui/items/`.

## H. Colheita (6) — só texto

| Arquivo | Item | Subject |
|---|---|---|
| `carrot` | Cenoura | A fresh orange carrot with green leafy top. |
| `wheat` | Trigo | A small bundle of golden wheat stalks tied with string. |
| `tomato` | Tomate | A shiny ripe red tomato with green stem. |
| `pepper` | Pimenta-de-Fogo | A bright red fire chili pepper with a tiny flame at its tip. |
| `mint` | Menta Gélida | A sprig of pale cyan-green mint leaves with tiny frost sparkles. |
| `pumpkin` | Abóbora | A big round orange pumpkin with a curly stem and a leaf. |

## I. Comida (8) — só texto

| Arquivo | Item | Subject |
|---|---|---|
| `bread` | Pão Rústico | A rustic round loaf of bread with a scored golden crust. |
| `carrot_stew` | Ensopado de Cenoura | A wooden bowl of carrot stew with carrot chunks, a little steam. |
| `spicy_soup` | Sopa Picante | A wooden bowl of red spicy soup with a chili on the rim, steam. |
| `dragon_chili` | Chili do Dragão | A clay bowl of dark red chili with small flames rising from it. |
| `mint_tea` | Chá de Menta Gélida | A cup of pale cyan mint tea with a mint leaf and frosty cold mist. |
| `garden_salad` | Salada da Horta | A wooden bowl of fresh green salad with tomato and carrot pieces. |
| `pumpkin_pie` | Torta de Abóbora | A round pumpkin pie with one slice cut out, golden crust. |
| `valdoria_feast` | Banquete de Valdoria | A grand platter with a roast chicken, bread and fruit, festive. |

---

## Depois de gerar

Me avise quando os PNGs estiverem em `assets/ui/skills/raw/` e `assets/ui/items/raw/`. Nos itens eu
removo o fundo branco, corto e reduzo, e troco o render 3D pela imagem (o render fica de reserva
para item novo sem ícone pintado). Nas habilidades eu:

- corto e reduzo para 128×128 (`assets/ui/skills/<arquivo>.png`);
- troco o desenho vetorial do `SkillIcon`, do `HordeIcon` e da barra de habilidades pela imagem,
  mantendo a moldura colorida, os pontinhos de nível e o contorno dourado das cartas;
- passivas da Horda e Ecos permanentes usam a mesma imagem (`p_*`);
- deixo o `IconPainter` como reserva caso falte algum arquivo.
