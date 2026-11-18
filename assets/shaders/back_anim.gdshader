shader_type spatial;
// Pano animado das capas (galáxia e elementais). Substitui, no jogo, os materiais "fx_<tipo>" dos GLBs de
// assets/models/back (BackFx.anim_material). Usa o UV do pano: U atravessa a capa, V vai da gola (0) à barra (1).
// Os desenhos são em faixas chapadas (sem degradê liso), para combinar com o toon do resto do jogo.
render_mode cull_disabled;

// 0 galáxia · 1 fogo · 2 gelo · 3 tempestade · 4 floresta
uniform int mode = 0;
uniform vec4 base : source_color = vec4(0.08, 0.1, 0.35, 1.0);
uniform vec4 base2 : source_color = vec4(0.3, 0.12, 0.5, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 glow2 : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float speed = 1.0;
uniform float energy = 2.0;

#include "res://assets/shaders/toon_light.gdshaderinc"

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Estrelas de quatro pontas numa grade: cada casa sorteia se tem estrela, onde, e o ritmo em que pisca.
float stars(vec2 p, float density, float t) {
	vec2 g = p * density;
	vec2 id = floor(g);
	float h = hash(id);
	if (h < 0.7) {
		return 0.0;
	}
	vec2 f = fract(g) - 0.5 - (vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5) * 0.5;
	vec2 q = abs(f);
	float core = smoothstep(0.1, 0.02, length(f));
	float rays = smoothstep(0.035, 0.0, min(q.x, q.y)) * smoothstep(0.34, 0.0, max(q.x, q.y));
	float twinkle = 0.45 + 0.55 * sin(t * (1.2 + h * 4.0) + h * 40.0);
	return (core + rays * 0.8) * twinkle;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = vec2(UV.x, UV.y * 1.3);
	vec3 col = base.rgb;
	vec3 emi = vec3(0.0);
	if (mode == 0) {
		// nebulosa em duas cores que deriva devagar, estrelas piscando e uma estrela cadente de tempos em tempos
		float n = fbm(p * 3.0 + vec2(t * 0.03, -t * 0.02));
		float n2 = fbm(p * 5.0 - vec2(t * 0.025, 0.0) + n);
		col = mix(base.rgb, base2.rgb, step(0.5, n) * 0.6 + step(0.62, n) * 0.4);
		emi += glow2.rgb * (step(0.6, n2) * 0.25 + step(0.72, n2) * 0.35);
		emi += glow.rgb * (stars(p, 9.0, t) + stars(p + 5.3, 17.0, t * 1.3) * 0.7);
		float ph = fract(t * 0.11);
		vec2 head = vec2(1.15 - ph * 2.6, -0.2 + ph * 3.0);
		vec2 d = p - head;
		float along = dot(d, normalize(vec2(1.0, -1.15)));
		float across = abs(dot(d, normalize(vec2(1.15, 1.0))));
		emi += glow.rgb * smoothstep(0.012, 0.0, across) * smoothstep(0.32, 0.0, along) * step(0.0, along) * 1.5;
	} else if (mode == 1) {
		// labaredas que sobem da barra, em três faixas de cor
		float rise = smoothstep(0.0, 1.0, UV.y);
		float f = fbm(vec2(p.x * 5.0, p.y * 4.0 + t * 1.3)) * 1.5 * rise + rise * rise * 0.3;
		col = mix(base.rgb, base2.rgb, step(0.3, f));
		emi += glow2.rgb * step(0.5, f) * 0.7;
		emi += glow.rgb * step(0.78, f);
		emi += vec3(1.0, 0.9, 0.5) * step(1.05, f) * 0.2;
	} else if (mode == 2) {
		// facetas de gelo, um reflexo que varre a capa e brilhos piscando
		vec2 cell = floor(vec2(p.x * 7.0 + p.y * 3.0, p.y * 6.0 - p.x * 2.0));
		float facet = hash(cell);
		col = mix(base.rgb, base2.rgb, step(0.45, facet) * 0.5 + step(0.8, facet) * 0.5);
		float band = smoothstep(0.07, 0.0, abs(fract(p.x * 0.6 + p.y * 0.8 - t * 0.16) - 0.5));
		emi += glow2.rgb * band * 0.55;
		emi += glow.rgb * stars(p, 13.0, t * 1.6);
	} else if (mode == 3) {
		// nuvens escuras rolando e raios que mudam de desenho e piscam
		float cloud = fbm(p * 3.0 + vec2(t * 0.06, t * 0.03));
		col = mix(base.rgb, base2.rgb, step(0.45, cloud) * 0.5 + step(0.6, cloud) * 0.5);
		float seed = floor(t * 2.5);
		float ridge = abs(fbm(vec2(p.x * 4.0 + seed * 7.3, p.y * 3.0 - t * 0.3)) - 0.5);
		float line = smoothstep(0.03, 0.0, ridge);
		float flicker = step(0.45, hash(vec2(floor(t * 9.0), seed)));
		emi += glow.rgb * line * (0.25 + flicker * 1.5);
		emi += glow2.rgb * step(0.02, line) * flicker * 0.12;
	} else {
		// folhagem em dois verdes, cipós ondulando e pulsos de luz que descem por eles, com pólen piscando
		float n = fbm(p * 4.0 + vec2(0.0, t * 0.02));
		col = mix(base.rgb, base2.rgb, step(0.48, n) * 0.6 + step(0.62, n) * 0.4);
		float vine = smoothstep(0.1, 0.0, abs(sin(p.x * 16.0 + sin(p.y * 6.0 + t * 0.3) * 1.4)));
		float pulse = smoothstep(0.12, 0.0, abs(fract(p.y * 1.2 - t * 0.18) - 0.5));
		emi += glow.rgb * vine * (0.12 + pulse * 0.9);
		emi += glow2.rgb * stars(p, 11.0, t) * 0.8;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emi * energy;
}
