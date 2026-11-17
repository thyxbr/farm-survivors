shader_type spatial;
// Esfera ou anel de energia "desenhado", num quadrado sempre de frente para a câmera: três tons chapados
// em faixas redondas e a borda tremendo como traço refeito a cada quadro. Com `inner` = 0 é um disco
// (núcleo claro no meio, cor, borda escura); com `inner` > 0 é um anel (claro no meio da faixa).
// Um material só: cor, furo e relógio vêm por instância (FXToon.orb, FXToon.pop).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.55, 0.8, 1.0, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.12, 0.2, 0.45, 1.0);
instance uniform float inner = 0.0;   // raio do furo (0 = disco; perto de 1 = anel fino)
instance uniform float seed = 0.0;
instance uniform float boil = 0.0;    // relógio em passos

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
	float r = length(p);
	float th = atan(p.y, p.x);
	float wob = 0.035 * sin(th * 5.0 + boil * 1.7 + seed * 6.0) + 0.02 * sin(th * 9.0 - boil * 2.3 + seed);
	float outer = 0.84 + wob;
	float hole = inner * outer;
	float t = (r - hole) / max(outer - hole, 0.001);      // 0 na borda de dentro, 1 na de fora
	float m = min(t, 1.0 - t) * (outer - hole);
	float fw = min(fwidth(r), 0.05) + 0.0001;
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	// disco: claro no centro; anel: claro no meio da faixa
	float k = mix(t, abs(t - 0.5) * 2.0, step(0.001, inner));
	vec3 c = col_core.rgb;
	c = mix(c, col_mid.rgb, smoothstep(0.42 - fw * 2.0, 0.42 + fw * 2.0, k + wob * 1.5));
	c = mix(c, col_edge.rgb, smoothstep(0.8 - fw * 2.0, 0.8 + fw * 2.0, k));
	ALBEDO = c;
	ALPHA = alpha * col_mid.a;
}
