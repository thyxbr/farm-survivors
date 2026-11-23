shader_type spatial;
// Vórtice Sombrio: o brilho das fitas e da meia-lua (aditivo, por cima da fumaça: next_pass de vortex_smoke).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/sword_vortex/vortex_common.gdshaderinc"

uniform float rim_gain = 4.5;
uniform float veil_gain = 0.1;

void fragment() {
	float smoke;
	float rim;
	float veil;
	vortex(UV, COLOR.a, TIME, smoke, rim, veil);
	vec3 hot = mix(glow_col, vec3(1.0), 0.55 * (1.0 - UV.x));
	ALBEDO = (hot * rim * rim_gain + glow_col * veil * veil_gain) * intensity;
	ALPHA = 1.0;
}
