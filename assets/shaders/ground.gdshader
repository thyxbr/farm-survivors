// Chão do mapa: grama com manchas (ruído em espaço de mundo) e trilhas/clareiras pintadas por
// formas (retângulos e discos) com bordas irregulares. As formas vêm de scripts/world/ground.gd.
shader_type spatial;
render_mode diffuse_burley;

#include "res://assets/shaders/ground_common.gdshaderinc"
#include "res://assets/shaders/toon_light.gdshaderinc"

const int MAX_SHAPES = 64;
uniform vec4 shapes[MAX_SHAPES];      // retângulo: (cx, cz, meia_x, meia_z); disco: (cx, cz, raio, -1)
uniform float shape_ang[MAX_SHAPES];  // giro do retângulo em Y (radianos, como o rotation.y do nó)
uniform vec4 shape_cols[MAX_SHAPES];  // rgb linear + maciez da borda (m)
uniform float shape_grass[MAX_SHAPES]; // 0 = terra lisa; > 0 = grama baixa/pisada manchada com a cor
uniform int shape_count = 0;
const int MAX_RIVER = 192;
uniform vec4 river[MAX_RIVER];   // caminho dos rios (MapRiver): (x, z, meia largura sem chão, 1 = início de um rio)
uniform int river_count = 0;
uniform vec4 river_box;          // retângulo que contém os rios (min x, min z, max x, max z)

// Clima (scripts/autoload/weather.gd, publicado pelo WeatherFX): água no chão, neve acumulada e
// chuva caindo agora (respingos nas poças). Fora de Valdoria/praça ficam em 0.
global uniform float weather_wet;
global uniform float weather_snow;
global uniform float weather_rain;

varying vec2 wxz;

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float sd_box(vec2 p, vec2 h) {
	vec2 d = abs(p) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Respingos de chuva: um anel que abre e some por célula de `cell` metros, cada célula num
// tempo diferente. Devolve a inclinação (gradiente xz) da superfície da água.
vec2 ripple(vec2 p, float cell, float t) {
	vec2 q = p / cell;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash12(id);
	f -= (vec2(h, fract(h * 7.31)) - 0.5) * 0.5;
	float ph = fract(t * 1.4 + h * 9.0);
	float d = length(f) + 1e-4;
	float r = ph * 0.42;
	float x = (d - r) * 28.0;
	float wave = cos(x * 3.14159) * exp(-x * x) * (1.0 - ph);
	return f / d * wave;
}

void fragment() {
	// rio: o chão some na faixa do leito (a margem e a água ficam por baixo, no MapRiver)
	if (river_count > 1 && wxz.x > river_box.x && wxz.y > river_box.y && wxz.x < river_box.z && wxz.y < river_box.w) {
		for (int i = 1; i < river_count; i++) {
			vec4 b = river[i];
			if (b.w > 0.5) {
				continue;
			}
			vec2 a = river[i - 1].xy;
			vec2 ab = b.xy - a;
			float h = clamp(dot(wxz - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
			if (length(wxz - a - ab * h) < b.z) {
				discard;
			}
		}
	}
	vec3 grass = grass_color(wxz);
	vec3 col = grass;
	float n2 = texture(noise_tex, wxz * 0.047 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise_tex, wxz * 0.23 + vec2(0.71, 0.53)).r;
	float n4 = texture(noise_tex, wxz * 1.3).r;
	col *= 0.95 + 0.1 * n4;
	float edge_n = (n2 - 0.5) * 1.4 + (n3 - 0.5) * 0.6;
	float dirt = 0.0;   // quanto deste ponto é terra/pedra lisa (sem grama): poças nascem mais aí
	for (int i = 0; i < shape_count; i++) {
		vec4 s = shapes[i];
		vec4 c = shape_cols[i];
		vec2 dp = wxz - s.xy;
		float ca = cos(shape_ang[i]);
		float sa = sin(shape_ang[i]);
		float d = s.w < 0.0 ? length(dp) - s.z : sd_box(vec2(dp.x * ca - dp.y * sa, dp.x * sa + dp.y * ca), s.zw);
		float soft = c.a;
		d += edge_n * soft;
		float a = 1.0 - smoothstep(-soft * 0.3 - 0.02, soft * 0.3 + 0.02, d);
		// terra batida: pedrisco claro e marcas escuras
		vec3 sc = c.rgb * (0.85 + 0.25 * n3) * (0.9 + 0.2 * n4);
		float g = shape_grass[i];
		if (g > 0.0) {
			// grama baixa: a grama do chão tingida pela cor da forma, com manchas gastas
			// (mais claras e secas) onde o ruído médio sobe e riscos finos de pisada
			float worn = smoothstep(0.5, 0.72, n3) * 0.6 + smoothstep(0.55, 0.8, n4) * 0.25;
			vec3 low = mix(grass, c.rgb, 0.35) * (0.95 + 0.1 * n4);
			sc = mix(sc, mix(low, sc * 1.05, worn), g);
		}
		col = mix(col, sc, a);
		dirt = mix(dirt, 1.0 - g, a);
	}
	// Outono: folhas caídas espalhadas pela grama (menos nas trilhas), em tons de fogo.
	if (season_autumn > 0.0) {
		float lf = texture(noise_tex, wxz * 2.9 + vec2(0.19, 0.83)).r * 0.7 + n4 * 0.3;
		float patchy = smoothstep(0.35, 0.65, texture(noise_tex, wxz * 0.13 + vec2(0.61, 0.07)).r);
		float th_l = 0.66 - 0.08 * patchy;
		float leaf = smoothstep(th_l, th_l + 0.02, lf) * season_autumn * (1.0 - 0.85 * dirt);
		float hue = texture(noise_tex, wxz * 0.9 + vec2(0.44, 0.29)).r;
		vec3 lc = mix(vec3(0.62, 0.12, 0.02), vec3(0.75, 0.3, 0.03), smoothstep(0.35, 0.5, hue));
		lc = mix(lc, vec3(0.7, 0.48, 0.05), smoothstep(0.55, 0.68, hue));
		lc = mix(lc, vec3(0.24, 0.11, 0.03), smoothstep(0.72, 0.8, hue));   // folha velha, marrom
		col = mix(col, lc * (0.85 + 0.3 * n3), leaf);
	}
	float rough = 1.0;
	float spec = 0.25;
	vec3 nrm = vec3(0.0, 1.0, 0.0);

	// Molhado: escurece (terra mais que grama) e ganha brilho.
	float wet = weather_wet;
	col *= mix(1.0, mix(0.74, 0.56, dirt), wet);
	rough = mix(rough, mix(0.6, 0.38, dirt), wet);
	spec = mix(spec, 0.4, wet);

	// Poças: nas baixadas do ruído, maiores na terra e quanto mais água houver.
	float pn = texture(noise_tex, wxz * 0.09 + vec2(0.13, 0.61)).r * 0.8 + n3 * 0.2;
	float th = 0.9 - wet * mix(0.16, 0.29, dirt);
	float puddle = smoothstep(th, th + 0.025, pn) * smoothstep(0.12, 0.35, wet);
	if (puddle > 0.0) {
		vec2 g = ripple(wxz, 0.55, TIME) + ripple(wxz + vec2(0.27, 0.41), 0.8, TIME * 0.83 + 0.5);
		nrm = normalize(vec3(-g.x * 0.35 * weather_rain, 1.0, -g.y * 0.35 * weather_rain));
		vec3 water = col * 0.22 + vec3(0.015, 0.02, 0.028);
		col = mix(col, water, puddle);
		rough = mix(rough, 0.03, puddle);
		spec = mix(spec, 0.6, puddle);
		nrm = normalize(mix(vec3(0.0, 1.0, 0.0), nrm, puddle));
	}

	// Neve acumulada: cobre primeiro as manchas altas do ruído e por último as trilhas (pisadas);
	// ao derreter some na ordem inversa, em placas, e deixa o chão molhado (a água vem do weather).
	float sn = texture(noise_tex, wxz * 0.05 + vec2(0.52, 0.21)).r * 0.6 + n3 * 0.3 + n4 * 0.1;
	float th_s = 1.02 - weather_snow * 1.3 + dirt * 0.14;
	float snow = smoothstep(th_s, th_s + 0.1, sn);
	vec3 snow_col = vec3(0.88, 0.91, 0.96) * (0.95 + 0.07 * n4);
	snow_col = mix(snow_col, snow_col * vec3(0.9, 0.89, 0.88), dirt * 0.5);   // trilha: neve pisada
	col = mix(col, snow_col, snow);
	rough = mix(rough, 0.85, snow);
	spec = mix(spec, 0.35, snow);
	nrm = normalize(mix(nrm, vec3(0.0, 1.0, 0.0), snow));

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
