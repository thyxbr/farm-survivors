shader_type spatial;
// Malha lisa da Mãe-Verme pintada como desenho: o ácido (bolha, gotas, línguas do respingo) e as bolas de poeira.
// Três tons em faixas duras pela direção da superfície para uma luz fixa na tela, um ponto de brilho (`spec`) e o
// traço de fora no segundo passe (worm_ink). `wobble` faz a superfície tremer como gosma.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform float wobble = 0.0;

instance uniform vec3 core : instance_index(0) = vec3(0.57, 1.0, 0.07);
instance uniform vec3 mid : instance_index(1) = vec3(0.1, 0.78, 0.007);
instance uniform vec3 shade : instance_index(2) = vec3(0.002, 0.055, 0.004);
instance uniform float glow : instance_index(3) = 0.0;
instance uniform float spec : instance_index(4) = 0.0;
instance uniform float seed : instance_index(5) = 0.0;

void vertex() {
	VERTEX += NORMAL * wobble * sin(TIME * 13.0 + VERTEX.y * 5.0 + VERTEX.x * 4.0 + seed * 20.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float l = dot(n, normalize(vec3(-0.45, 0.55, 0.7)));
	vec3 col = mix(shade, mid, step(-0.15, l));
	col = mix(col, core, step(0.5, l));
	col = mix(col, vec3(1.0), step(0.955, dot(n, normalize(vec3(-0.35, 0.5, 0.8)))) * spec);
	ALBEDO = col * (1.0 + glow);
}
