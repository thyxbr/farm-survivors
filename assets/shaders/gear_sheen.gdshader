shader_type spatial;
// Superfícies sem luz própria dos conjuntos de fim de jogo (ouro, penas, escamas, osso): continuam com a luz
// em dois tons e ganham um reflexo em faixa dura que varre a peça de tempos em tempos (brilho de anime) e,
// se pedido, brasa que respira em veios pela peça e nas frestas (sombra assada escura na cor por vértice).
// Montado por GearFx (scripts/player/gear_fx.gd).
render_mode cull_back, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform vec3 sheen_col : source_color = vec3(1.0);
uniform float sheen_power = 0.8;
uniform vec3 sheen_dir = vec3(0.5, 1.0, 0.0);     // direção em que a faixa anda (espaço do modelo)
uniform float sheen_freq = 0.55;          // faixas por metro
uniform float sheen_speed = 0.3;          // faixas por segundo
uniform float sheen_width = 0.05;         // largura da faixa (fração do ciclo)
uniform vec3 ember_col : source_color = vec3(1.0, 0.45, 0.1);
uniform float ember = 0.0;                // brasa nas frestas (0 = sem)
uniform float ember_speed = 1.2;

#include "res://assets/shaders/toon_light.gdshaderinc"

varying vec3 pos;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	pos = VERTEX;
}

void fragment() {
	vec3 base = albedo.rgb;
	float ao = 1.0;
	if (use_vertex_color) {
		vec3 vc = COLOR.rgb;
		if (vertex_color_srgb) {
			vc = pow(vc, vec3(2.2));
		}
		ao = dot(vc, vec3(0.3333));
		base *= vc;
	}
	float ph = fract(dot(pos, normalize(sheen_dir)) * sheen_freq - TIME * sheen_speed);
	// faixa larga e, logo atrás, um risco fino: o par de reflexos do metal desenhado
	float s = step(abs(ph - 0.5), sheen_width) + step(abs(ph - 0.5 - sheen_width * 2.6), sheen_width * 0.35);
	vec3 glow = sheen_col * s * sheen_power;
	if (ember > 0.0) {
		// veios de lava: a linha onde o ruído cruza o meio, fina e de borda seca
		float vein = 1.0 - smoothstep(0.02, 0.03, abs(noise3(pos * 24.0) - 0.5));
		float crack = max(vein, 1.0 - smoothstep(0.35, 0.7, ao));
		float breath = 0.55 + 0.45 * sin(TIME * ember_speed + pos.y * 7.0 + pos.x * 3.0);
		glow += ember_col * crack * ember * breath;
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow;
}
