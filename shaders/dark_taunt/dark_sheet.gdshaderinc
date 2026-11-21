// Círculo da Provocação Sombria: leitura da sprite sheet (assets/vfx/dark_taunt/dark_taunt_sheet.webp, 8 x 8 quadros
// de 128 px, da esquerda para a direita e de cima para baixo, fundo preto). Usado por dark_sheet_add.gdshader (só o
// que brilha, aditivo) e dark_sheet_mix.gdshader (preserva as mãos e a fumaça escuras). Ver DarkSheet.

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
// 0 = billboard virado para a câmera; 1 = o quad como está no nó (deitado no chão); 2 = de pé, gira só em Y
uniform int mode = 0;
// recorte dentro do quadro (x, y, largura, altura em 0..1)
instance uniform vec4 crop = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;
// 0..1: revela do centro para fora (o círculo se desenhando)
instance uniform float reveal = 1.0;
// 1 = apaga as bordas do quad (o recorte não termina num retângulo)
instance uniform float soft_edge = 0.0;

void sheet_vertex(inout mat4 mv, mat4 model, mat4 view, mat4 inv_view) {
	vec3 sc = vec3(length(model[0].xyz), length(model[1].xyz), length(model[2].xyz));
	if (mode == 0) {
		mv = view * mat4(
			vec4(normalize(inv_view[0].xyz) * sc.x, 0.0),
			vec4(normalize(inv_view[1].xyz) * sc.y, 0.0),
			vec4(normalize(inv_view[2].xyz) * sc.z, 0.0),
			model[3]);
	} else if (mode == 2) {
		vec3 to_cam = inv_view[3].xyz - model[3].xyz;
		to_cam.y = 0.0;
		vec3 z = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
		mv = view * mat4(vec4(x * sc.x, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(z * sc.z, 0.0), model[3]);
	}
}

vec3 sheet_frame(float f, vec2 uv) {
	float total = columns * rows;
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	vec2 q = clamp(crop.xy + uv * crop.zw, vec2(0.004), vec2(0.996));
	return texture(sheet, (cell + q) / vec2(columns, rows)).rgb;
}

// quadro fracionário: mistura o atual com o seguinte (a animação não pula)
vec3 sheet_sample(vec2 uv) {
	float f0 = floor(frame);
	return mix(sheet_frame(f0, uv), sheet_frame(f0 + 1.0, uv), frame - f0);
}

float sheet_soft(vec2 uv) {
	if (soft_edge < 0.001) {
		return 1.0;
	}
	float e = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x) * smoothstep(0.0, 0.18, uv.y) * smoothstep(1.0, 0.82, uv.y);
	return mix(1.0, e, soft_edge);
}

float sheet_reveal(vec2 uv) {
	if (reveal >= 0.999) {
		return 1.0;
	}
	float r = length(uv - 0.5) * 2.0;
	float a = atan(uv.y - 0.5, uv.x - 0.5);
	float wob = 0.07 * sin(a * 7.0 + TIME * 5.0) + 0.04 * sin(a * 19.0 - TIME * 9.0);
	return 1.0 - smoothstep(reveal * 1.15 - 0.1, reveal * 1.15 + 0.02, r + wob);
}
