shader_type spatial;
// Círculo da Provocação Sombria: a onda de energia que corre pelo chão quando o herói solta os braços (DarkTauntVFX).
// Anel no chão: frente violeta acesa e um rastro de sombra para dentro, com a borda rasgada por ruído.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform vec3 col_edge : source_color = vec3(0.75, 0.3, 1.0);
uniform vec3 col_shadow : source_color = vec3(0.04, 0.0, 0.07);
instance uniform float intensity = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rag = 0.04 * sin(a * 13.0 + TIME * 6.0) + 0.03 * sin(a * 29.0 - TIME * 4.0) + 0.02 * hash(floor(vec2(a * 20.0, TIME * 12.0)));
	float d = r + rag;
	float edge = exp(-abs(d - 0.95) * 38.0);
	float trail = smoothstep(0.45, 0.95, d) * (1.0 - smoothstep(0.95, 1.0, d));
	ALBEDO = mix(col_shadow, col_edge * 2.2, clamp(edge, 0.0, 1.0));
	ALPHA = clamp(max(edge, trail * 0.55) * intensity, 0.0, 1.0) * step(r, 1.05);
}
