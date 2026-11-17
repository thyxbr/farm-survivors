shader_type spatial;
// Desenho de gelo no chão (Nova Gélida): floco de seis braços com ramos, anéis e geada no miolo, num
// quadrado deitado. Aparece do centro para fora (`reveal`) e some em manchas (`erode`). Traço de borda dura.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_line : source_color = vec4(0.9, 0.98, 1.0, 1.0);
instance uniform vec4 col_fill : source_color = vec4(0.45, 0.75, 1.0, 1.0);
instance uniform float reveal = 1.0;   // raio já desenhado (0..1,1)
instance uniform float erode = 0.0;    // 0 = inteiro, 1 = sumiu
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

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float th = atan(p.y, p.x);
	float sector = PI / 3.0;
	// dobra o plano em seis fatias espelhadas: desenha-se um braço só
	float a = mod(th + sector * 0.5, sector) - sector * 0.5;
	vec2 q = vec2(cos(a), abs(sin(a))) * r;
	vec2 bd = vec2(cos(0.96), sin(0.96));               // direção dos ramos
	float d = seg(q, vec2(0.12, 0.0), vec2(0.8, 0.0)) - 0.012;
	d = min(d, seg(q, vec2(0.34, 0.0), vec2(0.34, 0.0) + bd * 0.16) - 0.009);
	d = min(d, seg(q, vec2(0.52, 0.0), vec2(0.52, 0.0) + bd * 0.2) - 0.009);
	d = min(d, seg(q, vec2(0.68, 0.0), vec2(0.68, 0.0) + bd * 0.13) - 0.009);
	vec2 t = abs(q - vec2(0.84, 0.0));
	d = min(d, t.x + t.y * 1.8 - 0.045);                // losango na ponta
	// braços menores entre os grandes
	float a2 = mod(th, sector) - sector * 0.5;
	vec2 q2 = vec2(cos(a2), abs(sin(a2))) * r;
	d = min(d, seg(q2, vec2(0.58, 0.0), vec2(0.86, 0.0)) - 0.006);
	d = min(d, seg(q2, vec2(0.72, 0.0), vec2(0.72, 0.0) + bd * 0.08) - 0.005);
	// anéis
	d = min(d, abs(r - 0.95) - 0.014);
	d = min(d, abs(r - 0.885) - 0.005);
	d = min(d, abs(r - 0.22) - 0.008);
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float line = 1.0 - smoothstep(-fw, fw, d);
	// geada: manchas chapadas dentro do anel
	float n = noise(p * 5.0 + seed) * 0.6 + noise(p * 13.0 - seed) * 0.4;
	float fill = step(r, 0.95) * (0.14 + 0.16 * step(0.55, n));
	float vis = step(r, reveal) * step(erode * 1.06, 0.25 + n * 0.8);
	ALBEDO = mix(col_fill.rgb, col_line.rgb, line);
	ALPHA = max(line * col_line.a, fill) * vis;
}
