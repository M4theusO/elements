class_name Room
extends Node2D
## Base das salas jogáveis. A sala não contém a Terra: quem a carrega (Game) posiciona a
## personagem numa entrada e aplica os limites da câmera.
##
## Estrutura esperada (nem todos precisam ter filhos):
##   Background (fundo com parallax), Terrain (TileMapLayer), Props, Enemies,
##   Entrances (Marker2D, um por entrada; o nome é o identificador), Exits.
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


func _find_entrance(id: StringName) -> Marker2D:
	# Consulta direta (sem @onready): Game valida a entrada antes de a sala entrar na árvore.
	var entrances: Node = get_node_or_null(^"Entrances")
	if entrances == null or id.is_empty():
		return null
	return entrances.get_node_or_null(NodePath(String(id))) as Marker2D
