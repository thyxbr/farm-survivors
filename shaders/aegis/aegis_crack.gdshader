shader_type spatial;
// Égide Cristalina: rachaduras de uma placa (AegisCrack), por cima do cristal, no mesmo losango.
// Linhas de Voronoi (as placas se partem em pedaços) somadas a raios que saem do ponto do golpe. Crescem a
// partir do golpe conforme `crack` sobe, e brilham mais quanto mais rachada (azul esquentando para branco, como na sprite sheet).
// Aditivo: só o brilho das fissuras.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec4 col_cold : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform vec4 col_hot : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float intensity = 2.6;    // AegisConfig.crack_intensity
instance uniform float crack = 0.0;              // 0..1
instance uniform vec2 impact = vec2(0.5, 0.35);  // UV do golpe que abriu a rachadura
instance uniform float seed = 0.0;
instance uniform float fade = 1.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// distância à borda entre células (F2 - F1)
float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g + seed);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash2(n + g + seed);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec2 p = UV - 0.5;
	if (abs(p.x) + abs(p.y) > 0.49 || crack <= 0.001) {
		discard;
	}
	vec2 to = UV - impact;
	float dist = length(to);
	// área já rachada: cresce do golpe; a borda do avanço é irregular
	float wob = (hash2(floor(UV * 9.0) + seed).x - 0.5) * 0.12;
	float reach = crack * 1.15 + wob;
	float mask = 1.0 - smoothstep(reach - 0.06, reach, dist);
	// pedaços: mais finos (mais células) quanto mais rachada
	float cells = 2.5 + crack * 2.5;
	float e = voronoi_edge(UV * cells);
	float w = 0.018 + crack * 0.022;
	float fw = fwidth(e) + 0.0001;
	float lines = 1.0 - smoothstep(w - fw, w + fw, e);
	// raios saindo do golpe
	float ang = atan(to.y, to.x);
	float rays = 7.0;
	float ray_d = abs(fract(ang / TAU * rays + hash2(vec2(seed)).x) - 0.5) * dist * TAU / rays;
	float ray = (1.0 - smoothstep(0.004, 0.012, ray_d)) * step(dist, reach * 0.8);
	float k = max(lines * 0.85, ray) * mask;
	float hot = smoothstep(0.45, 1.0, crack);
	float pulse = 0.85 + 0.15 * sin(TIME * 9.0 + seed * 20.0);
	vec3 c = mix(col_cold.rgb, col_hot.rgb, hot);
	ALBEDO = c * k * intensity * (0.6 + crack * 0.9) * pulse * fade;
	ALPHA = 1.0;
}
