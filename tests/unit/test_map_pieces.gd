extends RefCounted
## Peças das cenas de mapa: altura no relevo (follow_ground), colisão padrão por modelo e listas do Inspector.
## Os scripts das peças carregam aqui sem autoload (se citassem um, este arquivo nem compilaria).


func test_ground_y_follows_relief() -> void:
	var hill := func(_x: float, _z: float) -> float: return 3.0
	T.eq(MapPreview.ground_y(true, 0.5, hill, 0.0, 0.0), 3.5, "seguindo o relevo: chão + distância")
	T.eq(MapPreview.ground_y(false, 2.0, hill, 0.0, 0.0), 2.0, "sem seguir: altura absoluta")


func test_ground_y_without_ground() -> void:
	var broken := func(_x: float, _z: float) -> float: return NAN
	T.eq(MapPreview.ground_y(true, 0.5, broken, 9999.0, 9999.0), 0.5, "chão inválido (fora do mapa): fica na distância")
	T.eq(MapPreview.ground_y(true, 0.5, Callable(), 0.0, 0.0), 0.5, "sem chão (servidor/teste): fica na distância")


func test_default_shapes() -> void:
	T.eq(MapProp.DEFAULT_SHAPE["fence"], [1, Vector3(2.1, 1.0, 0.25)], "cerca: caixa")
	T.eq(MapProp.DEFAULT_SHAPE["tree_oak"], [2, Vector3(0.4, 3, 0)], "carvalho: cilindro do tronco")
	T.eq(MapProp.DEFAULT_SHAPE["lamp"], [2, Vector3(0.12, 3.7, 0)], "lampião: cilindro fino")
	for m in MapProp.MODELS:
		T.ok(ResourceLoader.exists(MapProp.model_path(m)), "modelo %s existe" % m)


func test_decor_kinds() -> void:
	for k in ["xmas_tree", "snowman", "sleigh", "candy_cane", "gifts", "light_string", "lamp_garland", "wreath",
			"wagon", "scarecrow", "crops", "label", "forge_fire"]:
		T.ok(k in MapDecor.KINDS, "enfeite %s na lista" % k)


## Trocar o modelo põe a colisão padrão só quando a pessoa troca no editor; ao carregar a cena (nó ainda não
## pronto), a colisão salva fica como está (senão as árvores sem colisão ganhariam uma ao salvar).
func test_default_shape_only_on_interactive_change() -> void:
	T.ok(MapProp.applies_default_shape(true, true, true), "troca no editor com a cena aberta: põe a colisão padrão")
	T.ok(not MapProp.applies_default_shape(true, true, false), "carregando a cena: não mexe na colisão salva")
	T.ok(not MapProp.applies_default_shape(true, false, true), "no jogo: nunca")
	T.ok(not MapProp.applies_default_shape(false, true, true), "mesmo modelo: nada")
