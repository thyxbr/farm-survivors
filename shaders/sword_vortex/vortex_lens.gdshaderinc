// Vórtice Sombrio (SwordVortexFX): a lente do giro, o disco na altura da cintura (medido na referência: ~2,4 m de raio
// para um herói de 1,8 m). Duas camadas com a mesma conta:
//   vortex_lens_smoke.gdshader  mistura normal: o vidro escuro e a fumaça grossa na borda
//   vortex_lens_glow.gdshader   aditiva: a borda violeta acesa (forte na cabeça, com halo largo) e os riscos em espiral
// Malha: UV.x = ângulo atrás da cabeça em voltas (0 = junto da lâmina, 1 = uma volta atrás), UV.y = raio (0 centro, 1
// borda), COLOR.a = força do giro.
// "Pincelada": o mesmo ruído amostrado esticado ao longo da volta (x muito mais que y) vira riscos compridos de pincel.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;
instance uniform vec3 smoke_col = vec3(0.035, 0.008, 0.07);
instance uniform vec3 glow_col = vec3(0.62, 0.28, 1.0);

// riscos de pincel correndo ao longo da volta
float brush(vec2 uv, float time, float sx, float sy, float speed) {
	return texture(noise_tex, vec2(uv.x * sx - time * speed + seed, uv.y * sy + seed * 0.37)).r;
}

void lens(vec2 uv, float s, float time, out float glass, out float edge_smoke, out float rim, out float halo, out float streak) {
	float a = uv.x;               // voltas atrás da cabeça
	float r = clamp(uv.y, 0.0, 1.0);
	// a lente vai se apagando atrás da cabeça (uma volta e pouco), com a borda da apagada comida pelo pincel
	float b1 = brush(uv, time, 3.0, 0.6, 0.4);
	float tail = 1.0 - smoothstep(0.55, 1.05, a + (b1 - 0.5) * 0.35);
	// vidro escuro: ralo no meio, mais denso perto da borda
	glass = mix(0.35, 0.85, smoothstep(0.1, 0.8, r)) * tail * s;
	// fumaça grossa na borda, com tufos (pincel grosso) passando um pouco para fora
	float b2 = brush(uv, time, 5.0, 1.4, 0.9);
	float band = smoothstep(0.82, 0.9, r) * (1.0 - smoothstep(0.93 + 0.06 * b2, 1.0, r));
	edge_smoke = band * smoothstep(0.15, 0.6, b2 + 0.3) * tail * s;
	// borda acesa: fina e muito forte na cabeça, alargando e apagando atrás; halo largo em volta (o bloom da referência)
	float head = pow(1.0 - clamp(a, 0.0, 1.0), 1.6);
	float w = mix(0.018, 0.05, clamp(a, 0.0, 1.0));
	float b3 = brush(uv, time, 9.0, 0.4, 1.6);
	rim = exp(-pow((r - 0.8) / w, 2.0)) * head * (0.6 + 0.6 * b3) * s;
	// halo só para dentro da lente (por fora fica a fumaça preta)
	halo = exp(-pow((r - 0.8) / (w * 5.0), 2.0)) * (1.0 - smoothstep(0.8, 0.88, r)) * head * s;
	// riscos em espiral por dentro (o ar girando): pincel fino esticado, mais visível perto da cabeça
	float sp = brush(vec2(a + r * 0.35, r), time, 14.0, 6.0, 2.2);
	streak = smoothstep(0.62, 0.8, sp) * smoothstep(0.2, 0.8, r) * (1.0 - smoothstep(0.85, 0.95, r)) * head * s;
}
