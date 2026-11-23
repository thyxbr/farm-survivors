shader_type spatial;
// Pintura da Mãe-Verme num quad: um cacho de cristais, um jorro de terra, uma pedra ou o ácido, tirado de uma
// folha de `cols` x `cols` células. A pintura só tem tons: o branco é a face clara, o cinza a sombreada e as linhas
// pretas são o traço; as três cores entram aqui. Como no gelo, a silhueta vem da mesma pintura borrada (mip baixo),
// então o traço e o contorno ficam na cor da sombra em vez de virar buraco.
//   upright 1     em pé: o pé da pintura fica na origem do nó e o quad gira só em volta do Y do nó para a câmera
//   rise 0 -> 1   a pintura sobe de dentro do chão (o que ainda está abaixo da linha do pé não aparece)
//   erode 0 -> 1  some comida em pedaços, do mais escuro para o mais claro
//   glow          quanto o claro da pintura acende
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform float cols = 2.0;
// altura, dentro da célula, da linha do pé da pintura (0 = a borda de baixo)
uniform float base = 0.0;
// o pé da pintura some aos poucos nesta fração da altura (0 = corte seco)
uniform float foot_fade = 0.0;

instance uniform float cell = 0.0;
instance uniform float roll = 0.0;
instance uniform float flip = 0.0;
instance uniform vec3 core = vec3(0.9, 0.95, 1.0);
instance uniform vec3 mid = vec3(0.1, 0.6, 1.0);
instance uniform vec3 shade = vec3(0.02, 0.04, 0.3);
instance uniform float upright = 0.0;
instance uniform float rise = 1.0;
instance uniform float erode = 0.0;
instance uniform float glow = 0.0;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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
	// altura na pintura: 0 no pé, 1 no topo; subindo, a pintura está deslocada para baixo
	float h = (1.0 - uv.y) + (1.0 - rise);
	float above = 1.0 - step(1.0, h);
	float py = 1.0 - (base + clamp(h, 0.0, 1.0) * (1.0 - base));
	vec2 c = vec2(mod(cell, cols), floor(cell / cols));
	vec2 st = (c + clamp(vec2(uv.x, py), 0.02, 0.98)) / cols;
	float g = texture(paint, st).r;
	float sil = textureLod(paint, st, 3.0).r;
	vec3 col = mix(shade, mid, smoothstep(0.3, 0.62, g));
	col = mix(col, core, smoothstep(0.78, 0.94, g));
	float inside = smoothstep(0.1, 0.22, max(g, sil * 1.5));
	float n = hash(floor(uv * 18.0) + seed * 37.0);
	float keep = step(erode * 1.25, n * 0.75 + g * 0.5);
	ALBEDO = col * (1.0 + glow * smoothstep(0.55, 1.0, g));
	ALPHA = inside * above * keep * smoothstep(-0.001, foot_fade, 1.0 - uv.y);
}
