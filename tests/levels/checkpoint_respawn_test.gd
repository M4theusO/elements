extends SceneTree
## Teste automatizado do renascimento nos checkpoints (Etapa 8.3): sem checkpoint, renasce em
## start_room / start_entrance (morte na Sala 01 e na Sala 03); com checkpoint, no SpawnPoint do
## último altar ativado (mesma sala ou outra), olhando para spawn_facing; inimigos attempt só da
## sala da morte, outras salas e permanent preservados; checkpoints mantidos; vida, HUD,
## invulnerabilidade, dano bloqueado, pausa, Game Over fechado e controle só no fim; um reinício
## por confirmação; fallback seguro (checkpoint inconsistente, sala inexistente, cena que não é
## Room, sala sem Checkpoints, altar inexistente, altar sem SpawnPoint, sala inicial inválida e
## nenhum destino válido); transições normais depois.
##
## Usa a sala de teste da Etapa 8.2 (tests/checkpoints/altar_sandbox_room.tscn) e duas salas
## temporárias em user:// (nomes próprios, apagadas no fim). Esperas por sinais e estado.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/checkpoint_respawn_test.gd
## Imprime erros esperados (checkpoints e salas inválidos, fallback).

const GAME_PATH: String = "res://main/game.tscn"
const DIR: String = "res://world/levels/depths/forgotten_galleries/"
const ROOM_01: String = DIR + "room_01_awakening.tscn"
const ROOM_02: String = DIR + "room_02_gallery.tscn"
const ROOM_03: String = DIR + "room_03_ascent.tscn"
const ROOM_04: String = DIR + "room_04_crystals.tscn"
const SANDBOX: String = "res://tests/checkpoints/altar_sandbox_room.tscn"
const ALTAR_PATH: String = "res://world/levels/_shared/elemental_altar.tscn"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
## Cópia da sala de teste com um Fragmento a mais, de escopo permanent.
const PERM_ROOM: String = "user://checkpoint_respawn_perm_room.tscn"
## Cópia da sala de teste com um altar sem SpawnPoint.
const NO_SPAWN_ROOM: String = "user://checkpoint_respawn_no_spawn_room.tscn"
const WEST: StringName = &"sandbox_altar_west"
const EAST: StringName = &"sandbox_altar_east"
const NO_SPAWN: StringName = &"altar_no_spawn"
const FRAGMENT_ID: StringName = &"gallery_fragment_01"
const GUARDIAN_ID: StringName = &"respawn_guardian"
const BURROWER_ID: StringName = &"crystal_burrower_01"
const MAX_FRAMES: int = 900

var _failures: int = 0
var _checks: int = 0
var _game: Node2D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Checkpoints: renascimento (Etapa 8.3)")
	await process_frame
	_make_rooms()
	await _test_no_checkpoint_room_01()
	await _test_no_checkpoint_room_03()
	await _test_checkpoint_same_room()
	await _test_two_altars_last_one()
	await _test_checkpoint_other_room()
	await _test_permanent()
	await _test_invalid_checkpoints()
	await _test_no_spawn_point()
	await _test_start_room_invalid()
	await _test_nothing_valid()
	_cleanup()
	_finish()


func _finish() -> void:
	paused = false
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_no_checkpoint_room_01() -> void:
	print("-- Sem checkpoint: morte na Sala 01")
	await _new_game()
	_check(_game.call("get_respawn_room") == ROOM_01 and _game.call("get_respawn_entrance") == &"start",
		"renascimento previsto: Sala 01, entrada start")
	# Longe da entrada, olhando para a esquerda.
	_terra().global_position = Vector2(400, 320)
	_terra().set_facing(-1.0)
	await _wait(5)
	var obs: Dictionary = await _die_and_retry(true)
	var start: Marker2D = _room().get_entrance(&"start")
	_check(_game.call("get_room_path") == ROOM_01 and obs.end_position.distance_to(start.global_position) < 0.5,
		"renasce na Sala 01, entrada start (%s)" % obs.end_position)
	_check(_terra().get_facing() == _room().get_entrance_facing(&"start"), "olhando para dentro da sala")
	_check_retry_safety(obs, "Sala 01")
	await _check_after_restart(obs)


func _test_no_checkpoint_room_03() -> void:
	print("-- Sem checkpoint: morte na Sala 03")
	await _go(ROOM_02, &"west")
	await _go(ROOM_03, &"west")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and obs.swaps == [ROOM_01] and _game.call("get_room_path") == ROOM_01
		and obs.end_position.distance_to(_room().get_entrance(&"start").global_position) < 0.5,
		"morte na Sala 03: renasce na Sala 01, entrada start (não na entrada da sala da morte)")
	_check(_game.call("get_arrival_entrance") == &"start", "entrada de chegada: start")


func _test_checkpoint_same_room() -> void:
	print("-- Checkpoint na mesma sala")
	await _new_game()
	await _go(SANDBOX, &"west")
	_check(_activate(WEST), "altar oeste ativado pela interação")
	_check(_game.call("get_respawn_room") == SANDBOX and _game.call("get_respawn_entrance") == &"",
		"renascimento previsto: sala do altar, sem entrada (&\"\")")
	_kill(FRAGMENT_ID)
	_check(_game.call("get_defeated_enemies", SANDBOX) == [FRAGMENT_ID], "Fragmento da sala derrotado")
	_terra().global_position = Vector2(600, 320)
	_terra().set_facing(-1.0)
	await _wait(5)
	var obs: Dictionary = await _die_and_retry(true)
	var altar: ElementalAltar = _room().get_checkpoint(WEST)
	_check(obs.swaps == [SANDBOX] and _game.call("get_room_path") == SANDBOX, "uma troca, para a sala do altar")
	_check(obs.end_position.distance_to(altar.get_spawn_position()) < 0.5, "Terra no SpawnPoint do altar (%s)" % obs.end_position)
	_check(_terra().get_facing() == 1.0 and altar.get_spawn_facing() == 1.0, "olhando para spawn_facing (direita)")
	_check(_game.call("get_arrival_entrance") == &"", "entrada de chegada vazia (renasceu num altar)")
	_check(_room().get_persistent_enemies().has(FRAGMENT_ID) and (_game.call("get_defeated_enemies", SANDBOX) as Array).is_empty(),
		"sala da morte = sala do altar: o Fragmento voltou")
	_check(altar.is_current() and _game.call("is_current_checkpoint", SANDBOX, WEST), "o altar continua atual depois do reinício")
	_check_retry_safety(obs, "altar oeste")
	await _check_after_restart(obs)


func _test_two_altars_last_one() -> void:
	print("-- Dois altares: vale o último")
	_terra().global_position = Vector2(904, 320)
	await _wait(5)
	_check(_activate(EAST), "altar leste ativado")
	_terra().global_position = Vector2(500, 320)
	await _wait(5)
	var obs: Dictionary = await _die_and_retry()
	var east: ElementalAltar = _room().get_checkpoint(EAST)
	var west: ElementalAltar = _room().get_checkpoint(WEST)
	_check(obs.restarted == 1 and obs.end_position.distance_to(east.get_spawn_position()) < 0.5,
		"renasce no altar leste (o último ativado)")
	_check(_terra().get_facing() == -1.0, "olhando para spawn_facing do leste (esquerda)")
	_check(east.is_current() and west.is_activated() and not west.is_current()
		and _game.call("get_activated_checkpoints", SANDBOX) == [WEST, EAST], "checkpoint atual mantido; o anterior continua registrado")
	await _wait(10)
	var at: Vector2 = _terra().global_position
	await _wait(10)
	_check(_terra().is_on_floor() and _terra().global_position.distance_to(at) < 0.01 and absf(at.y - 320.0) < 0.5,
		"SpawnPoint seguro: no chão, parada, sem ser empurrada (%s)" % at)


func _test_checkpoint_other_room() -> void:
	print("-- Checkpoint em outra sala")
	# Checkpoint atual: altar leste da sala de teste (caso anterior). Fragmento da sala de teste
	# derrotado; Escavador da Sala 04 derrotado; morte na Sala 02 com o Fragmento dela derrotado.
	_kill(FRAGMENT_ID)
	await _go(ROOM_04, &"west")
	_kill(BURROWER_ID)
	await _go(ROOM_02, &"west")
	_kill(FRAGMENT_ID)
	var attempt: int = _game.call("get_attempt")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and obs.swaps == [SANDBOX] and _game.call("get_room_path") == SANDBOX
		and obs.end_position.distance_to(_room().get_checkpoint(EAST).get_spawn_position()) < 0.5,
		"morte na Sala 02: renasce no altar leste da sala de teste")
	_check(_game.call("get_attempt") == attempt + 1, "nova tentativa (%d)" % (attempt + 1))
	_check((_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty(), "inimigos da sala da morte (Sala 02) restaurados no registro")
	_check(_game.call("get_defeated_enemies", SANDBOX) == [FRAGMENT_ID] and not _room().get_persistent_enemies().has(FRAGMENT_ID),
		"sala do altar (não é a da morte): o Fragmento continua derrotado")
	_check(_game.call("get_defeated_enemies", ROOM_04) == [BURROWER_ID], "Sala 04: o Escavador continua derrotado")
	# Transições normais depois do reinício num altar.
	await _go(ROOM_01, &"east")
	_check(_game.call("get_room_path") == ROOM_01 and _game.call("get_arrival_entrance") == &"east"
		and _terra().global_position.distance_to(_room().get_entrance(&"east").global_position) < 0.5, "transição depois do reinício: Sala 01, entrada east")
	await _go(ROOM_02, &"west")
	_check(_room().get_persistent_enemies().has(FRAGMENT_ID), "Sala 02 revisitada: o Fragmento voltou")
	await _go(ROOM_04, &"west")
	_check(not _room().get_persistent_enemies().has(BURROWER_ID), "Sala 04 revisitada: o Escavador continua derrotado")
	_check(_game.call("is_current_checkpoint", SANDBOX, EAST), "transições não mexem no checkpoint atual")


func _test_permanent() -> void:
	print("-- Derrota permanent")
	await _new_game()
	await _go(PERM_ROOM, &"west")
	_check(_activate(WEST), "altar oeste da sala com permanent ativado")
	_kill(FRAGMENT_ID)
	_kill(GUARDIAN_ID)
	_check(_game.call("get_defeated_enemy_scope", PERM_ROOM, GUARDIAN_ID) == Room.SCOPE_PERMANENT, "guardião derrotado (permanent)")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and _game.call("get_room_path") == PERM_ROOM, "renasce no altar da mesma sala")
	_check(_room().get_persistent_enemies().has(FRAGMENT_ID) and not _room().get_persistent_enemies().has(GUARDIAN_ID)
		and _game.call("get_defeated_enemies", PERM_ROOM) == [GUARDIAN_ID], "o Fragmento comum volta; o permanent continua derrotado")


func _test_invalid_checkpoints() -> void:
	print("-- Checkpoint inválido: fallback para a Sala 01")
	await _new_game()
	await _go(SANDBOX, &"west")
	_check(_activate(WEST) and _activate_at(EAST, Vector2(904, 320)), "altares oeste e leste ativados")
	await _go(ROOM_04, &"west")
	_kill(BURROWER_ID)
	await _go(ROOM_02, &"west")
	var cases: Array = [
		[SANDBOX, &"ghost", "altar inexistente na sala"],
		["res://world/levels/nope_room.tscn", WEST, "sala do checkpoint inexistente (removida)"],
		[ALTAR_PATH, WEST, "cena que não é Room"],
		[ROOM_01, WEST, "sala sem nó Checkpoints"],
	]
	for spec: Array in cases:
		# Dados inconsistentes, como se o registro apontasse para algo que não existe mais.
		_game.set("_checkpoint_room", spec[0])
		_game.set("_checkpoint_id", spec[1])
		var defeated_04: Array = _game.call("get_defeated_enemies", ROOM_04)
		var obs: Dictionary = await _die_and_retry()
		_check(obs.restarted == 1 and obs.swaps == [ROOM_01] and _game.call("get_room_path") == ROOM_01
			and obs.end_position.distance_to(_room().get_entrance(&"start").global_position) < 0.5,
			"%s: renasce na Sala 01, entrada start (erro esperado)" % spec[2])
		_check(not _game.call("has_current_checkpoint") and _game.call("get_activated_checkpoints", SANDBOX) == [WEST, EAST],
			"%s: só a seleção atual foi limpa; histórico preservado" % spec[2])
		_check(_game.call("get_defeated_enemies", ROOM_04) == defeated_04, "%s: registro de inimigos de outras salas intacto" % spec[2])
		_check(not paused and not _game.call("is_retrying") and not _game.call("is_game_over") and is_zero_approx(_fade().modulate.a),
			"%s: nada preso (sem pausa, reinício, Game Over nem tela preta)" % spec[2])
		await _go(ROOM_02, &"west")


func _test_no_spawn_point() -> void:
	print("-- Altar sem SpawnPoint")
	await _new_game()
	await _go(NO_SPAWN_ROOM, &"west")
	var altar: ElementalAltar = _room().get_checkpoint(NO_SPAWN)
	_check(altar != null and not altar.has_spawn_point(), "altar válido na sala, sem SpawnPoint")
	_check(_game.call("activate_checkpoint", NO_SPAWN_ROOM, NO_SPAWN) and _activate(WEST) and _game.call("activate_checkpoint", NO_SPAWN_ROOM, NO_SPAWN),
		"altar sem SpawnPoint registrado como atual (depois do oeste)")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and _game.call("get_room_path") == ROOM_01
		and obs.end_position.distance_to(_room().get_entrance(&"start").global_position) < 0.5,
		"SpawnPoint inválido: renasce na Sala 01, entrada start (erro esperado)")
	_check(not _game.call("has_current_checkpoint") and _game.call("get_activated_checkpoints", NO_SPAWN_ROOM) == [NO_SPAWN, WEST],
		"seleção descartada; histórico dos altares preservado")


func _test_start_room_invalid() -> void:
	print("-- Sala inicial inválida: último recurso na sala da morte")
	await _new_game()
	await _go(ROOM_02, &"west")
	_kill(FRAGMENT_ID)
	_game.set("start_room", "res://world/levels/nope_start.tscn")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and obs.swaps == [ROOM_02] and _game.call("get_room_path") == ROOM_02
		and obs.end_position.distance_to(_room().get_entrance(&"west").global_position) < 0.5,
		"renasce na sala da morte, entrada de chegada west (erros esperados)")
	_check(_room().get_persistent_enemies().has(FRAGMENT_ID), "inimigos da sala da morte restaurados normalmente")
	_check(not paused and not _game.call("is_retrying") and is_zero_approx(_fade().modulate.a), "nada preso")


func _test_nothing_valid() -> void:
	print("-- Nenhum destino válido: falha controlada")
	await _new_game()
	await _go(SANDBOX, &"west")
	_check(_activate(WEST), "altar oeste ativado")
	# Renasce no altar (entrada de chegada fica &"") e então tudo fica inválido.
	await _die_and_retry()
	_check(_game.call("get_arrival_entrance") == &"" and _game.call("get_room_path") == SANDBOX, "renasceu no altar (sem entrada de chegada)")
	var room_before: Room = _room()
	_terra().global_position = Vector2(500, 320)
	await _wait(5)
	_game.set("_checkpoint_id", &"ghost")
	_game.set("start_room", "res://world/levels/nope_start.tscn")
	var obs: Dictionary = await _die_and_retry()
	_check(obs.restarted == 1 and obs.swaps.is_empty() and _room() == room_before and is_instance_valid(room_before),
		"nenhuma troca: continua na sala atual, que segue válida (erros esperados)")
	_check(not _terra().is_dead() and _terra().get_health().current_health == 5 and not paused and not _game.call("is_game_over")
		and not _game.call("is_retrying") and is_zero_approx(_fade().modulate.a) and _terra().can_process(),
		"falha controlada: Terra viva com 5, mundo rodando, sem tela preta nem Game Over")
	_game.set("start_room", ROOM_01)
	await _go(ROOM_01, &"east")
	_check(_game.call("get_room_path") == ROOM_01, "transições continuam funcionando")


# --- Reinício observado ----------------------------------------------------------------------

## Mata a Terra, espera o Game Over aceitar entrada e confirma com jump (evento real), insistindo
## durante o reinício. Acompanha quadro a quadro até attempt_restarted.
## hit: tenta um golpe na Terra durante o clarear (depois do revive).
func _die_and_retry(hit: bool = false) -> Dictionary:
	var terra: PlayerCharacter = _terra()
	var go: GameOverScreen = _game.call("get_game_over_screen")
	var obs: Dictionary = {
		"restarted": 0, "swaps": [], "swap_fade": -1.0, "swap_go_open": true, "swap_paused": false,
		"swap_terra_dead": false, "control_leak": false, "unpaused_early": false, "hit_ignored": true,
		"hit_tried": false, "end_position": Vector2.INF, "restart_invuln": 0.0, "restart_paused": true,
		"restart_go_open": true,
	}
	terra.get_health().take_damage(terra.get_health().current_health)
	for i: int in MAX_FRAMES:
		if go.is_open() and go.is_accepting_input():
			break
		await process_frame
	_check(go.is_open() and paused, "Game Over aberto, mundo pausado")
	var on_swap: Callable = func(room: Room) -> void:
		obs.swaps.append(room.scene_file_path)
		obs.swap_fade = _fade().modulate.a
		obs.swap_go_open = go.is_open()
		obs.swap_paused = paused
		obs.swap_terra_dead = terra.is_dead()
	var on_restarted: Callable = func(_a: int) -> void:
		obs.restarted += 1
		obs.end_position = terra.global_position
		obs.restart_invuln = terra.get_hurtbox().get_invulnerability_left()
		obs.restart_paused = paused
		obs.restart_go_open = go.is_open()
	_game.connect("room_changed", on_swap)
	_game.connect("attempt_restarted", on_restarted)
	_press(&"jump")
	for i: int in MAX_FRAMES:
		if obs.restarted > 0:
			break
		if i < 6:
			_press(&"jump")  # apertos repetidos durante o reinício: um só vale
		if i > 0 and not paused:
			obs.unpaused_early = true
		if terra.can_process():
			obs.control_leak = true
		if hit and not obs.hit_tried and not terra.is_dead():
			obs.hit_tried = true
			terra.get_hurtbox().receive_hit(1)
			obs.hit_ignored = terra.get_health().current_health == terra.get_health().max_health
		await process_frame
	_game.disconnect("room_changed", on_swap)
	_game.disconnect("attempt_restarted", on_restarted)
	await process_frame
	return obs


## Pausa, fade, Game Over, revive e controle durante o reinício.
func _check_retry_safety(obs: Dictionary, label: String) -> void:
	_check(obs.restarted == 1 and obs.swaps.size() == 1, "%s: um reinício, uma troca de sala, por confirmação (apertos repetidos ignorados)" % label)
	_check(is_equal_approx(obs.swap_fade, 1.0) and not obs.swap_go_open and obs.swap_paused and obs.swap_terra_dead,
		"%s: troca com a tela preta, Game Over fechado, mundo pausado, antes do revive" % label)
	_check(not obs.unpaused_early and not obs.control_leak, "%s: mundo pausado e Terra sem controle até o fim do reinício" % label)
	_check(obs.hit_tried and obs.hit_ignored, "%s: golpe durante o clarear ignorado" % label)
	_check(not obs.restart_paused and not obs.restart_go_open, "%s: no attempt_restarted, mundo rodando e Game Over fechado" % label)


## Vida, HUD, invulnerabilidade de 1 s a partir do controle e controle devolvido.
func _check_after_restart(obs: Dictionary) -> void:
	var terra: PlayerCharacter = _terra()
	_check(terra.get_health().current_health == 5 and not terra.is_dead(), "vida restaurada para 5")
	var hud: PlayerHud = _game.call("get_hud")
	_check(hud.get_hearts().get_full_count() == 5 and hud.get_hearts().get_empty_count() == 0, "HUD com 5 corações")
	_check(is_equal_approx(obs.restart_invuln, terra.revive_invulnerability_time) and is_equal_approx(terra.revive_invulnerability_time, 1.0),
		"invulnerabilidade de 1 s cheia quando o controle volta (%.3f)" % obs.restart_invuln)
	_check(terra.can_process() and terra.process_mode == Node.PROCESS_MODE_INHERIT and not paused, "controle devolvido depois do fade")
	_check(is_zero_approx(_fade().modulate.a) and not _fade().visible, "tela clara")
	terra.get_hurtbox().receive_hit(1)
	_check(terra.get_health().current_health == 5, "golpe logo depois: ignorado (invulnerável)")
	for i: int in 90:
		if not terra.get_hurtbox().is_invulnerable():
			break
		await physics_frame
	terra.get_hurtbox().receive_hit(1)
	_check(terra.get_health().current_health == 4, "acabada a invulnerabilidade, o golpe acerta")
	terra.get_health().restore_full()


# --- Salas de teste --------------------------------------------------------------------------

func _make_rooms() -> void:
	var perm: Node = (load(SANDBOX) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var guardian: Node2D = (load(FRAGMENT_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	guardian.name = "Guardian"
	guardian.position = Vector2(700.0, 320.0)
	guardian.set_meta(Room.PERSISTENT_ID_META, GUARDIAN_ID)
	guardian.set_meta(Room.PERSISTENCE_SCOPE_META, Room.SCOPE_PERMANENT)
	perm.get_node("Enemies").add_child(guardian)
	guardian.owner = perm
	_save(perm, PERM_ROOM)
	var no_spawn: Node = (load(SANDBOX) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var altar: ElementalAltar = ElementalAltar.new()  # só o script: sem Visuals, área nem SpawnPoint
	altar.name = "AltarNoSpawn"
	altar.checkpoint_id = NO_SPAWN
	altar.position = Vector2(300.0, 320.0)
	no_spawn.get_node("Checkpoints").add_child(altar)
	altar.owner = no_spawn
	_save(no_spawn, NO_SPAWN_ROOM)


func _save(room: Node, path: String) -> void:
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(room)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	_check(err == OK, "sala de teste gravada em %s" % path)
	room.free()


func _cleanup() -> void:
	for path: String in [PERM_ROOM, NO_SPAWN_ROOM]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game() -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	await _wait(3)


func _terra() -> PlayerCharacter:
	return _game.call("get_terra") as PlayerCharacter


func _room() -> Room:
	return _game.call("get_room") as Room


func _fade() -> ColorRect:
	return _game.get_node("Fade/ColorRect") as ColorRect


## Ativa o altar pela interação (sinal do altar → Game), com a Terra viva na sala dele.
func _activate(id: StringName) -> bool:
	var altar: ElementalAltar = _room().get_checkpoint(id)
	if altar == null:
		return false
	altar.activate()
	return _game.call("is_current_checkpoint", _game.call("get_room_path"), id)


func _activate_at(id: StringName, at: Vector2) -> bool:
	_terra().global_position = at
	return _activate(id)


func _kill(id: StringName) -> void:
	var enemy: Enemy = _room().get_persistent_enemies().get(id)
	_check(enemy != null, "inimigo '%s' presente para ser derrotado" % id)
	if enemy != null:
		(enemy.get_node("HealthComponent") as HealthComponent).take_damage(999)


func _go(room_path: String, entrance: StringName) -> void:
	var ok: bool = _game.call("request_transition", room_path, entrance)
	_check(ok, "transição para %s" % room_path.get_file())
	for i: int in MAX_FRAMES:
		if not _game.call("is_transitioning"):
			break
		await process_frame
	await _wait(3)


func _press(action: StringName) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1
