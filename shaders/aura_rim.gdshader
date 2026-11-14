shader_type spatial;
// Contorno de luz no corpo do personagem com buff (material_overlay nas peças do modelo).
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.4, 0.1, 1.0);   // segunda aura (igual à 1ª se só há uma)
uniform float strength = 0.6;
uniform float pulse_speed = 2.4;
uniform float rise = 0.0;       // > 0: o brilho é mais forte embaixo e sobe em ondas (fogo)

varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	float wave = 1.0;
	if (rise > 0.0) {
		wave = 0.55 + 0.45 * sin(wy * 5.0 - TIME * rise * 4.0);
	}
	vec3 c = mix(color.rgb, color2.rgb, 0.5 + 0.5 * sin(TIME * 1.6 + wy * 2.0));
	ALBEDO = c * fres * strength * pulse * wave;
}
