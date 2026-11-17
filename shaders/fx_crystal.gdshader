shader_type spatial;
// Cristal de gelo "desenhado": malha facetada de verdade (FXToon.crystal_mesh), sem luz da cena. Cada
// face recebe um de três tons chapados conforme para onde aponta (luz fixa de cima e da esquerda), e o
// topo clareia um pouco: lê como gelo lapidado, não como espinho nem como bolha.
render_mode unshaded, cull_disabled, shadows_disabled;

instance uniform vec4 col_core : source_color = vec4(0.96, 1.0, 1.0, 1.0);
instance uniform vec4 col_mid : source_color = vec4(0.55, 0.85, 1.0, 1.0);
instance uniform vec4 col_edge : source_color = vec4(0.14, 0.36, 0.78, 1.0);

varying vec3 world_normal;
varying float height;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	height = VERTEX.y;
}

void fragment() {
	float light = dot(normalize(world_normal), normalize(vec3(-0.5, 0.55, 0.65))) + (height - 0.5) * 0.35;
	vec3 c = col_edge.rgb;
	c = mix(c, col_mid.rgb, step(-0.05, light));
	c = mix(c, col_core.rgb, step(0.66, light));
	ALBEDO = c;
}
