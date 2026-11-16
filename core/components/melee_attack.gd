class_name MeleeAttack
extends Node
## Controla o tempo de um golpe corpo a corpo: preparação, fase ativa e recuperação.
## Liga a Hitbox só na fase ativa. Um novo golpe só começa depois da recuperação.

signal attack_started
signal attack_finished

enum Phase { READY, WINDUP, ACTIVE, RECOVERY }

## Tolerância de arredondamento: sem ela, somas de ticks (1/60 s) que deveriam fechar
## exatamente uma duração podem ficar um resíduo abaixo e gerar um tick a mais.
const TIME_EPSILON: float = 0.0001

@export var attack: AttackData
@export var hitbox: Hitbox

var _phase: Phase = Phase.READY
var _phase_time_left: float = 0.0


func _ready() -> void:
	# Avança as fases antes do personagem dono no mesmo tick, para que ele leia o estado
	# atualizado (direção travada e animação) sem atraso de um tick.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if _phase == Phase.READY:
		return
	_phase_time_left -= delta
	# O excedente passa para a fase seguinte, mantendo a duração total exata.
	while _phase != Phase.READY and _phase_time_left <= TIME_EPSILON:
		_advance_phase()


## Inicia um golpe se estiver pronto. Retorna se o golpe começou.
func try_attack() -> bool:
	if _phase != Phase.READY or attack == null or hitbox == null:
		return false
	hitbox.damage = attack.damage
	hitbox.set_debug_phase(Hitbox.DebugPhase.WINDUP)
	_phase = Phase.WINDUP
	_phase_time_left = attack.windup_time
	attack_started.emit()
	return true


## Verdadeiro durante a preparação e a fase ativa.
func is_striking() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.ACTIVE


## Verdadeiro do início do golpe até o fim da recuperação.
func is_busy() -> bool:
	return _phase != Phase.READY


## Encerra a fase ativa antes do tempo (ex.: investida que bate numa parede): desliga a
## Hitbox na hora e começa a recuperação completa a partir deste tick. Só age na fase ativa;
## na preparação, na recuperação ou pronto não faz nada (nunca adianta nem liga a hitbox).
## Retorna se a fase ativa foi encerrada.
func finish_active() -> bool:
	if _phase != Phase.ACTIVE:
		return false
	_phase = Phase.RECOVERY
	_phase_time_left = attack.recovery_time
	hitbox.deactivate()
	return true


## Interrompe o golpe em qualquer fase, sem dano nem recuperação (ex.: troca de sala):
## desliga a Hitbox e volta a pronto. Retorna se havia um golpe em andamento.
func cancel() -> bool:
	if _phase == Phase.READY:
		return false
	_phase = Phase.READY
	_phase_time_left = 0.0
	hitbox.deactivate()
	attack_finished.emit()
	return true


func _advance_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_phase = Phase.ACTIVE
			_phase_time_left += attack.active_time
			hitbox.activate()
		Phase.ACTIVE:
			_phase = Phase.RECOVERY
			_phase_time_left += attack.recovery_time
			hitbox.deactivate()
		Phase.RECOVERY:
			_phase = Phase.READY
			_phase_time_left = 0.0
			attack_finished.emit()
