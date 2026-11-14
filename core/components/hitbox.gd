class_name Hitbox
extends Area2D
## Área que causa dano. Não ocupa layer; procura hurtboxes pela mask (definida na cena).
## Só detecta enquanto ativa; cada Hurtbox é atingida no máximo uma vez por ativação.

signal hit_landed(hurtbox: Hurtbox)

## Fase exibida na representação provisória do alcance.
enum DebugPhase { HIDDEN, WINDUP, ACTIVE }

const DEBUG_WINDUP_COLOR: Color = Color(1.0, 0.85, 0.3, 0.25)
const DEBUG_ACTIVE_COLOR: Color = Color(1.0, 0.45, 0.2, 0.6)

@export var damage: int = 1
## Desenha o alcance do golpe (provisório, enquanto não há animação de ataque).
@export var show_debug: bool = true

var _is_active: bool = false
var _hit_targets: Array[Hurtbox] = []
var _debug_phase: DebugPhase = DebugPhase.HIDDEN


func _ready() -> void:
	monitoring = false
	monitorable = false


func _physics_process(_delta: float) -> void:
	# Consulta as sobreposições a cada tick: cobre tanto alvos que entram durante o golpe
	# quanto os que já estavam dentro do alcance quando ele foi ativado.
	if not _is_active or not monitoring:
		return
	for area: Area2D in get_overlapping_areas():
		var hurtbox: Hurtbox = area as Hurtbox
		if hurtbox == null or _hit_targets.has(hurtbox):
			continue
		_hit_targets.append(hurtbox)
		hurtbox.receive_hit(damage, get_hit_direction())
		hit_landed.emit(hurtbox)


func _draw() -> void:
	if not show_debug or _debug_phase == DebugPhase.HIDDEN:
		return
	var color: Color = DEBUG_ACTIVE_COLOR if _debug_phase == DebugPhase.ACTIVE else DEBUG_WINDUP_COLOR
	for child: Node in get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			draw_rect(Rect2(shape_node.position - size / 2.0, size), color)


func activate() -> void:
	_hit_targets.clear()
	_is_active = true
	# Deferido: pode ser chamado durante callbacks de física.
	set_deferred("monitoring", true)
	set_debug_phase(DebugPhase.ACTIVE)


func deactivate() -> void:
	_is_active = false
	set_deferred("monitoring", false)
	set_debug_phase(DebugPhase.HIDDEN)


func is_active() -> bool:
	return _is_active


## Trajetória do golpe no mundo (vetor unitário), repassada à Hurtbox atingida.
## Padrão: eixo x global da hitbox, que acompanha o flip e a rotação dos pais
## (golpe corpo a corpo dentro de Visuals). Hitboxes que se movem por conta própria
## (projéteis, ondas) devem sobrescrever com a direção real do movimento.
func get_hit_direction() -> Vector2:
	return global_transform.x.normalized()


func set_debug_phase(phase: DebugPhase) -> void:
	if phase != _debug_phase:
		_debug_phase = phase
		queue_redraw()
