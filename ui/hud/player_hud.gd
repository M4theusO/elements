class_name PlayerHud
extends CanvasLayer
## HUD da personagem jogável: corações de vida no canto superior esquerdo, fixos na tela
## (CanvasLayer não segue a câmera). Só apresenta: lê um HealthComponent e redesenha a cada
## health_changed. Não conhece a implementação da personagem nem decide nada sobre a morte.
##
## De onde vem a vida, em ordem: health (direto) > target.get_health() > primeiro nó do grupo
## target_group com get_health(). Assim serve para Terra, Aqua, Ignis e Aeris sem mudanças.

## Vida a mostrar (opcional; tem prioridade sobre target).
@export var health: HealthComponent
## Nó que expõe get_health() -> HealthComponent (opcional).
@export var target: Node
## Grupo procurado quando health e target estão vazios.
@export var target_group: StringName = &"player"

var _bound: HealthComponent

@onready var _hearts: HeartsDisplay = $Root/Hearts


func _ready() -> void:
	var source: HealthComponent = health
	if source == null:
		var node: Node = target
		if node == null and not target_group.is_empty():
			node = get_tree().get_first_node_in_group(target_group)
		if node != null:
			# A vida atual só existe depois do _ready do dono (current_health é @onready).
			if not node.is_node_ready():
				await node.ready
			if node.has_method(&"get_health"):
				source = node.call(&"get_health") as HealthComponent
	if source == null:
		push_warning("PlayerHud: nenhuma vida encontrada (health, target ou grupo '%s')." % target_group)
		return
	bind_health(source)


## Passa a mostrar esta vida (troca de personagem, por exemplo).
func bind_health(source: HealthComponent) -> void:
	if _bound != null and _bound.health_changed.is_connected(_on_health_changed):
		_bound.health_changed.disconnect(_on_health_changed)
	_bound = source
	if source == null:
		_hearts.set_values(0, 0)
		return
	if not source.is_node_ready():
		await source.ready
	source.health_changed.connect(_on_health_changed)
	_hearts.set_values(source.current_health, source.max_health)


func get_bound_health() -> HealthComponent:
	return _bound


func get_hearts() -> HeartsDisplay:
	return _hearts


func _on_health_changed(current: int, maximum: int) -> void:
	_hearts.set_values(current, maximum)
