shader_type spatial;
// Grito do Bastião: no chão, em volta dos pés do herói. `glow` = o brilho suave do disco enquanto ele grita; `wave` =
// raio (0..1 do plano) da onda do grito que corre para fora, com `wave_alpha` apagando ela no caminho. Aditivo.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.68, 1.0);
uniform vec3 hot : source_color = vec3(0.8, 0.95, 1.0);
uniform float gain = 1.0;
instance uniform float glow = 0.0;
instance uniform float wave = 0.0;
instance uniform float wave_alpha = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float disc = exp(-r * r * 5.0) * (1.0 - smoothstep(0.85, 1.0, r));
	// anel fino de runas tracejadas, girando devagar
	float ticks = step(0.5, fract(a * 4.0 / 3.14159 + TIME * 0.25));
	float runes = (1.0 - smoothstep(0.015, 0.035, abs(r - 0.62))) * mix(0.45, 1.0, ticks);
	float ring = (1.0 - smoothstep(0.0, 0.05, abs(r - wave))) * smoothstep(0.0, 0.08, wave);
	float trail = (1.0 - smoothstep(0.0, 0.35, wave - r)) * step(r, wave) * 0.25;
	vec3 c = color * (disc * 0.9 + runes * 0.7) * glow + mix(color, hot, 0.5) * (ring + trail) * wave_alpha;
	ALBEDO = c * gain * (1.0 - smoothstep(0.92, 1.0, r));
	ALPHA = 1.0;
}
