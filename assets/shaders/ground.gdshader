// Chão do mapa: grama com manchas (ruído em espaço de mundo) e trilhas/clareiras pintadas por
// formas (retângulos e discos) com bordas irregulares. As formas vêm de scripts/world/ground.gd.
shader_type spatial;
render_mode diffuse_burley;

#include "res://assets/shaders/ground_common.gdshaderinc"

const int MAX_SHAPES = 40;
uniform vec4 shapes[MAX_SHAPES];      // retângulo: (cx, cz, meia_x, meia_z); disco: (cx, cz, raio, -1)
uniform vec4 shape_cols[MAX_SHAPES];  // rgb linear + maciez da borda (m)
uniform float shape_grass[MAX_SHAPES]; // 0 = terra lisa; > 0 = grama baixa/pisada manchada com a cor
uniform int shape_count = 0;

varying vec2 wxz;

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float sd_box(vec2 p, vec2 h) {
	vec2 d = abs(p) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec3 grass = grass_color(wxz);
	vec3 col = grass;
	float n2 = texture(noise_tex, wxz * 0.047 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise_tex, wxz * 0.23 + vec2(0.71, 0.53)).r;
	float n4 = texture(noise_tex, wxz * 1.3).r;
	col *= 0.95 + 0.1 * n4;
	float edge_n = (n2 - 0.5) * 1.4 + (n3 - 0.5) * 0.6;
	for (int i = 0; i < shape_count; i++) {
		vec4 s = shapes[i];
		vec4 c = shape_cols[i];
		float d = s.w < 0.0 ? length(wxz - s.xy) - s.z : sd_box(wxz - s.xy, s.zw);
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
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.25;
}
