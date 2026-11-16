extends SceneTree
## Teste automatizado da HUD de vida (PlayerHud + HeartsDisplay) e da GameOverScreen:
## corações cheios/vazios conforme a vida (atualização imediata no dano, na cura e na
## restauração), formas de encontrar a vida (grupo, target, health), corações provisórios por
## código e com texturas, HUD fixa na tela (CanvasLayer); tela "Você caiu" com o jogo pausado,
## atraso de entrada, foco no botão, ui_accept (teclado e controle) e retry_requested.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/ui/player_hud_test.gd

const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const HUD_PATH: String = "res://ui/hud/player_hud.tscn"
const GAME_OVER_PATH: String = "res://ui/menus/game_over_screen.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== HUD de vida e Game Over")
	await process_frame
	await _test_hud_with_terra()
	await _test_hud_sources()
	_test_hearts_display()
	await _test_game_over()
	_finish()


func _test_hud_with_terra() -> void:
	print("-- HUD ligada à Terra pelo grupo player")
	var holder := Node2D.new()
	root.add_child(holder)
	var terra := (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	holder.add_child(terra)
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as PlayerHud
	holder.add_child(hud)
	await process_frame
	await process_frame
	var hearts := hud.get_hearts()
	_check(terra.is_in_group(&"player"), "Terra está no grupo player")
	_check(hud.get_bound_health() == terra.get_health(), "HUD encontrou a vida da Terra pelo grupo (sem export)")
	_check(hearts.get_maximum() == 5 and hearts.get_full_count() == 5 and hearts.get_empty_count() == 0, "começa com 5 corações cheios")
	_check(hud is CanvasLayer and hud.layer > 0 and hearts.position == Vector2(8, 8), "HUD em CanvasLayer (fixa na tela), corações a 8 px do canto superior esquerdo")
	var hb := terra.get_hurtbox()
	hb.receive_hit(1)
	_check(hearts.get_full_count() == 4 and hearts.get_empty_count() == 1, "dano 1: 4 cheios e 1 vazio, na hora (sem esperar quadro)")
	terra.get_health().take_damage(2)
	_check(hearts.get_full_count() == 2 and hearts.get_empty_count() == 3, "dano 2: 2 cheios e 3 vazios")
	terra.get_health().heal(1)
	_check(hearts.get_full_count() == 3 and hearts.get_empty_count() == 2, "cura 1: 3 cheios e 2 vazios")
	terra.get_health().heal(9)
	_check(hearts.get_full_count() == 5 and hearts.get_empty_count() == 0, "cura além do máximo: 5 cheios (nunca mais que o máximo)")
	terra.get_health().take_damage(99)
	_check(hearts.get_full_count() == 0 and hearts.get_empty_count() == 5, "morte: 0 cheios e 5 vazios (nunca negativo)")
	terra.revive()
	_check(hearts.get_full_count() == 5 and hearts.get_empty_count() == 0, "revive: 5 corações cheios de novo")
	holder.queue_free()
	await process_frame


func _test_hud_sources() -> void:
	print("-- Outras fontes de vida (reuso com outros personagens)")
	var holder := Node.new()
	root.add_child(holder)
	var hc := HealthComponent.new()
	hc.max_health = 3
	holder.add_child(hc)
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as PlayerHud
	hud.health = hc
	holder.add_child(hud)
	await process_frame
	_check(hud.get_bound_health() == hc and hud.get_hearts().get_maximum() == 3 and hud.get_hearts().get_full_count() == 3, "health exportado direto: 3 corações (máximo vem do componente)")
	var other := HealthComponent.new()
	other.max_health = 7
	holder.add_child(other)
	await process_frame
	other.take_damage(2)
	await hud.bind_health(other)
	_check(hud.get_hearts().get_maximum() == 7 and hud.get_hearts().get_full_count() == 5, "bind_health troca de personagem: 5 de 7")
	hc.take_damage(1)
	_check(hud.get_hearts().get_full_count() == 5, "a vida anterior deixa de atualizar a HUD")
	holder.queue_free()
	await process_frame


func _test_hearts_display() -> void:
	print("-- Corações (desenho provisório e texturas)")
	var hd := HeartsDisplay.new()
	root.add_child(hd)
	var rows_ok := true
	for row in HeartsDisplay.HEART_PATTERN:
		rows_ok = rows_ok and row.length() == HeartsDisplay.HEART_PATTERN[0].length()
	_check(rows_ok and hd.get_heart_size() == Vector2i(11, 10), "coração provisório em pixel art de 11x10 (todas as linhas do desenho com a mesma largura)")
	hd.set_values(5, 5)
	_check(hd.size == Vector2(5 * 11 + 4 * 2, 10), "5 corações com 2 px de espaço: 63x10 px")
	hd.set_values(-3, 5)
	_check(hd.get_full_count() == 0 and hd.get_empty_count() == 5, "valores fora do intervalo são limitados (nunca negativo)")
	hd.set_values(9, 5)
	_check(hd.get_full_count() == 5 and hd.get_empty_count() == 0, "valores acima do máximo são limitados")
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	hd.full_texture = ImageTexture.create_from_image(img)
	hd.empty_texture = ImageTexture.create_from_image(img)
	_check(hd.get_heart_size() == Vector2i(16, 16) and hd.size == Vector2(5 * 16 + 4 * 2, 16), "com texturas, usa o tamanho delas (preparado para os sprites)")
	hd.queue_free()


func _test_game_over() -> void:
	print("-- Tela de Game Over")
	var go := (load(GAME_OVER_PATH) as PackedScene).instantiate() as GameOverScreen
	root.add_child(go)
	await process_frame
	var retries := [0]
	go.retry_requested.connect(func() -> void: retries[0] += 1)
	var button := go.get_retry_button()
	_check(not go.is_open() and go.process_mode == Node.PROCESS_MODE_ALWAYS, "começa fechada e roda com o jogo pausado (process_mode ALWAYS)")
	_check((go.get_node("Root/Panel/Title") as Label).text == "Você caiu" and button.text == "Tentar novamente", "textos: \"Você caiu\" e \"Tentar novamente\"")
	# O ui_accept padrão da Godot 4.7 não tem botão de controle: a tela confirma também com jump.
	_check(_action_has_key(&"ui_accept", KEY_ENTER) and go.confirm_actions.has(&"jump") and _action_has_joy_button(&"jump", JOY_BUTTON_A), "teclado: ui_accept (Enter); controle: botão A pela ação jump (confirm_actions)")
	paused = true
	go.open()
	await process_frame
	_check(go.is_open() and not go.is_accepting_input() and button.disabled, "abre com o jogo pausado e ignora entrada no início (atraso)")
	_press_ui_accept()
	await process_frame
	_check(retries[0] == 0, "ui_accept durante o atraso não reinicia")
	# Espera em tempo (não em quadros): no modo headless os quadros correm mais rápido que 60/s.
	await create_timer(go.input_delay + 0.1, true).timeout
	_check(go.is_accepting_input() and not button.disabled and button.has_focus(), "depois do atraso (contado mesmo pausado): botão habilitado e com foco")
	_press_ui_accept()
	await process_frame
	await process_frame
	_check(retries[0] == 1, "ui_accept no botão emite retry_requested uma vez")
	_press_ui_accept()
	await process_frame
	_check(retries[0] == 1, "não emite de novo até ser reaberta")
	go.close()
	_check(not go.is_open(), "close() esconde a tela")
	# Controle: botão A (evento de joypad real) confirma depois do atraso.
	go.open()
	_press_joy_a()
	await process_frame
	_check(retries[0] == 1, "botão A durante o atraso não reinicia")
	# Espera em tempo (não em quadros): no modo headless os quadros correm mais rápido que 60/s.
	await create_timer(go.input_delay + 0.1, true).timeout
	_press_joy_a()
	await process_frame
	await process_frame
	_check(retries[0] == 2, "botão A do controle emite retry_requested (com o jogo pausado)")
	go.close()
	paused = false
	go.queue_free()
	await process_frame


func _press_ui_accept() -> void:
	var down := InputEventAction.new()
	down.action = &"ui_accept"
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = &"ui_accept"
	up.pressed = false
	Input.parse_input_event(up)


func _press_joy_a() -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = JOY_BUTTON_A
		e.pressed = pressed
		Input.parse_input_event(e)


func _action_has_key(action: StringName, key: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and ((e as InputEventKey).keycode == key or (e as InputEventKey).physical_keycode == key):
			return true
	return false


func _action_has_joy_button(action: StringName, button: JoyButton) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _finish() -> void:
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)
