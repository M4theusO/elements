class_name HealthComponent
extends Node
## Pontos de vida de uma entidade. Recebe dano e avisa por signals.

## Emitido a cada dano efetivamente aplicado (amount = vida perdida).
signal damaged(amount: int)
## Emitido uma única vez, quando a vida chega a zero.
signal died

@export_range(1, 1000, 1) var max_health: int = 3

@onready var current_health: int = max_health


func is_dead() -> bool:
	return current_health <= 0


func take_damage(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	var applied: int = mini(amount, current_health)
	current_health -= applied
	damaged.emit(applied)
	if current_health == 0:
		died.emit()
