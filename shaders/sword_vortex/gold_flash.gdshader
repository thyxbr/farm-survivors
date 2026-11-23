shader_type spatial;
// Vórtice Sombrio: o clarão dourado de quem leva um corte do giro (material_overlay do inimigo, Enemy.flash_with).
// O corpo inteiro acende em dourado quase branco, mais forte na silhueta (fresnel), com um tremeluzir que sobe como
// chama.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 gold = vec3(1.0, 0.78, 0.35);
uniform float gain = 1.6;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float flick = vn(vec2(wp.x * 6.0 + wp.z * 6.0, wp.y * 5.0 - TIME * 9.0));
	float k = 0.35 + fres * 1.4 + flick * 0.45;
	ALBEDO = mix(gold, vec3(1.0), fres * 0.6) * k * gain;
}
