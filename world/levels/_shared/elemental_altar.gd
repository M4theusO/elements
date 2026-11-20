class_name ElementalAltar
extends Node2D
## Altar Elemental: checkpoint de uma sala. Guarda só a própria identidade (checkpoint_id, único
## na sala), o estado mostrado (ativado / checkpoint atual) e o ponto de renascimento. Não
## conhece a Terra nem a Game: quem registra os checkpoints (Game) liga o sinal activated,
## decide se a ativação vale e devolve o estado com apply_state().
##
## Estrutura: Visuals (Node2D, arte e animação futuras) e SpawnPoint (Marker2D, pés da Terra ao
## renascer). Na sala, fica como filho direto de Checkpoints (ver Room.get_checkpoints()).

## Pedido de ativação (interação), inclusive repetido. first_time = o altar ainda não estava
## ativado. Não muda o estado sozinho: quem registra responde com apply_state().
signal activated(altar: ElementalAltar, first_time: bool)
## O estado mudou (por apply_state()). Para a arte e as animações futuras.
signal state_changed(is_activated: bool, is_current: bool)

enum Facing { LEFT = -1, RIGHT = 1 }

## Identificador estável, não vazio e único na sala (independe do nome do nó).
@export var checkpoint_id: StringName
## Lado para onde a Terra olha ao renascer aqui.
@export var spawn_facing: Facing = Facing.RIGHT

var _activated: bool = false
var _current: bool = false


## Pede a ativação (a interação da Terra chamará isto). Emite activated; o estado só muda
## quando quem registra aceita e chama apply_state().
func activate() -> void:
	activated.emit(self, not _activated)


## Já foi ativado alguma vez (nesta sessão).
func is_activated() -> bool:
	return _activated


## É o checkpoint de renascimento atual.
func is_current() -> bool:
	return _current


## Aplica o estado vindo do registro, sem emitir activated. Atual implica ativado.
## Emite state_changed só se algo mudar.
func apply_state(activated_state: bool, current_state: bool) -> void:
	var new_activated: bool = activated_state or current_state
	if new_activated == _activated and current_state == _current:
		return
	_activated = new_activated
	_current = current_state
	state_changed.emit(_activated, _current)


## Posição global dos pés da Terra ao renascer (SpawnPoint; sem ele, a do próprio altar).
## Com a sala dentro da árvore.
func get_spawn_position() -> Vector2:
	var spawn: Marker2D = get_node_or_null(^"SpawnPoint") as Marker2D
	if spawn == null:
		push_error("ElementalAltar '%s': sem SpawnPoint; usando a posição do altar." % checkpoint_id)
		return global_position
	return spawn.global_position


## 1 = direita, -1 = esquerda.
func get_spawn_facing() -> float:
	return float(spawn_facing)


## Sala à qual o altar pertence (primeiro ancestral Room), ou null fora de uma sala.
func get_room() -> Room:
	var node: Node = get_parent()
	while node != null:
		if node is Room:
			return node as Room
		node = node.get_parent()
	return null


## Caminho da cena da sala (o identificador de sala usado pela Game), ou "" fora de uma sala.
func get_room_path() -> String:
	var room: Room = get_room()
	return room.scene_file_path if room != null else ""
