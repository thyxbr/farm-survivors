shader_type spatial;
// O chão escurece por dentro do anel (o contraste que faz a crista acender). Plano deitado, borda macia.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

instance uniform float intensity = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0, 0.0, 0.02);
	ALPHA = (1.0 - smoothstep(0.7, 1.0, r)) * (0.35 + 0.65 * smoothstep(0.2, 0.9, r)) * intensity;
}
