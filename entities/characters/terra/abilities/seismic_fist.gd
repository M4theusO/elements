class_name SeismicFist
extends CharacterAbility
## Punho Sísmico da Terra: golpeia o chão e, após a preparação, libera uma SeismicWave
## que percorre o solo à frente. Só no chão; sair do chão durante a preparação cancela
## sem onda, sem dano e sem recarga. A recarga começa na liberação.

const WAVE_SCENE: PackedScene = preload("res://entities/characters/terra/abilities/seismic_wave.tscn")
## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001

@export_range(0.0, 2.0, 0.01, "suffix:s") var windup_time: float = 0.25
@export_range(1.0, 1000.0, 1.0, "suffix:px/s") var wave_speed: float = 240.0
@export_range(1.0, 640.0, 1.0, "suffix:px") var wave_range: float = 96.0
@export_range(0, 100, 1) var damage: int = 2
## Contada a partir da liberação da onda.
@export_range(0.0, 10.0, 0.05, "suffix:s") var cooldown_time: float = 1.5
## Distância à frente da Terra (a partir do centro) onde a onda nasce.
@export_range(0.0, 64.0, 1.0, "suffix:px") var spawn_offset: float = 12.0

var _is_casting: bool = false
var _windup_left: float = 0.0
var _cooldown_left: float = 0.0
var _direction: float = 1.0
## Onda em preparação (aviso visual). Após a liberação, a onda cuida de si mesma.
var _pending_wave: SeismicWave

@onready var _character: PlayerCharacter = get_parent() as PlayerCharacter


func _ready() -> void:
	# Atualiza antes do personagem no mesmo tick (ver MeleeAttack).
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not _is_casting:
		return
	if not _character.is_on_floor():
		_cancel()
		return
	_pending_wave.global_position = _wave_start_position()
	_windup_left -= delta
	if _windup_left <= TIME_EPSILON:
		_release()


func try_activate() -> bool:
	if _is_casting or _cooldown_left > TIME_EPSILON or _character == null or not _character.is_on_floor():
		return false
	_is_casting = true
	_windup_left = windup_time
	_direction = _character.get_facing()
	_pending_wave = WAVE_SCENE.instantiate() as SeismicWave
	# Filha do personagem, mas top_level: a posição é global e não segue a Terra após a liberação.
	_character.add_child(_pending_wave)
	_pending_wave.global_position = _wave_start_position()
	return true


func is_casting() -> bool:
	return _is_casting


func _wave_start_position() -> Vector2:
	return _character.global_position + Vector2(_direction * spawn_offset, 0.0)


func _release() -> void:
	_is_casting = false
	_cooldown_left = cooldown_time
	_pending_wave.global_position = _wave_start_position()
	_pending_wave.launch(_direction, wave_speed, wave_range, damage, _character.global_position.x)
	_pending_wave = null


func _cancel() -> void:
	_is_casting = false
	_pending_wave.queue_free()
	_pending_wave = null
