shader_type spatial;
// Domo de luz da explosão radiante: casca de fresnel aditiva com ondas que correm do chão para cima.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float intensity = 1.0;
uniform float fade = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float ripple = 0.75 + 0.25 * sin(UV.y * 40.0 - TIME * 10.0);
	float low = smoothstep(0.0, 0.5, UV.y);                // mais forte rente ao chão
	ALBEDO = min(color.rgb * intensity * fres * ripple * mix(0.4, 1.0, low) * fade, vec3(0.85));
}
