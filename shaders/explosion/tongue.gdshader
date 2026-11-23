shader_type spatial;
// Explosão: uma língua de fogo arremessada (linguas_folha.png: 2x2 formas, branco em fundo preto), num quad virado
// para a câmera e rodado por `roll` (o código aponta a cabeça grossa para onde ela voa). `erode` come a forma da
// borda para dentro: a língua afina e some em vez de ficar transparente.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D shapes : source_color, filter_linear_mipmap, repeat_disable;

instance uniform float cell = 0.0;
instance uniform float roll = 0.0;
instance uniform float flip = 0.0;
instance uniform vec3 hot = vec3(1.0, 0.95, 0.7);
instance uniform vec3 body = vec3(1.0, 0.55, 0.1);
instance uniform float erode = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float c = cos(roll);
	float sn = sin(roll);
	vec3 r0 = INV_VIEW_MATRIX[0].xyz;
	vec3 u0 = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + ((r0 * c + u0 * sn) * VERTEX.x + (u0 * c - r0 * sn) * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.y = 1.0 - uv.y;
	}
	vec2 c = vec2(mod(cell, 2.0), floor(cell / 2.0));
	float g = texture(shapes, (c + clamp(uv, 0.01, 0.99)) * 0.5).r;
	ALBEDO = mix(body, hot, smoothstep(0.8, 0.98, g) * (1.0 - erode)) * 1.6;
	ALPHA = smoothstep(0.1 + erode * 0.85, 0.2 + erode * 0.85, g);
}
