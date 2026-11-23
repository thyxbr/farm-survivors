// Corte em camadas (LayeredSlashTrail): a conta da forma, dividida entre a camada de fundo (slash_under, mistura normal:
// dá contraste de dia) e a de brilho (slash_glow, aditiva: o glow do mundo pega no que passa de 1).
// Malha: UV.x = idade (0 = junto da lâmina agora, 1 = o mais velho), UV.y = do cabo (0) à borda de fora (1),
// COLOR.a = força do golpe naquele ponto. As cores vêm da arma (instance uniforms, LayeredSlashTrail.set_color).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// corte pintado (corte_faixa.png): energia clara em fundo preto. A cabeça arredondada à esquerda, a borda
// de fora lisa em cima, línguas rasgadas embaixo, afinando até sumir à direita. Limites medidos na imagem (1024x254):
// x de 17 a 985, y de 49 (a borda de fora) a 231.
uniform sampler2D slash_tex : filter_linear_mipmap, repeat_disable;
const vec2 SLASH_X = vec2(17.0 / 1024.0, 985.0 / 1024.0);
const vec2 SLASH_Y = vec2(49.0 / 254.0, 231.0 / 254.0);

instance uniform vec3 tint = vec3(1.0, 0.35, 0.85);   // cor da arma, saturada
instance uniform vec3 deep = vec3(0.25, 0.04, 0.3);   // a mesma, escura (fundo)
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;
instance uniform float head_w = 0.92;    // largura do corpo na cabeça (fração da faixa cabo -> borda)
instance uniform float tail_pow = 0.55;  // > 1: fica largo por mais tempo antes de afinar
instance uniform float tex_on = 1.0;     // 1 = a forma vem do corte pintado; 0 = a forma antiga, por ruído

// body: o corpo em meia-lua (largo junto da lâmina, fino na cauda), com dentes do lado de dentro e se desfazendo em
// pedaços com a idade (erosão, não transparência). core: o fio quase branco na borda de fora. rim: a borda do corpo.
// rel: onde o ponto fica dentro do corpo (0 = borda de fora, 1 = ponta dos dentes do lado de dentro).
void slash_shape(vec2 uv, float s, float time, out float body, out float core, out float rim, out float rel, out float slash_paint) {
	slash_paint = 1.0;   // o cinza do corte pintado: o sombreado das línguas e dos riscos
	float age = clamp(uv.x, 0.0, 1.0);
	float v = clamp(uv.y, 0.0, 1.0);
	float d = 1.0 - v;   // distância da borda de fora
	// largura da meia-lua: cheia na cabeça, afinando até a cauda
	float w = mix(head_w, 0.05, pow(age, tail_pow)) * s;
	// dentes: ruído fino ao longo do corte e comprido no sentido do raio (línguas de fogo apontando para dentro)
	float teeth = texture(noise_tex, vec2(age * 7.0 + seed, v * 0.25 + seed * 0.3)).r;
	float teeth2 = texture(noise_tex, vec2(age * 16.0 - seed, v * 0.5)).r;
	float wj = w * (0.45 + 0.9 * teeth + 0.35 * (teeth2 - 0.5));
	body = 1.0 - smoothstep(wj - 0.05, wj, d);
	rel = clamp(d / max(wj, 0.001), 0.0, 1.0);
	// erosão: o ruído contra a idade; o que fica abaixo some. Corre um pouco para dar vida.
	float er = texture(noise_tex, vec2(age * 2.1 - time * 0.5 + seed * 1.7, v * 1.4 + time * 0.15)).r;
	float er2 = texture(noise_tex, vec2(age * 5.3 + seed, v * 3.7 - time * 0.4)).r;
	float e = er * 0.75 + er2 * 0.45;
	float cut = age * 1.15 - 0.12;
	float erode = smoothstep(cut - 0.04, cut + 0.06, e);
	body *= erode;
	body *= smoothstep(0.0, 0.3, v);                   // nada junto do cabo
	// borda acesa: a faixa em volta do limite (dentes e buracos da erosão)
	rim = (1.0 - smoothstep(0.0, 0.07, abs(d - wj + 0.04))) * erode * smoothstep(0.0, 0.3, v)
		+ (1.0 - smoothstep(0.0, 0.08, abs(e - cut - 0.01))) * body * 0.8;
	// fio: colado na borda de fora, dura menos que o corpo
	float cw = mix(0.06, 0.015, age) * max(s, 0.25);
	core = exp(-max(d, 0.0) / cw) * pow(1.0 - age, 1.4) * smoothstep(cut - 0.1, cut + 0.1, e + 0.25);
	if (tex_on > 0.5) {
		// a idade corre da cabeça (esquerda da imagem) à cauda (direita); a altura da pintura encolhe com a força do
		// golpe (um corte fraco é mais fino) e um tremor leve no x dá vida
		float jit = (texture(noise_tex, vec2(v * 0.7 + time * 0.8, seed)).r - 0.5) * 0.02;
		float tx = mix(SLASH_X.x, SLASH_X.y, clamp(age + jit, 0.0, 1.0));
		float ty = SLASH_Y.x + d / max(s * head_w, 0.15) * (SLASH_Y.y - SLASH_Y.x);
		float g = ty < 0.99 ? texture(slash_tex, vec2(tx, ty)).r : 0.0;
		slash_paint = g;
		rel = clamp((ty - SLASH_Y.x) / (SLASH_Y.y - SLASH_Y.x), 0.0, 1.0);
		body = smoothstep(0.06, 0.4, g) * smoothstep(0.0, 0.15, v) * mix(0.55, 1.0, g);
		// fio branco só bem colado na borda de fora (a cabeça pintada é toda clara: sem isso vira um borrão branco)
		core = smoothstep(0.85, 1.0, g) * (1.0 - smoothstep(0.0, 0.07, rel));
		rim = (smoothstep(0.3, 0.55, g) - smoothstep(0.65, 0.9, g)) * 0.8;
	}
}
