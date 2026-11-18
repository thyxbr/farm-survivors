shader_type spatial;
// Peças acesas dos conjuntos de fim de jogo (gemas, fios, olhos, runas): em vez da emissão parada do GLB, a
// luz corre pela peça em ondas, pulsa, tremula como chama ou cintila ponto a ponto, conforme os parâmetros
// que GearFx (scripts/player/gear_fx.gd) escolhe para cada conjunto. Sem sombra de forma: é luz própria.
render_mode cull_back, unshaded;

uniform vec3 albedo : source_color = vec3(1.0);          // cor da peça apagada
uniform vec3 emission : source_color = vec3(1.0);        // cor da luz
uniform vec3 hot : source_color = vec3(1.0);             // cor na crista da onda
uniform float energy = 1.5;
uniform float low = 0.45;                 // quanto sobra da luz no vale da onda (0 = apaga)
uniform vec3 flow_dir = vec3(0.0, 1.0, 0.0);    // onda que corre pela peça (espaço do modelo)
uniform float flow_freq = 0.0;            // ondas por metro (0 = sem onda)
uniform float flow_speed = 1.0;
uniform float flow_sharp = 3.0;           // crista mais fina
uniform float pulse = 0.0;                // pulso da peça inteira (0..1)
uniform float pulse_speed = 1.5;
uniform float flicker = 0.0;              // tremor de chama (0..1), sobe pela peça
uniform float twinkle = 0.0;              // cintilação ponto a ponto (0..1), em células de `twinkle_cell` m
uniform float twinkle_cell = 0.03;

varying vec3 pos;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	pos = VERTEX;
}

void fragment() {
	float t = TIME;
	float k = 1.0;        // brilho relativo (1 = como no GLB)
	float crest = 0.0;
	if (flow_freq > 0.0) {
		float w = 0.5 + 0.5 * sin(dot(pos, flow_dir) * flow_freq * TAU - t * flow_speed);
		crest = pow(w, flow_sharp);
		k *= mix(low, 1.35, crest);
	}
	if (pulse > 0.0) {
		k *= 1.0 - pulse * (0.5 + 0.5 * sin(t * pulse_speed));
	}
	if (flicker > 0.0) {
		float n = noise3(pos * vec3(26.0, 14.0, 26.0) - vec3(0.0, t * 1.6, 0.0)) * 0.65 + noise3(pos * 60.0 + t * 2.3) * 0.35;
		// degraus: a chama desenhada tem dois ou três tons, não degradê
		float f = 0.45 + 0.35 * step(0.38, n) + 0.45 * step(0.62, n);
		k *= mix(1.0, f, flicker);
		crest = max(crest, flicker * step(0.62, n));
	}
	if (twinkle > 0.0) {
		vec3 cell = floor(pos / twinkle_cell);
		float ph = hash3(cell);
		float tw = 0.5 + 0.5 * sin(t * (1.5 + 3.5 * ph) + ph * 40.0);
		k *= mix(1.0, 0.35 + 1.1 * tw * tw, twinkle);
		crest = max(crest, twinkle * step(0.9, tw));
	}
	// sem luz da cena (unshaded): a cor passa de 1 para acender o brilho da tela (glow) como a emissão fazia
	ALBEDO = mix(albedo, hot, crest * 0.6) * 0.55 + mix(emission, hot, crest) * energy * k;
}
