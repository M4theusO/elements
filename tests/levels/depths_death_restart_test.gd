extends SceneTree
## Teste automatizado do fluxo de morte e reinício na sala de teste isolada
## (depths_test_room.tscn como cena atual, como no F6): HUD com 5 corações; Terra morre ->
## animação -> mundo pausado e "Você caiu" aberto; "Tentar novamente" (ui_accept) recarrega a
## cena: Terra com vida cheia na posição inicial e 1 s de invulnerabilidade, inimigos e cenário
## restaurados, jogo despausado e tela fechada.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/levels/depths_death_restart_test.gd

const ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const TERRA_START: Vector2 = Vector2(56, 320)
const FRAGMENT_FLOOR_START: Vector2 = Vector2(648, 320)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Morte e reinício na sala de teste")
	await process_frame
	change_scene_to_file(ROOM_PATH)
	await _frames(5)
	var scene := current_scene
	_check(scene != null and scene.scene_file_path == ROOM_PATH, "sala de teste é a cena atual")
	if scene == null:
		_finish()
		return
	var terra := scene.get_node("Terra") as PlayerCharacter
	var hud := scene.get_node("PlayerHud") as PlayerHud
	var go := scene.get_node("GameOverScreen") as GameOverScreen
	var fragment := scene.get_node("Enemies/LivingFragmentFloor") as LivingFragment
	var props_count := scene.get_node("Props").get_child_count()
	_check(scene.get_node("DeathController") is SceneDeathController, "sala tem o controlador de morte e reinício")
	await _frames(20)
	_check(hud.get_hearts().get_full_count() == 5 and hud.get_hearts().get_empty_count() == 0, "HUD: 5 corações cheios")
	_check(not go.is_open() and not paused, "Game Over fechado e jogo rodando")

	# Estado alterado antes da morte: inimigo ferido.
	(fragment.get_node("Hurtbox") as Hurtbox).receive_hit(1)
	_check((fragment.get_node("HealthComponent") as HealthComponent).current_health == 2, "Fragmento do chão ferido (2 de 3) antes da morte da Terra")

	print("-- Morte")
	terra.get_health().take_damage(5)
	_check(terra.is_dead() and hud.get_hearts().get_full_count() == 0, "Terra morre; HUD com 0 corações cheios")
	_check(not go.is_open() and not paused, "Game Over ainda fechado durante a animação death")
	var opened := false
	for i in 120:
		await physics_frame
		if go.is_open():
			opened = true
			break
	_check(opened and paused, "depois da animação: \"Você caiu\" aberto e mundo pausado")
	var fx := fragment.global_position
	await _frames(20)
	_check(fragment.global_position == fx, "com o mundo pausado, os inimigos param")

	print("-- Tentar novamente")
	await create_timer(go.input_delay + 0.1, true).timeout
	_check(go.is_accepting_input() and go.get_retry_button().has_focus(), "botão \"Tentar novamente\" com foco e aceitando entrada")
	var down := InputEventAction.new()
	down.action = &"ui_accept"
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = &"ui_accept"
	Input.parse_input_event(up)
	await _frames(6)
	var fresh := current_scene
	_check(fresh != null and fresh != scene and fresh.scene_file_path == ROOM_PATH, "a cena foi recarregada (instância nova)")
	if fresh == null or fresh == scene:
		_finish()
		return
	var terra2 := fresh.get_node("Terra") as PlayerCharacter
	var hud2 := fresh.get_node("PlayerHud") as PlayerHud
	var go2 := fresh.get_node("GameOverScreen") as GameOverScreen
	var fragment2 := fresh.get_node("Enemies/LivingFragmentFloor") as LivingFragment
	_check(not paused and not go2.is_open(), "jogo despausado e tela fechada")
	_check(terra2.get_health().current_health == 5 and not terra2.is_dead(), "Terra com vida cheia (5)")
	_check(terra2.get_hurtbox().is_invulnerable() and terra2.get_hurtbox().get_invulnerability_left() > 0.8, "Terra renasce com ~1 s de invulnerabilidade (%.2f s restantes)" % terra2.get_hurtbox().get_invulnerability_left())
	_check(terra2.global_position.distance_to(TERRA_START) < 2.0, "Terra na posição inicial da sala")
	_check((fragment2.get_node("HealthComponent") as HealthComponent).current_health == 3 and fragment2.global_position.distance_to(FRAGMENT_FLOOR_START) < 2.0, "inimigo restaurado: vida cheia (3) na posição inicial")
	_check(fresh.get_node("Props").get_child_count() == props_count and fresh.get_node("Background") != null and fresh.get_node("Terrain") != null, "cenário restaurado (fundo, terreno e %d props)" % props_count)
	await _frames(10)
	_check(hud2.get_hearts().get_full_count() == 5, "HUD da cena nova com 5 corações")
	await create_timer(1.1).timeout
	_check(not terra2.get_hurtbox().is_invulnerable(), "invulnerabilidade de renascimento termina")
	_finish()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _finish() -> void:
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)
