extends SceneTree
## Teste automatizado do fundo com parallax do Reino das Profundezas
## (world/levels/depths/backgrounds/): imagens (tamanho, paleta, alfa, pixel inteiro, zonas,
## emenda horizontal), importação, cena (Parallax2D, sem colisões nem scripts), ligação com a
## sala de teste (atrás do terreno, câmera e configurações gráficas preservadas) e cobertura
## real da tela com a câmera nos limites da sala e em salas maiores.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/depths_parallax_test.gd

const DIR: String = "res://world/levels/depths/backgrounds/"
const SCENE_PATH: String = DIR + "depths_parallax.tscn"
const ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const PALETTE_PATH: String = DIR + "depths_bg_palette.png"

const VIEW: Vector2i = Vector2i(640, 360)
## Zona central (y) onde ficam os personagens; a camada próxima deve ficar limpa nela.
const CENTER_ROWS: Vector2i = Vector2i(96, 288)

## nó, arquivo, tamanho, escala do pixel da arte, scroll_scale, opaca, ocupação máxima na zona central
const LAYERS: Array = [
	["Far", "depths_bg_far.png", Vector2i(852, 360), 4, Vector2(0.15, 0.0), true, 1.0],
	["Mid", "depths_bg_mid.png", Vector2i(1110, 360), 6, Vector2(0.40, 0.0), false, 0.40],
	["Near", "depths_bg_near.png", Vector2i(1056, 360), 6, Vector2(0.70, 0.0), false, 0.05],
]
const PALETTE: Array[String] = [
	"0d1524", "192841", "263c5c", "34527a",
	"0e222c", "143442", "1b4554", "1f5163",
	"06090f", "0b121b", "111a26", "1c1520",
]
## Sala de teste: limites da câmera e posições originais.
const CAMERA_LIMITS: Rect2i = Rect2i(0, 0, 768, 368)
const TERRA_POS: Vector2 = Vector2(56, 320)
const FRAGMENT_FLOOR_POS: Vector2 = Vector2(648, 320)
## LivingFragmentPlatform: movido no editor em 2026-11-14 para o chão, ao pé do 1º degrau (aprovado).
const FRAGMENT_PLATFORM_POS: Vector2 = Vector2(302, 316)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Fundo com parallax: Reino das Profundezas")
	await process_frame
	_test_palette_file()
	for spec: Array in LAYERS:
		_test_image(spec)
		_test_import(spec)
	_test_scene()
	await _test_room()
	await _test_large_room_coverage()
	_test_project_settings()
	_finish()


# --- Imagens ---------------------------------------------------------------------------

func _test_palette_file() -> void:
	var img := _load_png(PALETTE_PATH)
	_check(img.get_size() == Vector2i(12, 1), "paleta: 12x1 (obtido %s)" % img.get_size())
	var ok := true
	for i in mini(img.get_width(), PALETTE.size()):
		if img.get_pixel(i, 0).to_html(false) != PALETTE[i] or img.get_pixel(i, 0).a8 != 255:
			ok = false
	_check(ok, "paleta: 12 cores aprovadas, na ordem far, mid, near")


func _test_image(spec: Array) -> void:
	var name: String = spec[0]
	var img := _load_png(DIR + spec[1])
	var size: Vector2i = spec[2]
	var scale: int = spec[3]
	_check(img.get_size() == size, "%s: tamanho %s (obtido %s)" % [name, size, img.get_size()])
	if img.get_size() != size:
		return
	var layer_index := LAYERS.find(spec)
	var allowed := {}
	for k in 4:
		allowed[PALETTE[layer_index * 4 + k]] = true

	var bad_color := 0
	var bad_alpha := 0
	var transparent := 0
	var center_cov := 0
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				bad_alpha += 1
			if c.a8 == 0:
				transparent += 1
			else:
				if not allowed.has(c.to_html(false)):
					bad_color += 1
				if y >= CENTER_ROWS.x and y < CENTER_ROWS.y:
					center_cov += 1
	_check(bad_color == 0, "%s: só as 4 cores da camada (fora da paleta: %d)" % [name, bad_color])
	_check(bad_alpha == 0, "%s: alfa só 0 ou 255, sem antialiasing (parciais: %d)" % [name, bad_alpha])
	if spec[5]:
		_check(transparent == 0, "%s: opaca (transparentes: %d)" % [name, transparent])
	var cov := float(center_cov) / (size.x * (CENTER_ROWS.y - CENTER_ROWS.x))
	_check(cov <= spec[6], "%s: ocupação da zona central y %d–%d = %.1f%% (máx. %.0f%%)" % [name, CENTER_ROWS.x, CENTER_ROWS.y, cov * 100.0, spec[6] * 100.0])
	if not spec[5]:
		var side_empty := true
		for y in range(int(size.y * 0.3), int(size.y * 0.7)):
			if img.get_pixel(0, y).a8 != 0 or img.get_pixel(size.x - 1, y).a8 != 0:
				side_empty = false
		_check(side_empty, "%s: laterais vazias entre 30%% e 70%% da altura (faixas de teto e chão podem tocar as bordas)" % name)

	# Pixel da arte inteiro: cada bloco scale x scale tem uma única cor (ampliação sem mistura).
	var mixed := 0
	for by in size.y / scale:
		for bx in size.x / scale:
			var ref := img.get_pixel(bx * scale, by * scale)
			for oy in scale:
				for ox in scale:
					if img.get_pixel(bx * scale + ox, by * scale + oy) != ref:
						mixed += 1
	_check(size.x % scale == 0 and size.y % scale == 0 and mixed == 0, "%s: pixels da arte de %dx%d px inteiros (pixels divergentes: %d)" % [name, scale, scale, mixed])

	# Emenda horizontal, no espaço dos pixels da arte: a dupla (última coluna, primeira coluna)
	# deve parecer com uma dupla vizinha interna (linhas diferentes e degrau dos contornos).
	var cols := size.x / scale
	var diffs: Array[int] = []
	var steps: Array[int] = []
	for c in cols - 1:
		var a := _art_column(img, c, scale)
		var b := _art_column(img, c + 1, scale)
		diffs.append(_row_diff(a, b))
		steps.append(_contour_step(a, b))
	diffs.sort()
	steps.sort()
	var last := _art_column(img, cols - 1, scale)
	var first := _art_column(img, 0, scale)
	var seam_diff := _row_diff(last, first)
	var seam_step := _contour_step(last, first)
	var p95_diff: int = diffs[int(diffs.size() * 0.95)]
	var p95_step: int = steps[int(steps.size() * 0.95)]
	_check(seam_diff <= p95_diff, "%s: emenda com %d linhas diferentes (p95 interno %d)" % [name, seam_diff, p95_diff])
	_check(seam_step <= mini(maxi(p95_step, 1), 2), "%s: silhuetas contínuas na emenda, degrau %d pixel(s) da arte (máx. %d)" % [name, seam_step, mini(maxi(p95_step, 1), 2)])


func _test_import(spec: Array) -> void:
	var name: String = spec[0]
	var cfg := ConfigFile.new()
	var err := cfg.load(DIR + spec[1] + ".import")
	_check(err == OK, "%s: arquivo .import presente" % name)
	if err != OK:
		return
	_check(cfg.get_value("params", "compress/mode", -1) == 0, "%s: importação Lossless" % name)
	_check(cfg.get_value("params", "mipmaps/generate", true) == false, "%s: sem mipmaps" % name)
	var tex := load(DIR + spec[1]) as Texture2D
	_check(tex != null and Vector2i(tex.get_size()) == spec[2], "%s: textura carregada com o tamanho da PNG" % name)


# --- Cena ------------------------------------------------------------------------------

func _test_scene() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "cena depths_parallax.tscn carrega")
	if scene == null:
		return
	var root := scene.instantiate()
	_check(root is Node2D and root.get_script() == null, "raiz Node2D sem script")
	_check(root.get_child_count() == LAYERS.size(), "3 camadas (obtido %d)" % root.get_child_count())
	for i in mini(root.get_child_count(), LAYERS.size()):
		var spec: Array = LAYERS[i]
		var par := root.get_child(i) as Parallax2D
		_check(par != null and par.name == spec[0], "camada %d = Parallax2D %s (ordem: distante, intermediária, próxima)" % [i, spec[0]])
		if par == null:
			continue
		var size: Vector2i = spec[2]
		_check(par.scroll_scale.is_equal_approx(spec[4]), "%s: scroll_scale %s (obtido %s)" % [spec[0], spec[4], par.scroll_scale])
		_check(par.repeat_size == Vector2(size.x, 0), "%s: repeat_size (%d, 0), só horizontal (obtido %s)" % [spec[0], size.x, par.repeat_size])
		_check(par.repeat_times == 1 and par.scroll_offset == Vector2.ZERO and par.autoscroll == Vector2.ZERO, "%s: repeat_times 1, sem scroll_offset nem autoscroll" % spec[0])
		_check(not par.ignore_camera_scroll and par.follow_viewport, "%s: segue a câmera" % spec[0])
		_check(par.z_index == 0 and par.z_as_relative, "%s: z_index 0 (fica atrás pela ordem na árvore)" % spec[0])
		var spr := par.get_node_or_null("Sprite2D") as Sprite2D
		_check(spr != null and par.get_child_count() == 1, "%s: um Sprite2D" % spec[0])
		if spr == null:
			continue
		_check(spr.texture != null and spr.texture.resource_path == DIR + spec[1], "%s: textura %s" % [spec[0], spec[1]])
		_check(not spr.centered and spr.position == Vector2.ZERO and spr.scale == Vector2.ONE and spr.offset == Vector2.ZERO, "%s: Sprite2D sem centralizar, em (0,0), escala 1" % spec[0])
		_check(spr.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and par.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE, "%s: filtro herdado (Nearest do projeto)" % spec[0])
		_check(spr.z_index == 0, "%s: Sprite2D com z_index 0" % spec[0])
	var forbidden := _find_forbidden(root)
	_check(forbidden.is_empty(), "sem colisões, áreas ou scripts no fundo %s" % (str(forbidden) if not forbidden.is_empty() else ""))
	root.free()


func _find_forbidden(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D or child is CollisionPolygon2D or child.get_script() != null:
			out.append(str(child.name))
		out.append_array(_find_forbidden(child))
	return out


# --- Sala de teste ---------------------------------------------------------------------

func _test_room() -> void:
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(room)
	var bg := room.get_node_or_null("Background") as Node2D
	var terrain := room.get_node_or_null("Terrain")
	_check(bg != null and bg.scene_file_path == SCENE_PATH, "sala: Background é instância de depths_parallax.tscn")
	_check(bg != null and terrain != null and bg.get_index() == 0 and bg.get_index() < terrain.get_index(), "sala: Background é o primeiro filho, antes do Terrain (desenhado atrás)")
	if bg == null or terrain == null:
		room.queue_free()
		return
	_check(bg.position == Vector2.ZERO and bg.z_index == 0 and bg.get_script() == null, "sala: instância sem posição, z_index ou script sobrescritos")
	var terra := room.get_node("Terra") as Node2D
	var cam := room.get_node("Terra/Camera2D") as Camera2D
	_check(Rect2i(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top) == CAMERA_LIMITS, "sala: limites da câmera preservados (0, 0, 768, 368)")
	_check(terra.position == TERRA_POS and (room.get_node("Enemies/LivingFragmentFloor") as Node2D).position == FRAGMENT_FLOOR_POS and (room.get_node("Enemies/LivingFragmentPlatform") as Node2D).position == FRAGMENT_PLATFORM_POS, "sala: posições da Terra e dos Fragmentos Vivos preservadas")

	# Cobertura real: a Terra parada em pontos da sala (a câmera vai até os limites).
	for e in room.get_node("Enemies").get_children():
		e.queue_free()
	terra.set_physics_process(false)
	for x: float in [0.0, 56.0, 300.0, 384.0, 452.3, 600.0, 768.0]:
		terra.position = Vector2(x, 320.0)
		await _wait(3)
		_check_coverage(bg, "sala, Terra em x %.1f (borda esquerda da câmera %.1f)" % [x, cam.get_screen_center_position().x - VIEW.x / 2.0])
	room.queue_free()
	await _wait(1)


## Salas maiores (reaproveitamento): câmera livre em posições extremas, inclusive negativas.
func _test_large_room_coverage() -> void:
	var holder := Node2D.new()
	root.add_child(holder)
	var bg := (load(SCENE_PATH) as PackedScene).instantiate() as Node2D
	holder.add_child(bg)
	var cam := Camera2D.new()
	holder.add_child(cam)
	cam.make_current()
	for p: Vector2 in [Vector2(-9000, 180), Vector2(-333.3, 900), Vector2(4586, 180), Vector2(5680, 2400), Vector2(20000.7, -500)]:
		cam.position = p
		await _wait(3)
		_check_coverage(bg, "sala maior, câmera em %s" % p)
	holder.queue_free()
	await _wait(1)


## Cada camada, na tela: começa em (-largura, 0] e se repete à direita (repeat_times 1),
## então cobre os 640 px; na vertical fica presa à tela (y = 0), cobrindo os 360 px.
## A distante (opaca) cobre a tela inteira. Confere também a velocidade: deslocamento na
## tela = -(borda da câmera x scroll_scale) módulo largura.
func _check_coverage(bg: Node2D, label: String) -> void:
	var ok := true
	var detail := ""
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var par := bg.get_child(i) as Parallax2D
		var w: float = (spec[2] as Vector2i).x
		var screen := par.position - par.screen_offset
		var expected := -fposmod(par.screen_offset.x * (spec[4] as Vector2).x, w)
		var start_ok := screen.x <= 0.001 and screen.x > -w
		var covers := start_ok and screen.x + 2.0 * w >= VIEW.x and w >= VIEW.x
		var speed_ok := absf(screen.x - expected) < 0.01 or absf(absf(screen.x - expected) - w) < 0.01
		if not (covers and speed_ok and absf(screen.y) < 0.001):
			ok = false
			detail += " %s: x %.2f (esperado %.2f), y %.2f;" % [spec[0], screen.x, expected, screen.y]
	_check(ok, "cobertura total e velocidades corretas: " + label + detail)


func _test_project_settings() -> void:
	_check(ProjectSettings.get_setting("display/window/size/viewport_width") == 640 and ProjectSettings.get_setting("display/window/size/viewport_height") == 360, "projeto: resolução interna 640x360 preservada")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer", "projeto: stretch viewport e escala inteira preservados")
	_check(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0, "projeto: filtro padrão Nearest preservado")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "projeto: renderizador Compatibility preservado")
	_check(not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"), "projeto: snap de transformações 2D inalterado (desligado)")


# --- Auxiliares ------------------------------------------------------------------------

func _load_png(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Coluna c em pixels da arte; vazio = "", senão a cor.
func _art_column(img: Image, c: int, scale: int) -> Array[String]:
	var out: Array[String] = []
	for r in img.get_height() / scale:
		var px := img.get_pixel(c * scale, r * scale)
		out.append("" if px.a8 == 0 else px.to_html(false))
	return out


func _row_diff(a: Array[String], b: Array[String]) -> int:
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n


## Maior distância entre uma fronteira de cor/vazio de uma coluna e a fronteira mais próxima
## da outra (nos dois sentidos), em pixels da arte; fronteira sem par a até 6 conta como 6.
func _contour_step(a: Array[String], b: Array[String]) -> int:
	var ea := _edges(a)
	var eb := _edges(b)
	var worst := 0
	for pair: Array in [[ea, eb], [eb, ea]]:
		for e: int in pair[0]:
			var best := 6
			for f: int in pair[1]:
				best = mini(best, absi(f - e))
			worst = maxi(worst, best)
	return worst


func _edges(col: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for i in range(1, col.size()):
		if col[i] != col[i - 1]:
			out.append(i)
	return out


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _finish() -> void:
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)
