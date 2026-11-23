shader_type spatial;
// Explosão: uma baforada da nuvem pintada (nuvem_folha.png: 4x4 quadros da mesma nuvem, de bola de fogo branca a
// gomos cinzentos que se desfazem), num quad virado para a câmera. A pintura só tem tons: o branco é o aceso, o
// cinza médio e o escuro são a luz e a sombra da fumaça. A cor entra aqui:
//   heat 1 -> 0   de fogo (sombra na cor do corpo, aceso na cor quente) para fumaça (dois tons)
//   glow          as rachas de brasa (rachas_brasa.png) acesas por dentro da fumaça: a marca do efeito
// `frame` é inteiro de propósito (sem misturar quadros): a nuvem anda em passos, como desenho animado.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform sampler2D cracks : source_color, filter_linear_mipmap, repeat_enable;

instance uniform float frame = 0.0;
instance uniform float roll = 0.0;
instance uniform float flip = 0.0;
instance uniform float seed = 0.0;
instance uniform vec3 hot = vec3(1.0, 0.95, 0.7);
instance uniform vec3 body = vec3(1.0, 0.55, 0.1);
instance uniform vec3 smoke_a = vec3(0.35, 0.16, 0.14);
instance uniform vec3 smoke_b = vec3(0.12, 0.04, 0.05);
instance uniform vec3 ember = vec3(1.0, 0.5, 0.1);
instance uniform float heat = 1.0;
instance uniform float glow = 0.0;
instance uniform float intensity = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float c = cos(roll);
	float sn = sin(roll);
	vec3 r0 = INV_VIEW_MATRIX[0].xyz;
	vec3 u0 = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + ((r0 * c + u0 * sn) * VERTEX.x + (u0 * c - r0 * sn) * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	float f = floor(frame);
	vec2 cell = vec2(mod(f, 4.0), floor(f / 4.0));
	float g = texture(sheet, (cell + clamp(uv, 0.006, 0.994)) * 0.25).r;
	float lit = smoothstep(0.75, 0.9, g);
	float midtone = smoothstep(0.42, 0.56, g);
	vec3 smoke = mix(smoke_b, smoke_a, midtone);
	vec3 cool = mix(smoke, smoke_a * 1.5, lit);
	// fogo: o miolo da bola na cor quente, as bordas e a sombra na cor do corpo
	float mid_ball = 1.0 - smoothstep(0.12, 0.42, length(uv - 0.5));
	vec3 fire = mix(body * mix(0.75, 1.15, lit), hot, lit * mid_ball);
	vec3 col = mix(cool, fire, heat);
	float c = texture(cracks, uv * 1.25 + vec2(seed, seed * 1.7)).r;
	col += ember * smoothstep(0.25, 0.8, c) * glow * 1.7 * (1.0 - lit * heat);
	ALBEDO = col;
	ALPHA = smoothstep(0.05, 0.16, g) * intensity;
}
