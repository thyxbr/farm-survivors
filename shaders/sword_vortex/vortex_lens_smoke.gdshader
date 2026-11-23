shader_type spatial;
// Vórtice Sombrio: a lente do giro, camada escura (mistura normal). Conta em vortex_lens.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/sword_vortex/vortex_lens.gdshaderinc"

void fragment() {
	float glass;
	float edge_smoke;
	float rim;
	float halo;
	float streak;
	lens(UV, COLOR.a, TIME, glass, edge_smoke, rim, halo, streak);
	float a = clamp(glass * 0.45 + edge_smoke * 0.6, 0.0, 0.9);
	// vidro arroxeado no meio, fumaça quase preta na borda
	ALBEDO = mix(smoke_col * 1.6, smoke_col * 0.4, smoothstep(0.1, 0.6, edge_smoke));
	ALPHA = a * intensity;
}
