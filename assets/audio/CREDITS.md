# Créditos de áudio

Todos os sons e músicas vêm do [OpenGameArt.org](https://opengameart.org). Os marcados **CC-BY** exigem
crédito, que também aparece no jogo em *Menu principal → Créditos* (`scripts/ui/credits_panel.gd`;
mantenha as duas listas iguais). **CC0** é domínio público.

Alterações feitas: conversão de formato (OGG para música e ambiente, WAV mono para efeitos), volume nivelado
(música em -20 LUFS, com agudos acima de 6 kHz suavizados), cortes de duração, mistura de camadas em alguns
efeitos e renomeação para o uso no jogo.

## Música

| Arquivo | Obra | Autor | Licença |
|---|---|---|---|
| `music/menu_asamis_journey` | "Asami's Journey" (main loop A), de [Contemplative Fantasy Vol. 2](https://opengameart.org/node/177224) | YannZ | CC-BY 4.0 |
| `music/hub_town_theme` | [Town Theme RPG](https://opengameart.org/content/town-theme-rpg) | cynicmusic | CC0 |
| `music/village_squirrel_village` | [Squirrel Village](https://opengameart.org/content/squirrel-village) (loop) | SoManyWhales | CC-BY 4.0 |
| `music/village_deck_the_halls` | [Deck the Halls - Christmas Song](https://opengameart.org/content/deck-the-halls-christmas-song-203) (música da vila no evento de Natal) | Dizzy Crow (Daniel Michel) | CC-BY 4.0 |
| `music/village_morning_frost` | [Morning Frost & Cheerful Christmas Time](https://opengameart.org/content/morning-frost-cheerful-christmas-time-jonathan-shaw-tarush-singhal) (guardada, ainda sem uso): mixagem de glitchart sobre ["Morning Frost"](https://opengameart.org/content/morning-frost-rpg-orchestral-essentials-village-music), de Jonathan Shaw (www.jshaw.co.uk, CC-BY 3.0), e [Cheerful Christmas Time](https://opengameart.org/content/cheerful-christmas-time), de Tarush Singhal (CC0) | glitchart, Jonathan Shaw, Tarush Singhal | CC-BY 3.0 |
| `music/wild_greenland_theme` | "Greenland Theme", de [Heroes 3 type music](https://opengameart.org/content/heroes-3-type-music) | Alexandr Zhelanov | CC-BY 4.0 |
| `music/ruins_dark_cavern` | [Dark Cavern Ambient](https://opengameart.org/content/dark-cavern-ambient) | Paul Wortmann | CC0 |
| `music/combat_battle_theme_3` | "Battle Theme 3", de [Battle themes](https://opengameart.org/node/76534) | Alexandr Zhelanov | CC-BY 4.0 |
| `music/swamp_whispering_marsh` | Tema do Pântano Sussurrante, composto para o jogo e tocado com o banco MuseScore General (`tools/audio/gen_music.py`) | Ecos de Valdoria | própria |
| `music/volcano_ash_crown` | Tema do Vulcão das Cinzas, composto para o jogo e tocado com o banco MuseScore General (`tools/audio/gen_music.py`) | Ecos de Valdoria | própria |
| `sfx/level_up_fanfare` | Fanfarra da subida de nível, composta para o jogo e tocada com o banco MuseScore General (`tools/audio/gen_levelup.py`) | Ecos de Valdoria | própria |
| `music/boss_blackmoor_colossus` | "Blackmoor Colossus" (loop sem vocais), de [Colossal Boss Battle Theme](https://opengameart.org/content/colossal-boss-battle-theme) | Matthew Pablo — www.matthewpablo.com | CC-BY 3.0 |

## Efeitos

| Arquivos | Obra | Autor | Licença |
|---|---|---|---|
| `sword_swing*`, `arcane_*`, `fire_*`, `frost_cast/hit`, `bow_draw/shot`, `arrow_hit`, `heal`, `portal`, `explode_2..4` | [Fantasy SFX Pack Vol 1](https://opengameart.org/content/jc-sounds-fantasy-sfx-pack-vol-1) | JC Sounds | CC-BY 4.0 |
| `staff_wind`, `explode_1`, `zap`, `slam`, `death`, `levelup` | [8 Magic Attacks](https://opengameart.org/content/8-magic-attacks) | leohpaz | CC-BY 4.0 |
| `mace_swing_1.mp3` | golpe de maça gerado no ElevenLabs (referência enviada pelo usuário) | — | gerado para o projeto |
| `sword_hit_flesh`, `sword_hit_heavy` | [Fleshy Fight Sounds](https://opengameart.org/content/fleshy-fight-sounds) | will_leamon | OGA-BY 3.0 |
| `sword_hit`, `chop_wood_1` | [50 RPG sound effects](https://opengameart.org/content/50-rpg-sound-effects) | Kenney (www.kenney.nl) | CC0 |
| `chop_wood_2`, `chop_stone` | [Impact](https://opengameart.org/content/impact) | qubodup | CC0 |
| `hit`, `sword_hit_heavy` (camada) | [Thwack Sounds](https://opengameart.org/content/thwack-sounds) | AntumDeluge | CC0 |
| `frost_nova`, `quest` | [Magic SFX Sample](https://opengameart.org/content/magic-sfx-sample) | ViRiX | CC-BY 3.0 |
| `swing`, `dodge`, `hurt`, `pickup` (também usado para o ouro), `click`, `error`, `slime`, `bow_full`, `anvil`, `death` (camada), `staff_wind_2` (camada) | [RPG Sound Pack](https://opengameart.org/content/rpg-sound-pack) | artisticdude | CC0 |
| `gem`, `enemy_die` | [80 CC0 RPG SFX](https://opengameart.org/content/80-cc0-rpg-sfx) | rubberduck | CC0 |

Os sons `bloop`, `plant`, `water`, `harvest`, `cook` e `eat` (horta e cozinha) seguem sintetizados por código
em `scripts/autoload/sfx.gd`.

## Ambiente

| Arquivo | Obra | Autor | Licença |
|---|---|---|---|
| `ambience/birds_wind` | [Birds and Wind - Ambient](https://opengameart.org/content/birds-and-wind-ambient-birds-wind-and-synth) | Spring Spring | CC0 |
| `ambience/crickets_night` | [Crickets Ambient Noise - loopable](https://opengameart.org/content/crickets-ambient-noise-loopable) | Wolfgang_ | CC0 |
| `ambience/fire_crackle` | [Fireplace Sound loop](https://opengameart.org/content/fireplace-sound-loop) | PagDev | CC0 |

Os ambientes `rain` (chuva), `swamp` (Pântano Sussurrante), `ice` (Geleira de Cristal), `lava` (Vulcão das
Cinzas) e `cave` (dungeons) foram sintetizados para o jogo, sem amostras de terceiros, por
`tools/audio/gen_ambience.py` (rode de novo para regerar).

## Banco de sons das músicas compostas

As duas músicas compostas para o jogo (`swamp_whispering_marsh` e `volcano_ash_crown`) são tocadas com o
**MuseScore_General.sf2** (licença MIT). Avisos que a licença pede para manter:

- FluidR3 (versão original) por Frank Wen, Copyright (c) 2000-02
- Conversão mono (FluidR3Mono) por Michael Cowgill, Copyright (c) 2014-17
- Adaptação para MuseScore_General.sf2 por S. Christian Collins, Copyright (c) 2018-19
- Temple Blocks por Ethan Winer, Copyright (c) 2002
- Drumline Cymbals por Michael Schorsch, Copyright (c) 2016
