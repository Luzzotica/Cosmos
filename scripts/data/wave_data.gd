@tool
extends Resource
class_name WaveData
## Data class for enemy wave configuration

@export var wave_number: int = 0
@export var enemy_count: int = 3
@export var spawn_delay: float = 2.0
@export var enemy_health_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0

## Calculate scaled enemy health
func get_scaled_health(base_health: float) -> float:
	return base_health * enemy_health_multiplier

## Calculate scaled enemy speed
func get_scaled_speed(base_speed: float) -> float:
	return base_speed * enemy_speed_multiplier
