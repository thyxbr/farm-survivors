shader_type spatial;
// Bolha de proteção em volta do personagem (SphereMesh): transparente no meio, borda acesa,
// favos de mel bem fracos e uma faixa de luz que sobe de vez em quando.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float strength = 0.8;
uniform float hex_scale = 7.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// distância até a borda do hexágono mais próximo (0 na borda)
float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float ang = atan(lp.z, lp.x);
	vec2 uv = vec2(ang * 1.2, lp.y * 1.6) * hex_scale / 3.0;
	float cells = smoothstep(0.06, 0.0, hex_edge(uv));
	// faixa de luz subindo
	float sweep = smoothstep(0.18, 0.0, abs(fract(lp.y * 0.45 - TIME * 0.35) - 0.5));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	ALBEDO = color.rgb;
	ALPHA = (fres * 0.9 + cells * (0.08 + fres * 0.5 + sweep * 0.35) + sweep * 0.06) * strength * pulse;
}
