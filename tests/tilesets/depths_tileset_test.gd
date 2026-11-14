extends SceneTree
## Teste automatizado do TileSet do Reino das Profundezas (depths_tileset.tres):
## atlas, camadas de física, colisão de cada tile, terrain sets e pintura real pelo pincel
## de terreno (set_cells_terrain_connect).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/tilesets/depths_tileset_test.gd

const TILESET_PATH: String = "res://world/tilesets/depths/depths_tileset.tres"
const ATLAS_PATH: String = "res://world/tilesets/depths/depths_terrain.png"
const TILE: int = 16
const SOURCE_ID: int = 0

const PHYSICS_WORLD: int = 0
const PHYSICS_PLATFORMS: int = 1
const LAYER_WORLD: int = 1
const LAYER_PLATFORMS: int = 2
const SET_ROCK: int = 0
const SET_PLATFORM: int = 1
const VARIANT_PROBABILITY: float = 0.15

const SOLID_POLYGON: PackedVector2Array = [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]
## Faixa one-way de 8 px no topo do tile.
const PLATFORM_POLYGON: PackedVector2Array = [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 0), Vector2(-8, 0)]

const R: int = TileSet.CELL_NEIGHBOR_RIGHT_SIDE
const BR: int = TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER
const B: int = TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
const BL: int = TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
const L: int = TileSet.CELL_NEIGHBOR_LEFT_SIDE
const TL: int = TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
const T: int = TileSet.CELL_NEIGHBOR_TOP_SIDE
const TR: int = TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
const ALL: Array[int] = [R, BR, B, BL, L, TL, T, TR]
const SIDES: Array[int] = [R, B, L, T]

## Tiles de rocha: célula -> [bits de vizinhança, peça base (variações) ou null].
const ROCK: Dictionary = {
	Vector2i(1, 1): [[R, BR, B, BL, L, TL, T, TR], null],
	Vector2i(5, 1): [[R, BR, B, BL, L, TL, T, TR], Vector2i(1, 1)],
	Vector2i(6, 1): [[R, BR, B, BL, L, TL, T, TR], Vector2i(1, 1)],
	Vector2i(7, 1): [[R, BR, B, BL, L, TL, T, TR], Vector2i(1, 1)],
	Vector2i(1, 0): [[L, R, B, BL, BR], null],
	Vector2i(5, 0): [[L, R, B, BL, BR], Vector2i(1, 0)],
	Vector2i(6, 0): [[L, R, B, BL, BR], Vector2i(1, 0)],
	Vector2i(0, 0): [[R, B, BR], null],
	Vector2i(2, 0): [[L, B, BL], null],
	Vector2i(0, 1): [[T, R, B, TR, BR], null],
	Vector2i(2, 1): [[T, L, B, TL, BL], null],
	Vector2i(1, 2): [[L, R, T, TL, TR], null],
	Vector2i(6, 2): [[L, R, T, TL, TR], Vector2i(1, 2)],
	Vector2i(0, 2): [[T, R, TR], null],
	Vector2i(2, 2): [[T, L, TL], null],
	Vector2i(3, 0): [[R, BR, B, BL, L, T, TR], null],
	Vector2i(4, 0): [[R, BR, B, BL, L, TL, T], null],
	Vector2i(3, 1): [[R, BR, B, L, TL, T, TR], null],
	Vector2i(4, 1): [[B, BL, L, TL, T, TR, R], null],
	Vector2i(7, 0): [[], null],
	Vector2i(3, 2): [[R], null],
	Vector2i(4, 2): [[L, R], null],
	Vector2i(5, 2): [[L], null],
	Vector2i(0, 3): [[B], null],
	Vector2i(1, 3): [[T, B], null],
	Vector2i(2, 3): [[T], null],
}
const PLATFORMS: Dictionary = {
	Vector2i(3, 3): [[R], null],
	Vector2i(4, 3): [[L, R], null],
	Vector2i(6, 3): [[L, R], Vector2i(4, 3)],
	Vector2i(5, 3): [[L], null],
	Vector2i(7, 3): [[], null],
}

var _failures: int = 0
var _checks: int = 0
var _tile_set: TileSet
var _source: TileSetAtlasSource


func _initialize() -> void:
	print("== TileSet: Reino das Profundezas")
	_tile_set = load(TILESET_PATH) as TileSet
	_check(_tile_set != null, "TileSet carregado")
	if _tile_set == null:
		quit(1)
		return
	_test_atlas()
	_test_physics_layers()
	_test_collisions()
	_test_terrains()
	await _test_painting()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Atlas ------------------------------------------------------------------------------

func _test_atlas() -> void:
	print("-- Atlas")
	_check(_tile_set.tile_shape == TileSet.TILE_SHAPE_SQUARE and _tile_set.tile_size == Vector2i(TILE, TILE), "tiles quadrados de 16x16")
	_check(_tile_set.get_source_count() == 1 and _tile_set.has_source(SOURCE_ID), "uma única fonte (id 0)")
	_source = _tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	_check(_source != null and _source.texture != null and _source.texture.resource_path == ATLAS_PATH,
		"fonte de atlas usa depths_terrain.png")
	_check(_source.texture_region_size == Vector2i(TILE, TILE) and _source.margins == Vector2i.ZERO
		and _source.separation == Vector2i.ZERO, "região 16x16, sem margem nem espaçamento")
	_check(_source.get_atlas_grid_size() == Vector2i(8, 4), "grade do atlas 8x4")
	_check(_source.get_tiles_count() == ROCK.size() + PLATFORMS.size(), "%d tiles criados (esperado %d)" % [_source.get_tiles_count(), ROCK.size() + PLATFORMS.size()])
	_check(not _source.has_tile(Vector2i(7, 2)), "célula (7,2) vazia não vira tile")
	var missing: Array[Vector2i] = []
	for cell: Vector2i in ROCK.keys() + PLATFORMS.keys():
		if not _source.has_tile(cell) or _source.get_alternative_tiles_count(cell) != 1:
			missing.append(cell)
	_check(missing.is_empty(), "todas as células do mapa existem, sem alternativas extras %s" % [missing])


# --- Camadas de física -------------------------------------------------------------------

func _test_physics_layers() -> void:
	print("-- Camadas de física")
	_check(_tile_set.get_physics_layers_count() == 2, "2 camadas de física")
	_check(_tile_set.get_physics_layer_collision_layer(PHYSICS_WORLD) == LAYER_WORLD
		and _tile_set.get_physics_layer_collision_mask(PHYSICS_WORLD) == 0, "camada 0 = layer world (1), sem máscara")
	_check(_tile_set.get_physics_layer_collision_layer(PHYSICS_PLATFORMS) == LAYER_PLATFORMS
		and _tile_set.get_physics_layer_collision_mask(PHYSICS_PLATFORMS) == 0, "camada 1 = layer platforms (2), sem máscara")


# --- Colisão de cada tile ----------------------------------------------------------------

func _test_collisions() -> void:
	print("-- Colisões")
	var wrong_solid: Array[Vector2i] = []
	for cell: Vector2i in ROCK:
		var data: TileData = _source.get_tile_data(cell, 0)
		var ok: bool = data.get_collision_polygons_count(PHYSICS_WORLD) == 1 \
			and data.get_collision_polygons_count(PHYSICS_PLATFORMS) == 0 \
			and data.get_collision_polygon_points(PHYSICS_WORLD, 0) == SOLID_POLYGON \
			and not data.is_collision_polygon_one_way(PHYSICS_WORLD, 0)
		if not ok:
			wrong_solid.append(cell)
	_check(wrong_solid.is_empty(), "26 sólidos: um polígono 16x16 na camada world, nada em platforms %s" % [wrong_solid])
	var wrong_platform: Array[Vector2i] = []
	for cell: Vector2i in PLATFORMS:
		var data: TileData = _source.get_tile_data(cell, 0)
		var ok: bool = data.get_collision_polygons_count(PHYSICS_PLATFORMS) == 1 \
			and data.get_collision_polygons_count(PHYSICS_WORLD) == 0 \
			and data.get_collision_polygon_points(PHYSICS_PLATFORMS, 0) == PLATFORM_POLYGON \
			and data.is_collision_polygon_one_way(PHYSICS_PLATFORMS, 0)
		if not ok:
			wrong_platform.append(cell)
	_check(wrong_platform.is_empty(), "5 plataformas: faixa 16x8 one-way no topo, na camada platforms %s" % [wrong_platform])


# --- Terrenos ----------------------------------------------------------------------------

func _test_terrains() -> void:
	print("-- Terrain sets")
	_check(_tile_set.get_terrain_sets_count() == 2, "2 terrain sets")
	_check(_tile_set.get_terrain_set_mode(SET_ROCK) == TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES
		and _tile_set.get_terrains_count(SET_ROCK) == 1 and _tile_set.get_terrain_name(SET_ROCK, 0) == "Rocha",
		"set 0: Rocha, cantos e lados")
	_check(_tile_set.get_terrain_set_mode(SET_PLATFORM) == TileSet.TERRAIN_MODE_MATCH_SIDES
		and _tile_set.get_terrains_count(SET_PLATFORM) == 1 and _tile_set.get_terrain_name(SET_PLATFORM, 0) == "Plataforma",
		"set 1: Plataforma, só lados")
	for spec: Array in [[ROCK, SET_ROCK, ALL], [PLATFORMS, SET_PLATFORM, SIDES]]:
		var table: Dictionary = spec[0]
		var wrong: Array[String] = []
		for cell: Vector2i in table:
			var data: TileData = _source.get_tile_data(cell, 0)
			var expected: Array = table[cell][0]
			var ok: bool = data.terrain_set == spec[1] and data.terrain == 0
			for n: int in spec[2]:
				ok = ok and data.get_terrain_peering_bit(n) == (0 if expected.has(n) else -1)
			var base: Variant = table[cell][1]
			ok = ok and is_equal_approx(data.probability, VARIANT_PROBABILITY if base != null else 1.0)
			if not ok:
				wrong.append(str(cell))
		_check(wrong.is_empty(), "set %d: bits de vizinhança e probabilidades de %d tiles conforme o mapa %s" % [spec[1], table.size(), wrong])
	var same_bits: bool = true
	for table: Dictionary in [ROCK, PLATFORMS]:
		for cell: Vector2i in table:
			var base: Variant = table[cell][1]
			if base != null:
				same_bits = same_bits and table[cell][0] == table[base][0]
	_check(same_bits, "variações com os mesmos bits da peça base")


# --- Pintura real ------------------------------------------------------------------------

## Pinta formas num TileMapLayer temporário com o pincel de terreno e confere a peça de cada célula.
func _test_painting() -> void:
	print("-- Pintura com o pincel de terreno")
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = _tile_set
	root.add_child(layer)
	# Mapa de teste: blocos com degraus e cantos internos, saliência no teto, faixas e plataformas.
	# Formas separadas por pelo menos um tile vazio (inclusive na diagonal).
	var map: Array[String] = [
		"..........................",
		".########.......####......",
		".########.......####......",
		".###..###........##.......",
		"..........................",
		"..####...........####.....",
		"..######..................",
		".#########...=====....#...",
		".#########............#...",
		"..............=.......#...",
	]
	var rock: Array[Vector2i] = []
	var platforms: Array[Vector2i] = []
	for y: int in map.size():
		for x: int in map[y].length():
			if map[y][x] == "#":
				rock.append(Vector2i(x, y))
			elif map[y][x] == "=":
				platforms.append(Vector2i(x, y))
	layer.set_cells_terrain_connect(rock, SET_ROCK, 0)
	layer.set_cells_terrain_connect(platforms, SET_PLATFORM, 0)
	await process_frame
	var wrong: Array[String] = []
	var checked: int = 0
	for y: int in map.size():
		for x: int in map[y].length():
			var cell: Vector2i = Vector2i(x, y)
			var expected: Vector2i = _expected_cell(map, x, y)
			var actual: Vector2i = layer.get_cell_atlas_coords(cell)
			if expected == Vector2i(-1, -1):
				if layer.get_cell_source_id(cell) != -1:
					wrong.append("%s vazio, veio %s" % [cell, actual])
				continue
			checked += 1
			if _base_of(actual) != expected:
				wrong.append("%s esperado %s, veio %s" % [cell, expected, actual])
	_check(wrong.is_empty(), "%d células pintadas com a peça certa para os vizinhos %s" % [checked, wrong])
	layer.queue_free()


# --- Auxiliares --------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _base_of(cell: Vector2i) -> Vector2i:
	for table: Dictionary in [ROCK, PLATFORMS]:
		if table.has(cell) and table[cell][1] != null:
			return table[cell][1]
	return cell


func _at(map: Array[String], x: int, y: int) -> String:
	if y < 0 or y >= map.size() or x < 0 or x >= map[y].length():
		return "."
	return map[y][x]


## Peça esperada (base) para uma célula do mapa, conforme os vizinhos. (-1,-1) = vazio.
static func expected_for(solid: Callable, platform: Callable, x: int, y: int) -> Vector2i:
	if platform.call(x, y):
		var l: bool = platform.call(x - 1, y)
		var r: bool = platform.call(x + 1, y)
		if l and r:
			return Vector2i(4, 3)
		if r:
			return Vector2i(3, 3)
		if l:
			return Vector2i(5, 3)
		return Vector2i(7, 3)
	if not solid.call(x, y):
		return Vector2i(-1, -1)
	var t: bool = not solid.call(x, y - 1)
	var b: bool = not solid.call(x, y + 1)
	var le: bool = not solid.call(x - 1, y)
	var ri: bool = not solid.call(x + 1, y)
	if t and b and le and ri:
		return Vector2i(7, 0)
	if t and b:
		return Vector2i(3, 2) if le else (Vector2i(5, 2) if ri else Vector2i(4, 2))
	if le and ri:
		return Vector2i(0, 3) if t else (Vector2i(2, 3) if b else Vector2i(1, 3))
	if t:
		return Vector2i(0, 0) if le else (Vector2i(2, 0) if ri else Vector2i(1, 0))
	if b:
		return Vector2i(0, 2) if le else (Vector2i(2, 2) if ri else Vector2i(1, 2))
	if le:
		return Vector2i(0, 1)
	if ri:
		return Vector2i(2, 1)
	if not solid.call(x - 1, y - 1):
		return Vector2i(3, 0)
	if not solid.call(x + 1, y - 1):
		return Vector2i(4, 0)
	if not solid.call(x - 1, y + 1):
		return Vector2i(3, 1)
	if not solid.call(x + 1, y + 1):
		return Vector2i(4, 1)
	return Vector2i(1, 1)


func _expected_cell(map: Array[String], x: int, y: int) -> Vector2i:
	return expected_for(func(cx: int, cy: int) -> bool: return _at(map, cx, cy) == "#",
		func(cx: int, cy: int) -> bool: return _at(map, cx, cy) == "=", x, y)
