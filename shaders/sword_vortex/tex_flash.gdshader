shader_type spatial;
// Vórtice Sombrio: o clarão do golpe final pintado (clarao.png: núcleo, raios e anel de choque claros em fundo preto).
// Quad virado para a câmera, aditivo; o claro da pintura vira brilho: branco no mais forte, a cor da arma no resto.
// Animado por código (SwordVortexFX._tex_flash): abre de golpe, gira um pouco e apaga.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D flare : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec3 col = vec3(0.6, 0.3, 1.0);
instance uniform float intensity = 1.0;
instance uniform float spin = 0.0;

void vertex() {
	float c = cos(spin);
	float s = sin(spin);
	vec2 q = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c);
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * q.y) * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float g = texture(flare, UV).r;
	vec3 c = mix(col, vec3(1.0), smoothstep(0.55, 1.0, g));
	ALBEDO = c * g * 2.2 * intensity;
	ALPHA = 1.0;
}
