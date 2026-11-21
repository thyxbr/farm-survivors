shader_type spatial;
// Galáxia viva do Ceifador do Vazio: no disco atrás da cabeça e nas costas do manto. O pano continua
// iluminado em dois tons (toon_light) e a galáxia entra por cima como luz própria: fundo de espaço, névoa,
// braços em espiral que giram, miolo aceso e estrelas que cintilam, tudo em faixas chapadas (desenhado).
// O UV vem de tools/blender/gear.py (g_galaxy_uv): posição de repouso vista por trás, u = x + 0,5 e
// v = 1 - z / 2, em metros; (0, 1) marca face sem galáxia. Montado por GearFx (scripts/player/gear_fx.gd).
render_mode cull_back, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.086, 0.078, 0.11, 1.0);    // pano por baixo
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform vec2 center = vec2(0.0, 0.66);       // centro da galáxia (x, altura), metros
uniform float radius = 0.2;                  // raio dos braços
uniform vec2 squash = vec2(1.0, 1.0);        // achatamento (galáxia inclinada)
uniform float tilt = 0.0;                    // giro do eixo da elipse, rad
uniform float star_reach = 3.0;              // até onde vão as estrelas soltas, em raios
uniform float spin = 0.22;                   // voltas dos braços, rad/s
uniform float energy = 1.25;
uniform float core_gain = 1.1;              // miolo aceso (negativo = buraco negro no meio)
uniform vec3 space_col : source_color = vec3(0.07, 0.04, 0.19);
uniform vec3 haze_col : source_color = vec3(0.23, 0.12, 0.5);
uniform vec3 arm_col : source_color = vec3(0.54, 0.29, 0.91);
uniform vec3 hot_col : source_color = vec3(0.94, 0.63, 0.94);
uniform vec3 star_col : source_color = vec3(0.9, 0.8, 1.0);

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

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// estrelas de quatro pontas, uma por célula, cada uma piscando no seu tempo
float stars(vec2 p, float cell, float density, float t) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	float rnd = hash(id);
	if (rnd > density) {
		return 0.0;
	}
	vec2 o = vec2(hash(id + 3.1), hash(id + 9.7)) * 0.6 + 0.2;
	vec2 d = abs(fract(g) - o);
	float size = 0.1 + 0.22 * hash(id + 5.5);
	float tw = 0.55 + 0.45 * sin(t * (1.2 + 3.0 * hash(id + 1.3)) + rnd * 60.0);
	size *= tw;
	// losango esticado nos dois eixos = cruz de quatro pontas
	float cross4 = min(d.x * 4.0 + d.y, d.x + d.y * 4.0);
	return step(cross4, size) * step(0.25, tw);
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
		vec2 p = vec2(UV.x - 0.5, (1.0 - UV.y) * 2.0) - center;
		vec2 q = (rot(-tilt) * p) / (radius * squash);
		float r = length(q);
		float t = TIME;
		// borda do espaço: ondulada e respirando devagar, para não parecer um círculo recortado
		float wob = fbm(q * 2.2 + vec2(t * 0.05, -t * 0.04));
		float edge = 1.32 + 0.34 * (wob - 0.5) + 0.03 * sin(t * 0.7);
		float in_space = 1.0 - smoothstep(edge - 0.04, edge, r);
		// braços: espiral logarítmica de dois braços girando, engrossada e roída por ruído que gira junto
		float ang = atan(q.y, q.x) + t * spin;
		vec2 turn = rot(t * spin) * q;
		float dust = fbm(turn * 3.4 + 11.0);
		float arms = 0.5 + 0.5 * cos(2.0 * ang - 6.4 * log(r + 0.05));
		float fall = 1.0 - smoothstep(0.35, 1.25, r);
		float v = arms * arms * fall * (0.5 + 0.8 * dust) + 0.3 * fall * dust;
		float core = exp(-r * r * 30.0) * (1.0 + 0.12 * sin(t * 1.7));
		v += core * core_gain;
		vec3 c = space_col;
		c = mix(c, haze_col, smoothstep(0.2, 0.25, v));
		c = mix(c, arm_col, smoothstep(0.42, 0.47, v));
		c = mix(c, hot_col, smoothstep(0.68, 0.73, v));
		c = mix(c, vec3(1.0, 0.95, 1.0), smoothstep(1.2, 1.28, v));
		float lum = 0.75 + 0.45 * smoothstep(0.2, 0.25, v) + 0.4 * smoothstep(0.42, 0.47, v) + 0.35 * smoothstep(0.68, 0.73, v);
		glow = c * lum * in_space;
		cover = in_space;
		// estrelas: uma camada miúda e densa dentro do espaço, outra maior e rala que se espalha pelo pano
		float reach = 1.0 - smoothstep(star_reach * 0.45, star_reach, r);
		float s1 = stars(p + turn * 0.0, 0.021, 0.5, t) * in_space;
		float s2 = stars(p + 3.7, 0.046, 0.34, t * 0.8 + 4.0) * reach;
		glow += star_col * (s1 * 1.6 + s2 * 2.2);
	}
	ALBEDO = base * (1.0 - cover);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow * energy;
}
