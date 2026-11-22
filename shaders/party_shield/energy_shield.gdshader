shader_type spatial;
// Grito do Bastião: um escudo pequeno de energia azul (do tamanho da mão do herói) num quad, desenhado por função de
// distância: borda acesa, miolo translúcido, emblema no meio e um halo suave em volta. Aditivo, dos dois lados (os
// escudos giram em volta do personagem e mostram as costas). PartyShieldBuff.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.62, 1.0);
uniform vec3 hot : source_color = vec3(0.8, 0.95, 1.0);
uniform float gain = 1.0;
instance uniform float intensity = 1.0;
// fase própria de cada escudo (o pulso não fica igual em todos)
instance uniform float phase = 0.0;
// 0..1: o escudo se desfazendo (o miolo some primeiro, a borda vira pontinhos)
instance uniform float dissolve = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// > 0 dentro do escudo (distância aproximada até a borda, em unidades do quad de -1..1)
float shield_inside(vec2 p) {
	float top = 0.78 - 0.1 * p.x * p.x;
	float k = clamp((p.y + 0.92) / 1.05, 0.0, 1.0);
	float w = 0.74 * pow(k, 0.62);
	return min(w - abs(p.x), top - p.y);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float e = shield_inside(p * 1.12);
	float body = smoothstep(0.0, 0.03, e);
	float rim = body * (1.0 - smoothstep(0.03, 0.13, e));
	float inner = shield_inside(p * 1.12 / 0.62);
	float emblem = smoothstep(0.0, 0.025, inner) * (1.0 - smoothstep(0.025, 0.07, inner));
	float bar = (1.0 - smoothstep(0.03, 0.06, abs(p.x))) * step(-0.45, p.y) * step(p.y, 0.45) * body;
	float halo = exp(-max(-e, 0.0) * 9.0) * (1.0 - body) * 0.55;
	float pulse = 0.82 + 0.18 * sin(TIME * 4.2 + phase * 6.283);
	// brilho que desliza de cima para baixo
	float sweep = smoothstep(0.18, 0.0, abs(p.y - (fract(TIME * 0.6 + phase) * 2.4 - 1.2))) * body * 0.6;
	float grain = hash(floor(UV * 26.0) + floor(phase * 97.0));
	float keep = step(dissolve * 1.05, grain);
	float fill = body * 0.28 * (1.0 - dissolve);
	vec3 c = color * (fill + halo * (1.0 - dissolve)) + mix(color, hot, 0.55) * (rim + emblem * 0.8 + bar * 0.45) * keep + hot * sweep * (1.0 - dissolve);
	ALBEDO = c * gain * intensity * pulse;
	ALPHA = 1.0;
}
