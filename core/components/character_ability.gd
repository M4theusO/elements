class_name CharacterAbility
extends Node
## Interface mínima da habilidade especial de um protagonista, acionada pelo PlayerCharacter
## (ação "ability"). Cada habilidade concreta fica em entities/characters/<nome>/abilities/
## e sobrescreve os métodos abaixo.


## Tenta iniciar a habilidade. Retorna se ela começou.
func try_activate() -> bool:
	return false


## Verdadeiro durante a preparação: o PlayerCharacter trava a direção e bloqueia o ataque básico.
func is_casting() -> bool:
	return false


## Interrompe a preparação sem efeito nem recarga (ex.: morte do personagem).
func cancel() -> void:
	pass
