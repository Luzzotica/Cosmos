@tool
extends Node3D
class_name HealthComponent
## Component that provides health and damage functionality

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal destroyed

@export var max_health: float = 100.0:
	set(value):
		max_health = value
		health = minf(health, max_health)
		health_changed.emit(health, max_health)

@export var health: float = 100.0:
	set(value):
		var old_health: float = health
		health = clampf(value, 0.0, max_health)
		health_changed.emit(health, max_health)
		
		if health <= 0 and old_health > 0:
			destroyed.emit()

var is_destroyed: bool:
	get:
		return health <= 0

var on_health_destroyed: Callable = Callable()


func _ready() -> void:
	if health <= 0:
		health = max_health


## Take damage
func take_damage(amount: float) -> void:
	if amount <= 0 or is_destroyed:
		return
	
	health -= amount
	damaged.emit(amount)
	
	if is_destroyed and on_health_destroyed.is_valid():
		on_health_destroyed.call()


## Heal
func heal(amount: float) -> void:
	if amount <= 0 or is_destroyed:
		return
	
	var actual_heal: float = minf(amount, max_health - health)
	health += actual_heal
	healed.emit(actual_heal)


## Get health percentage (0.0 to 1.0)
func get_health_percentage() -> float:
	if max_health <= 0:
		return 0.0
	return health / max_health


## Reset health to max
func reset() -> void:
	health = max_health
