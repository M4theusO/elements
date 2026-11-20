extends SceneTree
## Teste automatizado da segurança das transições (Etapa 2D de Vida/HUD/Morte):
## Hurtbox da Terra bloqueada do pedido da transição até a volta do controle (fade de saída,
## troca e fade de entrada), sem mexer na invulnerabilidade normal; morte antes da troca
## (transição cancelada, sala de origem continua), morte depois da troca (sala nova), Game Over
## e renascimento na sala e entrada corretas, sem transição duplicada nem _transitioning preso;
## death_finished durante a transição; Game removida (e recolocada) durante transição e retry.
##
## Esperas por sinais e estado (transition_finished, room_changed, death_finished,
## attempt_restarted, alfa do fade), não por tempos fixos.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/transition_safety_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_01: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const MAX_FRAMES: int = 600

var _failures: int = 0
var _checks: int = 0
var _game: Node2D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Segurança das transições (Etapa 2D)")
	await process_frame
	await _test_hurtbox_block_api()
	await _test_damage_blocked_during_transition()
	await _test_invulnerability_preserved()
	await _test_fatal_hit_then_request()
	await _test_death_before_swap_at_start()
	await _test_death_during_fade_out()
	await _test_death_after_swap()
	await _test_death_finished_during_transition()
	await _test_game_removed_during_transition()
	await _test_game_removed_during_retry()
	await _test_game_freed_during_transition()
	_finish()


func _finish() -> void:
	paused = false
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_hurtbox_block_api() -> void:
	print("-- Hurtbox.set_blocked")
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 5
	var hurtbox: Hurtbox = Hurtbox.new()
	hurtbox.health = health
	hurtbox.invulnerability_time = 0.5
	root.add_child(health)
	root.add_child(hurtbox)
	await physics_frame
	var received: Array[int] = [0]
	hurtbox.hit_received.connect(func(_d: int) -> void: received[0] += 1)
	_check(not hurtbox.is_blocked(), "começa desbloqueada")
	hurtbox.set_blocked(true)
	hurtbox.receive_hit(1)
	_check(health.current_health == 5 and received[0] == 0 and not hurtbox.is_invulnerable(),
		"bloqueada: golpe ignorado, sem hit_received e sem iniciar invulnerabilidade")
	hurtbox.set_blocked(false)
	hurtbox.receive_hit(1)
	_check(health.current_health == 4 and received[0] == 1 and is_equal_approx(hurtbox.get_invulnerability_left(), 0.5),
		"liberada: golpe acerta e inicia a invulnerabilidade normal (0,5 s)")
	hurtbox.set_blocked(true)
	var left: float = hurtbox.get_invulnerability_left()
	for i: int in 6:
		await physics_frame
	_check(hurtbox.get_invulnerability_left() < left and hurtbox.get_invulnerability_left() > 0.0,
		"o bloqueio não congela nem zera o contador de invulnerabilidade (%.3f -> %.3f)" % [left, hurtbox.get_invulnerability_left()])
	hurtbox.set_blocked(false)
	hurtbox.free()
	health.free()


func _test_damage_blocked_during_transition() -> void:
	print("-- Dano bloqueado durante a transição")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	var hurtbox: Hurtbox = terra.get_hurtbox()
	var health: HealthComponent = terra.get_health()
	var fade: ColorRect = _fade()
	var obs: Dictionary = {"swap_blocked": false, "swap_hp": -1, "swaps": 0}
	var on_swap: Callable = func(_room: Room) -> void:
		obs.swaps += 1
		obs.swap_blocked = hurtbox.is_blocked()
		hurtbox.receive_hit(1)
		obs.swap_hp = health.current_health
	_game.connect("room_changed", on_swap)
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida")
	_check(hurtbox.is_blocked(), "bloqueio ativo no próprio pedido (antes do _run_transition adiado)")
	hurtbox.receive_hit(5)
	_check(health.current_health == 5 and not terra.is_dead(), "golpe no mesmo instante do pedido ignorado (5 de vida)")
	_check(not _game.call("request_transition", ROOM_01, &"east"), "segundo pedido durante a transição recusado")
	# Fade de saída: espera o alfa começar a subir, com a sala de origem ainda atual.
	var origin: Room = _game.call("get_room") as Room
	var hit_out: bool = false
	for i: int in MAX_FRAMES:
		if fade.modulate.a > 0.0 and _game.call("get_room") == origin:
			hurtbox.receive_hit(5)
			hit_out = true
			break
		await process_frame
	_check(hit_out and health.current_health == 5, "golpe durante o fade de saída ignorado")
	# Fade de entrada: depois da troca, ainda em transição.
	var hit_in: bool = false
	for i: int in MAX_FRAMES:
		if obs.swaps > 0 and _game.call("is_transitioning") and fade.modulate.a < 1.0:
			_check(hurtbox.is_blocked(), "bloqueio ativo durante o fade de entrada")
			hurtbox.receive_hit(5)
			hit_in = true
			break
		await process_frame
	_check(obs.swaps == 1 and obs.swap_blocked and obs.swap_hp == 5, "golpe no momento da troca ignorado (bloqueada, 5 de vida)")
	_check(hit_in and health.current_health == 5, "golpe durante o fade de entrada ignorado")
	await _wait_transition_end(finished)
	_check(finished == [true] and not _game.call("is_transitioning"), "transição concluída uma vez (transition_finished(true))")
	_check(not hurtbox.is_blocked() and terra.process_mode == Node.PROCESS_MODE_INHERIT, "proteção encerrada e controle devolvido")
	_check(not hurtbox.is_invulnerable(), "sem invulnerabilidade sobrando dos golpes bloqueados")
	hurtbox.receive_hit(1)
	_check(health.current_health == 4, "depois da transição, o golpe acerta (5 -> 4)")
	_check(obs.swaps == 1 and _game.call("get_room_path") == ROOM_02, "uma única troca, para a Sala 02")
	_game.disconnect("room_changed", on_swap)
	_game.disconnect("transition_finished", on_finished)


func _test_invulnerability_preserved() -> void:
	print("-- Invulnerabilidade normal preservada")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	var hurtbox: Hurtbox = terra.get_hurtbox()
	hurtbox.receive_hit(1)
	var left: float = hurtbox.get_invulnerability_left()
	_check(terra.get_health().current_health == 4 and left > 0.5, "golpe normal: 4 de vida e %.3f s de invulnerabilidade" % left)
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	var at_finish: Array[float] = [-1.0]
	_game.connect("transition_finished", func(_s: bool) -> void: at_finish[0] = hurtbox.get_invulnerability_left(), CONNECT_ONE_SHOT)
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida logo depois do golpe")
	await _wait_transition_end(finished)
	_check(is_equal_approx(at_finish[0], left), "ao devolver o controle, a invulnerabilidade é a mesma (%.3f s): nem reduzida, nem reiniciada" % at_finish[0])
	var ticks: int = 0
	while hurtbox.is_invulnerable() and ticks < 200:
		await physics_frame
		ticks += 1
	var expected: int = roundi(left * Engine.physics_ticks_per_second)
	_check(absi(ticks - expected) <= 1, "e termina normalmente depois (%d ticks, ~%d)" % [ticks, expected])
	_check(not hurtbox.is_blocked(), "sem bloqueio sobrando")
	_game.disconnect("transition_finished", on_finished)


func _test_fatal_hit_then_request() -> void:
	print("-- Golpe fatal imediatamente antes do pedido")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	terra.get_health().take_damage(4)
	terra.get_hurtbox().receive_hit(1)
	_check(terra.is_dead(), "Terra morta pelo golpe")
	_check(not _game.call("request_transition", ROOM_02, &"west") and not _game.call("is_transitioning")
		and not terra.get_hurtbox().is_blocked(), "pedido logo depois recusado; nada bloqueado nem em transição")
	await _game_over_and_retry(ROOM_01)


func _test_death_before_swap_at_start() -> void:
	print("-- Morte entre o pedido e o início da troca")
	await _new_game()
	await _go(ROOM_02, &"west")
	var terra: PlayerCharacter = _terra()
	var origin: Room = _game.call("get_room") as Room
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	var swaps: Array[int] = [0]
	var on_swap: Callable = func(_r: Room) -> void: swaps[0] += 1
	_game.connect("room_changed", on_swap)
	_check(_game.call("request_transition", ROOM_01, &"east"), "transição pedida")
	# Dano que não passa pela Hurtbox (bloqueada), antes do _run_transition adiado.
	terra.get_health().take_damage(99)
	_check(terra.is_dead(), "Terra morta antes de a troca começar")
	await _wait_transition_end(finished)
	_check(finished == [false] and swaps[0] == 0, "transição cancelada (transition_finished(false)), sem troca")
	_check(_game.call("get_room") == origin and _game.call("get_room_path") == ROOM_02
		and _game.call("get_arrival_entrance") == &"west", "a Sala 02 continua a atual, entrada de chegada west")
	_check(not _game.call("is_transitioning") and not terra.get_hurtbox().is_blocked()
		and terra.process_mode == Node.PROCESS_MODE_INHERIT, "nada preso: sem transição, sem bloqueio, Terra processando")
	_check(_game.get_node("RoomSlot").get_child_count() == 1, "só uma sala no RoomSlot")
	_game.disconnect("transition_finished", on_finished)
	_game.disconnect("room_changed", on_swap)
	await _game_over_and_retry(ROOM_02)


func _test_death_during_fade_out() -> void:
	print("-- Morte durante o fade de saída (antes da troca)")
	await _new_game()
	await _go(ROOM_02, &"west")
	var terra: PlayerCharacter = _terra()
	var origin: Room = _game.call("get_room") as Room
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	_check(_game.call("request_transition", ROOM_01, &"east"), "transição pedida")
	var killed: bool = false
	for i: int in MAX_FRAMES:
		if _fade().modulate.a > 0.0 and _fade().modulate.a < 1.0:
			terra.get_health().take_damage(99)
			killed = true
			break
		await process_frame
	_check(killed and terra.is_dead(), "Terra morta no meio do escurecer (dano direto)")
	await _wait_transition_end(finished)
	_check(finished == [false] and _game.call("get_room") == origin and _game.call("get_room_path") == ROOM_02,
		"transição cancelada; a Sala 02 continua a atual")
	_check(is_zero_approx(_fade().modulate.a) and not _fade().visible, "tela clara de novo")
	_check(not _game.call("is_transitioning") and not terra.get_hurtbox().is_blocked()
		and terra.process_mode == Node.PROCESS_MODE_INHERIT, "nada preso depois do cancelamento")
	_check(_game.get_node("RoomSlot").get_child_count() == 1, "só uma sala no RoomSlot (destino liberado)")
	_game.disconnect("transition_finished", on_finished)
	await _game_over_and_retry(ROOM_02)


func _test_death_after_swap() -> void:
	print("-- Morte logo depois da troca efetiva")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	var swaps: Array[int] = [0]
	var on_swap: Callable = func(_r: Room) -> void:
		swaps[0] += 1
		if swaps[0] == 1:
			terra.get_health().take_damage(99)
	_game.connect("room_changed", on_swap)
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida")
	await _wait_transition_end(finished)
	_check(terra.is_dead() and finished == [true] and swaps[0] == 1 and _game.call("get_room_path") == ROOM_02,
		"Terra morta na troca; transição concluída para a Sala 02, uma única troca")
	_check(not _game.call("is_transitioning") and not terra.get_hurtbox().is_blocked(), "nada preso depois da transição")
	_check(not _game.call("request_transition", ROOM_01, &"east"), "nenhuma nova transição com a Terra morta")
	await _game_over_and_retry(ROOM_02)
	_check(swaps[0] == 2, "só a troca do reinício (para a Sala 01) aconteceu depois (sem troca involuntária) (%d)" % swaps[0])
	_game.disconnect("transition_finished", on_finished)
	_game.disconnect("room_changed", on_swap)


func _test_death_finished_during_transition() -> void:
	print("-- death_finished durante a transição")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	var at_finish: Array[bool] = [true]
	_game.connect("transition_finished", func(_s: bool) -> void: at_finish[0] = _game.call("is_game_over") or paused, CONNECT_ONE_SHOT)
	var emitted: Array[bool] = [false]
	var on_swap: Callable = func(_r: Room) -> void:
		terra.get_health().take_damage(99)
		# Simula o fim da morte (ex.: reserva de tempo sem animação) no meio da transição.
		terra.death_finished.emit()
		emitted[0] = true
	_game.connect("room_changed", on_swap, CONNECT_ONE_SHOT)
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida")
	for i: int in MAX_FRAMES:
		if emitted[0]:
			break
		await process_frame
	_check(emitted[0] and not _game.call("is_game_over") and not paused and _game.call("is_transitioning"),
		"death_finished no meio da transição: Game Over adiado, mundo rodando, transição seguindo")
	await _wait_transition_end(finished)
	_check(finished == [true] and not at_finish[0], "a transição termina normalmente (Game Over ainda fechado no sinal)")
	await process_frame
	_check(_game.call("is_game_over") and paused and not _game.call("is_transitioning"),
		"logo depois: Game Over aberto e mundo pausado, sem transição presa")
	_game.disconnect("transition_finished", on_finished)
	await _wait_accepting()
	await _retry_and_check(ROOM_01, &"start")


func _test_game_removed_during_transition() -> void:
	print("-- Game removida e recolocada durante a transição")
	await _new_game()
	var terra: PlayerCharacter = _terra()
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida")
	for i: int in MAX_FRAMES:
		if _fade().modulate.a > 0.0:
			break
		await process_frame
	var game: Node2D = _game
	root.remove_child(game)
	for i: int in 30:
		await process_frame
	_check(not paused and finished.is_empty() and game.call("is_transitioning"), "fora da árvore: transição parada, árvore despausada")
	root.add_child(game)
	await _wait_transition_end(finished)
	_check(finished == [true] and game.call("get_room_path") == ROOM_02 and not terra.get_hurtbox().is_blocked()
		and terra.process_mode == Node.PROCESS_MODE_INHERIT, "recolocada: a transição termina, proteção encerrada, controle devolvido")
	await _go(ROOM_01, &"east")
	_check(game.call("get_room_path") == ROOM_01, "transições seguintes funcionam")
	_game.disconnect("transition_finished", on_finished)


func _test_game_removed_during_retry() -> void:
	print("-- Game removida e recolocada durante o reinício")
	await _new_game()
	await _die()
	var restarted: Array[int] = [0]
	_game.connect("attempt_restarted", func(_a: int) -> void: restarted[0] += 1)
	_press(&"jump")
	await process_frame
	_check(_game.call("is_retrying") and paused, "reinício em andamento, mundo pausado")
	var game: Node2D = _game
	root.remove_child(game)
	_check(not paused, "fora da árvore: árvore despausada")
	for i: int in 40:
		await process_frame
	_check(not paused and restarted[0] == 0 and game.call("is_retrying"), "fora da árvore: reinício espera, árvore continua despausada")
	root.add_child(game)
	_check(paused, "recolocada: a pausa do reinício volta")
	for i: int in MAX_FRAMES:
		if restarted[0] > 0:
			break
		await process_frame
	_check(restarted[0] == 1 and not paused and not game.call("is_retrying") and not _terra().is_dead()
		and _terra().get_health().current_health == 5 and game.call("get_attempt") == 2, "reinício concluído depois de recolocada")
	await _go(ROOM_02, &"west")
	_check(game.call("get_room_path") == ROOM_02, "transições funcionam depois")


func _test_game_freed_during_transition() -> void:
	print("-- Game liberada durante a transição e durante o reinício")
	await _new_game()
	_check(_game.call("request_transition", ROOM_02, &"west"), "transição pedida")
	await process_frame
	_game.queue_free()
	_game = null
	for i: int in 30:
		await process_frame
	_check(not paused, "Game liberada no meio da transição: nada pausado")
	await _new_game()
	await _die()
	_press(&"jump")
	await process_frame
	_game.queue_free()
	_game = null
	for i: int in 30:
		await process_frame
	_check(not paused, "Game liberada no meio do reinício: árvore despausada")
	await _new_game()
	_check(not paused and _game.call("get_room_path") == ROOM_01, "Game nova funciona")


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game() -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		await process_frame
	paused = false
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	await physics_frame
	await process_frame


func _terra() -> PlayerCharacter:
	return _game.call("get_terra") as PlayerCharacter


func _fade() -> ColorRect:
	return _game.get_node("Fade/ColorRect") as ColorRect


func _wait_transition_end(finished: Array) -> void:
	for i: int in MAX_FRAMES:
		if not finished.is_empty():
			return
		await process_frame
	_check(false, "transition_finished não chegou")


func _go(room_path: String, entrance: StringName) -> void:
	var finished: Array = []
	var on_finished: Callable = func(swapped: bool) -> void: finished.append(swapped)
	_game.connect("transition_finished", on_finished)
	_check(_game.call("request_transition", room_path, entrance), "transição para %s iniciada" % room_path.get_file())
	await _wait_transition_end(finished)
	_game.disconnect("transition_finished", on_finished)
	await physics_frame


func _die() -> void:
	_terra().get_health().take_damage(99)
	await _wait_game_over()
	await _wait_accepting()


func _wait_game_over() -> void:
	for i: int in MAX_FRAMES:
		if _game.call("is_game_over"):
			return
		await process_frame
	_check(false, "Game Over não abriu")


func _wait_accepting() -> void:
	var go: GameOverScreen = _game.call("get_game_over_screen") as GameOverScreen
	for i: int in MAX_FRAMES:
		if go.is_accepting_input():
			return
		await process_frame


## Espera o Game Over na sala da morte e confirma o retry. Sem checkpoint, a Terra renasce na
## sala e entrada iniciais (Etapa 8.3), qualquer que seja a sala da morte.
func _game_over_and_retry(room_path: String) -> void:
	await _wait_game_over()
	_check(_game.call("is_game_over") and paused and _game.call("get_room_path") == room_path,
		"Game Over aberto na %s, mundo pausado" % room_path.get_file())
	await _wait_accepting()
	await _retry_and_check(ROOM_01, &"start")


func _retry_and_check(room_path: String, entrance: StringName) -> void:
	var restarted: Array[int] = [0]
	var at: Array[Vector2] = [Vector2.INF]
	var on_restarted: Callable = func(_a: int) -> void:
		restarted[0] += 1
		at[0] = _terra().global_position
	_game.connect("attempt_restarted", on_restarted)
	_press(&"jump")
	for i: int in MAX_FRAMES:
		if restarted[0] > 0:
			break
		await process_frame
	_game.disconnect("attempt_restarted", on_restarted)
	var room: Room = _game.call("get_room") as Room
	_check(restarted[0] == 1 and _game.call("get_room_path") == room_path and _game.call("get_arrival_entrance") == entrance
		and at[0].distance_to(room.get_entrance(entrance).global_position) < 0.5 and _terra().get_health().current_health == 5,
		"renasce na %s, entrada %s, com 5 de vida" % [room_path.get_file(), entrance])
	_check(not paused and not _game.call("is_transitioning") and not _terra().get_hurtbox().is_blocked(), "depois do reinício: nada pausado, preso ou bloqueado")


func _press(action: StringName) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1
