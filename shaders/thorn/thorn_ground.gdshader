shader_type spatial;
// Pintura deitada no chão da Espinheira (claro sobre preto, só tons; as três cores entram aqui): os rasgos da
// Garra (garra_rasgos.png), o chão rachado das Raízes (chao_rachado.png) e o mofo da Nuvem de Esporos
// (esporos_mofo.png). O branco vira `core` (acende com `heat`), o cinza vira `mid`, o vão escuro vira `shade`;
// o preto puro é vazio. `fill` pinta o fundo da área num disco, para ler até onde dói.
//   grow 0 -> 1   abre: do centro para fora (sweep 0) ou rasgando na diagonal da pintura (sweep 1)
//   erode 0 -> 1  some comida em pedaços, da borda para o centro, nunca só transparente
//   turn          giro em passos (rad/s), como desenho animado
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D paint : filter_linear_mipmap, repeat_disable;

instance uniform vec3 core = vec3(0.86, 0.16, 0.36);
instance uniform vec3 mid = vec3(0.38, 0.22, 0.16);
instance uniform vec3 shade = vec3(0.1, 0.04, 0.05);
instance uniform float heat = 0.0;
instance uniform float fill = 0.0;
instance uniform float grow = 1.0;
instance uniform float sweep = 0.0;
instance uniform float erode = 0.0;
instance uniform float spin = 0.0;
instance uniform float turn = 0.0;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	float t = floor((TIME + seed * 10.0) * 8.0) / 8.0;
	vec2 q = UV - 0.5;
	vec2 p = rot(q, spin + t * turn);
	float g = texture(paint, p + 0.5).r;
	float r = length(q) * 2.0;
	float along = dot(q, vec2(-0.7071, 0.7071)) * 1.414 + 0.5;
	float m = mix(r, along, sweep);
	float open = 1.0 - smoothstep(grow - 0.08, grow, m);
	vec3 col = mix(shade, mid, smoothstep(0.3, 0.45, g));
	vec3 lit = mix(core * 0.7, mix(core, vec3(1.0), 0.35 * heat) * (1.0 + 1.6 * heat), smoothstep(0.0, 0.3, heat));
	col = mix(col, lit, smoothstep(0.72, 0.86, g));
	float ink = smoothstep(0.1, 0.22, g);
	float disc = (1.0 - smoothstep(0.84, 0.9, r)) * fill;
	float n = hash(floor(UV * 24.0) + seed * 7.0);
	float keep = step(erode * 1.5, (1.0 - r) * 0.9 + n * 0.5 + 0.02);
	ALBEDO = mix(shade, col, ink);
	ALPHA = max(ink, disc) * open * keep;
}
