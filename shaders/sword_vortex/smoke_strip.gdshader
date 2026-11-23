shader_type spatial;
// Vórtice Sombrio: fita com textura pintada (fumaca_faixa.png na parede do giro, fumaca_fiapo.png nos rabos).
// Fumaça clara em fundo preto: o claro é a opacidade e o sombreado. Malha: UV.x = ao longo (0 = cabeça, junto da
// lâmina; 1 = cauda), UV.y = atravessando; COLOR.a = força.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D smoke : source_color, filter_linear_mipmap, repeat_enable;
// quantas vezes a textura repete ao longo da fita e a que velocidade corre (para a cauda: a fumaça é arrastada)
uniform float repeat = 2.0;
uniform float flow = 0.35;
// true: a textura é vertical (o fiapo: V ao longo da fita, U atravessando)
uniform bool along_v = false;
uniform float shade_lo = 0.35;
uniform float shade_hi = 1.15;
// some na cauda (fração de UV.x onde começa a sumir)
uniform float tail_fade = 0.55;

instance uniform vec3 smoke_col = vec3(0.045, 0.012, 0.08);
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 st = along_v ? vec2(UV.y, UV.x) : vec2(UV.x * repeat - TIME * flow + seed, UV.y);
	float g = texture(smoke, st).r;
	float fade = smoothstep(0.0, 0.04, UV.x) * (1.0 - smoothstep(tail_fade, 1.0, UV.x));
	ALBEDO = smoke_col * mix(shade_lo, shade_hi, g);
	// ralo: só o mais denso da pintura fica opaco (a fumaça rasga em vez de virar parede)
	ALPHA = smoothstep(0.15, 0.7, g) * 0.75 * fade * COLOR.a * intensity;
}
