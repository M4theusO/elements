extends Node2D
## Cena persistente do jogo: carrega a sala atual em RoomSlot, posiciona a Terra (instância
## única, nunca recriada nem trocada de pai) numa entrada e aplica os limites da câmera.
## As saídas das salas (RoomExit) pedem a troca; a Game valida o destino e faz a transição
## com fade, sem recriar a Terra (vida, componentes e recargas continuam os mesmos).
## Lembra, só em memória e só nesta sessão, os inimigos persistentes já derrotados de cada sala:
## eles não voltam quando a sala é recarregada; os vivos voltam inteiros, no ponto de origem.
## Cada derrota guarda o escopo do inimigo (Room.get_enemy_persistence_scope()): uma nova
## tentativa (start_new_attempt()) esquece as derrotas "attempt" de todas as salas e mantém
## as "permanent".
## Morte da Terra: a HUD (PlayerHud, camada 5, abaixo do fade) mostra a vida da Terra persistente;
## quando a animação de morte termina (death_finished), a Game pausa o mundo e abre a
## GameOverScreen (camada 20, funciona pausada). "Tentar novamente" (retry_requested) reinicia a
## tentativa: escurece com o mundo pausado, começa uma nova tentativa, recria a sala atual, faz a
## Terra renascer na entrada pela qual chegou a ela e clareia, tudo com o mundo pausado; no fim do
## clarear, Terra e inimigos voltam juntos (e a invulnerabilidade de renascimento começa a contar).
## Transições: a Hurtbox da Terra fica bloqueada do pedido até a volta do controle (ver
## request_transition() e _run_transition()).

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
## Entrada pela qual a Terra chegou à sala atual (onde renasce).
var _entrance_id: StringName = &""
## Verdadeiro do "Tentar novamente" aceito até o fim do reinício.
var _retrying: bool = false

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


## Entrada da sala atual onde a Terra renasce: a da chegada (start na sala inicial).
func get_respawn_entrance() -> StringName:
	return _entrance_id


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


## Começa uma nova tentativa: esquece as derrotas de escopo attempt de TODAS as salas (os
## inimigos comuns voltam na próxima vez que cada sala for carregada) e mantém as permanent.
## Não recarrega a sala atual nem mexe nos inimigos já carregados; quem reinicia a sala é o
## fluxo de renascimento. Retorna quantas derrotas foram esquecidas.
func start_new_attempt() -> int:
	var removed: int = 0
	for room_path: String in _defeated_enemies.keys():
		var defeated: Dictionary = _defeated_enemies[room_path]
		for enemy_id: StringName in defeated.keys():
			if defeated[enemy_id] != Room.SCOPE_PERMANENT:
				defeated.erase(enemy_id)
				removed += 1
		if defeated.is_empty():
			_defeated_enemies.erase(room_path)
	_attempt += 1
	return removed


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


## Carrega e confere a sala sem tocar na atual. Retorna null (com erro no console) se falhar.
func _instantiate_room(room_path: String, entrance_id: StringName) -> Room:
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
	if not room.has_entrance(entrance_id):
		push_error("Game: a sala '%s' não tem a entrada '%s'." % [room_path, entrance_id])
		room.free()
		return null
	return room


func _swap_room(room: Room, room_path: String, entrance_id: StringName) -> void:
	if _room != null:
		_room_slot.remove_child(_room)
		_room.queue_free()
	_room = room
	_room_path = room_path
	_entrance_id = entrance_id
	_apply_enemy_persistence(room, room_path)
	_room_slot.add_child(room)
	for room_exit: RoomExit in room.get_exits():
		room_exit.transition_requested.connect(request_transition)
	_place_terra(room, entrance_id)
	room_changed.emit(room)


## Terra parada na entrada, olhando para dentro da sala, e câmera nos limites da sala.
func _place_terra(room: Room, entrance_id: StringName) -> void:
	_terra.global_position = room.get_entrance(entrance_id).global_position
	_terra.velocity = Vector2.ZERO
	_terra.set_facing(room.get_entrance_facing(entrance_id))
	_apply_camera_bounds(room.get_camera_bounds())


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
##     attempt de todas as salas) e só então recria a sala atual, na entrada de chegada;
##  3. revive() (vida cheia, ações canceladas, invulnerabilidade); com o mundo pausado, a
##     invulnerabilidade, que conta em _physics_process da Hurtbox, não corre;
##  4. clareia com o mundo ainda pausado (nem Terra nem inimigos se movem);
##  5. despausa: Terra e inimigos voltam juntos, a invulnerabilidade começa a contar, e emite
##     attempt_restarted.
## Se a Game sair da árvore no meio, _exit_tree despausa a árvore e o reinício espera a volta
## (tree_entered; _enter_tree pausa de novo). Liberada, a sequência simplesmente termina.
func _run_retry() -> void:
	await _fade_to(1.0, true)
	if not is_inside_tree():
		await tree_entered
	_game_over.close()
	start_new_attempt()
	var room: Room = _instantiate_room(_room_path, _entrance_id)
	if room != null:
		_swap_room(room, _room_path, _entrance_id)
	else:
		# Não deveria acontecer (a sala já foi carregada antes): renasce na sala atual mesmo.
		push_error("Game: não foi possível recriar a sala '%s'; renascendo sem recriá-la." % _room_path)
		_place_terra(_room, _entrance_id)
	_terra.revive()
	await _fade_to(0.0, true)
	if not is_inside_tree():
		await tree_entered
	_paused_world = false
	get_tree().paused = false
	_retrying = false
	attempt_restarted.emit(_attempt)


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
