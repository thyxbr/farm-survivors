shader_type spatial;
// Lâmina Suprema: a espada gigante em chamas, na malha 3D de espada (GreatswordSupremeSlash.sword_mesh: lâmina com
// quina no meio e ponta, guarda, cabo e pomo). Começa como ferro escuro e pega fogo da guarda para a ponta conforme
// `heat` sobe (como na sprite sheet assets/vfx/greatsword_supreme/flame_sword_sheet.webp): brasa vermelha, laranja e o
// miolo da quina incandescente, com o fio da lâmina brilhando e chamas de ruído (noise_tex) subindo pela superfície.
// As cores passam de 1 (HDR): o glow do ambiente (WorldLighting, limiar 1,1) faz a lâmina brilhar.
// Comprimento 1 na malha: o cabo nas mãos (y = 0), a ponta em y = 1 e o pomo em y = -0.1.
//   UV.x   na lâmina: 0 no gume, 1 na quina do meio      COLOR.r 1 = lâmina, 0 = guarda, cabo e pomo
//   grow      0..1: a espada (ainda de ferro) se forma do pomo até a ponta
//   heat      0..1: o fogo sobe da guarda até a ponta e esquenta até o miolo branco
//   intensity brilho geral (0 = apagada)          dissolve 0..1: se desfaz em pedaços (o fim do efeito)
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 iron_dark : source_color = vec3(0.07, 0.065, 0.065);
uniform vec3 iron_light : source_color = vec3(0.42, 0.4, 0.4);
uniform vec3 ember_color : source_color = vec3(0.75, 0.08, 0.02);
uniform vec3 fire_color : source_color = vec3(1.0, 0.42, 0.06);
uniform vec3 hot_color : source_color = vec3(1.0, 0.8, 0.42);
uniform vec3 core_color : source_color = vec3(1.0, 0.97, 0.88);
uniform float hdr = 2.4;           // quanto as partes mais quentes passam de 1 (o glow pega nelas)
uniform float flame_speed = 0.9;   // velocidade das chamas subindo pela lâmina
uniform float pommel_y = -0.1;
instance uniform float grow = 1.0;
instance uniform float heat = 0.0;
instance uniform float intensity = 1.0;
instance uniform float dissolve = 0.0;

varying float along;
varying float part;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	along = VERTEX.y;
	part = COLOR.r;
}

// rampa de temperatura: ferro -> brasa -> fogo -> quente -> miolo branco (HDR)
vec3 fire_ramp(float t) {
	vec3 c = mix(ember_color, fire_color, smoothstep(0.2, 0.5, t));
	c = mix(c, hot_color, smoothstep(0.5, 0.8, t));
	c = mix(c, core_color, smoothstep(0.8, 1.0, t));
	return c * (1.0 + (hdr - 1.0) * smoothstep(0.45, 1.0, t));
}

void fragment() {
	// formação (ferro) do pomo até a ponta
	float front = mix(pommel_y, 1.02, grow);
	if (along > front) {
		discard;
	}
	if (dissolve > 0.0 && hash(floor(vec2(UV.x * 3.0 + part * 7.0, along * 40.0))) < dissolve) {
		discard;
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.0);
	// ferro: escuro com o brilho das faces viradas para a câmera e a borda clara (metal sem luz da cena)
	vec3 iron = mix(iron_dark, iron_light, pow(facing, 3.0) * 0.6 + rim * 0.35);
	// chamas subindo: duas camadas de ruído correndo para a ponta, deformadas uma pela outra
	float t = TIME * flame_speed;
	vec2 q = vec2(UV.x * 0.35 + part * 0.5, along * 2.2);
	float warp = texture(noise_tex, q * 0.7 + vec2(0.0, -t * 0.6)).r;
	float n = texture(noise_tex, q + vec2(warp * 0.25, -t)).r * 0.65
		+ texture(noise_tex, q * 2.3 + vec2(0.37, -t * 1.7)).r * 0.35;
	// o fogo sobe da guarda (y ~0.07) até a ponta conforme `heat`
	float lit = 1.0 - smoothstep(heat * 1.25 - 0.18, heat * 1.25 + 0.02, along - 0.05);
	lit *= smoothstep(0.0, 0.15, heat);
	vec3 c;
	if (part > 0.5) {
		float ridge = smoothstep(0.45, 1.0, UV.x);
		float edge = 1.0 - smoothstep(0.0, 0.16, UV.x);
		float temp = lit * (0.35 + 0.55 * n + ridge * 0.45 * heat + edge * 0.3);
		c = mix(iron, fire_ramp(clamp(temp, 0.0, 1.0)), smoothstep(0.08, 0.3, temp));
	} else {
		// guarda, cabo e pomo: ferro carbonizado (fica escuro) com um brilho de brasa por cima, sem trocar a cor
		float speck = texture(noise_tex, vec2(UV.x * 3.0 + along * 9.0, along * 14.0 - t * 0.5)).r;
		float glow = lit * smoothstep(0.62, 0.82, speck) * 0.6;
		c = iron * 0.75 + fire_color * glow;
	}
	// fio da lâmina e contorno acesos
	if (part > 0.5) {
		float edge = 1.0 - smoothstep(0.0, 0.12, UV.x);
		c += fire_color * hdr * 0.6 * edge * lit;
	}
	c += fire_color * rim * (part > 0.5 ? 0.8 : 0.15) * lit;
	// faixa da formação
	float band = (1.0 - smoothstep(0.0, 0.045, front - along)) * step(grow, 0.999);
	c = mix(c, fire_color * hdr, band);
	ALBEDO = c * max(intensity, 0.0);
	ALPHA = clamp(intensity, 0.0, 1.0);
}
