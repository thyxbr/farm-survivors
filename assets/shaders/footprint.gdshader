// Pegadas dos jogadores (scripts/world/footprints.gd): um quadrado deitado no chão por pegada, num
// MultiMesh. Na neve vira um buraco azulado com a borda de neve empurrada; na lama, marca escura e
// brilhante; no chão seco, só uma sombra fraca. A neve é medida com o mesmo ruído do chão
// (ground.gdshader), então a pegada só fica branca onde o chão está branco.
// INSTANCE_CUSTOM = (hora em que pisou, lado: -1 esquerdo / 1 direito, vida em s, 0).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

#include "res://assets/shaders/ground_common.gdshaderinc"
#include "res://assets/shaders/toon_light.gdshaderinc"

global uniform float weather_wet;
global uniform float weather_snow;

uniform float now = 0.0;
// tamanho do quadrado (m): a pegada fica no meio, com folga para a borda de neve
uniform vec2 quad_size = vec2(0.26, 0.42);

varying vec2 wxz;
varying vec3 info;

void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	info = INSTANCE_CUSTOM.xyz;
}

float sd_ellipse(vec2 p, vec2 r) {
	// aproximação boa para elipses pouco achatadas, em metros
	float k = length(p / r);
	return (k - 1.0) * min(r.x, r.y);
}

void fragment() {
	float side = info.y;
	vec2 p = (UV - 0.5) * quad_size;
	p.x *= side;         // pé esquerdo é o direito espelhado (+y = ponta do pé)
	// sola (peito do pé virado para dentro) e salto, ligados por um arco estreito
	float sole = sd_ellipse(p - vec2(0.006, 0.05), vec2(0.052, 0.088));
	float heel = sd_ellipse(p - vec2(-0.002, -0.095), vec2(0.044, 0.05));
	vec2 a0 = vec2(-0.004, -0.085);
	vec2 a1 = vec2(0.004, 0.0);
	float h = clamp(dot(p - a0, a1 - a0) / dot(a1 - a0, a1 - a0), 0.0, 1.0);
	float arch = length(p - a0 - (a1 - a0) * h) - 0.027;
	float d = min(min(sole, heel), arch);
	float inside = 1.0 - smoothstep(-0.006, 0.004, d);
	float rim = smoothstep(-0.002, 0.008, d) * (1.0 - smoothstep(0.012, 0.035, d));
	// cravos da bota: listras de través
	float tread = step(0.5, fract(p.y * 42.0)) * (1.0 - smoothstep(-0.022, -0.012, d));

	float age = now - info.x;
	float life = max(info.z, 0.1);
	float fade = 1.0 - smoothstep(life * 0.55, life, age);

	// neve do chão neste ponto (mesma conta do ground.gdshader, sem as trilhas)
	float n3 = texture(noise_tex, wxz * 0.23 + vec2(0.71, 0.53)).r;
	float n4 = texture(noise_tex, wxz * 1.3).r;
	float sn = texture(noise_tex, wxz * 0.05 + vec2(0.52, 0.21)).r * 0.6 + n3 * 0.3 + n4 * 0.1;
	float th_s = 1.02 - weather_snow * 1.3;
	float snow = smoothstep(th_s, th_s + 0.1, sn);
	vec3 snow_col = vec3(0.88, 0.91, 0.96) * (0.95 + 0.07 * n4);

	// neve: fundo frio e sombreado, cravos um pouco mais escuros, borda empurrada mais clara
	vec3 hole = snow_col * vec3(0.5, 0.58, 0.78) * (1.0 - 0.1 * tread);
	vec3 s_col = mix(snow_col * 1.04, hole, inside);
	float s_a = max(inside * 0.95, rim * 0.6);

	// lama (chão molhado) ou poeira (seco): só a marca, sem borda
	vec3 mud = vec3(0.12, 0.085, 0.055) * (1.0 - 0.15 * tread);
	vec3 dust = vec3(0.17, 0.15, 0.09);
	float wet = clamp(weather_wet, 0.0, 1.0);
	vec3 g_col = mix(dust, mud, wet);
	float g_a = inside * mix(0.24, 0.75, wet);

	ALBEDO = mix(g_col, s_col, snow);
	ALPHA = mix(g_a, s_a, snow) * fade;
	ROUGHNESS = mix(mix(1.0, 0.35, wet), 0.85, snow);
	SPECULAR = mix(mix(0.2, 0.45, wet), 0.3, snow);
}
