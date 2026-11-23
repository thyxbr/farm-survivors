shader_type spatial;
// Raio aceso (aditivo): o miolo branco, a borda na cor. Ver bolt_common.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;
#include "bolt_common.gdshaderinc"

void fragment() {
	float g = bolt_value(UV);
	vec3 c = mix(col, vec3(1.0), smoothstep(0.5, 0.95, g) * whiten);
	ALBEDO = c * g * 1.6 * intensity;
	ALPHA = 1.0;
}
