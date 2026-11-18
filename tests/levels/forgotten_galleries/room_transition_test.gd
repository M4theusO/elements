extends SceneTree
## Teste automatizado das transições entre salas (Galerias Esquecidas, etapa 2): RoomExit,
## Game.request_transition e as Salas 01 e 02. Ida e volta caminhando, vida e instância da
## Terra preservadas, posição e orientação na chegada, câmera, fade, sem loop, um pedido por
## vez, falhas seguras, golpe/Punho Sísmico/pulo interrompidos na porta e inimigos sem acesso.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/room_transition_test.gd
## Os testes de falha segura imprimem erros esperados ("Game: sala ... não encontrada" etc.).

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_01: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const ROOM_03: String = "res://world/levels/depths/forgotten_galleries/room_03_ascent.tscn"
const ROOM_04: String = "res://world/levels/depths/forgotten_galleries/room_04_crystals.tscn"
const ROOM_05: String = "res://world/levels/depths/forgotten_galleries/room_05_ancient_gate.tscn"
const NOT_A_ROOM: String = "res://tests/movement_lab/movement_lab.tscn"
const DUMMY_PATH: String = "res://entities/enemies/training_dummy/training_dummy.tscn"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"

const VIEW: Vector2 = Vector2(640, 360)
const FLOOR_Y: float = 320.0
const ROOM_01_EAST: Vector2 = Vector2(904, 320)
const ROOM_02_WEST: Vector2 = Vector2(56, 320)
const ROOM_01_BOUNDS: Rect2i = Rect2i(0, 0, 960, 368)
const ROOM_02_BOUNDS: Rect2i = Rect2i(0, 0, 1024, 368)
## Perto da porta leste da Sala 01, ainda fora da área da saída (que começa em x 928).
const NEAR_EAST_DOOR: Vector2 = Vector2(890, 320)
## Boneco de treino posto à frente da chegada em west, dentro do alcance do soco da Terra.
const DUMMY_AT_ARRIVAL: Vector2 = Vector2(78, 320)
const TERRA_SIZE: Vector2 = Vector2(16, 46)
const FIST_COOLDOWN_TICKS: int = 95
## Duração de cada metade do fade na Game.
const FADE_TIME: float = 0.15

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _terra: PlayerCharacter
var _camera: Camera2D
var _fade: ColorRect
var _melee: MeleeAttack
var _fist: SeismicFist
var _changes: int = 0
var _terra_id: int = 0
var _spawn_dummy: bool = false
var _dummy: Node2D
## Pose da Terra no instante da troca de sala (sinal room_changed).
var _arrival: Vector2
var _arrival_facing: float = 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: transições entre salas")
	await process_frame
	_test_exit_config()
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	_game.connect("room_changed", _on_room_changed)
	_terra = _game.call("get_terra") as PlayerCharacter
	_camera = _game.get_node("Terra/Camera2D") as Camera2D
	_fade = _game.get_node("Fade/ColorRect") as ColorRect
	_melee = _terra.get_node("MeleeAttack") as MeleeAttack
	_fist = _terra.get_node("SeismicFist") as SeismicFist
	_terra_id = _terra.get_instance_id()
	await _wait(10)
	_check(_room_path() == ROOM_01 and _camera.process_mode == Node.PROCESS_MODE_ALWAYS,
		"começa na Sala 01; a câmera continua atualizando com a Terra pausada")
	await _test_walk_east()
	await _test_walk_back_west()
	await _test_single_request()
	await _test_failures()
	await _test_basic_attack()
	await _test_seismic_fist()
	await _test_jump()
	await _test_enemies_cannot_trigger()
	await _test_dead_terra()
	_finish()


func _finish() -> void:
	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração ---------------------------------------------------------------------------

func _test_exit_config() -> void:
	print("-- Saídas e entradas")
	# Cada sala: [nome da saída, sala de destino, entrada de destino].
	var expected: Dictionary = {
		ROOM_01: [[&"East", ROOM_02, &"west"]],
		ROOM_02: [[&"West", ROOM_01, &"east"], [&"East", ROOM_03, &"west"]],
		ROOM_03: [[&"West", ROOM_02, &"east"], [&"East", ROOM_04, &"west"]],
		ROOM_04: [[&"West", ROOM_03, &"east"], [&"East", ROOM_05, &"west"]],
		ROOM_05: [[&"West", ROOM_04, &"east"]],
	}
	for path: String in expected:
		var room: Room = (load(path) as PackedScene).instantiate() as Room
		var exits: Array[RoomExit] = room.get_exits()
		var specs: Array = expected[path]
		var names: Array[StringName] = []
		for e: RoomExit in exits:
			names.append(e.name)
		var want: Array[StringName] = []
		for spec: Array in specs:
			want.append(spec[0])
		_check(names == want, "%s: saídas %s" % [path.get_file(), want])
		if names != want:
			room.free()
			continue
		for i: int in exits.size():
			var e: RoomExit = exits[i]
			var spec: Array = specs[i]
			_check(e.collision_layer == 0 and e.collision_mask == 4 and e.monitoring and not e.monitorable,
				"%s/%s: layer 0, mask só player (3), monitoring ligado, monitorable desligado" % [path.get_file(), e.name])
			_check(e.target_room == spec[1] and e.target_entry == spec[2], "%s → %s (%s)" % [e.name, spec[1].get_file(), spec[2]])
			var target: Room = (load(e.target_room) as PackedScene).instantiate() as Room
			_check(target != null and target.has_entrance(e.target_entry), "o destino existe e tem a entrada %s" % e.target_entry)
			if target != null:
				target.free()
			var shape: RectangleShape2D = (e.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
			var area: Rect2 = Rect2(e.position - shape.size / 2.0, shape.size)
			var clear: bool = true
			for marker: Node in room.get_node("Entrances").get_children():
				var body: Rect2 = Rect2((marker as Marker2D).position - Vector2(TERRA_SIZE.x / 2.0, TERRA_SIZE.y), TERRA_SIZE)
				clear = clear and not body.grow(4.0).intersects(area)
			_check(clear, "%s/%s: nenhuma entrada da sala fica dentro (ou a menos de 4 px) da área da saída" % [path.get_file(), e.name])
		room.free()


# --- Ida e volta caminhando -----------------------------------------------------------------

func _test_walk_east() -> void:
	print("-- Ida 01 → 02 caminhando")
	_terra.get_health().take_damage(2)
	await _wait(40)
	var health: int = _terra.get_health().current_health
	_check(health == 3, "Terra ferida antes da porta (vida %d)" % health)
	var old_room: Room = _game.call("get_room") as Room
	await _reset(NEAR_EAST_DOOR, 1.0)
	var before: int = _changes
	Input.action_press("move_right")
	var started: bool = await _wait_until_transitioning(120)
	_check(started, "entrar na saída leste pede a transição")
	var info: Dictionary = await _wait_transition_end()
	_check(info.locked_samples > 0 and info.locked,
		"durante a troca a Terra fica sem controle e parada (%d quadros conferidos)" % info.locked_samples)
	# Ainda com a direita pressionada: chegou e já pode andar para dentro da sala.
	_check(_room_path() == ROOM_02 and _changes == before + 1, "chega à Sala 02 com uma única troca")
	_check(info.arrival.distance_to(ROOM_02_WEST) < 0.01 and info.facing == 1.0,
		"chega em west %s olhando para a direita (pos %s)" % [ROOM_02_WEST, info.arrival])
	_check(info.max_alpha >= 0.99 and info.seconds >= 2.0 * FADE_TIME - 0.02 and info.seconds <= 1.5,
		"fade até o preto e de volta (pico %.2f; %.3f s, ~2 × 0,15 s)" % [info.max_alpha, info.seconds])
	_check(not _fade.visible and _fade.modulate.a == 0.0, "fade invisível no fim")
	_check(_terra.process_mode == Node.PROCESS_MODE_INHERIT, "controle devolvido à Terra")
	_check(_terra.get_instance_id() == _terra_id and _terra.get_parent() == _game and _count_players() == 1,
		"mesma instância da Terra, ainda filha da Game, única na árvore")
	_check(_terra.get_health().current_health == health, "vida preservada (%d)" % _terra.get_health().current_health)
	_check(_camera_limits() == ROOM_02_BOUNDS, "limites da câmera = Sala 02")
	await _wait(2)
	_check(not is_instance_valid(old_room), "a Sala 01 anterior foi liberada")
	_check(_room_slot_count() == 1, "RoomSlot com uma única sala")
	await _check_camera_inside(ROOM_02_BOUNDS, "chegada na Sala 02")
	_check(not _inside_any_exit(), "a Terra não está dentro de nenhuma saída ao chegar")
	await _wait(40)
	Input.action_release("move_right")
	await _wait(60)
	_check(_changes == before + 1 and _room_path() == ROOM_02, "sem transição de volta em loop (andando e parada)")
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5 and _terra.global_position.x > ROOM_02_WEST.x,
		"andou para dentro da Sala 02 no chão (x %.1f)" % _terra.global_position.x)


func _test_walk_back_west() -> void:
	print("-- Volta 02 → 01 caminhando")
	await _reset(ROOM_02_WEST, 1.0)
	var before: int = _changes
	var health: int = _terra.get_health().current_health
	Input.action_press("move_left")
	var ticks: int = 0
	while not _game.call("is_transitioning") and ticks < 120:
		await physics_frame
		ticks += 1
	_check(_game.call("is_transitioning") and ticks <= 20, "voltando logo pela esquerda, pede a transição em %d ticks" % ticks)
	var info: Dictionary = await _wait_transition_end()
	Input.action_release("move_left")
	_check(_room_path() == ROOM_01 and _changes == before + 1, "volta à Sala 01 com uma única troca")
	_check(info.arrival.distance_to(ROOM_01_EAST) < 0.01 and info.facing == -1.0,
		"chega em east %s olhando para a esquerda (pos %s)" % [ROOM_01_EAST, info.arrival])
	_check(_terra.get_health().current_health == health and _terra.get_instance_id() == _terra_id,
		"mesma Terra, vida preservada (%d)" % health)
	_check(_camera_limits() == ROOM_01_BOUNDS, "limites da câmera = Sala 01")
	await _check_camera_inside(ROOM_01_BOUNDS, "chegada na Sala 01")
	await _wait(60)
	_check(_changes == before + 1 and not _inside_any_exit(), "sem loop na chegada à Sala 01")
	# Fragmento da Sala 02 reiniciado com a sala (persistência é da etapa 3).
	await _go(ROOM_02, &"west")
	var fragment: LivingFragment = (_game.call("get_room") as Room).get_node("Enemies/LivingFragment") as LivingFragment
	var fragment_health: HealthComponent = fragment.get_node("HealthComponent") as HealthComponent if fragment != null else null
	_check(fragment != null and fragment.get_patrol_origin_x() == 512.0 and absf(fragment.position.x - 512.0) <= fragment.patrol_distance
		and fragment_health.current_health == fragment_health.max_health,
		"a Sala 02 recarregada tem o Fragmento novo, com vida cheia, patrulhando a partir de x 512")
	await _go(ROOM_01, &"east")


func _test_single_request() -> void:
	print("-- Um pedido por vez")
	var before: int = _changes
	var first: bool = _game.call("request_transition", ROOM_02, &"west")
	var second: bool = _game.call("request_transition", ROOM_02, &"west")
	await process_frame
	var third: bool = _game.call("request_transition", ROOM_01, &"east")
	_check(first and not second and not third, "pedidos durante a transição são ignorados (%s, %s, %s)" % [first, second, third])
	await _wait_transition_end()
	await _wait(10)
	_check(_changes == before + 1 and _room_path() == ROOM_02 and _room_slot_count() == 1, "uma única troca")
	await _go(ROOM_01, &"east")


func _test_failures() -> void:
	print("-- Falha segura")
	await _reset(ROOM_01_EAST, -1.0)
	var room: Room = _game.call("get_room") as Room
	var before: int = _changes
	var cases: Array = [["sala inexistente", "res://world/levels/nope.tscn", &"west"],
		["entrada inexistente", ROOM_02, &"north"], ["cena que não é Room", NOT_A_ROOM, &"start"],
		["caminho vazio", "", &"west"]]
	for c: Array in cases:
		var ok: bool = _game.call("request_transition", c[1], c[2])
		await _wait(3)
		_check(not ok and _game.call("get_room") == room and not _game.call("is_transitioning")
			and _terra.process_mode == Node.PROCESS_MODE_INHERIT and not _fade.visible and _changes == before,
			"%s: recusada, sala atual, controle e fade intactos" % c[0])
	var ok_load: bool = _game.call("load_room", ROOM_02, &"north")
	_check(not ok_load and _game.call("get_room") == room, "load_room com entrada inexistente também mantém a sala")
	_check(_room_slot_count() == 1 and _count_players() == 1, "nenhuma sala ou Terra extra criada nas falhas")
	var x0: float = _terra.global_position.x
	Input.action_press("move_left")
	await _wait(10)
	Input.action_release("move_left")
	_check(_terra.global_position.x < x0 - 5.0, "a Terra continua controlável depois das falhas")


func _test_basic_attack() -> void:
	print("-- Transição durante o ataque básico")
	_check(not _melee.cancel(), "MeleeAttack.cancel() sem golpe em andamento não faz nada")
	for phase: String in ["preparação", "fase ativa"]:
		await _go(ROOM_01, &"east")
		await _reset(NEAR_EAST_DOOR, 1.0)
		await _press("attack")
		if phase == "fase ativa":
			for i: int in 20:
				if _melee.hitbox.is_active():
					break
				await physics_frame
		var striking: bool = _melee.is_striking() and (phase == "preparação") != _melee.hitbox.is_active()
		_check(striking, "golpe em %s no momento da porta" % phase)
		_spawn_dummy = true
		_game.call("request_transition", ROOM_02, &"west")
		await _wait_transition_end()
		_check(not _melee.is_busy() and not _melee.hitbox.is_active(), "%s: golpe cancelado, sem recuperação pendente" % phase)
		await _wait(2)
		_check(not _melee.hitbox.monitoring and _active_terra_hitboxes() == 0, "%s: nenhuma hitbox da Terra ativa" % phase)
		var dummy_health: HealthComponent = _dummy.get_node("HealthComponent") as HealthComponent
		await _wait(30)
		_check(dummy_health.current_health == dummy_health.max_health,
			"%s: o golpe não atravessa a porta (boneco à frente da chegada intacto)" % phase)
		# Controle: o mesmo boneco é atingido por um golpe novo, depois da chegada.
		await _press("attack")
		await _wait(20)
		_check(dummy_health.current_health == dummy_health.max_health - 1, "%s: depois da chegada o soco funciona (vida do boneco %d)" % [phase, dummy_health.current_health])
		await _wait(20)


func _test_seismic_fist() -> void:
	print("-- Transição durante o Punho Sísmico")
	for phase: String in ["preparação", "onda lançada"]:
		await _go(ROOM_01, &"east")
		await _reset(NEAR_EAST_DOOR - Vector2(40, 0), 1.0)
		await _wait(FIST_COOLDOWN_TICKS)
		await _press("ability")
		if phase == "onda lançada":
			for i: int in 30:
				if not _fist.is_casting():
					break
				await physics_frame
			await _wait(3)
		var state_ok: bool = _fist.is_casting() if phase == "preparação" else (not _fist.is_casting() and _waves() > 0)
		_check(state_ok, "Punho Sísmico em %s no momento da porta (%d onda[s])" % [phase, _waves()])
		_spawn_dummy = true
		_game.call("request_transition", ROOM_02, &"west")
		await _wait_transition_end()
		await _wait(2)
		_check(not _fist.is_casting() and _waves() == 0, "%s: habilidade cancelada, nenhuma onda atravessa a porta" % phase)
		_check(_active_terra_hitboxes() == 0, "%s: nenhuma hitbox da Terra ativa" % phase)
		var dummy_health: HealthComponent = _dummy.get_node("HealthComponent") as HealthComponent
		await _wait(40)
		_check(dummy_health.current_health == dummy_health.max_health, "%s: boneco à frente da chegada intacto" % phase)


func _test_jump() -> void:
	print("-- Transição durante o pulo")
	await _go(ROOM_01, &"east")
	await _reset(NEAR_EAST_DOOR, 1.0)
	Input.action_press("jump")
	await _wait(6)
	_check(not _terra.is_on_floor() and _terra.velocity.y < 0.0, "subindo no momento da porta")
	_game.call("request_transition", ROOM_02, &"west")
	await _wait_transition_end()
	var min_y: float = INF
	for i: int in 30:
		await physics_frame
		min_y = minf(min_y, _terra.global_position.y)
	Input.action_release("jump")
	_check(min_y >= FLOOR_Y - 0.5 and _terra.is_on_floor(), "o pulo não atravessa a porta: chega no chão e não sobe (menor y %.1f)" % min_y)


func _test_enemies_cannot_trigger() -> void:
	print("-- Inimigos não acionam saídas")
	await _go(ROOM_01, &"east")
	await _reset(Vector2(200, FLOOR_Y), 1.0)
	var room: Room = _game.call("get_room") as Room
	var room_exit: RoomExit = room.get_exits()[0]
	var requests: Array[int] = [0]
	room_exit.transition_requested.connect(func(_r: String, _e: StringName) -> void: requests[0] += 1)
	var before: int = _changes
	var fragment: LivingFragment = (load(FRAGMENT_PATH) as PackedScene).instantiate() as LivingFragment
	fragment.position = Vector2(944, 320)
	room.get_node("Enemies").add_child(fragment)
	await _wait(60)
	_check(requests[0] == 0 and _changes == before and _game.call("get_room") == room,
		"Fragmento Vivo dentro da área da saída não pede transição")
	room_exit.call("_on_body_entered", fragment)
	_check(requests[0] == 0, "mesmo chamado direto, a saída ignora corpos que não são a Terra")
	fragment.queue_free()
	await _wait(2)


func _test_dead_terra() -> void:
	print("-- Terra morta")
	_terra.get_health().take_damage(_terra.get_health().current_health)
	await _wait(5)
	var ok: bool = _game.call("request_transition", ROOM_02, &"west")
	_check(not ok and not _game.call("is_transitioning"), "com a Terra morta, a transição é recusada")


# --- Auxiliares ---------------------------------------------------------------------------

func _on_room_changed(room: Room) -> void:
	_changes += 1
	_arrival = _terra.global_position
	_arrival_facing = _terra.get_facing()
	if _spawn_dummy:
		_spawn_dummy = false
		_dummy = (load(DUMMY_PATH) as PackedScene).instantiate() as Node2D
		_dummy.position = DUMMY_AT_ARRIVAL
		room.get_node("Enemies").add_child(_dummy)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _room_path() -> String:
	return _game.call("get_room_path")


func _room_slot_count() -> int:
	return _game.get_node("RoomSlot").get_child_count()


func _camera_limits() -> Rect2i:
	return Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
		_camera.limit_bottom - _camera.limit_top)


func _check_camera_inside(bounds: Rect2i, label: String) -> void:
	await process_frame
	await process_frame
	var view: Rect2 = Rect2(_camera.get_screen_center_position() - VIEW / 2.0, VIEW)
	_check(view.position.x >= -0.001 and view.position.y >= -0.001 and view.end.x <= bounds.end.x + 0.001
		and view.end.y <= bounds.end.y + 0.001, "%s: a câmera mostra só a sala %s" % [label, view])


func _inside_any_exit() -> bool:
	var body: Rect2 = Rect2(_terra.global_position - Vector2(TERRA_SIZE.x / 2.0, TERRA_SIZE.y), TERRA_SIZE)
	for e: RoomExit in (_game.call("get_room") as Room).get_exits():
		var shape: RectangleShape2D = (e.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
		if body.intersects(Rect2(e.global_position - shape.size / 2.0, shape.size)):
			return true
	return false


func _count_players() -> int:
	return _count_in(root)


func _count_in(node: Node) -> int:
	var n: int = 1 if node is PlayerCharacter else 0
	for child: Node in node.get_children():
		n += _count_in(child)
	return n


func _waves() -> int:
	var n: int = 0
	for child: Node in _terra.get_children():
		if child is SeismicWave and not child.is_queued_for_deletion():
			n += 1
	return n


func _active_terra_hitboxes() -> int:
	var n: int = 0
	for hb: Node in _terra.find_children("*", "Hitbox", true, false):
		if (hb as Hitbox).is_active() or (hb as Hitbox).monitoring:
			n += 1
	return n


func _wait_until_transitioning(max_ticks: int) -> bool:
	for i: int in max_ticks:
		if _game.call("is_transitioning"):
			return true
		await physics_frame
	return _game.call("is_transitioning")


## Espera o fim da transição; registra o pico do fade, a duração e a pose no instante da troca.
## A duração soma o delta dos quadros de processo (o mesmo tempo que move o tween do fade); em
## headless ele não acompanha o relógio de parede.
func _wait_transition_end() -> Dictionary:
	var elapsed: float = 0.0
	var max_alpha: float = 0.0
	var locked: bool = true
	var locked_samples: int = 0
	for i: int in 2000:
		if not _game.call("is_transitioning"):
			break
		if _fade.visible:
			max_alpha = maxf(max_alpha, _fade.modulate.a)
		await process_frame
		elapsed += root.get_process_delta_time()
		# A partir do primeiro quadro (o início é adiado para o fim do quadro do pedido).
		if i > 0 and _game.call("is_transitioning"):
			locked = locked and _terra.process_mode == Node.PROCESS_MODE_DISABLED and _terra.velocity == Vector2.ZERO
			locked_samples += 1
	return {"seconds": elapsed, "max_alpha": max_alpha, "locked": locked, "locked_samples": locked_samples,
		"arrival": _arrival, "facing": _arrival_facing}


## Troca de sala direto (para preparar os casos), esperando o fim.
func _go(room_path: String, entrance: StringName) -> void:
	_release_all()
	if _room_path() != room_path:
		_game.call("request_transition", room_path, entrance)
		await _wait_transition_end()
	await _wait(5)


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
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
