extends Node2D
## Cena persistente do jogo: carrega a sala atual em RoomSlot, posiciona a Terra (instância
## única, nunca recriada nem trocada de pai) numa entrada e aplica os limites da câmera.
## Por enquanto carrega só a sala inicial; as transições entre salas virão depois.

## Sala carregada ao iniciar.
@export_file("*.tscn") var start_room: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
## Entrada (Marker2D em Entrances) onde a Terra começa.
@export var start_entrance: StringName = &"start"

var _room: Room

@onready var _room_slot: Node2D = $RoomSlot
@onready var _terra: PlayerCharacter = $Terra
@onready var _camera: Camera2D = $Terra/Camera2D


func _ready() -> void:
	load_room(start_room, start_entrance)


func get_room() -> Room:
	return _room


func get_terra() -> PlayerCharacter:
	return _terra


## Carrega a sala, põe a Terra parada na entrada e aplica os limites da câmera.
## Em caso de erro (cena inválida ou entrada inexistente) mantém o estado atual e retorna false.
func load_room(room_path: String, entrance_id: StringName) -> bool:
	var scene: PackedScene = load(room_path) as PackedScene
	if scene == null:
		push_error("Game: sala '%s' não encontrada." % room_path)
		return false
	var room: Room = scene.instantiate() as Room
	if room == null:
		push_error("Game: '%s' não é uma Room." % room_path)
		return false
	if not room.has_entrance(entrance_id):
		push_error("Game: a sala '%s' não tem a entrada '%s'." % [room_path, entrance_id])
		room.free()
		return false
	if _room != null:
		_room_slot.remove_child(_room)
		_room.queue_free()
	_room = room
	_room_slot.add_child(room)
	_terra.global_position = room.get_entrance(entrance_id).global_position
	_terra.velocity = Vector2.ZERO
	_apply_camera_bounds(room.get_camera_bounds())
	return true


func _apply_camera_bounds(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()
