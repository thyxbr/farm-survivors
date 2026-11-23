shader_type spatial;
// Lâminas Rúnicas: as runas acesas (runas_faixa.png, glifos brancos em fila) correndo ao longo das duas bordas da
// lâmina, acompanhando a curva do fuso. Quad mais largo que a lâmina, aditivo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;
#include "blade_common.gdshaderinc"

uniform sampler2D runes : source_color, filter_linear_mipmap, repeat_enable;
// quanto da faixa de runas cabe no comprimento da lâmina
uniform float span = 0.6;
instance uniform float phase = 0.0;

void fragment() {
	float x = (UV.x - 0.5) * 2.0;
	float y = UV.y;
	float prof = 1.0 - abs(y * 2.0 - 1.0);
	float center = 0.14 + 0.46 * prof;
	float d = (abs(x) - center) / 0.11;
	float inside = 1.0 - step(1.0, abs(d));
	float u = y * span + phase + (x > 0.0 ? 0.37 : 0.0) + TIME * 0.05;
	float g = texture(runes, vec2(u, d * 0.5 + 0.5)).r;
	float flick = 0.75 + 0.25 * sin(TIME * 23.0 + floor(u * 20.0) * 2.7);
	ALBEDO = mix(col, vec3(1.0), 0.2) * g * inside * smoothstep(0.0, 0.2, prof) * 1.7 * flick * intensity;
	ALPHA = 1.0;
}
