shader_type spatial;
// Canalização de Fogo: o círculo mágico (sheet A, assets/vfx/flame_channel/flame_circle_clean.png, 8 x 8 quadros de 128 px,
// fundo preto) num quad de pé na frente da palma, virado para o jato. Mistura ADITIVA: o preto não soma nada e some
// sozinho. O quadro vem de FlameChanneling (frame_a -> frame_b, mix: a animação não pula, e o laço emenda o último
// quadro no primeiro); `spin` gira o desenho em volta do centro (o círculo girando rápido além do giro da própria sheet).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
// corta o ruído da compressão perto do preto (brilho percebido)
uniform float black_cut = 0.06;
// > 1 estoura no Glow do WorldEnvironment
uniform float gain = 2.2;
uniform vec3 tint : source_color = vec3(1.0, 0.72, 0.45);
// os pontos mais quentes puxam para o amarelo-branco
uniform vec3 hot : source_color = vec3(1.0, 0.92, 0.7);

instance uniform float frame_a = 0.0;
instance uniform float frame_b = 0.0;
instance uniform float frame_mix = 0.0;
instance uniform float intensity = 1.0;
instance uniform float spin = 0.0;

vec3 cell_rgb(float f, vec2 uv) {
	f = clamp(floor(f + 0.5), 0.0, columns * rows - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	return texture(sheet, (cell + clamp(uv, vec2(0.0), vec2(1.0))) / vec2(columns, rows)).rgb;
}

void fragment() {
	vec2 d = UV - 0.5;
	float s = sin(spin);
	float c = cos(spin);
	vec2 uv = vec2(c * d.x - s * d.y, s * d.x + c * d.y) + 0.5;
	// recorte redondo: girando, os cantos do quadro (e a borda esmaecida) nunca aparecem
	float mask = 1.0 - smoothstep(0.44, 0.5, length(d));
	vec3 col = mix(cell_rgb(frame_a, uv), cell_rgb(frame_b, uv), frame_mix);
	float lum = pow(max(col.r, max(col.g, col.b)), 0.4545);
	col *= smoothstep(black_cut, black_cut + 0.08, lum);
	col = mix(col * tint, hot * col * 1.6, smoothstep(0.7, 1.0, lum) * 0.6);
	ALBEDO = col * gain * intensity * mask;
	ALPHA = 1.0;
}
