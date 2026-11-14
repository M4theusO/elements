extends SceneTree
## Teste automatizado dos cristais decorativos do Reino das Profundezas
## (world/props/depths/crystals/): paleta dos props, imagens (tamanho, transparência, cores,
## âncora, centralização), importação, cenas (Sprite2D sem script, colisões nem animação) e
## uso na sala de teste (nó Props entre Terrain e Enemies, apoio real no terreno, sem invadir
## tiles, regras de posicionamento, preservação de câmera, parallax e posições).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/props/depths_crystals_test.gd

const DIR: String = "res://world/props/depths/crystals/"
const PROPS_PALETTE: String = "res://world/props/depths/depths_props_palette.png"
const TERRAIN_PALETTE: String = "res://world/tilesets/depths/depths_palette.png"
const ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const PARALLAX_PATH: String = "res://world/levels/depths/backgrounds/depths_parallax.tscn"
const TILE: int = 16

## arquivo, nó raiz, tamanho, âncora, offset
const CRYSTALS: Array = [
	["crystal_small", "CrystalSmall", Vector2i(16, 24), "floor", Vector2(-8, -24)],
	["crystal_medium", "CrystalMedium", Vector2i(32, 32), "floor", Vector2(-16, -32)],
	["crystal_large", "CrystalLarge", Vector2i(48, 56), "floor", Vector2(-24, -56)],
	["crystal_ceiling", "CrystalCeiling", Vector2i(40, 48), "ceiling", Vector2(-20, 0)],
]
const NEW_COLORS: Array[String] = ["8a3a10", "ffc85a", "fff1c2", "2a2628", "47403d", "6b625b", "958a7e"]
## 10 cores do grupo dos cristais: contorno, rocha, cristal
const CRYSTAL_COLORS: Array[String] = [
	"130f12", "221817", "43261d", "5a3321", "794526", "98592c",
	"8a3a10", "fb9524", "ffc85a", "fff1c2",
]
const MIN_CONTACT: int = 4

## Regras da sala: superfícies do caminho principal (chão e degraus), onde a Terra anda e a
## onda sísmica corre. Cristais grandes ficam fora delas; médios e grandes fora do início.
const MAIN_PATH_Y: Array[int] = [320, 304, 288, 272]
const SPAWN_ZONE: Vector2i = Vector2i(32, 96)  # x onde a Terra começa (até 1 tile além do corpo)
const CAMERA_LIMITS: Rect2i = Rect2i(0, 0, 768, 368)
const TERRA_POS: Vector2 = Vector2(56, 320)
const FRAGMENT_FLOOR_POS: Vector2 = Vector2(648, 320)
const FRAGMENT_PLATFORM_POS: Vector2 = Vector2(600, 224)

var _failures: int = 0
var _checks: int = 0
var _images: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Cristais decorativos: Reino das Profundezas")
	await process_frame
	_test_palette()
	for spec: Array in CRYSTALS:
		_test_image(spec)
		_test_import(spec)
		_test_scene(spec)
	_test_room()
	_finish()


# --- Paleta e imagens ------------------------------------------------------------------

func _test_palette() -> void:
	var props := _load_png(PROPS_PALETTE)
	var terrain := _load_png(TERRAIN_PALETTE)
	_check(props.get_size() == Vector2i(24, 1), "paleta dos props: 24x1 (obtido %s)" % props.get_size())
	var same := true
	for i in mini(17, terrain.get_width()):
		if props.get_pixel(i, 0) != terrain.get_pixel(i, 0):
			same = false
	_check(same, "paleta dos props: começa com as 17 cores do terreno, na mesma ordem")
	var new_ok := true
	for i in NEW_COLORS.size():
		if 17 + i >= props.get_width() or props.get_pixel(17 + i, 0).to_html(false) != NEW_COLORS[i]:
			new_ok = false
	_check(new_ok, "paleta dos props: 7 cores novas aprovadas no fim (âmbar e pedra das ruínas)")
	var all_in := true
	for h in CRYSTAL_COLORS:
		var found := false
		for i in props.get_width():
			if props.get_pixel(i, 0).to_html(false) == h:
				found = true
		all_in = all_in and found
	_check(all_in, "as 10 cores dos cristais estão na paleta dos props")


func _test_image(spec: Array) -> void:
	var name: String = spec[0]
	var size: Vector2i = spec[2]
	var img := _load_png(DIR + name + ".png")
	_images[name] = img
	_check(img.get_size() == size, "%s: tamanho %s (obtido %s)" % [name, size, img.get_size()])
	if img.get_size() != size:
		return
	var bad_color := 0
	var bad_alpha := 0
	var opaque := 0
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				bad_alpha += 1
			if c.a8 == 255:
				opaque += 1
				if not CRYSTAL_COLORS.has(c.to_html(false)):
					bad_color += 1
	_check(bad_alpha == 0, "%s: transparência real, alfa só 0 ou 255 (parciais: %d)" % [name, bad_alpha])
	_check(bad_color == 0, "%s: só as 10 cores dos cristais (fora: %d)" % [name, bad_color])
	_check(opaque > 0 and opaque < size.x * size.y, "%s: tem desenho e fundo transparente (%d px opacos)" % [name, opaque])
	var used := img.get_used_rect()
	var floor: bool = spec[3] == "floor"
	var anchor_row := size.y - 1 if floor else 0
	var contact := 0
	for x in size.x:
		if img.get_pixel(x, anchor_row).a8 == 255:
			contact += 1
	_check((used.end.y == size.y) if floor else (used.position.y == 0), "%s: desenho encosta na %s da caixa (âncora real)" % [name, "última linha" if floor else "primeira linha"])
	_check(contact >= MIN_CONTACT, "%s: contato com o %s de %d px (mín. %d)" % [name, "chão" if floor else "teto", contact, MIN_CONTACT])
	var center_err := absf((used.position.x + used.size.x / 2.0) - size.x / 2.0)
	_check(center_err <= 0.5, "%s: desenho centrado na largura (desvio %.1f px)" % [name, center_err])


func _test_import(spec: Array) -> void:
	var name: String = spec[0]
	var cfg := ConfigFile.new()
	var err := cfg.load(DIR + name + ".png.import")
	_check(err == OK, "%s: arquivo .import presente" % name)
	if err != OK:
		return
	_check(cfg.get_value("params", "compress/mode", -1) == 0 and cfg.get_value("params", "mipmaps/generate", true) == false, "%s: importação Lossless, sem mipmaps" % name)
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
	_check(spr.position == Vector2.ZERO and spr.scale == Vector2.ONE and spr.rotation == 0.0 and not spr.flip_h and not spr.flip_v, "%s: sem transformação na cena" % name)
	_check(spr.hframes == 1 and spr.vframes == 1 and not spr.region_enabled, "%s: um único quadro, sem região" % name)
	_check(spr.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and spr.z_index == 0 and spr.z_as_relative, "%s: filtro herdado (Nearest do projeto) e z_index 0" % name)
	spr.free()


# --- Sala de teste ---------------------------------------------------------------------

func _test_room() -> void:
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node2D
	var props := room.get_node_or_null("Props") as Node2D
	var terrain := room.get_node_or_null("Terrain") as TileMapLayer
	var enemies := room.get_node_or_null("Enemies")
	var terra := room.get_node_or_null("Terra") as Node2D
	var bg := room.get_node_or_null("Background")
	_check(props != null and props.get_class() == "Node2D" and props.get_script() == null, "sala: nó Props (Node2D, sem script)")
	if props == null or terrain == null or enemies == null or terra == null or bg == null:
		_check(false, "sala: Background, Terrain, Props, Enemies e Terra presentes")
		room.free()
		return
	_check(bg.get_index() == 0 and terrain.get_index() == 1 and props.get_index() == 2 and enemies.get_index() == 3 and terra.get_index() == 4, "sala: ordem Background, Terrain, Props, Enemies, Terra (props atrás de inimigos, Terra e golpes)")
	_check(props.position == Vector2.ZERO and props.z_index == 0 and props.z_as_relative and terrain.z_index == 0 and enemies.z_index == 0 and terra.z_index == 0, "sala: z_index 0 em Terrain, Props, Enemies e Terra (a ordem na árvore decide)")

	var used_types := {}
	var all_instances := true
	var all_integer := true
	var all_plain := true
	var supported := true
	var no_overlap := true
	var rules := true
	var details := PackedStringArray()
	for child in props.get_children():
		var inst := child as Sprite2D
		var spec: Array = []
		for s: Array in CRYSTALS:
			if child.scene_file_path == DIR + s[0] + ".tscn":
				spec = s
		if inst == null or spec.is_empty():
			all_instances = false
			continue
		used_types[spec[0]] = true
		var pos := inst.position
		if pos != pos.round():
			all_integer = false
		if inst.scale != Vector2.ONE or inst.rotation != 0.0 or inst.z_index != 0 or inst.offset != spec[4] or inst.flip_h or inst.flip_v or inst.get_child_count() != 0 or inst.get_script() != null:
			all_plain = false
		var img: Image = _images.get(spec[0])
		if img == null:
			continue
		var floor: bool = spec[3] == "floor"
		var origin := Vector2i(pos) + Vector2i(spec[4])
		var anchor_row := img.get_height() - 1 if floor else 0
		# Apoio: todo pixel opaco da linha da âncora fica sobre (ou sob) um tile sólido.
		for x in img.get_width():
			var sx := img.get_width() - 1 - x if inst.flip_h else x
			if img.get_pixel(sx, anchor_row).a8 != 255:
				continue
			var p := origin + Vector2i(x, anchor_row)
			var support := p + (Vector2i(0, 1) if floor else Vector2i(0, -1))
			if not _solid(terrain, support):
				supported = false
				details.append("%s sem apoio em %s" % [child.name, p])
				break
		# Nenhum pixel opaco dentro de um tile sólido.
		for y in img.get_height():
			for x in img.get_width():
				var sx := img.get_width() - 1 - x if inst.flip_h else x
				if img.get_pixel(sx, y).a8 == 255 and _solid(terrain, origin + Vector2i(x, y)):
					no_overlap = false
		# Regras de posicionamento.
		var height := img.get_used_rect().size.y
		if spec[0] == "crystal_large" and floor and MAIN_PATH_Y.has(int(pos.y)):
			rules = false
			details.append("%s: cristal grande no caminho principal (y %d)" % [child.name, int(pos.y)])
		if floor and height > 24 and pos.x + img.get_width() / 2.0 > SPAWN_ZONE.x and pos.x - img.get_width() / 2.0 < SPAWN_ZONE.y and int(pos.y) == 320:
			rules = false
			details.append("%s: cristal alto no início da Terra" % child.name)
	_check(props.get_child_count() > 0 and all_instances, "sala: Props só contém instâncias das cenas de cristal (%d)" % props.get_child_count())
	_check(used_types.size() == CRYSTALS.size(), "sala: os quatro tipos de cristal aparecem (%s)" % ", ".join(used_types.keys()))
	_check(props.get_child_count() <= 12, "sala: quantidade contida (%d cristais, máx. 12)" % props.get_child_count())
	_check(all_integer, "sala: posições em pixels inteiros")
	_check(all_plain, "sala: instâncias só sobrescrevem a posição (regra da sala: sem flip, escala, rotação, z_index, offset ou filhos)")
	_check(supported, "sala: cristais de chão apoiados no terreno e pendentes presos ao teto em toda a linha de contato %s" % " ".join(details))
	_check(no_overlap, "sala: nenhum pixel de cristal dentro de tiles sólidos (não cobre chão, paredes nem plataformas)")
	_check(rules, "sala: cristais grandes fora do caminho principal e nenhum cristal alto no início da Terra %s" % " ".join(details))

	# Preservação: câmera, posições, parallax e ausência de colisões nos props.
	var cam := room.get_node("Terra/Camera2D") as Camera2D
	_check(Rect2i(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top) == CAMERA_LIMITS, "sala: limites da câmera preservados")
	_check(terra.position == TERRA_POS and (room.get_node("Enemies/LivingFragmentFloor") as Node2D).position == FRAGMENT_FLOOR_POS and (room.get_node("Enemies/LivingFragmentPlatform") as Node2D).position == FRAGMENT_PLATFORM_POS, "sala: posições da Terra e dos Fragmentos Vivos preservadas")
	_check(bg.scene_file_path == PARALLAX_PATH, "sala: Background continua sendo o parallax")
	_check(_find_forbidden(props).is_empty(), "sala: nenhum corpo, colisão, área ou script em Props")
	room.free()


func _solid(terrain: TileMapLayer, p: Vector2i) -> bool:
	return terrain.get_cell_source_id(Vector2i(floori(p.x / float(TILE)), floori(p.y / float(TILE)))) != -1


func _find_forbidden(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D or child is CollisionPolygon2D or child.get_script() != null:
			out.append(str(child.name))
		out.append_array(_find_forbidden(child))
	return out


# --- Auxiliares ------------------------------------------------------------------------

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
