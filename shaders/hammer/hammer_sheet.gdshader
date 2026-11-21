shader_type spatial;
// Martelo de Energia: um quadro da sprite sheet num quad, com mistura ADITIVA. O fundo da sheet é preto puro: na
// soma o preto não acrescenta nada e some sozinho, sem retângulo e sem recorte que comeria os brilhos fracos das
// bordas. `black_cut` só zera o ruído escuro da compressão (bem abaixo dos detalhes do desenho).
// `mode`: 0 = billboard virado para a câmera (explosão, dissipação); 1 = o quad como está no nó (círculo
// deitado); 2 = de pé, gira só em volta do Y para encarar a câmera (feixe de energia e rastro da queda).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/hammer/hammer_sheet.gdshaderinc"

uniform int mode = 0;
uniform float black_cut = 0.035;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (mode == 0) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
			vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
			MODEL_MATRIX[3]);
	} else if (mode == 2) {
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
		to_cam.y = 0.0;
		vec3 z = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(x * sc.x, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(z * sc.z, 0.0), MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec3 c = sheet_sample(UV);
	float lum = max(c.r, max(c.g, c.b));
	c *= smoothstep(black_cut, black_cut + 0.06, lum);
	c = sheet_recolor(c) * tint;
	ALBEDO = c * intensity * sheet_reveal(UV) * sheet_soft(UV);
	ALPHA = 1.0;
}
