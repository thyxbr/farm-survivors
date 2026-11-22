shader_type spatial;
// Lâmina Suprema: o rastro de uma alma (fita de DarkSouls, de frente para a câmera). UV.x = idade (0 = junto da alma,
// 1 = o mais velho), UV.y = de um lado ao outro; COLOR.a = o brilho da alma. Violeta aditivo esfriando para carmesim,
// rasgado pelo ruído.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float n = texture(noise_tex, vec2(age * 2.0 - TIME * 1.3, UV.y * 1.2 + COLOR.r * 7.0)).r;
	float a = pow(1.0 - age, 1.5) * smoothstep(0.0, 0.7, across) * smoothstep(age * 0.7, age * 0.7 + 0.35, n);
	ALBEDO = mix(rim_col * 0.9, vein_col * 0.7, smoothstep(0.15, 0.8, age)) * a * COLOR.a;
	ALPHA = 1.0;
}
