shader_type spatial;
// Canalização de Fogo: fumaça escura subindo da labareda. Billboard de partícula com a cor e o alfa da rampa do
// ParticleProcessMaterial (COLOR), um disco de borda macia com ruído (não um círculo perfeito) e fade de proximidade
// onde encosta na cena.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D noise : repeat_enable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_distance = 0.8;

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.w;
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mat_world = mat_world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float n = texture(noise, UV * 0.8 + vec2(seed * 7.13, seed * 3.71 + TIME * 0.15)).r;
	float r = length(UV - 0.5) * 2.0 + (n - 0.5) * 0.5;
	float disc = 1.0 - smoothstep(0.35, 1.0, r);
	float soft = 1.0;
	if (soft_distance > 0.0) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 world_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		world_pos.xyz /= world_pos.w;
		soft = clamp(1.0 - smoothstep(world_pos.z + soft_distance, world_pos.z, VERTEX.z), 0.0, 1.0);
	}
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a * disc * soft, 0.0, 1.0);
}
