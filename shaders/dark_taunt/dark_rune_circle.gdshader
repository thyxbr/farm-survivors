shader_type spatial;
// Círculo da Provocação Sombria: o círculo mágico no chão, desenhado por vetor (distâncias com fwidth: nítido de
// perto e de longe). De fora para dentro: borda dupla com uma faixa de runas (gira num sentido), hexagrama com
// círculos nas pontas (gira no outro), anel de dentro com runas miúdas (gira de novo no primeiro sentido, mais
// rápido) e um olho fendido no meio. Um véu escuro de fumaça cobre o disco (o chão fica em sombra) e o traço é
// violeta com o miolo magenta, em HDR.
//   `form` 0..1   desenha: a borda corre em volta, o anel de dentro corre ao contrário, o hexagrama se traça e o
//                 olho abre, com faíscas na ponta de cada traço (energia sombria desenhando).
//   `fade` 0..1   dissipa: as runas se desfazem em manchas (as partículas saem do DarkMagicCircle), o brilho cai,
//                 o véu se espalha e some.
//   `contract` 0..1  os anéis se contraem para o centro, o de fora primeiro.
// Mistura normal (o véu escuro precisa cobrir; os traços passam de 1 e brilham). Material duplicado por círculo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform vec3 col_line : source_color = vec3(0.34, 0.1, 0.95);
uniform vec3 col_hot : source_color = vec3(0.95, 0.2, 0.72);
uniform vec3 col_veil : source_color = vec3(0.025, 0.0, 0.05);
uniform float line_px = 1.1;
uniform float glow_width = 0.035;
uniform float veil_alpha = 0.72;
uniform float form = 1.0;
uniform float fade = 0.0;
uniform float contract = 0.0;
uniform float intensity = 1.0;
uniform float spin = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
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

// runa: um traço vertical e dois tortos sorteados entre seis pontos (cada setor tem a sua)
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

// faixa de runas entre r0 e r1, `n` setores; devolve a distância e o id do setor (para desfazer runa a runa)
vec2 rune_band(vec2 p, float r, float r0, float r1, float n, float seed) {
	float th = atan(p.y, p.x);
	float sector = TAU / n;
	float k = floor((th + sector * 0.5) / sector);
	float a = th - k * sector;
	float h = (r1 - r0) * 0.5;
	vec2 q = vec2(a * r / (h * 0.75), (r - (r0 + r1) * 0.5) / h);
	float id = mod(k, n) + seed;
	if (abs(q.y) > 1.0 || abs(q.x) > 1.2) {
		return vec2(9.0, id);
	}
	return vec2(rune(q, id) * h * 0.75, id);
}

void stroke(inout float core, inout float glow, float d, float wd, float vis, float px) {
	float fw = max(px, 0.00001);
	float w = max(wd, px * line_px);
	float c = 1.0 - smoothstep(w - fw, w + fw, d);
	core += c * vis;
	glow = max(glow, exp(-max(d - w, 0.0) / glow_width) * vis);
}

void fragment() {
	vec2 p0 = (UV - 0.5) * 2.0;
	p0.y = -p0.y;
	float r0 = length(p0);
	if (r0 > 1.08) {
		discard;
	}
	float px0 = fwidth(r0);
	float c_out = clamp(contract * 1.25, 0.0, 1.0);
	float c_mid = clamp(contract * 1.1 - 0.05, 0.0, 1.0);
	float c_in = clamp(contract * 0.95 - 0.05, 0.0, 1.0);
	float s_out = max(1.0 - c_out * c_out * (3.0 - 2.0 * c_out), 0.02);
	float s_mid = max(1.0 - c_mid * c_mid * (3.0 - 2.0 * c_mid), 0.02);
	float s_in = max(1.0 - c_in * c_in * (3.0 - 2.0 * c_in), 0.02);
	float ang0 = fract(atan(p0.x, p0.y) / TAU + 1.0);
	float f_outer = smoothstep(0.0, 0.45, form);
	float f_inner = smoothstep(0.2, 0.6, form);
	float f_hex = smoothstep(0.4, 0.85, form);
	float f_eye = smoothstep(0.75, 1.0, form);
	float core = 0.0;
	float glow = 0.0;
	float hotness = 0.0;
	// as runas somem uma a uma na dissipação (id sorteado contra o avanço)
	float rune_keep = 1.0;
	// borda: anéis e faixa de runas (sentido horário)
	{
		vec2 p = p0 / s_out;
		float r = length(p);
		float px = px0 / s_out;
		float sweep = step(ang0, f_outer * 1.001);
		stroke(core, glow, abs(r - 0.975), 0.008, sweep, px);
		stroke(core, glow, abs(r - 0.945), 0.0035, sweep, px);
		stroke(core, glow, abs(r - 0.80), 0.005, sweep, px);
		vec2 rb = rune_band(rot(p, spin), r, 0.815, 0.93, 28.0, 3.0);
		rune_keep = step(fade * 1.15, hash(vec2(rb.y, 4.1)) * 0.9 + 0.05);
		stroke(core, glow, rb.x, 0.0045, sweep * rune_keep, px);
		// marcas em volta da borda (dentes que giram no outro sentido)
		float tick = abs(fract(atan(rot(p, -spin * 0.6).y, rot(p, -spin * 0.6).x) / TAU * 56.0) - 0.5);
		stroke(core, glow, max(abs(r - 1.0) - 0.022, tick * 0.06), 0.0015, sweep * 0.8, px);
		// faísca na ponta do traço enquanto corre
		float head = abs(fract(ang0 - f_outer + 1.0));
		float spark = (1.0 - smoothstep(0.0, 0.03, min(head, 1.0 - head))) * step(f_outer, 0.999) * step(0.001, form);
		glow = max(glow, spark * exp(-abs(r - 0.96) * 26.0) * 2.4);
		hotness = max(hotness, spark);
	}
	// hexagrama (anti-horário) e os círculos nas pontas
	{
		vec2 p = p0 / s_mid;
		float px = px0 / s_mid;
		vec2 ph = rot(p, -spin * 0.8);
		float hex_vis = step(fract(ang0 + 0.5), f_hex * 1.001) * step(0.01, f_hex);
		stroke(core, glow, abs(tri(ph, 1.38)), 0.005, hex_vis, px);
		stroke(core, glow, abs(tri(-ph, 1.38)), 0.005, hex_vis, px);
		float a6 = atan(ph.y, ph.x) + PI * 0.5;
		float s6 = TAU / 6.0;
		float k6 = floor((a6 + s6 * 0.5) / s6);
		vec2 tipp = 0.8 * vec2(cos(k6 * s6 - PI * 0.5), sin(k6 * s6 - PI * 0.5));
		float dt = length(ph - tipp);
		stroke(core, glow, abs(dt - 0.055), 0.004, hex_vis, px);
		stroke(core, glow, dt, 0.012, hex_vis * rune_keep, px);
		hotness = max(hotness, (1.0 - smoothstep(0.0, 0.03, dt)) * hex_vis);
	}
	// anel de dentro (horário, mais rápido) e o olho fendido no meio
	{
		vec2 p = p0 / s_in;
		float r = length(p);
		float px = px0 / s_in;
		float in_ang = fract(-atan(p.x, p.y) / TAU + 1.0);
		float in_vis = step(in_ang, f_inner * 1.001) * step(0.01, f_inner);
		stroke(core, glow, abs(r - 0.4), 0.005, in_vis, px);
		stroke(core, glow, abs(r - 0.32), 0.003, in_vis, px);
		vec2 rb = rune_band(rot(p, spin * 1.7), r, 0.328, 0.392, 14.0, 11.0);
		stroke(core, glow, rb.x, 0.003, in_vis * step(fade * 1.15, hash(vec2(rb.y, 2.3)) * 0.9 + 0.05), px);
		// olho: amêndoa com a pupila fendida (o mesmo olhar dos provocados)
		vec2 pe = p / (0.6 + 0.4 * f_eye);
		float lid = abs(length(pe - vec2(0.0, -0.13)) - 0.2);
		lid = min(lid, abs(length(pe - vec2(0.0, 0.13)) - 0.2));
		lid = max(lid, abs(pe.x) - 0.16);
		stroke(core, glow, lid, 0.005, f_eye, px);
		float pupil = max(abs(pe.x) - 0.018 * (1.0 + 0.3 * sin(TIME * 3.0)), abs(pe.y) - 0.065);
		stroke(core, glow, max(pupil, 0.0), 0.004, f_eye, px);
		hotness = max(hotness, (1.0 - smoothstep(0.0, 0.08, length(pe))) * f_eye);
	}
	core = min(core, 1.0);
	// véu de sombra no disco: fumaça escura girando devagar, mais densa perto da borda
	float smoke = fbm(rot(p0, TIME * 0.12) * 3.0 + vec2(TIME * 0.15, -TIME * 0.1));
	float disc = (1.0 - smoothstep(0.93 * s_out, 1.0 * s_out, r0)) * f_outer;
	float veil = disc * veil_alpha * mix(0.55, 1.0, smoothstep(0.2, 0.95, r0)) * (0.7 + 0.6 * smoke);
	veil *= 1.0 - smoothstep(0.0, 1.0, fade);
	// filetes de energia correndo no véu (veias violeta)
	float vein = smoothstep(0.62, 0.7, fbm(rot(p0, -TIME * 0.2) * 5.0 + TIME * 0.3)) * disc * 0.35 * (1.0 - fade);
	float light = (1.0 - fade) * (1.0 - fade);
	vec3 line = mix(col_line, col_hot, clamp(hotness + core * 0.25, 0.0, 1.0));
	vec3 col = line * (core * 1.7 + glow * 0.75 + vein) * light * intensity;
	float lines_a = clamp(core + glow * 0.8 + vein, 0.0, 1.0) * light;
	// o ponto em que os anéis se fecham
	float pinch = smoothstep(0.55, 1.0, contract);
	col += col_hot * exp(-r0 * 16.0) * pinch * 3.0;
	ALBEDO = mix(col_veil, col / max(lines_a, 0.001), lines_a);
	ALPHA = clamp(max(veil, lines_a) + exp(-r0 * 16.0) * pinch, 0.0, 1.0);
}
