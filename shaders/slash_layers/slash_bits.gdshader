shader_type spatial;
// Corte em camadas (LayeredSlashTrail): arcos secundários, lascas e faíscas, todos na mesma superfície, aditivos.
// COLOR.rgb já vem com a cor e o brilho de cada peça; COLOR.a = quanto ela ainda vale (some com a idade).
// UV.x atravessa a peça (0..1, macia nas bordas), UV.y = da base (0) à ponta (1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

// brilho geral: as cores dos vértices ficam em 0..1 (8 bits); o que passa de 1 vem daqui
uniform float gain = 2.6;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float shape = smoothstep(0.0, 0.55, across) * (0.35 + 0.65 * UV.y);
	ALBEDO = COLOR.rgb * shape * COLOR.a * gain;
	ALPHA = 1.0;
}
