shader_type spatial;
// Círculo da Provocação Sombria: quadro da sprite sheet com mistura ADITIVA, para o que é luz (runas e traços
// roxos do círculo). O fundo preto não soma nada e some sozinho, sem retângulo; `black_cut` zera só o ruído da
// compressão. O roxo ganha um puxão para o magenta nos pontos mais quentes (`hot`).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/dark_taunt/dark_sheet.gdshaderinc"

uniform float black_cut = 0.08;
uniform float gain = 0.75;
uniform vec3 tint : source_color = vec3(0.75, 0.4, 1.0);
uniform vec3 hot : source_color = vec3(1.0, 0.35, 0.9);

void vertex() {
	sheet_vertex(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec3 c = sheet_sample(UV);
	float lum = pow(max(c.r, max(c.g, c.b)), 0.4545);   // percebida: a textura vem linearizada
	c *= smoothstep(black_cut, black_cut + 0.08, lum);
	c = mix(c, hot * c * 1.4, smoothstep(0.75, 1.0, lum) * 0.5);
	ALBEDO = c * tint * gain * intensity * sheet_reveal(UV) * sheet_soft(UV);
	ALPHA = 1.0;
}
