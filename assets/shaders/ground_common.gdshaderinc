// Cor da grama do chão, compartilhada entre o chão (ground.gdshader) e os tufos (grass.gdshader)
// para que o capim saia da mesma cor do pedaço de chão onde nasce.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 grass_dark : source_color = vec3(0.2, 0.37, 0.13);
uniform vec3 grass_light : source_color = vec3(0.37, 0.55, 0.2);
uniform vec3 grass_lush : source_color = vec3(0.16, 0.42, 0.14);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.55, 0.26);
// Estação (scripts/autoload/weather.gd): 0..1 do outono. A grama amarela e doura em manchas.
global uniform float season_autumn;

vec3 grass_color(vec2 p) {
	float n1 = texture(noise_tex, p * 0.011).r;
	float n2 = texture(noise_tex, p * 0.047 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise_tex, p * 0.23 + vec2(0.71, 0.53)).r;
	vec3 g = mix(grass_dark, grass_light, smoothstep(0.3, 0.72, n1));
	g = mix(g, grass_lush, smoothstep(0.55, 0.78, n2) * 0.55);
	g = mix(g, grass_dry, smoothstep(0.62, 0.8, n2 * 0.6 + n1 * 0.4) * 0.5);
	if (season_autumn > 0.0) {
		// outono: o verde vira palha dourada, mais forte nas manchas secas do ruído
		float l = dot(g, vec3(0.42, 0.5, 0.08));
		vec3 straw = l * vec3(1.55, 1.05, 0.32);
		float amt = season_autumn * (0.45 + 0.35 * smoothstep(0.35, 0.7, n2 * 0.5 + n1 * 0.5));
		g = mix(g, straw, amt);
	}
	return g * (0.9 + 0.2 * n3);
}
