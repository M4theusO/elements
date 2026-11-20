class_name ElementalAltar
extends Node2D
## Altar Elemental: checkpoint de uma sala. Guarda só a própria identidade (checkpoint_id, único
## na sala), o estado mostrado (ativado / checkpoint atual) e o ponto de renascimento. Não
## conhece a Terra nem a Game: quem registra os checkpoints (Game) liga o sinal activated,
## decide se a ativação vale e devolve o estado com apply_state().
##
## Estrutura: Visuals (Node2D, arte provisória; trocada pela definitiva sem mexer neste script),
## SpawnPoint (Marker2D, pés da Terra ao renascer), InteractionArea (Area2D) e Prompt (indicação
## "E — Interagir"). Na sala, fica como filho direto de Checkpoints (ver Room.get_checkpoints()).
##
## Interação: InteractionArea é uma zona de gatilho (sem layer, mask player, monitorable
## desligado). Com uma personagem jogável dentro dela, viva, no controle (processando) e no chão,
## um pressionamento NOVO de interact (evento sem eco) chama activate(). Nada acontece ao entrar
## na área, ao segurar o botão ou com o botão já apertado antes de entrar. Pausado (Game Over,
## reinício), o altar não recebe input.

## Pedido de ativação (interação), inclusive repetido. first_time = o altar ainda não estava
## ativado. Não muda o estado sozinho: quem registra responde com apply_state().
signal activated(altar: ElementalAltar, first_time: bool)
## O estado mudou (por apply_state()). Para a arte e as animações futuras.
signal state_changed(is_activated: bool, is_current: bool)

enum Facing { LEFT = -1, RIGHT = 1 }

## Ação do Input Map que ativa o altar.
const INTERACT_ACTION: StringName = &"interact"

## Identificador estável, não vazio e único na sala (independe do nome do nó).
@export var checkpoint_id: StringName
## Lado para onde a Terra olha ao renascer aqui.
@export var spawn_facing: Facing = Facing.RIGHT

var _activated: bool = false
var _current: bool = false
## Personagem jogável dentro da área (null fora).
var _player: PlayerCharacter

@onready var _area: Area2D = get_node_or_null(^"InteractionArea") as Area2D
@onready var _prompt: CanvasItem = get_node_or_null(^"Prompt") as CanvasItem


func _ready() -> void:
	if _area != null:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	_update_prompt()


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	# is_action_pressed sem allow_echo: só o evento do aperto (repetição do teclado ignorada).
	if not event.is_action_pressed(INTERACT_ACTION) or not can_interact():
		return
	# Um aperto ativa um altar só (e não chega a mais ninguém).
	get_viewport().set_input_as_handled()
	activate()


## Pede a ativação (a interação chama isto). Emite activated; o estado só muda quando quem
## registra aceita e chama apply_state().
func activate() -> void:
	activated.emit(self, not _activated)


## Verdadeiro se houver uma personagem jogável dentro da área (viva ou não).
func has_player_in_range() -> bool:
	return _player != null and is_instance_valid(_player)


## Interação possível agora: personagem na área, viva, no controle (processando; desligada na
## troca de sala) e no chão (a seta ↑ é interact e move_up ao mesmo tempo; no ar, não ativa).
func can_interact() -> bool:
	return has_player_in_range() and not _player.is_dead() and _player.can_process() \
		and _player.is_on_floor() and can_process()


func is_prompt_visible() -> bool:
	return _prompt != null and _prompt.visible


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


## Verdadeiro se o altar tiver o filho SpawnPoint (Marker2D) que marca o renascimento.
func has_spawn_point() -> bool:
	return get_node_or_null(^"SpawnPoint") is Marker2D


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


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		_player = body as PlayerCharacter
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_update_prompt()


## A indicação aparece só quando a interação é possível (some na morte, no Game Over, na
## transição e no ar).
func _update_prompt() -> void:
	if _prompt != null:
		_prompt.visible = can_interact()
