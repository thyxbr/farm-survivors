shader_type spatial;
// Lâminas Rúnicas: o corpo da lâmina (lamina_runica.png: fuso facetado cinza com contorno branco, fundo preto).
// O cinza das facetas vira cristal vermelho escuro e o contorno branco acende na cor.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
#include "blade_common.gdshaderinc"

uniform sampler2D blade : source_color, filter_linear_mipmap, repeat_disable;
// o recorte da pintura que tem a lâmina (o resto da imagem é fundo)
uniform vec4 crop = vec4(0.3, 0.02, 0.7, 0.985);

void fragment() {
	float g = texture(blade, vec2(mix(crop.x, crop.z, UV.x), mix(crop.y, crop.w, UV.y))).r;
	float edge = smoothstep(0.7, 0.95, g);
	vec3 body = col * mix(0.1, 0.6, smoothstep(0.1, 0.5, g));
	ALBEDO = mix(body, mix(col, vec3(1.0), 0.2) * 1.8, edge);
	ALPHA = smoothstep(0.04, 0.14, g) * intensity;
}
