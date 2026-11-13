extends CharacterBody2D
## Boneco de treino para validar o combate: tem vida e Hurtbox, pisca ao ser atingido
## e some ao morrer. Sem movimento, IA ou ataques.

## Modulate acima de 1 clareia o Polygon2D, quase branco no instante do acerto.
const FLASH_COLOR: Color = Color(2.0, 2.0, 2.0)
const FLASH_DURATION: float = 0.1

var _flash_tween: Tween

@onready var _visuals: Polygon2D = $Visuals
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)


func _on_damaged(_amount: int) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_visuals.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visuals, "modulate", Color.WHITE, FLASH_DURATION)


func _on_died() -> void:
	# Para de receber golpes imediatamente e some depois do último piscar.
	_hurtbox.set_deferred("monitorable", false)
	_flash_tween.tween_callback(queue_free)
