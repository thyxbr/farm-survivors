shader_type spatial;
// Faixas de energia do Manto do Vazio (referência "Celestial Knight", Natam Antony): o pano azul vira energia
// líquida que escorre devagar, com veios mais claros e bolhas/pontos de luz que sobem e piscam. É luz própria
// (sem sombra da cena), mas a borda escurece pelo ângulo com a câmera para a faixa não ficar chapada.
// Montado por GearFx (scripts/player/gear_fx.gd) pelo nome do material.
render_mode cull_back, unshaded;

uniform vec3 albedo : source_color = vec3(0.12, 0.31, 0.65);  // cor do GLB (só referência; usamos as de baixo)
uniform vec3 deep_col : source_color = vec3(0.03, 0.16, 0.62); // fundo da energia
uniform vec3 mid_col : source_color = vec3(0.1, 0.45, 1.0);    // corpo da energia
uniform vec3 hot_col : source_color = vec3(0.7, 0.92, 1.0);    // veios e bolhas
uniform float energy = 1.25;
uniform float flow_speed = 0.12;   // m/s que a energia escorre (para baixo)
uniform float vein_scale = 9.0;    // veios por metro
uniform float bubble_cell = 0.016; // tamanho da célula das bolhas, m
uniform float bubble_density = 0.5;
uniform float rim = 0.55;          // quanto a borda escurece (0 = chapado)

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

// bolhas: um ponto redondo por célula, subindo devagar e piscando no seu tempo
float bubbles(vec3 p, float cell, float t) {
	vec3 q = p + vec3(0.0, -t * 0.05, 0.0);
	vec3 g = q / cell;
	vec3 id = floor(g);
	float r = hash3(id);
	if (r > bubble_density) {
		return 0.0;
	}
	vec3 o = vec3(hash3(id + 3.1), hash3(id + 9.7), hash3(id + 5.3)) * 0.5 + 0.25;
	float d = length(fract(g) - o);
	float size = 0.12 + 0.22 * hash3(id + 7.7);
	float tw = 0.5 + 0.5 * sin(t * (1.2 + 2.5 * hash3(id + 1.3)) + r * 50.0);
	return step(d, size * (0.55 + 0.45 * tw)) * step(0.25, tw);
}

void vertex() {
	pos = VERTEX;
}

void fragment() {
	float t = TIME;
	vec3 p = pos + vec3(0.0, t * flow_speed, 0.0);   // amostrar mais alto com o tempo = o desenho desce
	// corpo: ruído esticado na vertical, em dois tons chapados (estilo desenho)
	float n = noise3(p * vec3(vein_scale, vein_scale * 0.45, vein_scale)) * 0.65
		+ noise3(p * vec3(vein_scale, vein_scale * 0.45, vein_scale) * 2.3 + 4.1) * 0.35;
	vec3 c = mix(deep_col, mid_col, smoothstep(0.32, 0.36, n));
	// veios claros: a borda fina entre os dois tons, como corrente elétrica
	float vein = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.62));
	c = mix(c, hot_col, vein * 0.5);
	// bolhas em duas escalas
	float b = max(bubbles(pos, bubble_cell, t), bubbles(pos + 2.7, bubble_cell * 2.2, t * 0.8) * 0.8);
	c = mix(c, hot_col, b);
	// sombra fingida pelo ângulo: o miolo de frente fica claro, a borda some no azul fundo
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(1.0 - rim, 1.0, facing);
	ALBEDO = c * energy;
}
