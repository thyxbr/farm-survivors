shader_type spatial;
// Material toon genérico (personagens, armas, props, construções, árvores): cor chapada com a luz em
// dois tons de toon_light.gdshaderinc. Montado em tempo de execução por ToonLook a partir de cada
// StandardMaterial3D; o contorno dos personagens é outro passe (toon_outline.gdshader).
render_mode cull_back, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
// cor por vértice (AO assado das placas, armas pintadas, cor por instância dos MultiMesh) e textura
// (armas traçadas) multiplicam o albedo
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

#include "res://assets/shaders/toon_light.gdshaderinc"

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_tex, UV).rgb;
	if (use_vertex_color) {
		vec3 vc = COLOR.rgb;
		if (vertex_color_srgb) {
			vc = pow(vc, vec3(2.2));
		}
		base *= vc;
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emission * emission_energy;
}
