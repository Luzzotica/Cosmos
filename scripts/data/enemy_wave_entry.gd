@tool
extends Resource
class_name EnemyWaveEntry
## Per-wave enemy composition entry.

@export var enemy_id: String = "enemy_standard"
@export var count: int = 1
@export var spawn_weight: float = 1.0


func sanitize() -> void:
	if enemy_id.strip_edges().is_empty():
		enemy_id = "enemy_standard"
	count = maxi(count, 0)
	spawn_weight = maxf(spawn_weight, 0.0)
