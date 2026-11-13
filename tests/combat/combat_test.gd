extends SceneTree
## Teste automatizado do combate básico: HealthComponent, Hurtbox, Hitbox, MeleeAttack,
## ataque da Terra e TrainingDummy. Simula entradas no laboratório de movimento.
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/combat/combat_test.gd

const LAB_PATH: String = "res://tests/movement_lab/movement_lab.tscn"
const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const DUMMY_PATH: String = "res://entities/enemies/training_dummy/training_dummy.tscn"

const PHYSICS_TICKS: float = 60.0
const FLOOR_Y: float = 320.0
## Região livre do laboratório para os testes de combate (longe dos bonecos do lab em x 260 e 880).
const ARENA_X: float = 120.0
## Distância horizontal entre a Terra e um boneco dentro do alcance (hitbox: x +8..+28).
const IN_REACH: float = 20.0
## Distância horizontal fora do alcance (hurtbox do boneco começaria em x +47).
const OUT_OF_REACH: float = 55.0

var _failures: int = 0
var _checks: int = 0
var _lab: Node
var _terra: PlayerCharacter
var _attack: MeleeAttack
var _hitbox: Hitbox
var _visuals: Node2D
var _sprite: AnimatedSprite2D
var _dummy_scene: PackedScene
var _started_count: int = 0
var _finished_count: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Combate básico")
	# Em _initialize a árvore ainda não processou nenhum frame; nós adicionados agora não receberiam _ready.
	await process_frame
	_dummy_scene = load(DUMMY_PATH) as PackedScene
	_check_static_configuration()
	await _test_health_component()

	_lab = (load(LAB_PATH) as PackedScene).instantiate()
	root.add_child(_lab)
	_terra = _lab.get_node("Terra") as PlayerCharacter
	_attack = _terra.get_node("MeleeAttack") as MeleeAttack
	_hitbox = _terra.get_node("Visuals/Hitbox") as Hitbox
	_visuals = _terra.get_node("Visuals") as Node2D
	_sprite = _terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	_attack.attack_started.connect(func() -> void: _started_count += 1)
	_attack.attack_finished.connect(func() -> void: _finished_count += 1)
	await _wait(30)

	await _test_phase_durations()
	await _test_cooldown()
	await _test_one_hit_per_swing()
	await _test_multiple_targets()
	await _test_reach_and_direction()
	await _test_facing_lock()
	await _test_movement_during_attack()
	await _test_air_attack()
	await _test_dummy_death()
	await _test_attack_animation()

	_release_all()
	print("== Resultado: %s (%d verificações, %d falha(s))" % [
		"SUCESSO" if _failures == 0 else "FALHOU", _checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Configuração ---------------------------------------------------------------

func _check_static_configuration() -> void:
	print("-- Configuração")
	var terra: PlayerCharacter = (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	var melee: MeleeAttack = terra.get_node("MeleeAttack") as MeleeAttack
	var hitbox: Hitbox = terra.get_node("Visuals/Hitbox") as Hitbox
	var data: AttackData = melee.attack
	_check(data != null and data.resource_path.ends_with("terra_basic_attack.tres"), "Terra usa terra_basic_attack.tres")
	_check(data.damage == 1 and is_equal_approx(data.windup_time, 0.08) and is_equal_approx(data.active_time, 0.1)
		and is_equal_approx(data.recovery_time, 0.22), "ataque da Terra: dano 1, tempos 0,08 / 0,10 / 0,22 s")
	_check(melee.hitbox == hitbox, "MeleeAttack referencia Visuals/Hitbox")
	_check(hitbox.collision_layer == 0 and hitbox.collision_mask == 32, "Hitbox: layer nenhuma | mask enemy_hurtbox (6)")
	_check(not hitbox.monitoring and not hitbox.monitorable and hitbox.show_debug, "Hitbox começa desativada, show_debug ligado")
	var hit_shape: CollisionShape2D = hitbox.get_node("CollisionShape2D") as CollisionShape2D
	_check((hit_shape.shape as RectangleShape2D).size == Vector2(20, 16) and hit_shape.position == Vector2(18, -28),
		"Hitbox da Terra 20x16 em (18,-28)")
	var hurtbox: Area2D = terra.get_node("Hurtbox") as Area2D
	_check(hurtbox.get_script() == null and hurtbox.collision_layer == 16 and hurtbox.collision_mask == 0
		and not hurtbox.monitoring, "Hurtbox da Terra inalterada (sem script, layer player_hurtbox)")
	_check(terra.collision_layer == 4 and terra.collision_mask == 67, "corpo da Terra inalterado (layer 3, mask 1/2/7)")
	terra.free()

	var dummy: Node = _dummy_scene.instantiate()
	var body: CharacterBody2D = dummy as CharacterBody2D
	_check(body != null and body.collision_layer == 8 and body.collision_mask == 67,
		"TrainingDummy: CharacterBody2D, layer enemies (4) | mask world, platforms, destructibles")
	var dummy_hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
	_check(dummy_hurtbox != null and dummy_hurtbox.collision_layer == 32 and dummy_hurtbox.collision_mask == 0
		and not dummy_hurtbox.monitoring and dummy_hurtbox.monitorable, "TrainingDummy: Hurtbox na layer enemy_hurtbox (6), sem mask")
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	_check(dummy_health != null and dummy_health.max_health == 3 and dummy_hurtbox.health == dummy_health,
		"TrainingDummy: HealthComponent com 3 de vida ligado à Hurtbox")
	_check(dummy.get_node("Visuals") is Polygon2D, "TrainingDummy: visual provisório Polygon2D")
	dummy.free()

	var lab: Node = (load(LAB_PATH) as PackedScene).instantiate()
	var dummies: int = 0
	for child: Node in lab.get_children():
		if child.scene_file_path == DUMMY_PATH:
			dummies += 1
	_check(dummies == 2, "MovementLab tem 2 TrainingDummy (%d)" % dummies)
	lab.free()


func _test_health_component() -> void:
	print("-- HealthComponent")
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 3
	root.add_child(health)
	var damaged_amounts: Array[int] = []
	var deaths: Array[int] = [0]
	health.damaged.connect(func(amount: int) -> void: damaged_amounts.append(amount))
	health.died.connect(func() -> void: deaths[0] += 1)
	_check(health.current_health == 3 and not health.is_dead(), "começa com a vida máxima (3)")
	health.take_damage(1)
	_check(health.current_health == 2 and damaged_amounts == [1], "dano 1: vida 2, damaged(1)")
	health.take_damage(0)
	health.take_damage(-2)
	_check(health.current_health == 2 and damaged_amounts.size() == 1, "dano zero ou negativo é ignorado")
	health.take_damage(5)
	_check(health.current_health == 0 and damaged_amounts == [1, 2], "dano excedente: vida 0 (não negativa), damaged(2)")
	_check(health.is_dead() and deaths[0] == 1, "died emitido ao chegar a zero")
	health.take_damage(1)
	_check(health.current_health == 0 and deaths[0] == 1 and damaged_amounts.size() == 2, "depois de morto: sem dano e sem novo died")

	var hurtbox: Hurtbox = Hurtbox.new()
	var hurt_health: HealthComponent = HealthComponent.new()
	hurtbox.health = hurt_health
	root.add_child(hurt_health)
	root.add_child(hurtbox)
	var received: Array[int] = []
	hurtbox.hit_received.connect(func(damage: int) -> void: received.append(damage))
	hurtbox.receive_hit(2)
	_check(received == [2] and hurt_health.current_health == 1, "Hurtbox emite hit_received e repassa o dano")
	for node: Node in [health, hurtbox, hurt_health]:
		node.queue_free()
	await process_frame


# --- Simulação ------------------------------------------------------------------

func _test_phase_durations() -> void:
	print("-- Fases do golpe")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	_started_count = 0
	_finished_count = 0
	await _press("attack")
	var windup: int = 0
	var active: int = 0
	var recovery: int = 0
	var order_ok: bool = true
	var stage: int = 0  # 0 preparação, 1 ativa, 2 recuperação
	var ticks: int = 0
	# Cada iteração lê o estado ao fim de um tick, a partir do tick em que o golpe começou.
	while _attack.is_busy() and ticks < 120:
		var current: int = 2 if not _attack.is_striking() else (1 if _hitbox.is_active() else 0)
		order_ok = order_ok and current >= stage
		stage = current
		match current:
			0: windup += 1
			1: active += 1
			2: recovery += 1
		await physics_frame
		ticks += 1
	var expected_windup: int = ceili(0.08 * PHYSICS_TICKS)
	var expected_total: int = ceili(0.40 * PHYSICS_TICKS - 0.001)
	var expected_striking: int = ceili(0.18 * PHYSICS_TICKS - 0.001)
	_check(order_ok, "fases em ordem: preparação → ativa → recuperação")
	_check(windup == expected_windup, "preparação: %d ticks (esperado %d)" % [windup, expected_windup])
	_check(active == expected_striking - expected_windup, "fase ativa: %d ticks (esperado %d)" % [active, expected_striking - expected_windup])
	_check(recovery == expected_total - expected_striking, "recuperação: %d ticks (esperado %d)" % [recovery, expected_total - expected_striking])
	_check(_started_count == 1 and _finished_count == 1, "attack_started e attack_finished emitidos uma vez")
	_check(not _hitbox.is_active(), "Hitbox desligada ao final")
	await _wait(2)
	_check(not _hitbox.monitoring, "monitoring da Hitbox desligado ao final")


func _test_cooldown() -> void:
	print("-- Tempo de recuperação")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	_started_count = 0
	# Aperta e solta alternadamente por 60 ticks (30 apertos).
	for i: int in 60:
		if i % 2 == 0:
			Input.action_press("attack")
		else:
			Input.action_release("attack")
		await physics_frame
	Input.action_release("attack")
	_check(_started_count == 3, "30 apertos em 1 s: %d golpes (esperado 3, ciclo de 24 ticks)" % _started_count)
	await _wait_until_ready()
	await _press("attack")
	_check(_attack.is_busy(), "novo golpe começa assim que a recuperação termina")
	await _wait_until_ready()


func _test_one_hit_per_swing() -> void:
	print("-- Um dano por alvo por golpe")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	var dummy: Node2D = _spawn_dummy(ARENA_X + IN_REACH)
	var health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var hit_ticks: Array[String] = []
	var hit_phase_ok: Array[bool] = [true]
	health.damaged.connect(func(_amount: int) -> void:
		hit_phase_ok[0] = hit_phase_ok[0] and _hitbox.is_active())
	var landed: Array[int] = [0]
	_hitbox.hit_landed.connect(func(_hurtbox: Hurtbox) -> void: landed[0] += 1)
	await _attack_and_wait()
	_check(health.current_health == 2, "alvo parado na hitbox por toda a fase ativa perde só 1 (vida %d)" % health.current_health)
	_check(hit_phase_ok[0], "o dano acontece durante a fase ativa")
	_check(landed[0] == 1, "hit_landed emitido uma vez (%d)" % landed[0])
	await _attack_and_wait()
	_check(health.current_health == 1, "golpe seguinte acerta de novo (vida %d)" % health.current_health)
	dummy.queue_free()
	await _wait(1)


func _test_multiple_targets() -> void:
	print("-- Vários alvos")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	var near: Node2D = _spawn_dummy(ARENA_X + IN_REACH - 4.0)
	var far: Node2D = _spawn_dummy(ARENA_X + IN_REACH + 4.0)
	await _attack_and_wait()
	var near_hp: int = (near.get_node("HealthComponent") as HealthComponent).current_health
	var far_hp: int = (far.get_node("HealthComponent") as HealthComponent).current_health
	_check(near_hp == 2 and far_hp == 2, "um golpe acerta os dois bonecos, 1 de dano cada (vidas %d e %d)" % [near_hp, far_hp])
	near.queue_free()
	far.queue_free()
	await _wait(1)


func _test_reach_and_direction() -> void:
	print("-- Alcance e direção")
	for facing: float in [1.0, -1.0]:
		var side: String = "direita" if facing > 0.0 else "esquerda"
		await _reset(Vector2(ARENA_X, FLOOR_Y), facing)
		var front: Node2D = _spawn_dummy(ARENA_X + IN_REACH * facing)
		var back: Node2D = _spawn_dummy(ARENA_X - IN_REACH * facing)
		var out: Node2D = _spawn_dummy(ARENA_X + OUT_OF_REACH * facing)
		await _attack_and_wait()
		_check(_hp(front) == 2, "olhando para a %s: acerta o boneco à frente" % side)
		_check(_hp(back) == 3, "olhando para a %s: não acerta o boneco atrás" % side)
		_check(_hp(out) == 3, "olhando para a %s: não acerta fora do alcance" % side)
		for dummy: Node2D in [front, back, out]:
			dummy.queue_free()
		await _wait(1)


func _test_facing_lock() -> void:
	print("-- Direção travada durante o golpe")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	var front: Node2D = _spawn_dummy(ARENA_X + IN_REACH)
	var back: Node2D = _spawn_dummy(ARENA_X - IN_REACH)
	await _press("attack")
	Input.action_press("move_left")
	var locked: bool = true
	while _attack.is_striking():
		locked = locked and _visuals.scale.x == 1.0
		await physics_frame
	_check(locked, "virar durante preparação e fase ativa não muda o lado")
	await _wait(1)
	_check(_visuals.scale.x == -1.0 and _attack.is_busy(), "na recuperação a direção é liberada")
	Input.action_release("move_left")
	_check(_hp(front) == 2 and _hp(back) == 3, "o golpe acertou só o lado original (frente %d, atrás %d)" % [_hp(front), _hp(back)])
	_check(_terra.global_position.x < ARENA_X - 1.0, "continuou se movendo para a esquerda durante o golpe (x=%.1f)" % _terra.global_position.x)
	await _wait_until_ready()
	front.queue_free()
	back.queue_free()
	await _wait(1)


func _test_movement_during_attack() -> void:
	print("-- Movimento durante o ataque")
	var without_attack: Array[Vector2] = await _record_run(-1)
	_started_count = 0
	var with_attack: Array[Vector2] = await _record_run(5)
	_check(_started_count == 2, "percurso com ataque: 2 golpes executados (no chão e no ar) (%d)" % _started_count)
	var identical: bool = without_attack.size() == with_attack.size()
	for i: int in mini(without_attack.size(), with_attack.size()):
		identical = identical and without_attack[i].is_equal_approx(with_attack[i])
	_check(identical, "andar + pular com e sem ataque: posições idênticas em %d ticks" % without_attack.size())


func _test_air_attack() -> void:
	print("-- Ataque no ar")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	Input.action_press("jump")
	await _wait(12)
	_check(not _terra.is_on_floor(), "Terra no ar")
	# Boneco "flutuando" à frente, na altura da hitbox (o TrainingDummy não tem gravidade).
	var dummy: Node2D = _spawn_dummy(_terra.global_position.x + IN_REACH, _terra.global_position.y - 4.0)
	var hit_in_air: Array[bool] = [false]
	(dummy.get_node("HealthComponent") as HealthComponent).damaged.connect(func(_amount: int) -> void:
		hit_in_air[0] = not _terra.is_on_floor())
	await _press("attack")
	_check(_attack.is_busy(), "golpe inicia no ar")
	await _wait_until_ready()
	Input.action_release("jump")
	_check(_hp(dummy) == 2 and hit_in_air[0], "golpe no ar acerta (vida %d)" % _hp(dummy))
	dummy.queue_free()
	await _wait_until_landed()


func _test_dummy_death() -> void:
	print("-- Morte do TrainingDummy")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	var dummy: Node2D = _spawn_dummy(ARENA_X + IN_REACH)
	var visual: Polygon2D = dummy.get_node("Visuals") as Polygon2D
	var health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
	var deaths: Array[int] = [0]
	health.died.connect(func() -> void: deaths[0] += 1)
	var flashed: bool = false
	await _press("attack")
	while _attack.is_busy():
		flashed = flashed or visual.modulate != Color.WHITE
		await physics_frame
	_check(flashed, "pisca ao receber dano")
	await _wait(12)
	_check(visual.modulate == Color.WHITE, "volta à cor normal depois de ~0,1 s")
	await _attack_and_wait()
	_check(is_instance_valid(dummy) and health.current_health == 1, "ainda presente com 1 de vida")
	await _press("attack")
	# Logo após a morte (antes do queue_free, que espera o piscar), a Hurtbox já foi desligada.
	var hurtbox_off_after_death: bool = false
	for i: int in 30:
		await physics_frame
		if deaths[0] == 1 and is_instance_valid(dummy):
			await physics_frame
			hurtbox_off_after_death = is_instance_valid(dummy) and not hurtbox.monitorable
			break
	_check(hurtbox_off_after_death, "ao morrer, a Hurtbox deixa de receber golpes (antes de sumir)")
	await _wait(20)
	_check(deaths[0] == 1, "died emitido uma vez no terceiro golpe")
	_check(not is_instance_valid(dummy), "boneco removido após morrer")
	await _wait_until_ready()
	await _attack_and_wait()
	_check(true, "golpear depois da remoção não gera erro")


func _test_attack_animation() -> void:
	print("-- Animação attack")
	# Sem attack no SpriteFrames da Terra: mantém a animação normal.
	_check(not _sprite.sprite_frames.has_animation(PlayerCharacter.ANIM_ATTACK), "terra_sprite_frames não tem attack (ainda)")
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	await _press("attack")
	var kept_idle: bool = true
	while _attack.is_busy():
		kept_idle = kept_idle and _sprite.animation == PlayerCharacter.ANIM_IDLE and _sprite.is_playing()
		await physics_frame
	_check(kept_idle, "parada: idle durante todo o golpe")
	Input.action_press("move_right")
	await _wait(5)
	await _press("attack")
	var kept_walk: bool = true
	while _attack.is_busy():
		kept_walk = kept_walk and _sprite.animation == PlayerCharacter.ANIM_WALK
		await physics_frame
	Input.action_release("move_right")
	_check(kept_walk, "andando: walk durante todo o golpe")

	# Cópia em memória com uma animação attack de teste (reaproveita quadros do idle).
	var original: SpriteFrames = _sprite.sprite_frames
	var with_attack: SpriteFrames = original.duplicate() as SpriteFrames
	with_attack.add_animation(PlayerCharacter.ANIM_ATTACK)
	with_attack.set_animation_loop(PlayerCharacter.ANIM_ATTACK, false)
	with_attack.set_animation_speed(PlayerCharacter.ANIM_ATTACK, 30.0)
	for i: int in 3:
		with_attack.add_frame(PlayerCharacter.ANIM_ATTACK, original.get_frame_texture(PlayerCharacter.ANIM_IDLE, i))
	_sprite.sprite_frames = with_attack
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	for swing: int in 2:
		await _press("attack")
		var starts_at_zero: bool = _sprite.animation == PlayerCharacter.ANIM_ATTACK and _sprite.frame == 0
		var attack_while_striking: bool = true
		while _attack.is_striking():
			attack_while_striking = attack_while_striking and _sprite.animation == PlayerCharacter.ANIM_ATTACK
			await physics_frame
		var normal_in_recovery: bool = true
		while _attack.is_busy():
			normal_in_recovery = normal_in_recovery and _sprite.animation == PlayerCharacter.ANIM_IDLE
			await physics_frame
		_check(starts_at_zero and attack_while_striking, "golpe %d: attack desde o quadro 0 na preparação e fase ativa" % (swing + 1))
		_check(normal_in_recovery, "golpe %d: volta para idle na recuperação" % (swing + 1))
	_sprite.sprite_frames = original
	await _wait(2)
	_check(_sprite.animation == PlayerCharacter.ANIM_IDLE and not original.has_animation(PlayerCharacter.ANIM_ATTACK),
		"SpriteFrames original restaurado e inalterado")


# --- Auxiliares -----------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  [OK]   " if condition else "  [FAIL] ") + message)
	if not condition:
		_failures += 1


func _wait(ticks: int) -> void:
	for i: int in ticks:
		await physics_frame


## Aperta e solta a ação. A entrada simulada só é vista no tick seguinte ao press,
## então espera esse tick rodar: ao retornar, o efeito (ex.: início do golpe) já ocorreu.
func _press(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _attack_and_wait() -> void:
	await _press("attack")
	await _wait_until_ready()


func _wait_until_ready(max_ticks: int = 120) -> void:
	for i: int in max_ticks:
		if not _attack.is_busy():
			return
		await physics_frame


func _wait_until_landed(max_ticks: int = 180) -> void:
	for i: int in max_ticks:
		if _terra.is_on_floor():
			return
		await physics_frame


func _release_all() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack"]:
		Input.action_release(action)


## Reposiciona a Terra parada no chão, olhando para o lado indicado.
func _reset(position: Vector2, facing: float) -> void:
	_release_all()
	await _wait_until_ready()
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


func _spawn_dummy(x: float, feet_y: float = FLOOR_Y) -> Node2D:
	var dummy: Node2D = _dummy_scene.instantiate() as Node2D
	dummy.position = Vector2(x, feet_y)
	_lab.add_child(dummy)
	return dummy


func _hp(dummy: Node) -> int:
	return (dummy.get_node("HealthComponent") as HealthComponent).current_health


## Percurso fixo (andar para a direita e pular); ataca no tick indicado (-1 = sem ataque).
func _record_run(attack_tick: int) -> Array[Vector2]:
	await _reset(Vector2(ARENA_X, FLOOR_Y), 1.0)
	var positions: Array[Vector2] = []
	Input.action_press("move_right")
	for i: int in 60:
		if i == 10:
			Input.action_press("jump")
		elif i == 25:
			Input.action_release("jump")
		if i == attack_tick or i == attack_tick + 30:
			Input.action_press("attack")
		elif i == attack_tick + 1 or i == attack_tick + 31:
			Input.action_release("attack")
		await physics_frame
		positions.append(_terra.global_position)
	_release_all()
	await _wait_until_landed()
	return positions
