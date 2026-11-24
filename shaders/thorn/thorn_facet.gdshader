shader_type spatial;
// Malha facetada da Espinheira pintada como desenho: os espinhos de raiz, as gavinhas dos Brotos e os talos dos
// cogumelos (ThornFX._tube). Normais chapadas: cada face ganha um tom só pela direção dela para uma luz fixa na
// tela (face clara, cor, sombra); o traço de fora vem do segundo passe (thorn_ink).
//   tip / tip_from   da altura `tip_from` (UV.y, 0 no pé e 1 na ponta) para cima, a casca vira a cor da ponta
//   grain            veios escuros da casca, em espiral pelo tubo
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

instance uniform vec3 core : instance_index(0) = vec3(0.6, 0.4, 0.28);
instance uniform vec3 mid : instance_index(1) = vec3(0.38, 0.22, 0.16);
instance uniform vec3 shade : instance_index(2) = vec3(0.17, 0.08, 0.08);
instance uniform float glow : instance_index(3) = 0.0;
instance uniform vec3 tip : instance_index(4) = vec3(0.86, 0.16, 0.36);
instance uniform float tip_from : instance_index(6) = 2.0;
instance uniform float grain : instance_index(7) = 1.0;

varying vec2 uvv;

void vertex() {
	uvv = UV;
}

void fragment() {
	float l = dot(normalize(NORMAL), normalize(vec3(-0.45, 0.55, 0.7)));
	float lit = step(0.5, l);
	float half_lit = step(0.05, l);
	float k = step(tip_from, uvv.y + 0.05 * sin(uvv.x * TAU * 3.0));
	vec3 c0 = mix(core, mix(tip, vec3(1.0), 0.45), k);
	vec3 c1 = mix(mid, tip, k);
	vec3 c2 = mix(shade, tip * 0.4, k);
	vec3 col = mix(c2, c1, half_lit);
	col = mix(col, c0, lit);
	float vein = 1.0 - step(0.07, abs(fract(uvv.x * 4.0 + uvv.y * 1.6) - 0.5));
	col = mix(col, c2, vein * 0.75 * grain * (1.0 - k) * step(0.08, uvv.y));
	ALBEDO = col * (1.0 + glow);
}
