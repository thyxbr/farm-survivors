shader_type spatial;
// Rastro de energia sombria (DarkBladeTrail): a camada de fumaça escura, mistura normal. O brilho vem do next_pass
// (dark_trail_glow.gdshader). Conta e paleta em dark_energy.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/greatsword_dark/dark_energy.gdshaderinc"

void fragment() {
	float smoke;
	vec3 glow;
	dark_trail(UV, COLOR.a, TIME, smoke, glow);
	ALBEDO = mix(smoke_col, smoke_rim, smoothstep(0.4, 1.0, UV.y) * (1.0 - UV.x));
	ALPHA = smoke * clamp(intensity, 0.0, 1.0);
}
