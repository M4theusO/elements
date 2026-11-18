extends SceneTree
## Teste automatizado da Sala 05 — Portão Antigo (Galerias Esquecidas, etapa 6): carregamento,
## dimensões, estrutura, terreno (peças, moldura, passagem oeste, parede leste fechada), props,
## o portão (composição provisória de tiles: forma, simetria, fendas fechadas, colisão real),
## impossibilidade de atravessá-lo com a física real, ausência de inimigos e de saídas além da
## oeste, câmera (limites, portão inteiro na tela, sem salto na chegada) e fundo, percurso nos
## dois sentidos e transições com a Sala 04 (vida, instância, golpe cancelado e o Escavador
## derrotado continua fora).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_05_ancient_gate_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_04: String = "res://world/levels/depths/forgotten_galleries/room_04_crystals.tscn"
const ROOM_PATH: String = "res://world/levels/depths/forgotten_galleries/room_05_ancient_gate.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const PROPS_DIR: String = "res://world/props/depths/"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const VIEW: Vector2 = Vector2(640, 360)
const ROOM_TILES: Vector2i = Vector2i(48, 23)
const BOUNDS: Rect2i = Rect2i(0, 0, 768, 368)
const ROOM_04_BOUNDS: Rect2i = Rect2i(0, 0, 896, 368)
const ROOM_CHILDREN: Array[String] = ["Background", "Terrain", "Props", "Enemies", "Entrances", "Exits"]

## Geometria esperada (células), igual à do gerador; fora da sala, moldura de 1 tile
## (2 atrás da passagem oeste).
const ROCK_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 48, 2), Rect2i(0, 0, 2, 16), Rect2i(46, 0, 2, 23), Rect2i(0, 20, 48, 3),
	Rect2i(4, 2, 5, 2), Rect2i(9, 19, 2, 1),
	Rect2i(16, 19, 2, 1), Rect2i(16, 2, 2, 6), Rect2i(28, 19, 2, 1), Rect2i(28, 2, 2, 6),
	Rect2i(32, 19, 14, 1), Rect2i(34, 8, 2, 11), Rect2i(37, 8, 6, 11), Rect2i(44, 8, 2, 11),
	Rect2i(32, 6, 14, 2), Rect2i(36, 4, 8, 2),
]
const FRAME_EXTRA: Array[Rect2i] = [Rect2i(-2, 14, 2, 8)]

## Portão (células): ombreiras, folha, fendas, verga, coroamento e soleira; eixo entre as
## colunas 39 e 40 (x 640).
const GATE_COLUMNS: Vector2i = Vector2i(34, 45)
const GATE_ROWS: Vector2i = Vector2i(4, 19)
const SLOT_COLUMNS: Array[int] = [36, 43]
const SLOT_ROWS: Vector2i = Vector2i(8, 18)
const GATE_AXIS_X: float = 640.0

## Geometria em px (pés = global_position).
const FLOOR_Y: float = 320.0
const STEP_Y: float = 304.0
const WEST: Vector2 = Vector2(56, 320)
const WEST_EXIT: Rect2 = Rect2(0, 256, 32, 64)
## Portão inteiro (do topo do coroamento ao chão) e a face onde a Terra para.
const GATE_RECT: Rect2 = Rect2(512, 64, 256, 256)
const GATE_FACE_X: float = 544.0
const GATE_STOP: Vector2 = Vector2(536, 304)
## Entrada e área da saída leste da Sala 04.
const ROOM_04_EAST: Vector2 = Vector2(840, 320)
const ROOM_04_EAST_EXIT: Rect2 = Rect2(864, 256, 32, 64)
const BURROWER_ID: StringName = &"crystal_burrower_01"
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
	print("== Galerias Esquecidas: Sala 05 — Portão Antigo")
	await process_frame
	await _new_game(ROOM_PATH, &"west")
	_room = _game.call("get_room") as Room
	_check(_room != null and _room.scene_file_path == ROOM_PATH, "a Game carrega a Sala 05")
	if _room == null:
		_finish()
		return
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_test_structure()
	if _terrain == null:
		_finish()
		return
	_test_terrain_cells()
	_test_gate_shape()
	_test_props()
	await _test_arrival()
	_set_exits(false)
	await _test_gate_blocks()
	await _test_camera()
	await _test_path_back()
	await _test_transitions()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Estrutura e terreno --------------------------------------------------------------------

func _test_structure() -> void:
	print("-- Estrutura")
	var names: Array[String] = []
	for child: Node in _room.get_children():
		names.append(child.name)
	_check(names == ROOM_CHILDREN, "filhos na ordem %s (%s)" % [ROOM_CHILDREN, names])
	var bounds: Rect2i = _room.get_camera_bounds()
	_check(bounds == BOUNDS and bounds.size == ROOM_TILES * TILE, "camera_bounds = 768x368 (48x23 tiles)")
	_check(_camera_limits() == BOUNDS, "limites da câmera: left 0, top 0, right 768, bottom 368")
	var bg: Node2D = _room.get_node_or_null("Background") as Node2D
	_check(bg != null and bg.scene_file_path == PARALLAX_PATH and bg.position == Vector2.ZERO,
		"Background é instância de depths_parallax.tscn")
	_check(_terrain != null and _terrain.tile_set != null and _terrain.tile_set.resource_path == TILESET_PATH
		and _terrain.collision_enabled, "Terrain: TileMapLayer com depths_tileset.tres e colisão ligada")
	var entrances: Array[String] = []
	for child: Node in _room.get_node("Entrances").get_children():
		if child is Marker2D:
			entrances.append(String(child.name))
	_check(entrances == ["west"] and _room.get_entrance(&"west").position == WEST and _room.get_entrance_facing(&"west") == 1.0,
		"uma única entrada, west %s, olhando para a direita" % WEST)
	var exits: Array[RoomExit] = _room.get_exits()
	_check(exits.size() == 1 and _room.get_node("Exits").get_child_count() == 1 and exits[0].name == &"West",
		"uma única saída, West: nenhuma saída para uma região futura")
	if exits.size() == 1:
		var e: RoomExit = exits[0]
		_check(e.target_room == ROOM_04 and e.target_entry == &"east", "West leva à Sala 04, entrada east")
		_check(e.collision_layer == 0 and e.collision_mask == 4 and e.monitoring and not e.monitorable,
			"West: layer 0, mask só player, monitoring ligado, monitorable desligado")
		_check(_exit_rect(e) == WEST_EXIT and not _body_rect(WEST).grow(4.0).intersects(WEST_EXIT),
			"área da saída West %s dentro da passagem; a entrada west fica 16 px fora dela" % _exit_rect(e))
	_check(_room.get_node("Enemies").get_child_count() == 0 and _count_type(_game, "Enemy") == 0
		and _room.get_persistent_enemies().is_empty(), "sem inimigos")
	_check(_count_type(_room, "PlayerCharacter") == 0 and _count_type(_room, "Camera2D") == 0
		and _count_type(_room, "StaticBody2D") == 0 and _count_type(_room, "Area2D") == 1,
		"sem Terra, câmera, corpos fora do tilemap nem áreas além da saída West (nenhum bloqueio invisível)")
	var state: SceneState = (load(ROOM_PATH) as PackedScene).get_state()
	var extra: Array[String] = []
	for i: int in state.get_node_count():
		if state.get_node_instance(i) == null:
			continue
		for p: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != &"position":
				extra.append("%s.%s" % [state.get_node_name(i), state.get_node_property_name(i, p)])
	_check(extra.is_empty(), "instâncias só sobrescrevem a posição %s" % [extra])


func _test_terrain_cells() -> void:
	print("-- Terreno")
	var mismatch: Array[String] = []
	for y: int in range(-2, ROOM_TILES.y + 2):
		for x: int in range(-3, ROOM_TILES.x + 3):
			var cell: Vector2i = Vector2i(x, y)
			var tile: TileData = _terrain.get_cell_tile_data(cell)
			var got: String = "." if tile == null else ("#" if tile.terrain_set == 0 else "=")
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
	var platforms: int = 0
	for cell: Vector2i in _terrain.get_used_cells():
		platforms += 1 if _is_platform(cell.x, cell.y) else 0
	_check(platforms == 0, "sem plataformas one-way")
	var open_edges: Array[Vector2i] = []
	for y: int in ROOM_TILES.y:
		if not _is_rock(ROOM_TILES.x - 1, y):
			open_edges.append(Vector2i(ROOM_TILES.x - 1, y))
		if not _is_rock(0, y) and not (y >= 16 and y <= 19):
			open_edges.append(Vector2i(0, y))
	for x: int in ROOM_TILES.x:
		for y: int in [0, ROOM_TILES.y - 1]:
			if not _is_rock(x, y):
				open_edges.append(Vector2i(x, y))
	_check(open_edges.is_empty(), "bordas fechadas por rocha, exceto a passagem oeste; parede leste inteira %s" % [open_edges])
	var passage: bool = true
	for y: int in range(16, 20):
		passage = passage and not _is_rock(0, y) and not _is_rock(1, y) and _is_rock(-1, y)
	_check(passage, "passagem oeste de 4 tiles, fechada pela moldura fora da câmera")
	_check(_rect_hits(Rect2(737, 40, 30, 300), 1) > 0, "parede leste com colisão real (layer world)")


func _test_gate_shape() -> void:
	print("-- Portão (composição provisória de tiles)")
	var solid: bool = true
	for c: Vector2i in [Vector2i(34, 8), Vector2i(35, 18), Vector2i(37, 8), Vector2i(42, 18), Vector2i(44, 8), Vector2i(45, 18),
			Vector2i(32, 6), Vector2i(45, 7), Vector2i(36, 4), Vector2i(43, 5), Vector2i(32, 19), Vector2i(45, 19)]:
		solid = solid and _is_rock(c.x, c.y)
	_check(solid, "ombreiras, folha, verga com beiral, coroamento e soleira em rocha")
	var slots: bool = true
	for x: int in SLOT_COLUMNS:
		for y: int in range(SLOT_ROWS.x, SLOT_ROWS.y + 1):
			slots = slots and not _is_rock(x, y)
		# Fendas fechadas: verga em cima, soleira embaixo, rocha dos dois lados (inalcançáveis).
		slots = slots and _is_rock(x, SLOT_ROWS.x - 1) and _is_rock(x, SLOT_ROWS.y + 1) \
			and _is_rock(x - 1, SLOT_ROWS.x) and _is_rock(x + 1, SLOT_ROWS.y)
	_check(slots, "duas fendas verticais de 1 tile delimitam a folha (colunas %s), fechadas por todos os lados" % [SLOT_COLUMNS])
	var symmetric: bool = true
	for y: int in range(GATE_ROWS.x, GATE_ROWS.y + 1):
		for x: int in range(GATE_COLUMNS.x, GATE_COLUMNS.y + 1):
			var mirror: int = int(2.0 * GATE_AXIS_X / TILE) - 1 - x
			symmetric = symmetric and _is_rock(x, y) == _is_rock(mirror, y)
	_check(symmetric, "estrutura simétrica em relação ao eixo x %.0f" % GATE_AXIS_X)
	var leaf_height: float = (SLOT_ROWS.y - SLOT_ROWS.x + 1) * TILE
	_check(GATE_RECT.size.y >= 5.0 * TERRA_SIZE.y and leaf_height >= 3.0 * TERRA_SIZE.y and GATE_RECT.size.y / BOUNDS.size.y > 0.6,
		"portão de %.0f px de altura (%.0f%% da sala) e folha de %.0f px, contra %.0f px da Terra" % [
			GATE_RECT.size.y, 100.0 * GATE_RECT.size.y / BOUNDS.size.y, leaf_height, TERRA_SIZE.y])
	# Colisão real na face do portão, colada a ela (sem bloqueio afastado).
	_check(_rect_hits(Rect2(GATE_FACE_X + 0.5, 140, 14, 150), 1) > 0 and _rect_hits(Rect2(GATE_FACE_X - 15.5, 140, 15, 160), 3) == 0,
		"colisão sólida (world) começa exatamente na face do portão, x %.0f; nada antes dela" % GATE_FACE_X)
	_check(_rect_hits(Rect2(GATE_FACE_X + 0.5, 140, 14, 150), 2) == 0, "o portão não é plataforma one-way")


func _test_props() -> void:
	print("-- Props")
	var props: Array[Node] = _room.get_node("Props").get_children()
	var ok: bool = props.size() > 0
	var inside_rock: Array[String] = []
	var crystals: int = 0
	var vegetation: int = 0
	var gate_crystals: int = 0
	for prop: Node in props:
		ok = ok and prop is Sprite2D and prop.scene_file_path.begins_with(PROPS_DIR)
		var is_crystal: bool = prop.scene_file_path.contains("/crystals/")
		crystals += 1 if is_crystal else 0
		vegetation += 1 if prop.scene_file_path.contains("/vegetation/") else 0
		if is_crystal and GATE_RECT.grow(16.0).has_point((prop as Node2D).position):
			gate_crystals += 1
		if prop is Sprite2D and _prop_touches_rock(prop as Sprite2D):
			inside_rock.append(String(prop.name))
	_check(ok and crystals + vegetation == props.size(), "%d props já commitados (%d cristais, %d de vegetação), nenhum sprite novo" % [props.size(), crystals, vegetation])
	_check(inside_rock.is_empty(), "nenhum pixel de prop dentro de rocha %s" % [inside_rock])
	_check(gate_crystals >= 5, "cristais incrustados no portão (%d)" % gate_crystals)
	var clear: bool = true
	for prop: Node in props:
		clear = clear and (prop as Node2D).position.distance_to(WEST) > 96.0
	_check(clear, "nenhum prop a menos de 96 px da entrada")


# --- Chegada, portão, câmera ----------------------------------------------------------------

func _test_arrival() -> void:
	print("-- Chegada por west")
	_check(_terra.global_position == WEST and _terra.get_facing() == 1.0, "Terra em west, olhando para a direita")
	_check(_shape_hits(WEST) == 0, "corpo da Terra em west sem sobreposição com o terreno")
	await _wait(30)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(WEST) < 0.5 and _game.call("get_room") == _room,
		"apoiada no chão em west, sem voltar pela saída")


func _test_gate_blocks() -> void:
	print("-- O portão bloqueia")
	# Da entrada até o portão andando para a direita e pulando cada obstáculo.
	await _reset(WEST, 1.0)
	var result: Dictionary = await _walk_with_hops(1.0, 900)
	_check(absf(result.pos.x - GATE_STOP.x) < 0.5 and absf(result.pos.y - GATE_STOP.y) < 0.5,
		"chega ao portão pela sala inteira e para na soleira, encostada na face (%s)" % result.pos)
	_check(result.max_x <= GATE_STOP.x + 0.5, "nunca passa da face do portão (x máx. %.1f)" % result.max_x)
	# Insistência: 5 s pulando contra o portão.
	Input.action_press("move_right")
	var max_x: float = -INF
	var min_y: float = INF
	for i: int in 300:
		if i % 40 == 0:
			Input.action_press("jump")
		elif i % 40 == 20:
			Input.action_release("jump")
		await physics_frame
		max_x = maxf(max_x, _terra.global_position.x)
		min_y = minf(min_y, _terra.global_position.y)
	_release_all()
	await _wait(60)
	_check(max_x <= GATE_STOP.x + 0.5 and absf(_terra.global_position.x - GATE_STOP.x) < 0.5,
		"5 s pulando contra o portão: não atravessa (x máx. %.1f)" % max_x)
	_check(min_y > GATE_RECT.position.y + 64.0, "o pulo não alcança o alto do portão (topo da Terra em y %.0f)" % (min_y - TERRA_SIZE.y))
	_check(_terra.is_on_floor() and _game.call("get_room") == _room and not _game.call("is_transitioning"),
		"sem transição no portão (nenhuma saída para uma região futura)")
	# Golpe e Punho Sísmico contra o portão: nada acontece além do normal.
	_terra.set_facing(1.0)
	await _tap("attack")
	await _wait(30)
	await _tap("ability")
	await _wait(60)
	_check(absf(_terra.global_position.x - GATE_STOP.x) < 0.5 and _game.call("get_room") == _room and _is_rock(34, 18),
		"golpe e Punho Sísmico contra o portão não o abrem nem movem a Terra")


func _test_camera() -> void:
	print("-- Câmera e fundo")
	_terra.set_physics_process(false)
	var ok: bool = true
	var cover: bool = true
	var detail: String = ""
	for x: float in [0.0, 56.0, 256.0, 384.0, 536.0, 700.3, 768.0]:
		for y: float in [320.0, 120.0]:
			_terra.global_position = Vector2(x, y)
			await process_frame
			await process_frame
			var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
			if not Rect2(BOUNDS).grow(0.001).encloses(view):
				ok = false
				detail += " (%s: %s)" % [Vector2(x, y), view]
			cover = cover and _background_covers()
	_check(ok, "câmera nunca mostra fora da sala (14 posições)%s" % detail)
	_check(cover, "o fundo com parallax cobre a tela inteira em todas as posições")
	_terra.global_position = GATE_STOP
	await process_frame
	await process_frame
	var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
	_check(view.grow(0.001).encloses(GATE_RECT), "com a Terra no portão, ele aparece inteiro na tela %s" % view)
	_terra.set_physics_process(true)
	await _reset(GATE_STOP, -1.0)


func _test_path_back() -> void:
	print("-- Retorno do portão à saída oeste")
	var result: Dictionary = await _walk_with_hops(-1.0, 900)
	_check(absf(result.pos.x - TERRA_HALF_WIDTH) < 0.5 and absf(result.pos.y - FLOOR_Y) < 0.5
		and _body_rect(result.pos).intersects(WEST_EXIT), "caminho de volta livre até a passagem oeste, dentro da área da saída (%s)" % result.pos)


# --- Transições -------------------------------------------------------------------------------

func _test_transitions() -> void:
	print("-- Transições com a Sala 04")
	await _new_game(ROOM_04, &"west")
	var room_04: Room = _game.call("get_room") as Room
	var east: RoomExit = null
	for e: RoomExit in room_04.get_exits():
		if e.name == &"East":
			east = e
	_check(east != null and east.target_room == ROOM_PATH and east.target_entry == &"west"
		and east.collision_layer == 0 and east.collision_mask == 4 and east.monitoring and not east.monitorable
		and _exit_rect(east) == ROOM_04_EAST_EXIT, "Sala 04: saída East (passagem leste) → Sala 05 (west)")
	_check(not _body_rect(ROOM_04_EAST).grow(4.0).intersects(ROOM_04_EAST_EXIT), "a entrada east da Sala 04 fica fora da saída East")
	var burrower: Enemy = room_04.get_node("Enemies/CrystalBurrower") as Enemy
	(burrower.get_node("HealthComponent") as HealthComponent).take_damage(99)
	_check(_game.call("is_enemy_defeated", ROOM_04, BURROWER_ID), "Escavador derrotado antes de seguir")
	_terra.get_health().take_damage(2)
	await _wait(40)
	var health: int = _terra.get_health().current_health
	var terra_id: int = _terra.get_instance_id()
	# Ida 04 → 05 andando e golpeando (o golpe é cancelado na troca).
	await _reset(Vector2(820, 320), 1.0)
	Input.action_press("move_right")
	var busy_at_change: Array[bool] = [true]
	var center_at_change: Array[Vector2] = [Vector2.INF]
	var on_change: Callable = func(_r: Room) -> void:
		busy_at_change[0] = (_terra.get_node("MeleeAttack") as MeleeAttack).is_busy()
	_game.connect("room_changed", on_change)
	for i: int in 40:
		if _game.call("is_transitioning"):
			break
		if i % 6 == 0:
			Input.action_press("attack")
		elif i % 6 == 1:
			Input.action_release("attack")
		await physics_frame
	var arrival: Dictionary = await _wait_change()
	_game.disconnect("room_changed", on_change)
	_release_all()
	_check(_game.call("get_room_path") == ROOM_PATH and arrival.pos == WEST and arrival.facing == 1.0,
		"Sala 04 → 05: chega em west %s, olhando para a direita" % [arrival.pos])
	_check(not busy_at_change[0], "golpe cancelado na troca")
	_check(_camera_limits() == BOUNDS, "limites da câmera trocados para 768x368")
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada (%d)" % health)
	center_at_change[0] = _camera.get_screen_center_position()
	_check(center_at_change[0].is_equal_approx(_expected_center(WEST, BOUNDS)),
		"a câmera já está na posição final ao clarear o fade, sem salto (%s)" % center_at_change[0])
	await _wait(30)
	_check(_game.call("get_room_path") == ROOM_PATH and _terra.is_on_floor() and _terra.global_position.distance_to(WEST) < 1.0,
		"sem transição de volta em loop; de pé na chegada")
	# Volta 05 → 04.
	Input.action_press("move_left")
	arrival = await _wait_change()
	Input.action_release("move_left")
	_check(_game.call("get_room_path") == ROOM_04 and arrival.pos == ROOM_04_EAST and arrival.facing == -1.0,
		"Sala 05 → 04: chega em east %s, olhando para a esquerda" % [arrival.pos])
	_check(_camera_limits() == ROOM_04_BOUNDS, "limites da câmera de volta aos da Sala 04 (896x368)")
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada")
	var room: Room = _game.call("get_room") as Room
	_check(room.get_node_or_null("Enemies/CrystalBurrower") == null and _count_type(room, "Enemy") == 0
		and _game.call("get_defeated_enemies", ROOM_04) == [BURROWER_ID], "o Escavador derrotado continua fora da Sala 04")
	await _wait(30)
	_check(_game.call("get_room_path") == ROOM_04 and _terra.is_on_floor(), "sem voltar em loop para a Sala 05 (%s, %s, chão %s)" % [String(_game.call("get_room_path")).get_file(), _terra.global_position, _terra.is_on_floor()])
	# E de novo para a Sala 05 (ida e volta repetida).
	Input.action_press("move_right")
	arrival = await _wait_change()
	Input.action_release("move_right")
	_check(_game.call("get_room_path") == ROOM_PATH and arrival.pos == WEST, "ida e volta repetível (de novo na Sala 05)")


# --- Auxiliares -----------------------------------------------------------------------------

## Anda no sentido dir pulando sempre que encosta numa parede; para quando não avança mais
## (parede que o pulo não vence) ou no limite de ticks. Retorna a posição final e o x máximo.
func _walk_with_hops(dir: float, max_ticks: int) -> Dictionary:
	var move: String = "move_right" if dir > 0.0 else "move_left"
	_release_all()
	Input.action_press(move)
	var max_x: float = -INF
	var last_x: float = _terra.global_position.x
	var still: int = 0
	var jumping: int = 0
	for i: int in max_ticks:
		await physics_frame
		max_x = maxf(max_x, _terra.global_position.x)
		if jumping > 0:
			jumping -= 1
			if jumping == 0:
				Input.action_release("jump")
		elif _terra.is_on_floor() and _terra.is_on_wall():
			Input.action_press("jump")
			jumping = 20
		still = still + 1 if absf(_terra.global_position.x - last_x) < 0.01 and _terra.is_on_floor() else 0
		last_x = _terra.global_position.x
		if still > 90:
			break
	_release_all()
	await _wait(5)
	return {"pos": _terra.global_position, "max_x": max_x}


func _new_game(room_path: String, entrance: StringName) -> void:
	_release_all()
	if _game != null:
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	_game.set("start_room", room_path)
	_game.set("start_entrance", entrance)
	root.add_child(_game)
	_terra = _game.call("get_terra") as PlayerCharacter
	_camera = _game.get_node("Terra/Camera2D") as Camera2D
	await _wait(2)


## Espera a próxima troca de sala e o fim da transição; retorna a pose no instante da troca.
func _wait_change() -> Dictionary:
	var info: Dictionary = {"pos": Vector2.INF, "facing": 0.0}
	var on_change: Callable = func(_r: Room) -> void:
		info.pos = _terra.global_position
		info.facing = _terra.get_facing()
	_game.connect("room_changed", on_change)
	for i: int in 600:
		await process_frame
		if info.pos != Vector2.INF and not _game.call("is_transitioning"):
			break
	_game.disconnect("room_changed", on_change)
	return info


func _expected_center(p: Vector2, bounds: Rect2i) -> Vector2:
	return Vector2(clampf(p.x, VIEW.x / 2.0, bounds.end.x - VIEW.x / 2.0), clampf(p.y, VIEW.y / 2.0, bounds.end.y - VIEW.y / 2.0))


func _set_exits(enabled: bool) -> void:
	for e: RoomExit in _room.get_exits():
		e.monitoring = enabled


func _camera_limits() -> Rect2i:
	return Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
		_camera.limit_bottom - _camera.limit_top)


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
	return _rect_hits(_body_rect(feet).grow(-0.1), 3)


func _rect_hits(rect: Rect2, mask: int) -> int:
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	params.shape = shape
	params.transform = Transform2D(0.0, rect.get_center())
	params.collision_mask = mask
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
	var tile: TileData = _terrain.get_cell_tile_data(Vector2i(x, y))
	return tile != null and tile.terrain_set == 0


func _is_platform(x: int, y: int) -> bool:
	var tile: TileData = _terrain.get_cell_tile_data(Vector2i(x, y))
	return tile != null and tile.terrain_set == 1


func _base_of(cell: Vector2i) -> Vector2i:
	for table: Dictionary in [TilesetTest.ROCK, TilesetTest.PLATFORMS]:
		if table.has(cell) and table[cell][1] != null:
			return table[cell][1]
	return cell


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
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
