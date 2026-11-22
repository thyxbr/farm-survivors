shader_type spatial;
// Grito do Bastião: um quadro da sprite sheet dos escudos azuis (assets/vfx/party_shield/party_shield_sheet.png,
// h_frames = 8, v_frames = 8: 64 quadros de 128 px, da esquerda para a direita e de cima para baixo, fundo preto
// puro). Mistura ADITIVA: o preto não soma nada e some sozinho, sem retângulo; `black_cut` zera o ruído da compressão.
// Billboard virado para a câmera. A arte é um anel em perspectiva: a metade de cima do quadro é o lado de trás do anel
// e a de baixo, o da frente. Com `half_mode` = 1 (só a de cima) num quad empurrado para trás do personagem (`push` < 0)
// e `half_mode` = 2 (só a de baixo) num empurrado para a frente, o corpo tapa o lado de trás do anel (PartyShieldBuff).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float h_frames = 8.0;
uniform float v_frames = 8.0;
uniform float black_cut = 0.06;
uniform float gain = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// altura (0..1 no quadro, de cima para baixo) onde as duas metades se encontram, e a largura da emenda suave
uniform float seam = 0.5;
uniform float seam_soft = 0.08;

// quadro atual, o próximo e a mistura entre eles (a animação não pula; no laço o próximo do último é o primeiro)
instance uniform float frame_a = 0.0;
instance uniform float frame_b = 0.0;
instance uniform float blend = 0.0;
instance uniform float intensity = 1.0;
// 0 = o quadro inteiro; 1 = só a metade de cima (trás do anel); 2 = só a de baixo (frente)
instance uniform float half_mode = 0.0;
// metros na direção da câmera (negativo = para trás); o tamanho na tela é compensado
instance uniform float push = 0.0;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	float dist = max(length(to_cam), 0.01);
	vec3 o = origin + to_cam / dist * push;
	float k = clamp((dist - push) / dist, 0.2, 4.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * sc.x * k, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * sc.y * k, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * sc.z * k, 0.0),
		vec4(o, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec3 frame_rgb(float f, vec2 uv) {
	float total = h_frames * v_frames;
	f = clamp(floor(f + 0.001), 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, h_frames), floor(f / h_frames));
	vec2 q = clamp(uv, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + q) / vec2(h_frames, v_frames)).rgb;
}

void fragment() {
	vec3 c = mix(frame_rgb(frame_a, UV), frame_rgb(frame_b, UV), clamp(blend, 0.0, 1.0));
	float lum = pow(max(c.r, max(c.g, c.b)), 0.4545);   // percebida: a textura vem linearizada
	c *= smoothstep(black_cut, black_cut + 0.08, lum);
	float m = 1.0;
	if (half_mode > 0.5 && half_mode < 1.5) {
		m = 1.0 - smoothstep(seam - seam_soft, seam + seam_soft, UV.y);
	} else if (half_mode > 1.5) {
		m = smoothstep(seam - seam_soft, seam + seam_soft, UV.y);
	}
	// cantos do quad sempre apagados (nada de retângulo se a arte encostar na borda)
	vec2 e = smoothstep(vec2(0.0), vec2(0.06), UV) * smoothstep(vec2(0.0), vec2(0.06), vec2(1.0) - UV);
	ALBEDO = c * tint * gain * intensity * m * e.x * e.y;
	ALPHA = 1.0;
}
