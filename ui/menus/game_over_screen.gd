class_name GameOverScreen
extends CanvasLayer
## Tela "Você caiu" com a opção "Tentar novamente". Só apresenta a morte: open()/close() e o
## sinal retry_requested; quem a usa (controlador de morte da cena) decide como reiniciar.
## Funciona com o jogo pausado (process_mode = ALWAYS) e com teclado ou controle: o botão
## recebe o foco e responde a ui_accept (Enter/Espaço); como o ui_accept padrão da Godot não
## tem botão de controle, a tela também confirma com confirm_actions (padrão: jump = botão A,
## Espaço, K, Z), sem mexer no Input Map.

signal retry_requested

## Tempo sem aceitar o botão depois de abrir (evita confirmar sem querer com o botão do pulo
## ainda pressionado). Conta mesmo com o jogo pausado.
@export_range(0.0, 2.0, 0.05, "suffix:s") var input_delay: float = 0.4
## Ações do jogo que também confirmam "Tentar novamente" (além do ui_accept no botão).
@export var confirm_actions: Array[StringName] = [&"jump"]

var _accepting: bool = false
var _open_id: int = 0

@onready var _retry_button: Button = $Root/Panel/RetryButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_retry_button.pressed.connect(_on_retry_pressed)


func open() -> void:
	_open_id += 1
	var id: int = _open_id
	visible = true
	_accepting = false
	_retry_button.disabled = true
	if input_delay > 0.0:
		await get_tree().create_timer(input_delay, true).timeout
	if id != _open_id or not visible:
		return
	_accepting = true
	_retry_button.disabled = false
	_retry_button.grab_focus()


func close() -> void:
	_open_id += 1
	visible = false
	_accepting = false
	_retry_button.disabled = true


func is_open() -> bool:
	return visible


func is_accepting_input() -> bool:
	return _accepting


func get_retry_button() -> Button:
	return _retry_button


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _accepting:
		return
	for action in confirm_actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			_on_retry_pressed()
			return


func _on_retry_pressed() -> void:
	if not _accepting:
		return
	_accepting = false
	_retry_button.disabled = true
	retry_requested.emit()
