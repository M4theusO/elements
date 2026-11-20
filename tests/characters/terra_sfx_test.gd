extends SceneTree
## Teste automatizado dos efeitos sonoros da Terra (CharacterSfx + sinais do PlayerCharacter,
## CharacterAbility e componentes de combate). Valida pedidos de reprodução (sinal
## sound_requested) e o estado dos players, não a audição:
##  - arquivos: 9 WAV mono, PCM 16 bits, 44,1 kHz, pico <= -1 dBFS, audíveis, sem silêncio no
##    início, importados como AudioStreamWAV;
##  - barramento SFX (com limitador) e configuração do nó Sfx na terra.tscn;
##  - passos só andando no chão (cadência pela distância, variações sem repetição, pitch e
##    volume dentro da variação; nada parado, no ar, empurrando parede ou morta);
##  - pulo efetivo (inclusive coyote time e jump buffer), nada ao apertar no ar;
##  - pouso só após queda real, com volume pela velocidade; nada no início da cena nem após
##    reposicionamento;
##  - golpe e Punho Sísmico só quando começam/liberam de fato (rejeitados, em recarga ou
##    cancelados não tocam);
##  - dano real (invulnerabilidade e bloqueio não tocam), golpe fatal só com a morte, uma vez;
##  - fluxo real da Game (transição, morte, Game Over pausado, retry) e da sala avulsa com o
##    SceneDeathController (cena recarregada no meio do som de morte).
##
## Execução (na raiz do projeto), sai com código 0 se tudo passar e 1 se algo falhar:
##   godot --headless --path . -s res://tests/characters/terra_sfx_test.gd

const TERRA_PATH: String = "res://entities/characters/terra/terra.tscn"
const GAME_PATH: String = "res://main/game.tscn"
const TEST_ROOM_PATH: String = "res://world/levels/depths/depths_test_room.tscn"
const AUDIO_DIR: String = "res://entities/characters/terra/audio/"
const SOUND_FILES: Array[String] = ["footstep_01", "footstep_02", "footstep_03", "jump", "land",
		"attack", "seismic_fist", "hurt", "death"]
const FLOOR_Y: float = 200.0
## Bloco elevado (borda para coyote time e queda): x 1000–1200, topo 32 px acima do chão.
const LEDGE_LEFT: float = 1000.0
const LEDGE_RIGHT: float = 1200.0
const LEDGE_TOP: float = FLOOR_Y - 32.0
## Parede: face esquerda em x 1500.
const WALL_X: float = 1500.0

var _failures: int = 0
var _checks: int = 0
## Eventos pedidos pelo CharacterSfx observado, na ordem.
var _events: Array[StringName] = []
## Corpos do cenário de teste (chão, bloco elevado, parede).
var _level: Array[Node] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("== Efeitos sonoros da Terra")
	await process_frame
	_test_files()
	_test_bus()
	_make_level()
	await _test_scene_setup()
	await _test_footsteps_contact()
	await _test_footsteps_distance()
	await _test_jump_and_land()
	await _test_attack_and_ability()
	await _test_damage_and_death()
	_clear_level()
	await _test_game_flow()
	await _test_scene_restart_flow()
	_finish()


# --- Arquivos e barramento -----------------------------------------------------------------

func _test_files() -> void:
	print("-- Arquivos WAV")
	for name: String in SOUND_FILES:
		var path := AUDIO_DIR + name + ".wav"
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_check(false, "%s existe" % path)
			continue
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var header_ok := bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
				and bytes.slice(8, 12).get_string_from_ascii() == "WAVE"
		var fmt := bytes.decode_u16(20)
		var channels := bytes.decode_u16(22)
		var rate := bytes.decode_u32(24)
		var bits := bytes.decode_u16(34)
		var data_size := bytes.decode_u32(40)
		_check(header_ok and fmt == 1 and channels == 1 and rate == 44100 and bits == 16 and bytes.slice(36, 40).get_string_from_ascii() == "data",
				"%s: WAV PCM mono 16 bits 44,1 kHz" % name)
		var samples := data_size / 2
		var peak := 0
		var first_loud := -1
		for i in samples:
			var v: int = absi(bytes.decode_s16(44 + i * 2))
			peak = maxi(peak, v)
		var threshold := int(peak * 0.01)  # -40 dB do pico
		for i in samples:
			if absi(bytes.decode_s16(44 + i * 2)) >= threshold:
				first_loud = i
				break
		var peak_db := linear_to_db(peak / 32767.0)
		var duration := samples / 44100.0
		var lead_ms := first_loud * 1000.0 / 44100.0
		_check(peak_db <= -1.0 + 0.01 and peak_db >= -14.0, "%s: pico %.2f dBFS (<= -1, audível)" % [name, peak_db])
		_check(lead_ms < 5.0, "%s: sem silêncio no início (%.2f ms)" % [name, lead_ms])
		var max_len := 1.05 if name == "death" else 0.8
		_check(duration >= 0.08 and duration <= max_len, "%s: duração %.0f ms" % [name, duration * 1000.0])
		var stream := load(path) as AudioStreamWAV
		_check(stream != null and not stream.stereo and stream.mix_rate == 44100 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
				"%s: importado como AudioStreamWAV mono, sem loop" % name)


func _test_bus() -> void:
	print("-- Barramento SFX")
	var idx := AudioServer.get_bus_index(&"SFX")
	_check(AudioServer.get_bus_name(0) == "Master" and idx > 0, "Master preservado e SFX existe (índice %d)" % idx)
	if idx < 0:
		return
	_check(AudioServer.get_bus_send(idx) == &"Master", "SFX envia para o Master")
	var limiter: AudioEffectHardLimiter = null
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(idx, e):
			limiter = AudioServer.get_bus_effect(idx, e)
	_check(limiter != null and limiter.ceiling_db <= -1.0, "SFX com limitador ativo (teto <= -1 dB) contra saturação na soma")


# --- Personagem isolada --------------------------------------------------------------------

func _test_scene_setup() -> void:
	print("-- Nó Sfx na Terra")
	# Nasce 40 px acima do chão: a primeira queda não é pouso (início da cena).
	var terra := await _spawn_terra(Vector2(100, FLOOR_Y - 40))
	var sfx := _sfx(terra)
	_check(sfx != null, "Terra tem o nó Sfx (CharacterSfx)")
	if sfx == null:
		return
	_check(sfx.footsteps.size() == 3 and sfx.jump_sound != null and sfx.land_sound != null and sfx.attack_sound != null \
			and sfx.ability_sound != null and sfx.hurt_sound != null and sfx.death_sound != null, "9 sons atribuídos (3 passos + 6)")
	var all_ok := true
	for event: StringName in [CharacterSfx.EVENT_FOOTSTEP, CharacterSfx.EVENT_JUMP, CharacterSfx.EVENT_LAND, CharacterSfx.EVENT_ATTACK,
			CharacterSfx.EVENT_ABILITY, CharacterSfx.EVENT_HURT, CharacterSfx.EVENT_DEATH]:
		var p := sfx.get_player(event)
		if p == null or p.bus != &"SFX" or p.process_mode != Node.PROCESS_MODE_ALWAYS:
			all_ok = false
	_check(all_ok, "um AudioStreamPlayer2D por evento, no SFX, com PROCESS_MODE_ALWAYS")
	_check(sfx.get_player(CharacterSfx.EVENT_FOOTSTEP).max_polyphony == 2, "passos com polifonia 2")
	_check(terra.is_on_floor() and _events.is_empty(), "nenhum som ao nascer e cair no chão (início da cena)")
	await _physics(30)
	_check(_events.is_empty(), "parada: nenhum som")
	_free(terra)


## Por quadro de contato (configuração da Terra): o passo cai no quadro 1 da walk, e a cadência
## acompanha o FPS da walk e o speed_scale proporcional à velocidade.
func _test_footsteps_contact() -> void:
	print("-- Passos por quadro de contato (Terra)")
	var terra := await _spawn_terra(Vector2(100, FLOOR_Y))
	var sfx := _sfx(terra)
	var sprite := terra.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	_check(sfx.uses_contact_frames() and sfx.footstep_sprite == sprite and sfx.footstep_animation == &"walk" \
			and sfx.footstep_contact_frames == PackedInt32Array([1]), "Terra: passos no quadro 1 da walk")
	var walk_fps := sprite.sprite_frames.get_animation_speed(&"walk")
	var loop_ms := 1000.0 * sprite.sprite_frames.get_frame_count(&"walk") / walk_fps
	var times: Array[float] = []
	var in_phase := [true]
	var on_step := func(e: StringName) -> void:
		if e == CharacterSfx.EVENT_FOOTSTEP:
			times.append(Time.get_ticks_usec() / 1000.0)
			if sprite.animation != &"walk" or sprite.frame != 1:
				in_phase[0] = false
	sfx.sound_requested.connect(on_step)
	Input.action_press(&"move_right")
	await _physics(150)  # 2,5 s
	Input.action_release(&"move_right")
	await _physics(20)
	_check(in_phase[0] and times.size() >= 3, "todo passo cai no quadro de contato (quadro 1 da walk): %d passos" % times.size())
	var mean := _mean_interval(times, 2)
	_check(absf(mean - loop_ms) < loop_ms * 0.12, "velocidade cheia: um passo por loop da walk (%.0f ms; loop = %.0f ms a %.1f FPS)" % [mean, loop_ms, walk_fps])
	var n := times.size()
	await _physics(30)
	_check(times.size() == n, "parada: nenhum passo")

	print("-- Passos por quadro de contato em meia velocidade (analógico 0,5)")
	times.clear()
	Input.action_press(&"move_right", 0.5)
	await _physics(180)  # 3 s
	Input.action_release(&"move_right")
	await _physics(20)
	mean = _mean_interval(times, 1)
	_check(in_phase[0] and times.size() >= 3, "meia velocidade: passos ainda no quadro de contato (%d)" % times.size())
	_check(absf(mean - loop_ms * 2.0) < loop_ms * 0.25, "meia velocidade: pernas e passos na metade do ritmo (%.0f ms; esperado ~%.0f)" % [mean, loop_ms * 2.0])

	print("-- Pouso andando")
	times.clear()
	_events.clear()
	Input.action_press(&"move_right")
	await _physics(30)
	Input.action_press(&"jump")
	var land_ms := -1.0
	for i in 120:
		await physics_frame
		if land_ms < 0.0 and _count(CharacterSfx.EVENT_LAND) > 0:
			land_ms = Time.get_ticks_usec() / 1000.0
			Input.action_release(&"jump")
			break
	await _physics(45)
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	var after: Array[float] = []
	for t in times:
		if land_ms >= 0.0 and t >= land_ms:
			after.append(t - land_ms)
	_check(land_ms >= 0.0 and not after.is_empty() and after[0] >= sfx.footstep_land_grace * 1000.0 - 20.0,
			"pousando andando: o pouso é o contato; o primeiro passo depois vem a %.0f ms (carência %.0f ms)" % [
			after[0] if not after.is_empty() else -1.0, sfx.footstep_land_grace * 1000.0])
	await _physics(20)

	print("-- Passos por quadro de contato: parede")
	_teleport(terra, Vector2(WALL_X - 40, FLOOR_Y))
	await _physics(5)
	Input.action_press(&"move_right")
	await _physics(40)
	times.clear()
	await _physics(60)
	Input.action_release(&"move_right")
	_check(times.is_empty() and sprite.animation == &"idle", "empurrando a parede: idle e nenhum passo")
	sfx.sound_requested.disconnect(on_step)
	_free(terra)


func _test_footsteps_distance() -> void:
	print("-- Passos, modo por distância (sem quadros de contato)")
	var terra := await _spawn_terra(Vector2(100, FLOOR_Y), true)
	var sfx := _sfx(terra)
	var steps_idx: Array[int] = []
	var pitch_ok := [true]
	sfx.sound_requested.connect(func(e: StringName) -> void:
		if e == CharacterSfx.EVENT_FOOTSTEP:
			steps_idx.append(sfx.get_last_footstep_index())
			var p := sfx.get_player(e)
			if absf(p.pitch_scale - 1.0) > sfx.footstep_pitch_variation + 0.0001 \
					or absf(p.volume_db - sfx.footstep_volume_db) > sfx.footstep_volume_variation_db + 0.0001:
				pitch_ok[0] = false)
	var x0 := terra.global_position.x
	Input.action_press(&"move_right")
	await _physics(90)
	Input.action_release(&"move_right")
	var dist := terra.global_position.x - x0
	await _physics(30)  # desacelera e para
	dist = terra.global_position.x - x0
	var expected := _expected_steps(dist, sfx)
	_check(steps_idx.size() >= expected - 1 and steps_idx.size() <= expected,
			"velocidade cheia: %d passos em %.0f px (esperado ~%d: 1º a %.0f px, depois a cada %.0f px)" % [
			steps_idx.size(), dist, expected, sfx.footstep_first_distance, sfx.footstep_distance])
	var no_repeat := true
	for i in range(1, steps_idx.size()):
		if steps_idx[i] == steps_idx[i - 1]:
			no_repeat = false
	var used := {}
	for i in steps_idx:
		used[i] = true
	_check(no_repeat and steps_idx.size() >= 3, "variação nunca se repete em seguida (%s)" % str(steps_idx))
	_check(used.size() >= 2, "usa variações diferentes (%d de 3)" % used.size())
	_check(pitch_ok[0], "pitch e volume dentro da variação (±%.0f%%, ±%.1f dB)" % [sfx.footstep_pitch_variation * 100.0, sfx.footstep_volume_variation_db])
	var n := steps_idx.size()
	await _physics(30)
	_check(steps_idx.size() == n and absf(terra.get_real_velocity().x) < 0.5, "parada depois de soltar: nenhum passo")

	print("-- Passos por distância em meia velocidade (analógico 0,5)")
	_events.clear()
	x0 = terra.global_position.x
	Input.action_press(&"move_right", 0.5)
	await _physics(120)
	Input.action_release(&"move_right")
	await _physics(20)
	dist = terra.global_position.x - x0
	expected = _expected_steps(dist, sfx)
	var half := _count(CharacterSfx.EVENT_FOOTSTEP)
	_check(half >= expected - 1 and half <= expected and half >= 2,
			"meia velocidade: %d passos em %.0f px em 2 s (mesma distância por passo, mais espaçados no tempo)" % [half, dist])

	print("-- Passos por distância: parede")
	_teleport(terra, Vector2(WALL_X - 40, FLOOR_Y))
	await _physics(5)
	Input.action_press(&"move_right")
	await _physics(40)  # chega à parede
	_events.clear()
	await _physics(40)  # empurrando a parede
	Input.action_release(&"move_right")
	_check(_count(CharacterSfx.EVENT_FOOTSTEP) == 0 and absf(terra.global_position.x - (WALL_X - 8)) < 1.0,
			"empurrando a parede: nenhum passo (x %.1f)" % terra.global_position.x)
	_free(terra)


func _test_jump_and_land() -> void:
	print("-- Pulo e pouso")
	var terra := await _spawn_terra(Vector2(200, FLOOR_Y))
	var sfx := _sfx(terra)
	_events.clear()
	# Botão segurado: pulo completo (soltar cedo corta o pulo variável).
	Input.action_press(&"jump")
	await _physics(2)
	_check(_count(CharacterSfx.EVENT_JUMP) == 1, "pulo no chão: 1 som de pulo")
	var steps_in_air := 0
	Input.action_press(&"move_right")
	var landed_volume := 0.0
	var prev_steps := _count(CharacterSfx.EVENT_FOOTSTEP)
	for i in 90:
		await physics_frame
		var steps := _count(CharacterSfx.EVENT_FOOTSTEP)
		if not terra.is_on_floor() and steps > prev_steps:
			steps_in_air += 1
		prev_steps = steps
		if _count(CharacterSfx.EVENT_LAND) > 0:
			landed_volume = sfx.get_player(CharacterSfx.EVENT_LAND).volume_db
			break
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	_check(steps_in_air == 0, "andando no ar: nenhum passo")
	_check(_count(CharacterSfx.EVENT_LAND) == 1 and _count(CharacterSfx.EVENT_JUMP) == 1, "pouso depois do pulo: 1 som de pouso (e nenhum pulo extra)")
	_check(landed_volume > -3.0 and landed_volume <= sfx.land_volume_db + 0.001, "pouso de pulo completo quase no volume cheio (%.2f dB)" % landed_volume)
	var land_idx := _events.find(CharacterSfx.EVENT_LAND)
	_check(land_idx >= 0 and not _events.slice(land_idx).has(CharacterSfx.EVENT_FOOTSTEP), "nenhum passo no tick do pouso")
	await _physics(30)

	print("-- Apertar no ar (sem coyote) não pula")
	_events.clear()
	Input.action_press(&"jump")
	await _physics(20)  # ~ápice (0,38 s): longe do chão (queda de ~0,3 s > buffer de 0,1 s)
	Input.action_release(&"jump")
	await physics_frame
	var before := _count(CharacterSfx.EVENT_JUMP)
	await _tap(&"jump")
	await _physics(4)
	_check(before == 1 and _count(CharacterSfx.EVENT_JUMP) == 1 and not terra.is_on_floor(), "segundo aperto no ar: nenhum som de pulo")
	await _wait_floor(terra)
	await _physics(10)
	_check(_count(CharacterSfx.EVENT_JUMP) == 1 and _count(CharacterSfx.EVENT_LAND) == 1, "ao pousar, o aperto antigo não vira pulo (fora do buffer)")

	print("-- Jump buffer")
	_events.clear()
	await _tap(&"jump")
	# Desce até ficar a poucos pixels do chão e aperta (dentro do buffer de 0,1 s).
	for i in 120:
		await physics_frame
		if terra.velocity.y > 0.0 and terra.global_position.y > FLOOR_Y - 14.0:
			break
	await _tap(&"jump")
	await _physics(6)
	_check(_count(CharacterSfx.EVENT_JUMP) == 2 and _count(CharacterSfx.EVENT_LAND) == 1 and not terra.is_on_floor(),
			"aperto pouco antes do chão: pousa e pula de novo (pulos %d, pousos %d)" % [_count(CharacterSfx.EVENT_JUMP), _count(CharacterSfx.EVENT_LAND)])
	await _wait_floor(terra)
	await _physics(10)

	print("-- Coyote time")
	_teleport(terra, Vector2(LEDGE_RIGHT - 24, LEDGE_TOP))
	await _physics(10)
	_check(terra.is_on_floor() and terra.global_position.y <= LEDGE_TOP + 1.0, "Terra sobre o bloco elevado")
	_events.clear()
	Input.action_press(&"move_right")
	for i in 60:
		await physics_frame
		if not terra.is_on_floor():
			break
	Input.action_release(&"move_right")
	_check(not terra.is_on_floor() and _count(CharacterSfx.EVENT_JUMP) == 0, "saiu da borda sem pular: nenhum som")
	await physics_frame
	await _tap(&"jump")
	_check(_count(CharacterSfx.EVENT_JUMP) == 1, "pulo pelo coyote time (2 ticks fora da borda): 1 som de pulo")
	await _wait_floor(terra)
	await _physics(10)

	print("-- Queda de uma borda")
	_teleport(terra, Vector2(LEDGE_RIGHT - 24, LEDGE_TOP))
	await _physics(10)
	_events.clear()
	Input.action_press(&"move_right")
	await _physics(40)
	Input.action_release(&"move_right")
	var vol := sfx.get_player(CharacterSfx.EVENT_LAND).volume_db
	_check(_count(CharacterSfx.EVENT_LAND) == 1 and _count(CharacterSfx.EVENT_JUMP) == 0, "queda de 32 px: 1 som de pouso, nenhum pulo")
	_check(vol > sfx.land_min_volume_db and vol < -1.0, "volume proporcional à queda (%.2f dB, entre %.1f e 0)" % [vol, sfx.land_min_volume_db])

	print("-- Reposicionamento")
	_events.clear()
	_teleport(terra, Vector2(300, FLOOR_Y - 30))
	await _physics(30)
	_check(_count(CharacterSfx.EVENT_LAND) == 0 and terra.is_on_floor(), "teleporte (interrupt_actions) e queda curta: nenhum pouso")
	_free(terra)


func _test_attack_and_ability() -> void:
	print("-- Golpe básico")
	var terra := await _spawn_terra(Vector2(300, FLOOR_Y))
	var melee := terra.get_node("MeleeAttack") as MeleeAttack
	var fist := terra.ability as SeismicFist
	_events.clear()
	await _tap(&"attack")
	_check(_count(CharacterSfx.EVENT_ATTACK) == 1 and melee.is_busy(), "golpe começou: 1 som")
	await _tap(&"attack")
	await _physics(5)
	await _tap(&"attack")
	_check(_count(CharacterSfx.EVENT_ATTACK) == 1, "apertos durante o golpe (rejeitados): nenhum som extra")
	await _physics(30)
	await _tap(&"attack")
	_check(_count(CharacterSfx.EVENT_ATTACK) == 2, "depois da recuperação: novo golpe, novo som")
	await _physics(30)

	print("-- Punho Sísmico")
	_events.clear()
	await _tap(&"ability")
	_check(fist.is_casting() and _count(CharacterSfx.EVENT_ABILITY) == 0, "na preparação: ainda sem som")
	await _tap(&"attack")
	_check(_count(CharacterSfx.EVENT_ATTACK) == 0, "golpe durante a preparação (rejeitado): nenhum som")
	var released_tick := -1
	for i in 30:
		await physics_frame
		if _count(CharacterSfx.EVENT_ABILITY) > 0 and released_tick < 0:
			released_tick = i
			_check(not fist.is_casting(), "som no tick da liberação da onda")
	_check(_count(CharacterSfx.EVENT_ABILITY) == 1, "liberação: exatamente 1 som (onda e física não duplicam)")
	await _tap(&"ability")
	await _physics(20)
	_check(_count(CharacterSfx.EVENT_ABILITY) == 1 and not fist.is_casting(), "em recarga (rejeitada): nenhum som")
	await _physics(90)  # fim da recarga de 1,5 s

	print("-- Punho Sísmico cancelado")
	_events.clear()
	await _tap(&"ability")
	_check(fist.is_casting(), "preparação começou")
	await _tap(&"jump")
	await _physics(30)
	_check(not fist.is_casting() and _count(CharacterSfx.EVENT_ABILITY) == 0, "preparação cancelada ao sair do chão: nenhum som de habilidade")
	await _wait_floor(terra)
	_free(terra)


func _test_damage_and_death() -> void:
	print("-- Dano")
	var terra := await _spawn_terra(Vector2(400, FLOOR_Y))
	var sfx := _sfx(terra)
	var hurtbox := terra.get_hurtbox()
	var health := terra.get_health()
	_events.clear()
	hurtbox.receive_hit(1)
	_check(_count(CharacterSfx.EVENT_HURT) == 1 and health.current_health == 4, "dano real: 1 som de dano")
	hurtbox.receive_hit(1)
	_check(_count(CharacterSfx.EVENT_HURT) == 1 and health.current_health == 4, "golpe na invulnerabilidade: nenhum som")
	await _physics(40)
	hurtbox.set_blocked(true)
	hurtbox.receive_hit(1)
	hurtbox.set_blocked(false)
	_check(_count(CharacterSfx.EVENT_HURT) == 1 and health.current_health == 4, "Hurtbox bloqueada (porta): nenhum som")
	hurtbox.receive_hit(0)
	_check(_count(CharacterSfx.EVENT_HURT) == 1, "golpe de dano 0: nenhum som")

	print("-- Golpe fatal")
	await _physics(40)
	hurtbox.receive_hit(9)
	_check(terra.is_dead() and _count(CharacterSfx.EVENT_DEATH) == 1 and _count(CharacterSfx.EVENT_HURT) == 1,
			"golpe fatal: só o som de morte (dano %d, morte %d)" % [_count(CharacterSfx.EVENT_HURT), _count(CharacterSfx.EVENT_DEATH)])
	var death_player := sfx.get_player(CharacterSfx.EVENT_DEATH)
	_check(death_player.playing, "som de morte tocando")
	Input.action_press(&"move_right")
	await _physics(30)
	await _tap(&"jump")
	await _tap(&"attack")
	await _tap(&"ability")
	Input.action_release(&"move_right")
	await _physics(40)
	hurtbox.receive_hit(1)
	health.take_damage(1)
	_check(_events.count(CharacterSfx.EVENT_DEATH) == 1 and _events.size() == 2,
			"morta: nenhum passo, pulo, golpe, habilidade, dano ou morte repetida (%s)" % str(_events))

	print("-- Morte com o mundo pausado")
	_free(terra)
	terra = await _spawn_terra(Vector2(600, FLOOR_Y))
	sfx = _sfx(terra)
	death_player = sfx.get_player(CharacterSfx.EVENT_DEATH)
	_events.clear()
	terra.get_health().take_damage(5)  # direto no HealthComponent: mesma ordem damaged -> died
	_check(_events == [CharacterSfx.EVENT_DEATH], "dano fatal direto no HealthComponent: só a morte")
	await _physics(10)
	paused = true
	var p0 := death_player.get_playback_position()
	await _frames(20)
	var p1 := death_player.get_playback_position()
	_check(death_player.playing and not death_player.stream_paused and p1 > p0, "pausado: o som de morte continua (%.2f -> %.2f s)" % [p0, p1])
	paused = false

	print("-- Renascimento")
	_events.clear()
	terra.revive()
	await _physics(20)
	_check(_events.is_empty(), "revive(): nenhum som (nem pouso)")
	_check(death_player.playing or sfx.get_death_sound_elapsed() < 0.0, "revive() não corta o som de morte")
	hurtbox = terra.get_hurtbox()
	await _physics(60)
	hurtbox.receive_hit(1)
	_check(_count(CharacterSfx.EVENT_HURT) == 1, "depois de renascer, o dano volta a tocar")
	hurtbox.receive_hit(0)
	await _physics(40)
	hurtbox.receive_hit(9)
	_check(_count(CharacterSfx.EVENT_DEATH) == 1, "segunda morte: morte toca de novo, uma vez")
	_free(terra)


# --- Fluxo real: Game ----------------------------------------------------------------------

func _test_game_flow() -> void:
	print("-- Game: início, transição, morte e retry")
	change_scene_to_file(GAME_PATH)
	await _frames(5)
	var game := current_scene
	if game == null or game.scene_file_path != GAME_PATH:
		_check(false, "Game carregada")
		return
	var terra: PlayerCharacter = game.get_terra()
	var sfx := _sfx(terra)
	_events.clear()
	sfx.sound_requested.connect(_on_sound)
	await _physics(40)
	_check(not _events.has(CharacterSfx.EVENT_LAND) and not _events.has(CharacterSfx.EVENT_FOOTSTEP), "início na Sala 01: nenhum pouso nem passo (%s)" % str(_events))

	# Transição andando de verdade: leva a Terra até a saída leste da Sala 01.
	var room_path: String = game.get_room_path()
	var exit_x := 960.0
	terra.global_position = Vector2(exit_x - 120, 320)
	terra.interrupt_actions()
	await _physics(10)
	_events.clear()
	var steps_during_fade := 0
	var landed_after := 0
	var disabled_seen := false
	Input.action_press(&"move_right")
	var swapped := false
	var prev_steps := 0
	for i in 240:
		await physics_frame
		var steps := _count(CharacterSfx.EVENT_FOOTSTEP)
		if terra.process_mode == Node.PROCESS_MODE_DISABLED:
			disabled_seen = true
			if steps > prev_steps:
				steps_during_fade += 1
		prev_steps = steps
		if game.get_room_path() != room_path:
			swapped = true
		if swapped and not game.is_transitioning():
			break
	Input.action_release(&"move_right")
	_events.clear()
	await _physics(30)
	landed_after = _count(CharacterSfx.EVENT_LAND)
	_check(swapped, "transição real para a sala seguinte")
	_check(disabled_seen and steps_during_fade == 0, "segurando a direção no fade (Terra desligada): nenhum passo")
	_check(landed_after == 0, "chegada na sala nova: nenhum pouso falso")

	# Morte e retry: o som de morte não pode ser cortado pela pausa, pelo fade nem pelo revive.
	var death_player := sfx.get_player(CharacterSfx.EVENT_DEATH)
	var go: GameOverScreen = game.get_game_over_screen()
	await _physics(10)
	_events.clear()
	terra.get_hurtbox().receive_hit(9)
	_check(_events == [CharacterSfx.EVENT_DEATH], "morte na Game: só o som de morte")
	var length := death_player.stream.get_length()
	var cut := false
	var retried := false
	var restarted := [false]
	game.attempt_restarted.connect(func(_a: int) -> void: restarted[0] = true, CONNECT_ONE_SHOT)
	var last_pos := 0.0
	while true:
		await process_frame
		var elapsed := sfx.get_death_sound_elapsed()
		if elapsed < 0.0:
			break  # o som chegou ao fim
		if elapsed < length - 0.05:
			if not death_player.playing or death_player.stream_paused:
				cut = true
			last_pos = maxf(last_pos, death_player.get_playback_position())
		# Retry o mais cedo possível (assim que o Game Over abre, sem esperar o atraso de
		# entrada): é o caminho mais curto até o renascimento.
		if not retried and go.is_open():
			retried = true
			_check(paused, "Game Over aberto com o mundo pausado durante o som de morte")
			go.retry_requested.emit()
	_check(retried, "retry pedido enquanto o som de morte tocava")
	_check(not cut, "som de morte tocou inteiro: pausa, fade, recriação da sala e revive não o cortaram (até %.2f de %.2f s)" % [last_pos, length])
	for i in 60:
		if restarted[0]:
			break
		await process_frame
	_check(restarted[0] and not terra.is_dead() and not paused, "retry concluído: Terra viva e mundo despausado")
	_check(_events.count(CharacterSfx.EVENT_DEATH) == 1 and _count(CharacterSfx.EVENT_HURT) == 0 and _count(CharacterSfx.EVENT_LAND) == 0,
			"no fluxo inteiro: morte uma vez, nenhum dano nem pouso falso (%s)" % str(_events))
	sfx.sound_requested.disconnect(_on_sound)


# --- Fluxo real: sala avulsa (SceneDeathController recarrega a cena) ------------------------

func _test_scene_restart_flow() -> void:
	print("-- Sala avulsa: cena recarregada no meio do som de morte")
	change_scene_to_file(TEST_ROOM_PATH)
	await _frames(5)
	var scene := current_scene
	var terra := scene.get_node("Terra") as PlayerCharacter
	var go := scene.get_node("GameOverScreen") as GameOverScreen
	var sfx := _sfx(terra)
	var death_stream: AudioStream = sfx.death_sound
	go.input_delay = 0.0  # força o recarregamento com o som de morte ainda tocando
	await _physics(20)
	terra.get_health().take_damage(5)
	for i in 120:
		await physics_frame
		if go.is_open():
			break
	await process_frame
	var elapsed_before := sfx.get_death_sound_elapsed()
	_check(go.is_open() and elapsed_before > 0.0, "Game Over aberto com a morte ainda tocando (%.2f s)" % elapsed_before)
	_accept()
	await _frames(6)
	var fresh := current_scene
	_check(fresh != null and fresh != scene, "cena recarregada (Terra antiga liberada)")
	var detached := _detached_players()
	_check(detached.size() == 1, "o som de morte continua num player avulso na raiz (%d)" % detached.size())
	if detached.size() == 1:
		var p := detached[0]
		_check(p.playing and p.process_mode == Node.PROCESS_MODE_ALWAYS and p.bus == &"SFX" and p.stream == death_stream,
				"player avulso: mesmo som, SFX, tocando")
		_check(p.get_playback_position() >= elapsed_before - 0.05, "continua do ponto em que estava (%.2f s >= %.2f s)" % [p.get_playback_position(), elapsed_before])
	var terra2 := fresh.get_node("Terra") as PlayerCharacter
	var sfx2 := _sfx(terra2)
	_events.clear()
	sfx2.sound_requested.connect(_on_sound)
	await create_timer(1.2).timeout
	_check(_detached_players().is_empty(), "player avulso se libera ao terminar")
	_check(_events.is_empty(), "Terra nova: nenhum som ao renascer (nem pouso)")
	sfx2.sound_requested.disconnect(_on_sound)

	print("-- Sala avulsa: fluxo com o atraso normal do Game Over")
	terra2.get_health().take_damage(5)
	var go2 := fresh.get_node("GameOverScreen") as GameOverScreen
	for i in 120:
		await physics_frame
		if go2.is_open():
			break
	var delay := go2.input_delay
	await create_timer(delay + 0.1, true).timeout
	var still := sfx2.get_death_sound_elapsed()
	_accept()
	await _frames(6)
	_check(current_scene != fresh, "recarregada de novo")
	var d2 := _detached_players()
	_check((still < 0.0 and d2.is_empty()) or (still >= 0.0 and d2.size() == 1),
			"atraso normal do Game Over (%.2f s): %s" % [delay,
			"o som já tinha terminado no recarregamento, nada a continuar" if still < 0.0 else "som ainda tocando, continuado no player avulso"])
	for p in d2:
		p.queue_free()


# --- Auxiliares ----------------------------------------------------------------------------

func _on_sound(event: StringName) -> void:
	_events.append(event)


func _expected_steps(dist: float, sfx: CharacterSfx) -> int:
	if dist < sfx.footstep_first_distance:
		return 0
	return 1 + int((dist - sfx.footstep_first_distance) / sfx.footstep_distance)


func _count(event: StringName) -> int:
	return _events.count(event)


func _sfx(terra: PlayerCharacter) -> CharacterSfx:
	return terra.get_node_or_null("Sfx") as CharacterSfx


func _detached_players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for child in root.get_children():
		if child is AudioStreamPlayer and String(child.name).begins_with(CharacterSfx.DETACHED_PLAYER_NAME) and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _accept() -> void:
	var down := InputEventAction.new()
	down.action = &"ui_accept"
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = &"ui_accept"
	Input.parse_input_event(up)


## Média dos intervalos entre os tempos (ms), ignorando os skip primeiros (aceleração).
func _mean_interval(times: Array[float], skip: int) -> float:
	if times.size() < skip + 2:
		return -1.0
	return (times[-1] - times[skip]) / (times.size() - 1 - skip)


## distance_mode: tira os quadros de contato antes do _ready (passos por distância).
func _spawn_terra(pos: Vector2, distance_mode: bool = false) -> PlayerCharacter:
	var terra := (load(TERRA_PATH) as PackedScene).instantiate() as PlayerCharacter
	terra.position = pos
	if distance_mode:
		_sfx(terra).footstep_contact_frames = PackedInt32Array()
	_events.clear()
	root.add_child(terra)
	_sfx(terra).sound_requested.connect(_on_sound)
	await _physics(20)
	return terra


func _free(terra: PlayerCharacter) -> void:
	_sfx(terra).sound_requested.disconnect(_on_sound)
	terra.queue_free()
	await process_frame
	for p in _detached_players():
		p.queue_free()


## Como a Game: reposiciona e interrompe tudo (o próximo contato com o chão não é pouso).
func _teleport(terra: PlayerCharacter, pos: Vector2) -> void:
	terra.global_position = pos
	terra.interrupt_actions()




func _make_level() -> void:
	_level.append(_box(Rect2(-2000, FLOOR_Y, 4000, 32)))
	_level.append(_box(Rect2(LEDGE_LEFT, LEDGE_TOP, LEDGE_RIGHT - LEDGE_LEFT, FLOOR_Y - LEDGE_TOP)))
	_level.append(_box(Rect2(WALL_X, FLOOR_Y - 200, 32, 200)))


func _clear_level() -> void:
	for n in _level:
		n.queue_free()
	_level.clear()


func _box(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = rect.size
	shape.shape = r
	shape.position = rect.get_center()
	body.add_child(shape)
	root.add_child(body)
	return body


func _wait_floor(terra: PlayerCharacter) -> void:
	for i in 120:
		await physics_frame
		if terra.is_on_floor():
			return


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


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
