class_name Hurtbox
extends Area2D
## Área que recebe golpes. Não procura nada (mask vazia): quem detecta o acerto é a Hitbox.
## Layer definida na cena (player_hurtbox ou enemy_hurtbox).
## Opcional: invulnerabilidade temporária após cada golpe aceito (invulnerability_time > 0).

## Emitido a cada golpe aceito. damage = dano após _get_damage_taken (pode ser 0).
signal hit_received(damage: int)

## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001

## Vida que recebe o dano. Sem ela, o golpe só emite hit_received.
@export var health: HealthComponent
## Tempo após um golpe aceito em que novos golpes são ignorados. 0 = sem invulnerabilidade.
@export_range(0.0, 5.0, 0.05, "suffix:s") var invulnerability_time: float = 0.0

var _invulnerable_left: float = 0.0
var _last_hit_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Conta antes das hitboxes no mesmo tick: a invulnerabilidade dura exatamente o tempo configurado.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


## hit_direction: trajetória do golpe no mundo (vetor unitário, ver Hitbox.get_hit_direction());
## Vector2.ZERO = desconhecida (chamadas diretas, sem Hitbox).
func receive_hit(damage: int, hit_direction: Vector2 = Vector2.ZERO) -> void:
	# Ignorado durante a invulnerabilidade (inclusive um segundo golpe no mesmo tick).
	if is_invulnerable():
		return
	_last_hit_direction = hit_direction
	var taken: int = maxi(_get_damage_taken(damage, hit_direction), 0)
	hit_received.emit(taken)
	if health != null:
		health.take_damage(taken)
	_invulnerable_left = invulnerability_time


func is_invulnerable() -> bool:
	return _invulnerable_left > TIME_EPSILON


## Tempo restante de invulnerabilidade (0 quando vulnerável).
func get_invulnerability_left() -> float:
	return _invulnerable_left if is_invulnerable() else 0.0


## Direção do último golpe aceito (Vector2.ZERO se desconhecida ou se ainda não houve golpe).
func get_last_hit_direction() -> Vector2:
	return _last_hit_direction


## Gancho para subclasses ajustarem o dano conforme o golpe (ex.: defesa por lado).
## Chamado só para golpes aceitos; resultado negativo vira 0. Padrão: dano sem alteração.
func _get_damage_taken(damage: int, _hit_direction: Vector2) -> int:
	return damage
