extends SceneTree
## Teste automatizado da Sala 04 — Cristais (Galerias Esquecidas, etapa 5): estrutura,
## dimensões, entradas e saídas (oeste para a Sala 03, leste para a Sala 05), terreno
## (peças, moldura, passagens, pilares sólidos), props, o único Escavador de Cristal (patrulha,
## chegada sem encontro, detecção, investida interrompida pelos dois pilares, esquiva subindo no
## pilar, janela de atordoamento, contra-ataque e derrota com golpes reais), câmera e fundo,
## percurso nos dois sentidos, transições com a Sala 03 (cuja saída de cima fica 96 px acima da
## chegada nesta sala) e persistência do Escavador (morte registrada na hora, derrotado na volta,
## restaurado ao reiniciar, vivo e ferido volta inteiro).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_04_crystals_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_03: String = "res://world/levels/depths/forgotten_galleries/room_03_ascent.tscn"
const ROOM_PATH: String = "res://world/levels/depths/forgotten_galleries/room_04_crystals.tscn"
const ROOM_05: String = "res://world/levels/depths/forgotten_galleries/room_05_ancient_gate.tscn"
const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const BURROWER_PATH: String = "res://entities/enemies/crystal_burrower/crystal_burrower.tscn"
const PROPS_DIR: String = "res://world/props/depths/"
const TilesetTest: Script = preload("res://tests/tilesets/depths_tileset_test.gd")

const TILE: int = 16
const VIEW: Vector2 = Vector2(640, 360)
const ROOM_TILES: Vector2i = Vector2i(56, 23)
const BOUNDS: Rect2i = Rect2i(0, 0, 896, 368)
const ROOM_03_BOUNDS: Rect2i = Rect2i(0, 0, 640, 720)
const ROOM_CHILDREN: Array[String] = ["Background", "Terrain", "Props", "Enemies", "Entrances", "Exits"]

## Geometria esperada (células), igual à do gerador; fora da sala, moldura de 1 tile
## (2 atrás das passagens).
const ROCK_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 56, 2), Rect2i(0, 0, 2, 16), Rect2i(54, 0, 2, 16), Rect2i(0, 20, 56, 3),
	Rect2i(14, 19, 4, 1), Rect2i(18, 18, 2, 2), Rect2i(36, 18, 2, 2), Rect2i(38, 19, 4, 1),
	Rect2i(20, 2, 6, 2), Rect2i(30, 2, 6, 2), Rect2i(2, 9, 2, 2), Rect2i(52, 9, 2, 2),
]
const FRAME_EXTRA: Array[Rect2i] = [Rect2i(-2, 14, 2, 8), Rect2i(56, 14, 2, 8)]
const PILLAR_CELLS: Array[Rect2i] = [Rect2i(18, 18, 2, 2), Rect2i(36, 18, 2, 2)]

## Geometria em px (pés = global_position).
const FLOOR_Y: float = 320.0
const RISE_Y: float = 304.0
const PILLAR_Y: float = 288.0
const WEST: Vector2 = Vector2(56, 320)
const EAST: Vector2 = Vector2(840, 320)
const RISE_WEST: Rect2 = Rect2(224, 304, 64, 16)
const PILLAR_WEST: Rect2 = Rect2(288, 288, 32, 32)
const PILLAR_EAST: Rect2 = Rect2(576, 288, 32, 32)
const RISE_EAST: Rect2 = Rect2(608, 304, 64, 16)
## Arena plana entre os pilares.
const ARENA: Rect2 = Rect2(320, 320, 256, 0)
const WEST_EXIT: Rect2 = Rect2(0, 256, 32, 64)
const EAST_EXIT: Rect2 = Rect2(864, 256, 32, 64)
## Saída de cima da Sala 03 e a entrada dela (lado da Sala 03).
const ROOM_03_EAST: Vector2 = Vector2(584, 224)
const ROOM_03_EAST_EXIT: Rect2 = Rect2(608, 160, 32, 64)
const BURROWER_POS: Vector2 = Vector2(448, 320)
const BURROWER_ID: StringName = &"crystal_burrower_01"
const BURROWER_HALF_WIDTH: float = 16.0
## Topo dos pilares, onde a Terra se esquiva.
const PILLAR_WEST_TOP: Vector2 = Vector2(304, 288)
const PILLAR_EAST_TOP: Vector2 = Vector2(592, 288)
const TERRA_HALF_WIDTH: float = 8.0
const TERRA_SIZE: Vector2 = Vector2(16, 46)
## Distância do contra-ataque: a Terra atrás do Escavador, com o soco alcançando a Hurtbox.
const COUNTER_DISTANCE: float = 36.0
const TICK: float = 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _room: Room
var _terra: PlayerCharacter
var _camera: Camera2D
var _terrain: TileMapLayer
var _burrower: CrystalBurrower


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: Sala 04 — Cristais")
	await process_frame
	await _new_game(ROOM_PATH, &"west")
	_room = _game.call("get_room") as Room
	_check(_room != null and _room.scene_file_path == ROOM_PATH, "a Game carrega a Sala 04")
	if _room == null:
		_finish()
		return
	_terrain = _room.get_node_or_null("Terrain") as TileMapLayer
	_burrower = _room.get_node_or_null("Enemies/CrystalBurrower") as CrystalBurrower
	_test_structure()
	if _terrain == null or _burrower == null:
		_finish()
		return
	_test_terrain_cells()
	_test_props()
	await _test_arrival()
	await _test_patrol()
	await _test_dodge_and_counter()
	await _test_east_pillar()
	await _test_defeat()
	# Câmera depois do combate: teleportar a Terra pela sala com o Escavador vivo o provocaria.
	await _test_camera()
	# Daqui em diante, só a geometria (o Escavador já foi derrotado) e com a saída desligada.
	_set_exits(false)
	await _test_path_east()
	await _test_path_west()
	await _test_transitions()
	await _test_persistence()
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
	_check(bounds == BOUNDS and bounds.size == ROOM_TILES * TILE, "camera_bounds = 896x368 (56x23 tiles)")
	_check(_camera_limits() == BOUNDS, "limites da câmera = camera_bounds")
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
		and _room.get_entrance(&"east").position == EAST, "entradas west %s e east %s (chegada da Sala 05)" % [WEST, EAST])
	_check(_room.get_entrance_facing(&"west") == 1.0 and _room.get_entrance_facing(&"east") == -1.0,
		"chegando por west olha para a direita; por east, para a esquerda")
	var exits: Array[RoomExit] = _room.get_exits()
	_check(exits.size() == 2 and _room.get_node("Exits").get_child_count() == 2 and exits[0].name == &"West"
		and exits[1].name == &"East", "duas saídas: West (Sala 03) e East (Sala 05)")
	if exits.size() == 2:
		var east: RoomExit = exits[1]
		_check(east.target_room == ROOM_05 and east.target_entry == &"west" and east.collision_layer == 0
			and east.collision_mask == 4 and east.monitoring and not east.monitorable, "East leva à Sala 05, entrada west (layer 0, mask só player)")
		_check(_exit_rect(east) == EAST_EXIT and not _body_rect(EAST).grow(4.0).intersects(EAST_EXIT),
			"área da saída East %s dentro da passagem leste; a entrada east fica fora dela" % _exit_rect(east))
		var e: RoomExit = exits[0]
		_check(e.target_room == ROOM_03 and e.target_entry == &"east", "West leva à Sala 03, entrada east (a de cima)")
		_check(e.collision_layer == 0 and e.collision_mask == 4 and e.monitoring and not e.monitorable,
			"West: layer 0, mask só player, monitoring ligado, monitorable desligado")
		_check(_exit_rect(e) == WEST_EXIT and not _body_rect(WEST).grow(4.0).intersects(WEST_EXIT),
			"área da saída West %s dentro da passagem; a entrada west fica fora dela" % _exit_rect(e))
	var enemies: Array[Node] = _room.get_node("Enemies").get_children()
	_check(enemies.size() == 1 and _burrower.scene_file_path == BURROWER_PATH and _count_type(_game, "Enemy") == 1,
		"exatamente um Escavador de Cristal (cena existente)")
	_check(_burrower.position == BURROWER_POS, "Escavador no centro da arena %s" % BURROWER_POS)
	_check(_burrower.get_meta(Room.PERSISTENT_ID_META, &"") == BURROWER_ID and _room.get_persistent_enemies().keys() == [BURROWER_ID],
		"identificador persistente %s" % BURROWER_ID)
	var health: HealthComponent = _burrower.get_node("HealthComponent") as HealthComponent
	var data: AttackData = (_burrower.get_node("MeleeAttack") as MeleeAttack).attack
	_check(health.max_health == 5 and health.current_health == 5 and is_equal_approx(_burrower.patrol_distance, 64.0)
		and is_equal_approx(_burrower.dash_speed, 180.0) and is_equal_approx(data.windup_time, 0.6)
		and is_equal_approx(data.active_time, 0.75) and is_equal_approx(data.recovery_time, 1.2)
		and is_equal_approx(_burrower.cooldown_time, 1.0),
		"atributos intactos: 5 HP, patrulha ±64, preparação 0,6 s, investida 180 px/s por até 0,75 s, atordoamento 1,2 s, recarga 1 s")
	for id: StringName in [&"west", &"east"]:
		var d: float = absf(_room.get_entrance(id).position.x - BURROWER_POS.x)
		_check(d - _burrower.patrol_distance - 128.0 > 100.0,
			"entrada %s a %.0f px do Escavador (fora da patrulha + visão, com folga)" % [id, d])
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
	_check(extra.is_empty(), "instâncias só sobrescrevem a posição e o identificador (sem mudar IA, colisões nem combate) %s" % [extra])


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
			and not _is_rock(54, y) and not _is_rock(55, y) and _is_rock(56, y)
	_check(passages, "passagens de 4 tiles nas duas paredes, fechadas pela moldura fora da câmera")
	# Pilares: sólidos (camada world) com colisão real em toda a área.
	var solid: bool = true
	for r: Rect2i in PILLAR_CELLS:
		for cell: Vector2i in [r.position, r.end - Vector2i.ONE, Vector2i(r.position.x, r.end.y - 1), Vector2i(r.end.x - 1, r.position.y)]:
			var tile: TileData = _terrain.get_cell_tile_data(cell)
			solid = solid and tile != null and tile.terrain_set == 0 and tile.get_collision_polygons_count(0) > 0
	_check(solid, "os dois pilares são rocha sólida, com polígono de colisão na camada world")
	_check(_rect_hits(PILLAR_WEST.grow(-1.0), 1) > 0 and _rect_hits(PILLAR_EAST.grow(-1.0), 1) > 0
		and _rect_hits(PILLAR_WEST.grow(-1.0), 2) == 0, "colisão física dos pilares na layer world (não one-way)")
	var flat: bool = true
	for x: int in range(int(ARENA.position.x / TILE), int(ARENA.end.x / TILE)):
		for y: int in range(4, 20):
			flat = flat and not _is_rock(x, y)
		flat = flat and _is_rock(x, 20)
	_check(flat, "arena plana de %d px entre os pilares (x %d–%d), sem teto baixo" % [ARENA.size.x, ARENA.position.x, ARENA.end.x])
	var high: bool = PILLAR_WEST.size.y < 56.0 and PILLAR_WEST.size.y > 20.0
	_check(high, "pilares de %d px: mais altos que o Escavador (corpo de 20) e baixos para o pulo da Terra (56)" % PILLAR_WEST.size.y)


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
	var on_walls: int = 0
	var on_ceiling: int = 0
	for prop: Node in props:
		var p: Vector2 = (prop as Node2D).position
		if not prop.scene_file_path.contains("/crystals/"):
			continue
		if p.x < 80.0 or p.x > BOUNDS.end.x - 80.0:
			on_walls += 1
		if prop.scene_file_path.ends_with("crystal_ceiling.tscn") and _is_rock(floori(p.x / TILE), floori(p.y / TILE) - 1):
			on_ceiling += 1
	_check(on_walls >= 4, "cristais nas saliências das duas paredes (%d)" % on_walls)
	_check(on_ceiling >= 4, "cristais pendentes presos à rocha de cima (%d)" % on_ceiling)
	var clear: bool = true
	for prop: Node in props:
		var p: Vector2 = (prop as Node2D).position
		clear = clear and p.distance_to(WEST) > 96.0 and p.distance_to(EAST) > 96.0
		# Chão da arena livre (área do combate e da investida).
		clear = clear and not (p.y >= FLOOR_Y - 1.0 and p.x > ARENA.position.x and p.x < ARENA.end.x)
	_check(clear, "nenhum prop a menos de 96 px das entradas nem no chão da arena")


# --- Chegada, câmera, patrulha --------------------------------------------------------------

func _test_arrival() -> void:
	print("-- Chegada por west")
	_check(_terra.global_position == WEST and _terra.get_facing() == 1.0, "Terra em west, olhando para a direita")
	_check(_shape_hits(WEST) == 0, "corpo da Terra em west sem sobreposição com o terreno")
	var started: bool = false
	var detected: bool = false
	for i: int in 180:
		await physics_frame
		started = started or _burrower.get_state() in [CrystalBurrower.State.CHARGE, CrystalBurrower.State.DASH]
		detected = detected or _burrower.is_target_detected()
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(WEST) < 0.5, "apoiada no chão em west")
	_check(_burrower.is_on_floor() and absf(_burrower.global_position.y - FLOOR_Y) < 0.5, "Escavador apoiado no chão")
	_check(not started and not detected and _terra.get_health().current_health == _terra.get_health().max_health,
		"o encontro não começa na chegada (3 s parada na entrada, sem detecção nem ataque)")


func _test_camera() -> void:
	print("-- Câmera e fundo")
	_set_exits(false)
	_terra.set_physics_process(false)
	var ok: bool = true
	var cover: bool = true
	var detail: String = ""
	for x: float in [0.0, 56.0, 304.0, 448.0, 600.3, 840.0, 896.0]:
		for y: float in [320.0, 120.0]:
			_terra.global_position = Vector2(x, y)
			await process_frame
			await process_frame
			var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
			if view.position.x < -0.001 or view.position.y < -0.001 or view.end.x > BOUNDS.end.x + 0.001 \
					or view.end.y > BOUNDS.end.y + 0.001:
				ok = false
				detail += " (%s: %s)" % [Vector2(x, y), view]
			cover = cover and _background_covers()
	_check(ok, "câmera nunca mostra fora da sala (14 posições)%s" % detail)
	_check(cover, "o fundo com parallax cobre a tela inteira em todas as posições")
	_terra.set_physics_process(true)
	await _reset(WEST, 1.0)
	_set_exits(true)
	_check(_game.call("get_room") == _room and not _game.call("is_transitioning"), "a sala continua a mesma depois do teste da câmera")


func _test_patrol() -> void:
	print("-- Patrulha")
	var min_x: float = INF
	var max_x: float = -INF
	var on_floor: bool = true
	var walled: bool = false
	var attacked: bool = false
	for i: int in 720:
		await physics_frame
		min_x = minf(min_x, _burrower.global_position.x)
		max_x = maxf(max_x, _burrower.global_position.x)
		on_floor = on_floor and absf(_burrower.global_position.y - FLOOR_Y) < 0.5
		walled = walled or _burrower.is_on_wall()
		attacked = attacked or _burrower.get_state() == CrystalBurrower.State.CHARGE
	var origin: float = _burrower.get_patrol_origin_x()
	_check(origin == BURROWER_POS.x and on_floor and absf(min_x - (origin - 64.0)) < 0.5 and absf(max_x - (origin + 64.0)) < 0.5,
		"patrulha completa no território (%.0f–%.0f), no chão" % [min_x, max_x])
	_check(not walled and min_x - BURROWER_HALF_WIDTH > PILLAR_WEST.end.x and max_x + BURROWER_HALF_WIDTH < PILLAR_EAST.position.x,
		"o território cabe entre os pilares, sem encostar neles na patrulha")
	_check(not attacked, "com a Terra na entrada, só patrulha")


# --- Combate ----------------------------------------------------------------------------------

## Esquiva real: a Terra espera no chão da arena, sobe no pilar oeste durante a preparação,
## a investida para na face do pilar e a Terra desce para golpear as costas no atordoamento.
func _test_dodge_and_counter() -> void:
	print("-- Esquiva no pilar oeste e contra-ataque")
	# Encostada na face do pilar: a investida (até 135 px, vista a até 136) termina no pilar.
	await _reset(Vector2(PILLAR_WEST.end.x + TERRA_HALF_WIDTH + 1.0, FLOOR_Y), -1.0)
	var hp_terra: int = _terra.get_health().current_health
	var charge_tick: int = await _wait_state(CrystalBurrower.State.CHARGE, 1500)
	_check(charge_tick >= 0 and _burrower.get_facing() == -1.0, "vê a Terra à frente e prepara a investida para a esquerda")
	if charge_tick < 0:
		return
	# Esquiva: pula para cima do pilar ao ver a preparação.
	Input.action_press("move_left")
	Input.action_press("jump")
	var charge_ticks: int = 1
	var dash: Dictionary = {"started": false, "ticks": 0, "wall": false, "stop_x": 0.0, "max_speed": 0.0}
	var landed_tick: int = -1
	var dash_end_tick: int = -1
	var hitbox_low: bool = true
	for i: int in 200:
		await physics_frame
		if landed_tick < 0 and _terra.is_on_floor() and absf(_terra.global_position.y - PILLAR_Y) < 0.5:
			_release_all()
			landed_tick = i
		var s: CrystalBurrower.State = _burrower.get_state()
		if s == CrystalBurrower.State.CHARGE:
			charge_ticks += 1
		elif s == CrystalBurrower.State.DASH:
			dash.started = true
			dash.ticks += 1
			dash.max_speed = maxf(dash.max_speed, absf(_burrower.get_real_velocity().x))
			# Hitbox da investida (y -15..-1 dos pés): a Terra precisa estar acima dela ao cruzar.
			if absf(_terra.global_position.x - _burrower.global_position.x) < 30.0:
				hitbox_low = hitbox_low and _terra.global_position.y < FLOOR_Y - 15.0
		elif s == CrystalBurrower.State.STUNNED and dash_end_tick < 0:
			dash_end_tick = i
			dash.ticks += 1
			dash.wall = _burrower.is_on_wall()
			dash.stop_x = _burrower.global_position.x
		if landed_tick >= 0 and dash_end_tick >= 0:
			break
	_release_all()
	_check(absi(charge_ticks - 36) <= 1, "preparação de 0,6 s (%d ticks)" % charge_ticks)
	_check(landed_tick >= 0 and landed_tick <= dash_end_tick and hitbox_low,
		"a Terra sobe no pilar oeste (tick %d) antes de a investida chegar (fim no tick %d)" % [landed_tick, dash_end_tick])
	_check(dash.started and dash.ticks < 45 and dash.wall, "investida interrompida pela face do pilar oeste em %d ticks (máx. 45)" % dash.ticks)
	_check(absf(dash.stop_x - (PILLAR_WEST.end.x + BURROWER_HALF_WIDTH)) < 0.5, "para encostado no pilar (x %.1f)" % dash.stop_x)
	_check(dash.max_speed <= 180.5 and dash.max_speed > 179.0, "velocidade da investida preservada (%.1f px/s)" % dash.max_speed)
	_check(_terra.get_health().current_health == hp_terra, "a Terra sobre o pilar não é atingida")
	# Contra-ataque: desce do pilar andando para a direita, passa por trás e golpeia.
	var stun_ticks: int = 0
	Input.action_press("move_right")
	while _terra.global_position.x < _burrower.global_position.x + COUNTER_DISTANCE - 16.0 and stun_ticks < 60:
		await physics_frame
		stun_ticks += 1
	Input.action_release("move_right")
	while not _terra.is_on_floor() and stun_ticks < 60:
		await physics_frame
		stun_ticks += 1
	_terra.set_facing(-1.0)
	var landed: bool = _terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5
	var result: Dictionary = await _attack_while_stunned()
	stun_ticks += result.ticks
	_check(landed and result.ticks > 0, "desce do pilar e chega atrás do Escavador ainda atordoado (em %d ticks)" % (stun_ticks - result.ticks))
	_check(absi(stun_ticks + 1 - 72) <= 2, "janela de atordoamento de 1,2 s (%d ticks)" % (stun_ticks + 1))
	_check(result.damage >= 1 and result.full, "contra-ataque pelas costas: %d de dano, integral (sem carapaça) no atordoamento" % result.damage)
	_check(_terra.get_health().current_health == hp_terra, "nenhum dano à Terra no ciclo")
	await _place(PILLAR_WEST_TOP, 1.0)


func _test_east_pillar() -> void:
	print("-- Investida contra o pilar leste")
	await _reset(PILLAR_EAST_TOP, -1.0)
	var hp_terra: int = _terra.get_health().current_health
	var charge_tick: int = await _wait_state(CrystalBurrower.State.CHARGE, 1500)
	_check(charge_tick >= 0 and _burrower.get_facing() == 1.0, "vê a Terra no pilar leste e prepara a investida para a direita")
	if charge_tick < 0:
		return
	var dash: Dictionary = await _measure_dash()
	_check(dash.started and dash.wall and absf(dash.stop_x - (PILLAR_EAST.position.x - BURROWER_HALF_WIDTH)) < 0.5,
		"investida interrompida pela face do pilar leste (x %.1f, %d ticks)" % [dash.stop_x, dash.ticks])
	_check(_terra.get_health().current_health == hp_terra, "a Terra sobre o pilar leste não é atingida")


## Golpes reais em cada atordoamento até a derrota, alternando os pilares.
func _test_defeat() -> void:
	print("-- Derrota com golpes reais")
	var health: HealthComponent = _burrower.get_node("HealthComponent") as HealthComponent
	var cycles: int = 0
	var hp_terra: int = _terra.get_health().current_health
	# O Escavador está atordoado no pilar leste (teste anterior): contra-ataca já.
	# Array: o lambda captura variáveis locais por valor.
	var registered_on_death: Array[bool] = [false]
	health.died.connect(func() -> void:
		registered_on_death[0] = _game.call("is_enemy_defeated", ROOM_PATH, BURROWER_ID), CONNECT_ONE_SHOT)
	while not health.is_dead() and cycles < 6:
		if _burrower.get_state() != CrystalBurrower.State.STUNNED:
			var top: Vector2 = PILLAR_WEST_TOP if cycles % 2 == 0 else PILLAR_EAST_TOP
			await _reset(top, 1.0)
			if await _wait_state(CrystalBurrower.State.STUNNED, 1800) < 0:
				break
		var f: float = _burrower.get_facing()
		await _place(Vector2(_burrower.global_position.x - COUNTER_DISTANCE * f, FLOOR_Y), f)
		await _attack_while_stunned()
		cycles += 1
		if not health.is_dead():
			await _place(PILLAR_WEST_TOP, 1.0)
	_check(health.is_dead(), "derrotado com golpes reais em %d atordoamento(s)" % cycles)
	_check(registered_on_death[0], "a morte entra no registro da Game na hora (antes da animação)")
	_check(_terra.get_health().current_health == hp_terra, "a Terra não foi atingida em nenhum ciclo")
	await _wait(80)
	_check(not is_instance_valid(_burrower) or _burrower.is_queued_for_deletion(), "o Escavador some depois da animação death")


# --- Percurso -------------------------------------------------------------------------------

func _test_path_east() -> void:
	print("-- Percurso west → east")
	await _reset(WEST, 1.0)
	Input.action_press("move_right")
	var stop: float = await _walk_until_wall()
	_check(absf(stop - (RISE_WEST.position.x - TERRA_HALF_WIDTH)) < 0.5, "a elevação oeste bloqueia o andar (x %.1f)" % stop)
	var y: float = await _jump_and_land()
	_check(absf(y - RISE_Y) < 0.5, "sobe a elevação oeste (y %.1f)" % y)
	stop = await _walk_until_wall()
	_check(absf(stop - (PILLAR_WEST.position.x - TERRA_HALF_WIDTH)) < 0.5, "o pilar oeste bloqueia o andar (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(_over_or_on(y, PILLAR_WEST, 1.0), "pula o pilar oeste vindo da elevação (pousa em %s)" % _terra.global_position)
	stop = await _walk_until_wall()
	_check(absf(stop - (PILLAR_EAST.position.x - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"desce para a arena e atravessa até o pilar leste (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(absf(y - PILLAR_Y) < 0.5, "sobe o pilar leste (y %.1f)" % y)
	stop = await _walk_until_wall()
	Input.action_release("move_right")
	_check(absf(stop - (BOUNDS.end.x - TERRA_HALF_WIDTH)) < 0.5 and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"desce a elevação leste e chega ao fim da passagem leste (x %.1f)" % stop)
	_check(_game.call("get_room") == _room, "com a saída desligada, sem transição na passagem leste (a ida à Sala 05 tem teste próprio)")


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
	_check(absf(stop - (PILLAR_EAST.end.x + TERRA_HALF_WIDTH)) < 0.5, "o pilar leste bloqueia (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(_over_or_on(y, PILLAR_EAST, -1.0), "pula o pilar leste vindo da elevação (pousa em %s)" % _terra.global_position)
	stop = await _walk_until_wall()
	_check(absf(stop - (PILLAR_WEST.end.x + TERRA_HALF_WIDTH)) < 0.5, "atravessa a arena até o pilar oeste (x %.1f)" % stop)
	y = await _jump_and_land()
	_check(absf(y - PILLAR_Y) < 0.5, "sobe o pilar oeste pela direita")
	stop = await _walk_until_wall()
	Input.action_release("move_left")
	_check(absf(stop - TERRA_HALF_WIDTH) < 0.5 and _body_rect(_terra.global_position).intersects(WEST_EXIT),
		"caminho de retorno livre até a passagem oeste, dentro da área da saída (x %.1f)" % stop)


# --- Transições e persistência --------------------------------------------------------------

func _test_transitions() -> void:
	print("-- Transições com a Sala 03")
	await _new_game(ROOM_03, &"east")
	var room_03: Room = _game.call("get_room") as Room
	var east: RoomExit = null
	for e: RoomExit in room_03.get_exits():
		if e.name == &"East":
			east = e
	_check(east != null and east.target_room == ROOM_PATH and east.target_entry == &"west"
		and _exit_rect(east) == ROOM_03_EAST_EXIT, "Sala 03: saída East (na passagem de cima, y 160–224) → Sala 04 (west)")
	await _wait(10)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(ROOM_03_EAST) < 0.5,
		"na Sala 03, a Terra fica de pé na saliência do topo (y %.0f)" % _terra.global_position.y)
	_terra.get_health().take_damage(2)
	await _wait(40)
	var health: int = _terra.get_health().current_health
	var terra_id: int = _terra.get_instance_id()
	# Ida 03 → 04, golpeando no caminho (o golpe é cancelado na troca).
	Input.action_press("move_right")
	var striking_at_change: Array[bool] = [false]
	var on_change: Callable = func(_r: Room) -> void:
		striking_at_change[0] = (_terra.get_node("MeleeAttack") as MeleeAttack).is_busy()
	_game.connect("room_changed", on_change)
	for i: int in 30:
		await physics_frame
		if _game.call("is_transitioning"):
			break
		if i % 8 == 0:
			Input.action_press("attack")
		else:
			Input.action_release("attack")
	var arrival: Dictionary = await _wait_change()
	_game.disconnect("room_changed", on_change)
	_release_all()
	_check(_game.call("get_room_path") == ROOM_PATH and arrival.pos == WEST and arrival.facing == 1.0,
		"Sala 03 → 04: chega em west %s, olhando para a direita" % [arrival.pos])
	_check(not striking_at_change[0], "ações canceladas na troca (golpe interrompido)")
	_check(_camera_limits() == BOUNDS, "limites da câmera trocados para 896x368")
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada (%d)" % health)
	_check((_game.call("get_room") as Room).get_node_or_null("Enemies/CrystalBurrower") != null, "o Escavador está na sala")
	await _wait(30)
	_check(_game.call("get_room_path") == ROOM_PATH and _terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5,
		"sem transição de volta em loop; de pé no chão da Sala 04 (altura diferente da saída da Sala 03)")
	var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
	_check(Rect2(BOUNDS).encloses(view), "câmera dentro da sala na chegada %s" % view)
	# Volta 04 → 03 andando para a esquerda.
	Input.action_press("move_left")
	arrival = await _wait_change()
	Input.action_release("move_left")
	_check(_game.call("get_room_path") == ROOM_03 and arrival.pos == ROOM_03_EAST and arrival.facing == -1.0,
		"Sala 04 → 03: chega em east %s (em cima), olhando para a esquerda" % [arrival.pos])
	_check(_camera_limits() == ROOM_03_BOUNDS, "limites da câmera de volta aos da Sala 03 (640x720)")
	_check(_terra.get_instance_id() == terra_id and _terra.get_health().current_health == health, "mesma Terra, vida preservada")
	await _wait(20)
	_check(_terra.is_on_floor() and _terra.global_position.distance_to(ROOM_03_EAST) < 0.5 and _game.call("get_room_path") == ROOM_03,
		"de pé na saliência do topo da Sala 03, sem cair nem voltar em loop")
	view = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
	_check(Rect2(ROOM_03_BOUNDS).encloses(view) and view.has_point(_terra.global_position + Vector2(0, -23)),
		"câmera no alto da Sala 03, com a Terra na tela %s" % view)


func _test_persistence() -> void:
	print("-- Persistência do Escavador")
	# Derrotado: some na hora do registro e não volta ao revisitar.
	await _new_game(ROOM_PATH, &"west")
	var burrower: Enemy = (_game.call("get_room") as Room).get_node("Enemies/CrystalBurrower") as Enemy
	(burrower.get_node("HealthComponent") as HealthComponent).take_damage(99)
	_check(_game.call("is_enemy_defeated", ROOM_PATH, BURROWER_ID), "morte registrada imediatamente")
	await _wait(10)
	Input.action_press("move_left")
	await _wait_change()
	Input.action_release("move_left")
	_check(_game.call("get_room_path") == ROOM_03, "sai para a Sala 03")
	Input.action_press("move_right")
	await _wait_change()
	Input.action_release("move_right")
	var room: Room = _game.call("get_room") as Room
	_check(_game.call("get_room_path") == ROOM_PATH and room.get_node_or_null("Enemies/CrystalBurrower") == null
		and _count_type(room, "Enemy") == 0 and _game.call("get_defeated_enemies", ROOM_PATH) == [BURROWER_ID],
		"ao voltar, o Escavador continua derrotado")
	# Reiniciar o jogo (Game nova) restaura.
	await _new_game(ROOM_PATH, &"west")
	room = _game.call("get_room") as Room
	burrower = room.get_node_or_null("Enemies/CrystalBurrower") as Enemy
	_check(burrower != null and (burrower.get_node("HealthComponent") as HealthComponent).current_health == 5
		and _game.call("get_defeated_enemies", ROOM_PATH).is_empty(), "reiniciar o jogo restaura o Escavador com 5 de vida")
	# Vivo e ferido: volta inteiro, no ponto de origem.
	(burrower.get_node("HealthComponent") as HealthComponent).take_damage(2)
	await _wait(5)
	Input.action_press("move_left")
	await _wait_change()
	Input.action_release("move_left")
	Input.action_press("move_right")
	await _wait_change()
	Input.action_release("move_right")
	room = _game.call("get_room") as Room
	burrower = room.get_node_or_null("Enemies/CrystalBurrower") as Enemy
	_check(burrower != null and (burrower.get_node("HealthComponent") as HealthComponent).current_health == 5
		and burrower.global_position == BURROWER_POS and not _game.call("is_enemy_defeated", ROOM_PATH, BURROWER_ID),
		"sair com ele vivo (ferido) o restaura inteiro, no ponto de origem")


# --- Combate: auxiliares --------------------------------------------------------------------

## Espera o Escavador entrar no estado. Retorna o tick em que entrou, ou -1.
func _wait_state(state: CrystalBurrower.State, max_ticks: int) -> int:
	for i: int in max_ticks:
		if not is_instance_valid(_burrower) or _burrower.is_dead():
			return -1
		if _burrower.get_state() == state:
			return i
		await physics_frame
	return -1


## A partir de CHARGE: mede a investida até STUNNED.
func _measure_dash() -> Dictionary:
	var info: Dictionary = {"started": false, "ticks": 0, "wall": false, "stop_x": 0.0, "max_speed": 0.0}
	for i: int in 160:
		await physics_frame
		var s: CrystalBurrower.State = _burrower.get_state()
		if s == CrystalBurrower.State.DASH:
			info.started = true
			info.ticks += 1
			info.max_speed = maxf(info.max_speed, absf(_burrower.get_real_velocity().x))
		elif s == CrystalBurrower.State.STUNNED:
			info.wall = _burrower.is_on_wall()
			info.stop_x = _burrower.global_position.x
			# Tick em que bateu também conta como investida (a parede encerra depois do movimento).
			info.ticks += 1
			break
	return info


## Golpeia com o soco real enquanto o Escavador está atordoado. Retorna os ticks gastos,
## o dano causado e se todo golpe aceito causou dano integral (1).
func _attack_while_stunned() -> Dictionary:
	var health: HealthComponent = _burrower.get_node("HealthComponent") as HealthComponent
	var melee: MeleeAttack = _terra.get_node("MeleeAttack") as MeleeAttack
	var carapace: CarapaceHurtbox = _burrower.get_node("Hurtbox") as CarapaceHurtbox
	var start_hp: int = health.current_health
	var hits: Array[int] = []
	var on_hit: Callable = func(damage: int) -> void: hits.append(damage)
	carapace.hit_received.connect(on_hit)
	var ticks: int = 0
	# Aperta num tick e solta no seguinte (apertar e soltar no mesmo tick não conta como aperto).
	var pressed: bool = false
	while not health.is_dead() and _burrower.get_state() == CrystalBurrower.State.STUNNED and ticks < 120:
		if pressed:
			Input.action_release("attack")
			pressed = false
		elif not melee.is_busy():
			Input.action_press("attack")
			pressed = true
		await physics_frame
		ticks += 1
	Input.action_release("attack")
	carapace.hit_received.disconnect(on_hit)
	var full: bool = not hits.is_empty()
	for d: int in hits:
		full = full and d == 1
	return {"ticks": ticks, "damage": start_hp - health.current_health, "full": full}


# --- Auxiliares -----------------------------------------------------------------------------

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


## Depois de pular um pilar andando no sentido dir: pousou em cima dele ou já do outro lado
## (pilar de 2 tiles: vindo da elevação, o pulo com a direção segurada passa por cima).
func _over_or_on(y: float, pillar: Rect2, dir: float) -> bool:
	if absf(y - PILLAR_Y) < 0.5:
		return true
	var past: bool = _terra.global_position.x > pillar.end.x if dir > 0.0 else _terra.global_position.x < pillar.position.x
	return absf(y - FLOOR_Y) < 0.5 and past


## Põe a Terra parada num ponto sem esperar (para não gastar a janela de atordoamento).
func _place(position: Vector2, facing: float) -> void:
	_release_all()
	_terra.set_facing(facing)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await physics_frame


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
