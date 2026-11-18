extends Node2D
## Cena persistente do jogo: carrega a sala atual em RoomSlot, posiciona a Terra (instância
## única, nunca recriada nem trocada de pai) numa entrada e aplica os limites da câmera.
## As saídas das salas (RoomExit) pedem a troca; a Game valida o destino e faz a transição
## com fade, sem recriar a Terra (vida, componentes e recargas continuam os mesmos).
## Lembra, só em memória e só nesta sessão, os inimigos persistentes já derrotados de cada sala:
## eles não voltam quando a sala é recarregada; os vivos voltam inteiros, no ponto de origem.
## Cada derrota guarda o escopo do inimigo (Room.get_enemy_persistence_scope()): uma nova
## tentativa (start_new_attempt()) esquece as derrotas "attempt" de todas as salas e mantém
## as "permanent".

signal room_changed(room: Room)

## Duração de cada metade do fade (escurecer e clarear).
const FADE_TIME: float = 0.15

## Sala carregada ao iniciar.
@export_file("*.tscn") var start_room: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
## Entrada (Marker2D em Entrances) onde a Terra começa.
@export var start_entrance: StringName = &"start"

var _room: Room
var _room_path: String = ""
var _transitioning: bool = false
## Inimigos derrotados: { caminho da sala: { persistent_id: escopo (Room.SCOPE_*) } }.
## Registro único da Game, para os dois escopos; some com a Game (sem save).
var _defeated_enemies: Dictionary[String, Dictionary] = {}
## Número da tentativa atual (a primeira é 1).
var _attempt: int = 1

@onready var _room_slot: Node2D = $RoomSlot
@onready var _terra: PlayerCharacter = $Terra
@onready var _camera: Camera2D = $Terra/Camera2D
@onready var _fade: ColorRect = $Fade/ColorRect


func _ready() -> void:
	_fade.modulate.a = 0.0
	load_room(start_room, start_entrance)


func get_room() -> Room:
	return _room


func get_room_path() -> String:
	return _room_path


func get_terra() -> PlayerCharacter:
	return _terra


func is_transitioning() -> bool:
	return _transitioning


func is_enemy_defeated(room_path: String, enemy_id: StringName) -> bool:
	return _defeated_enemies.has(room_path) and _defeated_enemies[room_path].has(enemy_id)


## Identificadores dos inimigos derrotados na sala (cópia, em ordem de registro).
func get_defeated_enemies(room_path: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if _defeated_enemies.has(room_path):
		for id: StringName in _defeated_enemies[room_path]:
			result.append(id)
	return result


## Escopo registrado para a derrota (Room.SCOPE_ATTEMPT ou SCOPE_PERMANENT), ou &"" se o
## inimigo não estiver derrotado.
func get_defeated_enemy_scope(room_path: String, enemy_id: StringName) -> StringName:
	if not is_enemy_defeated(room_path, enemy_id):
		return &""
	return _defeated_enemies[room_path][enemy_id]


func get_attempt() -> int:
	return _attempt


## Começa uma nova tentativa: esquece as derrotas de escopo attempt de TODAS as salas (os
## inimigos comuns voltam na próxima vez que cada sala for carregada) e mantém as permanent.
## Não recarrega a sala atual nem mexe nos inimigos já carregados; quem reinicia a sala é o
## fluxo de renascimento. Retorna quantas derrotas foram esquecidas.
func start_new_attempt() -> int:
	var removed: int = 0
	for room_path: String in _defeated_enemies.keys():
		var defeated: Dictionary = _defeated_enemies[room_path]
		for enemy_id: StringName in defeated.keys():
			if defeated[enemy_id] != Room.SCOPE_PERMANENT:
				defeated.erase(enemy_id)
				removed += 1
		if defeated.is_empty():
			_defeated_enemies.erase(room_path)
	_attempt += 1
	return removed


## Carrega a sala na hora (sem fade), põe a Terra parada na entrada e aplica os limites da
## câmera. Em caso de erro (cena inválida ou entrada inexistente) mantém o estado e retorna false.
func load_room(room_path: String, entrance_id: StringName) -> bool:
	var room: Room = _instantiate_room(room_path, entrance_id)
	if room == null:
		return false
	_swap_room(room, room_path, entrance_id)
	return true


## Pede a troca de sala com fade. Ignorada durante outra transição ou com a Terra morta.
## O destino é validado antes de qualquer mudança: se falhar, a sala atual e o controle da
## Terra continuam como estavam. Retorna se a transição começou.
func request_transition(room_path: String, entrance_id: StringName) -> bool:
	if _transitioning or _terra.get_health().is_dead():
		return false
	var room: Room = _instantiate_room(room_path, entrance_id)
	if room == null:
		return false
	_transitioning = true
	# Adiado: o pedido chega no meio do passo de física (body_entered), quando não se pode
	# tirar corpos do espaço físico.
	_run_transition.call_deferred(room, room_path, entrance_id)
	return true


func _run_transition(room: Room, room_path: String, entrance_id: StringName) -> void:
	# Sem controle durante a troca: nada de golpe, onda ou pulo atravessando a porta.
	_terra.interrupt_actions()
	_terra.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade_to(1.0)
	_swap_room(room, room_path, entrance_id)
	await _fade_to(0.0)
	_terra.process_mode = Node.PROCESS_MODE_INHERIT
	_transitioning = false


## Carrega e confere a sala sem tocar na atual. Retorna null (com erro no console) se falhar.
func _instantiate_room(room_path: String, entrance_id: StringName) -> Room:
	if room_path.is_empty() or not ResourceLoader.exists(room_path):
		push_error("Game: sala '%s' não encontrada." % room_path)
		return null
	var scene: PackedScene = load(room_path) as PackedScene
	var node: Node = scene.instantiate() if scene != null else null
	var room: Room = node as Room
	if room == null:
		push_error("Game: '%s' não é uma Room." % room_path)
		if node != null:
			node.free()
		return null
	if not room.has_entrance(entrance_id):
		push_error("Game: a sala '%s' não tem a entrada '%s'." % [room_path, entrance_id])
		room.free()
		return null
	return room


func _swap_room(room: Room, room_path: String, entrance_id: StringName) -> void:
	if _room != null:
		_room_slot.remove_child(_room)
		_room.queue_free()
	_room = room
	_room_path = room_path
	_apply_enemy_persistence(room, room_path)
	_room_slot.add_child(room)
	for room_exit: RoomExit in room.get_exits():
		room_exit.transition_requested.connect(request_transition)
	_terra.global_position = room.get_entrance(entrance_id).global_position
	_terra.velocity = Vector2.ZERO
	_terra.set_facing(room.get_entrance_facing(entrance_id))
	_apply_camera_bounds(room.get_camera_bounds())
	room_changed.emit(room)


## Antes de a sala entrar na árvore: libera os inimigos já derrotados (nem chegam ao _ready) e
## liga a morte dos vivos ao registro. A ligação leva o caminho da sala, então uma morte durante
## o fade de saída fica na sala certa; morre com o inimigo (sem sinais acumulados entre visitas).
func _apply_enemy_persistence(room: Room, room_path: String) -> void:
	var enemies: Dictionary[StringName, Enemy] = room.get_persistent_enemies()
	for id: StringName in enemies:
		var enemy: Enemy = enemies[id]
		if is_enemy_defeated(room_path, id):
			enemy.get_parent().remove_child(enemy)
			enemy.free()
			continue
		var health: HealthComponent = enemy.get_node_or_null(^"HealthComponent") as HealthComponent
		if health == null:
			push_error("Game: inimigo '%s' (%s) sem HealthComponent; não será lembrado." % [id, room_path])
			continue
		var scope: StringName = room.get_enemy_persistence_scope(enemy)
		health.died.connect(_on_persistent_enemy_died.bind(room_path, id, scope), CONNECT_ONE_SHOT)


## Registra na hora da morte (antes da animação e do queue_free).
func _on_persistent_enemy_died(room_path: String, enemy_id: StringName, scope: StringName) -> void:
	if not _defeated_enemies.has(room_path):
		_defeated_enemies[room_path] = {}
	_defeated_enemies[room_path][enemy_id] = scope


func _apply_camera_bounds(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()
	_camera.force_update_scroll()


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
	_fade.visible = alpha > 0.0
