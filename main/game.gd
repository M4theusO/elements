extends Node2D
## Cena persistente do jogo: carrega a sala atual em RoomSlot, posiciona a Terra (instância
## única, nunca recriada nem trocada de pai) numa entrada e aplica os limites da câmera.
## As saídas das salas (RoomExit) pedem a troca; a Game valida o destino e faz a transição
## com fade, sem recriar a Terra (vida, componentes e recargas continuam os mesmos).
## Lembra, só em memória e só nesta sessão, os inimigos persistentes já derrotados de cada sala:
## eles não voltam quando a sala é recarregada; os vivos voltam inteiros, no ponto de origem.
## Cada derrota guarda o escopo do inimigo (Room.get_enemy_persistence_scope()): uma nova
## tentativa (start_new_attempt()) esquece as derrotas "attempt" e mantém as "permanent"; no
## reinício após a morte, só as da sala onde a Terra morreu (as outras salas continuam como estão).
## Morte da Terra: a HUD (PlayerHud, camada 5, abaixo do fade) mostra a vida da Terra persistente;
## quando a animação de morte termina (death_finished), a Game pausa o mundo e abre a
## GameOverScreen (camada 20, funciona pausada). "Tentar novamente" (retry_requested) reinicia a
## tentativa: escurece com o mundo pausado, começa uma nova tentativa (inimigos attempt da sala da
## morte), carrega a sala de renascimento (a do checkpoint atual, ou start_room), faz a Terra
## renascer no altar (ou em start_entrance) e clareia, tudo com o mundo pausado; no fim do
## clarear, Terra e inimigos voltam juntos (e a invulnerabilidade de renascimento começa a contar).
## Transições: a Hurtbox da Terra fica bloqueada do pedido até a volta do controle (ver
## request_transition() e _run_transition()).
## Checkpoints (Altares Elementais): a Game guarda, só em memória e só por identificadores
## (caminho da sala + checkpoint_id), os altares já ativados e o checkpoint de renascimento atual
## (um só). Ao carregar uma sala, devolve o estado a cada altar (ElementalAltar.apply_state()).
## Ativar um altar não começa tentativa nem mexe nos inimigos; pela interação (sinal activated
## do altar), a ativação aceita recupera toda a vida da Terra. O reinício renasce no SpawnPoint
## do altar atual (ver _run_retry()).

signal room_changed(room: Room)
## Reinício concluído: Terra viva, no controle, mundo rodando e tela clara.
signal attempt_restarted(attempt: int)
## Fim de uma transição (controle devolvido). swapped = false quando foi cancelada antes da troca.
signal transition_finished(swapped: bool)

## Duração de cada metade do fade (escurecer e clarear).
const FADE_TIME: float = 0.15

## Sala carregada ao iniciar.
@export_file("*.tscn") var start_room: String = "res://world/levels/depths/forgotten_galleries/room_01_awakening.tscn"
## Entrada (Marker2D em Entrances) onde a Terra começa.
@export var start_entrance: StringName = &"start"

var _room: Room
var _room_path: String = ""
var _transitioning: bool = false
## Inimigos derrotados: { caminho da sala: { persistent_id: escopo (Room.SCOPE_*) } }.
## Registro único da Game, para os dois escopos; some com a Game (sem save).
var _defeated_enemies: Dictionary[String, Dictionary] = {}
## Número da tentativa atual (a primeira é 1).
var _attempt: int = 1
## Verdadeiro enquanto a árvore estiver pausada pela Game (Game Over e começo do reinício).
var _paused_world: bool = false
## Entrada pela qual a Terra chegou à sala atual (&"" depois de renascer num altar).
var _entrance_id: StringName = &""
## Verdadeiro do "Tentar novamente" aceito até o fim do reinício.
var _retrying: bool = false
## Altares já ativados: { caminho da sala: { checkpoint_id: true } }. Só identificadores (nada
## de referências a nós das salas, que são liberadas); some com a Game (sem save).
var _activated_checkpoints: Dictionary[String, Dictionary] = {}
## Checkpoint de renascimento atual ("" / &"" = nenhum).
var _checkpoint_room: String = ""
var _checkpoint_id: StringName = &""

@onready var _room_slot: Node2D = $RoomSlot
@onready var _terra: PlayerCharacter = $Terra
@onready var _camera: Camera2D = $Terra/Camera2D
@onready var _fade: ColorRect = $Fade/ColorRect
@onready var _hud: PlayerHud = $PlayerHud
@onready var _game_over: GameOverScreen = $GameOverScreen


func _ready() -> void:
	_fade.modulate.a = 0.0
	# Uma ligação só: _ready roda uma vez por instância da Game, e a Terra nunca é recriada.
	_terra.death_finished.connect(_on_terra_death_finished)
	_game_over.retry_requested.connect(_on_retry_requested)
	# Desligada (transição) ou pausada (Game Over, reinício), a Terra fica no espaço físico como
	# corpo estático em vez de sair dele. Fora do espaço, o servidor ignora o teleporte para a
	# entrada e, ao ser religada, ela volta por um passo na posição antiga: se ali houver uma
	# RoomExit da sala nova (ex.: Sala 05 → 04, saídas oeste nas mesmas coordenadas), ela dispara.
	# Nenhum corpo tem a layer player na mask (só áreas: saídas e detecção dos inimigos), então
	# isso não cria colisões; a Hurtbox (Area2D filha) continua saindo do espaço e bloqueada,
	# sem dano no fade.
	_terra.disable_mode = CollisionObject2D.DISABLE_MODE_MAKE_STATIC
	load_room(start_room, start_entrance)


func get_hud() -> PlayerHud:
	return _hud


func get_game_over_screen() -> GameOverScreen:
	return _game_over


## Verdadeiro do fim da animação de morte até a tela escurecer no reinício.
func is_game_over() -> bool:
	return _game_over.is_open()


func is_retrying() -> bool:
	return _retrying


## Entrada pela qual a Terra chegou à sala atual (start_entrance no início; &"" depois de
## renascer num altar).
func get_arrival_entrance() -> StringName:
	return _entrance_id


## Sala prevista para o próximo renascimento: a do checkpoint atual, ou start_room sem checkpoint.
## (Um checkpoint que se mostrar inválido no reinício cai para start_room; ver _run_retry().)
func get_respawn_room() -> String:
	return _checkpoint_room if has_current_checkpoint() else start_room


## Entrada prevista para o próximo renascimento: start_entrance sem checkpoint; &"" com
## checkpoint (a Terra renasce no SpawnPoint do altar).
func get_respawn_entrance() -> StringName:
	return &"" if has_current_checkpoint() else start_entrance


func get_room() -> Room:
	return _room


func get_room_path() -> String:
	return _room_path


func get_terra() -> PlayerCharacter:
	return _terra


func is_transitioning() -> bool:
	return _transitioning


func is_enemy_defeated(room_path: String, enemy_id: StringName) -> bool:
	return _defeated_enemies.has(room_path) and _defeated_enemies[room_path].has(enemy_id)


## Identificadores dos inimigos derrotados na sala (cópia, em ordem de registro).
func get_defeated_enemies(room_path: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if _defeated_enemies.has(room_path):
		for id: StringName in _defeated_enemies[room_path]:
			result.append(id)
	return result


## Escopo registrado para a derrota (Room.SCOPE_ATTEMPT ou SCOPE_PERMANENT), ou &"" se o
## inimigo não estiver derrotado.
func get_defeated_enemy_scope(room_path: String, enemy_id: StringName) -> StringName:
	if not is_enemy_defeated(room_path, enemy_id):
		return &""
	return _defeated_enemies[room_path][enemy_id]


func get_attempt() -> int:
	return _attempt


## Começa uma nova tentativa: esquece as derrotas de escopo attempt e mantém as permanent.
## only_room vazio: em TODAS as salas (os inimigos comuns voltam na próxima vez que cada sala
## for carregada); com um caminho: só nessa sala, e as derrotas das outras continuam (é o que o
## reinício usa, com a sala da morte). Não recarrega a sala atual nem mexe nos inimigos já
## carregados; quem reinicia a sala é o fluxo de renascimento. Retorna quantas derrotas foram
## esquecidas.
func start_new_attempt(only_room: String = "") -> int:
	var removed: int = 0
	for room_path: String in _defeated_enemies.keys():
		if not only_room.is_empty() and room_path != only_room:
			continue
		var defeated: Dictionary = _defeated_enemies[room_path]
		for enemy_id: StringName in defeated.keys():
			if defeated[enemy_id] != Room.SCOPE_PERMANENT:
				defeated.erase(enemy_id)
				removed += 1
		if defeated.is_empty():
			_defeated_enemies.erase(room_path)
	_attempt += 1
	return removed


## Sala inicial do jogo (configuração start_room), independente da sala atual.
func get_start_room() -> String:
	return start_room


## Entrada inicial do jogo (configuração start_entrance).
func get_start_entrance() -> StringName:
	return start_entrance


## Ativa o altar checkpoint_id da sala carregada e o torna o checkpoint atual (o anterior
## continua ativado). Só vale para a sala atual (room_path == get_room_path()) e para um altar
## válido dela (Room.get_checkpoints(): ID não vazio e não repetido); assim nenhuma sala é
## carregada só para validar. Recusada (false, sem mudar nada) com a Terra morta, no Game Over,
## no reinício e durante uma transição. Repetir a ativação não duplica o registro. Não começa
## tentativa nem mexe nos inimigos ou na vida. Retorna se a ativação foi aceita.
func activate_checkpoint(room_path: String, checkpoint_id: StringName) -> bool:
	if checkpoint_id.is_empty():
		push_error("Game: checkpoint_id vazio.")
		return false
	if _room == null or room_path.is_empty() or room_path != _room_path:
		push_error("Game: checkpoint '%s' fora da sala carregada ('%s')." % [checkpoint_id, room_path])
		return false
	if not _room.get_checkpoints().has(checkpoint_id):
		push_error("Game: a sala '%s' não tem o checkpoint válido '%s'." % [room_path, checkpoint_id])
		return false
	if _transitioning or _retrying or _game_over.is_open() or _terra.is_dead():
		return false
	if not _activated_checkpoints.has(room_path):
		_activated_checkpoints[room_path] = {}
	_activated_checkpoints[room_path][checkpoint_id] = true
	_checkpoint_room = room_path
	_checkpoint_id = checkpoint_id
	_apply_checkpoint_states(_room, room_path)
	return true


func has_current_checkpoint() -> bool:
	return not _checkpoint_id.is_empty()


## Sala do checkpoint atual ("" sem checkpoint).
func get_current_checkpoint_room() -> String:
	return _checkpoint_room


## checkpoint_id do checkpoint atual (&"" sem checkpoint).
func get_current_checkpoint_id() -> StringName:
	return _checkpoint_id


func is_checkpoint_activated(room_path: String, checkpoint_id: StringName) -> bool:
	return _activated_checkpoints.has(room_path) and _activated_checkpoints[room_path].has(checkpoint_id)


func is_current_checkpoint(room_path: String, checkpoint_id: StringName) -> bool:
	return has_current_checkpoint() and room_path == _checkpoint_room and checkpoint_id == _checkpoint_id


## Altares ativados da sala (cópia, em ordem de ativação).
func get_activated_checkpoints(room_path: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if _activated_checkpoints.has(room_path):
		for id: StringName in _activated_checkpoints[room_path]:
			result.append(id)
	return result


## Carrega a sala na hora (sem fade), põe a Terra parada na entrada e aplica os limites da
## câmera. Em caso de erro (cena inválida ou entrada inexistente) mantém o estado e retorna false.
func load_room(room_path: String, entrance_id: StringName) -> bool:
	var room: Room = _instantiate_room(room_path, entrance_id)
	if room == null:
		return false
	_swap_room(room, room_path, entrance_id)
	return true


## Pede a troca de sala com fade. Ignorada durante outra transição ou com a Terra morta
## (inclusive durante o Game Over, que só abre com a Terra morta) e durante o reinício.
## O destino é validado antes de qualquer mudança: se falhar, a sala atual e o controle da
## Terra continuam como estavam. Retorna se a transição começou.
func request_transition(room_path: String, entrance_id: StringName) -> bool:
	if _transitioning or _retrying or _terra.get_health().is_dead():
		return false
	var room: Room = _instantiate_room(room_path, entrance_id)
	if room == null:
		return false
	_transitioning = true
	# Proteção contra dano a partir daqui, ainda dentro do body_entered: num tick de física os
	# sinais de área vêm antes dos _physics_process (inclusive das Hitbox inimigas), então
	# nenhum golpe do mesmo tick passa. Não mexe no contador de invulnerabilidade da Terra.
	_terra.get_hurtbox().set_blocked(true)
	# Adiado: o pedido chega no meio do passo de física (body_entered), quando não se pode
	# tirar corpos do espaço físico.
	_run_transition.call_deferred(room, room_path, entrance_id)
	return true


## O ponto de efetivação da troca é _swap_room(): antes dele a sala de origem é a atual;
## depois, a de destino. Uma morte antes desse ponto (só por dano que não passe pela Hurtbox,
## já que ela está bloqueada) cancela a transição: a sala de destino, ainda fora da árvore, é
## liberada, a Terra fica onde está e a morte segue (Game Over e renascimento na sala de origem).
## Uma morte depois da troca vale para a sala nova. Em todos os caminhos, _end_transition()
## devolve o controle, libera a Hurtbox e encerra o estado de transição.
func _run_transition(room: Room, room_path: String, entrance_id: StringName) -> void:
	if _terra.is_dead():
		# Morreu entre o pedido e o início da troca: cancela sem fade.
		room.free()
		_end_transition(false)
		return
	# Sem controle durante a troca: nada de golpe, onda ou pulo atravessando a porta.
	_terra.interrupt_actions()
	_terra.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade_to(1.0)
	if _terra.is_dead():
		# Morreu durante o escurecer: a sala de origem continua a atual.
		room.free()
		await _fade_to(0.0)
		_end_transition(false)
		return
	_swap_room(room, room_path, entrance_id)
	await _fade_to(0.0)
	_end_transition(true)


func _end_transition(swapped: bool) -> void:
	_terra.process_mode = Node.PROCESS_MODE_INHERIT
	_terra.get_hurtbox().set_blocked(false)
	_transitioning = false
	transition_finished.emit(swapped)


## Carrega e confere a sala (e a entrada) sem tocar na atual. Retorna null (com erro no console)
## se falhar.
func _instantiate_room(room_path: String, entrance_id: StringName) -> Room:
	var room: Room = _load_room(room_path)
	if room == null:
		return null
	if not room.has_entrance(entrance_id):
		push_error("Game: a sala '%s' não tem a entrada '%s'." % [room_path, entrance_id])
		room.free()
		return null
	return room


## Instancia a sala sem tocar na atual: o caminho precisa existir e a cena ser uma Room.
## Retorna null (com erro no console) se falhar.
func _load_room(room_path: String) -> Room:
	if room_path.is_empty() or not ResourceLoader.exists(room_path):
		push_error("Game: sala '%s' não encontrada." % room_path)
		return null
	var scene: PackedScene = load(room_path) as PackedScene
	var node: Node = scene.instantiate() if scene != null else null
	var room: Room = node as Room
	if room == null:
		push_error("Game: '%s' não é uma Room." % room_path)
		if node != null:
			node.free()
		return null
	return room


## Troca a sala atual pela já instanciada e validada. checkpoint_id vazio (transições, início):
## a Terra vai para a entrada entrance_id. Com checkpoint_id (reinício num altar): vai para o
## SpawnPoint do altar, lido só depois de a sala entrar na árvore (posição global correta); o
## altar não fica guardado, e a entrada de chegada passa a ser &"".
func _swap_room(room: Room, room_path: String, entrance_id: StringName, checkpoint_id: StringName = &"") -> void:
	if _room != null:
		_room_slot.remove_child(_room)
		_room.queue_free()
	_room = room
	_room_path = room_path
	_entrance_id = entrance_id
	_apply_enemy_persistence(room, room_path)
	_connect_checkpoints(room, room_path)
	_room_slot.add_child(room)
	for room_exit: RoomExit in room.get_exits():
		room_exit.transition_requested.connect(request_transition)
	if checkpoint_id.is_empty():
		_place_terra(room, entrance_id)
	else:
		var altar: ElementalAltar = room.get_checkpoint(checkpoint_id)
		_place_terra_at(altar.get_spawn_position(), altar.get_spawn_facing(), room.get_camera_bounds())
	room_changed.emit(room)


## Terra parada na entrada, olhando para dentro da sala, e câmera nos limites da sala.
func _place_terra(room: Room, entrance_id: StringName) -> void:
	_place_terra_at(room.get_entrance(entrance_id).global_position, room.get_entrance_facing(entrance_id),
		room.get_camera_bounds())


func _place_terra_at(feet: Vector2, facing: float, camera_bounds: Rect2i) -> void:
	_terra.global_position = feet
	_terra.velocity = Vector2.ZERO
	_terra.set_facing(facing)
	_apply_camera_bounds(camera_bounds)


## Antes de a sala entrar na árvore: libera os inimigos já derrotados (nem chegam ao _ready) e
## liga a morte dos vivos ao registro. A ligação leva o caminho da sala, então uma morte durante
## o fade de saída fica na sala certa; morre com o inimigo (sem sinais acumulados entre visitas).
func _apply_enemy_persistence(room: Room, room_path: String) -> void:
	var enemies: Dictionary[StringName, Enemy] = room.get_persistent_enemies()
	for id: StringName in enemies:
		var enemy: Enemy = enemies[id]
		if is_enemy_defeated(room_path, id):
			enemy.get_parent().remove_child(enemy)
			enemy.free()
			continue
		var health: HealthComponent = enemy.get_node_or_null(^"HealthComponent") as HealthComponent
		if health == null:
			push_error("Game: inimigo '%s' (%s) sem HealthComponent; não será lembrado." % [id, room_path])
			continue
		var scope: StringName = room.get_enemy_persistence_scope(enemy)
		health.died.connect(_on_persistent_enemy_died.bind(room_path, id, scope), CONNECT_ONE_SHOT)


## Registra na hora da morte (antes da animação e do queue_free).
func _on_persistent_enemy_died(room_path: String, enemy_id: StringName, scope: StringName) -> void:
	if not _defeated_enemies.has(room_path):
		_defeated_enemies[room_path] = {}
	_defeated_enemies[room_path][enemy_id] = scope


## Antes de a sala entrar na árvore: devolve a cada altar válido o estado do registro e liga o
## pedido de ativação (com o caminho da sala). Altares com ID vazio ou repetido não são ligados.
## As ligações morrem com a sala (sem sinais acumulados entre visitas).
func _connect_checkpoints(room: Room, room_path: String) -> void:
	for altar: ElementalAltar in room.get_checkpoints().values():
		altar.activated.connect(_on_altar_activated.bind(room_path))
	_apply_checkpoint_states(room, room_path)


## Estado de cada altar válido da sala a partir do registro (sem emitir activated).
func _apply_checkpoint_states(room: Room, room_path: String) -> void:
	var altars: Dictionary[StringName, ElementalAltar] = room.get_checkpoints()
	for id: StringName in altars:
		altars[id].apply_state(is_checkpoint_activated(room_path, id), is_current_checkpoint(room_path, id))


## Interação com um altar. Só o altar da sala carregada conta (um altar de uma sala já
## substituída é ignorado). Aceita a ativação (primeira ou repetida), a Terra recupera toda a
## vida (health_changed atualiza a HUD); recusada, nada muda. activate_checkpoint() sozinho
## (registro) não mexe na vida.
func _on_altar_activated(altar: ElementalAltar, _first_time: bool, room_path: String) -> void:
	if _room == null or altar.get_room() != _room:
		return
	if activate_checkpoint(room_path, altar.checkpoint_id):
		_terra.get_health().restore_full()


## Fim da animação de morte da Terra (emitido uma vez por morte): pausa o mundo e abre a tela.
## O reinício só começa quando o jogador confirma (retry_requested).
## Se a transição ainda estiver em andamento, espera ela terminar (ou ser cancelada) antes de
## pausar: pausar no meio deixaria o fade da transição parado e _transitioning preso.
func _on_terra_death_finished() -> void:
	if _game_over.is_open() or _retrying:
		return
	if _transitioning:
		await transition_finished
		if _game_over.is_open() or _retrying or not _terra.is_dead():
			return
	_paused_world = true
	get_tree().paused = true
	_game_over.open()


## "Tentar novamente": aceito uma única vez, só com o Game Over aberto e a Terra morta.
func _on_retry_requested() -> void:
	if _retrying or not _game_over.is_open() or not _terra.is_dead():
		return
	_retrying = true
	_run_retry()


## Sequência do reinício. Ordem:
##  1. escurece com o mundo ainda pausado (tween que processa durante a pausa);
##  2. com a tela preta: fecha o Game Over, começa a nova tentativa (limpa as derrotas
##     attempt só da sala onde a Terra morreu; as das outras salas e as permanent continuam;
##     os checkpoints não mudam) e só então carrega a sala de renascimento, independente da sala
##     da morte, nesta ordem (sem recursão; ver _place_for_respawn()):
##       a. checkpoint atual válido: sala do altar, Terra no SpawnPoint, olhando para spawn_facing;
##       b. start_room / start_entrance;
##       c. último recurso: a sala da morte, na entrada de chegada;
##  3. revive() (vida cheia, ações canceladas, invulnerabilidade); com o mundo pausado, a
##     invulnerabilidade, que conta em _physics_process da Hurtbox, não corre;
##  4. clareia com o mundo ainda pausado (nem Terra nem inimigos se movem);
##  5. despausa: Terra e inimigos voltam juntos, a invulnerabilidade começa a contar, e emite
##     attempt_restarted.
## Se a Game sair da árvore no meio, _exit_tree despausa a árvore e o reinício espera a volta
## (tree_entered; _enter_tree pausa de novo). Liberada, a sequência simplesmente termina.
func _run_retry() -> void:
	# Sala da morte, fixada no aceite: transições ficam recusadas durante o reinício, e o Game
	# Over só abre depois que uma transição em andamento termina (ou é cancelada).
	var death_room: String = _room_path
	var death_arrival: StringName = _entrance_id
	await _fade_to(1.0, true)
	if not is_inside_tree():
		await tree_entered
	_game_over.close()
	start_new_attempt(death_room)
	_place_for_respawn(death_room, death_arrival)
	_terra.revive()
	await _fade_to(0.0, true)
	if not is_inside_tree():
		await tree_entered
	_paused_world = false
	get_tree().paused = false
	_retrying = false
	attempt_restarted.emit(_attempt)


## Carrega a sala de renascimento e põe a Terra nela (uma troca só). Cada alternativa é validada
## antes de mexer na sala atual; falhou, passa à seguinte (sequência fixa, sem recursão nem
## novas tentativas). Nenhuma delas mexe no registro de inimigos.
func _place_for_respawn(death_room: String, death_arrival: StringName) -> void:
	if _respawn_at_checkpoint():
		return
	if _respawn_at_entrance(start_room, start_entrance):
		return
	push_error("Game: sala inicial '%s' (entrada '%s') inválida; renascendo na sala da morte." % [start_room, start_entrance])
	if _respawn_at_entrance(death_room, death_arrival):
		return
	# Nenhuma sala pôde ser carregada: fica na sala atual (que continua válida, porque nada foi
	# trocado), na entrada de chegada se ela existir. O reinício termina normalmente (revive,
	# clarear, despausar), sem tela preta permanente.
	push_error("Game: nenhum destino de renascimento válido (checkpoint, sala inicial, sala da morte '%s'); renascendo onde a Terra está." % death_room)
	_terra.velocity = Vector2.ZERO
	if _room != null and _room.has_entrance(_entrance_id):
		_place_terra(_room, _entrance_id)


## Checkpoint atual, se houver e for válido: caminho existente, cena Room, altar válido com esse
## checkpoint_id (Room.has_checkpoint(): exclui ausente, vazio e repetido) e com SpawnPoint.
## Inválido: erro no console, a sala instanciada é liberada e só a seleção atual é limpa (o
## histórico dos altares ativados continua). Retorna se a Terra foi posta no altar.
func _respawn_at_checkpoint() -> bool:
	if not has_current_checkpoint():
		return false
	var room_path: String = _checkpoint_room
	var checkpoint_id: StringName = _checkpoint_id
	var room: Room = _load_room(room_path)
	var problem: String = ""
	if room == null:
		problem = "sala inválida"
	elif not room.has_checkpoint(checkpoint_id):
		problem = "altar inexistente ou inválido na sala"
	elif not room.get_checkpoint(checkpoint_id).has_spawn_point():
		problem = "altar sem SpawnPoint"
	if not problem.is_empty():
		push_error("Game: checkpoint '%s' em '%s' descartado (%s); renascendo na sala inicial." % [checkpoint_id, room_path, problem])
		if room != null:
			room.free()
		_checkpoint_room = ""
		_checkpoint_id = &""
		return false
	_swap_room(room, room_path, &"", checkpoint_id)
	return true


## Sala e entrada, se válidas (_instantiate_room). Retorna se a Terra foi posta na entrada.
func _respawn_at_entrance(room_path: String, entrance_id: StringName) -> bool:
	var room: Room = _instantiate_room(room_path, entrance_id)
	if room == null:
		return false
	_swap_room(room, room_path, entrance_id)
	return true


## A pausa é da Game: se ela sair da árvore com o mundo pausado por ela (ex.: troca de cena ou
## fim de um teste no Game Over), a árvore não fica pausada para quem vier depois; se voltar
## ainda no Game Over ou no reinício, a pausa volta junto.
func _exit_tree() -> void:
	if _paused_world:
		get_tree().paused = false


func _enter_tree() -> void:
	if _paused_world:
		get_tree().paused = true


func _apply_camera_bounds(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()
	_camera.force_update_scroll()


## while_paused: o tween também corre com a árvore pausada (reinício). As transições normais
## mantêm o padrão (param junto com a Game).
func _fade_to(alpha: float, while_paused: bool = false) -> void:
	_fade.visible = true
	var tween: Tween = create_tween()
	if while_paused:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
	_fade.visible = alpha > 0.0
