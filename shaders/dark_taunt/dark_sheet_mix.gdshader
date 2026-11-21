shader_type spatial;
// Círculo da Provocação Sombria: quadro da sprite sheet com mistura NORMAL, para as mãos e a fumaça, que são
// escuras: com soma elas sumiriam. O fundo é preto quase puro (~0,01) e as mãos/fumaça são cinza-arroxeado escuro
// (0,08..0,25): o alfa sobe pela luminância logo acima do preto, então o fundo vira transparente (sem retângulo) e
// o escuro fica como sombra opaca por cima do jogo; o que brilha (contornos roxos) sai em HDR por cima.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/dark_taunt/dark_sheet.gdshaderinc"

uniform float black_cut = 0.04;
uniform float dark_alpha = 0.9;     // opacidade das partes escuras (mãos, fumaça)
uniform float glow_gain = 2.4;      // brilho dos contornos roxos
uniform float dark_tone = 0.6;      // o escuro fica ainda mais escuro (sombra, não cinza)
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	sheet_vertex(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec3 c = sheet_sample(UV);
	// a textura vem linearizada (source_color): os limiares valem na luminância percebida (sRGB), onde o fundo
	// é ~0,01 e as mãos/fumaça escuras ~0,1..0,25
	float lum = pow(max(c.r, max(c.g, c.b)), 0.4545);
	float a = smoothstep(black_cut, black_cut + 0.11, lum);
	float bright = smoothstep(0.45, 0.85, lum);
	vec3 col = mix(c * dark_tone, c * glow_gain, bright) * tint;
	ALBEDO = col;
	ALPHA = clamp(mix(a * dark_alpha, 1.0, bright) * intensity * sheet_soft(UV) * sheet_reveal(UV), 0.0, 1.0);
}
