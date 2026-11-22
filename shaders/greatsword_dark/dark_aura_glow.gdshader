shader_type spatial;
// Lâmina Suprema: casca de chamas sombrias, camada de brilho (aditiva, next_pass da fumaça). Conta em dark_aura.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/greatsword_dark/dark_aura.gdshaderinc"

void vertex() {
	aura_vertex(VERTEX, NORMAL, UV, TIME);
}

void fragment() {
	float smoke;
	vec3 glow;
	aura_shade(UV, NORMAL, VIEW, TIME, smoke, glow);
	ALBEDO = glow; ALPHA = 1.0;
}
