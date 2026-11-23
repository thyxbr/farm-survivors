shader_type spatial;
// O vento gelado do Sopro: faixa pintada (sopro_faixa.png, riscos de vento e flocos, repete na horizontal) correndo
// ao longo de um quad comprido que gira em volta do próprio eixo para a câmera (o Y do nó é a direção do sopro, da
// boca para longe). Nasce estreita na boca, abre em cone, corre para a ponta e some nela.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
#include "res://shaders/rune_blades/blade_common.gdshaderinc"

uniform sampler2D wind : source_color, filter_linear_mipmap, repeat_enable;
uniform float flow = 2.4;
uniform float repeat = 1.3;
uniform float mouth_w = 0.12;

instance uniform vec3 core = vec3(0.7, 0.93, 1.0);
instance uniform float seed = 0.0;
instance uniform float reveal = 1.0;

void fragment() {
	// UV.y = 1 na boca (base do quad) e 0 na ponta
	float along = 1.0 - UV.y;
	// cone: na boca a rajada tem `mouth_w` da largura e abre até a largura toda; a pintura é espremida junto, então
	// os riscos saem todos do mesmo ponto
	float x = (UV.x - 0.5) * 2.0;
	float w = mix(mouth_w, 1.0, smoothstep(0.0, 0.55, along));
	float across = 1.0 - smoothstep(w * 0.8, w, abs(x));
	float g = texture(wind, vec2(along * repeat - TIME * flow + seed, 0.5 + 0.4 * clamp(x / w, -1.0, 1.0))).r;
	// perto da boca o jato é denso (some o vão entre os riscos)
	g = max(g, (1.0 - smoothstep(0.0, 0.14, along)) * 0.75);
	float ends = smoothstep(0.0, 0.015, along) * (1.0 - smoothstep(reveal - 0.25, reveal, along)) * (1.0 - smoothstep(0.6, 1.0, along)) * across;
	ALBEDO = mix(col, core, smoothstep(0.45, 0.9, g)) * (1.0 + 0.5 * g);
	ALPHA = smoothstep(0.1, 0.55, g) * ends * intensity;
}
