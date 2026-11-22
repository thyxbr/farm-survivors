shader_type spatial;
// Bola de fogo do cajado (FireballProjectile): um quadro da folha assets/vfx/fireball/fireball_sheet.webp (8 x 8 quadros
// de 128 px, fundo preto #000000) desenhado com mistura ADITIVA: o preto não soma nada, então some sem alfa.
// O quad (QuadMesh 1 x 1) encara sempre a câmera; o tamanho vem da escala do nó.
//   `travel` = (0,0,0): quad de pé, quadros `frame_a` -> `frame_b` misturados por `blend` (carga e explosão).
//   `travel` = direção do voo: o quad gira na tela para a cauda ficar atrás do movimento (o desenho voa para +X).
//             Voando de lado mostra `frame_b` (bola com cauda); voando para longe/para perto da câmera a cauda
//             encurtaria até sumir, então mistura para `frame_a` (bola quase redonda).
// `pivot_a`/`pivot_b`: ponto da célula (UV) que fica na origem do nó, de cada quadro (o miolo da bola, ou a base da
// explosão), para o desenho não "andar" ao trocar de quadro.
// A fumaça cinza do desenho é tirada pela saturação (somada, viraria névoa clara): só o fogo e o miolo branco somam.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform int columns = 8;
uniform int rows = 8;
// margem tirada de cada borda da célula (fração dela): sem sangramento do quadro vizinho pelo filtro
uniform vec2 inset = vec2(0.006, 0.006);
uniform float black_cut = 0.03;
uniform float key_grey = 1.0;
uniform float sat_lo = 0.2;
uniform float sat_hi = 0.5;
uniform float bright_lo = 0.7;
uniform float hdr = 1.8;
uniform vec3 tint = vec3(1.0);
// quanto da direção do voo aparece na tela (0..1) para trocar a bola redonda pela bola com cauda
uniform float tail_lo = 0.25;
uniform float tail_hi = 0.7;
uniform vec4 edge_fade = vec4(0.04, 0.04, 0.04, 0.04);   // esquerda, direita, cima, baixo
instance uniform float frame_a = 0.0;
instance uniform float frame_b = 0.0;
instance uniform float blend = 0.0;
instance uniform float intensity = 1.0;
instance uniform vec2 pivot_a = vec2(0.5, 0.5);
instance uniform vec2 pivot_b = vec2(0.5, 0.5);
instance uniform vec3 travel = vec3(0.0);

varying float v_mix;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float m = blend;
	vec2 dir2 = vec2(1.0, 0.0);
	if (dot(travel, travel) > 0.0001) {
		vec3 v = mat3(VIEW_MATRIX) * normalize(travel);
		float s = length(v.xy);
		m = smoothstep(tail_lo, tail_hi, s);
		dir2 = s > 0.0001 ? v.xy / s : vec2(1.0, 0.0);
	}
	v_mix = m;
	vec2 piv = mix(pivot_a, pivot_b, m);
	// VERTEX.xy em -0,5..0,5 com +Y para cima; o UV cresce para baixo
	vec2 q = VERTEX.xy - vec2(piv.x - 0.5, 0.5 - piv.y);
	q = vec2(q.x * dir2.x - q.y * dir2.y, q.x * dir2.y + q.y * dir2.x);
	vec3 wp = org + INV_VIEW_MATRIX[0].xyz * q.x * sx + INV_VIEW_MATRIX[1].xyz * q.y * sy;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
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
	vec3 a = keyed(cell_rgb(frame_a, UV));
	vec3 b = keyed(cell_rgb(frame_b, UV));
	vec3 c = mix(a, b, clamp(v_mix, 0.0, 1.0));
	float fade = smoothstep(0.0, edge_fade.x + 0.0001, UV.x) * smoothstep(1.0, 1.0 - edge_fade.y - 0.0001, UV.x)
		* smoothstep(0.0, edge_fade.z + 0.0001, UV.y) * smoothstep(1.0, 1.0 - edge_fade.w - 0.0001, UV.y);
	ALBEDO = c * tint * fade * intensity;
	ALPHA = 1.0;
}
