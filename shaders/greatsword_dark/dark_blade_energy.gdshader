shader_type spatial;
// Lâmina Suprema: a energia sombria que cobre a montante e cresce com ela (malha de GreatswordSupremeSlash.sword_mesh:
// VERTEX.y = 0 nas mãos e 1 na ponta, UV.x = 0 no gume e 1 na quina, COLOR.r = 1 na lâmina). Só a lâmina aparece (a
// guarda e o cabo da malha ficam de fora: o cabo de verdade está nas mãos). Miolo de fumaça escura correndo para a
// ponta, gumes e borda acesos em violeta, veias e a quina carmesim, a frente da energia (onde ela ainda está cobrindo a
// lâmina) quase branca. Mistura normal com as cores claras passando de 1 (o glow pega nelas).
//   heat      0..1 quanto da lâmina a energia já cobriu (da guarda até a ponta)
//   intensity brilho geral      dissolve  0 = inteira, 1 = desfeita (depois do impacto)
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 smoke_col = vec3(0.03, 0.006, 0.055);
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);
uniform vec3 hot_col = vec3(1.0, 0.82, 1.0);
uniform float blade_from = 0.085;
instance uniform float heat = 0.0;
instance uniform float intensity = 1.0;
instance uniform float dissolve = 0.0;
instance uniform float seed = 0.0;

varying float along;
varying float part;

void vertex() {
	along = VERTEX.y;
	part = COLOR.r;
}

void fragment() {
	if (part < 0.5) {
		discard;
	}
	float h = clamp((along - blade_from) / (1.0 - blade_from), 0.0, 1.0);
	float n = texture(noise_tex, vec2(UV.x * 1.3 + seed, along * 3.5 - TIME * 1.2)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 3.7 - seed, along * 8.0 - TIME * 2.4)).r;
	// a frente da energia sobe pela lâmina, rasgada pelo ruído
	float front = heat * 1.08 - 0.04 + (n - 0.5) * 0.08;
	if (h > front) {
		discard;
	}
	float front_line = 1.0 - smoothstep(0.0, 0.06, front - h);
	front_line *= step(heat, 0.999);
	// desfeita: some da ponta para as mãos, a borda do corte acesa
	float cut = 1.0 - dissolve * 1.2;
	float dd = h * 0.75 + n * 0.25;
	if (dissolve > 0.0 && dd > cut) {
		discard;
	}
	float dis_edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.07, cut - dd) : 0.0;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float edge = 1.0 - smoothstep(0.0, 0.09, UV.x);
	float ridge = smoothstep(0.93, 1.0, UV.x);
	// veias: linhas finas correndo para a ponta (só onde o ruído largo deixa: não vira pontilhado)
	float vein = (1.0 - smoothstep(0.0, 0.025, abs(n2 - 0.5))) * smoothstep(0.45, 0.7, n);
	vec3 c = smoke_col * (0.4 + 1.1 * n);
	c += rim_col * 0.35 * smoothstep(0.55, 0.9, n) * (1.0 - UV.x);
	c += rim_col * (edge * 2.4 + fres * 0.5) * (0.8 + 0.4 * n2);
	c += vein_col * (vein * 1.1 + ridge * 0.35);
	c += hot_col * (front_line * 2.2 + smoothstep(0.94, 1.0, h) * edge * 0.9 + dis_edge * 2.0);
	ALBEDO = c * intensity;
	ALPHA = clamp((0.9 + 0.1 * max(edge, fres)) * min(intensity, 1.0), 0.0, 1.0);
}
