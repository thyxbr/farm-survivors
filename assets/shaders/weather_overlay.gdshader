// Camada de clima por cima dos modelos (material_overlay posto pelo WeatherFX): neve acumulada
// nas faces viradas para cima (telhados, copas, pedras, montanhas) e o escurecido brilhante de
// superfície molhada. Transparente e sem sombra; o WeatherFX só liga quando há neve ou água.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, shadows_disabled;

global uniform float weather_wet;
global uniform float weather_snow;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float up = smoothstep(0.2, 0.65, n.y);
	float nz = texture(noise_tex, wpos.xz * 0.05 + wpos.y * 0.02).r * 0.65
			+ texture(noise_tex, wpos.xz * 0.6 + vec2(0.3, 0.7)).r * 0.35;
	float th = 1.02 - weather_snow * 1.3;
	float s = up * smoothstep(th, th + 0.1, nz) * step(0.002, weather_snow);
	float w = weather_wet * 0.32 * (1.0 - s);
	float a = s + w;
	if (a < 0.004) {
		discard;
	}
	float snow_part = s / a;
	ALBEDO = vec3(0.9, 0.92, 0.97) * snow_part;
	ROUGHNESS = mix(0.22, 0.85, snow_part);
	SPECULAR = mix(0.55, 0.3, snow_part);
	ALPHA = clamp(a, 0.0, 1.0);
}
