shader_type spatial;
// Gelo pintado num quad virado para a câmera: o cacho de cristais (gelo_floracao.png) ou um cristal solto da folha
// 2x2 (gelo_cristais.png). A pintura só tem tons: o branco é a face clara, o cinza a face sombreada, e as linhas
// pretas são o traço. As três cores entram aqui (gelo claro, azul, sombra carmim do gelo de monstro). Para o traço
// e o contorno não virarem buraco, a silhueta vem da mesma pintura borrada (mip baixo): o que fica dentro dela e é
// escuro na pintura é pintado na cor da sombra.
//   grow  0 -> 1  o cacho abre do centro para fora        fade  1 -> 0  some das pontas para o centro
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform float cols = 1.0;

instance uniform float cell = 0.0;
instance uniform float roll = 0.0;
instance uniform float flip = 0.0;
instance uniform vec3 core = vec3(0.7, 0.93, 1.0);
instance uniform vec3 mid = vec3(0.1, 0.45, 0.95);
instance uniform vec3 shade = vec3(0.21, 0.004, 0.04);
instance uniform float grow = 1.0;
instance uniform float fade = 1.0;
// 1 = em pé: o quad gira só em volta do Y do nó para a câmera (a estaca cravada, os cacos do pé)
instance uniform float upright = 0.0;
instance uniform float flipv = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float c = cos(roll);
	float sn = sin(roll);
	vec3 r0 = INV_VIEW_MATRIX[0].xyz;
	vec3 u0 = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + ((r0 * c + u0 * sn) * VERTEX.x + (u0 * c - r0 * sn) * VERTEX.y) * s;
	if (upright > 0.5) {
		vec3 axis = normalize(MODEL_MATRIX[1].xyz);
		vec3 side = cross(axis, normalize(CAMERA_POSITION_WORLD - origin));
		side = length(side) > 0.001 ? normalize(side) : r0;
		world = origin + side * VERTEX.x * s + axis * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	if (flipv > 0.5) {
		uv.y = 1.0 - uv.y;
	}
	vec2 c = vec2(mod(cell, cols), floor(cell / cols));
	vec2 st = (c + clamp(uv, 0.03, 0.97)) / cols;
	float g = texture(paint, st).r;
	float sil = textureLod(paint, st, 3.0).r;
	float r = length(uv - 0.5) * 2.0;
	vec3 col = mix(shade, mid, smoothstep(0.3, 0.62, g));
	col = mix(col, core, smoothstep(0.78, 0.94, g));
	float inside = smoothstep(0.1, 0.22, max(g, sil * 1.5));
	float open = 1.0 - smoothstep(grow - 0.08, grow + 0.02, r);
	float keep = 1.0 - smoothstep(fade - 0.05, fade + 0.25, r);
	ALBEDO = col * (1.0 + 0.5 * smoothstep(0.85, 1.0, g));
	ALPHA = inside * open * keep;
}
