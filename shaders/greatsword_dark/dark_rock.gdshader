shader_type spatial;
// Lâmina Suprema: as placas de pedra partida levantadas nas bordas da cratera (MultiMesh de GreatswordSupremeSlash).
// Pedra escura com rachaduras acesas em violeta e carmesim por dentro (a energia do abismo vazando); a força do brilho
// de cada placa vem do custom data da instância (INSTANCE_CUSTOM.r: acende quando ela salta e esfria).
render_mode cull_back;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 stone_dark = vec3(0.075, 0.062, 0.072);
uniform vec3 stone_light = vec3(0.2, 0.17, 0.17);
uniform vec3 rim_col = vec3(0.48, 0.16, 1.0);
uniform vec3 vein_col = vec3(1.0, 0.1, 0.32);

varying vec3 wpos;
varying float glow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	glow = INSTANCE_CUSTOM.r;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.45 + vec2(wpos.y * 0.3)).r;
	float n2 = texture(noise_tex, wpos.zy * 0.9 + wpos.xx * 0.3).r;
	ALBEDO = mix(stone_dark, stone_light, smoothstep(0.3, 0.8, n));
	ROUGHNESS = 0.95;
	float crack = 1.0 - smoothstep(0.0, 0.045, abs(n2 - 0.5));
	EMISSION = mix(rim_col, vein_col, n) * crack * glow * 3.0;
}
