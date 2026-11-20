// Água do rio (scripts/map/map_river.gd): UV.x = metros ao longo do rio, UV.y = -1..1 de uma beira à outra.
// Estilo desenhado: cor chapada funda no meio e rasa nas beiras, riscos claros da correnteza descendo o rio,
// espuma ondulada nas beiras e brilho em faixa. Luz em dois tons como o resto do cenário.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://assets/shaders/toon_light.gdshaderinc"

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.09, 0.27, 0.36);
uniform vec3 shallow : source_color = vec3(0.2, 0.47, 0.5);
uniform vec3 foam : source_color = vec3(0.86, 0.93, 0.92);
uniform float flow = 1.2;
uniform float glow = 0.0;   // lava: a cor acende (EMISSION) e borra com o glow da tela

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float t = TIME * flow;
	float edge = abs(v);
	// funda/rasa em duas faixas (borda ondulando com o ruído)
	float wob = texture(noise_tex, vec2(u * 0.05 - t * 0.02, v * 0.3)).r - 0.5;
	float sh = smoothstep(0.62, 0.66, edge + wob * 0.22);
	vec3 col = mix(deep, shallow, sh);
	// manchas escuras de fundo, descendo devagar
	float dk = texture(noise_tex, vec2(u * 0.03 - t * 0.012, v * 0.25 + 0.4)).r;
	col *= mix(1.0, 0.85, smoothstep(0.58, 0.62, dk) * (1.0 - sh));
	// riscos da correnteza: ruído esticado ao longo do rio, cortado seco
	float s1 = texture(noise_tex, vec2(u * 0.09 - t * 0.09, v * 1.6)).r;
	float s2 = texture(noise_tex, vec2(u * 0.16 - t * 0.14 + 0.37, v * 2.4 + 0.7)).r;
	float streak = step(0.7, s1) * step(0.45, s2) * (1.0 - smoothstep(0.75, 0.9, edge));
	col = mix(col, mix(shallow, foam, 0.55), streak * 0.85);
	// espuma nas beiras (onde a água encosta na margem)
	float fn = texture(noise_tex, vec2(u * 0.22 - t * 0.05, v * 0.5 + 0.2)).r;
	float fo = smoothstep(0.86, 0.88, edge + (fn - 0.5) * 0.12);
	col = mix(col, foam, fo);
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
}
