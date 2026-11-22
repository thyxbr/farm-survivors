shader_type spatial;
// Grito do Bastião: aura azul suave em volta do herói enquanto a animação roda (uma cápsula um pouco maior que o
// corpo). Um véu de luz que acende perto da borda e apaga de novo antes do contorno (sem a linha dura de "redoma"),
// com faixas de energia subindo devagar e as pontas de cima e de baixo apagadas. Aditivo; `intensity` (por instância)
// sobe e desce com Tween para a aura acender e apagar sem tranco. PartyShieldCast.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.68, 1.0);
uniform vec3 hot : source_color = vec3(0.75, 0.92, 1.0);
uniform float gain = 0.55;
uniform float height = 2.2;
instance uniform float intensity = 0.0;

varying float ly;

void vertex() {
	ly = VERTEX.y / height + 0.5;
}

void fragment() {
	float edge = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	// sobe para a borda e cai antes dela: uma faixa larga e macia, nunca o contorno fino
	float veil = smoothstep(0.15, 0.75, edge) * (1.0 - smoothstep(0.78, 0.99, edge));
	float bands = 0.55 + 0.45 * sin(ly * 14.0 - TIME * 2.6 + sin(UV.x * 6.2832 * 3.0 + TIME * 0.7) * 0.9);
	float ends = smoothstep(0.02, 0.25, ly) * (1.0 - smoothstep(0.5, 0.9, ly));
	vec3 c = mix(color, hot, veil * 0.35);
	ALBEDO = c * veil * (0.45 + 0.55 * bands) * ends * gain * intensity;
	ALPHA = 1.0;
}
