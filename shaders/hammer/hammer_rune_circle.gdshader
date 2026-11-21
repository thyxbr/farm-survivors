shader_type spatial;
// Martelo de Energia: o círculo mágico desenhado por vetor (distâncias com fwidth: nítido de perto e de longe),
// por baixo/cima do quadro da sprite sheet (MagicCircle). Borda dupla com uma faixa de runas, hexagrama inscrito,
// anel de dentro com runas miúdas e um martelo no meio; traço dourado com brilho e o miolo azul.
// `form` (0..1) materializa (a borda corre em volta, o anel de dentro aparece, o hexagrama se traça, o emblema
// acende) com faíscas tremendo na frente do traço. `contract` (0..1) fecha: cada anel se contrai para o centro
// numa velocidade (o de fora primeiro), as runas se apertam e o brilho sobe até virar um ponto.
// Aditivo: o preto não soma nada. Material duplicado por círculo (MagicCircle.setup).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 col_core : source_color = vec3(1.0, 0.9, 0.62);
uniform vec3 col_glow : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 col_inner : source_color = vec3(0.25, 0.55, 1.0);
uniform float line_px = 1.1;
uniform float glow_width = 0.03;
uniform float form = 1.0;
uniform float contract = 0.0;
uniform float intensity = 1.0;
uniform float spin = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float tri(vec2 p, float r) {
	const float k = 1.7320508;
	p.y = -p.y;
	p /= r * 0.5;
	p.x = abs(p.x) - 1.0;
	p.y = p.y + 1.0 / k;
	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}
	p.x -= clamp(p.x, -2.0, 0.0);
	return -length(p) * sign(p.y) * r * 0.5;
}

float box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float rune(vec2 q, float id) {
	vec2 pts[6] = vec2[](vec2(-0.6, -0.8), vec2(0.6, -0.8), vec2(0.0, 0.0), vec2(-0.6, 0.8), vec2(0.6, 0.8), vec2(0.0, -0.8));
	float d = seg(q, vec2(0.0, -0.9), vec2(0.0, 0.9));
	for (int i = 0; i < 2; i++) {
		int a = int(floor(hash(vec2(id, float(i) * 3.1)) * 6.0));
		int b = int(floor(hash(vec2(id + 7.3, float(i) * 1.7)) * 6.0));
		if (a == b) { b = (b + 2) % 6; }
		d = min(d, seg(q, pts[a], pts[b]));
	}
	return d;
}

float rune_band(vec2 p, float r, float r0, float r1, float n, float seed) {
	float th = atan(p.y, p.x);
	float sector = TAU / n;
	float k = floor((th + sector * 0.5) / sector);
	float a = th - k * sector;
	float h = (r1 - r0) * 0.5;
	vec2 q = vec2(a * r / (h * 0.75), (r - (r0 + r1) * 0.5) / h);
	if (abs(q.y) > 1.0 || abs(q.x) > 1.2) {
		return 9.0;
	}
	return rune(q, mod(k, n) + seed) * h * 0.75;
}

void stroke(inout vec3 core, inout float glow, float d, float wd, float vis, float px) {
	float fw = max(px, 0.00001);
	float w = max(wd, px * line_px);
	float c = 1.0 - smoothstep(w - fw, w + fw, d);
	core += vec3(c * vis);
	glow = max(glow, exp(-max(d - w, 0.0) / glow_width) * vis);
}

void fragment() {
	vec2 p0 = (UV - 0.5) * 2.0;
	p0.y = -p0.y;
	float r0 = length(p0);
	if (r0 > 1.06) {
		discard;
	}
	float px0 = fwidth(r0);
	// fechamento: cada camada encolhe na sua velocidade (o de fora primeiro); s = escala da camada
	float c_out = clamp(contract * 1.25, 0.0, 1.0);
	float c_mid = clamp(contract * 1.1 - 0.05, 0.0, 1.0);
	float c_in = clamp(contract * 0.95 - 0.05, 0.0, 1.0);
	float s_out = max(1.0 - c_out * c_out * (3.0 - 2.0 * c_out), 0.02);
	float s_mid = max(1.0 - c_mid * c_mid * (3.0 - 2.0 * c_mid), 0.02);
	float s_in = max(1.0 - c_in * c_in * (3.0 - 2.0 * c_in), 0.02);
	float twist = contract * contract * 6.0;   // as runas apertam girando
	float ang0 = fract(atan(p0.x, p0.y) / TAU + 1.0);
	float f_outer = smoothstep(0.0, 0.35, form);
	float f_inner = smoothstep(0.25, 0.5, form);
	float f_hex = smoothstep(0.35, 0.78, form);
	float f_emb = smoothstep(0.72, 1.0, form);
	vec3 core = vec3(0.0);
	vec3 inner = vec3(0.0);
	float glow = 0.0;
	float iglow = 0.0;
	// borda (anéis e faixa de runas)
	{
		vec2 p = p0 / s_out;
		float r = length(p);
		float px = px0 / s_out;
		float sweep = step(ang0, f_outer * 1.001);
		stroke(core, glow, abs(r - 0.975), 0.009, sweep, px);
		stroke(core, glow, abs(r - 0.94), 0.0035, sweep, px);
		stroke(core, glow, abs(r - 0.85), 0.005, sweep, px);
		stroke(core, glow, rune_band(rot(p, spin + twist), r, 0.86, 0.935, 32.0, 3.0), 0.004, sweep, px);
		// faíscas na frente do traço enquanto corre
		float head = abs(fract(ang0 - f_outer + 1.0));
		float spark = (1.0 - smoothstep(0.0, 0.025, min(head, 1.0 - head))) * step(f_outer, 0.999) * step(0.001, form);
		glow = max(glow, spark * exp(-abs(r - 0.96) * 30.0) * 2.0);
	}
	// hexagrama
	{
		vec2 p = p0 / s_mid;
		float r = length(p);
		float px = px0 / s_mid;
		vec2 ph = rot(p, -spin * 0.7 - twist * 0.6);
		float hex_vis = step(fract(ang0 + 0.5), f_hex * 1.001) * step(0.01, f_hex);
		stroke(core, glow, abs(tri(ph, 1.44)), 0.006, hex_vis, px);
		stroke(core, glow, abs(tri(-ph, 1.44)), 0.006, hex_vis, px);
		float a6 = atan(ph.y, ph.x) + PI * 0.5;
		float s6 = TAU / 6.0;
		float k6 = floor((a6 + s6 * 0.5) / s6);
		vec2 tipp = 0.832 * vec2(cos(k6 * s6 - PI * 0.5), sin(k6 * s6 - PI * 0.5));
		stroke(core, glow, length(ph - tipp), 0.016, hex_vis, px);
	}
	// anel de dentro (azul) e o martelo no meio
	{
		vec2 p = p0 / s_in;
		float r = length(p);
		float px = px0 / s_in;
		float in_vis = f_inner * step(r, 0.42 * (0.4 + 0.6 * f_inner) + 0.01);
		stroke(inner, iglow, abs(r - 0.4), 0.005, in_vis, px);
		stroke(inner, iglow, abs(r - 0.33), 0.0035, in_vis, px);
		stroke(inner, iglow, rune_band(rot(p, -spin * 1.6 - twist * 1.3), r, 0.338, 0.392, 16.0, 11.0), 0.003, in_vis, px);
		vec2 pe = p / (0.55 + 0.45 * f_emb);
		float hm = min(box(pe - vec2(0.0, 0.08), vec2(0.15, 0.07)), box(pe + vec2(0.0, 0.06), vec2(0.022, 0.13)));
		stroke(core, glow, abs(hm), 0.006, f_emb, px);
		inner += vec3(step(hm, 0.0) * f_emb * 0.25);
	}
	float veil = step(r0, 0.975 * s_out) * 0.07 * f_outer;
	vec3 col = col_core * min(core, vec3(1.0)) * 1.7 + col_glow * glow + col_inner * (min(inner, vec3(1.0)) * 1.6 + vec3(iglow * 0.8))
		+ col_glow * veil;
	// o ponto de luz em que o círculo se fecha
	float pinch = smoothstep(0.55, 1.0, contract);
	col += vec3(1.0, 0.95, 0.85) * exp(-r0 * 14.0) * pinch * 3.0;
	col *= 1.0 + contract * 1.2;
	ALBEDO = col * intensity;
	ALPHA = 1.0;
}
