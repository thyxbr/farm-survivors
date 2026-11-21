shader_type spatial;
// Aviso de golpe em cone no chão (Martelada do Forjador Rúnico): a borda dura marca o leque desde o começo e o
// miolo enche da ponta de quem bate para fora até o golpe cair (`reveal` 0..1). Mesma leitura do aviso redondo
// (fx_telegraph): linhas carmim, miolo escuro em listras. A malha é um plano de 2x2 com o chefe no centro; o
// cone abre para +Z do plano, `half` radianos para cada lado.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_line : source_color = vec4(1.0, 0.3, 0.14, 1.0);
instance uniform vec4 col_fill : source_color = vec4(0.92, 0.1, 0.05, 1.0);
instance uniform float reveal = 0.0;
instance uniform float fade = 0.0;     // 0 = inteiro, 1 = sumiu
instance uniform float half = 0.63;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float th = atan(p.x, p.y);      // 0 = +Z do plano
	if (r > 1.0 || abs(th) > half) {
		discard;
	}
	// distância (em unidades do plano) até os dois raios da borda, o arco de fora e a frente do miolo
	float side = r * sin(half - abs(th));
	float d = side - 0.012;
	d = min(d, abs(r - 0.985) - 0.012);
	float front = clamp(reveal, 0.0, 1.0) * 0.97;
	d = min(d, abs(r - front) - 0.008);
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float line = 1.0 - smoothstep(-fw, fw, d);
	float stripes = step(0.5, fract(th * 9.0 / half));
	float fill = step(r, front) * (0.22 + 0.14 * stripes) + 0.08;
	ALBEDO = mix(col_fill.rgb, col_line.rgb, line);
	ALPHA = max(line * col_line.a, fill) * (1.0 - fade);
}
