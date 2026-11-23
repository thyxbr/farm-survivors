shader_type spatial;
// Buraco Negro: o disco de acreção deitado no chão. Duas pinturas (claro em fundo preto) giradas no shader:
// `arms` (espiral_bracos.png, os braços em fios) em duas camadas de velocidades diferentes, o miolo girando mais
// depressa que a borda, e `haze` (espiral_nevoa.png, a névoa larga) por baixo. A cor vem do raio: amarelo-laranja
// junto do miolo, magenta no meio, violeta e azul fundo fora. Por baixo, uma poça escura (lê de dia) e um aro
// fino aceso em `rim_at` (fração do meio-lado do plano): é o limite do dano.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D arms : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D haze : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 hot = vec3(1.0, 0.55, 0.12);
uniform vec3 mid = vec3(1.0, 0.08, 0.42);
uniform vec3 cold = vec3(0.36, 0.1, 1.0);
uniform vec3 far = vec3(0.1, 0.08, 0.6);
uniform vec3 rim_col = vec3(1.0, 0.16, 0.4);
uniform float rim_at = 0.88;

instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float t = TIME;
	float tw = 1.3 * (1.0 - clamp(r, 0.0, 1.0));
	float a1 = texture(arms, rot(p, t * 0.95 + tw * 0.7 + seed) + 0.5).r;
	float a2 = texture(arms, rot(p * 1.22, t * 0.55 + tw * 0.4 + seed + 2.1) + 0.5).r;
	float hz = texture(haze, rot(p * 0.92, t * 0.28 + seed - 1.0) + 0.5).r;
	// fios finos: uma camada recorta a outra (onde as duas são claras fica o fio aceso)
	float arm = a1 * (0.3 + 0.7 * a2);
	float wide = max(a1, a2) * 0.5;
	vec3 c = mix(hot, mid, smoothstep(0.24, 0.5, r));
	c = mix(c, cold, smoothstep(0.45, 0.72, r));
	c = mix(c, far, smoothstep(0.66, 1.0, r));
	vec3 base = mix(vec3(0.02, 0.0, 0.05), far * 0.7, max(hz, wide));
	float bright = smoothstep(0.35, 0.9, arm);
	vec3 col = mix(base, c * (0.4 + 0.7 * bright), smoothstep(0.12, 0.55, arm));
	float rim = (1.0 - smoothstep(0.0, 0.022, abs(r - rim_at))) * (0.7 + 0.3 * sin(t * 4.0));
	col = mix(col, rim_col * 1.2, rim * 0.8);
	float pool = (1.0 - smoothstep(rim_at - 0.3, rim_at + 0.01, r)) * 0.6;
	float alpha = max(max(smoothstep(0.08, 0.45, arm), max(hz, wide) * 0.7), max(pool, rim * 0.9));
	alpha *= 1.0 - smoothstep(0.95, 1.0, r);
	ALBEDO = col;
	ALPHA = alpha * intensity;
}
