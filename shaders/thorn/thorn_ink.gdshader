shader_type spatial;
// O traço em volta dos tubos da Espinheira (ThornFX._tube): a mesma malha um pouco mais gorda, só as faces de trás,
// na cor da sombra. Os tubos têm normais chapadas (para o tom por face), então a direção lisa de cada vértice vem
// guardada na cor do vértice (0..1 -> -1..1): engordar por ela não abre frestas entre as faces.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform float width = 0.035;

// o mesmo índice do passe principal: os dois passes dividem os parâmetros da instância
instance uniform vec3 shade : instance_index(2) = vec3(0.17, 0.08, 0.08);

void vertex() {
	float sx = max(length(MODEL_MATRIX[0].xyz), 0.001);
	VERTEX += (COLOR.rgb * 2.0 - 1.0) * width / sx;
}

void fragment() {
	ALBEDO = shade * 0.55;
}
