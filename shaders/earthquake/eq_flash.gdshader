shader_type spatial;
// Terremoto Devastador: o clarão do impacto (GroundImpact/Core). Billboard aditivo com miolo branco e borda azul,
// `energy` > 1 para o glow do ambiente acender no instante do contato. Puxado para a câmera para não ser cortado
// pelo chão.
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_add, fog_disabled;

uniform vec3 core_color : source_color = vec3(0.9, 0.96, 1.0);
uniform vec3 edge_color : source_color = vec3(0.15, 0.45, 1.0);
uniform float cam_push = 1.2;
instance uniform float energy = 1.0;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mv = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
		MODEL_MATRIX[3]);
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	VERTEX.z += cam_push;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 18.0);
	float halo = pow(max(1.0 - r, 0.0), 2.2);
	ALBEDO = (core_color * core * 3.0 + edge_color * halo) * energy;
	ALPHA = 1.0;
}
