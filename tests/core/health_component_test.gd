extends SceneTree
## Teste automatizado do HealthComponent: vida inicial, dano (nunca negativo, sem duplicação),
## morte uma única vez por vida, cura limitada ao máximo, restauração (renascimento) e sinais
## (damaged, died, health_changed). Também confere a vida da Terra (5) e a Hurtbox
## (invulnerabilidade de 0,6 s e start_invulnerability).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/core/health_component_test.gd

const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"

var _failures: int = 0
var _checks: int = 0
var _damaged: Array[int] = []
var _died: int = 0
var _changes: Array[Vector2i] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== HealthComponent")
	await process_frame
	var hc := HealthComponent.new()
	hc.max_health = 5
	root.add_child(hc)
	hc.damaged.connect(func(a: int) -> void: _damaged.append(a))
	hc.died.connect(func() -> void: _died += 1)
	hc.health_changed.connect(func(c: int, m: int) -> void: _changes.append(Vector2i(c, m)))

	_check(hc.current_health == 5 and hc.max_health == 5 and not hc.is_dead(), "começa com a vida máxima (5/5)")

	hc.take_damage(2)
	_check(hc.current_health == 3 and _damaged == [2] and _changes == [Vector2i(3, 5)], "dano 2: vida 3, damaged(2) e health_changed(3, 5)")
	hc.take_damage(0)
	hc.take_damage(-3)
	_check(hc.current_health == 3 and _damaged.size() == 1 and _changes.size() == 1, "dano zero ou negativo é ignorado (sem sinais)")

	_check(hc.heal(1) == 1 and hc.current_health == 4 and _changes.back() == Vector2i(4, 5), "cura 1: vida 4 e health_changed(4, 5)")
	_check(hc.heal(10) == 1 and hc.current_health == 5, "cura não passa do máximo (recupera só 1)")
	var n := _changes.size()
	_check(hc.heal(3) == 0 and hc.current_health == 5 and _changes.size() == n, "cura com vida cheia: nada muda, sem sinal")
	_check(hc.heal(0) == 0 and hc.heal(-2) == 0 and hc.current_health == 5, "cura zero ou negativa é ignorada")

	hc.take_damage(99)
	_check(hc.current_health == 0 and hc.is_dead() and _damaged.back() == 5, "dano maior que a vida: vida 0 (nunca negativa), damaged com a vida perdida (5)")
	_check(_died == 1 and _changes.back() == Vector2i(0, 5), "died uma vez e health_changed(0, 5)")
	n = _damaged.size()
	hc.take_damage(1)
	_check(hc.current_health == 0 and _damaged.size() == n and _died == 1, "dano depois da morte é ignorado (sem damaged nem died repetido)")
	_check(hc.heal(2) == 0 and hc.is_dead(), "cura não revive (para isso, restore_full)")

	hc.restore_full()
	_check(hc.current_health == 5 and not hc.is_dead() and _changes.back() == Vector2i(5, 5), "restore_full: vida cheia e health_changed(5, 5)")
	hc.take_damage(5)
	_check(_died == 2 and hc.is_dead(), "depois de restore_full, morrer de novo emite died outra vez (uma vez por vida)")
	hc.queue_free()

	# Terra: 5 de vida; Hurtbox com 0,6 s de invulnerabilidade, sem duplicar dano.
	var terra := (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	root.add_child(terra)
	await process_frame
	var th := terra.get_health()
	var hb := terra.get_hurtbox()
	_check(th.current_health == 5 and th.max_health == 5, "Terra começa com 5 de vida")
	hb.receive_hit(1)
	hb.receive_hit(1)
	_check(th.current_health == 4, "dois golpes no mesmo tick: só o primeiro conta (invulnerabilidade)")
	_check(absf(hb.get_invulnerability_left() - 0.6) < 0.001, "invulnerabilidade de 0,6 s após o golpe")
	await _physics(37)
	hb.receive_hit(1)
	_check(th.current_health == 3, "depois de 0,6 s, o golpe seguinte conta")
	await _physics(37)
	hb.start_invulnerability(1.0)
	_check(hb.is_invulnerable() and absf(hb.get_invulnerability_left() - 1.0) < 0.001, "start_invulnerability(1.0) sem golpe")
	hb.start_invulnerability(0.2)
	_check(absf(hb.get_invulnerability_left() - 1.0) < 0.001, "start_invulnerability não encurta uma invulnerabilidade maior")
	hb.receive_hit(1)
	_check(th.current_health == 3, "golpe ignorado durante start_invulnerability")
	terra.queue_free()
	_finish()


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
