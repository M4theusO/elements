class_name AttackData
extends Resource
## Dados de um golpe corpo a corpo: dano e duração de cada fase.
## Apenas dados: a lógica que os utiliza fica em MeleeAttack.

@export_range(0, 100, 1) var damage: int = 1
## Preparação: o golpe já começou, mas ainda não acerta.
@export_range(0.0, 1.0, 0.01, "suffix:s") var windup_time: float = 0.08
## Fase ativa: a Hitbox fica ligada e acerta os alvos.
@export_range(0.01, 1.0, 0.01, "suffix:s") var active_time: float = 0.1
## Recuperação: tempo até poder atacar de novo. Mínimo de ~1 tick para que a
## animação de ataque sempre recomece do primeiro quadro no golpe seguinte.
@export_range(0.02, 2.0, 0.01, "suffix:s") var recovery_time: float = 0.22
