shader_type spatial;
// Pincelada de luz "desenhada" numa fita (HolyFX.ribbon_mesh: UV.x = 0 na cauda, 1 na ponta; UV.y
// atravessa a fita). Afina nas duas pontas, miolo claro, riscos de pincel nas beiradas, avança até
// `head`, a cauda vem atrás em `tail` e tudo some por erosão. Irmã do corte da espada (fx_slash).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 0.9, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.35, 0.95, 0.5, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.05, 0.4, 0.35, 1.0);
instance uniform float head = 1.0;
instance uniform float tail = 0.0;
instance uniform float erode = 0.0;
instance uniform float seed = 0.0;
instance uniform float core = 1.0;
instance uniform float len = 6.0;     // comprimento da fita em larguras (escala dos riscos)

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
	float u = UV.x;
	float span = max(head - tail, 0.001);
	float s = clamp((u - tail) / span, 0.0, 1.0);          // 0 na cauda, 1 na ponta
	float n1 = noise(vec2(u * len * 0.8 + seed, UV.y * 5.0 + seed * 3.1));
	float n2 = noise(vec2(u * len * 2.5 - seed * 2.0, UV.y * 14.0));
	float streak = n1 * 0.65 + n2 * 0.35;
	// gota: fina na cauda, gorda perto da ponta, fecha em ponta
	float prof = pow(s, 0.7) * (1.0 - pow(smoothstep(0.72, 1.0, s), 2.0));
	float w = max(prof * (0.75 + 0.35 * n1), 0.0001);
	float d = 1.0 - abs(UV.y - 0.5) * 2.0 / w;             // 1 no meio, 0 na beirada
	float m = min(d * 2.0, min(u - tail, head - u) * 40.0);
	m = min(m, (prof - 0.04) * 20.0);
	m = min(m, (streak - (0.5 - d * 1.3)) * 3.0);          // beiradas em riscos soltos
	float keep = streak * 0.55 + d * 0.3 + s * 0.4;
	m = min(m, (keep - erode * 1.3) * 3.0);
	float fw = min(fwidth(m), 0.2) + 0.0001;
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	float mid_at = 0.25 + (n1 - 0.5) * 0.25 + erode * 0.35;
	float core_at = mix(0.9, 0.6, smoothstep(0.2, 0.8, s)) + (n2 - 0.5) * 0.18 + erode * 0.5;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(mid_at - fw, mid_at + fw, d));
	c = mix(c, col_core.rgb, smoothstep(core_at - fw, core_at + fw, d) * core);
	ALBEDO = c;
	ALPHA = alpha * col_mid.a;
}
