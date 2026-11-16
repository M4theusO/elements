extends SceneTree
## Teste automatizado da morte e do renascimento da Terra (PlayerCharacter): morte ao chegar a
## zero, animação death uma única vez, death_finished uma vez (por animation_finished e, sem
## death ou com death em loop, pelo tempo de reserva), bloqueio de movimento, golpe e habilidade
## e nenhum dano depois da morte; revive() com vida cheia, controle de volta e 1 s de
## invulnerabilidade (Hurtbox), e uma segunda morte funcionando igual.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/characters/death_respawn_test.gd

const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const FLOOR_Y: float = 200.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Morte e renascimento da Terra")
	await process_frame
	_make_floor()
	await _test_death_and_revive()
	await _test_fallback(false)
	await _test_fallback(true)
	_finish()


func _test_death_and_revive() -> void:
	var terra := await _spawn_terra(Vector2(100, FLOOR_Y))
	var health := terra.get_health()
	var hurtbox := terra.get_hurtbox()
	var sprite := terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var melee := terra.get_node("MeleeAttack") as MeleeAttack
	var finished := [0]
	var damaged := [0]
	terra.death_finished.connect(func() -> void: finished[0] += 1)
	health.damaged.connect(func(_a: int) -> void: damaged[0] += 1)
	_check(health.current_health == 5 and not terra.is_dead(), "Terra começa com 5 de vida, viva")

	print("-- Morte")
	hurtbox.receive_hit(5)
	_check(health.current_health == 0 and terra.is_dead(), "ao chegar a zero, morre")
	_check(sprite.animation == &"death" and sprite.is_playing(), "toca a animação death")
	var death_starts := 0
	var last: StringName = sprite.animation
	for i in 120:  # 2 s (a animação dura 0,75 s)
		await physics_frame
		if sprite.animation == &"death" and last != &"death":
			death_starts += 1
		last = sprite.animation
	var frames := sprite.sprite_frames.get_frame_count(&"death")
	_check(death_starts == 0 and sprite.animation == &"death" and not sprite.is_playing() and sprite.frame == frames - 1, "death toca uma vez só e fica no último quadro (%d/%d)" % [sprite.frame + 1, frames])
	_check(finished[0] == 1, "death_finished emitido uma única vez (animation_finished)")

	print("-- Bloqueios depois da morte")
	var x0 := terra.global_position.x
	Input.action_press(&"move_right")
	await _physics(30)
	Input.action_release(&"move_right")
	_check(absf(terra.global_position.x - x0) < 0.5, "movimento bloqueado (x %.1f -> %.1f)" % [x0, terra.global_position.x])
	await _tap(&"attack")
	_check(not melee.is_busy(), "golpe bloqueado")
	await _tap(&"ability")
	_check(not terra.ability.is_casting(), "habilidade bloqueada")
	await _tap(&"jump")
	await _physics(5)
	_check(terra.is_on_floor(), "pulo bloqueado")
	var n: int = damaged[0]
	await _physics(40)  # passa a invulnerabilidade de 0,6 s do último golpe
	hurtbox.receive_hit(1)
	_check(health.current_health == 0 and damaged[0] == n and finished[0] == 1, "nenhum dano nem nova morte depois de morrer")

	print("-- Renascimento")
	terra.revive()
	_check(health.current_health == 5 and not terra.is_dead(), "revive(): vida cheia (5) e viva")
	_check(absf(hurtbox.get_invulnerability_left() - 1.0) < 0.001, "revive(): 1 s de invulnerabilidade na Hurtbox")
	_check(sprite.animation == &"idle" and melee.process_mode == Node.PROCESS_MODE_INHERIT, "volta ao idle e o golpe é religado")
	hurtbox.receive_hit(1)
	_check(health.current_health == 5, "golpe ignorado durante a invulnerabilidade de renascimento")
	x0 = terra.global_position.x
	Input.action_press(&"move_right")
	await _physics(30)
	Input.action_release(&"move_right")
	_check(terra.global_position.x - x0 > 20.0, "movimento de volta (x %.1f -> %.1f)" % [x0, terra.global_position.x])
	await _tap(&"attack")
	_check(melee.is_busy(), "golpe de volta")
	await _physics(40)  # completa 1 s desde o revive (30 + 2 + 40 > 60 ticks)
	_check(not hurtbox.is_invulnerable(), "invulnerabilidade de renascimento acaba depois de 1 s")
	hurtbox.receive_hit(1)
	_check(health.current_health == 4, "depois dela, o golpe conta (vida 4)")

	print("-- Segunda morte")
	await _physics(40)
	hurtbox.receive_hit(9)
	await _physics(120)
	_check(terra.is_dead() and finished[0] == 2, "segunda morte: death_finished de novo, uma vez (total 2)")
	terra.queue_free()
	await process_frame


## Sem a animação death (ou com death em loop), death_finished vem pelo tempo de reserva.
func _test_fallback(looping: bool) -> void:
	print("-- death_finished de reserva (%s)" % ("death em loop" if looping else "sem animação death"))
	var terra := await _spawn_terra(Vector2(300, FLOOR_Y))
	var sprite := terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames.duplicate(true) as SpriteFrames
	if looping:
		frames.set_animation_loop(&"death", true)
	else:
		frames.remove_animation(&"death")
	sprite.sprite_frames = frames
	var finished := [0]
	terra.death_finished.connect(func() -> void: finished[0] += 1)
	terra.get_hurtbox().receive_hit(5)
	await _physics(30)  # 0,5 s: ainda não
	_check(finished[0] == 0, "antes de %.2f s, ainda sem death_finished" % PlayerCharacter.DEATH_FINISH_FALLBACK_TIME)
	await _physics(30)  # 1 s
	_check(finished[0] == 1, "depois de %.2f s, death_finished uma vez" % PlayerCharacter.DEATH_FINISH_FALLBACK_TIME)
	await _physics(60)
	_check(finished[0] == 1, "sem repetição")
	terra.queue_free()
	await process_frame


func _spawn_terra(pos: Vector2) -> PlayerCharacter:
	var terra := (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	terra.position = pos
	root.add_child(terra)
	await _physics(20)
	return terra


func _make_floor() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 32)
	shape.shape = rect
	shape.position = Vector2(0, FLOOR_Y + 16)
	body.add_child(shape)
	root.add_child(body)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _finish() -> void:
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)
