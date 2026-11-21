shader_type spatial;
// Faixa de metal derretido no chão (Forjador Rúnico): miolo incandescente que escorre ao longo da faixa, borda
// de escória escura com fio carmim, beirada roída. `heat` 1 = recém-derramado (amarelo/laranja), 0 = esfriando
// (vermelho escuro); `fade` apaga no fim. A malha é um plano; UV.x atravessa a faixa, UV.y vai ao longo dela.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

instance uniform float heat = 1.0;
instance uniform float fade = 0.0;
instance uniform float seed = 0.0;
instance uniform float aspect = 8.0;   // comprimento / largura da faixa

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);            // 0 no meio, 1 na beirada
	float along = UV.y * aspect;
	float ends = min(UV.y, 1.0 - UV.y) * aspect;     // distância até as pontas, em larguras
	float rough = noise(vec2(along * 1.6 + seed, seed * 3.0)) * 0.34;
	float body = 1.0 - across - rough + min(ends * 0.8, 0.25) - 0.2;
	if (body < 0.0) {
		discard;
	}
	float flow = noise(vec2(UV.x * 3.0 + seed, along * 1.2 - TIME * 0.7));
	float core = smoothstep(0.12, 0.5, body + flow * 0.22 - 0.1);
	vec3 crust = vec3(0.1, 0.012, 0.03);
	vec3 rim = vec3(0.86, 0.1, 0.16);
	vec3 hot = mix(vec3(0.8, 0.12, 0.05), mix(vec3(1.0, 0.5, 0.1), vec3(1.0, 0.86, 0.45), flow), heat);
	vec3 col = mix(crust, rim, smoothstep(0.02, 0.14, body));
	col = mix(col, hot, core);
	ALBEDO = col;
	ALPHA = (0.82 + 0.18 * core) * (1.0 - fade);
}
