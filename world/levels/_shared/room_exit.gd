class_name RoomExit
extends Area2D
## Saída de sala: quando a Terra entra na área, pede a transição para outra sala. Não executa
## a troca (quem decide e carrega é a Game). Zona de gatilho: layer 0, mask player, monitorable
## desligado (configurado na cena da sala).
##
## O destino é um caminho em texto, não PackedScene: as salas se referenciam nos dois sentidos
## e um preload cíclico quebraria o carregamento.

signal transition_requested(target_room: String, target_entry: StringName)

## Cena da sala de destino.
@export_file("*.tscn") var target_room: String
## Entrada (Marker2D em Entrances) da sala de destino.
@export var target_entry: StringName


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		transition_requested.emit(target_room, target_entry)
