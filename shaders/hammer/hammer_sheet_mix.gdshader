shader_type spatial;
// Martelo de Energia: quadro da sprite sheet deitado no chão (crateras), com mistura normal em vez de soma. Os
// quadros 51-54 trazem o chão rachado escuro em volta das rachaduras acesas: com soma o escuro sumiria. Aqui o
// fundo preto puro vira transparente pela luminância (alfa sobe rápido a partir do quase-preto), então as pedras
// escuras ficam como sombra sobre o chão do jogo e as rachaduras claras brilham por cima (cor HDR > 1).
// `vignette` apaga as bordas do quadro, para o desenho não acabar num retângulo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

#include "res://shaders/hammer/hammer_sheet.gdshaderinc"

uniform float black_cut = 0.04;
uniform float dark_alpha = 0.7;     // opacidade das partes escuras (pedra rachada)
uniform float glow_gain = 2.2;      // brilho das rachaduras acesas
uniform float vignette = 0.42;
uniform float core_hide = 0.38;     // o miolo estourado do quadro some (a bacia da cratera é do outro desenho)
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec3 c = sheet_sample(UV);
	float lum = max(c.r, max(c.g, c.b));
	float a = smoothstep(black_cut, black_cut + 0.12, lum);
	float r = length(UV - 0.5) * 2.0;
	float bright = smoothstep(0.35, 0.9, lum) * smoothstep(core_hide * 0.4, core_hide, r);
	vec3 col = sheet_recolor(c) * tint;
	// escuro: tom de pedra queimada; claro: a rachadura acesa (HDR)
	vec3 dark = c * 0.6;
	col = mix(dark, col * glow_gain, bright);
	float edge = 1.0 - smoothstep(1.0 - vignette, 1.0, r);
	ALBEDO = col;
	ALPHA = clamp(mix(a * dark_alpha, 1.0, bright) * edge * intensity * sheet_reveal(UV), 0.0, 1.0);
}
