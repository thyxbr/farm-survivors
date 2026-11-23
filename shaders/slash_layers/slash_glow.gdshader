shader_type spatial;
// Corte em camadas (LayeredSlashTrail): o brilho, aditivo, por cima do fundo (next_pass de slash_under).
// Centro quase branco no fio, a cor da arma no corpo, borda mais clara nos dentes e nos buracos da erosão.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/slash_layers/slash_common.gdshaderinc"

uniform float body_gain = 0.8;
uniform float rim_gain = 0.6;
uniform float core_gain = 2.4;

void fragment() {
	float body;
	float core;
	float rim;
	float rel;
	float slash_paint;
	float s = COLOR.a;
	slash_shape(UV, s, TIME, body, core, rim, rel, slash_paint);
	vec3 light = mix(tint, vec3(1.0), 0.25);   // menos branco: a cor da arma aparece
	vec3 hot = mix(tint, vec3(1.0), 0.85);
	// aceso perto da borda de fora, apagando para dentro (o fundo escuro manda lá)
	float outer = pow(1.0 - rel, 2.0);
	// o brilho segue a pintura: as línguas claras acendem, os vãos ficam apagados
	float paint = smoothstep(0.35, 1.0, slash_paint);
	vec3 c = tint * body * outer * paint * body_gain + light * rim * rim_gain * s * (0.35 + 0.65 * outer) + hot * core * core_gain;
	ALBEDO = c * intensity;
	ALPHA = 1.0;
}
