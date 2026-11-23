shader_type spatial;
// O corpo eletrizado: camada por cima do personagem (material_overlay) que acende o contorno, branco no pico e
// na cor ao apagar, tremendo como corrente.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 col = vec3(0.28, 0.38, 1.0);
uniform float intensity = 0.0;
uniform float white = 1.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float flick = 0.82 + 0.18 * sin(TIME * 73.0 + FRAGCOORD.y * 0.35);
	vec3 c = mix(col, vec3(1.0), white);
	ALBEDO = (c * f * 2.0 + col * 0.05) * intensity * flick;
	ALPHA = 1.0;
}
