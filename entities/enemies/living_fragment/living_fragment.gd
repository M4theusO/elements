class_name LivingFragment
extends Enemy
## Fragmento Vivo: pequena criatura de pedra que patrulha, persegue a Terra e ataca com
## uma investida curta (MeleeAttack: preparação parada, fase ativa em movimento, recuperação).
## Não cai de bordas nem atravessa paredes. Só a investida causa dano.

enum State { PATROL, CHASE, ATTACK, DEAD }

## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001
## Diferença horizontal mínima para virar na direção do alvo (evita tremer em cima dele).
const FACE_TARGET_MIN_DX: float = 0.1
## Velocidade horizontal real abaixo da qual o inimigo é considerado parado (animação idle).
const WALK_MIN_SPEED: float = 1.0

const ANIM_IDLE: StringName = &"idle"
const ANIM_WALK: StringName = &"walk"
const ANIM_ATTACK: StringName = &"attack"
const ANIM_HIT: StringName = &"hit"
const ANIM_DEATH: StringName = &"death"

@export_group("Patrulha")
@export_range(0.0, 200.0, 1.0, "suffix:px/s") var patrol_speed: float = 30.0
## Distância máxima, para cada lado, do ponto onde o inimigo nasceu.
@export_range(0.0, 512.0, 1.0, "suffix:px") var patrol_distance: float = 48.0

@export_group("Perseguição")
@export_range(0.0, 400.0, 1.0, "suffix:px/s") var chase_speed: float = 60.0
## Distância (entre as origens) acima da qual o alvo é perdido. A detecção (80 px) é a DetectionArea.
@export_range(0.0, 1024.0, 1.0, "suffix:px") var lose_range: float = 128.0
## Distância horizontal em que para de se aproximar.
@export_range(0.0, 128.0, 1.0, "suffix:px") var hold_distance: float = 24.0
## Altura dos olhos (acima dos pés) e do ponto mirado no alvo para a linha de visão.
@export_range(0.0, 64.0, 1.0, "suffix:px") var eye_height: float = 12.0
@export_range(0.0, 64.0, 1.0, "suffix:px") var target_sight_height: float = 16.0

@export_group("Investida")
@export_range(0.0, 256.0, 1.0, "suffix:px") var attack_range_x: float = 40.0
@export_range(0.0, 256.0, 1.0, "suffix:px") var attack_range_y: float = 24.0
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var dash_speed: float = 200.0
## A investida para quando o alvo, à frente, fica a esta distância horizontal (não atravessa a Terra).
## 12 px mantém a hurtbox da Terra dentro da hitbox (0 a 24 px à frente do centro).
@export_range(0.0, 64.0, 1.0, "suffix:px") var dash_stop_distance: float = 12.0

@export_group("Dano recebido")
## Tempo parado ao receber dano fora da investida (dura o mesmo que a animação hit: 3 quadros a 12 fps).
@export_range(0.0, 2.0, 0.05, "suffix:s") var hit_stun_time: float = 0.25
## Contada a partir do fim da recuperação.
@export_range(0.0, 10.0, 0.05, "suffix:s") var cooldown_time: float = 1.5

@export_group("Física")
@export_range(0.0, 2000.0, 1.0, "suffix:px/s") var max_fall_speed: float = 360.0
## Layers que contam como chão à frente (configurado na cena).
@export_flags_2d_physics var ground_mask: int = 0
## Layers que bloqueiam a visão (configurado na cena).
@export_flags_2d_physics var sight_mask: int = 0

var _state: State = State.PATROL
var _target: Node2D
var _cooldown_left: float = 0.0
var _stun_left: float = 0.0
var _patrol_origin_x: float = 0.0

@onready var _melee_attack: MeleeAttack = $MeleeAttack
@onready var _hitbox: Hitbox = $Visuals/Hitbox
@onready var _detection_area: Area2D = $DetectionArea


func _ready() -> void:
	super()
	_patrol_origin_x = global_position.x


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	# Lido antes de descontar: o tick em que o atordoamento termina ainda conta como parado (0,25 s = 15 ticks).
	var stunned: bool = is_stunned()
	_stun_left = maxf(_stun_left - delta, 0.0)
	_apply_gravity(delta, max_fall_speed)
	if stunned:
		# Atordoado: parado, sem trocar de estado nem iniciar investida.
		velocity.x = 0.0
	else:
		match _state:
			State.PATROL:
				_update_patrol()
			State.CHASE:
				_update_chase()
			State.ATTACK:
				_update_attack(delta)
	# Nunca sai de uma borda, em nenhum estado.
	if is_on_floor() and velocity.x != 0.0 and not _has_ground_ahead(signf(velocity.x), absf(velocity.x) * delta, ground_mask):
		velocity.x = 0.0
	move_and_slide()
	if _state == State.PATROL and is_on_wall() and get_wall_normal().x * get_facing() < 0.0:
		_set_facing(-get_facing())
	_update_animation()


func get_state() -> State:
	return _state


func get_target() -> Node2D:
	return _target


func get_patrol_origin_x() -> float:
	return _patrol_origin_x


func is_attack_ready() -> bool:
	return _cooldown_left <= TIME_EPSILON


func is_stunned() -> bool:
	return _stun_left > TIME_EPSILON


func _on_death() -> void:
	_state = State.DEAD
	_target = null
	velocity = Vector2.ZERO
	set_physics_process(false)
	# Uma investida em andamento não pode ligar a hitbox depois da morte.
	_melee_attack.process_mode = Node.PROCESS_MODE_DISABLED
	_hitbox.deactivate()
	_detection_area.set_deferred("monitoring", false)


func _play_death_animation() -> bool:
	if not _has_animation(ANIM_DEATH):
		return false
	_play(ANIM_DEATH, true)
	_sprite.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)
	return true


func _on_damaged(amount: int) -> void:
	super(amount)
	# O hit não interrompe a investida nem a morte (o dano que mata também chega aqui).
	if _state != State.ATTACK and not is_dead():
		_stun_left = hit_stun_time
		_play(ANIM_HIT, true)


func _update_patrol(can_acquire: bool = true) -> void:
	if can_acquire and _try_acquire_target():
		_state = State.CHASE
		_update_chase()
		return
	var offset: float = global_position.x - _patrol_origin_x
	# Fora da área (ou no limite) indo para longe dela: volta.
	if (offset >= patrol_distance and get_facing() > 0.0) or (offset <= -patrol_distance and get_facing() < 0.0):
		_set_facing(-get_facing())
	if is_on_floor() and not _has_ground_ahead(get_facing(), patrol_speed / Engine.physics_ticks_per_second, ground_mask):
		_set_facing(-get_facing())
	velocity.x = get_facing() * patrol_speed


func _update_chase() -> void:
	if not _is_target_valid() or global_position.distance_to(_target.global_position) > lose_range:
		_target = null
		_state = State.PATROL
		_update_patrol(false)
		return
	var dx: float = _target.global_position.x - global_position.x
	var dy: float = _target.global_position.y - global_position.y
	if absf(dx) > FACE_TARGET_MIN_DX:
		_set_facing(signf(dx))
	if absf(dx) <= attack_range_x and absf(dy) <= attack_range_y and is_on_floor() and is_attack_ready() \
			and _melee_attack.try_attack():
		_state = State.ATTACK
		velocity.x = 0.0
		return
	velocity.x = 0.0 if absf(dx) <= hold_distance else get_facing() * chase_speed


func _update_attack(delta: float) -> void:
	# MeleeAttack roda antes (prioridade -1): o estado lido aqui já é o deste tick.
	if not _melee_attack.is_busy():
		_cooldown_left = cooldown_time
		_state = State.CHASE if _is_target_valid() else State.PATROL
		velocity.x = 0.0
		return
	# Direção travada: só avança na fase ativa.
	if not _hitbox.is_active():
		velocity.x = 0.0
		return
	var speed: float = dash_speed
	# Alvo à frente: avança só até dash_stop_distance dele (sem ultrapassar no último tick).
	if _is_target_valid():
		var ahead: float = (_target.global_position.x - global_position.x) * get_facing()
		if ahead >= 0.0:
			speed = clampf((ahead - dash_stop_distance) / delta, 0.0, dash_speed)
	velocity.x = get_facing() * speed


## Adota como alvo um corpo dentro da DetectionArea com linha de visão livre.
func _try_acquire_target() -> bool:
	for body: Node2D in _detection_area.get_overlapping_bodies():
		if global_position.distance_to(body.global_position) <= lose_range \
				and _has_line_of_sight(body, eye_height, target_sight_height, sight_mask):
			_target = body
			return true
	return false


func _is_target_valid() -> bool:
	return is_instance_valid(_target) and not _target.is_queued_for_deletion()


## Escolhe a animação do estado atual. O hit, enquanto toca, tem prioridade sobre idle/walk.
## A investida usa as durações por quadro do SpriteFrames, ajustadas às fases do ataque.
func _update_animation() -> void:
	if _sprite == null:
		return
	if _state == State.ATTACK:
		# Começa uma vez por investida; se terminar antes do fim da recuperação, fica no último quadro.
		if _sprite.animation != ANIM_ATTACK:
			_play(ANIM_ATTACK, true)
		return
	if _sprite.animation == ANIM_HIT and _sprite.is_playing():
		return
	var speed: float = absf(get_real_velocity().x)
	if speed > WALK_MIN_SPEED:
		# Passo proporcional à velocidade: fps original na patrulha, dobro na perseguição.
		_play(ANIM_WALK, false, speed / patrol_speed if patrol_speed > 0.0 else 1.0)
	else:
		_play(ANIM_IDLE)
