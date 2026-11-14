// Partícula em risco (gota de chuva, rajada de vento): o comprimento segue a velocidade
// (eixo Y da partícula, com align_y no material de processo) e a largura vira para a câmera.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.75, 0.8, 0.9, 0.35);
uniform float width = 0.012;
uniform float length_m = 0.55;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(axis, to_cam));
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + side * sign(VERTEX.x) * width * sc + axis * sign(VERTEX.y) * 0.5 * length_m * sc;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

void fragment() {
	// some nas pontas e nas bordas; COLOR.a = fade da vida da partícula
	float along = 1.0 - abs(UV.y * 2.0 - 1.0);
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = tint.rgb;
	// rente à câmera vira um risco grosso: some perto dela
	float near = smoothstep(1.5, 5.0, length(VERTEX));
	ALPHA = tint.a * COLOR.a * smoothstep(0.0, 0.5, along) * smoothstep(0.0, 0.6, across) * near;
}
