// Árvores do mapa com o clima (posto pelo WeatherFX no lugar do material liso do GLB): a copa
// balança e verga com o vento (forte quando venta), a neve assenta nas faces de cima e a chuva
// escurece. A neve fica aqui (e não na camada weather_overlay) para acompanhar o balanço.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

global uniform float weather_wind;
global uniform vec2 weather_wind_dir;
global uniform float weather_phase;   // vento acumulado: acelera o balanço sem saltos
global uniform float weather_snow;
global uniform float weather_wet;

uniform vec3 albedo : source_color = vec3(0.3, 0.5, 0.2);
uniform float roughness = 0.9;
uniform float tree_height = 5.0;   // altura da malha (espaço do modelo): o topo balança mais
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / tree_height, 0.0, 1.2);
	float bend = h * h;
	float phase = origin.x * 0.21 + origin.z * 0.17;
	float w = weather_wind;
	vec2 wd = weather_wind_dir;
	// rajada que corre pelo mapa na direção do vento + balanço próprio de cada árvore
	float gust = 0.65 + 0.35 * sin(TIME * 0.5 + weather_phase * 0.5 - dot(origin.xz, wd) * 0.08);
	float sway = sin(TIME * 1.1 + weather_phase * 0.9 + phase);
	vec2 push = wd * (w * w * 0.45 * gust + (0.03 + w * 0.1) * sway);
	vec2 side = vec2(-wd.y, wd.x) * (0.02 + w * 0.05) * sin(TIME * 1.7 + weather_phase * 1.1 + phase * 1.3);
	vec3 off = vec3(push.x + side.x, 0.0, push.y + side.y) * bend;
	// folhas tremulando no alto
	off += vec3(sin(TIME * 5.0 + VERTEX.x * 3.0 + phase), 0.0, cos(TIME * 4.4 + VERTEX.z * 3.0 + phase)) * 0.015 * w * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm) * (FRONT_FACING ? 1.0 : -1.0);
	float up = smoothstep(0.2, 0.65, n.y);
	float nz = texture(noise_tex, wpos.xz * 0.05 + wpos.y * 0.02).r * 0.65
			+ texture(noise_tex, wpos.xz * 0.6 + vec2(0.3, 0.7)).r * 0.35;
	float th = 1.02 - weather_snow * 1.3;
	float s = up * smoothstep(th, th + 0.1, nz) * step(0.002, weather_snow);
	vec3 col = albedo * (1.0 - 0.3 * weather_wet);
	ALBEDO = mix(col, vec3(0.9, 0.92, 0.97), s);
	ROUGHNESS = mix(mix(roughness, 0.45, weather_wet), 0.85, s);
	SPECULAR = mix(0.5, 0.3, s);
}
