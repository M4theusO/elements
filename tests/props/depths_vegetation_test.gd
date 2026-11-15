extends SceneTree
## Teste automatizado da vegetação decorativa do Reino das Profundezas
## (world/props/depths/vegetation/): imagens (tamanho, transparência, cores por sprite, âncora,
## centralização, continuidade), importação, cenas (Sprite2D sem script, colisões nem animação) e
## uso na sala de teste (no nó Props depois dos cristais, apoio no desenho real do terreno,
## superfícies jogáveis livres, altura livre sob as peças penduradas, regras do caminho principal,
## preservação de cristais, câmera, parallax e posições).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/props/depths_vegetation_test.gd

const DIR: String = "res://world/props/depths/vegetation/"
const CRYSTAL_DIR: String = "res://world/props/depths/crystals/"
const PROPS_ROOT: String = "res://world/props/depths/"
const PROPS_PALETTE: String = "res://world/props/depths/depths_props_palette.png"
const ATLAS_PATH: String = "res://world/tilesets/depths/depths_terrain.png"
const ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const TILE: int = 16

const MOSS: Array[String] = ["221817", "301d18", "1a1e0c", "3f4612", "646a12", "878b13"]
const ROOT: Array[String] = ["130f12", "221817", "301d18", "43261d", "5a3321", "794526", "98592c"]
const FUNGI: Array[String] = ["221817", "43261d", "5a3321", "98592c", "c08550", "e3a86d", "3f4612", "646a12"]

## arquivo, nó raiz, caixa, âncora, offset, cores permitidas, contato mínimo
const SPRITES: Array = [
	["moss_hanging", "MossHanging", Vector2i(48, 32), "ceiling", Vector2(-24, 0), MOSS, 6],
	["root_short", "RootShort", Vector2i(32, 48), "ceiling", Vector2(-16, 0), ROOT, 2],
	["root_long", "RootLong", Vector2i(48, 64), "ceiling", Vector2(-24, 0), ROOT, 2],
	["moss_tuft", "MossTuft", Vector2i(32, 16), "floor", Vector2(-16, -16), MOSS, 6],
	["fungi_small", "FungiSmall", Vector2i(24, 24), "floor", Vector2(-12, -24), FUNGI, 2],
	["fungi_tall", "FungiTall", Vector2i(24, 32), "floor", Vector2(-12, -32), FUNGI, 2],
]

## Sala: quantidade de vegetação, regras e o que deve ser preservado.
const VEG_COUNT_RANGE: Vector2i = Vector2i(8, 10)
const MAIN_PATH_Y: Array[int] = [320, 304, 288, 272]
## No caminho principal, só vegetação baixa (exceto junto à parede). 20 px: o fungi_small aprovado
## tem 19 px de arte e foi aprovado no chão principal na composição de 2026-11-14.
const LOW_PROP_MAX_H: int = 20
const WALL_GAP: int = 4  # "encostada na parede": parede sólida a até 4 px do desenho
const SPAWN_ZONE: Vector2i = Vector2i(32, 96)
const TERRA_H: int = 46
const HEADROOM: int = 8
const SURFACE_DEPTH: int = 4  # topo dos tiles de chão que deve continuar visível
const PLATFORM_DEPTH: int = 8  # faixa one-way das plataformas que deve continuar visível
const CAMERA_LIMITS: Rect2i = Rect2i(0, 0, 768, 368)
const TERRA_POS: Vector2 = Vector2(56, 320)
const FRAGMENT_FLOOR_POS: Vector2 = Vector2(648, 320)
## LivingFragmentPlatform: movido no editor em 2026-11-14 para o chão, ao pé do 1º degrau (aprovado).
const FRAGMENT_PLATFORM_POS: Vector2 = Vector2(302, 316)
const CRYSTALS_EXPECTED: Dictionary = {
	"CrystalLargeBlock": Vector2(120, 128), "CrystalMediumStrip": Vector2(224, 240),
	"CrystalMediumCorner": Vector2(720, 320), "CrystalSmallFloor": Vector2(264, 320),
	"CrystalSmallStep": Vector2(404, 304), "CrystalSmallRight": Vector2(560, 320),
	"CrystalCeilingLeft": Vector2(200, 32), "CrystalCeilingSteps": Vector2(456, 32),
}

var _failures: int = 0
var _checks: int = 0
var _images: Dictionary = {}
var _terrain: TileMapLayer
var _atlas: Image


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Vegetação decorativa: Reino das Profundezas")
	await process_frame
	_test_palette()
	for spec: Array in SPRITES:
		_test_image(spec)
		_test_import(spec)
		_test_scene(spec)
	_test_room()
	_finish()


# --- Paleta e imagens ------------------------------------------------------------------

func _test_palette() -> void:
	var pal := _load_png(PROPS_PALETTE)
	var colors := {}
	for i in pal.get_width():
		colors[pal.get_pixel(i, 0).to_html(false)] = true
	var ok := true
	for list: Array in [MOSS, ROOT, FUNGI]:
		for h: String in list:
			ok = ok and colors.has(h)
	_check(pal.get_width() == 24 and ok, "as cores de musgos, raízes e fungos estão na paleta dos props (24 cores, nenhuma nova)")
	_check(not MOSS.has("aead19") and ROOT.has("98592c"), "listas aprovadas: musgos sem #aead19, raízes com #98592c")


func _test_image(spec: Array) -> void:
	var name: String = spec[0]
	var size: Vector2i = spec[2]
	var allowed: Array = spec[5]
	var img := _load_png(DIR + name + ".png")
	_images[name] = img
	_check(img.get_size() == size, "%s: tamanho %s (obtido %s)" % [name, size, img.get_size()])
	if img.get_size() != size:
		return
	var bad_alpha := 0
	var bad_color := 0
	var opaque := 0
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				bad_alpha += 1
			if c.a8 == 255:
				opaque += 1
				if not allowed.has(c.to_html(false)):
					bad_color += 1
	_check(bad_alpha == 0, "%s: transparência real, alfa só 0 ou 255 (parciais: %d)" % [name, bad_alpha])
	_check(bad_color == 0, "%s: só as %d cores permitidas para o sprite (fora: %d)" % [name, allowed.size(), bad_color])
	_check(opaque > 0 and opaque < size.x * size.y, "%s: tem desenho e fundo transparente (%d px opacos)" % [name, opaque])
	var used := img.get_used_rect()
	var floor: bool = spec[3] == "floor"
	var row := size.y - 1 if floor else 0
	var contact := 0
	for x in size.x:
		if img.get_pixel(x, row).a8 == 255:
			contact += 1
	_check((used.end.y == size.y) if floor else (used.position.y == 0), "%s: desenho encosta na %s da caixa (âncora real)" % [name, "última linha" if floor else "primeira linha"])
	_check(contact >= int(spec[6]), "%s: contato com o %s de %d px (mín. %d)" % [name, "chão" if floor else "teto", contact, spec[6]])
	_check(used.position.x == (size.x - used.size.x) / 2, "%s: desenho centrado na largura (x %d, sobra ímpar à direita)" % [name, used.position.x])
	# Continuidade: pedaços separados só geram aviso (não reprovam).
	var comps := _components(img)
	print("  [INFO] %s: %d pedaço(s) 8-conectado(s)%s" % [name, comps, "" if comps == 1 else " — revisar traços finos"])


func _test_import(spec: Array) -> void:
	var name: String = spec[0]
	var cfg := ConfigFile.new()
	var err := cfg.load(DIR + name + ".png.import")
	_check(err == OK and cfg.get_value("params", "compress/mode", -1) == 0 and cfg.get_value("params", "mipmaps/generate", true) == false, "%s: importação Lossless, sem mipmaps" % name)
	var tex := load(DIR + name + ".png") as Texture2D
	_check(tex != null and Vector2i(tex.get_size()) == spec[2], "%s: textura carregada com o tamanho da PNG" % name)


func _test_scene(spec: Array) -> void:
	var name: String = spec[0]
	var scene := load(DIR + name + ".tscn") as PackedScene
	_check(scene != null, "%s.tscn carrega" % name)
	if scene == null:
		return
	var spr := scene.instantiate() as Sprite2D
	_check(spr != null and spr.name == spec[1], "%s: raiz Sprite2D \"%s\"" % [name, spec[1]])
	if spr == null:
		return
	_check(spr.get_script() == null and spr.get_child_count() == 0, "%s: sem script e sem filhos (sem colisões, áreas ou animações)" % name)
	_check(spr.texture != null and spr.texture.resource_path == DIR + name + ".png", "%s: textura %s.png" % [name, name])
	_check(not spr.centered and spr.offset == spec[4], "%s: centered desligado, offset %s (âncora %s)" % [name, spec[4], "chão" if spec[3] == "floor" else "teto"])
	_check(spr.position == Vector2.ZERO and spr.scale == Vector2.ONE and spr.rotation == 0.0 and not spr.flip_h and not spr.flip_v and spr.hframes == 1 and spr.vframes == 1 and not spr.region_enabled, "%s: sem transformação, um único quadro" % name)
	_check(spr.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and spr.z_index == 0 and spr.z_as_relative, "%s: filtro herdado (Nearest do projeto) e z_index 0" % name)
	spr.free()


# --- Sala de teste ---------------------------------------------------------------------

func _test_room() -> void:
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node2D
	var props := room.get_node_or_null("Props") as Node2D
	_terrain = room.get_node_or_null("Terrain") as TileMapLayer
	_atlas = _load_png(ATLAS_PATH)
	if props == null or _terrain == null:
		_check(false, "sala: Props e Terrain presentes")
		room.free()
		return
	_check(props.get_index() == _terrain.get_index() + 1 and props.get_index() < room.get_node("Enemies").get_index() and props.get_index() < room.get_node("Terra").get_index(), "sala: Props entre Terrain e Enemies/Terra (vegetação atrás de personagens e golpes)")

	var types := {}
	var veg: Array[Sprite2D] = []
	var last_crystal := -1
	var first_veg := 99999
	var all_props := true
	for child in props.get_children():
		if not child.scene_file_path.begins_with(PROPS_ROOT):
			all_props = false
		if child.scene_file_path.begins_with(CRYSTAL_DIR):
			last_crystal = maxi(last_crystal, child.get_index())
		for s: Array in SPRITES:
			if child.scene_file_path == DIR + s[0] + ".tscn":
				types[s[0]] = true
				veg.append(child as Sprite2D)
				first_veg = mini(first_veg, child.get_index())
	_check(all_props, "sala: todo filho de Props é cena de props da região")
	_check(types.size() == SPRITES.size(), "sala: os seis tipos de vegetação aparecem (%s)" % ", ".join(types.keys()))
	_check(veg.size() >= VEG_COUNT_RANGE.x and veg.size() <= VEG_COUNT_RANGE.y, "sala: %d instâncias de vegetação (entre %d e %d)" % [veg.size(), VEG_COUNT_RANGE.x, VEG_COUNT_RANGE.y])
	_check(first_veg > last_crystal, "sala: vegetação depois dos cristais em Props (cristais preservados na mesma ordem)")

	var plain := true
	var integer := true
	var supported := true
	var surfaces_free := true
	var headroom_ok := true
	var path_ok := true
	var d_support := PackedStringArray()
	var d_headroom := PackedStringArray()
	var d_path := PackedStringArray()
	for inst in veg:
		var spec: Array = []
		for s: Array in SPRITES:
			if inst.scene_file_path == DIR + s[0] + ".tscn":
				spec = s
		var img: Image = _images.get(spec[0])
		if img == null:
			continue
		if inst.position != inst.position.round():
			integer = false
		if inst.scale != Vector2.ONE or inst.rotation != 0.0 or inst.z_index != 0 or inst.offset != spec[4] or inst.flip_h or inst.flip_v or inst.get_child_count() != 0 or inst.get_script() != null:
			plain = false
		var floor: bool = spec[3] == "floor"
		var origin := Vector2i(inst.position) + Vector2i(spec[4])
		var used := img.get_used_rect()
		# Apoio no desenho real do terreno: cada pixel opaco da linha da âncora tem um pixel opaco
		# do atlas logo abaixo (chão) ou acima (teto), com até 2 px de folga.
		var row := img.get_height() - 1 if floor else 0
		for x in img.get_width():
			if img.get_pixel(x, row).a8 != 255:
				continue
			var p := origin + Vector2i(x, row)
			var ok := false
			for d in range(1, 3):
				if _opaque(p + (Vector2i(0, d) if floor else Vector2i(0, -d))):
					ok = true
					break
			if not ok:
				supported = false
				d_support.append("%s sem apoio em %s" % [inst.name, p])
				break
		# Superfícies jogáveis livres: nenhum pixel sobre o topo do chão (4 px) nem sobre a faixa
		# one-way das plataformas (8 px). Sobreposição decorativa em outros pixels é permitida.
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a8 == 255 and _on_playable_surface(origin + Vector2i(x, y)):
					surfaces_free = false
		# Altura livre sob peças penduradas: Terra de pé (46 px) + 8 px de folga.
		if not floor:
			var bottom := origin.y + used.end.y
			for x in range(origin.x + used.position.x, origin.x + used.end.x):
				var y := bottom
				while y < 23 * TILE and not _solid(Vector2i(x, y)):
					y += 1
				if y - bottom < TERRA_H + HEADROOM:
					headroom_ok = false
					d_headroom.append("%s invade a altura livre em x %d (%d px)" % [inst.name, x, y - bottom])
					break
		# Caminho principal: no chão e nos degraus, só vegetação baixa, exceto encostada numa
		# parede; nada alto no início da Terra.
		if floor and MAIN_PATH_Y.has(int(inst.position.y)) and used.size.y > LOW_PROP_MAX_H:
			var l := origin.x + used.position.x - 1
			var r := origin.x + used.end.x
			var y_mid := int(inst.position.y) - 2
			var against_wall := false
			for g in range(1, WALL_GAP + 1):
				against_wall = against_wall or _solid(Vector2i(l - g + 1, y_mid)) or _solid(Vector2i(r + g - 1, y_mid))
			var in_spawn := int(inst.position.y) == 320 and r > SPAWN_ZONE.x and l < SPAWN_ZONE.y
			if not against_wall or in_spawn:
				path_ok = false
				d_path.append("%s alto no caminho principal sem parede ao lado" % inst.name)
	_check(integer, "sala: posições da vegetação em pixels inteiros")
	_check(plain, "sala: instâncias só sobrescrevem a posição (regra da sala)")
	_check(supported, "sala: vegetação apoiada no desenho real do terreno (pixel opaco do atlas) %s" % " ".join(d_support))
	_check(surfaces_free, "sala: topo do chão e faixa one-way das plataformas continuam visíveis (sobreposição só decorativa)")
	_check(headroom_ok, "sala: peças penduradas deixam altura livre para a Terra de pé (%d px) %s" % [TERRA_H + HEADROOM, " ".join(d_headroom)])
	_check(path_ok, "sala: no caminho principal só vegetação baixa (até %d px) ou encostada na parede; nada alto no início %s" % [LOW_PROP_MAX_H, " ".join(d_path)])

	# Preservação.
	var crystals_ok := true
	for n: String in CRYSTALS_EXPECTED:
		var c := props.get_node_or_null(n) as Node2D
		if c == null or c.position != CRYSTALS_EXPECTED[n]:
			crystals_ok = false
	_check(crystals_ok, "sala: os 8 cristais continuam com as mesmas posições")
	var cam := room.get_node("Terra/Camera2D") as Camera2D
	_check(Rect2i(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top) == CAMERA_LIMITS, "sala: limites da câmera preservados")
	_check((room.get_node("Terra") as Node2D).position == TERRA_POS and (room.get_node("Enemies/LivingFragmentFloor") as Node2D).position == FRAGMENT_FLOOR_POS and (room.get_node("Enemies/LivingFragmentPlatform") as Node2D).position == FRAGMENT_PLATFORM_POS, "sala: posições da Terra e dos Fragmentos Vivos preservadas")
	_check(room.get_node("Background").scene_file_path == PARALLAX_PATH and room.get_node("Background").get_index() == 0, "sala: parallax preservado como primeiro filho")
	_check(_find_forbidden(props).is_empty(), "sala: nenhum corpo, colisão, área ou script em Props")
	room.free()


func _cell(p: Vector2i) -> Vector2i:
	return Vector2i(floori(p.x / float(TILE)), floori(p.y / float(TILE)))


func _solid(p: Vector2i) -> bool:
	return _terrain.get_cell_source_id(_cell(p)) != -1


func _opaque(p: Vector2i) -> bool:
	var cell := _cell(p)
	if _terrain.get_cell_source_id(cell) == -1:
		return false
	var ac := _terrain.get_cell_atlas_coords(cell)
	return _atlas.get_pixel(ac.x * TILE + posmod(p.x, TILE), ac.y * TILE + posmod(p.y, TILE)).a8 > 0


func _is_platform(cell: Vector2i) -> bool:
	var data := _terrain.get_cell_tile_data(cell)
	return data != null and data.get_collision_polygons_count(1) > 0


## Pixel no topo visível de uma superfície jogável: tile sólido com o tile de cima vazio,
## nas primeiras SURFACE_DEPTH linhas (PLATFORM_DEPTH nas plataformas one-way).
func _on_playable_surface(p: Vector2i) -> bool:
	var cell := _cell(p)
	if _terrain.get_cell_source_id(cell) == -1 or _terrain.get_cell_source_id(cell + Vector2i(0, -1)) != -1:
		return false
	var depth := PLATFORM_DEPTH if _is_platform(cell) else SURFACE_DEPTH
	return posmod(p.y, TILE) < depth and _opaque(p)


func _components(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var count := 0
	for y in h:
		for x in w:
			if seen[y * w + x] == 1 or img.get_pixel(x, y).a8 != 255:
				continue
			count += 1
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * w + x] = 1
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var q := p + Vector2i(dx, dy)
						if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and seen[q.y * w + q.x] == 0 and img.get_pixel(q.x, q.y).a8 == 255:
							seen[q.y * w + q.x] = 1
							stack.append(q)
	return count


func _find_forbidden(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D or child is CollisionPolygon2D or child.get_script() != null:
			out.append(str(child.name))
		out.append_array(_find_forbidden(child))
	return out


func _load_png(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _finish() -> void:
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)
