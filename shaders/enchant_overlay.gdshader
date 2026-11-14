shader_type spatial;
// Camada por cima da arma encantada (material_overlay): brilho de borda (fresnel) + faixas
// de energia que sobem pela lâmina. A força cresce com o nível do encantamento.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float intensity = 0.5;      // 0..1 (nível / nível máximo)
uniform float band_speed = 1.2;
uniform float band_scale = 9.0;
uniform float pulse_speed = 2.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// faixas correndo ao longo do maior eixo da arma (soma dos eixos: serve para GLB e lâminas por código)
	float along = local_pos.x + local_pos.y + local_pos.z;
	float n = noise(local_pos * band_scale + vec3(0.0, -TIME * band_speed, TIME * band_speed * 0.5));
	float bands = smoothstep(0.55, 0.95, sin(along * band_scale * 1.7 - TIME * band_speed * 4.0) * 0.5 + 0.5 + n * 0.6 - 0.3);
	// pulso só a partir do +2 (no +1 o tom fica parado)
	float pulse = 1.0 - smoothstep(0.1, 0.3, intensity) * 0.3 * (0.5 - 0.5 * sin(TIME * pulse_speed));
	float base = 0.1 + 0.3 * intensity;                                   // tingido geral
	float rim = fres * smoothstep(0.1, 0.3, intensity) * (0.4 + 2.2 * intensity);   // borda: do +2 em diante
	float energy = bands * smoothstep(0.45, 0.6, intensity) * (0.6 + intensity); // faixas: do +3 em diante
	ALBEDO = glow_color.rgb * (base + rim + energy) * pulse * (0.4 + intensity);
}
