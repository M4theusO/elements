class_name CharacterSfx
extends Node2D
## Efeitos sonoros de um protagonista. Só ouve sinais (e lê o estado do personagem para os
## passos); a lógica de áudio não fica no PlayerCharacter. Cada personagem coloca um nó deste
## tipo na própria cena, com os próprios sons.
##
## Eventos:
##  - passos: só no chão, com deslocamento horizontal real (mesma regra da animação walk) e
##    viva. Dois modos:
##      * por quadro de contato (footstep_sprite + footstep_contact_frames preenchidos): toca
##        quando a animação footstep_animation chega a um desses quadros — som e pé sempre em
##        fase, inclusive com a walk acelerada/desacelerada pelo speed_scale;
##      * por distância (sem quadros de contato): um a cada footstep_distance px.
##    Alterna as variações sem repetir a anterior, com pitch e volume levemente aleatórios;
##  - pulo (PlayerCharacter.jumped), pouso (PlayerCharacter.landed, volume pela velocidade de
##    queda; quedas lentas não tocam), golpe (MeleeAttack.attack_started), habilidade
##    (CharacterAbility.activated), dano (HealthComponent.damaged) e morte
##    (HealthComponent.died).
##  - Golpe fatal: damaged chega antes de died, já com a vida em zero; dano que mata toca só a
##    morte (vale em qualquer ordem dos sinais, porque a decisão lê HealthComponent.is_dead()).
##
## Um AudioStreamPlayer2D por evento (filhos criados no _ready), para que um som não corte o
## outro; os passos usam polifonia 2. Os players rodam com PROCESS_MODE_ALWAYS: um som já
## começado termina mesmo com o mundo pausado (Game Over) ou com o personagem desligado (fade da
## troca de sala). A lógica deste nó herda o modo do personagem, então nenhum som novo é pedido
## enquanto ele está desligado ou pausado.
## Morte: se este nó sair da árvore com o som de morte tocando (ex.: a cena é recarregada no
## "Tentar novamente" do SceneDeathController), o som continua num AudioStreamPlayer avulso na
## raiz da árvore, a partir do mesmo ponto, e se libera ao terminar.

## Emitido a cada som efetivamente pedido (event = uma das constantes EVENT_*).
signal sound_requested(event: StringName)

const EVENT_FOOTSTEP: StringName = &"footstep"
const EVENT_JUMP: StringName = &"jump"
const EVENT_LAND: StringName = &"land"
const EVENT_ATTACK: StringName = &"attack"
const EVENT_ABILITY: StringName = &"ability"
const EVENT_HURT: StringName = &"hurt"
const EVENT_DEATH: StringName = &"death"
## Nome do player avulso que continua o som de morte fora do personagem.
const DETACHED_PLAYER_NAME: String = "DetachedCharacterSfx"
const FOOTSTEP_POLYPHONY: int = 2

## Personagem dono (vazio = o pai).
@export var character: PlayerCharacter
@export var melee_attack: MeleeAttack
## Vazia = character.get_health().
@export var health: HealthComponent
## Vazia = character.ability.
@export var ability: CharacterAbility
@export var bus: StringName = &"SFX"

@export_group("Sons")
@export var footsteps: Array[AudioStream] = []
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
@export var attack_sound: AudioStream
@export var ability_sound: AudioStream
@export var hurt_sound: AudioStream
@export var death_sound: AudioStream

@export_group("Volumes")
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var footstep_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var jump_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var land_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var attack_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var ability_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var hurt_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var death_volume_db: float = 0.0

@export_group("Passos")
## Sprite cuja animação marca os passos (modo por quadro de contato).
@export var footstep_sprite: AnimatedSprite2D
@export var footstep_animation: StringName = &"walk"
## Quadros da footstep_animation em que o pé toca o chão. Vazio = modo por distância.
@export var footstep_contact_frames: PackedInt32Array = PackedInt32Array()
## Depois de um som de pouso, contatos dentro deste tempo não tocam passo (o pouso já é o
## contato; ao pousar andando, a walk recomeça e chega ao contato logo em seguida).
@export_range(0.0, 1.0, 0.01, "suffix:s") var footstep_land_grace: float = 0.2
## Modo por distância: distância percorrida no chão entre dois passos.
@export_range(4.0, 128.0, 1.0, "suffix:px") var footstep_distance: float = 32.0
## Modo por distância: até o primeiro passo quando a personagem começa a andar (ou pousa andando).
@export_range(0.0, 128.0, 1.0, "suffix:px") var footstep_first_distance: float = 12.0
## Variação aleatória de pitch (fração: 0,06 = ±6%).
@export_range(0.0, 0.5, 0.01) var footstep_pitch_variation: float = 0.06
@export_range(0.0, 6.0, 0.1, "suffix:dB") var footstep_volume_variation_db: float = 1.5

@export_group("Pouso")
## Abaixo desta velocidade de queda o pouso não toca (degraus mínimos, chegada numa sala).
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var land_min_speed: float = 120.0
## A partir desta velocidade, volume cheio (land_volume_db).
@export_range(1.0, 1000.0, 1.0, "suffix:px/s") var land_full_speed: float = 360.0
## Atenuação do pouso na velocidade mínima.
@export_range(-30.0, 0.0, 0.5, "suffix:dB") var land_min_volume_db: float = -9.0

var _players: Dictionary[StringName, AudioStreamPlayer2D] = {}
var _step_distance_left: float = 0.0
var _land_grace_left: float = 0.0
var _last_footstep: int = -1
var _rng := RandomNumberGenerator.new()
## Início do som de morte (Time.get_ticks_usec), ou -1 sem morte tocando.
var _death_started_usec: int = -1


func _ready() -> void:
	# Depois do personagem no mesmo tick: os passos leem o resultado do move_and_slide().
	process_physics_priority = 1
	if character == null:
		character = get_parent() as PlayerCharacter
	if character == null:
		push_warning("%s: sem PlayerCharacter; nenhum som será tocado." % name)
		set_physics_process(false)
		return
	if health == null:
		health = character.get_health()
	if ability == null:
		ability = character.ability
	var bus_name: StringName = bus
	if AudioServer.get_bus_index(bus) < 0:
		push_warning("%s: barramento '%s' não existe; usando Master." % [name, bus])
		bus_name = &"Master"
	_make_player(EVENT_FOOTSTEP, null, bus_name, FOOTSTEP_POLYPHONY)
	_make_player(EVENT_JUMP, jump_sound, bus_name)
	_make_player(EVENT_LAND, land_sound, bus_name)
	_make_player(EVENT_ATTACK, attack_sound, bus_name)
	_make_player(EVENT_ABILITY, ability_sound, bus_name)
	_make_player(EVENT_HURT, hurt_sound, bus_name)
	_make_player(EVENT_DEATH, death_sound, bus_name)
	character.jumped.connect(_on_jumped)
	character.landed.connect(_on_landed)
	if melee_attack != null:
		melee_attack.attack_started.connect(_play.bind(EVENT_ATTACK, attack_volume_db))
	if ability != null:
		ability.activated.connect(_play.bind(EVENT_ABILITY, ability_volume_db))
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if uses_contact_frames():
		footstep_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_reset_footsteps()


func _physics_process(delta: float) -> void:
	_land_grace_left = maxf(_land_grace_left - delta, 0.0)
	if uses_contact_frames():
		return
	if not _can_step():
		_reset_footsteps()
		return
	var speed: float = absf(character.get_real_velocity().x)
	_step_distance_left -= speed * delta
	if _step_distance_left <= 0.0:
		_step_distance_left += footstep_distance
		_play_footstep()


## Os filhos saem da árvore antes do pai: aqui o player de morte já parou. Por isso a posição
## vem do relógio desde o início da morte (o player toca em PROCESS_MODE_ALWAYS e com pitch 1,
## então o tempo real decorrido é a posição no som, inclusive com o mundo pausado).
func _exit_tree() -> void:
	var position_s: float = get_death_sound_elapsed()
	if position_s < 0.0 or not is_inside_tree():
		return
	var death_player: AudioStreamPlayer2D = _players[EVENT_DEATH]
	if position_s >= death_player.stream.get_length():
		return
	# O personagem está saindo da árvore com a morte tocando: o som continua fora dele.
	_continue_detached.call_deferred(get_tree(), death_player.stream, position_s,
			death_player.volume_db, death_player.bus)


func get_player(event: StringName) -> AudioStreamPlayer2D:
	return _players.get(event)


func _make_player(event: StringName, stream: AudioStream, bus_name: StringName, polyphony: int = 1) -> void:
	var player := AudioStreamPlayer2D.new()
	player.name = "%sPlayer" % String(event).capitalize().replace(" ", "")
	player.stream = stream
	player.bus = bus_name
	player.max_polyphony = polyphony
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	_players[event] = player


func _play(event: StringName, volume_db: float, pitch: float = 1.0) -> void:
	var player: AudioStreamPlayer2D = _players.get(event)
	if player == null or player.stream == null:
		return
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	sound_requested.emit(event)


func _play_footstep() -> void:
	if footsteps.is_empty():
		return
	var index: int = _rng.randi_range(0, footsteps.size() - 1)
	if footsteps.size() > 1 and index == _last_footstep:
		index = (index + 1 + _rng.randi_range(0, footsteps.size() - 2)) % footsteps.size()
	_last_footstep = index
	_players[EVENT_FOOTSTEP].stream = footsteps[index]
	var pitch: float = 1.0 + _rng.randf_range(-footstep_pitch_variation, footstep_pitch_variation)
	var volume: float = footstep_volume_db + _rng.randf_range(-footstep_volume_variation_db, footstep_volume_variation_db)
	_play(EVENT_FOOTSTEP, volume, pitch)


## Índice da última variação de passo tocada (-1 = nenhuma ainda).
func get_last_footstep_index() -> int:
	return _last_footstep


## Verdadeiro no modo por quadro de contato.
func uses_contact_frames() -> bool:
	return footstep_sprite != null and not footstep_contact_frames.is_empty()


## Passo só no chão, deslocando de verdade e viva (mesma regra da animação walk).
func _can_step() -> bool:
	return not character.is_dead() and character.is_on_floor() \
			and absf(character.get_real_velocity().x) > PlayerCharacter.WALK_SPEED_THRESHOLD


## A AnimatedSprite2D avança os quadros no _process; desligada (troca de sala) ou pausada, não
## avança e não emite frame_changed.
func _on_sprite_frame_changed() -> void:
	if footstep_sprite.animation != footstep_animation or not footstep_contact_frames.has(footstep_sprite.frame):
		return
	if _land_grace_left > 0.0 or not _can_step():
		return
	_play_footstep()


func _reset_footsteps() -> void:
	_step_distance_left = footstep_first_distance


func _on_jumped() -> void:
	_play(EVENT_JUMP, jump_volume_db)


func _on_landed(fall_speed: float) -> void:
	_reset_footsteps()
	if fall_speed < land_min_speed:
		return
	var weight: float = clampf(inverse_lerp(land_min_speed, maxf(land_full_speed, land_min_speed + 1.0), fall_speed), 0.0, 1.0)
	_play(EVENT_LAND, land_volume_db + lerpf(land_min_volume_db, 0.0, weight))
	_land_grace_left = footstep_land_grace


func _on_damaged(_amount: int) -> void:
	# Golpe fatal: a vida já está em zero quando damaged chega; só a morte toca.
	if health.is_dead():
		return
	_play(EVENT_HURT, hurt_volume_db)


## HealthComponent.died é emitido uma única vez por vida.
func _on_died() -> void:
	var player: AudioStreamPlayer2D = _players[EVENT_DEATH]
	if player.stream == null:
		return
	_death_started_usec = Time.get_ticks_usec()
	_play(EVENT_DEATH, death_volume_db)


## Segundos desde o início do som de morte, ou -1 se não houve morte ou se o som já acabou.
func get_death_sound_elapsed() -> float:
	if _death_started_usec < 0:
		return -1.0
	var elapsed: float = (Time.get_ticks_usec() - _death_started_usec) / 1000000.0
	var stream: AudioStream = _players[EVENT_DEATH].stream
	if stream == null or elapsed >= stream.get_length():
		return -1.0
	return elapsed


## Continua um som num player avulso na raiz (não posicional: o personagem não existe mais).
static func _continue_detached(tree: SceneTree, stream: AudioStream, from_position: float, volume_db: float, bus_name: StringName) -> void:
	if tree == null or tree.root == null or stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = DETACHED_PLAYER_NAME
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.finished.connect(player.queue_free)
	tree.root.add_child(player, true)
	player.play(from_position)
