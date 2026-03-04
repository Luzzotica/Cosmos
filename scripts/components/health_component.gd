@tool
extends Node3D
class_name HealthComponent
## Component that provides health and damage functionality

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal damaged_event(payload: Dictionary)
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
var _resistance_profile: Dictionary = {}


func _ready() -> void:
	if health <= 0:
		health = max_health


## Take damage
func take_damage(amount: float) -> void:
	take_damage_event({
		"amount": amount,
		"damage_type": "generic",
		"source": null,
		"tags": PackedStringArray()
	})


func take_damage_event(event_payload: Dictionary) -> float:
	var amount: float = float(event_payload.get("amount", 0.0))
	if amount <= 0.0 or is_destroyed:
		return 0.0
	var damage_type: String = String(event_payload.get("damage_type", "generic"))
	var multiplier: float = get_damage_multiplier(damage_type)
	var actual_damage: float = amount * multiplier
	if actual_damage <= 0.0:
		damaged_event.emit({
			"amount": 0.0,
			"raw_amount": amount,
			"damage_type": damage_type,
			"multiplier": multiplier,
			"was_immune": true
		})
		return 0.0

	health -= actual_damage
	damaged.emit(actual_damage)
	damaged_event.emit({
		"amount": actual_damage,
		"raw_amount": amount,
		"damage_type": damage_type,
		"multiplier": multiplier,
		"was_immune": false
	})

	if is_destroyed and on_health_destroyed.is_valid():
		on_health_destroyed.call()
	return actual_damage


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


func set_resistance_profile(profile: Dictionary) -> void:
	_resistance_profile = {}
	for damage_type in profile.keys():
		_resistance_profile[String(damage_type)] = maxf(float(profile[damage_type]), 0.0)


func get_damage_multiplier(damage_type: String) -> float:
	if _resistance_profile.has(damage_type):
		return float(_resistance_profile[damage_type])
	return 1.0
