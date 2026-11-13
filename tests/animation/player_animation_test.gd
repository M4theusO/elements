extends SceneTree
## Teste automatizado das animações e da movimentação do PlayerCharacter (Terra).
## Simula entradas no laboratório de movimento e verifica as transições idle/walk/jump/fall,
## colisão com paredes, aterrissagem, flip horizontal e preservação dos parâmetros físicos.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/animation/player_animation_test.gd

const LAB_PATH: String = "res://tests/movement_lab/movement_lab.tscn"
const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"

## Parâmetros físicos aprovados (terra_stats.tres). Alterá-los deve ser uma decisão consciente.
const EXPECTED_STATS: Dictionary = {
	"max_speed": 110.0,
	"ground_acceleration": 800.0,
	"ground_deceleration": 1000.0,
	"air_acceleration": 600.0,
	"air_deceleration": 400.0,
	"jump_height": 56.0,
	"jump_time_to_apex": 0.38,
	"fall_gravity_multiplier": 1.6,
	"jump_cut_multiplier": 0.5,
	"max_fall_speed": 360.0,
	"coyote_time": 0.1,
	"jump_buffer_time": 0.1,
}

const PHYSICS_TICKS: float = 60.0
## Posições no laboratório (pés da personagem).
const FLOOR_Y: float = 320.0
const SPAWN: Vector2 = Vector2(160.0, FLOOR_Y)
## Topo do Step3 (y = 272, x 640..688) e face esquerda do Step4 (x = 760, 4 tiles de altura).
const STEP3_EDGE: Vector2 = Vector2(680.0, 272.0)
const STEP4_LEFT_FACE_X: float = 760.0
const BODY_HALF_WIDTH: float = 8.0

var _failures: int = 0
var _checks: int = 0
var _terra: PlayerCharacter
var _sprite: AnimatedSprite2D
var _visuals: Node2D
## Histórico de animações efetivamente iniciadas (via signal animation_changed).
var _animation_log: Array[StringName] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== PlayerCharacter: animações e movimentação")
	_check_static_configuration()

	var lab: Node = (load(LAB_PATH) as PackedScene).instantiate()
	root.add_child(lab)
	_terra = lab.get_node("Terra") as PlayerCharacter
	_sprite = _terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	_visuals = _terra.get_node("Visuals") as Node2D
	_sprite.animation_changed.connect(_on_animation_changed)
	await _wait(30)

	await _test_idle()
	await _test_walk_and_stop()
	await _test_jump_fall_and_landing()
	await _test_release_direction_in_air()
	await _test_walls()
	await _test_ledge_fall()
	await _test_flip()
	await _test_measured_physics()
	await _test_missing_animation_fallback()

	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração (sem simulação) ---------------------------------------------

func _check_static_configuration() -> void:
	print("-- Configuração")
	var terra: PlayerCharacter = (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	var stats: CharacterStats = terra.stats
	_check(stats != null and stats.resource_path.ends_with("terra_stats.tres"), "Terra usa terra_stats.tres")
	for property: String in EXPECTED_STATS:
		var value: float = stats.get(property)
		_check(is_equal_approx(value, EXPECTED_STATS[property]),
			"%s = %s (aprovado: %s)" % [property, value, EXPECTED_STATS[property]])

	_check(terra.collision_layer == 4 and terra.collision_mask == (1 | 2 | 64),
		"corpo: layer player | mask world, platforms, destructibles")
	var body_shape: CollisionShape2D = terra.get_node("CollisionShape2D")
	_check((body_shape.shape as RectangleShape2D).size == Vector2(16, 46) and body_shape.position == Vector2(0, -23),
		"collider do corpo 16x46 em (0,-23)")
	var hurtbox: Area2D = terra.get_node("Hurtbox")
	var hurt_shape: CollisionShape2D = hurtbox.get_node("CollisionShape2D")
	_check(hurtbox.collision_layer == 16 and hurtbox.collision_mask == 0,
		"Hurtbox: layer player_hurtbox | mask nenhuma")
	_check((hurt_shape.shape as RectangleShape2D).size == Vector2(14, 44) and hurt_shape.position == Vector2(0, -22),
		"collider da Hurtbox 14x44 em (0,-22)")

	var sprite: AnimatedSprite2D = terra.get_node("Visuals/AnimatedSprite2D")
	var frames: SpriteFrames = sprite.sprite_frames
	_check(frames != null and frames.resource_path.ends_with("terra_sprite_frames.tres"), "Terra usa terra_sprite_frames.tres")
	_check(sprite.autoplay == "idle" and not sprite.centered and sprite.offset == Vector2(-25, -61),
		"AnimatedSprite2D: autoplay idle, offset (-25,-61)")
	# [nome, quadros, FPS, loop, arquivo]
	var expected_animations: Array = [
		[PlayerCharacter.ANIM_IDLE, 4, 6.0, true, "terra_idle.png"],
		[PlayerCharacter.ANIM_WALK, 8, 12.0, true, "terra_walk.png"],
		[PlayerCharacter.ANIM_JUMP, 2, 10.0, false, "terra_jump.png"],
		[PlayerCharacter.ANIM_FALL, 2, 8.0, true, "terra_fall.png"],
	]
	for spec: Array in expected_animations:
		var anim: StringName = spec[0]
		var ok: bool = frames.has_animation(anim) \
			and frames.get_frame_count(anim) == spec[1] \
			and is_equal_approx(frames.get_animation_speed(anim), spec[2]) \
			and frames.get_animation_loop(anim) == spec[3]
		for i: int in frames.get_frame_count(anim):
			var atlas: AtlasTexture = frames.get_frame_texture(anim, i) as AtlasTexture
			ok = ok and atlas != null and atlas.region == Rect2(i * 48, 0, 48, 64) \
				and atlas.atlas.resource_path.ends_with(spec[4])
		_check(ok, "%s: %d quadros 48x64 de %s, %d FPS, loop=%s" % [anim, spec[1], spec[4], spec[2], spec[3]])
	terra.free()


# --- Simulação ------------------------------------------------------------------

func _test_idle() -> void:
	print("-- Idle")
	await _reset(SPAWN)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - FLOOR_Y) < 0.5, "assenta no chão (y=%.2f)" % _terra.global_position.y)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE and _sprite.is_playing(), "parada no chão: idle tocando")
	var start_frame: int = _sprite.frame
	var seen: Dictionary = {}
	_animation_log.clear()
	for i: int in 60:
		await physics_frame
		seen[_sprite.frame] = true
	_check(_animation_log.is_empty(), "idle não é reiniciada a cada frame (0 trocas em 60 ticks)")
	_check(seen.size() > 1 or _sprite.frame != start_frame, "idle avança os quadros (%d quadros vistos)" % seen.size())


func _test_walk_and_stop() -> void:
	print("-- Walk")
	await _reset(SPAWN)
	_animation_log.clear()
	Input.action_press("move_right")
	await _wait(3)
	_check(_sprite.animation == PlayerCharacter.ANIM_WALK and _sprite.is_playing(), "andando no chão: walk")
	var seen: Dictionary = {}
	for i: int in 40:
		await physics_frame
		seen[_sprite.frame] = true
	_check(_animation_log == [PlayerCharacter.ANIM_WALK], "walk iniciada uma única vez (trocas: %s)" % [_animation_log])
	_check(seen.size() > 1, "walk avança os quadros (%d quadros vistos)" % seen.size())
	Input.action_release("move_right")
	await _wait(15)
	_check(is_zero_approx(_terra.velocity.x) and _sprite.animation == PlayerCharacter.ANIM_IDLE, "solta o direcional e para: idle")


func _test_jump_fall_and_landing() -> void:
	print("-- Jump, Fall e aterrissagem")
	# Parada: idle -> jump -> fall -> idle
	await _reset(SPAWN)
	_animation_log.clear()
	Input.action_press("jump")
	await _wait(2)
	_check(not _terra.is_on_floor() and _terra.velocity.y < 0.0 and _sprite.animation == PlayerCharacter.ANIM_JUMP, "subindo: jump")
	await _wait(12)  # 0,2 s: os 2 quadros de jump (10 FPS) já terminaram, ainda subindo
	_check(_terra.velocity.y < 0.0 and _sprite.frame == 1 and not _sprite.is_playing(), "jump para no último quadro sem reiniciar")
	var saw_fall: bool = false
	var fall_while_rising: bool = false
	var jump_while_falling: bool = false
	while not _terra.is_on_floor():
		await physics_frame
		if _terra.is_on_floor():
			break
		if _terra.velocity.y > 0.0:
			saw_fall = saw_fall or _sprite.animation == PlayerCharacter.ANIM_FALL
			jump_while_falling = jump_while_falling or _sprite.animation == PlayerCharacter.ANIM_JUMP
		elif _terra.velocity.y < 0.0:
			fall_while_rising = fall_while_rising or _sprite.animation == PlayerCharacter.ANIM_FALL
	Input.action_release("jump")
	_check(saw_fall and not jump_while_falling, "descendo: fall")
	_check(not fall_while_rising, "fall nunca aparece durante a subida")
	await _wait(1)
	_check(_terra.is_on_floor() and _sprite.animation == PlayerCharacter.ANIM_IDLE, "aterrissa sem movimento: idle")
	_check(_animation_log == [PlayerCharacter.ANIM_JUMP, PlayerCharacter.ANIM_FALL, PlayerCharacter.ANIM_IDLE],
		"sequência sem trocas extras: %s" % [_animation_log])

	# Andando: walk -> jump -> fall -> walk
	await _reset(SPAWN)
	Input.action_press("move_right")
	await _wait(10)
	_animation_log.clear()
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	await _wait_until_landed()
	await _wait(1)
	_check(_terra.is_on_floor() and absf(_terra.velocity.x) > 1.0 and _sprite.animation == PlayerCharacter.ANIM_WALK, "aterrissa com movimento: walk")
	_check(_animation_log == [PlayerCharacter.ANIM_JUMP, PlayerCharacter.ANIM_FALL, PlayerCharacter.ANIM_WALK],
		"sequência sem trocas extras: %s" % [_animation_log])
	Input.action_release("move_right")


func _test_release_direction_in_air() -> void:
	print("-- Soltar o direcional no ar")
	await _reset(SPAWN)
	Input.action_press("move_right")
	await _wait(10)
	Input.action_press("jump")
	await _wait(3)
	Input.action_release("move_right")
	await _wait(1)
	_check(_sprite.animation == PlayerCharacter.ANIM_JUMP, "soltar o direcional subindo mantém jump")
	while _terra.velocity.y <= 0.0 and not _terra.is_on_floor():
		await physics_frame
	await _wait(2)
	_check(not _terra.is_on_floor() and _sprite.animation == PlayerCharacter.ANIM_FALL, "sem direcional descendo: fall")
	Input.action_release("jump")
	await _wait_until_landed()
	await _wait(30)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE, "pousa e desacelera até parar: idle")


func _test_walls() -> void:
	print("-- Paredes")
	# Parede esquerda do laboratório (termina em x = 0).
	await _reset(Vector2(40.0, FLOOR_Y))
	Input.action_press("move_left")
	await _wait(60)
	_check(absf(_terra.global_position.x - BODY_HALF_WIDTH) < 1.0 and is_zero_approx(_terra.velocity.x),
		"encostada na parede esquerda (x=%.1f, vel=%.1f)" % [_terra.global_position.x, _terra.velocity.x])
	_animation_log.clear()
	await _wait(30)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE and _animation_log.is_empty(),
		"empurrando a parede esquerda: idle estável (trocas: %s)" % [_animation_log])
	_check(_visuals.scale.x == -1.0, "empurrando a parede esquerda: continua virada para ela")
	Input.action_release("move_left")

	# Face esquerda do Step4 (64 px, alto demais para subir).
	await _reset(Vector2(700.0, FLOOR_Y))
	Input.action_press("move_right")
	await _wait(60)
	_check(absf(_terra.global_position.x - (STEP4_LEFT_FACE_X - BODY_HALF_WIDTH)) < 1.0 and _sprite.animation == PlayerCharacter.ANIM_IDLE,
		"empurrando a parede direita: idle (x=%.1f)" % _terra.global_position.x)
	_check(_visuals.scale.x == 1.0, "empurrando a parede direita: continua virada para ela")

	# Pulo contra a parede, segurando o direcional: jump -> fall -> idle, sem walk ao pousar
	# (a personagem não se desloca horizontalmente em nenhum momento).
	_animation_log.clear()
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	await _wait_until_landed()
	await _wait(1)
	_check(_animation_log == [PlayerCharacter.ANIM_JUMP, PlayerCharacter.ANIM_FALL, PlayerCharacter.ANIM_IDLE],
		"pulo contra a parede: %s" % [_animation_log])
	Input.action_release("move_right")


func _test_ledge_fall() -> void:
	print("-- Sair de uma borda")
	await _reset(STEP3_EDGE)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - STEP3_EDGE.y) < 0.5, "em cima do Step3")
	_animation_log.clear()
	Input.action_press("move_right")
	await _wait_until_airborne()
	await _wait(2)
	_check(_terra.velocity.y > 0.0 and _sprite.animation == PlayerCharacter.ANIM_FALL, "sai da borda andando, sem pular: fall")
	Input.action_release("move_right")
	await _wait_until_landed()
	await _wait(30)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE, "pousa e para: idle")
	_check(not _animation_log.has(PlayerCharacter.ANIM_JUMP), "jump não aparece em queda sem pulo (trocas: %s)" % [_animation_log])


func _test_flip() -> void:
	print("-- Flip horizontal")
	await _reset(SPAWN)
	Input.action_press("move_right")
	await _wait(5)
	_check(_visuals.scale.x == 1.0, "direita: scale.x = 1")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _wait(1)
	_check(_visuals.scale.x == -1.0, "esquerda: vira imediatamente (scale.x = -1)")
	Input.action_release("move_left")
	await _wait(20)
	_check(_visuals.scale.x == -1.0, "sem input: mantém o lado")
	Input.action_press("jump")
	await _wait(3)
	Input.action_press("move_right")
	await _wait(1)
	_check(_visuals.scale.x == 1.0 and _sprite.animation == PlayerCharacter.ANIM_JUMP, "vira no ar sem interromper jump")
	_release_all()
	await _wait_until_landed()
	_check(_sprite.scale == Vector2.ONE and _sprite.position == Vector2.ZERO and not _sprite.flip_h,
		"flip feito só pelo Visuals (AnimatedSprite2D intacto)")


func _test_measured_physics() -> void:
	print("-- Física medida")
	var stats: CharacterStats = _terra.stats
	await _reset(SPAWN)
	Input.action_press("move_right")
	var ticks_to_max: int = -1
	for i: int in 60:
		await physics_frame
		if ticks_to_max < 0 and is_equal_approx(_terra.velocity.x, stats.max_speed):
			ticks_to_max = i + 1
	var expected_accel_ticks: int = ceili(stats.max_speed / stats.ground_acceleration * PHYSICS_TICKS)
	_check(absi(ticks_to_max - expected_accel_ticks) <= 1, "aceleração: %.0f px/s em %d ticks (esperado ~%d)" % [stats.max_speed, ticks_to_max, expected_accel_ticks])
	Input.action_release("move_right")
	var ticks_to_stop: int = 0
	while not is_zero_approx(_terra.velocity.x) and ticks_to_stop < 60:
		await physics_frame
		ticks_to_stop += 1
	var expected_decel_ticks: int = ceili(stats.max_speed / stats.ground_deceleration * PHYSICS_TICKS)
	_check(absi(ticks_to_stop - expected_decel_ticks) <= 1, "desaceleração: para em %d ticks (esperado ~%d)" % [ticks_to_stop, expected_decel_ticks])

	await _reset(SPAWN)
	var full_height: float = await _measure_jump_height(1000)
	_check(absf(full_height - stats.jump_height) <= 3.0, "pulo completo: %.1f px (alvo %.0f)" % [full_height, stats.jump_height])
	await _reset(SPAWN)
	var short_height: float = await _measure_jump_height(2)
	_check(short_height < full_height * 0.6, "pulo curto (solta cedo): %.1f px" % short_height)

	await _reset(Vector2(SPAWN.x, -60.0))
	var max_fall: float = 0.0
	for i: int in 60:
		await physics_frame
		max_fall = maxf(max_fall, _terra.velocity.y)
	_check(absf(max_fall - stats.max_fall_speed) < 1.0, "velocidade máxima de queda: %.1f px/s" % max_fall)

	# Coyote time: pulo 3 ticks após sair da borda ainda vale; 10 ticks depois, não.
	for case: Array in [[3, true], [10, false]]:
		await _reset(STEP3_EDGE)
		Input.action_press("move_right")
		var air_ticks: int = 0
		while air_ticks < case[0]:
			await physics_frame
			if not _terra.is_on_floor():
				air_ticks += 1
		Input.action_release("move_right")
		Input.action_press("jump")
		await _wait(2)
		Input.action_release("jump")
		_check((_terra.velocity.y < 0.0) == case[1], "coyote time: %d ticks após a borda -> %s" % [case[0], "pula" if case[1] else "não pula"])

	# Jump buffer: apertar logo antes de tocar o chão executa o pulo ao pousar.
	await _reset(SPAWN)
	_terra.global_position = Vector2(SPAWN.x, 300.0)  # 20 px acima do chão, já caindo no próximo tick
	var pressed: bool = false
	var jumped: bool = false
	for i: int in 60:
		await physics_frame
		if not pressed and not _terra.is_on_floor() and _terra.velocity.y > 0.0 and _terra.global_position.y > 314.0:
			Input.action_press("jump")
			pressed = true
		elif pressed and _terra.velocity.y < 0.0:
			jumped = true
			break
	_check(pressed and jumped, "jump buffer: pulo apertado no ar executa ao pousar")
	_release_all()


func _test_missing_animation_fallback() -> void:
	print("-- Animação ausente")
	# Cópia do SpriteFrames sem walk/jump/fall: o recurso original não é alterado.
	var original_frames: SpriteFrames = _sprite.sprite_frames
	var reduced: SpriteFrames = original_frames.duplicate() as SpriteFrames
	for anim: StringName in [PlayerCharacter.ANIM_WALK, PlayerCharacter.ANIM_JUMP, PlayerCharacter.ANIM_FALL]:
		reduced.remove_animation(anim)
	_sprite.sprite_frames = reduced
	await _reset(SPAWN)
	Input.action_press("move_right")
	await _wait(5)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE and _sprite.is_playing(), "sem walk: idle ao andar")
	Input.action_press("jump")
	await _wait(3)
	_check(not _terra.is_on_floor() and _sprite.animation == PlayerCharacter.ANIM_IDLE and _sprite.is_playing(), "sem jump/fall: idle no ar")
	_release_all()
	await _wait_until_landed()
	_sprite.sprite_frames = original_frames
	_check(original_frames.has_animation(PlayerCharacter.ANIM_WALK), "SpriteFrames original preservado")

	# Cena base sem SpriteFrames: roda sem erro.
	var bare: PlayerCharacter = (load("res://entities/characters/_shared/player_character.tscn") as PackedScene).instantiate()
	bare.stats = _terra.stats
	bare.position = Vector2(300.0, FLOOR_Y)
	_terra.get_parent().add_child(bare)
	await _wait(10)
	_check(is_instance_valid(bare) and bare.is_on_floor(), "personagem sem SpriteFrames roda sem erro")
	bare.queue_free()
	await _wait(1)


# --- Auxiliares -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _on_animation_changed() -> void:
	_animation_log.append(_sprite.animation)


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


func _wait_until_landed(max_ticks: int = 180) -> void:
	for i: int in max_ticks:
		if _terra.is_on_floor():
			return
		await physics_frame


func _wait_until_airborne(max_ticks: int = 120) -> void:
	for i: int in max_ticks:
		if not _terra.is_on_floor():
			return
		await physics_frame


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump"]:
		Input.action_release(action)


func _reset(position: Vector2) -> void:
	_release_all()
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(20)


## Altura máxima atingida (px), soltando o pulo após hold_ticks.
func _measure_jump_height(hold_ticks: int) -> float:
	var start_y: float = _terra.global_position.y
	var min_y: float = start_y
	await physics_frame
	Input.action_press("jump")
	for i: int in 90:
		await physics_frame
		if i == hold_ticks:
			Input.action_release("jump")
		min_y = minf(min_y, _terra.global_position.y)
	Input.action_release("jump")
	return start_y - min_y
