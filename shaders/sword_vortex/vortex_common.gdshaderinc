// Vórtice Sombrio (SwordVortexFX): fitas do redemoinho e a meia-lua do golpe final. Duas camadas com a mesma conta:
//   vortex_smoke.gdshader  mistura normal: fumaça quase preta e arroxeada, de bordas esfiapadas (o "negro" de verdade)
//   vortex_glow.gdshader   aditiva: o fio violeta aceso na borda de fora (quase branco na cabeça) e um véu violeta
// Malha: UV.x = idade (0 = cabeça, junto da lâmina; 1 = cauda), UV.y = de dentro (0) para fora (1), COLOR.a = força.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;
instance uniform vec3 smoke_col = vec3(0.045, 0.01, 0.08);   // a meia-lua usa um roxo mais claro
instance uniform vec3 glow_col = vec3(0.62, 0.28, 1.0);
instance uniform float rim_pos = 0.88;                        // onde corre o fio aceso (0..1 em UV.y)
// 0 = fita de bordas esfiapadas (o redemoinho); 1 = nuvem (a meia-lua): bordas que somem devagar, rolos de fumaça
// grandes que sobem e se mexem, densidade variando por dentro, desfazendo em tufos macios
instance uniform float soft = 0.0;

void vortex(vec2 uv, float s, float time, out float smoke, out float rim, out float veil) {
	float age = clamp(uv.x, 0.0, 1.0);
	float y = clamp(uv.y, 0.0, 1.0);
	// nuvem: entorta a fita com um ruído grande e lento (os rolos de fumaça ondulam e sobem para fora)
	vec2 warp = vec2(texture(noise_tex, vec2(age * 0.9 + seed, y * 0.6 - time * 0.25)).r,
		texture(noise_tex, vec2(age * 0.7 - seed, y * 0.8 - time * 0.2 + 0.5)).r) - 0.5;
	vec2 q = vec2(age, y) + warp * 0.35 * soft;
	// ruído correndo ao longo da fita (fumaça arrastada pelo giro)
	float n = texture(noise_tex, vec2(q.x * 2.2 - time * 0.9 + seed, q.y * 0.9 + seed * 0.3)).r;
	float n2 = texture(noise_tex, vec2(q.x * 6.5 - time * 1.7 - seed, q.y * 2.3 + time * 0.3)).r;
	// perfil atravessando a fita: cheio no meio, bordas comidas pelo ruído (fiapos); na nuvem, bem mais macio
	float edge = min(q.y, 1.0 - q.y) * 2.0;
	float prof = smoothstep(0.0, mix(0.55, 1.1, soft), edge + (n - 0.5) * mix(0.7, 0.9, soft));
	// nuvem: densidade por dentro (rolos mais grossos e mais ralos), em ruído grande
	float cloud = texture(noise_tex, vec2(q.x * 1.3 - time * 0.15 + seed * 0.7, q.y * 1.1 - time * 0.35)).r;
	prof *= mix(1.0, smoothstep(0.2, 0.75, cloud) * 0.85 + 0.25, soft);
	// erosão com a idade: a cauda se desfaz em pedaços (na nuvem, em tufos de borda macia)
	float e = n * 0.7 + n2 * 0.5;
	float cut = age * 1.1 - 0.1;
	float erode = smoothstep(cut - mix(0.05, 0.2, soft), cut + mix(0.12, 0.3, soft), e);
	smoke = prof * erode * s;
	// fio aceso: estreito, colado na borda de fora, mais forte e mais fino na cabeça, quebrando na cauda
	float w = mix(0.03, 0.08, age);
	float live = pow(1.0 - age, 1.2) * smoothstep(cut - 0.2, cut + 0.1, e + 0.2) * s;
	// fio fino e um halo largo e fraco em volta (o bloom da referência, que o glow suave do jogo não faz)
	rim = (exp(-pow((y - rim_pos) / w, 2.0)) + 0.25 * exp(-pow((y - rim_pos) / (w * 5.0), 2.0))) * live;
	veil = prof * erode * (1.0 - age) * s;
}
