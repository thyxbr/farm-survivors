shader_type spatial;
// Olhos da provocação: um quadro de assets/vfx/dark_taunt/taunt_eyes.png (8 x 8 quadros, gerado por
// tools/taunt_sheet_bake.gd a partir da sheet com fundo cinza: o fundo já foi tirado, o alfa é o contorno escuro e
// a cor é o brilho vermelho, pré-multiplicada). Billboard sempre de frente para a câmera; `glow` empurra o vermelho
// para HDR (brilho intenso), `intensity` apaga tudo junto (aparecer e sumir).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
// recorte: só a faixa dos olhos dentro do quadro
uniform vec4 crop = vec4(0.1, 0.3, 0.8, 0.4);
uniform float glow = 3.0;
uniform vec3 tint : source_color = vec3(1.0, 0.35, 0.25);
instance uniform float frame = 1.0;
instance uniform float intensity = 1.0;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec4 eye_frame(float f, vec2 uv) {
	f = clamp(f, 0.0, columns * rows - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	vec2 q = clamp(crop.xy + uv * crop.zw, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + q) / vec2(columns, rows));
}

void fragment() {
	float f0 = floor(frame);
	vec4 c = mix(eye_frame(f0, UV), eye_frame(f0 + 1.0, UV), frame - f0);
	// a textura importa como sRGB: a cor pré-multiplicada já vem linearizada; o vermelho vira brasa (HDR)
	float heat = max(c.r, max(c.g, c.b));
	vec3 col = c.rgb * (1.0 + glow * smoothstep(0.05, 0.6, heat)) + tint * heat * glow * 0.35;
	ALBEDO = col * intensity;
	ALPHA = c.a * intensity;
}
