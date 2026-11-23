shader_type spatial;
// Vórtice Sombrio: o corte aceso do giro (SwordVortexFX._build_edge). Não é uma linha chapada: são duas fitas em cruz
// (uma em pé, uma deitada) seguindo a borda da lente, que juntas formam um tubo de luz com espessura. Visto de lado ele
// é alto, visto de cima é largo, como um corte de verdade no espaço.
// Profundidade: o lado do anel virado para a câmera acende cheio; o do fundo fica fraco (atrás do herói e da fumaça).
// Malha: UV.x = voltas atrás da cabeça (0 = junto da lâmina), UV.y = atravessando o tubo (0..1); COLOR.a = força.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float gain = 3.0;

instance uniform vec3 glow_col = vec3(0.62, 0.28, 1.0);
instance uniform vec3 center = vec3(0.0);
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = clamp(UV.x, 0.0, 1.0);
	float y = clamp(UV.y, 0.0, 1.0) * 2.0 - 1.0;
	// seção do tubo: núcleo fino e quente no meio, brilho largo e macio em volta
	float core = exp(-y * y * 30.0);
	float soft = exp(-y * y * 4.0);
	if (COLOR.g < 0.5) {
		// saia: UV.y 0 = embaixo, 1 = na borda; luz que desce da borda e se apaga, com riscos verticais de velocidade
		float sk = pow(clamp(UV.y, 0.0, 1.0), 3.0);
		float st = texture(noise_tex, vec2(a * 18.0 - TIME * 3.0 + seed, 0.3)).r;
		core = 0.0;
		// só junto da lâmina (a saia é o rastro recente): some bem antes do resto do corte
		soft = sk * (0.3 + 0.9 * st) * 0.22 * (1.0 - smoothstep(0.0, 0.45, a));
	}
	// cabeça forte, apagando atrás; riscos correndo ao longo (movimento)
	float head = pow(1.0 - a, 1.4);
	float n = texture(noise_tex, vec2(a * 7.0 - TIME * 2.5 + seed, UV.y * 0.6)).r;
	// frente x fundo em relação à câmera
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 to_p = normalize(v_world.xz - center.xz + 1e-4);
	vec2 to_c = normalize(cam.xz - center.xz + 1e-4);
	float front = mix(0.2, 1.0, smoothstep(-0.6, 0.6, dot(to_p, to_c)));
	vec3 hot = mix(glow_col, vec3(1.0), 0.55 * pow(1.0 - a, 6.0));
	vec3 c = hot * core * 1.4 + glow_col * soft * 0.45;
	ALBEDO = c * head * (0.65 + 0.7 * n) * front * COLOR.a * gain * intensity;
	ALPHA = 1.0;
}
