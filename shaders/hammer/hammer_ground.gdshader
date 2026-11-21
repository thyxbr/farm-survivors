shader_type spatial;
// Martelo de Energia: marcas no chão, desenhadas por conta (sem textura esticada), num quad deitado.
//   kind 0 = cratera (GroundCrater): bacia escura no meio, borda levantada de terra, rachaduras saindo para fora
//            e energia residual azul pulsando no fundo.
//   kind 1 = rachaduras do impacto (HammerImpact): rachaduras longas e luminosas do centro até a borda do raio,
//            com o chão queimado no miolo.
// Mistura normal: o escuro escurece o chão do jogo e as rachaduras acesas brilham por cima (cor HDR > 1).
// `appear` 0..1 = as rachaduras correndo do centro para fora; `energy` = brilho delas (some aos poucos);
// `fade` = opacidade geral (some no fim); `seed` = forma diferente para cada marca.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform int kind = 0;
uniform vec3 col_hot : source_color = vec3(0.6, 0.85, 1.0);
uniform vec3 col_warm : source_color = vec3(1.0, 0.68, 0.22);
uniform vec3 col_dark : source_color = vec3(0.05, 0.045, 0.05);
uniform vec3 col_rim : source_color = vec3(0.26, 0.21, 0.16);
instance uniform float appear = 1.0;
instance uniform float energy = 1.0;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// rachaduras radiais: `n` raios com o ângulo tremendo pela distância (zigue-zague) e galhos curtos;
// devolve a intensidade da linha (1 no traço) e o comprimento relativo em `len`
float cracks(vec2 p, float n, float reach, float thick, float s) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float best = 0.0;
	float sector = TAU / n;
	float px = fwidth(r) * 1.2 + 0.0005;
	for (int i = 0; i < 14; i++) {
		if (float(i) >= n) {
			break;
		}
		float fi = float(i);
		float base = (fi + hash(vec2(fi, s)) * 0.6) * sector;
		float len = reach * (0.55 + 0.45 * hash(vec2(s, fi + 4.0)));
		// ângulo do raio nesta distância: zigue-zague que cresce para fora
		float ang = base + (noise(vec2(r * 7.0, fi * 3.7 + s)) - 0.5) * 0.55 * r;
		float da = abs(mod(a - ang + PI, TAU) - PI);
		float d = da * r;
		float w = thick * (1.0 - 0.75 * smoothstep(0.0, len, r));
		float line = (1.0 - smoothstep(w, w + px, d)) * step(r, len);
		// galho: sai no meio do raio, para um lado
		float bstart = len * (0.35 + 0.3 * hash(vec2(fi, s + 9.0)));
		float side = hash(vec2(fi + 2.0, s)) > 0.5 ? 1.0 : -1.0;
		float bang = ang + side * (0.25 + 0.5 * (r - bstart) / max(len, 0.001));
		float bda = abs(mod(a - bang + PI, TAU) - PI) * r;
		float bline = (1.0 - smoothstep(w * 0.7, w * 0.7 + px, bda)) * step(bstart, r) * step(r, bstart + len * 0.35);
		best = max(best, max(line, bline));
	}
	return best;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float n = noise(p * 5.0 + seed) * 0.6 + noise(p * 13.0 - seed) * 0.4;
	float grow = appear * 1.05;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (kind == 0) {
		// bacia escura (borda irregular), borda de terra levantada
		float rr = r + (n - 0.5) * 0.18;
		float bowl = 1.0 - smoothstep(0.38, 0.62, rr / max(grow, 0.01));
		float rim = exp(-pow((rr / max(grow, 0.01) - 0.68) / 0.12, 2.0)) * step(0.01, grow);
		float c = cracks(p, 7.0, 1.0 * grow, 0.03, seed);
		float pulse = 0.65 + 0.35 * sin(TIME * 5.0 + seed * 3.0);
		vec3 hot = mix(col_warm, col_hot, smoothstep(0.1, 0.8, r));
		col = mix(col_rim * (0.7 + 0.5 * n), col_dark, bowl);
		alpha = max(bowl * 0.88, rim * 0.6) * (0.75 + 0.25 * n);
		// energia residual no fundo da cratera
		float res = exp(-r * 5.0) * energy * pulse;
		col += col_hot * res * 2.5;
		alpha = max(alpha, res);
		col = mix(col, hot * 2.6 * (0.6 + 0.4 * pulse), c * energy);
		alpha = max(alpha, c * max(energy, 0.55));
		// chão escurecido em volta (poeira), some para a borda
		alpha = max(alpha, (1.0 - smoothstep(0.5, 1.0, r)) * 0.25 * n);
	} else {
		float c = cracks(p, 11.0, 1.02 * grow, 0.011, seed);
		float scorch = (1.0 - smoothstep(0.08, 0.42, r + (n - 0.5) * 0.15)) * step(0.01, appear);
		vec3 hot = mix(vec3(1.4, 1.3, 1.1), mix(col_warm, col_hot, smoothstep(0.2, 0.9, r)), smoothstep(0.0, 0.25, r));
		col = col_dark * (0.8 + 0.4 * n);
		alpha = scorch * 0.75;
		col = mix(col, hot * 2.4, c * energy);
		alpha = max(alpha, c * max(energy, 0.5));
		// brilho no miolo logo depois do golpe
		float core = exp(-r * 7.0) * energy;
		col += col_hot * core * 2.0;
		alpha = max(alpha, core);
	}
	ALBEDO = col;
	ALPHA = clamp(alpha * fade, 0.0, 1.0);
}
