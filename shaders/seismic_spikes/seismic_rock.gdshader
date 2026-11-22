shader_type spatial;
// Estacas Sísmicas: o chão rachado, um quadro da sprite sheet 8 x 8 (64 quadros de 128 px, fundo preto puro #000000,
// vista de cima) num plano deitado no chão, desenhado como TERRA, não como luz (com mistura aditiva a terra cinza
// somava com a cena e virava clarão/névoa):
//   - mistura normal (alfa). O fundo preto vira transparente por uma chave de brilho medida no máximo da vizinhança
//     do pixel (`key_spread`), para as fissuras finas e o miolo escuro da cratera não furarem (continuam escuros);
//   - iluminado pela cena (sol, lua, ambiente, a luz laranja do impacto); `self_light` mantém a forma legível no escuro;
//   - só o laranja saturado (brasas nas fissuras) emite, com `ember_glow` baixo: o Glow do ambiente realça sem estourar.
// Quadro fracionário (mistura o atual com o seguinte). Por instância: `frame`, `intensity` (multiplica o alfa: fade),
// `reveal` (0..1: círculo em volta do centro crescendo, as rachaduras se espalhando até o raio).
render_mode cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float columns = 8.0;
uniform float rows = 8.0;
uniform float key_lo = 0.03;
uniform float key_hi = 0.12;
uniform float key_spread = 2.0;
uniform float frame_px = 128.0;
uniform float opacity = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float self_light = 0.12;
uniform vec3 ember_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float ember_glow = 1.0;
uniform float mask_inner = 0.72;
uniform float mask_outer = 0.98;
uniform float reveal_feather = 0.15;
// onde o terreno sobe acima do plano, some aos poucos (sem linha reta)
uniform float soft_depth = 0.02;

instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;
instance uniform float reveal = 1.0;

vec2 cell_uv(float f, vec2 uv) {
	f = clamp(f, 0.0, columns * rows - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	return (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(columns, rows);
}

vec4 sheet_frame(float f, vec2 uv) {
	vec3 c = texture(sheet, cell_uv(f, uv)).rgb;
	float k = max(c.r, max(c.g, c.b));
	vec2 px = vec2(key_spread / frame_px);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec3 n = texture(sheet, cell_uv(f, uv + vec2(cos(a), sin(a)) * px)).rgb;
		k = max(k, max(n.r, max(n.g, n.b)));
	}
	return vec4(c, smoothstep(key_lo, key_hi, k));
}

void fragment() {
	float f0 = floor(frame);
	vec4 s = mix(sheet_frame(f0, UV), sheet_frame(f0 + 1.0, UV), frame - f0);
	vec3 c = s.rgb;
	float lum = max(c.r, max(c.g, c.b));
	float sat = (lum - min(c.r, min(c.g, c.b))) / max(lum, 0.001);
	float ember = smoothstep(0.35, 0.65, sat) * smoothstep(0.08, 0.3, c.r - c.b);
	float r = length(UV - 0.5) * 2.0;
	float mask = 1.0 - smoothstep(mask_inner, mask_outer, r);
	float rv = reveal * (1.0 + reveal_feather);
	mask *= 1.0 - smoothstep(rv - reveal_feather, rv, r);
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	mask *= smoothstep(0.0, soft_depth, scene_z - (-VERTEX.z));
	ALBEDO = c * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = c * tint * self_light + ember_color * ember * lum * ember_glow;
	ALPHA = clamp(s.a * mask * opacity * intensity, 0.0, 1.0);
}
