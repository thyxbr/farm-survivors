shader_type spatial;
// Esfera Sombria: a casca. Fios de fumaça pintados (fios_faixa.png, faixa que repete) correndo em volta de uma
// esfera; a malha é inclinada e girada por código. Só a beirada da esfera mostra os fios (de frente fica o miolo
// das camadas de riscos), os mais claros em violeta: são os arcos finos em volta da bola.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D strands : source_color, filter_linear_mipmap, repeat_enable;

instance uniform vec3 dark = vec3(0.03, 0.01, 0.06);
instance uniform vec3 glow = vec3(0.62, 0.5, 1.0);
instance uniform float intensity = 1.0;
instance uniform float flow = 1.0;
instance uniform float phase = 0.0;

void fragment() {
	float g = texture(strands, vec2(UV.x * 2.0 + TIME * flow + phase, mix(0.08, 0.92, UV.y))).r;
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float lit = smoothstep(0.85, 1.0, g);
	ALBEDO = mix(dark, glow, lit);
	ALPHA = smoothstep(0.45, 0.85, g) * smoothstep(0.25, 0.8, edge) * sin(UV.y * PI) * intensity;
}
