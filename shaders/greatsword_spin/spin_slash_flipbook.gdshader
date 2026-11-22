shader_type spatial;
// Ciclone de Aço: os cortes de lâmina da sprite sheet (assets/vfx/greatsword_spin/spin_slash_sheet.webp: 8 x 8 quadros,
// da esquerda para a direita e de cima para baixo, fundo preto puro #000000) com mistura ADITIVA: o preto não soma
// nada, então não precisa de canal alfa. Um shader para os dois usos:
//   anel principal (GreatswordSpinSlash.ring)  quadro pela instance uniform `frame` (fracionário: mistura com o seguinte)
//   cortes soltos (GPUParticles3D Slashes)     `particle_frames`: o quadro sai da vida da partícula (INSTANCE_CUSTOM.y,
//                                              spin_slash_particles.gdshader), de particle_range.x a particle_range.y,
//                                              e o COLOR.a da partícula apaga o corte no fim da vida
// Malha: um PlaneMesh deitado (virado para +Y), UV 0..1 = a célula inteira.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform int h_frames = 8;
uniform int v_frames = 8;
// abaixo disto (o mais claro dos canais) é fundo: corta o ruído da compressão em volta dos cortes
uniform float black_cut = 0.035;
// o mais claro passa de 1 (o glow pega nele)
uniform float hdr = 1.6;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool flip_x = false;
uniform bool particle_frames = false;
uniform vec2 particle_range = vec2(10.0, 40.0);
instance uniform float frame = 0.0;
instance uniform float intensity = 1.0;

varying float v_frame;
varying float v_alpha;

void vertex() {
	if (particle_frames) {
		v_frame = mix(particle_range.x, particle_range.y, clamp(INSTANCE_CUSTOM.y, 0.0, 1.0));
		v_alpha = COLOR.a;
	} else {
		v_frame = frame;
		v_alpha = 1.0;
	}
}

vec3 frame_rgb(float f, vec2 cuv) {
	float total = float(h_frames * v_frames);
	f = clamp(f, 0.0, total - 1.0);
	vec2 cell = vec2(mod(f, float(h_frames)), floor(f / float(h_frames)));
	// meio texel de margem para o filtro não puxar o quadro vizinho
	vec2 q = clamp(cuv, vec2(0.002), vec2(0.998));
	return texture(sheet, (cell + q) / vec2(float(h_frames), float(v_frames))).rgb;
}

void fragment() {
	vec2 cuv = UV;
	if (flip_x) {
		cuv.x = 1.0 - cuv.x;
	}
	float total = float(h_frames * v_frames);
	float f0 = floor(v_frame);
	vec3 c = mix(frame_rgb(f0, cuv), frame_rgb(min(f0 + 1.0, total - 1.0), cuv), v_frame - f0);
	float mx = max(c.r, max(c.g, c.b));
	c *= smoothstep(black_cut, black_cut + 0.08, mx);
	c *= 1.0 + (hdr - 1.0) * smoothstep(0.7, 1.0, mx);
	// some perto da borda da célula (o quadro vizinho nunca aparece como uma linha)
	float edge = smoothstep(0.0, 0.04, cuv.x) * smoothstep(1.0, 0.96, cuv.x) * smoothstep(0.0, 0.04, cuv.y) * smoothstep(1.0, 0.96, cuv.y);
	ALBEDO = c * tint * edge * intensity * v_alpha;
	ALPHA = 1.0;
}
