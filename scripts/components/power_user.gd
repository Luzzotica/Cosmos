@tool
extends Node3D
class_name PowerUser
## Component that consumes power

signal power_consumed(amount: float)
signal power_state_changed(has_power: bool)

@export var use_power_cost: float = 5.0  # Power cost per use
@export var power_buffer_capacity: float = 15.0  # Internal buffer

var power_buffer: float = 0.0
var power_consumption: float = 0.0  # For tracking
var is_construction_user: bool = false  # True if this is a temporary construction power user


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_register_with_power_graph")


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_unregister_from_power_graph()


func _register_with_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.add_user(self)


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_user(self)


## Check if user has enough power to operate
var has_power: bool:
	get:
		return power_buffer >= use_power_cost


## Consume exactly `amount` power (draw from grid first if buffer low)
func consume_power_amount(amount: float) -> bool:
	if amount <= 0:
		return true
	draw_power_from_graph()
	if power_buffer >= amount:
		power_buffer -= amount
		power_consumption = amount
		power_consumed.emit(amount)
		draw_power_from_graph()
		return true
	return false


## Try to consume power for one use
func consume_power() -> bool:
	if power_buffer >= use_power_cost:
		power_buffer -= use_power_cost
		power_consumption = use_power_cost
		power_consumed.emit(use_power_cost)
		
		# Try to refill buffer from grid
		draw_power_from_graph()
		
		return true
	else:
		# Not enough in buffer, try to draw from grid
		draw_power_from_graph()
		
		if power_buffer >= use_power_cost:
			power_buffer -= use_power_cost
			power_consumption = use_power_cost
			power_consumed.emit(use_power_cost)
			return true
		
		return false


## Draw power from the grid into the buffer
func draw_power_from_graph() -> void:
	if not PowerGraphManager:
		return
	
	var needed: float = power_buffer_capacity - power_buffer
	if needed <= 0:
		return
	
	var drawn: float = PowerGraphManager.draw_power_for_user(self, needed)
	var old_has_power: bool = has_power
	power_buffer += drawn
	
	if old_has_power != has_power:
		power_state_changed.emit(has_power)


## Get buffer percentage (0.0 to 1.0)
func get_buffer_percentage() -> float:
	if power_buffer_capacity <= 0:
		return 0.0
	return power_buffer / power_buffer_capacity


## Manually add power to the buffer (for testing)
func add_power(amount: float) -> void:
	var old_has_power: bool = has_power
	power_buffer = minf(power_buffer + amount, power_buffer_capacity)
	if old_has_power != has_power:
		power_state_changed.emit(has_power)
