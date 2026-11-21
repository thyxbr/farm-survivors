shader_type spatial;
// Martelo de Energia: a onda de choque que corre pelo chão a partir do impacto (HammerImpact). Um anel deitado
// cujo raio cresce com `progress` (0..1 = do centro até a borda do quad), com a frente azul-branca, um rastro
// dourado atrás e poeira tremida na borda. Aditivo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 col_front : source_color = vec3(0.55, 0.8, 1.0);
uniform vec3 col_back : source_color = vec3(1.0, 0.62, 0.18);
uniform float progress = 0.0;
uniform float intensity = 1.0;
uniform float width = 0.09;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float wob = (noise(vec2(a * 6.0, progress * 4.0)) - 0.5) * 0.05;
	float front = progress + wob;
	float d = r - front;
	// frente fina e forte, rastro largo e dourado atrás
	float ring = exp(-pow(d / (width * 0.35), 2.0));
	float wake = smoothstep(-width * 1.8, 0.0, d) * (1.0 - smoothstep(0.0, width * 0.4, d)) * step(d, 0.0);
	float dust = noise(p * 18.0 + progress * 3.0);
	vec3 col = col_front * ring * 2.4 + col_back * wake * (0.25 + 0.75 * dust) * 0.45;
	float fade = 1.0 - smoothstep(0.65, 1.0, progress);
	ALBEDO = col * intensity * fade * step(r, 1.0);
	ALPHA = 1.0;
}
