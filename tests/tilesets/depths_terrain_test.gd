extends SceneTree
## Teste automatizado do atlas de terreno do Reino das Profundezas (depths_terrain.png).
## Verifica só propriedades técnicas (dimensões, paleta, transparência, grade, bordas e
## encaixe entre tiles vizinhos); a aprovação visual é manual.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/tilesets/depths_terrain_test.gd

const ATLAS_PATH: String = "res://world/tilesets/depths/depths_terrain.png"
const PALETTE_PATH: String = "res://world/tilesets/depths/depths_palette.png"

const TILE: int = 16
const COLUMNS: int = 8
const ROWS: int = 4
const MAX_PALETTE: int = 20
## Índice da paleta reservado aos props (cristais, lanterna); não pode aparecer no terreno.
const RESERVED_INDEX: int = 16
## Transparência só é permitida até esta distância de um lado exposto.
const EXPOSED_MARGIN: int = 3
## Arredondamento máximo nas pontas da linha de apoio (topo e plataformas).
const ROUNDING: int = 2
## Linhas da plataforma que recebem colisão (faixa one-way de 8 px).
const PLATFORM_BODY_ROWS: int = 8
## Emenda = diferença média que atravessa a borda / diferença média entre pixels vizinhos
## dentro dos dois tiles. Limites calibrados na rocha sem cortes da folha de origem
## (187 pares de tiles vizinhos reais: mediana 0,96, 95% até 1,95).
const SEAM_MAX: float = 1.95
const SEAM_MEAN_MAX: float = 1.2
## Musgo do canto interno: a profundidade na coluna de encontro pode variar até isso
## em relação à coluna vizinha do topo.
const MOSS_DEPTH_TOLERANCE: int = 2
const GREEN_INDICES: Array[int] = [9, 10, 11, 12, 13, 14]
## Imagem ampliada teria quase todos os blocos 2x2 de uma cor só.
const MAX_UNIFORM_2X2: float = 0.5

enum Kind { SOLID, PLATFORM, EMPTY }

## Papel de cada célula: tipo, lados que encostam em outro tile (C = cima, B = baixo,
## E = esquerda, D = direita) e a peça base, para as variações.
const CELLS: Dictionary = {
	Vector2i(0, 0): [Kind.SOLID, "DB", null],
	Vector2i(1, 0): [Kind.SOLID, "EDB", null],
	Vector2i(2, 0): [Kind.SOLID, "EB", null],
	Vector2i(3, 0): [Kind.SOLID, "CBED", null],
	Vector2i(4, 0): [Kind.SOLID, "CBED", null],
	Vector2i(5, 0): [Kind.SOLID, "EDB", Vector2i(1, 0)],
	Vector2i(6, 0): [Kind.SOLID, "EDB", Vector2i(1, 0)],
	Vector2i(7, 0): [Kind.SOLID, "", null],
	Vector2i(0, 1): [Kind.SOLID, "CDB", null],
	Vector2i(1, 1): [Kind.SOLID, "CBED", null],
	Vector2i(2, 1): [Kind.SOLID, "CEB", null],
	Vector2i(3, 1): [Kind.SOLID, "CBED", null],
	Vector2i(4, 1): [Kind.SOLID, "CBED", null],
	Vector2i(5, 1): [Kind.SOLID, "CBED", Vector2i(1, 1)],
	Vector2i(6, 1): [Kind.SOLID, "CBED", Vector2i(1, 1)],
	Vector2i(7, 1): [Kind.SOLID, "CBED", Vector2i(1, 1)],
	Vector2i(0, 2): [Kind.SOLID, "CD", null],
	Vector2i(1, 2): [Kind.SOLID, "CED", null],
	Vector2i(2, 2): [Kind.SOLID, "CE", null],
	Vector2i(3, 2): [Kind.SOLID, "D", null],
	Vector2i(4, 2): [Kind.SOLID, "ED", null],
	Vector2i(5, 2): [Kind.SOLID, "E", null],
	Vector2i(6, 2): [Kind.SOLID, "CED", Vector2i(1, 2)],
	Vector2i(7, 2): [Kind.EMPTY, "", null],
	Vector2i(0, 3): [Kind.SOLID, "B", null],
	Vector2i(1, 3): [Kind.SOLID, "CB", null],
	Vector2i(2, 3): [Kind.SOLID, "C", null],
	Vector2i(3, 3): [Kind.PLATFORM, "D", null],
	Vector2i(4, 3): [Kind.PLATFORM, "ED", null],
	Vector2i(5, 3): [Kind.PLATFORM, "E", null],
	Vector2i(6, 3): [Kind.PLATFORM, "ED", Vector2i(4, 3)],
	Vector2i(7, 3): [Kind.PLATFORM, "", null],
}

## Contorno: lados expostos de tiles sólidos só podem ter contorno ou transparência.
const OUTLINE_INDEX: int = 0

var _failures: int = 0
var _checks: int = 0
var _atlas: Image
var _palette: Array[Color] = []
var _palette_lookup: Dictionary = {}


func _initialize() -> void:
	print("== Atlas de terreno: Reino das Profundezas")
	_atlas = Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	var palette_image: Image = Image.load_from_file(ProjectSettings.globalize_path(PALETTE_PATH))
	_check(_atlas != null and not _atlas.is_empty(), "atlas carregado")
	_check(palette_image != null and not palette_image.is_empty(), "paleta carregada")
	if _atlas == null or palette_image == null:
		quit(1)
		return
	_atlas.convert(Image.FORMAT_RGBA8)
	palette_image.convert(Image.FORMAT_RGBA8)
	for x: int in palette_image.get_width():
		var color: Color = palette_image.get_pixel(x, 0)
		_palette.append(color)
		_palette_lookup[color.to_rgba32()] = x

	_test_dimensions(palette_image)
	_test_real_pixels()
	_test_palette()
	_test_alpha()
	_test_grid()
	_test_borders_and_transparency()
	_test_walk_surfaces()
	_test_exposed_outline()
	_test_seams()
	_test_inner_corner_walls()
	_test_variations()

	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- 1. Dimensões -----------------------------------------------------------------

func _test_dimensions(palette_image: Image) -> void:
	print("-- Dimensões")
	_check(_atlas.get_width() == COLUMNS * TILE and _atlas.get_height() == ROWS * TILE,
		"atlas %dx%d (esperado %dx%d)" % [_atlas.get_width(), _atlas.get_height(), COLUMNS * TILE, ROWS * TILE])
	_check(_atlas.get_width() % TILE == 0 and _atlas.get_height() % TILE == 0, "dimensões múltiplas de %d" % TILE)
	_check(palette_image.get_height() == 1 and _palette.size() <= MAX_PALETTE and _palette.size() > RESERVED_INDEX,
		"paleta em 1 linha com %d cores (máx. %d)" % [_palette.size(), MAX_PALETTE])
	_check(_palette_lookup.size() == _palette.size(), "paleta sem cores repetidas")


# --- 2. Pixel real (sem ampliação) ---------------------------------------------------

func _test_real_pixels() -> void:
	print("-- Pixel real")
	var blocks: int = 0
	var uniform: int = 0
	for y: int in range(0, _atlas.get_height(), 2):
		for x: int in range(0, _atlas.get_width(), 2):
			var c: Color = _atlas.get_pixel(x, y)
			if c.a8 == 0:
				continue
			blocks += 1
			if c == _atlas.get_pixel(x + 1, y) and c == _atlas.get_pixel(x, y + 1) and c == _atlas.get_pixel(x + 1, y + 1):
				uniform += 1
	var ratio: float = float(uniform) / maxf(blocks, 1)
	_check(ratio < MAX_UNIFORM_2X2, "blocos 2x2 de uma cor só: %.0f%% (limite %.0f%%; acima disso a imagem estaria ampliada)" % [ratio * 100.0, MAX_UNIFORM_2X2 * 100.0])


# --- 3. Paleta (sem borrão nem antialiasing) ----------------------------------------

func _test_palette() -> void:
	print("-- Paleta")
	var outside: int = 0
	var reserved: int = 0
	for y: int in _atlas.get_height():
		for x: int in _atlas.get_width():
			var c: Color = _atlas.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var key: int = Color(c.r, c.g, c.b, 1.0).to_rgba32()
			if not _palette_lookup.has(key):
				outside += 1
			elif _palette_lookup[key] == RESERVED_INDEX:
				reserved += 1
	_check(outside == 0, "todo pixel opaco é uma cor exata da paleta (%d fora)" % outside)
	_check(reserved == 0, "cor reservada aos props ausente do terreno (%d px)" % reserved)


# --- 4. Transparência verdadeira -----------------------------------------------------

func _test_alpha() -> void:
	print("-- Transparência")
	var partial: int = 0
	for y: int in _atlas.get_height():
		for x: int in _atlas.get_width():
			var a: int = _atlas.get_pixel(x, y).a8
			if a != 0 and a != 255:
				partial += 1
	_check(partial == 0, "alfa só 0 ou 255 (%d pixels semitransparentes)" % partial)


# --- 5. Grade ---------------------------------------------------------------------------

func _test_grid() -> void:
	print("-- Grade")
	_check(CELLS.size() == COLUMNS * ROWS, "mapa cobre as %d células" % (COLUMNS * ROWS))
	for cell: Vector2i in CELLS:
		var opaque: int = _opaque_count(cell)
		var kind: int = CELLS[cell][0]
		if kind == Kind.EMPTY:
			_check(opaque == 0, "%s vazia: 100%% transparente (%d px opacos)" % [cell, opaque])
		else:
			_check(opaque >= TILE * TILE / 2, "%s usada e preenchida (%d px opacos)" % [cell, opaque])


# --- 6. Bordas de contato opacas e transparência só nos lados expostos ----------------

func _test_borders_and_transparency() -> void:
	print("-- Bordas de contato e transparência")
	for cell: Vector2i in CELLS:
		var kind: int = CELLS[cell][0]
		if kind == Kind.EMPTY:
			continue
		var connected: String = CELLS[cell][1]
		# Plataformas: só o corpo (faixa de colisão) precisa ser opaco nos lados de contato.
		var rows: int = PLATFORM_BODY_ROWS if kind == Kind.PLATFORM else TILE
		var holes: int = 0
		for side: String in connected:
			for k: int in TILE:
				var p: Vector2i = _side_pixel(side, k)
				if p.y < rows and _alpha(cell, p) == 0:
					holes += 1
		_check(holes == 0, "%s: lados de contato %s 100%% opacos (%d furos)" % [cell, connected if connected != "" else "-", holes])
		if kind == Kind.SOLID:
			var misplaced: int = 0
			for y: int in TILE:
				for x: int in TILE:
					if _alpha(cell, Vector2i(x, y)) == 0 and not _near_exposed(connected, Vector2i(x, y)):
						misplaced += 1
			_check(misplaced == 0, "%s: transparência só a até %d px de um lado exposto (%d fora)" % [cell, EXPOSED_MARGIN, misplaced])


# --- 7. Superfície de apoio -----------------------------------------------------------

func _test_walk_surfaces() -> void:
	print("-- Superfície de apoio (linha 0)")
	for cell: Vector2i in CELLS:
		var kind: int = CELLS[cell][0]
		var connected: String = CELLS[cell][1]
		var walkable: bool = kind == Kind.PLATFORM or (kind == Kind.SOLID and not connected.contains("C"))
		if not walkable:
			continue
		var gaps: int = 0
		for x: int in TILE:
			var left_rounding: bool = not connected.contains("E") and x < ROUNDING
			var right_rounding: bool = not connected.contains("D") and x >= TILE - ROUNDING
			if not left_rounding and not right_rounding and _alpha(cell, Vector2i(x, 0)) == 0:
				gaps += 1
		_check(gaps == 0, "%s: linha 0 opaca (arredondamento máx. %d px nas pontas; %d falhas)" % [cell, ROUNDING, gaps])
		if kind == Kind.PLATFORM:
			var body_gaps: int = 0
			for y: int in range(1, PLATFORM_BODY_ROWS):
				for x: int in range(EXPOSED_MARGIN, TILE - EXPOSED_MARGIN):
					if _alpha(cell, Vector2i(x, y)) == 0:
						body_gaps += 1
			_check(body_gaps == 0, "%s: corpo da plataforma (linhas 0..%d) opaco (%d falhas)" % [cell, PLATFORM_BODY_ROWS - 1, body_gaps])


# --- Contorno nos lados expostos -------------------------------------------------------

func _test_exposed_outline() -> void:
	print("-- Contorno nos lados expostos")
	for cell: Vector2i in CELLS:
		if CELLS[cell][0] != Kind.SOLID:
			continue
		var connected: String = CELLS[cell][1]
		var wrong: int = 0
		for side: String in "CBED":
			if connected.contains(side):
				continue
			for k: int in TILE:
				var p: Vector2i = _side_pixel(side, k)
				var c: Color = _pixel(cell, p)
				if c.a8 != 0 and _index(c) != OUTLINE_INDEX:
					wrong += 1
		_check(wrong == 0, "%s: lados expostos só com contorno ou transparência (%d pixels)" % [cell, wrong])


# --- 8 e 9. Encaixe entre vizinhos (inclui centros repetidos em mosaico) ----------------

func _test_seams() -> void:
	print("-- Encaixe entre vizinhos")
	var tops: Array[Vector2i] = [Vector2i(1, 0), Vector2i(5, 0), Vector2i(6, 0)]
	var centers: Array[Vector2i] = [Vector2i(1, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)]
	var bottoms: Array[Vector2i] = [Vector2i(1, 2), Vector2i(6, 2)]
	var platforms: Array[Vector2i] = [Vector2i(4, 3), Vector2i(6, 3)]
	var horizontal: Array = []   # [esquerda, direita]
	var vertical: Array = []     # [cima, baixo]
	_pairs_all(horizontal, tops, tops)
	_pairs_all(horizontal, [Vector2i(0, 0), Vector2i(4, 0)], tops)
	_pairs_all(horizontal, tops, [Vector2i(2, 0), Vector2i(3, 0)])
	_pairs_all(horizontal, centers, centers)
	_pairs_all(horizontal, [Vector2i(0, 1), Vector2i(3, 0), Vector2i(3, 1)], centers)
	_pairs_all(horizontal, centers, [Vector2i(2, 1), Vector2i(4, 0), Vector2i(4, 1)])
	_pairs_all(horizontal, bottoms, bottoms)
	_pairs_all(horizontal, [Vector2i(0, 2), Vector2i(4, 1)], bottoms)
	_pairs_all(horizontal, bottoms, [Vector2i(2, 2), Vector2i(3, 1)])
	_pairs_all(horizontal, [Vector2i(3, 2), Vector2i(4, 2)], [Vector2i(4, 2), Vector2i(5, 2)])
	_pairs_all(horizontal, platforms, platforms)
	_pairs_all(horizontal, [Vector2i(3, 3)], platforms)
	_pairs_all(horizontal, platforms, [Vector2i(5, 3)])

	_pairs_all(vertical, tops, centers)
	_pairs_all(vertical, centers, centers)
	_pairs_all(vertical, centers, bottoms)
	_pairs_all(vertical, [Vector2i(3, 0), Vector2i(4, 0)], centers)
	_pairs_all(vertical, centers, [Vector2i(3, 1), Vector2i(4, 1)])
	# Parede acima de canto interno (rocha encontrando o musgo do canto) fica fora desta
	# métrica: é uma troca de material proposital, verificada em _test_inner_corner_walls().
	_pairs_all(vertical, [Vector2i(0, 0), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(0, 2)])
	_pairs_all(vertical, [Vector2i(3, 1)], [Vector2i(0, 1)])
	_pairs_all(vertical, [Vector2i(2, 0), Vector2i(2, 1)], [Vector2i(2, 1), Vector2i(2, 2)])
	_pairs_all(vertical, [Vector2i(4, 1)], [Vector2i(2, 1)])
	_pairs_all(vertical, [Vector2i(0, 3), Vector2i(1, 3)], [Vector2i(1, 3), Vector2i(2, 3)])

	var worst: float = 0.0
	var worst_pair: String = ""
	var total: float = 0.0
	var failed: Array[String] = []
	for direction: Array in [[horizontal, true, "|"], [vertical, false, "/"]]:
		for pair: Array in direction[0]:
			var ratio: float = _seam_ratio(pair[0], pair[1], direction[1])
			var label: String = "%s%s%s" % [pair[0], direction[2], pair[1]]
			total += ratio
			if ratio > worst:
				worst = ratio
				worst_pair = label
			if ratio > SEAM_MAX:
				failed.append("%s %.2f" % [label, ratio])
	var count: int = horizontal.size() + vertical.size()
	var mean: float = total / count
	print("     (%d pares lado a lado + %d empilhados; média %.2f, pior %.2f em %s)" % [
		horizontal.size(), vertical.size(), mean, worst, worst_pair])
	_check(failed.is_empty(), "cada emenda ≤ %.2fx a variação interna (pior %.2f)%s" % [
		SEAM_MAX, worst, "" if failed.is_empty() else "; acima: " + ", ".join(failed)])
	_check(mean <= SEAM_MEAN_MAX, "média das emendas ≤ %.1f (%.2f)" % [SEAM_MEAN_MAX, mean])


# --- Parede acima de canto interno: musgo, contorno e silhueta -----------------------------

## Canto interno ↖ (3,0): topo à esquerda, parede (lado esquerdo exposto) acima.
## Canto interno ↗ (4,0): topo à direita, parede (lado direito exposto) acima.
func _test_inner_corner_walls() -> void:
	print("-- Parede acima de canto interno")
	var tops: Array[Vector2i] = [Vector2i(1, 0), Vector2i(5, 0), Vector2i(6, 0)]
	for spec: Array in [
		[Vector2i(3, 0), [Vector2i(0, 1), Vector2i(0, 0)], true],
		[Vector2i(4, 0), [Vector2i(2, 1), Vector2i(2, 0)], false],
	]:
		var corner: Vector2i = spec[0]
		var walls: Array = spec[1]
		var left: bool = spec[2]
		# Coluna do canto que encosta no topo vizinho, e a coluna do topo que encosta nele.
		var corner_col: int = 0 if left else TILE - 1
		var top_col: int = TILE - 1 if left else 0
		var wall_col: int = 0 if left else TILE - 1

		# Silhueta: o canto é sólido e a parede encosta nele sem furos.
		_check(_opaque_count(corner) == TILE * TILE, "%s: canto interno 100%% opaco" % corner)
		for wall: Vector2i in walls:
			var holes: int = 0
			for x: int in TILE:
				if _alpha(wall, Vector2i(x, TILE - 1)) == 0:
					holes += 1
			_check(holes == 0, "%s sobre %s: linha de contato da parede sem furos (%d)" % [wall, corner, holes])

		# Contorno: o contorno da parede desce até o canto e o contorno do topo chega até ele,
		# fechando o "L" no ponto de encontro.
		for wall: Vector2i in walls:
			_check(_index(_pixel(wall, Vector2i(wall_col, TILE - 1))) == OUTLINE_INDEX,
				"%s sobre %s: contorno da parede chega ao canto" % [wall, corner])
		for top: Vector2i in tops:
			_check(_index(_pixel(top, Vector2i(top_col, 0))) == OUTLINE_INDEX,
				"%s ao lado de %s: contorno do topo chega ao canto" % [top, corner])

		# Musgo: o canto continua o musgo do topo vizinho (encosta na linha 0, profundidade
		# parecida na coluna de encontro) e se afina para dentro, sem musgo fora do canto.
		_check(_is_green(_pixel(corner, Vector2i(corner_col, 0))), "%s: musgo encosta na linha do chão" % corner)
		var corner_depth: int = _moss_depth(corner, corner_col)
		for top: Vector2i in tops:
			var top_depth: int = _moss_depth(top, top_col)
			_check(absi(corner_depth - top_depth) <= MOSS_DEPTH_TOLERANCE,
				"%s ao lado de %s: profundidade do musgo %d e %d (tolerância %d)" % [top, corner, top_depth, corner_depth, MOSS_DEPTH_TOLERANCE])
		var depths: Array[int] = []
		for i: int in 4:
			depths.append(_moss_depth(corner, corner_col + (i if left else -i)))
		var tapers: bool = true
		for i: int in range(1, depths.size()):
			tapers = tapers and depths[i] <= depths[i - 1]
		_check(tapers, "%s: musgo se afina para dentro do canto (profundidades %s)" % [corner, depths])
		var stray: int = 0
		for y: int in TILE:
			for x: int in TILE:
				var inside_band: bool = (x < 4) if left else (x >= TILE - 4)
				if not inside_band and _is_green(_pixel(corner, Vector2i(x, y))):
					stray += 1
		_check(stray == 0, "%s: musgo só nas 4 colunas do encontro (%d pixels fora)" % [corner, stray])


# --- 10. Variações sem mudar a colisão --------------------------------------------------

func _test_variations() -> void:
	print("-- Variações")
	for cell: Vector2i in CELLS:
		var base: Variant = CELLS[cell][2]
		if base == null:
			continue
		var base_cell: Vector2i = base
		_check(CELLS[cell][1] == CELLS[base_cell][1], "%s: mesmos lados de contato de %s" % [cell, base_cell])
		var rows: int = PLATFORM_BODY_ROWS if CELLS[cell][0] == Kind.PLATFORM else TILE
		var diff: int = 0
		for y: int in rows:
			for x: int in TILE:
				if (_alpha(cell, Vector2i(x, y)) == 0) != (_alpha(base_cell, Vector2i(x, y)) == 0):
					diff += 1
		_check(diff == 0, "%s: silhueta igual à de %s nas linhas 0..%d (%d pixels diferentes)" % [cell, base_cell, rows - 1, diff])


# --- Auxiliares -------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _pixel(cell: Vector2i, p: Vector2i) -> Color:
	return _atlas.get_pixel(cell.x * TILE + p.x, cell.y * TILE + p.y)


func _alpha(cell: Vector2i, p: Vector2i) -> int:
	return _pixel(cell, p).a8


func _index(c: Color) -> int:
	return _palette_lookup.get(Color(c.r, c.g, c.b, 1.0).to_rgba32(), -1)


func _is_green(c: Color) -> bool:
	return c.a8 != 0 and GREEN_INDICES.has(_index(c))


## Linha mais baixa com musgo na coluna (−1 se não houver).
func _moss_depth(cell: Vector2i, x: int) -> int:
	var depth: int = -1
	for y: int in TILE:
		if _is_green(_pixel(cell, Vector2i(x, y))):
			depth = y
	return depth


func _opaque_count(cell: Vector2i) -> int:
	var count: int = 0
	for y: int in TILE:
		for x: int in TILE:
			if _alpha(cell, Vector2i(x, y)) != 0:
				count += 1
	return count


## k-ésimo pixel da linha/coluna de borda do lado indicado.
func _side_pixel(side: String, k: int) -> Vector2i:
	match side:
		"C":
			return Vector2i(k, 0)
		"B":
			return Vector2i(k, TILE - 1)
		"E":
			return Vector2i(0, k)
		_:
			return Vector2i(TILE - 1, k)


func _near_exposed(connected: String, p: Vector2i) -> bool:
	return (not connected.contains("C") and p.y < EXPOSED_MARGIN) \
		or (not connected.contains("B") and p.y >= TILE - EXPOSED_MARGIN) \
		or (not connected.contains("E") and p.x < EXPOSED_MARGIN) \
		or (not connected.contains("D") and p.x >= TILE - EXPOSED_MARGIN)


func _pairs_all(out: Array, firsts: Array, seconds: Array) -> void:
	for a: Vector2i in firsts:
		for b: Vector2i in seconds:
			out.append([a, b])


func _difference(a: Color, b: Color) -> float:
	return absf(a.get_luminance() - b.get_luminance()) + (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 0.3


## Diferença média que atravessa a emenda dividida pela diferença média entre pixels
## vizinhos (na mesma direção) dentro dos dois tiles. Só pares de pixels opacos contam.
func _seam_ratio(first: Vector2i, second: Vector2i, horizontal: bool) -> float:
	var across: float = 0.0
	var across_n: int = 0
	for k: int in TILE:
		var a: Vector2i = Vector2i(TILE - 1, k) if horizontal else Vector2i(k, TILE - 1)
		var b: Vector2i = Vector2i(0, k) if horizontal else Vector2i(k, 0)
		var ca: Color = _pixel(first, a)
		var cb: Color = _pixel(second, b)
		if ca.a8 == 0 or cb.a8 == 0:
			continue
		across += _difference(ca, cb)
		across_n += 1
	var inside: float = 0.0
	var inside_n: int = 0
	for cell: Vector2i in [first, second]:
		for k: int in TILE:
			for j: int in TILE - 1:
				var p: Vector2i = Vector2i(j, k) if horizontal else Vector2i(k, j)
				var q: Vector2i = p + (Vector2i(1, 0) if horizontal else Vector2i(0, 1))
				var cp: Color = _pixel(cell, p)
				var cq: Color = _pixel(cell, q)
				if cp.a8 == 0 or cq.a8 == 0:
					continue
				inside += _difference(cp, cq)
				inside_n += 1
	if across_n == 0 or inside_n == 0 or inside == 0.0:
		return 0.0
	return (across / across_n) / (inside / inside_n)
