shader_type spatial;
// Corte em camadas (LayeredSlashTrail): o fundo escuro na cor da arma, mistura normal. Sem ele o brilho aditivo some
// contra um chão claro ao meio-dia; com ele o corte tem contorno, como nas referências desenhadas.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/slash_layers/slash_common.gdshaderinc"

uniform float under_alpha = 0.88;

void fragment() {
	float body;
	float core;
	float rim;
	float rel;
	float slash_paint;
	slash_shape(UV, COLOR.a, TIME, body, core, rim, rel, slash_paint);
	// a cor da arma junto da borda de fora, escurecendo até o fundo nos dentes
	ALBEDO = mix(tint * 0.85, deep, smoothstep(0.15, 0.8, rel));
	// a pintura por dentro: onde ela é escura (entre as línguas, os riscos) fica a cor funda e mais transparente;
	// onde é clara, a cor da arma. Sem isso o corte vira um preenchimento chapado
	ALBEDO = mix(deep, ALBEDO, smoothstep(0.25, 0.85, slash_paint));
	ALPHA = clamp(body * under_alpha * mix(0.45, 1.0, slash_paint) * intensity, 0.0, 1.0);
}
