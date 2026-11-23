shader_type spatial;
// Esfera Sombria: uma camada de riscos pintados (vortice_riscos.png, claro em fundo preto) num quad virado para a
// câmera, girando no próprio plano. O risco é fumaça quase preta e só o mais claro da pintura acende em violeta.
// Várias camadas com velocidades, sentidos e tamanhos diferentes dão o volume e o borrão do giro.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D streaks : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec3 dark = vec3(0.03, 0.01, 0.06);
instance uniform vec3 glow = vec3(0.62, 0.5, 1.0);
instance uniform float glow_amt = 1.0;
instance uniform float intensity = 1.0;
instance uniform float spin_speed = 1.0;
instance uniform float phase = 0.0;
instance uniform float flip = 0.0;
// miolo escuro fechado (só a camada de trás usa)
instance uniform float core = 0.0;
instance uniform float blur = 2.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 world = origin + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	if (flip > 0.5) {
		p.x = -p.x;
	}
	float r = length(p) * 2.0;
	// a bola não é um cata-vento certinho: o desenho entorta um pouco, mudando com o tempo
	p += 0.035 * sin(p.yx * 8.0 + TIME * 4.0 + phase);
	// o miolo gira mais que a ponta e respira: os riscos torcem e destorcem
	float a = TIME * spin_speed + phase + (1.0 - clamp(r, 0.0, 1.0)) * (0.9 + 0.5 * sin(TIME * 3.1 + phase));
	float c = cos(a);
	float s = sin(a);
	// amostra borrada (mip mais baixo): os fios finos da pintura juntam em tufos grossos, como no borrão do giro
	float g = textureLod(streaks, vec2(p.x * c - p.y * s, p.x * s + p.y * c) + 0.5, blur).r;
	// falhas: tufos soltos em vez de um disco cheio
	float ang = atan(p.y, p.x);
	float clump = smoothstep(0.2, 0.55, 0.5 + 0.5 * sin(ang * 5.0 + phase + TIME * 2.3) * sin(ang * 3.0 - phase * 2.0 - TIME * 1.4));
	clump = mix(clump, 1.0, core);
	float lit = smoothstep(0.38, 0.75, g) * glow_amt * smoothstep(0.2, 0.6, r);
	ALBEDO = mix(dark, glow, lit);
	// (a cor escura vem sempre do código: ShadowOrbFX)
	float hole = (1.0 - smoothstep(0.1, 0.42, r)) * core;
	ALPHA = max(smoothstep(0.05, 0.26, g) * clump, hole) * (1.0 - smoothstep(0.92, 1.0, r)) * intensity;
}
