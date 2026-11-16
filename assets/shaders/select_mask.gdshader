shader_type spatial;
// Seleção de personagem: marca no stencil (valor 1) os pixels do herói selecionado, sem desenhar cor.
// A borda (select_glow) só aparece fora dessa marca: fica a silhueta do corpo inteiro, sem as arestas
// de cada peça por dentro.
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, depth_test_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
