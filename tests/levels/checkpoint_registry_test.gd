extends SceneTree
## Teste automatizado da arquitetura dos checkpoints (Etapa 8.1, Altares Elementais):
## ElementalAltar isolado (estado, sinais, apply_state sem activated, ponto de renascimento,
## sala), descoberta e validação pela Room (ID vazio, repetido, inexistente), registro na Game
## (ativação inicial e repetida, vários altares, um só atual, troca do atual, validação de sala e
## ID), persistência ao descarregar, recriar e atravessar portas, ausência de referências a nós,
## e independência da tentativa, dos inimigos e da vida. Nenhuma sala real recebe altares: as
## salas de teste são cópias gravadas em user:// e apagadas no fim.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/checkpoint_registry_test.gd
## Imprime erros esperados (IDs vazios/repetidos, checkpoints e salas inválidos).

const GAME_PATH: String = "res://main/game.tscn"
const ALTAR_PATH: String = "res://world/levels/_shared/elemental_altar.tscn"
const ROOM_01: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
const ROOM_02: String = "res://world/levels/depths/forgotten_galleries/room_02_gallery.tscn"
const REAL_ROOMS: Array[String] = [
	ROOM_01, ROOM_02,
	"res://world/levels/depths/forgotten_galleries/room_03_ascent.tscn",
	"res://world/levels/depths/forgotten_galleries/room_04_crystals.tscn",
	"res://world/levels/depths/forgotten_galleries/room_05_ancient_gate.tscn",
]
## Cópia da Sala 02 (com o Fragmento) + altares A e B válidos, um sem ID, dois repetidos e um
## nó que não é altar.
const ROOM_A: String = "user://checkpoint_test_room_a.tscn"
## Cópia da Sala 01 + altar C.
const ROOM_B: String = "user://checkpoint_test_room_b.tscn"
const ALTAR_A: StringName = &"altar_a"
const ALTAR_B: StringName = &"altar_b"
const ALTAR_C: StringName = &"altar_c"
const DUP_ID: StringName = &"altar_dup"
const FRAGMENT_ID: StringName = &"gallery_fragment_01"

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
## Emissões capturadas: [altar_id, first_time] por activated; [altar_id, ativado, atual] por state_changed.
var _activated_log: Array = []
var _state_log: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Checkpoints: Altares Elementais (Etapa 8.1)")
	await process_frame
	_make_test_rooms()
	_test_altar_scene_and_source()
	_test_altar_alone()
	_test_room_discovery()
	await _test_start_config()
	await _test_activation_validation()
	await _test_activation_and_switch()
	await _test_unload_and_recreate()
	await _test_no_node_references()
	await _test_attempt_and_enemies()
	await _test_refusals()
	_cleanup()
	_finish()


func _finish() -> void:
	if _game != null:
		_game.queue_free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Casos ----------------------------------------------------------------------------------

func _test_altar_scene_and_source() -> void:
	print("-- Cena e código do altar")
	var altar: ElementalAltar = (load(ALTAR_PATH) as PackedScene).instantiate() as ElementalAltar
	_check(altar != null, "elemental_altar.tscn instancia um ElementalAltar")
	_check(altar.get_node_or_null(^"Visuals") is Node2D and altar.get_node_or_null(^"SpawnPoint") is Marker2D,
		"filhos Visuals (Node2D) e SpawnPoint (Marker2D)")
	_check(altar.get_node(^"Visuals").get_child_count() == 0, "sem sprites nem animações nesta etapa")
	var areas: int = 0
	for node: Node in altar.find_children("*", "CollisionObject2D", true, false):
		areas += 1
	_check(areas == 0, "sem área de interação nem colisão nesta etapa")
	_check(altar.checkpoint_id.is_empty() and not altar.is_activated() and not altar.is_current(),
		"padrão: sem ID, não ativado, não atual")
	altar.free()
	var source: String = (load("res://world/levels/_shared/elemental_altar.gd") as GDScript).source_code
	var forbidden: Array[String] = []
	for token: String in ["PlayerCharacter", "Terra", "get_terra", "start_new_attempt", "restore_full",
			"FileAccess", "ConfigFile", "ResourceSaver", "user://", "get_tree().root"]:
		if _code_only(source).contains(token):
			forbidden.append(token)
	_check(forbidden.is_empty(), "o altar não depende da Terra, da Game, da tentativa nem de disco %s" % [forbidden])
	var game_source: String = _code_only((load("res://main/game.gd") as GDScript).source_code)
	_check(not game_source.contains("FileAccess") and not game_source.contains("ConfigFile") and not game_source.contains("user://"),
		"a Game não grava checkpoints em disco")


func _test_altar_alone() -> void:
	print("-- Altar isolado")
	var altar: ElementalAltar = _new_altar(&"solo", Vector2(100, 200), Vector2(24, 0), ElementalAltar.Facing.LEFT)
	root.add_child(altar)
	_watch(altar)
	altar.activate()
	_check(_activated_log == [[&"solo", true]], "activate() emite activated(altar, first_time = true) (%s)" % [_activated_log])
	_check(not altar.is_activated() and _state_log.is_empty(), "activate() sozinho não muda o estado (quem registra responde)")
	altar.apply_state(true, false)
	_check(altar.is_activated() and not altar.is_current() and _state_log == [[&"solo", true, false]],
		"apply_state(true, false): ativado, não atual, state_changed uma vez")
	_check(_activated_log.size() == 1, "apply_state não emite activated")
	altar.apply_state(true, false)
	_check(_state_log.size() == 1, "apply_state sem mudança não emite nada")
	altar.activate()
	_check(_activated_log.back() == [&"solo", false], "já ativado: activated com first_time = false")
	altar.apply_state(false, true)
	_check(altar.is_activated() and altar.is_current() and _state_log.back() == [&"solo", true, true],
		"atual implica ativado (apply_state(false, true) → ativado e atual)")
	altar.apply_state(false, false)
	_check(not altar.is_activated() and not altar.is_current() and _activated_log.size() == 2,
		"apply_state(false, false) zera o estado, sem activated")
	_check(altar.get_spawn_position() == Vector2(124, 200), "ponto de renascimento = SpawnPoint global (%s)" % altar.get_spawn_position())
	_check(altar.get_spawn_facing() == -1.0, "lado ao renascer: esquerda")
	_check(altar.get_room() == null and altar.get_room_path() == "", "fora de uma sala: sem sala e caminho vazio")
	altar.get_node(^"SpawnPoint").free()
	_check(altar.get_spawn_position() == Vector2(100, 200), "sem SpawnPoint: posição do altar (erro esperado)")
	altar.free()
	_clear_logs()


func _test_room_discovery() -> void:
	print("-- Descoberta e validação pela Room")
	for path: String in REAL_ROOMS:
		var real: Room = (load(path) as PackedScene).instantiate() as Room
		_check(real.get_checkpoints().is_empty() and real.get_node_or_null(^"Checkpoints") == null,
			"%s: nenhum altar nas salas existentes" % path.get_file())
		real.free()
	var room: Room = (load(ROOM_A) as PackedScene).instantiate() as Room
	var altars: Dictionary[StringName, ElementalAltar] = room.get_checkpoints()
	_check(altars.keys() == [ALTAR_A, ALTAR_B], "só os altares válidos, em ordem (%s; erros esperados: ID vazio e repetido)" % [altars.keys()])
	_check(room.has_checkpoint(ALTAR_A) and room.has_checkpoint(ALTAR_B), "has_checkpoint nos válidos")
	_check(not room.has_checkpoint(&"") and not room.has_checkpoint(DUP_ID) and not room.has_checkpoint(&"nope"),
		"has_checkpoint recusa ID vazio, repetido e inexistente")
	_check(room.get_checkpoint(ALTAR_B) == room.get_node(^"Checkpoints/AltarB"), "get_checkpoint por checkpoint_id (independe do nome do nó)")
	_check(room.get_checkpoint(DUP_ID) == null and room.get_checkpoint(&"nope") == null, "get_checkpoint: null para repetido e inexistente (erros esperados)")
	_check(altars[ALTAR_A].get_room() == room and altars[ALTAR_A].get_room_path() == ROOM_A,
		"o altar identifica a sala e o caminho dela (%s)" % altars[ALTAR_A].get_room_path())
	room.free()


func _test_start_config() -> void:
	print("-- Sala e entrada iniciais")
	await _new_game()
	_check(_game.call("get_start_room") == ROOM_01 and _game.call("get_start_entrance") == &"start",
		"configuração padrão: Sala 01, entrada start")
	_game.call("load_room", ROOM_A, &"west")
	_check(_game.call("get_room_path") == ROOM_A and _game.call("get_start_room") == ROOM_01,
		"com outra sala carregada, a sala inicial continua a configurada")
	_check(not _game.call("has_current_checkpoint") and _game.call("get_current_checkpoint_room") == ""
		and _game.call("get_current_checkpoint_id") == &"", "uma Game nova começa sem checkpoint")
	# Configuração real alterada antes de a Game entrar na árvore.
	_game.queue_free()
	await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	_game.set("start_room", ROOM_B)
	_game.set("start_entrance", &"east")
	root.add_child(_game)
	await _wait(3)
	_check(_game.call("get_start_room") == ROOM_B and _game.call("get_start_entrance") == &"east",
		"get_start_room/entrance leem start_room/start_entrance da Game")


func _test_activation_validation() -> void:
	print("-- Validação da ativação")
	await _new_game()
	_game.call("load_room", ROOM_A, &"west")
	var bad: Array = [
		["", ALTAR_A, "caminho vazio"],
		["res://world/levels/nope.tscn", ALTAR_A, "sala inexistente"],
		[ROOM_B, ALTAR_C, "outra sala (válida, mas não carregada)"],
		[ROOM_02, ALTAR_A, "sala real sem altares"],
		[ROOM_A, &"", "ID vazio"],
		[ROOM_A, &"nope", "checkpoint inexistente"],
		[ROOM_A, DUP_ID, "ID repetido (excluído pela Room)"],
	]
	for spec: Array in bad:
		var ok: bool = _game.call("activate_checkpoint", spec[0], spec[1])
		_check(not ok, "recusa: %s (erro esperado)" % spec[2])
	_check(not _game.call("has_current_checkpoint") and _registry().is_empty(), "recusas não mexem no registro")
	var room: Room = _room()
	_check(not room.get_checkpoint(ALTAR_A).is_activated() and not room.get_checkpoint(ALTAR_B).is_activated(),
		"recusas não mexem nos altares")
	# Altares fora do registro (ID vazio / repetido) pedindo ativação pela interação.
	for node_name: String in ["AltarEmpty", "AltarDupA", "AltarDupB"]:
		(room.get_node("Checkpoints/" + node_name) as ElementalAltar).activate()
	_check(_registry().is_empty() and not _game.call("has_current_checkpoint"), "altares com ID vazio ou repetido nunca entram no registro")


func _test_activation_and_switch() -> void:
	print("-- Ativação inicial, repetida, vários altares e troca do atual")
	var room: Room = _room()
	var a: ElementalAltar = room.get_checkpoint(ALTAR_A)
	var b: ElementalAltar = room.get_checkpoint(ALTAR_B)
	_watch(a)
	_watch(b)
	a.activate()
	_check(_activated_log == [[ALTAR_A, true]], "ativação inicial pela interação: activated(first_time = true)")
	_check(_game.call("is_checkpoint_activated", ROOM_A, ALTAR_A) and _game.call("is_current_checkpoint", ROOM_A, ALTAR_A),
		"registrado e atual")
	_check(_game.call("get_current_checkpoint_room") == ROOM_A and _game.call("get_current_checkpoint_id") == ALTAR_A,
		"checkpoint atual = (sala A, altar_a)")
	_check(a.is_activated() and a.is_current() and not b.is_activated() and not b.is_current(), "estado devolvido aos altares carregados")
	_check(_state_log == [[ALTAR_A, true, true]], "um state_changed só, do altar A")
	a.activate()
	_check(_activated_log.back() == [ALTAR_A, false], "ativação repetida: first_time = false")
	_check(_game.call("get_activated_checkpoints", ROOM_A) == [ALTAR_A] and _state_log.size() == 1,
		"ativação repetida não duplica o registro nem muda o estado")
	_check(_game.call("activate_checkpoint", ROOM_A, ALTAR_A), "activate_checkpoint repetido também é aceito")
	b.activate()
	_check(_game.call("get_activated_checkpoints", ROOM_A) == [ALTAR_A, ALTAR_B], "dois altares registrados, em ordem de ativação")
	_check(_game.call("is_current_checkpoint", ROOM_A, ALTAR_B) and not _game.call("is_current_checkpoint", ROOM_A, ALTAR_A),
		"o novo altar é o atual")
	_check(a.is_activated() and not a.is_current() and b.is_activated() and b.is_current(),
		"troca do atual: o anterior continua ativado, sem ser atual")
	_check(_count_current(room) == 1, "um só altar atual na sala")
	_check(_game.call("activate_checkpoint", ROOM_A, ALTAR_A) and a.is_current() and not b.is_current() and b.is_activated(),
		"reativar o anterior o torna atual de novo")
	_clear_logs()


func _test_unload_and_recreate() -> void:
	print("-- Descarregar, recriar e atravessar portas")
	var old_a: ElementalAltar = _room().get_checkpoint(ALTAR_A)
	_check(_game.call("load_room", ROOM_B, &"start"), "carrega a sala B (a sala A é descarregada)")
	await process_frame
	_check(not is_instance_valid(old_a), "os altares da sala A foram liberados com ela")
	_check(_game.call("get_activated_checkpoints", ROOM_A) == [ALTAR_A, ALTAR_B] and _game.call("is_current_checkpoint", ROOM_A, ALTAR_A),
		"registro mantido com a sala descarregada")
	var c: ElementalAltar = _room().get_checkpoint(ALTAR_C)
	_check(not c.is_activated() and not c.is_current(), "altar C chega sem estado")
	c.activate()
	_check(_game.call("is_current_checkpoint", ROOM_B, ALTAR_C) and not _game.call("is_current_checkpoint", ROOM_A, ALTAR_A)
		and _game.call("is_checkpoint_activated", ROOM_A, ALTAR_A), "atual passou para outra sala; os da sala A continuam ativados")
	_check(_game.call("load_room", ROOM_A, &"east"), "recria a sala A")
	var a: ElementalAltar = _room().get_checkpoint(ALTAR_A)
	var b: ElementalAltar = _room().get_checkpoint(ALTAR_B)
	_check(a != old_a and a.is_activated() and not a.is_current() and b.is_activated() and not b.is_current(),
		"altares recriados recebem o estado do registro (ativados, nenhum atual)")
	b.activate()
	_check(_count_current(_room()) == 1 and b.is_current(), "na sala recriada, ativar volta a funcionar")
	# Porta real (transição com fade) para a sala B e de volta.
	await _go(ROOM_B, &"start")
	_check(_game.call("get_room_path") == ROOM_B and not _room().get_checkpoint(ALTAR_C).is_current()
		and _room().get_checkpoint(ALTAR_C).is_activated(), "após a transição: C ativado e não atual")
	await _go(ROOM_A, &"west")
	_check(_room().get_checkpoint(ALTAR_B).is_current() and _room().get_checkpoint(ALTAR_A).is_activated()
		and not _room().get_checkpoint(ALTAR_A).is_current(), "de volta pela transição: B atual, A só ativado")
	_check(_room().get_checkpoint(ALTAR_A).activated.get_connections().size() == 1,
		"uma ligação só por altar (sem sinais acumulados entre visitas)")


func _test_no_node_references() -> void:
	print("-- Sem referências a nós no registro")
	var registry: Dictionary = _registry()
	var only_ids: bool = true
	for room_path: Variant in registry:
		if not room_path is String:
			only_ids = false
		for id: Variant in registry[room_path]:
			if not id is StringName or not registry[room_path][id] is bool:
				only_ids = false
	_check(only_ids and registry.size() == 2, "registro: só caminhos (String), IDs (StringName) e bool (%s)" % [registry])
	_check(_game.get("_checkpoint_room") is String and _game.get("_checkpoint_id") is StringName,
		"checkpoint atual guardado como caminho + ID")
	var found_object: bool = false
	for prop: Dictionary in (_game.get_script() as GDScript).get_script_property_list():
		var value: Variant = _game.get(prop.name)
		if value is ElementalAltar:
			found_object = true
	_check(not found_object, "nenhuma variável da Game guarda um altar")
	# Altar de uma sala já substituída, ainda não liberado (mesmo quadro): ignorado.
	var stale: ElementalAltar = _room().get_checkpoint(ALTAR_A)
	_game.call("load_room", ROOM_B, &"start")
	stale.activate()
	_check(_game.call("is_current_checkpoint", ROOM_A, ALTAR_B), "altar de sala substituída não muda o checkpoint atual")
	await process_frame
	_check(not is_instance_valid(stale) and _game.call("is_current_checkpoint", ROOM_A, ALTAR_B)
		and _game.call("get_current_checkpoint_room") == ROOM_A, "consultas continuam válidas depois de o altar ser liberado")


func _test_attempt_and_enemies() -> void:
	print("-- Tentativa, inimigos e vida")
	await _new_game()
	_game.call("load_room", ROOM_A, &"west")
	await _wait(3)
	var terra: PlayerCharacter = _game.call("get_terra")
	terra.get_health().take_damage(2)
	var hp: int = terra.get_health().current_health
	var fragment: Enemy = _room().get_persistent_enemies().get(FRAGMENT_ID)
	var fragment_health: HealthComponent = fragment.get_node(^"HealthComponent")
	fragment_health.take_damage(fragment_health.current_health)
	var attempt: int = _game.call("get_attempt")
	_check(_game.call("get_defeated_enemies", ROOM_A) == [FRAGMENT_ID], "Fragmento derrotado e registrado")
	_room().get_checkpoint(ALTAR_A).activate()
	_check(_game.call("is_current_checkpoint", ROOM_A, ALTAR_A), "altar ativado")
	_check(_game.call("get_attempt") == attempt, "a ativação não começa uma nova tentativa (tentativa %d)" % attempt)
	_check(_game.call("get_defeated_enemies", ROOM_A) == [FRAGMENT_ID] and _game.call("get_defeated_enemy_scope", ROOM_A, FRAGMENT_ID) == Room.SCOPE_ATTEMPT,
		"a ativação não restaura inimigos nem mexe no escopo")
	_check(terra.get_health().current_health == hp, "a ativação não restaura vida nesta etapa (%d)" % hp)
	_room().get_checkpoint(ALTAR_A).activate()
	_check(_game.call("get_defeated_enemies", ROOM_A) == [FRAGMENT_ID] and _game.call("get_attempt") == attempt,
		"reutilizar o altar também não restaura inimigos")
	_game.call("load_room", ROOM_A, &"west")
	_check(_room().get_persistent_enemies().is_empty(), "recarregando a sala, o Fragmento continua derrotado")
	var removed: int = _game.call("start_new_attempt")
	_check(removed == 1 and (_game.call("get_defeated_enemies", ROOM_A) as Array).is_empty(), "start_new_attempt continua esquecendo as derrotas attempt")
	_check(_game.call("is_current_checkpoint", ROOM_A, ALTAR_A) and _game.call("get_activated_checkpoints", ROOM_A) == [ALTAR_A],
		"uma nova tentativa não apaga os checkpoints")


func _test_refusals() -> void:
	print("-- Ativação recusada durante transição e com a Terra morta")
	await _new_game()
	_game.call("load_room", ROOM_A, &"west")
	await _wait(3)
	_check(_game.call("request_transition", ROOM_B, &"start"), "transição pedida")
	var during: bool = _game.call("activate_checkpoint", ROOM_A, ALTAR_A)
	_check(not during and not _game.call("has_current_checkpoint"), "recusada durante a transição")
	await _wait_transition_end()
	await _wait(3)
	var terra: PlayerCharacter = _game.call("get_terra")
	terra.get_health().take_damage(terra.get_health().current_health)
	var c: ElementalAltar = _room().get_checkpoint(ALTAR_C)
	c.activate()
	_check(not _game.call("has_current_checkpoint") and not c.is_activated(), "recusada com a Terra morta (altar sem estado)")
	_check(not _game.call("activate_checkpoint", ROOM_B, ALTAR_C), "activate_checkpoint direto também é recusado")


# --- Salas de teste -------------------------------------------------------------------------

func _make_test_rooms() -> void:
	var room_a: Node = (load(ROOM_02) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var holder_a: Node2D = _add_checkpoints_node(room_a)
	for spec: Array in [["AltarA", ALTAR_A, 200.0, ElementalAltar.Facing.RIGHT], ["AltarB", ALTAR_B, 800.0, ElementalAltar.Facing.LEFT],
			["AltarEmpty", &"", 400.0, ElementalAltar.Facing.RIGHT], ["AltarDupA", DUP_ID, 600.0, ElementalAltar.Facing.RIGHT],
			["AltarDupB", DUP_ID, 700.0, ElementalAltar.Facing.RIGHT]]:
		var altar: ElementalAltar = (load(ALTAR_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as ElementalAltar
		altar.name = spec[0]
		altar.checkpoint_id = spec[1]
		altar.position = Vector2(spec[2], 320.0)
		altar.spawn_facing = spec[3]
		holder_a.add_child(altar)
		altar.owner = room_a
	var not_altar: Node2D = Node2D.new()
	not_altar.name = "NotAnAltar"
	holder_a.add_child(not_altar)
	not_altar.owner = room_a
	_save(room_a, ROOM_A)
	var room_b: Node = (load(ROOM_01) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var altar_c: ElementalAltar = (load(ALTAR_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as ElementalAltar
	altar_c.name = "AltarC"
	altar_c.checkpoint_id = ALTAR_C
	altar_c.position = Vector2(300.0, 320.0)
	_add_checkpoints_node(room_b).add_child(altar_c)
	altar_c.owner = room_b
	_save(room_b, ROOM_B)


## Checkpoints entre Props e Enemies (ordem de desenho prevista na Room).
func _add_checkpoints_node(room: Node) -> Node2D:
	var holder: Node2D = Node2D.new()
	holder.name = "Checkpoints"
	room.add_child(holder)
	room.move_child(holder, room.get_node("Enemies").get_index())
	holder.owner = room
	return holder


func _save(room: Node, path: String) -> void:
	var packed: PackedScene = PackedScene.new()
	packed.pack(room)
	ResourceSaver.save(packed, path)
	room.free()


func _cleanup() -> void:
	for path: String in [ROOM_A, ROOM_B]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Auxiliares -----------------------------------------------------------------------------

func _new_altar(id: StringName, at: Vector2, spawn_offset: Vector2, facing: ElementalAltar.Facing) -> ElementalAltar:
	var altar: ElementalAltar = (load(ALTAR_PATH) as PackedScene).instantiate() as ElementalAltar
	altar.checkpoint_id = id
	altar.position = at
	altar.spawn_facing = facing
	(altar.get_node(^"SpawnPoint") as Marker2D).position = spawn_offset
	return altar


func _watch(altar: ElementalAltar) -> void:
	altar.activated.connect(func(emitter: ElementalAltar, first_time: bool) -> void:
		_activated_log.append([emitter.checkpoint_id, first_time]))
	altar.state_changed.connect(func(is_activated: bool, is_current: bool) -> void:
		_state_log.append([altar.checkpoint_id, is_activated, is_current]))


func _clear_logs() -> void:
	_activated_log.clear()
	_state_log.clear()


func _count_current(room: Room) -> int:
	var count: int = 0
	for altar: ElementalAltar in room.get_checkpoints().values():
		if altar.is_current():
			count += 1
	return count


func _registry() -> Dictionary:
	return _game.get("_activated_checkpoints")


func _room() -> Room:
	return _game.call("get_room") as Room


## Código sem comentários (os comentários podem citar a Terra).
func _code_only(source: String) -> String:
	var lines: PackedStringArray = []
	for line: String in source.split("\n"):
		var cut: int = line.find("#")
		lines.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(lines)


func _new_game() -> void:
	if _game != null:
		_game.queue_free()
		await process_frame
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	await _wait(5)


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
