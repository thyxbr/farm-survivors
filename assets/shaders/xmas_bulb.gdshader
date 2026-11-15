shader_type spatial;
// Lâmpadas do pisca-pisca de Natal (scripts/world/christmas_decor.gd). Cada lâmpada é uma instância de
// MultiMesh: a cor vem da instância (COLOR) e INSTANCE_CUSTOM traz a fase (r) e o padrão do fio (g):
// corrida (as luzes andam pelo fio), cintilar e respirar. De dia brilham pouco; à noite (`night`, posto
// pelo DayNightFX) passam do limiar do glow e acendem a cena.
render_mode cull_back, shadows_disabled;

uniform float night = 0.0;
uniform float day_glow = 0.6;
uniform float night_glow = 4.5;

varying float v_phase;
varying float v_pattern;

void vertex() {
	v_phase = INSTANCE_CUSTOM.r;
	v_pattern = INSTANCE_CUSTOM.g;
}

void fragment() {
	float t = TIME;
	// corrida: um grupo de cada três acende por vez, andando pelo fio
	float chase = step(0.5, fract(t * 0.9 - v_phase * 0.34));
	// cintilar: cada lâmpada no seu ritmo
	float twinkle = smoothstep(0.1, 0.9, 0.5 + 0.5 * sin(t * (2.0 + fract(v_phase * 7.3) * 2.5) + v_phase * 61.0));
	// respirar: o fio inteiro sobe e desce junto, com as cores alternadas em contratempo
	float breathe = 0.5 + 0.5 * sin(t * 1.6 + mod(v_phase, 2.0) * 3.1416);
	float on = v_pattern < 0.5 ? chase : (v_pattern < 1.5 ? twinkle : breathe);
	float glow = mix(day_glow, night_glow, night) * mix(0.22, 1.0, on);
	ALBEDO = COLOR.rgb * 0.55;
	ROUGHNESS = 0.3;
	EMISSION = COLOR.rgb * glow;
}
