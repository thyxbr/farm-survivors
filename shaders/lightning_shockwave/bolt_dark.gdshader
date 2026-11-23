shader_type spatial;
// O "negativo" do raio: logo depois do clarão o mesmo desenho fica preto por alguns quadros (como na animação
// desenhada). Ver bolt_common.gdshaderinc.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
#include "bolt_common.gdshaderinc"

void fragment() {
	float g = bolt_value(UV);
	ALBEDO = vec3(0.0, 0.0, 0.015);
	ALPHA = smoothstep(0.35, 0.7, g) * intensity;
}
