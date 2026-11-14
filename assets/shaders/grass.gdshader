// Tufos de capim (MultiMesh): cor do chão embaixo + ponta mais clara, balanço de vento.
// COLOR.r da malha = altura relativa da folha (0 na base, 1 na ponta).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://assets/shaders/ground_common.gdshaderinc"

uniform float sway = 0.1;
uniform vec3 tip_tint : source_color = vec3(0.75, 0.82, 0.42);

// Clima (scripts/autoload/weather.gd): vento verga e sacode o capim; a neve soterra e branqueia.
global uniform float weather_wind;
global uniform vec2 weather_wind_dir;
global uniform float weather_phase;   // vento acumulado (s × força): acelera o balanço sem saltos
global uniform float weather_snow;
global uniform float weather_wet;

varying vec3 base_col;
varying float hgt;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hgt = COLOR.r;
	base_col = grass_color(origin.xz) * INSTANCE_CUSTOM.rgb;
	float w = weather_wind;
	// frequência nunca multiplica TIME: com vento a fase só anda mais rápido (weather_phase)
	float t = TIME * 1.7 + weather_phase * 1.6 + origin.x * 0.31 + origin.z * 0.23;
	// rajadas correm pelo campo na direção do vento (ondas largas e lentas)
	float along = dot(origin.xz, weather_wind_dir);
	float gust = 0.6 + 0.4 * sin(TIME * 0.4 + weather_phase * 0.7 - along * 0.09);
	float amp = sway * (1.0 + w * 1.1);
	float h2 = hgt * hgt;
	VERTEX.x += sin(t) * amp * h2 * gust;
	VERTEX.z += cos(t * 0.83) * amp * 0.6 * h2 * gust;
	// vento forte: o capim deita na direção do vento (direção do mundo levada ao espaço da instância)
	vec3 lean = (inverse(MODEL_MATRIX) * vec4(weather_wind_dir.x, 0.0, weather_wind_dir.y, 0.0)).xyz;
	VERTEX += lean * w * w * 0.18 * h2 * (0.7 + 0.5 * gust);
	// soterrado pela neve
	VERTEX.y *= 1.0 - weather_snow * 0.72;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	// as duas faces usam a normal "para cima" (senão a face de trás fica escura)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 c = mix(base_col * 0.78, base_col * tip_tint * 1.55, hgt);
	c *= 1.0 - 0.22 * weather_wet;
	c = mix(c, vec3(0.88, 0.91, 0.96), weather_snow * (0.55 + 0.4 * hgt));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
