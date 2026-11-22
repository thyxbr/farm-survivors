shader_type spatial;
// Terremoto Devastador: a energia azul e branca no fundo das rachaduras (passada aditiva por cima de eq_crack). Mesmas
// UVs: UV.x = de um lado ao outro, UV.y = distância ao centro (m). Bem forte logo atrás da frente da onda (a fissura
// acabou de abrir), pulsando ao longo do comprimento, e esfria com `glow` (a dissipação baixa até 0).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/earthquake/eq_noise.gdshaderinc"

uniform float wave_r = 0.0;
uniform float open_time = 0.9;
uniform float glow = 1.0;
uniform float hot_len = 1.6;      // m atrás da frente em que a fissura ainda está "fervendo"
uniform vec3 hot_color : source_color = vec3(0.85, 0.95, 1.0);
uniform vec3 cool_color : source_color = vec3(0.1, 0.38, 1.0);
uniform float cam_push = 0.06;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world += normalize(CAMERA_POSITION_WORLD - world) * cam_push;
	VERTEX = world - MODEL_MATRIX[3].xyz;
}

void fragment() {
	float behind = wave_r - UV.y;
	float open = smoothstep(0.0, open_time, behind);
	float across = abs(UV.x - 0.5) * 2.0;
	float wob = eq_noise(vec2(UV.y * 3.1, UV.x * 2.0)) * 0.35;
	float w = mix(0.2, 1.0, open) * (0.75 + wob);
	float core = 1.0 - smoothstep(0.0, w * 0.55, across);
	float hot = exp(-max(behind, 0.0) / hot_len);
	// pulso de energia correndo para fora pela fissura
	float pulse = 0.65 + 0.35 * sin(UV.y * 2.4 - TIME * 9.0) * eq_noise(vec2(UV.y * 1.3, TIME * 0.7));
	float e = core * step(0.0, behind) * (glow * pulse + hot * 1.4);
	vec3 col = mix(cool_color, hot_color, clamp(core * core * core * 0.5 + hot * 0.45, 0.0, 1.0));
	ALBEDO = col * e * 1.25;
	ALPHA = 1.0;
}
