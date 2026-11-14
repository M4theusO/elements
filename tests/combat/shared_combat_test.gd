extends SceneTree
## Teste automatizado da base compartilhada de combate e inimigos: direção do golpe
## (Hitbox → Hurtbox, inclusive a onda sísmica), gancho de dano da Hurtbox,
## MeleeAttack.finish_active() e helpers genéricos da base Enemy.
## Cada caso monta um cenário próprio em código.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/combat/shared_combat_test.gd

const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const DUMMY_PATH: String = "res://entities/enemies/training_dummy/training_dummy.tscn"
const WAVE_PATH: String = "res://entities/characters/terra/abilities/seismic_wave.tscn"

const FLOOR_Y: float = 400.0
const LAYER_WORLD: int = 1
## Layer de teste para hitbox/hurtbox montadas à mão (enemy_hurtbox).
const LAYER_TEST_HURTBOX: int = 32
## Fases do golpe de teste: 6 / 30 / 12 ticks.
const TEST_WINDUP: float = 0.1
const TEST_ACTIVE: float = 0.5
const TEST_RECOVERY: float = 0.2
const TEST_RECOVERY_TICKS: int = 12


## Hurtbox com o gancho sobrescrito: golpes vindos da direita (direção +x) não causam dano;
## direção -y devolve dano negativo (deve virar 0).
class SideHurtbox extends Hurtbox:
	func _get_damage_taken(damage: int, hit_direction: Vector2) -> int:
		if hit_direction.y < 0.0:
			return -5
		return 0 if hit_direction.x > 0.0 else damage


## Chama um Callable no tick seguinte ao armar, depois do MeleeAttack (prioridade padrão 0 > -1),
## como faz um inimigo dono do golpe.
class LateCaller extends Node:
	var action: Callable
	var result: Variant
	var frame: int = -1

	func _physics_process(_delta: float) -> void:
		if action.is_valid():
			result = action.call()
			frame = Engine.get_physics_frames()
			action = Callable()


var _failures: int = 0
var _checks: int = 0
var _world: Node2D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Base compartilhada de combate")
	await process_frame

	await _test_hitbox_direction()
	await _test_wave_direction()
	await _test_hurtbox_direction()
	await _test_damage_hook()
	await _test_direction_through_physics()
	await _test_terra_attacks_report_direction()
	await _test_finish_active()
	await _test_enemy_helpers()

	_release_all()
	if _world != null:
		_world.free()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Direção do golpe -------------------------------------------------------------

func _test_hitbox_direction() -> void:
	print("-- Hitbox.get_hit_direction()")
	await _new_world()
	var parent: Node2D = Node2D.new()
	_world.add_child(parent)
	var hitbox: Hitbox = _make_hitbox(parent)
	_check(hitbox.get_hit_direction().is_equal_approx(Vector2.RIGHT), "sem flip: (1, 0)")
	parent.scale.x = -1.0
	_check(hitbox.get_hit_direction().is_equal_approx(Vector2.LEFT), "pai com flip (scale.x = -1): (-1, 0)")
	parent.scale = Vector2(2.0, 2.0)
	_check(hitbox.get_hit_direction().is_equal_approx(Vector2.RIGHT), "escala do pai não altera o tamanho do vetor")
	parent.scale = Vector2.ONE
	parent.rotation = PI / 2.0
	_check(hitbox.get_hit_direction().is_equal_approx(Vector2.DOWN), "pai girado 90°: (0, 1)")


func _test_wave_direction() -> void:
	print("-- SeismicWave.get_hit_direction()")
	await _new_world()
	_floor(0.0, 1000.0)
	for direction: float in [1.0, -1.0]:
		var wave: SeismicWave = (load(WAVE_PATH) as PackedScene).instantiate() as SeismicWave
		_world.add_child(wave)
		wave.global_position = Vector2(500.0, FLOOR_Y)
		wave.launch(direction, 240.0, 96.0, 2, 500.0)
		_check(wave.get_hit_direction().is_equal_approx(Vector2(direction, 0.0)),
			"onda lançada para %s: (%d, 0), sem depender da escala" % ["a direita" if direction > 0.0 else "a esquerda", int(direction)])
		wave.queue_free()
	await physics_frame


func _test_hurtbox_direction() -> void:
	print("-- Hurtbox: direção recebida")
	await _new_world()
	var health: HealthComponent = _make_health(5)
	var hurtbox: Hurtbox = Hurtbox.new()
	hurtbox.health = health
	_world.add_child(hurtbox)
	var received: Array[int] = []
	hurtbox.hit_received.connect(func(damage: int) -> void: received.append(damage))
	_check(hurtbox.get_last_hit_direction() == Vector2.ZERO, "sem golpes: direção (0, 0)")
	hurtbox.receive_hit(2)
	_check(received == [2] and health.current_health == 3 and hurtbox.get_last_hit_direction() == Vector2.ZERO,
		"chamada antiga (só dano): repassa o dano, direção desconhecida (0, 0)")
	hurtbox.receive_hit(1, Vector2.LEFT)
	_check(received == [2, 1] and health.current_health == 2 and hurtbox.get_last_hit_direction() == Vector2.LEFT,
		"com direção: dano normal e direção guardada")

	hurtbox.invulnerability_time = 0.5
	hurtbox.receive_hit(1, Vector2.RIGHT)
	hurtbox.receive_hit(1, Vector2.LEFT)
	_check(received == [2, 1, 1] and hurtbox.get_last_hit_direction() == Vector2.RIGHT,
		"golpe ignorado pela invulnerabilidade não altera a direção guardada")


func _test_damage_hook() -> void:
	print("-- Hurtbox: gancho _get_damage_taken")
	await _new_world()
	var health: HealthComponent = _make_health(5)
	var hurtbox: SideHurtbox = SideHurtbox.new()
	hurtbox.health = health
	_world.add_child(hurtbox)
	var received: Array[int] = []
	var damaged: Array[int] = []
	hurtbox.hit_received.connect(func(damage: int) -> void: received.append(damage))
	health.damaged.connect(func(amount: int) -> void: damaged.append(amount))

	hurtbox.receive_hit(2, Vector2.RIGHT)
	_check(received == [0] and damaged.is_empty() and health.current_health == 5
		and hurtbox.get_last_hit_direction() == Vector2.RIGHT,
		"gancho zera o dano: hit_received(0), vida intacta, sem damaged")
	hurtbox.receive_hit(2, Vector2.LEFT)
	_check(received == [0, 2] and damaged == [2] and health.current_health == 3, "gancho mantém o dano: aplicado normalmente")
	hurtbox.receive_hit(2, Vector2.UP)
	_check(received == [0, 2, 0] and health.current_health == 3, "resultado negativo do gancho vira 0 (não cura)")


func _test_direction_through_physics() -> void:
	print("-- Hitbox → Hurtbox pela física")
	await _new_world()
	var health: HealthComponent = _make_health(5)
	var hurtbox: Hurtbox = _make_hurtbox(Vector2(500.0, 300.0), health)
	var attacker: Node2D = Node2D.new()
	attacker.position = Vector2(500.0, 300.0)
	attacker.scale.x = -1.0
	_world.add_child(attacker)
	var hitbox: Hitbox = _make_hitbox(attacker)
	await _wait(2)
	hitbox.activate()
	await _wait(4)
	_check(health.current_health == 4 and hurtbox.get_last_hit_direction().is_equal_approx(Vector2.LEFT),
		"golpe de hitbox virada para a esquerda: 1 de dano, direção (-1, 0) na hurtbox")
	hitbox.deactivate()


func _test_terra_attacks_report_direction() -> void:
	print("-- Golpes reais da Terra informam a direção")
	for facing: float in [1.0, -1.0]:
		await _new_world()
		_floor(0.0, 1000.0)
		var terra: PlayerCharacter = await _spawn_terra(500.0, facing)
		var dummy: Enemy = _spawn_dummy(500.0 + facing * 20.0)
		await _wait(2)
		var dummy_hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
		await _press("attack")
		await _wait(20)
		_check(_hp(dummy) == 2 and dummy_hurtbox.get_last_hit_direction().is_equal_approx(Vector2(facing, 0.0)),
			"soco para %s: direção (%d, 0)" % [_side(facing), int(facing)])

		dummy.queue_free()
		dummy = _spawn_dummy(500.0 + facing * 50.0)
		await _wait(2)
		dummy_hurtbox = dummy.get_node("Hurtbox") as Hurtbox
		var fist: SeismicFist = terra.get_node("SeismicFist") as SeismicFist
		await _press("ability")
		_check(fist.is_casting(), "Punho Sísmico iniciado para %s" % _side(facing))
		await _wait(45)
		_check(_hp(dummy) == 1 and dummy_hurtbox.get_last_hit_direction().is_equal_approx(Vector2(facing, 0.0)),
			"onda sísmica para %s: dano 2, direção (%d, 0)" % [_side(facing), int(facing)])


# --- MeleeAttack.finish_active() --------------------------------------------------

func _test_finish_active() -> void:
	print("-- MeleeAttack.finish_active()")
	await _new_world()
	var attacker_root: Node2D = Node2D.new()
	attacker_root.position = Vector2(500.0, 300.0)
	_world.add_child(attacker_root)
	var hitbox: Hitbox = _make_hitbox(attacker_root)
	var melee: MeleeAttack = MeleeAttack.new()
	var data: AttackData = AttackData.new()
	data.damage = 1
	data.windup_time = TEST_WINDUP
	data.active_time = TEST_ACTIVE
	data.recovery_time = TEST_RECOVERY
	melee.attack = data
	melee.hitbox = hitbox
	attacker_root.add_child(melee)
	var caller: LateCaller = LateCaller.new()
	attacker_root.add_child(caller)
	var started: Array[int] = [0]
	var finished_frames: Array[int] = []
	melee.attack_started.connect(func() -> void: started[0] += 1)
	melee.attack_finished.connect(func() -> void: finished_frames.append(Engine.get_physics_frames()))
	# Hurtbox longe do alcance; entra nele depois do encerramento antecipado.
	var health: HealthComponent = _make_health(10)
	var hurtbox: Hurtbox = _make_hurtbox(Vector2(800.0, 300.0), health)
	await _wait(2)

	_check(not melee.finish_active() and not melee.is_busy(), "pronto: finish_active() não faz nada")

	melee.try_attack()
	await physics_frame
	_check(not melee.finish_active() and melee.is_striking() and not hitbox.is_active(),
		"preparação: finish_active() retorna false e não liga a hitbox")
	var windup_left: int = 0
	while not hitbox.is_active() and windup_left < 30:
		await physics_frame
		windup_left += 1
	_check(hitbox.is_active() and windup_left <= int(TEST_WINDUP * 60.0),
		"preparação segue o tempo normal até a fase ativa (sem adiantar nem pular)")

	await _wait(5)
	caller.action = melee.finish_active
	await physics_frame
	var finish_frame: int = caller.frame
	_check(caller.result == true and not hitbox.is_active() and melee.is_busy() and not melee.is_striking(),
		"fase ativa: finish_active() retorna true, desliga a hitbox e entra na recuperação")
	await physics_frame
	_check(not hitbox.monitoring, "monitoring desligado no tick seguinte (set_deferred)")

	hurtbox.global_position = attacker_root.global_position
	caller.action = melee.finish_active
	await physics_frame
	_check(caller.result == false and melee.is_busy(), "recuperação: finish_active() retorna false")
	var reactivated: bool = false
	while melee.is_busy():
		await physics_frame
		reactivated = reactivated or hitbox.is_active() or hitbox.monitoring
	_check(not reactivated and health.current_health == 10, "hitbox não religa e não acerta durante a recuperação")
	_check(finished_frames.size() == 1 and finished_frames[0] - finish_frame == TEST_RECOVERY_TICKS,
		"recuperação completa (%d ticks) contada a partir do encerramento; attack_finished uma vez (%s)"
		% [TEST_RECOVERY_TICKS, finished_frames.map(func(f: int) -> int: return f - finish_frame)])

	_check(melee.try_attack(), "golpe seguinte começa normalmente")
	await _wait(int(TEST_WINDUP * 60.0) + 4)
	_check(hitbox.is_active() and health.current_health == 9 and started[0] == 2,
		"golpe seguinte: fase ativa liga a hitbox e acerta o alvo de novo (lista de alvos limpa)")
	while melee.is_busy():
		await physics_frame
	_check(health.current_health == 9 and finished_frames.size() == 2,
		"golpe sem encerramento antecipado: um acerto e fim normal")


# --- Helpers da base Enemy --------------------------------------------------------

func _test_enemy_helpers() -> void:
	print("-- Helpers da base Enemy")
	await _new_world()
	_floor(0.0, 300.0)
	var wall: StaticBody2D = _box(400.0, FLOOR_Y - 100.0, 410.0, FLOOR_Y)
	var dummy: Enemy = _spawn_dummy(100.0)
	await _wait(2)
	_check(dummy.get_facing() == 1.0, "get_facing(): 1 (Visuals sem flip)")
	dummy._set_facing(-1.0)
	_check(dummy.get_facing() == -1.0 and (dummy.get_node("Visuals") as Node2D).scale.x == -1.0,
		"_set_facing(-1): vira Visuals")
	_check(is_equal_approx(dummy._half_width, 8.0), "_half_width lido do corpo retangular (16 px)")

	_check(dummy._has_ground_ahead(1.0, 1.0, LAYER_WORLD), "chão à frente no meio da plataforma")
	dummy.global_position.x = 290.0
	await physics_frame
	_check(not dummy._has_ground_ahead(1.0, 4.0, LAYER_WORLD) and dummy._has_ground_ahead(-1.0, 4.0, LAYER_WORLD),
		"borda: sem chão à direita (fim em x 300), com chão à esquerda")
	_check(not dummy._has_ground_ahead(-1.0, 4.0, 2), "mask sem a layer do chão: não encontra chão")

	var target: Node2D = Node2D.new()
	target.global_position = Vector2(200.0, FLOOR_Y)
	_world.add_child(target)
	_check(dummy._has_line_of_sight(target, 12.0, 16.0, LAYER_WORLD), "linha de visão livre")
	target.global_position = Vector2(500.0, FLOOR_Y)
	await physics_frame
	_check(not dummy._has_line_of_sight(target, 12.0, 16.0, LAYER_WORLD), "parede entre os dois bloqueia a visão")
	_check(dummy._has_line_of_sight(target, 12.0, 16.0, 0), "sight_mask vazia: nada bloqueia")
	wall.free()

	var air: Enemy = _spawn_dummy(700.0, FLOOR_Y - 200.0)
	await physics_frame
	air.velocity = Vector2.ZERO
	air._apply_gravity(1.0 / 60.0, 360.0)
	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	_check(is_equal_approx(air.velocity.y, gravity / 60.0), "_apply_gravity: soma gravidade × delta no ar")
	air.velocity.y = 355.0
	air._apply_gravity(1.0 / 60.0, 360.0)
	_check(is_equal_approx(air.velocity.y, 360.0), "_apply_gravity: limitada a max_fall_speed")

	_check(dummy._sprite == null and not dummy._has_animation(&"idle"), "sem AnimatedSprite2D: nenhuma animação")
	dummy._play(&"idle", true, 2.0)
	_check(true, "_play sem AnimatedSprite2D não gera erro")


# --- Utilidades -------------------------------------------------------------------

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


func _new_world() -> void:
	_release_all()
	if _world != null:
		_world.free()
	_world = Node2D.new()
	root.add_child(_world)
	await physics_frame


func _box(left: float, top: float, right: float, bottom: float) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector2((left + right) / 2.0, (top + bottom) / 2.0)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(right - left, bottom - top)
	shape.shape = rect
	body.add_child(shape)
	_world.add_child(body)
	return body


func _floor(left: float, right: float) -> StaticBody2D:
	return _box(left, FLOOR_Y, right, FLOOR_Y + 32.0)


func _make_health(max_health: int) -> HealthComponent:
	var health: HealthComponent = HealthComponent.new()
	health.max_health = max_health
	_world.add_child(health)
	return health


## Hitbox 20x16 centrada na origem do pai, mask = layer de teste.
func _make_hitbox(parent: Node) -> Hitbox:
	var hitbox: Hitbox = Hitbox.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = LAYER_TEST_HURTBOX
	hitbox.show_debug = false
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(20.0, 16.0)
	shape.shape = rect
	hitbox.add_child(shape)
	parent.add_child(hitbox)
	return hitbox


func _make_hurtbox(at: Vector2, health: HealthComponent) -> Hurtbox:
	var hurtbox: Hurtbox = Hurtbox.new()
	hurtbox.collision_layer = LAYER_TEST_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.health = health
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(16.0, 16.0)
	shape.shape = rect
	hurtbox.add_child(shape)
	_world.add_child(hurtbox)
	hurtbox.global_position = at
	return hurtbox


func _spawn_terra(x: float, facing: float) -> PlayerCharacter:
	var terra: PlayerCharacter = (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	terra.position = Vector2(x, FLOOR_Y)
	_world.add_child(terra)
	(terra.get_node("Visuals") as Node2D).scale.x = facing
	await _wait(2)
	return terra


func _spawn_dummy(x: float, feet_y: float = FLOOR_Y) -> Enemy:
	var dummy: Enemy = (load(DUMMY_PATH) as PackedScene).instantiate() as Enemy
	dummy.position = Vector2(x, feet_y)
	_world.add_child(dummy)
	return dummy


func _hp(entity: Node) -> int:
	return (entity.get_node("HealthComponent") as HealthComponent).current_health


func _side(facing: float) -> String:
	return "a direita" if facing > 0.0 else "a esquerda"
