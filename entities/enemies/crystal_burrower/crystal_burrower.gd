class_name CrystalBurrower
extends Enemy
## Escavador de Cristal: criatura territorial de carapaça rochosa. Alterna pausas (IDLE) e
## patrulha lenta (PATROL) dentro do território; ao chegar a um limite (fim do território,
## parede ou borda) para, espera a pausa e só então vira. Vê a Terra apenas à frente
## (DetectionArea dentro de Visuals, que vira com ele) e com linha de visão livre.
## Etapa atual: a detecção só é registrada (get_detected_target()); ainda não inicia ataques.
## CHARGE, DASH e STUNNED existem no enum, mas ainda não têm comportamento.

enum State { IDLE, PATROL, CHARGE, DASH, STUNNED, DEAD }

## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001
## Folga de posição para considerar o limite do território atingido.
const POSITION_EPSILON: float = 0.01

@export_group("Patrulha")
@export_range(0.0, 200.0, 1.0, "suffix:px/s") var patrol_speed: float = 25.0
## Distância máxima, para cada lado, do ponto onde o inimigo nasceu.
@export_range(0.0, 512.0, 1.0, "suffix:px") var patrol_distance: float = 64.0
## Pausa parada em IDLE (no início e a cada limite da patrulha).
@export_range(0.0, 10.0, 0.05, "suffix:s") var idle_time: float = 1.0

@export_group("Detecção")
## Alcance e altura da visão: forma da DetectionArea na cena (128x40 px à frente).
## Altura dos olhos (acima dos pés) e do ponto mirado no alvo para a linha de visão.
@export_range(0.0, 64.0, 1.0, "suffix:px") var eye_height: float = 10.0
@export_range(0.0, 64.0, 1.0, "suffix:px") var target_sight_height: float = 16.0

@export_group("Física")
@export_range(0.0, 2000.0, 1.0, "suffix:px/s") var max_fall_speed: float = 360.0
## Layers que contam como chão à frente (configurado na cena).
@export_flags_2d_physics var ground_mask: int = 0
## Layers que bloqueiam a visão (configurado na cena).
@export_flags_2d_physics var sight_mask: int = 0

var _state: State = State.IDLE
var _idle_left: float = 0.0
## Vira ao fim da pausa (a pausa começou num limite da patrulha).
var _turn_after_idle: bool = false
var _patrol_origin_x: float = 0.0
var _detected_target: Node2D

@onready var _detection_area: Area2D = $Visuals/DetectionArea


func _ready() -> void:
	super()
	_patrol_origin_x = global_position.x
	_enter_idle(false)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta, max_fall_speed)
	match _state:
		State.IDLE:
			_update_idle(delta)
		State.PATROL:
			_update_patrol(delta)
		_:
			velocity.x = 0.0
	move_and_slide()
	# Parede à frente durante a patrulha: limite atingido.
	if _state == State.PATROL and is_on_wall() and get_wall_normal().x * get_facing() < 0.0:
		_enter_idle(true)
	_update_detection()


func get_state() -> State:
	return _state


func get_patrol_origin_x() -> float:
	return _patrol_origin_x


## Terra vista neste tick (à frente, dentro da área e com linha de visão), ou null.
## Atualizada no fim de cada tick em IDLE e PATROL.
func get_detected_target() -> Node2D:
	return _detected_target


func is_target_detected() -> bool:
	return _detected_target != null


func _on_death() -> void:
	_state = State.DEAD
	_detected_target = null
	velocity = Vector2.ZERO
	set_physics_process(false)
	_detection_area.set_deferred("monitoring", false)


func _enter_idle(turn_after: bool) -> void:
	_state = State.IDLE
	_idle_left = idle_time
	_turn_after_idle = turn_after
	velocity.x = 0.0


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	_idle_left -= delta
	if _idle_left > TIME_EPSILON:
		return
	if _turn_after_idle:
		_set_facing(-get_facing())
	_state = State.PATROL
	_update_patrol(delta)


func _update_patrol(delta: float) -> void:
	# No ar (ex.: caindo): sem deslocamento horizontal, para não sair de uma borda.
	if not is_on_floor():
		velocity.x = 0.0
		return
	var facing: float = get_facing()
	# Distância até o limite do território no sentido atual; o passo não o ultrapassa.
	var room: float = patrol_distance - (global_position.x - _patrol_origin_x) * facing
	if room <= POSITION_EPSILON:
		_enter_idle(true)
		return
	var speed: float = minf(patrol_speed, room / delta)
	if not _has_ground_ahead(facing, speed * delta, ground_mask):
		_enter_idle(true)
		return
	velocity.x = facing * speed


func _update_detection() -> void:
	_detected_target = null
	if _state != State.IDLE and _state != State.PATROL:
		return
	for body: Node2D in _detection_area.get_overlapping_bodies():
		if _has_line_of_sight(body, eye_height, target_sight_height, sight_mask):
			_detected_target = body
			return
