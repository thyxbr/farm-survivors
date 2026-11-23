shader_type spatial;
// Canalização de Fogo: cada partícula da labareda é um pedaço de chama da sheet B (assets/vfx/flame_channel/
// flame_jet_clean.png, 8 x 8 quadros de 128 px, fundo preto) num billboard virado para a câmera. Mistura
// pré-multiplicada com alfa = brilho (ver `occlusion`): o fundo preto some como no aditivo, mas os pedaços empilhados
// não estouram em branco. Dezenas deles, crescendo e esfriando ao longo da vida (a rampa de cor do
// ParticleProcessMaterial chega em COLOR), formam o volume do jato.
// Flipbook: o ParticleProcessMaterial avança INSTANCE_CUSTOM.z (anim_speed / anim_offset); aqui ele vira um quadro
// dentro de [frame_from, frame_to] (só os quadros cheios de fogo da sheet), em laço e com mistura entre um quadro e o
// seguinte. O recorte elíptico esconde o retângulo do quadro, e o fade de proximidade
// (profundidade da cena) some a chama onde ela entra no chão ou numa parede, sem linha dura.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float columns = 8.0;
uniform float rows = 8.0;
uniform float frame_from = 14.0;
uniform float frame_to = 33.0;
uniform float black_cut = 0.05;
uniform float gain = 1.6;
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.78);
// m em que a chama some ao encostar na cena (0 = sem fade)
uniform float soft_distance = 0.5;
// raio do recorte elíptico (fração do quadro) e quanto dele esmaece
uniform float mask_radius = 0.5;
uniform float mask_soft = 0.3;
// quanto a chama cobre o que está atrás (alfa = brilho x isto): 0 = aditivo puro (empilhado estoura em branco), 1 = a
// chama densa fica da cor do fogo. O preto continua transparente (brilho 0 = alfa 0 e cor 0).
uniform float occlusion = 0.7;
// > 1 escurece os meios-tons da sheet (mais laranja, menos branco)
uniform float contrast = 1.6;
// quanto da rotação sorteada sobra com a chama alinhada ao voo (0 = todas exatamente na direção do jato)
uniform float align_jitter = 0.15;

varying float anim;

void vertex() {
	anim = INSTANCE_CUSTOM.z;
	// billboard de partícula virado para a câmera e GIRADO NA DIREÇÃO DO VOO: com `particle_flag_align_y` no
	// ParticleProcessMaterial o eixo Y da partícula é a velocidade; projetada na tela, ela diz para onde o +U do quadro
	// (a sheet corre da esquerda para a direita) deve apontar, e as línguas de fogo seguem o jato em vez de ir para os
	// lados. A rotação sorteada (INSTANCE_CUSTOM.x) vira só uma variação pequena; com o voo apontando para a câmera
	// (projeção curta, sem direção na tela) volta à rotação sorteada.
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	vec3 p0 = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 p1 = p0 + (VIEW_MATRIX * vec4(normalize(MODEL_MATRIX[1].xyz), 0.0)).xyz * 0.5;
	vec2 d = (p1.xy / max(-p1.z, 0.05) - p0.xy / max(-p0.z, 0.05)) * max(-p0.z, 0.05);
	float along = smoothstep(0.04, 0.2, length(d));
	float a = mix(INSTANCE_CUSTOM.x, -atan(d.y, d.x) + INSTANCE_CUSTOM.x * align_jitter, along);
	mat_world = mat_world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec3 cell_rgb(float f, vec2 uv) {
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	return texture(sheet, (cell + uv) / vec2(columns, rows)).rgb;
}

void fragment() {
	float n = max(frame_to - frame_from + 1.0, 1.0);
	float x = fract(anim) * n;
	float f0 = floor(x);
	float k = x - f0;
	float fa = frame_from + mod(f0, n);
	float fb = frame_from + mod(f0 + 1.0, n);
	vec3 col = mix(cell_rgb(fa, UV), cell_rgb(fb, UV), k);
	float lum = pow(max(col.r, max(col.g, col.b)), 0.4545);
	col *= smoothstep(black_cut, black_cut + 0.08, lum);
	// contraste: os meios-tons da chama descem para o laranja-vermelho e só o miolo fica amarelo (empilhados, os
	// pedaços não viram uma massa branca e o desenho das línguas de fogo aparece)
	col = pow(col, vec3(contrast));
	col = mix(col, hot * lum, smoothstep(0.85, 1.0, lum) * 0.25);
	float r = length((UV - 0.5) * vec2(1.0, 1.15)) * 2.0;
	float mask = 1.0 - smoothstep(mask_radius * 2.0 - mask_soft, mask_radius * 2.0, r);
	float soft = 1.0;
	if (soft_distance > 0.0) {
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 world_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		world_pos.xyz /= world_pos.w;
		soft = clamp(1.0 - smoothstep(world_pos.z + soft_distance, world_pos.z, VERTEX.z), 0.0, 1.0);
	}
	float w = COLOR.a * mask * soft;
	ALBEDO = col * COLOR.rgb * gain * w;
	ALPHA = clamp(lum * occlusion * w, 0.0, 1.0);
}
