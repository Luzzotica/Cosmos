@tool
extends Resource
class_name WaveData
## Data class for enemy wave configuration

const EnemyWaveEntryClass: Script = preload("res://scripts/data/enemy_wave_entry.gd")

@export var wave_number: int = 0
@export var enemy_count: int = 3
@export var spawn_delay: float = 2.0
@export var enemy_health_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0
@export var enemy_composition: Array[Resource] = []

## Calculate scaled enemy health
func get_scaled_health(base_health: float) -> float:
	return base_health * enemy_health_multiplier

## Calculate scaled enemy speed
func get_scaled_speed(base_speed: float) -> float:
	return base_speed * enemy_speed_multiplier


func get_total_enemy_count() -> int:
	if enemy_composition.is_empty():
		return enemy_count
	var total: int = 0
	for entry in enemy_composition:
		if entry == null:
			continue
		if entry.get_script() != EnemyWaveEntryClass:
			continue
		total += maxi(int(entry.get("count")), 0)
	return total
