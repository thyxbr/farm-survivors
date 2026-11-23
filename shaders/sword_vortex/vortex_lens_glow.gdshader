shader_type spatial;
// Vórtice Sombrio: a lente do giro, camada acesa (aditiva, next_pass da escura). Conta em vortex_lens.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/sword_vortex/vortex_lens.gdshaderinc"

uniform float rim_gain = 0.6;
uniform float halo_gain = 0.45;
uniform float streak_gain = 0.9;

void fragment() {
	float glass;
	float edge_smoke;
	float rim;
	float halo;
	float streak;
	lens(UV, COLOR.a, TIME, glass, edge_smoke, rim, halo, streak);
	vec3 hot = mix(glow_col, vec3(1.0), 0.35 * pow(1.0 - clamp(UV.x, 0.0, 1.0), 8.0));
	ALBEDO = (hot * rim * rim_gain + glow_col * halo * halo_gain + glow_col * streak * streak_gain) * intensity;
	ALPHA = 1.0;
}
