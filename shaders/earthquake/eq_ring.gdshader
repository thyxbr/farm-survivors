shader_type spatial;
// Terremoto Devastador: o anel de energia da onda de choque, desenhado num disco que segue o relevo (ShockwaveRing
// monta o disco pela grade polar de alturas do chão). UV.x = distância ao centro / raio máximo, UV.y = ângulo
// (0..1). A frente da onda (`wave`, na mesma escala de UV.x) é uma borda fina e branca, com um brilho azul
// arrastando para dentro e quebrado por ruído (não é um círculo de compasso). Aditivo: o preto não soma nada.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/earthquake/eq_noise.gdshaderinc"

uniform float wave = 0.0;
// largura da borda e do rastro, em fração do raio
uniform float ring_width = 0.05;
uniform float trail = 0.22;
uniform float intensity = 1.0;
// brilho que fica no chão por dentro depois que a onda passou (energia residual)
uniform float residual = 0.05;
uniform vec3 edge_color : source_color = vec3(0.12, 0.42, 1.0);
uniform vec3 core_color : source_color = vec3(0.85, 0.95, 1.0);
// puxa o disco para a câmera (m): não briga com o chão entre os pontos da grade
uniform float cam_push = 0.08;

varying vec3 v_world;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world += normalize(CAMERA_POSITION_WORLD - world) * cam_push;
	v_world = world;
	VERTEX = world - MODEL_MATRIX[3].xyz;
}

void fragment() {
	float r = UV.x;
	float ang = UV.y;
	float n = eq_fbm(vec2(ang * 38.0, r * 9.0 - TIME * 1.7));
	float n2 = eq_noise(vec2(ang * 90.0 + TIME * 0.6, r * 25.0));
	// borda tremida: a frente avança mais em uns pontos que em outros
	float front = wave + (n - 0.5) * ring_width * 1.4;
	float d = r - front;
	float lead = 1.0 - smoothstep(0.0, ring_width * 0.45, d);
	float behind = exp(min(d, 0.0) / max(trail, 0.001));
	float band = d >= 0.0 ? lead : behind;
	band *= mix(0.45, 1.35, n2);
	float core = exp(-abs(d) / (ring_width * 0.22));
	float inside = (1.0 - smoothstep(-0.02, 0.0, d)) * residual * (0.5 + n);
	// some perto da borda do disco e enquanto a onda ainda é um ponto
	float fade = (1.0 - smoothstep(1.02, 1.1, r)) * smoothstep(0.0, 0.04, wave);
	vec3 col = mix(edge_color, core_color, clamp(core * 1.2, 0.0, 1.0));
	ALBEDO = col * (band * 1.1 + core * 2.4 + inside) * intensity * fade;
	ALPHA = 1.0;
}
