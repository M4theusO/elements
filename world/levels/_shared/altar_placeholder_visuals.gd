extends Node2D
## Arte PROVISÓRIA do Altar Elemental (até a arte definitiva da Etapa 8.4): pedestal de pedra e
## uma gema desenhados por código em pixels inteiros, com a gema mostrando o estado do altar
## pai (state_changed): inativo = apagada, ativado = âmbar escuro, atual = âmbar claro com brilho.
## Para trocar pela arte definitiva, basta substituir o nó Visuals; o altar não depende dele.
## Origem = base do pedestal (chão), como o altar.

const STONE_DARK: Color = Color("#2a2628")
const STONE: Color = Color("#47403d")
const STONE_LIGHT: Color = Color("#6b625b")
const GEM_INACTIVE: Color = Color("#3a3640")
const GEM_ACTIVATED: Color = Color("#8a3a10")
const GEM_CURRENT: Color = Color("#ffc85a")
const GLOW_CURRENT: Color = Color("#fb9524")
## Larguras das linhas da gema (losango de 8x8, pares para ficar centrado em pixels inteiros).
const GEM_ROWS: Array[int] = [2, 4, 6, 8, 8, 6, 4, 2]
const GEM_TOP: int = -33

var _activated: bool = false
var _current: bool = false


func _ready() -> void:
	var altar: ElementalAltar = get_parent() as ElementalAltar
	if altar != null:
		altar.state_changed.connect(_on_state_changed)
		_on_state_changed(altar.is_activated(), altar.is_current())


## Cor atual da gema (para testes e depuração).
func get_gem_color() -> Color:
	if _current:
		return GEM_CURRENT
	return GEM_ACTIVATED if _activated else GEM_INACTIVE


func _on_state_changed(is_activated: bool, is_current: bool) -> void:
	_activated = is_activated
	_current = is_current
	queue_redraw()


func _draw() -> void:
	# Pedestal: base 20x4, coluna 12x16, tampo 18x3.
	draw_rect(Rect2(-10, -4, 20, 4), STONE_DARK)
	draw_rect(Rect2(-6, -20, 12, 16), STONE)
	draw_rect(Rect2(-6, -20, 2, 16), STONE_LIGHT)
	draw_rect(Rect2(-9, -23, 18, 3), STONE_LIGHT)
	if _current:
		# Brilho: moldura de 1 px em volta do losango.
		for i: int in GEM_ROWS.size():
			var glow_width: int = GEM_ROWS[i] + 2
			draw_rect(Rect2(-(glow_width >> 1), GEM_TOP + i - 1, glow_width, 3), GLOW_CURRENT)
	var gem: Color = get_gem_color()
	for i: int in GEM_ROWS.size():
		var width: int = GEM_ROWS[i]
		draw_rect(Rect2(-(width >> 1), GEM_TOP + i, width, 1), gem)
