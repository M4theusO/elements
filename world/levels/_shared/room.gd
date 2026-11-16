class_name Room
extends Node2D
## Base das salas jogáveis. A sala não contém a Terra: quem a carrega (Game) posiciona a
## personagem numa entrada e aplica os limites da câmera.
##
## Estrutura esperada (nem todos precisam ter filhos):
##   Background (fundo com parallax), Terrain (TileMapLayer), Props, Enemies,
##   Entrances (Marker2D, um por entrada; o nome é o identificador), Exits (RoomExit).
## As entradas marcam a posição dos pés da Terra.

## Metadata da instância do inimigo com o identificador persistente (ver get_persistent_enemies()).
const PERSISTENT_ID_META: StringName = &"persistent_id"

## Área visível da sala em pixels (limites da câmera). Múltiplos de 16, pelo menos 640x368.
@export var camera_bounds: Rect2i = Rect2i(0, 0, 640, 368)


func get_camera_bounds() -> Rect2i:
	return camera_bounds


func has_entrance(id: StringName) -> bool:
	return _find_entrance(id) != null


## Retorna a entrada pedida, ou null (com erro no console) se ela não existir.
func get_entrance(id: StringName) -> Marker2D:
	var entrance: Marker2D = _find_entrance(id)
	if entrance == null:
		push_error("Room '%s': entrada '%s' não encontrada." % [name, id])
	return entrance


## Lado para onde a Terra olha ao chegar por uma entrada: para dentro da sala (para o centro
## dos limites da câmera). 1 = direita, -1 = esquerda.
func get_entrance_facing(id: StringName) -> float:
	var entrance: Marker2D = _find_entrance(id)
	if entrance == null:
		return 1.0
	return -1.0 if entrance.position.x > camera_bounds.get_center().x else 1.0


func get_exits() -> Array[RoomExit]:
	var result: Array[RoomExit] = []
	var exits: Node = get_node_or_null(^"Exits")
	if exits != null:
		for child: Node in exits.get_children():
			if child is RoomExit:
				result.append(child as RoomExit)
	return result


## Inimigos persistentes (filhos diretos de Enemies), por identificador. O identificador é o
## metadata PERSISTENT_ID_META da instância (StringName ou String, não vazio, único na sala),
## independente do nome do nó. Inimigos sem identificador válido ou com identificador repetido
## ficam de fora (com erro no console): continuam no jogo, mas renascem sempre com a sala.
func get_persistent_enemies() -> Dictionary[StringName, Enemy]:
	var result: Dictionary[StringName, Enemy] = {}
	var duplicated: Dictionary[StringName, bool] = {}
	var enemies: Node = get_node_or_null(^"Enemies")
	if enemies == null:
		return result
	for child: Node in enemies.get_children():
		if not child is Enemy:
			continue
		# has_meta antes: get_meta com padrão null ainda acusa erro de chave ausente.
		var value: Variant = child.get_meta(PERSISTENT_ID_META) if child.has_meta(PERSISTENT_ID_META) else null
		var id: StringName = StringName(value) if value is StringName or value is String else &""
		if id.is_empty():
			push_error("Room '%s': inimigo '%s' sem identificador persistente (metadata '%s'); não será lembrado." % [name, child.name, PERSISTENT_ID_META])
			continue
		if result.has(id) or duplicated.has(id):
			push_error("Room '%s': identificador persistente '%s' repetido (inimigo '%s'); nenhum inimigo com ele será lembrado." % [name, id, child.name])
			result.erase(id)
			duplicated[id] = true
			continue
		result[id] = child as Enemy
	return result


func _find_entrance(id: StringName) -> Marker2D:
	# Consulta direta (sem @onready): Game valida a entrada antes de a sala entrar na árvore.
	var entrances: Node = get_node_or_null(^"Entrances")
	if entrances == null or id.is_empty():
		return null
	return entrances.get_node_or_null(NodePath(String(id))) as Marker2D
