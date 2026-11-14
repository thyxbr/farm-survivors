shader_type spatial;
// Contorno por casca invertida: desenha só as faces de trás de uma cópia da malha, empurrada para fora
// pela normal. A malha da casca precisa de normais suavizadas (ToonLook as calcula), senão o low-poly
// de faces chapadas abre frestas nas arestas.
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(0.10, 0.08, 0.13, 1.0);
uniform float width = 0.0055;                 // metros, em espaço do modelo
uniform float distance_gain = 0.05;         // engrossa um pouco com a distância para não sumir de longe

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * (1.0 + d * distance_gain);
}

void fragment() {
	ALBEDO = color.rgb;
}
