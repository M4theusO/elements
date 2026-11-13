class_name Hurtbox
extends Area2D
## Área que recebe golpes. Não procura nada (mask vazia): quem detecta o acerto é a Hitbox.
## Layer definida na cena (player_hurtbox ou enemy_hurtbox).
## Opcional: invulnerabilidade temporária após cada golpe aceito (invulnerability_time > 0).

signal hit_received(damage: int)

## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001

## Vida que recebe o dano. Sem ela, o golpe só emite hit_received.
@export var health: HealthComponent
## Tempo após um golpe aceito em que novos golpes são ignorados. 0 = sem invulnerabilidade.
@export_range(0.0, 5.0, 0.05, "suffix:s") var invulnerability_time: float = 0.0

var _invulnerable_left: float = 0.0


func _ready() -> void:
	# Conta antes das hitboxes no mesmo tick: a invulnerabilidade dura exatamente o tempo configurado.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


func receive_hit(damage: int) -> void:
	# Ignorado durante a invulnerabilidade (inclusive um segundo golpe no mesmo tick).
	if is_invulnerable():
		return
	hit_received.emit(damage)
	if health != null:
		health.take_damage(damage)
	_invulnerable_left = invulnerability_time


func is_invulnerable() -> bool:
	return _invulnerable_left > TIME_EPSILON


## Tempo restante de invulnerabilidade (0 quando vulnerável).
func get_invulnerability_left() -> float:
	return _invulnerable_left if is_invulnerable() else 0.0
