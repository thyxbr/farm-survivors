shader_type spatial;
// Sombra em dois tons para personagens (teste de estilo "desenhado").
// Cada luz ou acende a face por inteiro ou deixa a face no tom de sombra: não há degradê.
// A cor final continua vindo da luz do jogo (sol, contraluz, ambiente), só o corte é que fica seco.
render_mode cull_back, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
// quanto da luz direta sobra na face em sombra, por canal (azulado => sombra fria)
uniform vec3 shade_tint = vec3(0.40, 0.38, 0.55);
// a face acesa recebe a luz inteira (sem o cosseno), então a luz é reduzida para não estourar as cores claras
uniform float light_gain : hint_range(0.0, 1.5) = 0.72;
uniform float threshold : hint_range(-1.0, 1.0) = 0.22;
uniform float softness : hint_range(0.0, 0.2) = 0.015;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;       // brilho em faixa, para metal
// cor por vértice (AO assado das placas, armas pintadas) e textura (armas traçadas) multiplicam o albedo
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

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

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(threshold - softness, threshold + softness, ndl);
	float atten = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		// a sombra projetada também corta seco, e entra no mesmo tom de sombra
		lit *= smoothstep(0.42, 0.58, ATTENUATION);
		atten = 1.0;
	}
	vec3 tint = mix(shade_tint, vec3(1.0), lit);
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * atten * light_gain / PI;
	if (gloss > 0.0) {
		float h = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
		SPECULAR_LIGHT += step(0.965, h) * lit * gloss * LIGHT_COLOR * atten / PI;
	}
}
