class_name CharacterStats
extends Resource
## Parâmetros de movimento e pulo de um protagonista.
## Apenas dados: a lógica que os utiliza fica em PlayerCharacter.
## Unidades em pixels (px) e segundos (s), na escala da viewport interna (640x360, tiles de 16 px).

## Menor jump_time_to_apex aceito (Inspector e cálculos de pulo).
const MIN_JUMP_TIME_TO_APEX: float = 0.05

@export_group("Movimento horizontal")
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var max_speed: float = 110.0
@export_range(0.0, 10000.0, 1.0, "suffix:px/s²") var ground_acceleration: float = 800.0
@export_range(0.0, 10000.0, 1.0, "suffix:px/s²") var ground_deceleration: float = 1000.0
@export_range(0.0, 10000.0, 1.0, "suffix:px/s²") var air_acceleration: float = 600.0
@export_range(0.0, 10000.0, 1.0, "suffix:px/s²") var air_deceleration: float = 400.0

@export_group("Pulo")
## Altura máxima do pulo (segurando o botão).
@export_range(1.0, 500.0, 1.0, "suffix:px") var jump_height: float = 56.0
## Tempo para atingir a altura máxima. Junto com jump_height, define a velocidade do pulo e a gravidade.
@export_range(MIN_JUMP_TIME_TO_APEX, 2.0, 0.01, "suffix:s") var jump_time_to_apex: float = 0.38
## Multiplica a gravidade durante a queda, deixando-a mais firme que a subida.
@export_range(1.0, 5.0, 0.05) var fall_gravity_multiplier: float = 1.6
## Fator aplicado à velocidade de subida ao soltar o pulo (pulo variável). 1.0 desativa o corte.
@export_range(0.0, 1.0, 0.05) var jump_cut_multiplier: float = 0.5
@export_range(0.0, 2000.0, 1.0, "suffix:px/s") var max_fall_speed: float = 360.0

@export_group("Tolerâncias")
## Tempo após sair de uma borda em que o pulo ainda é permitido.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time: float = 0.1
## Tempo em que um pulo apertado antes de tocar o chão fica guardado.
@export_range(0.0, 0.5, 0.01, "suffix:s") var jump_buffer_time: float = 0.1
