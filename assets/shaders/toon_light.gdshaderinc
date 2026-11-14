// Luz em dois tons, compartilhada por personagens, cenário, chão e grama (docs/ESTILO_TOON.md).
// Cada luz ou acende a face por inteiro ou a deixa no tom de sombra; a sombra projetada pelo sol
// corta seco e cai no mesmo tom. Cor e intensidade continuam vindo das luzes do jogo.

// quanto da luz direta sobra na face em sombra, por canal (azulado => sombra fria)
uniform vec3 shade_tint = vec3(0.40, 0.38, 0.55);
// a face acesa recebe a luz inteira (sem o cosseno), então a luz é reduzida para não estourar as cores claras
uniform float light_gain : hint_range(0.0, 1.5) = 0.68;
uniform vec3 cast_tint = vec3(0.16, 0.16, 0.27);         // luz que sobra dentro da sombra projetada
uniform float threshold : hint_range(-1.0, 1.0) = 0.22;
uniform float softness : hint_range(0.0, 0.2) = 0.015;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;       // brilho em faixa, para metal
uniform bool toon = true;                               // falso (`--notoon`): Lambert comum

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (!toon) {
		DIFFUSE_LIGHT += max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		float lit = smoothstep(threshold - softness, threshold + softness, ndl);
		float cast = 1.0;
		float atten = ATTENUATION;
		if (LIGHT_IS_DIRECTIONAL) {
			// degrau largo: o borrão da sombra tem ruído, e um degrau estreito deixava a borda granulada
			cast = smoothstep(0.3, 0.7, ATTENUATION);
			atten = 1.0;
		}
		// sombra projetada é mais funda que a sombra de forma, para o chão não perder o contraste
		vec3 tint = mix(cast_tint, mix(shade_tint, vec3(1.0), lit), cast);
		lit *= cast;
		DIFFUSE_LIGHT += tint * LIGHT_COLOR * atten * light_gain / PI;
		if (gloss > 0.0) {
			float h = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
			SPECULAR_LIGHT += step(0.965, h) * lit * gloss * LIGHT_COLOR * atten / PI;
		}
	}
}
