shader_type spatial;
// O traço em volta do cristal 3D: a mesma malha um pouco mais gorda, só as faces de trás, na cor da sombra.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform float width = 0.035;

// o mesmo índice do passe principal: os dois passes dividem os parâmetros da instância
instance uniform vec3 shade : instance_index(2) = vec3(0.02, 0.013, 0.34);

void vertex() {
	// engorda para fora do eixo (a malha é um prisma em volta do Y) e estica a ponta
	float s = length(MODEL_MATRIX[0].xyz);
	vec2 out_dir = length(VERTEX.xz) > 0.0001 ? normalize(VERTEX.xz) : vec2(0.0);
	VERTEX.xz += out_dir * width / max(s, 0.001);
	VERTEX.y += step(0.99, VERTEX.y) * width * 1.5 / max(length(MODEL_MATRIX[1].xyz), 0.001);
}

void fragment() {
	ALBEDO = shade * 0.55;
}
