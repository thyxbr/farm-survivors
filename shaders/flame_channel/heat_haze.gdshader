shader_type spatial;
// Canalização de Fogo: distorção de calor na ponta da labareda. Um billboard que lê a tela já desenhada (os opacos) e a
// desloca com um ruído subindo; o recorte redondo some a borda. `strength` (por instância) sobe com o jato e cai no fim.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float scroll = 1.4;
instance uniform float strength = 0.0;

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float m = 1.0 - smoothstep(0.15, 0.5, length(UV - 0.5));
	vec2 n = texture(noise, UV * 1.3 + vec2(0.0, TIME * scroll)).rg - 0.5;
	n += (texture(noise, UV * 2.7 - vec2(TIME * 0.3, TIME * scroll * 1.7)).rg - 0.5) * 0.5;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + n * strength * m * 0.05, 0.0).rgb;
	ALPHA = m * step(0.001, strength);
}
