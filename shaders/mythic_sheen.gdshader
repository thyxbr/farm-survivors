shader_type spatial;
// Camada por cima do arco mítico inteiro (material_overlay, BowAura): borda acesa na cor do arco, um reflexo que
// percorre o arco de ponta a ponta de tempos em tempos e cintilas miúdas, como metal encantado.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float rim = 0.12;
uniform float sweep_every = 3.2;   // segundos entre reflexos
uniform float sparkle = 0.5;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// reflexo: uma faixa diagonal que desce da ponta de cima até a de baixo
	float ph = fract(TIME / sweep_every);
	float zc = mix(0.9, -0.9, ph);
	float band = exp(-pow((local_pos.z + local_pos.y * 0.6 - zc) / 0.05, 2.0));
	// cintilas: células de 1 cm que acendem uma de cada vez
	vec3 cell = floor(local_pos * 90.0);
	float h = hash(cell);
	float tw = pow(max(0.0, sin(TIME * (1.5 + h * 2.5) + h * 40.0)), 24.0) * step(0.82, h);
	vec3 c = glow_color.rgb;
	ALBEDO = c * (fres * rim + band * 0.4) + mix(c, vec3(1.0), 0.6) * tw * sparkle;
}
