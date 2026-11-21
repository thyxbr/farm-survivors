shader_type spatial;
// Terremoto Devastador: um trecho da sprite sheet (assets/vfx/earthquake/earthquake_sheet.webp, 8 x 8 quadros de
// 128 px, fundo preto puro #000000) tocado num billboard, com mistura ADITIVA: o preto não soma nada e some sozinho.
// A sheet foi desenhada vista de 3/4 de cima, com o chão no meio/baixo do quadro: o quad fica de pé sobre o ponto e é
// puxado `cam_push` m para a câmera, para a parte de baixo (o chão desenhado) não ser cortada pelo chão de verdade.
// A partir da linha 4 os quadros preenchem a célula inteira (fumaça e pedras até a borda): a máscara radial
// (`mask_inner`..`mask_outer`) apaga a borda para o retângulo do quad nunca aparecer. O quadro é fracionário:
// mistura o atual com o seguinte (animação suave mesmo com poucos quadros).
// O quad pode atravessar o chão (ele é grande e fica de pé): em vez de o teste de profundidade cortar numa linha reta
// (o retângulo aparecendo), a parte que fica atrás do cenário some aos poucos em `soft_depth` m.
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_depth = 2.5;
uniform float columns = 8.0;
uniform float rows = 8.0;
uniform float black_cut = 0.035;
uniform float cam_push = 2.0;
// cinza (fumaça desenhada) somado ao céu vira névoa: mantém só esta fração dele; o azul saturado fica inteiro
uniform float smoke_keep = 0.22;
uniform float mask_inner = 0.55;
uniform float mask_outer = 0.98;
uniform vec3 tint : source_color = vec3(1.0);
uniform float boost = 1.35;

instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;

vec3 sheet_frame(float f, vec2 uv) {
	float total = columns * rows;
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	vec2 q = clamp(uv, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + q) / vec2(columns, rows)).rgb;
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mv = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
		MODEL_MATRIX[3]);
	NORMAL = vec3(0.0, 0.0, 1.0);
	// skip_vertex_transform: o vértice sai daqui em espaço de vista, onde a câmera olha para -Z (somar aproxima)
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	VERTEX.z += cam_push;
}

void fragment() {
	float f0 = floor(frame);
	vec3 c = mix(sheet_frame(f0, UV), sheet_frame(f0 + 1.0, UV), frame - f0);
	float lum = max(c.r, max(c.g, c.b));
	c *= smoothstep(black_cut, black_cut + 0.05, lum);
	float sat = (lum - min(c.r, min(c.g, c.b))) / max(lum, 0.001);
	c *= mix(smoke_keep, 1.0, smoothstep(0.15, 0.5, sat));
	// o miolo azul fica branco-azulado e mais forte (passa do 1: o glow do ambiente acende)
	c = mix(c, vec3(0.85, 0.95, 1.0) * lum, smoothstep(0.75, 1.0, lum) * 0.6) * boost;
	float r = length(UV - 0.5) * 2.0;
	float mask = 1.0 - smoothstep(mask_inner, mask_outer, r);
	// atrás do cenário: some aos poucos (profundidade linear da cena x deste fragmento, em espaço de vista)
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float behind = -VERTEX.z - scene_z;
	mask *= 1.0 - smoothstep(0.0, soft_depth, behind);
	ALBEDO = c * tint * intensity * mask;
	ALPHA = 1.0;
}
