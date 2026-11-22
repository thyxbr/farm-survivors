// Energia sombria da montante (Ciclone de Aço, Dança do Abismo, Lâmina Suprema): a mesma paleta das garras do Corte do
// Abismo (abyss_talon.gdshader): miolo de fumaça quase preta e violeta, borda acesa em violeta, veias carmesim e o mais
// quente quase branco. Cada efeito desenha em DUAS camadas com a mesma conta (dark_energy()):
//   *_smoke.gdshader  mistura normal (blend_mix): a fumaça escura que cobre o que está atrás (o "dark" de verdade)
//   *_glow.gdshader   mistura aditiva (blend_add): as bordas, as veias e o fio aceso por cima (o glow pega no > 1)
// O material da fumaça leva o do brilho em next_pass: mesma malha, as mesmas instance uniforms.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 smoke_col = vec3(0.03, 0.006, 0.055);
uniform vec3 smoke_rim = vec3(0.16, 0.04, 0.26);
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);
uniform vec3 hot_col = vec3(1.0, 0.82, 1.0);
uniform float smoke_alpha = 0.95;
uniform float glow_gain = 1.0;
uniform float flow = 0.7;   // velocidade com que o ruído corre ao longo do rastro

instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

// Rastro de lâmina (malha de DarkBladeTrail): UV.x = idade (0 = junto da lâmina agora, 1 = o mais velho), UV.y = do
// cabo (0) à ponta (1); `fade` = COLOR.a (força do golpe naquele ponto). Devolve (fumaça 0..1) e o brilho (rgb).
void dark_trail(vec2 uv, float fade, float time, out float smoke, out vec3 glow) {
	float age = clamp(uv.x, 0.0, 1.0);
	float along = clamp(uv.y, 0.0, 1.0);
	vec2 nuv = vec2(age * 1.6 - time * flow + seed, along * 1.3 + seed * 0.37);
	float n = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, vec2(age * 3.7 - time * flow * 1.9 - seed, along * 3.1 + time * 0.25)).r;
	// corpo: cheio junto da lâmina, rasgando em fiapos pelo ruído conforme envelhece; borda macia no cabo e na ponta
	float side = smoothstep(0.0, 0.22, along) * (1.0 - smoothstep(0.86, 1.0, along));
	float life = pow(1.0 - age, 0.8);
	float tear = smoothstep(age * 0.95 - 0.25, age * 0.95 + 0.15, n * 0.75 + n2 * 0.4);
	float body = side * life * tear * fade;
	smoke = clamp(body * smoke_alpha, 0.0, 1.0);
	// brilho: o fio que a lâmina acabou de cortar (idade baixa) e a borda de fora (ponta), veias carmesim no corpo
	float lead = exp(-age * 9.0) * smoothstep(0.1, 0.5, along);
	float outer = smoothstep(0.55, 0.97, along) * (1.0 - smoothstep(0.97, 1.0, along)) * pow(1.0 - age, 1.6);
	float vein = (1.0 - smoothstep(0.0, 0.07, abs(n2 - 0.5))) * body;
	float wisp_edge = (1.0 - smoothstep(0.0, 0.12, abs(tear - 0.5))) * side * life * fade;
	glow = rim_col * (lead * 0.9 + outer * 1.0 + wisp_edge * 0.3) * fade
		+ vein_col * vein * 1.1
		+ hot_col * pow(lead, 6.0) * smoothstep(0.7, 1.0, along) * 0.6 * fade;
	glow *= glow_gain;
}
