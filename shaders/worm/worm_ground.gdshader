shader_type spatial;
// Chão quebrado do Desmoronamento (chao_rachado.png: placas de pedra cinzentas e rachaduras brancas em fundo
// preto, visto de cima), num plano deitado. As placas ganham a cor da pedra; as rachaduras acendem na cor quente
// (`heat` 1 -> 0: de acesas a frias). Abre do centro para fora (`grow`) e some comida da borda para o centro, em
// pedaços (`erode`), nunca só transparente.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D cracks : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec3 stone_a = vec3(0.3, 0.26, 0.24);
instance uniform vec3 stone_b = vec3(0.08, 0.06, 0.06);
instance uniform vec3 hot = vec3(1.0, 0.6, 0.12);
instance uniform float heat = 1.0;
instance uniform float grow = 1.0;
instance uniform float erode = 0.0;
instance uniform float spin = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(spin);
	float s = sin(spin);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float g = texture(cracks, p + 0.5).r;
	float sil = textureLod(cracks, p + 0.5, 3.0).r;
	float r = length(p) * 2.0;
	float crack = smoothstep(0.62, 0.85, g);
	vec3 col = mix(stone_b, stone_a, smoothstep(0.2, 0.45, g));
	// a rachadura: acesa na cor quente (branca no auge), depois escura como o vão entre as placas
	vec3 lit = mix(hot, vec3(1.0), 0.5 * heat) * (1.0 + 2.2 * heat);
	col = mix(col, mix(stone_b * 0.5, lit, smoothstep(0.0, 0.25, heat)), crack);
	float inside = smoothstep(0.08, 0.2, max(g, sil * 1.4));
	float open = 1.0 - smoothstep(grow - 0.1, grow, r);
	float n = hash(floor((p + 0.5) * 22.0) + spin);
	float keep = step(erode * 1.5, (1.0 - r) * 0.9 + n * 0.5 + 0.02);
	ALBEDO = col;
	ALPHA = inside * open * keep;
}
