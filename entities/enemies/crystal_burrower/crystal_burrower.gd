class_name CrystalBurrower
extends Enemy
## Escavador de Cristal: criatura territorial de carapaça rochosa. Alterna pausas (IDLE) e
## patrulha lenta (PATROL) dentro do território; ao chegar a um limite (fim do território,
## parede ou borda) para, espera a pausa e só então vira. Vê a Terra apenas à frente
## (DetectionArea dentro de Visuals, que vira com ele) e com linha de visão livre.
## Ao ver a Terra (com a recarga pronta e no chão), ataca com uma investida longa, conduzida
## pelo MeleeAttack: preparação parada (CHARGE) → investida que atravessa a Terra (DASH,
## hitbox ligada) → vulnerável e parado (STUNNED) → IDLE, com recarga a partir daí.
## Cada estado do ataque é uma fase do MeleeAttack (AttackData crystal_burrower_dash.tres):
## windup_time = CHARGE, active_time = duração máxima do DASH, recovery_time = STUNNED.
## Carapaça nas costas (CarapaceHurtbox): golpes por trás causam metade do dano, exceto em
## STUNNED. Em IDLE/PATROL, um golpe o faz parar por um instante e virar para o atacante;
## o ataque (CHARGE, DASH, STUNNED) nunca é interrompido nem muda de direção.

enum State { IDLE, PATROL, CHARGE, DASH, STUNNED, DEAD }

## Tolerância de arredondamento na contagem de tempo (ver MeleeAttack).
const TIME_EPSILON: float = 0.0001
## Folga de posição para considerar o limite do território atingido.
const POSITION_EPSILON: float = 0.01
## Diferença horizontal mínima para virar na direção do alvo ao iniciar o ataque.
const FACE_TARGET_MIN_DX: float = 0.1

## Feedback provisório do ataque no self_modulate do sprite (Visuals/AnimatedSprite2D), até as
## animações próprias de cada estado; o clarão de dano usa Visuals.modulate e se soma a este.
## CHARGE pisca entre o normal e o brilho; DASH fica no brilho intenso; STUNNED fica apagado.
const CRYSTAL_NORMAL: Color = Color.WHITE
const CRYSTAL_CHARGE: Color = Color(1.6, 1.6, 1.6)
const CRYSTAL_DASH: Color = Color(2.2, 2.2, 2.2)
const CRYSTAL_STUNNED: Color = Color(0.45, 0.45, 0.45)
const CRYSTAL_BLINK_INTERVAL: float = 0.1
## Clarões provisórios (Visuals.modulate) dos golpes na carapaça: com dano reduzido, um clarão
## lilás no lugar do branco normal; absorvido (0 de dano), um clarão curto cinza-arroxeado.
const SHELL_HIT_COLOR: Color = Color(1.5, 1.3, 2.0)
const SHELL_HIT_DURATION: float = 0.1
const SHELL_BLOCK_COLOR: Color = Color(0.7, 0.6, 0.9)
const SHELL_BLOCK_DURATION: float = 0.06

@export_group("Patrulha")
@export_range(0.0, 200.0, 1.0, "suffix:px/s") var patrol_speed: float = 25.0
## Distância máxima, para cada lado, do ponto onde o inimigo nasceu.
@export_range(0.0, 512.0, 1.0, "suffix:px") var patrol_distance: float = 64.0
## Pausa parada em IDLE (no início, a cada limite da patrulha e depois de STUNNED).
@export_range(0.0, 10.0, 0.05, "suffix:s") var idle_time: float = 1.0

@export_group("Detecção")
## Alcance e altura da visão: forma da DetectionArea na cena (128x40 px à frente).
## Altura dos olhos (acima dos pés) e do ponto mirado no alvo para a linha de visão.
@export_range(0.0, 64.0, 1.0, "suffix:px") var eye_height: float = 10.0
@export_range(0.0, 64.0, 1.0, "suffix:px") var target_sight_height: float = 16.0

@export_group("Investida")
## Dano e durações ficam no AttackData do MeleeAttack. Alcance máximo teórico:
## dash_speed x active_time (180 x 0,75 = 135 px).
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var dash_speed: float = 180.0
## Tempo sem iniciar outra investida, contado a partir do fim de STUNNED.
@export_range(0.0, 10.0, 0.05, "suffix:s") var cooldown_time: float = 1.0

@export_group("Dano recebido")
## Tempo parado ao receber um golpe em IDLE/PATROL (a redução de dano fica na CarapaceHurtbox).
@export_range(0.0, 2.0, 0.05, "suffix:s") var hit_react_time: float = 0.25

@export_group("Física")
@export_range(0.0, 2000.0, 1.0, "suffix:px/s") var max_fall_speed: float = 360.0
## Layers que contam como chão à frente (configurado na cena).
@export_flags_2d_physics var ground_mask: int = 0
## Layers que bloqueiam a visão (configurado na cena).
@export_flags_2d_physics var sight_mask: int = 0

var _state: State = State.IDLE
var _idle_left: float = 0.0
## Vira ao fim da pausa (a pausa começou num limite da patrulha).
var _turn_after_idle: bool = false
var _patrol_origin_x: float = 0.0
var _detected_target: Node2D
var _cooldown_left: float = 0.0
## Tempo desde o início de CHARGE (só para o piscar dos cristais).
var _charge_elapsed: float = 0.0
var _react_left: float = 0.0

@onready var _detection_area: Area2D = $Visuals/DetectionArea
@onready var _carapace: CarapaceHurtbox = $Hurtbox
@onready var _melee_attack: MeleeAttack = $MeleeAttack
@onready var _hitbox: Hitbox = $Visuals/Hitbox
@onready var _state_tint: CanvasItem = $Visuals/AnimatedSprite2D


func _ready() -> void:
	super()
	_patrol_origin_x = global_position.x
	_carapace.hit_received.connect(_on_hit_received)
	_carapace.shell_blocked.connect(_on_shell_blocked)
	_enter_idle(false)


func _physics_process(delta: float) -> void:
	# MeleeAttack roda antes (prioridade -1): a fase lida aqui já é a deste tick.
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	# Lido antes de descontar: o tick em que a reação termina ainda conta como parado (0,25 s = 15 ticks).
	var reacting: bool = is_reacting()
	_react_left = maxf(_react_left - delta, 0.0)
	_apply_gravity(delta, max_fall_speed)
	match _state:
		State.IDLE:
			if reacting:
				velocity.x = 0.0
			else:
				_update_idle(delta)
		State.PATROL:
			if reacting:
				velocity.x = 0.0
			else:
				_update_patrol(delta)
		State.CHARGE:
			_update_charge(delta)
		State.DASH:
			_update_dash(delta)
		State.STUNNED:
			_update_stunned()
		_:
			velocity.x = 0.0
	move_and_slide()
	# Parede à frente: limite da patrulha ou fim antecipado da investida. A Hitbox (filha)
	# roda depois deste nó no mesmo tick, então já encontra a hitbox desligada.
	if is_on_wall() and get_wall_normal().x * get_facing() < 0.0:
		if _state == State.PATROL and not reacting:
			_enter_idle(true)
		elif _state == State.DASH:
			_end_dash_early()
	_update_detection()
	# A reação a um golpe tem prioridade sobre a detecção: não inicia o ataque enquanto dura.
	if not reacting:
		_try_start_charge()
	_update_state_tint()


func get_state() -> State:
	return _state


func get_patrol_origin_x() -> float:
	return _patrol_origin_x


## Terra vista neste tick (à frente, dentro da área e com linha de visão), ou null.
## Atualizada no fim de cada tick em IDLE e PATROL (null nos outros estados).
func get_detected_target() -> Node2D:
	return _detected_target


func is_target_detected() -> bool:
	return _detected_target != null


## A recarga terminou (pode iniciar uma investida ao ver a Terra).
func is_attack_ready() -> bool:
	return _cooldown_left <= TIME_EPSILON


## Parado por causa de um golpe recebido em IDLE/PATROL.
func is_reacting() -> bool:
	return _react_left > TIME_EPSILON


func _on_death() -> void:
	_state = State.DEAD
	_detected_target = null
	_react_left = 0.0
	velocity = Vector2.ZERO
	# Golpes no corpo morto não passam pela carapaça (sem shell_blocked nem frações guardadas).
	_carapace.shell_active = false
	_carapace.reset_pending_damage()
	set_physics_process(false)
	# Um ataque em andamento não pode ligar a hitbox nem avançar de fase depois da morte.
	_melee_attack.process_mode = Node.PROCESS_MODE_DISABLED
	_hitbox.deactivate()
	_detection_area.set_deferred("monitoring", false)
	_state_tint.self_modulate = CRYSTAL_NORMAL


## Clarão do dano aplicado: lilás se o golpe acertou a carapaça, o branco da base nos outros
## casos e no golpe que mata (a morte some ao fim deste clarão, ver Enemy._on_died()).
func _on_damaged(amount: int) -> void:
	if _carapace.is_last_hit_on_shell() and not is_dead():
		_flash(SHELL_HIT_COLOR, SHELL_HIT_DURATION)
	else:
		super(amount)


## Todo golpe aceito, inclusive os absorvidos (damage 0); vem antes de o dano ser aplicado.
func _on_hit_received(damage: int) -> void:
	# Morto ou golpe fatal: a morte cuida de tudo, sem reação.
	if is_dead() or damage >= _health.current_health:
		return
	# CHARGE, DASH e STUNNED não são interrompidos nem mudam de direção.
	if _state != State.IDLE and _state != State.PATROL:
		return
	_react_left = hit_react_time
	velocity.x = 0.0
	# Vira para quem atacou (contra a trajetória do golpe), se ela for conhecida.
	var direction: Vector2 = _carapace.get_last_hit_direction()
	if absf(direction.x) > CarapaceHurtbox.DIRECTION_EPSILON:
		var toward_attacker: float = -signf(direction.x)
		if toward_attacker != get_facing():
			_set_facing(toward_attacker)
			# Já virou: uma virada pendente do fim da pausa o deixaria de costas para o atacante.
			_turn_after_idle = false


func _on_shell_blocked() -> void:
	if not is_dead():
		_flash(SHELL_BLOCK_COLOR, SHELL_BLOCK_DURATION)


## Mesmo mecanismo do clarão da base Enemy (_flash_tween), com outra cor e duração.
func _flash(color: Color, duration: float) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_visuals.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visuals, "modulate", Color.WHITE, duration)


func _enter_idle(turn_after: bool) -> void:
	_state = State.IDLE
	_idle_left = idle_time
	_turn_after_idle = turn_after
	velocity.x = 0.0


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	_idle_left -= delta
	if _idle_left > TIME_EPSILON:
		return
	if _turn_after_idle:
		_set_facing(-get_facing())
	_state = State.PATROL
	_update_patrol(delta)


func _update_patrol(delta: float) -> void:
	# No ar (ex.: caindo): sem deslocamento horizontal, para não sair de uma borda.
	if not is_on_floor():
		velocity.x = 0.0
		return
	var facing: float = get_facing()
	# Distância até o limite do território no sentido atual; o passo não o ultrapassa.
	var room: float = patrol_distance - (global_position.x - _patrol_origin_x) * facing
	if room <= POSITION_EPSILON:
		_enter_idle(true)
		return
	var speed: float = minf(patrol_speed, room / delta)
	if not _has_ground_ahead(facing, speed * delta, ground_mask):
		_enter_idle(true)
		return
	velocity.x = facing * speed


func _update_detection() -> void:
	_detected_target = null
	if _state != State.IDLE and _state != State.PATROL:
		return
	for body: Node2D in _detection_area.get_overlapping_bodies():
		if _has_line_of_sight(body, eye_height, target_sight_height, sight_mask):
			_detected_target = body
			return


## Chamado no fim do tick, logo depois da detecção (que já confirmou a linha de visão).
## A preparação do MeleeAttack começa a contar no tick seguinte: CHARGE dura exatamente windup_time.
func _try_start_charge() -> void:
	if _state != State.IDLE and _state != State.PATROL:
		return
	if _detected_target == null or is_dead() or not is_on_floor() or not is_attack_ready():
		return
	if not _melee_attack.try_attack():
		return
	# Vira para a Terra uma única vez; a direção fica travada até o fim do ataque.
	var dx: float = _detected_target.global_position.x - global_position.x
	if absf(dx) > FACE_TARGET_MIN_DX:
		_set_facing(signf(dx))
	_state = State.CHARGE
	_charge_elapsed = 0.0
	velocity.x = 0.0


func _update_charge(delta: float) -> void:
	# A hitbox liga quando o MeleeAttack entra na fase ativa: começa a investida neste tick.
	if _hitbox.is_active():
		_state = State.DASH
		_update_dash(delta)
		return
	_charge_elapsed += delta
	velocity.x = 0.0


func _update_dash(delta: float) -> void:
	# Fase ativa esgotada (tempo máximo): o MeleeAttack já desligou a hitbox e está na recuperação.
	if not _hitbox.is_active():
		_enter_stunned()
		return
	if not is_on_floor():
		velocity.x = 0.0
		return
	var facing: float = get_facing()
	# Borda à frente: para antes de dar o passo que o tiraria do chão.
	if not _has_ground_ahead(facing, dash_speed * delta, ground_mask):
		_end_dash_early()
		return
	velocity.x = facing * dash_speed


## Parede ou borda: encerra a fase ativa agora (hitbox desligada na hora) e começa
## a recuperação completa (STUNNED) a partir deste tick.
func _end_dash_early() -> void:
	_melee_attack.finish_active()
	_enter_stunned()


func _enter_stunned() -> void:
	_state = State.STUNNED
	velocity.x = 0.0
	# Vulnerável: dano integral, sem levar frações de antes para este período.
	_carapace.shell_active = false
	_carapace.reset_pending_damage()


func _update_stunned() -> void:
	velocity.x = 0.0
	if _melee_attack.is_busy():
		return
	# Fim da recuperação: carapaça de volta, IDLE e só então começa a recarga.
	_carapace.shell_active = true
	_cooldown_left = cooldown_time
	_enter_idle(false)


func _update_state_tint() -> void:
	match _state:
		State.CHARGE:
			var lit: bool = int(_charge_elapsed / CRYSTAL_BLINK_INTERVAL) % 2 == 0
			_state_tint.self_modulate = CRYSTAL_CHARGE if lit else CRYSTAL_NORMAL
		State.DASH:
			_state_tint.self_modulate = CRYSTAL_DASH
		State.STUNNED:
			_state_tint.self_modulate = CRYSTAL_STUNNED
		_:
			_state_tint.self_modulate = CRYSTAL_NORMAL
