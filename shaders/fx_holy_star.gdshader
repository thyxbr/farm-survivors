shader_type spatial;
// Estrela "desenhada" sempre de frente para a câmera (quad 2x2, UV 0..1): brilho de 4 pontas ou
// estouro de impacto de várias pontas. Borda dura, três tons chapados, some encolhendo por erosão.
// Um material só: tudo o que muda vem por instância.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 0.9, 1.0);
instance uniform vec4 col_mid : source_color = vec4(1.0, 0.8, 0.25, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.75, 0.35, 0.05, 1.0);
instance uniform float head = 1.0;    // 0..1: abre do centro para fora
instance uniform float erode = 0.0;
instance uniform float seed = 0.0;
instance uniform float core = 1.0;
instance uniform float points = 4.0;  // número de pontas
instance uniform float sharp = 5.0;   // maior = pontas mais finas
instance uniform float body = 0.16;   // raio do miolo entre as pontas (0..1)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// de frente para a câmera, mantendo a escala do nó
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + seed * 0.37 * step(4.5, points);   // o estouro gira a cada quadro desenhado
	float spike = pow(abs(cos(ang * points * 0.5)), sharp);
	// cada ponta do estouro tem um comprimento (ruído por ponta)
	float idx = floor(ang * points / 6.2832 + 0.5);
	float len = mix(1.0, 0.6 + 0.4 * hash(vec2(idx, floor(seed * 7.7))), step(4.5, points));
	float R = mix(body, len, spike) * head;
	float d = 1.0 - r / max(R, 0.001);                     // 1 no centro, 0 na borda
	float m = min(d * 3.0, (d - erode * 1.05) * 4.0);
	float fw = min(fwidth(m), 0.2) + 0.0001;
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	float mid_at = 0.2 + erode * 0.6;
	float core_at = 0.5 + erode * 0.6;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(mid_at - fw, mid_at + fw, d));
	c = mix(c, col_core.rgb, smoothstep(core_at - fw, core_at + fw, d) * core);
	ALBEDO = c;
	ALPHA = alpha * col_mid.a;
}
