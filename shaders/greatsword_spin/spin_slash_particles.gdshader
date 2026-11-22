shader_type particles;
// Ciclone de Aço: os cortes soltos (GPUParticles3D Slashes em GreatswordSpinSlash, coordenadas locais). Cada partícula é
// um corte inteiro da sprite sheet (spin_slash_flipbook.gdshader com `particle_frames`) num PlaneMesh deitado, centrado
// no herói: nasce na altura da lâmina com um giro qualquer em volta do herói, inclinado até `tilt_max` em relação ao
// chão (cortes em vários ângulos), e varre girando em volta do próprio eixo enquanto toca os quadros.
//   CUSTOM.y = vida (0..1): o quadro da sheet e o apagar (COLOR.a)
render_mode disable_velocity;

uniform float tilt_max = 0.66;          // rad
uniform float size_min = 5.0;           // diâmetro (m)
uniform float size_max = 6.6;
uniform float height = 1.0;             // altura do centro (m)
uniform float height_jitter = 0.35;
uniform float sweep_speed = 7.0;        // giro em volta do próprio eixo (rad/s, o sentido do giro do herói)
// fração dos cortes que nascem (0..1): GreatswordSpinSlash acompanha a velocidade do giro e a derruba com Tween ao
// desacelerar (o amount_ratio do nó não segura a emissão de um shader de partículas próprio)
uniform float emit_ratio = 1.0;

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

mat3 rot_y(float a) {
	return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
}

mat3 rot_x(float a) {
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a)));
}

mat3 rot_z(float a) {
	return mat3(vec3(cos(a), sin(a), 0.0), vec3(-sin(a), cos(a), 0.0), vec3(0.0, 0.0, 1.0));
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	// não nasce (fica inativo até a próxima volta da emissão)
	if (rand_from_seed(seed) >= emit_ratio) {
		ACTIVE = false;
	}
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.0, 0.0, 1.0);
	}
	if (RESTART_ROT_SCALE || RESTART_POSITION) {
		float yaw = rand_from_seed(seed) * TAU;
		float tilt = (rand_from_seed(seed) * 2.0 - 1.0) * tilt_max;
		float roll = (rand_from_seed(seed) * 2.0 - 1.0) * tilt_max * 0.6;
		float size = mix(size_min, size_max, rand_from_seed(seed));
		float y = height + (rand_from_seed(seed) * 2.0 - 1.0) * height_jitter;
		mat3 b = rot_y(yaw) * rot_x(tilt) * rot_z(roll) * size;
		TRANSFORM = EMISSION_TRANSFORM * mat4(vec4(b[0], 0.0), vec4(b[1], 0.0), vec4(b[2], 0.0), vec4(0.0, y, 0.0, 1.0));
	}
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float a = CUSTOM.y;
	// acende rápido e se apaga no fim da passada
	COLOR.a = smoothstep(0.0, 0.08, a) * (1.0 - smoothstep(0.65, 1.0, a));
	// varre em volta do próprio eixo (o Y local, a normal do plano)
	mat3 b = mat3(TRANSFORM[0].xyz, TRANSFORM[1].xyz, TRANSFORM[2].xyz) * rot_y(sweep_speed * DELTA);
	TRANSFORM[0].xyz = b[0];
	TRANSFORM[1].xyz = b[1];
	TRANSFORM[2].xyz = b[2];
	if (CUSTOM.y > CUSTOM.w) {
		ACTIVE = false;
	}
}
