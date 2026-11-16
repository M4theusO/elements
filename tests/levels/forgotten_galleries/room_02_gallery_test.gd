extends SceneTree
## Teste automatizado da Sala 02 — Galeria (Galerias Esquecidas, etapa 2): estrutura,
## dimensões, entradas e saídas, terreno (peças, moldura, passagens), props, o único Fragmento
## Vivo (patrulha, perseguição e investida no espaço da sala) e o percurso real com a física da
## Terra nos dois sentidos. A sala é carregada pela Game, entrando pela entrada west.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_02_gallery_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_01_PATH: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_PATH: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
const CRYSTAL_DIR: String = "res://world/props/depths/crystals/"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const VIEW: Vector2 = Vector2(640, 360)
const ROOM_TILES: Vector2i = Vector2i(64, 23)
const BOUNDS: Rect2i = Rect2i(0, 0, 1024, 368)
const ROOM_CHILDREN: Array[String] = ["Background", "Terrain", "Props", "Enemies", "Entrances", "Exits"]

## Geometria esperada (células), igual à do gerador; fora da sala, moldura de 1 tile
## (2 atrás das passagens).
const ROCK_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 64, 2), Rect2i(0, 0, 2, 16), Rect2i(62, 0, 2, 16), Rect2i(0, 20, 64, 3),
	Rect2i(12, 19, 4, 1), Rect2i(48, 19, 4, 1), Rect2i(14, 2, 8, 2), Rect2i(40, 2, 10, 2),
]
const FRAME_EXTRA: Array[Rect2i] = [Rect2i(-2, 14, 2, 8), Rect2i(64, 14, 2, 8)]

## Geometria em px (pés = global_position).
const FLOOR_Y: float = 320.0
const RISE_Y: float = 304.0
const WEST: Vector2 = Vector2(56, 320)
const EAST: Vector2 = Vector2(968, 320)
const RISE_WEST: Rect2 = Rect2(192, 304, 64, 16)
const RISE_EAST: Rect2 = Rect2(768, 304, 64, 16)
## Arena plana entre as duas elevações (sem degraus nem paredes).
const ARENA: Rect2 = Rect2(256, 320, 512, 0)
const WEST_EXIT: Rect2 = Rect2(0, 256, 32, 64)
const FRAGMENT_POS: Vector2 = Vector2(512, 320)
const TERRA_HALF_WIDTH: float = 8.0
const TERRA_SIZE: Vector2 = Vector2(16, 46)
## Distância mínima entre as entradas e o Fragmento (detecção de 80 px + perda de alvo em 128).
const MIN_ENTRANCE_DISTANCE: float = 250.0

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _room: Room
var _terra: PlayerCharacter
var _camera: Camera2D
var _terrain: TileMapLayer
var _fragment: LivingFragment


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: Sala 02 — Galeria")
	await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	_game.set("start_room", ROOM_PATH)
	_game.set("start_entrance", &"west")
	root.add_child(_game)
	_room = _game.call("get_room") as Room
	_terra = _game.call("get_terra") as PlayerCharacter
	_camera = _game.get_node("Terra/Camera2D") as Camera2D
	_check(_room != null and _room.scene_file_path == ROOM_PATH, "a Game carrega a Sala 02")
	if _room == null:
		_finish()
		return
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_fragment = _room.get_node_or_null("Enemies/LivingFragment") as LivingFragment
	_test_structure()
	if _terrain == null or _fragment == null:
		_finish()
		return
	_test_terrain_cells()
	_test_props()
	await _test_arrival()
	await _test_camera()
	await _test_fragment()
	# Daqui em diante, só a geometria: sem inimigo e com a saída desligada (as transições
	# têm teste próprio).
	_fragment.queue_free()
	for room_exit: RoomExit in _room.get_exits():
		room_exit.monitoring = false
	await _wait(2)
	await _test_path_east()
	await _test_path_west()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Estrutura ----------------------------------------------------------------------------

func _test_structure() -> void:
	print("-- Estrutura")
	var names: Array[String] = []
	for child: Node in _room.get_children():
		names.append(child.name)
	_check(names == ROOM_CHILDREN, "filhos na ordem %s (%s)" % [ROOM_CHILDREN, names])
	var bounds: Rect2i = _room.get_camera_bounds()
	_check(bounds == BOUNDS and bounds.size == ROOM_TILES * TILE, "camera_bounds = 1024x368 (64x23 tiles)")
	_check(bounds.position.x % TILE == 0 and bounds.position.y % TILE == 0 and bounds.size.x % TILE == 0
		and bounds.size.y % TILE == 0 and bounds.size.x >= VIEW.x and bounds.size.y >= VIEW.y,
		"limites múltiplos de 16 e pelo menos do tamanho da tela")
	_check(Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
		_camera.limit_bottom - _camera.limit_top) == BOUNDS, "limites da câmera = camera_bounds")
	var bg: Node2D = _room.get_node_or_null("Background") as Node2D
	_check(bg != null and bg.scene_file_path == PARALLAX_PATH and bg.position == Vector2.ZERO,
		"Background é instância de depths_parallax.tscn")
	_check(_terrain != null and _terrain.tile_set != null and _terrain.tile_set.resource_path == TILESET_PATH
		and _terrain.collision_enabled, "Terrain: TileMapLayer com depths_tileset.tres e colisão ligada")
	var entrances: Array[String] = []
	for child: Node in _room.get_node("Entrances").get_children():
		if child is Marker2D:
			entrances.append(String(child.name))
	_check(entrances == ["west", "east"] and _room.get_entrance(&"west").position == WEST
		and _room.get_entrance(&"east").position == EAST, "entradas west %s e east %s" % [WEST, EAST])
	_check(_room.get_entrance_facing(&"west") == 1.0 and _room.get_entrance_facing(&"east") == -1.0,
		"chegando por west olha para a direita; por east, para a esquerda")
	var exits: Array[RoomExit] = _room.get_exits()
	_check(exits.size() == 1 and _room.get_node("Exits").get_child_count() == 1 and exits[0].name == &"West",
		"uma única saída, West (east ainda sem transição)")
	if exits.size() == 1:
		var e: RoomExit = exits[0]
		_check(e.target_room == ROOM_01_PATH and e.target_entry == &"east", "West leva à Sala 01, entrada east")
		_check(e.collision_layer == 0 and e.collision_mask == 4 and e.monitoring and not e.monitorable,
			"West: layer 0, mask só player, monitoring ligado, monitorable desligado")
		_check(_exit_rect(e) == WEST_EXIT, "área da saída West %s (dentro da passagem)" % _exit_rect(e))
	var enemies: Array[Node] = _room.get_node("Enemies").get_children()
	_check(enemies.size() == 1 and _fragment != null and _fragment.scene_file_path == FRAGMENT_PATH
		and _count_type(_game, "Enemy") == 1, "exatamente um Fragmento Vivo")
	if _fragment != null:
		_check(_fragment.position == FRAGMENT_POS, "Fragmento no centro da arena %s" % FRAGMENT_POS)
		_check(_fragment.get_meta(Room.PERSISTENT_ID_META, &"") == &"gallery_fragment_01" and _room.get_persistent_enemies().keys() == [&"gallery_fragment_01"],
			"Fragmento com identificador persistente gallery_fragment_01")
		for id: StringName in [&"west", &"east"]:
			var d: float = absf(_room.get_entrance(id).position.x - _fragment.position.x)
			_check(d >= MIN_ENTRANCE_DISTANCE, "entrada %s a %.0f px do Fragmento (mín. %.0f)" % [id, d, MIN_ENTRANCE_DISTANCE])
	_check(_count_type(_room, "PlayerCharacter") == 0 and _count_type(_room, "Camera2D") == 0
		and _count_type(_room, "StaticBody2D") == 0, "sala sem Terra, câmera ou corpos fora do tilemap")
	var state: SceneState = (load(ROOM_PATH) as PackedScene).get_state()
	var extra: Array[String] = []
	for i: int in state.get_node_count():
		if state.get_node_instance(i) == null:
			continue
		for p: int in state.get_node_property_count(i):
			if not state.get_node_property_name(i, p) in [&"position", &"metadata/persistent_id"]:
				extra.append("%s.%s" % [state.get_node_name(i), state.get_node_property_name(i, p)])
	_check(extra.is_empty(), "instâncias só sobrescrevem a posição e o identificador persistente (sem mudar IA nem combate) %s" % [extra])


func _test_terrain_cells() -> void:
	print("-- Terreno")
	var mismatch: Array[String] = []
	for y: int in range(-2, ROOM_TILES.y + 2):
		for x: int in range(-3, ROOM_TILES.x + 3):
			var cell: Vector2i = Vector2i(x, y)
			var data: TileData = _terrain.get_cell_tile_data(cell)
			var got: String = "." if data == null else ("#" if data.terrain_set == 0 else "=")
			if got != _expected_kind(cell):
				mismatch.append("%s: %s" % [cell, got])
	_check(mismatch.is_empty(), "geometria igual ao mapa aprovado %s" % [mismatch.slice(0, 8)])
	var wrong: Array[String] = []
	for cell: Vector2i in _terrain.get_used_cells():
		var want: Vector2i = TilesetTest.expected_for(_is_rock, _is_platform, cell.x, cell.y)
		var got: Vector2i = _base_of(_terrain.get_cell_atlas_coords(cell))
		if got != want:
			wrong.append("%s: %s (esperado %s)" % [cell, got, want])
	_check(wrong.is_empty(), "toda célula tem a peça certa para os vizinhos %s" % [wrong.slice(0, 8)])
	var open_edges: Array[Vector2i] = []
	for y: int in ROOM_TILES.y:
		for x: int in [0, ROOM_TILES.x - 1]:
			if not _is_rock(x, y) and not (y >= 16 and y <= 19):
				open_edges.append(Vector2i(x, y))
	for x: int in ROOM_TILES.x:
		for y: int in [0, ROOM_TILES.y - 1]:
			if not _is_rock(x, y):
				open_edges.append(Vector2i(x, y))
	_check(open_edges.is_empty(), "bordas da câmera fechadas por rocha, exceto as duas passagens %s" % [open_edges])
	var passages: bool = true
	for y: int in range(16, 20):
		passages = passages and not _is_rock(0, y) and not _is_rock(1, y) and _is_rock(-1, y) \
			and not _is_rock(62, y) and not _is_rock(63, y) and _is_rock(64, y)
	_check(passages, "passagens de 4 tiles nas duas paredes, fechadas pela moldura fora da câmera")
	var flat: bool = true
	for x: int in range(int(ARENA.position.x / TILE), int(ARENA.end.x / TILE)):
		for y: int in range(2, 20):
			flat = flat and (y < 4 or not _is_rock(x, y))
		flat = flat and _is_rock(x, 20)
	_check(flat, "arena plana de %d px entre as elevações (x %d–%d)" % [ARENA.size.x, ARENA.position.x, ARENA.end.x])


func _test_props() -> void:
	print("-- Props")
	var props: Array[Node] = _room.get_node("Props").get_children()
	var ok: bool = props.size() > 0
	var inside_rock: Array[String] = []
	for prop: Node in props:
		ok = ok and prop is Sprite2D and prop.scene_file_path.begins_with(CRYSTAL_DIR)
		if prop is Sprite2D and _prop_touches_rock(prop as Sprite2D):
			inside_rock.append(String(prop.name))
	_check(ok, "%d props, todos cristais já commitados" % props.size())
	_check(inside_rock.is_empty(), "nenhum pixel de prop dentro de tiles sólidos %s" % [inside_rock])
	var clear: bool = true
	for prop: Node in props:
		var x: float = (prop as Node2D).position.x
		clear = clear and absf(x - WEST.x) > 96.0 and absf(x - EAST.x) > 96.0 and absf(x - FRAGMENT_POS.x) > 96.0
	_check(clear, "nenhum prop a menos de 96 px das entradas nem da patrulha do Fragmento")


# --- Chegada, câmera, Fragmento -------------------------------------------------------------

func _test_arrival() -> void:
	print("-- Chegada por west")
	_check(_terra.global_position == WEST and _terra.get_facing() == 1.0, "Terra em west, olhando para a direita")
	_check(not _body_rect(WEST).intersects(WEST_EXIT), "a chegada não fica dentro da saída West")
	_check(_shape_hits(WEST) == 0, "corpo da Terra em west sem sobreposição com o terreno")
	await _wait(20)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(WEST) < 0.5, "apoiada no chão em west")
	_check(_fragment.is_on_floor() and absf(_fragment.global_position.y - FLOOR_Y) < 0.5, "Fragmento apoiado no chão")
	_check(_fragment.get_state() == LivingFragment.State.PATROL, "o Fragmento não percebe a Terra na entrada")


func _test_camera() -> void:
	print("-- Câmera")
	# Saídas desligadas: teleportar a Terra para x 0 cairia na saída West e trocaria a sala.
	for room_exit: RoomExit in _room.get_exits():
		room_exit.monitoring = false
	_terra.set_physics_process(false)
	var ok: bool = true
	var detail: String = ""
	for x: float in [0.0, 56.0, 320.0, 512.0, 700.3, 968.0, 1024.0]:
		for y: float in [320.0, 120.0]:
			_terra.global_position = Vector2(x, y)
			await process_frame
			await process_frame
			var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
			if view.position.x < -0.001 or view.position.y < -0.001 or view.end.x > BOUNDS.end.x + 0.001 \
					or view.end.y > BOUNDS.end.y + 0.001:
				ok = false
				detail += " (%s: %s)" % [Vector2(x, y), view]
	_check(ok, "câmera nunca mostra fora da sala (14 posições)%s" % detail)
	_terra.set_physics_process(true)
	await _reset(WEST, 1.0)
	for room_exit: RoomExit in _room.get_exits():
		room_exit.monitoring = true
	_check(_game.call("get_room") == _room and not _game.call("is_transitioning"), "a sala continua a mesma depois do teste da câmera")


func _test_fragment() -> void:
	print("-- Fragmento Vivo")
	var min_x: float = INF
	var max_x: float = -INF
	var on_floor: bool = true
	for i: int in 360:
		await physics_frame
		min_x = minf(min_x, _fragment.global_position.x)
		max_x = maxf(max_x, _fragment.global_position.x)
		on_floor = on_floor and absf(_fragment.global_position.y - FLOOR_Y) < 0.5
	var origin: float = _fragment.get_patrol_origin_x()
	_check(on_floor and min_x >= origin - _fragment.patrol_distance - 0.5 and max_x <= origin + _fragment.patrol_distance + 0.5
		and max_x - min_x >= 2.0 * _fragment.patrol_distance - 1.0,
		"patrulha completa (%.0f–%.0f) no chão, sem paredes no caminho" % [min_x, max_x])
	# Terra à esquerda, dentro da detecção: perseguição e investida sem sair da arena.
	await _reset(Vector2(_fragment.global_position.x - 70.0, FLOOR_Y), 1.0)
	var chased: bool = false
	var attacked: bool = false
	var inside: bool = true
	for i: int in 240:
		await physics_frame
		chased = chased or _fragment.get_state() == LivingFragment.State.CHASE
		attacked = attacked or _fragment.get_state() == LivingFragment.State.ATTACK
		inside = inside and _fragment.global_position.x > ARENA.position.x + 9.0 and _fragment.global_position.x < ARENA.end.x - 9.0 \
			and absf(_fragment.global_position.y - FLOOR_Y) < 0.5
		if attacked and _fragment.get_state() != LivingFragment.State.ATTACK:
			break
	_check(chased and attacked, "percebe a Terra, persegue e investe")
	_check(inside, "perseguição e investida dentro da arena plana")
	# Perde a Terra longe: volta à patrulha.
	await _reset(WEST, 1.0)
	var back: bool = false
	for i: int in 300:
		await physics_frame
		if _fragment.get_state() == LivingFragment.State.PATROL:
			back = true
			break
	_check(back, "com a Terra de volta à entrada, volta a patrulhar")


# --- Percurso -------------------------------------------------------------------------------

func _test_path_east() -> void:
	print("-- Percurso west → east")
	await _reset(WEST, 1.0)
	Input.action_press("move_right")
	var stop: float = await _walk_until_wall()
	_check(absf(stop - (RISE_WEST.position.x - TERRA_HALF_WIDTH)) < 0.5, "a elevação oeste (1 tile) bloqueia o andar (x %.1f)" % stop)
	var y: float = await _jump_and_land()
	_check(absf(y - RISE_Y) < 0.5, "sobe a elevação oeste com um pulo (y %.1f)" % y)
	stop = await _walk_until_wall()
	_check(absf(stop - (RISE_EAST.position.x - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"desce para a arena e atravessa até a elevação leste (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(absf(y - RISE_Y) < 0.5, "sobe a elevação leste (y %.1f)" % y)
	stop = await _walk_until_wall()
	Input.action_release("move_right")
	_check(absf(stop - (BOUNDS.end.x - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"chega ao fim da passagem leste, fechada até a Sala 03 (x %.1f)" % stop)


func _test_path_west() -> void:
	print("-- Percurso east → west (retorno)")
	await _reset(EAST, -1.0)
	_check(_shape_hits(EAST) == 0, "corpo da Terra em east sem sobreposição com o terreno")
	Input.action_press("move_left")
	var stop: float = await _walk_until_wall()
	_check(absf(stop - (RISE_EAST.end.x + TERRA_HALF_WIDTH)) < 0.5, "a elevação leste bloqueia (x %.1f)" % stop)
	var y: float = await _jump_and_land()
	_check(absf(y - RISE_Y) < 0.5, "sobe a elevação leste pela direita")
	stop = await _walk_until_wall()
	_check(absf(stop - (RISE_WEST.end.x + TERRA_HALF_WIDTH)) < 0.5, "atravessa a arena até a elevação oeste (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(absf(y - RISE_Y) < 0.5, "sobe a elevação oeste pela direita")
	stop = await _walk_until_wall()
	Input.action_release("move_left")
	_check(absf(stop - TERRA_HALF_WIDTH) < 0.5 and _body_rect(_terra.global_position).intersects(WEST_EXIT),
		"caminho de retorno livre até a passagem oeste, dentro da área da saída (x %.1f)" % stop)


# --- Auxiliares -----------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _expected_kind(cell: Vector2i) -> String:
	var inside: bool = cell.x >= 0 and cell.y >= 0 and cell.x < ROOM_TILES.x and cell.y < ROOM_TILES.y
	if inside:
		for r: Rect2i in ROCK_RECTS:
			if r.has_point(cell):
				return "#"
		return "."
	var in_frame: bool = cell.x >= -1 and cell.y >= -1 and cell.x <= ROOM_TILES.x and cell.y <= ROOM_TILES.y
	for r: Rect2i in FRAME_EXTRA:
		in_frame = in_frame or r.has_point(cell)
	return "#" if in_frame else "."


func _exit_rect(e: RoomExit) -> Rect2:
	var shape: RectangleShape2D = (e.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	return Rect2(e.position - shape.size / 2.0, shape.size)


func _body_rect(feet: Vector2) -> Rect2:
	return Rect2(feet - Vector2(TERRA_SIZE.x / 2.0, TERRA_SIZE.y), TERRA_SIZE)


func _shape_hits(feet: Vector2) -> int:
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = TERRA_SIZE - Vector2(0.2, 0.2)
	params.shape = shape
	params.transform = Transform2D(0.0, feet + Vector2(0.0, -TERRA_SIZE.y / 2.0))
	params.collision_mask = 3
	return _game.get_world_2d().direct_space_state.intersect_shape(params).size()


func _prop_touches_rock(sprite: Sprite2D) -> bool:
	var image: Image = sprite.texture.get_image()
	var origin: Vector2i = Vector2i(sprite.position + sprite.offset)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var p: Vector2i = origin + Vector2i(x, y)
			if image.get_pixel(x, y).a > 0.0 and _is_rock(floori(p.x / float(TILE)), floori(p.y / float(TILE))):
				return true
	return false


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
	_terra.set_facing(facing)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(10)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(5)


## Anda (com a direção já pressionada) até encostar numa parede. Retorna o x dos pés.
func _walk_until_wall() -> float:
	for i: int in 600:
		await physics_frame
		if i > 3 and _terra.is_on_wall() and _terra.is_on_floor():
			break
	return _terra.global_position.x


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
