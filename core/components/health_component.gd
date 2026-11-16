class_name HealthComponent
extends Node
## Pontos de vida de uma entidade. Recebe dano, cura e avisa por signals.
## A vida fica sempre entre 0 e max_health.

## Emitido a cada dano efetivamente aplicado (amount = vida perdida).
signal damaged(amount: int)
## Emitido uma única vez por vida, quando a vida chega a zero.
signal died
## Emitido sempre que a vida atual muda (dano, cura ou restauração), para interfaces.
signal health_changed(current: int, maximum: int)

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
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()


## Recupera até amount de vida, sem passar do máximo. Ignorado com amount <= 0 ou depois da
## morte (para voltar da morte, use restore_full()). Retorna a vida efetivamente recuperada.
func heal(amount: int) -> int:
	if amount <= 0 or is_dead():
		return 0
	var applied: int = mini(amount, max_health - current_health)
	if applied > 0:
		current_health += applied
		health_changed.emit(current_health, max_health)
	return applied


## Volta à vida cheia, inclusive depois da morte (renascimento). Depois disso, chegar a zero
## de novo emite died outra vez.
func restore_full() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
