shader_type spatial;
// Terremoto Devastador: o fundo escuro das rachaduras (GroundCrack monta as fitas seguindo o relevo). UV.x = de um
// lado ao outro da fita (0..1), UV.y = distância do ponto ao centro do terremoto (m). Só aparece onde a onda
// (`wave_r`, m) já passou, e a fissura ABRE depois que ela passa (começa fina e alarga). O brilho azul do fundo é a
// passada seguinte (eq_crack_glow.gdshader, next_pass), com as mesmas contas de abertura.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/earthquake/eq_noise.gdshaderinc"

uniform float wave_r = 0.0;
uniform float open_time = 0.9;   // m atrás da frente para a fissura abrir toda
uniform float alpha_mul = 1.0;   // some no fim (dissipação)
uniform vec3 deep_color : source_color = vec3(0.015, 0.02, 0.035);
uniform vec3 lip_color : source_color = vec3(0.16, 0.15, 0.15);
uniform float cam_push = 0.05;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world += normalize(CAMERA_POSITION_WORLD - world) * cam_push;
	VERTEX = world - MODEL_MATRIX[3].xyz;
}

void fragment() {
	float behind = wave_r - UV.y;
	float open = smoothstep(0.0, open_time, behind);
	float across = abs(UV.x - 0.5) * 2.0;
	// borda roída: a largura varia ao longo da fissura
	float wob = eq_noise(vec2(UV.y * 3.1, UV.x * 2.0)) * 0.35;
	float w = mix(0.2, 1.0, open) * (0.75 + wob);
	float inside = 1.0 - smoothstep(w * 0.8, w, across);
	ALBEDO = mix(deep_color, lip_color, smoothstep(0.3, 1.0, across / max(w, 0.001)));
	ALPHA = inside * step(0.0, behind) * alpha_mul * 0.95;
}
