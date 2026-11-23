shader_type spatial;
// Riscos finos de velocidade em volta do anel: arcos soltos, de ponta afinada, girando. Mesma malha do anel
// (wave_ring.gdshader).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

instance uniform vec3 col = vec3(0.28, 0.38, 1.0);
instance uniform float intensity = 1.0;
instance uniform float radius = 1.0;
instance uniform float width = 1.0;
instance uniform float lift = 0.0;
instance uniform float swirl = 0.0;
instance uniform float seed = 0.0;

void vertex() {
	float v = VERTEX.y;
	float r = radius + v * width;
	VERTEX = vec3(VERTEX.x * r, 0.06 + v * lift, VERTEX.z * r);
}

void fragment() {
	float ang = UV.x * TAU;
	float sum = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float y = 0.15 + 0.32 * fi;
		float win = smoothstep(0.6, 1.0, sin(ang * (1.0 + mod(fi, 2.0)) + seed * 3.0 + fi * 1.9 + swirl * (1.0 + 0.3 * fi)));
		float line = 1.0 - smoothstep(0.0, 0.022 * win + 0.001, abs(UV.y - y));
		sum += line * win;
	}
	ALBEDO = mix(col, vec3(1.0), 0.35) * sum * 0.8 * intensity;
	ALPHA = 1.0;
}
