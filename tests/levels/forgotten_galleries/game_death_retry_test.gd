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
const ROOM_03: String = "res://world/levels/depths/forgotten_galleries/room_03_ascent.tscn"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
const FRAGMENT_NODE: String = "Enemies/LivingFragment"
const FRAGMENT_ID: StringName = &"gallery_fragment_01"
## Cópia da Sala 02 com mais um Fragmento, de escopo permanent (gravada em user:// e apagada no fim).
const SCOPE_ROOM: String = "user://death_retry_test_scope_room.tscn"
const GUARDIAN_ID: StringName = &"retry_guardian"
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
	await _test_retry_flow()
	await _test_respawn_at_start()
	await _test_arrival_entrance_and_previous_rooms()
	_make_scope_room()
	await _test_permanent_and_enemy_during_fade()
	await _test_game_removed()
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCOPE_ROOM))
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
	var retry_links: int = 0
	for c: Dictionary in go.retry_requested.get_connections():
		if (c.callable as Callable).get_object() == _game:
			retry_links += 1
	_check(retry_links == 1, "uma única ligação da Game com retry_requested (%d)" % retry_links)
	_check(_game.call("get_attempt") == 1 and not _game.call("is_retrying") and _game.call("get_respawn_entrance") == &"start",
		"tentativa 1, sem reinício, entrada de renascimento start")


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
	await _wait_accepting()
	_check(go.is_accepting_input() and go.get_retry_button().has_focus() and not go.get_retry_button().disabled,
		"pausado: botão \"Tentar novamente\" habilitado, com foco e aceitando entrada")

	# Sem reinício automático: sem confirmação, nada acontece.
	for i: int in 30:
		await process_frame
	_check(_game.call("get_attempt") == 1 and not _game.call("is_retrying"), "sem confirmação: nenhuma nova tentativa (tentativa 1)")
	_check(terra.is_dead() and terra.get_health().current_health == 0 and hud.get_hearts().get_full_count() == 0,
		"sem confirmação: Terra continua morta (0 de vida)")
	_check(_game.call("get_room") == room and is_instance_valid(room) and _game.call("get_room_path") == ROOM_02,
		"sem confirmação: sala não recarregada (mesma instância)")
	_check(paused and go.visible and retries[0] == 0, "sem confirmação: mundo pausado, tela visível, nenhum retry_requested")
	_check(finished[0] == 1 and death_starts[0] == 1, "morte processada uma única vez no total")


## Continua do caso anterior: Terra morta na Sala 02 (chegou por west), Fragmento vivo.
func _test_retry_flow() -> void:
	print("-- Tentar novamente: sequência do reinício")
	var terra: PlayerCharacter = _terra()
	var go: GameOverScreen = _screen()
	var old_room: Room = _game.call("get_room") as Room
	var old_fragment: Node = old_room.get_node_or_null(FRAGMENT_NODE)
	_check(_game.call("get_respawn_entrance") == &"west", "entrada de renascimento: west (chegada à Sala 02)")
	var retries: Array[int] = [0]
	go.retry_requested.connect(func() -> void: retries[0] += 1)
	var obs: Dictionary = await _confirm_and_watch(true)
	_check(retries[0] == 3, "o botão emite um retry_requested; com os 2 emitidos pelo teste, 3 no total (%d)" % retries[0])
	_check(obs.duplicates_ignored, "pedidos repetidos durante o reinício (botão, sinal emitido de novo, ui_accept) ignorados")
	_check(obs.transition_refused, "request_transition recusado durante o reinício")
	_check(obs.restarted == 1 and obs.restart_arg == 2 and _game.call("get_attempt") == 2,
		"attempt_restarted uma vez, tentativa 2 (%d, arg %d)" % [obs.restarted, obs.restart_arg])
	# Momento da troca (room_changed): tela preta, Game Over fechado, tentativa nova, mundo pausado.
	_check(obs.swap_count == 1, "sala recriada uma vez (%d room_changed)" % obs.swap_count)
	_check(is_equal_approx(obs.swap_fade, 1.0) and not obs.swap_go_open and obs.swap_paused and obs.swap_attempt == 2,
		"na recriação: tela preta (%.2f), Game Over fechado, mundo pausado, tentativa já 2" % obs.swap_fade)
	_check(obs.swap_terra_dead, "na recriação, a limpeza e a sala nova vêm antes do revive()")
	_check(not obs.control_leak, "Terra sem controle (pausada ou desligada) do retry até attempt_restarted")
	_check(not obs.moved, "direção segurada durante o clarear não move a Terra")
	_check(not obs.unpaused_early and not (obs.enemy_watch as Dictionary).is_empty() and obs.enemies_still_in_fade,
		"mundo pausado durante todo o clarear: inimigos parados (%d observados)" % (obs.enemy_watch as Dictionary).size())
	_check(obs.released_together, "Terra e inimigos liberados juntos, no instante de attempt_restarted")
	_check(obs.min_invuln > 0.999, "invulnerabilidade não corre durante o fade (mínimo %.3f s)" % obs.min_invuln)
	_check(obs.hit_during_fade_ignored, "golpe durante o clarear ignorado (vida continua 5)")
	# Estado final.
	var room: Room = _game.call("get_room") as Room
	var entrance: Marker2D = room.get_entrance(&"west")
	_check(room != old_room and is_instance_valid(room) and _game.call("get_room_path") == ROOM_02, "Sala 02 recriada (instância nova)")
	await process_frame
	_check(not is_instance_valid(old_room) and (old_fragment == null or not is_instance_valid(old_fragment)),
		"sala e Fragmento antigos liberados")
	_check(terra.get_health().current_health == 5 and not terra.is_dead(), "Terra com 5 de vida, viva")
	_check(_hud().get_hearts().get_full_count() == 5 and _hud().get_hearts().get_empty_count() == 0, "HUD com 5 corações")
	_check(obs.end_position.distance_to(entrance.global_position) < 0.5 and terra.get_facing() == room.get_entrance_facing(&"west"),
		"Terra na entrada west, olhando para dentro da sala")
	_check(not go.is_open() and not paused and not _game.call("is_retrying") and not _game.call("is_game_over"),
		"Game Over fechado, árvore despausada, reinício concluído")
	var fade: ColorRect = _game.get_node("Fade/ColorRect") as ColorRect
	_check(is_zero_approx(fade.modulate.a) and not fade.visible, "tela clara")
	var camera: Camera2D = terra.get_node("Camera2D") as Camera2D
	var bounds: Rect2i = room.get_camera_bounds()
	_check(camera.limit_left == bounds.position.x and camera.limit_right == bounds.end.x and camera.limit_top == bounds.position.y
		and camera.limit_bottom == bounds.end.y, "limites da câmera da sala recriada")
	_check(terra.process_mode == Node.PROCESS_MODE_INHERIT and terra.can_process(), "controle devolvido")
	_check(_sprite(terra).animation == PlayerCharacter.ANIM_IDLE, "animação idle após renascer")
	var fragment: Enemy = room.get_node_or_null(FRAGMENT_NODE) as Enemy
	_check(fragment != null and fragment != old_fragment and _enemy_count() == 1 and _game_links(fragment) == 1,
		"Fragmento da sala atual restaurado (um só, instância nova, uma ligação)")
	await _check_invulnerability_window(terra, obs)
	# Transições depois de renascer.
	await _go(ROOM_01, &"east")
	_check(_game.call("get_room_path") == ROOM_01 and _game.call("get_respawn_entrance") == &"east", "transição após renascer: Sala 01, entrada east")
	await _go(ROOM_02, &"west")
	_check(_game.call("get_room_path") == ROOM_02 and _enemy_count() == 1, "volta à Sala 02 com um Fragmento")
	await process_frame
	_check(retries[0] == 3 and obs.restarted == 1 and _game.call("get_attempt") == 2, "nada se repetiu depois (o botão não reemitiu; um reinício)")


func _test_respawn_at_start() -> void:
	print("-- Renascimento na sala inicial (entrada start)")
	await _new_game()
	_check(_game.call("get_room_path") == ROOM_01 and _game.call("get_respawn_entrance") == &"start", "sala inicial, entrada start")
	var terra: PlayerCharacter = _terra()
	var start: Vector2 = (_game.call("get_room") as Room).get_entrance(&"start").global_position
	# Morre longe da entrada (andando, não teleportada).
	Input.action_press(&"move_right")
	for i: int in 40:
		await physics_frame
	Input.action_release(&"move_right")
	_check(terra.global_position.distance_to(start) > 50.0, "Terra longe da entrada start antes de morrer (%.0f px)" % terra.global_position.distance_to(start))
	await _die()
	var obs: Dictionary = await _confirm_and_watch()
	_check(obs.restarted == 1 and _game.call("get_attempt") == 2, "reinício concluído (tentativa 2)")
	_check(obs.end_position.distance_to(start) < 0.5 and terra.get_health().current_health == 5,
		"renasce na entrada start (não onde morreu), com 5 de vida")


func _test_arrival_entrance_and_previous_rooms() -> void:
	print("-- Entrada de chegada e inimigos de salas anteriores")
	await _new_game()
	await _go(ROOM_02, &"west")
	_kill_fragment()
	_check(_game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID), "Fragmento da Sala 02 derrotado")
	await _go(ROOM_03, &"west")
	_check(_game.call("get_respawn_entrance") == &"west", "Sala 03 pela entrada west")
	await _go(ROOM_02, &"east")
	_check(_game.call("get_room_path") == ROOM_02 and _game.call("get_respawn_entrance") == &"east" and _enemy_count() == 0,
		"de volta à Sala 02 pela outra porta: entrada east; Fragmento continua derrotado (mesma tentativa)")
	# Morte logo depois de entrar na sala.
	await _die()
	var obs: Dictionary = await _confirm_and_watch()
	var room: Room = _game.call("get_room") as Room
	_check(obs.restarted == 1 and _game.call("get_room_path") == ROOM_02, "morte logo após entrar: reinício na Sala 02")
	_check(obs.end_position.distance_to(room.get_entrance(&"east").global_position) < 0.5
		and _game.call("get_respawn_entrance") == &"east", "renasce na entrada east (a da última chegada)")
	_check(_enemy_count() == 1 and room.get_node_or_null(FRAGMENT_NODE) != null and not _game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID),
		"o Fragmento derrotado na sala atual volta (um só)")
	# Derrota numa sala anterior e morte em outra.
	_kill_fragment()
	await _go(ROOM_03, &"west")
	await _die()
	obs = await _confirm_and_watch()
	_check(obs.restarted == 1 and _game.call("get_room_path") == ROOM_03 and _game.call("get_attempt") == 3
		and obs.end_position.distance_to((_game.call("get_room") as Room).get_entrance(&"west").global_position) < 0.5,
		"morte na Sala 03: renasce na entrada west da Sala 03 (tentativa 3)")
	_check((_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty(), "registro da Sala 02 limpo")
	await _go(ROOM_02, &"east")
	var fragment: Enemy = (_game.call("get_room") as Room).get_node_or_null(FRAGMENT_NODE) as Enemy
	_check(fragment != null and _enemy_count() == 1 and _game_links(fragment) == 1
		and _health(fragment).current_health == _health(fragment).max_health,
		"revisitando a Sala 02: o Fragmento comum volta (um só, vida cheia, uma ligação)")


func _test_permanent_and_enemy_during_fade() -> void:
	print("-- Derrotas permanent e inimigo derrotado durante o clarear")
	await _new_game()
	_check(_game.call("load_room", SCOPE_ROOM, &"west"), "sala de teste com um Fragmento permanent")
	await physics_frame
	_kill_by_id(FRAGMENT_ID)
	_kill_by_id(GUARDIAN_ID)
	_check(_game.call("get_defeated_enemy_scope", SCOPE_ROOM, GUARDIAN_ID) == Room.SCOPE_PERMANENT
		and _game.call("get_defeated_enemy_scope", SCOPE_ROOM, FRAGMENT_ID) == Room.SCOPE_ATTEMPT, "derrotas attempt e permanent registradas")
	await physics_frame
	await _die()
	var obs: Dictionary = await _confirm_and_watch(false, true)
	_check(obs.restarted == 1, "reinício concluído")
	_check(obs.swap_names == ["LivingFragment"], "na recriação: volta o Fragmento comum; o permanent não %s" % [obs.swap_names])
	_check(obs.killed_during_fade, "Fragmento derrotado durante o clarear (dano direto, mundo pausado): registrado")
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [GUARDIAN_ID, FRAGMENT_ID]
		and _game.call("get_defeated_enemy_scope", SCOPE_ROOM, GUARDIAN_ID) == Room.SCOPE_PERMANENT,
		"permanent preservada; a derrota durante o clarear entra na tentativa nova %s" % [_game.call("get_defeated_enemies", SCOPE_ROOM)])
	await physics_frame
	_check(_game.call("load_room", SCOPE_ROOM, &"west") and _enemy_count() == 0, "recarregada: nenhum dos dois volta (sem duplicação)")


func _test_game_removed() -> void:
	print("-- Game removida no Game Over e durante o reinício")
	await _new_game()
	await _die()
	_check(paused, "árvore pausada pelo Game Over")
	var game: Node2D = _game
	_game = null
	root.remove_child(game)
	_check(not paused, "Game removida no Game Over: árvore despausada")
	game.free()
	await _new_game()
	_check(not paused and not _screen().is_open() and _hud().get_hearts().get_full_count() == 5, "Game nova: rodando, Game Over oculto, 5 corações")
	await _die()
	_press(&"jump")
	await process_frame
	_check(_game.call("is_retrying") and paused, "reinício em andamento (tela escurecendo, mundo pausado)")
	game = _game
	_game = null
	root.remove_child(game)
	_check(not paused, "Game removida durante o reinício: árvore despausada")
	for i: int in 30:
		await process_frame
	_check(not paused, "e continua despausada depois de o fade terminar fora da árvore")
	game.free()
	await _new_game()
	_check(not paused and _game.call("get_attempt") == 1, "Game nova depois disso: rodando, tentativa 1")


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


## Mata a Terra e espera death_finished e o botão aceitar entrada (sinal e estado, não tempo).
func _die() -> void:
	var terra: PlayerCharacter = _terra()
	var done: Array[bool] = [false]
	var on_done: Callable = func() -> void: done[0] = true
	terra.death_finished.connect(on_done)
	terra.get_health().take_damage(terra.get_health().current_health)
	for i: int in MAX_FRAMES:
		if done[0]:
			break
		await process_frame
	terra.death_finished.disconnect(on_done)
	_check(done[0] and _screen().is_open() and paused, "Terra morreu; Game Over aberto e mundo pausado")
	await _wait_accepting()


func _wait_accepting() -> void:
	for i: int in MAX_FRAMES:
		if _screen().is_accepting_input():
			return
		await process_frame


## Confirma "Tentar novamente" (ação jump) e acompanha o reinício quadro a quadro até
## attempt_restarted. extra: tenta pedidos repetidos, transição, direção segurada e golpe
## durante o clarear. kill_during_fade: derrota o Fragmento da sala nova (dano direto) durante
## o clarear, com o mundo ainda pausado. Também confere inimigos parados no clarear e a
## liberação simultânea de Terra e inimigos no attempt_restarted (Etapa 2D).
func _confirm_and_watch(extra: bool = false, kill_during_fade: bool = false) -> Dictionary:
	var terra: PlayerCharacter = _terra()
	var go: GameOverScreen = _screen()
	var fade: ColorRect = _game.get_node("Fade/ColorRect") as ColorRect
	var obs: Dictionary = {
		"restarted": 0, "restart_arg": 0, "swap_count": 0, "swap_fade": -1.0, "swap_go_open": true,
		"swap_paused": false, "swap_attempt": 0, "swap_terra_dead": false, "swap_names": [],
		"control_leak": false, "moved": false, "min_invuln": 99.0, "hit_during_fade_ignored": true,
		"duplicates_ignored": true, "transition_refused": true, "killed_during_fade": false,
		"end_position": Vector2.ZERO, "restart_invuln": 0.0, "restart_tick": 0,
		"unpaused_early": false, "released_together": false, "enemies_still_in_fade": false, "enemy_watch": {},
	}
	var on_swap: Callable = func(_room: Room) -> void:
		obs.swap_count += 1
		obs.swap_fade = fade.modulate.a
		obs.swap_go_open = go.is_open()
		obs.swap_paused = paused
		obs.swap_attempt = _game.call("get_attempt")
		obs.swap_terra_dead = terra.is_dead()
		obs.swap_names = _enemy_names()
	var on_restarted: Callable = func(attempt: int) -> void:
		obs.restarted += 1
		obs.restart_arg = attempt
		# Solta a direção no mesmo instante em que o controle volta.
		Input.action_release(&"move_right")
		obs.end_position = terra.global_position
		obs.restart_invuln = terra.get_hurtbox().get_invulnerability_left()
		obs.restart_tick = Engine.get_physics_frames()
		# Liberação simultânea: no instante do sinal, mundo despausado e Terra e inimigos processando.
		var all_free: bool = not paused and terra.can_process() and not _game.call("is_retrying")
		var still: bool = true
		for enemy: Variant in obs.enemy_watch:
			if is_instance_valid(enemy) and not (enemy as Enemy).is_dead():
				all_free = all_free and (enemy as Enemy).can_process()
				still = still and (enemy as Enemy).global_position == obs.enemy_watch[enemy]
		obs.released_together = all_free
		obs.enemies_still_in_fade = still
	_game.connect("room_changed", on_swap)
	_game.connect("attempt_restarted", on_restarted)
	var attempt_before: int = _game.call("get_attempt")
	_press(&"jump")
	await process_frame
	if extra:
		_press(&"jump")
		_press(&"ui_accept")
		go.retry_requested.emit()
		go.retry_requested.emit()
		obs.transition_refused = not _game.call("request_transition", ROOM_01, &"east")
	var hold_from: Vector2 = Vector2.INF
	var enemy_watch: Dictionary = {}
	obs.enemy_watch = enemy_watch
	for i: int in MAX_FRAMES:
		if obs.restarted > 0:
			break
		if terra.can_process():
			obs.control_leak = true
		if not terra.is_dead():
			obs.min_invuln = minf(obs.min_invuln, terra.get_hurtbox().get_invulnerability_left())
		# Clarear (depois da troca): mundo ainda pausado; direção segurada, golpe, inimigos
		# parados e inimigo derrotado por dano direto.
		if obs.swap_count > 0:
			if not paused:
				obs.unpaused_early = true
			if enemy_watch.is_empty():
				for child: Node in (_game.call("get_room") as Room).get_node("Enemies").get_children():
					if child is Enemy:
						enemy_watch[child] = (child as Enemy).global_position
			if extra and hold_from == Vector2.INF and not terra.is_dead():
				hold_from = terra.global_position
				Input.action_press(&"move_right")
				terra.get_hurtbox().receive_hit(1)
				obs.hit_during_fade_ignored = terra.get_health().current_health == terra.get_health().max_health
			if kill_during_fade and not obs.killed_during_fade:
				var enemy: Enemy = (_game.call("get_room") as Room).get_node_or_null(FRAGMENT_NODE) as Enemy
				if enemy != null:
					_health(enemy).take_damage(999)
					obs.killed_during_fade = _game.call("is_enemy_defeated", SCOPE_ROOM, FRAGMENT_ID)
		await process_frame
	Input.action_release(&"move_right")
	if hold_from != Vector2.INF:
		obs.moved = obs.end_position != hold_from
	else:
		obs.moved = extra  # o clarear com o mundo rodando não foi observado
	if extra:
		obs.duplicates_ignored = _game.call("get_attempt") == attempt_before + 1
	_game.disconnect("room_changed", on_swap)
	_game.disconnect("attempt_restarted", on_restarted)
	return obs


## Invulnerabilidade de renascimento: começa cheia quando o controle volta e dura 1 s de
## física (contada em ticks reais, porque a Hurtbox desconta em _physics_process).
## Os ticks contam a partir do tick físico registrado no próprio attempt_restarted (obs).
func _check_invulnerability_window(terra: PlayerCharacter, obs: Dictionary) -> void:
	var hurtbox: Hurtbox = terra.get_hurtbox()
	var full: float = terra.revive_invulnerability_time
	_check(is_equal_approx(obs.restart_invuln, full), "ao recuperar o controle: %.3f s de invulnerabilidade" % obs.restart_invuln)
	var expected_ticks: int = roundi(full * Engine.physics_ticks_per_second)
	var hit_ignored: bool = true
	var hit_done: bool = false
	for i: int in expected_ticks * 3:
		var elapsed: int = Engine.get_physics_frames() - int(obs.restart_tick)
		if not hurtbox.is_invulnerable():
			break
		if not hit_done and elapsed >= expected_ticks / 2:
			hit_done = true
			hurtbox.receive_hit(1)
			hit_ignored = terra.get_health().current_health == 5
		await physics_frame
	var ticks: int = Engine.get_physics_frames() - int(obs.restart_tick)
	_check(hit_done and absi(ticks - expected_ticks) <= 1, "invulnerável por %d ticks de física depois do controle (~%d = %.1f s)" % [ticks, expected_ticks, full])
	_check(hit_ignored, "golpe no meio da invulnerabilidade ignorado")
	hurtbox.receive_hit(1)
	_check(terra.get_health().current_health == 4, "depois dela, o golpe acerta (5 -> 4)")


func _kill_fragment() -> void:
	var fragment: Enemy = (_game.call("get_room") as Room).get_node_or_null(FRAGMENT_NODE) as Enemy
	_check(fragment != null, "Fragmento presente para ser derrotado")
	if fragment != null:
		_health(fragment).take_damage(999)


func _kill_by_id(id: StringName) -> void:
	var enemy: Enemy = (_game.call("get_room") as Room).get_persistent_enemies().get(id)
	_check(enemy != null, "inimigo '%s' presente para ser derrotado" % id)
	if enemy != null:
		_health(enemy).take_damage(999)


func _health(enemy: Enemy) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


func _sprite(terra: PlayerCharacter) -> AnimatedSprite2D:
	return terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D


func _enemy_count() -> int:
	return _enemy_names().size()


func _enemy_names() -> Array[String]:
	var names: Array[String] = []
	var room: Room = _game.call("get_room") as Room
	for child: Node in room.get_node("Enemies").get_children():
		if child is Enemy and not child.is_queued_for_deletion() and not (child as Enemy).is_dead():
			names.append(String(child.name))
	names.sort()
	return names


## Ligações do died do inimigo com a Game (registro de derrotas).
func _game_links(enemy: Enemy) -> int:
	var n: int = 0
	for c: Dictionary in _health(enemy).died.get_connections():
		if (c.callable as Callable).get_object() == _game:
			n += 1
	return n


func _make_scope_room() -> void:
	var scoped: Node = (load(ROOM_02) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var guardian: Node2D = (load(FRAGMENT_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	guardian.name = "Guardian"
	guardian.position = Vector2(700.0, 320.0)
	guardian.set_meta(Room.PERSISTENT_ID_META, GUARDIAN_ID)
	guardian.set_meta(Room.PERSISTENCE_SCOPE_META, Room.SCOPE_PERMANENT)
	scoped.get_node("Enemies").add_child(guardian)
	guardian.owner = scoped
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(scoped)
	if err == OK:
		err = ResourceSaver.save(packed, SCOPE_ROOM)
	_check(err == OK, "sala de teste gravada em %s" % SCOPE_ROOM)
	scoped.free()


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
