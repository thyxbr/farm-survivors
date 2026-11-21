shader_type spatial;
// Martelo de Energia: o corpo do martelo 3D (EnergyHammer). Energia azul elétrica com o contorno claro (fresnel),
// linhas de energia correndo pelo cabo, runas gravadas (glifos sorteados numa grade, no espaço do objeto) e os
// detalhes dourados (`accent` por peça, instance uniform). Branco no miolo e nas runas.
// Etapas (parâmetros do material, duplicado por martelo):
//   clip_y      altura (mundo) do círculo: acima dele nada aparece (o martelo sai de dentro do círculo), com a
//               borda acesa onde ele atravessa
//   solidity    0..1 = transparência parcial na formação -> inteiro
//   glow        brilho geral (cai depois do impacto)
//   crack       0..1 = rachaduras de energia na superfície (antes da dissolução)
//   dissolve_y  altura (mundo) até onde já se desfez (de baixo para cima: a cabeça primeiro, depois o cabo)
render_mode unshaded, cull_back, depth_prepass_alpha, shadows_disabled, blend_mix, fog_disabled;

uniform vec3 col_energy : source_color = vec3(0.1, 0.42, 1.0);
uniform vec3 col_rim : source_color = vec3(0.72, 0.9, 1.0);
uniform vec3 col_gold : source_color = vec3(1.0, 0.72, 0.22);
uniform float clip_y = 10000.0;
uniform float solidity = 1.0;
uniform float glow = 1.0;
uniform float crack = 0.0;
uniform float dissolve_y = -10000.0;
uniform float dissolve_band = 0.45;
uniform float rune_density = 3.2;
instance uniform float accent = 0.0;    // 0 = energia azul, 1 = dourado
instance uniform float runes = 1.0;     // 0 = sem runas nesta peça
instance uniform float core = 0.0;      // 1 = miolo branco (cristal)

varying vec3 wpos;
varying vec3 lpos;
varying vec3 lnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = 0.0;
	float a = hash(i.xy + i.z * 17.0);
	float b = hash(i.xy + vec2(1, 0) + i.z * 17.0);
	float c = hash(i.xy + vec2(0, 1) + i.z * 17.0);
	float d = hash(i.xy + vec2(1, 1) + i.z * 17.0);
	float e = hash(i.xy + (i.z + 1.0) * 17.0);
	float g = hash(i.xy + vec2(1, 0) + (i.z + 1.0) * 17.0);
	float h = hash(i.xy + vec2(0, 1) + (i.z + 1.0) * 17.0);
	float k = hash(i.xy + vec2(1, 1) + (i.z + 1.0) * 17.0);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float rune(vec2 q, float id) {
	vec2 pts[6] = vec2[](vec2(-0.55, -0.7), vec2(0.55, -0.7), vec2(0.0, 0.0), vec2(-0.55, 0.7), vec2(0.55, 0.7), vec2(0.0, -0.7));
	float d = seg(q, vec2(0.0, -0.8), vec2(0.0, 0.8));
	for (int i = 0; i < 2; i++) {
		int a = int(floor(hash(vec2(id, float(i) * 3.1)) * 6.0));
		int b = int(floor(hash(vec2(id + 7.3, float(i) * 1.7)) * 6.0));
		if (a == b) { b = (b + 2) % 6; }
		d = min(d, seg(q, pts[a], pts[b]));
	}
	return d;
}

// distância à borda das células de Voronoi (rachaduras)
float voronoi_edge(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(hash(i.xy + g.xy + (i.z + g.z) * 7.0), hash(i.yz + g.yz + 3.1), hash(i.zx + g.zx + 5.7));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return d2 - d1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lnorm = NORMAL;
}

void fragment() {
	// sai de dentro do círculo: acima do plano dele nada
	float above = wpos.y - clip_y;
	if (above > 0.0) {
		discard;
	}
	float n = noise3(wpos * 4.0 + vec3(0.0, TIME * 0.6, 0.0));
	// dissolução de baixo para cima com borda irregular
	float dd = wpos.y - dissolve_y + (n - 0.5) * dissolve_band;
	if (dd < 0.0) {
		discard;
	}
	vec3 nv = normalize(NORMAL);
	float fres = pow(1.0 - clamp(abs(dot(nv, VIEW)), 0.0, 1.0), 2.2);
	// runas: o plano da face (pela normal do objeto), grade de glifos
	vec3 an = abs(lnorm);
	vec2 uv = an.x > an.y && an.x > an.z ? lpos.zy : (an.y > an.z ? lpos.xz : lpos.xy);
	vec2 g = uv * rune_density;
	vec2 cell = floor(g);
	vec2 q = (fract(g) - 0.5) * 2.0;
	float rd = rune(q * 1.25, hash(cell) * 40.0 + floor(hash(cell + 3.3) * 4.0));
	float has = step(0.58, hash(cell + 9.1));
	float fw = fwidth(rd) + 0.0001;
	float rline = (1.0 - smoothstep(0.07 - fw, 0.07 + fw, rd)) * has * runes;
	// linhas de energia correndo ao longo do martelo
	float flow = smoothstep(0.96, 1.0, sin(lpos.y * 7.0 - TIME * 7.0 + n * 3.0)) * (1.0 - accent) * 0.6;
	// veias elétricas por dentro do azul: o meio fino das faixas de ruído, tremendo
	float nv2 = noise3(lpos * 3.2 + vec3(TIME * 0.9, -TIME * 1.3, 0.0));
	float vein = (1.0 - smoothstep(0.0, 0.035, abs(nv2 - 0.5))) * (1.0 - accent) * (1.0 - core);
	float flicker = 0.9 + 0.1 * sin(TIME * 31.0 + wpos.y * 5.0) * sin(TIME * 17.3);
	// sombreamento falso (o material é sem luz): as faces de cima e da frente mais claras, dá volume às peças
	float ndl = clamp(dot(nv, normalize(vec3(0.35, 0.75, 0.55))), 0.0, 1.0);
	float shade = 0.5 + 0.5 * ndl;
	vec3 energy = col_energy * (0.55 + 0.45 * n) * shade + vec3(0.02, 0.06, 0.2);
	vec3 gold = col_gold * (0.55 + 0.25 * n) * (0.45 + 0.75 * ndl);
	vec3 base = mix(energy, gold, accent);
	vec3 col = base + mix(col_rim, vec3(1.0, 0.9, 0.6), accent) * fres * (1.4 - 0.7 * accent);
	col += mix(vec3(0.75, 0.9, 1.0), vec3(1.0, 0.95, 0.75), accent) * rline * 2.0;
	col += col_rim * (flow + vein * 1.3);
	col = mix(col, vec3(1.3, 1.35, 1.45) * (0.85 + 0.3 * fres), core);
	// rachaduras de energia (brancas, com o miolo azul)
	float cr = 0.0;
	if (crack > 0.001) {
		float e = voronoi_edge(lpos * 3.4);
		float wv = 0.012 + 0.03 * crack;
		float fwe = fwidth(e) + 0.0001;
		cr = (1.0 - smoothstep(wv, wv + fwe, e)) * smoothstep(0.0, 0.35, crack * 1.2 - n * 0.4);
		col = mix(col * (1.0 - 0.4 * crack), vec3(1.5, 1.75, 2.0), cr);
	}
	// borda acesa onde atravessa o círculo e na frente da dissolução
	float edge_c = 1.0 - smoothstep(0.0, 0.18, -above);
	float edge_d = 1.0 - smoothstep(0.0, 0.16, dd);
	col += vec3(1.0, 0.85, 0.5) * edge_c * 2.5 + vec3(0.6, 0.85, 1.0) * edge_d * 3.0;
	col *= glow * flicker;
	float a = mix(0.28 + 0.5 * fres, 1.0, solidity);
	a = max(a, max(rline * 0.9, max(edge_c, edge_d)));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
