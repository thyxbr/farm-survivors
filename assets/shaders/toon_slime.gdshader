shader_type spatial;
// Gelatina no estilo toon (corpo e base do slime): a mesma luz em dois tons do resto do jogo, sobre um
// corpo translúcido. A borda vista de lado fica mais grossa: mais opaca e mais escura, em degrau, como a
// espessura de uma gota. Grava profundidade para que o contorno (toon_slime_outline.gdshader), desenhado
// depois, apareça só na silhueta e não por dentro do corpo. Montado por ToonLook.apply_slime.
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.25, 0.85, 0.3, 0.78);   // alfa = opacidade no miolo
uniform float rim_start : hint_range(0.0, 1.0) = 0.56;      // onde começa a borda grossa (0 = de frente)
uniform float rim_soft : hint_range(0.0, 0.2) = 0.02;
uniform float rim_shade : hint_range(0.0, 1.0) = 0.62;      // cor da borda = cor do corpo × isto
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.96;
// a malha é facetada; a borda usa a normal de um elipsoide para sair contínua em vez de face a face
uniform vec3 blob_center = vec3(0.0, 0.22, 0.0);
uniform vec3 blob_radii = vec3(0.45, 0.44, 0.45);

#include "res://assets/shaders/toon_light.gdshaderinc"

varying vec3 round_normal;

void vertex() {
	vec3 n = (VERTEX - blob_center) / (blob_radii * blob_radii);
	round_normal = MODELVIEW_NORMAL_MATRIX * normalize(n);
}

void fragment() {
	float facing = clamp(dot(normalize(round_normal), VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_start - rim_soft, rim_start + rim_soft, 1.0 - facing);
	ALBEDO = albedo.rgb * mix(1.0, rim_shade, rim);
	ALPHA = mix(albedo.a, max(albedo.a, rim_alpha), rim);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
