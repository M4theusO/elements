extends SceneTree
## Teste automatizado da Sala 03 — Ascensão (Galerias Esquecidas, etapa 4, sala vertical):
## estrutura, dimensões, terreno (peças, moldura, passagens, regras de altura livre), props,
## cada salto do caminho principal e do desvio com a física real da Terra (três pontos de
## impulso por salto), subida contínua, descida (sair de cada plataforma leva a uma mais baixa),
## câmera vertical (acompanha, sem tremer, dentro dos limites, fundo cobrindo a tela) e
## transições com a Sala 02 (vida, instância e persistência dos inimigos preservadas).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_03_ascent_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const ROOM_PATH: String = "res://world/levels/depths/forgotten_galleries/room_03_ascent.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const PROPS_DIR: String = "res://world/props/depths/"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const VIEW: Vector2 = Vector2(640, 360)
const ROOM_TILES: Vector2i = Vector2i(40, 45)
const BOUNDS: Rect2i = Rect2i(0, 0, 640, 720)
const ROOM_CHILDREN: Array[String] = ["Background", "Terrain", "Props", "Enemies", "Entrances", "Exits"]

## Geometria esperada (células), igual à do gerador.
const ROCK_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 40, 2), Rect2i(0, 0, 2, 38), Rect2i(38, 0, 2, 10), Rect2i(38, 14, 2, 31),
	Rect2i(0, 42, 40, 3), Rect2i(8, 40, 4, 2), Rect2i(32, 32, 6, 2), Rect2i(2, 22, 4, 2),
	Rect2i(26, 14, 12, 2), Rect2i(2, 31, 4, 2),
]
const PLATFORM_RECTS: Array[Rect2i] = [
	Rect2i(14, 38, 4, 1), Rect2i(20, 36, 4, 1), Rect2i(26, 34, 4, 1), Rect2i(26, 30, 4, 1),
	Rect2i(20, 28, 4, 1), Rect2i(14, 26, 4, 1), Rect2i(8, 24, 4, 1), Rect2i(8, 20, 4, 1),
	Rect2i(14, 18, 4, 1), Rect2i(20, 16, 4, 1), Rect2i(7, 29, 3, 1), Rect2i(12, 27, 2, 1),
]
const FRAME_EXTRA: Array[Rect2i] = [Rect2i(-2, 36, 2, 8), Rect2i(40, 8, 2, 8)]
## Passagens (células livres na parede): de baixo, à esquerda (Sala 02); de cima, à direita (Sala 04).
const WEST_PASSAGE_ROWS: Vector2i = Vector2i(38, 41)
const EAST_PASSAGE_ROWS: Vector2i = Vector2i(10, 13)

## Superfícies em px: Rect2(x inicial, topo, largura, 0).
const FLOOR: Rect2 = Rect2(32, 672, 96, 0)        # chão até a face do S1
const S1: Rect2 = Rect2(128, 640, 64, 0)
const A2: Rect2 = Rect2(224, 608, 64, 0)
const A3: Rect2 = Rect2(320, 576, 64, 0)
const A4: Rect2 = Rect2(416, 544, 64, 0)
const R1: Rect2 = Rect2(512, 512, 96, 0)
const B1: Rect2 = Rect2(416, 480, 64, 0)
const B2: Rect2 = Rect2(320, 448, 64, 0)
const B3: Rect2 = Rect2(224, 416, 64, 0)
const B4: Rect2 = Rect2(128, 384, 64, 0)
const L1: Rect2 = Rect2(32, 352, 64, 0)
const C1: Rect2 = Rect2(128, 320, 64, 0)
const C2: Rect2 = Rect2(224, 288, 64, 0)
const C3: Rect2 = Rect2(320, 256, 64, 0)
const TOP: Rect2 = Rect2(416, 224, 192, 0)
const D: Rect2 = Rect2(32, 496, 64, 0)
const E: Rect2 = Rect2(112, 464, 48, 0)
const F: Rect2 = Rect2(192, 432, 32, 0)
const WEST: Vector2 = Vector2(56, 672)
const EAST: Vector2 = Vector2(584, 224)
const WEST_EXIT: Rect2 = Rect2(0, 608, 32, 64)

const TERRA_HALF_WIDTH: float = 8.0
const TERRA_SIZE: Vector2 = Vector2(16, 46)
## Altura que a cabeça da Terra alcança acima da superfície de partida (pulo de 56 + 46 de altura).
const JUMP_HEAD_CLEARANCE: float = 102.0
## Pontos de impulso: distância da frente do corpo até a borda no instante do pulo.
const TAKEOFF_OFFSETS: Array[float] = [2.0, 10.0, 20.0]

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _room: Room
var _terra: PlayerCharacter
var _camera: Camera2D
var _terrain: TileMapLayer
var _jumps: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: Sala 03 — Ascensão")
	await process_frame
	await _new_game(ROOM_PATH, &"west")
	_room = _game.call("get_room") as Room
	_check(_room != null and _room.scene_file_path == ROOM_PATH, "a Game carrega a Sala 03")
	if _room == null:
		_finish()
		return
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_test_structure()
	if _terrain == null:
		_finish()
		return
	_test_terrain_cells()
	_test_clearance_rules()
	_test_props()
	await _test_arrival()
	# Geometria com a saída desligada (a transição tem casos próprios no fim).
	_set_exits(false)
	await _test_main_jumps()
	await _test_detour()
	await _test_continuous_climb()
	await _test_descent()
	await _test_camera_points()
	_set_exits(true)
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
	_check(bounds == BOUNDS and bounds.size == ROOM_TILES * TILE, "camera_bounds = 640x720 (40x45 tiles)")
	_check(_camera_limits() == BOUNDS, "limites da câmera: left 0, top 0, right 640, bottom 720")
	var bg: Node2D = _room.get_node_or_null("Background") as Node2D
	_check(bg != null and bg.scene_file_path == PARALLAX_PATH and bg.position == Vector2.ZERO, "Background é instância de depths_parallax.tscn")
	_check(_terrain != null and _terrain.tile_set != null and _terrain.tile_set.resource_path == TILESET_PATH
		and _terrain.collision_enabled, "Terrain: TileMapLayer com depths_tileset.tres e colisão ligada")
	var entrances: Array[String] = []
	for child: Node in _room.get_node("Entrances").get_children():
		if child is Marker2D:
			entrances.append(String(child.name))
	_check(entrances == ["west", "east"] and _room.get_entrance(&"west").position == WEST
		and _room.get_entrance(&"east").position == EAST, "entradas west %s (embaixo) e east %s (em cima)" % [WEST, EAST])
	_check(_room.get_entrance_facing(&"west") == 1.0 and _room.get_entrance_facing(&"east") == -1.0, "chegada por west olha para a direita; por east, para a esquerda")
	var exits: Array[RoomExit] = _room.get_exits()
	_check(exits.size() == 1 and _room.get_node("Exits").get_child_count() == 1 and exits[0].name == &"West",
		"uma única saída, West; a de cima (Sala 04) ainda não existe")
	if exits.size() == 1:
		var e: RoomExit = exits[0]
		_check(e.target_room == ROOM_02 and e.target_entry == &"east", "West leva à Sala 02, entrada east")
		_check(e.collision_layer == 0 and e.collision_mask == 4 and e.monitoring and not e.monitorable, "West: layer 0, mask só player")
		_check(_exit_rect(e) == WEST_EXIT, "área da saída West %s (dentro da passagem de baixo)" % _exit_rect(e))
	_check(_room.get_node("Enemies").get_child_count() == 0 and _count_type(_game, "Enemy") == 0
		and _room.get_persistent_enemies().is_empty(), "sem inimigos")
	_check(_count_type(_room, "PlayerCharacter") == 0 and _count_type(_room, "Camera2D") == 0
		and _count_type(_room, "StaticBody2D") == 0, "sala sem Terra, câmera ou corpos fora do tilemap")
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
	print("-- Terreno e colisões")
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
	var rock_ok: bool = true
	var platform_ok: bool = true
	var platforms: int = 0
	for cell: Vector2i in _terrain.get_used_cells():
		var data: TileData = _terrain.get_cell_tile_data(cell)
		if data.terrain_set == 0:
			rock_ok = rock_ok and data.get_collision_polygons_count(0) > 0 and data.get_collision_polygons_count(1) == 0
		else:
			platforms += 1
			platform_ok = platform_ok and data.get_collision_polygons_count(1) > 0 and data.get_collision_polygons_count(0) == 0 \
				and data.is_collision_polygon_one_way(1, 0)
	_check(rock_ok, "toda rocha colide em world")
	_check(platform_ok and platforms == 45, "%d tiles de plataforma, todos one-way em platforms" % platforms)
	var open_edges: Array[Vector2i] = []
	for y: int in ROOM_TILES.y:
		if not _is_rock(0, y) and not (y >= WEST_PASSAGE_ROWS.x and y <= WEST_PASSAGE_ROWS.y):
			open_edges.append(Vector2i(0, y))
		if not _is_rock(ROOM_TILES.x - 1, y) and not (y >= EAST_PASSAGE_ROWS.x and y <= EAST_PASSAGE_ROWS.y):
			open_edges.append(Vector2i(ROOM_TILES.x - 1, y))
	for x: int in ROOM_TILES.x:
		for y: int in [0, ROOM_TILES.y - 1]:
			if not _is_rock(x, y):
				open_edges.append(Vector2i(x, y))
	_check(open_edges.is_empty(), "bordas da câmera fechadas por rocha, exceto as duas passagens %s" % [open_edges])
	var west_ok: bool = true
	for y: int in range(WEST_PASSAGE_ROWS.x, WEST_PASSAGE_ROWS.y + 1):
		west_ok = west_ok and not _is_rock(0, y) and not _is_rock(1, y) and _is_rock(-1, y)
	_check(west_ok and _is_rock(0, 42) and _is_rock(0, 37), "passagem de baixo (oeste) de 4 tiles, sobre o chão")
	var east_ok: bool = true
	for y: int in range(EAST_PASSAGE_ROWS.x, EAST_PASSAGE_ROWS.y + 1):
		east_ok = east_ok and not _is_rock(38, y) and not _is_rock(39, y) and _is_rock(40, y)
	_check(east_ok and _is_rock(38, 14) and _is_rock(38, 9), "passagem de cima (leste) de 4 tiles sobre a saliência do topo, fechada pela moldura até a Sala 04")


## Regras de altura livre conferidas célula a célula.
func _test_clearance_rules() -> void:
	print("-- Altura livre")
	var bonk: Array[String] = []
	var low_platform: Array[String] = []
	var rows_needed: int = ceili(JUMP_HEAD_CLEARANCE / TILE)
	for cell: Vector2i in _terrain.get_used_cells():
		if cell.x < 2 or cell.x > ROOM_TILES.x - 3 or cell.y < 2 or cell.y >= ROOM_TILES.y:
			continue
		if _is_solid_or_platform(cell.x, cell.y - 1):
			continue
		# Superfície de pé: nenhuma rocha até a altura da cabeça no pulo (one-way não bate).
		for dy: int in range(1, rows_needed + 1):
			if _is_rock(cell.x, cell.y - dy):
				bonk.append("%s (rocha %d tiles acima)" % [cell, dy])
				break
		# One-way: nenhuma superfície de pé logo abaixo (a menos de 4 tiles), para a cabeça não
		# atravessar o desenho da plataforma.
		if _is_platform(cell.x, cell.y):
			for dy: int in range(1, 4):
				var below: Vector2i = Vector2i(cell.x, cell.y + dy)
				if _is_solid_or_platform(below.x, below.y) and not _is_solid_or_platform(below.x, below.y - 1):
					low_platform.append("%s sobre %s" % [cell, below])
	_check(bonk.is_empty(), "nenhuma rocha a menos de %.0f px acima de uma superfície (sem bater a cabeça no pulo) %s" % [JUMP_HEAD_CLEARANCE, bonk.slice(0, 6)])
	_check(low_platform.is_empty(), "plataformas one-way a pelo menos 4 tiles de qualquer superfície abaixo %s" % [low_platform.slice(0, 6)])


func _test_props() -> void:
	print("-- Props")
	var props: Array[Node] = _room.get_node("Props").get_children()
	var ok: bool = props.size() > 0
	var inside_rock: Array[String] = []
	var crystals: int = 0
	var vegetation: int = 0
	for prop: Node in props:
		ok = ok and prop is Sprite2D and prop.scene_file_path.begins_with(PROPS_DIR)
		crystals += 1 if prop.scene_file_path.contains("/crystals/") else 0
		vegetation += 1 if prop.scene_file_path.contains("/vegetation/") else 0
		if prop is Sprite2D and _prop_touches_rock(prop as Sprite2D):
			inside_rock.append(String(prop.name))
	_check(ok and crystals + vegetation == props.size(), "%d props já commitados (%d cristais, %d de vegetação)" % [props.size(), crystals, vegetation])
	_check(inside_rock.is_empty(), "nenhum pixel de prop dentro de rocha %s" % [inside_rock])
	var large: Node2D = _room.get_node_or_null("Props/CrystalLargeDetour") as Node2D
	_check(large != null and large.position == Vector2(64, D.position.y), "cristal grande em destaque na saliência do desvio")
	var clear: bool = true
	for prop: Node in props:
		var p: Vector2 = (prop as Node2D).position
		clear = clear and p.distance_to(WEST) > 96.0 and p.distance_to(EAST) > 96.0
	_check(clear, "nenhum prop a menos de 96 px das entradas")


# --- Física: saltos ---------------------------------------------------------------------------

func _test_arrival() -> void:
	print("-- Chegada por west")
	_check(_terra.global_position == WEST and _terra.get_facing() == 1.0, "Terra em west, embaixo, olhando para a direita")
	_check(_shape_hits(WEST) == 0 and _shape_hits(EAST) == 0, "corpo da Terra nas duas entradas sem sobreposição com o terreno")
	_check(not _body_rect(WEST).intersects(WEST_EXIT), "a chegada não fica dentro da saída West")
	await _wait(20)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(WEST) < 0.5, "apoiada no chão")


func _test_main_jumps() -> void:
	print("-- Saltos do caminho principal (3 pontos de impulso cada)")
	var hops: Array = [["chão → S1 (+2)", FLOOR, S1, 1.0], ["S1 → A2 (+2)", S1, A2, 1.0],
		["A2 → A3 (+2)", A2, A3, 1.0], ["A3 → A4 (+2)", A3, A4, 1.0], ["A4 → R1 (+2)", A4, R1, 1.0],
		["R1 → B1 (+2)", R1, B1, -1.0], ["B1 → B2 (+2)", B1, B2, -1.0], ["B2 → B3 (+2)", B2, B3, -1.0],
		["B3 → B4 (+2)", B3, B4, -1.0], ["B4 → L1 (+2)", B4, L1, -1.0], ["L1 → C1 (+2)", L1, C1, 1.0],
		["C1 → C2 (+2)", C1, C2, 1.0], ["C2 → C3 (+2)", C2, C3, 1.0], ["C3 → topo (+2)", C3, TOP, 1.0]]
	_check(hops.size() == 14, "14 saltos do chão ao topo")
	for hop: Array in hops:
		await _check_hop(hop[0], hop[1], hop[2], hop[3])


func _test_detour() -> void:
	print("-- Desvio opcional")
	# Entrada: sair do B4 pela esquerda sem o pulo para L1 cai no desvio (E ou D, conforme o
	# impulso); dos dois há volta ao caminho.
	await _reset(Vector2(B4.position.x + 20.0, B4.position.y), -1.0)
	Input.action_press("move_left")
	var landed: float = await _until_landed(240)
	Input.action_release("move_left")
	_check(absf(landed - E.position.y) < 0.5 or absf(landed - D.position.y) < 0.5,
		"saindo do B4 pela esquerda sem pular para L1, cai no desvio (y %.1f; E 464 ou D 496)" % landed)
	await _check_hop("E → D (−2, cristal)", E, D, -1.0)
	await _check_hop("D → E (+2, volta)", D, E, 1.0)
	await _check_hop("E → F (+2)", E, F, 1.0)
	await _check_hop("F → B3 (+1, de volta ao caminho)", F, B3, 1.0)


func _check_hop(label: String, src: Rect2, dst: Rect2, dir: float) -> void:
	var results: Array[String] = []
	var ok: bool = true
	for off: float in TAKEOFF_OFFSETS:
		var r: Dictionary = await _hop(src, dst, dir, off)
		var landed_ok: bool = r.jumped and not r.bonk and absf(r.y - dst.position.y) < 0.5 \
			and r.x > dst.position.x - TERRA_HALF_WIDTH and r.x < dst.end.x + TERRA_HALF_WIDTH
		ok = ok and landed_ok
		results.append("%s%.0f→(%.0f, %.0f)%s" % ["" if landed_ok else "FALHA ", off, r.x, r.y, " bateu a cabeça" if r.bonk else ""])
	_check(ok, "%s: pousa com impulso a %s px da borda %s" % [label, TAKEOFF_OFFSETS, results])


## Corre a partir da outra ponta da superfície, pula quando a frente do corpo está a `off` px da
## borda (segurando pulo e direção) e espera pousar.
func _hop(src: Rect2, dst: Rect2, dir: float, off: float) -> Dictionary:
	var start_x: float = src.position.x + 10.0 if dir > 0.0 else src.end.x - 10.0
	await _reset(Vector2(start_x, src.position.y), dir)
	var edge: float = src.end.x if dir > 0.0 else src.position.x
	var move: String = "move_right" if dir > 0.0 else "move_left"
	Input.action_press(move)
	var jumped: bool = false
	var left_ground: bool = false
	var bonk: bool = false
	for i: int in 300:
		await physics_frame
		var lead: float = _terra.global_position.x + TERRA_HALF_WIDTH * dir
		if not jumped:
			if (lead - (edge - off * dir)) * dir >= 0.0 or _terra.is_on_wall():
				Input.action_press("jump")
				jumped = true
			elif not _terra.is_on_floor():
				break
			continue
		left_ground = left_ground or not _terra.is_on_floor()
		bonk = bonk or _terra.is_on_ceiling()
		if left_ground and _terra.is_on_floor():
			break
	_release_all()
	if jumped:
		_jumps += 1
	return {"jumped": jumped, "bonk": bonk, "x": _terra.global_position.x, "y": _terra.global_position.y}


func _test_continuous_climb() -> void:
	print("-- Subida contínua, da entrada ao topo")
	await _reset(WEST, 1.0)
	var path: Array = [[FLOOR, S1, 1.0], [S1, A2, 1.0], [A2, A3, 1.0], [A3, A4, 1.0], [A4, R1, 1.0],
		[R1, B1, -1.0], [B1, B2, -1.0], [B2, B3, -1.0], [B3, B4, -1.0], [B4, L1, -1.0],
		[L1, C1, 1.0], [C1, C2, 1.0], [C2, C3, 1.0], [C3, TOP, 1.0]]
	var steps: int = 0
	var cam: Dictionary = {"ok": true, "max_step": 0.0, "detail": ""}
	for step: Array in path:
		var landed: bool = await _run_to_edge_and_jump(step[0], step[2], 10.0, cam)
		if not landed or absf(_terra.global_position.y - (step[1] as Rect2).position.y) > 0.5:
			break
		steps += 1
	_check(steps == path.size(), "sobe sem recomeçar: %d de %d saltos (pés em y %.0f)" % [steps, path.size(), _terra.global_position.y])
	_check(cam.ok, "a câmera acompanha a subida quadro a quadro, sem atraso nem salto (maior passo %.1f px)%s" % [cam.max_step, cam.detail])
	# No topo: anda até a passagem de cima, fechada (a Sala 04 não existe).
	Input.action_press("move_right")
	await _wait(150)
	Input.action_release("move_right")
	_check(absf(_terra.global_position.x - (BOUNDS.end.x - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - TOP.position.y) < 0.5
		and _game.call("get_room") == _room, "a passagem de cima termina na moldura, sem transição")


## Parte do ponto atual (já na superfície `src`): anda até a borda e pula. Retorna se pousou.
func _run_to_edge_and_jump(src: Rect2, dir: float, off: float, cam: Dictionary) -> bool:
	var edge: float = src.end.x if dir > 0.0 else src.position.x
	var move: String = "move_right" if dir > 0.0 else "move_left"
	_release_all()
	Input.action_press(move)
	var jumped: bool = false
	var left_ground: bool = false
	for i: int in 400:
		await physics_frame
		_track_camera(cam)
		var lead: float = _terra.global_position.x + TERRA_HALF_WIDTH * dir
		if not jumped:
			if (lead - (edge - off * dir)) * dir >= 0.0 or _terra.is_on_wall():
				Input.action_press("jump")
				jumped = true
			continue
		left_ground = left_ground or not _terra.is_on_floor()
		if left_ground and _terra.is_on_floor():
			_release_all()
			return true
	_release_all()
	return false


func _test_descent() -> void:
	print("-- Descida e retorno")
	# Sair por qualquer borda livre de qualquer plataforma ou saliência leva a uma superfície mais baixa.
	var surfaces: Array = [["S1", S1, [1.0, -1.0]], ["A2", A2, [1.0, -1.0]], ["A3", A3, [1.0, -1.0]],
		["A4", A4, [1.0, -1.0]], ["R1", R1, [-1.0]], ["B1", B1, [1.0, -1.0]], ["B2", B2, [1.0, -1.0]],
		["B3", B3, [1.0, -1.0]], ["B4", B4, [1.0, -1.0]], ["L1", L1, [1.0]], ["C1", C1, [1.0, -1.0]],
		["C2", C2, [1.0, -1.0]], ["C3", C3, [1.0, -1.0]], ["topo", TOP, [-1.0]], ["D", D, [1.0]],
		["E", E, [1.0, -1.0]], ["F", F, [1.0, -1.0]]]
	var stuck: Array[String] = []
	for s: Array in surfaces:
		for dir: float in s[2]:
			var src: Rect2 = s[1]
			await _reset(Vector2(src.get_center().x, src.position.y), dir)
			Input.action_press("move_right" if dir > 0.0 else "move_left")
			var landed: float = await _until_landed(300)
			_release_all()
			if not (landed > src.position.y + 0.5 and _terra.is_on_floor()):
				stuck.append("%s %s (y %.0f)" % [s[0], "→" if dir > 0.0 else "←", landed])
	_check(stuck.is_empty(), "sair andando de qualquer borda livre leva a uma superfície mais baixa, sem prender a Terra %s" % [stuck])
	# Do topo até o chão sem pular: anda, cai pelas bordas e, ao encostar numa parede, vira
	# (como um jogador descendo).
	await _reset(Vector2(TOP.end.x - 30.0, TOP.position.y), -1.0)
	var cam: Dictionary = {"ok": true, "max_step": 0.0, "detail": ""}
	var dir: float = -1.0
	var turns: int = 0
	var landings: Array[int] = []
	Input.action_press("move_left")
	for i: int in 3000:
		await physics_frame
		_track_camera(cam)
		if _terra.is_on_floor() and absf(_terra.global_position.y - FLOOR.position.y) < 0.5:
			break
		if _terra.is_on_floor() and (landings.is_empty() or landings[-1] != int(_terra.global_position.y)):
			landings.append(int(_terra.global_position.y))
		if _terra.is_on_floor() and _terra.is_on_wall():
			Input.action_release("move_left" if dir < 0.0 else "move_right")
			dir = -dir
			turns += 1
			Input.action_press("move_left" if dir < 0.0 else "move_right")
	_release_all()
	var at_floor: bool = absf(_terra.global_position.y - FLOOR.position.y) < 0.5
	_check(at_floor, "do topo, sem pular (só andando e virando nas paredes), a Terra desce até o chão (y %.0f; pousos %s; %d viradas)" % [_terra.global_position.y, landings, turns])
	_check(cam.ok, "a câmera acompanha a descida quadro a quadro (maior passo %.1f px)%s" % [cam.max_step, cam.detail])
	Input.action_press("move_left")
	await _wait(120)
	Input.action_release("move_left")
	_check(absf(_terra.global_position.x - TERRA_HALF_WIDTH) < 0.5 and _body_rect(_terra.global_position).intersects(WEST_EXIT),
		"segue pelo chão até a passagem de baixo, dentro da área da saída West (x %.1f)" % _terra.global_position.x)


func _until_landed(max_ticks: int) -> float:
	var left_ground: bool = false
	for i: int in max_ticks:
		await physics_frame
		left_ground = left_ground or not _terra.is_on_floor()
		if left_ground and _terra.is_on_floor():
			break
	return _terra.global_position.y


# --- Câmera -------------------------------------------------------------------------------

## Compara a câmera com a posição da Terra (limitada à sala) no mesmo quadro.
func _track_camera(cam: Dictionary) -> void:
	await process_frame
	var center: Vector2 = _camera.get_screen_center_position()
	var expected: Vector2 = _expected_center(_terra.global_position)
	var view: Rect2 = Rect2(center - VIEW / 2.0, VIEW)
	var inside: bool = view.position.x >= -0.001 and view.position.y >= -0.001 and view.end.x <= BOUNDS.end.x + 0.001 \
		and view.end.y <= BOUNDS.end.y + 0.001
	if cam.has("last"):
		cam.max_step = maxf(cam.max_step, (center - (cam.last as Vector2)).length())
	cam.last = center
	if not inside or center.distance_to(expected) > 0.5:
		if cam.ok:
			cam.detail = " (Terra %s: centro %s, esperado %s)" % [_terra.global_position, center, expected]
		cam.ok = false
	if cam.max_step > 12.0:
		cam.ok = false


func _expected_center(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, VIEW.x / 2.0, BOUNDS.end.x - VIEW.x / 2.0), clampf(p.y, VIEW.y / 2.0, BOUNDS.end.y - VIEW.y / 2.0))


func _test_camera_points() -> void:
	print("-- Câmera nos limites e fundo")
	_terra.set_physics_process(false)
	var ok: bool = true
	var cover: bool = true
	var detail: String = ""
	for p: Vector2 in [Vector2(56, 720), Vector2(320, 672), Vector2(320, 540), Vector2(200, 400.5),
			Vector2(320, 180), Vector2(584, 224), Vector2(0, 0), Vector2(640, 720), Vector2(450, 333.3)]:
		_terra.global_position = p
		await process_frame
		await process_frame
		var center: Vector2 = _camera.get_screen_center_position()
		var view: Rect2 = Rect2(center - VIEW / 2.0, VIEW)
		if center.distance_to(_expected_center(p)) > 0.01 or view.position.y < -0.001 or view.end.y > BOUNDS.end.y + 0.001 \
				or view.position.x != 0.0 or view.end.x != BOUNDS.end.x:
			ok = false
			detail += " (%s: %s)" % [p, view]
		cover = cover and _background_covers()
	_check(ok, "a câmera fica presa na largura (x 0–640) e vai do topo (y 0) ao fundo (y 720), sem passar dos limites%s" % detail)
	_check(cover, "o fundo com parallax cobre a tela inteira em todas as alturas")
	_terra.set_physics_process(true)


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


# --- Transições -----------------------------------------------------------------------------

func _test_transitions() -> void:
	print("-- Transições com a Sala 02")
	await _new_game(ROOM_02, &"west")
	var room_02: Room = _game.call("get_room") as Room
	var fragment: Enemy = room_02.get_node("Enemies/LivingFragment") as Enemy
	(fragment.get_node("HealthComponent") as HealthComponent).take_damage(99)
	_check(_game.call("is_enemy_defeated", ROOM_02, &"gallery_fragment_01"), "Fragmento da Sala 02 derrotado antes de subir")
	var e: Array[RoomExit] = room_02.get_exits()
	var east: RoomExit = null
	for x: RoomExit in e:
		if x.name == &"East":
			east = x
	_check(east != null and east.target_room == ROOM_PATH and east.target_entry == &"west"
		and east.collision_layer == 0 and east.collision_mask == 4 and not east.monitorable, "Sala 02: saída East → Sala 03 (west)")
	if east != null:
		var shape: RectangleShape2D = (east.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
		_check(Rect2(east.position - shape.size / 2.0, shape.size) == Rect2(992, 256, 32, 64)
			and not _body_rect((room_02.get_entrance(&"east") as Marker2D).position).grow(4.0).intersects(Rect2(992, 256, 32, 64)),
			"área da saída East (992–1024) dentro da passagem, a entrada east da Sala 02 fora dela")
	_terra.get_health().take_damage(2)
	await _wait(40)
	var health: int = _terra.get_health().current_health
	var terra_id: int = _terra.get_instance_id()
	# Ida 02 → 03 andando.
	await _reset(Vector2(940, 320), 1.0)
	Input.action_press("move_right")
	var arrival: Dictionary = await _wait_change()
	Input.action_release("move_right")
	_check(_game.call("get_room_path") == ROOM_PATH and arrival.pos == WEST and arrival.facing == 1.0,
		"Sala 02 → 03: chega em west, embaixo, olhando para a direita (%s)" % [arrival.pos])
	_check(_camera_limits() == BOUNDS, "limites da câmera trocados para 640x720")
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada (%d)" % health)
	await process_frame
	await process_frame
	var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
	_check(view == Rect2(0, 360, 640, 360), "a câmera chega já no fundo da sala %s" % view)
	await _wait(30)
	_check(_game.call("get_room_path") == ROOM_PATH, "sem transição de volta em loop")
	# Volta 03 → 02 andando para a esquerda.
	Input.action_press("move_left")
	arrival = await _wait_change()
	Input.action_release("move_left")
	_check(_game.call("get_room_path") == ROOM_02 and arrival.pos == Vector2(968, 320) and arrival.facing == -1.0,
		"Sala 03 → 02: chega em east, olhando para a esquerda (%s)" % [arrival.pos])
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada")
	_check((_game.call("get_room") as Room).get_node_or_null("Enemies/LivingFragment") == null
		and _game.call("get_defeated_enemies", ROOM_02) == [&"gallery_fragment_01"], "o Fragmento derrotado continua fora da Sala 02")
	_check(_camera_limits() == Rect2i(0, 0, 1024, 368), "limites da câmera de volta aos da Sala 02")


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game(room_path: String, entrance: StringName) -> void:
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


func _set_exits(enabled: bool) -> void:
	for e: RoomExit in _room.get_exits():
		e.monitoring = enabled


func _camera_limits() -> Rect2i:
	return Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
		_camera.limit_bottom - _camera.limit_top)


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
		for r: Rect2i in PLATFORM_RECTS:
			if r.has_point(cell):
				return "="
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


func _is_solid_or_platform(x: int, y: int) -> bool:
	return _terrain.get_cell_tile_data(Vector2i(x, y)) != null


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
