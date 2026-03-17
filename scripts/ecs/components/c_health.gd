class_name C_Health
extends Component
## ECS health component with damage logic, resistance, and signals.

signal health_changed(current_hp: float, maximum_hp: float)
signal damaged(amount: float)
signal destroyed

@export var current: float = 100.0
@export var maximum: float = 100.0
## Damage type -> multiplier (1.0 = normal, 0.0 = immune, <1.0 = resistant)
@export var resistance_profile: Dictionary = {}

var is_destroyed: bool:
	get: return current <= 0.0


func _init(p_max: float = 100.0, p_current: float = -1.0) -> void:
	maximum = p_max
	current = p_current if p_current >= 0.0 else p_max


func take_damage_event(event_payload: Dictionary) -> float:
	var amount: float = float(event_payload.get("amount", 0.0))
	if amount <= 0.0 or is_destroyed:
		return 0.0
	var damage_type: String = String(event_payload.get("damage_type", "generic"))
	var multiplier: float = get_damage_multiplier(damage_type)
	var actual_damage: float = amount * multiplier
	if actual_damage <= 0.0:
		return 0.0
	var was_alive: bool = current > 0.0
	current = maxf(current - actual_damage, 0.0)
	damaged.emit(actual_damage)
	health_changed.emit(current, maximum)
	if current <= 0.0 and was_alive:
		destroyed.emit()
	return actual_damage


func take_damage(amount: float) -> void:
	take_damage_event({"amount": amount, "damage_type": "generic"})


func heal(amount: float) -> void:
	if amount <= 0.0 or is_destroyed:
		return
	current = minf(current + amount, maximum)
	health_changed.emit(current, maximum)


func get_damage_multiplier(damage_type: String) -> float:
	if resistance_profile.has(damage_type):
		return maxf(float(resistance_profile[damage_type]), 0.0)
	return 1.0


func get_health_percentage() -> float:
	if maximum <= 0.0:
		return 0.0
	return current / maximum
