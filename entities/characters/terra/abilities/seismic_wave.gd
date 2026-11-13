class_name SeismicWave
extends Hitbox
## Onda do Punho Sísmico: uma Hitbox que percorre o chão depois de liberada.
## Usa top_level (definido na cena) para ficar no espaço do mundo, independente da Terra.
## Origem da cena = base da onda, na altura dos pés.
## Antes de launch() é apenas o aviso visual da preparação (não causa dano).
## Uma única ativação por onda: cada Hurtbox é atingida no máximo uma vez.

## Altura (acima da base) do raio que procura paredes à frente.
const WALL_RAY_HEIGHT: float = 6.0
## Extensão vertical do raio que procura chão sob a próxima posição.
const GROUND_RAY_REACH: float = 4.0

## Layers que bloqueiam a onda como parede (configurado na cena).
@export_flags_2d_physics var wall_mask: int = 0
## Layers que contam como chão para a onda continuar (configurado na cena).
@export_flags_2d_physics var ground_mask: int = 0

var _launched: bool = false
var _direction: float = 1.0
var _speed: float = 0.0
var _max_range: float = 0.0
var _traveled: float = 0.0
## Borda frontal já verificada; o próximo raio de parede parte dela.
var _checked_front_x: float = 0.0
var _half_width: float = 0.0


func _ready() -> void:
	super()
	for child: Node in get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			_half_width = (shape_node.shape as RectangleShape2D).size.x / 2.0
	set_debug_phase(DebugPhase.WINDUP)


func _physics_process(delta: float) -> void:
	# Primeiro aplica o dano das sobreposições da posição atual.
	super(delta)
	if not _launched:
		return
	if _traveled >= _max_range:
		_finish()
		return
	var step: float = minf(_speed * delta, _max_range - _traveled)
	var next_position: Vector2 = global_position + Vector2(_direction * step, 0.0)
	if _is_blocked(next_position):
		_finish()
		return
	global_position = next_position
	_traveled += step
	_checked_front_x = next_position.x + _direction * _half_width


## Libera a onda. origin_x: centro de quem a criou (fora de paredes), usado como
## início do primeiro raio para a onda não nascer dentro de uma parede.
func launch(direction: float, speed: float, max_range: float, wave_damage: int, origin_x: float) -> void:
	_direction = signf(direction)
	_speed = speed
	_max_range = max_range
	damage = wave_damage
	_traveled = 0.0
	_checked_front_x = origin_x
	_launched = true
	activate()


func is_launched() -> bool:
	return _launched


func get_traveled_distance() -> float:
	return _traveled


## Verifica a posição futura: parede entre a borda já verificada e a nova borda frontal,
## ou ausência de chão sob o novo centro (buraco/borda).
func _is_blocked(next_position: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var wall_y: float = next_position.y - WALL_RAY_HEIGHT
	var front_x: float = next_position.x + _direction * _half_width
	var wall_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		Vector2(_checked_front_x, wall_y), Vector2(front_x, wall_y), wall_mask)
	if not space.intersect_ray(wall_query).is_empty():
		return true
	var ground_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		next_position + Vector2(0.0, -GROUND_RAY_REACH), next_position + Vector2(0.0, GROUND_RAY_REACH), ground_mask)
	return space.intersect_ray(ground_query).is_empty()


func _finish() -> void:
	_launched = false
	deactivate()
	queue_free()
