shader_type spatial;
// Terremoto Devastador: pedra das placas levantadas e dos fragmentos (MultiMesh). A cor de vértice marca onde a pedra
// guarda energia (a face de baixo das placas, o miolo dos fragmentos); INSTANCE_CUSTOM.x = o quanto ainda está
// quente (0..1, esfria com o tempo) e INSTANCE_CUSTOM.y = o quanto já afundou/sumiu (0..1, dissolve com ruído).
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/earthquake/eq_noise.gdshaderinc"

uniform vec3 rock_a : source_color = vec3(0.30, 0.29, 0.30);
uniform vec3 rock_b : source_color = vec3(0.17, 0.16, 0.18);
uniform vec3 glow_color : source_color = vec3(0.15, 0.5, 1.0);
uniform float glow_energy = 3.5;

varying vec3 v_local;
varying vec2 v_custom;
varying vec3 v_mask;

void vertex() {
	v_local = VERTEX;
	v_custom = INSTANCE_CUSTOM.xy;
	v_mask = COLOR.rgb;
}

void fragment() {
	float n = eq_fbm(v_local.xz * 5.0 + v_local.y * 3.0);
	ALBEDO = mix(rock_b, rock_a, n);
	ROUGHNESS = 0.92;
	EMISSION = glow_color * v_mask * v_custom.x * glow_energy * (0.6 + 0.8 * n);
	// sumindo: furos que crescem com o ruído (some aos poucos, não tudo de uma vez)
	if (n < v_custom.y * 1.05 - 0.02) {
		discard;
	}
}
