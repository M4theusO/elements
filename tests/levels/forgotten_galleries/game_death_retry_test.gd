extends SceneTree
## Teste automatizado da vida, HUD e Game Over na Game (Etapa 2B de Vida/HUD/Morte):
## HUD única na camada 5 ligada à Terra persistente, atualização imediata, vida preservada e sem
## cura nas transições, morte com a animação uma vez, Game Over só depois de death_finished,
## mundo pausado com o menu funcionando, transições recusadas com a Terra morta, nenhum
## reinício automático e a árvore despausada quando a Game sai.
##
## Esperas por sinais reais (death_finished, room_changed, retry_requested), com limite de
## quadros só como proteção contra travamento, e não por tempos fixos em ticks de física.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/game_death_retry_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_01: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const FRAGMENT_NODE: String = "Enemies/LivingFragment"
## Limite de segurança (quadros) para esperar um sinal.
const MAX_FRAMES: int = 600

var _failures: int = 0
var _checks: int = 0
var _game: Node2D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Game: vida, HUD e Game Over (Etapa 2B)")
	await process_frame
	await _test_structure()
	await _test_damage_and_transitions()
	await _test_death_and_game_over()
	await _test_cleanup_unpauses()
	_finish()


func _finish() -> void:
	paused = false
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_structure() -> void:
	print("-- Estrutura: HUD, fade e Game Over na Game")
	await _new_game()
	var hud: PlayerHud = _hud()
	var go: GameOverScreen = _screen()
	var fade: CanvasLayer = _game.get_node("Fade") as CanvasLayer
	_check(hud != null and _count_of(PlayerHud) == 1, "uma única PlayerHud na Game")
	_check(go != null and _count_of(GameOverScreen) == 1, "uma única GameOverScreen na Game")
	if hud == null or go == null:
		return
	_check(hud.layer == 5 and fade.layer == 10 and go.layer == 20 and hud.layer < fade.layer and fade.layer < go.layer,
		"camadas: HUD %d < Fade %d < Game Over %d" % [hud.layer, fade.layer, go.layer])
	_check(hud.get_bound_health() == _terra().get_health(), "HUD ligada à vida da Terra persistente da Game")
	_check(hud.get_hearts().get_full_count() == 5 and hud.get_hearts().get_empty_count() == 0
		and hud.get_hearts().get_maximum() == 5, "HUD inicial: 5 corações cheios")
	_check(not go.is_open() and not go.visible and not _game.call("is_game_over"), "Game Over começa oculto")
	_check(go.process_mode == Node.PROCESS_MODE_ALWAYS, "Game Over processa com o jogo pausado")
	_check(not paused, "mundo rodando")
	var links: int = 0
	for c: Dictionary in _terra().death_finished.get_connections():
		if (c.callable as Callable).get_object() == _game:
			links += 1
	_check(links == 1, "uma única ligação da Game com death_finished (%d)" % links)
	_check(go.retry_requested.get_connections().is_empty(), "retry_requested ainda sem ligação (reinício é a Etapa 2C)")


func _test_damage_and_transitions() -> void:
	print("-- Dano e transições")
	var hud: PlayerHud = _hud()
	var hud_id: int = hud.get_instance_id()
	var health: HealthComponent = _terra().get_health()
	health.take_damage(1)
	_check(hud.get_hearts().get_full_count() == 4 and hud.get_hearts().get_empty_count() == 1,
		"atualização imediata após dano: 4 cheios, 1 vazio (sem esperar quadro)")
	health.take_damage(1)
	_check(hud.get_hearts().get_full_count() == 3, "segundo dano: 3 cheios")
	await _go(ROOM_02, &"west")
	_check(_game.call("get_room_path") == ROOM_02, "chegou à Sala 02")
	_check(health.current_health == 3 and hud.get_hearts().get_full_count() == 3 and hud.get_hearts().get_empty_count() == 2,
		"vida preservada na ida: 3 de 5, HUD igual")
	await _go(ROOM_01, &"east")
	_check(_game.call("get_room_path") == ROOM_01 and health.current_health == 3 and hud.get_hearts().get_full_count() == 3,
		"vida preservada na volta: ainda 3 (sem cura automática)")
	await _go(ROOM_02, &"west")
	_check(health.current_health == 3, "várias transições sem cura (3)")
	_check(_hud() != null and _hud().get_instance_id() == hud_id and _count_of(PlayerHud) == 1
		and hud.get_bound_health() == health, "HUD não recriada nas transições (mesma instância, mesma vida)")
	_check(_screen() != null and not _screen().is_open() and not paused, "Game Over fechado e mundo rodando após as transições")


func _test_death_and_game_over() -> void:
	print("-- Morte e Game Over")
	var terra: PlayerCharacter = _terra()
	var go: GameOverScreen = _screen()
	var hud: PlayerHud = _hud()
	var sprite: AnimatedSprite2D = terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var room: Room = _game.call("get_room") as Room
	var fragment: Node2D = room.get_node_or_null(FRAGMENT_NODE) as Node2D
	_check(fragment != null, "Fragmento vivo na Sala 02 (para conferir a pausa)")
	# Contadores ligados antes da morte.
	var death_starts: Array[int] = [0]
	var death_ends: Array[int] = [0]
	var finished: Array[int] = [0]
	var retries: Array[int] = [0]
	sprite.animation_changed.connect(func() -> void:
		if sprite.animation == PlayerCharacter.ANIM_DEATH:
			death_starts[0] += 1)
	sprite.animation_finished.connect(func() -> void:
		if sprite.animation == PlayerCharacter.ANIM_DEATH:
			death_ends[0] += 1)
	terra.death_finished.connect(func() -> void: finished[0] += 1)
	go.retry_requested.connect(func() -> void: retries[0] += 1)

	terra.get_health().take_damage(terra.get_health().current_health)
	_check(terra.is_dead() and hud.get_hearts().get_full_count() == 0 and hud.get_hearts().get_empty_count() == 5,
		"Terra morta; HUD com 0 cheios e 5 vazios na hora")
	_check(not go.is_open() and not paused, "logo após a morte: Game Over fechado e mundo rodando")
	_check(not _game.call("request_transition", ROOM_01, &"east") and not _game.call("is_transitioning"),
		"com a Terra morta (animação em andamento), transição recusada")

	# Espera o fim real da animação (death_finished), conferindo a cada quadro que a tela não abriu antes.
	var early_open: bool = false
	for i: int in MAX_FRAMES:
		if finished[0] > 0:
			break
		if go.is_open() or paused:
			early_open = true
		await process_frame
	_check(finished[0] == 1, "death_finished emitido (%d)" % finished[0])
	_check(not early_open, "Game Over não abriu nem pausou antes de death_finished")
	_check(death_starts[0] == 1 and death_ends[0] == 1, "animação death começou e terminou uma vez (%d/%d)" % [death_starts[0], death_ends[0]])
	_check(go.is_open() and go.visible and _game.call("is_game_over"), "Game Over (\"Você caiu\") aberto após death_finished")
	_check(paused, "mundo pausado no Game Over")
	var title: Label = _find_label(go, "Você caiu")
	_check(title != null and title.is_visible_in_tree(), "texto \"Você caiu\" visível")

	# Mundo parado durante a pausa; a animação de morte não recomeça.
	var terra_at: Vector2 = terra.global_position
	var fragment_at: Vector2 = fragment.global_position if fragment != null else Vector2.ZERO
	var frame_at: int = sprite.frame
	for i: int in 30:
		await physics_frame
	_check(terra.global_position == terra_at and (fragment == null or fragment.global_position == fragment_at),
		"com o mundo pausado, Terra e Fragmento não se movem")
	_check(sprite.animation == PlayerCharacter.ANIM_DEATH and sprite.frame == frame_at and death_starts[0] == 1
		and finished[0] == 1, "a animação death fica no último quadro; não toca de novo nem reemite death_finished")
	_check(not _game.call("request_transition", ROOM_01, &"east") and not _game.call("is_transitioning")
		and _game.call("get_room") == room, "no Game Over, request_transition é recusado")
	var exits: Array[RoomExit] = room.get_exits()
	if not exits.is_empty():
		exits[0].transition_requested.emit(exits[0].target_room, exits[0].target_entry)
		await process_frame
		_check(not _game.call("is_transitioning") and _game.call("get_room") == room, "saída da sala acionada no Game Over: nada acontece")

	# Menu funcional com a árvore pausada: espera o atraso de entrada (timer que conta pausado).
	for i: int in MAX_FRAMES:
		if go.is_accepting_input():
			break
		await process_frame
	_check(go.is_accepting_input() and go.get_retry_button().has_focus() and not go.get_retry_button().disabled,
		"pausado: botão \"Tentar novamente\" habilitado, com foco e aceitando entrada")
	_press(&"jump")
	await process_frame
	_check(retries[0] == 1, "pausado: a ação jump confirma e emite retry_requested (%d)" % retries[0])
	_press(&"ui_accept")
	_press(&"jump")
	await process_frame
	_check(retries[0] == 1, "confirmações repetidas não emitem de novo (%d)" % retries[0])

	# Sem reinício automático: nada além do sinal acontece.
	for i: int in 30:
		await process_frame
	_check(_game.call("get_attempt") == 1, "nenhuma nova tentativa (tentativa 1)")
	_check(terra.is_dead() and terra.get_health().current_health == 0 and hud.get_hearts().get_full_count() == 0,
		"Terra continua morta (0 de vida)")
	_check(_game.call("get_room") == room and is_instance_valid(room) and _game.call("get_room_path") == ROOM_02,
		"sala não recarregada (mesma instância)")
	_check(paused and go.visible, "mundo continua pausado e a tela continua visível")
	_check(finished[0] == 1 and death_starts[0] == 1, "morte processada uma única vez no total")


func _test_cleanup_unpauses() -> void:
	print("-- Saída da Game durante o Game Over")
	_check(paused, "árvore pausada pela Game antes da saída")
	var game: Node2D = _game
	_game = null
	root.remove_child(game)
	_check(not paused, "Game removida no Game Over: árvore despausada")
	game.free()
	# Uma Game nova começa normalmente.
	await _new_game()
	_check(not paused and not _screen().is_open() and _hud().get_hearts().get_full_count() == 5, "Game nova: rodando, Game Over oculto, 5 corações")
	_check(_terra().death_finished.get_connections().size() >= 1, "Game nova ligada à morte da própria Terra")


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game() -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	await physics_frame
	await process_frame


func _terra() -> PlayerCharacter:
	return _game.call("get_terra") as PlayerCharacter


func _hud() -> PlayerHud:
	return _game.call("get_hud") as PlayerHud


func _screen() -> GameOverScreen:
	return _game.call("get_game_over_screen") as GameOverScreen


func _count_of(type: Variant) -> int:
	var n: int = 0
	for child: Node in _game.get_children():
		if is_instance_of(child, type):
			n += 1
	return n


func _find_label(node: Node, text: String) -> Label:
	if node is Label and (node as Label).text == text:
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, text)
		if found != null:
			return found
	return null


## Pede a transição e espera room_changed e o fim do fade (sinais e estado, não tempo fixo).
func _go(room_path: String, entrance: StringName) -> void:
	var changed: Array[bool] = [false]
	var on_changed: Callable = func(_room: Room) -> void: changed[0] = true
	_game.connect("room_changed", on_changed)
	var started: bool = _game.call("request_transition", room_path, entrance)
	_check(started, "transição para %s iniciada" % room_path.get_file())
	for i: int in MAX_FRAMES:
		if changed[0] and not _game.call("is_transitioning"):
			break
		await process_frame
	_game.disconnect("room_changed", on_changed)
	await physics_frame


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
