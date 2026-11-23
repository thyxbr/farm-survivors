shader_type spatial;
// Geada pintada no chão (geada_chao.png: frondes de gelo brancas em fundo preto), num plano deitado. Abre do
// centro para fora (`grow`) e some comida do mais fraco para o mais forte (`erode`), nunca só transparente.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D frost : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec3 core = vec3(0.7, 0.93, 1.0);
instance uniform vec3 mid = vec3(0.1, 0.45, 0.95);
instance uniform float grow = 1.0;
instance uniform float erode = 0.0;
instance uniform float spin = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(spin);
	float s = sin(spin);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float g = texture(frost, p + 0.5).r;
	// um véu de frio por baixo das frondes (a mesma pintura borrada): lê de longe e de dia
	float veil = textureLod(frost, p + 0.5, 4.0).r;
	float r = length(p) * 2.0;
	float open = 1.0 - smoothstep(grow - 0.15, grow, r);
	float line = smoothstep(0.12 + erode * 0.8, 0.3 + erode * 0.8, g);
	ALBEDO = mix(mid, core, line) * (1.0 + 0.6 * line);
	ALPHA = max(line, veil * 0.55 * (1.0 - erode)) * open * (1.0 - smoothstep(0.9, 1.0, r));
}
