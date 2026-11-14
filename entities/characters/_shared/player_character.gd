class_name PlayerCharacter
extends CharacterBody2D
## Base compartilhada pelos protagonistas: movimento horizontal, gravidade, pulo, ataque básico
## e vida (HealthComponent + Hurtbox com invulnerabilidade após dano). Em 0 de vida, perde o
## controle e toca a animação death.
## Todos os parâmetros vêm de um CharacterStats; cada personagem fornece o seu.
## O golpe (dados e alcance) é configurado na cena de cada personagem, em MeleeAttack e Visuals/Hitbox.

## Nomes de animação padronizados para todos os protagonistas (definidos no SpriteFrames de cada um).
const ANIM_IDLE: StringName = &"idle"
const ANIM_WALK: StringName = &"walk"
const ANIM_JUMP: StringName = &"jump"
const ANIM_FALL: StringName = &"fall"
const ANIM_ATTACK: StringName = &"attack"
const ANIM_ABILITY: StringName = &"ability"
const ANIM_DEATH: StringName = &"death"
## Velocidade horizontal mínima (px/s) para considerar que o personagem está andando.
const WALK_SPEED_THRESHOLD: float = 1.0
## Feedback de dano (provisório): clarão no acerto e sprite piscando durante a invulnerabilidade.
const DAMAGE_FLASH_COLOR: Color = Color(2.0, 2.0, 2.0)
const DAMAGE_FLASH_DURATION: float = 0.1
const INVULNERABLE_BLINK_INTERVAL: float = 0.075
const INVULNERABLE_ALPHA: float = 0.35

@export var stats: CharacterStats
## Habilidade especial do personagem (ação "ability"). Vazia na cena base.
@export var ability: CharacterAbility

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
## Verdadeiro enquanto sobe por causa de um pulo (permite o corte do pulo variável).
var _is_jump_rising: bool = false
var _damage_flash_tween: Tween
var _is_dead: bool = false

@onready var _visuals: Node2D = $Visuals
@onready var _sprite: AnimatedSprite2D = $Visuals/AnimatedSprite2D
@onready var _melee_attack: MeleeAttack = $MeleeAttack
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _health: HealthComponent = $HealthComponent


func _ready() -> void:
	if stats == null:
		push_warning("%s: nenhum CharacterStats atribuído; usando valores padrão." % name)
		stats = CharacterStats.new()
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)


func _process(_delta: float) -> void:
	# Apenas visual: não interfere em movimento, pulo, golpe ou habilidade.
	# Morta, não pisca: a animação de morte fica sempre visível.
	var left: float = _hurtbox.get_invulnerability_left()
	var hidden_phase: bool = not _is_dead and left > 0.0 and int(left / INVULNERABLE_BLINK_INTERVAL) % 2 == 0
	_sprite.self_modulate.a = INVULNERABLE_ALPHA if hidden_phase else 1.0


func _physics_process(delta: float) -> void:
	if _is_dead:
		# Sem controle: só a gravidade e a desaceleração natural até parar.
		_apply_gravity(delta)
		_apply_horizontal_movement(0.0, delta)
		move_and_slide()
		return

	var direction: float = Input.get_axis("move_left", "move_right")

	_update_timers(delta)
	_apply_gravity(delta)
	_handle_jump()
	_apply_horizontal_movement(direction, delta)
	move_and_slide()
	_update_facing(direction)
	# Depois do facing: atacar e virar no mesmo tick golpeia para o novo lado.
	# Golpe básico e preparação da habilidade não se sobrepõem.
	if Input.is_action_just_pressed("attack") and not _is_ability_casting():
		_melee_attack.try_attack()
	if Input.is_action_just_pressed("ability") and ability != null and not _melee_attack.is_striking():
		ability.try_activate()
	_update_animation()


## Velocidade inicial do pulo (px/s, positiva) derivada da altura e do tempo até o topo.
func get_jump_velocity() -> float:
	return 2.0 * stats.jump_height / _get_time_to_apex()


## Gravidade de subida (px/s²) derivada da altura e do tempo até o topo.
func get_jump_gravity() -> float:
	var time_to_apex: float = _get_time_to_apex()
	return 2.0 * stats.jump_height / (time_to_apex * time_to_apex)


## Lado para onde o personagem olha: 1.0 (direita) ou -1.0 (esquerda).
func get_facing() -> float:
	return _visuals.scale.x


func get_health() -> HealthComponent:
	return _health


func get_hurtbox() -> Hurtbox:
	return _hurtbox


func _on_damaged(_amount: int) -> void:
	if _damage_flash_tween != null:
		_damage_flash_tween.kill()
	_visuals.modulate = DAMAGE_FLASH_COLOR
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_visuals, "modulate", Color.WHITE, DAMAGE_FLASH_DURATION)


## Sem respawn por enquanto: a personagem fica caída no último quadro de death.
func _on_died() -> void:
	_is_dead = true
	_is_jump_rising = false
	# Um golpe ou habilidade em preparação não pode causar dano depois da morte.
	_melee_attack.process_mode = Node.PROCESS_MODE_DISABLED
	_melee_attack.hitbox.deactivate()
	if ability != null:
		ability.cancel()
	_play_animation(ANIM_DEATH)


func _is_ability_casting() -> bool:
	return ability != null and ability.is_casting()


## jump_time_to_apex limitado ao mínimo do Inspector, mesmo se atribuído por código
## (evita divisão por zero ou valores negativos).
func _get_time_to_apex() -> float:
	return maxf(stats.jump_time_to_apex, CharacterStats.MIN_JUMP_TIME_TO_APEX)


func _update_timers(delta: float) -> void:
	# is_on_floor() reflete o último move_and_slide().
	if is_on_floor():
		_coyote_timer = stats.coyote_time
		if velocity.y >= 0.0:
			_is_jump_rising = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = stats.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity: float = get_jump_gravity()
	if velocity.y > 0.0:
		gravity *= stats.fall_gravity_multiplier
	velocity.y = minf(velocity.y + gravity * delta, stats.max_fall_speed)


func _handle_jump() -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = -get_jump_velocity()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_is_jump_rising = true
		# Pulo vindo do buffer com o botão já solto: aplica o corte imediatamente.
		if not Input.is_action_pressed("jump"):
			_cut_jump()
	elif _is_jump_rising and Input.is_action_just_released("jump"):
		_cut_jump()

	if velocity.y >= 0.0:
		_is_jump_rising = false


func _cut_jump() -> void:
	if velocity.y < 0.0:
		velocity.y *= stats.jump_cut_multiplier
	_is_jump_rising = false


func _apply_horizontal_movement(direction: float, delta: float) -> void:
	var target_speed: float = direction * stats.max_speed
	# Acelera apenas para ganhar velocidade na direção atual (ou partindo do repouso).
	# Desacelera ao soltar, ao reduzir a inclinação do analógico ou ao inverter a direção.
	var is_same_direction: bool = is_zero_approx(velocity.x) or signf(direction) == signf(velocity.x)
	var is_accelerating: bool = direction != 0.0 and is_same_direction and absf(target_speed) > absf(velocity.x)

	var rate: float
	if is_on_floor():
		rate = stats.ground_acceleration if is_accelerating else stats.ground_deceleration
	else:
		rate = stats.air_acceleration if is_accelerating else stats.air_deceleration

	velocity.x = move_toward(velocity.x, target_speed, rate * delta)


func _update_facing(direction: float) -> void:
	# Mantém o lado atual quando não há input horizontal, durante o golpe
	# (preparação e fase ativa) e durante a preparação da habilidade.
	if direction != 0.0 and not _melee_attack.is_striking() and not _is_ability_casting():
		_visuals.scale.x = signf(direction)


func _update_animation() -> void:
	# Prioridade: attack durante preparação e fase ativa (se existir no SpriteFrames;
	# senão, segue a animação normal). Na recuperação, volta à animação do estado físico.
	if _melee_attack.is_striking() and _sprite.sprite_frames != null \
			and _sprite.sprite_frames.has_animation(ANIM_ATTACK):
		_play_animation(ANIM_ATTACK)
		return
	# Mesma regra para a habilidade, durante a preparação.
	if _is_ability_casting() and _sprite.sprite_frames != null \
			and _sprite.sprite_frames.has_animation(ANIM_ABILITY):
		_play_animation(ANIM_ABILITY)
		return
	# No ar: jump subindo, fall descendo. No chão: walk em movimento, idle parado.
	# Walk usa o deslocamento real do move_and_slide(): empurrar uma parede resulta em idle,
	# inclusive no tick do pouso, em que velocity.x pode sobrar sem movimento efetivo.
	var animation_name: StringName
	if not is_on_floor():
		animation_name = ANIM_JUMP if velocity.y < 0.0 else ANIM_FALL
	elif absf(get_real_velocity().x) > WALK_SPEED_THRESHOLD:
		animation_name = ANIM_WALK
	else:
		animation_name = ANIM_IDLE
	_play_animation(animation_name)


func _play_animation(animation_name: StringName) -> void:
	var frames: SpriteFrames = _sprite.sprite_frames
	if frames == null:
		return
	# Animação ausente no SpriteFrames do personagem: usa idle como alternativa.
	if not frames.has_animation(animation_name):
		if not frames.has_animation(ANIM_IDLE):
			return
		animation_name = ANIM_IDLE
	if _sprite.animation == animation_name:
		# Já é a animação atual. Só retoma se for em loop e estiver parada;
		# animações sem loop (ex.: jump) permanecem no último quadro.
		if _sprite.is_playing() or not frames.get_animation_loop(animation_name):
			return
	_sprite.play(animation_name)
