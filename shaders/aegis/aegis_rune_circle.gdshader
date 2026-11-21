shader_type spatial;
// Égide Cristalina: círculo mágico no chão, desenhado por vetor (distâncias com fwidth): nítido de perto e de
// longe, sem textura esticada. O desenho é o da sprite sheet (quadros 1..14): borda dupla com uma faixa de
// runas, hexagrama inscrito, anel interno com runas miúdas e o emblema de escudo no meio, em branco-azulado
// com brilho azul em volta. `form` (0..1) refaz a ordem da sheet: a borda de runas corre em volta, o anel de
// dentro aparece, o hexagrama se traça e por fim o emblema acende. A faixa de runas e o hexagrama giram
// devagar em sentidos opostos (`spin`). Some em manchas (`erode`). Aditivo: só o brilho soma no chão.
// O material desenha depois das placas (render_priority 4): visto pela câmera, o miolo do círculo fica atrás
// do vidro da coroa, e desenhado antes o vidro apagava o brilho. Parâmetros comuns (não "instance"): cada círculo
// duplica o material (AegisGroundCircle.setup); com instance uniforms as dezenas de placas apagavam este.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 col_core : source_color = vec3(0.82, 0.93, 1.0);   // traço (quase branco)
uniform vec3 col_glow : source_color = vec3(0.22, 0.5, 1.0);    // brilho em volta do traço
uniform vec3 col_fill : source_color = vec3(0.1, 0.22, 0.55);   // véu dentro do círculo
uniform float line_px = 1.2;      // meia-largura mínima do traço em pixels (não some de longe)
uniform float glow_width = 0.022; // alcance do brilho (fração do raio)
uniform float form = 1.0;       // 0..1: formação
uniform float erode = 0.0;      // 0 = inteiro, 1 = sumiu
uniform float intensity = 1.0;
uniform float spin = 0.0;       // rad

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
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

// contorno de triângulo equilátero de "raio" r (vértice para cima, em +y)
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

// glifo de runa no quadrado [-1,1]: haste + 2 traços sorteados entre 6 pontos
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

// faixa de runas entre r0 e r1 com n glifos; devolve a distância ao traço (em unidades do raio)
float rune_band(vec2 p, float r, float r0, float r1, float n, float seed) {
	float th = atan(p.y, p.x);
	float sector = TAU / n;
	float k = floor((th + sector * 0.5) / sector);
	float a = th - k * sector;                     // ângulo dentro da fatia
	float h = (r1 - r0) * 0.5;
	vec2 q = vec2(a * r / (h * 0.75), (r - (r0 + r1) * 0.5) / h);
	if (abs(q.y) > 1.0 || abs(q.x) > 1.2) {
		return 9.0;
	}
	return rune(q, mod(k, n) + seed) * h * 0.75;
}

// escudo "heater" (topo reto, ponta embaixo no -y) de largura w e altura h, centrado
float shield(vec2 p, float w, float h) {
	float top = h * 0.45;
	float tip = -h * 0.55;
	float yy = clamp((top - p.y) / (top - tip), 0.0, 1.0);
	float u = max(yy - 0.45, 0.0) / 0.55;   // sem pow de base negativa (NaN na GPU)
	float hw = w * sqrt(max(0.0, 1.0 - u * u));
	return max(abs(p.x) - hw, max(p.y - top, tip - p.y));
}

// soma o traço `d` (meia-largura `wd`) com núcleo nítido e brilho
void stroke(inout vec3 core, inout float glow, float d, float wd, float vis, float px) {
	float fw = max(px, 0.00001);
	float w = max(wd, px * line_px);
	float c = 1.0 - smoothstep(w - fw, w + fw, d);
	core += vec3(c * vis);
	glow = max(glow, exp(-max(d - w, 0.0) / glow_width) * vis);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;     // -1..1
	p.y = -p.y;
	float r = length(p);
	if (r > 1.06) {
		discard;
	}
	float px = fwidth(r);          // tamanho do pixel em unidades do raio
	float ang = fract(atan(p.x, p.y) / TAU + 1.0);   // 0 em cima, horário
	// etapas da formação (a ordem da sheet)
	float f_outer = smoothstep(0.0, 0.35, form);     // a borda corre em volta
	float f_inner = smoothstep(0.25, 0.5, form);
	float f_hex = smoothstep(0.35, 0.78, form);
	float f_emb = smoothstep(0.72, 1.0, form);
	vec3 core = vec3(0.0);
	float glow = 0.0;
	// borda: anéis e a faixa de runas (gira com spin)
	float sweep = step(ang, f_outer * 1.001);
	stroke(core, glow, abs(r - 0.975), 0.0075, sweep, px);
	stroke(core, glow, abs(r - 0.945), 0.003, sweep, px);
	stroke(core, glow, abs(r - 0.855), 0.004, sweep, px);
	vec2 pr = rot(p, spin);
	stroke(core, glow, rune_band(pr, r, 0.865, 0.94, 36.0, 1.0), 0.0035, sweep, px);
	// anel de dentro com runas miúdas (cresce do centro)
	float in_vis = f_inner * step(r, 0.415 * (0.4 + 0.6 * f_inner) + 0.01);
	stroke(core, glow, abs(r - 0.4), 0.004, in_vis, px);   // dentro do hexágono do hexagrama (apótema 0,42)
	stroke(core, glow, abs(r - 0.335), 0.003, in_vis, px);
	stroke(core, glow, rune_band(rot(p, -spin * 1.5), r, 0.342, 0.393, 18.0, 9.0), 0.0025, in_vis, px);
	// hexagrama (gira ao contrário da faixa), traçado em volta
	vec2 ph = rot(p, -spin * 0.6);
	float hex_vis = step(fract(ang + 0.5), f_hex * 1.001) * step(0.01, f_hex);
	float t1 = tri(ph, 1.464);   // vértices em 0,845 do raio (o triângulo tem os vértices a 0,577 x r)
	float t2 = tri(-ph, 1.464);
	stroke(core, glow, abs(t1), 0.005, hex_vis, px);
	stroke(core, glow, abs(t2), 0.005, hex_vis, px);
	// pontinhos nas 6 pontas do hexagrama
	float a6 = atan(ph.y, ph.x) + PI * 0.5;
	float s6 = TAU / 6.0;
	float k6 = floor((a6 + s6 * 0.5) / s6);
	vec2 tipp = 0.845 * vec2(cos(k6 * s6 - PI * 0.5), sin(k6 * s6 - PI * 0.5));
	stroke(core, glow, length(ph - tipp), 0.012, hex_vis, px);
	// véu claro nas pontas da estrela (os triângulos de fora do hexágono)
	float in_star = step(min(t1, t2), 0.0) * step(0.4, r);
	// emblema de escudo
	float es = 0.5 + 0.5 * f_emb;
	vec2 pe = p / es;
	float sh = shield(pe, 0.17, 0.4) * es;
	stroke(core, glow, abs(sh), 0.006, f_emb, px);
	stroke(core, glow, abs(shield(pe, 0.13, 0.31) * es), 0.003, f_emb, px);
	stroke(core, glow, seg(pe, vec2(0.0, -0.12), vec2(0.0, 0.14)) * es, 0.003, f_emb, px);
	stroke(core, glow, seg(pe, vec2(-0.07, 0.07), vec2(0.07, 0.07)) * es, 0.003, f_emb, px);
	// véu dentro do círculo
	float veil = step(r, 0.975) * (0.05 + 0.1 * in_star * f_hex + 0.12 * step(sh, 0.0) * f_emb) * f_outer;
	vec3 col = col_core * min(core, vec3(1.0)) * 1.6 + col_glow * glow * 0.9 + col_fill * veil;
	// some em manchas
	float n = noise(p * 6.0) * 0.6 + noise(p * 15.0) * 0.4;
	float vis = step(erode * 1.08, 0.2 + n * 0.85);
	ALBEDO = col * intensity * vis;
	ALPHA = 1.0;
}
