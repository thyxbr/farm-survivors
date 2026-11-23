// Raio e Onda de Choque: quad com um dos 4 raios pintados de raio_folha.png (4 colunas, branco em fundo preto).
// `free` = 0: o quad fica em pé e só gira no eixo Y para a câmera (o raio que cai do céu, pé no chão);
// `free` = 1: virado inteiro para a câmera e rodado por `roll` (os arcos pequenos da crista da onda).
// `column` escolhe o desenho, `vrange` o trecho da altura da coluna, `flip` espelha.
uniform sampler2D bolts : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec3 col = vec3(1.0);
instance uniform float intensity = 1.0;
instance uniform float column = 0.0;
instance uniform vec2 vrange = vec2(0.0, 1.0);
instance uniform float flip = 0.0;
instance uniform float free = 0.0;
instance uniform float roll = 0.0;
// quanto do miolo fica branco (0 = todo na cor)
instance uniform float whiten = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 right;
	vec3 up;
	if (free > 0.5) {
		float c = cos(roll);
		float s = sin(roll);
		vec3 r0 = INV_VIEW_MATRIX[0].xyz;
		vec3 u0 = INV_VIEW_MATRIX[1].xyz;
		right = r0 * c + u0 * s;
		up = u0 * c - r0 * s;
	} else {
		vec3 f = CAMERA_POSITION_WORLD - origin;
		f.y = 0.0;
		f = normalize(f + vec3(0.0001, 0.0, 0.0));
		right = normalize(cross(vec3(0.0, 1.0, 0.0), f));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 world = origin + right * VERTEX.x * sx + up * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float bolt_value(vec2 uv) {
	float u = flip > 0.5 ? 1.0 - uv.x : uv.x;
	u = (column + mix(0.03, 0.97, u)) * 0.25;
	float v = mix(vrange.x, vrange.y, uv.y);
	return texture(bolts, vec2(u, v)).r;
}
