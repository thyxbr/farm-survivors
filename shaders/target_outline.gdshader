shader_type spatial;
// Borda do alvo da Cura: casca invertida (como o contorno toon), mais grossa, clara e pulsando.
// A malha precisa de normais suavizadas (ToonLook._hull_of).
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.25, 1.0, 0.35, 1.0);
uniform vec4 color2 : source_color = vec4(0.75, 1.0, 0.45, 1.0);
uniform float width = 0.024;           // metros, em espaço do modelo
uniform float distance_gain = 0.035;   // engrossa com a distância para continuar legível de longe

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pulse = 1.0 + 0.25 * sin(TIME * 6.0);
	VERTEX += NORMAL * width * pulse * (1.0 + d * distance_gain);
}

void fragment() {
	float k = 0.5 + 0.5 * sin(TIME * 4.0);
	ALBEDO = mix(color.rgb, color2.rgb, k) * 1.6;
}
