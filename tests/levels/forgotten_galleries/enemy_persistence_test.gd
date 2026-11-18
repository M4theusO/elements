extends SceneTree
## Teste automatizado da persistência temporária dos inimigos (Galerias Esquecidas, etapa 3):
## registro na hora da morte, inimigo derrotado não volta, ferido volta inteiro, registro por
## sala, reinício da Game, IDs repetidos/vazios/ausentes, morte durante a animação e durante a
## transição, sem sinais duplicados, Terra preservada, falhas sem corromper o registro.
## Etapa 2A (tentativas): escopo attempt/permanent da metadata persistence_scope (padrão,
## valores válidos e inválidos), escopo guardado no registro, start_new_attempt() esquecendo só
## as derrotas attempt de todas as salas, permanent preservada, sem duplicação de inimigos.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/enemy_persistence_test.gd
## Imprime erros esperados (IDs inválidos, escopos inválidos e sala inexistente). Salas de teste temporárias são
## gravadas em user:// e apagadas no fim.

const GAME_PATH: String = "res://main/game.tscn"
const ROOM_01: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const ROOM_04: String = "res://world/levels/depths/forgotten_galleries/room_04_crystals.tscn"
const FRAGMENT_PATH: String = "res://entities/enemies/living_fragment/living_fragment.tscn"
## Cópia da Sala 02 em outro caminho (mesmo ID em outra sala).
const OTHER_ROOM: String = "user://persistence_test_other_room.tscn"
## Sala 02 com inimigos de ID repetido, vazio e ausente.
const BAD_IDS_ROOM: String = "user://persistence_test_bad_ids.tscn"
## Sala 02 com mais três Fragmentos: escopo permanent, escopo inválido e escopo attempt explícito.
const SCOPE_ROOM: String = "user://persistence_test_scopes.tscn"
const FRAGMENT_ID: StringName = &"gallery_fragment_01"
const BURROWER_ID: StringName = &"crystal_burrower_01"
const GUARDIAN_ID: StringName = &"scope_guardian"
const TYPO_ID: StringName = &"scope_typo"
const EXPLICIT_ID: StringName = &"scope_explicit_attempt"
const FRAGMENT_NODE: String = "Enemies/LivingFragment"

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _terra_id: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: persistência temporária dos inimigos")
	await process_frame
	_test_source()
	_make_test_rooms()
	await _test_death_registered()
	await _test_restart()
	await _test_wounded_returns_full()
	await _test_no_duplicate_signals()
	await _test_death_during_transition()
	await _test_rooms_are_separate()
	await _test_bad_ids()
	_test_scope_reading()
	await _test_attempt_scopes()
	await _test_new_attempt_respawns()
	await _test_new_attempt_edge_cases()
	_cleanup()
	_finish()


func _finish() -> void:
	if _game != null:
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_source() -> void:
	print("-- Sem save em disco nem autoload")
	var source: String = (load("res://main/game.gd") as GDScript).source_code
	var forbidden: Array[String] = []
	for token: String in ["FileAccess", "ConfigFile", "ResourceSaver", "user://", "JSON"]:
		if source.contains(token):
			forbidden.append(token)
	_check(forbidden.is_empty(), "game.gd não grava nada em disco %s" % [forbidden])
	var autoloads: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		if String(prop.name).begins_with("autoload/"):
			autoloads.append(prop.name)
	_check(autoloads.is_empty(), "nenhum autoload no projeto %s" % [autoloads])


func _test_death_registered() -> void:
	print("-- Registro da morte, durante a animação, e retorno")
	await _new_game()
	await _go(ROOM_02, &"west")
	var fragment: LivingFragment = _fragment()
	_check(fragment != null and not _game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID), "Fragmento vivo e fora do registro ao chegar")
	var health: HealthComponent = _health(fragment)
	_terra().get_health().take_damage(1)
	await _wait(40)
	var terra_health: int = _terra().get_health().current_health
	health.take_damage(health.current_health)
	_check(_game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID) and _game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID],
		"morte registrada no mesmo instante (%s)" % [_game.call("get_defeated_enemies", ROOM_02)])
	await _wait(5)
	_check(is_instance_valid(fragment) and fragment.is_inside_tree() and fragment.get_state() == LivingFragment.State.DEAD,
		"o registro não espera a animação nem o queue_free (Fragmento ainda tocando death)")
	_check(_sprite(fragment).animation == &"death" and _sprite(fragment).is_playing(), "a animação de morte continua normalmente")
	# Sai antes de a animação terminar.
	await _go(ROOM_01, &"east")
	_check(not is_instance_valid(fragment), "saiu da sala com a animação em andamento; o Fragmento foi liberado com a sala")
	_check((_game.call("get_defeated_enemies", ROOM_01) as Array).is_empty(), "nada registrado para a Sala 01")
	await _go(ROOM_02, &"west")
	_check(_fragment() == null and _count_enemies() == 0, "de volta à Sala 02, o Fragmento derrotado não reaparece")
	_check((_game.call("get_room") as Room).get_persistent_enemies().is_empty(), "nenhum inimigo persistente na sala recarregada")
	await _go(ROOM_01, &"east")
	await _go(ROOM_02, &"west")
	_check(_fragment() == null and _game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID], "continua morto em visitas repetidas; registro sem duplicatas")
	# Sala carregada diretamente (load_room, sem transição).
	_check(_game.call("load_room", ROOM_02, &"east") and _fragment() == null, "load_room direto também respeita o registro")
	await _wait(2)
	# Falhas não corrompem o registro.
	var before: Array = _game.call("get_defeated_enemies", ROOM_02)
	var ok: bool = _game.call("request_transition", "res://world/levels/nope.tscn", &"west")
	var ok2: bool = _game.call("request_transition", ROOM_01, &"north")
	await _wait(3)
	_check(not ok and not ok2 and _game.call("get_defeated_enemies", ROOM_02) == before
		and (_game.call("get_defeated_enemies", ROOM_01) as Array).is_empty(), "transições recusadas não mexem no registro")
	_check(_terra().get_instance_id() == _terra_id and _terra().get_health().current_health == terra_health,
		"Terra preservada (mesma instância, vida %d)" % terra_health)


func _test_restart() -> void:
	print("-- Reinício da Game")
	await _new_game()
	_check((_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty(), "uma Game nova começa com o registro vazio")
	await _go(ROOM_02, &"west")
	var fragment: LivingFragment = _fragment()
	_check(fragment != null and _health(fragment).current_health == _health(fragment).max_health, "o Fragmento reaparece com vida cheia")


func _test_wounded_returns_full() -> void:
	print("-- Ferido, mas vivo")
	var fragment: LivingFragment = _fragment()
	var health: HealthComponent = _health(fragment)
	health.take_damage(health.max_health - 1)
	_check(health.current_health == 1 and not fragment.is_dead(), "Fragmento ferido (vida %d)" % health.current_health)
	await _go(ROOM_01, &"east")
	_check((_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty(), "sair da sala não registra inimigos vivos")
	await _go(ROOM_02, &"west")
	var again: LivingFragment = _fragment()
	_check(again != null and again != fragment and _health(again).current_health == _health(again).max_health
		and again.get_patrol_origin_x() == 512.0, "volta um Fragmento novo, com vida cheia, no ponto de origem")


func _test_no_duplicate_signals() -> void:
	print("-- Sem sinais duplicados")
	var counts: Array[int] = []
	for i: int in 3:
		await _go(ROOM_01, &"east")
		await _go(ROOM_02, &"west")
		counts.append(_game_connections(_health(_fragment())))
	_check(counts == [1, 1, 1], "uma única ligação da Game com a morte do Fragmento a cada visita %s" % [counts])
	var fragment: LivingFragment = _fragment()
	var calls: Array[int] = [0]
	_health(fragment).died.connect(func() -> void: calls[0] += 1)
	_health(fragment).take_damage(99)
	_health(fragment).take_damage(99)
	await _wait(2)
	_check(calls[0] == 1 and _game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID], "morte emitida e registrada uma vez")


func _test_death_during_transition() -> void:
	print("-- Morte durante a transição")
	await _new_game()
	await _go(ROOM_02, &"west")
	var room: Room = _game.call("get_room") as Room
	var fragment: LivingFragment = _fragment()
	var started: bool = _game.call("request_transition", ROOM_01, &"east")
	await process_frame
	await process_frame
	_check(started and _game.call("is_transitioning") and _game.call("get_room") == room, "no meio do fade, a Sala 02 ainda é a atual")
	_health(fragment).take_damage(99)
	_check(_game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID) and not _game.call("is_enemy_defeated", ROOM_01, FRAGMENT_ID),
		"morte durante a transição registrada na sala em que aconteceu")
	await _wait_transition_end()
	_check(_game.call("get_room_path") == ROOM_01, "a transição termina normalmente")
	await _go(ROOM_02, &"west")
	_check(_fragment() == null, "na volta, o Fragmento morto durante a transição não reaparece")


func _test_rooms_are_separate() -> void:
	print("-- Registro separado por sala")
	# Sala 02 já com o Fragmento derrotado (caso anterior). A cópia em outro caminho usa o mesmo ID.
	_check(_game.call("load_room", OTHER_ROOM, &"west"), "carrega a cópia da Sala 02 em outro caminho")
	var copy_fragment: LivingFragment = _fragment()
	_check(copy_fragment != null, "o mesmo ID em outra sala não é afetado pelo registro da Sala 02")
	_health(copy_fragment).take_damage(99)
	_check(_game.call("get_defeated_enemies", OTHER_ROOM) == [FRAGMENT_ID] and _game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID]
		and (_game.call("get_defeated_enemies", ROOM_01) as Array).is_empty(), "cada sala com o próprio registro")
	await _wait(2)


func _test_bad_ids() -> void:
	print("-- IDs repetidos, vazios e ausentes")
	await _new_game()
	_check(_game.call("load_room", BAD_IDS_ROOM, &"west"), "carrega a sala com IDs inválidos (erros esperados no console)")
	var room: Room = _game.call("get_room") as Room
	var persistent: Dictionary = room.get_persistent_enemies()
	_check(persistent.keys() == [FRAGMENT_ID], "só o ID válido é persistente (%s)" % [persistent.keys()])
	_check(_count_enemies() == 5, "os inimigos com ID inválido continuam no jogo (%d)" % _count_enemies())
	var connected: Array[String] = []
	for enemy: Node in room.get_node("Enemies").get_children():
		if _game_connections(_health(enemy as Enemy)) > 0:
			connected.append(String(enemy.name))
	_check(connected == ["LivingFragment"], "só o inimigo válido ligado ao registro %s" % [connected])
	for enemy: Node in room.get_node("Enemies").get_children():
		_health(enemy as Enemy).take_damage(99)
	var defeated: Array = _game.call("get_defeated_enemies", BAD_IDS_ROOM)
	_check(defeated == [FRAGMENT_ID] and not _game.call("is_enemy_defeated", BAD_IDS_ROOM, &"")
		and not _game.call("is_enemy_defeated", BAD_IDS_ROOM, &"dup_id"), "mortes com ID vazio ou repetido não são registradas %s" % [defeated])
	await _wait(2)
	_check(_game.call("load_room", BAD_IDS_ROOM, &"west"), "recarrega a sala")
	var names: Array[String] = []
	for enemy: Node in (_game.call("get_room") as Room).get_node("Enemies").get_children():
		names.append(String(enemy.name))
	names.sort()
	_check(names == ["DupA", "DupB", "EmptyId", "NoId"], "os de ID inválido renascem; o válido continua morto %s" % [names])


func _test_scope_reading() -> void:
	print("-- Escopo de persistência (Room.get_enemy_persistence_scope)")
	var room: Room = (load(ROOM_02) as PackedScene).instantiate() as Room
	var probe: Node = Node.new()
	probe.name = "Probe"
	_check(Room.SCOPE_ATTEMPT == &"attempt" and Room.SCOPE_PERMANENT == &"permanent"
		and Room.PERSISTENCE_SCOPE_META == &"persistence_scope", "constantes: persistence_scope, attempt e permanent")
	_check(room.get_enemy_persistence_scope(probe) == Room.SCOPE_ATTEMPT, "sem metadata: attempt")
	_check(room.get_enemy_persistence_scope(null) == Room.SCOPE_ATTEMPT, "inimigo nulo: attempt, sem erro")
	var cases: Array = [
		[&"attempt", Room.SCOPE_ATTEMPT, "StringName attempt"],
		["attempt", Room.SCOPE_ATTEMPT, "String attempt"],
		[&"permanent", Room.SCOPE_PERMANENT, "StringName permanent"],
		["permanent", Room.SCOPE_PERMANENT, "String permanent"],
		[&"boss", Room.SCOPE_ATTEMPT, "texto desconhecido (erro esperado) -> attempt"],
		["Permanent", Room.SCOPE_ATTEMPT, "maiúscula não é aceita (erro esperado) -> attempt"],
		[&"", Room.SCOPE_ATTEMPT, "vazio (erro esperado) -> attempt"],
		[1, Room.SCOPE_ATTEMPT, "número (erro esperado) -> attempt"],
		[true, Room.SCOPE_ATTEMPT, "booleano (erro esperado) -> attempt"],
	]
	for spec: Array in cases:
		probe.set_meta(Room.PERSISTENCE_SCOPE_META, spec[0])
		_check(room.get_enemy_persistence_scope(probe) == spec[1], "metadata %s" % spec[2])
	probe.free()
	var fragment: Node = room.get_node(FRAGMENT_NODE)
	_check(not fragment.has_meta(Room.PERSISTENCE_SCOPE_META) and room.get_enemy_persistence_scope(fragment) == Room.SCOPE_ATTEMPT,
		"Fragmento Vivo da Sala 02 sem metadata: attempt")
	room.free()
	var room_04: Room = (load(ROOM_04) as PackedScene).instantiate() as Room
	var burrower: Enemy = room_04.get_persistent_enemies().get(BURROWER_ID)
	_check(burrower is CrystalBurrower and not burrower.has_meta(Room.PERSISTENCE_SCOPE_META)
		and room_04.get_enemy_persistence_scope(burrower) == Room.SCOPE_ATTEMPT, "Escavador de Cristal da Sala 04 sem metadata: attempt")
	room_04.free()


func _test_attempt_scopes() -> void:
	print("-- Escopo guardado no registro, em salas diferentes")
	await _new_game()
	_check(_game.call("get_attempt") == 1, "uma Game nova começa na tentativa 1")
	await _go(ROOM_02, &"west")
	_kill(FRAGMENT_ID)
	_check(_game.call("get_defeated_enemy_scope", ROOM_02, FRAGMENT_ID) == Room.SCOPE_ATTEMPT, "Fragmento (Sala 02) registrado como attempt")
	_check(_game.call("get_defeated_enemy_scope", ROOM_02, &"nope") == &"", "inimigo não derrotado: escopo vazio")
	await _wait(2)
	_check(_game.call("load_room", ROOM_04, &"west"), "carrega a Sala 04")
	_kill(BURROWER_ID)
	_check(_game.call("get_defeated_enemy_scope", ROOM_04, BURROWER_ID) == Room.SCOPE_ATTEMPT, "Escavador (Sala 04) registrado como attempt")
	await _wait(2)
	_check(_game.call("load_room", SCOPE_ROOM, &"west"), "carrega a sala com escopos (erro esperado: escopo inválido)")
	for id: StringName in [FRAGMENT_ID, GUARDIAN_ID, TYPO_ID, EXPLICIT_ID]:
		_kill(id)
	var expected: Dictionary = {FRAGMENT_ID: Room.SCOPE_ATTEMPT, GUARDIAN_ID: Room.SCOPE_PERMANENT,
		TYPO_ID: Room.SCOPE_ATTEMPT, EXPLICIT_ID: Room.SCOPE_ATTEMPT}
	var got: Dictionary = {}
	for id: StringName in expected:
		got[id] = _game.call("get_defeated_enemy_scope", SCOPE_ROOM, id)
	_check(got == expected, "escopos registrados: sem metadata e explícito attempt, permanent, inválido -> attempt %s" % [got])
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [FRAGMENT_ID, GUARDIAN_ID, TYPO_ID, EXPLICIT_ID],
		"get_defeated_enemies continua devolvendo os IDs, em ordem de registro")
	_check(_game.call("get_attempt") == 1, "derrotas não mudam a tentativa")
	await _wait(2)
	# Mesma tentativa: ninguém volta, em nenhuma sala, por load_room ou por transição.
	_check(_game.call("load_room", SCOPE_ROOM, &"west") and _count_enemies() == 0, "mesma tentativa: sala com escopos sem inimigos")
	_check(_game.call("load_room", ROOM_04, &"west") and _enemy(BURROWER_ID) == null and _count_enemies() == 0,
		"mesma tentativa: Escavador continua derrotado")
	_check(_game.call("load_room", ROOM_01, &"east"), "volta à Sala 01")
	await _wait(2)
	await _go(ROOM_02, &"west")
	_check(_fragment() == null and _count_enemies() == 0, "mesma tentativa, por transição: Fragmento continua derrotado")


func _test_new_attempt_respawns() -> void:
	print("-- Nova tentativa: limpeza global das derrotas attempt")
	# Continua do caso anterior: Sala 02 atual, derrotas em ROOM_02, ROOM_04 e SCOPE_ROOM.
	var terra_health: int = _terra().get_health().current_health
	var removed: int = _game.call("start_new_attempt")
	_check(removed == 5 and _game.call("get_attempt") == 2, "start_new_attempt esquece 5 derrotas attempt e passa à tentativa 2 (%d)" % removed)
	_check((_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty()
		and (_game.call("get_defeated_enemies", ROOM_04) as Array).is_empty(), "Salas 02 e 04 sem derrotas")
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [GUARDIAN_ID]
		and _game.call("get_defeated_enemy_scope", SCOPE_ROOM, GUARDIAN_ID) == Room.SCOPE_PERMANENT, "a derrota permanent é preservada")
	_check(_terra().get_instance_id() == _terra_id and _terra().get_health().current_health == terra_health,
		"a Terra não é tocada (mesma instância, vida %d)" % terra_health)
	_check(_game.call("get_room_path") == ROOM_02 and _fragment() == null, "a sala atual não é recarregada pela limpeza")
	# Revisitas: cada inimigo attempt volta uma única vez, com uma única ligação ao registro.
	await _go(ROOM_01, &"east")
	await _go(ROOM_02, &"west")
	var fragment: LivingFragment = _fragment()
	_check(fragment != null and _count_enemies() == 1 and _game_connections(_health(fragment)) == 1
		and _health(fragment).current_health == _health(fragment).max_health, "Sala 02: o Fragmento volta (um só, vida cheia, uma ligação)")
	_check(_game.call("load_room", ROOM_04, &"west"), "carrega a Sala 04")
	var burrower: Enemy = _enemy(BURROWER_ID)
	_check(burrower is CrystalBurrower and _count_enemies() == 1 and _game_connections(_health(burrower)) == 1,
		"Sala 04: o Escavador volta (um só, uma ligação)")
	_check(_game.call("load_room", SCOPE_ROOM, &"west"), "carrega a sala com escopos (erro esperado: escopo inválido)")
	var names: Array[String] = _enemy_names()
	_check(names == ["Explicit", "LivingFragment", "Typo"] and _enemy(GUARDIAN_ID) == null,
		"sala com escopos: voltam os attempt (inclusive o inválido); o permanent não %s" % [names])
	# A nova tentativa registra de novo, normalmente.
	_kill(FRAGMENT_ID)
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [GUARDIAN_ID, FRAGMENT_ID], "nova derrota registrada na tentativa 2")
	await _wait(2)
	_check(_game.call("load_room", SCOPE_ROOM, &"west") and _enemy_names() == ["Explicit", "Typo"],
		"tentativa 2: o Fragmento derrotado de novo não volta")


func _test_new_attempt_edge_cases() -> void:
	print("-- Nova tentativa: casos de borda")
	# Inimigo vivo na sala atual durante a limpeza: a ligação continua e a morte entra na tentativa nova.
	var typo: Enemy = _enemy(TYPO_ID)
	_check(_game.call("start_new_attempt") == 1 and _game.call("get_attempt") == 3, "tentativa 3 (esquece 1 derrota)")
	_check(_game_connections(_health(typo)) == 1, "inimigo vivo da sala atual continua ligado ao registro")
	_kill(TYPO_ID)
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [GUARDIAN_ID, TYPO_ID], "e a morte dele é registrada normalmente")
	await _wait(2)
	# Registro só com permanent: nada a esquecer; repetir não acumula efeitos além do contador.
	_check(_game.call("start_new_attempt") == 1 and _game.call("start_new_attempt") == 0 and _game.call("get_attempt") == 5,
		"chamadas seguidas: esquece 1, depois 0; tentativa 5")
	_check(_game.call("get_defeated_enemies", SCOPE_ROOM) == [GUARDIAN_ID]
		and (_game.call("get_defeated_enemies", ROOM_02) as Array).is_empty(), "só a derrota permanent permanece")
	# Uma Game nova não herda nada (sem save): tentativa 1 e registro vazio, inclusive o permanent.
	await _new_game()
	_check(_game.call("get_attempt") == 1 and (_game.call("get_defeated_enemies", SCOPE_ROOM) as Array).is_empty(),
		"Game nova: tentativa 1 e registro vazio (permanent só em memória)")


# --- Salas temporárias ----------------------------------------------------------------------

func _make_test_rooms() -> void:
	var copy: Node = (load(ROOM_02) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_save(copy, OTHER_ROOM)
	var bad: Node = (load(ROOM_02) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var enemies: Node = bad.get_node("Enemies")
	for spec: Array in [["DupA", &"dup_id", 300.0], ["DupB", &"dup_id", 380.0], ["EmptyId", &"", 640.0], ["NoId", null, 720.0]]:
		var fragment: Node2D = (load(FRAGMENT_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		fragment.name = spec[0]
		fragment.position = Vector2(spec[2], 320.0)
		if spec[1] != null:
			fragment.set_meta(Room.PERSISTENT_ID_META, spec[1])
		enemies.add_child(fragment)
		fragment.owner = bad
	_save(bad, BAD_IDS_ROOM)
	var scoped: Node = (load(ROOM_02) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var scoped_enemies: Node = scoped.get_node("Enemies")
	for spec: Array in [["Guardian", GUARDIAN_ID, &"permanent", 300.0], ["Typo", TYPO_ID, &"permanente", 640.0],
			["Explicit", EXPLICIT_ID, "attempt", 720.0]]:
		var extra: Node2D = (load(FRAGMENT_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		extra.name = spec[0]
		extra.position = Vector2(spec[3], 320.0)
		extra.set_meta(Room.PERSISTENT_ID_META, spec[1])
		extra.set_meta(Room.PERSISTENCE_SCOPE_META, spec[2])
		scoped_enemies.add_child(extra)
		extra.owner = scoped
	_save(scoped, SCOPE_ROOM)


func _save(room: Node, path: String) -> void:
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(room)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	_check(err == OK, "sala de teste gravada em %s" % path)
	room.free()


func _cleanup() -> void:
	for path: String in [OTHER_ROOM, BAD_IDS_ROOM, SCOPE_ROOM]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Auxiliares -----------------------------------------------------------------------------

func _new_game() -> void:
	if _game != null:
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	_terra_id = _terra().get_instance_id()
	await _wait(5)


func _terra() -> PlayerCharacter:
	return _game.call("get_terra") as PlayerCharacter


func _fragment() -> LivingFragment:
	var room: Room = _game.call("get_room") as Room
	var node: Node = room.get_node_or_null(FRAGMENT_NODE)
	return node as LivingFragment if node != null and not node.is_queued_for_deletion() else null


## Inimigo persistente da sala atual pelo ID (null se não estiver lá ou estiver sendo liberado).
func _enemy(id: StringName) -> Enemy:
	var enemy: Enemy = (_game.call("get_room") as Room).get_persistent_enemies().get(id)
	return enemy if enemy != null and not enemy.is_queued_for_deletion() else null


func _kill(id: StringName) -> void:
	var enemy: Enemy = _enemy(id)
	if enemy == null:
		_check(false, "inimigo '%s' presente para ser derrotado" % id)
		return
	_health(enemy).take_damage(999)


func _enemy_names() -> Array[String]:
	var names: Array[String] = []
	for child: Node in (_game.call("get_room") as Room).get_node("Enemies").get_children():
		if child is Enemy and not child.is_queued_for_deletion():
			names.append(String(child.name))
	names.sort()
	return names


func _health(enemy: Enemy) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


func _sprite(enemy: Enemy) -> AnimatedSprite2D:
	return enemy.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D


func _count_enemies() -> int:
	var n: int = 0
	for child: Node in (_game.call("get_room") as Room).get_node("Enemies").get_children():
		if child is Enemy and not child.is_queued_for_deletion():
			n += 1
	return n


## Ligações do sinal died com a Game (o registro de mortes).
func _game_connections(health: HealthComponent) -> int:
	var n: int = 0
	for c: Dictionary in health.died.get_connections():
		if (c.callable as Callable).get_object() == _game:
			n += 1
	return n


func _go(room_path: String, entrance: StringName) -> void:
	if _game.call("request_transition", room_path, entrance):
		await _wait_transition_end()
	await _wait(5)


func _wait_transition_end() -> void:
	for i: int in 2000:
		if not _game.call("is_transitioning"):
			break
		await process_frame


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1
