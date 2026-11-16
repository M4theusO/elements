class_name HeartsDisplay
extends Control
## Fileira de corações: um por ponto de vida máximo, cheios até a vida atual e vazios no resto.
## Sem texturas, desenha corações provisórios em pixel art por código (HEART_PATTERN); quando a
## arte existir, basta atribuir full_texture e empty_texture (mesmo tamanho para os dois).

## Coração provisório (11x10). X = contorno, R = vermelho, D = sombra, H = brilho, . = vazio.
## No coração vazio, R/D/H viram EMPTY_FILL.
const HEART_PATTERN: Array[String] = [
	".XXX...XXX.",
	"XRRRX.XRRRX",
	"XRHRRXRRRDX",
	"XRHRRRRRRDX",
	"XRRRRRRRRDX",
	".XRRRRRRDX.",
	"..XRRRRDX..",
	"...XRRDX...",
	"....XDX....",
	".....X.....",
]
## Cores provisórias dos corações (vermelho aprovado para a vida; contorno da paleta do terreno).
const OUTLINE: Color = Color("130f12")
const FILL: Color = Color("c4303c")
const SHADE: Color = Color("7c1c2a")
const HIGHLIGHT: Color = Color("f2867a")
const EMPTY_FILL: Color = Color("3a2a30")

## Textura do coração cheio (opcional; sem ela, usa o desenho provisório).
@export var full_texture: Texture2D:
	set(value):
		full_texture = value
		_refresh()
## Textura do coração vazio (opcional).
@export var empty_texture: Texture2D:
	set(value):
		empty_texture = value
		_refresh()
## Espaço entre corações, em pixels.
@export_range(0, 16, 1) var spacing: int = 2:
	set(value):
		spacing = value
		_refresh()

var _current: int = 0
var _maximum: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


## Atualiza a fileira (vida limitada entre 0 e maximum).
func set_values(current: int, maximum: int) -> void:
	_maximum = maxi(maximum, 0)
	_current = clampi(current, 0, _maximum)
	_refresh()


func get_full_count() -> int:
	return _current


func get_empty_count() -> int:
	return _maximum - _current


func get_maximum() -> int:
	return _maximum


## Tamanho de um coração: o da textura, ou o do desenho provisório.
func get_heart_size() -> Vector2i:
	if full_texture != null:
		return Vector2i(full_texture.get_size())
	return Vector2i(HEART_PATTERN[0].length(), HEART_PATTERN.size())


func _refresh() -> void:
	var heart: Vector2i = get_heart_size()
	custom_minimum_size = Vector2(maxi(_maximum * heart.x + maxi(_maximum - 1, 0) * spacing, 0), heart.y)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var heart: Vector2i = get_heart_size()
	for i in _maximum:
		var origin := Vector2(i * (heart.x + spacing), 0)
		var full: bool = i < _current
		var tex: Texture2D = full_texture if full else empty_texture
		if tex != null:
			draw_texture(tex, origin)
		else:
			_draw_pattern(origin, full)


func _draw_pattern(origin: Vector2, full: bool) -> void:
	for y in HEART_PATTERN.size():
		var row: String = HEART_PATTERN[y]
		for x in row.length():
			var c: Color
			match row[x]:
				"X": c = OUTLINE
				"R": c = FILL if full else EMPTY_FILL
				"D": c = SHADE if full else EMPTY_FILL
				"H": c = HIGHLIGHT if full else EMPTY_FILL
				_: continue
			draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), c)
