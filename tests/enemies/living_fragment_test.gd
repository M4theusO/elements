extends SceneTree
## Teste automatizado do Fragmento Vivo (LivingFragment), da base Enemy e da vida da Terra
## (HealthComponent + Hurtbox com invulnerabilidade). Cada caso monta um cenário próprio em código.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/enemies/living_fragment_test.gd

const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const DUMMY_PATH: String = "res://entities/enemies/training_dummy/training_dummy.tscn"
const LAB_PATH: String = "res://tests/movement_lab/movement_lab.tscn"

const FLOOR_Y: float = 400.0
const START_X: float = 400.0
const HALF_WIDTH: float = 9.0
const WINDUP_TICKS: int = 21
const ACTIVE_TICKS: int = 12
const RECOVERY_TICKS: int = 24
const COOLDOWN_TICKS: int = 90
const INVULNERABLE_TICKS: int = 36
const DASH_DISTANCE: float = 40.0
const LAYER_WORLD: int = 1
const LAYER_PLATFORMS: int = 2

var _failures: int = 0
var _checks: int = 0
var _world: Node2D
var _fragment_scene: PackedScene
var _terra_scene: PackedScene
var _dummy_scene: PackedScene


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Fragmento Vivo")
	await process_frame
	_fragment_scene = load(FRAGMENT_PATH) as PackedScene
	_terra_scene = load(TERRA_PATH) as PackedScene
	_dummy_scene = load(DUMMY_PATH) as PackedScene
	_check_static_configuration()

	await _test_patrol()
	await _test_patrol_wall()
	await _test_patrol_edges()
	await _test_detection()
	await _test_line_of_sight()
	await _test_chase()
	await _test_chase_obstacles()
	await _test_dash()
	await _test_dash_facing_lock()
	await _test_dash_obstacles()
	await _test_cooldown()
	await _test_terra_invulnerability()
	await _test_simultaneous_attacks()
	await _test_terra_zero_health()
	await _test_invulnerability_keeps_controls()
	await _test_damage_received()
	await _test_animations()
	await _test_death()
	await _test_death_during_windup()
	await _test_training_dummy()

	_release_all()
	if _world != null:
		_world.free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração ---------------------------------------------------------------

func _check_static_configuration() -> void:
	print("-- Configuração")
	var fragment: LivingFragment = _fragment_scene.instantiate() as LivingFragment
	_check(fragment is Enemy and fragment.collision_layer == 8 and fragment.collision_mask == 67,
		"LivingFragment é Enemy; corpo layer enemies | mask world, platforms, destructibles")
	var hurtbox: Hurtbox = fragment.get_node("Hurtbox") as Hurtbox
	var health: HealthComponent = fragment.get_node("HealthComponent") as HealthComponent
	_check(hurtbox.collision_layer == 32 and hurtbox.collision_mask == 0 and hurtbox.health == health
		and health.max_health == 3 and is_zero_approx(hurtbox.invulnerability_time),
		"Hurtbox na layer enemy_hurtbox, 3 de vida, sem invulnerabilidade")
	var hitbox: Hitbox = fragment.get_node("Visuals/Hitbox") as Hitbox
	_check(hitbox.collision_layer == 0 and hitbox.collision_mask == 16 and not hitbox.monitoring
		and not hitbox.show_debug, "Hitbox: layer nenhuma | mask player_hurtbox, desligada, sem aviso de debug")
	var hit_shape: CollisionShape2D = hitbox.get_node("CollisionShape2D") as CollisionShape2D
	var body_shape: CollisionShape2D = fragment.get_node("CollisionShape2D") as CollisionShape2D
	_check((hit_shape.shape as RectangleShape2D).size == Vector2(24, 12) and hit_shape.position == Vector2(12, -10)
		and (body_shape.shape as RectangleShape2D).size == Vector2(18, 24) and body_shape.position == Vector2(0, -12),
		"corpo 18x24; Hitbox 24x12 do centro para a frente")
	var detection: Area2D = fragment.get_node("DetectionArea") as Area2D
	var circle: CircleShape2D = (detection.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	_check(detection.collision_layer == 0 and detection.collision_mask == 4 and not detection.monitorable
		and is_equal_approx(circle.radius, 80.0), "DetectionArea: mask player, raio 80 px")
	var melee: MeleeAttack = fragment.get_node("MeleeAttack") as MeleeAttack
	var data: AttackData = melee.attack
	_check(melee.hitbox == hitbox and data.damage == 1 and is_equal_approx(data.windup_time, 0.35)
		and is_equal_approx(data.active_time, 0.2) and is_equal_approx(data.recovery_time, 0.4),
		"investida: dano 1; 0,35 / 0,20 / 0,40 s")
	_check(is_equal_approx(fragment.patrol_speed, 30.0) and is_equal_approx(fragment.patrol_distance, 48.0)
		and is_equal_approx(fragment.chase_speed, 60.0) and is_equal_approx(fragment.lose_range, 128.0)
		and is_equal_approx(fragment.attack_range_x, 40.0) and is_equal_approx(fragment.attack_range_y, 24.0)
		and is_equal_approx(fragment.dash_speed, 200.0) and is_equal_approx(fragment.cooldown_time, 1.5)
		and is_equal_approx(fragment.hold_distance, 24.0) and is_equal_approx(fragment.dash_stop_distance, 12.0)
		and is_equal_approx(fragment.hit_stun_time, 0.25),
		"valores: patrulha 30 px/s ±48, perseguição 60, perda 128, gatilho 40/24, investida 200, recarga 1,5 s, para a 12 px do alvo, atordoamento 0,25 s")
	_check(fragment.ground_mask == (LAYER_WORLD | LAYER_PLATFORMS) and fragment.sight_mask == (LAYER_WORLD | 64),
		"raios: chão = world + platforms; visão bloqueada por world + destructibles")
	var sprite: AnimatedSprite2D = fragment.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = sprite.sprite_frames if sprite != null else null
	var frames_ok: bool = frames != null
	if frames_ok:
		for anim: Array in [[&"idle", 4, true], [&"walk", 6, true], [&"attack", 8, false], [&"hit", 3, false], [&"death", 6, false]]:
			frames_ok = frames_ok and frames.has_animation(anim[0]) and frames.get_frame_count(anim[0]) == anim[1] \
				and frames.get_animation_loop(anim[0]) == anim[2] \
				and frames.get_frame_texture(anim[0], 0).get_size() == Vector2(64, 48)
	_check(frames_ok and sprite.autoplay == "idle" and sprite.offset == Vector2(-32, -45),
		"visual: idle 4, walk 6, attack 8, hit 3, death 6 quadros 64x48; pés na origem")
	fragment.free()

	var terra: PlayerCharacter = _terra_scene.instantiate() as PlayerCharacter
	var terra_hurtbox: Hurtbox = terra.get_node("Hurtbox") as Hurtbox
	var terra_health: HealthComponent = terra.get_node("HealthComponent") as HealthComponent
	_check(terra_hurtbox != null and terra_health != null and terra_hurtbox.health == terra_health
		and terra_health.max_health == 5 and is_equal_approx(terra_hurtbox.invulnerability_time, 0.6),
		"Terra: 5 de vida, Hurtbox ligada à vida, invulnerabilidade 0,6 s")
	_check(terra_hurtbox.collision_layer == 16 and terra_hurtbox.collision_mask == 0 and not terra_hurtbox.monitoring,
		"Hurtbox da Terra continua na layer player_hurtbox, sem mask")
	terra.free()

	var dummy: Node = _dummy_scene.instantiate()
	_check(dummy is Enemy, "TrainingDummy usa a base Enemy")
	dummy.free()

	var lab: Node = (load(LAB_PATH) as PackedScene).instantiate()
	var fragments: int = 0
	for child: Node in lab.get_children():
		if child.scene_file_path == FRAGMENT_PATH:
			fragments += 1
	_check(fragments == 2, "MovementLab tem 2 Fragmentos Vivos (%d)" % fragments)
	lab.free()


# --- Patrulha -------------------------------------------------------------------

func _test_patrol() -> void:
	print("-- Patrulha")
	await _new_world()
	_floor(0.0, 1000.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var start_x: float = fragment.global_position.x
	await _wait(30)
	_check(is_equal_approx(fragment.global_position.x - start_x, 15.0),
		"30 px/s: 15 px em 30 ticks (%.2f)" % (fragment.global_position.x - start_x))
	var track: Dictionary = await _track(fragment, 600)
	_check(track.min_x >= START_X - 48.0 - 0.6 and track.max_x <= START_X + 48.0 + 0.6,
		"fica em ±48 px da origem (%.1f a %.1f)" % [track.min_x, track.max_x])
	_check(track.min_x <= START_X - 47.0 and track.max_x >= START_X + 47.0, "percorre a área inteira, virando nos limites")
	_check(track.always_on_floor and track.max_y <= FLOOR_Y + 0.5, "sempre no chão")
	_check(fragment.get_state() == LivingFragment.State.PATROL, "sem alvo, continua patrulhando")


func _test_patrol_wall() -> void:
	print("-- Patrulha: parede")
	await _new_world()
	_floor(0.0, 1000.0)
	_box(430.0, 200.0, 446.0, FLOOR_Y)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var track: Dictionary = await _track(fragment, 600)
	_check(track.max_x + HALF_WIDTH <= 430.05, "não atravessa a parede (borda frontal máx. %.2f)" % (track.max_x + HALF_WIDTH))
	_check(track.max_x >= 420.5 and track.min_x <= START_X - 47.0, "encosta na parede e volta (%.1f a %.1f)" % [track.min_x, track.max_x])


func _test_patrol_edges() -> void:
	print("-- Patrulha: bordas")
	await _new_world()
	_floor(0.0, 420.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var track: Dictionary = await _track(fragment, 600)
	_check(track.always_on_floor and track.max_y <= FLOOR_Y + 0.5, "não cai da borda do chão")
	_check(track.max_x + HALF_WIDTH <= 420.6 and track.min_x <= START_X - 47.0,
		"vira na borda (borda frontal máx. %.2f) e segue patrulhando" % (track.max_x + HALF_WIDTH))

	await _new_world()
	_box(370.0, FLOOR_Y, 430.0, FLOOR_Y + 8.0, LAYER_PLATFORMS, true)
	fragment = _spawn_fragment(START_X)
	track = await _track(fragment, 600)
	_check(track.always_on_floor and track.max_y <= FLOOR_Y + 0.5, "plataforma one-way: não cai")
	_check(track.min_x - HALF_WIDTH >= 369.4 and track.max_x + HALF_WIDTH <= 430.6
		and track.max_x - track.min_x >= 35.0, "plataforma one-way: vira nas duas bordas (%.1f a %.1f)" % [track.min_x, track.max_x])


# --- Detecção e perseguição -----------------------------------------------------

func _test_detection() -> void:
	print("-- Detecção")
	# Borda do corpo da Terra (16 px de largura) a 79 px do centro do círculo: detecta.
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X - 86.0, 1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	await _wait(3)
	_check(fragment.get_state() == LivingFragment.State.CHASE and fragment.get_target() == terra,
		"Terra a ~79 px: persegue")

	# A ~81 px (e se afastando, pois o fragmento patrulha para o outro lado): não detecta.
	await _new_world()
	_floor(0.0, 1000.0)
	terra = await _spawn_terra(START_X - 89.0, 1.0)
	fragment = _spawn_fragment(START_X)
	var detected: bool = false
	for i: int in 20:
		await physics_frame
		detected = detected or fragment.get_state() != LivingFragment.State.PATROL
	_check(not detected, "Terra a ~81 px: não detecta")

	# Histerese: perde o alvo só acima de 128 px.
	await _new_world()
	_floor(0.0, 1000.0)
	terra = await _spawn_terra(START_X + 120.0, 1.0)
	fragment = _spawn_fragment(START_X)
	await _wait(3)
	terra.global_position.x = START_X + 70.0
	await _wait(3)
	_check(fragment.get_state() == LivingFragment.State.CHASE, "Terra a 70 px: persegue")
	terra.global_position.x = fragment.global_position.x + 110.0
	await _wait(2)
	_check(fragment.get_state() == LivingFragment.State.CHASE, "Terra a 110 px (fora da detecção, dentro de 128): continua perseguindo")
	terra.global_position.x = fragment.global_position.x + 140.0
	await _wait(2)
	_check(fragment.get_state() == LivingFragment.State.PATROL and fragment.get_target() == null,
		"Terra a 140 px: perde o alvo e volta a patrulhar")


func _test_line_of_sight() -> void:
	print("-- Linha de visão")
	await _new_world()
	_floor(0.0, 1000.0)
	var wall: StaticBody2D = _box(440.0, 200.0, 456.0, FLOOR_Y)
	var terra: PlayerCharacter = await _spawn_terra(470.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var detected: bool = false
	for i: int in 120:
		await physics_frame
		detected = detected or fragment.get_state() != LivingFragment.State.PATROL
	_check(not detected, "parede entre os dois: não detecta (Terra a 62 px)")
	_check(_hp(terra) == 5, "sem dano através da parede")
	wall.free()
	terra.global_position.x = fragment.global_position.x + 60.0
	await _wait(3)
	_check(fragment.get_state() == LivingFragment.State.CHASE, "sem a parede: detecta com linha de visão livre")

	# Obstáculo baixo não bloqueia a visão (raio dos olhos passa por cima).
	await _new_world()
	_floor(0.0, 1000.0)
	_box(430.0, FLOOR_Y - 8.0, 446.0, FLOOR_Y)
	terra = await _spawn_terra(480.0, -1.0)
	fragment = _spawn_fragment(START_X)
	await _wait(3)
	_check(fragment.get_state() == LivingFragment.State.CHASE, "obstáculo baixo (8 px) não bloqueia a visão")


func _test_chase() -> void:
	print("-- Perseguição")
	await _new_world()
	_floor(0.0, 1000.0)
	await _spawn_terra(START_X + 70.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	await _wait_state(fragment, LivingFragment.State.CHASE)
	var x0: float = fragment.global_position.x
	await _wait(10)
	_check(is_equal_approx(fragment.global_position.x - x0, 10.0) and fragment.get_facing() == 1.0,
		"60 px/s em direção à Terra (à direita): %.2f px em 10 ticks" % (fragment.global_position.x - x0))

	await _new_world()
	_floor(0.0, 1000.0)
	await _spawn_terra(START_X - 70.0, 1.0)
	fragment = _spawn_fragment(START_X)
	await _wait_state(fragment, LivingFragment.State.CHASE)
	x0 = fragment.global_position.x
	await _wait(10)
	_check(is_equal_approx(fragment.global_position.x - x0, -10.0) and fragment.get_facing() == -1.0,
		"vira e persegue para a esquerda: %.2f px em 10 ticks" % (fragment.global_position.x - x0))


func _test_chase_obstacles() -> void:
	print("-- Perseguição: borda e parede")
	await _new_world()
	_floor(0.0, 420.0)
	_floor(440.0, 1000.0)
	await _spawn_terra(470.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var track: Dictionary = await _track(fragment, 120)
	_check(track.always_on_floor and track.max_y <= FLOOR_Y + 0.5 and track.max_x + HALF_WIDTH <= 420.6,
		"para na borda sem cair (borda frontal máx. %.2f)" % (track.max_x + HALF_WIDTH))
	_check(fragment.get_state() == LivingFragment.State.CHASE and fragment.get_facing() == 1.0
		and is_zero_approx(fragment.velocity.x), "continua no estado de perseguição, parado e virado para a Terra")

	await _new_world()
	_floor(0.0, 1000.0)
	_box(430.0, FLOOR_Y - 8.0, 446.0, FLOOR_Y)
	await _spawn_terra(480.0, -1.0)
	fragment = _spawn_fragment(START_X)
	track = await _track(fragment, 120)
	_check(track.max_x + HALF_WIDTH <= 430.05 and track.max_x >= 420.5,
		"para no obstáculo sem atravessá-lo (borda frontal máx. %.2f)" % (track.max_x + HALF_WIDTH))


# --- Investida ------------------------------------------------------------------

func _test_dash() -> void:
	print("-- Investida")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var melee: MeleeAttack = fragment.get_node("MeleeAttack") as MeleeAttack
	var hitbox: Hitbox = fragment.get_node("Visuals/Hitbox") as Hitbox
	var hits: Array[int] = [0]
	terra.get_hurtbox().hit_received.connect(func(_d: int) -> void: hits[0] += 1)
	await _wait_state(fragment, LivingFragment.State.ATTACK)
	var dx: float = terra.global_position.x - fragment.global_position.x
	_check(dx <= 40.0 and dx > 38.0, "dispara com a Terra a %.1f px (≤ 40)" % dx)
	var x_start: float = fragment.global_position.x
	var phases: Dictionary = {"windup": 0, "active": 0, "recovery": 0}
	var windup_still: bool = true
	var recovery_still: bool = true
	var hp_after_windup: int = -1
	var x_after_active: float = 0.0
	while melee.is_busy():
		if melee.is_striking() and not hitbox.is_active():
			phases.windup += 1
			windup_still = windup_still and is_equal_approx(fragment.global_position.x, x_start)
			hp_after_windup = _hp(terra)
		elif hitbox.is_active():
			phases.active += 1
			x_after_active = fragment.global_position.x
		else:
			phases.recovery += 1
			recovery_still = recovery_still and is_equal_approx(fragment.global_position.x, x_after_active)
		await physics_frame
	_check(phases.windup == WINDUP_TICKS and windup_still and hp_after_windup == 5,
		"preparação: %d ticks parado, sem dano (esperado %d)" % [phases.windup, WINDUP_TICKS])
	_check(phases.active == ACTIVE_TICKS, "fase ativa: %d ticks (esperado %d)" % [phases.active, ACTIVE_TICKS])
	_check(is_equal_approx(terra.global_position.x - x_after_active, 12.0) and x_after_active - x_start < DASH_DISTANCE,
		"avança %.2f px e para a 12 px da Terra (sobra %.2f px)" % [x_after_active - x_start, terra.global_position.x - x_after_active])
	_check(phases.recovery == RECOVERY_TICKS and recovery_still,
		"recuperação: %d ticks parado (esperado %d)" % [phases.recovery, RECOVERY_TICKS])
	_check(_hp(terra) == 4 and hits[0] == 1, "Terra perde exatamente 1 de vida por investida (vida %d, acertos %d)" % [_hp(terra), hits[0]])

	# Terra acima (|dy| > 24): não dispara.
	await _new_world()
	_floor(0.0, 1000.0)
	_box(420.0, FLOOR_Y - 32.0, 520.0, FLOOR_Y - 24.0, LAYER_PLATFORMS, true)
	terra = await _spawn_terra(450.0, -1.0, FLOOR_Y - 32.0)
	fragment = _spawn_fragment(START_X)
	var attacked: bool = false
	for i: int in 120:
		await physics_frame
		attacked = attacked or fragment.get_state() == LivingFragment.State.ATTACK
	_check(not attacked and _hp(terra) == 5, "Terra 32 px acima: não dispara a investida")


func _test_dash_facing_lock() -> void:
	print("-- Investida: direção travada")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var melee: MeleeAttack = fragment.get_node("MeleeAttack") as MeleeAttack
	await _wait_state(fragment, LivingFragment.State.ATTACK)
	var x_start: float = fragment.global_position.x
	terra.global_position.x = x_start - 30.0
	var locked: bool = true
	while melee.is_busy():
		locked = locked and fragment.get_facing() == 1.0
		await physics_frame
	_check(locked and is_equal_approx(fragment.global_position.x - x_start, DASH_DISTANCE),
		"Terra passa para trás: a investida segue para a frente (%.1f px)" % (fragment.global_position.x - x_start))
	_check(_hp(terra) == 5, "Terra atrás não é atingida")


func _test_dash_obstacles() -> void:
	print("-- Investida: borda e parede")
	await _new_world()
	_floor(0.0, 440.0)
	_floor(456.0, 1000.0)
	await _spawn_terra(470.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	await _wait_state(fragment, LivingFragment.State.ATTACK, 180)
	var started: bool = fragment.get_state() == LivingFragment.State.ATTACK
	var track: Dictionary = await _track(fragment, WINDUP_TICKS + ACTIVE_TICKS + RECOVERY_TICKS + 5)
	_check(started and track.always_on_floor and track.max_y <= FLOOR_Y + 0.5
		and track.max_x + HALF_WIDTH <= 440.6, "investida na borda: para sem cair (borda frontal máx. %.2f)" % (track.max_x + HALF_WIDTH))

	await _new_world()
	_floor(0.0, 1000.0)
	_box(440.0, FLOOR_Y - 8.0, 456.0, FLOOR_Y)
	await _spawn_terra(470.0, -1.0)
	fragment = _spawn_fragment(START_X)
	await _wait_state(fragment, LivingFragment.State.ATTACK, 180)
	started = fragment.get_state() == LivingFragment.State.ATTACK
	track = await _track(fragment, WINDUP_TICKS + ACTIVE_TICKS + RECOVERY_TICKS + 5)
	_check(started and track.max_x + HALF_WIDTH <= 440.05,
		"investida contra obstáculo: não atravessa (borda frontal máx. %.2f)" % (track.max_x + HALF_WIDTH))


func _test_cooldown() -> void:
	print("-- Recarga")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var melee: MeleeAttack = fragment.get_node("MeleeAttack") as MeleeAttack
	await _wait_state(fragment, LivingFragment.State.ATTACK)
	while melee.is_busy():
		await physics_frame
	var gap: int = 0
	var held_still: bool = true
	var x_hold: float = fragment.global_position.x
	while not melee.is_busy() and gap < 300:
		held_still = held_still and is_equal_approx(fragment.global_position.x, x_hold)
		gap += 1
		await physics_frame
	_check(gap == COOLDOWN_TICKS, "nova investida %d ticks após o fim da recuperação (esperado %d)" % [gap, COOLDOWN_TICKS])
	_check(held_still, "na recarga, com a Terra a menos de 24 px, espera parado")
	while melee.is_busy():
		await physics_frame
	_check(_hp(terra) == 3, "segunda investida também acerta (vida %d)" % _hp(terra))


# --- Vida e invulnerabilidade da Terra -------------------------------------------

func _test_terra_invulnerability() -> void:
	print("-- Invulnerabilidade da Terra")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X, 1.0)
	var hurtbox: Hurtbox = terra.get_hurtbox()
	var visuals: Node2D = terra.get_node("Visuals") as Node2D
	var sprite: AnimatedSprite2D = terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var received: Array[int] = [0]
	hurtbox.hit_received.connect(func(_d: int) -> void: received[0] += 1)
	hurtbox.receive_hit(1)
	hurtbox.receive_hit(1)
	_check(_hp(terra) == 4 and received[0] == 1 and hurtbox.is_invulnerable(),
		"dois golpes no mesmo instante: só o primeiro conta (vida %d)" % _hp(terra))
	_check(visuals.modulate.r > 1.0, "feedback: clarão no acerto")
	var frames: int = 0
	var blinked: bool = false
	var ignored: bool = true
	while hurtbox.is_invulnerable() and frames < 120:
		await process_frame
		frames += 1
		blinked = blinked or sprite.self_modulate.a < 1.0
		if hurtbox.is_invulnerable():
			hurtbox.receive_hit(1)
			ignored = ignored and _hp(terra) == 4
	_check(ignored and received[0] == 1, "golpes durante a invulnerabilidade não tiram vida")
	_check(blinked, "feedback: sprite pisca durante a invulnerabilidade")
	await _wait(3)
	await process_frame
	_check(is_equal_approx(sprite.self_modulate.a, 1.0) and visuals.modulate.is_equal_approx(Color.WHITE),
		"feedback: volta ao normal depois da invulnerabilidade")
	hurtbox.receive_hit(1)
	_check(_hp(terra) == 3, "depois da invulnerabilidade recebe dano de novo (vida %d)" % _hp(terra))

	# Duração exata, com golpes vindos de uma Hitbox (dentro do tick de física, como no jogo):
	# a Hitbox é reativada a cada tick e tenta acertar sempre.
	await _wait(INVULNERABLE_TICKS + 2)
	var hitbox: Hitbox = Hitbox.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = 16
	hitbox.show_debug = false
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(40.0, 40.0)
	shape.shape = rect
	hitbox.add_child(shape)
	hitbox.position = terra.global_position + Vector2(0.0, -20.0)
	_world.add_child(hitbox)
	var hit_frames: Array[int] = []
	terra.get_health().damaged.connect(func(_a: int) -> void: hit_frames.append(Engine.get_physics_frames()))
	for i: int in INVULNERABLE_TICKS * 2 + 10:
		hitbox.activate()
		await physics_frame
	hitbox.deactivate()
	_check(hit_frames.size() == 3 and hit_frames[1] - hit_frames[0] == INVULNERABLE_TICKS
		and hit_frames[2] - hit_frames[1] == INVULNERABLE_TICKS,
		"golpes contínuos acertam a cada %d ticks = 0,6 s (%s)" % [INVULNERABLE_TICKS, str(hit_frames)])


func _test_simultaneous_attacks() -> void:
	print("-- Dois Fragmentos ao mesmo tempo")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0, 1.0)
	var left: LivingFragment = _spawn_fragment(START_X)
	var right: LivingFragment = _spawn_fragment(START_X + 120.0)
	var left_hitbox: Hitbox = left.get_node("Visuals/Hitbox") as Hitbox
	var right_hitbox: Hitbox = right.get_node("Visuals/Hitbox") as Hitbox
	var both_active: int = 0
	for i: int in 90:
		await physics_frame
		if left_hitbox.is_active() and right_hitbox.is_active():
			both_active += 1
	_check(both_active > 0, "as duas investidas ficam ativas juntas (%d ticks)" % both_active)
	_check(_hp(terra) == 4, "ataques simultâneos tiram só 1 de vida (vida %d)" % _hp(terra))


func _test_terra_zero_health() -> void:
	print("-- Terra sem vida")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X, 1.0)
	var health: HealthComponent = terra.get_health()
	var deaths: Array[int] = [0]
	var damaged: Array[int] = [0]
	health.died.connect(func() -> void: deaths[0] += 1)
	health.damaged.connect(func(_a: int) -> void: damaged[0] += 1)
	terra.get_hurtbox().receive_hit(10)
	_check(_hp(terra) == 0 and deaths[0] == 1, "dano excedente: vida 0, died uma vez")
	await _wait(INVULNERABLE_TICKS + 2)
	terra.get_hurtbox().receive_hit(1)
	_check(_hp(terra) == 0 and damaged[0] == 1 and deaths[0] == 1, "sem vida: novos golpes não causam dano")
	var fragment: LivingFragment = _spawn_fragment(START_X - 60.0)
	await _wait(180)
	_check(_hp(terra) == 0 and damaged[0] == 1 and deaths[0] == 1 and fragment.get_state() != LivingFragment.State.DEAD,
		"investidas do Fragmento também não causam dano")


func _test_invulnerability_keeps_controls() -> void:
	print("-- Invulnerabilidade não altera os controles")
	var normal: Array[Vector2] = await _record_terra_run(false)
	var invulnerable: Array[Vector2] = await _record_terra_run(true)
	_check(_same_path(normal, invulnerable), "corrida e pulo idênticos com e sem invulnerabilidade (%d ticks)" % normal.size())

	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X, 1.0)
	var melee: MeleeAttack = terra.get_node("MeleeAttack") as MeleeAttack
	var fist: SeismicFist = terra.get_node("SeismicFist") as SeismicFist
	terra.get_hurtbox().receive_hit(1)
	await _press("attack")
	_check(terra.get_hurtbox().is_invulnerable() and melee.is_busy(), "golpe básico funciona durante a invulnerabilidade")
	while melee.is_busy():
		await physics_frame
	await _press("ability")
	_check(terra.get_hurtbox().is_invulnerable() and fist.is_casting(), "Punho Sísmico funciona durante a invulnerabilidade")
	await _wait(120)


# --- Dano recebido e morte --------------------------------------------------------

func _test_damage_received() -> void:
	print("-- Dano recebido")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X - 20.0, 1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var visuals: Node2D = fragment.get_node("Visuals") as Node2D
	var damaged: Array[int] = [0]
	(fragment.get_node("HealthComponent") as HealthComponent).damaged.connect(func(_a: int) -> void: damaged[0] += 1)
	await _press("attack")
	await _wait_until(func() -> bool: return damaged[0] > 0, 30)
	_check(_hp(fragment) == 2 and damaged[0] == 1, "golpe básico: -1 (vida %d)" % _hp(fragment))
	_check(visuals.modulate.r > 1.0, "pisca ao receber dano")
	await _wait(40)

	await _new_world()
	_floor(0.0, 1000.0)
	terra = await _spawn_terra(START_X - 100.0, 1.0)
	fragment = _spawn_fragment(START_X + 10.0)
	fragment.get_node("Visuals").scale.x = -1.0
	await _press("ability")
	await _wait(60)
	_check(_is_alive(fragment) and _hp(fragment) == 1, "onda do Punho Sísmico: -2, uma única vez (vida %d)" % _hp(fragment))
	terra.global_position.x = fragment.global_position.x - 20.0
	_set_terra_facing(terra, 1.0)
	await _wait(2)
	var fragment_health: HealthComponent = fragment.get_node("HealthComponent") as HealthComponent
	await _press("attack")
	await _wait_until(func() -> bool: return fragment_health.is_dead(), 30)
	var died: bool = fragment_health.is_dead()
	await _wait(50)
	_check(died and not _is_alive(fragment),
		"onda + golpe básico derrotam o Fragmento (Terra em x=%.1f, Fragmento em x=%.1f)" % [terra.global_position.x, fragment.global_position.x if _is_alive(fragment) else -1.0])


func _test_animations() -> void:
	print("-- Animações")
	await _new_world()
	_floor(0.0, 1000.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var sprite: AnimatedSprite2D = fragment.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var hurtbox: Hurtbox = fragment.get_node("Hurtbox") as Hurtbox
	await _wait(5)
	_check(sprite.animation == &"walk" and sprite.is_playing() and is_equal_approx(sprite.speed_scale, 1.0),
		"patrulha: walk na velocidade original")
	hurtbox.receive_hit(1)
	_check(sprite.animation == &"hit" and sprite.frame == 0 and is_equal_approx(sprite.speed_scale, 1.0),
		"dano: hit desde o quadro 0")
	var stun_x: float = fragment.global_position.x
	var stun_ticks: int = 0
	var stun_still: bool = true
	while fragment.is_stunned() and stun_ticks < 60:
		await physics_frame
		stun_ticks += 1
		stun_still = stun_still and fragment.global_position.x == stun_x
	_check(stun_still and stun_ticks == 15, "atordoado parado durante o hit (%d ticks, esperado 15)" % stun_ticks)
	await _wait(5)
	_check(sprite.animation == &"walk" and sprite.is_playing() and fragment.global_position.x != stun_x,
		"depois do hit volta a andar (walk)")

	await _new_world()
	_floor(0.0, 420.0)
	_floor(440.0, 1000.0)
	await _spawn_terra(470.0, -1.0)
	fragment = _spawn_fragment(START_X)
	sprite = fragment.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	await _wait(6)
	_check(fragment.get_state() == LivingFragment.State.CHASE and sprite.animation == &"walk"
		and is_equal_approx(sprite.speed_scale, 2.0), "perseguição: walk no dobro da velocidade")
	await _wait(114)
	_check(fragment.get_state() == LivingFragment.State.CHASE and sprite.animation == &"idle"
		and is_equal_approx(sprite.speed_scale, 1.0), "parado na borda perseguindo: idle")

	await _new_world()
	_floor(0.0, 1000.0)
	await _spawn_terra(START_X + 60.0, -1.0)
	fragment = _spawn_fragment(START_X)
	sprite = fragment.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	hurtbox = fragment.get_node("Hurtbox") as Hurtbox
	await _wait_state(fragment, LivingFragment.State.ATTACK)
	_check(sprite.animation == &"attack" and sprite.frame == 0, "investida: attack desde o quadro 0")
	await _wait(5)
	hurtbox.receive_hit(1)
	_check(sprite.animation == &"attack", "dano durante a investida não interrompe o attack")
	await _wait(WINDUP_TICKS - 5)
	_check(absi(sprite.frame - 4) <= 1, "fim da preparação: quadro %d (esperado ~4)" % sprite.frame)
	await _wait(ACTIVE_TICKS)
	_check(absi(sprite.frame - 6) <= 1, "fim da fase ativa: quadro %d (esperado ~6)" % sprite.frame)
	await _wait(RECOVERY_TICKS + 1)
	_check(fragment.get_state() != LivingFragment.State.ATTACK and sprite.animation != &"attack",
		"fim da recuperação: sai do attack (%s)" % sprite.animation)


func _test_death() -> void:
	print("-- Morte")
	await _new_world()
	_floor(0.0, 1000.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var hurtbox: Hurtbox = fragment.get_node("Hurtbox") as Hurtbox
	var detection: Area2D = fragment.get_node("DetectionArea") as Area2D
	var deaths: Array[int] = [0]
	(fragment.get_node("HealthComponent") as HealthComponent).died.connect(func() -> void: deaths[0] += 1)
	await _wait(10)
	for i: int in 3:
		hurtbox.receive_hit(1)
	var death_position: Vector2 = fragment.global_position
	_check(deaths[0] == 1 and fragment.is_dead() and fragment.get_state() == LivingFragment.State.DEAD,
		"3 golpes: morre (died uma vez)")
	var death_sprite: AnimatedSprite2D = fragment.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	_check(death_sprite.animation == &"death" and death_sprite.is_playing() and death_sprite.frame == 0,
		"animação death começa do quadro 0")
	hurtbox.receive_hit(1)
	_check(deaths[0] == 1 and _hp(fragment) == 0, "golpes após a morte são ignorados")
	await physics_frame
	_check(not hurtbox.monitorable and not detection.monitoring, "Hurtbox e detecção desligadas")
	var still: bool = true
	var ticks: int = 0
	while _is_alive(fragment) and ticks < 60:
		still = still and fragment.global_position == death_position
		ticks += 1
		await physics_frame
	_check(still, "não se move depois de morrer")
	# death: 6 quadros a 10 fps = 0,6 s (36 ticks), com folga para o ritmo de process/physics.
	_check(not _is_alive(fragment) and ticks >= 30 and ticks <= 44,
		"some ao fim da animação de morte (%d ticks)" % ticks)


func _test_death_during_windup() -> void:
	print("-- Morte durante a preparação")
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 30.0, -1.0)
	var fragment: LivingFragment = _spawn_fragment(START_X)
	var hitbox: Hitbox = fragment.get_node("Visuals/Hitbox") as Hitbox
	await _wait_state(fragment, LivingFragment.State.ATTACK)
	await _wait(5)
	(fragment.get_node("HealthComponent") as HealthComponent).take_damage(3)
	var activated: bool = false
	while _is_alive(fragment):
		activated = activated or hitbox.is_active()
		await physics_frame
	await _wait(40)
	_check(not activated and _hp(terra) == 5, "morto na preparação: a investida nunca acerta")


func _test_training_dummy() -> void:
	print("-- TrainingDummy")
	await _new_world()
	_floor(0.0, 1000.0)
	var dummy: Node2D = _dummy_scene.instantiate() as Node2D
	dummy.position = Vector2(START_X, FLOOR_Y)
	_world.add_child(dummy)
	await _wait(2)
	var hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
	var visuals: Polygon2D = dummy.get_node("Visuals") as Polygon2D
	hurtbox.receive_hit(1)
	_check(_hp(dummy) == 2 and visuals.modulate.r > 1.0, "golpe: -1 e pisca")
	hurtbox.receive_hit(1)
	_check(_hp(dummy) == 1, "sem invulnerabilidade: o golpe seguinte também conta")
	await _wait(10)
	_check(visuals.modulate.is_equal_approx(Color.WHITE) and dummy.global_position == Vector2(START_X, FLOOR_Y),
		"volta à cor normal e continua parado")
	hurtbox.receive_hit(1)
	await physics_frame
	_check(not hurtbox.monitorable, "ao morrer, deixa de receber golpes")
	var ticks: int = 0
	while _is_alive(dummy) and ticks < 60:
		ticks += 1
		await physics_frame
	_check(not _is_alive(dummy) and ticks <= 8, "some depois do piscar (%d ticks)" % ticks)


# --- Auxiliares -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _wait_until(condition: Callable, max_ticks: int) -> void:
	for i: int in max_ticks:
		if condition.call():
			return
		await physics_frame


func _wait_state(fragment: LivingFragment, state: LivingFragment.State, max_ticks: int = 120) -> void:
	for i: int in max_ticks:
		if fragment.get_state() == state:
			return
		await physics_frame


## A entrada simulada só é vista no tick seguinte ao press; ao retornar, o efeito já ocorreu.
func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack", "ability"]:
		Input.action_release(action)


func _new_world() -> void:
	_release_all()
	if _world != null:
		_world.free()
	_world = Node2D.new()
	root.add_child(_world)
	await physics_frame


func _box(left: float, top: float, right: float, bottom: float, layer: int = LAYER_WORLD,
		one_way: bool = false) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = Vector2((left + right) / 2.0, (top + bottom) / 2.0)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(right - left, bottom - top)
	shape.shape = rect
	shape.one_way_collision = one_way
	body.add_child(shape)
	_world.add_child(body)
	return body


func _floor(left: float, right: float) -> StaticBody2D:
	return _box(left, FLOOR_Y, right, FLOOR_Y + 32.0)


func _spawn_fragment(x: float, feet_y: float = FLOOR_Y) -> LivingFragment:
	var fragment: LivingFragment = _fragment_scene.instantiate() as LivingFragment
	fragment.position = Vector2(x, feet_y)
	_world.add_child(fragment)
	return fragment


func _spawn_terra(x: float, facing: float, feet_y: float = FLOOR_Y) -> PlayerCharacter:
	var terra: PlayerCharacter = _terra_scene.instantiate() as PlayerCharacter
	terra.position = Vector2(x, feet_y)
	_world.add_child(terra)
	_set_terra_facing(terra, facing)
	await _wait(2)
	return terra


func _set_terra_facing(terra: PlayerCharacter, facing: float) -> void:
	(terra.get_node("Visuals") as Node2D).scale.x = facing


func _hp(entity: Node) -> int:
	return (entity.get_node("HealthComponent") as HealthComponent).current_health


func _is_alive(node: Variant) -> bool:
	return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()


## Acompanha o Fragmento por alguns ticks: extremos de posição e se ficou sempre no chão.
func _track(fragment: LivingFragment, ticks: int) -> Dictionary:
	var result: Dictionary = {
		"min_x": fragment.global_position.x, "max_x": fragment.global_position.x,
		"max_y": fragment.global_position.y, "always_on_floor": true,
	}
	await physics_frame
	for i: int in ticks:
		await physics_frame
		result.min_x = minf(result.min_x, fragment.global_position.x)
		result.max_x = maxf(result.max_x, fragment.global_position.x)
		result.max_y = maxf(result.max_y, fragment.global_position.y)
		result.always_on_floor = result.always_on_floor and fragment.is_on_floor()
	return result


## Corre para a direita e pula; opcionalmente começa invulnerável.
func _record_terra_run(invulnerable: bool) -> Array[Vector2]:
	await _new_world()
	_floor(0.0, 1000.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X, 1.0)
	await _wait(10)
	if invulnerable:
		terra.get_hurtbox().receive_hit(1)
	var path: Array[Vector2] = []
	Input.action_press("move_right")
	for i: int in 30:
		if i == 10:
			Input.action_press("jump")
		if i == 16:
			Input.action_release("jump")
		await physics_frame
		path.append(terra.global_position)
	_release_all()
	return path


func _same_path(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i: int in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true
