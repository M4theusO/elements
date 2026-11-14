extends SceneTree
## Teste automatizado do Escavador de Cristal (CrystalBurrower), etapa 2: cena, IDLE/PATROL,
## território, paredes, bordas, detecção frontal, dano e morte provisória.
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
	print("-- Detecção não inicia ataques (etapa 2)")
	await _new_world()
	_floor(0.0, 1000.0)
	var burrower: CrystalBurrower = _spawn_burrower(START_X)
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


# --- Utilidades -------------------------------------------------------------------

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
