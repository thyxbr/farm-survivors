shader_type spatial;
// Poça de Ácido pintada, num plano deitado: duas camadas da mesma pintura (acido_poca.png: anel de líquido claro
// com línguas escuras em espiral, visto de cima) girando em sentidos opostos, sobre um fundo verde escuro que
// marca a área que dói, com a trama de bolhas (acido_bolhas.png) fervendo por cima. A pintura só tem tons; as
// três cores entram aqui. O giro e a fervura andam em passos, como desenho animado.
//   grow 0 -> 1   a poça se espalha do centro
//   erode 0 -> 1  some comida pela trama de bolhas: primeiro o fundo, por último os fios claros
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D pool : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D web : source_color, filter_linear_mipmap, repeat_enable;

instance uniform vec3 core = vec3(0.7, 1.0, 0.17);
instance uniform vec3 mid = vec3(0.15, 0.8, 0.01);
instance uniform vec3 shade = vec3(0.005, 0.07, 0.004);
instance uniform float grow = 1.0;
instance uniform float erode = 0.0;
instance uniform float seed = 0.0;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	float t = floor((TIME + seed * 10.0) * 12.0) / 12.0;
	vec2 p = (UV - 0.5) / max(grow, 0.05);
	float r = length(p) * 2.0;
	float g1 = texture(pool, rot(p, t * 0.9 + seed * 6.0) + 0.5).r;
	float g2 = texture(pool, rot(p * 1.3, -t * 0.55 + seed * 3.0) + 0.5).r;
	float liquid = max(g1, g2 * 0.75);
	// a trama ferve: duas amostras que deslizam em passos
	float w1 = texture(web, p * 1.6 + vec2(t * 0.05, seed)).r;
	float w2 = texture(web, rot(p, 1.1) * 2.3 - vec2(seed, t * 0.07)).r;
	float foam = max(w1, w2 * 0.7);
	float disc = 1.0 - smoothstep(0.62, 0.7, r);
	vec3 col = mix(shade, mid, 0.45 * smoothstep(0.4, 0.8, foam));
	col = mix(col, mid, smoothstep(0.3, 0.6, liquid));
	col = mix(col, core, smoothstep(0.8, 0.95, liquid) * (0.7 + 0.3 * foam));
	col = mix(col, mid, smoothstep(0.0, 0.5, erode));
	float body = smoothstep(0.12, 0.25, liquid);
	// comido pela trama: o fundo some primeiro, o líquido fica só nos fios e some
	float fill = disc * 0.82 * (1.0 - smoothstep(0.0, 0.35, erode));
	float eaten = smoothstep(erode * 1.15 - 0.08, erode * 1.15, foam * 0.75 + liquid * 0.2 + 0.08);
	ALBEDO = col * (1.0 + 0.25 * smoothstep(0.8, 1.0, liquid));
	ALPHA = max(fill, body * eaten) * (1.0 - step(1.0, r));
}
