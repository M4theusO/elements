extends SceneTree
## Teste automatizado do Punho Sísmico da Terra (SeismicFist + SeismicWave).
## Simula entradas no laboratório de movimento.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/combat/seismic_fist_test.gd

const LAB_PATH: String = "res://tests/movement_lab/movement_lab.tscn"
const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const BASE_PATH: String = "res://entities/characters/_shared/player_character.tscn"
const WAVE_PATH: String = "res://entities/characters/terra/abilities/seismic_wave.tscn"
const DUMMY_PATH: String = "res://entities/enemies/training_dummy/training_dummy.tscn"

const FLOOR_Y: float = 320.0
## Topo do Step3 (x 640..688) e da plataforma one-way (x 960..1088).
const STEP3_TOP_Y: float = 272.0
const PLATFORM_TOP_Y: float = 272.0
const WINDUP_TICKS: int = 15
const COOLDOWN_TICKS: int = 90
const WAVE_STEP: float = 4.0
const WAVE_RANGE: float = 96.0
const SPAWN_OFFSET: float = 12.0
const WAVE_HALF_WIDTH: float = 8.0

var _failures: int = 0
var _checks: int = 0
var _lab: Node
var _terra: PlayerCharacter
var _fist: SeismicFist
var _melee: MeleeAttack
var _sprite: AnimatedSprite2D
var _visuals: Node2D
var _dummy_scene: PackedScene


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Punho Sísmico")
	await process_frame
	_dummy_scene = load(DUMMY_PATH) as PackedScene
	_check_static_configuration()

	_lab = (load(LAB_PATH) as PackedScene).instantiate()
	root.add_child(_lab)
	_terra = _lab.get_node("Terra") as PlayerCharacter
	_fist = _terra.get_node("SeismicFist") as SeismicFist
	_melee = _terra.get_node("MeleeAttack") as MeleeAttack
	_sprite = _terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	_visuals = _terra.get_node("Visuals") as Node2D
	await _wait(30)

	await _test_activation_and_timing()
	await _test_range_and_damage()
	await _test_direction()
	await _test_facing_lock()
	await _test_global_position_while_moving()
	await _test_air_block()
	await _test_cancel()
	await _test_walls()
	await _test_ledges()
	await _test_one_way_platform()
	await _test_cooldown()
	await _test_basic_attack_compatibility()
	await _test_movement_preserved()
	await _test_animation()

	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração ---------------------------------------------------------------

func _check_static_configuration() -> void:
	print("-- Configuração")
	var terra: PlayerCharacter = (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	var fist: SeismicFist = terra.get_node_or_null("SeismicFist") as SeismicFist
	_check(fist != null and terra.ability == fist, "Terra: ability = SeismicFist")
	_check(is_equal_approx(fist.windup_time, 0.25) and is_equal_approx(fist.wave_speed, 240.0)
		and is_equal_approx(fist.wave_range, WAVE_RANGE) and fist.damage == 2 and is_equal_approx(fist.cooldown_time, 1.5)
		and is_equal_approx(fist.spawn_offset, SPAWN_OFFSET), "valores: 0,25 s, 240 px/s, 96 px, dano 2, recarga 1,5 s")
	_check(fist is CharacterAbility, "SeismicFist implementa CharacterAbility")
	terra.free()
	var base: PlayerCharacter = (load(BASE_PATH) as PackedScene).instantiate() as PlayerCharacter
	_check(base.ability == null, "cena base sem habilidade")
	base.free()

	var wave: SeismicWave = (load(WAVE_PATH) as PackedScene).instantiate() as SeismicWave
	_check(wave is Hitbox, "SeismicWave é uma Hitbox")
	_check(wave.top_level, "SeismicWave usa top_level")
	_check(wave.collision_layer == 0 and wave.collision_mask == 32, "onda: layer nenhuma | mask enemy_hurtbox (6)")
	_check(wave.wall_mask == 1 and wave.ground_mask == 3, "raios: paredes = world; chão = world + platforms")
	var shape: CollisionShape2D = wave.get_node("CollisionShape2D") as CollisionShape2D
	_check((shape.shape as RectangleShape2D).size == Vector2(16, 12) and shape.position == Vector2(0, -6),
		"onda 16x12 com a base na origem")
	_check(not wave.monitoring and not wave.monitorable, "onda começa desativada")
	wave.free()


# --- Simulação ------------------------------------------------------------------

func _test_activation_and_timing() -> void:
	print("-- Ativação no chão e tempos")
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	_check(_fist.is_casting(), "L no chão inicia a preparação")
	var waves: Array[SeismicWave] = _waves()
	_check(waves.size() == 1 and not waves[0].is_launched() and not waves[0].is_active(),
		"aviso da onda criado, ainda sem causar dano")
	var casting_ticks: int = 0
	while _fist.is_casting() and casting_ticks < 60:
		casting_ticks += 1
		await physics_frame
	_check(casting_ticks == WINDUP_TICKS, "preparação: %d ticks (esperado %d)" % [casting_ticks, WINDUP_TICKS])
	waves = _waves()
	_check(waves.size() == 1 and waves[0].is_launched() and waves[0].is_active(), "onda liberada e ativa após a preparação")
	var result: Dictionary = await _follow_wave(waves[0])
	_check(is_equal_approx(result.traveled, WAVE_RANGE), "onda percorre exatamente %.0f px (%.1f)" % [WAVE_RANGE, result.traveled])
	_check(absf(result.end_x - (60.0 + SPAWN_OFFSET + WAVE_RANGE)) < 0.5, "onda termina em x=%.1f (esperado %.1f)" % [result.end_x, 60.0 + SPAWN_OFFSET + WAVE_RANGE])
	_check(_waves().is_empty(), "onda removida ao completar o alcance")
	await _wait_cooldown()


func _test_range_and_damage() -> void:
	print("-- Alcance e dano")
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	var near: Node2D = _spawn_dummy(60.0 + 90.0)
	var far: Node2D = _spawn_dummy(60.0 + 130.0)
	var damaged_count: Array[int] = [0]
	(near.get_node("HealthComponent") as HealthComponent).damaged.connect(func(_a: int) -> void: damaged_count[0] += 1)
	var near_hurtbox: Hurtbox = near.get_node("Hurtbox") as Hurtbox
	await _press("ability")
	await _wait_until_released()
	var wave: SeismicWave = _waves()[0]
	var overlap_ticks: int = 0
	while _is_alive(wave):
		if wave.monitoring and wave.get_overlapping_areas().has(near_hurtbox):
			overlap_ticks += 1
		await physics_frame
	_check(_hp(near) == 1, "inimigo a 90 px recebe 2 de dano (vida %d)" % _hp(near))
	_check(_hp(far) == 3, "inimigo a 130 px está fora do alcance (vida %d)" % _hp(far))
	_check(damaged_count[0] == 1 and overlap_ticks >= 3,
		"um único dano apesar de %d ticks de sobreposição" % overlap_ticks)
	for dummy: Node2D in [near, far]:
		dummy.queue_free()
	await _wait_cooldown()

	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	var first: Node2D = _spawn_dummy(100.0)
	var second: Node2D = _spawn_dummy(140.0)
	await _press("ability")
	await _wait_until_released()
	await _follow_wave(_waves()[0])
	_check(_hp(first) == 1 and _hp(second) == 1, "uma onda atinge dois inimigos, 2 de dano cada (vidas %d e %d)" % [_hp(first), _hp(second)])
	first.queue_free()
	second.queue_free()
	await _wait_cooldown()


func _test_direction() -> void:
	print("-- Direção")
	await _reset(Vector2(220.0, FLOOR_Y), -1.0)
	var front: Node2D = _spawn_dummy(220.0 - 90.0)
	var back: Node2D = _spawn_dummy(220.0 + 25.0)
	var far: Node2D = _spawn_dummy(220.0 - 130.0)
	await _press("ability")
	await _wait_until_released()
	var result: Dictionary = await _follow_wave(_waves()[0])
	# _follow_wave começa a observar após o primeiro passo (a onda anda no tick da liberação).
	_check(result.end_x < result.start_x and absf(result.end_x - (220.0 - SPAWN_OFFSET - WAVE_RANGE)) < 0.5,
		"olhando para a esquerda: segue para a esquerda e termina em x=%.1f (esperado %.1f)" % [result.end_x, 220.0 - SPAWN_OFFSET - WAVE_RANGE])
	_check(_hp(front) == 1 and _hp(back) == 3 and _hp(far) == 3,
		"esquerda: acerta à frente, não atrás nem fora do alcance (%d, %d, %d)" % [_hp(front), _hp(back), _hp(far)])
	for dummy: Node2D in [front, back, far]:
		dummy.queue_free()
	await _wait_cooldown()
	# Direita já coberta em _test_range_and_damage; aqui confirma o sentido.
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	await _wait_until_released()
	result = await _follow_wave(_waves()[0])
	_check(result.end_x > result.start_x, "olhando para a direita: segue para a direita")
	await _wait_cooldown()


func _test_facing_lock() -> void:
	print("-- Direção travada na preparação")
	await _reset(Vector2(120.0, FLOOR_Y), 1.0)
	await _press("ability")
	Input.action_press("move_left")
	var locked: bool = true
	while _fist.is_casting():
		locked = locked and _visuals.scale.x == 1.0
		await physics_frame
	var wave: SeismicWave = _waves()[0]
	await _wait(2)
	_check(locked, "virar durante a preparação não muda o lado")
	_check(_visuals.scale.x == -1.0, "após a liberação a direção é liberada")
	var result: Dictionary = await _follow_wave(wave)
	Input.action_release("move_left")
	_check(result.end_x > result.start_x, "a onda segue o lado travado (direita), não o novo")
	await _wait_cooldown()


func _test_global_position_while_moving() -> void:
	print("-- Posição global e top_level com a Terra em movimento")
	for facing: float in [1.0, -1.0]:
		var side: String = "direita" if facing > 0.0 else "esquerda"
		var start_x: float = 60.0 if facing > 0.0 else 230.0
		await _reset(Vector2(start_x, FLOOR_Y), facing)
		var walk: String = "move_right" if facing > 0.0 else "move_left"
		var back_action: String = "move_left" if facing > 0.0 else "move_right"
		Input.action_press(walk)
		await _wait(20)
		await _press("ability")
		var follows: bool = true
		var wave: SeismicWave = _waves()[0]
		while _fist.is_casting():
			# O aviso acompanha a frente da Terra (até 1 tick de deslocamento de diferença).
			var expected: float = _terra.global_position.x + facing * SPAWN_OFFSET
			follows = follows and absf(wave.global_position.x - expected) <= 2.0 and wave.global_position.y == _terra.global_position.y
			await physics_frame
		_check(follows, "%s: aviso acompanha a frente da Terra andando" % side)
		# Libera, e a Terra passa a andar no sentido oposto.
		Input.action_release(walk)
		Input.action_press(back_action)
		var steps_ok: bool = true
		var top_level_ok: bool = true
		var last_x: float = wave.global_position.x
		var y0: float = wave.global_position.y
		var ticks: int = 0
		await physics_frame
		while _is_alive(wave):
			var dx: float = wave.global_position.x - last_x
			steps_ok = steps_ok and (is_equal_approx(dx, facing * WAVE_STEP) or is_zero_approx(dx))
			top_level_ok = top_level_ok and wave.position == wave.global_position and wave.global_position.y == y0
			last_x = wave.global_position.x
			ticks += 1
			await physics_frame
		Input.action_release(back_action)
		_check(steps_ok and ticks >= 20, "%s: onda anda %.0f px/tick no sentido original, independente da Terra" % [side, WAVE_STEP])
		_check(top_level_ok, "%s: position == global_position (top_level) e altura constante" % side)
		await _wait_cooldown()


func _test_air_block() -> void:
	print("-- Bloqueio no ar")
	await _reset(Vector2(120.0, FLOOR_Y), 1.0)
	Input.action_press("jump")
	await _wait(8)
	await _press("ability")
	_check(not _terra.is_on_floor() and not _fist.is_casting() and _waves().is_empty(), "L no ar não faz nada")
	Input.action_release("jump")
	await _wait_until_landed()
	await _wait(1)
	await _press("ability")
	_check(_fist.is_casting(), "ao pousar, ativa na hora (recarga não foi gasta)")
	await _wait_until_released()
	await _follow_wave(_waves()[0])
	await _wait_cooldown()


func _test_cancel() -> void:
	print("-- Cancelamento")
	# Pulando durante a preparação.
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	var dummy: Node2D = _spawn_dummy(60.0 + 30.0)
	await _press("ability")
	await _wait(4)
	var pending: SeismicWave = _waves()[0]
	Input.action_press("jump")
	await _wait(3)
	_check(not _fist.is_casting(), "pular durante a preparação cancela")
	_check(not is_instance_valid(pending) and _waves().is_empty(), "nenhuma onda ou aviso permanece")
	Input.action_release("jump")
	await _wait(60)
	_check(_hp(dummy) == 3, "cancelada: nenhum dano")
	await _wait_until_landed()
	await _wait(1)
	await _press("ability")
	_check(_fist.is_casting(), "cancelada: sem recarga (ativa de novo ao pousar)")
	await _wait_until_released()
	await _follow_wave(_waves()[0])
	_check(_hp(dummy) == 1, "nova ativação funciona normalmente")
	dummy.queue_free()
	await _wait_cooldown()

	# Saindo de uma borda andando durante a preparação.
	await _reset(Vector2(684.0, STEP3_TOP_Y), 1.0)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - STEP3_TOP_Y) < 0.5, "Terra na borda do Step3")
	Input.action_press("move_right")
	await _press("ability")
	_check(_fist.is_casting(), "preparação iniciada andando para a borda")
	var cancelled_in_air: bool = false
	for i: int in WINDUP_TICKS + 5:
		await physics_frame
		if not _fist.is_casting():
			cancelled_in_air = not _terra.is_on_floor()
			break
	Input.action_release("move_right")
	await _wait(1)
	_check(cancelled_in_air and _waves().is_empty(), "cair da borda cancela, sem onda")
	await _wait_until_landed()
	await _wait(1)
	await _press("ability")
	_check(_fist.is_casting(), "sem recarga após cair da borda")
	await _wait_until_released()
	await _follow_wave(_waves()[0])
	await _wait_cooldown()


func _test_walls() -> void:
	print("-- Paredes")
	# Step1 (face esquerda em x = 400).
	await _reset(Vector2(360.0, FLOOR_Y), 1.0)
	var before_wall: Node2D = _spawn_dummy(390.0)
	var behind_wall: Node2D = _spawn_dummy(460.0)
	await _press("ability")
	await _wait_until_released()
	var result: Dictionary = await _follow_wave(_waves()[0])
	_check(result.max_front <= 400.0 + 0.01, "onda não passa da parede do Step1 (borda frontal máx. %.1f)" % result.max_front)
	_check(result.traveled < WAVE_RANGE, "onda some ao bater na parede (percorreu %.0f px)" % result.traveled)
	_check(_hp(before_wall) == 1 and _hp(behind_wall) == 3, "acerta antes da parede, não atrás dela (%d, %d)" % [_hp(before_wall), _hp(behind_wall)])
	before_wall.queue_free()
	behind_wall.queue_free()
	await _wait_cooldown()

	# Encostada na parede esquerda do laboratório (x = 0): a onda nasceria dentro dela.
	await _reset(Vector2(8.0, FLOOR_Y), -1.0)
	await _press("ability")
	# Guarda a referência ainda na preparação: a onda some no próprio tick da liberação.
	var blocked_wave: SeismicWave = _waves()[0]
	var start_x: float = blocked_wave.global_position.x
	await _wait_until_released()
	var blocked_ticks: int = 0
	while _is_alive(blocked_wave):
		blocked_ticks += 1
		await physics_frame
	_check(blocked_ticks == 0 and _waves().is_empty(),
		"colada na parede: a onda some ao ser liberada, sem avançar (nasceria em x=%.0f, dentro da parede)" % start_x)
	await _wait_cooldown()


func _test_ledges() -> void:
	print("-- Bordas e buracos")
	# Topo do Step3, indo para a direita (borda em x = 688). Bonecos "flutuando" na altura do topo.
	await _reset(Vector2(650.0, STEP3_TOP_Y), 1.0)
	var on_step: Node2D = _spawn_dummy(680.0, STEP3_TOP_Y)
	var over_gap: Node2D = _spawn_dummy(720.0, STEP3_TOP_Y)
	await _press("ability")
	await _wait_until_released()
	var result: Dictionary = await _follow_wave(_waves()[0])
	_check(result.max_center <= 688.0, "direita: centro da onda não passa da borda (máx. %.1f)" % result.max_center)
	_check(_hp(on_step) == 1 and _hp(over_gap) == 3, "acerta sobre o degrau, não além da borda (%d, %d)" % [_hp(on_step), _hp(over_gap)])
	on_step.queue_free()
	over_gap.queue_free()
	await _wait_cooldown()
	# Indo para a esquerda (borda em x = 640).
	await _reset(Vector2(680.0, STEP3_TOP_Y), -1.0)
	var left_gap: Node2D = _spawn_dummy(610.0, STEP3_TOP_Y)
	await _press("ability")
	await _wait_until_released()
	result = await _follow_wave(_waves()[0])
	_check(result.min_center >= 640.0 and _hp(left_gap) == 3, "esquerda: para na borda (mín. %.1f), não atinge além" % result.min_center)
	left_gap.queue_free()
	await _wait_cooldown()


func _test_one_way_platform() -> void:
	print("-- Plataforma one-way")
	await _reset(Vector2(975.0, PLATFORM_TOP_Y), 1.0)
	_check(_terra.is_on_floor() and absf(_terra.global_position.y - PLATFORM_TOP_Y) < 0.5, "Terra sobre a plataforma")
	var on_platform: Node2D = _spawn_dummy(1060.0, PLATFORM_TOP_Y)
	await _press("ability")
	await _wait_until_released()
	var result: Dictionary = await _follow_wave(_waves()[0])
	_check(is_equal_approx(result.traveled, WAVE_RANGE), "sobre a plataforma: percorre o alcance inteiro (%.0f px)" % result.traveled)
	_check(_hp(on_platform) == 1, "sobre a plataforma: acerta o inimigo")
	on_platform.queue_free()
	await _wait_cooldown()

	await _reset(Vector2(1050.0, PLATFORM_TOP_Y), 1.0)
	var past_edge: Node2D = _spawn_dummy(1110.0, PLATFORM_TOP_Y)
	await _press("ability")
	await _wait_until_released()
	result = await _follow_wave(_waves()[0])
	_check(result.max_center <= 1088.0 and _hp(past_edge) == 3, "para na borda da plataforma (máx. %.1f)" % result.max_center)
	past_edge.queue_free()
	await _wait_cooldown()

	# No chão, passando por baixo da plataforma (a plataforma não conta como parede).
	await _reset(Vector2(930.0, FLOOR_Y), 1.0)
	var under: Node2D = _spawn_dummy(1030.0)
	await _press("ability")
	await _wait_until_released()
	result = await _follow_wave(_waves()[0])
	_check(is_equal_approx(result.traveled, WAVE_RANGE) and _hp(under) == 1, "passa por baixo da plataforma e acerta (%.0f px)" % result.traveled)
	under.queue_free()
	await _wait_cooldown()


func _test_cooldown() -> void:
	print("-- Recarga")
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	await _wait_until_released()
	# Ao retomar após physics_frame, get_physics_frames() já indica o próximo tick a rodar.
	var release_tick: int = Engine.get_physics_frames() - 1
	var extra_waves: bool = false
	var reactivated_after: int = -1
	# Aperta e solta a cada tick (just_pressed a cada 2 ticks) até reativar.
	for tick: int in 120:
		if tick % 2 == 0:
			Input.action_press("ability")
		else:
			Input.action_release("ability")
		await physics_frame
		if _fist.is_casting():
			reactivated_after = (Engine.get_physics_frames() - 1) - release_tick
			break
		extra_waves = extra_waves or _waves().size() > 1
	Input.action_release("ability")
	_check(not extra_waves, "apertos durante a recarga não criam ondas")
	# Os apertos simulados só geram just_pressed a cada 2 ticks: 90 ou 91.
	_check(reactivated_after == COOLDOWN_TICKS or reactivated_after == COOLDOWN_TICKS + 1,
		"reativa %d ticks após a liberação (recarga de %d ticks)" % [reactivated_after, COOLDOWN_TICKS])
	await _wait_until_released()
	await _wait_cooldown()


func _test_basic_attack_compatibility() -> void:
	print("-- Compatibilidade com o ataque básico")
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	await _press("attack")
	_check(_fist.is_casting() and not _melee.is_busy(), "J durante a preparação é ignorado")
	await _wait_until_released()
	await _press("attack")
	_check(_melee.is_busy() and _waves().size() == 1, "J com a onda em movimento funciona")
	await _wait_melee_ready()
	await _wait_cooldown()

	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("attack")
	await _press("ability")
	_check(_melee.is_striking() and not _fist.is_casting(), "L durante o golpe básico é ignorado")
	while _melee.is_striking():
		await physics_frame
	await _press("ability")
	_check(_fist.is_casting(), "L na recuperação do golpe básico funciona")
	await _wait_until_released()
	await _follow_wave(_waves()[0])
	await _wait_melee_ready()
	await _wait_cooldown()

	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	var dummy: Node2D = _spawn_dummy(60.0 + 20.0)
	await _press("attack")
	await _wait_melee_ready()
	await _press("ability")
	await _wait_until_released()
	await _wait(10)
	_check(not is_instance_valid(dummy) or _hp(dummy) == 0, "soco (1) + onda (2) derrotam o boneco")
	await _wait(20)
	await _wait_cooldown()


func _test_movement_preserved() -> void:
	print("-- Movimento e pulo preservados")
	var reference: Array[Vector2] = await _record_run(-1)
	var flags: Array[bool] = [false]
	var with_release: Array[Vector2] = await _record_run(3, flags)
	_check(flags[0], "percurso com a habilidade: onda liberada")
	_check(_same_path(reference, with_release), "andar + pular com a habilidade liberada: posições idênticas (%d ticks)" % reference.size())
	await _wait_cooldown()
	flags[0] = false
	var with_cancel: Array[Vector2] = await _record_run(22, flags)
	_check(not flags[0], "percurso com pulo na preparação: habilidade cancelada")
	_check(_same_path(reference, with_cancel), "andar + pular cancelando a habilidade: posições idênticas")
	await _wait_cooldown()


func _test_animation() -> void:
	print("-- Animação ability")
	var original: SpriteFrames = _sprite.sprite_frames
	var anim: StringName = PlayerCharacter.ANIM_ABILITY
	# Formato: 4 quadros 64x64 (agachar, erguer, descer, impacto), 60 FPS, durações 4/4/4/3 = 15 ticks = preparação de 0,25 s.
	var durations: Array[float] = [4.0, 4.0, 4.0, 3.0]
	var format_ok: bool = original.has_animation(anim) and original.get_frame_count(anim) == 4 \
		and is_equal_approx(original.get_animation_speed(anim), 60.0) and not original.get_animation_loop(anim)
	if format_ok:
		for i: int in 4:
			var atlas: AtlasTexture = original.get_frame_texture(anim, i) as AtlasTexture
			format_ok = format_ok and atlas != null and atlas.region == Rect2(i * 64, 0, 64, 64) \
				and atlas.atlas.resource_path.ends_with("terra_seismic_fist.png") \
				and is_equal_approx(original.get_frame_duration(anim, i), durations[i])
	_check(format_ok, "ability: 4 quadros 64x64 de terra_seismic_fist.png, 60 FPS, sem loop, durações 4/4/4/3")

	# Habilidade real: começa no quadro 0, avança em ordem e chega ao impacto (quadro 3) antes da onda nascer.
	# Tolerância de 1 tick: o AnimatedSprite2D avança no _process, não no tick de física.
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	var starts_at_zero: bool = _sprite.animation == anim and _sprite.frame == 0
	var frames_seen: Array[int] = []
	var ability_while_casting: bool = true
	while _fist.is_casting():
		ability_while_casting = ability_while_casting and _sprite.animation == anim
		frames_seen.append(_sprite.frame)
		await physics_frame
	var in_order: bool = true
	for i: int in range(1, frames_seen.size()):
		in_order = in_order and frames_seen[i] >= frames_seen[i - 1]
	var impact_ticks: int = frames_seen.count(3)
	_check(starts_at_zero and ability_while_casting and in_order,
		"com ability: toca em ordem durante a preparação (quadros por tick: %s)" % [frames_seen])
	_check(impact_ticks >= 2 and impact_ticks <= 4, "impacto (quadro 3) nos últimos ticks da preparação (%d ticks)" % impact_ticks)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE, "após a liberação: volta para idle")
	await _follow_wave(_waves()[0])
	await _wait_cooldown()

	# Sem ability no SpriteFrames (cópia em memória): mantém a animação normal.
	var without_ability: SpriteFrames = original.duplicate() as SpriteFrames
	without_ability.remove_animation(anim)
	_sprite.sprite_frames = without_ability
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	await _press("ability")
	var kept_idle: bool = true
	while _fist.is_casting():
		kept_idle = kept_idle and _sprite.animation == PlayerCharacter.ANIM_IDLE and _sprite.is_playing()
		await physics_frame
	_check(kept_idle, "sem ability: idle durante a preparação")
	_sprite.sprite_frames = original
	await _follow_wave(_waves()[0])
	await _wait_cooldown()
	_check(original.has_animation(anim), "SpriteFrames original inalterado")


# --- Auxiliares -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


## A entrada simulada só é vista no tick seguinte ao press; ao retornar, o efeito já ocorreu.
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
	await _wait_until_released()
	await _wait_melee_ready()
	var action: String = "move_right" if facing > 0.0 else "move_left"
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(20)
	_terra.global_position = position
	_terra.velocity = Vector2.ZERO
	await _wait(2)


func _wait_until_released(max_ticks: int = 60) -> void:
	for i: int in max_ticks:
		if not _fist.is_casting():
			return
		await physics_frame


func _wait_melee_ready(max_ticks: int = 60) -> void:
	for i: int in max_ticks:
		if not _melee.is_busy():
			return
		await physics_frame


## Espera a recarga (e qualquer onda em andamento) terminar.
func _wait_cooldown() -> void:
	_release_all()
	await _wait(COOLDOWN_TICKS + 5)


func _wait_until_landed(max_ticks: int = 180) -> void:
	for i: int in max_ticks:
		if _terra.is_on_floor():
			return
		await physics_frame


func _waves() -> Array[SeismicWave]:
	var result: Array[SeismicWave] = []
	for child: Node in _terra.get_children():
		if child is SeismicWave and not child.is_queued_for_deletion():
			result.append(child as SeismicWave)
	return result


func _is_alive(node: Variant) -> bool:
	return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()


## Acompanha a onda até ela sumir; registra posições extremas e distância percorrida.
func _follow_wave(wave: SeismicWave) -> Dictionary:
	var direction: float = 0.0
	var result: Dictionary = {
		"start_x": wave.global_position.x, "end_x": wave.global_position.x,
		"max_center": wave.global_position.x, "min_center": wave.global_position.x,
		"max_front": -INF, "traveled": 0.0, "ticks": 0,
	}
	while _is_alive(wave):
		var x: float = wave.global_position.x
		if direction == 0.0 and x != result.start_x:
			direction = signf(x - result.start_x)
		result.end_x = x
		result.max_center = maxf(result.max_center, x)
		result.min_center = minf(result.min_center, x)
		result.max_front = maxf(result.max_front, x + WAVE_HALF_WIDTH)
		result.traveled = wave.get_traveled_distance()
		result.ticks += 1
		await physics_frame
	return result


func _spawn_dummy(x: float, feet_y: float = FLOOR_Y) -> Node2D:
	var dummy: Node2D = _dummy_scene.instantiate() as Node2D
	dummy.position = Vector2(x, feet_y)
	_lab.add_child(dummy)
	return dummy


func _hp(dummy: Node) -> int:
	return (dummy.get_node("HealthComponent") as HealthComponent).current_health


func _same_path(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


## Percurso fixo: anda para a direita e pula no tick 30. Aperta L no tick indicado (-1 = não).
## flags[0] indica se alguma onda foi liberada.
func _record_run(ability_tick: int, flags: Array[bool] = [false]) -> Array[Vector2]:
	await _reset(Vector2(60.0, FLOOR_Y), 1.0)
	var positions: Array[Vector2] = []
	Input.action_press("move_right")
	for i: int in 70:
		if i == 30:
			Input.action_press("jump")
		elif i == 45:
			Input.action_release("jump")
		if i == ability_tick:
			Input.action_press("ability")
		elif i == ability_tick + 1:
			Input.action_release("ability")
		await physics_frame
		positions.append(_terra.global_position)
		for wave: SeismicWave in _waves():
			flags[0] = flags[0] or wave.is_launched()
	_release_all()
	await _wait_until_landed()
	return positions
