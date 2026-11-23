shader_type spatial;
// O anel da onda de choque: a crista pintada (onda_faixa.png: faixa clara embaixo, línguas rasgadas para cima)
// enrolada em círculo. Malha: anel unitário (VERTEX = cos, v, sen; UV.x = volta 0..1, UV.y = v, 0 dentro e 1 fora);
// o raio, a largura e a altura da borda de fora vêm por instância, então a mesma malha serve ao anel deitado no chão
// e à coroa em pé. `erode` desfaz a pintura (mais num lado que no outro: o anel some em pedaços).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D crest : source_color, filter_linear_mipmap, repeat_enable;
uniform float repeat = 3.0;
// quanto do claro da pintura vira branco (o resto fica na cor)
uniform float highlight = 0.55;
uniform vec3 deep = vec3(0.02, 0.02, 0.32);
// o anel não é um círculo perfeito: o raio ondula na volta
uniform float wobble = 0.04;

instance uniform vec3 col = vec3(0.28, 0.38, 1.0);
instance uniform float intensity = 1.0;
instance uniform float radius = 1.0;
instance uniform float width = 1.0;
instance uniform float lift = 0.0;
instance uniform float erode = 0.05;
instance uniform float swirl = 0.0;
instance uniform float seed = 0.0;

void vertex() {
	float v = VERTEX.y;
	float ang = UV.x * TAU;
	float wob = 1.0 + wobble * (sin(ang * 2.0 + seed * 5.0) + 0.7 * sin(ang * 7.0 + seed * 11.0));
	float r = (radius + v * width * (0.75 + 0.5 * fract(wob * 3.7))) * wob;
	VERTEX = vec3(VERTEX.x * r, 0.05 + v * lift, VERTEX.z * r);
}

void fragment() {
	float u = UV.x * repeat + swirl + seed;
	float fu = fract(u);
	// a pintura não emenda perfeita: perto da emenda mistura com a outra metade da faixa
	float tv = mix(0.93, 0.2, UV.y);
	float a = texture(crest, vec2(fu, tv)).r;
	float b = texture(crest, vec2(fract(fu + 0.5), tv)).r;
	float g = mix(a, b, smoothstep(0.8, 1.0, abs(fu - 0.5) * 2.0));
	float local = erode * (1.0 + 0.35 * sin(UV.x * TAU * 3.0 + seed * 9.0) + 0.2 * sin(UV.x * TAU * 7.0 + seed * 4.0));
	// luz de desenho: só a beirada da pintura virada para fora acende em branco (a diferença para a mesma pintura
	// um pouco deslocada), o miolo fica na cor e o fraco no azul fundo
	float a2 = texture(crest, vec2(fu - 0.012, tv + 0.07)).r;
	float b2 = texture(crest, vec2(fract(fu + 0.5) - 0.012, tv + 0.07)).r;
	float g2 = mix(a2, b2, smoothstep(0.8, 1.0, abs(fu - 0.5) * 2.0));
	float edge = clamp((g - g2) * 2.2, 0.0, 1.0);
	vec3 k = mix(deep, col, smoothstep(0.35, 0.9, g) * (0.35 + 0.65 * UV.y));
	k = mix(k, vec3(1.0), edge * highlight);
	ALBEDO = k * (0.85 + 1.1 * edge);
	ALPHA = smoothstep(local, local + 0.1, g) * smoothstep(0.0, 0.1, UV.y) * intensity;
}
