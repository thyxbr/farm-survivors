extends Node
## Demonstração do Martelo de Energia (habilidade 4 da espada com escudo), num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_sword --hammerdemo
## Dá o escudo, sobe para o nível 5, leva o herói para um descampado fora da vila e põe goblins à frente (dentro do
## raio do golpe) e alguns mais longe (fora dele), para ver o choque com o chão: onda de choque da sprite sheet,
## rachaduras projetadas, detritos/brasas/fumaça, tremor da câmera e o hitstop.
##   4  usa a habilidade   T  nova leva de goblins   Y  zera a recarga   L  câmera lenta (liga/desliga)
## A vida enche sozinha e a recarga zera sozinha depois de cada golpe.

const SPOT := Vector3(-105, 0.3, 40)
const ID := "sword_hammer"

var _player: Node
var _mobs: Array = []
var _ready_done := false
var _label: Label
var _slow := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 120)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.text = "Preparando a demonstração..."
	layer.add_child(_label)
	_setup()


func _setup() -> void:
	# espera o mundo e o jogador local
	while true:
		await get_tree().create_timer(0.5).timeout
		for p in get_tree().get_nodes_in_group("players"):
			if not p.remote:
				_player = p
		if _player != null and Game.char_class != "" and Game.equipment.get("weapon", "") != "":
			break
	await get_tree().create_timer(0.5).timeout
	Econ.test_force_level(maxi(Game.level, 5))
	if Game.count_item("wooden_shield") == 0:
		Game.add_item("wooden_shield")
	Game.equip("wooden_shield")
	await get_tree().create_timer(0.5).timeout
	_player.global_position = SPOT
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	_spawn_wave()
	_ready_done = true


## Goblins em volta do ponto onde o martelo cai (à frente do herói): os de perto dentro do raio, dois fora dele.
func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var cfg: HammerConfig = HammerAbilities.CONFIG
	var f: Vector3 = _player.facing()
	var center: Vector3 = _player.global_position + f * cfg.forward_offset
	var offs := []
	for i in 7:
		var a := TAU * i / 7.0
		offs.append(Vector3(cos(a), 0, sin(a)) * cfg.radius * (0.4 if i % 2 == 0 else 0.75))
	offs.append(Vector3(cfg.radius + 4.0, 0, 0))
	offs.append(Vector3(-cfg.radius - 4.0, 0, 1.0))
	for off in offs:
		var e := Enemy.new()
		e.kind = "goblin"
		get_tree().current_scene.add_child(e)
		e.global_position = center + off
		e.home = e.global_position
		_mobs.append(e)


func _process(_delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	Game.hp = Game.max_hp()   # o herói não morre na demonstração
	# depois do golpe a recarga zera sozinha (dá para repetir logo)
	if _player.ability != ID and float(_player.cooldowns.get(ID, 0.0)) > 0.0:
		_player.cooldowns[ID] = 0.0
	# câmera lenta: reaplica depois que o hitstop devolve o tempo normal
	if _slow and not FXEpic._hs_active:
		Engine.time_scale = 0.3
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
	var kit := Game.ability_kit()
	_label.text = "Martelo de Energia — demonstração\n" \
		+ "[4] usar   [T] nova leva de goblins   [Y] zerar recarga   [L] câmera lenta: %s\n" % ("LIGADA" if _slow else "desligada") \
		+ "habilidade 4: %s\n" % (ItemDB.ABILITIES[kit[3]].name if kit.size() > 3 else "?") \
		+ "goblins vivos: %d" % alive


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn_wave()
		KEY_Y:
			_player.cooldowns[ID] = 0.0
		KEY_L:
			_slow = not _slow
			if not _slow and not FXEpic._hs_active:
				Engine.time_scale = 1.0
