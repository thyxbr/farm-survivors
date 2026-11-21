shader_type spatial;
// Égide Cristalina: quadro da sprite sheet (assets/vfx/aegis/aegis_sheet.webp, grade 8 x 8, quadros de
// 128 px, da esquerda para a direita e de cima para baixo) num billboard virado para a câmera.
// O fundo da sheet é preto: com blend_add o preto não soma nada e some sozinho, sem recorte que comeria os
// detalhes luminosos. `black_cut` só zera o ruído escuro da compressão, mantendo o brilho fraco das bordas.
// Os quadros vizinhos são misturados (frame fracionário).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
uniform float black_cut = 0.06;
uniform vec3 tint = vec3(1.0);
instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;

void vertex() {
	// billboard esférico mantendo a escala do nó
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec3 sample_frame(float f, vec2 uv) {
	float total = columns * rows;
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	// meio texel de margem para não puxar o quadro vizinho no filtro
	vec2 inset = clamp(uv, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + inset) / vec2(columns, rows)).rgb;
}

void fragment() {
	float f0 = floor(frame);
	float t = frame - f0;
	vec3 c = mix(sample_frame(f0, UV), sample_frame(f0 + 1.0, UV), t);
	float lum = max(c.r, max(c.g, c.b));
	c *= smoothstep(black_cut, black_cut + 0.1, lum);
	ALBEDO = c * tint * intensity;
	ALPHA = 1.0;
}
