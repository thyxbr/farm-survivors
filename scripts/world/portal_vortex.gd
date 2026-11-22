class_name PortalVortex
extends Node3D
## Portal redondo de dungeon: um redemoinho de luz no meio (espiral girando, branco no centro, na cor `color`
## em volta), cercado por um anel de nuvem escura que gira mais devagar, e raios que estalam na borda da nuvem.
## Fica de pé no plano XY do nó (olha para +Z e -Z), com o centro na origem; `radius` = raio da nuvem (m).
## Só visual: quem monta não cria isto no servidor (headless).

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.6, 0.45, 1.0, 1.0);
uniform vec4 cloud : source_color = vec4(0.16, 0.12, 0.26, 1.0);
uniform float spin = 1.0;
uniform float seed = 0.0;
uniform float open = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv) / max(open, 0.001);
	float a = atan(uv.y, uv.x);
	float t = TIME * spin;
	// redemoinho: o ângulo torce mais perto do centro (espiral) e gira
	float sw = a + 3.2 / (r + 0.3) - t * 1.8;
	vec2 p = vec2(cos(sw), sin(sw)) * (0.6 + r * 3.5);
	float streak = fbm(p + vec2(seed));
	float arms = 0.5 + 0.5 * sin(sw * 3.0 + streak * 5.0);
	float core = smoothstep(0.6, 0.0, r);
	float v = core * (0.25 + 0.95 * arms * streak) + smoothstep(0.16, 0.0, r) * 0.8;
	vec3 col = mix(tint.rgb * 0.55, vec3(1.0), smoothstep(0.7, 1.25, v)) * (0.55 + 1.1 * v);
	float a_core = smoothstep(0.6, 0.42, r);
	// anel de nuvem: fumaça escura girando devagar, borda rasgada
	float ca = a - t * 0.4;
	vec2 cp = vec2(cos(ca), sin(ca)) * (0.8 + r * 2.4) + vec2(seed * 0.37, 0.0);
	float cn = fbm(cp * 1.4 + vec2(0.0, t * 0.15));
	float edge = r + (cn - 0.5) * 0.42;
	float ring = smoothstep(0.34, 0.5, r) * smoothstep(1.0, 0.7, edge);
	vec3 ccol = cloud.rgb * (0.35 + 1.3 * cn);
	ccol += tint.rgb * smoothstep(0.68, 0.45, r) * 0.8;     // a luz do miolo acende a beira da nuvem
	ccol += tint.rgb * pow(cn, 3.0) * 0.6;                  // fiapos claros
	float a_ring = ring * smoothstep(0.25, 0.45, cn + 0.1);
	ALBEDO = mix(ccol, col, a_core);
	ALPHA = clamp(max(a_core, a_ring), 0.0, 1.0);
}
"""

@export var color := Color(0.6, 0.4, 1.0)
@export var radius := 2.6

var _mats: Array[ShaderMaterial] = []
var _bolts: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _bolt_t := 0.0
var _light: OmniLight3D
var _t := 0.0
var _open := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var sh := Shader.new()
	sh.code = SHADER
	# duas camadas um pouco afastadas, girando em ritmos diferentes: de lado não vira uma folha
	for i in 2:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("cloud", (color * 0.35).lerp(Color(0.07, 0.05, 0.1), 0.45))
		m.set_shader_parameter("spin", 1.0 if i == 0 else -0.7)
		m.set_shader_parameter("seed", _rng.randf() * 50.0)
		m.render_priority = i
		var q := QuadMesh.new()
		q.size = Vector2.ONE * radius * 2.0 * (1.0 if i == 0 else 0.9)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position.z = -0.12 * i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mats.append(m)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.albedo_color = color.lerp(Color.WHITE, 0.45)
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolts = MeshInstance3D.new()
	_bolts.mesh = ImmediateMesh.new()
	_bolts.material_override = _bolt_mat
	_bolts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolts.position.z = 0.06
	add_child(_bolts)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.2
	_light.omni_range = radius * 3.2
	_light.position = Vector3(0, 0, 0.8)
	add_child(_light)


## Abre crescendo do nada (o portal do chefe quando ele cai).
func open_anim(time := 0.9) -> void:
	_set_open(0.0)
	create_tween().tween_method(_set_open, 0.0, 1.0, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_open(v: float) -> void:
	_open = v
	for m in _mats:
		m.set_shader_parameter("open", maxf(v, 0.001))


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = (1.9 + 0.5 * sin(_t * 2.3) + 0.25 * sin(_t * 7.1)) * _open
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		_bolt_t = _rng.randf_range(0.07, 0.16)
		_draw_bolts()


## Raios: alguns estalos em zigue-zague saindo da borda da nuvem (às vezes nenhum: pisca).
func _draw_bolts() -> void:
	var im := _bolts.mesh as ImmediateMesh
	im.clear_surfaces()
	var n := _rng.randi_range(0, 3) if _open > 0.9 else 0
	if n == 0:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in n:
		var a := _rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * radius * _rng.randf_range(0.45, 0.65)
		var d := Vector2(cos(a), sin(a))
		var steps := _rng.randi_range(3, 6)
		var w := 0.03
		for s in steps:
			var turn := d.rotated(_rng.randf_range(-0.9, 0.9))
			var q := p + turn * radius * _rng.randf_range(0.05, 0.1)
			_seg(im, p, q, w)
			if _rng.randf() < 0.25:   # galho
				_seg(im, q, q + turn.rotated(_rng.randf_range(-1.2, 1.2)) * radius * 0.12, w * 0.6)
			p = q
			w *= 0.85
	im.surface_end()


static func _seg(im: ImmediateMesh, a: Vector2, b: Vector2, w: float) -> void:
	var n := (b - a).orthogonal().normalized() * w
	var v := [Vector3(a.x + n.x, a.y + n.y, 0), Vector3(a.x - n.x, a.y - n.y, 0), Vector3(b.x - n.x, b.y - n.y, 0),
		Vector3(b.x + n.x, b.y + n.y, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		im.surface_add_vertex(v[i])
