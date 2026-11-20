extends SceneTree
## Teste automatizado da interação com os Altares Elementais (Etapa 8.2), na cena de teste
## tests/checkpoints/altar_sandbox.tscn (Game real + sala herdada da Sala 02 com dois altares):
## área (só personagens jogáveis), nada ao entrar, pressionamento novo (sem segurar, sem eco, sem
## aperto anterior à entrada), teclado (E, ↑) e controle (B) pelo Input Map, W (só move_up) e ↑
## no ar ignorados, vida restaurada e HUD, troca do checkpoint atual, tentativa e inimigos
## intactos, bloqueio com a Terra morta, no Game Over, na transição e no reinício, indicação
## "E — Interagir" e estado visual provisório.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/checkpoint_interaction_test.gd

const SANDBOX_PATH: String = "res://tests/checkpoints/altar_sandbox.tscn"
const SANDBOX_ROOM: String = "res://tests/checkpoints/altar_sandbox_room.tscn"
const WEST: StringName = &"sandbox_altar_west"
const EAST: StringName = &"sandbox_altar_east"
const WEST_X: float = 136.0
const EAST_X: float = 904.0
const FLOOR_Y: float = 320.0
## Fora das duas áreas, no chão plano da chegada.
const OUTSIDE_X: float = 72.0
const FRAGMENT_ID: StringName = &"gallery_fragment_01"
const Visuals := preload("res://world/levels/_shared/altar_placeholder_visuals.gd")

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
## [checkpoint_id, first_time] de cada activated emitido pelos altares da sala atual.
var _requests: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Checkpoints: interação e recuperação de vida (Etapa 8.2)")
	await process_frame
	_test_input_map()
	await _new_game()
	await _test_area_detection()
	await _test_press_outside()
	await _test_first_activation()
	await _test_hold_and_echo()
	await _test_pressed_before_entering()
	await _test_devices_and_up_arrow()
	await _test_other_altar()
	await _test_attempt_and_enemies()
	await _test_transition_blocks()
	await _test_death_game_over_retry()
	_finish()


func _finish() -> void:
	_release_all()
	if _game != null:
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_input_map() -> void:
	print("-- Input Map (sem alterações)")
	_check(InputMap.has_action(ElementalAltar.INTERACT_ACTION), "ação interact existe")
	_check(_matches(_key_event(KEY_E, true)) and _matches(_key_event(KEY_UP, true)) and _matches(_pad_event(JOY_BUTTON_B, true)),
		"interact: E, ↑ e botão B do controle")
	_check(not _matches(_key_event(KEY_W, true)) and not _matches(_pad_event(JOY_BUTTON_A, true)) and not _matches(_key_event(KEY_K, true)),
		"W, A do controle e K (pulo) não são interact")


func _test_area_detection() -> void:
	print("-- Área de interação")
	var west: ElementalAltar = _altar(WEST)
	var area: Area2D = west.get_node(^"InteractionArea")
	_check(area.collision_layer == 0 and area.collision_mask == 4 and area.monitoring and not area.monitorable,
		"zona de gatilho: sem layer, mask player (4), monitoring ligado, monitorable desligado")
	_check(not west.has_player_in_range() and not west.is_prompt_visible(), "Terra longe: fora da área, sem indicação")
	# Outros corpos: um na layer player que não é personagem e um na layer enemies.
	var fake_player: CharacterBody2D = _body(1 << 2, Vector2(WEST_X, FLOOR_Y - 20))
	var fake_enemy: CharacterBody2D = _body(1 << 3, Vector2(WEST_X, FLOOR_Y - 20))
	await _wait(4)
	_check(not west.has_player_in_range() and not west.is_prompt_visible() and _requests.is_empty(),
		"corpos que não são personagem jogável (layer player ou enemies) são ignorados")
	fake_player.queue_free()
	fake_enemy.queue_free()
	await _place(WEST_X)
	_check(west.has_player_in_range() and west.can_interact(), "Terra dentro da área, no chão, viva e no controle")
	_check(west.is_prompt_visible(), "indicação \"E — Interagir\" visível")
	_check((west.get_node(^"Prompt") as Label).text == "E — Interagir", "texto da indicação")
	_check(_requests.is_empty() and not _game.call("has_current_checkpoint"), "entrar na área não ativa nada")
	await _wait(30)
	_check(_requests.is_empty(), "ficar parado na área por 30 ticks também não ativa")
	await _place(OUTSIDE_X)
	_check(not west.has_player_in_range() and not west.is_prompt_visible(), "ao sair da área, a indicação some")


func _test_press_outside() -> void:
	print("-- Interação fora da área")
	await _tap_key(KEY_E)
	_check(_requests.is_empty() and not _game.call("has_current_checkpoint"), "E fora da área é ignorado")


func _test_first_activation() -> void:
	print("-- Primeira ativação: registro, vida e HUD")
	var health: HealthComponent = _terra().get_health()
	health.take_damage(2)
	await _wait(40)  # passa a invulnerabilidade do golpe (não interfere na interação)
	_check(health.current_health == 3 and _hud_full() == 3, "Terra ferida: 3 de vida, HUD com 3 corações")
	await _place(WEST_X)
	var west: ElementalAltar = _altar(WEST)
	_check(_gem(west) == Visuals.GEM_INACTIVE, "altar inativo: gema apagada")
	await _tap_key(KEY_E)
	_check(_requests == [[WEST, true]], "um aperto de E: uma ativação, first_time = true (%s)" % [_requests])
	_check(_game.call("is_current_checkpoint", SANDBOX_ROOM, WEST) and _game.call("get_activated_checkpoints", SANDBOX_ROOM) == [WEST],
		"registrado e atual")
	_check(health.current_health == 5 and health.current_health == health.max_health, "vida restaurada para 5")
	_check(_hud_full() == 5 and _hud_empty() == 0, "HUD atualizada pelo health_changed (5 corações cheios)")
	_check(west.is_activated() and west.is_current() and _gem(west) == Visuals.GEM_CURRENT, "estado visual: atual (gema clara)")
	_check(west.is_prompt_visible(), "a indicação continua enquanto a Terra estiver na área")


func _test_hold_and_echo() -> void:
	print("-- Segurar e repetição do teclado")
	_requests.clear()
	await _key(KEY_E, true)
	_check(_requests.size() == 1, "aperto: uma ativação")
	for i: int in 3:
		await _key(KEY_E, true, true)  # eco (repetição automática do teclado)
	await _wait(30)
	_check(_requests.size() == 1, "segurando (com eco) por 30 ticks: nenhuma ativação extra")
	await _key(KEY_E, false)
	_check(_requests.size() == 1 and _game.call("get_activated_checkpoints", SANDBOX_ROOM) == [WEST],
		"soltar não ativa; registro sem duplicatas")


func _test_pressed_before_entering() -> void:
	print("-- Botão apertado antes de entrar")
	await _place(OUTSIDE_X)
	_requests.clear()
	var health: HealthComponent = _terra().get_health()
	health.take_damage(1)
	await _key(KEY_E, true)
	_check(_requests.is_empty(), "apertado fora da área: nada")
	await _place(WEST_X)
	await _wait(20)
	_check(_requests.is_empty() and health.current_health == 4, "entrou com E segurado: nada (vida continua 4)")
	await _key(KEY_E, false)
	await _tap_key(KEY_E)
	_check(_requests == [[WEST, false]], "novo aperto dentro da área: ativação repetida (first_time = false)")
	_check(health.current_health == 5 and _hud_full() == 5, "interação repetida também restaura a vida")
	_check(_game.call("get_activated_checkpoints", SANDBOX_ROOM) == [WEST] and _game.call("is_current_checkpoint", SANDBOX_ROOM, WEST),
		"repetida: continua atual, sem duplicar o registro")


func _test_devices_and_up_arrow() -> void:
	print("-- Teclado (E, ↑), controle (B), W e ↑ no ar")
	_requests.clear()
	await _tap_key(KEY_UP)
	_check(_requests.size() == 1, "↑ (esquema B) no chão, dentro da área: ativa")
	await _tap_pad(JOY_BUTTON_B)
	_check(_requests.size() == 2, "botão B do controle: ativa")
	await _tap_key(KEY_W)
	await _tap_pad(JOY_BUTTON_A)
	_check(_requests.size() == 2, "W (só move_up) e A do controle (pulo) não ativam")
	# ↑ no ar: impulso para cima dentro da área.
	var terra: PlayerCharacter = _terra()
	var west: ElementalAltar = _altar(WEST)
	terra.velocity = Vector2(0, -200)
	var airborne: bool = false
	for i: int in 10:
		await physics_frame
		if not terra.is_on_floor() and west.has_player_in_range():
			airborne = true
			break
	_check(airborne and not west.can_interact() and not west.is_prompt_visible(), "no ar e na área: sem interação e sem indicação")
	await _tap_key(KEY_UP)
	_check(_requests.size() == 2 and not terra.is_on_floor(), "↑ no ar não ativa (pulo/plataforma sobre o altar)")
	for i: int in 120:
		await physics_frame
		if terra.is_on_floor():
			break
	await _wait(2)
	await _tap_key(KEY_UP)
	_check(_requests.size() == 3, "de volta ao chão, ↑ ativa")


func _test_other_altar() -> void:
	print("-- Outro altar")
	_requests.clear()
	await _place(EAST_X)
	var east: ElementalAltar = _altar(EAST)
	var west: ElementalAltar = _altar(WEST)
	_check(east.is_prompt_visible() and not west.is_prompt_visible(), "só o altar próximo mostra a indicação")
	await _tap_key(KEY_E)
	_check(_requests == [[EAST, true]], "um aperto ativa só o altar leste")
	_check(_game.call("is_current_checkpoint", SANDBOX_ROOM, EAST) and not _game.call("is_current_checkpoint", SANDBOX_ROOM, WEST),
		"o checkpoint atual passou para o altar leste")
	_check(_game.call("get_activated_checkpoints", SANDBOX_ROOM) == [WEST, EAST] and west.is_activated(),
		"o altar anterior continua registrado")
	_check(_gem(east) == Visuals.GEM_CURRENT and _gem(west) == Visuals.GEM_ACTIVATED, "visual: leste atual, oeste ativado (âmbar escuro)")


func _test_attempt_and_enemies() -> void:
	print("-- Tentativa e inimigos")
	var fragment: Enemy = _room().get_persistent_enemies().get(FRAGMENT_ID)
	var fragment_health: HealthComponent = fragment.get_node(^"HealthComponent")
	fragment_health.take_damage(fragment_health.current_health)
	await _wait(2)
	var attempt: int = _game.call("get_attempt")
	_check(_game.call("get_defeated_enemies", SANDBOX_ROOM) == [FRAGMENT_ID], "Fragmento derrotado e registrado")
	_requests.clear()
	await _tap_key(KEY_E)
	await _tap_pad(JOY_BUTTON_B)
	_check(_requests.size() == 2, "duas interações")
	_check(_game.call("get_attempt") == attempt, "a interação não reinicia a tentativa (%d)" % attempt)
	_check(_game.call("get_defeated_enemies", SANDBOX_ROOM) == [FRAGMENT_ID] and _game.call("get_defeated_enemy_scope", SANDBOX_ROOM, FRAGMENT_ID) == Room.SCOPE_ATTEMPT,
		"a interação não restaura inimigos")
	_check(_count_enemies() <= 1 and (fragment == null or not is_instance_valid(fragment) or fragment.get_state() == LivingFragment.State.DEAD),
		"nenhum inimigo novo na sala")


func _test_transition_blocks() -> void:
	print("-- Transição bloqueia a interação")
	await _place(EAST_X)
	var health: HealthComponent = _terra().get_health()
	health.take_damage(1)
	await _wait(40)
	var east: ElementalAltar = _altar(EAST)
	_requests.clear()
	_check(_game.call("request_transition", SANDBOX_ROOM, &"west"), "transição pedida com a Terra na área")
	await process_frame
	await physics_frame
	_check(_game.call("is_transitioning") and not east.can_interact() and not east.is_prompt_visible(),
		"durante a transição: sem interação e sem indicação")
	await _tap_key(KEY_E)
	_check(_requests.is_empty(), "E durante a transição é ignorado")
	east.activate()  # mesmo um pedido direto é recusado pela Game
	_check(health.current_health == 4, "pedido direto durante a transição: recusado, sem cura")
	await _game.transition_finished
	await _wait(3)
	var west: ElementalAltar = _altar(WEST)
	_check(west.is_activated() and not west.is_current() and _altar(EAST).is_current() and _gem(_altar(EAST)) == Visuals.GEM_CURRENT,
		"sala recriada: estado e visual vindos do registro")
	health.restore_full()


func _test_death_game_over_retry() -> void:
	print("-- Terra morta, Game Over e reinício")
	await _place(WEST_X)
	var west: ElementalAltar = _altar(WEST)
	var terra: PlayerCharacter = _terra()
	_requests.clear()
	terra.get_health().take_damage(terra.get_health().current_health)
	# process_frame vem antes dos _process dos nós: o segundo garante que o altar já atualizou a indicação.
	await process_frame
	await process_frame
	_check(terra.is_dead() and not west.can_interact() and not west.is_prompt_visible(), "Terra morta: sem interação e sem indicação")
	await _tap_key(KEY_E)
	_check(_requests.is_empty() and terra.get_health().current_health == 0, "E com a Terra morta: ignorado, sem cura")
	await terra.death_finished
	await process_frame
	_check(_game.call("is_game_over") and paused, "Game Over aberto, mundo pausado")
	await _tap_key(KEY_E)
	await _tap_pad(JOY_BUTTON_B)
	_check(_requests.is_empty() and terra.get_health().current_health == 0 and _game.call("is_game_over"),
		"E e B no Game Over: ignorados (altar pausado), sem cura e sem confirmar o retry")
	west.activate()
	_check(_game.call("is_current_checkpoint", SANDBOX_ROOM, EAST) and terra.get_health().current_health == 0,
		"pedido direto no Game Over: recusado")
	var screen: GameOverScreen = _game.call("get_game_over_screen")
	screen.retry_requested.emit()
	await process_frame
	_check(_game.call("is_retrying"), "reinício em andamento")
	var retry_altar: ElementalAltar = _altar(WEST)
	await _tap_key(KEY_E)
	retry_altar.activate()
	_check(_game.call("is_current_checkpoint", SANDBOX_ROOM, EAST) and _game.call("get_activated_checkpoints", SANDBOX_ROOM) == [WEST, EAST],
		"durante o reinício: interação e pedido direto recusados")
	await _game.attempt_restarted
	await _wait(3)
	_check(not paused and not terra.is_dead() and _game.call("is_current_checkpoint", SANDBOX_ROOM, EAST),
		"depois do reinício: Terra viva, checkpoint atual mantido")
	await _place(WEST_X)
	_requests.clear()
	await _tap_key(KEY_E)
	_check(_requests == [[WEST, false]] and _game.call("is_current_checkpoint", SANDBOX_ROOM, WEST),
		"depois do reinício, a interação volta a funcionar")


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game() -> void:
	_game = (load(SANDBOX_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	_game.room_changed.connect(_on_room_changed)
	_on_room_changed(_room())
	await _wait(5)


func _on_room_changed(room: Room) -> void:
	for altar: ElementalAltar in room.get_checkpoints().values():
		altar.activated.connect(func(emitter: ElementalAltar, first_time: bool) -> void:
			_requests.append([emitter.checkpoint_id, first_time]))


func _terra() -> PlayerCharacter:
	return _game.call("get_terra") as PlayerCharacter


func _room() -> Room:
	return _game.call("get_room") as Room


func _altar(id: StringName) -> ElementalAltar:
	return _room().get_checkpoint(id)


func _gem(altar: ElementalAltar) -> Color:
	return altar.get_node(^"Visuals").call("get_gem_color")


func _hud_full() -> int:
	return (_game.call("get_hud") as PlayerHud).get_hearts().get_full_count()


func _hud_empty() -> int:
	return (_game.call("get_hud") as PlayerHud).get_hearts().get_empty_count()


func _count_enemies() -> int:
	return _room().get_node(^"Enemies").get_child_count()


## Terra parada no chão em x (pés em FLOOR_Y); espera a área e o chão atualizarem.
func _place(x: float) -> void:
	var terra: PlayerCharacter = _terra()
	terra.global_position = Vector2(x, FLOOR_Y)
	terra.velocity = Vector2.ZERO
	await _wait(4)


func _body(layer: int, at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(16, 32)
	shape.shape = rect
	body.add_child(shape)
	body.global_position = at
	_room().add_child(body)
	return body


func _key_event(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _pad_event(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	return event


func _matches(event: InputEvent) -> bool:
	return event.is_action(ElementalAltar.INTERACT_ACTION)


## Envia o evento pelo caminho real (Input → viewport → _unhandled_input).
func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	await physics_frame


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	await _send(_key_event(code, pressed, echo))


func _tap_key(code: Key) -> void:
	await _key(code, true)
	await _key(code, false)


func _tap_pad(button: JoyButton) -> void:
	await _send(_pad_event(button, true))
	await _send(_pad_event(button, false))


func _release_all() -> void:
	for code: Key in [KEY_E, KEY_UP, KEY_W]:
		Input.parse_input_event(_key_event(code, false))
	Input.parse_input_event(_pad_event(JOY_BUTTON_B, false))


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1
