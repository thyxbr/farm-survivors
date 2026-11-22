shader_type spatial;
// Lâmina Suprema: casca de chamas sombrias, camada de fumaça escura (mistura normal). Conta em dark_aura.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/greatsword_dark/dark_aura.gdshaderinc"

void vertex() {
	aura_vertex(VERTEX, NORMAL, UV, TIME);
}

void fragment() {
	float smoke;
	vec3 glow;
	aura_shade(UV, NORMAL, VIEW, TIME, smoke, glow);
	ALBEDO = smoke_col; ALPHA = smoke;
}
