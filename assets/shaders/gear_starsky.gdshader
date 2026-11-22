shader_type spatial;
// Céu estrelado vivo na capa das Placas Astrais (cavaleiro celeste): azul-noite escuro no alto clareando para
// a barra, nebulosa em faixas chapadas que passa devagar, uma camada de estrelas miúdas e outra de estrelas
// grandes de quatro pontas, cada uma piscando no seu tempo. O pano é a própria luz (sem sombra de forma).
// O UV vem de tools/blender/gear.py (g_galaxy_uv): posição de repouso, u = x + 0,5 e v = 1 - z / 2, em metros;
// (0, 0) marca face sem céu. Montado por GearFx (scripts/player/gear_fx.gd).
render_mode cull_back, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.1, 0.14, 0.38, 1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform float top_z = 1.05;                  // altura do azul mais escuro
uniform float cloth_z = 1.44;                // acima disto o pano é o azul liso do manto; degradê até top_z
uniform float bottom_z = 0.3;                // altura do azul mais claro
uniform float energy = 1.0;
uniform float drift = 0.02;                  // velocidade da nebulosa, m/s
uniform vec3 cloth_col : source_color = vec3(0.149, 0.188, 0.459);
uniform vec3 top_col : source_color = vec3(0.02, 0.03, 0.13);
uniform vec3 bottom_col : source_color = vec3(0.09, 0.22, 0.62);
uniform vec3 neb_col : source_color = vec3(0.3, 0.46, 0.95);
uniform vec3 star_col : source_color = vec3(1.0, 0.96, 0.86);
uniform float rings = 0.0;                   // anéis dourados ("planetas" do Cavaleiro Cósmico), 0 = sem
uniform float star_scale = 1.0;              // < 1 deixa as estrelas menores e mais juntas (janelas pequenas)

#include "res://assets/shaders/toon_light.gdshaderinc"

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.1 + 7.3) * 0.3 + noise(p * 4.3 + 1.7) * 0.1;
}

// anéis finos, um por célula, pulsando devagar
float ring_cells(vec2 p, float cell, float density, float t) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	if (hash(id + 7.7) > density) {
		return 0.0;
	}
	vec2 o = vec2(hash(id + 2.2), hash(id + 6.1)) * 0.5 + 0.25;
	float r = 0.12 + 0.12 * hash(id + 4.4);
	float d = abs(length(fract(g) - o) - r);
	float tw = 0.6 + 0.4 * sin(t * (0.6 + hash(id + 8.8)) + hash(id) * 40.0);
	return (1.0 - smoothstep(0.025, 0.05, d)) * tw;
}

// estrelas de quatro pontas, uma por célula, cada uma piscando no seu tempo
float stars(vec2 p, float cell, float density, float t, float arms) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	float rnd = hash(id);
	if (rnd > density) {
		return 0.0;
	}
	vec2 o = vec2(hash(id + 3.1), hash(id + 9.7)) * 0.6 + 0.2;
	vec2 d = abs(fract(g) - o);
	float size = 0.08 + 0.2 * hash(id + 5.5);
	float tw = 0.55 + 0.45 * sin(t * (1.0 + 2.6 * hash(id + 1.3)) + rnd * 60.0);
	size *= tw;
	float cross4 = min(d.x * arms + d.y, d.x + d.y * arms);
	return step(cross4, size) * step(0.2, tw);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		vec3 vc = COLOR.rgb;
		if (vertex_color_srgb) {
			vc = pow(vc, vec3(2.2));
		}
		base *= vc;
	}
	vec3 glow = vec3(0.0);
	float cover = 0.0;
	if (UV.x > 0.02) {
		vec2 p = vec2(UV.x - 0.5, (1.0 - UV.y) * 2.0);
		float t = TIME;
		float g = clamp((top_z - p.y) / (top_z - bottom_z), 0.0, 1.0);
		vec3 c = mix(top_col, bottom_col, smoothstep(0.0, 1.0, g));
		// nebulosa: duas faixas chapadas, mais fortes embaixo
		float n = fbm(p * vec2(3.0, 2.2) + vec2(t * drift, -t * drift * 0.7));
		c = mix(c, mix(bottom_col, neb_col, 0.5), smoothstep(0.55, 0.58, n) * (0.35 + 0.65 * g));
		c = mix(c, neb_col, smoothstep(0.7, 0.73, n) * g);
		float s1 = stars(p, 0.017 * star_scale, 0.55, t, 4.0);
		float s2 = stars(p + 3.7, 0.075 * star_scale, 0.2, t * 0.8 + 4.0, 7.0);
		s2 += rings * ring_cells(p + 1.3, 0.05 * star_scale, 0.3, t);
		// emenda com o manto: o azul liso escurece em céu e as estrelas vão aparecendo
		float sky = smoothstep(cloth_z, top_z, p.y);
		c = mix(cloth_col, c, smoothstep(0.0, 0.85, sky));
		glow = c + star_col * (s1 * 1.3 + s2 * 2.6) * smoothstep(0.25, 0.8, sky);
		// forma das dobras: o céu é luz própria, então a sombra vem da oclusão assada (cor do vértice) e de
		// quanto a face vira de lado para a câmera, em dois degraus chapados
		float ao = use_vertex_color ? COLOR.r : 1.0;
		float face = abs(dot(NORMAL, VIEW));
		float form = mix(0.5, 1.0, smoothstep(0.52, 0.58, face)) * mix(0.55, 1.0, smoothstep(0.55, 0.62, ao));
		glow *= form;
		cover = 1.0;
	}
	ALBEDO = base * (1.0 - cover);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow * energy;
}
