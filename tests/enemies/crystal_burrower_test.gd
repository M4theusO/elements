extends SceneTree
## Teste automatizado do Escavador de Cristal (CrystalBurrower), etapas 2 e 3: cena, IDLE/PATROL,
## território, paredes, bordas, detecção frontal, dano, morte provisória e o ataque
## (CHARGE → DASH → STUNNED → recarga), incluindo fins antecipados e morte em cada fase.
## Cada caso monta um cenário próprio em código.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/enemies/crystal_burrower_test.gd

const BURROWER_PATH: String = "res://entities/enemies/crystal_burrower/crystal_burrower.tscn"
const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"

const FLOOR_Y: float = 400.0
const START_X: float = 400.0
const HALF_WIDTH: float = 16.0
const IDLE_TICKS: int = 60
const PATROL_SPEED: float = 25.0
const TERRITORY: float = 64.0
const LAYER_WORLD: int = 1
const LAYER_PLATFORMS: int = 2
## Pausa longa: mantém o Escavador parado nos testes de detecção.
const LONG_IDLE: float = 100.0
## A lista de sobreposições da Area2D é atualizada no passo de física seguinte: ~2 ticks até a leitura.
const DETECTION_TICKS: int = 4
## Ataque a 60 ticks/s: preparação 0,6 s, investida 0,75 s a 180 px/s (3 px/tick), vulnerável 1,2 s, recarga 1 s.
const CHARGE_TICKS: int = 36
const DASH_TICKS: int = 45
const DASH_STEP: float = 3.0
const DASH_RANGE: float = 135.0
const STUN_TICKS: int = 72
const COOLDOWN_TICKS: int = 60
## Recarga longa: mantém os testes de detecção sem iniciar ataques.
const LONG_COOLDOWN: float = 100.0
## Pulo sobre a investida: a Terra (100 px à frente) pula quando o Escavador já andou isto,
## e segura o botão por estes ticks (pulo completo).
const JUMP_TRIGGER_DX: float = 50.0
const JUMP_HOLD_TICKS: int = 20

var _failures: int = 0
var _checks: int = 0
var _world: Node2D
var _burrower_scene: PackedScene
var _terra_scene: PackedScene


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Escavador de Cristal")
	await process_frame
	_burrower_scene = load(BURROWER_PATH) as PackedScene
	_terra_scene = load(TERRA_PATH) as PackedScene
	_check_static_configuration()

	await _test_initial_idle()
	await _test_patrol_territory()
	await _test_patrol_wall()
	await _test_patrol_edge()
	await _test_gravity()
	await _test_front_detection()
	await _test_detection_facing_left()
	await _test_detection_height()
	await _test_line_of_sight()
	await _test_detection_keeps_patrol()
	await _test_damage()
	await _test_death()

	_check_attack_configuration()
	await _test_full_attack_cycle()
	await _test_charge_from_patrol()
	await _test_no_attack_from_behind()
	await _test_no_charge_in_air()
	await _test_locked_direction()
	await _test_dash_wall()
	await _test_dash_edge()
	await _test_jump_over_dash()
	await _test_no_damage_outside_dash()
	await _test_cooldown_and_new_attack()
	await _test_death_in_charge()
	await _test_death_in_dash()
	await _test_death_in_stunned()

	if _world != null:
		_world.free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração ---------------------------------------------------------------

func _check_static_configuration() -> void:
	print("-- Configuração")
	var burrower: CrystalBurrower = _burrower_scene.instantiate() as CrystalBurrower
	_check(burrower != null and burrower is Enemy, "cena instancia um CrystalBurrower (Enemy)")
	_check(burrower.collision_layer == 8 and burrower.collision_mask == 67,
		"corpo: layer enemies | mask world, platforms, destructibles")
	var body_shape: CollisionShape2D = burrower.get_node("CollisionShape2D") as CollisionShape2D
	_check((body_shape.shape as RectangleShape2D).size == Vector2(32, 20) and body_shape.position == Vector2(0, -10),
		"corpo 32x20 apoiado na origem (pés)")
	var hurtbox: Hurtbox = burrower.get_node("Hurtbox") as Hurtbox
	var health: HealthComponent = burrower.get_node("HealthComponent") as HealthComponent
	var hurt_shape: CollisionShape2D = hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	_check(hurtbox.collision_layer == 32 and hurtbox.collision_mask == 0 and not hurtbox.monitoring
		and hurtbox.health == health and is_zero_approx(hurtbox.invulnerability_time),
		"Hurtbox na layer enemy_hurtbox, sem mask, sem invulnerabilidade")
	_check((hurt_shape.shape as RectangleShape2D).size == Vector2(34, 28) and hurt_shape.position == Vector2(0, -14),
		"Hurtbox 34x28 apoiada nos pés (alcança o soco da Terra, y -36..-20)")
	_check(health.max_health == 5, "5 de vida")
	var detection: Area2D = burrower.get_node("Visuals/DetectionArea") as Area2D
	var det_shape: CollisionShape2D = detection.get_node("CollisionShape2D") as CollisionShape2D
	_check(detection.collision_layer == 0 and detection.collision_mask == 4 and detection.monitoring
		and not detection.monitorable, "DetectionArea dentro de Visuals (vira junto): mask player")
	_check((det_shape.shape as RectangleShape2D).size == Vector2(128, 40) and det_shape.position == Vector2(64, -20),
		"detecção 128x40 só à frente (x 0..128, y -40..0)")
	_check(is_equal_approx(burrower.patrol_speed, 25.0) and is_equal_approx(burrower.patrol_distance, 64.0)
		and is_equal_approx(burrower.idle_time, 1.0), "patrulha 25 px/s, território ±64 px, pausa 1 s")
	_check(burrower.ground_mask == LAYER_WORLD | LAYER_PLATFORMS and burrower.sight_mask == 65,
		"ground_mask world + platforms; sight_mask world + destructibles")
	_check(burrower.get_node_or_null("Visuals/AnimatedSprite2D") == null
		and burrower.get_node("Visuals/Body") is Polygon2D and burrower.get_node("Visuals/Crystals") is Polygon2D
		and burrower.get_node("Visuals/Eye") is Polygon2D, "visual provisório: Polygon2D (corpo, cristais, olho)")
	_check(CrystalBurrower.State.keys() == ["IDLE", "PATROL", "CHARGE", "DASH", "STUNNED", "DEAD"],
		"estados: IDLE, PATROL, CHARGE, DASH, STUNNED, DEAD")
	burrower.free()


# --- Pausa e patrulha -------------------------------------------------------------

func _test_initial_idle() -> void:
	print("-- Estado inicial e pausa")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	_check(burrower.get_state() == CrystalBurrower.State.IDLE and _hp(burrower) == 5 and burrower.get_facing() == 1.0,
		"começa em IDLE, 5 de vida, olhando para a direita")
	var idle_ticks: int = 0
	var idle_moved: bool = false
	for i: int in 120:
		await physics_frame
		if burrower.get_state() != CrystalBurrower.State.IDLE:
			break
		idle_ticks += 1
		idle_moved = idle_moved or not is_equal_approx(burrower.global_position.x, START_X)
	# A pausa inicial começa no _ready, antes do primeiro tick: 1 tick a menos que a pausa nos limites.
	_check(absi(idle_ticks - IDLE_TICKS) <= 1 and not idle_moved, "pausa inicial de ~1 s parado (%d ticks)" % idle_ticks)
	_check(burrower.get_state() == CrystalBurrower.State.PATROL and burrower.get_facing() == 1.0,
		"depois da pausa inicial: PATROL, sem virar")
	var x0: float = burrower.global_position.x
	await _wait(60)
	_check(absf(burrower.global_position.x - x0 - PATROL_SPEED) < 0.5,
		"patrulha a 25 px/s (%.2f px em 1 s)" % (burrower.global_position.x - x0))


func _test_patrol_territory() -> void:
	print("-- Território")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	var track: Dictionary = {"max_x": START_X, "always_on_floor": true}
	await _wait(IDLE_TICKS + 5)
	while burrower.get_state() == CrystalBurrower.State.PATROL:
		await physics_frame
		track.max_x = maxf(track.max_x, burrower.global_position.x)
		track.always_on_floor = track.always_on_floor and burrower.is_on_floor()
	_check(burrower.get_state() == CrystalBurrower.State.IDLE
		and absf(burrower.global_position.x - (START_X + TERRITORY)) < 0.05 and burrower.get_facing() == 1.0,
		"para exatamente no limite direito (x %.2f), ainda olhando para a direita" % burrower.global_position.x)
	var stop_x: float = burrower.global_position.x
	var idle_ticks: int = 0
	while burrower.get_state() == CrystalBurrower.State.IDLE and idle_ticks < 200:
		await physics_frame
		idle_ticks += 1
	_check(idle_ticks == IDLE_TICKS and burrower.get_facing() == -1.0,
		"pausa de 1 s no limite (%d ticks) e só então vira para a esquerda" % idle_ticks)
	var rest: Dictionary = await _track(burrower, 2 * 64 * 60 / 25 + 2 * IDLE_TICKS + 60)
	_check(absf(stop_x - (START_X + TERRITORY)) < 0.05 and rest.min_x >= START_X - TERRITORY - 0.05
		and rest.max_x <= START_X + TERRITORY + 0.05 and track.max_x <= START_X + TERRITORY + 0.05,
		"fica dentro do território (x %.2f..%.2f)" % [rest.min_x, rest.max_x])
	_check(rest.min_x <= START_X - TERRITORY + 0.05, "alcança o limite esquerdo e volta")
	_check(track.always_on_floor and rest.always_on_floor, "sempre no chão")


func _test_patrol_wall() -> void:
	print("-- Paredes")
	await _new_world()
	_floor(0.0, 1000.0)
	_box(START_X + 30.0, FLOOR_Y - 64.0, START_X + 46.0, FLOOR_Y)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	var track: Dictionary = await _track(burrower, IDLE_TICKS + 90)
	_check(track.max_x <= START_X + 30.0 - HALF_WIDTH + 0.05, "não atravessa a parede (x máx %.2f)" % track.max_x)
	_check(burrower.get_state() == CrystalBurrower.State.IDLE or burrower.get_facing() == -1.0,
		"parede: para em IDLE e vira depois da pausa")
	await _wait(IDLE_TICKS + 30)
	_check(burrower.get_facing() == -1.0 and burrower.global_position.x < START_X + 30.0 - HALF_WIDTH - 1.0,
		"depois da pausa volta para a esquerda")


func _test_patrol_edge() -> void:
	print("-- Bordas")
	await _new_world()
	_floor(0.0, START_X + 30.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	var track: Dictionary = await _track(burrower, IDLE_TICKS + 90)
	_check(track.always_on_floor and track.max_x <= START_X + 30.0 - HALF_WIDTH + 1.0,
		"não sai da borda (x máx %.2f, borda em %.0f)" % [track.max_x, START_X + 30.0])
	await _wait(IDLE_TICKS + 30)
	_check(burrower.get_facing() == -1.0 and burrower.is_on_floor(), "borda: pausa e vira, sem cair")

	# Plataforma one-way também conta como chão.
	await _new_world()
	_box(START_X - 100.0, FLOOR_Y, START_X + 30.0, FLOOR_Y + 8.0, LAYER_PLATFORMS, true)
	burrower = _spawn_burrower(START_X)
	track = await _track(burrower, 2 * IDLE_TICKS + 200)
	_check(track.always_on_floor and track.max_x <= START_X + 30.0 - HALF_WIDTH + 1.0
		and track.min_x >= START_X - 100.0 + HALF_WIDTH - 1.0, "patrulha numa plataforma one-way sem cair")


func _test_gravity() -> void:
	print("-- Gravidade")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y - 60.0, 0.0)
	var x0: float = burrower.global_position.x
	var drift: float = 0.0
	for i: int in 60:
		await physics_frame
		if not burrower.is_on_floor():
			drift = maxf(drift, absf(burrower.global_position.x - x0))
	_check(burrower.is_on_floor() and absf(burrower.global_position.y - FLOOR_Y) < 0.5 and is_zero_approx(drift),
		"cai até o chão sem andar no ar (y %.2f, deslocamento no ar %.2f)" % [burrower.global_position.y, drift])


# --- Detecção -----------------------------------------------------------------------

func _test_front_detection() -> void:
	print("-- Detecção frontal")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	_hold_attacks(burrower)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0)
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected() and burrower.get_detected_target() == terra, "Terra 60 px à frente: detectada")
	terra.global_position.x = START_X + 120.0
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected(), "Terra a 120 px à frente: detectada")
	terra.global_position.x = START_X + 150.0
	await _wait(DETECTION_TICKS)
	_check(not burrower.is_target_detected(), "Terra a 150 px à frente: fora do alcance")
	terra.global_position.x = START_X - 60.0
	await _wait(DETECTION_TICKS)
	_check(not burrower.is_target_detected() and burrower.get_detected_target() == null,
		"Terra 60 px atrás: não detectada (carapaça de costas)")
	terra.global_position.x = START_X - 12.0
	await _wait(DETECTION_TICKS)
	_check(not burrower.is_target_detected(), "Terra encostada atrás: não detectada")
	terra.global_position.x = START_X + 60.0
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected(), "volta à frente: detectada de novo")


func _test_detection_facing_left() -> void:
	print("-- Detecção acompanha o lado")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	_hold_attacks(burrower)
	burrower._set_facing(-1.0)
	var terra: PlayerCharacter = await _spawn_terra(START_X - 60.0)
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected(), "olhando para a esquerda: Terra à esquerda detectada")
	terra.global_position.x = START_X + 60.0
	await _wait(DETECTION_TICKS)
	_check(not burrower.is_target_detected(), "olhando para a esquerda: Terra à direita (costas) não detectada")


func _test_detection_height() -> void:
	print("-- Altura da detecção")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	_hold_attacks(burrower)
	# Plataforma baixa (24 px): dentro da altura de 40 px.
	_box(START_X + 40.0, FLOOR_Y - 24.0, START_X + 100.0, FLOOR_Y - 16.0, LAYER_PLATFORMS, true)
	# Plataforma alta (48 px): acima da área.
	_box(START_X + 40.0, FLOOR_Y - 48.0, START_X + 100.0, FLOOR_Y - 40.0, LAYER_PLATFORMS, true)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 70.0, FLOOR_Y - 24.0)
	await _wait(4)
	_check(terra.is_on_floor() and burrower.is_target_detected(), "Terra 24 px acima, à frente: detectada")
	terra.global_position = Vector2(START_X + 70.0, FLOOR_Y - 48.0)
	await _wait(4)
	_check(terra.is_on_floor() and is_equal_approx(terra.global_position.y, FLOOR_Y - 48.0)
		and not burrower.is_target_detected(), "Terra 48 px acima, à frente: fora da altura")


func _test_line_of_sight() -> void:
	print("-- Linha de visão")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	_hold_attacks(burrower)
	var wall: StaticBody2D = _box(START_X + 40.0, FLOOR_Y - 64.0, START_X + 48.0, FLOOR_Y)
	await _spawn_terra(START_X + 90.0)
	await _wait(DETECTION_TICKS)
	_check(not burrower.is_target_detected(), "parede entre os dois: não detectada")
	wall.free()
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected(), "sem a parede: detectada")
	# Plataformas one-way não bloqueiam a visão.
	_box(START_X + 40.0, FLOOR_Y - 20.0, START_X + 48.0, FLOOR_Y - 8.0, LAYER_PLATFORMS, true)
	await _wait(DETECTION_TICKS)
	_check(burrower.is_target_detected(), "plataforma one-way no caminho: não bloqueia")


func _test_detection_keeps_patrol() -> void:
	print("-- Detecção durante a recarga não inicia ataques")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	_hold_attacks(burrower)
	await _spawn_terra(START_X + 100.0)
	var detected: bool = false
	var other_state: bool = false
	for i: int in IDLE_TICKS + 60:
		await physics_frame
		detected = detected or burrower.is_target_detected()
		var state: CrystalBurrower.State = burrower.get_state()
		other_state = other_state or (state != CrystalBurrower.State.IDLE and state != CrystalBurrower.State.PATROL)
	_check(detected and not other_state and burrower.global_position.x > START_X + 20.0,
		"vê a Terra e segue entre IDLE e PATROL, andando normalmente")


# --- Dano e morte -------------------------------------------------------------------

func _test_damage() -> void:
	print("-- Dano recebido")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	await _wait(IDLE_TICKS + 10)
	var hurtbox: Hurtbox = burrower.get_node("Hurtbox") as Hurtbox
	hurtbox.receive_hit(1)
	var visuals: Node2D = burrower.get_node("Visuals") as Node2D
	_check(_hp(burrower) == 4 and visuals.modulate.r > 1.0, "1 de dano: vida 4 e clarão")
	var x0: float = burrower.global_position.x
	await _wait(20)
	_check(burrower.get_state() == CrystalBurrower.State.PATROL and burrower.global_position.x > x0
		and visuals.modulate.is_equal_approx(Color.WHITE), "o golpe não interrompe a patrulha; clarão some")

	# Soco real da Terra alcança a hurtbox.
	await _new_world()
	_floor(0.0, 1000.0)
	burrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	await _spawn_terra(START_X - 20.0)
	await _press("attack")
	await _wait(20)
	_check(_hp(burrower) == 4, "soco da Terra acerta o Escavador")


func _test_death() -> void:
	print("-- Morte")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	_hold_attacks(burrower)
	var hurtbox: Hurtbox = burrower.get_node("Hurtbox") as Hurtbox
	var health: HealthComponent = burrower.get_node("HealthComponent") as HealthComponent
	var deaths: Array[int] = [0]
	health.died.connect(func() -> void: deaths[0] += 1)
	await _spawn_terra(START_X + 60.0)
	await _wait(IDLE_TICKS + 10)
	hurtbox.receive_hit(10)
	_check(deaths[0] == 1 and _hp(burrower) == 0 and burrower.is_dead()
		and burrower.get_state() == CrystalBurrower.State.DEAD and not burrower.is_target_detected(),
		"dano excedente: vida 0, died uma vez, estado DEAD, sem alvo")
	var x0: float = burrower.global_position.x
	await physics_frame
	hurtbox.receive_hit(1)
	_check(deaths[0] == 1 and _hp(burrower) == 0 and not hurtbox.monitorable
		and is_equal_approx(burrower.global_position.x, x0) and not burrower.is_physics_processing(),
		"morto: parado, sem física, hurtbox desligada, golpes ignorados")
	var ticks: int = 0
	while _is_alive(burrower) and ticks < 60:
		await physics_frame
		ticks += 1
	_check(not _is_alive(burrower) and ticks <= 10, "some depois do piscar (%d ticks)" % ticks)


# --- Ataque (etapa 3) ---------------------------------------------------------------

func _check_attack_configuration() -> void:
	print("-- Configuração do ataque")
	var burrower: CrystalBurrower = _burrower_scene.instantiate() as CrystalBurrower
	var melee: MeleeAttack = burrower.get_node("MeleeAttack") as MeleeAttack
	var hitbox: Hitbox = burrower.get_node("Visuals/Hitbox") as Hitbox
	var data: AttackData = melee.attack
	_check(data != null and data.resource_path.ends_with("crystal_burrower_dash.tres") and data.damage == 1
		and is_equal_approx(data.windup_time, 0.6) and is_equal_approx(data.active_time, 0.75)
		and is_equal_approx(data.recovery_time, 1.2),
		"AttackData próprio: dano 1, preparação 0,6 s, investida até 0,75 s, vulnerável 1,2 s")
	_check(melee.hitbox == hitbox, "MeleeAttack controla a Visuals/Hitbox (vira junto)")
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D") as CollisionShape2D
	_check(hitbox.collision_layer == 0 and hitbox.collision_mask == 16 and not hitbox.monitoring
		and not hitbox.show_debug, "Hitbox sem layer, mask player_hurtbox, desligada, sem desenho de depuração")
	_check((shape.shape as RectangleShape2D).size == Vector2(28, 14) and shape.position == Vector2(4, -8),
		"Hitbox 28x14 baixa, cobrindo o corpo (x -10..18, y -15..-1)")
	_check(is_equal_approx(burrower.dash_speed, 180.0) and is_equal_approx(burrower.cooldown_time, 1.0)
		and is_equal_approx(burrower.dash_speed * data.active_time, DASH_RANGE),
		"investida 180 px/s (alcance teórico 135 px), recarga 1 s")
	burrower.free()


func _test_full_attack_cycle() -> void:
	print("-- Ciclo completo: CHARGE → DASH → STUNNED → IDLE")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var hitbox: Hitbox = _hitbox_of(burrower)
	var hits: Array[int] = [0]
	hitbox.hit_landed.connect(func(_hurtbox: Hurtbox) -> void: hits[0] += 1)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 80.0)
	var waited: int = await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	_check(waited >= 0 and burrower.get_facing() == 1.0 and is_zero_approx(burrower.velocity.x),
		"Terra à frente: entra em CHARGE, parado e olhando para ela (%d ticks)" % waited)
	var charge: Dictionary = await _measure_state(burrower, CrystalBurrower.State.CHARGE)
	_check(charge.ticks == CHARGE_TICKS, "preparação de 0,6 s (%d ticks)" % charge.ticks)
	_check(is_equal_approx(charge.min_x, START_X) and is_equal_approx(charge.max_x, START_X),
		"parado durante a preparação")
	_check(not charge.hitbox_on and _hp(terra) == 5 and hits[0] == 0, "hitbox desligada em toda a preparação; sem dano")
	_check(charge.colors.has(CrystalBurrower.CRYSTAL_CHARGE) and charge.colors.has(CrystalBurrower.CRYSTAL_NORMAL),
		"cristais piscam na preparação")
	_check(burrower.get_state() == CrystalBurrower.State.DASH and hitbox.is_active(),
		"CHARGE → DASH no tick em que a hitbox liga")
	var dash: Dictionary = await _measure_state(burrower, CrystalBurrower.State.DASH)
	var distance: float = dash.last_x - charge.last_x
	_check(dash.ticks == DASH_TICKS, "duração máxima de 0,75 s (%d ticks)" % dash.ticks)
	_check(absf(distance - DASH_RANGE) < 0.5, "percorre ~135 px (%.2f px)" % distance)
	_check(is_equal_approx(dash.min_step, DASH_STEP) and is_equal_approx(dash.max_step, DASH_STEP),
		"180 px/s constantes (%.2f..%.2f px por tick)" % [dash.min_step, dash.max_step])
	_check(dash.hitbox_all_on and dash.colors == [CrystalBurrower.CRYSTAL_DASH],
		"hitbox ligada em toda a investida; cristais no brilho intenso")
	_check(_hp(terra) == 4 and hits[0] == 1 and dash.last_x > terra.global_position.x + HALF_WIDTH,
		"atravessa a Terra e causa 1 de dano, um acerto só")
	_check(burrower.get_state() == CrystalBurrower.State.STUNNED and not hitbox.is_active(),
		"tempo máximo: STUNNED com a hitbox desligada")
	var stun: Dictionary = await _measure_state(burrower, CrystalBurrower.State.STUNNED)
	_check(stun.ticks == STUN_TICKS, "vulnerável por 1,2 s (%d ticks)" % stun.ticks)
	_check(is_equal_approx(stun.min_x, dash.last_x) and is_equal_approx(stun.max_x, dash.last_x)
		and not stun.hitbox_on and stun.colors == [CrystalBurrower.CRYSTAL_STUNNED],
		"STUNNED: parado, hitbox desligada, cristais apagados")
	_check(burrower.get_state() == CrystalBurrower.State.IDLE and not burrower.is_attack_ready()
		and _crystals_of(burrower).self_modulate == CrystalBurrower.CRYSTAL_NORMAL,
		"STUNNED → IDLE, recarga começando, cristais normais")
	_check(_hp(terra) == 4 and hits[0] == 1, "um único acerto no ataque inteiro")


func _test_charge_from_patrol() -> void:
	print("-- CHARGE a partir da patrulha")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	await _spawn_terra(START_X + 150.0)
	var previous: CrystalBurrower.State = burrower.get_state()
	var found: bool = false
	for i: int in IDLE_TICKS + 120:
		await physics_frame
		if burrower.get_state() == CrystalBurrower.State.CHARGE:
			found = true
			break
		previous = burrower.get_state()
	_check(found and previous == CrystalBurrower.State.PATROL, "Terra entra na visão durante a patrulha: PATROL → CHARGE")
	var x0: float = burrower.global_position.x
	await _wait(10)
	_check(burrower.get_state() == CrystalBurrower.State.CHARGE and is_equal_approx(burrower.global_position.x, x0),
		"para completamente ao preparar")


func _test_no_attack_from_behind() -> void:
	print("-- Sem ataque com a Terra atrás")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
	await _spawn_terra(START_X - 40.0)
	var attacked: bool = false
	for i: int in IDLE_TICKS + 90:
		await physics_frame
		attacked = attacked or burrower.get_state() == CrystalBurrower.State.CHARGE
	_check(not attacked and burrower.get_state() == CrystalBurrower.State.PATROL, "Terra 40 px atrás: segue patrulhando")

	await _new_world()
	_floor(0.0, 1000.0)
	burrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X - 12.0)
	await _wait(60)
	_check(burrower.get_state() == CrystalBurrower.State.IDLE and burrower.get_facing() == 1.0 and _hp(terra) == 5,
		"Terra encostada atrás: sem ataque, sem virar, sem dano")


func _test_no_charge_in_air() -> void:
	print("-- Sem CHARGE no ar")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y - 60.0, LONG_IDLE)
	await _spawn_terra(START_X + 60.0)
	var charged_in_air: bool = false
	var detected_in_air: bool = false
	var charged: bool = false
	for i: int in 60:
		await physics_frame
		var in_air: bool = not burrower.is_on_floor()
		detected_in_air = detected_in_air or (in_air and burrower.is_target_detected())
		charged_in_air = charged_in_air or (in_air and burrower.get_state() == CrystalBurrower.State.CHARGE)
		charged = charged or burrower.get_state() == CrystalBurrower.State.CHARGE
	_check(detected_in_air and not charged_in_air, "vê a Terra caindo, mas não prepara no ar")
	_check(charged, "prepara depois de pousar")


func _test_locked_direction() -> void:
	print("-- Direção travada")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 80.0)
	await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	# A Terra passa para trás do Escavador durante a preparação.
	terra.global_position = Vector2(START_X - 60.0, FLOOR_Y)
	var charge: Dictionary = await _measure_state(burrower, CrystalBurrower.State.CHARGE)
	_check(not charge.facing_changed and burrower.get_facing() == 1.0, "Terra passa para trás na preparação: não vira")
	var dash: Dictionary = await _measure_state(burrower, CrystalBurrower.State.DASH)
	_check(not dash.facing_changed and dash.last_x > START_X + DASH_RANGE - 1.0 and _hp(terra) == 5,
		"a investida segue para a direita até o fim (x %.2f), longe da Terra" % dash.last_x)


func _test_dash_wall() -> void:
	print("-- Investida contra parede")
	await _new_world()
	_floor(0.0, 1000.0)
	var wall_x: float = START_X + 70.0
	_box(wall_x, FLOOR_Y - 64.0, wall_x + 16.0, FLOOR_Y)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var hitbox: Hitbox = _hitbox_of(burrower)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 40.0)
	await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	var charge: Dictionary = await _measure_state(burrower, CrystalBurrower.State.CHARGE)
	var dash: Dictionary = await _measure_state(burrower, CrystalBurrower.State.DASH)
	_check(dash.ticks < DASH_TICKS and dash.max_x <= wall_x - HALF_WIDTH + 0.05,
		"para na parede (x %.2f) antes do tempo máximo (%d ticks)" % [dash.max_x, dash.ticks])
	_check(burrower.get_state() == CrystalBurrower.State.STUNNED and not hitbox.is_active(),
		"parede: STUNNED com a hitbox desligada no mesmo tick")
	var stun: Dictionary = await _measure_state(burrower, CrystalBurrower.State.STUNNED)
	_check(stun.ticks == STUN_TICKS and not stun.hitbox_on,
		"recuperação completa depois da parede: 1,2 s (%d ticks)" % stun.ticks)
	_check(charge.ticks == CHARGE_TICKS and _hp(terra) == 4, "a Terra entre ele e a parede leva 1 de dano")


func _test_dash_edge() -> void:
	print("-- Investida diante de borda")
	await _new_world()
	var edge_x: float = START_X + 60.0
	_floor(0.0, edge_x)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	await _spawn_terra(START_X + 30.0)
	await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	await _measure_state(burrower, CrystalBurrower.State.CHARGE)
	var dash: Dictionary = await _measure_state(burrower, CrystalBurrower.State.DASH)
	_check(dash.ticks < DASH_TICKS and dash.on_floor and dash.max_x <= edge_x - HALF_WIDTH + DASH_STEP
		and dash.max_x > edge_x - HALF_WIDTH - DASH_STEP,
		"para na borda (x %.2f, borda em %.0f), sem cair, em %d ticks" % [dash.max_x, edge_x, dash.ticks])
	_check(burrower.get_state() == CrystalBurrower.State.STUNNED and not _hitbox_of(burrower).is_active(),
		"borda: STUNNED com a hitbox desligada")
	var stun: Dictionary = await _measure_state(burrower, CrystalBurrower.State.STUNNED)
	_check(stun.ticks == STUN_TICKS and stun.on_floor, "1,2 s vulnerável, no chão (%d ticks)" % stun.ticks)


func _test_jump_over_dash() -> void:
	print("-- Terra pula sobre a investida")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 100.0)
	await _wait_state(burrower, CrystalBurrower.State.DASH, 60)
	while burrower.get_state() == CrystalBurrower.State.DASH and burrower.global_position.x < START_X + JUMP_TRIGGER_DX:
		await physics_frame
	Input.action_press("jump")
	var min_clearance: float = INF
	var held: int = 0
	while burrower.get_state() == CrystalBurrower.State.DASH:
		await physics_frame
		held += 1
		if held == JUMP_HOLD_TICKS:
			Input.action_release("jump")
		var dx: float = terra.global_position.x - burrower.global_position.x
		# Sobreposição horizontal entre a hitbox (x -10..18) e a hurtbox da Terra (±7).
		if dx >= -10.0 - 7.0 and dx <= 18.0 + 7.0:
			min_clearance = minf(min_clearance, FLOOR_Y - terra.global_position.y)
	Input.action_release("jump")
	_check(_hp(terra) == 5 and burrower.global_position.x > terra.global_position.x + HALF_WIDTH
		and min_clearance > 15.0,
		"passa por baixo da Terra no ar sem acertá-la (pés a %.1f px do chão, topo da hitbox a 15 px)" % min_clearance)


func _test_no_damage_outside_dash() -> void:
	print("-- Sem dano fora da investida")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var hits: Array[int] = [0]
	_hitbox_of(burrower).hit_landed.connect(func(_hurtbox: Hurtbox) -> void: hits[0] += 1)
	# Terra encostada na frente: dentro da área da hitbox desde o início da preparação.
	var terra: PlayerCharacter = await _spawn_terra(START_X + 8.0)
	await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	await _measure_state(burrower, CrystalBurrower.State.CHARGE)
	_check(hits[0] == 0 and _hp(terra) == 5, "sobreposta durante a preparação inteira: sem dano")
	await _wait_state(burrower, CrystalBurrower.State.STUNNED, 60)
	_check(hits[0] == 1 and _hp(terra) == 4, "a investida acerta uma vez")
	# Terra em cima do Escavador vulnerável (a invulnerabilidade dela acaba no meio do STUNNED).
	terra.global_position = Vector2(burrower.global_position.x + 4.0, FLOOR_Y)
	await _measure_state(burrower, CrystalBurrower.State.STUNNED)
	_check(hits[0] == 1 and _hp(terra) == 4, "sobreposta durante STUNNED: sem dano")
	await _wait(30)
	_check(hits[0] == 1 and _hp(terra) == 4 and burrower.get_state() == CrystalBurrower.State.IDLE,
		"sobreposta em IDLE: sem dano por contato")


func _test_cooldown_and_new_attack() -> void:
	print("-- Recarga e nova investida")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 80.0)
	await _wait_state(burrower, CrystalBurrower.State.STUNNED, 120)
	var x: float = burrower.global_position.x
	terra.global_position = Vector2(x - 60.0, FLOOR_Y)
	await _wait(20)
	_check(burrower.get_state() == CrystalBurrower.State.STUNNED and burrower.get_facing() == 1.0
		and not burrower.is_target_detected(), "STUNNED: não vira para a Terra atrás")
	terra.global_position = Vector2(x + 60.0, FLOOR_Y)
	await _wait(20)
	_check(burrower.get_state() == CrystalBurrower.State.STUNNED and not burrower.is_target_detected(),
		"STUNNED: Terra à frente não inicia outro ataque")
	await _wait_state(burrower, CrystalBurrower.State.IDLE, STUN_TICKS)
	var ticks: int = 0
	var detected_waiting: bool = false
	while burrower.get_state() == CrystalBurrower.State.IDLE and ticks < 200:
		await physics_frame
		ticks += 1
		detected_waiting = detected_waiting or (burrower.is_target_detected() and not burrower.is_attack_ready())
	_check(detected_waiting, "na recarga: vê a Terra, mas não ataca")
	_check(ticks == COOLDOWN_TICKS and burrower.get_state() == CrystalBurrower.State.CHARGE,
		"recarga de 1 s contada do fim de STUNNED; depois, nova investida (%d ticks)" % ticks)


func _test_death_in_charge() -> void:
	print("-- Morte em CHARGE")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 20.0)
	await _wait_state(burrower, CrystalBurrower.State.CHARGE, 20)
	await _wait(10)
	await _kill_and_check(burrower, terra, 5, "CHARGE")


func _test_death_in_dash() -> void:
	print("-- Morte em DASH")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 60.0)
	await _wait_state(burrower, CrystalBurrower.State.DASH, 60)
	await physics_frame
	await _kill_and_check(burrower, terra, 5, "DASH")


func _test_death_in_stunned() -> void:
	print("-- Morte em STUNNED")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X, FLOOR_Y, LONG_IDLE)
	var terra: PlayerCharacter = await _spawn_terra(START_X + 80.0)
	await _wait_state(burrower, CrystalBurrower.State.STUNNED, 120)
	await _wait(10)
	await _kill_and_check(burrower, terra, 4, "STUNNED")


## Mata o Escavador e confirma que nada mais acontece: parado, hitbox e ataque desligados,
## sem novas transições nem dano à Terra até sumir.
func _kill_and_check(burrower: CrystalBurrower, terra: PlayerCharacter, terra_hp: int, label: String) -> void:
	var hitbox: Hitbox = _hitbox_of(burrower)
	var melee: MeleeAttack = burrower.get_node("MeleeAttack") as MeleeAttack
	(burrower.get_node("Hurtbox") as Hurtbox).receive_hit(10)
	_check(burrower.get_state() == CrystalBurrower.State.DEAD and is_zero_approx(burrower.velocity.x)
		and not hitbox.is_active() and melee.process_mode == Node.PROCESS_MODE_DISABLED
		and not burrower.is_physics_processing() and not burrower.is_target_detected()
		and _crystals_of(burrower).self_modulate == CrystalBurrower.CRYSTAL_NORMAL,
		"morte em %s: DEAD, parado, hitbox e ataque desligados" % label)
	var x0: float = burrower.global_position.x
	var moved: bool = false
	var other_state: bool = false
	var ticks: int = 0
	while ticks < 60:
		await physics_frame
		ticks += 1
		if not _is_alive(burrower):
			continue
		moved = moved or not is_equal_approx(burrower.global_position.x, x0)
		other_state = other_state or burrower.get_state() != CrystalBurrower.State.DEAD
		other_state = other_state or hitbox.is_active()
	_check(not moved and not other_state and _hp(terra) == terra_hp and not _is_alive(burrower),
		"morte em %s: sem movimento, transições ou dano depois; some (vida da Terra %d)" % [label, _hp(terra)])


# --- Utilidades -------------------------------------------------------------------

func _hold_attacks(burrower: CrystalBurrower) -> void:
	burrower._cooldown_left = LONG_COOLDOWN


func _hitbox_of(burrower: CrystalBurrower) -> Hitbox:
	return burrower.get_node("Visuals/Hitbox") as Hitbox


func _crystals_of(burrower: CrystalBurrower) -> CanvasItem:
	return burrower.get_node("Visuals/Crystals") as CanvasItem


## Espera até o Escavador entrar no estado (no máximo max_ticks). Retorna os ticks esperados, ou -1.
func _wait_state(burrower: CrystalBurrower, state: CrystalBurrower.State, max_ticks: int) -> int:
	var ticks: int = 0
	while _is_alive(burrower) and burrower.get_state() != state:
		if ticks >= max_ticks:
			return -1
		await physics_frame
		ticks += 1
	return ticks if _is_alive(burrower) else -1


## Acompanha o estado atual até ele terminar (deve ser chamado com o Escavador já nele).
## ticks = ticks observados no estado; last_x = posição no último deles; passos entre ticks;
## hitbox_on = ligada (ou monitorando) em algum tick; hitbox_all_on = ligada em todos;
## colors = cores distintas dos cristais.
func _measure_state(burrower: CrystalBurrower, state: CrystalBurrower.State, max_ticks: int = 300) -> Dictionary:
	var hitbox: Hitbox = _hitbox_of(burrower)
	var crystals: CanvasItem = _crystals_of(burrower)
	var facing: float = burrower.get_facing()
	var x: float = burrower.global_position.x
	var result: Dictionary = {
		"ticks": 0, "last_x": x, "min_x": x, "max_x": x, "min_step": INF, "max_step": -INF,
		"hitbox_on": false, "hitbox_all_on": true, "facing_changed": false, "colors": [], "on_floor": true,
	}
	while _is_alive(burrower) and burrower.get_state() == state and result.ticks < max_ticks:
		x = burrower.global_position.x
		if result.ticks > 0:
			var step: float = absf(x - result.last_x)
			result.min_step = minf(result.min_step, step)
			result.max_step = maxf(result.max_step, step)
		result.ticks += 1
		result.last_x = x
		result.min_x = minf(result.min_x, x)
		result.max_x = maxf(result.max_x, x)
		result.hitbox_on = result.hitbox_on or hitbox.is_active() or hitbox.monitoring
		result.hitbox_all_on = result.hitbox_all_on and hitbox.is_active()
		result.facing_changed = result.facing_changed or burrower.get_facing() != facing
		result.on_floor = result.on_floor and burrower.is_on_floor()
		if not (result.colors as Array).has(crystals.self_modulate):
			(result.colors as Array).append(crystals.self_modulate)
		await physics_frame
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


## A entrada simulada só é vista no tick seguinte ao press; ao retornar, o efeito já ocorreu.
func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _new_world() -> void:
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


## idle_time é aplicado antes de entrar na árvore (a pausa inicial começa no _ready).
func _spawn_burrower(x: float, feet_y: float = FLOOR_Y, idle_time: float = -1.0) -> CrystalBurrower:
	var burrower: CrystalBurrower = _burrower_scene.instantiate() as CrystalBurrower
	burrower.position = Vector2(x, feet_y)
	if idle_time >= 0.0:
		burrower.idle_time = idle_time
	_world.add_child(burrower)
	return burrower


func _spawn_terra(x: float, feet_y: float = FLOOR_Y) -> PlayerCharacter:
	var terra: PlayerCharacter = _terra_scene.instantiate() as PlayerCharacter
	terra.position = Vector2(x, feet_y)
	_world.add_child(terra)
	await _wait(2)
	return terra


func _hp(entity: Node) -> int:
	return (entity.get_node("HealthComponent") as HealthComponent).current_health


func _is_alive(node: Variant) -> bool:
	return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()


## Acompanha o Escavador por alguns ticks: extremos de posição e se ficou sempre no chão.
func _track(burrower: CrystalBurrower, ticks: int) -> Dictionary:
	var result: Dictionary = {
		"min_x": burrower.global_position.x, "max_x": burrower.global_position.x, "always_on_floor": true,
	}
	await physics_frame
	for i: int in ticks:
		await physics_frame
		result.min_x = minf(result.min_x, burrower.global_position.x)
		result.max_x = maxf(result.max_x, burrower.global_position.x)
		result.always_on_floor = result.always_on_floor and burrower.is_on_floor()
	return result
