shader_type spatial;
// Contorno do slime: a mesma casca invertida de toon_outline.gdshader, mas no passe transparente e
// desenhada depois do corpo (render_priority do material). Como o corpo translúcido grava profundidade,
// a casca só passa no teste fora da silhueta e não aparece por dentro da gelatina.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.10, 0.08, 0.13, 1.0);
uniform float width = 0.0055;
uniform float distance_gain = 0.05;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * (1.0 + d * distance_gain);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;      // escrever ALPHA é o que leva o material para o passe transparente
}
