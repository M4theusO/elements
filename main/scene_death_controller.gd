class_name SceneDeathController
extends Node
## Controlador de morte e reinício para cenas avulsas, sem a Game (ex.: sala de teste rodada
## com F6). Decide o que fazer com a morte; a apresentação fica com a GameOverScreen:
##  - personagem termina de morrer (death_finished) -> pausa o mundo e abre a tela;
##  - "Tentar novamente" (retry_requested) -> despausa e recarrega a cena atual, que volta
##    inteira ao estado do arquivo (personagem, inimigos e cenário);
##  - na cena recarregada, chama revive() na personagem (vida cheia e invulnerabilidade de
##    renascimento). O aviso atravessa o recarregamento numa variável estática (sem autoload).
## No fluxo principal, quem faz esse papel é a Game (renascer na entrada da sala atual).

## Personagem controlada (opcional; sem ela, usa o primeiro nó de player_group).
@export var player: PlayerCharacter
@export var game_over_screen: GameOverScreen
@export var player_group: StringName = &"player"

## Verdadeiro entre o pedido de "Tentar novamente" e o _ready do controlador da cena nova.
static var _revive_on_next_ready: bool = false


func _ready() -> void:
	# Precisa receber o pedido da tela com o jogo pausado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player == null and not player_group.is_empty():
		player = get_tree().get_first_node_in_group(player_group) as PlayerCharacter
	if player == null or game_over_screen == null:
		push_warning("SceneDeathController: personagem ou GameOverScreen não definidos; morte sem Game Over.")
		return
	player.death_finished.connect(_on_death_finished)
	game_over_screen.retry_requested.connect(_on_retry_requested)
	if _revive_on_next_ready:
		_revive_on_next_ready = false
		if not player.is_node_ready():
			await player.ready
		player.revive()


func _on_death_finished() -> void:
	get_tree().paused = true
	game_over_screen.open()


func _on_retry_requested() -> void:
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene
	tree.paused = false
	game_over_screen.close()
	if scene == null or not (scene == owner or scene.is_ancestor_of(self)):
		push_warning("SceneDeathController: a cena deste controlador não é a cena atual; nada a recarregar.")
		return
	_revive_on_next_ready = true
	tree.reload_current_scene()
