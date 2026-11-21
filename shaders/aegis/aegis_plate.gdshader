shader_type spatial;
// Égide Cristalina: uma placa de proteção em losango (AegisPlate), com a arte da sprite sheet:
// `plate_tex` = o losango com o escudo (quadro 15) e `cracked_tex` = o mesmo losango rachado (quadro 42),
// recortados por tools/aegis_sheet_extract.gd. O UV do losango (AegisPlate.diamond_mesh) tem o centro em
// (0,5; 0,5) e as pontas no meio de cada lado do quadrado, igual ao recorte das texturas.
// O fundo preto da sheet vira transparência pelo brilho (alpha = luminância): as bordas acesas ficam quase
// opacas e o miolo de vidro azul fica translúcido, sem esconder quem está dentro.
// A rachadura troca a arte inteira pela rachada a partir do ponto do golpe (`impact`) conforme `damage` sobe.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D plate_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float fill_alpha = 0.13;   // véu azul do miolo (o vidro)
uniform float glow = 1.5;          // multiplica o brilho da arte
instance uniform float appear = 1.0;   // 0 = escondida, 1 = formada (cresce de baixo para cima)
instance uniform float fade = 1.0;     // transparência geral (dissipar)
instance uniform float flash = 0.0;    // clarão (golpe, pulsação antes de quebrar)
instance uniform float damage = 0.0;   // 0..1: quanto desta placa já rachou
instance uniform vec2 impact = vec2(0.5, 0.35);
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = abs(p.x) + abs(p.y);           // 0 no centro, 0,5 na borda
	if (d > 0.5) {
		discard;
	}
	// cresce de baixo para cima (v = 1 embaixo), com um fio claro na frente
	float front = 1.0 - appear * 1.25;
	float vis = smoothstep(front - 0.02, front + 0.02, UV.y);
	float lead = exp(-pow((UV.y - front) * 28.0, 2.0)) * step(appear, 0.999);
	// área rachada: cresce do golpe, borda irregular
	float wob = (hash(floor(UV * 8.0) + seed) - 0.5) * 0.15;
	float reach = damage * 1.2 + wob;
	float cracked = (1.0 - smoothstep(reach - 0.08, reach, distance(UV, impact))) * step(0.001, damage);
	vec3 a = texture(plate_tex, UV).rgb;
	vec3 b = texture(cracked_tex, UV).rgb;
	vec3 c = mix(a, b, cracked);
	float lum = max(c.r, max(c.g, c.b));
	float shimmer = 0.88 + 0.12 * sin(TIME * 2.3 + seed * 6.28 + p.y * 9.0);
	float flicker = 1.0 - damage * 0.3 * (0.5 + 0.5 * sin(TIME * 21.0 + seed * 40.0));
	vec3 col = c * tint * glow * shimmer * flicker;
	col += vec3(0.55, 0.8, 1.0) * (lead * 1.5 + flash * 1.1);
	float al = smoothstep(0.08, 0.6, lum) + fill_alpha;
	al = clamp(al * flicker + lead * 0.7 + flash * 0.3, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = al * vis * fade;
}
