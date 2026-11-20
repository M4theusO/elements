extends SceneTree
## Teste de integração completo das Galerias Esquecidas (Etapa 7.2): uma única instância real de
## main/game.tscn percorre as Salas 01 → 05 e volta até a 01, com a Terra, os inimigos, a física,
## o combate, as transições, a câmera, a persistência, a morte, o Game Over e o retry reais.
##
## Estratégia (sem teleporte no percurso principal, sem load_room, sem mexer no registro da Game
## nem na vida dos inimigos):
## - Andar: a direção fica segurada e a Terra pula sempre que encosta numa parede estando no chão
##   (degraus, blocos, pilares); cada porta é atravessada andando até a RoomExit.
## - Sala 03 (subida): rotina determinística dos 14 saltos (anda até 10 px da borda de cada
##   superfície e pula com o botão segurado), a mesma validada em room_03_ascent_test.gd.
## - Sala 03 (descida): sem pular, anda e vira ao encostar numa parede (como um jogador descendo);
##   no chão, pula o degrau S1 para chegar à saída de baixo.
## - Combates reativos, guiados pelo estado do inimigo: o Fragmento Vivo é golpeado (soco real)
##   quando chega perto; contra o Escavador, a Terra sobe no pilar oeste, a investida para na face
##   do pilar (STUNNED), a Terra desce por trás e golpeia durante o atordoamento, e repete.
## - Morte na Sala 05 pela API pública de dano do HealthComponent (a sala não tem inimigos); o
##   "Tentar novamente" é confirmado com a ação jump, como o jogador. Sem checkpoint, a Terra
##   renasce na Sala 01, entrada start (Etapa 8.3).
## - Fase G (retorno 05 → 01), cenário independente: como o renascimento leva à Sala 01, a fase
##   começa com uma única preparação explícita, load_room(Sala 05, west) — a única exceção à regra
##   "sem load_room" —, e depois faz o percurso de volta inteiro andando, como antes.
## Um monitor por quadro (process_frame) confere a câmera (dentro dos limites e acompanhando a
## Terra), nenhum Game Over indevido e a instância única da Terra durante todo o fluxo.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/forgotten_galleries/galleries_full_flow_test.gd

const GAME_PATH: String = "res://main/game.tscn"
const DIR: String = "res://world/levels/depths/forgotten_galleries/"
const ROOM_01: String = DIR + "room_01_awakening.tscn"
const ROOM_02: String = DIR + "room_02_gallery.tscn"
const ROOM_03: String = DIR + "room_03_ascent.tscn"
const ROOM_04: String = DIR + "room_04_crystals.tscn"
const ROOM_05: String = DIR + "room_05_ancient_gate.tscn"
const FRAGMENT_NODE: String = "Enemies/LivingFragment"
const FRAGMENT_ID: StringName = &"gallery_fragment_01"
const BURROWER_NODE: String = "Enemies/CrystalBurrower"
const BURROWER_ID: StringName = &"crystal_burrower_01"
const VIEW: Vector2 = Vector2(640, 360)
const TERRA_HALF_WIDTH: float = 8.0
## Alcance para golpear: o soco cobre de 8 a 28 px à frente do centro da Terra.
const PUNCH_REACH: float = 30.0

## Sala 03: superfícies (Rect2(x inicial, topo, largura, 0)) e o caminho dos 14 saltos.
const R3_FLOOR: Rect2 = Rect2(32, 672, 96, 0)
const R3_PATH: Array = [
	[Rect2(32, 672, 96, 0), 640.0, 1.0], [Rect2(128, 640, 64, 0), 608.0, 1.0], [Rect2(224, 608, 64, 0), 576.0, 1.0],
	[Rect2(320, 576, 64, 0), 544.0, 1.0], [Rect2(416, 544, 64, 0), 512.0, 1.0],
	[Rect2(512, 512, 96, 0), 480.0, -1.0], [Rect2(416, 480, 64, 0), 448.0, -1.0], [Rect2(320, 448, 64, 0), 416.0, -1.0],
	[Rect2(224, 416, 64, 0), 384.0, -1.0], [Rect2(128, 384, 64, 0), 352.0, -1.0],
	[Rect2(32, 352, 64, 0), 320.0, 1.0], [Rect2(128, 320, 64, 0), 288.0, 1.0], [Rect2(224, 288, 64, 0), 256.0, 1.0],
	[Rect2(320, 256, 64, 0), 224.0, 1.0],
]
## Sala 04: pilar oeste e o topo dele.
const PILLAR_WEST: Rect2 = Rect2(288, 288, 32, 32)
const PILLAR_TOP_Y: float = 288.0
const ARENA_FLOOR_Y: float = 320.0
## Sala 05: onde a Terra para encostada no portão (sobre a soleira, na face do pilar da arte).
const GATE_STOP: Vector2 = Vector2(544, 308)

var _failures: int = 0
var _checks: int = 0
var _game: Node2D
var _terra: PlayerCharacter
var _camera: Camera2D
var _terra_id: int = 0
## Monitor por quadro.
var _monitor: Dictionary = {"frames": 0, "camera_out": [], "camera_lag": [], "game_over_opened": 0, "terra_count_bad": false}
var _game_over_allowed: bool = false
## Trocas de sala: caminhos, na ordem; e o estado das ações da Terra em cada troca.
var _changes: Array[String] = []
var _dirty_swaps: Array[String] = []
## Salas já substituídas (referência fraca): todas têm de ter sido liberadas.
var _old_rooms: Array[WeakRef] = []
var _current_room: WeakRef


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Galerias Esquecidas: fluxo completo (Etapa 7.2)")
	await process_frame
	await _phase_a_start()
	await _phase_b_room_02()
	await _phase_c_room_03_climb()
	await _phase_d_room_04()
	await _phase_e_room_05()
	await _phase_f_death_and_retry()
	await _phase_g_return()
	_final_checks()
	_finish()


func _finish() -> void:
	_release_all()
	if process_frame.is_connected(_on_frame):
		process_frame.disconnect(_on_frame)
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	if _game != null and is_instance_valid(_game):
		_game.free()
	quit(1 if _failures > 0 else 0)


# --- Fases ------------------------------------------------------------------------------------

func _phase_a_start() -> void:
	print("-- Fase A: início")
	_game = (load(GAME_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_game)
	_terra = _game.call("get_terra") as PlayerCharacter
	_camera = _game.get_node("Terra/Camera2D") as Camera2D
	_terra_id = _terra.get_instance_id()
	_game.connect("room_changed", _on_room_changed)
	process_frame.connect(_on_frame)
	await _wait(5)
	_check(_game.call("get_room_path") == ROOM_01 and _game.call("get_respawn_entrance") == &"start", "sala inicial: Sala 01, entrada start")
	_check(not _terra.is_dead() and _terra.get_health().current_health == _terra.get_health().max_health, "Terra viva, com vida cheia")
	_check(_camera_limits() == (_room().get_camera_bounds()) and _camera.is_current(), "câmera atual, com os limites da Sala 01")
	_check(_count_games() == 1 and _count_terras() == 1, "uma Game e uma Terra na árvore")


func _phase_b_room_02() -> void:
	print("-- Fase B: Sala 01 → Sala 02 e o Fragmento Vivo")
	var arrived: bool = await _walk_to_next_room(1.0, ROOM_02, 3000)
	_check(arrived and _terra.global_position.distance_to(Vector2(56, 320)) < 0.6, "Sala 01 atravessada andando; chega à Sala 02 pela entrada west")
	await _no_auto_exit()
	var fragment: Enemy = _room().get_node_or_null(FRAGMENT_NODE) as Enemy
	_check(fragment != null and not fragment.is_dead(), "Fragmento Vivo presente e vivo")
	if fragment == null:
		return
	var hp_before: int = _terra.get_health().current_health
	var result: Dictionary = await _fight_fragment(fragment)
	_check(result.dead and result.hits >= 3, "Fragmento derrotado com o soco real (%d golpe(s) aceitos, %d ticks)" % [result.hits, result.ticks])
	_check(_game.call("is_enemy_defeated", ROOM_02, FRAGMENT_ID) and _game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID],
		"morte do Fragmento registrada")
	_check(not _terra.is_dead() and _terra.get_instance_id() == _terra_id,
		"Terra viva (vida %d → %d) e a mesma instância" % [hp_before, _terra.get_health().current_health])
	var to_03: bool = await _walk_to_next_room(1.0, ROOM_03, 2400)
	_check(to_03, "Sala 02 atravessada andando até a saída leste")


func _phase_c_room_03_climb() -> void:
	print("-- Fase C: Sala 03, subida")
	_check(_game.call("get_room_path") == ROOM_03 and _terra.global_position.distance_to(Vector2(56, 672)) < 0.6, "chega à Sala 03 pela entrada de baixo (56, 672)")
	await _no_auto_exit()
	var start_center: Vector2 = _camera.get_screen_center_position()
	var steps: int = 0
	for step: Array in R3_PATH:
		var landed: bool = await _run_to_edge_and_jump(step[0], step[2])
		if not landed or absf(_terra.global_position.y - float(step[1])) > 0.5:
			break
		steps += 1
	_check(steps == R3_PATH.size(), "sobe os 14 saltos com física real, sem teleporte (%d de %d; pés em y %.0f)" % [steps, R3_PATH.size(), _terra.global_position.y])
	var top_center: Vector2 = _camera.get_screen_center_position()
	_check(start_center.y > top_center.y + 300.0 and absf(top_center.y - _terra.global_position.y) < 1.0,
		"a câmera acompanhou a subida (centro y %.0f → %.0f)" % [start_center.y, top_center.y])
	var to_04: bool = await _walk_to_next_room(1.0, ROOM_04, 600)
	_check(to_04, "alcança a saída de cima e atravessa para a Sala 04")


func _phase_d_room_04() -> void:
	print("-- Fase D: Sala 04 e o Escavador de Cristal")
	_check(_terra.global_position.distance_to(Vector2(56, 320)) < 0.6, "chega à Sala 04 pela entrada west, embaixo")
	await _no_auto_exit()
	var burrower: CrystalBurrower = _room().get_node_or_null(BURROWER_NODE) as CrystalBurrower
	_check(burrower != null and not burrower.is_dead(), "Escavador presente e vivo")
	if burrower == null:
		return
	var result: Dictionary = await _fight_burrower(burrower)
	_check(result.charges >= 1, "provoca a investida (%d preparação(ões))" % result.charges)
	_check(result.pillar_stops >= 1, "a investida para na face do pilar oeste (%d vez(es), x %.1f)" % [result.pillar_stops, result.stop_x])
	_check(result.stunned_hits >= 1, "golpeia durante o atordoamento (%d golpe(s) com dano)" % result.stunned_hits)
	_check(result.dead, "Escavador derrotado com o soco real (%d ticks)" % result.ticks)
	_check(_game.call("is_enemy_defeated", ROOM_04, BURROWER_ID) and _game.call("get_defeated_enemies", ROOM_04) == [BURROWER_ID],
		"morte do Escavador registrada")
	_check(not _terra.is_dead() and _terra.get_instance_id() == _terra_id, "Terra viva (vida %d) e a mesma instância" % _terra.get_health().current_health)
	var to_05: bool = await _walk_to_next_room(1.0, ROOM_05, 3000)
	_check(to_05, "Sala 04 atravessada andando até a saída leste")


func _phase_e_room_05() -> void:
	print("-- Fase E: Sala 05 e o Portão Antigo")
	_check(_terra.global_position.distance_to(Vector2(56, 320)) < 0.6 and _terra.get_facing() == 1.0, "chega à Sala 05 pela entrada west, olhando para a direita")
	await _no_auto_exit()
	var result: Dictionary = await _walk_until_stalled(1.0, 1200)
	_check(result.pos.distance_to(GATE_STOP) < 0.6 and result.max_x <= GATE_STOP.x + 0.5,
		"caminha até o portão e para encostada nele (%s)" % result.pos)
	Input.action_press("move_right")
	var max_x: float = -INF
	for i: int in 240:
		if i % 40 == 0:
			Input.action_press("jump")
		elif i % 40 == 20:
			Input.action_release("jump")
		await physics_frame
		max_x = maxf(max_x, _terra.global_position.x)
	_release_all()
	await _wait(40)
	_check(max_x <= GATE_STOP.x + 0.5 and _game.call("get_room_path") == ROOM_05 and not _game.call("is_transitioning"),
		"4 s insistindo e pulando: não atravessa o portão, nenhuma transição (x máx. %.1f)" % max_x)
	_check(_room().get_exits().size() == 1 and _room().get_exits()[0].target_room == ROOM_04, "a única saída da Sala 05 volta à Sala 04")
	_check(_camera_limits() == Rect2i(0, 0, 768, 368), "limites da câmera da Sala 05 (768x368)")


func _phase_f_death_and_retry() -> void:
	print("-- Fase F: morte e retry na Sala 05")
	var go: GameOverScreen = _game.call("get_game_over_screen") as GameOverScreen
	var restarted: Array[int] = [0]
	var restart_pos: Array[Vector2] = [Vector2.INF]
	_game.connect("attempt_restarted", func(_a: int) -> void:
		restarted[0] += 1
		restart_pos[0] = _terra.global_position)
	var died: Array[bool] = [false]
	_terra.death_finished.connect(func() -> void: died[0] = true, CONNECT_ONE_SHOT)
	_game_over_allowed = true
	_terra.get_health().take_damage(_terra.get_health().current_health)
	for i: int in 600:
		if go.is_open() and go.is_accepting_input():
			break
		await process_frame
	_check(died[0] and go.is_open() and paused and _game.call("is_game_over"), "a Terra morre; Game Over aberto, mundo pausado")
	# Confirma com jump (evento de entrada real, como o teclado ou o controle geram) e insiste mais
	# 3 vezes enquanto o reinício escurece (o Game Over ainda aberto): só um pode valer. Depois para,
	# para nenhum aperto chegar à Terra quando o controle voltar.
	var attempt_before: int = _game.call("get_attempt")
	var presses: int = 0
	var extra: int = 0
	for i: int in 600:
		if restarted[0] > 0 or extra >= 3:
			break
		if i % 6 == 0:
			_send_action(&"jump", true)
			presses += 1
			if _game.call("is_retrying"):
				extra += 1
		elif i % 6 == 3:
			_send_action(&"jump", false)
		await process_frame
	_send_action(&"jump", false)
	for i: int in 600:
		if restarted[0] > 0:
			break
		await process_frame
	await _wait(10)
	_game_over_allowed = false
	_check(restarted[0] == 1 and _game.call("get_attempt") == attempt_before + 1 and presses >= 2,
		"retry pelo fluxo real: um único reinício (%d confirmação(ões) apertadas)" % presses)
	# Etapa 8.3: sem checkpoint, renasce na sala e entrada iniciais (Sala 01, start), não na sala da morte.
	var start: Vector2 = _room().get_entrance(&"start").global_position if _room().has_entrance(&"start") else Vector2.INF
	_check(_game.call("get_room_path") == ROOM_01 and restart_pos[0].distance_to(start) < 0.6
		and _terra.global_position.distance_to(start) < 0.6 and _terra.is_on_floor(),
		"morte na Sala 05 sem checkpoint: renasce na Sala 01, entrada start, de pé (%s no reinício; %s depois)" % [restart_pos[0], _terra.global_position])
	_check(_terra.get_health().current_health == _terra.get_health().max_health and not _terra.is_dead(), "vida restaurada")
	_check(_terra.get_hurtbox().is_invulnerable() and not paused and not go.is_open(), "invulnerabilidade temporária; mundo rodando; Game Over fechado")
	_check(_count_games() == 1 and _count_terras() == 1 and _terra.get_instance_id() == _terra_id, "sem duplicação de Game nem de Terra; mesma instância")
	_check(_game.call("get_defeated_enemies", ROOM_02) == [FRAGMENT_ID] and _game.call("get_defeated_enemies", ROOM_04) == [BURROWER_ID],
		"registro das Salas 02 e 04 preservado")


func _phase_g_return() -> void:
	print("-- Fase G: retorno (cenário independente a partir da Sala 05)")
	# Preparação (única exceção ao "sem load_room"): depois do renascimento na Sala 01, volta à
	# entrada west da Sala 05 para refazer o retorno inteiro andando.
	var before: int = _changes.size()
	_check(_game.call("load_room", ROOM_05, &"west") and _changes.size() == before + 1
		and _terra.global_position.distance_to(Vector2(56, 320)) < 0.6, "preparação: Sala 05, entrada west")
	await _wait(5)
	var to_04: bool = await _walk_to_next_room(-1.0, ROOM_04, 600)
	_check(to_04 and _terra.global_position.distance_to(Vector2(840, 320)) < 0.6, "Sala 05 → 04, chegada pela entrada east")
	await _no_auto_exit()
	_check(_room().get_node_or_null(BURROWER_NODE) == null and _count_enemies() == 0, "o Escavador continua derrotado")
	var to_03: bool = await _walk_to_next_room(-1.0, ROOM_03, 3000)
	_check(to_03 and _terra.global_position.distance_to(Vector2(584, 224)) < 0.6, "Sala 04 → 03, chegada em cima (entrada east)")
	await _no_auto_exit()
	var descent: Dictionary = await _descend_room_03()
	_check(descent.floor, "desce a Sala 03 andando, sem pular, até o chão (pousos %s, %d viradas)" % [descent.landings, descent.turns])
	_check(descent.monotonic, "cada pouso fica mais baixo que o anterior")
	var to_02: bool = await _walk_to_next_room(-1.0, ROOM_02, 1200)
	_check(to_02 and _terra.global_position.distance_to(Vector2(968, 320)) < 0.6, "Sala 03 → 02 pela saída de baixo, chegada pela entrada east")
	await _no_auto_exit()
	_check(_room().get_node_or_null(FRAGMENT_NODE) == null and _count_enemies() == 0, "o Fragmento Vivo continua derrotado")
	var to_01: bool = await _walk_to_next_room(-1.0, ROOM_01, 2400)
	_check(to_01 and _terra.global_position.distance_to(Vector2(904, 320)) < 0.6, "Sala 02 → 01, chegada pela entrada east")
	await _no_auto_exit()
	var end: Dictionary = await _walk_until_stalled(-1.0, 3000)
	_check(absf(end.pos.x - 40.0) < 0.6 and absf(end.pos.y - 320.0) < 0.6, "atravessa a Sala 01 andando até a parede oeste (%s)" % end.pos)
	# Terra funcional: pula, golpeia e anda.
	var y0: float = _terra.global_position.y
	Input.action_press("jump")
	var min_y: float = y0
	for i: int in 60:
		await physics_frame
		min_y = minf(min_y, _terra.global_position.y)
	Input.action_release("jump")
	await _wait(40)
	await _tap("attack")
	var striking: bool = (_terra.get_node("MeleeAttack") as MeleeAttack).is_busy()
	await _wait(40)
	Input.action_press("move_right")
	await _wait(30)
	Input.action_release("move_right")
	_check(min_y < y0 - 40.0 and striking and _terra.global_position.x > 60.0 and _terra.is_on_floor() and not _terra.is_dead(),
		"Terra funcional no fim: pula (%.0f px), golpeia e anda" % (y0 - min_y))


func _final_checks() -> void:
	print("-- Verificações do fluxo inteiro")
	# Reinício na Sala 01 (Etapa 8.3) e a preparação da fase G (Sala 05).
	var expected: Array[String] = [ROOM_02, ROOM_03, ROOM_04, ROOM_05, ROOM_01, ROOM_05, ROOM_04, ROOM_03, ROOM_02, ROOM_01]
	var names: Array[String] = []
	for p: String in _changes:
		names.append(p.get_file().get_basename())
	_check(_changes == expected, "trocas de sala na ordem esperada, nenhuma duplicada (8 portas + 1 reinício + 1 preparação): %s" % [names])
	_check(_dirty_swaps.is_empty(), "em toda troca: golpe parado, hitbox desligada, nenhum efeito lançado, sala anterior liberada %s" % [_dirty_swaps])
	_check((_monitor.camera_out as Array).is_empty(), "câmera nunca mostrou fora dos limites da sala (%d quadros) %s" % [_monitor.frames, (_monitor.camera_out as Array).slice(0, 3)])
	_check((_monitor.camera_lag as Array).is_empty(), "câmera acompanhou a Terra em todos os quadros fora de transição e pausa %s" % [(_monitor.camera_lag as Array).slice(0, 3)])
	_check(not _monitor.terra_count_bad and _terra.get_instance_id() == _terra_id, "uma única Terra, a mesma instância, do começo ao fim")
	var alive: int = 0
	for ref: WeakRef in _old_rooms:
		alive += 1 if ref.get_ref() != null else 0
	_check(_old_rooms.size() == 9 and alive == 0 and _current_room.get_ref() == _room(),
		"as 9 salas substituídas foram liberadas (%d ainda existem); só a atual continua" % alive)
	_check(_game.call("get_attempt") == 2 and not _game.call("is_game_over"), "uma única morte no fluxo (tentativa 2), sem Game Over pendente")


# --- Movimento --------------------------------------------------------------------------------

## Anda no sentido dir (pulando ao encostar numa parede) até a próxima troca de sala terminar.
## Retorna se chegou à sala esperada.
func _walk_to_next_room(dir: float, expected_room: String, max_ticks: int) -> bool:
	var before: int = _changes.size()
	var move: String = "move_right" if dir > 0.0 else "move_left"
	_release_all()
	Input.action_press(move)
	var jumping: int = 0
	for i: int in max_ticks:
		await physics_frame
		if _changes.size() > before:
			break
		if jumping > 0:
			jumping -= 1
			if jumping == 0:
				Input.action_release("jump")
		elif _terra.is_on_floor() and _terra.is_on_wall():
			Input.action_press("jump")
			jumping = 20
	_release_all()
	for i: int in 120:
		if not _game.call("is_transitioning"):
			break
		await process_frame
	await physics_frame
	return _changes.size() == before + 1 and _game.call("get_room_path") == expected_room


## Anda pulando paredes até não avançar mais. Retorna a posição final e o x máximo.
func _walk_until_stalled(dir: float, max_ticks: int) -> Dictionary:
	var move: String = "move_right" if dir > 0.0 else "move_left"
	_release_all()
	Input.action_press(move)
	var max_x: float = -INF
	var last_x: float = _terra.global_position.x
	var still: int = 0
	var jumping: int = 0
	for i: int in max_ticks:
		await physics_frame
		max_x = maxf(max_x, _terra.global_position.x)
		if jumping > 0:
			jumping -= 1
			if jumping == 0:
				Input.action_release("jump")
		elif _terra.is_on_floor() and _terra.is_on_wall():
			Input.action_press("jump")
			jumping = 20
		# Parada = x sem mudar por 90 ticks (pode estar pulando contra a parede nesse tempo).
		still = still + 1 if absf(_terra.global_position.x - last_x) < 0.01 else 0
		last_x = _terra.global_position.x
		if still > 90:
			break
	_release_all()
	for i: int in 120:
		if _terra.is_on_floor():
			break
		await physics_frame
	await _wait(5)
	return {"pos": _terra.global_position, "max_x": max_x}


## Sala 03: anda até 10 px da borda da superfície src e pula; retorna se pousou.
func _run_to_edge_and_jump(src: Rect2, dir: float) -> bool:
	var edge: float = src.end.x if dir > 0.0 else src.position.x
	var move: String = "move_right" if dir > 0.0 else "move_left"
	_release_all()
	Input.action_press(move)
	var jumped: bool = false
	var left_ground: bool = false
	for i: int in 400:
		await physics_frame
		var lead: float = _terra.global_position.x + TERRA_HALF_WIDTH * dir
		if not jumped:
			if (lead - (edge - 10.0 * dir)) * dir >= 0.0 or _terra.is_on_wall():
				Input.action_press("jump")
				jumped = true
			continue
		left_ground = left_ground or not _terra.is_on_floor()
		if left_ground and _terra.is_on_floor():
			_release_all()
			return true
	_release_all()
	return false


## Sala 03, do alto até o chão sem pular: anda e vira ao encostar numa parede.
func _descend_room_03() -> Dictionary:
	var dir: float = -1.0
	var turns: int = 0
	var landings: Array[int] = []
	var monotonic: bool = true
	Input.action_press("move_left")
	for i: int in 3600:
		await physics_frame
		if _terra.is_on_floor() and absf(_terra.global_position.y - R3_FLOOR.position.y) < 0.5:
			break
		if _terra.is_on_floor() and (landings.is_empty() or landings[-1] != int(_terra.global_position.y)):
			if not landings.is_empty() and int(_terra.global_position.y) < landings[-1]:
				monotonic = false
			landings.append(int(_terra.global_position.y))
		if _terra.is_on_floor() and _terra.is_on_wall():
			Input.action_release("move_left" if dir < 0.0 else "move_right")
			dir = -dir
			turns += 1
			Input.action_press("move_left" if dir < 0.0 else "move_right")
	_release_all()
	return {"floor": absf(_terra.global_position.y - R3_FLOOR.position.y) < 0.5 and _terra.is_on_floor(),
		"landings": landings, "turns": turns, "monotonic": monotonic}


# --- Combate ----------------------------------------------------------------------------------

## Avança até o Fragmento chegar perto e golpeia (soco real) quando ele está ao alcance, virando
## para ele se preciso. Retorna se morreu, golpes aceitos e ticks.
func _fight_fragment(fragment: Enemy) -> Dictionary:
	var health: HealthComponent = fragment.get_node("HealthComponent") as HealthComponent
	var hits: Array[int] = [0]
	var hurtbox: Hurtbox = fragment.get_node("Hurtbox") as Hurtbox
	var on_hit: Callable = func(_d: int) -> void: hits[0] += 1
	hurtbox.hit_received.connect(on_hit)
	var melee: MeleeAttack = _terra.get_node("MeleeAttack") as MeleeAttack
	var pressed: bool = false
	var jumping: int = 0
	var ticks: int = 0
	_release_all()
	for i: int in 1800:
		ticks = i
		if health.is_dead() or _terra.is_dead():
			break
		var dx: float = fragment.global_position.x - _terra.global_position.x
		var toward: float = signf(dx) if absf(dx) > 0.5 else _terra.get_facing()
		_release_move()
		# Pulo segurado por 20 ticks (um toque curto não vence a elevação, por causa do pulo variável).
		if jumping > 0:
			jumping -= 1
			if jumping == 0:
				Input.action_release("jump")
		if pressed:
			Input.action_release("attack")
			pressed = false
		elif absf(dx) > PUNCH_REACH - 4.0 and not melee.is_striking():
			# Fora do alcance: anda até ele (pulando a elevação, se encostar).
			Input.action_press("move_right" if toward > 0.0 else "move_left")
			if _terra.is_on_floor() and _terra.is_on_wall() and jumping == 0:
				Input.action_press("jump")
				jumping = 20
		elif _terra.get_facing() != toward and not melee.is_striking():
			# Virado para o outro lado: um toque na direção dele.
			Input.action_press("move_right" if toward > 0.0 else "move_left")
		elif absf(dx) <= PUNCH_REACH and not melee.is_busy():
			Input.action_press("attack")
			pressed = true
		await physics_frame
	_release_all()
	if hurtbox.hit_received.is_connected(on_hit):
		hurtbox.hit_received.disconnect(on_hit)
	await _wait(5)
	return {"dead": health.is_dead(), "hits": hits[0], "ticks": ticks}


## Contra o Escavador: sobe no pilar oeste, espera a investida bater no pilar, desce por trás e
## golpeia no atordoamento; repete até a derrota.
func _fight_burrower(burrower: CrystalBurrower) -> Dictionary:
	var health: HealthComponent = burrower.get_node("HealthComponent") as HealthComponent
	var melee: MeleeAttack = _terra.get_node("MeleeAttack") as MeleeAttack
	var result: Dictionary = {"charges": 0, "pillar_stops": 0, "stop_x": 0.0, "stunned_hits": 0, "dead": false, "ticks": 0}
	var on_damaged: Callable = func(_a: int) -> void:
		if burrower.get_state() == CrystalBurrower.State.STUNNED:
			result.stunned_hits += 1
	health.damaged.connect(on_damaged)
	var last_state: int = -1
	var pressed: bool = false
	_release_all()
	for i: int in 7200:
		result.ticks = i
		if health.is_dead() or _terra.is_dead():
			break
		var state: int = burrower.get_state()
		if state != last_state:
			if state == CrystalBurrower.State.CHARGE:
				result.charges += 1
			if state == CrystalBurrower.State.STUNNED and burrower.is_on_wall() \
					and absf(burrower.global_position.x - (PILLAR_WEST.end.x + 16.0)) < 0.6:
				result.pillar_stops += 1
				result.stop_x = burrower.global_position.x
			last_state = state
		var on_pillar: bool = _terra.is_on_floor() and absf(_terra.global_position.y - PILLAR_TOP_Y) < 0.5 \
			and _terra.global_position.x > PILLAR_WEST.position.x and _terra.global_position.x < PILLAR_WEST.end.x
		_release_move()
		if pressed:
			Input.action_release("attack")
			pressed = false
		elif state == CrystalBurrower.State.STUNNED:
			# Desce e vai para trás dele (lado oposto ao que ele olha), vira e golpeia.
			var f: float = burrower.get_facing()
			var target_x: float = burrower.global_position.x - 20.0 * f
			var dx: float = target_x - _terra.global_position.x
			if absf(dx) > 3.0 and not melee.is_striking():
				Input.action_press("move_right" if dx > 0.0 else "move_left")
			elif _terra.get_facing() != f and not melee.is_striking():
				Input.action_press("move_right" if f > 0.0 else "move_left")
			elif _terra.is_on_floor() and not melee.is_busy():
				Input.action_press("attack")
				pressed = true
		elif not on_pillar:
			# Vai para o pilar oeste: da entrada, para a direita (pula a elevação e o pilar); da arena,
			# para a esquerda, pulando ao encostar na face do pilar ou ao ver a preparação.
			var x: float = _terra.global_position.x
			if x < PILLAR_WEST.position.x + 8.0:
				Input.action_press("move_right")
			elif x > PILLAR_WEST.end.x - 8.0:
				Input.action_press("move_left")
			if _terra.is_on_floor() and (_terra.is_on_wall() or (state == CrystalBurrower.State.CHARGE and x > PILLAR_WEST.end.x)):
				Input.action_press("jump")
			elif _terra.is_on_floor():
				Input.action_release("jump")
		else:
			# No pilar: parada, esperando a investida.
			Input.action_release("jump")
		await physics_frame
	_release_all()
	health.damaged.disconnect(on_damaged)
	result.dead = health.is_dead()
	await _wait(60)
	return result


# --- Monitor e trocas -------------------------------------------------------------------------

func _on_frame() -> void:
	if _game == null or not is_instance_valid(_game) or not _game.is_inside_tree():
		return
	_monitor.frames += 1
	if _count_terras() != 1:
		_monitor.terra_count_bad = true
	var go: GameOverScreen = _game.call("get_game_over_screen") as GameOverScreen
	if go.is_open() and not _game_over_allowed:
		_monitor.game_over_opened += 1
		(_monitor.camera_out as Array).append("Game Over indevido")
	var room: Room = _game.call("get_room") as Room
	if room == null or not is_instance_valid(room):
		return
	var bounds: Rect2i = room.get_camera_bounds()
	var center: Vector2 = _camera.get_screen_center_position()
	var view: Rect2 = Rect2(center - VIEW / 2.0, VIEW)
	if not Rect2(bounds).grow(0.001).encloses(view):
		(_monitor.camera_out as Array).append("%s: %s" % [room.scene_file_path.get_file(), view])
	if not _game.call("is_transitioning") and not _game.call("is_retrying") and not paused:
		var p: Vector2 = _terra.global_position
		var expected: Vector2 = Vector2(clampf(p.x, VIEW.x / 2.0, bounds.end.x - VIEW.x / 2.0), clampf(p.y, VIEW.y / 2.0, bounds.end.y - VIEW.y / 2.0))
		if center.distance_to(expected) > 0.5:
			(_monitor.camera_lag as Array).append("%s: centro %s, esperado %s" % [room.scene_file_path.get_file(), center, expected])


func _on_room_changed(room: Room) -> void:
	_changes.append(room.scene_file_path)
	if _current_room != null:
		_old_rooms.append(_current_room)
	_current_room = weakref(room)
	var melee: MeleeAttack = _terra.get_node("MeleeAttack") as MeleeAttack
	var problems: Array[String] = []
	if melee.is_busy():
		problems.append("golpe em andamento")
	if melee.hitbox.is_active():
		problems.append("hitbox ativa")
	for child: Node in _terra.get_children():
		if child is Hitbox and (child as Hitbox).top_level and not child.is_queued_for_deletion():
			problems.append("efeito lançado %s" % child.name)
	if _room_slot_count() != 1:
		problems.append("%d salas no RoomSlot" % _room_slot_count())
	if not problems.is_empty():
		_dirty_swaps.append("%s: %s" % [room.scene_file_path.get_file(), problems])


## Depois de chegar: 40 ticks parada, sem nenhuma troca nova.
func _no_auto_exit() -> void:
	var before: int = _changes.size()
	var room: Room = _room()
	await _wait(40)
	_check(_changes.size() == before and _room() == room and is_instance_valid(room), "nenhuma saída acionada sozinha depois da chegada (%s)" % room.scene_file_path.get_file())


# --- Auxiliares -----------------------------------------------------------------------------

func _room() -> Room:
	return _game.call("get_room") as Room


func _room_slot_count() -> int:
	return _game.get_node("RoomSlot").get_child_count()


func _count_enemies() -> int:
	return _room().get_node("Enemies").get_child_count()


func _count_games() -> int:
	var n: int = 0
	for child: Node in root.get_children():
		if child.scene_file_path == GAME_PATH:
			n += 1
	return n


func _count_terras() -> int:
	var n: int = 0
	for child: Node in _game.get_children():
		if child is PlayerCharacter:
			n += 1
	for child: Node in _room().get_children() if _room() != null and is_instance_valid(_room()) else []:
		if child is PlayerCharacter:
			n += 1
	return n


func _camera_limits() -> Rect2i:
	return Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left,
		_camera.limit_bottom - _camera.limit_top)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


## Evento de ação real (passa por _unhandled_input, como o teclado ou o controle).
func _send_action(action: StringName, pressed_state: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed_state
	Input.parse_input_event(event)


func _release_move() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack", "ability"]:
		Input.action_release(action)
