class_name AegisCrack
extends MeshInstance3D
## Égide Cristalina: rachaduras de uma placa (prefab scenes/vfx/aegis/aegis_crack.tscn), por cima do
## cristal no mesmo losango (shader aegis_crack). A placa (AegisPlate) põe uma destas como filha; o valor só
## cresce (uma rachadura não fecha) e o ponto de origem fica o do primeiro golpe que a abriu.

var amount := 0.0
var _impact_set := false


func _ready() -> void:
	if mesh == null:
		mesh = AegisPlate.diamond_mesh()
	position.z = 0.004   # um fio à frente do cristal (evita briga de profundidade)
	visible = false


## Racha até `c` (0..1). `impact_uv` = onde o golpe acertou no losango (só vale na primeira rachadura).
func set_crack(c: float, impact_uv := Vector2(0.5, 0.35), seed := 0.0) -> void:
	c = clampf(c, 0.0, 1.0)
	if c <= amount:
		return
	if not _impact_set:
		_impact_set = true
		set_instance_shader_parameter("impact", impact_uv)
		set_instance_shader_parameter("seed", seed)
	amount = c
	visible = amount > 0.0
	set_instance_shader_parameter("crack", amount)


func set_intensity(v: float) -> void:
	var m := material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("intensity", v)


func set_fade(f: float) -> void:
	set_instance_shader_parameter("fade", clampf(f, 0.0, 1.0))
