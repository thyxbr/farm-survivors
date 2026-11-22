extends "res://tools/retarget_great_combo.gd"
## Gera scripts/player/knight_moves_great_dark.gd (KnightMovesGreatDark): a Dança do Abismo (tecla 3 da montante), o
## combo tirado de quatro clipes do Mixamo, retargetados para os pivôs do cavaleiro como o combo da montante
## (tools/retarget_great_combo.gd: o corpo pelas trilhas, a arma pela trajetória `end`/`dir`/`edge` para o IK das mãos).
##   godot --headless --path . res://tools/retarget_great_dark_combo.tscn -- <slide_attack.fbx> <slash.fbx> <slash_1.fbx> <high_spin.fbx> [saida.gd]
## Na ordem do combo: "Great Sword Slide Attack" (sempre o primeiro), "Great Sword Slash", "Great Sword Slash (1)" e
## "Great Sword High Spin Attack".
##
## Cada clipe vira uma trilha de N quadros uniformes no tempo (sem deformar: g = 1), recortada em [início, fim] (as
## sobras paradas do Mixamo saem; medidas com tools/great_dark_combo_probe.gd). Os clipes andam (o deslize vai 3,3 m à
## frente): o deslocamento do quadril no chão vira a trilha ROOT, na escala da perna do cavaleiro, e a habilidade move o
## herói por ela (o corpo fica no lugar do modelo). A altura do quadril não: o KnightAnim.ground_drop desce o corpo
## pelas pernas dobradas.
## Também imprime a velocidade da ponta da lâmina em cada quadro: os picos são os golpes (GreatswordDarkComboConfig).

## [início, fim] em segundos de cada clipe, na ordem dos argumentos.
const CLIPS := [
	[0.0, 2.0],    # 0 deslize: escorrega de joelho com a lâmina baixa e sobe girando num corte
	[0.0, 1.6],    # 1 corte girando o corpo inteiro
	[0.1, 1.2],    # 2 corte rápido em diagonal
	[0.0, 1.8],    # 3 giro alto: avança girando e fecha num golpe de cima
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < CLIPS.size():
		push_error("uso: -- <slide_attack.fbx> <slash.fbx> <slash_1.fbx> <high_spin.fbx> [saida.gd]")
		get_tree().quit(1)
		return
	var out: String = args[CLIPS.size()] if args.size() > CLIPS.size() else "res://scripts/player/knight_moves_great_dark.gd"
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": GREAT_WEAPON})
	_r = KnightAnim.rig(m)
	_blade_len = (_lk.tip as Node3D).global_position.distance_to((_lk.holder as Node3D).global_position)
	var hip_k: float = (_r.LegL as Node3D).global_position.y
	var tracks := []
	var roots := []
	var times := []
	for c in CLIPS.size():
		_clip = MixamoClip.new()
		if not _clip.load_fbx(args[c], self):
			get_tree().quit(1)
			return
		var g0 := _clip.globals(0.0)
		var arm_k: float = (_r.ArmR as Node3D).global_position.distance_to((_r.ElbowR as Node3D).global_position) \
			+ (_r.hand_r as Vector3).length()
		var arm_m := _pt(g0, "RightArm").distance_to(_pt(g0, "RightForeArm")) + _pt(g0, "RightForeArm").distance_to(_palm(g0, "Right"))
		_scale = arm_k / arm_m
		var t0: float = CLIPS[c][0]
		var t1: float = minf(float(CLIPS[c][1]), _clip.anim.length)
		var hip_m := _pt(g0, "Hips").y
		var res := _great_track(t0, t0 + (t1 - t0) * HIT_AT, t1, 300.0)
		tracks.append(res.track)
		times.append(t1 - t0)
		# deslocamento do quadril no chão, desde o começo do trecho, na escala da perna
		var root := []
		var h0 := _pt(_clip.globals(t0), "Hips")
		for i in N:
			var h := _pt(_clip.globals(t0 + (t1 - t0) * float(i) / float(N - 1)), "Hips") - h0
			root.append(Vector3(h.x, 0.0, h.z) * (hip_k / hip_m))
		roots.append(root)
		print("clipe %d (%s): %.2f..%.2f s  escala do braço %.3f  anda %.2f m  mão mais longe do alcance %.2f m" % [c,
			args[c].get_file(), t0, t1, _scale, (root.back() as Vector3).length(), res.miss])
		var line := "  ponta (m/s):"
		for i in range(1, N):
			var v := (_tip(res.track, i) - _tip(res.track, i - 1)).length() / ((t1 - t0) / float(N - 1))
			line += " %d:%.0f" % [i, v]
		print(line)
	_write_dark(out, tracks, roots, times)
	print("gravado: ", out)
	get_tree().quit()


func _write_dark(path: String, tracks: Array, roots: Array, times: Array) -> void:
	var s := "class_name KnightMovesGreatDark\nextends RefCounted\n"
	s += "## GERADO por tools/retarget_great_dark_combo.gd a partir do Mixamo (\"Great Sword Slide Attack\", \"Great Sword\n"
	s += "## Slash\", \"Great Sword Slash (1)\", \"Great Sword High Spin Attack\"): não edite à mão, rode a ferramenta de novo.\n"
	s += "## Dança do Abismo (tecla 3 da montante): quatro golpes, sempre nesta ordem. Cada trilha tem N quadros uniformes\n"
	s += "## (0..1): o corpo como em KnightMovesGreat e a arma (`end`, `dir`, `edge`) no espaço do modelo, para o IK das duas\n"
	s += "## mãos. ROOT = o quanto o herói anda em cada quadro (espaço do modelo, desde o começo do golpe).\n\n"
	s += "enum { SLIDE, SLASH, SLASH_2, HIGH_SPIN }\n\n"
	s += "const N := %d\n" % N
	s += "## Duração de cada golpe no clipe do Mixamo (s): o ritmo natural.\n"
	var durs := []
	for d in times:
		durs.append(_f(d))
	s += "const CLIP_TIME := [%s]\n\n" % ", ".join(durs)
	s += "const ROOT := [\n"
	for r in roots:
		var vals := []
		for v in r:
			vals.append(_v(v))
		s += "\t[%s],\n" % ", ".join(vals)
	s += "]\n\n"
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
