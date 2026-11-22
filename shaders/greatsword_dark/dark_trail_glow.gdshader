shader_type spatial;
// Rastro de energia sombria (DarkBladeTrail): a camada de brilho (bordas violeta, veias carmesim, o fio quase branco),
// mistura aditiva, desenhada depois da fumaça (next_pass de dark_trail_smoke). Conta em dark_energy.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/greatsword_dark/dark_energy.gdshaderinc"

void fragment() {
	float smoke;
	vec3 glow;
	dark_trail(UV, COLOR.a, TIME, smoke, glow);
	ALBEDO = glow * intensity;
	ALPHA = 1.0;
}
