// Tufos de capim (MultiMesh): cor do chão embaixo + ponta mais clara, balanço de vento.
// COLOR.r da malha = altura relativa da folha (0 na base, 1 na ponta).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://assets/shaders/ground_common.gdshaderinc"

uniform float sway = 0.1;
uniform vec3 tip_tint : source_color = vec3(0.75, 0.82, 0.42);

varying vec3 base_col;
varying float hgt;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hgt = COLOR.r;
	base_col = grass_color(origin.xz) * INSTANCE_CUSTOM.rgb;
	float t = TIME * 1.7 + origin.x * 0.31 + origin.z * 0.23;
	float gust = 0.6 + 0.4 * sin(TIME * 0.4 + origin.x * 0.05);
	VERTEX.x += sin(t) * sway * hgt * hgt * gust;
	VERTEX.z += cos(t * 0.83) * sway * 0.6 * hgt * hgt * gust;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	// as duas faces usam a normal "para cima" (senão a face de trás fica escura)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 c = mix(base_col * 0.78, base_col * tip_tint * 1.55, hgt);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
