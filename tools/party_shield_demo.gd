extends Node
## Demonstração do Grito do Bastião (habilidade 5 da espada com escudo), num personagem descartável
## (user://demo_solo.json, apagado a cada vez: não mexe no save solo).
##   godot --path . res://scenes/world.tscn -- --weapon=iron_sword --rallydemo
## Dá o escudo, sobe para o nível 6 e leva o herói para um descampado fora da vila, com dois aliados parados (réplicas
## de outros jogadores, "do grupo"). No solo o buff vai só para o herói; aqui os aliados mostram o mesmo visual quando
## o herói recebe o buff (como no online, onde o servidor manda o buff para cada um do grupo).
##   5  usa a habilidade      Y  zera a recarga      U  acaba o buff agora (ver a dissipação)

const SPOT := Vector3(-105, 0.3, 36)
const ALLIES := [Vector3(-2.4, 0, 1.6), Vector3(2.6, 0, 1.2)]

var _player: Node
var _allies: Array = []
var _ready_done := false
var _label: Label
var _had := false


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
	while true:
		await get_tree().create_timer(0.5).timeout
		for p in get_tree().get_nodes_in_group("players"):
			if not p.remote:
				_player = p
		if _player != null and Game.char_class != "" and Game.equipment.get("weapon", "") != "":
			break
	await get_tree().create_timer(0.5).timeout
	Econ.test_force_level(maxi(Game.level, int(ItemDB.ABILITIES[PartyShieldRules.ID].level)))
	if Game.count_item("wooden_shield") == 0:
		Game.add_item("wooden_shield")
	Game.equip("wooden_shield")
	await get_tree().create_timer(0.5).timeout
	_player.global_position = SPOT
	_player.velocity = Vector3.ZERO
	var names := ["Aliado 1", "Aliado 2"]
	for i in ALLIES.size():
		var a := Player.new()
		a.remote = true
		get_tree().current_scene.add_child(a)
		a.global_position = SPOT + ALLIES[i]
		a._net_pos = a.global_position
		a.display_name = names[i]
		_allies.append(a)
	_ready_done = true


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	Game.hp = Game.max_hp()
	var has := Game.has_buff(PartyShieldRules.BUFF)
	if has != _had:   # os aliados "do grupo" mostram o mesmo buff que o herói
		_had = has
		for a in _allies:
			if is_instance_valid(a):
				a._vfx_apply({"auras": ["bastiao"] if has else [], "en": "", "lv": 0}, false)
	var cd: float = _player.cooldowns.get(PartyShieldRules.ID, 0.0)
	var left: float = Game.buffs.get(PartyShieldRules.BUFF, 0.0)
	_label.text = "Grito do Bastião — demonstração\n" \
		+ "[5] usar   [Y] zerar recarga   [U] acabar o buff agora\n" \
		+ "recarga: %s   buff: %s\n" % [("%.1f s" % cd) if cd > 0.0 else "pronta", ("%.1f s" % left) if has else "—"] \
		+ "defesa: %.1f" % Game.defense()


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_Y:
			_player.cooldowns[PartyShieldRules.ID] = 0.0
		KEY_U:
			if Game.has_buff(PartyShieldRules.BUFF):
				Game.buffs[PartyShieldRules.BUFF] = 0.05
