shader_type spatial;
// Mão sombria (ShadowHand): corpo quase preto e arroxeado, com a borda acesa em violeta (fresnel: o contorno brilha,
// o miolo fica escuro) e veias de energia subindo pelo braço. As pontas dos dedos esquentam para o magenta.
//   clip_y      altura do chão (mundo): abaixo dela não desenha, então o braço parece sair de dentro do chão.
//   dissolve    0..1: desfaz em fumaça de baixo para cima com a borda acesa (afundando/sumindo).
//   glow        intensidade da energia (DarkTauntConfig.energy_intensity e o aperto ao agarrar).
// Opaco (ordena bem entre os dedos); o ar espectral vem da borda acesa. Material compartilhado, valores por instância.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 col_core : source_color = vec3(0.025, 0.0, 0.045);
uniform vec3 col_rim : source_color = vec3(0.6, 0.22, 1.0);
uniform vec3 col_hot : source_color = vec3(1.0, 0.3, 0.85);
uniform float rim_power = 2.2;
instance uniform float clip_y = -1000.0;
instance uniform float dissolve = 0.0;
instance uniform float glow = 1.0;
// 0..1 ao longo do braço (pela altura local): as pontas (1) esquentam
instance uniform float tip_from = 1.2;

varying vec3 world_pos;
varying vec3 local_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
}

void fragment() {
	if (world_pos.y < clip_y) {
		discard;
	}
	float n = noise(world_pos * 7.0 + vec3(0.0, -TIME * 1.6, 0.0));
	// dissolve: some de baixo para cima, com ruído
	float h = clamp((world_pos.y - clip_y) / 2.2, 0.0, 1.0);
	float cut = dissolve * 1.25 - h * 0.25;
	if (n < cut) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, 0.08, n - cut);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	// veias: faixas de ruído subindo pelo braço
	float vein = smoothstep(0.66, 0.74, noise(world_pos * vec3(9.0, 3.0, 9.0) + vec3(0.0, -TIME * 2.4, 0.0)));
	float tip = smoothstep(tip_from, tip_from + 0.12, local_pos.y);
	vec3 rim = mix(col_rim, col_hot, clamp(tip + edge, 0.0, 1.0));
	// perto do chão a mão ainda está "do outro lado": a borda acende mais forte
	float ground = 1.0 - smoothstep(0.0, 0.25, world_pos.y - clip_y);
	vec3 col = col_core + rim * (fres * 2.2 + vein * 0.5 + tip * 0.6 + ground * 1.2) * glow + col_hot * edge * 3.0 * glow;
	ALBEDO = col;
}
