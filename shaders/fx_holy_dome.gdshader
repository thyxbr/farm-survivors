shader_type spatial;
// Onda de choque em domo "desenhada": só a silhueta da meia esfera aparece, em faixas chapadas de
// borda dura (fresnel em degraus), e some por erosão. Um material só: o que muda vem por instância.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_core : source_color = vec4(1.0, 1.0, 0.9, 1.0);
instance uniform vec4 col_mid : source_color = vec4(1.0, 0.8, 0.25, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.75, 0.35, 0.05, 1.0);
instance uniform float head = 1.0;
instance uniform float erode = 0.0;
instance uniform float seed = 0.0;
instance uniform float core = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = UV.x * 6.2832;
	float n = noise(vec2(cos(a), sin(a)) * 3.0 + vec2(seed, UV.y * 9.0 - seed * 2.0));
	float d = (fres - (0.62 + erode * 0.5) + (n - 0.5) * 0.3) / 0.38;   // 0 onde a faixa começa, 1 na silhueta
	float m = d * 5.0;
	float fw = min(fwidth(m), 0.2) + 0.0001;
	float alpha = smoothstep(-fw, fw, m);
	if (alpha < 0.01) {
		discard;
	}
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, smoothstep(0.25 - fw, 0.25 + fw, d));
	c = mix(c, col_core.rgb, smoothstep(0.7 - fw, 0.7 + fw, d) * core);
	ALBEDO = c;
	ALPHA = alpha * col_mid.a * head;
}
