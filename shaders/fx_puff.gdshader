shader_type spatial;
// Baforada "desenhada" (fumaça, fogo que estufa, névoa): um cacho de bolas num quadrado sempre de frente
// para a câmera, com três tons chapados como se cada bola fosse iluminada de cima e da esquerda. Some
// encolhendo as bolas, cada uma no seu ritmo, em vez de ficar transparente.
// Um material só: cor, erosão e semente vêm por instância (FXToon.puff).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.7, 0.7, 0.7, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.3, 0.3, 0.3, 1.0);
instance uniform float erode = 0.0;   // 0 = inteira, 1 = sumiu
instance uniform float seed = 0.0;    // forma do cacho
instance uniform float boil = 0.0;    // relógio em passos: as bolas tremem como desenho quadro a quadro

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	// de frente para a câmera, mantendo a escala do nó
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;                                       // y para cima
	float best = -1.0;
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		// uma bola no meio e seis em volta
		float ang = fi * 1.0472 + seed * 6.2832 + hash1(fi + seed) * 0.7;
		float off = (i == 0) ? 0.0 : 0.4 + 0.12 * hash1(fi * 3.1 + seed);
		vec2 c = vec2(cos(ang), sin(ang)) * off + 0.025 * vec2(sin(boil * 5.0 + fi), cos(boil * 4.0 + fi * 2.0));
		float r = (i == 0) ? 0.5 : 0.28 + 0.15 * hash1(fi * 7.7 + seed * 2.0);
		r *= clamp(1.0 - erode * (0.95 + 0.7 * hash1(fi * 1.3 + seed)), 0.0, 1.0);
		vec2 d = p - c;
		float z2 = r * r - dot(d, d);
		if (z2 > 0.0) {
			float z = sqrt(z2);
			if (z > best) {
				best = z;
				nrm = vec3(d, z) / r;
			}
		}
	}
	if (best <= 0.0) {
		discard;
	}
	float light = dot(nrm, normalize(vec3(-0.45, 0.65, 0.6)));
	float fw = min(fwidth(light), 0.1) + 0.0001;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(0.08 - fw, 0.08 + fw, light));
	c = mix(c, col_core.rgb, smoothstep(0.66 - fw, 0.66 + fw, light));
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.035, best) * col_mid.a;
}
