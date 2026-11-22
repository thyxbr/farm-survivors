shader_type spatial;
// Lâmina Suprema: uma alma fugindo da cratera (DarkSouls). Um QuadMesh 1 x 1 de pé ao longo do eixo Y do nó (a direção
// do voo: a cabeça vai na frente) que gira em volta dele para encarar a câmera. Desenhada no shader: cabeça pálida
// violeta com as órbitas e a boca escuras (gritando), o corpo afinando numa cauda de fumaça que tremula e se desfaz.
// Mistura normal: o escuro dos olhos e da boca aparece; o claro passa de 1 (o glow pega).
//   intensity  0..1 (o nascer e o sumir)     seed  muda o tremular de cada alma
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 core_col = vec3(1.45, 1.25, 1.9);
uniform vec3 body_col = vec3(0.62, 0.3, 1.0);
uniform vec3 tail_col = vec3(0.32, 0.05, 0.3);
uniform vec3 hole_col = vec3(0.02, 0.0, 0.035);
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	vec3 axn = normalize(ax);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = cross(axn, cam - org);
	side = length(side) > 0.0001 ? normalize(side) : normalize(MODEL_MATRIX[0].xyz);
	vec3 wp = org + side * VERTEX.x * wid + ax * VERTEX.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return dot(d, d);
}

void fragment() {
	// UV.y = 0 em cima (a cabeça, na frente do voo) e 1 embaixo (a ponta da cauda)
	vec2 p = UV;
	float wob = (texture(noise_tex, vec2(seed + TIME * 0.6, p.y * 1.5 - TIME * 1.8)).r - 0.5) * 0.35 * smoothstep(0.25, 1.0, p.y);
	p.x += wob;
	float n = texture(noise_tex, vec2(p.x * 2.0 + seed, p.y * 2.5 - TIME * 2.2)).r;
	// cabeça e corpo afinando até a cauda
	float head = 1.0 - smoothstep(0.75, 1.0, ellipse(p, vec2(0.5, 0.24), vec2(0.2, 0.17)));
	float half_w = mix(0.2, 0.015, smoothstep(0.24, 1.0, p.y)) * (0.8 + 0.5 * n);
	float body = (1.0 - smoothstep(half_w * 0.5, half_w, abs(p.x - 0.5))) * step(0.24, p.y);
	body *= 1.0 - smoothstep(0.7, 1.0, p.y);
	float shape = max(head, body);
	if (shape < 0.01) {
		discard;
	}
	// olhos e boca: buracos escuros, a boca aberta num grito
	float eyes = max(1.0 - smoothstep(0.6, 1.0, ellipse(p, vec2(0.42, 0.22), vec2(0.045, 0.06))),
		1.0 - smoothstep(0.6, 1.0, ellipse(p, vec2(0.58, 0.22), vec2(0.045, 0.06))));
	float mouth = 1.0 - smoothstep(0.55, 1.0, ellipse(p, vec2(0.5, 0.33), vec2(0.04, 0.065 + 0.015 * sin(TIME * 9.0 + seed))));
	float holes = max(eyes, mouth) * head;
	float core = 1.0 - smoothstep(0.0, 0.9, ellipse(p, vec2(0.5, 0.26), vec2(0.16, 0.24)));
	vec3 c = mix(tail_col, body_col, 1.0 - smoothstep(0.3, 0.95, p.y));
	c = mix(c, core_col, clamp(core * 1.2, 0.0, 1.0));
	c += body_col * 0.6 * (1.0 - smoothstep(0.0, 0.08, abs(n - 0.5))) * (1.0 - head);
	c = mix(c, hole_col, holes);
	ALBEDO = c;
	ALPHA = clamp(shape * (0.55 + 0.45 * max(core, holes)) * (1.0 - smoothstep(0.5, 1.0, p.y) * (1.0 - n) * 0.8) * intensity, 0.0, 1.0);
}
