shader_type spatial;
// Corte "desenhado": uma pincelada em arco (malha de FXToon.arc_mesh: UV.x ao longo do arco, da cauda à
// ponta; UV.y da borda de dentro à de fora). Borda dura, três tons chapados (núcleo, meio, sombra), riscos
// de pincel na parte de dentro e sumiço por erosão em vez de transparência.
// Um material só para todos os cortes: tudo o que muda vem por instância (sem shader novo por golpe).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.55, 0.8, 1.0, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.12, 0.2, 0.45, 1.0);
instance uniform float head = 1.0;    // 0..1: até onde a pincelada já chegou
instance uniform float tail = 0.0;    // 0..1: onde ela começa (sobe quando a cauda some)
instance uniform float erode = 0.0;   // 0 = inteira, 1 = sumiu
instance uniform float seed = 0.0;
instance uniform float arc = 3.0;     // ângulo do arco em radianos (escala dos riscos)
instance uniform float thick = 1.0;   // 0..1: largura máxima em relação à malha
instance uniform float core = 1.0;    // 0 = sem núcleo claro (camada de sombra)
instance uniform float peak = 0.5;    // 0..1: onde a forma é mais gorda (perto de 1 = lança, gorda na ponta)
instance uniform float blunt = 0.0;   // 1 = a cauda não afina (base larga: estilhaço, fissura que sai de um ponto)

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
	float v = UV.y;
	float span = max(head - tail, 0.001);
	float s = clamp((u - tail) / span, 0.0, 1.0);          // 0 na cauda, 1 na ponta
	float a = u * arc;
	// riscos compridos ao longo do arco (pincel) e um grão mais fino
	float n1 = noise(vec2(a * 1.6 + seed, v * 7.0 + seed * 3.1));
	float n2 = noise(vec2(a * 5.0 - seed * 2.0, v * 19.0));
	float streak = n1 * 0.65 + n2 * 0.35;
	// perfil de meia-lua: afina até um ponto na cauda e fecha em ponta na frente (mais gorda depois do meio)
	float prof = mix(pow(s, 0.6), 1.0, blunt) * (1.0 - pow(smoothstep(peak, 1.0, s), 1.7));
	float w = max(prof * thick * (0.8 + 0.4 * n1), 0.0001);
	float d = (v - (1.0 - w)) / w;                         // 0 na borda de dentro, 1 na de fora
	// dentro da forma
	float m = min(d, min(u - tail, head - u) * 40.0);
	m = min(m, (prof - 0.04) * 20.0);                      // sem fio solto onde a forma já fechou
	// falhas de pincel: a metade de dentro é feita de riscos soltos
	m = min(m, (streak - (0.58 - d * 1.25)) * 3.0);
	// erosão: cauda e borda de dentro somem primeiro
	float keep = streak * 0.55 + d * 0.3 + s * 0.4;
	m = min(m, (keep - erode * 1.3) * 3.0);
	float fw = min(fwidth(m), 0.2) + 0.0001;             // nas quebras do ruído a derivada explode: sem fio
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	// três tons chapados: o núcleo só perto da ponta e da borda de fora
	float core_at = mix(0.98, 0.74, smoothstep(0.2, 0.75, s)) + (n2 - 0.5) * 0.18 + erode * 0.5;
	float mid_at = 0.28 + (n1 - 0.5) * 0.3 + erode * 0.35;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(mid_at - fw, mid_at + fw, d));
	c = mix(c, col_core.rgb, smoothstep(core_at - fw, core_at + fw, d) * core);
	ALBEDO = c;
	ALPHA = alpha * col_mid.a;
}
