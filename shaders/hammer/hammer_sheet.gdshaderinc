// Martelo de Energia: leitura da sprite sheet (assets/vfx/hammer/hammer_sheet.webp, 8 x 8 quadros de 128 px, da
// esquerda para a direita e de cima para baixo, fundo preto puro). Usado por hammer_sheet.gdshader (aditivo) e
// hammer_sheet_mix.gdshader (com os detalhes escuros, para o chão rachado das crateras).

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
// recorte dentro do quadro (x, y, largura, altura em 0..1): o rastro e a energia usam só o feixe, sem o anel
instance uniform vec4 crop = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;
// 0 = cores da sheet (dourado), 1 = azul elétrico com o miolo branco (mesmo brilho, outro tom)
instance uniform float recolor = 0.0;
instance uniform float flip_v = 0.0;
// 0..1: revela do centro para fora (materialização do círculo); 1 = inteiro
instance uniform float reveal = 1.0;
// 1 = apaga as bordas do quad (o recorte do feixe não termina num retângulo)
instance uniform float soft_edge = 0.0;

vec3 sheet_frame(float f, vec2 uv) {
	float total = columns * rows;
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	vec2 q = crop.xy + uv * crop.zw;
	// meio texel de margem para não puxar o quadro vizinho no filtro
	q = clamp(q, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + q) / vec2(columns, rows)).rgb;
}

// quadro fracionário: mistura o quadro atual com o seguinte
vec3 sheet_sample(vec2 uv) {
	if (flip_v > 0.5) {
		uv.y = 1.0 - uv.y;
	}
	float f0 = floor(frame);
	return mix(sheet_frame(f0, uv), sheet_frame(f0 + 1.0, uv), frame - f0);
}

vec3 sheet_recolor(vec3 c) {
	float lum = max(c.r, max(c.g, c.b));
	vec3 blue = mix(vec3(0.08, 0.32, 1.0), vec3(0.85, 0.95, 1.0), smoothstep(0.55, 1.0, lum)) * lum * 1.25;
	return mix(c, blue, recolor);
}

float sheet_soft(vec2 uv) {
	if (soft_edge < 0.001) {
		return 1.0;
	}
	float e = smoothstep(0.0, 0.3, uv.x) * smoothstep(1.0, 0.7, uv.x) * smoothstep(0.0, 0.18, uv.y) * smoothstep(1.0, 0.82, uv.y);
	return mix(1.0, e, soft_edge);
}

// revelação radial com borda tremida (energia se juntando do centro para fora)
float sheet_reveal(vec2 uv) {
	if (reveal >= 0.999) {
		return 1.0;
	}
	float r = length(uv - 0.5) * 2.0;
	float a = atan(uv.y - 0.5, uv.x - 0.5);
	float wob = 0.06 * sin(a * 9.0 + TIME * 7.0) + 0.04 * sin(a * 23.0 - TIME * 11.0);
	return 1.0 - smoothstep(reveal * 1.15 - 0.08, reveal * 1.15 + 0.02, r + wob);
}
