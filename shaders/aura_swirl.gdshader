shader_type spatial;
// Tubo de energia em volta do personagem (CylinderMesh sem tampas): riscos de luz que giram
// em espiral e sobem. Usado pelas auras de vento, cura e herói com cores e ritmos diferentes.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.7, 1.0, 1.0, 1.0);
uniform float strength = 0.8;
uniform float streaks = 3.0;     // quantos riscos em volta (inteiro)
uniform float twist = 1.5;       // quanto o risco enrola ao subir
uniform float spin = 0.8;        // voltas por segundo
uniform float rise = 0.5;        // velocidade com que o padrão sobe
uniform float thin = 0.75;       // 0..1: quanto maior, mais finos os riscos
uniform float height = 1.8;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float h = lp.y / height + 0.5;                 // 0 embaixo, 1 em cima
	float ang = atan(lp.z, lp.x) / TAU + 0.5;      // 0..1 em volta
	float a = fract(ang * streaks + h * twist - TIME * spin);
	// risco: cabeça nítida e cauda longa
	float streak = smoothstep(thin, 1.0, a) * smoothstep(1.0, 0.97, a);
	// quebra os riscos em pedaços que sobem
	float n = noise(vec2(ang * streaks * 2.0, h * 4.0 - TIME * rise * 2.0));
	streak *= smoothstep(0.25, 0.75, n);
	float fade = smoothstep(0.0, 0.2, h) * smoothstep(1.0, 0.45, h);
	// some nas bordas da silhueta do tubo (evita linha dura no contorno)
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb;
	ALPHA = streak * fade * strength * smoothstep(0.05, 0.5, facing);
}
