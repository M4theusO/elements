extends SceneTree
## Teste automatizado da infraestrutura das Galerias Esquecidas (etapa 1): cena Game,
## base Room e Sala 01 — Despertar. Confere estrutura, carregamento, Terra única na entrada
## start, câmera (limites, sem sair da sala), fundo, terreno (peças, moldura, colisões,
## one-way) e o percurso real com a física da Terra (degraus, vão, plataforma, passagem).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_infra_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_PATH: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const CRYSTAL_DIR: String = "res://world/props/depths/crystals/"
const MAIN_SCENE: String = "res://tests/movement_lab/movement_lab.tscn"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const VIEW: Vector2 = Vector2(640, 360)
const ROOM_TILES: Vector2i = Vector2i(60, 23)
const BOUNDS: Rect2i = Rect2i(0, 0, 960, 368)
const ROOM_CHILDREN: Array[String] = ["Background", "Terrain", "Props", "Enemies", "Entrances", "Exits"]

## Geometria esperada (células), igual à do gerador; fora da sala tudo é rocha (moldura).
const ROCK_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 60, 2), Rect2i(0, 0, 2, 23), Rect2i(58, 0, 2, 16), Rect2i(0, 20, 60, 3),
	Rect2i(14, 19, 6, 1), Rect2i(20, 18, 6, 2), Rect2i(28, 18, 8, 2), Rect2i(48, 18, 4, 2),
	Rect2i(22, 2, 10, 2), Rect2i(44, 2, 8, 3),
]
const PLATFORM_RECTS: Array[Rect2i] = [Rect2i(37, 16, 6, 1)]
## Moldura com 2 tiles atrás da passagem direita (fora da câmera), para não haver peça sem par.
const FRAME_EXTRA: Rect2i = Rect2i(60, 14, 2, 8)

## Geometria em px (pés da Terra = global_position).
const START: Vector2 = Vector2(72, 320)
const FLOOR_Y: float = 320.0
const LEFT_WALL_X: float = 32.0
const STEP1_X: float = 224.0
const STEP1_Y: float = 304.0
const STEP2_Y: float = 288.0
const LEDGE_RECT: Rect2 = Rect2(448, 288, 128, 32)
const PLATFORM_RECT: Rect2 = Rect2(592, 256, 96, 8)
const BLOCK_RECT: Rect2 = Rect2(768, 288, 64, 32)
const PASSAGE_END_X: float = 960.0
const TERRA_HALF_WIDTH: float = 8.0
const TERRA_SIZE: Vector2 = Vector2(16, 46)

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _room: Room
var _terra: PlayerCharacter
var _camera: Camera2D
var _terrain: TileMapLayer


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: infraestrutura e Sala 01 — Despertar")
	await process_frame
	var scene: PackedScene = load(GAME_PATH) as PackedScene
	_check(scene != null, "game.tscn carrega")
	if scene == null:
		_finish()
		return
	_game = scene.instantiate() as Node2D
	root.add_child(_game)
	_terra = _game.get_node_or_null("Terra") as PlayerCharacter
	_camera = _game.get_node_or_null("Terra/Camera2D") as Camera2D
	_room = _game.call("get_room") as Room
	_check(_terra != null and _room != null and _terra.global_position == START,
		"logo após carregar, a Terra está na entrada start %s" % [_terra.global_position if _terra else null])
	_test_game_structure()
	if _terra == null or _camera == null or _room == null:
		_finish()
		return
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_test_room_structure()
	if _terrain == null:
		_finish()
		return
	_test_terrain_cells()
	_test_collision_layers()
	_test_props()
	_test_project()
	await _test_spawn()
	await _test_no_transitions()
	await _test_floor_and_walls()
	await _test_steps()
	await _test_gap()
	await _test_one_way()
	await _test_block_and_passage()
	await _test_camera()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Game ---------------------------------------------------------------------------------

func _test_game_structure() -> void:
	print("-- Cena Game")
	var slot: Node2D = _game.get_node_or_null("RoomSlot") as Node2D
	var fade: CanvasLayer = _game.get_node_or_null("Fade") as CanvasLayer
	var rect: ColorRect = _game.get_node_or_null("Fade/ColorRect") as ColorRect
	_check(slot != null and slot.get_index() == 0 and _terra != null and _terra.get_index() > slot.get_index(),
		"filhos: RoomSlot (Node2D) antes da Terra (desenhada por cima da sala)")
	_check(_terra != null and _terra.scene_file_path == "res://entities/characters/terra/terra.tscn",
		"Terra é instância de terra.tscn")
	_check(fade != null and rect != null and not rect.visible and rect.color == Color.BLACK
		and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Fade: CanvasLayer com ColorRect preto, invisível, sem bloquear o mouse")
	_check(_game.get("start_room") == ROOM_PATH and _game.get("start_entrance") == &"start",
		"configuração inicial: Sala 01, entrada start")
	if slot != null:
		_check(slot.get_child_count() == 1 and slot.get_child(0) == _room and _room.scene_file_path == ROOM_PATH,
			"RoomSlot contém só a Sala 01")
	_check(_count_type(root, "PlayerCharacter") == 1, "uma única Terra na árvore (%d)" % _count_type(root, "PlayerCharacter"))
	_check(_room != null and _count_type(_room, "PlayerCharacter") == 0, "a sala não contém Terra")
	if _camera != null:
		_check(_camera.is_current() and _count_type(root, "Camera2D") == 1, "Camera2D da Terra é a única e está ativa")
		_check(not _camera.position_smoothing_enabled and not _camera.rotation_smoothing_enabled
			and not _camera.drag_horizontal_enabled and not _camera.drag_vertical_enabled,
			"câmera sem suavização e sem drag")
		_check(_camera.zoom == Vector2.ONE and _camera.position == Vector2.ZERO and _camera.offset == Vector2.ZERO
			and _camera.ignore_rotation, "câmera com zoom 1, sem deslocamento, orientação padrão")
		_check(Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
			_camera.limit_bottom - _camera.limit_top) == BOUNDS, "limites da câmera = camera_bounds da sala (0, 0, 960, 368)")


# --- Sala ---------------------------------------------------------------------------------

func _test_room_structure() -> void:
	print("-- Estrutura da Sala 01")
	var names: Array[String] = []
	for child: Node in _room.get_children():
		names.append(child.name)
	_check(names == ROOM_CHILDREN, "filhos na ordem %s (%s)" % [ROOM_CHILDREN, names])
	var bounds: Rect2i = _room.get_camera_bounds()
	_check(bounds == BOUNDS and bounds.size == ROOM_TILES * TILE, "camera_bounds = 960x368 (60x23 tiles)")
	_check(bounds.position.x % TILE == 0 and bounds.position.y % TILE == 0 and bounds.size.x % TILE == 0
		and bounds.size.y % TILE == 0, "limites múltiplos de 16")
	_check(bounds.size.x >= VIEW.x and bounds.size.y >= VIEW.y, "sala pelo menos do tamanho da tela (640x360)")
	var bg: Node2D = _room.get_node_or_null("Background") as Node2D
	_check(bg != null and bg.scene_file_path == PARALLAX_PATH and bg.position == Vector2.ZERO,
		"Background é instância de depths_parallax.tscn, sem deslocamento")
	_check(_terrain != null and _terrain.tile_set != null and _terrain.tile_set.resource_path == TILESET_PATH
		and _terrain.collision_enabled, "Terrain: TileMapLayer com depths_tileset.tres e colisão ligada")
	var entrances: Node = _room.get_node_or_null("Entrances")
	_check(entrances != null and entrances.get_child_count() == 1 and entrances.get_child(0) is Marker2D
		and entrances.get_child(0).name == &"start", "Entrances: só o Marker2D start")
	_check(_room.has_entrance(&"start") and not _room.has_entrance(&"east") and not _room.has_entrance(&""),
		"has_entrance: start existe; east e vazio não")
	_check(_room.get_entrance(&"start") != null and _room.get_entrance(&"start").position == START,
		"get_entrance(start) nos pés em %s" % START)
	_check(_room.get_node("Enemies").get_child_count() == 0 and _count_type(_game, "Enemy") == 0, "sem inimigos")
	_check(_room.get_node("Exits").get_child_count() == 0, "Exits vazio (sem saídas nesta etapa)")
	_check(_count_type(_room, "Area2D") == 0 and _count_type(_room, "Camera2D") == 0
		and _count_type(_room, "StaticBody2D") == 0, "sala sem Area2D (gatilhos), câmera ou corpos fora do tilemap")


func _test_terrain_cells() -> void:
	print("-- Terreno")
	var expected_rock: int = 0
	var expected_platform: int = 0
	var mismatch: Array[String] = []
	for y: int in range(-2, ROOM_TILES.y + 2):
		for x: int in range(-2, ROOM_TILES.x + 2):
			var cell: Vector2i = Vector2i(x, y)
			var want: String = _expected_kind(cell)
			var data: TileData = _terrain.get_cell_tile_data(cell)
			var got: String = "." if data == null else ("#" if data.terrain_set == 0 else "=")
			expected_rock += 1 if want == "#" else 0
			expected_platform += 1 if want == "=" else 0
			if want != got:
				mismatch.append("%s: %s (esperado %s)" % [cell, got, want])
	_check(mismatch.is_empty(), "geometria igual ao mapa aprovado (%d rocha, %d plataforma) %s" % [expected_rock, expected_platform, mismatch.slice(0, 8)])
	var wrong: Array[String] = []
	for cell: Vector2i in _terrain.get_used_cells():
		var want: Vector2i = TilesetTest.expected_for(_is_rock, _is_platform, cell.x, cell.y)
		var got: Vector2i = _base_of(_terrain.get_cell_atlas_coords(cell))
		if got != want:
			wrong.append("%s: %s (esperado %s)" % [cell, got, want])
	_check(wrong.is_empty(), "toda célula tem a peça certa para os vizinhos (sem combinações fora do conjunto) %s" % [wrong.slice(0, 8)])
	var frame_ok: bool = true
	for x: int in range(-1, ROOM_TILES.x + 1):
		frame_ok = frame_ok and _is_rock(x, -1) and _is_rock(x, ROOM_TILES.y)
	for y: int in range(-1, ROOM_TILES.y + 1):
		frame_ok = frame_ok and _is_rock(-1, y) and _is_rock(ROOM_TILES.x, y)
	_check(frame_ok, "moldura de rocha completa 1 tile fora da câmera")
	# Nas bordas da câmera só aparecem tiles com o lado de fora coberto (sem vazio no limite),
	# exceto a passagem da direita, que termina na moldura.
	var open_edges: Array[Vector2i] = []
	for y: int in ROOM_TILES.y:
		for x: int in [0, ROOM_TILES.x - 1]:
			if not _is_rock(x, y) and not (x == ROOM_TILES.x - 1 and y >= 16 and y <= 19):
				open_edges.append(Vector2i(x, y))
	for x: int in ROOM_TILES.x:
		for y: int in [0, ROOM_TILES.y - 1]:
			if not _is_rock(x, y):
				open_edges.append(Vector2i(x, y))
	_check(open_edges.is_empty(), "bordas da câmera fechadas por rocha, só a passagem direita aberta (linhas 16–19) %s" % [open_edges])
	var passage_ok: bool = true
	for y: int in range(16, 20):
		for x: int in [ROOM_TILES.x - 2, ROOM_TILES.x - 1]:
			passage_ok = passage_ok and not _is_rock(x, y)
		passage_ok = passage_ok and _is_rock(ROOM_TILES.x, y)
	_check(passage_ok and _is_rock(ROOM_TILES.x - 1, 15) and _is_rock(ROOM_TILES.x - 1, 20),
		"passagem direita de 4 tiles de altura (futura saída), fechada pela moldura")


func _test_collision_layers() -> void:
	print("-- Colisões")
	var ts: TileSet = _terrain.tile_set
	_check(ts.get_physics_layers_count() == 2 and ts.get_physics_layer_collision_layer(0) == 1
		and ts.get_physics_layer_collision_layer(1) == 2, "camadas de física do tileset: world (1) e platforms (2)")
	var rock_ok: bool = true
	var platform_ok: bool = true
	for cell: Vector2i in _terrain.get_used_cells():
		var data: TileData = _terrain.get_cell_tile_data(cell)
		if data.terrain_set == 0:
			rock_ok = rock_ok and data.get_collision_polygons_count(0) > 0 and data.get_collision_polygons_count(1) == 0
		else:
			platform_ok = platform_ok and data.get_collision_polygons_count(1) > 0 and data.get_collision_polygons_count(0) == 0 \
				and data.is_collision_polygon_one_way(1, 0)
	_check(rock_ok, "todo tile de rocha tem colisão em world")
	_check(platform_ok, "todo tile de plataforma tem colisão one-way em platforms")
	_check(_terra.collision_mask & 3 == 3, "a Terra colide com world e platforms (mask %d)" % _terra.collision_mask)


func _test_props() -> void:
	print("-- Props")
	var props: Node = _room.get_node("Props")
	var ok: bool = props.get_child_count() > 0
	var inside_rock: Array[String] = []
	for prop: Node in props.get_children():
		ok = ok and prop is Sprite2D and prop.scene_file_path.begins_with(CRYSTAL_DIR)
		var sprite: Sprite2D = prop as Sprite2D
		if sprite != null and sprite.texture != null and _prop_touches_rock(sprite):
			inside_rock.append(String(prop.name))
	_check(ok, "%d props, todos cristais já commitados (sem vegetação pendente)" % props.get_child_count())
	_check(inside_rock.is_empty(), "nenhum pixel de prop dentro de tiles sólidos %s" % [inside_rock])
	var start_clear: bool = true
	for prop: Node in props.get_children():
		start_clear = start_clear and absf((prop as Node2D).position.x - START.x) > 96.0
	_check(start_clear, "nenhum prop a menos de 96 px da Terra no início")
	var state: SceneState = (load(ROOM_PATH) as PackedScene).get_state()
	var extra: Array[String] = []
	for i: int in state.get_node_count():
		if state.get_node_instance(i) == null:
			continue
		for p: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != &"position":
				extra.append("%s.%s" % [state.get_node_name(i), state.get_node_property_name(i, p)])
	_check(extra.is_empty(), "instâncias só sobrescrevem a posição %s" % [extra])


func _test_project() -> void:
	print("-- Projeto")
	_check(ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE, "cena principal continua o MovementLab")
	_check(not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")
		and not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel"), "pixel snapping continua desligado")


# --- Física e percurso --------------------------------------------------------------------

func _test_spawn() -> void:
	print("-- Nascimento")
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = TERRA_SIZE - Vector2(0.2, 0.2)
	params.shape = shape
	params.transform = Transform2D(0.0, START + Vector2(0.0, -TERRA_SIZE.y / 2.0))
	params.collision_mask = _terra.collision_mask
	params.exclude = [_terra.get_rid()]
	var hits: Array[Dictionary] = _game.get_world_2d().direct_space_state.intersect_shape(params)
	_check(hits.is_empty(), "corpo da Terra em start sem sobreposição com colisões (%d)" % hits.size())
	await _wait(30)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(START) < 0.5,
		"Terra apoiada no chão, sem cair nem escorregar (%s)" % _terra.global_position)
	_check(_terra.get_health().current_health == _terra.get_health().max_health, "vida cheia")


func _test_no_transitions() -> void:
	print("-- Sem transições")
	var slot: Node = _game.get_node("RoomSlot")
	await _reset(Vector2(900, FLOOR_Y), 1.0)
	Input.action_press("move_right")
	await _wait(60)
	Input.action_release("move_right")
	_check(slot.get_child_count() == 1 and slot.get_child(0) == _room and _game.call("get_room") == _room,
		"na passagem direita a sala continua a mesma")
	_check(not (_game.get_node("Fade/ColorRect") as ColorRect).visible, "Fade continua invisível")


func _test_floor_and_walls() -> void:
	print("-- Chão e paredes")
	await _reset(START, 1.0)
	Input.action_press("move_right")
	var on_floor: bool = true
	for i: int in 200:
		await physics_frame
		on_floor = on_floor and _terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.01
		if _terra.is_on_wall():
			break
	await _wait(5)
	Input.action_release("move_right")
	_check(on_floor, "anda no chão sem tropeçar nas emendas (y constante)")
	_check(absf(_terra.global_position.x - (STEP1_X - TERRA_HALF_WIDTH)) < 0.5,
		"degrau de 1 tile bloqueia o andar: para em x %.1f (esperado %.1f)" % [_terra.global_position.x, STEP1_X - TERRA_HALF_WIDTH])
	await _reset(START, -1.0)
	Input.action_press("move_left")
	await _wait(60)
	Input.action_release("move_left")
	_check(absf(_terra.global_position.x - (LEFT_WALL_X + TERRA_HALF_WIDTH)) < 0.5 and _terra.is_on_wall(),
		"parede esquerda: para em x %.1f (esperado %.1f)" % [_terra.global_position.x, LEFT_WALL_X + TERRA_HALF_WIDTH])


func _test_steps() -> void:
	print("-- Degraus de 1 tile")
	await _reset(Vector2(STEP1_X - 28.0, FLOOR_Y), 1.0)
	Input.action_press("move_right")
	var y1: float = await _jump_and_land()
	_check(absf(y1 - STEP1_Y) < 0.5, "sobe o 1º degrau: pousa em y %.1f (esperado %.1f)" % [y1, STEP1_Y])
	var y2: float = await _jump_and_land()
	_check(absf(y2 - STEP2_Y) < 0.5, "sobe o 2º degrau: pousa em y %.1f (esperado %.1f)" % [y2, STEP2_Y])
	Input.action_release("move_right")


func _test_gap() -> void:
	print("-- Vão de 2 tiles")
	await _reset(Vector2(380, STEP2_Y), 1.0)
	Input.action_press("move_right")
	await _wait(12)
	var y: float = await _jump_and_land()
	Input.action_release("move_right")
	_check(absf(y - LEDGE_RECT.position.y) < 0.5 and _terra.global_position.x > LEDGE_RECT.position.x,
		"pula o vão e pousa no patamar (x %.1f, y %.1f)" % [_terra.global_position.x, y])
	await _reset(Vector2(432, FLOOR_Y), 1.0)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5, "dentro do vão, a Terra fica no chão (sem queda fatal)")
	Input.action_press("move_right")
	y = await _jump_and_land()
	Input.action_release("move_right")
	_check(absf(y - LEDGE_RECT.position.y) < 0.5, "sai do vão com um pulo (2 tiles): y %.1f" % y)


func _test_one_way() -> void:
	print("-- Plataforma one-way (opcional)")
	await _reset(Vector2(540, LEDGE_RECT.position.y), 1.0)
	Input.action_press("move_right")
	await _wait(12)
	var y: float = await _jump_and_land()
	Input.action_release("move_right")
	_check(absf(y - PLATFORM_RECT.position.y) < 0.5 and PLATFORM_RECT.has_point(Vector2(_terra.global_position.x, y + 1.0)),
		"do patamar, pula até a plataforma (x %.1f, y %.1f)" % [_terra.global_position.x, y])
	Input.action_press("move_right")
	await _wait(60)
	Input.action_release("move_right")
	await _wait(30)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5 and _terra.global_position.x > PLATFORM_RECT.end.x,
		"sai pela borda da plataforma e cai no chão (x %.1f)" % _terra.global_position.x)
	await _reset(Vector2(640, FLOOR_Y), 1.0)
	Input.action_press("jump")
	var top: float = INF
	var bumped: bool = false
	for i: int in 90:
		await physics_frame
		top = minf(top, _terra.global_position.y)
		bumped = bumped or _terra.is_on_ceiling()
		if i > 5 and _terra.is_on_floor():
			break
	Input.action_release("jump")
	_check(not bumped and top > PLATFORM_RECT.position.y and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"do chão, a plataforma (4 tiles) não é alcançada e não bloqueia a cabeça (pés até y %.1f)" % top)
	await _reset(Vector2(560, LEDGE_RECT.position.y), 1.0)
	Input.action_press("move_right")
	await _wait(40)
	Input.action_release("move_right")
	await _wait(30)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"sem usar a plataforma, desce do patamar para o chão (caminho principal)")


func _test_block_and_passage() -> void:
	print("-- Bloco de 2 tiles e passagem")
	await _reset(Vector2(700, FLOOR_Y), 1.0)
	Input.action_press("move_right")
	await _wait(12)
	var y: float = await _jump_and_land()
	_check(absf(y - BLOCK_RECT.position.y) < 0.5, "sobe o bloco de 2 tiles com um pulo (y %.1f)" % y)
	await _wait(60)
	Input.action_release("move_right")
	await _wait(30)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5 and _terra.global_position.x > BLOCK_RECT.end.x,
		"desce do bloco para o chão da passagem")
	Input.action_press("move_right")
	await _wait(120)
	Input.action_release("move_right")
	_check(absf(_terra.global_position.x - (PASSAGE_END_X - TERRA_HALF_WIDTH)) < 0.5 and _terra.is_on_wall()
		and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"a passagem termina na moldura, no limite da câmera (x %.1f)" % _terra.global_position.x)


func _test_camera() -> void:
	print("-- Câmera")
	_terra.set_physics_process(false)
	var points: Array[Vector2] = [START, Vector2(0, 320), Vector2(200, 320), Vector2(320, 288),
		Vector2(480, 200), Vector2(640, 256), Vector2(800.5, 288), Vector2(952, 320), Vector2(960, 40),
		Vector2(500, 0), Vector2(123.4, 368)]
	for p: Vector2 in points:
		_terra.global_position = p
		await process_frame
		await process_frame
		var center: Vector2 = _camera.get_screen_center_position()
		var view: Rect2 = Rect2(center - VIEW / 2.0, VIEW)
		var inside: bool = view.position.x >= -0.001 and view.position.y >= -0.001 \
			and view.end.x <= BOUNDS.end.x + 0.001 and view.end.y <= BOUNDS.end.y + 0.001
		var expected: Vector2 = Vector2(clampf(p.x, VIEW.x / 2.0, BOUNDS.end.x - VIEW.x / 2.0),
			clampf(p.y, VIEW.y / 2.0, BOUNDS.end.y - VIEW.y / 2.0))
		_check(inside and center.distance_to(expected) < 0.01,
			"Terra em %s: tela %s dentro da sala, centro %s (esperado %s)" % [p, view, center, expected])
		_check(_background_covers(), "  fundo cobre a tela inteira com a Terra em %s" % p)
	_terra.set_physics_process(true)


## Cada Parallax2D, na tela, começa em (-largura, 0] e se repete (largura ≥ 640): cobre os
## 640 px; na vertical fica presa à tela (y = 0) e cobre os 360 px. Mesma regra do teste do fundo.
func _background_covers() -> bool:
	var bg: Node2D = _room.get_node("Background") as Node2D
	var ok: bool = bg.get_child_count() == 3
	for child: Node in bg.get_children():
		var par: Parallax2D = child as Parallax2D
		var sprite: Sprite2D = par.get_child(0) as Sprite2D if par != null and par.get_child_count() > 0 else null
		if par == null or sprite == null or sprite.texture == null:
			return false
		var w: float = sprite.texture.get_width()
		var screen: Vector2 = par.position - par.screen_offset
		ok = ok and w >= VIEW.x and sprite.texture.get_height() >= VIEW.y and par.repeat_size.x == w \
			and screen.x <= 0.001 and screen.x > -w and absf(screen.y) < 0.001
	return ok


# --- Auxiliares ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _prop_touches_rock(sprite: Sprite2D) -> bool:
	var image: Image = sprite.texture.get_image()
	var origin: Vector2i = Vector2i(sprite.position + sprite.offset)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var p: Vector2i = origin + Vector2i(x, y)
			if image.get_pixel(x, y).a > 0.0 and _is_rock(floori(p.x / float(TILE)), floori(p.y / float(TILE))):
				return true
	return false


func _expected_kind(cell: Vector2i) -> String:
	var inside: bool = cell.x >= 0 and cell.y >= 0 and cell.x < ROOM_TILES.x and cell.y < ROOM_TILES.y
	var in_frame: bool = cell.x >= -1 and cell.y >= -1 and cell.x <= ROOM_TILES.x and cell.y <= ROOM_TILES.y
	if not in_frame:
		return "#" if FRAME_EXTRA.has_point(cell) else "."
	if not inside:
		return "#"
	for r: Rect2i in ROCK_RECTS:
		if r.has_point(cell):
			return "#"
	for r: Rect2i in PLATFORM_RECTS:
		if r.has_point(cell):
			return "="
	return "."


func _count_type(node: Node, type_name: String) -> int:
	var n: int = 0
	if node.is_class(type_name) or (type_name == "Enemy" and node is Enemy) \
			or (type_name == "PlayerCharacter" and node is PlayerCharacter):
		n += 1
	for child: Node in node.get_children():
		n += _count_type(child, type_name)
	return n


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
