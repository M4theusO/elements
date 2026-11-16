class_name Room
extends Node2D
## Base das salas jogáveis. A sala não contém a Terra: quem a carrega (Game) posiciona a
## personagem numa entrada e aplica os limites da câmera.
##
## Estrutura esperada (nem todos precisam ter filhos):
##   Background (fundo com parallax), Terrain (TileMapLayer), Props, Enemies,
##   Entrances (Marker2D, um por entrada; o nome é o identificador), Exits (RoomExit).
## As entradas marcam a posição dos pés da Terra.

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


func _find_entrance(id: StringName) -> Marker2D:
	# Consulta direta (sem @onready): Game valida a entrada antes de a sala entrar na árvore.
	var entrances: Node = get_node_or_null(^"Entrances")
	if entrances == null or id.is_empty():
		return null
	return entrances.get_node_or_null(NodePath(String(id))) as Marker2D
