shader_type spatial;
// Buraco Negro: a esfera do miolo. Preta, sem luz; só a beirada acende fina na cor quente do disco.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 rim_col = vec3(1.0, 0.55, 0.25);

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 7.0);
	ALBEDO = rim_col * f * 0.9;
}
