shader_type spatial;
// Selo no chão "desenhado" (plano 2x2 em XZ, UV 0..1): anel de pincel, anel fino de dentro, marcas
// radiais e uma cruz no centro. Borda dura, três tons chapados; o anel se desenha em volta (`head`)
// e some por erosão. Um material só: tudo o que muda vem por instância.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 0.9, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.35, 0.95, 0.5, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.05, 0.4, 0.35, 1.0);
instance uniform float head = 1.0;    // 0..1: quanto do anel já foi desenhado em volta
instance uniform float erode = 0.0;
instance uniform float seed = 0.0;
instance uniform float core = 1.0;    // 0 = sem núcleo claro (camada de sombra)
instance uniform float thick = 0.12;  // meia largura do anel de fora (raio = 1 na borda do plano)
instance uniform float glyph = 0.0;   // 1 = cruz no centro
instance uniform float ticks = 0.0;   // número de marcas radiais entre os anéis (0 = sem)
instance uniform float inner = 1.0;   // 1 = anel fino de dentro

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
	vec2 q = p / max(r, 0.001);
	float turn = fract(atan(p.y, p.x) / 6.2832 + 0.5);     // 0..1 em volta
	float n1 = noise(q * 2.4 + vec2(seed, seed * 1.7));
	float n2 = noise(q * 7.0 + vec2(r * 6.0 - seed * 2.0, 4.0));
	float streak = n1 * 0.65 + n2 * 0.35;
	// anel de fora: largura de pincel irregular, desenhado em volta até `head`
	float w = thick * (0.65 + 0.7 * n1);
	float d = 1.0 - abs(r - (0.84 - thick)) / w;
	d = min(d, (head * 1.08 - turn) * 14.0);
	// anel fino de dentro (gira ao contrário)
	float d2 = 1.0 - abs(r - 0.5) / (thick * 0.32);
	d2 = min(d2, (head * 1.08 - (1.0 - turn)) * 14.0);
	d = max(d, d2 * inner - (1.0 - inner) * 9.0);
	// marcas radiais entre os dois anéis
	if (ticks > 0.5) {
		float seg = abs(fract(turn * ticks) - 0.5) * 2.0;    // 1 no meio de cada marca
		float t = min((seg - 0.72) * 5.0, min((r - 0.56) * 22.0, (0.7 - r) * 22.0));
		d = max(d, min(t, (head - 0.35) * 8.0));
	}
	// cruz no centro
	if (glyph > 0.5) {
		vec2 ap = abs(p);
		float cr = max(min(0.075 - ap.x, 0.3 - ap.y), min(0.075 - ap.y, 0.3 - ap.x)) / 0.075;
		d = max(d, min(cr, (head - 0.2) * 8.0));
	}
	float m = d * 2.5;
	m = min(m, (streak * 0.8 + d * 0.5 - erode * 1.35) * 4.0);
	float fw = min(fwidth(m), 0.2) + 0.0001;
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	float mid_at = 0.28 + erode * 0.35;
	float core_at = 0.66 + (n2 - 0.5) * 0.2 + erode * 0.5;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(mid_at - fw, mid_at + fw, d));
	c = mix(c, col_core.rgb, smoothstep(core_at - fw, core_at + fw, d) * core);
	ALBEDO = c;
	ALPHA = alpha * col_mid.a;
}
