class_name Enemy
extends CharacterBody2D
## Base mínima dos inimigos: liga HealthComponent e Hurtbox, pisca ao receber dano
## e some ao morrer. Sem IA nem estados; cada inimigo cuida do próprio comportamento.
## Oferece helpers genéricos (gravidade, lado, borda, linha de visão, animação) que cada
## inimigo usa se quiser; nenhum deles roda sozinho.
## A cena precisa dos nós Visuals (Node2D, olhando para a direita), HealthComponent e Hurtbox.
## Opcionais: CollisionShape2D com RectangleShape2D (largura usada no raio de borda) e
## Visuals/AnimatedSprite2D (helpers de animação).

## Modulate acima de 1 clareia o visual, quase branco no instante do acerto.
const FLASH_COLOR: Color = Color(2.0, 2.0, 2.0)
const FLASH_DURATION: float = 0.1
## Raio de borda: começa um pouco acima dos pés e procura chão um pouco abaixo deles.
const EDGE_RAY_RISE: float = 4.0
const EDGE_RAY_DEPTH: float = 8.0

var _flash_tween: Tween
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
## Metade da largura do corpo (0 se o corpo não for retangular).
var _half_width: float = 0.0

@onready var _visuals: CanvasItem = $Visuals
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visuals/AnimatedSprite2D") as AnimatedSprite2D


func _ready() -> void:
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	var body: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is RectangleShape2D:
		_half_width = (body.shape as RectangleShape2D).size.x / 2.0


func is_dead() -> bool:
	return _health.is_dead()


## Lado para onde olha: 1.0 (direita) ou -1.0 (esquerda). O lado é a escala horizontal de Visuals.
func get_facing() -> float:
	return (_visuals as Node2D).scale.x


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


func _set_facing(direction: float) -> void:
	(_visuals as Node2D).scale.x = direction


## Gravidade padrão do projeto, limitada a max_fall_speed. Não faz nada no chão.
func _apply_gravity(delta: float, max_fall_speed: float) -> void:
	if is_on_floor():
		return
	velocity.y = minf(velocity.y + _gravity * delta, max_fall_speed)


## Existe chão logo depois da borda frontal, considerando o passo do tick?
## ground_mask: layers que contam como chão.
func _has_ground_ahead(direction: float, step: float, ground_mask: int) -> bool:
	var x: float = global_position.x + direction * (_half_width + step)
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		Vector2(x, global_position.y - EDGE_RAY_RISE), Vector2(x, global_position.y + EDGE_RAY_DEPTH), ground_mask)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Raio livre entre os olhos (eye_height acima dos pés) e o ponto mirado no alvo
## (target_height acima da origem dele)? sight_mask: layers que bloqueiam a visão.
func _has_line_of_sight(target: Node2D, eye_height: float, target_height: float, sight_mask: int) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0.0, -eye_height), target.global_position + Vector2(0.0, -target_height), sight_mask)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _has_animation(anim: StringName) -> bool:
	return _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


## Toca a animação (ignorada se não existir). restart = recomeça do quadro 0 mesmo se já for a atual.
## speed_scale é aplicado a cada chamada (1.0 = fps original do SpriteFrames).
func _play(anim: StringName, restart: bool = false, speed_scale: float = 1.0) -> void:
	if not _has_animation(anim):
		return
	_sprite.speed_scale = speed_scale
	if restart or _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)
		if restart:
			_sprite.set_frame_and_progress(0, 0.0)
