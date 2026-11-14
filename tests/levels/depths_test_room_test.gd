extends SceneTree
## Teste automatizado da sala de teste do Reino das Profundezas (depths_test_room.tscn):
## estrutura da cena, peças do terreno, colisão real com a Terra (chão, paredes, degraus,
## teto, plataforma one-way), onda sísmica sobre tiles e Fragmento Vivo no terreno.
## Simula entradas, como os demais testes.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/depths_test_room_test.gd

const ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const ROOM_SIZE: Vector2i = Vector2i(48, 23)
const ROCK_CELLS: int = 520
const PLATFORM_CELLS: int = 10

## Geometria da sala (px). Pés da Terra = global_position.
const FLOOR_Y: float = 320.0
const LEFT_WALL_X: float = 32.0
const STEP1_X: float = 352.0
const STEP_TOPS: Array[float] = [304.0, 288.0, 272.0]
const STEP3_RIGHT_X: float = 544.0
const WIDE_PLATFORM: Rect2 = Rect2(560, 224, 80, 8)
const HIGH_PLATFORM_Y: float = 144.0
const OVERHANG_BOTTOM_Y: float = 80.0
const TERRA_HALF_WIDTH: float = 8.0
const TERRA_HEIGHT: float = 46.0
const MAX_SPEED: float = 110.0
const WAVE_RANGE: float = 96.0
const WAVE_HALF_WIDTH: float = 16.0
const COOLDOWN_TICKS: int = 95

var _failures: int = 0
var _checks: int = 0
var _room: Node2D
var _terrain: TileMapLayer
var _terra: PlayerCharacter
var _fist: SeismicFist
var _fragment_floor: LivingFragment
var _fragment_platform: LivingFragment


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Sala de teste: Reino das Profundezas")
	await process_frame
	_room = (load(ROOM_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_room)
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_terra = _room.get_node_or_null("Terra") as PlayerCharacter
	_fragment_floor = _room.get_node_or_null("Enemies/LivingFragmentFloor") as LivingFragment
	_fragment_platform = _room.get_node_or_null("Enemies/LivingFragmentPlatform") as LivingFragment
	_test_structure()
	if _terrain == null or _terra == null or _fragment_floor == null or _fragment_platform == null:
		_finish()
		return
	_fist = _terra.get_node("SeismicFist") as SeismicFist
	_test_terrain_cells()

	await _test_settle()
	await _test_fragment_patrol()
	await _test_fragment_detection()
	_fragment_floor.queue_free()
	_fragment_platform.queue_free()
	await _wait(2)

	await _test_floor_and_walls()
	await _test_steps()
	await _test_ceiling()
	await _test_one_way()
	await _test_wave_floor()
	await _test_wave_platform_and_enemy()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Estrutura ---------------------------------------------------------------------------

func _test_structure() -> void:
	print("-- Estrutura da cena")
	_check(_terrain != null and _terrain.tile_set != null and _terrain.tile_set.resource_path == TILESET_PATH,
		"Terrain é um TileMapLayer com depths_tileset.tres")
	_check(_terrain != null and _terrain.collision_enabled, "colisão do TileMapLayer ligada")
	_check(_terra != null and _terra.scene_file_path.ends_with("terra.tscn"), "Terra instanciada")
	_check(_fragment_floor != null and _fragment_platform != null
		and _fragment_floor.scene_file_path.ends_with("living_fragment.tscn"), "2 Fragmentos Vivos em Enemies")
	if _terra == null:
		return
	_check(_terra.position == Vector2(56, FLOOR_Y), "Terra começa sobre o chão (x 56)")
	var camera: Camera2D = _terra.get_node_or_null("Camera2D") as Camera2D
	_check(camera != null and camera.limit_left == 0 and camera.limit_top == 0
		and camera.limit_right == ROOM_SIZE.x * TILE and camera.limit_bottom == ROOM_SIZE.y * TILE,
		"câmera na Terra, limites = sala (768x368)")
	# A cena não fixa propriedades das instâncias além da posição (seguem as cenas originais).
	var state: SceneState = (load(ROOM_PATH) as PackedScene).get_state()
	var extra: Array[String] = []
	for i: int in state.get_node_count():
		if state.get_node_instance(i) == null:
			continue
		for p: int in state.get_node_property_count(i):
			var prop: StringName = state.get_node_property_name(i, p)
			if prop != &"position":
				extra.append("%s.%s" % [state.get_node_name(i), prop])
	_check(extra.is_empty(), "instâncias só sobrescrevem a posição %s" % [extra])


func _test_terrain_cells() -> void:
	print("-- Peças do terreno")
	var rock: int = 0
	var platforms: int = 0
	for cell: Vector2i in _terrain.get_used_cells():
		var data: TileData = _terrain.get_cell_tile_data(cell)
		if data.terrain_set == 0:
			rock += 1
		elif data.terrain_set == 1:
			platforms += 1
	_check(rock == ROCK_CELLS and platforms == PLATFORM_CELLS, "%d células de rocha e %d de plataforma (esperado %d e %d)" % [rock, platforms, ROCK_CELLS, PLATFORM_CELLS])
	var wrong: Array[String] = []
	for cell: Vector2i in _terrain.get_used_cells():
		var expected: Vector2i = TilesetTest.expected_for(_is_rock, _is_platform, cell.x, cell.y)
		var actual: Vector2i = _base_of(_terrain.get_cell_atlas_coords(cell))
		if actual != expected:
			wrong.append("%s: %s (esperado %s)" % [cell, actual, expected])
	_check(wrong.is_empty(), "toda célula tem a peça certa para os vizinhos (sem combinações fora do conjunto) %s" % [wrong])
	var inside: bool = true
	for cell: Vector2i in _terrain.get_used_cells():
		inside = inside and cell.x >= -1 and cell.y >= -1 and cell.x <= ROOM_SIZE.x and cell.y <= ROOM_SIZE.y
	_check(inside, "terreno dentro da sala mais a moldura de 1 tile fora da câmera")


# --- Fragmento Vivo ----------------------------------------------------------------------

func _test_settle() -> void:
	print("-- Assentamento")
	await _wait(30)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5, "Terra no chão (y %.1f)" % _terra.global_position.y)
	_check(_fragment_floor.is_on_floor() and absf(_fragment_floor.global_position.y - FLOOR_Y) < 0.5,
		"Fragmento do chão apoiado (y %.1f)" % _fragment_floor.global_position.y)
	_check(_fragment_platform.is_on_floor() and absf(_fragment_platform.global_position.y - WIDE_PLATFORM.position.y) < 0.5,
		"Fragmento da plataforma one-way apoiado (y %.1f)" % _fragment_platform.global_position.y)


func _test_fragment_patrol() -> void:
	print("-- Patrulha sobre tiles (600 ticks, Terra longe)")
	var floor_min: float = INF
	var floor_max: float = -INF
	var plat_min: float = INF
	var plat_max: float = -INF
	var floor_y_ok: bool = true
	var plat_y_ok: bool = true
	for i: int in 600:
		await physics_frame
		var fx: float = _fragment_floor.global_position.x
		var px: float = _fragment_platform.global_position.x
		floor_min = minf(floor_min, fx)
		floor_max = maxf(floor_max, fx)
		plat_min = minf(plat_min, px)
		plat_max = maxf(plat_max, px)
		floor_y_ok = floor_y_ok and absf(_fragment_floor.global_position.y - FLOOR_Y) < 0.5
		plat_y_ok = plat_y_ok and absf(_fragment_platform.global_position.y - WIDE_PLATFORM.position.y) < 0.5
	_check(floor_y_ok and floor_max - floor_min > 30.0, "chão: patrulha %.0f..%.0f sem sair do chão" % [floor_min, floor_max])
	_check(plat_y_ok and plat_max - plat_min > 10.0, "plataforma: patrulha %.0f..%.0f sem cair" % [plat_min, plat_max])
	_check(plat_min >= WIDE_PLATFORM.position.x and plat_max <= WIDE_PLATFORM.end.x,
		"plataforma: centro sempre sobre a plataforma (%.0f..%.0f)" % [WIDE_PLATFORM.position.x, WIDE_PLATFORM.end.x])


func _test_fragment_detection() -> void:
	print("-- Detecção e investida sobre tiles")
	await _reset(Vector2(_fragment_floor.global_position.x - 56.0, FLOOR_Y), 1.0)
	var attacked: bool = false
	for i: int in 300:
		await physics_frame
		if _fragment_floor.get_state() == LivingFragment.State.ATTACK:
			attacked = true
			break
	_check(attacked, "Fragmento do chão vê a Terra e faz a investida")
	await _reset(Vector2(56, FLOOR_Y), 1.0)


# --- Terra: chão, paredes, degraus, teto, one-way ------------------------------------------

func _test_floor_and_walls() -> void:
	print("-- Chão e paredes")
	await _reset(Vector2(56, FLOOR_Y), 1.0)
	Input.action_press("move_right")
	var reached: bool = false
	var min_speed: float = INF
	var on_floor: bool = true
	var start_x: float = _terra.global_position.x
	var measured_from: float = 0.0
	for i: int in 400:
		await physics_frame
		var vx: float = _terra.get_real_velocity().x
		if not reached and vx >= MAX_SPEED - 0.01:
			reached = true
			measured_from = _terra.global_position.x
		if reached and _terra.global_position.x < STEP1_X - TERRA_HALF_WIDTH - 12.0:
			min_speed = minf(min_speed, vx)
			on_floor = on_floor and _terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.01
		if _terra.global_position.x >= STEP1_X - TERRA_HALF_WIDTH - 0.5 and _terra.is_on_wall():
			break
	var seams: int = int((STEP1_X - 12.0 - measured_from) / TILE)
	_check(reached and min_speed >= MAX_SPEED - 0.01, "velocidade máxima mantida sobre %d emendas de tile (mín. %.2f px/s)" % [seams, min_speed])
	_check(on_floor, "sempre no chão, y constante")
	await _wait(10)
	Input.action_release("move_right")
	_check(absf(_terra.global_position.x - (STEP1_X - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - FLOOR_Y) < 0.01,
		"degrau de 1 tile bloqueia: para em x %.1f (esperado %.1f), sem subir" % [_terra.global_position.x, STEP1_X - TERRA_HALF_WIDTH])
	_check(start_x < _terra.global_position.x, "andou da origem até o degrau")
	await _reset(Vector2(100, FLOOR_Y), -1.0)
	Input.action_press("move_left")
	await _wait(60)
	Input.action_release("move_left")
	_check(absf(_terra.global_position.x - (LEFT_WALL_X + TERRA_HALF_WIDTH)) < 0.5 and _terra.is_on_wall(),
		"parede esquerda: para em x %.1f (esperado %.1f)" % [_terra.global_position.x, LEFT_WALL_X + TERRA_HALF_WIDTH])


func _test_steps() -> void:
	print("-- Degraus (pulando)")
	await _reset(Vector2(STEP1_X - 20.0, FLOOR_Y), 1.0)
	Input.action_press("move_right")
	for k: int in 3:
		var landed_y: float = await _jump_and_land()
		_check(absf(landed_y - STEP_TOPS[k]) < 0.5, "sobe o degrau %d: pousa em y %.1f (esperado %.1f)" % [k + 1, landed_y, STEP_TOPS[k]])
	Input.action_release("move_right")


func _test_ceiling() -> void:
	print("-- Teto")
	await _reset(Vector2(624, HIGH_PLATFORM_Y), 1.0)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - HIGH_PLATFORM_Y) < 0.5, "Terra na plataforma alta (y %.1f)" % _terra.global_position.y)
	Input.action_press("jump")
	var top_feet: float = INF
	var hit_ceiling: bool = false
	for i: int in 60:
		await physics_frame
		top_feet = minf(top_feet, _terra.global_position.y)
		hit_ceiling = hit_ceiling or _terra.is_on_ceiling()
		if i > 5 and _terra.is_on_floor():
			break
	Input.action_release("jump")
	var expected: float = OVERHANG_BOTTOM_Y + TERRA_HEIGHT
	_check(hit_ceiling and absf(top_feet - expected) < 1.5,
		"bate a cabeça na saliência: pés sobem até y %.1f (esperado %.1f; sem teto iriam a %.0f)" % [top_feet, expected, HIGH_PLATFORM_Y - 56.0])
	await _wait(30)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - HIGH_PLATFORM_Y) < 0.5, "volta a pousar na plataforma")


func _test_one_way() -> void:
	print("-- Plataforma one-way")
	await _reset(Vector2(600, FLOOR_Y), 1.0)
	# Impulso vertical (a plataforma larga fica a 96 px do chão, acima do pulo de 56 px).
	_terra.velocity.y = -440.0
	var crossed: bool = false
	var blocked: bool = false
	for i: int in 90:
		await physics_frame
		crossed = crossed or _terra.global_position.y < WIDE_PLATFORM.position.y
		blocked = blocked or (_terra.is_on_ceiling() and not crossed)
		if crossed and _terra.is_on_floor():
			break
	_check(crossed and not blocked, "subindo por baixo, atravessa a plataforma")
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - WIDE_PLATFORM.position.y) < 0.5,
		"pousa em cima (y %.1f, esperado %.1f)" % [_terra.global_position.y, WIDE_PLATFORM.position.y])
	Input.action_press("move_right")
	await _wait(60)
	Input.action_release("move_right")
	await _wait(40)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5 and _terra.global_position.x > WIDE_PLATFORM.end.x,
		"sai pela borda e cai até o chão (x %.1f, y %.1f)" % [_terra.global_position.x, _terra.global_position.y])


# --- Onda sísmica -------------------------------------------------------------------------

func _test_wave_floor() -> void:
	print("-- Onda sísmica no chão de tiles")
	await _reset(Vector2(100, FLOOR_Y), 1.0)
	var result: Dictionary = await _cast_and_follow()
	_check(is_equal_approx(result.traveled, WAVE_RANGE) and result.y_constant,
		"percorre os %.0f px sobre %d tiles (%.1f), na altura do chão" % [WAVE_RANGE, int(WAVE_RANGE / TILE), result.traveled])
	await _wait(COOLDOWN_TICKS)
	await _reset(Vector2(300, FLOOR_Y), 1.0)
	result = await _cast_and_follow()
	_check(result.traveled < WAVE_RANGE and result.max_front <= STEP1_X + 0.01,
		"para na face do degrau (borda frontal máx. %.1f, percorreu %.0f px)" % [result.max_front, result.traveled])
	await _wait(COOLDOWN_TICKS)
	await _reset(Vector2(520, STEP_TOPS[2]), 1.0)
	result = await _cast_and_follow()
	_check(result.traveled < WAVE_RANGE and result.max_center <= STEP3_RIGHT_X and result.y_constant,
		"no topo do degrau 3, para na borda (centro máx. %.1f, esperado ≤ %.0f)" % [result.max_center, STEP3_RIGHT_X])
	await _wait(COOLDOWN_TICKS)


func _test_wave_platform_and_enemy() -> void:
	print("-- Onda sísmica na plataforma one-way, com inimigo")
	var fragment: LivingFragment = (load(FRAGMENT_PATH) as PackedScene).instantiate() as LivingFragment
	fragment.position = Vector2(624, WIDE_PLATFORM.position.y)
	_room.get_node("Enemies").add_child(fragment)
	await _reset(Vector2(568, WIDE_PLATFORM.position.y), 1.0)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - WIDE_PLATFORM.position.y) < 0.5, "Terra sobre a plataforma one-way")
	var health: HealthComponent = fragment.get_node("HealthComponent") as HealthComponent
	var before: int = health.current_health
	var result: Dictionary = await _cast_and_follow()
	_check(health.current_health == before - 2, "a onda atinge o Fragmento sobre a plataforma (vida %d → %d)" % [before, health.current_health])
	_check(result.traveled < WAVE_RANGE and result.max_center <= WIDE_PLATFORM.end.x and result.y_constant,
		"a onda corre sobre a plataforma e para na borda (centro máx. %.1f)" % result.max_center)


# --- Auxiliares ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _is_rock(x: int, y: int) -> bool:
	var data: TileData = _terrain.get_cell_tile_data(Vector2i(x, y))
	return data != null and data.terrain_set == 0


func _is_platform(x: int, y: int) -> bool:
	var data: TileData = _terrain.get_cell_tile_data(Vector2i(x, y))
	return data != null and data.terrain_set == 1


func _base_of(cell: Vector2i) -> Vector2i:
	for table: Dictionary in [TilesetTest.ROCK, TilesetTest.PLATFORMS]:
		if table.has(cell) and table[cell][1] != null:
			return table[cell][1]
	return cell


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack", "ability"]:
		Input.action_release(action)


func _reset(position: Vector2, facing: float) -> void:
	_release_all()
	var action: String = "move_right" if facing > 0.0 else "move_left"
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(10)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(5)


## Pula com o botão segurado e espera pousar. Retorna a altura dos pés no pouso.
func _jump_and_land() -> float:
	Input.action_press("jump")
	var left_ground: bool = false
	for i: int in 120:
		await physics_frame
		left_ground = left_ground or not _terra.is_on_floor()
		if left_ground and _terra.is_on_floor():
			break
	Input.action_release("jump")
	await _wait(2)
	return _terra.global_position.y


func _waves() -> Array[SeismicWave]:
	var result: Array[SeismicWave] = []
	for child: Node in _terra.get_children():
		if child is SeismicWave and not child.is_queued_for_deletion():
			result.append(child as SeismicWave)
	return result


## Usa o Punho Sísmico e acompanha a onda até ela sumir.
func _cast_and_follow() -> Dictionary:
	await _press("ability")
	for i: int in 30:
		if not _fist.is_casting():
			break
		await physics_frame
	var result: Dictionary = {"traveled": 0.0, "max_center": -INF, "max_front": -INF, "y_constant": true}
	var waves: Array[SeismicWave] = _waves()
	if waves.is_empty():
		return result
	var wave: SeismicWave = waves[0]
	var y0: float = wave.global_position.y
	while is_instance_valid(wave) and not wave.is_queued_for_deletion():
		result.traveled = wave.get_traveled_distance()
		result.max_center = maxf(result.max_center, wave.global_position.x)
		result.max_front = maxf(result.max_front, wave.global_position.x + WAVE_HALF_WIDTH)
		result.y_constant = result.y_constant and wave.global_position.y == y0
		await physics_frame
	return result
