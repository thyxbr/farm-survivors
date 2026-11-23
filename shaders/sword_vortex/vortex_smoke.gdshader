shader_type spatial;
// Vórtice Sombrio: a fumaça escura das fitas e da meia-lua (mistura normal). Conta em vortex_common.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/sword_vortex/vortex_common.gdshaderinc"

uniform float smoke_alpha = 1.0;

void fragment() {
	float smoke;
	float rim;
	float veil;
	vortex(UV, COLOR.a, TIME, smoke, rim, veil);
	ALBEDO = mix(smoke_col, glow_col * 0.25, smoothstep(0.6, 1.0, UV.y) * 0.35);
	// nuvem: onde é ralo puxa para o violeta (luz passando), onde é denso fica quase preto (volume)
	ALBEDO = mix(ALBEDO, mix(smoke_col * 2.2 + glow_col * 0.08, smoke_col * 0.35, smoothstep(0.15, 0.8, smoke)), soft);
	ALPHA = clamp(smoke * smoke_alpha * intensity, 0.0, 1.0);
}
