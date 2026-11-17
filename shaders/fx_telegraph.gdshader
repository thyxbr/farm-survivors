shader_type spatial;
// Aviso de ataque em área no chão: um anel de borda dura marca o raio desde o começo e o miolo enche do
// centro para fora até o golpe cair (`reveal` 0..1), com listras que giram devagar para chamar a atenção.
// Mesmos parâmetros dos desenhos de chão (fx_frost_sigil, fx_rune_circle).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_line : source_color = vec4(1.0, 0.25, 0.12, 1.0);
instance uniform vec4 col_fill : source_color = vec4(0.9, 0.1, 0.05, 1.0);
instance uniform float reveal = 0.0;   // quanto do raio o miolo já encheu
instance uniform float erode = 0.0;    // 0 = inteiro, 1 = sumiu
instance uniform float seed = 0.0;
instance uniform float spin = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float th = atan(p.y, p.x) + spin;
	// anel de fora, um anel fino por dentro e a frente do miolo
	float d = abs(r - 0.95) - 0.02;
	d = min(d, abs(r - 0.86) - 0.006);
	float front = clamp(reveal, 0.0, 1.0) * 0.86;
	d = min(d, abs(r - front) - 0.012);
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float line = 1.0 - smoothstep(-fw, fw, d);
	// miolo: listras radiais chapadas, só até a frente
	float stripes = step(0.5, fract(th * 12.0 / TAU));
	float fill = step(r, front) * (0.2 + 0.14 * stripes) + step(r, 0.95) * 0.07;
	float gone = step(erode, 0.001) + (1.0 - step(erode, 0.001)) * step(erode, 1.0 - r * 0.6);
	ALBEDO = mix(col_fill.rgb, col_line.rgb, line);
	ALPHA = max(line * col_line.a, fill) * gone * (1.0 - erode);
}
