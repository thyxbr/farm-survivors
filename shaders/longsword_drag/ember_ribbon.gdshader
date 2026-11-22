shader_type spatial;
// Corte do Abismo: as fitas de luz montadas a cada quadro por DragAndSlash (ImmediateMesh), com mistura ADITIVA.
//   UV.x = idade do ponto (0 = acabou de nascer, 1 = vai sumir)   UV.y = através da fita (0..1)
//   COLOR.a = brilho do ponto (a ponta da lâmina brilha mais que o cabo; o sulco esfria com a idade)
// Rastro da lâmina: branco quente na borda da frente (`lead`), laranja no meio e vermelho escuro no fim, com estrias de
// ruído que correm ao longo dele. Sulco no chão: a mesma rampa, mais estreita e com brasas piscando.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 hot = vec3(1.0, 0.93, 0.75);
uniform vec3 mid = vec3(1.0, 0.45, 0.09);
uniform vec3 cold = vec3(0.55, 0.06, 0.02);
uniform float hdr = 2.4;
// 0 = rastro da lâmina (UV.y 0 = o cabo, 1 = a ponta); 1 = sulco no chão (UV.y 0..1 através, o meio mais quente)
uniform int mode = 0;
uniform float streak_scale = 3.0;
uniform float flicker = 0.0;
instance uniform float intensity = 1.0;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = UV.y;
	float n = texture(noise_tex, vec2(UV.x * streak_scale - TIME * 0.6, across * 1.3)).r;
	float body;
	float heat;
	if (mode == 0) {
		// mais forte perto da ponta, some no cabo; a borda da frente (idade 0) é a mais quente
		body = smoothstep(0.0, 0.45, across) * (1.0 - smoothstep(0.96, 1.0, across));
		heat = (1.0 - smoothstep(0.0, 0.35, age)) * smoothstep(0.35, 1.0, across);
		body *= pow(1.0 - age, 1.6);
	} else {
		float d = abs(across - 0.5) * 2.0;
		body = 1.0 - smoothstep(0.25, 1.0, d);
		heat = (1.0 - smoothstep(0.0, 0.25, age)) * (1.0 - smoothstep(0.0, 0.45, d));
		body *= 1.0 - smoothstep(0.55, 1.0, age);
		// brasas: pontos que piscam
		float e = texture(noise_tex, vec2(UV.x * 9.0, across * 2.0 + TIME * 0.1)).r;
		body *= 0.65 + 0.7 * smoothstep(0.55, 0.8, e) * (0.6 + 0.4 * sin(TIME * 23.0 + e * 40.0));
	}
	vec3 c = mix(cold, mid, smoothstep(0.0, 0.6, 1.0 - age));
	c = mix(c, hot, heat);
	float streak = mix(0.55, 1.25, smoothstep(0.3, 0.75, n));
	float k = body * streak * COLOR.a * intensity * (1.0 + flicker * (n - 0.5));
	ALBEDO = c * k * (1.0 + (hdr - 1.0) * heat);
	ALPHA = 1.0;
}
