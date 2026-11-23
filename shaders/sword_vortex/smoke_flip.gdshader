shader_type spatial;
// Vórtice Sombrio: tufo de fumaça do giro (MultiMesh em SwordVortexFX._step_orbit). Quad virado para a câmera que
// toca a folha fumaca_folha.png (4x4 quadros de uma baforada se desfazendo, fumaça clara em fundo preto: o claro é a
// opacidade e o sombreado). Por instância: COLOR = cor e opacidade; INSTANCE_CUSTOM.x = quadro (0..15, misturando
// dois vizinhos), .y = rotação no plano da tela (rad).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
// claro e escuro da fumaça a partir do cinza da folha (o sombreado pintado vira volume)
uniform float shade_lo = 0.35;
uniform float shade_hi = 1.15;

varying float v_frame;

void vertex() {
	v_frame = INSTANCE_CUSTOM.x;
	float a = INSTANCE_CUSTOM.y;
	vec2 q = vec2(VERTEX.x * cos(a) - VERTEX.y * sin(a), VERTEX.x * sin(a) + VERTEX.y * cos(a));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + INV_VIEW_MATRIX[0].xyz * q.x * sx + INV_VIEW_MATRIX[1].xyz * q.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float cell(vec2 uv, float f) {
	float i = clamp(floor(f), 0.0, 15.0);
	vec2 o = vec2(mod(i, 4.0), floor(i / 4.0));
	return texture(sheet, (o + clamp(uv, 0.002, 0.998)) / 4.0).r;
}

void fragment() {
	float f = clamp(v_frame, 0.0, 14.999);
	float g = mix(cell(UV, f), cell(UV, f + 1.0), fract(f));
	ALBEDO = COLOR.rgb * mix(shade_lo, shade_hi, g);
	ALPHA = smoothstep(0.03, 0.45, g) * COLOR.a;
}
