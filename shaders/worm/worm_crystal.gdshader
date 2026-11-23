shader_type spatial;
// Cristal da Onda de Cristais em 3D: um prisma de seis faces com ponta (WormFX._crystal_mesh), pintado como
// desenho. Cada face tem um tom só, escolhido pela direção dela para uma luz fixa na tela (face clara, cor,
// sombra), com um risco de brilho nas faces claras; o traço de fora vem do segundo passe (worm_crystal_ink).
// Visto de qualquer lado é um cristal de verdade, e as faces trocam de tom quando a câmera gira.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

instance uniform vec3 core : instance_index(0) = vec3(0.75, 0.97, 1.0);
instance uniform vec3 mid : instance_index(1) = vec3(0.04, 0.6, 1.0);
instance uniform vec3 shade : instance_index(2) = vec3(0.02, 0.013, 0.34);
instance uniform float glow : instance_index(3) = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	// normal da face (a malha tem normais chapadas), no espaço da câmera
	float l = dot(normalize(NORMAL), normalize(vec3(-0.45, 0.55, 0.7)));
	float lit = step(0.5, l);
	float half_lit = step(0.05, l);
	vec3 col = mix(shade, mid, half_lit);
	col = mix(col, core, lit);
	// a sombra clareia um pouco perto da ponta: o cristal é translúcido
	col = mix(col, mid, (1.0 - half_lit) * smoothstep(0.55, 1.0, local.y) * 0.6);
	// risco de brilho atravessando as faces claras
	float streak = 1.0 - step(0.05, abs(fract(local.y * 1.7 + local.x * 4.0 + local.z * 3.0) - 0.5));
	col = mix(col, vec3(1.0), streak * lit * 0.85);
	ALBEDO = col * (1.0 + glow * (0.35 + 0.65 * half_lit));
}
