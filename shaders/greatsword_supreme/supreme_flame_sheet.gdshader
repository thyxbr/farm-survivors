shader_type spatial;
// Lâmina Suprema: as chamas da sprite sheet (assets/vfx/greatsword_supreme/flame_sword_sheet.webp: 8 x 4 quadros de
// 128 x 256 px, da esquerda para a direita e de cima para baixo, fundo preto #000000) em volta da espada 3D, com mistura
// ADITIVA. A espada desenhada está na mesma pose em todos os quadros (inclinada ~14°); cada ponto do quad é levado ao
// pixel da espada desenhada que corresponde a ele, então as chamas ficam em cima da lâmina 3D em qualquer posição dela.
// O quad (nó FlameSheet, filho do SwordPivot) gira em volta do eixo da lâmina para encarar a câmera. Comprimento 1 =
// das mãos à ponta: o quad vai de `along_from` (abaixo do cabo) a `along_to` (acima da ponta, as chamas que sobem).
// O cinza (a fumaça e o ferro desenhados) quase não soma: a lâmina 3D e as partículas de fumaça cuidam deles.
//   frame      quadro da sheet (fracionário: mistura com o seguinte)      intensity brilho (0 = apagada)
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform int columns = 8;
uniform int rows = 4;
uniform vec2 cell_px = vec2(128.0, 256.0);
// a espada desenhada: o ponto das mãos (no cabo, logo abaixo da guarda), a direção da lâmina (para a ponta) e quantos
// pixels vale o comprimento 1 (das mãos à ponta), medidos no quadro 1 da sheet
uniform vec2 hilt_px = vec2(48.3, 214.2);
uniform vec2 axis_px = vec2(0.244, -0.970);
uniform float px_per_unit = 198.0;
uniform float along_from = -0.22;
uniform float along_to = 1.115;
uniform float across = 0.72;      // largura do quad (comprimentos da espada)
uniform float black_cut = 0.04;
uniform float hdr = 1.8;
instance uniform float frame = 1.0;
instance uniform float intensity = 1.0;

void vertex() {
	vec3 ax = MODEL_MATRIX[1].xyz;
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 axn = normalize(ax);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - (org + ax * 0.5);
	vec3 side = cross(axn, to_cam);
	side = length(side) > 0.0001 ? normalize(side) : normalize(MODEL_MATRIX[0].xyz);
	vec3 wp = org + side * VERTEX.x * wid + ax * VERTEX.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

vec3 frame_rgb(float f, vec2 cuv) {
	float total = float(columns * rows);
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, float(columns)), floor(f / float(columns)));
	// meio texel de margem para não puxar o quadro vizinho no filtro
	vec2 q = clamp(cuv, vec2(0.003), vec2(0.997));
	return texture(sheet, (cell + q) / vec2(float(columns), float(rows))).rgb;
}

void fragment() {
	float a = mix(along_from, along_to, 1.0 - UV.y);
	float s = (UV.x - 0.5) * across;
	vec2 perp = vec2(-axis_px.y, axis_px.x);
	vec2 p = hilt_px + (axis_px * a + perp * s) * px_per_unit;
	vec2 cuv = p / cell_px;
	// fora da célula: nada (e um apagado suave perto da borda dela)
	float inside = smoothstep(0.0, 0.16, cuv.x) * smoothstep(1.0, 0.84, cuv.x) * smoothstep(0.0, 0.07, cuv.y) * smoothstep(1.0, 0.93, cuv.y);
	float f0 = floor(frame);
	vec3 c = mix(frame_rgb(f0, cuv), frame_rgb(f0 + 1.0, cuv), frame - f0);
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.001 ? (mx - mn) / mx : 0.0;
	c *= smoothstep(black_cut, black_cut + 0.06, mx);
	// fogo (saturado) e o miolo branco (muito claro) somam; o cinza da fumaça e do ferro quase não
	c *= max(smoothstep(0.25, 0.6, sat), smoothstep(0.75, 0.95, mx));
	// o mais quente passa de 1 (glow)
	c *= 1.0 + (hdr - 1.0) * smoothstep(0.7, 1.0, mx);
	ALBEDO = c * inside * intensity;
	ALPHA = 1.0;
}
