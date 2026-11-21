shader_type spatial;
// Terremoto Devastador: a parede baixa de energia que corre em cima da frente da onda (ShockwaveRing refaz a faixa a
// cada quadro no raio atual, com a base no chão de cada ponto). UV.x = ângulo (0..1), UV.y = 0 no chão e 1 no topo.
// Estrias verticais subindo e o topo esfarrapado; aditivo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/earthquake/eq_noise.gdshaderinc"

uniform float intensity = 1.0;
uniform float streaks = 70.0;
uniform vec3 base_color : source_color = vec3(0.75, 0.9, 1.0);
uniform vec3 top_color : source_color = vec3(0.1, 0.35, 1.0);

void fragment() {
	float h = UV.y;
	float s = eq_fbm(vec2(UV.x * streaks, h * 1.5 - TIME * 3.5));
	// topo esfarrapado: cada estria tem a sua altura
	float top = 0.35 + 0.65 * eq_noise(vec2(UV.x * streaks * 0.5, TIME * 0.8));
	float a = (1.0 - smoothstep(top * 0.4, top, h)) * smoothstep(0.0, 0.06, h) * (0.35 + 0.9 * s);
	vec3 col = mix(base_color * 1.6, top_color, smoothstep(0.0, 0.6, h));
	ALBEDO = col * a * intensity;
	ALPHA = 1.0;
}
