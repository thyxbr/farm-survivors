// Linhas de vento (estilo desenho): cada partícula voa na direção do vento ondulando de lado e para
// cima, às vezes dá uma volta inteira (laço), e deixa um rastro fino e branco (trail do GPUParticles3D
// com RibbonTrailMesh). A base da partícula vira para a câmera para o rastro chato não sumir de lado.
shader_type particles;

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 camera_pos = vec3(0.0);
uniform vec3 box = vec3(14.0, 2.0, 14.0);   // meia-extensão da área de nascimento
uniform float speed = 9.0;
uniform float loop_chance = 0.35;

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 9277u + RANDOM_SEED * 26699u + uint(INDEX) * 7919u;
	vec3 p = vec3(rnd(s), rnd(s), rnd(s)) * 2.0 - 1.0;
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(p * box, 1.0)).xyz;
	// CUSTOM: x = fase, y = amplitude da ondulação, z = início do laço (< 0: sem laço), w = idade
	CUSTOM.x = rnd(s) * 6.2831;
	CUSTOM.y = 0.35 + rnd(s) * 0.55;
	CUSTOM.z = rnd(s) < loop_chance ? 0.25 + rnd(s) * 0.35 : -1.0;
	CUSTOM.w = 0.0;
	VELOCITY = wind_dir * speed;
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}

void process() {
	float t = CUSTOM.w;
	CUSTOM.w += DELTA;
	vec3 fwd = normalize(wind_dir);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 side = normalize(cross(fwd, up));
	float ph = CUSTOM.x;
	float amp = CUSTOM.y;
	vec3 v = fwd * speed
			+ side * cos(t * 2.4 + ph) * amp * speed * 0.35
			+ up * cos(t * 3.3 + ph * 1.7) * amp * speed * 0.18;
	// laço: durante 0,55 s a velocidade gira uma volta no plano (frente, cima)
	float life = t / LIFETIME;
	if (CUSTOM.z >= 0.0) {
		float lt = (life - CUSTOM.z) / (0.55 / LIFETIME);
		if (lt > 0.0 && lt < 1.0) {
			float a = lt * 6.2831;
			v = (fwd * cos(a) + up * sin(a)) * speed * 0.75 + side * amp * 0.6;
		}
	}
	VELOCITY = v;
	// o rastro chato fica de frente para a câmera: X da partícula perpendicular à direção e à câmera
	vec3 dir = normalize(v);
	vec3 to_cam = normalize(camera_pos - TRANSFORM[3].xyz);
	vec3 x = cross(dir, to_cam);
	x = length(x) > 1e-3 ? normalize(x) : side;
	vec3 z = normalize(cross(x, dir));
	TRANSFORM[0].xyz = x;
	TRANSFORM[1].xyz = dir;
	TRANSFORM[2].xyz = z;
	COLOR = vec4(1.0, 1.0, 1.0, smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.65, 1.0, life)));
}
