shader_type spatial;
// Rajada rasteira (ar gelado da Nova Gélida): num quadrado deitado, uma faixa de fiapos que corre do centro
// para fora. A frente é clara e cheia; para trás os fiapos rareiam. Meio transparente, de borda dura.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_front : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 col_trail : source_color = vec4(0.7, 0.9, 1.0, 1.0);
instance uniform float front = 0.0;    // raio da frente (0..1 do quadrado)
instance uniform float erode = 0.0;    // 0 = inteira, 1 = sumiu
instance uniform float seed = 0.0;
instance uniform float opacity = 0.5;

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
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = 0.3;
	float s = (front - r) / band;          // 0 na frente, 1 na cauda
	if (r > 1.0 || s < 0.0 || s > 1.0) {
		discard;
	}
	// fiapos: ruído amarrado à direção (sem emenda em volta) e esticado para fora
	vec2 dir = p / max(r, 0.001);
	// (frequência alta em volta e baixa ao longo do raio: riscos finos apontando para fora)
	float n = noise(dir * 13.0 + vec2(r * 1.6 - front * 2.0) + seed) * 0.6
		+ noise(dir * 31.0 - vec2(r * 3.0) - seed) * 0.4;
	float keep = n - (0.44 + s * 0.5) - erode * 0.9;
	float fw = min(fwidth(keep), 0.1) + 0.0001;
	float alpha = smoothstep(-fw, fw, keep);
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = mix(col_trail.rgb, col_front.rgb, step(s, 0.2));
	ALPHA = alpha * opacity;
}
