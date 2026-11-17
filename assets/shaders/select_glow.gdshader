shader_type spatial;
// Borda do herói selecionado: casca invertida (como toon_outline) desenhada só onde select_mask não
// marcou o stencil, ou seja, em volta da silhueta. Transparente para vir depois da máscara (render_priority).
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(1.0, 0.76, 0.28, 1.0);
uniform float width = 0.02;      // metros, em espaço do modelo
uniform float strength = 1.0;    // 0 apaga (o herói sentando)

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb * 1.6;
	ALPHA = color.a * strength;
}
