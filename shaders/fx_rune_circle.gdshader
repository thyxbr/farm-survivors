shader_type spatial;
// Círculo de runas de fogo no chão (Chuva de Meteoros): anéis com marcas girando para um lado, dois
// quadrados cruzados (estrela de oito pontas), raios e losangos girando para o outro, e brasa no miolo.
// Mesmos parâmetros do desenho de gelo (fx_frost_sigil): aparece do centro para fora e some em manchas.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_line : source_color = vec4(1.0, 0.8, 0.35, 1.0);
instance uniform vec4 col_fill : source_color = vec4(0.75, 0.12, 0.03, 1.0);
instance uniform float reveal = 1.0;   // raio já desenhado (0..1,1)
instance uniform float erode = 0.0;    // 0 = inteiro, 1 = sumiu
instance uniform float seed = 0.0;
instance uniform float spin = 0.0;     // ângulo do giro (rad)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Dobra o ângulo `th` em `n` fatias iguais e devolve o ponto na fatia (eixo da fatia em +x).
vec2 fold(float th, float r, float n) {
	float sector = TAU / n;
	float a = mod(th + sector * 0.5, sector) - sector * 0.5;
	return vec2(cos(a), sin(a)) * r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float th = atan(p.y, p.x);
	float out_th = th + spin;              // parte de fora
	float in_th = th - spin * 0.6;         // parte de dentro, ao contrário
	// anéis de fora e as 24 marcas entre eles
	float d = abs(r - 0.95) - 0.014;
	d = min(d, abs(r - 0.86) - 0.006);
	d = min(d, seg(fold(out_th, r, 24.0), vec2(0.875, 0.0), vec2(0.935, 0.0)) - 0.006);
	// dois quadrados cruzados
	d = min(d, abs(fold(in_th, r, 4.0).x - 0.58) - 0.008);
	d = min(d, abs(fold(in_th + PI * 0.25, r, 4.0).x - 0.58) - 0.008);
	// losangos nas oito pontas e raios curtos por dentro
	vec2 q = fold(in_th, r, 8.0);
	vec2 t = abs(q - vec2(0.76, 0.0));
	d = min(d, t.x + t.y * 1.6 - 0.04);
	d = min(d, seg(fold(in_th + PI * 0.125, r, 8.0), vec2(0.4, 0.0), vec2(0.52, 0.0)) - 0.008);
	// anéis de dentro
	d = min(d, abs(r - 0.34) - 0.009);
	d = min(d, abs(r - 0.12) - 0.007);
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float line = 1.0 - smoothstep(-fw, fw, d);
	// brasa: manchas chapadas dentro do anel
	float n = noise(p * 5.0 + seed) * 0.6 + noise(p * 13.0 - seed) * 0.4;
	float fill = step(r, 0.95) * (0.12 + 0.16 * step(0.55, n));
	float vis = step(r, reveal) * step(erode * 1.06, 0.25 + n * 0.8);
	ALBEDO = mix(col_fill.rgb, col_line.rgb, line);
	ALPHA = max(line * col_line.a, fill) * vis;
}
