shader_type spatial;
// Runas e veios dos arcos míticos (superfícies "bw_<id>_rune" do GLB, WeaponModel): a cor de base acesa com pulsos
// de energia que correm do punho para as pontas (|z| do modelo = distância do centro do arco) e um brilho que respira.
render_mode unshaded, cull_back;

uniform vec4 base_color : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.9, 0.8, 1.0, 1.0);
uniform float speed = 0.55;      // pulsos por segundo
uniform float spacing = 0.22;    // metros entre pulsos
uniform float strength = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float d = length(local_pos.yz * vec2(0.6, 1.0));
	float w = fract(d / spacing - TIME * speed);
	float pulse = pow(smoothstep(0.55, 1.0, w), 3.0) * (1.0 - smoothstep(0.97, 1.0, w));
	float breathe = 0.85 + 0.15 * sin(TIME * 2.3 + d * 9.0);
	ALBEDO = mix(base_color.rgb * breathe, hot_color.rgb * 1.35, pulse * strength);
}
