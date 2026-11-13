class_name Enemy
extends CharacterBody2D
## Base mínima dos inimigos: liga HealthComponent e Hurtbox, pisca ao receber dano
## e some ao morrer. Sem IA, gravidade ou estados; cada inimigo cuida do próprio comportamento.
## A cena precisa dos nós Visuals (CanvasItem), HealthComponent e Hurtbox.

## Modulate acima de 1 clareia o visual, quase branco no instante do acerto.
const FLASH_COLOR: Color = Color(2.0, 2.0, 2.0)
const FLASH_DURATION: float = 0.1

var _flash_tween: Tween

@onready var _visuals: CanvasItem = $Visuals
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)


func is_dead() -> bool:
	return _health.is_dead()


## Chamado uma vez, na morte, antes de o inimigo sumir. Sobrescreva para parar o comportamento.
func _on_death() -> void:
	pass


## Chamado uma vez, na morte, depois de _on_death(). Retorne true se o próprio inimigo
## cuida de sumir (ex.: ao fim da animação de morte); false = some depois do piscar.
func _play_death_animation() -> bool:
	return false


func _on_damaged(_amount: int) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_visuals.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visuals, "modulate", Color.WHITE, FLASH_DURATION)


func _on_died() -> void:
	# Para de receber golpes imediatamente; some depois do último piscar ou da animação de morte.
	_hurtbox.set_deferred("monitorable", false)
	_on_death()
	if not _play_death_animation():
		_flash_tween.tween_callback(queue_free)
