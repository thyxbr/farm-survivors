shader_type spatial;
// Aviso de golpe em cone no chão (Sopro Congelante da Sentinela da Nevasca): o setor do cone com borda dura, o
// miolo enchendo do bico para fora até o golpe sair (`reveal` 0..1) e, à frente dele, o arco que o cone ainda vai
// varrer, com setas correndo no sentido do giro. O plano (2x2) fica deitado, com o bico no centro e o eixo do
// cone em +Z; quem desenha gira o nó junto com o cone.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform vec4 col_line : source_color = vec4(1.0, 0.3, 0.14, 1.0);
instance uniform vec4 col_fill : source_color = vec4(0.92, 0.1, 0.05, 1.0);
instance uniform float half_angle = 0.35;   // meia abertura do cone (rad)
instance uniform float ahead = 0.0;         // arco que ainda falta varrer (rad, com sinal: + = yaw crescendo)
instance uniform float reveal = 0.0;        // quanto do raio o miolo já encheu
instance uniform float fade = 0.0;          // 0 = inteiro, 1 = sumiu
instance uniform float run = 0.0;           // relógio das setas

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0 || r < 0.03) {
		discard;
	}
	float a = atan(p.x, p.y);            // 0 no eixo (+Z), crescendo para +X
	float sgn = ahead >= 0.0 ? 1.0 : -1.0;
	float lead = a * sgn - half_angle;   // > 0: à frente do cone, no sentido do giro
	float inside = step(abs(a), half_angle);
	float path = step(0.0, lead) * step(lead, abs(ahead)) * (1.0 - inside);
	if (inside + path < 0.5) {
		discard;
	}
	// bordas: os dois lados do cone, o arco de fora e a frente do miolo
	float side = abs(abs(a) - half_angle) * r;
	float d = min(side - 0.012, abs(r - 0.97) - 0.014);
	float front = clamp(reveal, 0.0, 1.0) * 0.97;
	d = min(d, abs(r - front) - 0.01);
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float line = (1.0 - smoothstep(-fw, fw, d)) * inside;
	float stripes = step(0.5, fract(r * 9.0 - run * 1.5));
	float fill = inside * (step(r, front) * (0.24 + 0.14 * stripes) + 0.08);
	// caminho: faixa fraca com setas (divisas) correndo no sentido do giro e a borda de fora
	float chev = step(0.55, fract(lead * 5.0 - abs(r - 0.6) * 2.2 - run));
	float rim = 1.0 - smoothstep(0.0, 0.012, abs(r - 0.97) - 0.008);
	float pfill = path * (0.05 + 0.13 * chev * step(0.25, r) + 0.45 * rim);
	ALBEDO = mix(col_fill.rgb, col_line.rgb, max(line, path * max(chev * 0.6, rim)));
	ALPHA = max(max(line * col_line.a, fill), pfill) * (1.0 - fade);
}
