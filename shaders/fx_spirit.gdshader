shader_type spatial;
// Anjo-espírito da subida de nível (quad 1x1 com a imagem, sempre de frente para a câmera).
// Translúcido e dourado: a cor da imagem é quase toda trocada por um dourado claro que segue o brilho
// dela, com um halo suave em volta da silhueta, a borda tremulando como chama fria e os pés sumindo
// num rastro. `fade` (por instância) acende e apaga.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0, 0.78, 0.18);  // dourado do espírito (mesmo tom da coluna)
uniform vec3 glow_col : source_color = vec3(1.0, 0.88, 0.45); // halo dourado
uniform float keep_color = 0.12;                             // quanto da cor original sobra
uniform float body_alpha = 0.7;
uniform float glow_radius = 0.035;
instance uniform float fade = 1.0;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	// tremulado: as linhas da imagem ondulam de lado, mais forte embaixo (o rastro)
	float low = smoothstep(0.45, 1.0, uv.y);
	uv.x += sin(uv.y * 22.0 - TIME * 7.0) * (0.002 + 0.01 * low);
	vec4 c = texture(tex, uv);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 ghost = mix(tint * (0.85 + 0.45 * lum), c.rgb, keep_color);
	ghost = mix(ghost, vec3(1.0, 0.97, 0.85), 0.12 + 0.35 * lum * lum);   // miolo claro, quase branco
	// halo: média do alfa em volta (silhueta borrada)
	float halo = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = 6.2832 * float(i) / 12.0;
		halo += texture(tex, uv + vec2(cos(a), sin(a)) * glow_radius).a;
		halo += texture(tex, uv + vec2(cos(a + 0.26), sin(a + 0.26)) * glow_radius * 2.0).a * 0.6;
	}
	halo = clamp(halo / 19.2, 0.0, 1.0);
	float shimmer = 0.85 + 0.15 * sin(TIME * 5.0 + uv.y * 9.0);
	float body = c.a * body_alpha * shimmer;
	float glow = halo * (1.0 - c.a) * (0.6 + 0.15 * sin(TIME * 8.0));
	// pés somem num rastro
	float tail = 1.0 - smoothstep(0.72, 1.0, UV.y);
	ALBEDO = mix(glow_col, ghost, c.a);
	ALPHA = clamp(body + glow, 0.0, 1.0) * tail * fade;
}
