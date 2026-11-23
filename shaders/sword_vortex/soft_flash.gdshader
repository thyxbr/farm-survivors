shader_type spatial;
// Vórtice Sombrio: o clarão do golpe final. Quad virado para a câmera, aditivo, brilho que cai suave do centro
// (branco no meio, a cor nas bordas), sem contorno: um clarão de luz, não uma bola desenhada.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, blend_add, fog_disabled;

instance uniform vec3 col = vec3(0.6, 0.3, 1.0);
instance uniform float intensity = 1.0;
// > 1 achata o brilho num risco horizontal (o raio de luz deitado)
instance uniform float stretch = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0),
		vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y *= stretch;
	float r = length(p);
	float core = exp(-r * r * 14.0);
	float halo = exp(-r * r * 3.2) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = (vec3(1.0) * core * 2.5 + col * halo * 1.6) * intensity;
	ALPHA = 1.0;
}
