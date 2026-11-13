# Fase 1 — Fundação (contas, banco, servidor dono do personagem, tabelas) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O servidor passa a ser dono do personagem inteiro (ouro, itens, XP, equipamento, missões, horta), com contas de login e senha via HTTPS, banco SQLite e números de balanceamento em tabelas JSON; o solo offline usa a mesma camada de economia num banco local.

**Architecture:** As regras do personagem saem do autoload `Game` para classes puras (`CharState` + `CharRules`) que recebem as tabelas por injeção. `CharacterService` junta regras + banco + `economy_log`. Um autoload `Econ` roteia: offline chama o serviço local (síncrono, `user://solo.db`); online manda pedido RPC ao servidor, que aplica e devolve o estado completo. O `Game` vira espelho do estado. O servidor Godot também serve HTTP (login/cadastro/health) atrás do HTTPS do Easypanel; o ENet recebe token em vez de nome.

**Tech Stack:** Godot 4.7.2 / GDScript, ENet, GDExtension `godot-sqlite` (2shady4u), `TCPServer` para HTTP, `HMACContext`/`Crypto` para PBKDF2.

**Spec:** `docs/superpowers/specs/2026-11-13-hub-servidor-autoritativo-design.md` (seções 5.1–5.5, 5.7 "o que fica da partida", 6 fase 1)

## Global Constraints

- Godot `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`; código, comentários, mensagens e README em português, no estilo do projeto (comentários `##` explicando o porquê).
- Trabalhar no worktree `C:/Games/godot-3d-hub` (branch nova `fase1-fundacao` a partir de `hub-design`); nunca no checkout principal.
- Senha nunca no UDP, nunca em texto no banco: PBKDF2-HMAC-SHA256, sal aleatório de 16 bytes por conta, **100 000 iterações**, comparação em tempo constante.
- Portas: ENet `GAME_PORT` (7777), HTTP `HTTP_PORT` (8080). Banco do servidor: `--db=PATH` ou env `DB_PATH` (Docker: `/data/valdoria.db`).
- Online: o cliente **nunca** concede a si ouro, itens, XP ou progresso de missão. Toda concessão vem do servidor.
- Offline: a partida roda no PC; ganhos chamam o `CharacterService` local em `user://solo.db` (conta local id 1).
- Saves antigos (`savegame.json`, `colony_character.json`) deixam de ser lidos; sem migração.
- Tabelas de balanceamento em `res://data/balance/*.json`; o servidor semeia o banco com elas na primeira subida e depois usa o banco.
- Subir `application/config/version` para **0.8.0** (o CI exige versão nova).
- Dados de rede vindos do cliente são sempre validados (tipos, ids conhecidos, faixas), como `_clean_look` já faz.
- Os testes existentes continuam passando: smoke (`--smoketest`), colônia (`--colonytest`), `net_test` (com as mudanças da Task 9).

## Review Focus

1. **Clique duplo / pedidos em sequência** (comprar 2× rápido com ouro para 1): o servidor processa em ordem e a segunda compra falha; o cliente termina com o estado do servidor. → teste na Task 8.
2. **Volume ausente no servidor** (`DB_PATH` aponta para pasta que não existe ou sem escrita): o servidor sai com erro claro em vez de criar um banco efêmero. → teste na Task 2.
3. **Mesma conta entrando duas vezes**: a sessão antiga é derrubada, e um `report` atrasado da sessão velha não sobrescreve o estado. → teste na Task 6.
4. **Ida e volta das tabelas**: preço continua `int` (mostra "50", não "50.0"), cores e vetores voltam iguais às constantes originais. → teste na Task 1.
5. **Queda no meio da partida**: o que já foi ganho está gravado (concessão imediata); pegar um item depois de cair é recusado. → teste na Task 10.

---

### Task 1: Executor de testes unitários + tabelas de balanceamento em JSON

**Files:**
- Create: `tests/unit/run.gd` (extends `SceneTree`; acha `tests/unit/test_*.gd`, roda cada método `test_*`, imprime falhas, `quit(1)` se alguma falhar)
- Create: `tests/unit/assert.gd` (`class_name T`: `static func eq(a, b, msg := "")`, `ok(cond, msg := "")` registrando falhas)
- Create: `scripts/balance/balance_tables.gd` (`class_name BalanceTables`)
- Create: `scripts/autoload/balance.gd` (autoload `Balance`, registrado **antes** de `ItemDB` em `project.godot`)
- Create: `data/balance/items.json, crops.json, recipes.json, spells.json, quests.json, shop.json, rarity.json, enemies.json, horde.json, horde_events.json, colony.json, rules.json`
- Create: `tools/export_balance.gd` (script `-s` de uso único que gera os JSON a partir das `const` atuais)
- Modify: `scripts/autoload/item_db.gd`, `scripts/colony/colony_data.gd`, `scripts/survival/upgrades.gd`, `scripts/enemies/enemy.gd` (`TYPES`), `scripts/survival/horde_events.gd`
- Test: `tests/unit/test_balance.gd`

**Interfaces:**
- Produces:
  - `BalanceTables.load_dir(path: String) -> BalanceTables`, `.from_dict(d: Dictionary) -> BalanceTables`, `.to_dict() -> Dictionary`, `.get_table(name: String) -> Dictionary`, `.set_table(name: String, data: Dictionary) -> void`
  - `static func BalanceTables.decode(v: Variant) -> Variant` / `encode(v: Variant) -> Variant`. Codificação: `Color` → `{"$c":[r,g,b,a]}`, `Vector2` → `{"$v2":[x,y]}`, `Vector3` → `{"$v3":[x,y,z]}`. Todo `float` inteiro vindo do JSON vira `int`.
  - Autoload `Balance`: `var tables: BalanceTables`, `signal changed(names: Array)`, `func apply(d: Dictionary) -> void` (troca tabelas e repovoa as `static var`).
  - `rules.json` reúne números soltos hoje espalhados: `sell_ratio` 0.5, `xp_curve` {"base":60,"exp":1.55}, `points_per_level` 3, `farm` {"plots":12,"start":6,"unlock_base":30,"unlock_step":15,"fert_bonus":0.4,"water_mult":2,"bonus_chance":0.12,"seed_back":0.35}.
  - `ItemDB.ITEMS`, `CROPS`, `RECIPES`, `SPELLS`, `QUESTS`, `SHOP_STOCK`, `RARITY` deixam de ser `const` e viram `static var`/`var` com o **mesmo nome**, preenchidas por `Balance`. Idem `ColonyData.BUILDINGS/UNITS/ANIMALS/WAVE_COSTS/...`, `UPG.WEAPONS/PASSIVES/BLESSINGS/COMBOS`, `Enemy.TYPES`, `HordeEvents.EVENTS`. Os demais arquivos não mudam a sintaxe de acesso.

- [ ] **Step 1: Escrever `tools/export_balance.gd`** que lê as `const` atuais e grava os JSON com `BalanceTables.encode` (rodar antes de trocar as `const`). Rodar: `$G --headless --path . -s tools/export_balance.gd` → os 12 arquivos existem.
- [ ] **Step 2: Escrever o teste que falha** `tests/unit/test_balance.gd`:
  - `test_roundtrip_matches_consts`: para cada tabela, `BalanceTables.load_dir("res://data/balance").get_table(n)` é igual (`==` profundo) ao snapshot gerado pelo export (guardar o snapshot em `tests/unit/fixtures/balance_snapshot.res` via `var_to_bytes` no Step 1).
  - `test_ints_stay_int`: `typeof(t.get_table("items")["health_potion"].price) == TYPE_INT`.
  - `test_color_and_vector`: um item com `color` volta como `Color`; um tipo de inimigo com `Vector3` volta como `Vector3`.
- [ ] **Step 3: Rodar** `$G --headless --path . -s tests/unit/run.gd` → FAIL (classe não existe).
- [ ] **Step 4: Implementar** `BalanceTables`, autoload `Balance` (carrega `res://data/balance` no `_ready`) e trocar as `const` pelos `static var` preenchidos.
- [ ] **Step 5: Rodar** unitários → PASS; smoke (`res://scenes/world.tscn -- --smoketest`) e colônia (`res://scenes/colony.tscn -- --colonytest`) → saem com 0.
- [ ] **Step 6: Commit** `Tabelas de balanceamento em JSON (Balance) e executor de testes unitários`.

### Task 2: SQLite, camada `Db` e migrações

**Files:**
- Create: `addons/godot-sqlite/` (vendorizado; **pedir confirmação ao usuário antes de baixar** a release do GitHub `2shady4u/godot-sqlite` compatível com Godot 4.7, com binários Windows e Linux x86_64)
- Create: `scripts/server/db.gd` (`class_name Db`)
- Create: `scripts/server/migrations.gd` (`class_name Migrations`, lista ordenada de SQL)
- Test: `tests/unit/test_db.gd`

**Interfaces:**
- Produces:
  - `Db.open(path: String) -> Db` (null + `push_error` se a pasta não existir ou não aceitar escrita; cria o arquivo se faltar), `close()`
  - `query(sql: String, args: Array = []) -> Array[Dictionary]`, `exec(sql: String, args: Array = []) -> bool`, `last_id() -> int`, `transaction(fn: Callable) -> bool` (BEGIN/COMMIT, ROLLBACK se `fn` retornar false)
  - `Migrations.apply(db: Db) -> int` (versão final; idempotente). Schema v1 = tabelas da spec §5.2 (`accounts, sessions, characters, inventory, passives, base_buildings, base_donations, balance_tables, balance_history, runs, run_players, economy_log, schema_version`). `accounts.username` com `COLLATE NOCASE UNIQUE`. Inventário em tabela própria `inventory(account_id, slot_index, item_id, qty)` para preservar a ordem da mochila.

- [ ] **Step 1: Teste que falha** `test_db.gd`:
  - `test_migrate_fresh`: banco em `user://test_db.db` (apagado antes) → `Migrations.apply` retorna 1; `query("SELECT name FROM sqlite_master WHERE type='table'")` contém as 13 tabelas.
  - `test_migrate_idempotent`: aplicar 2× → mesma versão, sem erro.
  - `test_transaction_rollback`: insert dentro de `transaction` que retorna false → linha não existe.
  - `test_open_missing_dir`: `Db.open("user://nao_existe/x.db") == null` (Review Focus 2).
- [ ] **Step 2: Rodar** unitários → FAIL.
- [ ] **Step 3: Baixar o addon (com o OK do usuário), implementar `Db` e `Migrations`.**
- [ ] **Step 4: Rodar** unitários → PASS. Rodar também `$G --headless --path . --import` → sem erro de GDExtension.
- [ ] **Step 5: Commit** `Banco SQLite (godot-sqlite), camada Db e migrações`.

### Task 3: Contas, senhas e sessões

**Files:**
- Create: `scripts/server/auth/password.gd` (`class_name Password`)
- Create: `scripts/server/auth/account_store.gd` (`class_name AccountStore`)
- Create: `scripts/server/auth/auth_provider.gd` (`class_name AuthProvider`, base) e `password_provider.gd` (`class_name PasswordProvider extends AuthProvider`), `steam_provider.gd` (`class_name SteamProvider extends AuthProvider`, `verify` retorna erro "não suportado")
- Test: `tests/unit/test_auth.gd`

**Interfaces:**
- Consumes: `Db` (Task 2).
- Produces:
  - `Password.hash(pass: String, salt: PackedByteArray, iterations := 100000) -> PackedByteArray`, `Password.new_salt() -> PackedByteArray`, `Password.matches(pass, salt, expected) -> bool` (tempo constante)
  - `AccountStore.new(db: Db, admin_users: PackedStringArray)`
  - `register(username: String, password: String) -> Dictionary` → `{"ok":true,"id":int}` ou `{"ok":false,"err":"nome_invalido"|"senha_curta"|"nome_em_uso"}`. Nome: 3–16 de `[A-Za-z0-9_]`; senha ≥ 8.
  - `login(username, password, ip: String) -> Dictionary` → `{"ok":true,"id","name","token","expires","is_admin"}` ou `{"ok":false,"err":"credenciais"|"muitas_tentativas"}`. Limite: 5 falhas em 300 s por nome **e** por IP. Marca `is_admin` se o nome está em `admin_users`.
  - `resolve_token(token: String) -> Dictionary` → `{"id","name","is_admin"}` ou `{}`. Token: 32 bytes aleatórios em hex; no banco guarda-se só o SHA-256; validade 24 h.
  - `AuthProvider.verify(credentials: Dictionary, ip: String) -> Dictionary` (mesmo formato do `login`).

- [ ] **Step 1: Teste que falha** `test_auth.gd`: `test_register_and_login` (token resolve para o mesmo id); `test_wrong_password`; `test_duplicate_name_case_insensitive` ("Ana" e "ana" → `nome_em_uso`); `test_rate_limit` (6ª tentativa errada → `muitas_tentativas`, mesmo com a senha certa); `test_hash_not_plain` (coluna `pass_hash` ≠ bytes da senha e tem 32 bytes); `test_admin_flag` (`admin_users=["Rique"]` → `is_admin` true); `test_expired_token` (forçar `expires_at` no passado → `{}`); `test_steam_unsupported`.
- [ ] **Step 2: Rodar** → FAIL.
- [ ] **Step 3: Implementar** (PBKDF2 com `HMACContext` em laço; o relógio do limite vem de um `Callable` injetável para o teste).
- [ ] **Step 4: Rodar** → PASS (o teste de hash deve rodar em < 2 s; se não, baixar iterações só no teste via parâmetro).
- [ ] **Step 5: Commit** `Contas com senha (PBKDF2), sessões por token e provedor de login`.

### Task 4: Servidor HTTP de login

**Files:**
- Create: `scripts/server/http/http_request_parser.gd` (`class_name HttpRequestParser`, função pura)
- Create: `scripts/server/http/auth_http.gd` (`class_name AuthHttp extends Node`)
- Modify: `scripts/autoload/network.gd` (`start_server` abre `Db`, aplica migrações, cria `AccountStore` e `AuthHttp`; sai com código 1 se `Db.open` falhar)
- Modify: `Dockerfile` (`ENV HTTP_PORT=8080 DB_PATH=/data/valdoria.db`, `EXPOSE 8080`, `CMD` passa `--http-port` e `--db`; criar `/data` com dono `valdoria`)
- Test: `tests/unit/test_http.gd`

**Interfaces:**
- Consumes: `AccountStore` (Task 3).
- Produces:
  - `HttpRequestParser.parse(buf: PackedByteArray) -> Dictionary` → `{"complete":bool,"method","path","headers":{},"body":String}` ou `{"error":400|413}`; corpo máximo 4096 bytes; exige `Content-Length` para POST.
  - Rotas (JSON): `POST /auth/register {user,pass}` → 201 `{id}` | 400/409 `{err}`; `POST /auth/login {user,pass}` → 200 `{token,expires,name,is_admin}` | 401/429 `{err}`; `POST /auth/steam` → 501; `GET /health` → 200 `{"version": Network.version()}`; outras → 404.
  - IP do cliente: `X-Forwarded-For` (primeiro item) só se o par TCP for IP privado/loopback; senão o IP do par.
  - Conexão fecha após uma resposta; conexões sem pedido completo em 5 s são fechadas.
  - Linha de comando do servidor: `--http-port=N` (padrão env `HTTP_PORT` ou 8080), `--db=PATH` (padrão env `DB_PATH` ou `user://server.db`), `--admins=a,b` (padrão env `ADMIN_USERS`).

- [ ] **Step 1: Teste que falha** `test_http.gd`: pedido completo; pedido em dois pedaços (`complete:false` no 1º); corpo > 4096 → 413; POST sem `Content-Length` → 400.
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar** parser e `AuthHttp` (poll no `_process`).
- [ ] **Step 4: Rodar** unitários → PASS. Teste manual: subir servidor `--server --port=7790 --http-port=8790 --db=user://manual.db` e `curl -s -X POST localhost:8790/auth/register -d '{"user":"Ana","pass":"teste-1234"}'` → 201; `/auth/login` → token; `curl localhost:8790/health` → versão.
- [ ] **Step 5: Commit** `Servidor HTTP de login e cadastro (health para o CI)`.

### Task 5: Regras do personagem em classes puras

**Files:**
- Create: `scripts/character/char_state.gd` (`class_name CharState`)
- Create: `scripts/character/char_rules.gd` (`class_name CharRules`, só `static func`)
- Create: `scripts/character/loot_rules.gd` (`class_name LootRules`: o sorteio que hoje está em `Enemy.drop_loot`, sem criar nós)
- Test: `tests/unit/test_char_rules.gd`

**Interfaces:**
- Consumes: `BalanceTables` (Task 1).
- Produces:
  - `CharState`: campos `level, xp, gold, stat_points, attributes, inventory (Array[{id,qty}]), equipment, quests, flags, farm, hp, mp, world_pos, world_yaw, kills`; `to_dict() -> Dictionary`, `static from_dict(d) -> CharState`, `static new_character(bt: BalanceTables) -> CharState` (valores de `Game.new_game` atual).
  - Toda regra: `static func <op>(s: CharState, bt: BalanceTables, ...) -> Dictionary` retornando `{"ok":bool, "err":String, "events":Array}`; muta `s` só se ok. Eventos: `{"t":"notify","text","color"}`, `{"t":"level_up","level"}`, `{"t":"looted","id","qty"}`, `{"t":"quest"}`, `{"t":"farm"}`.
  - Ops (portadas do `game.gd` atual, mesma lógica e textos): `grant(s,bt,gold,xp,items:Dictionary)`, `kill(s,bt,kind,xp)` (XP + progresso de missão + `kills`), `buy(s,bt,id)` (só ids em `SHOP_STOCK` ou sementes de `CROPS`), `sell(s,bt,id)`, `equip(s,bt,id)`, `unequip(s,bt,slot)`, `consume(s,bt,id)` (tira 1 de poção/comida/colheita; a cura e o buff ficam no cliente), `cook(s,bt,recipe,times)`, `spend_point(s,bt,attr)`, `start_quest(s,bt,id)` (só se `none` e a anterior da cadeia `done`), `complete_quest(s,bt,id)` (só se `ready`), `sort_inventory(s,bt)`, `unlock_plot`, `plant(s,bt,i,crop,buy_missing,now)`, `water(s,bt,i,now)`, `fertilize(s,bt,i,now)`, `harvest(s,bt,i,now,rng)`.
  - Horta por relógio: cada canteiro guarda `growth` e `t` (unix s da última atualização); `static func farm_growth(p, bt, now) -> float` = `min(1, growth + (now - t) / time * (water_mult se regado))`. O cliente usa a mesma função para desenhar.
  - `LootRules.roll(bt, kind: String, rng: RandomNumberGenerator) -> Dictionary` → `{"gold":int, "items":{id:qty}}`.
  - Aleatoriedade sempre via `RandomNumberGenerator` passado como parâmetro (testes com seed fixa).

- [ ] **Step 1: Teste que falha** `test_char_rules.gd` (um teste por op; exemplos que fixam valores):
  - `test_buy_and_sell`: ouro 100, comprar `health_potion` (preço da tabela) → ouro 100−preço, 1 poção; vender → ouro + `ceil(preço*0.5)`.
  - `test_buy_not_in_shop`: comprar um item lendário → `err == "nao_vende"`, estado igual.
  - `test_buy_double_without_gold` (Review Focus 1): ouro = preço; duas compras seguidas → 1ª ok, 2ª `ouro_insuficiente`.
  - `test_equip_offhand_needs_class`, `test_equip_swaps_back_to_bag`, `test_weapon_change_returns_offhand`.
  - `test_kill_levels_up`: XP para o nível 2 = 60 → `kill(...,60)` → nível 2, 3 pontos, evento `level_up`.
  - `test_quest_flow`: start → kills até `count` → estado `ready` → complete dá ouro/itens/XP da tabela; `complete` antes de `ready` falha.
  - `test_farm_clock`: plantar em `now=1000`; em `now=1000+time/2` sem regar `growth≈0.5`; regado ≈1.0; colher antes de pronto falha.
  - `test_cook`: ingredientes insuficientes falham; com o dobro, `times=2` produz 2.
  - `test_loot_roll_deterministic`: mesma seed → mesmo resultado.
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar.** **Step 4: Rodar** → PASS.
- [ ] **Step 5: Commit** `Regras do personagem em classes puras (CharState, CharRules, LootRules)`.

### Task 6: `CharacterService` (regras + banco + registro da economia)

**Files:**
- Create: `scripts/character/character_service.gd` (`class_name CharacterService`)
- Test: `tests/unit/test_character_service.gd`

**Interfaces:**
- Consumes: `Db`, `CharState`, `CharRules`, `LootRules`, `BalanceTables`.
- Produces:
  - `CharacterService.new(db: Db, bt: BalanceTables, clock: Callable = Time.get_unix_time_from_system)`
  - `load_or_create(account_id: int) -> CharState` (cache em memória por conta)
  - `CLIENT_OPS := ["buy","sell","equip","unequip","consume","cook","spend_point","start_quest","complete_quest","sort_inventory","unlock_plot","plant","water","fertilize","harvest"]`
  - `apply(account_id: int, op: String, args: Array) -> Dictionary` → `{"ok","err","events","state": CharState.to_dict()}`; recusa op fora de `CLIENT_OPS` (`err "op_invalida"`) e argumentos de tipo errado (`err "args"`); grava em transação; cada op bem-sucedida que muda ouro/itens gera uma linha em `economy_log(kind=op, amount, item_id, source="player")`.
  - `grant(account_id, gold: int, xp: int, items: Dictionary, source: String) -> Dictionary` e `kill(account_id, kind: String, xp: int) -> Dictionary` (só o servidor/solo chama; `source` ex.: `"loot"`, `"quest"`, `"horde_run"`, `"city_night"`).
  - `report(account_id, session_id: int, hp: float, mp: float, pos: Vector3, yaw: float) -> void` — ignora se `session_id` não for a sessão atual da conta (Review Focus 3); clampa hp/mp em [0, 10000].
  - `set_session(account_id, session_id: int)`, `unload(account_id)` (grava e tira do cache).
  - `run_summary(account_id, mode: String, gold: int, xp: int, items: Dictionary)` grava **uma** linha `economy_log(kind="run", source=mode)`; as concessões durante a partida usam `grant(..., source="horde_run"|"city_night")` sem log por moeda.

- [ ] **Step 1: Teste que falha**: `test_persists_across_instances` (comprar, fechar, abrir novo serviço no mesmo arquivo → mesmo estado); `test_rejects_unknown_op` (`"grant"` via `apply` → `op_invalida`); `test_rejects_bad_args` (`buy` com `[123]`); `test_economy_log_rows` (compra → 1 linha com `item_id`); `test_stale_session_report_ignored`; `test_grant_logs_source`.
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar.** **Step 4: Rodar** → PASS.
- [ ] **Step 5: Commit** `CharacterService: personagem no banco com registro da economia`.

### Task 7: Login no cliente e token no ENet

**Files:**
- Create: `scripts/autoload/auth.gd` (autoload `Auth`, cliente)
- Modify: `scripts/autoload/network.gd` (`_register` recebe token; `join` passa a receber token; uma sessão por conta; nome = nome da conta)
- Modify: `scripts/ui/main_menu.gd` (painel *Jogar online*: usuário, senha, endereço; botões *Entrar* e *Criar conta*; lembra usuário e endereço, nunca a senha)
- Test: `tests/net_test.gd` (login antes de conectar)

**Interfaces:**
- Consumes: rotas da Task 4, `AccountStore.resolve_token`, `CharacterService.set_session/unload`.
- Produces:
  - `Auth.base_url(address: String) -> String`: `--auth-url=` tem prioridade; host IP literal ou `localhost` → `http://host:8080`; senão `https://host`. A porta do endereço vale só para o UDP.
  - `Auth.register(address, user, pass) -> Dictionary` e `Auth.login(address, user, pass) -> Dictionary` (com `await`, via `HTTPRequest`; mesmos `{ok, err, ...}` das rotas; mensagens em português para cada `err`).
  - `Network.join(address: String, token: String) -> void`. `_register(token: String, client_version: String, look = {}, _extra = "")` — **mesma quantidade de argumentos** (o comentário existente explica por quê); a checagem de versão continua antes do token. Token inválido → `_rejected("Sessão expirada. Entre de novo.")`.
  - `players[id]` ganha `"account": int`. Conta já conectada em outro peer → o peer antigo é desconectado antes de aceitar o novo; `CharacterService.set_session(account, id)`.
  - `net_test`: `--name=Ana` vira usuário; senha fixa `teste-1234`; registra (ignora 409) e loga; `--auth-url=http://127.0.0.1:<http>` vem da linha de comando.

- [ ] **Step 1: Mudar `net_test.gd`** para logar antes de conectar e adicionar a checagem `test_second_login_kicks_first` (com `--peers=2`, Beto conecta uma segunda vez com o mesmo token e espera que a primeira conexão caia). Rodar servidor + 2 clientes (comandos do README com `--http-port=8790 --db=user://nettest.db` no servidor e `--auth-url=http://127.0.0.1:8790` nos clientes) → FAIL.
- [ ] **Step 2: Implementar** `Auth`, `_register` com token, painel do menu.
- [ ] **Step 3: Rodar** o `net_test` → os dois clientes saem com 0. Abrir o jogo, criar conta pelo menu contra um servidor local → chega ao salão.
- [ ] **Step 4: Commit** `Login e cadastro no menu; o ENet entra com token de sessão`.

### Task 8: `Econ` e o `Game` como espelho (offline e online)

**Files:**
- Create: `scripts/autoload/econ.gd` (autoload `Econ`, registrado depois de `Network`)
- Modify: `scripts/autoload/game.gd` (mutadores roteiam por `Econ`; `apply_state(d: Dictionary)` + `apply_events(ev: Array)`; somem `save_game/load_game/_read_save` e o JSON do personagem)
- Modify: UIs que chamam mutadores e usam o retorno `bool` (`shop_ui.gd`, `game_menu.gd`, `char_preview.gd`, `cooking_ui.gd`, `plant_ui.gd`, `hud.gd`, `world.gd`, `farm_plot.gd`, `kitchen.gd`, `npc.gd`)
- Modify: `tests/smoke_test.gd` (save/load vira persistência do `solo.db`), `tests/net_test.gd`

**Interfaces:**
- Consumes: `CharacterService` (Task 6), `Network` (Task 7).
- Produces:
  - `Econ.request(op: String, args: Array) -> void`. Offline: chama `CharacterService.apply(1, op, args)` local na hora e entrega o resultado. Online: RPC `_econ_req(seq: int, op, args)` ao servidor; resposta `_econ_res(seq, ok, err, events, state)`.
  - `signal Econ.result(op: String, ok: bool, err: String)` (as UIs que precisam do resultado escutam isto em vez do `bool` de retorno).
  - `Econ.grant(gold, xp, items, source)` e `Econ.kill(kind, xp)`: **só offline** (no cliente online fazem `push_error("concessão no cliente online: %s")` e não fazem nada — esse erro serve para achar chamadas esquecidas).
  - Servidor: `_econ_req` resolve `players[sender].account`, chama `CharacterService.apply`, responde só ao remetente. Pedidos do mesmo peer são processados na ordem de chegada (RPC confiável já ordena).
  - Na aceitação (`_accepted`), o servidor envia `_balance(tables: Dictionary)` (via `Balance.tables.to_dict()` codificado) e `_econ_res(0, true, "", [], state)` com o estado inicial; o cliente aplica antes de trocar de cena.
  - Solo: `Econ` abre `user://solo.db` (ou `--solo-db=PATH`, usado pelo smoke test com arquivo apagado no início) na primeira vez que o jogo começa offline. "Novo jogo" no menu apaga o personagem local (pergunta antes).
  - `Game.gold/inventory/...` continuam existindo e com os mesmos sinais (`stats_changed`, `inventory_changed`, `quests_changed`, `farm_changed`, `leveled_up`, `item_looted`), emitidos por `apply_state/apply_events`.
  - Cura de poção/comida e buffs: o cliente aplica **depois** de `Econ.result("consume", true)`; a checagem "vida já está cheia" continua no cliente antes de pedir.
  - Vida/mana/posição: `Econ.report_vitals()` a cada `autosave_interval` e ao trocar de zona (RPC `_econ_report(hp, mp, pos, yaw)`; offline grava direto). F5 offline = `report_vitals` + aviso "Jogo salvo"; F9 offline recarrega do `solo.db`. No online, F5/F9 não fazem nada.

- [ ] **Step 1: Testes que falham**: no `net_test` (Ana): comprar 1 poção com ouro de teste concedido pelo servidor (`--grant-test-gold` só aceito quando o servidor roda com `--test`); `test_double_buy` (Review Focus 1: duas `request("buy")` seguidas com ouro para uma → no fim 1 poção e ouro certo); `test_forged_op` (enviar `_econ_req(…, "grant", …)` direto → resposta `op_invalida`, ouro igual); `test_reconnect_keeps_state` (sair e entrar de novo → mesmo inventário). No smoke test: depois de comprar/equipar, recriar o serviço local e conferir o mesmo estado.
- [ ] **Step 2: Rodar** smoke e `net_test` → FAIL.
- [ ] **Step 3: Implementar** `Econ`, trocar os mutadores do `Game` e ajustar as UIs.
- [ ] **Step 4: Rodar** unitários, smoke, colônia e `net_test` → todos saem com 0.
- [ ] **Step 5: Commit** `Personagem pelo Econ: servidor dono no online, serviço local no solo`.

### Task 9: Ganhos vindos do servidor (inimigos, loot, Horda, cidade)

**Files:**
- Create: `scripts/server/pickups.gd` (`class_name PickupRegistry`)
- Modify: `scripts/autoload/network.gd` (`server_enemy_killed` → `CharacterService.kill` + loot pelo registro; `_kill_reward` vira só aviso/efeito)
- Modify: `scripts/enemies/enemy.gd` (`_die` offline → `Econ.kill` + `LootRules` + nós de pickup; `drop_loot` usa `LootRules.roll`)
- Modify: `scripts/world/pickup.gd` (pickup com `net_id`: online pede `Econ.request("claim_pickup", [net_id])`; offline `Econ.grant`)
- Modify: `scripts/survival/survival_mode.gd` (role "server" concede ouro, itens e sementes por jogador via `CharacterService.grant(..., "horde_run")`; role "client" para de chamar `Game.add_*`; moedas e itens no chão da Horda online passam pelo `PickupRegistry`)
- Modify: `scripts/autoload/lobby.gd` (`_city_reward`: o servidor concede antes de avisar; o cliente só mostra)
- Modify: `scripts/character/character_service.gd` (op `claim_pickup` fica **fora** de `CLIENT_OPS`; o servidor trata a RPC própria `_claim_pickup(net_id)`)
- Test: `tests/unit/test_pickups.gd`, `tests/net_test.gd`

**Interfaces:**
- Consumes: `CharacterService.grant/kill`, `LootRules.roll`.
- Produces:
  - `PickupRegistry.spawn(owner: int, zone: String, pos: Vector3, gold: int, items: Dictionary, ttl := 120.0) -> int` (net_id); `claim(net_id, peer: int, peer_pos: Vector3) -> Dictionary` → `{"ok","gold","items"}` ou `{"ok":false,"err":"dono"|"pego"|"expirou"|"longe"}` (distância máxima 4 m da última posição recebida em `_apply_remote_state`); `drop_peer(peer)` remove os pickups do peer.
  - RPC servidor→dono `_pickup_spawned(net_id, gold, items, pos)`; cliente→servidor `_claim_pickup(net_id)`; o servidor responde com `_econ_res` (estado novo + evento `looted`).
  - Loot é por jogador que acertou (como hoje: `e.contributors`), cada um com seu sorteio.

- [ ] **Step 1: Teste que falha** `test_pickups.gd`: dono errado, pego duas vezes, expirado (relógio injetado), longe (5 m) → cada um com seu `err`; caso ok devolve o conteúdo. No `net_test` (Ana): matar um slime → XP do personagem sobe **no servidor** (conferido pelo estado recebido), pickup aparece e, ao pegar, ouro/itens sobem; o `push_error` "concessão no cliente online" não aparece na saída (o teste falha se aparecer).
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar.** **Step 4: Rodar** unitários, smoke, `net_test` com `--horde=lead|join` e com `--city=lead|join` → todos saem com 0.
- [ ] **Step 5: Commit** `Loot, XP e recompensas concedidos pelo servidor`.

### Task 10: Caixa da Defesa separado, queda no meio da partida

**Files:**
- Modify: `scripts/colony/colony.gd`, `scripts/colony/colony_world.gd`, `scripts/ui/colony_hud.gd`, `scripts/ui/colony_ui.gd` (o ouro da cidade vira `colony.treasury`; nada escreve em `Game.gold`; some o `colony_character.json`)
- Modify: `scripts/autoload/game.gd` (`start_colony` não salva/restaura mais o personagem)
- Modify: `tests/colony_test.gd`, `tests/net_test.gd`

**Interfaces:**
- Consumes: `Econ`, `CharacterService.run_summary`, `PickupRegistry.drop_peer`.
- Produces:
  - `Colony.treasury: int` (início `START_GOLD` solo, `COOP_START_GOLD + COOP_GOLD_PER_PLAYER*n` em grupo, valores de `colony.json`).
  - Ao fim de uma partida (Horda ou Defesa, online e offline), `CharacterService.run_summary` grava a linha de resumo (Spec §5.7).
  - Queda: `Network._on_peer_disconnected` chama `CharacterService.unload(account)` e `PickupRegistry.drop_peer(peer)`.

- [ ] **Step 1: Testes que falham**: `colony_test`: ouro do personagem antes == depois de uma partida solo com construções (só muda pelas recompensas por noite). `net_test --city=join`: Beto cai no meio da noite 1 e volta → recompensas da noite já concedidas continuam no estado; um `_claim_pickup` de um pickup antigo dele → `err` (Review Focus 5).
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar.** **Step 4: Rodar** colônia e `net_test --city=lead|join` → 0.
- [ ] **Step 5: Commit** `Defesa com caixa próprio da partida; resumo por partida na economia`.

### Task 11: Deploy, CI, documentação e versão

**Files:**
- Modify: `.github/workflows/deploy.yml` (servidor de teste com `--http-port` e `--db` temporário; clientes com `--auth-url`; o job *Conferir servidor publicado* passa a fazer `GET https://<domínio>/health` e comparar `version`)
- Modify: `README.md` (seções Multiplayer, Salão, testes; Easypanel: **Mounts → volume em `/data`**, domínio com proxy para a porta **8080**, envs `DB_PATH`, `HTTP_PORT`, `ADMIN_USERS`), `.claude/skills/smoke-check/SKILL.md` (comandos novos)
- Modify: `project.godot` (`application/config/version="0.8.0"`)

- [ ] **Step 1: Atualizar CI, README e skill.**
- [ ] **Step 2: Rodar localmente a sequência do CI** (import, unitários, smoke, colônia, `net_test` com horda e cidade) usando a skill `smoke-check` → todos PASSOU.
- [ ] **Step 3: `docker build -t valdoria-server .`** (se o Docker estiver disponível) e `docker run -v valdoria-data:/data -p 7777:7777/udp -p 8080:8080` → `/health` responde a versão 0.8.0; derrubar e subir de novo o container com o mesmo volume → uma conta criada antes continua logando. (A imagem cria `/data` com dono `valdoria` para que o volume nomeado herde a permissão.)
- [ ] **Step 4: Commit** `Versão 0.8.0: deploy com HTTP e volume do banco; README e CI`.
