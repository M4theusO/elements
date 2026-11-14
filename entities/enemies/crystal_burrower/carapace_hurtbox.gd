class_name CarapaceHurtbox
extends Hurtbox
## Hurtbox com carapaça nas costas: golpes que vêm de trás (deslocando-se para o mesmo lado
## para onde o dono olha) causam só uma fração do dano. Frente e costas saem da trajetória
## do golpe (hit_direction), não da posição do atacante, para valer também para projéteis.
## Frações de HP ficam num acumulador até somarem 1 (ex.: 1 HP pelas costas = 0, 1, 0, 1...).
## Não conhece o dono: ele liga/desliga a carapaça (shell_active) e zera o acumulador.

## Golpe absorvido por inteiro pela carapaça (0 de dano aplicado).
signal shell_blocked

## Componente horizontal mínimo da trajetória para saber o lado; abaixo disso, dano integral.
const DIRECTION_EPSILON: float = 0.0001
## Tolerância de arredondamento ao tirar a parte inteira do acumulador.
const DAMAGE_EPSILON: float = 0.0001

## Nó cuja orientação define a frente (escala x positiva = olhando para a direita).
@export var facing_node: Node2D
## Fração do dano que passa pela carapaça.
@export_range(0.0, 1.0, 0.05) var back_damage_multiplier: float = 0.5

## Desligada, todo golpe causa dano integral (ex.: dono vulnerável).
var shell_active: bool = true

var _pending_damage: float = 0.0
var _last_hit_on_shell: bool = false


## O último golpe aceito acertou a carapaça (vindo das costas, com ela ativa).
func is_last_hit_on_shell() -> bool:
	return _last_hit_on_shell


## Fração de HP guardada, ainda não aplicada.
func get_pending_damage() -> float:
	return _pending_damage


func reset_pending_damage() -> void:
	_pending_damage = 0.0


func _get_damage_taken(damage: int, hit_direction: Vector2) -> int:
	_last_hit_on_shell = false
	if not shell_active or facing_node == null or absf(hit_direction.x) <= DIRECTION_EPSILON:
		return damage
	var facing: float = signf(facing_node.global_transform.x.x)
	# Golpe frontal: vem ao encontro do dono (trajetória oposta à orientação).
	if hit_direction.x * facing <= 0.0:
		return damage
	_last_hit_on_shell = true
	_pending_damage += damage * back_damage_multiplier
	var taken: int = floori(_pending_damage + DAMAGE_EPSILON)
	_pending_damage = maxf(_pending_damage - taken, 0.0)
	if taken <= 0:
		shell_blocked.emit()
	return taken
