shader_type spatial;
// Égide Cristalina: um anel giratório (fino, tracejado, com marcas) desenhado num quadrado no chão.
// Quem gira é o nó (AegisRings); o shader só desenha. Aditivo: o preto some.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float radius = 0.94;      // raio do anel no quadrado (0..1)
uniform float width = 0.012;      // espessura do traço
uniform float dashes = 12.0;      // quantos traços na volta
uniform float dash_fill = 0.72;   // fração de cada traço desenhada
uniform float ticks = 36.0;       // marcas curtas para fora
instance uniform float fade = 1.0;
instance uniform float intensity = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float th = atan(p.y, p.x) / TAU + 0.5;
	float dash = step(fract(th * dashes), dash_fill);
	float d = abs(r - radius) - width;
	float fw = min(fwidth(d), 0.05) + 0.0001;
	float ring = (1.0 - smoothstep(-fw, fw, d)) * dash;
	// marcas: traços curtos para fora do anel
	float tk = abs(fract(th * ticks) - 0.5) * TAU * r / ticks;   // distância lateral ao centro da marca (aprox.)
	float tick = (1.0 - smoothstep(0.004, 0.004 + fw, tk)) * step(radius + width, r) * step(r, radius + 0.05);
	float halo = exp(-pow((r - radius) * 40.0, 2.0)) * 0.35;
	ALBEDO = color.rgb * (ring * 1.7 + tick * 1.2 + halo) * fade * intensity;
	ALPHA = 1.0;
}
