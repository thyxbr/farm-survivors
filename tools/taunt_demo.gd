extends Node
## Demonstração do Círculo da Provocação Sombria (habilidade 3 da espada com escudo), num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_sword --tauntdemo
## Dá o escudo, sobe para o nível 5, leva o herói para um descampado fora da vila e cerca de goblins (6 perto, dentro
## do círculo, e 2 longe, fora dele). Um aliado parado (réplica de outro jogador) fica perto dos monstros: sem a
## provocação é ele o alvo; provocados, eles largam o aliado e vêm no herói.
##   3  usa a habilidade        T  nova leva de monstros        Y  zera a recarga        a vida enche sozinha

const SPOT := Vector3(-105, 0.3, 40)
const CLOSE := [Vector3(3.5, 0, 1.5), Vector3(-3.0, 0, 2.5), Vector3(1.0, 0, -4.0), Vector3(-4.2, 0, -1.2),
	Vector3(4.0, 0, -2.4), Vector3(-1.2, 0, 4.4)]
const FAR := [Vector3(10.5, 0, 2.0), Vector3(-10.0, 0, -4.0)]

var _player: Node
var _ally: Node
var _mobs: Array = []
var _ready_done := false
var _label: Label


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
	_ally = Player.new()
	_ally.remote = true
	get_tree().current_scene.add_child(_ally)
	_ally.global_position = SPOT + Vector3(5.5, 0, 0.5)
	_ally._net_pos = _ally.global_position
	_ally.display_name = "Aliado"
	await get_tree().create_timer(0.3).timeout
	_spawn_wave()
	_ready_done = true


func _spawn_wave() -> void:
	for e in _mobs:
		if is_instance_valid(e):
			e.queue_free()
	_mobs.clear()
	var base: Vector3 = _player.global_position
	for off in CLOSE + FAR:
		var e := Enemy.new()
		e.kind = "goblin"
		get_tree().current_scene.add_child(e)
		e.global_position = base + off
		e.home = e.global_position
		_mobs.append(e)


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	Game.hp = Game.max_hp()   # o herói não morre na demonstração
	var taunted := 0
	var alive := 0
	for e in _mobs:
		if is_instance_valid(e) and not e.dead:
			alive += 1
			if e.taunt_t > 0.0:
				taunted += 1
	var kit := Game.ability_kit()
	var cd: float = _player.cooldowns.get("sword_taunt", 0.0)
	_label.text = "Círculo da Provocação Sombria — demonstração\n" \
		+ "[3] usar   [T] nova leva de goblins   [Y] zerar recarga\n" \
		+ "habilidade 3: %s   recarga: %s\n" % [ItemDB.ABILITIES[kit[2]].name if kit.size() > 2 else "?", ("%.1f s" % cd) if cd > 0.0 else "pronta"] \
		+ "goblins vivos: %d   provocados: %d" % [alive, taunted]


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_T:
			_spawn_wave()
		KEY_Y:
			_player.cooldowns["sword_taunt"] = 0.0
