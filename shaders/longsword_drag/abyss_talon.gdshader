shader_type spatial;
// Corte do Abismo: uma unha da garra espectral (malha curva gerada por DragAndSlash.talon_mesh: UV.y = 0 na base e 1
// na ponta, UV.x = volta em torno dela). Cristal escuro violeta com a borda acesa (fresnel), veias carmesim subindo, a
// ponta quase branca e a base em brasa onde sai do chão. No fim ela se desfaz de baixo para cima por ruído, com a borda
// do corte acesa.
//   glow      brilho geral (o nascer e o crepitar)      dissolve  0 = inteira, 1 = desfeita
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 core = vec3(0.05, 0.01, 0.09);
uniform vec3 rim = vec3(0.62, 0.32, 1.0);
uniform vec3 vein = vec3(1.0, 0.1, 0.32);
uniform vec3 tip_hot = vec3(1.0, 0.82, 1.0);
uniform float hdr = 2.6;
instance uniform float glow = 1.0;
instance uniform float dissolve = 0.0;
instance uniform float seed = 0.0;

void fragment() {
	float h = UV.y;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec2 nuv = vec2(UV.x * 2.0 + seed, h * 3.0 - TIME * 1.4);
	float n = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, vec2(UV.x * 5.0 - seed, h * 7.0 - TIME * 3.1)).r;
	// veias: faixas finas onde o ruído cruza o meio
	float v = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
	v *= 0.6 + 0.8 * n2;
	// dissolve: some de baixo para cima (o ruído quebra a linha), a borda do corte acesa
	float cut = dissolve * 1.25 - 0.12;
	float d = n * 0.35 + (1.0 - h) * 0.65;
	if (d < cut) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, 0.08, d - cut);
	edge *= step(0.001, dissolve);
	vec3 c = core;
	c += rim * fres * 1.6;
	c += vein * v * (0.7 + 0.6 * fres);
	c += tip_hot * smoothstep(0.78, 1.0, h) * 1.4;
	c += vein * (1.0 - smoothstep(0.0, 0.18, h)) * 1.2;   // a base em brasa, saindo do chão
	c += vec3(1.0, 0.55, 1.0) * edge * 2.5;
	ALBEDO = c * glow * (1.0 + (hdr - 1.0) * max(fres * 0.6, smoothstep(0.85, 1.0, h)));
}
