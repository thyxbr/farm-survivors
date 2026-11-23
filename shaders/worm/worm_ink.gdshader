shader_type spatial;
// O traço em volta das malhas da Mãe-Verme: a mesma malha um pouco mais gorda, só as faces de trás, na cor da
// sombra. `mode` diz para onde engordar: 0 = para fora do eixo Y (os prismas: cristal e espigão de terra),
// 1 = pela normal (malhas lisas: ácido e poeira), 2 = para fora do centro (as pedras, de normais chapadas).
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform float width = 0.035;
uniform int mode = 0;
uniform float wobble = 0.0;

// os mesmos índices do passe principal: os dois passes dividem os parâmetros da instância
instance uniform vec3 shade : instance_index(2) = vec3(0.02, 0.013, 0.34);
instance uniform float seed : instance_index(5) = 0.0;

void vertex() {
	float sx = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float sy = max(length(MODEL_MATRIX[1].xyz), 0.001);
	if (mode == 0) {
		vec2 out_dir = length(VERTEX.xz) > 0.0001 ? normalize(VERTEX.xz) : vec2(0.0);
		VERTEX.xz += out_dir * width / sx;
		VERTEX.y += step(0.99, VERTEX.y) * width * 1.5 / sy;
	} else if (mode == 1) {
		VERTEX += NORMAL * wobble * sin(TIME * 13.0 + VERTEX.y * 5.0 + VERTEX.x * 4.0 + seed * 20.0);
		VERTEX += NORMAL * width / sx;
	} else {
		VERTEX += normalize(VERTEX) * width / sx;
	}
}

void fragment() {
	ALBEDO = shade * 0.55;
}
