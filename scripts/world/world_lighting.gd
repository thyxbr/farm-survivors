class_name WorldLighting
extends RefCounted
## Luz da vila: céu, ambiente, tonemap, sol e contraluz. Fica fora do world.gd e sem autoload para que
## tools/weapon_shot.gd (foto de modelo no Godot) use exatamente a mesma luz do jogo.


static func build(parent: Node) -> void:
	# Guia de estilo (docs/PROMPT_LOWPOLY.md §6): sol quente a ~45°, ambiente frio a 30–40%,
	# contraluz fraca. Tudo barato: uma sombra só (a do sol, 2 cascatas), contraluz sem sombra.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.26, 0.45, 0.8)
	sm.sky_horizon_color = Color(0.7, 0.78, 0.88)
	sm.ground_horizon_color = Color(0.7, 0.78, 0.88)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.25)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64   # céu procedural liso: 64 px bastam e o cubemap sai barato
	env.sky = sky
	# Ambiente: metade vem do céu, metade de um azul-lavanda fixo, e bem mais fraco que o sol,
	# para as faces na sombra ficarem frias e com valor separado das iluminadas.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.56, 0.6, 0.74)
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# ACES dá o contraste e a cor cheia do render "Standard" do Blender; o Filmic lavava
	# as faces claras e o AgX deixava tudo cinza. Exposição abaixo de 1 compensa o ganho do ACES.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	# SSAO curto: escurece só o contato (pé no chão, dobras da armadura), sem manchar a cena.
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.79, 0.86)
	env.fog_density = 0.002
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	# Sol: quente, 45° de altura. Sombra macia por blur (PCF) e não por tamanho angular,
	# que liga o PCSS e custa bem mais. Duas cascatas cobrem a câmera em 3ª pessoa.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_fade_start = 0.85
	parent.add_child(sun)
	# Contraluz: luz fria rasante vinda do lado oposto ao sol, sem sombra (custo quase nulo).
	# Acende a borda das ombreiras, do elmo e da capa e descola o personagem do chão.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 145, 0)
	rim.light_energy = 0.4
	rim.light_color = Color(0.84, 0.88, 1.0)
	rim.light_specular = 0.25
	rim.shadow_enabled = false
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # não desenha um 2º sol no céu
	parent.add_child(rim)
