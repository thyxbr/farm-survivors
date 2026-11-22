shader_type spatial;
// Redemoinho de energia sombria no chão (Ciclone de Aço; o anel da Dança do Abismo): um PlaneMesh deitado, UV 0..1. Braços
// de fumaça escura girando em espiral (coordenadas polares + ruído), a borda acesa em violeta e veias carmesim. Mistura
// normal: escurece o chão de verdade; as cores claras da borda também aparecem (o glow pega no que passa de 1).
//   intensity  0..1 o quanto aparece      spin  ângulo atual do giro (rad, o redemoinho acompanha o herói)
//   inner      raio do buraco do meio (fração)   ring  0 = disco cheio, 1 = só um anel fino na borda
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 smoke_col = vec3(0.03, 0.006, 0.055);
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);
uniform float arms = 3.0;
uniform float twist = 2.4;
instance uniform float intensity = 1.0;
instance uniform float spin = 0.0;
instance uniform float inner = 0.12;
instance uniform float ring = 0.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	float a = atan(c.y, c.x);
	float sw = a * arms - spin * arms + r * twist * arms;
	float n = texture(noise_tex, vec2(sw / 6.2831 * 0.5 + seed, r * 1.6 - TIME * 0.4)).r;
	float n2 = texture(noise_tex, vec2(a / 6.2831 * 3.0 - spin * 0.2 + seed, r * 4.0 - TIME * 0.9)).r;
	float arm = 0.5 + 0.5 * sin(sw + n * 3.0);
	float edge = smoothstep(1.0, 0.82, r) * smoothstep(inner, inner + 0.25, r);
	float band = mix(1.0, smoothstep(0.55, 0.85, r), ring);
	float dens = edge * band * mix(0.35, 1.0, arm) * (0.6 + 0.6 * n);
	float rim = exp(-pow((r - 0.9) / 0.05, 2.0)) * (0.3 + 0.7 * arm);
	float vein = (1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5))) * edge * band;
	vec3 col = mix(smoke_col, rim_col * 1.3, clamp(rim * 0.8, 0.0, 1.0));
	col = mix(col, vein_col * 1.3, clamp(vein * 0.7, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(max(dens * 0.9, max(rim * 0.7, vein * 0.6)) * intensity, 0.0, 1.0);
}
