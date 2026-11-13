class_name Hurtbox
extends Area2D
## Área que recebe golpes. Não procura nada (mask vazia): quem detecta o acerto é a Hitbox.
## Layer definida na cena (player_hurtbox ou enemy_hurtbox).

signal hit_received(damage: int)

## Vida que recebe o dano. Sem ela, o golpe só emite hit_received.
@export var health: HealthComponent


func receive_hit(damage: int) -> void:
	hit_received.emit(damage)
	if health != null:
		health.take_damage(damage)
