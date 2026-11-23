shader_type spatial;
// O respingo de energia no chão, visto de cima (respingo_chao.png, claro em fundo preto), num plano deitado.
// Miolo branco, meio na cor, pontas no azul fundo. `erode` come a pintura do mais fraco para o mais forte e `hole`
// abre um buraco do centro para fora: o respingo vira anel.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D splash : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 deep = vec3(0.1, 0.08, 0.7);

instance uniform vec3 col = vec3(0.28, 0.38, 1.0);
instance uniform float intensity = 1.0;
instance uniform float erode = 0.1;
instance uniform float hole = 0.0;
instance uniform float spin = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(spin);
	float s = sin(spin);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float g = texture(splash, p + 0.5).r;
	float r = length(p) * 2.0;
	vec3 k = mix(deep, col, smoothstep(0.15, 0.5, g));
	k = mix(k, vec3(1.0), smoothstep(0.75, 1.0, g) * (1.0 - smoothstep(0.25, 0.75, r)));
	ALBEDO = k * (0.9 + 0.5 * g);
	ALPHA = smoothstep(erode, erode + 0.12, g) * smoothstep(hole - 0.25, hole, r) * (1.0 - smoothstep(0.92, 1.0, r)) * intensity;
}
