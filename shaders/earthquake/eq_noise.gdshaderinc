// Terremoto Devastador: ruído de valor barato (sem textura) para quebrar as bordas do anel, das fissuras e da pedra.

float eq_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float eq_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(eq_hash(i), eq_hash(i + vec2(1.0, 0.0)), u.x),
		mix(eq_hash(i + vec2(0.0, 1.0)), eq_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float eq_fbm(vec2 p) {
	return eq_noise(p) * 0.55 + eq_noise(p * 2.13 + 7.1) * 0.3 + eq_noise(p * 4.37 - 3.3) * 0.15;
}
