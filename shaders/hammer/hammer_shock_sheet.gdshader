shader_type spatial;
// Martelo de Energia: a onda de choque com as fissuras radiais (assets/vfx/hammer/hammer_shock_sheet.webp, 8 x 8
// quadros de 128 px, fundo preto puro) tocada num billboard no ponto do impacto, com mistura ADITIVA: o preto não
// soma nada e some sozinho. A sheet foi desenhada vista de lado, com o chão rachado na metade de baixo do quadro:
// por isso o quad fica de pé no chão e é puxado `cam_push` metros para a câmera, para a parte de baixo (o chão
// desenhado) não ser cortada pelo chão de verdade. Mesmas leituras da sheet que o resto do martelo
// (hammer_sheet.gdshaderinc: `frame`, `intensity`, `recolor`).
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

#include "res://shaders/hammer/hammer_sheet.gdshaderinc"

uniform float black_cut = 0.03;
uniform float cam_push = 2.5;
uniform float smoke_keep = 0.3;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mv = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
		MODEL_MATRIX[3]);
	NORMAL = vec3(0.0, 0.0, 1.0);
	// skip_vertex_transform: o vértice sai daqui já em espaço de vista. Nele a câmera olha para -Z: somar em Z
	// aproxima o quad dela
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	VERTEX.z += cam_push;
}

void fragment() {
	vec3 c = sheet_sample(UV);
	float lum = max(c.r, max(c.g, c.b));
	c *= smoothstep(black_cut, black_cut + 0.05, lum);
	// a fumaça desenhada é cinza: somada ao céu claro vira névoa branca (e mostra o retângulo do quad). Mantém o
	// fogo e as fissuras (saturados) e atenua o cinza; a fumaça de verdade é das partículas (escurece o fundo)
	float sat = (lum - min(c.r, min(c.g, c.b))) / max(lum, 0.001);
	c *= mix(smoke_keep, 1.0, smoothstep(0.2, 0.55, sat));
	c = sheet_recolor(c) * tint;
	ALBEDO = c * intensity * sheet_soft(UV);
	ALPHA = 1.0;
}
