extends SceneTree
## Teste de regressão: sincronia física da Terra nas transições (defeito Sala 05 → 04).
## Desligada durante a troca, a Terra saía do espaço físico; o servidor ignorava o teleporte para
## a entrada e, ao ser religada, ela voltava por um passo na posição antiga, onde a saída oeste
## da Sala 04 (mesmas coordenadas da saída oeste da Sala 05) disparava e a levava à Sala 03.
## A Game agora usa DISABLE_MODE_MAKE_STATIC na Terra.
##
## Percorre todas as conexões das Galerias (01 ↔ 02 ↔ 03 ↔ 04 ↔ 05) andando de verdade e confere
## em cada travessia: chegada certa, nenhum body_entered nas saídas da sala nova, nenhuma troca
## automática depois, posição no servidor de física igual à do nó em todos os ticks desde a troca,
## Terra parada e sem controle no fade (com a direção segurada), nenhum dano no fade com uma
## Hitbox hostil ativa sobre ela, golpe cancelado, vida e instância preservadas, câmera e limites.
## Depois repete 05 ↔ 04 várias vezes e confere a persistência do Escavador.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/transition_physics_sync_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const DIR: String = "res://world/levels/depths/forgotten_galleries/"
const ROOM_01: String = DIR + "room_01_awakening.tscn"
const ROOM_02: String = DIR + "room_02_gallery.tscn"
const ROOM_03: String = DIR + "room_03_ascent.tscn"
const ROOM_04: String = DIR + "room_04_crystals.tscn"
const ROOM_05: String = DIR + "room_05_ancient_gate.tscn"
const VIEW: Vector2 = Vector2(640, 360)
const BURROWER_ID: StringName = &"crystal_burrower_01"
## Ticks observados depois do fim da transição.
const AFTER_TICKS: int = 90
## Bit da layer player_hurtbox (5).
const PLAYER_HURTBOX_MASK: int = 16

## [nome, sala de origem, ponto de partida (pés), sentido, sala de destino, chegada esperada, lado]
const CROSSINGS: Array = [
	["01 → 02", ROOM_01, Vector2(890, 320), 1.0, ROOM_02, Vector2(56, 320), 1.0],
	["02 → 03", ROOM_02, Vector2(950, 320), 1.0, ROOM_03, Vector2(56, 672), 1.0],
	["03 → 04", ROOM_03, Vector2(584, 224), 1.0, ROOM_04, Vector2(56, 320), 1.0],
	["04 → 05", ROOM_04, Vector2(820, 320), 1.0, ROOM_05, Vector2(56, 320), 1.0],
	["05 → 04", ROOM_05, Vector2(76, 320), -1.0, ROOM_04, Vector2(840, 320), -1.0],
	["04 → 03", ROOM_04, Vector2(76, 320), -1.0, ROOM_03, Vector2(584, 224), -1.0],
	["03 → 02", ROOM_03, Vector2(76, 672), -1.0, ROOM_02, Vector2(968, 320), -1.0],
	["02 → 01", ROOM_02, Vector2(76, 320), -1.0, ROOM_01, Vector2(904, 320), -1.0],
]

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _terra: PlayerCharacter
var _camera: Camera2D
var _hostile: Hitbox


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Transições: sincronia física da Terra (regressão Sala 05 → 04)")
	await process_frame
	await _new_game(ROOM_01, &"start")
	_check(_terra.disable_mode == CollisionObject2D.DISABLE_MODE_MAKE_STATIC,
		"a Game configura a Terra com DISABLE_MODE_MAKE_STATIC na inicialização")
	await _test_hostile_hitbox_works()
	_terra.get_health().take_damage(1)
	await _wait(45)
	for c: Array in CROSSINGS:
		if c[1] == ROOM_04 and c[4] == ROOM_05:
			# Antes de seguir para a Sala 05, derrota o Escavador (persistência na volta).
			var b: Enemy = _room().get_node_or_null("Enemies/CrystalBurrower") as Enemy
			if b != null:
				(b.get_node("HealthComponent") as HealthComponent).take_damage(99)
			_check(_game.call("is_enemy_defeated", ROOM_04, BURROWER_ID), "Escavador derrotado antes de 04 → 05")
		await _cross(c)
	_check(_room().get_node_or_null("Enemies") != null and _game.call("get_room_path") == ROOM_01,
		"volta completa até a Sala 01")
	await _test_repeated_05_04()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


## Controle: a Hitbox hostil do teste causa dano fora da transição (senão a verificação de
## "nenhum dano no fade" não provaria nada).
func _test_hostile_hitbox_works() -> void:
	print("-- Controle: Hitbox hostil do teste")
	await _reset(Vector2(300, 320), 1.0)
	var hp: int = _terra.get_health().current_health
	_hostile.global_position = _terra.global_position + Vector2(0, -23)
	_hostile.activate()
	await _wait(6)
	_hostile.deactivate()
	_check(_terra.get_health().current_health == hp - 1, "fora da transição, a Hitbox hostil acerta a Terra (%d → %d)" % [hp, _terra.get_health().current_health])
	_terra.get_health().restore_full()
	await _wait(45)


## Uma travessia andando, com o golpe apertado no caminho e a direção segurada no fade.
func _cross(c: Array) -> void:
	var label: String = c[0]
	print("-- %s" % label)
	_check(_game.call("get_room_path") == c[1], "%s: começa na sala de origem" % label)
	await _reset(c[2], c[3])
	var hp: int = _terra.get_health().current_health
	var terra_id: int = _terra.get_instance_id()
	var rid: RID = _terra.get_rid()
	var info: Dictionary = {"swapped": false, "pos": Vector2.INF, "busy": true, "stray": [], "damage": 0}
	var on_damaged: Callable = func(_amount: int) -> void: info.damage += 1
	_terra.get_health().damaged.connect(on_damaged)
	var on_change: Callable = func(room: Room) -> void:
		info.swapped = true
		info.pos = _terra.global_position
		info.busy = (_terra.get_node("MeleeAttack") as MeleeAttack).is_busy()
		for e: RoomExit in room.get_exits():
			e.body_entered.connect(func(b: Node2D) -> void:
				(info.stray as Array).append("%s por %s em %s" % [e.name, b.name, b.global_position]))
	_game.connect("room_changed", on_change)
	var move: String = "move_right" if c[3] > 0.0 else "move_left"
	Input.action_press(move)
	var started: bool = false
	var desync: Array[String] = []
	var moved_in_fade: bool = false
	for i: int in 600:
		if not started:
			# Golpe apertado a cada 8 ticks até a transição começar.
			if i % 8 == 0:
				Input.action_press("attack")
			elif i % 8 == 1:
				Input.action_release("attack")
		await physics_frame
		if _game.call("is_transitioning") and not started:
			started = true
			Input.action_release("attack")
			_hostile.activate()
		if started:
			# Hitbox hostil sempre sobre a Terra durante a transição.
			_hostile.global_position = _terra.global_position + Vector2(0, -23)
		if info.swapped:
			if _terra.global_position != info.pos:
				moved_in_fade = moved_in_fade or _game.call("is_transitioning")
			_check_sync(rid, desync, "fade")
		if started and not _game.call("is_transitioning"):
			break
	_hostile.deactivate()
	_release_all()
	_check(info.swapped and _game.call("get_room_path") == c[4] and info.pos == c[5] and _terra.get_facing() == c[6],
		"%s: chega em %s olhando para %s" % [label, info.pos, "a direita" if c[6] > 0.0 else "a esquerda"])
	_check(not info.busy, "%s: golpe cancelado na troca" % label)
	_check(not moved_in_fade, "%s: sem controle no fade (direção segurada, a Terra não sai da entrada)" % label)
	await _wait(AFTER_TICKS)
	_game.disconnect("room_changed", on_change)
	_terra.get_health().damaged.disconnect(on_damaged)
	_check_sync(rid, desync, "depois")
	_check((info.stray as Array).is_empty(), "%s: nenhum body_entered nas saídas da sala nova %s" % [label, info.stray])
	_check(_game.call("get_room_path") == c[4] and _terra.is_on_floor() and _terra.global_position.distance_to(c[5]) < 1.0,
		"%s: nenhuma troca automática em %d ticks; de pé na chegada" % [label, AFTER_TICKS])
	_check(desync.is_empty(), "%s: posição no servidor de física = posição do nó em todos os ticks desde a troca %s" % [label, desync.slice(0, 3)])
	_check(info.damage == 0 and _terra.get_health().current_health == hp, "%s: nenhum dano no fade com Hitbox hostil ativa (vida %d)" % [label, hp])
	_check(_terra.get_instance_id() == terra_id, "%s: mesma instância da Terra" % label)
	var bounds: Rect2i = _room().get_camera_bounds()
	var limits: Rect2i = Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
	var center: Vector2 = _camera.get_screen_center_position()
	_check(limits == bounds and center.is_equal_approx(_expected_center(_terra.global_position, bounds)),
		"%s: limites da câmera da sala nova e câmera na Terra %s" % [label, center])


func _test_repeated_05_04() -> void:
	print("-- 05 ↔ 04 repetidas (5 idas e voltas)")
	await _new_game(ROOM_04, &"west")
	(_room().get_node("Enemies/CrystalBurrower").get_node("HealthComponent") as HealthComponent).take_damage(99)
	var ok: bool = true
	var detail: String = ""
	var terra_id: int = _terra.get_instance_id()
	for n: int in 5:
		for target: Array in [[Vector2(820, 320), 1.0, ROOM_05, Vector2(56, 320)], [Vector2(76, 320), -1.0, ROOM_04, Vector2(840, 320)]]:
			await _reset(target[0], target[1])
			Input.action_press("move_right" if target[1] > 0.0 else "move_left")
			var arrival: Vector2 = await _wait_change()
			_release_all()
			await _wait(60)
			var room_ok: bool = _game.call("get_room_path") == target[2] and arrival == target[3]
			if target[2] == ROOM_04:
				room_ok = room_ok and _room().get_node_or_null("Enemies/CrystalBurrower") == null
			if not room_ok:
				ok = false
				detail += " (volta %d: %s em %s)" % [n, String(_game.call("get_room_path")).get_file(), arrival]
	_check(ok, "10 travessias seguidas sem desvio para a Sala 03, Escavador sempre derrotado%s" % detail)
	_check(_terra.get_instance_id() == terra_id and _game.call("get_defeated_enemies", ROOM_04) == [BURROWER_ID],
		"mesma Terra; registro do Escavador intacto")


# --- Auxiliares -----------------------------------------------------------------------------

## Com a Terra no espaço físico, a posição guardada no servidor tem de ser a do nó.
func _check_sync(rid: RID, desync: Array[String], phase: String) -> void:
	if not PhysicsServer2D.body_get_space(rid).is_valid():
		desync.append("%s: fora do espaço" % phase)
		return
	var server: Vector2 = (PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM) as Transform2D).origin
	if server.distance_to(_terra.global_position) > 0.01:
		desync.append("%s: servidor %s, nó %s" % [phase, server, _terra.global_position])


func _new_game(room_path: String, entrance: StringName) -> void:
	_release_all()
	if _game != null:
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	_game.set("start_room", room_path)
	_game.set("start_entrance", entrance)
	root.add_child(_game)
	_terra = _game.call("get_terra") as PlayerCharacter
	_camera = _game.get_node("Terra/Camera2D") as Camera2D
	# Hitbox hostil do teste (como a de um inimigo: sem layer, mask player_hurtbox), filha da
	# Game para atravessar as trocas de sala.
	_hostile = Hitbox.new()
	_hostile.name = "TestHostileHitbox"
	_hostile.collision_layer = 0
	_hostile.collision_mask = PLAYER_HURTBOX_MASK
	_hostile.monitorable = false
	_hostile.show_debug = false
	_hostile.damage = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(48, 64)
	shape.shape = rect
	_hostile.add_child(shape)
	_game.add_child(_hostile)
	# Desliga no mesmo instante em que a transição devolve o controle (antes do próximo tick).
	_game.connect("transition_finished", func(_swapped: bool) -> void: _hostile.deactivate())
	await _wait(2)


func _room() -> Room:
	return _game.call("get_room") as Room


## Espera a próxima troca de sala e o fim da transição; retorna a posição no instante da troca.
func _wait_change() -> Vector2:
	var info: Dictionary = {"pos": Vector2.INF}
	var on_change: Callable = func(_r: Room) -> void: info.pos = _terra.global_position
	_game.connect("room_changed", on_change)
	for i: int in 600:
		await physics_frame
		if info.pos != Vector2.INF and not _game.call("is_transitioning"):
			break
	_game.disconnect("room_changed", on_change)
	return info.pos


func _expected_center(p: Vector2, bounds: Rect2i) -> Vector2:
	return Vector2(clampf(p.x, VIEW.x / 2.0, bounds.end.x - VIEW.x / 2.0), clampf(p.y, VIEW.y / 2.0, bounds.end.y - VIEW.y / 2.0))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack", "ability"]:
		Input.action_release(action)


func _reset(position: Vector2, facing: float) -> void:
	_release_all()
	_terra.set_facing(facing)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(10)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(5)
