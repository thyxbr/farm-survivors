extends "res://tools/retarget_great_combo.gd"
## Gera scripts/player/knight_moves_great_cast.gd (KnightMovesGreatCast): a Lâmina Suprema (ultimate da montante) tirada
## do "Great Sword Casting" do Mixamo, retargetada para os pivôs do cavaleiro como o combo da montante
## (tools/retarget_great_combo.gd: corpo pelas trilhas, a arma pela trajetória `end`/`dir`/`edge` para o IK das mãos).
##   godot --headless --path . res://tools/retarget_great_casting.tscn -- <great_sword_casting.fbx> [saida.gd]
##
## O clipe tem fases bem separadas (medidas com tools/great_casting_probe.gd): ergue a espada acima da cabeça, segura,
## corta para baixo até se ajoelhar com a lâmina no chão, fica ajoelhado e se levanta. Cada fase vira uma trilha de N
## quadros uniformes, sem a deformação de tempo do combo (g = 1): a habilidade toca cada uma no próprio ritmo
## (GreatswordSupremeConfig) e segura a pose erguida enquanto a aura se forma.

## [início, fim] em segundos do "Great Sword Casting", na ordem de KnightMovesGreatCast.TRACKS.
const PHASES := [
	[0.0, 0.75],    # RAISE: da guarda até a espada acima da cabeça
	[0.75, 1.4],    # HOLD: espada no alto (a aura se forma)
	[1.4, 2.5],     # SLASH: gira a lâmina por trás, passa por cima da cabeça e a crava no chão à frente
	[2.5, 3.45],    # KNEEL: ajoelhado, a lâmina no chão
	[3.45, 4.8],    # RISE: levanta e volta à guarda
]
const SLASH_PHASE := 2


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("uso: -- <great_sword_casting.fbx> [saida.gd]")
		get_tree().quit(1)
		return
	var out: String = args[1] if args.size() > 1 else "res://scripts/player/knight_moves_great_cast.gd"
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": GREAT_WEAPON})
	_r = KnightAnim.rig(m)
	_clip = MixamoClip.new()
	if not _clip.load_fbx(args[0], self):
		get_tree().quit(1)
		return
	_blade_len = (_lk.tip as Node3D).global_position.distance_to((_lk.holder as Node3D).global_position)
	var g0 := _clip.globals(0.0)
	var arm_k: float = (_r.ArmR as Node3D).global_position.distance_to((_r.ElbowR as Node3D).global_position) \
		+ (_r.hand_r as Vector3).length()
	var arm_m := _pt(g0, "RightArm").distance_to(_pt(g0, "RightForeArm")) + _pt(g0, "RightForeArm").distance_to(_palm(g0, "Right"))
	_scale = arm_k / arm_m
	print("escala do braço %.3f, lâmina %.2f m" % [_scale, _blade_len])
	var tracks := []
	for ph in PHASES:
		# acerto no ponto em que g = 1 (sem deformar o tempo da fase)
		var t_hit: float = ph[0] + (ph[1] - ph[0]) * HIT_AT
		var res := _great_track(ph[0], t_hit, ph[1], 180.0)
		tracks.append(res.track)
		print("fase %d: %.2f..%.2f s  mão mais longe do alcance %.2f m" % [tracks.size(), ph[0], ph[1], res.miss])
	_align_edges(tracks)
	_align_turns(tracks)
	var slash: Dictionary = tracks[SLASH_PHASE]
	var tip := _tip(slash, N - 1)
	print("ponta da lâmina no impacto: ", tip)
	_write_cast(out, tracks, tip)
	print("gravado: ", out)
	get_tree().quit()


## _great_track escolhe o lado do gume de cada trilha sozinha (pelo movimento da ponta no "acerto"), o que numa fase
## parada sai ao acaso: o corte manda e as outras fases seguem a vizinha, para o gume não virar 180° na emenda.
func _align_edges(tracks: Array) -> void:
	for k in range(SLASH_PHASE + 1, tracks.size()):
		_flip_if(tracks[k], (tracks[k - 1].edge as Array).back(), 0)
	for k in range(SLASH_PHASE - 1, -1, -1):
		_flip_if(tracks[k], (tracks[k + 1].edge as Array)[0], N - 1)


func _flip_if(tr: Dictionary, ref: Vector3, at: int) -> void:
	if (tr.edge[at] as Vector3).dot(ref) >= 0.0:
		return
	for i in N:
		tr.edge[i] = -(tr.edge[i] as Vector3)


## O giro do quadril e do tronco começa cada trilha em -PI..PI: emenda com a anterior pela volta mais curta.
func _align_turns(tracks: Array) -> void:
	for k in range(1, tracks.size()):
		for j in ["spin", "twist"]:
			var prev: float = (tracks[k - 1][j] as Array).back()
			var off: float = prev + wrapf(float(tracks[k][j][0]) - prev, -PI, PI) - float(tracks[k][j][0])
			for i in N:
				tracks[k][j][i] = float(tracks[k][j][i]) + off


func _write_cast(path: String, tracks: Array, tip: Vector3) -> void:
	var s := "class_name KnightMovesGreatCast\nextends RefCounted\n"
	s += "## GERADO por tools/retarget_great_casting.gd a partir do Mixamo (\"Great Sword Casting\"): não edite à mão, rode\n"
	s += "## a ferramenta de novo. Lâmina Suprema (ultimate da montante) em cinco fases, cada uma com N quadros uniformes\n"
	s += "## (0..1): o corpo como em KnightMovesGreat e a arma (`end`, `dir`, `edge`) no espaço do modelo, para o IK das\n"
	s += "## duas mãos. KnightAnim.great_cast_pose toca uma fase de cada vez.\n\n"
	s += "enum { RAISE, HOLD, SLASH, KNEEL, RISE }\n\n"
	s += "const N := %d\n" % N
	s += "## Duração de cada fase no clipe do Mixamo (s): o ritmo natural, se a habilidade quiser segui-lo.\n"
	var durs := []
	for ph in PHASES:
		durs.append(_f(ph[1] - ph[0]))
	s += "const CLIP_TIME := [%s]\n" % ", ".join(durs)
	s += "## Ponta da lâmina no fim do corte (espaço do modelo): onde a espada bate no chão.\n"
	s += "const IMPACT_TIP := %s\n\n" % _v(tip)
	s += "const TRACKS := [\n"
	for tr in tracks:
		s += "\t{\n"
		for j in tr:
			var vals := []
			for v in tr[j]:
				vals.append(_v(v) if v is Vector3 else _f(v))
			s += "\t\t\"%s\": [%s],\n" % [j, ", ".join(vals)]
		s += "\t},\n"
	s += "]\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()
