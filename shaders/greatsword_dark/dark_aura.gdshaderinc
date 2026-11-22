// Lâmina Suprema: a casca de chamas sombrias em volta da energia da espada (malha GreatswordSupremeSlash.aura_mesh: UV.y
// = 0 na guarda e 1 na ponta, UV.x = a volta em torno da lâmina; normais suaves). Os vértices incham para fora com o
// ruído (as línguas de fogo tremem) e as chamas correm para a ponta. Desenhada em duas camadas como o rastro
// (dark_energy.gdshaderinc): *_smoke (mistura normal, a fumaça escura) e *_glow (aditiva, a borda e as veias).
//   heat  0..1 quanto da lâmina já está coberto     intensity  brilho geral (0 = apagada)

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 smoke_col = vec3(0.03, 0.006, 0.055);
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);
uniform vec3 hot_col = vec3(1.0, 0.82, 1.0);
uniform float puff = 0.09;
instance uniform float heat = 0.0;
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

void aura_vertex(inout vec3 v, vec3 nrm, vec2 uv, float time) {
	float f = textureLod(noise_tex, vec2(uv.x * 2.0 + seed, uv.y * 2.5 - time * 1.4), 0.0).r;
	float f2 = textureLod(noise_tex, vec2(uv.x * 5.0 - seed, uv.y * 6.0 - time * 2.6), 0.0).r;
	float v_flame = f * 0.65 + f2 * 0.35;
	// incha mais no meio da lâmina e menos na ponta (a ponta continua afiada)
	float body = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.82, 1.0, uv.y) * 0.7);
	v += nrm * puff * body * (0.4 + 1.6 * v_flame);
	// as línguas de fogo puxam para a ponta
	v.y += puff * 0.8 * body * v_flame;
}

void aura_shade(vec2 uv, vec3 nrm, vec3 view, float time, out float smoke, out vec3 glow) {
	float front = heat * 1.06 - 0.03;
	float grown = 1.0 - smoothstep(front - 0.08, front, uv.y);
	float fres = pow(1.0 - clamp(abs(dot(nrm, view)), 0.0, 1.0), 1.4);
	float n = texture(noise_tex, vec2(uv.x * 2.0 + seed, uv.y * 3.0 - time * 1.5)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 4.5 - seed, uv.y * 7.0 - time * 2.9)).r;
	float flame = smoothstep(0.3, 0.7, n * 0.65 + n2 * 0.45 + fres * 0.3);
	float tips = smoothstep(0.55, 0.95, n2) * fres;
	smoke = clamp(flame * (0.45 + 0.75 * fres) * grown * intensity, 0.0, 0.92);
	float vein = (1.0 - smoothstep(0.0, 0.05, abs(n - 0.5))) * flame;
	glow = rim_col * (fres * fres * flame * 1.5 + tips * 0.9) + vein_col * vein * 0.9
		+ hot_col * (1.0 - smoothstep(0.0, 0.05, abs(uv.y - front))) * step(heat, 0.999) * 0.8;
	glow *= grown * intensity;
}
