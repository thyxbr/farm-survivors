// Lâminas Rúnicas: quad comprido que gira só em volta do próprio eixo (o Y do nó = a direção da lâmina) para
// ficar de frente para a câmera: a lâmina aponta para onde o nó aponta e nunca fica de quina.
instance uniform vec3 col = vec3(1.0, 0.14, 0.1);
instance uniform float intensity = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(axis, to_cam);
	side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	vec3 world = origin + side * VERTEX.x * sx + axis * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}
