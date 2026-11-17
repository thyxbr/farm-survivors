shader_type spatial;
// Coluna de luz sagrada (cilindro aberto): some no alto, borda mais forte que o miolo e faixas subindo.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform float intensity = 2.2;
uniform float fade = 1.0;        // 0..1, animado por tween
uniform float scroll = 1.0;      // velocidade das faixas subindo

void fragment() {
	float v = UV.y;                                        // 0 no topo, 1 na base
	float vert = smoothstep(0.0, 0.75, v) * (1.0 - smoothstep(0.96, 1.0, v));
	float fres = 1.0 - abs(dot(NORMAL, VIEW));
	float edge = mix(0.3, 1.0, pow(fres, 1.4));
	float bands = 0.65 + 0.35 * sin(v * 26.0 + TIME * scroll * 7.0) * sin(UV.x * 6.2832 * 3.0 + TIME * 1.7);
	// teto abaixo de 1: acima disso o bloom do cenário estoura colunas finas num borrão branco
	ALBEDO = min(color.rgb * intensity * vert * edge * bands * fade, vec3(0.85));
}
