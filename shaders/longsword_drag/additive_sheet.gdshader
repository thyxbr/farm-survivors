shader_type spatial;
// Corte do Abismo: um quadro de sprite sheet com fundo preto (#000000) desenhado com mistura ADITIVA (o preto não soma
// nada). Serve às duas folhas da habilidade:
//   drag_sparks_sheet.webp   4 x 8 quadros de 256 x 128 px (fagulhas da ponta raspando o chão, vistas de lado)
//   rising_claws_sheet.webp  6 x 6 quadros de ~170 px com linhas de grade cinza (arco do corte e garras espectrais)
// O quad é um QuadMesh 1 x 1; o nó dá o tamanho pela escala dos eixos X (largura) e Y (altura).
//   billboard 0  plano fixo, como o nó está
//             1  gira em volta do eixo Y do nó (de pé) para encarar a câmera: garras e arco do corte
//             2  gira em volta do eixo X do nó (o comprimento) para encarar a câmera: as fagulhas deitadas ao longo
//                do caminho da ponta (a altura do quadro fica sempre do lado de cima)
// Dois quadros (`frame_a`, `frame_b`) misturados por `blend`: a troca de quadro é um cross-fade, sem salto.
// O cinza do desenho (chão de pedra, fumaça, lâmina, linhas de grade) é tirado pela saturação: só o fogo e a energia
// (cores saturadas) e o miolo muito claro somam. `key_grey` 0 desliga isso.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform int columns = 8;
uniform int rows = 8;
// margem tirada de cada borda da célula (fração dela): pula as linhas de grade e o sangramento do filtro
uniform vec2 inset = vec2(0.004, 0.004);
uniform int billboard = 0;
uniform float black_cut = 0.035;
uniform float key_grey = 1.0;
uniform float sat_lo = 0.22;
uniform float sat_hi = 0.55;
uniform float bright_lo = 0.72;
uniform float hdr = 1.7;
uniform vec3 tint = vec3(1.0);
// apagado suave nas bordas do quad (fração): sem corte reto onde o desenho encosta na célula
uniform vec4 edge_fade = vec4(0.05, 0.05, 0.05, 0.02);   // esquerda, direita, cima, baixo
instance uniform float frame_a = 0.0;
instance uniform float frame_b = 0.0;
instance uniform float blend = 0.0;
instance uniform float intensity = 1.0;
instance uniform float flip_x = 0.0;

void vertex() {
	if (billboard != 0) {
		vec3 org = MODEL_MATRIX[3].xyz;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		if (billboard == 1) {
			vec3 ax = MODEL_MATRIX[1].xyz;
			vec3 axn = normalize(ax);
			float wid = length(MODEL_MATRIX[0].xyz);
			vec3 to_cam = cam - (org + ax * 0.5);
			vec3 side = cross(axn, to_cam);
			side = length(side) > 0.0001 ? normalize(side) : normalize(MODEL_MATRIX[0].xyz);
			vec3 wp = org + side * VERTEX.x * wid + ax * VERTEX.y;
			POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
		} else {
			vec3 ax = MODEL_MATRIX[0].xyz;
			vec3 axn = normalize(ax);
			float hgt = length(MODEL_MATRIX[1].xyz);
			vec3 to_cam = normalize(cam - org);
			vec3 n = to_cam - axn * dot(to_cam, axn);
			n = length(n) > 0.0001 ? normalize(n) : normalize(MODEL_MATRIX[2].xyz);
			vec3 up = cross(n, axn);
			up *= sign(dot(up, vec3(0.0, 1.0, 0.0)) + 0.0001);
			vec3 wp = org + ax * VERTEX.x + up * VERTEX.y * hgt;
			POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
		}
	}
}

vec3 cell_rgb(float f, vec2 uv) {
	float total = float(columns * rows);
	f = clamp(floor(f + 0.5), 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, float(columns)), floor(f / float(columns)));
	vec2 q = mix(inset, vec2(1.0) - inset, uv);
	return texture(sheet, (cell + q) / vec2(float(columns), float(rows))).rgb;
}

vec3 keyed(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.001 ? (mx - mn) / mx : 0.0;
	c *= smoothstep(black_cut, black_cut + 0.06, mx);
	float keep = max(smoothstep(sat_lo, sat_hi, sat), smoothstep(bright_lo, bright_lo + 0.2, mx));
	c *= mix(1.0, keep, key_grey);
	// o mais quente passa de 1 (o glow pega nele)
	return c * (1.0 + (hdr - 1.0) * smoothstep(0.65, 1.0, mx));
}

void fragment() {
	vec2 uv = UV;
	if (flip_x > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec3 a = keyed(cell_rgb(frame_a, uv));
	vec3 b = keyed(cell_rgb(frame_b, uv));
	vec3 c = mix(a, b, clamp(blend, 0.0, 1.0));
	float fade = smoothstep(0.0, edge_fade.x + 0.0001, UV.x) * smoothstep(1.0, 1.0 - edge_fade.y - 0.0001, UV.x)
		* smoothstep(0.0, edge_fade.z + 0.0001, UV.y) * smoothstep(1.0, 1.0 - edge_fade.w - 0.0001, UV.y);
	ALBEDO = c * tint * fade * intensity;
	ALPHA = 1.0;
}
