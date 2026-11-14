shader_type spatial;
// Marca no chão sob o personagem com buff (PlaneMesh): brilho suave, anel e traços girando.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float strength = 1.5;
uniform float ticks = 12.0;     // traços do anel interno (0 = sem traços)
uniform float spin = 0.25;      // voltas por segundo dos traços
uniform float glow = 0.35;      // brilho suave no miolo

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) / TAU + 0.5;
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2);
	// anel externo fino
	float ring = smoothstep(0.045, 0.0, abs(r - 0.86));
	// anel interno em traços, girando
	float dash = 0.0;
	if (ticks > 0.5) {
		float t = fract(ang * ticks + TIME * spin);
		dash = smoothstep(0.035, 0.0, abs(r - 0.68)) * smoothstep(0.5, 0.56, t);
	}
	// brilho que morre antes da borda
	float soft = pow(clamp(1.0 - r / 0.95, 0.0, 1.0), 1.6) * glow;
	ALBEDO = color.rgb;
	ALPHA = (ring * 0.9 + dash * 0.7 + soft) * strength * pulse * step(r, 1.0);
}
